#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
  source_lib archive.sh
  fixture_config_json
}
teardown() { teardown_sandbox; }

make_branch() {
  local id="$1" status="$2" days_old="$3"
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  local f="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/${id}-x.md"
  cat > "$f" <<EOF
---
id: $id
created: 2026-01-01T00:00:00Z
lens: technical
severity: normal
status: $status
title: "X"
evidence_ref: "a"
dedup_hash: h
---

Body
EOF
  # Backdate mtime to simulate age (BSD vs GNU)
  if [[ "$(uname)" == "Darwin" ]]; then
    touch -t "$(date -u -v-${days_old}d +%Y%m%d%H%M.%S)" "$f"
  else
    touch -d "$days_old days ago" "$f"
  fi
}

@test "archive: kept branches older than 14 days move to archive/" {
  make_branch "2026-01-01-001" "kept" "20"
  bonsai_archive_run "$CLAUDE_PROJECT_DIR"
  [ ! -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-01-01-001-x.md" ]
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/archive/2026-01-01-001-x.md" ]
}

@test "archive: trimmed branches older than 7 days move to archive/" {
  make_branch "2026-01-02-001" "trimmed" "10"
  bonsai_archive_run "$CLAUDE_PROJECT_DIR"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/archive/2026-01-02-001-x.md" ]
}

@test "archive: open branches are never archived" {
  make_branch "2026-01-03-001" "open" "999"
  bonsai_archive_run "$CLAUDE_PROJECT_DIR"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-01-03-001-x.md" ]
}

@test "archive: recent kept/trimmed are not archived" {
  make_branch "2026-01-04-001" "kept" "2"
  make_branch "2026-01-04-002" "trimmed" "1"
  bonsai_archive_run "$CLAUDE_PROJECT_DIR"
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-01-04-001-x.md" ]
  [ -f "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches/2026-01-04-002-x.md" ]
}

@test "archive: empty branches dir is a no-op" {
  run bonsai_archive_run "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}
