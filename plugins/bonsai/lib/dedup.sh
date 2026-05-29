#!/usr/bin/env bash
# Observation deduplication: sha256 hash + rolling array in state.json.

[[ -n "${_BONSAI_DEDUP_SOURCED:-}" ]] && return 0
_BONSAI_DEDUP_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_BONSAI_DEDUP_WINDOW=50

_bonsai_dedup_normalize() {
  local s="$1"
  printf '%s' "$s" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Compute sha256 over normalized "title|evidence_ref".
bonsai_dedup_hash() {
  local title="$1"
  local evidence="$2"
  local n_title n_ev
  n_title="$(_bonsai_dedup_normalize "$title")"
  n_ev="$(_bonsai_dedup_normalize "$evidence")"
  printf '%s|%s' "$n_title" "$n_ev" | bonsai_sha256
}

# Exit 0 if hash is in the rolling array, 1 otherwise (or on corrupt state).
bonsai_dedup_contains() {
  local project_dir="$1"
  local hash="$2"
  local file; file="$(bonsai_state_file "$project_dir")"
  [[ -f "$file" ]] || return 1
  local present=""
  if ! present="$(jq -r --arg h "$hash" '.dedup_hashes // [] | index($h) // empty' "$file" 2>/dev/null)"; then
    return 1
  fi
  [[ -n "$present" ]]
}

bonsai_dedup_add() {
  local project_dir="$1"
  local hash="$2"
  local file; file="$(bonsai_state_file "$project_dir")"
  bonsai_ensure_dir "$(dirname "$file")" || return 1
  if [[ ! -f "$file" ]]; then
    # Guard the init jq just like the update path — if jq fails we must not
    # write an empty file silently.
    local init=""
    if ! init="$(jq -n --arg h "$hash" \
        '{"__version":1,"last_run_iso":"1970-01-01T00:00:00Z","dedup_hashes":[$h]}' 2>/dev/null)"; then
      bonsai_log ERROR "dedup_add: jq failed during init at $file"
      return 1
    fi
    if [[ -z "$init" ]]; then
      bonsai_log ERROR "dedup_add: empty init output at $file"
      return 1
    fi
    bonsai_json_write "$file" "$init"
    return $?
  fi
  local updated=""
  # Idempotent append: drop any existing copy of $h before re-appending, so a
  # double-call (e.g. a retried emit) can never duplicate an entry. Re-adding a
  # known hash also moves it to the tail, keeping the rolling window LRU-ordered.
  if ! updated="$(jq --arg h "$hash" --argjson n "$_BONSAI_DEDUP_WINDOW" '
    .dedup_hashes = (((.dedup_hashes // []) | map(select(. != $h))) + [$h])
    | .dedup_hashes = (.dedup_hashes | .[(-$n):])
  ' "$file" 2>/dev/null)"; then
    updated=""
  fi
  if [[ -z "$updated" ]]; then
    bonsai_log ERROR "dedup_add: corrupt state.json at $file"
    return 1
  fi
  bonsai_json_write "$file" "$updated"
}
