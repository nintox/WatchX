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
check("20%|r |cffcccccc»|r |cff4da6ff7" in str(ev("R.pct.__text")), "now » where it ends: " + str(ev('R.pct.__text')))

# the tick fades in where it is, rises, fades – and when it's done it stays gone (no drop back down)
ex('R.tickAnim:GetScript("OnFinished")(R.tickAnim)')
check(ev('R.tick:GetAlpha()') == 0, "the tick's animation over: gone, not back at its spot")
# smooth: buffs looked at again and again (UNIT_AURA) don't restart the tick – one a second
ex('PLAYS = 0; local old = R.tickAnim.Play; R.tickAnim.Play = function(s) PLAYS = PLAYS + 1; return old(s) end')
ex('for i = 1, 20 do fire("UNIT_AURA", "player"); tick(0.25) end')
check(4 <= ev('PLAYS') <= 6, "5 s with UNIT_AURA every 0.25 s: one tick a second (%d)" % ev('PLAYS'))

# health/mana hidden: no %, but what's still to come from the buff's words
ex('local s = {}; SECRET[s] = true; MP = s; tick(0.3)')
check(ev('R.pct.__text') == "", "hidden mana: no %")
check(ev('R.info.__text') == "", "no line under the icon: " + str(ev('R.info.__text')))
check(ev('R.bar:IsShown()'), "the game's own fill for hidden mana")
check("+151" in str(ev('R.tick.__text')), "the tick still comes")
# hidden mana, but the game's curve API is there: "26% » 95%" worked out by the game
ex(r"""
CurveConstants = { ScaleTo100 = { scale = true } }
Enum = Enum or {}; Enum.LuaCurveType = { Linear = 1 }
C_CurveUtil = { CreateCurve = function()
  local c = { pts = {} }
  function c:SetType() end
  function c:AddPoint(x, y) self.pts[#self.pts+1] = { x, y } end
  return c end }
local function eval(c, x)
  if c.scale then return x * 100 end
  for i = 2, #c.pts do local a, b = c.pts[i-1], c.pts[i]; if x <= b[1] then return a[2] + (b[2]-a[2]) * (x-a[1]) / (b[1]-a[1]) end end
  return c.pts[#c.pts][2]
end
function UnitPowerPercent(u, pt, pred, curve) return eval(curve, 0.26) end
methods.SetFormattedText = function(self, f, ...) self.__text = string.format(f, ...) end
tick(0.3)
""")
t = str(ev('R.pct.__text'))
check("26%|r |cffcccccc»|r" in t, "hidden: now » end through the curve: " + t)


# "X over Y sec": an even share each second
ex('MP = 1000; AURAS = { { name = "Food", spellId = 2, icon = 1, expirationTime = T + 30, duration = 30 } }; TIPS = { "Restores 1,338 health over 30 sec." }; fire("UNIT_AURA", "player"); tick(0.5)')
check("+45" in str(ev('WatchXEating.rows[1].tick.__text')), "food over 30 s: +45 a second: " + str(ev('WatchXEating.rows[1].tick.__text')))

ex('AURAS = {}; fire("UNIT_AURA", "player"); tick(0.5)')
check(not ev('WatchXEating:IsShown()'), "done eating: gone")
# unlock and lock with nothing to eat: the "drag to move" label goes away too
ex('AURAS = {}; NS.StartMove(); tick(1, 0.25)')
check(ev('WatchXEatingLabel and WatchXEatingLabel:IsShown()'), "unlocked: the label shows")
ex('NS.StopMove(); tick(1, 0.25)')
check(not ev('WatchXEatingLabel:IsShown()'), "locked: the label is gone")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("eating:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
