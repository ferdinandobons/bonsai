---
name: sleep
description: Silence Bonsai temporarily for this project
argument-hint: "<30m|1h|4h|1d>"
arguments: [duration]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:sleep $duration` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/mute.sh"
  if bonsai_mute_sleep "$CLAUDE_PROJECT_DIR" "$1"; then
    echo "OK"
  else
    echo "ERR: invalid duration. Use 30m, 1h, 4h, or 1d."
  fi
' _ "$duration"`

If the previous line printed OK, tell the user:
```
Bonsai is sleeping for $duration. Run /bonsai:wake to resume earlier.
```

If it printed an ERR line, surface that message to the user verbatim.
