---
name: config
description: View or edit per-project Bonsai config
argument-hint: "[<key> <value>]"
arguments: [key, value]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:config $key $value` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/common.sh"
  cfg="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  key="$1"; value="$2"
  if [ -z "$key" ]; then
    if [ -f "$cfg" ]; then
      echo "Current config ($cfg):"
      echo
      jq . "$cfg"
    else
      echo "No config — run /bonsai:tend first."
    fi
    exit 0
  fi
  if [ ! -f "$cfg" ]; then
    echo "ERR: no config — run /bonsai:tend first."
    exit 0
  fi
  case "$key" in
    gardener_model|throttle_min_minutes|max_observations_per_run|push_notifications_enabled|auto_archive_kept_after_days|auto_archive_trimmed_after_days|push_notifications_per_hour)
      ;;
    *)
      echo "ERR: unknown config key. Allowed: gardener_model, throttle_min_minutes, max_observations_per_run, push_notifications_enabled, auto_archive_kept_after_days, auto_archive_trimmed_after_days, push_notifications_per_hour"
      exit 0 ;;
  esac
  # Sanity-check the existing config FIRST. If it is already corrupt, refuse
  # to write — otherwise jq fails, tmp ends up empty, and the mv silently
  # wipes the user's config (P1-3 from the post-ship review).
  if ! jq empty "$cfg" 2>/dev/null; then
    echo "ERR: config.json is currently corrupt. Fix it by hand or delete it and re-run /bonsai:tend."
    exit 0
  fi
  tmp=$(mktemp)
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    jq --arg k "$key" --argjson v "$value" ".[\$k] = \$v" "$cfg" > "$tmp" 2>/dev/null
  elif [[ "$value" =~ ^(true|false)$ ]]; then
    jq --arg k "$key" --argjson v "$value" ".[\$k] = \$v" "$cfg" > "$tmp" 2>/dev/null
  else
    jq --arg k "$key" --arg v "$value" ".[\$k] = \$v" "$cfg" > "$tmp" 2>/dev/null
  fi
  if [ ! -s "$tmp" ] || ! jq empty "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "ERR: failed to update config (jq error). Leaving config.json untouched."
    exit 0
  fi
  mv "$tmp" "$cfg"
  echo "OK: $key = $value"
' _ "$key" "$value"`

Print the helper output verbatim.
