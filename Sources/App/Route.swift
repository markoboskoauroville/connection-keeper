// MAC · AGGREGATE · BOTH (v43, request 59, Marko 1.11.2026: "a simple on-off switch ... between Mac connection or
// aggregate connection ... If I have my computer on Wi-Fi, I can just switch to Wi-Fi and ignore bypassing the
// aggregate. If I'm on aggregate, I'm bypassing the Wi-Fi of my computer ... Third option is both. That means there is
// a fallback mechanism: if aggregate doesn't work, then local is working").
// Three words on the stripe's first row; the chosen one green, the others grey:
//   MAC        the Mac on its own connection (its Wi-Fi or cable); the aggregation off, nothing of it in the way.
//   AGGREGATE  every connection through the joined lines (utun99); the Mac's own Wi-Fi is not used, even when the
//              aggregation stumbles (the root helper never steps aside while the file `tunnel-strict` is there).
//   BOTH       through the joined lines, and when they stop carrying traffic the helper steps aside within seconds and
//              the Mac's own connection carries everything until the lines work again (the fail-open of v14–v42).
import AppKit

enum Route: String {
    case mac, aggregate, both
    static let strictFlag = Paths.support.appendingPathComponent("tunnel-strict")
    static var current: Route {
        guard Aggregation.on else { return .mac }
        return FileManager.default.fileExists(atPath: strictFlag.path) ? .aggregate : .both
    }
    static func setStrict(_ on: Bool) {
        if on { FileManager.default.createFile(atPath: strictFlag.path, contents: Data("strict\n".utf8)) }
        else { try? FileManager.default.removeItem(at: strictFlag) }
    }
    // The installed helper knows `tunnel-strict` from v43 on; an older one treats AGGREGATE as BOTH.
    static var helperKnowsStrict: Bool {
        let s = (try? String(contentsOfFile: "/Library/PrivilegedHelperTools/com.mantra.connectionkeeper.tunnel/version", encoding: .utf8)) ?? ""
        return (Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) >= 43
    }
}

extension Stripe {
    @objc func pickMac() { pickRoute(.mac) }
    @objc func pickAggregateRoute() { pickRoute(.aggregate) }
    @objc func pickBoth() { pickRoute(.both) }

    func pickRoute(_ r: Route) {
        let was = Route.current
        guard r != was else { showRoute(); return }
        appendLog("\(logStamp()) ROUTE \(was.rawValue) → \(r.rawValue) (pressed on the stripe)")
        Route.setStrict(r == .aggregate)
        if (r == .mac) != (was == .mac) { switchMode(r != .mac) }
        if r == .aggregate && Aggregation.tunnelInstalled && !Route.helperKnowsStrict {
            show("AGGREGATE: the helper installed is older than v43 and still falls back to the Mac (sudo ./tunnel.sh install)", Ink.amber, for: 12)
        } else {
            show(r == .mac ? "MAC: the Mac on its own connection" : r == .aggregate ? "AGGREGATE: only the joined lines, never the Mac's Wi-Fi" : "BOTH: the joined lines, the Mac's own connection when they fail", Ink.green, for: 8)
        }
        showRoute()
    }

    func showRoute() {
        let r = Route.current
        for (w, mine) in [(macWord, Route.mac), (aggWord, .aggregate), (bothWord, .both)] {
            w.contentTintColor = r == mine ? Ink.green : Ink.grey
            w.setAccessibilityValue(r == mine ? "on" : "off")
        }
    }
}
