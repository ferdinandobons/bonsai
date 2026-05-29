#!/usr/bin/env bats
#
# Coverage for the user-facing slash-command scripts in lib/commands/. These are
# the code users invoke directly; before this file only start.sh and config.sh
# had tests. Each command is exercised via its real script with sandbox env vars.

load '../helpers/setup'
load '../helpers/fixtures'

setup() {
  setup_sandbox
  source_lib common.sh
  source_lib branches.sh
}
teardown() { teardown_sandbox; }

cmd() { bash "$BONSAI_PLUGIN_ROOT/lib/commands/$1.sh" "${@:2}"; }

start_project() { cmd start >/dev/null; }

write_obs() {
  local id="$1" title="${2:-Obs}"
  local obs; obs="$(jq -n --arg id "$id" --arg t "$title" '{
    id:$id, created_iso:"2026-05-27T00:00:00Z", lens:"technical", severity:"normal",
    title:$t, tldr:"x", evidence_ref:"r", evidence_detail:"d",
    suggested_action:"a", action_brief:"b", related_branch_ids:[], dedup_hash:"h"
  }')"
  bonsai_branches_write "$CLAUDE_PROJECT_DIR" "$obs" >/dev/null
}

# --- status -----------------------------------------------------------------

@test "cmd status: prints the health block" {
  start_project
  run cmd status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Bonsai health"
  echo "$output" | grep -q "State:"
  echo "$output" | grep -q "Quota:"
}

@test "cmd status: reports no errors on a clean install" {
  start_project
  run cmd status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Errors:"
  echo "$output" | grep -q "hook errors (24h):    0"
  echo "$output" | grep -q "recent:               none"
}

@test "cmd status: surfaces a recent hook error from bonsai-errors.log" {
  start_project
  mkdir -p "$CLAUDE_PLUGIN_DATA/logs"
  # bonsai_log writes ERROR lines here; simulate a fresh startup/execution failure.
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s [ERROR] stop.sh trap: line 42 (boom)\n' "$ts" > "$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
  run cmd status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hook errors (24h):    1"
  echo "$output" | grep -q "hook: .*stop.sh trap: line 42 (boom)"
}

@test "cmd status: surfaces a gardener execution error" {
  start_project
  mkdir -p "$CLAUDE_PLUGIN_DATA/logs"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  jq -n '{subtype:"error_during_execution", num_turns:3, result:"model wedged", usage:{}}' \
    > "$CLAUDE_PLUGIN_DATA/logs/gardener-${ts}.log"
  run cmd status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "gardener errors (24h): 1"
  echo "$output" | grep -q "gardener: .*error_during_execution: model wedged"
}

# --- list -------------------------------------------------------------------

@test "cmd list: reports nothing when there are no open observations" {
  start_project
  run cmd list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No open observations"
}

@test "cmd list: shows an open observation" {
  start_project
  write_obs "2026-05-27-001" "MyOpenObs"
  run cmd list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MyOpenObs"
  echo "$output" | grep -q "2026-05-27-001"
}

# --- done -------------------------------------------------------------------

@test "cmd done: marks an observation kept" {
  start_project
  write_obs "2026-05-27-001"
  run cmd done "2026-05-27-001"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
  local f; f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-001")"
  run bonsai_branches_read_field "$f" "status"
  [ "$output" = "kept" ]
}

@test "cmd done: reports not found for an unknown id" {
  start_project
  run cmd done "2026-01-01-999"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not found"
}

# --- dismiss ----------------------------------------------------------------

@test "cmd dismiss: marks trimmed and records the reason in trimmed.md" {
  start_project
  write_obs "2026-05-27-001" "NoisyObs"
  run cmd dismiss "2026-05-27-001" too noisy for this project
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
  local f; f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "2026-05-27-001")"
  run bonsai_branches_read_field "$f" "status"
  [ "$output" = "trimmed" ]
  grep -q "too noisy for this project" "$CLAUDE_PROJECT_DIR/.claude/bonsai/trimmed.md"
}

@test "cmd dismiss: reports not found for an unknown id" {
  start_project
  run cmd dismiss "2026-01-01-999" whatever
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not found"
}

# --- discuss ----------------------------------------------------------------

@test "cmd discuss: prints the observation file" {
  start_project
  write_obs "2026-05-27-001" "DiscussThis"
  run cmd discuss "2026-05-27-001"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DiscussThis"
}

@test "cmd discuss: reports not found for an unknown id" {
  start_project
  run cmd discuss "2026-01-01-999"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not found"
}

# --- stop (the command, not the hook) ---------------------------------------

@test "cmd stop: unregisters the project from the whitelist" {
  source_lib whitelist.sh
  start_project
  run bonsai_whitelist_is_tended "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]                       # tended after start
  run cmd stop
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
  run bonsai_whitelist_is_tended "$CLAUDE_PROJECT_DIR"
  [ "$status" -ne 0 ]                        # no longer tended
}

# --- mute / unmute ----------------------------------------------------------

@test "cmd mute: mutes the project for a valid duration" {
  source_lib mute.sh
  start_project
  run cmd mute "30m"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK_PROJECT"
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -eq 0 ]
}

@test "cmd mute: rejects an invalid duration" {
  start_project
  run cmd mute "banana"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ERR"
}

@test "cmd unmute: clears a project mute" {
  source_lib mute.sh
  start_project
  cmd mute "30m" >/dev/null
  run cmd unmute
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK_PROJECT"
  run bonsai_mute_is_muted "$CLAUDE_PROJECT_DIR"
  [ "$status" -ne 0 ]
}
