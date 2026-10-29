// Shared by the keeper (daemon) and the stripe (app): the version, the paths, the config, the state.
import Foundation

let CKVersion = 37

// The phase the keeper writes when the current connection is dead and no other one works (v5).
let noOtherPrefix = "NO OTHER CONNECTION"
let CKReleaseURL = "https://github.com/markoboskoauroville/connection-keeper/releases/latest"
let CKAgentLabel = "com.mantra.connectionkeeper"

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let config = home.appendingPathComponent(".config/connection-keeper.json")
    static let support = home.appendingPathComponent("Library/Application Support/connection-keeper")
    static let state = support.appendingPathComponent("state.json")
    static let command = support.appendingPathComponent("command.json")
    static let lock = support.appendingPathComponent("keeper.lock")
    static let speedLock = support.appendingPathComponent("speedtest.hold")
    static let alert = support.appendingPathComponent("failover-alert.json")
    static let log = home.appendingPathComponent("Library/Logs/connection-keeper.log")
}

// One way to reach the internet. Only "wifi" is driven in v1; other kinds are kept in the list
// and skipped with a log line, so ethernet / USB / iPhone tether can be added as drivers later.
struct Connection: Codable, Equatable {
    var kind: String          // "wifi" | later "ethernet", "tether"
    var name: String          // the SSID for wifi, a label for the others
    var interface: String?    // nil: found automatically (the Wi-Fi port for wifi)
    var enabled: Bool

    init(kind: String, name: String, interface: String? = nil, enabled: Bool = true) {
        self.kind = kind; self.name = name; self.interface = interface; self.enabled = enabled
    }
}

struct Config: Codable {
    var version = 1
    var intervalSeconds = 300
    var pingHost = "1.1.1.1"
    var httpProbe = "http://captive.apple.com/hotspot-detect.html"
    var dryRun = false
    var connections: [Connection] = []

    init() {}

    // Every key is optional, so an older or hand-edited file still loads.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        intervalSeconds = max(30, try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 300)
        pingHost = try c.decodeIfPresent(String.self, forKey: .pingHost) ?? "1.1.1.1"
        httpProbe = try c.decodeIfPresent(String.self, forKey: .httpProbe) ?? "http://captive.apple.com/hotspot-detect.html"
        dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        connections = try c.decodeIfPresent([Connection].self, forKey: .connections) ?? []
    }

    // The first run: Marko's two access points, in the order the Mac already prefers them.
    static func makeDefault() -> Config {
        var cfg = Config()
        let preferred = Net.preferredNetworks(Net.wifiInterface() ?? "en0")
        let wanted = ["mantra", "Something"]
        var names = preferred.filter { p in wanted.contains { $0.lowercased() == p.lowercased() } }
        if names.isEmpty { names = Array(preferred.prefix(2)) }
        cfg.connections = names.map { Connection(kind: "wifi", name: $0) }
        return cfg
    }

    static func load() -> Config {
        if let data = try? Data(contentsOf: Paths.config),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) { return cfg }
        let cfg = makeDefault()
        cfg.save()
        return cfg
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Paths.config, options: .atomic) }
    }
}

struct CheckRecord: Codable {
    var at: Date
    var online: Bool
    var how: String
    var latencyMs: Double?
}

// Written by the keeper every two seconds; the stripe reads it. A heartbeat older than 15 s
// means the keeper is not running.
struct KeeperState: Codable {
    var heartbeat = Date()
    var pid: Int32 = 0
    var dryRun = false
    var current: String?
    var currentInterface: String?
    var phase = "starting"
    var healthy = true
    var lastCheck: CheckRecord?
    var nextCheck: Date?
    var lastFailover: Date?
    var lastFailoverFrom: String?
    var lastFailoverTo: String?
    var recent: [String] = []

    static func load() -> KeeperState? {
        guard let data = try? Data(contentsOf: Paths.state) else { return nil }
        return try? jsonDecoder().decode(KeeperState.self, from: data)
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? jsonEncoder().encode(self) { try? data.write(to: Paths.state, options: .atomic) }
    }

    var isFresh: Bool { Date().timeIntervalSince(heartbeat) < 15 }
}

// THE RED ALERT (Marko, 14.10.2026: "If it switches connection during its running, please color all font
// in red ... so I know that connection is changed from distance and I need to check what's wrong with my
// first connection"). Written by the keeper when IT left a dead connection for another one (never for a
// switch he made). Kept in its own file, so it survives a restart of the keeper, the stripe or the Mac.
// It goes away when he presses OK on the stripe, or when the Mac is back on the connection that died.
struct FailoverAlert: Codable {
    var from: String          // the connection that died (the first one, if several failovers follow)
    var to: String            // where the keeper is now
    var at: Date              // when it died
    var how: String           // the remedy that worked
    var simulated = false     // a test: stays until OK, even on `from`

    static func load() -> FailoverAlert? {
        guard let data = try? Data(contentsOf: Paths.alert) else { return nil }
        return try? jsonDecoder().decode(FailoverAlert.self, from: data)
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? jsonEncoder().encode(self) { try? data.write(to: Paths.alert, options: .atomic) }
    }

    static func clear() { try? FileManager.default.removeItem(at: Paths.alert) }

    // "mantra died 09:41 → on Something"
    var line: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "\(from) died \(f.string(from: at)) → on \(to)"
    }
}

func logStamp() -> String {
    ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
}

// One line in the keeper's log, from either program.
func appendLog(_ line: String) {
    if let h = try? FileHandle(forWritingTo: Paths.log) {
        h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close()
    } else {
        try? (line + "\n").write(to: Paths.log, atomically: true, encoding: .utf8)
    }
}

// What the stripe asks of the keeper. The keeper reads it and deletes it.
struct KeeperCommand: Codable {
    var action: String        // "switch" | "check"
    var target: String?
    var at = Date()

    func send() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? jsonEncoder().encode(self) { try? data.write(to: Paths.command, options: .atomic) }
    }

    static func take() -> KeeperCommand? {
        guard let data = try? Data(contentsOf: Paths.command) else { return nil }
        try? FileManager.default.removeItem(at: Paths.command)
        return try? jsonDecoder().decode(KeeperCommand.self, from: data)
    }
}

func jsonEncoder() -> JSONEncoder {
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
}

func jsonDecoder() -> JSONDecoder {
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
}
