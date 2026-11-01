// 5G ONLY FOR BIG DOWNLOADS (v48, request 67, Marko 1.11.2026: "5G is only used after five minutes of constant
// downloading at the high speed then it speeds up and when the speed drops after five minutes you go back to 4G").
//
// The phones rest on 4G. When everything the server carries down stays at or above `boostMbps` for `boostAfter`
// seconds (5 min) without a break, every phone line is set to 5G. When it stays below `restMbps` for `backAfter`
// seconds (5 min), every phone goes back to 4G. A short dip does not count: each window starts again when the
// rate crosses back. The state is written to boost.json, so a restart of the server still brings the phones home.
// The probe of Balance.swift follows each switch, so the line's capacity is right a few seconds later.
//
// Test copy only: CK_AGG_BOOST_AFTER, CK_AGG_BOOST_BACK (seconds), CK_AGG_BOOST_MBPS shorten the windows.

import Foundation

let boostAfter = Double(aggEnv["CK_AGG_BOOST_AFTER"] ?? "") ?? 300
let backAfter = Double(aggEnv["CK_AGG_BOOST_BACK"] ?? "") ?? 300
let boostMbps = Double(aggEnv["CK_AGG_BOOST_MBPS"] ?? "") ?? 15     // a big download, not a web page or a call
let restMbps = boostMbps / 3
let boostFile = aggTestCopy ? URL(fileURLWithPath: NSTemporaryDirectory() + "ck-boost-test.json")
                            : Paths.support.appendingPathComponent("boost.json")

final class Boost {
    var on = false, highSince: Date?, lowSince: Date?
    struct Saved: Codable { let on: Bool; let at: Date; let reason: String }
    init() { on = (try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: boostFile)))?.on ?? false }
    func save(_ reason: String) { try? JSONEncoder().encode(Saved(on: on, at: Date(), reason: reason)).write(to: boostFile) }
}

extension Server {
    // Called once a second from the balance loop with what all the lines carry down together.
    func boostTick(_ boost: Boost, total: Double, phones: [Phone]) {
        let now = Date()
        if total >= boostMbps { boost.highSince = boost.highSince ?? now } else { boost.highSince = nil }
        if total < restMbps { boost.lowSince = boost.lowSince ?? now } else { boost.lowSince = nil }
        if !boost.on, let h = boost.highSince, now.timeIntervalSince(h) >= boostAfter, !phones.isEmpty {
            boost.on = true; boost.lowSince = nil
            let why = String(format: "%.0f s of downloading at %.0f Mbit/s or more (now %.0f)", boostAfter, boostMbps, total)
            boost.save(why); log("5G for the big download: \(why)")
            Thread.detachNewThread { setRadios(phones, fiveG: true) }
        } else if boost.on, let l = boost.lowSince, now.timeIntervalSince(l) >= backAfter {
            boost.on = false; boost.highSince = nil
            let why = String(format: "%.0f s below %.0f Mbit/s: the big download is over", backAfter, restMbps)
            boost.save(why); log("back to 4G: \(why)")
            Thread.detachNewThread { setRadios(phones, fiveG: false) }
        }
    }
}

func setRadios(_ phones: [Phone], fiveG: Bool) {
    for p in phones {
        let slot = PhoneRadio.state(p.serial)?.slot ?? 0
        let ok = PhoneRadio.set(p.serial, slot: slot, fiveG: fiveG)
        log("\(p.name): \(fiveG ? "5G" : "4G") \(ok ? "set" : "NOT set (adb did not answer)")")
    }
}
