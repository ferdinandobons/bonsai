---
name: mute
description: Silence Bonsai temporarily for this project (or all projects with --global)
argument-hint: "<30m|1h|4h|1d> [--global]"
arguments: [duration, scope]
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/mute.sh:*)"]
---

The user has invoked `/bonsai:mute $duration $scope` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/mute.sh" $duration $scope
```

If the previous line printed `OK_PROJECT`, tell the user:
```
Bonsai is muted for $duration in this project. Run /bonsai:unmute to resume earlier.
```

If it printed `OK_GLOBAL`, tell the user:
```
Bonsai is muted GLOBALLY for $duration (all watched projects). Run /bonsai:unmute --global to resume.
```

If it printed an ERR line, surface that message to the user verbatim.
