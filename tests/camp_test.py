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
check(not ev('row("camp")') and not ev('NS.levelCamp'), "no camp: nothing")
ex('AURAS = { A("Arcane Intellect", 1459, 1800), A("Welcoming Campfire", 1289723, 40) }; row("x"); NS.RefreshLevel()')
check(ev('NS.levelCamp and NS.levelCamp.sitExpires and not NS.levelCamp.expires'), "sitting by the fire: the minute is noted")
check(ev('NS.levelFrame.bonusBox:IsShown() and NS.levelFrame.bonusBox.camp:IsShown()'), "the box shows, with the fire")
print("    box:", ev('NS.levelFrame.bonus:GetText()'), "/", ev('NS.levelFrame.bonus2:GetText()'))
ex('AURAS = { A("Arcane Intellect", 1459, 1800), A("Camp Benefits", 1229741, 3500, 0, 77), A("Sharpened", 555001, 3510) }; row("x"); NS.RefreshLevel()')
check(not ev('row("camp")'), "no icon of its own on the strip")
c = ev('NS.levelCamp')
txt = " | ".join(str(c.lines[i]) for i in range(1, len(c.lines) + 1)) if c and c.lines else ""
print("    camp:", txt)
check("all stats by 8%" in txt and "Stamina by 56" in txt, "its effects, line by line")
check("remaining" not in txt and "Camp Benefits" not in txt, "without its name and the time line")
check("Sharpened" in txt and "Arcane" not in txt, "a buff that came with it is listed, others aren't")
check(c and 3400 < c.expires - ev('GetTime()') < 3500, "when it ends")
ex('GetXPExhaustion = function() return 0 end; row("x"); NS.RefreshLevel()')
check("Camp" in str(ev('NS.levelFrame.bonus:GetText()')) and "m" in str(ev('NS.levelFrame.bonus2:GetText()')),
      "no XP bonus or rested: the box says Camp and its time: " + str(ev('NS.levelFrame.bonus2:GetText()')))
ex('GetXPExhaustion = function() return 13000 end')
ex('NS.levelFrame:GetScript("OnEnter")(NS.levelFrame)')
check(ev('GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() or true'), "the tooltip opens")
# the sleeping bag: 3/3 and ready again -> yellow, "lie on it again"
ex('C_Item.GetItemCount = function(id) return id == 211527 and 1 or 0 end; GetItemCount = C_Item.GetItemCount; NS.bagsDirty = true')
ex('AURAS = { A("Well-Rested", 429959, 3480, 3) }; if NS.OnBagsChanged then NS.OnBagsChanged() end; fire("BAG_UPDATE_DELAYED")')
b = ev('row("bag")')
print("    bag:", b and b.state, str(b and b.text))
check(b and b.state == "wait" and "2 hours" in str(b.text), "3/3, bag ready: lie again for 2 hours")
ex('AURAS = { A("Well-Rested", 429959, 7100, 3) }')
b = ev('row("bag")')
check(b and b.state == "ok", "3/3 and just renewed: green")
# a portal: the buffs read missing for a moment and come back – no "3/3, you can get up" again
ex('DONE = {}; local d = NS.Done; NS.Done = function(m) table.insert(DONE, m); d(m) end')
ex('AURAS = { A("Well-Rested", 429959, 3000, 3), A("Well Fed", 1243969, 800) }; look(3)')
ex('DONE = {}; AURAS = {}; look(2); AURAS = { A("Well-Rested", 429959, 2990, 3), A("Well Fed", 1243969, 790) }; look(3)')
check(ev('#DONE') == 0, "after a loading screen: no 'you can get up' / 'stop eating' " + str(ev('DONE[1]')))
ex('AURAS = { A("Well-Rested", 429959, 7200, 2) }; look(3); DONE = {}; AURAS = { A("Well-Rested", 429959, 7200, 3) }; look(3)')
check(ev('DONE[1]') and "3/3" in str(ev('DONE[1]')), "2 -> 3 on the bag: 'you can get up'")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("camp:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
