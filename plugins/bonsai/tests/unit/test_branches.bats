#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
}
teardown() { teardown_sandbox; }

@test "branches: allocate_id returns date-NNN format" {
  run bonsai_branches_allocate_id "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$ ]]
}

@test "branches: allocate_id increments per same day" {
  local a; a="$(bonsai_branches_allocate_id "$CLAUDE_PROJECT_DIR")"
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  touch "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/${a}-fake.md"
  local b; b="$(bonsai_branches_allocate_id "$CLAUDE_PROJECT_DIR")"
  [ "$a" != "$b" ]
  local an="${a: -3}"
  local bn="${b: -3}"
  [ "$((10#$bn))" -eq "$((10#$an + 1))" ]
}

@test "branches: write creates file with frontmatter + body" {
  local obs='{
    "id":"2026-05-27-001",
    "created_iso":"2026-05-27T21:18:00Z",
    "lens":"technical",
    "severity":"critical",
    "title":"Race condition in updateCache",
    "tldr":"Two concurrent calls overwrite.",
    "evidence_ref":"src/cache.ts:42",
    "evidence_detail":"increment without lock",
    "suggested_action":"Use atomic increment.",
    "action_brief":"Long brief here.",
    "related_branch_ids":[],
    "dedup_hash":"abc123"
  }'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-05-27-001-race-condition-in-updatecache.md"
  [ -f "$f" ]
  grep -q "^id: 2026-05-27-001$" "$f"
  grep -q "^severity: critical$" "$f"
  grep -q "^status: open$" "$f"
  grep -q "## Action brief" "$f"
}

@test "branches: read_field extracts frontmatter value" {
  local obs='{"id":"2026-05-27-001","created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"Foo","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-05-27-001-foo.md"
  run bonsai_branches_read_field "$f" "severity"
  [ "$output" = "normal" ]
}

@test "branches: set_status updates frontmatter in place" {
  local obs='{"id":"2026-05-27-002","created_iso":"2026-05-27T21:18:00Z","lens":"workflow","severity":"low","title":"Tip","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h2"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-05-27-002-tip.md"
  bonsai_branches_set_status "$f" "trimmed"
  run bonsai_branches_read_field "$f" "status"
  [ "$output" = "trimmed" ]
}

@test "branches: find_by_id returns full path" {
  local obs='{"id":"2026-05-27-003","created_iso":"2026-05-27T21:18:00Z","lens":"strategic","severity":"normal","title":"Decision","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h3"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  run bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-003"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-05-27-003-decision.md" ]]
}

@test "branches: list_open returns only open branches" {
  local obs1='{"id":"2026-05-27-100","created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"OneOpen","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h100"}'
  local obs2='{"id":"2026-05-27-101","created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"OneKept","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h101"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs1"
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs2"
  local f2; f2="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-101")"
  bonsai_branches_set_status "$f2" "kept"
  run bonsai_branches_list_open "$CLAUDE_PROJECT_DIR"
  echo "$output" | grep -q "2026-05-27-100"
  ! echo "$output" | grep -q "2026-05-27-101"
}

@test "branches: write fails on missing id" {
  local obs='{"created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"NoID","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h"}'
  run bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  [ "$status" -eq 1 ]
}

@test "branches: write fails on null id" {
  local obs='{"id":null,"created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"NullID","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h"}'
  run bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  [ "$status" -eq 1 ]
}

@test "branches: read_field on corrupt file returns empty" {
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  echo "not valid frontmatter here" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/corrupt.md"
  run bonsai_branches_read_field "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/corrupt.md" "severity"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "branches: read_field on missing file returns 1" {
  run bonsai_branches_read_field "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/nonexistent.md" "severity"
  [ "$status" -eq 1 ]
}

@test "branches: set_status on missing file returns 1" {
  run bonsai_branches_set_status "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/nonexistent.md" "open"
  [ "$status" -eq 1 ]
}

@test "branches: find_by_id returns 1 on no match" {
  run bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-01-01-999"
  [ "$status" -eq 1 ]
}

@test "branches: list_open on empty directory returns empty" {
  run bonsai_branches_list_open "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
