# connection-keeper: lessons

## The decisions

- **The SSID comes from `ipconfig getsummary`, not CoreWLAN.** Since macOS 14, CoreWLAN and
  `networksetup -getairportnetwork` hide the SSID from a process without Location permission ("You are not
  associated with an AirPort network" while connected to `mantra`, measured 13.10.2026). `ipconfig getsummary en0`
  still names it. A LaunchAgent cannot ask for Location, so this keeps the keeper free of any permission.
- **Ping and HTTP, not ping alone.** A network that blocks ICMP is not an outage; the HTTP probe decides.
  Measured 13.10.2026: with the ping pointed at 192.0.2.1 the keeper said "online via mantra (http (ping blocked))".
- **One file each way, not a socket or a port.** state.json out, command.json in. Nothing to collide with in
  `ports.md`, and the stripe can show the last state even with the keeper dead.
- **No fail-back.** Returning to the first network whenever it works again would flap between two access points
  when one is marginal. Rejected for v1; a "prefer the first" switch can be added if Marko wants it.
- **The keeper lives inside the app bundle.** One install, one signature ("Mantra Apps"), and the LaunchAgent
  points at `/Applications/…/connection-keeperd`.
- **Drivers per kind.** Marko: "it's going to in future find also wired connections". Only the driver is new for
  a new kind; the ladder and the list stay.

- **The red alert is its own file, not a field of state.json** (v4). The keeper rebuilds its state at every start,
  so a failover recorded there is forgotten by a restart; Marko must still see red when he comes back to the Mac.
- **Only an automatic failover turns it red.** A switch from the drop-down is his own act and needs no warning;
  the keeper's `manual` flag tells them apart. The speed test does not go through `attempt()`, so it never does.
- **The first dead connection is the one remembered.** If mantra dies, then Something, the line still names
  mantra: that is what he has to go and fix. Coming back to it, by the keeper or by hand, clears the red.
- **All the words red, not a red dot.** The dot alone was not visible from across the room (Marko, 14.10.2026).

- **A join is believed by the SSID, and it has three roads** (v5). networksetup alone cannot join a protected Wi-Fi
  on macOS 15; the password typed once (keychain) or Control Centre through accessibility can. Proven by the live
  test below.
- **The drop-down switches from the stripe itself, at once** (v5). Marko pressed mantra and "nothing is happening":
  v4 sent the request to the keeper, whose one networksetup call failed silently behind an amber "recovering".
- **NO OTHER CONNECTION is a phase, not an alert file.** It is true only while nothing works, and the keeper rewrites
  the phase on every check, so it goes away by itself the moment a connection answers.

## The traps

- `networksetup` exits 0 on failure and prints the reason; read the words, then check the SSID and the IP.
- `screencapture -x` of the whole screen captures only the main display; the stripe was on the second one.
  `screencapture -l <windowid>` captures the window itself.
- **networksetup cannot join a protected Wi-Fi on macOS 15** (14.10.2026). `networksetup -setairportnetwork en0 mantra`
  prints `Error: -3900 ... tmpErr`; airportd's log says `Apple80211Associate2: Missing password for upper auth 4096 ...
  Failed to associate to Wi-Fi network Something, returned error code -3900` and `Location Services disabled for
  non-entitled client (proc=/usr/sbin/networksetup)`. The forced disconnect then lets macOS auto-join pick a network
  by itself, which once happened to be the one asked for and fooled the first look. Read it with
  `/usr/bin/log show --predicate 'process == "airportd"'` (plain `log` is a zsh builtin).
- Wi-Fi power off and on does not bring back the first preferred network: macOS rejoined the one used last.
- Control Centre's Wi-Fi list has no "Connect" in System Settings' ⋯ menu; Control Centre → Wi-Fi details →
  the row `wifi-network-<SSID>` is what switches (accessibility press, no mouse).
- **Control Centre opens only when the front app is not full screen** (14.10.2026, menu bar set to hide): AXPress on
  `com.apple.menuextra.controlcenter` returned success and nothing opened over full-screen iTerm; with Finder in front
  the panel opened at once. Hence Finder forward for the moment.
- A permission check run from the terminal answers for the terminal: `--check-join` must be started with `open -n`.
- Two keepers (a test beside the agent) would fight; the flock on `keeper.lock` makes the second one leave.

## Live test, 14.10.2026 (Marko: "switch 5 min each connection a few times")

Planned: three switches mantra ↔ Something, five minutes each, ending on mantra. Stopped twice by Marko (a 1.6 GB
lesson download in Firefox, then "switch to Mantra and keep it live"), and stopped for good by the finding that the
switch itself does not work in v4.

| Time | From → to | How | SSID after | Internet | Keeper log | Stripe | Colour |
|---|---|---|---|---|---|---|---|
| 09:40 | (start) | agent loaded, stripe opened | mantra | ok | `online via mantra (ping 1.1.1.1, 27 ms)` | docs/live-20261014/00-start-mantra.png | normal |
| 09:41 | mantra → Something | networksetup | mantra | ok | (nothing: no check due) | — | normal |
| 09:42 | mantra → Something | networksetup again | Something (macOS auto-join, not the join) | ok, HTTP 200 | `online via Something (ping 1.1.1.1, 2497 ms)` 09:45, then 69 ms, 52 ms | 01a-something-just-after.png, 01-something.png | normal (not red: correct) |
| 09:56 | — | Speed test (⚙, Something row) | Something | 53.2 ↓ / 17.3 ↑ Mbit/s, 63 ms | `speed test running: checks held` | — | normal |
| 09:57 | Something → mantra | **the stripe's drop-down** (v4) | Something | ok | `MANUAL switch to "mantra" asked from the stripe` · `join "mantra" refused: ... -3900 tmpErr` · `"mantra" did not come up within 30 s` · `back online on Something` | 02a-after-dropdown.png ("recovering: wifi "mantra"" amber, no message) | amber, then normal |
| 09:58–09:59 | Something → mantra | networksetup ×3 | Something | ok | — | — | — |
| 10:00 | Something → mantra | Wi-Fi power off/on | Something (auto-join chose it) | ok | — | — | — |
| 10:06 | Something → mantra | Control Centre → Wi-Fi → mantra (accessibility) | **mantra** within 3 s | ok, HTTP 200, ping 38–92 ms | `online via mantra` at the next check | — | normal |
| 10:33 | — | v5, `--simulate-offline` (dry run) | mantra | — | `NO OTHER CONNECTION: mantra is dead and Something did not work (round 1); next try in 60 s` | docs/v5-no-other-connection.png | bold red line, red dot |
| 10:38 | mantra → Something | v5 drop-down | mantra (Something out of range: Marko took the phone) | ok | `MANUAL switch to "Something" FAILED: networksetup: Could not find network Something.; no password stored (⚙ → Password); no Accessibility permission for Control Centre` | 03a-switching.png → 03b-switch-result.png | amber "switching to Something…" at once, red answer after 9 s |
| 10:39 | mantra → mantra | v5 drop-down | mantra | ok | `MANUAL switch to "mantra" done: already on mantra` | 04-on-mantra.png | green "on mantra ✓ 10:39" |

The Firefox download (Video Download Helper, HLS, 1.6 GB) survived the 09:42 change of network and finished at
09:53 on Something.
