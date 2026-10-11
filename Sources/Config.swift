import Foundation

enum RemoteButton: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable {
    case up, down, left, right, select, back, tv, playPause, mute, volumeUp, volumeDown, power, mic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Center click"
        case .back: "Back"
        case .tv: "TV"
        case .playPause: "Play / Pause"
        case .mute: "Mute"
        case .volumeUp: "Volume +"
        case .volumeDown: "Volume −"
        case .power: "Power"
        case .mic: "Mic (side)"
        }
    }

    /// HID (usage page, usage) reported by the Siri Remote (2nd/3rd gen), from discovery.
    static func from(page: UInt32, usage: UInt32) -> RemoteButton? {
        switch (page, usage) {
        case (0x0C, 0x42): .up
        case (0x0C, 0x43): .down
        case (0x0C, 0x44): .left
        case (0x0C, 0x45): .right
        case (0x0C, 0x80): .select
        case (0x01, 0x86): .back
        case (0x0C, 0x60): .tv
        case (0x0C, 0xCD): .playPause
        case (0x0C, 0xE2): .mute
        case (0x0C, 0xE9): .volumeUp
        case (0x0C, 0xEA): .volumeDown
        case (0x0C, 0x30): .power
        case (0x0C, 0x04): .mic
        default: nil
        }
    }

    var repeatsWhileHeld: Bool { [.up, .down, .left, .right].contains(self) }
}

/// Touch-surface gestures that run an action, mapped like buttons.
enum Gesture: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable {
    case tap, twoFingerTap, twoFingerClick
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tap: "Tap"
        case .twoFingerTap: "Two-finger tap"
        case .twoFingerClick: "Two-finger click"
        }
    }

    var detail: String {
        switch self {
        case .tap: "A quick touch with one finger."
        case .twoFingerTap: "A quick touch with two fingers."
        case .twoFingerClick: "Press the clickpad while two fingers rest on it."
        }
    }

    var icon: String {
        switch self {
        case .tap: "hand.tap"
        case .twoFingerTap: "hand.tap.fill"
        case .twoFingerClick: "hand.point.up.left.and.text"
        }
    }
}

/// An action is a string: a shortcut like "ctrl+right", a named action (see Actions.swift), or
/// "custom:<id>" for one of the user's saved shortcuts. Empty string means nothing.
struct Mapping: Codable, Equatable {
    var press = ""
    var release = ""
    var longPress = ""
    /// nil uses the global long-press delay.
    var longPressMs: Double?
}

/// Per-app button overrides, used while one of `bundleIDs` is the frontmost app.
struct AppProfile: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var bundleIDs: [String]
    /// Only overridden buttons; the rest use the All apps mapping.
    var buttons: [RemoteButton: Mapping] = [:]
    /// Fall back to All apps while a text field has focus (Back stays Delete while typing).
    var exceptWhenTyping = true
}

/// A named shortcut or AppleScript the user saved; mapped to buttons as "custom:<id>".
struct CustomAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case shortcut, script }
    var id = UUID().uuidString
    var name: String
    var kind = Kind.shortcut
    /// A shortcut string ("ctrl+shift+space") or AppleScript source.
    var value: String
}

struct Config: Codable, Equatable {
    var buttons: [RemoteButton: Mapping] = Config.defaultButtons
    var longPressMs = 500.0
    var trackpadEnabled = true
    var gestures: [Gesture: String] = Config.defaultGestures
    var twoFingerScrollEnabled = true
    var cursorSpeed = 1.0
    var ringScrollEnabled = true
    var scrollSpeed = 1.0
    var autoUpdate = true
    var showMenuBarIcon = true
    var showInDock = false
    var customActions: [CustomAction] = []
    var voice = VoiceSettings()
    var profiles: [AppProfile] = Config.defaultProfiles

    static let defaultProfiles = [
        AppProfile(id: "browsers", name: "Web browsers", bundleIDs: [
            "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
            "company.thebrowser.Browser", "company.thebrowser.dia", "com.microsoft.edgemac", "org.mozilla.firefox",
            "com.brave.Browser", "com.kagi.kagimacOS", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        ], buttons: [.back: Mapping(press: "cmd+[", longPress: "cmd+]")]),
    ]

    /// The mapping for `button` given the frontmost app. `isTyping` is only asked when a profile
    /// would apply, since it queries Accessibility.
    func mapping(for button: RemoteButton, app bundleID: String?, isTyping: () -> Bool) -> Mapping {
        if let bundleID, let profile = profiles.first(where: { $0.bundleIDs.contains(bundleID) }),
           let override = profile.buttons[button], !(profile.exceptWhenTyping && isTyping()) {
            return override
        }
        return buttons[button] ?? Mapping()
    }

    static let defaultGestures: [Gesture: String] = [.tap: "left-click", .twoFingerTap: "right-click", .twoFingerClick: "right-click"]

    static let defaultButtons: [RemoteButton: Mapping] = [
        .up: Mapping(press: "up"),
        .down: Mapping(press: "down"),
        .left: Mapping(press: "left"),
        .right: Mapping(press: "right"),
        .select: Mapping(press: "left-click", longPress: "right-click"),
        .back: Mapping(press: "delete"),
        .tv: Mapping(press: "return", longPress: "right-click"),
        .playPause: Mapping(press: "play-pause"),
        .mute: Mapping(),
        .volumeUp: Mapping(press: "ctrl+left"),
        .volumeDown: Mapping(press: "ctrl+right"),
        .power: Mapping(press: "escape"),
        .mic: Mapping(),
    ]

    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TinyRemote")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    /// Saved values are layered over the defaults, so settings added in later versions
    /// don't invalidate an existing config file.
    static func load() -> Config {
        guard let saved = (try? Data(contentsOf: url)).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
              let defaults = (try? JSONEncoder().encode(Config())).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
        else { return Config() }
        var merged = defaults.merging(saved) { _, new in new }
        // Also layer keyed groups (buttons, gestures) so new entries get their defaults.
        for (key, value) in defaults {
            if let defaultGroup = value as? [String: Any], let savedGroup = saved[key] as? [String: Any] {
                merged[key] = defaultGroup.merging(savedGroup) { _, new in new }
            }
        }
        if saved["tapToClick"] as? Bool == false, (saved["gestures"] as? [String: Any])?["tap"] == nil {
            merged["gestures"] = (merged["gestures"] as? [String: Any] ?? [:]).merging(["tap": ""]) { _, new in new }  // pre-0.2 setting
        }
        return (try? JSONSerialization.data(withJSONObject: merged)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
    }

    /// Set by the self-test so it never touches the real config file.
    static var readOnly = false

    func save() {
        guard !Config.readOnly else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Config.url, options: .atomic)
    }
}
