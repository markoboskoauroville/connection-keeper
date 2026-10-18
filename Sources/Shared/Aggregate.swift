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
    static var on: Bool { aggregateMode && !selected.isEmpty }

    // THE MODE (request 34, Marko 18.10.2026: "After the last update, I don't have any connections ... make it simple to
    // switch mode in the application to aggregate or one connection. To simply and quickly overwrite our aggregation
    // services"). One connection: the helper's flag gone (utun99 down within 2 s), macOS's proxy off, the server stopped
    // and kept from starting at login, so nothing of the aggregation is left between the Mac and its line. Aggregate: the
    // server on and the ticked lines joined. The ticks are kept either way.
    static let modeFile = Paths.support.appendingPathComponent("mode")
    static var aggregateMode: Bool {
        get {
            if let m = try? String(contentsOf: modeFile, encoding: .utf8) { return m.hasPrefix("aggregate") }
            return FileManager.default.fileExists(atPath: tunnelFlag.path)
        }
        set {
            try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try? (newValue ? "aggregate\n" : "one\n").write(to: modeFile, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    static func setMode(_ aggregate: Bool) -> [String] {
        aggregateMode = aggregate
        let domain = "gui/\(getuid())", agent = "\(domain)/\(CKAggregateLabel)"
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(CKAggregateLabel).plist").path
        if aggregate {
            shell("/bin/launchctl", ["enable", agent])
            shell("/bin/launchctl", ["bootstrap", domain, plist])       // fails harmlessly when it is loaded already
            shell("/bin/launchctl", ["kickstart", agent])
            return ["mode aggregate, server started"] + (selected.isEmpty ? ["no line ticked: nothing joined yet"] : apply(true))
        }
        var said = apply(false)
        if !tunnelInstalled || systemProxyIsOn() { said += systemProxy(false) }
        shell("/bin/launchctl", ["bootout", agent])
        shell("/bin/launchctl", ["disable", agent])
        return ["mode one connection"] + said + ["server stopped"]
    }

    // THE VIRTUAL DEVICE (v14, request 33): when the root helper ck-tunnel is installed, aggregation on means the device
    // utun99, shown as mantra_networkaggregate, carries all internet traffic, and macOS's proxy setting stays off; the
    // helper follows this flag. Without the helper, the proxy setting as in v13.
    static let tunnelFlag = Paths.support.appendingPathComponent("tunnel-on")
    static let tunnelDevice = "utun99", tunnelName = "mantra_networkaggregate"
    static var tunnelInstalled: Bool { FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.mantra.connectionkeeper.tunnel.plist") }
    static var tunnelUp: Bool {
        ((try? String(contentsOfFile: "/Library/PrivilegedHelperTools/com.mantra.connectionkeeper.tunnel/state", encoding: .utf8)) ?? "").hasPrefix("on")
    }

    // The one switch the ticks throw.
    @discardableResult
    static func apply(_ on: Bool) -> [String] {
        if tunnelInstalled {
            if on { FileManager.default.createFile(atPath: tunnelFlag.path, contents: Data()) }
            else { try? FileManager.default.removeItem(at: tunnelFlag) }
            let off = systemProxyIsOn() ? systemProxy(false) : []
            return ["\(tunnelName) \(on ? "asked up" : "asked down")"] + off
        }
        return systemProxy(on)
    }

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

// The last `ck-aggregate test`: each line alone and all of them joined through the server, down and up, in Mbit/s.
struct AggTest: Codable {
    let at: Date, alone: [String: Double], aloneUp: [String: Double]?, joined: Double, joinedUp: Double?, mb: Double
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
