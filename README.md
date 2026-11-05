# Network Aggregate Connection Keeper (Mantra)

```
git clone https://github.com/markoboskoauroville/connection-keeper.git && cd connection-keeper && ./build.sh && ./agent.sh load
```

Keeps the Mac online. A keeper (LaunchAgent) checks the internet every 5 minutes (ping 1.1.1.1, then an HTTP
probe), and when it is gone it walks a ladder: retry, rejoin the same Wi-Fi, join the next one in the list
(`mantra`, `Something`), switch the Wi-Fi power off and on, then back off and try again. A floating stripe shows
the connection, its live speed, the ping, the last check and the last failover, with a drop-down to switch by hand
and a gear for the list.

Stop the keeper:

```
./agent.sh unload
```

| Document | For whom |
|---|---|
| [TAKEOVER.md](TAKEOVER.md) | the next session: how it works now, the files, what has never been proven |
| [LESSONS.md](LESSONS.md) | anybody about to change a decision: what was learned and why it is so |
| [momentaryupdates.md](momentaryupdates.md) | Marko's requests, word for word, with their status |

## Press the ping (v3, 13.10.2026)

The "ping" on the stripe is a button. Press it and the stripe pings 1.1.1.1 itself (with the HTTP probe behind it), keeper running or not, and says the answer on the status line: **ALIVE ✓** and the time in green with the ping in ms, or **NOT ALIVE ✗** in red. The answer stays 20 seconds, then the usual reading returns.

## Red after a failover (v4, 14.10.2026)

When the keeper leaves a dead connection by itself (mantra stops answering, the keeper moves to Something), every
word on the stripe turns red, so it is seen from across the room, and the failover field says which connection died
and when: **mantra died 09:41 → on Something**. It stays red, through restarts of the stripe, the keeper or the Mac,
until **OK** on the stripe is pressed (or the red words are clicked), or until the Mac is back on the connection that
died. A switch made by hand from the drop-down never turns it red. Settings shows the same line in red at the top.

![the stripe after a failover](docs/v4-red-after-failover.png)

Try it without touching the network (the test alert stays until OK):

```
"/Applications/Connection Keeper (Mantra).app/Contents/MacOS/connection-keeperd" --simulate-failover mantra Something
```

## The switch that really switches, and NO OTHER CONNECTION (v5, 14.10.2026)

Choosing a connection in the drop-down now starts the join at once: the status line says **switching to mantra…**,
then **on mantra ✓ 10:39** in green, or in red why not (**✗ Something: not in range**). On macOS 15 a program may
join a password-protected Wi-Fi only with its password, so each Wi-Fi gets its password once in ⚙ → **Password…**
(kept in the login keychain), or the app gets the Accessibility permission and switches through Control Centre the
way a hand does. When the connection in use is dead and no other one in the list works, the status line says in
bold red **NO OTHER CONNECTION — mantra dead, Something not working**, until a connection works again.

![NO OTHER CONNECTION](docs/v5-no-other-connection.png)

## Always on top, and the switch through Control Centre (v6, 14.10.2026)

The stripe stays above every window, on every Space and beside full-screen apps; ⚙ → **Always on top** turns it into
an ordinary window and back, and the choice is remembered. With the Accessibility permission (granted 14.10.2026) a
switch from the drop-down presses the network in Control Centre's Wi-Fi list, as a hand would, when the password way
is not there. Check the road without switching:

```
open -n "/Applications/Connection Keeper (Mantra).app" --args --check-join    # one line in the log: CHECK join path …
```

## Pipes, not empty space (v7, 14.10.2026)

![the stripe, v7](docs/v7-stripe.png)

The items sit close with a dim pipe between them and the stripe is only as wide as its words. If its remembered place
is on no screen, it comes back to the top middle of the main screen.

## How much data is left (v8, 14.10.2026)

![the stripe, v8](docs/v8-data-balance.png)

The stripe shows what is left on the Telemach SIM in the TP-Link router: **28.2 GB left · 13:00** (the time is the
one in Telemach's SMS), amber below 10 GB, red below 2 GB. A click on it, or ⚙ → **Check data**, asks again: behind
the scenes the command `router-sms balance --json` (repo [router-sms](https://github.com/markoboskoauroville/router-sms))
sends STANJE to 13880 through the router with a headless browser and reads the reply; the stripe says
"checking data…" meanwhile and never waits. Each check is one SMS, so the automatic check (⚙, every N hours) is off
until he turns it on. Measured: 13.6 s and 11.4 s from the click to the answer.

```
open -n "/Applications/Connection Keeper (Mantra).app" --args --check-data     # the same as a click
```

## A stripe that holds still, the speed unit, Settings with margins (v9, 14.10.2026)

![the stripe, v9](docs/v9-stripe-1.png)

Every item on the stripe has a fixed width and every number a fixed number of places (four digits, right-aligned,
monospaced), so the stripe no longer "breathes" as the speed changes; ⚙ sits at the left end, next to the dot, where
it never moves. ⚙ → **Speed unit**: Auto in bits (bit/s → kbit/s → Mbit/s, the default), Auto in bytes
(B/s → kB/s → MB/s), or one fixed unit (bit/s, kbit/s, Mbit/s, Gbit/s, B/s, kB/s, MB/s, GB/s); the speed test results
follow it. Settings takes the size its content needs, 20 points from every edge.

![Settings, v9](docs/v9-settings.png)

## Internet speed only, never the local network (v10, 14.10.2026)

![the stripe during a 150 MB adb push to the phone, v10](docs/v10-stripe-during-adb-2.png)

The speed on the stripe, now labelled **internet**, counts only what goes through the router to the internet: the
kernel's byte counters of the default route (`nettop -m route`, "default -> en0 -> 192.168.1.1"), TCP and UDP. v1 to
v9 counted everything on en0, so a transfer to the phone at 192.168.1.103 showed as internet speed. Measured during a
150 MB adb push to the phone (3.6–3.9 MB/s on the local network): en0 3605–3924 kB/s out, the stripe 0–26 kB/s.

## The data check in front of his eyes (v11, 18.10.2026)

A click on the data item (or ⚙ → Check data) now runs `router-sms balance --visible --json`: a Firefox window opens
on the router, logs in (the password typed dot by dot), writes STANJE to 13880 letter by letter, sends it, waits in
the Inbox, opens Telemach's reply when it comes and holds it on the screen for 15 s, then closes; the stripe shows
the result. The same script every time, no AI. Nothing else may stay logged in to the router meanwhile (it allows one
session; MANTRA_MANIFEST modules/tp-link-router.md).

**The speed test on speedtest.net.** Beside the live internet speed the stripe keeps the last speedtest.net result,
**test ↓ 33.1 ↑ 25.2 · 01:15** (Mbit/s). A click on it, or on the live speed, runs `speedtest-firefox --visible`: a
Firefox window opens speedtest.net, declines the cookie banner, presses GO and shows the result for 10 s (about 45 s
in all).

**Behind the scenes at every start, and once on a new day.** Five seconds after the stripe starts it asks the data
left, then runs the speed test, both headless, nothing on the screen; past midnight it does both again if the day has
no value yet. Only a click by hand opens a window.

```
speedtest-firefox [--visible] [--json]     # Tools/speedtest-firefox, linked into ~/.local/bin
```

## One line, less of it, colours instead of words (v12, 18.10.2026)

![the stripe, v12](docs/v12-stripe.png)

The stripe says only what matters, in one line (MANTRA_MANIFEST modules/one-line-stripe.md): the connection (green
on Wi-Fi, yellow on a cable, USB adapter or phone), the live internet speed with the last speedtest.net result in
parentheses (download green, upload red, no arrows, no time), the ping in yellow, the data left ("98.5 GB left", no
time). "checked … ago" and "failover … ago" are gone; the status place appears only when it has something to say
(NO OTHER CONNECTION, a ping answer, a switch), the failover place only in the red alert. At every start the ping,
the data and the speed test run at once behind the scenes, and each place says (...) until its answer comes.

The speed test's Firefox keeps one profile, `~/Library/Application Support/connection-keeper/firefox`. Since v46
(request 64) it copies uBlock Origin from Marko's own Firefox profile at every start (no advertisements on
speedtest.net), and its window shows no Firefox interface: only the macOS title bar with the close button.

## Claude Code's API drops (v46, 1.11.2026, request 65)

`ck-claude` (Tools/, in the app's Resources, on the PATH) runs while the app runs. It follows every Claude Code
transcript, writes each failed API try with the state of the lines at that second (mode, tunnel, route, DNS, a TLS
handshake to api.anthropic.com) and probes the API with a TLS handshake every 30 s. The bottom row `☁ CLAUDE` shows
the last drop, today's count and the probe. (The Claude Code mod `mods/api-drops` that put the same in every session's
status line was removed on 5.11.2026 at Marko's word: "I don't need it. I don't want to see it.") `ck-claude report` and
`ck-claude history --days 7` read it back. The rule: MANTRA_MANIFEST modules/claude-api-drops.md.

## Aggregation: two lines at once (v13, 18.10.2026)

The app has a third program, `ck-aggregate`, the **aggregation server**: a proxy on 127.0.0.1:8857 (SOCKS5 and HTTP on
one port, the LaunchAgent `com.mantra.connectionkeeper.aggregate`). Every new connection goes out through one of the
joined lines, bound to its device, and the faster line gets more of them. A browser, a download manager or a speed test
opens many connections at once, so it uses both lines together. One single connection still stays on one line.

Only lines that leave the house through **different** devices are joined: the cable and the Wi-Fi through the same
TP-Link (the same public IP or the same router MAC) are one line, and the Wi-Fi is ignored (request 25).

**The stripe** has one row per connection, and the **JOINED** row at the bottom (request 27): each row shows its own
live speed, its ping and whether it is joined. The JOINED row shows the lines joined, their speeds added, the
connections the server holds, and the last joined test against the best single line.

**The drop-down selects** (request 28): under JOIN, a tick box for every connection online now (the menu stays open).
Any tick turns aggregation on, which points macOS's SOCKS proxy at the server. No tick turns aggregation off, and the
proxy goes back off. If the server stops answering for 15 s, the stripe switches the proxy off at once, restarts the
server, and switches the proxy on again when the server answers.

```
ck-aggregate uplinks      which lines are different, which are ignored
ck-aggregate test [s]     each line alone, then all through the server (s seconds each, default 6; SIM data is printed)
ck-aggregate on | off     macOS's proxy → the server, or off (the ticks do this)
```
(`/Applications/Connection Keeper (Mantra).app/Contents/MacOS/ck-aggregate`; the server's words: `curl 127.0.0.1:8857/status`.)

## mantra_networkaggregate: the virtual device (v14, 18.10.2026)

macOS uses a virtual network device, **mantra_networkaggregate** (utun99), as its connection and knows nothing about
aggregation; the device does it. A small root helper, `ck-tunnel` (the LaunchDaemon
`com.mantra.connectionkeeper.tunnel`), runs hev-socks5-tunnel (MIT) on utun99 and sends all IPv4 internet traffic
into it with two half routes. hev hands every connection, TCP and UDP, to the aggregation server, which sends it out
over the joined lines. It is free: a real Network Extension would need a paid Apple developer account.

Install once, with your password (it copies the helper out of the installed app into /Library/PrivilegedHelperTools):

```
sudo ./tunnel.sh install        # sudo ./tunnel.sh uninstall to remove it; ./tunnel.sh status
```

After that the JOIN ticks switch the device: any tick and it carries the internet (the stripe's first row reads
mantra_networkaggregate, the lines have rows under it); no tick and the Mac is straight on its lines. If the server
stops answering for 6 s, the helper removes its routes by itself, so the internet never dies with it.

On a fresh clone the build fetches hev-socks5-tunnel 2.19.0 once and checks its fingerprint (it is not kept in the
repository).

Proven 18.10.2026 (a 5-minute test run): plain downloads with no proxy set, 73.8 Mbit/s through the device, both lines
carrying (cable 19.4 MB + Something 34.7 MB in 6 s); name lookups, UDP to 1.1.1.1, the web and the keeper all fine;
the stripe showed cable 26.0 + Something 54.1 = JOINED 80.1 Mbit/s live.

## One connection or aggregate connection (v15–v16, 18.10.2026)

After v14 the Mac lost the internet until a restart, and the restart brought the device straight back. Now one click on the
stripe's last row switches between **ONE CONNECTION** and **AGGREGATE CONNECTION**; the drop-down starts with the same two
choices. One connection takes every part of the aggregation away without a password: the helper's flag (utun99 down
within 2 s), macOS's SOCKS proxy, and the aggregation server, which is also kept from starting at login. The ticked lines
are kept for the next time. The root helper ck-tunnel now sends a real request (HEAD to 1.1.1.1 / 1.0.0.1) through the
device every 10 s; two misses, or macOS taking its routes away five times in a minute, and it lets go and rests five
minutes. The new helper is installed with `sudo ./tunnel.sh install`.

## A phone over USB (v17, 19.10.2026)

Plug in an Android phone with USB debugging allowed and it becomes a line of its own, "Nothing A142 (USB)" on the stripe, even though macOS cannot use Android's USB tethering (RNDIS) and this phone refuses NCM. The keeper puts a small proxy, ck-phone, on the phone over adb and reaches the phone's internet through the same USB cable. Tick it in ▾ JOIN and click ONE CONNECTION to aggregate it with the cable. Web pages, downloads and everything on TCP use both; UDP (calls, QUIC) stays on the cable.

## WIRES or WI-FI (v21, 28.10.2026)

Marko: *"I am afraid of Wi-Fi, and I think it burns my brain ... So we go wires only, and my brain will be happy."*
A switch on the first row, beside ⚙: **WIRES | WI-FI**.

- **WIRES** (about 35-45 s): checks that the cable (AX88179B to the TP-Link) carries the internet, else switches
  nothing; moves the aggregation's ticks to the cable and the phone on USB and waits until the server uses them; then
  the Mac's Wi-Fi off, the TP-Link's Wi-Fi off (`router-sms wifi off`, over the cable), the Nothing phone's hotspot off
  (its Quick Settings tile, taps shown on the phone) and its own Wi-Fi off; then the internet checked on the cable.
- **WI-FI** (about 30-45 s): puts back what was on before WIRES (`wires-state.json`): the router's Wi-Fi, the Mac's
  Wi-Fi (back on mantra), the phone's hotspot last, the ticks.

The work is `Tools/ck-wires` (inside the app as Resources/ck-wires): `ck-wires wires|wifi|status [--json]` from a
terminal does the same. Every step goes to the log as one `WIRES` line.

## The colours of a connection (v22, 28.10.2026)

Marko: *"Red means device is available, but it's not connected, green means device is connected ... grey means it was
connected in the past, but now it's not available."* On every row of the stripe (name and dot) and in ▾:
**green** carries the internet (the first row, or joined in AGGREGATE CONNECTION), **red** is here but not connected,
**grey** was connected before and is gone now ("not available · connected 12 min ago"). The stripe remembers every
line that was ever green for a week (`seen-lines.json`), so a Wi-Fi switched off by WIRES or a phone unplugged stays
on the stripe in grey. The aggregation row keeps its own colours (green 2 of 2 up, amber fewer, red server down).

## One line: ▸ AGGREGATE CONNECTION (v23, 28.10.2026)

Marko: *"Put only Aggregate Connection with a small arrow. I can open and see what is aggregated ... The whole status
line is basically one line."* The stripe is one line: `● ⚙ WIRES|WI-FI ▸ AGGREGATE CONNECTION | speed | ping | data`.
Aggregating, the name is AGGREGATE CONNECTION and the speed is the joined lines added; with one connection, the name
is that connection. ▸ (in front of the name, like a folder in Finder) opens the rows of the lines under it, coloured
green / red / grey (v22), the cable carrying the internet included; ▾ closes them. It opens closed; the choice is kept.
The name still opens the menu (one connection / aggregate, the JOIN ticks). The old last row "AGGREGATE CONNECTION"
shows only for ONE CONNECTION (aggregating, it would say the top line twice).

## Only what is connected; "connection"; WIRES under ⚙ (v24–v25, 28.10.2026)

- v24 (request 42: *"just show what is actually right now connected, and that's all"*): ▸ opens only the lines
  connected now (joined while aggregating, else the one carrying the internet). Nothing gone, nothing merely here.
- v25 (request 43: *"Just put connection ... reduce the size ... this switch between wires and Wi-Fi can go under the
  settings gear icon"*): aggregating, the one line says **connection**, and the name is only as wide as its word
  (about a third narrower). ⚙ opens a small menu: WIRES, WI-FI (the one in force ticked), Settings….

## Tight, resizable, the macOS minimize, no LED (v26–v28, 28.10.2026)

- v26 (request 44): every field as wide as its words now (no room kept for "888.8 GB left" or the widest speed), no
  padding spaces inside the numbers. The stripe is drawn at a scale (stripeScale, 0.5-3×): the root view keeps its
  natural size in its own coordinates (a flipped view, so it scales from the top-left).
- v27 (request 45: *"On the right side, put the two vertical lines, which I'm dragging and resizing ... On the left
  side, make a minimize button which looks exactly as minimize button from the macOS"*): the grip ‖ at the right end
  (dragged left/right, the stripe smaller/bigger, the left edge staying), the yellow macOS minimize on the left ("−" on
  it under the mouse). The old "–" is gone.
- v28 (request 46: *"Remove the LED next to the minimize circle"*): no dot on any row; when the dot would have been red
  or amber, the word "connection" takes that colour.

## A digital display (v29, 28.10.2026)

Marko: *"My user interface is breathing ... Please make a digital display. Make fixed positions for every number and
every letter."* Every field has the width of its widest possible words, whatever it says now: speeds in four places
plus the unit ("62.8 Mbit/s", " 698 kbit/s"), the test in parentheses in six ("(45.0)", " (...)"), "ping 999 ms",
"888.8 GB left", and the status slot ("ALIVE ✓ 15:16:41") always reserved, empty when there is nothing to say (a
longer message is cut with "…", whole in its tooltip). Measured: 813 points wide in 28 readings, with the status
coming and going.

## Faster switching between the lines (v31, 28.10.2026)

Marko: *"optimize speed of switching between lines."* The aggregation server (Sources/Aggregate/Failover.swift):
- every line checked every 3 s (a TCP handshake to 1.1.1.1:443, about 200 bytes; skipped while the line just carried a
  new connection), dead after two misses, at once when its device loses its address; was a ping every 20 s;
- a new connection races: the best line first, the next one after 1 s or a failure, the first to answer wins;
- names kept 5 minutes; a lookup slower than 2 s uses the last answer, else asks 1.1.1.1 over TCP through a live line;
  a UDP name lookup (port 53) whose line is dead goes over TCP through a live line (the phone carries TCP only).
Measured: the phone's data off 30 s, a new connection through the server every 1.4 s: 44 of 44 answered, the slowest
1.6 s; the phone seen dead after 7 s (43 s before), back 3 s after its data returned.

## ⟳ RESCAN, and a plugged-in phone joins by itself (v32, 28.10.2026)

Marko: *"how can I force it to recheck connections? ... I plugged in my phone, and it's not automatically recognized.
I want to have some kind of refresh or push button."* The stripe now reads `🟡 ⚙ ⟳ ▸ connection | …`:
- **⟳** finds every device and phone again and checks every line now: the status slot says "rescanning…" (⟳ amber),
  then **2 LINES ✓ 22:37** (green two or more, amber one, red none; the names in its tooltip), about 16 s.
  From a terminal the same: `open -n "/Applications/Network Aggregate Connection Keeper (Mantra).app" --args --rescan`,
  or the distributed notification `ConnectionKeeperRescan`.
- **Nothing to press for a plug**: the server looks at the devices and the phones adb sees every second; a change finds
  the lines again at once, and a phone or cable that appears while lines are ticked is ticked too ("plugged in: Nothing
  A142 (USB): joined"). A Wi-Fi is never ticked this way, nor a device unticked while it stayed plugged in.
- **The real cause** of "not recognized": the server leaked one pipe per program it ran. After 6.5 h it held 2473
  of them, every program it started (ifconfig, adb) said nothing, and from 17:58 on 28.10.2026 it had no line at all, so
  nothing plugged in could ever appear. Fixed in `shell()` (Sources/Shared/Net.swift); the server and the keeper keep
  0 pipes over time now.

## Test speed, test health, the aggregate download, MAC · AGGREGATE · BOTH, 4G · 5G (v43, 1.11.2026)

**TEST SPEED** and **TEST HEALTH** at the top of the stripe open a report window: every line alone and all together,
ping, jitter, loss, latency under load with a grade, HTTPS times, the phones' radio, graphs over time. **MAC** (the Mac's
own connection), **AGGREGATE** (only the joined lines) or **BOTH** (the lines, the Mac's connection when they fail).
**4G / 5G** on each phone's line switch the phone through adb. Downloads over all lines at once, resumable, checked:

```
ck-net get https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin --to ~/Downloads
ck-net list        ck-net resume <id>        ck-net test health        ck-net test speed
```
The download shows on the stripe's bottom line (RESUME when broken) and on the Download Monitor.

## The balance by real speed, 5G only for big downloads, the stripe stays put (v47–v48, 1.11.2026)

Each line's speed is measured live (bytes per second and a recent peak) and measured again whenever a phone switches
4G ↔ 5G or gets a new address, so new connections go to the line with the most free speed: the Pixel on 5G (~139
Mbit/s) is no longer treated as a 10 Mbit/s line. The phones rest on 4G; after five minutes of fast downloading (15
Mbit/s or more) they go to 5G, and after five quiet minutes back to 4G. A connection already open stays on its line;
one big file over every line needs several connections (ck-net, or Chrome's parallel downloading). The stripe stays
on the desktop and display where it is; a click on its menu bar icon brings it to you.
