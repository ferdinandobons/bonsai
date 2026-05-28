#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib telemetry.sh
  LOGS="$CLAUDE_PLUGIN_DATA/logs"
  mkdir -p "$LOGS"
}
teardown() { teardown_sandbox; }

# Write a gardener log fixture: gardener-<ts>.log holding a result JSON.
make_log() {
  local ts="$1" subtype="$2" num_turns="$3"
  jq -n --arg s "$subtype" --argjson n "$num_turns" \
    '{type:"result", subtype:$s, num_turns:$n, usage:{}}' \
    > "$LOGS/gardener-${ts}.log"
}

@test "telemetry: stats counts completed, errored, max_turns and peak turns" {
  make_log "20260528T100000Z" "success"               4
  make_log "20260528T101000Z" "success"               21
  make_log "20260528T102000Z" "error_max_turns"       25
  make_log "20260528T103000Z" "error_during_execution" 7
  run bonsai_telemetry_gardener_stats "$LOGS"
  [ "$status" -eq 0 ]
  # Format: total completed errored max_turns peak_turns
  [ "$output" = "4 2 2 1 25" ]
}

@test "telemetry: cutoff excludes logs older than the window" {
  make_log "20260101T000000Z" "success" 30
  make_log "20260528T120000Z" "success" 5
  run bonsai_telemetry_gardener_stats "$LOGS" "20260528T000000Z"
  # Only the recent log counted: peak turns is 5, not 30.
  [ "$output" = "1 1 0 0 5" ]
}

@test "telemetry: a corrupt/partial log counts as errored" {
  printf 'not json — claude died mid-write' > "$LOGS/gardener-20260528T130000Z.log"
  run bonsai_telemetry_gardener_stats "$LOGS"
  [ "$output" = "1 0 1 0 0" ]
}

@test "telemetry: missing log dir yields all zeros" {
  run bonsai_telemetry_gardener_stats "$CLAUDE_PLUGIN_DATA/nope"
  [ "$status" -eq 0 ]
  [ "$output" = "0 0 0 0 0" ]
}

@test "telemetry: empty log dir yields all zeros" {
  run bonsai_telemetry_gardener_stats "$LOGS"
  [ "$output" = "0 0 0 0 0" ]
}
