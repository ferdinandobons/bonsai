#!/usr/bin/env bash
# Push notification helper. Formats payload + enforces hourly rate limit.

[[ -n "${_BONSAI_PUSH_SOURCED:-}" ]] && return 0
_BONSAI_PUSH_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/quota.sh"

_BONSAI_PUSH_HOURLY_CAP_DEFAULT=5

# Resolve hourly cap from per-project config.json (falls back to default).
_bonsai_push_hourly_cap() {
  local project_dir="$1"
  local cfg="$project_dir/.claude/bonsai/config.json"
  local cap="$_BONSAI_PUSH_HOURLY_CAP_DEFAULT"
  if [[ -f "$cfg" ]]; then
    local v
    v="$(bonsai_json_get "$cfg" '.push_notifications_per_hour')"
    [[ "$v" =~ ^[0-9]+$ ]] && cap="$v"
  fi
  printf '%s' "$cap"
}

bonsai_push_format() {
  local obs="$1"
  local title=""
  if ! title="$(printf '%s' "$obs" | jq -r '.title' 2>/dev/null)"; then
    bonsai_log ERROR "push_format: failed to extract title"
    return 1
  fi
  if [[ -z "$title" || "$title" == "null" ]]; then
    bonsai_log ERROR "push_format: missing title"
    return 1
  fi
  local project="${CLAUDE_PROJECT_DIR:-unknown}"
  local proj_name; proj_name="$(basename "$project")"
  # Build body inside jq so the title can't break out of the body string
  # (e.g. newlines, quotes from LLM-generated titles).
  jq -n --arg t "Bonsai · ${proj_name}" --arg title "$title" \
    '{title:$t, body:("Critical observation: " + $title + " — open the chip to fix.")}'
}

# Exit 0 if a push is allowed for this project in the last hour, 1 otherwise.
bonsai_push_rate_ok() {
  local project_dir="$1"
  local file="${CLAUDE_PLUGIN_DATA}/quota.json"
  [[ -f "$file" ]] || return 0
  local now; now="$(date -u +%s)"
  local cutoff=$(( now - 3600 ))
  local n=""
  if ! n="$(jq -r --arg s "$project_dir" --argjson c "$cutoff" \
    '[.events[] | select(.kind=="push" and .scope==$s and .epoch>=$c)] | length' \
    "$file" 2>/dev/null)"; then
    n=0
  fi
  [[ -z "$n" || "$n" == "null" ]] && n=0
  local cap; cap="$(_bonsai_push_hourly_cap "$project_dir")"
  [[ "$n" -lt "$cap" ]]
}
