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
  hash="$(printf '%s' "$project_dir" | bonsai_sha256 | cut -c1-16)"
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

  # Lock exists — reclaim only if stale. If the epoch is missing/unreadable (the
  # holder's epoch write may not have landed yet), treat the lock as just-created
  # rather than ancient — otherwise a contender would reclaim a fresh lock and a
  # second gardener would spawn.
  local now; now="$(date -u +%s)"
  local created; created="$(cat "$lock_dir/epoch" 2>/dev/null || printf '')"
  [[ "$created" =~ ^[0-9]+$ ]] || created="$now"
  if (( now - created >= stale_secs )); then
    bonsai_log WARN "lock_acquire: reclaiming stale lock $lock_dir (age $((now - created))s)"
    # Serialize the reclaim through a separate atomic-mkdir guard. A bare
    # rm+mkdir has a TOCTOU window where a racing hook's rm deletes the winner's
    # fresh lock, so both believe they hold it and two gardeners spawn. With the
    # guard, exactly one racer wins the mkdir and performs the rm+recreate; the
    # rest fail the mkdir and back off without touching $lock_dir. The guard is
    # held only for two local fs ops; if a reclaimer is killed mid-flight, a
    # guard older than a few seconds is treated as abandoned (no permanent wedge).
    local guard="${lock_dir}.reclaiming"
    if [[ -d "$guard" ]]; then
      local g; g="$(cat "$guard/epoch" 2>/dev/null || printf '0')"
      [[ "$g" =~ ^[0-9]+$ ]] || g=0
      (( now - g >= 10 )) && rm -rf "$guard" 2>/dev/null
    fi
    if mkdir "$guard" 2>/dev/null; then
      date -u +%s > "$guard/epoch" 2>/dev/null || true
      # Re-check under the guard: between our stale read and winning the guard,
      # another reclaimer may already have refreshed the lock. If it's no longer
      # stale, back off instead of clobbering a now-fresh lock.
      # Missing/unreadable epoch → a racer is mid-create; treat as fresh (cur=now),
      # consistent with the initial check, so we never clobber a just-born lock.
      local cur; cur="$(cat "$lock_dir/epoch" 2>/dev/null || printf '')"
      [[ "$cur" =~ ^[0-9]+$ ]] || cur="$now"
      local rc=1
      if (( now - cur >= stale_secs )); then
        # Reclaim IN PLACE: overwrite the dead holder's epoch with a fresh one.
        # We never rm+mkdir the lock dir, so it never momentarily disappears and
        # no concurrent fresh acquire can slip into a rm→mkdir gap. (The guard
        # already guarantees we're the only reclaimer.)
        if date -u +%s > "$lock_dir/epoch" 2>/dev/null; then rc=0; fi
      fi
      rm -rf "$guard" 2>/dev/null
      return "$rc"
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
