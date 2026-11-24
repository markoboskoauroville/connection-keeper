// DROPS INSIDE THE TEST COPY (request 55, widened by request 108). The real lines, routes and radios are never touched:
// a copy under test (CK_AGG_TEST) reads the file CK_AGG_FAULT, one line per line name, and plays the fault on its OWN
// connections only. `ck-test drop | delay | loss | cap | flow | stall | kill | restore` (Tools/ck-test) writes it.
//
//   AX88179B=dead                the cable pulled: dials fail at once, its open connections are cut, the health check fails
//   AX88179B=silent              4G gone quiet: dials wait out their timeout, open connections stop moving, the check fails
//   Something=delay:300          300 ms more on every connect and on every piece in both directions (a delay line)
//   Something=loss:5             5 % of the pieces wait 200 ms first (a lost packet's retransmission, as TCP sees it)
//   Something=rate:20            the whole line at most 20 Mbit/s each way (one bucket for all its connections)
//   Something=flow:15            each connection at most 15 Mbit/s (one TCP connection limited by a 4G round trip)
//   Something=stall:2@1764000000 from that second, 2 s with nothing moving and no dial answering (a hotspot stalls)
//   AX88179B=kill@1764000000     the connections open at that second are cut once (the cable dies mid-download)
// Several at once with commas: `Something=rate:40,delay:80`. A line not in the file is healthy. Never read by the real
// server: without CK_AGG_TEST the file is ignored even when CK_AGG_FAULT is set.
import Foundation
import Darwin

struct LineFault: Equatable {
    var dead = false, silent = false
    var delayMs = 0.0, lossPct = 0.0, rateMbps = 0.0, flowMbps = 0.0
    var stallFrom: Double?, stallFor = 0.0, killAt: Double?

    static func parse(_ spec: String) -> LineFault {
        var f = LineFault()
        for part in spec.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let at = part.split(separator: "@", maxSplits: 1).map(String.init)
            let kv = at[0].split(separator: ":", maxSplits: 1).map(String.init)
            let v = kv.count > 1 ? Double(kv[1]) ?? 0 : 0, when = at.count > 1 ? Double(at[1]) : nil
            switch kv[0] {
            case "dead": f.dead = true
            case "silent": f.silent = true
            case "delay": f.delayMs = max(0, v)
            case "loss": f.lossPct = min(max(0, v), 100)
            case "rate": f.rateMbps = max(0, v)
            case "flow": f.flowMbps = max(0, v)
            case "stall": f.stallFor = max(0, v); f.stallFrom = when ?? Date().timeIntervalSince1970
            case "kill": f.killAt = when ?? Date().timeIntervalSince1970
            default: break
            }
        }
        return f
    }
    func stalled(_ now: Double) -> Bool { if let s = stallFrom { return now >= s && now < s + stallFor }; return false }
}

enum Faults {
    static let path: String? = aggTestCopy ? aggEnv["CK_AGG_FAULT"] : nil
    static var enabled: Bool { path != nil }
    private static let lock = NSLock()
    private static var cache: [String: LineFault] = [:], readAt = 0.0, said: [String: LineFault] = [:]

    static func parseFile(_ text: String) -> [String: LineFault] {
        var all: [String: LineFault] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces), spec = String(line[line.index(after: eq)...])
            if !name.isEmpty && !name.hasPrefix("#") { all[name] = LineFault.parse(spec) }
        }
        return all
    }

    // the faults now, the file read again at most every 0.2 s
    static func of(_ name: String) -> LineFault? {
        guard let path else { return nil }
        let now = Date().timeIntervalSince1970
        lock.lock(); defer { lock.unlock() }
        if now - readAt > 0.2 {
            readAt = now
            cache = parseFile((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            for (n, f) in cache where said[n] != f { said[n] = f; log("FAULT \(n): \(describe(f))") }
            for n in said.keys where cache[n] == nil { said[n] = nil; log("FAULT \(n): restored") }
        }
        return cache[name]
    }

    static func describe(_ f: LineFault) -> String {
        var w: [String] = []
        if f.dead { w.append("dead") }; if f.silent { w.append("silent") }
        if f.delayMs > 0 { w.append("delay \(Int(f.delayMs)) ms") }; if f.lossPct > 0 { w.append("loss \(f.lossPct) %") }
        if f.rateMbps > 0 { w.append("line at most \(f.rateMbps) Mbit/s") }; if f.flowMbps > 0 { w.append("each connection at most \(f.flowMbps) Mbit/s") }
        if f.stallFrom != nil { w.append("stall \(f.stallFor) s") }; if f.killAt != nil { w.append("connections cut") }
        return w.isEmpty ? "healthy" : w.joined(separator: ", ")
    }

    // MARK: the line buckets (one per line and direction)
    final class Bucket {
        let lock = NSLock(); var tokens = 0.0, last = Date().timeIntervalSince1970
        // wait until n bytes may pass at `mbps`; a 50 ms burst is allowed
        func take(_ n: Int, mbps: Double) {
            let rate = mbps * 1e6 / 8
            lock.lock()
            let now = Date().timeIntervalSince1970
            tokens = min(tokens + (now - last) * rate, rate * 0.05); last = now
            tokens -= Double(n)
            let wait = tokens < 0 ? -tokens / rate : 0
            lock.unlock()
            if wait > 0 { usleep(useconds_t(min(wait, 5) * 1e6)) }
        }
    }
    private static var buckets: [String: Bucket] = [:]
    static func bucket(_ key: String) -> Bucket {
        lock.lock(); defer { lock.unlock() }
        if let b = buckets[key] { return b }
        let b = Bucket(); buckets[key] = b; return b
    }

    // MARK: the open connections, so a dead line or a kill cuts them even when they are idle
    private final class Open { let line: String, a: Int32, b: Int32, since: Double; var cut = false
        init(_ line: String, _ a: Int32, _ b: Int32, _ since: Double) { self.line = line; self.a = a; self.b = b; self.since = since } }
    private static var open: [Int32: Open] = [:], watching = false

    static func register(_ line: String, _ c: Int32, _ out: Int32, since: Double) {
        guard enabled else { return }
        lock.lock(); open[c] = Open(line, c, out, since); let start = !watching; watching = true; lock.unlock()
        if start {
            Thread.detachNewThread {
                while true {
                    usleep(200_000)
                    Faults.lock.lock(); let all = Array(Faults.open.values); Faults.lock.unlock()
                    let now = Date().timeIntervalSince1970
                    for o in all where !o.cut {
                        guard let f = Faults.of(o.line) else { continue }
                        let kill = f.killAt.map { o.since < $0 && now >= $0 } ?? false
                        if f.dead || kill {
                            Faults.lock.lock()
                            if Faults.open[o.a] === o { o.cut = true; shutdown(o.a, SHUT_RDWR); shutdown(o.b, SHUT_RDWR) }   // under the lock: never a closed fd
                            Faults.lock.unlock()
                            log("FAULT \(o.line): a connection cut (\(f.dead ? "dead" : "kill"))")
                        }
                    }
                }
            }
        }
    }
    static func unregister(_ c: Int32) { guard enabled else { return }; lock.lock(); open[c] = nil; lock.unlock() }
}

// the dial's part: true = this attempt fails (dead at once; silent after `timeout`); a stall holds the dial until it is
// over (as a SYN is answered once a stalled hotspot moves again) and fails only when it outlasts `timeout`; a delay waits
func fault(_ u: Uplink) -> String? {
    guard let f = Faults.of(u.name) else { return nil }
    if f.dead { return "dead" }
    if f.silent { return "silent" }
    if f.stalled(Date().timeIntervalSince1970) { return "stalled" }
    return nil
}
func faulted(_ u: Uplink, timeout: Int) -> Bool {
    guard let f = Faults.of(u.name) else { return false }
    if f.delayMs > 0 { usleep(useconds_t(min(f.delayMs, 10_000) * 1000)) }
    guard let kind = fault(u) else { return false }
    if kind == "silent" { sleep(UInt32(timeout)); return true }
    if kind == "stalled" {
        let end = Date().addingTimeInterval(Double(timeout))
        while Date() < end, fault(u) == "stalled" { usleep(50_000) }
        return fault(u) != nil
    }
    return true
}

// The data's part, one per direction of a connection (relay's pump): forward() sends a piece through the faults.
final class FaultShaper {
    let line: String, down: Bool, since: Double
    let mine = Faults.Bucket()
    private let qlock = NSCondition()
    private var queue: [(due: Double, data: [UInt8])] = [], queued = 0, sender: Thread?, failed = false, closing = false, ended = false
    init(line: String, down: Bool, since: Double) { self.line = line; self.down = down; self.since = since }

    // false: the connection is cut (dead, killed) or the far side has gone
    func forward(_ to: Int32, _ data: [UInt8]) -> Bool {
        var f = Faults.of(line) ?? LineFault()
        while f.silent || f.stalled(Date().timeIntervalSince1970) {      // nothing moves; the sender waits as on a quiet line
            usleep(50_000); f = Faults.of(line) ?? LineFault()
        }
        if f.dead { return false }
        if let k = f.killAt, since < k, Date().timeIntervalSince1970 >= k { return false }
        if f.lossPct > 0, Double.random(in: 0..<100) < f.lossPct { usleep(200_000) }
        if f.rateMbps > 0 { Faults.bucket(line + (down ? "/down" : "/up")).take(data.count, mbps: f.rateMbps) }
        if f.flowMbps > 0 { mine.take(data.count, mbps: f.flowMbps) }
        if f.delayMs <= 0 && sender == nil { return sendAll(to, data) }
        // a delay line: the piece leaves `delay` after it came in; the pump goes on reading (at most 8 MB held)
        qlock.lock()
        if failed { qlock.unlock(); return false }
        while queued > 8 << 20 && !failed { qlock.wait() }
        queue.append((Date().timeIntervalSince1970 + f.delayMs / 1000, data)); queued += data.count
        if sender == nil {
            let t = Thread { [self] in
                while true {
                    qlock.lock()
                    while queue.isEmpty && !closing { qlock.wait() }
                    if queue.isEmpty && closing { ended = true; qlock.broadcast(); qlock.unlock(); return }
                    let (due, d) = queue.removeFirst(); queued -= d.count; qlock.broadcast(); qlock.unlock()
                    let wait = due - Date().timeIntervalSince1970
                    if wait > 0 { usleep(useconds_t(min(wait, 10) * 1e6)) }
                    if !sendAll(to, d) { qlock.lock(); failed = true; ended = true; queue.removeAll(); queued = 0; qlock.broadcast(); qlock.unlock(); return }
                }
            }
            sender = t; t.start()
        }
        qlock.signal(); qlock.unlock()
        return true
    }

    // the pump has read its last piece: what the delay line holds is sent before the direction is closed
    func drain() {
        guard sender != nil else { return }
        qlock.lock(); closing = true; qlock.broadcast()
        while !ended { qlock.wait() }                      // the sender has sent the last piece (or the far side went)
        qlock.unlock()
    }
}

// `ck-aggregate fault-selftest` (request 108, CI and safe on the Mac: no network, no program started): the fault file's
// words, the line bucket's pace, and the test copy's refusals (TestCopy.refusal is only asked, nothing is run).
func faultSelftest(_ args: [String]) -> Never {
    var fails = 0
    func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }
    let all = Faults.parseFile("AX88179B=dead\nNothing A142 (USB)=rate:20,delay:80\n# a note=dead\nSomething=stall:2@1000,kill@1001,loss:5,flow:15\nbroken line\n")
    check(all.count == 3, "three lines read, the note and the broken line skipped (\(all.count))")
    check(all["AX88179B"]?.dead == true, "dead")
    check(all["Nothing A142 (USB)"]?.rateMbps == 20 && all["Nothing A142 (USB)"]?.delayMs == 80, "a name with spaces and brackets, two faults")
    let s = all["Something"] ?? LineFault()
    check(s.stalled(1000.5) && !s.stalled(1002.5) && s.killAt == 1001 && s.lossPct == 5 && s.flowMbps == 15, "stall window, kill time, loss, flow")
    let b = Faults.Bucket(), t0 = Date()
    for _ in 0..<40 { b.take(65536, mbps: 20) }                       // 2.6 MB at 20 Mbit/s: about 1.05 s
    let took = Date().timeIntervalSince(t0)
    check(took > 0.85 && took < 1.6, String(format: "the line bucket paces 2.6 MB at 20 Mbit/s in %.2f s (about 1.05)", took))
    // the refusals: asked only, never run (they answer the same with or without CK_AGG_TEST here: the table is printed)
    let table: [(String, [String], Bool)] = [
        ("/usr/sbin/networksetup", ["-setairportpower", "en0", "off"], false), ("/usr/sbin/networksetup", ["-listallhardwareports"], true),
        ("/usr/sbin/networksetup", ["-ordernetworkservices", "Wi-Fi"], false), ("/usr/sbin/networksetup", ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "8857"], false),
        ("/sbin/route", ["-n", "get", "default"], true), ("/sbin/route", ["-n", "delete", "-net", "0.0.0.0/1"], false),
        ("/sbin/ifconfig", ["-l"], true), ("/sbin/ifconfig", ["en0", "down"], false), ("/usr/sbin/ipconfig", ["getoption", "en0", "router"], true),
        ("/usr/sbin/ipconfig", ["set", "en0", "DHCP"], false), ("/bin/launchctl", ["kickstart", "gui/501/x"], false), ("/bin/launchctl", ["print", "gui/501/x"], true),
        ("adb", ["devices", "-l"], true), ("adb", ["-s", "X", "shell", "getprop", "ro.product.manufacturer"], true),
        ("adb", ["-s", "X", "shell", "svc", "wifi", "disable"], false), ("adb", ["-s", "X", "shell", "cmd", "wifi", "set-wifi-enabled", "disabled"], false),
        ("adb", ["-s", "X", "shell", "cmd", "wifi", "status"], true), ("adb", ["-s", "X", "shell", "cmd", "phone", "set-allowed-network-types-for-users", "-s", "0", "1"], false),
        ("adb", ["-s", "X", "shell", "cmd", "phone", "get-allowed-network-types-for-users", "-s", "0"], true),
        ("adb", ["-s", "X", "push", "ck-phone", "/data/local/tmp/ck-phone"], false), ("adb", ["-s", "X", "forward", "tcp:8860", "tcp:8858"], false),
        ("adb", ["-s", "X", "shell", "pkill -f /data/local/tmp/ck-phone"], false), ("adb", ["reconnect", "offline"], false),
        ("adb", ["-s", "X", "shell", "echo A=$(settings get global airplane_mode_on); dumpsys connectivity 2>/dev/null | grep -E 'Active default network'"], true),
        ("adb", ["-s", "X", "shell", "settings put global mobile_data 0"], false), ("/usr/bin/curl", ["-s", "https://api.ipify.org"], true),
        ("/usr/bin/osascript", ["-e", "quit app \"x\""], false), ("/usr/bin/pkill", ["-f", "ck-aggregate"], false),
    ]
    if ckTestCopy {
        for (path, a, allowed) in table {
            let r = TestCopy.refusal(path, a)
            check((r == nil) == allowed, "\(allowed ? "runs   " : "REFUSED") \((path as NSString).lastPathComponent) \(a.joined(separator: " ").prefix(70))")
        }
    } else {
        print("(the refusal table is checked only with CK_AGG_TEST set)")
    }
    print(fails == 0 ? "FAULT SELFTEST PASS" : "FAULT SELFTEST FAIL: \(fails)")
    exit(fails == 0 ? 0 : 1)
}
