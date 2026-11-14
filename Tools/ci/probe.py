#!/usr/bin/env python3
"""CI only: 10 new connections a second to 1.1.1.1:80 (GET /cdn-cgi/trace) for <seconds>, through whatever road the Mac
has. A failure to connect or to get the answer of a NEW connection is counted as "new"; one that connected and then
broke as "in flight" (a road changed under it). Prints one JSON line at the end."""
import json, socket, sys, time
secs = float(sys.argv[1]); out = sys.argv[2]
t0, n, new, inflight, log = time.time(), 0, 0, 0, []
while time.time() - t0 < secs:
    start = time.time(); phase = "connect"
    try:
        s = socket.create_connection(("1.1.1.1", 80), timeout=3)
        phase = "answer"
        s.settimeout(3)
        s.sendall(b"GET /cdn-cgi/trace HTTP/1.0\r\nHost: 1.1.1.1\r\n\r\n")
        data = b""
        while True:
            b = s.recv(4096)
            if not b: break
            data += b
        s.close()
        if b"ip=" not in data: raise RuntimeError("no trace in the answer")
    except Exception as e:
        if phase == "connect": new += 1
        else: inflight += 1
        log.append(f"{time.time() - t0:.1f} s {phase}: {e}")
    n += 1
    time.sleep(max(0, 0.1 - (time.time() - start)))
json.dump({"probes": n, "newFailed": new, "inflightBroken": inflight, "log": log[:20]}, open(out, "w"))
