#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  # Stub `claude` binary in PATH so we can verify the invocation args without
  # actually running a Claude session.
  export STUB_DIR="$BATS_TEST_TMPDIR/stub-bin"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
# Record args + stdin for assertions, then exit 0.
printf '%s\n' "$@" > "$STUB_DIR/claude-args.txt"
cat - > "$STUB_DIR/claude-stdin.txt"
EOF
  chmod +x "$STUB_DIR/claude"
  export PATH="$STUB_DIR:$PATH"
}
teardown() { teardown_sandbox; }

@test "dispatch: launches claude -p with --agent bonsai:gardener" {
  source "$BONSAI_PLUGIN_ROOT/lib/dispatch.sh"
  bonsai_dispatch_gardener '{"project_dir":"/tmp/x","session_id":"s1"}' "/tmp/log.txt"
  # Give the backgrounded process a moment to flush
  sleep 0.5
  grep -q -- "-p" "$STUB_DIR/claude-args.txt"
  grep -q -- "--agent" "$STUB_DIR/claude-args.txt"
  grep -q -- "bonsai:gardener" "$STUB_DIR/claude-args.txt"
}

@test "dispatch: passes the prompt input as stdin to claude" {
  source "$BONSAI_PLUGIN_ROOT/lib/dispatch.sh"
  bonsai_dispatch_gardener '{"project_dir":"/tmp/x","session_id":"abc"}' "/tmp/log.txt"
  sleep 0.5
  grep -q '"session_id":"abc"' "$STUB_DIR/claude-stdin.txt"
}

@test "dispatch: returns immediately without waiting for claude to finish" {
  source "$BONSAI_PLUGIN_ROOT/lib/dispatch.sh"
  # Replace stub with a slow one
  cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
  chmod +x "$STUB_DIR/claude"
  local start; start=$(date +%s)
  bonsai_dispatch_gardener '{"k":"v"}' "/tmp/log.txt"
  local elapsed=$(( $(date +%s) - start ))
  # Should return in under 2 seconds even though stub sleeps for 5
  [ "$elapsed" -lt 2 ]
}

@test "dispatch: redirects stdout and stderr to the log path" {
  source "$BONSAI_PLUGIN_ROOT/lib/dispatch.sh"
  cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
echo "stdout-line"
echo "stderr-line" >&2
EOF
  chmod +x "$STUB_DIR/claude"
  local log="$BATS_TEST_TMPDIR/gardener.log"
  bonsai_dispatch_gardener '{}' "$log"
  sleep 0.5
  grep -q "stdout-line" "$log"
  grep -q "stderr-line" "$log"
}

@test "dispatch: returns nonzero if 'claude' binary is missing" {
  source "$BONSAI_PLUGIN_ROOT/lib/dispatch.sh"
  rm -f "$STUB_DIR/claude"
  # Restrict PATH so a system-installed real `claude` doesn't satisfy
  # command -v inside the function.
  PATH="$STUB_DIR:/usr/bin:/bin" run bonsai_dispatch_gardener '{}' "/tmp/log.txt"
  [ "$status" -ne 0 ]
}
