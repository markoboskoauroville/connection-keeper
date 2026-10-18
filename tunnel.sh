#!/bin/bash
# The virtual device mantra_networkaggregate (v14): the root helper ck-tunnel as the LaunchDaemon
# com.mantra.connectionkeeper.tunnel. Free road, no Apple developer account (LESSONS, 18.10.2026).
#   sudo ./tunnel.sh install     copy ck-tunnel and hev-socks5-tunnel out of the installed app into
#                                /Library/PrivilegedHelperTools (root's, so nobody else can change what root runs), start it
#   sudo ./tunnel.sh uninstall   stop it, remove the half routes, remove it
#   ./tunnel.sh status           is it loaded, is the device up, the last lines of its log
# Up or down it follows the stripe's JOIN ticks; nothing here turns aggregation on.
set -euo pipefail
LABEL=com.mantra.connectionkeeper.tunnel
DIR=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
APP="/Applications/Connection Keeper (Mantra).app"
LOG=/Library/Logs/connection-keeper-tunnel.log

case "${1:-status}" in
  install)
    [ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo ./tunnel.sh install"; exit 1; }
    [ -x "$APP/Contents/MacOS/ck-tunnel" ] || { echo "not built: ./build.sh first"; exit 1; }
    USERHOME=$(dscl . -read "/Users/${SUDO_USER:?run it with sudo from your own account}" NFSHomeDirectory | awk '{print $2}')
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    mkdir -p "$DIR"
    cp "$APP/Contents/MacOS/ck-tunnel" "$APP/Contents/Resources/tunnel/hev-socks5-tunnel" "$DIR/"
    chown -R root:wheel "$DIR"; chmod 755 "$DIR" "$DIR/ck-tunnel" "$DIR/hev-socks5-tunnel"
    sed -e "s|__DIR__|$DIR|g" -e "s|__HOME__|$USERHOME|g" -e "s|__LOG__|$LOG|g" "$(dirname "$0")/launchd/$LABEL.plist" > "$PLIST"
    chown root:wheel "$PLIST"; chmod 644 "$PLIST"
    launchctl bootstrap system "$PLIST"
    sleep 2
    launchctl print "system/$LABEL" | grep -E '^\s*(state|pid) =' || true
    tail -3 "$LOG" 2>/dev/null || true ;;
  uninstall)
    [ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo ./tunnel.sh uninstall"; exit 1; }
    launchctl bootout "system/$LABEL" 2>/dev/null && echo "stopped" || echo "was not running"
    route -q -n delete -net 0.0.0.0/1 -interface utun99 2>/dev/null || true
    route -q -n delete -net 128.0.0.0/1 -interface utun99 2>/dev/null || true
    rm -rf "$DIR" "$PLIST"; echo "removed" ;;
  status)
    launchctl print "system/$LABEL" 2>/dev/null | grep -E '^\s*(state|pid) =' || echo "not installed"
    echo "device: $(cat "$DIR/state" 2>/dev/null || echo "?")"
    tail -5 "$LOG" 2>/dev/null || true ;;
  *) echo "usage: sudo $0 install | sudo $0 uninstall | $0 status"; exit 2 ;;
esac
