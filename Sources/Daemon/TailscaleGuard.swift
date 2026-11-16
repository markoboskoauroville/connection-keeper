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
// v83 (request 92, 16.11.2026: "the TAILSCALE switch is always off when I start it"). Three faults found:
// (1) the guard ran Tailscale.app's binary from launchd's empty environment, where it is the GUI ("The Tailscale GUI failed
// to start"), so every check said "did not answer" and the guard "restarted" a healthy Tailscale; now every call has
// TAILSCALE_BE_CLI=1 (launchd gives stdin /dev/null). (2) It stopped/started the VPN service "Tailscale", but the service is named
// "Tailscale 2" ("No service"); the name is now read from `scutil --nc list` (io.tailscale). (3) macOS quits every app at a
// shut-down, and Tailscale.app turns its connection OFF when it quits (WantRunning false), so after each start the switch
// is off. Within 10 minutes of the guard starting (login), a Stopped Tailscale is brought up once with `Tailscale up`
// (same account, same settings, nothing else changed). Later a Stopped Tailscale is Marko's own choice and left alone.
// v85 (request 94, the stress pass): a slow cycle is no longer taken for a sleep; heal() counts only Running as healed and
// brings a Stopped Tailscale back up (a scutil stop/start can switch it off); the start window is the Mac's uptime (15 min),
// plus once per new Tailscale.app process; the service is addressed by its id (the enabled entry first); `tailscale up`
// that wants every flag named runs the line the CLI suggests; utun route changes and the 90 s after our own restart do
// not trigger checks.
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

    var bootUpDone = false
    var lastAppPid: String?          // v85: Tailscale.app's pid; a new one = the app was (re)started
    var upForPid: String?            // the pid already brought up once
    var healStopped = false          // v85: our own scutil stop/start left Tailscale Stopped: bring it back

    init(dry: Bool) { self.dry = dry }

    /// Tailscale.app's binary as the CLI (never the GUI)
    func ts(_ args: [String], timeout: TimeInterval) -> (status: Int32, out: String) {
        shell("/usr/bin/env", ["TAILSCALE_BE_CLI=1", TailscaleGuard.bin] + args, timeout: timeout)
    }

    /// v85: the VPN service's id (unambiguous for scutil), the enabled ("*") io.tailscale entry first; nil = none found
    func serviceID() -> String? {
        let r = shell("/usr/sbin/scutil", ["--nc", "list"], timeout: 10)
        let lines = r.out.split(separator: "\n").filter { $0.contains("io.tailscale") }
        let pick = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("*") } ?? lines.first
        guard let l = pick else { return nil }
        return l.split(separator: " ").map(String.init).first { $0.count == 36 && $0.filter { $0 == "-" }.count == 4 }
    }

    func appPid() -> String? {
        let r = shell("/usr/bin/pgrep", ["-x", "Tailscale"], timeout: 5)
        return r.out.split(separator: "\n").first.map(String.init)
    }

    /// v85: `tailscale up`; when the CLI wants every non-default flag named, the exact line it suggests is run instead
    @discardableResult
    func bringUp(_ why: String) -> Bool {
        log("Tailscale is Stopped (\(why)): tailscale up")
        var r = ts(["up"], timeout: 30)
        if r.status != 0, let range = r.out.range(of: "tailscale up ") {
            let line = r.out[range.upperBound...].split(separator: "\n").first.map(String.init) ?? ""
            let args = line.split(separator: " ").map(String.init).filter { $0.hasPrefix("--") }
            log("tailscale up wants every flag: tailscale up \(args.joined(separator: " "))")
            r = ts(["up"] + args, timeout: 30)
        }
        log("tailscale up: exit \(r.status) \(r.out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
        sleep(5)
        if case .ok = evaluate() { return true }
        return false
    }

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
                // v85: a utun default route is a VPN's own (an exit node, the keeper's tunnel), and a route change within 90 s of
                // our own restart is that restart: neither triggers a check (no self-feeding heal)
                let recentHeal = lastRestart.map { now.timeIntervalSince($0) < 90 } ?? false
                if r != lastRoute {
                    let vpn = (r ?? "").hasPrefix("utun") || (lastRoute ?? "").hasPrefix("utun")
                    if let was = lastRoute, !recentHeal, !vpn { log("default route \(was) → \(r ?? "none"): checked in 15 s"); trigger = now.addingTimeInterval(15) }
                    lastRoute = r
                }
            }
            // v85: lastTick after every cycle (a slow cycle or heal is not a sleep)
            if let t = trigger, now >= t { trigger = nil; cycle(triggered: true); lastTick = Date(); nextCheck = Date().addingTimeInterval(60); continue }
            if now >= nextCheck { cycle(triggered: false); lastTick = Date(); nextCheck = Date().addingTimeInterval(60) }
        }
    }

    func status() -> [String: Any]? {
        let r = ts(["status", "--json"], timeout: 15)
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
            if ts(["ping", "-c", "1", "--timeout", "5s", ip], timeout: 12).status != 0 {
                return .bad("every online peer has rx 0 and a ping to \(ip) fails")
            }
        }
        return .ok("running, \(peers.count) peer\(peers.count == 1 ? "" : "s") online")
    }

    func cycle(triggered: Bool) {
        switch evaluate() {
        case .ok(let d): bad = 0; failedHeals = 0; write("ok", d)
        case .off(let d):
            bad = 0
            // v85: Stopped is brought up once (a) in the first 15 minutes after the Mac starts, (b) once per new Tailscale.app
            // process (the app turns its connection off when it quits: a restart or an update leaves it off), (c) when our own
            // heal left it Stopped. Any other Stopped is Marko's switch and is left alone.
            let pid = appPid()
            let newApp = pid != nil && lastAppPid != nil && pid != lastAppPid && upForPid != pid
            if lastAppPid == nil || pid != nil { lastAppPid = pid }
            let boot = !bootUpDone && ProcessInfo.processInfo.systemUptime < 900
            if d.contains("Stopped"), !dry, boot || newApp || healStopped {
                let why = healStopped ? "after our own restart of the extension" : boot ? "after the Mac started" : "Tailscale.app was restarted"
                bootUpDone = bootUpDone || boot; upForPid = pid; healStopped = false
                if bringUp(why), case .ok(let d2) = evaluate() { write("ok", d2); return }
            }
            write("off", d)
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
        guard let svc = serviceID() else { log("no io.tailscale VPN service in scutil --nc list: restart skipped"); write("red", why + " (no VPN service found)"); return }
        shell("/usr/sbin/scutil", ["--nc", "stop", svc], timeout: 20)
        sleep(4)
        shell("/usr/sbin/scutil", ["--nc", "start", svc], timeout: 20)
        sleep(15)
        var v = evaluate()
        // v85: a stop/start can leave Tailscale switched off (Stopped): that is not healed, bring it up
        if case .off(let d) = v, d.contains("Stopped") { _ = bringUp("after our own restart of the extension"); v = evaluate() }
        switch v {
        case .ok(let d):
            bad = 0; failedHeals = 0
            log("healed: \(d)"); write("ok", d)
        case .off(let d):
            bad = 0; healStopped = true
            log("after the restart: \(d)"); write("off", d)
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
