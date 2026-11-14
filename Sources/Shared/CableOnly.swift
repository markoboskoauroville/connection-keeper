// THE NOTHING ONLY ON THE CABLE (v81, request 89, Marko 14.11.2026: "I want this kind of connection only cable to my
// noting phone, nothing else noting phone is only connection and only through the cable"). The Nothing A142 is a line
// only as an adb device whose transport is USB (`adb devices -l` with a "usb:" field; Phones.list() already asks for
// it): never a wireless adb address (100.x Tailscale, ip:port, a 127.0.0.1 forward), and never its Wi-Fi hotspot.
//   - phone hotspots (the SSIDs in phone-hotspots.txt, "Something" from the start, the Nothing's own SoftAp name learned
//     over adb) are never a line of the aggregate, never joined by the keeper's ladder, greyed in the stripe's lists;
//   - ⟳ and a plug-in run `Phones.refreshAdb()` (adb start-server, reconnect offline, stale offline 127.0.0.1 Nothing
//     entries dropped) and the stripe says what the cable does: `CableOnly.nothingStatus()`.
// macOS has no RNDIS driver and the A142 refuses NCM (v17), so the cable line is ck-phone (SOCKS5) over `adb forward`.
import Foundation

enum CableOnly {
    static let file = Paths.support.appendingPathComponent("phone-hotspots.txt")
    static let defaults: Set<String> = ["Something"]

    // The Wi-Fi names that are a phone's hotspot (one per line in the file; # starts a comment).
    static var hotspots: Set<String> {
        let words = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return defaults.union(words)
    }
    static func isPhoneHotspot(_ ssid: String?) -> Bool { ssid.map { hotspots.contains($0) } ?? false }

    static func learn(_ ssid: String) {
        let s = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains("\n"), !hotspots.contains(s) else { return }
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? "# phone hotspots: never a line of Connection Keeper (v81)\n"
        try? (old + (old.hasSuffix("\n") ? "" : "\n") + s + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    struct Entry { let serial, state: String; let usb: Bool; let model: String; let fields: [String] }

    // `adb devices -l`, every entry with its state and whether its transport is USB.
    static func entries() -> [Entry] {
        guard let adb = Phones.adb else { return [] }
        return shell(adb, ["devices", "-l"], timeout: 8).out.components(separatedBy: "\n").dropFirst().compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 2 else { return nil }
            let model = f.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) } ?? ""
            return Entry(serial: f[0], state: f[1], usb: f.contains { $0.hasPrefix("usb:") }, model: model, fields: f)
        }
    }

    static let nothingModels = ["A142", "A063", "A065", "A059", "A015", "A024", "A001", "AIN"]
    static func looksNothing(_ e: Entry) -> Bool {
        nothingModels.contains { e.model.uppercased().hasPrefix($0) } || e.fields.contains { $0 == "device:Pacman" || $0.hasPrefix("product:Pacman") }
    }

    // What the cable gives the Nothing now, in words for the stripe, and whether it is a line (ok).
    //   ok:   "Nothing: on the cable (USB adb)"
    //   else: "Nothing: allow USB debugging on the phone" / "Nothing: cable gives power only, no data: try another cable /
    //          port" / "Nothing: only over wireless adb, not on the cable" / "Nothing: not on the cable"
    static func nothingStatus() -> (ok: Bool, words: String, detail: String) {
        guard let adb = Phones.adb else { return (false, "Nothing: no adb on this Mac", "adb was not found") }
        let all = entries()
        let usb = all.filter { $0.usb && looksNothing($0) }
        if let d = usb.first(where: { $0.state == "device" }) {
            learnHotspot(d.serial)
            return (true, "Nothing: on the cable (USB adb)", "USB serial \(d.serial)")
        }
        if let u = usb.first(where: { $0.state == "unauthorized" }) { return (false, "Nothing: allow USB debugging on the phone", "USB serial \(u.serial) unauthorized") }
        if let u = usb.first { return (false, "Nothing: on the cable but adb says \(u.state)", "USB serial \(u.serial) \(u.state)") }
        // not on USB: the phone asked over wireless adb (read only) what its USB port sees
        let wireless = all.filter { !$0.usb && $0.state == "device" && looksNothing($0) }
        for w in wireless {
            let r = shell(adb, ["-s", w.serial, "shell", "dumpsys usb | grep -m1 kernel_state; dumpsys battery | grep -m1 'USB powered'"], timeout: 8)
            guard r.status == 0 else { continue }
            learnHotspot(w.serial)
            let disconnected = r.out.contains("kernel_state=DISCONNECTED"), powered = r.out.contains("USB powered: true")
            if powered && disconnected {
                return (false, "Nothing: cable gives power only, no data: try another cable / port",
                        "The phone (over wireless adb \(w.serial)) says: USB powered, USB data DISCONNECTED. A charge-only cable or a bad port: use a data cable straight into the Mac.")
            }
            if powered { return (false, "Nothing: on the cable, but USB debugging does not answer", "USB powered, data \(disconnected ? "DISCONNECTED" : "up"); check USB debugging and the USB mode (File transfer)") }
            return (false, "Nothing: not on the cable (only wireless adb)", "reachable only over wireless adb \(w.serial): not used as a line")
        }
        return (false, "Nothing: not on the cable", all.isEmpty ? "adb lists no device" : "adb lists: " + all.map { "\($0.serial) \($0.state)" }.joined(separator: ", "))
    }

    // The phone's own hotspot name, read once over any adb (read only), kept so that Wi-Fi is never a line.
    static var learned = Set<String>()
    static func learnHotspot(_ serial: String) {
        guard !learned.contains(serial), let adb = Phones.adb else { return }
        learned.insert(serial)
        let r = shell(adb, ["-s", serial, "shell", "dumpsys wifi | grep -m1 mCurrentSoftApConfiguration"], timeout: 8)
        if let m = r.out.range(of: #"ssid = "([^"]+)""#, options: .regularExpression) {
            let s = String(r.out[m]).replacingOccurrences(of: "ssid = ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            learn(s)
        }
    }
}

extension Phones {
    // ⟳ and a plug-in (v81): adb's server up, offline devices asked again, stale offline 127.0.0.1 entries of the Nothing
    // dropped (an old forward; a live one is never touched). Lines for the log.
    @discardableResult
    static func refreshAdb() -> [String] {
        guard let adb else { return ["no adb on this Mac"] }
        var said: [String] = []
        shell(adb, ["start-server"], timeout: 10)
        let before = CableOnly.entries()
        if before.contains(where: { $0.state == "offline" }) {
            shell(adb, ["reconnect", "offline"], timeout: 10)
            said.append("adb reconnect offline")
            usleep(800_000)
        }
        for e in CableOnly.entries() where e.state == "offline" && e.serial.hasPrefix("127.0.0.1:") && CableOnly.looksNothing(e) {
            shell(adb, ["disconnect", e.serial], timeout: 5)
            said.append("stale offline \(e.serial) (\(e.model)) dropped")
        }
        return said
    }
}

// NOTHING ONLY (cable) (v81, request 90, Marko 14.11.2026: "nothing phone is a ground truth when you're able to attach to it
// by debugging, remove Wi-Fi and let it use its cell modem ... go only through the cable and only through the noting phone
// and ignore completely TP Link"). A mode of the aggregation (the file nothing-only = "on"):
//   - the only line is the Nothing on its USB cable (adb serial with a usb: field); its own Wi-Fi is switched off over that
//     USB serial (`cmd wifi set-wifi-enabled disabled`), so it goes out on its cell modem; never over wireless adb;
//   - AX88179B (TP-Link) and the Mac's Wi-Fi are not lines and not bond legs; they are kept only as STANDBY: used the
//     moment the Nothing's line does not answer (so the Mac is never without internet), said on the stripe, and left again
//     as soon as the Nothing answers;
//   - the bond (Frankfurt) is untouched: its legs are the server's live lines, so in this mode the Nothing only.
// Switched on only from the stripe's ⚙ when the USB link is verified (CableOnly.nothingStatus().ok); off = the ticks again.
enum NothingOnly {
    static let file = Paths.support.appendingPathComponent("nothing-only")
    static let stateFile = Paths.support.appendingPathComponent("nothing-only-state")   // written by ck-aggregate
    static var on: Bool { ((try? String(contentsOf: file, encoding: .utf8)) ?? "").hasPrefix("on") }
    static func set(_ v: Bool) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if v { try? "on\n".write(to: file, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: stateFile) }
    }
    static func isNothing(_ name: String) -> Bool { let n = name.lowercased(); return n.contains("nothing") || n.contains("a142") }
    // "nothing" (the Nothing carries), "standby <names>" (the Nothing does not answer; the standby carries), "none"
    static var state: String? {
        guard on else { return nil }
        return (try? String(contentsOf: stateFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func writeState(_ s: String) { try? (s + "\n").write(to: stateFile, atomically: true, encoding: .utf8) }
}
