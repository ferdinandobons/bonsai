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
#   $3 - lock_dir (optional): a per-project lock acquired by the caller; the
#        detached subshell releases it when claude exits (or is killed), so the
#        lock is held for exactly the gardener's lifetime.
# Returns:
#   0 if the spawn succeeded (claude binary present and process started)
#   1 if the claude binary is missing
bonsai_dispatch_gardener() {
  local prompt_input="$1"
  local log_path="$2"
  local lock_dir="${3:-}"

  if ! command -v claude >/dev/null 2>&1; then
    return 1
  fi

  # Ensure log dir exists before redirecting into it.
  local log_dir
  log_dir="$(dirname "$log_path")"
  mkdir -p "$log_dir" 2>/dev/null || true

  # Wall-clock guard: --max-turns caps iterations but cannot stop a hung claude
  # (network stall, model wedged). Wrap with timeout/gtimeout when available so
  # a stuck gardener can't live forever as a detached process. macOS ships
  # neither by default — there we degrade gracefully to no wall-clock cap, and
  # --max-turns remains the bound.
  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout 600"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout 600"
  fi

  # nohup + disown + redirect every stream so the child survives parent exit.
  # We avoid `setsid` for portability (not on macOS by default).
  # The pipe from `printf` provides stdin to claude; we redirect the bash -c
  # subshell's stdout/stderr to the log file so we capture claude's full output.
  # Hard limits:
  # --max-turns: PRIMARY cap on iterations. The gardener's 8-step workflow
  #   typically needs 10-15 turns of tool work even with pre-sliced input
  #   (Read transcript, Bash jq filtering, Bash find, evidence reads, Bash to
  #   write branch file, Bash to regenerate INDEX). 25 gives meaningful slack
  #   while still capping pathological loops. This is the ONLY hard cap we use.
  # --fallback-model: keeps the gardener responsive when the primary model is
  #   overloaded — graceful degradation, no hard fail.
  #
  # We intentionally do NOT set --max-budget-usd. Bonsai's target users run on
  # Claude subscription plans (Pro/Max/Team/Enterprise) where the gardener
  # consumes the included Agent SDK credit; USD numbers reported by claude -p
  # are API-equivalent estimates, not actual deductions. Capping by USD is
  # meaningless. The combination of --max-turns and the pre-sliced transcript
  # (see stop.sh transcript_tail_lines) bounds work effectively. Token usage
  # is recorded in the gardener log's .usage field for post-hoc visibility.
  # shellcheck disable=SC2016
  # The single-quoted bash -c body is intentional: "$1"/"$2" must refer to the
  # positional args passed to the nested bash subshell ($prompt_input,
  # $lock_dir), not expand at this outer shell. Same for the printf format "%s".
  # Only $timeout_cmd is interpolated by breaking out of the single quotes — it
  # is a fixed, locally-computed string (empty or "timeout 600"). The EXIT trap
  # releases the lock no matter how claude ends (normal, error, timeout, kill).
  nohup bash -c '
    ld="$2"
    cleanup() { [ -n "$ld" ] && rm -rf "$ld" 2>/dev/null; }
    trap cleanup EXIT
    printf "%s" "$1" | '"$timeout_cmd"' claude -p \
      --agent bonsai:gardener \
      --max-turns 25 \
      --fallback-model sonnet \
      --output-format json
  ' bonsai-gardener "$prompt_input" "$lock_dir" \
    < /dev/null \
    > "$log_path" 2>&1 \
    & disown

  return 0
}
