#!/bin/bash
# WatchX – Made by Rikerud. Double-click to sync WatchX's settings through a cloud folder (iCloud Drive, Dropbox,
# OneDrive, Google Drive): pick the folder here, and the same folder on your other computer. The bridge (installed
# with "Install (Mac).command") then keeps the settings in step: copied up when you log out, down before you play.
DEST="$HOME/Library/Application Support/WatchX"
CFG="$DEST/cloud_folder.txt"
LOGFILE="$HOME/Library/Logs/WatchX-bridge.log"

echo "======================================"
echo "  WatchX – cloud sync"
echo "  Made by Rikerud"
echo "======================================"
echo
if [ ! -f "$DEST/watchx_bridge.sh" ]; then
    echo "The bridge isn't installed yet – double-click \"Install (Mac).command\" first."
    read -r -p "Press Enter to close."; exit 1
fi
NOW="$(head -n 1 "$CFG" 2>/dev/null)"
if [ -n "$NOW" ]; then
    A="$(osascript -e "button returned of (display dialog \"WatchX syncs to:
$NOW\" buttons {\"Turn off\", \"Keep it\", \"Pick another\"} default button \"Keep it\" with title \"WatchX cloud sync\")" 2>/dev/null)"
    case "$A" in
        "Turn off") rm -f "$CFG"; echo "Cloud sync is off."; read -r -p "Press Enter to close."; exit 0 ;;
        "Pick another") ;;
        *) echo "Nothing changed."; read -r -p "Press Enter to close."; exit 0 ;;
    esac
fi
START="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
[ -d "$START" ] || START="$HOME"
PICK="$(osascript -e "POSIX path of (choose folder with prompt \"Pick a folder your cloud keeps in step (iCloud Drive, Dropbox, OneDrive, Google Drive)\" default location POSIX file \"$START\")" 2>/dev/null)"
PICK="${PICK%/}"
if [ -z "$PICK" ]; then echo "Nothing changed."; read -r -p "Press Enter to close."; exit 0; fi
[ "$(basename "$PICK")" = "WatchX" ] && PICK="$(dirname "$PICK")"   # (picked a WatchX folder itself: that one is used)
# WatchX's own folder in it, made now (the bridge keeps each WoW account's settings in there)
if ! mkdir -p "$PICK/WatchX"; then
    echo "Couldn't make a folder in $PICK – pick another one."
    read -r -p "Press Enter to close."; exit 1
fi
printf '%s\n' "$PICK" > "$CFG"
echo "Cloud sync: $PICK/WatchX (made – your settings go in there)"
open "$PICK/WatchX" 2>/dev/null
echo "Checking that the bridge can use it…"
sleep 8
LINE="$(grep "Cloud sync:" "$LOGFILE" 2>/dev/null | tail -n 1)"
echo "${LINE:-(nothing from the bridge yet – is it running? Install (Mac).command starts it)}"
case "$LINE" in
    *"won't let"*)
        echo
        echo "macOS keeps background helpers out of some folders. Either pick a folder in your home folder"
        echo "that your cloud app syncs (e.g. ~/Dropbox), or: System Settings > Privacy & Security >"
        echo "Full Disk Access > + > press Cmd+Shift+G, type /bin/bash, Open – then run this again."
        ;;
esac
echo
echo "Do the same on your other computer, with the same folder. Play on one computer at a time."
read -r -p "Done! Press Enter to close."
