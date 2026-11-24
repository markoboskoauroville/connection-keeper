// `ck-aggregate bond-selftest` (v65, request 84): the proof of ckbond, run by GitHub's macOS runner (nothing is compiled
// or run on Marko's Mac). The relay (ck-bond-server, built for darwin) listens on 127.0.0.1; three emulated lines are
// local proxies in front of it, each with its own speed and delay in both directions:
//   lineA 80 Mbit/s, 20 ms each way     lineB 80 Mbit/s, 20 ms each way     lineC 16 Mbit/s, 60 ms each way
// One leg per line. Fetch 1: a 64 MB file through ONE bond stream, checked by SHA-256, with each leg's share. Fetch 2: the
// same, and lineA goes silent (a 4G line that stops answering) after 24 MB; the fetch must still finish intact.
//
//   ck-aggregate bond-selftest --server 127.0.0.1:18443 --token-file <hex file> --url http://127.0.0.1:18080/big.bin --sha <hex>
import Foundation
import Darwin
import CryptoKit

// v91 (request 102): the bond selftest's speed floors, as fractions of the best emulated line (80 Mbit/s); measured first
// (CI history and the bench run of 23.11.2026, see TAKEOVER v91), set under the lowest good run, above a broken scheduler.
// v95 (the scheduler): raised after the A/B bench of 24.11.2026 (TAKEOVER v95): v95's scheduler read fetch 1 108-143 and
// fetch 2 96-108 on the runner (v92's: 44-141 and 25-69); the floors keep about 35 % room under the lowest v95 run.
enum BondFloors {
    static let fetch1 = 0.85      // one stream over 80 + 80 + 16: 68 Mbit/s (v91 0.40)
    static let fetch2 = 0.70      // lineA silenced at 24 MB: 56 Mbit/s, the goal itself (v91 0.25; a stalled leg is copied now)
}

final class ThrottleProxy {
    let name: String, mbps: Double, delay: Double, target: UInt16
    // v95: `bloat` s: a loaded line's extra delay (a 4G cell's scheduler, a hotspot's Wi-Fi hop): each chunk is held
    // delay + bloat x (how busy the line was over the last 0.5 s), so the round trip rises to about delay x 2 + bloat under
    // load whatever the sender's own queue is. The queue is sized for it.
    let bloat: Double
    var port: UInt16 = 0
    private let lock = NSLock()
    private var holed = false, holedUntil = 0.0
    init(_ name: String, mbps: Double, delay: Double, target: UInt16, bloat: Double = 0) {
        self.name = name; self.mbps = mbps; self.delay = delay; self.target = target; self.bloat = bloat
    }

    var isHoled: Bool { lock.lock(); defer { lock.unlock() }; return holed || bnow() < holedUntil }
    // The line goes silent: nothing moves any more, nothing is closed (the leg must notice by itself).
    func blackhole() { lock.lock(); holed = true; lock.unlock() }
    // v95: silent for `secs`, then it carries on (a 4G stall): the leg must not die, the stream must not wait for it.
    func stall(_ secs: Double) { lock.lock(); holedUntil = bnow() + secs; lock.unlock() }

    func start() -> Bool {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_port = 0; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafePointer(to: &a, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, size) } }) == 0, listen(s, 16) == 0 else { return false }
        var len = size
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
        port = UInt16(bigEndian: a.sin_port)
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(s, nil, nil)
                if c < 0 { usleep(10_000); continue }
                if isHoled { close(c); continue }               // a dead line takes no new connection either
                guard let t = loopbackConnect(target) else { close(c); continue }
                prepare(c)
                Thread.detachNewThread { [self] in pipe(c, t) }
                Thread.detachNewThread { [self] in pipe(t, c) }
            }
        }
        return true
    }

    // from → to: every chunk held `delay` seconds, then sent at `mbps` (a token bucket); the queue holds about one
    // delay's worth, so the sender feels the line's speed through TCP.
    func pipe(_ from: Int32, _ to: Int32) {
        let q = NSCondition()
        var chunks: [(Double, [UInt8])] = [], queued = 0, eof = false
        let limit = Int(mbps * 1e6 / 8 * (delay + bloat)) + 131_072
        var recent: [(Double, Int)] = []                    // v95: bytes sent in the last 0.5 s (how busy the line is)
        Thread.detachNewThread { [self] in
            var buf = [UInt8](repeating: 0, count: 16384)
            while true {
                q.lock(); while queued >= limit { q.wait() }; q.unlock()
                while isHoled { usleep(10_000) }
                let n = buf.withUnsafeMutableBytes { recv(from, $0.baseAddress, 16384, 0) }
                q.lock()
                if n <= 0 { eof = true } else { chunks.append((bnow(), Array(buf[0..<n]))); queued += n }
                q.broadcast(); q.unlock()
                if n <= 0 { return }
            }
        }
        var nextFree = bnow()
        while true {
            q.lock()
            while chunks.isEmpty && !eof { q.wait() }
            if chunks.isEmpty { q.unlock(); shutdown(to, SHUT_WR); return }
            let (at, bytes) = chunks.removeFirst()
            queued -= bytes.count
            q.broadcast(); q.unlock()
            // a sleep on GitHub's runner can last several ms longer than asked (the first run read 27 of 80 Mbit/s):
            // the bucket keeps up to 20 ms of credit, so the line still averages its speed
            var hold = delay
            if bloat > 0 {
                let t = bnow()
                recent.removeAll { t - $0.0 > 0.5 }
                let busy = min(1, Double(recent.reduce(0) { $0 + $1.1 }) * 8 / (mbps * 1e6 * 0.5))
                hold += bloat * busy
                recent.append((t, bytes.count))
            }
            let now = bnow(), when = max(at + hold, nextFree)
            nextFree = max(when, now - 0.02) + Double(bytes.count * 8) / (mbps * 1e6)
            if when > now + 0.001 { usleep(UInt32((when - now) * 1e6)) }
            while isHoled { usleep(10_000) }
            if !sendAll(to, bytes) { return }
        }
    }
}

func loopbackConnect(_ port: UInt16) -> Int32? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var sa = sockaddr_in(); sa.sin_family = sa_family_t(AF_INET); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    sa.sin_port = port.bigEndian; sa.sin_addr.s_addr = inet_addr("127.0.0.1")
    let ok = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
    if !ok { close(fd); return nil }
    prepare(fd)
    return fd
}

// v91: a TCP echo on 127.0.0.1 (the idle test's destination); its port, or nil.
func tcpEcho() -> UInt16? {
    let s = socket(AF_INET, SOCK_STREAM, 0)
    guard s >= 0 else { return nil }
    var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_port = 0; a.sin_addr.s_addr = inet_addr("127.0.0.1")
    let size = socklen_t(MemoryLayout<sockaddr_in>.size)
    guard withUnsafePointer(to: &a, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, size) } }) == 0, listen(s, 4) == 0 else { close(s); return nil }
    var len = size
    _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
    Thread.detachNewThread {
        while true {
            let c = accept(s, nil, nil)
            if c < 0 { usleep(10_000); continue }
            Thread.detachNewThread {
                var buf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = buf.withUnsafeMutableBytes { recv(c, $0.baseAddress, 4096, 0) }
                    if n <= 0 || !sendAll(c, Array(buf[0..<n])) { break }
                }
                close(c)
            }
        }
    }
    return UInt16(bigEndian: a.sin_port)
}

struct BondFetch { var ok = false, bytes = 0, length = -1, sha = "", secs = 0.0, why = "", maxGap = 0.0 }

// One HTTP/1.0 GET through ONE bond stream: a socket pair, one end bridged into the stream exactly as a SOCKS client is.
func bondFetch(_ b: BondClient, host: String, port: UInt16, path: String, progress: ((Int) -> Void)? = nil) -> BondFetch {
    var r = BondFetch()
    let t0 = bnow()
    guard let s = b.open(host, port, timeout: 3) else { r.why = "the stream did not open"; return r }   // as the server does: OPEN_OK first
    var sv: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sv) == 0 else { b.reset(s); r.why = "socketpair failed"; return r }
    var big: Int32 = 1 << 20, one: Int32 = 1
    for fd in sv {
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &big, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &big, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
    let req = Array("GET \(path) HTTP/1.0\r\nHost: \(host):\(port)\r\nUser-Agent: ckbond-selftest\r\n\r\n".utf8)
    let bridged = DispatchSemaphore(value: 0)
    let inner = sv[0], outer = sv[1]
    Thread.detachNewThread { b.bridge(inner, s, first: req); bridged.signal() }
    shutdown(outer, SHUT_WR)                                // the request is all we send
    var head = [UInt8](), inBody = false, hasher = SHA256()
    var buf = [UInt8](repeating: 0, count: 65536)
    var lastAt = 0.0                                        // v95: the longest wait between two pieces of the body
    while true {
        let n = buf.withUnsafeMutableBytes { recv(outer, $0.baseAddress, 65536, 0) }
        if n <= 0 { break }
        let now = bnow()
        if inBody && lastAt > 0 { r.maxGap = max(r.maxGap, now - lastAt) }
        lastAt = now
        if inBody {
            hasher.update(data: Data(buf[0..<n])); r.bytes += n
        } else {
            head += buf[0..<n]
            let mark: [UInt8] = [13, 10, 13, 10]
            if head.count >= 4, let at = (0...(head.count - 4)).first(where: { Array(head[$0..<($0 + 4)]) == mark }) {
                inBody = true
                let rest = Array(head[(at + 4)...])
                let text = String(decoding: head[0..<at], as: UTF8.self)
                for line in text.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                    r.length = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? -1
                }
                if !text.hasPrefix("HTTP/1.0 200") && !text.hasPrefix("HTTP/1.1 200") { r.why = "answer: " + (text.components(separatedBy: "\r\n").first ?? "") }
                hasher.update(data: Data(rest)); r.bytes += rest.count
                head = []
            }
        }
        progress?(r.bytes)
    }
    close(outer)
    _ = bridged.wait(timeout: .now() + 30)
    r.secs = bnow() - t0
    r.sha = bondHex(hasher.finalize().withUnsafeBytes { Array($0) })
    r.ok = r.why.isEmpty && inBody && r.length == r.bytes
    if r.why.isEmpty && !r.ok { r.why = "got \(r.bytes) of \(r.length) bytes" }
    return r
}

func bondSelftest(_ args: [String]) -> Never {
    signal(SIGPIPE, SIG_IGN)
    setvbuf(stdout, nil, _IOLBF, 0)
    func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    guard let server = arg("--server"), let sp = server.split(separator: ":").last.flatMap({ UInt16($0) }),
          let tf = arg("--token-file"), let tokenText = try? String(contentsOfFile: tf, encoding: .utf8), let token = bondUnhex(tokenText),
          let urlText = arg("--url"), let url = URL(string: urlText), let host = url.host, let want = arg("--sha")?.lowercased() else {
        print("usage: ck-aggregate bond-selftest --server 127.0.0.1:18443 --token-file <file> --url http://127.0.0.1:18080/big.bin --sha <hex>")
        exit(2)
    }
    let port = UInt16(url.port ?? 80), path = url.path.isEmpty ? "/" : url.path
    if let names = arg("--scenarios") {
        bondScenarios(names.split(separator: ",").map(String.init), server: sp, token: token, host: host, port: port, path: path, want: want,
                      measureOnly: args.contains("--measure-only"))
    }
    let lines = [ThrottleProxy("lineA", mbps: 80, delay: 0.020, target: sp), ThrottleProxy("lineB", mbps: 80, delay: 0.020, target: sp),
                 ThrottleProxy("lineC", mbps: 16, delay: 0.060, target: sp)]
    for l in lines {
        guard l.start() else { print("BOND SELFTEST FAIL: no local port for \(l.name)"); exit(1) }
        print("emulated \(l.name): \(Int(l.mbps)) Mbit/s, \(Int(l.delay * 1000)) ms each way, 127.0.0.1:\(l.port)")
    }
    let client = BondClient(host: "127.0.0.1", port: sp, token: token, paths: {
        lines.map { l in BondPath(key: l.name, line: l.name, dial: { loopbackConnect(l.port) }) }
    })
    client.start()
    let t0 = bnow()
    while client.legCount < 3 && bnow() - t0 < 20 { usleep(100_000) }
    print(String(format: "legs up: %d of 3 after %.1f s", client.legCount, bnow() - t0))
    guard client.legCount == 3 else { print("BOND SELFTEST FAIL: the legs did not come up"); exit(1) }
    sleep(2)                                                // a few PINGs: each leg knows its RTT

    // v91 (assessment 23.11.2026): an idle bonded stream is not reset. This stream to a local echo stays silent for
    // --idle-only seconds. `--idle-expect kept` (the relay as deployed, 24 h safety net): it must still echo afterwards.
    // `--idle-expect ended` (the control: the relay with CK_BOND_IDLE=4s, the pre-v91 rule shrunk from 10 min): it must
    // be gone, so the test is known to see a reset when there is one.
    if let idleText = arg("--idle-only"), let idle = UInt32(idleText) {
        guard let echo = tcpEcho() else { print("BOND IDLE TEST FAIL: no local echo"); exit(1) }
        guard let s = client.open("127.0.0.1", echo, timeout: 3) else { print("BOND IDLE TEST FAIL: the stream did not open"); exit(1) }
        var sv: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sv) == 0 else { print("BOND IDLE TEST FAIL: socketpair"); exit(1) }
        Thread.detachNewThread { client.bridge(sv[0], s) }
        let outer = sv[1]
        deadline(outer, 5)
        func roundTrip(_ word: String) -> Bool {
            guard sendAll(outer, Array(word.utf8)) else { return false }
            var got = [UInt8](), buf = [UInt8](repeating: 0, count: 256)
            while got.count < word.utf8.count {
                let n = buf.withUnsafeMutableBytes { recv(outer, $0.baseAddress, 256, 0) }
                if n <= 0 { return false }
                got += buf[0..<n]
            }
            return String(decoding: got, as: UTF8.self) == word
        }
        let first = roundTrip("before the silence\n")
        print("idle test: first echo \(first ? "back" : "MISSING"); now \(idle) s of silence on the stream (the legs keep pinging)")
        sleep(idle)
        let second = roundTrip("after the silence\n")
        print("idle test: echo after \(idle) s idle \(second ? "back: the stream was kept" : "MISSING: the stream was ended")")
        close(outer)
        let wantKept = arg("--idle-expect") != "ended"
        if first && second == wantKept { print("BOND IDLE TEST PASS: a bonded stream idle for \(idle) s was \(second ? "kept" : "ended, as this relay's short limit says")"); exit(0) }
        print("BOND IDLE TEST FAIL (expected the stream \(wantKept ? "kept" : "ended"))"); exit(1)
    }

    // v76 (the throughput question): only the UDP round trip on fresh legs, with each leg's own RTT beside it
    if args.contains("--udp-rtt-only"), let ue = arg("--udp-echo"), let ep = ue.split(separator: ":").last.flatMap({ UInt16($0) }) {
        let ul = NSLock(); var got: [Int: Double] = [:], sentAt: [Int: Double] = [:]
        guard let fid = client.openFlow(onReply: { body in
            guard body.count > 7, let idx = Int(String(decoding: body[7...], as: UTF8.self).split(separator: "|").first ?? "") else { return }
            ul.lock(); if got[idx] == nil { got[idx] = bnow() }; ul.unlock()
        }) else { print("UDP RTT: no flow"); exit(1) }
        Thread.detachNewThread {
            let t0 = bnow()
            while true {
                sleep(1)
                client.cv.lock()
                let d = client.legs.map { l in String(format: "%@ heard %.1fs ago udpq %d ctlq %d sent %llu acked %llu", l.key, bnow() - l.lastHeard, l.udpq.count, l.ctlq.count, l.sent, l.acked) }.joined(separator: " | ")
                client.cv.unlock()
                ul.lock(); let n = got.count; ul.unlock()
                print(String(format: "  t+%.0fs back %d: %@", bnow() - t0, n, d))
            }
        }
        for i in 0..<100 {
            let msg = Array("\(i)|".utf8) + [UInt8](repeating: 46, count: 60)
            ul.lock(); sentAt[i] = bnow(); ul.unlock()
            client.sendDgram(fid, [1, 127, 0, 0, 1, UInt8(ep >> 8), UInt8(ep & 255)] + msg)
            usleep(50_000)
        }
        sleep(1)
        ul.lock(); let r = got.compactMap { k, v in sentAt[k].map { (v - $0) * 1000 } }.sorted(); ul.unlock()
        let legs = (client.status()["legs"] as? [[String: Any]] ?? []).map { "\($0["line"] ?? "?") \($0["rttMs"] ?? "?") ms" }.joined(separator: ", ")
        print(String(format: "UDP RTT: %d of 100 back, median %.1f ms, p10 %.1f, p90 %.1f (legs: %@)", r.count, r.isEmpty ? 0 : r[r.count / 2], r.isEmpty ? 0 : r[r.count / 10], r.isEmpty ? 0 : r[r.count * 9 / 10], legs))
        exit(0)
    }

    var failures: [String] = []
    // 1. one stream over three lines
    let before = client.legBytes()
    let f1 = bondFetch(client, host: host, port: port, path: path)
    let after = client.legBytes()
    let mbps1 = Double(f1.bytes) * 8 / max(f1.secs, 0.001) / 1e6
    print(String(format: "fetch 1 (one stream, 3 lines): %d bytes in %.2f s = %.1f Mbit/s; sha %@ (%@)",
                 f1.bytes, f1.secs, mbps1, f1.sha, f1.sha == want ? "matches" : "DIFFERENT"))
    let total = lines.reduce(0.0) { $0 + Double((after[$1.name] ?? 0) - (before[$1.name] ?? 0)) }
    var carried = 0
    for l in lines {
        let share = total > 0 ? Double((after[l.name] ?? 0) - (before[l.name] ?? 0)) / total * 100 : 0
        if share >= 10 { carried += 1 }
        print(String(format: "  %@ carried %.1f%% of the stream's frames", l.name, share))
    }
    print(String(format: "  the fastest line alone is 80 Mbit/s: the one stream ran at %.0f%% of it", mbps1 / 80 * 100))
    if !f1.ok { failures.append("fetch 1: \(f1.why)") }
    if f1.sha != want { failures.append("fetch 1: SHA-256 differs") }
    if carried < 2 { failures.append("fetch 1: fewer than two lines carried 10% of the stream") }

    // 2. the same, and lineA goes silent after 24 MB
    var killedAt = -1.0
    let t2 = bnow()
    let f2 = bondFetch(client, host: host, port: port, path: path, progress: { got in
        if killedAt < 0 && got >= 24 << 20 { killedAt = bnow() - t2; lines[0].blackhole(); print(String(format: "  lineA silenced at %d bytes (%.2f s)", got, killedAt)) }
    })
    let mbps2 = Double(f2.bytes) * 8 / max(f2.secs, 0.001) / 1e6
    print(String(format: "fetch 2 (lineA silenced mid-way): %d bytes in %.2f s = %.1f Mbit/s; sha %@ (%@); legs left %d",
                 f2.bytes, f2.secs, mbps2, f2.sha, f2.sha == want ? "matches" : "DIFFERENT", client.legCount))
    // v91 (assessment 23.11.2026, request 102): speed floors. The goal is fetch 1 at 1.1x the best line (88 Mbit/s) and
    // fetch 2 at 0.7x of 80 (56) after a line died; today's scheduler does not reach that every run, and GitHub's runner
    // varies up to 2x run to run (TAKEOVER v76-v78), so the floors fail a real regression (one line carrying it all, the
    // v65 estimator spiral at 36.7 / 10.0) but not the runner's noise. The gap to the goal is printed every run.
    let best = 80.0, goal1 = 1.1, goal2 = 0.7, floor1 = BondFloors.fetch1, floor2 = BondFloors.fetch2
    print(String(format: "SPEED fetch 1: %.2fx the best line (goal %.1fx = %.0f Mbit/s, floor %.2fx = %.0f)%@", mbps1 / best, goal1, goal1 * best, floor1, floor1 * best,
                 mbps1 / best >= goal1 ? "" : String(format: "  KNOWN SHORTFALL: %.0f%% of the goal", mbps1 / (goal1 * best) * 100)))
    print(String(format: "SPEED fetch 2: %.2fx of 80 after lineA died (goal %.1fx = %.0f Mbit/s, floor %.2fx = %.0f)%@", mbps2 / best, goal2, goal2 * best, floor2, floor2 * best,
                 mbps2 / best >= goal2 ? "" : String(format: "  KNOWN SHORTFALL: %.0f%% of the goal", mbps2 / (goal2 * best) * 100)))
    if f1.ok && mbps1 < floor1 * best { failures.append(String(format: "fetch 1: %.1f Mbit/s, under the floor of %.0f (%.2fx the best line)", mbps1, floor1 * best, floor1)) }
    if f2.ok && mbps2 < floor2 * best { failures.append(String(format: "fetch 2: %.1f Mbit/s, under the floor of %.0f (%.2fx of 80)", mbps2, floor2 * best, floor2)) }
    if killedAt < 0 { failures.append("fetch 2: lineA was never silenced") }
    if !f2.ok { failures.append("fetch 2: \(f2.why)") }
    if f2.sha != want { failures.append("fetch 2: SHA-256 differs") }
    // 3. v71: the relay is upgraded (SIGHUP: the binary on disk takes over the same socket) in the middle of a fetch, while
    // a new small fetch starts every 100 ms: the big one must finish intact on the old process, no small one may fail
    if let rp = arg("--relay-pid").flatMap({ Int32($0) }), let small = arg("--small") {
        let pl = NSLock()
        var probes = 0, probeFails: [String] = [], probing = true, hupAt = -1.0
        let t3 = bnow()
        Thread.detachNewThread {
            while true {
                pl.lock(); let go = probing; pl.unlock()
                if !go { break }
                let r = bondFetch(client, host: host, port: port, path: small)
                pl.lock(); probes += 1; if !r.ok { probeFails.append(String(format: "%.1f s: %@", bnow() - t3, r.why)) }; pl.unlock()
                usleep(100_000)
            }
        }
        let f3 = bondFetch(client, host: host, port: port, path: path, progress: { got in
            if hupAt < 0 && got >= 16 << 20 { hupAt = bnow() - t3; kill(rp, SIGHUP); print(String(format: "  relay told to hand over (SIGHUP) at %d bytes (%.2f s)", got, hupAt)) }
        })
        sleep(3)                                            // the probes go on after the switch, on the new process
        pl.lock(); probing = false; let n = probes, bad = probeFails; pl.unlock()
        sleep(1)
        let gen = (client.status()["generation"] as? Int) ?? 0
        print(String(format: "fetch 3 (relay upgraded mid-way): %d bytes in %.2f s; sha %@ (%@); small fetches during it: %d, failed %d; generation now %d",
                     f3.bytes, f3.secs, f3.sha, f3.sha == want ? "matches" : "DIFFERENT", n, bad.count, gen))
        for b in bad.prefix(5) { print("  failed probe: \(b)") }
        if hupAt < 0 { failures.append("fetch 3: the relay was never told to hand over") }
        if !f3.ok || f3.sha != want { failures.append("fetch 3: \(f3.ok ? "SHA-256 differs" : f3.why)") }
        if !bad.isEmpty { failures.append("fetch 3: \(bad.count) of \(n) small fetches failed during the hand-over") }
        if n < 10 { failures.append("fetch 3: only \(n) small fetches ran") }
        if gen < 1 { failures.append("fetch 3: no new generation after the hand-over (no GOAWAY seen)") }
    }
    // 4. v74: UDP. A flow to a local echo: 300 datagrams of 100 bytes at 50 a second (a call's audio: the flow is
    // "redundant", every datagram on two legs); lineB goes silent after 100. No copy may reach the app twice, and the
    // datagrams must keep coming back after the line died.
    if let ue = arg("--udp-echo"), let ep = ue.split(separator: ":").last.flatMap({ UInt16($0) }) {
        let ul = NSLock()
        var got: [Int: Double] = [:], dups = 0
        var sentAt: [Int: Double] = [:]
        let fid = client.openFlow { body in
            guard body.count > 7, body[0] == 1 else { return }
            let text = String(decoding: body[7...], as: UTF8.self)
            guard let idx = Int(text.split(separator: "|").first ?? "") else { return }
            ul.lock(); if got[idx] != nil { dups += 1 } else { got[idx] = bnow() }; ul.unlock()
        }
        if let fid {
            var killedAt = -1
            for i in 0..<300 {
                let msg = Array("\(i)|".utf8) + [UInt8](repeating: 46, count: 100 - "\(i)|".utf8.count)
                ul.lock(); sentAt[i] = bnow(); ul.unlock()
                client.sendDgram(fid, [1, 127, 0, 0, 1, UInt8(ep >> 8), UInt8(ep & 255)] + msg)
                if i == 100 { lines[1].blackhole(); killedAt = i; print("  lineB silenced after datagram 100") }
                usleep(20_000)
            }
            sleep(2)
            ul.lock()
            let total = got.count, late = (200..<300).filter { got[$0] != nil }.count, around = (100..<200).filter { got[$0] != nil }.count
            let rtts = got.compactMap { k, v in sentAt[k].map { (v - $0) * 1000 } }.sorted()
            let median = rtts.isEmpty ? 0 : rtts[rtts.count / 2]
            ul.unlock()
            client.closeFlow(fid)
            print(String(format: "UDP (redundant flow, 300 datagrams, lineB silenced at %d): %d came back (%d of 100 right after the loss, %d of the last 100), %d copies reached the app, median round trip %.0f ms",
                         killedAt, total, around, late, dups, median))
            if total < 285 { failures.append("UDP: only \(total) of 300 datagrams came back") }
            if late < 98 { failures.append("UDP: only \(late) of the last 100 came back after the line died") }
            if dups > 0 { failures.append("UDP: \(dups) duplicate datagrams reached the app") }
        } else { failures.append("UDP: no flow could be opened") }
        // a DNS question through the relay (to 1.1.1.1, from the relay's address)
        let dl = NSLock(); var answer: [UInt8]?
        if let dfid = client.openFlow(onReply: { body in dl.lock(); answer = body; dl.unlock() }) {
            let q: [UInt8] = [0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7] + Array("example".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1]
            let t0 = bnow()
            client.sendDgram(dfid, [1, 1, 1, 1, 1, 0, 53] + q)
            while bnow() - t0 < 3 { dl.lock(); let a = answer; dl.unlock(); if a != nil { break }; usleep(20_000) }
            dl.lock(); let a = answer; dl.unlock()
            client.closeFlow(dfid)
            if let a, a.count > 19, a[7] == 0x12, a[8] == 0x34 {
                DNSNames.learn(Array(a[7...]))
                let ips = DNSNames.map.keys.sorted()
                print(String(format: "DNS through the relay: example.com answered by 1.1.1.1 in %.0f ms (%@)", (bnow() - t0) * 1000, ips.joined(separator: ", ")))
            } else { failures.append("DNS: no answer from 1.1.1.1 through the relay in 3 s") }
        }
    }

    // 4b. v79: one live line left (lineA and lineB silenced): the bond is still in use (privacy); with "bond only when it
    // adds speed" it steps aside
    do {
        sleep(4)                                            // lineB's leg is declared dead after 3 s of silence
        let one = client.status()
        let inUse = one["bypass"] is NSNull
        client.cv.lock(); client.minLines = 2; client.cv.unlock()
        let aside = client.status()["bypass"] as? String
        client.cv.lock(); client.minLines = 1; client.cv.unlock()
        let alive = (one["legs"] as? [[String: Any]] ?? []).filter { ($0["alive"] as? Bool) == true }.count
        print("one line left (\(alive) leg): bond \(inUse ? "in use (privacy)" : "STEPPED ASIDE"); with speed-only: \(aside ?? "in use")")
        if !inUse { failures.append("one leg: the bond stepped aside although privacy is the default") }
        if aside == nil { failures.append("one leg + speed-only: the bond did not step aside") }
    }

    // 5. v74: the direct list (bond-direct.txt) by name and by an address a DNS answer named
    if let df = aggEnv["CK_BOND_DIRECT"] {
        try? "# test\nexample.com\n*.youtube.com\n".write(toFile: df, atomically: true, encoding: .utf8)
        let byName = Direct.match("www.youtube.com"), sub = Direct.match("m.example.com"), not = Direct.match("example.org")
        let byIP = DNSNames.map.keys.first.flatMap { Direct.match($0) }
        print("direct list: www.youtube.com → \(byName ?? "-"), m.example.com → \(sub ?? "-"), example.org → \(not ?? "-"), example.com's address → \(byIP ?? "-")")
        if byName != "youtube.com" || sub != "example.com" || not != nil { failures.append("direct list: wrong matches") }
        if arg("--udp-echo") != nil && byIP != "example.com" { failures.append("direct list: an address named by DNS did not match") }
    }

    // 6. v74: bond switched off in the middle of a fetch: the client drains. The fetch must finish intact; a new connection
    // must be turned to today's path at once (open() → nil without waiting).
    do {
        var drainedAt = -1.0, refusedMs = -1.0
        let t6 = bnow()
        let legs6 = client.legCount
        let f6 = bondFetch(client, host: host, port: port, path: path, progress: { got in
            if drainedAt < 0 && got >= 16 << 20 {
                drainedAt = bnow() - t6
                client.drain()
                let t = bnow(); let s = client.open(host, port, timeout: 1); refusedMs = (bnow() - t) * 1000
                if let s { client.reset(s) }
                print(String(format: "  bond switched off (drain) at %d bytes; a new connection was turned away in %.1f ms (%@)", got, refusedMs, s == nil ? "goes direct" : "WAS BONDED"))
            }
        })
        print("  fetch 6 ran over \(legs6) leg(s): traffic through the relay with one line")
        print(String(format: "fetch 6 (bond off mid-way): %d bytes in %.2f s; sha %@ (%@)", f6.bytes, f6.secs, f6.sha, f6.sha == want ? "matches" : "DIFFERENT"))
        if !f6.ok || f6.sha != want { failures.append("fetch 6: the draining stream did not finish intact") }
        if refusedMs < 0 || refusedMs > 50 { failures.append("fetch 6: a new connection was not turned away at once") }
    }
    let st = client.status()
    if let d = try? JSONSerialization.data(withJSONObject: st, options: [.sortedKeys]) { print("status: " + String(decoding: d, as: UTF8.self)) }
    if failures.isEmpty {
        print(String(format: "BOND SELFTEST PASS: one stream %.1f Mbit/s over 3 lines (best line 80), intact after a line died (%.1f Mbit/s)", mbps1, mbps2))
        exit(0)
    }
    print("BOND SELFTEST FAIL: " + failures.joined(separator: "; "))
    exit(1)
}

// MARK: v95 scenarios (the bond scheduler, 24.11.2026)

// The floors of the scenarios, as fractions of the best line of each (measured first: TAKEOVER v95; the runner is noisy).
enum BondScenarioFloors {
    static let unequal = 0.80     // 90 + 25 Mbit/s: one stream (v95 86-106; v92 59-101)
    static let deep = 0.80        // 80 + 80 Mbit/s whose round trip rises by 0.25 s under load (v95 90-113; v92 37-77)
    static let upload = 0.70      // one upload over 80 + 80 + 16 (v95 80-131; v92 69-81)
    static let maxGap = 1.0       // seconds: the longest wait in a stream while one of two lines stalls for 2 s (v95 0.40-0.82; v92 1.66-2.00)
}

// A TCP sink on 127.0.0.1: reads to the end, answers "<bytes> <sha256 hex>\n".
func tcpSink() -> UInt16? {
    let s = socket(AF_INET, SOCK_STREAM, 0)
    guard s >= 0 else { return nil }
    var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_port = 0; a.sin_addr.s_addr = inet_addr("127.0.0.1")
    let size = socklen_t(MemoryLayout<sockaddr_in>.size)
    guard withUnsafePointer(to: &a, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, size) } }) == 0, listen(s, 4) == 0 else { close(s); return nil }
    var len = size
    _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
    Thread.detachNewThread {
        while true {
            let c = accept(s, nil, nil)
            if c < 0 { usleep(10_000); continue }
            Thread.detachNewThread {
                var h = SHA256(), n = 0, buf = [UInt8](repeating: 0, count: 65536)
                while true {
                    let r = buf.withUnsafeMutableBytes { recv(c, $0.baseAddress, 65536, 0) }
                    if r <= 0 { break }
                    h.update(data: Data(buf[0..<r])); n += r
                }
                _ = sendAll(c, Array("\(n) \(bondHex(h.finalize().withUnsafeBytes { Array($0) }))\n".utf8))
                close(c)
            }
        }
    }
    return UInt16(bigEndian: a.sin_port)
}

// One upload through ONE bond stream to the sink: `bytes` random bytes; their SHA-256 must come back.
func bondUpload(_ b: BondClient, port: UInt16, bytes: Int) -> (ok: Bool, secs: Double, why: String) {
    let t0 = bnow()
    guard let s = b.open("127.0.0.1", port, timeout: 3) else { return (false, 0, "the stream did not open") }
    var sv: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sv) == 0 else { b.reset(s); return (false, 0, "socketpair failed") }
    var big: Int32 = 1 << 20, one: Int32 = 1
    for fd in sv {
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &big, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &big, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
    let inner = sv[0], outer = sv[1]
    Thread.detachNewThread { b.bridge(inner, s) }
    var h = SHA256(), sent = 0
    var g = SystemRandomNumberGenerator()
    let block = (0..<(1 << 20)).map { _ in UInt8.random(in: 0...255, using: &g) }
    while sent < bytes {
        let piece = Array(block[0..<min(block.count, bytes - sent)])
        h.update(data: Data(piece))
        guard sendAll(outer, piece) else { close(outer); return (false, bnow() - t0, "write failed at \(sent)") }
        sent += piece.count
    }
    shutdown(outer, SHUT_WR)
    var answer = [UInt8](), buf = [UInt8](repeating: 0, count: 256)
    deadline(outer, 60)
    while true { let n = buf.withUnsafeMutableBytes { recv(outer, $0.baseAddress, 256, 0) }; if n <= 0 { break }; answer += buf[0..<n] }
    close(outer)
    let want = "\(bytes) \(bondHex(h.finalize().withUnsafeBytes { Array($0) }))"
    let got = String(decoding: answer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return (got == want, bnow() - t0, got == want ? "" : "the sink said \(got.prefix(80))")
}

// `--scenarios unequal,deep,stall,upload` [--measure-only]: each on its own emulated lines and its own bond client (a
// new group on the relay). One line per result, "SCENARIO <name>: ..."; without --measure-only a floor missed fails.
func bondScenarios(_ names: [String], server sp: UInt16, token: [UInt8], host: String, port: UInt16, path: String, want: String, measureOnly: Bool) -> Never {
    var failures: [String] = []
    print("scheduler: \(BondProto.legacy ? "v92 (CK_BOND_LEGACY)" : "v95")")
    func run(_ lines: [ThrottleProxy], _ body: (BondClient) -> Void) {
        for l in lines { guard l.start() else { failures.append("no port for \(l.name)"); return } }
        let c = BondClient(host: "127.0.0.1", port: sp, token: token, paths: { lines.map { l in BondPath(key: l.name, line: l.name, dial: { loopbackConnect(l.port) }) } })
        c.start()
        let t0 = bnow()
        while c.legCount < lines.count && bnow() - t0 < 20 { usleep(100_000) }
        guard c.legCount == lines.count else { failures.append("legs did not come up"); c.stop(); return }
        sleep(2)
        body(c)
        if let d = try? JSONSerialization.data(withJSONObject: c.status()["legs"] ?? [], options: [.sortedKeys]) { print("  legs: " + String(decoding: d, as: UTF8.self)) }
        c.stop()
        sleep(1)
    }
    func check(_ name: String, _ ok: Bool, _ what: String) { if !ok { failures.append("\(name): \(what)") } }
    for name in names {
        switch name {
        case "unequal":                                     // the real pair of 24.11.2026: hotspot ~90, cable ~25
            run([ThrottleProxy("fast", mbps: 90, delay: 0.020, target: sp), ThrottleProxy("slow", mbps: 25, delay: 0.015, target: sp)]) { c in
                let f = bondFetch(c, host: host, port: port, path: path)
                let mbps = Double(f.bytes) * 8 / max(f.secs, 0.001) / 1e6
                print(String(format: "SCENARIO unequal (90 + 25 Mbit/s, one stream): %.1f Mbit/s = %.2fx the best line (sum 115 = %.2fx); longest wait %.2f s; sha %@",
                             mbps, mbps / 90, mbps / 115, f.maxGap, f.sha == want ? "matches" : "DIFFERENT"))
                check(name, f.ok && f.sha == want, "fetch broken (\(f.why))")
                check(name, mbps >= BondScenarioFloors.unequal * 90, String(format: "%.1f Mbit/s under the floor %.2fx of 90", mbps, BondScenarioFloors.unequal))
            }
        case "deep":                                        // a 4G-like line: the round trip rises by 0.25 s under load
            run([ThrottleProxy("deepA", mbps: 80, delay: 0.020, target: sp, bloat: 0.25), ThrottleProxy("deepB", mbps: 80, delay: 0.020, target: sp, bloat: 0.25)]) { c in
                let f = bondFetch(c, host: host, port: port, path: path)
                let mbps = Double(f.bytes) * 8 / max(f.secs, 0.001) / 1e6
                print(String(format: "SCENARIO deep (80 + 80 Mbit/s, +0.25 s under load): %.1f Mbit/s = %.2fx the best line; longest wait %.2f s; sha %@",
                             mbps, mbps / 80, f.maxGap, f.sha == want ? "matches" : "DIFFERENT"))
                check(name, f.ok && f.sha == want, "fetch broken (\(f.why))")
                check(name, mbps >= BondScenarioFloors.deep * 80, String(format: "%.1f Mbit/s under the floor %.2fx of 80", mbps, BondScenarioFloors.deep))
            }
        case "stall":                                       // one of two lines silent for 2 s in the middle of a stream
            let a = ThrottleProxy("stallA", mbps: 80, delay: 0.020, target: sp), b = ThrottleProxy("stallB", mbps: 40, delay: 0.020, target: sp)
            run([a, b]) { c in
                var at = -1.0
                let t0 = bnow()
                let f = bondFetch(c, host: host, port: port, path: path, progress: { got in
                    if at < 0 && got >= 16 << 20 { at = bnow() - t0; a.stall(2) }
                })
                let mbps = Double(f.bytes) * 8 / max(f.secs, 0.001) / 1e6
                let legs = c.legCount
                print(String(format: "SCENARIO stall (80 + 40 Mbit/s, the 80 silent for 2 s at %.2f s): %.1f Mbit/s; longest wait in the stream %.2f s (limit %.1f); legs after %d of 2; sha %@",
                             at, mbps, f.maxGap, BondScenarioFloors.maxGap, legs, f.sha == want ? "matches" : "DIFFERENT"))
                check(name, at >= 0, "the line was never stalled")
                check(name, f.ok && f.sha == want, "fetch broken (\(f.why))")
                check(name, f.maxGap < BondScenarioFloors.maxGap, String(format: "the stream waited %.2f s", f.maxGap))
                check(name, legs == 2, "a 2 s stall killed a leg")
            }
        case "upload":
            guard let sink = tcpSink() else { failures.append("upload: no sink"); continue }
            run([ThrottleProxy("upA", mbps: 80, delay: 0.020, target: sp), ThrottleProxy("upB", mbps: 80, delay: 0.020, target: sp),
                 ThrottleProxy("upC", mbps: 16, delay: 0.060, target: sp)]) { c in
                let n = 32 << 20
                let u = bondUpload(c, port: sink, bytes: n)
                let mbps = Double(n) * 8 / max(u.secs, 0.001) / 1e6
                print(String(format: "SCENARIO upload (one stream up over 80 + 80 + 16): %.1f Mbit/s = %.2fx the best line; sha %@", mbps, mbps / 80, u.ok ? "matches" : "DIFFERENT " + u.why))
                check(name, u.ok, "upload broken (\(u.why))")
                check(name, mbps >= BondScenarioFloors.upload * 80, String(format: "%.1f Mbit/s under the floor %.2fx of 80", mbps, BondScenarioFloors.upload))
            }
        default: failures.append("no scenario \(name)")
        }
    }
    if failures.isEmpty || measureOnly {
        print("BOND SCENARIOS \(failures.isEmpty ? "PASS" : "MEASURED (floors not applied): " + failures.joined(separator: "; "))"); exit(0)
    }
    print("BOND SCENARIOS FAIL: " + failures.joined(separator: "; ")); exit(1)
}
