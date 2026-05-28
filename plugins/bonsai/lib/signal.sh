#!/usr/bin/env bash
# Cheap "did the working tree change?" signal for adaptive throttling and for
# feeding the gardener context. The hash covers tracked changes vs HEAD plus the
# list of untracked files. Non-git dirs / clean trees hash to a stable value so
# the caller treats them as "no signal" (and falls back to the idle cadence).

[[ -n "${_BONSAI_SIGNAL_SOURCED:-}" ]] && return 0
_BONSAI_SIGNAL_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

# `.claude/bonsai` is excluded everywhere below: the gardener writes its own
# branches/INDEX/state there, and counting that as a change would make every run
# look "active" and defeat the idle cadence.
_BONSAI_SIGNAL_EXCLUDE=':!.claude/bonsai'

# Hash of working-tree changes vs HEAD + untracked paths. Best-effort: never
# errors, and a non-git dir hashes the empty payload (stable constant).
bonsai_signal_diff_hash() {
  local dir="$1"
  local payload=""
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    payload="$(git -C "$dir" diff HEAD -- . "$_BONSAI_SIGNAL_EXCLUDE" 2>/dev/null; \
               git -C "$dir" ls-files --others --exclude-standard -- . "$_BONSAI_SIGNAL_EXCLUDE" 2>/dev/null)"
  fi
  printf '%s' "$payload" | { shasum -a 256 2>/dev/null || sha256sum; } | awk '{print $1}'
}

# Human-readable diff-stat (tracked changes vs HEAD). Empty for clean/non-git.
bonsai_signal_diff_stat() {
  local dir="$1"
  git -C "$dir" diff HEAD --stat -- . "$_BONSAI_SIGNAL_EXCLUDE" 2>/dev/null || true
}
