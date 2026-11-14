# ckbond v1: one connection over every line

Request 84 (Marko, 14.11.2026): bonding through the Oracle Cloud server. Since v65 of Network Aggregate Connection Keeper.

## Why

Without bonding the aggregation server (ck-aggregate, 127.0.0.1:8857) puts each TCP connection on ONE line. A browser
opens many connections, so a page uses all lines; but a single flow (a video upload, one big download, a one-connection
speed test) is never faster than its line, and dies when its line dies. Joining one connection over several lines needs
a machine outside the house that puts the pieces back together: that is the relay on chromium-vm (Oracle, Frankfurt,
linux/arm64, 2 Gbit/s, public 130.61.181.83, ~35 ms from the house lines).

## The workflow

```
app ─SOCKS/HTTP─▶ ck-aggregate ──leg 1 (cable  en17)──┐
                   (Bond.swift)  ──leg 2 (Wi-Fi)───────┼──▶ ck-bond-server :443 ──one TCP──▶ destination
                                 ──leg 3 (phone, adb)──┘    (chromium-vm)
```

1. With `bond.json` `"on": true` the Mac keeps one TCP **leg** (1–2 per line, `legsPerLine`) to the relay through each
   live line: cable and Wi-Fi bound to their device (as `dial()` does), phones through their ck-phone SOCKS port
   (`Phones.dial`). Legs are made again when the lines change (checked every second); a dead one is retried after 3 s,
   doubling to 30 s.
2. A new SOCKS or HTTP connection to an internet address becomes a **stream**: OPEN host:port, the relay dials it and
   answers OPEN_OK, then the bytes flow both ways as DATA frames spread over all legs. Destinations in the house
   (loopback, 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10 incl. Tailscale, `.local`, names without a dot) stay
   on today's path.
3. Fewer than two lines with a leg up (v67): the bond steps aside, new connections take today's `race()` path, and
   `/status` `bond.bypass` says why (one line gains nothing from the relay, it only adds its hop). The legs stay up, so
   the bond is back the moment a second line is. The bond takes the aggregation's lines as they are: a ticked line the
   stripe's HTTPS probe marks NO DATA (dead-lines.json) or that is not found is left out, and `bypass` and the log line
   `BOND paths: … ; left out: …` (written whenever the set changes) say so (v69).
4. OPEN is optimistic (v67): the client gets its SOCKS/HTTP answer and its first bytes follow OPEN at once, without
   waiting a relay round trip for OPEN_OK. OPEN_FAIL closes the client's socket; no OPEN_OK within 10 s resets the stream.
5. UDP (QUIC, calls, DNS over UDP) is not bonded: it keeps today's one-line path.

## The wire

### Legs and the handshake

A leg is a TCP connection to the relay. All numbers big-endian.

1. relay → Mac: `snonce` (32 random bytes).
2. Mac → relay: `cnonce` (32) | `clientID` (16, random per ck-aggregate run; all legs of one Mac carry the same one and
   form a **group**) | `HMAC-SHA256(token, "ckbond1" | snonce | cnonce | clientID)` (32).
3. A wrong HMAC, or nothing within 10 s: the relay closes at once, without a word. Ten failures from one address in
   ten minutes and that address is refused for ten minutes.
4. Keys: `HKDF-SHA256(ikm = token, salt = snonce | cnonce, info = "ckbond1 c2s" | "ckbond1 s2c", 32 bytes)`: one
   AES-256-GCM key per direction. Nonce = 4 zero bytes | u64 record counter of that leg and direction (from 0).
5. The relay's first record is a WELCOME frame: the Mac knows the token matched.

Record: `len u16` (ciphertext + 16-byte tag) | ciphertext | tag. One frame per record.

### Frames

`type u8 | stream u32 | seq u32 | len u16 | payload` (payload at most 16 KB).

| type | name | seq | payload |
|---|---|---|---|
| 1 | OPEN (Mac → relay) | 0 | `host:port` (`[v6]:port`) |
| 2 | OPEN_OK | 0 | none |
| 3 | OPEN_FAIL | 0 | a short reason |
| 4 | DATA | n | bytes |
| 5 | FIN | n | none: this direction is finished (half close) |
| 6 | RST | – | none: the stream is gone; sent on every leg |
| 7 | ACK | see below | stream ≠ 0: `seq` = next frame expected, all before it **delivered** (cumulative); stream 0: **leg ACK**, payload u64 = sequenced bytes received on this leg |
| 8 / 9 | PING / PONG | id | the sender's clock (ns), echoed |
| 10 | WELCOME | – | none |

Types 1–5 are **sequenced**: numbered per stream and direction from 0, reliable, delivered in order. A stream is made on its first frame,
whatever it is (its DATA may overtake its OPEN on a faster leg); one whose OPEN does not come within 10 s is reset.

### Reliability

- Each side keeps every sequenced frame until its stream ACK. Each sent frame remembers its leg and that leg's byte
  count after it.
- The receiver counts the sequenced bytes it got on each leg and answers with a leg ACK every 32 KB or on the 50 ms
  tick. A frame whose leg ACK came back has arrived (it waits in the receiver's memory if it is out of order).
- A leg is dead after 3 s without any record (PING every second each way), or at once when its socket fails. Every
  frame it carried that its leg ACK does not cover is sent again on the other legs, oldest first.
- The receiver sorts by `seq`, delivers in order, drops copies (and answers a copy with an ACK, in case the ACK it
  lost was the reason).
- Stream ACK every 256 KB delivered or on the 50 ms tick. The window: at most 4 MB unacknowledged per stream and
  direction, so a slow destination or client never fills memory.

### The scheduler (both sides, per frame)

- `arrival(leg) = minRTT/2 + (bytes in flight on the leg + this frame) / rate`; the leg with the earliest arrival wins.
- In flight = sequenced bytes put on the leg minus its leg ACK. Cap: `max(64 KB, rate × (2 × minRTT + 50 ms))`; a leg
  at its cap takes nothing until its ACKs come back. This bounds the reordering and keeps the kernel's buffers small.
- `rate` (v67): delivered bytes from the leg ACKs over at least 250 ms (and 2 × minRTT), smoothed 0.6 old / 0.4 new. It
  follows a sample down only when the leg was backlogged the whole sample (found full between every two ACKs); otherwise
  it only rises. Starting value 20 Mbit/s. Each side sends its estimate in its PONGs, so the Mac shows both directions.
  (v65 averaged over 100 ms and spiralled a leg to nothing; v66 took the best 100 ms and believed a phone's adb bursts.)
- A young stream (its first 64 KB: a handshake, a request, a small answer) may use up to twice a leg's cap, so it does
  not queue behind the other streams' bulk.
- `minRTT`: the lowest PING time seen on the leg (a ping waits behind the leg's own queue; a minimum that followed it
  up would grow the cap and with it the queue). The leg is made again when its line changes.

### Limits and timeouts (relay)

Streams idle 10 min are reset; a group without legs for 60 s is gone (the Mac gives up after 50 s and starts a new
group); 1024 streams per group, 64 legs per group, 64 groups, 512 legs in all. Destinations on loopback, private,
link-local (the cloud's metadata), and 100.64/10 (Tailscale) are refused unless `-allow-local` (the CI test only).

## Files and commands

| What | Where |
|---|---|
| Relay source (Go, standard library only) | `Sources/Bond/server/` |
| Relay binary | release asset `ck-bond-server-linux-arm64` (built by CI next to `app.zip`) |
| systemd unit / installer | `Tools/bond/ckbond.service`, `Tools/bond/install.sh` |
| Mac client | `Sources/Aggregate/Bond.swift`; hooks in `socks()` / `http()` of `main.swift` |
| Config (0600) | `~/Library/Application Support/connection-keeper/bond.json` `{"on":false,"server":"130.61.181.83","port":443,"token":"<64 hex>","legsPerLine":1}` |
| Relay token | `/etc/ckbond/token` (hex, root 0600), read through systemd `LoadCredential` |
| Status | `curl -s 127.0.0.1:8857/status` → `"bond": {on, bypass, server, legs: [{line, rttMs, rateUpMbps (the Mac's estimate), rateDownMbps (the relay's, from its PONGs), alive, inflightKB, …}], streams, opened, mbUp, mbDown}`; `bypass` is null when the bond is used, else why not |
| Log | lines starting with `BOND` (ck-aggregate's log; `journalctl -u ckbond` on the VM) |

- `ck-aggregate bond-init`: writes bond.json with a new random token, bond off; prints only `token written to <path>`.
  An existing file is kept.
- `ck-aggregate bond-selftest …`: the loopback proof, run by CI (below).
- bond.json is read every 5 s: `"on": true` starts the bond, `false` stops it; no restart needed.

## The proof (CI)

The workflow builds the relay for darwin, starts it on 127.0.0.1:18443 with a random test token, serves a 64 MB random
file with `python3 -m http.server`, and runs `ck-aggregate bond-selftest`: three local proxies emulate the lines
(A and B 80 Mbit/s with 20 ms each way, C 16 Mbit/s with 60 ms), one leg each. Fetch 1 takes the file through ONE
stream and checks SHA-256 and that at least two lines carried 10 % of it; fetch 2 silences line A after 24 MB and must
still finish intact. The step fails on FAIL, before the release.

## What it does not do (phase 2)

- UDP: QUIC, video calls, DNS over UDP keep their one-line path. A UDP-in-frames mode (or a TUN on both ends) is phase 2.
- The relay is one more hop: about +35 ms on every bonded connection, and the VM's own 2 Gbit/s and Oracle's egress
  are the ceiling. Every site sees the VM's address (Frankfurt), not the house's.
- The relay is not yet installed (14.11.2026). Port 443: the VCN's Default Security List already allows it and the VM's
  iptables INPUT policy is ACCEPT (checked by the oci CLI, request 84); install.sh adds an ACCEPT rule anyway when a REJECT exists.

## Upgrades and switches without a drop (v71, request 85)

| Switch | What happens | Proof |
|---|---|---|
| Bond switched off or changed (bond.json) | The old client **drains**: no new streams; its open streams finish on their legs (at most 10 min), then its legs close. New connections take today's path at once. | `bond.bypass` says "draining" |
| A new connection cannot be bonded | It waits at most **1 s** for OPEN_OK (or the OPEN_FAIL), then takes today's `race()` path; the client never sees a failure for it. | hooks in `main.swift` (`open(…, timeout: 1)`) |
| Relay upgrade | `install.sh --keep-token <new binary>` moves the binary into place and runs `systemctl reload ckbond` → SIGHUP → the binary on disk starts as a child **with the same listening socket** (fd 3), says READY (fd 4) and `MAINPID=` to systemd (Type=notify, NotifyAccess=all); the old process stops accepting, sends **GOAWAY** (frame 13) on every leg and serves its streams until they end (`-drain`, 10 min). The Mac starts a new **generation**: a new client id, new legs to the new process, new streams there; the old generation's legs close when its last stream ends. | CI: fetch 3 intact across a SIGHUP, a small fetch every 0.1–0.5 s during it, 0 failed |
| Mac aggregate upgrade | The updater runs `ck-aggregate handover` (new binary): an **interim server** listens beside the old one (SO_REUSEPORT); the old one gets SIGTERM, stops accepting within 0.2 s, takes what is queued, lets its connections finish (10 min max), exits; launchd starts the new server; the interim one sees its marker (`aggregate-serving/<pid>`) and drains the same way. Draining and interim servers change nothing on the Mac (no 4G/5G, radio probes, plug-in ticks, ⟳). | CI: `Tools/ci/handover_test.py`, 20 probes/s and a long download across old → interim → new, 0 failures |

Once only: a relay before v71 (Type=simple, no SIGHUP hand-over) and a ck-aggregate before v71 (no SO_REUSEPORT) cannot
hand over. The first install of v71 restarts the relay once (`install.sh` says "restarted … once"; the Mac goes direct
for new connections within 1 s, bonded streams of that moment end), and `handover` stops a v70 server and takes its
port the moment it is free (a few ms; that server's open connections end). Every later upgrade is hitless.

## Open = Frankfurt, Quit = the Mac as before (v73, requests 86 + 87)

The app is a normal Mac app (Dock, ⌘-Tab, a titled window, a main menu). `Sources/Shared/Session.swift`:

- **Open:** the service order of now is kept once (the "before"); the keeper and the aggregation server are started and
  answering; only then the tunnel flag (the root helper adds the two half routes through utun99). A lease
  (`app-lease.json`: the app's pid and program path) says the app owns the session.
- **Quit (⌘Q, Dock Quit, logout):** proxy off and the tunnel flag removed first (the helper deletes the half routes, then
  stops hev; the Mac's own default route, never touched, takes every new connection), the service order back to the
  "before", then the keeper and the server disabled and stopped (the server drains), ck-phone and our adb forwards
  removed, the lease removed. The mode (aggregate / one connection) is kept for the next open.
- **Update:** the updater's quit keeps everything; the lease says "updating" for 3 minutes, the new copy takes it over.
- **Crash:** ck-aggregate checks the lease twice a second; a lease whose program is gone (and not updating) = the same
  quit, from there (seen in CI: about 2 s).
- **OFF** stays the explicit "stop everything, also at the next login".
- `ck-bondcheck --clean-save` before opening, `ck-bondcheck --clean` after quitting: proxies, default/half routes,
  service order, DNS resolvers, our processes and the tunnel flag compared (PASS = identical).
- CI (`Tools/ci/session_test.sh`, the real tunnel helper on GitHub's runner): open → quit and open → crash with new
  connections from three threads the whole time: 0 failed, the clean check PASS after each.

## UDP, DNS, the direct list, STRICT (v74–v75, request 85)

- **UDP:** a SOCKS5 UDP association (hev turns the Mac's UDP into these) is one **flow** on the relay, with one UDP
  socket of its own there (a cone NAT: QUIC, STUN/ICE and games keep one outside address and port). Frames DGRAM (11):
  unreliable, not ordered, never resent; `seq` only to drop copies. Payload: flags (bit 0 redundant) | atyp | address |
  port | data. DGRAM_CLOSE (12) when the association ends. A quiet flow (under 64 kbit/s, packets under 400 bytes: a
  call's audio, DNS, game ticks) is **redundant**: each datagram on the two quickest legs, the copy dropped by `seq`; a
  busy flow (QUIC downloads, video) goes on the quickest leg with room (256 KB of datagrams waiting per leg at most,
  beyond it a datagram is dropped as UDP may be). NAT timeouts on the relay: 30 s without an answer, 180 s idle once
  answered; 256 flows per group. Datagrams to the house (private addresses) stay direct. A flow whose relay process
  hands over moves to the new generation (its outside port changes once; QUIC migrates).
- **DNS:** a question to the house's resolver (a private address, port 53, e.g. the router) is asked at 1.1.1.1 through
  the relay and its answer handed back as if the router had answered; other resolvers' questions go through the relay
  as any UDP. `ck-bondcheck` checks `whoami.cloudflare` (CH TXT @1.1.1.1 = the relay) and `o-o.myaddr.l.google.com`
  (the system resolver's question must not come from the home line or its /24). Not covered: Tailscale's MagicDNS
  (100.100.100.100) answers inside tailscaled; where tailscaled sends its own upstream questions is its business (the
  check shows it).
- **Direct list:** `bond-direct.txt`, one domain per line (covers subdomains; `#` comments), read again when it changes,
  ⚙ Settings → "Direct list…". Names from SOCKS/HTTP; for the tunnel's IP-only connections the names learned from DNS
  answers that pass through the server (30 min). A listed domain shows the HOME address. Apps cannot be listed.
- **PRIVACY STRICT** (bond.json `"strict": true`, ⚙ Settings, default off): with no bond leg up, a new connection to
  the internet is refused (SOCKS "not allowed", HTTP 403, datagrams dropped) instead of going over the home line; the
  house and the direct list still go direct; the tunnel helper's `tunnel-strict` follows it, so it does not fail open.
- **The stripe:** ⇄ FRA n · x↓ green / ⇄ ASIDE amber / ⇄ DOWN red / ⇄ off grey, " STRICT"; a click runs ck-bondcheck.
- **/status `watchdog`:** acceptLoopMs, clients, maxClients, openFiles, uptimeS, draining, interim, pid, app (lease),
  strict; the log says "WATCHDOG" when the accept loop stops turning for 5 s. The server's log rotates at 10 MB
  (`.1`); the relay logs to journald (rotated by it).

## One line = still through Frankfurt (v79)

Marko's priority is privacy ("acting as my VPN, hiding my real IP behind Frankfurt"): with ONE live leg every connection
still goes through the relay (no speed gain, the home address hidden); only with NO leg do new connections go direct (or
are refused under PRIVACY STRICT). ⚙ "Bond only when it adds speed (2+ lines)" (bond.json `"speedOnly": true`, off by
default) brings back the v67 rule. ck-bondcheck: "a live leg to the relay" is the check; one leg adds the NOTE "no speed
gain". The stripe shows ⇄ FRA 1.
