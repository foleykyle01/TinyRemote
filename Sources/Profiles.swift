import SwiftUI
import UniformTypeIdentifiers

/// Whether the user is typing: the focused element is an editable text control.
enum Focus {
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func isTyping() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)  // never stall a button press on a busy app
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if textRoles.contains(role as? String ?? "") { return true }
        // Rich editors in web pages (contenteditable) expose a settable text selection.
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success && settable.boolValue
    }
}

enum AppInfo {
    static func url(_ bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    static func name(_ bundleID: String) -> String {
        url(bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    static func icon(_ bundleID: String) -> NSImage {
        url(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
    }
}

/// Sheet for a profile's name, apps and typing behavior.
struct ProfileEditor: View {
    let profileID: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var remote = Remote.shared

    private var index: Int? { remote.config.profiles.firstIndex { $0.id == profileID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let index {
                TextField("Profile name", text: $remote.config.profiles[index].name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Text("Used when one of these apps is in front").font(.headline)
                let installed = remote.config.profiles[index].bundleIDs.filter { AppInfo.url($0) != nil }
                let missing = remote.config.profiles[index].bundleIDs.count - installed.count
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(installed, id: \.self) { bundleID in
                            HStack {
                                Image(nsImage: AppInfo.icon(bundleID)).resizable().frame(width: 24, height: 24)
                                Text(AppInfo.name(bundleID))
                                Spacer()
                                Button { remote.config.profiles[index].bundleIDs.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        if installed.isEmpty { Text("No apps yet.").foregroundStyle(.secondary) }
                    }
                }
                .frame(maxHeight: 220)
                if missing > 0 {
                    Text("Also covers \(missing) app\(missing == 1 ? "" : "s") that aren't installed on this Mac.").font(.callout).foregroundStyle(.secondary)
                }
                Button("Add App…") { addApps(to: index) }
                Toggle("Use the All apps setting while typing in a text field", isOn: $remote.config.profiles[index].exceptWhenTyping)
                Text("Keeps Back as Delete in an address bar or search box.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Delete Profile", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.async { remote.config.profiles.removeAll { $0.id == profileID } }
                    }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func addApps(to index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !remote.config.profiles[index].bundleIDs.contains(bundleID) else { continue }
            remote.config.profiles[index].bundleIDs.append(bundleID)
        }
    }
}
