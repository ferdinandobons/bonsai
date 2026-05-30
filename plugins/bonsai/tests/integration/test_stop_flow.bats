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

# Put a stub `claude` on PATH so dispatch never makes a real API call (the hook
# spawns `claude -p` in the background). Without this, a machine with the real
# claude installed would fire a live gardener — and bill the user — during tests.
stub_claude() {
  local d="$BATS_TEST_TMPDIR/stub-bin"; mkdir -p "$d"
  printf '#!/usr/bin/env bash\ncat - >/dev/null\n' > "$d/claude"
  chmod +x "$d/claude"
  export PATH="$d:$PATH"
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
  # Give the backgrounded gardener a moment to write its evidence (poll up to 3s)
  local i=0
  while [ ! -f "$STUB_OUT" ] && [ $i -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -f "$STUB_OUT" ]
  # Hook output must be empty (or {}) for CC's Stop hook schema validator —
  # asserted LAST with [ ] (a bare [[ ]] mid-test would not fail the test).
  [ -z "$output" ] || [ "$output" = "{}" ]
}

@test "stop: when gates pass, updates state.json last_run_iso" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  stub_claude
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json" ]
  local iso; iso="$(jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")"
  [ "$iso" != "1970-01-01T00:00:00Z" ]
}

@test "stop: when gates pass, increments quota.json run counter" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  stub_claude
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  local n
  n="$(jq -r '[.events[] | select(.kind=="run")] | length' "$CLAUDE_PLUGIN_DATA/quota.json")"
  [ "$n" = "1" ]
}

@test "stop: skips when a gardener lock is already held for the project" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  source "$BONSAI_PLUGIN_ROOT/lib/common.sh"
  source "$BONSAI_PLUGIN_ROOT/lib/lock.sh"
  local lock; lock="$(bonsai_lock_path "$CLAUDE_PROJECT_DIR")"
  bonsai_lock_acquire "$lock"   # held + fresh → concurrency gate must block
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" \
    '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Hook skipped before step 6 → last_run untouched.
  local iso; iso="$(jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")"
  [ "$iso" = "1970-01-01T00:00:00Z" ]
}

@test "stop: idle (no code change since last run) uses the longer idle throttle" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_config_json
  local ten_min_ago; ten_min_ago="$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '10 min ago' +%Y-%m-%dT%H:%M:%SZ)"
  fixture_state_json "$ten_min_ago"
  ( cd "$CLAUDE_PROJECT_DIR" && git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m init )
  # Record the current diff hash as last_diff_hash → "nothing changed since last run".
  source "$BONSAI_PLUGIN_ROOT/lib/common.sh"; source "$BONSAI_PLUGIN_ROOT/lib/signal.sh"
  local h; h="$(bonsai_signal_diff_hash "$CLAUDE_PROJECT_DIR")"
  jq --arg h "$h" '.last_diff_hash=$h' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json" > "$BATS_TEST_TMPDIR/s" \
    && mv "$BATS_TEST_TMPDIR/s" "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run run_stop_hook_with_input "$input"
  [ "$status" -eq 0 ]
  # idle throttle (20m) not elapsed (only 10m) → skipped → last_run unchanged
  [ "$(jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")" = "$ten_min_ago" ]
}

@test "stop: gardener receives the PREVIOUS last_run_iso, not the freshly-updated one" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  local prev="2020-01-01T00:00:00Z"
  fixture_state_json "$prev"
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"; mkdir -p "$stub_dir"
  cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
cat - > "$BATS_TEST_TMPDIR/g-stdin.txt"
EOF
  chmod +x "$stub_dir/claude"; export PATH="$stub_dir:$PATH"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input"
  for i in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/g-stdin.txt" ] && break; sleep 0.1; done
  # The gardener's observation window must start at the previous run, not "now".
  [ "$(jq -r '.last_run_iso' "$BATS_TEST_TMPDIR/g-stdin.txt")" = "$prev" ]
}

@test "stop: gardener prompt includes a git_diff context field" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  ( cd "$CLAUDE_PROJECT_DIR" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'x\n' > f.txt && git add f.txt && git commit -qm init && printf 'y\n' >> f.txt )
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"; mkdir -p "$stub_dir"
  cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
cat - > "$BATS_TEST_TMPDIR/gd-stdin.txt"
EOF
  chmod +x "$stub_dir/claude"; export PATH="$stub_dir:$PATH"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input"
  for i in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/gd-stdin.txt" ] && break; sleep 0.1; done
  jq -e 'has("git_diff")' "$BATS_TEST_TMPDIR/gd-stdin.txt"
  # and it actually contains the change
  jq -r '.git_diff' "$BATS_TEST_TMPDIR/gd-stdin.txt" | grep -q "f.txt"
}

@test "stop: gardener prompt includes a non-empty project_history when a module churned" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  ( cd "$CLAUDE_PROJECT_DIR" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p auth \
    && printf 'a\n' > auth/login.sh && git add -A && git commit -qm c1 \
    && printf 'b\n' >> auth/login.sh && git add -A && git commit -qm c2 \
    && printf 'c\n' >> auth/login.sh && git add -A && git commit -qm c3 \
    && printf 'work\n' >> auth/login.sh )
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"; mkdir -p "$stub_dir"
  cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
cat - > "$BATS_TEST_TMPDIR/ph-stdin.txt"
EOF
  chmod +x "$stub_dir/claude"; export PATH="$stub_dir:$PATH"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input"
  for i in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/ph-stdin.txt" ] && break; sleep 0.1; done
  # Guard the read: a loaded runner may not flush the detached stub within the
  # poll budget; assert non-empty first so the failure is "stub never wrote",
  # not an opaque jq parse error (mirrors the [ -f ] gate at the first dispatch
  # test above).
  [ -s "$BATS_TEST_TMPDIR/ph-stdin.txt" ]
  jq -e 'has("project_history")' "$BATS_TEST_TMPDIR/ph-stdin.txt"
  jq -r '.project_history' "$BATS_TEST_TMPDIR/ph-stdin.txt" | grep -q 'auth'
}

@test "stop: history_enabled=false empties project_history but the hook still spawns" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  jq '.history_enabled = false' "$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json" \
    > "$BATS_TEST_TMPDIR/cfg" && mv "$BATS_TEST_TMPDIR/cfg" "$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  ( cd "$CLAUDE_PROJECT_DIR" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p auth && printf 'a\n' > auth/login.sh && git add -A && git commit -qm c1 \
    && printf 'b\n' >> auth/login.sh && git add -A && git commit -qm c2 \
    && printf 'work\n' >> auth/login.sh )
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"; mkdir -p "$stub_dir"
  cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
cat - > "$BATS_TEST_TMPDIR/phoff-stdin.txt"
EOF
  chmod +x "$stub_dir/claude"; export PATH="$stub_dir:$PATH"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input"
  for i in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/phoff-stdin.txt" ] && break; sleep 0.1; done
  # Guard the read: a loaded runner may not flush the detached stub within the
  # poll budget; assert non-empty first so the failure is "stub never wrote",
  # not an opaque jq parse error (mirrors the [ -f ] gate at the first dispatch
  # test above).
  [ -s "$BATS_TEST_TMPDIR/phoff-stdin.txt" ]
  jq -e 'has("project_history")' "$BATS_TEST_TMPDIR/phoff-stdin.txt"
  run jq -r '.project_history' "$BATS_TEST_TMPDIR/phoff-stdin.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r '.last_run_iso' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json")" != "1970-01-01T00:00:00Z" ]
}

@test "stop: a diff with multibyte UTF-8 truncated at the byte cap still dispatches" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  fixture_state_json "1970-01-01T00:00:00Z"
  ( cd "$CLAUDE_PROJECT_DIR" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'seed\n' > big.txt && git add big.txt && git commit -qm init )
  # >60KB of 2-byte chars so head -c 60000 splits a character mid-sequence.
  ( cd "$CLAUDE_PROJECT_DIR" && printf 'è%.0s' {1..40000} > big.txt )
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"; mkdir -p "$stub_dir"
  cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
cat - > "$BATS_TEST_TMPDIR/mb-stdin.txt"
EOF
  chmod +x "$stub_dir/claude"; export PATH="$stub_dir:$PATH"
  local input; input="$(jq -n --arg c "$CLAUDE_PROJECT_DIR" '{cwd:$c, session_id:"s", transcript_path:"/tmp/t"}')"
  run_stop_hook_with_input "$input"
  for i in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/mb-stdin.txt" ] && break; sleep 0.1; done
  # Byte-truncating a multibyte diff must not break dispatch. jq 1.7+ tolerates
  # the dangling byte (substitutes U+FFFD); this guards against a regression to
  # a jq that would reject it.
  jq -e 'has("git_diff")' "$BATS_TEST_TMPDIR/mb-stdin.txt"
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
