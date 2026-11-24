# "Has run out" warnings must only come when the buff really is gone:
# not for a buff that's off for a moment, not from a look in (or right around) a fight, not by the clock in a fight.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
WELL_RESTED, WELL_FED = 429959, 1243969
function A(name, id, left, stacks, dur)
  return { name = name, spellId = id, expirationTime = left and (T + left) or 0, duration = dur or left or 0, applications = stacks or 0 }
end
function secret() local s = {}; SECRET[s] = true; return s end
function hidden(n) local t = {} for i = 1, n do t[i] = { name = secret(), spellId = secret(), expirationTime = secret(), applications = secret() } end return t end
function warns() local t = {} for _, w in ipairs(WARNS) do if w:find("run out") then t[#t+1] = w end end return t end
function look(sec) for i = 1, math.floor(sec) do tick(1, 0.25); NS.LevelStatus(); NS.CheckBuffs() end end
function normal() return { A("Well-Rested", WELL_RESTED, 7000, 3, 7200), A("Well Fed", WELL_FED, 800, 0, 900), A("Water Breathing", 131, 500, 0, 600) } end
NS.db.buffCustom = { "Water Breathing" }
AURAS = normal(); look(5); WARNS = {}
''')
def runout(): return list(ev('warns()').values())

# 1. off for a moment (a new stack, a renewal): no warning
ex('AURAS = { A("Well Fed", WELL_FED, 790, 0, 900), A("Water Breathing", 131, 490, 0, 600) }; look(2)')
ex('AURAS = normal(); look(25)')
check(runout() == [], "a buff off for a moment: no 'has run out' " + str(runout()))

# 2. a fight: the look at its start can't make the buffs out (hidden), the fight goes on, they're still there after
ex('WARNS = {}; INFIGHT = true; AURAS = hidden(3); look(1); COMBAT = true; look(40)')
ex('COMBAT = false; INFIGHT = false; fire("PLAYER_REGEN_ENABLED"); look(1); AURAS = normal(); look(30)')
check(runout() == [], "a fight with hidden buffs, all still there after it: no warning " + str(runout()))

# 3. renewed in a fight after its clock ran out: no warning after the fight
ex('WARNS = {}; AURAS = { A("Well-Rested", WELL_RESTED, 7000, 3, 7200), A("Well Fed", WELL_FED, 800, 0, 900), A("Water Breathing", 131, 20, 0, 600) }; look(3)')
ex('INFIGHT = true; COMBAT = true; look(30); AURAS = normal(); look(5)')
ex('COMBAT = false; INFIGHT = false; fire("PLAYER_REGEN_ENABLED"); look(30)')
check(runout() == [], "Water Breathing ran out by the clock in a fight but was renewed: no warning " + str(runout()))

# 4. really gone (out of combat): one warning each, only after it stayed gone a while
# Water Breathing clicked off early: no warning; then a new one that runs out at its time
ex('WARNS = {}; AURAS = { A("Well-Rested", WELL_RESTED, 7000, 3, 7200), A("Well Fed", WELL_FED, 700, 0, 900) }; look(3)')
check(runout() == [], "clicked off early: no warning " + str(runout()))
ex('AURAS = { A("Well-Rested", WELL_RESTED, 7000, 3, 7200), A("Well Fed", WELL_FED, 700, 0, 900), A("Water Breathing", 131, 4, 0, 600) }; look(5)')
ex('AURAS = { A("Well Fed", WELL_FED, 690, 0, 900) }; look(8)')
check(runout() == [], "gone for a few seconds only: nothing yet " + str(runout()))
ex('look(25)')
w = runout()
check(sum("Well-Rested" in x for x in w) == 1 and sum("Water Breathing" in x for x in w) == 1,
      "really gone: Well-Rested and Water Breathing said once each " + str(w))
ex('WARNS = {}; AURAS = {}; look(30)')
check(sum("Well Fed has run out" in x for x in runout()) == 1, "Well Fed really gone: said once " + str(runout()))
ex('WARNS = {}; look(60)')
check(runout() == [], "and not again " + str(runout()))

errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("warnings:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
