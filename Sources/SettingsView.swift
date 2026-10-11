import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case buttons = "Buttons", trackpad = "Trackpad", general = "General", setup = "Setup"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .buttons: "circle.grid.cross"
        case .trackpad: "hand.point.up.left"
        case .general: "gearshape"
        case .setup: "checkmark.shield"
        }
    }
}

struct SettingsView: View {
    @State private var pane: Pane? = Permissions.allGranted ? .buttons : .setup

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                .navigationSplitViewColumnWidth(160)
        } detail: {
            switch pane ?? .buttons {
            case .buttons: ButtonsPane()
            case .trackpad: TrackpadPane()
            case .general: GeneralPane()
            case .setup: SetupPane()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { NSApp.activate() }
    }
}

// MARK: - Buttons

struct ButtonsPane: View {
    @ObservedObject private var remote = Remote.shared

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Button").bold()
                        Text("Press").bold()
                        Text("Long press").bold()
                        Text("Release").bold()
                    }
                    Divider()
                    ForEach(RemoteButton.allCases) { button in
                        GridRow {
                            Text(button.title)
                                .foregroundStyle(remote.lastButton == button ? Color.accentColor : .primary)
                                .fontWeight(remote.lastButton == button ? .semibold : .regular)
                            ActionPicker(action: binding(button, \.press))
                            ActionPicker(action: binding(button, \.longPress))
                            ActionPicker(action: binding(button, \.release))
                        }
                    }
                }
            } footer: {
                Text("Press a button on the remote to highlight its row. Release runs when you let go; the mic button uses it to stop dictation.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Buttons")
    }

    private func binding(_ button: RemoteButton, _ field: WritableKeyPath<Mapping, String>) -> Binding<String> {
        Binding(get: { remote.config.buttons[button, default: Mapping()][keyPath: field] },
                set: { remote.config.buttons[button, default: Mapping()][keyPath: field] = $0 })
    }
}

/// Pick a preset/action or record any shortcut.
struct ActionPicker: View {
    @Binding var action: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        if recording {
            Button("Type shortcut…") { stopRecording() }
                .buttonStyle(.borderedProminent)
                .frame(width: 170, alignment: .leading)
        } else {
            Menu(Actions.title(action)) {
                Button("Record shortcut…") { startRecording() }
                Section("Shortcuts") {
                    ForEach(Actions.presets, id: \.id) { preset in Button(preset.title) { action = preset.id } }
                }
                Section("Actions") {
                    ForEach(Actions.named, id: \.id) { named in Button(named.title) { action = named.id } }
                }
                Divider()
                Button("None") { action = "" }
            }
            .frame(width: 170, alignment: .leading)
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            action = Actions.shortcutString(keyCode: event.keyCode, flags: event.modifierFlags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

// MARK: - Trackpad

struct TrackpadPane: View {
    @ObservedObject private var remote = Remote.shared

    var body: some View {
        Form {
            Section {
                Toggle("Move the cursor with the touch surface", isOn: $remote.config.trackpadEnabled)
                LabeledContent("Cursor speed") { Slider(value: $remote.config.cursorSpeed, in: 0.3...3) }
                Toggle("Tap to click", isOn: $remote.config.tapToClick)
            }
            Section {
                Toggle("Circle the outer ring to scroll", isOn: $remote.config.ringScrollEnabled)
                LabeledContent("Scroll speed") { Slider(value: $remote.config.scrollSpeed, in: 0.3...3) }
            } footer: {
                Text("Touches that start on the ring's edge scroll; touches in the middle move the cursor.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Trackpad")
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var remote = Remote.shared
    @ObservedObject private var updater = Updater.shared
    @State private var openAtLogin = LoginItem.enabled

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin).onChange(of: openAtLogin) { LoginItem.enabled = openAtLogin }
                LabeledContent("Long press after") {
                    Slider(value: $remote.config.longPressMs, in: 250...1200, step: 50)
                    Text("\(Int(remote.config.longPressMs)) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            Section("Updates") {
                Toggle("Install updates automatically", isOn: $remote.config.autoUpdate)
                LabeledContent("Version \(updater.current)") {
                    Text(updater.status).foregroundStyle(.secondary)
                    Button("Check Now") { updater.check(install: true) }
                }
            }
            Section("Mappings") {
                HStack {
                    Button("Show Config File") { NSWorkspace.shared.activateFileViewerSelecting([Config.url]) }
                    Button("Reset to Defaults", role: .destructive) { remote.config.buttons = Config.defaultButtons }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Setup (onboarding)

struct SetupPane: View {
    @ObservedObject private var remote = Remote.shared
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var accessibility = Permissions.accessibility
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                step("Input Monitoring", "Lets TinyRemote read the remote's buttons and touch surface.", done: inputMonitoring) {
                    Button("Grant…") { Permissions.requestInputMonitoring() }
                }
                step("Accessibility", "Lets TinyRemote send shortcuts, clicks and cursor movement.", done: accessibility) {
                    Button("Grant…") { Permissions.requestAccessibility() }
                }
                step("Siri Remote connected", "Pair it in Bluetooth settings: hold Back and Volume + for 5 seconds near the Mac.", done: remote.connected) {
                    Button("Bluetooth…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                }
                step("Exclusive access", "Quit GoatRemote (and remove it from login items) so only TinyRemote handles the remote.", done: remote.exclusive) {
                    Button("Retry") { remote.openHID() }
                }
            } header: {
                Text("Get TinyRemote ready")
            } footer: {
                Text("macOS applies Input Monitoring after a restart of the app.").foregroundStyle(.secondary)
            }
            Section {
                Button("Restart TinyRemote") { Updater.relaunch() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .onReceive(poll) { _ in
            inputMonitoring = Permissions.inputMonitoring
            accessibility = Permissions.accessibility
        }
    }

    private func step(_ title: String, _ detail: String, done: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { action() }
        }
        .padding(.vertical, 4)
    }
}
