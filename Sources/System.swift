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

/// Updates from GitHub releases over HTTPS (public repo, no login). URLSession downloads aren't quarantined,
/// so the unnotarized app still opens. Releases are signed with the same certificate, so permissions survive updates.
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
        guard let data = fetch("https://api.github.com/repos/\(Self.repo)/releases/latest"),
              let release = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = release["tag_name"] as? String else { return "Couldn't reach GitHub" }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard latest.compare(current, options: .numeric) == .orderedDescending else { return "Up to date (\(current))" }
        guard install else { return "Version \(latest) is available" }

        let assets = release["assets"] as? [[String: Any]] ?? []
        guard let url = assets.first(where: { $0["name"] as? String == "TinyRemote.zip" })?["browser_download_url"] as? String,
              let zip = fetch(url) else { return "Download of \(latest) failed" }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TinyRemote-update")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zipPath = dir.appendingPathComponent("TinyRemote.zip")
        guard (try? zip.write(to: zipPath)) != nil, run("/usr/bin/ditto", ["-x", "-k", zipPath.path, dir.path]) else {
            return "Unpacking \(latest) failed"
        }
        do {
            _ = try FileManager.default.replaceItemAt(Bundle.main.bundleURL, withItemAt: dir.appendingPathComponent("TinyRemote.app"))
        } catch {
            return "Install of \(latest) failed: \(error.localizedDescription)"
        }
        log("updated to \(latest)")
        DispatchQueue.main.async { Self.relaunch() }
        return "Updated to \(latest), restarting…"
    }

    /// Blocking GET; only called off the main thread.
    private func fetch(_ url: String) -> Data? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("TinyRemote/\(current)", forHTTPHeaderField: "User-Agent")
        var result: Data?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { result = data }
            done.signal()
        }.resume()
        done.wait()
        return result
    }

    static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundleURL.path]
        try? shell.run()
        NSApp.terminate(nil)
    }

    private func run(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
