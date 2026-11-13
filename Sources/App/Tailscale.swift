// The Tailscale icon on the top row (v52): green running, amber a failing check or a restart in progress, red not healed
// after a restart, grey off / not installed. The guard itself lives in the keeper (Daemon/TailscaleGuard.swift).
import AppKit

extension Stripe {
    func tailscaleSummary() -> (NSColor, String) {
        guard let d = try? Data(contentsOf: Paths.support.appendingPathComponent("tailscale-state.json")),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return (Ink.grey, "Tailscale guard: no report yet (the keeper writes one every minute)") }
        let st = j["state"] as? String ?? "?"
        let at = (j["checked"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let t = at.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "?"
        let rs = (j["lastRestart"] as? String).flatMap { $0.isEmpty ? nil : ISO8601DateFormatter().date(from: $0) }
            .map { "last refresh " + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "never refreshed"
        let stale = at.map { Date().timeIntervalSince($0) > 300 } ?? true
        let color: NSColor = stale ? Ink.grey : st == "ok" ? Ink.green : st == "amber" ? Ink.amber : st == "red" ? Ink.red : Ink.grey
        return (color, "Tailscale: \(j["detail"] ?? "?"); checked \(t); \(rs)" + (stale ? " (the keeper has not reported for 5 minutes)" : ""))
    }
    func showTailscale() { let (c, s) = tailscaleSummary(); tsWord.contentTintColor = c; tsWord.toolTip = s }
    @objc func tsPressed() { let (c, s) = tailscaleSummary(); show(s, c, for: 10) }
}
