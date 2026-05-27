#!/usr/bin/env bash
# Common test setup. Source this from every .bats file via:
#   load 'helpers/setup'

# Resolve plugin root (parent of tests/)
BONSAI_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BONSAI_PLUGIN_ROOT

# Per-test sandbox dirs (cleaned up in teardown)
setup_sandbox() {
  BONSAI_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/bonsai-test.XXXXXX")"
  export BONSAI_TEST_TMP
  export CLAUDE_PLUGIN_ROOT="$BONSAI_PLUGIN_ROOT"
  export CLAUDE_PLUGIN_DATA="$BONSAI_TEST_TMP/plugin-data"
  export CLAUDE_PROJECT_DIR="$BONSAI_TEST_TMP/project"
  mkdir -p "$CLAUDE_PLUGIN_DATA" "$CLAUDE_PROJECT_DIR/.claude/bonsai"
}

teardown_sandbox() {
  if [[ -n "${BONSAI_TEST_TMP:-}" && -d "$BONSAI_TEST_TMP" ]]; then
    rm -rf "$BONSAI_TEST_TMP"
  fi
}

# Source a lib script by relative path under lib/
source_lib() {
  local lib="$1"
  # shellcheck disable=SC1090
  source "$BONSAI_PLUGIN_ROOT/lib/$lib"
}
