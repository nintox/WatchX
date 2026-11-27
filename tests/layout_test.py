# The rebuff icons' layout is each character's own (spot, row/column, size, gap, icons placed on their own); a new
# character starts from another of its class; an export takes them along. Nameplate icons: moved up/down, left/right.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
WHO = { "Rikerud", "MAGE" }
UnitName = function(u) if u == "player" then return WHO[1], nil end return nil end
UnitClass = function(u) if u == "player" then return WHO[2], WHO[2] end return "Mage", "MAGE" end
function as(name, class) WHO = { name, class } end
function setLayout(x, vertical, scale)
    NS.db.rebuffPoint = { "CENTER", "CENTER", x, -100 }; NS.db.rebuffVertical = vertical; NS.db.rebuffScale = scale
    NS.db.rebuffGroupPts = NS.db.rebuffGroupPts or {}; NS.db.rebuffGroupPts[WHO[2]] = { [2] = { "TOPLEFT", "BOTTOMLEFT", x, 300 } }
end
''')
# the mage: a column on the left; logging out keeps it
ex('as("Rikerud", "MAGE"); setLayout(-300, true, 1.4); fire("PLAYER_LOGOUT")')
check(ev('NS.db.charLayout["Rikerud-Forever"] and NS.db.charLayout["Rikerud-Forever"].rebuffVertical') == True, "logout: the mage's layout kept under his name")
# another mage logs in: none of his own -> the mage's
ex('as("Frostar", "MAGE"); NS.LoadCharLayout()')
check(ev('NS.db.rebuffPoint[3]') == -300 and ev('NS.db.rebuffVertical') == True, "a new mage starts from the other mage's layout")
ex('setLayout(-100, true, 1.0); NS.SaveCharLayout()')
# a warrior: a row on the right
ex('as("Gorm", "WARRIOR"); NS.LoadCharLayout(); setLayout(250, false, 0.8); fire("PLAYER_LOGOUT")')
# back on the first mage: his own again
ex('as("Rikerud", "MAGE"); NS.LoadCharLayout()')
check(ev('NS.db.rebuffPoint[3]') == -300 and ev('NS.db.rebuffVertical') == True and ev('NS.db.rebuffScale') == 1.4, "Rikerud: his column on the left, his size")
check(ev('NS.db.rebuffGroupPts.MAGE[2][3]') == -300, "and his own icons' spots")
ex('as("Frostar", "MAGE"); NS.LoadCharLayout()')
check(ev('NS.db.rebuffPoint[3]') == -100 and ev('NS.db.rebuffScale') == 1.0, "Frostar (same class): his own")
ex('as("Gorm", "WARRIOR"); NS.LoadCharLayout()')
check(ev('NS.db.rebuffPoint[3]') == 250 and ev('NS.db.rebuffVertical') == False and ev('NS.db.rebuffScale') == 0.8, "Gorm the warrior: a row on the right")
# shown there: the frame moves at once
ex('NS.db.rebuffOn = true; NS.db.rebuff = { WARRIOR = { "Battle Shout" } }; NS.RefreshRebuff(); NS.LoadCharLayout()')
check(ev('WatchXRebuff == nil or (select(4, WatchXRebuff:GetPoint())) == 250'), "the icons' frame moved to it")
# an export (on Gorm) -> another machine: every character's layout along
ex('EXP = NS.MakeExport({ settings = true })')
ex('NS.db.charLayout = nil; setLayout(0, false, 1)')
ex('NS.ApplyExport(NS.ReadExport(EXP))')
check(ev('NS.db.rebuffPoint[3]') == 250, "imported: Gorm's own layout in place")
ex('as("Rikerud", "MAGE"); NS.LoadCharLayout()')
check(ev('NS.db.rebuffPoint[3]') == -300 and ev('NS.db.rebuffVertical') == True, "and Rikerud's came along")

# nameplate icons: higher by default, and moved by the settings
ex(r'''
ENEMY = { nameplate1 = { "Gorm", "WARRIOR" } }
local oN, oE, oP, oA = UnitName, UnitExists, UnitIsPlayer, UnitCanAttack
UnitName = function(u) if ENEMY[u] then return ENEMY[u][1], nil end return oN(u) end
local oC = UnitClass
UnitClass = function(u) if ENEMY[u] then return ENEMY[u][2], ENEMY[u][2] end return oC(u) end
UnitExists = function(u) return ENEMY[u] ~= nil or oE(u) end
UnitIsPlayer = function(u) return ENEMY[u] ~= nil or oP(u) end
UnitCanAttack = function(a, u) return ENEMY[u] ~= nil end
NS.db.plateIcons = true
PL = CreateFrame("Frame", nil, UIParent)
C_NamePlate.GetNamePlateForUnit = function(u) if ENEMY[u] then return PL end end
local pe = NS.PaintPlateExtras; NS.PaintPlateExtras = function(f, u, ...) PF = f; return pe(f, u, ...) end
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
''')
check(ev('PF and PF:IsShown()'), "the class icon on the plate")
check(ev('select(5, PF:GetPoint())') == 8 and ev('(select(4, PF:GetPoint()))') == 0, "8 above the nameplate by default")
ex('NS.db.plateY = 30; NS.db.plateX = -20; NS.UpdatePlates()')
check(ev('select(5, PF:GetPoint())') == 30 and ev('(select(4, PF:GetPoint()))') == -20, "moved: 30 up, 20 left")
ex('NS.db.plateY = 999; NS.UpdatePlates()')
check(ev('select(5, PF:GetPoint())') == 100, "kept within reach (100 at most)")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("layout:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
