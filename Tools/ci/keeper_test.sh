#!/bin/bash
# CI only (v90, assessment 23.11.2026): the keeper's ladder with every probe offline (dry run, short waits), around it a
# simulated Wi-Fi, its network, a second live line and the aggregation. The Wi-Fi power cycle must appear only when no
# other line carries and the Wi-Fi is not on a phone hotspot.
set -u
K="$1"
fail=0
run() { perl -e 'alarm 60; exec @ARGV' "$K" --simulate-offline --fast --once "$@" 2>&1; }
check() {   # name, output, must-contain (or ""), must-not-contain (or "")
  local name="$1" out="$2" yes="$3" no="$4" ok=1
  [ -n "$yes" ] && ! grep -q -- "$yes" <<<"$out" && ok=0
  [ -n "$no" ] && grep -q -- "$no" <<<"$out" && ok=0
  if [ $ok = 1 ]; then echo "PASS $name"; else echo "FAIL $name"; echo "$out" | sed 's/^/    /'; fail=1; fi
}
a=$(run --simulate-wifi en0 --simulate-ssid "home-wifi-test")
check "a) Wi-Fi alone and dead: the power cycle is the last step" "$a" "step: Wi-Fi power off and on" ""
b=$(run --simulate-wifi en0 --simulate-ssid "home-wifi-test" --simulate-other-line "AX88179B (en17)")
check "b) a second line carries: no power cycle" "$b" "power cycle skipped (en0): AX88179B (en17) still carries" "step: Wi-Fi power off"
c=$(run --simulate-wifi en0 --simulate-ssid "Something")
check "c) on the phone hotspot Something: no power cycle" "$c" "on the phone hotspot \"Something\"" "step: Wi-Fi power off"
d=$(run --simulate-wifi en0 --simulate-ssid "Something" --simulate-other-line "AX88179B (en17)" --simulate-aggregate)
check "d) aggregation on and a line alive: not offline, no ladder" "$d" "NOT OFFLINE" "retry 1 of 2"
echo "--- b) as the log says it"; grep -E "OFFLINE|step:|skipped|NO OTHER" <<<"$b" | sed 's/^/    /'
exit $fail
