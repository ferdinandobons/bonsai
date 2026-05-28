---
name: health
description: Show Bonsai status, quota, cost estimate for this project
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/health.sh:*)"]
---

The user has invoked `/bonsai:health` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/health.sh"
```

Print the output of the above block verbatim. Do not interpret or summarize it.
