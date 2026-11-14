// ON · OFF · TOP (v39, request 56, Marko 31.10.2026: "every application, including this one, has on-off switch, and off
// we going to clean up all traces from this app, and we have on top, which is just the word top"). As in Mantra Sound
// Recorder v8 (MANTRA_MANIFEST swift-apps.md, "The first row of every app: ON OFF … TOP ✕"); the stripe is a panel,
// so the words sit on its one line: ON OFF after the minimize circle, TOP before the LED.
//
// OFF leaves nothing of the app between the Mac and the internet, then quits:
//   - the tunnel's flag removed (utun99's routes go within 2 s; the root helper idles, it cannot be removed without
//     his password), macOS's SOCKS proxy off, the aggregation server stopped and kept from starting at login;
//   - the keeper (the Wi-Fi switching) stopped and kept from starting at login;
//   - ck-phone stopped on every phone and its adb port forward removed;
//   - the passing files (rescan, commands, test locks) deleted.
// The radios are left exactly as they are: the TP-Link's Wi-Fi, the Mac's Wi-Fi and the phones' hotspots are never
// switched by OFF. Settings, the ticks, the logs stay (they change nothing in the network).
// ON is the app running: started from the star it brings back the mode it had before OFF. A login start after OFF
// quits at once: OFF stays off until he starts it.
import AppKit

enum OnOff {
    static let resumeKey = "resumeAggregate", offKey = "offByHand"

    // The whole clean-up; each line says what was done (logged).
    static func cleanUp() -> [String] {
        var said: [String] = []
        let wasAggregate = Aggregation.aggregateMode
        UserDefaults.standard.set(wasAggregate, forKey: resumeKey)
        said += Aggregation.setMode(false)
        if Aggregation.tunnelInstalled {
            for _ in 0..<20 where Aggregation.tunnelUp { usleep(250_000) }
            said.append(Aggregation.tunnelUp ? "the tunnel still up after 5 s (its helper takes it down within seconds)" : "the tunnel down, the Mac straight on its lines")
        }
        if Aggregation.systemProxyIsOn() { said += Aggregation.systemProxy(false) }
        let domain = "gui/\(getuid())"
        shell("/bin/launchctl", ["bootout", "\(domain)/\(CKAgentLabel)"])
        shell("/bin/launchctl", ["disable", "\(domain)/\(CKAgentLabel)"])
        said.append("the keeper stopped")
        if let adb = Phones.adb {
            for p in Phones.list() {
                shell(adb, ["-s", p.serial, "shell", "pkill", "-f", Phones.remote], timeout: 8)
                shell(adb, ["-s", p.serial, "forward", "--remove", "tcp:\(p.port)"], timeout: 8)
                said.append("\(p.name): ck-phone stopped, port forward removed")
            }
        }
        for f in ["aggregate-rescan", "aggregate-rescan-done", "command.json", "speedtest.json.lock", "speedtest.hold"] {
            try? FileManager.default.removeItem(at: Paths.support.appendingPathComponent(f))
        }
        return said
    }

    // At start: a login start after OFF quits; a start by hand clears OFF and brings aggregation back if it was on.
    static func atStart(login: Bool) -> Bool {
        if UserDefaults.standard.bool(forKey: offKey) {
            if login { return false }
            UserDefaults.standard.set(false, forKey: offKey)
            if UserDefaults.standard.bool(forKey: resumeKey) {
                UserDefaults.standard.set(false, forKey: resumeKey)
                DispatchQueue.global().async {
                    for l in Aggregation.setMode(true) { appendLog("\(logStamp()) ON: \(l)") }
                }
            }
        }
        return true
    }
}

extension Stripe {
    func word(_ title: String, _ color: NSColor, _ action: Selector, id: String, tip: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        b.contentTintColor = color
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setAccessibilityIdentifier(id)
        b.toolTip = tip
        return b
    }

    func showTop() { topWord.contentTintColor = OnTop.on ? Ink.green : Ink.grey; topWord.setAccessibilityValue(OnTop.on ? "on" : "off") }

    @objc func toggleTop() { OnTop.on.toggle(); showTop() }

    @objc func switchOff() {
        offWord.contentTintColor = Ink.amber
        offWord.title = "OFF…"
        appendLog("\(logStamp()) OFF pressed: cleaning up")
        DispatchQueue.global().async {
            let said = OnOff.cleanUp()
            for l in said { appendLog("\(logStamp()) OFF: \(l)") }
            UserDefaults.standard.set(true, forKey: OnOff.offKey)
            try? FileManager.default.removeItem(at: Session.lease)
            DispatchQueue.main.async { AppShell.shared.offDone = true; NSApp.terminate(nil) }
        }
    }
}
