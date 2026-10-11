# TinyRemote

Minimal Siri Remote controller for macOS: remappable buttons, trackpad cursor, ring scrolling. Nothing else.

## Install

Needs the GitHub CLI logged in to an account with access to this repo (`brew install gh && gh auth login`).

```sh
gh release download -R foleykyle01/TinyRemote -p TinyRemote.zip -D /tmp/tinyremote --clobber \
  && ditto -x -k /tmp/tinyremote/TinyRemote.zip ~/Applications \
  && open ~/Applications/TinyRemote.app
```

The Setup page walks through Input Monitoring, Accessibility and pairing the remote. TinyRemote opens at login and updates itself from GitHub releases (toggle both in General).

The app isn't notarized, so install and update through `gh` rather than a browser download; browser downloads are quarantined and Gatekeeper blocks them.

## Develop

- `./build.sh` builds and signs into `~/Applications/TinyRemote.app`.
- `./release.sh 0.2.0 "notes"` bumps the version, builds, tags and publishes a release.
- Releases must be signed with the same certificate, or macOS drops the Input Monitoring and Accessibility grants on update.
- Logs: `~/Library/Logs/TinyRemote.log`. Mappings: `~/Library/Application Support/TinyRemote/config.json`.
