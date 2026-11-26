# Rebuff icons placed on their own: unlocked, drag an icon away -> a group of its own there; drop it next to another
# icon -> it joins that one's group, beside it. One size and one gap for all; "Link them all again".
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
UnitClass = function(u) return "Mage", "MAGE" end
IsShiftKeyDown = function() return false end
KNOWN = { ["Ice Armor"] = 101, ["Arcane Intellect"] = 103, ["Dampen Magic"] = 105 }
C_Spell.GetSpellInfo = function(n) if KNOWN[n] then return { name = n, iconID = KNOWN[n] } end end
C_Spell.GetSpellTexture = function(n) return KNOWN[n] end
GetSpellInfo = function(n) if KNOWN[n] then return n end end
NS.AddRebuff("Ice Armor"); NS.AddRebuff("Arcane Intellect"); NS.AddRebuff("Dampen Magic")
AURAS = {}
tick(1, 0.5)
function icon(line) for _, b in ipairs(WatchXRebuff.icons) do if b.line == line and b:IsShown() then return b end end end
function at(b, x, y) b.GetCenter = function() return x, y end; b.GetLeft = function() return x - 16 end; b.GetTop = function() return y + 16 end end
function drag(b) b:GetScript("OnDragStart")(b); b:GetScript("OnDragStop")(b) end
''')
check(ev('icon("Dampen Magic") ~= nil'), "three icons in the row")
ex('NS.StartMove()')
check(ev('icon("Ice Armor"):GetAttribute("type1")') is None, "unlocked: a click doesn't cast")
# drag Dampen Magic far away: its own group, there
ex('at(icon("Ice Armor"), 100, 100); at(icon("Arcane Intellect"), 140, 100); at(icon("Dampen Magic"), 600, 300); drag(icon("Dampen Magic"))')
check(ev('WatchXRebuffGroup2 ~= nil and WatchXRebuffGroup2:IsShown()'), "dragged away: a group of its own")
check(ev('icon("Dampen Magic"):GetParent() == WatchXRebuffGroup2'), "  with Dampen Magic in it")
pt = ev('NS.db.rebuffGroupPts.MAGE[2]')
check(pt is not None and pt[3] == 600 - 16 - 6 and pt[4] == 300 + 16 + 6, "  where it was dropped")
check(ev('icon("Ice Armor"):GetParent() == WatchXRebuff'), "the others stay in the main row")
# drop it right of Ice Armor: back in the main row, between Ice Armor and Arcane Intellect
ex('at(icon("Ice Armor"), 100, 100); at(icon("Arcane Intellect"), 180, 100); at(icon("Dampen Magic"), 138, 102); drag(icon("Dampen Magic"))')
check(ev('icon("Dampen Magic"):GetParent() == WatchXRebuff'), "dropped next to another: linked into its row")
order = ev('table.concat(NS.RebuffList(), ",")')
check(order == "Ice Armor,Dampen Magic,Arcane Intellect", "  beside it: " + str(order))
check(not ev('WatchXRebuffGroup2:IsShown()') and ev('NS.db.rebuffGroupPts.MAGE[2]') is None, "  the empty group is gone")
# two away together: a group of two
ex('at(icon("Arcane Intellect"), 700, 500); drag(icon("Arcane Intellect"))')
ex('at(icon("Arcane Intellect"), 700, 500); at(icon("Dampen Magic"), 738, 499); drag(icon("Dampen Magic"))')
check(ev('icon("Dampen Magic"):GetParent() == icon("Arcane Intellect"):GetParent() and icon("Dampen Magic"):GetParent() ~= WatchXRebuff'), "two linked in a group of their own")
# gap and size: for all
w = ev('icon("Arcane Intellect"):GetParent():GetWidth()')
ex('NS.db.rebuffGap = 20; NS.RefreshRebuff()')
check(ev('icon("Arcane Intellect"):GetParent():GetWidth()') == w + 12, "a bigger gap: the group gets wider")
ex('NS.SetSize("rebuffScale", 1.5)')
check(abs(ev('icon("Arcane Intellect"):GetParent():GetScale()') - 1.5) < 0.001 and abs(ev('WatchXRebuff:GetScale()') - 1.5) < 0.001, "one size for every group")
ex('NS.RebuffJoin()')
check(ev('icon("Dampen Magic"):GetParent() == WatchXRebuff and icon("Arcane Intellect"):GetParent() == WatchXRebuff'), "Link them all again: one row")
ex('NS.StopMove()')
check(ev('icon("Ice Armor"):GetAttribute("type1")') == "spell", "locked: a click casts again")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("rebuff groups:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
