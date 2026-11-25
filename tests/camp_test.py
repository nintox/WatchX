# The camp: a "Camp Benefits" icon on the XP strip with what the camp gave you; the sitting minute before it;
# the sleeping bag at 3/3 says "lie again" once it's ready (back to 2 hours).
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
function A(name, id, left, stacks, inst) return { name = name, spellId = id, expirationTime = left and (T + left) or 0, duration = left or 0, applications = stacks or 0, auraInstanceID = inst } end
function look(sec) for i = 1, math.floor(sec) do tick(1, 0.25) end; return NS.LevelStatus() end
function row(slot) for _, r in ipairs(look(3) or {}) do if r.slot == slot then return r end end end
C_TooltipInfo.GetUnitBuffByAuraInstanceID = function(u, inst)
  if inst == 77 then return { lines = { { leftText = "Camp Benefits" }, { leftText = "Increases all stats by 8%." },
    { leftText = "Increases Stamina by 56." }, { leftText = "58 minutes remaining" } } } end
end
''')
ex('AURAS = { A("Arcane Intellect", 1459, 1800) }')
check(not ev('row("camp")'), "no camp: no camp icon")
ex('AURAS = { A("Arcane Intellect", 1459, 1800), A("Welcoming Campfire", 1289723, 40) }')
check(ev('row("camp") and row("camp").state') == "wait", "sitting by the fire: the minute counts down")
ex('AURAS = { A("Arcane Intellect", 1459, 1800), A("Camp Benefits", 1229741, 3500, 0, 77), A("Sharpened", 555001, 3510) }')
r = ev('row("camp")')
txt = str(r and r.text)
print("    camp:", txt.replace("\n", " | "), "|", r and r.timer)
check(r and r.state == "ok", "Camp Benefits: green")
check("all stats by 8%" in txt and "Stamina by 56" in txt, "its effects, line by line")
check("remaining" not in txt and not txt.startswith("Camp Benefits"), "without its name and the time line")
check("Sharpened" in txt and "Arcane" not in txt, "a buff that came with it is listed, others aren't")
check(r and r.timer and 3400 < r.timer < 3500, "the time left")
# the sleeping bag: 3/3 and ready again -> yellow, "lie on it again"
ex('C_Item.GetItemCount = function(id) return id == 211527 and 1 or 0 end; GetItemCount = C_Item.GetItemCount; NS.bagsDirty = true')
ex('AURAS = { A("Well-Rested", 429959, 3480, 3) }; if NS.OnBagsChanged then NS.OnBagsChanged() end; fire("BAG_UPDATE_DELAYED")')
b = ev('row("bag")')
print("    bag:", b and b.state, str(b and b.text))
check(b and b.state == "wait" and "2 hours" in str(b.text), "3/3, bag ready: lie again for 2 hours")
ex('AURAS = { A("Well-Rested", 429959, 7100, 3) }')
b = ev('row("bag")')
check(b and b.state == "ok", "3/3 and just renewed: green")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("camp:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
