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

final class SpeedBrowser: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static var shared: SpeedBrowser?
    static let home = URL(string: "https://www.speedtest.net/")!

    let window: NSWindow
    let web: WKWebView
    let status = NSTextField(labelWithString: "")

    static func open() {
        if let b = shared { b.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "speedtest.net"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 520, height: 420)
        window.level = .floating                       // above ordinary windows, under the stripe (layer 25)

        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.translatesAutoresizingMaskIntoConstraints = false

        // one thin bar under the page: back, reload, home, and how many ad lists are on
        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self, action: action)
            b.isBordered = false
            b.toolTip = tip
            b.setAccessibilityLabel(tip)
            return b
        }
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = "Ad blocking: loading the lists…"
        let bar = NSStackView(views: [button("chevron.left", "Back", #selector(back)), button("arrow.clockwise", "Reload", #selector(reload)),
                                      button("house", "speedtest.net", #selector(goHome)),
                                      button("eye", "The whole page, or only the test frame", #selector(toggleFull)), status])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(web)
        content.addSubview(bar)
        window.contentView = content
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: content.topAnchor),
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: web.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 26),
        ])

        // on the screen of the stripe, centred
        if let s = (NSApp.windows.first { $0 is NSPanel && $0.isVisible })?.screen ?? NSScreen.main {
            let f = s.visibleFrame
            let w = min(820, f.width - 40), h = min(600, f.height - 40)
            window.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: false)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appendLog("\(logStamp()) SPEEDTEST browser opened")

        // the page loads only after the blocking rules are in, so no ad is ever fetched
        AdBlock.install(into: config.userContentController) { [weak self] on, rules in
            guard let self = self else { return }
            self.status.stringValue = on.isEmpty ? "Ad blocking: no list could be loaded" : "Ad blocking on: \(on.joined(separator: ", ")) (\(rules) rules)"
            self.web.load(URLRequest(url: SpeedBrowser.home))
        }
    }

    @objc func back() { if web.canGoBack { web.goBack() } }
    @objc func reload() { web.reload() }
    var full = false
    @objc func toggleFull() {
        full.toggle()
        web.evaluateJavaScript("window.ckFull = \(full); window.ckTidy && window.ckTidy()")
    }
    @objc func goHome() { web.load(URLRequest(url: SpeedBrowser.home)) }

    // a link meant for a new window opens in this one
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.title = webView.title?.isEmpty == false ? webView.title! : "speedtest.net"
    }

    func windowWillClose(_ notification: Notification) {
        web.stopLoading()
        web.loadHTMLString("", baseURL: nil)           // the test stops when the window closes; no data spent after
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
