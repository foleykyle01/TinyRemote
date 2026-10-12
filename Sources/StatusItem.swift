import AppKit
import Combine

/// The menu-bar icon, built with AppKit rather than SwiftUI's MenuBarExtra. macOS remembers a removed menu-bar
/// item as hidden and MenuBarExtra can't override that, so "Show in the menu bar" did nothing once turned off.
/// Follows the `showMenuBarIcon` default.
final class StatusItem: NSObject, NSMenuDelegate {
    static let shared = StatusItem()
    static let defaultsKey = "showMenuBarIcon"

    private var item: NSStatusItem?
    private var observers: Set<AnyCancellable> = []

    private var shouldShow: Bool { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }

    func start() {
        apply()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &observers)
        Remote.shared.$problems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] problems in self?.updateIcon(problems) }
            .store(in: &observers)
    }

    /// Hiding removes the item and showing creates a fresh one, rather than toggling `isVisible`, so macOS is
    /// never asked to remember a "hidden" state for TinyRemote's icon.
    private func apply() {
        if shouldShow, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "TinyRemote"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
            updateIcon(Remote.shared.problems)
        } else if !shouldShow, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func updateIcon(_ problems: [String]) {
        let image = NSImage(systemSymbolName: problems.isEmpty ? "appletvremote.gen4" : "exclamationmark.triangle",
                            accessibilityDescription: "TinyRemote")
        image?.isTemplate = true
        item?.button?.image = image
    }

    // Rebuilt each time it opens so status and update text are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let problems = Remote.shared.problems
        if problems.isEmpty {
            add(menu, "Remote ready")
        } else {
            problems.forEach { add(menu, "⚠︎ \($0)") }
            add(menu, "Fix in Setup…") { SettingsWindow.show(.setup) }
        }
        menu.addItem(.separator())
        add(menu, "Settings…", key: ",") { SettingsWindow.show(.buttons) }
        add(menu, "Reconnect Remote") { Remote.shared.reconnect() }
        add(menu, "Check for Updates") { Updater.shared.check(install: true) }
        if !Updater.shared.status.isEmpty { add(menu, Updater.shared.status) }
        menu.addItem(.separator())
        add(menu, "Quit TinyRemote", key: "q") { NSApp.terminate(nil) }
    }

    /// Items without an action show as disabled text.
    private func add(_ menu: NSMenu, _ title: String, key: String = "", action: (() -> Void)? = nil) {
        let item = NSMenuItem(title: title, action: action == nil ? nil : #selector(run(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = action
        menu.addItem(item)
    }

    @objc private func run(_ sender: NSMenuItem) { (sender.representedObject as? () -> Void)?() }
}
