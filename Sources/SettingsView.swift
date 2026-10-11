import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case remote = "Remote", shortcuts = "My Shortcuts", general = "General", setup = "Setup"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .remote: "appletvremote.gen4"
        case .shortcuts: "command"
        case .general: "gearshape"
        case .setup: "checkmark.shield"
        }
    }
}

/// Shared so the menu bar can open a specific pane.
final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var pane: Pane? = Permissions.allGranted ? .remote : .setup
}

struct SettingsView: View {
    @ObservedObject private var navigation = Navigation.shared

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $navigation.pane) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                .navigationSplitViewColumnWidth(170)
        } detail: {
            switch navigation.pane ?? .remote {
            case .remote: RemotePane()
            case .shortcuts: ShortcutsPane()
            case .general: GeneralPane()
            case .setup: SetupPane()
            }
        }
        .frame(minWidth: 860, minHeight: 680)
        .onAppear { NSApp.activate() }
    }
}

// MARK: - Remote (pointer + per-button bindings)

struct RemotePane: View {
    @ObservedObject private var remote = Remote.shared
    @State private var selected = RemoteButton.tv

    var body: some View {
        Form {
            Section("Pointer") {
                Toggle("Move the cursor with the touch surface", isOn: $remote.config.trackpadEnabled)
                LabeledContent("Cursor speed") {
                    Slider(value: $remote.config.cursorSpeed, in: 0.3...3)
                    Text(String(format: "%.2fx", remote.config.cursorSpeed)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle("Tap to click", isOn: $remote.config.tapToClick)
                Toggle("Circle the outer ring to scroll", isOn: $remote.config.ringScrollEnabled)
                LabeledContent("Scroll speed") {
                    Slider(value: $remote.config.scrollSpeed, in: 0.3...3)
                    Text(String(format: "%.2fx", remote.config.scrollSpeed)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Section {
                HStack(alignment: .top, spacing: 32) {
                    RemoteDrawing(selected: $selected)
                    ButtonEditor(button: $selected)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Button bindings")
            } footer: {
                Text("Click a button on the drawing or press it on your remote. Two fingers on the touch surface also scroll.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Remote")
        .onChange(of: remote.lastButton) { if let button = remote.lastButton { selected = button } }
    }
}

/// A drawn Siri Remote (2nd/3rd gen); each control selects its button.
struct RemoteDrawing: View {
    @Binding var selected: RemoteButton

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 38)
                .fill(LinearGradient(colors: [Color(white: 0.88), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: 210, height: 500)
            control(.mic, systemImage: nil, shape: Capsule(), width: 6, height: 52)
                .offset(x: 3, y: 150)
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    control(.power, systemImage: "power", size: 38)
                }
                .padding(.horizontal, 22)
                clickpad
                HStack(spacing: 22) {
                    VStack(spacing: 16) {
                        control(.back, systemImage: "chevron.left", size: 62)
                        control(.playPause, systemImage: "playpause.fill", size: 62)
                        control(.mute, systemImage: "speaker.slash.fill", size: 62)
                    }
                    VStack(spacing: 16) {
                        control(.tv, systemImage: "tv", size: 62)
                        VStack(spacing: 0) {
                            control(.volumeUp, systemImage: "plus", shape: UnevenRoundedRectangle(topLeadingRadius: 31, topTrailingRadius: 31), width: 62, height: 70)
                            control(.volumeDown, systemImage: "minus", shape: UnevenRoundedRectangle(bottomLeadingRadius: 31, bottomTrailingRadius: 31), width: 62, height: 70)
                        }
                    }
                }
            }
            .padding(.top, 18)
            .frame(width: 210)
        }
        .frame(width: 216, height: 500)
    }

    private var clickpad: some View {
        ZStack {
            Circle().fill(Color(white: 0.1)).frame(width: 176, height: 176)
            control(.select, systemImage: nil, size: 92)
            control(.up, systemImage: "circle.fill", size: 36, iconScale: 0.15).offset(y: -66)
            control(.down, systemImage: "circle.fill", size: 36, iconScale: 0.15).offset(y: 66)
            control(.left, systemImage: "circle.fill", size: 36, iconScale: 0.15).offset(x: -66)
            control(.right, systemImage: "circle.fill", size: 36, iconScale: 0.15).offset(x: 66)
        }
    }

    private func control(_ button: RemoteButton, systemImage: String?, size: CGFloat, iconScale: CGFloat = 0.32) -> some View {
        control(button, systemImage: systemImage, shape: Circle(), width: size, height: size, iconScale: iconScale)
    }

    private func control(_ button: RemoteButton, systemImage: String?, shape: some Shape, width: CGFloat, height: CGFloat, iconScale: CGFloat = 0.32) -> some View {
        let isSelected = selected == button
        return Button { selected = button } label: {
            ZStack {
                shape.fill(isSelected ? Color.accentColor.opacity(0.85) : Color(white: 0.13))
                shape.stroke(isSelected ? Color.accentColor : Color(white: 0.3), lineWidth: isSelected ? 2.5 : 1)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: min(width, height) * iconScale, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: width, height: height)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(button.title)
    }
}

struct ButtonEditor: View {
    @Binding var button: RemoteButton
    @ObservedObject private var remote = Remote.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Button", selection: $button) {
                ForEach(RemoteButton.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 220)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                row("Press", \.press)
                row("Release", \.release)
                row("Long press", \.longPress)
                GridRow {
                    Text("Long press after")
                    HStack {
                        TextField("ms", value: longPressMs, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("ms").foregroundStyle(.secondary)
                    }
                    Button {
                        remote.config.buttons[button, default: Mapping()].longPressMs = nil
                    } label: { Label("Default", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .disabled(mapping.longPressMs == nil)
                }
            }
            Text("Press runs when the button goes down (or on release if a long press is set). Release runs when you let go — useful for push-to-talk dictation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mapping: Mapping { remote.config.buttons[button, default: Mapping()] }

    private var longPressMs: Binding<Double> {
        Binding(get: { mapping.longPressMs ?? remote.config.longPressMs },
                set: { remote.config.buttons[button, default: Mapping()].longPressMs = max(150, $0) })
    }

    private func row(_ title: String, _ field: WritableKeyPath<Mapping, String>) -> some View {
        let defaultValue = Config.defaultButtons[button, default: Mapping()][keyPath: field]
        return GridRow {
            Text(title)
            ActionField(action: Binding(get: { mapping[keyPath: field] },
                                        set: { remote.config.buttons[button, default: Mapping()][keyPath: field] = $0 }),
                        defaultAction: defaultValue)
        }
    }
}

/// Shows an action with a picker (presets, saved shortcuts, actions), Capture, and Default.
struct ActionField: View {
    @Binding var action: String
    var defaultAction: String
    @ObservedObject private var remote = Remote.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        HStack(spacing: 10) {
            Menu(recorder.isRecording ? "Type a shortcut…" : Actions.title(action)) {
                if !remote.config.customActions.isEmpty {
                    Section("My shortcuts") {
                        ForEach(remote.config.customActions) { custom in Button(custom.name) { action = "custom:\(custom.id)" } }
                    }
                }
                Section("Shortcuts") {
                    ForEach(Actions.presets, id: \.id) { preset in Button(preset.title) { action = preset.id } }
                }
                Section("Actions") {
                    ForEach(Actions.named, id: \.id) { named in Button(named.title) { action = named.id } }
                }
                Divider()
                Button("None") { action = "" }
            }
            .frame(width: 200)
            Button {
                recorder.toggle { action = $0 }
            } label: { Label(recorder.isRecording ? "Cancel" : "Capture", systemImage: "record.circle") }
                .buttonStyle(.borderless)
            Button { action = defaultAction } label: { Label("Default", systemImage: "arrow.counterclockwise") }
                .buttonStyle(.borderless)
                .disabled(action == defaultAction)
        }
    }
}

/// Captures the next key combo typed while the settings window is focused.
/// ponytail: local monitor only; system-reserved combos (⌃←, ⌘Space) never reach it, so those are presets.
final class ShortcutRecorder: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?

    func toggle(onRecord: @escaping (String) -> Void) {
        if isRecording { stop(); return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            onRecord(Actions.shortcutString(keyCode: event.keyCode, flags: event.modifierFlags))
            self?.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    deinit { stop() }
}

// MARK: - My Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var remote = Remote.shared
    @State private var draft = CustomAction(name: "", value: "")
    @State private var editingID: String?
    @StateObject private var recorder = ShortcutRecorder()
    @State private var testStatus = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Start dictation"))
                Picker("Type", selection: $draft.kind) {
                    Text("Keyboard shortcut").tag(CustomAction.Kind.shortcut)
                    Text("AppleScript").tag(CustomAction.Kind.script)
                }
                .pickerStyle(.segmented)
                switch draft.kind {
                case .shortcut:
                    LabeledContent("Shortcut") {
                        Text(draft.value.isEmpty ? "Not recorded" : Actions.title(draft.value))
                            .foregroundStyle(draft.value.isEmpty ? .secondary : .primary)
                        Button(recorder.isRecording ? "Type a shortcut… (click to cancel)" : "Record") {
                            recorder.toggle { draft.value = $0 }
                        }
                    }
                case .script:
                    TextEditor(text: $draft.value)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if draft.value.isEmpty {
                                Text("tell application \"Music\" to playpause").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false)
                            }
                        }
                }
                HStack {
                    Button("Test") { test(draft) }.disabled(draft.value.isEmpty)
                    Text(testStatus).foregroundStyle(.secondary)
                    Spacer()
                    if editingID != nil { Button("Cancel") { resetDraft() } }
                    Button(editingID == nil ? "Add Shortcut" : "Save Changes") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.value.isEmpty)
                }
            } header: {
                Text(editingID == nil ? "New shortcut" : "Edit shortcut")
            } footer: {
                Text("Saved shortcuts appear under \"My shortcuts\" in every button's menu. Test waits 2 seconds so you can switch to the app it's for.")
                    .foregroundStyle(.secondary)
            }

            Section("Saved") {
                if remote.config.customActions.isEmpty {
                    Text("No saved shortcuts yet.").foregroundStyle(.secondary)
                }
                ForEach(remote.config.customActions) { custom in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(custom.name)
                            Text(custom.kind == .shortcut ? Actions.title(custom.value) : "AppleScript")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Test") { test(custom) }
                        Button("Edit") {
                            draft = custom
                            editingID = custom.id
                        }
                        Button(role: .destructive) { delete(custom) } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My Shortcuts")
    }

    private func test(_ custom: CustomAction) {
        testStatus = "Running in 2 seconds…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            switch custom.kind {
            case .shortcut: Actions.tap(custom.value)
            case .script: Actions.runAppleScript(custom.value)
            }
            testStatus = "Sent \(custom.kind == .shortcut ? Actions.title(custom.value) : "script")"
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        if let index = remote.config.customActions.firstIndex(where: { $0.id == editingID }) {
            remote.config.customActions[index] = draft
        } else {
            remote.config.customActions.append(draft)
        }
        resetDraft()
    }

    private func delete(_ custom: CustomAction) {
        let reference = "custom:\(custom.id)"
        remote.config.customActions.removeAll { $0.id == custom.id }
        for button in RemoteButton.allCases {
            var mapping = remote.config.buttons[button, default: Mapping()]
            for field in [\Mapping.press, \.release, \.longPress] where mapping[keyPath: field] == reference { mapping[keyPath: field] = "" }
            remote.config.buttons[button] = mapping
        }
        if editingID == custom.id { resetDraft() }
    }

    private func resetDraft() {
        recorder.stop()
        draft = CustomAction(name: "", value: "")
        editingID = nil
        testStatus = ""
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
                LabeledContent("Default long press") {
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
                    Button("Reset Buttons to Defaults", role: .destructive) { remote.config.buttons = Config.defaultButtons }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Setup (onboarding + diagnostics)

struct SetupPane: View {
    @ObservedObject private var remote = Remote.shared
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var accessibility = Permissions.accessibility
    @State private var lastInput = "No input yet"
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
                step("Siri Remote connected", "Pair it in Bluetooth settings: hold Back and Volume + near the Mac for 5 seconds.", done: remote.connected) {
                    Button("Bluetooth…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                }
                step("Exclusive access", "Another app (like GoatRemote) is holding the remote. Quit it and remove it from Login Items.", done: remote.exclusive || !remote.connected) {
                    Button("Retry") { remote.openHID() }
                }
            } header: {
                Text("Get TinyRemote ready")
            } footer: {
                Text("macOS applies Input Monitoring after TinyRemote restarts.").foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                LabeledContent("Last input", value: lastInput)
                LabeledContent("Last button", value: remote.lastButton?.title ?? "—")
                HStack {
                    Button("Reconnect Remote") { remote.reconnect() }
                    Button("Restart TinyRemote") { Updater.relaunch() }
                    Button("Show Log") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/TinyRemote.log")) }
                }
                Text("If the remote shows as connected in Bluetooth but nothing happens here when you press a button, use Reconnect Remote. TinyRemote also reconnects automatically after sleep.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .onReceive(poll) { _ in
            inputMonitoring = Permissions.inputMonitoring
            accessibility = Permissions.accessibility
            if let at = remote.lastInputAt {
                let seconds = Int(Date().timeIntervalSince(at))
                lastInput = seconds < 2 ? "Just now" : "\(seconds) s ago"
            }
        }
    }

    private func step(_ title: String, _ detail: String, done: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(done ? .green : .orange)
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
