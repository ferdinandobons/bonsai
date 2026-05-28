---
name: status
description: Show Bonsai status, quota, cost estimate for this project
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/status.sh:*)"]
---

The user has invoked `/bonsai:status` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/status.sh"
```

Print the output of the above block verbatim. Do not interpret or summarize it.
