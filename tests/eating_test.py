# The eating & drinking tiles: time left, the % above, a "+N" tick each time the buff gives,
# and – when health/mana can't be read – what's still to come.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
MP = 1000
function UnitPower() return MP end function UnitPowerMax() return 5000 end
TIPS = {}
C_TooltipInfo.GetUnitAura = function(u, i) local t = TIPS[i] if t then return { lines = { { leftText = AURAS[i].name }, { leftText = t } } } end end
AURAS = { { name = "Drink", spellId = 1, icon = 1, expirationTime = T + 18, duration = 24 } }
TIPS = { "Restores 151 mana per second." }
fire("UNIT_AURA", "player"); NS.RefreshEating(); tick(0.2)
R = WatchXEating.rows[1]
''')
check(ev('WatchXEating:IsShown()'), "drinking: the tile is up")
check(ev('R.time.__text') in ("17.8", "17.9"), "time left on the icon: " + str(ev('R.time.__text')))
check("20%" in str(ev('R.pct.__text')), "the % above: " + str(ev('R.pct.__text')))
check("+151" in str(ev('R.tick.__text')), "a tick: " + str(ev('R.tick.__text')))
ex('FIRST = R.nextTick; tick(1.05)')
check(ev('R.nextTick') > ev('FIRST'), "the next tick a second later")
check("ends at" in str(ev('R.info.__text')) or "full in" in str(ev('R.info.__text')), "where it ends: " + str(ev('R.info.__text')))

# smooth: buffs looked at again and again (UNIT_AURA) don't restart the tick – one a second
ex('PLAYS = 0; local old = R.tickAnim.Play; R.tickAnim.Play = function(s) PLAYS = PLAYS + 1; return old(s) end')
ex('for i = 1, 20 do fire("UNIT_AURA", "player"); tick(0.25) end')
check(4 <= ev('PLAYS') <= 6, "5 s with UNIT_AURA every 0.25 s: one tick a second (%d)" % ev('PLAYS'))

# health/mana hidden: no %, but what's still to come from the buff's words
ex('local s = {}; SECRET[s] = true; MP = s; tick(0.3)')
check(ev('R.pct.__text') == "", "hidden mana: no %")
check("to come" in str(ev('R.info.__text')), "what's to come: " + str(ev('R.info.__text')))
check(ev('R.bar:IsShown()'), "the game's own fill for hidden mana")
check("+151" in str(ev('R.tick.__text')), "the tick still comes")

# "X over Y sec": an even share each second
ex('MP = 1000; AURAS = { { name = "Food", spellId = 2, icon = 1, expirationTime = T + 30, duration = 30 } }; TIPS = { "Restores 1,338 health over 30 sec." }; fire("UNIT_AURA", "player"); tick(0.5)')
check("+45" in str(ev('WatchXEating.rows[1].tick.__text')), "food over 30 s: +45 a second: " + str(ev('WatchXEating.rows[1].tick.__text')))

ex('AURAS = {}; fire("UNIT_AURA", "player"); tick(0.5)')
check(not ev('WatchXEating:IsShown()'), "done eating: gone")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("eating:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
