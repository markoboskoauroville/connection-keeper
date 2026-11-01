// FASTER SWITCHING BETWEEN THE LINES (v31, request 48, Marko 28.10.2026: "optimize speed of switching between lines").
// The cut test of that morning: with mantra cut, every new connection timed out until a minute after it came back, for
// three reasons, each answered here:
//   1. the server saw the dead line after 43 s (a ping every 20 s, two misses): now a TCP handshake to 1.1.1.1:443 every
//      3 s on each line, dead after two misses (about 6 s), and at once when its device has lost its address; a line
//      that just carried a new connection is not probed (its own traffic says it lives);
//   2. a new connection waited up to 5 s per address on the first line before trying the next: now the next line starts
//      after 1 s, both race, the first to answer wins and the other is closed;
//   3. the name lookup (getaddrinfo) could hang on the dead line's DNS: now every answer is kept 5 minutes, a lookup
//      that takes more than 2 s uses the last answer, and with none it asks 1.1.1.1 over TCP through a live line.
import Foundation
import Darwin

// MARK: the names

final class Box<T> { var value: T; init(_ v: T) { value = v } }

enum Resolver {
    static let lock = NSLock()
    static var cache: [String: (addrs: [Data], at: Date)] = [:]
    static var lines: () -> [Uplink] = { [] }           // the server's lines, for a lookup through a live one
    static let keep: TimeInterval = 300, patience: TimeInterval = 2

    // Socket addresses (port 0) for host: an IP as it is, else the system's answer, the kept one or 1.1.1.1's.
    static func addresses(_ host: String) -> [Data] {
        if let n = system(host, numeric: true), !n.isEmpty { return n }
        lock.lock(); let kept = cache[host]; lock.unlock()
        if let kept, Date().timeIntervalSince(kept.at) < keep { return kept.addrs }
        let got = Box<[Data]?>(nil), done = DispatchSemaphore(value: 0)
        Thread.detachNewThread { got.value = system(host, numeric: false); done.signal() }
        if done.wait(timeout: .now() + patience) == .success, let a = got.value, !a.isEmpty { store(host, a); return a }
        if let kept { log("DNS \(host): slow, the answer of \(Int(Date().timeIntervalSince(kept.at))) s ago used"); return kept.addrs }
        for u in lines() where u.alive {
            if let a = overTCP(host, via: u), !a.isEmpty { log("DNS \(host): asked 1.1.1.1 through \(u.name)"); store(host, a); return a }
        }
        _ = done.wait(timeout: .now() + 4)              // nothing else to try: give the system a little longer
        if let a = got.value, !a.isEmpty { store(host, a); return a }
        return []
    }

    static func store(_ host: String, _ a: [Data]) { lock.lock(); cache[host] = (a, Date()); lock.unlock() }

    static func system(_ host: String, numeric: Bool) -> [Data]? {
        var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC
        if numeric { hints.ai_flags = AI_NUMERICHOST }
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(first) }
        var out: [Data] = []
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let a = p {
            if let sa = a.pointee.ai_addr { out.append(Data(bytes: sa, count: Int(a.pointee.ai_addrlen))) }
            p = a.pointee.ai_next
        }
        return out
    }

    // One A query over TCP to 1.1.1.1:53 through this line (the phone carries TCP only, so not UDP).
    static func overTCP(_ host: String, via u: Uplink) -> [Data]? {
        guard let fd = u.phone.map({ Phones.dial("1.1.1.1", 53, via: $0.port, timeout: 3) }) ?? dial("1.1.1.1", 53, via: u.iface, timeout: 2) else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let id = UInt16.random(in: 0...UInt16.max)
        var q: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in host.split(separator: ".") { let b = Array(label.utf8); guard b.count < 64 else { return nil }; q += [UInt8(b.count)] + b }
        q += [0, 0, 1, 0, 1]
        guard sendAll(fd, [UInt8(q.count >> 8), UInt8(q.count & 255)] + q), let lp = readExact(fd, 2) else { return nil }
        let n = Int(lp[0]) << 8 | Int(lp[1])
        guard n >= 12, let r = readExact(fd, n), r[0] == q[0], r[1] == q[1] else { return nil }
        func skipName(_ i: inout Int) -> Bool {
            while i < r.count {
                let l = Int(r[i])
                if l == 0 { i += 1; return true }
                if l & 0xC0 == 0xC0 { i += 2; return true }
                i += l + 1
            }
            return false
        }
        var i = 12
        guard skipName(&i) else { return nil }
        i += 4
        var out: [Data] = []
        for _ in 0..<(Int(r[6]) << 8 | Int(r[7])) {
            guard skipName(&i), i + 10 <= r.count else { break }
            let type = Int(r[i]) << 8 | Int(r[i + 1]), len = Int(r[i + 8]) << 8 | Int(r[i + 9])
            i += 10
            guard i + len <= r.count else { break }
            if type == 1 && len == 4 {
                var sa = sockaddr_in(); sa.sin_family = sa_family_t(AF_INET); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                memcpy(&sa.sin_addr, Array(r[i..<i + 4]), 4)
                out.append(Data(bytes: &sa, count: MemoryLayout<sockaddr_in>.size))
            }
            i += len
        }
        return out
    }
}

// MARK: the race and the checks

// The test copy's fault switch (request 55): the names in the file CK_AGG_FAULT are lines that have "died": "dead" fails at
// once (a cable pulled), "silent" waits out the timeout first (4G gone quiet, the usual death). Never set for the real server.
func fault(_ u: Uplink) -> String? {
    guard let f = aggEnv["CK_AGG_FAULT"], let t = try? String(contentsOfFile: f, encoding: .utf8) else { return nil }
    for line in t.components(separatedBy: "\n") {
        let p = line.split(separator: "=", maxSplits: 1).map(String.init)
        if p.count == 2, p[0] == u.name { return p[1].trimmingCharacters(in: .whitespaces) }
    }
    return nil
}
func faulted(_ u: Uplink, timeout: Int) -> Bool {
    guard let f = fault(u) else { return false }
    if f == "silent" { sleep(UInt32(timeout)) }
    return true
}

final class Race {
    let lock = NSLock(), done = DispatchSemaphore(value: 0)
    var winner: (Int32, Uplink)?, finished = 0
}

extension Server {
    // Out through the best line; when it has not answered within a second the next one starts too, and the first to
    // connect wins. A line that fails is checked at once.
    func race(_ host: String, _ port: UInt16, for c: Int32) -> (Int32, Uplink)? {
        for _ in 0..<100 { lock.lock(); let none = lines.isEmpty; lock.unlock(); if !none { break }; usleep(200_000) }
        lock.lock()
        let now = Date()
        let order = lines.sorted { load($0, now) < load($1, now) }   // v47: live rate and capacity (Balance.swift)
        lock.unlock()
        let r = Race()
        var started = 0
        func start(_ u: Uplink) {
            lock.lock(); u.active += 1; u.pending += 1; lock.unlock()
            started += 1
            Thread.detachNewThread { [self] in
                let fd = faulted(u, timeout: 5) ? nil : u.phone.map { Phones.dial(host, port, via: $0.port, timeout: 8) } ?? dial(host, port, via: u.iface)
                r.lock.lock()
                let won = fd != nil && r.winner == nil
                if won { r.winner = (fd!, u) }
                r.finished += 1
                r.lock.unlock()
                lock.lock()
                u.pending -= 1
                if won { u.connections += 1; u.seen[c] = Date(); u.lastGood = Date() } else { u.active -= 1 }
                lock.unlock()
                if let fd, !won { close(fd) }
                if fd == nil { checkSoon(u) }
                r.done.signal()
            }
        }
        guard let first = order.first else { return nil }
        start(first)
        var next = 1
        while true {
            _ = r.done.wait(timeout: .now() + 1)        // one attempt finished, or a second went by
            r.lock.lock(); let won = r.winner != nil; let finished = r.finished; r.lock.unlock()
            if won { break }
            if next < order.count { start(order[next]); next += 1; continue }   // a failure or a slow line: the next one
            if finished >= started { break }            // every line tried, none answered
        }
        r.lock.lock(); defer { r.lock.unlock() }
        return r.winner
    }

    // Every 3 s every line at once; dead after two misses in a row, or at once when its device lost its address.
    func checkLines() {
        lock.lock(); let ls = lines; lock.unlock()
        for u in ls { checkSoon(u) }
    }

    func checkSoon(_ u: Uplink) {
        lock.lock()
        if u.probing { lock.unlock(); return }
        let fresh = Date().timeIntervalSince(u.lastGood) < 3 && u.alive
        u.probing = !fresh
        lock.unlock()
        if fresh { return }
        Thread.detachNewThread { [self] in
            let gone = u.phone == nil && ipv4(of: u.iface) == nil
            var ok = false
            if !gone && !faulted(u, timeout: 2) {
                for host in ["1.1.1.1", "8.8.8.8"] {
                    if let fd = u.phone.map({ Phones.dial(host, 443, via: $0.port, timeout: 3) }) ?? dial(host, 443, via: u.iface, timeout: 2) {
                        close(fd); ok = true; break
                    }
                }
            }
            lock.lock()
            u.probing = false
            u.misses = ok ? 0 : gone ? 2 : u.misses + 1
            if ok { u.lastGood = Date() }
            let alive = ok || u.misses < 2
            if alive != u.alive { log("\(u.name) \(alive ? "is back" : gone ? "lost its address: new connections go to the others" : "does not answer: new connections go to the others")") }
            u.alive = alive
            lock.unlock()
        }
    }
}

extension Server {
    // A DNS query that came as UDP, asked over TCP (to 1.1.1.1:53) through a live line, the answer sent back to the
    // client as if it came from the server it asked (v31: in WIRES the phone carries TCP only, and the cable may be gone).
    func dnsOverTCP(_ query: [UInt8], origin: in_addr, to client: sockaddr_in, via local: Int32) {
        lock.lock(); let ls = lines.filter(\.alive); lock.unlock()
        for u in ls {
            guard let fd = u.phone.map({ Phones.dial("1.1.1.1", 53, via: $0.port, timeout: 3) }) ?? dial("1.1.1.1", 53, via: u.iface, timeout: 2) else { continue }
            var tv = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            defer { close(fd) }
            guard sendAll(fd, [UInt8(query.count >> 8), UInt8(query.count & 255)] + query), let lp = readExact(fd, 2),
                  let answer = readExact(fd, Int(lp[0]) << 8 | Int(lp[1])) else { continue }
            var packet: [UInt8] = [0, 0, 0, 1]
            withUnsafeBytes(of: origin) { packet += $0 }
            packet += [0, 53] + answer
            var dest = client
            _ = packet.withUnsafeBytes { b in withUnsafePointer(to: &dest) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(local, b.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
            return
        }
    }
}
