#!/bin/bash
# WatchX bridge (Mac) – Made by Rikerud
#
# Sends WatchX alerts to ntfy and Discord:
#   * instant: watches the Screenshots folder. WatchX takes a screenshot with a small code block in
#     the corner (read by watchx_decode.js); the alert is sent within a second, with the picture.
#   * logout: the game writes its settings file when you're logged out – WatchX notes why (AFK,
#     disconnect); a game that closes without that (a crash) is noticed too.
#   * slow fallback: tagged lines in WoWChatLog.txt (only when screenshots don't work).
# Needs nothing extra – uses bash, curl, sips and osascript, which ship with macOS.
# The URLs are set in game (/wx) and read from WTF/Account/*/SavedVariables/WatchX.lua.
#
# Normally set up by "Install (Mac).command" (alerts, cloud sync or both), which copies it to
# ~/Library/Application Support/WatchX (so addon updates don't touch it).
# Manually:  bash watchx_bridge.sh          (watch)
#            bash watchx_bridge.sh --test   (send a test alert)

DIR="$(cd "$(dirname "$0")" && pwd)"
# The game's _forever_ folder: set by the installer (wow_folder.txt), or the old spot (AddOns/WatchX/bridge).
ROOT="${NW_ROOT:-}"
[ -z "$ROOT" ] && [ -f "$DIR/wow_folder.txt" ] && ROOT="$(head -n 1 "$DIR/wow_folder.txt")"
[ -z "$ROOT" ] && ROOT="$(cd "$DIR/../../../.." && pwd)"
CHATLOG="${NW_CHATLOG:-$ROOT/Logs/WoWChatLog.txt}"
SHOTS="${NW_SHOTS:-$ROOT/Screenshots}"
DECODE="$DIR/watchx_decode.js"
WOW_PROC="$ROOT/World of Warcraft.app/Contents/MacOS/"
PIDFILE="$HOME/.watchx-bridge.pid"
WORK="${TMPDIR:-$HOME/Library/Caches}/watchx-bridge"   # per user (never a shared /tmp folder)
SENT_FILE="$WORK/sent"
UA="WatchX-bridge/2.0"
KEEP_SHOTS=30   # WatchX screenshots kept in Screenshots/WatchX

mkdir -p "$WORK"
log() { echo "[$(date +%H:%M:%S)] $*"; }

sv_file() { ls -t "$ROOT"/WTF/Account/*/SavedVariables/WatchX.lua 2>/dev/null | head -n 1; }

sv_get() {  # <file> <key>  (a string value)
    sed -n "s/^[[:space:]]*\[\"$2\"\] = \"\(.*\)\",[[:space:]]*\$/\1/p" "$1" | head -n 1 \
        | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}
sv_num() {  # <file> <key>  (a number value)
    sed -n "s/^[[:space:]]*\[\"$2\"\] = \([0-9][0-9]*\),[[:space:]]*\$/\1/p" "$1" | head -n 1
}

# WatchX's own key per WoW account (one game folder can hold several): only chat-log lines with one are alerts.
known_keys() {
    local f
    for f in "$ROOT"/WTF/Account/*/SavedVariables/WatchX.lua; do
        [ -f "$f" ] && sv_get "$f" bridgeKey
    done | tr '\n' ' '
}

load_settings() {
    NTFY_URL="" NTFY_TOKEN="" DISCORD_WEBHOOK="" DISCORD_MENTION=""
    SV="$(sv_file)"
    [ -n "$SV" ] || return
    NTFY_URL="$(sv_get "$SV" ntfyUrl)"
    NTFY_TOKEN="$(sv_get "$SV" ntfyToken)"
    DISCORD_WEBHOOK="$(sv_get "$SV" discordWebhook)"
    DISCORD_MENTION="$(sv_get "$SV" discordMention)"
    # "ntfy.sh/topic" works too: add https:// when it's missing
    case "$NTFY_URL" in ""|*://*) ;; *) NTFY_URL="https://$NTFY_URL" ;; esac
    case "$DISCORD_WEBHOOK" in ""|*://*) ;; *) DISCORD_WEBHOOK="https://$DISCORD_WEBHOOK" ;; esac
}

targets() {
    local t=""
    [ -n "$NTFY_URL" ] && t="ntfy"
    [ -n "$DISCORD_WEBHOOK" ] && t="${t:+$t, }Discord"
    echo "${t:-NONE – set it up in game with /wx}"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

urlencode() {  # byte by byte (bash 3.2 on macOS can't do UTF-8 bytes itself)
    local out="" h
    for h in $(printf '%s' "$1" | od -An -v -tx1); do
        case "$h" in
            3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]|2d|2e|5f|7e) out+="$(printf "\\x$h")" ;;
            *) out+="%$h" ;;
        esac
    done
    printf '%s' "$out"
}

curl_code() {  # <curl args...>  -> prints HTTP status, retries on network errors / 429 / 5xx
    local code i wait hdr="$WORK/headers.$$"
    for i in 1 2; do
        code="$(curl -s -o /dev/null -D "$hdr" -w '%{http_code}' --connect-timeout 5 --max-time 15 -A "$UA" "$@")"
        case "$code" in
            2*) break ;;
            4*) [ "$code" = 429 ] || break ;;
        esac
        [ "$i" = 2 ] && break
        wait="$i"
        if [ "$code" = 429 ]; then   # too many: wait as long as the server says (up to 10 s)
            wait="$(tr -d '\r' < "$hdr" 2>/dev/null | sed -n 's/^[Rr]etry-[Aa]fter: *\([0-9][0-9]*\).*/\1/p' | head -n 1)"
            [ -n "$wait" ] || wait=1
            [ "$wait" -gt 10 ] && wait=10
            wait=$((wait + 1))
        fi
        sleep "$wait"
    done
    rm -f "$hdr"
    echo "$code"
}

# The address and token go to curl in a small file only you can read, not on its command line (where any user's
# `ps` would show the webhook, the topic or the token while it sends).
cfg_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }
secret_cfg() {  # <url> [bearer token] -> prints the file's path (remove it after)
    local f="$WORK/req.$$.$RANDOM"
    ( umask 077
      printf 'url = "%s"\n' "$(cfg_escape "$1")" > "$f"
      [ -n "$2" ] && printf 'header = "Authorization: Bearer %s"\n' "$(cfg_escape "$2")" >> "$f" )
    printf '%s' "$f"
}

late_note() {  # <id>  -> " (late: N min)" when the alert is over 2 minutes old (the id starts with its time)
    local id="$1" age
    [ ${#id} -ge 4 ] && [ ${#id} -le 16 ] || return
    age=$(( $(date +%s) - 10#${id:0:${#id}-3} ))
    [ "$age" -gt 120 ] && printf ' (late: %d min)' $((age / 60))
}

already_sent() { grep -qx "$1" "$SENT_FILE" 2>/dev/null; }
mark_sent() {
    echo "$1" >> "$SENT_FILE"
    if [ "$(wc -l < "$SENT_FILE")" -gt 300 ]; then
        tail -n 150 "$SENT_FILE" > "$SENT_FILE.tmp" && mv "$SENT_FILE.tmp" "$SENT_FILE"
    fi
}

ZWSP="$(printf '\342\200\213')"   # a zero-width space: breaks @mentions and [links](...) someone else wrote
notify() {  # <kind> <subject> <text> [image]
    local kind="$1" subject="$2" text="$3" image="$4" title prio tags code
    subject="${subject//@/@$ZWSP}" text="${text//@/@$ZWSP}"
    subject="${subject//](/]$ZWSP(}" text="${text//](/]$ZWSP(}"
    load_settings  # always fresh URLs (changed in game + reload)
    case "$kind" in
        SPAWN)   title="$subject is up!";   prio=5; tags="rotating_light" ;;
        LOOT)    title="$subject dropped!"; prio=5; tags="tada,gem" ;;
        ENEMY)   title="$subject spotted!"; prio=4; tags="crossed_swords" ;;
        PLAYER)  title="$subject found!";   prio=4; tags="eyes" ;;
        FRIEND)  title="$subject nearby";   prio=3; tags="wave" ;;
        ATTACK)  title="You're being attacked!"; prio=5; tags="warning,crossed_swords" ;;
        DEATH)   title="$subject died";     prio=3; tags="skull" ;;
        AFK)     title="AFK logout soon – move!"; prio=5; tags="warning,hourglass" ;;
        LOGOUT)  title="Logging out now!";   prio=5; tags="warning" ;;
        OFFLINE) title="$subject";           prio=5; tags="electric_plug" ;;
        CLOSED)  title="$subject";           prio=3; tags="electric_plug" ;;   # a guess (crash?): no mention
        TEST)    title="WatchX test";        prio=3; tags="test_tube" ;;
        *)       title="WatchX $kind";       prio=3; tags="bell" ;;
    esac
    if [ -z "$NTFY_URL" ] && [ -z "$DISCORD_WEBHOOK" ]; then
        log "  No ntfy/Discord set up in game – nothing sent."
        return
    fi
    local mention=""
    case "$kind" in SPAWN|LOOT|ENEMY|PLAYER|ATTACK|AFK|LOGOUT|OFFLINE) mention="$DISCORD_MENTION " ;; esac

    local cfg
    if [ -n "$NTFY_URL" ]; then
        local url="${NTFY_URL%/}"
        code=""
        if [ -n "$image" ]; then
            # the picture as the body, the rest as query parameters (UTF-8 safe)
            local q="title=$(urlencode "$title")&message=$(urlencode "$text")&priority=$prio&tags=$(urlencode "$tags")&filename=watchx.jpg"
            cfg="$(secret_cfg "$url?$q" "$NTFY_TOKEN")"
            code="$(curl_code -T "$image" -K "$cfg")"; rm -f "$cfg"
            log "  ntfy (with screenshot) -> $code"
        fi
        case "$code" in
            2*) ;;
            429) log "  ntfy: too many requests – not sent again" ;;
            ""|4*)   # no picture, or the picture refused (too big…): the text alone
                local server="${url%/*}" topic="${url##*/}" jtags
                jtags="\"${tags//,/\",\"}\""
                local json="{\"topic\":\"$(json_escape "$topic")\",\"title\":\"$(json_escape "$title")\",\"message\":\"$(json_escape "$text")\",\"priority\":$prio,\"tags\":[$jtags]}"
                cfg="$(secret_cfg "$server/" "$NTFY_TOKEN")"
                log "  ntfy -> $(curl_code -H 'Content-Type: application/json' --data-binary "$json" -K "$cfg")"; rm -f "$cfg"
                ;;
            *) log "  ntfy: not sent again without the picture (it may have arrived; or no network)" ;;
        esac
    fi
    if [ -n "$DISCORD_WEBHOOK" ]; then
        local content="${mention# }**$title**"$'\n'"$text"
        local payload="{\"content\":\"$(json_escape "$content")\"}"
        code=""
        if [ -n "$image" ]; then
            cfg="$(secret_cfg "$DISCORD_WEBHOOK")"
            code="$(curl_code --form-string "payload_json=$payload" -F "files[0]=@$image;filename=watchx.jpg;type=image/jpeg" -K "$cfg")"; rm -f "$cfg"
            log "  discord (with screenshot) -> $code"
        fi
        case "$code" in
            2*) ;;
            429) log "  discord: too many requests – not sent again" ;;
            ""|4*) cfg="$(secret_cfg "$DISCORD_WEBHOOK")"
                   log "  discord -> $(curl_code -H 'Content-Type: application/json' --data-binary "$payload" -K "$cfg")"; rm -f "$cfg" ;;
            *) log "  discord: not sent again without the picture (it may have arrived; or no network)" ;;
        esac
    fi
}

# ---------------------------------------------------------------- instant: screenshots

size_of() { stat -f %z "$1" 2>/dev/null; }

process_shot() {  # <file>
    local f="$1" out="" try s1 s2 kind id subject text
    for try in 1 2 3 4 5 6 7 8 9 10; do
        [ -f "$f" ] || return
        s1="$(size_of "$f")"
        out="$(osascript -l JavaScript "$DECODE" "$f" 2>/dev/null)"
        case "$out" in
            OK*) break ;;
            NO)  sleep 0.2; s2="$(size_of "$f")"; [ "$s1" = "$s2" ] && return ;;   # not ours
            *)   sleep 0.2 ;;                                                    # still being written
        esac
    done
    case "$out" in OK*) ;; *) return ;; esac
    IFS=$'\t' read -r _ kind id subject text <<< "$out"
    already_sent "$id" && return
    mark_sent "$id"
    text="$text$(late_note "$id")"
    log "$kind (instant): $subject – $text"
    # wait until WoW has finished writing the file, then a smaller copy for the phone
    s1=""
    for try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        s2="$(size_of "$f")"
        [ -n "$s2" ] && [ "$s2" = "$s1" ] && break
        s1="$s2"
        sleep 0.15
    done
    local small="$WORK/watchx.jpg" clean="$WORK/clean.jpg" src="$f" image=""
    rm -f "$small" "$clean"
    # a copy with the code block painted over (now that the file is complete)
    osascript -l JavaScript "$DECODE" "$f" "$clean" >/dev/null 2>&1
    [ -s "$clean" ] && src="$clean"
    if sips -Z 1600 -s format jpeg -s formatOptions 75 "$src" --out "$small" >/dev/null 2>&1 && [ -s "$small" ]; then
        image="$small"
    else
        image="$f"
    fi
    notify "$kind" "$subject" "$text" "$image"
    # WatchX's own screenshots go to Screenshots/WatchX (the newest few are kept)
    mkdir -p "$SHOTS/WatchX" && mv -f "$f" "$SHOTS/WatchX/" 2>/dev/null
    ls -t "$SHOTS/WatchX" 2>/dev/null | tail -n +$((KEEP_SHOTS + 1)) | while IFS= read -r old; do
        rm -f "$SHOTS/WatchX/$old"
    done
}

RECENT=""
SHOTS_MTIME=""
check_shots() {
    [ -d "$SHOTS" ] || return
    local f name m
    m="$(stat -f %Fm "$SHOTS" 2>/dev/null)"   # a new picture changes the folder: only then look inside (to the ns)
    [ "$m" = "$SHOTS_MTIME" ] && return
    SHOTS_MTIME="$m"
    touch "$WORK/stamp.next"
    while IFS= read -r f; do
        name="${f##*/}"
        case "|$RECENT|" in *"|$name|"*) continue ;; esac
        RECENT="$name|${RECENT:0:2000}"
        process_shot "$f"
    done < <(find "$SHOTS" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.tga' \) \
                -newer "$WORK/stamp" 2>/dev/null)
    mv -f "$WORK/stamp.next" "$WORK/stamp"
}

# ---------------------------------------------------------------- logged out / game closed

# The game's path at the start of a command line, as plain text (grep would also find its own command line).
wow_running() {
    ps -axo command= 2>/dev/null | P="$WOW_PROC" awk '{ sub(/^ +/, "") } index($0, ENVIRON["P"]) == 1 { f = 1 } END { exit !f }'
}

SV_MTIME="" LAST_EXIT="" WOW_UP="" WOW_SINCE=0 WOW_CHECKED=0
check_exit() {   # every 2 seconds (the settings file and the game process)
    local sv m why at now
    now="$(date +%s)"
    [ $((now - WOW_CHECKED)) -lt 2 ] && return
    WOW_CHECKED="$now"
    sv="$(sv_file)"
    if [ -n "$sv" ]; then
        m="$(stat -f %m "$sv" 2>/dev/null)"
        if [ "$m" != "$SV_MTIME" ]; then
            SV_MTIME="$m"
            why="$(sv_get "$sv" exitWhy)" at="$(sv_num "$sv" exitAt)"
            if [ -n "$at" ] && [ "$at" != "$LAST_EXIT" ] && [ $((now - at)) -lt 120 ]; then
                LAST_EXIT="$at"
                case "$why" in
                    afk)
                        log "Logged out (AFK)"
                        notify OFFLINE "Logged out of WoW (AFK)" "The game logged you out for being AFK."
                        ;;
                    disconnect)
                        # closing the game window looks the same – only a game that keeps running was thrown out
                        sleep 8
                        if wow_running; then
                            log "Logged out / disconnected"
                            notify OFFLINE "Logged out of WoW" "You're no longer in the game (disconnected or logged out)."
                        else
                            log "Game closed"
                        fi
                        ;;
                    *) log "Game: $why" ;;
                esac
            fi
        fi
    fi
    if wow_running; then
        [ "$WOW_UP" = 1 ] || WOW_SINCE="$now"
        WOW_UP=1
    elif [ "$WOW_UP" = 1 ]; then
        WOW_UP=0
        sleep 3   # a normal quit writes the settings file first
        sv="$(sv_file)"; at="$(sv_num "$sv" exitAt)"
        # a crash = no logout written since the game started (sitting at character select for a while is fine)
        if [ -z "$at" ] || [ "$at" -lt "$WOW_SINCE" ]; then
            log "Game closed without logging out (crash?)"
            notify CLOSED "WoW closed" "The game closed without logging out (crash?)."
        fi
        SV_MTIME="$(stat -f %m "$sv" 2>/dev/null)"
    fi
}

# ---------------------------------------------------------------- cloud sync (optional)
# One folder you pick ("Install (Mac).command", 2 or 3, writes it to cloud_folder.txt): a folder iCloud Drive, Dropbox,
# OneDrive or Google Drive keeps in step between your computers. WatchX's settings file of each WoW account is kept
# there as <folder>/WatchX/<account>/WatchX.lua:
#   * yours changed (you logged out or reloaded): copied up
#   * the cloud's changed (another computer) and the game isn't running: copied down (the game reads it at login,
#     and writes over it at logout – so never while it runs). Yours is kept as WatchX.lua.before-sync first.
#   * the first time on a computer, when the cloud already has one: the cloud's is taken (yours kept as above).
# What was last in step is remembered per account (sync/<account>.sum), so it's clear which side changed. Both
# changed (two computers playing at once): yours wins, the cloud's is kept next to it as WatchX.lua.conflict.
CLOUD_CFG="$DIR/cloud_folder.txt"
SYNC_DIR="$DIR/sync"
CLOUD_AT=0 CLOUD_SAID=""
sum_of() { [ -f "$1" ] && cksum < "$1" 2>/dev/null | awk '{ print $1 "-" $2 }'; }
settled() {   # <file>: not being written right now (same size twice, half a second apart)
    local a b
    a="$(stat -f %z "$1" 2>/dev/null)"; sleep 0.5; b="$(stat -f %z "$1" 2>/dev/null)"
    [ -n "$a" ] && [ "$a" = "$b" ]
}
put() {   # <from> <to>: a whole copy or none (a temp file next to it, then renamed)
    mkdir -p "$(dirname "$2")" && cp -p "$1" "$2.watchx-tmp" && mv -f "$2.watchx-tmp" "$2"
}
cloud_say() { [ "$CLOUD_SAID" = "$1" ] || { CLOUD_SAID="$1"; log "Cloud sync: $1"; }; }
cloud_sync() {   # every 5 seconds
    local now cloud acc name L C S base ls cs at
    now="$(date +%s)"
    [ $((now - CLOUD_AT)) -lt 5 ] && return
    CLOUD_AT="$now"
    cloud="$(head -n 1 "$CLOUD_CFG" 2>/dev/null)"
    [ -n "$cloud" ] || { CLOUD_SAID=""; return; }
    if [ ! -d "$cloud" ]; then cloud_say "the folder isn't there: $cloud"; return; fi
    if ! { mkdir -p "$cloud/WatchX" 2>/dev/null && touch "$cloud/WatchX/.watchx-test" 2>/dev/null; }; then
        cloud_say "macOS won't let the bridge use $cloud – pick a folder in your home folder (e.g. Dropbox), or give bash Full Disk Access"
        return
    fi
    rm -f "$cloud/WatchX/.watchx-test"
    cloud_say "on – $cloud/WatchX"
    mkdir -p "$SYNC_DIR"
    for acc in "$ROOT"/WTF/Account/*/; do
        name="$(basename "$acc")"
        [ "$name" = "SavedVariables" ] && continue
        L="${acc}SavedVariables/WatchX.lua" C="$cloud/WatchX/$name/WatchX.lua" S="$SYNC_DIR/$name.sum"
        base="$(cat "$S" 2>/dev/null)" ls="$(sum_of "$L")" cs="$(sum_of "$C")"
        if [ "$ls" = "$cs" ]; then
            [ -n "$ls" ] && [ "$base" != "$ls" ] && echo "$ls" > "$S"
            continue
        fi
        if [ -n "$cs" ] && { [ -z "$base" ] || [ "$cs" != "$base" ]; } && { [ -z "$base" ] || [ "$ls" = "$base" ] || [ -z "$ls" ]; }; then
            # down: the cloud's is new (or this computer is new to it) and yours hasn't changed
            wow_running && continue
            settled "$C" || continue
            [ -f "$L" ] && cp -p "$L" "$L.before-sync"
            put "$C" "$L" || { log "Cloud sync: couldn't write $L"; continue; }
            echo "$(sum_of "$L")" > "$S"
            log "Cloud sync: $name – got the settings from the cloud"
            # the file changed, but nothing happened here: no "logged out" alert from another computer's logout
            SV_MTIME="$(stat -f %m "$(sv_file)" 2>/dev/null)"
            at="$(sv_num "$L" exitAt)"; [ -n "$at" ] && LAST_EXIT="$at"
        elif [ -n "$ls" ]; then
            # up: yours changed (a logout, a reload) – or the cloud has none yet
            settled "$L" || continue
            if [ -n "$cs" ] && [ -n "$base" ] && [ "$cs" != "$base" ]; then
                cp -p "$C" "$C.conflict" && log "Cloud sync: $name – both changed; yours kept, the cloud's saved as WatchX.lua.conflict"
            fi
            put "$L" "$C" || { log "Cloud sync: couldn't write $C"; continue; }
            echo "$ls" > "$S"
            log "Cloud sync: $name – sent your settings to the cloud"
        fi
    done
}

# ---------------------------------------------------------------- slow fallback: chat log

watch_chatlog() {
    # Only WatchX's own lines: "<key> [WatchX]#..." with this install's key (in any game language). Other players
    # can type "[WatchX]#..." in Trade, but they don't know the key. Before the game has saved a key (it does at
    # the next reload or logout) – and for the old tag without one – only a line that starts like your own
    # "You are now Busy:" message (or a whisper you sent) counts.
    local RE_KEY='(^|[^A-Za-z0-9])([A-Za-z0-9]+) \[WatchX\]#([0-9]+) ([A-Z]+) (.*)$'
    local RE_MINE='^[0-9/]+ [0-9:.]+  (You are now Busy: |To [^:]+: )([A-Za-z0-9]+ )?\[WatchX\]#'
    local RE_OLD='^[0-9/]+ [0-9:.]+  You are now Busy: \[WatchX\]#([0-9]+) ([A-Z]+) (.*)$'
    local line id kind rest subject text now key keys
    while IFS= read -r line; do
        line="${line%$'\r'}"
        case "$line" in *"[WatchX"*) ;; *) continue ;; esac
        if [[ "$line" =~ $RE_KEY ]]; then
            key="${BASH_REMATCH[2]}" id="${BASH_REMATCH[3]}" kind="${BASH_REMATCH[4]}" rest="${BASH_REMATCH[5]}"
            keys=" $(known_keys) "
            if [ "$keys" = "  " ]; then
                [[ "$line" =~ $RE_MINE ]] || continue
            else
                case "$keys" in *" $key "*) ;; *) continue ;; esac
            fi
        elif [[ "$line" =~ $RE_OLD ]]; then
            id="${BASH_REMATCH[1]}" kind="${BASH_REMATCH[2]}" rest="${BASH_REMATCH[3]}"
            [ -z "$(known_keys)" ] || continue   # a key is saved: this WatchX always uses it, the old tag isn't from it
        else
            continue
        fi
        # the id is the time + 3 digits: an old line (or a strange id) is skipped
        { [ ${#id} -ge 4 ] && [ ${#id} -le 16 ]; } || continue
        now="$(date +%s)"
        [ $((now - 10#${id:0:${#id}-3})) -gt 1800 ] && continue   # (WoW writes this file late: up to 30 min is kept)
        already_sent "$id" && continue   # sent instantly already (or a whisper logged twice)
        mark_sent "$id"
        subject="${rest%%::*}" text="${rest#*::}$(late_note "$id")"
        log "$kind (chat log): $text"
        notify "$kind" "$subject" "$text"
    done < <(exec tail -n 0 -F "$CHATLOG" 2>/dev/null)
}

# (the tests load the functions above without starting the bridge)
if [ -n "${WATCHX_LIB:-}" ]; then return 0 2>/dev/null || exit 0; fi

# ---------------------------------------------------------------- main

log "WatchX bridge 2.0 – Made by Rikerud"
load_settings
# What it does (chosen in "Install (Mac).command"): alerts, sync or both (no choice saved: as before, alerts)
MODE="$(head -n 1 "$DIR/mode.txt" 2>/dev/null)"
case "$MODE" in sync|both) ;; *) MODE=alerts ;; esac
[ "$MODE" = alerts ] && rm -f "$CLOUD_CFG"   # (chose alerts only: no sync)
[ "$MODE" = sync ] || log "Targets: $(targets)${SV:+  (from ${SV#$ROOT/})}"

if [ "$1" = "--test" ]; then   # bash watchx_bridge.sh --test [image]
    notify TEST WatchX "Test from the bridge – alerts are working." "$2"
    exit 0
fi
if [ "$1" = "--decode" ]; then   # bash watchx_bridge.sh --decode <image>
    osascript -l JavaScript "$DECODE" "$2"
    exit 0
fi

# Only one bridge at a time.
OLDPID="$(cat "$PIDFILE" 2>/dev/null)"
if [ -n "$OLDPID" ] && [ "$OLDPID" != "$$" ] && ps -p "$OLDPID" -o command= 2>/dev/null | grep -q "watchx_bridge.sh"; then
    log "Bridge is already running (pid $OLDPID) – exiting."
    exit 0
fi
echo $$ > "$PIDFILE"
cleanup() { trap - EXIT; rm -f "$PIDFILE"; pkill -P $$ 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' TERM INT

touch "$WORK/stamp"   # only screenshots from now on
: > "$SENT_FILE"
SV_MTIME="$(stat -f %m "$(sv_file)" 2>/dev/null)"
wow_running && WOW_UP=1 && WOW_SINCE="$(date +%s)"
if [ "$MODE" = sync ]; then
    log "Cloud sync only (no phone alerts)"
else
    log "Watching $SHOTS (instant), the game (logout) and $CHATLOG (fallback)"
    watch_chatlog &
fi

# Quick while the game runs (alerts within a second); slower when it doesn't (next to no CPU all day).
while true; do
    if [ "$MODE" != sync ]; then
        check_shots
        check_exit
    fi
    [ "$MODE" != alerts ] && cloud_sync
    if [ "$WOW_UP" = 1 ] && [ "$MODE" != sync ]; then sleep 0.3; else sleep 2; fi
done
