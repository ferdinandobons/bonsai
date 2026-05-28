#!/usr/bin/env bash
# Rebuild INDEX.md from the branches/ directory.

[[ -n "${_BONSAI_INDEX_SOURCED:-}" ]] && return 0
_BONSAI_INDEX_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/branches.sh"

_bonsai_index_section() {
  local title="$1"
  shift
  local files=("$@")
  printf '## %s (%d)\n' "$title" "${#files[@]}"
  for f in "${files[@]}"; do
    local id t rel
    id="$(bonsai_branches_read_field "$f" "id")"
    t="$(bonsai_branches_read_field "$f" "title")"
    rel="branches/$(basename "$f")"
    printf -- '- [%s — %s](%s)\n' "$id" "$t" "$rel"
  done
  printf '\n'
}

bonsai_index_regenerate() {
  local project_dir="$1"
  local dir="$project_dir/.claude/bonsai"
  bonsai_ensure_dir "$dir/branches" || return 1
  local idx="$dir/INDEX.md"

  local -a crit norm low kept trimmed archived
  shopt -s nullglob
  for f in "$dir/branches"/*.md; do
    local sev status
    if ! sev="$(bonsai_branches_read_field "$f" "severity")"; then
      sev=""
    fi
    if ! status="$(bonsai_branches_read_field "$f" "status")"; then
      status="open"
    fi
    case "$status" in
      open)
        case "$sev" in
          critical) crit+=("$f") ;;
          low)      low+=("$f") ;;
          # normal + any unknown/malformed severity: never drop an open
          # observation from the index.
          *)        norm+=("$f") ;;
        esac
        ;;
      kept)     kept+=("$f") ;;
      trimmed)  trimmed+=("$f") ;;
      archived) archived+=("$f") ;;
    esac
  done
  shopt -u nullglob

  # Atomic write: tmp + mv so readers never see a half-written INDEX.md.
  local tmp
  tmp="$(mktemp "${idx}.tmp.XXXXXX")" || return 1
  if ! {
    printf '# Bonsai · index\n\n'
    printf '_Last updated: %s_\n\n' "$(bonsai_now_iso)"
    _bonsai_index_section "🔴 Open critical" "${crit[@]}"
    _bonsai_index_section "🟡 Open normal"   "${norm[@]}"
    _bonsai_index_section "⚪ Open low"      "${low[@]}"
    _bonsai_index_section "✅ Kept"          "${kept[@]}"
    _bonsai_index_section "🚫 Trimmed"       "${trimmed[@]}"
    _bonsai_index_section "🗄 Archived"      "${archived[@]}"
  } > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$idx" || { rm -f "$tmp"; return 1; }
}
