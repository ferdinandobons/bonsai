#!/usr/bin/env bash
# View or set one config key. Always exits 0 (errors are printed, not raised):
# the output is surfaced verbatim by the .md command, and a nonzero exit would
# read as a tool failure.
set -e
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"

cfg="$(bonsai_config_file "${CLAUDE_PROJECT_DIR}")"
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
  gardener_model|throttle_min_minutes|throttle_idle_minutes|max_observations_per_run|auto_archive_kept_after_days|auto_archive_trimmed_after_days|transient_data_ttl_days)
    ;;
  *)
    echo "ERR: unknown config key. Allowed: gardener_model, throttle_min_minutes, throttle_idle_minutes, max_observations_per_run, auto_archive_kept_after_days, auto_archive_trimmed_after_days, transient_data_ttl_days"
    exit 0 ;;
esac

# Type-check the value per key. Every key except gardener_model is a
# non-negative integer; reject a mismatch instead of writing a value every
# numeric consumer would silently ignore while we report "OK".
if [ "$key" != "gardener_model" ] && ! [[ "$value" =~ ^[0-9]+$ ]]; then
  echo "ERR: $key must be a non-negative integer, got: $value"
  exit 0
fi

if ! jq empty "$cfg" 2>/dev/null; then
  echo "ERR: config.json is currently corrupt. Fix it by hand or delete it and re-run /bonsai:start."
  exit 0
fi

tmp=$(mktemp)
# `|| true`: a jq failure (e.g. config is valid JSON but not an object) must not
# abort under `set -e` — the integrity check below turns it into a clean error.
if [ "$key" = "gardener_model" ]; then
  jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$cfg" > "$tmp" 2>/dev/null || true
else
  jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$cfg" > "$tmp" 2>/dev/null || true
fi

if [ ! -s "$tmp" ] || ! jq empty "$tmp" 2>/dev/null; then
  rm -f "$tmp"
  echo "ERR: failed to update config (jq error). Leaving config.json untouched."
  exit 0
fi

mv "$tmp" "$cfg"
echo "OK: $key = $value"
