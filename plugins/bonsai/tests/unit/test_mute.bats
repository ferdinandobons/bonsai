#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib mute.sh
}
teardown() { teardown_sandbox; }

@test "mute: parse_duration accepts 30m, 1h, 4h, 1d" {
  run bonsai_mute_parse_duration "30m"
  [ "$status" -eq 0 ]; [ "$output" = "1800" ]
  run bonsai_mute_parse_duration "1h"
  [ "$status" -eq 0 ]; [ "$output" = "3600" ]
  run bonsai_mute_parse_duration "4h"
  [ "$status" -eq 0 ]; [ "$output" = "14400" ]
  run bonsai_mute_parse_duration "1d"
  [ "$status" -eq 0 ]; [ "$output" = "86400" ]
}

@test "mute: parse_duration rejects invalid input" {
  run bonsai_mute_parse_duration "garbage"
  [ "$status" -ne 0 ]
  run bonsai_mute_parse_duration "5x"
  [ "$status" -ne 0 ]
  run bonsai_mute_parse_duration ""
  [ "$status" -ne 0 ]
}

@test "mute: is_muted false when no mute file" {
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 1 ]
}

@test "mute: sleep then is_muted true within window" {
  bonsai_mute_sleep "$CLAUDE_PROJECT_DIR" "30m"
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}

@test "mute: sleep then wake → is_muted false" {
  bonsai_mute_sleep "$CLAUDE_PROJECT_DIR" "1h"
  bonsai_mute_wake "$CLAUDE_PROJECT_DIR"
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 1 ]
}

@test "mute: expired mute is_muted false" {
  local file="$CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json"
  echo '{"__version":1,"mute_until_epoch":1}' > "$file"
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 1 ]
}

@test "mute: status reports remaining seconds when muted" {
  bonsai_mute_sleep "$CLAUDE_PROJECT_DIR" "1h"
  run bonsai_mute_remaining_seconds "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" -gt 3500 ]
  [ "$output" -le 3600 ]
}

@test "mute: is_muted returns 1 on corrupt mute.json" {
  echo "{not valid json" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json"
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 1 ]
}

@test "mute: remaining_seconds returns 0 on corrupt mute.json" {
  echo "{not valid json" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json"
  run bonsai_mute_remaining_seconds "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "mute: is_muted_global false when no global mute file" {
  run bonsai_mute_is_muted_global
  [ "$status" -eq 1 ]
}

@test "mute: sleep_global then is_muted_global true" {
  bonsai_mute_sleep_global "1h"
  run bonsai_mute_is_muted_global
  [ "$status" -eq 0 ]
}

@test "mute: wake_global removes global mute" {
  bonsai_mute_sleep_global "1h"
  bonsai_mute_wake_global
  run bonsai_mute_is_muted_global
  [ "$status" -eq 1 ]
}

@test "mute: global and project mutes are independent" {
  bonsai_mute_sleep "$CLAUDE_PROJECT_DIR" "1h"
  # Global not set
  run bonsai_mute_is_muted_global
  [ "$status" -eq 1 ]
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}
