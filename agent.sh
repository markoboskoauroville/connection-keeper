#!/bin/bash
# The keeper and, since v13, the aggregation server as LaunchAgents (they run as Marko, at login, and are restarted
# if they stop).
#   ./agent.sh load      install ~/Library/LaunchAgents/com.mantra.connectionkeeper{,.aggregate}.plist and start them
#   ./agent.sh unload    stop them and remove the plists, macOS's proxy off (the stripe stays; "keeper not running")
#   ./agent.sh status    are they running, and the last lines of their logs
set -euo pipefail
cd "$(dirname "$0")"
LABEL=com.mantra.connectionkeeper
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
KEEPER="/Applications/Network Aggregate Connection Keeper (Mantra).app/Contents/MacOS/connection-keeperd"
AGG=com.mantra.connectionkeeper.aggregate
AGGPLIST="$HOME/Library/LaunchAgents/$AGG.plist"
AGGBIN="/Applications/Network Aggregate Connection Keeper (Mantra).app/Contents/MacOS/ck-aggregate"

case "${1:-status}" in
  load)
    [ -x "$KEEPER" ] || { echo "not installed: run ./build.sh first"; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    sed "s|__HOME__|$HOME|g" launchd/$LABEL.plist > "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    sleep 3
    launchctl print "gui/$(id -u)/$LABEL" | grep -E '^\s*(state|pid) =' || true
    tail -3 "$HOME/Library/Logs/connection-keeper.log"
    sed "s|__HOME__|$HOME|g" launchd/$AGG.plist > "$AGGPLIST"
    launchctl bootout "gui/$(id -u)/$AGG" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGGPLIST"
    sleep 2
    launchctl print "gui/$(id -u)/$AGG" | grep -E '^\s*(state|pid) =' || true
    tail -2 "$HOME/Library/Logs/connection-keeper-aggregate.log" 2>/dev/null || true ;;
  unload)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null && echo "stopped" || echo "was not running"
    rm -f "$PLIST"
    [ -x "$AGGBIN" ] && "$AGGBIN" off >/dev/null || true
    launchctl bootout "gui/$(id -u)/$AGG" 2>/dev/null && echo "aggregation server stopped, macOS's proxy off" || true
    rm -f "$AGGPLIST" ;;
  status)
    launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E '^\s*(state|pid) =' || echo "not loaded"
    tail -5 "$HOME/Library/Logs/connection-keeper.log" 2>/dev/null || true
    launchctl print "gui/$(id -u)/$AGG" 2>/dev/null | grep -E '^\s*(state|pid) =' || echo "aggregation server not loaded"
    tail -3 "$HOME/Library/Logs/connection-keeper-aggregate.log" 2>/dev/null || true ;;
  *) echo "usage: $0 load | unload | status"; exit 2 ;;
esac
