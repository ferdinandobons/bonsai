#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branches.sh"

id="$1"
f="$(bonsai_branches_find_by_id "${CLAUDE_PROJECT_DIR}" "$id")"
if [ -z "$f" ]; then
  echo "ERR: observation $id not found"
  exit 0
fi
cat "$f"
