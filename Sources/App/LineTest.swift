// TEST ON EVERY ROW (v89, request 99, Marko 23.11.2026: "Next to each connection, just put a test action button, and that
// one is using algorithms from something we already have built in. That's the web page with speed test, without bringing
// user interface. Use only that connection and give the results as a test.")
//
// The engine is speedtest.net in the app's own WebKit (as the speedometer's window, SpeedBrowser.swift, with the same
// uBlock rules), but in a window nobody sees: GO is pressed and the numbers are read by the same words speedtest-firefox
// reads (Resources/speedtest/reader.js: "DOWNLOAD Mbps", "UPLOAD Mbps", "Ping ms", the test over at /result/<id>).
//
// ONLY THAT CONNECTION. A web view follows the Mac's route, which is the aggregate tunnel. So the test's web view gets
// its own proxy (WKWebsiteDataStore.proxyConfigurations, macOS 14+), a SOCKS5 server that exists only for this test:
//   a cable or the Mac's Wi-Fi   LineProxy below, on 127.0.0.1:<free port>: every connection it opens is bound to that
//                                device and its address (IP_BOUND_IF + bind, as ck-aggregate's dial and curl --interface);
//   a phone on its cable         the phone's own ck-phone SOCKS5 through adb forward (127.0.0.1:886x): its SIM only;
//   ALL TICKED                   no proxy: the Mac's route, i.e. the ticked lines together (through the bond when it is on).
// LineProxy counts the bytes it carried, so the log says how much went over the line; the interface counters
// (netstat -ib) are the outside proof. One test at a time; a second click is refused on the status line.
import AppKit
import WebKit
import Network

// A SOCKS5 server (CONNECT only, IPv4) whose connections leave through one device.
final class LineProxy {
    let iface: String
    private(set) var port: UInt16 = 0
    private var listener: Int32 = -1
    private var stopped = false
    private let lock = NSLock()
    private(set) var bytesDown = 0, bytesUp = 0, connections = 0, refused = 0

    init?(iface: String) {
        self.iface = iface
        guard if_nametoindex(iface) != 0 else { return nil }
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_port = 0; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        let b = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard b == 0, listen(s, 128) == 0 else { close(s); return nil }
        var got = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &got) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
        port = UInt16(bigEndian: got.sin_port)
        listener = s
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(s, nil, nil)
                if c < 0 { if stopped { return }; usleep(20_000); continue }
                Thread.detachNewThread { [self] in serve(c) }
            }
        }
    }

    func stop() { lock.lock(); stopped = true; lock.unlock(); shutdown(listener, SHUT_RDWR); close(listener) }

    private static func exact(_ fd: Int32, _ n: Int) -> [UInt8]? {
        var b = [UInt8](repeating: 0, count: n), got = 0
        while got < n { let r = b.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, n - got, 0) }; if r <= 0 { return nil }; got += r }
        return b
    }
    private static func sendAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count { let r = bytes.withUnsafeBytes { send(fd, $0.baseAddress! + sent, bytes.count - sent, 0) }; if r <= 0 { return false }; sent += r }
        return true
    }

    // the device's own IPv4 address
    private func source() -> in_addr? {
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

    private func dial(_ addr: in_addr, _ port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var index = if_nametoindex(iface)
        guard setsockopt(fd, IPPROTO_IP, 25 /* IP_BOUND_IF */, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else { close(fd); return nil }
        if let src = source() {
            var sa = sockaddr_in(); sa.sin_family = sa_family_t(AF_INET); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); sa.sin_addr = src
            let b = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            if b != 0 { close(fd); return nil }
        } else { close(fd); return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 8, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var to = sockaddr_in(); to.sin_family = sa_family_t(AF_INET); to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        to.sin_port = port.bigEndian; to.sin_addr = addr
        let ok = withUnsafePointer(to: &to) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
        guard ok else { close(fd); return nil }
        var none = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private func resolve(_ host: String) -> in_addr? {
        var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let r = res else { return nil }
        defer { freeaddrinfo(res) }
        guard let sa = r.pointee.ai_addr else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
    }

    private func serve(_ c: Int32) {
        var one: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        func fail(_ code: UInt8) { _ = LineProxy.sendAll(c, [5, code, 0, 1, 0, 0, 0, 0, 0, 0]); close(c); lock.lock(); refused += 1; lock.unlock() }
        guard let hello = LineProxy.exact(c, 2), hello[0] == 5, LineProxy.exact(c, Int(hello[1])) != nil, LineProxy.sendAll(c, [5, 0]),
              let req = LineProxy.exact(c, 4), req[0] == 5 else { close(c); return }
        guard req[1] == 1 else { fail(7); return }                       // CONNECT only
        var addr: in_addr?
        switch req[3] {
        case 1:
            if let b = LineProxy.exact(c, 4) {
                var v: UInt32 = UInt32(b[3]); v = v << 8 | UInt32(b[2]); v = v << 8 | UInt32(b[1]); v = v << 8 | UInt32(b[0])
                var a = in_addr(); a.s_addr = v; addr = a
            }
        case 3: if let n = LineProxy.exact(c, 1), let name = LineProxy.exact(c, Int(n[0])) { addr = resolve(String(decoding: name, as: UTF8.self)) }
        case 4: _ = LineProxy.exact(c, 16); fail(8); return               // IPv6: not on a pinned line
        default: fail(8); return
        }
        guard let pb = LineProxy.exact(c, 2) else { close(c); return }
        let port = UInt16(pb[0]) << 8 | UInt16(pb[1])
        guard let a = addr, let out = dial(a, port) else { fail(4); return }
        guard LineProxy.sendAll(c, [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]) else { close(c); close(out); return }
        var none = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
        lock.lock(); connections += 1; lock.unlock()
        let group = DispatchGroup()
        func pump(_ from: Int32, _ to: Int32, down: Bool) {
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = buf.withUnsafeMutableBytes { recv(from, $0.baseAddress, 65536, 0) }
                if n <= 0 { break }
                if !LineProxy.sendAll(to, Array(buf[0..<n])) { break }
                lock.lock(); if down { bytesDown += n } else { bytesUp += n }; lock.unlock()
            }
            shutdown(to, SHUT_WR)
        }
        group.enter()
        Thread.detachNewThread { pump(c, out, down: false); group.leave() }
        pump(out, c, down: true)
        _ = group.wait(timeout: .now() + 30)
        close(c); close(out)
    }
}

// One speedtest.net run in a web view nobody sees, pinned as above.
final class LineSpeedTest: NSObject, WKNavigationDelegate {
    enum Pin { case device(String), socks(UInt16), route }
    static var running: LineSpeedTest?
    static var readerJS: [String: String] = {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent("speedtest/reader.js"), let s = try? String(contentsOf: u, encoding: .utf8) else { return [:] }
        // the file holds three expressions, each after a line "//== NAME"
        var out: [String: String] = [:], name = "", body: [String] = []
        for line in s.components(separatedBy: "\n") {
            if line.hasPrefix("//== ") { if !name.isEmpty { out[name] = body.joined(separator: "\n") }; name = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces); body = [] }
            else if !name.isEmpty { body.append(line) }
        }
        if !name.isEmpty { out[name] = body.joined(separator: "\n") }
        return out
    }()

    let name: String
    let pin: Pin
    let proxy: LineProxy?
    let web: WKWebView
    let window: NSWindow
    let started = Date()
    var phase = "load"
    var goAt: Date?
    // v92: GO is pressed only 3 s after the page has finished loading, and pressed again while it is still on the page
    // (v89-v90: GO clicked ~1 s after the start, before speedtest.net's own script was ready, was ignored: 5 of 6 runs
    // sat on the start page until the 120 s timeout; the one run that finished had pressed GO at 4 s)
    var loadedAt: Date?
    var running: Date?
    var presses = 0
    var lastProgress = Date.distantPast
    var finished = false
    var failLogged = false
    var last: [String: Any] = [:]
    let done: (_ result: WebSpeed?, _ error: String?, _ note: String) -> Void

    static func start(_ name: String, _ pin: Pin, done: @escaping (WebSpeed?, String?, String) -> Void) -> String? {
        if let r = running { return "a test is running (\(r.name)); one at a time" }
        guard #available(macOS 14.0, *) else { return "the test needs macOS 14" }
        var proxy: LineProxy?
        if case .device(let i) = pin {
            guard let p = LineProxy(iface: i) else { return "\(name): its device \(i) is not here" }
            proxy = p
        }
        running = LineSpeedTest(name, pin, proxy, done)
        return nil
    }

    private init(_ name: String, _ pin: Pin, _ proxy: LineProxy?, _ done: @escaping (WebSpeed?, String?, String) -> Void) {
        self.name = name; self.pin = pin; self.proxy = proxy; self.done = done
        let config = WKWebViewConfiguration()
        let store = WKWebsiteDataStore.nonPersistent()          // nothing shared with the speedometer's window or other tests
        if #available(macOS 14.0, *) {
            var port: UInt16?
            switch pin {
            case .device: port = proxy?.port
            case .socks(let p): port = p
            case .route: port = nil
            }
            if let port, let p = NWEndpoint.Port(rawValue: port) {
                store.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: NWEndpoint.hostPort(host: "127.0.0.1", port: p))]
            }
        }
        config.websiteDataStore = store
        if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }   // v92: never throttled while unseen
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), configuration: config)
        // a window nobody sees (alpha 0, no mouse, no Dock, no ⌘-Tab): WebKit runs a page that is in a window at full speed
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.contentView = web
        if let s = NSScreen.main { window.setFrameOrigin(NSPoint(x: s.frame.minX, y: s.frame.minY)) }
        window.orderFrontRegardless()
        web.navigationDelegate = self
        appendLog("\(logStamp()) LINE TEST \(name): speedtest.net in a hidden web view, \(pinWords)")
        AdBlock.install(into: config.userContentController) { [weak self] _, _ in
            self?.web.load(URLRequest(url: SpeedBrowser.home))
        }
        tick()
    }

    var pinWords: String {
        switch pin {
        case .device(let i): return "pinned to \(i) by a SOCKS5 proxy on 127.0.0.1:\(proxy?.port ?? 0) (bound to the device)"
        case .socks(let p): return "pinned to the phone through its ck-phone on 127.0.0.1:\(p)"
        case .route: return "over the Mac's route (the ticked lines together)"
        }
    }

    func js(_ key: String, _ then: @escaping (Any?) -> Void) {
        guard let s = LineSpeedTest.readerJS[key] else { then(nil); return }
        web.evaluateJavaScript(s) { r, _ in then(r) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if loadedAt == nil, webView.url?.host?.contains("speedtest.net") == true { loadedAt = Date() }
    }

    // once a second: the banner declined; GO pressed 3 s after the page loaded; pressed again (up to 4 times) while GO is
    // still there 8 s later; then the numbers read until the result page
    func tick() {
        guard !finished else { return }
        let age = Date().timeIntervalSince(started)
        if running == nil {
            if age > 60 { finish(nil, presses == 0 ? "speedtest.net did not load within 60 s" : "the test did not start after \(presses) presses of GO"); return }
            js("DECLINE") { _ in }
            if let l = loadedAt, Date().timeIntervalSince(l) >= 3 {
                if let g = goAt, Date().timeIntervalSince(g) < 8 {
                    js("GOVISIBLE") { [weak self] r in
                        guard let self, self.running == nil, (r as? Bool) == false else { return }
                        self.running = Date()
                        appendLog("\(logStamp()) LINE TEST \(self.name): the test runs (GO gone after \(self.presses) press\(self.presses == 1 ? "" : "es"))")
                    }
                } else if presses < 4 {
                    js("GO") { [weak self] r in
                        guard let self, (r as? String) == "go" else { return }
                        self.presses += 1; self.goAt = Date()
                        appendLog("\(logStamp()) LINE TEST \(self.name): GO pressed (\(self.presses))")
                    }
                } else if let g = goAt, Date().timeIntervalSince(g) >= 8 {
                    finish(nil, "the test did not start after 4 presses of GO"); return
                }
            }
        } else {
            if Date().timeIntervalSince(running!) > 120 { finish(nil, "no result within 120 s"); return }
            js("RESULT") { [weak self] r in
                guard let self, let d = r as? [String: Any] else { return }
                self.last = d
                if Date().timeIntervalSince(self.lastProgress) >= 15 {
                    self.lastProgress = Date()
                    appendLog("\(logStamp()) LINE TEST \(self.name): so far ↓ \(d["down"] as? String ?? "") ↑ \(d["up"] as? String ?? "")")
                }
                let down = Double(d["down"] as? String ?? ""), up = Double(d["up"] as? String ?? "")
                if (d["done"] as? Bool) == true, let down, let up {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
                    let t = DateFormatter(); t.dateFormat = "HH:mm"
                    let s = WebSpeed(down_mbps: down, up_mbps: up, ping_ms: Double(d["ping"] as? String ?? ""), url: d["url"] as? String,
                                     at: f.string(from: Date()), time: t.string(from: Date()), seconds: Date().timeIntervalSince(self.running ?? self.started))
                    self.finish(s, nil)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.tick() }
    }

    func finish(_ s: WebSpeed?, _ error: String?) {
        guard !finished else { return }
        if s == nil && !failLogged {
            // v90: what the page showed when it gave no result (which server, how far it got), once, then finish
            failLogged = true
            js("TEXT") { [weak self] r in
                appendLog("\(logStamp()) LINE TEST \(self?.name ?? "?") page at the failure: \(String(((r as? String) ?? "no text").prefix(900)))")
                self?.finish(nil, error)
            }
            return
        }
        finished = true
        web.stopLoading()
        web.loadHTMLString("", baseURL: nil)
        window.orderOut(nil)
        proxy?.stop()
        let ip = (last["ip"] as? String).map { $0.isEmpty ? "" : ", address \($0)" } ?? ""
        let isp = (last["isp"] as? String).map { $0.isEmpty ? "" : " (\($0))" } ?? ""
        let carried = proxy.map { String(format: "; the proxy carried ↓%.1f MB ↑%.1f MB in %ld connections, %ld refused", Double($0.bytesDown) / 1e6, Double($0.bytesUp) / 1e6, $0.connections, $0.refused) } ?? ""
        let note = "\(pinWords)\(ip)\(isp)\(carried)"
        if let s { appendLog("\(logStamp()) LINE TEST \(name): ↓ \(s.down_mbps) ↑ \(s.up_mbps) Mbps, ping \(s.ping_ms.map { String($0) } ?? "?") ms; \(note)") }
        else { appendLog("\(logStamp()) LINE TEST \(name) FAILED: \(error ?? "?"); \(note)") }
        LineSpeedTest.running = nil
        done(s, error, note)
    }
}

extension Stripe {
    // TEST on a row (and on the ALL TICKED row): one test at a time, a click by hand only (no automatic test over a SIM).
    @objc func rowTestPressed(_ b: NSButton) {
        guard let name = b.identifier?.rawValue else { return }
        let pin: LineSpeedTest.Pin
        if name == Stripe.allTickedName {
            pin = .route
        } else {
            guard let o = others.first(where: { $0.name == name }) else { show("\(name) is not here: nothing to test", Ink.amber, for: 6); return }
            if Phones.isPhone(o.iface) {
                guard let p = Phones.list().first(where: { $0.device == o.iface }) else { show("\(name): the phone's line is not ready", Ink.amber, for: 6); return }
                pin = .socks(p.port)
            } else { pin = .device(o.iface) }
        }
        let label = name == Stripe.allTickedName ? (tickedNames.isEmpty ? "the Mac's own connection" : tickedNames.joined(separator: " + ")) : name
        if let refused = LineSpeedTest.start(name, pin, done: { [weak self] s, err, note in
            guard let self else { return }
            if let s { WebSpeedByConnection.record(s, on: name == Stripe.allTickedName ? "ticked: " + label : name) }
            self.rowTests[name] = (s, err, note, label)
            self.show(s.map { String(format: "TEST %@: ↓ %.1f ↑ %.1f Mbit/s, ping %.0f ms", label, $0.down_mbps, $0.up_mbps, $0.ping_ms ?? 0) } ?? "TEST \(label): \(err ?? "failed")",
                      s == nil ? Ink.red : Ink.green, for: 20, tip: note)
            self.layoutLines()
        }) {
            show(refused, Ink.amber, for: 6)
            return
        }
        rowTests[name] = (nil, nil, "running", label)
        show("TEST \(label): speedtest.net over \(name == Stripe.allTickedName ? "the ticked lines together" : "this line only")… (about 40 s)", Ink.amber, for: 60)
        layoutLines()
    }

    // The result words on a row: "↓ 26.3 ↑ 38.2 · 21:16", "testing…", "✗ no result".
    func testWords(_ name: String) -> (String, NSColor, String?) {
        if let t = rowTests[name] {
            if t.note == "running" { return ("testing…", Ink.amber, nil) }
            if let s = t.result { return (String(format: "↓%.1f ↑%.1f %@", s.down_mbps, s.up_mbps, s.time), Ink.text, "speedtest.net \(s.at): ↓ \(s.down_mbps) ↑ \(s.up_mbps) Mbit/s, ping \(s.ping_ms.map { String(Int($0)) } ?? "?") ms\n\(t.note)") }
            return ("✗ " + (t.error ?? "failed"), Ink.red, t.note)
        }
        let key = name == Stripe.allTickedName ? "ticked: " + (tickedNames.isEmpty ? "the Mac's own connection" : tickedNames.joined(separator: " + ")) : name
        if let s = WebSpeedByConnection.all()[key] { return (String(format: "↓%.1f ↑%.1f %@", s.down_mbps, s.up_mbps, s.time), Ink.dim, "speedtest.net \(s.at): ↓ \(s.down_mbps) ↑ \(s.up_mbps) Mbit/s") }
        return ("", Ink.dim, nil)
    }
}
