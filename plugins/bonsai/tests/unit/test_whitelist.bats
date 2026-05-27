#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib whitelist.sh
}
teardown() { teardown_sandbox; }

@test "whitelist: is_tended returns 1 when projects.json is missing" {
  run bonsai_whitelist_is_tended "/some/path"
  [ "$status" -eq 1 ]
}

@test "whitelist: is_tended returns 0 when cwd is in list" {
  fixture_projects_json "/foo" "/bar"
  run bonsai_whitelist_is_tended "/foo"
  [ "$status" -eq 0 ]
}

@test "whitelist: is_tended returns 1 when cwd is not in list" {
  fixture_projects_json "/foo"
  run bonsai_whitelist_is_tended "/baz"
  [ "$status" -eq 1 ]
}

@test "whitelist: is_tended returns 1 when projects.json is corrupted" {
  echo "{not valid json" > "$CLAUDE_PLUGIN_DATA/projects.json"
  run bonsai_whitelist_is_tended "/foo"
  [ "$status" -eq 1 ]
}

@test "whitelist: add creates file if missing" {
  bonsai_whitelist_add "/new/path"
  [ -f "$CLAUDE_PLUGIN_DATA/projects.json" ]
  run jq -e '.tended | index("/new/path") != null' "$CLAUDE_PLUGIN_DATA/projects.json"
  [ "$status" -eq 0 ]
}

@test "whitelist: add is idempotent" {
  bonsai_whitelist_add "/p"
  bonsai_whitelist_add "/p"
  run jq -r '.tended | length' "$CLAUDE_PLUGIN_DATA/projects.json"
  [ "$output" = "1" ]
}

@test "whitelist: remove deletes entry but keeps others" {
  fixture_projects_json "/a" "/b" "/c"
  bonsai_whitelist_remove "/b"
  run jq -r '.tended | join(",")' "$CLAUDE_PLUGIN_DATA/projects.json"
  [ "$output" = "/a,/c" ]
}

@test "whitelist: remove on missing entry is a no-op" {
  fixture_projects_json "/a"
  bonsai_whitelist_remove "/zzz"
  run jq -r '.tended | length' "$CLAUDE_PLUGIN_DATA/projects.json"
  [ "$output" = "1" ]
}

@test "whitelist: list returns all entries one per line" {
  fixture_projects_json "/x" "/y"
  run bonsai_whitelist_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^/x$"
  echo "$output" | grep -q "^/y$"
}

@test "whitelist: remove on corrupt file returns 1 and logs an error" {
  echo "{not valid json" > "$CLAUDE_PLUGIN_DATA/projects.json"
  run bonsai_whitelist_remove "/foo"
  [ "$status" -eq 1 ]
  [ -f "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log" ]
  grep -q "whitelist_remove: corrupt" "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
}

@test "whitelist: add on corrupt file returns 1 and logs an error" {
  echo "{not valid json" > "$CLAUDE_PLUGIN_DATA/projects.json"
  run bonsai_whitelist_add "/foo"
  [ "$status" -eq 1 ]
  [ -f "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log" ]
  grep -q "whitelist_add: corrupt" "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
}
