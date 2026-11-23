-- WatchX – Made by Rikerud
-- Passive alerts when selected rare mobs spawn (Prince Nazjak built in, custom mobs can be added).
--
-- Detection (fully passive, no macro/targeting):
--   * Nameplates: scans all visible nameplates every second + NAME_PLATE_UNIT_ADDED.
--     Requires enemy nameplates to be enabled and you to be within nameplate range.
--   * Mouseover / target.
--   * Deaths: UNIT_DIED / PARTY_KILL (GUIDs remembered from the nameplate), the "%s dies." /
--     "You have slain %s!" chat lines, and corpses seen on nameplates.
--   Not the combat log: WoW Forever closes COMBAT_LOG_EVENT_* to addons (registering it is
--   blocked – that was the "blocked from an action" popup). Secret values are skipped.
--
-- Phone alerts: WoW addons cannot make HTTP requests. The addon takes a screenshot with a small code
-- block in the corner (see "instant alerts"); the bridge (bridge/ in the source, WatchX-Bridge.zip on
-- GitHub; set up once with its "Install" file, which copies it out of the game folder) sees the new file, reads the code and sends the alert to ntfy and Discord at once.
-- Fallback when screenshots don't work: a tagged line in the chat log (/chatlog), which WoW writes in
-- big chunks (slow): [WatchX]#<id> <TYPE> <subject>::<text>
-- AFK: a warning 5 min before the AFK logout; the logout itself is seen by the bridge (exitWhy).
--
-- This file: data, detection, alerts, chat log state, session log, slash commands.
-- UI.lua: panel, mini bar, settings page, guide, minimap button.

local ADDON, ns = ...

ns.AUTHOR = "Rikerud"
ns.BRIDGE_URL = "github.com/nintox/WatchX/releases"   -- WatchX-Bridge.zip (the phone bridge isn't in the CurseForge download)
ns.MAX_CUSTOM = 9

-- Built-in presets. Add more here: name must match the in-game name exactly.
ns.PRESETS = {
    { name = "Prince Nazjak", note = "Tidal Charm", loot = { [1404] = "Tidal Charm" },
      -- where to stand (Arathi Highlands): 24 known spawn points, 41 yd nameplates – no single spot
      -- sees them all; these two see the most (from Questie's spawn data)
      zone = "Arathi Highlands", mapID = 1417,
      spots = {
          { x = 21.9, y = 84.4, text = "Spot 1 – north group: sees 8 of 24 spawn points" },
          { x = 22.3, y = 89.2, text = "Spot 2 – south group: sees 6 more (14 of 24 with both)" },
      },
      spawns = { { 19.8, 88.8 }, { 20.2, 82.4 }, { 20.6, 83.4 }, { 20.8, 84 }, { 21.2, 84.6 }, { 21.2, 89.2 },
          { 21.2, 89.6 }, { 21.6, 82.8 }, { 21.6, 86 }, { 21.6, 89 }, { 21.8, 83.6 }, { 21.8, 84.8 },
          { 22.4, 89.6 }, { 22.8, 84.4 }, { 23, 84.8 }, { 23, 86.2 }, { 23, 88 }, { 23.2, 82.2 },
          { 23.2, 83.2 }, { 23.4, 89 }, { 23.6, 83.8 }, { 23.6, 89.4 }, { 23.6, 89.8 }, { 24, 88.4 } } },
}

local TAG = "[WatchX]"
local REALERT_AFTER = 180   -- seconds without seeing the mob before a new sighting counts as a new spawn
local DEATH_GRACE = 30      -- seconds after a death during which new sightings are ignored
local ENEMY_COOLDOWN = 600  -- seconds before the same enemy player is announced again
local LOG_MAX = 80

local defaults = {
    whisper = true,       -- send tagged whisper to yourself (for the bridge)
    sound = true,
    enemyPlayers = false, -- alert on any hostile player (PvP), outside instances
    friendlyPlayers = false, -- alert on any friendly player, outside instances, cities/inns and your group
    attackAlert = true,   -- alert when something attacks you while you're idle or AFK
    nearby = false,       -- the Nearby list of enemy players + stealth warnings (in game only, like Spy)
    stealthWarn = true,   -- Nearby: the "Stealthed player detected!" card
    stealthSound = true,  -- Nearby: a sound with it
    newEnemyCard = false, -- Nearby: an "Enemy player detected!" card for every new enemy (stealth/KOS always)
    warnDock = false,     -- Nearby: the cards sit on top of the list (off: top of the screen, movable)
    nearbyAttach = true,  -- Nearby: the list hangs under the mini bar, same width
    nearbyMax = 10,       -- Nearby: how many players the list shows
    nearbyNoBG = true,    -- Nearby: off in battlegrounds and arenas
    nearbyHideDungeon = false, -- Nearby: hidden in dungeons (else faded)
    nearbyHideRaid = false,    -- Nearby: hidden in raids (else faded)
    kosAlert = true,      -- Nearby: a "Kill on sight!" card + sound when a KOS player shows up
    enemies = {},         -- Nearby history: key -> { name, class, level, guild, firstSeen, lastSeen, zone, seen, kills, deaths, kos, avoid, note }
    kosGuilds = {},       -- lower-case guild name -> guild name, KOS
    avoidGroup = true,    -- ... a warning when one of them invites you or is in your group
    avoidChat = true,     -- ... a red [Avoid] before their chat lines
    wantedOn = true,      -- WANTED: bounties shared with your guild and friends
    wantedGuild = true,   -- ... sent to and taken from the guild
    wantedFriends = true, -- ... and your online friends
    wantedAlert = true,   -- ... a card + sound when a wanted player shows up
    nearbyShowEmpty = false, -- Nearby: show the list even when no enemy is around
    nearbyKeep = 5,       -- Nearby: minutes a player stays in the list after he was last seen
    plateIcons = false,   -- a class icon over enemy players' nameplates
    plateFriendly = false, -- ... and over friendly players'
    plateSize = 22,       -- the nameplate icon's size (12 - 40)
    plateHealer = true,
    plateKOS = true,
    levelHelper = true,   -- the XP boosts list (until max level)
    levelMissing = false, -- ... only what's missing
    levelFlash = true,    -- ... the missing lines pulse
    levelWarn = true,     -- ... a warning when a boost runs out
    levelHideCombat = true,
    levelHideInstance = false,
    buffWarn = true,      -- buff warnings: before / when a watched buff runs out
    buffSoon = 60,        -- ... seconds before (0: only when it's gone)
    buffGone = true,      -- ... when it has run out
    buffGroups = { breath = true, consumables = true, own = false, others = false },
    buffCustom = {},      -- ... your own list: buff names or spell IDs (shared by all profiles)      -- ... with a red ring and a skull on KOS players   -- ... with a green + on proven healers (talents, group role, healing-talent spells)
    notifyDeath = true,   -- send death alerts to phone
    show = true,          -- mini bar shown
    locked = false,       -- mini bar locked
    miniQuiet = false,    -- mini bar only shows when something is up (the alert spot stays)
    hideIdle = false,     -- mini bar hidden while nothing is watched
    scanOn = true,        -- rare scan (like unitscan): the watch list is live (off: nothing on it is looked for)
    mapSpots = true,      -- the best places to stand, as pins on the world map and minimap
    alertSame = true,     -- the big alert pops up in the mini bar's spot (false: alertPoint)
    minimap = { hide = false },
    watch = { ["Prince Nazjak"] = true },  -- name -> watched (on/off)
    custom = {},                           -- custom mob names, in order
    mobs = {},                             -- name -> state (see MobState)
    log = {},                              -- this session's log (/wx log)
    -- Read by the bridge from SavedVariables:
    ntfyUrl = "",
    ntfyToken = "",
    discordWebhook = "",
    discordMention = "@here",
    instant = true,       -- instant alerts by screenshot (falls back to the chat log if that doesn't work)
    afkWarn = true,       -- alert 5 min before the AFK logout, and when you get logged out
    afkLogoutMin = 25,    -- minutes from the AFK flag to the logout (learned when it happens)
    -- Runtime, read by the bridge: exitAt (time()), exitWhy ("reload", "logout", "quit", "afk", "disconnect")
}

local db
local counter = 0
local lastLootAlert = 0
local watchByLower = {}   -- lower(name) -> name, enabled only
local activeLoot = {}     -- itemID -> { item = name, mob = name }
local ev = CreateFrame("Frame")

-- ---------------------------------------------------------------- helpers

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4d85b3WatchX|r: " .. msg)
end
ns.Print = Print

local function Fmt(sec)
    sec = math.max(0, math.floor(sec))
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end
ns.Fmt = Fmt

local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end
ns.Trim = Trim

-- Forever can hand over secret values (unit names, GUIDs, health); those are skipped.
local function Plain(v)
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return nil end
    end
    return v
end

-- An enemy player: one you can attack, or of the other faction even when they aren't PvP flagged (then the
-- game doesn't call them hostile, but they're still Horde to your Alliance).
function ns.IsHostilePlayer(unit)
    if Plain(UnitIsEnemy("player", unit)) == true or Plain(UnitCanAttack("player", unit)) == true then return true end
    if Plain(UnitIsPlayer(unit)) ~= true or not UnitFactionGroup then return false end
    local mine, theirs = Plain((UnitFactionGroup("player"))), Plain((UnitFactionGroup(unit)))
    return type(mine) == "string" and type(theirs) == "string" and mine ~= "Neutral" and theirs ~= "Neutral"
        and mine ~= theirs
end

-- A Lua pattern from one of the game's format strings ("%s dies." -> "^(.+) dies%.$").
local function MakePattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
    p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%s", "(.+)"):gsub("%%%%%d%%%$d", "(%%d+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end
ns.MakePattern = MakePattern

-- Session log (as in LayerSwap): kept in SavedVariables so a problem can be read afterwards.
local function Log(...)
    if not db then return end
    local parts = { date("%H:%M:%S") }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(db.log, table.concat(parts, " "))
    while #db.log > LOG_MAX do table.remove(db.log, 1) end
end
ns.Log = Log

-- Runs fn; an error is logged and said once in chat instead of breaking WatchX for the session.
local reportedErrors = {}
-- WatchX's own CPU time: every handler is timed once at its outermost call (debugprofilestop: microsecond clock,
-- costs next to nothing). /wx mem shows it.
-- Also the longest single call (a lag spike shows there, not in the average), calls over 5 ms, and the memory
-- WatchX's own code allocates (garbage the game has to clear later).
ns.cpu = { ms = 0, by = {}, depth = 0, clock = debugprofilestop, max = 0, spikes = 0, kb = 0 }   -- one table: locals limit
function ns.cpu.Spent(label, dt, kb)
    local C = ns.cpu
    C.ms = C.ms + dt
    C.by[label] = (C.by[label] or 0) + dt
    if dt > C.max then C.max, C.maxLabel = dt, label end
    if dt > 5 then C.spikes = C.spikes + 1 end
    if kb and kb > 0 then C.kb = C.kb + kb end
end
function ns.Timed(fn, label)
    label = label or "other"
    return function(...)
        local C = ns.cpu
        if not C.clock or C.depth > 0 then return fn(...) end
        C.depth = 1
        local t0, m0 = C.clock(), collectgarbage("count")
        local ok, a, b, c = pcall(fn, ...)
        C.Spent(label, C.clock() - t0, collectgarbage("count") - m0)
        C.depth = 0
        if not ok then error(a, 0) end
        return a, b, c
    end
end

function ns.Safe(label, fn, ...)
    local C = ns.cpu
    local top = C.clock and C.depth == 0
    local t0, m0
    if top then C.depth = 1; t0, m0 = C.clock(), collectgarbage("count") end
    local ok, err = pcall(fn, ...)
    if top then C.Spent(label or "other", C.clock() - t0, collectgarbage("count") - m0); C.depth = 0 end
    if not ok then
        err = tostring(err)
        if Log then Log("error", label, err) end
        if not reportedErrors[err] then
            reportedErrors[err] = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff4d85b3WatchX|r: |cffff4040error (" .. label .. "):|r " .. err
                .. " |cffaaaaaa– please send a screenshot of this to " .. tostring(ns.AUTHOR) .. ".|r")
        end
    end
    return ok
end

local function Refresh()
    if ns.RefreshUI then ns.RefreshUI() end
end

local function MobState(name)
    local m = db.mobs[name]
    if not m then
        m = { alive = false, samples = {}, kills = {} }
        db.mobs[name] = m
    end
    return m
end
ns.MobState = MobState

local function PresetFor(name)
    for _, p in ipairs(ns.PRESETS) do
        if p.name:lower() == name:lower() then return p end
    end
end

-- All mobs: presets first, then custom ones.
function ns.GetMobList()
    local list = {}
    for _, p in ipairs(ns.PRESETS) do
        list[#list + 1] = { name = p.name, preset = true, note = p.note, enabled = db.watch[p.name] and true or false }
    end
    for _, name in ipairs(db.custom) do
        list[#list + 1] = { name = name, preset = false, enabled = db.watch[name] and true or false }
    end
    return list
end

function ns.RebuildWatch()
    wipe(watchByLower)
    wipe(activeLoot)
    for _, mob in ipairs(ns.GetMobList()) do
        if mob.enabled and db.scanOn ~= false then
            watchByLower[mob.name:lower()] = mob.name
            local p = PresetFor(mob.name)
            if p and p.loot then
                for id, item in pairs(p.loot) do activeLoot[id] = { item = item, mob = p.name } end
            end
        end
    end
end

local function Resolve(name)
    return name and watchByLower[name:lower()]
end

local function FindAny(name)
    name = Trim(name):lower()
    for _, mob in ipairs(ns.GetMobList()) do
        if mob.name:lower() == name then return mob.name end
    end
end
ns.FindAny = FindAny

-- The rare scan as a whole on or off (the list and each name's own switch stay as they are).
function ns.SetScan(on)
    db.scanOn = on and true or false
    ns.RebuildWatch()
    if ns.UpdateMapPins then ns.Safe("map pins", ns.UpdateMapPins) end
    Refresh()
end

-- on: true; off: nil (off the list for the built-in rares) or false with keep (switched off, still listed).
function ns.SetWatched(name, on, keep)
    if on then db.watch[name] = true elseif keep then db.watch[name] = false else db.watch[name] = nil end
    ns.RebuildWatch()
    if ns.UpdateMapPins then ns.Safe("map pins", ns.UpdateMapPins) end
    Refresh()
end

function ns.AddCustom(name)
    name = Trim(name)
    if name == "" then return false, "Enter a name." end
    if FindAny(name) then return false, "'" .. name .. "' is already in the list." end
    if #db.custom >= ns.MAX_CUSTOM then return false, "Max " .. ns.MAX_CUSTOM .. " custom mobs." end
    table.insert(db.custom, name)
    ns.SetWatched(name, true)
    Print("Added '" .. name .. "'.")
    return true
end

function ns.RemoveCustom(name)
    for i, n in ipairs(db.custom) do
        if n == name then
            table.remove(db.custom, i)
            db.watch[name] = nil
            ns.RebuildWatch()
            Print("Removed '" .. name .. "'.")
            Refresh()
            return true
        end
    end
end

local function EstimatedRespawn(name)
    local m = MobState(name)
    if m.manualRespawn then return m.manualRespawn, "manual" end
    local best
    for _, v in ipairs(m.samples) do
        if not best or v < best then best = v end
    end
    if best then return best, string.format("fastest of %d seen", #m.samples) end
end
ns.EstimatedRespawn = EstimatedRespawn

function ns.SetManualRespawn(name, minutes)
    local n = tonumber(minutes)
    MobState(name).manualRespawn = (n and n > 0) and math.floor(n * 60) or nil
    Refresh()
end

-- Status of one mob: state ("up"/"dead"/"unknown"), short colored text, detail text,
-- and seconds until the estimated respawn (nil if unknown).
-- A name on the watch list that turned out to be a player (shown as FOUND instead of UP).
function ns.IsPlayerEntry(name) return MobState(name).isPlayer == true end

function ns.GetMobStatus(name)
    local m, now = MobState(name), time()
    if m.alive and m.lastSeen and now - m.lastSeen < REALERT_AFTER then
        return "up", "|cff40ff40UP|r", "seen " .. Fmt(now - m.lastSeen) .. " ago"
    elseif m.lastDeath then
        local since = now - m.lastDeath
        local est = EstimatedRespawn(name)
        if est then
            local left = est - since
            if left > 0 then
                return "dead", "|cffff6060dead|r " .. Fmt(since), "respawn ~" .. Fmt(left), left
            end
            return "dead", "|cffffd100due|r", "can spawn any moment", 0
        end
        return "dead", "|cffff6060dead|r " .. Fmt(since), "learning respawn"
    end
    return "unknown", "|cff808080not seen|r", ""
end

-- ---------------------------------------------------------------- chat log
-- LoggingChat() is protected in this client (even just reading it), so the addon never calls it.
-- The chat log is toggled with /chatlog – typed by the player or via the secure bar in UI.lua –
-- and the state is tracked from the message /chatlog prints.

function ns.HasTargets()
    return db and db.whisper and (db.ntfyUrl ~= "" or db.discordWebhook ~= "")
end

function ns.ChatLogText()
    if db.chatlogOn == true then return "|cff40ff40on|r" end
    if db.chatlogOn == false then return "|cffff6060OFF|r" end
    return "|cffffd100unknown|r"
end

local chatLogJustSet = false
local function SetChatLogState(on)
    chatLogJustSet = true
    db.chatlogOn = on
    Log("chatlog", on and "on" or "off")
    if on then Print("Chat log is |cff40ff40on|r – phone alerts can be delivered.") end
    if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
    Refresh()
end

local function HookChatLog()
    local function onMessage(_, msg)
        if type(msg) ~= "string" then return end
        if CHATLOGENABLED and msg:find(CHATLOGENABLED, 1, true) then SetChatLogState(true)
        elseif CHATLOGDISABLED and msg:find(CHATLOGDISABLED, 1, true) then SetChatLogState(false) end
    end
    hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", onMessage)
    if ChatFrame1 and ChatFrame1 ~= DEFAULT_CHAT_FRAME then hooksecurefunc(ChatFrame1, "AddMessage", onMessage) end
    -- Fallback if the message wasn't seen: flip the known state.
    if SlashCmdList and SlashCmdList.CHATLOG then
        hooksecurefunc(SlashCmdList, "CHATLOG", function()
            if not chatLogJustSet then SetChatLogState(db.chatlogOn ~= true) end
            chatLogJustSet = false
        end)
    end
end

-- ---------------------------------------------------------------- sending
-- The alert goes into WoW's chat log through a line only you see. Forever doesn't let you whisper
-- yourself ("No player named 'X' is currently playing"), so there are three ways, tried in order.
-- One that fails is remembered (db.methodFailed) and the next one is used – the alert is resent:
--   whisper  – a whisper to yourself
--   realm    – a whisper to Name-Realm
--   dnd      – your Busy message: "You are now Busy: <alert>" is logged; Busy is cleared again
-- If the game holds back a send (ADDON_ACTION_BLOCKED/FORBIDDEN during it, as LayerSwap measured
-- for its own sends), the alert is kept and the UI asks for one click to send it.

local METHODS = { "whisper", "realm", "dnd" }
ns.METHODS = METHODS
local sendingChat, heldBack = false, false
local pendingMsg
local lastSend          -- { msg, method, target, at }: to spot "No player named" right after a whisper

function ns.HasPending() return pendingMsg ~= nil end

local function MyRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if (not r or r == "") and GetRealmName then r = (GetRealmName() or ""):gsub("[%s%-']", "") end
    return (r and r ~= "") and r or nil
end

local function CurrentMethod()
    if db.sendMethod and db.sendMethod ~= "auto" then return db.sendMethod end
    db.methodFailed = db.methodFailed or {}
    for _, m in ipairs(METHODS) do
        if not db.methodFailed[m] then return m end
    end
    return "dnd"
end
ns.CurrentMethod = CurrentMethod

-- One chat send. Returns ok, held back, result.
local function SendChat(msg, chatType, target)
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return false, false, "chat lockdown" end
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    sendingChat, heldBack = true, false
    local ok, result = pcall(send, msg, chatType, nil, target)
    sendingChat = false
    if heldBack then return false, true end
    local enum = Enum and Enum.SendChatMessageResult
    return ok and (result == nil or result == true or result == 0 or (enum and result == enum.Success)) or false,
        false, ok and result or "error"
end

local function IsBusy()
    return UnitIsDND and Plain(UnitIsDND("player")) == true
end

local SendAlertLine
SendAlertLine = function(msg)
    local me = UnitName("player")
    if not me then return false end
    local method = CurrentMethod()
    local target, ok, held, res, mine
    if method == "dnd" then
        if IsBusy() then SendChat("", "DND") end            -- already Busy: a new message would toggle it off
        ok, held, res = SendChat(msg, "DND")
        if ok then
            C_Timer.After(1.5, function() if IsBusy() then SendChat("", "DND") end end)
        end
    else
        target = me
        if method == "realm" then
            local realm = MyRealm()
            if realm then target = me .. "-" .. realm end
        end
        -- set before the send: "No player named" may come back while it is still running
        mine = { msg = msg, method = method, target = target, at = GetTime() }
        lastSend = mine
        ok, held, res = SendChat(msg, "WHISPER", target)
    end
    if mine and mine.failed then return true end           -- the next way took over and sent it
    if held then
        Log("send", method, "held back by the game")
        pendingMsg = msg
        Print("|cffffd100The game held back the phone alert. Click the red bar to send it.|r")
        if ns.ShowSendBar then ns.ShowSendBar(true) end
        return false
    end
    if ok then
        Log("send", method, "ok")
        return true
    end
    if lastSend == mine then lastSend = nil end
    Log("send", method, "failed", tostring(res))
    Print("|cffffd100The phone alert could not be sent (" .. tostring(res) .. ").|r")
    return false
end

-- A system message right after a send: "No player named ..." means that way doesn't work here.
local notFoundPattern
local function OnSystemMessage(text)
    text = Plain(text)
    if type(text) ~= "string" or not lastSend or not lastSend.target then return end
    if GetTime() - lastSend.at > 5 then return end
    notFoundPattern = notFoundPattern or MakePattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.")
    local who = notFoundPattern and text:match(notFoundPattern)
    if not who then return end
    local me = (UnitName("player") or ""):lower()
    if who:lower() ~= lastSend.target:lower() and not who:lower():find(me, 1, true) then return end
    local failed, msg = lastSend.method, lastSend.msg
    lastSend.failed = true
    lastSend = nil
    db.methodFailed = db.methodFailed or {}
    db.methodFailed[failed] = true
    Log("method", failed, "does not work here")
    if db.sendMethod and db.sendMethod ~= "auto" then
        Print("|cffffd100Sending by '" .. failed .. "' doesn't work here – use /wx method auto.|r")
        return
    end
    Print("|cffaaaaaaThat way of reaching the chat log doesn't work here – trying the next one (" .. CurrentMethod() .. ").|r")
    SendAlertLine(msg)
end

function ns.SendPending()
    local msg = pendingMsg
    pendingMsg = nil
    if ns.ShowSendBar then ns.ShowSendBar(false) end
    if msg and SendAlertLine(msg) then Print("Phone alert sent.") end
end

-- The slow way (fallback): a tagged line in the chat log. WoW writes that file in big chunks, so it
-- can take minutes to reach the phone – only used when screenshots don't work.
local function Signal(kind, subject, text, epoch, ctr)
    local msg = string.format("%s#%d%03d %s %s::%s", TAG, epoch, ctr, kind, subject, text or "")
    if SendAlertLine(msg:sub(1, 240)) and ns.HasTargets() and db.chatlogOn ~= true then
        Print("|cffffd100The chat log may be off – click the yellow bar (or type /chatlog), "
            .. "otherwise alerts can't reach your phone.|r")
    end
end

-- ---------------------------------------------------------------- instant alerts (screenshot)
-- WoW saves a screenshot to disk at once, and the bridge watches the Screenshots folder. While the
-- picture is taken, a small black-and-white code block is shown in the top-left corner: it carries the
-- alert (kind, name, text), so the bridge knows what to send – and ignores your own screenshots.
-- Layout (in cells): black margin, white border, then the data bits row by row, MSB first.
-- Data: "W" "X" <length> <payload> <fletcher-16 a> <b>;
-- payload: <kind letter> <epoch: 4 bytes> <counter> <subject> 0x1F <text>.
local SHOT_CELL, SHOT_COLS = 7, 48          -- cell size in screen units (the screen is 768 high), data columns
local SHOT_KINDS = { SPAWN = "S", LOOT = "L", ENEMY = "E", PLAYER = "P", FRIEND = "F", DEATH = "D", TEST = "T",
                     AFK = "A", LOGOUT = "O", ATTACK = "H" }
ns.SHOT_CELL, ns.SHOT_COLS = SHOT_CELL, SHOT_COLS

local function CutUtf8(s, n)
    if #s <= n then return s end
    s = s:sub(1, n)
    return (s:gsub("[\192-\255][\128-\191]*$", ""))   -- don't leave half a letter at the end
end

function ns.ShotBits(kind, epoch, ctr, subject, text)
    local payload = { (SHOT_KINDS[kind] or "T"):byte() }
    for i = 3, 0, -1 do payload[#payload + 1] = math.floor(epoch / 256 ^ i) % 256 end
    payload[#payload + 1] = ctr % 256
    for c in CutUtf8(subject or "", 32):gmatch(".") do payload[#payload + 1] = c:byte() end
    payload[#payload + 1] = 31
    for c in CutUtf8(text or "", 64):gmatch(".") do payload[#payload + 1] = c:byte() end
    local bytes = { 87, 88, #payload }
    local a, b = #payload % 255, #payload % 255
    for _, v in ipairs(payload) do
        bytes[#bytes + 1] = v
        a = (a + v) % 255
        b = (b + a) % 255
    end
    bytes[#bytes + 1] = a
    bytes[#bytes + 1] = b
    local bits = {}
    for _, v in ipairs(bytes) do
        for i = 7, 0, -1 do bits[#bits + 1] = math.floor(v / 2 ^ i) % 2 end
    end
    return bits
end

local marker, markerCells
local function ShowMarker(bits)
    if not marker then
        -- no parent: shown even with the interface hidden (Alt-Z), always in screen units (768 high)
        marker = CreateFrame("Frame", "WatchXMarker", nil)
        marker:SetFrameStrata("TOOLTIP")
        marker:SetFrameLevel(9000)
        if WorldFrame then marker:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0) else marker:SetPoint("TOPLEFT", 0, 0) end
        marker.black = marker:CreateTexture(nil, "BACKGROUND")
        marker.black:SetAllPoints()
        marker.black:SetColorTexture(0, 0, 0, 1)
        marker.white = marker:CreateTexture(nil, "BORDER")
        marker.white:SetColorTexture(1, 1, 1, 1)
        marker.white:SetPoint("TOPLEFT", SHOT_CELL, -SHOT_CELL)
        marker.inner = marker:CreateTexture(nil, "ARTWORK")
        marker.inner:SetColorTexture(0, 0, 0, 1)
        marker.inner:SetPoint("TOPLEFT", SHOT_CELL * 2, -SHOT_CELL * 2)
        markerCells = {}
    end
    local rows = math.ceil(#bits / SHOT_COLS)
    marker:SetSize((SHOT_COLS + 4) * SHOT_CELL, (rows + 4) * SHOT_CELL)
    marker.white:SetSize((SHOT_COLS + 2) * SHOT_CELL, (rows + 2) * SHOT_CELL)
    marker.inner:SetSize(SHOT_COLS * SHOT_CELL, rows * SHOT_CELL)
    for i = 1, math.max(#bits, #markerCells) do
        local t = markerCells[i]
        if bits[i] == 1 then
            if not t then
                t = marker:CreateTexture(nil, "OVERLAY")
                t:SetColorTexture(1, 1, 1, 1)
                t:SetSize(SHOT_CELL, SHOT_CELL)
                local c, r = (i - 1) % SHOT_COLS, math.floor((i - 1) / SHOT_COLS)
                t:SetPoint("TOPLEFT", (c + 2) * SHOT_CELL, -(r + 2) * SHOT_CELL)
                markerCells[i] = t
            end
            t:Show()
        elseif t then
            t:Hide()
        end
    end
    marker:Show()
end

local function HideMarker() if marker then marker:Hide() end end

local shotQueue, shotBusy, shotWait = {}, false, nil
local takingShot, shotBlocked = false, false
ns.shotEvents = false   -- SCREENSHOT_SUCCEEDED/FAILED registered (set below)

local NextShot
local function ShotDone(item, ok, why)
    HideMarker()
    shotWait, shotBusy = nil, false
    if ok then
        if db.instantOK ~= true then Log("instant", "screenshot works") end
        db.instantOK = true
    else
        Log("instant", "screenshot failed", why or "?")
        db.instantOK = false
        Print("|cffffd100Instant alert failed (" .. (why or "?") .. ") – sending it the slow way (chat log).|r")
        if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
        Signal(item.kind, item.subject, item.text, item.epoch, item.ctr)
    end
    C_Timer.After(0.3, NextShot)
end

NextShot = function()
    if shotBusy or #shotQueue == 0 then return end
    local item = table.remove(shotQueue, 1)
    shotBusy = true
    ShowMarker(ns.ShotBits(item.kind, item.epoch, item.ctr, item.subject, item.text))
    C_Timer.After(0.25, function()   -- let the code block (and the raid warning) be drawn first
        takingShot, shotBlocked = true, false
        local ok, err = pcall(Screenshot)
        takingShot = false
        if not ok or shotBlocked then
            ShotDone(item, false, shotBlocked and "blocked by the game" or tostring(err))
            return
        end
        shotWait = item
        C_Timer.After(ns.shotEvents and 5 or 1.5, function()
            if shotWait == item then ShotDone(item, not ns.shotEvents, "no picture saved") end
        end)
    end)
end

function ns.OnScreenshot(success)
    if shotWait then ShotDone(shotWait, success, "the game couldn't save it") end
end

-- The phone part of an alert: the instant way when it works, the chat log otherwise.
local function Phone(kind, subject, text)
    if not db.whisper then return end
    if kind == "DEATH" and not db.notifyDeath then return end
    counter = (counter + 1) % 256
    local epoch = time()
    if db.instant ~= false and db.instantOK ~= false and Screenshot then
        shotQueue[#shotQueue + 1] = { kind = kind, subject = subject, text = text, epoch = epoch, ctr = counter }
        NextShot()
    else
        Signal(kind, subject, text, epoch, counter)
    end
end
ns.Phone = Phone

-- msg: shown in game; phoneText (optional): the shorter text for the phone (it carries the name in its title).
local function Alert(kind, subject, msg, phoneText)
    Print("|cffff4040" .. msg .. "|r")
    Log("alert", kind, subject)
    if db.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    if FlashClientIcon then FlashClientIcon() end
    Phone(kind, subject, phoneText or msg)
end
ns.Alert = Alert

-- Delayed so the test travels exactly like a real spawn alert (not straight from a click).
function ns.SendTest()
    Print("Sending a test alert in 3 seconds (the same way a real spawn alert is sent)...")
    C_Timer.After(3, function()
        Alert("TEST", "WatchX", "Test from WatchX – if you see this on your phone, everything works.",
            "Test – if you see this on your phone, it works!")
    end)
end

local function Location()
    local sub, zone = GetSubZoneText(), GetZoneText()
    if sub and sub ~= "" then return sub .. ", " .. (zone or "") end
    return zone or "?"
end

-- ---------------------------------------------------------------- state

local function OnDeath(name, source)
    local m, now = MobState(name), time()
    if not m.alive and m.lastDeath and now - m.lastDeath < 120 then return end
    m.alive = false
    m.lastDeath = now
    table.insert(m.kills, now)
    Log("death", name, source)

    local msg = name .. " died (" .. (source or "?") .. ")."
    local est = EstimatedRespawn(name)
    if est then
        msg = msg .. string.format(" Earliest respawn around %s (in %s).", date("%H:%M", now + est), Fmt(est))
    end
    Print(msg)
    Phone("DEATH", name, msg)
    Refresh()
end
ns.OnDeath = OnDeath

-- "60 Rogue, <Guild>, PvP" for a player unit (secret parts are left out).
local function PlayerInfo(unit)
    local parts = {}
    local level = Plain(UnitLevel(unit))
    local class = Plain((UnitClass(unit)))
    if type(level) == "number" or type(class) == "string" then
        parts[#parts + 1] = ((type(level) == "number" and level > 0) and level or "??") .. (class and (" " .. class) or "")
    end
    local guild = Plain((GetGuildInfo(unit)))
    if type(guild) == "string" and guild ~= "" then parts[#parts + 1] = "<" .. guild .. ">" end
    if Plain(UnitIsPVP(unit)) == true then parts[#parts + 1] = "PvP" end
    return table.concat(parts, ", ")
end

local function OnSeen(name, unit, source)
    local m, now = MobState(name), time()
    if unit and Plain(UnitIsDead(unit)) == true then
        OnDeath(name, "corpse seen")
        return
    end
    if m.lastDeath and now - m.lastDeath < DEATH_GRACE then return end

    local stillSameSpawn = m.alive and m.lastSeen and (now - m.lastSeen) < REALERT_AFTER
    m.lastSeen = now
    if stillSameSpawn then return end

    m.alive = true
    -- a player on your watch list: "found" (enemy or friend), no respawn learning. ("spotted" is for
    -- any enemy player, from "Any enemy player".)
    if unit and Plain(UnitIsPlayer(unit)) == true then
        m.isPlayer = true
        local info = PlayerInfo(unit)
        local hostile = ns.IsHostilePlayer(unit)
        local who = (hostile and "enemy" or "") .. ((hostile and info ~= "") and ", " or "") .. info
        Log("found", name, source)
        local key, full = ns.PlayerKey(unit)
        if key and full ~= name then m.full, m.key = full, key end   -- for the target button
        Alert("PLAYER", name, string.format("%s found! (%s%s)", name, who ~= "" and (who .. " – ") or "", Location()),
            (who ~= "" and (who .. " · ") or "") .. Location())
        Refresh()
        return
    end
    m.isPlayer = nil
    local extra = ""
    if m.lastDeath and m.sampledDeath ~= m.lastDeath then
        local gap = now - m.lastDeath
        m.sampledDeath = m.lastDeath
        if gap < 12 * 3600 then
            table.insert(m.samples, gap)
            extra = string.format(" %s after last kill.", Fmt(gap))
        end
    end
    local hp = ""
    local cur, max = unit and Plain(UnitHealth(unit)), unit and Plain(UnitHealthMax(unit))
    if type(cur) == "number" and type(max) == "number" and max > 0 then
        hp = string.format(" · HP %d%%", math.floor(cur / max * 100 + 0.5))
    end
    Log("spawn", name, source)
    Alert("SPAWN", name, string.format("%s is UP! (%s, %s)%s%s", name, Location(), source or "?", hp, extra),
        Location() .. hp)
    Refresh()
end

function ns.ResetData()
    db.mobs = {}
    Print("All kill and respawn data reset.")
    Refresh()
end

-- ---------------------------------------------------------------- scanning

local guidToName = {}   -- GUIDs of watched mobs seen this session, for UNIT_DIED / PARTY_KILL
local enemySeen = {}    -- enemy player name -> last announced
local friendSeen = {}   -- friendly player name -> last announced
ns.lastEnemy = nil      -- { name =, at = } for the panel and mini bar
ns.lastFriend = nil     -- the same for friendly players

-- Any hostile player (PvP), when "Any enemy player" is on. Not in instances or battlegrounds,
-- and the same player only once every ENEMY_COOLDOWN seconds.
local function CheckEnemyPlayer(unit, name, source)
    local hostile = Plain(UnitIsEnemy("player", unit)) == true or Plain(UnitCanAttack("player", unit)) == true
    if not hostile or Plain(UnitIsDead(unit)) == true then return end
    local inInstance = IsInInstance and IsInInstance()
    if inInstance then return end
    local now = time()
    ns.lastEnemy = { name = name, at = now }
    if enemySeen[name] and now - enemySeen[name] < ENEMY_COOLDOWN then return end
    enemySeen[name] = now
    local info = PlayerInfo(unit)
    Log("enemy", name, source)
    Alert("ENEMY", name, string.format("Enemy player: %s (%s%s)", name, info ~= "" and (info .. " – ") or "", Location()),
        (info ~= "" and (info .. " · ") or "") .. Location())
end

-- ---------------------------------------------------------------- nearby enemies (like Spy)
-- Every enemy player the nameplates, target, mouseover or focus show is listed for a while, with
-- level, class and guild. Stealth is spotted from the cast (Stealth, Vanish, Prowl, Shadowmeld): the
-- nameplate goes at once, so the name it last showed is kept for a moment. Learned from Spy's
-- Forever port. In game only – nothing is sent to the phone.
local NEARBY_ACTIVE, GONE_WINDOW = 30, 1.5
function ns.NearbyKeepMin() return math.max(1, math.min(30, tonumber(db and db.nearbyKeep) or 5)) end
local function NearbyKeep() return ns.NearbyKeepMin() * 60 end
local STEALTH_IDS = { [1784] = "Stealth", [1785] = "Stealth", [1786] = "Stealth", [1787] = "Stealth",
    [1856] = "Vanish", [1857] = "Vanish", [5215] = "Prowl", [6783] = "Prowl", [9913] = "Prowl",
    [20580] = "Shadowmeld" }
local STEALTH_NAMES = { Stealth = true, Vanish = true, Prowl = true, Shadowmeld = true }
ns.nearby = {}            -- key -> { key, name, first, class, level, guild, firstSeen, last, stealth, targetingMe }
ns.NEARBY_ACTIVE = NEARBY_ACTIVE
local plateKeys, gonePlates, lastStealth = {}, {}, {}

-- Forever player names have a surname where Classic had the realm: key "First-Last", shown "First Last".
local function PlayerKey(unit)
    local name, realm = UnitName(unit)
    name, realm = Plain(name), Plain(realm)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm, name .. " " .. realm, name end
    return name, name, name
end
ns.PlayerKey = PlayerKey

-- The macro that targets a player: the full name first, then the other ways Forever may want it.
function ns.TargetMacro(first, full, key)
    if not full or full == first then return "/targetexact " .. first end
    return table.concat({ "/cleartarget", "/targetexact " .. full, "/targetexact [noexists] " .. key,
        "/targetexact [noexists] " .. first }, "\n")
end

local function NoteNearby(unit)
    local key, display, first = PlayerKey(unit)
    if not key then return end
    local now, e, isNew = time(), ns.nearby[key], false
    if not e then
        e = { key = key, name = display, first = first, firstSeen = now }
        ns.nearby[key] = e
        isNew = true
    end
    e.last = now
    local _, class = UnitClass(unit)
    class = Plain(class)
    if type(class) == "string" then e.class = class end
    local lvl = Plain(UnitLevel(unit))
    if type(lvl) == "number" then e.level = lvl end
    local guild = Plain((GetGuildInfo(unit)))
    if type(guild) == "string" and guild ~= "" then e.guild = guild end
    local race = Plain((UnitRace(unit)))
    if type(race) == "string" and race ~= "" then e.race = race end
    if Plain(UnitIsUnit(unit .. "target", "player")) == true then e.targetingMe = now end
    -- the history (kept between sessions)
    local r = ns.EnemyRecord(key, display)
    if isNew or now - (r.lastSeen or 0) > NearbyKeep() then r.seen = (r.seen or 0) + 1 end
    r.lastSeen, r.zone = now, GetZoneText and Plain(GetZoneText()) or r.zone
    r.class, r.level, r.guild, r.race = e.class or r.class, e.level or r.level, e.guild or r.guild, e.race or r.race
    local guid = Plain(UnitGUID(unit))
    if type(guid) == "string" then ns.playerGuids[guid] = key end
    e.kos = ns.IsKOS(key, first, e.guild)
    if isNew then
        local w = ns.Wanted and ns.Wanted(key)
        if e.kos and db.kosAlert ~= false and ns.OnKOS then ns.OnKOS(e)
        elseif w and db.wantedAlert ~= false and ns.OnWantedSeen then ns.OnWantedSeen(e, w)
        elseif ns.OnNewEnemy then ns.OnNewEnemy(e) end
    end
    return key
end

-- ---------------------------------------------------------------- KOS, notes and history
ns.playerGuids = {}   -- GUID -> key, this session (for kills)
local ENEMY_MAX = 2000

function ns.EnemyRecord(key, name)
    local r = db.enemies[key]
    if not r then
        r = { name = name or key:gsub("%-", " "), firstSeen = time(), seen = 0, kills = 0, deaths = 0 }
        db.enemies[key] = r
        ns.enemyCount = (ns.enemyCount or 0) + 1
        if ns.enemyCount > ENEMY_MAX then ns.PruneEnemies() end
    elseif name then
        r.name = name
    end
    return r
end

-- Too many: the oldest ones without KOS, a note or kills go first.
function ns.PruneEnemies()
    local list = {}
    for k, r in pairs(db.enemies) do
        if not (r.kos or r.avoid or r.wanted or r.note or (r.kills or 0) > 0 or (r.deaths or 0) > 0) then list[#list + 1] = { k, r.lastSeen or 0 } end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, math.floor(#list / 4) do db.enemies[list[i][1]] = nil end
    ns.enemyCount = nil
    local n = 0
    for _ in pairs(db.enemies) do n = n + 1 end
    ns.enemyCount = n
end

-- KOS: the player (by full key or by first name only) or the guild.
function ns.IsKOS(key, first, guild)
    local r = db.enemies[key]
    if r and r.kos then return true end
    local f = first and db.enemies[first]
    if f and f.kos then return true end
    if type(guild) == "string" and db.kosGuilds[guild:lower()] then return true, "guild" end
    return false
end

-- A typed name ("Shixa Nightblade", "Shixa-Nightblade" or just "Shixa") -> the key it's stored by.
function ns.KeyFromName(name)
    name = Trim(name or "")
    if name == "" then return end
    local key = name:gsub("%s+", "-")
    for k in pairs(db.enemies) do if k:lower() == key:lower() then return k end end
    return key
end

function ns.SetKOS(key, on)
    local r = ns.EnemyRecord(key)
    r.kos = on and true or nil
    local e = ns.nearby[key]
    if e then e.kos = ns.IsKOS(key, e.first, e.guild) end
    Print((on and "|cffff3030KOS|r: " or "No longer KOS: ") .. r.name)
    if ns.UpdatePlates then ns.UpdatePlates() end
    Refresh()
end

function ns.SetGuildKOS(guild, on)
    guild = Trim(guild or "")
    if guild == "" then return end
    db.kosGuilds[guild:lower()] = on and guild or nil
    for key, e in pairs(ns.nearby) do e.kos = ns.IsKOS(key, e.first, e.guild) end
    Print((on and "|cffff3030KOS guild|r: " or "No longer a KOS guild: ") .. "<" .. guild .. ">")
    if ns.UpdatePlates then ns.UpdatePlates() end
    Refresh()
end

function ns.SetNote(key, text)
    local r = ns.EnemyRecord(key)
    text = Trim(text or "")
    r.note = text ~= "" and text or nil
    Refresh()
    if ns.RefreshHistory then ns.RefreshHistory() end
end

function ns.ForgetEnemy(key)
    local fw = db.enemies[key] and db.enemies[key].wanted
    if fw and not fw.paid and ns.WantedMine and not ns.WantedMine(fw) then
        Print("Can't forget " .. (db.enemies[key].name or key) .. ": " .. (fw.by or "someone") .. " has a bounty on them.")
        return false
    end
    if fw and ns.WantedMine and ns.WantedMine(fw) then ns.RemoveWanted(key) end   -- yours: down for all
    db.enemies[key] = nil
    if ns.AvoidChanged then ns.AvoidChanged() end
    ns.enemyCount = nil
    Refresh()
end

-- A kill by you or your group: if it was a player we know, count it.
function ns.OnPlayerKill(targetGuid)
    targetGuid = Plain(targetGuid)
    local key = type(targetGuid) == "string" and ns.playerGuids[targetGuid]
    if not key then return end
    local r = ns.EnemyRecord(key)
    r.kills = (r.kills or 0) + 1
    r.lastKill = time()
    Log("kill", r.name)
    Print("Killed " .. r.name .. " |cffaaaaaa(" .. r.kills .. " kill" .. (r.kills == 1 and "" or "s") .. ")|r")
    if ns.OnWantedKill then ns.Safe("wanted", ns.OnWantedKill, key) end
    Refresh()
end

-- You died: the enemy player who had you targeted most recently (within 10 s) gets the kill.
function ns.OnPlayerDead()
    local best, at, now = nil, 0, time()
    for key, e in pairs(ns.nearby) do
        if e.targetingMe and now - e.targetingMe <= 10 and e.targetingMe > at then best, at = key, e.targetingMe end
    end
    if not best then return end
    local r = ns.EnemyRecord(best)
    r.deaths = (r.deaths or 0) + 1
    r.lastDeath = now
    Log("killed by", r.name)
    Print("Killed by " .. r.name .. "? |cffaaaaaa(" .. r.deaths .. " time" .. (r.deaths == 1 and "" or "s") .. ")|r")
    Refresh()
end

-- Newest first; old ones are dropped.
function ns.NearbyList()
    local list, now = {}, time()
    for key, e in pairs(ns.nearby) do
        if now - e.last > NearbyKeep() or (e.example and now >= e.example) then ns.nearby[key] = nil
        else list[#list + 1] = e end
    end
    table.sort(list, function(a, b) if a.last ~= b.last then return a.last > b.last end return a.key < b.key end)
    return list
end

-- How the Nearby list looks here: "show" (open world, or battlegrounds when allowed), "fade" (dungeons
-- and raids) or "hide" (where the settings say so).
function ns.NearbyZoneMode()
    if not IsInInstance then return "show" end
    local inside, kind = IsInInstance()
    if not inside then return "show" end
    if kind == "pvp" or kind == "arena" then return db.nearbyNoBG == false and "show" or "hide" end
    if kind == "raid" then return db.nearbyHideRaid and "hide" or "fade" end
    if kind == "party" or kind == "scenario" then return db.nearbyHideDungeon and "hide" or "fade" end
    return "fade"
end

-- Where Nearby works: the open world; battlegrounds and arenas only when "Hide in battlegrounds" is unticked.
function ns.NearbyHere()
    if not (IsInInstance) then return true end
    local inside, kind = IsInInstance()
    if not inside then return true end
    if kind == "pvp" or kind == "arena" then return db.nearbyNoBG == false end
    return false   -- dungeons and raids: no enemy players there anyway
end

local function OnStealthCast(unit, spellID)
    if not (db.nearby and type(unit) == "string") or not ns.NearbyHere() then return end
    if not (unit == "target" or unit == "focus" or unit == "mouseover" or unit:find("^nameplate%d+$")) then return end
    spellID = Plain(spellID)
    if type(spellID) ~= "number" then return end
    local what = STEALTH_IDS[spellID]
    if not what then
        local nameOf = (C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(spellID)))
            or (GetSpellInfo and Plain((GetSpellInfo(spellID))))
        if not (type(nameOf) == "string" and STEALTH_NAMES[nameOf]) then return end
        what = nameOf
    end
    local key
    if Plain(UnitExists(unit)) == true and Plain(UnitIsPlayer(unit)) == true then
        if not ns.IsHostilePlayer(unit) then return end
        key = NoteNearby(unit)
    else
        local gone = gonePlates[unit]
        if gone and GetTime() - gone.at <= GONE_WINDOW then key = gone.key end
    end
    local e = key and ns.nearby[key]
    if not e then return end
    local now = time()
    e.stealth, e.stealthHow = now, what
    if lastStealth[key] and now - lastStealth[key] < 5 then return end   -- one cast fires on every token
    lastStealth[key] = now
    Log("stealth", e.name, what)
    local info = ((e.level and e.level > 0) and (e.level .. " ") or "") .. (e.class and (e.class:sub(1, 1) .. e.class:sub(2):lower()) or "")
    Print("|cffc080ffStealthed player detected:|r " .. e.name .. (info ~= "" and (" (" .. info .. ")") or "")
        .. " – " .. what)
    if db.stealthWarn == false then Refresh() return end
    if db.stealthSound ~= false then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if ns.ShowStealthToast then ns.ShowStealthToast(e) end
    Refresh()
end

-- ---------------------------------------------------------------- healers (for the nameplate icons)
-- Only proof counts, never "he cast a heal" (a Ret paladin or a Feral druid heals himself too):
--   * friendly players: their talents, read by inspecting them (like Leatrix Plus's ID card on Forever: the
--     three trees side by side in one trait tree, told apart by the gaps between the columns), or their group role.
--   * enemy players can't be inspected (WoW never lets you inspect the other faction), so: a cast of a spell only
--     a healing talent gives (Riptide, Wild Growth, Prayer of Mending, Holy Shock ...), or a healer's form.
--     A spell or form only a damage talent gives (Shadowform, Moonkin Form, Lava Burst ...) proves the opposite.
-- Spells are matched by name, so every rank counts. Final talents on Forever from ForeverAuras' catalog
-- (talentsforever.com). Kept for 30 days in db.roles, for friends and enemies alike.
local HEALER_TALENT_IDS = {
    401859, 10060, 724, 34861, 47540,   -- priest: Prayer of Mending, Power Infusion, Lightwell, Circle of Healing, Penance
    408521, 16190, 974,                 -- shaman: Riptide, Mana Tide Totem, Earth Shield
    408120, 18562, 33891,               -- druid: Wild Growth, Swiftmend, Tree of Life
    20473, 53563 }                      -- paladin: Holy Shock, Beacon of Light
local DAMAGE_TALENT_IDS = {
    15473, 15407, 15286, 15487,         -- priest: Shadowform, Mind Flay, Vampiric Embrace, Silence
    408490, 16166, 17364, 425336,       -- shaman: Lava Burst, Elemental Mastery, Stormstrike, Rage of the Farseer
    24858, 5570, 16979, 417141,         -- druid: Moonkin Form, Insect Swarm, Feral Charge, Berserk
    20375, 20066, 20925 }               -- paladin: Seal of Command, Repentance, Holy Shield
-- The talent trees, left to right, that make a healer.
local HEALER_TREES = { PRIEST = { [1] = true, [2] = true }, PALADIN = { [1] = true }, SHAMAN = { [3] = true },
    DRUID = { [3] = true } }
local ROLE_DAYS, ROLE_MAX, REINSPECT = 30, 3000, 24 * 3600
ns.roles = {}              -- "plate:nameplateN" -> role, for players whose name is hidden (battlegrounds)
local roleSpells = nil

local function SpellName(id)
    local n = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
    if type(n) ~= "string" and GetSpellInfo then n = Plain((GetSpellInfo(id))) end
    return type(n) == "string" and n or nil
end
ns.SpellName = SpellName

local function RoleOfSpell(spellID)   -- "healer", "dps" or nil, and the spell's name
    if not roleSpells then
        roleSpells = {}
        for _, id in ipairs(HEALER_TALENT_IDS) do local n = SpellName(id); if n then roleSpells[n] = "healer" end end
        for _, id in ipairs(DAMAGE_TALENT_IDS) do local n = SpellName(id); if n then roleSpells[n] = "dps" end end
    end
    local n = SpellName(spellID)
    return n and roleSpells[n], n
end

local function RoleStore()
    db.roles = type(db.roles) == "table" and db.roles or {}
    return db.roles
end

local function PruneRoles(t)
    local list = {}
    for k, r in pairs(t) do list[#list + 1] = { k, r.at or 0 } end
    if #list <= ROLE_MAX then return end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, #list - ROLE_MAX + 200 do t[list[i][1]] = nil end
end

-- Remember what a player is. key = "First-Last" (or nil when the name is hidden; then the plate holds it).
local function SetRole(key, unit, role, how)
    local entry = { role = role, how = how, at = time() }
    local old
    if key then
        local t = RoleStore()
        old = t[key]
        t[key] = entry
        if not old then PruneRoles(t) end
    elseif type(unit) == "string" and unit:find("^nameplate%d+$") then
        old = ns.roles["plate:" .. unit]
        ns.roles["plate:" .. unit] = entry
    else
        return
    end
    if old and old.role == role then return end
    Log("role", key or unit, role, how)
    if ns.UpdatePlates then ns.UpdatePlates() end
end

local function KnownUnit(unit)
    return type(unit) == "string" and (unit == "target" or unit == "focus" or unit == "mouseover"
        or unit:find("^nameplate%d+$") or unit:find("^party%d$") or unit:find("^raid%d+$"))
end

local function OnRoleCast(unit, spellID)
    if not KnownUnit(unit) then return end
    spellID = Plain(spellID)
    if type(spellID) ~= "number" or Plain(UnitIsPlayer(unit)) ~= true then return end
    local role, name = RoleOfSpell(spellID)
    if role then SetRole((PlayerKey(unit)), unit, role, name) end
end

-- A healer's or damage dealer's form on the player (Tree of Life, Shadowform, Moonkin Form). Out of combat;
-- Forever hides auras in combat, and then this finds nothing.
function ns.ScanRoleAuras(unit)
    if Plain(UnitIsPlayer(unit)) ~= true then return end
    for i = 1, 40 do
        local id
        if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
            if not ok or type(a) ~= "table" then break end
            id = Plain(a.spellId)
        elseif UnitBuff then
            local ok, name, _, _, _, _, _, _, _, sid = pcall(UnitBuff, unit, i)
            if not ok or name == nil then break end
            id = Plain(sid)
        else
            return
        end
        if type(id) == "number" then
            local role, name = RoleOfSpell(id)
            if role then SetRole((PlayerKey(unit)), unit, role, name) return end
        end
    end
end

-- The role for a player: "healer", "dps" or nil, and how it's known.
function ns.Role(key, unit)
    if type(unit) == "string" and UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        r = ok and Plain(r)
        if r == "HEALER" then return "healer", "group role" end
        if r == "TANK" or r == "DAMAGER" then return "dps", "group role" end
    end
    local e = key and db and type(db.roles) == "table" and db.roles[key]
    if e and time() - (e.at or 0) < ROLE_DAYS * 86400 then return e.role, e.how end
    e = (type(unit) == "string" and ns.roles["plate:" .. unit]) or (key and ns.roles[key])   -- (by key: the example)
    if e then return e.role, e.how end
end
function ns.IsHealer(key, unit) return ns.Role(key, unit) == "healer" end

-- ---- inspecting friendly players' talents
-- One at a time, out of combat, only healing classes in inspect range, and never while you have the Inspect window
-- open (that's yours). Each player again after a day at most. If the game blocks it, it's off until /reload.
local inspect = { pending = nil, last = 0, tried = {} }
local HEAL_CLASSES = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }

-- Points per tree, left to right, from Forever's trait tree (config -1 = the inspected player), or nil.
local function InspectTrees()
    local cfg = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID or -1
    if C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo then
        local ok, info = pcall(C_Traits.GetConfigInfo, cfg)
        local trees = ok and type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs
        local columns, xs = {}, {}
        for _, treeID in ipairs(trees or {}) do
            local okN, nodes = pcall(C_Traits.GetTreeNodes, Plain(treeID))
            for _, nodeID in ipairs(okN and type(nodes) == "table" and nodes or {}) do
                local okI, node = pcall(C_Traits.GetNodeInfo, cfg, Plain(nodeID))
                local x = okI and type(node) == "table" and Plain(node.posX)
                if type(x) == "number" then
                    local pts = tonumber(Plain(node.ranksPurchased)) or 0
                    if pts == 0 then pts = tonumber(Plain(node.activeRank)) or 0 end
                    if not columns[x] then columns[x] = 0; xs[#xs + 1] = x end
                    columns[x] = columns[x] + pts
                end
            end
        end
        if #xs >= 3 then
            table.sort(xs)
            local gaps = {}
            for i = 2, #xs do gaps[#gaps + 1] = xs[i] - xs[i - 1] end
            table.sort(gaps)
            local usual = gaps[math.ceil(#gaps / 2)] or 0
            local out = { columns[xs[1]] }
            for i = 2, #xs do
                if xs[i] - xs[i - 1] > usual * 1.5 then out[#out + 1] = 0 end
                out[#out] = out[#out] + columns[xs[i]]
            end
            if #out == 3 then return out end
        end
    end
    if GetNumTalentTabs and GetTalentTabInfo then   -- the classic way
        local out = {}
        for tab = 1, 3 do
            local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab, true)
            if not ok then return end
            local spent = type(a) == "string" and c or e
            spent = tonumber(Plain(spent))
            if not spent then return end
            out[tab] = spent
        end
        return out
    end
end

local function ReadInspect(p, tries)
    if inspect.pending ~= p then return end
    local trees = InspectTrees()
    local total = trees and (trees[1] + trees[2] + trees[3]) or 0
    if total == 0 and tries < 3 then   -- the answer can take a moment to fill in
        C_Timer.After(0.5 * tries, function() ns.Safe("inspect", ReadInspect, p, tries + 1) end)
        return
    end
    inspect.pending = nil
    if total > 0 then
        local best = 1
        for i = 2, 3 do if trees[i] > trees[best] then best = i end end
        local heal = HEALER_TREES[p.class] and HEALER_TREES[p.class][best]
        SetRole(p.key, nil, heal and "healer" or "dps", "talents " .. table.concat(trees, "/"))
    end
    if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then pcall(ClearInspectPlayer) end
end

function ns.OnInspectReady(guid)
    local p = inspect.pending
    if p and Plain(guid) == p.guid then ReadInspect(p, 1) end
end

-- Called for friendly players on nameplates (UI.lua). Asks for at most one inspect every 3 seconds.
function ns.MaybeInspect(unit)
    if inspect.blocked or not (db.plateFriendly and db.plateHealer ~= false) then return end
    if not (NotifyInspect and CanInspect) or InCombatLockdown() then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    local now = GetTime()
    if inspect.pending and now - inspect.pending.at < 5 then return end
    if now - inspect.last < 3 then return end
    local _, class = UnitClass(unit)
    class = Plain(class)
    if not HEAL_CLASSES[class] or Plain(UnitIsUnit(unit, "player")) == true then return end
    if Plain(UnitIsPlayer(unit)) ~= true or ns.IsHostilePlayer(unit) then return end
    local key = PlayerKey(unit)
    local guid = Plain(UnitGUID(unit))
    if not key or type(guid) ~= "string" then return end
    local e = type(db.roles) == "table" and db.roles[key]
    if e and e.how and e.how:find("^talents") and time() - (e.at or 0) < REINSPECT then return end
    if inspect.tried[key] and now - inspect.tried[key] < 300 then return end
    local ok, can = pcall(CanInspect, unit)
    if not ok or Plain(can) ~= true then return end
    if CheckInteractDistance then
        local okD, near = pcall(CheckInteractDistance, unit, 1)
        if okD and Plain(near) == false then return end
    end
    inspect.tried[key], inspect.last = now, now
    inspect.pending = { key = key, guid = guid, class = class, at = now }
    pcall(NotifyInspect, unit)
end

-- The game said no (ADDON_ACTION_BLOCKED): stop asking.
function ns.InspectBlocked()
    inspect.blocked, inspect.pending = true, nil
    Print("Reading friendly players' talents isn't allowed on this client – the healer mark uses their spells instead.")
end

-- ---------------------------------------------------------------- XP boosts (until max level)
-- What gives extra XP on Forever, and what you're missing right now. From the Forever guides (Nov 2026):
--   * Rested: kills give double XP until it's spent (quests don't). Builds in an inn or a city while logged
--     out, 5% of a level per 8 hours, up to 150%.
--   * Camp Tent (Leatherworking 20, 5 Light Leather): by a campfire it tops rested up to 5% of a level, for
--     everyone sitting there a minute; then "Boosted Rest" blocks another tent for 1 hour.
--   * Well Fed (cooked food): +5% kill XP, about 15 minutes, gone on death.
--   * Cozy Sleeping Bag (quest chain from level 14): lying on it gives Well-Rested, +1% XP a minute, up to 3.
-- Your auras are hidden in combat on Forever, so they're read out of combat and kept (counting down).
local CAMP_TENT, SLEEPING_BAG = 279978, 211527
local CAMPFIRES = { { 279981, "Basic Campfire" }, { 279961, "Journeyman Campfire" }, { 279974, "Expert Campfire" } }
-- The other camp features (put by a campfire, they buff everyone sitting there; they share a 1-hour cooldown).
-- From ForeverFishing's camp list (Nov 2026); anything else whose tooltip says "Requires a Campfire nearby"
-- is found in your bags too.
local CAMP_FEATURES = {
    { 279979, "Camp Chair" }, { 279967, "Fish Bowl" }, { 279960, "Lodestone" }, { 279944, "Sharpening Wheel" },
    { 279962, "Incense Candle" }, { 279956, "Mana Well" }, { 279976, "Enchanted Lute" }, { 279968, "First Aid Kit" },
    { 279950, "Reagent Bot" }, { 279949, "Repair Bot" }, { 279957, "Cookie's Feast" }, { 279972, "Faction Banner" },
    { 279973, "Faction Banner" }, { 279965, "Fishing Rack" }, { 279966, "Fishing Hut" }, { 279970, "Fermenter" },
    { 279990, "Alchemy Laboratory" }, { 279988, "Anvil" }, { 279955, "Master Forge" }, { 279985, "Arcane Salvager" },
    { 279987, "Arcane Forge" }, { 279989, "Anarchist's Workbench" }, { 279964, "Greenhouse" },
    { 279947, "Seed Hybridizer" }, { 279941, "Tanning Rack" }, { 279945, "Sewing Machine" }, { 279948, "Rock Garden" },
    { 279952, "Molten Foundry" }, { 279969, "Field Guide" }, { 279938, "Trapper's Workbench" },
    { 279943, "Spinning Wheel" }, { 279959, "Loom" }, { 279982, "Iron Oven" }, { 279940, "Toxin Study" },
    { 279951, "Plague Doctor's Laboratory" },
}
local WELL_FED, BOOSTED_REST, WELL_RESTED = 1243969, 1229451, 429959
local AURA_NAMES = { [WELL_FED] = "Well Fed", [BOOSTED_REST] = "Boosted Rest", [WELL_RESTED] = "Well-Rested" }
local auraCache = { at = 0 }

-- Bags are only read again when they change (BAG_UPDATE), not on every refresh: counts and XP food are kept.
local bagState = { dirty = true, at = -100, pending = false }
local statusCache = { at = -100, dirty = true }
local countCache = {}
local ItemCountRaw
local function ItemCount(id)
    local c = countCache[id]
    if not c then c = { ItemCountRaw(id) }; countCache[id] = c end
    return c[1], c[2]
end
ItemCountRaw = function(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    local n = 0
    if f then
        local ok, c = pcall(f, id)
        n = ok and tonumber(Plain(c)) or 0
    end
    if n == 0 and PlayerHasToy then   -- the sleeping bag may be a toy
        local ok, has = pcall(PlayerHasToy, id)
        if ok and Plain(has) == true then return 1, true end
    end
    return n, false
end

local function ItemName(id, fallback)
    local n = GetItemInfo and Plain((GetItemInfo(id)))
    return type(n) == "string" and n or fallback
end

local function ItemCooldownLeft(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return 0 end
    local ok, start, dur = pcall(f, id)
    start, dur = ok and tonumber(Plain(start)), ok and tonumber(Plain(dur))
    if not (start and dur) or start == 0 or dur <= 1.5 then return 0 end   -- 1.5 s = the global cooldown
    return math.max(0, start + dur - GetTime())
end

-- Does a buff's text say it gives XP? (true / false / nil = can't tell). Set below, with the tooltip helpers.
local AuraIsXP

-- The boost auras on you: spell ID -> { left = seconds (nil: no end), stacks }.
-- Well Fed counts when it's the XP one: its own ID, or any buff whose text says it gives XP from kills (a
-- "Well Fed" from stat food doesn't count when its text can be read).
local function ReadAuras()
    local byName, found = {}, {}
    for id, en in pairs(AURA_NAMES) do
        byName[en] = id
        local n = SpellName(id)
        if n then byName[n] = id end
    end
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local name, count, expires, sid
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if not ok or type(a) ~= "table" then break end
                name, count, expires, sid = a.name, a.applications, a.expirationTime, a.spellId
            elseif UnitAura then
                local ok, n, _, c, _, _, e, _, _, _, s = pcall(UnitAura, "player", i, filter)
                if not ok or n == nil then break end
                name, count, expires, sid = n, c, e, s
            else
                break
            end
            name, count, expires, sid = Plain(name), Plain(count), Plain(expires), Plain(sid)
            if filter == "HELPFUL" and type(name) == "string" and name:lower():find("campfire", 1, true) then
                found.campfire = true   -- e.g. Welcoming Campfire: there's a fire close by
            end
            if filter == "HELPFUL" and (name == "Food" or name == "Food & Drink" or name == "Refreshment") then
                found.eating = true     -- sitting and eating: the new Well Fed comes after 10 seconds
            end
            local id = (AURA_NAMES[sid] and sid) or (type(name) == "string" and byName[name])
            if filter == "HELPFUL" and AuraIsXP and id ~= WELL_RESTED and sid ~= WELL_FED then
                local xp = AuraIsXP(i, sid, name)
                if id == WELL_FED and xp == false then id = nil          -- stat food's Well Fed
                elseif not id and xp then id = WELL_FED end              -- an XP buff by another name
            end
            if id and not found[id] then
                local left = (type(expires) == "number" and expires > 0) and math.max(0, expires - GetTime()) or nil
                found[id] = { left = left, stacks = tonumber(count) or 0 }
            end
        end
    end
    return found
end

function ns.MaxLevel()
    local m = GetMaxPlayerLevel and Plain(GetMaxPlayerLevel())
    return tonumber(m) or 60
end

-- XP food: anything in your bags whose tooltip says "Experience (gained) from kills is increased by 5%" (how
-- Forever words it; ForeverFishing's food journal reads the same line) – or gives rested XP.
-- The plain item tooltip (item:ID) is read, not the bag slot: food you cooked yourself says "<Made by Name>",
-- and names are secret on Forever (touching them is an error). Every line is checked before it's read.
local xpFoodCache = {}   -- itemID -> true/false (false is asked again after a while)
local NOT_FOOD = { [CAMP_TENT] = true, [SLEEPING_BAG] = true }
local CAMP_KNOWN = { [CAMP_TENT] = true }
for _, c in ipairs(CAMPFIRES) do NOT_FOOD[c[1]] = true; CAMP_KNOWN[c[1]] = true end
for _, c in ipairs(CAMP_FEATURES) do NOT_FOOD[c[1]] = true; CAMP_KNOWN[c[1]] = true end

local function IsXPText(t)
    if type(t) ~= "string" then return false end
    local l = t:lower()
    local xp = l:find("experience", 1, true) or l:find("%f[%a]xp%f[%A]")
    return xp and (l:find("kill", 1, true) or l:find("rested", 1, true)) and true or false
end
ns.IsXPText = IsXPText

local function Secret(v) return Plain(v) == nil and v ~= nil end
local RETRIEVING = type(RETRIEVING_ITEM_INFO) == "string" and RETRIEVING_ITEM_INFO or "Retrieving item information"

-- The tooltip's text as one string, or nil (not loaded yet / can't be read).
local function TooltipText(data)
    if type(data) ~= "table" or Secret(data) then return nil end
    local ok, lines = pcall(rawget, data, "lines")
    if not ok or type(lines) ~= "table" or Secret(lines) then return nil end
    local out = {}
    for i = 1, 40 do
        local okL, line = pcall(rawget, lines, i)
        if not okL or line == nil then break end
        if type(line) == "table" and not Secret(line) then
            for _, key in ipairs({ "leftText", "rightText" }) do
                local okT, t = pcall(rawget, line, key)
                t = okT and Plain(t)
                if type(t) == "string" then
                    if t == RETRIEVING then return nil end
                    out[#out + 1] = t
                end
            end
        end
    end
    return #out > 0 and table.concat(out, "\n") or nil
end

-- The old way, if the tooltip data API can't read it: a hidden tooltip, line by line.
local scanTip
local function ScanTipText(itemID)
    if not (CreateFrame and WorldFrame) then return nil end
    if not scanTip then
        local ok, t = pcall(CreateFrame, "GameTooltip", "WatchXScanTip", nil, "GameTooltipTemplate")
        if not ok or not t then return nil end
        scanTip = t
    end
    local out, loading = {}, false
    pcall(function()
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetHyperlink("item:" .. itemID)
        for i = 1, math.min(30, scanTip:NumLines() or 0) do
            local fs = _G["WatchXScanTipTextLeft" .. i]
            local t = fs and Plain(fs:GetText())
            if type(t) == "string" then
                if t == RETRIEVING then loading = true end
                out[#out + 1] = t
            end
        end
    end)
    pcall(scanTip.Hide, scanTip)
    if loading or #out == 0 then return nil end
    return table.concat(out, "\n")
end

local function ItemTooltipText(itemID, bag, slot)
    local T = C_TooltipInfo or {}
    local text
    if T.GetHyperlink then
        local ok, data = pcall(T.GetHyperlink, "item:" .. itemID)
        if ok then text = TooltipText(data) end
    end
    if not text and T.GetItemByID then
        local ok, data = pcall(T.GetItemByID, itemID)
        if ok then text = TooltipText(data) end
    end
    if not text then text = ScanTipText(itemID) end
    if not text and T.GetBagItem and bag then
        local ok, data = pcall(T.GetBagItem, bag, slot)
        if ok then text = TooltipText(data) end
    end
    return text
end

-- The item's Use: spell, in words (some foods only say it there).
local function ItemSpellText(itemID)
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not get then return nil end
    local ok, _, sid = pcall(get, itemID)
    sid = ok and tonumber(Plain(sid))
    if not sid then return nil end
    local desc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if not desc then return nil end
    local okD, t = pcall(desc, sid)
    t = okD and Plain(t)
    return type(t) == "string" and t ~= "" and t or nil
end

-- A buff's text: its tooltip, or its spell's description. Cached per spell (it doesn't change).
local auraXPCache = {}
AuraIsXP = function(index, sid, name)
    local key = sid or name
    if key == nil then return nil end
    local c = auraXPCache[key]
    if type(c) == "boolean" then return c end
    if c and GetTime() < c then return nil end   -- couldn't be read a moment ago
    local text
    local T = C_TooltipInfo
    for _, f in ipairs({ T and T.GetUnitAura or false, T and T.GetUnitBuff or false }) do
        if f and not text then
            local ok, data = pcall(f, "player", index, "HELPFUL")
            if ok then text = TooltipText(data) end
        end
    end
    if not text and sid then
        local desc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
        if desc then
            local ok, t = pcall(desc, sid)
            t = ok and Plain(t)
            if type(t) == "string" and t ~= "" then text = t end
        end
    end
    if not text then auraXPCache[key] = GetTime() + 60 return nil end
    -- the name line alone isn't the description
    local body = name and text:gsub("^" .. name:gsub("%p", "%%%0") .. "\n?", "") or text
    local yes = IsXPText(body)
    auraXPCache[key] = yes
    return yes
end

local function IsConsumable(itemID)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return true end
    local ok, _, _, _, _, _, classID = pcall(f, itemID)
    classID = ok and tonumber(Plain(classID))
    return classID == nil or classID == 0   -- 0 = Consumable (food, drink, potions)
end

local function IsXPFood(itemID, bag, slot)
    local known = xpFoodCache[itemID]
    if known == true then return true end
    if db and type(db.xpFoods) == "table" and db.xpFoods[itemID] then xpFoodCache[itemID] = true return true end
    if type(known) == "number" and GetTime() < known then return false end
    if NOT_FOOD[itemID] or not IsConsumable(itemID) then xpFoodCache[itemID] = GetTime() + 3600 return false end
    local text = ItemTooltipText(itemID, bag, slot)
    if not text then bagState.pending = true return false end   -- not loaded yet: ask again a bit later
    local yes = IsXPText(text) or IsXPText(ItemSpellText(itemID))
    xpFoodCache[itemID] = yes or (GetTime() + 120)   -- a "no" is checked again in 2 minutes
    if yes and db then   -- kept: inside instances the item text may not be readable
        if type(db.xpFoods) ~= "table" then db.xpFoods = {} end
        db.xpFoods[itemID] = true
    end
    return yes
end

-- A camp feature we don't know by ID: its tooltip says "Requires a Campfire nearby". Each item is read once.
local campCache = {}   -- itemID -> true/false (false is asked again after a while)
local function IsCampExtra(itemID, bag, slot)
    if CAMP_KNOWN[itemID] or itemID == SLEEPING_BAG then return false end
    local known = campCache[itemID]
    if known == true then return true end
    if type(known) == "number" and GetTime() < known then return false end
    local text = ItemTooltipText(itemID, bag, slot)
    if not text then bagState.pending = true return false end
    local yes = text:lower():find("campfire nearby", 1, true) and true or false
    campCache[itemID] = yes or (GetTime() + 3600)
    return yes
end

-- How many XP food items you carry, and the name of the one you have most of.
local function XPFoodInBags()
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return nil end
    local total, best, bestN, bestID, byID, list = 0, nil, 0, nil, {}, {}
    local camp, campByID = {}, {}
    local slots = 0
    for bag = 0, 4 do
        local okN, n = pcall(C.GetContainerNumSlots, bag)
        slots = slots + (okN and tonumber(Plain(n)) or 0)
        for slot = 1, (okN and tonumber(Plain(n)) or 0) do
            local ok, info = pcall(C.GetContainerItemInfo, bag, slot)
            local id = ok and type(info) == "table" and not Secret(info) and Plain(info.itemID)
            if type(id) == "number" and IsCampExtra(id, bag, slot) then
                local count = tonumber(Plain(info.stackCount)) or 1
                local e = campByID[id]
                if not e then
                    e = { id = id, name = Plain(info.itemName) or ItemName(id, "Camp item"), count = 0 }
                    campByID[id], camp[#camp + 1] = e, e
                end
                e.count = e.count + count
            elseif type(id) == "number" and IsXPFood(id, bag, slot) then
                local count = tonumber(Plain(info.stackCount)) or 1
                total = total + count
                local e = byID[id]
                if not e then
                    e = { id = id, name = Plain(info.itemName) or ItemName(id, "XP food"), count = 0 }
                    byID[id], list[#list + 1] = e, e
                end
                e.count = e.count + count
                if count > bestN then
                    best, bestN, bestID = Plain(info.itemName) or (GetItemInfo and Plain((GetItemInfo(id)))), count, id
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    if slots == 0 then return nil end   -- the bags aren't there yet (a loading screen): can't tell
    return total, best, bestID, list, camp
end

-- Icons for the XP boosts strip: the item's or the buff's own icon, or a stock one if it isn't loaded yet.
local function ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if not (f and id) then return nil end
    local ok, t = pcall(f, id)
    t = ok and Plain(t)
    return (type(t) == "number" or type(t) == "string") and t or nil
end
local function SpellIcon(id)
    local f = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if not f then return nil end
    local ok, t = pcall(f, id)
    t = ok and Plain(t)
    return (type(t) == "number" or type(t) == "string") and t or nil
end

local function Clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then return ("%d:%02d:%02d"):format(sec / 3600, (sec % 3600) / 60, sec % 60) end
    return ("%d:%02d"):format(sec / 60, sec % 60)
end
ns.Clock = Clock
ns.ItemIcon = ItemIcon

-- Warnings when a boost has run out (or a wait is over): a raid-warning line mid-screen, a sound and chat.
-- Not in combat (it waits until the fight is over) and not when you've just died.
local lastBoost, pendingWarn, fedGone = nil, {}, nil
local function Warn(msg)
    Print("|cffffd100" .. msg .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.82, b = 0 })
    end
    if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end

-- Good news (a buff is done): green mid-screen, a softer sound. (On ns: the main chunk is at the locals limit.)
function ns.Done(msg)
    Print("|cff40ff40" .. msg .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, { r = 0.25, g = 1, b = 0.35 })
    end
    local snd = SOUNDKIT and (SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.RAID_WARNING)
    if PlaySound and snd then pcall(PlaySound, snd, "Master") end
end

-- In a city or an inn (resting) the XP and buff warnings keep quiet: they're for when you're out playing.
function ns.QuietHere()
    return db and db.warnInCity ~= true and IsResting and Plain(IsResting()) == true
end

local function CheckBoosts(now)
    local was = lastBoost
    lastBoost = now
    if not was or db.levelWarn == false then return end
    if Plain(UnitIsDeadOrGhost("player")) == true then return end
    local function gone(k) return was[k] and not now[k] end
    -- done: you can stop eating / get up / the tent has worked (shown at once, in town too: you just did it)
    if now.fed and not was.fed and not fedGone then
        ns.Done("Well Fed – +5% XP from kills for 15 min. You can stop eating.")
    elseif now.fed and not was.fed and fedGone then
        ns.Done("Well Fed again – topped up for 15 min.")
    end
    if (now.restedStacks or 0) >= 3 and (was.restedStacks or 0) < 3 then
        ns.Done("Well-Rested 3/3 – the full +3% XP. You can get up.")
    end
    if now.boost and not was.boost then
        ns.Done("Boosted Rest – the tent is done" .. (now.restedPct and (": rested " .. now.restedPct .. "%") or "") .. ".")
    end
    -- Well Fed gone: eating a new dish takes the old one away and gives the new one 10 seconds later, so wait 20
    -- seconds (and while you're eating) before saying it's run out.
    if gone("fed") then
        fedGone = GetTime()
        if C_Timer then C_Timer.After(21, function() statusCache.dirty = true; if ns.LevelStatus then ns.Safe("xp boosts", ns.LevelStatus) end end) end
    end
    if now.fed or now.eating then fedGone = nil end
    if fedGone and GetTime() - fedGone >= 20 then
        fedGone = nil
        pendingWarn.fed = now.food and now.food > 0 and ("Well Fed has run out – eat " .. (now.foodName or "XP food") .. ".")
            or "Well Fed has run out – and you have no XP food in your bags!"
    end
    if (was.food or 0) > 0 and now.food == 0 and not pendingWarn.fed and not now.eating then
        pendingWarn.food = "You've used your last XP food – cook or buy more."
    end
    if gone("rested") then pendingWarn.bag = "Well-Rested (Sleeping Bag) has run out." end
    if gone("boost") and now.lowRested then pendingWarn.tent = "Camp Tent works again – your rested is under 5%." end
    if gone("bagCd") and not now.rested then pendingWarn.bagReady = "Your Cozy Sleeping Bag is ready again." end
    if InCombatLockdown() then return end
    if ns.QuietHere() then wipe(pendingWarn) return end   -- in town: nothing to say
    for k, msg in pairs(pendingWarn) do
        Warn(msg)
        pendingWarn[k] = nil
    end
end

-- The XP boosts: { { state = "ok" | "todo" | "wait" | "info", name, icon, text, tip, timer, count }, ... }, or nil
-- at max level. name = the tooltip title, text = how it stands, timer = seconds left, count = a number on the icon.
-- The bags again: when they changed (at most once a second), after 15 s while an item's text wasn't loaded
-- yet, and every 2 minutes anyway.
local foodCache = {}
local function ReadBags()
    local now = GetTime()
    if bagState.loadingUntil and now < bagState.loadingUntil then return end   -- just after a loading screen
    local since = now - bagState.at
    if not ((bagState.dirty and since >= 1) or (bagState.pending and since >= 15) or since >= 120) then return end
    bagState.dirty, bagState.pending, bagState.at = false, false, now
    wipe(countCache)
    local fresh = { XPFoodInBags() }
    if fresh[1] == nil and foodCache and foodCache[1] then bagState.pending = true return end   -- keep the last good one
    foodCache = fresh
end

function ns.LevelDirty() statusCache.dirty = true; bagState.dirty = true end

-- ---------------------------------------------------------------- what you can make (XP boosts)
-- When you open a profession, the recipes that make XP things (camp tent, campfires, camp features, XP food) are
-- kept for that character. The XP icons then also show what you can make when you have none: how many you have
-- the reagents for, or what's missing, and a click opens the profession. Its own function: the main chunk is
-- close to Lua's 200-locals limit.
(function()
    local CRAFT_PROFS = { "Cooking", "Leatherworking", "Tailoring", "Engineering", "Blacksmithing", "Alchemy",
        "Woodworking", "Survival" }
    local function CharKey()
        local n = Plain(UnitName("player"))
        return type(n) == "string" and n or "?"
    end
    local function Mine()
        db.recipes = db.recipes or {}
        local k = CharKey()
        db.recipes[k] = db.recipes[k] or { items = {}, profs = {} }
        return db.recipes[k]
    end
    local function LinkID(link)
        link = Plain(link)
        return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end
    local function Kind(id)
        if id == CAMP_TENT or CAMP_KNOWN[id] then return "tent" end
        for _, c in ipairs(CAMPFIRES) do if c[1] == id then return "fire" end end
        if IsCampExtra(id) then return "tent" end
        if IsXPFood(id) then return "food" end
    end

    -- The modern profession window (C_TradeSkillUI, what WoW Forever has): recipe IDs and their schematics.
    local function ScanModern()
        local T = C_TradeSkillUI
        local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
        local prof = Plain(type(base) == "table" and base.professionName)
        if type(prof) ~= "string" or prof == "" then return end
        if T.IsTradeSkillLinked and Plain(T.IsTradeSkillLinked()) == true then return end   -- someone else's
        local found = {}
        for _, rid in ipairs(T.GetAllRecipeIDs() or {}) do
            local okI, info = pcall(T.GetRecipeInfo, rid)
            local okS, sch = pcall(T.GetRecipeSchematic, rid, false)
            if okI and type(info) == "table" and info.learned and okS and type(sch) == "table" then
                local id = tonumber(Plain(sch.outputItemID))
                local what = id and Kind(id)
                if what then
                    local reagents = {}
                    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                        local r1 = slot.reagents and slot.reagents[1]
                        local rid2 = r1 and tonumber(Plain(r1.itemID))
                        if rid2 and (slot.reagentType == nil or slot.reagentType == 1) then
                            reagents[#reagents + 1] = { id = rid2, name = ItemName(rid2, "reagent"),
                                count = tonumber(Plain(slot.quantityRequired)) or 1 }
                        end
                    end
                    found[id] = { prof = prof, name = Plain(info.name) or ItemName(id, "?"), kind = what, reagents = reagents }
                end
            end
        end
        return prof, found
    end

    local function Scan()
        local mine = Mine()
        local prof, found
        if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
            prof, found = ScanModern()
            if prof then
                for id, r in pairs(mine.items) do if r.prof == prof and not found[id] then mine.items[id] = nil end end
                for id, r in pairs(found) do mine.items[id] = r end
                mine.profs[prof] = time()
                ns.LevelDirty()
                return
            end
        end
        if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillItemLink) then return end
        prof = Plain(GetTradeSkillLine and (GetTradeSkillLine()))
        if type(prof) ~= "string" or prof == "" or prof == "UNKNOWN" then return end
        found = {}
        for i = 1, (tonumber(Plain(GetNumTradeSkills())) or 0) do
            local ok, name, kind = pcall(GetTradeSkillInfo, i)
            name, kind = Plain(name), Plain(kind)
            if ok and type(name) == "string" and kind ~= "header" then
                local id = LinkID(GetTradeSkillItemLink(i))
                local what = id and Kind(id)
                if what then
                    local reagents = {}
                    for j = 1, (tonumber(Plain(GetTradeSkillNumReagents and GetTradeSkillNumReagents(i))) or 0) do
                        local rName, _, rCount = GetTradeSkillReagentInfo(i, j)
                        reagents[#reagents + 1] = { id = LinkID(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)),
                            name = Plain(rName), count = tonumber(Plain(rCount)) or 1 }
                    end
                    found[id] = { prof = prof, name = name, kind = what, reagents = reagents }
                end
            end
        end
        for id, r in pairs(mine.items) do if r.prof == prof and not found[id] then mine.items[id] = nil end end
        for id, r in pairs(found) do mine.items[id] = r end
        mine.profs[prof] = time()
        ns.LevelDirty()
    end

    ns.ScanRecipes = Scan

    -- The things you can make for one icon ("tent": tent, campfires, camp features; "food"), not the ones you
    -- already carry. { id, name, count = 0, fire, craft = { prof, can, missing } }, the ones you can make first.
    function ns.CraftOptions(kind, have)
        local list = {}
        local mine = db and db.recipes and db.recipes[CharKey()]
        if not mine then return list end
        for id, r in pairs(mine.items) do
            if (r.kind == kind or (kind == "tent" and r.kind == "fire")) and not (have and have[id]) then
                local can, miss = nil, {}
                for _, g in ipairs(r.reagents or {}) do
                    local n = g.id and ItemCount(g.id) or 0
                    local k = math.floor(n / math.max(1, g.count))
                    can = can and math.min(can, k) or k
                    if n < g.count then miss[#miss + 1] = (g.count - n) .. " " .. (g.name or "?") end
                end
                list[#list + 1] = { id = id, name = r.name or ItemName(id, "?"), count = 0, fire = r.kind == "fire" or nil,
                    craft = { prof = r.prof, can = can or 0, missing = table.concat(miss, ", ") } }
            end
        end
        table.sort(list, function(a, b)
            if (a.craft.can > 0) ~= (b.craft.can > 0) then return a.craft.can > 0 end
            return a.name < b.name
        end)
        return list
    end

    -- Professions you have that WatchX hasn't seen open yet (it can't read recipes before that).
    function ns.UnseenProfessions()
        local out = {}
        local mine = db and db.recipes and db.recipes[CharKey()]
        local want = {}
        for _, p in ipairs(CRAFT_PROFS) do want[p] = true end
        if GetProfessions and GetProfessionInfo then   -- modern
            for _, idx in ipairs({ GetProfessions() }) do
                local ok, name = pcall(GetProfessionInfo, idx)
                name = ok and Plain(name)
                if type(name) == "string" and want[name] and not (mine and mine.profs[name]) then out[#out + 1] = name end
            end
            return out
        end
        if not (GetNumSkillLines and GetSkillLineInfo) then return out end
        for i = 1, (tonumber(Plain(GetNumSkillLines())) or 0) do
            local ok, name, isHeader = pcall(GetSkillLineInfo, i)
            name = ok and Plain(name)
            if type(name) == "string" and not isHeader and want[name] and not (mine and mine.profs[name]) then
                out[#out + 1] = name
            end
        end
        return out
    end

    if CreateFrame then
        local ev = CreateFrame("Frame")
        for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
            pcall(ev.RegisterEvent, ev, e)
        end
        local queued
        ev:SetScript("OnEvent", function()
            if queued or not db then return end
            queued = true
            -- a moment later (the list fills in), and once more for item text that wasn't loaded yet
            C_Timer.After(0.5, function() queued = nil; ns.Safe("recipes", Scan) end)
            C_Timer.After(3, function() ns.Safe("recipes", Scan) end)
        end)
    end
end)()


if CreateFrame then
    local bagEvents = CreateFrame("Frame")
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_ENTERING_WORLD", "TOYS_UPDATED", "UNIT_AURA",
                         "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION" }) do
        pcall(bagEvents.RegisterEvent, bagEvents, e)
    end
    if not pcall(bagEvents.RegisterUnitEvent, bagEvents, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        pcall(bagEvents.RegisterEvent, bagEvents, "UNIT_SPELLCAST_SUCCEEDED")
    end
    bagEvents:SetScript("OnEvent", ns.Timed(function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" and ns.OnCampCast then pcall(ns.OnCampCast, spellID) end
        elseif event == "UNIT_AURA" then
            if unit == "player" then statusCache.dirty = true end
        elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" or event == "PLAYER_LEVEL_UP" then
            statusCache.dirty = true
        else
            -- after a loading screen (an instance, a /reload) the bags can read empty for a moment: wait a little
            if event == "PLAYER_ENTERING_WORLD" then bagState.loadingUntil = GetTime() + 5 end
            bagState.dirty, statusCache.dirty = true, true
        end
    end, "bags & XP events"))
end

-- A campfire close by: a "...Campfire" buff on you, or one you put down here less than 10 minutes ago.
local campFire = {}
local function PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and Plain(map)
    if type(map) ~= "number" then return end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok2 or type(pos) ~= "table" then return end
    local x, y = Plain(pos.x), Plain(pos.y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    return map, x, y
end

function ns.CampFireNear()
    if auraCache.found and auraCache.found.campfire then return true end
    if not campFire.at or GetTime() - campFire.at > 600 then return false end
    local map, x, y = PlayerPos()
    if map and campFire.map and (map ~= campFire.map or math.abs(x - campFire.x) + math.abs(y - campFire.y) > 0.01) then
        return false   -- walked away from it
    end
    return true
end

local fireSpells
local function IsFireSpell(spellID)
    if not fireSpells then
        fireSpells = {}
        local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
        for _, c in ipairs(CAMPFIRES) do
            local ok, name, sid = pcall(get or function() end, c[1])
            name, sid = ok and Plain(name), ok and Plain(sid)
            if type(sid) == "number" then fireSpells[sid] = true end
            if type(name) == "string" then fireSpells[name] = true end
            fireSpells[c[2]] = true
        end
    end
    spellID = Plain(spellID)
    return spellID and (fireSpells[spellID] or fireSpells[SpellName(spellID) or ""]) and true or false
end

-- Seconds since you lit a fire right here (within 10 minutes), or nil.
function ns.CampFireLit()
    if not campFire.at or GetTime() - campFire.at > 600 then return nil end
    if ns.CampFireNear and not ns.CampFireNear() then return nil end
    return GetTime() - campFire.at
end

function ns.OnCampCast(spellID)
    -- the sleeping bag: the stacks come one a minute from now (the meal & camp timer counts them down)
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local ok, bname, bsid = pcall(get or function() end, SLEEPING_BAG)
    local sid = Plain(spellID)
    if ok and sid and (Plain(bsid) == sid or (type(bname) == "string" and SpellName and SpellName(sid) == Plain(bname))) then
        ns.bagStart = GetTime()
        if ns.RefreshEating then ns.Safe("eating timer", ns.RefreshEating) end
    end
    if not IsFireSpell(spellID) then return end
    campFire.at = GetTime()
    campFire.map, campFire.x, campFire.y = PlayerPos()
    statusCache.dirty = true
end

-- Worked out at most once a second (sooner after a change to your buffs, bags or XP, but never more than
-- three times a second): the bars refresh on lots of events, and this used to cost real CPU in a busy city.
local ComputeLevelStatus
function ns.LevelStatus()
    local since = GetTime() - statusCache.at
    if since < 1 and not (statusCache.dirty and since >= 0.3) then return statusCache.rows end
    statusCache.rows = ComputeLevelStatus()
    statusCache.at, statusCache.dirty = GetTime(), false
    return statusCache.rows
end

ComputeLevelStatus = function()
    local level = tonumber(Plain(UnitLevel("player"))) or 0
    if level <= 0 or level >= ns.MaxLevel() then return nil end
    ReadBags()
    if not InCombatLockdown() or not auraCache.found then
        local ok, found = pcall(ReadAuras)
        if ok then auraCache.found, auraCache.at = found, GetTime() end
    end
    local passed = GetTime() - auraCache.at
    local function aura(id)
        local a = auraCache.found and auraCache.found[id]
        if not a then return nil end
        local left = a.left and a.left - passed
        if left and left <= 0 then return nil end
        return { left = left, stacks = a.stacks }
    end
    local rows, seen = {}, {}
    seen.eating = auraCache.found and auraCache.found.eating or nil
    local name, icon, slot, use, options
    local function add(state, text, tip, timer, count)
        rows[#rows + 1] = { state = state, name = name, icon = icon, text = text, tip = tip, timer = timer,
            count = (count and count > 0) and tostring(count) or nil, slot = slot, use = use, options = options }
    end
    local picks = type(db.levelPick) == "table" and db.levelPick or {}
    -- the one you chose (right-click menu) if you still have it, else the first
    local function Pick(key, opts)
        for _, o in ipairs(opts) do if o.id == picks[key] then return o end end
        return opts[1]
    end

    -- Camp Tent (rested itself isn't listed: the XP bar shows it)
    local xpMax = tonumber(Plain(UnitXPMax("player"))) or 0
    local rested = tonumber(Plain(GetXPExhaustion and GetXPExhaustion())) or 0
    local pct = xpMax > 0 and rested / xpMax * 100 or 0
    seen.lowRested = pct < 5
    seen.restedPct = math.floor(pct + 0.5)
    local tentTip = "Light a campfire (Cooking: Simple Wood + Flint and Tinder), put a Camp Tent by it and sit a "
        .. "minute: rested goes up to 5% of a level, for everyone sitting there. Then Boosted Rest blocks another tent "
        .. "for 1 hour. Made with Leatherworking 20 (5 Light Leather) – a friend's tent works too.\n\nRested: kills "
        .. "give double XP until it's spent. It also builds while you're logged out in an inn or a city."
    local boost = aura(BOOSTED_REST)
    local tents = ItemCount(CAMP_TENT)
    seen.boost = boost and true or nil
    name, icon, slot = "Camp Tent", ItemIcon(CAMP_TENT) or SpellIcon(BOOSTED_REST) or "Interface\\Icons\\Spell_Fire_Fire", "tent"
    -- what you carry: campfires, and the camp features (the tent first) – one feature per player per hour
    local fires, feats = {}, {}
    if tents > 0 then feats[1] = { id = CAMP_TENT, name = ItemName(CAMP_TENT, "Camp Tent"), count = tents } end
    for _, c in ipairs(CAMPFIRES) do
        local n = ItemCount(c[1])
        if n > 0 then fires[#fires + 1] = { id = c[1], name = ItemName(c[1], c[2]), count = n, fire = true } end
    end
    for _, c in ipairs(CAMP_FEATURES) do
        local n = ItemCount(c[1])
        if n > 0 then feats[#feats + 1] = { id = c[1], name = ItemName(c[1], c[2]), count = n } end
    end
    for _, e in ipairs(foodCache[5] or {}) do feats[#feats + 1] = { id = e.id, name = e.name, count = e.count } end
    options = {}
    for _, o in ipairs(fires) do options[#options + 1] = o end
    for _, o in ipairs(feats) do options[#options + 1] = o end
    local have, tentCraft = {}, nil
    for _, o in ipairs(options) do have[o.id] = true end
    for _, o in ipairs(ns.CraftOptions and ns.CraftOptions("tent", have) or {}) do
        options[#options + 1] = o
        if o.id == CAMP_TENT then tentCraft = o end
    end
    -- a click puts down the fire first (unless there's one close by), the next click your camp feature
    local fire, feat = Pick("fire", fires), Pick("tent", feats)
    local near = ns.CampFireNear()
    use = (fire and not near) and fire or feat or fire
    if not use and tents == 0 and tentCraft then use = tentCraft end   -- none: make one
    local picks = {}
    if fire then picks[fire.id] = true end
    if feat then picks[feat.id] = true end
    if use and not boost and pct < 5 then icon = ItemIcon(use.id) or icon end
    local how = ""
    if use and use.fire and feat then how = " Click: " .. use.name .. " first, then click again for " .. feat.name .. "."
    elseif use and use.fire then how = " Click: " .. use.name .. " (you have no tent)."
    elseif use and use.craft then
        how = " You can make one with " .. use.craft.prof .. (use.craft.can > 0 and (" (reagents for " .. use.craft.can .. ")")
            or (use.craft.missing ~= "" and (" – missing " .. use.craft.missing) or "")) .. ". Click: open " .. use.craft.prof .. "."
    elseif use then how = " Click: " .. use.name .. (near and " (there's a campfire close by)." or ".") end
    if boost then
        add("wait", "Boosted Rest – you can use another tent when it's gone.", tentTip, boost.left)
    elseif pct < 5 then
        add("todo", "Your rested is under 5%." .. ((tents > 0 or (use and use.craft)) and how or " You have no Camp Tent."), tentTip, nil, tents)
    else
        add("ok", ("Not needed – you have %d%% rested."):format(math.floor(pct + 0.5)) .. how, tentTip)
    end
    rows[#rows].picks, rows[#rows].fireNear = picks, near

    -- Well Fed, and XP food in your bags
    local food, foodName, foodID, foods = foodCache[1], foodCache[2], foodCache[3], foodCache[4]
    slot, options = "food", {}
    local haveFood = {}
    for _, o in ipairs(foods or {}) do options[#options + 1] = o; haveFood[o.id] = true end
    local cookable = ns.CraftOptions and ns.CraftOptions("food", haveFood) or {}
    for _, o in ipairs(cookable) do options[#options + 1] = o end
    local fpick = Pick("food", options)
    if fpick and fpick.craft and foods and foods[1] then fpick = foods[1] end   -- eat what you have before cooking
    use = fpick
    if fpick then foodName, foodID = fpick.name, fpick.id end
    seen.food, seen.foodName = food, foodName
    local fedTip = "Food that says \"Experience gained from kills is increased by 5%\" gives Well Fed for about "
        .. "15 minutes. Gone when you die; a new dish replaces the old one."
    local fed = aura(WELL_FED)
    seen.fed = fed and true or nil
    local none = food == 0   -- nil: can't tell
    local bagNote = none and "\n|cffff6060No XP food in your bags!|r Cook some, or buy it."
        or (food and food > 0 and ("\nXP food in your bags: " .. food
            .. (#(foods or {}) > 1 and (" (" .. #foods .. " kinds)") or "") .. ".")) or ""
    name = "Well Fed"
    if fed then
        icon = ItemIcon(foodID) or SpellIcon(WELL_FED) or "Interface\\Icons\\Spell_Misc_Food"   -- your food, not the buff
        add((fed.left and fed.left < 120) and "wait" or "ok", "+5% XP from kills." .. bagNote, fedTip, fed.left,
            fpick and fpick.count)
    else
        icon = ItemIcon(foodID) or SpellIcon(WELL_FED) or "Interface\\Icons\\Spell_Misc_Food"
        local cook = none and fpick and fpick.craft
        add("todo", (cook and ("|cffff6060No XP food in your bags|r – you can make " .. fpick.name .. " with " .. cook.prof
                .. (cook.can > 0 and (" (reagents for " .. cook.can .. ")") or (cook.missing ~= "" and (" – missing " .. cook.missing) or ""))
                .. ". Click: open " .. cook.prof .. "."))
            or (none and "|cffff6060No XP food in your bags!|r Cook some, or buy it.")
            or ("Eat " .. (foodName or "XP food") .. (fpick and (" (you have " .. fpick.count .. ").") or ".")),
            fedTip, nil, fpick and not fpick.craft and fpick.count or nil)
    end

    -- Cozy Sleeping Bag
    local bagTip = "Lie on the Cozy Sleeping Bag: Well-Rested, +1% XP for each minute, up to +3%. Once an hour; it "
        .. "stays when you die. Party members can use yours."
    local wr = aura(WELL_RESTED)
    seen.rested = wr and true or nil
    seen.restedStacks = wr and wr.stacks or 0
    name, icon, slot = "Cozy Sleeping Bag", ItemIcon(SLEEPING_BAG) or SpellIcon(WELL_RESTED) or "Interface\\Icons\\Spell_Nature_Sleep", "bag"
    local bags, toy = ItemCount(SLEEPING_BAG)
    options = {}
    if bags > 0 then options[1] = { id = SLEEPING_BAG, name = ItemName(SLEEPING_BAG, "Cozy Sleeping Bag"), count = bags, toy = toy } end
    use = options[1]
    if wr then
        local st = math.max(1, math.min(3, wr.stacks))
        icon = ItemIcon(SLEEPING_BAG) or SpellIcon(WELL_RESTED) or icon   -- the bag, not the buff
        add(st >= 3 and "ok" or "wait", ("Well-Rested %d/3: +%d%% XP."):format(st, st)
            .. (st < 3 and " Keep lying on the bag for the full +3%." or ""), bagTip, wr.left, st)
    elseif bags > 0 then
        local cd = ItemCooldownLeft(SLEEPING_BAG)
        seen.bagCd = cd > 0 or nil
        if cd > 0 then add("wait", "On cooldown – ready again when the clock runs out.", bagTip, cd)
        else add("todo", "Ready – lie on it for 3 minutes.", bagTip) end
    elseif level >= 14 then
        add("info", "You don't have one yet – a quest chain from level 14.", bagTip .. "\n\nThe chain starts at Alexston "
            .. "Farmstead in Westfall (Alliance) or the Burned-Out Remains in the Barrens (Horde).")
    end
    CheckBoosts(seen)
    return rows
end

-- ---------------------------------------------------------------- buff warnings
-- A warning (mid-screen, sound, chat) shortly before a buff you care about runs out, and when it has. What to
-- watch: ready-made groups (underwater breathing, potions/elixirs/flasks, your own buffs, buffs from others) and
-- your own list of names or spell IDs. Your auras are hidden in combat on Forever, so they're read out of
-- combat; in a fight it goes by the clock (a buff renewed mid-fight is seen again afterwards).
local BREATH = { ["water breathing"] = true, ["unending breath"] = true, ["underwater breathing"] = true,
    ["greater water breathing"] = true, ["elixir of water breathing"] = true }
local buffTracked = {}   -- lower-case name -> { name, expires, dur, group, soon }

local function ReadBuffs()
    local out = {}
    for i = 1, 40 do
        local name, icon, dur, expires, caster, sid
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            name, icon, dur, expires, caster, sid = a.name, a.icon, a.duration, a.expirationTime, a.sourceUnit, a.spellId
        elseif UnitAura then
            local ok, n, ic, _, _, d, e, c, _, _, sp = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok or n == nil then break end
            name, icon, dur, expires, caster, sid = n, ic, d, e, c, sp
        else
            break
        end
        name, caster = Plain(name), Plain(caster)
        if type(name) == "string" and name ~= "" then
            out[#out + 1] = { name = name, icon = Plain(icon), dur = tonumber(Plain(dur)) or 0,
                expires = tonumber(Plain(expires)) or 0, caster = type(caster) == "string" and caster or nil,
                sid = tonumber(Plain(sid)) }
        end
    end
    return out
end
ns.ReadBuffs = function() local ok, l = pcall(ReadBuffs) return ok and l or {} end

local function KnownSpell(sid)
    if not sid then return false end
    for _, f in ipairs({ IsPlayerSpell or false, IsSpellKnown or false }) do
        if f then
            local ok, yes = pcall(f, sid)
            if ok and Plain(yes) == true then return true end
        end
    end
    return false
end

-- Is it on your own list? (by name, any case, or spell ID)
function ns.BuffOnList(name, sid)
    local l = type(name) == "string" and name:lower()
    for i, c in ipairs(db.buffCustom or {}) do
        if (tonumber(c) and tonumber(c) == sid) or (type(c) == "string" and c:lower() == l) then return i end
    end
end

-- Which group a buff is watched by, or nil.
function ns.BuffGroup(a)
    if ns.BuffOnList(a.name, a.sid) then return "custom" end
    local g, l = db.buffGroups or {}, a.name:lower()
    if BREATH[l] then return g.breath ~= false and "breath" or nil end
    if (a.dur or 0) <= 0 then return nil end
    -- the XP boosts warn about these themselves (below max level)
    if AURA_NAMES[a.sid] or a.name == "Well Fed" or a.name == "Well-Rested" or a.name == "Boosted Rest" then
        if db.levelWarn ~= false and ns.LevelStatus and (tonumber(Plain(UnitLevel("player"))) or 0) < ns.MaxLevel() then
            return nil
        end
    end
    if a.caster == "player" then
        if not KnownSpell(a.sid) then   -- not a spell of yours: it came from your bags
            return (g.consumables ~= false and a.dur >= 60) and "consumables" or nil
        end
        return (g.own == true and a.dur >= 300) and "own" or nil
    end
    return (g.others == true and a.dur >= 300) and "others" or nil
end

local function BuffMsg(t, left)
    local surface = t.group == "breath" and IsSwimming and Plain(IsSwimming()) == true
    if left then
        return t.name .. " runs out in " .. Clock(left) .. (surface and " – head for air!" or "!")
    end
    return t.name .. " has run out!" .. (surface and " Get to the surface!" or "")
end

-- A buff that's gone at its time waits a few seconds before the warning: camp buffs (Welcoming Campfire and
-- the camp features) end and come straight back while you sit by the fire. One that comes back like that renews
-- by itself: no "runs out in" warnings for it this session.
local BUFF_GRACE = 6
local buffPendingGone, buffSelfRenew = {}, {}

local function BuffGoneNow(k, t, now)
    buffTracked[k] = nil
    buffPendingGone[k] = { t = t, at = now }
end

function ns.CheckBuffs()
    if db.buffWarn == false then wipe(buffTracked); wipe(buffPendingGone) return end
    if Plain(UnitIsDeadOrGhost("player")) == true then wipe(buffTracked); wipe(buffPendingGone) return end   -- dying took them
    local now, soon = GetTime(), tonumber(db.buffSoon) or 60
    local fight = InCombatLockdown()
    if not fight then
        local ok, list = pcall(ReadBuffs)
        if ok then
            local here = {}
            for _, a in ipairs(list) do
                local g = a.expires > 0 and ns.BuffGroup(a)
                if g then
                    local k = a.name:lower()
                    here[k] = true
                    if buffPendingGone[k] then   -- back again within a few seconds: it renews by itself
                        buffPendingGone[k] = nil
                        buffSelfRenew[k] = true
                    end
                    local t = buffTracked[k]
                    if not t or a.expires > t.expires + 1 then   -- new, or renewed
                        buffTracked[k] = { name = a.name, expires = a.expires, dur = a.dur, group = g }
                    else
                        t.group = g
                    end
                end
            end
            for k, t in pairs(buffTracked) do
                if not here[k] then
                    -- gone at its time: it ran out (maybe). Gone early: clicked off, dispelled or zoned – no warning.
                    if now >= t.expires - 3 then BuffGoneNow(k, t, now) else buffTracked[k] = nil end
                end
            end
        end
    end
    for k, t in pairs(buffTracked) do
        local left = t.expires - now
        if left <= 0 then
            if fight then BuffGoneNow(k, t, now) end   -- can't see it in a fight: by the clock it's gone
        elseif not t.soon and soon > 0 and left <= soon and t.dur > soon + 5 and not buffSelfRenew[k] then
            t.soon = true
            if not ns.QuietHere() then Warn(BuffMsg(t, left)) end
        end
    end
    for k, p in pairs(buffPendingGone) do
        if now - p.at >= BUFF_GRACE then
            buffPendingGone[k] = nil
            if db.buffGone ~= false and not ns.QuietHere() then Warn(BuffMsg(p.t)) end
        end
    end
end

function ns.AddBuffWatch(text)
    text = ns.Trim(tostring(text or ""))
    if text == "" then return end
    db.buffCustom = db.buffCustom or {}
    local id = tonumber(text)
    if ns.BuffOnList(text, id) then Print(text .. " is already on your buff list.") return end
    db.buffCustom[#db.buffCustom + 1] = id or text
    Print("Buff warnings: " .. (id and (SpellName(id) or ("spell " .. id)) or text) .. " added.")
end

function ns.RemoveBuffWatch(i)
    if db.buffCustom and db.buffCustom[i] then table.remove(db.buffCustom, i) end
end

-- ---------------------------------------------------------------- avoid list
-- People you don't want to play with (ninja looters, and worse): a mark on the same player records as KOS and
-- notes (db.enemies – the Nearby history), so the note is the one you already have. Shared by all characters.
-- Shown in their tooltip and the Nearby list, a warning when one of them invites you or is in your group, and a
-- red [Avoid] before their chat lines. Names are "First Last"; just "First" matches anyone called that.
local avoidIndex   -- lower-case key -> key, rebuilt when the list changes
local function AvoidIndex()
    if not avoidIndex then
        avoidIndex = {}
        for k, r in pairs(db.enemies) do if r.avoid then avoidIndex[k:lower()] = k end end
    end
    return avoidIndex
end
function ns.AvoidChanged() avoidIndex = nil end

-- The record for a name/key ("Shixa-Nightblade", "Shixa Nightblade" or "Shixa") if it's on the list, and its key.
function ns.Avoided(name)
    if type(name) ~= "string" or not db then return nil end
    local idx = AvoidIndex()
    if not next(idx) then return nil end
    local k = Trim(name):gsub("%s+", "-"):lower()
    local key = idx[k] or idx[(k:match("^([^%-]+)"))]
    return key and db.enemies[key], key
end

-- On (or off) the list; a note is kept with the player like any other note.
function ns.SetAvoid(name, on, note)
    local key = ns.KeyFromName(name)
    if not key then return end
    local r = ns.EnemyRecord(key, not db.enemies[key] and Trim(name):gsub("%-", " ") or nil)
    r.avoid = on and true or nil
    note = Trim(note or "")
    if note ~= "" then r.note = note end
    ns.AvoidChanged()
    Print(on and ("|cffff8040Avoid|r: " .. r.name .. (r.note and (" – " .. r.note) or ""))
        or ("No longer on your avoid list: " .. r.name))
    Refresh()
    return key
end

function ns.AvoidLine(r)
    return "|cffff8040WatchX: Avoid|r" .. (r.note and ("|cffffb080 – " .. r.note .. "|r") or "")
end

-- 2.9.0 kept the list on its own: move it onto the player records.
function ns.MigrateAvoid()
    if type(db.avoid) ~= "table" then db.avoid = nil return end
    for _, e in pairs(db.avoid) do
        if type(e) == "table" and e.name then
            local key = ns.KeyFromName(e.name)
            local r = ns.EnemyRecord(key, not db.enemies[key] and e.name or nil)
            r.avoid = true
            r.note = r.note or e.note
        end
    end
    db.avoid = nil
    ns.AvoidChanged()
end

-- In your group, or an invite: one warning per player while you're in the group.
local avoidWarned = {}
local function AvoidWarn(r, what)
    Warn("Avoid list: " .. (r.name or "?") .. " " .. what .. (r.note and (" – " .. r.note) or ""))
end

local function CheckGroup()
    if db.avoidGroup == false or not next(AvoidIndex()) then return end
    local raid = Plain(IsInRaid and IsInRaid()) == true
    local n = raid and (tonumber(Plain(GetNumGroupMembers())) or 0) or 4
    if not raid and Plain(IsInGroup and IsInGroup()) ~= true then wipe(avoidWarned) return end
    local here = {}
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if Plain(UnitExists(unit)) == true then
            local key = PlayerKey(unit)
            local e = key and ns.Avoided(key)
            if e then
                here[key] = true
                if not avoidWarned[key] then
                    avoidWarned[key] = true
                    AvoidWarn(e, "is in your group")
                end
            end
        end
    end
    for k in pairs(avoidWarned) do if not here[k] then avoidWarned[k] = nil end end
end

-- Their chat lines get a red [Avoid] in front (say, yell, whispers, channels, group, guild).
local function AvoidChatFilter(_, _, msg, author, ...)
    if db and db.avoidChat ~= false and next(AvoidIndex()) then
        local ok, e = pcall(function()
            local a, m = Plain(author), Plain(msg)
            if type(a) ~= "string" or type(m) ~= "string" then return nil end
            return ns.Avoided(a)
        end)
        if ok and e then return false, "|cffff4040[Avoid]|r " .. msg, author, ... end
    end
    return false, msg, author, ...
end

if CreateFrame then
    local avoidEvents = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_INVITE_REQUEST", "PLAYER_ENTERING_WORLD" }) do
        pcall(avoidEvents.RegisterEvent, avoidEvents, e)
    end
    avoidEvents:SetScript("OnEvent", function(_, event, who)
        if not db then return end
        if event == "PARTY_INVITE_REQUEST" then
            ns.Safe("avoid list", function()
                local e = db.avoidGroup ~= false and ns.Avoided(Plain(who))
                if e then AvoidWarn(e, "invited you to a group") end
            end)
        else
            ns.Safe("avoid list", CheckGroup)
        end
    end)
    if ChatFrame_AddMessageEventFilter then
        for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_PARTY",
                             "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD",
                             "CHAT_MSG_EMOTE", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
            pcall(ChatFrame_AddMessageEventFilter, e, AvoidChatFilter)
        end
    end
end

-- ---------------------------------------------------------------- WANTED: bounties shared with guild and friends
-- Put a bounty (a reward and a note) on a player. It's sent to your guild and your online friends who run
-- WatchX, and theirs to you: the player gets a WANTED tag in Nearby, History and the tooltip, and a card
-- when he shows up. A kill by you or your group claims it, and everyone hears who did. The gold itself is
-- paid by mail: at a mailbox WatchX fills in the claimer, a subject and the gold, you press Send, and it's PAID for
-- everyone. Stored on the History records (r.wanted = { copper, note, by, t, claimed = { by, full, t }, paid }).
-- Its own function: the main chunk is at Lua's 200-locals limit.
(function()
    local PREFIX, VER, SEP = "WatchX", "W1", "~"
    local MAX_REWARD, MAX_NOTE = 24, 100
    local OPEN_DAYS, CLAIMED_DAYS = 14, 3

    local function Clean(s, n)
        s = Trim((tostring(s or "")):gsub("[%c|~]", " "))
        if s == "" then return nil end
        return s:sub(1, n)
    end
    local function Me()
        local n = Plain(UnitName("player"))
        return type(n) == "string" and n or "?"
    end
    local function On() return db and db.wantedOn ~= false end
    -- Your name as mail takes it: "First-Surname" when the game gives a surname.
    local function MyFull()
        local n, r = UnitName("player")
        n, r = Plain(n), Plain(r)
        if type(n) ~= "string" then return Me() end
        if type(r) == "string" and r ~= "" then return n .. "-" .. r end
        return n
    end

    -- Money: rewards are copper (shown with coin icons); old ones may still be plain text.
    local function Money(c)
        c = math.floor(tonumber(c) or 0)
        if GetCoinTextureString then
            local ok, str = pcall(GetCoinTextureString, c)
            if ok and type(str) == "string" and str ~= "" then return str end
        end
        local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
        local t = {}
        if g > 0 then t[#t + 1] = g .. "g" end
        if sv > 0 then t[#t + 1] = sv .. "s" end
        if cp > 0 or #t == 0 then t[#t + 1] = cp .. "c" end
        return table.concat(t, " ")
    end
    ns.Money = Money
    local UNITS = { g = 10000, gold = 10000, s = 100, silver = 100, c = 1, copper = 1 }
    -- "50g 20s ninja looter" -> 502000, "ninja looter"
    function ns.ParseMoney(text)
        local total, rest = 0, text or ""
        while true do
            local n, unit, after = rest:match("^%s*(%d+)%s*(%a+)(.*)$")
            local mult = unit and UNITS[unit:lower()]
            if not mult then break end
            total, rest = total + tonumber(n) * mult, after
        end
        return total, Trim(rest)
    end
    function ns.WantedReward(w)
        if not w then return nil end
        if w.copper and w.copper > 0 then return Money(w.copper) end
        return w.reward
    end

    -- The bounty on this player (still open), or nil. A bounty on just a first name ("Bob") counts for any Bob.
    function ns.Wanted(key)
        if not (key and db and On()) then return end
        local r = db.enemies[key]
        local w = r and r.wanted
        if w and not w.claimed then return w, r end
        local first = key:match("^([^%-]+)%-")
        local fr = first and db.enemies[first]
        if fr and fr.wanted and not fr.wanted.claimed then return fr.wanted, fr, first end
    end
    -- A line for tooltips and lists.
    function ns.WantedLine(w)
        if not w then return "" end
        local rw = ns.WantedReward(w)
        local s = "|cffffa000WANTED|r" .. (rw and (" |cffffd100" .. rw .. "|r") or "")
            .. (w.by and ("|cffaaaaaa by " .. w.by .. "|r") or "") .. (w.note and (" – " .. w.note) or "")
        if w.claimed then
            local mine, byMe = ns.WantedMine(w), w.claimed.by == Me()
            s = s .. "  |cff40ff40claimed by " .. (byMe and "you" or (w.claimed.by or "?")) .. "|r"
            if w.paid then s = s .. "  |cff40ff40· paid|r"
            elseif mine then s = s .. "  |cffff8040· you owe " .. (rw or "?") .. " – pay at a mailbox|r"
            elseif byMe then s = s .. "  |cffffd100· " .. (w.by or "?") .. " owes you " .. (rw or "?") .. "|r"
            else s = s .. "  |cffaaaaaa· not paid yet|r" end
        end
        return s
    end

    -- Bounty news: a card like the stealth one (and a chat line); the plain mid-screen warning if there's no card.
    local function Card(kind, who, reward, from, msg, class)
        if ns.BountyCard and ns.BountyCard(kind, who, reward, from, class) then Print("|cffffa000" .. msg .. "|r")
        else Warn(msg) end
    end

    -- The whole story, for tooltips: posted (by, when, reward, note), claimed (who, when, where), paid.
    local function Ago(t)
        local d = math.max(0, time() - (t or time()))
        if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
        if d < 86400 then return math.floor(d / 3600) .. " h ago" end
        return math.floor(d / 86400) .. " d ago"
    end
    function ns.AddWantedLines(tip, w)
        if not (tip and w) then return end
        local rw = ns.WantedReward(w) or "?"
        tip:AddLine(" ")
        tip:AddDoubleLine("|cffffa000WANTED|r " .. rw, (w.by == Me() and "by you" or ("by " .. (w.by or "?"))) .. ", " .. Ago(w.t), 1, 1, 1, 0.7, 0.7, 0.7)
        if not w.claimed then
            tip:AddLine(w.forever and "No end date – until it's claimed or taken down"
                or ("Ends in " .. math.max(0, math.ceil(((w.t or time()) + OPEN_DAYS * 86400 - time()) / 86400)) .. " days if nobody claims it"), 0.6, 0.6, 0.6)
        end
        if w.note then tip:AddLine("\"" .. w.note .. "\"", 1, 0.85, 0.5, true) end
        local c = w.claimed
        if c then
            tip:AddDoubleLine("|cff40ff40Killed by " .. (c.by == Me() and "you" or (c.by or "?")) .. "|r", Ago(c.t), 1, 1, 1, 0.7, 0.7, 0.7)
            if c.zone then tip:AddLine("in " .. c.zone, 0.7, 0.7, 0.7) end
            if c.t then tip:AddLine(date("%d.%m %H:%M", c.t), 0.5, 0.5, 0.5) end
            if w.paid then tip:AddDoubleLine("|cff40ff40Paid|r", Ago(w.paid), 1, 1, 1, 0.7, 0.7, 0.7)
            elseif ns.WantedMine(w) then tip:AddLine("You owe " .. rw .. " – a Pay button shows at the mailbox.", 1, 0.5, 0.25, true)
            elseif c.by == Me() then tip:AddLine((w.by or "?") .. " owes you " .. rw .. ".", 1, 0.82, 0, true)
            else tip:AddLine("Not paid yet.", 0.7, 0.7, 0.7) end
        end
    end

    -- Sending: one message every 0.3 s (the game drops a burst), to the guild and to each online friend.
    local queue, sender = {}, CreateFrame("Frame")
    local wait = 0
    sender:Hide()
    sender:SetScript("OnUpdate", ns.Timed(function(self, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        local m = table.remove(queue, 1)
        if not m then self:Hide() return end
        wait = 0.3
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, m[1], m[2], m[3])
    end, "WANTED sending"))
    local friends = {}   -- lower-case name -> true (online friends, rebuilt when sending)
    local function Friends()
        wipe(friends)
        local list = {}
        if not (C_FriendList and C_FriendList.GetNumFriends) then return list end
        for i = 1, (Plain(C_FriendList.GetNumFriends()) or 0) do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            local name = ok and info and Plain(info.name)
            if type(name) == "string" and name ~= "" then
                friends[name:lower()] = true
                friends[(name:match("^[^%-]+") or name):lower()] = true
                if Plain(info.connected) == true then list[#list + 1] = name end
            end
        end
        return list
    end
    local function Send(...)
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
        local msg = table.concat({ VER, ... }, SEP)
        if #msg > 250 then msg = msg:sub(1, 250) end
        if db.wantedGuild ~= false and Plain(IsInGuild and IsInGuild()) == true then queue[#queue + 1] = { msg, "GUILD" } end
        if db.wantedFriends ~= false then
            for _, name in ipairs(Friends()) do queue[#queue + 1] = { msg, "WHISPER", name } end
        end
        sender:Show()
    end
    local recent = {}   -- key..t -> time it was last sent or heard (no echo storms when syncing)
    local function SendAdd(key, r)
        local w = r.wanted
        recent[key .. (w.t or 0)] = time()
        Send("A", key, r.name or key, r.class or "", (w.copper and tostring(w.copper)) or w.reward or "", w.note or "", w.by or "", w.t or 0,
            w.claimed and w.claimed.by or "", w.claimed and w.claimed.t or 0, w.claimed and w.claimed.full or "", w.paid and 1 or 0,
            w.claimed and w.claimed.zone or "", w.forever and 1 or 0)
    end

    -- reward: copper, or text like "50g 20s"; a bounty needs one. forever: no end date (stays until claimed or
    -- taken down).
    function ns.SetWanted(key, name, reward, note, forever)
        if not key then return false end
        local copper = type(reward) == "number" and math.floor(reward) or ns.ParseMoney(tostring(reward or ""))
        if not copper or copper <= 0 then
            Print("A bounty needs a reward: gold, silver or copper (e.g. |cffffd100/wx wanted Name: 50g ninja looter|r).")
            return false
        end
        local old = db.enemies[key] and db.enemies[key].wanted
        if old and not old.claimed and not ns.WantedMine(old) then
            Print((old.by or "Someone") .. " already has a bounty on " .. (db.enemies[key].name or key) .. " – only they can change it.")
            return false
        end
        local r = ns.EnemyRecord(key, name)
        r.wanted = { copper = copper, note = Clean(note, MAX_NOTE), by = Me(), t = time(), forever = forever and true or nil }
        r.wantedHide = nil
        SendAdd(key, r)
        Print("|cffffa000WANTED|r posted: " .. r.name .. " – " .. Money(copper)
            .. (r.wanted.note and (" (" .. r.wanted.note .. ")") or "") .. " |cffaaaaaa– sent to your guild and friends|r")
        if ns.RefreshUI then ns.RefreshUI() end; if ns.RefreshHistory then ns.RefreshHistory() end
        return true
    end

    ns.MyName = Me

    -- Is this bounty yours? Only the one who put it up can change it or take it down.
    function ns.WantedMine(w) return w and (w.by == nil or w.by == Me()) end

    -- Your own bounty: taken down for everyone. Someone else's can't be (it goes when it's claimed or old).
    function ns.RemoveWanted(key)
        local r = key and db.enemies[key]
        if not (r and r.wanted) then return end
        local w = r.wanted
        if not ns.WantedMine(w) then
            Print("Only " .. (w.by or "the one who put it up") .. " can take this bounty down.")
            return false
        end
        Send("D", key, w.by or Me(), w.t or 0)
        r.wanted = nil
        -- only here for the bounty (never seen, nothing else on it): gone from History too
        if not (r.kos or r.avoid or r.note or (r.seen or 0) > 0 or (r.kills or 0) > 0 or (r.deaths or 0) > 0) and not r.wantedHide then
            db.enemies[key] = nil
        end
        Print("Bounty taken down: " .. (r.name or key))
        if ns.RefreshUI then ns.RefreshUI() end; if ns.RefreshHistory then ns.RefreshHistory() end
    end

    -- A kill by you or your group (ns.OnPlayerKill): the bounty is yours.
    function ns.OnWantedKill(key)
        local w, r, held = ns.Wanted(key)
        if not w then return end
        key = held or key
        local zone = Plain(GetZoneText and GetZoneText())
        local sub = Plain(GetSubZoneText and GetSubZoneText())
        zone = type(zone) == "string" and zone ~= "" and zone or nil
        if zone and type(sub) == "string" and sub ~= "" and sub ~= zone then zone = sub .. ", " .. zone end
        w.claimed = { by = Me(), full = MyFull(), t = time(), zone = zone }
        Send("C", key, w.claimed.by, w.claimed.t, w.t or 0, w.claimed.full, zone or "")
        Card("bountyKill", r.name or key, ns.WantedReward(w), (w.by and w.by ~= Me()) and ("from " .. w.by) or "yours",
            "Bounty claimed: " .. (r.name or key) .. (zone and (" in " .. zone) or "") .. (ns.WantedReward(w) and (" – " .. ns.WantedReward(w)) or "")
            .. ((w.by and w.by ~= Me()) and (" from " .. w.by .. " (they pay by mail)") or ""), r.class)
        if ns.RefreshHistory then ns.RefreshHistory() end
    end

    -- Paid (by mail, or "Mark paid" after a trade): only the one who put it up.
    function ns.MarkPaid(key)
        local r = key and db.enemies[key]
        local w = r and r.wanted
        if not (w and w.claimed and not w.paid and ns.WantedMine(w)) then return false end
        w.paid = time()
        Send("P", key, w.by or Me(), w.t or 0)
        Print("|cff40ff40Bounty paid|r: " .. (w.claimed.by or "?") .. " got " .. (ns.WantedReward(w) or "it") .. " for " .. (r.name or key) .. ".")
        if ns.RefreshUI then ns.RefreshUI() end; if ns.RefreshHistory then ns.RefreshHistory() end
        return true
    end
    -- The bounties others owe you (you claimed them, not paid yet): { key, r, w }.
    function ns.OwedToMe()
        local out = {}
        for key, r in pairs(db and db.enemies or {}) do
            local w = r.wanted
            if w and w.claimed and not w.paid and w.claimed.by == Me() and not ns.WantedMine(w) then out[#out + 1] = { key = key, r = r, w = w } end
        end
        return out
    end
    -- The claimed bounties you still owe: { key, r, w }.
    function ns.OwedBounties()
        local out = {}
        for key, r in pairs(db and db.enemies or {}) do
            local w = r.wanted
            if w and w.claimed and not w.paid and ns.WantedMine(w) and w.claimed.by ~= Me() then out[#out + 1] = { key = key, r = r, w = w } end
        end
        table.sort(out, function(a, b) return (a.w.claimed.t or 0) < (b.w.claimed.t or 0) end)
        return out
    end

    local function Apply(op, f, from)
        local key = f[1]
        if type(key) ~= "string" or key == "" or #key > 60 then return end
        local tt = tonumber
        if op == "A" then
            local t = tt(f[7]) or 0
            local forever = f[13] == "1"
            if t <= 0 or (not forever and time() - t > OPEN_DAYS * 86400) then return end
            local r = db.enemies[key]
            if r and ((r.wanted and (r.wanted.t or 0) >= t) or (r.wantedHide and r.wantedHide >= t)) then
                -- known; a claim or a payment we missed still counts
                if r.wanted and (r.wanted.t or 0) == t then
                    if not r.wanted.claimed and f[8] and f[8] ~= "" then
                        r.wanted.claimed = { by = Clean(f[8], 40), t = tt(f[9]) or t, full = Clean(f[10], 60), zone = Clean(f[12], 60) }
                    end
                    if r.wanted.claimed and not r.wanted.paid and f[11] == "1" then r.wanted.paid = time() end
                end
                recent[key .. t] = time()
                return
            end
            r = ns.EnemyRecord(key, Clean(f[2], 60))
            if (not r.class) and f[3] ~= "" then r.class = Clean(f[3], 20) end
            local cp = (f[4] or ""):match("^%d+$") and tonumber(f[4]) or nil
            r.wanted = { copper = cp, reward = (not cp) and Clean(f[4], MAX_REWARD) or nil, note = Clean(f[5], MAX_NOTE),
                by = Clean(f[6], 40) or from, t = t, forever = forever or nil }
            if f[8] and f[8] ~= "" then r.wanted.claimed = { by = Clean(f[8], 40), t = tt(f[9]) or t, full = Clean(f[10], 60), zone = Clean(f[12], 60) } end
            if r.wanted.claimed and f[11] == "1" then r.wanted.paid = time() end
            recent[key .. t] = time()
            if time() - t < 600 and not r.wanted.claimed then
                Card("bountyNew", r.name or key, ns.WantedReward(r.wanted), "from " .. (r.wanted.by or "?"),
                    "WANTED from " .. (r.wanted.by or "?") .. ": " .. (r.name or key)
                    .. (ns.WantedReward(r.wanted) and (" – " .. ns.WantedReward(r.wanted)) or "") .. (r.wanted.note and (" (" .. r.wanted.note .. ")") or ""), r.class)
            end
        elseif op == "D" then
            local r = db.enemies[key]
            if r and r.wanted and r.wanted.by == Clean(f[2], 40) and (tt(f[3]) or 0) >= (r.wanted.t or 0) then
                r.wanted = nil
            end
        elseif op == "C" then
            local r = db.enemies[key]
            local w = r and r.wanted
            if w and not w.claimed and (tt(f[4]) or 0) == (w.t or 0) then
                w.claimed = { by = Clean(f[2], 40) or from, t = tt(f[3]) or time(), full = Clean(f[5], 60), zone = Clean(f[6], 60) }
                local where = w.claimed.zone and (" in " .. w.claimed.zone) or ""
                if ns.WantedMine(w) then
                    Card("bountyOwe", r.name or key, ns.WantedReward(w), "to " .. w.claimed.by,
                        w.claimed.by .. " killed " .. (r.name or key) .. where .. " and claimed your bounty – you owe "
                        .. (ns.WantedReward(w) or "the reward") .. ". Pay it at a mailbox.", r.class)
                else
                    Card("bountyKill", r.name or key, ns.WantedReward(w), "by " .. w.claimed.by,
                        "Bounty claimed: " .. (r.name or key) .. " by " .. w.claimed.by .. where
                        .. (ns.WantedReward(w) and (" – " .. ns.WantedReward(w)) or "") .. (w.by and (", from " .. w.by) or ""), r.class)
                end
            end
        elseif op == "P" then
            local r = db.enemies[key]
            local w = r and r.wanted
            if w and w.claimed and not w.paid and w.by == Clean(f[2], 40) and (tt(f[3]) or 0) == (w.t or 0) then
                w.paid = time()
                if w.claimed.by == Me() then
                    Card("bountyPaid", r.name or key, ns.WantedReward(w), "from " .. (w.by or "?"),
                        (w.by or "?") .. " paid you " .. (ns.WantedReward(w) or "the bounty") .. " for " .. (r.name or key) .. " – check your mail.", r.class)
                end
            end
        end
        if ns.RefreshUI then ns.RefreshUI() end; if ns.RefreshHistory then ns.RefreshHistory() end
    end

    -- Someone logged in: everyone sends what they know, a few seconds apart, skipping what was just sent.
    local replyAt
    local function Reply()
        replyAt = nil
        local now = time()
        for key, r in pairs(db.enemies) do
            local w = r.wanted
            if w and w.t and not (recent[key .. w.t] and now - recent[key .. w.t] < 60) then SendAdd(key, r) end
        end
    end

    local function OnMessage(prefix, text, channel, from)
        if Plain(prefix) ~= PREFIX or not On() then return end
        text, channel, from = Plain(text), Plain(channel), Plain(from)
        if type(text) ~= "string" or type(from) ~= "string" then return end
        local short = from:match("^[^%-]+") or from
        if short == Me() then return end
        if channel == "WHISPER" then   -- only from your friends
            if not next(friends) then Friends() end
            if not (friends[from:lower()] or friends[short:lower()]) then return end
        elseif channel ~= "GUILD" then
            return
        end
        local f = {}
        for part in (text .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = part end
        if f[1] ~= VER then return end
        local op = table.remove(f, 1) and table.remove(f, 1)
        if op == "H" then
            if not replyAt then
                replyAt = true
                C_Timer.After(2 + math.random() * 4, function() ns.Safe("wanted", Reply) end)
            end
        else
            Apply(op, f, short)
        end
    end

    -- Old ones go: open bounties after two weeks, paid ones after three days, claimed-not-paid after two weeks.
    local function Expire()
        local now = time()
        for _, r in pairs(db.enemies) do
            local w = r.wanted
            if w and ((w.paid and now - w.paid > CLAIMED_DAYS * 86400)
                    or (w.claimed and not w.paid and now - (w.claimed.t or 0) > OPEN_DAYS * 86400)
                    or (not w.claimed and not w.forever and now - (w.t or 0) > OPEN_DAYS * 86400)) then
                r.wanted = nil
            end
        end
    end

    -- Paying by mail: at a mailbox a "Pay bounty" button under the mail window; it fills in the claimer, a subject
    -- and the gold on the Send Mail tab, you press Send yourself. The mail that goes out with that subject and at
    -- least that gold marks it paid. Nothing of Blizzard's is called or changed but the boxes' text.
    local payBtn, pending, sentFor
    local function Subject(key) return "Bounty: " .. ((db.enemies[key] and db.enemies[key].name) or key) end
    local function Fill()
        local o = pending and db.enemies[pending] and db.enemies[pending].wanted
        if not (o and SendMailFrame and SendMailFrame:IsShown()) then return end
        if SendMailNameEditBox then SendMailNameEditBox:SetText(o.claimed.full or o.claimed.by or "") end
        if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(Subject(pending)) end
        if SendMailRadioButton_OnClick then pcall(SendMailRadioButton_OnClick, 1) end   -- send money, not COD
        if SendMailMoney and MoneyInputFrame_SetCopper then pcall(MoneyInputFrame_SetCopper, SendMailMoney, o.copper or 0) end
    end
    local function UpdatePayButton()
        if not (MailFrame and MailFrame:IsShown()) then if payBtn then payBtn:Hide() end return end
        local owed = ns.OwedBounties()
        if #owed == 0 or not On() then if payBtn then payBtn:Hide() end return end
        if not payBtn then
            payBtn = CreateFrame("Button", "WatchXPayBounty", MailFrame, "UIPanelButtonTemplate")
            payBtn:SetSize(300, 24)
            payBtn:SetPoint("TOP", MailFrame, "BOTTOM", 0, -4)
            payBtn:SetScript("OnClick", function(self)
                pending = self.key
                if SendMailFrame and SendMailFrame:IsShown() then Fill()
                else Print("Open the |cffffd100Send Mail|r tab – WatchX fills in the bounty, then press Send.") end
            end)
            if SendMailFrame and SendMailFrame.HookScript then SendMailFrame:HookScript("OnShow", function() ns.Safe("wanted", Fill) end) end
        end
        local o = owed[1]
        payBtn.key = o.key
        payBtn:SetText("Pay bounty: " .. (o.w.claimed.by or "?") .. " – " .. (ns.WantedReward(o.w) or "?")
            .. (#owed > 1 and ("  (+" .. (#owed - 1) .. ")") or ""))
        payBtn:Show()
    end
    if hooksecurefunc and SendMail then
        hooksecurefunc("SendMail", function(_, subject)
            sentFor = nil
            local o = pending and db and db.enemies[pending] and db.enemies[pending].wanted
            local money = GetSendMailMoney and tonumber(Plain(GetSendMailMoney())) or 0
            if o and Plain(subject) == Subject(pending) and money >= (o.copper or 0) then sentFor = pending end
        end)
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:RegisterEvent("FRIENDLIST_UPDATE")
    for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
            C_Timer.After(12, function() ns.Safe("wanted", function()
                if not db then return end
                Expire()
                if On() then
                    Send("H")
                    local owed = ns.OwedBounties()
                    if #owed > 0 then
                        Print("|cffff8040You owe " .. #owed .. (#owed == 1 and " bounty" or " bounties") .. "|r – a Pay button shows at the mailbox.")
                    end
                    local due = ns.OwedToMe()
                    if #due > 0 then
                        local names = {}
                        for i = 1, math.min(3, #due) do names[i] = (due[i].w.by or "?") .. " " .. (ns.WantedReward(due[i].w) or "") end
                        Print("|cffffd100Owed to you:|r " .. table.concat(names, ", ") .. (#due > 3 and (" and " .. (#due - 3) .. " more") or "")
                            .. " |cffaaaaaa(History > Wanted)|r")
                    end
                end
            end) end)
        elseif event == "FRIENDLIST_UPDATE" then
            wipe(friends)
        elseif event == "MAIL_SHOW" or event == "MAIL_CLOSED" then
            if event == "MAIL_CLOSED" then pending = nil end
            ns.Safe("wanted", UpdatePayButton)
        elseif event == "MAIL_SEND_SUCCESS" then
            if sentFor then ns.MarkPaid(sentFor); sentFor, pending = nil, nil end
            ns.Safe("wanted", UpdatePayButton)
        elseif db then
            ns.Safe("wanted", OnMessage, ...)
        end
    end)
end)()

function ns.BuffTest()
    Warn("Water Breathing runs out in 0:30 – head for air!  |cff808080(a test)|r")
end

-- /wx nearby test: a few made-up enemies and a stealth card, to see what it looks like.
function ns.NearbyTest()
    if not db.nearby then ns.SetNearby(true) end
    local now = time()
    for i, ex in ipairs({ { "Example Rogue", "ROGUE", 60 }, { "Example Warrior", "WARRIOR", 58 },
                          { "Example Mage", "MAGE", 60 }, { "Example Druid", "DRUID", -1 } }) do
        local key = ex[1]:gsub(" ", "-")
        ns.nearby[key] = { key = key, name = ex[1], first = ex[1]:match("^%S+"), class = ex[2], level = ex[3],
            firstSeen = now - i * 20, last = (i == 4) and (now - 90) or now, guild = (i == 2) and "Example Guild" or nil,
            example = now + 60 }
    end
    local rogue = ns.nearby["Example-Rogue"]
    rogue.stealth, rogue.stealthHow = now, "Stealth"
    ns.roles["Example-Druid"] = { role = "healer", how = "Wild Growth", at = now }   -- this session only
    Print("Example Nearby list and stealth card shown (made-up names – gone in a minute).")
    if ns.ShowStealthToast then ns.ShowStealthToast(rogue) end
    Refresh()
    if C_Timer then C_Timer.After(61, function() ns.roles["Example-Druid"] = nil; Refresh() end) end
end

function ns.SetNearby(on)
    db.nearby = on and true or false
    Print("Nearby enemies: " .. (db.nearby and "|cff40ff40on|r" or "off"))
    if not db.nearby then wipe(ns.nearby) end
    Refresh()
end

-- Any friendly player, when "Any friendly player" is on. Not in instances, cities or inns (far too
-- many), not yourself or your group, and the same player only once every ENEMY_COOLDOWN seconds.
local function CheckFriendlyPlayer(unit, name, source)
    if ns.IsHostilePlayer(unit) then return end
    if Plain(UnitIsUnit("player", unit)) == true or Plain(UnitIsDead(unit)) == true then return end
    if Plain(UnitInParty(unit)) == true or Plain(UnitInRaid(unit)) then return end
    if (IsInInstance and IsInInstance()) or (IsResting and IsResting()) then return end
    local now = time()
    ns.lastFriend = { name = name, at = now }
    if friendSeen[name] and now - friendSeen[name] < ENEMY_COOLDOWN then return end
    friendSeen[name] = now
    local info = PlayerInfo(unit)
    Log("friend", name, source)
    Alert("FRIEND", name, string.format("Friendly player: %s (%s%s)", name, info ~= "" and (info .. " – ") or "",
        Location()), (info ~= "" and (info .. " · ") or "") .. Location())
end

local function CheckUnit(unit, source)
    if not UnitExists(unit) then return end
    local raw = Plain(UnitName(unit))
    if type(raw) ~= "string" then return end
    if db.nearby and Plain(UnitIsPlayer(unit)) == true and ns.NearbyHere()
        and ns.IsHostilePlayer(unit)
        and Plain(UnitIsDead(unit)) ~= true then
        local key = NoteNearby(unit)
        if key and unit:find("^nameplate") then plateKeys[unit] = key end
    end
    local name = Resolve(raw)
    if name then
        local guid = Plain(UnitGUID(unit))
        if type(guid) == "string" then guidToName[guid] = name end
        OnSeen(name, unit, source)
    elseif Plain(UnitIsPlayer(unit)) == true then
        if db.enemyPlayers then CheckEnemyPlayer(unit, raw, source) end
        if db.friendlyPlayers then CheckFriendlyPlayer(unit, raw, source) end
    end
end

function ns.SetEnemyPlayers(on)
    db.enemyPlayers = on and true or false
    Print("Any enemy player: " .. (db.enemyPlayers and "|cff40ff40on|r" or "off"))
    if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
    Refresh()
end

function ns.SetFriendlyPlayers(on)
    db.friendlyPlayers = on and true or false
    Print("Any friendly player: " .. (db.friendlyPlayers and "|cff40ff40on|r" or "off")
        .. ((db.friendlyPlayers and GetCVar("nameplateShowFriends") ~= "1")
            and " – |cffffd100friendly nameplates are off|r (Shift+V or the yellow bar)." or ""))
    if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
    Refresh()
end

function ns.IsWatchingAnything()
    return next(watchByLower) ~= nil or (db and (db.enemyPlayers or db.friendlyPlayers))
end

-- Enemy nameplates are needed for mobs and enemy players; friendly ones for "Any friendly player".
function ns.NeedsEnemyPlates()
    return next(watchByLower) ~= nil or (db and db.enemyPlayers)
end
function ns.FriendPlatesMissing()
    return db and db.friendlyPlayers and GetCVar("nameplateShowFriends") ~= "1"
end

local function OnGuidDied(guid, source)
    guid = Plain(guid)
    local name = type(guid) == "string" and guidToName[guid]
    if name then
        guidToName[guid] = nil
        OnDeath(name, source)
    end
end

local deathPatterns
local function OnDeathLine(text)
    text = Plain(text)
    if type(text) ~= "string" then return end
    deathPatterns = deathPatterns or { MakePattern(_G.UNITDIESOTHER), MakePattern(_G.SELFKILLOTHER) }
    for _, p in ipairs(deathPatterns) do
        local who = text:match(p)
        local name = who and Resolve(who)
        if name then OnDeath(name, "death message") return end
    end
end

local function ScanNameplates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) or not (ns.IsWatchingAnything() or db.nearby) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates then return end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then CheckUnit(unit, "nameplate") end
    end
end

local function ScanLoot()
    if not next(activeLoot) or time() - lastLootAlert < 60 then return end
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        local hit = id and activeLoot[id]
        if hit then
            lastLootAlert = time()
            Alert("LOOT", hit.item, string.format("%s DROPPED from %s!!!", hit.item:upper(), hit.mob),
                "From " .. hit.mob .. " · " .. Location())
            return
        end
    end
end

-- ---------------------------------------------------------------- AFK logout warning
-- The game marks you AFK after a few idle minutes and logs you out a while later (with a 20 second
-- countdown). WatchX counts from the AFK flag and warns 5 minutes before; the real time is learned
-- from the countdown. The logout itself can't be sent from the game (it has stopped by then): the
-- bridge sees the settings file being written at the logout and reads exitWhy.
local afkSince, afkWarned, campingAfk, exitReason

local function CheckAfk()
    local afk = UnitIsAFK and Plain(UnitIsAFK("player")) == true
    if afk and not afkSince then
        afkSince, afkWarned = time(), false
        Log("afk", "on")
    elseif not afk and afkSince then
        afkSince = nil
        afkEndedAt = time()
        Log("afk", "off")
    end
end

function ns.AfkStatus()   -- seconds until the expected logout, or nil when not AFK
    if not afkSince then return nil end
    return (db.afkLogoutMin or 25) * 60 - (time() - afkSince)
end

local function AfkTick()
    if not (afkSince and db.afkWarn) or afkWarned then return end
    local left = ns.AfkStatus()
    if left <= 5 * 60 then
        afkWarned = true
        Alert("AFK", "AFK logout", "You will be logged out for being AFK in about " .. Fmt(math.max(left, 60))
            .. " – move your character!", "Logged out in about " .. Fmt(math.max(left, 60)) .. " – move your character!")
    end
end

local function OnCamping()
    CheckAfk()
    if not afkSince then return end   -- you logged out yourself
    campingAfk = true
    local min = math.floor((time() - afkSince + 20) / 60 + 0.5)
    if min >= 6 and min <= 90 and min ~= db.afkLogoutMin then
        Log("afk", "logout comes after", min, "min AFK")
        db.afkLogoutMin = min
    end
    if db.afkWarn then
        Alert("LOGOUT", "AFK logout", "Logging out in 20 seconds for being AFK!", "Logging out in 20 seconds – move now!")
    end
end

-- ---------------------------------------------------------------- profiles
-- A profile = what you watch + alert and display choices. The live settings are the active profile;
-- switching stores them and loads the other one. Phone links, timers and the log are shared.
local PROFILE_KEYS = { "enemyPlayers", "friendlyPlayers", "attackAlert", "whisper", "instant", "afkWarn",
    "notifyDeath", "sound", "show", "miniQuiet", "hideIdle", "alertSame", "miniPoint", "miniScale", "miniWidth",
    "alertPoint", "alertScale", "alertWidth", "nearby", "nearbyPoint", "nearbyScale", "nearbyWidth", "toastPoint",
    "stealthWarn", "stealthSound", "nearbyShowEmpty", "nearbyKeep", "newEnemyCard", "warnDock", "nearbyAttach", "nearbyMax", "nearbyNoBG", "nearbyHideDungeon", "nearbyHideRaid",
    "plateIcons", "plateFriendly", "plateHealer", "plateSize", "plateKOS",
    "levelHelper", "levelMissing", "levelFlash", "levelWarn", "levelHideCombat", "levelHideInstance", "levelPoint", "levelScale", "levelWidth",
    "buffWarn", "buffSoon", "buffGone", "buffGroups", "avoidGroup", "avoidChat", "scanOn", "wantedOn", "wantedGuild", "wantedFriends", "wantedAlert" }
local PROFILE_MAX_NAME = 16

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Snapshot()
    local snap = { watch = Copy(db.watch), custom = Copy(db.custom) }
    for _, k in ipairs(PROFILE_KEYS) do snap[k] = Copy(db[k]) end
    return snap
end

local function ApplySnapshot(snap)
    db.watch = Copy(snap.watch or {})
    db.custom = Copy(snap.custom or {})
    for _, k in ipairs(PROFILE_KEYS) do
        db[k] = Copy(snap[k])
        if db[k] == nil and defaults[k] ~= nil then db[k] = Copy(defaults[k]) end
    end
end

-- The first time: three ready-made profiles, all starting from your current choices.
function ns.InitProfiles()
    if type(db.profiles) ~= "table" or not next(db.profiles) then
        local base = Snapshot()
        local leveling = Copy(base)
        leveling.watch = {}                    -- your list stays, switched off
        leveling.enemyPlayers, leveling.attackAlert = true, true
        leveling.miniQuiet, leveling.hideIdle = true, true
        local pvp = Copy(base)
        pvp.enemyPlayers, pvp.attackAlert, pvp.miniQuiet = true, true, false
        db.profiles = { Camping = base, Leveling = leveling, PvP = pvp }
        db.profile = "Camping"
    end
    if not db.profiles[db.profile or ""] then db.profile = ns.ProfileNames()[1] end
end

function ns.ProfileNames()
    local names = {}
    for name in pairs(db.profiles or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local function AfterProfileChange()
    ns.RebuildWatch()
    if ns.ApplyLayout then ns.ApplyLayout() end
    if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
    Refresh()
end

function ns.SwitchProfile(name)
    if not (db.profiles and db.profiles[name]) or name == db.profile then return end
    if db.profile then db.profiles[db.profile] = Snapshot() end
    ApplySnapshot(db.profiles[name])
    db.profile = name
    Print("Profile: |cff38ccad" .. name .. "|r")
    AfterProfileChange()
end

-- A new profile starts as a copy of your current choices. Returns true, or false + why.
function ns.NewProfile(name)
    name = Trim(name or "")
    if name == "" then return false, "Enter a name." end
    if #name > PROFILE_MAX_NAME then return false, "Max " .. PROFILE_MAX_NAME .. " letters." end
    for n in pairs(db.profiles) do
        if n:lower() == name:lower() then return false, "There is already a profile called '" .. n .. "'." end
    end
    if db.profile then db.profiles[db.profile] = Snapshot() end
    db.profiles[name] = Snapshot()
    db.profile = name
    Print("New profile |cff38ccad" .. name .. "|r – a copy of your current settings. Change what you like.")
    Refresh()
    return true
end

function ns.DeleteProfile(name)
    if not db.profiles[name] then return false end
    if #ns.ProfileNames() <= 1 then Print("You need at least one profile.") return false end
    db.profiles[name] = nil
    Print("Deleted the profile '" .. name .. "'.")
    if db.profile == name then
        db.profile = ns.ProfileNames()[1]
        ApplySnapshot(db.profiles[db.profile])
        Print("Profile: |cff38ccad" .. db.profile .. "|r")
        AfterProfileChange()
    else
        Refresh()
    end
    return true
end

function ns.SaveProfile()   -- keeps the active profile up to date (also done at logout)
    if db and db.profiles and db.profile then db.profiles[db.profile] = Snapshot() end
end

-- ---------------------------------------------------------------- attacked
-- Combat starts while you haven't done anything for a while (or are AFK) = something attacked you.
-- Doing something = moving, casting, changing target or moving the mouse (checked every second). Tabbed out,
-- the game sees no mouse, so that still counts as away.
-- (Without the combat log the attacker is found through nameplates: whoever has you targeted.)
local IDLE_FOR = 20          -- seconds without moving, casting, targeting or moving the mouse
local lastActive, lastAttack, afkEndedAt = time(), 0, 0   -- a fresh login counts as active

function ns.MarkActive() lastActive = time() end

local cursorX, cursorY
local function CheckCursor()
    if not GetCursorPosition then return end
    local x, y = GetCursorPosition()
    x, y = Plain(x), Plain(y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    if cursorX and (math.abs(x - cursorX) > 2 or math.abs(y - cursorY) > 2) then lastActive = time() end
    cursorX, cursorY = x, y
end

local function Attacker()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates then return end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and Plain(UnitIsUnit(unit .. "target", "player")) == true
            and Plain(UnitCanAttack("player", unit)) == true then
            local name = Plain(UnitName(unit))
            if type(name) == "string" then
                local lvl = Plain(UnitLevel(unit))
                return name, (type(lvl) == "number" and lvl > 0) and lvl or nil, Plain(UnitIsPlayer(unit)) == true
            end
        end
    end
end

local function OnCombatStart()
    if not db.attackAlert then return end
    local now = time()
    local idle = now - lastActive >= IDLE_FOR
    local afk = afkSince ~= nil or now - afkEndedAt <= 3   -- combat may clear the AFK flag first
    if not (idle or afk) or now - lastAttack < 60 then return end
    lastAttack = now
    C_Timer.After(0.3, function()   -- give the nameplates a moment to show who it is
        local who, lvl, isPlayer = Attacker()
        local hp = ""
        local cur, max = Plain(UnitHealth("player")), Plain(UnitHealthMax("player"))
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            hp = "HP " .. math.floor(cur / max * 100 + 0.5) .. "%"
        end
        local by = who and (who .. (lvl and (" (" .. (isPlayer and "player, " or "") .. lvl .. ")") or "")) or nil
        Log("attacked", who or "?")
        Alert("ATTACK", who or "Something",
            "You are being attacked" .. (by and (" by " .. by) or "") .. "! (" .. Location() .. ")",
            (by and ("By " .. by .. " · ") or "") .. (hp ~= "" and (hp .. " · ") or "") .. Location())
    end)
end

for name, why in pairs({ ReloadUI = "reload", Logout = "logout", Quit = "quit", ForceQuit = "quit" }) do
    if type(_G[name]) == "function" then pcall(hooksecurefunc, name, function() exitReason = why end) end
end
if C_UI and type(C_UI.Reload) == "function" then
    pcall(hooksecurefunc, C_UI, "Reload", function() exitReason = "reload" end)
end

-- Every second: scan nameplates and refresh the UI.
local ticker = CreateFrame("Frame")
local elapsed = 0
local TickWork   -- the once-a-second work (timed); the frame-by-frame part below stays as small as it can be
ticker:SetScript("OnUpdate", function(_, dt)
    if not db then return end
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    TickWork()
end)
TickWork = ns.Timed(function()
    ns.Safe("scan", ScanNameplates)
    ns.Safe("afk", function() CheckCursor(); CheckAfk(); AfkTick() end)
    -- the XP boost warnings also work with the list switched off (the list reads it every second itself)
    if db.levelHelper == false and db.levelWarn ~= false then ns.Safe("xp boosts", ns.LevelStatus) end
    ns.Safe("buffs", ns.CheckBuffs)
    Refresh()
end, "1 s ticker")

-- ---------------------------------------------------------------- events

-- Never COMBAT_LOG_EVENT_*: Forever blocks it for addons.
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
    "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "LOOT_OPENED",
    "UNIT_DIED", "PARTY_KILL", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_SYSTEM",
    "PLAYER_FLAGS_CHANGED", "PLAYER_CAMPING", "PLAYER_LOGOUT",
    "PLAYER_REGEN_DISABLED", "PLAYER_STARTED_MOVING", "UNIT_SPELLCAST_SENT", "PLAYER_ENTER_COMBAT",
    "NAME_PLATE_UNIT_REMOVED", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_DEAD", "INSPECT_READY",
}) do
    pcall(ev.RegisterEvent, ev, e)
end
ns.shotEvents = pcall(ev.RegisterEvent, ev, "SCREENSHOT_SUCCEEDED") and pcall(ev.RegisterEvent, ev, "SCREENSHOT_FAILED")

local function GetVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end
ns.GetVersion = GetVersion

local ACTIVE = { PLAYER_STARTED_MOVING = true, UNIT_SPELLCAST_SENT = true, PLAYER_ENTER_COMBAT = true,
                 PLAYER_TARGET_CHANGED = true, LOOT_OPENED = true }
local function OnEvent(_, event, arg1, arg2, ...)
    if ACTIVE[event] then ns.MarkActive() end   -- you did something: combat now is probably your own
    if event == "PLAYER_STARTED_MOVING" or event == "UNIT_SPELLCAST_SENT" or event == "PLAYER_ENTER_COMBAT" then
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        if db then OnCombatStart() end
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if db and arg1 ~= "player" then   -- unit, castGUID, spellID
            local spellID = (...)
            OnStealthCast(arg1, spellID)
            OnRoleCast(arg1, spellID)
        end
        return
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(arg1) == "string" then ns.roles["plate:" .. arg1] = nil end
        if type(arg1) == "string" and plateKeys[arg1] then
            gonePlates[arg1] = { key = plateKeys[arg1], at = GetTime() }
            plateKeys[arg1] = nil
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        ns.cpuStart, ns.cpu.ms = GetTime(), 0
        WatchXDB = WatchXDB or {}
        db = WatchXDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = type(v) == "table" and CopyTable(v) or v end
        end
        ns.db = db
        db.exitAt, db.exitWhy = nil, nil
        ns.InitProfiles()
        ns.MigrateAvoid()
        for _, r in pairs(db.enemies) do r.healer = nil end   -- 2.3.0 guessed healers from heals; only proof now
        if db.instant ~= false then
            -- the bridge reads the code block from the picture: JPEG at a quality that keeps it sharp
            if GetCVar("screenshotFormat") == "tga" then pcall(SetCVar, "screenshotFormat", "jpeg") end
            if (tonumber(GetCVar("screenshotQuality")) or 10) < 6 then pcall(SetCVar, "screenshotQuality", "6") end
        end
        -- One session per log; the previous one is kept (it is read from disk after a /reload).
        db.previousLog = db.log
        db.log = {}
        Log("session", (GetBuildInfo()), "v" .. GetVersion())
        ns.RebuildWatch()
        HookChatLog()
        if ns.InitUI then ns.InitUI() end

        if GetCVar("nameplateShowEnemies") ~= "1" then
            Print("|cffffd100Enemy nameplates are OFF|r – click the yellow bar or press V, otherwise nothing can be spotted.")
        end
        if db.ntfyUrl == "" and db.discordWebhook == "" then
            Print("Phone alerts aren't set up yet – type /wx and press Settings.")
        end
        Print("v" .. GetVersion() .. " loaded – Made by " .. ns.AUTHOR .. ". /wx opens the panel.")
        return
    end
    if not db then return end

    if event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin, arg2 = isReloadingUi. Forever turns the chat log off on a login AND on a
        -- reload (seen 21 Nov 2026: the log file stopped at the /reload), so both make the state unknown.
        if arg1 or arg2 then db.chatlogOn = nil end
        if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
    elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        if arg1 == ADDON then
            Log("blocked", event, tostring(arg2))
            if tostring(arg2):find("Inspect") then
                ns.InspectBlocked()
            elseif takingShot then
                shotBlocked = true   -- NextShot falls back to the chat log
            elseif sendingChat then
                heldBack = true   -- SendAlertLine says it in plain words and offers the click
            else
                Print("|cffffd100The game blocked " .. tostring(arg2) .. " – that action needs a click on this "
                    .. "client. Please tell " .. ns.AUTHOR .. " (see /wx log).|r")
            end
        end
    elseif event == "INSPECT_READY" then
        ns.OnInspectReady(arg1)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        CheckUnit(arg1, "nameplate")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CheckUnit("mouseover", "mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target", "target")
    elseif event == "LOOT_OPENED" then
        ScanLoot()
    elseif event == "UNIT_DIED" then
        OnGuidDied(arg1, "died nearby")
    elseif event == "PARTY_KILL" then
        OnGuidDied(arg2, "killed by your group")
        ns.OnPlayerKill(arg2)
    elseif event == "PLAYER_DEAD" then
        ns.OnPlayerDead()
    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        OnDeathLine(arg1)
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(arg1)
    elseif event == "PLAYER_FLAGS_CHANGED" then
        CheckAfk()
    elseif event == "PLAYER_CAMPING" then
        OnCamping()
    elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
        ns.OnScreenshot(event == "SCREENSHOT_SUCCEEDED")
    elseif event == "PLAYER_LOGOUT" then
        -- written to disk right now: the bridge sees the file change and tells your phone (not on reload/quit)
        ns.SaveProfile()
        db.exitAt = time()
        db.exitWhy = exitReason or (campingAfk and "afk") or "disconnect"
    end
end
ev:SetScript("OnEvent", function(...) ns.Safe("event", OnEvent, ...) end)

-- ---------------------------------------------------------------- slash

SLASH_WATCHX1 = "/wx"
SLASH_WATCHX2 = "/watchx"
local function OnSlash(input)
    if not db then return end
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local function toggle(key, label)
        if rest == "on" then db[key] = true elseif rest == "off" then db[key] = false else db[key] = not db[key] end
        Print(label .. ": " .. (db[key] and "on" or "off"))
        if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
        Refresh()
    end

    if cmd == "" then
        if ns.TogglePanel then ns.TogglePanel() end
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        if ns.OpenSettings then ns.OpenSettings() end
    elseif cmd == "guide" or cmd == "help" or cmd == "howto" then
        if ns.ShowHelp then ns.ShowHelp() end
    elseif cmd == "test" then
        ns.SendTest()
    elseif cmd == "add" then
        local ok, err = ns.AddCustom(rest)
        if not ok then Print(err) end
    elseif cmd == "remove" then
        local name = FindAny(rest)
        if not (name and ns.RemoveCustom(name)) then Print("No custom mob named '" .. rest .. "'.") end
    elseif cmd == "list" or cmd == "status" then
        for _, mob in ipairs(ns.GetMobList()) do
            local _, short, detail = ns.GetMobStatus(mob.name)
            Print(string.format("%s%s – %s %s · kills: %d", mob.enabled and "" or "|cff808080(off)|r ",
                mob.name, short, detail, #MobState(mob.name).kills))
        end
        Print(string.format("Chat log: %s · Nameplates: %s (%s yd)", ns.ChatLogText(),
            GetCVar("nameplateShowEnemies") == "1" and "on" or "OFF", GetCVar("nameplateMaxDistance") or "?"))
    elseif cmd == "mini" then
        if ns.SetMiniShown then ns.SetMiniShown(not db.show) end
    elseif cmd == "move" then
        if ns.ToggleUnlock then ns.ToggleUnlock() end
    elseif cmd == "alert" then
        db.alertSame = (db.alertSame == false)
        Print(db.alertSame and "The alert pops up in the mini bar's spot."
            or "The alert has its own spot – /wx move to place it.")
        if ns.RefreshUI then ns.RefreshUI() end
        if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
    elseif cmd == "quiet" then
        db.miniQuiet = not db.miniQuiet
        Print(db.miniQuiet and "Mini bar only shows when something is up." or "Mini bar always shown.")
        if ns.RefreshUI then ns.RefreshUI() end
    elseif cmd == "lock" then
        if ns.StopMove then ns.StopMove() end
    elseif cmd == "unlock" then
        if ns.StartMove then ns.StartMove() end
    elseif cmd == "profile" then
        if rest ~= "" then
            local want
            for _, n in ipairs(ns.ProfileNames()) do if n:lower() == rest:lower() then want = n end end
            if want then ns.SwitchProfile(want) else Print("No profile called '" .. rest .. "'.") end
        else
            Print("Profiles: " .. table.concat(ns.ProfileNames(), ", ") .. " · active: " .. tostring(db.profile)
                .. " · /wx profile <name> to switch")
        end
    elseif cmd == "xp" or cmd == "boosts" then
        db.levelHelper = db.levelHelper == false
        Print("XP boosts list: " .. (db.levelHelper and "|cff40ff40on|r" or "off")
            .. ((db.levelHelper and not ns.LevelStatus()) and " (it only shows below level " .. ns.MaxLevel() .. ")" or ""))
        if ns.RefreshUI then ns.RefreshUI() end
    elseif (cmd == "mem" or cmd == "memory" or cmd == "cpu") and rest == "reset" then
        local C = ns.cpu
        ns.cpuStart, C.ms, C.by, C.max, C.maxLabel, C.spikes, C.kb = GetTime(), 0, {}, 0, nil, 0, 0
        Print("CPU clock reset – play a while (best: when it lags), then type /wx mem.")
    elseif cmd == "mem" or cmd == "memory" or cmd == "cpu" then
        -- how much memory WatchX uses right now, and what it keeps between sessions
        local Upd = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
        local Get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
        if Upd then pcall(Upd) end
        local ok, kb = false, nil
        if Get then ok, kb = pcall(Get, "WatchX") end
        local players, notes, logLines = 0, 0, #(db.log or {})
        for _, r in pairs(db.enemies) do
            players = players + 1
            if r.note or r.kos or r.avoid or r.wanted then notes = notes + 1 end
        end
        Print(("Memory: |cffffd100%s|r |cffaaaaaa(with garbage Lua hasn't cleared yet)|r  ·  players remembered: %d (%d with KOS, avoid, WANTED or a note; the oldest "
            .. "plain ones go after 2000)  ·  log: %d lines (max %d)  ·  rare catalogue: %d mobs"):format(
            ok and kb and (kb >= 1024 and ("%.1f MB"):format(kb / 1024) or ("%d KB"):format(kb)) or "?",
            players, notes, logLines, LOG_MAX, #(ns.RARES or {})))
        local up = GetTime() - (ns.cpuStart or 0)
        if debugprofilestop and up > 0 then
            Print(("CPU (WatchX's own clock): |cffffd100%.0f ms|r in %s  ·  %.2f ms a second  ·  |cffffd100%.3f%%|r of one CPU core"):format(
                ns.cpu.ms, ns.Fmt and ns.Fmt(up) or (math.floor(up) .. " s"), ns.cpu.ms / up, ns.cpu.ms / up / 10))
            local parts = {}
            for k, v in pairs(ns.cpu.by) do parts[#parts + 1] = { k, v } end
            table.sort(parts, function(a, b) return a[2] > b[2] end)
            local top = {}
            for i = 1, math.min(6, #parts) do
                top[#top + 1] = ("%s |cffffd100%.0f%%|r"):format(parts[i][1], ns.cpu.ms > 0 and parts[i][2] / ns.cpu.ms * 100 or 0)
            end
            if #top > 0 then Print("|cffaaaaaaMost of it:|r " .. table.concat(top, "  ·  ")
                .. "  |cffaaaaaa(/wx mem reset: measure from now, without the login)|r") end
            local C = ns.cpu
            local spikeCol = C.max > 16 and "|cffff4040" or C.max > 5 and "|cffffd100" or "|cff40ff40"
            Print(("Longest single call: %s%.1f ms|r (%s)  ·  calls over 5 ms: %d  ·  garbage made: %.0f KB a second"):format(
                spikeCol, C.max, C.maxLabel or "-", C.spikes, C.kb / up)
                .. " |cffaaaaaa(a frame at 60 fps is 16.7 ms)|r")
        end
        local GetCPU = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
        if GetCVar("scriptProfile") == "1" and GetCPU then
            local okc, ms = pcall(GetCPU, "WatchX")
            if okc and ms then Print(("CPU since login/reload: %.0f ms"):format(ms)) end
        else
            Print("|cffaaaaaaThe game's own measure: /console scriptProfile 1 and a /reload (it costs a little itself – "
                .. "/console scriptProfile 0 afterwards).|r")
        end
    elseif cmd == "rares" or cmd == "rare" or cmd == "catalogue" then
        if ns.ShowRares then ns.ShowRares() end
    elseif cmd == "wanted" or cmd == "bounty" then
        -- /wx wanted Name Surname: 50g ninja looter   (or just /wx wanted for the list)
        local name, after = rest:match("^([^:]+):%s*(.*)$")
        name = Trim(name or rest)
        if name ~= "" then
            local copper, note = ns.ParseMoney(after or "")
            ns.SetWanted(ns.KeyFromName(name), name, copper, note)
        elseif ns.ShowHistory then ns.ShowHistory("wanted") end
    elseif cmd == "avoid" or cmd == "blacklist" then
        -- /wx avoid Name Surname: note   (or just /wx avoid to open the list)
        local name, note = rest:match("^([^:]+):%s*(.*)$")
        name = name or rest
        if Trim(name) ~= "" then ns.SetAvoid(name, true, note)
        elseif ns.ShowHistory then ns.ShowHistory("avoid") end
    elseif cmd == "buffs" or cmd == "buff" then
        if rest == "test" then ns.BuffTest()
        elseif rest ~= "" then ns.AddBuffWatch(rest)
        elseif ns.OpenBuffSettings then ns.OpenBuffSettings() end
    elseif cmd == "nearby" or cmd == "spy" then
        if rest == "test" then ns.NearbyTest()
        elseif rest == "on" or rest == "off" then ns.SetNearby(rest == "on")
        elseif ns.OpenNearbySettings then ns.OpenNearbySettings() end
    elseif cmd == "attack" or cmd == "attacked" then
        toggle("attackAlert", "Alert when attacked")
    elseif cmd == "friend" or cmd == "friendly" then
        ns.SetFriendlyPlayers(not db.friendlyPlayers)
    elseif cmd == "enemy" or cmd == "pvp" then
        ns.SetEnemyPlayers(not db.enemyPlayers)
    elseif cmd == "whisper" then toggle("whisper", "Phone alerts")
    elseif cmd == "instant" then
        toggle("instant", "Instant alerts (screenshot)")
        db.instantOK = nil
    elseif cmd == "afk" then
        local min = tonumber(rest)
        if min and min >= 6 and min <= 120 then
            db.afkLogoutMin = math.floor(min)
            Print("AFK logout expected " .. db.afkLogoutMin .. " min after you go AFK – warning 5 min before.")
        else
            toggle("afkWarn", "AFK logout warning")
        end
    elseif cmd == "sound" then toggle("sound", "Sound")
    elseif cmd == "minimap" then
        if ns.SetMinimapShown then ns.SetMinimapShown(db.minimap.hide) end
    elseif cmd == "dead" then
        local name = FindAny(rest ~= "" and rest or "Prince Nazjak")
        if name then MobState(name).alive = false; MobState(name).lastDeath = nil; OnDeath(name, "manual")
        else Print("Unknown mob.") end
    elseif cmd == "respawn" then
        local min, who = rest:match("^(%S+)%s*(.-)$")
        local name = FindAny(who ~= "" and who or "Prince Nazjak")
        if not name then Print("Usage: /wx respawn <minutes> [name]") return end
        ns.SetManualRespawn(name, min)
        local m = MobState(name)
        Print(name .. ": " .. (m.manualRespawn and ("respawn set to " .. Fmt(m.manualRespawn)) or "manual respawn cleared."))
    elseif cmd == "method" then
        db.methodFailed = db.methodFailed or {}
        if rest == "reset" then
            db.methodFailed, db.sendMethod = {}, nil
            Print("Send method reset – WatchX finds the way again with the next alert.")
        elseif rest == "auto" or rest == "whisper" or rest == "realm" or rest == "dnd" then
            db.sendMethod = rest ~= "auto" and rest or nil
            Print("Send method: " .. rest)
        else
            local failed = {}
            for _, m in ipairs(METHODS) do if db.methodFailed[m] then failed[#failed + 1] = m end end
            Print("Send method: |cff40ff40" .. CurrentMethod() .. "|r" .. (db.sendMethod and " (forced)" or " (auto)")
                .. (#failed > 0 and ("  ·  doesn't work here: " .. table.concat(failed, ", ")) or "")
                .. "  ·  /wx method auto|whisper|realm|dnd|reset")
        end
    elseif cmd == "reset" then
        ns.ResetData()
    elseif cmd == "log" then
        local lines = (rest == "previous" and db.previousLog) or db.log or {}
        Print((rest == "previous" and "Previous" or "This") .. " session's log (" .. #lines .. " lines):")
        for i = math.max(1, #lines - 24), #lines do DEFAULT_CHAT_FRAME:AddMessage("  " .. lines[i]) end
    else
        Print("Made by " .. ns.AUTHOR .. ". Commands: /wx (panel) | settings | guide | test | add <name> | "
            .. "remove <name> | profile [name] | enemy | friend | nearby [on|off|test] | xp | buffs [name|test] | avoid [name: note] | wanted [name: reward note] | rares | mem | attack | afk [minutes] | instant | list | mini | quiet | alert | move | lock | unlock | minimap | sound | "
            .. "whisper | dead [name] | "
            .. "respawn <min> [name] | reset | log [previous]")
    end
end
SlashCmdList.WATCHX = function(input) ns.Safe("/wx", OnSlash, input) end
