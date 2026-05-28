#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  fixture_config_json
}
teardown() { teardown_sandbox; }

run_stop_hook_with_input() {
  local input="$1"
  local hook="$BONSAI_PLUGIN_ROOT/hooks/stop.sh"
  printf '%s' "$input" | bash "$hook"
}

@test "stop: exits 0 silently when cwd not in whitelist" {
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop: exits 0 silently when project is muted" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  local future; future=$(( $(date -u +%s) + 3600 ))
  jq -n --argjson u "$future" '{"__version":1,"mute_until_epoch":$u}' \
    > "$CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop: exits 0 silently when throttled (recent last_run)" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop: when all gates pass, returns empty output and spawns gardener" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  # Stub `claude` so dispatch doesn't make a real API call
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"
  mkdir -p "$stub_dir"
  export STUB_OUT="$BATS_TEST_TMPDIR/gardener-ran.txt"
  cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
echo "gardener invoked at \$(date)" > "$STUB_OUT"
EOF
  chmod +x "$stub_dir/claude"
  export PATH="$stub_dir:$PATH"

  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  # Hook output must be empty (or {}) so CC's Stop hook schema validator accepts it
  [[ -z "$output" || "$output" == "{}" ]]
  # Give the backgrounded gardener a moment to write its evidence (poll up to 3s)
  local i=0
  while [ ! -f "$STUB_OUT" ] && [ $i -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -f "$STUB_OUT" ]
}

@test "stop: when gates pass, updates state.json last_run_iso" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input" >/dev/null
  local iso
  iso="$(jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")"
  [[ "$iso" != "1970-01-01T00:00:00Z" ]]
}

@test "stop: when gates pass, increments quota.json run counter" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input" >/dev/null
  local n
  n="$(jq -r '[.events[] | select(.kind=="run")] | length' "$CLAUDE_PLUGIN_DATA/quota.json")"
  [ "$n" = "1" ]
}

@test "stop: malformed stdin JSON is silently ignored" {
  run bash -c 'echo "{not json" | bash "$BONSAI_PLUGIN_ROOT/hooks/stop.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop: empty stdin is silently ignored" {
  run bash -c 'echo -n "" | bash "$BONSAI_PLUGIN_ROOT/hooks/stop.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
