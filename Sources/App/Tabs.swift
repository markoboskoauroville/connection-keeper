// TWO TABS (v54, Marko 13.11.2026: "I want to have a very simple user interface ... two tabs. There will be all connections
// on the first tab, and the second tab will be connections in use. I can see everything which phone can see, and then I
// can see what is actually in use"). ALL: every connection the Mac sees (its own Wi-Fi networks in range, each cable,
// each phone) with one short state word: IN USE, READY, NO DATA, AIRPLANE, VIA WI-FI, SAME UPLINK, NO NET, and the
// stacked signal meters. IN USE (the default): only the lines carrying traffic now (the joined ones, or the one the
// internet goes through), each with its meters and live speed; the first row is the total. A line that loops never
// appears there.
import AppKit

extension Stripe {
    @objc func pickTabAll() { setTab("all") }
    @objc func pickTabUse() { setTab("inuse") }

    func setTab(_ t: String) {
        guard t != tab else { return }
        tab = t
        UserDefaults.standard.set(t, forKey: "linesTab")
        showTabs()
        layoutLines()
        fit()
    }

    func showTabs() {
        tabAll.contentTintColor = tab == "all" ? Ink.green : Ink.grey
        tabUse.contentTintColor = tab == "inuse" ? Ink.green : Ink.grey
        tabAll.setAccessibilityValue(tab == "all" ? "on" : "off"); tabUse.setAccessibilityValue(tab == "inuse" ? "on" : "off")
    }

    func layoutAll() {
        guard let column = panel.contentView?.subviews.first as? NSStackView, let anchor = aggRow else { return }
        let show = tab == "all"
        if show { refreshWifiScan() }
        let joinedNow = Set(agg?.lines.filter(\.alive).map(\.device) ?? [])
        var want: [(key: String, name: String, state: String, color: NSColor)] = []
        for o in others {
            let inUse = Aggregation.on ? joinedNow.contains(o.iface) : o.iface == iface
            var st = "READY", c = Ink.text
            if inUse { st = "IN USE"; c = Ink.green }
            else if let s = o.sameAs { st = s; c = Ink.grey }
            else if deadIfaces.contains(o.iface) { st = "NO DATA"; c = Ink.amber }
            else if o.ms == nil { st = "NO NET"; c = Ink.grey }
            want.append(("dev:" + o.iface, Net.shown(o.name, o.iface), st, c))
        }
        let have = Set(others.map(\.name))
        for n in wifiScan where !have.contains(n) { want.append(("wifi:" + n, n, "READY", Ink.dim)) }
        var changed = false
        let lead = gear.fittingSize.width + rescan.fittingSize.width + expand.fittingSize.width + 9, nameW = connectionWidth()
        for w in want where allRows[w.key] == nil {
            let r = LineRow(leadWidth: lead, nameWidth: nameW)
            r.dot.isHidden = true
            r.view.isHidden = !show
            allRows[w.key] = r
            column.insertArrangedSubview(r.view, at: column.arrangedSubviews.firstIndex(of: anchor.view) ?? column.arrangedSubviews.count - 1)
            changed = true
        }
        for (k, r) in allRows where !want.contains(where: { $0.key == k }) {
            column.removeArrangedSubview(r.view); r.view.removeFromSuperview(); allRows[k] = nil; changed = true
        }
        for w in want {
            guard let r = allRows[w.key] else { continue }
            if r.name.stringValue != w.name { r.name.stringValue = w.name }
            r.name.textColor = w.color
            r.info.stringValue = w.state; r.info.textColor = w.color
            if r.view.isHidden == show { r.view.isHidden = !show; changed = true }
        }
        if changed { fit() }
    }
}
