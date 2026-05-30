#!/usr/bin/env bats
# Branch-level staleness helpers: created_epoch parsing + mark_stale/is_stale_flag.

load '../helpers/setup'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
}
teardown() { teardown_sandbox; }

mk_branch() {
  local id="$1" created="$2"
  local dir="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  mkdir -p "$dir"
  cat > "$dir/$id-x.md" <<EOF
---
id: $id
created: $created
lens: technical
severity: critical
status: open
title: "T"
evidence_ref: "e"
dedup_hash: h
---
body
EOF
  printf '%s' "$dir/$id-x.md"
}

@test "branches: created_epoch parses a canonical timestamp" {
  local b; b="$(mk_branch 2026-05-29-001 '2026-05-29T00:00:00Z')"
  run bonsai_branches_created_epoch "$b"
  [ "$status" -eq 0 ]
  [ "$output" -gt 1700000000 ]
}

@test "branches: created_epoch returns 0 (fail-open) on a malformed timestamp" {
  local b; b="$(mk_branch 2026-05-29-002 'garbage')"
  run bonsai_branches_created_epoch "$b"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "branches: mark_stale adds stale:true, keeps status open, leaves no .tmp" {
  local b; b="$(mk_branch 2026-05-29-003 '2026-05-29T00:00:00Z')"
  bonsai_branches_mark_stale "$b"
  grep -q '^stale: true$' "$b"
  grep -q '^status: open$' "$b"
  run bash -c "ls $CLAUDE_PROJECT_DIR/.claude/bonsai/branches/*.tmp.* 2>/dev/null"
  [ -z "$output" ]
}

@test "branches: mark_stale is idempotent (exactly one stale line after two calls)" {
  local b; b="$(mk_branch 2026-05-29-004 '2026-05-29T00:00:00Z')"
  bonsai_branches_mark_stale "$b"
  bonsai_branches_mark_stale "$b"
  run grep -c '^stale: true$' "$b"
  [ "$output" = "1" ]
}

@test "branches: is_stale_flag reads back true after mark_stale" {
  local b; b="$(mk_branch 2026-05-29-005 '2026-05-29T00:00:00Z')"
  run bonsai_branches_is_stale_flag "$b"
  [ "$status" -ne 0 ]
  bonsai_branches_mark_stale "$b"
  run bonsai_branches_is_stale_flag "$b"
  [ "$status" -eq 0 ]
}

@test "branches: mark_stale on a missing file returns 1" {
  run bonsai_branches_mark_stale "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/nope.md"
  [ "$status" -eq 1 ]
}

@test "branches: is_demoted_critical does NOT demote on a non-numeric now (broken clock)" {
  # F2/F3 guard: a transiently empty `date -u +%s` must not silently empty the box.
  local b; b="$(mk_branch 2026-05-29-006 '2026-05-29T00:00:00Z')"
  run bonsai_branches_is_demoted_critical "$b" 7 ""
  [ "$status" -ne 0 ]   # not demoted: fail-open keeps the critical in the box
}

@test "branches: is_demoted_critical still demotes a stale-flagged critical with a broken now" {
  # PART A (stale flag) is independent of `now`, so the guard must not disable it.
  local b; b="$(mk_branch 2026-05-29-007 '2026-05-29T00:00:00Z')"
  bonsai_branches_mark_stale "$b"
  run bonsai_branches_is_demoted_critical "$b" 7 ""
  [ "$status" -eq 0 ]
}

@test "branches: is_demoted_critical demotes an aged-out critical with a valid now" {
  local b; b="$(mk_branch 2026-05-29-008 '2000-01-01T00:00:00Z')"
  run bonsai_branches_is_demoted_critical "$b" 7 "$(date -u +%s)"
  [ "$status" -eq 0 ]
}

@test "branches: is_demoted_critical does not demote a fresh critical when TTL is off" {
  local b; b="$(mk_branch 2026-05-29-009 '2026-05-29T00:00:00Z')"
  run bonsai_branches_is_demoted_critical "$b" 0 "$(date -u +%s)"
  [ "$status" -ne 0 ]
}
