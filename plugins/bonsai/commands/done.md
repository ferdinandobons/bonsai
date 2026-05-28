---
name: done
description: Mark a Bonsai observation as addressed / accepted
argument-hint: "<id>"
arguments: [id]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/done.sh:*)"]
---

The user has invoked `/bonsai:done $id` in the current project.

```!
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" "${CLAUDE_PLUGIN_ROOT}/lib/commands/done.sh" "$id"
```

Tell the user:
```
Kept observation $id. It will auto-archive after the configured threshold.
```

If the helper printed an ERR line, surface that verbatim.
