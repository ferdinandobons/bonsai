---
name: discuss
description: Discuss a Bonsai observation in the current session
argument-hint: "<id>"
arguments: [id]
allowed-tools:
  - Read
  - Bash
---

You are now discussing a Bonsai observation in this session.

The observation file content follows:

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/branches.sh"
  f="$(bonsai_branches_find_by_id "$CLAUDE_PROJECT_DIR" "$1")"
  if [ -z "$f" ]; then
    echo "ERR: observation $1 not found"
    exit 0
  fi
  cat "$f"
' _ "$id"`

Help the user think through this. Do not jump to a solution — first surface
what they might be missing, then together decide whether to act on it, modify
it, or trim it. You have full session context; engage as a thinking partner,
not a code generator.

If the bash output started with "ERR:", surface that message and stop.
