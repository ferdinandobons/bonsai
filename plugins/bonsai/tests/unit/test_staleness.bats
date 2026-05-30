#!/usr/bin/env bats

load '../helpers/setup'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
  source_lib staleness.sh
}
teardown() { teardown_sandbox; }

# Write a branch file with explicit created / severity / status / evidence_ref /
# stale flag. `stale` arg of "none" omits the key entirely.
mk_branch() {
  local id="$1" sev="$2" st="$3" created="$4" ev="$5" stale="${6:-none}"
  local dir="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'id: %s\n' "$id"
    printf 'created: %s\n' "$created"
    printf 'lens: technical\n'
    printf 'severity: %s\n' "$sev"
    printf 'status: %s\n' "$st"
    printf 'title: "T %s"\n' "$id"
    printf 'evidence_ref: "%s"\n' "$ev"
    printf 'dedup_hash: h%s\n' "$id"
    [ "$stale" != "none" ] && printf 'stale: %s\n' "$stale"
    printf -- '---\n'
    printf 'body\n'
  } > "$dir/$id-x.md"
  printf '%s' "$dir/$id-x.md"
}

# Touch a path to "now" (default) or backdate N days (BSD vs GNU).
touch_file() {
  local f="$1" days_old="${2:-0}"
  mkdir -p "$(dirname "$f")"
  : > "$f"
  if [ "$days_old" -gt 0 ]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      touch -t "$(date -u -v-${days_old}d +%Y%m%d%H%M.%S)" "$f"
    else
      touch -d "$days_old days ago" "$f"
    fi
  fi
}

# --- bonsai_staleness_evidence_path ---

@test "staleness: evidence_path strips a trailing :NN line suffix" {
  run bonsai_staleness_evidence_path 'src/cache.ts:42'
  [ "$status" -eq 0 ]
  [ "$output" = "src/cache.ts" ]
}

@test "staleness: evidence_path strips a trailing :NN:NN line:col suffix" {
  run bonsai_staleness_evidence_path 'src/a.ts:42:5'
  [ "$status" -eq 0 ]
  [ "$output" = "src/a.ts" ]
}

@test "staleness: evidence_path passes a bare path through unchanged" {
  run bonsai_staleness_evidence_path 'src/no-line.ts'
  [ "$status" -eq 0 ]
  [ "$output" = "src/no-line.ts" ]
}

@test "staleness: evidence_path rejects the transcript sentinel" {
  run bonsai_staleness_evidence_path 'transcript'
  [ "$status" -ne 0 ]
}

@test "staleness: evidence_path rejects the git diff sentinel" {
  run bonsai_staleness_evidence_path 'git diff'
  [ "$status" -ne 0 ]
}

@test "staleness: evidence_path rejects an absolute path" {
  run bonsai_staleness_evidence_path '/abs/path.ts:1'
  [ "$status" -ne 0 ]
}

@test "staleness: evidence_path rejects a parent-dir escape" {
  run bonsai_staleness_evidence_path '../escape.ts:1'
  [ "$status" -ne 0 ]
}

@test "staleness: evidence_path rejects an empty ref" {
  run bonsai_staleness_evidence_path ''
  [ "$status" -ne 0 ]
}

# --- bonsai_staleness_is_stale ---

@test "staleness: is_stale TRUE when evidence file is newer than created" {
  local b; b="$(mk_branch 2026-05-29-001 critical open '2020-01-01T00:00:00Z' 'foo.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/foo.txt"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -eq 0 ]
}

@test "staleness: is_stale FALSE when evidence file is older than created" {
  local b; b="$(mk_branch 2026-05-29-002 critical open '2099-01-01T00:00:00Z' 'foo.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/foo.txt"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

@test "staleness: is_stale FALSE inside the grace window" {
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local b; b="$(mk_branch 2026-05-29-003 critical open "$now" 'foo.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/foo.txt"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

@test "staleness: is_stale FALSE for the transcript sentinel regardless of files" {
  local b; b="$(mk_branch 2026-05-29-004 critical open '2020-01-01T00:00:00Z' 'transcript')"
  touch_file "$CLAUDE_PROJECT_DIR/transcript"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

@test "staleness: is_stale FALSE for the git diff sentinel" {
  local b; b="$(mk_branch 2026-05-29-005 critical open '2020-01-01T00:00:00Z' 'git diff')"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

@test "staleness: is_stale FALSE when the evidence file is missing (deleted != changed)" {
  local b; b="$(mk_branch 2026-05-29-006 critical open '2020-01-01T00:00:00Z' 'gone.txt:9')"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

@test "staleness: is_stale FALSE (fail-open) on a malformed created timestamp" {
  local b; b="$(mk_branch 2026-05-29-007 critical open 'not-a-date' 'foo.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/foo.txt"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

@test "staleness: is_stale rejects an absolute evidence_ref even if that file changed" {
  local b; b="$(mk_branch 2026-05-29-008 critical open '2020-01-01T00:00:00Z' '/etc/hosts:1')"
  run bonsai_staleness_is_stale "$CLAUDE_PROJECT_DIR" "$b"
  [ "$status" -ne 0 ]
}

# --- bonsai_staleness_run (scope + demote-not-archive) ---

@test "staleness: run flags ONLY the open critical, leaves normal/kept and statuses intact" {
  local bc; bc="$(mk_branch 2026-05-29-101 critical open    '2020-01-01T00:00:00Z' 'crit.txt:1')"
  local bn; bn="$(mk_branch 2026-05-29-102 normal   open    '2020-01-01T00:00:00Z' 'norm.txt:1')"
  local bk; bk="$(mk_branch 2026-05-29-103 critical kept    '2020-01-01T00:00:00Z' 'kept.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/crit.txt"
  touch_file "$CLAUDE_PROJECT_DIR/norm.txt"
  touch_file "$CLAUDE_PROJECT_DIR/kept.txt"

  run bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]

  run bonsai_branches_is_stale_flag "$bc"; [ "$status" -eq 0 ]
  run bonsai_branches_is_stale_flag "$bn"; [ "$status" -ne 0 ]
  run bonsai_branches_is_stale_flag "$bk"; [ "$status" -ne 0 ]

  grep -q '^status: open$' "$bc"
  grep -q '^status: open$' "$bn"
  grep -q '^status: kept$' "$bk"
}

@test "staleness: run is idempotent and leaves no .tmp file" {
  local bc; bc="$(mk_branch 2026-05-29-110 critical open '2020-01-01T00:00:00Z' 'crit.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/crit.txt"
  bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  run grep -c '^stale: true$' "$bc"
  [ "$output" = "1" ]
  run bash -c "ls $CLAUDE_PROJECT_DIR/.claude/bonsai/branches/*.tmp.* 2>/dev/null"
  [ -z "$output" ]
}

@test "staleness: run re-arms a flagged critical when evidence changes AGAIN" {
  # Backdate created far in the past so the first sweep flags it.
  local b; b="$(mk_branch 2026-05-29-120 critical open '2020-01-01T00:00:00Z' 'crit.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/crit.txt"
  bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  run bonsai_branches_is_stale_flag "$b"; [ "$status" -eq 0 ]
  grep -q '^stale_at: ' "$b"

  # Force the watermark to the past so any touch beats stale_at + grace, then
  # change the evidence file AGAIN (advance its mtime to now).
  sed -i.bak 's/^stale_at: .*/stale_at: 1000000000/' "$b" && rm -f "$b.bak"
  : > "$CLAUDE_PROJECT_DIR/crit.txt"

  run bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  # Re-armed: flag cleared, no .tmp left behind.
  run bonsai_branches_is_stale_flag "$b"; [ "$status" -ne 0 ]
  run bash -c "ls $CLAUDE_PROJECT_DIR/.claude/bonsai/branches/*.tmp.* 2>/dev/null"
  [ -z "$output" ]
}

@test "staleness: re-arm leaves an unparseable stale_at (0) demoted, never churns" {
  local b; b="$(mk_branch 2026-05-29-121 critical open '2020-01-01T00:00:00Z' 'crit.txt:1')"
  touch_file "$CLAUDE_PROJECT_DIR/crit.txt"
  bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  run bonsai_branches_is_stale_flag "$b"; [ "$status" -eq 0 ]
  # Corrupt the watermark → stale_at parses as 0 → re-arm must NOT fire.
  sed -i.bak 's/^stale_at: .*/stale_at: not-a-number/' "$b" && rm -f "$b.bak"
  : > "$CLAUDE_PROJECT_DIR/crit.txt"
  run bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
  run bonsai_branches_is_stale_flag "$b"; [ "$status" -eq 0 ]
}

@test "staleness: run on a project with no branches dir is a no-op success" {
  rm -rf "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  run bonsai_staleness_run "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}
