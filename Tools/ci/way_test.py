#!/usr/bin/env python3
"""CI only (v80, request 88): FRANKFURT → CROATIA → FRANKFURT under 10+ new connections a second, 0 failures, and the far
end sees the relay's address in FRANKFURT and the line's own in CROATIA.

    way_test.py <ck-aggregate> <state dir> <relay port> <token hex file>

The relay dials from 127.0.0.2 (-dial-from), the test copy's one line is lo0 (127.0.0.1); a whoami server on 127.0.0.1:18081
answers with the address that reached it."""
import http.server, json, os, socket, struct, subprocess, sys, threading, time, urllib.request

BIN, ST, RPORT, TOKF = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
PORT, WHO = 18958, 18081
cfg = f"{ST}/way-bond.json"
json.dump({"on": True, "server": "127.0.0.1", "port": RPORT, "token": open(TOKF).read().strip(), "legsPerLine": 1}, open(cfg, "w"))
os.chmod(cfg, 0o600)

class Who(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b = self.client_address[0].encode()
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("0.0.0.0", WHO), Who)
threading.Thread(target=srv.serve_forever, daemon=True).start()

env = dict(os.environ, CK_AGG_PORT=str(PORT), CK_AGG_TEST="1", CK_AGG_FAKE_LINE="lo0", CK_BOND_ALLOW_LOCAL="1",
           CK_AGG_SELECTION=f"{ST}/sel.json", CK_AGG_LINES=f"{ST}/lines.json", CK_AGG_MARKS=f"{ST}/marks", CK_BOND_CONFIG=cfg)
agg = subprocess.Popen([BIN, "serve"], env=env, stdout=subprocess.DEVNULL, stderr=open(f"{ST}/way-aggregate.log", "w"))

def status():
    try: return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/status", timeout=2))
    except Exception: return None
def legs():
    s = status() or {}
    return len([l for l in (s.get("bond") or {}).get("legs", []) if l.get("alive")]), (s.get("bond") or {}).get("bypass")

for _ in range(300):
    n, by = legs()
    if n >= 1 and by is None: break
    time.sleep(0.1)
else:
    print("FAIL: the bond did not come up with one leg (bypass:", legs(), ")"); agg.terminate(); sys.exit(1)

def ask():
    s = socket.create_connection(("127.0.0.1", PORT), timeout=4)
    s.sendall(b"\x05\x01\x00"); assert s.recv(2) == b"\x05\x00"
    s.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("127.0.0.1") + struct.pack(">H", WHO))
    rep = s.recv(10)
    if len(rep) < 2 or rep[1] != 0: raise RuntimeError(f"socks reply {rep[:2]!r}")
    s.sendall(b"GET / HTTP/1.0\r\nHost: x\r\n\r\n")
    d = b""
    while True:
        b = s.recv(4096)
        if not b: break
        d += b
    s.close()
    return d.split(b"\r\n\r\n", 1)[1].decode()

t0, res, lock, stop = time.time(), [], threading.Lock(), False
def worker():
    while not stop:
        a = time.time()
        try: r = ask()
        except Exception as e: r = f"FAIL {e}"
        with lock: res.append((a - t0, r))
        time.sleep(max(0, 0.25 - (time.time() - a)))
ws = [threading.Thread(target=worker) for _ in range(4)]
for w in ws: w.start()

def way(on):
    c = json.load(open(cfg)); c["on"] = on
    with open(cfg, "r+") as f: f.seek(0); f.write(json.dumps(c)); f.truncate()
    return time.time() - t0

marks = [("FRANKFURT", 0.0)]
time.sleep(6)
marks.append(("CROATIA", way(False))); time.sleep(6)
marks.append(("FRANKFURT", way(True))); time.sleep(8)
stop = True
for w in ws: w.join()
agg.terminate()

fails = [r for r in res if r[1].startswith("FAIL")]
print(f"{len(res)} new connections in {res[-1][0]:.0f} s ({len(res) / res[-1][0]:.1f}/s), {len(fails)} failed")
for f in fails[:5]: print("   ", f)
ok = not fails and len(res) / res[-1][0] >= 10
want = {"FRANKFURT": "127.0.0.2", "CROATIA": "127.0.0.1"}
for i, (name, at) in enumerate(marks):
    end = marks[i + 1][1] if i + 1 < len(marks) else res[-1][0]
    seen = [r for t, r in res if at <= t < end]
    settled = [r for t, r in res if at + 2.5 <= t < end]             # the switch is read within a second, legs come up
    tally = {ip: seen.count(ip) for ip in sorted(set(seen))}
    good = bool(settled) and all(r == want[name] for r in settled)
    first = next((round(t - at, 2) for t, r in res if at <= t < end and r == want[name]), None)
    print(f"{name:<9} from {at:5.1f} s: answers {tally}; the far end saw {want[name]} from +{first} s; after 2.5 s all {want[name]}: {good}")
    ok &= good
print("WAY TEST PASS" if ok else "WAY TEST FAIL")
sys.exit(0 if ok else 1)
