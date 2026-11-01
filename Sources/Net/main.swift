// ck-net (v43, request 58, Marko 1.11.2026): TEST SPEED, TEST HEALTH and the AGGREGATE DOWNLOAD MONITOR's engine.
//
//   ck-net test health            every line at once: ping 1.1.1.1 for 10 s (min/avg/max, jitter, loss), five HTTPS
//                                 requests (connect, TLS, first byte), its public address and Cloudflare site, a phone's
//                                 radio (5G/4G, RSRP, SINR). Almost no data.
//   ck-net test speed             every line alone (download 4 streams, then upload 3 streams, 5 s each, with a ping
//                                 running under the load), then all lines together. About 500 MB of SIM data.
//   ck-net get <url> [--to <dir|file>] [--name N] [--id ID]
//                                 one file in 8 MB pieces over every line at once (the cable bound to its device, each
//                                 phone through its ck-phone), each piece written at its place in <file>.ckpart; a piece
//                                 cut in the middle is continued from its last byte on any line (the stitch). At the end
//                                 the SHA-256 is checked when the server gave one (Hugging Face), then the file is renamed.
//   ck-net resume <id>            go on with a download whose program stopped (crash, kill, a Mac restart)
//   ck-net stop <id>              stop it (it can be resumed)
//   ck-net list                   the downloads, one line each
//
// The results are JSON in Application Support/connection-keeper: linetest-health.json, linetest-speed.json (rewritten
// every half second while running, so the stripe's window draws them live), downloads/<id>.json. Every download is also
// reported to the Download Monitor (127.0.0.1:8833, /report), Marko's rule of 8.9.2026.
import Foundation
import CryptoKit

setvbuf(stdout, nil, _IOLBF, 0)
signal(SIGPIPE, SIG_IGN)

// MARK: - small things

final class Locked<T> {
    private var v: T
    private let l = NSLock()
    init(_ v: T) { self.v = v }
    func get() -> T { l.lock(); defer { l.unlock() }; return v }
    func set(_ n: T) { l.lock(); v = n; l.unlock() }
    @discardableResult func mutate<R>(_ f: (inout T) -> R) -> R { l.lock(); defer { l.unlock() }; return f(&v) }
}

func now() -> Double { Date().timeIntervalSince1970 }
func say(_ s: String) { print("\(logStamp()) \(s)") }
let curlPath = "/usr/bin/curl"
let support = Paths.support

func writeJSON(_ obj: Any, to url: URL) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return }
    let tmp = url.appendingPathExtension("tmp")
    try? d.write(to: tmp)
    _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    if !FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.moveItem(at: tmp, to: url) }
}
func readJSON(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}
func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

// MARK: - the lines

struct NetLine {
    let name: String, kind: String           // "cable" | "phone"
    let iface: String?, port: Int?, serial: String?
    var curl: [String] { kind == "phone" ? ["--socks5-hostname", "127.0.0.1:\(port ?? 0)"] : ["--interface", iface ?? ""] }
}

// The lines the aggregation knows (aggregate-lines.json), those the server says are alive; without the server, every
// remembered line whose device is here.
func currentLines() -> [NetLine] {
    let file = support.appendingPathComponent("aggregate-lines.json")
    guard let d = try? Data(contentsOf: file), let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
    let status = Aggregation.status()
    var out: [NetLine] = []
    for e in arr {
        guard let name = e["name"] as? String else { continue }
        if let st = status, let l = st.lines.first(where: { $0.name == name }), !l.alive { continue }
        if let serial = e["serial"] as? String, let port = e["port"] as? Int {
            out.append(NetLine(name: name, kind: "phone", iface: nil, port: port, serial: serial))
        } else if let iface = e["iface"] as? String, if_nametoindex(iface) != 0 {
            out.append(NetLine(name: name, kind: "cable", iface: iface, port: nil, serial: nil))
        }
    }
    return out
}

// MARK: - curl as a byte stream

// Runs curl with its body on stdout, handing each block to `onData` as it comes; returns curl's exit status, the HTTP
// code (written to stderr by -w) and the bytes. `cancel` set → curl is stopped.
final class Cancel { var flag = false }

@discardableResult
func curlStream(_ args: [String], cancel: Cancel? = nil, onData: (UnsafeRawBufferPointer) -> Bool) -> (status: Int32, code: Int, bytes: Int64) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: curlPath)
    p.arguments = ["-s", "-L", "-o", "-", "-w", "%{stderr}CKCODE %{http_code}\n"] + args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, 0, 0) }
    var errData = Data()
    let errDone = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); errDone.signal() }
    let fd = out.fileHandleForReading.fileDescriptor
    var buf = [UInt8](repeating: 0, count: 256 * 1024)
    var total: Int64 = 0
    var stopped = false
    while true {
        let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        if n <= 0 { break }
        total += Int64(n)
        let keep = buf.withUnsafeBytes { onData(UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
        if !keep || (cancel?.flag ?? false) { stopped = true; p.terminate(); break }
    }
    if stopped { while read(fd, &buf, buf.count) > 0 {} }
    p.waitUntilExit()
    _ = errDone.wait(timeout: .now() + 2)
    try? out.fileHandleForReading.close(); try? err.fileHandleForReading.close()
    let code = String(decoding: errData, as: UTF8.self).components(separatedBy: "CKCODE ").last
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    return (stopped ? -2 : p.terminationStatus, code, total)
}

// An upload of random bytes fed through curl's stdin until `until`; each block counted when curl took it.
func curlUpload(_ args: [String], until: Double, onSent: (Int) -> Void) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: curlPath)
    p.arguments = ["-s", "-X", "POST", "-T", "-", "-H", "Content-Type: application/octet-stream", "-o", "/dev/null"] + args
    let inp = Pipe()
    p.standardInput = inp
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    var block = [UInt8](repeating: 0, count: 64 * 1024)
    for i in 0..<block.count { block[i] = UInt8.random(in: 0...255) }
    let fd = inp.fileHandleForWriting.fileDescriptor
    while now() < until && p.isRunning {
        let n = block.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n <= 0 { break }
        onSent(n)
    }
    try? inp.fileHandleForWriting.close()
    let deadline = now() + 3
    while p.isRunning && now() < deadline { usleep(50_000) }
    if p.isRunning { p.terminate() }
    p.waitUntilExit()
    return p.terminationStatus
}

// MARK: - ping

struct PingResult { var sent = 0, got = 0; var rtts: [Double] = []; var series: [[Double]] = [] }

// ICMP from the line itself: the cable bound to its device (ping -b), a phone from its own shell (adb shell ping).
func ping(_ l: NetLine, seconds: Int, t0: Double, into res: Locked<PingResult>, host: String = "1.1.1.1") {
    let p = Process()
    if l.kind == "phone", let adb = Phones.adb, let s = l.serial {
        p.executableURL = URL(fileURLWithPath: adb)
        p.arguments = ["-s", s, "shell", "ping", "-i", "0.2", "-w", "\(seconds)", "-W", "1", host]
    } else {
        p.executableURL = URL(fileURLWithPath: "/sbin/ping")
        p.arguments = ["-b", l.iface ?? "", "-i", "0.2", "-t", "\(seconds)", "-W", "1000", host]
    }
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return }
    let start = now()
    var pending = ""
    let fh = out.fileHandleForReading
    while true {
        let d = fh.availableData
        if d.isEmpty { break }
        pending += String(decoding: d, as: UTF8.self)
        while let nl = pending.firstIndex(of: "\n") {
            let line = String(pending[..<nl]); pending = String(pending[pending.index(after: nl)...])
            if let r = line.range(of: "time="), let ms = Double(line[r.upperBound...].prefix { "0123456789.".contains($0) }) {
                res.mutate { $0.got += 1; $0.rtts.append(ms); $0.series.append([r2(now() - t0), ms]) }
            }
        }
    }
    p.waitUntilExit()
    let sent = max(1, Int((now() - start) / 0.2))
    res.mutate { $0.sent = max($0.got, sent) }
}

func pingSummary(_ r: PingResult) -> [String: Any] {
    guard !r.rtts.isEmpty else { return ["sent": r.sent, "got": 0, "lossPct": 100.0] }
    let s = r.rtts.sorted()
    var jit = 0.0
    if r.rtts.count > 1 { for i in 1..<r.rtts.count { jit += abs(r.rtts[i] - r.rtts[i - 1]) }; jit /= Double(r.rtts.count - 1) }
    let loss = r.sent > 0 ? max(0, 100.0 * Double(r.sent - r.got) / Double(r.sent)) : 0
    return ["min": r1(s.first!), "avg": r1(s.reduce(0, +) / Double(s.count)), "max": r1(s.last!),
            "p95": r1(s[min(s.count - 1, Int(Double(s.count) * 0.95))]), "jitter": r1(jit),
            "sent": r.sent, "got": r.got, "lossPct": r1(loss)]
}

// MARK: - HTTPS timings, the public address, the radio

func httpTimings(_ l: NetLine, n: Int = 5) -> [String: Any] {
    var conn: [Double] = [], tls: [Double] = [], ttfb: [Double] = [], fails = 0
    for _ in 0..<n {
        let r = shell(curlPath, ["-s", "-o", "/dev/null", "-m", "6", "-w", "%{http_code} %{time_connect} %{time_appconnect} %{time_starttransfer}"]
                      + l.curl + ["https://www.google.com/generate_204"], timeout: 8)
        let f = r.out.split(separator: " ").compactMap { Double($0) }
        if r.status == 0, f.count == 4, f[0] == 204 { conn.append(f[1] * 1000); tls.append(f[2] * 1000); ttfb.append(f[3] * 1000) } else { fails += 1 }
    }
    func med(_ a: [Double]) -> Double? { a.isEmpty ? nil : r1(a.sorted()[a.count / 2]) }
    var o: [String: Any] = ["requests": n, "failed": fails]
    if let v = med(conn) { o["connectMs"] = v }
    if let v = med(tls) { o["tlsMs"] = v }
    if let v = med(ttfb) { o["firstByteMs"] = v }
    return o
}

func trace(_ l: NetLine) -> [String: String] {
    let r = shell(curlPath, ["-s", "-m", "6"] + l.curl + ["https://speed.cloudflare.com/cdn-cgi/trace"], timeout: 8)
    var o: [String: String] = [:]
    for line in r.out.split(separator: "\n") {
        let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
        if kv.count == 2, ["ip", "colo", "http", "tls", "loc"].contains(kv[0]) { o[kv[0]] = kv[1] }
    }
    return o
}

func radio(_ l: NetLine) -> [String: Any]? {
    guard l.kind == "phone", let s = l.serial else { return nil }
    return PhoneRadio.read(s)
}

// MARK: - grades

func latencyGrade(loadedPlus: Double?) -> String {
    guard let d = loadedPlus else { return "—" }
    switch d { case ..<5: return "A+"; case ..<30: return "A"; case ..<60: return "B"; case ..<200: return "C"; case ..<400: return "D"; default: return "F" }
}

// 0–100 from the idle ping and the requests: loss weighs most, then jitter, then the round trip.
func healthScore(_ p: [String: Any], _ h: [String: Any]) -> Int {
    var s = 100.0
    let loss = p["lossPct"] as? Double ?? 100
    s -= min(60, loss * 6)
    if let j = p["jitter"] as? Double { s -= min(20, max(0, j - 3) * 1.0) }
    if let a = p["avg"] as? Double { s -= min(20, max(0, a - 30) * 0.25) } else { s -= 20 }
    if let f = h["failed"] as? Int, let n = h["requests"] as? Int, n > 0 { s -= Double(f) / Double(n) * 30 }
    return max(0, Int(s.rounded()))
}
func scoreWord(_ s: Int) -> String { s >= 90 ? "excellent" : s >= 75 ? "good" : s >= 55 ? "fair" : s >= 30 ? "poor" : "bad" }

// MARK: - TEST HEALTH

func testHealth() {
    let out = support.appendingPathComponent("linetest-health.json")
    let lines = currentLines()
    let t0 = now()
    var doc: [String: Any] = ["kind": "health", "started": t0, "phase": "running: ping 10 s, HTTPS, radio on \(lines.count) lines", "running": true,
                              "lines": lines.map { ["name": $0.name, "kind": $0.kind] }]
    writeJSON(doc, to: out)
    say("TEST HEALTH on \(lines.map(\.name).joined(separator: ", "))")
    var results = [[String: Any]](repeating: [:], count: lines.count)
    let rl = NSLock()
    let pings = lines.map { _ in Locked(PingResult()) }
    let g = DispatchGroup()
    for (i, l) in lines.enumerated() {
        g.enter()
        DispatchQueue.global().async {
            let pg = DispatchGroup()
            pg.enter(); DispatchQueue.global().async { ping(l, seconds: 10, t0: t0, into: pings[i]); pg.leave() }
            let tr = trace(l)
            let h = httpTimings(l)
            let rad = radio(l)
            pg.wait()
            let p = pingSummary(pings[i].get())
            var r: [String: Any] = ["name": l.name, "kind": l.kind, "ping": p, "http": h, "pingSeries": pings[i].get().series]
            if let ip = tr["ip"] { r["publicIP"] = ip }
            if let c = tr["colo"] { r["colo"] = c }
            if let rad { r["radio"] = rad }
            let sc = healthScore(p, h)
            r["score"] = sc; r["word"] = scoreWord(sc)
            rl.lock(); results[i] = r; rl.unlock()
            g.leave()
        }
    }
    while g.wait(timeout: .now() + 0.5) == .timedOut {
        rl.lock()
        doc["lines"] = lines.enumerated().map { i, l -> [String: Any] in
            results[i].isEmpty ? ["name": l.name, "kind": l.kind, "pingSeries": pings[i].get().series] : results[i] }
        rl.unlock()
        writeJSON(doc, to: out)
    }
    doc["lines"] = results
    let scores = results.compactMap { $0["score"] as? Int }
    let overall = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
    doc["score"] = overall; doc["word"] = scoreWord(overall)
    doc["finished"] = now(); doc["running"] = false; doc["phase"] = "done"
    var verdict: [String] = []
    for r in results {
        let p = r["ping"] as? [String: Any] ?? [:]
        verdict.append("\(r["name"] ?? ""): \(r["word"] ?? "") (\(r["score"] ?? 0)/100), ping \(p["avg"] ?? "—") ms, jitter \(p["jitter"] ?? "—") ms, loss \(p["lossPct"] ?? "—") %")
    }
    doc["verdict"] = verdict
    writeJSON(doc, to: out)
    for v in verdict { say(v) }
    say("health \(overall)/100 (\(scoreWord(overall))) in \(Int(now() - t0)) s")
}

// MARK: - TEST SPEED

let downURL = "https://speed.cloudflare.com/__down?bytes=50000000"
let upURL = "https://speed.cloudflare.com/__up"

// Counts bytes per line into a series of 0.25 s bins; the speed is taken after the first second (TCP's slow start).
final class Meter {
    let t0: Double, start: Double
    let bytes = Locked<Int64>(0)
    var counted: Int64 = 0
    var series: [[Double]] = []
    var lastAt: Double
    var lastBytes: Int64 = 0
    var steadyFrom: (at: Double, bytes: Int64)?
    init(t0: Double) { self.t0 = t0; start = now(); lastAt = start }
    func add(_ n: Int) { bytes.mutate { $0 += Int64(n) } }
    func sample() {
        let t = now(), b = bytes.get()
        if t - lastAt > 0.05 { series.append([r2(t - t0), r1(Double(b - lastBytes) * 8 / (t - lastAt) / 1e6)]) }
        lastAt = t; lastBytes = b
        if steadyFrom == nil && t - start >= 1 { steadyFrom = (t, b) }
    }
    var mbps: Double {
        let t = now(), b = bytes.get()
        if let s = steadyFrom, t - s.at > 0.5 { return r1(Double(b - s.bytes) * 8 / (t - s.at) / 1e6) }
        return t - start > 0.2 ? r1(Double(b) * 8 / (t - start) / 1e6) : 0
    }
    var mb: Double { Double(bytes.get()) / 1e6 }
}

// Down (4 streams) or up (3 streams) on these lines at once for `secs`, with a ping on each line under the load.
func loadPhase(_ lines: [NetLine], up: Bool, secs: Double, t0: Double, publish: ([Meter], [Locked<PingResult>]) -> Void) -> ([Meter], [Locked<PingResult>], [Double]) {
    let meters = lines.map { _ in Meter(t0: t0) }
    let pings = lines.map { _ in Locked(PingResult()) }
    let until = now() + secs
    let g = DispatchGroup()
    for (i, l) in lines.enumerated() {
        g.enter(); DispatchQueue.global().async { ping(l, seconds: Int(secs), t0: t0, into: pings[i]); g.leave() }
        for _ in 0..<(up ? 3 : 4) {
            g.enter()
            DispatchQueue.global().async {
                if up {
                    while now() < until - 0.3 { _ = curlUpload(l.curl + ["-m", "\(Int(secs) + 2)", upURL], until: until) { meters[i].add($0) } }
                } else {
                    let c = Cancel()
                    while now() < until - 0.3 {
                        _ = curlStream(l.curl + ["-m", "\(Int(secs) + 2)", downURL], cancel: c) { b in meters[i].add(b.count); return now() < until }
                    }
                }
                g.leave()
            }
        }
    }
    while now() < until { usleep(250_000); meters.forEach { $0.sample() }; publish(meters, pings) }
    let rates = meters.map(\.mbps)      // read before the streams wind down
    _ = g.wait(timeout: .now() + 6)
    for m in meters { m.series.append([r2(now() - t0), 0]) }
    return (meters, pings, rates)
}

// quick (v43, request 61, the test at every start of the app): no line alone, all lines together 4 s down and 4 s up,
// each line's part counted; about 150 MB. Written to linetest-start.json for the stripe's bottom line.
func testSpeed(quick: Bool = false) {
    let out = support.appendingPathComponent(quick ? "linetest-start.json" : "linetest-speed.json")
    let lines = currentLines()
    let t0 = now()
    let secs = quick ? 4.0 : 5.0
    var doc: [String: Any] = ["kind": "speed", "started": t0, "running": true, "seconds": secs, "lines": lines.map { ["name": $0.name, "kind": $0.kind] }]
    var series: [String: [[Double]]] = [:]
    var pingSeries: [String: [[Double]]] = [:]
    var mbUsed = 0.0
    func publish(_ phase: String) { doc["phase"] = phase; doc["series"] = series; doc["pingSeries"] = pingSeries; doc["mbUsed"] = r1(mbUsed); writeJSON(doc, to: out) }
    say("TEST SPEED on \(lines.map(\.name).joined(separator: ", "))")

    // idle latency first, all lines together (3 s)
    publish("idle ping, 3 s")
    let idle = lines.map { _ in Locked(PingResult()) }
    let ig = DispatchGroup()
    for (i, l) in lines.enumerated() { ig.enter(); DispatchQueue.global().async { ping(l, seconds: 3, t0: t0, into: idle[i]); ig.leave() } }
    ig.wait()
    var rows: [[String: Any]] = lines.enumerated().map { i, l in
        let p = pingSummary(idle[i].get())
        pingSeries[l.name] = idle[i].get().series
        return ["name": l.name, "kind": l.kind, "idle": p]
    }
    doc["rows"] = rows

    // each line alone
    for (i, l) in lines.enumerated() where !quick {
        for up in [false, true] {
            let key = "\(l.name)|\(up ? "up" : "down")"
            let base = pingSeries[l.name] ?? []
            let (m, p, rs) = loadPhase([l], up: up, secs: secs, t0: t0) { ms, ps in
                series[key] = ms[0].series
                pingSeries[l.name] = base + ps[0].get().series
                publish("\(l.name) alone: \(up ? "upload" : "download") \(ms[0].mbps) Mbit/s")
            }
            let rate = rs[0]
            series[key] = m[0].series
            mbUsed += m[0].mb
            let lp = pingSummary(p[0].get())
            rows[i][up ? "upMbps" : "downMbps"] = rate
            rows[i][up ? "loadedUp" : "loadedDown"] = lp
            pingSeries[l.name] = base + p[0].get().series
            doc["rows"] = rows
            say("\(l.name) alone \(up ? "up" : "down"): \(rate) Mbit/s, ping under load \(lp["avg"] ?? "—") ms")
        }
        let idleAvg = (rows[i]["idle"] as? [String: Any])?["avg"] as? Double
        let ld = (rows[i]["loadedDown"] as? [String: Any])?["avg"] as? Double
        let lu = (rows[i]["loadedUp"] as? [String: Any])?["avg"] as? Double
        if let a = idleAvg {
            rows[i]["bloatDownMs"] = ld.map { r1($0 - a) } ?? NSNull()
            rows[i]["bloatUpMs"] = lu.map { r1($0 - a) } ?? NSNull()
            rows[i]["grade"] = latencyGrade(loadedPlus: max(ld.map { $0 - a } ?? 0, lu.map { $0 - a } ?? 0))
        }
        doc["rows"] = rows
    }

    // all lines together
    var together: [String: Any] = [:]
    for up in [false, true] {
        let (m, _, rates) = loadPhase(lines, up: up, secs: secs, t0: t0) { ms, _ in
            for (i, l) in lines.enumerated() { series["ALL|\(up ? "up" : "down")|\(l.name)"] = ms[i].series }
            publish("all lines together: \(up ? "upload" : "download") \(r1(ms.map(\.mbps).reduce(0, +))) Mbit/s")
        }
        for (i, l) in lines.enumerated() { series["ALL|\(up ? "up" : "down")|\(l.name)"] = m[i].series; mbUsed += m[i].mb }
        var per: [String: Double] = [:]
        for (i, l) in lines.enumerated() { per[l.name] = rates[i] }
        together[up ? "upMbps" : "downMbps"] = r1(rates.reduce(0, +))
        together[up ? "perLineUp" : "perLineDown"] = per
        say("ALL together \(up ? "up" : "down"): \(r1(rates.reduce(0, +))) Mbit/s")
    }
    let sumDown = rows.compactMap { $0["downMbps"] as? Double }.reduce(0, +)
    let sumUp = rows.compactMap { $0["upMbps"] as? Double }.reduce(0, +)
    if sumDown > 0, let d = together["downMbps"] as? Double { together["downEfficiencyPct"] = Int((d / sumDown * 100).rounded()) }
    if sumUp > 0, let u = together["upMbps"] as? Double { together["upEfficiencyPct"] = Int((u / sumUp * 100).rounded()) }
    doc["together"] = together
    doc["rows"] = rows
    doc["finished"] = now(); doc["running"] = false
    var verdict: [String] = []
    for r in rows {
        verdict.append("\(r["name"] ?? ""): ↓ \(r["downMbps"] ?? "—") ↑ \(r["upMbps"] ?? "—") Mbit/s, ping \(((r["idle"] as? [String: Any])?["avg"]) ?? "—") ms idle, latency grade \(r["grade"] ?? "—")")
    }
    verdict.append("ALL TOGETHER: ↓ \(together["downMbps"] ?? "—") ↑ \(together["upMbps"] ?? "—") Mbit/s (\(together["downEfficiencyPct"] ?? "—") % of the lines' sum down)")
    doc["verdict"] = verdict
    publish("done in \(Int(now() - t0)) s, \(Int(mbUsed)) MB of SIM data")
    for v in verdict { say(v) }
}

// MARK: - THE AGGREGATE DOWNLOAD

let downloads = support.appendingPathComponent("downloads")
let pieceSize: Int64 = 8 * 1024 * 1024

final class Piece { let s: Int64, e: Int64; var have: Int64; var busy = false
    init(_ s: Int64, _ e: Int64, _ h: Int64) { self.s = s; self.e = e; have = h }
    var len: Int64 { e - s + 1 }; var done: Bool { have >= len } }

final class LineStat { var bytes: Int64 = 0, pieces = 0, fails = 0, active = 0, streak = 0; var restUntil = 0.0; var last = ""
    var window: [(Double, Int64)] = [] }

final class Job {
    let id: String, url: String, dest: String, name: String
    var size: Int64 = 0, sha: String?
    var pieces: [Piece] = []
    let lock = NSLock()
    var stats: [String: LineStat] = [:]
    var events: [String] = []
    var breaks = 0, resumes = 0, started = now(), firstStarted = now()
    var fd: Int32 = -1
    var stopping = false
    var state = "starting"
    var window: [(Double, Int64)] = []
    var stateURL: URL { downloads.appendingPathComponent("\(id).json") }
    var part: String { dest + ".ckpart" }
    init(id: String, url: String, dest: String, name: String) { self.id = id; self.url = url; self.dest = dest; self.name = name }
    var have: Int64 { pieces.reduce(0) { $0 + min($1.have, $1.len) } }
    func event(_ s: String) { lock.lock(); events.append("\(logStamp()) \(s)"); if events.count > 40 { events.removeFirst(events.count - 40) }; lock.unlock(); say(s) }
}

func slug(_ s: String) -> String {
    String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }).split(separator: "-").joined(separator: "-")
}

// The size and the fingerprint, asked through the first line that answers (Hugging Face: X-Linked-Size / -ETag).
func probe(_ url: String, lines: [NetLine]) -> (Int64, String?)? {
    for l in lines + [NetLine(name: "Mac", kind: "cable", iface: nil, port: nil, serial: nil)] {
        let args = (l.iface == nil && l.kind == "cable" ? [] : l.curl) + ["-s", "-I", "-L", "-m", "15", url]
        let r = shell(curlPath, args, timeout: 18)
        guard r.status == 0 else { continue }
        var size: Int64?, linked: Int64?, sha: String?
        for line in r.out.components(separatedBy: "\r\n") {
            let low = line.lowercased()
            if low.hasPrefix("content-length:") { size = Int64(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) }
            if low.hasPrefix("x-linked-size:") { linked = Int64(line.dropFirst(14).trimmingCharacters(in: .whitespaces)) }
            if low.hasPrefix("x-linked-etag:") {
                let v = line.dropFirst(14).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                if v.count == 64, v.allSatisfy({ $0.isHexDigit }) { sha = v.lowercased() }
            }
        }
        if let s = linked ?? size, s > 0 { return (s, sha) }
    }
    return nil
}

func saveJob(_ j: Job) {
    j.lock.lock()
    let t = now()
    let have = j.have
    j.window.append((t, have)); j.window = j.window.filter { t - $0.0 <= 5 }
    let bps = j.window.count > 1 ? Double(have - j.window.first!.1) / max(0.1, t - j.window.first!.0) : 0
    var per: [String: Any] = [:]
    for (n, s) in j.stats {
        s.window.append((t, s.bytes)); s.window = s.window.filter { t - $0.0 <= 5 }
        let lb = s.window.count > 1 ? Double(s.bytes - s.window.first!.1) / max(0.1, t - s.window.first!.0) : 0
        per[n] = ["mbps": r1(lb * 8 / 1e6), "mb": r1(Double(s.bytes) / 1e6), "pieces": s.pieces, "fails": s.fails, "active": s.active,
                  "resting": s.restUntil > t, "last": s.last]
    }
    let doc: [String: Any] = [
        "id": j.id, "name": j.name, "url": j.url, "dest": j.dest, "part": j.part, "size": j.size, "sha256": j.sha ?? NSNull(),
        "pieceSize": pieceSize, "pieces": j.pieces.map { [$0.s, $0.e, $0.have] },
        "have": have, "pct": j.size > 0 ? r1(Double(have) * 100 / Double(j.size)) : 0,
        "mbps": r1(bps * 8 / 1e6), "etaSeconds": bps > 1000 ? Int(Double(j.size - have) / bps) : NSNull(),
        "piecesDone": j.pieces.filter(\.done).count, "piecesAll": j.pieces.count,
        "lines": per, "breaks": j.breaks, "resumes": j.resumes, "state": j.state, "pid": getpid(),
        "started": j.firstStarted, "updated": t, "events": j.events]
    j.lock.unlock()
    writeJSON(doc, to: j.stateURL)
}

func reportMonitor(_ j: Job, done: Bool = false) {
    let body: [String: Any] = ["id": "ck-\(j.id)", "name": "\(j.name) (aggregate)", "have_mb": r1(Double(j.have) / 1048576),
                               "want_mb": r1(Double(j.size) / 1048576), "done": done,
                               "info": "Aggregate Download Monitor (Network Aggregate Connection Keeper): \(j.url) → \(j.dest)"]
    guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
    var req = URLRequest(url: URL(string: "http://127.0.0.1:8833/report")!, timeoutInterval: 2)
    req.httpMethod = "POST"; req.httpBody = d; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
    _ = sem.wait(timeout: .now() + 3)
}

// One worker: takes the first piece nobody holds, fetches what it still lacks on its line, writes each block at its
// place; a cut leaves the piece with the bytes it has, for any line to continue (the stitch).
func worker(_ j: Job, _ l: NetLine) {
    let st: LineStat = { j.lock.lock(); defer { j.lock.unlock() }; if j.stats[l.name] == nil { j.stats[l.name] = LineStat() }; return j.stats[l.name]! }()
    while !j.stopping {
        if st.restUntil > now() { usleep(300_000); continue }
        j.lock.lock()
        let p = j.pieces.first { !$0.done && !$0.busy }
        p?.busy = true
        if p != nil { st.active += 1 }
        j.lock.unlock()
        guard let p else { return }
        let from = p.s + p.have
        let cancel = Cancel()
        var over = false
        let r = curlStream(l.curl + ["--connect-timeout", "8", "--speed-limit", "30000", "--speed-time", "8", "-m", "300",
                                     "-r", "\(from)-\(p.e)", j.url], cancel: cancel) { b in
            if j.stopping { return false }
            let off = p.s + p.have
            if off + Int64(b.count) > p.e + 1 { over = true; return false }
            var w = 0
            while w < b.count {
                let n = pwrite(j.fd, b.baseAddress! + w, b.count - w, off_t(off + Int64(w)))
                if n <= 0 { return false }
                w += n
            }
            j.lock.lock(); p.have += Int64(b.count); st.bytes += Int64(b.count); j.lock.unlock()
            return true
        }
        j.lock.lock()
        p.busy = false; st.active -= 1
        let ok = p.done
        j.lock.unlock()
        if ok {
            st.pieces += 1; st.streak = 0; st.last = "ok"
        } else if j.stopping {
            return
        } else {
            st.fails += 1; st.streak += 1
            let why = over ? "the server ignored the range" : r.code >= 400 ? "HTTP \(r.code)" : r.status == 28 ? "too slow / timed out" : r.status == 7 || r.status == 97 ? "no connection" : "cut (curl \(r.status), HTTP \(r.code))"
            st.last = why
            let got = p.have - (from - p.s)
            j.lock.lock(); j.breaks += 1; j.lock.unlock()
            j.event("\(l.name): piece at \(p.s / 1048576) MB broke after \(got / 1024) kB: \(why); it continues from byte \(p.s + p.have) on the next free line")
            if over { p.have = 0 }
            let rest = [2.0, 4, 6, 10][min(3, st.streak - 1)]      // a line back from a cut rejoins within 10 s
            st.restUntil = now() + rest
        }
    }
}

func runJob(_ j: Job) -> Int32 {
    try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(atPath: (j.dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    j.fd = open(j.part, O_RDWR | O_CREAT, 0o644)
    guard j.fd >= 0 else { say("cannot open \(j.part)"); return 1 }
    ftruncate(j.fd, off_t(j.size))
    j.state = "downloading"
    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
    let sigs = [SIGTERM, SIGINT].map { s -> DispatchSourceSignal in
        let src = DispatchSource.makeSignalSource(signal: s, queue: .global())
        src.setEventHandler { j.event("stopped by a signal: it can be resumed"); j.state = "stopped"; j.stopping = true }
        src.resume(); return src
    }
    _ = sigs
    var running: [String: Int] = [:]
    let perLine = 3
    let g = DispatchGroup()
    func spawn() {
        for l in currentLines() where (running[l.name] ?? 0) < perLine {
            if (running[l.name] ?? 0) == 0 && !(j.stats[l.name].map { $0.restUntil > now() } ?? false) { j.event("\(l.name): \(perLine) connections on this line") }
            for _ in (running[l.name] ?? 0)..<perLine {
                running[l.name, default: 0] += 1
                g.enter()
                DispatchQueue.global().async { worker(j, l); DispatchQueue.main.async { running[l.name, default: 1] -= 1 }; g.leave() }
            }
        }
    }
    let ticker = DispatchSource.makeTimerSource(queue: .main)
    var tick = 0
    var finished = false
    ticker.schedule(deadline: .now() + 1, repeating: 1)
    ticker.setEventHandler {
        tick += 1
        saveJob(j)
        if tick % 2 == 0 { DispatchQueue.global().async { reportMonitor(j) } }
        if tick % 5 == 0 && !j.stopping { spawn() }        // a line that came back, or a new one
        j.lock.lock(); let all = j.pieces.allSatisfy(\.done); j.lock.unlock()
        if (all || j.stopping) && !finished { finished = true; CFRunLoopStop(CFRunLoopGetMain()) }
    }
    spawn()
    ticker.resume()
    CFRunLoopRun()
    j.stopping = true
    _ = g.wait(timeout: .now() + 10)
    ticker.cancel()
    fsync(j.fd); close(j.fd)
    if j.state == "stopped" || !j.pieces.allSatisfy(\.done) {
        if j.state != "stopped" { j.state = "broken" }
        saveJob(j); reportMonitor(j)
        return 2
    }
    j.state = "verifying"; saveJob(j)
    if let sha = j.sha {
        j.event("all \(j.pieces.count) pieces in: checking SHA-256 against the server's \(sha.prefix(12))…")
        guard let fh = FileHandle(forReadingAtPath: j.part) else { return 1 }
        var h = SHA256()
        while autoreleasepool(invoking: { () -> Bool in
            let d = fh.readData(ofLength: 16 << 20); if d.isEmpty { return false }; h.update(data: d); return true }) {}
        let got = h.finalize().map { String(format: "%02x", $0) }.joined()
        if got != sha {
            j.event("SHA-256 WRONG (\(got.prefix(12))…): every piece is fetched again")
            j.lock.lock(); j.pieces.forEach { $0.have = 0 }; j.lock.unlock()
            j.state = "broken"; saveJob(j); return 3
        }
        j.event("SHA-256 matches: \(got.prefix(16))… the file is exactly the server's")
    }
    try? FileManager.default.removeItem(atPath: j.dest)
    try? FileManager.default.moveItem(atPath: j.part, toPath: j.dest)
    j.state = "done"
    let secs = now() - j.started
    j.event("DONE: \(j.dest), \(r1(Double(j.size) / 1e6)) MB in \(Int(secs)) s this run (\(r1(Double(j.size) * 8 / 1e6 / max(1, secs))) Mbit/s average), \(j.breaks) breaks stitched, \(j.resumes) resumes")
    saveJob(j); reportMonitor(j, done: true)
    return 0
}

func loadJob(_ id: String) -> Job? {
    guard let d = readJSON(downloads.appendingPathComponent("\(id).json")),
          let url = d["url"] as? String, let dest = d["dest"] as? String else { return nil }
    let j = Job(id: id, url: url, dest: dest, name: d["name"] as? String ?? id)
    j.size = (d["size"] as? NSNumber)?.int64Value ?? 0
    j.sha = d["sha256"] as? String
    j.breaks = d["breaks"] as? Int ?? 0
    j.resumes = (d["resumes"] as? Int ?? 0)
    j.firstStarted = d["started"] as? Double ?? now()
    j.events = d["events"] as? [String] ?? []
    j.pieces = (d["pieces"] as? [[NSNumber]] ?? []).map { Piece($0[0].int64Value, $0[1].int64Value, $0[2].int64Value) }
    return j
}

func pidAlive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

func get(_ args: [String]) -> Int32 {
    guard let url = args.first else { print("ck-net get <url> [--to <dir|file>] [--name N] [--id ID]"); return 1 }
    func opt(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    let file = (URL(string: url)?.lastPathComponent).flatMap { $0.isEmpty ? nil : $0 } ?? "download"
    var dest = (opt("--to") as NSString?)?.expandingTildeInPath ?? (NSHomeDirectory() + "/Downloads")
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: dest, isDirectory: &isDir), isDir.boolValue { dest = (dest as NSString).appendingPathComponent(file) }
    let id = opt("--id") ?? slug(file)
    if let old = loadJob(id), old.url == url, FileManager.default.fileExists(atPath: old.part) {
        say("\(id) is already started: resuming it"); return resume(id)
    }
    let lines = currentLines()
    say("lines: \(lines.map(\.name).joined(separator: ", "))")
    guard let (size, sha) = probe(url, lines: lines) else { say("the size could not be read (no line answered, or the server gives none)"); return 1 }
    let j = Job(id: id, url: url, dest: dest, name: opt("--name") ?? file)
    j.size = size; j.sha = sha
    var s: Int64 = 0
    while s < size { j.pieces.append(Piece(s, min(size, s + pieceSize) - 1, 0)); s += pieceSize }
    j.event("START \(file): \(r1(Double(size) / 1e6)) MB in \(j.pieces.count) pieces of 8 MB over \(lines.count) lines\(sha.map { ", SHA-256 \($0.prefix(12))… from the server" } ?? "")")
    return runJob(j)
}

func resume(_ id: String) -> Int32 {
    guard let j = loadJob(id) else { say("no download \(id)"); return 1 }
    if let d = readJSON(j.stateURL), let pid = d["pid"] as? Int32, pid != getpid(), pidAlive(pid), (d["state"] as? String) == "downloading" {
        say("\(id) is downloading already (pid \(pid))"); return 0
    }
    if (readJSON(j.stateURL)?["state"] as? String) == "done" { say("\(id) is done: \(j.dest)"); return 0 }
    j.resumes += 1
    j.event("RESUME #\(j.resumes): \(r1(Double(j.have) / 1e6)) of \(r1(Double(j.size) / 1e6)) MB already here (\(j.pieces.filter(\.done).count) of \(j.pieces.count) pieces, \(j.pieces.filter { !$0.done && $0.have > 0 }.count) half pieces continue from their last byte)")
    return runJob(j)
}

func list() {
    let files = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil)) ?? []
    for f in files where f.pathExtension == "json" {
        guard let d = readJSON(f) else { continue }
        var st = d["state"] as? String ?? "?"
        if st == "downloading", let pid = d["pid"] as? Int32, !pidAlive(pid) { st = "broken" }
        print("\(d["id"] ?? "")  \(st)  \(d["pct"] ?? 0) %  \(d["mbps"] ?? 0) Mbit/s  \(d["dest"] ?? "")")
    }
}

// MARK: - main

let a = Array(CommandLine.arguments.dropFirst())
switch (a.first, a.dropFirst().first) {
case ("test", "health"): testHealth()
case ("test", "speed"): testSpeed(quick: a.contains("--quick"))
case ("get", _): exit(get(Array(a.dropFirst())))
case ("resume", let id?): exit(resume(id))
case ("stop", let id?):
    if let d = readJSON(downloads.appendingPathComponent("\(id).json")), let pid = d["pid"] as? Int32, pidAlive(pid) { kill(pid, SIGTERM); say("stopping \(id) (pid \(pid))") }
    else { say("\(id) is not running") }
case ("list", _): list()
default:
    print("ck-net v\(CKVersion): test health | test speed | get <url> [--to dir|file] [--name N] [--id ID] | resume <id> | stop <id> | list")
}
