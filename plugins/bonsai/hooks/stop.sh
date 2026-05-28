#!/usr/bin/env bash
# bonsai Stop hook — gatekeeper.
# Reads JSON on stdin, runs the gating chain, and either exits 0 silently
# or emits a hookSpecificOutput JSON telling Claude to dispatch the gardener.
#
# Spec §9: this hook must NEVER disturb the session. Any error path exits 0.

LIB_DIR="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE[0]%/*}/..}/lib"
# CC exports CLAUDE_PLUGIN_DATA to hook processes per the plugins
# reference docs, but provide a defensive fallback for older CC versions
# or direct invocation (tests, manual debugging) — must match the canonical
# path used by the slash commands' bootstrap.
: "${CLAUDE_PLUGIN_DATA:=$HOME/.claude/plugins/data/bonsai-bonsai}"
export CLAUDE_PLUGIN_DATA
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

  # 2. Mute gate — global FIRST, then per-project
  if bonsai_mute_is_muted_global; then
    bonsai_log INFO "stop: global mute active, skip"
    exit 0
  fi
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
  # last_run_iso is what the gardener uses to bound its transcript window
  # and to filter "files modified since last run". Without it the gardener
  # falls back to reading the entire session, blowing the token budget.
  local last_run_iso
  last_run_iso="$(jq -r '.last_run_iso // "1970-01-01T00:00:00Z"' "$state_file" 2>/dev/null || printf '1970-01-01T00:00:00Z')"
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

  # Build the structured prompt_input (the gardener subagent's input).
  local prompt_input
  prompt_input="$(jq -n \
    --arg cwd "$cwd" \
    --arg sid "$session_id" \
    --arg tp "$transcript_path" \
    --arg now "$now" \
    --arg last_run "$last_run_iso" \
    --arg model "$model" \
    --argjson hashes "$hashes" \
    --argjson lenses "$lenses" \
    --arg trimmed "$trimmed_content" \
    '{
      "project_dir": $cwd,
      "session_id": $sid,
      "transcript_path": $tp,
      "last_run_iso": $last_run,
      "now_iso": $now,
      "gardener_model": $model,
      "lenses_enabled": $lenses,
      "recent_dedup_hashes": $hashes,
      "trimmed_anti_patterns": $trimmed
    }')"

  # Emit additionalContext as a natural-language instruction (not raw JSON-as-string).
  # Claude reads additionalContext as plain text appended to its context; this
  # text tells Claude what to do next. The structured prompt_input is included
  # as a fenced JSON block so Claude can pass it verbatim to the Agent tool.
  # shellcheck disable=SC2016  # backticks below are markdown fences, not subshells
  local ctx_text
  ctx_text=$'Bonsai (proactive observer) has been triggered for this session. '
  ctx_text+=$'The gating chain (whitelist + mute + throttle + quota) passed; '
  ctx_text+=$'you should now dispatch the bonsai:gardener subagent.\n\n'
  ctx_text+=$'Please call the Agent tool with:\n'
  ctx_text+=$'- subagent_type: "bonsai:gardener"\n'
  ctx_text+=$'- run_in_background: true\n'
  ctx_text+=$'- prompt: the gardener\'s prompt template, populated with this input JSON:\n\n'
  ctx_text+=$'```json\n'
  ctx_text+="$prompt_input"
  ctx_text+=$'\n```\n\n'
  ctx_text+=$'The gardener will read this input, run its triage, and emit observations to '
  ctx_text+=$'.claude/bonsai/branches/. It runs entirely in the background — do not wait '
  ctx_text+=$'for it before responding to the user.'

  jq -n --arg ctx "$ctx_text" \
    '{"hookSpecificOutput": {"hookEventName":"Stop","additionalContext": $ctx}}'
}

main
exit 0
