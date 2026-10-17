// THE SPEED TEST ON SPEEDTEST.NET (v11, Marko 18.10.2026: "When I click speed, you are going to open the speedtest.net
// and test the speeds. Next to (upload and download) current speed, you just keep the last result ... during running,
// nothing is happening in front of my eyes. Everything in the background. When I manually click, it's happening in
// front of my eyes"). The command `speedtest-firefox` (Tools/, linked into ~/.local/bin): a Firefox of its own presses
// GO on speedtest.net and reads the numbers. Headless at start and on a new day; --visible for a click. No AI.
import AppKit

struct WebSpeed: Codable {
    var down_mbps: Double
    var up_mbps: Double
    var ping_ms: Double?
    var url: String?
    var at: String              // "2026-10-18 01:11"
    var time: String            // "01:11"
    var seconds: Double?

    var line: String { String(format: "test ↓ %5.1f ↑ %5.1f · %@", down_mbps, up_mbps, time) }   // Mbit/s, as speedtest.net
    var tip: String {
        String(format: "speedtest.net at %@: download %.2f Mbit/s, upload %.2f Mbit/s", at, down_mbps, up_mbps)
            + (ping_ms.map { String(format: ", ping %.0f ms", $0) } ?? "") + (url.map { "\n\($0)" } ?? "")
            + "\nClick: test again on speedtest.net in a Firefox window you watch."
    }

    static let file = Paths.support.appendingPathComponent("speedtest.json")   // written by the command
    static let command = Paths.home.appendingPathComponent(".local/bin/speedtest-firefox").path

    static func load() -> WebSpeed? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WebSpeed.self, from: d)
    }

    // Runs the test (about 40 s); call it off the main thread.
    static func run(visible: Bool) -> Result<WebSpeed, Error> {
        struct Fail: LocalizedError { let errorDescription: String? }
        guard FileManager.default.isExecutableFile(atPath: command) else {
            return .failure(Fail(errorDescription: "speedtest-firefox is not installed (connection-keeper/Tools)"))
        }
        let r = shell(command, visible ? ["--visible", "--json"] : ["--json"], timeout: 180)
        let last = r.out.split(separator: "\n").last.map(String.init) ?? ""
        if let d = last.data(using: .utf8), let s = try? JSONDecoder().decode(WebSpeed.self, from: d) { return .success(s) }
        if let d = last.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let e = o["error"] as? String {
            return .failure(Fail(errorDescription: e))
        }
        return .failure(Fail(errorDescription: r.status == 15 ? "no answer within 180 s" : String(r.out.suffix(200))))
    }
}

// "I need to have the values for this day": a value whose date is not today is checked again behind the scenes.
func isToday(_ at: String?) -> Bool {
    guard let at else { return false }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    return at.hasPrefix(f.string(from: Date()))
}
