// SIGNAL STRENGTH AS A VU METER (v49, request 69 point 4, Marko 13.11.2026: "anything connected to my computer that's giving
// some kind of internet": its signal, measured precisely "like a VU meter on audio equipment"). Every line row has a
// horizontal meter in a fixed slot: a dBm scale with red / amber / green zones, the live value (about once a second), a
// peak-hold marker that falls slowly, and the exact number beside it. A click opens a larger meter window with every
// value of the line and a 5-minute history, for aiming a phone.
//   Mac Wi-Fi   CoreWLAN every 1 s: RSSI, noise, SNR = RSSI - noise, tx rate, channel and band.
//               Zones (RSSI): >= -55 excellent, -55..-67 good, -67..-75 fair, < -75 poor. Without the Location
//               permission (macOS 14+) the reading is 0: PERMISSIONS shows top right and a click opens its page.
//   Phone       adb every 2 s, ONE shell: dumpsys telephony.registry | grep mSignalStrength. LTE rsrp, rsrq, rssnr
//               (SINR), rssi; NR ssRsrp, ssRsrq, ssSinr; 2147483647 = unavailable, ignored. RSRP zones: >= -80
//               excellent, -80..-90 good, -90..-100 fair, < -100 poor; SINR: >= 20, 13..20, 0..13, < 0.
//               A phone whose hotspot the Mac's Wi-Fi is on is reached over the hotspot's gateway (adb tcpip 5555),
//               so the Wi-Fi line shows the phone's radio, which is what the internet depends on.
//   Cable       the link speed from ifconfig (Mb/s). The TP-Link's 4G signal is not read (no new router login).
import AppKit
import CoreWLAN
import CoreLocation

struct MeterScale {
    let lo: Double, hi: Double, excellent: Double, good: Double, fair: Double, unit: String
    var neutral = false                      // v50: a link speed is not a quality: grey, no red/amber/green
    static let wifi = MeterScale(lo: -95, hi: -30, excellent: -55, good: -67, fair: -75, unit: "dBm")
    static let rsrp = MeterScale(lo: -140, hi: -60, excellent: -80, good: -90, fair: -100, unit: "dBm")
    static let link = MeterScale(lo: 0, hi: 1000, excellent: 900, good: 500, fair: 90, unit: "Mb/s", neutral: true)
    func color(_ v: Double) -> NSColor { if neutral { return Ink.text }; return v >= good ? Ink.green : v >= fair ? Ink.amber : Ink.red }
    func word(_ v: Double) -> String { if neutral { return "" }; return v >= excellent ? "excellent" : v >= good ? "good" : v >= fair ? "fair" : "poor" }
    func frac(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, (v - lo) / (hi - lo)))) }
    var zones: [(Double, Double, NSColor)] { if neutral { return [(lo, hi, Ink.dim)] }; return [(lo, fair, Ink.red), (fair, good, Ink.amber), (good, hi, Ink.green)] }
}

func sinrWord(_ v: Double) -> String { v >= 20 ? "excellent" : v >= 13 ? "good" : v >= 0 ? "fair" : "poor" }

struct LineSignal {
    var scale = MeterScale.wifi
    var value: Double?
    var peak: Double?
    var peakAt = Date()
    var text = "—"
    var tint: NSColor?
    var details: [String] = []
    var history: [(at: Date, v: Double)] = []
}

final class SignalHub {
    static let shared = SignalHub()
    var lines: [String: LineSignal] = [:]
    var tags: [String: String] = [:]
    var wifiNeedsLocation = false
    var hotspotTarget: String?

    func put(_ key: String, scale: MeterScale, value: Double?, text: String, details: [String]) {
        var l = lines[key] ?? LineSignal()
        let now = Date()
        l.scale = scale; l.value = value; l.text = text; l.details = details
        if let v = value {
            let dt = now.timeIntervalSince(l.peakAt)
            let fallen = (l.peak ?? v) - (scale.hi - scale.lo) * 0.01 * dt        // the peak falls 1 % of the scale a second
            l.peak = max(v, fallen); l.peakAt = now
            l.history.append((now, v))
            l.history.removeAll { now.timeIntervalSince($0.at) > 300 }
        } else { l.peak = nil }
        lines[key] = l
    }

    // The adb address of the phone whose hotspot the Mac's Wi-Fi is on: the Wi-Fi's gateway, port 5555.
    static func findHotspot() -> String? {
        guard let adb = Phones.adb, let w = Net.wifiInterface() else { return nil }
        let gw = shell("/usr/sbin/ipconfig", ["getoption", w, "router"], timeout: 4).out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gw.isEmpty else { return nil }
        let target = gw + ":5555"
        func up() -> Bool { shell(adb, ["-s", target, "get-state"], timeout: 4).out.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("device") }
        if up() { return target }
        shell(adb, ["connect", target], timeout: 5)
        return up() ? target : nil
    }

    // The signal fields of `dumpsys telephony.registry | grep mSignalStrength`; the first SIM with values wins.
    static func parsePhone(_ out: String) -> [String: Double] {
        var o: [String: Double] = [:]
        func num(_ s: Substring, _ k: String) -> Double? {
            guard let r = s.range(of: k + "=") else { return nil }
            let v = s[r.upperBound...].prefix { $0 == "-" || $0.isNumber }
            guard let i = Int(v), i != Int(Int32.max), i > -1000, i < 1000 else { return nil }
            return Double(i)
        }
        for line in out.components(separatedBy: "\n") {
            guard let m = line.range(of: "mSignalStrength=") else { continue }
            let l = line[m.upperBound...]
            func seg(_ key: String) -> Substring? {
                guard let r = l.range(of: key) else { return nil }
                let t = l[r.upperBound...]
                return t.range(of: "CellSignalStrength").map { t[..<$0.lowerBound] } ?? t
            }
            if let t = seg("CellSignalStrengthLte:") {
                for (k, n) in [("rssi", "rssi"), ("rsrp", "rsrp"), ("rsrq", "rsrq"), ("rssnr", "rssnr")] where o[n] == nil { if let v = num(t, k) { o[n] = v } }
            }
            if let t = seg("CellSignalStrengthNr:") {
                for (k, n) in [("ssRsrp", "nrRsrp"), ("ssRsrq", "nrRsrq"), ("ssSinr", "nrSinr")] where o[n] == nil { if let v = num(t, k) { o[n] = v } }
            }
        }
        return o
    }

    func putPhone(_ key: String, _ v: [String: Double], tag: String?) {
        if let tag { tags[key] = tag }
        let primary = v["rsrp"] ?? v["nrRsrp"]
        let t = tags[key] ?? ""
        let short = t.contains("5G") ? "5G" : t.contains("4G+") ? "4G+" : t.isEmpty ? "" : "4G"
        var d: [String] = []
        func add(_ name: String, _ k: String, _ unit: String, _ word: ((Double) -> String)? = nil) {
            if let x = v[k] { d.append("\(name) \(Int(x)) \(unit)" + (word.map { "  (\($0(x)))" } ?? "")) }
        }
        add("LTE RSRP ", "rsrp", "dBm", MeterScale.rsrp.word); add("LTE RSRQ ", "rsrq", "dB"); add("LTE RSSNR (SINR) ", "rssnr", "dB", sinrWord); add("LTE RSSI ", "rssi", "dBm")
        add("NR ssRSRP ", "nrRsrp", "dBm", MeterScale.rsrp.word); add("NR ssRSRQ ", "nrRsrq", "dB"); add("NR ssSINR ", "nrSinr", "dB", sinrWord)
        if !t.isEmpty { d.append("Network: " + t) }
        let sinr = v["rssnr"] ?? v["nrSinr"]
        put(key, scale: .rsrp, value: primary, text: primary.map { "\(Int($0)) dBm \(short) SINR \(sinr.map { String(Int($0)) } ?? "—")" } ?? "no signal", details: d)
        // the colour is the worse of RSRP and SINR (SINR decides the speed): red poor, amber fair, green good
        if let p = primary {
            let rank = { (c: NSColor) -> Int in c == Ink.red ? 2 : c == Ink.amber ? 1 : 0 }
            let sc: NSColor = sinr.map { $0 >= 13 ? Ink.green : $0 >= 0 ? Ink.amber : Ink.red } ?? Ink.green
            let rc = MeterScale.rsrp.color(p)
            lines[key]?.tint = rank(sc) > rank(rc) ? sc : rc
        }
    }
}

extension Stripe {
    func startSignals() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sampleWifi(); self?.updateMeters() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.samplePhones() }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sampleLinks() }
    }

    func sampleWifi() {
        let hub = SignalHub.shared
        guard let c = CWWiFiClient.shared().interface(), c.powerOn() else { hub.lines["wifi"] = nil; return }
        let rssi = c.rssiValue(), noise = c.noiseMeasurement()
        if rssi == 0 {
            if let n = c.interfaceName, Net.ipAddress(n) != nil { hub.wifiNeedsLocation = true }
            hub.put("wifi", scale: .wifi, value: nil, text: "no reading", details: ["No RSSI: the Location permission is missing (macOS 14+)."])
            return
        }
        hub.wifiNeedsLocation = false
        let band: String
        switch c.wlanChannel()?.channelBand {
        case .band2GHz?: band = "2.4 GHz"
        case .band5GHz?: band = "5 GHz"
        case .band6GHz?: band = "6 GHz"
        default: band = ""
        }
        let ch = c.wlanChannel().map { "channel \($0.channelNumber) \(band)" } ?? "channel ?"
        let d = ["Wi-Fi RSSI \(rssi) dBm  (\(MeterScale.wifi.word(Double(rssi))))", "noise \(noise) dBm", "SNR \(rssi - noise) dB",
                 String(format: "tx rate %.0f Mbit/s", c.transmitRate()), ch]
        hub.put("wifi", scale: .wifi, value: Double(rssi), text: "\(rssi) dBm SNR \(rssi - noise)", details: d)
    }

    // Every 2 s, one adb shell a phone, off the main thread; the tag (4G / 5G) every 16 s.
    func samplePhones() {
        if phoneSampling { return }
        phoneSampling = true
        signalTick += 1
        let round = signalTick, known = SignalHub.shared.hotspotTarget
        let usb = others.filter { Phones.isPhone($0.iface) }.map { String($0.iface.dropFirst(4)) }
        DispatchQueue.global().async {
            var hot = known
            if round % 15 == 1 || (hot == nil && round % 5 == 1) { hot = SignalHub.findHotspot() }
            var targets = usb.map { ("adb:" + $0, $0) }
            if let hot { targets.append(("hot", hot)) }
            var out: [(String, [String: Double], String?)] = []
            if let adb = Phones.adb {
                for (key, serial) in targets {
                    let r = shell(adb, ["-s", serial, "shell", "dumpsys telephony.registry | grep mSignalStrength"], timeout: 6)
                    let tag = round % 8 == 1 ? PhoneRadio.read(serial)?["type"] as? String : nil
                    out.append((key, SignalHub.parsePhone(r.out), tag))
                }
            }
            DispatchQueue.main.async {
                self.phoneSampling = false
                let hub = SignalHub.shared
                hub.hotspotTarget = hot
                if hot == nil { hub.lines["hot"] = nil }
                for (key, v, tag) in out {
                    if v.isEmpty { if key == "hot" { hub.hotspotTarget = nil; hub.lines["hot"] = nil }; continue }
                    hub.putPhone(key, v, tag: tag)
                }
            }
        }
    }

    // The cable's link speed from ifconfig's media line, every 5 s.
    func sampleLinks() {
        let cables = others.filter { !$0.wifi && !Phones.isPhone($0.iface) }.map(\.iface)
        guard !cables.isEmpty else { return }
        DispatchQueue.global().async {
            var got: [(String, Double?, String)] = []
            for i in cables {
                let out = shell("/sbin/ifconfig", [i], timeout: 4).out
                var mbps: Double?, media = "?"
                if let r = out.range(of: #"media: [^\n]*"#, options: .regularExpression) { media = String(out[r]) }
                if let r = media.range(of: #"\((\d+)(G?)base"#, options: .regularExpression) {
                    let s = media[r].dropFirst().prefix { $0.isNumber }
                    mbps = Double(s).map { $0 * (media[r].contains("Gbase") ? 1000 : 1) }
                }
                got.append((i, mbps, media))
            }
            DispatchQueue.main.async {
                for (i, m, media) in got {
                    SignalHub.shared.put("link:" + i, scale: .link, value: m, text: m.map { "\(Int($0)) Mb/s" } ?? "no link",
                                         details: ["Link speed " + (m.map { "\(Int($0)) Mb/s" } ?? "none"), media])
                }
            }
        }
    }

    // The meters a line shows: a hotspot line has two, WI-FI (Mac to phone) and 4G (phone to tower).
    func signalKeys(_ o: OtherLine) -> [(String, String)] {
        if Phones.isPhone(o.iface) { return [("4G", "adb:" + String(o.iface.dropFirst(4)))] }
        if o.wifi { return SignalHub.shared.lines["hot"]?.value != nil ? [("WI-FI", "wifi"), ("4G", "hot")] : [("WI-FI", "wifi")] }
        return [("LINK", "link:" + o.iface)]
    }

    func updateMeters() {
        let hub = SignalHub.shared
        for o in others {
            guard let r = lineRows[o.iface] else { continue }
            let keys = signalKeys(o)
            let slots = [(r.tag1, r.meter, r.sig), (r.tag2, r.meter2, r.sig2)]
            for (i, s) in slots.enumerated() {
                let (tag, meter, sig) = s
                guard i < keys.count else { tag.stringValue = ""; meter.alphaValue = 0; meter.onClick = nil; sig.stringValue = ""; continue }
                let (name, key) = keys[i]
                tag.stringValue = name; tag.textColor = Ink.dim; meter.alphaValue = 1
                if key == "wifi" && hub.wifiNeedsLocation {
                    tag.stringValue = "WI-FI ·"; meter.value = nil; meter.peak = nil; meter.needsDisplay = true
                    sig.stringValue = "permission"; sig.textColor = Ink.amber
                    meter.toolTip = "The Mac's Wi-Fi signal needs the Location permission: PERMISSIONS, top right."
                    continue
                }
                guard let l = hub.lines[key] else { meter.value = nil; meter.peak = nil; meter.needsDisplay = true; sig.stringValue = "—"; sig.textColor = Ink.dim; continue }
                meter.scale = l.scale; meter.value = l.value; meter.peak = l.peak; meter.needsDisplay = true
                sig.stringValue = l.text
                sig.textColor = l.tint ?? l.value.map { l.scale.color($0) } ?? Ink.dim
                meter.toolTip = l.details.joined(separator: "\n") + "\nClick: a larger meter with a 5-minute history."
                meter.onClick = { SignalWindow.show(key: key, title: o.name + " · " + name) }
            }
        }
        SignalWindow.updateAll()
    }
}

// The meter: zones dim, filled to the value in the zone colours, a white peak-hold marker, a tick at "excellent".
final class VUMeter: NSView {
    var scale = MeterScale.wifi
    var value: Double?
    var peak: Double?
    var big = false
    var onClick: (() -> Void)?
    override var intrinsicContentSize: NSSize { NSSize(width: big ? NSView.noIntrinsicMetric : 150, height: big ? 30 : 14) }
    override func draw(_ r: NSRect) {
        let w = bounds.width, h = bounds.height
        let track = NSRect(x: 0, y: h * 0.2, width: w, height: h * 0.6)
        for z in scale.zones {
            let x0 = w * scale.frac(z.0), x1 = w * scale.frac(z.1)
            z.2.withAlphaComponent(0.25).setFill()
            NSRect(x: x0, y: track.minY, width: x1 - x0, height: track.height).fill()
        }
        if let v = value {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: track.minY, width: w * scale.frac(v), height: track.height)).addClip()
            for z in scale.zones {
                let x0 = w * scale.frac(z.0), x1 = w * scale.frac(z.1)
                z.2.setFill()
                NSRect(x: x0, y: track.minY, width: x1 - x0, height: track.height).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(calibratedWhite: 0.7, alpha: scale.neutral ? 0 : 0.6).setFill()
        NSRect(x: w * scale.frac(scale.excellent) - 0.5, y: 0, width: 1, height: h).fill()
        if let p = peak {
            NSColor.white.setFill()
            NSRect(x: max(0, w * scale.frac(p) - 1), y: 0, width: 2, height: h).fill()
        }
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
}

// The 5-minute history of one line.
final class HistoryGraph: NSView {
    var scale = MeterScale.wifi
    var points: [(at: Date, v: Double)] = []
    override func draw(_ r: NSRect) {
        let w = bounds.width, h = bounds.height
        func y(_ v: Double) -> CGFloat { h * scale.frac(v) }
        for z in scale.zones {
            z.2.withAlphaComponent(0.15).setFill()
            NSRect(x: 0, y: y(z.0), width: w, height: y(z.1) - y(z.0)).fill()
        }
        let now = Date()
        let path = NSBezierPath()
        for (i, p) in points.enumerated() {
            let x = w * CGFloat(1 - now.timeIntervalSince(p.at) / 300)
            if i == 0 { path.move(to: NSPoint(x: x, y: y(p.v))) } else { path.line(to: NSPoint(x: x, y: y(p.v))) }
        }
        NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: Ink.dim]
        ("\(Int(scale.hi)) \(scale.unit)" as NSString).draw(at: NSPoint(x: 4, y: h - 14), withAttributes: a)
        ("\(Int(scale.lo)) \(scale.unit)" as NSString).draw(at: NSPoint(x: 4, y: 2), withAttributes: a)
        ("−5 min" as NSString).draw(at: NSPoint(x: 4, y: h / 2 - 6), withAttributes: a)
        ("now" as NSString).draw(at: NSPoint(x: w - 28, y: 2), withAttributes: a)
    }
}

// The larger meter window: resizable, the traffic lights on the left (a titled window).
final class SignalWindow: NSObject, NSWindowDelegate {
    static var open: [String: SignalWindow] = [:]
    let key: String
    let window: NSWindow
    let meter = VUMeter(), graph = HistoryGraph()
    let text = NSTextField(wrappingLabelWithString: "")

    static func show(key: String, title: String) {
        if let w = open[key] { w.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = SignalWindow(key: key, title: title)
        open[key] = w
        w.update()
        w.window.center()
        w.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    static func updateAll() { for w in open.values { w.update() } }

    init(key: String, title: String) {
        self.key = key
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Signal · " + title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 420, height: 360)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Ink.ground
        meter.big = true
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.heightAnchor.constraint(equalToConstant: 30).isActive = true
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.textColor = Ink.text
        graph.translatesAutoresizingMaskIntoConstraints = false
        graph.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        graph.setContentHuggingPriority(.defaultLow, for: .vertical)
        let stack = NSStackView(views: [meter, text, graph])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        window.contentView = stack
    }

    func update() {
        guard let l = SignalHub.shared.lines[key] else { text.stringValue = "No reading yet."; return }
        meter.scale = l.scale; meter.value = l.value; meter.peak = l.peak; meter.needsDisplay = true
        var lines = [l.value.map { "\(l.text)   \(l.scale.word($0))" } ?? l.text] + l.details
        if key == "hot", let w = SignalHub.shared.lines["wifi"] { lines += ["", "Mac Wi-Fi to the phone's hotspot:"] + w.details }
        text.stringValue = lines.joined(separator: "\n")
        graph.scale = l.scale; graph.points = l.history; graph.needsDisplay = true
    }

    func windowWillClose(_ n: Notification) { SignalWindow.open[key] = nil }
}
