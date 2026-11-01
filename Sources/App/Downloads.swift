// THE AGGREGATE DOWNLOAD MONITOR (v43, request 58, Marko 1.11.2026: "connect my download monitor and my aggregate in one
// application. Down in the status line, it registers the file which is downloading ... you can just press Resume if a
// download is broken. It gave verbose data about downloading status, speed, percentage, and estimated time of arrival").
// The bottom rows of the stripe: one per download of ck-net (Application Support/connection-keeper/downloads/*.json),
// running, broken or finished in the last ten minutes, and one per download the Download Monitor (127.0.0.1:8833) sees
// running. ck-net's rows carry RESUME (broken / stopped) or STOP (running); a program that died while downloading is
// BROKEN (its pid gone). Every slot has a fixed width so the stripe does not breathe while the numbers change.
import AppKit

struct DownloadRow {
    let id: String, text: NSAttributedString, canResume: Bool, canStop: Bool, ours: Bool
}

enum Downloads {
    static let dir = Paths.support.appendingPathComponent("downloads")
    static var monitorJobs: [[String: Any]] = []
    static var asking = false

    static func pidAlive(_ p: Int32) -> Bool { p > 0 && kill(p, 0) == 0 }

    static func eta(_ s: Int?) -> String {
        guard let s, s >= 0 else { return "ETA —" }
        return s >= 3600 ? String(format: "ETA %d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "ETA %d:%02d", s / 60, s % 60)
    }

    static func rows() -> [DownloadRow] {
        var out: [DownloadRow] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        var docs: [[String: Any]] = files.filter { $0.pathExtension == "json" }.compactMap {
            guard let d = try? Data(contentsOf: $0) else { return nil }
            return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        }
        docs.sort { ($0["updated"] as? Double ?? 0) > ($1["updated"] as? Double ?? 0) }
        for d in docs {
            guard let id = d["id"] as? String else { continue }
            var state = d["state"] as? String ?? "?"
            let updated = d["updated"] as? Double ?? 0
            let pid = d["pid"] as? Int32 ?? 0
            if ["downloading", "starting", "verifying"].contains(state) && !pidAlive(pid) { state = "broken" }
            if state == "done" && Date().timeIntervalSince1970 - updated > 600 { continue }
            if state != "done" && state != "downloading" && Date().timeIntervalSince1970 - updated > 86400 * 3 { continue }
            let name = d["name"] as? String ?? id
            let size = (d["size"] as? Double ?? 0) / 1e6, have = (d["have"] as? Double ?? 0) / 1e6
            let pct = d["pct"] as? Double ?? 0, mbps = state == "downloading" ? d["mbps"] as? Double ?? 0 : 0
            let lines = d["lines"] as? [String: [String: Any]] ?? [:]
            let per = lines.keys.sorted().map { k -> String in
                let l = lines[k]!
                let short = k.replacingOccurrences(of: " (USB)", with: "").replacingOccurrences(of: "Google ", with: "").components(separatedBy: " ").first ?? k
                let rest = (l["resting"] as? Bool ?? false) ? "✗" : ""
                return "\(short) \(String(format: "%5.1f", l["mbps"] as? Double ?? 0))\(rest)"
            }.joined(separator: " · ")
            let a = NSMutableAttributedString()
            let stateColor: NSColor = state == "done" ? Ink.green : state == "downloading" ? Ink.text : state == "verifying" ? Ink.amber : Ink.red
            a.append(NSAttributedString(string: "⬇ ", attributes: [.font: bold, .foregroundColor: stateColor]))
            let shortName = name.count > 30 ? String(name.prefix(29)) + "…" : name.padding(toLength: 30, withPad: " ", startingAt: 0)
            a.append(NSAttributedString(string: shortName + " ", attributes: [.font: mono, .foregroundColor: Ink.text]))
            let st = (state == "downloading" ? "" : state.uppercased() + " ").padding(toLength: 10, withPad: " ", startingAt: 0)
            a.append(NSAttributedString(string: st, attributes: [.font: bold, .foregroundColor: stateColor]))
            let nums = String(format: "%5.1f %% %6.0f/%-6.0f MB %6.1f Mbit/s ", pct, have, size, mbps)
                + (state == "downloading" ? eta(d["etaSeconds"] as? Int) : state == "done" ? "complete" : "").padding(toLength: 12, withPad: " ", startingAt: 0)
            a.append(NSAttributedString(string: nums, attributes: [.font: mono, .foregroundColor: Ink.text]))
            let extra = " | \(per) | \(d["piecesDone"] ?? 0)/\(d["piecesAll"] ?? 0) pieces · \(d["breaks"] ?? 0) breaks stitched · \(d["resumes"] ?? 0) resumes"
            a.append(NSAttributedString(string: extra, attributes: [.font: mono, .foregroundColor: Ink.dim]))
            out.append(DownloadRow(id: id, text: a, canResume: state == "broken" || state == "stopped", canStop: state == "downloading", ours: true))
            if out.count >= 3 { break }
        }
        // the Download Monitor's own running downloads (Hugging Face workers, curl watched by file, …)
        for j in monitorJobs where (j["state"] as? String) == "running" && !((j["id"] as? String ?? "").hasPrefix("ck-")) {
            let a = NSMutableAttributedString(string: "⬇ ", attributes: [.font: bold, .foregroundColor: Ink.text])
            let name = j["name"] as? String ?? "?"
            a.append(NSAttributedString(string: (name.count > 30 ? String(name.prefix(29)) + "…" : name.padding(toLength: 30, withPad: " ", startingAt: 0)) + " " + "MONITOR   ", attributes: [.font: mono, .foregroundColor: Ink.dim]))
            let s = String(format: "%5.1f %% %6.0f/%-6.0f MB %6.1f Mbit/s ", j["pct"] as? Double ?? 0, (j["have_mb"] as? Double ?? 0) * 1.048576, (j["want_mb"] as? Double ?? 0) * 1.048576, (j["speed_mbs"] as? Double ?? 0) * 8)
                + eta(j["eta_s"] as? Int)
            a.append(NSAttributedString(string: s, attributes: [.font: mono, .foregroundColor: Ink.text]))
            out.append(DownloadRow(id: j["id"] as? String ?? "", text: a, canResume: false, canStop: false, ours: false))
            if out.count >= 4 { break }
        }
        return out
    }

    static func askMonitor() {
        guard !asking else { return }
        asking = true
        var req = URLRequest(url: URL(string: "http://127.0.0.1:8833/progress")!, timeoutInterval: 1.5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { d, _, _ in
            let jobs = d.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["jobs"] as? [[String: Any]] ?? []
            DispatchQueue.main.async { monitorJobs = jobs; asking = false }
        }.resume()
    }

    static func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: LineTest.tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
        appendLog("\(logStamp()) DOWNLOAD \(args.joined(separator: " ")) pressed on the stripe")
    }
}

extension Stripe {
    // Called every second from refresh().
    func showDownloads() {
        downloadTick += 1
        if downloadTick % 2 == 0 { Downloads.askMonitor() }
        let rows = Downloads.rows()
        let ids = rows.map(\.id)
        if ids != downloadIDs {
            downloadIDs = ids
            dlBox.arrangedSubviews.forEach { dlBox.removeArrangedSubview($0); $0.removeFromSuperview() }
            for r in rows {
                let t = NSTextField(labelWithString: "")
                t.lineBreakMode = .byClipping
                let b = NSButton(title: "", target: self, action: #selector(downloadButton(_:)))
                b.isBordered = false
                b.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
                b.identifier = NSUserInterfaceItemIdentifier(r.id)
                b.setAccessibilityIdentifier("download-\(r.id)")
                b.setContentHuggingPriority(.required, for: .horizontal)
                t.translatesAutoresizingMaskIntoConstraints = false
                t.widthAnchor.constraint(equalToConstant: ceil(r.text.size().width) + 70).isActive = true   // room for the numbers to change
                let row = NSStackView(views: [t, b])
                row.orientation = .horizontal
                row.spacing = 8
                row.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 6)
                row.heightAnchor.constraint(equalToConstant: 22).isActive = true
                dlBox.addArrangedSubview(row)
            }
            fit()
        }
        for (i, r) in rows.enumerated() {
            guard let row = dlBox.arrangedSubviews[i] as? NSStackView, let t = row.arrangedSubviews[0] as? NSTextField, let b = row.arrangedSubviews[1] as? NSButton else { continue }
            if t.attributedStringValue != r.text { t.attributedStringValue = r.text }
            let title = r.canResume ? "RESUME" : r.canStop ? "STOP" : ""
            if b.title != title {
                b.title = title
                b.contentTintColor = r.canResume ? Ink.green : Ink.dim
                b.toolTip = r.canResume ? "Go on from where it broke: every finished piece is kept, a cut piece continues from its last byte" : "Stop it (RESUME goes on later)"
                b.isHidden = title.isEmpty
            }
        }
        let h = dlBox.arrangedSubviews.isEmpty
        if dlBox.isHidden != h { dlBox.isHidden = h; fit() }
    }

    @objc func downloadButton(_ b: NSButton) {
        guard let id = b.identifier?.rawValue else { return }
        if b.title == "RESUME" { Downloads.run(["resume", id]); b.title = "…" }
        else if b.title == "STOP" { Downloads.run(["stop", id]); b.title = "…" }
    }
}
