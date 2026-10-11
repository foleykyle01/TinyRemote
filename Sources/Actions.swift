import AppKit

/// Turns action strings into synthetic input. Actions are either shortcuts
/// ("ctrl+shift+space", "cmd+tab", "f5", "key105") or one of `named`.
enum Actions {
    static let named: [(id: String, title: String)] = [
        ("left-click", "Left click"),
        ("right-click", "Right click"),
        ("double-click", "Double click"),
        ("play-pause", "Play / Pause"),
        ("next-track", "Next track"),
        ("previous-track", "Previous track"),
        ("fast-forward", "Fast forward"),
        ("rewind", "Rewind"),
        ("volume-up", "Volume up"),
        ("volume-down", "Volume down"),
        ("mute", "Mute"),
        ("brightness-up", "Display brightness up"),
        ("brightness-down", "Display brightness down"),
        ("keyboard-brightness-up", "Keyboard brightness up"),
        ("keyboard-brightness-down", "Keyboard brightness down"),
        ("keyboard-brightness-toggle", "Keyboard backlight on/off"),
        ("eject", "Eject"),
        ("mission-control", "Mission Control (app)"),
        ("launchpad", "Launchpad / Apps"),
    ]

    static var namedGroups: [(title: String, actions: [(id: String, title: String)])] {
        let mouse = named.filter { $0.id.hasSuffix("-click") }
        let media = named.filter { ["play-pause", "next-track", "previous-track", "fast-forward", "rewind", "volume-up", "volume-down", "mute"].contains($0.id) }
        let system = named.filter { action in !(mouse + media).contains { $0.id == action.id } }
        return [("Mouse", mouse), ("Media", media), ("System", system)]
    }

    /// NX_KEYTYPE_* codes for media/system keys, sent like a real keyboard's top row.
    private static let mediaKeys: [String: Int] = [
        "volume-up": 0, "volume-down": 1, "brightness-up": 2, "brightness-down": 3, "mute": 7, "eject": 14,
        "play-pause": 16, "next-track": 17, "previous-track": 18, "fast-forward": 19, "rewind": 20,
        "keyboard-brightness-up": 21, "keyboard-brightness-down": 22, "keyboard-brightness-toggle": 23,
    ]

    /// Shortcut presets shown in the picker; they're plain shortcuts, so users can record their own.
    static let presets: [(id: String, title: String)] = [
        ("ctrl+left", "Previous desktop"),
        ("ctrl+right", "Next desktop"),
        ("ctrl+up", "Mission Control"),
        ("ctrl+down", "App windows"),
        ("cmd+tab", "Switch app"),
        ("cmd+space", "Spotlight"),
        ("cmd+shift+5", "Screenshot"),
        ("cmd+w", "Close window"),
        ("cmd+q", "Quit app"),
        ("return", "Return"),
        ("escape", "Escape"),
        ("delete", "Delete"),
        ("space", "Space"),
    ]

    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111, "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119,
        "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "capslock": 57, "help": 114, "section": 10,
        "num0": 82, "num1": 83, "num2": 84, "num3": 85, "num4": 86, "num5": 87, "num6": 88, "num7": 89, "num8": 91, "num9": 92,
        "num.": 65, "num*": 67, "num+": 69, "numclear": 71, "num/": 75, "numenter": 76, "num-": 78, "num=": 81,
        "yen": 93, "jisunderscore": 94, "eisu": 102, "kana": 104,
    ]
    static let keyNames = Dictionary(keyCodes.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    /// fn is flag-only: pressing the real fn/Globe key can trigger dictation or the emoji picker.
    static let modifiers: [(name: String, flag: CGEventFlags, symbol: String, key: CGKeyCode?)] = [
        ("fn", .maskSecondaryFn, "fn ", nil), ("ctrl", .maskControl, "⌃", 59), ("opt", .maskAlternate, "⌥", 58),
        ("shift", .maskShift, "⇧", 56), ("cmd", .maskCommand, "⌘", 55),
    ]
    private static let modifierAliases = ["alt": "opt", "option": "opt", "control": "ctrl", "command": "cmd"]

    static func parseShortcut(_ action: String) -> (key: CGKeyCode, flags: CGEventFlags)? {
        var parts = action.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.popLast() else { return nil }
        var flags: CGEventFlags = []
        for part in parts {
            let name = modifierAliases[part] ?? part
            guard let modifier = modifiers.first(where: { $0.name == name }) else { return nil }
            flags.insert(modifier.flag)
        }
        // A lone modifier ("cmd") taps just that key.
        if parts.isEmpty, let modifier = modifiers.first(where: { $0.name == (modifierAliases[keyName] ?? keyName) }), let key = modifier.key {
            return (key, [])
        }
        guard let key = keyCodes[keyName] ?? (keyName.hasPrefix("key") ? CGKeyCode(keyName.dropFirst(3)) : nil) else { return nil }
        // Arrow and function keys carry these flags on real keyboards; Spaces switching ignores them otherwise.
        if (123...126).contains(key) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        if (2...3).contains(keyName.count) && keyName.hasPrefix("f") && keyName.dropFirst().allSatisfy(\.isNumber) { flags.insert(.maskSecondaryFn) }
        if keyName.hasPrefix("num") { flags.insert(.maskNumericPad) }
        return (key, flags)
    }

    static func shortcutString(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        parts.append(keyNames[CGKeyCode(keyCode)] ?? "key\(keyCode)")
        return parts.joined(separator: "+")
    }

    static func custom(_ action: String) -> CustomAction? {
        guard action.hasPrefix("custom:") else { return nil }
        let id = action.dropFirst("custom:".count)
        return Remote.shared.config.customActions.first { $0.id == id }
    }

    static func title(_ action: String) -> String {
        if action.isEmpty { return "—" }
        if action.hasPrefix("custom:") { return custom(action)?.name ?? "Deleted shortcut" }
        if let named = (named + presets).first(where: { $0.id == action }) { return named.title }
        var parts = action.split(separator: "+").map(String.init)
        let key = parts.popLast() ?? ""
        let symbols = modifiers.filter { parts.contains($0.name) }.map(\.symbol).joined()
        let keySymbols = ["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "escape": "⎋", "delete": "⌫", "tab": "⇥", "space": "Space"]
        return symbols + (keySymbols[key] ?? key.uppercased())
    }

    /// Whether the action has a held state (key/mouse down until the button is released).
    static func isHoldable(_ action: String) -> Bool { parseShortcut(action) != nil || action.hasSuffix("-click") }

    static var leftButtonDown = false

    static func perform(_ action: String, down: Bool) {
        switch action {
        case "": return
        case _ where action.hasPrefix("custom:"):
            guard let custom = custom(action) else { return }
            switch custom.kind {
            case .shortcut: perform(custom.value, down: down)
            case .script: if down { runAppleScript(custom.value) }
            }
        case "left-click": mouse(down ? .leftMouseDown : .leftMouseUp, .left); leftButtonDown = down
        case "right-click": mouse(down ? .rightMouseDown : .rightMouseUp, .right)
        case "double-click":
            guard down else { return }
            for _ in 0..<2 { mouse(.leftMouseDown, .left); mouse(.leftMouseUp, .left) }
        case "mission-control": if down { openApp(["/System/Applications/Mission Control.app"]) }
        case "launchpad": if down { openApp(["/System/Applications/Launchpad.app", "/System/Applications/Apps.app"]) }
        case _ where mediaKeys[action] != nil: media(mediaKeys[action]!, down: down)
        default:
            guard let (key, flags) = parseShortcut(action) else { return }
            // Press and release modifiers as their own keys, like a real keyboard. Putting the flags
            // only on the key event leaves macOS believing they're still held, so later clicks
            // become Ctrl-clicks (right-clicks).
            let used = modifiers.compactMap { modifier in modifier.key.map { (key: $0, flag: modifier.flag) } }.filter { flags.contains($0.flag) }
            var held = CGEventFlags()
            if down {
                for modifier in used { held.insert(modifier.flag); postKey(modifier.key, down: true, flags: held) }
                postKey(key, down: true, flags: flags)
            } else {
                postKey(key, down: false, flags: flags)
                held = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
                for modifier in used.reversed() { held.remove(modifier.flag); postKey(modifier.key, down: false, flags: held) }
            }
        }
    }

    static func tap(_ action: String) {
        perform(action, down: true)
        usleep(15_000)
        perform(action, down: false)
    }

    private static func openApp(_ candidates: [String]) {
        guard let path = candidates.first(where: FileManager.default.fileExists) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Runs off the main thread so a slow script can't stall the remote.
    static func runAppleScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.terminationHandler = { log("applescript exited \($0.terminationStatus)") }
        try? process.run()
    }

    private static func postKey(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    static var cursorLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private static var lastDown = (time: Date.distantPast, location: CGPoint.zero, clicks: 0)
    private static var eventNumber: Int64 = 0

    /// Synthetic clicks need the fields a real mouse fills in, or some apps (Electron/Teams) misread them:
    /// a click count for double-clicks, a shared event number for down/up, pressure, and only the
    /// physical keyboard's modifiers.
    private static func mouse(_ type: CGEventType, _ button: CGMouseButton) {
        let location = cursorLocation
        let isDown = type == .leftMouseDown || type == .rightMouseDown
        if isDown {
            let isRepeat = Date().timeIntervalSince(lastDown.time) < NSEvent.doubleClickInterval
                && hypot(location.x - lastDown.location.x, location.y - lastDown.location.y) < 5
            lastDown = (Date(), location, isRepeat ? lastDown.clicks + 1 : 1)
            eventNumber += 1
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { return }
        event.flags = CGEventSource.flagsState(.hidSystemState).intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        event.setIntegerValueField(.mouseEventClickState, value: Int64(lastDown.clicks))
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        event.setDoubleValueField(.mouseEventPressure, value: isDown ? 1 : 0)
        log("click \(type.rawValue) clicks=\(lastDown.clicks) flags=\(String(event.flags.rawValue, radix: 16))")
        event.post(tap: .cghidEventTap)
    }

    /// NX_KEYTYPE_* media keys, sent as system-defined events like a real keyboard's media row.
    private static func media(_ key: Int, down: Bool) {
        let state = down ? 0xA00 : 0xB00
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | state, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}
