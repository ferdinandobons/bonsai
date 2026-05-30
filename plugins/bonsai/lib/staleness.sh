#!/usr/bin/env bash
# Deterministic staleness detection for OPEN CRITICAL observations.
#
# An open critical is "stale" when the project file it cites (its evidence_ref)
# has been modified AFTER the observation was created — positive evidence that
# the cited code moved. A stale critical is DEMOTED (frontmatter `stale: true`,
# set by bonsai_branches_mark_stale) but NOT archived: status stays `open`, so it
# remains in bonsai_branches_list_open / /bonsai:list / INDEX. It only drops out
# of the return-reminder box. "File changed" is not "bug fixed".
#
# Everything here is pure mtime + ISO-epoch math — no LLM call, no new emission
# path. It is conservative by construction: anything we cannot PROVE changed
# (sentinel refs, absolute/escaping paths, missing files, unreadable mtime,
# unparseable `created`) is left un-flagged, so a real critical is never silently
# buried. Every error path returns 0 (fail-open) so a sweep can't disturb a
# session or crash the gardener.

[[ -n "${_BONSAI_STALENESS_SOURCED:-}" ]] && return 0
_BONSAI_STALENESS_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/branches.sh"

# Grace window (seconds): the evidence file must be MORE than this much newer
# than `created` to count as stale. This absorbs clock skew and same-minute user
# edits straddling the created timestamp, so a borderline write can't self-
# trigger a demotion. Overridable for tests.
: "${_BONSAI_STALENESS_GRACE_SECS:=120}"

# Resolve a project-relative file path from an LLM-authored evidence_ref, or fail
# (return nonzero) if the ref is not a plausible in-project file path.
#
# evidence_ref is free text: it may be "src/foo.ts:42", "src/foo.ts:42:5", a bare
# "src/foo.ts", or one of the sentinels "transcript" / "git diff" (and prose).
# We strip a trailing ":NN" or ":NN:NN" line/column suffix, then REJECT:
#   * the sentinels transcript / git diff (no concrete file to stat)
#   * absolute paths ("/...")  — must resolve strictly under the project
#   * any ".." segment        — must not escape the project dir
# The error is one-directional: we under-resolve, never over-resolve, so the
# worst case is "no change vs today", never a wrongly-buried critical.
bonsai_staleness_evidence_path() {
  local ref="$1"
  [[ -n "$ref" ]] || return 1
  case "$ref" in
    transcript|"transcript "*) return 1 ;;
    "git diff"|"git diff "*|git-diff) return 1 ;;
  esac
  # Strip a trailing :NN or :NN:NN (line / line:col). Anchored to end-of-string
  # so a colon inside the path (rare, but possible) is untouched.
  local p; p="$(printf '%s' "$ref" | sed -E 's/:[0-9]+(:[0-9]+)?$//')"
  [[ -n "$p" ]] || return 1
  case "$p" in
    /*)    return 1 ;;   # absolute → reject
    *..*)  return 1 ;;   # any parent-dir escape → reject
  esac
  printf '%s' "$p"
}

# Return 0 (stale) iff the open observation's evidence file changed after it was
# created. Stale ONLY when ALL hold:
#   * the ref resolves to an in-project relative path (above),
#   * that path exists as a regular file under project_dir,
#   * its mtime > 0 (readable) AND the observation's created epoch > 0 (parsed),
#   * (mtime - created) > grace window.
# Any failure → return 1 (not stale). Pure fail-open: never crashes.
bonsai_staleness_is_stale() {
  local project_dir="$1" branch_file="$2"
  [[ -d "$project_dir" && -f "$branch_file" ]] || return 1

  local ref; ref="$(bonsai_branches_read_field "$branch_file" "evidence_ref")"
  [[ -n "$ref" ]] || return 1

  local rel; rel="$(bonsai_staleness_evidence_path "$ref")" || return 1
  local resolved="$project_dir/$rel"
  # Must be an existing regular file strictly under the project. A deleted file
  # (resolved path missing) is NOT "changed" — leave the critical nagging.
  [[ -f "$resolved" ]] || return 1

  local mtime; mtime="$(bonsai_file_mtime_epoch "$resolved")"
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
  (( mtime > 0 )) || return 1

  local created; created="$(bonsai_branches_created_epoch "$branch_file")"
  (( created > 0 )) || return 1

  (( mtime - created > _BONSAI_STALENESS_GRACE_SECS )) || return 1
  return 0
}

# Sweep OPEN CRITICALS only: for each stale one not already flagged, set
# `stale: true`. Critical-only, so zero churn for normal/low. Idempotent and
# atomic (inherited from bonsai_branches_mark_stale). Always returns 0.
bonsai_staleness_run() {
  local project_dir="$1"
  [[ -d "$project_dir" ]] || return 0
  local f sev
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    sev="$(bonsai_branches_read_field "$f" "severity")"
    [[ "$sev" == "critical" ]] || continue
    # Already demoted? Re-arm BEFORE the idempotent fast-path: if the evidence
    # file has changed AGAIN since the flag was recorded (mtime > stale_at +
    # grace), clear the flag so this critical is re-evaluated fresh instead of
    # staying permanently demoted. Pure mtime math, fail-open. A stale_at of 0
    # (unparseable / pre-watermark file) never re-arms — we leave it demoted
    # rather than risk churning a flag we can't reason about.
    if bonsai_branches_is_stale_flag "$f"; then
      local stale_at; stale_at="$(bonsai_branches_stale_at_epoch "$f")"
      if (( stale_at > 0 )); then
        local ev_rel ev_path ev_mtime
        ev_rel="$(bonsai_staleness_evidence_path "$(bonsai_branches_read_field "$f" "evidence_ref")")" || ev_rel=""
        if [[ -n "$ev_rel" && -f "$project_dir/$ev_rel" ]]; then
          ev_path="$project_dir/$ev_rel"
          ev_mtime="$(bonsai_file_mtime_epoch "$ev_path")"
          if [[ "$ev_mtime" =~ ^[0-9]+$ ]] \
             && (( ev_mtime - stale_at > _BONSAI_STALENESS_GRACE_SECS )); then
            bonsai_branches_clear_stale "$f" \
              && bonsai_log INFO "staleness: re-armed $(basename "$f") (evidence changed again since flag)"
          fi
        fi
      fi
      # Whether or not we re-armed, do not re-mark in the same pass — the next
      # sweep re-evaluates a re-armed file from scratch (mtime vs created).
      continue
    fi
    if bonsai_staleness_is_stale "$project_dir" "$f"; then
      bonsai_branches_mark_stale "$f" \
        && bonsai_log INFO "staleness: marked $(basename "$f") stale (evidence changed since created)"
    fi
  done < <(bonsai_branches_list_open "$project_dir")
  return 0
}
