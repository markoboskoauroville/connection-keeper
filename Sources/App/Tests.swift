// TEST SPEED · TEST HEALTH (v43, request 58, Marko 1.11.2026: "in the user interface at the top, are the buttons Test
// Speed and Test Health. It tests both things and gives a report in a pop-up window, reporting for each interface: speed,
// speed together for uploading and downloading, health ... an overall health graph ... which make sense for professional
// engineers in networking").
// The measuring is ck-net (Sources/Net, Contents/MacOS/ck-net); it rewrites linetest-speed.json / linetest-health.json
// every half second, and the report window draws that file as it grows: a table per line, the throughput over time
// (one colour per line, the same colour in both graphs and the table), the round trip over time (idle, then under load),
// and the findings in words.
import AppKit

enum LineTest {
    static func file(_ kind: String) -> URL { Paths.support.appendingPathComponent("linetest-\(kind).json") }
    static var tool: String {
        let mine = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ck-net").path
        return FileManager.default.isExecutableFile(atPath: mine) ? mine : "/Applications/Network Aggregate Connection Keeper (Mantra).app/Contents/MacOS/ck-net"
    }
    // Series colours, the dataviz reference palette's dark column in its fixed order (blue, orange, aqua, yellow);
    // a line keeps its colour by its place in the test's own list.
    static let palette: [NSColor] = ["3987e5", "d95926", "199e70", "c98500", "d55181"].map { hex in
        let v = UInt32(hex, radix: 16)!
        return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    static var running: [String: Process] = [:]
}

extension Stripe {
    @objc func testSpeedPressed() { runLineTest("speed") }
    @objc func testHealthPressed() { runLineTest("health") }

    func runLineTest(_ kind: String) {
        let w = LineTestWindow.open(kind)
        if let p = LineTest.running[kind], p.isRunning { w.window.makeKeyAndOrderFront(nil); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: LineTest.tool)
        p.arguments = ["test", kind]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? FileManager.default.removeItem(at: LineTest.file(kind))
        do { try p.run() } catch { w.failed("ck-net could not start: \(error.localizedDescription)"); return }
        LineTest.running[kind] = p
        (kind == "speed" ? testSpeedWord : testHealthWord).contentTintColor = Ink.amber
        appendLog("\(logStamp()) TEST \(kind.uppercased()) pressed")
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                (kind == "speed" ? self?.testSpeedWord : self?.testHealthWord)?.contentTintColor = Ink.text
                LineTestWindow.windows[kind]?.reload()
            }
        }
    }
}

// A chart: x = seconds since the test began, y = one measure (Mbit/s or ms); one series per line; a recessive grid.
final class SeriesChart: NSView {
    var title = "", unit = ""
    var timeAxis = true
    var bars = false          // each point a bar (the health report's TLS / first-byte pairs)
    var series: [(name: String, color: NSColor, points: [[Double]], dashed: Bool)] = []
    var bands: [(from: Double, to: Double, label: String)] = []
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let ink = NSColor(calibratedWhite: 0.88, alpha: 1), muted = NSColor(calibratedWhite: 0.55, alpha: 1)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: muted]
        (title as NSString).draw(at: NSPoint(x: 0, y: bounds.height - 16), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink])
        let plot = NSRect(x: 44, y: 18, width: bounds.width - 52, height: bounds.height - 44)
        let all = series.flatMap(\.points)
        guard !all.isEmpty else { ("waiting for the first samples…" as NSString).draw(at: NSPoint(x: plot.minX, y: plot.midY), withAttributes: small); return }
        let xMax = max(5, all.map { $0[0] }.max() ?? 1)
        var yMax = max(1, all.map { $0[1] }.max() ?? 1)
        let step = [1.0, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000].first { yMax / $0 <= 5 } ?? 5000
        yMax = (yMax / step).rounded(.up) * step
        func pt(_ p: [Double]) -> NSPoint { NSPoint(x: plot.minX + CGFloat(p[0] / xMax) * plot.width, y: plot.minY + CGFloat(min(p[1], yMax) / yMax) * plot.height) }
        // phase bands (which line was alone, all together), behind everything
        for (i, b) in bands.enumerated() {
            let x0 = plot.minX + CGFloat(b.from / xMax) * plot.width, x1 = plot.minX + CGFloat(b.to / xMax) * plot.width
            NSColor(calibratedWhite: 1, alpha: i % 2 == 0 ? 0.035 : 0.0).setFill()
            NSRect(x: x0, y: plot.minY, width: max(0, x1 - x0), height: plot.height).fill()
            (b.label as NSString).draw(at: NSPoint(x: x0 + 3, y: plot.maxY + 2), withAttributes: small)
        }
        // grid and y axis
        var y = 0.0
        while y <= yMax + 0.001 {
            let yy = plot.minY + CGFloat(y / yMax) * plot.height
            NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
            let g = NSBezierPath(); g.move(to: NSPoint(x: plot.minX, y: yy)); g.line(to: NSPoint(x: plot.maxX, y: yy)); g.lineWidth = 1; g.stroke()
            let t = (y == y.rounded() ? String(Int(y)) : String(format: "%.1f", y)) as NSString
            let sz = t.size(withAttributes: small)
            t.draw(at: NSPoint(x: plot.minX - sz.width - 4, y: yy - sz.height / 2), withAttributes: small)
            y += step
        }
        (unit as NSString).draw(at: NSPoint(x: 0, y: plot.maxY + 2), withAttributes: small)
        if timeAxis {
            ("\(Int(xMax)) s" as NSString).draw(at: NSPoint(x: plot.maxX - 24, y: 2), withAttributes: small)
            ("0 s" as NSString).draw(at: NSPoint(x: plot.minX, y: 2), withAttributes: small)
        }
        if bars {
            let w: CGFloat = 22
            for s in series {
                for (k, p) in s.points.enumerated() {
                    let top = pt(p), r = NSRect(x: top.x - w / 2, y: plot.minY, width: w, height: max(1, top.y - plot.minY))
                    s.color.withAlphaComponent(k == 0 ? 0.55 : 1).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
                    let v = String(format: "%.0f ms", p[1]) as NSString
                    let sz = v.size(withAttributes: small)
                    v.draw(at: NSPoint(x: top.x - sz.width / 2, y: top.y + 2), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: ink])
                }
            }
            return
        }
        // the lines: 2 px, a gap in the line where a sample is missing for more than a second
        for s in series where s.points.count > 1 {
            let path = NSBezierPath()
            var last: Double?
            for p in s.points {
                if let l = last, p[0] - l < 1.2 { path.line(to: pt(p)) } else { path.move(to: pt(p)) }
                last = p[0]
            }
            path.lineWidth = 2; path.lineJoinStyle = .round
            if s.dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
            s.color.setStroke(); path.stroke()
        }
    }
}

final class LineTestWindow: NSObject, NSWindowDelegate {
    static var windows: [String: LineTestWindow] = [:]
    let kind: String
    let window: NSWindow
    let head = NSTextField(labelWithString: "")
    let table = NSTextField(labelWithString: "")
    let legend = NSTextField(labelWithString: "")
    let notes = NSTextField(wrappingLabelWithString: "")
    let chartA = SeriesChart(), chartB = SeriesChart()
    var timer: Timer?

    static func open(_ kind: String) -> LineTestWindow {
        if let w = windows[kind] { w.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); w.start(); return w }
        let w = LineTestWindow(kind); windows[kind] = w; w.start(); return w
    }

    init(_ kind: String) {
        self.kind = kind
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = kind == "speed" ? "TEST SPEED" : "TEST HEALTH"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 900, height: 560)
        window.level = .floating            // above ordinary windows, under the stripe (layer 25)
        let close = NSButton(title: "✕", target: self, action: #selector(closeIt))
        close.isBordered = false; close.font = .systemFont(ofSize: 15, weight: .bold); close.contentTintColor = Ink.text
        close.setAccessibilityIdentifier("close"); close.toolTip = "Close the report (the test goes on if it runs)"
        head.font = .monospacedSystemFont(ofSize: 15, weight: .bold); head.textColor = Ink.text
        head.lineBreakMode = .byTruncatingTail
        table.font = .monospacedSystemFont(ofSize: 12, weight: .regular); table.textColor = Ink.text
        table.isSelectable = true; table.maximumNumberOfLines = 0; table.lineBreakMode = .byWordWrapping   // never cut: a narrow window wraps
        legend.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        notes.font = .systemFont(ofSize: 12); notes.textColor = Ink.text; notes.isSelectable = true
        for v in [head, table, legend, notes, chartA, chartB, close] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(v) }
        let c = window.contentView!
        head.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        table.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        notes.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: c.topAnchor, constant: 8), close.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -12),
            head.topAnchor.constraint(equalTo: c.topAnchor, constant: 10), head.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16),
            head.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            table.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 10), table.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            table.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -16),
            legend.topAnchor.constraint(equalTo: table.bottomAnchor, constant: 10), legend.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            chartA.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 6), chartA.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16),
            chartA.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -16),
            chartB.topAnchor.constraint(equalTo: chartA.bottomAnchor, constant: 10), chartB.leadingAnchor.constraint(equalTo: chartA.leadingAnchor),
            chartB.trailingAnchor.constraint(equalTo: chartA.trailingAnchor), chartB.heightAnchor.constraint(equalTo: chartA.heightAnchor),
            chartA.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),
            notes.topAnchor.constraint(equalTo: chartB.bottomAnchor, constant: 10), notes.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            notes.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -16),
            notes.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -12),
        ])
        if kind == "speed" { chartA.title = "Throughput over time"; chartA.unit = "Mbit/s"; chartB.title = "Round trip to 1.1.1.1 (idle, then under the load above)"; chartB.unit = "ms" }
        else { chartA.title = "Round trip to 1.1.1.1, every 0.2 s"; chartA.unit = "ms"; chartB.title = "HTTPS to google.com per line: TLS handshake → first byte (median of 5)"; chartB.unit = "ms"; chartB.timeAxis = false; chartB.bars = true }
        // the window on the display where the stripe stands, centred
        if let s = (NSApp.windows.first { $0 is NSPanel && $0.isVisible })?.screen ?? NSScreen.main {
            let v = s.visibleFrame
            window.setFrame(NSRect(x: v.midX - min(590, v.width / 2 - 10), y: v.midY - min(390, v.height / 2 - 10), width: min(1180, v.width - 20), height: min(780, v.height - 20)), display: false)
        }
        Hover.walk(window.contentView!)
        head.stringValue = "\(window.title): starting…"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func closeIt() { window.orderOut(nil); timer?.invalidate() }
    func windowWillClose(_ notification: Notification) { timer?.invalidate() }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.reload() }
        reload()
    }
    func failed(_ why: String) { head.stringValue = "\(window.title): \(why)"; head.textColor = Ink.red }

    func reload() {
        guard let d = try? Data(contentsOf: LineTest.file(kind)), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        let running = j["running"] as? Bool ?? false
        if !running { timer?.invalidate() }
        if kind == "speed" { drawSpeed(j, running) } else { drawHealth(j, running) }
    }

    func names(_ j: [String: Any]) -> [String] { (j["lines"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } }
    func color(_ i: Int) -> NSColor { LineTest.palette[i % LineTest.palette.count] }
    func f(_ v: Any?, _ unit: String = "") -> String {
        if let d = v as? Double { return (d >= 100 ? String(format: "%.0f", d) : String(format: "%.1f", d)) + unit }
        if let i = v as? Int { return "\(i)\(unit)" }
        return "—"
    }
    func pad(_ s: String, _ n: Int, right: Bool = false) -> String {
        let t = s.count > n ? String(s.prefix(n - 1)) + "…" : s
        let sp = String(repeating: " ", count: max(0, n - t.count))
        return right ? sp + t : t + sp
    }
    func setLegend(_ ns: [String], extra: String = "") {
        let a = NSMutableAttributedString()
        for (i, n) in ns.enumerated() {
            a.append(NSAttributedString(string: "━━ ", attributes: [.foregroundColor: color(i), .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)]))
            a.append(NSAttributedString(string: n + "    ", attributes: [.foregroundColor: Ink.text, .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]))
        }
        if !extra.isEmpty { a.append(NSAttributedString(string: extra, attributes: [.foregroundColor: Ink.dim, .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)])) }
        legend.attributedStringValue = a
    }
    func clock(_ t: Any?) -> String {
        guard let t = t as? Double else { return "" }
        let f = DateFormatter(); f.dateFormat = "d.M.yyyy HH:mm:ss"; return f.string(from: Date(timeIntervalSince1970: t))
    }

    // MARK: speed
    func drawSpeed(_ j: [String: Any], _ running: Bool) {
        let ns = names(j)
        let rows = j["rows"] as? [[String: Any]] ?? []
        let tog = j["together"] as? [String: Any] ?? [:]
        let mb = j["mbUsed"] as? Double ?? 0
        if running { head.stringValue = "TEST SPEED · \(j["phase"] as? String ?? "…") · \(Int(mb)) MB so far"; head.textColor = Ink.amber }
        else { head.stringValue = "TEST SPEED · ALL TOGETHER ↓ \(f(tog["downMbps"])) ↑ \(f(tog["upMbps"])) Mbit/s · \(clock(j["finished"])) · \(Int(mb)) MB of SIM data"; head.textColor = Ink.green }
        var t = pad("LINE", 22) + pad("↓ Mbit/s", 9, right: true) + pad("↑ Mbit/s", 9, right: true) + pad("idle ms", 9, right: true)
            + pad("jitter", 8, right: true) + pad("loss %", 8, right: true) + pad("+ms ↓load", 11, right: true) + pad("+ms ↑load", 11, right: true) + pad("grade", 7, right: true)
            + pad("↓ in ALL", 10, right: true) + pad("↑ in ALL", 10, right: true) + "\n"
        let perD = tog["perLineDown"] as? [String: Double] ?? [:], perU = tog["perLineUp"] as? [String: Double] ?? [:]
        for r in rows {
            let n = r["name"] as? String ?? "", idle = r["idle"] as? [String: Any] ?? [:]
            t += pad(n, 22) + pad(f(r["downMbps"]), 9, right: true) + pad(f(r["upMbps"]), 9, right: true) + pad(f(idle["avg"]), 9, right: true)
                + pad(f(idle["jitter"]), 8, right: true) + pad(f(idle["lossPct"]), 8, right: true) + pad(f(r["bloatDownMs"]), 11, right: true)
                + pad(f(r["bloatUpMs"]), 11, right: true) + pad(r["grade"] as? String ?? "—", 7, right: true)
                + pad(f(perD[n]), 10, right: true) + pad(f(perU[n]), 10, right: true) + "\n"
        }
        if tog["downMbps"] != nil {
            let sumD = rows.compactMap { $0["downMbps"] as? Double }.reduce(0, +), sumU = rows.compactMap { $0["upMbps"] as? Double }.reduce(0, +)
            t += pad("SUM OF THE LINES ALONE", 22) + pad(f(sumD), 9, right: true) + pad(f(sumU), 9, right: true) + "\n"
            t += pad("ALL TOGETHER", 22) + pad(f(tog["downMbps"]), 9, right: true) + pad(f(tog["upMbps"]), 9, right: true)
                + "   = \(f(tog["downEfficiencyPct"]))% ↓ and \(f(tog["upEfficiencyPct"]))% ↑ of the sum"
        }
        table.stringValue = t
        setLegend(ns, extra: "solid = download, dashed = upload")
        let series = j["series"] as? [String: [[Double]]] ?? [:]
        var a: [(String, NSColor, [[Double]], Bool)] = []
        var bands: [(Double, Double, String)] = []
        for (i, n) in ns.enumerated() {
            for (dir, dashed) in [("down", false), ("up", true)] {
                let pts = (series["\(n)|\(dir)"] ?? []) + (series["ALL|\(dir)|\(n)"] ?? [])
                a.append((n, color(i), pts.sorted { $0[0] < $1[0] }, dashed))
            }
            let alone = (series["\(n)|down"] ?? []) + (series["\(n)|up"] ?? [])
            if let lo = alone.map({ $0[0] }).min(), let hi = alone.map({ $0[0] }).max() { bands.append((lo, hi, n.replacingOccurrences(of: " (USB)", with: "") + " alone")) }
        }
        let allPts = ns.flatMap { (series["ALL|down|\($0)"] ?? []) + (series["ALL|up|\($0)"] ?? []) }
        if let lo = allPts.map({ $0[0] }).min(), let hi = allPts.map({ $0[0] }).max() { bands.append((lo, hi, "ALL together")) }
        // the total of all lines while together, in the ink colour
        for dir in ["down", "up"] {
            var bins: [Double: Double] = [:]
            for n in ns { for p in series["ALL|\(dir)|\(n)"] ?? [] where p[1] > 0 { bins[(p[0] * 4).rounded() / 4, default: 0] += p[1] } }
            let pts = bins.keys.sorted().map { [$0, bins[$0]!] }
            if !pts.isEmpty { a.append(("ALL", Ink.text, pts, dir == "up")) }
        }
        chartA.series = a.map { (name: $0.0, color: $0.1, points: $0.2, dashed: $0.3) }
        chartA.bands = bands.map { (from: $0.0, to: $0.1, label: $0.2) }
        let ps = j["pingSeries"] as? [String: [[Double]]] ?? [:]
        chartB.series = ns.enumerated().map { (name: $1, color: color($0), points: ps[$1] ?? [], dashed: false) }
        chartB.bands = chartA.bands
        chartA.needsDisplay = true; chartB.needsDisplay = true
        notes.stringValue = running ? "Each line alone: 5 s download (4 streams), 5 s upload (3 streams), a ping running on the line during each. Then all lines at once. The speed is counted after the first second (TCP slow start). The white line is all lines added." : findingsSpeed(rows, tog)
    }

    func findingsSpeed(_ rows: [[String: Any]], _ tog: [String: Any]) -> String {
        var s: [String] = []
        let best = rows.max { ($0["downMbps"] as? Double ?? 0) < ($1["downMbps"] as? Double ?? 0) }
        if let b = best { s.append("Fastest alone: \(b["name"] ?? "") ↓ \(f(b["downMbps"])) Mbit/s.") }
        for r in rows where (r["downMbps"] as? Double ?? 0) < 50 { s.append("\(r["name"] ?? "") gives only \(f(r["downMbps"])) Mbit/s down alone: far below a 5G line (150–200 expected).") }
        if let e = tog["downEfficiencyPct"] as? Int, e < 75 {
            let per = tog["perLineDown"] as? [String: Double] ?? [:]
            let phones = rows.filter { ($0["kind"] as? String) == "phone" }
            let phonesAlone = phones.compactMap { $0["downMbps"] as? Double }
            let phonesAll = phones.compactMap { per[$0["name"] as? String ?? ""] }.reduce(0, +)
            if phones.count > 1, let mx = phonesAlone.max(), phonesAll < mx * 1.25 {
                s.append("BOTTLENECK: together the phones give \(f(phonesAll)) Mbit/s, hardly more than one phone alone (\(f(mx))). Both phones' traffic passes through adb over USB on this Mac: that path is the ceiling, not the radio. A phone in USB tethering (NCM, as a network card) would skip it.")
            } else {
                s.append("Together the lines reach \(e)% of their sum: something on the Mac's side is shared (USB, adb, the CPU).")
            }
        }
        for r in rows {
            if let g = r["grade"] as? String, ["D", "F"].contains(g) { s.append("\(r["name"] ?? ""): latency grade \(g): under load the round trip grows by \(f(r["bloatDownMs"])) ms down / \(f(r["bloatUpMs"])) ms up (bufferbloat): calls and games suffer while that line is full.") }
        }
        return s.joined(separator: "\n")
    }

    // MARK: health
    func drawHealth(_ j: [String: Any], _ running: Bool) {
        let lines = j["lines"] as? [[String: Any]] ?? []
        let ns = lines.compactMap { $0["name"] as? String }
        if running { head.stringValue = "TEST HEALTH · \(j["phase"] as? String ?? "…")"; head.textColor = Ink.amber }
        else {
            let sc = j["score"] as? Int ?? 0
            head.stringValue = "TEST HEALTH · \(sc)/100 \((j["word"] as? String ?? "").uppercased()) · \(clock(j["finished"]))"
            head.textColor = sc >= 75 ? Ink.green : sc >= 55 ? Ink.amber : Ink.red
        }
        var t = pad("LINE", 22) + pad("score", 14) + pad("min", 7, right: true) + pad("avg", 7, right: true) + pad("max", 7, right: true) + pad("p95", 7, right: true)
            + pad("jitter", 8, right: true) + pad("loss %", 8, right: true) + pad("TLS ms", 8, right: true) + pad("1st byte", 9, right: true) + "   public IP / site / radio\n"
        for l in lines {
            let p = l["ping"] as? [String: Any] ?? [:], h = l["http"] as? [String: Any] ?? [:]
            var radio = ""
            if let r = l["radio"] as? [String: Any] {
                radio = (r["type"] as? String ?? "?") + ((r["operator"] as? String).map { " \($0)" } ?? "")
                if let v = r["nrRsrp"] { radio += " RSRP \(v) dBm" } else if let v = r["lteRsrp"] { radio += " RSRP \(v) dBm" }
                if let v = r["nrSinr"] { radio += " SINR \(v) dB" } else if let v = r["lteSnr"] { radio += " SNR \(v) dB" }
            } else if (l["kind"] as? String) == "cable" { radio = "router" }
            let sc = l["score"] as? Int
            t += pad(l["name"] as? String ?? "", 22) + pad(sc.map { "\($0) \(l["word"] as? String ?? "")" } ?? "…", 14)
                + pad(f(p["min"]), 7, right: true) + pad(f(p["avg"]), 7, right: true) + pad(f(p["max"]), 7, right: true) + pad(f(p["p95"]), 7, right: true)
                + pad(f(p["jitter"]), 8, right: true) + pad(f(p["lossPct"]), 8, right: true) + pad(f(h["tlsMs"]), 8, right: true) + pad(f(h["firstByteMs"]), 9, right: true)
                + "   \(l["publicIP"] as? String ?? "") \(l["colo"] as? String ?? "") \(radio)\n"
        }
        table.stringValue = t
        setLegend(ns)
        chartA.series = lines.enumerated().map { (name: $1["name"] as? String ?? "", color: color($0), points: $1["pingSeries"] as? [[Double]] ?? [], dashed: false) }
        // B: one bar pair per line drawn as two points (TLS, first byte) so the same chart view serves
        chartB.series = lines.enumerated().map { i, l in
            let h = l["http"] as? [String: Any] ?? [:]
            let x = Double(i) * 3 + 1
            return (name: l["name"] as? String ?? "", color: color(i), points: [[x, h["tlsMs"] as? Double ?? 0], [x + 1, h["firstByteMs"] as? Double ?? 0]], dashed: false)
        }
        var hb: [(from: Double, to: Double, label: String)] = []
        for i in 0..<lines.count { let x = Double(i) * 3; hb.append((from: x + 0.5, to: x + 2.5, label: (lines[i]["name"] as? String ?? "").replacingOccurrences(of: " (USB)", with: "") + ": TLS (pale), first byte")) }
        chartB.bands = hb
        chartA.needsDisplay = true; chartB.needsDisplay = true
        if running { notes.stringValue = "Every line at once: a ping to 1.1.1.1 every 0.2 s for 10 s from the line itself (the cable bound to its device, a phone from its own shell), five HTTPS requests through the line, its public address and Cloudflare site, a phone's radio from Android. Almost no data."; return }
        var s: [String] = []
        for l in lines {
            let p = l["ping"] as? [String: Any] ?? [:]
            if let loss = p["lossPct"] as? Double, loss >= 1 { s.append("\(l["name"] ?? ""): \(f(loss)) % of the pings lost: TCP slows down on every loss; above 1 % a line feels unreliable.") }
            if let jit = p["jitter"] as? Double, jit >= 10 { s.append("\(l["name"] ?? ""): jitter \(f(jit)) ms: voice and video calls stutter above about 30 ms.") }
            if let r = l["radio"] as? [String: Any], let t = r["type"] as? String, !t.contains("5G") { s.append("\(l["name"] ?? ""): the phone shows \(t) on its data SIM right now (no 5G carrier attached).") }
            if let r = l["radio"] as? [String: Any], let rsrp = (r["nrRsrp"] ?? r["lteRsrp"]) as? Int, rsrp <= -110 { s.append("\(l["name"] ?? ""): weak LTE anchor signal (RSRP \(rsrp) dBm; good is above -90): a phone nearer a window holds 5G better.") }
        }
        if s.isEmpty { s.append("No fault found: every line answers, no loss worth naming, steady round trips.") }
        notes.stringValue = s.joined(separator: "\n")
    }
}
