import SwiftUI

@main
struct TinyRemoteApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        guard CommandLine.arguments.contains("--self-test") else { return }
        Config.readOnly = true
        assert(Actions.parseShortcut("ctrl+shift+space")! == (49, [.maskControl, .maskShift]))
        assert(Actions.parseShortcut("ctrl+right")!.flags.contains([.maskControl, .maskSecondaryFn]))
        assert(Actions.parseShortcut("cmd+key105")!.key == 105)
        assert(Actions.parseShortcut("hyper+x") == nil && Actions.parseShortcut("left-click") == nil)
        assert(Actions.shortcutString(keyCode: 49, flags: [.control, .shift]) == "ctrl+shift+space")
        assert(Actions.parseShortcut("ctrl+fn+right")!.flags.contains([.maskControl, .maskSecondaryFn]))  // GoatRemote style
        assert(Actions.parseShortcut("command+shift+5")! == (23, [.maskCommand, .maskShift]))
        assert(Actions.parseShortcut("cmd")! == (55, []) && Actions.parseShortcut("f20")!.key == 90)
        assert(Actions.parseShortcut("num5")!.flags.contains(.maskNumericPad) && Actions.parseShortcut("f")!.flags.isEmpty)
        assert(Actions.parseShortcut("eject") == nil && Actions.title("eject") == "Eject")
        assert(Actions.title("ctrl+shift+space") == "⌃⇧Space" && Actions.title("cmd+opt+k") == "⌥⌘K")
        Remote.shared.config.customActions = [CustomAction(id: "t", name: "Dictate", value: "ctrl+shift+space")]
        assert(Actions.title("custom:t") == "Dictate" && Actions.title("custom:gone") == "Deleted shortcut")
        var voice = VoiceSettings(shortcut: "ctrl+shift+space")
        assert(voice.mapping == Mapping(press: "ctrl+shift+space", release: "ctrl+shift+space"))
        voice.micStyle = .tapToToggle
        assert(voice.mapping == Mapping(press: "ctrl+shift+space"))
        voice.appMode = .hold
        assert(voice.mapping == Mapping(press: "hold:ctrl+shift+space") && Actions.isHeld(voice.mapping.press))
        assert(Actions.title("hold:ctrl+shift+space") == "Hold ⌃⇧Space" && !Actions.isHeld("double-click"))
        assert(VoiceSettings().mapping == Mapping())
        let profiles = Config()
        assert(profiles.mapping(for: .back, app: "com.apple.Safari", isTyping: { false }).press == "cmd+[")
        assert(profiles.mapping(for: .back, app: "com.google.Chrome", isTyping: { true }).press == "delete")  // typing keeps Delete
        assert(profiles.mapping(for: .back, app: "com.microsoft.Word", isTyping: { fatalError("no profile, no AX query") }).press == "delete")
        assert(profiles.mapping(for: .tv, app: "com.apple.Safari", isTyping: { false }).press == "return")  // not overridden
        var config = Config()
        config.buttons[.mute] = Mapping(press: "mute")
        let json = try! JSONEncoder().encode(config)
        assert(String(decoding: json, as: UTF8.self).contains("\"mute\":{"))  // buttons encode as an object
        assert(String(decoding: json, as: UTF8.self).contains("\"twoFingerTap\":\"right-click\""))
        print("self-test passed")
        exit(0)
    }

    var body: some Scene {
        // The menu-bar icon is an AppKit StatusItem; SwiftUI just needs a scene. ⌘, opens TinyRemote's own window.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindow.show() }.keyboardShortcut(",")
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") { return snapshot(to: CommandLine.arguments[index + 1]) }
        freopen(NSHomeDirectory() + "/Library/Logs/TinyRemote.log", "a", stderr)
        log("TinyRemote \(Updater.shared.current) started")
        LoginItem.enableOnFirstLaunch()
        Remote.shared.start()
        Updater.shared.schedule()
        StatusItem.shared.start()
        Dock.apply()
        if Onboarding.shouldShow {
            OnboardingWindow.show()
        } else if !Permissions.allGranted {
            SettingsWindow.show(.setup)
        }
    }

    /// Opening TinyRemote again (Finder, Spotlight, Dock) shows Settings, the way back when the
    /// menu-bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.show()
        return false
    }
}

/// The settings window, managed directly so it can be opened from the menu bar, on reopen, and at first launch.
/// A menu-bar-only app can't take focus from the front app, so TinyRemote shows in the Dock while it's open.
enum SettingsWindow {
    static var enabled = true  // off in snapshot mode
    private(set) static var window: NSWindow?

    static var isOpen: Bool { window?.isVisible == true }

    static func show(_ pane: Pane? = nil) {
        guard enabled else { return }
        if let pane { Navigation.shared.pane = pane }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: hosting)
            window.title = "TinyRemote"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 980, height: 760))
            window.center()
            window.setFrameAutosaveName("TinyRemoteSettings")
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                DispatchQueue.main.async { Dock.apply() }  // after the window is no longer visible
            }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Dock icon: always when "Show in the Dock" is on, otherwise only while Settings is open.
enum Dock {
    static func apply() {
        let windowOpen = SettingsWindow.isOpen || OnboardingWindow.isOpen
        NSApp.setActivationPolicy(Remote.shared.config.showInDock || windowOpen ? .regular : .accessory)
    }
}

extension AppDelegate {
    /// Dev tool: renders each settings pane to PNG (dark mode) without screen-recording permission.
    /// Usage: TinyRemote --snapshot /tmp/shots
    func snapshot(to directory: String) {
        Config.readOnly = true
        SettingsWindow.enabled = false
        OnboardingWindow.enabled = false
        Remote.shared.connected = true  // show the ready state in docs; snapshot mode doesn't attach to the remote
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let pages: [(String, AnyView, NSSize)] = Pane.allCases.map { ($0.rawValue, AnyView(SettingsView()), NSSize(width: 980, height: 820)) }
            + OnboardingView.Step.allCases.map { ("Onboarding \($0.rawValue + 1)", AnyView(OnboardingView(fixedStep: $0)), NSSize(width: 600, height: 540)) }
        for (name, view, size) in pages {
            if let pane = Pane(rawValue: name) { Navigation.shared.pane = pane }
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: 0), size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: view)
            window.orderFrontRegardless()  // off-screen, but composited so the window server can capture it
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))  // let SwiftUI settle
            // CGWindowListCreateImage is marked unavailable for new code but still works for our own windows.
            typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            let capture = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage"), to: Capture.self)
            guard let image = capture(.null, CGWindowListOption.optionIncludingWindow.rawValue, CGWindowID(window.windowNumber),
                                      CGWindowImageOption([.boundsIgnoreFraming, .bestResolution]).rawValue)?.takeRetainedValue() else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(directory)/\(name).png"))
            window.close()
        }
        exit(0)
    }
}
