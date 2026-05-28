---
name: observe
description: Show the N most recent open observations
argument-hint: "[N=5]"
arguments: [n]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/observe.sh:*)"]
---

The user has invoked `/bonsai:observe $n` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/observe.sh" $n
```

Print the output verbatim. Do not interpret.
