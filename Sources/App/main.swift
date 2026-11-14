// Network Aggregate Connection Keeper (Mantra): one floating stripe that shows the connection, its speed and the
// keeper's last word, with a drop-down to switch by hand and a gear for the list of connections.
import AppKit
import CoreWLAN
import CoreLocation

let appName = "Network Aggregate Connection Keeper (Mantra)"

enum DataBalanceNote { static let checkNow = Notification.Name("ConnectionKeeperCheckData") }

// ALWAYS ON TOP (v6, Marko 14.10.2026: "please keep it always on top, which can be changed in the settings").
// A setting of the stripe only, remembered in its defaults; on unless he turns it off in ⚙.
enum OnTop {
    static let key = "alwaysOnTop"
    static let changed = Notification.Name("ConnectionKeeperOnTopChanged")
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? false }    // v73: off by default (a normal window)
        set { UserDefaults.standard.set(newValue, forKey: key); NotificationCenter.default.post(name: changed, object: nil) }
    }
}

// TRAIL-like ground: dark, colour only for state. Green on, amber holding / working, red down,
// grey present but not available.
enum Ink {
    static let ground = NSColor(calibratedWhite: 0.08, alpha: 0.94)
    static let text = NSColor(calibratedWhite: 0.88, alpha: 1)
    static let dim = NSColor(calibratedWhite: 0.55, alpha: 1)
    static let green = NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.45, alpha: 1)
    static let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 1)
    static let red = NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.30, alpha: 1)
    static let grey = NSColor(calibratedWhite: 0.40, alpha: 1)
    static let yellow = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.20, alpha: 1)   // v12: the ping section (Marko)
}

// WHERE THE STRIPE STANDS (v13, Marko 18.10.2026: "make sure the app itself remembers its last position and its last
// display"): the display by its name and the stripe's top-left corner on it, so a taller or shorter stripe and a
// re-arranged desk still find the same place. NSWindow's autosave kept the whole frame and lost the place when the
// stripe changed height.
enum StripePlace {
    static let key = "stripePlace"
    static func save(_ panel: NSPanel) {
        let f = panel.frame
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: f.midX, y: f.maxY - 1)) }) ?? panel.screen else { return }
        UserDefaults.standard.set(["screen": s.localizedName, "x": f.minX - s.frame.minX, "top": s.frame.maxY - f.maxY], forKey: key)
    }
    static func restore(_ panel: NSPanel) -> Bool {
        guard let p = UserDefaults.standard.dictionary(forKey: key), let name = p["screen"] as? String,
              let x = p["x"] as? Double, let top = p["top"] as? Double,
              let s = NSScreen.screens.first(where: { $0.localizedName == name }) else { return false }
        panel.setFrameOrigin(NSPoint(x: s.frame.minX + x, y: s.frame.maxY - top - panel.frame.height))
        return true
    }
}

// v9 (Marko 14.10.2026: "the whole status line is breathing. So I'm trying to click on the settings icon and it's
// moving"): every item has a FIXED width, sized for its widest text, so changing numbers never move anything; the
// stripe changes width only when its state changes (red, NO OTHER CONNECTION, a message), and keeps its left edge.
let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
    ceil((s as NSString).size(withAttributes: [.font: font]).width) + 6
}

func label(_ width: CGFloat, align: NSTextAlignment = .left, font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)) -> NSTextField {
    let l = NSTextField(labelWithString: "")
    l.font = font
    l.textColor = Ink.text
    l.alignment = align
    l.lineBreakMode = .byTruncatingTail
    l.translatesAutoresizingMaskIntoConstraints = false
    l.widthAnchor.constraint(equalToConstant: width).isActive = true
    l.setContentHuggingPriority(.required, for: .horizontal)
    return l
}

func fixWidth(_ v: NSView, _ width: CGFloat) -> NSLayoutConstraint {
    let c = v.widthAnchor.constraint(equalToConstant: width)
    c.isActive = true
    return c
}

func rate(_ bytesPerSecond: Double) -> String { SpeedUnit.current.format(bytesPerSecond: bytesPerSecond) }

// The widest speed text of the chosen unit: auto never needs more than five places, a fixed unit up to nine.
func speedSample() -> String {
    let u = SpeedUnit.current
    let digits = (u == .autoBits || u == .autoBytes) ? 4 : 9
    let n = String(repeating: "8", count: digits) + " " + String(repeating: "M", count: u.unitWidth)
    return "888\(n)  888\(n)"   // v60: room for the arrows; v51: one number per direction (the test result is in the tooltip)
}

// v12 (Marko 18.10.2026: "you're using too much of my real estate ... remove internet ... just in parentheses. Put the
// test results ... I don't need the time"): the last speedtest.net result in parentheses after each live number, in
// Mbit/s (MB/s when the unit is bytes); "(...)" until this run has tested, "(✗)" for 30 s after one failed.
func testPart(_ mbps: Double?, mark: String?) -> String {
    let inner: String
    if let mark { inner = mark }
    else if let mbps { inner = SpeedUnit.slot(SpeedUnit.current.isBits ? mbps : mbps / 8).trimmingCharacters(in: .whitespaces) }
    else { inner = "—" }
    let t = "(\(inner))"
    return String(repeating: " ", count: max(0, 6 - t.count)) + t
}

// v12 (Marko 18.10.2026: "every Wi-Fi device will be green. Every LAN port hardware port or maybe tethering through
// phone will be yellow"): the connection's name takes the colour of the device the internet goes through.
func isWiFi(_ iface: String?) -> Bool {
    guard let iface else { return false }
    return CWWiFiClient.shared().interfaceNames()?.contains(iface) ?? false
}

func ago(_ d: Date?) -> String {
    guard let d else { return "never" }
    let s = Int(Date().timeIntervalSince(d))
    if s < 60 { return "\(max(s, 0)) s ago" }
    if s < 3600 { return "\(s / 60) min ago" }
    if s < 86400 { return "\(s / 3600) h ago" }
    return "\(s / 86400) d ago"
}

final class Dot: NSView {
    var color = Ink.grey { didSet { needsDisplay = true } }
    override func draw(_ r: NSRect) { color.setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill() }
}

final class Stripe: NSObject {
    let panel: NSPanel
    let dot = Dot()
    let led = Dot()                             // v36, request 53: the one LED, internet green / red (MenuBar.swift)
    var menuItem: NSStatusItem?
    var lastMenuSpeed: (Double?, Double?) = (nil, nil)
    var lastMenuUp: Bool?
    let connButton = NSButton(title: "…", target: nil, action: nil)
    let speed = label(textWidth(speedSample(), monoFont), font: monoFont)
    var speedWidth: NSLayoutConstraint!
    var connWidth: NSLayoutConstraint!
    let ping = NSButton(title: "ping —", target: nil, action: nil)
    let data = NSButton(title: "data —", target: nil, action: nil)   // v8: the Telemach balance; a click asks now
    var dataBusy = false
    var lastTest = WebSpeed.load()              // v11/v12: the last speedtest.net result, in parentheses beside the speed
    var testMark: String?                       // "..." until tested, "✗" after a failure
    var webBusy = false
    var webHeld = Date.distantPast
    var dataHeld = Date.distantPast             // a failed check's words stay until then
    let checked = label(Stripe.checkedNormal)
    let failover = label(Stripe.failoverNormal)
    static let checkedNormal = textWidth("checked 59 min ago ✓", .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
    static let failoverNormal = textWidth("failover 59 min ago", .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
    let ok = NSButton(title: "OK", target: nil, action: nil)
    let gear = NSButton(title: "⚙", target: nil, action: nil)
    let rescan = NSButton(title: "⟳", target: nil, action: nil)   // v32, request 49: find every line again, now
    let lights = TrafficLights()                // v49, request 70: the standard red / yellow / green, on the left (Lights.swift)
    // v49 (request 69): WI-FI · CABLE · BOTH ticks on the top row (Choose.swift), the dead lines (Health.swift), the signal (Signal.swift)
    lazy var wifiTick = makeTick(#selector(tickWifi), id: "tick-wifi")
    lazy var cableTick = makeTick(#selector(tickCable), id: "tick-cable")
    lazy var bothTick = makeTick(#selector(tickBoth), id: "tick-both")
    lazy var wifiLabel = word("WI-FI", Ink.text, #selector(openWifiList), id: "choose-wifi", tip: "Tick: the Mac on its Wi-Fi (first in the service order, the cable second). Click the word: the Wi-Fi networks in range, tick the one to use.")
    lazy var cableLabel = word("CABLE", Ink.text, #selector(openCableList), id: "choose-cable", tip: "Tick: the cable first. Click the word: the wired interfaces and phones, tick the ones to use.")
    lazy var bothLabel = word("BOTH", Ink.text, #selector(tickBoth), id: "choose-both", tip: "Tick: aggregation over the ticked lines (the Wi-Fi in use and the ticked cables).")
    lazy var cloudWord = word("", Ink.green, #selector(cloudPressed), id: "claude-cloud", tip: "Watches Claude Code's connection to Anthropic")
    lazy var tsWord = word("", Ink.grey, #selector(tsPressed), id: "tailscale", tip: "Tailscale")
    lazy var tabAll = word("ALL", Ink.grey, #selector(pickTabAll), id: "tab-all", tip: "Every connection the Mac can see: Wi-Fi networks in range, cables, phones, each with its state and signal")
    lazy var tabUse = word("IN USE", Ink.green, #selector(pickTabUse), id: "tab-inuse", tip: "Only the lines carrying traffic now, with their signal and live speed")
    var tab = UserDefaults.standard.string(forKey: "linesTab") ?? "inuse"
    // v60 (request 80): the filters of ALL, "" / "lan" / "wifi"; the LAN and Wi-Fi icons beside ALL, grey off, green on
    var allFilter = UserDefaults.standard.string(forKey: "allFilter") ?? ""
    lazy var lanFilter = word("LAN", Ink.grey, #selector(pickLanFilter), id: "filter-lan", tip: "In ALL: only the wired connections (cables, phones over USB). Again: every connection")
    lazy var wifiFilter = word("WI-FI", Ink.grey, #selector(pickWifiFilter), id: "filter-wifi", tip: "In ALL: only the Wi-Fi networks. Again: every connection")
    // v60 (request 82): H, the help: an infographic of the stripe in the app's own browser
    lazy var helpWord = word("H", Ink.text, #selector(helpPressed), id: "help", tip: "Help: what every part of the stripe does, as a picture (opens and closes)")
    var allRows: [String: LineRow] = [:]
    lazy var wifiNoData = noDataLabel()
    lazy var cableNoData = noDataLabel()
    let ruleChecks = Rule()
    var deadIfaces = Set<String>()
    var probeState: [String: ProbeState] = [:]
    var probing = false
    var zoomPrev: (scale: CGFloat, x: CGFloat)?
    var phoneSampling = false
    var menuPlaceLogged = false
    var signalTick = 0
    var wifiScan: [String] = []
    var wifiScanAt = Date.distantPast
    let grip = Grip()                           // v27, request 45: two vertical lines on the right, dragged to resize
    let permissions = NSButton(title: "PERMISSIONS", target: nil, action: nil)   // v38: shown only while one is missing
    // v39 (request 56): ON OFF after the minimize circle, TOP before the LED (OnOff.swift)
    lazy var onWord = word("ON", Ink.green, #selector(noop), id: "on", tip: "The app is on (it runs)")
    lazy var offWord = word("OFF", Ink.grey, #selector(switchOff), id: "off",
        tip: "Off: the aggregation, the tunnel, the proxy, the keeper and the phones' helper stopped, nothing of the app left between the Mac and the internet; then the app quits. The Wi-Fi radios stay as they are.")
    lazy var topWord = word("TOP", OnTop.on ? Ink.green : Ink.grey, #selector(toggleTop), id: "top", tip: "Always on top: green, the stripe stays above every other window")
    // v43 (requests 58, 59): MAC AGGREGATE BOTH (Route.swift), TEST SPEED TEST HEALTH (Tests.swift), the downloads (Downloads.swift)
    lazy var macWord = word("MAC", Ink.grey, #selector(pickMac), id: "route-mac", tip: "MAC: the Mac on its own connection (its Wi-Fi or cable), the aggregation off")
    lazy var aggWord = word("AGGREGATE", Ink.grey, #selector(pickAggregateRoute), id: "route-aggregate", tip: "AGGREGATE: everything through the joined lines; the Mac's own Wi-Fi never used, even when they stumble")
    lazy var bothWord = word("BOTH", Ink.grey, #selector(pickBoth), id: "route-both", tip: "BOTH: through the joined lines; when they stop carrying traffic the Mac's own connection takes over within seconds, and gives back when they work again")
    lazy var testWord: NSTextField = { let t = NSTextField(labelWithString: "TEST:"); t.font = .monospacedSystemFont(ofSize: 12, weight: .bold); t.textColor = Ink.dim; t.setContentHuggingPriority(.required, for: .horizontal); return t }()
    lazy var testSpeedWord = word("SPEED", Ink.text, #selector(testSpeedPressed), id: "test-speed", tip: "speedtest.net in the app's own browser window, ads blocked by uBlock Origin's lists")
    lazy var testHealthWord = word("HEALTH", Ink.text, #selector(testHealthPressed), id: "test-health", tip: "Every line at once: ping, jitter, loss, HTTPS times, public address, the phones' radio, in a report window (10 s, almost no data)")
    let dlBox = NSStackView()
    let ruleLines = Rule(), ruleStatus = Rule()      // v44 (request 62): under the first row, above the status lines
    var downloadIDs: [String] = []
    var downloadTick = 0
    var radioStates: [String: (fiveG: Bool?, shown: String, slot: Int)] = [:]
    var radioReading = false
    var wiresBusy = false
    var sharing: Set<String> = []        // v34: the lines whose Wi-Fi share is switching
    var minimizedFrame: NSRect?
    var failoverWidth: NSLayoutConstraint!
    var checkedPipe: NSTextField!
    var failoverPipe: NSTextField!
    var checkedWidth: NSLayoutConstraint!
    var pingWidth: NSLayoutConstraint!, dataWidth: NSLayoutConstraint!   // v26: every field as wide as its text now
    var scale = CGFloat(UserDefaults.standard.double(forKey: "stripeScale")).clamped(0.5, 3, or: 1)   // v26: resizable
    var resizingByHand = false
    // v59 (request 79, Marko 14.11.2026: "Before actually changing the font size, you need to first remove the gap between
    // the text"): the grip first closes the gaps (the stacks' spacing and side margins, 1 = as built, 0 = none), and only
    // with no gap left does the scale (the letters) go smaller; wider: the gaps come back first, then the letters grow.
    var gap = Swift.min(Swift.max(CGFloat(UserDefaults.standard.object(forKey: "stripeGap") as? Double ?? 1), 0), 1)
    var gapBase: [ObjectIdentifier: (spacing: CGFloat, left: CGFloat, right: CGFloat)] = [:]
    var noOther = false                         // the keeper says NO OTHER CONNECTION: the status is red
    var red = false                             // the failover alert is on: every word is red

    var iface: String?
    var lastCounters: (rx: UInt64, tx: UInt64)?
    var sampling = false
    var lastSample = Date()
    var tick = 0
    var state: KeeperState?
    var settings: SettingsWindow?
    var here: String?
    var pingHeld = Date.distantPast             // the answer of a pressed ping stays on the stripe until then
    // v13 (requests 27, 28): a row per other connection and the aggregation row (Lines.swift)
    var lineRows: [String: LineRow] = [:]
    var aggRow: LineRow!
    var others: [OtherLine] = []
    let expand = NSButton(title: "▸", target: nil, action: nil)   // v23, request 41: opens the rows under the one line
    var expanded = true                         // v54: the rows are always there; the tabs ALL / IN USE choose which
    var seen = SeenLines.load()                 // v22, request 40: the lines once connected (grey when gone)
    var agg: AggStatus?
    var aggMainLast: (rx: UInt64, tx: UInt64)?
    var scanning = false
    var serverMisses = 0
    var proxyDropped = false
    var lineTesting = Set<String>()             // request 30: the rows being tested now ("JOINED" for all)

    override init() {
        // v73 (request 86): a normal titled window: the system's traffic lights, minimize to the Dock, moved by the title bar
        panel = StripeWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 30),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Connection Keeper"
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = false
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        applyOnTop()
        NotificationCenter.default.addObserver(forName: OnTop.changed, object: nil, queue: .main) { [weak self] _ in self?.applyOnTop(); self?.showTop() }
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = Ink.ground
        panel.isOpaque = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let root = FlippedView()          // v26: scaled from the top-left corner (resizable)
        root.wantsLayer = true
        root.layer?.backgroundColor = Ink.ground.cgColor
        root.layer?.cornerRadius = 8
        panel.contentView = root

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 12).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 12).isActive = true

        for b in [connButton, gear] {
            b.isBordered = false
            b.target = self
            b.font = .systemFont(ofSize: 12, weight: .semibold)
            b.contentTintColor = Ink.text
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        connButton.action = #selector(showConnections)
        connButton.alignment = .left
        connButton.toolTip = "Switch the connection"
        ping.isBordered = false
        ping.target = self
        ping.action = #selector(pingNow)
        ping.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ping.contentTintColor = Ink.yellow
        ping.alignment = .left
        ping.translatesAutoresizingMaskIntoConstraints = false
        ping.toolTip = "Press: ping now and say on the stripe whether the internet is alive"
        data.isBordered = false
        data.target = self
        data.action = #selector(checkDataByHand)
        data.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        data.contentTintColor = Ink.text
        data.alignment = .left
        data.translatesAutoresizingMaskIntoConstraints = false
        data.setContentHuggingPriority(.required, for: .horizontal)
        dataWidth = fixWidth(data, textWidth("888.8 GB", monoFont))
        // "When I click on download speed, it tests download speed" (request 16): the live speed starts the test too
        speed.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(testSpeedByHand)))
        speed.maximumNumberOfLines = 1
        speed.cell?.wraps = false
        speed.lineBreakMode = .byClipping
        speed.toolTip = speedTip()
        data.font = monoFont
        ping.font = monoFont
        pingWidth = fixWidth(ping, textWidth("ping 999 ms", monoFont))
        speedWidth = speed.constraints.first { $0.firstAttribute == .width }
        connWidth = fixWidth(connButton, connectionWidth())
        NotificationCenter.default.addObserver(forName: SpeedUnit.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.speedWidth.constant = textWidth(speedSample(), monoFont)
            self.lastCounters = nil
            self.fit()
        }
        // OK: Marko has seen that the first connection died. A click on the red failover words does the same.
        ok.bezelStyle = .rounded
        ok.controlSize = .small
        ok.font = .systemFont(ofSize: 11, weight: .bold)
        ok.target = self
        ok.action = #selector(acknowledge)
        ok.toolTip = "I have seen it: back to the normal colours"
        ok.translatesAutoresizingMaskIntoConstraints = false
        ok.isHidden = true
        failover.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(acknowledge)))
        failoverWidth = failover.constraints.first { $0.firstAttribute == .width }
        checkedWidth = checked.constraints.first { $0.firstAttribute == .width }
        gear.action = #selector(gearMenu)        // v25: the menu holds WIRES / WI-FI and Settings
        gear.font = .systemFont(ofSize: 15)
        gear.toolTip = "WIRES or WI-FI, and Settings"
        // v32 (request 49: "I want to have some kind of refresh or push button"): ⟳ beside ⚙
        rescan.isBordered = false
        rescan.target = self
        rescan.action = #selector(rescanNow)
        rescan.font = .systemFont(ofSize: 14, weight: .semibold)
        rescan.contentTintColor = Ink.text
        rescan.setContentHuggingPriority(.required, for: .horizontal)
        rescan.toolTip = "RESCAN: find every device and phone again (a phone just plugged in), check every line, join the new ones"

        // v7 (Marko 14.10.2026: "reduce the space between the text and just put pipes in between"): the items sit
        // close, a dim pipe between them, and the stripe is as wide as its words.
        func pipe() -> NSTextField {
            let p = NSTextField(labelWithString: "|")
            p.textColor = Ink.grey
            p.font = .systemFont(ofSize: 12)
            p.setContentHuggingPriority(.required, for: .horizontal)
            return p
        }
        checkedPipe = pipe()
        failoverPipe = pipe()
        for b in [connButton, ping, gear] { b.setContentHuggingPriority(.required, for: .horizontal) }
        // v12 (Marko 18.10.2026: "I don't need text checked two minutes ago ... reduce as much as possible size of this
        // banner by reducing spaces"): "checked … ago" and "failover … ago" are gone from the normal stripe; the status
        // place shows only when it has something to say (NO OTHER CONNECTION, a ping answer, a switch), the failover
        // place only in the red alert. Closer items, smaller margins.
        // v27 (request 45: "On the left side, make a minimize button which looks exactly as minimize button from the
        // macOS ... align that button with the rest of the text"): the yellow circle, "−" on it while the mouse is over
        wireLights()
        for (w, l) in [(lanFilter, "LAN filter"), (wifiFilter, "Wi-Fi filter"), (helpWord, "Help")] { w.setAccessibilityLabel(l) }
        for (w, sym) in [(testSpeedWord, "speedometer"), (testHealthWord, "waveform.path.ecg"), (helpWord, "questionmark.circle"), (lanFilter, "cable.connector.horizontal"), (wifiFilter, "wifi"), (cloudWord, "cloud.fill"), (tsWord, "point.3.connected.trianglepath.dotted")] {
            w.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil); w.title = w.image == nil ? "TS" : ""; w.imagePosition = .imageOnly
        }
        // v27 ("On the right side, put the two vertical lines, which I'm dragging and resizing"): the grip scales the stripe
        grip.onDrag = { [weak self] w in self?.resize(toWidth: w) }
        grip.startWidth = { [weak self] in self?.panel.frame.width ?? 0 }
        grip.toolTip = "Drag left or right: the stripe smaller or bigger"
        // v23 (request 41: "Put only Aggregate Connection with a small arrow. I can open and see what is aggregated ...
        // The whole status line is basically one line"): ▸ opens the rows of the lines under it, ▾ closes them.
        expand.isBordered = false
        expand.target = self
        expand.action = #selector(toggleExpand)
        expand.font = .systemFont(ofSize: 13, weight: .bold)
        expand.contentTintColor = Ink.text
        expand.setContentHuggingPriority(.required, for: .horizontal)
        expand.toolTip = "Open: see the lines (green connected, red here but not connected, grey gone)"
        // v28 (request 46: "Remove the LED next to the minimize circle"): no dot; its warning colours the word instead
        // v38 (Marko, 30.10.2026: "If permissions are not set, it needs to have text in the top right: Permissions"):
        // the word at the right end of the stripe, amber, while a permission is missing; a click opens its page
        permissions.isBordered = false
        permissions.target = self
        permissions.action = #selector(openPermissions)
        permissions.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        permissions.contentTintColor = NSColor(calibratedRed: 0xE8/255, green: 0xA3/255, blue: 0x3D/255, alpha: 1)
        permissions.setContentHuggingPriority(.required, for: .horizontal)
        permissions.toolTip = "A permission is off (Accessibility: joining a Wi-Fi through Control Centre; Location: the Wi-Fi signal reading). This opens its page in System Settings"
        permissions.isHidden = Permissions.missing.isEmpty
        let row = NSStackView(views: [onWord, offWord, pipe(), gear, rescan, connButton, pipe(), speed, pipe(), ping, pipe(), data, checkedPipe, checked, failoverPipe, failover, ok, testSpeedWord, testHealthWord, helpWord, topWord, led, permissions])
        row.orientation = .horizontal
        row.spacing = 3
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        // v13: the rows stand in a column, the first row on top, the aggregation row last (Lines.swift).
        aggRow = LineRow(leadWidth: onWord.fittingSize.width + offWord.fittingSize.width + pipe().fittingSize.width + 12 + gear.fittingSize.width + rescan.fittingSize.width + 6, nameWidth: connectionWidth())
        aggRow.dot.isHidden = true
        aggRow.name.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleMode)))
        aggRow.speed.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(testRowSpeed(_:))))
        aggRow.speed.toolTip = "All joined lines' live speed added.\nClick: test every line alone, then all joined, to compare (about 40 s)."
        dlBox.orientation = .vertical
        dlBox.alignment = .leading
        dlBox.spacing = 0
        dlBox.isHidden = true
        let checkRow = NSStackView(views: [lights, wifiTick, wifiLabel, wifiNoData, pipe(), cableTick, cableLabel, cableNoData, pipe(), bothTick, bothLabel, cloudWord, tsWord])
        checkRow.orientation = .horizontal
        checkRow.spacing = 3
        checkRow.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        checkRow.translatesAutoresizingMaskIntoConstraints = false
        checkRow.heightAnchor.constraint(equalToConstant: 22).isActive = true
        aggRow.sigBox.alphaValue = 0
        let spacerL = NSView(), spacerR = NSView()
        for sp in [spacerL, spacerR] { sp.translatesAutoresizingMaskIntoConstraints = false; sp.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        let tabRow = NSStackView(views: [spacerL, lanFilter, wifiFilter, tabAll, tabUse, spacerR])
        spacerL.widthAnchor.constraint(equalTo: spacerR.widthAnchor).isActive = true      // only after both are in tabRow (v55: before it crashed at launch)
        tabRow.orientation = .horizontal; tabRow.spacing = 18
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabRow.heightAnchor.constraint(equalToConstant: 20).isActive = true
        showTabs()
        let column = NSStackView(views: [checkRow, ruleChecks, row, ruleLines, tabRow, aggRow.view, ruleStatus, dlBox])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 20)   // the right 20 points: the grip
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        tabRow.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -16).isActive = true
        for r in [ruleChecks, ruleLines, ruleStatus] { r.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -16).isActive = true }
        column.setCustomSpacing(3, after: checkRow); column.setCustomSpacing(3, after: ruleChecks); column.setCustomSpacing(3, after: row); column.setCustomSpacing(3, after: ruleLines)
        column.setCustomSpacing(3, after: aggRow.view); column.setCustomSpacing(3, after: ruleStatus)
        Hover.watchPresses()
        // the grip at the right end of the column (the column, not the root: the root's own edge is the unscaled one)
        grip.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grip)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            grip.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -5),
            grip.centerYAnchor.constraint(equalTo: checkRow.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 10),
            grip.heightAnchor.constraint(equalToConstant: 18),
        ])
        panel.setContentSize(column.fittingSize)

        if !StripePlace.restore(panel) && panel.setFrameUsingName("ConnectionKeeperStripe") { StripePlace.save(panel) }   // the v12 place, once
        else if !StripePlace.restore(panel), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 10))
        }
        keepOnScreen()
        // Every move by his hand is remembered at once (request 31); moves the stripe makes itself keep the top-left.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, self.minimizedFrame == nil else { return }
            StripePlace.save(self.panel)
        }
        panel.orderFrontRegardless()
        setUpMenuBar()                    // v36: the icon with the speeds; hides the stripe again if he left it hidden

        showData()
        showWebSpeed()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        // v38: the permissions read again every 2 s; the stripe changes only when they changed
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let hide = Permissions.missing.isEmpty
            if hide != self.permissions.isHidden { self.permissions.isHidden = hide; self.fit() }
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.autoData(); self?.newDay(); loadAgents(); if Wires.on { DispatchQueue.global().async { Wires.refreshShares() } } }
        loadAgents()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.scanLines() }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.readRadios() }
        startSignals(); startHealth(); refreshWifiScan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.readRadios() }
        layoutLines()
        scanLines()
        // At every start, behind the scenes (request 17): the data left, then the speed test, one after the other so
        // the two Firefoxes never share the 4G line's measurement.
        // v12 (Marko 18.10.2026: "you need to do all the tests ... Also ping as soon as application start ... three dots
        // inside parenthesis" for what is not tested yet): at once the ping, the data, then the speed; until each answers
        // its place says (...).
        testMark = "..."
        setSpeed(nil, nil)
        pingNow()
        // v43 (request 61, Marko 1.11.2026: "at the starting of the app, you need to do a speed test, and that speed test is
        // displayed in the status line at the bottom"): ck-net's quick test of all lines together (about 150 MB) replaces
        // speedtest.net at start; it waits 20 s for the lines to be found. A click on the speed still opens speedtest.net.
        checkData(visible: false) {}
        ClaudeDrops.start()      // v46 (request 65): Claude Code's drops followed while the app runs
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.startSpeedTest() }
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.restoreStripe() }
        }
        NotificationCenter.default.addObserver(forName: DataBalanceNote.checkNow, object: nil, queue: .main) { [weak self] _ in self?.checkDataByHand() }
        // v32: ⟳ pressed from outside too (a terminal, a script): the distributed notification "ConnectionKeeperRescan"
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("ConnectionKeeperRescan"), object: nil, queue: .main) { [weak self] _ in self?.rescanNow() }
    }

    // THE DATA BALANCE (v8): the last answer, "28.6 GB left · 11:57" (GB with one decimal, the time from Telemach's SMS);
    // amber below 10 GB, red below 2 GB.
    func showData() {
        if dataBusy || Date() < dataHeld { return }
        if let b = DataBalance.load() {
            data.title = b.line.replacingOccurrences(of: " left", with: "")
            data.contentTintColor = red ? Ink.red : b.color
            data.toolTip = b.tip
        } else {
            data.title = "data ?"
            data.contentTintColor = red ? Ink.red : Ink.dim
            data.toolTip = "Click: ask Telemach how much data is left (sends STANJE to 13880 through the router, one SMS)."
        }
        fit()
    }

    // A click on the item, ⚙ → Check data, or the timer: the command runs behind the scenes, the stripe never waits.
    @objc func checkDataByHand() { checkData(visible: true) }

    func checkData(visible: Bool, then: (() -> Void)? = nil) {
        if dataBusy { then?(); return }
        dataBusy = true
        data.title = "(...) GB"
        data.contentTintColor = Ink.amber
        fit()
        let t0 = Date()
        appendLog("\(logStamp()) DATA balance asked: router-sms balance (STANJE to 13880)\(visible ? " in front of him" : " behind the scenes")")
        DispatchQueue.global().async {
            let r = DataBalance.check(visible: visible)
            DispatchQueue.main.async {
                self.dataBusy = false
                let secs = Date().timeIntervalSince(t0)
                switch r {
                case .success(let b):
                    appendLog(String(format: "%@ DATA %.2f MB left of %.2f MB (used %.2f) at %@ (%.1f s from the click)",
                                     logStamp(), b.left_mb, b.total_mb, b.used_mb, b.at, secs))
                    self.showData()
                case .failure(let e):
                    appendLog("\(logStamp()) DATA balance FAILED: \(e.localizedDescription)")
                    self.dataHeld = Date().addingTimeInterval(30)
                    self.data.title = "data ✗"
                    self.data.contentTintColor = Ink.red
                    self.data.toolTip = e.localizedDescription
                    self.fit()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30.5) { self.showData() }
                }
                then?()
            }
        }
    }

    // THE SPEED TEST (v11): the last speedtest.net result beside the live speed; a click tests in front of him.
    // v12 (Marko 18.10.2026: "I don't need arrows ... Green number means download, red number means upload"): no
    // arrows, the download half green, the upload half red; all red in the failover alert as every other word.
    func setSpeed(_ down: Double?, _ up: Double?) {
        let dash = String(repeating: " ", count: max(0, rate(0).count - 1)) + "—"
        let d = down.map(rate) ?? dash
        let u = up.map(rate) ?? dash
        speed.attributedStringValue = speedWithArrows(d, u, red ? Ink.red : Ink.green, Ink.red)   // v60: arrows back (request 81)
        showMenuBarSpeed(down, up)
    }

    func speedTip() -> String {
        "Internet only: the bytes through the router to the internet (the default route), per second. Traffic inside the local network is not counted.\n"
            + "Green: download, red: upload. In parentheses: the last speedtest.net result, \(SpeedUnit.current.isBits ? "Mbit/s" : "MB/s")"
            + (lastTest.map { String(format: " (%.2f ↓ %.2f ↑ Mbit/s, ping %.0f ms)", $0.down_mbps, $0.up_mbps, $0.ping_ms ?? 0) } ?? "")
            + ".\nClick: test on speedtest.net in a Firefox window you watch."
    }

    func showWebSpeed() {
        if webBusy || Date() < webHeld { return }
        testMark = nil
        lastTest = WebSpeed.load()
        speed.toolTip = speedTip()
    }

    @objc func testSpeedByHand() { testSpeed(visible: true) }

    func testSpeed(visible: Bool) {
        if webBusy { return }
        webBusy = true
        testMark = "..."
        appendLog("\(logStamp()) SPEEDTEST asked\(visible ? " in front of him" : " behind the scenes")")
        DispatchQueue.global().async {
            let r = WebSpeed.run(visible: visible)
            let on = Net.defaultRouteInterface().map(Net.displayName)   // the connection it was measured on
            DispatchQueue.main.async {
                self.webBusy = false
                switch r {
                case .success(let w):
                    if let on { WebSpeedByConnection.record(w, on: on) }
                    self.showWebSpeed()
                case .failure(let e):
                    appendLog("\(logStamp()) SPEEDTEST FAILED: \(e.localizedDescription)")
                    self.webHeld = Date().addingTimeInterval(30)
                    self.testMark = "✗"
                    self.speed.toolTip = "The speed test failed: \(e.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30.5) { self.showWebSpeed() }
                }
            }
        }
    }

    // "I need to have the values for this day": past midnight, both again behind the scenes (once: a failure waits
    // for the next start or a click, so a dead line never sends SMS after SMS).
    var dayTried = ""
    func newDay() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        if dayTried == "" { dayTried = today; return }          // the start already asked
        guard dayTried != today else { return }
        dayTried = today
        let needData = !isToday(DataBalance.load()?.checked), needSpeed = !isToday(WebSpeed.load()?.at)
        if needData { checkData(visible: false) { if needSpeed { self.testSpeed(visible: false) } } }
        else if needSpeed { testSpeed(visible: false) }
    }

    func autoData() {
        let h = DataAuto.hours
        guard h > 0, !dataBusy else { return }
        let last = (try? DataBalance.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if Date().timeIntervalSince(last) >= Double(h) * 3600 { checkData(visible: false) }
    }

    // On top: above ordinary and floating windows. Off: an ordinary window.
    // v48 (request 68, Marko 1.11.2026: "make my application not follow me everywhere. If it's open on one screen, it
    // needs to stay there ... When I switch desktops, monitors, it's following me all around"): no .canJoinAllSpaces
    // any more, which put it on every desktop of every display. It stays on the desktop and the display where it is;
    // only a click on its menu bar icon brings it to where he is (menuBarClicked, .moveToActiveSpace for that moment).
    func applyOnTop() {
        if OnTop.on {
            panel.level = .floating
            panel.collectionBehavior = [.managed, .fullScreenAuxiliary]
            if !MenuBarPrefs.stripeHidden { panel.orderFrontRegardless() }
        } else {
            panel.level = .normal
            panel.collectionBehavior = [.managed]
        }
    }

    func refresh() {
        reading()
        showDownloads()
        showRoute()
        showChoice()
        if tick % 5 == 0 { showCloud(); showTailscale() }
        applyAlert()
        showLed()
        // v28: the dot is gone from the stripe; when it would have been red or amber the name says it in that colour
        if !red && !noOther && (dot.color == Ink.red || dot.color == Ink.amber) { connButton.contentTintColor = dot.color }
        fit()
    }

    // THE RED (Marko, 14.10.2026): after the keeper failed over by itself, every word on the stripe is red
    // and the failover field says which connection died and when, until OK or until the Mac is back on it.
    func applyAlert() {
        var alert = FailoverAlert.load()
        if let a = alert, !a.simulated {
            let alive = state?.isFresh ?? false
            let current = alive ? state?.current : here
            if current == a.from, !alive || (state?.healthy ?? false) {
                FailoverAlert.clear(); alert = nil
                appendLog("\(logStamp()) ALERT cleared by the stripe: back on \"\(a.from)\"")
            }
        }
        guard let a = alert else {
            if red {
                red = false
                for b in [connButton, gear, rescan] { b.contentTintColor = Ink.text }
                if Date() >= pingHeld { ping.contentTintColor = Ink.yellow }
                speed.textColor = Ink.text; failover.textColor = Ink.text; failover.font = speed.font
                ok.isHidden = true
                showData()
                failoverWidth.constant = Stripe.failoverNormal
                fit()
                reading()
            }
            return
        }
        if !red {
            red = true
            ok.isHidden = false
            failoverWidth.constant = 260
            fit()
        }
        for b in [connButton, ping, data, gear, rescan] { b.contentTintColor = Ink.red }
        for l in [speed, checked, failover] { l.textColor = Ink.red }
        failover.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        failover.stringValue = a.line
        failover.toolTip = "\(a.from) stopped answering at \(a.at.formatted(date: .abbreviated, time: .shortened)); " +
            "the keeper moved to \(a.to) (\(a.how)). Check what is wrong with \(a.from). Press OK when you have seen it." +
            (a.simulated ? "  [test]" : "")
        dot.color = Ink.red
    }

    @objc func acknowledge() {
        guard let a = FailoverAlert.load() else { return }
        FailoverAlert.clear()
        appendLog("\(logStamp()) ALERT acknowledged on the stripe (OK): \(a.line)")
        applyAlert()
    }

    // MINIMIZE (v13, Marko 18.10.2026: "when I switch to it with ... command tab, it should come up, it should not stay on
    // the dock ... coming back to [the] position"): no Dock miniaturizing. The stripe is taken off the screen and the
    // app becomes an ordinary one only while hidden, so Command-Tab and the Dock know it; the moment it is switched to,
    // the stripe is back where it was and the app leaves the Dock and Command-Tab again.
    @objc func openPermissions() { Permissions.openMissing() }
    @objc func noop() {}

    @objc func minimizeStripe() {
        // v36: the stripe goes to the menu bar icon; a click on the icon brings it back
        MenuBarPrefs.stripeHidden = true
        panel.orderOut(nil)
        appendLog("\(logStamp()) stripe minimized to the menu bar icon")
    }

    func restoreStripe() {
        guard let f = minimizedFrame else { return }
        minimizedFrame = nil
        panel.setFrame(f, display: true)
        keepOnScreen()
        applyOnTop()
        panel.orderFrontRegardless()
        appendLog("\(logStamp()) stripe back from minimized")
    }

    // The stripe keeps its left and top edges and takes the size its words and rows need.
    func fit() {
        guard let root = panel.contentView, let column = root.subviews.first else { return }
        Hover.walk(root)
        ruleStatus.isHidden = dlBox.isHidden || dlBox.arrangedSubviews.isEmpty
        ruleLines.isHidden = lineRows.isEmpty && aggRow.view.isHidden
        let t = checked.stringValue
        let quiet = t.isEmpty || t.hasPrefix("checked ") || t == "keeper not running"
        checked.isHidden = false; checkedPipe.isHidden = false          // v29: the status slot keeps its place
        checked.alphaValue = quiet ? 0 : 1
        if failover.isHidden == red { failover.isHidden = !red; failoverPipe.isHidden = !red }
        tighten()
        applyGap(gap, in: column)
        column.layoutSubtreeIfNeeded()
        let natural = column.fittingSize
        // v26 (request 44: "make this user interface resizable"): the stripe is drawn at `scale`; dragging an edge
        // changes the scale, so the words grow or shrink with it and are never cut
        let size = NSSize(width: ceil(natural.width * scale), height: ceil(natural.height * scale))
        if root.bounds.size != natural { rescale(root, natural) }
        let now = panel.contentRect(forFrameRect: panel.frame).size      // v73: the window has a title bar
        if abs(size.width - now.width) < 1 && abs(size.height - now.height) < 1 { return }
        let x = panel.frame.minX, top = panel.frame.maxY
        resizingByHand = true
        panel.setContentSize(size)
        rescale(root, natural)
        panel.setFrameOrigin(NSPoint(x: x, y: top - size.height))
        resizingByHand = false
        keepOnScreen()
    }

    // v29 (request 47: "Please make a digital display. Make fixed positions for every number and every letter"): every
    // field has the width of its widest possible words in the monospaced font, whatever it says now, so nothing on the
    // stripe ever moves or changes its size; the slots are as small as those words allow (request 44).
    static let statusSample = "ALIVE ✓ 88:88:88"
    func tighten() {
        func w(_ s: String) -> CGFloat { textWidth(s, monoFont) }
        func set(_ c: NSLayoutConstraint?, _ v: CGFloat) { if let c, abs(c.constant - v) >= 1 { c.constant = v } }
        set(speedWidth, w(speedSample()))
        set(pingWidth, w("ping 999 ms"))
        set(dataWidth, w("888.8 GB"))
        set(checkedWidth, w(Stripe.statusSample))
        if !failover.isHidden { set(failoverWidth, textWidth(failover.stringValue, failover.font ?? monoFont)) }
        for r in Array(lineRows.values) + (aggRow.map { [$0] } ?? []) {
            set(r.speed.constraints.first { $0.firstAttribute == .width }, w(speedSample()))
            set(r.ping.constraints.first { $0.firstAttribute == .width }, w("999 ms"))
            set(r.info.constraints.first { $0.firstAttribute == .width }, w(LineRow.infoSample))
        }
    }

    // The root keeps its natural size in its own coordinates and is drawn into the bigger or smaller window; the layout
    // is done again in those coordinates (without it the rows slid up out of the window at 1.3×).
    func rescale(_ root: NSView, _ natural: NSSize) {
        root.setBoundsOrigin(.zero)
        root.setBoundsSize(natural)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        root.needsDisplay = true
    }

    func applyGap(_ g: CGFloat, in view: NSView) {
        if let st = view as? NSStackView {
            let id = ObjectIdentifier(st)
            if gapBase[id] == nil { gapBase[id] = (st.spacing, st.edgeInsets.left, st.edgeInsets.right) }
            let b = gapBase[id]!
            if abs(st.spacing - b.spacing * g) > 0.05 { st.spacing = b.spacing * g }
            let l = b.left * g, r = b.right * g
            if abs(st.edgeInsets.left - l) > 0.05 || abs(st.edgeInsets.right - r) > 0.05 {
                st.edgeInsets = NSEdgeInsets(top: st.edgeInsets.top, left: l, bottom: st.edgeInsets.bottom, right: r)
            }
        }
        for v in view.subviews { applyGap(g, in: v) }
    }

    func naturalSize(gap g: CGFloat, _ column: NSView) -> NSSize {
        applyGap(g, in: column)
        column.layoutSubtreeIfNeeded()
        return column.fittingSize
    }

    // A drag of the grip (v59): narrower closes the gaps first, then the letters shrink; wider opens the gaps first, then
    // the letters grow. The height follows; the left edge stays.
    func resize(toWidth width: CGFloat) {
        guard !resizingByHand, let root = panel.contentView, let column = root.subviews.first else { return }
        let open = naturalSize(gap: 1, column), shut = naturalSize(gap: 0, column)
        guard open.width > 0, shut.width > 0 else { return }
        var g: CGFloat = 1, s: CGFloat = 1
        if width >= open.width { g = 1; s = width / open.width }
        else if width <= shut.width { g = 0; s = width / shut.width }
        else {
            // the gaps' share of the width is linear in g: one step there, one check
            g = (width - shut.width) / (open.width - shut.width)
            let w = naturalSize(gap: g, column).width
            if w > width + 0.5, open.width - shut.width > 0 { g = max(0, g - (w - width) / (open.width - shut.width)) }
        }
        s = s.clamped(0.5, 3, or: 1)
        gap = g; scale = s
        UserDefaults.standard.set(Double(g), forKey: "stripeGap")
        UserDefaults.standard.set(Double(s), forKey: "stripeScale")
        let natural = naturalSize(gap: g, column)
        let top = panel.frame.maxY, x = panel.frame.minX
        resizingByHand = true
        panel.setContentSize(NSSize(width: ceil(natural.width * s), height: ceil(natural.height * s)))
        rescale(root, natural)
        panel.setFrameOrigin(NSPoint(x: x, y: top - panel.frame.height))
        resizingByHand = false
    }

    // Never lost off the screens (14.10.2026 the saved place was x = -2247, on no display: the stripe was invisible).
    // At least 80 points of it stay on some screen, otherwise it goes to the top middle of the main screen.
    // v13 (request 31): a stripe that is partly off its display is nudged back inside THAT display (its whole frame, the
    // menu bar strip included: he puts it at the very top of the Mac's display); only a stripe on no display at all goes
    // to the main one. Before, a top edge 1 point into the menu bar strip sent it to the BenQ (four times on 18.10.2026).
    func keepOnScreen() {
        let f = panel.frame
        if let s = NSScreen.screens.max(by: { $0.frame.intersection(f).width * $0.frame.intersection(f).height < $1.frame.intersection(f).width * $1.frame.intersection(f).height }),
           !s.frame.intersection(f).isNull {
            let r = s.frame
            let x = min(max(f.minX, r.minX), r.maxX - f.width), y = min(max(f.minY, r.minY), r.maxY - f.height)
            if x != f.minX || y != f.minY { panel.setFrameOrigin(NSPoint(x: x, y: y)) }
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.midX - f.width / 2, y: v.maxY - f.height - 10))
        appendLog("\(logStamp()) stripe was off every screen (x \(Int(f.minX)), y \(Int(f.minY))); brought back to \(screen.localizedName)")
    }

    func reading() {
        if tick % 5 == 0 {
            // v14: while the virtual device carries the internet, the first row is mantra_networkaggregate; the real
            // lines (the cable, the Wi-Fi) get rows of their own under it.
            let now = Aggregation.tunnelUp ? Aggregation.tunnelDevice : Net.defaultRouteInterface()
            if now != iface { iface = now; lastCounters = nil }
            if !(state?.isFresh ?? false) { here = currentNow() }
        }
        tick += 1

        // INTERNET speed only (v10): the bytes of the default route through the router, sampled every second off the
        // main thread. Traffic inside the house (the phone, the router's page, AirPlay) is not counted.
        if let iface, !sampling {
            sampling = true
            DispatchQueue.global().async {
                let all = Traffic.internetAll()
                let c = all?[iface]
                DispatchQueue.main.async {
                    self.sampling = false
                    let dt = Date().timeIntervalSince(self.lastSample)
                    if let all { self.sampleLines(all, dt: dt) }
                    if iface == Aggregation.tunnelDevice || (Aggregation.on && self.agg != nil) { self.lastSample = Date(); return }   // set from the lines
                    guard let c else { self.setSpeed(nil, nil); self.lastCounters = nil; return }
                    if let last = self.lastCounters, dt > 0 {
                        // a route made again (network change) starts its counters at 0: show nothing for that second
                        let down = c.rx >= last.rx ? Double(c.rx - last.rx) / dt : 0
                        let up = c.tx >= last.tx ? Double(c.tx - last.tx) / dt : 0
                        self.setSpeed(down, up)
                    }
                    self.lastCounters = c
                    self.lastSample = Date()
                }
            }
        } else if iface == nil {
            setSpeed(nil, nil)
        }

        state = KeeperState.load()
        let alive = state?.isFresh ?? false
        let cfg = Config.load()
        let current = alive ? state?.current : here
        let tunnel = iface == Aggregation.tunnelDevice
        // v23 (request 41): aggregating, the one line says only AGGREGATE CONNECTION; the lines are behind ▸
        let joinedNow = Aggregation.on && agg != nil
        // v25 (request 43: "Just put connection, and that's all ... reduce the size"): the word and only as wide as it is
        connButton.title = joinedNow ? "connection" : (tunnel ? Aggregation.tunnelName : current.map { Net.shown($0, iface) } ?? "no network")
        let w = textWidth(connButton.title, .systemFont(ofSize: 12, weight: .semibold)) + 8
        if abs(connWidth.constant - w) >= 1 { connWidth.constant = w; fit() }
        // request 40: the line carrying the internet is connected, so green (grey when there is none)
        if !red && !noOther {
            let up = agg?.lines.filter(\.alive).count ?? 0
            connButton.contentTintColor = iface == nil ? Ink.grey : joinedNow && up < 2 ? Ink.amber : Ink.green
        }

        if Date() < pingHeld { return }            // a pressed ping's answer is being shown

        if let s = state, alive {
            let check = s.lastCheck
            ping.title = check?.latencyMs.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
            // NO OTHER CONNECTION (Marko, 14.10.2026): the connection is dead and none in the list works.
            // Red and bold on the status line until a connection works again; he has to do something.
            let none = s.phase.hasPrefix(noOtherPrefix)
            if none != noOther {
                noOther = none
                checkedWidth.constant = none ? 520 : Stripe.checkedNormal
                checked.font = .monospacedDigitSystemFont(ofSize: 12, weight: none ? .bold : .regular)
                if !none { checked.toolTip = nil }
                if !red { connButton.contentTintColor = none ? Ink.red : Ink.text }
                fit()
            }
            if none {
                checked.stringValue = s.phase
                checked.textColor = Ink.red
                checked.toolTip = "The connection in use is dead and no other connection in the list works. The keeper keeps trying; check the access points."
            } else if s.phase == "ok" || s.phase == "checking" {
                checked.stringValue = "checked \(ago(check?.at)) \(check?.online == false ? "✗" : "✓")"
                checked.textColor = check?.online == false ? Ink.red : Ink.text
            } else {
                checked.stringValue = s.phase
                checked.textColor = Ink.amber
            }
            failover.stringValue = s.lastFailover == nil ? "no failover" : "failover \(ago(s.lastFailover))"
            failover.toolTip = s.lastFailover == nil ? nil : "\(s.lastFailoverFrom ?? "?") → \(s.lastFailoverTo ?? "?")"
            dot.color = none ? Ink.red : !s.healthy ? (check?.online == false ? Ink.red : Ink.amber) : (s.dryRun || cfg.dryRun ? Ink.amber : Ink.green)
            dot.toolTip = s.dryRun ? "keeper running in dry run: it only logs" : "keeper running, pid \(s.pid)"
        } else {
            ping.title = "ping —"
            checked.stringValue = "keeper not running"
            checked.textColor = Ink.dim
            failover.stringValue = state?.lastFailover == nil ? "no failover" : "failover \(ago(state?.lastFailover))"
            dot.color = Ink.grey
            dot.toolTip = "the keeper (LaunchAgent \(CKAgentLabel)) is not running"
        }
    }

    // The connection's name gets the width of the longest name in the list, so a switch does not move the rest.
    func connectionWidth() -> CGFloat {
        let f = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let names = Config.load().connections.map { $0.name + " (USB)" } + ["no network", Aggregation.tunnelName, "ONE CONNECTION"]
        return (names.map { textWidth($0, f) }.max() ?? 80) + 8   // the rows' names; the first row fits its own word
    }

    func currentNow() -> String? {
        guard let i = iface else { return nil }
        return Net.displayName(i)
    }

    // v12 LIVE (Marko 18.10.2026: "offer only the one which is online now ... Make it live", then "when I confirm what
    // are actually my connection, they need to be greyed out if they are not available"): the drop-down opens with
    // "checking…" and fills itself while open. His Wi-Fi networks (⚙) are always listed: usable when in range (or in use
    // and answering), greyed out when not. Every other device with an address (a cable, a USB adapter, a phone) is
    // pinged through itself: usable when it answers, greyed when not. A Wi-Fi not joined cannot be pinged before
    // joining, so "in range" is the most that can be known of it. The one carrying the internet has the tick.
    @objc func showConnections() {
        // Every row is there from the first moment, saying "checking…", and only its words change when its answer comes:
        // rows added to an open menu were cut and left a blank highlighted bar (18.10.2026).
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 460
        addModeSection(menu)
        let cfg = Config.load()
        let wifi = Net.wifiInterface()
        let active = Net.activeInterfaces().filter { $0 != wifi }
        var rows: [(item: NSMenuItem, kind: String, name: String, dev: String)] = []
        func row(_ name: String, _ kind: String, _ dev: String) {
            let item = NSMenuItem(title: "\(name)   checking…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.target = self
            menu.addItem(item)
            rows.append((item, kind, name, dev))
        }
        for c in cfg.connections where c.kind == "wifi" { row(c.name, "wifi", wifi ?? "") }
        for c in cfg.connections where c.kind == "lan" { row(c.name, "lan", Net.lanDevice(c) ?? "") }
        for i in active where !rows.contains(where: { $0.dev == i && $0.kind == "lan" }) { row(Net.displayName(i), "lan", i) }
        DispatchQueue.global().async {
            let route = Net.defaultRouteInterface()
            let ssid = wifi.flatMap { Net.currentSSID($0) }
            let wifiMs = wifi.flatMap { w in Net.ipAddress(w) != nil ? Net.onlineVia(w, host: cfg.pingHost) : nil }
            let near = Net.wifiInRange()
            var lanMs: [String: Double] = [:]
            for r in rows where r.kind == "lan" && active.contains(r.dev) { lanMs[r.dev] = Net.onlineVia(r.dev, host: cfg.pingHost) }
            let tests = WebSpeedByConnection.all()
            let joinedDevs = Aggregation.on ? Set(Aggregation.status()?.lines.filter(\.alive).map(\.device) ?? []) : []
            RunLoop.main.perform(inModes: [.common]) {
                for r in rows {
                    let live: Bool, ok: Bool, words: String, color: NSColor
                    if r.kind == "wifi" {
                        let inUse = r.name == ssid
                        live = inUse && route == wifi
                        ok = inUse ? wifiMs != nil : near.contains(r.name)
                        words = "Wi-Fi · " + (inUse ? (wifiMs.map { String(format: "ping %3.0f ms", $0) } ?? "joined, no internet")
                                              : near.contains(r.name) ? "in range" : "not in range")
                        color = lineColor(gone: !ok, connected: live || inUse && joinedDevs.contains(r.dev))
                        r.item.action = #selector(self.pick(_:)); r.item.representedObject = r.name
                    } else {
                        let ms = lanMs[r.dev]
                        live = route == r.dev && !r.dev.isEmpty
                        ok = ms != nil
                        words = "cable · " + (ms.map { String(format: "ping %3.0f ms", $0) } ?? (active.contains(r.dev) ? "no internet" : "not plugged in"))
                        color = lineColor(gone: !ok && !active.contains(r.dev), connected: live || joinedDevs.contains(r.dev))
                        r.item.action = #selector(self.pickDevice(_:)); r.item.representedObject = r.dev
                    }
                    // v12 (Marko: "add to live connection in parentheses (LIVE) ... this is clearer"): the one carrying the internet
                    let f = NSFont.menuFont(ofSize: 0)
                    let t = NSMutableAttributedString(string: "\(r.kind == "lan" ? Net.shown(r.name, r.dev) : r.name)\(live ? " (LIVE)" : "")   \(words)",
                                                      attributes: [.foregroundColor: color, .font: f])
                    // the last speed test on this connection: download green, upload red (grey when not available)
                    if let w = tests[r.name] {
                        t.append(NSAttributedString(string: "  · ", attributes: [.foregroundColor: Ink.grey, .font: f]))
                        t.append(NSAttributedString(string: String(format: "%.1f", w.down_mbps), attributes: [.foregroundColor: ok ? Ink.green : Ink.grey, .font: f]))
                        t.append(NSAttributedString(string: String(format: " %.1f Mbit/s", w.up_mbps), attributes: [.foregroundColor: ok ? Ink.red : Ink.grey, .font: f]))
                    }
                    r.item.attributedTitle = t
                    r.item.isEnabled = ok
                    r.item.state = live ? .on : .off
                }
                menu.update()
            }
        }
        addJoinSection(menu)
        menu.addItem(.separator())
        let check = NSMenuItem(title: "Check now", action: #selector(checkNow), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let log = NSMenuItem(title: "Open the log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit (back to the normal connection)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: connButton.bounds.height + 4), in: connButton)
    }

    // THE MANUAL SWITCH (v5, Marko 14.10.2026: "I click on mantra, and then nothing is happening. It's not
    // switching immediately."). The stripe joins at once itself, keeper or not, holds the keeper's checks
    // meanwhile, and says on the status line what is happening and how it ended. A switch by hand never turns
    // the stripe red. Joining goes the road in Join.swift (networksetup, the stored password, Control Centre).
    // v12: a cable, a USB adapter or a phone: its service to the top of the order, the internet goes through it.
    @objc func pickDevice(_ item: NSMenuItem) {
        guard let iface = item.representedObject as? String else { return }
        let name = Net.displayName(iface)
        let r = Net.prefer(iface)
        appendLog("\(logStamp()) MANUAL switch to \(name) (\(iface)) from the stripe: " + (r.ok ? "done, \(r.detail)" : "FAILED: \(r.detail)"))
        show(r.ok ? "on \(name) ✓" : "✗ \(name): \(r.detail)", r.ok ? Ink.green : Ink.red, for: 20)
        lastCounters = nil
        if state?.isFresh ?? false { KeeperCommand(action: "check").send() }
    }

    @objc func pick(_ item: NSMenuItem) {
        guard let name = item.representedObject as? String else { return }
        if Config.load().dryRun { show("dry run: would join \(name)", Ink.amber, for: 20); return }
        let iface = Net.wifiInterface() ?? "en0"
        Net.prefer(iface)                                   // v12: Wi-Fi above a cable, so the internet follows the pick
        if Net.currentSSID(iface) == name {
            appendLog("\(logStamp()) MANUAL switch to \"\(name)\": already joined, Wi-Fi now first")
            show("on \(name) ✓", Ink.green, for: 20); return
        }
        show("switching to \(name)…", Ink.amber, for: 180)
        dot.color = Ink.amber
        appendLog("\(logStamp()) MANUAL switch to \"\(name)\" from the stripe: joining now")
        Speed.hold(true)
        DispatchQueue.global().async {
            let r = Join.wifi(name, iface) { msg in DispatchQueue.main.async { self.show(msg, Ink.amber, for: 180) } }
            Speed.hold(false)
            appendLog("\(logStamp()) MANUAL switch to \"\(name)\" " + (r.ok ? "done: \(r.detail)" : "FAILED: \(r.detail)"))
            DispatchQueue.main.async {
                let at = Date().formatted(date: .omitted, time: .shortened)
                if r.ok {
                    self.show("on \(name) ✓  \(at)", Ink.green, for: 20)
                    self.dot.color = Ink.green
                } else {
                    let why = r.detail.contains("Could not find network") ? "not in range"
                        : r.detail.contains("no password stored") ? "needs its password (⚙) or Accessibility"
                        : "see the log"
                    self.show("✗ \(name): \(why)  \(at)", Ink.red, for: 30, tip: r.detail)
                    self.dot.color = Ink.red
                }
                if self.state?.isFresh ?? false { KeeperCommand(action: "check").send() }
            }
        }
    }

    // A message that stands on the status line for a while (the usual reading waits until then).
    func show(_ text: String, _ color: NSColor, for seconds: Double, tip: String? = nil) {
        pingHeld = Date().addingTimeInterval(seconds)
        if !noOther { checkedWidth.constant = 380; fit() }
        checked.stringValue = text
        checked.textColor = color
        checked.toolTip = tip
        if seconds < 60 {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) {
                if Date() >= self.pingHeld {
                    self.checked.toolTip = nil
                    if !self.noOther { self.checkedWidth.constant = Stripe.checkedNormal; self.fit() }
                    self.refresh()
                }
            }
        }
    }

    @objc func checkNow() {
        if state?.isFresh ?? false { KeeperCommand(action: "check").send(); return }
        checked.stringValue = "checking…"
        let cfg = Config.load()
        DispatchQueue.global().async {
            let p = Net.probe(pingHost: cfg.pingHost, httpURL: cfg.httpProbe)
            DispatchQueue.main.async {
                switch p {
                case .online(_, let ms): self.checked.stringValue = "online now ✓"; self.ping.title = ms.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
                case .captive: self.checked.stringValue = "captive portal ✗"
                case .offline: self.checked.stringValue = "offline now ✗"
                }
            }
        }
    }

    // THE PING BUTTON (Marko, 13.10.2026: "I want to press the ping and then it pings and tells me if my
    // connection is alive or not ... exactly on the status line"). The stripe pings by itself, keeper or
    // not, and the answer stands on the stripe for 20 s before the usual reading comes back.
    @objc func pingNow() {
        let cfg = Config.load()
        pingHeld = Date().addingTimeInterval(60)
        ping.title = "ping (...)"
        ping.contentTintColor = Ink.yellow
        checked.stringValue = "pinging \(cfg.pingHost)…"
        checked.textColor = Ink.amber
        dot.color = Ink.amber
        applyAlert()
        DispatchQueue.global().async {
            let p = Net.probe(pingHost: cfg.pingHost, httpURL: cfg.httpProbe)
            DispatchQueue.main.async {
                let at = Date().formatted(date: .omitted, time: .standard)
                switch p {
                case .online(_, let ms):
                    self.ping.title = ms.map { String(format: "ping %3.0f ms", $0) } ?? "ping —"
                    self.checked.stringValue = ms != nil ? "ALIVE ✓  \(at)" : "ALIVE ✓  web only (ping blocked)"
                    self.ping.contentTintColor = Ink.yellow; self.checked.textColor = Ink.green; self.dot.color = Ink.green
                case .captive:
                    self.ping.title = "ping ✗"
                    self.checked.stringValue = "NOT ALIVE ✗  captive portal  \(at)"
                    self.ping.contentTintColor = Ink.red; self.checked.textColor = Ink.red; self.dot.color = Ink.red
                case .offline:
                    self.ping.title = "ping ✗"
                    self.checked.stringValue = "NOT ALIVE ✗  no answer  \(at)"
                    self.ping.contentTintColor = Ink.red; self.checked.textColor = Ink.red; self.dot.color = Ink.red
                }
                self.pingHeld = Date().addingTimeInterval(20)
                self.applyAlert()
                DispatchQueue.main.asyncAfter(deadline: .now() + 20.5) {
                    if Date() >= self.pingHeld { self.ping.contentTintColor = Ink.yellow; self.refresh() }
                }
            }
        }
    }

    // RESCAN (v32, request 49: "how can I force it to recheck connections? ... I plugged in my phone, and it's not
    // automatically recognized"). The stripe looks again itself at once, and asks the server (Aggregation.requestRescan)
    // to find every device and phone again and check every line; the status slot says "rescanning…", then the lines
    // the server has now ("2 LINES ✓ 22:41", their names in the tooltip), or in red that the server did not answer.
    @objc func rescanNow() {
        let asked = Date()
        pingHeld = asked.addingTimeInterval(60)
        checked.stringValue = "rescanning…"
        checked.textColor = Ink.amber
        checked.toolTip = nil
        rescan.contentTintColor = Ink.amber
        fit()
        appendLog("\(logStamp()) RESCAN pressed")
        scanLines()
        let aggregating = Aggregation.aggregateMode
        DispatchQueue.global().async {
            var answer: [String]?
            if aggregating {
                Aggregation.requestRescan()
                if Aggregation.status() == nil {      // the server is not there: loaded and started again, it takes the request
                    for l in Aggregation.ensureAgents() { appendLog("\(logStamp()) RESCAN: \(l) was not loaded, loaded it") }
                    shell("/bin/launchctl", ["kickstart", "gui/\(getuid())/\(CKAggregateLabel)"])
                }
                for _ in 0..<60 { if let a = Aggregation.rescanAnswer(since: asked) { answer = a; break }; usleep(500_000) }
            }
            DispatchQueue.main.async {
                let at = Date().formatted(date: .omitted, time: .shortened)
                self.rescan.contentTintColor = Ink.text
                if !aggregating {
                    self.checked.stringValue = "RESCANNED ✓ \(at)"; self.checked.textColor = Ink.green
                } else if let a = answer {
                    let alive = a.filter { $0.hasSuffix("(alive)") }.count
                    self.checked.stringValue = "\(alive) LINE\(alive == 1 ? "" : "S") ✓ \(at)"
                    self.checked.textColor = alive >= 2 ? Ink.green : alive == 1 ? Ink.amber : Ink.red
                    self.checked.toolTip = a.isEmpty ? "no line found" : a.joined(separator: "\n")
                    appendLog("\(logStamp()) RESCAN answered: " + (a.isEmpty ? "no line" : a.joined(separator: " + ")))
                } else {
                    self.checked.stringValue = "RESCAN ✗ \(at)"; self.checked.textColor = Ink.red
                    self.checked.toolTip = "The aggregation server did not answer within 30 s"
                    appendLog("\(logStamp()) RESCAN: the server did not answer within 30 s")
                }
                self.scanLines()
                self.pingHeld = Date().addingTimeInterval(20)
                self.fit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 20.5) {
                    if Date() >= self.pingHeld { self.checked.toolTip = nil; self.refresh() }
                }
            }
        }
    }

    @objc func openLog() { NSWorkspace.shared.open(Paths.log) }

    @objc func openSettings() {
        if settings == nil { settings = SettingsWindow() }
        settings?.show()
    }
}

// `--check-join`: can this app reach Control Centre's Wi-Fi list (Accessibility granted)? Reads it, presses nothing.
if CommandLine.arguments.contains("--check-join") {
    let r = ControlCenterWifi.list()
    let line = "\(logStamp()) CHECK join path: accessibility \(AXIsProcessTrusted() ? "granted" : "NOT granted"); Control Centre Wi-Fi list " +
        (r.ok ? "read: \(r.networks.joined(separator: ", "))" : "not read: \(r.detail)") +
        "; stored passwords: " + Config.load().connections.map { "\($0.name) \(WifiPassword.has($0.name) ? "yes" : "no")" }.joined(separator: ", ")
    print(line); appendLog(line)
    exit(r.ok ? 0 : 1)
}

// v33 (request 50): the keeper and the server loaded by the stripe when macOS did not load them at login.
func loadAgents() {
    DispatchQueue.global().async {
        for l in Aggregation.ensureAgents() { appendLog("\(logStamp()) AGENT \(l) was not loaded (macOS Login Items: not allowed in the background?): loaded it") }
    }
}

let app = NSApplication.shared
if !OnOff.atStart(login: CommandLine.arguments.contains("--login") || (ProcessInfo.processInfo.systemUptime < 600 && !CommandLine.arguments.contains("--selftest"))) { exit(0) }   // v39: OFF stays off at login
app.setActivationPolicy(.regular)                  // v73 (request 86): a Dock icon, ⌘-Tab, a main menu
let stripe = Stripe()
stripe.lights.isHidden = true                       // the system's own traffic lights replace the drawn ones
AppShell.shared.install(on: app)
let atLogin = CommandLine.arguments.contains("--login")
if !CommandLine.arguments.contains("--selftest") {
    // v73 (request 87): open = Frankfurt; the session's order never leaves the Mac without a road
    DispatchQueue.global().async { Session.open { appendLog("\(logStamp()) \($0)") } }
    if atLogin && !WindowPrefs.openAtLogin { MenuBarPrefs.stripeHidden = true; stripe.panel.orderOut(nil) }
}
if CommandLine.arguments.contains("--settings") { stripe.openSettings() }
if CommandLine.arguments.contains("--check-data") { stripe.checkDataByHand() }    // v8: the same as a click on the data item
if CommandLine.arguments.contains("--rescan") { stripe.rescanNow() }             // v32: the same as ⟳
// v55: `--selftest` builds the whole stripe, lays it out, lets the timers run for 4 s and exits 0 (CI runs it; a crash in
// Stripe.init, like the v54 constraint without a common ancestor, fails the workflow instead of shipping).
if !CommandLine.arguments.contains("--selftest") { MenuBarPlace.registerLogin(); Updater.checkAtStart() }   // v62: asks to update at start
if CommandLine.arguments.contains("--selftest") {
    stripe.panel.orderOut(nil)
    stripe.fit(); stripe.layoutLines()
    RunLoop.current.run(until: Date().addingTimeInterval(4))
    stripe.fit()
    // v73: the window is a normal one, and its picture for the CI artifact (looked at by Claude, never by Marko's screen)
    let m = stripe.panel.styleMask
    guard m.contains(.titled), m.contains(.miniaturizable), m.contains(.closable), NSApp.activationPolicy() == .regular, NSApp.mainMenu != nil else {
        print("selftest FAIL: not a normal window/app (style \(m.rawValue), policy \(NSApp.activationPolicy().rawValue))"); exit(1)
    }
    if let v = stripe.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/selftest-window.png"))
    }
    print("selftest OK: Stripe built, laid out, \(stripe.panel.frame.size); titled window, Dock app, menu: \(NSApp.mainMenu?.items.map(\.title).joined(separator: ", ") ?? "")")
    exit(0)
}
app.run()

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat, or fallback: CGFloat) -> CGFloat { self > 0 ? Swift.min(Swift.max(self, lo), hi) : fallback }
}

// v38: the permissions the stripe uses: Accessibility (joining a Wi-Fi through Control Centre's list, Join.swift).
// Nothing is asked by itself, at --login or ever; only a click on PERMISSIONS asks (swift-apps.md).
enum Permissions {
    static let needed = ["Accessibility", "Location"]
    static let locationManager = CLLocationManager()
    static func allowed(_ p: String) -> Bool {
        switch p {
        case "Accessibility": return AXIsProcessTrusted()
        case "Location": return !SignalHub.shared.wifiNeedsLocation || locationManager.authorizationStatus == .authorizedAlways   // v49: the Wi-Fi's signal reading
        default: return true
        }
    }
    static var missing: [String] { needed.filter { !allowed($0) } }
    // the system's own request once (it puts the app in the list), then the page of the first one missing
    static func openMissing() {
        guard let p = missing.first else { return }
        if p == "Accessibility" { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
        if p == "Location" { locationManager.requestWhenInUseAuthorization() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + (p == "Location" ? "LocationServices" : p))!)
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

// v27 (request 45): two vertical lines at the right end; dragged left or right, the stripe gets smaller or bigger.
final class Grip: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var startWidth: (() -> CGFloat)?
    private var from: (x: CGFloat, width: CGFloat)?
    override func draw(_ r: NSRect) {
        Ink.dim.setFill()
        for x in [bounds.midX - 2.5, bounds.midX + 1.5] {
            NSBezierPath(roundedRect: NSRect(x: x, y: bounds.minY + 2, width: 1, height: bounds.height - 4), xRadius: 0.5, yRadius: 0.5).fill()
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { from = (NSEvent.mouseLocation.x, startWidth?() ?? 0) }
    override func mouseDragged(with e: NSEvent) {
        guard let from else { return }
        onDrag?(from.width + NSEvent.mouseLocation.x - from.x)
    }
    override func mouseUp(with e: NSEvent) { from = nil }
}
