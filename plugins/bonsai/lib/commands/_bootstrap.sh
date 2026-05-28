#!/usr/bin/env bash
# Bootstrap: ensure CLAUDE_PLUGIN_ROOT, CLAUDE_PROJECT_DIR, and
# CLAUDE_PLUGIN_DATA are set. Sourced as the first line of every
# lib/commands/*.sh.
#
# Claude Code expands ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_DATA}
# when the .md command is parsed, but only exports them as environment
# variables to hook processes and MCP/LSP subprocesses — NOT to slash
# command Bash() subprocesses (see code.claude.com/docs/en/plugins-reference
# §Environment variables). The .md commands pass CLAUDE_PLUGIN_DATA
# inline as an env prefix to bridge that gap; this bootstrap provides a
# defensive fallback so the helpers also work when invoked directly
# (tests, manual debugging, or future CC versions that change behavior).
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${CLAUDE_PROJECT_DIR:=$PWD}"
: "${CLAUDE_PLUGIN_DATA:=$HOME/.claude/plugins/data/bonsai-bonsai}"
export CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA
