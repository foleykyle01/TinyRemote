import AppKit
import IOKit.hid

let remoteVendorID = 76    // Apple
let remoteProductID = 788  // Siri Remote (2nd/3rd gen)

func log(_ message: String) {
    fputs("\(Date()) \(message)\n", stderr)
    fflush(stderr)
}

/// Reads the Siri Remote (buttons via HID, touch surface via MultitouchSupport) and runs the mapped actions.
final class Remote: ObservableObject {
    static let shared = Remote()

    @Published var config = Config.load() { didSet { config.save() } }
    @Published var lastButton: RemoteButton?
    @Published var connected = false
    /// False when another app (e.g. GoatRemote) holds the remote exclusively, so macOS and that app also react.
    @Published var exclusive = true

    private let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var holds: [RemoteButton: Hold] = [:]
    private var hidOpened = false

    private struct Hold {
        var clickHeld = false
        var longPressFired = false
        var timers: [Timer] = []
    }

    func start() {
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
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, _ in
            Unmanaged<Remote>.fromOpaque(context!).takeUnretainedValue().connected = false
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        openHID()
        Touch.onFrame = { [weak self] point in self?.touch(point) }
        Touch.startRemoteDevices()
    }

    /// Seize the remote so macOS doesn't also act on Play/Volume; fall back to shared access.
    func openHID() {
        if hidOpened {
            // Closing also unschedules the manager, so put it back on the run loop.
            IOHIDManagerClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidOpened = true
        exclusive = IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
        if !exclusive { IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)) }
        log("hid opened, exclusive: \(exclusive)")
    }

    // MARK: Buttons

    private func button(_ button: RemoteButton, down: Bool) {
        let binding = config.buttons[button] ?? Mapping()
        log("\(button) \(down ? "down" : "up") accessibility=\(AXIsProcessTrusted())")
        if down {
            lastButton = button
            buttonDuringTouch = true
            var hold = Hold()
            if !binding.longPress.isEmpty {
                hold.timers.append(.scheduledTimer(withTimeInterval: config.longPressMs / 1000, repeats: false) { [weak self] _ in
                    self?.holds[button]?.longPressFired = true
                    Actions.tap(binding.longPress)
                })
            } else if binding.press.hasSuffix("-click") {
                Actions.perform(binding.press, down: true)  // held so the trackpad can drag
                hold.clickHeld = true
                dragTravel = 0
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

    // MARK: Touch surface

    private enum TouchMode { case none, cursor, scroll }
    private var touchMode = TouchMode.none
    private var lastPoint = CGPoint.zero
    private var lastAngle = 0.0
    private var scrollRemainder = 0.0
    private var touchStart = Date()
    private var touchTravel = 0.0
    private var buttonDuringTouch = false
    /// Finger travel since the click went down; pressing the clickpad nudges the finger, so ignore small moves.
    private var dragTravel = 0.0
    private let dragDeadZone = 0.06

    /// `point` is the first touching finger in normalized pad coordinates (origin bottom-left), or nil on lift.
    private func touch(_ point: CGPoint?) {
        guard config.trackpadEnabled else { touchMode = .none; return }
        guard let point else {
            // A quick, still touch in the middle is a tap; skip it if a button was physically pressed.
            if touchMode == .cursor, config.tapToClick, !buttonDuringTouch,
               Date().timeIntervalSince(touchStart) < 0.25, touchTravel < 0.04 {
                Actions.tap("left-click")
            }
            touchMode = .none
            return
        }
        let angle = atan2(point.y - 0.5, point.x - 0.5)
        defer { lastPoint = point; lastAngle = angle }
        if touchMode == .none {
            // Starting on the outer ring scrolls (circle it like an iPod); anywhere else moves the cursor.
            let onRing = hypot(point.x - 0.5, point.y - 0.5) > 0.38
            touchMode = config.ringScrollEnabled && onRing ? .scroll : .cursor
            scrollRemainder = 0
            touchStart = Date()
            touchTravel = 0
            buttonDuringTouch = false
            return
        }
        switch touchMode {
        case .cursor:
            let dx = point.x - lastPoint.x, dy = lastPoint.y - point.y
            touchTravel += hypot(dx, dy)
            if Actions.leftButtonDown {
                dragTravel += hypot(dx, dy)
                if dragTravel < dragDeadZone { return }
            }
            // ponytail: fixed accel curve; tune or make it a setting if it feels off.
            let gain = 900 * config.cursorSpeed * (1 + min(hypot(dx, dy) * 40, 3))
            moveCursor(by: CGVector(dx: dx * gain, dy: dy * gain))
        case .scroll:
            var delta = angle - lastAngle
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            scrollRemainder += -delta * 400 * config.scrollSpeed  // clockwise scrolls down
            let pixels = scrollRemainder.rounded(.towardZero)
            scrollRemainder -= pixels
            if pixels != 0 {
                CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-pixels), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            }
        case .none: break
        }
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
    static var onFrame: ((CGPoint?) -> Void)?
    private static var started = Set<UInt64>()

    private static let framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private static func symbol<T>(_ name: String, _: T.Type) -> T { unsafeBitCast(dlsym(framework, name)!, to: T.self) }
    private static let createList = symbol("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>).self)
    private static let getService = symbol("MTDeviceGetService", (@convention(c) (UnsafeMutableRawPointer) -> io_service_t).self)
    private static let register = symbol("MTRegisterContactFrameCallback", (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self)
    private static let start = symbol("MTDeviceStart", (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self)

    // Finger struct is 96 bytes: state at 20 (4 = touching), normalized x/y at 32/36.
    private static let callback: Callback = { _, fingers, count, _, _ in
        var point: CGPoint?
        if let fingers {
            for i in 0..<Int(count) where fingers.load(fromByteOffset: i * 96 + 20, as: Int32.self) == 4 {
                point = CGPoint(x: Double(fingers.load(fromByteOffset: i * 96 + 32, as: Float.self)),
                                y: Double(fingers.load(fromByteOffset: i * 96 + 36, as: Float.self)))
                break
            }
        }
        DispatchQueue.main.async { onFrame?(point) }
        return 0
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
            guard productID == remoteProductID, !started.contains(entryID) else { continue }
            started.insert(entryID)
            _ = Unmanaged.passRetained(device)  // keep the device alive for the callback
            register(ref, callback)
            log("touch surface started: \(start(ref, 0))")
        }
    }
}
