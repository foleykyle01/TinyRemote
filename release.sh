#!/bin/bash
# Publishes a GitHub release; installed copies pick it up through the in-app updater.
# Usage: ./release.sh 0.2.0 "What changed"
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version> [notes]}"
NOTES="${2:-}"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(($(git rev-list --count HEAD) + 1))" Info.plist
rm -rf build
./build.sh build/TinyRemote.app
ditto -c -k --keepParent build/TinyRemote.app build/TinyRemote.zip

git commit -qam "Release $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" build/TinyRemote.zip install.sh --title "TinyRemote $VERSION" --notes "$NOTES"
