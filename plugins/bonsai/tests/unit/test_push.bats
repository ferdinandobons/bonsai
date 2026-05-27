#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib quota.sh
  source_lib push.sh
  fixture_config_json
}
teardown() { teardown_sandbox; }

@test "push: format emits title and body with project name" {
  local obs='{
    "id":"x", "lens":"technical", "severity":"critical",
    "title":"Race condition","tldr":"oops","action_brief":"b"
  }'
  CLAUDE_PROJECT_DIR=/some/dir/my-project run bonsai_push_format "$obs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.title' >/dev/null
  echo "$output" | jq -e '.body' >/dev/null
  [ "$(echo "$output" | jq -r '.title')" = "Bonsai · my-project" ]
  echo "$output" | jq -r '.body' | grep -q "Race condition"
}

@test "push: rate_ok true when no push in last hour" {
  run bonsai_push_rate_ok "/p"
  [ "$status" -eq 0 ]
}

@test "push: rate_ok false when 5 pushes already in last hour" {
  local now; now="$(date -u +%s)"
  local recent=$(( now - 100 ))
  local events; events="$(jq -n --argjson r "$recent" '
    [range(0;5) | {"kind":"push","scope":"/p","epoch":$r}]')"
  jq -n --argjson e "$events" '{"__version":1,"events":$e}' > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_push_rate_ok "/p"
  [ "$status" -eq 1 ]
}

@test "push: rate_ok true when 5 pushes but older than 1h" {
  local now; now="$(date -u +%s)"
  local old=$(( now - 4000 ))   # > 1h ago
  local events; events="$(jq -n --argjson o "$old" '
    [range(0;5) | {"kind":"push","scope":"/p","epoch":$o}]')"
  jq -n --argjson e "$events" '{"__version":1,"events":$e}' > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_push_rate_ok "/p"
  [ "$status" -eq 0 ]
}

@test "push: rate_ok scoped to project (different project hits don't block)" {
  local now; now="$(date -u +%s)"
  local recent=$(( now - 100 ))
  local events; events="$(jq -n --argjson r "$recent" '
    [range(0;5) | {"kind":"push","scope":"/other","epoch":$r}]')"
  jq -n --argjson e "$events" '{"__version":1,"events":$e}' > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_push_rate_ok "/p"
  [ "$status" -eq 0 ]
}

@test "push: format fails on missing title" {
  local obs='{"id":"x","lens":"technical","severity":"critical","tldr":"x","action_brief":"y"}'
  run bonsai_push_format "$obs"
  [ "$status" -eq 1 ]
}
