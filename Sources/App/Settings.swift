// The gear: which connections the keeper may use, in which order, and how often it checks.
// Every change is written to ~/.config/connection-keeper.json at once; the keeper reads it on its
// next round.
import AppKit
import Security

final class SettingsWindow: NSObject {
    let window: NSWindow
    let rows = NSStackView()
    let addPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    let interval = NSTextField(string: "")
    let dry = NSButton(checkboxWithTitle: "Dry run (the keeper only logs what it would do)", target: nil, action: nil)
    let onTop = NSButton(checkboxWithTitle: "Always on top (the stripe stays above every window, on every Space)", target: nil, action: nil)
    var cfg = Config.load()
    let testAll = NSButton(title: "Speed test all", target: nil, action: nil)
    let speedStatus = NSTextField(labelWithString: "")
    var testing = false
    let alertLine = NSTextField(labelWithString: "")
    let dataLine = NSTextField(labelWithString: "")
    let dataAuto = NSButton(checkboxWithTitle: "Check the data balance by itself every", target: nil, action: nil)
    let dataHours = NSTextField(string: "")
    let unitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    var stackView: NSStackView!

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(appName): Settings"
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Connections, in the order the keeper tries them")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6

        addPopup.target = self
        addPopup.action = #selector(add(_:))

        interval.alignment = .right
        interval.widthAnchor.constraint(equalToConstant: 50).isActive = true
        interval.target = self
        interval.action = #selector(intervalChanged)
        let intervalRow = NSStackView(views: [NSTextField(labelWithString: "Check every"), interval, NSTextField(labelWithString: "minutes")])

        dry.target = self
        dry.action = #selector(dryChanged)
        onTop.target = self
        onTop.action = #selector(onTopChanged)

        // The version, plain and dim; a click opens the newest release (version-visible.md).
        let version = NSButton(title: "v\(CKVersion)", target: self, action: #selector(openRelease))
        version.isBordered = false
        version.font = .systemFont(ofSize: 11)
        version.contentTintColor = .secondaryLabelColor

        testAll.target = self
        testAll.action = #selector(speedAll)
        speedStatus.textColor = .secondaryLabelColor
        speedStatus.font = .systemFont(ofSize: 11)
        let speedRow = NSStackView(views: [testAll, speedStatus])

        // v8: the Telemach data balance. Each check is one SMS (STANJE to 13880), so the automatic one is off by default.
        let checkData = NSButton(title: "Check data", target: self, action: #selector(checkDataNow))
        checkData.toolTip = "Send STANJE to 13880 through the router now and show what is left (one SMS)"
        dataLine.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dataLine.textColor = .secondaryLabelColor
        dataAuto.target = self
        dataAuto.action = #selector(dataAutoChanged)
        dataHours.alignment = .right
        dataHours.widthAnchor.constraint(equalToConstant: 40).isActive = true
        dataHours.target = self
        dataHours.action = #selector(dataAutoChanged)
        let dataRow = NSStackView(views: [checkData, dataLine])
        let dataAutoRow = NSStackView(views: [dataAuto, dataHours, NSTextField(labelWithString: "hours (one SMS each time)")])

        // v9: the speed unit, for the stripe and the speed test results.
        for u in SpeedUnit.allCases { unitPopup.addItem(withTitle: u.title); unitPopup.lastItem?.representedObject = u.rawValue }
        unitPopup.target = self
        unitPopup.action = #selector(unitChanged)
        let unitRow = NSStackView(views: [NSTextField(labelWithString: "Speed unit"), unitPopup])

        alertLine.lineBreakMode = .byWordWrapping
        alertLine.maximumNumberOfLines = 0
        alertLine.preferredMaxLayoutWidth = 560

        let stack = NSStackView(views: [alertLine, title, rows, speedRow, addPopup, intervalRow, unitRow, dataRow, dataAutoRow, onTop, dry, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 24)
        stackView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
    }

    func show() {
        cfg = Config.load()
        // The failover alert (v4) stands in red above the list, the same words as on the stripe.
        if let a = FailoverAlert.load() {
            alertLine.stringValue = "\(a.line). Check what is wrong with \(a.from); OK on the stripe clears it."
            alertLine.textColor = NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.30, alpha: 1)
            alertLine.font = .systemFont(ofSize: 13, weight: .bold)
            alertLine.isHidden = false
        } else {
            alertLine.isHidden = true
        }
        rebuild()
        sizeToContent()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func rebuild() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, c) in cfg.connections.enumerated() {
            let on = NSButton(checkboxWithTitle: c.name, target: self, action: #selector(toggle(_:)))
            on.state = c.enabled ? .on : .off
            on.tag = i
            on.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let kind = NSTextField(labelWithString: c.kind == "wifi" ? "Wi-Fi" : "\(c.kind) (not driven yet)")
            kind.textColor = .secondaryLabelColor
            kind.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let up = small("▲", #selector(moveUp(_:)), i); up.isEnabled = i > 0
            let down = small("▼", #selector(moveDown(_:)), i); down.isEnabled = i < cfg.connections.count - 1
            let remove = small("✕", #selector(remove(_:)), i)
            let speed = small("Speed test", #selector(speedOne(_:)), i); speed.isEnabled = !testing && c.kind == "wifi"
            let result = NSTextField(labelWithString: Speed.load()[c.name]?.line ?? "")
            result.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            result.textColor = .secondaryLabelColor
            let pw = small(WifiPassword.has(c.name) ? "Password ✓" : "Password…", #selector(password(_:)), i)
            pw.isEnabled = c.kind == "wifi"
            pw.toolTip = "macOS 15 lets the keeper join a Wi-Fi only with its password (or through Control Centre with the Accessibility permission). Kept in your login keychain, nowhere else."
            rows.addArrangedSubview(NSStackView(views: [on, kind, up, down, remove, pw, speed, result]))
        }

        addPopup.removeAllItems()
        addPopup.addItem(withTitle: "Add a Wi-Fi the Mac knows…")
        let have = Set(cfg.connections.map { $0.name })
        for name in Net.preferredNetworks(Net.wifiInterface() ?? "en0") where !have.contains(name) {
            addPopup.addItem(withTitle: name)
        }
        interval.stringValue = String(format: "%g", Double(cfg.intervalSeconds) / 60)
        dry.state = cfg.dryRun ? .on : .off
        onTop.state = OnTop.on ? .on : .off
        if let i = SpeedUnit.allCases.firstIndex(of: SpeedUnit.current) { unitPopup.selectItem(at: i) }
        DispatchQueue.main.async { self.sizeToContent() }
        dataLine.stringValue = DataBalance.load().map { "\($0.line)  (Telemach \($0.at))" } ?? "not asked yet"
        dataAuto.state = DataAuto.hours > 0 ? .on : .off
        if dataHours.stringValue.isEmpty || DataAuto.hours > 0 { dataHours.stringValue = "\(DataAuto.hours > 0 ? DataAuto.hours : 6)" }
    }

    // v9 (Marko 14.10.2026: "In the settings, we have cutting text. It's too close to the edge"): the window takes the
    // size its content needs, with 20 points of margin, every time the content changes.
    func sizeToContent() {
        guard let stack = stackView else { return }
        stack.layoutSubtreeIfNeeded()
        // NSStackView's fittingSize leaves out the right inset when a row is wider than the rest: count it ourselves.
        let widest = stack.arrangedSubviews.filter { !$0.isHidden }.map { $0.fittingSize.width }.max() ?? 0
        let width = max(560, widest + stack.edgeInsets.left + stack.edgeInsets.right)
        let want = stack.fittingSize
        let origin = window.frame.origin, oldHeight = window.frame.height
        window.setContentSize(NSSize(width: width, height: want.height))
        window.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + oldHeight - window.frame.height))   // keep the top
    }

    @objc func unitChanged() {
        guard let raw = unitPopup.selectedItem?.representedObject as? String, let u = SpeedUnit(rawValue: raw) else { return }
        SpeedUnit.current = u
        appendLog("\(logStamp()) speed unit: \(u.title)")
        rebuild()
    }

    @objc func checkDataNow() {
        NotificationCenter.default.post(name: DataBalanceNote.checkNow, object: nil)
        dataLine.stringValue = "checking… (the stripe shows the answer)"
    }

    @objc func dataAutoChanged() {
        let h = Int(dataHours.stringValue) ?? 6
        DataAuto.hours = dataAuto.state == .on ? max(1, h) : 0
        appendLog("\(logStamp()) DATA automatic check " + (DataAuto.hours > 0 ? "every \(DataAuto.hours) h" : "off"))
    }

    func small(_ t: String, _ a: Selector, _ tag: Int) -> NSButton {
        let b = NSButton(title: t, target: self, action: a)
        b.bezelStyle = .inline
        b.tag = tag
        return b
    }

    func commit() { cfg.save(); rebuild() }

    @objc func toggle(_ b: NSButton) { cfg.connections[b.tag].enabled = b.state == .on; commit() }
    @objc func moveUp(_ b: NSButton) { cfg.connections.swapAt(b.tag, b.tag - 1); commit() }
    @objc func moveDown(_ b: NSButton) { cfg.connections.swapAt(b.tag, b.tag + 1); commit() }
    @objc func remove(_ b: NSButton) { cfg.connections.remove(at: b.tag); commit() }

    @objc func add(_ p: NSPopUpButton) {
        guard p.indexOfSelectedItem > 0, let name = p.titleOfSelectedItem else { return }
        cfg.connections.append(Connection(kind: "wifi", name: name))
        commit()
    }

    @objc func intervalChanged() {
        if let m = Double(interval.stringValue.replacingOccurrences(of: ",", with: ".")), m > 0 {
            cfg.intervalSeconds = max(30, Int(m * 60))
        }
        commit()
    }

    // The Wi-Fi password, once (v5): typed into a secure field, kept in the login keychain for this app and its
    // keeper only. Empty and Save removes it.
    @objc func password(_ b: NSButton) {
        let name = cfg.connections[b.tag].name
        let a = NSAlert()
        a.messageText = "Password for \(name)"
        a.informativeText = "So the keeper can switch to \(name) by itself. It stays in your login keychain; nobody sees it. Leave it empty and Save to remove it."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = field
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if field.stringValue.isEmpty {
            WifiPassword.remove(name)
            appendLog("\(logStamp()) password for \"\(name)\" removed in Settings")
        } else {
            let st = WifiPassword.set(name, field.stringValue)
            appendLog("\(logStamp()) password for \"\(name)\" " + (st == errSecSuccess ? "stored in the keychain" : "NOT stored (keychain error \(st))"))
        }
        rebuild()
    }

    @objc func onTopChanged() { OnTop.on = onTop.state == .on }

    @objc func dryChanged() { cfg.dryRun = dry.state == .on; commit() }

    // SPEED TEST: one connection, or every Wi-Fi in the list in order. Testing one that is not in use switches the Mac
    // to it for about half a minute and back, so he is told first.
    @objc func speedOne(_ b: NSButton) { runTests([cfg.connections[b.tag]]) }
    @objc func speedAll() { runTests(cfg.connections.filter { $0.kind == "wifi" }) }

    func runTests(_ list: [Connection]) {
        guard !testing, !list.isEmpty else { return }
        let here = Net.wifiInterface().flatMap { Net.currentSSID($0) }
        let others = list.filter { $0.name != here }.map { $0.name }
        if !others.isEmpty {
            let a = NSAlert()
            a.messageText = "Switch Wi-Fi to test?"
            a.informativeText = "To measure \(others.joined(separator: ", ")) the Mac joins it for about half a minute, then goes back to \(here ?? "the network it is on"). The internet drops for a few seconds at each switch."
            a.addButton(withTitle: "Test"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        testing = true; testAll.isEnabled = false; rebuild()
        DispatchQueue.global().async {
            for c in list {
                let r = Speed.test(c) { msg in DispatchQueue.main.async { self.speedStatus.stringValue = msg } }
                Speed.save(r)
                DispatchQueue.main.async { self.rebuild() }
            }
            DispatchQueue.main.async {
                self.testing = false; self.testAll.isEnabled = true
                self.speedStatus.stringValue = "done"; self.rebuild()
            }
        }
    }

    @objc func openRelease() { NSWorkspace.shared.open(URL(string: CKReleaseURL)!) }
}
