import AppKit

/// Turns action strings into synthetic input. Actions are either shortcuts
/// ("ctrl+shift+space", "cmd+tab", "f5", "key105") or one of `named`.
enum Actions {
    static let named: [(id: String, title: String)] = [
        ("left-click", "Left click"),
        ("right-click", "Right click"),
        ("play-pause", "Play / Pause"),
        ("next-track", "Next track"),
        ("previous-track", "Previous track"),
        ("volume-up", "Volume up"),
        ("volume-down", "Volume down"),
        ("mute", "Mute"),
    ]

    /// Shortcut presets shown in the picker; they're plain shortcuts, so users can record their own.
    static let presets: [(id: String, title: String)] = [
        ("ctrl+left", "Previous desktop"),
        ("ctrl+right", "Next desktop"),
        ("ctrl+up", "Mission Control"),
        ("ctrl+down", "App windows"),
        ("cmd+tab", "Switch app"),
        ("ctrl+shift+space", "FluidVoice dictation"),
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
    ]
    static let keyNames = Dictionary(keyCodes.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    static let modifiers: [(name: String, flag: CGEventFlags, symbol: String)] = [
        ("ctrl", .maskControl, "⌃"), ("opt", .maskAlternate, "⌥"), ("shift", .maskShift, "⇧"), ("cmd", .maskCommand, "⌘"),
    ]

    static func parseShortcut(_ action: String) -> (key: CGKeyCode, flags: CGEventFlags)? {
        var parts = action.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.popLast() else { return nil }
        var flags: CGEventFlags = []
        for part in parts {
            guard let modifier = modifiers.first(where: { $0.name == part || (part == "alt" && $0.name == "opt") }) else { return nil }
            flags.insert(modifier.flag)
        }
        guard let key = keyCodes[keyName] ?? (keyName.hasPrefix("key") ? CGKeyCode(keyName.dropFirst(3)) : nil) else { return nil }
        // Arrow and function keys carry these flags on real keyboards; Spaces switching ignores them otherwise.
        if (123...126).contains(key) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        if key >= 96 && key <= 122 && keyName.hasPrefix("f") { flags.insert(.maskSecondaryFn) }
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

    static func title(_ action: String) -> String {
        if action.isEmpty { return "—" }
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
        case "left-click": mouse(down ? .leftMouseDown : .leftMouseUp, .left); leftButtonDown = down
        case "right-click": mouse(down ? .rightMouseDown : .rightMouseUp, .right)
        case "play-pause": media(16, down: down)
        case "next-track": media(17, down: down)
        case "previous-track": media(18, down: down)
        case "volume-up": media(0, down: down)
        case "volume-down": media(1, down: down)
        case "mute": media(7, down: down)
        default:
            guard let (key, flags) = parseShortcut(action) else { return }
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func tap(_ action: String) {
        perform(action, down: true)
        usleep(15_000)
        perform(action, down: false)
    }

    static var cursorLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private static func mouse(_ type: CGEventType, _ button: CGMouseButton) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cursorLocation, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    /// NX_KEYTYPE_* media keys, sent as system-defined events like a real keyboard's media row.
    private static func media(_ key: Int, down: Bool) {
        let state = down ? 0xA00 : 0xB00
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | state, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}
