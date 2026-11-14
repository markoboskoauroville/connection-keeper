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

final class ThrottleProxy {
    let name: String, mbps: Double, delay: Double, target: UInt16
    var port: UInt16 = 0
    private let lock = NSLock()
    private var holed = false
    init(_ name: String, mbps: Double, delay: Double, target: UInt16) { self.name = name; self.mbps = mbps; self.delay = delay; self.target = target }

    var isHoled: Bool { lock.lock(); defer { lock.unlock() }; return holed }
    // The line goes silent: nothing moves any more, nothing is closed (the leg must notice by itself).
    func blackhole() { lock.lock(); holed = true; lock.unlock() }

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
        let limit = Int(mbps * 1e6 / 8 * delay) + 131_072
        Thread.detachNewThread { [self] in
            var buf = [UInt8](repeating: 0, count: 16384)
            while true {
                q.lock(); while queued >= limit { q.wait() }; q.unlock()
                while isHoled { sleep(1) }
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
            let now = bnow(), when = max(at + delay, nextFree)
            nextFree = max(when, now - 0.02) + Double(bytes.count * 8) / (mbps * 1e6)
            if when > now + 0.001 { usleep(UInt32((when - now) * 1e6)) }
            while isHoled { sleep(1) }
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

struct BondFetch { var ok = false, bytes = 0, length = -1, sha = "", secs = 0.0, why = "" }

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
    while true {
        let n = buf.withUnsafeMutableBytes { recv(outer, $0.baseAddress, 65536, 0) }
        if n <= 0 { break }
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
        if n < 20 { failures.append("fetch 3: only \(n) small fetches ran") }
        if gen < 1 { failures.append("fetch 3: no new generation after the hand-over (no GOAWAY seen)") }
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
