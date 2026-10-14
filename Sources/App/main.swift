// Connection Keeper (Mantra): one floating stripe that shows the connection, its speed and the
// keeper's last word, with a drop-down to switch by hand and a gear for the list of connections.
import AppKit

let appName = "Connection Keeper (Mantra)"

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

func label(_ width: CGFloat, align: NSTextAlignment = .left) -> NSTextField {
    let l = NSTextField(labelWithString: "")
    l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    l.textColor = Ink.text
    l.alignment = align
    l.lineBreakMode = .byTruncatingTail
    l.translatesAutoresizingMaskIntoConstraints = false
    l.widthAnchor.constraint(equalToConstant: width).isActive = true
    return l
}

func rate(_ bytesPerSecond: Double) -> String {
    let b = max(0, bytesPerSecond)
    if b >= 1_000_000 { return String(format: "%.1f MB/s", b / 1_000_000) }
    if b >= 1_000 { return String(format: "%.0f kB/s", b / 1_000) }
    return String(format: "%.0f B/s", b)
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
    let speed = label(165)
    let ping = NSButton(title: "ping —", target: nil, action: nil)
    let checked = label(190)
    let failover = label(130)
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
        connButton.widthAnchor.constraint(equalToConstant: 130).isActive = true
        connButton.toolTip = "Switch the connection"
        ping.isBordered = false
        ping.target = self
        ping.action = #selector(pingNow)
        ping.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ping.contentTintColor = Ink.text
        ping.alignment = .left
        ping.translatesAutoresizingMaskIntoConstraints = false
        ping.widthAnchor.constraint(equalToConstant: 76).isActive = true
        ping.toolTip = "Press: ping now and say on the stripe whether the internet is alive"
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

        let row = NSStackView(views: [dot, connButton, speed, ping, checked, failover, ok, gear])
        row.orientation = .horizontal
        row.spacing = 10
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
        panel.orderFrontRegardless()

        refresh()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        reading()
        applyAlert()
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
                failoverWidth.constant = 130
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
        for b in [connButton, ping, gear] { b.contentTintColor = Ink.red }
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
        let origin = panel.frame.origin
        panel.setContentSize(NSSize(width: row.fittingSize.width, height: 30))
        panel.setFrameOrigin(origin)
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
                speed.stringValue = "↓ \(rate(down))   ↑ \(rate(up))"
            }
            lastCounters = c
            lastSample = Date()
        } else {
            speed.stringValue = "↓ —   ↑ —"
        }

        state = KeeperState.load()
        let alive = state?.isFresh ?? false
        let cfg = Config.load()
        let current = alive ? state?.current : here
        connButton.title = (current ?? "no network") + " ▾"

        if Date() < pingHeld { return }            // a pressed ping's answer is being shown

        if let s = state, alive {
            let check = s.lastCheck
            ping.title = check?.latencyMs.map { String(format: "ping %.0f ms", $0) } ?? "ping —"
            // NO OTHER CONNECTION (Marko, 14.10.2026): the connection is dead and none in the list works.
            // Red and bold on the status line until a connection works again; he has to do something.
            let none = s.phase.hasPrefix(noOtherPrefix)
            if none != noOther {
                noOther = none
                checkedWidth.constant = none ? 520 : 190
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
                    if !self.noOther { self.checkedWidth.constant = 190; self.fit() }
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
                case .online(_, let ms): self.checked.stringValue = "online now ✓"; self.ping.title = ms.map { String(format: "ping %.0f ms", $0) } ?? "ping —"
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
                    self.ping.title = ms.map { String(format: "ping %.0f ms", $0) } ?? "ping —"
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let stripe = Stripe()
if CommandLine.arguments.contains("--settings") { stripe.openSettings() }
app.run()
