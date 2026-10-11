import AppKit
import IOKit.hid

// MARK: - Logging

let logPath = NSHomeDirectory() + "/Library/Logs/TinyRemote.log"
freopen(logPath, "a", stderr)

func log(_ message: String) {
    fputs("\(Date()) \(message)\n", stderr)
    fflush(stderr)
}

let remoteVendorID = 76    // Apple
let remoteProductID = 788  // Siri Remote (2nd/3rd gen)

// MARK: - Buttons (HID)

let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(hid, [kIOHIDVendorIDKey: remoteVendorID, kIOHIDProductIDKey: remoteProductID] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(hid, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
    let length = IOHIDValueGetLength(value)
    if length > 4 {
        log(String(format: "hid page=0x%X usage=0x%X bytes=%d", page, usage, length))
    } else {
        log(String(format: "hid page=0x%X usage=0x%X value=%d", page, usage, IOHIDValueGetIntegerValue(value)))
    }
}, nil)
IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
log("hid open: \(IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)))")

// MARK: - Touch surface (private MultitouchSupport)

typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
func mtSymbol<T>(_ name: String, _: T.Type) -> T { unsafeBitCast(dlsym(mt, name)!, to: T.self) }
let MTDeviceCreateList = mtSymbol("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>).self)
let MTDeviceGetService = mtSymbol("MTDeviceGetService", (@convention(c) (UnsafeMutableRawPointer) -> io_service_t).self)
let MTRegisterContactFrameCallback = mtSymbol("MTRegisterContactFrameCallback", (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void).self)
let MTDeviceStart = mtSymbol("MTDeviceStart", (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self)

// Finger struct layout (96 bytes): identifier @16, state @20, normalized x/y @32/36.
let fingerStride = 96

func productID(of service: io_service_t) -> Int? {
    IORegistryEntrySearchCFProperty(service, kIOServicePlane, "ProductID" as CFString, kCFAllocatorDefault,
        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
}

var lastTouchLog = Date.distantPast
let touchCallback: MTContactCallback = { _, fingers, count, _, _ in
    guard let fingers, Date().timeIntervalSince(lastTouchLog) > 0.1 || count == 0 else { return 0 }
    lastTouchLog = Date()
    let desc = (0..<Int(count)).map { i -> String in
        let f = fingers + i * fingerStride
        return String(format: "id=%d state=%d x=%.3f y=%.3f", f.load(fromByteOffset: 16, as: Int32.self),
            f.load(fromByteOffset: 20, as: Int32.self), f.load(fromByteOffset: 32, as: Float.self), f.load(fromByteOffset: 36, as: Float.self))
    }
    log("touch n=\(count) \(desc.joined(separator: " | "))")
    return 0
}

let devices = MTDeviceCreateList().takeRetainedValue() as [AnyObject]
for device in devices {
    let ref = Unmanaged.passUnretained(device).toOpaque()
    let pid = productID(of: MTDeviceGetService(ref))
    log("mt device productID=\(pid.map(String.init) ?? "?")")
    guard pid == remoteProductID else { continue }
    MTRegisterContactFrameCallback(ref, touchCallback)
    log("mt start: \(MTDeviceStart(ref, 0))")
}

log("TinyRemote discovery running")
NSApplication.shared.run()
