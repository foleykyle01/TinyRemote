import SwiftUI

/// A small floating panel shown next to System Settings with TinyRemote's icon to drag into the privacy list.
/// macOS doesn't always add the app to Input Monitoring on its own, and dragging the app in always works.
enum PermissionHelper {
    enum Kind {
        case inputMonitoring, accessibility
        var title: String { self == .inputMonitoring ? "Input Monitoring" : "Accessibility" }
        var isGranted: Bool { self == .inputMonitoring ? Permissions.inputMonitoring : Permissions.accessibility }
    }

    private static var panel: NSPanel?

    static func show(_ kind: Kind) {
        panel?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 250),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Allow \(kind.title)"
        panel.level = .floating  // stay above System Settings
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: PermissionHelperView(kind: kind) { close() })
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 340, y: screen.minY + 40))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    static func close() {
        panel?.close()
        panel = nil
    }
}

struct PermissionHelperView: View {
    let kind: PermissionHelper.Kind
    let done: () -> Void
    var preview = false  // snapshot mode: always show the drag state
    @State private var granted = false
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("\(kind.title) is on").font(.headline)
                if kind == .inputMonitoring {
                    Text("Restart TinyRemote to finish.").foregroundStyle(.secondary)
                    Button("Restart TinyRemote") { Updater.relaunch() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Done", action: done).buttonStyle(.borderedProminent)
                }
            } else {
                Text("Drag TinyRemote into the \(kind.title) list, then turn it on.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                    .help("Drag into the list in System Settings")
                Text("If TinyRemote is already listed, just turn its switch on.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(width: 320, height: 250)
        .onReceive(poll) { _ in
            if preview { return }
            granted = kind.isGranted
            if granted && kind == .accessibility { DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: done) }
        }
    }
}
