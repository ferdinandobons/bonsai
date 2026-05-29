#!/usr/bin/env bash
# Read-only telemetry over the per-run gardener logs.
#
# Each gardener-<ts>.log is the `claude -p --output-format json` result object.
# The fields that matter for "is the gardener healthy / is --max-turns enough":
#   - subtype:   "success" | "error_max_turns" | "error_during_execution" | ...
#   - num_turns: turns the gardener actually used
# (The top-level stop_reason is the last API message's reason — "end_turn" — and
# does NOT indicate the run hit the turn cap; subtype does.)

[[ -n "${_BONSAI_TELEMETRY_SOURCED:-}" ]] && return 0
_BONSAI_TELEMETRY_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

# Aggregate gardener run stats. Prints one line:
#   "<total> <completed> <errored> <max_turns> <peak_turns>"
# Args:
#   $1 - log_dir (defaults to $CLAUDE_PLUGIN_DATA/logs)
#   $2 - cutoff_ts (optional, "YYYYMMDDTHHMMSSZ"): ignore logs older than this,
#        compared lexically against the timestamp in the filename.
bonsai_telemetry_gardener_stats() {
  local log_dir="${1:-${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}/logs}"
  local cutoff="${2:-}"
  local total=0 completed=0 errored=0 max_turns=0 peak=0
  if [[ -d "$log_dir" ]]; then
    local log fname ts subtype turns
    shopt -s nullglob
    for log in "$log_dir/"gardener-*.log; do
      [[ -f "$log" ]] || continue
      fname="$(basename "$log")"
      ts="${fname#gardener-}"
      ts="${ts%.log}"
      # Lexical timestamp comparison (ISO basic format sorts correctly).
      if [[ -n "$cutoff" && "$ts" < "$cutoff" ]]; then continue; fi
      total=$((total + 1))
      subtype="$(jq -r '.subtype // "error"' "$log" 2>/dev/null || printf 'error')"
      if [[ "$subtype" == "success" ]]; then
        completed=$((completed + 1))
      else
        errored=$((errored + 1))
        [[ "$subtype" == "error_max_turns" ]] && max_turns=$((max_turns + 1))
      fi
      turns="$(jq -r '.num_turns // 0' "$log" 2>/dev/null || printf '0')"
      [[ "$turns" =~ ^[0-9]+$ ]] || turns=0
      (( turns > peak )) && peak="$turns"
    done
    shopt -u nullglob
  fi
  printf '%s %s %s %s %s' "$total" "$completed" "$errored" "$max_turns" "$peak"
}

# List recent gardener execution errors, most recent last. Prints one line per
# errored run:
#   "<ts> <subtype>: <message>"
# A run counts as errored when its result subtype is not "success", or when the
# log can't be parsed at all (claude died mid-write — a real execution failure
# that would otherwise be invisible). The message is pulled from .result/.error
# when present, newline-flattened and truncated so a long stack can't blow up the
# status block.
# Args:
#   $1 - log_dir (defaults to $CLAUDE_PLUGIN_DATA/logs)
#   $2 - cutoff_ts (optional, "YYYYMMDDTHHMMSSZ"): same lexical-compare semantics
#        as the other telemetry helpers.
#   $3 - max lines to print (default 5).
bonsai_telemetry_gardener_errors() {
  local log_dir="${1:-${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}/logs}"
  local cutoff="${2:-}"
  local max="${3:-5}"
  [[ "$max" =~ ^[0-9]+$ ]] || max=5
  [[ -d "$log_dir" ]] || return 0
  # bash 3.2 (the macOS system bash) errors on `"${arr[@]}"` for an empty array
  # under set -u, and a caller may have it set — keep an explicit empty guard.
  local lines=() log fname ts subtype msg
  shopt -s nullglob
  for log in "$log_dir/"gardener-*.log; do
    [[ -f "$log" ]] || continue
    fname="$(basename "$log")"; ts="${fname#gardener-}"; ts="${ts%.log}"
    if [[ -n "$cutoff" && "$ts" < "$cutoff" ]]; then continue; fi
    subtype="$(jq -r '.subtype // empty' "$log" 2>/dev/null)"
    if [[ -z "$subtype" ]]; then
      # Unparseable / partial log: surface the first non-blank line as the clue.
      subtype="unparseable"
      msg="$(tr -d '\r' < "$log" 2>/dev/null | grep -m1 -v '^[[:space:]]*$' | cut -c1-160)"
    elif [[ "$subtype" == "success" ]]; then
      continue
    else
      msg="$(jq -r '(.result // .error // "") | tostring' "$log" 2>/dev/null | tr '\n' ' ' | cut -c1-160)"
    fi
    lines+=("$ts $subtype: $msg")
  done
  shopt -u nullglob
  [[ ${#lines[@]} -eq 0 ]] && return 0
  # Filenames already sort by ts, but sort explicitly so the oldest-first / tail
  # contract holds regardless of glob order, then keep the most recent $max.
  printf '%s\n' "${lines[@]}" | sort | tail -n "$max"
}

# Sum token usage across gardener logs in the window. Prints one line:
#   "<input> <cache_read> <cache_creation> <output>"
# Same args/cutoff semantics as bonsai_telemetry_gardener_stats.
bonsai_telemetry_token_usage() {
  local log_dir="${1:-${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}/logs}"
  local cutoff="${2:-}"
  local ti=0 tcr=0 tcw=0 to=0
  if [[ -d "$log_dir" ]]; then
    local log fname ts vals i cr cw o
    shopt -s nullglob
    for log in "$log_dir/"gardener-*.log; do
      [[ -f "$log" ]] || continue
      fname="$(basename "$log")"; ts="${fname#gardener-}"; ts="${ts%.log}"
      if [[ -n "$cutoff" && "$ts" < "$cutoff" ]]; then continue; fi
      # One jq pass per log emits the four buckets (0 when absent).
      vals="$(jq -r '.usage | "\(.input_tokens // 0) \(.cache_read_input_tokens // 0) \(.cache_creation_input_tokens // 0) \(.output_tokens // 0)"' "$log" 2>/dev/null || printf '0 0 0 0')"
      read -r i cr cw o <<< "$vals"
      [[ "$i"  =~ ^[0-9]+$ ]] && ti=$((ti + i))
      [[ "$cr" =~ ^[0-9]+$ ]] && tcr=$((tcr + cr))
      [[ "$cw" =~ ^[0-9]+$ ]] && tcw=$((tcw + cw))
      [[ "$o"  =~ ^[0-9]+$ ]] && to=$((to + o))
    done
    shopt -u nullglob
  fi
  printf '%s %s %s %s' "$ti" "$tcr" "$tcw" "$to"
}
