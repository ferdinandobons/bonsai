---
name: rest
description: Stop Bonsai for this project (history is preserved)
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:rest` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/whitelist.sh"
  bonsai_whitelist_remove "$CLAUDE_PROJECT_DIR"
  echo "OK"
'`

Print to the user:

```
Bonsai is silent for this project.
Your observation log at .claude/bonsai/ is preserved.
Run /bonsai:tend to start watching again.
```

Do not perform any other action.
