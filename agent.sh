#!/bin/bash
# The keeper as a LaunchAgent (it runs as Marko, at login, and is restarted if it stops).
#   ./agent.sh load      install ~/Library/LaunchAgents/com.mantra.connectionkeeper.plist and start it
#   ./agent.sh unload    stop it and remove the plist (the stripe stays; it says "keeper not running")
#   ./agent.sh status    is it running, and the last lines of its log
set -euo pipefail
cd "$(dirname "$0")"
LABEL=com.mantra.connectionkeeper
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
KEEPER="/Applications/Connection Keeper (Mantra).app/Contents/MacOS/connection-keeperd"

case "${1:-status}" in
  load)
    [ -x "$KEEPER" ] || { echo "not installed: run ./build.sh first"; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    sed "s|__HOME__|$HOME|g" launchd/$LABEL.plist > "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    sleep 3
    launchctl print "gui/$(id -u)/$LABEL" | grep -E '^\s*(state|pid) =' || true
    tail -3 "$HOME/Library/Logs/connection-keeper.log" ;;
  unload)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null && echo "stopped" || echo "was not running"
    rm -f "$PLIST" ;;
  status)
    launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E '^\s*(state|pid) =' || echo "not loaded"
    tail -5 "$HOME/Library/Logs/connection-keeper.log" 2>/dev/null || true ;;
  *) echo "usage: $0 load | unload | status"; exit 2 ;;
esac
