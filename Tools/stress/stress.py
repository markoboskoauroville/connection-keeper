#!/usr/bin/env python3
"""Stress a TEST COPY of ck-aggregate (never the real one on 8857).
usage: stress.py <label> <line names separated by ,> [--slowloris]"""
import asyncio, json, os, socket, struct, subprocess, sys, time, statistics, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("CK_BIN", os.path.join(HERE, "ck-aggregate"))
PORT = 8957
SEL, FAULT = os.path.join(HERE, "sel.json"), os.path.join(HERE, "fault")
assert PORT != 8857

label, names = sys.argv[1], [n for n in sys.argv[2].split(",") if n]
slowloris = "--slowloris" in sys.argv
out = {"label": label, "ticked": names, "steps": []}

def status():
    try:
        return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/status", timeout=3))
    except Exception:
        return None

def server_stats(pid):
    fds = subprocess.run(["lsof", "-p", str(pid)], capture_output=True, text=True).stdout.count("\n") - 1
    th = subprocess.run(["ps", "-M", "-p", str(pid)], capture_output=True, text=True).stdout.count("\n") - 1
    return {"fds": fds, "threads": th, "alive": subprocess.run(["kill", "-0", str(pid)]).returncode == 0}

async def socks_open(host, port, timeout=20):
    r, w = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", PORT), timeout)
    w.write(b"\x05\x01\x00"); await w.drain()
    assert await asyncio.wait_for(r.readexactly(2), timeout) == b"\x05\x00"
    h = host.encode()
    w.write(b"\x05\x01\x00\x03" + bytes([len(h)]) + h + struct.pack(">H", port)); await w.drain()
    rep = await asyncio.wait_for(r.readexactly(10), timeout)
    if rep[1] != 0:
        w.close(); raise RuntimeError(f"socks reply {rep[1]}")
    return r, w

async def trace(host="www.cloudflare.com", timeout=20):
    t = time.time()
    r, w = await socks_open(host, 80, timeout)
    w.write(f"GET /cdn-cgi/trace HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode()); await w.drain()
    body = await asyncio.wait_for(r.read(), timeout)
    w.close()
    ip = next((l[3:] for l in body.decode(errors="replace").splitlines() if l.startswith("ip=")), None)
    if not ip:
        raise RuntimeError("no trace answer")
    return time.time() - t, ip

async def burst(n, host="www.cloudflare.com"):
    res = await asyncio.gather(*[trace(host) for _ in range(n)], return_exceptions=True)
    ok = [x for x in res if not isinstance(x, Exception)]
    errs = {}
    for x in res:
        if isinstance(x, Exception):
            k = type(x).__name__ + (":" + str(x)[:40] if str(x) else ""); errs[k] = errs.get(k, 0) + 1
    lat = sorted(x[0] for x in ok)
    by_ip = {}
    for _, ip in ok: by_ip[ip] = by_ip.get(ip, 0) + 1
    return {"n": n, "ok": len(ok), "fail": n - len(ok), "errors": errs,
            "p50": round(statistics.median(lat), 2) if lat else None,
            "p95": round(lat[int(len(lat) * .95) - 1], 2) if lat else None, "by_ip": by_ip}

def udp_dns(n=10):
    """SOCKS5 UDP ASSOCIATE, one A query for example.com to 1.1.1.1:53 each."""
    good = 0
    for i in range(n):
        try:
            c = socket.create_connection(("127.0.0.1", PORT), timeout=10)
            c.sendall(b"\x05\x01\x00"); c.recv(2)
            c.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
            rep = c.recv(10)
            if rep[1] != 0: c.close(); continue
            relay = ("127.0.0.1", struct.unpack(">H", rep[8:10])[0])
            u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.settimeout(5)
            q = struct.pack(">HHHHHH", 0x1234 + i, 0x0100, 1, 0, 0, 0) + b"\x07example\x03com\x00\x00\x01\x00\x01"
            u.sendto(b"\x00\x00\x00\x01" + socket.inet_aton("1.1.1.1") + struct.pack(">H", 53) + q, relay)
            d, _ = u.recvfrom(4096)
            if len(d) > 22 and d[10:12] == struct.pack(">H", 0x1234 + i): good += 1
            u.close(); c.close()
        except Exception:
            pass
    return {"udp_dns_ok": good, "of": n}

async def hold(k):
    held = []
    for _ in range(k):
        try:
            held.append(await socks_open("1.1.1.1", 443, 10))
        except Exception:
            break
    return held

async def main():
    json.dump(names, open(SEL, "w"))
    open(FAULT, "w").close()
    env = dict(os.environ, CK_AGG_PORT=str(PORT), CK_AGG_SELECTION=SEL, CK_AGG_TEST="1", CK_AGG_FAULT=FAULT)
    log = open(os.path.join(HERE, f"server-{label}.log"), "w")
    # launchd gives its agents 256 open files (launchctl limit maxfiles): the test copy gets the same
    srv = subprocess.Popen(["/bin/sh", "-c", f'ulimit -Sn 256; exec "{BIN}" serve'], env=env, stderr=log, stdout=log)
    try:
        st = None
        for _ in range(60):
            st = status()
            if st and len(st["lines"]) >= 1 and all(l.get("publicIP") for l in st["lines"]): break
            await asyncio.sleep(1)
        await asyncio.sleep(4)          # the first health checks
        st = status()
        out["lines"] = [(l["name"], l["publicIP"], l["alive"]) for l in (st or {}).get("lines", [])]
        out["ignored"] = (st or {}).get("ignored", [])
        if not out["lines"]:
            out["steps"].append({"step": "no line found"}); return
        for n in (20, 100, 250) + ((1000,) if "--big" in sys.argv else ()):
            r = await burst(n); r["step"] = f"burst {n}"; r.update(server_stats(srv.pid)); out["steps"].append(r)
        r = await burst(30, host="cloudflare.com"); r["step"] = "burst 30 by name"; out["steps"].append(r)
        out["steps"].append({"step": "udp", **udp_dns()})
        held = await hold(160)
        s = server_stats(srv.pid)
        r = await burst(20); r["step"] = f"20 while {len(held)} held open"; r.update(s); out["steps"].append(r)
        for _, w in held: w.close()
        await asyncio.sleep(3)
        if len(out["lines"]) > 1:
            first = out["lines"][0][0]
            for how in ("silent", "dead"):
                open(FAULT, "w").write(f"{first}={how}\n")
                t0 = time.time(); fails = []; oks = 0
                while time.time() - t0 < 15:
                    r = await burst(5); oks += r["ok"]; fails += [round(time.time() - t0, 1)] * r["fail"]
                st = status()
                out["steps"].append({"step": f"{first} {how}", "ok": oks, "fail": len(fails), "fail_times_s": fails[:20],
                                     "alive": {l["name"]: l["alive"] for l in st["lines"]} if st else None})
                open(FAULT, "w").close()
                await asyncio.sleep(8)
        if slowloris:
            idle = []
            for _ in range(300):
                try: idle.append(socket.create_connection(("127.0.0.1", PORT), timeout=2))
                except Exception: break
            await asyncio.sleep(2)
            r = await burst(10); r["step"] = f"10 while {len(idle)} silent clients connected"; r.update(server_stats(srv.pid)); out["steps"].append(r)
            for s_ in idle: s_.close()
            await asyncio.sleep(3)
            r = await burst(10); r["step"] = "10 after the silent clients left"; r.update(server_stats(srv.pid)); out["steps"].append(r)
        await asyncio.sleep(2)
        st = status()
        out["after"] = {"active": {l["name"]: l["active"] for l in st["lines"]} if st else None, **server_stats(srv.pid)}
    finally:
        srv.terminate(); srv.wait(5)
        out["server_log_tail"] = open(os.path.join(HERE, f"server-{label}.log")).read().splitlines()[-8:]
        json.dump(out, open(os.path.join(HERE, f"result-{label}.json"), "w"), indent=1)
        print(json.dumps(out, indent=1))

asyncio.run(main())
