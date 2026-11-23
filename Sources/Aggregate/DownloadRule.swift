// THE DOWNLOAD LINE IN CROATIA (request 105; the line and the size: Sources/Shared/DownloadLine.swift).
// A TCP connection cannot be moved once it is open, and its size is not known when it opens. So:
//   - a connection that has received more than the threshold (50 MB unless ⚙ says otherwise) is a big download: its
//     destination (the host as the client named it: a name, or the address the tunnel hands over) is remembered for
//     10 minutes, and every NEW connection to it is dialled first on the download line;
//   - a plain-HTTP request with a Range header (a download manager, a resumed download) marks its host the same way at once;
//   - the download line is only the FIRST try: when it is dead or gone it is not first, and race() still starts the next
//     line after 1 s or at its failure, so nothing ever waits for it.
// Through FRANKFURT (the bond) a connection is a stream of the relay and this rule does not apply; the hook the bond
// scheduler needs is written in TAKEOVER.md (request 105).
import Foundation

enum DownloadRule {
    static let keep: TimeInterval = 600
    private static let lock = NSLock()
    private static var big: [String: Date] = [:]          // host → remembered until

    static func remember(_ host: String, why: String) {
        guard !host.isEmpty, DownloadLine.line != nil else { return }
        lock.lock(); let fresh = (big[host] ?? .distantPast) < Date(); big[host] = Date().addingTimeInterval(keep); lock.unlock()
        if fresh { log("DOWNLOAD \(host): \(why); new connections to it go first to \(DownloadLine.line ?? "?") for \(Int(keep / 60)) min") }
    }

    // a connection's received bytes went from `before` to `after`: true the moment it passes the threshold
    @discardableResult
    static func counted(_ host: String, before: Int, after: Int, line: String) -> Bool {
        guard DownloadLine.line != nil else { return false }
        let t = DownloadLine.thresholdBytes
        guard before < t, after >= t else { return false }
        remember(host, why: "passed \(Int(DownloadLine.thresholdMB)) MB on \(line)")
        return true
    }

    static func isBig(_ host: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        big = big.filter { $0.value > now }
        return big[host] != nil
    }

    static var remembered: [String] { lock.lock(); defer { lock.unlock() }; let now = Date(); return big.filter { $0.value > now }.keys.sorted() }

    // race()'s order with the download line first, for a remembered host and a live download line; else unchanged
    static func reorder(_ order: [Uplink], host: String) -> [Uplink] {
        guard let name = DownloadLine.line, isBig(host), let i = order.firstIndex(where: { $0.name == name && $0.alive }) else { return order }
        var o = order
        let u = o.remove(at: i)
        return [u] + o
    }

    // what /status says
    static func status(_ lines: [Uplink]) -> [String: Any] {
        guard let name = DownloadLine.line else { return ["line": NSNull(), "thresholdMB": DownloadLine.thresholdMB] }
        let u = lines.first { $0.name == name }
        return ["line": name, "thresholdMB": DownloadLine.thresholdMB, "present": u != nil, "alive": u?.alive ?? false,
                "bigHosts": remembered.count, "appliesThroughBond": false]
    }
}

// `ck-aggregate download-selftest` (request 105, CI): the rule on fake lines, no network.
func downloadSelftest() -> Never {
    guard aggEnv["CK_DL_FILE"] != nil else { print("download-selftest: set CK_DL_FILE to a scratch file (it writes the download line)"); exit(2) }
    var fails = 0
    func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
    let a = Uplink(iface: "en17", name: "AX88179B", gateway: nil, gatewayMAC: nil, publicIP: "1.1.1.1")
    let b = Uplink(iface: "en0", name: "Something", gateway: nil, gatewayMAC: nil, publicIP: "2.2.2.2")
    let order = [b, a]                                    // the balance's own order: Something first
    DownloadLine.set(line: "AX88179B", thresholdMB: 50)
    check(DownloadRule.reorder(order, host: "files.example").first === b, "no big transfer yet: the balance's order (Something first)")
    // a fake big transfer to host H on Something, counted in 1 MB blocks as relay() counts them
    var got = 0, crossedAt = -1
    for i in 0..<80 { let before = got; got += 1_048_576; if DownloadRule.counted("files.example", before: before, after: got, line: "Something") { crossedAt = i } }
    check(crossedAt == 47, "the transfer counts as big once past 50 MB (at block \(crossedAt + 1) of 1 MB)")
    check(DownloadRule.reorder(order, host: "files.example").first === a, "a new connection to the big host goes first to the download line AX88179B")
    check(DownloadRule.reorder(order, host: "other.example").first === b, "another host keeps the balance's order")
    a.alive = false
    let dead = DownloadRule.reorder(order, host: "files.example")
    check(dead.first === b && dead.count == 2, "the download line dead: the big host falls back to the balance's order (nothing waits)")
    a.alive = true
    DownloadLine.set(line: nil)
    check(DownloadRule.reorder(order, host: "files.example").first === b, "no download line marked: today's balance")
    DownloadLine.set(line: "Gone line")
    DownloadRule.remember("files.example", why: "test")
    check(DownloadRule.reorder(order, host: "files.example").first === b, "the download line not among the lines: the balance's order")
    print(fails == 0 ? "download-selftest: all passed" : "download-selftest: \(fails) failed")
    exit(fails == 0 ? 0 : 1)
}
