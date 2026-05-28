---
name: list
description: Show the N most recent open observations
argument-hint: "[N=5]"
arguments: [n]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/list.sh:*)"]
---

The user has invoked `/bonsai:list $n` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/list.sh" $n
```

Print the output verbatim. Do not interpret.
