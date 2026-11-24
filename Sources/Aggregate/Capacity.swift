// THE LINE WITH THE MOST ROOM (request 112, 24.11.2026; the coordinator's brief after the night's measurements).
//
// Measured in CROATIA (no relay) with the cable (27-31 Mbit/s) and the hotspot (70-105) ticked: 8 parallel streams gave
// 76-105 (mean 89), the same as the hotspot alone, 74 % of the bytes on the hotspot; one stream got 83 or 33 depending on
// where it landed. Two causes in the v47/v62 choice, (rate + 2 Mbit/s per busy connection) / capacity + connect time:
//   1. capacity = the largest of the stored test, the peak and the probe. The cable's stored number had been averaged down
//      to 9 Mbit/s (86.33.92.240 in aggregate-speeds.json at 02:10, /status "capacity 9"): a line thought slow gets
//      connections only once the other holds ten times as many, so it never carries enough to show its real speed;
//   2. a burst of new connections (a download manager's 8 at once) all saw rate 0: the 2 Mbit/s per connection was the
//      only thing spreading them, a count, not a room.
// Now each new connection goes where it can expect the most:
//   expected = max(free room, fair share);  free room = capacity - what the line carries now (0 while connections placed
//   in the last 2 s have not shown their speed yet: they will take it); fair share = capacity / (busy connections + 1)
//   score    = connect time + 16 Mbit (a 2 MB piece) / expected        (lower wins; a dead line 1e9 as before)
// So long parallel streams fill the line with room until it is full, then the next one; a single stream on idle lines
// goes to the biggest capacity (with a quick connect breaking near-ties for small requests).
// The capacity (`est`), with a floor and a decay so an idle line never looks infinitely free nor dead:
//   - MEASURED FULL: when one more connection starts moving >= 512 KB per 2 s on a line that already had one or more
//     such, the line's delivered rate 2-4 s later is compared with the 2 s before: a gain under 30 % of one connection's
//     share means the line was full (the connections only share it), and `full` = that rate (one TCP connection over 4G
//     is limited by its round trip, so "two connections" alone never says "full": the gain does). A later higher rate
//     raises `full` at once. For 10 minutes after a verdict est = max(full, the v47 peak) x 1.1; the stored test and the
//     probe are not trusted over it (a stored 100 on a line that now gives 30 is corrected the same way);
//   - NOT MEASURED in the last 10 minutes: the v47 capacity (stored test, peak with its 10 min half-life, probe), but at
//     least half of the best other line's estimate: an unknown line is tried with a few streams and measured, never
//     starved by an old number (the 9 above);
//   - never below 1 Mbit/s.
// Kept as they were: the v47 rate, peak and probes (Balance.swift), the race to the next line after 1 s (Failover.swift),
// usable() and the standby, the same-line rules (sameLine), the download line first for a big host (DownloadRule.reorder).
import Foundation

final class LineRoom {
    var full = 0.0, fullAt = Date.distantPast           // the rate while the line was full, and when
    var placed: [Date] = []                              // connections given to this line, kept 2 s (not yet measured)
    var flows: [Int32: (bytes: Int, since: Date)] = [:]  // bytes per connection in its current 2 s window
    var bulk = 0                                         // connections moving >= 512 KB per 2 s (last tick)
    var est = 0.0, measured = false                      // last tick's capacity, for /status and the log
    var lastBytes = 0, history: [Double] = []            // delivered Mbit/s of each of the last 10 seconds
    var trial: (before: Double, bulk: Int, at: Int)?     // one more connection began: the rate before, the count, the tick
    var ticks = 0
}

var legacyLoad = aggEnv["CK_AGG_LEGACY_LOAD"] != nil      // the v62 formula, for a comparison (selftest --legacy)
let roomKeep: TimeInterval = 600, roomYoung: TimeInterval = 2, roomFloor = 1.0, roomPiece = 16.0

extension Server {
    // the capacity this line is placed by (under the lock)
    func roomCapacity(_ u: Uplink, among ls: [Uplink], _ now: Date) -> (est: Double, measured: Bool) {
        let r = u.meter.room
        if now.timeIntervalSince(r.fullAt) < roomKeep && r.full > 0 { return (max(max(r.full, u.meter.peak) * 1.1, roomFloor), true) }
        let best = ls.filter { $0 !== u && $0.alive && !$0.standby }.map { o -> Double in
            let ro = o.meter.room
            return now.timeIntervalSince(ro.fullAt) < roomKeep && ro.full > 0 ? max(ro.full, o.meter.peak) * 1.1 : o.capacity
        }.max() ?? 0
        return (max(u.capacity, best * 0.5, roomFloor), false)
    }

    // what a new connection can expect on this line, Mbit/s (under the lock)
    func roomExpected(_ u: Uplink, among ls: [Uplink], _ now: Date) -> Double {
        let est = roomCapacity(u, among: ls, now).est
        let young = u.pending + u.meter.room.placed.filter { now.timeIntervalSince($0) < roomYoung }.count
        let free = young > 0 ? 0 : max(est - u.meter.rate, 0)
        let share = est / Double(u.busy(now) + 1)
        return max(free, share)
    }

    // lower is better: the time to bring a 2 MB piece; dead lines last (under the lock)
    func roomScore(_ u: Uplink, among ls: [Uplink], _ now: Date) -> Double {
        (u.alive ? 0 : 1e9) + (u.rttMs ?? 50) / 1000 + roomPiece / max(roomExpected(u, among: ls, now), 0.1)
    }

    // race()'s order: by room, the download line first for a big host (request 105); the first is marked young at once,
    // so the next connection of a burst already sees it (under the lock)
    func placementOrder(_ ls: [Uplink], host: String, _ now: Date) -> [Uplink] {
        let all = lines
        let scored = ls.map { ($0, roomScore($0, among: all, now)) }.sorted { $0.1 < $1.1 }.map { $0.0 }
        let order = DownloadRule.reorder(scored, host: host)
        if let first = order.first { first.meter.room.placed.append(now) }
        return order
    }

    // a connection's received bytes (relay, under the lock)
    func roomBytes(_ u: Uplink, _ c: Int32, _ n: Int, _ now: Date) {
        let r = u.meter.room
        if var f = r.flows[c], now.timeIntervalSince(f.since) < 2 { f.bytes += n; r.flows[c] = f } else { r.flows[c] = (n, now) }
    }
    func roomEnd(_ u: Uplink, _ c: Int32) { u.meter.room.flows[c] = nil }

    // once a second, after the meters (under the lock): the young and the bulk counted, the full verdict
    func roomTick(_ ls: [Uplink], _ now: Date) {
        for u in ls {
            let r = u.meter.room
            r.ticks += 1
            r.placed = r.placed.filter { now.timeIntervalSince($0) < roomYoung }
            r.flows = r.flows.filter { now.timeIntervalSince($0.value.since) < 4 }
            let bulkBefore = r.bulk
            r.bulk = r.flows.values.filter { $0.bytes >= 524_288 && now.timeIntervalSince($0.since) < 2.5 }.count
            let d = max(u.bytesDown - r.lastBytes, 0); r.lastBytes = u.bytesDown
            r.history.append(Double(d) * 8 / 1e6); if r.history.count > 10 { r.history.removeFirst() }
            func mean(_ a: ArraySlice<Double>) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
            let now1 = r.history.last ?? 0
            // a measured line that carries more than its verdict: the verdict was low
            if now.timeIntervalSince(r.fullAt) < roomKeep, r.full > 0, now1 > r.full * 1.05, r.history.count >= 2,
               mean(r.history.suffix(2)) > r.full { r.full = mean(r.history.suffix(2)); r.fullAt = now }
            if r.trial == nil, bulkBefore >= 1, r.bulk == bulkBefore + 1, r.history.count >= 3 {
                // the 2 s before this tick (the new one only began to count in this tick)
                r.trial = (mean(r.history.dropLast().suffix(2)), bulkBefore, r.ticks)
            }
            if let t = r.trial, r.ticks - t.at >= 4 {
                r.trial = nil
                let after = mean(r.history.suffix(2))
                if r.bulk > t.bulk, t.before >= 1 {
                    let one = t.before / Double(t.bulk)
                    if after - t.before < 0.3 * one {
                        let was = r.full
                        r.full = max(after, t.before); r.fullAt = now
                        if abs(was - r.full) > 0.2 * max(was, 1) {
                            log(String(format: "ROOM %@ is full at %.1f Mbit/s (%d → %d connections: %.1f → %.1f)", u.name, r.full, t.bulk, r.bulk, t.before, after))
                        }
                    }
                }
            }
            let (est, measured) = roomCapacity(u, among: ls, now)
            r.est = est; r.measured = measured
        }
    }

    func roomStatus(_ u: Uplink, _ now: Date) -> [String: Any] {
        let r = u.meter.room
        return ["capacity": (r.est * 10).rounded() / 10, "measured": r.measured, "full": (r.full * 10).rounded() / 10,
                "fullAgoS": r.fullAt == .distantPast ? -1 : Int(now.timeIntervalSince(r.fullAt)), "bulk": r.bulk,
                "expected": (roomExpected(u, among: lines, now) * 10).rounded() / 10]
    }
}

// `ck-aggregate room-selftest` (request 112, CI): the choice alone on emulated lines, no network. Each tick is one second
// of fluid TCP: a line shares its capacity between its connections, each connection at most `flow` Mbit/s (one TCP
// connection over a 4G round trip rarely fills the line alone); the server's own meters, room and race order run on it.
func roomSelftest(_ args: [String]) -> Never {
    func val(_ k: String, _ d: Double) -> Double { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? d }
    let slowCap = val("--slow", 30), fastCap = val("--fast", 90), flowCap = val("--flow", 18), stale = val("--stale", 9)
    let legacy = args.contains("--legacy")
    legacyLoad = legacy
    var fails = 0
    func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }

    // one scenario: `streams` long downloads opened `gap` s apart, `secs` s in all; the bytes per line and the total
    func run(_ title: String, streams: Int, gap: Double, secs: Int, slowSaved: Double, fastSaved: Double) -> (total: Double, slow: Double, fast: Double, firstOn: String) {
        let s = Server()
        let slow = Uplink(iface: "lo0", name: "slow", gateway: nil, gatewayMAC: nil, publicIP: "10.0.0.1")
        let fast = Uplink(iface: "lo0", name: "fast", gateway: nil, gatewayMAC: nil, publicIP: "10.0.0.2")
        slow.mbps = slowSaved; fast.mbps = fastSaved; slow.rttMs = 25; fast.rttMs = 45
        s.lines = [slow, fast]
        var conns: [(line: Uplink, fd: Int32)] = []
        var bytes: [String: Double] = ["slow": 0, "fast": 0]
        var firstOn = ""
        var t = Date(timeIntervalSince1970: 1_000_000), opened = 0, nextOpen = 0.0, clock = 0.0, steps = 0
        let step = 0.1, from = gap * Double(streams - 1) + 3                     // measured once every stream is open + 3 s
        while clock < Double(secs) {
            while opened < streams && clock >= nextOpen {
                s.lock.lock()
                let order: [Uplink] = legacy ? s.lines.sorted { s.load($0, t) < s.load($1, t) } : s.placementOrder(s.lines, host: "files.example", t)
                let u = order[0]; let fd = Int32(1000 + opened)
                u.active += 1; u.connections += 1; u.seen[fd] = t
                s.lock.unlock()
                if opened == 0 { firstOn = u.name }
                conns.append((u, fd)); opened += 1; nextOpen += gap
            }
            // fluid sharing: each line gives its connections min(flow, the rest shared out evenly)
            for u in [slow, fast] {
                let cap = u === slow ? slowCap : fastCap
                let mine = conns.filter { $0.line === u }
                guard !mine.isEmpty else { continue }
                let each = min(flowCap, cap / Double(mine.count))
                for c in mine {
                    let n = Int(each * 1e6 / 8 * step)
                    s.lock.lock(); u.bytesDown += n; u.seen[c.fd] = t; s.roomBytes(u, c.fd, n, t); s.lock.unlock()
                    if clock >= from { bytes[u.name, default: 0] += Double(n) }
                }
            }
            steps += 1; clock = Double(steps) * step; t = t.addingTimeInterval(step)
            if steps % 10 == 0 {                                                  // the balance loop's second
                s.lock.lock()
                for u in s.lines {
                    let m = u.meter
                    let d = max(u.bytesDown - m.lastBytes, 0); m.lastBytes = u.bytesDown
                    m.rate = m.rate * 0.67 + Double(d) * 8 / 1e6 * 0.33
                    m.peak = max(m.peak * 0.99885, m.rate)
                }
                s.roomTick(s.lines, t)
                s.lock.unlock()
            }
        }
        let span = Double(secs) - from
        let sl = bytes["slow"]! * 8 / 1e6 / span, fa = bytes["fast"]! * 8 / 1e6 / span
        let split = "slow \(conns.filter { $0.line === slow }.count), fast \(conns.filter { $0.line === fast }.count)"
        print(String(format: "%@: %.1f Mbit/s (slow %.1f of %.0f, fast %.1f of %.0f; connections %@)", title, sl + fa, sl, slowCap, fa, fastCap, split))
        return (sl + fa, sl, fa, firstOn)
    }

    print("room-selftest\(legacy ? " (the v47/v62 choice, for comparison)" : ""): lines slow \(Int(slowCap)) + fast \(Int(fastCap)) Mbit/s, one connection at most \(Int(flowCap))")
    let need = 1.2 * fastCap
    func both(_ r: (total: Double, slow: Double, fast: Double, firstOn: String), _ what: String) {
        check(r.total >= need, String(format: "%@: %.1f >= 1.2 x %.0f = %.0f Mbit/s", what, r.total, fastCap, need))
        check(r.slow >= 0.85 * slowCap && r.fast >= 0.85 * fastCap,
              String(format: "%@: both lines near their caps (slow %.1f >= %.1f, fast %.1f >= %.1f)", what, r.slow, 0.85 * slowCap, r.fast, 0.85 * fastCap))
    }
    both(run("a. 8 streams at once, both stored numbers right", streams: 8, gap: 0, secs: 20, slowSaved: slowCap, fastSaved: fastCap), "a. 8 at once")
    both(run("b. 8 streams at once, the slow line stored at \(Int(stale)) (stale)", streams: 8, gap: 0, secs: 20, slowSaved: stale, fastSaved: fastCap * 0.8), "b. 8 at once, stale")
    both(run("c. 8 streams, one every 0.5 s", streams: 8, gap: 0.5, secs: 24, slowSaved: slowCap, fastSaved: fastCap), "c. one every 0.5 s")
    both(run("d. 8 streams, one every 3 s, the slow line stale", streams: 8, gap: 3, secs: 40, slowSaved: stale, fastSaved: fastCap * 0.8), "d. one every 3 s, stale")
    both(run("e. 16 streams at once, the slow line stale", streams: 16, gap: 0, secs: 20, slowSaved: stale, fastSaved: fastCap * 0.8), "e. 16 at once, stale")
    let one = run("f. one stream", streams: 1, gap: 0, secs: 10, slowSaved: slowCap, fastSaved: fastCap)
    check(one.firstOn == "fast", "f. one stream lands on the faster line (it went to \(one.firstOn))")
    let oneStale = run("g. one stream, the slow line stale", streams: 1, gap: 0, secs: 10, slowSaved: stale, fastSaved: fastCap * 0.8)
    check(oneStale.firstOn == "fast", "g. one stream, slow line stale: the faster line (it went to \(oneStale.firstOn))")
    print("  not checked (no choice can know better before it measures):")
    _ = run("   h. one stream, the FAST line stored at 20, below the slow line", streams: 1, gap: 0, secs: 10, slowSaved: slowCap, fastSaved: 20)
    _ = run("   i. 8 streams one every 3 s, the slow line stored HIGH at 100", streams: 8, gap: 3, secs: 40, slowSaved: 100, fastSaved: fastCap)
    print(fails == 0 ? "ROOM SELFTEST PASS" : "ROOM SELFTEST FAIL: \(fails)")
    exit(fails == 0 || legacy ? 0 : 1)
}
