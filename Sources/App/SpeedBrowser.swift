// THE SPEEDOMETER OPENS SPEEDTEST.NET IN THE APP'S OWN BROWSER (v57, request 76, Marko 14.11.2026: "It needs to do a
// different action. Remove whatever is doing now ... open up in its own browser, so the browser must be encoded in this
// application ... https://www.speedtest.net/ ... it must have already built-in the plugin to block commercials. ublock").
// The browser is the Mac's own WebKit (WKWebView), inside the app: no Firefox, no Chrome, nothing to download.
// Chromium (CEF) was weighed and left: ~250 MB in every release, over a SIM line with no data left.
// The ad blocking is uBlock Origin's own default lists (uBlock filters, EasyList, Peter Lowe's), turned into WebKit
// content rules by Tools/make_adblock.py at build time (Resources/adblock/*.json); seed.json, written by hand, always
// compiles, so the page is never shown with ads even when a big list fails.
import AppKit
import WebKit

// v59 (request 78, Marko 14.11.2026: "a browser without any edges, only showing the middle frame ... I don't want to have
// any margin, just useful information on screen"): no title bar, no bottom bar; frame.js measures the frame (GO, the
// speeds, the line, Telemach) and posts its size; the window takes exactly that size plus a 12 pt edge and the page is
// scrolled so the frame sits in it. Esc closes, Cmd-drag moves, Cmd-R reloads, a second press on the speedometer closes.
final class EdgelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { close(); return }
        if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "r" { SpeedBrowser.shared?.web.reload(); return }
        super.keyDown(with: e)
    }
    override func sendEvent(_ e: NSEvent) {
        if e.type == .leftMouseDown, e.modifierFlags.contains(.command) { performDrag(with: e); return }
        if e.type == .keyDown, e.keyCode == 53 { close(); return }
        if e.type == .keyDown, e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "r" { SpeedBrowser.shared?.web.reload(); return }
        super.sendEvent(e)
    }
}

// v82 (request 91, Marko 14.11.2026: "update this speed testing small web page. Please make it draggable with the mouse, so
// I can drag it anywhere I like"): a thin grip bar on top of the page (the page itself takes the mouse, so a drag on it
// tests the page, not the window): a drag anywhere on the bar moves the window, ✕ at its right end closes. The place is
// kept (screen + top-left) between opens and is never pushed back by the app; the page's own size changes keep the
// top-left corner.
final class GripBar: NSView {
    static let height: CGFloat = 16
    var onClose: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); bounds.fill()
        NSColor(calibratedWhite: 0.45, alpha: 1).setFill()
        let w: CGFloat = 36
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - w / 2, y: bounds.midY - 1.5, width: w, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        let x = NSAttributedString(string: "✕", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1)])
        x.draw(at: NSPoint(x: bounds.maxX - 16, y: (bounds.height - x.size().height) / 2))
    }
    var closeRect: NSRect { NSRect(x: bounds.maxX - 22, y: 0, width: 22, height: bounds.height) }
    override func resetCursorRects() {
        addCursorRect(bounds.insetBy(dx: 0, dy: 0).divided(atDistance: bounds.width - 22, from: .minXEdge).slice, cursor: .openHand)
        addCursorRect(closeRect, cursor: .pointingHand)
    }
    override func mouseDown(with e: NSEvent) {
        if closeRect.contains(convert(e.locationInWindow, from: nil)) { onClose?(); return }
        NSCursor.closedHand.push()
        window?.performDrag(with: e)
        NSCursor.pop()
    }
}

enum SpeedPlace {
    static let key = "speedWindowPlace"
    static func save(_ w: NSWindow) {
        guard let s = w.screen else { return }
        let f = w.frame
        UserDefaults.standard.set(["screen": s.localizedName, "x": f.minX - s.frame.minX, "top": s.frame.maxY - f.maxY], forKey: key)
    }
    // the saved top-left, only when that display is still there and the grip would be on it
    static func restore(_ w: NSWindow) -> Bool {
        guard let p = UserDefaults.standard.dictionary(forKey: key), let name = p["screen"] as? String,
              let x = p["x"] as? Double, let top = p["top"] as? Double,
              let s = NSScreen.screens.first(where: { $0.localizedName == name }) else { return false }
        let origin = NSPoint(x: s.frame.minX + x, y: s.frame.maxY - top - w.frame.height)
        let grip = NSRect(x: origin.x, y: origin.y + w.frame.height - GripBar.height, width: w.frame.width, height: GripBar.height)
        guard s.frame.intersection(grip).width >= 60 else { return false }
        w.setFrameOrigin(origin)
        return true
    }
}

final class SpeedBrowser: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static var shared: SpeedBrowser?
    static let home = URL(string: "https://www.speedtest.net/")!
    static let edge: CGFloat = 12

    let window: EdgelessWindow
    let web: WKWebView

    static func open() {
        if let b = shared { b.window.close(); return }          // the speedometer again: closed
        shared = SpeedBrowser()
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // speedtest.net's consent and settings are kept between opens
        // v58 (request 77): only the test frame (GO, download, upload, the line, Telemach); Resources/speedtest/frame.js
        if let u = Bundle.main.resourceURL?.appendingPathComponent("speedtest/frame.js"), let js = try? String(contentsOf: u, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: config)
        window = EdgelessWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        config.userContentController.add(self, name: "ckFrame")
        window.title = "speedtest.net"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating                       // above ordinary windows, under the stripe (layer 25)
        window.backgroundColor = .black
        window.hasShadow = true
        window.isOpaque = false
        // v82: the grip bar on top, the page under it
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 520 + GripBar.height))
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.masksToBounds = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        let grip = GripBar(frame: NSRect(x: 0, y: 520, width: 760, height: GripBar.height))
        grip.autoresizingMask = [.width, .minYMargin]
        web.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        web.autoresizingMask = [.width, .height]
        box.addSubview(web); box.addSubview(grip)
        window.setContentSize(box.frame.size)
        window.contentView = box
        grip.onClose = { [weak self] in self?.window.close() }
        web.navigationDelegate = self
        web.uiDelegate = self
        web.underPageBackgroundColor = .black

        // where he left it last time (v82); else on the screen of the stripe, centred
        if !SpeedPlace.restore(window), let s = (NSApp.windows.first { $0 is NSPanel && $0.isVisible })?.screen ?? NSScreen.main {
            let f = s.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.midX - 380, y: f.midY - 260))
        }
        window.alphaValue = 0                          // shown once the frame has been measured: no flash of the page
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appendLog("\(logStamp()) SPEEDTEST browser opened")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.window.alphaValue = 1 }   // never left invisible

        // the page loads only after the blocking rules are in, so no ad is ever fetched
        AdBlock.install(into: config.userContentController) { [weak self] on, rules in
            appendLog("\(logStamp()) ADBLOCK on: \(on.joined(separator: ", ")) (\(rules) rules)")
            self?.web.load(URLRequest(url: SpeedBrowser.home))
        }
    }

    // frame.js: {w, h} of the frame in CSS pixels; the window keeps its top-left corner
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let w = (d["w"] as? NSNumber)?.doubleValue, let h = (d["h"] as? NSNumber)?.doubleValue, w > 40, h > 40 else { return }
        let size = NSSize(width: ceil(w) + 2 * SpeedBrowser.edge, height: ceil(h) + 2 * SpeedBrowser.edge + GripBar.height)
        let f = window.frame
        if abs(f.width - size.width) > 2 || abs(f.height - size.height) > 2 {
            window.setFrame(NSRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
        }
        window.alphaValue = 1
    }

    // a link meant for a new window opens in this one
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    func windowDidMove(_ notification: Notification) { SpeedPlace.save(window) }   // v82: his place, kept

    func windowWillClose(_ notification: Notification) {
        SpeedPlace.save(window)
        web.stopLoading()
        web.loadHTMLString("", baseURL: nil)           // the test stops when the window closes; no data spent after
        web.configuration.userContentController.removeScriptMessageHandler(forName: "ckFrame")
        SpeedBrowser.shared = nil
    }
}

// The rule lists in Resources/adblock, compiled by WebKit once per version and kept in its store.
enum AdBlock {
    static let lists = [("seed", "seed"), ("network", "uBlock network"), ("cosmetic", "uBlock cosmetic")]

    static func install(into ucc: WKUserContentController, done: @escaping (_ on: [String], _ rules: Int) -> Void) {
        guard let store = WKContentRuleListStore.default(),
              let dir = Bundle.main.resourceURL?.appendingPathComponent("adblock") else { done([], 0); return }
        var on: [String] = [], rules = 0, left = lists.count
        func finished() { left -= 1; if left == 0 { done(lists.map { $0.1 }.filter { on.contains($0) }, rules) } }
        for (file, label) in lists {
            let url = dir.appendingPathComponent("\(file).json")
            guard let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) else { finished(); continue }
            let count = (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? 0
            let id = "ck-adblock-\(file)-v\(CKVersion)-\(data.count)"
            let add: (WKContentRuleList?) -> Void = { list in
                DispatchQueue.main.async {
                    if let list = list { ucc.add(list); on.append(label); rules += count }
                    finished()
                }
            }
            store.lookUpContentRuleList(forIdentifier: id) { found, _ in
                if let found = found { add(found); return }
                store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                    if let error = error { appendLog("\(logStamp()) ADBLOCK \(file) did not compile: \(error.localizedDescription)") }
                    add(list)
                }
            }
        }
    }
}

// H, THE HELP (v60, request 82, Marko 14.11.2026: "infographics explaining all the parts of the user interface ... using
// the same ... browser to show itself ... quickly, I can see what each icon does and how to use this app"): the page is
// Resources/help/index.html inside the app, shown in the same edgeless WebKit window; H again or Esc closes it.
final class HelpBrowser: NSObject, NSWindowDelegate {
    static var shared: HelpBrowser?
    let window: EdgelessWindow
    let web: WKWebView

    static func toggle() {
        if let h = shared { h.window.close(); return }
        shared = HelpBrowser()
    }

    override init() {
        web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        window = EdgelessWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.title = "Connection Keeper: help"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.backgroundColor = .black
        window.hasShadow = true
        window.contentView = web
        web.wantsLayer = true
        web.layer?.cornerRadius = 10
        web.layer?.masksToBounds = true
        web.underPageBackgroundColor = .black
        if let s = (NSApp.windows.first { $0 is NSPanel && $0.isVisible })?.screen ?? NSScreen.main {
            let f = s.visibleFrame
            let w = min(980, f.width - 40), h = min(720, f.height - 40)
            window.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: false)
        }
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("help") {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appendLog("\(logStamp()) HELP opened")
    }

    func windowWillClose(_ notification: Notification) { HelpBrowser.shared = nil }
}

extension Stripe {
    @objc func helpPressed() { HelpBrowser.toggle() }
}
