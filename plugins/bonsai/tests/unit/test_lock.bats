#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib lock.sh
  LOCK="$CLAUDE_PLUGIN_DATA/locks/test.lock"
}
teardown() { teardown_sandbox; }

@test "lock: acquire on a free lock succeeds and creates the dir" {
  run bonsai_lock_acquire "$LOCK"
  [ "$status" -eq 0 ]
  [ -d "$LOCK" ]
}

@test "lock: second acquire while held (fresh) fails" {
  bonsai_lock_acquire "$LOCK"
  run bonsai_lock_acquire "$LOCK"
  [ "$status" -ne 0 ]
}

@test "lock: acquire reclaims a stale lock" {
  bonsai_lock_acquire "$LOCK"
  # Backdate the lock's epoch well beyond the stale threshold.
  printf '%s' "1" > "$LOCK/epoch"
  run bonsai_lock_acquire "$LOCK" 900
  [ "$status" -eq 0 ]
  [ -d "$LOCK" ]
}

@test "lock: concurrent reclaim of one stale lock yields exactly one winner" {
  bonsai_lock_acquire "$LOCK"
  printf '%s' "1" > "$LOCK/epoch"   # backdate well past the stale threshold
  local wins="$BATS_TEST_TMPDIR/wins"; : > "$wins"
  # Several Stop hooks racing on the same stale lock must not all reclaim it —
  # only one may win, else two gardeners spawn and race quota.json / branch ids.
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    ( bonsai_lock_acquire "$LOCK" 900 && printf 'x\n' >> "$wins" ) &
  done
  wait
  local n; n="$(grep -c x "$wins" 2>/dev/null || printf 0)"
  [ "$n" -eq 1 ]
}

@test "lock: a held lock whose epoch is missing is treated as fresh, not reclaimed" {
  bonsai_lock_acquire "$LOCK"
  rm -f "$LOCK/epoch"            # simulate an epoch write that didn't land
  run bonsai_lock_acquire "$LOCK" 900
  [ "$status" -ne 0 ]           # must NOT reclaim a lock with unknown age
}

@test "lock: release lets a subsequent acquire succeed" {
  bonsai_lock_acquire "$LOCK"
  bonsai_lock_release "$LOCK"
  [ ! -d "$LOCK" ]
  run bonsai_lock_acquire "$LOCK"
  [ "$status" -eq 0 ]
}

@test "lock: release on a non-existent lock is a no-op success" {
  run bonsai_lock_release "$CLAUDE_PLUGIN_DATA/locks/never.lock"
  [ "$status" -eq 0 ]
}

@test "lock: path is deterministic per project and lives under plugin data" {
  local a b
  a="$(bonsai_lock_path /Users/me/projA)"
  b="$(bonsai_lock_path /Users/me/projA)"
  [ "$a" = "$b" ]
  [ "${a#"$CLAUDE_PLUGIN_DATA"/}" != "$a" ]   # a starts with $CLAUDE_PLUGIN_DATA/ ([ ] is honored mid-test; [[ ]] is not)
  local c; c="$(bonsai_lock_path /Users/me/projB)"
  [ "$a" != "$c" ]
}
