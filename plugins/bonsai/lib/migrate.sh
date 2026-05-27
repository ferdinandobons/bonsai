#!/usr/bin/env bash
# Schema migrations. No-op at v1. Reads __version from each JSON file under
# CLAUDE_PLUGIN_DATA/ and CLAUDE_PROJECT_DIR/.claude/bonsai/; logs WARN if > 1.

[[ -n "${_BONSAI_MIGRATE_SOURCED:-}" ]] && return 0
_BONSAI_MIGRATE_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_BONSAI_CURRENT_VERSION=1

bonsai_migrate_check() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local v
  v="$(bonsai_json_get "$file" '.__version')"
  [[ -z "$v" ]] && return 0
  if [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -gt "$_BONSAI_CURRENT_VERSION" ]]; then
    bonsai_log WARN "migrate: $file declares __version=$v, this plugin supports $_BONSAI_CURRENT_VERSION"
  fi
}

# At v1: nothing to migrate. Future versions will add per-version functions.
bonsai_migrate_run_all() {
  local project_dir="$1"
  bonsai_migrate_check "${CLAUDE_PLUGIN_DATA}/projects.json"
  bonsai_migrate_check "${CLAUDE_PLUGIN_DATA}/config.json"
  bonsai_migrate_check "${CLAUDE_PLUGIN_DATA}/quota.json"
  bonsai_migrate_check "${CLAUDE_PLUGIN_DATA}/mute.json"
  bonsai_migrate_check "$project_dir/.claude/bonsai/config.json"
  bonsai_migrate_check "$project_dir/.claude/bonsai/state.json"
  bonsai_migrate_check "$project_dir/.claude/bonsai/mute.json"
}
