import AppKit
import IOKit.hid

let remoteVendorID = 76    // Apple
let remoteProductID = 788  // Apple TV Remote (2nd/3rd gen)

func log(_ message: String) {
    fputs("\(Date()) \(message)\n", stderr)
    fflush(stderr)
}

/// Reads the Apple TV Remote (buttons via HID, touch surface via MultitouchSupport) and runs the mapped actions.
final class Remote: ObservableObject {
    static let shared = Remote()
    /// Input Monitoring only takes effect for a process started after it was granted.
    static let launchedWithInputMonitoring = Permissions.inputMonitoring

    @Published var config = Config.load() { didSet { config.save() } }
    @Published var lastButton: RemoteButton?
    @Published var connected = false
    /// False when another app (e.g. GoatRemote) holds the remote exclusively, so macOS and that app also react.
    @Published var exclusive = true
    /// Human-readable reasons the remote may not work; drives the menu-bar warning and Setup page.
    @Published var problems: [String] = []
    /// Not published: touch frames arrive ~60×/s. Setup polls it.
    private(set) var lastInputAt: Date?

    private let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var holds: [RemoteButton: Hold] = [:]
    private var hidOpened = false
    private var healthTimer: Timer?

    private struct Hold {
        /// The mapping the press started with, so release matches it (e.g. a two-finger click).
        var mapping = Mapping()
        var clickHeld = false
        /// A click with a long press set waits: release = click, move = drag, hold still = long press.
        var pendingClick = false
        var longPressFired = false
        var timers: [Timer] = []
    }

    func start() {
        _ = Remote.launchedWithInputMonitoring  // capture at launch
        // Only the buttons interface; the touch surface is read through MultitouchSupport.
        IOHIDManagerSetDeviceMatching(hid, [
            kIOHIDVendorIDKey: remoteVendorID, kIOHIDProductIDKey: remoteProductID,
            kIOHIDPrimaryUsagePageKey: 0x0C, kIOHIDPrimaryUsageKey: 0x01,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hid, { context, _, _, value in
            let element = IOHIDValueGetElement(value)
            guard let button = RemoteButton.from(page: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element)) else { return }
            Unmanaged<Remote>.fromOpaque(context!).takeUnretainedValue().button(button, down: IOHIDValueGetIntegerValue(value) != 0)
        }, context)
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, _, _, _ in
            let remote = Unmanaged<Remote>.fromOpaque(context!).takeUnretainedValue()
            remote.connected = true
            log("remote connected")
            // The touch surface reappears a moment after the remote reconnects.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Touch.startRemoteDevices() }
            remote.checkHealth()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, _ in
            let remote = Unmanaged<Remote>.fromOpaque(context!).takeUnretainedValue()
            remote.releaseAll()
            remote.connected = (IOHIDManagerCopyDevices(remote.hid) as? Set<IOHIDDevice>)?.isEmpty == false
            log("remote disconnected")
            remote.checkHealth()
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        openHID()
        Touch.onFrame = { [weak self] points in self?.touch(points) }
        Touch.startRemoteDevices()

        // Sleep drops the touch surface and can leave a click held; rebuild everything on wake.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.releaseAll()
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.reconnect() }
        }
        healthTimer = .scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkHealth() }
        checkHealth()
    }

    /// Seize the remote so macOS doesn't also act on Play/Volume; fall back to shared access.
    func openHID() {
        if hidOpened {
            // Closing also unschedules the manager, so put it back on the run loop.
            IOHIDManagerClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        let wasOpened = hidOpened, wasExclusive = exclusive
        hidOpened = true
        exclusive = IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
        if !exclusive { IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if !wasOpened || exclusive != wasExclusive { log("hid opened, exclusive: \(exclusive)") }  // retries every 5 s; log changes only
    }

    /// Full restart of both input paths; used after wake and by the Setup page's Reconnect button.
    func reconnect() {
        log("reconnecting")
        releaseAll()
        openHID()
        Touch.restart()
        checkHealth()
    }

    /// Let go of anything held (a click mid-drag, repeat timers) so nothing stays stuck.
    func releaseAll() {
        for hold in holds.values {
            hold.timers.forEach { $0.invalidate() }
            if hold.clickHeld { Actions.perform(hold.mapping.press, down: false) }
        }
        holds.removeAll()
        touchMode = .none
    }

    func checkHealth() {
        if connected && !exclusive { openHID() }  // GoatRemote (or similar) may have quit since
        var found: [String] = []
        if !Permissions.inputMonitoring { found.append("Input Monitoring is off") }
        if !Permissions.accessibility { found.append("Accessibility is off") }
        if !connected { found.append("Apple TV Remote not connected") } else if !exclusive { found.append("Another app is using the remote") }
        if found != problems { problems = found }
    }

    // MARK: Buttons

    private func button(_ button: RemoteButton, down: Bool) {
        var binding = holds[button]?.mapping
            ?? config.mapping(for: button, app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, isTyping: Focus.isTyping)
        // Clicking with two fingers resting on the pad is its own gesture (right click by default).
        if down, button == .select, fingerCount >= 2, let action = config.gestures[.twoFingerClick], !action.isEmpty {
            binding = Mapping(press: action)
        }
        log("\(button) \(down ? "down" : "up")")
        lastInputAt = Date()
        cursorFrozenUntil = Date().addingTimeInterval(0.15)  // pressing buttons nudges the finger on the pad
        if down {
            lastButton = button
            buttonDuringTouch = true
            var hold = Hold(mapping: binding)
            if binding.press.hasSuffix("-click") { dragTravel = 0 }
            if !binding.longPress.isEmpty {
                hold.pendingClick = binding.press.hasSuffix("-click")
                let delay = (binding.longPressMs ?? config.longPressMs) / 1000
                hold.timers.append(.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.holds[button]?.longPressFired = true
                    self?.holds[button]?.pendingClick = false
                    Actions.tap(binding.longPress)
                })
            } else if Actions.isHeld(binding.press) {
                Actions.perform(binding.press, down: true)  // held until release: drags, push-to-talk keys
                hold.clickHeld = true
            } else {
                Actions.tap(binding.press)
                if button.repeatsWhileHeld && Actions.parseShortcut(binding.press) != nil {
                    hold.timers.append(.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                        self?.holds[button]?.timers.append(.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in Actions.tap(binding.press) })
                    })
                }
            }
            holds[button] = hold
        } else {
            guard let hold = holds.removeValue(forKey: button) else { return }
            hold.timers.forEach { $0.invalidate() }
            if hold.clickHeld {
                Actions.perform(binding.press, down: false)
            } else if !binding.longPress.isEmpty && !hold.longPressFired {
                Actions.tap(binding.press)
            }
            Actions.tap(binding.release)
        }
    }

    /// Presses a button as if on the remote (Voice page's Test).
    func simulatePress(_ button: RemoteButton, holdFor seconds: TimeInterval, completion: @escaping () -> Void) {
        self.button(button, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.button(button, down: false)
            completion()
        }
    }

    // MARK: Touch surface

    private enum TouchMode { case none, cursor, ringScroll, twoFingerScroll }
    private var touchMode = TouchMode.none
    private var lastPoint = CGPoint.zero
    private var lastAngle = 0.0
    private var scrollRemainder = CGVector.zero
    private var touchStart = Date()
    private var touchTravel = 0.0
    private var buttonDuringTouch = false
    private var fingerCount = 0
    private var maxFingers = 0
    private var cursorFrozenUntil = Date.distantPast
    /// Finger travel since the click went down; pressing the clickpad nudges the finger, so ignore small moves.
    private var dragTravel = 0.0
    private let dragDeadZone = 0.06

    /// `points` are touching fingers in normalized pad coordinates (origin bottom-left); empty on lift.
    private func touch(_ points: [CGPoint]) {
        fingerCount = points.count
        guard config.trackpadEnabled else { touchMode = .none; return }
        guard let first = points.first else {
            // A quick, still touch is a tap; skip it if a button was physically pressed meanwhile.
            let isTap = !buttonDuringTouch && Date().timeIntervalSince(touchStart) < 0.3 && touchTravel < 0.05
            if isTap && maxFingers >= 2 {
                Actions.tap(config.gestures[.twoFingerTap] ?? "")
            } else if isTap && touchMode == .cursor {
                Actions.tap(config.gestures[.tap] ?? "")
            }
            touchMode = .none
            return
        }
        maxFingers = max(maxFingers, points.count)
        lastInputAt = Date()
        // Two fingers scroll in both directions; stay in scroll mode until all fingers lift.
        let point = points.count >= 2 ? CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2) : first
        let angle = atan2(point.y - 0.5, point.x - 0.5)
        defer { lastPoint = point; lastAngle = angle }
        if points.count >= 2 && touchMode != .twoFingerScroll {
            if touchMode == .none {  // both fingers landed together
                touchStart = Date()
                touchTravel = 0
                buttonDuringTouch = false
            }
            touchMode = .twoFingerScroll
            scrollRemainder = .zero
            return
        }
        if touchMode == .none {
            // Starting on the outer ring scrolls (circle it like an iPod); anywhere else moves the cursor.
            let onRing = hypot(point.x - 0.5, point.y - 0.5) > 0.38
            touchMode = config.ringScrollEnabled && onRing ? .ringScroll : .cursor
            scrollRemainder = .zero
            touchStart = Date()
            touchTravel = 0
            buttonDuringTouch = false
            maxFingers = points.count
            return
        }
        let dx = point.x - lastPoint.x, dy = lastPoint.y - point.y
        switch touchMode {
        case .cursor:
            touchTravel += hypot(dx, dy)
            if Date() < cursorFrozenUntil { return }
            let pending = holds.first { $0.value.pendingClick }?.key
            if Actions.leftButtonDown || pending != nil {
                dragTravel += hypot(dx, dy)
                if dragTravel < dragDeadZone { return }
                if let pending { startDrag(pending) }
            }
            // ponytail: fixed accel curve; tune or make it a setting if it feels off.
            let gain = 900 * config.cursorSpeed * (1 + min(hypot(dx, dy) * 40, 3))
            moveCursor(by: CGVector(dx: dx * gain, dy: dy * gain))
        case .ringScroll:
            var delta = angle - lastAngle
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            scroll(by: CGVector(dx: 0, dy: delta * 400))  // clockwise scrolls down
        case .twoFingerScroll:
            if points.count < 2 { return }  // one finger lifted first; don't jump
            touchTravel += hypot(dx, dy)
            guard config.twoFingerScrollEnabled, touchTravel > 0.02 else { return }  // still might be a tap
            scroll(by: CGVector(dx: dx * 1500, dy: -dy * 1500))  // content follows the fingers
        case .none: break
        }
    }

    /// The finger moved while a pending click was held: it's a drag, so press the button now.
    private func startDrag(_ button: RemoteButton) {
        guard var hold = holds[button] else { return }
        hold.timers.forEach { $0.invalidate() }
        hold.timers = []
        hold.pendingClick = false
        hold.clickHeld = true
        holds[button] = hold
        Actions.perform(hold.mapping.press, down: true)
    }

    private func scroll(by delta: CGVector) {
        scrollRemainder.dx += delta.dx * config.scrollSpeed
        scrollRemainder.dy += delta.dy * config.scrollSpeed
        let x = scrollRemainder.dx.rounded(.towardZero), y = scrollRemainder.dy.rounded(.towardZero)
        scrollRemainder.dx -= x
        scrollRemainder.dy -= y
        guard x != 0 || y != 0 else { return }
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(y), wheel2: Int32(x), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    private func moveCursor(by delta: CGVector) {
        var bounds = CGRect.null
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        for id in ids.prefix(Int(count)) { bounds = bounds.union(CGDisplayBounds(id)) }
        let current = Actions.cursorLocation
        let target = CGPoint(x: min(max(current.x + delta.dx, bounds.minX), bounds.maxX - 1),
                             y: min(max(current.y + delta.dy, bounds.minY), bounds.maxY - 1))
        let type: CGEventType = Actions.leftButtonDown ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

/// Private MultitouchSupport bindings for the remote's touch surface.
enum Touch {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    static var onFrame: (([CGPoint]) -> Void)?
    /// Attached surfaces by registry ID, retained so the callback stays valid.
    private static var started: [UInt64: UnsafeMutableRawPointer] = [:]

    private static let framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private static func symbol<T>(_ name: String, _: T.Type) -> T { unsafeBitCast(dlsym(framework, name)!, to: T.self) }
    private static let createList = symbol("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>).self)
    private static let getService = symbol("MTDeviceGetService", (@convention(c) (UnsafeMutableRawPointer) -> io_service_t).self)
    private static let register = symbol("MTRegisterContactFrameCallback", (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self)
    private static let start = symbol("MTDeviceStart", (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self)
    private static let unregister = symbol("MTUnregisterContactFrameCallback", (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self)
    private static let stop = symbol("MTDeviceStop", (@convention(c) (UnsafeMutableRawPointer) -> Int32).self)

    // Finger struct is 96 bytes: state at 20 (4 = touching), normalized x/y at 32/36.
    private static let callback: Callback = { _, fingers, count, _, _ in
        var points: [CGPoint] = []
        if let fingers {
            for i in 0..<Int(count) where fingers.load(fromByteOffset: i * 96 + 20, as: Int32.self) == 4 {
                points.append(CGPoint(x: Double(fingers.load(fromByteOffset: i * 96 + 32, as: Float.self)),
                                      y: Double(fingers.load(fromByteOffset: i * 96 + 36, as: Float.self))))
            }
        }
        DispatchQueue.main.async { onFrame?(points) }
        return 0
    }

    /// Detach every known surface and attach again; after wake the old device objects may be dead,
    /// and re-registering a live one without detaching would double every touch frame.
    static func restart() {
        for ref in started.values {
            unregister(ref, callback)
            _ = stop(ref)
            Unmanaged<AnyObject>.fromOpaque(ref).release()
        }
        started.removeAll()
        startRemoteDevices()
    }

    static func startRemoteDevices() {
        guard framework != nil else { return }
        for device in createList().takeRetainedValue() as [AnyObject] {
            let ref = Unmanaged.passUnretained(device).toOpaque()
            let service = getService(ref)
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            let productID = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "ProductID" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
            guard productID == remoteProductID, started[entryID] == nil else { continue }
            started[entryID] = Unmanaged.passRetained(device).toOpaque()
            register(ref, callback)
            log("touch surface started: \(start(ref, 0))")
        }
    }
}
