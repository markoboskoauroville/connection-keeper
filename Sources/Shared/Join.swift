// JOINING A WI-FI ON macOS 15 (v5, live test 14.10.2026).
//
// `networksetup -setairportnetwork en0 mantra` without a password does not join: airportd logs
// "Apple80211Associate2: Missing password for upper auth 4096 ... Failed to associate ... -3900" because
// networksetup is not entitled to the keychain password. When the Mac then lands somewhere it is macOS's own
// auto-join after the forced disconnect, not the network that was asked for. So a join tries, in order:
//   1. networksetup alone (works for open networks), confirmed by the SSID;
//   2. networksetup with the password Marko gave once in Settings (kept in the login keychain, never in a file);
//   3. Control Centre's Wi-Fi list, clicked through accessibility (what a hand on the menu does; needs the
//      Accessibility permission for this program);
// and believes only the SSID and an address afterwards.
import Foundation
import Security
import ApplicationServices
import AppKit

enum WifiPassword {
    static let service = "com.mantra.connectionkeeper.wifi"

    // Both programs of the bundle may read it without a prompt.
    static func trustedApps() -> [SecTrustedApplication] {
        let paths = ["/Applications/Network Aggregate Connection Keeper (Mantra).app",
                     "/Applications/Network Aggregate Connection Keeper (Mantra).app/Contents/MacOS/connection-keeperd"]
        return paths.compactMap { p in
            var t: SecTrustedApplication?
            return SecTrustedApplicationCreateFromPath(p, &t) == errSecSuccess ? t : nil
        }
    }

    static func has(_ ssid: String) -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: ssid, kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ ssid: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: ssid, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func set(_ ssid: String, _ password: String) -> OSStatus {
        remove(ssid)
        var access: SecAccess?
        SecAccessCreate("Connection Keeper: Wi-Fi \(ssid)" as CFString, trustedApps() as CFArray, &access)
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: ssid, kSecAttrLabel as String: "Connection Keeper: Wi-Fi \(ssid)",
                                kSecValueData as String: Data(password.utf8)]
        if let access { q[kSecAttrAccess as String] = access }
        return SecItemAdd(q as CFDictionary, nil)
    }

    static func remove(_ ssid: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: ssid]
        SecItemDelete(q as CFDictionary)
    }
}

enum Join {
    // Up to `seconds` for the Mac to be on `ssid` with an address.
    static func confirm(_ ssid: String, _ iface: String, seconds: Int) -> Bool {
        for _ in 0..<max(1, seconds / 2) {
            if Net.currentSSID(iface) == ssid, Net.ipAddress(iface) != nil { return true }
            sleep(2)
        }
        return Net.currentSSID(iface) == ssid && Net.ipAddress(iface) != nil
    }

    // The whole road. `progress` gets a few words for the status line. `detail` says which way worked or why none did.
    static func wifi(_ ssid: String, _ iface: String, progress: (String) -> Void = { _ in }) -> (ok: Bool, detail: String) {
        if Net.currentSSID(iface) == ssid, Net.ipAddress(iface) != nil { return (true, "already on \(ssid)") }
        var why: [String] = []

        let plain = Net.join(ssid, iface)
        if confirm(ssid, iface, seconds: plain.ok ? 20 : 6) { return (true, "joined by networksetup") }
        why.append("networksetup: \(plain.detail.replacingOccurrences(of: "\n", with: " "))")

        if let pw = WifiPassword.get(ssid) {
            progress("joining \(ssid) with its password…")
            let r = shell("/usr/sbin/networksetup", ["-setairportnetwork", iface, ssid, pw], timeout: 40)
            if confirm(ssid, iface, seconds: 20) { return (true, "joined with the stored password") }
            why.append("with the stored password: \(r.out.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))")
        } else {
            why.append("no password stored (⚙ → Password)")
        }

        if AXIsProcessTrusted() {
            progress("joining \(ssid) through Control Centre…")
            let c = ControlCenterWifi.click(ssid)
            if c.ok, confirm(ssid, iface, seconds: 20) { return (true, "joined through Control Centre") }
            why.append("Control Centre: \(c.detail)")
        } else {
            why.append("no Accessibility permission for Control Centre")
        }
        return (false, why.joined(separator: "; "))
    }
}

// Control Centre's Wi-Fi list, pressed through the accessibility API (no mouse moves). Elements are found
// by their identifiers (com.apple.menuextra.controlcenter, controlcenter-wifi, wifi-network-<SSID>), which
// do not change with the language. Measured on macOS 15, 14.10.2026.
enum ControlCenterWifi {
    static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    static func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    static func ident(_ e: AXUIElement) -> String? { attr(e, "AXIdentifier") as? String }

    static func find(_ root: AXUIElement, depth: Int = 0, _ match: (String) -> Bool) -> AXUIElement? {
        if let i = ident(root), match(i) { return root }
        if depth > 12 { return nil }
        for c in children(root) { if let f = find(c, depth: depth + 1, match) { return f } }
        return nil
    }

    static func wait(_ seconds: Double, _ get: () -> AXUIElement?) -> AXUIElement? {
        let end = Date().addingTimeInterval(seconds)
        repeat { if let e = get() { return e }; usleep(200_000) } while Date() < end
        return nil
    }

    // Control Centre does not open over a full-screen app (measured 14.10.2026: nothing over full-screen iTerm,
    // the panel at once with Finder in front). Finder comes forward for the moment; the app before it returns after.
    static func withFinderInFront<T>(_ body: () -> T) -> T {
        let before = NSWorkspace.shared.frontmostApplication
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate()
            usleep(600_000)
        }
        let r = body()
        if let before, before.bundleIdentifier != "com.apple.finder" { usleep(300_000); before.activate() }
        return r
    }

    static func click(_ ssid: String) -> (ok: Bool, detail: String) { withFinderInFront { clickNow(ssid) } }
    static func list() -> (ok: Bool, networks: [String], detail: String) { withFinderInFront { listNow() } }

    static func clickNow(_ ssid: String) -> (ok: Bool, detail: String) {
        guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return (false, "Control Centre is not running")
        }
        let app = AXUIElementCreateApplication(cc.processIdentifier)
        let bar = (attr(app, "AXExtrasMenuBar") as! AXUIElement?) ?? app
        let wanted = "wifi-network-\(ssid)"
        var opened: AXUIElement?

        // A Wi-Fi icon in the menu bar opens the list directly; otherwise Control Centre, then its Wi-Fi details.
        if let wifiItem = children(bar).first(where: { ident($0) == "com.apple.menuextra.wifi" }) {
            AXUIElementPerformAction(wifiItem, kAXPressAction as CFString); opened = wifiItem
        } else if let ccItem = children(bar).first(where: { ident($0) == "com.apple.menuextra.controlcenter" }) {
            AXUIElementPerformAction(ccItem, kAXPressAction as CFString); opened = ccItem
            guard let tile = wait(3, { find(app) { $0 == "controlcenter-wifi" } }) else { return (false, "no Wi-Fi tile") }
            var names: CFArray?
            AXUIElementCopyActionNames(tile, &names)
            if let details = (names as? [String])?.first(where: { $0.contains("show details") }) {
                AXUIElementPerformAction(tile, details as CFString)
            } else {
                close(opened); return (false, "the Wi-Fi tile has no details action")
            }
        } else {
            return (false, "no Control Centre in the menu bar")
        }
        guard let row = wait(4, { find(app) { $0 == wanted } }) else {
            close(opened); return (false, "\(ssid) is not in the Wi-Fi list (out of range?)")
        }
        let err = AXUIElementPerformAction(row, kAXPressAction as CFString)
        usleep(500_000)
        close(opened)
        return err == .success ? (true, "pressed") : (false, "press failed (\(err.rawValue))")
    }

    // A dry look (v6): open the Wi-Fi list, read the networks it offers, close it, press nothing.
    static func listNow() -> (ok: Bool, networks: [String], detail: String) {
        guard AXIsProcessTrusted() else { return (false, [], "no Accessibility permission") }
        guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return (false, [], "Control Centre is not running")
        }
        let app = AXUIElementCreateApplication(cc.processIdentifier)
        guard let bar = attr(app, "AXExtrasMenuBar") else { return (false, [], "no menu bar extras") }
        let barEl = bar as! AXUIElement
        var opened: AXUIElement?
        if let wifiItem = children(barEl).first(where: { ident($0) == "com.apple.menuextra.wifi" }) {
            AXUIElementPerformAction(wifiItem, kAXPressAction as CFString); opened = wifiItem
        } else if let ccItem = children(barEl).first(where: { ident($0) == "com.apple.menuextra.controlcenter" }) {
            AXUIElementPerformAction(ccItem, kAXPressAction as CFString); opened = ccItem
            guard let tile = wait(3, { find(app) { $0 == "controlcenter-wifi" } }) else { close(opened); return (false, [], "no Wi-Fi tile") }
            var names: CFArray?
            AXUIElementCopyActionNames(tile, &names)
            guard let details = (names as? [String])?.first(where: { $0.contains("show details") }) else {
                close(opened); return (false, [], "the Wi-Fi tile has no details action")
            }
            AXUIElementPerformAction(tile, details as CFString)
        } else {
            return (false, [], "no Control Centre in the menu bar")
        }
        _ = wait(4, { find(app) { $0.hasPrefix("wifi-network-") } })
        var found: [String] = []
        func collect(_ e: AXUIElement, _ depth: Int) {
            if let i = ident(e), i.hasPrefix("wifi-network-") { found.append(String(i.dropFirst("wifi-network-".count))) }
            if depth < 12 { children(e).forEach { collect($0, depth + 1) } }
        }
        collect(app, 0)
        close(opened)
        return (!found.isEmpty, found, found.isEmpty ? "the Wi-Fi list showed no networks" : "read the list")
    }

    // The panel closes with a second press on its menu bar item.
    static func close(_ item: AXUIElement?) {
        guard let item else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }
}
