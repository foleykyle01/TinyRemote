# Changelog

Every TinyRemote release. Downloads for each version are on the [releases page](https://github.com/foleykyle01/TinyRemote/releases).

## 0.6.4 (2026-10-12)

- **Grant…** for Input Monitoring or Accessibility now shows a small floating panel next to System Settings with TinyRemote's icon to drag into the list, for when macOS doesn't add it on its own. The panel confirms once the permission is on and offers the restart Input Monitoring needs.

## 0.6.3 (2026-10-12)

- Fixed: the menu-bar icon could disappear for good after being hidden. TinyRemote now hides it by removing it, and creates a fresh one when you turn it back on.
- TinyRemote has a new app ID, so macOS asks for **Input Monitoring** and **Accessibility** once more after this update. The Setup page walks you through it. Your mappings and settings carry over.

## 0.6.2 (2026-10-12)

- **Show in the menu bar** now takes effect instantly when you turn it back on. Before, macOS remembered the icon as hidden and kept it away.

## 0.6.1 (2026-10-11)

- The app and docs now call it the Apple TV Remote

## 0.6.0 — now open source (2026-10-11)

TinyRemote is now public under the MIT license.

- **Install with one command, no GitHub account needed:**
  `curl -fsSL https://github.com/foleykyle01/TinyRemote/releases/latest/download/install.sh | bash`
- Updates download straight from GitHub over HTTPS; the GitHub CLI is no longer needed
- Builds fall back to a local signature when the maintainer's certificate isn't present, so anyone can build from source
- New README with a remote map, a thumb cheat sheet and an FAQ

## 0.5.1 (2026-10-11)

- **None** is now the first option in every action menu
- The install script waits for a running copy to quit before relaunching

## 0.5.0 (2026-10-11)

- **Welcome guide for new installs:** allow Input Monitoring and Accessibility (with a restart prompt when macOS needs one), connect the Apple TV Remote with a live connected check, try the buttons and clickpad, then finish with open-at-login
- Progress is kept across the Input Monitoring restart
- **Setup → Run Setup Again** shows the guide any time
- Existing installs skip the guide

## 0.4.0 (2026-10-11)

- **Light and dark app icon:** blue in light mode, graphite in dark mode, plus a tinted variant on macOS 26 (built from an Icon Composer file)
- **Show in the menu bar** and **Show in the Dock** switches in General
- With the menu-bar icon hidden, open TinyRemote from Applications or Spotlight to get back to Settings
- The Settings window reliably opens in front of other apps
- The README logo follows GitHub's light/dark theme

## 0.3.0 (2026-10-11)

- **App profiles:** buttons can do different things per app. A built-in **Web browsers** profile makes Back go back a page (long press goes forward) in Safari, Chrome, Arc, Dia, Edge, Firefox, Brave, Orion, Vivaldi and Opera. Back stays Delete everywhere else, and also while you're typing in a text field.
- Create profiles for any app from the Buttons page (**Mappings for → New Profile…**)
- New presets: Browser back/forward, Reload page, Next/Previous tab, New tab
- The Settings window now opens in front of other apps, with a Dock icon while it's open
- Quieter log while another app holds the remote

## 0.2.0 (2026-10-11)

- **Buttons:** drawn-remote editor with press, release and long press for every button, each with its own hold time
- **Touch Surface:** scrolling (two-finger swipe, ring), cursor, click, click-and-hold for right click, tap, two-finger tap and two-finger click
- **Voice:** pick your dictation app; reads FluidVoice's shortcut automatically; hold-to-talk or tap-to-toggle
- **My Shortcuts:** record, name, test and reuse shortcuts or AppleScripts
- Every built-in GoatRemote action: Fn, F13–F20, keypad, brightness, keyboard backlight, eject, media keys, Launchpad, Mission Control
- Captures reserved shortcuts like ⌃→ and ⌘Space
- Reconnects after sleep, takes the remote back from other apps, and warns in the menu bar if a permission goes missing
- Fixed: clicks after a Ctrl shortcut became right clicks
- New app icon; requires macOS 15 or later on Apple silicon

## 0.1.1 (2026-10-11)

- No user-facing changes; this release verified that installed copies update themselves

## 0.1.0 (2026-10-11)

- First public build: a menu-bar app that turns the Apple TV Remote into a Mac controller
- Remappable buttons with press and long-press actions
- Touch surface moves the pointer, with tap to click and a drag dead zone
- Circle the outer ring to scroll
- Setup page for Input Monitoring, Accessibility and pairing
- Opens at login and updates itself from GitHub releases
