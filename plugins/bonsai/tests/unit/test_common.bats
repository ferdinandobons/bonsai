#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() { setup_sandbox; source_lib common.sh; }
teardown() { teardown_sandbox; }

@test "common: bonsai_now_iso returns ISO-8601 UTC" {
  run bonsai_now_iso
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "common: bonsai_log writes to log file with timestamp" {
  bonsai_log INFO "test message"
  [ -f "$CLAUDE_PLUGIN_DATA/logs/bonsai.log" ]
  grep -q "test message" "$CLAUDE_PLUGIN_DATA/logs/bonsai.log"
  grep -qE "\[INFO\]" "$CLAUDE_PLUGIN_DATA/logs/bonsai.log"
}

@test "common: bonsai_log ERROR writes to bonsai-errors.log" {
  bonsai_log ERROR "boom"
  [ -f "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log" ]
  grep -q "boom" "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
}

@test "common: bonsai_silent_exit emits no stdout/stderr and exits 0" {
  run bash -c 'source "$BONSAI_PLUGIN_ROOT/lib/common.sh"; bonsai_silent_exit "reason"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common: bonsai_json_get returns value from file" {
  echo '{"a":{"b":42}}' > "$CLAUDE_PLUGIN_DATA/x.json"
  run bonsai_json_get "$CLAUDE_PLUGIN_DATA/x.json" '.a.b'
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "common: bonsai_json_get returns empty for missing file" {
  run bonsai_json_get "$CLAUDE_PLUGIN_DATA/missing.json" '.a'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common: bonsai_ensure_dir creates nested directories" {
  bonsai_ensure_dir "$CLAUDE_PLUGIN_DATA/a/b/c"
  [ -d "$CLAUDE_PLUGIN_DATA/a/b/c" ]
}
