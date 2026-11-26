# Sizes without dragging: WatchX settings > SIZE (+ / -) and /wx size 150 – for a small screen (a MacBook's).
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex('NS.RefreshUI(); NS.RefreshXPBar(); NS.RefreshLevel()')
check(ev('NS.GetSize("miniScale")') == 1, "starts at 100 %")
ex('SlashCmdList["WATCHX"]("size 150")')
for k in ("miniScale", "nearbyScale", "xpBarScale", "levelScale", "rebuffScale"):
    check(ev('NS.db.%s' % k) == 1.5, "/wx size 150: %s 150 %%" % k)
check(abs(ev('WatchXMini and WatchXMini:GetScale() or NS.GetSize("miniScale")') - 1.5) < 0.001, "the mini bar is drawn at 150 %")
ex('SlashCmdList["WATCHX"]("size 900")')
check(ev('NS.db.miniScale') == 3, "at most 300 %")
ex('SlashCmdList["WATCHX"]("size")')
# the settings page: + / - rows
ex('NS.OpenSettings()')
ex('SlashCmdList["WATCHX"]("size 100")')
ex('NS.SetSize("levelScale", NS.GetSize("levelScale") + 0.1)')
check(ev('NS.db.levelScale') == 1.1, "+ : the XP boost icons 10 % bigger")
check(abs(ev('WatchXLeveling and WatchXLeveling:GetScale() or 1.1') - 1.1) < 0.001, "and drawn so")
ex('NS.db.nearby = true; NS.AttachNearby(); NS.RefreshUI()')
if ev('WatchXNearby and WatchXNearby.attached'):
    ex('NS.SetSize("nearbyScale", 1.4)')
    check(ev('NS.db.miniScale') == 1.4 and abs(ev('WatchXNearby:GetScale()') - 1.4) < 0.001, "Enemies list under the mini bar: + makes it (and the mini bar) bigger")
    ex('NS.SetSize("miniScale", 1)')
else:
    check(False, "the Enemies list hangs under the mini bar in this test")
ex('InCombatLockdown = function() return true end')
check(ev('NS.SetSize("miniScale", 2)') == False and ev('NS.db.miniScale') == 1, "not in a fight")
ex('InCombatLockdown = function() return false end')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("size:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
