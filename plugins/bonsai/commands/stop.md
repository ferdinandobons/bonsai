---
name: stop
description: Stop Bonsai for this project (history is preserved)
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/stop.sh:*)"]
---

The user has invoked `/bonsai:stop` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/stop.sh"
```

Print to the user:

```
Bonsai is silent for this project.
Your observation log at .claude/bonsai/ is preserved.
Run /bonsai:start to start watching again.
```

Do not perform any other action.
