#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"

cfg="${CLAUDE_PROJECT_DIR}/.claude/bonsai/config.json"
key="$1"
value="$2"

if [ -z "$key" ]; then
  if [ -f "$cfg" ]; then
    echo "Current config ($cfg):"
    echo
    jq . "$cfg"
  else
    echo "No config — run /bonsai:start first."
  fi
  exit 0
fi

if [ ! -f "$cfg" ]; then
  echo "ERR: no config — run /bonsai:start first."
  exit 0
fi

case "$key" in
  gardener_model|throttle_min_minutes|max_observations_per_run|push_notifications_enabled|auto_archive_kept_after_days|auto_archive_trimmed_after_days|push_notifications_per_hour)
    ;;
  *)
    echo "ERR: unknown config key. Allowed: gardener_model, throttle_min_minutes, max_observations_per_run, push_notifications_enabled, auto_archive_kept_after_days, auto_archive_trimmed_after_days, push_notifications_per_hour"
    exit 0 ;;
esac

if ! jq empty "$cfg" 2>/dev/null; then
  echo "ERR: config.json is currently corrupt. Fix it by hand or delete it and re-run /bonsai:start."
  exit 0
fi

tmp=$(mktemp)
if [[ "$value" =~ ^-?[0-9]+$ ]]; then
  jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$cfg" > "$tmp" 2>/dev/null
elif [[ "$value" =~ ^(true|false)$ ]]; then
  jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$cfg" > "$tmp" 2>/dev/null
else
  jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$cfg" > "$tmp" 2>/dev/null
fi

if [ ! -s "$tmp" ] || ! jq empty "$tmp" 2>/dev/null; then
  rm -f "$tmp"
  echo "ERR: failed to update config (jq error). Leaving config.json untouched."
  exit 0
fi

mv "$tmp" "$cfg"
echo "OK: $key = $value"
