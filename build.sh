#!/bin/bash
# Builds Network Aggregate Connection Keeper (Mantra).app (the stripe + the keeper inside it), signs it with
# "Mantra Apps", installs it in /Applications and zips it as N-connection-keeper-vN.zip.
# It does NOT load the LaunchAgent: that is ./agent.sh load.
set -euo pipefail
cd "$(dirname "$0")"

V=$(grep -E '^let CKVersion' Sources/Shared/Model.swift | grep -oE '[0-9]+')
NAME="Network Aggregate Connection Keeper (Mantra)"
APP="build/$NAME.app"

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/Daemon/*.swift -o "$APP/Contents/MacOS/connection-keeperd"
swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/Aggregate/*.swift -o "$APP/Contents/MacOS/ck-aggregate"
swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/Net/*.swift -o "$APP/Contents/MacOS/ck-net"
swiftc -O -swift-version 5 Sources/Tunnel/*.swift -o "$APP/Contents/MacOS/ck-tunnel"
# hev-socks5-tunnel (MIT, github.com/heiher/hev-socks5-tunnel) for the virtual device: fetched once, pinned by its
# fingerprint, never kept in this repository (on the Download Monitor first; 316 KB of SIM data).
HEV=Resources/tunnel/hev-socks5-tunnel
HEVSHA=c72e2d99b698542105e10777a5105a60bb04f4d80bfbf95f20f3365cb77e5d47
if [ "$(shasum -a 256 "$HEV" 2>/dev/null | cut -d' ' -f1)" != "$HEVSHA" ]; then
  python3 ~/Developer/DOWNLOAD_MONITOR/dlmon.py add hev-socks5-tunnel --name "hev-socks5-tunnel 2.19.0" --want-mb 0.3 --file "$PWD/$HEV" --info "Connection Keeper build" || true
  curl -sL -o "$HEV" https://github.com/heiher/hev-socks5-tunnel/releases/download/2.19.0/hev-socks5-tunnel-darwin-arm64
  [ "$(shasum -a 256 "$HEV" | cut -d' ' -f1)" = "$HEVSHA" ] || { echo "hev-socks5-tunnel: wrong fingerprint, not used"; rm -f "$HEV"; exit 1; }
  chmod +x "$HEV"
fi
mkdir -p "$APP/Contents/Resources/tunnel" && cp Resources/tunnel/hev-socks5-tunnel Resources/tunnel/LICENSE "$APP/Contents/Resources/tunnel/"
# ck-phone (v17, request 36): the phone's half of a phone line over USB, a SOCKS5 server for Android (arm64)
mkdir -p "$APP/Contents/Resources/phone"
(cd Sources/Phone && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o "../../$APP/Contents/Resources/phone/ck-phone" main.go)
# ck-wires (v21, request 39): WIRES | WI-FI, the radios off or back
cp Tools/ck-wires "$APP/Contents/Resources/ck-wires" && chmod +x "$APP/Contents/Resources/ck-wires"
# ck-claude (v46, request 65): Claude Code's connection drops, followed while the app runs
cp Tools/ck-claude "$APP/Contents/Resources/ck-claude" && chmod +x "$APP/Contents/Resources/ck-claude"
swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/App/*.swift -framework AppKit -o "$APP/Contents/MacOS/Connection Keeper"
sed "s/__VERSION__/$V/g" Resources/Info.plist > "$APP/Contents/Info.plist"
swift Tools/make_icon.swift build/AppIcon.iconset "$V"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force -s "Mantra Apps" -i com.mantra.connectionkeeper.keeper "$APP/Contents/MacOS/connection-keeperd"
codesign --force -s "Mantra Apps" -i com.mantra.connectionkeeper.aggregate "$APP/Contents/MacOS/ck-aggregate"
codesign --force -s "Mantra Apps" -i com.mantra.connectionkeeper.net "$APP/Contents/MacOS/ck-net"
codesign --force -s "Mantra Apps" -i com.mantra.connectionkeeper.tunnel "$APP/Contents/MacOS/ck-tunnel"
codesign --force -s "Mantra Apps" "$APP"
codesign --verify --deep "$APP"

if pgrep -xq "Connection Keeper"; then echo "the stripe is running: quit it first, then build again"; exit 1; fi
rm -rf "/Applications/$NAME.app"
cp -R "$APP" /Applications/
ditto -c -k --keepParent "$APP" "build/$V-connection-keeper-v$V.zip"
mkdir -p ~/.local/bin && ln -sf "/Applications/$NAME.app/Contents/MacOS/ck-net" ~/.local/bin/ck-net
echo "built v$V: /Applications/$NAME.app and build/$V-connection-keeper-v$V.zip"
