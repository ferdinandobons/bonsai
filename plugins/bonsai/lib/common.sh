#!/usr/bin/env bash
# Shared helpers for bonsai. Sourced by all other lib/*.sh and by stop.sh.
# Safe to source multiple times.

[[ -n "${_BONSAI_COMMON_SOURCED:-}" ]] && return 0
_BONSAI_COMMON_SOURCED=1

# We deliberately do NOT enable `set -o pipefail` at module scope: sourcing
# must not change the caller's shell options. Bonsai must never disturb the
# session, and pipefail in stop.sh could turn a SIGPIPE on a downstream tool
# into a non-zero hook exit, which Claude Code would surface. Apply pipefail
# locally inside subshells when needed:
#   ( set -o pipefail; cmd1 | cmd2 )

# Current time in ISO-8601 UTC (e.g. "2026-05-27T21:18:00Z").
bonsai_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Ensure a directory exists. Silent on success.
bonsai_ensure_dir() {
  local dir="$1"
  [[ -z "$dir" ]] && return 1
  mkdir -p "$dir" 2>/dev/null || return 1
}

# Append a log line. Levels: INFO, WARN, ERROR.
# Errors are duplicated to bonsai-errors.log.
bonsai_log() {
  local level="$1"
  shift
  local msg="$*"
  local data_dir="${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}"
  bonsai_ensure_dir "$data_dir/logs" || return 0
  local ts
  ts="$(bonsai_now_iso)"
  printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$data_dir/logs/bonsai.log"
  if [[ "$level" == "ERROR" ]]; then
    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$data_dir/logs/bonsai-errors.log"
  fi
  return 0
}

# Silent exit 0 with optional log message. Used by gatekeeper checks.
bonsai_silent_exit() {
  local reason="${1:-no reason}"
  bonsai_log INFO "silent_exit: $reason"
  exit 0
}

# Read JSON value at jq path. Returns empty string on error.
bonsai_json_get() {
  local file="$1"
  local path="$2"
  [[ -f "$file" ]] || { printf ''; return 0; }
  jq -r "$path // empty" "$file" 2>/dev/null || printf ''
}

# Write a JSON file atomically (write to a unique tmp then mv).
# Uses mktemp instead of $$ because $$ does not change across subshells —
# two concurrent command substitutions would collide and silently lose data.
bonsai_json_write() {
  local file="$1"
  local content="$2"
  local dir
  dir="$(dirname "$file")"
  bonsai_ensure_dir "$dir" || return 1
  local tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  printf '%s' "$content" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  return 0
}

# Slugify a string for use as filename segment.
# Lowercase, replace non-alphanumerics with dashes, trim, max 40 chars.
# Empty / all-special input → "untitled" so callers never produce filenames
# like "2026-05-27-001-.md".
bonsai_slugify() {
  local s="$1"
  local out
  out="$(
    printf '%s' "$s" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
      | cut -c1-40
  )"
  if [[ -z "$out" ]]; then
    printf 'untitled'
  else
    printf '%s' "$out"
  fi
}
