#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

run_start() { bash "$BONSAI_PLUGIN_ROOT/lib/commands/start.sh" "$@"; }
cfg_val() { jq -r "$1" "$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"; }

@test "start: writes a default config" {
  run run_start
  [ "$status" -eq 0 ]
  [ "$(cfg_val '.throttle_min_minutes')" = "5" ]
}

@test "start: default config includes throttle_idle_minutes" {
  run_start
  [ "$(cfg_val '.throttle_idle_minutes')" = "20" ]
}

@test "start: --throttle=10m sets 10 minutes" {
  run_start --throttle=10m
  [ "$(cfg_val '.throttle_min_minutes')" = "10" ]
}

@test "start: --throttle=2h sets 120 minutes" {
  run_start --throttle=2h
  [ "$(cfg_val '.throttle_min_minutes')" = "120" ]
}

@test "start: invalid --throttle is ignored with a warning, command succeeds" {
  run run_start --throttle=abc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "WARN"                  # user is told it was ignored
  [ "$(cfg_val '.throttle_min_minutes')" = "5" ]   # default unchanged
}

@test "start: invalid --quota-runs is ignored with a warning, command succeeds" {
  run run_start --quota-runs=xyz
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "WARN"
  [ "$(cfg_val '.quota.runs_per_day')" = "10" ]    # default unchanged
}

@test "start: a valid flag still applies after earlier invalid ones" {
  run_start --throttle=abc --quota-runs=xyz --throttle=15m
  [ "$(cfg_val '.throttle_min_minutes')" = "15" ]
}

@test "start: registers the project in the whitelist and bootstraps state.json" {
  run_start
  jq -e --arg p "$CLAUDE_PROJECT_DIR" '.tended | index($p) != null' "$CLAUDE_PLUGIN_DATA/projects.json"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json" ]
}

@test "start: --lenses sets the lens array" {
  run_start --lenses=technical,workflow
  [ "$(cfg_val '.lenses_enabled | join(",")')" = "technical,workflow" ]
}

@test "start: --model sets the gardener model" {
  run_start --model=claude-opus-4-8
  [ "$(cfg_val '.gardener_model')" = "claude-opus-4-8" ]
}

@test "start: --throttle=1d sets 1440 minutes" {
  run_start --throttle=1d
  [ "$(cfg_val '.throttle_min_minutes')" = "1440" ]
}
