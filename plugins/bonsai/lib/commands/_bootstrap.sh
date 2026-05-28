#!/usr/bin/env bash
# Bootstrap: ensure CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR are set.
# Sourced as the first line of every lib/commands/*.sh.
#
# Claude Code expands ${CLAUDE_PLUGIN_ROOT} when the .md command is parsed
# (so the script is found and executed), but does not export it into the
# subprocess. We derive it from the script's own location instead.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${CLAUDE_PROJECT_DIR:=$PWD}"
export CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR
