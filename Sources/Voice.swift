import SwiftUI

/// How the mic button drives a dictation app. The page writes the result into the mic button's mapping.
struct VoiceSettings: Codable, Equatable {
    enum AppMode: String, Codable { case toggle, hold }
    enum MicStyle: String, Codable { case holdToTalk, tapToToggle }

    var app = "FluidVoice"
    /// The dictation app's start/stop shortcut, e.g. "ctrl+shift+space".
    var shortcut = ""
    var appMode = AppMode.toggle
    var micStyle = MicStyle.holdToTalk

    var mapping: Mapping {
        guard !shortcut.isEmpty else { return Mapping() }
        switch (appMode, micStyle) {
        case (.hold, _): return Mapping(press: "hold:" + shortcut)
        case (.toggle, .holdToTalk): return Mapping(press: shortcut, release: shortcut)
        case (.toggle, .tapToToggle): return Mapping(press: shortcut)
        }
    }
}

struct DictationApp: Identifiable {
    let name: String
    /// App bundle name to look for in /Applications; nil for built-in or "Other".
    let bundleName: String?
    let note: String
    var id: String { name }

    var installedURL: URL? {
        guard let bundleName else { return nil }
        return ["/Applications", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: "\($0)/\(bundleName).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let fnNote = "Another app can't press Fn/Globe by itself, so give it a key combo such as ⌃⌥Space."
    static let all = [
        DictationApp(name: "FluidVoice", bundleName: "FluidVoice", note: "TinyRemote reads FluidVoice's shortcut and mode for you."),
        DictationApp(name: "Wispr Flow", bundleName: "Wispr Flow", note: "In Wispr Flow's settings, set a dictation shortcut, then capture it here. \(fnNote)"),
        DictationApp(name: "superwhisper", bundleName: "superwhisper", note: "Capture the recording shortcut from superwhisper's settings."),
        DictationApp(name: "VoiceInk", bundleName: "VoiceInk", note: "Capture the recording shortcut from VoiceInk's settings. \(fnNote)"),
        DictationApp(name: "MacWhisper", bundleName: "MacWhisper", note: "Capture MacWhisper's dictation shortcut from its settings."),
        DictationApp(name: "Apple Dictation", bundleName: nil, note: "In System Settings → Keyboard → Dictation, set Shortcut to Customize… with a key combo (not Fn/Globe or Control twice), then capture it here."),
        DictationApp(name: "Other", bundleName: nil, note: "Capture the shortcut your dictation app uses to start and stop."),
    ]
}

enum FluidVoiceSettings {
    /// FluidVoice's first key-combo dictation shortcut and its mode, read from its preferences.
    /// Modifier-only shortcuts (e.g. Right Option alone) are skipped.
    static func read() -> (shortcut: String, mode: VoiceSettings.AppMode)? {
        guard let defaults = UserDefaults(suiteName: "com.FluidApp.app"),
              let data = defaults.data(forKey: "PrimaryDictationShortcuts"),
              let shortcuts = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let modifierKeyCodes = 54...63
        guard let entry = shortcuts.first(where: { ($0["keyCode"] as? Int).map { !modifierKeyCodes.contains($0) } ?? false }),
              let keyCode = entry["keyCode"] as? Int else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(entry["modifierFlagsRawValue"] as? Int ?? 0))
        let mode = (defaults.string(forKey: "HotkeyMode") ?? "toggle").lowercased()
        return (Actions.shortcutString(keyCode: UInt16(keyCode), flags: flags), mode.contains("hold") || mode.contains("push") ? .hold : .toggle)
    }
}

struct VoicePane: View {
    @ObservedObject private var remote = Remote.shared
    @StateObject private var recorder = ShortcutRecorder()
    @State private var status = ""
    @State private var testing = false

    private var voice: Binding<VoiceSettings> { $remote.config.voice }
    private var app: DictationApp { DictationApp.all.first { $0.name == remote.config.voice.app } ?? DictationApp.all.last! }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Card(title: "Dictation app") {
                    HStack {
                        Picker("App", selection: voice.app) {
                            ForEach(DictationApp.all) { app in
                                Text(app.installedURL != nil ? "\(app.name) (installed)" : app.name).tag(app.name)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        if let url = app.installedURL {
                            Button("Open \(app.name)") { NSWorkspace.shared.open(url) }
                        }
                    }
                    Text(app.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                Card(title: "Shortcut") {
                    HStack(spacing: 14) {
                        Text(recorder.isRecording ? "Type the shortcut…" : (voice.wrappedValue.shortcut.isEmpty ? "Not set" : Actions.title(voice.wrappedValue.shortcut)))
                            .font(.title3.monospaced())
                            .foregroundStyle(voice.wrappedValue.shortcut.isEmpty && !recorder.isRecording ? .secondary : .primary)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 180, minHeight: 34, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        Button { recorder.toggle { voice.wrappedValue.shortcut = $0 } } label: {
                            Label(recorder.isRecording ? "Cancel" : "Capture", systemImage: "record.circle")
                        }
                        if app.name == "FluidVoice" {
                            Button { readFluidVoice() } label: { Label("Read from FluidVoice", systemImage: "arrow.down.doc") }
                        }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.titleAndIcon)
                    if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }

                    Picker("The app listens", selection: voice.appMode) {
                        Text("Toggle: shortcut starts and stops").tag(VoiceSettings.AppMode.toggle)
                        Text("Hold: listens while the shortcut is held").tag(VoiceSettings.AppMode.hold)
                    }
                    .pickerStyle(.radioGroup)
                    if voice.wrappedValue.appMode == .toggle {
                        Picker("Mic button", selection: voice.micStyle) {
                            Text("Hold to talk").tag(VoiceSettings.MicStyle.holdToTalk)
                            Text("Tap to start, tap to stop").tag(VoiceSettings.MicStyle.tapToToggle)
                        }
                        .pickerStyle(.radioGroup)
                    }
                }

                Card(title: "Mic button") {
                    if remote.config.buttons[.mic] == remote.config.voice.mapping {
                        Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("The mic button has a different mapping on the Buttons page.", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Use These Settings") { apply() }
                        }
                    }
                    HStack {
                        Button(testing ? "Speak now…" : "Test (holds the mic button for 3 seconds)") { test() }
                            .disabled(testing || remote.config.voice.shortcut.isEmpty)
                        Text("Switch to a text field first if your app types where the cursor is.").font(.callout).foregroundStyle(.secondary)
                    }
                }

                Card(title: "Use the remote's own microphone") {
                    Text("Not available yet. Your dictation app records from the microphone chosen in that app, such as your AirPods or the Mac's built-in mic.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why it's off").font(.headline)
                        bullet("macOS doesn't let apps use the Siri Remote's microphone. The only known way is to turn on Bluetooth debug logging for the whole Mac and read the remote's audio out of that log with admin rights.")
                        bullet("That log includes private data from every Bluetooth device, and the capture grows in memory while it runs.")
                        bullet("It needs Apple's PacketLogger (a free developer download), an admin password, a configuration profile, and an extra audio driver.")
                        bullet("The remote only sends audio while the mic button is held.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Voice")
        .onAppear { if remote.config.voice.app == "FluidVoice" && remote.config.voice.shortcut.isEmpty { readFluidVoice() } }
        .onChange(of: remote.config.voice) { apply() }
    }

    private var summary: String {
        let v = remote.config.voice
        if v.shortcut.isEmpty { return "Mic button does nothing until a shortcut is set." }
        switch (v.appMode, v.micStyle) {
        case (.hold, _): return "Hold the mic button to dictate with \(v.app) (holds \(Actions.title(v.shortcut)))."
        case (.toggle, .holdToTalk): return "Hold the mic button to dictate with \(v.app); release to stop."
        case (.toggle, .tapToToggle): return "Tap the mic button to start \(v.app), tap again to stop."
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func apply() { remote.config.buttons[.mic] = remote.config.voice.mapping }

    private func readFluidVoice() {
        guard let found = FluidVoiceSettings.read() else {
            status = "Couldn't find a key-combo shortcut in FluidVoice. Add one in FluidVoice's settings (a modifier key alone won't work), or capture it here."
            return
        }
        remote.config.voice.shortcut = found.shortcut
        remote.config.voice.appMode = found.mode
        status = "Read from FluidVoice: \(Actions.title(found.shortcut)), \(found.mode == .toggle ? "toggle" : "hold") mode."
    }

    private func test() {
        testing = true
        remote.simulatePress(.mic, holdFor: 3) { testing = false }
    }
}
