---
name: unmute
description: Resume Bonsai after a mute (project; --global also clears global mute)
argument-hint: "[--global]"
arguments: [scope]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/unmute.sh:*)"]
---

The user has invoked `/bonsai:unmute $scope` in the current project.

```!
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" "${CLAUDE_PLUGIN_ROOT}/lib/commands/unmute.sh" "$scope"
```

If it printed `OK_PROJECT`, tell the user:
```
Bonsai is unmuted in this project. Watching resumes from the next turn.
```

If it printed `OK_GLOBAL`, tell the user:
```
Bonsai is unmuted (global + this project cleared). Watching resumes everywhere.
```
