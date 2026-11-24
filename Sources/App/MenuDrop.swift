// THE DROP-DOWN CONTROLLER (request 106, Marko 24.11.2026: "when I press on it to have something similar as iSTAT drop-down
// menu, so not opening the interface itself, opening the controller as a drop-down menu. There must be also options to start
// the interface from the top, first option, and then quick options").
// A left click on the menu-bar item opens this panel under the item, on the display whose menu bar was clicked (a right
// click keeps the short FRANKFURT / CROATIA menu). It closes on a click outside, on Escape, or on a second click on the item.
// Top first: "Open Connection Keeper". Then the quick options, acting at once: FRANKFURT / CROATIA; the lines that are here
// (or ticked), grouped by family, each with its tick, its ↓ download mark, its live speed and its state word; ALL TICKED with
// the joined speed and its TEST; aggregation ON / OFF; at the bottom Check now, Open the log, Quit.
// One module: every control calls the stripe's own action (tickPressed, dlPressed, pickFrankfurt, rowTestPressed ...), every
// word and number is read from the stripe's model (tickEntries, tickState, families, the rows' live speed), so the drop-down
// is a second view of the same thing, never a copy of the rules. Left out (in the main window only): Wi-Fi networks in range
// and lines seen before but not here, the signal meters, ping, the per-line TEST, 4G / 5G, the speed test window, settings.
// The hover card (kit menubar-hover) still shows on hover; the drop-down stands above it (a higher window level) and the card
// goes as soon as the mouse leaves the item.
import AppKit

final class DropPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onEscape?() } else { super.keyDown(with: e) } }
}

final class MenuDrop: NSObject {
    static var shared: MenuDrop?
    weak var stripe: Stripe?
    let panel: DropPanel
    let column = NSStackView()
    var timer: Timer?
    var monitors: [Any] = []
    var shownNames: [String] = []
    var rows: [String: (tick: NSButton, dl: NSButton, rail: Rail, name: NSTextField, speed: NSTextField, state: NSTextField)] = [:]
    let openButton = NSButton(title: "", target: nil, action: nil)
    let frankfurt = NSButton(title: "FRANKFURT", target: nil, action: nil), croatia = NSButton(title: "CROATIA", target: nil, action: nil)
    let allSpeed = label(textWidth(speedSample(), monoFont), font: monoFont)
    let allTest = NSButton(title: "TEST", target: nil, action: nil)
    let allResult = label(textWidth("↓888.8 ↑888.8 88:88", monoFont), font: monoFont)
    let aggOn = NSButton(title: "ON", target: nil, action: nil), aggOff = NSButton(title: "OFF", target: nil, action: nil)
    let linesBox = NSStackView()
    static let nameW: CGFloat = 150, stateW = textWidth("DL: CROATIA ONLY", monoFont)

    static func toggle(_ s: Stripe) {
        if let d = shared { d.close(); return }
        shared = MenuDrop(s)
    }

    init(_ s: Stripe) {
        stripe = s
        panel = DropPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)     // above the hover card
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.onEscape = { [weak self] in self?.close() }
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Ink.ground.cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        box.layer?.borderWidth = 1
        panel.contentView = box
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        column.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: box.leadingAnchor), column.topAnchor.constraint(equalTo: box.topAnchor),
                                     column.trailingAnchor.constraint(equalTo: box.trailingAnchor), column.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
        build()
        refresh()
        place()
        panel.orderFrontRegardless()
        panel.makeKey()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common); timer = t
        // a click anywhere else closes it (other apps: global monitor; our own other windows: local monitor)
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.close() }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            guard let self else { return e }
            if e.window !== self.panel && !(e.window?.className.contains("StatusBar") ?? false) { self.close() }
            return e
        }) { monitors.append(l) }
        appendLog("\(logStamp()) MENU BAR drop-down opened")
    }

    func close() {
        timer?.invalidate(); timer = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        panel.orderOut(nil)
        if MenuDrop.shared === self { MenuDrop.shared = nil }
    }

    // under the item, on the display whose menu bar was clicked (the mouse is there), kept inside that display
    func place() {
        let m = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = column.fittingSize
        guard let f = scr?.frame else { return }
        let top = f.maxY - NSStatusBar.system.thickness - 4
        let x = min(max(m.x - 30, f.minX + 6), f.maxX - size.width - 6)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: the pieces

    func section(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 9.5, weight: .semibold)
        l.textColor = Ink.dim
        return l
    }
    func word(_ b: NSButton, _ size: CGFloat = 12) {
        b.isBordered = false
        b.font = .monospacedSystemFont(ofSize: size, weight: .bold)
        b.setContentHuggingPriority(.required, for: .horizontal)
    }
    func rule() -> NSView {
        let r = NSBox(); r.boxType = .separator
        r.translatesAutoresizingMaskIntoConstraints = false
        return r
    }

    func build() {
        guard let s = stripe else { return }
        word(openButton, 13)
        openButton.target = self; openButton.action = #selector(openPressed)
        openButton.alignment = .left
        openButton.setAccessibilityIdentifier("drop-open")
        for (b, sel, id) in [(frankfurt, #selector(Stripe.pickFrankfurt), "drop-frankfurt"), (croatia, #selector(Stripe.pickCroatia), "drop-croatia")] {
            word(b); b.target = s; b.action = sel; b.setAccessibilityIdentifier(id)
        }
        for (b, on) in [(aggOn, true), (aggOff, false)] {
            word(b); b.target = self; b.action = on ? #selector(aggOnPressed) : #selector(aggOffPressed)
            b.setAccessibilityIdentifier(on ? "drop-agg-on" : "drop-agg-off")
        }
        word(allTest, 11)
        allTest.target = s; allTest.action = #selector(Stripe.rowTestPressed(_:))
        allTest.identifier = NSUserInterfaceItemIdentifier(Stripe.allTickedName)
        allTest.setAccessibilityIdentifier("drop-test-all")
        linesBox.orientation = .vertical; linesBox.alignment = .leading; linesBox.spacing = 0
        let allName = label(MenuDrop.nameW + Rail.width + 40, font: .systemFont(ofSize: 12, weight: .semibold))
        allName.stringValue = "ALL TICKED"; allName.textColor = Ink.green
        let allRow = NSStackView(views: [allName, allSpeed, allTest, allResult]); allRow.spacing = 6
        let way = NSStackView(views: [frankfurt, croatia]); way.spacing = 14
        let agg = NSStackView(views: [section("AGGREGATION"), aggOn, aggOff]); agg.spacing = 10
        var bottom: [NSView] = []
        for (t, sel, target) in [("Check now", #selector(Stripe.checkNow), s as AnyObject), ("Open the log", #selector(Stripe.openLog), s as AnyObject),
                                 ("Quit (back to the normal connection)", #selector(NSApplication.terminate(_:)), NSApp as AnyObject)] {
            let b = NSButton(title: t, target: target, action: sel)
            b.isBordered = false; b.font = .systemFont(ofSize: 12); b.contentTintColor = Ink.text; b.alignment = .left
            bottom.append(b)
        }
        let views: [NSView] = [openButton, rule(), section("WAY"), way, rule(), section("LINES"), linesBox, allRow, rule(), agg, rule()] + bottom
        for v in views { column.addArrangedSubview(v) }
        for v in column.arrangedSubviews where v is NSBox { v.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -24).isActive = true }
        column.setCustomSpacing(8, after: openButton)
    }

    // the lines shown: those here now and those ticked (in the stripe's order: by family, wired first)
    func buildLines() {
        guard let s = stripe else { return }
        let ticked = Set(s.tickedNames)
        let entries = s.tickEntries().filter { $0.other != nil || ticked.contains($0.name) }
        let names = entries.map(\.name)
        guard names != shownNames else { return }
        shownNames = names
        for v in linesBox.arrangedSubviews { linesBox.removeArrangedSubview(v); v.removeFromSuperview() }
        rows = [:]
        for e in entries {
            let tick = NSButton(checkboxWithTitle: "", target: s, action: #selector(Stripe.tickPressed(_:)))
            tick.appearance = NSAppearance(named: .darkAqua)
            tick.identifier = NSUserInterfaceItemIdentifier(e.name); tick.setAccessibilityIdentifier("drop-tick-" + e.name)
            let dl = NSButton(); dl.isBordered = false; dl.imagePosition = .imageOnly
            dl.target = s; dl.action = #selector(Stripe.dlPressed(_:))
            dl.identifier = NSUserInterfaceItemIdentifier(e.name); dl.setAccessibilityIdentifier("drop-download-" + e.name)
            dl.translatesAutoresizingMaskIntoConstraints = false
            dl.widthAnchor.constraint(equalToConstant: 16).isActive = true
            let rail = Rail()
            rail.translatesAutoresizingMaskIntoConstraints = false
            rail.widthAnchor.constraint(equalToConstant: Rail.width).isActive = true
            rail.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let name = label(MenuDrop.nameW, font: .systemFont(ofSize: 12, weight: .semibold))
            let speed = label(textWidth(speedSample(), monoFont), font: monoFont)
            let state = label(MenuDrop.stateW, font: monoFont)
            let row = NSStackView(views: [rail, tick, dl, name, speed, state])
            row.spacing = 4; row.setCustomSpacing(0, after: rail)
            row.heightAnchor.constraint(equalToConstant: 22).isActive = true
            linesBox.addArrangedSubview(row)
            rows[e.name] = (tick, dl, rail, name, speed, state)
        }
        place()
    }

    // every second while open: the same words and numbers as the stripe's rows
    func refresh() {
        guard let s = stripe else { close(); return }
        buildLines()
        let open = s.panel.isVisible && !MenuBarPrefs.stripeHidden
        openButton.title = open ? "Connection Keeper is open: bring it forward" : "Open Connection Keeper"
        openButton.contentTintColor = Ink.green
        let bond = BondConfigFile.load()?.on == true
        frankfurt.contentTintColor = bond ? Ink.green : Ink.grey
        croatia.contentTintColor = bond ? Ink.grey : Ink.green
        let ticked = Set(s.tickedNames)
        let entries = s.tickEntries().filter { rows[$0.name] != nil }
        let fam = s.families(entries.map(\.name))
        for (i, e) in entries.enumerated() {
            guard let r = rows[e.name] else { continue }
            let on = ticked.contains(e.name)
            if (r.tick.state == .on) != on { r.tick.state = on ? .on : .off }
            let mark = DownloadLine.line == e.name
            r.dl.image = NSImage(systemSymbolName: mark ? "arrow.down.circle.fill" : "arrow.down.circle", accessibilityDescription: "download line")
            r.dl.contentTintColor = mark ? Ink.green : Ink.dim
            r.dl.toolTip = mark ? "DOWNLOADS: big downloads go here. Click: no download line." : "Downloads: make \(e.name) the line for big downloads"
            let f = fam[e.name] ?? [e.name]
            let prev = i > 0 && f.contains(entries[i - 1].name), next = i + 1 < entries.count && f.contains(entries[i + 1].name)
            r.rail.pos = f.count < 2 ? .none : !prev ? .first : next ? .middle : .last
            r.rail.lit = on
            let st = s.tickState(e, ticked: on)
            r.name.stringValue = e.other.map { Net.shown($0.name, $0.iface) } ?? e.name
            r.name.textColor = on ? (st.color == Ink.green ? Ink.green : st.color) : (e.other == nil ? Ink.grey : NSColor.white)
            r.state.stringValue = st.word; r.state.textColor = st.color
            if let row = s.lineRows[e.name] { r.speed.attributedStringValue = row.speed.attributedStringValue }
        }
        if let a = s.aggRow { allSpeed.attributedStringValue = a.speed.attributedStringValue }
        let tw = s.testWords(Stripe.allTickedName)
        allResult.stringValue = tw.0; allResult.textColor = tw.1; allResult.toolTip = tw.2
        allTest.isEnabled = LineSpeedTest.running == nil
        allTest.contentTintColor = allTest.isEnabled ? Ink.text : Ink.grey
        let aggregating = !s.tickedNames.isEmpty
        aggOn.contentTintColor = aggregating ? Ink.green : Ink.grey
        aggOff.contentTintColor = aggregating ? Ink.grey : Ink.green
        aggOn.toolTip = "ON: the ticked lines joined" + (Aggregation.selected.isEmpty ? "" : " (" + Aggregation.selected.joined(separator: " + ") + ")")
        aggOff.toolTip = "OFF: no tick, the Mac straight on its own connection"
    }

    @objc func openPressed() {
        close()
        stripe?.bringStripe()
    }
    @objc func aggOnPressed() {
        guard let s = stripe, s.tickedNames.isEmpty else { return }
        let last = Aggregation.selected
        if last.isEmpty { s.show("no line ticked before: tick the lines in the list", Ink.amber, for: 8); return }
        s.setTicks(last)
    }
    @objc func aggOffPressed() {
        guard let s = stripe, !s.tickedNames.isEmpty else { return }
        s.setTicks([])
    }
}
