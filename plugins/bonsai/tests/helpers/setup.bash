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

# Poll until a file exists and is non-empty, up to ~5s. Returns 0 on success.
# Use instead of a fixed `sleep` when asserting on output written by a detached
# background process (nohup ... & disown), whose timing is nondeterministic.
wait_for_file() {
  local f="$1" i
  for i in $(seq 1 50); do [ -s "$f" ] && return 0; sleep 0.1; done
  [ -s "$f" ]
}

# Poll until a pattern appears in a file, up to ~5s. Returns 0 on match.
# Robust against partial writes: keeps polling until the content is present.
wait_for_grep() {
  local pat="$1" f="$2" i
  for i in $(seq 1 50); do grep -q "$pat" "$f" 2>/dev/null && return 0; sleep 0.1; done
  return 1
}

# Source a lib script by relative path under lib/.
# Fails loudly with context if the file isn't there yet (helps when a test is
# run before its corresponding lib has been written).
source_lib() {
  local lib_path="$BONSAI_PLUGIN_ROOT/lib/$1"
  if [[ ! -f "$lib_path" ]]; then
    echo "source_lib: $lib_path not found (has the lib been written yet?)" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$lib_path"
}
