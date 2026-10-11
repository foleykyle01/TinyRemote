#!/bin/bash
# Installs or updates TinyRemote from the latest GitHub release into ~/Applications.
# Usage: curl -fsSL https://github.com/foleykyle01/TinyRemote/releases/latest/download/install.sh | bash
set -euo pipefail
REPO="foleykyle01/TinyRemote"
DEST="$HOME/Applications"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading the latest TinyRemote…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/TinyRemote.zip" -o "$TMP/TinyRemote.zip"

pkill -x TinyRemote 2>/dev/null || true
for _ in $(seq 1 50); do pgrep -x TinyRemote >/dev/null || break; sleep 0.1; done  # let it quit before relaunching
mkdir -p "$DEST"
rm -rf "$DEST/TinyRemote.app"
ditto -x -k "$TMP/TinyRemote.zip" "$DEST"
# Not notarized: make sure Gatekeeper doesn't block it if the file picked up a quarantine flag.
xattr -dr com.apple.quarantine "$DEST/TinyRemote.app" 2>/dev/null || true
open "$DEST/TinyRemote.app"
echo "TinyRemote is installed in $DEST and running. Look for the remote icon in the menu bar."
