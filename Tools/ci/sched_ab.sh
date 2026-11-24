#!/bin/bash
# CI only (v95, the bond scheduler): ONE build of ck-aggregate and the relay, run twice per round - CK_BOND_LEGACY=1 on both
# ends (= the v92 scheduler) and without (v95) - interleaved on the same runner, N rounds: the main selftest's fetch 1 and
# fetch 2, and the four scenarios (measure only). Then the medians. Usage: sched_ab.sh <agg binary> <relay binary> <rounds>
set -u
AGG=$1; RELAY=$2; N=$3
T=$(mktemp -d)
head -c 67108864 /dev/urandom > "$T/big.bin"
SHA=$(shasum -a 256 "$T/big.bin" | cut -d' ' -f1)
openssl rand -hex 32 > "$T/token"
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$T" >/dev/null 2>&1 &
HTTP=$!
sleep 1
num() { sed -n "$1" | head -1; }
for round in $(seq 1 "$N"); do
  for mode in v92 v95; do
    if [ $mode = v92 ]; then export CK_BOND_LEGACY=1; else unset CK_BOND_LEGACY; fi
    "$RELAY" -listen 127.0.0.1:18443 -token-file "$T/token" -allow-local 2>"$T/relay-$mode-$round.log" &
    RP=$!; sleep 1
    out=$(perl -e 'alarm 200; exec @ARGV' "$AGG" bond-selftest --server 127.0.0.1:18443 --token-file "$T/token" --url http://127.0.0.1:18080/big.bin --sha "$SHA" 2>/dev/null)
    f1=$(echo "$out" | num 's/^fetch 1 .* = \([0-9.]*\) Mbit\/s.*/\1/p'); f2=$(echo "$out" | num 's/^fetch 2 .* = \([0-9.]*\) Mbit\/s.*/\1/p')
    sc=$(perl -e 'alarm 300; exec @ARGV' "$AGG" bond-selftest --server 127.0.0.1:18443 --token-file "$T/token" --url http://127.0.0.1:18080/big.bin --sha "$SHA" --scenarios unequal,deep,stall,upload --measure-only 2>/dev/null)
    echo "$sc" | grep -E "^SCENARIO|legs:" | sed "s/^/  $mode /" | cut -c1-600
    un=$(echo "$sc" | num 's/^SCENARIO unequal[^:]*: \([0-9.]*\) Mbit.*/\1/p'); dp=$(echo "$sc" | num 's/^SCENARIO deep[^:]*: \([0-9.]*\) Mbit.*/\1/p')
    gap=$(echo "$sc" | num 's/^SCENARIO stall.*longest wait in the stream \([0-9.]*\) s.*/\1/p'); up=$(echo "$sc" | num 's/^SCENARIO upload[^:]*: \([0-9.]*\) Mbit.*/\1/p')
    echo "round $round $mode: fetch1 ${f1:-?} fetch2 ${f2:-?} unequal ${un:-?} deep ${dp:-?} stallgap ${gap:-?} upload ${up:-?}" | tee -a "$T/results"
    kill $RP 2>/dev/null; wait $RP 2>/dev/null; sleep 1
  done
done
unset CK_BOND_LEGACY
echo "--- relay (v95, last round)"; grep -E "scheduler|legs," "$T/relay-v95-$N.log" | tail -6 | cut -c1-500
echo "--- medians (Mbit/s; stallgap = the longest wait in the stream, seconds)"
python3 - "$T/results" <<'PYEND'
import re, statistics, sys
rows = open(sys.argv[1]).read().splitlines()
for mode in ("v92", "v95"):
    out = []
    for k in ("fetch1", "fetch2", "unequal", "deep", "stallgap", "upload"):
        v = [float(x) for l in rows if f" {mode}:" in l for x in re.findall(rf"{k} ([0-9.]+)", l)]
        out.append(f"{k} {statistics.median(v):.2f} [{min(v):.2f}-{max(v):.2f}]" if v else f"{k} ?")
    print(f"{mode}: " + "; ".join(out))
PYEND
kill $HTTP 2>/dev/null
exit 0
