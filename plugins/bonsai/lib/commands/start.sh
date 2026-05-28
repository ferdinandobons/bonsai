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
  "quota": {"runs_per_day": 10, "observations_per_day": 20},
  "lenses_enabled": ["technical","strategic","workflow"],
  "auto_archive_kept_after_days": 14,
  "auto_archive_trimmed_after_days": 7,
  "transient_data_ttl_days": 7,
  "push_notifications_enabled": true,
  "max_observations_per_run": 3
}
EOF
fi

for tok in $args; do
  case "$tok" in
    --throttle=*) v="${tok#*=}"; n="${v%[mhd]}"; u="${v: -1}"; mins="$n"
      [ "$u" = "h" ] && mins=$((n*60)); [ "$u" = "d" ] && mins=$((n*1440))
      tmp=$(mktemp); jq --argjson m "$mins" '.throttle_min_minutes = $m' "$cfg" > "$tmp" && mv "$tmp" "$cfg" ;;
    --quota-runs=*) v="${tok#*=}"; tmp=$(mktemp); jq --argjson v "$v" '.quota.runs_per_day = $v' "$cfg" > "$tmp" && mv "$tmp" "$cfg" ;;
    --quota-observations=*) v="${tok#*=}"; tmp=$(mktemp); jq --argjson v "$v" '.quota.observations_per_day = $v' "$cfg" > "$tmp" && mv "$tmp" "$cfg" ;;
    --lenses=*) v="${tok#*=}"; arr=$(echo "$v" | jq -R 'split(",")'); tmp=$(mktemp); jq --argjson a "$arr" '.lenses_enabled = $a' "$cfg" > "$tmp" && mv "$tmp" "$cfg" ;;
    --model=*) v="${tok#*=}"; tmp=$(mktemp); jq --arg m "$v" '.gardener_model = $m' "$cfg" > "$tmp" && mv "$tmp" "$cfg" ;;
  esac
done

echo "OK"
