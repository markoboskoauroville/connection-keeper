// What the Mac's network looks like, read through its own command-line tools, and the few acts
// that change it (join a Wi-Fi, switch the Wi-Fi power). No Location permission is needed:
// `ipconfig getsummary` names the SSID where CoreWLAN would ask for it.
import Foundation
import CoreWLAN

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
    // Asked of macOS every time (v12, Marko 18.10.2026: "I always see en0 as device, but I'm changing the devices"): the
    // keeper used to ask once at its start, the answer was empty at the login of 17.10.2026, and every connection was
    // "en0" from then on. CoreWLAN first; networksetup only when CoreWLAN knows no Wi-Fi.
    static func wifiInterface() -> String? {
        if let n = CWWiFiClient.shared().interfaceNames()?.sorted().first { return n }
        let out = shell("/usr/sbin/networksetup", ["-listallhardwareports"]).out
        let lines = out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Hardware Port: Wi-Fi") && i + 1 < lines.count {
            return lines[i + 1].replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // The name a person knows: the Wi-Fi network's name ("mantra"), or "Wi-Fi" when macOS hides it; for any other
    // device its hardware port ("iPhone USB", "AX88179B", "Thunderbolt Bridge"), never "en0".
    static func displayName(_ iface: String) -> String {
        if iface == wifiInterface() { return currentSSID(iface) ?? "Wi-Fi" }
        let lines = shell("/usr/sbin/networksetup", ["-listallhardwareports"]).out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == "Device: \(iface)" && i > 0 {
            let port = lines[i - 1].replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            if !port.isEmpty { return port }
        }
        return iface
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

    // A join that is believed only by the SSID and an address afterwards (see Join.swift for the road).
    static func joinAndConfirm(_ ssid: String, _ iface: String) -> (ok: Bool, detail: String) {
        Join.wifi(ssid, iface)
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

    // INTERNET ONLY (v10, Marko 14.10.2026: "I think it's measuring my local network transfer. It should only show the
    // speed of internet transfer, never local."). The interface counters above count everything on en0, the adb push
    // to the phone on 192.168.1.103 included. The kernel also keeps byte counters per route; the default route
    // ("default -> en0 -> 192.168.1.1") carries only what goes out through the router to the internet, TCP and UDP
    // (measured: a 20 MB download +20.4 MB, 3 MB of UDP to 1.1.1.1 +3.08 MB, a 24 MB adb push to the phone +0).
    // `nettop -m route` prints them; IPv4 and IPv6 default routes of the interface are summed.
    static func internet(_ iface: String) -> (rx: UInt64, tx: UInt64)? {
        let r = shell("/usr/bin/nettop", ["-x", "-n", "-L", "1", "-m", "route"], timeout: 5)
        guard r.status == 0 else { return nil }
        var rx: UInt64 = 0, tx: UInt64 = 0, found = false
        for line in r.out.split(separator: "\n") {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count > 3 else { continue }
            let route = f[1].split(separator: " ").map(String.init)      // ["default", "->", "en0", "->", "192.168.1.1"]
            guard route.count >= 3, route[0] == "default", route[2] == iface else { continue }
            rx &+= UInt64(f[2]) ?? 0
            tx &+= UInt64(f[3]) ?? 0
            found = true
        }
        return found ? (rx, tx) : nil
    }
}
