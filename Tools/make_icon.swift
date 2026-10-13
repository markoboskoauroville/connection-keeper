// Draws the app icon in code: the stripe itself, with two Wi-Fi fans on it (one carrying, green;
// one waiting, grey) and the arrow between them that is the keeper's whole job. The version sits
// under the symbol (version-visible.md).
//   swift Tools/make_icon.swift <out.iconset> <version>
import AppKit

let out = CommandLine.arguments[1]
let version = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func fan(_ c: NSPoint, _ r: CGFloat, _ color: NSColor) {
    color.setStroke()
    color.setFill()
    for i in 1...3 {
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: r * CGFloat(i) / 3, startAngle: 45, endAngle: 135)
        p.lineWidth = r * 0.13
        p.lineCapStyle = .round
        p.stroke()
    }
    NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.1, y: c.y - r * 0.1, width: r * 0.2, height: r * 0.2)).fill()
}

func draw(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let u = s / 100
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 4 * u, y: 4 * u, width: 92 * u, height: 92 * u), xRadius: 20 * u, yRadius: 20 * u).fill()

        // the stripe
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 12 * u, y: 38 * u, width: 76 * u, height: 32 * u), xRadius: 7 * u, yRadius: 7 * u).fill()

        fan(NSPoint(x: 30 * u, y: 44 * u), 20 * u, NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.45, alpha: 1))
        fan(NSPoint(x: 70 * u, y: 44 * u), 20 * u, NSColor(calibratedWhite: 0.42, alpha: 1))

        // the switch between them
        let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 1)
        amber.setStroke()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 43 * u, y: 55 * u))
        arrow.line(to: NSPoint(x: 57 * u, y: 55 * u))
        arrow.move(to: NSPoint(x: 52 * u, y: 60 * u))
        arrow.line(to: NSPoint(x: 57 * u, y: 55 * u))
        arrow.line(to: NSPoint(x: 52 * u, y: 50 * u))
        arrow.lineWidth = 3 * u
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()

        if s >= 32 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15 * u, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1),
            ]
            let t = NSAttributedString(string: "v\(version)", attributes: attrs)
            let w = t.size()
            t.draw(at: NSPoint(x: (s - w.width) / 2, y: 13 * u))
        }
        return true
    }
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
