#!/usr/bin/env bash
set -e
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/whitelist.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/mute.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/quota.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/telemetry.sh"

cwd="${CLAUDE_PROJECT_DIR}"

active="INACTIVE"
bonsai_whitelist_is_tended "$cwd" && active="ACTIVE"

mute_status="none"
if bonsai_mute_is_muted "$cwd"; then
  rem=$(bonsai_mute_remaining_seconds "$cwd")
  mute_status="muted for $((rem/60))m"
fi

last="never"
state="$cwd/.claude/bonsai/state.json"
[ -f "$state" ] && last="$(jq -r '.last_run_iso // "never"' "$state")"

p_runs=$(bonsai_quota_count_events_24h "run" "$cwd")
p_obs=$(bonsai_quota_count_events_24h "observation" "$cwd")
g_runs=$(bonsai_quota_count_events_24h "run")
g_obs=$(bonsai_quota_count_events_24h "observation")

cfg="$(bonsai_config_file "$cwd")"
model="claude-sonnet-4-6"
[ -f "$cfg" ] && model="$(jq -r '.gardener_model' "$cfg")"

# Token usage over the last 24h, summed from the gardener logs by telemetry.sh
# (one scan, shared with the run-health stats below). claude -p's .usage splits
# input into four buckets: input (fresh), cache_read, cache_creation, output —
# the cache buckets dominate subscription-credit consumption (see branch
# 2026-05-28-001), so all four are reported.
gardener_log_dir="${CLAUDE_PLUGIN_DATA}/logs"
cutoff=$(date -u -v-1d +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -d "1 day ago" +%Y%m%dT%H%M%SZ 2>/dev/null)
read -r total_input_tokens total_cache_read total_cache_creation total_output_tokens \
  <<< "$(bonsai_telemetry_token_usage "$gardener_log_dir" "$cutoff")"
total_tokens=$((total_input_tokens + total_cache_read + total_cache_creation + total_output_tokens))

echo "Bonsai health for $cwd"
echo
echo "State:        $active  (mute: $mute_status)"
echo "Last run:     $last"
echo "Model:        $model"
echo
echo "Quota:"
echo "  per-project runs (24h):           $p_runs"
echo "  per-project observations (24h):   $p_obs"
echo "  global runs (24h):                $g_runs"
echo "  global observations (24h):        $g_obs"
echo
echo "Token usage (last 24h, all projects):"
echo "  input (fresh):       $total_input_tokens"
echo "  input (cache read):  $total_cache_read"
echo "  input (cache write): $total_cache_creation"
echo "  output:              $total_output_tokens"
echo "  total:               $total_tokens"

# Gardener run health: completed vs errored, how many hit the turn cap, and the
# peak turns used — makes any future --max-turns bump data-driven instead of
# guesswork (see branch 2026-05-28-002).
# shellcheck disable=SC2034  # g_total is read for positional alignment, not displayed
read -r g_total g_completed g_errored g_maxturns g_peak \
  <<< "$(bonsai_telemetry_gardener_stats "$gardener_log_dir" "$cutoff")"
echo
echo "Gardener runs (last 24h):"
echo "  completed:        $g_completed"
echo "  errored:          $g_errored"
echo "  hit max-turns:    $g_maxturns"
echo "  peak turns used:  $g_peak"

# Startup / execution errors. Two independent sources, both surfaced here so any
# failure is visible from `/bonsai:status` without digging through log files:
#   - Hook failures (stop.sh, remind.sh — i.e. startup/SessionStart and the Stop
#     dispatcher) are recorded in bonsai-errors.log by their ERR traps.
#   - Gardener subprocess failures live in the per-run gardener-*.log result JSON
#     and never reach bonsai-errors.log, so they're pulled separately.
echo
echo "Errors:"
err_log="${CLAUDE_PLUGIN_DATA}/logs/bonsai-errors.log"
# ISO-8601 UTC timestamps sort lexically, so a string compare bounds the 24h
# window (bonsai_log prefixes every line with bonsai_now_iso).
cutoff_iso=$(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
hook_err_count=0
hook_err_recent=""
if [ -f "$err_log" ]; then
  hook_err_count=$(awk -v c="$cutoff_iso" '$1 >= c {n++} END{print n+0}' "$err_log")
  [ "$hook_err_count" -gt 0 ] && hook_err_recent="$(awk -v c="$cutoff_iso" '$1 >= c' "$err_log" | tail -n 3)"
fi
gardener_errs="$(bonsai_telemetry_gardener_errors "$gardener_log_dir" "$cutoff" 3)"
echo "  hook errors (24h):    $hook_err_count"
echo "  gardener errors (24h): $g_errored"
if [ -n "$hook_err_recent" ] || [ -n "$gardener_errs" ]; then
  echo "  recent:"
  [ -n "$hook_err_recent" ] && printf '%s\n' "$hook_err_recent" | sed 's/^/    hook: /'
  [ -n "$gardener_errs" ] && printf '%s\n' "$gardener_errs" | sed 's/^/    gardener: /'
else
  echo "  recent:               none"
fi
