// The speed test (v2). Marko, 13.10.2026: "add a speed test button in the settings so I can speed test every
// connection available there". The measure is macOS's own `networkQuality -c` (Apple's servers, download and upload
// in parallel, ~15 s), bound to the connection's interface. A connection that is not the one in use is joined first
// and the Mac goes back to the one it was on afterwards; while a test runs, the keeper holds its checks
// (Paths.speedLock), so it does not "heal" the short gap the switch makes.
import Foundation

struct SpeedResult: Codable {
    var name: String
    var at: Date
    var downMbps: Double?
    var upMbps: Double?
    var rttMs: Double?
    var rpm: Int?
    var error: String?

    var line: String {
        if let e = error { return "failed: \(e)" }
        let f = DateFormatter(); f.dateFormat = "d.M. HH:mm"
        let d = downMbps.map { String(format: "↓ %.0f", $0) } ?? "↓ ?"
        let u = upMbps.map { String(format: "↑ %.0f Mbit/s", $0) } ?? "↑ ?"
        let r = rttMs.map { String(format: " · %.0f ms", $0) } ?? ""
        return "\(d)  \(u)\(r) · \(f.string(from: at))"
    }
}

enum Speed {
    static let file = Paths.support.appendingPathComponent("speed.json")

    static func load() -> [String: SpeedResult] {
        guard let d = try? Data(contentsOf: file), let r = try? jsonDecoder().decode([String: SpeedResult].self, from: d) else { return [:] }
        return r
    }
    static func save(_ r: SpeedResult) {
        var all = load(); all[r.name] = r
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? jsonEncoder().encode(all).write(to: file)
    }

    // The keeper skips its checks while this file is younger than 3 minutes.
    static func hold(_ on: Bool) {
        if on { try? Data("\(getpid())".utf8).write(to: Paths.speedLock) } else { try? FileManager.default.removeItem(at: Paths.speedLock) }
    }
    static func held() -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: Paths.speedLock.path), let m = a[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(m) < 180
    }

    static func measure(_ name: String, iface: String) -> SpeedResult {
        let r = shell("/usr/bin/networkQuality", ["-c", "-I", iface], timeout: 90)
        var out = SpeedResult(name: name, at: Date())
        guard let start = r.out.firstIndex(of: "{"),
              let j = try? JSONSerialization.jsonObject(with: Data(r.out[start...].utf8)) as? [String: Any] else {
            out.error = r.out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80).description
            if out.error!.isEmpty { out.error = "networkQuality said nothing" }
            return out
        }
        func num(_ k: String) -> Double? { (j[k] as? NSNumber)?.doubleValue }
        out.downMbps = num("dl_throughput").map { $0 / 1_000_000 }
        out.upMbps = num("ul_throughput").map { $0 / 1_000_000 }
        out.rttMs = num("base_rtt")
        out.rpm = num("responsiveness").map { Int($0) }
        if out.downMbps == nil && out.upMbps == nil { out.error = (j["error_code"] as? NSNumber).map { "error \($0)" } ?? "no throughput in the answer" }
        return out
    }

    // Test one Wi-Fi: join it if it is not the one in use, wait until the internet answers, measure, go back.
    static func test(_ c: Connection, progress: @escaping (String) -> Void) -> SpeedResult {
        guard c.kind == "wifi", let iface = Net.wifiInterface() else {
            return SpeedResult(name: c.name, at: Date(), error: "\(c.kind) is not driven yet")
        }
        let was = Net.currentSSID(iface)
        hold(true); defer { hold(false) }
        if was != c.name {
            progress("joining \(c.name)…")
            let j = Net.join(c.name, iface)
            if !j.ok { return SpeedResult(name: c.name, at: Date(), error: "could not join: \(j.detail)") }
            var up = false
            for _ in 0..<15 { if Net.probe(pingHost: "1.1.1.1", httpURL: "http://captive.apple.com/hotspot-detect.html").isOnline { up = true; break }; sleep(2) }
            if !up {
                if let was = was { progress("no internet on \(c.name), back to \(was)…"); _ = Net.join(was, iface) }
                return SpeedResult(name: c.name, at: Date(), error: "joined, but no internet within 30 s")
            }
        }
        progress("measuring \(c.name) (about 15 s)…")
        let r = measure(c.name, iface: iface)
        if let was = was, was != c.name { progress("back to \(was)…"); _ = Net.join(was, iface) }
        return r
    }
}
