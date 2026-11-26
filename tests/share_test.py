# Telling your party / guild what you spot: stealth, KOS, WANTED (and every enemy when ticked); once a minute per
# player and kind; not what another WatchX here just said; not in battlegrounds.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
SAID = {}
function SendChatMessage(msg, chan) table.insert(SAID, chan .. "|" .. msg) end
function said() local t = SAID; SAID = {}; return table.concat(t, "\n") end
function IsInGroup() return true end
GetZoneText = function() return "Arathi Highlands" end
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function() return 1417 end
C_Map.GetPlayerMapPosition = function() return { x = 0.452, y = 0.618 } end
E1 = { key = "Grimble-X", name = "Grimble Hexley", class = "ROGUE", level = 60, guild = "Hollow Crown" }
E2 = { key = "Bram-X", name = "Bram Stonefist", class = "WARRIOR", level = 58 }
''')
ex('NS.ShareSpot(E1, "stealth", "Vanish")')
check(ev('said()') == "", "off by default: nothing said")
ex('NS.db.shareParty = true; NS.db.shareGuild = true; NS.ShareSpot(E1, "stealth", "Vanish")')
out = str(ev('said()'))
print("    " + out.replace("\n", "\n    "))
check("PARTY|WatchX: Stealth – [Grimble Hexley] 60 Rogue <Hollow Crown> (Vanish) · Arathi Highlands 45,62" in out, "party: who, what, where")
check("GUILD|WatchX: Stealth" in out, "and guild")
ex('tick(5, 1); NS.ShareSpot(E1, "stealth", "Vanish")')
check(ev('said()') == "", "the same player and kind: not again within a minute")
ex('NS.ShareSpot(E2, "enemy")')
check(ev('said()') == "", "every enemy: off by default")
ex('NS.ShareSpot(E2, "wanted", { copper = 15000, kills = 10 })')
check("WANTED – [Bram Stonefist] 58 Warrior – 1g 50s a kill" in str(ev('said()')), "WANTED with the reward")
# another WatchX said it first (their line in guild chat): yours keeps quiet
ex('tick(5, 1); fire("CHAT_MSG_GUILD", "WatchX: Kill on sight – [Sly Whisperpaw] 35 Rogue · Arathi Highlands 40,60", "Someone")')
ex('NS.ShareSpot({ key = "Sly-X", name = "Sly Whisperpaw", class = "ROGUE", level = 35 }, "kos")')
check(ev('said()') == "", "someone else's WatchX said it: not again")
ex('tick(5, 1); NS.ShareSpot({ key = "Kessa-X", name = "Kessa Shade", class = "ROGUE", level = 41 }, "kos")')
check("Kill on sight – [Kessa Shade]" in str(ev('said()')), "a new KOS player: said")
# a battleground: nothing
ex('tick(5, 1); local ii = IsInInstance; IsInInstance = function() return true, "pvp" end; NS.ShareSpot({ key = "A-X", name = "Aldric Brightmane", level = 37, class = "PALADIN" }, "kos"); IsInInstance = ii')
check(ev('said()') == "", "in a battleground: nothing")
# the guild has its own ticks (until you tick them, it follows the party's)
ex('NS.db.shareParty = true; NS.db.shareGuild = true; NS.db.shareGuildStealth = false; tick(70, 1)')
ex('NS.ShareSpot({ key = "Nyx-X", name = "Nyx Shadeveil", class = "ROGUE", level = 44 }, "stealth", "Stealth")')
out = str(ev('said()'))
check("PARTY|WatchX: Stealth" in out and "GUILD|" not in out, "stealth off for the guild: only the party hears it")
ex('NS.db.shareGuildAll = true; tick(15, 1); NS.ShareSpot({ key = "Pip-X", name = "Pip Ashgrove", class = "MAGE", level = 30 }, "enemy")')
out = str(ev('said()'))
check("GUILD|WatchX: Enemy" in out and "PARTY|" not in out, "every enemy just for the guild: only the guild hears it")
ex('NS.db.shareGuildStealth, NS.db.shareGuildAll = nil, nil')
# from the player's menu: said where you ask, whatever the ticks
ex('NS.db.shareParty = false; NS.db.shareGuild = false; tick(2, 1)')
ex('NS.db.enemies["Bram-X"] = { name = "Bram Stonefist", class = "WARRIOR", level = 58, guild = "Stormborn", kos = true }')
ex('NS.EnemyMenu(UIParent, "Bram-X")')
ex('for _, b in ipairs(WatchXMenu and WatchXMenu.buttons or {}) do if b:IsShown() and tostring(b:GetText()):find("guild|r") then b:GetScript("OnClick")(b) end end')
out = str(ev('said()'))
print("    menu:", out)
check(out.startswith("GUILD|WatchX: Kill on sight – [Bram Stonefist] 58 Warrior <Stormborn>"), "menu: announce in guild")
ex('tick(2, 1); NS.EnemyMenu(UIParent, "Bram-X")')
ex('for _, b in ipairs(WatchXMenu.buttons) do if b:IsShown() and tostring(b:GetText()):find("say|r") then b:GetScript("OnClick")(b) end end')
check(str(ev('said()')).startswith("SAY|WatchX: Kill on sight – [Bram Stonefist]"), "menu: announce in say")
ex('tick(2, 1); NS.EnemyMenu(UIParent, "Bram-X")')
ex('for _, b in ipairs(WatchXMenu.buttons) do if b:IsShown() and tostring(b:GetText()):find("party|r") then b:GetScript("OnClick")(b) end end')
check(str(ev('said()')).startswith("PARTY|WatchX: Kill on sight"), "menu: announce in party")

errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("share:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
