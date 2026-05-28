#!/usr/bin/env bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/lib/whitelist.sh"
bonsai_whitelist_remove "${CLAUDE_PROJECT_DIR}"
echo "OK"
