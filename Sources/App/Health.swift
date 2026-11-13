// THE DEAD-LINE FALLBACK (v49, request 69, Marko 13.11.2026: "If it's connected, it doesn't have any data throughput, and
// I have Wi-Fi. It needs to understand that there is no data. It needs not to fight with it. It needs to ignore it").
// Every 20 s, each line with a gateway gets an HTTPS probe bound to its own interface (curl --interface en17
// https://www.google.com, 15 s at most). Two failures in a row: the line is NO DATA (amber on the stripe), moved
// below a working line in macOS's service order, and left out of the aggregation (Aggregation.dead, read by
// ck-aggregate). It comes back when its probes have succeeded for a full minute. Nothing is switched off and on; every
// change is one line in ~/Library/Logs/connection-keeper.log. A phone over adb is not probed here (its own
// check is Phones.online).
import AppKit

struct ProbeState { var fails = 0; var goodSince: Date?; var dead = false }

extension Stripe {
    func startHealth() {
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.probeLines() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.probeLines() }
    }

    func probeLines() {
        if probing { return }
        probing = true
        DispatchQueue.global().async {
            var targets: [String] = []
            for i in Net.activeInterfaces() {
                let gw = shell("/usr/sbin/ipconfig", ["getoption", i, "router"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !gw.isEmpty { targets.append(i) }
            }
            var results: [String: Bool] = [:]
            let lock = NSLock(), group = DispatchGroup()
            for i in targets {
                group.enter()
                DispatchQueue.global().async {
                    let r = shell("/usr/bin/curl", ["-s", "-o", "/dev/null", "-m", "15", "--interface", i, "-w", "%{http_code}", "https://www.google.com"], timeout: 18)
                    let code = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ok = r.status == 0 && (code.hasPrefix("2") || code.hasPrefix("3"))
                    lock.lock(); results[i] = ok; lock.unlock()
                    group.leave()
                }
            }
            group.wait()
            DispatchQueue.main.async { self.probing = false; self.absorbProbes(results) }
        }
    }

    func absorbProbes(_ results: [String: Bool]) {
        var changed = false
        for (i, ok) in results {
            var s = probeState[i] ?? ProbeState()
            if ok {
                s.fails = 0
                if s.dead {
                    if s.goodSince == nil { s.goodSince = Date() }
                    if Date().timeIntervalSince(s.goodSince!) >= 60 {
                        s.dead = false; s.goodSince = nil; changed = true
                        appendLog("\(logStamp()) NO DATA over: \(i) carries data again (probes succeeded for a minute); it may be first again")
                    }
                }
            } else {
                s.goodSince = nil; s.fails += 1
                if s.fails >= 2 && !s.dead {
                    s.dead = true; changed = true
                    appendLog("\(logStamp()) NO DATA: \(i) is up but the HTTPS probe through it fails; moved below a working line, left out of the aggregation")
                }
            }
            probeState[i] = s
        }
        for i in probeState.keys where results[i] == nil { if probeState[i]?.dead == true { changed = true }; probeState[i] = nil }
        let dead = Set(probeState.filter { $0.value.dead }.keys)
        if changed || dead != deadIfaces { deadIfaces = dead; applyDead() }
        showChoice()
    }

    // The dead lines' names for the aggregation, and the service order again.
    func applyDead() {
        let dead = deadIfaces
        let c = choice
        DispatchQueue.global().async {
            Aggregation.dead = dead.map { Net.displayName($0) }.sorted()
            if let said = ServiceOrder.apply(c, cable: Stripe.cableTicks(), dead: dead) { appendLog("\(logStamp()) ORDER (dead lines last): \(said)") }
        }
    }
}
