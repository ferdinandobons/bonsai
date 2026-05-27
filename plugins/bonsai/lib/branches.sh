#!/usr/bin/env bash
# Branch file I/O: create with frontmatter+body, read fields, update status.

[[ -n "${_BONSAI_BRANCHES_SOURCED:-}" ]] && return 0
_BONSAI_BRANCHES_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_branches_dir() { printf '%s/.claude/bonsai/branches' "$1"; }

# Allocate next id of the form YYYY-MM-DD-NNN for today.
bonsai_branches_allocate_id() {
  local project_dir="$1"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  bonsai_ensure_dir "$dir" || return 1
  local today; today="$(date -u +%Y-%m-%d)"
  local max=0
  local pattern="$dir/${today}-"
  shopt -s nullglob
  for f in "$pattern"*.md; do
    local base; base="$(basename "$f")"
    if [[ "$base" =~ ^${today}-([0-9]{3})- ]]; then
      local n=$((10#${BASH_REMATCH[1]}))
      [[ "$n" -gt "$max" ]] && max="$n"
    fi
  done
  shopt -u nullglob
  printf '%s-%03d' "$today" $((max + 1))
}

# Write a branch file from a JSON observation. Returns 0 on success.
bonsai_branches_write() {
  local project_dir="$1"
  local obs_json="$2"
  local id title slug
  if ! id=$(printf '%s' "$obs_json" | jq -r '.id' 2>/dev/null); then
    bonsai_log ERROR "branches_write: failed to extract id"
    return 1
  fi
  if [[ -z "$id" || "$id" == "null" ]]; then
    bonsai_log ERROR "branches_write: missing id"
    return 1
  fi
  if ! title=$(printf '%s' "$obs_json" | jq -r '.title' 2>/dev/null); then
    bonsai_log ERROR "branches_write: failed to extract title"
    return 1
  fi
  slug="$(bonsai_slugify "$title")"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  bonsai_ensure_dir "$dir" || return 1
  local file="$dir/${id}-${slug}.md"
  {
    printf -- '---\n'
    printf 'id: %s\n'           "$id"
    printf 'created: %s\n'      "$(printf '%s' "$obs_json" | jq -r '.created_iso')"
    printf 'lens: %s\n'         "$(printf '%s' "$obs_json" | jq -r '.lens')"
    printf 'severity: %s\n'     "$(printf '%s' "$obs_json" | jq -r '.severity')"
    printf 'status: open\n'
    printf 'title: %s\n'        "$title"
    printf 'evidence_ref: %s\n' "$(printf '%s' "$obs_json" | jq -r '.evidence_ref')"
    printf 'dedup_hash: %s\n'   "$(printf '%s' "$obs_json" | jq -r '.dedup_hash')"
    printf -- '---\n\n'
    printf '%s\n\n'             "$(printf '%s' "$obs_json" | jq -r '.tldr')"
    printf '## Evidence\n%s\n\n' "$(printf '%s' "$obs_json" | jq -r '.evidence_detail')"
    printf '## Suggested action\n%s\n\n' "$(printf '%s' "$obs_json" | jq -r '.suggested_action')"
    printf '## Action brief\n%s\n\n' "$(printf '%s' "$obs_json" | jq -r '.action_brief')"
    local related; related="$(printf '%s' "$obs_json" | jq -r '.related_branch_ids[]?' 2>/dev/null)"
    if [[ -n "$related" ]]; then
      printf '## Related\n'
      while IFS= read -r r; do printf -- '- [[%s]]\n' "$r"; done <<< "$related"
      printf '\n'
    fi
  } > "$file"
}

# Read a single frontmatter field value.
bonsai_branches_read_field() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^"k": " {
      sub("^"k": ", "")
      print
      exit
    }
  ' "$file"
}

# Set status: open | trimmed | kept | archived.
bonsai_branches_set_status() {
  local file="$1"
  local new_status="$2"
  [[ -f "$file" ]] || return 1
  local tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  awk -v ns="$new_status" '
    BEGIN { in_fm=0; done=0 }
    /^---$/ {
      in_fm = !in_fm
      print
      next
    }
    in_fm && /^status: / && !done {
      print "status: " ns
      done=1
      next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

bonsai_branches_find_by_id() {
  local project_dir="$1"
  local id="$2"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  [[ -d "$dir" ]] || return 1
  local hit; hit="$(find "$dir" -maxdepth 1 -name "${id}-*.md" -print -quit 2>/dev/null)"
  [[ -n "$hit" ]] && { printf '%s' "$hit"; return 0; }
  return 1
}

bonsai_branches_list_open() {
  local project_dir="$1"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  for f in "$dir"/*.md; do
    local s; s="$(bonsai_branches_read_field "$f" "status")"
    [[ "$s" == "open" ]] && printf '%s\n' "$f"
  done
  shopt -u nullglob
}
