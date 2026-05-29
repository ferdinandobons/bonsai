#!/usr/bin/env bats

load '../helpers/setup'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
  source_lib reminder.sh
}
teardown() { teardown_sandbox; }

# Create a branch file with a given id / severity / status. Body is irrelevant.
mk_branch() {
  local id="$1" sev="$2" st="$3"
  local dir="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  mkdir -p "$dir"
  cat > "$dir/$id-x.md" <<EOF
---
id: $id
created: 2026-05-29T00:00:00Z
lens: technical
severity: $sev
status: $st
title: "T $id"
evidence_ref: "e"
dedup_hash: h$id
---
body
EOF
}

reminder_file() { printf '%s/.claude/bonsai/reminder.json' "$CLAUDE_PROJECT_DIR"; }

# --- bonsai_reminder_critical_ids ---

@test "reminder: critical_ids empty when no branches" {
  run bonsai_reminder_critical_ids "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reminder: critical_ids returns only open+critical, sorted" {
  mk_branch "2026-05-29-003" critical open
  mk_branch "2026-05-29-001" critical open
  mk_branch "2026-05-29-002" normal   open
  mk_branch "2026-05-29-004" low      open
  run bonsai_reminder_critical_ids "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2026-05-29-001" ]
  [ "${lines[1]}" = "2026-05-29-003" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "reminder: critical_ids excludes resolved (kept/trimmed/archived) critical" {
  mk_branch "2026-05-29-001" critical kept
  mk_branch "2026-05-29-002" critical trimmed
  mk_branch "2026-05-29-003" critical archived
  run bonsai_reminder_critical_ids "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- bonsai_reminder_message ---

@test "reminder: message is singular for 1" {
  run bonsai_reminder_message 1
  echo "$output" | grep -q "1 critical observation awaiting"
}

@test "reminder: message is plural for >1" {
  run bonsai_reminder_message 3
  echo "$output" | grep -q "3 critical observations awaiting"
}

# --- bonsai_reminder_emit (orchestrator) ---

@test "reminder: emit is silent when no critical observations" {
  mk_branch "2026-05-29-001" normal open
  mk_branch "2026-05-29-002" low    open
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(reminder_file)" ]
}

@test "reminder: emit surfaces a critical and records reminder.json" {
  mk_branch "2026-05-29-001" critical open
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "1 critical observation awaiting"
  [ -f "$(reminder_file)" ]
  [ "$(jq -r '.session_id' "$(reminder_file)")" = "sess-A" ]
  [ "$(jq -r '.notified_ids[0]' "$(reminder_file)")" = "2026-05-29-001" ]
}

@test "reminder: emit is silent on the second call in the same session" {
  mk_branch "2026-05-29-001" critical open
  bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A" >/dev/null
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reminder: emit box lists the finding id, title and call to action" {
  mk_branch "2026-05-29-001" critical open
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2026-05-29-001"
  echo "$output" | grep -q "T 2026-05-29-001"   # mk_branch sets title "T <id>"
  echo "$output" | grep -q "/bonsai:list"
  echo "$output" | grep -q "/bonsai:discuss"
}

@test "reminder: emit box shows at most 3 findings then '+N more'" {
  mk_branch "2026-05-29-001" critical open
  mk_branch "2026-05-29-002" critical open
  mk_branch "2026-05-29-003" critical open
  mk_branch "2026-05-29-004" critical open
  mk_branch "2026-05-29-005" critical open
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "5 critical observations awaiting"
  echo "$output" | grep -q "+2 more"
  # exactly three numbered finding rows
  [ "$(echo "$output" | grep -c '^  [0-9]\. ')" -eq 3 ]
  # most-recent-first: 005 listed, 001 collapsed into "+N more"
  echo "$output" | grep -q "2026-05-29-005"
}

@test "reminder: emit re-surfaces when a NEW critical appears in the same session" {
  mk_branch "2026-05-29-001" critical open
  bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A" >/dev/null
  mk_branch "2026-05-29-002" critical open
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2 critical observations awaiting"
}

@test "reminder: emit re-surfaces when the session id changes" {
  mk_branch "2026-05-29-001" critical open
  bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A" >/dev/null
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-B"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "1 critical observation awaiting"
  [ "$(jq -r '.session_id' "$(reminder_file)")" = "sess-B" ]
}

@test "reminder: emit goes silent once the critical is resolved" {
  mk_branch "2026-05-29-001" critical open
  # different session each call so dedup never suppresses; only severity/status matters
  bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-A" >/dev/null
  bonsai_branches_set_status "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-05-29-001-x.md" kept
  run bonsai_reminder_emit "$CLAUDE_PROJECT_DIR" "sess-B"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
