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

    // v60 (request 80, Marko 14.11.2026: "If I select it, only LAN connections are shown ... everything wired ... the Wi-Fi
    // icon ... shows me only Wi-Fi"): one filter at a time; the same icon again shows everything. Pressing one opens ALL.
    @objc func pickLanFilter() { setFilter(allFilter == "lan" ? "" : "lan") }
    @objc func pickWifiFilter() { setFilter(allFilter == "wifi" ? "" : "wifi") }
    func setFilter(_ f: String) {
        allFilter = f
        UserDefaults.standard.set(f, forKey: "allFilter")
        if tab != "all" { setTab("all") } else { showTabs(); layoutLines(); fit() }
        layoutAll()
    }

    // v60 (request 80: "When I click on the name, it should become green and become part of the aggregated connections
    // ... White means it's not in use. I click. Green means it's in use"): a click on a name in ALL ticks or unticks that
    // line for the aggregation (the same ticks as the ▾ JOIN list); with the first tick the aggregation comes on.
    @objc func allNameClicked(_ g: NSClickGestureRecognizer) {
        guard let key = (allRows.first { $0.value.name === g.view })?.key, key.hasPrefix("dev:") else {
            show("a Wi-Fi network in range: join it with WI-FI first; then it is a line here", Ink.amber, for: 6); return
        }
        let dev = String(key.dropFirst(4))
        guard let o = others.first(where: { $0.iface == dev }) else { return }
        if o.sameAs != nil || o.ms == nil {
            show("\(Net.shown(o.name, o.iface)): \(o.sameAs ?? "no internet through it"), it cannot join", Ink.amber, for: 6); return
        }
        // aggregation off: old ticks from an earlier run do not count; a click always joins (the Mac's line + this one)
        var sel = Aggregation.on ? Aggregation.selected : []
        let joining = !sel.contains(o.name)
        if joining {
            // the Mac's own line counts as ticked too while nothing was chosen yet
            if sel.isEmpty, let i = iface, i != Aggregation.tunnelDevice, i != o.iface { sel.append(Net.displayName(i)) }
            sel.append(o.name)
        } else { sel.removeAll { $0 == o.name } }
        let was = Aggregation.on
        Aggregation.selected = sel
        appendLog("\(logStamp()) ALL: \(o.name) \(joining ? "joined" : "left"); ticks \(sel.isEmpty ? "none" : sel.joined(separator: " + "))")
        if !was && joining && !Aggregation.on { switchMode(true) }
        else if was != Aggregation.on || sel.isEmpty {
            proxyDropped = false; serverMisses = 0
            let now = Aggregation.on
            DispatchQueue.global().async { let said = Aggregation.setMode(now); appendLog("\(logStamp()) AGGREGATION \(now ? "on" : "off"): " + said.joined(separator: "; ")) }
        }
        layoutAll()
        layoutLines()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.scanLines(); self.layoutAll() }
    }

    func showTabs() {
        lanFilter.contentTintColor = tab == "all" && allFilter == "lan" ? Ink.green : Ink.grey
        wifiFilter.contentTintColor = tab == "all" && allFilter == "wifi" ? Ink.green : Ink.grey
        lanFilter.setAccessibilityValue(allFilter == "lan" ? "on" : "off"); wifiFilter.setAccessibilityValue(allFilter == "wifi" ? "on" : "off")
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
        let ticked = Set(Aggregation.selected)
        for o in others {
            if allFilter == "lan" && o.wifi { continue }
            if allFilter == "wifi" && !o.wifi { continue }
            let inUse = Aggregation.on ? (joinedNow.contains(o.iface) || ticked.contains(o.name)) : o.iface == iface
            // v60: the name white = not in use, green = in use (a click toggles it); the state word keeps its colour
            var st = "READY", c = Ink.text
            if inUse { st = joinedNow.contains(o.iface) || !Aggregation.on ? "IN USE" : "JOINING"; c = Ink.green }
            else if let s = o.sameAs { st = s; c = Ink.grey }
            else if deadIfaces.contains(o.iface) { st = "NO DATA"; c = Ink.amber }
            else if o.ms == nil { st = "NO NET"; c = Ink.grey }
            if let w = roleWord(o.iface) {                        // v82 (request 91): NOTHING ONLY's roles
                st = w; c = w == "STANDBY" ? Ink.grey : w == "ACTIVE" ? Ink.green : w == "NO ANSWER" ? Ink.red : Ink.amber
            }
            want.append(("dev:" + o.iface, Net.shown(o.name, o.iface), st, c))
        }
        let have = Set(others.map(\.name))
        if allFilter != "lan" { for n in wifiScan where !have.contains(n) { want.append(("wifi:" + n, n, "READY", Ink.dim)) } }
        var changed = false
        let lead = gear.fittingSize.width + rescan.fittingSize.width + expand.fittingSize.width + 9, nameW = connectionWidth()
        for w in want where allRows[w.key] == nil {
            let r = LineRow(leadWidth: lead, nameWidth: nameW)
            r.dot.isHidden = true
            r.view.isHidden = !show
            r.name.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(allNameClicked(_:))))
            r.name.toolTip = "Click: join this line to the aggregation (green) or leave it (white)"
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
            r.name.textColor = w.color == Ink.green ? Ink.green : (w.color == Ink.text ? NSColor.white : w.color)
            r.info.stringValue = w.state; r.info.textColor = w.color
            if r.view.isHidden == show { r.view.isHidden = !show; changed = true }
        }
        if changed { fit() }
    }
}
