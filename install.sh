#!/usr/bin/env bash
# Bonsai — convenience installer for Claude Code.
#
# Usage (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/ferdinandobons/bonsai/main/install.sh)
#
# Or, after cloning:
#   ./install.sh
#
# Adds the bonsai marketplace + enables the plugin in ~/.claude/settings.json,
# atomically. Idempotent (safe to re-run). Requires `jq`.

set -e

MARKETPLACE_NAME="bonsai"
PLUGIN_KEY="bonsai@bonsai"
REPO="ferdinandobons/bonsai"
SETTINGS_DIR="${HOME}/.claude"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
BACKUP_FILE="${SETTINGS_FILE}.bonsai-backup-$(date +%Y%m%d-%H%M%S)"

# Colors (gracefully degrade in dumb terminals)
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
say "${BOLD}🌱 Bonsai installer${RESET}"
say "${DIM}a patient gardener for your Claude Code sessions${RESET}"
echo

# --- Preflight ---------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed."
  say "  Install it first:"
  say "    macOS:  brew install jq"
  say "    Linux:  sudo apt install jq    (or your distro's equivalent)"
  exit 1
fi
ok "jq found"

mkdir -p "$SETTINGS_DIR"
ok "settings dir ready: $SETTINGS_DIR"

# --- Read or initialize settings ---------------------------------------------

if [ -f "$SETTINGS_FILE" ]; then
  if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    err "$SETTINGS_FILE exists but is not valid JSON."
    say "  Fix it by hand or remove it before re-running this installer."
    exit 1
  fi
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  ok "backed up existing settings → $(basename "$BACKUP_FILE")"
else
  echo '{}' > "$SETTINGS_FILE"
  ok "created fresh settings.json"
fi

# --- Detect prior install ----------------------------------------------------

already_marketplace=$(jq -r --arg n "$MARKETPLACE_NAME" \
  '.extraKnownMarketplaces[$n] // empty | tostring' "$SETTINGS_FILE")
already_enabled=$(jq -r --arg k "$PLUGIN_KEY" \
  '.enabledPlugins[$k] // empty | tostring' "$SETTINGS_FILE")

if [ -n "$already_marketplace" ] && [ "$already_enabled" = "true" ]; then
  warn "bonsai is already installed and enabled — nothing to do."
  rm -f "$BACKUP_FILE"
  echo
  say "Run ${BOLD}/plugin${RESET} inside Claude Code to manage it."
  exit 0
fi

# --- Atomic merge ------------------------------------------------------------

tmp="$(mktemp "${SETTINGS_FILE}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

jq --arg n "$MARKETPLACE_NAME" --arg k "$PLUGIN_KEY" --arg repo "$REPO" '
  .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) +
    { ($n): { source: { source: "github", repo: $repo } } })
  | .enabledPlugins = ((.enabledPlugins // {}) +
    { ($k): true })
' "$SETTINGS_FILE" > "$tmp"

if ! jq empty "$tmp" 2>/dev/null; then
  err "merge produced invalid JSON — refusing to write. Backup at $BACKUP_FILE."
  exit 1
fi

mv "$tmp" "$SETTINGS_FILE"
trap - EXIT
ok "marketplace registered: ${MARKETPLACE_NAME} → github:${REPO}"
ok "plugin enabled: ${PLUGIN_KEY}"

# --- Done --------------------------------------------------------------------

echo
say "${BOLD}🌿 Bonsai installed.${RESET}"
echo
say "Next steps:"
say "  1. ${BOLD}Restart Claude Code${RESET} (or run ${BOLD}/plugin${RESET} to reload)."
say "  2. In any project you want watched: ${BOLD}/bonsai:start${RESET}"
say "  3. Anytime: ${BOLD}/bonsai:help${RESET} for the full command list."
echo
say "${DIM}Backup of your previous settings.json:${RESET}"
say "${DIM}  $BACKUP_FILE${RESET}"
say "${DIM}To uninstall: bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/main/uninstall.sh)${RESET}"
echo
