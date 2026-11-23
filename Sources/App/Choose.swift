// THE SERVICE ORDER (v49 request 69, v89 request 97). Until v88 the top row had WI-FI · CABLE · BOTH ticks; v89 (Marko
// 23.11.2026: "always all connections are listed and I have check marks for each connection ... Wi-Fi, cable, both,
// these things go out") replaced them with one tick per connection (Ticks.swift). What stays here: macOS's service order
// (the ticked lines first, a NO DATA line last) and the Wi-Fi scan for the list.
import AppKit

enum LinkChoice: String { case wifi, cable, both }

enum ServiceOrder {
    struct Svc { let name: String; let device: String?; let wifi: Bool }

    static func list() -> [Svc] {
        let lines = shell("/usr/sbin/networksetup", ["-listnetworkserviceorder"]).out.components(separatedBy: "\n")
        var out: [Svc] = []
        for (i, line) in lines.enumerated() {
            guard let r = line.range(of: #"^\([0-9*]+\) "#, options: .regularExpression), i + 1 < lines.count else { continue }
            let info = lines[i + 1]
            let dev = info.range(of: #"Device: ([a-z0-9]+)\)"#, options: .regularExpression).map { String(info[$0].dropFirst("Device: ".count).dropLast()) }
            out.append(Svc(name: String(line[r.upperBound...]), device: dev, wifi: info.contains("Hardware Port: Wi-Fi")))
        }
        return out
    }

    // Returns what it did, nil when the order is right already. `first`: the devices of the ticked lines (they go first);
    // dead lines go last, but only while a line with data remains.
    static func apply(first: Set<String>, dead: Set<String>) -> String? {
        let cur = list()
        guard !cur.isEmpty else { return nil }
        let live = cur.filter { s in s.device != nil && !dead.contains(s.device!) && Net.ipAddress(s.device!) != nil }
        let useDead = live.isEmpty ? Set<String>() : dead
        func rank(_ s: Svc) -> Int {
            let r = first.isEmpty ? 0 : (s.device.map { first.contains($0) } == true ? 0 : 1)
            return r + (s.device.map { useDead.contains($0) } == true ? 10 : 0)
        }
        let new = cur.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element.name)
        if new == cur.map(\.name) { return nil }
        let r = shell("/usr/sbin/networksetup", ["-ordernetworkservices"] + new)
        return r.status == 0 && !r.out.contains("rror") ? "\(new.joined(separator: " > "))" : "failed: " + r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Stripe {
    func refreshWifiScan() {
        guard Date().timeIntervalSince(wifiScanAt) > 15 else { return }
        wifiScanAt = Date()
        DispatchQueue.global().async {
            var names = Net.wifiInRange()
            if let w = Net.wifiInterface(), let cur = Net.currentSSID(w) { names.insert(cur) }
            DispatchQueue.main.async { self.wifiScan = names.sorted() }
        }
    }
}
