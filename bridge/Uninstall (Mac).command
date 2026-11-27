#!/bin/bash
# WatchX – Made by Rikerud. Double-click to remove the alert bridge.
LABEL="no.rikerud.watchx"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null
pkill -f "watchx_bridge.sh" 2>/dev/null
rm -f "$PLIST" "$HOME/.watchx-bridge.pid"
DEST="$HOME/Library/Application Support/WatchX"
rm -f "$DEST/watchx_bridge.sh" "$DEST/watchx_decode.js" "$DEST/wow_folder.txt" "$DEST/Uninstall (Mac).command" \
      "$DEST/Cloud sync (Mac).command" "$DEST/cloud_folder.txt"
rm -rf "$DEST/sync"   # (what was last in step; the files in your cloud folder are left as they are)
rmdir "$DEST" 2>/dev/null   # only when nothing else is left in it
# its work folder (the old spot in /tmp too) and its log
rm -rf "${TMPDIR:-$HOME/Library/Caches}/watchx-bridge" "$HOME/Library/Caches/watchx-bridge" "/tmp/watchx-bridge" 2>/dev/null
rm -f "$HOME/Library/Logs/WatchX-bridge.log"
echo "The WatchX bridge has been stopped and removed. (The in-game addon is untouched.)"
read -r -p "Press Enter to close."
