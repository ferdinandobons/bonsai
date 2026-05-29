#!/usr/bin/env bash
# bonsai reminder hook — runs on UserPromptSubmit and SessionStart.
# When the user returns to a tended project, surface a one-line nudge if there
# are open critical observations not yet shown this session. Reading stays
# manual (/bonsai:list).
#
# Like the Stop hook, this must NEVER disturb the session: every path exits 0
# with either empty output or a single control-JSON object.

LIB_DIR="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE[0]%/*}/..}/lib"
# CC exports CLAUDE_PLUGIN_DATA to hook processes; fall back for direct runs.
: "${CLAUDE_PLUGIN_DATA:=$HOME/.claude/plugins/data/bonsai-bonsai}"
export CLAUDE_PLUGIN_DATA
# shellcheck disable=SC1091
source "$LIB_DIR/common.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/whitelist.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/mute.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/branches.sh"
# shellcheck disable=SC1091
source "$LIB_DIR/reminder.sh"

# Wrap every error so the hook never breaks the session.
trap 'bonsai_log ERROR "remind.sh trap: line $LINENO ($BASH_COMMAND)"; exit 0' ERR

main() {
  local input
  input="$(cat)"
  [[ -z "$input" ]] && exit 0

  # Parse JSON. Malformed → silent exit. SessionStart and UserPromptSubmit both
  # carry cwd + session_id; fall back to the CLAUDE_PROJECT_DIR env var for cwd.
  local cwd session_id
  if ! cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; then
    bonsai_log INFO "remind.sh: malformed JSON on stdin"
    exit 0
  fi
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  [[ -z "$cwd" ]] && cwd="${CLAUDE_PROJECT_DIR:-}"
  [[ -z "$cwd" ]] && exit 0

  # 1. Whitelist gate — only tended projects.
  bonsai_whitelist_is_tended "$cwd" || exit 0

  # 2. Mute gate — global first, then per-project. A muted project is silent.
  if bonsai_mute_is_muted_global; then exit 0; fi
  if bonsai_mute_is_muted "$cwd"; then exit 0; fi

  # 3. Build the reminder line (empty unless a not-yet-surfaced critical exists).
  local line
  line="$(bonsai_reminder_emit "$cwd" "$session_id")"
  [[ -z "$line" ]] && exit 0

  # Surface as a user-visible warning; suppress the raw stdout echo so only the
  # systemMessage reaches the user.
  jq -nc --arg m "$line" '{systemMessage: $m, suppressOutput: true}'
  exit 0
}

main
# shellcheck disable=SC2317
# Belt-and-suspenders: main() always exits, but guarantee success if a future
# edit returns instead — this hook must never leak a nonzero exit to CC.
exit 0
