#!/usr/bin/env python3
"""CI only (v71, request 85): ck-aggregate is upgraded under load without one failed connection.

    handover_test.py <ck-aggregate> <state dir> <http port> <sha of big.bin>

A test copy (port 18957, one fake line lo0) serves; 20 probes a second (HTTP /status on the port, and a SOCKS connection
to the local web server with a small GET) and one long, slowly read 64 MB download run through it, while:
  `ck-aggregate handover --old-pid A` starts the interim server B and drains A;
  A exits when its download is done; the script then starts C as launchd would; B sees C and drains.
PASS: no probe failed, the download is intact, A and B exited, C serves.
"""
import hashlib, json, os, socket, struct, subprocess, sys, threading, time, urllib.request

BIN, STATE, HTTP, SHA = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
PORT = 18957
env = dict(os.environ, CK_AGG_PORT=str(PORT), CK_AGG_TEST="1", CK_AGG_FAKE_LINE="lo0",
           CK_AGG_SELECTION=f"{STATE}/sel.json", CK_AGG_LINES=f"{STATE}/lines.json",
           CK_BOND_CONFIG=f"{STATE}/no-bond.json", CK_AGG_MARKS=f"{STATE}/marks")
logf = open(f"{STATE}/aggregate.log", "a")

def start(*args):
    return subprocess.Popen([BIN, *args], env=env, stdout=subprocess.DEVNULL, stderr=logf)

def status():
    try:
        return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/status", timeout=2))
    except Exception:
        return None

def socks(host, port, timeout=5):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=timeout)
    s.sendall(b"\x05\x01\x00")
    assert s.recv(2) == b"\x05\x00"
    s.sendall(b"\x05\x01\x00\x01" + socket.inet_aton(host) + struct.pack(">H", port))
    rep = b""
    while len(rep) < 10:
        b = s.recv(10 - len(rep))
        if not b: raise RuntimeError("socks closed")
        rep += b
    if rep[1] != 0: raise RuntimeError(f"socks reply {rep[1]}")
    return s

def get(s, path):
    s.sendall(f"GET {path} HTTP/1.0\r\nHost: x\r\n\r\n".encode())
    data = b""
    while True:
        b = s.recv(65536)
        if not b: break
        data += b
    return data

a = start("serve")
for _ in range(200):
    st = status()
    if st and any(l["device"] == "lo0" for l in st["lines"]): break
    time.sleep(0.1)
else:
    print("FAIL: the first server did not come up with its test line"); sys.exit(1)
print(f"server A pid {a.pid} up")

stop, probes, fails, lock = False, 0, [], threading.Lock()
t0 = time.time()
def prober():
    global probes
    while not stop:
        for kind in ("status", "socks"):
            try:
                if kind == "status":
                    ok = status() is not None
                else:
                    s = socks("127.0.0.1", HTTP); d = get(s, "/small.bin"); s.close(); ok = b" 200 " in d[:20] and len(d) > 2048
                why = "" if ok else "bad answer"
            except Exception as e:
                ok, why = False, str(e)
            with lock:
                probes += 1
                if not ok: fails.append(f"{time.time() - t0:.2f} s {kind}: {why}")
        time.sleep(0.1)
threading.Thread(target=prober, daemon=True).start()

big = {"ok": False}
def download():
    try:
        s = socks("127.0.0.1", HTTP, timeout=30)
        s.sendall(b"GET /big.bin HTTP/1.0\r\nHost: x\r\n\r\n")
        h, head, n = hashlib.sha256(), b"", 0
        while True:
            b = s.recv(65536)
            if not b: break
            if head is not None:
                head += b
                if b"\r\n\r\n" in head:
                    rest = head.split(b"\r\n\r\n", 1)[1]; h.update(rest); n += len(rest); head = None
                continue
            h.update(b); n += len(b)
            time.sleep(0.008)                       # about 8 s for 64 MB: it spans the whole hand-over
        big.update(ok=h.hexdigest() == SHA, bytes=n)
    except Exception as e:
        big.update(why=str(e))
d = threading.Thread(target=download); d.start()

time.sleep(2)
b = start("handover", "--old-pid", str(a.pid))
print(f"{time.time() - t0:.2f} s: handover started, interim server B pid {b.pid}")
while a.poll() is None and time.time() - t0 < 120: time.sleep(0.05)
print(f"{time.time() - t0:.2f} s: A exited ({a.returncode}) after its connections finished")
c = start("serve")                                  # what launchd's KeepAlive does
print(f"{time.time() - t0:.2f} s: server C pid {c.pid} started (as launchd would)")
while b.poll() is None and time.time() - t0 < 180: time.sleep(0.05)
print(f"{time.time() - t0:.2f} s: B exited ({b.returncode})")
d.join(120)
time.sleep(2)
stop = True
time.sleep(0.5)
alive_c = c.poll() is None and status() is not None
c.terminate()
print(f"probes {probes}, failed {len(fails)}; long download: {big}; C serving: {alive_c}")
for f in fails[:10]: print("  failed:", f)
ok = not fails and big.get("ok") and a.returncode == 0 and b.returncode == 0 and alive_c and probes > 100
print("HANDOVER TEST PASS" if ok else "HANDOVER TEST FAIL")
sys.exit(0 if ok else 1)
