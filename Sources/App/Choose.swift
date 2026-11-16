// WI-FI · CABLE · BOTH (v49, request 69, Marko 13.11.2026: "put check marks at the top ... Wi-Fi: if I click that, Wi-Fi is
// enabled in the system. Cable: ... Both: aggregation works with both. If I click on Wi-Fi or Wired, I have a list of all
// wired and Wi-Fi connections currently available, and I can check mark which I want to use").
//   WI-FI  alone: the Wi-Fi is first in macOS's service order, the cable stays but second; aggregation off.
//   CABLE  alone: the ticked cables (USB LAN adapters, phones) first, the Wi-Fi after them; aggregation off.
//   BOTH   aggregation over the ticked lines (the Wi-Fi network in use + the ticked cables), the existing mechanism.
// A click on the word WI-FI opens the networks in range (tick one to join it); on CABLE the wired interfaces and
// phones (tick the ones to use). The service order is changed with `networksetup -ordernetworkservices` (no password).
// A line that is NO DATA (Health.swift) goes below a working one in every mode.
import AppKit

enum LinkChoice: String { case wifi, cable, both }

enum ServiceOrder {
    struct Svc { let name: String; let device: String?; let wifi: Bool }

    static func list() -> [Svc] {
        let lines = shell("/usr/sbin/networksetup", ["-listnetworkserviceorder"]).out.components(separatedBy: "\n")
        var out: [Svc] = []
        for (i, line) in lines.enumerated() {
            guard let r = line.range(of: #"^\([0-9*]+\) "#, options: .regularExpression), i + 1 < lines.count else { continue }
            let info = lines[i + 1]
            let dev = info.range(of: #"Device: ([a-z0-9]+)\)"#, options: .regularExpression).map { String(info[$0].dropFirst("Device: ".count).dropLast()) }
            out.append(Svc(name: String(line[r.upperBound...]), device: dev, wifi: info.contains("Hardware Port: Wi-Fi")))
        }
        return out
    }

    // Returns what it did, nil when the order is right already. Dead lines go last, but only while a line with data remains.
    static func apply(_ c: LinkChoice, cable: Set<String>?, dead: Set<String>) -> String? {
        let cur = list()
        guard !cur.isEmpty else { return nil }
        let live = cur.filter { s in s.device != nil && !dead.contains(s.device!) && Net.ipAddress(s.device!) != nil }
        let useDead = live.isEmpty ? Set<String>() : dead
        func rank(_ s: Svc) -> Int {
            var r = 0
            switch c {
            case .wifi: r = s.wifi ? 0 : 1
            case .cable: r = (!s.wifi && s.device != nil && (cable == nil || cable!.contains(s.name))) ? 0 : 1
            case .both: r = 0
            }
            return r + (s.device.map { useDead.contains($0) } == true ? 10 : 0)
        }
        let new = cur.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element.name)
        if new == cur.map(\.name) { return nil }
        let r = shell("/usr/sbin/networksetup", ["-ordernetworkservices"] + new)
        return r.status == 0 && !r.out.contains("rror") ? "\(new.joined(separator: " > "))" : "failed: " + r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ChoiceQueue { static let lock = NSLock(); static var pending: LinkChoice?; static var running = false }

extension Stripe {
    static let cableKey = "cableTicks"
    // nil = every cable (nothing chosen yet)
    static func cableTicks() -> Set<String>? { (UserDefaults.standard.array(forKey: cableKey) as? [String]).map(Set.init) }

    var choice: LinkChoice {
        if Aggregation.on { return .both }
        if let s = UserDefaults.standard.string(forKey: "linkChoice"), let c = LinkChoice(rawValue: s) { return c }
        return iface.map { isWiFi($0) } == false ? .cable : .wifi
    }

    func makeTick(_ sel: Selector, id: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: "", target: self, action: sel)
        b.appearance = NSAppearance(named: .darkAqua)
        b.setAccessibilityIdentifier(id)
        return b
    }

    func noDataLabel() -> NSTextField {
        let l = label(textWidth("NO DATA", monoFont), font: .monospacedSystemFont(ofSize: 11, weight: .bold))
        l.stringValue = "NO DATA"
        l.textColor = Ink.amber
        l.alphaValue = 0
        l.toolTip = "Amber: the line is connected but no data comes through it (an HTTPS probe through it fails). It is ignored until its probes succeed for a minute."
        return l
    }

    func showChoice() {
        let c = choice
        for (b, w, mine) in [(wifiTick, wifiLabel, LinkChoice.wifi), (cableTick, cableLabel, .cable), (bothTick, bothLabel, .both)] {
            let want: NSControl.StateValue = c == mine ? .on : .off
            if b.state != want { b.state = want }
            w.contentTintColor = c == mine ? Ink.green : Ink.text
            b.setAccessibilityValue(c == mine ? "on" : "off")
        }
        let wifi = Net.wifiInterface()
        wifiNoData.alphaValue = deadIfaces.contains { $0 == wifi } ? 1 : 0
        cableNoData.alphaValue = deadIfaces.contains { $0 != wifi } ? 1 : 0
    }

    @objc func tickWifi() { setChoice(.wifi) }
    @objc func tickCable() { setChoice(.cable) }
    @objc func tickBoth() { setChoice(.both) }

    func setChoice(_ c: LinkChoice) {
        let was = choice
        UserDefaults.standard.set(c.rawValue, forKey: "linkChoice")
        appendLog("\(logStamp()) CHOICE \(was.rawValue) → \(c.rawValue) (ticked on the stripe)")
        showChoice()
        show(c == .wifi ? "WI-FI: the Mac on Wi-Fi, the cable second" : c == .cable ? "CABLE: the ticked cables first" : "BOTH: aggregation over the ticked lines", Ink.green, for: 8)
        // v86: ONE serial queue, latest wins: a tick during a running job only replaces what waits; the job loops until
        // nothing waits, so two switch jobs never overlap (stripe ticks and the outside notification both come here).
        ChoiceQueue.lock.lock()
        ChoiceQueue.pending = c
        let start = !ChoiceQueue.running
        if start { ChoiceQueue.running = true }
        ChoiceQueue.lock.unlock()
        guard start else { appendLog("\(logStamp()) CHOICE \(c.rawValue) queued (a switch is running; the latest wins)"); return }
        DispatchQueue.global().async {
            while true {
                ChoiceQueue.lock.lock()
                let next = ChoiceQueue.pending
                ChoiceQueue.pending = nil
                if next == nil { ChoiceQueue.running = false }
                ChoiceQueue.lock.unlock()
                guard let c = next else { return }
                let dead = DispatchQueue.main.sync { self.deadIfaces }
                let sem = DispatchSemaphore(value: 0)
                if c == .both {
                    var names: [String] = []
                    if let w = Net.wifiInterface(), Net.ipAddress(w) != nil { names.append(Net.displayName(w)) }
                    let ticks = Stripe.cableTicks()
                    for s in Net.lanServices() where Net.ipAddress(s.device) != nil && (ticks == nil || ticks!.contains(s.name)) { names.append(s.name) }
                    if names.isEmpty { names = Aggregation.selected }
                    Aggregation.selected = names
                    DispatchQueue.main.async { self.switchMode(true) { sem.signal() } }
                    _ = sem.wait(timeout: .now() + 90)
                } else if Aggregation.on {
                    DispatchQueue.main.async { self.switchMode(false) { sem.signal() } }
                    _ = sem.wait(timeout: .now() + 90)
                }
                if let said = ServiceOrder.apply(c, cable: Stripe.cableTicks(), dead: dead) { appendLog("\(logStamp()) ORDER (\(c.rawValue)): \(said)") }
            }
        }
    }

    // The lists: rows are views, so a tick does not close the menu (as the JOIN section).
    func listItem(_ menu: NSMenu, _ title: String, ticked: Bool, enabled: Bool = true, id: String, action: Selector) {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        b.state = ticked ? .on : .off
        b.isEnabled = enabled
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.font = .menuFont(ofSize: 0)
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        b.frame = NSRect(x: 20, y: 2, width: 370, height: 20)
        v.addSubview(b)
        let item = NSMenuItem(); item.view = v
        menu.addItem(item)
    }
    func listHead(_ menu: NSMenu, _ title: String) {
        let h = NSMenuItem(title: title, action: nil, keyEquivalent: ""); h.isEnabled = false
        menu.addItem(h)
    }

    func refreshWifiScan() {
        guard Date().timeIntervalSince(wifiScanAt) > 15 else { return }
        wifiScanAt = Date()
        DispatchQueue.global().async {
            var names = Net.wifiInRange()
            if let w = Net.wifiInterface(), let cur = Net.currentSSID(w) { names.insert(cur) }
            DispatchQueue.main.async { self.wifiScan = names.sorted() }
        }
    }

    @objc func openWifiList() {
        refreshWifiScan()
        show("WI-FI: …", Ink.amber, for: 6)   // v86: the shell calls run off the main thread; the list opens when they are done
        DispatchQueue.global().async {
            let cur = Net.wifiInterface().flatMap { Net.currentSSID($0) }
            DispatchQueue.main.async { self.popWifiList(cur) }
        }
    }

    func popWifiList(_ cur: String?) {
        let menu = NSMenu(); menu.autoenablesItems = false
        listHead(menu, "WI-FI networks in range: tick the one to use")
        let names = Set(wifiScan + (cur.map { [$0] } ?? [])).sorted()
        if names.isEmpty { listHead(menu, "  scanning… open this list again in a few seconds") }
        // v81 (request 89): a phone's hotspot is never joined here (the Nothing only by its USB cable)
        for n in names {
            let hot = CableOnly.isPhoneHotspot(n)
            listItem(menu, hot ? n + "   (phone hotspot: not used, the Nothing only by cable)" : n, ticked: n == cur && !hot, enabled: !hot, id: n, action: #selector(pickWifiNetwork(_:)))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: wifiLabel.bounds.height + 4), in: wifiLabel)
    }

    @objc func pickWifiNetwork(_ b: NSButton) {
        guard let ssid = b.identifier?.rawValue, let w = Net.wifiInterface() else { return }
        if CableOnly.isPhoneHotspot(ssid) { show("\(ssid) is a phone hotspot: not used (the Nothing only by its USB cable)", Ink.amber, for: 15); return }
        appendLog("\(logStamp()) WI-FI network ticked on the stripe: \(ssid)")
        show("WI-FI: joining \(ssid)…", Ink.amber, for: 60)
        DispatchQueue.global().async {
            let r = Net.currentSSID(w) == ssid ? (ok: true, detail: "already on it") : Join.wifi(ssid, w)
            appendLog("\(logStamp()) WI-FI join \(ssid): \(r.ok ? "ok" : "failed") (\(r.detail))")
            DispatchQueue.main.async {
                self.show(r.ok ? "WI-FI: on \(ssid)" : "WI-FI: could not join \(ssid): \(r.detail)", r.ok ? Ink.green : Ink.red, for: 15)
                if self.choice == .wifi { self.setChoice(.wifi) }
                self.scanLines()
            }
        }
    }

    @objc func openCableList() {
        show("CABLE: …", Ink.amber, for: 6)   // v86: the shell calls run off the main thread
        DispatchQueue.global().async {
            let svcs = Net.lanServices().map { (s: $0, up: Net.ipAddress($0.device) != nil, shown: Net.shown($0.name, $0.device)) }
            DispatchQueue.main.async { self.popCableList(svcs) }
        }
    }

    func popCableList(_ svcs: [(s: (name: String, device: String), up: Bool, shown: String)]) {
        let menu = NSMenu(); menu.autoenablesItems = false
        listHead(menu, "CABLE: wired interfaces and phones, tick the ones to use")
        let ticks = Stripe.cableTicks()
        var any = false
        for x in svcs {
            let dead = deadIfaces.contains(x.s.device)
            listItem(menu, x.shown + (dead ? "   NO DATA" : x.up ? "" : "   (no address)") + (roleWord(x.s.device).map { "   \($0)" } ?? ""), ticked: ticks == nil || ticks!.contains(x.s.name), id: x.s.name, action: #selector(pickCable(_:)))
            any = true
        }
        for o in others where Phones.isPhone(o.iface) {
            listItem(menu, o.name + (o.sameAs.map { "   (\($0))" } ?? "   (phone over adb)") + (roleWord(o.iface).map { "   \($0)" } ?? ""), ticked: o.sameAs == nil && (ticks == nil || ticks!.contains(o.name)), enabled: o.sameAs == nil, id: o.name, action: #selector(pickCable(_:)))
            any = true
        }
        if !any { listHead(menu, "  no wired interface found") }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: cableLabel.bounds.height + 4), in: cableLabel)
    }

    @objc func pickCable(_ b: NSButton) {
        guard let name = b.identifier?.rawValue else { return }
        let on = b.state == .on
        let phones = others.filter { Phones.isPhone($0.iface) }.map(\.name)
        DispatchQueue.global().async {
            let all = Array(Set(Net.lanServices().map(\.name) + phones))
            DispatchQueue.main.async {
                var s = Stripe.cableTicks() ?? Set(all)
                if on { s.insert(name) } else { s.remove(name) }
                UserDefaults.standard.set(Array(s).sorted(), forKey: Stripe.cableKey)
                appendLog("\(logStamp()) CABLE ticks: \(s.isEmpty ? "none" : s.sorted().joined(separator: " + "))")
                if self.choice != .wifi { self.setChoice(self.choice) }
            }
        }
    }
}
