#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
  source_lib index.sh
}
teardown() { teardown_sandbox; }

write_obs() {
  local id="$1" sev="$2" lens="$3" title="$4"
  local obs; obs="$(jq -n --arg id "$id" --arg sev "$sev" --arg ln "$lens" --arg t "$title" '{
    id:$id, created_iso:"2026-05-27T00:00:00Z",
    lens:$ln, severity:$sev, title:$t,
    tldr:"x", evidence_ref:"r", evidence_detail:"d",
    suggested_action:"a", action_brief:"b",
    related_branch_ids:[], dedup_hash:"h"
  }')"
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs" >/dev/null
}

@test "index: regenerate builds INDEX.md from branches/" {
  write_obs "2026-05-27-001" "critical" "technical" "Race"
  write_obs "2026-05-27-002" "normal"   "strategic" "Decision"
  write_obs "2026-05-27-003" "low"      "workflow"  "Tip"

  bonsai_index_regenerate "$CLAUDE_PROJECT_DIR"
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/INDEX.md"
  [ -f "$f" ]
  grep -q "Bonsai · index" "$f"
  grep -q "Open critical" "$f"
  grep -q "Race" "$f"
  grep -q "Decision" "$f"
}

@test "index: regenerate groups by status" {
  write_obs "2026-05-27-001" "critical" "technical" "Race"
  write_obs "2026-05-27-002" "normal"   "strategic" "Decision"
  local f1; f1="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-002")"
  bonsai_branches_set_status "$f1" "kept"

  bonsai_index_regenerate "$CLAUDE_PROJECT_DIR"
  local idx="$CLAUDE_PROJECT_DIR/.claude/bonsai/INDEX.md"
  grep -q "Kept" "$idx"
}

@test "index: regenerate with no branches still creates valid INDEX.md" {
  bonsai_index_regenerate "$CLAUDE_PROJECT_DIR"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/INDEX.md" ]
}
