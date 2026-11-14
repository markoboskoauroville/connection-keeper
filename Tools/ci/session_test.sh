#!/bin/bash
# CI only (v73, request 87): open = through the aggregation, quit = the Mac exactly as before, a crash = the same, with
# 10 new connections a second the whole time. Installs the app, the aggregation LaunchAgent and the root tunnel helper on
# the GitHub runner (never on Marko's Mac).
set -u
APP="Network Aggregate Connection Keeper (Mantra)"
DST="/Applications/$APP.app"
AGG="$DST/Contents/MacOS/ck-aggregate"
SUP="$HOME/Library/Application Support/connection-keeper"
STATE=/Library/PrivilegedHelperTools/com.mantra.connectionkeeper.tunnel/state
T=$(mktemp -d)
fail=0
say() { echo "$(date +%T) $*"; }

rm -rf "$DST" 2>/dev/null || sudo rm -rf "$DST"
cp -R "build/$APP.app" /Applications/ 2>/dev/null || sudo cp -R "build/$APP.app" /Applications/
mkdir -p "$SUP" ~/Library/LaunchAgents
NAME=$("$AGG" uplinks 2>/dev/null | sed -n 's/^line: \(.*\) (\(en[0-9]*\)) .*/\1/p' | head -1)
[ -n "$NAME" ] || { say "no line found on the runner"; "$AGG" uplinks; exit 1; }
python3 -c 'import json,sys; json.dump([sys.argv[1]], open(sys.argv[2], "w"))' "$NAME" "$SUP/aggregate-selection.json"
say "the runner's line: $NAME"
sed "s|__HOME__|$HOME|g" launchd/com.mantra.connectionkeeper.aggregate.plist > ~/Library/LaunchAgents/com.mantra.connectionkeeper.aggregate.plist
sudo ./tunnel.sh install >/dev/null 2>&1 || { say "the tunnel helper did not install"; exit 1; }
sudo cat /Library/Logs/connection-keeper-tunnel.log 2>/dev/null | tail -2

python3 Tools/ck-bondcheck --clean-save
python3 Tools/ci/probe.py 150 "$T/probe.json" &
PROBE=$!
sleep 3

cycle() {   # $1 = how it ends: quit | crash
  sleep 3600 & local FAKE=$!                      # the "app": the lease follows this process
  say "OPEN (app pid $FAKE)"
  CK_SESSION_NO_KEEPER=1 "$AGG" session open --app-pid $FAKE | sed 's/^/    /'
  for i in $(seq 1 60); do grep -q '^on' "$STATE" 2>/dev/null && break; sleep 0.5; done
  if grep -q '^on' "$STATE" 2>/dev/null; then say "tunnel up: $(netstat -rn -f inet | awk '$1=="0/1" {print $1, $NF}')"
  else say "FAIL: the tunnel did not come up"; sudo tail -5 /Library/Logs/connection-keeper-tunnel.log; fail=1; fi
  sleep 10
  local c0=$(curl -s -m 2 127.0.0.1:8857/status | python3 -c 'import json,sys; print(sum(l["connections"] for l in json.load(sys.stdin)["lines"]))' 2>/dev/null)
  say "through the aggregation server: $c0 connections so far"
  [ "${c0:-0}" -gt 20 ] || { say "FAIL: the traffic did not go through the server"; fail=1; }
  if [ "$1" = quit ]; then
    say "QUIT"
    "$AGG" session close | sed 's/^/    /'
  else
    say "CRASH: the app is killed"
    kill -9 $FAKE
  fi
  for i in $(seq 1 80); do
    pgrep -x ck-aggregate >/dev/null || pgrep -x hev-socks5-tunnel >/dev/null || [ -e "$SUP/tunnel-on" ] || break
    sleep 0.5
  done
  say "after the $1: $(pgrep -x ck-aggregate >/dev/null && echo 'ck-aggregate still runs' || echo 'no ck-aggregate'), tunnel $(cat $STATE 2>/dev/null)"
  python3 Tools/ck-bondcheck --clean | sed 's/^/    /'
  python3 Tools/ck-bondcheck --clean >/dev/null || fail=1
  kill $FAKE 2>/dev/null
  sleep 4
}
cycle quit
cycle crash
grep -h "SESSION" "$HOME/Library/Logs/connection-keeper-aggregate.log" 2>/dev/null | tail -8
wait $PROBE
python3 - "$T/probe.json" <<'PY' || fail=1
import json, sys
p = json.load(open(sys.argv[1]))
print(f"probe: {p['probes']} new connections ({p['perSecond']}/s), {p['newFailed']} failed to open, {p['inflightBroken']} broken in flight (a road changed under an open one)")
for l in p["log"]: print("   ", l)
sys.exit(0 if p["newFailed"] == 0 and p["perSecond"] >= 10 else 1)
PY
sudo ./tunnel.sh uninstall >/dev/null 2>&1
[ $fail = 0 ] && echo "SESSION TEST PASS" || echo "SESSION TEST FAIL"
exit $fail
