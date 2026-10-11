// Draws the TinyRemote icon (an original remote glyph, not an SF Symbol) and writes
// Resources/AppIcon.icns plus docs/logo.png. Run from the repo root: swift tools/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024  // design on a 1024 grid
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    // Background: macOS icon body (824pt, ~185pt corners) with a deep blue gradient.
    let body = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x3B82F6), ending: color(0x1E3A8A))!.draw(in: body, angle: -90)
    NSGradient(starting: color(0xFFFFFF, 0.18), ending: color(0xFFFFFF, 0))!.draw(in: body, angle: -90)  // top sheen

    // Remote body with a soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 40 * s
    shadow.shadowOffset = NSSize(width: 0, height: -18 * s)
    shadow.set()
    let remote = NSBezierPath(roundedRect: rect(362, 170, 300, 684), xRadius: 120 * s, yRadius: 120 * s)
    color(0xF4F5F7).setFill()
    remote.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFFFFF), ending: color(0xD5D8DE))!.draw(in: NSBezierPath(roundedRect: rect(362, 170, 300, 684), xRadius: 120 * s, yRadius: 120 * s), angle: -90)

    // Clickpad: dark ring with an inner pad.
    color(0x111317).setFill()
    NSBezierPath(ovalIn: rect(392, 534, 240, 240)).fill()
    color(0x23262D).setFill()
    NSBezierPath(ovalIn: rect(457, 599, 110, 110)).fill()

    // Two rows of buttons.
    color(0x111317).setFill()
    for (x, y) in [(400.0, 400.0), (536.0, 400.0), (400.0, 270.0), (536.0, 270.0)] {
        NSBezierPath(ovalIn: rect(x, y, 88, 88)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = FileManager.default.currentDirectoryPath
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! render(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(root)/docs/logo.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "\(root)/Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and docs/logo.png" : "iconutil failed")
