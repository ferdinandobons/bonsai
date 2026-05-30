#!/usr/bin/env bash
# Deterministic, no-LLM longitudinal history index for a project.
#
# Builds a per-project per-module git-churn summary at
# <project>/.claude/bonsai/history.json from a bounded `git log` pass, and
# renders a clamped human summary the Stop hook feeds the gardener as ONE
# CONTEXT-only payload field (project_history). It NEVER calls an LLM, never
# touches any gate, and is fail-open everywhere: every path degrades to the
# empty string (exactly today's behaviour) rather than disturbing the session.
#
# Bounding (so a huge monorepo can't blow the prompt or hang the hook):
#   * `git log --since="<window> days ago"` — git-native window, sidesteps the
#     BSD/GNU `date -d` vs `date -v` divergence the repo already pays elsewhere.
#   * `-n 200` commit cap.
#   * top ~25 modules by churn.
#   * ~1.5KB head -c clamp on the rendered summary.
#   * HEAD-sha cache: when no new commit landed (and the window is unchanged),
#     the cached index is reused and the walk is skipped — the no-commit case is
#     one `git rev-parse HEAD` + a file read.
#   * timeout/gtimeout 5 wraps the walk (same idiom as dispatch.sh); bare macOS
#     has neither and degrades to no wall-clock cap, exactly like dispatch.
#
# history.json is a single self-overwriting HEAD-cached file that never grows,
# so it needs no migrate/archive wiring. It lives under .claude/bonsai/, already
# excluded from signal.sh and the git_diff via ':!.claude/bonsai'.

[[ -n "${_BONSAI_HISTORY_SOURCED:-}" ]] && return 0
_BONSAI_HISTORY_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

# Exclude the gardener's own bookkeeping, exactly as signal.sh / stop.sh.
_BONSAI_HISTORY_EXCLUDE=':!.claude/bonsai'

# Path to the per-project history index.
bonsai_history_file() { printf '%s/.claude/bonsai/history.json' "$1"; }

# Choose a wall-clock guard for the git walk, mirroring dispatch.sh. Prints the
# command prefix ("timeout 5", "gtimeout 5", or "" when neither exists).
_bonsai_history_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout 5'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout 5'
  else
    printf ''
  fi
}

# Compute (or refresh) <project>/.claude/bonsai/history.json.
#   $1 - project dir
#   $2 - window in days (default 7; non-numeric falls back to 7)
# Returns 0 always (fail-open). Writes NO file for a non-git dir or an empty
# repo. Skips the walk when HEAD and the window are unchanged (cache hit). When
# the (recomputed) window has zero in-window commits, REMOVES any stale index so
# the summary renders empty instead of serving an outdated module list.
bonsai_history_compute() {
  local dir="$1"
  local window="$2"
  [[ "$window" =~ ^[0-9]+$ ]] || window=7

  # Non-git dir → no file, no work (mirrors git_diff being empty for non-git).
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local head_sha
  head_sha="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
  # An empty repo (no commits) has no HEAD → nothing to summarise.
  [[ -n "$head_sha" ]] || return 0

  local file
  file="$(bonsai_history_file "$dir")"

  # UTC calendar day (POSIX %Y%m%d — no BSD/GNU date divergence). Part of the
  # cache key so an IDLE repo (same HEAD, same window) still recomputes at least
  # once per UTC day: the window is wall-clock-relative (`--since="N days ago"`),
  # so a commit at the window edge ages OUT as real time advances even with HEAD
  # unchanged. Without this, a cache hit would keep serving that aged-out commit
  # as a false "still churning" signal. On a `date` failure today is "" and the
  # gate below simply misses (fail-open → a still-bounded recompute).
  local today; today="$(date -u +%Y%m%d 2>/dev/null || true)"

  # Cache hit: HEAD unchanged AND the window is the same AND still the same UTC
  # day → reuse the index, skip the walk. A window change (or a new day) must
  # force a recompute so the summary reflects the new window / re-walks the
  # wall-clock window.
  if [[ -f "$file" ]]; then
    local cached_head cached_window cached_day
    cached_head="$(jq -r '.computed_for_head // empty' "$file" 2>/dev/null || true)"
    cached_window="$(jq -r '.window_days // empty' "$file" 2>/dev/null || true)"
    cached_day="$(jq -r '.computed_day // empty' "$file" 2>/dev/null || true)"
    if [[ -n "$cached_head" && "$cached_head" == "$head_sha" \
          && "$cached_window" == "$window" \
          && -n "$today" && "$cached_day" == "$today" ]]; then
      return 0
    fi
  fi

  # Bounded walk. Header line: "<40-hex-sha>\t<committer ISO date>"; body lines
  # are file paths; commits are blank-separated. awk aggregates each path to its
  # first segment (or '.' for repo-root files) and counts DISTINCT commits per
  # module (so one commit touching auth/a and auth/b counts once for auth), and
  # tracks the latest commit date seen for that module.
  #
  # The header is matched with `length($1)==40 && $1 ~ /^[0-9a-f]+$/` (NOT a
  # `{40}` interval) so it works even on the older BSD awk that disables interval
  # expressions by default — current macOS/Linux awks accept both, this is the
  # safest form. A malformed line falls through and is dropped, never fatal.
  # Capture the (already -n 200 bounded) git walk into a variable FIRST, then
  # aggregate. Piping the timeout-wrapped git straight into `… | head -25` lets
  # `head` close the pipe early once the 25-module cap is hit (only with >25
  # modules); on GNU/Linux that early close races the teardown of the
  # `timeout`-wrapped git and can drop its output entirely (the walk works
  # unwrapped on macOS, where there is no `timeout`). Buffering the bounded walk
  # in `raw` takes git out of the early-closed pipe, and capping with
  # `awk 'NR<=25'` (which reads all of sort's output instead of closing it early)
  # removes the SIGPIPE altogether. Fail-open to an empty walk.
  local tcmd; tcmd="$(_bonsai_history_timeout)"
  local raw
  # shellcheck disable=SC2086
  raw="$($tcmd git -C "$dir" log --since="${window} days ago" --name-only \
          --pretty=format:'%H%x09%cI' -n 200 -- . "$_BONSAI_HISTORY_EXCLUDE" 2>/dev/null || true)"
  local tsv
  tsv="$(printf '%s\n' "$raw" \
        | awk -F'\t' '
            length($1)==40 && $1 ~ /^[0-9a-f]+$/ && NF==2 { commit=$1; cdate=$2; next }
            $0 == "" { next }
            {
              path=$1
              n=index(path,"/")
              if (n>0) seg=substr(path,1,n-1); else seg="."
              key=seg SUBSEP commit
              if (!(key in seen)) {
                seen[key]=1
                mods[seg]++
                if (last[seg]=="" || cdate>last[seg]) last[seg]=cdate
              }
            }
            END { for (s in mods) printf "%s\t%d\t%s\n", s, mods[s], last[s] }
          ' 2>/dev/null \
        | sort -t"$(printf '\t')" -k2,2nr \
        | awk 'NR<=25' || true)"

  # No commits in the window → the previous index (if any) is now stale: it would
  # carry an OLD window_days + OLD modules and the summary would render them
  # against the NEW window label, feeding the gardener a false longitudinal
  # signal. Remove it so the summary falls through to its empty path. (rm -f is a
  # harmless no-op when no file exists; the next real commit recreates it.)
  if [[ -z "$tsv" ]]; then
    rm -f "$file" 2>/dev/null || true
    return 0
  fi

  # TSV → modules object via jq. A malformed line is dropped, never fatal.
  local modules_json
  modules_json="$(printf '%s' "$tsv" | jq -R -s '
      split("\n") | map(select(length>0)) | map(split("\t"))
      | map(select(length>=2 and (.[1]|test("^[0-9]+$"))))
      | map({ key: .[0], value: { modifications: (.[1]|tonumber), last_seen: (.[2] // "") } })
      | from_entries' 2>/dev/null || true)"
  [[ -n "$modules_json" ]] || return 0

  local gen_iso; gen_iso="$(bonsai_now_iso)"
  local index_json
  index_json="$(jq -n \
      --arg head "$head_sha" \
      --argjson window "$window" \
      --arg day "$today" \
      --arg gen "$gen_iso" \
      --argjson modules "$modules_json" \
      '{__version:1, computed_for_head:$head, window_days:$window, computed_day:$day, generated_iso:$gen, modules:$modules}' \
      2>/dev/null || true)"
  [[ -n "$index_json" ]] || return 0

  # Atomic write (tmp+mv) via the shared helper — same discipline as everywhere.
  bonsai_json_write "$file" "$index_json" 2>/dev/null || true
  return 0
}

# Render the top 5-8 hottest modules as a clamped human summary, e.g.:
#   auth/ — 7 commits in 7d (last 2026-05-28)
# Prints the empty string on ANY failure (non-git, no commits, timeout, jq).
#   $1 - project dir
#   $2 - window in days (default 7)
bonsai_history_summary() {
  local dir="$1"
  local window="$2"
  [[ "$window" =~ ^[0-9]+$ ]] || window=7

  bonsai_history_compute "$dir" "$window" 2>/dev/null || true

  local file
  file="$(bonsai_history_file "$dir")"
  [[ -f "$file" ]] || { printf ''; return 0; }

  # Render top modules by churn. '.' (repo-root files) shows as '(root)' for
  # readability. last_seen may be empty; guard the date slice.
  local summary
  summary="$(jq -r --argjson w "$window" '
      (.modules // {}) | to_entries
      | sort_by(-(.value.modifications))
      | .[0:8]
      | map(
          (if .key == "." then "(root)" else .key + "/" end)
          + " — " + (.value.modifications|tostring) + " commits in " + ($w|tostring) + "d"
          + (if (.value.last_seen // "") == "" then "" else " (last " + (.value.last_seen[0:10]) + ")" end)
        )
      | join("\n")
    ' "$file" 2>/dev/null || true)"

  [[ -n "$summary" ]] || { printf ''; return 0; }
  # ~1.5KB clamp so a wide repo can never blow the prompt.
  printf '%s' "$summary" | head -c 1500
}
