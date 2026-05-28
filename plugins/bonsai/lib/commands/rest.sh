#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/whitelist.sh"
bonsai_whitelist_remove "${CLAUDE_PROJECT_DIR}"
echo "OK"
