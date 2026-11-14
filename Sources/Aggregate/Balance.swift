// THE LOAD BALANCE (v47, request 66, Marko 1.11.2026: "Google Pixel 7, in the middle of transfer, I switch to 5G ... this
// connection is not used at all ... Everything going through mantra ... please build it professionally").
//
// Found 1.11.2026 10:50: the server chose a line by (busy + 1) / mbps, and mbps was the last `ck-aggregate test` stored
// by public IP. The Pixel's 5G address had never been tested, so it was the default 10 Mbit/s for five hours, while
// mantra kept its old 36. Measured alone at that moment: the Pixel on 5G 128–140 Mbit/s, on 4G 39.5, mantra 12.6–25
// (it carried the Chrome download). So every heavy connection went to the slowest line: 1,944 MB over mantra, 263 over
// the Pixel, though the Pixel had taken more connections (its share were the small, idle ones).
//
// Now every line knows three things, refreshed by itself:
//   rate      what it carries right now, down, Mbit/s (its byte counters every second, smoothed over ~3 s)
//   peak      the most it has carried lately (decays with a half-life of ~10 min, so a line that got slower drops)
//   probed    a short measurement of its own: 2 downloads for 3 s, when a line appears with no known speed, when a
//             phone's radio changes (4G ↔ 5G) and when its public address changes; never more than once a minute
// capacity = the largest of the three (and the stored test), and a new connection goes to the line with the lowest
// expected load: (rate + 2 Mbit/s for each busy connection) / capacity. An idle 130 Mbit/s line beats a full 25 one.
//
// What it cannot do: move a connection that is already open. One TCP connection is one road to the server at the other
// end; moving it mid-way would need a server of ours on the far side (a VPS, Speedify-style bonding). A single big
// download spreads over the lines only when it is opened as several connections: ck-net (pieces over every line),
// a download manager, or Chrome with chrome://flags/#enable-parallel-downloading.

import Foundation

final class LineMeter {
    var rate = 0.0, peak = 0.0, probed: Double?, probedAt = Date.distantPast
    var lastBytes = 0, radio: String?, probeIP: String?, probing = false
    var settleAt: Date?                                  // a second look ~30 s after a radio change
}

extension Uplink {
    var capacity: Double { max(mbps, meter.peak, meter.probed ?? 0, 0.5) }
}

extension Server {
    // Lower is better. Dead lines last.
    // v62 (request 83, QC fix 3): + the line's connect time (60 ms → 0.06, 5 ms → 0.005): with the lines idle a new
    // connection (a page, an API call) takes the quick line; under load the throughput term (≥ 0.05 per busy
    // connection on a 40 Mbit/s line) still spreads the work over every line.
    func load(_ u: Uplink, _ now: Date) -> Double {
        (u.alive ? 0 : 1e9) + (u.meter.rate + 2 * Double(u.busy(now) + 1)) / u.capacity + (u.rttMs ?? 50) / 1000
    }

    func startBalance() {
        Thread.detachNewThread { [self] in
            var tick = 0
            let boost = Boost()                                  // v48: 5G only for big downloads (Boost.swift)
            while true {
                sleep(1); tick += 1
                lock.lock()
                for u in lines {
                    let m = u.meter
                    let d = max(u.bytesDown - m.lastBytes, 0); m.lastBytes = u.bytesDown
                    let now = Double(d) * 8 / 1e6
                    m.rate = m.rate * 0.67 + now * 0.33
                    m.peak = max(m.peak * 0.99885, m.rate)          // half-life ~10 min
                }
                let ls = lines
                let total = ls.reduce(0) { $0 + $1.meter.rate }
                lock.unlock()
                if !aggQuiet {                                   // v71: a draining or interim server changes nothing
                    boostTick(boost, total: total, phones: ls.compactMap { $0.cellular ? $0.phone : nil })
                    if tick % 10 == 0 { for u in ls { checkRadio(u) } }
                }
                if tick % 30 == 0 { logBalance(ls) }
            }
        }
    }

    // A phone's radio type and every line's public address; a change (or no speed known at all) is measured.
    func checkRadio(_ u: Uplink) {
        lock.lock(); let m = u.meter, known = Lines.savedSpeeds()[u.publicIP ?? u.iface] != nil; lock.unlock()
        var reason: String?
        if let p = u.phone, let r = PhoneRadio.read(p.serial)?["type"] as? String {
            lock.lock(); let was = m.radio; m.radio = r; lock.unlock()
            if let was, was != r { reason = "radio \(was) → \(r)" }
        }
        lock.lock()
        if m.probeIP != nil && m.probeIP != u.publicIP { reason = reason ?? "public address \(m.probeIP!) → \(u.publicIP ?? "?")" }
        if m.probed == nil && !known { reason = reason ?? "no speed known" }
        if reason == nil, let t = m.settleAt, Date() >= t { reason = "settled after the radio change"; m.settleAt = nil }
        // A radio change is always measured (Marko switches 4G ↔ 5G by hand and expects the line to follow at once);
        // anything else at most once a minute.
        let radioChange = reason?.hasPrefix("radio") == true || reason?.hasPrefix("settled") == true
        let tooSoon = m.probing || (!radioChange && Date().timeIntervalSince(m.probedAt) < 60)
        if reason != nil && !tooSoon { m.probing = true }
        lock.unlock()
        guard let reason, !tooSoon else { return }
        // 1.11.2026 10:52: probed 4 s after 5G → 4G it read 6.7 Mbit/s; the same 4G gave 39.5 a minute later. The
        // radio needs a few seconds after the switch: wait 6 s, and look again 30 s later.
        if reason.hasPrefix("radio") { sleep(6) }
        let mbps = probe(u)
        lock.lock()
        m.probing = false; m.probedAt = Date(); m.probeIP = u.publicIP
        if reason.hasPrefix("radio") { m.settleAt = Date().addingTimeInterval(30) }
        if mbps > 0.5 {
            // after a radio change the old peak is history: a line that got slower must not keep its 5G number
            if reason.hasPrefix("radio") || reason.hasPrefix("public") { m.peak = 0 }
            let carried = m.rate
            m.probed = reason.hasPrefix("settled") ? max(mbps + carried, m.probed ?? 0) : mbps + carried                     // what it gave the probe on top of what it already carried
            u.mbps = m.probed!
        }
        let cap = u.capacity
        lock.unlock()
        if mbps > 0.5 { Lines.saveSpeeds([u.publicIP ?? u.iface: cap]) }
        log(String(format: "%@: %@: measured %.1f Mbit/s, capacity now %.0f", u.name, reason, mbps, cap))
    }

    // Two downloads for 3 s through this one line, Mbit/s. ~25 MB on a 5G line.
    func probe(_ u: Uplink) -> Double {
        let how = u.phone.map { ["-x", "socks5h://127.0.0.1:\($0.port)"] } ?? ["--interface", u.iface]
        var procs: [(Process, Pipe)] = []
        for i in 0..<2 {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-s", "-o", "/dev/null", "-m", "3", "-w", "%{size_download}"] + how + [speedURLs[i]]
            p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            try? p.run(); procs.append((p, pipe))
        }
        var bytes = 0.0
        for (p, pipe) in procs {
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            bytes += Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return bytes * 8 / 3 / 1e6
    }

    func logBalance(_ ls: [Uplink]) {
        lock.lock()
        let now = Date()
        let s = ls.map { u in String(format: "%@ %.1f of %.0f Mbit/s, %d busy", u.name, u.meter.rate, u.capacity, u.busy(now)) }
        let moving = ls.contains { $0.meter.rate > 1 }
        lock.unlock()
        if moving { log("balance: " + s.joined(separator: " | ")) }
    }
}
