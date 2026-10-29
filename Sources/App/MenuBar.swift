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
            let img = NSImage(systemSymbolName: "network", accessibilityDescription: "Network Aggregate Connection Keeper")
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(menuBarClicked)
            b.toolTip = "Network Aggregate Connection Keeper\nInternet speed now, Mbit/s: download green, upload red.\nClick: show or hide the stripe."
        }
        menuItem = item
        showMenuBarSpeed(nil, nil)
        led.translatesAutoresizingMaskIntoConstraints = false
        led.widthAnchor.constraint(equalToConstant: 12).isActive = true
        led.heightAnchor.constraint(equalToConstant: 12).isActive = true
        led.toolTip = "Internet: green connected, red disconnected"
        if MenuBarPrefs.stripeHidden { panel.orderOut(nil) }
    }

    func showMenuBarSpeed(_ down: Double?, _ up: Double?) {
        guard let b = menuItem?.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let t = NSMutableAttributedString(string: " " + menuBarRate(down), attributes: [.font: font, .foregroundColor: Ink.green])
        t.append(NSAttributedString(string: " " + menuBarRate(up), attributes: [.font: font, .foregroundColor: Ink.red]))
        b.attributedTitle = t
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
        menuItem?.button?.contentTintColor = up ? nil : Ink.red      // the icon itself turns red when the internet is gone
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
