// AN UPGRADE WITHOUT A REFUSED CONNECTION (v71, request 85, Marko 14.11.2026: "I need my connection non-stop please
// flawlessly transition"). Until v70 the updater ran `launchctl kickstart -k`: the server died with every connection it
// carried, and for ~0.4 s nothing listened on 8857, so the tunnel and the system proxy saw refused connections.
//
// Now (`ck-aggregate handover`, run by the updater with the NEW binary):
//   1. an interim server starts beside the old one on the same port (SO_REUSEPORT): new connections have two listeners;
//   2. the old server gets SIGTERM: it stops accepting at once (poll, 0.2 s), takes what is already queued, and lets
//      its open connections finish (at most 10 min), then exits;
//   3. launchd (KeepAlive) starts the new server from the new binary; it listens beside the interim one;
//   4. the interim server sees the new one's marker (aggregate-serving/<pid>) and drains the same way.
// A draining or interim server changes nothing on the Mac (no 4G/5G switching, no radio probes, no plug-in ticks).
import Foundation
import Darwin

var aggDraining = false
var aggInterim = false
var aggQuiet: Bool { aggDraining || aggInterim }
var handoverOld: Int32?

enum Handover {
    static var markDir: URL { aggEnv["CK_AGG_MARKS"].map { URL(fileURLWithPath: $0) } ?? Paths.support.appendingPathComponent("aggregate-serving") }
    static let lock = NSLock()
    static var isListening = false
    static var sources: [DispatchSourceSignal] = []

    // The server listens: its marker, and SIGTERM means drain (not die).
    static func listening(_ server: Server) {
        try? FileManager.default.createDirectory(at: markDir, withIntermediateDirectories: true)
        try? "\(aggPort)".write(to: markDir.appendingPathComponent(String(getpid())), atomically: true, encoding: .utf8)
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        src.setEventHandler {
            if !aggDraining { log("HANDOVER SIGTERM: no new connections here; the open ones finish (at most 10 min)"); aggDraining = true }
        }
        src.resume()
        lock.lock(); sources.append(src); isListening = true; lock.unlock()
    }

    // (the accept loop's thread) Take what is already queued, close the port, wait for the connections, exit.
    static func drainAndExit(_ server: Server, listener s: Int32) -> Never {
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
        var taken = 0
        while true {
            let c = accept(s, nil, nil)
            if c < 0 { break }
            taken += 1
            server.lock.lock(); server.clients += 1; server.lock.unlock()
            prepare(c); deadline(c, 15)
            Thread.detachNewThread { server.handle(c); server.lock.lock(); server.clients -= 1; server.lock.unlock() }
        }
        close(s)
        try? FileManager.default.removeItem(at: markDir.appendingPathComponent(String(getpid())))
        server.lock.lock(); let open = server.clients; server.lock.unlock()
        log("HANDOVER port closed here (\(taken) queued connection(s) taken first); \(open) open connection(s) finish")
        let end = Date().addingTimeInterval(600)
        var last = open
        while Date() < end {
            server.lock.lock(); let n = server.clients; server.lock.unlock()
            if n == 0 { break }
            if n != last { last = n; if n % 10 == 0 || n < 5 { log("HANDOVER draining: \(n) connection(s) open") } }
            sleep(1)
        }
        log("HANDOVER drained: pid \(getpid()) exits")
        exit(0)
    }

    // A live server on our port other than these pids (its marker), or nil. Markers of dead processes are removed.
    static func successor(excluding: Set<Int32>) -> Int32? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: markDir.path)) ?? []
        for n in names {
            guard let p = Int32(n) else { continue }
            if kill(p, 0) != 0 { try? FileManager.default.removeItem(at: markDir.appendingPathComponent(n)); continue }
            if excluding.contains(p) { continue }
            if (try? String(contentsOf: markDir.appendingPathComponent(n), encoding: .utf8)) == "\(aggPort)" { return p }
        }
        return nil
    }

    // The pid launchd runs the aggregation server under, or nil.
    static func launchdPid() -> Int32? {
        guard !aggTestCopy else { return nil }
        let out = shell("/bin/launchctl", ["print", "gui/\(getuid())/\(CKAggregateLabel)"], timeout: 5).out
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("pid = "), let p = Int32(t.dropFirst(6)) { return p }
        }
        return nil
    }

    // `ck-aggregate handover [--old-pid N]`
    static func run(_ a: [String]) -> Never {
        aggInterim = true
        let me = getpid()
        handoverOld = a.firstIndex(of: "--old-pid").flatMap { $0 + 1 < a.count ? Int32(a[$0 + 1]) : nil } ?? launchdPid()
        log("HANDOVER interim server pid \(me) covers port \(aggPort) while the old server (pid \(handoverOld.map { String($0) } ?? "none")) drains and the new one starts")
        Thread.detachNewThread {
            while true { lock.lock(); let up = isListening; lock.unlock(); if up { break }; usleep(10_000) }
            if let old = handoverOld, old != me, kill(old, 0) == 0 { kill(old, SIGTERM) }
            let end = Date().addingTimeInterval(1200)
            while Date() < end {
                if let p = successor(excluding: [me, handoverOld ?? -1]) {
                    log("HANDOVER the new server (pid \(p)) listens: the interim one drains")
                    aggDraining = true
                    return
                }
                usleep(100_000)
            }
            log("HANDOVER no new server came in 20 min: this interim server stays the server")
            aggInterim = false
        }
        Server().run()
        exit(0)
    }
}
