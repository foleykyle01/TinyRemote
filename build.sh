#!/bin/bash
# Builds and signs TinyRemote.app (default ~/Applications, or the path given). A stable signing identity keeps the
# Input Monitoring / Accessibility grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-$HOME/Applications/TinyRemote.app}"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/Assets.car "$APP/Contents/Resources/"
swiftc -O -target arm64-apple-macos15.0 -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/TinyRemote"
# Releases use the maintainer's certificate so macOS keeps permissions across updates. Anyone else gets a
# local ad-hoc signature (set SIGN_IDENTITY to use your own certificate).
IDENTITY="${SIGN_IDENTITY:-Apple Development: Kyle Foley (SD263FBPPD)}"
security find-identity -v -p codesigning | grep -qF "$IDENTITY" || IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP"
echo "built $APP"
