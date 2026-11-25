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
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("food:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
