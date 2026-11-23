// THE DEFAULT DOWNLOAD LINE (v93+, request 105, Marko 24.11.2026: "Add a tick or check mark for line to be as default
// download line, which means in practice if I download bigger files, they're automatically going to my cheaper line which
// I am going to select"). One line (by its tick name) or none, and the size from which a transfer counts as big.
// download-line.json beside aggregate-selection.json: {"line": "AX88179B", "thresholdMB": 50}; no line = today's balance.
// Written by the stripe (the ↓ mark on a row, ⚙ for the size, the notification ConnectionKeeperDownloadLine), read live by
// ck-aggregate (the rule in Sources/Aggregate/DownloadRule.swift) and by ck-net (its downloads use only that line).
import Foundation

enum DownloadLine {
    struct Conf: Codable, Equatable { var line: String?; var thresholdMB: Double? }
    static let file = aggEnv["CK_DL_FILE"].map { URL(fileURLWithPath: $0) } ?? Paths.support.appendingPathComponent("download-line.json")
    static let defaultMB = 50.0
    private static let lock = NSLock()
    private static var cache: (at: Date, conf: Conf)?

    // read at most once a second (the server asks for every new connection)
    static var conf: Conf {
        lock.lock(); defer { lock.unlock() }
        if let c = cache, Date().timeIntervalSince(c.at) < 1 { return c.conf }
        let c = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Conf.self, from: $0) } ?? Conf()
        cache = (Date(), c)
        return c
    }
    static var line: String? { conf.line.flatMap { $0.isEmpty ? nil : $0 } }
    static var thresholdMB: Double { max(1, conf.thresholdMB ?? defaultMB) }
    static var thresholdBytes: Int { Int(thresholdMB * 1e6) }

    static func set(line: String?, thresholdMB mb: Double? = nil) {
        var c = conf
        c.line = line.flatMap { $0.isEmpty ? nil : $0 }
        if let mb { c.thresholdMB = mb }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(c).write(to: file, options: .atomic)
        lock.lock(); cache = (Date(), c); lock.unlock()
    }
}
