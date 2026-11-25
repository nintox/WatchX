# XP food whose buff isn't called "Well Fed": learned while you eat it; the "+N% XP" beside the icons.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
function A(name, id, left, stacks, dur) return { name = name, spellId = id, expirationTime = left and (T + left) or 0, duration = dur or left or 0, applications = stacks or 0 } end
function look(sec) for i = 1, math.floor(sec) do tick(1, 0.25); NS.LevelStatus() end end
AURAS = { A("Arcane Intellect", 1459, 1500, 0, 1800) }; look(3)
''')
check(not ev('NS.levelBonus') or ev('NS.levelBonus.food') == 0, "no food buff: +0")
# eat through the strip's food icon: Food (20 s), then "Hearty Feast" for 15 min
ex('NS.foodUsedAt = GetTime(); AURAS = { A("Arcane Intellect", 1459, 1495, 0, 1800), A("Food", 433, 20, 0, 20) }; look(3)')
ex('AURAS = { A("Arcane Intellect", 1459, 1480, 0, 1800), A("Food", 433, 8, 0, 20), A("Hearty Feast", 777001, 900, 0, 900) }; look(3)')
check(ev('NS.db.xpBuffs and NS.db.xpBuffs[777001]') == "Hearty Feast", "the new 15-min buff is learned as the XP food's")
check(not (ev('NS.db.xpBuffs') and ev('NS.db.xpBuffs[1459]')), "a buff you already had isn't")
ex('AURAS = { A("Arcane Intellect", 1459, 1470, 0, 1800), A("Hearty Feast", 777001, 880, 0, 900), A("Well-Rested", 429959, 7000, 2, 7200) }; look(3)')
b = ev('NS.levelBonus')
check(b and b.food == 5 and b.bag == 2, "food + bag 2/3: +7%")
check("+7%" in str(ev('NS.levelFrame and NS.levelFrame.bonus:GetText()')), "beside the icons: " + str(ev('NS.levelFrame and NS.levelFrame.bonus:GetText()')))
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("xp food:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
