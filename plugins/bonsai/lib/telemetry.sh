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
