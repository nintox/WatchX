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
# a rogue: poisons are weapon enchants – every one in your bags, found by its text (WoW Forever's, any name, any
# rank); left-click puts the default on, right-click picks the default; MH / OH always shown (faded while on)
ex(r"""
CLASS = "ROGUE"; KNOWN = {}
NS.db.rebuffAll = false
ITEMS = { [6947] = "Instant Poison", [6949] = "Instant Poison II", [2892] = "Deadly Poison", [3775] = "Crippling Poison", [2589] = "Linen Cloth" }
BAGS = { 6947, 6949, 2892, 3775, 2589 }
-- like WoW Forever: no GetContainerItemID – the bags are read with GetContainerItemInfo (name and count in it)
C_Container.GetContainerItemID = nil
C_Container.GetContainerItemInfo = function(bag, slot)
  local id = bag == 0 and BAGS[slot]
  if id then return { itemID = id, itemName = ITEMS[id], stackCount = 20 } end
end
C_Item.GetItemNameByID = function(id) return nil end   -- (names not loaded: they come from the bag slot)
GetItemInfo = function(id) return ITEMS[id] end
C_TooltipInfo.GetHyperlink = function(link)
  local id = tonumber(link:match("item:(%d+)"))
  if id and ITEMS[id] and ITEMS[id]:find("Poison") then
    return { lines = { { leftText = ITEMS[id] }, { leftText = "Use: Coats a weapon with poison that lasts for 30 minutes." } } }
  end
  return { lines = { { leftText = ITEMS[id] or "?" } } }
end
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, 2, 2 end   -- a weapon
GetInventoryItemID = function(u, slot) if slot == 16 or slot == 17 then return 5000 + slot end end
ENCH = { false, false }
GetWeaponEnchantInfo = function() return ENCH[1], 1740000, 0, 0, ENCH[2], 900000, 0, 0 end
C_TooltipInfo.GetInventoryItem = function(u, slot) return { lines = { { leftText = "Some Dagger" }, { leftText = (slot == 16 and "Instant Poison II" or "Deadly Poison") .. " (29 min)" } } } end
NS.db.rebuff.ROGUE = { "Main hand: Instant Poison / Deadly Poison / Crippling Poison", "Off hand: Deadly Poison / Instant Poison" }
NS.RebuffBagsChanged(); NS.RefreshRebuff()
""")
check(ev('shown()') == "Main hand: Instant Poison / Deadly Poison / Crippling Poison,Off hand: Deadly Poison / Instant Poison", "no poison on either: both icons")
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Instant Poison\n/use 16", "left-click: Instant onto the main hand")
check(str(ev('WatchXRebuff.icons[2]:GetAttribute("macrotext1")')) == "/use Deadly Poison\n/use 17", "and Deadly onto the off hand")
check(ev('WatchXRebuff.icons[1].hand:GetText()') == "MH" and ev('WatchXRebuff.icons[2].hand:GetText()') == "OH", "MH / OH on them")
# right-click: every poison in your bags (all ranks, not the cloth), with how many; pick one
ex('B1 = WatchXRebuff.icons[1]; B1:GetScript("PostClick")(B1, "RightButton")')
menu = ev('(function() local t = {} for _, b in ipairs(WatchXMenu.buttons) do if b:IsShown() then t[#t + 1] = tostring(b:GetText()) end end return table.concat(t, " | ") end)()')
print("    right-click:", menu)
check(menu.count("Poison") == 4 and "Instant Poison II" in menu and "Linen" not in menu and "x20" in menu, "right-click: all 4 poisons with counts, nothing else")
ex('for _, b in ipairs(WatchXMenu.buttons) do if b:IsShown() and tostring(b:GetText()):find("Crippling") then b:GetScript("OnClick")(b) end end')
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Crippling Poison\n/use 16", "picked: left-click puts Crippling on from now on")
ex('NS.RebuffPick(NS.RebuffList()[1], "Instant Poison II"); NS.RefreshRebuff()')
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Instant Poison II\n/use 16", "any rank can be the default")
# on: still shown (faded), with the icon of what's on and its minutes
ex('ENCH = { true, false }; NS.RefreshRebuff()')
check(ev('shown()').startswith("Main hand"), "main hand on: still shown")
check(ev('WatchXRebuff.icons[1].icon:GetAlpha()') < 0.6 and ev('WatchXRebuff.icons[1].left:GetText()') == "29m", "faded, with 29m left")
check(ev('WatchXRebuff.icons[1].onName') == "Instant Poison II", "it knows what's on: Instant Poison II")
ex('NS.db.rebuffWeaponAlways = false; NS.RefreshRebuff()')
check(ev('shown()') == "Off hand: Deadly Poison / Instant Poison", "'always show' off: only the missing one")
ex('NS.db.rebuffWeaponAlways = nil')
ex('C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, 4, 6 end; ENCH = { false, false }; NS.RefreshRebuff()')
check(ev('shown()') == "Main hand: Instant Poison / Deadly Poison / Crippling Poison", "a shield in the off hand: no OH icon")
ex('C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, 2, 2 end; NS.RefreshRebuff()')
ex('if not WatchXRebuffOptions then NS.BuildRebuffSettings() end; NS.db.rebuff.ROGUE = {}; WatchXRebuffOptions:GetScript("OnShow")(WatchXRebuffOptions)')
sug = ev('(function() local t = {} for _, c in ipairs(WatchXRebuffOptions.sugs) do if c:IsShown() then t[#t + 1] = c.line:sub(1, 9) end end return table.concat(t, ",") end)()')
check(sug == "Main hand,Off hand:", "a rogue's quick add: main hand and off hand poison " + str(sug))
# a poison typed as a buff: a weapon line, the one you typed picked; main hand, then off hand
ex('NS.db.rebuff.ROGUE = nil; NS.db.rebuffPick = nil; NS.AddRebuff("Instant Poison IV"); NS.AddRebuff("Deadly Poison V")')
l1, l2 = str(ev('NS.RebuffList()[1]')), str(ev('NS.RebuffList()[2]'))
check(l1.startswith("Main hand: Instant Poison / Deadly Poison") and "Crippling Poison" in l1, "typed: main hand, all the poisons, Instant first")
check(l2.startswith("Off hand: Deadly Poison / Instant Poison"), "then the off hand, Deadly first")
ex('NS.db.rebuff.ROGUE = { "Instant Poison IV", "Instant Poison III" }')
check(str(ev('NS.RebuffList()[1]')).startswith("Main hand: Instant Poison /") and str(ev('NS.RebuffList()[2]')).startswith("Off hand: Instant Poison /"),
      "lines added before: fixed the same way")
ex('NS.RefreshRebuff()')
check(str(ev('WatchXRebuff.icons[1]:GetAttribute("macrotext1")')) == "/use Instant Poison II\n/use 16", "Instant Poison IV picked but not in the bags: another Instant rank you have")
ex('WatchXRebuffOptions:GetScript("OnShow")(WatchXRebuffOptions)')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("rebuff:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
