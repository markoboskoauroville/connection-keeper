// PING VM (v84, request 93, Marko 16.11.2026: "can I get in Connection Keeper this kind of ping Marko virtual machine button
// then it opens the terminal and I watch it pinging of my machine"). A click opens a NEW iTerm2 window (Terminal.app only
// when iTerm2 is missing) running `ping 100.102.86.30`, chromium-vm over Tailscale; if Tailscale is off, the window first
// runs tailscale-ensure-up and says so. Right-click (the button's menu): `tailscale ping chromium-vm`, which shows whether
// the path is direct or through a DERP relay. The public address 130.61.181.83 does not answer ping (Oracle's security
// list and the VM's iptables drop ICMP) and is left that way (TAKEOVER, "PING VM").
// The window is opened with `open -a` on a .command file: no AppleEvents, so no Automation permission is asked.
import AppKit

enum PingVM {
    static let vm = "100.102.86.30"
    static let ts = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    static let prelude = """
    #!/bin/zsh
    clear
    echo "Pinging chromium-vm (Frankfurt) over Tailscale. Ctrl+C stops."
    echo
    ENSURE="$HOME/.local/bin/tailscale-ensure-up"
    if [ -x "$ENSURE" ]; then
      if ! "$ENSURE" --check >/dev/null 2>&1; then echo "Tailscale is off: turning it on first (tailscale-ensure-up) ..."; "$ENSURE"; echo; fi
    elif ! TAILSCALE_BE_CLI=1 \(ts) status >/dev/null 2>&1 </dev/null; then
      echo "Tailscale is off: turning it on first (tailscale up) ..."; TAILSCALE_BE_CLI=1 \(ts) up </dev/null; echo
    fi

    """

    static func open(tailscalePing: Bool) {
        let body = tailscalePing
            ? "echo \"tailscale ping: 'via DERP(...)' = relayed, 'via <ip:port>' = direct\"; echo\nTAILSCALE_BE_CLI=1 \(ts) ping --until-direct=false -c 100000 chromium-vm </dev/null\n"
            : "exec /sbin/ping \(vm)\n"
        let file = Paths.support.appendingPathComponent(tailscalePing ? "tailscale-ping-vm.command" : "ping-vm.command")
        do {
            try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try (prelude + body).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch {
            appendLog("\(logStamp()) PING VM: could not write \(file.lastPathComponent): \(error)")
            return
        }
        let ws = NSWorkspace.shared
        let app = ws.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")
            ?? ws.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        guard let app else { appendLog("\(logStamp()) PING VM: no iTerm2 and no Terminal"); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        ws.open([file], withApplicationAt: app, configuration: cfg) { _, err in
            appendLog("\(logStamp()) PING VM: \(tailscalePing ? "tailscale ping" : "ping") opened in \(app.deletingPathExtension().lastPathComponent)" + (err.map { " (error: \($0.localizedDescription))" } ?? ""))
        }
    }
}

extension Stripe {
    func makePingVMWord() -> NSButton {
        let b = word("PING VM", Ink.text, #selector(pingVMPressed), id: "ping-vm",
                     tip: "Opens a terminal pinging chromium-vm (Frankfurt) over Tailscale. Right-click: tailscale ping (direct or DERP)")
        let m = NSMenu()
        let a = NSMenuItem(title: "ping 100.102.86.30 (chromium-vm over Tailscale)", action: #selector(pingVMPressed), keyEquivalent: ""); a.target = self
        let t = NSMenuItem(title: "tailscale ping chromium-vm (direct or DERP)", action: #selector(tailscalePingVMPressed), keyEquivalent: ""); t.target = self
        m.addItem(a); m.addItem(t)
        b.menu = m
        return b
    }
    @objc func pingVMPressed() { PingVM.open(tailscalePing: false) }
    @objc func tailscalePingVMPressed() { PingVM.open(tailscalePing: true) }
}
