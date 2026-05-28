#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  fixture_config_json
  cfg="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
}
teardown() { teardown_sandbox; }

run_config() { bash "$BONSAI_PLUGIN_ROOT/lib/commands/config.sh" "$@"; }

@test "config: setting a numeric key applies it and exits 0" {
  run run_config throttle_min_minutes 9
  [ "$status" -eq 0 ]
  [ "$(jq -r '.throttle_min_minutes' "$cfg")" = "9" ]
}

@test "config: setting a string key applies it" {
  run run_config gardener_model claude-opus-4-8
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gardener_model' "$cfg")" = "claude-opus-4-8" ]
}

@test "config: throttle_idle_minutes is an accepted key" {
  run run_config throttle_idle_minutes 30
  [ "$status" -eq 0 ]
  [ "$(jq -r '.throttle_idle_minutes' "$cfg")" = "30" ]
}

@test "config: unknown key is rejected, exits 0, config untouched" {
  run run_config bogus_key 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "unknown config key"
  [ "$(jq -r '.throttle_min_minutes' "$cfg")" = "5" ]
}

@test "config: corrupt config reports an error and exits 0" {
  echo 'not json' > "$cfg"
  run run_config throttle_min_minutes 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "corrupt"
}

@test "config: a valid-JSON but non-object config fails gracefully" {
  # `[]` passes `jq empty` but `.[$k] = $v` errors — must not die under set -e.
  echo '[]' > "$cfg"
  run run_config throttle_min_minutes 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "failed"
}
