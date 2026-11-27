# Enemy players: a potion they drink (their cast) shows on their nameplate and in the Enemies list while it lasts;
# a warrior's stance (his stance cast, an ability only that stance allows, or his stance buff out of combat).
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
NS.db.nearby = true; NS.db.plateIcons = true
ENEMY = { nameplate1 = { "Gorm", "WARRIOR" }, nameplate2 = { "Lissa", "DRUID" } }
local oN, oC, oE, oP, oA, oG = UnitName, UnitClass, UnitExists, UnitIsPlayer, UnitCanAttack, UnitGUID
UnitName = function(u) if ENEMY[u] then return ENEMY[u][1], nil end return oN(u) end
UnitClass = function(u) if ENEMY[u] then return ENEMY[u][2], ENEMY[u][2] end return oC(u) end
UnitExists = function(u) return ENEMY[u] ~= nil or oE(u) end
UnitIsPlayer = function(u) return ENEMY[u] ~= nil or oP(u) end
UnitCanAttack = function(a, u) return ENEMY[u] ~= nil end
UnitGUID = function(u) if ENEMY[u] then return "Player-1-" .. ENEMY[u][1] end return oG(u) end
UnitLevel = function() return 40 end
SPELLS = { [6615] = "Free Action", [3169] = "Invulnerability", [71] = "Defensive Stance", [1680] = "Whirlwind", [100] = "Charge", [2457] = "Battle Stance" }
C_Spell.GetSpellName = function(id) return SPELLS[id] or ("Spell" .. id) end
C_Spell.GetSpellTexture = function(id) return 5000 + id end
PLATES = {}
C_NamePlate.GetNamePlateForUnit = function(u) if ENEMY[u] then PLATES[u] = PLATES[u] or CreateFrame("Frame", nil, UIParent) return PLATES[u] end end
local pe = NS.PaintPlateExtras; NS.PaintPlateExtras = function(f, u, ...) PF = PF or {}; PF[u] = f; return pe(f, u, ...) end
fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
function key(u) return (NS.PlayerKey(u)) end
function cast(u, id) fire("UNIT_SPELLCAST_SUCCEEDED", u, "Cast-1", id) end
function rowText() local t = {} for _, r in ipairs(WatchXNearby and WatchXNearby.rows or {}) do if r:IsShown() then t[#t + 1] = tostring(r.info:GetText()) end end return table.concat(t, " | ") end
''')
ex('cast("nameplate1", 6615); tick(0.5)')
e = 'NS.nearby[key("nameplate1")]'
check(ev(e + ' ~= nil and ' + e + '.potion ~= nil and ' + e + '.potion.label') == "Free Action", "Free Action Potion seen")
ex('f = nil; for p, i in pairs(PLATES) do end; PI = nil')
check(ev('PF and PF.nameplate1 and PF.nameplate1.pot and PF.nameplate1.pot:IsShown()'), "its icon on Gorm's nameplate")
ex('NS.RefreshUI(); tick(1.2)')
print("    rows:", ev('rowText()'))
check("FREE ACTION" in str(ev('rowText()')), "and in the list, with its seconds")
ex('cast("nameplate1", 6615); cast("nameplate1", 6615)')
check(ev(e + '.potion.dur') == 30, "the same cast on every token: once")
ex('tick(31, 1)')
check("FREE ACTION" not in str(ev('rowText()')), "over after 30 s: gone from the list")
# stances
ex('cast("nameplate1", 71); tick(0.3)')
check(ev(e + '.stance') == "Defensive", "Defensive Stance cast: Defensive")
ex('cast("nameplate1", 1680); tick(0.3)')
check(ev(e + '.stance') == "Berserker", "Whirlwind (only in Berserker): Berserker")
ex('NS.RefreshUI(); tick(1.2)')
check("BERS" in str(ev('rowText()')), "the list says BERS")
check(ev('PF.nameplate1.stance and PF.nameplate1.stance:IsShown()'), "a stance icon on the plate")
check(not ev('PF.nameplate1.pot:IsShown()'), "the potion's icon gone when it's over")
ex('cast("nameplate2", 100); tick(0.3)')
check(not ev('NS.nearby[key("nameplate2")] and NS.nearby[key("nameplate2")].stance'), "a druid's Charge: no stance")
ex('NS.db.plateStance = false; NS.RefreshUI(); tick(1.2)')
check("BERS" not in str(ev('rowText()')), "switched off: not shown")
# /wx plates test: a made-up potion and stance on your target's plate, a friend's too (friendly icons off)
ex('''
NS.db.plateStance = true; NS.db.plateFriendly = false
ENEMY.nameplate3 = { "Venn", "MAGE" }
local oCA = UnitCanAttack
UnitCanAttack = function(a, u) if u == "nameplate3" or u == "target" then return false end return oCA(a, u) end
local oIU, oG2, oP2, oN2, oC2 = UnitIsUnit, UnitGUID, UnitIsPlayer, UnitName, UnitClass
UnitIsUnit = function(a, b) if (a == "nameplate3" and b == "target") or (a == "target" and b == "nameplate3") then return true end return oIU(a, b) end
UnitGUID = function(u) if u == "target" then return "Player-1-Venn" end return oG2(u) end
UnitIsPlayer = function(u) if u == "target" then return true end return oP2(u) end
UnitName = function(u) if u == "target" then return "Venn", nil end return oN2(u) end
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
''')
check(not ev('PF.nameplate3 and PF.nameplate3:IsShown()'), "a friend's plate: no icon (friendly icons off)")
ex('SlashCmdList.WATCHX("plates test"); tick(0.3)')
check(ev('PF.nameplate3 and PF.nameplate3:IsShown() and PF.nameplate3.pot and PF.nameplate3.pot:IsShown()'), "/wx plates test: the potion on the friend's plate")
check(ev('PF.nameplate3.stance and PF.nameplate3.stance:IsShown()'), "and the stance")
check(not ev('PF.nameplate1.pot:IsShown()'), "not on another player's plate")
ex('tick(21, 1)')
check(not ev('PF.nameplate3:IsShown()'), "after 20 s: gone again")
check(not ev('NS.nearby[key("nameplate3")]'), "the friend isn't put in the Enemies list")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("potions:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
