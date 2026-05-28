---
name: rest
description: Stop Bonsai for this project (history is preserved)
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/rest.sh:*)"]
---

The user has invoked `/bonsai:rest` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/rest.sh"
```

Print to the user:

```
Bonsai is silent for this project.
Your observation log at .claude/bonsai/ is preserved.
Run /bonsai:tend to start watching again.
```

Do not perform any other action.
