#!/usr/bin/env bash
# Background dispatch of the bonsai:gardener subagent via `claude -p` headless.
#
# Stop hooks can't return additionalContext or call SubagentDispatch, so the
# only trigger is a detached `claude` subprocess. We use `claude -p` (not
# `--bg`) to avoid worktree isolation, supervisor coupling, and listing the
# gardener in `claude agents` — it's silent infrastructure. Detachment via
# `nohup ... & disown` lets the child survive hook/session exit and SIGHUP.

[[ -n "${_BONSAI_DISPATCH_SOURCED:-}" ]] && return 0
_BONSAI_DISPATCH_SOURCED=1

# Launch the gardener in the background.
# Args:
#   $1 - prompt_input (JSON string, passed to gardener via stdin)
#   $2 - log_path (file to receive stdout+stderr)
#   $3 - lock_dir (optional): a per-project lock acquired by the caller; the
#        detached subshell releases it when claude exits (or is killed), so the
#        lock is held for exactly the gardener's lifetime.
#   $4 - model (optional): the model the gardener should run on. When set, it is
#        passed as `claude -p --model <model>` so the configured `gardener_model`
#        actually takes effect — without it the agent always ran on the model
#        pinned in agents/gardener.md, making the config/`--model=` flag a no-op.
# Returns:
#   0 if the spawn succeeded (claude binary present and process started)
#   1 if the claude binary is missing
bonsai_dispatch_gardener() {
  local prompt_input="$1"
  local log_path="$2"
  local lock_dir="${3:-}"
  local model="${4:-}"

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

  # Hard limits:
  # --max-turns 25: PRIMARY cap. The 8-step workflow needs ~10-15 turns even on
  #   pre-sliced input; 25 gives slack while capping pathological loops.
  # --fallback-model: graceful degradation when the primary model is overloaded.
  # No --max-budget-usd: target users are on subscription plans where claude -p's
  #   USD figures are API-equivalent estimates, not real deductions, so a USD cap
  #   is meaningless. --max-turns + the pre-sliced transcript bound the work;
  #   token usage lives in the log's .usage field.
  # shellcheck disable=SC2016
  # The bash -c body is single-quoted on purpose: "$1"/"$2"/"$3" must bind to the
  # nested subshell's args ($prompt_input, $lock_dir, $model), not expand here.
  # Only $timeout_cmd is interpolated (a fixed local string). The model is passed
  # as a positional arg and turned into a `--model` flag INSIDE the subshell via
  # an args array, so an exotic model string can never break quoting or inject —
  # the same data-safety discipline the gardener prompt uses for LLM text. The
  # EXIT trap releases the lock however claude ends (normal, error, timeout,
  # kill). `setsid` is avoided for portability (absent on macOS).
  nohup bash -c '
    ld="$2"; md="$3"
    cleanup() { [ -n "$ld" ] && rm -rf "$ld" 2>/dev/null; }
    trap cleanup EXIT
    args=( -p --agent bonsai:gardener --max-turns 25 --fallback-model sonnet --output-format json )
    [ -n "$md" ] && args=( --model "$md" "${args[@]}" )
    printf "%s" "$1" | '"$timeout_cmd"' claude "${args[@]}"
  ' bonsai-gardener "$prompt_input" "$lock_dir" "$model" \
    < /dev/null \
    > "$log_path" 2>&1 \
    & disown

  return 0
}
