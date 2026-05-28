#!/usr/bin/env bash
# Bootstrap: ensure CLAUDE_PLUGIN_ROOT, CLAUDE_PROJECT_DIR, and
# CLAUDE_PLUGIN_DATA are set. Sourced as the first line of every
# lib/commands/*.sh.
#
# Claude Code expands ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_DATA} when
# the .md command is parsed, but does not export them to slash command Bash()
# subprocesses (only to hook processes and MCP/LSP subprocesses). The .md
# commands pass CLAUDE_PLUGIN_DATA inline as an env prefix; this bootstrap
# provides a defensive fallback for direct invocation.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${CLAUDE_PROJECT_DIR:=$PWD}"
: "${CLAUDE_PLUGIN_DATA:=$HOME/.claude/plugins/data/bonsai-bonsai}"
export CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA
