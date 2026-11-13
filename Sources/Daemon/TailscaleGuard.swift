// THE TAILSCALE GUARD (v52, Marko 13.11.2026: "I don't want this thing to happen with Tailscale anymore. Can we also build
// some demons which are always active and controlling Tailscale? If I'm in the USA and I want to access my computer ...
// this demon is restarting it automatically, refreshing it"). Today Tailscale's network extension came up while the
// default route was the dead SIM cable and stayed broken for hours ("Unable to connect to the Tailscale coordination
// server", every peer "tx N rx 0"); tailscale down/up, rebind and restarting the app did nothing, but
// `scutil --nc stop "Tailscale"`, 4 s, `scutil --nc start "Tailscale"` healed it at once.
// Every 60 s: `Tailscale status --json`. Unhealthy = Health names the coordination server, or BackendState is not Running
// while it is not simply stopped / waiting for a login, or Self offline, or every online peer has rx 0 and a
// `tailscale ping` to one fails; two checks in a row, while the internet itself answers. Then the extension is stopped and
// started (never signed out, no setting changed). Back-off 2, 5, 15 minutes while it does not heal, at most 6 restarts an
// hour. Also checked 15 s after the default route changes (a NO DATA demotion, WI-FI / CABLE) and after a wake from sleep
// (a gap in the 2 s loop), and then one failed check is enough. Every failure and restart is in the log; the state for
// the stripe's icon is tailscale-state.json.
import Foundation

final class TailscaleGuard {
    static let bin = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    static let stateFile = Paths.support.appendingPathComponent("tailscale-state.json")
    enum Verdict { case ok(String), off(String), netDown, bad(String) }

    let dry: Bool
    var bad = 0, failedHeals = 0
    var nextAllowed = Date.distantPast
    var restarts: [Date] = []
    var lastRestart: Date?
    var lastRoute: String?
    var lastTick = Date()

    init(dry: Bool) { self.dry = dry }

    func log(_ s: String) { appendLog("\(logStamp()) TAILSCALE \(s)") }

    func start() {
        guard FileManager.default.isExecutableFile(atPath: TailscaleGuard.bin) else { write("none", "Tailscale is not installed"); return }
        log("guard started (checks every 60 s, restarts the network extension when it is broken)")
        Thread.detachNewThread { self.loop() }
    }

    func loop() {
        var nextCheck = Date().addingTimeInterval(20)
        var trigger: Date?
        var n = 0
        while true {
            sleep(2)
            let now = Date()
            if now.timeIntervalSince(lastTick) > 30 { log("woke from sleep: checked in 15 s"); trigger = now.addingTimeInterval(15) }
            lastTick = now
            n += 1
            if n % 3 == 0 {
                let r = Net.defaultRouteInterface()
                if r != lastRoute {
                    if let was = lastRoute { log("default route \(was) → \(r ?? "none"): checked in 15 s"); trigger = now.addingTimeInterval(15) }
                    lastRoute = r
                }
            }
            if let t = trigger, now >= t { trigger = nil; cycle(triggered: true); nextCheck = Date().addingTimeInterval(60); continue }
            if now >= nextCheck { cycle(triggered: false); nextCheck = Date().addingTimeInterval(60) }
        }
    }

    func status() -> [String: Any]? {
        let r = shell(TailscaleGuard.bin, ["status", "--json"], timeout: 15)
        guard r.status == 0, let d = r.out.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    func internetWorks() -> Bool {
        let r = shell("/usr/bin/curl", ["-s", "-m", "5", "-o", "/dev/null", "-w", "%{http_code}", "https://controlplane.tailscale.com"], timeout: 8)
        return r.status == 0 && r.out.trimmingCharacters(in: .whitespacesAndNewlines) != "000"
    }

    func evaluate() -> Verdict {
        guard let j = status() else { return internetWorks() ? .bad("tailscale status did not answer") : .netDown }
        let backend = j["BackendState"] as? String ?? "?"
        if ["Stopped", "NeedsLogin", "NeedsMachineAuth"].contains(backend) { return .off("BackendState \(backend): left alone") }
        if !internetWorks() { return .netDown }
        let health = j["Health"] as? [String] ?? []
        if let h = health.first(where: { $0.lowercased().contains("coordination") }) { return .bad("Health: \(h)") }
        if backend != "Running" { return .bad("BackendState \(backend)") }
        if (j["Self"] as? [String: Any])?["Online"] as? Bool == false { return .bad("this Mac is offline in the tailnet") }
        let peers = ((j["Peer"] as? [String: Any]) ?? [:]).values.compactMap { $0 as? [String: Any] }.filter { $0["Online"] as? Bool == true }
        if !peers.isEmpty, peers.allSatisfy({ ($0["RxBytes"] as? Int ?? 0) == 0 }),
           let ip = (peers.first?["TailscaleIPs"] as? [String])?.first {
            if shell(TailscaleGuard.bin, ["ping", "-c", "1", "--timeout", "5s", ip], timeout: 12).status != 0 {
                return .bad("every online peer has rx 0 and a ping to \(ip) fails")
            }
        }
        return .ok("running, \(peers.count) peer\(peers.count == 1 ? "" : "s") online")
    }

    func cycle(triggered: Bool) {
        switch evaluate() {
        case .ok(let d): bad = 0; failedHeals = 0; write("ok", d)
        case .off(let d): bad = 0; write("off", d)
        case .netDown: write("amber", "the internet itself is down; Tailscale left alone")
        case .bad(let d):
            bad += 1
            log("check failed (\(bad)): \(d)")
            write("amber", d)
            if bad >= 2 || triggered { heal(d) }
        }
    }

    func heal(_ why: String) {
        let now = Date()
        restarts.removeAll { now.timeIntervalSince($0) > 3600 }
        guard now >= nextAllowed else { log("restart held back until \(DateFormatter.localizedString(from: nextAllowed, dateStyle: .none, timeStyle: .medium)) (back-off)"); return }
        guard restarts.count < 6 else { log("6 restarts in the last hour: no more for now"); write("red", why + " (6 restarts this hour, waiting)"); return }
        if dry { log("WOULD restart the network extension: \(why)"); return }
        restarts.append(now); lastRestart = now
        log("RESTART the network extension (scutil --nc stop, 4 s, start): \(why)")
        write("amber", "restarting: " + why)
        shell("/usr/sbin/scutil", ["--nc", "stop", "Tailscale"], timeout: 20)
        sleep(4)
        shell("/usr/sbin/scutil", ["--nc", "start", "Tailscale"], timeout: 20)
        sleep(15)
        switch evaluate() {
        case .ok(let d), .off(let d):
            bad = 0; failedHeals = 0
            log("healed: \(d)"); write("ok", d)
        default:
            failedHeals += 1
            let wait = [2.0, 5.0, 15.0][min(failedHeals - 1, 2)]
            nextAllowed = Date().addingTimeInterval(wait * 60)
            log("not healed after the restart; next try in \(Int(wait)) min")
            write("red", "not healed after a restart: " + why)
        }
    }

    func write(_ state: String, _ detail: String) {
        let iso = ISO8601DateFormatter()
        let j: [String: Any] = ["state": state, "detail": detail, "checked": iso.string(from: Date()),
                                "lastRestart": lastRestart.map { iso.string(from: $0) } ?? "", "restartsHour": restarts.count]
        guard let d = try? JSONSerialization.data(withJSONObject: j) else { return }
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? d.write(to: TailscaleGuard.stateFile, options: .atomic)
    }
}
