#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
}
teardown() { teardown_sandbox; }

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

@test "branches: write never overwrites an existing id (collision → reassign)" {
  # Two observations propose the SAME id (as the LLM gardener does today).
  # The second write must NOT clobber the first: it reassigns to the next free
  # id and returns the resolved path.
  local obs1='{"id":"2026-05-27-001","created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"First","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h1"}'
  local obs2='{"id":"2026-05-27-001","created_iso":"2026-05-27T21:18:00Z","lens":"technical","severity":"normal","title":"Second","tldr":"x","evidence_ref":"a","evidence_detail":"b","suggested_action":"c","action_brief":"d","related_branch_ids":[],"dedup_hash":"h2"}'
  local f1; f1="$(bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs1")"
  local f2; f2="$(bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs2")"
  # Both files exist, are distinct, and the first is untouched.
  [ -f "$f1" ]
  [ -f "$f2" ]
  [ "$f1" != "$f2" ]
  grep -q "^title: \"First\"$" "$f1"
  grep -q "^title: \"Second\"$" "$f2"
  # The reassigned file carries a different, higher id in its frontmatter
  # (not a duplicate 001).
  local id1 id2
  id1="$(bonsai_branches_read_field "$f1" "id")"
  id2="$(bonsai_branches_read_field "$f2" "id")"
  [ "$id1" = "2026-05-27-001" ]
  [ "$id2" != "2026-05-27-001" ]
  # Exactly two branch files on disk → no silent clobber.
  local count; count="$(find "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches" -name '*.md' | wc -l | tr -d ' ')"
  [ "$count" -eq 2 ]
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

@test "branches: write fails on null/missing non-id field" {
  local obs='{"id":"2026-05-27-200","title":"T","created_iso":null,"lens":"technical","severity":"normal","tldr":"x","evidence_ref":"r","evidence_detail":"d","suggested_action":"a","action_brief":"b","related_branch_ids":[],"dedup_hash":"h"}'
  run bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  [ "$status" -eq 1 ]
}

@test "branches: title containing a colon is quoted and roundtrips" {
  local obs='{"id":"2026-05-27-201","title":"Cache: invalidation bug","created_iso":"2026-05-27T00:00:00Z","lens":"technical","severity":"normal","tldr":"x","evidence_ref":"src/cache.ts:42","evidence_detail":"d","suggested_action":"a","action_brief":"b","related_branch_ids":[],"dedup_hash":"h"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f; f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-201")"
  [ -f "$f" ]
  # Frontmatter still parseable: title field on a single line, evidence_ref intact
  grep -qE '^title: "Cache: invalidation bug"$' "$f"
  grep -qE '^evidence_ref: "src/cache\.ts:42"$' "$f"
  run bonsai_branches_read_field "$f" "title"
  [ "$output" = "Cache: invalidation bug" ]
  run bonsai_branches_read_field "$f" "evidence_ref"
  [ "$output" = "src/cache.ts:42" ]
}

@test "branches: a newline in severity cannot inject extra frontmatter keys" {
  # severity is LLM-authored and written as a bare YAML scalar. A newline in it
  # must not smuggle a second frontmatter line.
  local obs; obs="$(jq -n '{
    id:"2026-05-27-310", created_iso:"2026-05-27T00:00:00Z", lens:"technical",
    severity:"normal\ninjected_key: pwned", title:"T", tldr:"x", evidence_ref:"r",
    evidence_detail:"d", suggested_action:"a", action_brief:"b",
    related_branch_ids:[], dedup_hash:"h"}')"
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f; f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-310")"
  [ -f "$f" ]
  # No smuggled key landed in the frontmatter.
  run grep -c '^injected_key:' "$f"
  [ "$output" = "0" ]
  # severity stays a valid enum value (unknown → downgraded to normal).
  run bonsai_branches_read_field "$f" "severity"
  [ "$output" = "normal" ]
}

@test "branches: a backslash in the title is escaped in the YAML scalar" {
  # JSON "C:\\\\tmp" decodes to a single backslash; the YAML writer must escape
  # it so a double-quoted-string parser doesn't read \t as a tab.
  local obs; obs="$(jq -n '{
    id:"2026-05-27-311", created_iso:"2026-05-27T00:00:00Z", lens:"technical",
    severity:"normal", title:"path C:\\tmp", tldr:"x", evidence_ref:"r",
    evidence_detail:"d", suggested_action:"a", action_brief:"b",
    related_branch_ids:[], dedup_hash:"h"}')"
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f; f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-311")"
  grep -qF 'title: "path C:\\tmp"' "$f"   # backslash doubled in the raw file
}

@test "branches: find_by_id rejects a glob id instead of matching unrelated files" {
  local obs='{"id":"2026-05-27-312","created_iso":"2026-05-27T00:00:00Z","lens":"technical","severity":"normal","title":"Real","tldr":"x","evidence_ref":"r","evidence_detail":"d","suggested_action":"a","action_brief":"b","related_branch_ids":[],"dedup_hash":"h"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  run bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "*"   # must NOT glob-match the real file
  [ "$status" -eq 1 ]
}

@test "branches: set_status rejects invalid status with log" {
  local obs='{"id":"2026-05-27-202","title":"X","created_iso":"2026-05-27T00:00:00Z","lens":"technical","severity":"normal","tldr":"x","evidence_ref":"r","evidence_detail":"d","suggested_action":"a","action_brief":"b","related_branch_ids":[],"dedup_hash":"h"}'
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs"
  local f; f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-202")"
  run bonsai_branches_set_status "$f" "frobnicate"
  [ "$status" -eq 1 ]
  grep -q "invalid status" "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
}
