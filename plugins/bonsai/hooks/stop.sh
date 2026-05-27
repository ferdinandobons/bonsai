#!/usr/bin/env bash
# bonsai Stop hook — gatekeeper.
# Reads JSON on stdin, runs the gating chain, and either exits 0 silently
# or emits a hookSpecificOutput JSON telling Claude to dispatch the gardener.
#
# Spec §9: this hook must NEVER disturb the session. Any error path exits 0.

LIB_DIR="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE[0]%/*}/..}/lib"
# shellcheck disable=SC1091
source "$LIB_DIR/common.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/whitelist.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/mute.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/quota.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/migrate.sh"

# Wrap every error so the hook never breaks the session.
trap 'bonsai_log ERROR "stop.sh trap: line $LINENO ($BASH_COMMAND)"; exit 0' ERR

main() {
  local input
  input="$(cat)"
  [[ -z "$input" ]] && exit 0

  # Parse JSON. Malformed → silent exit.
  local cwd session_id transcript_path
  if ! cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; then
    bonsai_log INFO "stop.sh: malformed JSON on stdin"
    exit 0
  fi
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"

  [[ -z "$cwd" ]] && exit 0

  # 1. Whitelist gate
  bonsai_whitelist_is_tended "$cwd" || exit 0

  # 2. Mute gate (per-project)
  if bonsai_mute_is_muted "$cwd"; then
    bonsai_log INFO "stop: project muted, skip"
    exit 0
  fi

  # 3. Schema migration (no-op v1)
  bonsai_migrate_run_all "$cwd"

  # 4. Throttle gate
  if ! CLAUDE_PROJECT_DIR="$cwd" bonsai_quota_throttle_ok "$cwd"; then
    bonsai_log INFO "stop: throttled, skip"
    exit 0
  fi

  # 5. Caps gate
  if ! CLAUDE_PROJECT_DIR="$cwd" bonsai_quota_caps_ok; then
    bonsai_log INFO "stop: quota cap reached, skip"
    exit 0
  fi

  # 6. Update last_run + record run event
  bonsai_quota_update_last_run "$cwd"
  bonsai_quota_record_event "run" "$cwd"

  # 7. Build dispatch instruction for the gardener
  local now; now="$(bonsai_now_iso)"
  local state_file="$cwd/.claude/bonsai/state.json"
  local hashes; hashes="$(jq -c '.dedup_hashes // []' "$state_file" 2>/dev/null || printf '[]')"
  local trimmed_md="$cwd/.claude/bonsai/trimmed.md"
  local trimmed_content=""
  [[ -f "$trimmed_md" ]] && trimmed_content="$(cat "$trimmed_md")"

  local cfg_file="$cwd/.claude/bonsai/config.json"
  local model="claude-sonnet-4-6"
  local lenses='["technical","strategic","workflow"]'
  if [[ -f "$cfg_file" ]]; then
    local m; m="$(bonsai_json_get "$cfg_file" '.gardener_model')"
    [[ -n "$m" ]] && model="$m"
    local l; l="$(jq -c '.lenses_enabled // ["technical","strategic","workflow"]' "$cfg_file" 2>/dev/null)"
    [[ -n "$l" ]] && lenses="$l"
  fi

  local instruction
  instruction="$(jq -n \
    --arg cwd "$cwd" \
    --arg sid "$session_id" \
    --arg tp "$transcript_path" \
    --arg now "$now" \
    --arg model "$model" \
    --argjson hashes "$hashes" \
    --argjson lenses "$lenses" \
    --arg trimmed "$trimmed_content" \
    '{
      "directive": "Dispatch the bonsai:gardener subagent in the background (run_in_background: true) with this prompt:",
      "subagent_type": "bonsai:gardener",
      "prompt_input": {
        "project_dir": $cwd,
        "session_id": $sid,
        "transcript_path": $tp,
        "now_iso": $now,
        "gardener_model": $model,
        "lenses_enabled": $lenses,
        "recent_dedup_hashes": $hashes,
        "trimmed_anti_patterns": $trimmed
      }
    }')"

  jq -n --arg ctx "$instruction" \
    '{"hookSpecificOutput": {"hookEventName":"Stop","additionalContext": $ctx}}'
}

main
exit 0
