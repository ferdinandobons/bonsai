---
name: wake
description: Resume Bonsai after sleep (project; --global also clears global mute)
argument-hint: "[--global]"
arguments: [scope]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:wake $scope` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/common.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/mute.sh"
  scope="$1"
  if [ "$scope" = "--global" ]; then
    bonsai_mute_wake_global
    bonsai_mute_wake "$CLAUDE_PROJECT_DIR"
    echo "OK_GLOBAL"
  else
    bonsai_mute_wake "$CLAUDE_PROJECT_DIR"
    echo "OK_PROJECT"
  fi
' _ "$scope"`

If it printed `OK_PROJECT`, tell the user:
```
Bonsai is awake in this project. Watching resumes from the next turn.
```

If it printed `OK_GLOBAL`, tell the user:
```
Bonsai is awake (global + this project cleared). Watching resumes everywhere.
```
