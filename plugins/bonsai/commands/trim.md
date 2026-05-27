---
name: trim
description: Mark a Bonsai observation as not useful (the gardener learns from this)
argument-hint: "<id> [reason]"
arguments: [id, reason]
allowed-tools:
  - Bash
---

The user has invoked `/bonsai:trim $id $reason` in $CLAUDE_PROJECT_DIR.

!`bash -c '
  source "$CLAUDE_PLUGIN_ROOT/lib/common.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/branches.sh"
  source "$CLAUDE_PLUGIN_ROOT/lib/index.sh"
  id="$1"; shift
  reason="$*"
  [ -z "$reason" ] && reason="(no reason given)"
  cwd="$CLAUDE_PROJECT_DIR"
  f="$(bonsai_branches_find_by_id "$cwd" "$id")"
  if [ -z "$f" ]; then
    echo "ERR: observation $id not found"
    exit 0
  fi
  title="$(bonsai_branches_read_field "$f" "title")"
  bonsai_branches_set_status "$f" "trimmed"
  trimmed_md="$cwd/.claude/bonsai/trimmed.md"
  if [ ! -f "$trimmed_md" ]; then
    cat > "$trimmed_md" <<EOF
# Trimmed branches — anti-patterns

The gardener reads this file before every run. Use it to teach Bonsai which
observations are not useful, so it stops emitting similar ones.

EOF
  fi
  {
    echo "---"
    echo
    echo "## $id — $title"
    echo "Trimmed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Reason: $reason"
    echo
  } >> "$trimmed_md"
  bonsai_index_regenerate "$cwd"
  echo "OK"
' _ "$id" "$reason"`

Tell the user:
```
Trimmed observation $id. Bonsai will avoid similar observations going forward.
```

If the helper printed an ERR line, surface that verbatim.
