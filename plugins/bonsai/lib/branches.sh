#!/usr/bin/env bash
# Branch file I/O: create with frontmatter+body, read fields, update status.

[[ -n "${_BONSAI_BRANCHES_SOURCED:-}" ]] && return 0
_BONSAI_BRANCHES_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_branches_dir() { printf '%s/.claude/bonsai/branches' "$1"; }

# Next free id of the form <day>-NNN for a given day (YYYY-MM-DD), scanning
# existing branch files. Shared by allocate_id and the collision-safe write
# path so id assignment is deterministic in code — never delegated to the LLM,
# which cannot reliably count existing ids and has produced duplicate ids in
# practice (two runs both picking 001).
_bonsai_branches_next_free_id() {
  local project_dir="$1"
  local day="$2"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  bonsai_ensure_dir "$dir" || return 1
  local max=0
  shopt -s nullglob
  for f in "$dir/${day}-"*.md; do
    local base; base="$(basename "$f")"
    if [[ "$base" =~ ^${day}-([0-9]{3})- ]]; then
      local n=$((10#${BASH_REMATCH[1]}))
      [[ "$n" -gt "$max" ]] && max="$n"
    fi
  done
  shopt -u nullglob
  printf '%s-%03d' "$day" $((max + 1))
}

# Allocate next id of the form YYYY-MM-DD-NNN for today.
bonsai_branches_allocate_id() {
  local project_dir="$1"
  local today; today="$(date -u +%Y-%m-%d)"
  _bonsai_branches_next_free_id "$project_dir" "$today"
}

# Extract a single field from the observation JSON, fail loudly on missing/null.
_bonsai_branches_extract() {
  local obs_json="$1"
  local field="$2"
  local v=""
  if ! v="$(printf '%s' "$obs_json" | jq -r --arg f "$field" '.[$f]' 2>/dev/null)"; then
    return 1
  fi
  if [[ -z "$v" || "$v" == "null" ]]; then
    return 1
  fi
  printf '%s' "$v"
}

# Sanitize a string for use in single-line YAML scalar:
# strip newlines (replaced with space) so it never escapes its line.
_bonsai_yaml_sanitize_oneline() {
  printf '%s' "$1" | tr '\n\r' '  '
}

# Write a branch file from a JSON observation. Returns 0 on success.
bonsai_branches_write() {
  local project_dir="$1"
  local obs_json="$2"
  # Validate every required field up front. Missing/null → fail loudly.
  local id title created lens severity evidence_ref dedup_hash \
        tldr evidence_detail suggested_action action_brief
  for field in id title created_iso lens severity evidence_ref dedup_hash \
               tldr evidence_detail suggested_action action_brief; do
    local v
    if ! v="$(_bonsai_branches_extract "$obs_json" "$field")"; then
      bonsai_log ERROR "branches_write: missing or null field '$field'"
      return 1
    fi
    case "$field" in
      id) id="$v" ;;
      title) title="$v" ;;
      created_iso) created="$v" ;;
      lens) lens="$v" ;;
      severity) severity="$v" ;;
      evidence_ref) evidence_ref="$v" ;;
      dedup_hash) dedup_hash="$v" ;;
      tldr) tldr="$v" ;;
      evidence_detail) evidence_detail="$v" ;;
      suggested_action) suggested_action="$v" ;;
      action_brief) action_brief="$v" ;;
    esac
  done

  local slug; slug="$(bonsai_slugify "$title")"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  bonsai_ensure_dir "$dir" || return 1

  # YAML safety: quote the title (it's user/LLM text and may contain colons).
  # Escape internal " and strip newlines so the frontmatter stays single-line.
  local safe_title; safe_title="$(_bonsai_yaml_sanitize_oneline "$title")"
  safe_title="${safe_title//\"/\\\"}"
  local safe_evidence; safe_evidence="$(_bonsai_yaml_sanitize_oneline "$evidence_ref")"
  safe_evidence="${safe_evidence//\"/\\\"}"

  # Day component used to reallocate a colliding id. Derive it from the proposed
  # id; fall back to today (UTC) if the id is malformed.
  local day="${id:0:10}"
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || day="$(date -u +%Y-%m-%d)"

  # Pre-render the related-links block once (independent of id).
  local related; related="$(printf '%s' "$obs_json" | jq -r '.related_branch_ids[]?' 2>/dev/null)"

  # Collision-safe atomic write. The LLM-proposed id is advisory: if any branch
  # already carries it, reassign to the next free id for the day. Create via `ln`
  # (atomic, fails if target exists) not `mv` (silently clobbers), so a duplicate
  # id can never overwrite an observation. On a lost race, reallocate and retry,
  # bounded so a pathological loop can't hang the gardener.
  local file tmp attempt=0
  local max_attempts=50
  while :; do
    shopt -s nullglob
    local existing=("$dir/${id}-"*.md)
    shopt -u nullglob
    if (( ${#existing[@]} > 0 )); then
      id="$(_bonsai_branches_next_free_id "$project_dir" "$day")"
    fi
    file="$dir/${id}-${slug}.md"

    tmp="$(mktemp "${dir}/.${slug}.tmp.XXXXXX")" || return 1
    if ! {
      printf -- '---\n'
      printf 'id: %s\n'             "$id"
      printf 'created: %s\n'        "$created"
      printf 'lens: %s\n'           "$lens"
      printf 'severity: %s\n'       "$severity"
      printf 'status: open\n'
      printf 'title: "%s"\n'        "$safe_title"
      printf 'evidence_ref: "%s"\n' "$safe_evidence"
      printf 'dedup_hash: %s\n'     "$dedup_hash"
      printf -- '---\n\n'
      printf '%s\n\n'                       "$tldr"
      printf '## Evidence\n%s\n\n'          "$evidence_detail"
      printf '## Suggested action\n%s\n\n'  "$suggested_action"
      printf '## Action brief\n%s\n\n'      "$action_brief"
      if [[ -n "$related" ]]; then
        printf '## Related\n'
        while IFS= read -r r; do printf -- '- [[%s]]\n' "$r"; done <<< "$related"
        printf '\n'
      fi
    } > "$tmp"; then
      rm -f "$tmp"
      return 1
    fi

    # `ln` is atomic and refuses to overwrite — last defense against clobbering.
    if ln "$tmp" "$file" 2>/dev/null; then
      rm -f "$tmp"
      # Return the resolved path so callers don't reconstruct the filename.
      printf '%s' "$file"
      return 0
    fi
    rm -f "$tmp"
    attempt=$((attempt + 1))
    if (( attempt >= max_attempts )); then
      bonsai_log ERROR "branches_write: could not allocate a free id after $max_attempts attempts (day=$day)"
      return 1
    fi
    # Lost a race for this filename: force reallocation on the next iteration.
    id="$(_bonsai_branches_next_free_id "$project_dir" "$day")"
  done
}

# Read a single frontmatter field value.
# For quoted YAML strings ("..."), strip surrounding quotes from the output.
bonsai_branches_read_field() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^"k": " {
      sub("^"k": ", "")
      # Strip surrounding double-quotes if present (from sanitized write path)
      if (substr($0,1,1) == "\"" && substr($0,length($0),1) == "\"") {
        $0 = substr($0, 2, length($0)-2)
        gsub("\\\\\"", "\"")
      }
      print
      exit
    }
  ' "$file"
}

# Set status to one of: open | trimmed | kept | archived. Reject anything else.
bonsai_branches_set_status() {
  local file="$1"
  local new_status="$2"
  [[ -f "$file" ]] || return 1
  case "$new_status" in
    open|trimmed|kept|archived) ;;
    *)
      bonsai_log ERROR "branches_set_status: invalid status '$new_status'"
      return 1
      ;;
  esac
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
