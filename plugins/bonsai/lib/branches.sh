#!/usr/bin/env bash
# Branch file I/O: create with frontmatter+body, read fields, update status.

[[ -n "${_BONSAI_BRANCHES_SOURCED:-}" ]] && return 0
_BONSAI_BRANCHES_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

_bonsai_branches_dir() { printf '%s/.claude/bonsai/branches' "$1"; }

# Next free id of the form <day>-NNN for a given day (YYYY-MM-DD), scanning
# existing branch files. Used by the collision-safe write path so id assignment
# is deterministic in code — never delegated to the LLM, which cannot reliably
# count existing ids and has produced duplicate ids in practice (two runs both
# picking 001).
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

  # Defense-in-depth for the bare (unquoted) YAML scalars written below: strip
  # newlines from LLM-authored id/lens/severity so a stray newline can't inject a
  # second frontmatter line, and clamp severity to the known enum (unknown →
  # normal, the documented "when in doubt, downgrade" default).
  id="$(_bonsai_yaml_sanitize_oneline "$id")"
  lens="$(_bonsai_yaml_sanitize_oneline "$lens")"
  severity="$(_bonsai_yaml_sanitize_oneline "$severity")"
  case "$severity" in critical|normal|low) ;; *) severity="normal" ;; esac

  local slug; slug="$(bonsai_slugify "$title")"
  local dir; dir="$(_bonsai_branches_dir "$project_dir")"
  bonsai_ensure_dir "$dir" || return 1

  # YAML safety: quote the title (it's user/LLM text and may contain colons).
  # Escape internal " and strip newlines so the frontmatter stays single-line.
  local safe_title; safe_title="$(_bonsai_yaml_sanitize_oneline "$title")"
  safe_title="${safe_title//\\/\\\\}"   # escape backslashes BEFORE quotes (\t etc.)
  safe_title="${safe_title//\"/\\\"}"
  local safe_evidence; safe_evidence="$(_bonsai_yaml_sanitize_oneline "$evidence_ref")"
  safe_evidence="${safe_evidence//\\/\\\\}"
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
  if awk -v ns="$new_status" '
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
  ' "$file" > "$tmp"; then
    mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  else
    rm -f "$tmp"; return 1
  fi
}

bonsai_branches_find_by_id() {
  local project_dir="$1"
  local id="$2"
  # Reject a non-literal id so a glob/metacharacter (e.g. "*") in a CLI argument
  # can't turn `-name "${id}-*.md"` into a wildcard matching an unrelated branch.
  [[ "$id" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$ ]] || return 1
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

# --- Staleness support (orthogonal `stale: true` flag — NOT a status value) ---
#
# `stale` is a SEPARATE frontmatter key from `status`. The status enum stays
# open|trimmed|kept|archived (above); a stale observation keeps status==open so
# it stays in list_open / /bonsai:list / INDEX and is merely DEMOTED out of the
# reminder box. This keeps the "is this open?" invariant single-valued.

# Parse the `created` frontmatter (canonical %Y-%m-%dT%H:%M:%SZ, written at the
# top of bonsai_branches_write) into epoch seconds. Delegates to the shared
# BSD-first / GNU-fallback ISO->epoch helper bonsai_iso_to_epoch (common.sh),
# which already carries the fail-0 contract mirroring bonsai_file_mtime_epoch:
# any parse failure (missing key, non-canonical stamp) prints 0 so a malformed
# timestamp can never crash a sweep.
bonsai_branches_created_epoch() {
  local file="$1"
  local iso; iso="$(bonsai_branches_read_field "$file" "created")"
  printf '%s' "$(bonsai_iso_to_epoch "$iso")"
}

# Idempotently set `stale: true` (plus a `stale_at: <epoch>` watermark) inside the
# frontmatter. Atomic (tmp+mv), mirrors bonsai_branches_set_status. Never touches
# `status:`. If a `stale:` line already exists it is normalized to `true`; if a
# `stale_at:` line already exists its value is PRESERVED (so an idempotent re-call
# never moves the watermark and the re-arm window stays stable); otherwise each
# key is inserted just before the closing `---` of the frontmatter. A second call
# is a no-op (still exactly one `stale: true` + one `stale_at:` line), so
# concurrent housekeeping passes can't duplicate it.
#
# `stale_at` is the epoch at which the demotion was recorded; bonsai_staleness_run
# uses it to RE-ARM (clear the flag) once the evidence file changes AGAIN after
# the flag was set, so the demotion can never become a one-way trap.
bonsai_branches_mark_stale() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local now; now="$(date -u +%s)"
  [[ "$now" =~ ^[0-9]+$ ]] || now=0
  local tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  if awk -v now="$now" '
    BEGIN { in_fm=0; done_stale=0; done_at=0 }
    /^---$/ {
      # Closing fence of the frontmatter: backfill any key we did not see.
      if (in_fm==1) {
        if (done_stale==0) { print "stale: true"; done_stale=1 }
        if (done_at==0)    { print "stale_at: " now; done_at=1 }
      }
      in_fm = !in_fm
      print
      next
    }
    in_fm && /^stale: / && !done_stale { print "stale: true"; done_stale=1; next }
    # Preserve an existing watermark verbatim (idempotent re-call must not move it).
    in_fm && /^stale_at: / && !done_at { print; done_at=1; next }
    { print }
  ' "$file" > "$tmp"; then
    mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  else
    rm -f "$tmp"; return 1
  fi
}

# Parse the `stale_at` watermark (epoch seconds) written by mark_stale. Fail-0
# contract (mirrors bonsai_branches_created_epoch): a missing or non-numeric value
# prints 0 and returns 0, so the re-arm math can never crash a sweep.
bonsai_branches_stale_at_epoch() {
  local file="$1"
  local v; v="$(bonsai_branches_read_field "$file" "stale_at")"
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# Clear the staleness demotion: strip both `stale:` and `stale_at:` frontmatter
# lines so the file returns to a pristine not-stale state. Atomic (tmp+mv), never
# touches `status:`. Used by bonsai_staleness_run to RE-ARM a critical whose
# evidence file changed again after it was flagged, so the next sweep re-evaluates
# it fresh (and a fresh mark_stale records a fresh watermark). A no-op on a file
# with no stale keys.
bonsai_branches_clear_stale() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  if awk '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm = !in_fm; print; next }
    in_fm && /^stale: / { next }
    in_fm && /^stale_at: / { next }
    { print }
  ' "$file" > "$tmp"; then
    mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  else
    rm -f "$tmp"; return 1
  fi
}

# Returns 0 iff the frontmatter `stale` key is exactly "true". An absent key reads
# as empty (read_field yields nothing) → returns 1, so every pre-existing branch
# file is forward-compatibly treated as not-stale.
bonsai_branches_is_stale_flag() {
  local file="$1"
  local v; v="$(bonsai_branches_read_field "$file" "stale")"
  [[ "$v" == "true" ]]
}

# --- Critical demotion predicate (single source of truth) ---
#
# Both the return-reminder box (reminder.sh) and INDEX.md (index.sh) need the same
# answer to "is this open critical DEMOTED out of the box / into the needs-re-check
# bucket?". Centralizing the predicate here (the common ancestor both already
# source) keeps the box and INDEX from ever disagreeing about which criticals are
# de-emphasized. Demote-not-archive: the observation always stays status==open.

# Read the soft-TTL config: an open critical older than this many days stops
# FEEDING the reminder box (and moves to INDEX's needs-re-check bucket). Default
# 0 = DISABLED — zero behavior change until a maintainer opts in. Only a clean
# non-negative integer enables it; anything else (missing key, negative, non-
# numeric) -> 0 (off). Safe on a missing config file: bonsai_json_get fails-empty,
# which fails the integer match and falls back to 0.
bonsai_branches_critical_ttl_days() {
  local project_dir="$1"
  local v; v="$(bonsai_json_get "$(bonsai_config_file "$project_dir")" '.critical_reminder_ttl_days')"
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# Returns 0 (demoted) iff an OPEN CRITICAL should drop out of the reminder box.
# Demoted when EITHER:
#   PART A: the deterministic stale flag is set (its evidence file changed after
#           `created` — see staleness.sh), OR
#   PART B: soft TTL is enabled (ttl_days > 0) AND the observation has aged past
#           it. Two aged-out cases:
#             * created > now  : an implausible FUTURE timestamp (bad clock or a
#               fixture dated e.g. 2099) parses to a positive epoch but yields a
#               negative age that would NEVER pass the ttl test, pinning the box
#               forever on one bad stamp -> treat as already aged-out (demote).
#             * created > 0 AND aged past ttl_days : the normal aged-out case.
#           A created epoch of 0 (unparseable timestamp) is treated as
#           NOT-aged-out — fail-open, never silence on doubt.
# Args: $1 branch file, $2 ttl_days (already validated), $3 now epoch (seconds).
# The caller computes ttl_days and `now` ONCE per pass and passes them in, so a
# whole regenerate/sweep shares one clock and avoids a `date` fork per file.
# Callers must pre-filter to open+critical; this does not re-check severity.
bonsai_branches_is_demoted_critical() {
  local file="$1" ttl_days="$2" now="$3"
  bonsai_branches_is_stale_flag "$file" && return 0
  if (( ttl_days > 0 )); then
    # Fail-open on a broken clock: a non-numeric `now` (e.g. a transiently empty
    # `date -u +%s` on a degraded/minimal host) must NOT demote every open critical
    # out of the box at once. Bash coerces "" to 0 inside (( )), so `created > 0`
    # would then fire for every real timestamp. Skip the TTL path entirely instead
    # (clamping `now` to 0 would NOT help — it would still demote everything). The
    # stale-flag path above is independent of `now` and still applies.
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    local created; created="$(bonsai_branches_created_epoch "$file")"
    if (( created > now )); then
      return 0
    elif (( created > 0 )) && (( (now - created) / 86400 >= ttl_days )); then
      return 0
    fi
  fi
  return 1
}
