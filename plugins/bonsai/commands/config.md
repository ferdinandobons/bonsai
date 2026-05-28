---
name: config
description: View or edit per-project Bonsai config
argument-hint: "[<key> <value>]"
arguments: [key, value]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/config.sh:*)"]
---

The user has invoked `/bonsai:config $key $value` in the current project.

```!
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" "${CLAUDE_PLUGIN_ROOT}/lib/commands/config.sh" $key $value
```

Print the helper output verbatim.
