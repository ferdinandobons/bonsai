---
name: trim
description: Mark a Bonsai observation as not useful (the gardener learns from this)
argument-hint: "<id> [reason]"
arguments: [id, reason]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/trim.sh:*)"]
---

The user has invoked `/bonsai:trim $id $reason` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/trim.sh" $id $reason
```

Tell the user:
```
Trimmed observation $id. Bonsai will avoid similar observations going forward.
```

If the helper printed an ERR line, surface that verbatim.
