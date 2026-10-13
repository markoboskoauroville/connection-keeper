// The gear: which connections the keeper may use, in which order, and how often it checks.
// Every change is written to ~/.config/connection-keeper.json at once; the keeper reads it on its
// next round.
import AppKit

final class SettingsWindow: NSObject {
    let window: NSWindow
    let rows = NSStackView()
    let addPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    let interval = NSTextField(string: "")
    let dry = NSButton(checkboxWithTitle: "Dry run (the keeper only logs what it would do)", target: nil, action: nil)
    var cfg = Config.load()

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(appName): Settings"
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Connections, in the order the keeper tries them")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6

        addPopup.target = self
        addPopup.action = #selector(add(_:))

        interval.alignment = .right
        interval.widthAnchor.constraint(equalToConstant: 50).isActive = true
        interval.target = self
        interval.action = #selector(intervalChanged)
        let intervalRow = NSStackView(views: [NSTextField(labelWithString: "Check every"), interval, NSTextField(labelWithString: "minutes")])

        dry.target = self
        dry.action = #selector(dryChanged)

        // The version, plain and dim; a click opens the newest release (version-visible.md).
        let version = NSButton(title: "v\(CKVersion)", target: self, action: #selector(openRelease))
        version.isBordered = false
        version.font = .systemFont(ofSize: 11)
        version.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, rows, addPopup, intervalRow, dry, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
        ])
    }

    func show() {
        cfg = Config.load()
        rebuild()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func rebuild() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, c) in cfg.connections.enumerated() {
            let on = NSButton(checkboxWithTitle: c.name, target: self, action: #selector(toggle(_:)))
            on.state = c.enabled ? .on : .off
            on.tag = i
            on.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let kind = NSTextField(labelWithString: c.kind == "wifi" ? "Wi-Fi" : "\(c.kind) (not driven yet)")
            kind.textColor = .secondaryLabelColor
            kind.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let up = small("▲", #selector(moveUp(_:)), i); up.isEnabled = i > 0
            let down = small("▼", #selector(moveDown(_:)), i); down.isEnabled = i < cfg.connections.count - 1
            let remove = small("✕", #selector(remove(_:)), i)
            rows.addArrangedSubview(NSStackView(views: [on, kind, up, down, remove]))
        }

        addPopup.removeAllItems()
        addPopup.addItem(withTitle: "Add a Wi-Fi the Mac knows…")
        let have = Set(cfg.connections.map { $0.name })
        for name in Net.preferredNetworks(Net.wifiInterface() ?? "en0") where !have.contains(name) {
            addPopup.addItem(withTitle: name)
        }
        interval.stringValue = String(format: "%g", Double(cfg.intervalSeconds) / 60)
        dry.state = cfg.dryRun ? .on : .off
    }

    func small(_ t: String, _ a: Selector, _ tag: Int) -> NSButton {
        let b = NSButton(title: t, target: self, action: a)
        b.bezelStyle = .inline
        b.tag = tag
        return b
    }

    func commit() { cfg.save(); rebuild() }

    @objc func toggle(_ b: NSButton) { cfg.connections[b.tag].enabled = b.state == .on; commit() }
    @objc func moveUp(_ b: NSButton) { cfg.connections.swapAt(b.tag, b.tag - 1); commit() }
    @objc func moveDown(_ b: NSButton) { cfg.connections.swapAt(b.tag, b.tag + 1); commit() }
    @objc func remove(_ b: NSButton) { cfg.connections.remove(at: b.tag); commit() }

    @objc func add(_ p: NSPopUpButton) {
        guard p.indexOfSelectedItem > 0, let name = p.titleOfSelectedItem else { return }
        cfg.connections.append(Connection(kind: "wifi", name: name))
        commit()
    }

    @objc func intervalChanged() {
        if let m = Double(interval.stringValue.replacingOccurrences(of: ",", with: ".")), m > 0 {
            cfg.intervalSeconds = max(30, Int(m * 60))
        }
        commit()
    }

    @objc func dryChanged() { cfg.dryRun = dry.state == .on; commit() }

    @objc func openRelease() { NSWorkspace.shared.open(URL(string: CKReleaseURL)!) }
}
