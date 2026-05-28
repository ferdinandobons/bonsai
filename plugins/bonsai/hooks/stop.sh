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
source "$LIB_DIR/signal.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/lock.sh"
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

  # 4. Adaptive throttle. If code changed since the last run, use the short
  # cadence; if nothing changed (idle / conversational turn), use the longer
  # idle cadence — strategic/workflow observations are sampled, never dropped.
  local cur_diff_hash; cur_diff_hash="$(bonsai_signal_diff_hash "$cwd")"
  local last_diff_hash; last_diff_hash="$(bonsai_json_get "$cwd/.claude/bonsai/state.json" '.last_diff_hash')"
  local throttle_override=""
  # `-n` guard: a blank hash (both hash tools missing) must NOT match a blank
  # last_diff_hash and wrongly trigger the idle cadence.
  if [[ -n "$cur_diff_hash" && "$cur_diff_hash" == "$last_diff_hash" ]]; then
    local idle_minutes=20
    local cfg_idle="$cwd/.claude/bonsai/config.json"
    if [[ -f "$cfg_idle" ]]; then
      local iv; iv="$(jq -r '.throttle_idle_minutes // 20' "$cfg_idle" 2>/dev/null)"
      [[ "$iv" =~ ^[0-9]+$ ]] && idle_minutes="$iv"
    fi
    throttle_override="$idle_minutes"
  fi
  if ! CLAUDE_PROJECT_DIR="$cwd" bonsai_quota_throttle_ok "$cwd" "$throttle_override"; then
    bonsai_log INFO "stop: throttled (override=${throttle_override:-config}), skip"
    exit 0
  fi

  # 5. Caps gate
  if ! CLAUDE_PROJECT_DIR="$cwd" bonsai_quota_caps_ok; then
    bonsai_log INFO "stop: quota cap reached, skip"
    exit 0
  fi

  # 5b. Concurrency gate. Acquire the per-project lock; if another gardener is
  # running (parallel session or racing Stop hook), skip rather than spawn a
  # second one that races on quota.json/state.json/branch-id. The lock is
  # released by the detached gardener on exit; a stale lock is reclaimed.
  local lock_dir; lock_dir="$(bonsai_lock_path "$cwd")"
  if ! bonsai_lock_acquire "$lock_dir"; then
    bonsai_log INFO "stop: gardener already running for this project, skip"
    exit 0
  fi

  # 6. Capture the PREVIOUS last_run_iso BEFORE we overwrite it — the gardener's
  # observation window starts at the prior run, not now.
  local state_file="$cwd/.claude/bonsai/state.json"
  local last_run_iso; last_run_iso="$(bonsai_json_get "$state_file" '.last_run_iso')"
  [[ -z "$last_run_iso" ]] && last_run_iso="1970-01-01T00:00:00Z"

  # Update last_run + record run event BEFORE spawning so a second Stop hook
  # firing immediately (e.g. CC retrying) sees a fresh last_run and the
  # throttle gate blocks it.
  bonsai_quota_update_last_run "$cwd" "$cur_diff_hash"
  bonsai_quota_record_event "run" "$cwd"

  # 7. Build the prompt input for the gardener
  local now; now="$(bonsai_now_iso)"
  local hashes; hashes="$(jq -c '.dedup_hashes // []' "$state_file" 2>/dev/null || printf '[]')"
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

  # 7b. Pre-slice the transcript: real sessions can exceed 1MB / the Sonnet
  # context window, making the gardener burn turns reading instead of triaging.
  # Slice to the last N lines (config: transcript_tail_lines, default 200).
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

  # 7c. Structured git diff as primary detection context (bounded so we never
  # blow the prompt). Empty for non-git dirs — the gardener falls back to the
  # transcript.
  local git_diff=""
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Exclude .claude/bonsai (gardener bookkeeping) — consistent with signal.sh.
    git_diff="$(git -C "$cwd" diff HEAD -- . ':!.claude/bonsai' 2>/dev/null | head -c 60000)"
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
    --arg git_diff "$git_diff" \
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
      "trimmed_anti_patterns": $trimmed,
      "git_diff": $git_diff
    }')"

  # 8. Spawn the gardener in the background. Log goes to plugin-data so the
  # user can inspect failures via:
  #   cat ~/.claude/plugins/data/bonsai-bonsai/logs/gardener-*.log
  local log_file
  log_file="$CLAUDE_PLUGIN_DATA/logs/gardener-$(date -u +%Y%m%dT%H%M%SZ).log"
  if ! bonsai_dispatch_gardener "$prompt_input" "$log_file" "$lock_dir"; then
    bonsai_log ERROR "stop.sh: bonsai_dispatch_gardener failed (is 'claude' on PATH?)"
    # Nothing was spawned, so release the lock now instead of waiting for the
    # staleness backstop — otherwise the project would be blocked for 15 min.
    bonsai_lock_release "$lock_dir"
  fi

  # 9. Exit silently — CC's Stop hook schema does not allow additionalContext,
  # so we just return success. The gardener runs detached and writes to
  # .claude/bonsai/branches/ asynchronously.
  exit 0
}

main
# shellcheck disable=SC2317
# Belt-and-suspenders: main() always exits explicitly, but guarantee a success
# exit if a future edit returns instead — the Stop hook must never leak a
# nonzero exit to CC.
exit 0
