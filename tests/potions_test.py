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
SPELLS = { [6615] = "Free Action", [3169] = "Invulnerability", [71] = "Defensive Stance", [1680] = "Whirlwind", [100] = "Charge", [2457] = "Battle Stance", [2379] = "Speed" }
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
# several potions at once: each its own icon, the list shows both
ex('NS.db.plateStance = true; cast("nameplate1", 6615); tick(0.2); cast("nameplate1", 2379); tick(0.3)')
check(ev('PF.nameplate1.pots[1] and PF.nameplate1.pots[1]:IsShown() and PF.nameplate1.pots[2] and PF.nameplate1.pots[2]:IsShown()'), "Free Action and Swiftness: two icons on the plate")
ex('NS.RefreshUI(); tick(1.2)')
check("FREE ACTION" in str(ev('rowText()')) and "SWIFTNESS" in str(ev('rowText()')), "both in the list")
ex('tick(15, 1); NS.RefreshUI(); tick(1)')
check("SWIFTNESS" not in str(ev('rowText()')) and "FREE ACTION" in str(ev('rowText()')), "Swiftness over (15 s), Free Action still on")
check(ev('PF.nameplate1.pots[1]:IsShown()') and not ev('PF.nameplate1.pots[2]:IsShown()'), "the plate: one icon left")
ex('tick(16, 1)')
# your order: Free Action before Swiftness (default), though Swiftness is over sooner; then your own; how many
ex('cast("nameplate1", 2379); tick(0.3); cast("nameplate1", 6615); tick(0.3)')
check(ev('NS.ActivePotions(NS.nearby[key("nameplate1")])[1].label') == "Free Action", "default order: Free Action first")
ex('NS.SetPotionOrder("swift, free")')
check(ev('NS.db.potionOrder[1]') == "Swiftness" and ev('NS.db.potionOrder[2]') == "Free Action", "\"swift, free\" -> Swiftness, Free Action")
check(ev('NS.ActivePotions(NS.nearby[key("nameplate1")])[1].label') == "Swiftness", "now Swiftness first")
ex('CHATLINES = {}; NS.SetPotionOrder("Free Action, Bananas")')
check(ev('#NS.db.potionOrder') == 1, "an unknown name left out")
check("Bananas" in str(ev('table.concat(CHATLINES or {}, " ")')), "and said")
ex('NS.db.platePotionMax = 1; NS.UpdatePlates()')
check(ev('PF.nameplate1.pots[1]:IsShown()') and not ev('PF.nameplate1.pots[2]:IsShown()'), "at most 1 on a plate: one icon")
ex('NS.db.platePotionMax = 4; NS.UpdatePlates(); tick(31, 1)')
# your own potion: an item's name -> the spell it casts; then it shows like the others
ex('''
SPELLS[11405] = "Elixir of the Giants"; SPELLS[17549] = "Arcane Protection"
C_Item.GetItemSpell = function(n) if n == "Elixir of Giants" then return "Elixir of the Giants", 11405 end end
CHATLINES = {}
''')
check(ev('NS.AddCustomPotion("Elixir of Giants: 60")') == True, "added: Elixir of Giants: 60")
check(ev('NS.db.customPotions[1].spell') == "Elixir of the Giants" and ev('NS.db.customPotions[1].secs') == 60, "its spell and seconds")
check("Elixir of Giants 60s" in str(ev('NS.PotionListText()')), "in the list of watched ones")
check("Free Action 30s" in str(ev('NS.PotionListText()')), "the built-in ones in that list too")
ex('cast("nameplate1", 11405); tick(0.3)')
check(ev('NS.ActivePotions(NS.nearby[key("nameplate1")])[1].label') == "Elixir of Giants", "seen when they drink it")
check(ev('PF.nameplate1.pots[1]:IsShown()'), "on the plate")
ex('NS.SetPotionOrder("giants, free action")')
check(ev('NS.db.potionOrder[1]') == "Elixir of Giants", "yours can go in the order")
check(ev('NS.AddCustomPotion("17549: 20")') == True and ev('NS.db.customPotions[2].label') == "Arcane Protection", "by spell ID")
check(ev('NS.AddCustomPotion("Elixir of Giants: 45")') and ev('#NS.db.customPotions') == 2 and ev('NS.db.customPotions[2].secs') == 45, "added again: its seconds changed, not twice")
check(ev('NS.RemoveCustomPotion("elixir of giants")') == True and ev('#NS.db.customPotions') == 1, "removed")
check(ev('NS.RemoveCustomPotion("Free Action")') == False, "a built-in one can't be removed")
ex('tick(61, 1); cast("nameplate1", 11405); tick(0.3)')
check(len(list(ev('NS.ActivePotions(NS.nearby[key("nameplate1")])').values())) == 0, "removed: not watched")
ex('NS.SetPotionOrder("Free Action, Living Action, Invulnerability, Swiftness, Restorative")')
# the important ones: a glow on the plate, gold in the list, a sound when drunk
ex('''SOUNDS = {}; local oPS = PlaySound; PlaySound = function(id, ch) SOUNDS[#SOUNDS + 1] = id; return true end
SOUNDKIT = SOUNDKIT or {}; SOUNDKIT.ALARM_CLOCK_WARNING_2 = 12867''')
ex('tick(31, 1); cast("nameplate1", 2379); tick(0.3)')
check(ev('#SOUNDS') == 0, "Swiftness (no glow): no sound")
check(not ev('PF.nameplate1.pots[1].glow:IsShown()'), "and no glow")
ex('cast("nameplate1", 6615); tick(0.3)')
check(ev('#SOUNDS') == 1, "Free Action (glow): a sound")
check(ev('PF.nameplate1.pots[1].glow:IsShown()'), "Free Action's icon (first): a glow")
check(not ev('PF.nameplate1.pots[2].glow:IsShown()'), "Swiftness's: none")
ex('NS.RefreshUI(); tick(1.2)')
check("ffcc33FREE ACTION" in str(ev('rowText()')), "gold in the list")
ex('cast("nameplate1", 3169); tick(0.3)')
check(ev('#SOUNDS') == 1, "Invulnerability right after: no second sound (1.5 s)")
ex('NS.db.sounds = { potion = "off" }; tick(31, 1); cast("nameplate1", 6615); tick(0.3)')
check(ev('#SOUNDS') == 1, "sound off: none")
ex('NS.db.sounds = {}; NS.SetPotionGlow("swift"); tick(2); cast("nameplate1", 2379); tick(0.3)')
check(ev('NS.db.potionGlow[1]') == "Swiftness" and ev('#SOUNDS') == 2, "your own glow list: Swiftness now sounds")
ex('NS.SetPotionGlow("Free Action, Living Action, Invulnerability"); tick(31, 1)')
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
local oE2 = UnitExists
UnitExists = function(u) if u == "target" then return true end return oE2(u) end
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
''')
check(not ev('PF.nameplate3 and PF.nameplate3:IsShown()'), "a friend's plate: no icon (friendly icons off)")
ex('SlashCmdList.WATCHX("plates test"); tick(0.3)')
check(ev('PF.nameplate3 and PF.nameplate3:IsShown() and PF.nameplate3.pot and PF.nameplate3.pot:IsShown()'), "/wx plates test: the potion on the friend's plate")
check(ev('PF.nameplate3.stance and PF.nameplate3.stance:IsShown()'), "and the stance")
check(ev('PF.nameplate3.pots[2] and PF.nameplate3.pots[2]:IsShown()'), "two test potions")
check(not ev('PF.nameplate1.pot:IsShown()'), "not on another player's plate")
ex('tick(21, 1)')
check(not ev('PF.nameplate3:IsShown()'), "after 20 s: gone again")
check(not ev('NS.nearby[key("nameplate3")]'), "the friend isn't put in the Enemies list")
# ... and on a mob
ex('''
MOB = CreateFrame("Frame", nil, UIParent)
local gp = C_NamePlate.GetNamePlateForUnit
C_NamePlate.GetNamePlateForUnit = function(u) if u == "nameplate4" or u == "target" then return MOB end return gp(u) end
local oE3, oIU3, oG3, oP3, oN3 = UnitExists, UnitIsUnit, UnitGUID, UnitIsPlayer, UnitName
UnitExists = function(u) if u == "nameplate4" or u == "target" then return true end return oE3(u) end
UnitIsPlayer = function(u) if u == "nameplate4" or u == "target" then return false end return oP3(u) end
UnitGUID = function(u) if u == "nameplate4" or u == "target" then return "Creature-0-1-2-3-1234-0001" end return oG3(u) end
UnitName = function(u) if u == "target" then return "Kobold Miner", nil end return oN3(u) end
fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
''')
check(not ev('PF.nameplate4 and PF.nameplate4:IsShown()'), "a mob's plate: no icon")
ex('CHATLINES = {}; SlashCmdList.WATCHX("plates test"); tick(0.3)')
check(ev('PF.nameplate4 and PF.nameplate4:IsShown() and PF.nameplate4.pot:IsShown() and PF.nameplate4.stance:IsShown()'), "/wx plates test on a mob: icon, potion and stance")
check(not ev('PF.nameplate4.heal:IsShown()'), "no healer mark on the mob")
ex('tick(21, 1)')
check(not ev('PF.nameplate4:IsShown()'), "the mob's: gone after 20 s")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("potions:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
