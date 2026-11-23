#!/bin/bash
# WatchX – Made by Rikerud. Double-click to remove the alert bridge.
LABEL="no.rikerud.watchx"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null
pkill -f "watchx_bridge.sh" 2>/dev/null
rm -f "$PLIST" "$HOME/.watchx-bridge.pid"
DEST="$HOME/Library/Application Support/WatchX"
rm -f "$DEST/watchx_bridge.sh" "$DEST/watchx_decode.js" "$DEST/wow_folder.txt"
echo "The WatchX bridge has been stopped and removed. (The in-game addon is untouched.)"
read -r -p "Press Enter to close."
