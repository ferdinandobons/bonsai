#!/usr/bin/env bash
# Shared helpers for bonsai. Sourced by all other lib/*.sh and by stop.sh.
# Safe to source multiple times.

[[ -n "${_BONSAI_COMMON_SOURCED:-}" ]] && return 0
_BONSAI_COMMON_SOURCED=1

# We deliberately do NOT enable `set -o pipefail` at module scope: sourcing
# must not change the caller's shell options. Bonsai must never disturb the
# session, and pipefail in stop.sh could turn a SIGPIPE on a downstream tool
# into a non-zero hook exit, which Claude Code would surface. Apply pipefail
# locally inside subshells when needed:
#   ( set -o pipefail; cmd1 | cmd2 )

# Current time in ISO-8601 UTC (e.g. "2026-05-27T21:18:00Z").
bonsai_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Current time in ISO basic format (e.g. "20260527T211800Z") — lexically
# comparable, used for log/slice filename stamps and the 24h cutoff compare.
bonsai_now_basic() {
  date -u +"%Y%m%dT%H%M%SZ"
}

# Canonical per-project file paths — single source of truth for the layout.
bonsai_state_file()  { printf '%s/.claude/bonsai/state.json' "$1"; }
bonsai_config_file() { printf '%s/.claude/bonsai/config.json' "$1"; }

# sha256 hex digest of stdin. macOS ships `shasum`; Linux ships `sha256sum`.
# Returns 1 (no output) if BOTH are unavailable, so callers can tell a real
# digest from an empty one instead of silently propagating a blank hash (which
# would collapse every project to the same lock/dedup key).
bonsai_sha256() {
  local h
  h="$({ shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
  [[ -n "$h" ]] || return 1
  printf '%s\n' "$h"
}

# File mtime in epoch seconds, cross-platform. GNU `stat -c %Y` first, then BSD
# `stat -f %m`; on Linux `stat -f` is a filesystem flag that succeeds but prints
# garbage, so validate numeric before returning (0 on failure).
bonsai_file_mtime_epoch() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0')"
  [[ "$m" =~ ^[0-9]+$ ]] || m=0
  printf '%s' "$m"
}

# ISO-8601 (canonical %Y-%m-%dT%H:%M:%SZ) -> epoch seconds, cross-platform.
# BSD `date -j -u -f` first, then GNU `date -u -d`. Fail-0 contract, mirroring
# bonsai_file_mtime_epoch: empty input or any parse failure prints 0 so a
# malformed timestamp can never crash a caller. The canonical never-run sentinel
# "1970-01-01T00:00:00Z" parses to a real 0 — callers that must distinguish that
# from an unparseable stamp (e.g. quota.sh's throttle WARN) keep their own raw
# inline parse instead of using this collapsing helper.
bonsai_iso_to_epoch() {
  local iso="$1" e
  [[ -z "$iso" ]] && { printf '0'; return 0; }
  e="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" '+%s' 2>/dev/null \
       || date -u -d "$iso" '+%s' 2>/dev/null)"
  [[ "$e" =~ ^[0-9]+$ ]] || e=0
  printf '%s' "$e"
}

# Ensure a directory exists. Silent on success.
bonsai_ensure_dir() {
  local dir="$1"
  [[ -z "$dir" ]] && return 1
  mkdir -p "$dir" 2>/dev/null || return 1
}

# Append a log line. Levels: INFO, WARN, ERROR.
# Errors are duplicated to bonsai-errors.log.
bonsai_log() {
  local level="$1"
  shift
  local msg="$*"
  local data_dir="${CLAUDE_PLUGIN_DATA:-/tmp/bonsai-no-data}"
  bonsai_ensure_dir "$data_dir/logs" || return 0
  local ts
  ts="$(bonsai_now_iso)"
  printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$data_dir/logs/bonsai.log"
  if [[ "$level" == "ERROR" ]]; then
    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$data_dir/logs/bonsai-errors.log"
  fi
  return 0
}

# Rotate a persistent log file in place when it grows past a byte cap, keeping
# only the most recent lines. bonsai.log / bonsai-errors.log are append-only and
# otherwise grow without bound on heavy use; this is called opportunistically
# from the housekeeping path (archive/purge) rather than on every log write, so
# the hot bonsai_log path stays a pure append. Best-effort and silent.
#   $1 - file        $2 - max_bytes (default 524288 = 512 KiB)
#   $3 - keep_lines (default 2000)
bonsai_log_rotate() {
  local file="$1"
  local max_bytes="${2:-524288}"
  local keep_lines="${3:-2000}"
  [[ -f "$file" ]] || return 0
  local size
  size="$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  (( size <= max_bytes )) && return 0
  local tmp
  tmp="$(mktemp "${file}.rot.XXXXXX" 2>/dev/null)" || return 0
  if tail -n "$keep_lines" "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# Read JSON value at jq path. Returns empty string on error.
bonsai_json_get() {
  local file="$1"
  local path="$2"
  [[ -f "$file" ]] || { printf ''; return 0; }
  jq -r "$path // empty" "$file" 2>/dev/null || printf ''
}

# Write a JSON file atomically (write to a unique tmp then mv).
# Uses mktemp instead of $$ because $$ does not change across subshells —
# two concurrent command substitutions would collide and silently lose data.
bonsai_json_write() {
  local file="$1"
  local content="$2"
  local dir
  dir="$(dirname "$file")"
  bonsai_ensure_dir "$dir" || return 1
  local tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  printf '%s' "$content" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  return 0
}

# Slugify a string for use as filename segment.
# Lowercase, replace non-alphanumerics with dashes, trim, max 40 chars.
# Empty / all-special input → "untitled" so callers never produce filenames
# like "2026-05-27-001-.md".
bonsai_slugify() {
  local s="$1"
  local out
  out="$(
    printf '%s' "$s" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
      | cut -c1-40 \
      | sed -E 's/-+$//'
  )"
  if [[ -z "$out" ]]; then
    printf 'untitled'
  else
    printf '%s' "$out"
  fi
}
