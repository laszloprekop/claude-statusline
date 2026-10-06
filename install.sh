#!/usr/bin/env bash
# Installs the status line: downloads statusline.sh into the Claude Code config folder and
# points the statusLine setting at it. The previous settings are kept as a backup.
set -euo pipefail

DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
URL="https://raw.githubusercontent.com/laszloprekop/claude-statusline/main/statusline.sh"
SETTINGS="$DEST/settings.json"

for tool in jq curl git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing: $tool. Install it and run this again." >&2; exit 1; }
done

mkdir -p "$DEST"
curl -fsSL "$URL" -o "$DEST/statusline.sh"
chmod +x "$DEST/statusline.sh"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
NEW=$(jq --arg cmd "bash $DEST/statusline.sh" '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' "$SETTINGS") || {
  echo "Could not read $SETTINGS as JSON. Nothing was changed in it." >&2; exit 1; }
cp "$SETTINGS" "$SETTINGS.bak-statusline"
printf '%s\n' "$NEW" > "$SETTINGS"

echo "Installed $DEST/statusline.sh"
echo "Previous settings: $SETTINGS.bak-statusline"
echo "The bar appears after your next message in Claude Code. It needs a Nerd Font for the icons."
