#!/usr/bin/env bash
# Bonsai — uninstaller for Claude Code.
#
# Usage (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/ferdinandobons/bonsai/main/uninstall.sh)
#
# Removes the bonsai marketplace + plugin entry from ~/.claude/settings.json.
# Does NOT delete your observations (.claude/bonsai/ in each project is preserved).
# Idempotent. Requires `jq`.

set -e

MARKETPLACE_NAME="bonsai"
PLUGIN_KEY="bonsai@bonsai"
SETTINGS_FILE="${HOME}/.claude/settings.json"
BACKUP_FILE="${SETTINGS_FILE}.bonsai-backup-$(date +%Y%m%d-%H%M%S)"

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  RED="$(tput setaf 1)"; DIM="$(tput dim)"; RESET="$(tput sgr0)"
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi

ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$YELLOW" "$RESET" "$1"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; }
say()  { printf '%s\n' "$1"; }

echo
say "${BOLD}🪻 Bonsai uninstaller${RESET}"
echo

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed."
  exit 1
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  warn "no settings.json found — nothing to uninstall."
  exit 0
fi

if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
  err "$SETTINGS_FILE is not valid JSON. Fix it by hand first."
  exit 1
fi

has_marketplace=$(jq -r --arg n "$MARKETPLACE_NAME" \
  '.extraKnownMarketplaces[$n] // empty | tostring' "$SETTINGS_FILE")
has_plugin=$(jq -r --arg k "$PLUGIN_KEY" \
  '.enabledPlugins[$k] // empty | tostring' "$SETTINGS_FILE")

if [ -z "$has_marketplace" ] && [ -z "$has_plugin" ]; then
  warn "bonsai is not installed — nothing to do."
  exit 0
fi

cp "$SETTINGS_FILE" "$BACKUP_FILE"
ok "backed up settings → $(basename "$BACKUP_FILE")"

tmp="$(mktemp "${SETTINGS_FILE}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

jq --arg n "$MARKETPLACE_NAME" --arg k "$PLUGIN_KEY" '
  if .extraKnownMarketplaces then .extraKnownMarketplaces |= del(.[$n]) else . end
  | if .enabledPlugins then .enabledPlugins |= del(.[$k]) else . end
' "$SETTINGS_FILE" > "$tmp"

if ! jq empty "$tmp" 2>/dev/null; then
  err "merge produced invalid JSON — refusing to write. Backup at $BACKUP_FILE."
  exit 1
fi

mv "$tmp" "$SETTINGS_FILE"
trap - EXIT
ok "marketplace removed: ${MARKETPLACE_NAME}"
ok "plugin disabled: ${PLUGIN_KEY}"

echo
say "${BOLD}Bonsai uninstalled from settings.${RESET}"
echo
say "Note: your observation logs (${BOLD}.claude/bonsai/${RESET} in each watched project) are ${BOLD}preserved${RESET}."
say "Delete them manually if you want a clean slate:"
say "  ${DIM}rm -rf <project>/.claude/bonsai${RESET}"
echo
say "${DIM}Settings backup: $BACKUP_FILE${RESET}"
echo
