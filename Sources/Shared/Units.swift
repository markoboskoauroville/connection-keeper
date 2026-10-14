// THE SPEED UNIT (v9, Marko 14.10.2026: "I want to have in settings the unit of measurement of speed. Different options
// or automatic, depending on the speed you go from kilobits to megabits ... any standard practices of measuring").
// Auto in bits (bit/s → kbit/s → Mbit/s → Gbit/s, the default) or in bytes (B/s → kB/s → MB/s → GB/s), or one fixed
// unit. Decimal steps of 1000, as networks count. Chosen in ⚙, remembered in the stripe's defaults.
//
// NO BREATHING (same request: "the whole status line is breathing ... a fixed number of places for numbers"): every
// number comes out in a slot of the same width, four significant digits right-aligned (" 9.87", " 98.7", "  987"),
// and every unit is padded to the widest one, so in a monospaced font the text never changes its width.
import Foundation

enum SpeedUnit: String, CaseIterable {
    case autoBits, autoBytes, bit, kbit, Mbit, Gbit, B, kB, MB, GB

    static let key = "speedUnit"
    static let changed = Notification.Name("ConnectionKeeperSpeedUnitChanged")
    static var current: SpeedUnit {
        get { UserDefaults.standard.string(forKey: key).flatMap(SpeedUnit.init) ?? .autoBits }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); NotificationCenter.default.post(name: changed, object: nil) }
    }

    var title: String {
        switch self {
        case .autoBits: return "Auto, bits (bit/s → kbit/s → Mbit/s)"
        case .autoBytes: return "Auto, bytes (B/s → kB/s → MB/s)"
        default: return name
        }
    }

    var name: String {
        switch self {
        case .autoBits, .bit: return "bit/s"
        case .kbit: return "kbit/s"
        case .Mbit: return "Mbit/s"
        case .Gbit: return "Gbit/s"
        case .autoBytes, .B: return "B/s"
        case .kB: return "kB/s"
        case .MB: return "MB/s"
        case .GB: return "GB/s"
        }
    }

    var isBits: Bool { [.autoBits, .bit, .kbit, .Mbit, .Gbit].contains(self) }

    // Units of one family, smallest first, with their size in that family's base (bit or byte).
    private var ladder: [(SpeedUnit, Double)] {
        isBits ? [(.bit, 1), (.kbit, 1e3), (.Mbit, 1e6), (.Gbit, 1e9)] : [(.B, 1), (.kB, 1e3), (.MB, 1e6), (.GB, 1e9)]
    }

    // The widest unit of the family, so every unit can be padded to it.
    var unitWidth: Int { isBits ? 6 : 4 }

    /// "  12.3 Mbit/s" — always the same number of characters for this setting.
    func format(bytesPerSecond: Double) -> String {
        let base = max(0, bytesPerSecond) * (isBits ? 8 : 1)
        var unit = ladder[0]
        switch self {
        case .autoBits, .autoBytes:
            for u in ladder where base >= u.1 * 0.9995 { unit = u }   // switch at 1000 of the smaller one
        default:
            unit = ladder.first { $0.0 == self } ?? ladder[0]
        }
        let v = base / unit.1
        let unitText = unit.0.name.padding(toLength: unitWidth, withPad: " ", startingAt: 0)
        return "\(SpeedUnit.slot(v)) \(unitText)"
    }

    /// Four significant digits in a slot of five characters, right-aligned; a fixed unit may need more and gets them.
    static func slot(_ v: Double) -> String {
        let s: String
        if v < 9.995 { s = String(format: "%.2f", v) }
        else if v < 99.95 { s = String(format: "%.1f", v) }
        else { s = String(format: "%.0f", v) }
        return String(repeating: " ", count: max(0, 5 - s.count)) + s
    }
}
