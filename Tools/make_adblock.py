#!/usr/bin/env python3
"""uBlock Origin's default filter lists -> WebKit content-blocker JSON (v57, request 76).

Run by build.sh on GitHub's runner (ADBLOCK_FETCH=1), never on the Mac: it downloads the lists there.
    python3 Tools/make_adblock.py <out_dir>
Writes <out_dir>/network.json (block / allow requests) and <out_dir>/cosmetic.json (hide ad boxes).
Only filters WebKit can express are kept; the rest (scriptlets, procedural selectors, regexes) are skipped.
A list that cannot be fetched leaves an empty [] file: seed.json still blocks the big ad networks.
"""
import json, re, sys, urllib.request

LISTS = [
    "https://ublockorigin.github.io/uAssets/filters/filters.txt",
    "https://ublockorigin.github.io/uAssets/filters/privacy.txt",
    "https://ublockorigin.github.io/uAssets/filters/unbreak.txt",
    "https://easylist.to/easylist/easylist.txt",
    "https://easylist.to/easylist/easyprivacy.txt",
    "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext",
]
MAX_NETWORK = 140000          # WebKit takes 150,000 rules per list
HOST = re.compile(r"^[a-z0-9.-]+$")
PATH_OK = re.compile(r"^[A-Za-z0-9._~/\-=&%]*$")
TYPES = {"script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
         "xmlhttprequest": "raw", "xhr": "raw", "subdocument": "document", "frame": "document",
         "font": "font", "media": "media", "ping": "ping", "websocket": "raw", "other": "raw"}
BAD_SELECTOR = (":-abp-", ":has-text", ":xpath", ":style", ":matches-", ":upward", ":remove", ":watch-attr",
                ":min-text-length", ":others", ":if", ":contains", ":nth-ancestor", ":matches-css", ":has(")


def fetch(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "ck-adblock"}), timeout=60) as r:
            return r.read().decode("utf-8", "replace").splitlines()
    except Exception as e:
        print(f"  {url}: {e}", file=sys.stderr)
        return []


def esc(s):
    return re.sub(r"([.+?^$()\[\]{}|\\])", r"\\\1", s)


def network(line):
    allow = line.startswith("@@")
    if allow:
        line = line[2:]
    if not line.startswith("||"):
        return None
    body, _, opts = line[2:].partition("$")
    trigger = {}
    for o in filter(None, opts.split(",")):
        neg = o.startswith("~")
        name = o.lstrip("~")
        if name in ("third-party", "3p"):
            trigger["load-type"] = ["first-party" if neg else "third-party"]
        elif name in ("first-party", "1p"):
            trigger["load-type"] = ["third-party" if neg else "first-party"]
        elif name in TYPES and not neg:
            trigger.setdefault("resource-type", [])
            if TYPES[name] not in trigger["resource-type"]:
                trigger["resource-type"].append(TYPES[name])
        elif name in ("important", "all"):
            pass
        else:
            return None                       # domain=, redirect=, removeparam=, csp=, ... are not expressible
    body = body.rstrip("^|")
    host, slash, path = body.partition("/")
    host = host.rstrip("^").lower()
    if not host or not HOST.match(host) or "*" in host or not PATH_OK.match(path):
        return None
    if slash:
        rest = esc("/" + path)
    else:
        rest = "[/:?]"
    trigger["url-filter"] = r"^[^:]+://+([^:/]+\.)?" + esc(host) + rest
    return {"trigger": trigger, "action": {"type": "ignore-previous-rules" if allow else "block"}}


def cosmetic(line, generic, by_domain):
    if "#@#" in line or "#?#" in line or "#$#" in line or "#%#" in line or "##+js" in line or "##^" in line:
        return
    domains, sep, sel = line.partition("##")
    if not sep or not sel or any(b in sel for b in BAD_SELECTOR) or sel.startswith("+") or "{" in sel:
        return
    if not domains:
        generic.append(sel)
        return
    ds = domains.split(",")
    if any(d.startswith("~") or not HOST.match(d) or "*" in d for d in ds):
        return
    by_domain.setdefault(tuple(sorted(ds)), []).append(sel)


def main(out):
    blocks, allows, generic, by_domain, seen = [], [], [], {}, set()
    for url in LISTS:
        lines = fetch(url)
        print(f"  {url}: {len(lines)} lines", file=sys.stderr)
        for raw in lines:
            line = raw.strip()
            if not line or line[0] in "!#[" and not line.startswith("##"):
                continue
            if line in seen:
                continue
            seen.add(line)
            if "##" in line or "#@#" in line or "#?#" in line:
                cosmetic(line, generic, by_domain)
                continue
            r = network(line)
            if r:
                (allows if r["action"]["type"] == "ignore-previous-rules" else blocks).append(r)
    net = (blocks[:MAX_NETWORK - len(allows)] + allows)        # exceptions last, so they win
    cos = []
    for i in range(0, len(generic), 400):
        cos.append({"trigger": {"url-filter": ".*"}, "action": {"type": "css-display-none", "selector": ", ".join(generic[i:i + 400])}})
    for ds, sels in by_domain.items():
        cos.append({"trigger": {"url-filter": ".*", "if-domain": ["*" + d for d in ds]},
                    "action": {"type": "css-display-none", "selector": ", ".join(sels)}})
    with open(f"{out}/network.json", "w") as f:
        json.dump(net, f, separators=(",", ":"))
    with open(f"{out}/cosmetic.json", "w") as f:
        json.dump(cos, f, separators=(",", ":"))
    print(f"adblock: {len(net)} network rules ({len(allows)} exceptions), {len(generic)} generic + "
          f"{sum(len(v) for v in by_domain.values())} site selectors in {len(cos)} rules", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
