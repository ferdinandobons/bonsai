#!/usr/bin/env bash
# Per-project mute (sleep/wake).
# State file: $CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json
# Schema: {"__version":1, "mute_until_epoch":<int>}

[[ -n "${_BONSAI_MUTE_SOURCED:-}" ]] && return 0
_BONSAI_MUTE_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_mute_file() {
  local project_dir="$1"
  printf '%s/.claude/bonsai/mute.json' "$project_dir"
}

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

bonsai_mute_sleep() {
  local project_dir="$1"
  local duration="$2"
  local secs
  secs="$(bonsai_mute_parse_duration "$duration")" || return 1
  local until=$(( $(date -u +%s) + secs ))
  local file
  file="$(_bonsai_mute_file "$project_dir")"
  bonsai_ensure_dir "$(dirname "$file")" || return 1
  jq -n --argjson u "$until" '{"__version":1,"mute_until_epoch":$u}' > "$file"
}

bonsai_mute_wake() {
  local project_dir="$1"
  local file
  file="$(_bonsai_mute_file "$project_dir")"
  rm -f "$file"
}

# Exit 0 if muted, 1 otherwise. Expired → 1.
bonsai_mute_is_muted() {
  local project_dir="$1"
  local file
  file="$(_bonsai_mute_file "$project_dir")"
  [[ -f "$file" ]] || return 1
  local until
  until="$(jq -r '.mute_until_epoch // 0' "$file" 2>/dev/null)"
  [[ -z "$until" || "$until" == "null" ]] && return 1
  local now
  now="$(date -u +%s)"
  [[ "$now" -lt "$until" ]]
}

bonsai_mute_remaining_seconds() {
  local project_dir="$1"
  local file
  file="$(_bonsai_mute_file "$project_dir")"
  [[ -f "$file" ]] || { printf '0'; return 0; }
  local until
  until="$(jq -r '.mute_until_epoch // 0' "$file" 2>/dev/null)"
  local now
  now="$(date -u +%s)"
  local rem=$(( until - now ))
  [[ "$rem" -lt 0 ]] && rem=0
  printf '%d' "$rem"
}
