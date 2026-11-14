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
        let item = MenuBarPlace.make()
        configureStatusButton(item)
        menuItem = item
        showMenuBarSpeed(nil, nil)
        led.translatesAutoresizingMaskIntoConstraints = false
        led.widthAnchor.constraint(equalToConstant: 12).isActive = true
        led.heightAnchor.constraint(equalToConstant: 12).isActive = true
        led.toolTip = "Internet: green connected, red disconnected"
        if MenuBarPrefs.stripeHidden { panel.orderOut(nil) }
        // v55: next to iStat Menus' network item, kept there (see MenuBarPlace)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.checkMenuPlace(tries: 2) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.checkMenuPlace(tries: 2) }
        }
    }

    func configureStatusButton(_ item: NSStatusItem) {
        if let b = item.button {
            b.imagePosition = .imageOnly
            b.target = self
            b.action = #selector(menuBarClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])     // v80: a right click opens FRANKFURT / CROATIA
            b.toolTip = "Network Aggregate Connection Keeper\nInternet speed now: upload on top, download below (as iStat Menus).\nThe dot: green connected, red disconnected. Click: show or hide the stripe."
        }
    }

    // v56: measured on this Mac (13.11.2026, a test status item made from Python): the "NSStatusItem Preferred Position"
    // value only orders an item among the items that have a stored value (Control Centre, SoundSource, Hot ...). Any value
    // above about 650 lands at the left end of that group (x about 2056 on the BenQ); every item without a stored value
    // (iStat, Hammerspoon, Speechify, AutoRaise, BetterDisplay, Little Snitch, Claude ...) sits LEFT of that group in
    // launch order, and a new item without a value goes to the far left. So a key cannot put us beside iStat; only a
    // Cmd-drag by hand does, and macOS then stores the position. v55 recreated the item three times trying; v56 only logs
    // the distance once and leaves the item alone.
    func checkMenuPlace(tries: Int) {
        guard !menuPlaceLogged, let item = menuItem, let w = item.button?.window, let istat = MenuBarPlace.istatLeft() else { return }
        menuPlaceLogged = true
        appendLog("\(logStamp()) MENU BAR item right edge \(Int(w.frame.maxX)), iStat's network item left edge \(Int(istat)): \(Int(istat - w.frame.maxX)) pt apart (Cmd-drag it once to sit beside iStat; macOS keeps that)")
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
                // v82 (request 91): amber while NOTHING ONLY runs on its fallback line
                let fallback = NothingOnly.state?.hasPrefix("standby") == true
                (self.internetUp() ? (fallback ? Ink.amber : Ink.green) : Ink.red).withAlphaComponent(0.85).setFill()
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

    // v43 (Marko 1.11.2026: "I have an icon on the menu bar. When I click it, nothing happens. When I click it, my user
    // interface should come in front and be on top"): the icon stands in the menu bar of every display, and the stripe
    // stayed on the MacBook while he clicked on the BenQ's, so the click hid or showed it where he was not looking.
    // Now a click brings the stripe to the display whose icon was clicked (top middle, unless it is on that display
    // already), on top of everything; only a click while it stands there, in front, hides it again.
    @objc func menuBarClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            let m = NSMenu()
            let on = BondConfigFile.load()?.on == true
            let f = NSMenuItem(title: "FRANKFURT (through the relay)", action: #selector(pickFrankfurt), keyEquivalent: ""); f.target = self; f.state = on ? .on : .off
            let c = NSMenuItem(title: "CROATIA (straight over my lines)", action: #selector(pickCroatia), keyEquivalent: ""); c.target = self; c.state = on ? .off : .on
            m.addItem(f); m.addItem(c)
            if let b = menuItem?.button { m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 4), in: b) }
            return
        }
        let screen = menuItem?.button?.window?.screen ?? NSScreen.main
        let here = panel.isVisible && panel.screen == screen && panel.occlusionState.contains(.visible) && !MenuBarPrefs.stripeHidden
        if here {
            MenuBarPrefs.stripeHidden = true
            panel.orderOut(nil)
            appendLog("\(logStamp()) MENU BAR click: stripe hidden")
            return
        }
        MenuBarPrefs.stripeHidden = false
        if panel.isMiniaturized { panel.deminiaturize(nil) }         // v81: his click brings it out of the Dock
        if let f = minimizedFrame { minimizedFrame = nil; panel.setFrame(f, display: true) }
        if let s = screen, panel.screen != s {
            let v = s.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.midX - panel.frame.width / 2, y: v.maxY - panel.frame.height - 6))
        }
        keepOnScreen()
        applyOnTop()
        panel.collectionBehavior.insert(.moveToActiveSpace)          // v48: to his desktop on this click only
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.applyOnTop() }
        appendLog("\(logStamp()) MENU BAR click: stripe in front on \(screen?.localizedName ?? "?")")
    }
}

// MY CONNECTION KEEPER ALWAYS AVAILABLE, BESIDE ISTAT (v55, Marko 13.11.2026: "please put My Connection Keeper Always
// Available in the menu bar. Make it start by system and let it be there, always positioned next to this ISTAT. They need
// to be next to each other; they are partners"). macOS keeps a status item's place in the defaults key
// "NSStatusItem Preferred Position <autosaveName>" (our own domain), the distance in points from the RIGHT edge of the
// menu bar display, read when the item is created. iStat's item is found by its window (owner "iStat Menus Status",
// layer 25, on the main display; its name "com.bjango.istatmenus.network" is only readable with the Screen Recording
// permission, so without it the leftmost iStat item on that display is used). Ours is put with its right edge at iStat's
// left edge: preferred = display width - iStat's x. iStat's own preferences are never written.
import ServiceManagement

enum MenuBarPlace {
    static let name = "ConnectionKeeperItem"
    static var key: String { "NSStatusItem Preferred Position " + name }

    // iStat's network item's left edge on the main display, in points (window coordinates, origin top-left).
    static func istatLeft() -> CGFloat? {
        let main = CGDisplayBounds(CGMainDisplayID())
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var xs: [(CGFloat, String)] = []
        for w in list where (w[kCGWindowOwnerName as String] as? String) == "iStat Menus Status" && (w[kCGWindowLayer as String] as? Int) == 25 {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let wd = b["Width"], let h = b["Height"],
                  h <= 40, x >= main.minX, x + wd <= main.maxX else { continue }
            xs.append((x, (w[kCGWindowName as String] as? String) ?? ""))
        }
        if let n = xs.first(where: { $0.1.hasSuffix(".network") }) { return n.0 }
        return xs.map(\.0).min()
    }

    static func preferred() -> Double? {
        guard let x = istatLeft() else { return nil }
        return Double(CGDisplayBounds(CGMainDisplayID()).width - x)
    }

    // The item, with the position set first (nothing is written to iStat's domain).
    static func make() -> NSStatusItem {
        if let p = preferred() { UserDefaults.standard.set(p, forKey: key) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        item.isVisible = true
        return item
    }

    // At every start: the app is a login item, so the menu bar item is there after a restart, stripe shown or not.
    static func registerLogin() {
        let s = SMAppService.mainApp
        if s.status != .enabled {
            do { try s.register(); appendLog("\(logStamp()) LOGIN ITEM registered (status \(s.status.rawValue))") }
            catch { appendLog("\(logStamp()) LOGIN ITEM could not be registered: \(error.localizedDescription) (System Settings > General > Login Items)") }
        }
    }
}
