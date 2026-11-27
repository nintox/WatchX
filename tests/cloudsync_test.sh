#!/bin/bash
# The bridge's cloud sync (Mac): up when yours changed, down when the cloud's did (never while the game runs), the
# cloud's taken on a new computer, both changed -> yours wins + .conflict. Runs on a Mac only (stat -f).
[ "$(uname)" = Darwin ] || { echo "cloud sync: skipped (not a Mac)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
check() { if eval "$1"; then echo "ok   $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
mk() {   # <name>: a computer with its own game folder and bridge folder, one account
    mkdir -p "$T/$1/wow/WTF/Account/ACC1/SavedVariables" "$T/$1/bridge"
    printf '%s\n' "$T/cloud" > "$T/$1/bridge/cloud_folder.txt"
}
on() {   # <name>: load the bridge as that computer
    NW_ROOT="$T/$1/wow" WATCHX_LIB=1 TMPDIR="$T/tmp/" . "$(dirname "$0")/../bridge/watchx_bridge.sh" >/dev/null 2>&1
    DIR="$T/$1/bridge"; CLOUD_CFG="$DIR/cloud_folder.txt"; SYNC_DIR="$DIR/sync"; ROOT="$T/$1/wow"
    log() { :; }
    wow_running() { [ "$GAME" = 1 ]; }
    CLOUD_AT=0
}
sync() { CLOUD_AT=0; cloud_sync; }
mkdir -p "$T/cloud" "$T/tmp"
mk A; mk B
LA="$T/A/wow/WTF/Account/ACC1/SavedVariables/WatchX.lua"; LB="$T/B/wow/WTF/Account/ACC1/SavedVariables/WatchX.lua"
C="$T/cloud/WatchX/ACC1/WatchX.lua"
GAME=0
echo 'WatchXDB = { ["v"] = "A1" }' > "$LA"
on A; sync
check '[ -f "$C" ] && grep -q A1 "$C"' "A: the cloud has none -> A's sent up"
echo 'WatchXDB = { ["v"] = "B0" }' > "$LB"
GAME=1; on B; sync
check 'grep -q B0 "$LB" && grep -q A1 "$C"' "B new, game running: nothing fetched, nothing sent"
GAME=0; sync
check 'grep -q A1 "$LB"' "B new, game closed: the cloud's (A's) taken"
check 'grep -q B0 "$LB.before-sync"' "B's own kept as .before-sync"
echo 'WatchXDB = { ["v"] = "B2" }' > "$LB"; sync
check 'grep -q B2 "$C"' "B logs out: sent up"
on A; sync
check 'grep -q B2 "$LA"' "A (game closed): B's fetched"
sync
check 'grep -q B2 "$LA" && grep -q B2 "$C" && [ ! -f "$C.conflict" ]' "in step: nothing more happens"
echo 'WatchXDB = { ["v"] = "A3" }' > "$LA"
on B; echo 'WatchXDB = { ["v"] = "B3" }' > "$LB"; sync
on A; sync
check 'grep -q A3 "$C" && grep -q B3 "$C.conflict"' "both changed: A's (this one) kept, B's saved as .conflict"
on B; GAME=1; sync
check 'grep -q B3 "$LB"' "B with the game running: not touched"
echo "cloud sync: $([ $fails = 0 ] && echo ALL PASSED || echo "$fails FAILED")"
exit $fails
