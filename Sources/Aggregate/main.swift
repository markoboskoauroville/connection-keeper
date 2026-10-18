// ck-aggregate: the aggregation server (v13, Marko 18.10.2026: "Start to build aggregation server and everything needed
// for this to work"). A proxy on 127.0.0.1:8857 (SOCKS5 and HTTP on the same port) that sends every new connection out
// through one of the Mac's lines, bound to its device, the faster line getting more of them. A browser opens many
// connections at once, so a page, a download manager or a speed test uses both lines together; one single connection
// stays on one line (joining one connection over two lines needs a server outside the house, see LESSONS).
//
// Only the connections ticked in the stripe's drop-down (request 28); none ticked: every line, for `test` only, since
// macOS then sends nothing here.
//
// Only lines that leave the house through different devices are joined (request 25): the cable and the Wi-Fi through
// the same TP-Link are one line (same public IP or the same router MAC); the cable is kept, the Wi-Fi ignored.
//
//   ck-aggregate serve           the server (the LaunchAgent runs this)
//   ck-aggregate uplinks         which lines are different, which are ignored
//   ck-aggregate test [s]        each line alone, then all through the server, down and up, s seconds each (default 6)
//   ck-aggregate test-line <n>   one line alone, down and up (a click on its row's speed)
//   ck-aggregate on | off        macOS's SOCKS proxy on every network service → the server, or back off
import Foundation
import Darwin

let speedURL = "https://proof.ovh.net/files/1Gb.dat"   // cut by time; Cloudflare slowed our downloads to 0.5 Mbit/s after a few tests (18.10.2026)

func log(_ s: String) {
    let f = ISO8601DateFormatter(); f.timeZone = .current
    FileHandle.standardError.write("\(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
}

// MARK: the lines

final class Uplink {
    let iface: String, name: String, gateway: String?, gatewayMAC: String?, publicIP: String?
    var mbps: Double = 10, alive = true, misses = 0, active = 0, connections = 0, bytesDown = 0, bytesUp = 0
    // BUSY, not open (18.10.2026: Chrome alone held 31 idle connections through the server and they counted as load):
    // the connections being dialled plus those that moved bytes in the last 5 s, by their client socket.
    var pending = 0, seen: [Int32: Date] = [:]
    func busy(_ now: Date) -> Int { pending + seen.values.filter { now.timeIntervalSince($0) < 5 }.count }
    init(iface: String, name: String, gateway: String?, gatewayMAC: String?, publicIP: String?) {
        self.iface = iface; self.name = name; self.gateway = gateway; self.gatewayMAC = gatewayMAC; self.publicIP = publicIP
    }
    func sameLine(_ o: Uplink) -> Bool {
        if let a = publicIP, a == o.publicIP { return true }
        if let a = gatewayMAC, a == o.gatewayMAC { return true }
        return false
    }
}

enum Lines {
    static func gateway(_ iface: String) -> String? {
        let g = shell("/usr/sbin/ipconfig", ["getoption", iface, "router"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? nil : g
    }
    static func gatewayMAC(_ gw: String, _ iface: String) -> String? {
        for line in shell("/usr/sbin/arp", ["-n", gw], timeout: 5).out.components(separatedBy: "\n") where line.contains("on \(iface)") {
            if let r = line.range(of: #" at ([0-9a-f:]+) "#, options: .regularExpression) {
                return String(line[r]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "at ", with: "")
            }
        }
        return nil
    }
    static func publicIP(_ iface: String) -> String? {
        let r = shell("/usr/bin/curl", ["-s", "-4", "-m", "6", "--interface", iface, "https://api.ipify.org"], timeout: 8)
        let ip = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && ip.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil ? ip : nil
    }

    // Every device with an address and a router (only the ticked ones when any is ticked), one per line out of the house. Of two devices on the same line the
    // cable is kept (steadier than the Wi-Fi). Devices with no internet are left out.
    // A device stays a line while it has an address and a router; whether it answers is the health check's word (a
    // single lost ping on a full 4G line dropped Something for a minute in the middle of the first joined test,
    // 18.10.2026). `known`: the public IPs found before, kept when a lookup fails under load.
    static func discover(known: [String: String] = [:]) -> (lines: [Uplink], ignored: [(Uplink, Uplink)]) {
        let wifi = Net.wifiInterface()
        let ticked = Set(Aggregation.selected)
        var found: [Uplink] = []
        for i in Net.activeInterfaces() {
            guard ticked.isEmpty || ticked.contains(Net.displayName(i)), let gw = gateway(i) else { continue }
            found.append(Uplink(iface: i, name: Net.displayName(i), gateway: gw, gatewayMAC: gatewayMAC(gw, i), publicIP: publicIP(i) ?? known[i]))
        }
        found.sort { ($0.iface == wifi ? 1 : 0) < ($1.iface == wifi ? 1 : 0) }
        var lines: [Uplink] = [], ignored: [(Uplink, Uplink)] = []
        for u in found {
            if let kept = lines.first(where: { $0.sameLine(u) }) { ignored.append((u, kept)) } else { lines.append(u) }
        }
        let w = savedSpeeds()
        for u in lines { if let m = w[u.publicIP ?? u.iface] { u.mbps = max(m, 0.5) } }
        return (lines, ignored)
    }

    // The last measured speed of each line (by its public IP, which follows the line across devices), from `test`.
    static func savedSpeeds() -> [String: Double] {
        guard let d = try? Data(contentsOf: Aggregation.speeds) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: d)) ?? [:]
    }
    static func saveSpeeds(_ m: [String: Double]) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        var all = savedSpeeds(); m.forEach { k, v in all[k] = all[k].map { ($0 + v) / 2 } ?? v }   // one 4G dip never starves a line
        try? JSONEncoder().encode(all).write(to: Aggregation.speeds)
    }
}

// MARK: sockets

let IP_BOUND_IF_: Int32 = 25, IPV6_BOUND_IF_: Int32 = 125

func readExact(_ fd: Int32, _ n: Int) -> [UInt8]? {
    var buf = [UInt8](repeating: 0, count: n), got = 0
    while got < n {
        let r = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, n - got, 0) }
        if r <= 0 { return nil }
        got += r
    }
    return buf
}
func sendAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var sent = 0
    while sent < bytes.count {
        let r = bytes.withUnsafeBytes { send(fd, $0.baseAddress! + sent, bytes.count - sent, 0) }
        if r <= 0 { return false }
        sent += r
    }
    return true
}

// A TCP connection to host:port that leaves through this one device (IP_BOUND_IF), or nil after `timeout` seconds.
func dial(_ host: String, _ port: UInt16, via iface: String, timeout: Int32 = 8) -> Int32? {
    var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC
    var res: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &res) == 0, let first = res else { return nil }
    defer { freeaddrinfo(first) }
    var addrs: [UnsafeMutablePointer<addrinfo>] = []
    var p: UnsafeMutablePointer<addrinfo>? = first
    while let a = p { addrs.append(a); p = a.pointee.ai_next }
    addrs.sort { ($0.pointee.ai_family == AF_INET ? 0 : 1) < ($1.pointee.ai_family == AF_INET ? 0 : 1) }   // 4G hotspots often lack IPv6
    var index = if_nametoindex(iface)
    for a in addrs {
        let fd = socket(a.pointee.ai_family, SOCK_STREAM, 0)
        if fd < 0 { continue }
        let v6 = a.pointee.ai_family == AF_INET6
        guard setsockopt(fd, v6 ? IPPROTO_IPV6 : IPPROTO_IP, v6 ? IPV6_BOUND_IF_ : IP_BOUND_IF_, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else { close(fd); continue }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var ok = connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen) == 0
        if !ok && errno == EINPROGRESS {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            if poll(&pfd, 1, timeout * 1000) == 1 {
                var err: Int32 = 0; var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
                ok = err == 0
            }
        }
        if ok { _ = fcntl(fd, F_SETFL, flags); prepare(fd); return fd }
        close(fd)
    }
    return nil
}

func prepare(_ fd: Int32) {
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
}

// MARK: the server

final class Server {
    let lock = NSLock()
    var lines: [Uplink] = []
    var ignored: [(Uplink, Uplink)] = []
    let started = Date()

    func refresh() {
        lock.lock()
        let known = Dictionary(lines.compactMap { u in u.publicIP.map { (u.iface, $0) } }, uniquingKeysWith: { a, _ in a })
        lock.unlock()
        let d = Lines.discover(known: known)
        lock.lock()
        // Counters stay with a line that is still there.
        for u in d.lines {
            if let old = lines.first(where: { $0.iface == u.iface && $0.publicIP == u.publicIP }) {
                u.alive = old.alive; u.misses = old.misses
                u.active = old.active; u.connections = old.connections; u.bytesDown = old.bytesDown; u.bytesUp = old.bytesUp
            }
        }
        let before = lines.map { "\($0.name)/\($0.iface)" }, after = d.lines.map { "\($0.name)/\($0.iface)" }
        lines = d.lines; ignored = d.ignored
        lock.unlock()
        if before != after {
            log("lines: \(d.lines.map { "\($0.name) (\($0.iface), \($0.publicIP ?? "?"), \(Int($0.mbps)) Mbit/s)" }.joined(separator: " + "))"
                + (d.ignored.isEmpty ? "" : "; ignored, same line: " + d.ignored.map { "\($0.0.name) = \($0.1.name)" }.joined(separator: ", ")))
        }
    }

    func health() {
        lock.lock(); let ls = lines; lock.unlock()
        for u in ls {
            let answered = Net.onlineVia(u.iface) != nil || Net.onlineVia(u.iface, host: "8.8.8.8") != nil
            lock.lock()
            u.misses = answered ? 0 : u.misses + 1
            let alive = answered || u.misses < 2              // dead after two silent checks in a row, not one lost ping
            if alive != u.alive { log("\(u.name) \(alive ? "is back" : "does not answer: new connections go to the others")") }
            u.alive = alive
            lock.unlock()
        }
    }

    // Out through the best line; if it cannot reach the host, through the next (a dead line is skipped this way too).
    func open(_ host: String, _ port: UInt16, for c: Int32) -> (Int32, Uplink)? {
        // The line is reserved before dialling, so connections arriving together spread over the lines (they all saw
        // "0 active" and took the same line in the first joined test).
        var tried = Set<String>()
        while true {
            lock.lock()
            let now = Date()
            let alive = lines.filter { !tried.contains($0.iface) }
            guard let u = alive.min(by: { a, b in
                if a.alive != b.alive { return a.alive }
                return Double(a.busy(now) + 1) / a.mbps < Double(b.busy(now) + 1) / b.mbps
            }) else { lock.unlock(); return nil }
            u.active += 1; u.pending += 1
            lock.unlock()
            if let fd = dial(host, port, via: u.iface) {
                lock.lock(); u.connections += 1; u.pending -= 1; u.seen[c] = Date(); lock.unlock()
                return (fd, u)
            }
            lock.lock(); u.active -= 1; u.pending -= 1; lock.unlock()
            tried.insert(u.iface)
        }
    }

    func run() {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET); addr.sin_port = aggPort.bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let b = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard b == 0, listen(s, 256) == 0 else { log("port \(aggPort) is taken: \(String(cString: strerror(errno)))"); exit(1) }
        refresh()
        Thread.detachNewThread { [self] in while true { sleep(20); health() } }
        // Again every minute (a Wi-Fi joined elsewhere, a cable pulled), and at once when the ticks change.
        Thread.detachNewThread { [self] in
            var last = Date(), ticks = Aggregation.selected
            while true {
                sleep(2)
                let now = Aggregation.selected
                if now != ticks || Date().timeIntervalSince(last) >= 60 { ticks = now; last = Date(); refresh() }
            }
        }
        log("ck-aggregate v\(CKVersion) on 127.0.0.1:\(aggPort) (SOCKS5 and HTTP)")
        while true {
            let c = accept(s, nil, nil)
            if c < 0 { continue }
            prepare(c)
            Thread.detachNewThread { [self] in handle(c) }
        }
    }

    func handle(_ c: Int32) {
        var first: UInt8 = 0
        guard recv(c, &first, 1, MSG_PEEK) == 1 else { close(c); return }
        if first == 5 { socks(c) } else { http(c) }
    }

    func socks(_ c: Int32) {
        guard let hello = readExact(c, 2), let _ = readExact(c, Int(hello[1])), sendAll(c, [5, 0]),
              let req = readExact(c, 4), req[1] == 1 else { close(c); return }
        var host = ""
        switch req[3] {
        case 1: guard let a = readExact(c, 4) else { close(c); return }; host = a.map(String.init).joined(separator: ".")
        case 3: guard let n = readExact(c, 1), let d = readExact(c, Int(n[0])) else { close(c); return }; host = String(decoding: d, as: UTF8.self)
        case 4:
            guard let a = readExact(c, 16) else { close(c); return }
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            _ = a.withUnsafeBytes { inet_ntop(AF_INET6, $0.baseAddress, &buf, socklen_t(buf.count)) }
            host = String(cString: buf)
        default: close(c); return
        }
        guard let p = readExact(c, 2) else { close(c); return }
        let port = UInt16(p[0]) << 8 | UInt16(p[1])
        guard let (out, u) = open(host, port, for: c) else { _ = sendAll(c, [5, 4, 0, 1, 0, 0, 0, 0, 0, 0]); close(c); return }
        guard sendAll(c, [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]) else { finish(c, out, u, 0, 0); return }
        relay(c, out, u)
    }

    func http(_ c: Int32) {
        var head = [UInt8]()
        while head.count < 65536 {
            guard let b = readExact(c, 1) else { close(c); return }
            head.append(b[0])
            if head.count >= 4 && head.suffix(4) == [13, 10, 13, 10] { break }
        }
        let text = String(decoding: head, as: UTF8.self)
        let line = (text.components(separatedBy: "\r\n").first ?? "").split(separator: " ").map(String.init)   // "\r\n" is one Character in Swift
        guard line.count >= 2 else { close(c); return }
        if line[0] == "CONNECT" {
            let hp = line[1].split(separator: ":", omittingEmptySubsequences: false)
            let host = hp.dropLast().joined(separator: ":").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard let port = UInt16(hp.last ?? ""), let (out, u) = open(host, port, for: c) else {
                _ = sendAll(c, Array("HTTP/1.1 502 Bad Gateway\r\n\r\n".utf8)); close(c); return
            }
            guard sendAll(c, Array("HTTP/1.1 200 Connection established\r\n\r\n".utf8)) else { finish(c, out, u, 0, 0); return }
            relay(c, out, u)
        } else if line[1].hasPrefix("/") {
            let body = line[1].hasPrefix("/status") ? status() : "ck-aggregate v\(CKVersion): use me as a SOCKS5 or HTTP proxy; /status for the lines\n"
            let type = line[1].hasPrefix("/status") ? "application/json" : "text/plain"
            _ = sendAll(c, Array("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8))
            close(c)
        } else if let url = URL(string: line[1]), let host = url.host {
            // Plain http://: the request goes on in origin form, one request per connection.
            let path = (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? "")
            var rest = text.components(separatedBy: "\r\n").dropFirst().filter { !$0.lowercased().hasPrefix("proxy-connection:") && !$0.lowercased().hasPrefix("connection:") }
            rest.insert("Connection: close", at: rest.count - 2)
            guard let (out, u) = open(host, UInt16(url.port ?? 80), for: c) else {
                _ = sendAll(c, Array("HTTP/1.1 502 Bad Gateway\r\n\r\n".utf8)); close(c); return
            }
            let req = "\(line[0]) \(path) \(line.count > 2 ? line[2] : "HTTP/1.1")\r\n" + rest.joined(separator: "\r\n")
            guard sendAll(out, Array(req.utf8)) else { finish(c, out, u, 0, 0); return }
            relay(c, out, u)
        } else {
            close(c)
        }
    }

    // Both directions copied until each side has said it is done; the bytes counted on the line.
    func relay(_ c: Int32, _ out: Int32, _ u: Uplink) {
        let group = DispatchGroup()
        var up = 0, down = 0, done = false
        func pump(_ from: Int32, _ to: Int32, _ count: @escaping (Int) -> Void) {
            var buf = [UInt8](repeating: 0, count: 65536), total = 0, touched = Date()
            while true {
                let n = buf.withUnsafeMutableBytes { recv(from, $0.baseAddress, 65536, 0) }
                if n <= 0 { break }
                if !sendAll(to, Array(buf[0..<n])) { break }
                total += n
                if total >= 1_048_576 || Date().timeIntervalSince(touched) > 1 { count(total); total = 0; touched = Date() }
            }
            count(total)
            shutdown(to, SHUT_WR)
            // One side has finished; the other gets 30 s to finish too, then the connection is ended (a peer that never
            // closes would hold its line's thread and socket for ever).
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [self] in
                lock.lock()                                    // under the lock: `done` is set before the sockets close
                if !done { shutdown(to, SHUT_RDWR); shutdown(from, SHUT_RDWR) }
                lock.unlock()
            }
        }
        group.enter()
        Thread.detachNewThread { [self] in pump(c, out) { n in self.lock.lock(); up += n; u.bytesUp += n; u.seen[c] = Date(); self.lock.unlock() }; group.leave() }
        pump(out, c) { n in self.lock.lock(); down += n; u.bytesDown += n; u.seen[c] = Date(); self.lock.unlock() }
        group.wait()
        lock.lock(); done = true; lock.unlock()
        finish(c, out, u, up, down)
    }

    func finish(_ c: Int32, _ out: Int32, _ u: Uplink, _ up: Int, _ down: Int) {
        lock.lock(); u.active -= 1; u.seen[c] = nil; lock.unlock()
        close(c); close(out)
    }

    func status() -> String {
        lock.lock(); defer { lock.unlock() }
        let ls: [[String: Any]] = lines.map { u in
            ["name": u.name, "device": u.iface, "publicIP": u.publicIP ?? "", "gateway": u.gateway ?? "", "mbps": u.mbps,
             "alive": u.alive, "active": u.active, "connections": u.connections, "mbDown": Double(u.bytesDown) / 1e6, "mbUp": Double(u.bytesUp) / 1e6]
        }
        let ig: [[String: String]] = ignored.map { ["name": $0.0.name, "device": $0.0.iface, "sameLineAs": $0.1.name] }
        let d: [String: Any] = ["version": CKVersion, "port": Int(aggPort), "since": ISO8601DateFormatter().string(from: started), "lines": ls, "ignored": ig]
        return String(decoding: try! JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self) + "\n"
    }
}

// MARK: the test

// v13 (request 30: "speed test when I click on the number for upload or download ... the same clicking applies to
// combinations so I can compare"): download and upload, each line alone, then all lines through the server.
let uploadFile = Paths.support.appendingPathComponent("upload-50MB.bin")
let uploadURL = "https://speed.cloudflare.com/__up"

// `streams` transfers at once for `seconds`, through one device or through the server; Mbit/s, MB spent and each
// line's share. The bytes are those macOS counts on each line's own default route (`ifaces`), what really went over
// the air: curl's own upload count through the server counted what the server took into its buffers, so the first
// joined upload read 64.8 Mbit/s over two lines that add up to 38 (18.10.2026).
func measure(_ how: [String], streams: Int, seconds: Int, up: Bool = false, ifaces: [String]) -> (mbps: Double, mb: Double, share: [String: Double]) {
    if up && !FileManager.default.fileExists(atPath: uploadFile.path) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: uploadFile.path, contents: Data(count: 50_000_000))
    }
    var procs: [(Process, Pipe)] = []
    let before = Traffic.internetAll()
    let t0 = Date()
    for _ in 0..<streams {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-s", "-o", "/dev/null", "-m", String(seconds), "-w", up ? "%{size_upload}" : "%{size_download}"] + how
            + (up ? ["--data-binary", "@" + uploadFile.path, uploadURL] : [speedURL])
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run(); procs.append((p, pipe))
    }
    var curlBytes = 0.0
    for (p, pipe) in procs {
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        curlBytes += Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    let secs = max(Date().timeIntervalSince(t0), 0.1)
    var share: [String: Double] = [:]
    if let before, let after = Traffic.internetAll() {
        for i in ifaces {
            guard let a = after[i], let b = before[i] else { continue }
            let n = up ? (a.tx >= b.tx ? a.tx - b.tx : 0) : (a.rx >= b.rx ? a.rx - b.rx : 0)
            share[i] = Double(n) * 8 / secs / 1e6
        }
    }
    let bytes = share.isEmpty ? curlBytes : share.values.reduce(0, +) * secs * 1e6 / 8
    return (bytes * 8 / secs / 1e6, bytes / 1e6, share)
}

func faster(_ joined: Double, _ best: Double) -> String {
    best > 0 && joined > best * 1.1 ? String(format: "%.0f%% faster than the best line alone", (joined / best - 1) * 100) : "not faster"
}

// `only`: one line by its name (a click on its row); nil: every line alone, then joined (a click on JOINED).
func test(seconds: Int, only: String? = nil) {
    let d = Lines.discover(), lines = d.lines.filter { only == nil || $0.name == only }
    for (u, kept) in d.ignored { print("ignored: \(u.name) (\(u.iface)) is the same line as \(kept.name) (public IP \(u.publicIP ?? "?"))") }
    guard !lines.isEmpty else { print(only.map { "\($0) is not a line now" } ?? "no line"); exit(1) }
    let old = AggTest.load()
    var spent = 0.0, alone = old?.alone ?? [:], aloneUp = old?.aloneUp ?? [:], speeds: [String: Double] = [:]
    for u in lines {
        let dn = measure(["--interface", u.iface], streams: 4, seconds: seconds, ifaces: [u.iface])
        let up = measure(["--interface", u.iface], streams: 4, seconds: seconds, up: true, ifaces: [u.iface])
        spent += dn.mb + up.mb; alone[u.name] = dn.mbps; aloneUp[u.name] = up.mbps; speeds[u.publicIP ?? u.iface] = dn.mbps
        print(String(format: "%@ (%@, %@) alone: down %.1f, up %.1f Mbit/s", u.name, u.iface, u.publicIP ?? "?", dn.mbps, up.mbps))
    }
    Lines.saveSpeeds(speeds)
    guard only == nil, lines.count > 1 else {
        AggTest(at: Date(), alone: alone, aloneUp: aloneUp, joined: old?.joined ?? 0, joinedUp: old?.joinedUp, mb: spent).save()
        print(String(format: "SIM data spent: %.0f MB", spent)); return
    }
    // The server, in this process unless the LaunchAgent's is running already.
    if shell("/usr/bin/curl", ["-s", "-m", "2", "http://127.0.0.1:\(aggPort)/status"], timeout: 3).status != 0 {
        Thread.detachNewThread { Server().run() }
        sleep(2)
        while shell("/usr/bin/curl", ["-s", "-m", "2", "http://127.0.0.1:\(aggPort)/status"], timeout: 3).status != 0 { sleep(1) }
    }
    let via = ["-x", "socks5h://127.0.0.1:\(aggPort)"]
    let dn = measure(via, streams: 4 * lines.count, seconds: seconds, ifaces: lines.map(\.iface))
    let up = measure(via, streams: 4 * lines.count, seconds: seconds, up: true, ifaces: lines.map(\.iface))
    func split(_ m: [String: Double]) -> String { lines.map { String(format: "%@ %.1f", $0.name, m[$0.iface] ?? 0) }.joined(separator: " + ") }
    spent += dn.mb + up.mb
    AggTest(at: Date(), alone: alone, aloneUp: aloneUp, joined: dn.mbps, joinedUp: up.mbps, mb: spent).save()
    let names = Set(lines.map(\.name))
    let bestDn = alone.filter { names.contains($0.key) }.values.max() ?? 0, bestUp = aloneUp.filter { names.contains($0.key) }.values.max() ?? 0
    print(String(format: "joined through the server: down %.1f Mbit/s (%@; best line alone %.1f): %@", dn.mbps, split(dn.share), bestDn, faster(dn.mbps, bestDn)))
    print(String(format: "joined through the server: up %.1f Mbit/s (%@; best line alone %.1f): %@", up.mbps, split(up.share), bestUp, faster(up.mbps, bestUp)))
    print(String(format: "SIM data spent: %.0f MB", spent))
}

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first ?? "" {
case "serve": Server().run()
case "uplinks":
    let d = Lines.discover()
    for u in d.lines { print("line: \(u.name) (\(u.iface)) gateway \(u.gateway ?? "?") \(u.gatewayMAC ?? "?") public \(u.publicIP ?? "?") \(Int(u.mbps)) Mbit/s") }
    for (u, k) in d.ignored { print("ignored: \(u.name) (\(u.iface)), the same line as \(k.name)") }
case "test": test(seconds: argv.count > 1 ? Int(argv[1]) ?? 6 : 6)
case "test-line" where argv.count > 1: test(seconds: argv.count > 2 ? Int(argv[2]) ?? 6 : 6, only: argv[1])
case "on": Aggregation.systemProxy(true).forEach { print($0) }
case "off": Aggregation.systemProxy(false).forEach { print($0) }
default: print("usage: ck-aggregate serve | uplinks | test [seconds] | test-line <name> [seconds] | on | off"); exit(2)
}
