#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/mute.sh"

scope="$1"

if [ "$scope" = "--global" ]; then
  bonsai_mute_wake_global
  bonsai_mute_wake "${CLAUDE_PROJECT_DIR}"
  echo "OK_GLOBAL"
else
  bonsai_mute_wake "${CLAUDE_PROJECT_DIR}"
  echo "OK_PROJECT"
fi
