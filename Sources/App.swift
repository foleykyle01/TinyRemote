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
