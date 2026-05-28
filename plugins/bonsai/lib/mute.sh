#!/usr/bin/env bash
# Per-project mute (mute/unmute).
# State file: $CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json
# Schema: {"__version":1, "mute_until_epoch":<int>}

[[ -n "${_BONSAI_MUTE_SOURCED:-}" ]] && return 0
_BONSAI_MUTE_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_mute_file()        { printf '%s/.claude/bonsai/mute.json' "$1"; }
_bonsai_mute_global_file() { printf '%s/mute.json' "${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}"; }

# Parse a duration like 30m, 1h, 4h, 1d → seconds on stdout. Invalid → exit 1.
bonsai_mute_parse_duration() {
  local d="$1"
  [[ -z "$d" ]] && return 1
  if [[ "$d" =~ ^([0-9]+)([mhd])$ ]]; then
    local n="${BASH_REMATCH[1]}"
    local u="${BASH_REMATCH[2]}"
    case "$u" in
      m) printf '%d' $((n * 60)) ;;
      h) printf '%d' $((n * 3600)) ;;
      d) printf '%d' $((n * 86400)) ;;
    esac
    return 0
  fi
  return 1
}

# --- shared file-level primitives (project + global wrappers delegate here) ---

# Read mute_until_epoch from a file; prints 0 for missing/corrupt/expired-absent.
_bonsai_mute_until() {
  local file="$1"
  [[ -f "$file" ]] || { printf '0'; return 0; }
  local until; until="$(jq -r '.mute_until_epoch // 0' "$file" 2>/dev/null)"
  [[ "$until" =~ ^[0-9]+$ ]] || until=0
  printf '%s' "$until"
}

# Exit 0 if the file indicates an active (non-expired) mute.
_bonsai_mute_is_muted_file() {
  local until; until="$(_bonsai_mute_until "$1")"
  [[ "$until" -ne 0 && "$(date -u +%s)" -lt "$until" ]]
}

# Write a mute expiring `duration` from now into the file.
_bonsai_mute_sleep_file() {
  local file="$1" duration="$2"
  local secs; secs="$(bonsai_mute_parse_duration "$duration")" || return 1
  local until=$(( $(date -u +%s) + secs ))
  bonsai_ensure_dir "$(dirname "$file")" || return 1
  local content; content="$(jq -n --argjson u "$until" '{"__version":1,"mute_until_epoch":$u}')" || return 1
  bonsai_json_write "$file" "$content"
}

# --- per-project mute (state: $CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json) ---

bonsai_mute_sleep()    { _bonsai_mute_sleep_file "$(_bonsai_mute_file "$1")" "$2"; }
bonsai_mute_wake()     { rm -f "$(_bonsai_mute_file "$1")"; }
bonsai_mute_is_muted() { _bonsai_mute_is_muted_file "$(_bonsai_mute_file "$1")"; }

# --- global mute ($CLAUDE_PLUGIN_DATA/mute.json) — silences all watched projects ---

bonsai_mute_sleep_global()    { _bonsai_mute_sleep_file "$(_bonsai_mute_global_file)" "$1"; }
bonsai_mute_wake_global()     { rm -f "$(_bonsai_mute_global_file)"; }
bonsai_mute_is_muted_global() { _bonsai_mute_is_muted_file "$(_bonsai_mute_global_file)"; }

# Seconds left on the per-project mute (0 if not muted / expired / corrupt).
bonsai_mute_remaining_seconds() {
  local until; until="$(_bonsai_mute_until "$(_bonsai_mute_file "$1")")"
  local rem=$(( until - $(date -u +%s) ))
  [[ "$rem" -lt 0 ]] && rem=0
  printf '%d' "$rem"
}
