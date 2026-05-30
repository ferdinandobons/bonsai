#!/usr/bin/env bash
# Soft return-reminder. When the user comes back to a tended project (new prompt
# or new conversation), surface a one-line nudge IF there are open critical
# observations not yet shown this session. Reading stays manual (/bonsai:list);
# this never opens or summarizes an observation, only points at it.
#
# Per-session dedup state lives in its OWN file (not state.json) so it can never
# race the detached gardener's writes to state.json.
# State file: $CLAUDE_PROJECT_DIR/.claude/bonsai/reminder.json
# Schema: {"__version":1,"session_id":<str>,"notified_ids":[<id>,...]}

[[ -n "${_BONSAI_REMINDER_SOURCED:-}" ]] && return 0
_BONSAI_REMINDER_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/branches.sh"

_bonsai_reminder_file() { printf '%s/.claude/bonsai/reminder.json' "$1"; }

# IDs of open observations at the critical threshold, one per line, sorted.
# Sorted output gives a stable order for tests and a deterministic notified set.
# Demotion (stale-flag OR aged past the soft TTL, incl. an implausible future
# stamp) is decided by the single shared predicate bonsai_branches_is_demoted_critical
# (branches.sh), so the box and INDEX can never disagree about which criticals are
# de-emphasized.
bonsai_reminder_critical_ids() {
  local project_dir="$1"
  local ttl_days; ttl_days="$(bonsai_branches_critical_ttl_days "$project_dir")"
  local now; now="$(date -u +%s)"
  {
    local f sev id
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      sev="$(bonsai_branches_read_field "$f" "severity")"
      [[ "$sev" == "critical" ]] || continue
      # An aged-out or deterministically-stale critical drops OUT of the box but
      # stays status==open (remains in /bonsai:list and INDEX). Demote-not-drop.
      bonsai_branches_is_demoted_critical "$f" "$ttl_days" "$now" && continue
      id="$(bonsai_branches_read_field "$f" "id")"
      [[ -n "$id" ]] && printf '%s\n' "$id"
    done < <(bonsai_branches_list_open "$project_dir")
  } | sort
}

# IDs already surfaced in THIS session. Empty if reminder.json is missing or
# belongs to a different session — a new session always re-surfaces.
_bonsai_reminder_notified_ids() {
  local project_dir="$1" session_id="$2"
  local file; file="$(_bonsai_reminder_file "$project_dir")"
  [[ -f "$file" ]] || return 0
  local stored; stored="$(jq -r '.session_id // empty' "$file" 2>/dev/null)"
  [[ "$stored" == "$session_id" ]] || return 0
  jq -r '.notified_ids[]? // empty' "$file" 2>/dev/null
}

# Persist the surfaced id set for this session (replaces any prior session).
_bonsai_reminder_mark() {
  local project_dir="$1" session_id="$2"; shift 2
  local file; file="$(_bonsai_reminder_file "$project_dir")"
  local ids_json
  ids_json="$(printf '%s\n' "$@" | jq -R . | jq -s 'map(select(length>0))')" || return 1
  local content
  content="$(jq -n --arg sid "$session_id" --argjson ids "$ids_json" \
    '{"__version":1,"session_id":$sid,"notified_ids":$ids}')" || return 1
  bonsai_json_write "$file" "$content"
}

# Header line for N pending critical observations (used as the box title).
bonsai_reminder_message() {
  local n="$1"
  if [[ "$n" -eq 1 ]]; then
    printf '🌿 Bonsai · 1 critical observation awaiting review'
  else
    printf '🌿 Bonsai · %s critical observations awaiting review' "$n"
  fi
}

# Truncate a string to at most `max` characters, appending an ellipsis when cut,
# so a long title can't blow up the box layout. Character counting is locale-
# dependent but only affects cosmetics, never correctness.
_bonsai_reminder_trunc() {
  local s="$1" max="${2:-52}"
  if [[ "${#s}" -gt "$max" ]]; then
    printf '%s…' "${s:0:$((max - 1))}"
  else
    printf '%s' "$s"
  fi
}

# How many top findings the box lists before collapsing the rest into "+N more".
_BONSAI_REMINDER_BOX_TOP=3

# Orchestrator: print a boxed reminder on stdout iff there is at least one open
# critical observation not yet surfaced this session, and record the surfaced
# set. Silent (no output) otherwise. Always returns 0 — a reminder must never
# disturb the turn.
#
# The box (vs a one-liner) is deliberate: a bare systemMessage is easy to miss,
# so we surface the title + the top findings so they're scannable at a glance.
bonsai_reminder_emit() {
  local project_dir="$1" session_id="$2"
  local critical; critical="$(bonsai_reminder_critical_ids "$project_dir")"
  [[ -z "$critical" ]] && return 0

  local notified; notified="$(_bonsai_reminder_notified_ids "$project_dir" "$session_id")"

  # Any critical id not in the already-notified set means there's something new
  # to surface. grep -xF: whole-line, fixed-string match (ids never contain
  # regex metacharacters, but be safe).
  local id has_new=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! printf '%s\n' "$notified" | grep -qxF -- "$id"; then
      has_new=1
      break
    fi
  done <<< "$critical"
  [[ "$has_new" -eq 0 ]] && return 0

  local count; count="$(printf '%s\n' "$critical" | grep -c .)"
  local rule='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

  # Top findings: most-recent first (id sorts ascending by date, so reverse).
  local top; top="$(printf '%s\n' "$critical" | sort -r | grep -m"$_BONSAI_REMINDER_BOX_TOP" .)"

  printf '%s\n' "$rule"
  bonsai_reminder_message "$count"; printf '\n'
  local n=0 file title
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    n=$((n + 1))
    file="$(bonsai_branches_find_by_id "$project_dir" "$id" 2>/dev/null)"
    title=""
    [[ -n "$file" ]] && title="$(bonsai_branches_read_field "$file" "title")"
    [[ -z "$title" ]] && title="(untitled)"
    printf '  %d. %s — %s\n' "$n" "$id" "$(_bonsai_reminder_trunc "$title")"
  done <<< "$top"
  if [[ "$count" -gt "$_BONSAI_REMINDER_BOX_TOP" ]]; then
    printf '  … +%d more\n' "$((count - _BONSAI_REMINDER_BOX_TOP))"
  fi
  printf '  → /bonsai:list to read · /bonsai:discuss <id> to dig in\n'
  printf '%s' "$rule"

  # Record the FULL current critical set (bounded to what's open) as notified,
  # so resolved ids drop out naturally and the list can't grow unbounded.
  local ids=()
  while IFS= read -r id; do [[ -n "$id" ]] && ids+=("$id"); done <<< "$critical"
  _bonsai_reminder_mark "$project_dir" "$session_id" "${ids[@]}"
  return 0
}
