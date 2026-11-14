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

- **The data balance is a command, not code inside the app** (v8; Marko: "ask the remaining megabytes only through a
  headless browser through the command ... So it all works behind the scenes"). The router's page, its login and the
  SMS belong to router-sms, which can send any SMS; the stripe only runs `router-sms balance --json` and shows the
  answer. A first plan drove his own Firefox (firefoxctl); he chose a headless browser of its own instead.
- **The automatic data check is off by default**: each check is one SMS to 13880.

- **Fixed widths, not "as wide as the words"** (v9). v7 sized every item to its words to remove empty space; then
  every change of a number moved everything to its right, ⚙ included, and Marko could not hit it ("the whole status
  line is breathing"). Now the space is fixed per item and ⚙ is at the left end.
- **Auto speed in bits by default**: Marko asked for "kilobits to megabits"; bytes are a choice in ⚙.

- **Internet speed from the default route's counters, not the interface's** (v10, Marko: "It should only show the
  speed of internet transfer, never local"). The interface counts the phone, the router's page and every LAN copy;
  the kernel's per-route counters (`nettop -m route`) separate them exactly, UDP included. Subtracting the LAN route
  from the interface was rejected: the interface counts headers the route does not (about 3 %), which would show a
  local copy as phantom internet. The router's own WAN page was rejected for the stripe: a headless browser once a
  second, and it measures the whole house, not this Mac.

## The traps

- adb compresses: a pushed file of zeros (`mkfile`) went at "4005 MB/s" and moved nothing over the air; a test of the
  network needs random bytes.

- NSStackView's `fittingSize` leaves out the right edge inset when one arranged view (the connection rows with their
  speed test results) is wider than the rest: Settings cut the text at the right edge (Marko's screenshot,
  14.10.2026 13:12).

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
- **A remembered window place can be on no screen** (14.10.2026: "-2247 185" after a change of displays): the stripe
  ran, layer 25, and nobody could see it. `keepOnScreen()` since v7.
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

## 18.10.2026 (v11, v12)

- **The router allows one session**, so nothing may stay logged in to it in the background (the router-sms warm server
  did, and every check failed by turns); and it shows a new SMS only to a freshly loaded page. Both are in
  router-sms's LESSONS; the rule in MANTRA_MANIFEST modules/tp-link-router.md.
- **The AI never types a router password.** Request 15 asked for Claude in Chrome; the script types it instead, which
  also turned out faster and free (no Claude run per click).
- **A throwaway Firefox profile loses what he installs in it** (uBlock, 18.10.2026). The speed test keeps one profile;
  router-sms still uses a throwaway one (nothing to keep there).
- **A fixed-width label wraps when its sample is one character short**: the padded "(25.6)" is seven places, the
  sample had six. One line is a manifest rule now (modules/one-line-stripe.md).
- **speedtest.net 2026 has no stable class names**: GO is a button whose text is "GO", the numbers are read from the
  page's words after DOWNLOAD Mbps / UPLOAD Mbps / Ping ms, and the test is over when the address becomes /result/<id>.

## 18.10.2026 (v13, aggregation)

- **Joining connections, not packets**: without a machine outside the house, the most one Mac can do is give each new
  TCP connection to a different line (bound with IP_BOUND_IF). That doubles anything that opens many connections
  (browsers, speed tests, parallel downloads), but one single download or one video stream stays on one line. Joining
  one connection over two lines needs a server outside (a VPS running an MPTCP or bonding tunnel such as
  OpenMPTCProuter, glorytun or engarde, the way Speedify works). That is the next step, and it costs a monthly VPS.
- **The same router is one line**: cable + Wi-Fi through the TP-Link gave the same public IP (86.33.x, Telemach).
  `ck-aggregate` groups devices by public IP or router MAC and keeps the cable.
- **"\r\n" is one Character in Swift**: `text.prefix { $0 != "\r" }` never stops at the end of an HTTP line. Use
  `components(separatedBy: "\r\n")`.
- **macOS keeps a default route per device**: `nettop -m route` lists `default -> en0` and `default -> en17` with their
  own counters, so every row of the stripe gets its own live internet speed from one nettop call.
- **networksetup changes the SOCKS proxy without a password** (proven 18.10.2026 on 13 services, on and off again).
- **A proxy that dies takes the internet with it**: the stripe watches the server and switches macOS's proxy off
  after 15 s of silence. The LaunchAgent is `Standard`, not `Background` (Background throttles a proxy's I/O).
- **The stripe grew taller**: "back on screen" put the origin at maxY − 40, which only works for 30 points of height.
  It is maxY − height − 10 now, and the top must be under the menu bar.
- **Bind the address too, not only the device**: with IP_BOUND_IF alone, 4 of 6 connections through the server hung
  for the full dial timeout (8 s) before the next line took them. Binding the socket to the device's own IPv4 address
  as well (what `curl --interface` does) brought every dial to about 0.1 s.
- **Count on the wire**: curl's upload count through a local proxy counts what the proxy took into its buffers (64.8
  Mbit/s "joined" over lines adding up to 38). The test counts each line's own route bytes (nettop), alone and joined.
- **Test servers ration us**: after a few rounds Cloudflare slowed downloads to 0.5 Mbit/s and OVH and Hetzner
  answered 429. The download test spreads its streams over four servers (two Hetzner sites, OVH, Tele2).
- **Open is not busy**: Chrome held 31 idle connections through the server and they counted as load. The server
  counts only connections that moved bytes in the last 5 s, and a measured speed is averaged with the one before.
- **First honest result, 18.10.2026 09:50**: cable 30.6/24.8, Something 40.0/18.9, joined 49.1 down (+23%) and
  44.2 up (+78%) Mbit/s, both lines carrying.
- **The free virtual device**: a Network Extension (a device listed in System Settings) needs a paid Apple developer
  account, and GitHub can only sign with certificates Apple issued. The free road is a root helper with a utun device
  (hev-socks5-tunnel) and two half routes 0/1 + 128/1; the default route stays, so the keeper's view is unchanged.
- **The main line has no road of its own**: macOS gives every line but the main one a default route bound to its
  device (flag I). With the half routes up, sockets bound to the cable found no road and the cable counted as dead for
  the whole first test run. The helper adds `route add -ifscope en17 default <router>` while the device is up.
- **A utun carries TCP and UDP, not ping**: the keeper's ping is pinned to the real line (`ping -b`).
- **The server must answer at once**: it used to find its lines (10-20 s) before accepting; through the device the
  whole Mac would wait. Now it accepts at once and the first connections wait for the lines.
- **UDP reply race**: the reply thread read the client's address before the wait, so the first reply was dropped.

## 18.10.2026, v15: a fail-open check must test the road, not the door

v14's helper took the device down only when the aggregation server stopped answering on 127.0.0.1:8857. The server kept
answering while nothing got out, so every page hung and Marko restarted the Mac; the tunnel-on flag survived the restart
and brought the device back. The check is now a real HEAD to 1.1.1.1 / 1.0.0.1 through the device, and the routes being
taken away again and again counts as failure too (fighting macOS is worse than off). And there is one switch, ONE LINE ⇄
JOINED, that takes every piece of the aggregation away without a password.

## 19.10.2026, v17: a phone over USB without tethering (request 36)

- **macOS speaks NCM, not RNDIS; Android tethers with RNDIS.** Android 12+ can be told `settings put global tether_force_usb_functions 1` (NCM), but the phone's USB gadget HAL must support it: the Nothing A142 (MediaTek) logs "Could not set unsupported function for the GadgetHal" and its `tetherableNcmRegexs` is empty (`dumpsys tethering`). Look there first; it cannot be changed without root. Setting it also turns USB tethering off, so put it back (`settings delete`).
- **adb is a network cable too.** A static Go SOCKS5 server run from adb's shell (`setsid nohup … &` in /data/local/tmp) survives the shell and goes out through the phone's internet; `adb forward` brings it to the Mac. 36–45 Mbit/s, ping ~55 ms. TCP only.
- **Android has no /etc/resolv.conf**: a GOOS=linux binary must be given its resolvers (1.1.1.1, 8.8.8.8).
- **curl through adb lies about uploads** (157 Mbit/s on 4G: adb's buffers); count a phone line on the phone's own /proc/net/dev (ccmni*, rmnet_data*, wlan*). And /proc/net/dev lines have no leading space for long names: split on ":" first.
- **A test that starts its own server must wait until the server knows every line**: a phone's public-IP lookup takes ~9 s and the first joined test read 0.0.

## 28.10.2026, v20: the rename

- **The launchd plists in `launchd/` are templates**: `__HOME__` is filled in by `agent.sh`. Copied by hand into
  ~/Library/LaunchAgents, the log path stays `__HOME__/…`, launchd cannot open it and the agent exits 78 (EX_CONFIG)
  before its first line. Install them with `./agent.sh`, or `sed "s#__HOME__#$HOME#g"`.
- **The tunnel's fail-open works for real** (first time seen): the server went away for the rename and ck-tunnel logged
  "DOWN: the aggregation server does not answer; the Mac is straight on its lines"; the internet stayed, and the device
  came back by itself 50 s later when the server answered again.

## 28.10.2026, v21: WIRES or WI-FI (request 39)

- **The Nothing phone (Android 16) has no shell command for the hotspot** (`cmd wifi` has no start/stop-softap,
  `cmd tethering` has no shell): the Quick Settings tile is pressed through uiautomator. Only the tile's node is
  looked at, never the notifications. The state is read from `dumpsys tethering` ("ap0 - TetheredState").
- **Bring the hotspot back last**: with the phone's hotspot on before the Mac's Wi-Fi, macOS joined "Something"
  (the hotspot) instead of mantra, and `networksetup -setairportnetwork` could not move it (the old -3900).
- **Move the ticks before pulling the Wi-Fi**: the server re-reads the ticks within 2 s, so WIRES waits until it
  shows the cable as a line; this session's own API stream lived through every switch.
- **A tick is "wired" when it is a wired hardware port or a phone "(USB)"**: removing only the Wi-Fi's current name
  left "mantra" ticked when the Mac had been on "Something".

## 28.10.2026, v22: colours by state, not by kind (request 40)

- Before v22 the colour said the kind (Wi-Fi green, cable yellow) and a line that went away vanished. Grey needs a
  memory of what was connected: seen-lines.json, written when a line is green (at most once a minute per line).
  The memory was seeded with mantra, really connected until WIRES at 14:27 the same day.

## 28.10.2026, v25: pop-up menus do not open through Accessibility

- AXPress on ⚙ or on the connection name runs nothing visible: an NSMenu popped up from a button of this
  non-activating panel needs a real mouse click (tried with the app in front too). The ⚙ menu was left for Marko's
  hand; ck-wires itself was proven before (v21).

## 28.10.2026, v26-v28: scaling a layer-backed stripe

- **setBoundsSize on a layer-backed, non-flipped root scales from the bottom-left**: the content slid up out of the
  window at 1.3×. A flipped root view fixed it.
- **A constraint to the root's trailing edge uses the unscaled window**: the old "–" landed outside the window at 1.5×
  (log: root.bounds 763 wide, the "–" at x 1124). Pin to the column's edge instead: the column lives in the scaled
  coordinates.
- **The grip is Marko's hand**: a drag cannot be made through Accessibility; the scale path was proven by setting
  stripeScale 1.3/1.4/1.5 and relaunching.
- **Every relaunch of the stripe sends one STANJE SMS** (the data check at start): about fifteen on 28.10.2026 from the
  rebuilds.

## 28.10.2026, v29: "no empty space" and "no breathing" pull in opposite directions

- Request 44 (no empty space) had the fields follow their words, and the stripe breathed (request 47). The answer that
  serves both: fixed slots, each as small as its widest words; the v9 rule (fixed places for numbers) stands, with
  four places instead of five. Width measured over time is the test, not one screenshot.

## 28.10.2026, v30: an old balance never replaces a newer one

- The stripe keeps the reading whose Telemach time is the newest; an older reply (an old SMS read again) is logged and ignored. The cause itself was fixed in router-sms v4.

## 28.10.2026, v31: faster switching, and the tunnel that is not up in WIRES

- Detection was the slow part (43 s): a 3 s TCP check with two misses sees a dead line in about 7 s; racing the next
  line after 1 s hides even those seconds from a new connection.
- **Since WIRES (14:18) mantra_networkaggregate has not stayed up**: every time ck-tunnel brings utun99 up, its 0/1 and
  128/1 routes are deleted within 2.5 s by short-lived processes, four times, and the helper rests five minutes (81
  times in its log since 19.10, every 5 minutes since 14:19 today). With the Mac's Wi-Fi on (14:07-14:18) it held.
  Not Tailscale (paused for one attempt: the same). Suspect: the scoped default route the helper adds on the cable when
  the cable is the Mac's only network (configd keeps it for itself). Changing the helper needs Marko's admin password.
  Meanwhile the Mac goes straight out through the cable, and the server's improvements wait for the tunnel.

## 28.10.2026, v32: a phone not recognized was a pipe leak

- **Process + Pipe outside a run loop leaks**: the Pipe's file handles are autoreleased, and a thread or a top-level
  loop that never drains a pool keeps every one open (measured: 50 calls, 50 more descriptors). Once the limit is
  reached the programs still run but their output is lost, so the code sees "no interfaces, no phones, no routes"
  rather than an error. Wrap every Process call in `autoreleasepool` and close the pipe's ends; check a long-running
  helper with `lsof -p <pid> | grep -c PIPE`, not by its log.
- **"Not recognized" was not "not looked for"**: the server already looked every minute; it had been blind for hours.
  A rescan button alone would not have helped; the leak fix did, the button and the plug watcher make it immediate.
- **The tunnel's vanishing routes were probably the same leak** in the root helper (routes visible by hand while it
  said they were gone). Look at what a process actually sees before believing that macOS deletes something.
- `adb reconnect` flaps for under a second (between two looks); `adb -s <serial> usb` (adbd restarted on the phone)
  hides the phone for about 10 s and is the honest stand-in for an unplug.

## 28.10.2026: launchctl bootout is not finished when it returns

`sudo ./tunnel.sh install` stopped the old helper, copied the new one, then failed with "Bootstrap failed: 5:
Input/output error": the old job was still being torn down. install now waits until `launchctl print` no longer finds
the job and tries the bootstrap up to five times.

## 31.10.2026 (v39, requests 55 and 56): the outage was the file limit, not the failover

- **launchd gives an agent 256 open files** (`launchctl limit maxfiles`: soft 256, hard unlimited). A proxy uses two per
  connection, so at about 125 connections every new one failed, and the server's own adb / ipconfig / curl could not
  start, so it also lost its lines (`lines:` empty). With the tunnel carrying all of the Mac, that is "no internet".
  Raise the soft limit in the program (setrlimit) and cap the clients below the threads (4096 a process, two each).
- **A handshake needs a deadline.** A client that connects and says nothing held its slot for ever; 300 of them took
  the whole server. 15 s, then cleared before the relay (idle connections may sleep for hours).
- **Never copy a live object to keep its counters**: the connections in flight end on the old one. The "2895 active".
- **Same operator, same public IP**: two 4G lines (TP-Link and the Nothing on Telemach) can share a carrier-NAT address.
  A phone on its own mobile data is its own line.
- **Test on a copy, never on the line you talk through**: CK_AGG_PORT / CK_AGG_SELECTION / CK_AGG_TEST / CK_AGG_FAULT
  run a second server with its own ticks and a fault switch. A test's `ulimit -n` sets the hard limit too: use `-Sn`
  or the copy cannot raise it (the first "fixed" run was capped at 85 by the test, not the server).
- Measured: before, 250 at once 102–126 of 250, 124 held → 0 of 20 new; after, 250 of 250, held 20/20, 300 silent
  clients 10/10, failover 0 failures; 1000 at once is the 4G line's limit (one line 27–81 %, cable + phone 994/1000).
- **v40 (10:17 the same day, from Marko's own OFF/ON test):** he pulled the cable and the Nothing and plugged in the Pixel;
  no ticked line was left, the Mac's Wi-Fi was not ticked, so the server had no line and the tunnel carried nothing
  for 20 s until it rested. Now: no ticked line here → every line; only phones ticked → the Mac's own line joins (a
  phone carries no UDP). The phone's maker is read only from a good adb answer (an error text became a ticked name).

## 31.10.2026 (v41, v42): a retry must not hit the same dying line

- The restart gap was the search itself (router, ARP and a public-address curl per device, ~6 s); remembering the lines
  and starting on them makes it 0.2–0.4 s. A remembered line that is gone is harmless: the race moves on in ≤1 s.
- A health check retried at once tests the same broken path twice in the same second; one dropped cable became two
  misses and a needless fail-open (13:33:22). A retry waits long enough for the server's own line check (3 s rounds).

## 1.11.2026 (v43)

- **5G is TelephonyDisplayInfo, not gsm.network.type.** 5G NSA rides an LTE anchor: getprop and the RIL say LTE, the
  status bar says 5G from `overrideNetwork=NR_NSA`. Read the SIM that carries data (`Phone Id=N` block with
  `mDataConnectionState=2`); on the Nothing that is SIM 2, and SIM 1's signal was read by mistake first. Marko: "Don't
  make nonsense claims": look at the phone before saying what it is on.
- **One file over many lines needs pieces, not connections.** The server balances connections, so one download stays on
  one line; ck-net asks byte ranges per line itself. With pwrite at the offset, a cut costs only the bytes in flight.
- **One speed test is one moment.** At 03:50 both phones together gave ~130 Mbit/s (≈ one phone) and adb looked like
  the ceiling; at 04:25 they gave 132 + 138 down, 157 + 167 up together (all lines 293 ↓ 331 ↑). The cell's load at that
  minute decides; the report's BOTTLENECK note is a hint for that run only, never a verdict without a second run.
- **A phone whose data drops joins the house Wi-Fi and stays.** Its line becomes "the same line" as the router's; in WIRES
  the server now switches the phone's Wi-Fi off.
- **The menu bar icon is on every display.** Toggling the stripe on a display other than the clicked one looks like
  "nothing happens".
- **An Accessibility press is not a click.** AX presses the button's action directly; a real click goes through hit
  testing and misses a button that stands outside its superview's bounds. Put clickable things in the row itself.

## 1.11.2026

- Through the tunnel (utun99, hev-socks5-tunnel) a TCP connect succeeds in 1 ms whatever is behind it: a probe of the
  internet through the aggregate must finish a TLS handshake, or it proves nothing.
- uBlock Origin copied into a profile's extensions folder is active on the next start, but its first start loads the
  filter lists after the page: the first page still has its ads.
- Claude Code's own record of a drop is in the transcript (`subtype: api_error`, `error.connection.code`,
  `retryAttempt`); the mod engine shows the retry only as an opaque marker, so the watcher reads the transcripts.
- A name for a Claude Code mod cannot start with "claude-" (reserved): the mod is `api-drops`.

## 1.11.2026 (v47): a stored speed is not a capacity

The balance used `ck-aggregate test` results stored by public IP. A phone's new 5G address had never been tested, so
the default 10 Mbit/s sent every heavy connection to the slowest line for five hours. Speeds must be live (byte
counters per second, a decaying peak) and re-measured when the radio or the public address changes; a probe right
after a 4G/5G switch reads far too low (6.7 instead of 38), wait ~6 s and look again 30 s later. Counting connections
is no measure of load: the Pixel had more connections than mantra and a seventh of its bytes.

## 1.11.2026 (v48): test copies and windows

`pkill -f` must match the command line as it runs: the test copy started as `./ck-aggregate serve` survived a kill by
its full path, kept port 8957, and one test ran on the old build. A window with `.canJoinAllSpaces` is on every desktop
of every display: to Marko it "follows him around". The rules are in MANTRA_MANIFEST network-aggregation.md.

## 13.11.2026 (v49): a line that is up is not a line that carries data

- Link up and an address say nothing: the cable to a TP-Link with an exhausted SIM looked healthy while every connection stalled, because macOS kept it first. The only honest test is an HTTPS request bound to that interface (`curl --interface`). Two misses, then reorder and leave out; no toggling, no fighting; come back only after a minute of success so a flaky line does not flap.
- Real traffic-light buttons: `NSWindow.standardWindowButton(_:for:)` added to a borderless panel's view; give them our own target and action. Hover.swift must not touch them.
- adb works over the phone's own hotspot (gateway:5555) when Tailscale is down; one shell `dumpsys telephony.registry | grep mSignalStrength` is enough for RSRP/RSRQ/SINR; 2147483647 means unavailable.
- First push of the workflow: GitHub's macOS runners can queue for many minutes; cancel superseded runs so the older version never overwrites Latest.

## 13.11.2026 (v50): the system's window buttons are grey in a non-key panel
- A non-activating panel is never key, so NSWindow.standardWindowButton draws the inactive grey look. Draw the three circles ourselves in the exact colours. A link speed is not a quality: no red zone for a cable. For a phone the SINR decides the speed, so it sits beside RSRP and sets the colour.

## 13.11.2026 (v55): a constraint between views that are not in one hierarchy crashes the launch
- v54 activated `spacerL.width == spacerR.width` before both were in the tab row: NSGenericException "no common ancestor" in Stripe.init, the app died at every start. Activate a constraint only after both views are subviews of one parent. The CI now runs the built app with `--selftest` (build the stripe, lay it out, run the timers 4 s, exit 0), so a launch crash fails the workflow.

- 14.11.2026: `macro ax-press` matches labels without case: "Wi-Fi" pressed the WI-FI word (its network menu opened and blocked the
  stripe until a click outside), and "off" would have hit OFF (the app quits). Icon buttons get a unique accessibility label
  (LAN filter, Wi-Fi filter, Help); press by that, or click by screen coordinates from a window screenshot.
- 14.11.2026: Aggregation.selected survives "one connection" mode; any UI that adds a tick must start fresh when aggregation is off.
- 14.11.2026: proof.ovh.net/files/100Mb.dat is 100 MB (megabytes), not 100 megabits: a "12.5 MB" end-game test spent 105 MB of SIM
  data. Check the size with `curl -sI` before any test download. The same server answers HTTP 429 to many parallel ranges from one
  address; ck-net v64 rests that line 15 s.

## 14.11.2026 (v65–v66): ckbond, bonding through the relay
- A leg's rate must not be an average of delivery samples: a leg that was at its cap for a moment and then idle (the stream's
  window full behind a slow line) read a low sample, got a smaller cap, carried less, read lower: in the first CI run one of two
  equal 80 Mbit/s lines carried 8.6 % and the stream ran at 36.7 Mbit/s. A windowed maximum that falls only through windows in
  which the leg was at its cap gave 105.6 Mbit/s over 80 + 80 + 16.
- The minimum RTT must not follow the pings up: a ping waits behind the leg's own queue, the cap is built on the RTT, so a minimum
  that rises grows the queue that raised it. The lowest seen per leg; the leg is made again when its line changes.
- Count only the sequenced frames in the leg ACKs, on both ends: counting the ACKs themselves makes each ACK call for another.
- On GitHub's macOS runner a usleep of 1–2 ms lasts several ms more: a test line paced per chunk ran at a third of its speed.
  Keep some credit in the token bucket (20 ms here).
- Both the Swift and the Go side compiled at the first push: write the CI step that proves it before the code (the selftest
  failing the workflow is what made the slow rate visible at all).
- A maximum of short delivery samples believes bursts: a phone behind adb delivers in lumps, so a best-100-ms rate made it look
  far faster than it is, it got most of the stream and filled the window (live 14.11.2026: 40 Mbit/s bonded vs 51 direct). Samples
  of >= 250 ms, smoothed, and lowered only when the leg was backlogged throughout.
- Show the estimate that does the work: for a download the relay schedules, so the Mac's own (upload) rate in /status read "10"
  and looked broken. The relay now sends its rate in PONG.
- An optimistic OPEN means the stream's first DATA can arrive first on a faster leg: the far end must make the stream on any
  first frame and hold the gap (v67 CI failed with 0 bytes, v68 fixed).
- One line through the relay is a hop with no gain: bond only with two or more lines up.
- A line can leave the pool from three places (the stripe's NO DATA probe, the server's 60 s refresh, the 1 s health dial):
  each must log its reason, or the next layer (the bond) only sees "one line" and nobody can tell why. A health dial's patience
  must follow the line's RTT: 1.2 s is fine for a 30 ms cable and a coin toss for a 300 ms hotspot.
- 14.11.2026: a reachability check of the relay from the Mac must leave over a real line (`curl --interface en17`): through
  the Mac's own tunnel any TCP connect "answers" at once (1 ms) and proves nothing.
- 14.11.2026: a phone hotspot is only as good as the Wi-Fi hop to the Mac: on a tree it had 70 Mbit/s of 4G but a 300 ms,
  flapping hop; near the desk (−63 dBm) it carried half of every bonded stream.
- Hitless upgrades need the socket to outlive the process: the relay passes its listening fd to its successor (nothing in
  the accept queue is lost) and tells systemd the new MAINPID; the Mac server shares the port (SO_REUSEPORT) with an interim
  copy, because launchd will not start a job's new process before the old one has exited.
- A draining server must stop changing the world (4G/5G switching, radio probes, plug-in ticks): two servers at once is
  fine only if one of them is passive.
- 14.11.2026: toggling the live bond.json during measurements cut Marko's bonded connections each time (v66–v70 stopped
  every stream on "off"). Measure on a test copy; since v71 "off" drains.
- Quit must undo in the order that keeps a road: the helper deletes the half routes (the Mac's own default route was never
  touched) before anything behind them stops; open adds the routes only after the server behind them answers. With that
  order, 1685 new connections across open/quit/crash had 0 failures and even 0 in-flight breaks on the CI runner.
- A probe must accept what the far end really says: 1.1.1.1:80 answers a redirect without "ip=", which counted 794 false
  failures.
