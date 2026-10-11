// Draws the README artwork in light and dark variants: docs/banner*.png, docs/remote-map*.png and
// docs/social-preview.jpg. Run from the repo root after tools/make-icon.swift: swift tools/make-readme-art.swift
import AppKit

let root = FileManager.default.currentDirectoryPath

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Renders at 2x into a PNG. Drawing code uses top-left coordinates in points.
func render(_ width: CGFloat, _ height: CGFloat, to path: String, scale: CGFloat = 2, _ draw: (_ flip: (NSRect) -> NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw { NSRect(x: $0.minX, y: height - $0.maxY, width: $0.width, height: $0.height) }
    NSGraphicsContext.restoreGraphicsState()
    let data = path.hasSuffix(".jpg") ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])! : rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(root)/\(path)"))
}

enum Align { case left, center, right }

/// Draws one block of text, shrinking the font until the widest line fits `width`.
func text(_ string: String, _ point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color textColor: NSColor,
          align: Align = .left, width: CGFloat = 1000, height: CGFloat, flip: (NSRect) -> NSRect) {
    let style = NSMutableParagraphStyle()
    style.alignment = align == .left ? .left : align == .center ? .center : .right
    style.lineSpacing = 2
    var fontSize = size
    func attributed() -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: textColor, .paragraphStyle: style,
        ])
    }
    while fontSize > 8, string.split(separator: "\n").contains(where: {
        NSAttributedString(string: String($0), attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight)]).size().width > width
    }) { fontSize -= 1 }
    let x = align == .left ? point.x : align == .center ? point.x - width / 2 : point.x - width
    attributed().draw(with: flip(NSRect(x: x, y: point.y, width: width, height: height)), options: [.usesLineFragmentOrigin])
}

// MARK: Banner and social preview

func banner(width: CGFloat, height: CGFloat, dark: Bool, path: String) {
    let logo = NSImage(contentsOfFile: "\(root)/docs/\(dark ? "logo-dark" : "logo").png")!
    render(width, height, to: path) { flip in
        let card = NSBezierPath(roundedRect: flip(NSRect(x: 0, y: 0, width: width, height: height)), xRadius: 36, yRadius: 36)
        NSGradient(starting: color(dark ? 0x23262D : 0x3B82F6), ending: color(dark ? 0x0B0C0F : 0x1E3A8A))!.draw(in: card, angle: -35)
        NSGradient(starting: color(0xFFFFFF, dark ? 0.06 : 0.14), ending: color(0xFFFFFF, 0))!.draw(in: card, angle: -90)
        let iconSize = height * 0.78
        logo.draw(in: flip(NSRect(x: height * 0.12, y: (height - iconSize) / 2, width: iconSize, height: iconSize)))
        let textX = height * 0.12 + iconSize + height * 0.04
        let textWidth = width - textX - height * 0.1
        text("TinyRemote", NSPoint(x: textX, y: height * 0.26), size: height * 0.2, weight: .bold, color: .white, width: textWidth, height: height * 0.3, flip: flip)
        text("Your Apple TV Remote, made for your Mac.", NSPoint(x: textX, y: height * 0.51), size: height * 0.075, weight: .medium,
             color: color(0xFFFFFF, 0.92), width: textWidth, height: height * 0.12, flip: flip)
        text("Remap every button · Trackpad · App-aware · Push-to-talk dictation", NSPoint(x: textX, y: height * 0.64),
             size: height * 0.048, color: color(0xFFFFFF, 0.7), width: textWidth, height: height * 0.1, flip: flip)
    }
}

banner(width: 1400, height: 440, dark: false, path: "docs/banner.png")
banner(width: 1400, height: 440, dark: true, path: "docs/banner-dark.png")
/// Link-preview card (1280x640): icon above centered text, since a side-by-side layout is too cramped at 2:1.
func socialPreview(path: String) {
    let width: CGFloat = 1280, height: CGFloat = 640
    let logo = NSImage(contentsOfFile: "\(root)/docs/logo.png")!
    render(width, height, to: path, scale: 1) { flip in  // GitHub wants 1280x640 under 1 MB
        let card = NSBezierPath(rect: flip(NSRect(x: 0, y: 0, width: width, height: height)))
        NSGradient(starting: color(0x3B82F6), ending: color(0x1E3A8A))!.draw(in: card, angle: -35)
        NSGradient(starting: color(0xFFFFFF, 0.14), ending: color(0xFFFFFF, 0))!.draw(in: card, angle: -90)
        logo.draw(in: flip(NSRect(x: (width - 300) / 2, y: 30, width: 300, height: 300)))
        let center = width / 2, textWidth = width - 160
        text("TinyRemote", NSPoint(x: center, y: 330), size: 104, weight: .bold, color: .white, align: .center, width: textWidth, height: 130, flip: flip)
        text("Your Apple TV Remote, made for your Mac.", NSPoint(x: center, y: 462), size: 44, weight: .medium,
             color: color(0xFFFFFF, 0.92), align: .center, width: textWidth, height: 60, flip: flip)
        text("Remap every button · Trackpad · App-aware · Push-to-talk dictation", NSPoint(x: center, y: 530),
             size: 30, color: color(0xFFFFFF, 0.72), align: .center, width: textWidth, height: 46, flip: flip)
    }
}
socialPreview(path: "docs/social-preview.jpg")

// MARK: Annotated remote

func remoteMap(dark: Bool, path: String) {
    let W: CGFloat = 1500, H: CGFloat = 1000
    let ink = color(dark ? 0xE6EDF3 : 0x1F2328), muted = color(dark ? 0x9DA7B3 : 0x59636E), line = color(dark ? 0x3D444D : 0xC5CBD3)
    let key = color(0x111317)
    render(W, H, to: path) { flip in
        color(dark ? 0x0D1117 : 0xF6F8FA).setFill()
        NSBezierPath(roundedRect: flip(NSRect(x: 0, y: 0, width: W, height: H)), xRadius: 28, yRadius: 28).fill()

        // Remote body, side mic, buttons (top-left coordinates).
        let shadow = NSShadow()
        shadow.shadowColor = color(0x000000, dark ? 0.5 : 0.18)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        color(0xE9EBEF).setFill()
        NSBezierPath(roundedRect: flip(NSRect(x: 560, y: 60, width: 260, height: 880)), xRadius: 110, yRadius: 110).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: color(0xFAFBFC), ending: color(0xCDD1D8))!
            .draw(in: NSBezierPath(roundedRect: flip(NSRect(x: 560, y: 60, width: 260, height: 880)), xRadius: 110, yRadius: 110), angle: -90)
        color(0x2A2D33).setFill()
        NSBezierPath(roundedRect: flip(NSRect(x: 818, y: 260, width: 8, height: 100)), xRadius: 4, yRadius: 4).fill()

        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ fill: NSColor) {
            fill.setFill()
            NSBezierPath(ovalIn: flip(NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))).fill()
        }
        func glyph(_ symbol: String, _ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat) {
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .semibold).applying(.init(paletteColors: [.white]))) else { return }
            let s = image.size
            image.draw(in: flip(NSRect(x: cx - s.width / 2, y: cy - s.height / 2, width: s.width, height: s.height)))
        }
        circle(765, 130, 26, key); glyph("power", 765, 130, 20)
        circle(690, 330, 115, key)
        circle(690, 330, 50, color(0x24272E))
        for (x, y) in [(690.0, 240.0), (690.0, 420.0), (600.0, 330.0), (780.0, 330.0)] { circle(x, y, 6, color(0xE6E8EC)) }
        circle(630, 540, 48, key); glyph("chevron.left", 630, 540, 26)
        circle(750, 540, 48, key); glyph("tv", 750, 540, 24)
        circle(630, 660, 48, key); glyph("playpause.fill", 630, 660, 24)
        circle(630, 780, 48, key); glyph("speaker.slash.fill", 630, 780, 22)
        key.setFill()
        NSBezierPath(roundedRect: flip(NSRect(x: 702, y: 612, width: 96, height: 216)), xRadius: 48, yRadius: 48).fill()
        glyph("plus", 750, 670, 26); glyph("minus", 750, 770, 26)

        // Callouts: (anchor on the remote, label y, title, detail, left side?)
        let callouts: [(NSPoint, CGFloat, String, String, Bool)] = [
            (NSPoint(x: 575, y: 330), 300, "Clickpad", "Slide to move the pointer · tap or press to click\nhold still to right-click · circle the edge to scroll\npress the edges for arrow keys", true),
            (NSPoint(x: 582, y: 540), 520, "Back", "Delete · back a page in browsers", true),
            (NSPoint(x: 582, y: 660), 640, "Play / Pause", "Play or pause media", true),
            (NSPoint(x: 582, y: 780), 760, "Mute", "Yours to assign", true),
            (NSPoint(x: 791, y: 130), 110, "Power", "Escape", false),
            (NSPoint(x: 826, y: 310), 290, "Mic (side)", "Hold to dictate with your dictation app", false),
            (NSPoint(x: 798, y: 540), 520, "TV", "Return · hold for right-click", false),
            (NSPoint(x: 798, y: 670), 650, "Volume +", "Previous desktop", false),
            (NSPoint(x: 798, y: 770), 750, "Volume −", "Next desktop", false),
        ]
        for (anchor, labelY, title, detail, left) in callouts {
            let endX: CGFloat = left ? 520 : 870
            let path = NSBezierPath()
            path.lineWidth = 2
            path.move(to: flip(NSRect(x: anchor.x, y: anchor.y, width: 0, height: 0)).origin)
            path.line(to: flip(NSRect(x: endX, y: labelY + 20, width: 0, height: 0)).origin)
            line.setStroke()
            path.stroke()
            circle(anchor.x, anchor.y, 5, color(0x3B82F6))
            let textX: CGFloat = left ? 505 : 885
            text(title, NSPoint(x: textX, y: labelY), size: 26, weight: .semibold, color: ink, align: left ? .right : .left, width: 480, height: 40, flip: flip)
            text(detail, NSPoint(x: textX, y: labelY + 38), size: 20, color: muted, align: left ? .right : .left, width: 480, height: 110, flip: flip)
        }
        text("Defaults · change any of them in Settings", NSPoint(x: 48, y: 950), size: 18, color: muted, width: W, height: 30, flip: flip)
    }
}

remoteMap(dark: false, path: "docs/remote-map.png")
remoteMap(dark: true, path: "docs/remote-map-dark.png")
print("wrote docs/banner*.png, docs/remote-map*.png, docs/social-preview.jpg")
