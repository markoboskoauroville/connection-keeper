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
    let info = label(textWidth("8 lines · 888 conn · 88.8× best, up 88.8×  ", monoFont), font: monoFont)
    var lastBytes: (rx: UInt64, tx: UInt64)?
    var lastAt: Date?, lastRate: (Double, Double)?      // a phone row: when the server's counters were read, the rate

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
        let u = "\(up.map(rate) ?? dash) \(test?.1 == nil && mark == nil ? "      " : testPart(test?.1, mark: mark))"
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
            // v23: aggregating, the one line is AGGREGATE CONNECTION, so the line under it needs its own row too
            // v24: the line carrying the internet has its row too (the opened list shows what is connected now)
            for i in Net.activeInterfaces() {
                let gw = shell("/usr/sbin/ipconfig", ["getoption", i, "router"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
                if gw.isEmpty { continue }
                found.append(OtherLine(iface: i, name: Net.displayName(i), wifi: i == wifi, ms: Net.onlineVia(i),
                                       sameAs: st?.ignored.first { $0.device == i }?.sameLineAs))
            }
            // v17 (request 36): a phone on a USB cable, its line over adb (its server started here if need be)
            for p in Phones.list() {
                if let note = Phones.ensure(p) { appendLog("\(logStamp()) PHONE \(p.name): \(note)") }
                found.append(OtherLine(iface: p.device, name: p.name, wifi: false, ms: Phones.online(p), sameAs: nil))
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
        guard Aggregation.on, !Aggregation.tunnelInstalled else { serverMisses = 0; return }   // the helper watches it itself
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
        let lead = gear.fittingSize.width + rescan.fittingSize.width + expand.fittingSize.width + 9, nameW = connectionWidth()
        var changed = false
        rememberLines()
        // v24 (request 42: "just show what is actually right now connected, and that's all"): only the green lines,
        // the joined ones while aggregating, else the one carrying the internet; nothing gone, nothing merely here
        let joinedNow = Set(agg?.lines.filter(\.alive).map(\.device) ?? [])
        let shown = others.filter { Aggregation.on ? joinedNow.contains($0.iface) : $0.iface == iface }
        for o in shown where lineRows[o.iface] == nil {
            let r = LineRow(leadWidth: lead, nameWidth: nameW)
            r.view.edgeInsets.left += 12                    // v28: the names under the first row's name, past the minimize
            r.dot.isHidden = true                           // v28 (request 46): every line shown is connected; no dots
            r.name.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(showConnections)))
            r.speed.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(testRowSpeed(_:))))
            lineRows[o.iface] = r
            column.insertArrangedSubview(r.view, at: column.arrangedSubviews.count - 1)
            changed = true
        }
        for (dev, r) in lineRows where !shown.contains(where: { $0.iface == dev }) {
            column.removeArrangedSubview(r.view); r.view.removeFromSuperview(); lineRows[dev] = nil
            changed = true
        }
        let joined = Set(agg?.lines.map(\.device) ?? [])
        let tests = WebSpeedByConnection.all(), aggTest = AggTest.load()
        for o in shown {
            guard let r = lineRows[o.iface] else { continue }
            let ok = o.ms != nil
            // request 40: green connected (joined), red here but not connected, grey connected before and gone now
            let gone = o.iface.hasPrefix(SeenLines.gonePrefix)
            let color = lineColor(gone: gone, connected: Aggregation.on && joined.contains(o.iface))
            r.name.stringValue = gone ? o.name : Net.shown(o.name, o.iface)
            r.name.textColor = color
            r.dot.color = color
            r.ping.stringValue = o.ms.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
            r.ping.textColor = ok ? Ink.yellow : Ink.grey
            if gone {
                r.info.stringValue = "not available · connected " + ago(seen[o.name]?.last)
                r.info.textColor = Ink.grey
                r.name.toolTip = "Grey: connected before, not available now"
                r.speed.toolTip = nil
                if r.lastBytes == nil { r.setSpeed(nil, nil, test: lineTest(o.name, tests, aggTest), dim: true) }
                continue
            }
            r.info.textColor = Ink.dim
            r.name.toolTip = color == Ink.green ? "Green: connected, carrying the internet" : "Red: here, but not connected (tick it in ▾ to join it)"
            let line = agg?.lines.first { $0.device == o.iface }
            r.info.stringValue = o.sameAs.map { "same line as \($0): not joined" }
                ?? (Aggregation.on && line != nil ? String(format: "joined · %d conn · %.0f MB", line!.active, line!.mbDown + line!.mbUp)
                    : ok ? "not joined" : "no internet")
            r.speed.toolTip = "Its own live speed (its default route); in parentheses its last test alone, down and up.\nClick: test this line now (Cloudflare, about 6 s each way)."
            if r.lastBytes == nil { r.setSpeed(nil, nil, test: lineTest(o.name, tests, aggTest), dim: !ok, mark: lineTesting.contains(o.name) ? "..." : nil) }
        }
        // A phone row's live speed: the server's bytes on it between two scans (the Mac has no counter for adb).
        for o in others where Phones.isPhone(o.iface) {
            guard let r = lineRows[o.iface] else { continue }
            let l = agg?.lines.first { $0.device == o.iface }
            let c = l.map { (rx: UInt64($0.mbDown * 1e6), tx: UInt64($0.mbUp * 1e6)) }
            var v: (Double, Double)?
            if let c, let last = r.lastBytes, let at = r.lastAt {
                let dt = max(Date().timeIntervalSince(at), 0.5)
                v = (c.rx >= last.rx ? Double(c.rx - last.rx) / dt : 0, c.tx >= last.tx ? Double(c.tx - last.tx) / dt : 0)
            }
            r.lastBytes = c; r.lastAt = Date(); r.lastRate = v
            r.setSpeed(v?.0, v?.1, test: lineTest(o.name, tests, aggTest), dim: o.ms == nil, mark: lineTesting.contains(o.name) ? "..." : nil)
        }
        // v23 (request 41): the rows only when ▸ is opened; the one line is the whole stripe otherwise
        for r in lineRows.values where r.view.isHidden == expanded { r.view.isHidden = !expanded; changed = true }
        // aggregating, the one line already is AGGREGATE CONNECTION: no second row saying it again
        let aggHidden = !expanded || Aggregation.on
        if let a = aggRow, a.view.isHidden != aggHidden { a.view.isHidden = aggHidden; changed = true }
        expand.title = expanded ? "▾" : "▸"
        // The aggregation row: always the last.
        guard let a = aggRow else { return }
        a.name.stringValue = Aggregation.on ? "AGGREGATE CONNECTION" : "ONE CONNECTION"   // request 35, his words
        a.name.toolTip = "Click: switch between one connection and aggregate connection"
        if !Aggregation.on {
            a.dot.color = Ink.grey; a.name.textColor = Ink.text
            a.info.stringValue = Aggregation.selected.isEmpty ? "tick lines in ▾ to aggregate" : "click ONE CONNECTION to aggregate"
            a.info.textColor = Ink.dim
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
        var sumDown = 0.0, sumUp = 0.0, allDown = 0.0, allUp = 0.0
        func rates(_ last: (rx: UInt64, tx: UInt64)?, _ c: (rx: UInt64, tx: UInt64)?) -> (Double, Double)? {
            guard let last, let c, dt > 0 else { return nil }
            return (c.rx >= last.rx ? Double(c.rx - last.rx) / dt : 0, c.tx >= last.tx ? Double(c.tx - last.tx) / dt : 0)
        }
        for o in others {
            guard let r = lineRows[o.iface] else { continue }
            if Phones.isPhone(o.iface) {                    // its speed is set in layoutLines from the server's counters
                if let v = r.lastRate {
                    if joined.contains(o.iface) { sumDown += v.0; sumUp += v.1 }
                    allDown += v.0; allUp += v.1
                }
                continue
            }
            let c = all[o.iface]
            let v = rates(r.lastBytes, c)
            r.lastBytes = c
            r.setSpeed(v?.0, v?.1, test: lineTest(o.name, tests, aggTest), dim: o.ms == nil, mark: lineTesting.contains(o.name) ? "..." : nil)
            if joined.contains(o.iface), let v { sumDown += v.0; sumUp += v.1 }
            if o.sameAs == nil, let v { allDown += v.0; allUp += v.1 }
        }
        if let i = iface, joined.contains(i), let v = rates(aggMainLast, all[i]) { sumDown += v.0; sumUp += v.1 }
        if let i = iface { aggMainLast = all[i] }
        let on = Aggregation.on && agg != nil
        // v14: under mantra_networkaggregate the first row is the real lines added; utun99's own counters count every
        // byte twice (into hev and back out), 163 Mbit/s over lines carrying 82.8 (18.10.2026)
        if iface == Aggregation.tunnelDevice { setSpeed(allDown, allUp) }
        else if on { setSpeed(sumDown, sumUp) }            // v23: the one line is the joined lines added
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

    // ONE CLICK, THE OTHER MODE (request 34; request 35 named them): ONE CONNECTION ⇄ AGGREGATE CONNECTION on the stripe's last row, and the two choices on top of ▾.
    @objc func toggleMode() { switchMode(!Aggregation.on) }
    @objc func pickOne() { switchMode(false) }
    @objc func pickAggregate() { switchMode(true) }

    func switchMode(_ aggregate: Bool) {
        if aggregate && Aggregation.selected.isEmpty {
            // nothing ticked yet: every usable line that is its own line
            var s: [String] = []
            if let i = iface, i != Aggregation.tunnelDevice { s.append(Net.displayName(i)) }
            s += others.filter { $0.ms != nil && $0.sameAs == nil && $0.iface != iface }.map(\.name)
            Aggregation.selected = s
        }
        proxyDropped = false; serverMisses = 0
        appendLog("\(logStamp()) MODE asked on the stripe: \(aggregate ? "aggregate (" + Aggregation.selected.joined(separator: " + ") + ")" : "one connection")")
        DispatchQueue.global().async {
            let said = Aggregation.setMode(aggregate)
            appendLog("\(logStamp()) MODE \(aggregate ? "aggregate" : "one connection"): " + said.joined(separator: "; "))
            DispatchQueue.main.async { self.layoutLines(); self.scanLines() }
        }
        show(aggregate ? "aggregate connection: joining the lines…" : "one connection: aggregation off", aggregate ? Ink.amber : Ink.green, for: 8)
        layoutLines()
    }

    func addModeSection(_ menu: NSMenu) {
        let on = Aggregation.on
        for (title, sel, picked) in [("One connection   the Mac straight on its line, aggregation off", #selector(pickOne), !on),
                                     ("Aggregate connection   join the ticked lines (\(Aggregation.tunnelName))", #selector(pickAggregate), on)] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.state = picked ? .on : .off
            menu.addItem(i)
        }
        menu.addItem(.separator())
    }

    // THE JOIN TICKS (request 28). Rows are views, so a tick does not close the menu.
    func addJoinSection(_ menu: NSMenu) {
        var names: [(String, Bool, String)] = []
        if let i = iface, i != Aggregation.tunnelDevice { names.append((Net.displayName(i), true, i)) }
        for o in others where !names.contains(where: { $0.0 == o.name }) { names.append((o.name, o.ms != nil, o.iface)) }
        menu.addItem(.separator())
        let head = NSMenuItem(title: "JOIN (aggregation): tick the connections, none = off", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        let ticked = Set(Aggregation.selected)
        for (name, ok, dev) in names {
            let same = others.first { $0.name == name }?.sameAs
            let b = NSButton(checkboxWithTitle: Net.shown(name, dev) + (same.map { "   (same line as \($0), ignored)" } ?? ""), target: self, action: #selector(toggleJoin(_:)))
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
                let said = Aggregation.setMode(now)
                appendLog("\(logStamp()) AGGREGATION \(now ? "on" : "off"): " + said.joined(separator: "; "))
            }
        }
        layoutLines()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.scanLines() }
    }
}

// THE COLOURS OF A CONNECTION (v22, request 40, Marko 28.10.2026: "Red means device is available, but it's not
// connected, green means device is connected ... grey means it was connected in the past, but now it's not available").
// Every line that was ever green is remembered (seen-lines.json, a week), so it can stay on the stripe in grey when
// its device is gone (the Wi-Fi in WIRES, the phone unplugged).
func lineColor(gone: Bool, connected: Bool) -> NSColor { gone ? Ink.grey : connected ? Ink.green : Ink.red }

enum SeenLines {
    struct Seen: Codable { var wifi: Bool; var last: Date }
    static let file = Paths.support.appendingPathComponent("seen-lines.json")
    static let gonePrefix = "gone:"
    static let keep: TimeInterval = 7 * 86400
    static func load() -> [String: Seen] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Seen].self, from: $0) } ?? [:]
    }
    static func save(_ s: [String: Seen]) { try? JSONEncoder().encode(s).write(to: file, options: .atomic) }
}

extension Stripe {
    var currentName: String? { (state?.isFresh ?? false) ? state?.current : here }

    // The lines green now: the one under the first row (not the virtual device) and every joined one.
    func rememberLines() {
        let joined = Set(agg?.lines.map(\.device) ?? [])
        var green: [(String, Bool)] = []
        if let i = iface, i != Aggregation.tunnelDevice, let name = currentName { green.append((name, isWiFi(i))) }
        for o in others where Aggregation.on && joined.contains(o.iface) { green.append((o.name, o.wifi)) }
        var changed = false
        for (name, wifi) in green {
            if let s = seen[name], Date().timeIntervalSince(s.last) < 60 { continue }
            seen[name] = SeenLines.Seen(wifi: wifi, last: Date()); changed = true
        }
        if changed { SeenLines.save(seen) }
    }

    // Remembered lines whose device is not here now, as rows of their own (grey).
    func goneLines() -> [OtherLine] {
        let present = Set(others.map(\.name) + (Aggregation.on ? [] : [currentName ?? ""] + (iface.map { [Net.displayName($0)] } ?? [])))
        return seen.filter { !present.contains($0.key) && Date().timeIntervalSince($0.value.last) < SeenLines.keep }
            .sorted { $0.key < $1.key }
            .map { OtherLine(iface: SeenLines.gonePrefix + $0.key, name: $0.key, wifi: $0.value.wifi, ms: nil, sameAs: nil) }
    }
}

extension Stripe {
    @objc func toggleExpand() {
        expanded.toggle()
        UserDefaults.standard.set(expanded, forKey: "linesExpanded")
        layoutLines()
        fit()
    }
}
