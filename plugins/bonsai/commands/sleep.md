---
name: sleep
description: Silence Bonsai temporarily for this project (or all projects with --global)
argument-hint: "<30m|1h|4h|1d> [--global]"
arguments: [duration, scope]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:sleep $duration $scope` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/common.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/mute.sh"
  duration="$1"
  scope="$2"
  if [ "$scope" = "--global" ]; then
    if bonsai_mute_sleep_global "$duration"; then
      echo "OK_GLOBAL"
    else
      echo "ERR: invalid duration. Use 30m, 1h, 4h, or 1d."
    fi
  else
    if bonsai_mute_sleep "$CLAUDE_PROJECT_DIR" "$duration"; then
      echo "OK_PROJECT"
    else
      echo "ERR: invalid duration. Use 30m, 1h, 4h, or 1d."
    fi
  fi
' _ "$duration" "$scope"`

If the previous line printed `OK_PROJECT`, tell the user:
```
Bonsai is sleeping for $duration in this project. Run /bonsai:wake to resume earlier.
```

If it printed `OK_GLOBAL`, tell the user:
```
Bonsai is sleeping GLOBALLY for $duration (all tended projects). Run /bonsai:wake --global to resume.
```

If it printed an ERR line, surface that message to the user verbatim.
