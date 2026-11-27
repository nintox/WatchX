#!/bin/bash
# WatchX – Made by Rikerud
# Double-click to set up the WatchX bridge: phone alerts, cloud sync of your settings, or both – or to remove it.
# The bridge runs in the background (no window) and starts by itself every time you log in to your Mac.
# Run it again any time to change your choice or the cloud folder.

SRC="$(cd "$(dirname "$0")" && pwd)"
SELF="$SRC/$(basename "$0")"
DEST="$HOME/Library/Application Support/WatchX"   # the bridge runs from here, so addon updates can't break it
LABEL="no.rikerud.watchx"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGFILE="$HOME/Library/Logs/WatchX-bridge.log"
DRY=0
if [ "$1" = "--dry-run" ]; then   # (a test: everything in a folder of its own – the real bridge isn't touched)
    DRY=1
    DEST="${2:-$(mktemp -d)}"
    PLIST="$DEST/$LABEL.plist" LOGFILE="$DEST/bridge.log"
fi
CFG="$DEST/cloud_folder.txt"

bye() { echo; read -r -p "${1:-Press Enter to close.}"; exit "${2:-0}"; }

echo "======================================"
echo "  WatchX bridge – Made by Rikerud"
echo "======================================"
echo
echo "What do you want?"
echo "  1) Phone alerts   – stealth, KOS, rares … on your phone (ntfy / Discord)"
echo "  2) Cloud sync     – the same WatchX settings on all your computers"
echo "  3) Both"
echo "  4) Remove the WatchX bridge"
echo
read -r -p "Type 1, 2, 3 or 4 and press Enter [3]: " CHOICE
case "${CHOICE:-3}" in
    1) MODE=alerts ;;
    2) MODE=sync ;;
    3) MODE=both ;;
    4) MODE=remove ;;
    *) echo "That isn't 1, 2, 3 or 4 – nothing changed."; bye ;;
esac
echo

stop_bridge() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null
    pkill -f "watchx_bridge.sh" 2>/dev/null
}

# ---- remove
if [ "$MODE" = remove ]; then
    [ $DRY = 1 ] && { echo "(dry-run) would remove the bridge"; exit 0; }
    stop_bridge
    rm -f "$PLIST" "$HOME/.watchx-bridge.pid"
    rm -f "$DEST/watchx_bridge.sh" "$DEST/watchx_decode.js" "$DEST/wow_folder.txt" "$DEST/mode.txt" "$CFG" \
          "$DEST/Install (Mac).command" "$DEST/Uninstall (Mac).command" "$DEST/Cloud sync (Mac).command"
    rm -rf "$DEST/sync"   # (what was last in step; the files in your cloud folder are left as they are)
    rmdir "$DEST" 2>/dev/null   # only when nothing else is left in it
    rm -rf "${TMPDIR:-$HOME/Library/Caches}/watchx-bridge" "$HOME/Library/Caches/watchx-bridge" 2>/dev/null
    rm -f "$LOGFILE"
    echo "The WatchX bridge has been stopped and removed. (The in-game addon is untouched.)"
    bye
fi

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# ---- find the game's _forever_ folder
is_wow() { [ -n "$1" ] && { [ -d "$1/WTF" ] || [ -d "$1/Interface/AddOns" ]; }; }
WOW="${NW_ROOT:-}"
is_wow "$WOW" || WOW="$(head -n 1 "$DEST/wow_folder.txt" 2>/dev/null)"   # (set up before)
is_wow "$WOW" || WOW="$(cd "$SRC/../../../.." 2>/dev/null && pwd)"   # run from Interface/AddOns/WatchX/bridge
is_wow "$WOW" || WOW="/Applications/World of Warcraft/_forever_"
is_wow "$WOW" || WOW="$(mdfind 'kMDItemFSName == "_forever_"' 2>/dev/null | while read -r p; do is_wow "$p" && echo "$p" && break; done)"
while ! is_wow "$WOW"; do
    echo "Couldn't find World of Warcraft's _forever_ folder."
    echo "Drag the _forever_ folder (inside your World of Warcraft folder) into this window and press Enter:"
    read -r WOW
    WOW="$(printf '%s' "$WOW" | sed -e 's/\\\(.\)/\1/g' -e 's/^[[:space:]"]*//' -e 's/[[:space:]"]*$//' -e 's:/*$::')"
    [ -z "$WOW" ] && { echo "Cancelled."; bye "Press Enter to close." 1; }
    is_wow "$WOW/_forever_" && WOW="$WOW/_forever_"
done
echo "World of Warcraft: $WOW"

# ---- the cloud folder (2 and 3): a WatchX folder is made in the one you pick
if [ "$MODE" != alerts ]; then
    NOW="$(head -n 1 "$CFG" 2>/dev/null)"
    PICK=""
    if [ -n "$NOW" ] && [ -d "$NOW" ]; then
        read -r -p "Cloud folder: $NOW/WatchX – keep it? (Enter = keep, c = choose another) " A
        [ "$A" = c ] || [ "$A" = C ] || PICK="$NOW"
    fi
    if [ -z "$PICK" ]; then
        echo "Pick the folder your cloud keeps in step (iCloud Drive, Dropbox, OneDrive, Google Drive)…"
        START="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
        [ -d "$START" ] || START="$HOME"
        PICK="$(osascript -e "POSIX path of (choose folder with prompt \"WatchX cloud sync: pick a folder your cloud keeps in step (iCloud Drive, Dropbox, OneDrive, Google Drive)\" default location POSIX file \"$START\")" 2>/dev/null)"
        PICK="${PICK%/}"
    fi
    [ -n "$PICK" ] && [ "$(basename "$PICK")" = "WatchX" ] && PICK="$(dirname "$PICK")"   # (a WatchX folder itself)
    if [ -z "$PICK" ]; then
        if [ "$MODE" = sync ]; then echo "No folder picked – nothing changed."; bye; fi
        echo "No folder picked – phone alerts only for now (run this again to add cloud sync)."
        MODE=alerts
    elif ! mkdir -p "$PICK/WatchX" 2>/dev/null; then
        echo "Couldn't make a folder in $PICK – run this again and pick another one."
        [ "$MODE" = sync ] && bye "Press Enter to close." 1
        MODE=alerts
    else
        echo "Cloud folder: $PICK/WatchX (your settings go in there)"
    fi
fi
echo

# ---- copy the bridge to its own folder; what it does
mkdir -p "$DEST" "$(dirname "$PLIST")" "$HOME/Library/Logs"
if [ "$SRC" != "$DEST" ]; then
    if ! cp -f "$SRC/watchx_bridge.sh" "$SRC/watchx_decode.js" "$DEST/"; then
        echo "Couldn't copy the bridge to $DEST."
        bye "Press Enter to close." 1
    fi
    cp -f "$SELF" "$DEST/Install (Mac).command" 2>/dev/null   # (to run again from there: change, or remove)
    rm -f "$DEST/Uninstall (Mac).command" "$DEST/Cloud sync (Mac).command"   # (the old separate ones)
fi
printf '%s\n' "$WOW" > "$DEST/wow_folder.txt"
printf '%s\n' "$MODE" > "$DEST/mode.txt"
if [ "$MODE" = alerts ]; then rm -f "$CFG"; else printf '%s\n' "$PICK" > "$CFG"; fi
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
    bye "Press Enter to close." 1
fi
if [ $DRY = 1 ]; then echo "(dry-run) Wrote $PLIST"; exit 0; fi

# ---- stop any old bridge and start the new one
stop_bridge
sleep 1
: > "$LOGFILE"
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
    launchctl load -w "$PLIST"
fi
sleep 2

# loaded and really running (a loaded job that stopped would pass "launchctl list")
if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running"; then
    echo "✅ The bridge is running in the background. It starts by itself when you log in to your Mac."
else
    echo "⚠️  The bridge doesn't seem to be running. Log: $LOGFILE"
fi
if [ "$MODE" != alerts ]; then
    echo "Checking that it can use the cloud folder…"
    for _ in 1 2 3 4 5 6 7 8; do grep -q "Cloud sync:" "$LOGFILE" 2>/dev/null && break; sleep 1; done
fi
echo
echo "--- Status ---"
cat "$LOGFILE"
echo "--------------"
if [ "$MODE" != alerts ] && grep -q "won't let" "$LOGFILE" 2>/dev/null; then
    echo
    echo "macOS keeps background helpers out of some folders. Either run this again and pick a folder in"
    echo "your home folder that your cloud app syncs (e.g. ~/Dropbox), or: System Settings > Privacy & Security >"
    echo "Full Disk Access > + > press Cmd+Shift+G, type /bin/bash, Open – then run this again."
fi
if [ "$MODE" != alerts ]; then
    echo
    echo "Cloud sync: do the same on your other computer (choose 2 or 3, the same folder)."
    echo "Your settings go up when you log out, and come down before you play. Play on one computer at a time."
fi
if [ "$MODE" != sync ]; then
    echo
    echo "Phone alerts – in game: type /wx, press Settings, paste your ntfy link and/or Discord webhook"
    echo "and press \"Save & reload\"."
    echo
    read -r -p "Send a test alert now? (y/n) " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        /bin/bash "$DIR/watchx_bridge.sh" --test
    fi
fi
echo
echo "Run this again any time to change it (or remove it): $DEST/Install (Mac).command"
bye "Done! Press Enter to close this window."
