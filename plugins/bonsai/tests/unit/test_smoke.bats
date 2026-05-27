#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "smoke: bats runs and sandbox env vars are set" {
  [ -n "$BONSAI_PLUGIN_ROOT" ]
  [ -d "$CLAUDE_PLUGIN_DATA" ]
  [ -d "$CLAUDE_PROJECT_DIR/.claude/bonsai" ]
}

@test "smoke: fixtures create valid JSON files" {
  fixture_projects_json "/some/path" "/another/path"
  fixture_state_json "2026-05-27T00:00:00Z"
  fixture_config_json

  run jq -e '.tended | length == 2' "$CLAUDE_PLUGIN_DATA/projects.json"
  [ "$status" -eq 0 ]
}
