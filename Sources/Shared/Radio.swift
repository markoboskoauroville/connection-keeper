// THE PHONE'S RADIO (v43, request 60, Marko 1.11.2026: "A phone is for sure 5G or 4G, so I can remotely, through ADB,
// switch my quality of connection ... two buttons next to the Wi-Fi icon, 4G and 5G").
// Read: what the phone's own status bar shows for the SIM carrying data. Switch: Android's own
// `cmd phone set-allowed-network-types-for-users -s <slot> <bitmask>` from adb's shell (no root; the same setting as
// Settings → SIMs → Preferred network type), on the data SIM's slot. 5G = every type allowed; 4G = every type but NR
// (bit 19, TelephonyManager.NETWORK_TYPE_BITMASK_NR). Measured on the Pixel 7, 1.11.2026: 4G → LTE_CA in 6 s, 5G →
// NR_NSA in 8 s, the line stayed joined.
import Foundation

enum PhoneRadio {
    static let all = "11111111111111111111", noNR = "01111111111111111111"

    // A phone's radio as the phone itself shows it (Marko 1.11.2026: "They are on 5G. Don't make nonsense claims"):
    // telephony.registry per SIM ("Phone Id=N"); the SIM carrying data (mDataConnectionState=2) is the line's. Its
    // TelephonyDisplayInfo is what the status bar draws: network=LTE with overrideNetwork=NR_NSA is 5G NSA (an LTE anchor
    // with a 5G carrier), NR_ADVANCED 5G+, network=NR 5G SA, LTE_CA 4G+. The signal is read from the same SIM's block.
    static func read(_ s: String) -> [String: Any]? {
        guard let adb = Phones.adb else { return nil }
        var o: [String: Any] = [:]
        let reg = shell(adb, ["-s", s, "shell", "dumpsys", "telephony.registry"], timeout: 8).out
        let blocks = reg.components(separatedBy: "Phone Id=").dropFirst()
        guard let blk = blocks.first(where: { $0.contains("mDataConnectionState=2") }) ?? blocks.first else { return nil }
        let sim = Int(blk.prefix { $0.isNumber }) ?? 0
        o["sim"] = sim + 1
        func field(_ key: String, in text: Substring) -> String? {
            guard let r = text.range(of: key + "=") else { return nil }
            return String(text[r.upperBound...].prefix { $0 != "," && $0 != "}" && $0 != " " && $0 != "\n" })
        }
        func num(_ key: String, in text: Substring) -> Int? {
            guard let v = field(key, in: text), let i = Int(v), i != Int(Int32.max), i > -10000, i < 10000 else { return nil }
            return i
        }
        let b = Substring(blk)
        if let r = b.range(of: "mTelephonyDisplayInfo=") {
            let info = b[r.upperBound...].prefix { $0 != "\n" }
            let net = field("network", in: info) ?? "?", over = field("overrideNetwork", in: info) ?? "NONE"
            o["network"] = net; o["override"] = over
            o["type"] = net == "NR" ? "5G SA" : over == "NR_NSA" ? "5G NSA" : over == "NR_ADVANCED" ? "5G+" : over == "LTE_CA" ? "4G+ (LTE CA)" : net == "LTE" ? "4G LTE" : net
        }
        if let r = b.range(of: "mSignalStrength=") {
            let line = b[r.upperBound...].prefix { $0 != "\n" }
            if let nr = line.range(of: "CellSignalStrengthNr:") {
                let t = line[nr.upperBound...]
                if let v = num("ssRsrp", in: t) { o["nrRsrp"] = v }
                if let v = num("ssSinr", in: t) { o["nrSinr"] = v }
            }
            if let lte = line.range(of: "CellSignalStrengthLte:") {
                let t = line[lte.upperBound...]
                if let v = num("rsrp", in: t) { o["lteRsrp"] = v }
                if let v = num("rssnr", in: t) { o["lteSnr"] = v }
            }
        }
        let ops = shell(adb, ["-s", s, "shell", "getprop", "gsm.operator.alpha"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
        if sim < ops.count, !ops[sim].isEmpty { o["operator"] = ops[sim] }
        return o
    }


    // Is 5G (NR) allowed on the data SIM's slot now? nil when adb did not answer.
    static func allows5G(_ serial: String, slot: Int) -> Bool? {
        guard let adb = Phones.adb else { return nil }
        let r = shell(adb, ["-s", serial, "shell", "cmd", "phone", "get-allowed-network-types-for-users", "-s", "\(slot)"], timeout: 6)
        guard r.status == 0, r.out.contains("LTE") else { return nil }
        return r.out.contains("|NR")
    }

    @discardableResult
    static func set(_ serial: String, slot: Int, fiveG: Bool) -> Bool {
        guard let adb = Phones.adb else { return false }
        let r = shell(adb, ["-s", serial, "shell", "cmd", "phone", "set-allowed-network-types-for-users", "-s", "\(slot)", fiveG ? all : noNR], timeout: 8)
        return r.out.contains("completed")
    }

    // Everything the stripe shows for one phone: allowed 5G, the type on the status bar, the slot.
    static func state(_ serial: String) -> (fiveG: Bool?, shown: String, slot: Int)? {
        guard let r = read(serial) else { return nil }
        let slot = (r["sim"] as? Int ?? 1) - 1
        return (allows5G(serial, slot: slot), r["type"] as? String ?? "?", slot)
    }
}
