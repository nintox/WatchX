# A mage's "Scroll: …" in the bags: hovering it puts a secure button over it whose right-click casts Comprehend
# Scroll on that very slot; not for other items, not without the spell, not while writing a letter, not in a fight.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
ITEMS = { [0] = { [3] = "|cffffffff|Hitem:900001::|h[Scroll: Arcane Ward]|h|r", [4] = "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r" } }
C_Container.GetContainerItemInfo = function(bag, slot) local l = ITEMS[bag] and ITEMS[bag][slot] if l then return { hyperlink = l, itemID = 1 } end end
KNOWS = true
IsPlayerSpell = function(id) return KNOWS and id == 1310030 end
C_Spell.GetSpellName = function(id) if id == 1310030 then return "Comprehend Scroll" end return "Spell" .. id end
OWNER = CreateFrame("Button", "BagSlot", UIParent); OWNER:SetSize(37, 37)
OWNER.GetLeft = function() return 500 end; OWNER.GetBottom = function() return 300 end
LINES = {}
GameTooltip.GetOwner = function() return OWNER end
GameTooltip.AddLine = function(self, t) table.insert(LINES, t) end
function hover(bag, slot) LINES = {}; NS.ComprehendHover(GameTooltip, bag, slot) end
''')
ex('hover(0, 4)')
check(ev('WatchXComprehend == nil or not WatchXComprehend:IsShown()'), "linen cloth: nothing")
ex('hover(0, 3)')
check(ev('WatchXComprehend ~= nil and WatchXComprehend:IsShown()'), "a scroll: the button over it")
check(ev('WatchXComprehend:GetAttribute("macrotext2")') == "/cast Comprehend Scroll\n/use 0 3", "right-click: the spell onto bag 0 slot 3")
check(ev('WatchXComprehend:GetAttribute("type2")') == "macro" and ev('WatchXComprehend:GetAttribute("type1")') is None, "left-click isn't ours (the bag's own)")
check(ev('LINES[1]') == "Right-click: Comprehend Scroll", "the tooltip says so")
ex('NS.ComprehendHover(GameTooltip, 0, 3)')
check(ev('#LINES') == 1, "the same tooltip twice: the line once")
ex('WatchXComprehend:GetScript("OnLeave")(WatchXComprehend)')
check(not ev('WatchXComprehend:IsShown()'), "mouse away: gone")
ex('KNOWS = false; C_Spell.GetSpellInfo = function() return nil end; tick(1); hover(0, 3)')
check(not ev('WatchXComprehend:IsShown()'), "without the spell (not a mage): nothing")
ex('KNOWS = true; SendMailFrame = CreateFrame("Frame"); SendMailFrame:Show(); tick(1); hover(0, 3)')
check(not ev('WatchXComprehend:IsShown()'), "writing a letter: right-click is the mail's")
ex('SendMailFrame:Hide(); local c = InCombatLockdown; InCombatLockdown = function() return true end; tick(1); hover(0, 3); InCombatLockdown = c')
check(not ev('WatchXComprehend:IsShown()'), "in a fight: nothing")
ex('NS.db.comprehendClick = false; tick(1); hover(0, 3)')
check(not ev('WatchXComprehend:IsShown()'), "switched off: nothing")
# /wx scroll: says what it sees
ex('NS.db.comprehendClick = nil; PRINTED = {}; local p = NS.Print; NS.Print = function(m) table.insert(PRINTED, m) end; NS.ScrollDebug(); NS.Print = p')
out = str(ev('table.concat(PRINTED, "\\n")'))
print("    " + out.replace("\n", "\n    "))
check("known" in out and "Scroll: Arcane Ward" in out and "can be comprehended" in out, "/wx scroll: the spell, your scrolls")
ex('IsPlayerSpell = function() return false end; C_SpellBook = { IsSpellKnown = function(id) return id == 1309973 end }')
check(ev('NS.ComprehendSpell()') is not None, "known through C_SpellBook too (IsPlayerSpell saying no)")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("scrolls:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
