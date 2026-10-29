// THE MENU BAR (v36, request 53, Marko 29.10.2026: "make my app, which is aggregating connections, appear as an icon on
// the menu bar ... It also needs to show current upload and download speeds. When I click on the icon, the user
// interface opens, and it has one LED: green if the internet is connected, and red if it's disconnected").
// The icon is the network symbol with the live internet speed beside it: download green, upload red, as on the stripe
// (no arrows, request of 18.10.2026), in Mbit/s, every number in a fixed slot so the menu bar never breathes
// (request 47). A click shows the stripe or hides it; the stripe remembers which. The minimize circle now hides the
// stripe to the icon. The one LED sits at the right end of the stripe's first row, away from the minimize circle
// (request 46 took the dot from beside it).
import AppKit

enum MenuBarPrefs {
    static let hiddenKey = "stripeHiddenInMenuBar"
    static var stripeHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hiddenKey) }
        set { UserDefaults.standard.set(newValue, forKey: hiddenKey) }
    }
}

// iStat's way: "0.02 Mb/s", "12.3 Mb/s", "123 Mb/s"; "— Mb/s" while there is no reading.
func istatRate(_ bytesPerSecond: Double?) -> String {
    guard let b = bytesPerSecond else { return "— Mb/s" }
    let m = b * 8 / 1_000_000
    return (m < 10 ? String(format: "%.2f", m) : m < 100 ? String(format: "%.1f", m) : String(format: "%.0f", min(m, 9999))) + " Mb/s"
}

// Mbit/s in four places: " 0.0", " 9.9", "12.3", " 123", "1234" (figure spaces keep the width).
func menuBarRate(_ bytesPerSecond: Double?) -> String {
    guard let b = bytesPerSecond else { return "\u{2007}\u{2007}\u{2007}—" }
    let m = b * 8 / 1_000_000
    let s = m < 100 ? String(format: "%.1f", m) : String(format: "%.0f", min(m, 9999))
    return String(repeating: "\u{2007}", count: max(0, 4 - s.count)) + s
}

extension Stripe {
    func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.imagePosition = .imageOnly
            b.target = self
            b.action = #selector(menuBarClicked)
            b.toolTip = "Network Aggregate Connection Keeper\nInternet speed now: upload on top, download below (as iStat Menus).\nThe dot: green connected, red disconnected. Click: show or hide the stripe."
        }
        menuItem = item
        showMenuBarSpeed(nil, nil)
        led.translatesAutoresizingMaskIntoConstraints = false
        led.widthAnchor.constraint(equalToConstant: 12).isActive = true
        led.heightAnchor.constraint(equalToConstant: 12).isActive = true
        led.toolTip = "Internet: green connected, red disconnected"
        if MenuBarPrefs.stripeHidden { panel.orderOut(nil) }
    }

    // v37 (request 54, Marko 29.10.2026: "Take a screenshot of the menu bar, and you will see another app which is
    // doing the counting. Please copy the same UI"): iStat Menus' network item, drawn the same way: a round dot, then
    // two small lines, upload on top and download below, "0.02 Mb/s", right aligned in a fixed width, in the menu bar's
    // own grey. The dot is our LED.
    func showMenuBarSpeed(_ down: Double?, _ up: Double?) {
        lastMenuSpeed = (down, up)
        guard let b = menuItem?.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let lines = [istatRate(up), istatRate(down)]
        let textW = ceil(("88.88 Mb/s" as NSString).size(withAttributes: [.font: font]).width)
        let dot: CGFloat = 9, gap: CGFloat = 5, h: CGFloat = 22
        let img = NSImage(size: NSSize(width: dot + gap + textW, height: h), flipped: false) { _ in
            b.effectiveAppearance.performAsCurrentDrawingAppearance {
                (self.internetUp() ? Ink.green : Ink.red).withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: (h - dot) / 2, width: dot, height: dot)).fill()
                let style = NSMutableParagraphStyle(); style.alignment = .right
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
                (lines[0] as NSString).draw(in: NSRect(x: dot + gap, y: h / 2 - 1, width: textW, height: 11), withAttributes: attrs)
                (lines[1] as NSString).draw(in: NSRect(x: dot + gap, y: 1, width: textW, height: 11), withAttributes: attrs)
            }
            return true
        }
        img.isTemplate = false
        b.image = img
        b.title = ""
    }

    // Green while the internet answers: aggregating, a joined line alive; otherwise the keeper's last check and a road
    // to the internet at all.
    func internetUp() -> Bool {
        if Aggregation.on, let a = agg { return a.lines.contains { $0.alive } }
        if let s = state, s.isFresh, s.lastCheck?.online == false { return false }
        return iface != nil
    }

    func showLed() {
        let up = internetUp()
        led.color = up ? Ink.green : Ink.red
        if up != lastMenuUp { lastMenuUp = up; showMenuBarSpeed(lastMenuSpeed.0, lastMenuSpeed.1) }   // the dot follows
    }

    @objc func menuBarClicked() {
        if panel.isVisible {
            MenuBarPrefs.stripeHidden = true
            panel.orderOut(nil)
        } else {
            MenuBarPrefs.stripeHidden = false
            if let f = minimizedFrame { minimizedFrame = nil; panel.setFrame(f, display: true) }
            keepOnScreen()
            applyOnTop()
            panel.orderFrontRegardless()
        }
    }
}
