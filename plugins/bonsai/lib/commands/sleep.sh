#!/usr/bin/env bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/mute.sh"

duration="$1"
scope="$2"

if [ "$scope" = "--global" ]; then
  if bonsai_mute_sleep_global "$duration"; then
    echo "OK_GLOBAL"
  else
    echo "ERR: invalid duration. Use 30m, 1h, 4h, or 1d."
  fi
else
  if bonsai_mute_sleep "${CLAUDE_PROJECT_DIR}" "$duration"; then
    echo "OK_PROJECT"
  else
    echo "ERR: invalid duration. Use 30m, 1h, 4h, or 1d."
  fi
fi
