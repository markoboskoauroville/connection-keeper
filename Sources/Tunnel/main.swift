// ck-tunnel: the virtual device mantra_networkaggregate (v14, Marko 18.10.2026, request 33: "create virtual LAN device, so
// in the macOS I can select this device and macOS will not know about aggregation ... this device is doing aggregation",
// then "We can't pay ... we go with free helper"). A real Network Extension needs a paid Apple developer account; this
// is the free road: a root LaunchDaemon (installed once by `sudo ./tunnel.sh install`) that runs hev-socks5-tunnel (MIT,
// github.com/heiher/hev-socks5-tunnel) on the device utun99 and sends all IPv4 internet traffic into it with two half
// routes (0/1 and 128/1, in front of the default route, which stays as it is for the keeper). hev turns the packets into
// SOCKS5 connections to ck-aggregate on 127.0.0.1:8857, whose own sockets are bound to the real lines, so nothing loops.
//
// It follows a flag the stripe writes (the JOIN ticks): the flag present and the server answering = the device up; no
// flag, or the server silent three checks in a row = routes removed, the Mac straight on its lines again (fail-open: a
// dead server must never take the internet with it).
import Foundation
import Darwin

// --dir: where hev-socks5-tunnel is and the state goes (the installed place unless a test names another);
// --for N: a test run that ends by itself after N seconds, routes removed (nothing installed).
func arg(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
let dir = arg("--dir") ?? "/Library/PrivilegedHelperTools/com.mantra.connectionkeeper.tunnel"
let hevPath = dir + "/hev-socks5-tunnel", confPath = dir + "/hev.yml", statePath = dir + "/state"
let device = "utun99", address = "198.18.0.1"
let halves = ["0.0.0.0/1", "128.0.0.0/1"]

func log(_ s: String) {
    let f = ISO8601DateFormatter(); f.timeZone = .current
    FileHandle.standardError.write("\(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = pipe; p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: d, as: UTF8.self))
}

guard let home = arg("--home") else { log("usage: ck-tunnel --home /Users/<name> [--dir <folder>] [--for <seconds>]"); exit(2) }
let flag = home + "/Library/Application Support/connection-keeper/tunnel-on"
let endAt = arg("--for").flatMap(Double.init).map { Date().addingTimeInterval($0) }

// The server answers a TCP connect on 127.0.0.1:8857 within a second.
func serverAnswers() -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = UInt16(8857).bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    if r == 0 { return true }
    guard errno == EINPROGRESS else { return false }
    var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    guard poll(&p, 1, 1000) == 1 else { return false }
    var err: Int32 = 0; var len = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
    return err == 0
}

func routesPresent() -> Bool {
    let out = run("/usr/sbin/netstat", ["-rn", "-f", "inet"]).out
    return out.components(separatedBy: "\n").filter { $0.contains(device) && ($0.hasPrefix("0/1") || $0.hasPrefix("128.0/1")) }.count == 2
}

// THE MAIN LINE NEEDS ITS OWN ROAD (18.10.2026, the first test run): macOS gives every line but the main one a default
// route bound to its device (flag I); the main line (the cable, en17) has only the general default route, and the two
// half routes win over it, so the server's sockets bound to the cable found no road and the cable counted as dead the
// whole time the device was up. While up, every line with a router but no bound default route gets one.
var scoped: [String] = []

func addScopedDefaults() {
    for line in run("/usr/sbin/netstat", ["-rn", "-f", "inet"]).out.components(separatedBy: "\n") where line.hasPrefix("default") {
        let f = line.split(separator: " ").map(String.init)
        guard f.count >= 4, !f[2].contains("I"), let iface = f.last, iface != device, !iface.hasPrefix("utun"), !scoped.contains(iface) else { continue }
        if run("/sbin/route", ["-q", "-n", "add", "-ifscope", iface, "default", f[1]]).status == 0 {
            scoped.append(iface); log("\(iface): its own default route through \(f[1]) while the device is up")
        }
    }
}

func addRoutes() {
    addScopedDefaults()
    for h in halves { run("/sbin/route", ["-q", "-n", "add", "-net", h, "-interface", device]) }
}

func deleteRoutes() {
    for h in halves { run("/sbin/route", ["-q", "-n", "delete", "-net", h, "-interface", device]) }
    for i in scoped { run("/sbin/route", ["-q", "-n", "delete", "-ifscope", i, "default"]) }
    scoped = []
}

func writeState(_ s: String) {
    try? s.write(toFile: statePath, atomically: true, encoding: .utf8)
    chmod(statePath, 0o644)
}

var hev: Process?

func up() {
    let conf = """
    tunnel:
      name: \(device)
      mtu: 8500
      ipv4: \(address)
      icmp: 'off'
    socks5:
      port: 8857
      address: 127.0.0.1
      udp: 'udp'
    misc:
      log-file: stderr
      log-level: warn
      limit-nofile: 65535
    """
    try? conf.write(toFile: confPath, atomically: true, encoding: .utf8)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: hevPath); p.arguments = [confPath]
    do { try p.run() } catch { log("hev-socks5-tunnel did not start: \(error)"); return }
    hev = p
    for _ in 0..<50 where run("/sbin/ifconfig", [device]).status != 0 { usleep(100_000) }
    addRoutes()
    log("UP: \(device) carries the internet (mantra_networkaggregate)")
    writeState("on \(device)")
}

func down(_ why: String) {
    deleteRoutes()
    if let p = hev, p.isRunning { p.terminate(); p.waitUntilExit() }
    hev = nil
    log("DOWN: \(why); the Mac is straight on its lines")
    writeState("off")
}

for s in [SIGTERM, SIGINT] {
    signal(s, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: s, queue: .global())
    src.setEventHandler { down("stopped"); exit(0) }
    src.resume()
    _ = Unmanaged.passRetained(src)   // kept for the life of the process
}

log("ck-tunnel started, flag \(flag)")
deleteRoutes()                         // a crash may have left them
writeState("off")
var misses = 0
while true {
    if let endAt, Date() >= endAt { down("the test run is over"); exit(0) }
    let want = FileManager.default.fileExists(atPath: flag)
    let answers = want ? serverAnswers() : false
    misses = answers ? 0 : misses + 1
    if let p = hev {
        if !p.isRunning { down("hev-socks5-tunnel stopped (status \(p.terminationStatus))") }
        else if !want { down("aggregation off") }
        else if misses >= 3 { down("the aggregation server does not answer") }
        else if !routesPresent() { addRoutes(); log("routes were gone (a network change): added again") }
        else { addScopedDefaults() }                   // a line that became the main one meanwhile
    } else if want && answers {
        up()
    }
    sleep(2)
}
