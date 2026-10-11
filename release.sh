#!/bin/bash
# Publishes a GitHub release and adds it to CHANGELOG.md; installed copies pick it up through the in-app updater.
# Usage: ./release.sh 0.7.0 "- First change
# - Second change"
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version> <notes>}"
NOTES="${2:?give release notes as a bullet list}"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }

# Same notes in both places: newest entry goes under the changelog's 4-line intro.
{ head -n 4 CHANGELOG.md; printf '## %s (%s)\n\n%s\n\n' "$VERSION" "$(date +%F)" "$NOTES"; tail -n +5 CHANGELOG.md; } > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md
BODY="## TinyRemote $VERSION

$NOTES

Install or update: \`curl -fsSL https://github.com/foleykyle01/TinyRemote/releases/latest/download/install.sh | bash\`"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(($(git rev-list --count HEAD) + 1))" Info.plist
rm -rf build
./build.sh build/TinyRemote.app
ditto -c -k --keepParent build/TinyRemote.app build/TinyRemote.zip

git commit -qam "Release $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" build/TinyRemote.zip install.sh --title "TinyRemote $VERSION" --notes "$BODY"
