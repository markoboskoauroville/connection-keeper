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

// Cut by time. Spread over four servers: after a few rounds on 18.10.2026 Cloudflare slowed our downloads to 0.5 Mbit/s
// and OVH answered 429 Too Many Requests; one stream per server and round keeps every one of them quiet.
let speedURLs = ["https://fsn1-speed.hetzner.com/1GB.bin", "https://nbg1-speed.hetzner.com/1GB.bin",
                 "https://proof.ovh.net/files/1Gb.dat", "http://speedtest.tele2.net/1GB.zip"]

func log(_ s: String) {
    let f = ISO8601DateFormatter(); f.timeZone = .current
    FileHandle.standardError.write("\(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
}

// MARK: the lines

final class Uplink {
    let iface: String, name: String, gateway: String?, gatewayMAC: String?, publicIP: String?
    var phone: Phone?                                    // v17: a phone over USB (adb), dialled as a SOCKS5 proxy
    var mbps: Double = 10, alive = true, misses = 0, active = 0, connections = 0, bytesDown = 0, bytesUp = 0
    // BUSY, not open (18.10.2026: Chrome alone held 31 idle connections through the server and they counted as load):
    // the connections being dialled plus those that moved bytes in the last 5 s, by their client socket.
    var pending = 0, seen: [Int32: Date] = [:]
    var lastGood = Date.distantPast, probing = false     // v31: the last proof it carries; a check under way
    func busy(_ now: Date) -> Int { pending + seen.values.filter { now.timeIntervalSince($0) < 5 }.count }
    init(iface: String, name: String, gateway: String?, gatewayMAC: String?, publicIP: String?) {
        self.iface = iface; self.name = name; self.gateway = gateway; self.gatewayMAC = gatewayMAC; self.publicIP = publicIP
    }
    var cellular = false                                 // a phone whose internet is its mobile data, not a Wi-Fi
    func sameLine(_ o: Uplink) -> Bool {
        // Two 4G lines of the same operator can leave through the same public address (carrier NAT): at 09:06 on
        // 31.10.2026 the Nothing (LTE, Telemach) read the TP-Link's 86.33.92.213 and was dropped as "the same line" for
        // three minutes. A phone on its own mobile data is its own radio, so its own line.
        if cellular || o.cellular { return false }
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
    static func discover(known: [String: String] = [:], anyLine: Bool = false) -> (lines: [Uplink], ignored: [(Uplink, Uplink)]) {
        let wifi = Net.wifiInterface()
        let ticked = anyLine ? [] : Set(Aggregation.selected)
        var found: [Uplink] = []
        for i in Net.activeInterfaces() {
            guard ticked.isEmpty || ticked.contains(Net.displayName(i)), let gw = gateway(i) else { continue }
            found.append(Uplink(iface: i, name: Net.displayName(i), gateway: gw, gatewayMAC: gatewayMAC(gw, i), publicIP: publicIP(i) ?? known[i]))
        }
        // v17 (request 36): every phone on a USB cable with its server answering is a line of its own.
        for p in Phones.list() where ticked.isEmpty || ticked.contains(p.name) {
            if let note = Phones.ensure(p) { log("\(p.name): \(note)") }
            guard Phones.answers(p) else { continue }
            // v43 (1.11.2026): in WIRES a phone is a line by its mobile data only. When its data went off for a moment
            // (the cut test at 04:08) Android joined the house Wi-Fi and stayed on it after the data came back; its
            // traffic then left through the TP-Link and the line was dropped as "the same line as AX88179B". Its Wi-Fi
            // goes off here, as WIRES means (the radios are off in WIRES), and it is looked at again.
            if !Phones.onMobileData(p), let adb = Phones.adb,
               ((try? String(contentsOf: Paths.support.appendingPathComponent("wires"), encoding: .utf8)) ?? "").hasPrefix("wires") {
                shell(adb, ["-s", p.serial, "shell", "svc", "wifi", "disable"], timeout: 6)
                log("\(p.name) was on a Wi-Fi in WIRES: its Wi-Fi switched off, so it goes out on its mobile data")
                for _ in 0..<10 where !Phones.onMobileData(p) { usleep(500_000) }
            }
            let u = Uplink(iface: p.device, name: p.name, gateway: nil, gatewayMAC: nil, publicIP: Phones.publicIP(p) ?? known[p.device])
            u.phone = p; u.cellular = Phones.onMobileData(p); found.append(u)
        }
        found.sort { ($0.iface == wifi ? 1 : 0) < ($1.iface == wifi ? 1 : 0) }
        var lines: [Uplink] = [], ignored: [(Uplink, Uplink)] = []
        for u in found {
            if let kept = lines.first(where: { $0.sameLine(u) }) { ignored.append((u, kept)) } else { lines.append(u) }
        }
        let w = savedSpeeds()
        for u in lines { if let m = w[u.publicIP ?? u.iface] { u.mbps = max(m, 0.5) } }
        // NO TICKED LINE HERE (31.10.2026, 10:17: Marko pulled the cable and the Nothing and plugged in the Pixel; the Mac's
        // Wi-Fi was not ticked, the server had no line, and the tunnel carried nothing for 20 s until it stepped aside):
        // then every line with a router or a phone, so the Mac is never left without a road while the tunnel is up.
        if lines.isEmpty && !ticked.isEmpty {
            let any = discover(known: known, anyLine: true)
            if !any.lines.isEmpty { log("no ticked line is here: using \(any.lines.map(\.name).joined(separator: " + ")) until one comes back") }
            return any
        }
        // ONLY PHONES TICKED (31.10.2026): a phone carries TCP only, so calls, QUIC and other UDP had no road at all;
        // the Mac's own lines (Wi-Fi, cable) join so UDP has one.
        if !anyLine && !lines.isEmpty && lines.allSatisfy({ $0.phone != nil }) {
            let mac = discover(known: known, anyLine: true).lines.filter { $0.phone == nil && !lines.contains(where: $0.sameLine) }
            if !mac.isEmpty { log("only phones ticked: \(mac.map(\.name).joined(separator: " + ")) joins for UDP"); return (lines + mac, ignored) }
        }
        return (lines, ignored)
    }

    // THE LINES REMEMBERED (v41, request 57, Marko 31.10.2026: "Can this time be improved?"): a restart left the server
    // with no line for ~7 s while it asked every device for its router and public address, and every connection of the
    // Mac waited. The lines are written down whenever they change; at start those whose device still has an address
    // carry traffic at once, and the full search replaces them a few seconds later (a gone one fails over in the race).
    struct Saved: Codable { let iface, name: String; let gateway, gatewayMAC, publicIP: String?; let serial: String?; let port: UInt16?; let cellular: Bool }
    static func remember(_ ls: [Uplink]) {
        let all = ls.map { Saved(iface: $0.iface, name: $0.name, gateway: $0.gateway, gatewayMAC: $0.gatewayMAC, publicIP: $0.publicIP,
                                 serial: $0.phone?.serial, port: $0.phone?.port, cellular: $0.cellular) }
        try? JSONEncoder().encode(all).write(to: Aggregation.remembered)
    }
    static func remembered() -> [Uplink] {
        guard let d = try? Data(contentsOf: Aggregation.remembered), let all = try? JSONDecoder().decode([Saved].self, from: d) else { return [] }
        let w = savedSpeeds()
        return all.compactMap { s in
            if s.serial == nil && ipv4(of: s.iface) == nil { return nil }     // the device is gone or has no address
            let u = Uplink(iface: s.iface, name: s.name, gateway: s.gateway, gatewayMAC: s.gatewayMAC, publicIP: s.publicIP)
            if let serial = s.serial, let port = s.port { u.phone = Phone(serial: serial, name: s.name, port: port) }
            u.cellular = s.cellular
            if let m = w[u.publicIP ?? u.iface] { u.mbps = max(m, 0.5) }
            return u
        }
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

// The device's own IPv4 address, from the kernel's table (no process per connection).
func ipv4(of iface: String) -> in_addr? {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
    defer { freeifaddrs(ifap) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let a = p {
        if let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: a.pointee.ifa_name) == iface {
            return addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        }
        p = a.pointee.ifa_next
    }
    return nil
}

// A TCP connection to host:port that leaves through this one device, or nil after `timeout` seconds. The socket is
// bound to the device (IP_BOUND_IF) AND to its address, as `curl --interface` does: with IP_BOUND_IF alone four of
// six connections hung until the timeout on 18.10.2026.
func dial(_ host: String, _ port: UInt16, via iface: String, timeout: Int32 = 5) -> Int32? {
    // v31: the names through Resolver (kept 5 min, never a hang on a dead line's DNS); the port written into each address
    var addrs = Resolver.addresses(host).map { d -> Data in var d = d; d[2] = UInt8(port >> 8); d[3] = UInt8(port & 255); return d }
    func family(_ d: Data) -> Int32 { Int32(d[1]) }
    addrs.sort { (family($0) == AF_INET ? 0 : 1) < (family($1) == AF_INET ? 0 : 1) }   // 4G hotspots often lack IPv6
    var index = if_nametoindex(iface)
    for d in addrs {
        let fd = socket(family(d), SOCK_STREAM, 0)
        if fd < 0 { continue }
        let v6 = family(d) == AF_INET6
        guard setsockopt(fd, v6 ? IPPROTO_IPV6 : IPPROTO_IP, v6 ? IPV6_BOUND_IF_ : IP_BOUND_IF_, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else { close(fd); continue }
        if !v6, let src = ipv4(of: iface) {
            var sa = sockaddr_in(); sa.sin_family = sa_family_t(AF_INET); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); sa.sin_addr = src
            let b = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            if b != 0 { close(fd); continue }
        }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var ok = d.withUnsafeBytes { connect(fd, $0.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(d.count)) } == 0
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

// THE OUTAGE (request 55, Marko 31.10.2026: "this application bugged out the connection on my computer. I couldn't use any
// internet"). launchd gives its agents 256 open files; each connection takes two, so at about 125 connections every new
// one failed, the server's own adb / ipconfig / curl could no longer start and it lost its lines; a client that never
// spoke held its file for ever. Measured on a test copy: 250 at once, 131 failed; 124 held open, 20 of 20 new failed.
// Now: 16384 files, at most 1500 clients (two threads each, 4096 per process), refused at once beyond that, and 15 s for
// a client to say where it goes.
let openFiles: Int = {
    var r = rlimit()
    getrlimit(RLIMIT_NOFILE, &r)
    let want = min(rlim_t(16384), r.rlim_max)
    if r.rlim_cur < want { r.rlim_cur = want; setrlimit(RLIMIT_NOFILE, &r) }
    getrlimit(RLIMIT_NOFILE, &r)
    return Int(r.rlim_cur)
}()
let maxClients = min(1500, max(openFiles / 3, 50))

// A receive deadline on a socket, in seconds; 0 waits for ever (the relay: an idle connection may sleep for hours).
func deadline(_ fd: Int32, _ seconds: Int) {
    var tv = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
}

func prepare(_ fd: Int32) {
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
}

// MARK: the server

final class Server {
    let lock = NSLock()
    var clients = 0
    var lines: [Uplink] = []
    var ignored: [(Uplink, Uplink)] = []
    let started = Date()

    func refresh() {
        lock.lock()
        let known = Dictionary(lines.compactMap { u in u.publicIP.map { (u.iface, $0) } }, uniquingKeysWith: { a, _ in a })
        lock.unlock()
        let d = Lines.discover(known: known)
        lock.lock()
        // A line that is still there stays the same object (request 55, 31.10.2026): the connections it carries end on
        // it, so its counters stay true. A copy, as before, kept every connection open at a refresh as "active" for
        // ever (2895 on the cable after four hours) and lost the busy marks the balance reads.
        let fresh = d.lines.map { u -> Uplink in
            guard let old = lines.first(where: { $0.iface == u.iface && $0.publicIP == u.publicIP }) else { return u }
            old.mbps = u.mbps; old.phone = u.phone
            return old
        }
        let before = lines.map { "\($0.name)/\($0.iface)" }, after = fresh.map { "\($0.name)/\($0.iface)" }
        lines = fresh; ignored = d.ignored
        lock.unlock()
        if !fresh.isEmpty { Lines.remember(fresh) }
        if before != after {
            log("lines: \(d.lines.map { "\($0.name) (\($0.iface), \($0.publicIP ?? "?"), \(Int($0.mbps)) Mbit/s)" }.joined(separator: " + "))"
                + (d.ignored.isEmpty ? "" : "; ignored, same line: " + d.ignored.map { "\($0.0.name) = \($0.1.name)" }.joined(separator: ", ")))
        }
    }

    func health() {
        lock.lock(); let ls = lines; lock.unlock()
        for u in ls {
            let answered = u.phone.map { p in Phones.online(p) != nil || Phones.online(p, host: "8.8.8.8") != nil }
                ?? (Net.onlineVia(u.iface) != nil || Net.onlineVia(u.iface, host: "8.8.8.8") != nil)
            lock.lock()
            u.misses = answered ? 0 : u.misses + 1
            let alive = answered || u.misses < 2              // dead after two silent checks in a row, not one lost ping
            if alive != u.alive { log("\(u.name) \(alive ? "is back" : "does not answer: new connections go to the others")") }
            u.alive = alive
            lock.unlock()
        }
    }

    // Out through the best line; if it cannot reach the host, through the next (a dead line is skipped this way too).
    func open(_ host: String, _ port: UInt16, for c: Int32) -> (Int32, Uplink)? { race(host, port, for: c) }   // v31

    func openOneByOne(_ host: String, _ port: UInt16, for c: Int32) -> (Int32, Uplink)? {
        // The line is reserved before dialling, so connections arriving together spread over the lines (they all saw
        // "0 active" and took the same line in the first joined test).
        var tried = Set<String>()
        for _ in 0..<100 { lock.lock(); let none = lines.isEmpty; lock.unlock(); if !none { break }; usleep(200_000) }
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
            if let fd = u.phone.map({ Phones.dial(host, port, via: $0.port) }) ?? dial(host, port, via: u.iface) {
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
        // macOS's SOCKS proxy setting points at this number, so it never moves: the one owner in the Mac's port
        // registry (MANTRA_PORTS v2, 27.10.2026), and `mantra-ports check` names a stranger on it
        if !aggTestCopy { Ports.record("aggregate", aggPort, udp: false, health: "/status") }
        // Answering at once: finding the lines takes 10-20 s (pings, public IPs), and with the virtual device the whole
        // Mac waits for the server after each restart. The first connections wait for the lines in open().
        // v41: the remembered lines carry traffic from the first second; the search below replaces them.
        // Nothing remembered (the first run): every device with an address and a router, without the slow public-address
        // lookups, so the Mac's own roads carry traffic until the search has finished.
        var saved = Lines.remembered(), how = "the remembered lines"
        if saved.isEmpty {
            how = "the devices with a router"
            saved = Net.activeInterfaces().compactMap { i in Lines.gateway(i).map { Uplink(iface: i, name: Net.displayName(i), gateway: $0, gatewayMAC: nil, publicIP: nil) } }
        }
        if !saved.isEmpty {
            lock.lock(); if lines.isEmpty { lines = saved }; lock.unlock()
            log("started on \(how): \(saved.map { "\($0.name) (\($0.iface))" }.joined(separator: " + ")); finding them again")
        }
        Thread.detachNewThread { [self] in refresh() }
        // v31 (request 48): every line checked every 3 s (Failover.swift), not every 20 s
        Resolver.lines = { [self] in lock.lock(); defer { lock.unlock() }; return lines }
        Thread.detachNewThread { [self] in while true { sleep(3); checkLines() } }
        // Again every minute (a Wi-Fi joined elsewhere, a cable pulled), and at once when the ticks change.
        // v32 (request 49): at once too when a device comes or goes (a phone plugged in, a cable), and when ⟳ is pressed.
        Thread.detachNewThread { [self] in
            var last = Date(), ticks = Aggregation.selected, devices = deviceFingerprint()
            while true {
                sleep(1)
                if !aggTestCopy && FileManager.default.fileExists(atPath: Aggregation.rescanFile.path) {
                    try? FileManager.default.removeItem(at: Aggregation.rescanFile)
                    log("RESCAN asked from the stripe: every device and phone found again, every line checked")
                    rescan(); ticks = Aggregation.selected; last = Date(); devices = deviceFingerprint()
                    continue
                }
                let d = deviceFingerprint()
                if d != devices {
                    log("devices changed (\(devices.joined(separator: " ")) → \(d.joined(separator: " "))): lines found again")
                    joinPlugged(Set(d).subtracting(devices))
                    devices = d
                    refresh(); checkLines(); ticks = Aggregation.selected; last = Date()
                    continue
                }
                let now = Aggregation.selected
                if now != ticks || Date().timeIntervalSince(last) >= 60 { ticks = now; last = Date(); refresh() }
            }
        }
        log("ck-aggregate v\(CKVersion) on 127.0.0.1:\(aggPort) (SOCKS5 and HTTP), \(openFiles) files, \(maxClients) clients at most")
        var refusedAt = Date.distantPast
        while true {
            let c = accept(s, nil, nil)
            if c < 0 { usleep(20_000); continue }               // out of files for a moment: never a loop at full speed
            lock.lock(); let full = clients >= maxClients; if !full { clients += 1 }; lock.unlock()
            if full {
                close(c)                                          // refused at once: the program asks again, nothing hangs
                if Date().timeIntervalSince(refusedAt) > 60 { refusedAt = Date(); log("\(maxClients) connections open: new ones refused until some end") }
                continue
            }
            prepare(c)
            deadline(c, 15)                                       // a client that says nothing is let go after 15 s
            Thread.detachNewThread { [self] in handle(c); lock.lock(); clients -= 1; lock.unlock() }
        }
    }

    // ⟳ (v32): the lines found again and every one of them checked now, not after its 3 s; the answer for the stripe.
    func rescan() {
        refresh()
        lock.lock(); for u in lines { u.lastGood = .distantPast }; lock.unlock()
        checkLines()
        for _ in 0..<20 { lock.lock(); let busy = lines.contains { $0.probing }; lock.unlock(); if !busy { break }; usleep(250_000) }
        lock.lock()
        let said = lines.map { "\($0.name) (\($0.alive ? "alive" : "silent"))" }
        lock.unlock()
        log("RESCAN done: " + (said.isEmpty ? "no line" : said.joined(separator: " + ")))
        try? ([ISO8601DateFormatter().string(from: Date())] + said).joined(separator: "\n").write(to: Aggregation.rescanDone, atomically: true, encoding: .utf8)
    }

    // A device plugged in while lines are ticked joins them by itself (request 49: "I plugged in my phone, and it's not
    // automatically recognized"): a phone on USB or a cable that appeared since the last look (`appeared`: entries of
    // deviceFingerprint). A Wi-Fi is never ticked this way (WIRES and WI-FI switch it on and off; that is not a plug),
    // nor a device he unticked while it stayed plugged in.
    func joinPlugged(_ appeared: Set<String>) {
        let ticks = Aggregation.selected
        guard !aggTestCopy, Aggregation.aggregateMode, !ticks.isEmpty, !appeared.isEmpty else { return }
        let wifi = Net.wifiInterface()
        var names: [String] = []
        for e in appeared.sorted() {
            if e.hasPrefix("adb:") {
                let serial = String(e.dropFirst(4).split(separator: "=").first ?? "")
                guard e.hasSuffix("=device") else { continue }        // unauthorized, offline: not a line yet
                for _ in 0..<5 {                                       // adb names it a moment after it is seen
                    if let p = Phones.list().first(where: { $0.serial == serial }) { names.append(p.name); break }
                    sleep(1)
                }
            } else if e != wifi {
                names.append(Net.displayName(e))
            }
        }
        let new = names.filter { !ticks.contains($0) }
        if !new.isEmpty {
            Aggregation.selected = ticks + new
            log("plugged in: \(new.joined(separator: ", ")): joined")
        }
    }
}

// The devices with an IPv4 address (not the tunnel, loopback or Apple's own) and the phones adb sees, with their state:
// cheap (no program but adb), so it is asked every second; a change means something was plugged in or pulled out.
func deviceFingerprint() -> [String] {
    var out: [String] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&ifap) == 0, let first = ifap {
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            let name = String(cString: a.pointee.ifa_name)
            if let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               !["lo", "utun", "awdl", "llw", "anpi", "ap", "bridge", "gif", "stf"].contains(where: { name.hasPrefix($0) }) {
                out.append(name)
            }
            p = a.pointee.ifa_next
        }
        freeifaddrs(ifap)
    }
    if let adb = Phones.adb {
        for line in shell(adb, ["devices"], timeout: 5).out.components(separatedBy: "\n").dropFirst() {
            let f = line.split(separator: "\t").map(String.init)
            if f.count == 2 { out.append("adb:\(f[0])=\(f[1])") }
        }
    }
    return Array(Set(out)).sorted()
}

extension Server {
    func handle(_ c: Int32) {
        var first: UInt8 = 0
        guard recv(c, &first, 1, MSG_PEEK) == 1 else { close(c); return }
        if first == 5 { socks(c) } else { http(c) }
    }

    func socks(_ c: Int32) {
        guard let hello = readExact(c, 2), let _ = readExact(c, Int(hello[1])), sendAll(c, [5, 0]),
              let req = readExact(c, 4), req[1] == 1 || req[1] == 3 else { close(c); return }
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
        if req[1] == 3 { udp(c); return }
        guard let (out, u) = open(host, port, for: c) else { _ = sendAll(c, [5, 4, 0, 1, 0, 0, 0, 0, 0, 0]); close(c); return }
        guard sendAll(c, [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]) else { finish(c, out, u, 0, 0); return }
        relay(c, out, u)
    }

    // UDP (v14, for the virtual device mantra_networkaggregate: name lookups, QUIC, calls): SOCKS5 UDP ASSOCIATE. A UDP
    // socket on 127.0.0.1 for the client and one UDP socket out through ONE line: the whole association stays on it,
    // since a QUIC connection or a call must keep its path. It lives as long as the client's TCP connection. IPv4 only.
    func udp(_ c: Int32) {
        deadline(c, 0)
        for _ in 0..<100 { lock.lock(); let none = lines.isEmpty; lock.unlock(); if !none { break }; usleep(200_000) }
        lock.lock()
        let now = Date()
        let pick = lines.filter { $0.alive && $0.phone == nil }.min { Double($0.busy(now) + 1) / $0.mbps < Double($1.busy(now) + 1) / $1.mbps } ?? lines.first { $0.phone == nil }   // adb carries TCP only: UDP never goes to a phone
        if let u = pick { u.active += 1; u.connections += 1; u.seen[c] = now }
        lock.unlock()
        let fail: [UInt8] = [5, 1, 0, 1, 0, 0, 0, 0, 0, 0]
        guard let u = pick else { _ = sendAll(c, fail); close(c); return }
        let local = socket(AF_INET, SOCK_DGRAM, 0), out = socket(AF_INET, SOCK_DGRAM, 0)
        func done() { close(local); close(out); lock.lock(); u.active -= 1; u.seen[c] = nil; lock.unlock(); close(c) }
        var la = sockaddr_in(); la.sin_family = sa_family_t(AF_INET); la.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); la.sin_addr.s_addr = inet_addr("127.0.0.1")
        var index = if_nametoindex(u.iface)
        var oa = sockaddr_in(); oa.sin_family = sa_family_t(AF_INET); oa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        if let src = ipv4(of: u.iface) { oa.sin_addr = src }
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard local >= 0, out >= 0,
              withUnsafePointer(to: &la, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(local, $0, size) } }) == 0,
              setsockopt(out, IPPROTO_IP, IP_BOUND_IF_, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0,
              withUnsafePointer(to: &oa, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(out, $0, size) } }) == 0 else {
            _ = sendAll(c, fail); done(); return
        }
        var len = size
        _ = withUnsafeMutablePointer(to: &la) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(local, $0, &len) } }
        let lp = UInt16(bigEndian: la.sin_port)
        guard sendAll(c, [5, 0, 0, 1, 127, 0, 0, 1, UInt8(lp >> 8), UInt8(lp & 255)]) else { done(); return }

        var running = true, client: sockaddr_in?, names: [String: in_addr] = [:]
        let box = NSLock(), group = DispatchGroup()
        func flush(_ up: inout Int, _ down: inout Int) {
            lock.lock(); u.bytesUp += up; u.bytesDown += down; u.seen[c] = Date(); lock.unlock(); up = 0; down = 0
        }
        // client → the internet: [0, 0, frag, atyp, address, port, data]
        group.enter()
        Thread.detachNewThread { [self] in
            var buf = [UInt8](repeating: 0, count: 65536), up = 0, none = 0, last = Date()
            while true {
                box.lock(); let go = running; box.unlock()
                if !go { break }
                var pfd = pollfd(fd: local, events: Int16(POLLIN), revents: 0)
                if poll(&pfd, 1, 1000) != 1 { continue }
                var from = sockaddr_in(); var fl = size
                let n = buf.withUnsafeMutableBytes { b in withUnsafeMutablePointer(to: &from) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(local, b.baseAddress, 65536, 0, $0, &fl) } } }
                guard n > 10, buf[2] == 0 else { continue }                      // fragments are not supported (none are sent)
                box.lock(); client = from; box.unlock()
                var dst = sockaddr_in(); dst.sin_family = sa_family_t(AF_INET); dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                var at = 4
                switch buf[3] {
                case 1: memcpy(&dst.sin_addr, Array(buf[4..<8]), 4); at = 8
                case 3:
                    let l = Int(buf[4]); guard n > 5 + l + 2 else { continue }
                    let name = String(decoding: buf[5..<(5 + l)], as: UTF8.self); at = 5 + l
                    if let a = names[name] { dst.sin_addr = a } else {
                        var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM
                        var res: UnsafeMutablePointer<addrinfo>?
                        guard getaddrinfo(name, nil, &hints, &res) == 0, let r = res else { continue }
                        let a = r.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                        freeaddrinfo(r); names[name] = a; dst.sin_addr = a
                    }
                default: none += 1; continue                                     // IPv6: the sender falls back to IPv4
                }
                dst.sin_port = (UInt16(buf[at]) << 8 | UInt16(buf[at + 1])).bigEndian
                let data = at + 2
                // v31: this association's line is dead and it is a name lookup: over TCP through a live line instead
                lock.lock(); let lineAlive = u.alive; lock.unlock()
                if !lineAlive && UInt16(bigEndian: dst.sin_port) == 53, let to = client {
                    let query = Array(buf[data..<n]), origin = dst.sin_addr
                    Thread.detachNewThread { [self] in dnsOverTCP(query, origin: origin, to: to, via: local) }
                    continue
                }
                let sent = buf.withUnsafeBytes { b in withUnsafePointer(to: &dst) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(out, b.baseAddress! + data, n - data, 0, $0, size) } } }
                if sent > 0 { up += sent }
                if Date().timeIntervalSince(last) > 1 { var d = 0; flush(&up, &d); last = Date() }
            }
            var d = 0; flush(&up, &d)
            group.leave()
        }
        // the internet → client, with the sender's address in front
        group.enter()
        Thread.detachNewThread { [self] in
            var buf = [UInt8](repeating: 0, count: 65536), down = 0, last = Date()
            while true {
                box.lock(); let go = running; box.unlock()
                if !go { break }
                var pfd = pollfd(fd: out, events: Int16(POLLIN), revents: 0)
                if poll(&pfd, 1, 1000) != 1 { continue }
                var from = sockaddr_in(); var fl = size
                let n = buf.withUnsafeMutableBytes { b in withUnsafeMutablePointer(to: &from) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(out, b.baseAddress, 65536, 0, $0, &fl) } } }
                box.lock(); let to = client; box.unlock()        // after the packet: the first reply comes within the wait
                guard n > 0, var dest = to else { continue }
                var packet: [UInt8] = [0, 0, 0, 1]
                withUnsafeBytes(of: from.sin_addr) { packet += $0 }
                let port = UInt16(bigEndian: from.sin_port)
                packet += [UInt8(port >> 8), UInt8(port & 255)]
                packet += buf[0..<n]
                let sent = packet.withUnsafeBytes { b in withUnsafePointer(to: &dest) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(local, b.baseAddress, packet.count, 0, $0, size) } } }
                if sent > 0 { down += n }
                if Date().timeIntervalSince(last) > 1 { var u0 = 0; flush(&u0, &down); last = Date() }
            }
            var u0 = 0; flush(&u0, &down)
            group.leave()
        }
        // The association ends with the client's TCP connection.
        var b: UInt8 = 0
        while recv(c, &b, 1, 0) > 0 {}
        box.lock(); running = false; box.unlock()
        group.wait()
        done()
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
        deadline(c, 0)
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
    let phones = ifaces.filter(Phones.isPhone)
    func phoneCounts() -> [String: (rx: UInt64, tx: UInt64)] {
        Dictionary(uniqueKeysWithValues: phones.compactMap { d in Phones.counters(String(d.dropFirst(4))).map { (d, $0) } })
    }
    let before = Traffic.internetAll(), phonesBefore = phoneCounts()
    let t0 = Date()
    for i in 0..<streams {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-s", "-o", "/dev/null", "-m", String(seconds), "-w", up ? "%{size_upload}" : "%{size_download}"] + how
            + (up ? ["--data-binary", "@" + uploadFile.path, uploadURL] : [speedURLs[i % speedURLs.count]])
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
    let phonesAfter = phoneCounts()
    var share: [String: Double] = [:]
    if let before, let after = Traffic.internetAll() {
        for i in ifaces {
            guard let a = after[i], let b = before[i] else { continue }
            let n = up ? (a.tx >= b.tx ? a.tx - b.tx : 0) : (a.rx >= b.rx ? a.rx - b.rx : 0)
            share[i] = Double(n) * 8 / secs / 1e6
        }
    }
    // v17: a phone line has no counter on the Mac: the phone's own, read over adb
    for d in phones {
        guard let a = phonesAfter[d], let b = phonesBefore[d] else { continue }
        let n = up ? (a.tx >= b.tx ? a.tx - b.tx : 0) : (a.rx >= b.rx ? a.rx - b.rx : 0)
        share[d] = Double(n) * 8 / secs / 1e6
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
        let how = u.phone.map { ["-x", "socks5h://127.0.0.1:\($0.port)"] } ?? ["--interface", u.iface]
        let dn = measure(how, streams: 4, seconds: seconds, ifaces: [u.iface])
        let up = measure(how, streams: 4, seconds: seconds, up: true, ifaces: [u.iface])
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
    // and until it has found every line (finding a phone's public IP takes some seconds; the first joined test of
    // 19.10.2026 ran out before the server knew any line and read 0.0)
    for _ in 0..<30 where (Aggregation.status()?.lines.count ?? 0) < lines.count { sleep(1) }
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
