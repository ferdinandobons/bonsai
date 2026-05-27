#!/usr/bin/env bash
# Rolling 24h quota + per-project throttle.

[[ -n "${_BONSAI_QUOTA_SOURCED:-}" ]] && return 0
_BONSAI_QUOTA_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_quota_file() { printf '%s/quota.json' "${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}"; }
_bonsai_state_file() { printf '%s/.claude/bonsai/state.json' "$1"; }
_bonsai_config_file() { printf '%s/.claude/bonsai/config.json' "$1"; }

_bonsai_quota_init_if_missing() {
  local file; file="$(_bonsai_quota_file)"
  [[ -f "$file" ]] && return 0
  bonsai_ensure_dir "$(dirname "$file")" || return 1
  bonsai_json_write "$file" '{"__version":1,"events":[]}'
}

# Record an event. kind: run | observation | push. scope: project path.
# Also prunes events older than 24h on every write — keeps quota.json bounded.
bonsai_quota_record_event() {
  local kind="$1"
  local scope="$2"
  _bonsai_quota_init_if_missing || return 1
  local file; file="$(_bonsai_quota_file)"
  local now; now="$(date -u +%s)"
  local cutoff=$(( now - 86400 ))
  # Prune-then-append in one jq pass so we never read stale entries again.
  # Use if-guard so callers with set -E (bats) don't trap on corrupt JSON.
  local updated=""
  if ! updated="$(jq --arg k "$kind" --arg s "$scope" \
                     --argjson e "$now" --argjson c "$cutoff" \
        '.events = ([.events[] | select(.epoch >= $c)]
                   + [{"kind":$k,"scope":$s,"epoch":$e}])' \
        "$file" 2>/dev/null)"; then
    updated=""
  fi
  if [[ -z "$updated" ]]; then
    bonsai_log ERROR "quota_record_event: corrupt quota.json at $file"
    return 1
  fi
  bonsai_json_write "$file" "$updated"
}

# Count events of kind in last 24h. Optional scope filter. Corrupt → 0.
bonsai_quota_count_events_24h() {
  local kind="$1"
  local scope="${2:-}"
  local file; file="$(_bonsai_quota_file)"
  [[ -f "$file" ]] || { printf '0'; return 0; }
  local now; now="$(date -u +%s)"
  local cutoff=$(( now - 86400 ))
  local count
  if [[ -n "$scope" ]]; then
    count="$(jq -r --arg k "$kind" --arg s "$scope" --argjson c "$cutoff" \
      '[.events[] | select(.kind==$k and .scope==$s and .epoch>=$c)] | length' \
      "$file" 2>/dev/null)"
  else
    count="$(jq -r --arg k "$kind" --argjson c "$cutoff" \
      '[.events[] | select(.kind==$k and .epoch>=$c)] | length' \
      "$file" 2>/dev/null)"
  fi
  [[ -z "$count" || "$count" == "null" ]] && count="0"
  printf '%s' "$count"
}

# Per-project throttle. Exit 0 if min interval has passed, 1 otherwise.
bonsai_quota_throttle_ok() {
  local project_dir="$1"
  local state; state="$(_bonsai_state_file "$project_dir")"
  local cfg; cfg="$(_bonsai_config_file "$project_dir")"
  local min_minutes=5
  if [[ -f "$cfg" ]]; then
    local v; v="$(bonsai_json_get "$cfg" '.throttle_min_minutes')"
    [[ -n "$v" && "$v" =~ ^[0-9]+$ ]] && min_minutes="$v"
  fi
  local now_epoch; now_epoch="$(date -u +%s)"
  local last_epoch=0
  if [[ -f "$state" ]]; then
    local iso; iso="$(bonsai_json_get "$state" '.last_run_iso')"
    if [[ -n "$iso" ]]; then
      # Cross-platform date → epoch (BSD vs GNU)
      last_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" '+%s' 2>/dev/null \
                    || date -u -d "$iso" '+%s' 2>/dev/null || echo 0)"
    else
      bonsai_log WARN "throttle_ok: state.json exists but last_run_iso missing/empty — treating as first run"
    fi
  fi
  [[ "$last_epoch" -eq 0 ]] && return 0
  local diff=$(( now_epoch - last_epoch ))
  local min_secs=$(( min_minutes * 60 ))
  [[ "$diff" -ge "$min_secs" ]]
}

# Caps check: per-project runs/observations + global runs/observations.
bonsai_quota_caps_ok() {
  local project_dir="${CLAUDE_PROJECT_DIR:-}"
  if [[ -z "$project_dir" || "$project_dir" == "/" ]]; then
    bonsai_log WARN "caps_ok: CLAUDE_PROJECT_DIR unset or '/' — per-project caps will not match real events"
    project_dir="/"
  fi
  local cfg; cfg="$(_bonsai_config_file "$project_dir")"
  local p_runs_cap=10 p_obs_cap=20
  local g_runs_cap=50 g_obs_cap=100
  if [[ -f "$cfg" ]]; then
    local v
    v="$(bonsai_json_get "$cfg" '.quota.runs_per_day')"
    [[ "$v" =~ ^[0-9]+$ ]] && p_runs_cap="$v"
    v="$(bonsai_json_get "$cfg" '.quota.observations_per_day')"
    [[ "$v" =~ ^[0-9]+$ ]] && p_obs_cap="$v"
  fi
  # Global caps can be overridden via $CLAUDE_PLUGIN_DATA/config.json
  # (spec §10: global_quota.runs_per_day / .observations_per_day).
  local global_cfg="${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}/config.json"
  if [[ -f "$global_cfg" ]]; then
    local gv
    gv="$(bonsai_json_get "$global_cfg" '.global_quota.runs_per_day')"
    [[ "$gv" =~ ^[0-9]+$ ]] && g_runs_cap="$gv"
    gv="$(bonsai_json_get "$global_cfg" '.global_quota.observations_per_day')"
    [[ "$gv" =~ ^[0-9]+$ ]] && g_obs_cap="$gv"
  fi
  local p_runs p_obs g_runs g_obs
  p_runs="$(bonsai_quota_count_events_24h "run" "$project_dir")"
  p_obs="$(bonsai_quota_count_events_24h "observation" "$project_dir")"
  g_runs="$(bonsai_quota_count_events_24h "run")"
  g_obs="$(bonsai_quota_count_events_24h "observation")"
  [[ "$p_runs" -lt "$p_runs_cap" ]] || return 1
  [[ "$p_obs"  -lt "$p_obs_cap"  ]] || return 1
  [[ "$g_runs" -lt "$g_runs_cap" ]] || return 1
  [[ "$g_obs"  -lt "$g_obs_cap"  ]] || return 1
  return 0
}

bonsai_quota_update_last_run() {
  local project_dir="$1"
  local state; state="$(_bonsai_state_file "$project_dir")"
  bonsai_ensure_dir "$(dirname "$state")" || return 1
  local now; now="$(bonsai_now_iso)"
  # Use `if`-guarded command so callers with `set -e` / `set -E` (e.g. bats)
  # don't blow up when jq legitimately fails on a corrupt state.json.
  local updated=""
  if [[ -f "$state" ]]; then
    if ! updated="$(jq --arg t "$now" '.last_run_iso = $t' "$state" 2>/dev/null)"; then
      updated=""
    fi
  fi
  if [[ -z "$updated" ]]; then
    [[ -f "$state" ]] && bonsai_log WARN "quota_update_last_run: corrupt or missing state.json, rebuilding"
    local fresh
    fresh="$(jq -n --arg t "$now" '{"__version":1,"last_run_iso":$t,"dedup_hashes":[]}')"
    bonsai_json_write "$state" "$fresh"
  else
    bonsai_json_write "$state" "$updated"
  fi
}
