// THE TRAFFIC LIGHTS (v49, request 70, Marko 13.11.2026: "On the left side, like any window in the Mac OS, I need to have a
// red button, a yellow button, and a green button"). The real standard window buttons (NSWindow.standardWindowButton), all
// three on the left of the stripe's top row, in the usual order and spacing (20 points apart). Red closes the stripe
// (hidden, the menu bar icon brings it back; the daemons keep running), yellow minimizes as before, green toggles
// the full size (the stripe as wide as the display, and back).
import AppKit

final class TrafficLights: NSView {
    static let width: CGFloat = 54
    var onClose: (() -> Void)?, onMini: (() -> Void)?, onZoom: (() -> Void)?
    private let buttons: [NSButton]

    init() {
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { NSWindow.standardWindowButton($0, for: mask) }
        super.init(frame: NSRect(x: 0, y: 0, width: TrafficLights.width, height: 16))
        translatesAutoresizingMaskIntoConstraints = false
        let sel = [#selector(closePressed), #selector(miniPressed), #selector(zoomPressed)]
        for (i, b) in buttons.enumerated() {
            b.frame.origin = NSPoint(x: CGFloat(i) * 20, y: (16 - b.frame.height) / 2)
            b.target = self
            b.action = sel[i]
            b.isEnabled = true
            addSubview(b)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: TrafficLights.width, height: 16) }
    override var mouseDownCanMoveWindow: Bool { false }
    @objc func closePressed() { onClose?() }
    @objc func miniPressed() { onMini?() }
    @objc func zoomPressed() { onZoom?() }
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
