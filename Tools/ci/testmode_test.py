#!/usr/bin/env python3
"""CI only (request 108): TEST MODE end to end, through Tools/ck-test itself, on two fake lines (lo0) shaped by faults.

    testmode_test.py <ck-aggregate> <scratch dir>

A local web server gives big.bin; ck-test starts the copy under test (sandboxed, its own folder) with --bin, and:
  cap      a line at 20 Mbit/s reads 20 (+-35 %)
  pair     A 20 + B 60, 8 streams: both carry, the total >= 0.8 x 80
  kill     the connection on A is cut mid-download within 2 s
  stall    a 2 s stall on B: a 10 MB download takes >= 2 s longer and arrives intact
  delay    300 ms on A: the first byte >= 0.3 s
  silent   A silent: /status says A not alive within 6 s; restored: alive again
  guard    ck-test fail-guard: the copy is gone within 6 s, ENDED says why
  stop     the port is free; the live folder (~/Library/Application Support/connection-keeper) is as before
"""
import hashlib, http.server, json, os, subprocess, sys, threading, time, urllib.request

BIN, T = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
CKTEST = os.path.join(HERE, "..", "ck-test")
PORT, WEB = 18858, 18099
LIVE = os.path.expanduser("~/Library/Application Support/connection-keeper")
os.makedirs(T, exist_ok=True)
big = os.path.join(T, "big.bin")
with open(big, "wb") as f:
    f.write(os.urandom(64 << 20))
mid = os.path.join(T, "ten.bin")
with open(mid, "wb") as f:
    f.write(os.urandom(10 << 20))
SHA10 = hashlib.sha256(open(mid, "rb").read()).hexdigest()


class Quiet(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=T, **k)
    def log_message(self, *a): pass


srv = http.server.ThreadingHTTPServer(("127.0.0.1", WEB), Quiet)
threading.Thread(target=srv.serve_forever, daemon=True).start()
env = dict(os.environ, CK_AGG_FAKE_LINES="A:lo0:20,B:lo0:60")
fails = []


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what, flush=True)
    if not ok: fails.append(what)


def ck(*args, timeout=120):
    r = subprocess.run([sys.executable, CKTEST, *args], env=env, capture_output=True, text=True, timeout=timeout)
    print("  $ ck-test " + " ".join(args) + "\n" + "\n".join("    " + l for l in (r.stdout + r.stderr).strip().splitlines()[-12:]), flush=True)
    return r


def status():
    try: return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/status", timeout=2))
    except Exception: return None


def line(name):
    return next((l for l in (status() or {}).get("lines", []) if l["name"] == name), None)


def curl(path, *extra, m=30):
    t0 = time.time()
    r = subprocess.run(["curl", "-s", "-o", os.path.join(T, "got.bin"), "-m", str(m), "-w", "%{size_download} %{time_starttransfer}",
                        "-x", f"socks5h://127.0.0.1:{PORT}", *extra, f"http://127.0.0.1:{WEB}/{path}"], capture_output=True, text=True)
    size, ttfb = (r.stdout.split() + ["0", "0"])[:2]
    return int(float(size)), float(ttfb), time.time() - t0


def live_files():
    if not os.path.isdir(LIVE): return "absent"
    return sorted((f, os.path.getmtime(os.path.join(LIVE, f))) for f in os.listdir(LIVE))


live_before = live_files()
r = ck("start", "--bin", BIN, "--lines", "A,B", "--port", str(PORT), "--ttl", "15")
check(r.returncode == 0 and status() is not None, "ck-test start: the copy answers on its own port")
if r.returncode != 0:
    sys.exit(1)
for _ in range(20):
    if line("A") and line("B"): break
    time.sleep(0.5)
check(bool(line("A") and line("B")), "the copy has the two fake lines A and B")

# cap: only A ticked, A at 20
ck("lines", "A"); ck("cap", "A", "20")
for _ in range(20):
    s = status() or {}
    if [l["name"] for l in s.get("lines", [])] == ["A"]: break
    time.sleep(0.5)
r = ck("measure", "--url", f"http://127.0.0.1:{WEB}/big.bin", "--streams", "2", "--secs", "5")
got = float(r.stdout.split("Mbit/s")[0].split()[-1]) if "Mbit/s" in r.stdout else 0
check(13 <= got <= 27, f"cap A 20 Mbit/s: measured {got:.1f}")

# the pair: A 20 + B 60, 8 streams
ck("lines", "A,B")
for _ in range(20):
    if line("A") and line("B"): break
    time.sleep(0.5)
ck("cap", "B", "60")
time.sleep(1)
r = ck("measure", "--url", f"http://127.0.0.1:{WEB}/big.bin", "--streams", "8", "--secs", "8")
got = float(r.stdout.split("Mbit/s")[0].split()[-1]) if "Mbit/s" in r.stdout else 0
check(got >= 0.8 * 80, f"the pair A 20 + B 60 with 8 streams: {got:.1f} >= 64")
check(" A 0.0 " not in r.stdout and " B 0.0 " not in r.stdout, "the pair: both lines carried")

# kill: only A, a long download, cut after 2 s
ck("lines", "A")
time.sleep(4)
res = {}
th = threading.Thread(target=lambda: res.update(v=curl("big.bin", m=40)))
th.start(); time.sleep(2.5)
ck("kill", "A"); tk = time.time()
th.join(20)
size, _, took = res.get("v", (0, 0, 99))
check(not th.is_alive() and size < (64 << 20) and time.time() - tk < 5, f"kill A: the download was cut ({size >> 20} of 64 MB, {time.time() - tk:.1f} s after the kill)")
ck("restore", "A")

# stall: only B, capped at 40 (10 MB ~2 s), then a 3 s stall from now: the same download >= 2 s longer, intact
ck("lines", "B")
time.sleep(4)
ck("cap", "B", "40")
time.sleep(0.5)
_, _, base = curl("ten.bin")
ck("stall", "B", "3")
time.sleep(0.4)                                   # the copy reads its fault file every 0.2 s
size, _, took = curl("ten.bin")
ok = size == (10 << 20) and hashlib.sha256(open(os.path.join(T, "got.bin"), "rb").read()).hexdigest() == SHA10
check(ok and took >= base + 2.0, f"stall B 3 s: 10 MB in {took:.1f} s (without: {base:.1f} s), intact: {ok}")
ck("restore", "B")

# delay: only A, 300 ms
ck("lines", "A")
time.sleep(4)
ck("delay", "A", "300")
time.sleep(0.5)
_, ttfb, _ = curl("ten.bin")
check(ttfb >= 0.3, f"delay A 300 ms: first byte after {ttfb:.2f} s")
ck("restore", "A")

# silent: A not alive within 6 s, back after restore
ck("lines", "A,B")
time.sleep(3)
ck("drop", "A", "silent")
t0 = time.time()
while time.time() - t0 < 8 and (line("A") or {}).get("alive", True): time.sleep(0.3)
check((line("A") or {}).get("alive") is False, f"drop A silent: not alive after {time.time() - t0:.1f} s")
ck("restore", "A")
t0 = time.time()
while time.time() - t0 < 8 and not (line("A") or {}).get("alive", False): time.sleep(0.3)
check((line("A") or {}).get("alive") is True, f"restore A: alive again after {time.time() - t0:.1f} s")

# the guard tears the copy down when its check fails
rec = json.load(open(os.path.expanduser("~/Library/Caches/ck-test/current.json")))
ck("fail-guard"); t0 = time.time()
while time.time() - t0 < 8 and status() is not None: time.sleep(0.3)
gone = status() is None
ended = open(os.path.join(rec["state"], "ENDED")).read() if os.path.exists(os.path.join(rec["state"], "ENDED")) else ""
check(gone and "on purpose" in ended, f"fail-guard: the copy gone after {time.time() - t0:.1f} s; ENDED: {ended.strip()}")
r = ck("stop")
check("port %d free" % PORT in r.stdout and "LIVE SIDE IDENTICAL" in r.stdout, "stop: port free, the live side identical")
check(live_files() == live_before, "the live folder: as before (" + ("absent" if live_before == "absent" else f"{len(live_before)} files") + ")")
log = open(os.path.expanduser("~/Library/Caches/ck-test/last-run/aggregate.log")).read()
print("--- the copy's log (FAULT lines)"); print("\n".join(l for l in log.splitlines() if "FAULT" in l or "REFUSED" in l)[-3000:])
print("TESTMODE TEST " + ("PASS" if not fails else f"FAIL: {len(fails)}: " + "; ".join(fails)))
sys.exit(1 if fails else 0)
