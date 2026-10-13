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
        let r = Net.join(c.name, iface)
        if !r.ok { keeper.log("join \"\(c.name)\" refused: \(r.detail)") }
        // Whatever networksetup said, believe only the SSID and an address.
        for _ in 0..<15 {
            keeper.pause(2)
            if Net.currentSSID(iface) == c.name, Net.ipAddress(iface) != nil { return true }
        }
        keeper.log("\"\(c.name)\" did not come up within 30 s")
        return false
    }
}

let drivers: [String: Driver] = ["wifi": WifiDriver()]

final class Keeper {
    var cfg = Config.load()
    var state = KeeperState()
    var dryRun: Bool
    var failures = 0
    lazy var wifiIface: String? = Net.wifiInterface()

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
        if let h = try? FileHandle(forWritingTo: Paths.log) {
            h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close()
        } else {
            try? (line + "\n").write(to: Paths.log, atomically: true, encoding: .utf8)
        }
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
            state.current = iface == wifiIface ? Net.currentSSID(iface) : iface
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
        } else {
            log("back online on \(state.current ?? "?") after: \(what)")
        }
        return true
    }

    func bringUp(_ c: Connection) -> Bool {
        guard let d = drivers[c.kind] else { log("\"\(c.name)\": kind \"\(c.kind)\" has no driver yet, skipped"); return false }
        return attempt("\(c.kind) \"\(c.name)\"") { d.activate(c, keeper: self) }
    }

    func online(_ p: Probe) {
        failures = 0
        if case .online(let how, let ms) = p {
            setPhase("ok", healthy: true)
            log("online via \(state.current ?? "?") (\(how)\(ms.map { String(format: ", %.0f ms", $0) } ?? ""))")
        }
        state.nextCheck = Date().addingTimeInterval(Double(cfg.intervalSeconds))
    }

    // The ladder: retry, rejoin, the others in order, Wi-Fi power off and on, then back off.
    func checkAndHeal() {
        setPhase("checking", healthy: state.healthy)
        var p = probe(); record(p)
        if p.isOnline { online(p); return }
        log("OFFLINE: \(state.lastCheck?.how ?? "?") on \(state.current ?? "no network")")

        for i in 1...2 {
            setPhase("offline: retry \(i) of 2", healthy: false)
            log("retry \(i) of 2 in 15 s")
            pause(15)
            p = probe(); record(p)
            if p.isOnline { log("it was a blip (retry \(i))"); online(p); return }
        }

        let enabled = cfg.connections.filter { $0.enabled }
        let wifi = wifiIface
        let here = wifi.flatMap { Net.currentSSID($0) }

        if let here, let c = enabled.first(where: { $0.kind == "wifi" && $0.name == here }) {
            if attempt("rejoin \"\(here)\"", { WifiDriver().activate(c, keeper: self) }) { online(probe()); return }
        }
        for c in enabled where !(c.kind == "wifi" && c.name == here) {
            if bringUp(c) { online(probe()); return }
        }
        if let wifi {
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
        let delay = min(60 * pow(2, Double(failures - 1)), Double(cfg.intervalSeconds))
        state.nextCheck = Date().addingTimeInterval(delay)
        setPhase("offline: nothing works, next try in \(Int(delay)) s", healthy: false)
        log("NO CONNECTION WORKS (round \(failures)); next try in \(Int(delay)) s")
    }

    func manualSwitch(_ target: String) {
        guard let c = cfg.connections.first(where: { $0.name == target }) else { log("switch: \"\(target)\" is not in the list"); return }
        log("MANUAL switch to \"\(target)\" asked from the stripe")
        if bringUp(c) { online(probe()) } else { state.nextCheck = Date().addingTimeInterval(20) }
    }

    func run() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        log("connection-keeper v\(CKVersion) started, pid \(getpid()), every \(cfg.intervalSeconds) s, list: " +
            cfg.connections.map { "\($0.kind):\($0.name)\($0.enabled ? "" : "(off)")" }.joined(separator: ", "))
        state.nextCheck = Date()
        while true {
            cfg = Config.load()
            dryRun = dryRunFlag || cfg.dryRun
            if let cmd = KeeperCommand.take() {
                if cmd.action == "switch", let t = cmd.target { manualSwitch(t) }
                if cmd.action == "check" { log("check asked from the stripe"); state.nextCheck = Date() }
            }
            if Speed.held() {                       // a speed test is switching networks on purpose
                if state.phase != "holding: a speed test runs" { setPhase("holding: a speed test runs", healthy: state.healthy); log("speed test running: checks held") }
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
