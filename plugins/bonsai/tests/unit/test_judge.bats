#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() { setup_sandbox; source_lib common.sh; source_lib judge.sh; }
teardown() { teardown_sandbox; }

@test "judge: build_prompt embeds candidates, existing observations and anti-patterns" {
  local cands='[{"title":"Race in cache","tldr":"two writers"}]'
  local existing='[{"id":"2026-05-01-001","title":"Cache race","tldr":"concurrent writes"}]'
  local anti='avoid style nits'
  run bonsai_judge_build_prompt "$cands" "$existing" "$anti"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Race in cache"
  echo "$output" | grep -q "2026-05-01-001"
  echo "$output" | grep -q "avoid style nits"
  echo "$output" | grep -q "duplicate_of"
}

@test "judge: parse extracts verdicts from clean JSON" {
  local r='{"verdicts":[{"candidate_index":0,"keep":true,"severity":"low","duplicate_of":null,"reason":"ok"}]}'
  run bonsai_judge_parse "$r"
  [ "$status" -eq 0 ]
  [ "$output" = "0 true low" ]
}

@test "judge: parse tolerates a result wrapped in prose / code fences" {
  local r=$'here is the verdict:\n```json\n{"verdicts":[{"candidate_index":1,"keep":false,"severity":"normal","duplicate_of":"2026-05-01-001","reason":"dup"}]}\n```\nthanks'
  run bonsai_judge_parse "$r"
  [ "$status" -eq 0 ]
  [ "$output" = "1 false normal" ]
}

@test "judge: parse handles multiple verdicts, one line each" {
  local r='{"verdicts":[{"candidate_index":0,"keep":true,"severity":"critical","duplicate_of":null,"reason":"x"},{"candidate_index":1,"keep":false,"severity":"low","duplicate_of":null,"reason":"y"}]}'
  run bonsai_judge_parse "$r"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0 true critical" ]
  [ "${lines[1]}" = "1 false low" ]
}

@test "judge: parse on garbage returns nonzero" {
  run bonsai_judge_parse "not json at all"
  [ "$status" -ne 0 ]
}

@test "judge: prose with a stray brace before the JSON never yields a wrong verdict" {
  # A leading brace in prose can defeat the brace-isolation; the contract is
  # fail-clean (nonzero → gardener fails open), never a corrupted verdict line.
  local r='Note {x}: {"verdicts":[{"candidate_index":0,"keep":true,"severity":"low","duplicate_of":null,"reason":"ok"}]}'
  run bonsai_judge_parse "$r"
  if [ "$status" -eq 0 ]; then [ "$output" = "0 true low" ]; else [ -z "$output" ]; fi
}
