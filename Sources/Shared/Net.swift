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

    // LIVE (v12, Marko 18.10.2026: "check all internet connections and offer only the one which is online now ... Make
    // it live"): the Wi-Fi networks in range this moment, by name. system_profiler still names them where CoreWLAN's
    // scan gives nil without the Location permission. About 3 s; call it off the main thread.
    static func wifiInRange() -> Set<String> {
        let out = shell("/usr/sbin/system_profiler", ["SPAirPortDataType"], timeout: 20).out
        var names = Set<String>(), inList = false
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "Current Network Information:" || t == "Other Local Wi-Fi Networks:" { inList = true; continue }
            let indent = line.prefix { $0 == " " }.count
            if inList && indent <= 10 && !t.isEmpty { inList = false }
            if inList && indent == 12 && t.hasSuffix(":") { names.insert(String(t.dropLast())) }
        }
        return names
    }

    // The devices that have an address now (Wi-Fi, a cable, a USB adapter, a tethered phone), not the Mac's own.
    static func activeInterfaces() -> [String] {
        let all = shell("/sbin/ifconfig", ["-l"], timeout: 5).out.split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let skip = ["lo", "gif", "stf", "utun", "awdl", "llw", "anpi", "ap", "bridge"]
        return all.filter { i in !skip.contains { i.hasPrefix($0) } && ipAddress(i) != nil }
    }

    // The internet through this one device, without switching anything: one ping bound to it. The ms, or nil.
    static func onlineVia(_ iface: String, host: String = "1.1.1.1") -> Double? {
        let r = shell("/sbin/ping", ["-b", iface, "-c", "1", "-t", "3", host], timeout: 6)
        guard r.status == 0, let m = r.out.range(of: #"time=([0-9.]+)"#, options: .regularExpression) else { return nil }
        return Double(r.out[m].dropFirst(5))
    }

    // SWITCH BETWEEN DEVICES (v12, Marko 18.10.2026: "try to switch between LAN connection and Wi-Fi connection"): the
    // device's network service goes to the top of macOS's service order, so the internet goes through it; no
    // password is needed (proven 18.10.2026: AX88179B on en17 above Wi-Fi, the default route moved to en17).
    @discardableResult
    static func prefer(_ iface: String) -> (ok: Bool, detail: String) {
        let lines = shell("/usr/sbin/networksetup", ["-listnetworkserviceorder"]).out.components(separatedBy: "\n")
        var order: [String] = [], mine: String?
        for (i, line) in lines.enumerated() {
            guard let r = line.range(of: #"^\([0-9*]+\) "#, options: .regularExpression) else { continue }
            let name = String(line[r.upperBound...])
            order.append(name)
            if i + 1 < lines.count, lines[i + 1].contains("Device: \(iface))") { mine = name }
        }
        guard let mine else { return (false, "no network service for \(iface)") }
        if order.first == mine { return (true, "\(mine) is first already") }
        let r = shell("/usr/sbin/networksetup", ["-ordernetworkservices", mine] + order.filter { $0 != mine })
        return r.status == 0 && !r.out.contains("rror") ? (true, "\(mine) first") : (false, r.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // The cable devices macOS has a network service for (USB LAN adapters, Ethernet, a tethered phone), by the name in
    // System Settings → Network, with their device: [("AX88179B", "en17"), ("iPhone USB", "en8"), …]. Wi-Fi, the
    // Thunderbolt bridge and services without a device are left out.
    static func lanServices() -> [(name: String, device: String)] {
        let lines = shell("/usr/sbin/networksetup", ["-listnetworkserviceorder"]).out.components(separatedBy: "\n")
        var out: [(String, String)] = []
        for (i, line) in lines.enumerated() {
            guard let r = line.range(of: #"^\([0-9*]+\) "#, options: .regularExpression), i + 1 < lines.count,
                  let d = lines[i + 1].range(of: #"Device: ([a-z0-9]+)\)"#, options: .regularExpression) else { continue }
            let name = String(line[r.upperBound...])
            let device = String(lines[i + 1][d].dropFirst("Device: ".count).dropLast())
            if lines[i + 1].contains("Hardware Port: Wi-Fi") || name.contains("Thunderbolt Bridge") || device.hasPrefix("bridge") { continue }
            out.append((name, device))
        }
        return out
    }

    // The device of a LAN connection now (a USB adapter may get another enX when plugged elsewhere): by its service name.
    static func lanDevice(_ c: Connection) -> String? {
        lanServices().first { $0.name == c.name }?.device ?? c.interface
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
    static func internet(_ iface: String) -> (rx: UInt64, tx: UInt64)? { internetAll()?[iface] }

    // v13 (request 27, a stripe line per connection): every device's default route from one nettop call. macOS keeps a
    // default route per device (scoped), so a second line used by the aggregation server has its own counters.
    static func internetAll() -> [String: (rx: UInt64, tx: UInt64)]? {
        let r = shell("/usr/bin/nettop", ["-x", "-n", "-L", "1", "-m", "route"], timeout: 5)
        guard r.status == 0 else { return nil }
        var all: [String: (rx: UInt64, tx: UInt64)] = [:]
        for line in r.out.split(separator: "\n") {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count > 3 else { continue }
            let route = f[1].split(separator: " ").map(String.init)      // ["default", "->", "en0", "->", "192.168.1.1"]
            guard route.count >= 3, route[0] == "default" else { continue }
            let old = all[route[2]] ?? (0, 0)
            all[route[2]] = (old.rx &+ (UInt64(f[2]) ?? 0), old.tx &+ (UInt64(f[3]) ?? 0))
        }
        return all
    }
}
