import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case buttons = "Buttons", touch = "Touch Surface", voice = "Voice", shortcuts = "My Shortcuts", general = "General", setup = "Setup"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .buttons: "appletvremote.gen4"
        case .touch: "hand.point.up.left"
        case .voice: "mic"
        case .shortcuts: "command"
        case .general: "gearshape"
        case .setup: "checkmark.shield"
        }
    }
}

/// Shared so the menu bar can open a specific pane.
final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var pane: Pane? = Permissions.allGranted ? .buttons : .setup
}

struct SettingsView: View {
    @ObservedObject private var navigation = Navigation.shared

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $navigation.pane) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                .navigationSplitViewColumnWidth(170)
        } detail: {
            switch navigation.pane ?? .buttons {
            case .buttons: ButtonsPane()
            case .touch: TouchPane()
            case .voice: VoicePane()
            case .shortcuts: ShortcutsPane()
            case .general: GeneralPane()
            case .setup: SetupPane()
            }
        }
        .frame(minWidth: 980, minHeight: 720)

    }
}

// MARK: - Remote (pointer + per-button bindings)

/// A titled rounded panel; used instead of Form so custom rows keep their layout.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct ButtonsPane: View {
    @ObservedObject private var remote = Remote.shared
    @State private var selected = RemoteButton.tv
    /// nil = All apps; otherwise an app profile's ID.
    @State private var profileID: String?
    @State private var editingProfile: String?

    private var profile: AppProfile? { remote.config.profiles.first { $0.id == profileID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Mappings for")
                    Picker("Mappings for", selection: $profileID) {
                        Text("All apps").tag(String?.none)
                        ForEach(remote.config.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if let profileID { Button("Edit Profile…") { editingProfile = profileID } }
                    Button("New Profile…") {
                        let new = AppProfile(name: "New profile", bundleIDs: [])
                        remote.config.profiles.append(new)
                        profileID = new.id
                        editingProfile = new.id
                    }
                    Spacer()
                }
                Text(profile.map { "Overrides used while \(appList($0)) is in front. Buttons you don't customize use the All apps setting." }
                     ?? "Choose a button on the drawing, or press it on your remote.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 36) {
                    RemoteDrawing(selected: $selected)
                    ButtonEditor(button: $selected, profileID: profileID)
                }
                .padding(20)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
        .navigationTitle("Buttons")
        .onChange(of: remote.lastButton) { if let button = remote.lastButton { selected = button } }
        .onChange(of: remote.config.profiles.map(\.id)) { if profile == nil { profileID = nil } }
        .sheet(item: Binding(get: { editingProfile.map { IdentifiedID(id: $0) } }, set: { editingProfile = $0?.id })) { ProfileEditor(profileID: $0.id) }
    }

    private func appList(_ profile: AppProfile) -> String {
        let names = profile.bundleIDs.filter { AppInfo.url($0) != nil }.map(AppInfo.name)
        switch names.count {
        case 0: return "one of its apps"
        case 1: return names[0]
        case 2, 3: return names.dropLast().joined(separator: ", ") + " or " + names.last!
        default: return names.prefix(3).joined(separator: ", ") + " or another of its apps"
        }
    }
}

struct IdentifiedID: Identifiable { let id: String }

struct TouchPane: View {
    @ObservedObject private var remote = Remote.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Card(title: "Scrolling") {
                    toggleRow("Swipe with two fingers", $remote.config.twoFingerScrollEnabled)
                    toggleRow("Circle the outer ring (like an iPod)", $remote.config.ringScrollEnabled)
                    speedRow("Speed", $remote.config.scrollSpeed)
                        .disabled(!remote.config.twoFingerScrollEnabled && !remote.config.ringScrollEnabled)
                }
                Card(title: "Cursor") {
                    toggleRow("Move the cursor with one finger", $remote.config.trackpadEnabled)
                    speedRow("Speed", $remote.config.cursorSpeed).disabled(!remote.config.trackpadEnabled)
                }
                Card(title: "Clicking") {
                    touchRow("hand.point.up", "Click", "Press the clickpad.", select(\.press), Config.defaultButtons[.select]?.press ?? "")
                    Divider()
                    touchRow("hand.point.up.fill", "Click and hold", "Press and keep your thumb still. Move while pressing to drag instead.",
                             select(\.longPress), Config.defaultButtons[.select]?.longPress ?? "") {
                        HStack(spacing: 8) {
                            Text("Hold for").foregroundStyle(.secondary)
                            TextField("", value: holdMs, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("ms").foregroundStyle(.secondary)
                        }
                        .disabled(remote.config.buttons[.select]?.longPress.isEmpty ?? true)
                    }
                    Divider()
                    touchRow(Gesture.tap.icon, Gesture.tap.title, "Touch quickly without pressing.", gesture(.tap), Config.defaultGestures[.tap] ?? "")
                }
                Card(title: "Two fingers") {
                    ForEach([Gesture.twoFingerTap, .twoFingerClick]) { gesture in
                        touchRow(gesture.icon, gesture.title, gesture.detail, self.gesture(gesture), Config.defaultGestures[gesture] ?? "")
                        if gesture == .twoFingerTap { Divider() }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Touch Surface")
    }

    private func toggleRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).frame(maxWidth: .infinity, alignment: .leading) }
            .toggleStyle(.switch)
    }

    private func touchRow(_ icon: String, _ title: String, _ detail: String, _ action: Binding<String>, _ defaultAction: String,
                          @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                ActionField(action: action, defaultAction: defaultAction)
                extra()
            }
        }
    }

    /// The clickpad press is the remote's "select" button; its mapping is edited here, not on Buttons.
    private func select(_ field: WritableKeyPath<Mapping, String>) -> Binding<String> {
        Binding(get: { remote.config.buttons[.select, default: Mapping()][keyPath: field] },
                set: { remote.config.buttons[.select, default: Mapping()][keyPath: field] = $0 })
    }

    private func gesture(_ gesture: Gesture) -> Binding<String> {
        Binding(get: { remote.config.gestures[gesture] ?? "" }, set: { remote.config.gestures[gesture] = $0 })
    }

    private var holdMs: Binding<Double> {
        Binding(get: { remote.config.buttons[.select]?.longPressMs ?? remote.config.longPressMs },
                set: { remote.config.buttons[.select, default: Mapping()].longPressMs = max(150, $0) })
    }

    private func speedRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 0.3...3)
            Text(String(format: "%.2fx", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
        }
    }
}

/// A drawn Apple TV Remote (2nd/3rd gen); each control selects its button.
struct RemoteDrawing: View {
    @Binding var selected: RemoteButton

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 38)
                .fill(LinearGradient(colors: [Color(white: 0.88), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: 210, height: 540)
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
        .frame(width: 216, height: 540)
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
    var profileID: String?
    @ObservedObject private var remote = Remote.shared

    private var profileIndex: Int? { profileID.flatMap { id in remote.config.profiles.firstIndex { $0.id == id } } }
    private var globalMapping: Mapping { remote.config.buttons[button, default: Mapping()] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Button", selection: $button) {
                ForEach(RemoteButton.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .font(.title3)
            if button == .select {
                Text("The clickpad's click, click-and-hold and tap are set on the Touch Surface page.")
                    .foregroundStyle(.secondary)
                Button("Open Touch Surface") { Navigation.shared.pane = .touch }
            } else if let index = profileIndex, remote.config.profiles[index].buttons[button] == nil {
                Text("Uses the All apps setting: \(Actions.title(globalMapping.press)).").foregroundStyle(.secondary)
                Button("Customize for \(remote.config.profiles[index].name)") {
                    remote.config.profiles[index].buttons[button] = defaultMapping == Mapping() ? globalMapping : defaultMapping
                }
            } else {
                bindings
                if let index = profileIndex {
                    Button("Use the All apps setting instead") { remote.config.profiles[index].buttons[button] = nil }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var bindings: some View {
        VStack(alignment: .leading, spacing: 18) {
            row("Press", \.press)
            row("Release", \.release)
            row("Long press", \.longPress)
            HStack(spacing: 10) {
                Text("Long press after").foregroundStyle(.secondary)
                TextField("", value: longPressMs, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("ms").foregroundStyle(.secondary)
                Button {
                    update { $0.longPressMs = nil }
                } label: { Label("Default", systemImage: "arrow.counterclockwise") }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
                    .disabled(mapping.longPressMs == nil)
            }
            Text("Press runs when the button goes down, or on release if a long press is set. Release runs when you let go, which suits push-to-talk dictation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The mapping being edited: the profile's override, or the All apps mapping.
    private var mapping: Mapping { profileIndex.flatMap { remote.config.profiles[$0].buttons[button] } ?? globalMapping }

    /// What Default restores: the built-in profile's mapping, or the built-in All apps mapping.
    private var defaultMapping: Mapping {
        guard let index = profileIndex else { return Config.defaultButtons[button, default: Mapping()] }
        let id = remote.config.profiles[index].id
        return Config.defaultProfiles.first { $0.id == id }?.buttons[button] ?? Mapping()
    }

    private func update(_ change: (inout Mapping) -> Void) {
        if let index = profileIndex {
            var override = remote.config.profiles[index].buttons[button] ?? globalMapping
            change(&override)
            remote.config.profiles[index].buttons[button] = override
        } else {
            change(&remote.config.buttons[button, default: Mapping()])
        }
    }

    private var longPressMs: Binding<Double> {
        Binding(get: { mapping.longPressMs ?? remote.config.longPressMs },
                set: { value in update { $0.longPressMs = max(150, value) } })
    }

    private func row(_ title: String, _ field: WritableKeyPath<Mapping, String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            ActionField(action: Binding(get: { mapping[keyPath: field] },
                                        set: { value in update { $0[keyPath: field] = value } }),
                        defaultAction: defaultMapping[keyPath: field])
        }
    }
}

/// An action value (click for presets, saved shortcuts and actions), plus Capture and Default.
struct ActionField: View {
    @Binding var action: String
    var defaultAction: String
    @ObservedObject private var remote = Remote.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                Button("None") { action = "" }
                Divider()
                if !remote.config.customActions.isEmpty {
                    Section("My shortcuts") {
                        ForEach(remote.config.customActions) { custom in Button(custom.name) { action = "custom:\(custom.id)" } }
                    }
                }
                Section("Shortcuts") {
                    ForEach(Actions.presets, id: \.id) { preset in Button(preset.title) { action = preset.id } }
                }
                ForEach(Actions.namedGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.actions, id: \.id) { named in Button(named.title) { action = named.id } }
                    }
                }
            } label: {
                HStack {
                    Text(recorder.isRecording ? "Type a shortcut…" : (action.isEmpty ? "(none)" : Actions.title(action)))
                        .foregroundStyle(action.isEmpty && !recorder.isRecording ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(width: 220, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(recorder.isRecording ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Button {
                recorder.toggle { action = $0 }
            } label: { Label(recorder.isRecording ? "Cancel" : "Capture", systemImage: "record.circle") }
            Button { action = defaultAction } label: { Label("Default", systemImage: "arrow.counterclockwise") }
                .disabled(action == defaultAction)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// Captures the next key combo system-wide, swallowing it so reserved shortcuts (⌃→, ⌘Space)
/// can be recorded instead of firing. Falls back to window-only capture if the tap can't be created.
final class ShortcutRecorder: ObservableObject {
    @Published var isRecording = false
    private var onRecord: ((String) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?

    func toggle(onRecord: @escaping (String) -> Void) {
        if isRecording { stop(); return }
        self.onRecord = onRecord
        isRecording = true
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, type, event, context in
            guard type == .keyDown, let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<ShortcutRecorder>.fromOpaque(context).takeUnretainedValue()
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let shortcut = Actions.shortcutString(keyCode: keyCode, flags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
            DispatchQueue.main.async { recorder.finish(shortcut) }
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        } else {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.finish(Actions.shortcutString(keyCode: event.keyCode, flags: event.modifierFlags))
                return nil
            }
        }
    }

    private func finish(_ shortcut: String) {
        guard isRecording else { return }
        onRecord?(shortcut)
        stop()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        tap = nil
        source = nil
        monitor = nil
        onRecord = nil
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
                Toggle("Show in the menu bar", isOn: $remote.config.showMenuBarIcon)
                Toggle("Show in the Dock", isOn: $remote.config.showInDock)
                    .onChange(of: remote.config.showInDock) { Dock.apply() }
            } header: {
                Text("Appearance")
            } footer: {
                Text(remote.config.showMenuBarIcon || remote.config.showInDock
                     ? "TinyRemote also shows in the Dock while this window is open."
                     : "With both off, open TinyRemote from Applications or Spotlight to get back to Settings.")
                    .foregroundStyle(.secondary)
            }
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
                step("Apple TV Remote connected", remote.connected ? "Connected and ready." : "Pair it in Bluetooth settings: hold Back and Volume + near the Mac for 5 seconds.", done: remote.connected) {
                    Button("Bluetooth…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                }
                step("Exclusive access", remote.exclusive ? "Only TinyRemote handles the remote, so macOS won't also react to Play or Volume." : "Another app (like GoatRemote) is holding the remote. Quit it and remove it from Login Items.", done: remote.exclusive || !remote.connected) {
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
                    Button("Run Setup Again") { Onboarding.restart() }
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
