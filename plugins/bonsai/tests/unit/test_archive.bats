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

# Backdate a file's mtime by N days (BSD vs GNU).
backdate() {
  local f="$1" days="$2"
  if [[ "$(uname)" == "Darwin" ]]; then
    touch -t "$(date -u -v-${days}d +%Y%m%d%H%M.%S)" "$f"
  else
    touch -d "$days days ago" "$f"
  fi
}

@test "archive: purge_transient deletes old sliced + gardener logs, keeps recent" {
  mkdir -p "$CLAUDE_PLUGIN_DATA/sliced" "$CLAUDE_PLUGIN_DATA/logs"
  touch "$CLAUDE_PLUGIN_DATA/sliced/sliced-old.jsonl";  backdate "$CLAUDE_PLUGIN_DATA/sliced/sliced-old.jsonl" 10
  touch "$CLAUDE_PLUGIN_DATA/logs/gardener-old.log";    backdate "$CLAUDE_PLUGIN_DATA/logs/gardener-old.log" 10
  touch "$CLAUDE_PLUGIN_DATA/sliced/sliced-new.jsonl"
  touch "$CLAUDE_PLUGIN_DATA/logs/gardener-new.log"

  bonsai_archive_purge_transient 7

  [ ! -f "$CLAUDE_PLUGIN_DATA/sliced/sliced-old.jsonl" ]
  [ ! -f "$CLAUDE_PLUGIN_DATA/logs/gardener-old.log" ]
  [ -f "$CLAUDE_PLUGIN_DATA/sliced/sliced-new.jsonl" ]
  [ -f "$CLAUDE_PLUGIN_DATA/logs/gardener-new.log" ]
}

@test "archive: purge_transient never deletes persistent bonsai logs" {
  mkdir -p "$CLAUDE_PLUGIN_DATA/logs"
  touch "$CLAUDE_PLUGIN_DATA/logs/bonsai.log";        backdate "$CLAUDE_PLUGIN_DATA/logs/bonsai.log" 365
  touch "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"; backdate "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log" 365

  bonsai_archive_purge_transient 7

  [ -f "$CLAUDE_PLUGIN_DATA/logs/bonsai.log" ]
  [ -f "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log" ]
}

@test "archive: run also purges old transient data (default ttl)" {
  mkdir -p "$CLAUDE_PLUGIN_DATA/sliced"
  touch "$CLAUDE_PLUGIN_DATA/sliced/sliced-stale.jsonl"
  backdate "$CLAUDE_PLUGIN_DATA/sliced/sliced-stale.jsonl" 30
  bonsai_archive_run "$CLAUDE_PROJECT_DIR"
  [ ! -f "$CLAUDE_PLUGIN_DATA/sliced/sliced-stale.jsonl" ]
}

@test "archive: purge_transient on missing dirs is a no-op success" {
  rm -rf "$CLAUDE_PLUGIN_DATA/sliced" "$CLAUDE_PLUGIN_DATA/logs"
  run bonsai_archive_purge_transient 7
  [ "$status" -eq 0 ]
}
