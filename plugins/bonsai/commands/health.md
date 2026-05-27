---
name: health
description: Show Bonsai status, quota, cost estimate for this project
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:health` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/common.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/whitelist.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/mute.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/quota.sh"
  cwd="$CLAUDE_PROJECT_DIR"
  active="INACTIVE"
  bonsai_whitelist_is_tended "$cwd" && active="ACTIVE"
  mute_status="none"
  if bonsai_mute_is_muted "$cwd"; then
    rem=$(bonsai_mute_remaining_seconds "$cwd")
    mute_status="muted for $((rem/60))m"
  fi
  last="never"
  state="$cwd/.claude/bonsai/state.json"
  [ -f "$state" ] && last="$(jq -r ".last_run_iso // \"never\"" "$state")"
  p_runs=$(bonsai_quota_count_events_24h "run" "$cwd")
  p_obs=$(bonsai_quota_count_events_24h "observation" "$cwd")
  g_runs=$(bonsai_quota_count_events_24h "run")
  g_obs=$(bonsai_quota_count_events_24h "observation")
  cfg="$cwd/.claude/bonsai/config.json"
  model="claude-sonnet-4-6"
  [ -f "$cfg" ] && model="$(jq -r ".gardener_model" "$cfg")"
  est_tokens=$((p_runs * 6000))
  est_cost_cents=$(( est_tokens * 3 / 10000 ))
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
  echo "Cost estimate (today, this project): ~\$0.$(printf %02d $est_cost_cents) (est. ${est_tokens} tokens)"
  err_log="$CLAUDE_PLUGIN_DATA/logs/bonsai-errors.log"
  if [ -f "$err_log" ]; then
    recent_err=$(tail -1 "$err_log")
    echo
    echo "Last error: $recent_err"
  fi
'`

Print the output of the above block verbatim. Do not interpret or summarize it.
