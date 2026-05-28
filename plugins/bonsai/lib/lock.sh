#!/usr/bin/env bash
# Per-project advisory lock to serialize gardener dispatch.
#
# Stop hooks fire after every turn and the gardener runs as a detached process,
# so two interactive sessions on the same project (or two Stop hooks racing)
# could spawn concurrent gardeners that both read-modify-write quota.json /
# state.json (lost updates) and both allocate the same branch id.
#
# We use an atomic `mkdir` as the mutex (portable: macOS has no flock). The lock
# is acquired by the Stop hook before spawning and released by the detached
# gardener subshell when claude exits. A staleness backstop reclaims a lock left
# behind by a crashed gardener so Bonsai can never wedge permanently.

[[ -n "${_BONSAI_LOCK_SOURCED:-}" ]] && return 0
_BONSAI_LOCK_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

# Default staleness threshold (seconds). Comfortably exceeds the gardener's
# wall-clock cap (timeout 600s in dispatch.sh), so a live gardener is never
# treated as stale.
_BONSAI_LOCK_STALE_SECS_DEFAULT=900

# Deterministic lock path for a project dir, under plugin data.
bonsai_lock_path() {
  local project_dir="$1"
  local data_dir="${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}"
  local hash
  hash="$(printf '%s' "$project_dir" \
    | { shasum -a 256 2>/dev/null || sha256sum; } \
    | awk '{print substr($1,1,16)}')"
  printf '%s/locks/%s.lock' "$data_dir" "$hash"
}

# Acquire the lock. Returns 0 if acquired, 1 if held by a fresh holder.
# A stale lock (older than the threshold) is reclaimed.
bonsai_lock_acquire() {
  local lock_dir="$1"
  local stale_secs="${2:-$_BONSAI_LOCK_STALE_SECS_DEFAULT}"
  [[ -n "$lock_dir" ]] || return 1
  bonsai_ensure_dir "$(dirname "$lock_dir")" || return 1

  if mkdir "$lock_dir" 2>/dev/null; then
    date -u +%s > "$lock_dir/epoch" 2>/dev/null || true
    return 0
  fi

  # Lock exists — reclaim only if stale.
  local created; created="$(cat "$lock_dir/epoch" 2>/dev/null || printf '0')"
  [[ "$created" =~ ^[0-9]+$ ]] || created=0
  local now; now="$(date -u +%s)"
  if (( now - created >= stale_secs )); then
    bonsai_log WARN "lock_acquire: reclaiming stale lock $lock_dir (age $((now - created))s)"
    rm -rf "$lock_dir" 2>/dev/null
    if mkdir "$lock_dir" 2>/dev/null; then
      date -u +%s > "$lock_dir/epoch" 2>/dev/null || true
      return 0
    fi
  fi
  return 1
}

# Release the lock. Always succeeds (missing lock is a no-op).
bonsai_lock_release() {
  local lock_dir="$1"
  [[ -n "$lock_dir" ]] || return 0
  rm -rf "$lock_dir" 2>/dev/null || true
  return 0
}
