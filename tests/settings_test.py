# WatchX's own settings window: the pages in a list on the left (General, PvP, Leveling), one shown at a time;
# Options > AddOns > WatchX is a page with a button to it. PvP is four pages.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

check(ev('WatchXLanding ~= nil and WatchXLanding.name == "WatchX"'), "Options > AddOns > WatchX: the landing page")
ex('NS.OpenSettings()')
check(ev('WatchXSettings and WatchXSettings:IsShown()'), "/wx settings opens WatchX's own window")
check(ev('WatchXOptions:IsShown() and WatchXOptions:GetParent() ~= UIParent'), "the main page in it")
tabs = ["main", "alerts", "enemies", "plates", "kos", "avoid", "level", "buffs", "rebuff"]
pages = {"main": "WatchXOptions", "enemies": "WatchXNearbyOptions", "plates": "WatchXPlateOptions", "kos": "WatchXKOSOptions",
         "avoid": "WatchXAvoidOptions", "level": "WatchXLevelOptions", "buffs": "WatchXBuffOptions", "rebuff": "WatchXRebuffOptions"}
for t in tabs:
    ex('NS.OpenWindow("%s")' % t)
    check(ev('NS.SettingsShown()') == t, "page: " + t)
    if t in pages:
        others = [p for k, p in pages.items() if k != t]
        shown = [p for p in others if ev('%s:IsShown()' % p)]
        check(ev('%s:IsShown()' % pages[t]) and not shown, "  only it is shown " + str(shown))
check(len(list(ev('WatchXSettings.navButtons').values())) == 9, "nine pages in the list")
# the PvP pages work
ex('NS.OpenNearbySettings("kos"); NS.SetKOS(NS.KeyFromName("Badguy"), true); NS.RefreshKOSChips()')
check(ev('NS.SettingsShown()') == "kos", "OpenNearbySettings('kos') opens KOS & bounties")
check(len(list(ev('NS.soundBtns').values())) >= 4, "the sound pickers are on the Enemies page")
ex('NS.OpenNearbySettings()')
check(ev('NS.SettingsShown()') == "enemies", "and with nothing: the Enemies list page")
# a check box: click it, the setting follows
ex('NS.db.nearbyShowEmpty = false; NS.RefreshPvPOptions()')
ex('''for _, f in ipairs(FRAMES) do
  if f.__kind == "CheckButton" and f.get and f.__parent == nil then end
end''')
# the window's own Unlock / Lock button: the window stays open
ex('NS.OpenSettings(); WatchXSettings.lock:GetScript("OnClick")(WatchXSettings.lock)')
check(ev('NS.IsMoving()') and ev('WatchXSettings:IsShown()'), "Unlock in the window: unlocked, the window stays")
check("Lock" in str(ev('WatchXSettings.lock:GetText()')), "  and the button says Lock bars")
ex('WatchXSettings.lock:GetScript("OnClick")(WatchXSettings.lock)')
check(not ev('NS.IsMoving()'), "click again: locked")
# unlocking the bars closes the window (it would be in the way)
ex('NS.StartMove()')
check(not ev('WatchXSettings:IsShown()'), "Unlock bars: the window steps aside")
ex('NS.StopMove()')
# pages without their own scroll frame scroll in the window (nothing runs out at the bottom)
ex('NS.OpenWindow("level")')
check(ev('WatchXLevelOptions:GetParent() ~= nil and WatchXLevelOptions:GetParent():GetObjectType() == "ScrollFrame"'), "XP boosts scrolls in the window")
check(ev('(WatchXLevelOptions.contentH or 0) > 300'), "  and knows how tall it is: " + str(ev('WatchXLevelOptions.contentH')))
ex('NS.OpenWindow("rebuff")')
check(ev('WatchXRebuffOptions:GetParent():GetObjectType() == "ScrollFrame"'), "Rebuff icons scrolls too")
# rebuff: a spell ID or a Wowhead link; the buff catalogue
ex('NS.db.rebuff = {}')
check(ev('NS.AddRebuff("10220")') and "Spell10220" in list(ev('NS.RebuffList()').values()), "a spell ID adds that spell")
check(ev('NS.AddRebuff("https://www.wowhead.com/classic/spell=7302/frost-armor")') and "Spell7302" in list(ev('NS.RebuffList()').values()), "a Wowhead link too")
ex('C_Spell.GetSpellName = function() return nil end; GetSpellInfo = function() return nil end')
check(not ev('NS.AddRebuff("999999")'), "an ID that doesn't exist: not added")
ex('NS.ShowBuffCatalog()')
check(ev('WatchXBuffCatalog:IsShown()'), "Browse buffs: the catalogue opens")
rows = ev('(function() local t = {} for _, r in ipairs(WatchXBuffCatalog.rows) do if r:IsShown() then t[#t + 1] = tostring(r.line) end end return table.concat(t, "|") end)()')
check("Arcane Intellect" in rows and "Ice Armor" in rows, "a mage's buffs in it")
ex('KNOWN = { ["Arcane Intellect"] = true }')
ex('for _, r in ipairs(WatchXBuffCatalog.rows) do if r.line == "Arcane Intellect" then r:GetScript("OnClick")(r) end end')
check("Arcane Intellect" in list(ev('NS.RebuffList()').values()), "click one: added")
ex('WatchXBuffCatalog.all:SetChecked(true); NS.ShowBuffCatalog()')
ex('WatchXBuffCatalog.search:SetText("shout"); WatchXBuffCatalog.search:GetScript("OnTextChanged")(WatchXBuffCatalog.search)')
check(ev('(function() for _, r in ipairs(WatchXBuffCatalog.rows) do if r:IsShown() and r.text:GetText() and r.text:GetText():find("Warrior") then return true end end end)()'), "All classes: the others under a heading")
rows = ev('(function() local t = {} for _, r in ipairs(WatchXBuffCatalog.rows) do if r:IsShown() and r.line then t[#t + 1] = r.line end end return table.concat(t, "|") end)()')
check(rows == "Battle Shout / Commanding Shout|Battle Shout|Commanding Shout", "search: the either-one line first, then each: " + str(rows))
# either one: merge two lines, pick which a click casts, split again
ex('NS.db.rebuff.MAGE = { "Dampen Magic", "Amplify Magic" }; KNOWN = { ["Dampen Magic"] = 1, ["Amplify Magic"] = 2 }')
ex('C_Spell.GetSpellInfo = function(n) if KNOWN[n] then return { name = n, iconID = 1 } end end')
check(ev('NS.RebuffMerge("Dampen Magic", "Amplify Magic")') and ev('table.concat(NS.RebuffList(), ",")') == "Dampen Magic / Amplify Magic", "or…: two become one line")
ex('NS.RebuffPick("Dampen Magic / Amplify Magic", "Amplify Magic"); AURAS = {}; NS.RefreshRebuff()')
check(ev('WatchXRebuff.icons[1]:GetAttribute("spell1")') == "Amplify Magic", "picked: a click casts Amplify Magic")
ex('AURAS = { { name = "Amplify Magic", spellId = 2, expirationTime = T + 600, duration = 600, applications = 0 } }; NS.RefreshRebuff()')
check(not ev('WatchXRebuff:IsShown()'), "either one up: nothing missing")
check(ev('NS.RebuffSplit("Dampen Magic / Amplify Magic")') and ev('table.concat(NS.RebuffList(), ",")') == "Dampen Magic,Amplify Magic", "split: apart again")
# alert profiles: only what you watch and how you're alerted switches; bars and PvP stay
ex('NS.db.nearbyMax = 7; NS.db.scanOn = true; NS.NewProfile("Farm"); NS.db.scanOn = false; NS.db.nearbyMax = 12')
ex('NS.SwitchProfile("Camping")')
check(ev('NS.db.nearbyMax') == 12, "switching the alert profile leaves the Enemies list alone")
ex('NS.SwitchProfile("Farm")')
check(ev('NS.db.scanOn') == False, "but the rare scan follows the profile")
check(ev('WatchXSettings.exp ~= nil'), "the window's top button: Export / import")
# no panel any more: /wx opens the settings, the minimap button toggles the Enemies list (shown at once)
ex('NS.CloseWindow(); SlashCmdList["WATCHX"]("")')
check(ev('NS.SettingsShown()') == "main", "/wx: the settings window")
ex('SlashCmdList["WATCHX"]("")')
check(not ev('WatchXSettings:IsShown()'), "/wx again: closed")
check(ev('WatchXPanel') is None, "the old panel isn't made")
ex('NS.db.nearby = false; NS.db.nearbyShowEmpty = false; NS.ToggleEnemies()')
ex('tick(1, 1)')
check(ev('NS.db.nearby') and ev('WatchXNearby and WatchXNearby:IsShown()'), "minimap click: the Enemies list on, shown even while empty")
ex('tick(9, 1)')
check(not ev('WatchXNearby:IsShown()'), "  (empty: it goes after a moment)")
ex('NS.ToggleEnemies()')
check(not ev('NS.db.nearby'), "click again: off")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("settings:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
