#!/usr/bin/env bash
set -e
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branches.sh"

id="$1"
# `|| true`: find_by_id returns nonzero when the id is unknown; without this the
# command substitution would abort under `set -e` before the friendly message.
f="$(bonsai_branches_find_by_id "${CLAUDE_PROJECT_DIR}" "$id" || true)"
if [ -z "$f" ]; then
  echo "ERR: observation $id not found"
  exit 0
fi
cat "$f"
