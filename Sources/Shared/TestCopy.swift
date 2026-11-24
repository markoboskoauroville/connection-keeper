// THE TEST COPY TOUCHES NOTHING (request 108, Marko 24.11.2026 01:45: "make a special test mode when you can go through
// Wi-Fi, normal Mac connection, and test all the drops without dropping yourself from the internet. Do not cut the branch
// you are sitting on, please").
//
// A ck-aggregate started with CK_AGG_TEST (by `ck-test start`, Tools/ck-test) is a copy under test. Before request 108 it
// still wrote the live folder's nothing-only-state and aggregate-speeds.json and could switch the phone's Wi-Fi off over
// adb. Now, mechanically:
//   - Paths.support is the copy's own folder (CK_AGG_STATE, else a fresh temporary one): every file it writes is its own;
//   - every program it starts goes through shell(), and shell() refuses here anything that changes the Mac or a phone:
//     only the reading commands below run (adb devices / getprop / dumpsys / cat ..., networksetup -list / -get, route get,
//     ifconfig -l, ipconfig get..., arp -n, curl, ping, lsof, nettop, shasum). A refusal is logged "TEST COPY REFUSED".
//   - ck-test runs it under sandbox-exec with every write outside its folder denied (a second wall, in the kernel).
import Foundation

let ckTestCopy = ProcessInfo.processInfo.environment["CK_AGG_TEST"] != nil

enum TestCopy {
    // nil: allowed; else the reason it is refused.
    static func refusal(_ path: String, _ args: [String]) -> String? {
        guard ckTestCopy else { return nil }
        let tool = (path as NSString).lastPathComponent
        switch tool {
        case "curl", "ping", "lsof", "nettop", "shasum", "arp", "scutil", "sw_vers", "pgrep", "ps", "system_profiler", "ioreg", "networkQuality":
            return nil
        case "ipconfig":
            return args.first.map { $0.hasPrefix("get") } == true ? nil : "ipconfig \(args.first ?? "")"
        case "ifconfig":
            return args.isEmpty || args == ["-l"] || (args.count == 1 && !args[0].hasPrefix("-")) ? nil : "ifconfig with changes"
        case "route":
            return args.contains("get") && !args.contains(where: { ["add", "delete", "change", "flush"].contains($0) }) ? nil : "route \(args.first ?? "")"
        case "networksetup":
            guard let a = args.first else { return "networksetup" }
            return a.hasPrefix("-list") || a.hasPrefix("-get") || a.hasPrefix("-print") ? nil : "networksetup \(a)"
        case "launchctl":
            return args.first == "print" || args.first == "list" ? nil : "launchctl \(args.first ?? "")"
        case "adb":
            return adbRefusal(args)
        default:
            return tool                                   // anything else: not needed by a copy under test
        }
    }

    static func adbRefusal(_ all: [String]) -> String? {
        var a = all
        if a.first == "-s", a.count >= 2 { a.removeFirst(2) }
        guard let verb = a.first else { return "adb" }
        switch verb {
        case "devices", "get-state", "get-serialno", "version": return nil
        case "forward": return a.count == 2 && a[1] == "--list" ? nil : "adb forward"
        case "shell":
            let cmd = a.dropFirst().joined(separator: " ")
            let lower = cmd.lowercased().replacingOccurrences(of: "2>/dev/null", with: "")
            for bad in ["put ", "set-", "svc ", "kill", "setsid", "nohup", "chmod", "rm ", "reboot", "enable", "disable", "input ",
                        "am ", "pm ", "start", "stop", ">", "mv ", "cp "] where lower.contains(bad) {
                return "adb shell \(cmd.prefix(40))"
            }
            let first = cmd.split(separator: " ").first.map(String.init) ?? ""
            let readers = ["getprop", "dumpsys", "cat", "echo", "sha256sum", "pgrep", "ip", "ls"]
            if readers.contains(first) || cmd.hasPrefix("cmd wifi status") || cmd.hasPrefix("cmd phone get-") { return nil }
            return "adb shell \(cmd.prefix(40))"
        default: return "adb \(verb)"
        }
    }
}
