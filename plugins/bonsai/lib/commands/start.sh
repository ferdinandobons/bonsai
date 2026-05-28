#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/whitelist.sh"

cwd="${CLAUDE_PROJECT_DIR}"
args="$*"

bonsai_whitelist_add "$cwd"
mkdir -p "$cwd/.claude/bonsai/branches" "$cwd/.claude/bonsai/archive"

state="$cwd/.claude/bonsai/state.json"
[ -f "$state" ] || echo '{"__version":1,"last_run_iso":"1970-01-01T00:00:00Z","dedup_hashes":[]}' > "$state"

cfg="$cwd/.claude/bonsai/config.json"
if [ ! -f "$cfg" ]; then
  cat > "$cfg" <<'EOF'
{
  "__version": 1,
  "gardener_model": "claude-sonnet-4-6",
  "throttle_min_minutes": 5,
  "throttle_idle_minutes": 20,
  "quota": {"runs_per_day": 10, "observations_per_day": 20},
  "lenses_enabled": ["technical","strategic","workflow"],
  "auto_archive_kept_after_days": 14,
  "auto_archive_trimmed_after_days": 7,
  "transient_data_ttl_days": 7,
  "max_observations_per_run": 3
}
EOF
fi

# Apply a jq mutation to $cfg atomically; on failure keep the old file, warn,
# and clean up the tmp. Always returns 0 so `set -e` can't abort the loop.
_set_cfg() {
  local expr="$1"; shift
  local tmp; tmp="$(mktemp 2>/dev/null)" || { echo "WARN: mktemp failed, skipping"; return 0; }
  if jq "$@" "$expr" "$cfg" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"; echo "WARN: failed to apply config update"
  fi
  return 0
}

# Optional overrides on top of the default config just written. Each is a
# --key=value flag; --throttle takes an m/h/d suffix (e.g. 10m, 2h, 1d). Numeric
# flags are validated — a bad value is skipped with a warning, not silently
# dropped. `set -f`: word-split $args without glob expansion.
set -f
for tok in $args; do
  case "$tok" in
    --throttle=*)
      v="${tok#*=}"; n="${v%[mhd]}"; u="${v: -1}"
      if ! [[ "$n" =~ ^[0-9]+$ ]]; then echo "WARN: ignoring invalid --throttle=$v"; continue; fi
      mins="$n"
      [ "$u" = "h" ] && mins=$((n*60)); [ "$u" = "d" ] && mins=$((n*1440))
      _set_cfg '.throttle_min_minutes = $m' --argjson m "$mins" ;;
    --quota-runs=*)
      v="${tok#*=}"
      if ! [[ "$v" =~ ^[0-9]+$ ]]; then echo "WARN: ignoring invalid --quota-runs=$v"; continue; fi
      _set_cfg '.quota.runs_per_day = $v' --argjson v "$v" ;;
    --quota-observations=*)
      v="${tok#*=}"
      if ! [[ "$v" =~ ^[0-9]+$ ]]; then echo "WARN: ignoring invalid --quota-observations=$v"; continue; fi
      _set_cfg '.quota.observations_per_day = $v' --argjson v "$v" ;;
    --lenses=*)
      v="${tok#*=}"; arr="$(printf '%s' "$v" | jq -R 'split(",")')"
      _set_cfg '.lenses_enabled = $a' --argjson a "$arr" ;;
    --model=*)
      v="${tok#*=}"
      _set_cfg '.gardener_model = $m' --arg m "$v" ;;
  esac
done
set +f

echo "OK"
