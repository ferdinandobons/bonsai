---
name: observe
description: Show the N most recent open observations
argument-hint: "[N=5]"
arguments: [n]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:observe $n` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/common.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/branches.sh"
  n="$1"
  [ -z "$n" ] && n=5
  cwd="$CLAUDE_PROJECT_DIR"
  files=$(bonsai_branches_list_open "$cwd" | tail -n "$n")
  if [ -z "$files" ]; then
    echo "No open observations. /bonsai:health for status."
    exit 0
  fi
  echo "Open observations (most recent $n):"
  echo
  while IFS= read -r f; do
    id=$(bonsai_branches_read_field "$f" "id")
    sev=$(bonsai_branches_read_field "$f" "severity")
    lens=$(bonsai_branches_read_field "$f" "lens")
    title=$(bonsai_branches_read_field "$f" "title")
    printf "  [%s · %s] %s — %s\n" "$lens" "$sev" "$id" "$title"
    printf "    /bonsai:discuss %s\n\n" "$id"
  done <<< "$files"
' _ "$n"`

Print the output verbatim. Do not interpret.
