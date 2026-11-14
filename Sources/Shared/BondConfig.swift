// bond.json, read by the aggregation server and the stripe (v75: here, so the app sees it too). Written by
// `ck-aggregate bond-init` (Bond.swift) with mode 0600; the token never leaves it.
import Foundation

struct BondConfig: Codable {
    var on: Bool
    var server: String
    var port: UInt16
    var token: String
    var legsPerLine: Int
    var strict: Bool?          // v74: PRIVACY STRICT: no leg up = new connections refused, never direct (default off)
    var speedOnly: Bool?       // v79: bond only when it adds speed (2+ lines); default off: one leg is enough (privacy, a VPN)
}

enum BondConfigFile {
    static var url: URL { aggEnv["CK_BOND_CONFIG"].map { URL(fileURLWithPath: $0) } ?? Paths.support.appendingPathComponent("bond.json") }
    static func load() -> BondConfig? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BondConfig.self, from: d)
    }
    // Changed in place: its 0600 mode and its token stay. false: there is no bond.json (bond-init first).
    @discardableResult
    static func update(_ change: (inout BondConfig) -> Void) -> Bool {
        guard var c = load() else { return false }
        change(&c)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(c), let h = FileHandle(forWritingAtPath: url.path) else { return false }
        h.truncateFile(atOffset: 0); h.write(d); h.closeFile()
        return true
    }
}
