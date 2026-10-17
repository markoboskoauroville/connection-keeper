# Connection Keeper (Mantra)

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
