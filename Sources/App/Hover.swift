// HOVER AND PRESS (v44, request 62, Marko 1.11.2026: "I need to have a hover over. When I'm under any button, it's
// changing color ... Something so I know I'm over that, and when I click, it's going to react").
// Every button of the stripe and of its windows gets a tracking area: the mouse over it lays a light rounded plate under
// the word and the cursor becomes the pointing hand; a press flashes the plate green for a quarter second. Buttons are
// found by walking the views after every layout (Hover.walk), so a button made later (a new line, a download) has it too.
import AppKit

final class Hover: NSObject {
    static var owners: [ObjectIdentifier: Hover] = [:]
    static let over = NSColor(calibratedWhite: 1, alpha: 0.26).cgColor
    static let rim = NSColor(calibratedWhite: 1, alpha: 0.55).cgColor
    static let grow: CGFloat = 1.25     // v45 (request 63): the word under the mouse grows by a quarter
    static let press = NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.45, alpha: 0.45).cgColor
    weak var button: NSButton?
    var inside = false

    static func add(_ b: NSButton) {
        let id = ObjectIdentifier(b)
        guard owners[id] == nil else { return }
        let h = Hover(); h.button = b
        owners[id] = h
        b.wantsLayer = true
        b.layer?.cornerRadius = 4
        // v45 (request 63: "enlarge its buttons so even its area of clicking is enlarging"): every button is at least
        // 8 points wider and 22 high than its word, so the click lands near it too; a fixed slot (a lower priority
        // here) keeps its own width.
        let fit = b.fittingSize
        b.translatesAutoresizingMaskIntoConstraints = false
        let w = b.widthAnchor.constraint(greaterThanOrEqualToConstant: fit.width + 8); w.priority = .defaultHigh; w.isActive = true
        let hgt = b.heightAnchor.constraint(greaterThanOrEqualToConstant: 22); hgt.priority = .defaultHigh; hgt.isActive = true
        b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: h, userInfo: nil))
    }

    static func walk(_ v: NSView) {
        if v is TrafficLights { return }
        if let b = v as? NSButton { add(b) }
        for s in v.subviews { walk(s) }
    }

    @objc func mouseEntered(with e: NSEvent) {
        guard let b = button, b.isEnabled, b.alphaValue > 0 else { return }
        inside = true
        b.layer?.backgroundColor = Hover.over
        b.layer?.borderColor = Hover.rim
        b.layer?.borderWidth = 1
        Hover.scale(b, Hover.grow)
        NSCursor.pointingHand.set()
    }
    @objc func mouseExited(with e: NSEvent) {
        inside = false
        button?.layer?.backgroundColor = nil
        button?.layer?.borderWidth = 0
        if let b = button { Hover.scale(b, 1) }
        NSCursor.arrow.set()
    }

    // Grows the button about its own centre (the layer's anchor is its corner), above its neighbours.
    static func scale(_ b: NSButton, _ k: CGFloat) {
        guard let l = b.layer else { return }
        let w = b.bounds.width, h = b.bounds.height
        var t = CATransform3DMakeTranslation(w / 2, h / 2, 0)
        t = CATransform3DScale(t, k, k, 1)
        t = CATransform3DTranslate(t, -w / 2, -h / 2, 0)
        CATransaction.begin(); CATransaction.setAnimationDuration(0.08)
        l.transform = k == 1 ? CATransform3DIdentity : t
        l.zPosition = k == 1 ? 0 : 10
        CATransaction.commit()
        b.superview?.layer?.masksToBounds = false
    }

    // A press anywhere in our windows: the button under it flashes.
    static func watchPresses() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard let w = e.window, let content = w.contentView else { return e }
            var v = content.hitTest(content.convert(e.locationInWindow, from: nil))
            while let x = v, !(x is NSButton) { v = x.superview }
            if let b = v as? NSButton, b.isEnabled, b.alphaValue > 0, let h = owners[ObjectIdentifier(b)] {
                b.layer?.backgroundColor = press
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak b] in b?.layer?.backgroundColor = h.inside ? over : nil }
            }
            return e
        }
    }
}

// A thin horizontal line between the parts of the stripe (request 62: "Under the first line, put the horizontal line.
// Then all my connections are coming, and then another horizontal line for status").
final class Rule: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.40, alpha: 1).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
