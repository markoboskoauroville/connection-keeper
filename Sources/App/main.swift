// Connection Keeper (Mantra): one floating stripe that shows the connection, its speed and the
// keeper's last word, with a drop-down to switch by hand and a gear for the list of connections.
import AppKit

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
    return "↓ \(n)  ↑ \(n)"
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
    var dataHeld = Date.distantPast             // a failed check's words stay until then
    let checked = label(Stripe.checkedNormal)
    let failover = label(Stripe.failoverNormal)
    static let checkedNormal = textWidth("checked 59 min ago ✓", .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
    static let failoverNormal = textWidth("failover 59 min ago", .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
    let ok = NSButton(title: "OK", target: nil, action: nil)
    let gear = NSButton(title: "⚙", target: nil, action: nil)
    var failoverWidth: NSLayoutConstraint!
    var checkedWidth: NSLayoutConstraint!
    var noOther = false                         // the keeper says NO OTHER CONNECTION: the status is red
    var red = false                             // the failover alert is on: every word is red

    var iface: String?
    var lastCounters: (rx: UInt32, tx: UInt32)?
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
        ping.contentTintColor = Ink.text
        ping.alignment = .left
        ping.translatesAutoresizingMaskIntoConstraints = false
        ping.toolTip = "Press: ping now and say on the stripe whether the internet is alive"
        data.isBordered = false
        data.target = self
        data.action = #selector(checkData)
        data.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        data.contentTintColor = Ink.text
        data.alignment = .left
        data.translatesAutoresizingMaskIntoConstraints = false
        data.setContentHuggingPriority(.required, for: .horizontal)
        _ = fixWidth(data, max(textWidth("888.8 GB left · 88:88", monoFont), textWidth("checking data…", monoFont)))
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
        for b in [connButton, ping, gear] { b.setContentHuggingPriority(.required, for: .horizontal) }
        let row = NSStackView(views: [dot, gear, connButton, pipe(), speed, pipe(), ping, pipe(), data, pipe(), checked, pipe(), failover, ok])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
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
        refresh()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.autoData() }
        NotificationCenter.default.addObserver(forName: DataBalanceNote.checkNow, object: nil, queue: .main) { [weak self] _ in self?.checkData() }
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
    @objc func checkData() {
        if dataBusy { return }
        dataBusy = true
        data.title = "checking data…"
        data.contentTintColor = Ink.amber
        fit()
        let t0 = Date()
        appendLog("\(logStamp()) DATA balance asked: router-sms balance (STANJE to 13880)")
        DispatchQueue.global().async {
            let r = DataBalance.check()
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
            }
        }
    }

    func autoData() {
        let h = DataAuto.hours
        guard h > 0, !dataBusy else { return }
        let last = (try? DataBalance.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if Date().timeIntervalSince(last) >= Double(h) * 3600 { checkData() }
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
                if Date() >= pingHeld { ping.contentTintColor = Ink.text }
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

        // Speed of the interface that carries the default route, sampled every second.
        if let iface, let c = Traffic.counters(iface) {
            let dt = Date().timeIntervalSince(lastSample)
            if let last = lastCounters, dt > 0 {
                let down = Double(c.rx &- last.rx) / dt, up = Double(c.tx &- last.tx) / dt
                speed.stringValue = "↓ \(rate(down))  ↑ \(rate(up))"
            }
            lastCounters = c
            lastSample = Date()
        } else {
            speed.stringValue = "↓     —        ↑     —"
        }

        state = KeeperState.load()
        let alive = state?.isFresh ?? false
        let cfg = Config.load()
        let current = alive ? state?.current : here
        connButton.title = (current ?? "no network") + " ▾"

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
        if i == Net.wifiInterface() { return Net.currentSSID(i) }
        return i
    }

    @objc func showConnections() {
        let menu = NSMenu()
        let current = (state?.isFresh ?? false) ? state?.current : here
        for c in Config.load().connections {
            let item = NSMenuItem(title: "\(c.name)\(c.kind == "wifi" ? "" : "  (\(c.kind))")", action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.name
            item.state = c.name == current ? .on : .off
            item.isEnabled = c.enabled && c.kind == "wifi"
            menu.addItem(item)
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
        ping.title = "pinging…"
        ping.contentTintColor = Ink.amber
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
                    self.ping.contentTintColor = Ink.green; self.checked.textColor = Ink.green; self.dot.color = Ink.green
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
                    if Date() >= self.pingHeld { self.ping.contentTintColor = Ink.text; self.refresh() }
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
if CommandLine.arguments.contains("--check-data") { stripe.checkData() }    // v8: the same as a click on the data item
app.run()
