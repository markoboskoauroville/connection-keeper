# connection-keeper: takeover

**Version v6** (14.10.2026) · repository markoboskoauroville/connection-keeper (private) · artefact `6-connection-keeper-v6.zip`, tag `v6`
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
