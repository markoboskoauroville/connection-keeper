#!/usr/bin/env python3
"""CI only: new connections to 1.1.1.1:80 (an HTTP GET; any HTTP answer counts) from two threads, together at least 10 a
second, for <seconds>, through whatever road the Mac has. A NEW connection that cannot be opened or gets no answer within
3 s is counted "newFailed"; one that was open and broke, "inflightBroken" (a road changed under it). One JSON line at the end."""
import json, socket, sys, threading, time
secs = float(sys.argv[1]); out = sys.argv[2]
t0, lock = time.time(), threading.Lock()
st = {"probes": 0, "newFailed": 0, "inflightBroken": 0, "log": []}
def one():
    phase = "connect"
    try:
        s = socket.create_connection(("1.1.1.1", 80), timeout=3)
        phase = "answer"
        s.settimeout(3)
        s.sendall(b"GET /cdn-cgi/trace HTTP/1.0\r\nHost: 1.1.1.1\r\n\r\n")
        data = s.recv(64)
        s.close()
        if not data.startswith(b"HTTP/1."): raise RuntimeError(f"not HTTP: {data[:20]!r}")
        return None
    except Exception as e:
        return phase, str(e)
def worker():
    while time.time() - t0 < secs:
        start = time.time(); r = one()
        with lock:
            st["probes"] += 1
            if r:
                st["newFailed" if r[0] == "connect" else "inflightBroken"] += 1
                if len(st["log"]) < 20: st["log"].append(f"{time.time() - t0:.1f} s {r[0]}: {r[1]}")
        time.sleep(max(0, 0.18 - (time.time() - start)))
ts = [threading.Thread(target=worker) for _ in range(2)]
for t in ts: t.start()
for t in ts: t.join()
st["perSecond"] = round(st["probes"] / secs, 1)
json.dump(st, open(out, "w"))
