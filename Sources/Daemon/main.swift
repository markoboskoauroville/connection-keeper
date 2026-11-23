// connection-keeperd: checks the internet every few minutes and, when it is gone, walks a ladder
// of remedies until one of Marko's connections carries it again.
//
//   connection-keeperd                 run (the LaunchAgent starts it like this)
//   connection-keeperd --dry-run       log what it WOULD do; never touches the network
//   connection-keeperd --once          one check (and the ladder if it fails), then exit
//   connection-keeperd --simulate-offline --fast
//                                      test the ladder: every probe says offline, waits are short,
//                                      and --dry-run is forced
import Foundation

let args = Set(CommandLine.arguments.dropFirst())
let simulateOffline = args.contains("--simulate-offline")
let dryRunFlag = args.contains("--dry-run") || simulateOffline
let once = args.contains("--once")
let fast = args.contains("--fast")
// v90 (assessment 23.11.2026), CI only, together with --simulate-offline: what the ladder sees around it.
//   --simulate-wifi en0          the Wi-Fi device (a runner has none)
//   --simulate-ssid Something    the network it is on (a phone hotspot when the name is one)
//   --simulate-other-line NAME   another line carries while the default device does not
//   --simulate-aggregate         the aggregation is on (traffic rides ck-aggregate's lines)
func argValue(_ k: String) -> String? {
    let a = CommandLine.arguments
    return a.firstIndex(of: k).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
}
let simWifi = simulateOffline ? argValue("--simulate-wifi") : nil
let simSSID = simulateOffline ? argValue("--simulate-ssid") : nil
let simOtherLine = simulateOffline ? argValue("--simulate-other-line") : nil
let simAggregate = simulateOffline && args.contains("--simulate-aggregate")

// connection-keeperd --simulate-failover [FROM TO]
//   writes the red alert as if FROM had died and the keeper had moved to TO, and exits. It touches no
//   network; the alert is marked simulated, so it stays until OK is pressed on the stripe.
if let i = CommandLine.arguments.firstIndex(of: "--simulate-failover") {
    let rest = Array(CommandLine.arguments.dropFirst(i + 1).prefix(2))
    let names = Config.load().connections.map { $0.name }
    let from = rest.count == 2 ? rest[0] : (names.first ?? "mantra")
    let to = rest.count == 2 ? rest[1] : (names.dropFirst().first ?? "Something")
    let a = FailoverAlert(from: from, to: to, at: Date(), how: "simulated", simulated: true)
    a.save()
    appendLog("\(logStamp()) TEST: simulated failover alert written: \(a.line)")
    print("written \(Paths.alert.path): \(a.line)")
    exit(0)
}

// A driver knows how to bring one kind of connection up. v1 has Wi-Fi; a wired or tethered driver
// is added here and in `drivers` without touching the ladder.
protocol Driver {
    func activate(_ c: Connection, keeper: Keeper) -> Bool
}

struct WifiDriver: Driver {
    func activate(_ c: Connection, keeper: Keeper) -> Bool {
        guard let iface = c.interface ?? Net.wifiInterface() else { keeper.log("no Wi-Fi interface"); return false }
        if keeper.dryRun { keeper.log("WOULD join Wi-Fi \"\(c.name)\" on \(iface)"); return false }
        if !Net.wifiPowerOn(iface) { _ = Net.setWifiPower(iface, true); keeper.pause(5) }
        // The join runs beside the loop so the heartbeat keeps beating (a join can take a minute).
        var result: (ok: Bool, detail: String)?
        let lock = NSLock()
        DispatchQueue.global().async { let r = Join.wifi(c.name, iface); lock.lock(); result = r; lock.unlock() }
        while true {
            keeper.pause(1)
            lock.lock(); let r = result; lock.unlock()
            if let r {
                if r.ok { keeper.log("joined \"\(c.name)\": \(r.detail)"); return true }
                keeper.log("join \"\(c.name)\" failed: \(r.detail)")
                return false
            }
        }
    }
}

// LAN (v12, Marko 18.10.2026: "add lan interface meaning cable interface"): a cable that answers through itself goes
// to the top of the service order, and the internet goes through it.
struct LanDriver: Driver {
    func activate(_ c: Connection, keeper: Keeper) -> Bool {
        guard let dev = Net.lanDevice(c), Net.ipAddress(dev) != nil else { keeper.log("LAN \"\(c.name)\": no cable or no address"); return false }
        guard Net.onlineVia(dev, host: keeper.cfg.pingHost) != nil else { keeper.log("LAN \"\(c.name)\" (\(dev)): no internet through it"); return false }
        if keeper.dryRun { keeper.log("WOULD put LAN \"\(c.name)\" (\(dev)) first"); return false }
        let r = Net.prefer(dev)
        keeper.log("LAN \"\(c.name)\" (\(dev)): " + r.detail)
        return r.ok
    }
}

let drivers: [String: Driver] = ["wifi": WifiDriver(), "lan": LanDriver()]

final class Keeper {
    var cfg = Config.load()
    var state = KeeperState()
    var dryRun: Bool
    var failures = 0
    var diedAt: Date?                       // when the current trouble began
    var manual = false                      // a switch Marko asked for: no red alert
    var wifiIface: String? { simWifi ?? Net.wifiInterface() }   // asked every time (v12: a lazy answer stuck empty since a login)
    func ssid(_ iface: String) -> String? { simSSID ?? Net.currentSSID(iface) }
    // v90: the Mac's Wi-Fi is on a phone's hotspot (phone-hotspots.txt): its SIM decides; a power cycle cannot help it
    var onPhoneHotspot: Bool { wifiIface.flatMap { ssid($0) }.map { CableOnly.isPhoneHotspot($0) } ?? false }
    var aggregating: Bool { simAggregate || (!simulateOffline && Aggregation.aggregateMode) }

    // v90 (assessment 23.11.2026): the probe is pinned to the default-route device, so a dead default device is not "the
    // Mac is offline" while another line carries. ck-aggregate's own health check first (every line it holds, also
    // NOTHING ONLY's standby), else a cable of the list that answers a ping through itself. The line's name, or nil.
    func liveElsewhere() -> String? {
        if simulateOffline { return simOtherLine }
        let dead = Net.defaultRouteInterface()
        if let st = Aggregation.status(), let l = st.lines.first(where: { $0.alive && $0.device != dead }) { return "\(l.name) (\(l.device), ck-aggregate)" }
        for c in cfg.connections where c.enabled && c.kind == "lan" {
            if let d = Net.lanDevice(c), d != dead, Net.ipAddress(d) != nil, Net.onlineVia(d, host: cfg.pingHost) != nil { return "\(c.name) (\(d))" }
        }
        return nil
    }
    // v90: the next look; 30 s while the Wi-Fi is on a phone's hotspot (a SIM that runs out of data shows quickly)
    func nextLook() -> Double { onPhoneHotspot ? Double(min(30, cfg.intervalSeconds)) : Double(cfg.intervalSeconds) }

    init() {
        dryRun = dryRunFlag || cfg.dryRun
        state.pid = getpid()
        state.dryRun = dryRun
    }

    func log(_ s: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        let line = "\(stamp) \(dryRun ? "[dry] " : "")\(s)"
        print(line); fflush(stdout)
        state.recent.append(line)
        if state.recent.count > 30 { state.recent.removeFirst(state.recent.count - 30) }
        appendLog(line)
        saveState()
    }

    func pause(_ seconds: Double) {
        // The heartbeat keeps beating during a long wait, so the stripe never calls a busy keeper dead.
        var left = fast ? seconds / 50 : seconds
        while left > 0 { let step = min(left, 2); usleep(UInt32(step * 1_000_000)); left -= step; saveState() }
    }

    func saveState() {
        state.heartbeat = Date()
        state.dryRun = dryRun
        if let iface = Net.defaultRouteInterface() ?? wifiIface {
            state.currentInterface = iface
            state.current = Net.displayName(iface)
        }
        state.save()
    }

    func probe() -> Probe {
        if simulateOffline { return .offline("simulated") }
        return Net.probe(pingHost: cfg.pingHost, httpURL: cfg.httpProbe)
    }

    func record(_ p: Probe) {
        switch p {
        case .online(let how, let ms): state.lastCheck = CheckRecord(at: Date(), online: true, how: how, latencyMs: ms)
        case .captive: state.lastCheck = CheckRecord(at: Date(), online: false, how: "captive portal", latencyMs: nil)
        case .offline(let why): state.lastCheck = CheckRecord(at: Date(), online: false, how: why, latencyMs: nil)
        }
    }

    func setPhase(_ s: String, healthy: Bool) { state.phase = s; state.healthy = healthy; saveState() }

    // Try one remedy, then ask the internet whether it worked.
    func attempt(_ what: String, _ act: () -> Bool) -> Bool {
        setPhase("recovering: \(what)", healthy: false)
        log("step: \(what)")
        let before = state.current
        let acted = act()
        if dryRun && !acted { return false }
        let p = probe(); record(p)
        guard p.isOnline else { log("still offline after: \(what)"); return false }
        saveState()
        if before != state.current {
            state.lastFailover = Date(); state.lastFailoverFrom = before; state.lastFailoverTo = state.current
            log("FAILOVER \(before ?? "nothing") -> \(state.current ?? "?") (\(what))")
            if !manual, let to = state.current { raiseAlert(from: before, to: to, how: what) }
        } else {
            log("back online on \(state.current ?? "?") after: \(what)")
        }
        return true
    }

    // The keeper left a dead connection by itself: the stripe turns red until Marko presses OK or the
    // Mac is back on the connection that died. A second failover keeps the first dead one as `from`.
    func raiseAlert(from: String?, to: String, how: String) {
        if var a = FailoverAlert.load(), !a.simulated {
            if a.from == to { FailoverAlert.clear(); log("ALERT cleared: back on \"\(to)\""); return }
            a.to = to; a.how = how; a.save()
            log("ALERT kept: \(a.line)")
            return
        }
        let a = FailoverAlert(from: from ?? "nothing", to: to, at: diedAt ?? Date(), how: how)
        a.save()
        log("ALERT raised (the stripe is red): \(a.line)")
    }

    // Back on the connection that died, by whatever road: the red goes.
    func clearAlertIfHome() {
        guard let a = FailoverAlert.load(), !a.simulated, let here = state.current, here == a.from,
              state.healthy else { return }
        FailoverAlert.clear()
        log("ALERT cleared: back on \"\(here)\"")
    }

    func bringUp(_ c: Connection) -> Bool {
        guard let d = drivers[c.kind] else { log("\"\(c.name)\": kind \"\(c.kind)\" has no driver yet, skipped"); return false }
        return attempt("\(c.kind) \"\(c.name)\"") { d.activate(c, keeper: self) }
    }

    func online(_ p: Probe) {
        failures = 0
        if case .online(let how, let ms) = p {
            setPhase("ok", healthy: true)
            clearAlertIfHome()
            log("online via \(state.current ?? "?") (\(how)\(ms.map { String(format: ", %.0f ms", $0) } ?? ""))")
        }
        state.nextCheck = Date().addingTimeInterval(nextLook())
    }

    // The ladder: retry, rejoin, the others in order, Wi-Fi power off and on, then back off.
    func checkAndHeal() {
        setPhase("checking", healthy: state.healthy)
        var p = probe(); record(p)
        if p.isOnline { online(p); return }
        // v90: with the aggregation on, the traffic rides ck-aggregate's lines; one of them alive is not an outage of the Mac
        if aggregating, let other = liveElsewhere() {
            failures = 0
            setPhase("ok: \(state.current ?? "the default device") has no internet, \(other) carries", healthy: true)
            log("NOT OFFLINE: \(state.current ?? "the default device") does not answer (\(state.lastCheck?.how ?? "?")), but \(other) carries the aggregation: no ladder")
            state.nextCheck = Date().addingTimeInterval(30)
            return
        }
        diedAt = Date()
        log("OFFLINE: \(state.lastCheck?.how ?? "?") on \(state.current ?? "no network")")

        for i in 1...2 {
            setPhase("offline: retry \(i) of 2", healthy: false)
            log("retry \(i) of 2 in 15 s")
            pause(15)
            p = probe(); record(p)
            if p.isOnline { log("it was a blip (retry \(i))"); online(p); return }
        }

        // v81 (request 89): the keeper never joins a phone's hotspot by itself (it spends that phone's SIM); v87: Marko may
        // join it by hand and then it is a line of the aggregate
        let skipped = cfg.connections.filter { $0.enabled && $0.kind == "wifi" && CableOnly.isPhoneHotspot($0.name) }
        if !skipped.isEmpty { log("ladder: \(skipped.map { "\"\($0.name)\"" }.joined(separator: ", ")) skipped: a phone hotspot (joined only by hand)") }
        let enabled = cfg.connections.filter { $0.enabled && !($0.kind == "wifi" && CableOnly.isPhoneHotspot($0.name)) }
        let wifi = wifiIface
        let here = wifi.flatMap { ssid($0) }

        if let here, let c = enabled.first(where: { $0.kind == "wifi" && $0.name == here }) {
            if attempt("rejoin \"\(here)\"", { WifiDriver().activate(c, keeper: self) }) { online(probe()); return }
        }
        for c in enabled where !(c.kind == "wifi" && c.name == here) {
            if bringUp(c) { online(probe()); return }
        }
        // v90 (23.11.2026: the hotspot's SIM had no data; the cycle added about two minutes and the Claude API was gone for
        // 212 s): the Wi-Fi is never power-cycled while another line carries, nor when it is on a phone's hotspot
        let other = liveElsewhere()
        if let wifi, other != nil || onPhoneHotspot {
            log("Wi-Fi power cycle skipped (\(wifi)): " + (other.map { "\($0) still carries" } ?? "on the phone hotspot \"\(here ?? "?")\" (its SIM decides, a power cycle cannot help)"))
        } else if let wifi {
            let cycled = attempt("Wi-Fi power off and on (\(wifi))") {
                if dryRun { log("WOULD switch Wi-Fi power off, wait 5 s, on"); return false }
                _ = Net.setWifiPower(wifi, false); pause(5); _ = Net.setWifiPower(wifi, true); pause(20)
                return true
            }
            if cycled { online(probe()); return }
            for c in enabled where c.kind == "wifi" {
                if bringUp(c) { online(probe()); return }
            }
        }

        failures += 1
        let delay = min(60 * pow(2, Double(failures - 1)), nextLook())
        state.nextCheck = Date().addingTimeInterval(delay)
        let others = enabled.filter { !($0.kind == "wifi" && $0.name == here) }.map { $0.name }
        setPhase("\(noOtherPrefix) — \(here ?? "the Wi-Fi") dead, \(others.isEmpty ? "none in the list" : others.joined(separator: ", ") + " not working") · next try \(Int(delay)) s", healthy: false)
        log("NO OTHER CONNECTION: \(here ?? "no network") is dead and \(others.isEmpty ? "the list has no other" : others.joined(separator: ", ") + " did not work") (round \(failures)); next try in \(Int(delay)) s")
    }

    func manualSwitch(_ target: String) {
        guard let c = cfg.connections.first(where: { $0.name == target }) else { log("switch: \"\(target)\" is not in the list"); return }
        log("MANUAL switch to \"\(target)\" asked from the stripe")
        manual = true; defer { manual = false }
        if bringUp(c) { online(probe()) } else { state.nextCheck = Date().addingTimeInterval(20) }
    }

    func run() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        log("connection-keeper v\(CKVersion) started, pid \(getpid()), every \(cfg.intervalSeconds) s, list: " +
            cfg.connections.map { "\($0.kind):\($0.name)\($0.enabled ? "" : "(off)")" }.joined(separator: ", "))
        state.nextCheck = Date()
        if !once { TailscaleGuard(dry: dryRunFlag || cfg.dryRun).start() }      // v52
        while true {
            cfg = Config.load()
            dryRun = dryRunFlag || cfg.dryRun
            if let cmd = KeeperCommand.take() {
                if cmd.action == "switch", let t = cmd.target { manualSwitch(t) }
                if cmd.action == "check" { log("check asked from the stripe"); state.nextCheck = Date() }
            }
            if Speed.held() {                       // a speed test is switching networks on purpose
                if state.phase != "holding: a speed test runs" { setPhase("holding: a speed test runs", healthy: state.healthy); log("checks held (a speed test or a switch from the stripe is running)") }
            } else if state.phase == "holding: a speed test runs" {
                state.nextCheck = Date()            // the hold is over: look at once, not in 5 minutes
                checkAndHeal()
            } else if let next = state.nextCheck, Date() >= next {
                checkAndHeal()
                if once { log("--once: done"); return }
            }
            saveState()
            sleep(2)
        }
    }
}

// One keeper at a time: a second copy (a manual run beside the LaunchAgent) leaves at once.
try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
let lockFD = open(Paths.lock.path, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    print("connection-keeperd: another keeper is running (\(Paths.lock.path)); leaving")
    exit(1)
}
Keeper().run()
