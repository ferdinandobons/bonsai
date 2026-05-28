#!/usr/bin/env bash
set -e
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

cfg="$cwd/.claude/bonsai/config.json"
model="claude-sonnet-4-6"
[ -f "$cfg" ] && model="$(jq -r '.gardener_model' "$cfg")"

# Sum actual token usage from gardener log files in the last 24h.
# Each gardener-*.log holds the claude -p result JSON with .usage fields
# (set by the headless run itself, not estimated).
#
# CC's .usage breaks input into four buckets:
#   - input_tokens:               net new (uncached) prompt tokens
#   - cache_read_input_tokens:    tokens read from prompt cache (cheaper, but real context)
#   - cache_creation_input_tokens: tokens written to cache (one-time per cache entry)
#   - output_tokens:              generation tokens
# Summing only input + output misses the cache buckets, which dominate
# subscription-credit consumption (1900x larger in observed gardener runs —
# see branch 2026-05-28-001).
gardener_log_dir="${CLAUDE_PLUGIN_DATA}/logs"
total_input_tokens=0
total_output_tokens=0
total_cache_read=0
total_cache_creation=0
cutoff=$(date -u -v-1d +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -d "1 day ago" +%Y%m%dT%H%M%SZ 2>/dev/null)
if [ -d "$gardener_log_dir" ]; then
  for log in "$gardener_log_dir"/gardener-*.log; do
    [ -f "$log" ] || continue
    fname=$(basename "$log")
    ts="${fname#gardener-}"
    ts="${ts%.log}"
    if [ -n "$cutoff" ] && [ "$ts" \< "$cutoff" ]; then continue; fi
    in_t=$(jq -r '.usage.input_tokens // 0' "$log" 2>/dev/null)
    out_t=$(jq -r '.usage.output_tokens // 0' "$log" 2>/dev/null)
    cr_t=$(jq -r '.usage.cache_read_input_tokens // 0' "$log" 2>/dev/null)
    cw_t=$(jq -r '.usage.cache_creation_input_tokens // 0' "$log" 2>/dev/null)
    [[ "$in_t" =~ ^[0-9]+$ ]] && total_input_tokens=$((total_input_tokens + in_t))
    [[ "$out_t" =~ ^[0-9]+$ ]] && total_output_tokens=$((total_output_tokens + out_t))
    [[ "$cr_t" =~ ^[0-9]+$ ]] && total_cache_read=$((total_cache_read + cr_t))
    [[ "$cw_t" =~ ^[0-9]+$ ]] && total_cache_creation=$((total_cache_creation + cw_t))
  done
fi
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
