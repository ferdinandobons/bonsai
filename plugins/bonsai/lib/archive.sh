#!/usr/bin/env bash
# Auto-archive: move kept/trimmed branches older than config thresholds.

[[ -n "${_BONSAI_ARCHIVE_SOURCED:-}" ]] && return 0
_BONSAI_ARCHIVE_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/branches.sh"

# Purge transient plugin-data older than ttl_days: pre-sliced transcripts
# (sliced/sliced-*.jsonl) and per-run gardener logs (logs/gardener-*.log).
# Written once per run, never re-read, so they grow unbounded (MBs/day). The
# persistent bonsai.log / bonsai-errors.log are deliberately NOT matched.
#   $1 - ttl_days (default 7)   $2 - data_dir (default $CLAUDE_PLUGIN_DATA)
bonsai_archive_purge_transient() {
  local ttl_days="${1:-7}"
  local data_dir="${2:-${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}}"
  [[ "$ttl_days" =~ ^[0-9]+$ ]] || ttl_days=7
  local now; now="$(date -u +%s)"
  local cutoff=$(( ttl_days * 86400 ))
  local f mtime age
  shopt -s nullglob
  for f in "$data_dir/sliced/"sliced-*.jsonl "$data_dir/logs/"gardener-*.log; do
    [[ -f "$f" ]] || continue
    mtime="$(bonsai_file_mtime_epoch "$f")"
    age=$(( now - mtime ))
    if (( age >= cutoff )); then
      rm -f "$f" 2>/dev/null \
        && bonsai_log INFO "purge: removed $(basename "$f") (age $((age / 86400))d)"
    fi
  done
  shopt -u nullglob

  # Rotate the persistent logs while we're doing housekeeping. These are never
  # purged by age (they're the audit trail), so without rotation they grow
  # unbounded on heavy use. Keep the recent tail of each.
  bonsai_log_rotate "$data_dir/logs/bonsai.log"
  bonsai_log_rotate "$data_dir/logs/bonsai-errors.log"
  return 0
}

bonsai_archive_run() {
  local project_dir="$1"
  local cfg; cfg="$(bonsai_config_file "$project_dir")"
  local kept_days=14 trimmed_days=7 transient_ttl_days=7
  if [[ -f "$cfg" ]]; then
    local v
    v="$(bonsai_json_get "$cfg" '.auto_archive_kept_after_days')"
    [[ "$v" =~ ^[0-9]+$ ]] && kept_days="$v"
    v="$(bonsai_json_get "$cfg" '.auto_archive_trimmed_after_days')"
    [[ "$v" =~ ^[0-9]+$ ]] && trimmed_days="$v"
    v="$(bonsai_json_get "$cfg" '.transient_data_ttl_days')"
    [[ "$v" =~ ^[0-9]+$ ]] && transient_ttl_days="$v"
  fi

  # Best-effort cleanup of transient plugin-data files (slices + gardener logs).
  # Runs on every gardener archive pass; idempotent and global (not per-project).
  bonsai_archive_purge_transient "$transient_ttl_days"
  local dir="$project_dir/.claude/bonsai/branches"
  local arc="$project_dir/.claude/bonsai/archive"
  bonsai_ensure_dir "$arc" || return 1
  [[ -d "$dir" ]] || return 0
  local now; now="$(date -u +%s)"
  shopt -s nullglob
  for f in "$dir"/*.md; do
    local status; status="$(bonsai_branches_read_field "$f" "status")"
    local thr
    case "$status" in
      kept)    thr="$kept_days" ;;
      trimmed) thr="$trimmed_days" ;;
      *) continue ;;
    esac
    local mtime; mtime="$(bonsai_file_mtime_epoch "$f")"
    # A failed stat returns 0 → a ~20000-day age that would archive a brand-new
    # branch. Skip rather than misfile a fresh observation.
    if [[ "$mtime" -eq 0 ]]; then
      bonsai_log WARN "archive: skipping $(basename "$f") (mtime unreadable)"
      continue
    fi
    local age_days=$(( (now - mtime) / 86400 ))
    if [[ "$age_days" -ge "$thr" ]]; then
      # Mark archived in the frontmatter BEFORE moving, so the file under archive/
      # carries an accurate status instead of a stale kept/trimmed.
      bonsai_branches_set_status "$f" "archived"
      mv "$f" "$arc/"
      bonsai_log INFO "archive: moved $(basename "$f") (was $status, age=${age_days}d)"
    fi
  done
  shopt -u nullglob
  return 0
}
