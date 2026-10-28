// WIRES OR WI-FI (v21, request 39, Marko 28.10.2026: "a toggle button right in the interface: wire or Wi-Fi ... I am
// afraid of Wi-Fi, and I think it burns my brain ... So we go wires only"). WIRES: the Mac's Wi-Fi off, the TP-Link's
// Wi-Fi off, the phone's hotspot (and its Wi-Fi) off, and the aggregation's ticks moved to the cable. WI-FI: what was on
// before put back. The work is the script ck-wires (Tools/, in the app's Resources), so the same steps run from a
// terminal: `ck-wires wires|wifi|status`.
// v25 (request 43: "this switch between wires and Wi-Fi can go under the settings gear icon. It doesn't need to be
// visible all the time"): ⚙ opens a small menu, WIRES and WI-FI on top (the one in force ticked), Settings under them.
import AppKit

enum Wires {
    static let modeFile = Paths.support.appendingPathComponent("wires")
    static var on: Bool { ((try? String(contentsOf: modeFile, encoding: .utf8)) ?? "").hasPrefix("wires") }
    static var script: String { Bundle.main.resourceURL!.appendingPathComponent("ck-wires").path }

    struct Answer: Decodable { let said: [String]; let failed: [String]; let seconds: Double }

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
