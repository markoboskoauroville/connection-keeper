// THE DATA BALANCE (v8, Marko 14.10.2026: "know how much megabytes are left on my account ... Connection Keeper can
// ask the remaining megabytes only through a headless browser through the command ... So it all works behind the
// scenes"). The stripe runs the command `router-sms balance --json` (repo router-sms, ~/Developer/ROUTER_SMS): a
// headless Firefox sends STANJE to 13880 through the TP-Link router and reads Telemach's reply. No AI, no window.
// The last answer is kept in data-balance.json and shown at start.
// v11 (Marko 18.10.2026, requests 15 and 17: "like invisible hand ... do it in front of my eyes"; "during running,
// nothing is happening in front of my eyes ... When I manually click, it's happening in front of my eyes"): a click
// runs the command with --visible, so the same script does every step in a Firefox window he watches; at start and
// on a new day it runs behind the scenes.
import AppKit

struct DataBalance: Codable {
    var left_mb: Double
    var total_mb: Double
    var used_mb: Double
    var at: String              // "2026-10-14 11:57", the time inside Telemach's SMS
    var time: String            // "11:57"
    var eur: Double?
    var checked: String?        // when the Mac asked
    var seconds: Double?        // how long the command took

    var leftGB: Double { left_mb / 1024 }
    var line: String { String(format: "%.1f GB left", leftGB) }   // v12: no time ("time when we tested it's not important")
    var color: NSColor { leftGB < 2 ? Ink.red : leftGB < 10 ? Ink.amber : Ink.text }
    var tip: String {
        String(format: "Telemach, at %@: %.2f MB used of %.2f MB, %.2f MB left", at, used_mb, total_mb, left_mb)
            + (eur.map { String(format: "; account %.2f EUR", $0) } ?? "")
            + (checked.map { "\nasked \($0)" } ?? "") + (seconds.map { String(format: " (%.0f s)", $0) } ?? "")
            + "\nClick: send STANJE to 13880 now in a Firefox window you watch (one SMS)."
    }

    static let file = Paths.support.appendingPathComponent("data-balance.json")
    static let command = Paths.home.appendingPathComponent(".local/bin/router-sms").path

    static func load() -> DataBalance? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(DataBalance.self, from: d)
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(self).write(to: DataBalance.file, options: .atomic)
    }

    // Runs the command (one SMS); call it off the main thread. Either the balance or the reason it failed.
    static func check(visible: Bool) -> Result<DataBalance, Error> {
        struct Fail: LocalizedError { let errorDescription: String? }
        guard FileManager.default.isExecutableFile(atPath: command) else {
            return .failure(Fail(errorDescription: "router-sms is not installed (~/Developer/ROUTER_SMS)"))
        }
        let r = shell(command, visible ? ["balance", "--visible", "--json"] : ["balance", "--json"], timeout: 150)
        let last = r.out.split(separator: "\n").last.map(String.init) ?? ""
        if let d = last.data(using: .utf8), let b = try? JSONDecoder().decode(DataBalance.self, from: d) {
            b.save()
            return .success(b)
        }
        if let d = last.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let e = o["error"] as? String {
            return .failure(Fail(errorDescription: e))
        }
        return .failure(Fail(errorDescription: r.status == 15 ? "no answer within 150 s" : String(r.out.suffix(200))))
    }
}

// The automatic check: off unless he sets it in ⚙ (each check is one SMS). 0 = off, else every N hours.
enum DataAuto {
    static let key = "dataBalanceEveryHours"
    static var hours: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: key) }
    }
}
