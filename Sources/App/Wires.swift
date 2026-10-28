// WIRES OR WI-FI (v21, request 39, Marko 28.10.2026: "a toggle button right in the interface: wire or Wi-Fi ... I am
// afraid of Wi-Fi, and I think it burns my brain ... So we go wires only"). A switch on the first row, beside ⚙.
// WIRES: the Mac's Wi-Fi off, the TP-Link's Wi-Fi off, the phone's hotspot (and its Wi-Fi) off, and the aggregation's
// ticks moved to the cable. WI-FI: what was on before put back. The work is the script ck-wires (Tools/, in the app's
// Resources), so the same steps run from a terminal: `ck-wires wires|wifi|status`.
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
    func setupWires() {
        wiresSwitch.segmentCount = 2
        wiresSwitch.setLabel("WIRES", forSegment: 0)
        wiresSwitch.setLabel("WI-FI", forSegment: 1)
        wiresSwitch.trackingMode = .selectOne
        wiresSwitch.controlSize = .small
        wiresSwitch.font = .systemFont(ofSize: 11, weight: .bold)
        wiresSwitch.target = self
        wiresSwitch.action = #selector(pickWires)
        wiresSwitch.selectedSegment = Wires.on ? 0 : 1
        wiresSwitch.toolTip = "WIRES: every radio off (the Mac's Wi-Fi, the TP-Link's Wi-Fi, the phone's hotspot), cables only.\nWI-FI: the radios back as they were."
        wiresSwitch.translatesAutoresizingMaskIntoConstraints = false
        wiresSwitch.setContentHuggingPriority(.required, for: .horizontal)
    }

    @objc func pickWires() {
        let wires = wiresSwitch.selectedSegment == 0
        if wires == Wires.on && !wiresBusy { return }
        if wiresBusy { wiresSwitch.selectedSegment = Wires.on ? 0 : 1; return }
        wiresBusy = true
        wiresSwitch.isEnabled = false
        appendLog("\(logStamp()) WIRES asked on the stripe: \(wires ? "wires only" : "Wi-Fi back")")
        show(wires ? "WIRES: switching every radio off…" : "WI-FI: switching the radios back on…", Ink.amber, for: 120)
        DispatchQueue.global().async {
            let a = Wires.run(wires)
            DispatchQueue.main.async {
                self.wiresBusy = false
                self.wiresSwitch.isEnabled = true
                self.wiresSwitch.selectedSegment = Wires.on ? 0 : 1
                guard let a else { self.show("\(wires ? "WIRES" : "WI-FI"): no answer from ck-wires", Ink.red, for: 30); return }
                let tip = a.said.joined(separator: "\n") + String(format: "\n(%.0f s)", a.seconds)
                if a.failed.isEmpty {
                    self.show(wires ? "WIRES: radios off, cable only ✓" : "WI-FI: radios back ✓", Ink.green, for: 20, tip: tip)
                } else {
                    self.show("\(wires ? "WIRES" : "WI-FI"): not done: " + a.failed.joined(separator: ", "), Ink.red, for: 60, tip: tip)
                }
                self.layoutLines(); self.scanLines()
            }
        }
    }
}
