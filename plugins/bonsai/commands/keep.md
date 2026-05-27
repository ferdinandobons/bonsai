---
name: keep
description: Mark a Bonsai observation as addressed / accepted
argument-hint: "<id>"
arguments: [id]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:keep $id` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/branches.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/index.sh"
  cwd="$CLAUDE_PROJECT_DIR"
  f="$(bonsai_branches_find_by_id "$cwd" "$1")"
  if [ -z "$f" ]; then
    echo "ERR: observation $1 not found"
    exit 0
  fi
  bonsai_branches_set_status "$f" "kept"
  bonsai_index_regenerate "$cwd"
  echo "OK"
' _ "$id"`

Tell the user:
```
Kept observation $id. It will auto-archive after the configured threshold.
```

If the helper printed an ERR line, surface that verbatim.
