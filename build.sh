#!/bin/bash
# Builds Connection Keeper (Mantra).app (the stripe + the keeper inside it), signs it with
# "Mantra Apps", installs it in /Applications and zips it as N-connection-keeper-vN.zip.
# It does NOT load the LaunchAgent: that is ./agent.sh load.
set -euo pipefail
cd "$(dirname "$0")"

V=$(grep -E '^let CKVersion' Sources/Shared/Model.swift | grep -oE '[0-9]+')
NAME="Connection Keeper (Mantra)"
APP="build/$NAME.app"

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/Daemon/*.swift -o "$APP/Contents/MacOS/connection-keeperd"
swiftc -O -swift-version 5 Sources/Shared/*.swift Sources/App/*.swift -framework AppKit -o "$APP/Contents/MacOS/Connection Keeper"
sed "s/__VERSION__/$V/g" Resources/Info.plist > "$APP/Contents/Info.plist"
swift Tools/make_icon.swift build/AppIcon.iconset "$V"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force -s "Mantra Apps" -i com.mantra.connectionkeeper.keeper "$APP/Contents/MacOS/connection-keeperd"
codesign --force -s "Mantra Apps" "$APP"
codesign --verify --deep "$APP"

if pgrep -xq "Connection Keeper"; then echo "the stripe is running: quit it first, then build again"; exit 1; fi
rm -rf "/Applications/$NAME.app"
cp -R "$APP" /Applications/
ditto -c -k --keepParent "$APP" "build/$V-connection-keeper-v$V.zip"
echo "built v$V: /Applications/$NAME.app and build/$V-connection-keeper-v$V.zip"
