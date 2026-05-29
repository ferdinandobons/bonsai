#!/usr/bin/env bash
set -e
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branches.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/index.sh"

id="$1"
cwd="${CLAUDE_PROJECT_DIR}"

# `|| true`: find_by_id returns nonzero when the id is unknown; without this the
# command substitution would abort under `set -e` before the friendly message.
f="$(bonsai_branches_find_by_id "$cwd" "$id" || true)"
if [ -z "$f" ]; then
  echo "ERR: observation $id not found"
  exit 0
fi

bonsai_branches_set_status "$f" "kept"
bonsai_index_regenerate "$cwd"
echo "OK"
