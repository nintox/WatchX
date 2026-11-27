# Combo points (rogue / druid): pips under your target's nameplate – an enemy player or a mob; filled up to your
# combo points (each pip a bar, so a number the game hides in a fight still fills them); none at 0, none for a mage.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
CLASS = "ROGUE"; CPN = 0; TARGET = true
UnitClass = function(u) return "Rogue", CLASS end
UnitPower = function(u, t) if t == 4 then return CPN end return 100 end
UnitPowerMax = function(u, t) if t == 4 then return 5 end return 100 end
local oE, oA = UnitExists, UnitCanAttack
UnitExists = function(u) if u == "target" then return TARGET end return oE(u) end
UnitCanAttack = function(a, u) if u == "target" then return TARGET end return oA(a, u) end
PLATE = CreateFrame("Frame", nil, UIParent); PLATE.UnitFrame = CreateFrame("Frame", nil, PLATE); PLATE.UnitFrame.healthBar = CreateFrame("StatusBar", nil, PLATE.UnitFrame)
C_NamePlate.GetNamePlateForUnit = function(u) if u == "target" and TARGET then return PLATE end end
function pips() local n, f = 0, 0 for _, b in ipairs(WatchXComboPoints and WatchXComboPoints.pips or {}) do if b:IsShown() then n = n + 1; if (b.__value or b.VAL or 0) >= select(2, b:GetMinMaxValues()) then f = f + 1 end end end return n .. "/" .. f end
for _, b in ipairs({}) do end
''')
ex('fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints and WatchXComboPoints:IsShown()'), "0 combo points: nothing")
ex('CPN = 3; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")')
check(ev('WatchXComboPoints and WatchXComboPoints:IsShown()'), "3 combo points: the pips show")
check(ev('WatchXComboPoints:GetParent() == PLATE'), "on the target's nameplate")
check(ev('select(2, WatchXComboPoints:GetPoint(1)) == PLATE.UnitFrame.healthBar'), "under its health bar")
check(ev('select(1, WatchXComboPoints:GetPoint(1)) == "TOPLEFT" and select(1, WatchXComboPoints:GetPoint(2)) == "TOPRIGHT" and select(2, WatchXComboPoints:GetPoint(2)) == PLATE.UnitFrame.healthBar'),
      "as wide as the health bar (both its ends)")
ex('VALS = {} for i, b in ipairs(WatchXComboPoints.pips) do VALS[i] = b:IsShown() end')
check(ev('VALS[5] == true and VALS[6] == false'), "five pips (your max)")
check(ev('WatchXComboPoints.pips[5].clip == nil or (WatchXComboPoints.pips[5].clip:IsShown() and not WatchXComboPoints.pips[4].clip:IsShown())'), "the sparkle: on the last part only")
ex('CPN = 5; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")')
check(ev('WatchXComboPoints:IsShown()'), "5: still there (finish him)")
# a number the game hides in a fight: still shown (the bars fill themselves)
ex('local oS = issecretvalue; SECRET = { }; issecretvalue = function(v) return type(v) == "table" and v.secret == true end; CPN = { secret = true }; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")')
check(ev('WatchXComboPoints:IsShown()'), "hidden number in a fight: the pips still show")
ex('issecretvalue = nil; CPN = 2; TARGET = false; fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints:IsShown()'), "no target: gone")
ex('TARGET = true; CLASS = "MAGE"; fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints:IsShown()'), "a mage: never")
ex('CLASS = "ROGUE"; NS.db.plateCombo = false; fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints:IsShown()'), "switched off: gone")
# /wx plates test: 3 combo points on the target's plate – for a mage too
ex('NS.db.plateCombo = true; issecretvalue = function() return false end; CLASS = "MAGE"; TARGET = true; UnitIsPlayer = function() return true end; UnitName = function(u) return "Gorm", nil end; UnitGUID = function(u) return "Player-1-Gorm" end; SlashCmdList.WATCHX("plates test"); tick(0.3)')
check(ev('WatchXComboPoints:IsShown()'), "/wx plates test: combo points on the plate, for a mage too")
ex('tick(8.5, 0.5)')
check(ev('NS.plateDemo and NS.plateDemo.cp') == 5, "counted up to 5 in 8 s: all full")
ex('tick(21, 1)')
check(not ev('WatchXComboPoints:IsShown()'), "the test over: gone")
# 5 points on one, out of the fight, another targeted: none on the new one (they're the first one's); back: there again
ex(r"""
NS.db.plateCombo = true; NS.PlateDemoFor = function() return nil end
issecretvalue = function() return false end
CLASS = "ROGUE"; TARGET = true; TGUID = "Creature-A"
UnitGUID = function(u) if u == "target" then return TGUID end return "Player-1-0001" end
CPN = 0; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
for i = 1, 5 do CPN = i; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS") end
""")
check(ev('WatchXComboPoints:IsShown()'), "5 points on the one you built them on")
ex('TGUID = "Creature-B"; fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints:IsShown()'), "another targeted: none on it (still 5 on the first)")
ex('TGUID = "Creature-A"; fire("PLAYER_TARGET_CHANGED")')
check(ev('WatchXComboPoints:IsShown()'), "back on the first: its 5 again")
ex('TGUID = "Creature-B"; fire("PLAYER_TARGET_CHANGED"); CPN = 1; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")')
check(ev('WatchXComboPoints:IsShown()'), "a point built on the new one: shown there")
ex('TGUID = "Creature-A"; fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints:IsShown()'), "the first one's are gone now")
ex('TGUID = "Creature-B"; fire("PLAYER_TARGET_CHANGED"); GetComboPoints = function(u, t) return 0 end; fire("PLAYER_TARGET_CHANGED")')
check(not ev('WatchXComboPoints:IsShown()'), "the game says none on this target: none")
ex('GetComboPoints = nil; CPN = 0; fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("combo points:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
