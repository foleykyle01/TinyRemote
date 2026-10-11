import SwiftUI

/// First-run guide: welcome, permissions, pairing, a quick try, done. Progress survives the restart
/// macOS needs after Input Monitoring is granted.
enum Onboarding {
    private static let completeKey = "onboardingComplete"
    static let stepKey = "onboardingStep"

    /// New installs only: someone with a saved config already set TinyRemote up.
    static var shouldShow: Bool {
        if UserDefaults.standard.bool(forKey: completeKey) { return false }
        if FileManager.default.fileExists(atPath: Config.url.path) {
            UserDefaults.standard.set(true, forKey: completeKey)
            return false
        }
        return true
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: completeKey)
        UserDefaults.standard.set(0, forKey: stepKey)
        Remote.shared.config.save()  // marks this Mac as set up even if nothing was changed
    }

    static func restart() {
        UserDefaults.standard.set(0, forKey: stepKey)
        OnboardingWindow.show()
    }
}

enum OnboardingWindow {
    static var enabled = true  // off in snapshot mode
    private static var window: NSWindow?
    static var isOpen: Bool { window?.isVisible == true }

    static func show() {
        guard enabled else { return }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
            window.title = "Welcome to TinyRemote"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                DispatchQueue.main.async { Dock.apply() }
            }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func close() { window?.close() }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, permissions, remote, tryIt, done }

    @AppStorage(Onboarding.stepKey) private var stepIndex = 0
    @ObservedObject private var remote = Remote.shared
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var accessibility = Permissions.accessibility
    @State private var openAtLogin = LoginItem.enabled
    @State private var lastInput: Date?
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// Snapshot mode passes a fixed step.
    var fixedStep: Step?
    private var step: Step { fixedStep ?? Step(rawValue: stepIndex) ?? .welcome }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 28 : 8, height: 8)
                }
            }
            .padding(.top, 8)
            .animation(.easeInOut, value: step)

            content
                .frame(maxWidth: .infinity, alignment: step == .welcome || step == .done ? .center : .leading)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)

            HStack {
                if step != .welcome && step != .done {
                    Button("Back") { stepIndex = step.rawValue - 1 }
                }
                Spacer()
                footerButtons
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 600, height: 540)
        .onReceive(poll) { _ in
            inputMonitoring = Permissions.inputMonitoring
            accessibility = Permissions.accessibility
            lastInput = remote.lastInputAt
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                Text("Welcome to TinyRemote").font(.largeTitle.bold())
                Text("Use your Siri Remote to control your Mac: buttons, a trackpad, scrolling and push-to-talk dictation. Setup takes about a minute.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 20) {
                header("Allow access", "macOS asks you to approve two permissions. TinyRemote only uses them for the remote.")
                permissionRow("Input Monitoring", "Reads the remote's buttons and touch surface.", granted: inputMonitoring) {
                    Permissions.requestInputMonitoring()
                }
                permissionRow("Accessibility", "Sends the shortcuts, clicks and cursor movement you choose.", granted: accessibility) {
                    Permissions.requestAccessibility()
                }
                if needsRestart {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                        Text("macOS needs TinyRemote to restart to finish turning on Input Monitoring.")
                        Spacer()
                        Button("Restart") { Updater.relaunch() }
                    }
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        case .remote:
            VStack(alignment: .leading, spacing: 20) {
                header("Connect your Siri Remote", "Works with the aluminum Siri Remote (2nd and 3rd generation).")
                VStack(alignment: .leading, spacing: 10) {
                    numbered(1, "Bring the remote close to your Mac.")
                    numbered(2, "Hold Back and Volume + together for about 5 seconds.")
                    numbered(3, "Choose it in Bluetooth settings when it appears.")
                }
                Button("Open Bluetooth Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                }
                status(remote.connected, done: "Siri Remote connected", waiting: "Waiting for the remote…")
            }
        case .tryIt:
            VStack(alignment: .leading, spacing: 20) {
                header("Give it a try", "Everything below can be changed later in Settings.")
                VStack(alignment: .leading, spacing: 10) {
                    numbered(1, "Press any button. Its name appears below.")
                    numbered(2, "Slide your thumb on the clickpad to move the pointer.")
                    numbered(3, "Tap or press the clickpad to click. Press and hold still to right-click.")
                    numbered(4, "Circle the outer ring, or swipe with two fingers, to scroll.")
                }
                HStack {
                    Image(systemName: "appletvremote.gen4").font(.title)
                    VStack(alignment: .leading) {
                        Text(remote.lastButton?.title ?? "Press a button on your remote").font(.title3.bold())
                        Text(lastInput.map { Date().timeIntervalSince($0) < 2 ? "Input received" : "Last input a moment ago" } ?? "No input yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        case .done:
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                Text("You're all set").font(.largeTitle.bold())
                Text("TinyRemote runs from the remote icon in the menu bar. Open Settings any time to remap buttons, set up gestures and dictation, or add app profiles.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Toggle("Open TinyRemote at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { LoginItem.enabled = openAtLogin }
                    .toggleStyle(.switch)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private var footerButtons: some View {
        switch step {
        case .welcome:
            Button("Get Started") { stepIndex = Step.permissions.rawValue }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        case .permissions:
            Button("Continue") { stepIndex = Step.remote.rawValue }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!(inputMonitoring && accessibility) || needsRestart)
        case .remote:
            if !remote.connected { Button("Skip for Now") { stepIndex = Step.tryIt.rawValue } }
            Button("Continue") { stepIndex = Step.tryIt.rawValue }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!remote.connected)
        case .tryIt:
            Button("Continue") { stepIndex = Step.done.rawValue }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        case .done:
            Button("Open Settings") {
                Onboarding.finish()
                OnboardingWindow.close()
                SettingsWindow.show(.buttons)
            }
            Button("Done") {
                Onboarding.finish()
                OnboardingWindow.close()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    /// Granted after launch: reading the remote only starts after a restart.
    private var needsRestart: Bool { inputMonitoring && !Remote.launchedWithInputMonitoring }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ title: String, _ detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title).foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant…", action: request) }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.callout.bold()).frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func status(_ done: Bool, done doneText: String, waiting: String) -> some View {
        HStack(spacing: 10) {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(done ? doneText : waiting).foregroundStyle(done ? .primary : .secondary)
        }
        .font(.headline)
    }
}
