# XP an hour on the XP bar, and Shift-click (or /wx xp reset) to count again from now.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
XPNOW = 1000
function UnitXP() return XPNOW end function UnitXPMax() return 67100 end
fire("PLAYER_XP_UPDATE", "player")
for i = 1, 12 do tick(10, 1); XPNOW = XPNOW + 500; fire("PLAYER_XP_UPDATE", "player") end   -- 6000 XP in 2 minutes
NS.RefreshXPBar()
''')
pct = str(ev('WatchXXPBar.pct.__text'))
print("    bar:", pct)
check("/h" in pct and "k/h" in pct, "XP an hour on the bar")
ex('NS.db.xpRateOnBar = false; NS.RefreshXPBar()')
check("/h" not in str(ev('WatchXXPBar.pct.__text')), "switched off: just the %")
ex('NS.db.xpRateOnBar = nil')
ex('IsShiftKeyDown = function() return true end; WatchXXPBar:GetScript("OnMouseUp")(WatchXXPBar, "LeftButton"); IsShiftKeyDown = function() return false end')
check("/h" not in str(ev('WatchXXPBar.pct.__text')), "Shift-click: counted again from now (no rate until there's XP)")
ex('for i = 1, 8 do tick(10, 1); XPNOW = XPNOW + 1000; fire("PLAYER_XP_UPDATE", "player") end; NS.RefreshXPBar()')
check("/h" in str(ev('WatchXXPBar.pct.__text')), "after more XP: the new rate " + str(ev('WatchXXPBar.pct.__text')))
ex('SlashCmdList["WATCHX"]("xp reset")')
check("/h" not in str(ev('WatchXXPBar.pct.__text')), "/wx xp reset does the same")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("xp rate:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
