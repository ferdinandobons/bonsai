#!/usr/bin/env bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/lib/branches.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/index.sh"

id="$1"
cwd="${CLAUDE_PROJECT_DIR}"

f="$(bonsai_branches_find_by_id "$cwd" "$id")"
if [ -z "$f" ]; then
  echo "ERR: observation $id not found"
  exit 0
fi

bonsai_branches_set_status "$f" "kept"
bonsai_index_regenerate "$cwd"
echo "OK"
