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

err_log="${CLAUDE_PLUGIN_DATA}/logs/bonsai-errors.log"
if [ -f "$err_log" ]; then
  recent_err=$(tail -1 "$err_log")
  echo
  echo "Last error: $recent_err"
fi
