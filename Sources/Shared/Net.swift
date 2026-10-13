// What the Mac's network looks like, read through its own command-line tools, and the few acts
// that change it (join a Wi-Fi, switch the Wi-Fi power). No Location permission is needed:
// `ipconfig getsummary` names the SSID where CoreWLAN would ask for it.
import Foundation

@discardableResult
func shell(_ path: String, _ args: [String], timeout: TimeInterval = 20) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let deadline = Date().addingTimeInterval(timeout)
    var data = Data()
    let reader = DispatchQueue(label: "shell.read")
    let done = DispatchSemaphore(value: 0)
    reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile(); done.signal() }
    while p.isRunning && Date() < deadline { usleep(50_000) }
    if p.isRunning { p.terminate() }
    _ = done.wait(timeout: .now() + 2)
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

enum Probe {
    case online(how: String, latencyMs: Double?)
    case captive
    case offline(String)

    var isOnline: Bool { if case .online = self { return true }; return false }
}

enum Net {
    static func wifiInterface() -> String? {
        let out = shell("/usr/sbin/networksetup", ["-listallhardwareports"]).out
        let lines = out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Hardware Port: Wi-Fi") && i + 1 < lines.count {
            return lines[i + 1].replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func currentSSID(_ iface: String) -> String? {
        let out = shell("/usr/sbin/ipconfig", ["getsummary", iface]).out
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SSID : ") {
                let ssid = String(t.dropFirst("SSID : ".count))
                return ssid.isEmpty || ssid == "<redacted>" ? nil : ssid
            }
        }
        return nil
    }

    static func ipAddress(_ iface: String) -> String? {
        let r = shell("/usr/sbin/ipconfig", ["getifaddr", iface], timeout: 5)
        let ip = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && !ip.isEmpty ? ip : nil
    }

    static func defaultRouteInterface() -> String? {
        let out = shell("/sbin/route", ["-n", "get", "default"], timeout: 5).out
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("interface:") { return t.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    static func preferredNetworks(_ iface: String) -> [String] {
        let out = shell("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", iface]).out
        return out.components(separatedBy: "\n").dropFirst()
            .filter { $0.hasPrefix("\t") }
            .map { String($0.dropFirst()) }
            .filter { !$0.isEmpty }
    }

    static func wifiPowerOn(_ iface: String) -> Bool {
        shell("/usr/sbin/networksetup", ["-getairportpower", iface]).out.contains(": On")
    }

    // networksetup answers 0 even when it fails, and says why in words; any output is a failure.
    static func join(_ ssid: String, _ iface: String) -> (ok: Bool, detail: String) {
        let r = shell("/usr/sbin/networksetup", ["-setairportnetwork", iface, ssid], timeout: 40)
        let said = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.status == 0 && said.isEmpty, said.isEmpty ? "status \(r.status)" : said)
    }

    static func setWifiPower(_ iface: String, _ on: Bool) -> Bool {
        shell("/usr/sbin/networksetup", ["-setairportpower", iface, on ? "on" : "off"]).status == 0
    }

    // ping first; a blocked ping is not an outage, so an HTTP probe decides before "offline".
    static func probe(pingHost: String, httpURL: String) -> Probe {
        let r = shell("/sbin/ping", ["-c", "3", "-i", "0.5", "-t", "6", "-q", pingHost], timeout: 10)
        if r.status == 0 {
            var avg: Double?
            if let line = r.out.components(separatedBy: "\n").first(where: { $0.contains("round-trip") }),
               let eq = line.components(separatedBy: "= ").last {
                let parts = eq.components(separatedBy: "/")
                if parts.count > 1 { avg = Double(parts[1]) }
            }
            return .online(how: "ping \(pingHost)", latencyMs: avg)
        }
        switch http(httpURL) {
        case .some(true): return .online(how: "http (ping \(pingHost) blocked)", latencyMs: nil)
        case .some(false): return .captive
        case .none: return .offline("no ping from \(pingHost), no http")
        }
    }

    // true: the probe page came back as it should. false: something answered with another page
    // (a captive portal). nil: nothing answered.
    static func http(_ urlString: String) -> Bool? {
        guard let url = URL(string: urlString) else { return nil }
        let conf = URLSessionConfiguration.ephemeral
        conf.timeoutIntervalForRequest = 8
        conf.timeoutIntervalForResource = 10
        conf.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: conf)
        let sem = DispatchSemaphore(value: 0)
        var result: Bool?
        session.dataTask(with: url) { data, resp, _ in
            if let code = (resp as? HTTPURLResponse)?.statusCode {
                let body = String(decoding: data ?? Data(), as: UTF8.self)
                result = code == 200 && (!urlString.contains("captive.apple.com") || body.contains("Success"))
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 12)
        session.invalidateAndCancel()
        return result
    }
}

// Bytes in and out of one interface, from the kernel's interface table (32-bit counters: the
// difference is taken modulo 2^32, so a wrap reads as the right small number).
struct Traffic {
    static func counters(_ iface: String) -> (rx: UInt32, tx: UInt32)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            if let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: a.pointee.ifa_name) == iface, let raw = a.pointee.ifa_data {
                let d = raw.assumingMemoryBound(to: if_data.self).pointee
                return (d.ifi_ibytes, d.ifi_obytes)
            }
            p = a.pointee.ifa_next
        }
        return nil
    }
}
