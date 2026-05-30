#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() { setup_sandbox; source_lib common.sh; }
teardown() { teardown_sandbox; }

@test "common: bonsai_iso_to_epoch parses a canonical stamp to epoch" {
  run bonsai_iso_to_epoch '2021-01-01T00:00:00Z'
  [ "$status" -eq 0 ]
  [ "$output" = "1609459200" ]
}

@test "common: bonsai_iso_to_epoch maps the never-run sentinel to a real 0" {
  run bonsai_iso_to_epoch '1970-01-01T00:00:00Z'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "common: bonsai_iso_to_epoch fails to 0 on an unparseable stamp" {
  run bonsai_iso_to_epoch 'not-a-date'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "common: bonsai_iso_to_epoch returns 0 for empty input" {
  run bonsai_iso_to_epoch ''
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

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

@test "common: bonsai_log_rotate truncates an oversized log to its tail" {
  local f="$CLAUDE_PLUGIN_DATA/logs/big.log"
  mkdir -p "$CLAUDE_PLUGIN_DATA/logs"
  seq 1 5000 > "$f"
  bonsai_log_rotate "$f" 1024 100
  [ -f "$f" ]
  local lines; lines="$(wc -l < "$f" | tr -d '[:space:]')"
  [ "$lines" -eq 100 ]
  # The tail is kept: the very last original line survives, the first does not.
  grep -q "^5000$" "$f"
  ! grep -q "^1$" "$f"
}

@test "common: bonsai_log_rotate leaves a small log untouched" {
  local f="$CLAUDE_PLUGIN_DATA/logs/small.log"
  mkdir -p "$CLAUDE_PLUGIN_DATA/logs"
  printf 'one\ntwo\n' > "$f"
  bonsai_log_rotate "$f" 524288 2000
  run cat "$f"
  [ "$output" = "one
two" ]
}

@test "common: bonsai_log_rotate on a missing file is a no-op success" {
  run bonsai_log_rotate "$CLAUDE_PLUGIN_DATA/logs/nope.log"
  [ "$status" -eq 0 ]
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

@test "common: bonsai_slugify normal string lowercases and dashes" {
  run bonsai_slugify "Race Condition in updateCache"
  [ "$status" -eq 0 ]
  [ "$output" = "race-condition-in-updatecache" ]
}

@test "common: bonsai_slugify truncates at 40 chars" {
  run bonsai_slugify "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ"
  [ "$status" -eq 0 ]
  [ "${#output}" -le 40 ]
}

@test "common: bonsai_slugify empty input returns 'untitled'" {
  run bonsai_slugify ""
  [ "$status" -eq 0 ]
  [ "$output" = "untitled" ]
}

@test "common: bonsai_slugify all-special input returns 'untitled'" {
  run bonsai_slugify "!!!---???"
  [ "$status" -eq 0 ]
  [ "$output" = "untitled" ]
}

@test "common: bonsai_json_write produces atomic file" {
  bonsai_json_write "$CLAUDE_PLUGIN_DATA/out.json" '{"k":1}'
  [ -f "$CLAUDE_PLUGIN_DATA/out.json" ]
  run jq -e '.k == 1' "$CLAUDE_PLUGIN_DATA/out.json"
  [ "$status" -eq 0 ]
  # No leftover .tmp.* siblings
  run bash -c "ls $CLAUDE_PLUGIN_DATA/out.json.tmp.* 2>/dev/null"
  [ -z "$output" ]
}
