#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib migrate.sh
  LOG="$CLAUDE_PLUGIN_DATA/logs/bonsai.log"
}
teardown() { teardown_sandbox; }

@test "migrate: check on a missing file is a silent no-op (returns 0)" {
  run bonsai_migrate_check "$CLAUDE_PROJECT_DIR/.claude/bonsai/nope.json"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ] || ! grep -q "migrate:" "$LOG"
}

@test "migrate: a future __version logs a WARN" {
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  echo '{"__version":2}' > "$f"
  bonsai_migrate_check "$f"
  grep -q "migrate: $f declares __version=2" "$LOG"
}

@test "migrate: the current __version=1 is silent" {
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  echo '{"__version":1}' > "$f"
  bonsai_migrate_check "$f"
  [ ! -f "$LOG" ] || ! grep -q "migrate:" "$LOG"
}

@test "migrate: a missing __version key is silent" {
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  echo '{"throttle_min_minutes":5}' > "$f"
  run bonsai_migrate_check "$f"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ] || ! grep -q "migrate:" "$LOG"
}

@test "migrate: a non-numeric __version is tolerated without WARN" {
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  echo '{"__version":"two"}' > "$f"
  run bonsai_migrate_check "$f"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ] || ! grep -q "migrate:" "$LOG"
}

@test "migrate: run_all tolerates all targets being absent (returns 0)" {
  run bonsai_migrate_run_all "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}

@test "migrate: run_all warns about a future-versioned file" {
  echo '{"__version":3}' > "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  bonsai_migrate_run_all "$CLAUDE_PROJECT_DIR"
  grep -q "declares __version=3" "$LOG"
}
