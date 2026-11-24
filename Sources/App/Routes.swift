// A LINE WITHOUT ITS OWN ROAD (request 111, 24.11.2026; three installs, 23-24.11.2026, left the cable en17 and the Wi-Fi en0
// without a default route of their own: `curl --interface en17` failed at once, the stripe called them NO DATA and moved
// them down the service order, and the Mac ran on one line). The cause is the root tunnel helper (ck-tunnel, v43): when
// it comes up it adds `-ifscope <main line> default`, and when it goes down (every app quit and start) it deletes that
// route again, even after macOS has made it its own (the order changed meanwhile, the line is no longer the main one).
// macOS does not put the route back by itself. Without root, the app repairs it:
//   - every 30 s (and 10 s after start) every device with a router (not the tunnel, not a phone over adb) is checked in
//     the routing table for a default route through it (its own scoped one, or the main one);
//   - one missing: its network service is switched off and on again (`networksetup -setnetworkserviceenabled`, no
//     password; measured 24.11.2026 01:37: AX88179B off/on and configd rebuilt the scoped default routes of en17 AND en0);
//     at most once in 2 minutes per device, said in the log ("ROUTE ...");
//   - the health probe never calls such a line NO DATA (and never moves it down the order): the fault is the road, not
//     the line, and demoting it is what made it stick.
// The helper itself is fixed in Sources/Tunnel/main.swift (it deletes only a route it still owns); it takes effect when
// Marko runs `sudo ./tunnel.sh install` once.
import Foundation

enum RouteRepair {
    static let lock = NSLock()
    static var lastFix: [String: Date] = [:]
    static var busy = false

    // the devices among `ifaces` that have no default route through them at all
    static func missing(_ ifaces: [String]) -> [String] {
        let out = shell("/usr/sbin/netstat", ["-rn", "-f", "inet"], timeout: 5).out
        var has = Set<String>()
        for l in out.components(separatedBy: "\n") where l.hasPrefix("default") {
            if let i = l.split(separator: " ", omittingEmptySubsequences: true).last { has.insert(String(i)) }
        }
        return ifaces.filter { !has.contains($0) }
    }

    static func service(of iface: String) -> String? {
        if iface == Net.wifiInterface() { return "Wi-Fi" }
        return Net.lanServices().first { $0.device == iface }?.name
    }

    // Off the main thread. Returns the log words of what it did, [] when nothing was missing.
    static func checkAndRepair(_ ifaces: [String]) -> [String] {
        lock.lock(); if busy { lock.unlock(); return [] }; busy = true; lock.unlock()
        defer { lock.lock(); busy = false; lock.unlock() }
        var said: [String] = []
        // wired lines first: switching a cable's service off and on is the gentlest, and rebuilds the Wi-Fi's route too
        let miss = missing(ifaces).sorted { (isWifi($0) ? 1 : 0) < (isWifi($1) ? 1 : 0) }
        for i in miss {
            guard missing([i]).count == 1 else { continue }            // a repair of another line may have rebuilt it
            lock.lock(); let recent = Date().timeIntervalSince(lastFix[i] ?? .distantPast) < 120; if !recent { lastFix[i] = Date() }; lock.unlock()
            guard !recent, let svc = service(of: i) else { continue }
            shell("/usr/sbin/networksetup", ["-setnetworkserviceenabled", svc, "off"], timeout: 10)
            sleep(2)
            shell("/usr/sbin/networksetup", ["-setnetworkserviceenabled", svc, "on"], timeout: 10)
            var back = false
            for _ in 0..<15 { sleep(1); if missing([i]).isEmpty { back = true; break } }
            said.append("ROUTE \(i) had no default route of its own (the tunnel helper's bookkeeping): service \(svc) off and on: " + (back ? "its route is back" : "still none after 15 s"))
        }
        return said
    }

    static func isWifi(_ i: String) -> Bool { i == Net.wifiInterface() }
}

extension Stripe {
    func startRouteRepair() {
        func run() {
            let ifaces = others.filter { !Phones.isPhone($0.iface) && $0.iface != Aggregation.tunnelDevice && !$0.iface.hasPrefix("utun") }.map(\.iface)
            guard !ifaces.isEmpty else { return }
            DispatchQueue.global().async {
                for l in RouteRepair.checkAndRepair(ifaces) { appendLog("\(logStamp()) \(l)") }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { run() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in run() }
    }
}
