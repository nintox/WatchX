# The eating tile says what you eat (the item's name and icon) and, for buff food, the 10 s until Well Fed.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
HP = 500
function UnitHealth() return HP end function UnitHealthMax() return 2000 end
BAG = { [3] = 21023 }   -- slot -> item
C_Container.GetContainerItemID = nil   -- (like WoW Forever)
C_Container.GetContainerItemInfo = function(bag, slot) local id = bag == 0 and BAG[slot] if id then return { itemID = id, stackCount = 5 } end end
C_Item.GetItemSpell = function(id) if id == 21023 then return "Food", 433 end end
C_Item.GetItemNameByID = function(id) if id == 21023 then return "Dirge's Kickin' Chimaerok Chops" end return "Item" .. id end
C_Item.GetItemIconByID = function(id) if id == 21023 then return 777 end return 1 end
GetItemInfo = function(id) return C_Item.GetItemNameByID(id) end
C_TooltipInfo.GetHyperlink = function(link) if link == "item:21023" then return { lines = {
  { leftText = "Dirge's Kickin' Chimaerok Chops" },
  { leftText = "Use: Restores 2550 health over 30 sec. If you spend at least 10 seconds eating you will become well fed and gain 25 Stamina for 15 min." } } } end
  return { lines = {} } end
AURAS = { { name = "Food", spellId = 433, icon = 1, expirationTime = T + 28, duration = 30 } }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.2)
R = WatchXEating.rows[1]
R.icon.SetTexture = function(self, x) self.TEX = x end
tick(0.2)
''')
food = str(ev('R.food.__text'))
print("    food line:", food.replace("\n", " | "))
check("Chimaerok Chops" in food, "the food's name under the tile")
check(ev('R.icon.TEX') == 777, "the food's own icon: " + str(ev('R.icon.TEX')))
check("Well Fed in 8s" in food or "Well Fed in 9s" in food, "buff food: Well Fed in 8 s")
ex('tick(9, 0.25)')
check("Well Fed!" in str(ev('R.food.__text')), "after 10 s: Well Fed!")
# plain food, not in the bags any more (the last one): no name, no countdown, the fork and knife
ex('AURAS = { { name = "Food", spellId = 999, icon = 1, expirationTime = T + 18, duration = 21 } }; fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.2)')
check(str(ev('R.food.__text')) == "", "unknown food: nothing under the tile")
# a buff food whose text isn't loaded the first time: asked again (not "no buff" for good)
ex(r"""
BAG = { [3] = 21023, [4] = 30001 }
LOADED = false
local oldHL = C_TooltipInfo.GetHyperlink
C_TooltipInfo.GetHyperlink = function(link)
  if link == "item:30001" then
    if not LOADED then return { lines = { { leftText = "Retrieving item information" } } } end
    return { lines = { { leftText = "Hearty Stew" }, { leftText = "Use: Restores 900 health over 27 sec. If you spend at least 10 seconds eating you will become well fed and gain 8 Spirit for 15 min." } } }
  end
  return oldHL(link)
end
local oldGS = C_Item.GetItemSpell
C_Item.GetItemSpell = function(id) if id == 30001 then return "Food", 555 end return oldGS(id) end
AURAS = { { name = "Food", spellId = 555, icon = 1, expirationTime = T + 27, duration = 27 } }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.3)
""")
check("Well Fed in" not in str(ev('R.food.__text')), "text not loaded yet: no countdown yet")
ex('LOADED = true; tick(2.5, 0.25)')
check("Well Fed in" in str(ev('R.food.__text')), "loaded a moment later: Well Fed in … (was 'no' for good): " + str(ev('R.food.__text')).replace("\n", " | "))
# a food whose text never says it (XP food on Forever): learned the first time it makes you Well Fed, with its own wait
ex(r"""
BAG = { [5] = 30002 }
local oldGS2 = C_Item.GetItemSpell
C_Item.GetItemSpell = function(id) if id == 30002 then return "Food", 666 end return oldGS2(id) end
AURAS = { { name = "Food", spellId = 666, icon = 1, expirationTime = T + 30, duration = 30 } }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.3)
""")
check("Well Fed" not in str(ev('R.food.__text')), "unknown at first: no countdown")
ex(r"""
tick(6.7, 0.25)
AURAS[2] = { name = "Well Fed", spellId = 1248406, icon = 2, expirationTime = T + 900, duration = 900 }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.3)
""")
check(ev('NS.db.fedFood and NS.db.fedFood[666]') == 7, "learned: that food gives Well Fed after 7 s (%s)" % ev('NS.db.fedFood and NS.db.fedFood[666]'))
check("Well Fed!" in str(ev('R.food.__text')), "and it says Well Fed! the moment it comes")
ex(r"""
AURAS = { { name = "Food", spellId = 666, icon = 1, expirationTime = T + 30, duration = 30 } }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.3)
""")
food2 = str(ev('R.food.__text'))
check("Well Fed in 7s" in food2, "next time: Well Fed in 7s from the start: " + food2.replace("\n", " | "))
# two waters with the same "Drink" spell: the icon of the one you used, not the first in your bags
ex(r"""
BAG = { [1] = 159, [2] = 5350 }
local oGS3, oIc3, oNm3 = C_Item.GetItemSpell, C_Item.GetItemIconByID, C_Item.GetItemNameByID
C_Item.GetItemSpell = function(id) if id == 159 or id == 5350 then return "Drink", 1137 end return oGS3(id) end
C_Item.GetItemIconByID = function(id) if id == 159 then return 901 elseif id == 5350 then return 900 end return oIc3(id) end
C_Item.GetItemNameByID = function(id) if id == 159 then return "Refreshing Spring Water" elseif id == 5350 then return "Conjured Water" end return oNm3(id) end
NS.lastUsedItem = { id = 5350, at = GetTime() }   -- (what the UseContainerItem hook notes)
AURAS = { { name = "Drink", spellId = 1137, icon = 1, expirationTime = T + 27, duration = 27 } }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.3)
RW = WatchXEating.rows[1]
""")
check(ev('RW.icon.TEX') == 900 or ev('RW.icon:GetTexture()') == 900 or "Conjured Water" in str(ev('RW.food.__text')), "Conjured Water (used) shown, not the Spring Water first in the bags: " + str(ev('RW.food.__text')))
ex(r"""
NS.lastUsedItem = nil
tick(5); AURAS = { { name = "Drink", spellId = 1137, icon = 1, expirationTime = GetTime() + 60, duration = 60 } }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.3)
""")
check("Refreshing Spring Water" in str(ev('WatchXEating.rows[1].food.__text')), "nothing used noted: the first with that spell, as before")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("food:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
