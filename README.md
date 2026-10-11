<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
    <img src="docs/logo.png" width="160" alt="TinyRemote icon">
  </picture>
</p>

<h1 align="center">TinyRemote</h1>

<p align="center">
  Use the Apple Siri Remote as a clean, fully remappable Mac controller.<br>
  Buttons, trackpad, scrolling and push-to-talk dictation. Nothing else running in the background.
</p>

<p align="center">
  <a href="https://github.com/foleykyle01/TinyRemote/releases/latest/download/TinyRemote.zip"><b>Download TinyRemote</b></a>
  &nbsp;·&nbsp;
  <a href="#install">Install</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/foleykyle01/TinyRemote/releases/latest">Latest release</a>
</p>

<p align="center">
  <img src="docs/screenshots/buttons.png" width="760" alt="Buttons settings with a drawn Siri Remote">
</p>

## What it does

- **Every button is remappable.** Press, release and long press for each button, each with its own hold time. Pick from presets, capture any shortcut (including reserved ones like ⌃→ and ⌘Space), or run an AppleScript.
- **App-aware.** Profiles change buttons per app. In Safari, Chrome and other browsers, Back goes back a page and a long press goes forward. In every other app Back stays Delete, and it also stays Delete while you're typing in a browser's text field. Create profiles for any app.
- **Trackpad that behaves like one.** Move the cursor, tap or click to select, press and slide to drag, and press and hold still for a right click. That works one-handed with your thumb.
- **Scrolling.** Swipe with two fingers, or circle the outer ring like an iPod.
- **Push-to-talk dictation.** Pick your dictation app (FluidVoice, Wispr Flow, superwhisper, VoiceInk, MacWhisper, Apple Dictation or any other). TinyRemote reads FluidVoice's shortcut for you and sets up the mic button as hold-to-talk or tap-to-toggle.
- **My Shortcuts.** Record, name and test your own shortcuts and AppleScripts once, then use them on any button or gesture.
- **Recovers on its own.** Reconnects after sleep and takes the remote back if another app grabs it. The menu-bar icon warns you if a permission goes missing.
- **Small.** One menu-bar app with no AI models, background services, admin helpers or Bluetooth logging.

<table>
  <tr>
    <td><img src="docs/screenshots/touch-surface.png" alt="Touch Surface settings"></td>
    <td><img src="docs/screenshots/voice.png" alt="Voice settings"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/my-shortcuts.png" alt="My Shortcuts"></td>
    <td><img src="docs/screenshots/setup.png" alt="Setup and diagnostics"></td>
  </tr>
</table>

## Requirements

- A Mac with Apple silicon, running macOS 15 or later
- A Siri Remote (2nd or 3rd generation, the aluminum one) paired over Bluetooth: hold **Back** and **Volume +** near the Mac for 5 seconds, then pick it in Bluetooth settings

## Install

### One command (recommended)

Needs the [GitHub CLI](https://cli.github.com) signed in to an account with access to this repo (`brew install gh && gh auth login`).

```sh
gh release download -R foleykyle01/TinyRemote -p install.sh -O - | bash
```

This installs TinyRemote into `~/Applications`, replaces any older copy and opens it. Run it again any time to reinstall.

### Manual download

1. Download [TinyRemote.zip](https://github.com/foleykyle01/TinyRemote/releases/latest/download/TinyRemote.zip) and unzip it.
2. Move **TinyRemote.app** to your Applications folder.
3. TinyRemote isn't notarized by Apple, so macOS blocks it when it's downloaded through a browser. Allow it once with:
   ```sh
   xattr -dr com.apple.quarantine /Applications/TinyRemote.app
   ```
   Or open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

### First launch

TinyRemote opens its **Setup** page and walks you through:

1. **Input Monitoring**, to read the remote. macOS asks TinyRemote to restart afterwards.
2. **Accessibility**, to send shortcuts, clicks and cursor movement.
3. **Pairing the remote**, if it isn't connected yet.

TinyRemote opens at login by default. You can change that in **General**.

## Updates

TinyRemote checks this repo's releases every few hours and on launch, then installs new versions and restarts itself. Toggle this or click **Check Now** in **General**. Updates go through the GitHub CLI, so it needs `gh` installed and signed in.

## Uninstall

1. Quit TinyRemote from its menu-bar icon.
2. Delete `TinyRemote.app`, then remove it from **System Settings → General → Login Items** if it's still listed.
3. Optionally remove its settings and log: `~/Library/Application Support/TinyRemote` and `~/Library/Logs/TinyRemote.log`.

## Why there's no remote microphone

macOS doesn't let apps use the Siri Remote's microphone. The only known way is to turn on Bluetooth debug logging for the whole Mac and read the audio out of that log with admin rights. That log includes private data from every Bluetooth device, and the capture keeps growing in memory. TinyRemote leaves that off and lets your dictation app use your Mac's microphone or AirPods. The **Voice** page explains this in the app too.

## Development

```sh
./build.sh                              # build and sign into ~/Applications/TinyRemote.app
~/Applications/TinyRemote.app/Contents/MacOS/TinyRemote --self-test
~/Applications/TinyRemote.app/Contents/MacOS/TinyRemote --snapshot /tmp/shots   # render each settings page to PNG
swift tools/make-icon.swift             # regenerate the icon (Resources/AppIcon.icon → Assets.car) and README logos
./release.sh 0.3.0 "What changed"       # bump, build, tag and publish a release
```

- Plain `swiftc`, no Xcode project and no dependencies. The sources are in `Sources/`.
- Releases must be signed with the same certificate, or macOS drops the Input Monitoring and Accessibility grants on update.
- Settings: `~/Library/Application Support/TinyRemote/config.json`. Log: `~/Library/Logs/TinyRemote.log`.
- The touch surface uses Apple's private MultitouchSupport framework, which a macOS update could change.
