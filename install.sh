#!/bin/bash
# Installs or updates TinyRemote from the latest GitHub release into ~/Applications.
# Usage: gh release download -R foleykyle01/TinyRemote -p install.sh -O - | bash
set -euo pipefail
REPO="foleykyle01/TinyRemote"
DEST="$HOME/Applications"
command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh && gh auth login"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading the latest TinyRemote…"
gh release download -R "$REPO" -p TinyRemote.zip -D "$TMP"

pkill -x TinyRemote 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/TinyRemote.app"
ditto -x -k "$TMP/TinyRemote.zip" "$DEST"
# Not notarized: make sure Gatekeeper doesn't block it if the file picked up a quarantine flag.
xattr -dr com.apple.quarantine "$DEST/TinyRemote.app" 2>/dev/null || true
open "$DEST/TinyRemote.app"
echo "TinyRemote is installed in $DEST and running. Look for the remote icon in the menu bar."
