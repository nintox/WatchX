#!/bin/bash
# WatchX – Made by Rikerud
# Double-click to install the alert bridge. It runs in the background and
# starts automatically every time you log in to your Mac.

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/WatchX"   # the bridge runs from here, so addon updates can't break it
LABEL="no.rikerud.watchx"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGFILE="$HOME/Library/Logs/WatchX-bridge.log"
DRY=0; [ "$1" = "--dry-run" ] && DRY=1 && PLIST="${2:-/tmp/$LABEL.plist}"

echo "======================================"
echo "  WatchX – phone alerts"
echo "  Made by Rikerud"
echo "======================================"
echo

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Find the game's _forever_ folder.
is_wow() { [ -n "$1" ] && { [ -d "$1/WTF" ] || [ -d "$1/Interface/AddOns" ]; }; }
WOW="${NW_ROOT:-}"
is_wow "$WOW" || WOW="$(cd "$SRC/../../../.." 2>/dev/null && pwd)"   # run from Interface/AddOns/WatchX/bridge
is_wow "$WOW" || WOW="/Applications/World of Warcraft/_forever_"
is_wow "$WOW" || WOW="$(mdfind 'kMDItemFSName == "_forever_"' 2>/dev/null | while read -r p; do is_wow "$p" && echo "$p" && break; done)"
while ! is_wow "$WOW"; do
    echo "Couldn't find World of Warcraft's _forever_ folder."
    echo "Drag the _forever_ folder (inside your World of Warcraft folder) into this window and press Enter:"
    read -r WOW
    WOW="$(printf '%s' "$WOW" | sed -e 's/\\\(.\)/\1/g' -e 's/^[[:space:]"]*//' -e 's/[[:space:]"]*$//' -e 's:/*$::')"
    if [ -z "$WOW" ]; then echo "Cancelled."; read -r -p "Press Enter to close."; exit 1; fi
    is_wow "$WOW/_forever_" && WOW="$WOW/_forever_"
done
echo "World of Warcraft: $WOW"
echo

# Copy the bridge to its own folder and remember where the game is.
mkdir -p "$DEST" "$(dirname "$PLIST")" "$HOME/Library/Logs"
if [ "$SRC" != "$DEST" ]; then
    if ! cp -f "$SRC/watchx_bridge.sh" "$SRC/watchx_decode.js" "$DEST/"; then
        echo "Couldn't copy the bridge to $DEST."
        read -r -p "Press Enter to close."; exit 1
    fi
    cp -f "$SRC/Uninstall (Mac).command" "$SRC/Cloud sync (Mac).command" "$DEST/" 2>/dev/null
fi
printf '%s\n' "$WOW" > "$DEST/wow_folder.txt"
DIR="$DEST"
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null
chmod +x "$DIR/watchx_bridge.sh" "$DIR"/*.command 2>/dev/null

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$(xml "$DIR/watchx_bridge.sh")</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>$(xml "$LOGFILE")</string>
    <key>StandardErrorPath</key><string>$(xml "$LOGFILE")</string>
</dict>
</plist>
EOF

if ! plutil -lint "$PLIST" >/dev/null; then
    echo "Something went wrong while creating the startup file ($PLIST)."
    read -r -p "Press Enter to close."; exit 1
fi
if [ $DRY = 1 ]; then echo "(dry-run) Wrote $PLIST"; exit 0; fi

# Stop any old bridge and start the new one.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
pkill -f "watchx_bridge.sh" 2>/dev/null
sleep 1
: > "$LOGFILE"
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
    launchctl load -w "$PLIST"
fi
sleep 2

# loaded and really running (a loaded job that stopped would pass "launchctl list")
if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running"; then
    echo "✅ The bridge is installed and running in the background."
    echo "   It starts automatically when you log in to your Mac."
else
    echo "⚠️  The bridge doesn't seem to be running. Log: $LOGFILE"
fi
echo
echo "--- Status ---"
cat "$LOGFILE"
echo "--------------"
echo
echo "Next step in game: type /wx and press Settings, paste your"
echo "ntfy URL and/or Discord webhook and press \"Save & reload\"."
echo
echo "Several computers? Double-click \"Cloud sync (Mac).command\" to keep WatchX's"
echo "settings in step through iCloud Drive, Dropbox, OneDrive or Google Drive."
echo
read -r -p "Send a test alert now? (y/n) " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    /bin/bash "$DIR/watchx_bridge.sh" --test
fi
echo
read -r -p "Done! Press Enter to close this window."
