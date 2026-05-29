#!/usr/bin/env bash
# Build the Haiku filter/judge prompt and parse its verdict. Pure string/jq —
# the actual `claude -p --model haiku` call is made by the gardener (see
# agents/gardener.md), so dispatch/lock stay in one place. The judge does
# semantic dedup against open observations and calibrates severity before any
# branch is written.

[[ -n "${_BONSAI_JUDGE_SOURCED:-}" ]] && return 0
_BONSAI_JUDGE_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

# $1 candidates JSON  $2 existing-observations JSON  $3 anti-patterns text
bonsai_judge_build_prompt() {
  local candidates="$1" existing="$2" anti="$3"
  cat <<EOF
You are a strict editor for a proactive code observer. For each candidate
observation decide whether to KEEP it and at what severity.

Rules:
- Drop a candidate that is the SAME problem as an existing observation, even if
  worded differently: set keep=false and duplicate_of=<existing id>. When unsure
  whether two are the same problem, KEEP (never merge distinct problems).
- Drop obvious / low-signal nits. Prefer silence over noise.
- Severity: critical (reproducible bug / security / data loss), normal (concrete
  fix or decision), low (weak signal). When in doubt, downgrade.
- Avoid the anti-patterns below (things the user previously dismissed).

CANDIDATES:
$candidates

EXISTING OPEN OBSERVATIONS:
$existing

ANTI-PATTERNS (previously dismissed — do not resurface):
$anti

Return ONLY this JSON, no prose:
{"verdicts":[{"candidate_index":<int>,"keep":<bool>,"severity":"critical|normal|low","duplicate_of":<id or null>,"reason":"<short>"}]}
EOF
}

# Parse Haiku's reply (possibly wrapped in prose / code fences). Prints one line
# per verdict: "<index> <keep> <severity>". Returns nonzero if no valid verdict
# JSON is found, so the caller can fail open (write candidates unfiltered rather
# than lose a real finding to a judge hiccup).
bonsai_judge_parse() {
  local raw="$1"
  # Isolate the JSON object: drop everything before the first '{' and after the
  # last '}' (collapse newlines first so the sed ranges span the whole reply).
  local json
  json="$(printf '%s' "$raw" | tr '\n' '\036' \
    | sed -E 's/^[^{]*//; s/[^}]*$//' | tr '\036' '\n')"
  [[ -z "$json" ]] && return 1
  # pipefail in a subshell so the function's exit reflects jq (nonzero when the
  # reply has no valid verdicts → caller fails open), not the trailing `tr`. The
  # `tr -d '\r'` strips the CR that jq.exe emits on Windows (text-mode stdout),
  # which would otherwise leave a stray \r on each parsed verdict line.
  ( set -o pipefail
    printf '%s' "$json" \
      | jq -r '.verdicts[] | "\(.candidate_index) \(.keep) \(.severity)"' 2>/dev/null \
      | tr -d '\r' )
}
