#!/usr/bin/env bash
# Auto-archive: move kept/trimmed branches older than config thresholds.

[[ -n "${_BONSAI_ARCHIVE_SOURCED:-}" ]] && return 0
_BONSAI_ARCHIVE_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/branches.sh"

_bonsai_config_file() { printf '%s/.claude/bonsai/config.json' "$1"; }

bonsai_archive_run() {
  local project_dir="$1"
  local cfg; cfg="$(_bonsai_config_file "$project_dir")"
  local kept_days=14 trimmed_days=7
  if [[ -f "$cfg" ]]; then
    local v
    v="$(bonsai_json_get "$cfg" '.auto_archive_kept_after_days')"
    [[ "$v" =~ ^[0-9]+$ ]] && kept_days="$v"
    v="$(bonsai_json_get "$cfg" '.auto_archive_trimmed_after_days')"
    [[ "$v" =~ ^[0-9]+$ ]] && trimmed_days="$v"
  fi
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
    # Cross-platform mtime: try GNU stat -c first (Linux/CI), then BSD stat -f
    # (macOS). Order matters: on Linux, `stat -f` is a filesystem-info flag
    # that succeeds AND prints multi-line garbage, which would break the
    # arithmetic. Validate that mtime is purely numeric before use.
    local mtime
    mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || printf 0)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    local age_days=$(( (now - mtime) / 86400 ))
    if [[ "$age_days" -ge "$thr" ]]; then
      mv "$f" "$arc/"
      bonsai_log INFO "archive: moved $(basename "$f") (status=$status, age=${age_days}d)"
    fi
  done
  shopt -u nullglob
  return 0
}
