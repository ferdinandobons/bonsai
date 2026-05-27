#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib chip.sh
}
teardown() { teardown_sandbox; }

@test "chip: format produces required fields" {
  local obs='{
    "id":"2026-05-27-001",
    "lens":"technical",
    "severity":"critical",
    "title":"Race condition in updateCache",
    "tldr":"Two concurrent calls overwrite.",
    "action_brief":"Long rich brief here."
  }'
  run bonsai_chip_format "$obs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.title' >/dev/null
  echo "$output" | jq -e '.tldr' >/dev/null
  echo "$output" | jq -e '.prompt' >/dev/null
}

@test "chip: title is prefixed and truncated to 60 chars" {
  local long; long="$(printf 'a%.0s' {1..200})"
  local obs; obs="$(jq -n --arg t "$long" '{
    id:"2026-05-27-001", lens:"technical", severity:"critical",
    title:$t, tldr:"x", action_brief:"y"
  }')"
  run bonsai_chip_format "$obs"
  local title; title="$(echo "$output" | jq -r '.title')"
  [ "${#title}" -le 60 ]
  [[ "$title" == "Bonsai · "* ]]
}

@test "chip: prompt equals action_brief verbatim" {
  local obs='{
    "id":"x", "lens":"workflow", "severity":"normal",
    "title":"T", "tldr":"x", "action_brief":"BRIEF-MARKER"
  }'
  run bonsai_chip_format "$obs"
  [ "$(echo "$output" | jq -r '.prompt')" = "BRIEF-MARKER" ]
}

@test "chip: tag uses lens+severity short forms" {
  local obs='{"id":"x","lens":"strategic","severity":"normal","title":"T","tldr":"x","action_brief":"y"}'
  run bonsai_chip_format "$obs"
  local title; title="$(echo "$output" | jq -r '.title')"
  [[ "$title" == *"[STRAT · NORM]"* ]]
}

@test "chip: format fails on missing action_brief" {
  local obs='{"id":"x","lens":"technical","severity":"low","title":"T","tldr":"x"}'
  run bonsai_chip_format "$obs"
  [ "$status" -eq 1 ]
}
