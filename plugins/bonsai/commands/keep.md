---
name: keep
description: Mark a Bonsai observation as addressed / accepted
argument-hint: "<id>"
arguments: [id]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/keep.sh:*)"]
---

The user has invoked `/bonsai:keep $id` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/keep.sh" $id
```

Tell the user:
```
Kept observation $id. It will auto-archive after the configured threshold.
```

If the helper printed an ERR line, surface that verbatim.
