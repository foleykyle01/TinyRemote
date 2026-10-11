import AppKit
import IOKit.hid
import ServiceManagement

enum Permissions {
    static var inputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var allGranted: Bool { inputMonitoring && accessibility }

    static func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { openPane("Privacy_ListenEvent") }
    }

    static func requestAccessibility() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(prompt) { openPane("Privacy_Accessibility") }
    }

    static func openPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

enum LoginItem {
    static var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { _ = try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }

    /// Open at login by default, once; after that the user's choice sticks.
    static func enableOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: "loginItemConfigured") else { return }
        enabled = true
        UserDefaults.standard.set(true, forKey: "loginItemConfigured")
    }
}

/// Updates from GitHub releases via the `gh` CLI, which works with the private repo and
/// doesn't quarantine downloads (the app isn't notarized). Releases are signed with the same
/// certificate, so permissions survive updates.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "foleykyle01/TinyRemote"

    @Published var status = ""
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var timer: Timer?

    func schedule() {
        timer = .scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkIfAuto() }
        checkIfAuto()
    }

    private func checkIfAuto() { if Remote.shared.config.autoUpdate { check(install: true) } }

    func check(install: Bool) {
        status = "Checking…"
        DispatchQueue.global().async {
            let result = self.update(install: install)
            DispatchQueue.main.async { self.status = result }
        }
    }

    private func update(install: Bool) -> String {
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: FileManager.default.isExecutableFile) else {
            return "Updates need the GitHub CLI: brew install gh"
        }
        guard let tag = run(gh, ["api", "repos/\(Self.repo)/releases/latest", "--jq", ".tag_name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else { return "Couldn't reach GitHub (is gh logged in?)" }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard latest.compare(current, options: .numeric) == .orderedDescending else { return "Up to date (\(current))" }
        guard install else { return "Version \(latest) is available" }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TinyRemote-update")
        try? FileManager.default.removeItem(at: dir)
        let zip = dir.appendingPathComponent("TinyRemote.zip").path
        guard run(gh, ["release", "download", tag, "-R", Self.repo, "-p", "TinyRemote.zip", "-D", dir.path]) != nil,
              run("/usr/bin/ditto", ["-x", "-k", zip, dir.path]) != nil else { return "Download of \(latest) failed" }
        do {
            _ = try FileManager.default.replaceItemAt(Bundle.main.bundleURL, withItemAt: dir.appendingPathComponent("TinyRemote.app"))
        } catch {
            return "Install of \(latest) failed: \(error.localizedDescription)"
        }
        log("updated to \(latest)")
        DispatchQueue.main.async { Self.relaunch() }
        return "Updated to \(latest), restarting…"
    }

    static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundleURL.path]
        try? shell.run()
        NSApp.terminate(nil)
    }

    private func run(_ path: String, _ args: [String]) -> String? {
        let process = Process(), out = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
