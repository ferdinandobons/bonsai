#!/usr/bin/env bash
# Reusable fixture builders for tests.

# Create a minimal projects.json with given paths
fixture_projects_json() {
  local file="$CLAUDE_PLUGIN_DATA/projects.json"
  jq -n --argjson tended "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    '{"__version": 1, "tended": $tended}' > "$file"
}

# Create a minimal per-project state.json
fixture_state_json() {
  local file="$CLAUDE_PROJECT_DIR/.claude/bonsai/state.json"
  local last_run_iso="${1:-1970-01-01T00:00:00Z}"
  jq -n --arg last "$last_run_iso" \
    '{"__version": 1, "last_run_iso": $last, "dedup_hashes": []}' > "$file"
}

# Create a minimal per-project config.json
fixture_config_json() {
  local file="$CLAUDE_PROJECT_DIR/.claude/bonsai/config.json"
  cat > "$file" <<'EOF'
{
  "__version": 1,
  "gardener_model": "claude-sonnet-4-6",
  "throttle_min_minutes": 5,
  "quota": { "runs_per_day": 10, "observations_per_day": 20 },
  "lenses_enabled": ["technical", "strategic", "workflow"],
  "auto_archive_kept_after_days": 14,
  "auto_archive_trimmed_after_days": 7,
  "push_notifications_enabled": true,
  "max_observations_per_run": 3
}
EOF
}
