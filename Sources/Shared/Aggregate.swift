// AGGREGATION (v13, Marko 18.10.2026, requests 26–28): what the stripe and the aggregation server (ck-aggregate) share.
// The connections ticked in the stripe's drop-down are joined; none ticked means aggregation is off ("If he deselects
// everything, then it means we are exiting aggregation mode"). On, macOS's SOCKS proxy of every network service points
// at the server on 127.0.0.1:8857; off, it is switched off again, and nothing goes through the server.
import Foundation

let aggPort: UInt16 = 8857
let CKAggregateLabel = "com.mantra.connectionkeeper.aggregate"

enum Aggregation {
    static let selection = Paths.support.appendingPathComponent("aggregate-selection.json")
    static let speeds = Paths.support.appendingPathComponent("aggregate-speeds.json")
    static let lastTest = Paths.support.appendingPathComponent("aggregate-test.json")
    static let changed = Notification.Name("ConnectionKeeperAggregationChanged")

    // The connections to join, by the name a person knows ("Something", "AX88179B"); the Wi-Fi by its network's name.
    static var selected: [String] {
        get { (try? Data(contentsOf: selection)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set {
            try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try? JSONEncoder().encode(newValue).write(to: selection)
        }
    }
    static var on: Bool { !selected.isEmpty }

    // The server's own words (GET /status), or nil when it does not answer within a second.
    static func status() -> AggStatus? {
        let r = shell("/usr/bin/curl", ["-s", "-m", "1", "http://127.0.0.1:\(aggPort)/status"], timeout: 2)
        guard r.status == 0 else { return nil }
        return try? JSONDecoder().decode(AggStatus.self, from: Data(r.out.utf8))
    }

    // macOS's SOCKS proxy on every network service (the cables and the Wi-Fi) → the server, or off. The house stays
    // direct: *.local, the link-local and private ranges are bypassed.
    @discardableResult
    static func systemProxy(_ on: Bool) -> [String] {
        var said: [String] = []
        for s in Net.lanServices().map(\.name) + ["Wi-Fi"] {
            let r: (status: Int32, out: String)
            if on {
                r = shell("/usr/sbin/networksetup", ["-setsocksfirewallproxy", s, "127.0.0.1", String(aggPort)])
                shell("/usr/sbin/networksetup", ["-setproxybypassdomains", s, "*.local", "169.254/16", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "127.0.0.1", "localhost"])
            } else {
                r = shell("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", s, "off"])
            }
            let out = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            said.append("\(s): \(on ? "SOCKS → 127.0.0.1:\(aggPort)" : "SOCKS off")\(out.isEmpty ? "" : " (\(out))")")
        }
        return said
    }

    static func systemProxyIsOn() -> Bool {
        shell("/usr/sbin/networksetup", ["-getsocksfirewallproxy", "Wi-Fi"], timeout: 5).out.contains("Enabled: Yes")
    }
}

struct AggLine: Codable {
    let name: String, device: String, publicIP: String, gateway: String
    let mbps: Double, alive: Bool, active: Int, connections: Int, mbDown: Double, mbUp: Double
}
struct AggIgnored: Codable { let name: String, device: String, sameLineAs: String }
struct AggStatus: Codable { let version: Int, port: Int, lines: [AggLine], ignored: [AggIgnored] }

// The last `ck-aggregate test`: each line alone and all of them joined through the server, in Mbit/s.
struct AggTest: Codable {
    let at: Date, alone: [String: Double], joined: Double, mb: Double
    static func load() -> AggTest? {
        guard let d = try? Data(contentsOf: Aggregation.lastTest) else { return nil }
        let j = JSONDecoder(); j.dateDecodingStrategy = .iso8601
        return try? j.decode(AggTest.self, from: d)
    }
    func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? e.encode(self).write(to: Aggregation.lastTest)
    }
}
