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
    // v89 (request 97): the tick: this line is part of the aggregate connection (Ticks.swift)
    let tick = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let lead = NSView()
    let wifi = NSButton()           // v34 (request 51): in WIRES, this line shared over Wi-Fi to the house, in the lead's space
    let name: NSTextField
    // v43 (request 60): 4G and 5G beside the name on a phone's row; the one allowed now green, the other grey
    let g4 = NSButton(title: "4G", target: nil, action: nil), g5 = NSButton(title: "5G", target: nil, action: nil)
    let speed = label(textWidth(speedSample(), monoFont), font: monoFont)
    let ping = label(textWidth("999 ms", monoFont), font: monoFont)
    // v51: the two signal slots stacked in one small box (tag, a thin meter, "dBm · SINR"); Signal.swift fills them
    static let tagFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold), sigFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
    static let infoSample = "8L·888c·88.8×↑88.8×"
    let meter = VUMeter(), meter2 = VUMeter()
    let tag1 = label(18, font: LineRow.tagFont), tag2 = label(18, font: LineRow.tagFont)
    let sig = label(textWidth("-110 · -11", LineRow.sigFont), font: LineRow.sigFont), sig2 = label(textWidth("-110 · -11", LineRow.sigFont), font: LineRow.sigFont)
    let sigBox: NSStackView
    let info = label(textWidth(LineRow.infoSample, monoFont), font: monoFont)
    // v89 (request 99): TEST, speedtest.net over this line only, and its last result ("↓83.1 ↑29.4 23:10")
    let testButton = NSButton(title: "TEST", target: nil, action: nil)
    let result = label(textWidth("↓888.8 ↑888.8 88:88", monoFont), font: monoFont)
    var lastBytes: (rx: UInt64, tx: UInt64)?
    var lastAt: Date?, lastRate: (Double, Double)?      // a phone row: when the server's counters were read, the rate

    init(leadWidth: CGFloat, nameWidth: CGFloat) {
        name = label(nameWidth, font: .systemFont(ofSize: 12, weight: .semibold))
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 12).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 12).isActive = true
        lead.translatesAutoresizingMaskIntoConstraints = false
        wifi.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: "share this line over Wi-Fi")
        wifi.imagePosition = .imageOnly
        wifi.isBordered = false
        wifi.isHidden = true
        wifi.translatesAutoresizingMaskIntoConstraints = false
        lead.addSubview(wifi)
        NSLayoutConstraint.activate([wifi.trailingAnchor.constraint(equalTo: lead.trailingAnchor, constant: 2),
                                     wifi.centerYAnchor.constraint(equalTo: lead.centerYAnchor),
                                     wifi.widthAnchor.constraint(equalToConstant: 16), wifi.heightAnchor.constraint(equalToConstant: 16)])
        speed.lineBreakMode = .byClipping
        speed.maximumNumberOfLines = 1
        speed.cell?.wraps = false
        ping.textColor = Ink.yellow
        info.textColor = Ink.dim
        for (b, t) in [(g4, "4G"), (g5, "5G")] {
            b.isBordered = false
            b.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
            b.contentTintColor = Ink.grey
            b.setContentHuggingPriority(.required, for: .horizontal)
            b.alphaValue = 0                       // only a phone's row shows them; the slot stays so the columns align
            b.isEnabled = false
            b.setAccessibilityIdentifier("radio-\(t)")
        }
        // Marko 1.11.2026: "at the beginning of line ... move the buttons", then "Nothing Phone doesn't work": inside the
        // lead they stood partly outside it and a click could miss them; now they are items of the row, first in it,
        // and the lead is narrower by their width so nothing else moves.
        for b in [g4, g5] { b.setContentHuggingPriority(.required, for: .horizontal) }
        lead.widthAnchor.constraint(equalToConstant: max(20, leadWidth - g4.fittingSize.width - g5.fittingSize.width - tick.fittingSize.width - 6)).isActive = true
        func mini(_ t: NSTextField, _ m: VUMeter, _ s: NSTextField) -> NSStackView {
            let r = NSStackView(views: [t, m, s]); r.orientation = .horizontal; r.spacing = 3; r.alignment = .centerY; return r
        }
        sigBox = NSStackView(views: [mini(tag1, meter, sig), mini(tag2, meter2, sig2)])
        sigBox.orientation = .vertical; sigBox.spacing = 0; sigBox.alignment = .leading
        tick.appearance = NSAppearance(named: .darkAqua)
        tick.setContentHuggingPriority(.required, for: .horizontal)
        testButton.isBordered = false
        testButton.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        testButton.contentTintColor = Ink.text
        testButton.setContentHuggingPriority(.required, for: .horizontal)
        result.textColor = Ink.dim
        view = NSStackView(views: [tick, g4, g5, lead, name, linePipe(), speed, linePipe(), ping, linePipe(), sigBox, linePipe(), info, linePipe(), testButton, result])
        view.orientation = .horizontal
        view.spacing = 3
        view.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    // Download green, upload red, each with a test in parentheses, as on the first row.
    func setSpeed(_ down: Double?, _ up: Double?, test: (Double, Double?)?, dim: Bool = false, mark: String? = nil) {
        let dash = String(repeating: " ", count: max(0, rate(0).count - 1)) + "—"
        let d = down.map(rate) ?? dash
        let u = up.map(rate) ?? dash
        speed.attributedStringValue = speedWithArrows(d, u, dim ? Ink.grey : Ink.green, dim ? Ink.grey : Ink.red)
    }
    // v82 (request 91): a STANDBY line shows no live speed and no arrows, only a quiet dash
    func setIdle() {
        let s = String(repeating: " ", count: max(0, rate(0).count - 1)) + "—"
        speed.attributedStringValue = NSAttributedString(string: s, attributes: [.font: monoFont, .foregroundColor: Ink.grey])
    }
}

// v60 (request 81, Marko 14.11.2026: "next to upload speed, make a nice up arrow. Next to the download speed, make a nice
// download arrow"): an SF Symbol arrow in the number's own colour before each number, on the text's centre line.
func speedArrow(_ down: Bool, _ color: NSColor) -> NSAttributedString {
    let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: down ? "arrow.down" : "arrow.up", accessibilityDescription: down ? "download" : "upload")?
        .withSymbolConfiguration(cfg) else { return NSAttributedString(string: down ? "↓" : "↑", attributes: [.font: monoFont, .foregroundColor: color]) }
    let att = NSTextAttachment()
    att.image = img
    att.bounds = NSRect(x: 0, y: (monoFont.capHeight - img.size.height) / 2, width: img.size.width, height: img.size.height)
    let a = NSMutableAttributedString(attachment: att)
    a.append(NSAttributedString(string: "\u{2009}", attributes: [.font: monoFont]))
    return a
}

func speedWithArrows(_ d: String, _ u: String, _ dc: NSColor, _ uc: NSColor) -> NSAttributedString {
    let t = NSMutableAttributedString(attributedString: speedArrow(true, dc))
    t.append(NSAttributedString(string: d.trimmingCharacters(in: .whitespaces), attributes: [.font: monoFont, .foregroundColor: dc]))
    t.append(NSAttributedString(string: "  ", attributes: [.font: monoFont]))
    t.append(speedArrow(false, uc))
    t.append(NSAttributedString(string: u.trimmingCharacters(in: .whitespaces), attributes: [.font: monoFont, .foregroundColor: uc]))
    return t
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
        let seen = adbSeen, seenAt = nothingAt
        DispatchQueue.global().async {
            let st = Aggregation.status()
            let wifi = Net.wifiInterface()
            var found: [OtherLine] = []
            var routers: [String: String] = [:]                 // v89: each line's router, for the same-road rule (Ticks.swift)
            // v23: aggregating, the one line is AGGREGATE CONNECTION, so the line under it needs its own row too
            // v24: the line carrying the internet has its row too (the opened list shows what is connected now)
            for i in Net.activeInterfaces() {
                let gw = shell("/usr/sbin/ipconfig", ["getoption", i, "router"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
                if gw.isEmpty { continue }
                routers[Net.displayName(i)] = LineMemory.routerMAC(i)
                // v87 (request 96): a phone's hotspot is a line again (v81 had greyed it)
                found.append(OtherLine(iface: i, name: Net.displayName(i), wifi: i == wifi, ms: Net.onlineVia(i),
                                       sameAs: st?.ignored.first { $0.device == i }?.sameLineAs))
            }
            // v81 (request 89): adb looked at; a change (a phone plugged in or out) or every 30 s: the Nothing's cable said
            let adbNow = CableOnly.entries().map { "\($0.serial)=\($0.state)\($0.usb ? "u" : "")" }.sorted().joined(separator: " ")
            var nothing: (ok: Bool, words: String, detail: String)?
            if adbNow != seen || Date().timeIntervalSince(seenAt) > 30 {
                if adbNow != seen && !seen.isEmpty { Phones.refreshAdb().forEach { appendLog("\(logStamp()) ADB \($0)") } }
                nothing = CableOnly.nothingStatus()
            }
            // v17 (request 36): a phone on a USB cable, its line over adb (its server started here if need be)
            for p in Phones.list() {
                if let note = Phones.ensure(p) { appendLog("\(logStamp()) PHONE \(p.name): \(note)") }
                found.append(OtherLine(iface: p.device, name: p.name, wifi: false, ms: Phones.online(p), sameAs: nil))
                CableOnly.learnHotspot(p.serial)                 // v89: its hotspot's name, so the two are one group (once a run)
            }
            DispatchQueue.main.async {
                self.scanning = false
                if let n = nothing { self.adbSeen = adbNow; self.nothingAt = Date(); self.sayNothing(n, force: false) }
                self.others = found
                self.agg = st
                var ips: [String: String] = [:]
                for l in st?.lines ?? [] where !l.publicIP.isEmpty { ips[l.name] = l.publicIP }
                LineMemory.learn(routers: routers, ips: ips)
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
                    Aggregation.ensureAgents()
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

    // v89 (request 97): ONE list, always every connection the app knows (Ticks.swift), a tick each; no tabs, no ▾ list.
    func layoutLines() {
        guard let column = panel.contentView?.subviews.first as? NSStackView else { return }
        // the same lead as the ALL TICKED row (main.swift), so the names stand in one column under the first row's name
        let lead = onWord.fittingSize.width + offWord.fittingSize.width + linePipe().fittingSize.width + 12 + gear.fittingSize.width + rescan.fittingSize.width + 6, nameW = connectionWidth()
        var changed = false
        rememberLines()
        cleanOutsideTicks()
        let entries = tickEntries()
        let names = entries.map(\.name)
        for e in entries where lineRows[e.name] == nil {
            let r = LineRow(leadWidth: lead, nameWidth: nameW)
            r.dot.isHidden = true
            r.tick.target = self
            r.tick.action = #selector(tickPressed(_:))
            r.tick.identifier = NSUserInterfaceItemIdentifier(e.name)
            r.tick.setAccessibilityIdentifier("tick-" + e.name)
            r.tick.setAccessibilityLabel(e.name)
            r.speed.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(testRowSpeed(_:))))
            r.wifi.target = self
            r.wifi.action = #selector(toggleShare(_:))
            r.testButton.target = self
            r.testButton.action = #selector(rowTestPressed(_:))
            r.testButton.identifier = NSUserInterfaceItemIdentifier(e.name)
            r.testButton.setAccessibilityIdentifier("test-" + e.name)
            lineRows[e.name] = r
            changed = true
        }
        for (n, r) in lineRows where !names.contains(n) {
            column.removeArrangedSubview(r.view); r.view.removeFromSuperview(); lineRows[n] = nil
            changed = true
        }
        // the rows in the list's order, just above the (hidden) aggregation row; put again only when the set changed
        let want = names.compactMap { lineRows[$0]?.view }
        let now = column.arrangedSubviews.filter { v in lineRows.values.contains { $0.view === v } }
        if want.count != now.count || zip(want, now).contains(where: { $0.0 !== $0.1 }) {
            for v in now { column.removeArrangedSubview(v); v.removeFromSuperview() }
            for v in want { column.insertArrangedSubview(v, at: column.arrangedSubviews.firstIndex(of: aggRow.view) ?? column.arrangedSubviews.count - 1) }
            changed = true
        }
        let ticked = Set(tickedNames)
        let tests = WebSpeedByConnection.all(), aggTest = AggTest.load()
        for e in entries {
            guard let r = lineRows[e.name] else { continue }
            let on = ticked.contains(e.name)
            let st = tickState(e, ticked: on)
            if (r.tick.state == .on) != on { r.tick.state = on ? .on : .off }
            r.tick.setAccessibilityValue(on ? "on" : "off")
            r.tick.toolTip = on ? "Ticked: \(e.name) is part of the aggregate connection. Untick: leave it out (no tick at all: the Mac straight on its own connection)."
                : "Tick: \(e.name) becomes part of the aggregate connection. A line that is the same road as a ticked one (one Wi-Fi, the same phone, the same router) unticks that one."
            r.info.stringValue = st.word
            r.info.textColor = st.color
            r.info.toolTip = st.word.hasPrefix("⇄") ? "Unticked: the same road as a line just ticked (\(st.word.dropFirst(2)))" : nil
            let tw = testWords(e.name)
            r.result.stringValue = tw.0; r.result.textColor = tw.1; r.result.toolTip = tw.2
            r.testButton.isEnabled = e.other != nil && LineSpeedTest.running == nil
            r.testButton.contentTintColor = r.testButton.isEnabled ? Ink.text : Ink.grey
            r.testButton.toolTip = e.other == nil ? "Not here now: nothing to test" : LineSpeedTest.running != nil ? "A test is running; one at a time"
                : "TEST: speedtest.net over \(e.name) only (its own device, or the phone's SIM through its cable), in the background, about 40 s"
            guard let o = e.other else {
                // not here now: grey, no numbers, no meters
                r.name.stringValue = e.name
                r.name.textColor = on ? Ink.amber : Ink.grey
                r.name.toolTip = e.inRange ? "A Wi-Fi network in range. Tick: the Mac joins it and it is a line." : "Not here now" + (seen[e.name].map { ", last connected " + ago($0.last) } ?? "") + ". Ticked, it joins when it is back."
                r.ping.stringValue = "—"; r.ping.textColor = Ink.grey
                r.setIdle()
                r.lastBytes = nil
                for m in [r.meter, r.meter2] { m.alphaValue = 0 }
                for t in [r.tag1, r.sig, r.tag2, r.sig2] { t.stringValue = "" }
                r.tag1.identifier = nil; r.tag2.identifier = nil
                r.wifi.isHidden = true
                for b in [r.g4, r.g5] { b.alphaValue = 0; b.isEnabled = false }
                continue
            }
            let ok = o.ms != nil
            r.name.stringValue = Net.shown(o.name, o.iface)
            r.name.textColor = on ? (st.color == Ink.green ? Ink.green : st.color) : (ok ? NSColor.white : Ink.grey)
            r.name.toolTip = Phones.isPhone(o.iface) ? "\(o.name): the phone on its USB cable (its SIM, over adb)" : o.wifi ? "\(o.name): the Mac's Wi-Fi (\(o.iface))" : "\(o.name): a cable (\(o.iface))"
            r.ping.stringValue = o.ms.map { String(format: "%3.0f ms", $0) } ?? "—"
            r.ping.textColor = ok ? Ink.yellow : Ink.grey
            if Phones.isPhone(o.iface) {
                let serial = String(o.iface.dropFirst(4))
                for b in [r.g4, r.g5] {
                    b.alphaValue = 1; b.isEnabled = true; b.target = self; b.action = #selector(radioPressed(_:))
                    b.identifier = NSUserInterfaceItemIdentifier(serial)
                }
                showRadio(r, serial)
            } else { for b in [r.g4, r.g5] { b.alphaValue = 0; b.isEnabled = false } }
            showShare(r, o)
            r.speed.toolTip = "Its own live speed (its default route).\nClick: test this line now (Cloudflare, about 6 s each way)."
            if r.lastBytes == nil { r.setSpeed(nil, nil, test: lineTest(o.name, tests, aggTest), dim: !ok, mark: lineTesting.contains(o.name) ? "..." : nil) }
        }
        // A phone row's live speed: the server's bytes on it between two scans (the Mac has no counter for adb).
        for o in others where Phones.isPhone(o.iface) {
            guard let r = lineRows[o.name] else { continue }
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
        // v89 (request 99): the last row is ALL TICKED: the ticked lines together (or the Mac's own line with no tick), its
        // TEST runs speedtest.net over the Mac's route, to compare a combination with its single lines
        if let a = aggRow {
            if a.view.isHidden { a.view.isHidden = false; changed = true }
            a.tick.isHidden = true
            a.name.stringValue = tickedNames.isEmpty ? "NO TICK: THE MAC" : "ALL TICKED"
            a.name.textColor = tickedNames.isEmpty ? Ink.text : Ink.green
            a.name.toolTip = tickedNames.isEmpty ? "No line ticked: the Mac straight on its own connection" : "The ticked lines together: " + tickedNames.joined(separator: " + ")
            a.info.stringValue = tickedNames.isEmpty ? "" : "\(tickedNames.count) LINE\(tickedNames.count == 1 ? "" : "S")"
            a.info.textColor = Ink.dim
            a.ping.stringValue = ""
            a.testButton.target = self
            a.testButton.action = #selector(rowTestPressed(_:))
            a.testButton.identifier = NSUserInterfaceItemIdentifier(Stripe.allTickedName)
            a.testButton.setAccessibilityIdentifier("test-all-ticked")
            a.testButton.isEnabled = LineSpeedTest.running == nil
            a.testButton.contentTintColor = a.testButton.isEnabled ? Ink.text : Ink.grey
            a.testButton.toolTip = "TEST: speedtest.net over the ticked lines together (the Mac's route), to compare with each line alone"
            let tw = testWords(Stripe.allTickedName)
            a.result.stringValue = tw.0; a.result.textColor = tw.1; a.result.toolTip = tw.2
        }
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
            guard let r = lineRows[o.name] else { continue }
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
        else if let o = others.first(where: { lineRows[$0.name]?.speed === g.view }), o.sameAs == nil { name = o.name }
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

    func switchMode(_ aggregate: Bool, done: (() -> Void)? = nil) {
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
            done?()
        }
        show(aggregate ? "aggregate connection: joining the lines…" : "one connection: aggregation off", aggregate ? Ink.amber : Ink.green, for: 8)
        layoutLines()
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

// v43 (request 60): the phone's 4G / 5G, read every 15 s off the main thread (two adb calls a phone), switched on a click.
extension Stripe {
    func showRadio(_ r: LineRow, _ serial: String) {
        let st = radioStates[serial]
        let five = st?.fiveG
        r.g5.contentTintColor = five == true ? Ink.green : Ink.grey
        r.g4.contentTintColor = five == false ? Ink.green : Ink.grey
        let tip = st.map { "Now on the phone's status bar: \($0.shown) (SIM \($0.slot + 1), the one carrying data)." } ?? "Reading the phone…"
        r.g5.toolTip = tip + "\nClick: allow 5G on this phone (Settings → Preferred network type 5G), through adb."
        r.g4.toolTip = tip + "\nClick: 4G only on this phone (5G not allowed), through adb."
        r.g5.setAccessibilityValue(five == true ? "on" : "off"); r.g4.setAccessibilityValue(five == false ? "on" : "off")
    }

    func readRadios() {
        if radioReading { return }
        radioReading = true
        let serials = others.filter { Phones.isPhone($0.iface) }.map { String($0.iface.dropFirst(4)) }
        DispatchQueue.global().async {
            var got: [String: (fiveG: Bool?, shown: String, slot: Int)] = [:]
            for s in serials { if let st = PhoneRadio.state(s) { got[s] = st } }
            DispatchQueue.main.async {
                for (k, v) in got { self.radioStates[k] = v }
                for o in self.others where Phones.isPhone(o.iface) { if let r = self.lineRows[o.name] { self.showRadio(r, String(o.iface.dropFirst(4))) } }
                self.radioReading = false
            }
        }
    }

    @objc func radioPressed(_ b: NSButton) {
        guard let serial = b.identifier?.rawValue else { return }
        let five = b.title == "5G"
        let slot = radioStates[serial]?.slot
        b.contentTintColor = Ink.amber
        appendLog("\(logStamp()) RADIO \(serial): \(five ? "5G" : "4G") pressed")
        DispatchQueue.global().async {
            let sl = slot ?? PhoneRadio.state(serial)?.slot ?? 0
            let ok = PhoneRadio.set(serial, slot: sl, fiveG: five)
            // the phone takes some seconds to move to the other carrier; read it back after 8 s
            sleep(8)
            let st = PhoneRadio.state(serial)
            DispatchQueue.main.async {
                if let st { self.radioStates[serial] = st }
                appendLog("\(logStamp()) RADIO \(serial): \(ok ? "set" : "NOT set"), the phone shows \(st?.shown ?? "?")")
                for o in self.others where o.iface == "adb:\(serial)" { if let r = self.lineRows[o.name] { self.showRadio(r, serial) } }
                self.show(ok ? "\(five ? "5G" : "4G"): the phone shows \(st?.shown ?? "?")" : "the phone did not take the change (adb)", ok ? Ink.green : Ink.red, for: 8)
            }
        }
    }
}

// v81 (request 89): the Nothing's cable in words on the status line, when it changes (and on ⟳), and in the log.
extension Stripe {
    func sayNothing(_ n: (ok: Bool, words: String, detail: String), force: Bool) {
        let changed = n.words != nothingSaid
        if changed { appendLog("\(logStamp()) NOTHING \(n.words) (\(n.detail))") }
        nothingSaid = n.words
        guard changed || force else { return }
        // the first look after start says only a problem; "not on the cable" while it never was is said on ⟳ only
        if !force && !n.ok && n.words == "Nothing: not on the cable" { return }
        show(n.words, n.ok ? Ink.green : Ink.amber, for: n.ok ? 15 : 45, tip: n.detail)
    }
}

// v82 (request 91): the line's role in NOTHING ONLY ("active", "standby", "fallback"), nil in every other mode.
extension Stripe {
    func lineRole(_ dev: String) -> String? {
        guard NothingOnly.on else { return nil }
        return agg?.lines.first { $0.device == dev }?.role
    }
    func roleWord(_ dev: String) -> String? {
        switch lineRole(dev) {
        case "standby": return "STANDBY"
        case "fallback": return "FALLBACK·ACTIVE"
        case "active": return agg?.lines.first { $0.device == dev }?.alive == false ? "NO ANSWER" : "ACTIVE"
        default: return nil
        }
    }
}
