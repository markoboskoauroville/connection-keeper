// ONE TICK PER CONNECTION (v89, request 97, Marko 23.11.2026: "always all connections are listed and I have check marks
// for each connection. This Wi-Fi, cable, both, these things go out, and whatever I check mark becomes part of the
// aggregate connection. Of course, if I'm checking 2 things from the same connection, they are canceling each other. For
// example, I have Something Wi-Fi and I have Nothing USB. Only 1 can be active at a time.")
//
// The list under the first row is every connection the app knows: the lines here now (cables, phones on USB, the Wi-Fi
// joined), the Wi-Fi networks in range, the lines remembered from the last week, and any ticked line that is away. One
// tick each. The ticks ARE the choice:
//   no tick          aggregation off: the Mac straight on its own connection (the row it uses says MAC'S OWN);
//   one tick         everything through that one line (the aggregate of one: the tunnel, the bond to Frankfurt);
//   several ticks    the aggregate connection over those lines.
// A ticked Wi-Fi network that the Mac is not on is joined. Ticks go to aggregate-selection.json (Aggregation.selected),
// which ck-aggregate reads every second; the ticked lines also go first in macOS's service order.
//
// THE SAME UPSTREAM (exclusion groups). Two rows that are the same road out cannot both be ticked; ticking one unticks
// the other, and the unticked row says why for a few seconds. A row belongs to these groups (one shared group = the same):
//   radio:wifi     every Wi-Fi network: the Mac has one Wi-Fi, so one network at a time               ONE WI-FI
//   sim:<serial>   a phone on its cable and that phone's own hotspot (learned over adb: the hotspot's
//                  name and the phone's ro.serialno, CableOnly.learnHotspot): the same SIM             SAME PHONE
//   router:<mac>   lines whose router has the same hardware address (the cable AX88179B and the Wi-Fi
//                  "mantra" both behind the TP-Link): one router, one road                             SAME ROUTER
//   ip:<address>   lines that left through the same public address (never for a phone or a phone's
//                  hotspot: two SIMs can share a carrier's address and still be two roads)              SAME ADDRESS
// The router and address of each line are remembered (line-memory.json), so a Wi-Fi network in range that the Mac is
// not on still knows its router from the last time. The same rule cleans ticks that arrive from elsewhere (a phone
// plugged in and ticked by ck-aggregate, a terminal): the tick that was there first stays.
import AppKit

struct TickEntry {
    let name: String            // the tick's name, the one ck-aggregate knows (the Wi-Fi by its network's name)
    let other: OtherLine?       // the line, when it is here now
    let wifi: Bool
    let inRange: Bool           // a Wi-Fi network in range that the Mac is not on
    let kind: Int               // the order of the list: 0 cables, 1 phones, 2 Wi-Fi
}

enum LineMemory {
    struct Mem: Codable { var routers: [String: String] = [:]; var ips: [String: String] = [:] }
    static let file = Paths.support.appendingPathComponent("line-memory.json")
    static var mem: Mem = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Mem.self, from: $0) } ?? Mem()
    static func learn(routers: [String: String], ips: [String: String]) {
        var m = mem
        for (k, v) in routers where !v.isEmpty { m.routers[k] = v }
        for (k, v) in ips where !v.isEmpty { m.ips[k] = v }
        guard m.routers != mem.routers || m.ips != mem.ips else { return }
        mem = m
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(m).write(to: file, options: .atomic)
    }
    // The router's hardware address of a device that has a router now ("" when arp does not know it yet).
    static func routerMAC(_ iface: String) -> String {
        let gw = shell("/usr/sbin/ipconfig", ["getoption", iface, "router"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gw.isEmpty else { return "" }
        for line in shell("/usr/sbin/arp", ["-n", gw], timeout: 5).out.components(separatedBy: "\n") where line.contains("on \(iface)") {
            if let r = line.range(of: #" at ([0-9a-f:]+) "#, options: .regularExpression) {
                let mac = String(line[r]).replacingOccurrences(of: "at", with: "").trimmingCharacters(in: .whitespaces)
                return mac.contains(":") ? mac : ""
            }
        }
        return ""
    }
}

enum TickQueue { static let lock = NSLock(); static var pending: [String]?; static var running = false }

extension Stripe {
    // What the rows show ticked: the ticks while the aggregation is on, none while it is off.
    var tickedNames: [String] { Aggregation.aggregateMode ? Aggregation.selected : [] }

    // Every connection the app knows, in a fixed order (kind, then name), so rows never jump about.
    func tickEntries() -> [TickEntry] {
        var out: [TickEntry] = [], have = Set<String>()
        func add(_ e: TickEntry) { guard !e.name.isEmpty, !have.contains(e.name) else { return }; have.insert(e.name); out.append(e) }
        for o in others { add(TickEntry(name: o.name, other: o, wifi: o.wifi, inRange: false, kind: Phones.isPhone(o.iface) ? 1 : o.wifi ? 2 : 0)) }
        for n in wifiScan { add(TickEntry(name: n, other: nil, wifi: true, inRange: true, kind: 2)) }
        for (n, s) in seen where Date().timeIntervalSince(s.last) < SeenLines.keep && n != Aggregation.tunnelName && n != "Wi-Fi" {
            add(TickEntry(name: n, other: nil, wifi: s.wifi, inRange: false, kind: s.wifi ? 2 : n.hasSuffix("(USB)") ? 1 : 0))
        }
        for n in tickedNames { add(TickEntry(name: n, other: nil, wifi: false, inRange: false, kind: 0)) }
        // v90 (request 100): by FAMILY (the rows of one road out, families() below), the families in a fixed order (their
        // first kind, then their first name), inside a family the wired row first and the Wi-Fi under it
        let fam = families(out.map(\.name))
        func key(_ e: TickEntry) -> (Int, String, Int, String) {
            let f = fam[e.name] ?? [e.name]
            let members = out.filter { f.contains($0.name) }
            let first = members.map(\.kind).min() ?? e.kind
            let head = members.filter { $0.kind == first }.map { $0.name.lowercased() }.min() ?? e.name.lowercased()
            return (first, head, e.kind, e.name.lowercased())
        }
        return out.sorted { key($0) < key($1) }
    }

    // FAMILIES (v90, request 100): the rows that are one road out (the same phone, the same router, the same public
    // address: the groups of tickGroups() without "one Wi-Fi", which is the Mac's radio, not a road), joined through any
    // shared group. What is drawn together is what cancels each other. Every name → the names of its family.
    func families(_ names: [String]) -> [String: Set<String>] {
        var keys: [String: Set<String>] = [:]
        for n in names { keys[n] = Set(tickGroups(n).map(\.key).filter { $0 != "radio:wifi" }) }
        var fam: [String: Set<String>] = [:]
        var left = Set(names)
        while let start = left.first {
            var group: Set<String> = [start], todo = [start]
            left.remove(start)
            while let n = todo.popLast() {
                for m in left where !(keys[m] ?? []).isDisjoint(with: keys[n] ?? []) { group.insert(m); todo.append(m) }
                left.subtract(group)
            }
            for n in group { fam[n] = group }
        }
        return fam
    }

    // The groups of one tick's name (see the head of this file), each with the word a row shows when it is unticked by it.
    func tickGroups(_ name: String) -> [(key: String, word: String)] {
        let o = others.first { $0.name == name }
        let isWifi = o?.wifi ?? (wifiScan.contains(name) || seen[name]?.wifi == true || CableOnly.isPhoneHotspot(name))
        var g: [(key: String, word: String)] = []
        if isWifi { g.append((key: "radio:wifi", word: "ONE WI-FI")) }
        var serial: String?
        if let o, Phones.isPhone(o.iface) { serial = String(o.iface.dropFirst(4)) }
        else if isWifi { serial = CableOnly.owners[name] }
        if let s = serial { g.append((key: "sim:" + s, word: "SAME PHONE")) }
        if let mac = LineMemory.mem.routers[name] { g.append((key: "router:" + mac, word: "SAME ROUTER")) }
        let cellular = serial != nil || CableOnly.isPhoneHotspot(name) || (o.map { Phones.isPhone($0.iface) } ?? name.hasSuffix("(USB)"))
        if !cellular, let ip = LineMemory.mem.ips[name] { g.append((key: "ip:" + ip, word: "SAME ADDRESS")) }
        return g
    }

    // The word that says why `b` cannot be ticked beside `a`, nil when they are two roads.
    func clash(_ a: String, _ b: String) -> String? {
        guard a != b else { return nil }
        let gb = tickGroups(b)
        for x in tickGroups(a) { if gb.contains(where: { $0.key == x.key }) { return x.word } }
        return nil
    }

    // The ticks without clashes: the earlier tick stays. Returns the ticks kept and the ones dropped, with the reason.
    // v90: a line that is here beats one that is away (v89 kept the absent "mantra" and dropped the cable that was here).
    func cleanTicks(_ names: [String]) -> (kept: [String], dropped: [(name: String, by: String, word: String)]) {
        var kept: [String] = [], dropped: [(name: String, by: String, word: String)] = []
        let here = Set(others.map(\.name))
        let ordered = names.filter { here.contains($0) } + names.filter { !here.contains($0) }
        for n in ordered where !kept.contains(n) {
            if let by = kept.first(where: { clash($0, n) != nil }) { dropped.append((name: n, by: by, word: clash(by, n) ?? "")) } else { kept.append(n) }
        }
        return (kept, dropped)
    }

    func sayDropped(_ dropped: [(name: String, by: String, word: String)]) {
        for d in dropped {
            tickFlash[d.name] = (d.word, Date().addingTimeInterval(8))
            let why = d.word == "ONE WI-FI" ? "the Mac has one Wi-Fi, one network at a time"
                : d.word == "SAME PHONE" ? "the same phone, the same SIM"
                : d.word == "SAME ROUTER" ? "behind the same router" : "the same public address"
            appendLog("\(logStamp()) TICKS \(d.name) unticked: \(d.by) is ticked, \(why)")
            show("\(d.name) unticked: \(d.by) is the same road (\(why))", Ink.amber, for: 8)
        }
    }

    // The devices of the ticked lines that are here (for the service order).
    func tickedDevices() -> Set<String> {
        let t = Set(tickedNames)
        return Set(others.filter { t.contains($0.name) && !Phones.isPhone($0.iface) }.map(\.iface))
    }

    // A tick on a row, by his hand.
    @objc func tickPressed(_ b: NSButton) {
        guard let name = b.identifier?.rawValue else { return }
        var sel = tickedNames
        if b.state == .on {
            if let o = others.first(where: { $0.name == name }), o.ms == nil || deadIfaces.contains(o.iface) {
                b.state = .off
                show("\(Net.shown(o.name, o.iface)): no internet through it now, it cannot join", Ink.amber, for: 8)
                return
            }
            var dropped: [(name: String, by: String, word: String)] = []
            sel = sel.filter { n in
                if n == name { return false }
                if let w = clash(name, n) { dropped.append((name: n, by: name, word: w)); return false }
                return true
            }
            sel.append(name)
            sayDropped(dropped)
            appendLog("\(logStamp()) TICK \(name) on (by hand)")
        } else {
            sel.removeAll { $0 == name }
            appendLog("\(logStamp()) TICK \(name) off (by hand)")
        }
        setTicks(sel)
    }

    // The one way the ticks change (his hand, the outside notifications). Written at once so the rows show it; the
    // switching work (joining a Wi-Fi, the aggregation on or off, the service order) runs on ONE serial worker, the
    // latest ticks win (as v86's choice queue).
    func setTicks(_ wanted: [String]) {
        let c = cleanTicks(wanted)
        if !c.dropped.isEmpty { sayDropped(c.dropped) }
        let sel = c.kept
        if !sel.isEmpty { Aggregation.selected = sel }
        appendLog("\(logStamp()) TICKS \(sel.isEmpty ? "none: aggregation off, the Mac straight on its own connection" : sel.joined(separator: " + "))")
        show(sel.isEmpty ? "no tick: the Mac straight on its own connection" : sel.count == 1 ? "\(sel[0]): everything through this one line" : "aggregate: " + sel.joined(separator: " + "), Ink.green, for: 8)
        layoutLines()
        TickQueue.lock.lock()
        TickQueue.pending = sel
        let start = !TickQueue.running
        if start { TickQueue.running = true }
        TickQueue.lock.unlock()
        guard start else { appendLog("\(logStamp()) TICKS queued (a switch is running; the latest wins)"); return }
        DispatchQueue.global().async {
            while true {
                TickQueue.lock.lock()
                let next = TickQueue.pending
                TickQueue.pending = nil
                if next == nil { TickQueue.running = false }
                TickQueue.lock.unlock()
                guard let sel = next else { return }
                self.runTicks(sel)
            }
        }
    }

    // Off the main thread: what the ticks need on the Mac.
    func runTicks(_ sel: [String]) {
        let sem = DispatchSemaphore(value: 0)
        // a ticked Wi-Fi network the Mac is not on: joined (only one can be ticked, ONE WI-FI)
        let (scan, wifiNames): ([String], Set<String>) = DispatchQueue.main.sync { (self.wifiScan, Set(self.others.filter(\.wifi).map(\.name))) }
        if let w = Net.wifiInterface(), let ssid = sel.first(where: { scan.contains($0) && !wifiNames.contains($0) }), Net.currentSSID(w) != ssid {
            DispatchQueue.main.async { self.show("\(ssid): joining the Wi-Fi…", Ink.amber, for: 60) }
            let r = Join.wifi(ssid, w)
            appendLog("\(logStamp()) TICKS Wi-Fi \(ssid): \(r.ok ? "joined" : "NOT joined") (\(r.detail))")
            DispatchQueue.main.async { self.show(r.ok ? "\(ssid): joined" : "\(ssid): could not join (\(r.detail))", r.ok ? Ink.green : Ink.red, for: 15) }
        }
        if sel.isEmpty {
            if Aggregation.aggregateMode {
                DispatchQueue.main.async { self.switchMode(false) { sem.signal() } }
                _ = sem.wait(timeout: .now() + 90)
            }
        } else if !Aggregation.aggregateMode {
            DispatchQueue.main.async { self.switchMode(true) { sem.signal() } }
            _ = sem.wait(timeout: .now() + 90)
        }
        let (first, dead): (Set<String>, Set<String>) = DispatchQueue.main.sync { (self.tickedDevices(), self.deadIfaces) }
        if let said = ServiceOrder.apply(first: first, dead: dead) { appendLog("\(logStamp()) ORDER (ticks): \(said)") }
        DispatchQueue.main.async { self.scanLines() }
    }

    // Ticks that came from elsewhere (ck-aggregate ticking a phone just plugged in, a terminal) cleaned by the same rule.
    func cleanOutsideTicks() {
        guard Aggregation.aggregateMode, !TickQueue.running else { return }
        let sel = Aggregation.selected
        let c = cleanTicks(sel)
        guard !c.dropped.isEmpty, !c.kept.isEmpty else { return }
        Aggregation.selected = c.kept
        sayDropped(c.dropped)
    }

    // From outside (Queen, a terminal): ConnectionKeeperTicks with the names joined by commas ("" = none), and the older
    // ConnectionKeeperChoose (wifi = the Wi-Fi in use only, cable = every wired line, both = every line here) and
    // ConnectionKeeperNothingOnly "on" (= only the Nothing on its cable ticked).
    func outsideTicks(_ names: [String], _ said: String) {
        appendLog("\(logStamp()) TICKS from outside (\(said)): \(names.isEmpty ? "none" : names.joined(separator: " + "))")
        outsideTicksWanted = names
        outsideTicksGen += 1
        let g = outsideTicksGen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in        // v85: a burst collapses into the last
            guard let self, g == self.outsideTicksGen, let n = self.outsideTicksWanted else { return }
            self.outsideTicksWanted = nil
            self.setTicks(n)
        }
    }

    func ticksForChoice(_ c: LinkChoice) -> [String] {
        let usable = others.filter { $0.ms != nil && !deadIfaces.contains($0.iface) && $0.sameAs == nil }
        switch c {
        case .wifi: return usable.filter(\.wifi).map(\.name)
        case .cable: return usable.filter { !$0.wifi }.map(\.name)
        case .both: return usable.filter { !$0.wifi }.map(\.name) + usable.filter(\.wifi).map(\.name)
        }
    }

    func listenForOutsideTicks() {
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: Notification.Name("ConnectionKeeperTicks"), object: nil, queue: .main) { [weak self] n in
            let names = ((n.object as? String) ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            self?.outsideTicks(names, "ConnectionKeeperTicks")
        }
        dc.addObserver(forName: Notification.Name("ConnectionKeeperChoose"), object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            let want = (n.object as? String)?.lowercased()
            guard let c = want.flatMap({ LinkChoice(rawValue: $0) }) else {
                appendLog("\(logStamp()) CHOICE from outside ignored: \(want ?? "nothing") (wifi, cable or both)"); return
            }
            self.outsideTicks(self.ticksForChoice(c), "ConnectionKeeperChoose \(c.rawValue)")
        }
        dc.addObserver(forName: Notification.Name("ConnectionKeeperNothingOnly"), object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            guard (n.object as? String) == "on" else { appendLog("\(logStamp()) NOTHING ONLY off from outside: nothing to do (v89: the ticks decide)"); return }
            guard let nothing = self.others.first(where: { Phones.isPhone($0.iface) && NothingOnly.isNothing($0.name) }) else {
                self.show("NOTHING ONLY: the Nothing is not on the USB cable", Ink.red, for: 30); return
            }
            self.outsideTicks([nothing.name], "ConnectionKeeperNothingOnly on")
        }
    }

    // v89: NOTHING ONLY (v81) folded into the ticks: a mode left on would overrule every tick in ck-aggregate.
    func foldNothingOnly() {
        guard NothingOnly.on else { return }
        NothingOnly.set(false)
        appendLog("\(logStamp()) v89: NOTHING ONLY switched off, folded into the ticks (tick only the Nothing for the same)")
        DispatchQueue.global().async { Aggregation.requestRescan() }
    }

    // The state word and its colour for a row.
    func tickState(_ e: TickEntry, ticked: Bool) -> (word: String, color: NSColor) {
        if let f = tickFlash[e.name], f.until > Date() { return ("⇄ " + f.word, Ink.amber) }
        guard let o = e.other else {
            if e.inRange { return ticked ? ("JOINING", Ink.amber) : ("IN RANGE", Ink.dim) }
            return ticked ? ("NOT HERE", Ink.grey) : ("GONE", Ink.grey)
        }
        if deadIfaces.contains(o.iface) { return ("NO DATA", Ink.amber) }
        if ticked {
            if let l = agg?.lines.first(where: { $0.device == o.iface }) { return l.alive ? ("IN USE", Ink.green) : ("NO ANSWER", Ink.red) }
            if let s = o.sameAs { return (s, Ink.amber) }
            return ("JOINING", Ink.amber)
        }
        if o.ms == nil { return ("NO NET", Ink.grey) }
        if let s = o.sameAs { return (s, Ink.grey) }
        if tickedNames.isEmpty, o.iface == iface { return ("MAC'S OWN", Ink.green) }
        return ("READY", Ink.text)
    }
}
