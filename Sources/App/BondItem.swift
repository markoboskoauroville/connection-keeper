// THE BOND ON THE STRIPE (v75, request 85 item 5): one word in the first row, from ck-aggregate's /status "bond":
//   ⇄ FRA 2 · 48↓        green: through Frankfurt, two legs (bonded), 48 Mbit/s coming in now; ⇄ FRA 1: one line, private
//   ⇄ ASIDE              amber: on, but stepping aside (one line, draining …): new connections go direct
//   ⇄ DOWN               red: on, no leg to the relay (STRICT: nothing goes out)
//   ⇄ off                grey: bond.json says off
// " STRICT" follows when PRIVACY STRICT is on. A click runs ck-bondcheck (bundled) and shows its lines.
import AppKit

extension Stripe {
    func showBond() {
        DispatchQueue.global().async {
            let r = shell("/usr/bin/curl", ["-s", "-m", "1", "http://127.0.0.1:\(aggPort)/status"], timeout: 2)
            let b = (try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any])?["bond"] as? [String: Any]
            let cfg = BondConfigFile.load()
            DispatchQueue.main.async { self.paintBond(b, strict: (cfg?.on ?? false) && (cfg?.strict ?? false)) }
        }
    }

    func paintBond(_ b: [String: Any]?, strict: Bool) {
        let now = Date()
        var text = "⇄ off", color = Ink.grey, tip = "Bond off (bond.json): every connection on the Mac's own lines"
        if let b, (b["on"] as? Bool) == true {
            let legs = (b["legs"] as? [[String: Any]] ?? []).filter { ($0["alive"] as? Bool) == true }
            let lines = Set(legs.compactMap { $0["line"] as? String })
            let mb = b["mbDown"] as? Double ?? 0
            var mbps = 0.0
            if let (t, m) = bondLast, now.timeIntervalSince(t) > 0.5 { mbps = max(0, (mb - m) * 8 / now.timeIntervalSince(t)) }
            bondLast = (now, mb)
            if let why = b["bypass"] as? String {
                text = lines.isEmpty ? "⇄ DOWN" : "⇄ ASIDE"; color = lines.isEmpty ? Ink.red : Ink.amber
                tip = "Bond: \(why)"
            } else {
                text = String(format: "⇄ FRA %d · %.0f↓", lines.count, mbps); color = Ink.green
                tip = "Through the relay (\(b["server"] as? String ?? "?")): " + lines.sorted().joined(separator: " + ") + String(format: "; %.1f Mbit/s in now", mbps)
                    + (lines.count == 1 ? ". One line: private (the home address hidden), no speed gain." : ". Bonded.") + " Click: the full check."
            }
        }
        if strict { text += " STRICT"; tip += ". PRIVACY STRICT: with no leg up, nothing goes over the home line." }
        let cfg = BondConfigFile.load()
        frankfurtWord.contentTintColor = cfg?.on == true ? Ink.green : Ink.grey
        croatiaWord.contentTintColor = cfg?.on == true ? Ink.grey : Ink.green
        frankfurtWord.isEnabled = cfg != nil
        if cfg == nil { frankfurtWord.toolTip = "No bond.json yet: ck-aggregate bond-init, then the relay's token" }
        if bondWord.title != text { bondWord.title = text }
        bondWord.contentTintColor = color
        bondWord.toolTip = tip
        bondWord.setAccessibilityValue(text)
    }

    // FRANKFURT / CROATIA: bond.json "on"; the server sees it within a second. Seamless: going to Croatia the open
    // connections through Frankfurt finish there (the client drains) and every new one goes direct at once; going to
    // Frankfurt, new connections go direct until the first leg is up (a fraction of a second), then through the relay.
    @objc func pickFrankfurt() { pickWay(true) }
    @objc func pickCroatia() { pickWay(false) }
    func pickWay(_ frankfurt: Bool) {
        guard BondConfigFile.update({ $0.on = frankfurt }) else { show("no bond.json: ck-aggregate bond-init first", Ink.amber, for: 6); return }
        appendLog("\(logStamp()) WAY: \(frankfurt ? "FRANKFURT (through the relay)" : "CROATIA (straight over the Mac's own lines)")")
        show(frankfurt ? "FRANKFURT: through the relay" : "CROATIA: straight over your lines", Ink.green, for: 4)
        frankfurtWord.contentTintColor = frankfurt ? Ink.green : Ink.grey
        croatiaWord.contentTintColor = frankfurt ? Ink.grey : Ink.green
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showBond() }
    }

    @objc func bondPressed() {
        let script = Bundle.main.resourceURL?.appendingPathComponent("ck-bondcheck").path ?? ""
        show("checking the bond…", Ink.amber, for: 8)
        DispatchQueue.global().async {
            let r = shell("/usr/bin/python3", [script], timeout: 40)
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = r.status == 0 ? "Bond check: PASS" : "Bond check: FAIL"
                a.informativeText = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
                a.addButton(withTitle: "OK")
                a.runModal()
            }
        }
    }
}
