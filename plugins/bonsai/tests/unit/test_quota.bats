#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib quota.sh
  fixture_config_json
}
teardown() { teardown_sandbox; }

@test "quota: throttle_ok honors an explicit min_minutes override" {
  fixture_state_json "$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # last_run = now
  run bonsai_quota_throttle_ok "$CLAUDE_PROJECT_DIR" 1   # 1-min wait, not elapsed
  [ "$status" -ne 0 ]
  run bonsai_quota_throttle_ok "$CLAUDE_PROJECT_DIR" 0   # 0-min wait → always ok
  [ "$status" -eq 0 ]
}

@test "quota: update_last_run stores an optional diff hash" {
  bonsai_quota_update_last_run "$CLAUDE_PROJECT_DIR" "deadbeef"
  local h; h="$(jq -r '.last_diff_hash' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")"
  [ "$h" = "deadbeef" ]
}

@test "quota: update_last_run without a hash leaves last_diff_hash absent" {
  bonsai_quota_update_last_run "$CLAUDE_PROJECT_DIR"
  local h; h="$(jq -r '.last_diff_hash // "ABSENT"' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")"
  [ "$h" = "ABSENT" ]
}

@test "quota: caps_ok false when per-project observations reach the cap" {
  local i; for i in $(seq 1 20); do bonsai_quota_record_event "observation" "$CLAUDE_PROJECT_DIR"; done
  run bonsai_quota_caps_ok
  [ "$status" -ne 0 ]
}

@test "quota: global_quota override lowers the global cap and blocks across scopes" {
  echo '{"global_quota":{"runs_per_day":2}}' > "$CLAUDE_PLUGIN_DATA/config.json"
  bonsai_quota_record_event "run" "/proj-a"
  bonsai_quota_record_event "run" "/proj-b"
  run bonsai_quota_caps_ok
  [ "$status" -ne 0 ]
}

@test "quota: record_event creates quota.json with one entry" {
  bonsai_quota_record_event "run" "/foo"
  run jq -r '.events | length' "$CLAUDE_PLUGIN_DATA/quota.json"
  [ "$output" = "1" ]
}

@test "quota: count_events_24h counts only events in window" {
  local now; now="$(date -u +%s)"
  local old=$(( now - 100000 ))
  local recent=$(( now - 100 ))
  # Slash-free scope key: a fixture stores it as a jq literal but the lib looks
  # it up via `jq --arg`, and Git Bash converts POSIX-looking ("/p") --arg values
  # to Windows paths, desyncing the two. A key with no leading slash is immune and
  # is just as valid for this opaque-key logic.
  jq -n --argjson o "$old" --argjson r "$recent" '{
    "__version":1,
    "events":[
      {"kind":"run","scope":"p","epoch":$o},
      {"kind":"run","scope":"p","epoch":$r},
      {"kind":"run","scope":"p","epoch":$r}
    ]
  }' > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_quota_count_events_24h "run" "p"
  [ "$output" = "2" ]
}

@test "quota: count_events_24h counts global when scope omitted" {
  local now; now="$(date -u +%s)"
  local r=$(( now - 100 ))
  jq -n --argjson r "$r" '{
    "__version":1,
    "events":[
      {"kind":"run","scope":"/a","epoch":$r},
      {"kind":"run","scope":"/b","epoch":$r}
    ]
  }' > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_quota_count_events_24h "run"
  [ "$output" = "2" ]
}

@test "quota: count_events_24h returns 0 on corrupt quota.json" {
  echo "{not valid" > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_quota_count_events_24h "run"
  [ "$output" = "0" ]
}

@test "quota: throttle_ok true when last_run > throttle" {
  fixture_state_json "1970-01-01T00:00:00Z"
  run bonsai_quota_throttle_ok "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}

@test "quota: throttle_ok false when last_run within throttle" {
  fixture_state_json "$(bonsai_now_iso)"
  run bonsai_quota_throttle_ok "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 1 ]
}

@test "quota: caps_ok false when per-project runs reach 10" {
  local now; now="$(date -u +%s)"
  local recent=$(( now - 60 ))
  # Slash-free scope/project key — see the count_events_24h test above for why a
  # leading-slash key desyncs fixture literals from the lib's `jq --arg` lookups
  # under Git Bash.
  local events; events="$(jq -n --argjson r "$recent" '
    [range(0;10) | {"kind":"run","scope":"p","epoch":$r}]')"
  jq -n --argjson e "$events" '{"__version":1,"events":$e}' > "$CLAUDE_PLUGIN_DATA/quota.json"
  CLAUDE_PROJECT_DIR=p run bonsai_quota_caps_ok
  [ "$status" -eq 1 ]
}

@test "quota: caps_ok true when below all caps" {
  run bonsai_quota_caps_ok
  [ "$status" -eq 0 ]
}

@test "quota: update_last_run writes ISO timestamp" {
  fixture_state_json
  bonsai_quota_update_last_run "$CLAUDE_PROJECT_DIR"
  run jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "quota: update_last_run creates state.json if missing" {
  rm -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  bonsai_quota_update_last_run "$CLAUDE_PROJECT_DIR"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json" ]
  run jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "quota: update_last_run rebuilds corrupt state.json" {
  echo "{bad json" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  bonsai_quota_update_last_run "$CLAUDE_PROJECT_DIR"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json" ]
  run jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "quota: update_last_run on rebuild path never writes an empty state when jq fails" {
  echo "{bad json" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"   # forces rebuild
  # Shadow jq with a stub that always fails, simulating jq missing/erroring.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/jq"
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bonsai_quota_update_last_run "$CLAUDE_PROJECT_DIR" "abc"
  [ "$status" -ne 0 ]                                                    # must report failure
  [ -s "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json" ]                 # must NOT be emptied
}

@test "quota: record_event handles corrupt quota.json gracefully" {
  echo "invalid" > "$CLAUDE_PLUGIN_DATA/quota.json"
  run bonsai_quota_record_event "run" "/foo"
  [ "$status" -eq 1 ]
}
