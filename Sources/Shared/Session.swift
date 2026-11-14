// OPEN = FRANKFURT, QUIT = THE MAC AS BEFORE (v73, requests 86 + 87, Marko 14.11.2026: "when I'm closing the app, that
// should be seamlessly switched to normal connection, so there are no leftovers or nonsense. When it's open, it goes to
// Frankfurt. When it's closed, everything is as before").
//
// open (the app starts):  the service order as it is now is kept (once: the "before"), the keeper and the aggregation
//   server started and answering, THEN the tunnel flag / proxy: the routes through utun99 come only when the server behind
//   them already answers, so no new connection ever finds a dead road. A lease (app-lease.json: the app's pid) says the
//   app owns the session.
// close (⌘Q, Dock Quit, logout): the proxy off and the tunnel flag removed FIRST (the root helper deletes the two half
//   routes, then stops hev): the Mac's own default route, which was never touched, carries every new connection at once;
//   the service order back to the "before"; then the keeper and the server stopped and kept from starting at login
//   (the server drains its connections, v71), ck-phone and our adb forwards removed, the passing files deleted, the lease
//   removed. An update (the app quits to be replaced) keeps everything: the lease says "updating" for 3 minutes.
// crash: ck-aggregate watches the lease twice a second; a lease whose app is gone (and not updating) = the same close.
import Foundation
import Darwin

enum Session {
    struct Lease: Codable { var pid: Int32; var path: String?; var at: Date; var updatingUntil: Date? }
    static var lease: URL { Paths.support.appendingPathComponent("app-lease.json") }
    static var orderFile: URL { Paths.support.appendingPathComponent("service-order-before.txt") }
    static var modeFile: URL { Paths.support.appendingPathComponent("session-mode") }

    static func readLease() -> Lease? {
        guard let d = try? Data(contentsOf: lease) else { return nil }
        let j = JSONDecoder(); j.dateDecodingStrategy = .iso8601
        return try? j.decode(Lease.self, from: d)
    }
    static func writeLease(_ l: Lease) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? e.encode(l).write(to: lease, options: .atomic)
    }

    static func path(of pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }
    // The lease's process is alive and is the same program (not a reused pid).
    static func appAlive(_ l: Lease) -> Bool {
        guard kill(l.pid, 0) == 0 || errno == EPERM else { return false }
        guard let p = path(of: l.pid) else { return false }
        return l.path == nil || p == l.path
    }

    // The order of the network services, by name (networksetup's own words).
    static func serviceOrder() -> [String] {
        let out = shell("/usr/sbin/networksetup", ["-listnetworkserviceorder"], timeout: 8).out
        return out.components(separatedBy: "\n").compactMap { line in
            guard let r = line.range(of: #"^\([0-9*]+\) "#, options: .regularExpression) else { return nil }
            return String(line[r.upperBound...])
        }
    }

    // MARK: open

    static func open(app me: Int32 = getpid(), _ say: @escaping (String) -> Void) {
        if !FileManager.default.fileExists(atPath: orderFile.path) {
            let o = serviceOrder()
            if !o.isEmpty { try? o.joined(separator: "\n").write(to: orderFile, atomically: true, encoding: .utf8) }
            say("SESSION the service order before the app: \(o.joined(separator: " > "))")
        }
        writeLease(Lease(pid: me, path: path(of: me), at: Date(), updatingUntil: nil))
        let wantAggregate = ((try? String(contentsOf: modeFile, encoding: .utf8)) ?? "aggregate").hasPrefix("aggregate")
        let domain = "gui/\(getuid())"
        let keeper = aggEnv["CK_SESSION_NO_KEEPER"] == nil ? [CKAgentLabel] : []      // CI: no Wi-Fi keeper on a runner
        for label in keeper + (wantAggregate ? [CKAggregateLabel] : []) {
            let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist").path
            shell("/bin/launchctl", ["enable", "\(domain)/\(label)"])
            if shell("/bin/launchctl", ["print", "\(domain)/\(label)"]).status != 0 { shell("/bin/launchctl", ["bootstrap", domain, plist]) }
            shell("/bin/launchctl", ["kickstart", "\(domain)/\(label)"])           // no -k: a running one is left as it is
        }
        guard wantAggregate else { say("SESSION open: one connection (the mode at the last quit), the keeper started"); return }
        Aggregation.aggregateMode = true
        // the road through utun99 only once the server behind it answers
        var up = false
        for _ in 0..<100 { if Aggregation.status() != nil { up = true; break }; usleep(100_000) }
        if !up { say("SESSION open: the aggregation server did not answer in 10 s; the tunnel is asked up anyway (it waits for the server)") }
        let said = Aggregation.selected.isEmpty ? ["no line ticked: nothing joined yet"] : Aggregation.apply(true)
        say("SESSION open: server \(up ? "answering" : "not answering yet"), " + said.joined(separator: "; "))
    }

    // MARK: close

    static func markUpdating() {
        writeLease(Lease(pid: getpid(), path: path(of: getpid()), at: Date(), updatingUntil: Date().addingTimeInterval(180)))
    }

    // The network part of a close: after it the Mac is on its own lines with the service order of before.
    static func cleanNetwork(_ say: (String) -> Void) {
        if Aggregation.systemProxyIsOn() { say("SESSION " + Aggregation.systemProxy(false).joined(separator: "; ")) }
        if FileManager.default.fileExists(atPath: Aggregation.tunnelFlag.path) {
            try? FileManager.default.removeItem(at: Aggregation.tunnelFlag)
            var down = !Aggregation.tunnelUp
            for _ in 0..<60 where !down { usleep(100_000); down = !Aggregation.tunnelUp }
            say(down ? "SESSION the tunnel stepped aside: the half routes gone, the Mac on its own default route" : "SESSION the tunnel flag removed; the helper takes the routes down within its 2 s round")
        }
        if let before = try? String(contentsOf: orderFile, encoding: .utf8) {
            let want = before.components(separatedBy: "\n").filter { !$0.isEmpty }
            let now = serviceOrder()
            if !want.isEmpty && now != want && Set(now) == Set(want) {
                let r = shell("/usr/sbin/networksetup", ["-ordernetworkservices"] + want, timeout: 10)
                say("SESSION service order back to before (\(want.joined(separator: " > "))): \(r.status == 0 ? "done" : r.out)")
            }
            try? FileManager.default.removeItem(at: orderFile)
        }
    }

    // The processes: the keeper and the server stopped and kept from starting at login, ck-phone and our forwards gone.
    // Detached, so the app (or the server itself) can end at once; the server drains (SIGTERM, v71).
    static func stopAgents(_ say: (String) -> Void) {
        let domain = "gui/\(getuid())"
        var sh = "sleep 0.3\n"
        for label in [CKAgentLabel, CKAggregateLabel] {
            sh += "launchctl disable \(domain)/\(label)\nlaunchctl bootout \(domain)/\(label) 2>/dev/null\n"
        }
        if let adb = Phones.adb {
            sh += """
            for s in $('\(adb)' devices | awk 'NR>1 && $2=="device" {print $1}'); do
              '\(adb)' -s "$s" shell pkill -f \(Phones.remote) >/dev/null 2>&1
            done
            for p in $(seq \(Phones.firstPort) \(Phones.firstPort + 9)); do '\(adb)' forward --remove tcp:$p >/dev/null 2>&1; done

            """
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", sh]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
        for f in ["aggregate-rescan", "aggregate-rescan-done", "command.json", "speedtest.json.lock", "speedtest.hold"] {
            try? FileManager.default.removeItem(at: Paths.support.appendingPathComponent(f))
        }
        say("SESSION the keeper and the aggregation server stopped (the server lets its connections finish), ck-phone and its forwards removed")
    }

    // ⌘Q: everything back as before the app, in the order that never leaves the Mac without a road.
    static func close(_ say: (String) -> Void) {
        try? (Aggregation.aggregateMode ? "aggregate\n" : "one\n").write(to: modeFile, atomically: true, encoding: .utf8)
        cleanNetwork(say)
        stopAgents(say)
        try? FileManager.default.removeItem(at: lease)
        say("SESSION closed: the Mac is on its normal connection")
    }

    // ck-aggregate's watchdog: the app is gone without a close (a crash, a kill): the same close, from here.
    static func watch(_ say: @escaping (String) -> Void) {
        Thread.detachNewThread {
            while true {
                usleep(500_000)
                guard let l = readLease(), !appAlive(l) else { continue }
                if let u = l.updatingUntil, u > Date() { continue }        // the app is being replaced: its successor takes over
                say("SESSION the app (pid \(l.pid)) is gone without quitting\(l.updatingUntil != nil ? " (its update did not come back)" : ""): back to the Mac's normal connection")
                cleanNetwork(say)
                try? FileManager.default.removeItem(at: lease)
                stopAgents(say)
                return
            }
        }
    }
}
