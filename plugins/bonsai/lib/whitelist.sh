#!/usr/bin/env bash
# Project whitelist management.
# State lives at $CLAUDE_PLUGIN_DATA/projects.json.

[[ -n "${_BONSAI_WHITELIST_SOURCED:-}" ]] && return 0
_BONSAI_WHITELIST_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_whitelist_file() {
  printf '%s/projects.json' "${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}"
}

_bonsai_whitelist_init_if_missing() {
  local file
  file="$(_bonsai_whitelist_file)"
  [[ -f "$file" ]] && return 0
  bonsai_ensure_dir "$(dirname "$file")" || return 1
  # Use bonsai_json_write for atomicity (consistent with the rest of the module).
  bonsai_json_write "$file" '{"__version":1,"tended":[]}'
}

# Exit 0 if cwd is tended, 1 otherwise. Corruption → 1 (silent skip).
bonsai_whitelist_is_tended() {
  local cwd="$1"
  local file
  file="$(_bonsai_whitelist_file)"
  [[ -f "$file" ]] || return 1
  local hit
  hit="$(jq -r --arg p "$cwd" '.tended | index($p) // empty' "$file" 2>/dev/null)"
  [[ -n "$hit" ]]
}

bonsai_whitelist_add() {
  local path="$1"
  _bonsai_whitelist_init_if_missing || return 1
  local file
  file="$(_bonsai_whitelist_file)"
  # NOTE: read-modify-write is not atomic across concurrent processes.
  # Two simultaneous /bonsai:start calls in the same project could lose one
  # add. Acceptable for v1 — user-invoked, rare concurrency. See design §9.
  local updated
  updated="$(jq --arg p "$path" '
    if (.tended | index($p)) then .
    else .tended += [$p]
    end' "$file" 2>/dev/null)"
  if [[ -z "$updated" ]]; then
    bonsai_log ERROR "whitelist_add: corrupt projects.json at $file"
    return 1
  fi
  bonsai_json_write "$file" "$updated"
}

bonsai_whitelist_remove() {
  local path="$1"
  local file
  file="$(_bonsai_whitelist_file)"
  [[ -f "$file" ]] || return 0
  local updated
  updated="$(jq --arg p "$path" '.tended -= [$p]' "$file" 2>/dev/null)"
  if [[ -z "$updated" ]]; then
    # Corrupt JSON: log loudly. /bonsai:stop is user-invoked; the spec's
    # silent-failure rule applies to background hooks, not to a command the
    # user just typed asking us to stop watching.
    bonsai_log ERROR "whitelist_remove: corrupt projects.json at $file"
    return 1
  fi
  bonsai_json_write "$file" "$updated"
}

bonsai_whitelist_list() {
  local file
  file="$(_bonsai_whitelist_file)"
  [[ -f "$file" ]] || return 0
  jq -r '.tended[]' "$file" 2>/dev/null || true
}
