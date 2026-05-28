#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branches.sh"

n="${1:-5}"
cwd="${CLAUDE_PROJECT_DIR}"

files=$(bonsai_branches_list_open "$cwd" | tail -n "$n")
if [ -z "$files" ]; then
  echo "No open observations yet — Bonsai stays silent most of the time."
  echo "Run /bonsai:status to check health and quota."
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
