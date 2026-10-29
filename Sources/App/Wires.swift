// WIRES OR WI-FI (v21, request 39, Marko 28.10.2026: "a toggle button right in the interface: wire or Wi-Fi ... I am
// afraid of Wi-Fi, and I think it burns my brain ... So we go wires only"). WIRES: the Mac's Wi-Fi off, the TP-Link's
// Wi-Fi off, the phone's hotspot (and its Wi-Fi) off, and the aggregation's ticks moved to the cable. WI-FI: what was on
// before put back. The work is the script ck-wires (Tools/, in the app's Resources), so the same steps run from a
// terminal: `ck-wires wires|wifi|status`.
// v25 (request 43: "this switch between wires and Wi-Fi can go under the settings gear icon. It doesn't need to be
// visible all the time"): ⚙ opens a small menu, WIRES and WI-FI on top (the one in force ticked), Settings under them.
// v34 (request 51, Marko 29.10.2026: "each connection ... the icon, which looks like a Wi-Fi icon, which is grayed out or
// active ... Temporarily, I can enable Wi-Fi sharing of any active connection by that button ... Wi-Fi is never for this
// computer; it is for other devices on the network. Wi-Fi is never 5 GHz"): in WIRES each cable or phone row has a Wi-Fi
// icon, grey off, green on; a click shares that line to the house (the cable through the TP-Link's 2.4 GHz radio, a
// phone through its hotspot) or stops it. The Mac's Wi-Fi stays off. The work is `ck-wires share <line> on|off`.
import AppKit

enum Wires {
    static let modeFile = Paths.support.appendingPathComponent("wires")
    static var on: Bool { ((try? String(contentsOf: modeFile, encoding: .utf8)) ?? "").hasPrefix("wires") }
    static var script: String { Bundle.main.resourceURL!.appendingPathComponent("ck-wires").path }

    struct Answer: Decodable { let said: [String]; let failed: [String]; let seconds: Double }

    static let shareFile = Paths.support.appendingPathComponent("wifi-share.json")
    static func shares() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: shareFile))) ?? [:]
    }
    static func share(_ line: String, _ on: Bool) -> Answer? {
        let r = shell("/usr/bin/python3", [script, "share", line, on ? "on" : "off", "--json"], timeout: 200)
        guard let last = r.out.split(separator: "\n").last else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: Data(last.utf8))
    }
    // The phones' hotspots read again (one may be switched on the phone by hand); the router's stays as last switched.
    static func refreshShares() { _ = shell("/usr/bin/python3", [script, "share-status", "--json"], timeout: 30) }

    // Off the main thread: the router and the phone take 20-60 s.
    static func run(_ wires: Bool) -> Answer? {
        let r = shell("/usr/bin/python3", [script, wires ? "wires" : "wifi", "--json"], timeout: 300)
        guard let line = r.out.split(separator: "\n").last else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: Data(line.utf8))
    }
}

extension Stripe {
    @objc func gearMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, sel, picked) in [("WIRES   every radio off, cables only", #selector(pickWiresOn), Wires.on),
                                     ("WI-FI   the radios back as they were", #selector(pickWiresOff), !Wires.on)] {
            let i = NSMenuItem(title: wiresBusy && picked ? title + "   (switching…)" : title, action: sel, keyEquivalent: "")
            i.target = self
            i.state = picked ? .on : .off
            i.isEnabled = !wiresBusy
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        s.target = self
        menu.addItem(s)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: gear.bounds.height + 4), in: gear)
    }

    @objc func pickWiresOn() { setWires(true) }
    @objc func pickWiresOff() { setWires(false) }

    func setWires(_ wires: Bool) {
        if wiresBusy || wires == Wires.on { return }
        wiresBusy = true
        appendLog("\(logStamp()) WIRES asked on the stripe: \(wires ? "wires only" : "Wi-Fi back")")
        show(wires ? "WIRES: switching every radio off…" : "WI-FI: switching the radios back on…", Ink.amber, for: 120)
        DispatchQueue.global().async {
            let a = Wires.run(wires)
            DispatchQueue.main.async {
                self.wiresBusy = false
                guard let a else { self.show("\(wires ? "WIRES" : "WI-FI"): no answer from ck-wires", Ink.red, for: 30); return }
                let tip = a.said.joined(separator: "\n") + String(format: "\n(%.0f s)", a.seconds)
                if a.failed.isEmpty {
                    self.show(wires ? "WIRES ✓" : "WI-FI ✓", Ink.green, for: 15, tip: tip)
                } else {
                    self.show("\(wires ? "WIRES" : "WI-FI"): not done: " + a.failed.joined(separator: ", "), Ink.red, for: 60, tip: tip)
                }
                self.layoutLines(); self.scanLines()
            }
        }
    }
}

extension Stripe {
    func showShare(_ r: LineRow, _ o: OtherLine) {
        let can = Wires.on && !o.wifi && (Phones.isPhone(o.iface) || o.iface.hasPrefix("en"))
        r.wifi.isHidden = !can
        guard can else { return }
        r.wifi.identifier = NSUserInterfaceItemIdentifier(o.name)
        let busy = sharing.contains(o.name), on = Wires.shares()[o.name] == "on"
        r.wifi.contentTintColor = busy ? Ink.amber : on ? Ink.green : Ink.grey
        let how = Phones.isPhone(o.iface) ? "its hotspot" : "the TP-Link's 2.4 GHz Wi-Fi"
        r.wifi.toolTip = busy ? "switching…" : on
            ? "Wi-Fi ON: \(o.name) is shared to the other devices in the house through \(how). Click: off."
            : "Wi-Fi off. Click: share \(o.name) to the other devices in the house through \(how) for a while (never this Mac)."
    }

    @objc func toggleShare(_ b: NSButton) {
        guard let line = b.identifier?.rawValue, !sharing.contains(line) else { return }
        let on = Wires.shares()[line] != "on"
        sharing.insert(line)
        b.contentTintColor = Ink.amber
        appendLog("\(logStamp()) SHARE asked on the stripe: \(line) Wi-Fi \(on ? "on" : "off")")
        show("WI-FI \(on ? "ON" : "OFF"): \(line)…", Ink.amber, for: 120)
        DispatchQueue.global().async {
            let a = Wires.share(line, on)
            DispatchQueue.main.async {
                self.sharing.remove(line)
                let tip = (a?.said ?? []).joined(separator: "\n") + String(format: "\n(%.0f s)", a?.seconds ?? 0)
                if let a, a.failed.isEmpty {
                    self.show("WI-FI \(on ? "ON" : "OFF") ✓ \(line)", Ink.green, for: 15, tip: tip)
                } else {
                    self.show(a?.said.last ?? "WI-FI: no answer from ck-wires", Ink.red, for: 60, tip: tip)
                }
                self.layoutLines()
            }
        }
    }
}
