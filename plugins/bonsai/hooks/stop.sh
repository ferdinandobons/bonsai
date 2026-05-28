#!/usr/bin/env bash
# bonsai Stop hook — gatekeeper + dispatcher.
# Reads JSON on stdin, runs the gating chain (whitelist + mute + throttle +
# quota). If all gates pass, spawns the gardener subagent via `claude -p` in
# the background (see lib/dispatch.sh) and exits silently.
#
# This hook must NEVER disturb the session. Any error path exits 0 with no
# output, so CC's Stop hook schema validator always accepts our reply.

LIB_DIR="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE[0]%/*}/..}/lib"
# CC exports CLAUDE_PLUGIN_DATA to hook processes, but provide a defensive
# fallback for direct invocation — must match the canonical path used elsewhere.
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
# shellcheck disable=SC1091
source "$LIB_DIR/dispatch.sh"

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

  # 6. Update last_run + record run event BEFORE spawning so a second Stop hook
  # firing immediately (e.g. CC retrying) sees a fresh last_run and the
  # throttle gate blocks it.
  bonsai_quota_update_last_run "$cwd"
  bonsai_quota_record_event "run" "$cwd"

  # 7. Build the prompt input for the gardener
  local now; now="$(bonsai_now_iso)"
  local state_file="$cwd/.claude/bonsai/state.json"
  local hashes; hashes="$(jq -c '.dedup_hashes // []' "$state_file" 2>/dev/null || printf '[]')"
  local last_run_iso
  last_run_iso="$(jq -r '.last_run_iso // "1970-01-01T00:00:00Z"' "$state_file" 2>/dev/null || printf '1970-01-01T00:00:00Z')"
  local trimmed_md="$cwd/.claude/bonsai/trimmed.md"
  local trimmed_content=""
  [[ -f "$trimmed_md" ]] && trimmed_content="$(cat "$trimmed_md")"

  local cfg_file="$cwd/.claude/bonsai/config.json"
  local model="claude-sonnet-4-6"
  local lenses='["technical","strategic","workflow"]'
  local transcript_tail_lines=200
  if [[ -f "$cfg_file" ]]; then
    local m; m="$(bonsai_json_get "$cfg_file" '.gardener_model')"
    [[ -n "$m" ]] && model="$m"
    local l; l="$(jq -c '.lenses_enabled // ["technical","strategic","workflow"]' "$cfg_file" 2>/dev/null)"
    [[ -n "$l" ]] && lenses="$l"
    local t; t="$(jq -r '.transcript_tail_lines // 200' "$cfg_file" 2>/dev/null)"
    [[ "$t" =~ ^[0-9]+$ ]] && transcript_tail_lines="$t"
  fi

  # 7b. Pre-slice the transcript: real session transcripts can easily exceed
  # 1MB / 200k tokens (Sonnet context window), making the gardener spend most
  # of its turns reading and filtering instead of producing observations.
  # The hook slices to the last N lines (default 200, configurable via
  # config.json's transcript_tail_lines) and writes to a temp file. The
  # gardener receives the small slice and can focus on triage + emission.
  local sliced_transcript=""
  local sliced_dir="$CLAUDE_PLUGIN_DATA/sliced"
  if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    bonsai_ensure_dir "$sliced_dir" >/dev/null 2>&1 || true
    sliced_transcript="$sliced_dir/sliced-${session_id:-unknown}-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
    # tail -N is portable and schema-agnostic; jq filtering would require knowing
    # the transcript event schema, which is an internal CC format that may change.
    tail -n "$transcript_tail_lines" "$transcript_path" > "$sliced_transcript" 2>/dev/null || true
    # If the tail produced nothing useful, fall back to passing the original path
    # (the gardener has guidance to use tail itself for large files).
    [[ ! -s "$sliced_transcript" ]] && sliced_transcript="$transcript_path"
  else
    sliced_transcript="$transcript_path"
  fi

  local prompt_input
  prompt_input="$(jq -n \
    --arg cwd "$cwd" \
    --arg sid "$session_id" \
    --arg tp "$sliced_transcript" \
    --arg original_tp "$transcript_path" \
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
      "original_transcript_path": $original_tp,
      "last_run_iso": $last_run,
      "now_iso": $now,
      "gardener_model": $model,
      "lenses_enabled": $lenses,
      "recent_dedup_hashes": $hashes,
      "trimmed_anti_patterns": $trimmed
    }')"

  # 8. Spawn the gardener in the background. Log goes to plugin-data so the
  # user can inspect failures via:
  #   cat ~/.claude/plugins/data/bonsai-bonsai/logs/gardener-*.log
  local log_file
  log_file="$CLAUDE_PLUGIN_DATA/logs/gardener-$(date -u +%Y%m%dT%H%M%SZ).log"
  if ! bonsai_dispatch_gardener "$prompt_input" "$log_file"; then
    bonsai_log ERROR "stop.sh: bonsai_dispatch_gardener failed (is 'claude' on PATH?)"
  fi

  # 9. Exit silently — CC's Stop hook schema does not allow additionalContext,
  # so we just return success. The gardener runs detached and writes to
  # .claude/bonsai/branches/ asynchronously.
  exit 0
}

main
exit 0
