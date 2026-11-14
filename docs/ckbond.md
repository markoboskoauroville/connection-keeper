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
   the bond is back the moment a second line is.
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

Types 1–5 are **sequenced**: numbered per stream and direction from 0, reliable, delivered in order.

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
