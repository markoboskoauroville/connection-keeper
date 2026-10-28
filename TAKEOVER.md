# connection-keeper: takeover

**Version v10** (14.10.2026) · repository markoboskoauroville/connection-keeper (private) · artefact `10-connection-keeper-v10.zip`, tag `v10`
The reasons behind the choices are in [LESSONS.md](LESSONS.md).

## What it is

Marko has two access points, `mantra` and `Something` (the SSIDs exactly as the Mac's preferred networks list
them). When one loses the internet the Mac stays on it, so nothing works until somebody switches by hand. The
keeper does the switching, and the stripe shows what is happening and lets him switch himself.

## The model

| What | Where |
|---|---|
| The list of connections, interval, probes, dry run | `~/.config/connection-keeper.json` (written by the gear; the keeper re-reads it every 2 s) |
| The keeper's state, heartbeat every 2 s | `~/Library/Application Support/connection-keeper/state.json` |
| A request from the stripe (`switch` / `check`) | `…/connection-keeper/command.json`, taken and deleted by the keeper |
| The red alert after an automatic failover (v4): `{from, to, at, how, simulated}` | `…/connection-keeper/failover-alert.json` |
| One keeper only | `…/connection-keeper/keeper.lock` (flock) |
| The log | `~/Library/Logs/connection-keeper.log` (launchd's stderr: `connection-keeper.err.log`) |
| The LaunchAgent | `~/Library/LaunchAgents/com.mantra.connectionkeeper.plist`, label `com.mantra.connectionkeeper` |

A connection is `{kind, name, interface?, enabled}`. Only `kind: "wifi"` has a driver in v1; any other kind stays in
the list and is skipped with a log line. A new kind (ethernet, USB, iPhone tether) is one `Driver` in
`Sources/Daemon/main.swift` and one entry in `drivers`; the ladder does not change.

**The check:** `ping -c 3 1.1.1.1`; if it fails, `http://captive.apple.com/hotspot-detect.html` must answer
"Success". A page that answers with something else is a captive portal (offline). Online when either passes.

**The ladder, when offline:** two retries 15 s apart → rejoin the current SSID → each other enabled connection in
order → Wi-Fi power off 5 s and on → each enabled Wi-Fi again → back off 60, 120, 240 s … up to the interval.
Every step is logged; a change of network that brings the internet back is logged as `FAILOVER a -> b` and shown
on the stripe. It does not switch back to the first network while the second works (no flapping).

## Joining a Wi-Fi (v5)

`Join.wifi` in `Sources/Shared/Join.swift` is the only way in, for the keeper's ladder, the drop-down and the speed
test. In order: `networksetup -setairportnetwork` alone; then with the password from the login keychain (service
`com.mantra.connectionkeeper.wifi`, account = SSID, set in Settings → Password…, readable by the app and the keeper
without a prompt); then Control Centre's Wi-Fi list pressed through the accessibility API (identifiers
`com.apple.menuextra.controlcenter`, `controlcenter-wifi`, `wifi-network-<SSID>`; only when `AXIsProcessTrusted()`).
Each step is believed only when `ipconfig getsummary` names the SSID and the interface has an address. The detail
string says which step worked or why each failed. In the keeper the join runs on a second thread so the heartbeat
keeps beating.

The drop-down joins from the stripe itself, at once, keeper or not, with the keeper's checks held
(`speedtest.hold`); the keeper looks again as soon as a hold ends. It never raises the red alert.

**NO OTHER CONNECTION:** when the ladder ends with nothing working, the keeper's phase begins with
`NO OTHER CONNECTION` (`noOtherPrefix`) and the log says so; the stripe shows the phase bold red, wide, dot red, until
`online()` sets the phase back to `ok`.

## Always on top and the Control Centre road (v6)

`OnTop` (stripe's UserDefaults key `alwaysOnTop`, default true): on = window level `.statusBar` (25) with
`canJoinAllSpaces, fullScreenAuxiliary, stationary`; off = level `.normal`. ⚙ has the checkbox; a notification applies
it at once. Measured: layer 25 on, 0 off.

Control Centre does not open over a full-screen app (nothing over full-screen iTerm, the panel at once with Finder in
front), so `ControlCenterWifi.click`/`list` bring Finder forward, act, close the panel and give the front back to the
app that had it. `--check-join` (run with `open -n … --args --check-join` so the app's own Accessibility permission is
what counts, not the terminal's) logs `CHECK join path: accessibility granted; Control Centre Wi-Fi list read: mantra,
Something; stored passwords: …` and presses nothing. The Accessibility permission survived the rebuilds (stable
"Mantra Apps" signature).

## The stripe's layout (v7)

Labels have a maximum width, not a fixed one (`label(max)`, hugging required); a dim "|" label sits between the items;
`fit()` runs on every refresh and resizes the panel only when the fitting width changed, keeping the left edge.
`keepOnScreen()` (at start and after every fit) moves the stripe to the top middle of the main screen when less than
80 points of it are on any screen and logs it.

## Internet speed only (v10)

`Traffic.internet(iface)` (Net.swift) runs `nettop -x -n -L 1 -m route` (about 10 ms) once a second off the main thread
and sums bytes_in / bytes_out of the routes whose destination is `default` on the interface of the default route
(IPv4 and IPv6). Those counters carry only traffic to the internet, TCP and UDP; the local subnet has its own route
("192.168.1/24 -> en0") and the router its host route, neither counted. Measured 14.10.2026: a 20 MB download +20.4 MB
on the default route, 3 MB of UDP to 1.1.1.1 +3.08 MB, a 150 MB adb push to the phone (3.6–3.9 MB/s on en0) 0–26 kB/s
on the default route (the rest of the Mac's internet). A route made again after a network change starts at 0: that
second shows nothing. `Traffic.counters` (all of en0) is no longer used by the stripe.

## Fixed widths and the speed unit (v9)

The stripe's order is dot · ⚙ · connection ▾ | speed | ping | data | status | failover [OK]. Every item has an
*equal* width constraint (v7 had a maximum, which let the stripe change width with every number): the connection gets
the longest name in the list, speed the widest text of the chosen unit (`speedSample()`), ping "ping 999 ms", data
"888.8 GB left · 88:88", status "checked 59 min ago ✓", failover "failover 59 min ago". The width changes only with
the state (red alert, NO OTHER CONNECTION, a message on the status line), and the left edge stays, so ⚙ never moves.
Numbers are in `monospacedSystemFont`, four significant digits in a five-character slot (`SpeedUnit.slot`).
`Sources/Shared/Units.swift`: `SpeedUnit` (stripe's defaults key `speedUnit`, default `autoBits`), decimal steps of
1000, the unit padded to the family's widest. Measured 14.10.2026: three shots 3 s apart, 956 points each (bits),
926 each (bytes). Settings: `sizeToContent()` after every rebuild; NSStackView's fittingSize leaves out the right
inset when one row is wider than the rest, so the width is the widest row plus both insets.

## The data balance (v8)

`Sources/App/DataBalance.swift`. The stripe's item `data` (between ping and the status) shows
`…/connection-keeper/data-balance.json` (written at every successful check, read at start): "%.1f GB left · HH:MM",
the time from Telemach's SMS; amber < 10 GB, red < 2 GB, red with the failover alert. A click (or ⚙ → Check data, or
`--check-data` at launch) runs `~/.local/bin/router-sms balance --json` on a background thread, timeout 150 s, and
logs `DATA balance asked` and `DATA … MB left of … (N s from the click)` or `DATA balance FAILED: why` (the item then
says "data ✗" in red for 30 s, the reason in its tooltip). The automatic check: UserDefaults `dataBalanceEveryHours`,
0 = off (the default), checked every minute against the file's age. The SMS itself is done by router-sms
(~/Developer/ROUTER_SMS, its own TAKEOVER): a headless Firefox of its own logs in to the router at 192.168.1.1,
sends STANJE to 13880 and parses the reply; its warm server (LaunchAgent com.mantra.routersms, 127.0.0.1:8880) keeps
the login, so a check is the SMS's own time plus a few seconds.

## The red alert (v4)

When `attempt()` brings the internet back on a different connection and the switch was not asked from the stripe
(`manual` is false), the keeper writes `failover-alert.json` (`raiseAlert`). `from` is the connection that died, `at`
is when the check first found it offline. A second failover keeps the first `from`; a failover back onto `from`
deletes the file. `online()` also deletes it when the keeper is healthy on `from` again (`clearAlertIfHome`).
The stripe reads the file every second (`applyAlert`): every word red, the dot red, the failover field in bold
"mantra died 09:41 → on Something" (wider), and an **OK** button; OK or a click on the red words deletes the file
and logs "ALERT acknowledged". Without the keeper, the stripe itself clears it when its own reading of the SSID is
`from`. A `simulated` alert (`connection-keeperd --simulate-failover [FROM TO]`) never clears by itself, only by OK.
Settings shows the line in red above the list when it opens.

## The screens

- **The stripe** (floating, all Spaces, dragged anywhere, position remembered): state dot (green running, amber
  dry run or recovering, red offline, grey keeper not running) · current connection ▾ (the drop-down: the list,
  Check now, Open the log, Quit) · ↓ ↑ speed of the interface carrying the default route, per second · ping ·
  last check, or the keeper's phase in amber while it works · time since the last failover · ⚙.
- **Settings** (⚙, or launch with `--settings`): the connections with on/off, ▲ ▼ ✕; "Add a Wi-Fi the Mac
  knows…" (the Mac's preferred networks); check interval in minutes; dry run; `v1`, a click opens the latest release.

## The dangerous parts

- The keeper changes the network: `networksetup -setairportnetwork` and `-setairportpower`. A wrong ladder cuts
  the Mac off. `--dry-run` (or "Dry run" in settings) makes every act a log line.
- `networksetup` answers status 0 even when it fails; the keeper treats any output as a refusal and then believes
  only the SSID (`ipconfig getsummary`) and an IP address.
- The manual switch from the stripe joins directly when the keeper is not running.

## The files

| File | What |
|---|---|
| `Sources/Shared/Model.swift` | version, paths, Config, KeeperState, KeeperCommand |
| `Sources/Shared/Net.swift` | shell helper, SSID/route/preferred networks, join, power, probe, traffic counters |
| `Sources/Shared/Join.swift` | v5: the join road (networksetup, stored password, Control Centre), the keychain item |
| `Sources/Daemon/main.swift` | the keeper: drivers, the ladder, the loop, the lock |
| `Sources/App/main.swift` | the stripe |
| `Sources/App/Settings.swift` | the gear's window |
| `Sources/Shared/Units.swift` | v9: the speed unit and the fixed number slots |
| `Sources/App/DataBalance.swift` | v8: the data balance through `router-sms` |
| `Tools/make_icon.swift` | the icon, drawn in code, version under the symbol |
| `Resources/Info.plist` | bundle (LSUIElement: no Dock icon) |
| `launchd/com.mantra.connectionkeeper.plist` | the LaunchAgent template |
| `build.sh` / `agent.sh` | build + sign + install / load, unload, status |

## Building

`./build.sh`: both binaries with swiftc, the icon, signed "Mantra Apps", installed in
`/Applications/Connection Keeper (Mantra).app` (the keeper is `Contents/MacOS/connection-keeperd`), zipped as
`build/N-connection-keeper-vN.zip`. A new version: raise `CKVersion` in `Model.swift`, build, tag `vN`, release the
zip, delete the release before last.

Test the ladder without touching the network:

```
"/Applications/Connection Keeper (Mantra).app/Contents/MacOS/connection-keeperd" --simulate-offline --fast --once
```

## What has never been proven

- **The automatic data check has never fired** (off by default); amber and red for the data item were never seen
  (28.2 GB left). Proven 14.10.2026: two real checks from the stripe, 12:58 and 13:00, 28837.12 MB left.

- **A join with a stored password and a join through Control Centre from the app have never run.** Marko has not
  typed the passwords yet and the app had no Accessibility permission (granted later on 14.10.2026; v6's `--check-join` read the Wi-Fi list at 11:19, still never pressed a row from the app). Proven: networksetup alone fails
  on macOS 15 (live test, see LESSONS), a pressed Control Centre row switches at once (done by hand through
  accessibility from the terminal, 10:06), the drop-down answers at once with the reason ("not in range"), the
  NO OTHER CONNECTION line seen red with `--simulate-offline`.

- **The red alert has never followed a real failover.** Verified 14.10.2026 by `--simulate-failover`: red stripe
  seen (docs/v4-red-after-failover.png), still red after quitting and reopening the stripe, OK pressed through
  accessibility cleared it and logged it, and a non-simulated alert from `mantra` while on mantra cleared itself.
  `raiseAlert` inside the keeper runs only after a real network change.

- **No real failover has happened.** v1 to v4 could not have made one: networksetup without a password does not join
  on macOS 15 (LESSONS).
- The Wi-Fi power cycle has never been run.
- The LaunchAgent was loaded on 14.10.2026 and ran; start at login and restart after a crash are untested.
- A captive portal has only been reasoned about, never met.
- The stripe's speed was seen moving (5 kB/s → 198 kB/s) but not compared against another meter.

## State on 18.10.2026 (v12)

- The stripe: connection (green Wi-Fi / yellow other) | speed with the last speedtest.net result in parentheses
  (green down, red up) | ping (yellow) | data left; the status and failover places only when they have something to say.
- A click on the speed runs `speedtest-firefox --visible` (Tools/, linked into ~/.local/bin; kept profile
  ~/Library/Application Support/connection-keeper/firefox); a click on the data runs `router-sms balance --visible`.
- At start: pingNow, then `router-sms balance` then `speedtest-firefox`, both headless; again once past midnight
  (`newDay`). Each speed test costs about 100 MB of the SIM.
- The router-sms warm server is unloaded and must stay so (one router session).
- Never proven: the red alert's look with the v12 hidden places (`--simulate-failover`), the yellow colour on a cable
  or tethered phone (no cable plugged in on 18.10.2026).

## State on 18.10.2026 (v13): aggregation

- `Sources/Aggregate/main.swift`: `ck-aggregate` (serve / uplinks / test / on / off). It finds the lines (devices with
  a router that answer a ping through themselves), groups them by public IP or router MAC (one per group, the cable
  first), and gives every new connection to the line with the fewest connections for its speed. If a line cannot reach
  the host, the next line is tried. Health check every 20 s, lines found again every 60 s or at once when the ticks change.
- `Sources/Shared/Aggregate.swift`: the ticks (`aggregate-selection.json` in Application Support/connection-keeper),
  the server's /status, the last test (`aggregate-test.json`), macOS's SOCKS proxy on/off.
- `Sources/App/Lines.swift`: the stripe's extra rows, the JOINED row, the JOIN ticks, the server watcher.
- `launchd/com.mantra.connectionkeeper.aggregate.plist`; `agent.sh load` loads both agents, `unload` stops both and
  switches the proxy off. Log: `~/Library/Logs/connection-keeper-aggregate.log`.
- **Never proven:** two really different lines (the Mac's Wi-Fi on Something, the cable on mantra), so the speed gain is
  not measured yet; Marko's ticks; a whole day with the proxy on; Chrome with QUIC (Chrome turns QUIC off behind a SOCKS
  proxy, which is what we want). One single download stays on one line: the next step is a server outside (LESSONS).
- Every start of the stripe still runs the data SMS and a speedtest.net test (about 100 MB of SIM data).

## State on 18.10.2026 (v16): the mode switch

- `Aggregation.aggregateMode` (Shared/Aggregate.swift) is the file `mode` in Application Support ("one" / "aggregate"; missing
  = the old flag decides). `Aggregation.on` = aggregate mode AND lines ticked. `setMode` does the whole switch: on =
  launchctl enable + bootstrap + kickstart of com.mantra.connectionkeeper.aggregate, then `apply(true)`; off = `apply(false)`,
  the proxy off, bootout + disable of the agent.
- App/Lines.swift: `toggleMode` on the last row's name, `addModeSection` at the top of ▾; ticking none still means off.
- Tunnel/main.swift: `trafficPasses()` (two Cloudflare addresses by IP, 4 s each), checked 4 s after up and every 10 s;
  `rest()` = down + five minutes before up is allowed; route re-adds counted per minute.
- On 18.10.2026 at 12:40 the Mac is on ONE CONNECTION, the tunnel-on flag removed, the helper not running (still v14 in
  /Library/PrivilegedHelperTools until Marko runs `sudo ./tunnel.sh install`).
- Never proven: the v15 helper as root (needs his sudo); a fail-open triggered for real; AGGREGATE CONNECTION on screen.
  AX88179B (the USB-C cable) showed "no internet" at 12:36, not looked into.

## v17 (19.10.2026): phone lines over adb

`Sources/Shared/Phones.swift` lists the phones on a USB cable (`adb devices -l`, `usb:` only, not the emulator), names them "<maker> <model> (USB)", and `ensure()` pushes `Contents/Resources/phone/ck-phone` (built by build.sh from `Sources/Phone/main.go`, GOOS=linux GOARCH=arm64) to /data/local/tmp when its sha256 differs, starts it on the phone's 127.0.0.1:8858 and forwards Mac 127.0.0.1:8860+n to it. A phone's device is "adb:<serial>"; ck-aggregate's `Uplink.phone` dials it as SOCKS5 (`Phones.dial`), its health is a connection to 1.1.1.1:443 through it, UDP never goes to it; the test counts it on the phone's /proc/net/dev. The stripe ensures it too (every scan; cheap when it answers) and draws its speed from the server's byte counters. Known: `ensure` only pushes a new ck-phone when the old one stops answering (kill it on the phone after a change).

## v21 (28.10.2026): WIRES or WI-FI

The switch beside ⚙ runs `Resources/ck-wires wires|wifi --json` (Sources/App/Wires.swift); the mode is the file
`wires` in Application Support, the radios before WIRES are in `wires-state.json` (deleted by WI-FI). The router is
switched by `router-sms wifi on|off` (ROUTER_SMS v3, one session on the router: never run it beside another router-sms
job). The phone's hotspot is the Quick Settings tile (no shell command on the Nothing). Never proven: a phone that is
locked with a PIN (the tile may ask to unlock), and two phones on USB at once. Left in WIRES on 28.10.2026.

## State on 28.10.2026, 15:20 (v29)

The stripe: one line `🟡 ⚙ ▸ connection | speed (test) | ping | data | status ‖`. 🟡 = macOS minimize (TrafficMinimize,
main.swift); ⚙ = a menu with WIRES / WI-FI (Wires.swift) and Settings…; ▸ opens only the lines connected now (Lines.swift,
`shown`); "connection" while aggregating, else the line's name; ‖ = Grip, drags the scale (stripeScale in the stripe's
defaults, 0.5–3×; the root is a FlippedView whose bounds keep the natural size). Every field is a fixed slot (tighten()
in main.swift sets the widths from samples: speedSample(), "ping 999 ms", "888.8 GB left", statusSample), so the width
never changes (813 points at 1×). Colours: green connected, red here but not connected, grey gone (seen-lines.json; grey
rows are no longer shown on the stripe since v24, the ▾ menu still greys what is not available). No dots (v28).
Mode on 28.10.2026: WIRES (Mac Wi-Fi, TP-Link Wi-Fi and the phone's hotspot off), AGGREGATE CONNECTION over AX88179B +
Nothing A142 (USB). Marko: "everything working great".
Never proven: the drag by a hand other than his (he confirmed "all works" on v28); the ⚙ menu opened by Accessibility
(pop-up menus need a real click).

## State on 28.10.2026, 22:50 (v32): ⟳ RESCAN, plugged devices, the pipe leak

- **The pipe leak** (the cause of request 49): `shell()` leaked one pipe per call in every program without a run loop
  (ck-aggregate, connection-keeperd); the stripe drains its pool and did not. ck-aggregate had 2473 pipes after 6.5 h,
  every program it ran gave empty output, `discover()` found nothing and `/status` said `"lines": []` from 17:58.
  `shell()` now runs in `autoreleasepool` and closes both ends; the tunnel helper's `run()` the same.
- **⟳** (`rescan` in main.swift, `rescanNow()`): writes `aggregate-rescan` (Aggregation.requestRescan); the server's
  watcher (closure in `Server.run`, every 1 s) deletes it, `rescan()` = refresh + every line probed now
  (`lastGood` reset), and writes `aggregate-rescan-done` (time, then "name (alive|silent)" per line); the stripe waits
  up to 30 s (`rescanAnswer(since:)`) and shows "N LINES ✓ HH:MM". Not aggregating: the stripe's own scan only. Server
  silent: launchctl kickstart of the agent. Also `--rescan` and the distributed notification `ConnectionKeeperRescan`.
- **Plug detection** (`deviceFingerprint()` in Aggregate/main.swift): the IPv4 devices from getifaddrs (no program)
  plus `adb devices` with each state, every second; a change logs `devices changed (… → …)`, `joinPlugged` ticks the
  entries that appeared (a phone only in state "device", never the Wi-Fi), then refresh + checkLines.
- Measured 28.10.2026: ⟳ answered in 16 s, "2 LINES ✓ 22:37" seen on the stripe (both lines joined). The phone unticked,
  `adb usb` (adbd restarted on the phone, gone 10 s): "plugged in: Nothing A142 (USB): joined", both lines alive 19 s
  after it went. ck-aggregate: 0 pipes after 6 minutes. The ticks were put back as they were.
- Known: a flap shorter than about 1.3 s (`adb reconnect`) can fall between two looks; a real unplug is longer.
- **The tunnel helper (needs Marko's admin password)**: on 28.10.2026 22:27 its log said "routes were gone" while
  `netstat -rn` by hand showed 0/1 and 128.0/1 on utun99 the whole time; the helper had run 16 h with the same leaking
  `run()`, so its own netstat very likely came back empty, it re-added routes, and after four "re-adds" rested five
  minutes (the "macOS deletes the routes" of v31). The fix is in Sources/Tunnel/main.swift and is in the v32 app;
  installing it needs `sudo ./tunnel.sh install` from this folder (or at least a restart of the daemon,
  `sudo launchctl kickstart -k system/com.mantra.connectionkeeper.tunnel`). Never proven until then.
