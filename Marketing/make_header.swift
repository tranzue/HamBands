// Renders the App Store product page header for HamBand.
// Usage: swift Marketing/make_header.swift [output.png]
// Expects screenshots in Marketing/screens/ (bands.png, privileges.png, greyline.png).

import AppKit

let W: CGFloat = 3840, H: CGFloat = 1646
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : here.appendingPathComponent("header-3840x1646.png").path

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
// The app's mode colors (iOS system colors, dark appearance).
let blue = rgb(10, 132, 255), indigo = rgb(94, 92, 230), purple = rgb(191, 90, 242)
let orange = rgb(255, 159, 10), teal = rgb(100, 210, 255), green = rgb(48, 209, 88)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError() }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// MARK: Background: deep night-sky gradient
NSGradient(colors: [rgb(6, 10, 24), rgb(10, 18, 42), rgb(4, 6, 14)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// Soft glow behind the phones.
NSGradient(colors: [rgb(40, 90, 200, 0.35), rgb(40, 90, 200, 0)], atLocations: [0, 1], colorSpace: .sRGB)!
    .draw(fromCenter: NSPoint(x: 2755, y: 820), radius: 0, toCenter: NSPoint(x: 2755, y: 820), radius: 1100, options: [])

// MARK: Background motif: a radio dial of band-plan bars
let dialY: CGFloat = 250
// Tick scale along the bottom.
for i in 0...192 {
    let x = CGFloat(i) * 20
    let major = i % 8 == 0
    rgb(255, 255, 255, major ? 0.16 : 0.07).setFill()
    NSRect(x: x, y: dialY - (major ? 46 : 22), width: 3, height: major ? 46 : 22).fill()
}
// Faint band-chart bars drifting across the full width, echoing the app's chart.
let rows: [(y: CGFloat, segs: [(CGFloat, CGFloat, NSColor)])] = [
    (1460, [(0, 260, purple), (300, 700, orange), (760, 980, blue), (1040, 1500, purple), (1540, 2100, orange),
            (2160, 2420, teal), (2480, 3000, green), (3060, 3400, purple), (3440, 3840, orange)]),
    (1380, [(120, 420, teal), (470, 820, purple), (880, 1300, orange), (1360, 1560, indigo), (1620, 2200, green),
            (2260, 2600, blue), (2660, 3200, orange), (3260, 3840, teal)]),
    (330, [(0, 380, orange), (430, 760, purple), (820, 1240, green), (1300, 1500, blue), (1560, 2000, teal),
           (2060, 2500, purple), (2560, 3100, orange), (3160, 3840, green)]),
]
for row in rows {
    for (x0, x1, c) in row.segs {
        c.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: NSRect(x: x0, y: row.y, width: x1 - x0 - 14, height: 26), xRadius: 6, yRadius: 6).fill()
    }
}

// MARK: Phones
func drawPhone(_ name: String, center: CGPoint, height: CGFloat, angle: CGFloat, dim: CGFloat = 0) {
    guard let shot = NSImage(contentsOf: here.appendingPathComponent("screens/\(name).png")) else {
        fatalError("missing screens/\(name).png")
    }
    let width = height / 2622 * 1206
    let bezel: CGFloat = height * 0.022
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let body = NSRect(x: -width / 2 - bezel, y: -height / 2 - bezel, width: width + 2 * bezel, height: height + 2 * bezel)
    let bodyRadius = width * 0.17

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
    shadow.shadowBlurRadius = 90
    shadow.shadowOffset = NSSize(width: 0, height: -40)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    rgb(28, 30, 36).setFill()
    NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Titanium edge.
    rgb(120, 124, 134, 0.9).setStroke()
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: bodyRadius - 3, yRadius: bodyRadius - 3)
    edge.lineWidth = 6
    edge.stroke()

    let screen = NSRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let screenRadius = bodyRadius - bezel
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: screenRadius, yRadius: screenRadius).addClip()
    shot.draw(in: screen)
    if dim > 0 {
        NSColor.black.withAlphaComponent(dim).setFill()
        screen.fill(using: .sourceAtop)
    }
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

drawPhone("greyline", center: CGPoint(x: 2300, y: 805), height: 1080, angle: 6, dim: 0.25)
drawPhone("bands", center: CGPoint(x: 3210, y: 805), height: 1080, angle: -6, dim: 0.25)
drawPhone("privileges", center: CGPoint(x: 2755, y: 818), height: 1260, angle: 0)

// MARK: Text
func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          kern: CGFloat = 0, design: NSFontDescriptor.SystemDesign = .default) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = font.fontDescriptor.withDesign(design) { font = NSFont(descriptor: d, size: size) ?? font }
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: point)
}

let left: CGFloat = 560
// Small call-sign style eyebrow.
draw("FOR AMATEUR RADIO OPERATORS", at: CGPoint(x: left + 6, y: 1110), size: 50, weight: .semibold,
     color: teal, kern: 9)
draw("HamBand", at: CGPoint(x: left - 6, y: 820), size: 250, weight: .heavy, color: .white, kern: -4)
draw("Know your bands.", at: CGPoint(x: left, y: 690), size: 104, weight: .semibold, color: rgb(255, 255, 255, 0.92))

// Feature chips, colored like the band chart.
let chips: [(String, NSColor)] = [("Live HF conditions", green), ("FCC band privileges", orange), ("Greyline map", blue)]
var y: CGFloat = 560
for (label, color) in chips {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: left + 4, y: y + 12, width: 30, height: 30), xRadius: 8, yRadius: 8).fill()
    draw(label, at: CGPoint(x: left + 62, y: y), size: 58, weight: .medium, color: rgb(255, 255, 255, 0.78))
    y -= 86
}

NSGraphicsContext.restoreGraphicsState()
// Flatten to opaque RGB: App Store Connect rejects artwork with an alpha channel.
guard let drawn = rep.cgImage,
      let flat = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }
flat.draw(drawn, in: CGRect(x: 0, y: 0, width: W, height: H))
guard let opaque = flat.makeImage(),
      let png = NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:]) else { fatalError() }
try! png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out) (\(Int(W))×\(Int(H)))")
