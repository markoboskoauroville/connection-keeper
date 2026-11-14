// BONDING THROUGH THE CLOUD SERVER (v65, request 84, Marko 14.11.2026: "start to work on this improvement: 5, through
// bonding to Oracle Cloud Server"). ckbond v1, the Mac's half; the far half is Sources/Bond/server (Go), the protocol is
// docs/ckbond.md.
//
// Without it one TCP connection rides one line: a single upload, a single download or a one-connection speed test never
// goes faster than that line, and dies with it. With bond.json "on", every new SOCKS/HTTP connection becomes a stream:
// cut into frames, sent over ALL lines at once (one TCP leg per line to the relay on chromium-vm), put back in order
// there, and sent on to the destination as one normal connection; the replies come back the same way. A leg that dies
// takes nothing with it: what it carried unconfirmed goes out again on the others. No leg up: today's race() path.
//
//   bond.json  ~/Library/Application Support/connection-keeper/bond.json (0600), written by `ck-aggregate bond-init`:
//              {"on":false,"server":"130.61.181.83","port":443,"token":"<64 hex>","legsPerLine":1}; read every 5 s.
// Log lines start with "BOND". The token is never logged or shown in /status.
import Foundation
import Darwin
import CryptoKit

enum BondProto {
    static let open: UInt8 = 1, openOK: UInt8 = 2, openFail: UInt8 = 3, data: UInt8 = 4, fin: UInt8 = 5
    static let rst: UInt8 = 6, ack: UInt8 = 7, ping: UInt8 = 8, pong: UInt8 = 9, welcome: UInt8 = 10
    static let header = 11, maxPayload = 16384, tag = 16
    static let minRecord = 11 + 16, maxRecord = 11 + 16384 + 16
    static let window = 4 << 20, streamAckEvery = 256 << 10, legAckEvery: UInt64 = 32 << 10, minCap = 65536.0
    static let maxStreams = 1024
    static func sequenced(_ t: UInt8) -> Bool { t >= 1 && t <= 5 }
}

func bnow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func be32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * UInt32($0))) } }
func be64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (56 - 8 * UInt64($0))) } }
func rd32(_ b: [UInt8], _ i: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(b[i + $1]) } }
func rd64(_ b: [UInt8], _ i: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(b[i + $1]) } }
func bondHex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
func bondUnhex(_ s: String) -> [UInt8]? {
    let c = Array(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    guard c.count % 2 == 0 else { return nil }
    func v(_ x: UInt8) -> UInt8? {
        switch x { case 48...57: return x - 48; case 97...102: return x - 87; case 65...70: return x - 55; default: return nil }
    }
    var out: [UInt8] = []
    var i = 0
    while i < c.count { guard let h = v(c[i]), let l = v(c[i + 1]) else { return nil }; out.append(h << 4 | l); i += 2 }
    return out
}

struct BFrame {
    var type: UInt8, stream: UInt32, seq: UInt32, payload: [UInt8]
    init(_ type: UInt8, _ stream: UInt32 = 0, _ seq: UInt32 = 0, _ payload: [UInt8] = []) {
        self.type = type; self.stream = stream; self.seq = seq; self.payload = payload
    }
    var size: Int { BondProto.header + payload.count }
    func encode() -> [UInt8] {
        var b = [UInt8](); b.reserveCapacity(size)
        b.append(type); b += be32(stream); b += be32(seq)
        b.append(UInt8(payload.count >> 8)); b.append(UInt8(payload.count & 255))
        b += payload
        return b
    }
    static func decode(_ b: [UInt8]) -> BFrame? {
        guard b.count >= BondProto.header else { return nil }
        let n = Int(b[9]) << 8 | Int(b[10])
        guard n <= BondProto.maxPayload, b.count == BondProto.header + n else { return nil }
        return BFrame(b[0], rd32(b, 1), rd32(b, 5), Array(b[BondProto.header...]))
    }
}

enum BondCrypto {
    static func random(_ n: Int) -> [UInt8] {
        var g = SystemRandomNumberGenerator()                // arc4random: the kernel's CSPRNG
        return (0..<n).map { _ in UInt8.random(in: 0...255, using: &g) }
    }
    static func mac(_ token: [UInt8], _ parts: [[UInt8]]) -> [UInt8] {
        var h = HMAC<SHA256>(key: SymmetricKey(data: token))
        for p in parts { h.update(data: p) }
        return h.finalize().withUnsafeBytes { Array($0) }
    }
    static func keys(_ token: [UInt8], _ snonce: [UInt8], _ cnonce: [UInt8]) -> (c2s: SymmetricKey, s2c: SymmetricKey) {
        let ikm = SymmetricKey(data: token), salt = snonce + cnonce
        return (HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Array("ckbond1 c2s".utf8), outputByteCount: 32),
                HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Array("ckbond1 s2c".utf8), outputByteCount: 32))
    }
}

// One direction of one leg: AES-256-GCM, the nonce 4 zero bytes and a 64-bit record counter.
final class BondCipher {
    let key: SymmetricKey
    var counter: UInt64 = 0
    init(_ key: SymmetricKey) { self.key = key }
    private func nonce() -> AES.GCM.Nonce? {
        let n: [UInt8] = [0, 0, 0, 0] + be64(counter)
        counter += 1
        return try? AES.GCM.Nonce(data: n)
    }
    func seal(_ p: [UInt8]) -> [UInt8]? {
        guard let n = nonce(), let box = try? AES.GCM.seal(p, using: key, nonce: n) else { return nil }
        return Array(box.ciphertext) + Array(box.tag)
    }
    func open(_ c: [UInt8]) -> [UInt8]? {
        guard c.count >= BondProto.tag, let n = nonce(),
              let box = try? AES.GCM.SealedBox(nonce: n, ciphertext: Data(c[0..<(c.count - BondProto.tag)]), tag: Data(c[(c.count - BondProto.tag)...])),
              let p = try? AES.GCM.open(box, using: key) else { return nil }
        return Array(p)
    }
}

// MARK: bond.json

struct BondConfig: Codable {
    var on: Bool
    var server: String
    var port: UInt16
    var token: String
    var legsPerLine: Int
}

enum BondConfigFile {
    static var url: URL { aggEnv["CK_BOND_CONFIG"].map { URL(fileURLWithPath: $0) } ?? Paths.support.appendingPathComponent("bond.json") }
    static func load() -> BondConfig? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BondConfig.self, from: d)
    }
    // `ck-aggregate bond-init`: a new random token, bond off, mode 0600 from the first byte. An existing file is kept.
    static func initFile() -> String {
        let path = url.path
        if FileManager.default.fileExists(atPath: path) { return "token already in \(path) (kept)" }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cfg = BondConfig(on: false, server: "130.61.181.83", port: 443, token: bondHex(BondCrypto.random(32)), legsPerLine: 1)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(cfg) else { return "could not write \(path)" }
        let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return "could not write \(path)" }
        defer { close(fd) }
        let wrote = d.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, d.count) }
        return wrote == d.count ? "token written to \(path)" : "could not write \(path)"
    }
}

// MARK: legs and streams

// A way to the relay through one line: its dial gives a connected TCP socket (bound to the line), or nil.
struct BondPath { let key: String; let line: String; let dial: () -> Int32? }

final class BSent {
    let seq: UInt32, enc: [UInt8]
    var leg: BLeg?, legEnd: UInt64 = 0
    init(_ seq: UInt32, _ enc: [UInt8]) { self.seq = seq; self.enc = enc }
}

final class BLeg {
    let key: String, line: String, fd: Int32, tx: BondCipher, rx: BondCipher
    var ctlq: [[UInt8]] = [], dataq: [[UInt8]] = []
    var sent: UInt64 = 0, acked: UInt64 = 0, recv: UInt64 = 0, recvAcked: UInt64 = 0     // sequenced bytes only
    var rttMin = 0.05, rttMinAt = 0.0, gotPong = false, rate = 1_250_000.0, capped = false
    var sampleAt = bnow(), sampleAcked: UInt64 = 0
    var lastHeard = bnow(), lastPing = 0.0, pingID: UInt32 = 0, dead = false
    init(key: String, line: String, fd: Int32, tx: BondCipher, rx: BondCipher) {
        self.key = key; self.line = line; self.fd = fd; self.tx = tx; self.rx = rx
    }
}

final class BStream {
    let id: UInt32
    var fd: Int32 = -1
    var nextSeq: UInt32 = 0, peerAck: UInt32 = 0, unacked: [UInt32: BSent] = [:], unackedBytes = 0
    var expect: UInt32 = 0, ooo: [UInt32: BFrame] = [:], inbox: [BFrame] = []
    var delivered: UInt32 = 0, ackSent: UInt32 = 0, ackBytes = 0, ackForce = false
    var opened = 0                                       // 0 waiting, 1 OPEN_OK, 2 OPEN_FAIL
    var finSent = false, finRecv = false, done = false, delivering = true
    var up = 0, down = 0
    init(_ id: UInt32) { self.id = id }
}

// MARK: the client

final class BondClient {
    let cv = NSCondition()                               // guards everything below; every wait is on it
    let host: String, port: UInt16, token: [UInt8]
    let paths: () -> [BondPath]
    var clientID = BondCrypto.random(16)
    var legs: [BLeg] = [], streams: [UInt32: BStream] = [:], nextID: UInt32 = 1
    var running = true, dialing: Set<String> = [], retryAt: [String: Double] = [:], fails: [String: Int] = [:]
    var noLegsSince: Double?
    var bytesUp = 0, bytesDown = 0, opened = 0

    init(host: String, port: UInt16, token: [UInt8], paths: @escaping () -> [BondPath]) {
        self.host = host; self.port = port; self.token = token; self.paths = paths
    }

    func start() {
        Thread.detachNewThread { [self] in while isRunning { manage(); sleep(1) } }
        Thread.detachNewThread { [self] in while isRunning { usleep(50_000); tick() } }
    }
    var isRunning: Bool { cv.lock(); defer { cv.unlock() }; return running }
    func stop() {
        cv.lock()
        running = false
        for l in legs { kill(l, "bond off") }
        for s in streams.values { finish(s, rst: false) }
        cv.broadcast(); cv.unlock()
    }
    var ready: Bool { cv.lock(); defer { cv.unlock() }; return running && legs.contains { !$0.dead } }
    var legCount: Int { cv.lock(); defer { cv.unlock() }; return legs.count }
    func legBytes() -> [String: UInt64] { cv.lock(); defer { cv.unlock() }; return Dictionary(legs.map { ($0.key, $0.recv) }, uniquingKeysWith: { a, _ in a }) }

    // Every second: a leg for every path that has none, the legs of a line that is gone closed.
    func manage() {
        let want = paths()
        cv.lock()
        let keys = Set(want.map(\.key))
        for l in legs where !keys.contains(l.key) { kill(l, "its line is gone") }
        let now = bnow()
        var go: [BondPath] = []
        for p in want where !legs.contains(where: { $0.key == p.key }) && !dialing.contains(p.key) && (retryAt[p.key] ?? 0) <= now {
            dialing.insert(p.key); go.append(p)
        }
        cv.unlock()
        for p in go { Thread.detachNewThread { [self] in connect(p) } }
    }

    func connect(_ p: BondPath) {
        let leg = handshake(p)
        cv.lock()
        dialing.remove(p.key)
        guard let leg, running else {
            let n = (fails[p.key] ?? 0) + 1
            fails[p.key] = n
            retryAt[p.key] = bnow() + min(30, 1.5 * Double(1 << min(n, 5)))     // 3, 6, 12, 24, 30 s
            cv.unlock()
            if let leg { shutdown(leg.fd, SHUT_RDWR); close(leg.fd) }
            if n == 1 || n % 20 == 0 { log("BOND leg \(p.key) (\(p.line)): no answer from \(host):\(port) (\(n) tries)") }
            return
        }
        legs.append(leg); fails[p.key] = nil; retryAt[p.key] = nil
        let count = legs.count
        cv.broadcast(); cv.unlock()
        log("BOND leg \(p.key) (\(p.line)) up, \(count) leg\(count == 1 ? "" : "s")")
        let g = DispatchGroup()
        g.enter(); Thread.detachNewThread { [self] in writer(leg); g.leave() }
        g.enter(); Thread.detachNewThread { [self] in reader(leg); g.leave() }
        Thread.detachNewThread { g.wait(); close(leg.fd) }
    }

    // The handshake: the server's nonce; ours, the client id and the HMAC; the server's first record (WELCOME).
    func handshake(_ p: BondPath) -> BLeg? {
        guard let fd = p.dial() else { return nil }
        deadline(fd, 8)
        guard let sn = readExact(fd, 32) else { close(fd); return nil }
        let cn = BondCrypto.random(32)
        cv.lock(); let cid = clientID; cv.unlock()
        let mac = BondCrypto.mac(token, [Array("ckbond1".utf8), sn, cn, cid])
        guard sendAll(fd, cn + cid + mac) else { close(fd); return nil }
        let k = BondCrypto.keys(token, sn, cn)
        let rx = BondCipher(k.s2c)
        guard let lh = readExact(fd, 2) else { close(fd); return nil }
        let n = Int(lh[0]) << 8 | Int(lh[1])
        guard n >= BondProto.minRecord, n <= BondProto.maxRecord, let body = readExact(fd, n), let plain = rx.open(body),
              let f = BFrame.decode(plain), f.type == BondProto.welcome else { close(fd); return nil }
        deadline(fd, 0)
        return BLeg(key: p.key, line: p.line, fd: fd, tx: BondCipher(k.c2s), rx: rx)
    }

    func writer(_ l: BLeg) {
        while true {
            cv.lock()
            while !l.dead && l.ctlq.isEmpty && l.dataq.isEmpty { cv.wait() }
            if l.dead { cv.unlock(); return }
            let batch = l.ctlq + l.dataq
            l.ctlq = []; l.dataq = []
            cv.unlock()
            var out = [UInt8]()
            out.reserveCapacity(batch.reduce(0) { $0 + $1.count + 18 })
            var sealed = true
            for p in batch {
                guard let c = l.tx.seal(p) else { sealed = false; break }
                out.append(UInt8(c.count >> 8)); out.append(UInt8(c.count & 255)); out += c
            }
            if !sealed || !sendAll(l.fd, out) { cv.lock(); kill(l, sealed ? "write failed" : "seal failed"); cv.unlock(); return }
        }
    }

    func reader(_ l: BLeg) {
        var why = "closed by the server"
        while true {
            guard let lh = readExact(l.fd, 2) else { break }
            let n = Int(lh[0]) << 8 | Int(lh[1])
            guard n >= BondProto.minRecord, n <= BondProto.maxRecord else { why = "bad record length"; break }
            guard let body = readExact(l.fd, n) else { break }
            guard let p = l.rx.open(body), let f = BFrame.decode(p) else { why = "a record did not decrypt"; break }
            cv.lock(); onFrame(l, f); cv.unlock()
        }
        cv.lock(); kill(l, why); cv.unlock()
    }

    // (under cv) The leg is closed; every frame it carried that the server has not confirmed goes out on the others.
    func kill(_ l: BLeg, _ why: String) {
        guard !l.dead else { return }
        l.dead = true
        shutdown(l.fd, SHUT_RDWR)
        legs.removeAll { $0 === l }
        retryAt[l.key] = bnow() + 1
        var redo: [(BStream, BSent)] = []
        for s in streams.values where !s.done {
            for st in s.unacked.values where st.leg === l && st.legEnd > l.acked { redo.append((s, st)) }
        }
        redo.sort { $0.0.id != $1.0.id ? $0.0.id < $1.0.id : $0.1.seq < $1.1.seq }
        log("BOND leg \(l.key) (\(l.line)) down: \(why); \(redo.count) frames resent, \(legs.count) legs left")
        cv.broadcast()
        guard !redo.isEmpty else { return }
        Thread.detachNewThread { [self] in
            cv.lock()
            for (s, st) in redo where !s.done && st.leg === l && s.unacked[st.seq] === st {
                if !place(st, s) { break }
            }
            cv.unlock()
        }
    }

    // (under cv) The live leg where n bytes arrive first: RTT/2 + queued/rate, among those under their in-flight cap.
    func pick(_ n: Int) -> BLeg? {
        var best: BLeg?, bt = Double.infinity
        for l in legs where !l.dead {
            let infl = Double(l.sent - l.acked)
            let limit = max(BondProto.minCap, l.rate * (2 * l.rttMin + 0.05))
            if infl > 0 && infl + Double(n) > limit { l.capped = true; continue }
            let t = l.rttMin / 2 + (infl + Double(n)) / l.rate
            if t < bt { bt = t; best = l }
        }
        return best
    }

    func place(_ st: BSent, _ s: BStream) -> Bool {
        while running && !s.done {
            if let l = pick(st.enc.count) {
                l.dataq.append(st.enc); l.sent += UInt64(st.enc.count); st.leg = l; st.legEnd = l.sent
                cv.broadcast()
                return true
            }
            cv.wait()
        }
        return false
    }

    func ctl(_ l: BLeg?, _ f: BFrame) {
        guard let l, !l.dead else { return }
        l.ctlq.append(f.encode()); cv.broadcast()
    }
    func bestLeg() -> BLeg? { legs.filter { !$0.dead }.min { $0.rttMin < $1.rttMin } }
    func legAckSend(_ l: BLeg) { ctl(l, BFrame(BondProto.ack, 0, 0, be64(l.recv))); l.recvAcked = l.recv }
    func streamAckSend(_ s: BStream) {
        guard let l = bestLeg() else { return }
        ctl(l, BFrame(BondProto.ack, s.id, s.delivered)); s.ackSent = s.delivered; s.ackBytes = 0; s.ackForce = false
    }

    func legAck(_ l: BLeg, _ v: UInt64) {
        if v > l.acked && v <= l.sent { l.acked = v }
        let now = bnow(), dt = now - l.sampleAt
        if dt >= 0.1 {
            let sample = Double(l.acked - l.sampleAcked) / dt
            if l.capped { l.rate = max(16384, 0.5 * l.rate + 0.5 * sample) } else if sample > l.rate { l.rate = sample }
            l.capped = false; l.sampleAt = now; l.sampleAcked = l.acked
        }
        cv.broadcast()
    }

    func streamAck(_ s: BStream, _ v: UInt32) {
        guard v <= s.nextSeq else { return }
        while s.peerAck < v {
            if let st = s.unacked.removeValue(forKey: s.peerAck) { s.unackedBytes -= st.enc.count }
            s.peerAck += 1
        }
        checkDone(s); cv.broadcast()
    }

    func onFrame(_ l: BLeg, _ f: BFrame) {
        let now = bnow()
        l.lastHeard = now
        switch f.type {
        case BondProto.ping: ctl(l, BFrame(BondProto.pong, 0, f.seq, f.payload))
        case BondProto.pong:
            guard f.payload.count == 8 else { return }
            let rtt = max(now - Double(rd64(f.payload, 0)) / 1e9, 0.0005)
            // the lowest seen on this leg: a PING waits behind the leg's own queue, and a minimum that followed it up would
            // grow the in-flight cap, which grows the queue (the leg is made again when its line changes)
            if !l.gotPong || rtt < l.rttMin { l.rttMin = rtt; l.rttMinAt = now }
            l.gotPong = true
        case BondProto.ack:
            if f.stream == 0 { if f.payload.count == 8 { legAck(l, rd64(f.payload, 0)) } }
            else if let s = streams[f.stream] { streamAck(s, f.seq) }
        case BondProto.rst:
            if let s = streams[f.stream], !s.done { finish(s, rst: false) }
        case BondProto.welcome: break
        default:
            guard BondProto.sequenced(f.type) else { return }
            l.recv += UInt64(f.size)
            if l.recv - l.recvAcked >= BondProto.legAckEvery { legAckSend(l) }
            guard let s = streams[f.stream] else {
                if f.stream < nextID { ctl(l, BFrame(BondProto.ack, f.stream, f.seq &+ 1)) }   // a late copy of a finished stream
                return
            }
            if f.seq < s.expect || s.ooo[f.seq] != nil { s.ackForce = true; return }
            if f.seq == s.expect {
                s.inbox.append(f); s.expect += 1
                while let next = s.ooo.removeValue(forKey: s.expect) { s.inbox.append(next); s.expect += 1 }
                cv.broadcast()
            } else {
                s.ooo[f.seq] = f
            }
        }
    }

    func checkDone(_ s: BStream) {
        if !s.done && s.finSent && s.finRecv && s.peerAck == s.nextSeq && s.inbox.isEmpty { finish(s, rst: false) }
    }

    func finish(_ s: BStream, rst: Bool) {
        guard !s.done else { return }
        s.done = true
        if s.fd >= 0 { shutdown(s.fd, SHUT_RDWR) }
        if rst { for l in legs { ctl(l, BFrame(BondProto.rst, s.id)) } }
        cv.broadcast()
    }
    func reset(_ s: BStream) { cv.lock(); finish(s, rst: true); cv.unlock() }

    // (under cv, may wait for the window and a leg)
    func sendSeq(_ s: BStream, _ type: UInt8, _ payload: [UInt8]) -> Bool {
        let n = BondProto.header + payload.count
        while !s.done && running && s.unackedBytes > 0 && s.unackedBytes + n > BondProto.window { cv.wait() }
        guard !s.done, running else { return false }
        let f = BFrame(type, s.id, s.nextSeq, payload)
        s.nextSeq += 1
        let st = BSent(f.seq, f.encode())
        s.unacked[f.seq] = st; s.unackedBytes += n
        if type == BondProto.fin { s.finSent = true }
        if type == BondProto.data { s.up += payload.count; bytesUp += payload.count }
        return place(st, s)
    }

    func tick() {
        cv.lock(); defer { cv.unlock() }
        let now = bnow()
        for l in legs {
            if now - l.lastHeard > 3 { kill(l, "silent for 3 s"); continue }
            if now - l.lastPing >= 1 { l.lastPing = now; l.pingID &+= 1; ctl(l, BFrame(BondProto.ping, 0, l.pingID, be64(UInt64(now * 1e9)))) }
            if l.recv != l.recvAcked { legAckSend(l) }
        }
        for (id, s) in streams {
            if s.delivered != s.ackSent || s.ackForce { streamAckSend(s) }
            if s.done && !s.delivering { streams[id] = nil }
        }
        // No leg for 50 s (the server forgets a group after 60): the streams end and the next legs start a new group.
        if legs.isEmpty {
            if noLegsSince == nil { noLegsSince = now }
            if let t = noLegsSince, now - t > 50 {
                if !streams.isEmpty { log("BOND no leg for 50 s: \(streams.count) streams ended") }
                for s in streams.values { finish(s, rst: false) }
                clientID = BondCrypto.random(16); noLegsSince = now
            }
        } else { noLegsSince = nil }
        cv.broadcast()
    }

    // MARK: the use

    // A stream to host:port through the relay, after its OPEN_OK; nil when no leg is up, it failed, or 10 s went by.
    func open(_ host: String, _ port: UInt16, timeout: Double = 10) -> BStream? {
        cv.lock()
        guard running, legs.contains(where: { !$0.dead }), streams.count < BondProto.maxStreams else { cv.unlock(); return nil }
        let s = BStream(nextID); nextID += 1; streams[s.id] = s
        cv.unlock()
        Thread.detachNewThread { [self] in deliver(s) }
        let target = host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        cv.lock(); defer { cv.unlock() }
        guard sendSeq(s, BondProto.open, Array(target.utf8)) else { finish(s, rst: true); return nil }
        let end = bnow() + timeout
        while s.opened == 0 && !s.done && bnow() < end { _ = cv.wait(until: Date().addingTimeInterval(0.05)) }
        if s.opened == 1 && !s.done { opened += 1; return s }
        if s.opened == 0 { finish(s, rst: true) }
        return nil
    }

    // The stream's frames in order, to the client socket (bridged later: data waits for the socket).
    func deliver(_ s: BStream) {
        while true {
            cv.lock()
            while !s.done && (s.inbox.isEmpty || (s.fd < 0 && (s.inbox[0].type == BondProto.data || s.inbox[0].type == BondProto.fin))) { cv.wait() }
            if s.done { s.delivering = false; cv.broadcast(); cv.unlock(); return }
            let f = s.inbox.removeFirst(), fd = s.fd
            cv.unlock()
            var ok = true
            if f.type == BondProto.data { ok = sendAll(fd, f.payload) } else if f.type == BondProto.fin { shutdown(fd, SHUT_WR) }
            cv.lock()
            s.delivered += 1; s.ackBytes += f.size
            switch f.type {
            case BondProto.openOK: s.opened = 1
            case BondProto.openFail: s.opened = 2; finish(s, rst: false)
            case BondProto.data: s.down += f.payload.count; bytesDown += f.payload.count
            case BondProto.fin: s.finRecv = true
            default: ok = false
            }
            if !ok { finish(s, rst: true) } else {
                if s.ackBytes >= BondProto.streamAckEvery { streamAckSend(s) }
                checkDone(s)
            }
            cv.broadcast()
            cv.unlock()
        }
    }

    // A client socket and its stream joined until both ends are finished; `first`: bytes to send before the socket's.
    func bridge(_ fd: Int32, _ s: BStream, first: [UInt8] = []) {
        deadline(fd, 0)
        cv.lock(); s.fd = fd; let gone = s.done; cv.broadcast(); cv.unlock()
        var ok = !gone && (first.isEmpty || sendData(s, first))
        var buf = [UInt8](repeating: 0, count: BondProto.maxPayload)
        while ok {
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, BondProto.maxPayload, 0) }
            if n == 0 { cv.lock(); _ = sendSeq(s, BondProto.fin, []); checkDone(s); cv.unlock(); break }
            if n < 0 { reset(s); break }
            ok = sendData(s, Array(buf[0..<n]))
        }
        cv.lock()
        while !s.done && running { cv.wait() }
        finish(s, rst: true)                                 // nothing when it ended well (done already)
        while s.delivering { cv.wait() }                     // the socket is closed only when nobody writes to it
        cv.unlock()
        close(fd)
    }

    func sendData(_ s: BStream, _ b: [UInt8]) -> Bool {
        var i = 0
        while i < b.count {
            let j = min(i + BondProto.maxPayload, b.count)
            cv.lock(); let ok = sendSeq(s, BondProto.data, Array(b[i..<j])); cv.unlock()
            if !ok { return false }
            i = j
        }
        return true
    }

    func status() -> [String: Any] {
        cv.lock(); defer { cv.unlock() }
        let ls: [[String: Any]] = legs.map { l in
            ["line": l.line, "key": l.key, "alive": !l.dead, "rttMs": Double(Int(l.rttMin * 10_000)) / 10,
             "rateMbps": Double(Int(l.rate * 8 / 100_000)) / 10, "inflightKB": Int(l.sent - l.acked) / 1024,
             "mbSent": Double(Int(Double(l.sent) / 1e4)) / 100, "mbReceived": Double(Int(Double(l.recv) / 1e4)) / 100]
        }
        return ["on": running, "server": "\(host):\(port)", "legs": ls, "streams": streams.count, "opened": opened,
                "mbUp": Double(Int(Double(bytesUp) / 1e4)) / 100, "mbDown": Double(Int(Double(bytesDown) / 1e4)) / 100]
    }
}

// MARK: the hooks in the aggregation server

enum Bond {
    static let lock = NSLock()
    static var client: BondClient?

    // The bond for a new connection to host, or nil: bond off, no leg up, or a destination in the house.
    static func active(for host: String) -> BondClient? {
        lock.lock(); let c = client; lock.unlock()
        guard let c, !local(host), c.ready else { return nil }
        return c
    }

    static func status() -> [String: Any] {
        lock.lock(); let c = client; lock.unlock()
        return c?.status() ?? ["on": false]
    }

    // Loopback, private, link-local, carrier-grade NAT (Tailscale) and names without a dot stay on today's path.
    static func local(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".ts.net") || (!h.contains(".") && !h.contains(":")) { return true }
        if h.contains(":") { return h == "::1" || h.hasPrefix("fe80") || h.hasPrefix("fc") || h.hasPrefix("fd") }
        let p = h.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || p[0] == 127 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168)
            || (p[0] == 169 && p[1] == 254) || (p[0] == 100 && (64...127).contains(p[1])) || p[0] == 0
    }

    // bond.json read every 5 s: "on" starts the client, "off" (or no file) stops it; a changed server, port, token or
    // legsPerLine starts it again.
    static func watch(_ server: Server) {
        Thread.detachNewThread {
            var last: String?
            var warned = false
            while true {
                let cfg = BondConfigFile.load()
                let want = (cfg?.on ?? false) ? cfg : nil
                let token = want.flatMap { bondUnhex($0.token) }
                let sig = want.map { "\($0.server)|\($0.port)|\($0.legsPerLine)|\(SHA256.hash(data: Array($0.token.utf8)).description)" }
                if sig != last {
                    lock.lock(); let old = client; client = nil; lock.unlock()
                    old?.stop()
                    if let c = want, let token, token.count >= 16 {
                        let nc = BondClient(host: c.server, port: c.port, token: token, paths: server.bondPaths(c))
                        nc.start()
                        lock.lock(); client = nc; lock.unlock()
                        log("BOND on: relay \(c.server):\(c.port), \(max(1, min(c.legsPerLine, 2))) leg(s) per line")
                        warned = false
                    } else if want != nil {
                        if !warned { log("BOND bond.json: the token is not hex (at least 32 characters): bond stays off"); warned = true }
                    } else if last != nil {
                        log("BOND off: new connections take today's path")
                    }
                    last = sig
                }
                sleep(5)
            }
        }
    }
}

extension Server {
    // One path per live line (and per leg of it): cable and Wi-Fi bound to their device, phones through their SOCKS port.
    func bondPaths(_ c: BondConfig) -> () -> [BondPath] {
        let host = c.server, port = c.port, k = max(1, min(c.legsPerLine, 2))
        return { [weak self] in
            guard let self else { return [] }
            self.lock.lock(); let ls = self.lines.filter { $0.alive }; self.lock.unlock()
            return ls.flatMap { u in
                (0..<k).map { i in
                    BondPath(key: "\(u.iface)#\(i)", line: u.name, dial: {
                        if let p = u.phone { return Phones.dial(host, port, via: p.port, timeout: 5) }
                        return dial(host, port, via: u.iface, timeout: 5)
                    })
                }
            }
        }
    }
}
