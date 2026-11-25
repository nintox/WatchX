# Rebuff icons: a pulsing icon for each of your class's buffs you're missing (click: cast it on yourself);
# alternatives; spells you don't know left out; row or column; not changed in a fight.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
CLASS = "MAGE"
UnitClass = function(u) return "Mage", CLASS end
KNOWN = { ["Ice Armor"] = 101, ["Frost Armor"] = 102, ["Arcane Intellect"] = 103, ["Arcane Brilliance"] = 104 }
C_Spell.GetSpellInfo = function(n) if KNOWN[n] then return { name = n, iconID = KNOWN[n] } end end
C_Spell.GetSpellTexture = function(n) return KNOWN[n] end
GetSpellInfo = function(n) if KNOWN[n] then return n end end
function A(name) return { name = name, spellId = 1, expirationTime = T + 1500, duration = 1800, applications = 0 } end
function shown() local t = {} for _, b in ipairs(WatchXRebuff and WatchXRebuff.icons or {}) do if b:IsShown() then t[#t + 1] = b.line end end return table.concat(t, ",") end
AURAS = { A("Arcane Intellect") }
NS.AddRebuff("Ice Armor / Frost Armor"); NS.AddRebuff("Arcane Intellect / Arcane Brilliance"); NS.AddRebuff("Mage Armor")
tick(1, 0.5)
''')
check(ev('shown()') == "Ice Armor / Frost Armor", "missing Ice Armor: its icon (AI is up, Mage Armor isn't known): " + str(ev('shown()')))
b1 = 'WatchXRebuff.icons[1]'
check(ev(b1 + ':GetAttribute("spell1")') == "Ice Armor", "click casts the first one you know")
check(ev(b1 + '.pulse:IsPlaying()'), "it pulses")
ex('AURAS = { A("Arcane Intellect"), A("Frost Armor") }; tick(1, 0.5)')
check(ev('WatchXRebuff:IsShown()') == False, "an alternative is up: nothing missing, no icons")
ex('NS.db.rebuffAll = true; NS.RefreshRebuff()')
check(ev('shown()') == "Ice Armor / Frost Armor,Arcane Intellect / Arcane Brilliance", "'also the ones you have': both, dimmed")
check(not ev(b1 + '.pulse:IsPlaying()'), "the ones you have don't pulse")
w, h = ev('WatchXRebuff:GetWidth()'), ev('WatchXRebuff:GetHeight()')
ex('NS.db.rebuffVertical = true; NS.RefreshRebuff()')
w2, h2 = ev('WatchXRebuff:GetWidth()'), ev('WatchXRebuff:GetHeight()')
check(w > h and h2 > w2, "a row, or a column (%dx%d -> %dx%d)" % (w, h, w2, h2))
ex('NS.db.rebuffAll = false; NS.db.rebuffVertical = false')
# in a fight: left as it was (the buffs can't be read, the icons can't change)
ex('AURAS = { A("Arcane Intellect"), A("Frost Armor") }; NS.RefreshRebuff()')
ex('local old = InCombatLockdown; InCombatLockdown = function() return true end; AURAS = {}; NS.RefreshRebuff(); FIGHT = WatchXRebuff:IsShown(); InCombatLockdown = old')
check(ev('FIGHT') == False, "in a fight: not changed")
ex('tick(4, 0.5)')
check(ev('shown()') == "Ice Armor / Frost Armor,Arcane Intellect / Arcane Brilliance", "after it: both missing")
# another class: its own list
ex('CLASS = "WARRIOR"; KNOWN = { ["Battle Shout"] = 201 }; NS.RefreshRebuff()')
check(not ev('WatchXRebuff:IsShown()'), "a warrior: the mage's list doesn't show")
# the settings page: quick add for your class
ex('if not WatchXRebuffOptions then NS.BuildRebuffSettings() end; WatchXRebuffOptions:GetScript("OnShow")(WatchXRebuffOptions)')
sug = ev('(function() local t = {} for _, c in ipairs(WatchXRebuffOptions.sugs) do if c:IsShown() then t[#t + 1] = c.line end end return table.concat(t, ",") end)()')
print("    quick add:", sug)
check(sug == "Battle Shout", "quick add: the warrior's that you know")
ex('for _, c in ipairs(WatchXRebuffOptions.sugs) do if c:IsShown() then c:GetScript("OnClick")(c) end end')
check(ev('NS.RebuffList()[1]') == "Battle Shout", "one click adds it")
# a rogue: poisons are weapon enchants – missing when the weapon has none; any rank from your bags; pick which
ex(r'''
CLASS = "ROGUE"; KNOWN = {}
NS.db.rebuffAll = false
ITEMS = { [21927] = "Instant Poison VI", [20844] = "Deadly Poison V", [3775] = "Crippling Poison" }
BAGS = { 21927, 20844, 3775 }
C_Container.GetContainerItemID = function(bag, slot) if bag == 0 then return BAGS[slot] end end
C_Item.GetItemNameByID = function(id) return ITEMS[id] or ("Item" .. id) end
GetItemInfo = function(id) return ITEMS[id] end
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, 2, 2 end   -- a weapon
GetInventoryItemID = function(u, slot) if slot == 16 or slot == 17 then return 5000 + slot end end
ENCH = { false, false }
GetWeaponEnchantInfo = function() return ENCH[1], 0, 0, 0, ENCH[2], 0, 0, 0 end
NS.AddRebuff("Main hand: Instant Poison / Deadly Poison / Crippling Poison")
NS.AddRebuff("Off hand: Deadly Poison / Instant Poison")
NS.RefreshRebuff()
''')
check(ev('shown()') == "Main hand: Instant Poison / Deadly Poison / Crippling Poison,Off hand: Deadly Poison / Instant Poison", "no poison on either: both icons " + str(ev('shown()')))
mt = str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")'))
check(mt == "/use Instant Poison VI\n/use 16", "click: the highest rank from your bags onto the main hand: " + repr(mt))
check(str(ev('WatchXRebuff.icons[2]:GetAttribute("macrotext1")')) == "/use Deadly Poison V\n/use 17", "and Deadly onto the off hand")
ex('ENCH = { true, false }; NS.RefreshRebuff()')
check(ev('shown()') == "Off hand: Deadly Poison / Instant Poison", "main hand done: only the off hand")
ex('C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, 4, 6 end; NS.RefreshRebuff()')
check(not ev('WatchXRebuff:IsShown()'), "a shield in the off hand: nothing to poison")
ex('C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, 2, 2 end; ENCH = { false, false }; NS.RefreshRebuff()')
# pick another: hover the icon, click Crippling in the column
ex('B1 = WatchXRebuff.icons[1]; B1:GetScript("OnEnter")(B1)')
check(ev('WatchXRebuffFlyout and WatchXRebuffFlyout:IsShown()'), "hover: the poisons you have come up")
ex('for _, x in ipairs(WatchXRebuffFlyout.buttons) do if x:IsShown() and x.base == "Crippling Poison" then CRIP = x end end')
check(str(ev('CRIP:GetAttribute("macrotext1")')) == "/use Crippling Poison\n/use 16", "each one puts itself on that weapon")
ex('CRIP:GetScript("PostClick")(CRIP, "LeftButton"); NS.RefreshRebuff()')
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Crippling Poison\n/use 16", "picked: the icon uses Crippling from now on")
ex('if not WatchXRebuffOptions then NS.BuildRebuffSettings() end; NS.RebuffList()[1] = nil; NS.RebuffList()[2] = nil; WatchXRebuffOptions:GetScript("OnShow")(WatchXRebuffOptions)')
sug = ev('(function() local t = {} for _, c in ipairs(WatchXRebuffOptions.sugs) do if c:IsShown() then t[#t + 1] = c.line:sub(1, 9) end end return table.concat(t, ",") end)()')
check(sug == "Main hand,Off hand:", "a rogue's quick add: main hand and off hand poison " + str(sug))
# a poison typed as a buff: a weapon line with every poison, the one you typed picked; main hand, then off hand
ex('NS.db.rebuff.ROGUE = nil; NS.db.rebuffPick = nil; NS.AddRebuff("Instant Poison IV"); NS.AddRebuff("Deadly Poison V")')
l1, l2 = str(ev('NS.RebuffList()[1]')), str(ev('NS.RebuffList()[2]'))
print("    ", l1, "|", l2)
check(l1.startswith("Main hand: Instant Poison / Deadly Poison") and "Crippling Poison" in l1, "main hand: all the poisons, Instant first")
check(l2.startswith("Off hand: Deadly Poison / Instant Poison"), "off hand: Deadly first")
check(ev('(NS.RebuffPicked(NS.RebuffList()[1]))') == "Instant Poison" and ev('(NS.RebuffPicked(NS.RebuffList()[2]))') == "Deadly Poison", "the typed ones are picked")
ex('NS.db.rebuff.ROGUE = { "Instant Poison IV", "Instant Poison III" }')
check(str(ev('NS.RebuffList()[1]')).startswith("Main hand: Instant Poison /") and str(ev('NS.RebuffList()[2]')).startswith("Off hand: Instant Poison /"),
      "lines added before: fixed the same way")
# pick another in the settings: the icon uses it
ex('ENCH = { false, false }; NS.RebuffPick(NS.RebuffList()[1], "Crippling Poison"); NS.RefreshRebuff()')
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Crippling Poison\n/use 16", "picked in the settings: the icon puts Crippling on")
ex('NS.RebuffPick(NS.RebuffList()[1], "Wound Poison"); NS.RefreshRebuff()')
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Instant Poison VI\n/use 16", "picked one not in your bags: the first one you have")
ex('WatchXRebuffOptions:GetScript("OnShow")(WatchXRebuffOptions)')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("rebuff:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
