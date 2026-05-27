#!/usr/bin/env bash
# Format chip payload for mcp__ccd_session__spawn_task.
# Returns JSON {title, tldr, prompt} on stdout. The caller (gardener)
# is responsible for actually invoking the tool.

[[ -n "${_BONSAI_CHIP_SOURCED:-}" ]] && return 0
_BONSAI_CHIP_SOURCED=1

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/common.sh"

# Map lens to compact tag.
_bonsai_chip_lens_tag() {
  case "$1" in
    technical) printf 'TECH' ;;
    strategic) printf 'STRAT' ;;
    workflow)  printf 'FLOW' ;;
    *)         printf 'OBS' ;;
  esac
}

_bonsai_chip_sev_tag() {
  case "$1" in
    critical) printf 'CRIT' ;;
    normal)   printf 'NORM' ;;
    low)      printf 'LOW' ;;
    *)        printf '?' ;;
  esac
}

bonsai_chip_format() {
  local obs="$1"
  local lens sev title tldr brief
  if ! lens="$(printf '%s' "$obs"  | jq -r '.lens'         2>/dev/null)"; then return 1; fi
  if ! sev="$(printf '%s' "$obs"   | jq -r '.severity'     2>/dev/null)"; then return 1; fi
  if ! title="$(printf '%s' "$obs" | jq -r '.title'        2>/dev/null)"; then return 1; fi
  if ! tldr="$(printf '%s' "$obs"  | jq -r '.tldr'         2>/dev/null)"; then return 1; fi
  if ! brief="$(printf '%s' "$obs" | jq -r '.action_brief' 2>/dev/null)"; then return 1; fi
  # action_brief is required (the chip's prompt). Missing → error.
  if [[ -z "$brief" || "$brief" == "null" ]]; then
    bonsai_log ERROR "chip_format: missing action_brief"
    return 1
  fi
  local lt st
  lt="$(_bonsai_chip_lens_tag "$lens")"
  st="$(_bonsai_chip_sev_tag  "$sev")"
  local full_title="Bonsai · [${lt} · ${st}] ${title}"
  # Truncate at 60 chars (byte-safe; titles are typically ASCII).
  full_title="${full_title:0:60}"
  jq -n --arg t "$full_title" --arg tl "$tldr" --arg p "$brief" \
    '{title:$t, tldr:$tl, prompt:$p}'
}
