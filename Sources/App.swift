import SwiftUI

@main
struct TinyRemoteApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        guard CommandLine.arguments.contains("--self-test") else { return }
        assert(Actions.parseShortcut("ctrl+shift+space")! == (49, [.maskControl, .maskShift]))
        assert(Actions.parseShortcut("ctrl+right")!.flags.contains([.maskControl, .maskSecondaryFn]))
        assert(Actions.parseShortcut("cmd+key105")!.key == 105)
        assert(Actions.parseShortcut("hyper+x") == nil && Actions.parseShortcut("left-click") == nil)
        assert(Actions.shortcutString(keyCode: 49, flags: [.control, .shift]) == "ctrl+shift+space")
        assert(Actions.title("ctrl+shift+space") == "FluidVoice dictation" && Actions.title("cmd+opt+k") == "⌥⌘K")
        var config = Config()
        config.buttons[.mute] = Mapping(press: "mute")
        let json = try! JSONEncoder().encode(config)
        assert(String(decoding: json, as: UTF8.self).contains("\"mute\":{"))  // buttons encode as an object
        print("self-test passed")
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra("TinyRemote", systemImage: "appletvremote.gen4") { MenuContent() }
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

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var remote = Remote.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Text(remote.connected ? "Remote connected" : "Remote not connected")
        if !remote.exclusive { Text("Shared with another app — quit GoatRemote") }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Check for Updates") { updater.check(install: true) }
        if !updater.status.isEmpty { Text(updater.status) }
        Divider()
        Button("Quit TinyRemote") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
