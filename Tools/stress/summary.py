#!/usr/bin/env python3
"""One table row per combination from result-<label>.json (prefix as argv[1], e.g. '' or 'fixed-')."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
pre = sys.argv[1] if len(sys.argv) > 1 else ""
for label in ["cable", "wifi", "phone", "cable+wifi", "cable+phone", "wifi+phone", "all3"]:
    f = os.path.join(HERE, f"result-{pre}{label}.json")
    if not os.path.exists(f): continue
    d = json.load(open(f))
    steps = {s["step"]: s for s in d["steps"]}
    def ok(name):
        s = next((v for k, v in steps.items() if k.startswith(name)), None)
        return f'{s["ok"]}/{s["ok"] + s["fail"]}' if s else "-"
    lines = "+".join(f'{n}({ip})' for n, ip, _ in d.get("lines", []))
    ign = ",".join(i["name"] for i in d.get("ignored", []))
    spread = steps.get("burst 100", {}).get("by_ip", {})
    fo = [f'{k.split()[-1]} {v["ok"]}/{v["ok"] + v["fail"]}' for k, v in steps.items() if k.endswith(("silent", "dead"))]
    print(f'{label:12} lines={lines} ignored=[{ign}]  b20={ok("burst 20")} b100={ok("burst 100")} b250={ok("burst 250")} '
          f'b1000={ok("burst 1000")} name={ok("burst 30 by name")} udp={steps.get("udp", {}).get("udp_dns_ok", "-")}/10 '
          f'held={ok("20 while")} silent={ok("10 while")} after={ok("10 after")} spread100={spread} failover={fo} '
          f'p95(100)={steps.get("burst 100", {}).get("p95")} end={d.get("after")}')
