// A PHONE OVER USB IS A LINE (v17, request 36, Marko 19.10.2026: "I have two USB connection one is my USB to LAN
// adapter and connected to TP-Link another USB connection is my noting phone ... connected with USB tethering. So
// please detect and combine these two USB connections into one", and "make this switching from RNDIS mode to NCM
// automatically"). Android's USB tethering speaks RNDIS, which macOS has no driver for; NCM, which macOS does speak,
// is refused by the Nothing A142's USB system ("Could not set unsupported function for the GadgetHal", tried
// 19.10.2026 with tether_force_usb_functions=1 and `svc usb setFunctions ncm`), and changing that needs root. So the
// phone becomes a line over adb, on the same USB cable: ck-phone (Sources/Phone, a small SOCKS5 server) runs on the
// phone from adb's shell and goes out through the phone's internet; `adb forward` puts it on 127.0.0.1:<port> here.
// A phone line has no device on the Mac: its "device" is "adb:<serial>", and the server dials it as a SOCKS5 proxy.
import Foundation

struct Phone {
    let serial: String, name: String, port: UInt16
    var device: String { "adb:\(serial)" }
}

enum Phones {
    static let remote = "/data/local/tmp/ck-phone", remotePort: UInt16 = 8858, firstPort: UInt16 = 8860

    static var adb: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/Library/Android/sdk/platform-tools/adb", "/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // ck-phone in the app (Contents/Resources/phone), found from the running program, else from /Applications.
    static var binary: String? {
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let here = me.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/phone/ck-phone").path
        return [here, "/Applications/Network Aggregate Connection Keeper (Mantra).app/Contents/Resources/phone/ck-phone"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    static func isPhone(_ device: String) -> Bool { device.hasPrefix("adb:") }

    // The phones on a USB cable with USB debugging allowed (not the emulator, not adb over Wi-Fi), each with its own
    // port here, by its place in the serial order. Named by maker and model: "Nothing A142 (USB)".
    static func list() -> [Phone] {
        guard let adb else { return [] }
        let out = shell(adb, ["devices", "-l"], timeout: 8).out
        var serials: [(String, String)] = []
        for line in out.components(separatedBy: "\n").dropFirst() {
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 2, f[1] == "device", f.contains(where: { $0.hasPrefix("usb:") }) else { continue }
            let model = f.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? f[0]
            serials.append((f[0], model))
        }
        serials.sort { $0.0 < $1.0 }
        return serials.enumerated().map { i, s in
            let maker = shell(adb, ["-s", s.0, "shell", "getprop", "ro.product.manufacturer"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (maker.isEmpty || s.1.lowercased().hasPrefix(maker.lowercased()) ? s.1 : "\(maker) \(s.1)") + " (USB)"
            return Phone(serial: s.0, name: name, port: firstPort + UInt16(i))
        }
    }

    // The phone's server answering here: ck-phone on the phone (pushed when missing or different, started when not
    // running) and the port forwarded. A note of what was done, or nil when nothing was needed; throws its reason.
    @discardableResult
    static func ensure(_ p: Phone) -> String? {
        if answers(p) { return nil }
        guard let adb, let bin = binary else { return "no adb or no ck-phone in the app" }
        func sh(_ cmd: String) -> String { shell(adb, ["-s", p.serial, "shell", cmd], timeout: 15).out.trimmingCharacters(in: .whitespacesAndNewlines) }
        var did: [String] = []
        let mine = shell("/usr/bin/shasum", ["-a", "256", bin], timeout: 5).out.split(separator: " ").first.map(String.init) ?? ""
        if sh("sha256sum \(remote) 2>/dev/null").split(separator: " ").first.map(String.init) != mine {
            _ = sh("pkill -f \(remote)")
            guard shell(adb, ["-s", p.serial, "push", bin, remote], timeout: 60).status == 0 else { return "push to \(p.name) failed" }
            _ = sh("chmod 755 \(remote)")
            did.append("ck-phone pushed")
        }
        if sh("pgrep -f \(remote)").isEmpty {
            _ = sh("setsid nohup \(remote) -l 127.0.0.1:\(remotePort) >/data/local/tmp/ck-phone.log 2>&1 </dev/null &")
            did.append("ck-phone started")
        }
        shell(adb, ["-s", p.serial, "forward", "tcp:\(p.port)", "tcp:\(remotePort)"], timeout: 8)
        did.append("forwarded to 127.0.0.1:\(p.port)")
        for _ in 0..<10 where !answers(p) { usleep(300_000) }
        return did.joined(separator: ", ") + (answers(p) ? "" : ", but it does not answer")
    }

    // The SOCKS5 greeting answered on the phone's port.
    static func answers(_ p: Phone) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var sa = sockaddr_in(); sa.sin_family = sa_family_t(AF_INET); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_port = p.port.bigEndian; sa.sin_addr.s_addr = inet_addr("127.0.0.1")
        let c = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard c == 0, send(fd, [UInt8]([5, 1, 0]), 3, 0) == 3 else { return false }
        var r = [UInt8](repeating: 0, count: 2)
        return recv(fd, &r, 2, 0) == 2 && r == [5, 0]
    }

    // A TCP connection to host:port out through the phone, or nil after `timeout` seconds.
    static func dial(_ host: String, _ port: UInt16, via p: UInt16, timeout: Int = 10) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        var sa = sockaddr_in(); sa.sin_family = sa_family_t(AF_INET); sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_port = p.bigEndian; sa.sin_addr.s_addr = inet_addr("127.0.0.1")
        let h = Array(host.utf8)
        func exact(_ n: Int) -> [UInt8]? {
            var b = [UInt8](repeating: 0, count: n), got = 0
            while got < n { let r = b.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, n - got, 0) }; if r <= 0 { return nil }; got += r }
            return b
        }
        let ok = withUnsafePointer(to: &sa, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }) == 0
            && h.count < 256 && send(fd, [UInt8]([5, 1, 0]), 3, 0) == 3 && exact(2) == [5, 0]
        let req: [UInt8] = [5, 1, 0, 3, UInt8(h.count)] + h + [UInt8(port >> 8), UInt8(port & 255)]
        guard ok, send(fd, req, req.count, 0) == req.count, let rep = exact(10), rep[1] == 0 else { close(fd); return nil }
        var none = timeval(tv_sec: 0, tv_usec: 0)                  // the relay waits as long as the connection lives
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    // The internet through the phone: the ms to open a connection to 1.1.1.1:443 (or `host`) through it, or nil.
    static func online(_ p: Phone, host: String = "1.1.1.1") -> Double? {
        let t = Date()
        guard let fd = dial(host, 443, via: p.port, timeout: 5) else { return nil }
        close(fd)
        return Date().timeIntervalSince(t) * 1000
    }

    // What really went over the phone's own internet (mobile data or its Wi-Fi), from its kernel: curl's count through
    // adb is what adb took into its buffers, and a first upload test read 157 Mbit/s on 4G (19.10.2026).
    static func counters(_ serial: String) -> (rx: UInt64, tx: UInt64)? {
        guard let adb else { return nil }
        let r = shell(adb, ["-s", serial, "shell", "cat", "/proc/net/dev"], timeout: 5)
        guard r.status == 0 else { return nil }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for line in r.out.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard name.range(of: #"^(ccmni|rmnet_data|wlan)[0-9]+$"#, options: .regularExpression) != nil else { continue }
            let f = parts[1].split(separator: " ").compactMap { UInt64($0) }
            if f.count >= 9 { rx += f[0]; tx += f[8] }
        }
        return (rx, tx)
    }

    static func publicIP(_ p: Phone) -> String? {
        let r = shell("/usr/bin/curl", ["-s", "-4", "-m", "8", "-x", "socks5h://127.0.0.1:\(p.port)", "https://api.ipify.org"], timeout: 10)
        let ip = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && ip.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil ? ip : nil
    }
}
