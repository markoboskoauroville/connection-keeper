// THE DIRECT LIST (v74, request 85 item 3): domains that skip the relay and go out over the Mac's own lines (YouTube,
// when Marko wants it; default empty). ~/Library/Application Support/connection-keeper/bond-direct.txt, one domain per
// line (a domain covers its subdomains: youtube.com = www.youtube.com, m.youtube.com …), # for comments; read again when
// it changes. A direct-listed domain shows the HOME address to that site. Apps cannot be listed: the server sees
// connections, not the programs that make them.
//
// The tunnel (utun99) hands the server IP addresses, not names, so the names are learned from the DNS answers that pass
// through the server (UDP and the relay's DNS): an address whose last answer named a listed domain goes direct too.
import Foundation

enum Direct {
    static let lock = NSLock()
    static var file: URL { aggEnv["CK_BOND_DIRECT"].map { URL(fileURLWithPath: $0) } ?? Paths.support.appendingPathComponent("bond-direct.txt") }
    static var rules: [String] = [], stamp: Date?, checked = Date.distantPast
    static var told: [String: Date] = [:]

    static func current() -> [String] {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(checked) < 2 { return rules }
        checked = Date()
        let m = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if m != stamp {
            stamp = m
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            rules = text.components(separatedBy: .newlines).map { $0.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces).lowercased() }
                .map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }.filter { !$0.isEmpty }
            log("DIRECT list: \(rules.isEmpty ? "empty (everything through the relay)" : rules.joined(separator: ", "))")
        }
        return rules
    }

    // The listed domain this host (a name, or an address a DNS answer named) falls under, or nil.
    static func match(_ host: String) -> String? {
        let rs = current()
        guard !rs.isEmpty else { return nil }
        let h = host.lowercased()
        let names = [h] + (DNSNames.names(for: h))
        for n in names { if let r = rs.first(where: { n == $0 || n.hasSuffix("." + $0) }) { return r } }
        return nil
    }

    static func said(_ host: String, _ rule: String) {
        lock.lock(); let last = told[host] ?? .distantPast; if Date().timeIntervalSince(last) > 600 { told[host] = Date() }; lock.unlock()
        if Date().timeIntervalSince(last) > 600 { log("DIRECT \(host) (\(rule), bond-direct.txt): over the Mac's own line, the home address shows") }
    }
}

// The names DNS answers gave to addresses (A records), kept 30 min, at most 20000.
enum DNSNames {
    static let lock = NSLock()
    static var map: [String: (names: Set<String>, at: Date)] = [:]

    static func names(for ip: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let e = map[ip], Date().timeIntervalSince(e.at) < 1800 else { return [] }
        return Array(e.names)
    }

    // A DNS message (the answer): its question's name for every A record in it.
    static func learn(_ m: [UInt8]) {
        guard m.count > 12, m[2] & 0x80 != 0 else { return }               // an answer
        let qd = Int(m[4]) << 8 | Int(m[5]), an = Int(m[6]) << 8 | Int(m[7])
        guard qd >= 1, an >= 1 else { return }
        var i = 12, labels: [String] = []
        while i < m.count {
            let l = Int(m[i])
            if l == 0 { i += 1; break }
            if l & 0xC0 != 0 || i + 1 + l > m.count { return }
            labels.append(String(decoding: m[(i + 1)..<(i + 1 + l)], as: UTF8.self)); i += 1 + l
        }
        let name = labels.joined(separator: ".").lowercased()
        i += 4
        for _ in 1..<qd { return }                                         // one question only (the usual)
        var ips: [String] = []
        for _ in 0..<an {
            // the answer's name: a pointer or labels
            while i < m.count {
                let l = Int(m[i])
                if l & 0xC0 == 0xC0 { i += 2; break }
                if l == 0 { i += 1; break }
                i += 1 + l
            }
            guard i + 10 <= m.count else { break }
            let type = Int(m[i]) << 8 | Int(m[i + 1]), len = Int(m[i + 8]) << 8 | Int(m[i + 9])
            i += 10
            guard i + len <= m.count else { break }
            if type == 1 && len == 4 { ips.append("\(m[i]).\(m[i + 1]).\(m[i + 2]).\(m[i + 3])") }
            i += len
        }
        guard !name.isEmpty, !ips.isEmpty else { return }
        lock.lock()
        if map.count > 20000 { map = map.filter { Date().timeIntervalSince($0.value.at) < 1800 } }
        for ip in ips { var e = map[ip] ?? (names: Set<String>(), at: Date()); e.names.insert(name); e.at = Date(); map[ip] = e }
        lock.unlock()
    }
}
