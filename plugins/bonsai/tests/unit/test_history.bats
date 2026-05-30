#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib history.sh
  REPO="$BONSAI_TEST_TMP/repo"
  mkdir -p "$REPO"
}
teardown() { teardown_sandbox; }

# A git repo with one initial commit. Caller adds the churn it wants to assert.
init_repo() {
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'a\n' > seed.txt && git add seed.txt && git commit -qm init )
}

# Three commits on auth/login.sh + one on api/x.sh, all within the window.
seed_churn() {
  ( cd "$REPO" \
    && mkdir -p auth api \
    && printf 'a\n' > auth/login.sh && git add -A && git commit -qm c1 \
    && printf 'b\n' >> auth/login.sh && git add -A && git commit -qm c2 \
    && printf 'c\n' > api/x.sh && printf 'd\n' >> auth/login.sh && git add -A && git commit -qm c3 )
}

history_file() { printf '%s/.claude/bonsai/history.json' "$REPO"; }

@test "history: non-git dir yields an empty summary and writes no file" {
  run bonsai_history_summary "$REPO" 7
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(history_file)" ]
}

@test "history: empty repo (no commits) yields an empty summary, no file" {
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t )
  run bonsai_history_summary "$REPO" 7
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(history_file)" ]
}

@test "history: a repo whose only commit is outside the window yields empty summary" {
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'a\n' > seed.txt && git add -A \
    && GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
       git commit -qm init )
  run bonsai_history_summary "$REPO" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "history: counts distinct commits per module over the window" {
  init_repo
  seed_churn
  bonsai_history_compute "$REPO" 30
  [ -f "$(history_file)" ]
  run jq -r '.modules["auth"].modifications' "$(history_file)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 3
  run jq -r '.modules["api"].modifications' "$(history_file)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 1
}

@test "history: summary names the hottest module" {
  init_repo
  seed_churn
  run bonsai_history_summary "$REPO" 30
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'auth'
  echo "$output" | grep -q '3 commits'
}

@test "history: respects the window (old commits are excluded)" {
  init_repo
  ( cd "$REPO" && mkdir -p legacy \
    && printf 'old\n' > legacy/a.sh && git add -A \
    && GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
       git commit -qm legacy )
  ( cd "$REPO" && mkdir -p auth && printf 'x\n' > auth/login.sh && git add -A && git commit -qm recent )
  run bonsai_history_summary "$REPO" 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'auth'
  run bash -c "printf '%s' \"$output\" | grep -c legacy || true"
  [ "$output" = "0" ]
}

@test "history: .claude/bonsai changes are excluded from modules" {
  init_repo
  ( cd "$REPO" && mkdir -p .claude/bonsai auth \
    && printf 's\n' > .claude/bonsai/state.json \
    && printf 'a\n' > auth/login.sh && git add -A && git commit -qm mixed )
  bonsai_history_compute "$REPO" 30
  [ -f "$(history_file)" ]
  run jq -r '.modules | keys | join(",")' "$(history_file)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'auth'
  run bash -c "jq -r '.modules | keys[]' \"$(history_file)\" | grep -c '.claude' || true"
  [ "$output" = "0" ]
}

@test "history.json is valid JSON and the write is atomic (no leftover tmp)" {
  init_repo
  seed_churn
  bonsai_history_compute "$REPO" 30
  run jq empty "$(history_file)"
  [ "$status" -eq 0 ]
  run bash -c "ls \"$REPO/.claude/bonsai/\"history.json.tmp.* 2>/dev/null | wc -l | tr -d '[:space:]'"
  [ "$output" = "0" ]
}

@test "history: caches on unchanged HEAD, refreshes on a new commit" {
  init_repo
  seed_churn
  bonsai_history_compute "$REPO" 30
  local gen1; gen1="$(jq -r '.generated_iso' "$(history_file)")"
  [ -n "$gen1" ]
  bonsai_history_compute "$REPO" 30
  local gen2; gen2="$(jq -r '.generated_iso' "$(history_file)")"
  [ "$gen1" = "$gen2" ]
  ( cd "$REPO" && printf 'more\n' >> auth/login.sh && git add -A && git commit -qm c4 )
  bonsai_history_compute "$REPO" 30
  local head_now; head_now="$(cd "$REPO" && git rev-parse HEAD)"
  [ "$(jq -r '.computed_for_head' "$(history_file)")" = "$head_now" ]
  [ "$(jq -r '.modules["auth"].modifications' "$(history_file)")" = "4" ]
}

@test "history: a window change forces a recompute even on unchanged HEAD" {
  init_repo
  seed_churn
  bonsai_history_compute "$REPO" 30
  [ "$(jq -r '.window_days' "$(history_file)")" = "30" ]
  bonsai_history_compute "$REPO" 1
  [ "$(jq -r '.window_days' "$(history_file)")" = "1" ]
}

@test "history: a cache HIT on a new UTC day re-walks and removes an aged-out index" {
  # Idle repo: same HEAD, same window, but the cached index is from a PRIOR day.
  # The window is wall-clock-relative, so the (year-2000) commit has aged out of
  # a 1-day window. A naive cache hit (head+window only) would keep serving the
  # stale "auth — 9 commits" entry; with the computed_day in the key, compute must
  # re-walk, find zero in-window commits, and remove the stale index.
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p auth && printf 'a\n' > auth/login.sh && git add -A \
    && GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
       git commit -qm old )
  local head_now; head_now="$(cd "$REPO" && git rev-parse HEAD)"
  # Seed a stale index keyed to the CURRENT head AND window (so head+window match
  # → would be a cache HIT) but with computed_day set to a prior day.
  mkdir -p "$REPO/.claude/bonsai"
  printf '{"__version":1,"computed_for_head":"%s","window_days":1,"computed_day":"20000101","generated_iso":"2000-01-01T00:00:00Z","modules":{"auth":{"modifications":9,"last_seen":"2000-01-01T00:00:00Z"}}}\n' \
    "$head_now" > "$(history_file)"
  [ -f "$(history_file)" ]
  # Same head, same window — only the day differs. Must NOT early-return; the
  # re-walk finds no in-window commit and removes the stale index.
  bonsai_history_compute "$REPO" 1
  [ ! -f "$(history_file)" ]
  run bonsai_history_summary "$REPO" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "history: a recompute that finds no in-window commits removes a stale index" {
  # Only commit is from the year 2000 — outside any window. (We do NOT try to
  # bring it INTO a window: git approxidate overflows on a huge "N days ago" and
  # behaves erratically rather than reaching back decades, so we seed the stale
  # index directly instead of relying on that.)
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p auth && printf 'a\n' > auth/login.sh && git add -A \
    && GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
       git commit -qm old )
  # Seed a stale index attributed to a DIFFERENT head so the cache check misses
  # and compute is forced to walk. The walk finds zero in-window commits (the one
  # commit is from 2000, excluded by a 1-day window), so the stale file must go.
  mkdir -p "$REPO/.claude/bonsai"
  printf '{"__version":1,"computed_for_head":"%s","window_days":1,"generated_iso":"2000-01-01T00:00:00Z","modules":{"auth":{"modifications":9,"last_seen":"2000-01-01T00:00:00Z"}}}\n' \
    0000000000000000000000000000000000000000 > "$(history_file)"
  [ -f "$(history_file)" ]
  bonsai_history_compute "$REPO" 1
  [ ! -f "$(history_file)" ]
  run bonsai_history_summary "$REPO" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "history: module count and summary bytes are bounded" {
  init_repo
  ( cd "$REPO"
    for i in $(seq 1 40); do
      mkdir -p "mod$i"
      printf 'x\n' > "mod$i/f.sh"
      git add -A && git commit -qm "m$i"
    done )
  bonsai_history_compute "$REPO" 365
  run jq -r '.modules | length' "$(history_file)"
  [ "$status" -eq 0 ]
  [ "$output" -le 25 ]
  run bonsai_history_summary "$REPO" 365
  [ "$status" -eq 0 ]
  local len; len="$(printf '%s' "$output" | wc -c | tr -d '[:space:]')"
  [ "$len" -le 1500 ]
  local lines; lines="$(printf '%s\n' "$output" | grep -c 'commits in')"
  [ "$lines" -le 8 ]
}

@test "history: root-level files aggregate under the (root) bucket" {
  init_repo
  ( cd "$REPO" && printf 'r\n' > toplevel.txt && git add -A && git commit -qm rootfile )
  run bonsai_history_summary "$REPO" 30
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '(root)'
}
