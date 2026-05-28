---
name: sleep
description: Silence Bonsai temporarily for this project (or all projects with --global)
argument-hint: "<30m|1h|4h|1d> [--global]"
arguments: [duration, scope]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/sleep.sh:*)"]
---

The user has invoked `/bonsai:sleep $duration $scope` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/sleep.sh" $duration $scope
```

If the previous line printed `OK_PROJECT`, tell the user:
```
Bonsai is sleeping for $duration in this project. Run /bonsai:wake to resume earlier.
```

If it printed `OK_GLOBAL`, tell the user:
```
Bonsai is sleeping GLOBALLY for $duration (all tended projects). Run /bonsai:wake --global to resume.
```

If it printed an ERR line, surface that message to the user verbatim.
