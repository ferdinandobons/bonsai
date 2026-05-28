---
name: wake
description: Resume Bonsai after sleep (project; --global also clears global mute)
argument-hint: "[--global]"
arguments: [scope]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/wake.sh:*)"]
---

The user has invoked `/bonsai:wake $scope` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/wake.sh" $scope
```

If it printed `OK_PROJECT`, tell the user:
```
Bonsai is awake in this project. Watching resumes from the next turn.
```

If it printed `OK_GLOBAL`, tell the user:
```
Bonsai is awake (global + this project cleared). Watching resumes everywhere.
```
