#!/usr/bin/env bash
set -e
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bootstrap.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/common.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branches.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/index.sh"

id="$1"; shift || true
reason="$*"
[ -z "$reason" ] && reason="(no reason given)"
cwd="${CLAUDE_PROJECT_DIR}"

# `|| true`: find_by_id returns nonzero when the id is unknown; without this the
# command substitution would abort under `set -e` before the friendly message.
f="$(bonsai_branches_find_by_id "$cwd" "$id" || true)"
if [ -z "$f" ]; then
  echo "ERR: observation $id not found"
  exit 0
fi

title="$(bonsai_branches_read_field "$f" "title")"
bonsai_branches_set_status "$f" "trimmed"

trimmed_md="$cwd/.claude/bonsai/trimmed.md"
if [ ! -f "$trimmed_md" ]; then
  cat > "$trimmed_md" <<'EOF'
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
} >> "$trimmed_md" || true   # non-fatal: still regenerate the index below so the
                             # branch's new 'trimmed' status and INDEX.md agree

bonsai_index_regenerate "$cwd"
echo "OK"
