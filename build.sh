#!/bin/bash
# Builds and signs TinyRemote.app (default ~/Applications, or the path given). A stable signing identity keeps the
# Input Monitoring / Accessibility grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-$HOME/Applications/TinyRemote.app}"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/TinyRemote"
codesign --force --sign "Apple Development: Kyle Foley (SD263FBPPD)" "$APP"
echo "built $APP"
