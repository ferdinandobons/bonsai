#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

run_remind_hook() {
  local input="$1"
  printf '%s' "$input" | bash "$BONSAI_PLUGIN_ROOT/hooks/remind.sh"
}

mk_critical() {
  local id="$1"
  local dir="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  mkdir -p "$dir"
  cat > "$dir/$id-x.md" <<EOF
---
id: $id
created: 2026-05-29T00:00:00Z
lens: technical
severity: critical
status: open
title: "T $id"
evidence_ref: "e"
dedup_hash: h$id
---
body
EOF
}

input_json() {
  jq -n --arg c "$CLAUDE_PROJECT_DIR" --arg s "${1:-sess-A}" \
    '{cwd:$c, session_id:$s}'
}

@test "remind: silent (exit 0, no output) when project not whitelisted" {
  mk_critical "2026-05-29-001"
  run run_remind_hook "$(input_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remind: silent when project is muted" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  mk_critical "2026-05-29-001"
  local future; future=$(( $(date -u +%s) + 3600 ))
  jq -n --argjson u "$future" '{"__version":1,"mute_until_epoch":$u}' \
    > "$CLAUDE_PROJECT_DIR/.claude/bonsai/mute.json"
  run run_remind_hook "$(input_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remind: silent when no critical observations" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  run run_remind_hook "$(input_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remind: emits a systemMessage JSON when a critical is pending" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  mk_critical "2026-05-29-001"
  run run_remind_hook "$(input_json)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage' >/dev/null
  # The box (multi-line) survives JSON encode/decode: title + id + CTA present.
  echo "$output" | jq -r '.systemMessage' | grep -q "critical observation awaiting"
  echo "$output" | jq -r '.systemMessage' | grep -q "2026-05-29-001"
  echo "$output" | jq -r '.systemMessage' | grep -q "/bonsai:list"
}

@test "remind: second call in same session is silent (dedup)" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  mk_critical "2026-05-29-001"
  run_remind_hook "$(input_json sess-A)" >/dev/null
  run run_remind_hook "$(input_json sess-A)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remind: malformed stdin JSON is silently ignored" {
  run bash -c 'echo "{not json" | bash "$BONSAI_PLUGIN_ROOT/hooks/remind.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remind: empty stdin is silently ignored" {
  run bash -c 'printf "" | bash "$BONSAI_PLUGIN_ROOT/hooks/remind.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remind: falls back to CLAUDE_PROJECT_DIR when cwd absent from payload" {
  fixture_projects_json "$CLAUDE_PROJECT_DIR"
  mk_critical "2026-05-29-001"
  run bash -c 'printf "%s" "{\"session_id\":\"s\"}" | bash "$BONSAI_PLUGIN_ROOT/hooks/remind.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage' >/dev/null
}
