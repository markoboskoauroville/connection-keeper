// Connection Keeper (Mantra): one floating stripe that shows the connection, its speed and the
// keeper's last word, with a drop-down to switch by hand and a gear for the list of connections.
import AppKit
import CoreWLAN

let appName = "Connection Keeper (Mantra)"

enum DataBalanceNote { static let checkNow = Notification.Name("ConnectionKeeperCheckData") }

// ALWAYS ON TOP (v6, Marko 14.10.2026: "please keep it always on top, which can be changed in the settings").
// A setting of the stripe only, remembered in its defaults; on unless he turns it off in ⚙.
enum OnTop {
    static let key = "alwaysOnTop"
    static let changed = Notification.Name("ConnectionKeeperOnTopChanged")
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); NotificationCenter.default.post(name: changed, object: nil) }
    }
}

// TRAIL-like ground: dark, colour only for state. Green on, amber holding / working, red down,
// grey present but not available.
enum Ink {
    static let ground = NSColor(calibratedWhite: 0.08, alpha: 0.94)
    static let text = NSColor(calibratedWhite: 0.88, alpha: 1)
    static let dim = NSColor(calibratedWhite: 0.55, alpha: 1)
    static let green = NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.45, alpha: 1)
    static let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 1)
    static let red = NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.30, alpha: 1)
    static let grey = NSColor(calibratedWhite: 0.40, alpha: 1)
    static let yellow = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.20, alpha: 1)   // v12: the ping section (Marko)
}

// v9 (Marko 14.10.2026: "the whole status line is breathing. So I'm trying to click on the settings icon and it's
// moving"): every item has a FIXED width, sized for its widest text, so changing numbers never move anything; the
// stripe changes width only when its state changes (red, NO OTHER CONNECTION, a message), and keeps its left edge.
let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
    ceil((s as NSString).size(withAttributes: [.font: font]).width) + 6
}

func label(_ width: CGFloat, align: NSTextAlignment = .left, font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)) -> NSTextField {
    let l = NSTextField(labelWithString: "")
    l.font = font
    l.textColor = Ink.text
    l.alignment = align
    l.lineBreakMode = .byTruncatingTail
    l.translatesAutoresizingMaskIntoConstraints = false
    l.widthAnchor.constraint(equalToConstant: width).isActive = true
    l.setContentHuggingPriority(.required, for: .horizontal)
    return l
}

func fixWidth(_ v: NSView, _ width: CGFloat) -> NSLayoutConstraint {
    let c = v.widthAnchor.constraint(equalToConstant: width)
    c.isActive = true
    return c
}

func rate(_ bytesPerSecond: Double) -> String { SpeedUnit.current.format(bytesPerSecond: bytesPerSecond) }

// The widest speed text of the chosen unit: auto never needs more than five places, a fixed unit up to nine.
func speedSample() -> String {
    let u = SpeedUnit.current
    let digits = (u == .autoBits || u == .autoBytes) ? 5 : 9
    let n = String(repeating: "8", count: digits) + " " + String(repeating: "M", count: u.unitWidth)
    return "\(n)  (88.8)  \(n)  (88.8)"     // testPart is seven places: " (88.8)"
}

// v12 (Marko 18.10.2026: "you're using too much of my real estate ... remove internet ... just in parentheses. Put the
// test results ... I don't need the time"): the last speedtest.net result in parentheses after each live number, in
// Mbit/s (MB/s when the unit is bytes); "(...)" until this run has tested, "(✗)" for 30 s after one failed.
func testPart(_ mbps: Double?, mark: String?) -> String {
    let inner: String
    if let mark { inner = mark }
    else if let mbps { inner = SpeedUnit.slot(SpeedUnit.current.isBits ? mbps : mbps / 8).trimmingCharacters(in: .whitespaces) }
    else { inner = "—" }
    let t = "(\(inner))"
    return String(repeating: " ", count: max(0, 7 - t.count)) + t
}

// v12 (Marko 18.10.2026: "every Wi-Fi device will be green. Every LAN port hardware port or maybe tethering through
// phone will be yellow"): the connection's name takes the colour of the device the internet goes through.
func isWiFi(_ iface: String?) -> Bool {
    guard let iface else { return false }
    return CWWiFiClient.shared().interfaceNames()?.contains(iface) ?? false
}

func ago(_ d: Date?) -> String {
    guard let d else { return "never" }
    let s = Int(Date().timeIntervalSince(d))
    if s < 60 { return "\(max(s, 0)) s ago" }
    if s < 3600 { return "\(s / 60) min ago" }
    if s < 86400 { return "\(s / 3600) h ago" }
    return "\(s / 86400) d ago"
}

final class Dot: NSView {
    var color = Ink.grey { didSet { needsDisplay = true } }
    override func draw(_ r: NSRect) { color.setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill() }
}

final class Stripe: NSObject {
    let panel: NSPanel
    let dot = Dot()
    let connButton = NSButton(title: "…", target: nil, action: nil)
    let speed = label(textWidth(speedSample(), monoFont), font: monoFont)
    var speedWidth: NSLayoutConstraint!
    var connWidth: NSLayoutConstraint!
    let ping = NSButton(title: "ping —", target: nil, action: nil)
    let data = NSButton(title: "data —", target: nil, action: nil)   // v8: the Telemach balance; a click asks now
    var dataBusy = false
    var lastTest = WebSpeed.load()              // v11/v12: the last speedtest.net result, in parentheses beside the speed
    var testMark: String?                       // "..." until tested, "✗" after a failure
    var webBusy = false
    var webHeld = Date.distantPast
    var dataHeld = Date.distantPast             // a failed check's words stay until then
    let checked = label(Stripe.checkedNormal)
    let failover = label(Stripe.failoverNormal)
    static let checkedNormal = textWidth("checked 59 min ago ✓", .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
    static let failoverNormal = textWidth("failover 59 min ago", .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
    let ok = NSButton(title: "OK", target: nil, action: nil)
    let gear = NSButton(title: "⚙", target: nil, action: nil)
    var failoverWidth: NSLayoutConstraint!
    var checkedPipe: NSTextField!
    var failoverPipe: NSTextField!
    var checkedWidth: NSLayoutConstraint!
    var noOther = false                         // the keeper says NO OTHER CONNECTION: the status is red
    var red = false                             // the failover alert is on: every word is red

    var iface: String?
    var lastCounters: (rx: UInt64, tx: UInt64)?
    var sampling = false
    var lastSample = Date()
    var tick = 0
    var state: KeeperState?
    var settings: SettingsWindow?
    var here: String?
    var pingHeld = Date.distantPast             // the answer of a pressed ping stays on the stripe until then

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 30),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        applyOnTop()
        NotificationCenter.default.addObserver(forName: OnTop.changed, object: nil, queue: .main) { [weak self] _ in self?.applyOnTop() }
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Ink.ground.cgColor
        root.layer?.cornerRadius = 8
        panel.contentView = root

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 12).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 12).isActive = true

        for b in [connButton, gear] {
            b.isBordered = false
            b.target = self
            b.font = .systemFont(ofSize: 12, weight: .semibold)
            b.contentTintColor = Ink.text
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        connButton.action = #selector(showConnections)
        connButton.alignment = .left
        connButton.toolTip = "Switch the connection"
        ping.isBordered = false
        ping.target = self
        ping.action = #selector(pingNow)
        ping.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ping.contentTintColor = Ink.yellow
        ping.alignment = .left
        ping.translatesAutoresizingMaskIntoConstraints = false
        ping.toolTip = "Press: ping now and say on the stripe whether the internet is alive"
        data.isBordered = false
        data.target = self
        data.action = #selector(checkDataByHand)
        data.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        data.contentTintColor = Ink.text
        data.alignment = .left
        data.translatesAutoresizingMaskIntoConstraints = false
        data.setContentHuggingPriority(.required, for: .horizontal)
        _ = fixWidth(data, textWidth("888.8 GB left", monoFont))
        // "When I click on download speed, it tests download speed" (request 16): the live speed starts the test too
        speed.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(testSpeedByHand)))
        speed.maximumNumberOfLines = 1
        speed.cell?.wraps = false
        speed.lineBreakMode = .byClipping
        speed.toolTip = speedTip()
        data.font = monoFont
        ping.font = monoFont
        _ = fixWidth(ping, textWidth("ping 999 ms", monoFont))
        speedWidth = speed.constraints.first { $0.firstAttribute == .width }
        connWidth = fixWidth(connButton, connectionWidth())
        NotificationCenter.default.addObserver(forName: SpeedUnit.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.speedWidth.constant = textWidth(speedSample(), monoFont)
            self.lastCounters = nil
            self.fit()
        }
        // OK: Marko has seen that the first connection died. A click on the red failover words does the same.
        ok.bezelStyle = .rounded
        ok.controlSize = .small
        ok.font = .systemFont(ofSize: 11, weight: .bold)
        ok.target = self
        ok.action = #selector(acknowledge)
        ok.toolTip = "I have seen it: back to the normal colours"
        ok.translatesAutoresizingMaskIntoConstraints = false
        ok.isHidden = true
        failover.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(acknowledge)))
        failoverWidth = failover.constraints.first { $0.firstAttribute == .width }
        checkedWidth = checked.constraints.first { $0.firstAttribute == .width }
        gear.action = #selector(openSettings)
        gear.font = .systemFont(ofSize: 15)
        gear.toolTip = "Settings: the connections and their order"

        // v7 (Marko 14.10.2026: "reduce the space between the text and just put pipes in between"): the items sit
        // close, a dim pipe between them, and the stripe is as wide as its words.
        func pipe() -> NSTextField {
            let p = NSTextField(labelWithString: "|")
            p.textColor = Ink.grey
            p.font = .systemFont(ofSize: 12)
            p.setContentHuggingPriority(.required, for: .horizontal)
            return p
        }
        checkedPipe = pipe()
        failoverPipe = pipe()
        for b in [connButton, ping, gear] { b.setContentHuggingPriority(.required, for: .horizontal) }
        // v12 (Marko 18.10.2026: "I don't need text checked two minutes ago ... reduce as much as possible size of this
        // banner by reducing spaces"): "checked … ago" and "failover … ago" are gone from the normal stripe; the status
        // place shows only when it has something to say (NO OTHER CONNECTION, a ping answer, a switch), the failover
        // place only in the red alert. Closer items, smaller margins.
        let row = NSStackView(views: [dot, gear, connButton, pipe(), speed, pipe(), ping, pipe(), data, checkedPipe, checked, failoverPipe, failover, ok])
        row.orientation = .horizontal
        row.spacing = 3
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        panel.setContentSize(NSSize(width: row.fittingSize.width, height: 30))

        panel.setFrameAutosaveName("ConnectionKeeperStripe")
        if !panel.setFrameUsingName("ConnectionKeeperStripe"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - 40))
        }
        keepOnScreen()
        panel.orderFrontRegardless()

        showData()
        showWebSpeed()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.autoData(); self?.newDay() }
        // At every start, behind the scenes (request 17): the data left, then the speed test, one after the other so
        // the two Firefoxes never share the 4G line's measurement.
        // v12 (Marko 18.10.2026: "you need to do all the tests ... Also ping as soon as application start ... three dots
        // inside parenthesis" for what is not tested yet): at once the ping, the data, then the speed; until each answers
        // its place says (...).
        testMark = "..."
        setSpeed(nil, nil)
        pingNow()
        checkData(visible: false) { [weak self] in self?.testSpeed(visible: false) }
        NotificationCenter.default.addObserver(forName: DataBalanceNote.checkNow, object: nil, queue: .main) { [weak self] _ in self?.checkDataByHand() }
    }

    // THE DATA BALANCE (v8): the last answer, "28.6 GB left · 11:57" (GB with one decimal, the time from Telemach's SMS);
    // amber below 10 GB, red below 2 GB.
    func showData() {
        if dataBusy || Date() < dataHeld { return }
        if let b = DataBalance.load() {
            data.title = b.line
            data.contentTintColor = red ? Ink.red : b.color
            data.toolTip = b.tip
        } else {
            data.title = "data ?"
            data.contentTintColor = red ? Ink.red : Ink.dim
            data.toolTip = "Click: ask Telemach how much data is left (sends STANJE to 13880 through the router, one SMS)."
        }
        fit()
    }

    // A click on the item, ⚙ → Check data, or the timer: the command runs behind the scenes, the stripe never waits.
    @objc func checkDataByHand() { checkData(visible: true) }

    func checkData(visible: Bool, then: (() -> Void)? = nil) {
        if dataBusy { then?(); return }
        dataBusy = true
        data.title = "(...) GB left"
        data.contentTintColor = Ink.amber
        fit()
        let t0 = Date()
        appendLog("\(logStamp()) DATA balance asked: router-sms balance (STANJE to 13880)\(visible ? " in front of him" : " behind the scenes")")
        DispatchQueue.global().async {
            let r = DataBalance.check(visible: visible)
            DispatchQueue.main.async {
                self.dataBusy = false
                let secs = Date().timeIntervalSince(t0)
                switch r {
                case .success(let b):
                    appendLog(String(format: "%@ DATA %.2f MB left of %.2f MB (used %.2f) at %@ (%.1f s from the click)",
                                     logStamp(), b.left_mb, b.total_mb, b.used_mb, b.at, secs))
                    self.showData()
                case .failure(let e):
                    appendLog("\(logStamp()) DATA balance FAILED: \(e.localizedDescription)")
                    self.dataHeld = Date().addingTimeInterval(30)
                    self.data.title = "data ✗"
                    self.data.contentTintColor = Ink.red
                    self.data.toolTip = e.localizedDescription
                    self.fit()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30.5) { self.showData() }
                }
                then?()
            }
        }
    }

    // THE SPEED TEST (v11): the last speedtest.net result beside the live speed; a click tests in front of him.
    // v12 (Marko 18.10.2026: "I don't need arrows ... Green number means download, red number means upload"): no
    // arrows, the download half green, the upload half red; all red in the failover alert as every other word.
    func setSpeed(_ down: Double?, _ up: Double?) {
        let dash = String(repeating: " ", count: max(0, rate(0).count - 1)) + "—"
        let d = "\(down.map(rate) ?? dash) \(testPart(lastTest?.down_mbps, mark: testMark))"
        let u = "\(up.map(rate) ?? dash) \(testPart(lastTest?.up_mbps, mark: testMark))"
        let t = NSMutableAttributedString(string: d, attributes: [.font: monoFont, .foregroundColor: red ? Ink.red : Ink.green])
        t.append(NSAttributedString(string: "  " + u, attributes: [.font: monoFont, .foregroundColor: Ink.red]))
        speed.attributedStringValue = t
    }

    func speedTip() -> String {
        "Internet only: the bytes through the router to the internet (the default route), per second. Traffic inside the local network is not counted.\n"
            + "Green: download, red: upload. In parentheses: the last speedtest.net result, \(SpeedUnit.current.isBits ? "Mbit/s" : "MB/s")"
            + (lastTest.map { String(format: " (%.2f ↓ %.2f ↑ Mbit/s, ping %.0f ms)", $0.down_mbps, $0.up_mbps, $0.ping_ms ?? 0) } ?? "")
            + ".\nClick: test on speedtest.net in a Firefox window you watch."
    }

    func showWebSpeed() {
        if webBusy || Date() < webHeld { return }
        testMark = nil
        lastTest = WebSpeed.load()
        speed.toolTip = speedTip()
    }

    @objc func testSpeedByHand() { testSpeed(visible: true) }

    func testSpeed(visible: Bool) {
        if webBusy { return }
        webBusy = true
        testMark = "..."
        appendLog("\(logStamp()) SPEEDTEST asked\(visible ? " in front of him" : " behind the scenes")")
        DispatchQueue.global().async {
            let r = WebSpeed.run(visible: visible)
            DispatchQueue.main.async {
                self.webBusy = false
                switch r {
                case .success: self.showWebSpeed()
                case .failure(let e):
                    appendLog("\(logStamp()) SPEEDTEST FAILED: \(e.localizedDescription)")
                    self.webHeld = Date().addingTimeInterval(30)
                    self.testMark = "✗"
                    self.speed.toolTip = "The speed test failed: \(e.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30.5) { self.showWebSpeed() }
                }
            }
        }
    }

    // "I need to have the values for this day": past midnight, both again behind the scenes (once: a failure waits
    // for the next start or a click, so a dead line never sends SMS after SMS).
    var dayTried = ""
    func newDay() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        if dayTried == "" { dayTried = today; return }          // the start already asked
        guard dayTried != today else { return }
        dayTried = today
        let needData = !isToday(DataBalance.load()?.checked), needSpeed = !isToday(WebSpeed.load()?.at)
        if needData { checkData(visible: false) { if needSpeed { self.testSpeed(visible: false) } } }
        else if needSpeed { testSpeed(visible: false) }
    }

    func autoData() {
        let h = DataAuto.hours
        guard h > 0, !dataBusy else { return }
        let last = (try? DataBalance.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if Date().timeIntervalSince(last) >= Double(h) * 3600 { checkData(visible: false) }
    }

    // On top: above ordinary and floating windows, on every Space, beside full-screen apps. Off: an ordinary window.
    func applyOnTop() {
        if OnTop.on {
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.orderFrontRegardless()
        } else {
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        }
    }

    func refresh() {
        reading()
        applyAlert()
        fit()
    }

    // THE RED (Marko, 14.10.2026): after the keeper failed over by itself, every word on the stripe is red
    // and the failover field says which connection died and when, until OK or until the Mac is back on it.
    func applyAlert() {
        var alert = FailoverAlert.load()
        if let a = alert, !a.simulated {
            let alive = state?.isFresh ?? false
            let current = alive ? state?.current : here
            if current == a.from, !alive || (state?.healthy ?? false) {
                FailoverAlert.clear(); alert = nil
                appendLog("\(logStamp()) ALERT cleared by the stripe: back on \"\(a.from)\"")
            }
        }
        guard let a = alert else {
            if red {
                red = false
                for b in [connButton, gear] { b.contentTintColor = Ink.text }
                if Date() >= pingHeld { ping.contentTintColor = Ink.yellow }
                speed.textColor = Ink.text; failover.textColor = Ink.text; failover.font = speed.font
                ok.isHidden = true
                showData()
                failoverWidth.constant = Stripe.failoverNormal
                fit()
                reading()
            }
            return
        }
        if !red {
            red = true
            ok.isHidden = false
            failoverWidth.constant = 260
            fit()
        }
        for b in [connButton, ping, data, gear] { b.contentTintColor = Ink.red }
        for l in [speed, checked, failover] { l.textColor = Ink.red }
        failover.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        failover.stringValue = a.line
        failover.toolTip = "\(a.from) stopped answering at \(a.at.formatted(date: .abbreviated, time: .shortened)); " +
            "the keeper moved to \(a.to) (\(a.how)). Check what is wrong with \(a.from). Press OK when you have seen it." +
            (a.simulated ? "  [test]" : "")
        dot.color = Ink.red
    }

    @objc func acknowledge() {
        guard let a = FailoverAlert.load() else { return }
        FailoverAlert.clear()
        appendLog("\(logStamp()) ALERT acknowledged on the stripe (OK): \(a.line)")
        applyAlert()
    }

    // The stripe keeps its left edge and takes the width its words need.
    func fit() {
        guard let row = panel.contentView?.subviews.first else { return }
        let t = checked.stringValue
        let quiet = t.isEmpty || t.hasPrefix("checked ") || t == "keeper not running"
        if checked.isHidden != quiet { checked.isHidden = quiet; checkedPipe.isHidden = quiet }
        if failover.isHidden == red { failover.isHidden = !red; failoverPipe.isHidden = !red }
        row.layoutSubtreeIfNeeded()
        if abs(row.fittingSize.width - panel.frame.width) < 1 { return }
        let origin = panel.frame.origin
        panel.setContentSize(NSSize(width: row.fittingSize.width, height: 30))
        panel.setFrameOrigin(origin)
        keepOnScreen()
    }

    // Never lost off the screens (14.10.2026 the saved place was x = -2247, on no display: the stripe was invisible).
    // At least 80 points of it stay on some screen, otherwise it goes to the top middle of the main screen.
    func keepOnScreen() {
        let f = panel.frame
        let visible = NSScreen.screens.contains { s in
            let i = s.visibleFrame.intersection(f)
            return !i.isNull && i.width >= min(80, f.width) && i.height >= f.height / 2
        }
        if visible { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.midX - f.width / 2, y: v.maxY - 40))
        appendLog("\(logStamp()) stripe was off every screen (x \(Int(f.minX)), y \(Int(f.minY))); brought back to \(screen.localizedName)")
    }

    func reading() {
        if tick % 5 == 0 {
            let now = Net.defaultRouteInterface()
            if now != iface { iface = now; lastCounters = nil }
            if !(state?.isFresh ?? false) { here = currentNow() }
        }
        tick += 1

        // INTERNET speed only (v10): the bytes of the default route through the router, sampled every second off the
        // main thread. Traffic inside the house (the phone, the router's page, AirPlay) is not counted.
        if let iface, !sampling {
            sampling = true
            DispatchQueue.global().async {
                let c = Traffic.internet(iface)
                DispatchQueue.main.async {
                    self.sampling = false
                    guard let c else { self.setSpeed(nil, nil); self.lastCounters = nil; return }
                    let dt = Date().timeIntervalSince(self.lastSample)
                    if let last = self.lastCounters, dt > 0 {
                        // a route made again (network change) starts its counters at 0: show nothing for that second
                        let down = c.rx >= last.rx ? Double(c.rx - last.rx) / dt : 0
                        let up = c.tx >= last.tx ? Double(c.tx - last.tx) / dt : 0
                        self.setSpeed(down, up)
                    }
                    self.lastCounters = c
                    self.lastSample = Date()
                }
            }
        } else if iface == nil {
            setSpeed(nil, nil)
        }

        state = KeeperState.load()
        let alive = state?.isFresh ?? false
        let cfg = Config.load()
        let current = alive ? state?.current : here
        connButton.title = (current ?? "no network") + " ▾"
        if !red && !noOther { connButton.contentTintColor = iface == nil ? Ink.dim : isWiFi(iface) ? Ink.green : Ink.yellow }

        if Date() < pingHeld { return }            // a pressed ping's answer is being shown

        if let s = state, alive {
            let check = s.lastCheck
            ping.title = check?.latencyMs.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
            // NO OTHER CONNECTION (Marko, 14.10.2026): the connection is dead and none in the list works.
            // Red and bold on the status line until a connection works again; he has to do something.
            let none = s.phase.hasPrefix(noOtherPrefix)
            if none != noOther {
                noOther = none
                checkedWidth.constant = none ? 520 : Stripe.checkedNormal
                checked.font = .monospacedDigitSystemFont(ofSize: 12, weight: none ? .bold : .regular)
                if !none { checked.toolTip = nil }
                if !red { connButton.contentTintColor = none ? Ink.red : Ink.text }
                fit()
            }
            if none {
                checked.stringValue = s.phase
                checked.textColor = Ink.red
                checked.toolTip = "The connection in use is dead and no other connection in the list works. The keeper keeps trying; check the access points."
            } else if s.phase == "ok" || s.phase == "checking" {
                checked.stringValue = "checked \(ago(check?.at)) \(check?.online == false ? "✗" : "✓")"
                checked.textColor = check?.online == false ? Ink.red : Ink.text
            } else {
                checked.stringValue = s.phase
                checked.textColor = Ink.amber
            }
            failover.stringValue = s.lastFailover == nil ? "no failover" : "failover \(ago(s.lastFailover))"
            failover.toolTip = s.lastFailover == nil ? nil : "\(s.lastFailoverFrom ?? "?") → \(s.lastFailoverTo ?? "?")"
            dot.color = none ? Ink.red : !s.healthy ? (check?.online == false ? Ink.red : Ink.amber) : (s.dryRun || cfg.dryRun ? Ink.amber : Ink.green)
            dot.toolTip = s.dryRun ? "keeper running in dry run: it only logs" : "keeper running, pid \(s.pid)"
        } else {
            ping.title = "ping —"
            checked.stringValue = "keeper not running"
            checked.textColor = Ink.dim
            failover.stringValue = state?.lastFailover == nil ? "no failover" : "failover \(ago(state?.lastFailover))"
            dot.color = Ink.grey
            dot.toolTip = "the keeper (LaunchAgent \(CKAgentLabel)) is not running"
        }
    }

    // The connection's name gets the width of the longest name in the list, so a switch does not move the rest.
    func connectionWidth() -> CGFloat {
        let f = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let names = Config.load().connections.map { $0.name } + ["no network"]
        return (names.map { textWidth($0 + " ▾", f) }.max() ?? 80) + 8
    }

    func currentNow() -> String? {
        guard let i = iface else { return nil }
        return Net.displayName(i)
    }

    // v12 LIVE (Marko 18.10.2026: "offer only the one which is online now. Offline doesn't make sense to offer"): the
    // drop-down opens with "checking…" and fills itself while open: every device with an address is pinged through
    // itself (online ✓ and its ms, or left out); the Wi-Fi networks of the list are offered only when in range now.
    // A Wi-Fi not joined cannot be pinged before joining, so "in range" is the most that can be known of it.
    @objc func showConnections() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let waiting = NSMenuItem(title: "checking the connections…", action: nil, keyEquivalent: "")
        waiting.isEnabled = false
        menu.addItem(waiting)
        let cfg = Config.load()
        DispatchQueue.global().async {
            let wifi = Net.wifiInterface()
            var online: [(name: String, ms: Double, wifi: Bool)] = []
            for i in Net.activeInterfaces() {
                if let ms = Net.onlineVia(i, host: cfg.pingHost) { online.append((Net.displayName(i), ms, i == wifi)) }
            }
            let near = Net.wifiInRange()
            let joinable = cfg.connections.filter { $0.enabled && $0.kind == "wifi" && near.contains($0.name) && !online.contains { o in o.name == $0.name } }
            RunLoop.main.perform(inModes: [.common]) {
                var at = menu.index(of: waiting)
                menu.removeItem(waiting)
                for o in online {
                    let item = NSMenuItem(title: String(format: "%@   online ✓ %.0f ms", o.name, o.ms), action: nil, keyEquivalent: "")
                    item.state = .on
                    item.isEnabled = false
                    item.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: o.wifi ? Ink.green : Ink.yellow, .font: NSFont.menuFont(ofSize: 0)])
                    menu.insertItem(item, at: at); at += 1
                }
                for c in joinable {
                    let item = NSMenuItem(title: "\(c.name)   in range, switch to it", action: #selector(self.pick(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = c.name
                    menu.insertItem(item, at: at); at += 1
                }
                if online.isEmpty && joinable.isEmpty {
                    let none = NSMenuItem(title: "no connection online", action: nil, keyEquivalent: "")
                    none.isEnabled = false
                    menu.insertItem(none, at: at)
                }
                menu.update()
            }
        }
        menu.addItem(.separator())
        let check = NSMenuItem(title: "Check now", action: #selector(checkNow), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let log = NSMenuItem(title: "Open the log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit the stripe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: connButton.bounds.height + 4), in: connButton)
    }

    // THE MANUAL SWITCH (v5, Marko 14.10.2026: "I click on mantra, and then nothing is happening. It's not
    // switching immediately."). The stripe joins at once itself, keeper or not, holds the keeper's checks
    // meanwhile, and says on the status line what is happening and how it ended. A switch by hand never turns
    // the stripe red. Joining goes the road in Join.swift (networksetup, the stored password, Control Centre).
    @objc func pick(_ item: NSMenuItem) {
        guard let name = item.representedObject as? String else { return }
        if Config.load().dryRun { show("dry run: would join \(name)", Ink.amber, for: 20); return }
        let iface = Net.wifiInterface() ?? "en0"
        show("switching to \(name)…", Ink.amber, for: 180)
        dot.color = Ink.amber
        appendLog("\(logStamp()) MANUAL switch to \"\(name)\" from the stripe: joining now")
        Speed.hold(true)
        DispatchQueue.global().async {
            let r = Join.wifi(name, iface) { msg in DispatchQueue.main.async { self.show(msg, Ink.amber, for: 180) } }
            Speed.hold(false)
            appendLog("\(logStamp()) MANUAL switch to \"\(name)\" " + (r.ok ? "done: \(r.detail)" : "FAILED: \(r.detail)"))
            DispatchQueue.main.async {
                let at = Date().formatted(date: .omitted, time: .shortened)
                if r.ok {
                    self.show("on \(name) ✓  \(at)", Ink.green, for: 20)
                    self.dot.color = Ink.green
                } else {
                    let why = r.detail.contains("Could not find network") ? "not in range"
                        : r.detail.contains("no password stored") ? "needs its password (⚙) or Accessibility"
                        : "see the log"
                    self.show("✗ \(name): \(why)  \(at)", Ink.red, for: 30, tip: r.detail)
                    self.dot.color = Ink.red
                }
                if self.state?.isFresh ?? false { KeeperCommand(action: "check").send() }
            }
        }
    }

    // A message that stands on the status line for a while (the usual reading waits until then).
    func show(_ text: String, _ color: NSColor, for seconds: Double, tip: String? = nil) {
        pingHeld = Date().addingTimeInterval(seconds)
        if !noOther { checkedWidth.constant = 380; fit() }
        checked.stringValue = text
        checked.textColor = color
        checked.toolTip = tip
        if seconds < 60 {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) {
                if Date() >= self.pingHeld {
                    self.checked.toolTip = nil
                    if !self.noOther { self.checkedWidth.constant = Stripe.checkedNormal; self.fit() }
                    self.refresh()
                }
            }
        }
    }

    @objc func checkNow() {
        if state?.isFresh ?? false { KeeperCommand(action: "check").send(); return }
        checked.stringValue = "checking…"
        let cfg = Config.load()
        DispatchQueue.global().async {
            let p = Net.probe(pingHost: cfg.pingHost, httpURL: cfg.httpProbe)
            DispatchQueue.main.async {
                switch p {
                case .online(_, let ms): self.checked.stringValue = "online now ✓"; self.ping.title = ms.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
                case .captive: self.checked.stringValue = "captive portal ✗"
                case .offline: self.checked.stringValue = "offline now ✗"
                }
            }
        }
    }

    // THE PING BUTTON (Marko, 13.10.2026: "I want to press the ping and then it pings and tells me if my
    // connection is alive or not ... exactly on the status line"). The stripe pings by itself, keeper or
    // not, and the answer stands on the stripe for 20 s before the usual reading comes back.
    @objc func pingNow() {
        let cfg = Config.load()
        pingHeld = Date().addingTimeInterval(60)
        ping.title = "ping (...)"
        ping.contentTintColor = Ink.yellow
        checked.stringValue = "pinging \(cfg.pingHost)…"
        checked.textColor = Ink.amber
        dot.color = Ink.amber
        applyAlert()
        DispatchQueue.global().async {
            let p = Net.probe(pingHost: cfg.pingHost, httpURL: cfg.httpProbe)
            DispatchQueue.main.async {
                let at = Date().formatted(date: .omitted, time: .standard)
                switch p {
                case .online(_, let ms):
                    self.ping.title = ms.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
                    self.checked.stringValue = ms != nil ? "ALIVE ✓  \(at)" : "ALIVE ✓  web only (ping blocked)"
                    self.ping.contentTintColor = Ink.yellow; self.checked.textColor = Ink.green; self.dot.color = Ink.green
                case .captive:
                    self.ping.title = "ping ✗"
                    self.checked.stringValue = "NOT ALIVE ✗  captive portal  \(at)"
                    self.ping.contentTintColor = Ink.red; self.checked.textColor = Ink.red; self.dot.color = Ink.red
                case .offline:
                    self.ping.title = "ping ✗"
                    self.checked.stringValue = "NOT ALIVE ✗  no answer  \(at)"
                    self.ping.contentTintColor = Ink.red; self.checked.textColor = Ink.red; self.dot.color = Ink.red
                }
                self.pingHeld = Date().addingTimeInterval(20)
                self.applyAlert()
                DispatchQueue.main.asyncAfter(deadline: .now() + 20.5) {
                    if Date() >= self.pingHeld { self.ping.contentTintColor = Ink.yellow; self.refresh() }
                }
            }
        }
    }

    @objc func openLog() { NSWorkspace.shared.open(Paths.log) }

    @objc func openSettings() {
        if settings == nil { settings = SettingsWindow() }
        settings?.show()
    }
}

// `--check-join`: can this app reach Control Centre's Wi-Fi list (Accessibility granted)? Reads it, presses nothing.
if CommandLine.arguments.contains("--check-join") {
    let r = ControlCenterWifi.list()
    let line = "\(logStamp()) CHECK join path: accessibility \(AXIsProcessTrusted() ? "granted" : "NOT granted"); Control Centre Wi-Fi list " +
        (r.ok ? "read: \(r.networks.joined(separator: ", "))" : "not read: \(r.detail)") +
        "; stored passwords: " + Config.load().connections.map { "\($0.name) \(WifiPassword.has($0.name) ? "yes" : "no")" }.joined(separator: ", ")
    print(line); appendLog(line)
    exit(r.ok ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let stripe = Stripe()
if CommandLine.arguments.contains("--settings") { stripe.openSettings() }
if CommandLine.arguments.contains("--check-data") { stripe.checkDataByHand() }    // v8: the same as a click on the data item
app.run()
