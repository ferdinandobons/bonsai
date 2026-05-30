#!/usr/bin/env bats
# Regression guard for the Step 5b judge-dedup harvest loop in agents/gardener.md.
#
# The gardener collects the existing-observation set the judge dedups against by
# scanning branch frontmatter. The learning-loop fix widens that predicate from
# "open" only to "open OR kept": a problem the user already accepted via
# /bonsai:done (status: kept) must still suppress a re-surfaced duplicate.
#
# The harvest loop lives inline in the gardener prompt (not a lib fn), so this
# test reproduces the EXACT loop body and asserts its behaviour as data. It is a
# pure-bash determinism check: no claude/LLM call, no network.
#
# House rules honoured:
#   - non-final assertions use [ ... ] / grep -q, never a bare [[ ... ]]
#   - portable: ERE alternation (grep -E) works on BSD/macOS and GNU/Linux
#   - fail-open: missing dir / zero matches must still yield a valid empty array

load '../helpers/setup'
load '../helpers/fixtures'

setup() { setup_sandbox; source_lib common.sh; }
teardown() { teardown_sandbox; }

# Reproduce the gardener.md Step 5b harvest loop verbatim (post-fix grep), and
# write the resulting existing.json to $1. Mirrors the prompt 1:1 so a drift in
# the prompt is caught here. Returns the loop's exit status.
_run_harvest() {
  local out_file="$1"
  out=""; first=1
  for f in "$CLAUDE_PROJECT_DIR"/.claude/bonsai/branches/*.md; do
    [ -f "$f" ] || continue
    grep -Eq "^status: (open|kept)$" "$f" || continue
    grep -Eq "^stale: true$" "$f" && continue
    id="$(sed -n "s/^id: //p" "$f" | head -1)"
    [ -n "$id" ] || continue
    title="$(sed -n "s/^title: //p" "$f" | head -1 | sed "s/^\"//; s/\"$//")"
    entry="$(jq -n --arg id "$id" --arg t "$title" "{id:\$id,title:\$t}")"
    [ $first -eq 0 ] && out="$out,"; first=0; out="$out$entry"
  done
  printf "[%s]" "$out" > "$out_file"
}

# Write a minimal branch fixture: $1=basename $2=id $3=title $4=status
# Optional $5="stale" appends a `stale: true` line (the demotion flag).
_branch() {
  local dir="$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  mkdir -p "$dir"
  printf 'id: %s\ntitle: "%s"\nstatus: %s\n' "$2" "$3" "$4" > "$dir/$1"
  if [ "${5:-}" = "stale" ]; then printf 'stale: true\n' >> "$dir/$1"; fi
}

@test "harvest: judge guard — kept observations ARE collected (the fix)" {
  _branch a.md 2026-05-30-001 "Open finding" open
  _branch b.md 2026-05-30-002 "Accepted finding" kept
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  run jq -e . "$existing"
  [ "$status" -eq 0 ]
  local n; n="$(jq 'length' "$existing")"
  [ "$n" -eq 2 ]
  run jq -e 'any(.id=="2026-05-30-001")' "$existing"
  [ "$status" -eq 0 ]
  run jq -e 'any(.id=="2026-05-30-002")' "$existing"
  [ "$status" -eq 0 ]
}

@test "harvest: stale-flagged open critical is EXCLUDED (re-emission restored)" {
  # A deterministically-demoted critical (status: open + stale: true) must NOT
  # be harvested into existing.json, otherwise the judge drops a re-observation
  # of the same bug as a duplicate of it and it can never re-emerge.
  _branch a.md 2026-05-30-001 "Fresh open finding" open
  _branch b.md 2026-05-30-002 "Demoted stale critical" open stale
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  run jq -e . "$existing"
  [ "$status" -eq 0 ]
  local n; n="$(jq 'length' "$existing")"
  [ "$n" -eq 1 ]
  run jq -e 'any(.id=="2026-05-30-001")' "$existing"
  [ "$status" -eq 0 ]
  run jq -e 'any(.id=="2026-05-30-002")' "$existing"
  [ "$status" -ne 0 ]
}

@test "harvest: predicate regression — trimmed/archived stay OUT (silence preserved)" {
  _branch a.md 2026-05-30-001 "Open finding" open
  _branch b.md 2026-05-30-002 "Accepted finding" kept
  _branch c.md 2026-05-30-003 "Dismissed finding" trimmed
  _branch d.md 2026-05-30-004 "Archived finding" archived
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  local n; n="$(jq 'length' "$existing")"
  [ "$n" -eq 2 ]
  run jq -e 'any(.id=="2026-05-30-003")' "$existing"
  [ "$status" -ne 0 ]
  run jq -e 'any(.id=="2026-05-30-004")' "$existing"
  [ "$status" -ne 0 ]
}

@test "harvest: field retention — id and title survive into existing.json" {
  _branch a.md 2026-05-30-007 "Race in updateCache" kept
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  local id title
  id="$(jq -r '.[0].id' "$existing")"
  title="$(jq -r '.[0].title' "$existing")"
  [ "$id" = "2026-05-30-007" ]
  [ "$title" = "Race in updateCache" ]
}

@test "harvest: boundary — anchored alternation, no substring false match" {
  _branch a.md 2026-05-30-001 "Bogus openish" openish
  _branch b.md 2026-05-30-002 "Bogus keptly" keptly
  _branch c.md 2026-05-30-003 "Real open" open
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  local n; n="$(jq 'length' "$existing")"
  [ "$n" -eq 1 ]
  run jq -e 'any(.id=="2026-05-30-003")' "$existing"
  [ "$status" -eq 0 ]
}

@test "harvest: portability — ERE alternation matches open and kept on this grep" {
  run bash -c 'printf "status: open\n"   | grep -Eq "^status: (open|kept)$"'
  [ "$status" -eq 0 ]
  run bash -c 'printf "status: kept\n"   | grep -Eq "^status: (open|kept)$"'
  [ "$status" -eq 0 ]
  run bash -c 'printf "status: trimmed\n" | grep -Eq "^status: (open|kept)$"'
  [ "$status" -ne 0 ]
  run bash -c 'printf "status: archived\n" | grep -Eq "^status: (open|kept)$"'
  [ "$status" -ne 0 ]
}

@test "harvest: fail-open — no branch dir yields a valid empty array, not an error" {
  rm -rf "$CLAUDE_PROJECT_DIR/.claude/bonsai/branches"
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  run cat "$existing"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  run jq -e 'length == 0' "$existing"
  [ "$status" -eq 0 ]
}

@test "harvest: fail-open — only excluded statuses present yields empty array" {
  _branch c.md 2026-05-30-003 "Dismissed" trimmed
  _branch d.md 2026-05-30-004 "Archived" archived
  local existing="$BONSAI_TEST_TMP/existing.json"
  _run_harvest "$existing"
  run cat "$existing"
  [ "$output" = "[]" ]
  run jq -e . "$existing"
  [ "$status" -eq 0 ]
}

# Source-of-truth guard: the cases above exercise _run_harvest (a 1:1 copy of the
# Step 5b loop). That copy only protects against drift if the REAL prompt still
# carries the same predicate, so assert directly against agents/gardener.md. If
# someone narrows the prompt back to `^status: open$`, or drops the F1 stale-skip,
# every behavioural test above stays green but THESE fail. $BONSAI_PLUGIN_ROOT is
# exported by helpers/setup at load time and the file always ships in-repo, so
# this is deterministic. Patterns are single-quoted ERE literals: $f/$/| are grep
# syntax, never shell-expanded here.
@test "harvest: source guard — agents/gardener.md still carries the open|kept predicate" {
  local gardener="$BONSAI_PLUGIN_ROOT/agents/gardener.md"
  [ -f "$gardener" ]
  run grep -Eq '^[[:space:]]*grep -Eq "\^status: \(open\|kept\)\$" "\$f" \|\| continue$' "$gardener"
  [ "$status" -eq 0 ]
}

@test "harvest: source guard — agents/gardener.md still excludes stale-flagged branches" {
  local gardener="$BONSAI_PLUGIN_ROOT/agents/gardener.md"
  [ -f "$gardener" ]
  run grep -Eq '^[[:space:]]*grep -Eq "\^stale: true\$" "\$f" && continue$' "$gardener"
  [ "$status" -eq 0 ]
}
