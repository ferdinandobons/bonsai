#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib signal.sh
  REPO="$BONSAI_TEST_TMP/repo"
  mkdir -p "$REPO"
}
teardown() { teardown_sandbox; }

init_repo() {
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'a\n' > f.txt && git add f.txt && git commit -qm init )
}

@test "signal: non-git dir yields a stable hash across calls" {
  run bonsai_signal_diff_hash "$REPO"
  [ "$status" -eq 0 ]
  local a="$output"
  run bonsai_signal_diff_hash "$REPO"
  [ "$output" = "$a" ]
}

@test "signal: hash changes when a tracked file is modified" {
  init_repo
  local before; before="$(bonsai_signal_diff_hash "$REPO")"
  ( cd "$REPO" && printf 'b\n' >> f.txt )
  [ "$before" != "$(bonsai_signal_diff_hash "$REPO")" ]
}

@test "signal: hash is stable when nothing changes" {
  init_repo
  local a; a="$(bonsai_signal_diff_hash "$REPO")"
  [ "$a" = "$(bonsai_signal_diff_hash "$REPO")" ]
}

@test "signal: an untracked file changes the hash" {
  init_repo
  local before; before="$(bonsai_signal_diff_hash "$REPO")"
  ( cd "$REPO" && printf 'new\n' > untracked.txt )
  [ "$before" != "$(bonsai_signal_diff_hash "$REPO")" ]
}

@test "signal: diff_stat is empty for a clean/non-git dir" {
  run bonsai_signal_diff_stat "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "signal: diff_stat reports a modified tracked file" {
  init_repo
  ( cd "$REPO" && printf 'b\n' >> f.txt )
  run bonsai_signal_diff_stat "$REPO"
  echo "$output" | grep -q "f.txt"
}
