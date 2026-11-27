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
-- big chunks (slow): <key> [WatchX]#<id> <TYPE> <subject>::<text>  (the key = db.bridgeKey, per install;
-- in front, so bridges from before it still find "[WatchX]#")
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
    stealthSound = true,  -- Nearby: "Sounds" – all the PvP sounds on or off
    sounds = {},          -- Nearby: kind (stealth, kos, wanted, enemy, bounty) -> a sound (UI.lua ns.SOUND_CHOICES)
    newEnemyCard = false, -- Nearby: an "Enemy player detected!" card for every new enemy (stealth/KOS always)
    warnDock = false,     -- Nearby: the cards sit on top of the list (off: top of the screen, movable)
    nearbyAttach = true,  -- Nearby: the list hangs under the mini bar, same width
    nearbyMax = 10,       -- Nearby: how many players the list shows
    nearbyNoBG = true,    -- Nearby: off in battlegrounds and arenas
    nearbyHideDungeon = false, -- Nearby: hidden in dungeons (else faded)
    nearbyHideRaid = false,    -- Nearby: hidden in raids (else faded)
    kosAlert = true,      -- Nearby: a "Kill on sight!" card + sound when a KOS player shows up
    shareParty = false,   -- Enemies: say what you spot in party / raid chat
    shareGuild = false,   -- ... and / or in guild chat
    shareFriends = false, -- ... and / or whispered to the friends in shareFriendNames
    shareFriendNames = {},
    potionOrder = { "Free Action", "Living Action", "Invulnerability", "Swiftness", "Restorative" },   -- shown first
    platePotionMax = 4,   -- potions on one nameplate at most
    plateX = 0, plateY = 8,   -- nameplate icons: moved from just above the nameplate (+ = right / up)
    potionGlow = { "Free Action", "Living Action", "Invulnerability" },   -- the important ones: a glow round them
    customPotions = {},   -- your own: { spell = the spell it casts, id, label, secs } (Settings > Nameplates)
    shareStealth = true,  -- ... which: stealth, KOS, WANTED (and every new enemy, at most one every 10 s)
    shareKOS = true,
    shareWanted = true,
    shareAll = false,
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
    if type(db.log) ~= "table" then db.log = {} end   -- a fresh install has none yet
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
    if label == "/wx" then return end   -- what you type (/wx mem asks the game for every addon's memory: slow)
    C.ms = C.ms + dt
    C.by[label] = (C.by[label] or 0) + dt
    if dt > C.max then C.max, C.maxLabel = dt, label end
    if dt > 4 then C.spikes = C.spikes + 1 end
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

-- All mobs: presets first, then custom ones. The same list is handed out again while the names are the same (it's
-- asked for every refresh; "on" is brought up to date in place), so it doesn't make new tables each time.
function ns.GetMobList()
    local list = ns.mobList
    if list and list.db == db and #list == #ns.PRESETS + #db.custom then
        local same, k = true, #ns.PRESETS
        for i, p in ipairs(ns.PRESETS) do
            local m = list[i]
            if m.name ~= p.name then same = false break end
            m.enabled = db.watch[p.name] and true or false
        end
        for i, name in ipairs(same and db.custom or {}) do
            local m = list[k + i]
            if m.name ~= name then same = false break end
            m.enabled = db.watch[name] and true or false
        end
        if same then return list end
    end
    list = { db = db }
    ns.mobList = list
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
        msg = Plain(msg)   -- chat text can be a secret value: that would error on :find
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

ns.SendChat = SendChat   -- (the Enemies list tells your party / guild with it)

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
    -- this install's key in front: the bridge only takes chat-log lines with it (anyone can type "[WatchX]"),
    -- and a bridge from before the key still finds the tag after it
    local key = (type(db.bridgeKey) == "string" and db.bridgeKey ~= "") and (db.bridgeKey .. " ") or ""
    local msg = string.format("%s%s#%d%03d %s %s::%s", key, TAG, epoch, ctr, kind, subject, text or "")
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
        db.instantOK, ns.shotFails = true, 0
    else
        Log("instant", "screenshot failed", why or "?")
        -- one failed shot (a minimized window, a loading screen) doesn't switch it off: three in a row do
        ns.shotFails = (ns.shotFails or 0) + 1
        if ns.shotFails >= 3 then db.instantOK = false end
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
        local item = { kind = kind, subject = subject, text = text, epoch = epoch, ctr = counter }
        if kind == "SPAWN" or kind == "LOOT" or kind == "ATTACK" or kind == "AFK" or kind == "LOGOUT" or kind == "TEST" then
            -- urgent: ahead of the player sightings (each picture takes about a second)
            local at = 1
            while shotQueue[at] and (shotQueue[at].kind == "SPAWN" or shotQueue[at].kind == "ATTACK"
                    or shotQueue[at].kind == "LOGOUT" or shotQueue[at].kind == "AFK") do at = at + 1 end
            table.insert(shotQueue, at, item)
        else
            -- a crowd of players: no more than three sightings wait, the newest ones
            local n, first = 0, nil
            for i, q in ipairs(shotQueue) do
                if q.kind == kind then n = n + 1; first = first or i end
            end
            if n >= 3 and first then table.remove(shotQueue, first) end
            shotQueue[#shotQueue + 1] = item
        end
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
    -- links typed since the reload aren't in the saved settings yet, and the bridge only reads those
    local links = (db.ntfyUrl or "") .. "\1" .. (db.discordWebhook or "") .. "\1" .. (db.ntfyToken or "")
    if ns.linksAtLogin and links ~= ns.linksAtLogin then
        Print("|cffffd100Your phone links changed – press \"Save & reload\" first (the bridge reads them from the saved "
            .. "settings), then Send test.|r")
        return
    end
    if db.instantOK == false then db.instantOK, ns.shotFails = nil, 0 end   -- a test tries the instant way again
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
    while #m.kills > 50 do table.remove(m.kills, 1) end   -- the last 50 are plenty (saved between sessions)
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
        -- the same corpse seen again (it lies there for minutes): not a new death, no new alert
        if not m.alive and m.lastDeath and now - m.lastDeath < 900 then return end
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
        if gap >= 120 and gap < 12 * 3600 then   -- under 2 minutes is a double count, not a respawn
            table.insert(m.samples, gap)
            while #m.samples > 20 do table.remove(m.samples, 1) end
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

-- When a player was last announced. A long session in a busy place doesn't keep every name it ever saw: past
-- 500 the ones whose wait is over are forgotten. (On ns: the main chunk is at the 200-locals limit.)
function ns.Stamp(seen, name, now)
    if seen[name] == nil then
        local c = ns.stampN or setmetatable({}, { __mode = "k" })
        ns.stampN = c
        c[seen] = (c[seen] or 0) + 1
        if c[seen] > 500 then
            local n = 0
            for k, at in pairs(seen) do
                if now - at >= ENEMY_COOLDOWN then seen[k] = nil else n = n + 1 end
            end
            c[seen] = n
        end
    end
    seen[name] = now
end

-- Any hostile player (PvP), when "Any enemy player" is on. Not in instances or battlegrounds,
-- and the same player only once every ENEMY_COOLDOWN seconds.
local function CheckEnemyPlayer(unit, name, source)
    local hostile = Plain(UnitIsEnemy("player", unit)) == true or Plain(UnitCanAttack("player", unit)) == true
    if not hostile or Plain(UnitIsDead(unit)) == true then return end
    local inInstance = IsInInstance and IsInInstance()
    if inInstance then return end
    local now = time()
    if ns.lastEnemy then ns.lastEnemy.name, ns.lastEnemy.at = name, now else ns.lastEnemy = { name = name, at = now } end
    if enemySeen[name] and now - enemySeen[name] < ENEMY_COOLDOWN then return end
    ns.Stamp(enemySeen, name, now)
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
    -- a name only: anything else (a line break, a slash, brackets) could make the macro run more than /targetexact
    for _, v in ipairs({ first or "", full or "", key or "" }) do
        if type(v) ~= "string" or v:find("[%c/;%[%]|]") then return "" end
    end
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
    r.pos = ns.Coords and ns.Coords() or nil   -- (where you were: close enough to find them; none in dungeons)
    r.class, r.level, r.guild, r.race = e.class or r.class, e.level or r.level, e.guild or r.guild, e.race or r.race
    local guid = Plain(UnitGUID(unit))
    if type(guid) == "string" then ns.playerGuids[guid] = key end
    e.kos = ns.IsKOS(key, first, e.guild)
    if isNew then
        local w = ns.Wanted and ns.Wanted(key)
        if ns.ShareSpot then   -- your party / guild, when ticked
            if e.kos then ns.ShareSpot(e, "kos") elseif w then ns.ShareSpot(e, "wanted", w) else ns.ShareSpot(e, "enemy") end
        end
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
        if not ns.enemyCount then   -- counted once per session (the saved ones too), then kept up to date
            local n = 0
            for _ in pairs(db.enemies) do n = n + 1 end
            ns.enemyCount = n
        else
            ns.enemyCount = ns.enemyCount + 1
        end
        if ns.enemyCount > (ns.enemyPruneAt or ENEMY_MAX) then ns.PruneEnemies() end
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
    local n = 0
    for _ in pairs(db.enemies) do n = n + 1 end
    ns.enemyCount = n
    -- mostly kept ones (KOS, notes, kills)? then not again on the very next player
    ns.enemyPruneAt = math.max(ENEMY_MAX, n) + 200
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
-- Names as the game writes them: a capital first letter, the rest small, for the first name and the surname –
-- so "bob smith" finds Bob Smith. Letters like æ ø å é are one byte pair in UTF-8: capital = small - 32.
function ns.ProperName(s)
    if type(s) ~= "string" then return s end
    local function up(c)
        if #c == 1 then return c:upper() end
        local b1, b2 = c:byte(1, 2)
        if b1 == 195 and b2 >= 160 and b2 <= 190 and b2 ~= 183 then return string.char(195, b2 - 32) end
        return c
    end
    local function low(c)
        if #c == 1 then return c:lower() end
        local b1, b2 = c:byte(1, 2)
        if b1 == 195 and b2 >= 128 and b2 <= 158 and b2 ~= 151 then return string.char(195, b2 + 32) end
        return c
    end
    return (s:gsub("[^%s%-]+", function(w)
        local first, rest = w:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
        if not first then return w end
        return up(first) .. rest:gsub("[%z\1-\127\194-\244][\128-\191]*", low)
    end))
end

function ns.KeyFromName(name)
    name = ns.ProperName(Trim(name or ""))
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
    ns.historyDirty, ns.kosDirty = true, true   -- an open History / PvP page follows with the next refresh
    Refresh()
end

function ns.SetGuildKOS(guild, on)
    guild = Trim(guild or "")
    if guild == "" then return end
    db.kosGuilds[guild:lower()] = on and guild or nil
    for key, e in pairs(ns.nearby) do e.kos = ns.IsKOS(key, e.first, e.guild) end
    Print((on and "|cffff3030KOS guild|r: " or "No longer a KOS guild: ") .. "<" .. guild .. ">")
    if ns.UpdatePlates then ns.UpdatePlates() end
    ns.historyDirty, ns.kosDirty = true, true   -- an open History / PvP page follows
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
    if fw and ns.WantedMine and not ns.WantedMine(fw) and not (ns.WantedState and ns.WantedState(fw).settled) then
        Print("Can't forget " .. (db.enemies[key].name or key) .. ": " .. (fw.by or "someone") .. " has a bounty on them.")
        return false
    end
    if fw and ns.WantedMine and ns.WantedMine(fw) then ns.RemoveWanted(key) end   -- yours: down for all
    db.enemies[key] = nil
    if ns.AvoidChanged then ns.AvoidChanged() end
    ns.enemyCount = nil
    ns.historyDirty, ns.kosDirty = true, true   -- an open History / PvP page follows
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
    if ns.ShareSpot then ns.ShareSpot(e, "stealth", what) end
    if db.stealthWarn == false then Refresh() return end
    if ns.AlertSound then ns.AlertSound("stealth") end
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
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n <= ROLE_MAX then return end   -- counted first: no garbage for every new player
    local list = {}
    for k, r in pairs(t) do list[#list + 1] = { k, r.at or 0 } end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, #list - ROLE_MAX + 200 do t[list[i][1]] = nil end
end

-- Remember what a player is. key = "First-Last" (or nil when the name is hidden; then the plate holds it).
local function SetRole(key, unit, role, how)
    local old
    if key then
        local t = RoleStore()
        old = t[key]
        if old and old.role == role then old.at, old.how = time(), how return end   -- the same again: just fresher
        t[key] = { role = role, how = how, at = time() }
        if not old then PruneRoles(t) end
    elseif type(unit) == "string" and unit:find("^nameplate%d+$") then
        old = ns.roles["plate:" .. unit]
        ns.roles["plate:" .. unit] = { role = role, how = how, at = time() }
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

-- Potions and warrior stances on enemy players: seen from their casts (a potion is a spell when it's drunk, so is a
-- stance change), and out of combat from a warrior's stance buff. Kept on the player's Nearby entry: e.potions =
-- { [spell] = { label, spell, untilT, dur } } while they last, e.stance = "Battle" / "Defensive" / "Berserker".
do   -- (its own block: the main chunk is at Lua's 200-locals limit)
    -- spell name -> what to call it, how long it lasts (s)
    local POTIONS = {
        ["Free Action"] = { "Free Action", 30 }, ["Living Free Action"] = { "Living Action", 5 },
        ["Invulnerability"] = { "Invulnerability", 6 }, ["Restoration"] = { "Restorative", 10 },
        ["Speed"] = { "Swiftness", 15 }, ["Mighty Rage"] = { "Mighty Rage", 20 }, ["Great Rage"] = { "Great Rage", 20 },
        ["Rage"] = { "Rage", 20 }, ["Healing Potion"] = { "Healing Potion", 5 }, ["Restore Mana"] = { "Mana Potion", 5 },
        ["Purification"] = { "Purification", 5 }, ["Magic Resistance"] = { "Magic Resistance", 180 },
        ["Lesser Invisibility"] = { "Lesser Invisibility", 15 }, ["Invisibility"] = { "Invisibility", 18 },
        ["Fire Protection"] = { "Fire Protection", 60 }, ["Frost Protection"] = { "Frost Protection", 60 },
        ["Nature Protection"] = { "Nature Protection", 60 }, ["Shadow Protection"] = { "Shadow Protection", 60 },
        ["Arcane Protection"] = { "Arcane Protection", 60 },
    }
    ns.POTIONS = POTIONS
    ns.POTION_LABELS = {}   -- (the names you can put in the order: Settings > Nameplates)
    for _, v in pairs(POTIONS) do ns.POTION_LABELS[#ns.POTION_LABELS + 1] = v[1] end
    table.sort(ns.POTION_LABELS)
    local POTION_IDS = { [6615] = "Free Action", [24364] = "Living Free Action", [3169] = "Invulnerability",
        [11359] = "Restoration", [2379] = "Speed", [17528] = "Mighty Rage" }
    local STANCES = { ["Battle Stance"] = "Battle", ["Defensive Stance"] = "Defensive", ["Berserker Stance"] = "Berserker" }
    -- abilities only one stance allows: using one says which stance they're in
    local STANCE_OF = { Overpower = "Battle", Charge = "Battle", ["Mocking Blow"] = "Battle", Retaliation = "Battle",
        ["Thunder Clap"] = "Battle", ["Sweeping Strikes"] = "Battle",
        ["Shield Wall"] = "Defensive", ["Shield Block"] = "Defensive", Disarm = "Defensive", Revenge = "Defensive",
        Taunt = "Defensive",
        Intercept = "Berserker", Whirlwind = "Berserker", ["Berserker Rage"] = "Berserker", Pummel = "Berserker",
        Recklessness = "Berserker" }
    ns.STANCE_SPELLS = { Battle = 2457, Defensive = 71, Berserker = 2458 }
    ns.STANCE_ICONS = { Battle = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
        Defensive = "Interface\\Icons\\Ability_Warrior_DefensiveStance", Berserker = "Interface\\Icons\\Ability_Racial_Avatar" }
    local function IsWarrior(unit)
        local _, c = UnitClass(unit)
        return Plain(c) == "WARRIOR"
    end
    function ns.OnEnemyTrick(unit, spellID)
        if not (db.nearby and type(unit) == "string") or not ns.NearbyHere() then return end
        if not (unit == "target" or unit == "focus" or unit == "mouseover" or unit:find("^nameplate%d+$")) then return end
        spellID = Plain(spellID)
        if type(spellID) ~= "number" then return end
        local name = POTION_IDS[spellID] or SpellName(spellID)
        if type(name) ~= "string" then return end
        local pot, st = POTIONS[name], STANCES[name] or STANCE_OF[name]
        if not pot and type(db.customPotions) == "table" then   -- one you added yourself
            local low = name:lower()
            for _, c in ipairs(db.customPotions) do
                if c.id == spellID or (type(c.spell) == "string" and c.spell:lower() == low) then
                    pot = { c.label, tonumber(c.secs) or 30 } break
                end
            end
        end
        if not (pot or st) then return end
        if Plain(UnitIsPlayer(unit)) ~= true or not ns.IsHostilePlayer(unit) then return end
        if st and not IsWarrior(unit) then st = nil end   -- (Charge, Taunt … of a druid's: no stance)
        if not (pot or st) then return end
        local key = NoteNearby(unit)
        local e = key and ns.nearby[key]
        if not e then return end
        if pot then
            local now = GetTime()
            e.potions = e.potions or {}   -- (several at once: Free Action and Swiftness …, one each)
            for id, q in pairs(e.potions) do if q.untilT <= now then e.potions[id] = nil end end
            local old = e.potions[spellID]
            if not (old and now - (old.untilT - old.dur) < 2) then   -- (one cast, every token)
                local p = { label = pot[1], spell = spellID, untilT = now + pot[2], dur = pot[2] }
                e.potions[spellID], e.potion = p, p   -- (e.potion: the latest)
                Log("potion", e.name, pot[1])
                if ns.OnEnemyPotion then ns.Safe("potion sound", ns.OnEnemyPotion, e, p) end
            end
        end
        if st then e.stance, e.stanceAt = st, time() end
        if ns.OnEnemyTrickSeen then ns.OnEnemyTrickSeen(unit, e) end
    end
    -- out of combat: a warrior's stance is a buff on him (Forever hides auras in a fight)
    function ns.ScanStance(unit)
        if Plain(UnitIsPlayer(unit)) ~= true or not IsWarrior(unit) or not ns.IsHostilePlayer(unit) then return end
        local get = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
        if not get then return end
        for i = 1, 40 do
            local ok, a = pcall(get, unit, i)
            if not ok or type(a) ~= "table" then return end
            local st = STANCES[Plain(a.name) or ""]
            if not st then
                local sid = Plain(a.spellId)
                for k, id in pairs(ns.STANCE_SPELLS) do if id == sid then st = k end end
            end
            if st then
                local key = PlayerKey(unit)
                local e = key and ns.nearby[key]
                if e then e.stance, e.stanceAt = st, time() end
                return st
            end
        end
    end
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
            -- only a form the player puts on himself counts: Power Infusion, Earth Shield, Riptide and the like are
            -- buffs a healer gives to others, so they say nothing about this player
            if not ns.ROLE_FORMS then
                ns.ROLE_FORMS = {}
                for _, fid in ipairs({ 33891, 15473, 24858 }) do   -- Tree of Life, Shadowform, Moonkin Form
                    local fn = SpellName(fid)
                    if fn then ns.ROLE_FORMS[fn] = true end
                end
            end
            local role, name = RoleOfSpell(id)
            if role and name and ns.ROLE_FORMS[name] then SetRole((PlayerKey(unit)), unit, role, name) return end
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

-- An item's cooldown: start and duration, or nil when it's ready. Every way the client may have is asked (one of
-- them alone showed nothing on Forever): the item's, its bag slot's, and its Use: spell's – the longest wins.
-- Kept a second (it's asked on every refresh, and the bag slots are only looked through when the rest say nothing).
do   -- (its own block: the main chunk is at Lua's 200-locals limit)
local cdCache = {}
local function CdPair(a, b)
    if type(a) == "table" then return tonumber(Plain(a.startTime or a.start)), tonumber(Plain(a.duration)) end
    return tonumber(Plain(a)), tonumber(Plain(b))
end
function ns.ItemCooldown(id)
    local now = GetTime()
    local c = cdCache[id]
    if c and now - c.at < 1 then
        if c.s and c.s + c.d > now then return c.s, c.d end
        return nil
    end
    local bs, bd, bend = nil, nil, now
    local function try(f, ...)
        if type(f) ~= "function" then return end
        local ok, a, b = pcall(f, ...)
        if not ok then return end
        local st, du = CdPair(a, b)
        -- (1.5 s or less = the global cooldown)
        if st and du and st > 0 and du > 1.5 and st + du > bend then bs, bd, bend = st, du, st + du end
    end
    try(C_Item and C_Item.GetItemCooldown, id)
    try(C_Container and C_Container.GetItemCooldown, id)
    try(GetItemCooldown, id)
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if getSpell then
        local ok, _, sid = pcall(getSpell, id)
        sid = ok and tonumber(Plain(sid))
        if sid then try(C_Spell and C_Spell.GetSpellCooldown, sid); try(GetSpellCooldown, sid) end
    end
    local CC = C_Container
    if not bs and CC and CC.GetContainerItemCooldown and CC.GetContainerNumSlots and ns.SlotItem then
        for bag = 0, 4 do
            local okN, n = pcall(CC.GetContainerNumSlots, bag)
            for slot = 1, (okN and tonumber(Plain(n)) or 0) do
                if ns.SlotItem(bag, slot) == id then try(CC.GetContainerItemCooldown, bag, slot) break end
            end
            if bs then break end
        end
    end
    cdCache[id] = { at = now, s = bs, d = bd }
    return bs, bd
end
end
local function ItemCooldownLeft(id)
    local st, du = ns.ItemCooldown(id)
    return st and math.max(0, st + du - GetTime()) or 0
end

-- Does a buff's text say it gives XP? (true / false / nil = can't tell). Set below, with the tooltip helpers.
local AuraIsXP

-- The boost auras on you: spell ID -> { left = seconds (nil: no end), stacks }.
-- Well Fed counts when it's the XP one: its own ID, or any buff whose text says it gives XP from kills (a
-- "Well Fed" from stat food doesn't count when its text can be read).
local function ReadAuras()
    local byName, found = {}, {}
    local campName = SpellName(1229741)   -- Camp Benefits: one buff holding all a camp's effects, 1 hour
    for id, en in pairs(AURA_NAMES) do
        byName[en] = id
        local n = SpellName(id)
        if n then byName[n] = id end
    end
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local name, count, expires, sid, inst
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if not ok or type(a) ~= "table" then break end
                name, count, expires, sid, inst = a.name, a.applications, a.expirationTime, a.spellId, Plain(a.auraInstanceID)
            elseif UnitAura then
                local ok, n, _, c, _, _, e, _, _, _, s = pcall(UnitAura, "player", i, filter)
                if not ok or n == nil then break end
                name, count, expires, sid = n, c, e, s
            else
                break
            end
            name, count, expires, sid = Plain(name), Plain(count), Plain(expires), Plain(sid)
            if name == nil and sid == nil then found.unreadable = true end   -- there, but hidden (secret): an unsure read
            if filter == "HELPFUL" and type(name) == "string" and name:lower():find("campfire", 1, true) then
                found.campfire = true   -- e.g. Welcoming Campfire: there's a fire close by
            end
            if filter == "HELPFUL" and type(expires) == "number" and expires > 0 then
                -- the camp: Camp Benefits (what you got, read from its text later), the 1-minute sitting timer,
                -- and every buff of about an hour (if a camp object gives its own, it ends with Camp Benefits)
                if sid == 1229741 or (type(name) == "string" and (name == "Camp Benefits" or name == campName)) then
                    found.camp = { sid = sid, name = name, inst = inst, expires = expires }
                elseif sid == 1289723 or sid == 1229739 or name == "Welcoming Campfire" then
                    found.welcome = { expires = expires }
                elseif sid and not AURA_NAMES[sid] and expires - GetTime() > 600 then
                    found.hour = found.hour or {}
                    found.hour[#found.hour + 1] = { sid = sid, name = name, expires = expires }
                end
            end
            if filter == "HELPFUL" and (name == "Food" or name == "Food & Drink" or name == "Refreshment") then
                found.eating = true     -- sitting and eating: the new Well Fed comes after 10 seconds
            end
            local learned = filter == "HELPFUL" and sid and type(db.xpBuffs) == "table" and db.xpBuffs[sid]
            local id = (AURA_NAMES[sid] and sid) or (type(name) == "string" and byName[name]) or (learned and WELL_FED)
            -- buffs of 10–60 minutes (a food's Well Fed is one): what came new while you ate is learned (CheckBoosts)
            if filter == "HELPFUL" and sid and type(expires) == "number" and expires > 0 then
                local dur = expires - GetTime()
                if dur >= 300 and dur <= 3600 then found.long = found.long or {}; found.long[sid] = type(name) == "string" and name or tostring(sid) end
            end
            if filter == "HELPFUL" and AuraIsXP and id ~= WELL_RESTED and sid ~= WELL_FED and not learned then
                local xp = AuraIsXP(i, sid, name)
                if id == WELL_FED and xp == false then id = nil          -- stat food's Well Fed
                elseif not id and xp == "kill" then id = WELL_FED end    -- an XP-from-kills buff by another name
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

local function Secret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end
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

-- What a camp gave you: Camp Benefits' text, one effect a line (its name and "… remaining" left out), plus any
-- buff that came at the same moment. Read once per camp (again in 10 s if the text wasn't ready).
function ns.CampEffects(camp, hour)
    local key = tostring(camp.sid or camp.name) .. ":" .. math.floor(tonumber(camp.expires) or 0)
    local c = ns.campTip
    if c and c.key == key and (c.ok or GetTime() < c.retry) then return c.lines end
    local text
    local T = C_TooltipInfo
    if T and T.GetUnitBuffByAuraInstanceID and camp.inst then
        local ok, data = pcall(T.GetUnitBuffByAuraInstanceID, "player", camp.inst)
        if ok then text = TooltipText(data) end
    end
    local desc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if not text and desc and camp.sid then
        local ok, t = pcall(desc, camp.sid)
        t = ok and Plain(t)
        if type(t) == "string" and t ~= "" then text = t end
    end
    local lines, have = {}, {}
    for l in (text or ""):gmatch("[^\n]+") do
        l = l:gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" and l ~= camp.name and not l:lower():find("remaining", 1, true) and not have[l] then
            have[l] = true; lines[#lines + 1] = l
        end
    end
    for _, h in ipairs(hour or {}) do
        if type(h.name) == "string" and not have[h.name] and math.abs((h.expires or 0) - (camp.expires or 0)) <= 30 then
            have[h.name] = true; lines[#lines + 1] = h.name
        end
    end
    ns.campTip = { key = key, lines = lines, ok = text ~= nil, retry = GetTime() + 10 }
    return lines
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
    if not text and not T.GetHyperlink then text = ScanTipText(itemID) end   -- old clients only
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
    if type(t) == "string" and t ~= "" then return t end
    return nil, true   -- it has a spell, its words aren't loaded yet
end

-- A buff's text: its tooltip, or its spell's description. Cached per spell (it doesn't change).
local auraXPCache = {}
AuraIsXP = function(index, sid, name)
    local key = sid or name
    if key == nil then return nil end
    local c = auraXPCache[key]
    if c ~= nil and type(c) ~= "number" then return c end
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
    -- "kill": more XP from kills (the XP food's buff); "rest": only about rested XP (resting, a bed…); false: no XP
    local yes = IsXPText(body)
    if yes then yes = body:lower():find("kill", 1, true) and "kill" or "rest" end
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
    if known == false then return false end
    if type(known) == "number" and GetTime() < known then return false end
    if NOT_FOOD[itemID] or not IsConsumable(itemID) then xpFoodCache[itemID] = false return false end
    local text = ItemTooltipText(itemID, bag, slot)
    if not text then bagState.pending = true return false end   -- not loaded yet: ask again a bit later
    local spell, spellLoading = ItemSpellText(itemID)
    local yes = IsXPText(text) or IsXPText(spell)
    -- a "no" read from the item's own text is kept for the session (it doesn't change); only when the spell's
    -- words weren't loaded yet is it asked again a little later
    if yes then xpFoodCache[itemID] = true
    elseif spellLoading then xpFoodCache[itemID] = GetTime() + 120
    else xpFoodCache[itemID] = false end
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
    -- only consumables and miscellaneous items can be camp features: no tooltip read for armour, weapons, trade goods
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if f then
        local ok, _, _, _, _, _, classID = pcall(f, itemID)
        classID = ok and tonumber(Plain(classID))
        if classID and classID ~= 0 and classID ~= 15 then campCache[itemID] = GetTime() + 86400 return false end
    end
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
ns.ItemName = ItemName
ns.ItemTooltipText = ItemTooltipText   -- (the plain item's text, safely: the eating tiles read a food's with it)

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
    -- right after a loading screen auras and bags can read empty for a moment: no news from that; nor from a fight
    -- (buffs can read hidden there): it's compared with the last good look afterwards
    if bagState.loadingUntil and GetTime() < bagState.loadingUntil then return end
    if now.unsure then return end
    local was = lastBoost
    lastBoost = now
    if not was or db.levelWarn == false then return end
    if Plain(UnitIsDeadOrGhost("player")) == true then return end
    local function gone(k) return was[k] and not now[k] end
    -- done: you can stop eating / get up / the tent has worked (shown at once, in town too: you just did it).
    -- Only for what you just did: after a loading screen (a portal) the buffs can read missing for a moment and
    -- come back – that's not news. Well Fed comes from eating; the bag's stacks build one at a time (0 -> 3 is
    -- a bad read); a new Boosted Rest has almost its full hour left.
    local ate = now.eating or was.eating or ns.eatWatch
    if now.fed and not was.fed and ate and not fedGone then
        ns.Done("Well Fed – +5% XP from kills for 15 min. You can stop eating.")
    elseif now.fed and not was.fed and ate and fedGone then
        ns.Done("Well Fed again – topped up for 15 min.")
    end
    if (now.restedStacks or 0) >= 3 and (was.restedStacks or 0) >= 1 and (was.restedStacks or 0) < 3 then
        ns.Done("Well-Rested 3/3 – the full +3% XP. You can get up.")
    end
    if now.boost and not was.boost and (now.boostLeft or 0) > 3300 then
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
    -- An XP food whose Well Fed is called something else (or says it differently): the long buff that came while you
    -- ate it (XP food gone from your bags, or eaten through the XP icon) – and Well Fed not seen – is learned as its
    -- Well Fed, once.
    local E = ns.eatWatch
    if now.eating and not was.eating then
        E = { food = was.food, long = was.long or {} }
        ns.eatWatch = E
    end
    if E then
        if not now.eating and not E.done then E.done = GetTime() end
        local ateXP = ((now.food or 0) < (E.food or 0)) or (ns.foodUsedAt and GetTime() - ns.foodUsedAt < 90)
        if E.done and GetTime() - E.done > 40 then
            ns.eatWatch = nil
        elseif ateXP and not now.fed then
            for sid, nm in pairs(now.long or {}) do
                if not E.long[sid] and sid ~= WELL_RESTED and sid ~= BOOSTED_REST then
                    if type(db.xpBuffs) ~= "table" then db.xpBuffs = {} end
                    db.xpBuffs[sid] = nm
                    ns.eatWatch = nil
                    statusCache.dirty = true
                    Print("|cff40ff40" .. nm .. "|r is your XP food's buff – WatchX knows it from now on.")
                    break
                end
            end
        end
    end
    -- the last XP food: said once you stop eating (the count drops while you still sit and eat it)
    if ((was.food or 0) > 0 or was.foodOut) and (now.food or 0) == 0 then now.foodOut = true end
    if now.foodOut and not now.eating then
        if not pendingWarn.fed then pendingWarn.food = "You've used your last XP food – cook or buy more." end
        now.foodOut = nil
    end
    -- gone only when it stays gone for a while (a new stack or a renewal can take it off for a moment)
    local G = ns.boostGone or {}
    ns.boostGone = G
    for _, k in ipairs({ "rested", "boost" }) do
        if now[k] then G[k] = nil elseif was[k] and not G[k] then G[k] = GetTime() end
    end
    if G.rested and GetTime() - G.rested >= 15 then G.rested = nil; pendingWarn.bag = "Well-Rested (Sleeping Bag) has run out." end
    if G.boost and GetTime() - G.boost >= 15 then
        G.boost = nil
        if now.lowRested then pendingWarn.tent = "Camp Tent works again – your rested is under 5%." end
    end
    if gone("bagCd") and not now.rested then pendingWarn.bagReady = "Your Cozy Sleeping Bag is ready again." end
    if InCombatLockdown() then return end
    if ns.QuietHere() then wipe(pendingWarn) return end   -- in town: nothing to say
    -- only what's still true now (it may have come back since it was noted)
    if now.fed or now.eating then pendingWarn.fed = nil end
    if now.rested then pendingWarn.bag = nil end
    if now.boost then pendingWarn.tent = nil end
    if now.bagCd then pendingWarn.bagReady = nil end
    if (now.food or 0) > 0 then pendingWarn.food = nil end
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
        for _, c in ipairs(CAMPFIRES) do if c[1] == id then return "fire" end end
        if id == CAMP_TENT or CAMP_KNOWN[id] then return "tent" end
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
        if T.IsTradeSkillGuild and Plain(T.IsTradeSkillGuild()) == true then return end     -- a guild view
        if T.IsNPCCrafting and Plain(T.IsNPCCrafting()) == true then return end             -- an NPC's
        local found, learned = {}, 0
        for _, rid in ipairs(T.GetAllRecipeIDs() or {}) do
            local okI, info = pcall(T.GetRecipeInfo, rid)
            local okS, sch = false, nil
            if okI and type(info) == "table" and info.learned then
                learned = learned + 1
                okS, sch = pcall(T.GetRecipeSchematic, rid, false)
            end
            if okS and type(sch) == "table" then
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
        return prof, found, learned
    end

    -- Keep what was found. A list that isn't all there yet (fewer recipes than last time – still loading, or the
    -- window closed) only adds; nothing you know is ever taken away by an empty or half list.
    local function Keep(mine, prof, found, seen)
        if seen <= 0 then return end
        mine.seen = mine.seen or {}
        local full = seen >= (mine.seen[prof] or 0)
        if full then
            mine.seen[prof] = seen
            for id, r in pairs(mine.items) do if r.prof == prof and not found[id] then mine.items[id] = nil end end
        end
        for id, r in pairs(found) do mine.items[id] = r end
        mine.profs[prof] = time()
        ns.LevelDirty()
    end

    local function Scan()
        local mine = Mine()
        local prof, found
        if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
            local seen
            prof, found, seen = ScanModern()
            if prof then Keep(mine, prof, found, seen or 0) return end
        end
        if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillItemLink) then return end
        prof = Plain(GetTradeSkillLine and (GetTradeSkillLine()))
        if type(prof) ~= "string" or prof == "" or prof == "UNKNOWN" then return end
        found = {}
        local seen = 0
        for i = 1, (tonumber(Plain(GetNumTradeSkills())) or 0) do
            local ok, name, kind = pcall(GetTradeSkillInfo, i)
            name, kind = Plain(name), Plain(kind)
            if ok and type(name) == "string" and kind ~= "header" then
                seen = seen + 1
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
        Keep(mine, prof, found, seen)
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
            local idx = { GetProfessions() }
            for i = 1, 6 do   -- (nil where you have none – archaeology – so not ipairs: it would stop there)
                local ok, name = false, nil
                if idx[i] then ok, name = pcall(GetProfessionInfo, idx[i]) end
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
        -- (TRADE_SKILL_UPDATE / LIST_UPDATE keep coming while you craft: not those)
        for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
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
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_ENTERING_WORLD", "TOYS_UPDATED",
                         "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "GET_ITEM_INFO_RECEIVED",
                         "PLAYER_REGEN_ENABLED" }) do
        pcall(bagEvents.RegisterEvent, bagEvents, e)
    end
    -- your auras only (all units' would wake this for every nameplate in a busy city)
    if not pcall(bagEvents.RegisterUnitEvent, bagEvents, "UNIT_AURA", "player") then
        pcall(bagEvents.RegisterEvent, bagEvents, "UNIT_AURA")
    end
    if not pcall(bagEvents.RegisterUnitEvent, bagEvents, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        pcall(bagEvents.RegisterEvent, bagEvents, "UNIT_SPELLCAST_SUCCEEDED")
    end
    local timed = ns.Timed(function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" and ns.OnCampCast then pcall(ns.OnCampCast, spellID) end
        elseif event == "UNIT_AURA" then
            -- your buffs changed: they're read again (each read makes a new table per buff, so not every second)
            if unit == "player" then statusCache.dirty = true; ns.auraGen = (ns.auraGen or 0) + 1 end
        elseif event == "PLAYER_REGEN_ENABLED" then
            ns.combatEnd = GetTime()
            if C_Timer then C_Timer.After(3.2, function() statusCache.dirty = true; ns.auraGen = (ns.auraGen or 0) + 1 end) end   -- a good look then
        elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" or event == "PLAYER_LEVEL_UP" then
            statusCache.dirty = true
        else
            -- after a loading screen (an instance, a /reload) the bags can read empty for a moment: wait a little
            if event == "PLAYER_ENTERING_WORLD" then bagState.loadingUntil = GetTime() + 5; ns.auraGen = (ns.auraGen or 0) + 1 end
            bagState.dirty, statusCache.dirty = true, true
        end
    end, "bags & XP events")
    bagEvents:SetScript("OnEvent", function(self, event, ...)
        -- item text arriving (it can come by the hundred at an auction house): only a flag, nothing timed
        if event == "GET_ITEM_INFO_RECEIVED" then
            if bagState.pending then bagState.dirty = true end   -- an item's text we waited for has come
            return
        end
        timed(self, event, ...)
    end)
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

ns.PlayerPos = PlayerPos
-- Your spot on the map as "45,62" (nil in dungeons and where the map has none).
function ns.Coords()
    local map, x, y = PlayerPos()
    if not (map and x and y) or (x == 0 and y == 0) then return nil end
    return ("%d,%d"):format(math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
end
-- Where a player was last seen: "Arathi Highlands 45,62" (or just the zone, or nil).
function ns.WhereSeen(r)
    if not r then return nil end
    local w = (r.zone or "") .. (r.pos and ((r.zone and " " or "") .. r.pos) or "")
    return w ~= "" and w or nil
end

function ns.CampFireNear()
    if auraCache.found and auraCache.found.campfire then return true end
    if not campFire.at or GetTime() - campFire.at > 600 then return false end
    local map, x, y = PlayerPos()
    -- a few yards only (0.01 of a zone map was ~30 yards: too far for the fire to count)
    if map and campFire.map and (map ~= campFire.map or math.abs(x - campFire.x) + math.abs(y - campFire.y) > 0.0035) then
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

-- Worked out again after a change to your buffs, bags or XP (but never more than three times a second), else every
-- 5 seconds: the bars refresh on lots of events, and each look makes new tables. The icons' clocks count down by
-- themselves in between (row.ends).
local ComputeLevelStatus
function ns.LevelStatus()
    local since = GetTime() - statusCache.at
    if since < 5 and not (statusCache.dirty and since >= 0.3) then return statusCache.rows end
    statusCache.rows = ComputeLevelStatus()
    statusCache.at, statusCache.dirty = GetTime(), false
    ns.levelVersion = (ns.levelVersion or 0) + 1   -- the icons repaint when this changes
    return statusCache.rows
end

ComputeLevelStatus = function()
    local level = tonumber(Plain(UnitLevel("player"))) or 0
    if level <= 0 or level >= ns.MaxLevel() then return nil end
    ReadBags()
    -- in a fight (and a moment either side of it) buffs can read hidden: the last good look is used then, and a
    -- look that couldn't make out every buff never replaces a good one
    local unsure = ns.AurasUnsure()
    -- read again only when something changed (UNIT_AURA, bags, XP, a fight ended) or it's 10 s old: the times count
    -- down from the last read (each read makes a new table for every buff on you)
    local stale = statusCache.dirty or not auraCache.found or GetTime() - auraCache.at >= 10
    if stale and (not unsure or not auraCache.found) then
        local ok, found = pcall(ReadAuras)
        if ok and not (found.unreadable and auraCache.found) then auraCache.found, auraCache.at = found, GetTime() end
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
    seen.unsure = (unsure or (auraCache.found and auraCache.found.unreadable)) and true or nil   -- no news from this look
    seen.eating = auraCache.found and auraCache.found.eating or nil
    seen.long = auraCache.found and auraCache.found.long or nil
    local name, icon, slot, use, options
    local function add(state, text, tip, timer, count)
        rows[#rows + 1] = { state = state, name = name, icon = icon, text = text, tip = tip, timer = timer,
            ends = timer and (GetTime() + timer) or nil,   -- (the icons count down from this between two looks)
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
    seen.boostLeft = boost and boost.left or nil
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
    -- the camp feature (they share one hour) or the fire you'd put down: on cooldown?
    local cdItem = (feat and not feat.craft and feat) or (use and not use.craft and use) or nil
    local cs, cd = nil, nil
    if cdItem then cs, cd = ns.ItemCooldown(cdItem.id) end
    local cdLeft = cs and math.max(0, cs + cd - GetTime()) or 0
    if boost then
        add("wait", "Boosted Rest – you can use another tent when it's gone.", tentTip, boost.left)
    elseif cdLeft > 0 and pct < 5 then
        add("wait", cdItem.name .. " is on cooldown – ready again when the clock runs out (camp features share one hour).",
            tentTip, cdLeft)
    elseif pct < 5 then
        add("todo", "Your rested is under 5%." .. ((tents > 0 or (use and use.craft)) and how or " You have no Camp Tent."), tentTip, nil, tents)
    else
        add("ok", ("Not needed – you have %d%% rested."):format(math.floor(pct + 0.5)) .. how, tentTip)
    end
    rows[#rows].picks, rows[#rows].fireNear = picks, near
    rows[#rows].cdStart, rows[#rows].cdDur = cs, cd   -- (the swipe on the icon)

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
    -- the extra XP you have now, for the strip: XP food +5 %, the sleeping bag +1 % a stack; rested on top (double
    -- XP from kills while it lasts – the tent fills it)
    ns.levelBonus = { food = fed and 5 or 0, bag = wr and math.max(1, math.min(3, wr.stacks or 1)) or 0,
        rested = seen.restedPct or 0, tent = seen.boost and true or false }
    name, icon, slot = "Cozy Sleeping Bag", ItemIcon(SLEEPING_BAG) or SpellIcon(WELL_RESTED) or "Interface\\Icons\\Spell_Nature_Sleep", "bag"
    local bags, toy = ItemCount(SLEEPING_BAG)
    options = {}
    if bags > 0 then options[1] = { id = SLEEPING_BAG, name = ItemName(SLEEPING_BAG, "Cozy Sleeping Bag"), count = bags, toy = toy } end
    use = options[1]
    local bagS, bagD = nil, nil
    if bags > 0 then bagS, bagD = ns.ItemCooldown(SLEEPING_BAG) end
    if wr then
        local st = math.max(1, math.min(3, wr.stacks))
        icon = ItemIcon(SLEEPING_BAG) or SpellIcon(WELL_RESTED) or icon   -- the bag, not the buff
        -- full, but the bag is ready again: lying on it sets the timer back to 2 hours
        local renew = st >= 3 and bags > 0 and wr.left and wr.left < 6900 and ItemCooldownLeft(SLEEPING_BAG) <= 0
        add((st >= 3 and not renew) and "ok" or "wait", ("Well-Rested %d/3: +%d%% XP."):format(st, st)
            .. (st < 3 and " Keep lying on the bag for the full +3%." or "")
            .. (renew and " |cffffd100The bag is ready: lie on it again to set the timer back to 2 hours.|r" or "")
            .. ((not renew and bagS) and ("\nThe bag is on cooldown – the shade on the icon shows when it's ready.") or ""),
            bagTip, wr.left, st)
        rows[#rows].cdStart, rows[#rows].cdDur = bagS, bagD
    elseif bags > 0 then
        local cd = ItemCooldownLeft(SLEEPING_BAG)
        seen.bagCd = cd > 0 or nil
        if cd > 0 then add("wait", "On cooldown – ready again when the clock runs out.", bagTip, cd)
            rows[#rows].cdStart, rows[#rows].cdDur = bagS, bagD
        else add("todo", "Ready – lie on it for 3 minutes.", bagTip) end
    elseif level >= 14 then
        add("info", "You don't have one yet – a quest chain from level 14.", bagTip .. "\n\nThe chain starts at Alexston "
            .. "Farmstead in Westfall (Alliance) or the Burned-Out Remains in the Barrens (Horde).")
    end
    -- the camp: Camp Benefits and what it gave you, or the minute of sitting for it – shown in the "+%" box
    -- (ns.levelCamp: when it ends, its effects line by line, when the sitting minute ends)
    local cf = auraCache.found or {}
    local campOn = cf.camp and cf.camp.expires - GetTime() > 0
    local sitOn = cf.welcome and cf.welcome.expires - GetTime() > 0
    ns.levelCamp = (campOn or sitOn) and {
        expires = campOn and cf.camp.expires or nil,
        lines = campOn and ns.CampEffects(cf.camp, cf.hour) or nil,
        sitExpires = sitOn and cf.welcome.expires or nil,
    } or nil
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
        if name == nil and Plain(sid) ~= nil then   -- the name hidden, the spell ID not: its name from the spell
            local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
            local ok, n = pcall(get or function() end, Plain(sid))
            name = ok and Plain(n) or nil
        end
        if name == nil then out.unreadable = true end   -- there, but hidden: an unsure read
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
local BUFF_GRACE = 10

-- Can WatchX trust a look at your buffs right now? Not in a fight, nor in the first seconds after one (buffs can
-- read hidden then, and an empty look would say everything ran out). On ns: the main chunk is at the locals limit.
function ns.AurasUnsure()
    if InCombatLockdown() or Plain(UnitAffectingCombat("player")) == true then return true end
    return ns.combatEnd ~= nil and GetTime() - ns.combatEnd < 3
end
local buffPendingGone, buffSelfRenew = {}, {}

local function BuffGoneNow(k, t, now)
    buffTracked[k] = nil
    buffPendingGone[k] = { t = t, at = now }
end

function ns.CheckBuffs()
    if db.buffWarn == false then wipe(buffTracked); wipe(buffPendingGone) return end
    if Plain(UnitIsDeadOrGhost("player")) == true then wipe(buffTracked); wipe(buffPendingGone) return end   -- dying took them
    local now, soon = GetTime(), tonumber(db.buffSoon) or 60
    local fight = ns.AurasUnsure()
    if not fight then
        -- the last read, unless your buffs changed since (UNIT_AURA) or it's 10 s old (a read makes a table per buff)
        local B = ns.buffRead
        local ok, list
        if B and B.gen == ns.auraGen and now - B.at < 10 then
            ok, list = true, B.list
        else
            ok, list = pcall(ReadBuffs)
            if ok and not list.unreadable then ns.buffRead = { list = list, gen = ns.auraGen, at = now } end
        end
        if ok and list.unreadable then fight = true end   -- couldn't make them all out: no conclusions this time
        if ok and not fight then
            local here = {}
            for _, a in ipairs(list) do
                local g = a.expires > 0 and ns.BuffGroup(a)
                if g then
                    local k = a.name:lower()
                    here[k] = true
                    local p = buffPendingGone[k]
                    if p then
                        buffPendingGone[k] = nil
                        -- back within a couple of checks with the same length: it renews by itself (camp buffs by
                        -- the fire) – for one more round only; put back by hand later, it keeps its warnings
                        if now - p.at <= 3 and math.abs((p.t.dur or 0) - (a.dur or 0)) <= 1 then
                            buffSelfRenew[k] = now + (a.dur or 0) + 30
                        end
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
            -- (in a fight it can't be seen: it may have been renewed – the first good look after the fight decides)
        elseif not t.soon and soon > 0 and left <= soon and t.dur > soon + 5 and not (buffSelfRenew[k] and now < buffSelfRenew[k]) then
            t.soon = true
            if not ns.QuietHere() then Warn(BuffMsg(t, left)) end
        end
    end
    for k, p in pairs(buffPendingGone) do
        if now - p.at >= BUFF_GRACE and not fight then   -- still gone in a look it can trust
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
    local r = ns.EnemyRecord(key, not db.enemies[key] and ns.ProperName((Trim(name):gsub("%-", " "))) or nil)
    r.avoid = on and true or nil
    note = Trim(note or "")
    if note ~= "" then r.note = note end
    ns.AvoidChanged()
    Print(on and ("|cffff8040Avoid|r: " .. r.name .. (r.note and (" – " .. r.note) or ""))
        or ("No longer on your avoid list: " .. r.name))
    ns.historyDirty, ns.kosDirty = true, true   -- an open History / PvP page follows
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
    local OPEN_DAYS, CLAIMED_DAYS, GONE_DAYS = 14, 3, 15
    local FOREIGN_MAX, PER_POSTER_MAX = 200, 20   -- bounties from others kept at most (all, and per poster)

    -- Text from the network or typed: no control characters, no "|" (escape codes: icons, links), no "~" (our
    -- separator); cut at a letter boundary (UTF-8).
    local function Clean(s, n)
        if type(s) ~= "string" and type(s) ~= "number" then return nil end
        s = Trim((tostring(s)):gsub("[%c|~]", " "))
        if s == "" then return nil end
        if #s > n then s = (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", "")) end
        return s ~= "" and s or nil
    end
    -- A player key: "First-Last" or "First" – letters only (any language), one hyphen at most.
    local function ValidKey(k)
        return type(k) == "string" and #k >= 2 and #k <= 40 and k:find("^[%a\128-\255]+%-?[%a\128-\255]*$") ~= nil
    end
    -- A name the game would take: first name and surname 2–12 letters each (letters only – æ ø å é count), never
    -- three of the same letter in a row, and nothing rude (WoW refuses those names anyway). nil = fine, else why not.
    local RUDE_PART = { kuk = 1, pikk = 1, fitte = 1, hore = 1, faen = 1, suge = 1, sug = 1, dritt = 1, homo = 1,
        neger = 1, fuck = 1, shit = 1, cunt = 1, dick = 1, cock = 1, pussy = 1, penis = 1, vagina = 1, whore = 1,
        slut = 1, bitch = 1, fag = 1, faggot = 1, rape = 1, rapist = 1, nazi = 1, hitler = 1, suck = 1, sucker = 1,
        anal = 1, anus = 1, porn = 1, sex = 1, tits = 1, cum = 1, nigger = 1, nigga = 1, retard = 1, wank = 1,
        -- the same in the other languages people play in (the game has its own filter; this stops the obvious)
        fick = 1, ficken = 1, scheisse = 1, schlampe = 1, hure = 1, fotze = 1, wichser = 1, arsch = 1, schwanz = 1,
        nutte = 1, spast = 1, merde = 1, pute = 1, salope = 1, connard = 1, conne = 1, encule = 1, bite = 1,
        chatte = 1, nique = 1, batard = 1, puta = 1, puto = 1, mierda = 1, cabron = 1, cono = 1, polla = 1,
        pendejo = 1, maricon = 1, joder = 1, verga = 1, cazzo = 1, merda = 1, stronzo = 1, figa = 1, fitta = 1,
        hora = 1, javla = 1, knulla = 1, kneppe = 1, pik = 1, fisse = 1, luder = 1, kut = 1, lul = 1, hoer = 1,
        kanker = 1, tering = 1, kurwa = 1, chuj = 1, pizda = 1, jebac = 1 }
    local RUDE_IN = { "fuck", "cunt", "nigg", "fitte", "faggot", "whore", "hitler", "kuken", "kurwa", "fotze",
        "wichser", "hurensohn", "arschloch", "putain", "vaffanculo", "puttana", "klootzak", "hijodeputa", "jebac",
        "хуй", "хуе", "пизд", "бляд", "ебат", "ёб", "сука", "мудак", "пидор" }   -- even inside a name (Cyrillic too)
    -- small letters for the comparison: A–Z, and Cyrillic А–Я / Ё (two bytes each in UTF-8)
    local function Low(s)
        s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)   -- (not :lower(): a locale may touch UTF-8 bytes)
        s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)   -- А–П
        s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)   -- Р–Я
        return (s:gsub("\208\129", "\209\145"))                                                        -- Ё
    end
    function ns.NameProblem(name)
        if type(name) ~= "string" then return "That isn't a name." end
        local parts = {}
        for part in name:gmatch("[^%s%-]+") do parts[#parts + 1] = part end
        if #parts == 0 then return "Put in a name." end
        if #parts > 2 then return "A name is a first name and a surname – no more." end
        for _, part in ipairs(parts) do
            if not part:find("^[%a\128-\255]+$") then return "Names are letters only: " .. part end
            local letters = select(2, part:gsub("[^\128-\191]", ""))   -- (letters, not bytes: æ ø å are two bytes)
            if letters < 2 or letters > 12 then return "Each name is 2 to 12 letters: " .. part end
            local low = Low(part)
            if low:find("(%a)%1%1") then return "WoW doesn't allow three of the same letter in a row: " .. part end
            if RUDE_PART[low] then return "That isn't a name WoW would allow." end
            for _, w in ipairs(RUDE_IN) do if low:find(w, 1, true) then return "That isn't a name WoW would allow." end end
        end
        return nil
    end
    -- A whole number within limits, or nil.
    local function Int(v, lo, hi)
        v = tonumber(v)
        if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
        return v
    end
    local function Norm(n) return type(n) == "string" and (n:gsub("%s+", "-")):lower() or nil end
    local function First(n) return n and (n:match("^[^%-]+")) or n end
    local function Me()
        local n = Plain(UnitName("player"))
        return type(n) == "string" and n or "?"
    end
    local function On() return db and db.wantedOn ~= false end
    -- Your name as other players' games show it: "First-Surname" when known (from the game, or learned from
    -- your own message coming back in the guild channel).
    local function MyFull()
        if ns.myFull then return ns.myFull end
        local n, r = UnitName("player")
        n, r = Plain(n), Plain(r)
        if type(n) ~= "string" then return Me() end
        if type(r) == "string" and r ~= "" then return n .. "-" .. r end
        return n
    end
    -- The same player? Full names must match; when one side has no surname (old saves), the first names do.
    local function Same(a, b)
        a, b = Norm(a), Norm(b)
        if not a or not b then return false end
        if a == b then return true end
        if not a:find("-", 1, true) or not b:find("-", 1, true) then return First(a) == First(b) end
        return false
    end
    local function IsMe(name) return Same(name, MyFull()) end
    ns.IsMe = IsMe
    local function Show(name) return name and (name:gsub("%-", " ")) or "?" end   -- "First Last" for the eye

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

    -- Your bounties in guild chat, when ticked: posted, claimed, paid – with the reward. Only the one who put it up
    -- says it (else every WatchX in the guild would). Plain words: chat takes no colours or coin icons.
    local function Announce(msg)
        if not (db.wantedAnnounce and IsInGuild and Plain(IsInGuild()) == true) then return end
        local ok = pcall(SendChat, msg:sub(1, 250), "GUILD")
        if not ok then Log("announce failed") end
    end
    local function Gold(c)
        c = math.floor(tonumber(c) or 0)
        local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
        local t = {}
        if g > 0 then t[#t + 1] = g .. "g" end
        if sv > 0 then t[#t + 1] = sv .. "s" end
        if cp > 0 or #t == 0 then t[#t + 1] = cp .. "c" end
        return table.concat(t, " ")
    end
    local function RewardWords(w) return (w.copper and w.copper > 0) and Gold(w.copper) or tostring(w.reward or "a reward") end
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

    -- Is this bounty yours? Only the one who put it up can change it, take it down or mark it paid.
    function ns.WantedMine(w) return w and (w.by == nil or IsMe(w.by)) or false end
    -- A bounty can be for several kills (w.kills, the reward is per kill). Every kill claimed on it:
    -- { by, full, t, zone, paid } – in w.claims, or (one kill, as always) w.claimed / w.paid.
    local MAX_KILLS = 50
    local function Limit(w) return math.max(1, math.min(MAX_KILLS, math.floor(tonumber(w and w.kills) or 1))) end
    local function Claims(w)
        if not w then return {} end
        if w.claims then return w.claims end
        if w.claimed then
            local c = w.claimed
            return { { by = c.by, full = c.full, t = c.t, zone = c.zone, paid = w.paid, one = true } }
        end
        return {}
    end
    local function IsOpen(w) return w ~= nil and #Claims(w) < Limit(w) end
    local function Last(w) local c = Claims(w); return c[#c] end
    -- What's owed, per claimer: { { full, n, copper, t (the latest kill) }, ... }, oldest first.
    local function Debts(w)
        local by, out = {}, {}
        for _, c in ipairs(Claims(w)) do
            if not c.paid then
                local who = c.full or c.by
                local k = Norm(who) or "?"
                local e = by[k]
                if not e then e = { full = who, n = 0, copper = 0, t = c.t or 0 }; by[k] = e; out[#out + 1] = e end
                e.n = e.n + 1
                e.copper = e.copper + math.floor(w.copper or 0)
                e.t = math.max(e.t, c.t or 0)
            end
        end
        table.sort(out, function(a, b) return a.t < b.t end)
        return out
    end
    -- All kills in and all paid: nothing more to happen.
    local function Settled(w) return w ~= nil and not IsOpen(w) and #Debts(w) == 0 end
    local function ClaimedByMe(w)
        for _, c in ipairs(Claims(w)) do if IsMe(c.full or c.by) then return true end end
        return false
    end
    -- How it stands, for the lists: open, kills, limit, what you owe, what you're owed (copper), the latest kill.
    function ns.WantedState(w)
        local st = { open = IsOpen(w), kills = #Claims(w), limit = Limit(w), last = Last(w), owe = 0, owed = 0, debts = Debts(w) }
        local mine = ns.WantedMine(w)
        for _, e in ipairs(st.debts) do
            if mine and not IsMe(e.full) then st.owe = st.owe + e.copper end
            if not mine and IsMe(e.full) then st.owed = st.owed + e.copper end
        end
        st.settled = not st.open and #st.debts == 0
        return st
    end
    ns.WantedDebts = Debts
    ns.ClaimedByMe = ClaimedByMe
    ns.MyName = MyFull
    -- A kill claimed: one kill = the earliest wins (then the name), the same on every client; several = each kill
    -- counts once (claimer + time), the earliest ones up to the limit. True when it was new.
    local function AddClaim(w, c)
        if w.by and Same(c.full or c.by, w.by) then return false end   -- your own bounty can't be claimed by you
        if Limit(w) == 1 and not w.claims then
            local o = w.claimed
            if o and ((o.t or 0) < c.t or ((o.t or 0) == c.t and Norm(o.full or o.by) <= Norm(c.full or c.by))) then return false end
            w.claimed = { by = c.by, full = c.full, t = c.t, zone = c.zone }
            return true
        end
        w.claims = w.claims or {}
        for _, o in ipairs(w.claims) do
            if Norm(o.full or o.by) == Norm(c.full or c.by) and math.abs((o.t or 0) - (c.t or 0)) <= 2 then
                if c.paid and not o.paid then o.paid = c.paid; return true end
                return false
            end
        end
        local new = { by = c.by, full = c.full, t = c.t, zone = c.zone, paid = c.paid }
        table.insert(w.claims, new)
        table.sort(w.claims, function(x, y)
            if (x.t or 0) ~= (y.t or 0) then return (x.t or 0) < (y.t or 0) end
            return (Norm(x.full or x.by) or "") < (Norm(y.full or y.by) or "")
        end)
        while #w.claims > Limit(w) do table.remove(w.claims) end   -- over the limit: the latest kills don't count
        for _, o in ipairs(w.claims) do if o == new then return true end end
        return false
    end
    -- Paid: a claimer's kills up to a time (nil: all of them).
    local function PayClaims(w, who, upto)
        local any = false
        if w.claims then
            for _, c in ipairs(w.claims) do
                if not c.paid and (not who or Same(c.full or c.by, who)) and (not upto or (c.t or 0) <= upto) then c.paid = time(); any = true end
            end
        elseif w.claimed and not w.paid and (not who or Same(w.claimed.full or w.claimed.by, who)) then
            w.paid = time(); any = true
        end
        if w.claims and not IsOpen(w) and #Debts(w) == 0 then w.paid = w.paid or time() end
        return any
    end
    local function KillsWords(w) local n = Limit(w) return n > 1 and (" (kill " .. #Claims(w) .. "/" .. n .. ")") or "" end

    -- The bounty on this player (still open), or nil. A bounty on just a first name ("Bob") counts for any Bob.
    function ns.Wanted(key)
        if not (key and db and On()) then return end
        local r = db.enemies[key]
        local w = r and r.wanted
        if w and IsOpen(w) then return w, r end
        local first = key:match("^([^%-]+)%-")
        local fr = first and db.enemies[first]
        if fr and fr.wanted and IsOpen(fr.wanted) then return fr.wanted, fr, first end
    end
    -- A line for tooltips and lists.
    function ns.WantedLine(w)
        if not w then return "" end
        local rw = ns.WantedReward(w)
        local s = "|cffffa000WANTED|r" .. (rw and (" |cffffd100" .. rw .. (Limit(w) > 1 and " a kill" or "") .. "|r") or "")
            .. (w.by and ("|cffaaaaaa by " .. Show(w.by) .. "|r") or "") .. (w.note and (" – " .. w.note) or "")
        if Limit(w) > 1 then
            local st = ns.WantedState(w)
            s = s .. "  |cffffd100" .. st.kills .. "/" .. st.limit .. " kills|r"
            if st.owe > 0 then s = s .. "  |cffff8040· you owe " .. Money(st.owe) .. "|r"
            elseif st.owed > 0 then s = s .. "  |cffffd100· " .. Show(w.by) .. " owes you " .. Money(st.owed) .. "|r"
            elseif st.settled then s = s .. "  |cff40ff40· all paid|r" end
            return s
        end
        if w.claimed then
            local mine, byMe = ns.WantedMine(w), ClaimedByMe(w)
            s = s .. "  |cff40ff40claimed by " .. (byMe and "you" or Show(w.claimed.by)) .. "|r"
            if w.paid then s = s .. "  |cff40ff40· paid|r"
            elseif mine and not byMe then s = s .. "  |cffff8040· you owe " .. (rw or "?") .. " – pay at a mailbox|r"
            elseif byMe and not mine then s = s .. "  |cffffd100· " .. Show(w.by) .. " owes you " .. (rw or "?") .. "|r"
            elseif not mine then s = s .. "  |cffaaaaaa· not paid yet|r" end
        end
        return s
    end

    -- Bounty news: a card like the stealth one (and a chat line); at most one card every few seconds (the rest only
    -- in chat), the plain mid-screen warning if there's no card.
    local function Card(kind, who, reward, from, msg, class)
        if ns.AddBountyNews then ns.AddBountyNews(kind, who, reward, from, msg) end
        local now = GetTime()
        if now - (ns.lastBountyCard or -100) < 4 then Print("|cffffa000" .. msg .. "|r") return end
        ns.lastBountyCard = now
        if ns.BountyCard and ns.BountyCard(kind, who, reward, from, class) then Print("|cffffa000" .. msg .. "|r")
        else Warn(msg) end
    end

    -- The lists follow at once, but at most once per 0.2 s however many messages come in.
    local function Changed()
        if ns.wantedRefresh then return end
        ns.wantedRefresh = true
        C_Timer.After(0.2, function()
            ns.wantedRefresh = nil
            if ns.RefreshUI then ns.RefreshUI() end
            if ns.RefreshHistory then ns.RefreshHistory() end
        end)
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
        local mine, byMe = ns.WantedMine(w), ClaimedByMe(w)
        tip:AddLine(" ")
        tip:AddDoubleLine("|cffffa000WANTED|r " .. rw .. (Limit(w) > 1 and (" a kill, " .. Limit(w) .. " kills") or ""),
            (mine and "by you" or ("by " .. Show(w.by))) .. ", " .. Ago(w.t), 1, 1, 1, 0.7, 0.7, 0.7)
        if Limit(w) > 1 then
            local claims = Claims(w)
            if not IsOpen(w) then tip:AddLine("All " .. Limit(w) .. " kills are in.", 0.6, 0.6, 0.6)
            elseif not w.forever then tip:AddLine("Ends in " .. math.max(0, math.ceil(((w.t or time()) + OPEN_DAYS * 86400 - time()) / 86400)) .. " days", 0.6, 0.6, 0.6) end
            if w.note then tip:AddLine("\"" .. w.note .. "\"", 1, 0.85, 0.5, true) end
            for i = #claims, math.max(1, #claims - 5), -1 do
                local c = claims[i]
                tip:AddDoubleLine("|cff40ff40Kill " .. i .. ":|r " .. (IsMe(c.full or c.by) and "you" or Show(c.by)) .. (c.zone and ("  |cff999999" .. c.zone .. "|r") or ""),
                    (c.paid and "|cff40ff40paid|r  " or "") .. Ago(c.t), 1, 1, 1, 0.7, 0.7, 0.7)
            end
            for _, e in ipairs(Debts(w)) do
                if mine and not IsMe(e.full) then tip:AddLine("You owe " .. Money(e.copper) .. " to " .. Show(e.full) .. " (" .. e.n .. (e.n == 1 and " kill" or " kills") .. ") – a Pay button shows at the mailbox.", 1, 0.5, 0.25, true)
                elseif not mine and IsMe(e.full) then tip:AddLine(Show(w.by) .. " owes you " .. Money(e.copper) .. " (" .. e.n .. (e.n == 1 and " kill" or " kills") .. ").", 1, 0.82, 0, true) end
            end
            return
        end
        if not w.claimed then
            tip:AddLine(w.forever and "No end date – until it's claimed or taken down"
                or ("Ends in " .. math.max(0, math.ceil(((w.t or time()) + OPEN_DAYS * 86400 - time()) / 86400)) .. " days if nobody claims it"), 0.6, 0.6, 0.6)
        end
        if w.note then tip:AddLine("\"" .. w.note .. "\"", 1, 0.85, 0.5, true) end
        local c = w.claimed
        if c then
            tip:AddDoubleLine("|cff40ff40Killed by " .. (byMe and "you" or Show(c.by)) .. "|r", Ago(c.t), 1, 1, 1, 0.7, 0.7, 0.7)
            if c.zone then tip:AddLine("in " .. c.zone, 0.7, 0.7, 0.7) end
            if c.t then tip:AddLine(date("%d.%m %H:%M", c.t), 0.5, 0.5, 0.5) end
            if w.paid then tip:AddDoubleLine("|cff40ff40Paid|r", Ago(w.paid), 1, 1, 1, 0.7, 0.7, 0.7)
            elseif mine and not byMe then tip:AddLine("You owe " .. rw .. " to " .. Show(c.full or c.by) .. " – a Pay button shows at the mailbox.", 1, 0.5, 0.25, true)
            elseif byMe and not mine then tip:AddLine(Show(w.by) .. " owes you " .. rw .. ".", 1, 0.82, 0, true)
            elseif not mine then tip:AddLine("Not paid yet.", 0.7, 0.7, 0.7) end
        end
    end

    -- ---- sending: to the guild and to each online friend. The game lets a burst through and then about one a
    -- second, so: 8 quickly, then one a second. A sync message that someone else already sent meanwhile is skipped.
    local queue, sender = {}, CreateFrame("Frame")
    local wait, burst = 0, 8
    local recent = {}   -- key..t -> time it was last sent or heard (no echo storms when syncing)
    sender:Hide()
    sender:SetScript("OnUpdate", function(self, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        local m = table.remove(queue, 1)
        if not m then self:Hide() burst = 8 return end
        if m.rk and recent[m.rk] and recent[m.rk] > m.at then wait = 0 return end   -- someone else just sent it
        if burst > 0 then burst, wait = burst - 1, 0.15 else wait = 1 end
        local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.msg, m.chan, m.to)
        if not ok then Log("wanted", "send failed", m.chan) end
    end)
    local friends, friendList, friendsAt = {}, {}, -100   -- lower-case name -> true; online ones; when read
    local function Friends()
        if GetTime() - friendsAt < 30 then return friendList end
        friendsAt = GetTime()
        wipe(friends); wipe(friendList)
        if not (C_FriendList and C_FriendList.GetNumFriends) then return friendList end
        for i = 1, (Plain(C_FriendList.GetNumFriends()) or 0) do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            local name = ok and info and Plain(info.name)
            if type(name) == "string" and name ~= "" then
                friends[Norm(name)] = true
                if Plain(info.connected) == true then friendList[#friendList + 1] = name end
            end
        end
        return friendList
    end
    local function IsFriend(name)
        Friends()
        local n = Norm(name)
        if not n then return false end
        if friends[n] then return true end
        -- the list (or the sender) without surnames: the first name counts, if only one friend has it and the list
        -- doesn't know a different surname for him
        local f, hits, surname = First(n), 0, false
        for k in pairs(friends) do
            if First(k) == f then hits = hits + 1; if k:find("-", 1, true) then surname = true end end
        end
        if surname and n:find("-", 1, true) then return false end
        return hits == 1
    end
    local function Send(fields, rk)
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
        local msg = table.concat(fields, SEP)
        local now = time()
        if db.wantedGuild ~= false and Plain(IsInGuild and IsInGuild()) == true then
            queue[#queue + 1] = { msg = msg, chan = "GUILD", rk = rk, at = now }
        end
        if db.wantedFriends ~= false then
            for _, name in ipairs(Friends()) do queue[#queue + 1] = { msg = msg, chan = "WHISPER", to = name, rk = rk, at = now } end
        end
        sender:Show()
    end
    -- One bounty, in the order the protocol has always had; the note is cut to keep it under the 255-byte limit.
    local function SendAdd(key, r, fromSync)
        local w = r.wanted
        local rk = key .. (w.t or 0)
        if not fromSync then recent[rk] = time() end
        local c = Limit(w) == 1 and w.claimed or nil   -- (several kills: the claims go one by one, as R)
        local f = { VER, "A", key, r.name or key, r.class or "", (w.copper and tostring(w.copper)) or w.reward or "", "",
            w.by or MyFull(), w.t or 0, c and c.by or "", c and c.t or 0, c and c.full or "", (c and w.paid) and tostring(w.paid) or "0",
            c and (Clean(c.zone, 40) or "") or "", w.forever and 1 or 0, Limit(w) }
        local room = 250 - #table.concat(f, SEP)
        local note = w.note or ""
        if #note > room then note = room > 0 and (note:sub(1, room):gsub("[\192-\255][\128-\191]*$", "")) or "" end
        f[7] = note
        Send(f, fromSync and rk or nil)
        if fromSync then recent[rk] = recent[rk] or 0 end
        if w.claims and fromSync then   -- the kills so far, each with whether it's paid
            for _, cl in ipairs(w.claims) do
                Send({ VER, "R", key, cl.full or cl.by, cl.t or 0, w.t or 0, Clean(cl.zone, 40) or "", cl.paid and 1 or 0 })
            end
        end
    end

    local function ForeignCounts(poster)
        local all, his = 0, 0
        for _, r in pairs(db.enemies) do
            local w = r.wanted
            if w and not ns.WantedMine(w) then
                all = all + 1
                if poster and Same(w.by, poster) then his = his + 1 end
            end
        end
        return all, his
    end
    local function Gone(key) db.wantedGone = type(db.wantedGone) == "table" and db.wantedGone or {}; return db.wantedGone, db.wantedGone[key] end

    -- reward: copper, or text like "50g 20s"; a bounty needs one. forever: no end date (stays until claimed or
    -- taken down).
    function ns.SetWanted(key, name, reward, note, forever, kills)
        if not key then return false end
        kills = math.max(1, math.min(MAX_KILLS, math.floor(tonumber(kills) or 1)))
        key, name = ns.ProperName(key), ns.ProperName(name)   -- "bob-smith" is Bob-Smith
        if not ValidKey(key) then
            local why = "That isn't a player name WatchX can use."
            Print(why .. " (" .. tostring(name or key) .. ")") return false, why
        end
        local bad = ns.NameProblem(key)   -- only names the game would take go on the list (and out to others)
        if bad then Print(bad) return false, bad end
        local copper = type(reward) == "number" and math.floor(reward) or ns.ParseMoney(tostring(reward or ""))
        if not copper or copper <= 0 then
            Print("A bounty needs a reward: gold, silver or copper (e.g. |cffffd100/wx wanted Name: 50g ninja looter|r).")
            return false, "Put in a reward"
        end
        copper = math.min(copper, 1e10)
        local old = db.enemies[key] and db.enemies[key].wanted
        if old and #Debts(old) > 0 then
            local why = "Claimed and not paid yet – settle that first."
            Print("The bounty on " .. (db.enemies[key].name or key) .. ": " .. why) return false, why
        end
        if old and IsOpen(old) and not ns.WantedMine(old) then
            local why = Show(old.by) .. " has a bounty on them – only they can change it."
            Print(why) return false, why
        end
        local r = ns.EnemyRecord(key, name)
        local fresh = not old or old.copper ~= copper or Limit(old) ~= kills   -- (new, or a new reward: said in guild; a note isn't)
        r.wanted = { copper = copper, note = Clean(note, MAX_NOTE), by = MyFull(), t = time(), forever = forever and true or nil,
            kills = kills > 1 and kills or nil }
        r.wantedHide = nil
        local gone = Gone(key)
        gone[key] = nil
        SendAdd(key, r)
        local per = kills > 1 and (" a kill, " .. kills .. " kills") or ""
        Print("|cffffa000WANTED|r posted: " .. r.name .. " – " .. Money(copper) .. per
            .. (r.wanted.note and (" (" .. r.wanted.note .. ")") or "") .. " |cffaaaaaa– sent to your guild and friends|r")
        if fresh then
            local seen = r.lastSeen and ns.WhereSeen and ns.WhereSeen(r)
            seen = seen and (" Last seen: " .. seen .. ", " .. Fmt(math.max(0, time() - r.lastSeen)) .. " ago.") or ""
            Announce("WANTED: " .. r.name .. " – " .. Gold(copper) .. (kills > 1 and (" per kill, up to " .. kills .. " kills") or " reward")
                .. (r.wanted.note and (" (" .. r.wanted.note .. ")") or "") .. ". Kill them and claim it!" .. seen)
        end
        Changed()
        return true
    end

    -- Your own bounty: taken down for everyone (and it won't come back from someone who was offline then).
    -- Someone else's can't be (it goes when it's claimed and paid, or old).
    function ns.RemoveWanted(key)
        local r = key and db.enemies[key]
        if not (r and r.wanted) then return end
        local w = r.wanted
        if not ns.WantedMine(w) then
            Print("Only " .. Show(w.by) .. " can take this bounty down.")
            return false
        end
        Send({ VER, "D", key, w.by or MyFull(), time() })
        local gone = Gone(key)
        gone[key] = { t = w.t or time(), mine = true, at = time() }
        r.wanted = nil
        -- only here for the bounty (never seen, nothing else on it): gone from History too
        if not (r.kos or r.avoid or r.note or (r.seen or 0) > 0 or (r.kills or 0) > 0 or (r.deaths or 0) > 0) then
            db.enemies[key] = nil
        end
        Print("Bounty taken down: " .. (r.name or key))
        Changed()
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
        if ns.WantedMine(w) then   -- your own bounty: no claim (it stays up for someone else to earn)
            Print("You killed |cffffd100" .. (r.name or key) .. "|r – your own bounty, so nothing is claimed; it stays up.")
            return
        end
        local c = { by = MyFull(), full = MyFull(), t = time(), zone = Clean(zone, 40) }
        if not AddClaim(w, c) then return end
        Send({ VER, "C", key, c.by, c.t, w.t or 0, c.full, c.zone or "" })
        local mine = ns.WantedMine(w)
        if mine then Announce("BOUNTY CLAIMED: " .. (r.name or key) .. " was killed by " .. Show(c.by) .. (zone and (" in " .. zone) or "")
            .. KillsWords(w) .. " – " .. RewardWords(w) .. " reward.") end
        Card("bountyKill", r.name or key, ns.WantedReward(w), mine and "yours" or ("from " .. Show(w.by)),
            "Bounty claimed" .. KillsWords(w) .. ": " .. (r.name or key) .. (zone and (" in " .. zone) or "") .. (ns.WantedReward(w) and (" – " .. ns.WantedReward(w)) or "")
            .. (mine and "" or (" from " .. Show(w.by) .. " (they pay by mail)")), r.class)
        Changed()
    end

    -- Paid (by mail, or "Mark paid" after a trade): only the one who put it up.
    function ns.MarkPaid(key, who)
        local r = key and db.enemies[key]
        local w = r and r.wanted
        if not (w and ns.WantedMine(w)) then return false end
        local debts = Debts(w)
        local e
        for _, x in ipairs(debts) do if not who or Same(x.full, who) then e = x; break end end
        if not e then return false end
        local upto = time()
        PayClaims(w, e.full, upto)
        Send({ VER, "P", key, w.by or MyFull(), w.t or 0, e.full, upto })
        local kills = e.n > 1 and (" (" .. e.n .. " kills)") or ""
        Print("|cff40ff40Bounty paid|r: " .. Show(e.full) .. " got " .. Money(e.copper) .. kills .. " for " .. (r.name or key) .. ".")
        Announce("BOUNTY PAID: " .. Show(e.full) .. " got " .. Gold(e.copper) .. kills .. " for " .. (r.name or key) .. ".")
        Changed()
        return true
    end
    -- The bounties others owe you (you claimed them, not paid yet): { key, r, w }.
    function ns.OwedToMe()
        local out = {}
        for key, r in pairs(db and db.enemies or {}) do
            local w = r.wanted
            if w and not ns.WantedMine(w) then
                for _, e in ipairs(Debts(w)) do
                    if IsMe(e.full) then out[#out + 1] = { key = key, r = r, w = w, copper = e.copper, n = e.n } end
                end
            end
        end
        return out
    end
    -- The claimed bounties you still owe: { key, r, w } (your own kill on your own bounty owes nothing).
    function ns.OwedBounties()
        local out = {}
        for key, r in pairs(db and db.enemies or {}) do
            local w = r.wanted
            if w and ns.WantedMine(w) then
                for _, e in ipairs(Debts(w)) do
                    if not IsMe(e.full) then out[#out + 1] = { key = key, r = r, w = w, to = e.full, copper = e.copper, n = e.n, t = e.t } end
                end
            end
        end
        table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
        return out
    end

    -- ---- receiving. Every message is from another player and is checked as such: names, numbers, sizes; who may
    -- do what (only the poster takes a bounty down or marks it paid; a claim is always the sender's own); a bounty
    -- passed on by someone else can be learned, never change one you have; never one "by you" from anyone else.
    local function Apply(op, f, from)
        local key = ns.ProperName(f[1])   -- (one written in small letters by someone else is the same player)
        if not ValidKey(key) or ns.NameProblem(key) then return end   -- (a name no player can have: not taken in)
        local now = time()
        if op == "A" then
            local t = Int(f[7], 1, now + 300)
            local forever = f[13] == "1"
            if not t or (not forever and now - t > OPEN_DAYS * 86400) then return end
            local _, gone = Gone(key)
            if gone and (gone.t or 0) >= t then return end              -- taken down (or ran out): stays down
            local by = Clean(f[6], 60) or from
            if IsMe(by) then return end                                 -- yours only come from you
            local r = db.enemies[key]
            local w = r and r.wanted
            recent[key .. t] = now
            local kills = Int(f[14], 1, MAX_KILLS) or 1
            if w then
                if (w.t or 0) > t then return end                       -- we know a newer one
                if (w.t or 0) == t then
                    if kills > 1 then w.kills = kills; return end       -- (its kills come as R messages)
                    -- the same bounty: a claim or payment we missed (never on yours, never a claim in your name)
                    if not ns.WantedMine(w) then
                        local cby = Clean(f[8], 60)
                        if not w.claimed and cby and not IsMe(cby) then
                            w.claimed = { by = cby, t = Int(f[9], 1, now + 300) or t, full = Clean(f[10], 60) or cby, zone = Clean(f[12], 40) }
                            Changed()
                        end
                        local pt = f[11] ~= "0" and f[11] ~= "" and (Int(f[11], 1, now + 300) or (f[11] == "1" and now)) or nil
                        if w.claimed and not w.paid and pt and not ClaimedByMe(w) then w.paid = pt; Changed() end
                    end
                    return
                end
                -- a newer one: only from the same poster, and never over a claim that isn't paid
                if not Same(by, w.by) or #Debts(w) > 0 then return end
            else
                local all, his = ForeignCounts(by)
                if all >= FOREIGN_MAX or his >= PER_POSTER_MAX then return end
            end
            if not r then
                local nm = Clean(f[2], 40)
                if not (nm and nm:find("^[%a\128-\255]+ ?[%a\128-\255]*$")) then nm = nil end
                r = ns.EnemyRecord(key, nm)                              -- named once, never renamed from outside
            end
            if not r.class then
                local cl = Clean(f[3], 12)
                if cl and cl:find("^%u+$") then r.class = cl end
            end
            local cp = Int(f[4], 1, 1e10)
            r.wanted = { copper = cp, reward = (not cp) and Clean(f[4], MAX_REWARD) or nil, note = Clean(f[5], MAX_NOTE),
                by = by, t = t, forever = forever or nil, kills = kills > 1 and kills or nil }
            local cby = Clean(f[8], 60)
            if cby and not IsMe(cby) and kills == 1 then
                r.wanted.claimed = { by = cby, t = Int(f[9], 1, now + 300) or t, full = Clean(f[10], 60) or cby, zone = Clean(f[12], 40) }
                local pt = f[11] ~= "0" and f[11] ~= "" and (Int(f[11], 1, now + 300) or (f[11] == "1" and now)) or nil
                if pt then r.wanted.paid = pt end
            end
            if now - t < 600 and not r.wanted.claimed then
                Card("bountyNew", r.name or key, ns.WantedReward(r.wanted), "from " .. Show(by),
                    "WANTED from " .. Show(by) .. ": " .. (r.name or key)
                    .. (ns.WantedReward(r.wanted) and (" – " .. ns.WantedReward(r.wanted) .. (kills > 1 and (" a kill, " .. kills .. " kills") or "")) or "")
                    .. (r.wanted.note and (" (" .. r.wanted.note .. ")") or ""), r.class)
            end
            Changed()
        elseif op == "D" then
            local r = db.enemies[key]
            local w = r and r.wanted
            local t = Int(f[3], 1, now + 300)
            if w and t and t >= (w.t or 0) and Same(from, w.by) then     -- only the poster takes it down
                local gone = Gone(key)
                gone[key] = { t = w.t or t, at = now }
                r.wanted = nil
                Changed()
            end
        elseif op == "C" then
            local r = db.enemies[key]
            local w = r and r.wanted
            if not w or Settled(w) or Int(f[4], 0, now + 300) ~= (w.t or 0) or IsMe(from) then return end
            local ct = Int(f[3], 1, now + 300) or now
            -- the claimer is the sender, always. One kill: the earliest wins (then the name), the same on every
            -- client; several: each kill counts once, the earliest up to the limit
            local c = { by = from, full = from, t = ct, zone = Clean(f[6], 40) }
            if not AddClaim(w, c) then return end
            local where = c.zone and (" in " .. c.zone) or ""
            if ns.WantedMine(w) then
                Announce("BOUNTY CLAIMED: " .. Show(from) .. " killed " .. (r.name or key) .. where .. KillsWords(w) .. " – " .. RewardWords(w) .. " reward.")
                Card("bountyOwe", r.name or key, ns.WantedReward(w), "to " .. Show(from),
                    Show(from) .. " killed " .. (r.name or key) .. where .. KillsWords(w) .. " and claimed your bounty – you owe "
                    .. (ns.WantedReward(w) or "the reward") .. ". Pay it at a mailbox.", r.class)
            else
                Card("bountyKill", r.name or key, ns.WantedReward(w), "by " .. Show(from),
                    "Bounty claimed" .. KillsWords(w) .. ": " .. (r.name or key) .. " by " .. Show(from) .. where
                    .. (ns.WantedReward(w) and (" – " .. ns.WantedReward(w)) or "") .. (w.by and (", from " .. Show(w.by)) or ""), r.class)
            end
            Changed()
        elseif op == "R" then
            local r = db.enemies[key]
            local w = r and r.wanted
            if not w or ns.WantedMine(w) or Limit(w) == 1 or Int(f[4], 0, now + 300) ~= (w.t or 0) then return end
            local who = Clean(f[2], 60)
            if not who or IsMe(who) then return end
            local c = { by = who, full = who, t = Int(f[3], 1, now + 300) or now, zone = Clean(f[5], 40), paid = f[6] == "1" and now or nil }
            if AddClaim(w, c) then Changed() end
        elseif op == "P" then
            local r = db.enemies[key]
            local w = r and r.wanted
            if w and #Debts(w) > 0 and Same(from, w.by) and Int(f[3], 0, now + 300) == (w.t or 0) then
                local who = Clean(f[4], 60)
                local mineBefore = false
                for _, e in ipairs(Debts(w)) do if IsMe(e.full) and (not who or Same(who, e.full)) then mineBefore = true end end
                PayClaims(w, who, Int(f[5], 1, now + 300))
                if mineBefore then
                    Card("bountyPaid", r.name or key, ns.WantedReward(w), "from " .. Show(w.by),
                        Show(w.by) .. " paid you " .. (ns.WantedReward(w) or "the bounty") .. " for " .. (r.name or key) .. " – check your mail.", r.class)
                end
                Changed()
            end
        end
    end

    -- Someone logged in: everyone sends what they know, a few seconds apart, skipping what was just sent (also
    -- what someone else sends while ours waits). Your own take-downs go along, so they stay down everywhere.
    local replyAt, lastReply
    local function Reply()
        replyAt = nil
        if lastReply and time() - lastReply < 60 then return end
        lastReply = time()
        local now = time()
        for key, r in pairs(db.enemies) do
            local w = r.wanted
            if w and w.t and not (recent[key .. w.t] and now - recent[key .. w.t] < 60) then SendAdd(key, r, true) end
        end
        for key, g in pairs(type(db.wantedGone) == "table" and db.wantedGone or {}) do
            if g.mine and now - (g.at or 0) < GONE_DAYS * 86400 then Send({ VER, "D", key, MyFull(), now }) end
        end
        for key, r in pairs(db.enemies) do   -- your kills not paid yet: again (the poster may have been away)
            local w = r.wanted
            if w and not ns.WantedMine(w) then
                for _, c in ipairs(Claims(w)) do
                    if not c.paid and IsMe(c.full or c.by) then Send({ VER, "C", key, c.by, c.t or 0, w.t or 0, c.full or c.by, c.zone or "" }) end
                end
            end
        end
    end

    -- Per sender at most 40 messages a minute (a flood is dropped, not shown).
    local buckets = {}
    local function Allowed(from)
        local now, b = GetTime(), buckets[from]
        if not b or now - b.start > 60 then b = { start = now, n = 0 }; buckets[from] = b end
        b.n = b.n + 1
        return b.n <= 40
    end

    local function OnMessage(prefix, text, channel, from)
        if not On() then return end
        text, channel, from = Plain(text), Plain(channel), Plain(from)
        if type(text) ~= "string" or type(from) ~= "string" or #text > 255 or #from > 60 then return end
        local f = {}
        for part in (text .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = part end
        if f[1] ~= VER then return end
        -- your own message back from the guild channel: it tells how the others see your name
        if f[2] == "H" and f[3] and f[3] == ns.helloNonce then
            if Same(from, Me()) then ns.myFull = from end
            return
        end
        if IsMe(from) then return end
        if channel == "WHISPER" then   -- only from your friends
            if db.wantedFriends == false or not IsFriend(from) then return end
        elseif channel == "GUILD" then
            if db.wantedGuild == false then return end
        else
            return
        end
        if not Allowed(from) then return end
        local op = table.remove(f, 1) and table.remove(f, 1)
        if op == "H" then
            if not replyAt then
                replyAt = true
                C_Timer.After(2 + math.random() * 4, function() ns.Safe("wanted", Reply) end)
            end
        else
            Apply(op, f, from)
        end
    end

    -- Old ones go: open bounties after two weeks, paid ones after three days, claimed-not-paid after two weeks; and
    -- they don't come back from someone who still has them. Old take-down notes go after a while too.
    local function Expire()
        local now = time()
        local gone = Gone("")
        for key, r in pairs(db.enemies) do
            local w = r.wanted
            -- claims by the one who put it up (allowed before 2.30.3): taken off, so the bounty is open again
            if w and w.by then
                if w.claimed and Same(w.claimed.full or w.claimed.by, w.by) then w.claimed, w.paid = nil, nil end
                for i = #(w.claims or {}), 1, -1 do
                    local c = w.claims[i]
                    if Same(c.full or c.by, w.by) then table.remove(w.claims, i) end
                end
                if w.claims and #w.claims == 0 then w.claims = nil end
            end
            local last = w and Last(w)
            local debts = w and #Debts(w) or 0
            if w and ((Settled(w) and now - (w.paid or (last and last.t) or 0) > CLAIMED_DAYS * 86400)
                    or (debts > 0 and now - ((last and last.t) or 0) > OPEN_DAYS * 86400)
                    or (debts == 0 and IsOpen(w) and not w.forever and now - (w.t or 0) > OPEN_DAYS * 86400)) then
                gone[key] = { t = w.t or now, at = now, mine = ns.WantedMine(w) or nil }
                r.wanted = nil
            end
        end
        for key, g in pairs(gone) do
            if type(g) ~= "table" or now - (g.at or 0) > GONE_DAYS * 86400 then gone[key] = nil end
        end
        for k, at in pairs(recent) do if now - at > 3600 then recent[k] = nil end end
    end

    -- ---- paying by mail: at a mailbox a "Pay bounty" button under the mail window. A click asks once (who, how
    -- much), then WatchX sends the mail itself through the game's mail functions – nothing of Blizzard's mail window
    -- is touched. The mail that goes out marks it paid.
    local payBtn, pending
    local function Subject(key) return "Bounty: " .. (Clean((db.enemies[key] and db.enemies[key].name) or key, 40) or key) end
    local function UpdatePayButton()
        if not (MailFrame and MailFrame:IsShown()) then if payBtn then payBtn:Hide() end return end
        local owed = ns.OwedBounties()
        if #owed == 0 or not On() then if payBtn then payBtn:Hide() end return end
        if not payBtn then
            payBtn = CreateFrame("Button", "WatchXPayBounty", MailFrame, "UIPanelButtonTemplate")
            payBtn:SetSize(320, 24)
            payBtn:SetPoint("TOP", MailFrame, "BOTTOM", 0, -4)
            payBtn:SetScript("OnClick", function(self) ns.Safe("wanted", function()
                local r = self.key and db.enemies[self.key]
                local w = r and r.wanted
                local e
                for _, x in ipairs(w and ns.WantedMine(w) and Debts(w) or {}) do if Same(x.full, self.to) then e = x end end
                if not e then UpdatePayButton() return end
                local to = e.full
                StaticPopupDialogs["WATCHX_PAYBOUNTY"] = StaticPopupDialogs["WATCHX_PAYBOUNTY"] or {
                    button1 = ACCEPT or "Send", button2 = CANCEL or "Cancel",
                    timeout = 0, whileDead = true, hideOnEscape = true,
                }
                local d = StaticPopupDialogs["WATCHX_PAYBOUNTY"]
                d.text = "Send %s by mail to |cffffd100" .. Show(to) .. "|r for the bounty on " .. (r.name or self.key)
                    .. (e.n > 1 and (" (" .. e.n .. " kills)") or "") .. "?"
                d.OnAccept = function() ns.Safe("wanted", function()
                    if not (SetSendMailMoney and SendMail) then Print("Mail can't be sent from here.") return end
                    local money = math.floor(e.copper or 0)
                    if GetMoney and money > (tonumber(Plain(GetMoney())) or 0) then Print("You don't have " .. Money(money) .. ".") return end
                    if not SetSendMailMoney(money) then Print("The game didn't take the money for the mail.") return end
                    pending = { key = self.key, to = to }
                    SendMail(to, Subject(self.key), "WatchX bounty on " .. (r.name or self.key) .. (e.n > 1 and (", " .. e.n .. " kills") or "") .. ".")
                end) end
                StaticPopup_Show("WATCHX_PAYBOUNTY", Money(e.copper or 0))
            end) end)
        end
        local o = owed[1]
        payBtn.key, payBtn.to = o.key, o.to
        payBtn:SetText("Pay bounty: " .. Show(o.to) .. " – " .. Money(o.copper) .. (o.n > 1 and (" (" .. o.n .. " kills)") or "")
            .. (#owed > 1 and ("  (+" .. (#owed - 1) .. ")") or ""))
        payBtn:Show()
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:RegisterEvent("FRIENDLIST_UPDATE")
    for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            if Plain((...)) ~= PREFIX or not db then return end   -- every addon's messages come here: ours only
            ns.Safe("wanted", OnMessage, ...)
        elseif event == "PLAYER_LOGIN" then
            if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
            C_Timer.After(12, function() ns.Safe("wanted", function()
                if not db then return end
                Expire()
                if On() then
                    ns.helloNonce = tostring(math.random(100000, 999999))
                    Send({ VER, "H", ns.helloNonce })
                    local owed = ns.OwedBounties()
                    if #owed > 0 then
                        Print("|cffff8040You owe " .. #owed .. (#owed == 1 and " bounty" or " bounties") .. "|r – a Pay button shows at the mailbox.")
                    end
                    local due = ns.OwedToMe()
                    if #due > 0 then
                        local names = {}
                        for i = 1, math.min(3, #due) do names[i] = Show(due[i].w.by) .. " " .. Money(due[i].copper or 0) end
                        Print("|cffffd100Owed to you:|r " .. table.concat(names, ", ") .. (#due > 3 and (" and " .. (#due - 3) .. " more") or "")
                            .. " |cffaaaaaa(History > Wanted)|r")
                    end
                end
            end) end)
        elseif event == "FRIENDLIST_UPDATE" then
            friendsAt = -100
        elseif event == "MAIL_SHOW" or event == "MAIL_CLOSED" then
            if event == "MAIL_CLOSED" then pending = nil end
            ns.Safe("wanted", UpdatePayButton)
        elseif event == "MAIL_SEND_SUCCESS" then
            if pending then ns.MarkPaid(pending.key, pending.to); pending = nil end
            ns.Safe("wanted", UpdatePayButton)
        elseif event == "MAIL_FAILED" then
            if pending then Print("|cffff6060The bounty mail wasn't sent.|r"); pending = nil end
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
    Print("Example Enemies list and stealth card shown (made-up names – gone in a minute).")
    if ns.ShowStealthToast then ns.ShowStealthToast(rogue) end
    Refresh()
    if C_Timer then C_Timer.After(61, function() ns.roles["Example-Druid"] = nil; Refresh() end) end
end

function ns.SetNearby(on)
    db.nearby = on and true or false
    Print("Enemies list: " .. (db.nearby and "|cff40ff40on|r" or "off"))
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
    if ns.lastFriend then ns.lastFriend.name, ns.lastFriend.at = name, now else ns.lastFriend = { name = name, at = now } end
    if friendSeen[name] and now - friendSeen[name] < ENEMY_COOLDOWN then return end
    ns.Stamp(friendSeen, name, now)
    local info = PlayerInfo(unit)
    Log("friend", name, source)
    Alert("FRIEND", name, string.format("Friendly player: %s (%s%s)", name, info ~= "" and (info .. " – ") or "",
        Location()), (info ~= "" and (info .. " · ") or "") .. Location())
end

local function CheckUnit(unit, source)
    if not UnitExists(unit) then return end
    local raw, last = UnitName(unit)
    raw, last = Plain(raw), Plain(last)
    if type(raw) ~= "string" then return end
    if db.nearby and Plain(UnitIsPlayer(unit)) == true and ns.NearbyHere()
        and ns.IsHostilePlayer(unit)
        and Plain(UnitIsDead(unit)) ~= true then
        local key = NoteNearby(unit)
        if key and unit:find("^nameplate") then plateKeys[unit] = key end
    end
    local name = Resolve(raw)
    if not name and type(last) == "string" and last ~= "" then   -- a player on the list by full name (Forever has surnames)
        name = Resolve(raw .. " " .. last) or Resolve(raw .. "-" .. last)
    end
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
local afkSince, afkWarned, campingAfk, exitReason, afkEndedAt = nil, nil, nil, nil, 0

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
    -- you pressed Logout/Quit yourself (the hook below has set exitReason by now), or weren't AFK: not the AFK kick
    if exitReason or not afkSince then return end
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
-- An alert profile (WatchX > Alerts & scan) is what you watch and how you're alerted: the watch list, the rare scan,
-- the alerts and when the mini bar shows. Everything else (bars, PvP, leveling) is the same in every profile.
-- (Profiles saved before 2.30.4 held more: the rest is simply not read from them any more.)
local PROFILE_KEYS = { "scanOn", "enemyPlayers", "friendlyPlayers", "attackAlert", "whisper", "instant", "afkWarn",
    "notifyDeath", "sound", "miniQuiet", "hideIdle" }
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
    -- each character keeps the profile it had last time (set when you switch on it)
    local want = type(db.charProfile) == "table" and db.charProfile[ns.CharKey()] or nil
    if want and want ~= db.profile and db.profiles[want] then
        db.profiles[db.profile] = Snapshot()
        ApplySnapshot(db.profiles[want])
        db.profile = want
    end
end

-- "Name-Realm": which character this is (its own profile, its /played …)
function ns.CharKey()
    local n = UnitName and UnitName("player")
    if issecretvalue and n ~= nil and issecretvalue(n) then n = nil end
    return tostring(n or "?") .. "-" .. tostring((GetRealmName and GetRealmName()) or "")
end
function ns.RememberProfile(name)
    if type(db.charProfile) ~= "table" then db.charProfile = {} end
    db.charProfile[ns.CharKey()] = name
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
    ns.RememberProfile(name)
    Print("Alert profile: |cff38ccad" .. name .. "|r |cffaaaaaa(this character)|r")
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
    ns.RememberProfile(name)
    Print("New alert profile |cff38ccad" .. name .. "|r – a copy of what you watch now. Change what you like.")
    Refresh()
    return true
end

function ns.DeleteProfile(name)
    if not db.profiles[name] then return false end
    if #ns.ProfileNames() <= 1 then Print("You need at least one profile.") return false end
    db.profiles[name] = nil
    for k, v in pairs(type(db.charProfile) == "table" and db.charProfile or {}) do if v == name then db.charProfile[k] = nil end end
    Print("Deleted the profile '" .. name .. "'.")
    if db.profile == name then
        db.profile = ns.ProfileNames()[1]
        ApplySnapshot(db.profiles[db.profile])
        Print("Alert profile: |cff38ccad" .. db.profile .. "|r")
        AfterProfileChange()
    else
        Refresh()
    end
    return true
end

function ns.SaveProfile()   -- keeps the active profile up to date (also done at logout)
    if db and db.profiles and db.profile then db.profiles[db.profile] = Snapshot() end
end

-- The rebuff icons' layout is each character's own: where they are, row or column, size, gap, and the icons you
-- placed on their own. The live values are this character's; at logout they're kept under its name (charLayout),
-- at login its own come back. A character with none yet starts from another of its class (else as it is now).
-- It's all in WatchXDB, so an export takes every character's layout along.
do
    local KEYS = { "rebuffPoint", "rebuffScale", "rebuffGap", "rebuffVertical" }
    local function Class() local _, c = UnitClass("player"); c = Plain(c); return type(c) == "string" and c or "ANY" end
    function ns.SaveCharLayout()
        if not db then return end
        if type(db.charLayout) ~= "table" then db.charLayout = {} end
        local c = Class()
        local t = { class = c, at = time() }
        for _, k in ipairs(KEYS) do t[k] = Copy(db[k]) end
        t.spots = Copy(type(db.rebuffSpots) == "table" and db.rebuffSpots[c] or nil)
        t.pts = Copy(type(db.rebuffGroupPts) == "table" and db.rebuffGroupPts[c] or nil)
        db.charLayout[ns.CharKey()] = t
    end
    function ns.LoadCharLayout()   -- true when a saved layout was put in place
        if not db or type(db.charLayout) ~= "table" then return false end
        local c = Class()
        local t = db.charLayout[ns.CharKey()]
        if type(t) ~= "table" then   -- new here: the one of its class used last
            for _, o in pairs(db.charLayout) do
                if type(o) == "table" and o.class == c and (not t or (o.at or 0) > (t.at or 0)) then t = o end
            end
        end
        if type(t) ~= "table" then return false end
        for _, k in ipairs(KEYS) do db[k] = Copy(t[k]) end
        if type(db.rebuffSpots) ~= "table" then db.rebuffSpots = {} end
        if type(db.rebuffGroupPts) ~= "table" then db.rebuffGroupPts = {} end
        db.rebuffSpots[c] = Copy(t.spots) or {}
        db.rebuffGroupPts[c] = Copy(t.pts) or {}
        if ns.RebuffRelayout then ns.Safe("rebuff icons", ns.RebuffRelayout) end
        return true
    end
end

-- ---------------------------------------------------------------- attacked
-- Combat starts while you haven't done anything for a while (or are AFK) = something attacked you.
-- Doing something = moving, casting, changing target or moving the mouse (checked every second). Tabbed out,
-- the game sees no mouse, so that still counts as away.
-- (Without the combat log the attacker is found through nameplates: whoever has you targeted.)
local IDLE_FOR = 20          -- seconds without moving, casting, targeting or moving the mouse
local lastActive, lastAttack = time(), 0   -- a fresh login counts as active

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
-- The once-a-second work, spread over four frames a quarter second apart (at 120 Hz a frame is 8.3 ms: no single
-- frame gets all of it). Each part is timed on its own, so /wx mem shows which one costs what.
local TickJobs = {
    ns.Timed(function() ns.Safe("scan", ScanNameplates) end, "tick: nameplates"),
    ns.Timed(function()
        ns.Safe("afk", function() CheckCursor(); CheckAfk(); AfkTick() end)
        -- the XP boost warnings also work with the list switched off (the list reads it every second itself)
        if db.levelHelper == false and db.levelWarn ~= false then ns.Safe("xp boosts", ns.LevelStatus) end
    end, "tick: afk & xp"),
    ns.Timed(function() ns.Safe("buffs", ns.CheckBuffs) end, "tick: buffs"),
    ns.Timed(function() Refresh() end, "tick: refresh"),
}
TickJobs.at = 0   -- which one runs next (in the table: the main chunk is at the 200-locals limit)
function TickJobs.Run()   -- (on the table: no new top-level local)
    if not db then return end
    TickJobs.at = TickJobs.at % #TickJobs + 1
    TickJobs[TickJobs.at]()
end
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.25, TickJobs.Run)   -- the game's own timer: no Lua at all on the frames in between
else
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        TickJobs.Run()
    end)
end

-- ---------------------------------------------------------------- events

-- Never COMBAT_LOG_EVENT_*: Forever blocks it for addons.
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
    "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "LOOT_OPENED",
    "UNIT_DIED", "PARTY_KILL", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_SYSTEM",
    "PLAYER_FLAGS_CHANGED", "PLAYER_CAMPING", "LOGOUT_CANCEL", "PLAYER_LOGOUT",
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
            if ns.OnEnemyTrick then ns.Safe("potions & stances", ns.OnEnemyTrick, arg1, spellID) end
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
        if db.instantOK == false then db.instantOK = nil end   -- each session tries the instant way again
        ns.linksAtLogin = (db.ntfyUrl or "") .. "\1" .. (db.discordWebhook or "") .. "\1" .. (db.ntfyToken or "")
        if type(db.bridgeKey) ~= "string" or not db.bridgeKey:find("^%w+$") then   -- once per install
            local chars, k = "abcdefghijkmnpqrstuvwxyz23456789", {}
            for i = 1, 12 do local n = math.random(1, #chars); k[i] = chars:sub(n, n) end
            db.bridgeKey = table.concat(k)
        end
        do   -- players saved in small letters by older versions (a typed "bob smith") get the game's spelling
            local fix = {}
            for key in pairs(db.enemies or {}) do
                local p = ns.ProperName(key)
                if p ~= key and not db.enemies[p] then fix[key] = p end
            end
            for key, p in pairs(fix) do
                local r = db.enemies[key]
                db.enemies[key], db.enemies[p] = nil, r
                if type(r.name) == "string" then r.name = ns.ProperName(r.name) end
            end
        end
        do   -- the player history kept to its size now, not in the middle of a busy nameplate moment
            local n = 0
            for _ in pairs(db.enemies or {}) do n = n + 1 end
            ns.enemyCount = n
            if n > ENEMY_MAX then ns.PruneEnemies() end
        end
        ns.InitProfiles()
        ns.LoadCharLayout()
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
        Print("v" .. GetVersion() .. " loaded – Made by " .. ns.AUTHOR .. ". /wx opens the settings.")
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
        elseif arg1 then
            -- another addon's: the game only says "Interface action failed because of an AddOn" – say which
            -- (once per addon and action a session)
            ns.otherBlocks = ns.otherBlocks or {}
            local k = tostring(arg1) .. ":" .. tostring(arg2)
            if not ns.otherBlocks[k] then
                ns.otherBlocks[k] = true
                Log("blocked other", tostring(arg1), tostring(arg2))
                Print("|cff999999\"Interface action failed\" was |r" .. tostring(arg1) .. "|cff999999 (" .. tostring(arg2)
                    .. "), not WatchX.|r")
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
        C_Timer.After(0, function() ns.Safe("afk", OnCamping) end)   -- a frame later: the Logout hook has run
    elseif event == "LOGOUT_CANCEL" then
        exitReason, campingAfk = nil, nil   -- you moved: a later kick or disconnect must still be told
    elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
        ns.OnScreenshot(event == "SCREENSHOT_SUCCEEDED")
    elseif event == "PLAYER_LOGOUT" then
        -- written to disk right now: the bridge sees the file change and tells your phone (not on reload/quit)
        ns.SaveProfile()
        ns.SaveCharLayout()
        db.exitAt = time()
        db.exitWhy = exitReason or (campingAfk and "afk") or "disconnect"
    end
end
ev:SetScript("OnEvent", function(self, event, ...) ns.Safe(event, OnEvent, self, event, ...) end)   -- timed per event

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
        if ns.ToggleSettings then ns.ToggleSettings("main") end
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
    elseif cmd == "size" or cmd == "scale" then   -- /wx size 150: every bar and icon row at 150 %
        local pct = tonumber((rest or ""):match("(%d+)"))
        if not (ns.SetSize and ns.SIZE_KEYS) then return end
        if pct then
            local v = pct > 5 and pct / 100 or pct   -- (150 or 1.5)
            for _, k in ipairs(ns.SIZE_KEYS) do ns.SetSize(k, v) end
            Print("Size: |cffffd100" .. math.floor(ns.GetSize("miniScale") * 100 + 0.5) .. "%|r for every bar and icon row "
                .. "(60–300 %). One at a time: WatchX settings > SIZE.")
        else
            local t = {}
            for _, k in ipairs(ns.SIZE_KEYS) do t[#t + 1] = k:gsub("Scale$", "") .. " " .. math.floor(ns.GetSize(k) * 100 + 0.5) .. "%" end
            Print("Sizes: " .. table.concat(t, " · ") .. " – /wx size 150 sets them all; one at a time: WatchX settings > SIZE.")
        end
    elseif cmd == "xp" and rest == "reset" then
        if ns.ResetXPSession then ns.ResetXPSession() end
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
            local spikeCol = C.max >= 8.3 and "|cffff4040" or C.max >= 2 and "|cffffd100" or "|cff40ff40"
            Print(("Longest single call: %s%.1f ms|r (%s)  ·  calls over 4 ms: %d  ·  garbage made: %.0f KB a second"):format(
                spikeCol, C.max, C.maxLabel or "-", C.spikes, C.kb / up)
                .. " |cffaaaaaa(a frame at 120 Hz is 8.3 ms)|r")
        end
        local GetCPU = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
        if GetCVar("scriptProfile") == "1" and GetCPU then
            local okc, ms = pcall(GetCPU, "WatchX")
            if okc and ms then Print(("CPU since login/reload: %.0f ms"):format(ms)) end
        else
            Print("|cffaaaaaaThe game's own measure: /console scriptProfile 1 and a /reload (it costs a little itself – "
                .. "/console scriptProfile 0 afterwards).|r")
        end
    elseif cmd == "auras" or cmd == "buffs!" then
        -- every buff on you: name, spell ID, stacks and time left (to find what the sleeping bag, a fire or food give)
        local n = 0
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            local name, sid, st, ex = Plain(a.name), Plain(a.spellId), Plain(a.applications), Plain(a.expirationTime)
            local left = (type(ex) == "number" and ex > 0) and math.floor(ex - GetTime()) or nil
            local what = ""
            if type(db.xpBuffs) == "table" and sid and db.xpBuffs[sid] then what = "  |cff40ff40XP food (learned)|r"
            elseif sid == WELL_FED then what = "  |cff40ff40XP food|r"
            elseif AuraIsXP then
                local xp = AuraIsXP(i, sid, name)
                what = xp == "kill" and "  |cff40ff40XP from kills|r" or xp == "rest" and "  |cffaaaaaarested XP|r"
                    or xp == false and "" or "  |cff808080(text not readable)|r"
            end
            Print(("%d. |cffffd100%s|r  id %s  ·  stacks %s  ·  %s%s"):format(i, tostring(name or "?"), tostring(sid or "?"),
                tostring(st or 0), left and (left .. " s left") or "no end", what))
            n = n + 1
        end
        if n == 0 then Print("No buffs on you.") end
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
    elseif cmd == "export" or cmd == "import" or cmd == "backup" then
        if ns.ShowExport then ns.ShowExport(cmd == "import") end
    elseif (cmd == "plates" or cmd == "plate" or cmd == "nameplates") and rest == "test" and ns.PlateDemo then
        ns.PlateDemo()
    elseif (cmd == "swing" or cmd == "wand") and ns.SwingDemo then
        ns.SwingDemo()
    elseif (cmd == "potion" or cmd == "potions") and ns.AddCustomPotion then
        -- /wx potions: the list · /wx potion add Name: seconds · /wx potion remove Name
        local sub, what = rest:match("^(%S+)%s*(.*)$")
        if sub == "add" and what ~= "" then ns.AddCustomPotion(what)
        elseif (sub == "remove" or sub == "delete") and what ~= "" then ns.RemoveCustomPotion(what)
        else Print("Potions watched: " .. ns.PotionListText()) Print("/wx potion add Name: seconds · /wx potion remove Name") end
    elseif cmd == "scroll" or cmd == "scrolls" or cmd == "comprehend" then
        if ns.ScrollDebug then ns.ScrollDebug() else Print("Scrolls.lua isn't loaded – log out and in again (a /reload doesn't load new files).") end
    elseif cmd == "rebuff" then
        if rest == "why" and ns.RebuffWhy then ns.RebuffWhy()
        elseif rest ~= "" and ns.AddRebuff then ns.AddRebuff(rest)
        elseif ns.OpenRebuffSettings then ns.OpenRebuffSettings() end
    elseif cmd == "buffs" or cmd == "buff" then
        if rest == "test" then ns.BuffTest()
        elseif rest ~= "" then ns.AddBuffWatch(rest)
        elseif ns.OpenBuffSettings then ns.OpenBuffSettings() end
    elseif cmd == "nearby" or cmd == "enemies" or cmd == "spy" then
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
        if rest == "confirm" then ns.ResetData()
        else Print("This forgets every respawn time WatchX has learned. Type |cffffd100/wx reset confirm|r to do it.") end
    elseif cmd == "log" then
        local lines = (rest == "previous" and db.previousLog) or db.log or {}
        Print((rest == "previous" and "Previous" or "This") .. " session's log (" .. #lines .. " lines):")
        for i = math.max(1, #lines - 24), #lines do DEFAULT_CHAT_FRAME:AddMessage("  " .. lines[i]) end
    else
        Print("Made by " .. ns.AUTHOR .. ". Commands: /wx (settings) | guide | test | add <name> | "
            .. "remove <name> | profile [name] | enemy | friend | nearby [on|off|test] | xp | buffs [name|test] | swing | avoid [name: note] | wanted [name: reward note] | rares | mem | auras | attack | afk [minutes] | instant | list | mini | quiet | alert | move | lock | unlock | minimap | sound | "
            .. "whisper | dead [name] | "
            .. "respawn <min> [name] | reset | log [previous]")
    end
end
SlashCmdList.WATCHX = function(input) ns.Safe("/wx", OnSlash, input) end
