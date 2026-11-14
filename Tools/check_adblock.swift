// Compiles every ad-block list in <dir> with WebKit, as the app will (v57, request 76). A list WebKit refuses is cut in
// halves until the refused rules are found; those are dropped and the file is rewritten, so the app never meets a
// list that does not compile. Run by build.sh on GitHub's runner, before the app is signed.
//     swift Tools/check_adblock.swift <dir>
import Foundation
import WebKit

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("ck-adblock-check-\(getpid())")
try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
let store = WKContentRuleListStore(url: storeDir)!
var n = 0

func compiles(_ rules: [Any]) -> Bool {
    guard let d = try? JSONSerialization.data(withJSONObject: rules), let s = String(data: d, encoding: .utf8) else { return false }
    var ok: Bool?
    n += 1
    store.compileContentRuleList(forIdentifier: "check\(n)", encodedContentRuleList: s) { list, _ in ok = list != nil }
    while ok == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    store.removeContentRuleList(forIdentifier: "check\(n)") { _ in }
    return ok!
}

func good(_ rules: [Any]) -> [Any] {
    if rules.isEmpty || compiles(rules) { return rules }
    if rules.count == 1 { return [] }
    let half = rules.count / 2
    return good(Array(rules[..<half])) + good(Array(rules[half...]))
}

var failed = false
for f in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
    guard let d = try? Data(contentsOf: f), let rules = (try? JSONSerialization.jsonObject(with: d)) as? [Any] else {
        print("adblock check: \(f.lastPathComponent) is not a JSON list"); failed = true; continue
    }
    let kept = good(rules)
    if kept.count != rules.count {
        let out = try! JSONSerialization.data(withJSONObject: kept)
        try! out.write(to: f)
        print("adblock check: \(f.lastPathComponent): \(rules.count - kept.count) rules WebKit refused were dropped, \(kept.count) kept")
    } else {
        print("adblock check: \(f.lastPathComponent): \(kept.count) rules compile")
    }
    if f.lastPathComponent == "seed.json" && kept.count != rules.count { failed = true }
}
try? FileManager.default.removeItem(at: storeDir)
exit(failed ? 1 : 0)
