// THE TRAFFIC LIGHTS (v49, request 70, Marko 13.11.2026: "On the left side, like any window in the Mac OS, I need to have a
// red button, a yellow button, and a green button"). The real standard window buttons (NSWindow.standardWindowButton), all
// three on the left of the stripe's top row, in the usual order and spacing (20 points apart). Red closes the stripe
// (hidden, the menu bar icon brings it back; the daemons keep running), yellow minimizes as before, green toggles
// the full size (the stripe as wide as the display, and back).
import AppKit

final class TrafficLights: NSView {
    static let width: CGFloat = 52
    var onClose: (() -> Void)?, onMini: (() -> Void)?, onZoom: (() -> Void)?
    private var over = false { didSet { needsDisplay = true } }
    // v50: drawn in the exact macOS colours, always coloured (the stripe is a non-key panel, where the system's own
    // buttons turn grey): fill, darker 0.5 pt rim, and the x / - / + glyphs while the mouse is over the group.
    private let fills = [(0xFF, 0x5F, 0x57), (0xFE, 0xBC, 0x2E), (0x28, 0xC8, 0x40)]
    private let rims = [(0xE0, 0x44, 0x3E), (0xDE, 0xA1, 0x23), (0x1A, 0xAB, 0x29)]
    private let glyphs = [(0x4D, 0x00, 0x00), (0x99, 0x57, 0x00), (0x00, 0x65, 0x00)]
    private func c(_ t: (Int, Int, Int)) -> NSColor { NSColor(srgbRed: CGFloat(t.0) / 255, green: CGFloat(t.1) / 255, blue: CGFloat(t.2) / 255, alpha: 1) }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: TrafficLights.width, height: 16))
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: TrafficLights.width, height: 16) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    override func draw(_ r: NSRect) {
        for i in 0..<3 {
            let rect = NSRect(x: CGFloat(i) * 20 + 0.5, y: (bounds.height - 12) / 2 + 0.5, width: 11, height: 11)
            let circle = NSBezierPath(ovalIn: rect)
            c(fills[i]).setFill(); circle.fill()
            c(rims[i]).setStroke(); circle.lineWidth = 0.5; circle.stroke()
            guard over else { continue }
            let g = NSBezierPath(), m = rect.insetBy(dx: 3, dy: 3)
            switch i {
            case 0: g.move(to: NSPoint(x: m.minX, y: m.minY)); g.line(to: NSPoint(x: m.maxX, y: m.maxY)); g.move(to: NSPoint(x: m.minX, y: m.maxY)); g.line(to: NSPoint(x: m.maxX, y: m.minY))
            case 1: g.move(to: NSPoint(x: m.minX - 0.5, y: rect.midY)); g.line(to: NSPoint(x: m.maxX + 0.5, y: rect.midY))
            default: g.move(to: NSPoint(x: m.minX - 0.5, y: rect.midY)); g.line(to: NSPoint(x: m.maxX + 0.5, y: rect.midY)); g.move(to: NSPoint(x: rect.midX, y: m.minY - 0.5)); g.line(to: NSPoint(x: rect.midX, y: m.maxY + 0.5))
            }
            g.lineWidth = 1.2; g.lineCapStyle = .round
            c(glyphs[i]).setStroke(); g.stroke()
        }
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { over = true }
    override func mouseExited(with e: NSEvent) { over = false }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x
        guard x >= 0, x < TrafficLights.width else { return }
        let i = Int((x + 4) / 20)
        guard i < 3, abs(x - (CGFloat(i) * 20 + 6)) <= 8 else { return }
        [onClose, onMini, onZoom][i]?()
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "close, minimize, zoom" }
}

extension Stripe {
    func wireLights() {
        lights.onClose = { [weak self] in self?.closeStripe() }
        lights.onMini = { [weak self] in self?.minimizeStripe() }
        lights.onZoom = { [weak self] in self?.zoomStripe() }
        lights.toolTip = "Red: close the stripe (the menu bar icon brings it back; nothing is stopped). Yellow: hide it to the menu bar icon. Green: full width, and back."
    }

    // Red: the stripe goes away, the keeper, the aggregation and the helpers keep running.
    func closeStripe() {
        MenuBarPrefs.stripeHidden = true
        panel.orderOut(nil)
        appendLog("\(logStamp()) stripe closed (red button); the menu bar icon brings it back, nothing stopped")
    }

    // Green: as wide as the display's usable area, then back to the width and the place it had.
    @objc func zoomStripe() {
        guard let root = panel.contentView, let column = root.subviews.first, let screen = panel.screen ?? NSScreen.main else { return }
        let natural = column.fittingSize
        guard natural.width > 0 else { return }
        if let p = zoomPrev {
            zoomPrev = nil
            resize(toWidth: natural.width * p.scale)
            panel.setFrameOrigin(NSPoint(x: p.x, y: panel.frame.origin.y))
            appendLog("\(logStamp()) stripe back to its size (green button)")
        } else {
            zoomPrev = (scale, panel.frame.minX)
            resize(toWidth: screen.visibleFrame.width)
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX, y: panel.frame.origin.y))
            appendLog("\(logStamp()) stripe full width (green button)")
        }
    }
}
