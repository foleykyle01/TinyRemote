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
        var config = Config()
        config.buttons[.mute] = Mapping(press: "mute")
        let json = try! JSONEncoder().encode(config)
        assert(String(decoding: json, as: UTF8.self).contains("\"mute\":{"))  // buttons encode as an object
        print("self-test passed")
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra { MenuContent() } label: { MenuBarIcon() }
        Window("TinyRemote", id: "settings") { SettingsView() }
            .defaultLaunchBehavior(Permissions.allGranted ? .suppressed : .presented)
            .windowResizability(.contentSize)
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
    }
}

/// Turns into a warning when the remote can't work (permission lost, disconnected, held by another app).
struct MenuBarIcon: View {
    @ObservedObject private var remote = Remote.shared
    var body: some View {
        Image(systemName: remote.problems.isEmpty ? "appletvremote.gen4" : "exclamationmark.triangle")
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var remote = Remote.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if remote.problems.isEmpty {
            Text("Remote ready")
        } else {
            ForEach(remote.problems, id: \.self) { Text("⚠︎ \($0)") }
            Button("Fix in Setup…") { open(.setup) }
        }
        Divider()
        Button("Settings…") { open(.remote) }.keyboardShortcut(",")
        Button("Reconnect Remote") { remote.reconnect() }
        Button("Check for Updates") { updater.check(install: true) }
        if !updater.status.isEmpty { Text(updater.status) }
        Divider()
        Button("Quit TinyRemote") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func open(_ pane: Pane) {
        Navigation.shared.pane = pane
        openWindow(id: "settings")
        NSApp.activate()
    }
}

extension AppDelegate {
    /// Dev tool: renders each settings pane to PNG (dark mode) without screen-recording permission.
    /// Usage: TinyRemote --snapshot /tmp/shots
    func snapshot(to directory: String) {
        Config.readOnly = true
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for pane in Pane.allCases {
            Navigation.shared.pane = pane
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 980, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: SettingsView())
            window.orderFrontRegardless()  // off-screen, but composited so the window server can capture it
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))  // let SwiftUI settle
            // CGWindowListCreateImage is marked unavailable for new code but still works for our own windows.
            typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            let capture = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage"), to: Capture.self)
            guard let image = capture(.null, CGWindowListOption.optionIncludingWindow.rawValue, CGWindowID(window.windowNumber),
                                      CGWindowImageOption([.boundsIgnoreFraming, .bestResolution]).rawValue)?.takeRetainedValue() else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(directory)/\(pane.rawValue).png"))
            window.close()
        }
        exit(0)
    }
}
