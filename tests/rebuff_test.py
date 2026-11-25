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
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("rebuff:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
