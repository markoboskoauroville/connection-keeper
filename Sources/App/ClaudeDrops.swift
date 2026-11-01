// CLAUDE CODE'S DROPS (v46, request 65, Marko 1.11.2026: "detect that the connection dropped with Claude Code locally,
// and then slowly understand why this is happening and build some kind of protection for these drops ... mark this
// inside the status line of the aggregate connection"). The app starts ck-claude (Resources, Tools/ck-claude) with
// itself; it follows every Claude Code transcript and writes claude-drops-state.json. One bottom row:
//   ☁ CLAUDE  05:20 EPROTO×18 ECONNRESET×1 · 348 s, recovered · tunnel off via en17 · today 1 drop (19 tries) | API ✓ TLS 102 ms
// red while a session is still retrying, amber for a drop in the last 30 minutes, green when the API answers and
// nothing dropped; ✕ hides it until it says something new.
import AppKit

enum ClaudeDrops {
    static let state = Paths.support.appendingPathComponent("claude-drops-state.json")
    static var tool: String { Bundle.main.resourceURL!.appendingPathComponent("ck-claude").path }
    static var watcher: Process?

    static func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["watch", "--parent", String(getpid())]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); watcher = p } catch { appendLog("\(logStamp()) CLAUDE watcher did not start: \(error.localizedDescription)") }
    }

    static func stop() { if let p = watcher, p.isRunning { p.terminate() } }

    static func row() -> DownloadRow? {
        guard let d = try? Data(contentsOf: state), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let iso = ISO8601DateFormatter()
        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        let last = j["last"] as? [String: Any]
        let probe = j["probe"] as? [String: Any] ?? [:]
        let probeOK = probe["ok"] as? Bool ?? true
        let open = last?["open"] as? Bool ?? false
        let lastAt = (last?["start"] as? String).flatMap { iso.date(from: $0) }
        let recent = lastAt.map { Date().timeIntervalSince($0) < 1800 } ?? false
        let color: NSColor = open || !probeOK ? Ink.red : recent ? Ink.amber : Ink.green
        let a = NSMutableAttributedString(string: "☁ CLAUDE ", attributes: [.font: bold, .foregroundColor: color])
        var key = "ok"
        if let last, let lastAt {
            let kinds = (last["kinds"] as? [String: Int] ?? [:]).sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            let snap = last["snap"] as? [String: Any] ?? [:]
            let how = open ? "RETRYING" : (last["recovered"] as? Bool ?? false) ? "recovered after \(last["seconds"] ?? "?") s" : "gave up after \(last["seconds"] ?? "?") s"
            let tun = (snap["tunnel"] as? Bool ?? false) ? "tunnel on" : "tunnel off"
            let tls = (snap["tcp"] as? [String: Any])?["ok"] as? Bool
            a.append(NSAttributedString(string: "\(hm.string(from: lastAt)) \(kinds) · \(last["folder"] ?? "?") · \(how) · \(snap["mode"] ?? "?"), \(tun) via \(snap["via"] ?? "?")\(tls == false ? ", TLS failed" : "")",
                                        attributes: [.font: mono, .foregroundColor: Ink.text]))
            key = "\(last["start"] ?? "")\(open)"
        } else {
            a.append(NSAttributedString(string: "no drop since the watcher started", attributes: [.font: mono, .foregroundColor: Ink.text]))
        }
        let today = DateFormatter(); today.dateFormat = "yyyy-MM-dd"
        if let t = j["today"] as? [String: Any], (t["day"] as? String) == today.string(from: Date()) {
            a.append(NSAttributedString(string: " · today \(t["episodes"] ?? 0) drops (\(t["tries"] ?? 0) tries)", attributes: [.font: mono, .foregroundColor: Ink.dim]))
        }
        let tcp = probe["tcp"] as? [String: Any]
        let api = probeOK ? "API ✓ TLS \(tcp?["ms"] ?? "?") ms" : "API NOT REACHABLE \((tcp?["error"] as? String) ?? ((probe["dns"] as? [String: Any])?["error"] as? String) ?? "")"
        a.append(NSAttributedString(string: " | " + api, attributes: [.font: mono, .foregroundColor: probeOK ? Ink.dim : Ink.red]))
        if !probeOK { key += "down" }
        var r = DownloadRow(id: "claude", text: a, canResume: false, canStop: false, ours: false)
        r.key = key
        return r
    }
}
