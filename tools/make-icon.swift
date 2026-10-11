// Draws the TinyRemote icon (an original remote glyph, not an SF Symbol) and writes:
//   Resources/AppIcon.icon   Icon Composer source: blue (light) / graphite (dark) fill + remote layer
//   Resources/Assets.car     compiled icon with light, dark and tinted variants (macOS 26 follows the system)
//   Resources/AppIcon.icns   compiled fallback for macOS 15
//   docs/logo.png, docs/logo-dark.png   README logos
// Run from the repo root: swift tools/make-icon.swift  (needs Xcode for actool)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws onto a fresh square bitmap. `rect` maps the 1024-point design grid into it.
func bitmap(_ size: CGFloat, _ draw: (_ rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> NSRect, _ scale: CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    draw({ NSRect(x: $0 * s, y: $1 * s, width: $2 * s, height: $3 * s) }, s)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// The remote, in tile coordinates (the tile spans 100...924 on the 1024 grid).
func drawRemote(_ rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> NSRect, _ s: CGFloat, dark: Bool) {
    NSGradient(starting: color(0xFFFFFF), ending: color(0xD5D8DE))!
        .draw(in: NSBezierPath(roundedRect: rect(362, 170, 300, 684), xRadius: 120 * s, yRadius: 120 * s), angle: -90)
    color(0x111317).setFill()
    NSBezierPath(ovalIn: rect(392, 534, 240, 240)).fill()
    (dark ? color(0x2563EB) : color(0x23262D)).setFill()  // dark mode keeps the brand blue in the clickpad
    NSBezierPath(ovalIn: rect(457, 599, 110, 110)).fill()
    color(0x111317).setFill()
    for (x, y) in [(400.0, 400.0), (536.0, 400.0), (400.0, 270.0), (536.0, 270.0)] { NSBezierPath(ovalIn: rect(x, y, 88, 88)).fill() }
}

/// Icon Composer layer: the remote alone, scaled so the tile area fills the canvas (the system adds tile, mask, shadow).
func layer(dark: Bool) -> NSBitmapImageRep {
    bitmap(1024) { rect, s in
        let k = 1024.0 / 824.0
        drawRemote({ rect(($0 - 100) * k, ($1 - 100) * k, $2 * k, $3 * k) }, s * k, dark: dark)
    }
}

/// README logo: our own tile plus the remote.
func logo(dark: Bool) -> NSBitmapImageRep {
    bitmap(1024) { rect, s in
        let tile = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(starting: color(dark ? 0x3A3D44 : 0x3B82F6), ending: color(dark ? 0x101114 : 0x1E3A8A))!.draw(in: tile, angle: -90)
        NSGradient(starting: color(0xFFFFFF, dark ? 0.08 : 0.18), ending: color(0xFFFFFF, 0))!.draw(in: tile, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x000000, 0.35)
        shadow.shadowBlurRadius = 40 * s
        shadow.shadowOffset = NSSize(width: 0, height: -18 * s)
        shadow.set()
        color(0xF4F5F7).setFill()
        NSBezierPath(roundedRect: rect(362, 170, 300, 684), xRadius: 120 * s, yRadius: 120 * s).fill()
        NSGraphicsContext.restoreGraphicsState()
        drawRemote(rect, s, dark: dark)
    }
}

func png(_ rep: NSBitmapImageRep, _ path: String) { try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }

let root = FileManager.default.currentDirectoryPath
let icon = "\(root)/Resources/AppIcon.icon"
try? FileManager.default.removeItem(atPath: icon)
try! FileManager.default.createDirectory(atPath: "\(icon)/Assets", withIntermediateDirectories: true)
png(layer(dark: false), "\(icon)/Assets/remote.png")
png(layer(dark: true), "\(icon)/Assets/remote-dark.png")
try! """
{
  "fill-specializations" : [
    { "value" : { "automatic-gradient" : "extended-srgb:0.23137,0.50980,0.96471,1.00000" } },
    { "appearance" : "dark", "value" : { "automatic-gradient" : "extended-srgb:0.17647,0.18431,0.20784,1.00000" } }
  ],
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "image-name-specializations" : [
            { "value" : "remote.png" },
            { "appearance" : "dark", "value" : "remote-dark.png" }
          ],
          "name" : "remote"
        }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
""".write(toFile: "\(icon)/icon.json", atomically: true, encoding: .utf8)

let out = NSTemporaryDirectory() + "tinyremote-icon"
try? FileManager.default.removeItem(atPath: out)
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let actool = Process()
actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
actool.arguments = ["actool", icon, "--compile", out, "--platform", "macosx", "--minimum-deployment-target", "15.0",
                    "--app-icon", "AppIcon", "--output-partial-info-plist", "\(out)/partial.plist"]
actool.standardOutput = FileHandle.nullDevice
try! actool.run()
actool.waitUntilExit()
for file in ["Assets.car", "AppIcon.icns"] {
    try? FileManager.default.removeItem(atPath: "\(root)/Resources/\(file)")
    try! FileManager.default.copyItem(atPath: "\(out)/\(file)", toPath: "\(root)/Resources/\(file)")
}
png(logo(dark: false), "\(root)/docs/logo.png")
png(logo(dark: true), "\(root)/docs/logo-dark.png")
print("wrote AppIcon.icon, Assets.car, AppIcon.icns and docs logos")
