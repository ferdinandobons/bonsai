---
name: wake
description: Resume Bonsai after sleep
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:wake` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/mute.sh"
  bonsai_mute_wake "$CLAUDE_PROJECT_DIR"
  echo "OK"
'`

Tell the user:
```
Bonsai is awake. Watching resumes from the next turn.
```
