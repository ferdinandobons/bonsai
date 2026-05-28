#!/usr/bin/env bash
# Background dispatch of the bonsai:gardener subagent via `claude -p` headless mode.
#
# Stop hooks can't return additionalContext and can't call SubagentDispatch,
# so the only way to trigger the gardener is a fully detached `claude` subprocess.
# We use `claude -p` (not `claude --bg`) to avoid worktree isolation under
# .claude/worktrees/, supervisor coupling that complicates teardown, and listing
# the gardener in `claude agents` UI — it's silent infrastructure.
#
# Detachment uses `nohup ... & disown` so the child survives the hook exiting,
# the user closing their interactive session, and SIGHUP through the process tree.

[[ -n "${_BONSAI_DISPATCH_SOURCED:-}" ]] && return 0
_BONSAI_DISPATCH_SOURCED=1

# Launch the gardener in the background.
# Args:
#   $1 - prompt_input (JSON string, passed to gardener via stdin)
#   $2 - log_path (file to receive stdout+stderr)
# Returns:
#   0 if the spawn succeeded (claude binary present and process started)
#   1 if the claude binary is missing
bonsai_dispatch_gardener() {
  local prompt_input="$1"
  local log_path="$2"

  if ! command -v claude >/dev/null 2>&1; then
    return 1
  fi

  # Ensure log dir exists before redirecting into it.
  local log_dir
  log_dir="$(dirname "$log_path")"
  mkdir -p "$log_dir" 2>/dev/null || true

  # nohup + disown + redirect every stream so the child survives parent exit.
  # We avoid `setsid` for portability (not on macOS by default).
  # The pipe from `printf` provides stdin to claude; we redirect the bash -c
  # subshell's stdout/stderr to the log file so we capture claude's full output.
  nohup bash -c '
    printf "%s" "$1" | claude -p \
      --agent bonsai:gardener \
      --max-turns 15 \
      --max-budget-usd 0.50 \
      --fallback-model sonnet \
      --output-format json
  ' bonsai-gardener "$prompt_input" \
    < /dev/null \
    > "$log_path" 2>&1 \
    & disown

  return 0
}
