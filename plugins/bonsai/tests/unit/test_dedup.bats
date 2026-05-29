#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib dedup.sh
  fixture_state_json
}
teardown() { teardown_sandbox; }

@test "dedup: hash_observation is deterministic" {
  run bonsai_dedup_hash "Race condition" "src/cache.ts:42"
  local h1="$output"
  run bonsai_dedup_hash "Race condition" "src/cache.ts:42"
  [ "$output" = "$h1" ]
}

@test "dedup: hash_observation normalizes whitespace + case" {
  run bonsai_dedup_hash "  Race   Condition  " "SRC/cache.ts:42"
  local a="$output"
  run bonsai_dedup_hash "race condition" "src/cache.ts:42"
  [ "$output" = "$a" ]
}

@test "dedup: contains_hash returns false on empty state" {
  run bonsai_dedup_contains "$CLAUDE_PROJECT_DIR" "abc123"
  [ "$status" -eq 1 ]
}

@test "dedup: add then contains_hash true" {
  bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "deadbeef"
  run bonsai_dedup_contains "$CLAUDE_PROJECT_DIR" "deadbeef"
  [ "$status" -eq 0 ]
}

@test "dedup: rolling array trims to 50" {
  for i in $(seq -f "%02g" 1 60); do
    bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "hash-$i"
  done
  run jq -r '.dedup_hashes | length' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [ "$output" = "50" ]
  run jq -r '.dedup_hashes | contains(["hash-60"])' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [ "$output" = "true" ]
  run jq -r '.dedup_hashes | contains(["hash-01"])' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [ "$output" = "false" ]
}

@test "dedup: contains_hash false on corrupt state.json" {
  echo "{not valid" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  run bonsai_dedup_contains "$CLAUDE_PROJECT_DIR" "abc"
  [ "$status" -eq 1 ]
}

@test "dedup: add on corrupt state.json returns 1 and logs error" {
  echo "{not valid" > "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  run bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "abc"
  [ "$status" -eq 1 ]
  grep -q "dedup_add: corrupt" "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
}

@test "dedup: rolling window keeps newest at the tail (insertion order)" {
  for i in $(seq -f "%02g" 1 5); do
    bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "h-$i"
  done
  run jq -r '.dedup_hashes | last' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [ "$output" = "h-05" ]
}

@test "dedup: add is idempotent — same hash twice yields a single entry" {
  bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "dupe"
  bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "dupe"
  run jq -r '[.dedup_hashes[] | select(. == "dupe")] | length' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [ "$output" = "1" ]
}

@test "dedup: re-adding an existing hash moves it to the tail" {
  bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "a"
  bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "b"
  bonsai_dedup_add "$CLAUDE_PROJECT_DIR" "a"
  run jq -rc '.dedup_hashes' "$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  [ "$output" = '["b","a"]' ]
}

# Regression guard for the prompt↔library drift (obs 2026-05-28-002): the
# gardener must compute the dedup hash via the canonical library function, not a
# hand-rolled sha256 formula that can silently diverge from bonsai_dedup_hash().
@test "dedup: gardener delegates hashing to the library, no inline sha256 formula" {
  local g="$BONSAI_PLUGIN_ROOT/agents/gardener.md"
  grep -q "bonsai_dedup_hash" "$g"
  run grep -nE 'sha256\(' "$g"
  [ "$status" -ne 0 ]
}

@test "gardener: Step 6 passes the observation JSON via a file, not spliced into bash -c" {
  local g="$BONSAI_PLUGIN_ROOT/agents/gardener.md"
  # The multi-paragraph, LLM-authored observation JSON must NOT be spliced inline
  # (quotes/braces in a title would break the bash -c string or inject).
  run grep -F '"<obs_json>"' "$g"
  [ "$status" -ne 0 ]
  # It must be read back from a file instead.
  grep -q 'jq -r .dedup_hash "$obs_file"' "$g"
}
