// ONE LINE PER CONNECTION (v13, Marko 18.10.2026, request 27: "I have two status lines for each individual connection,
// and at the bottom ... a third line which is status of the aggregation with speeds and everything ... if we have
// multiple, even more than two, then there are more lines"). The first row is the stripe as it was (the connection
// carrying the internet, ⚙, ping, data). Under it a row for every other device with an address and a router: its own
// live speed (its own default route), its ping through itself, whether it is joined. The last row is the aggregation:
// the lines joined, their speeds added, the connections the server holds, the last joined test.
//
// THE DROP-DOWN SELECTS (request 28: "he can select multiple connections or deselect them. If he deselects everything,
// then it means we are exiting aggregation mode"): a JOIN section of tick boxes, one per connection online now; the
// menu stays open while ticking. Any tick: aggregation on (macOS's SOCKS proxy → the server). None: off.
import AppKit

struct OtherLine {
    let iface: String, name: String, wifi: Bool, ms: Double?, sameAs: String?
}

final class LineRow {
    let view: NSStackView
    let dot = Dot()
    let lead = NSView()
    let name: NSTextField
    let speed = label(textWidth(speedSample(), monoFont), font: monoFont)
    let ping = label(textWidth("ping 999 ms", monoFont), font: monoFont)
    let info = label(textWidth("8 lines · 888 conn · 8.8× best, up 8.8×", monoFont), font: monoFont)
    var lastBytes: (rx: UInt64, tx: UInt64)?

    init(leadWidth: CGFloat, nameWidth: CGFloat) {
        name = label(nameWidth, font: .systemFont(ofSize: 12, weight: .semibold))
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 12).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 12).isActive = true
        lead.translatesAutoresizingMaskIntoConstraints = false
        lead.widthAnchor.constraint(equalToConstant: leadWidth).isActive = true
        speed.lineBreakMode = .byClipping
        speed.maximumNumberOfLines = 1
        speed.cell?.wraps = false
        ping.textColor = Ink.yellow
        info.textColor = Ink.dim
        view = NSStackView(views: [dot, lead, name, linePipe(), speed, linePipe(), ping, linePipe(), info])
        view.orientation = .horizontal
        view.spacing = 3
        view.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    // Download green, upload red, each with a test in parentheses, as on the first row.
    func setSpeed(_ down: Double?, _ up: Double?, test: (Double, Double?)?, dim: Bool = false, mark: String? = nil) {
        let dash = String(repeating: " ", count: max(0, rate(0).count - 1)) + "—"
        let d = "\(down.map(rate) ?? dash) \(testPart(test?.0, mark: mark))"
        let u = "\(up.map(rate) ?? dash) \(test?.1 == nil && mark == nil ? "       " : testPart(test?.1, mark: mark))"
        let t = NSMutableAttributedString(string: d, attributes: [.font: monoFont, .foregroundColor: dim ? Ink.grey : Ink.green])
        t.append(NSAttributedString(string: "  " + u, attributes: [.font: monoFont, .foregroundColor: dim ? Ink.grey : Ink.red]))
        speed.attributedStringValue = t
    }
}

func linePipe() -> NSTextField {
    let p = NSTextField(labelWithString: "|")
    p.textColor = Ink.grey
    p.font = .systemFont(ofSize: 12)
    p.setContentHuggingPriority(.required, for: .horizontal)
    return p
}

extension Stripe {
    // Every 5 s, off the main thread: the other devices, their ping, the server's word.
    func scanLines() {
        if scanning { return }
        scanning = true
        let main = iface
        DispatchQueue.global().async {
            let st = Aggregation.status()
            let wifi = Net.wifiInterface()
            var found: [OtherLine] = []
            for i in Net.activeInterfaces() where i != main {
                let gw = shell("/usr/sbin/ipconfig", ["getoption", i, "router"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
                if gw.isEmpty { continue }
                found.append(OtherLine(iface: i, name: Net.displayName(i), wifi: i == wifi, ms: Net.onlineVia(i),
                                       sameAs: st?.ignored.first { $0.device == i }?.sameLineAs))
            }
            DispatchQueue.main.async {
                self.scanning = false
                self.others = found
                self.agg = st
                self.watchServer(st)
                self.layoutLines()
            }
        }
    }

    // On, and the server has not answered for 15 s: macOS's proxy off at once, or every page would hang; the agent is
    // kicked to start again, and the proxy comes back on when the server answers.
    func watchServer(_ st: AggStatus?) {
        guard Aggregation.on else { serverMisses = 0; return }
        if st == nil {
            serverMisses += 1
            if serverMisses == 3 {
                proxyDropped = true
                appendLog("\(logStamp()) AGGREGATION server does not answer on :\(aggPort): macOS's proxy off, the server restarted")
                DispatchQueue.global().async {
                    Aggregation.systemProxy(false)
                    shell("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(CKAggregateLabel)"])
                }
            }
        } else {
            serverMisses = 0
            if proxyDropped {
                proxyDropped = false
                appendLog("\(logStamp()) AGGREGATION server answers again: macOS's proxy on")
                DispatchQueue.global().async { Aggregation.systemProxy(true) }
            }
        }
    }

    func layoutLines() {
        guard let column = panel.contentView?.subviews.first as? NSStackView else { return }
        let lead = gear.fittingSize.width + 3, nameW = connWidth.constant
        var changed = false
        for o in others where lineRows[o.iface] == nil {
            let r = LineRow(leadWidth: lead, nameWidth: nameW)
            r.name.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(showConnections)))
            r.speed.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(testRowSpeed(_:))))
            lineRows[o.iface] = r
            column.insertArrangedSubview(r.view, at: column.arrangedSubviews.count - 1)
            changed = true
        }
        for (dev, r) in lineRows where !others.contains(where: { $0.iface == dev }) {
            column.removeArrangedSubview(r.view); r.view.removeFromSuperview(); lineRows[dev] = nil
            changed = true
        }
        let joined = Set(agg?.lines.map(\.device) ?? [])
        let tests = WebSpeedByConnection.all(), aggTest = AggTest.load()
        for o in others {
            guard let r = lineRows[o.iface] else { continue }
            let ok = o.ms != nil
            r.name.stringValue = o.name
            r.name.textColor = !ok ? Ink.grey : o.wifi ? Ink.green : Ink.yellow
            r.dot.color = !ok ? Ink.grey : Aggregation.on && joined.contains(o.iface) ? Ink.green : Ink.dim
            r.ping.stringValue = o.ms.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
            r.ping.textColor = ok ? Ink.yellow : Ink.grey
            let line = agg?.lines.first { $0.device == o.iface }
            r.info.stringValue = o.sameAs.map { "same line as \($0): not joined" }
                ?? (Aggregation.on && line != nil ? String(format: "joined · %d conn · %.0f MB", line!.active, line!.mbDown + line!.mbUp)
                    : ok ? "not joined" : "no internet")
            r.speed.toolTip = "Its own live speed (its default route); in parentheses its last test alone, down and up.\nClick: test this line now (Cloudflare, about 6 s each way)."
            if r.lastBytes == nil { r.setSpeed(nil, nil, test: lineTest(o.name, tests, aggTest), dim: !ok, mark: lineTesting.contains(o.name) ? "..." : nil) }
        }
        // The aggregation row: always the last.
        guard let a = aggRow else { return }
        a.name.stringValue = "JOINED"
        if !Aggregation.on {
            a.dot.color = Ink.grey; a.name.textColor = Ink.grey
            a.info.stringValue = "aggregation off: tick connections in ▾"; a.info.textColor = Ink.dim
            a.ping.stringValue = ""
        } else if let st = agg {
            let alive = st.lines.filter(\.alive)
            a.dot.color = alive.count >= 2 ? Ink.green : Ink.amber
            a.name.textColor = alive.count >= 2 ? Ink.green : Ink.amber
            a.ping.stringValue = "\(alive.count) of \(st.lines.count) up"
            a.ping.textColor = alive.count == st.lines.count ? Ink.yellow : Ink.amber
            let conn = st.lines.reduce(0) { $0 + $1.active }
            // v13 (request 30, the end was cut): the names are on the rows above; here only the numbers
            var words = "\(st.lines.count) lines · \(conn) conn"
            let names = Set(st.lines.map(\.name))
            if let t = aggTest, let best = t.alone.filter({ names.contains($0.key) }).values.max(), best > 0 {
                words += String(format: " · %.1f× best", t.joined / best)
                if let up = t.joinedUp, let bestUp = t.aloneUp?.filter({ names.contains($0.key) }).values.max(), bestUp > 0 { words += String(format: ", up %.1f×", up / bestUp) }
            }
            a.info.stringValue = words; a.info.textColor = Ink.text
        } else {
            a.dot.color = Ink.red; a.name.textColor = Ink.red
            a.ping.stringValue = ""
            a.info.stringValue = proxyDropped ? "server down: macOS's proxy off, restarting" : "server not answering on :\(aggPort)"
            a.info.textColor = Ink.red
        }
        a.info.toolTip = "The aggregation server ck-aggregate on 127.0.0.1:\(aggPort): every new connection goes out through one of the joined lines, the faster one getting more. One single download stays on one line."
        if changed { fit() }
    }

    func lineTest(_ name: String, _ tests: [String: WebSpeed], _ aggTest: AggTest?) -> (Double, Double?)? {
        if let a = aggTest?.alone[name] { return (a, aggTest?.aloneUp?[name]) }
        if let w = tests[name] { return (w.down_mbps, w.up_mbps) }
        return nil
    }

    // Every second, from the one nettop reading of the first row: the other rows' live speeds and their sum.
    func sampleLines(_ all: [String: (rx: UInt64, tx: UInt64)], dt: Double) {
        let tests = WebSpeedByConnection.all(), aggTest = AggTest.load()
        let joined = Set(agg?.lines.map(\.device) ?? [])
        var sumDown = 0.0, sumUp = 0.0
        func rates(_ last: (rx: UInt64, tx: UInt64)?, _ c: (rx: UInt64, tx: UInt64)?) -> (Double, Double)? {
            guard let last, let c, dt > 0 else { return nil }
            return (c.rx >= last.rx ? Double(c.rx - last.rx) / dt : 0, c.tx >= last.tx ? Double(c.tx - last.tx) / dt : 0)
        }
        for o in others {
            guard let r = lineRows[o.iface] else { continue }
            let c = all[o.iface]
            let v = rates(r.lastBytes, c)
            r.lastBytes = c
            r.setSpeed(v?.0, v?.1, test: lineTest(o.name, tests, aggTest), dim: o.ms == nil, mark: lineTesting.contains(o.name) ? "..." : nil)
            if joined.contains(o.iface), let v { sumDown += v.0; sumUp += v.1 }
        }
        if let i = iface, joined.contains(i), let v = rates(aggMainLast, all[i]) { sumDown += v.0; sumUp += v.1 }
        if let i = iface { aggMainLast = all[i] }
        let on = Aggregation.on && agg != nil
        aggRow.setSpeed(on ? sumDown : nil, on ? sumUp : nil, test: aggTest.map { ($0.joined, $0.joinedUp) }, dim: !on,
                        mark: lineTesting.contains("JOINED") ? "..." : nil)
    }

    // A CLICK ON A ROW'S SPEED (request 30: "the same clicking applies to combinations so I can compare"): that line
    // alone, down and up, behind the scenes; on JOINED every line alone and then all of them through the server. The
    // first row keeps its speedtest.net test in Firefox. "(...)" while it runs, the numbers in parentheses after.
    @objc func testRowSpeed(_ g: NSClickGestureRecognizer) {
        let name: String
        if g.view === aggRow.speed { name = "JOINED" }
        else if let o = others.first(where: { lineRows[$0.iface]?.speed === g.view }), o.sameAs == nil { name = o.name }
        else { return }
        if !lineTesting.isEmpty { return }                  // one test at a time: two would share the lines
        lineTesting.insert(name)
        appendLog("\(logStamp()) LINE TEST asked on the stripe: \(name == "JOINED" ? "every line alone, then joined" : name + " alone")")
        let bin = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ck-aggregate").path
        DispatchQueue.global().async {
            let r = shell(bin, name == "JOINED" ? ["test", "6"] : ["test-line", name, "6"], timeout: 120)
            DispatchQueue.main.async {
                self.lineTesting.remove(name)
                appendLog("\(logStamp()) LINE TEST \(name): " + r.out.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "; "))
                self.layoutLines()
            }
        }
    }

    // THE JOIN TICKS (request 28). Rows are views, so a tick does not close the menu.
    func addJoinSection(_ menu: NSMenu) {
        var names: [(String, Bool)] = []
        if let i = iface { names.append((Net.displayName(i), true)) }
        for o in others where !names.contains(where: { $0.0 == o.name }) { names.append((o.name, o.ms != nil)) }
        menu.addItem(.separator())
        let head = NSMenuItem(title: "JOIN (aggregation): tick the connections, none = off", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        let ticked = Set(Aggregation.selected)
        for (name, ok) in names {
            let same = others.first { $0.name == name }?.sameAs
            let b = NSButton(checkboxWithTitle: name + (same.map { "   (same line as \($0), ignored)" } ?? ""), target: self, action: #selector(toggleJoin(_:)))
            b.state = ticked.contains(name) ? .on : .off
            b.isEnabled = ok
            b.identifier = NSUserInterfaceItemIdentifier(name)
            b.font = .menuFont(ofSize: 0)
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 24))
            b.frame = NSRect(x: 20, y: 2, width: 430, height: 20)
            v.addSubview(b)
            let item = NSMenuItem()
            item.view = v
            menu.addItem(item)
        }
    }

    @objc func toggleJoin(_ b: NSButton) {
        guard let name = b.identifier?.rawValue else { return }
        let was = Aggregation.on
        var s = Aggregation.selected.filter { $0 != name }
        if b.state == .on { s.append(name) }
        Aggregation.selected = s
        let now = Aggregation.on
        appendLog("\(logStamp()) AGGREGATION ticks: \(s.isEmpty ? "none, aggregation off" : s.joined(separator: " + "))")
        if was != now {
            proxyDropped = false; serverMisses = 0
            DispatchQueue.global().async {
                if now { shell("/bin/launchctl", ["kickstart", "gui/\(getuid())/\(CKAggregateLabel)"]) }
                let said = Aggregation.systemProxy(now)
                appendLog("\(logStamp()) AGGREGATION \(now ? "on" : "off"): " + said.joined(separator: "; "))
            }
        }
        layoutLines()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.scanLines() }
    }
}
