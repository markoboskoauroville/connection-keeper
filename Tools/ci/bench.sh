#!/bin/bash
# CI only: build ck-aggregate and the relay of several refs, then run their bond selftests (phases 1-2: one stream over the
# three emulated lines, then a line silenced) interleaved, N rounds, and print the medians. HEAD also gets a UDP RTT probe.
set -u
B=/tmp/bench; mkdir -p $B/bin
case "$1" in
build)
  for r in $2; do
    rm -rf $B/src-$r; git worktree add -f $B/src-$r "$r" >/dev/null 2>&1 || { echo "no ref $r"; exit 1; }
    ( cd $B/src-$r && swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/Aggregate/*.swift -o $B/bin/agg-$r 2>&1 | grep -E "error" ; true )
    ( cd $B/src-$r/Sources/Bond/server && go build -o $B/bin/relay-$r . )
    ls -la $B/bin/agg-$r $B/bin/relay-$r || exit 1
  done ;;
run)
  T=$(mktemp -d)
  head -c 67108864 /dev/urandom > "$T/big.bin"
  SHA=$(shasum -a 256 "$T/big.bin" | cut -d' ' -f1)
  openssl rand -hex 32 > "$T/token"
  python3 -m http.server 18080 --bind 127.0.0.1 --directory "$T" >/dev/null 2>&1 &
  python3 Tools/ci/udp_echo.py 18053 &
  sleep 1
  for round in $(seq 1 "$3"); do
    for r in $2; do
      $B/bin/relay-$r -listen 127.0.0.1:18443 -token-file "$T/token" -allow-local 2>/dev/null &
      RP=$!; sleep 1
      out=$(perl -e 'alarm 200; exec @ARGV' $B/bin/agg-$r bond-selftest --server 127.0.0.1:18443 --token-file "$T/token" --url http://127.0.0.1:18080/big.bin --sha "$SHA" 2>/dev/null)
      f1=$(echo "$out" | sed -n 's/^fetch 1 .* = \([0-9.]*\) Mbit\/s.*/\1/p'); f2=$(echo "$out" | sed -n 's/^fetch 2 .* = \([0-9.]*\) Mbit\/s.*/\1/p')
      sh1=$(echo "$out" | grep -A3 '^fetch 1' | grep carried | sed 's/ *\(line.\) carried \([0-9.]*\)%.*/\1 \2/' | tr '\n' ' ')
      echo "round $round $r: fetch1 ${f1:-?} Mbit/s, fetch2 ${f2:-?} Mbit/s; shares $sh1" | tee -a $T/results
      kill $RP 2>/dev/null; wait $RP 2>/dev/null; pkill -f "relay-$r" 2>/dev/null; sleep 1
    done
  done
  echo "--- medians (fetch 1, one stream; fetch 2, after a line was silenced)"
  for r in $2; do
    python3 - "$r" "$T/results" <<'PY'
import re, statistics, sys
r, f = sys.argv[1], sys.argv[2]
a = [l for l in open(f) if f" {r}: " in l]
f1 = [float(x) for l in a for x in re.findall(r"fetch1 ([0-9.]+)", l)]
f2 = [float(x) for l in a for x in re.findall(r"fetch2 ([0-9.]+)", l)]
m = lambda v: f"{statistics.median(v):.1f}" if v else "?"
print(f"{r:>6}: fetch1 median {m(f1)} Mbit/s {f1}   fetch2 median {m(f2)} {f2}")
PY
  done
  echo "--- UDP round trip (HEAD), three times"
  for i in 1 2 3; do
    $B/bin/relay-HEAD -listen 127.0.0.1:18443 -token-file "$T/token" -allow-local 2> $T/relay-udp.log &
    RP=$!; sleep 1
    perl -e 'alarm 60; exec @ARGV' $B/bin/agg-HEAD bond-selftest --server 127.0.0.1:18443 --token-file "$T/token" --url http://127.0.0.1:18080/big.bin --sha "$SHA" --udp-echo 127.0.0.1:18053 --udp-rtt-only 2>&1 | grep -E "UDP RTT|FAIL|legs up|BOND leg|t\+"
    echo "  relay:"; sed 's/^/    /' $T/relay-udp.log | tail -12
    kill $RP; wait $RP 2>/dev/null; sleep 1
  done ;;
esac
