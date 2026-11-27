# The mini bar with the rare scan off: no "Nothing watched" hint and no rares on it (none is looked for); it goes
# away when nothing else is on it, and comes back with the scan.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

def text():
    return ev('(function() local t = {} for _, r in ipairs(WatchXMini.rows) do if r.name:IsShown() then t[#t + 1] = tostring(r.name:GetText()) end end return table.concat(t, " | ") end)()')

ex('NS.db.enemyPlayers = false; NS.db.friendlyPlayers = false; NS.db.hideIdle = false; NS.db.miniQuiet = false; NS.db.show = true')
ex('for k in pairs(NS.db.watch) do NS.db.watch[k] = nil end; NS.SetScan(true); tick(1.5)')
check("Nothing watched" in text(), "scan on, nothing picked: the hint (%s)" % text())
ex('NS.SetScan(false); tick(1.5)')
check("Nothing watched" not in text(), "scan off: no hint (%s)" % text())
check(ev('WatchXMini.visible') == False, "and the mini bar goes away (nothing on it)")
name = ev('NS.GetMobList()[1].name')
ex('NS.SetWatched(NS.GetMobList()[1].name, true); tick(1.5)')
check(name not in text(), "scan off: a watched rare isn't on the bar (it isn't looked for)")
ex('NS.SetScan(true); tick(1.5)')
check(name in text(), "scan on again: it is")
ex('NS.SetScan(false); NS.StartMove(true); tick(1.5)')
check("Rare scan off" in text() and ev('WatchXMini.visible') == True, "unlocked: shown, 'Rare scan off', to place it by")
ex('NS.StopMove(); NS.SetScan(true)')
# the Enemies list's title: ms / fps never run into "2 near" (the count keeps the coin's place even without a coin)
ex('NS.db.nearby = true; NS.db.nearbyStats = true; NS.db.nearbyShowEmpty = true; NS.RefreshUI(); tick(1.5)')
ex('WatchXNearby:Show(); local c = WatchXNearby.count; c:SetText("2 near"); c.SetText = function() end; WatchXNearby.news:Hide(); WatchXNearby.statsAt = nil; tick(1.5)')
x = ev('(select(4, WatchXNearby.stats:GetPoint(1)))')
cw = ev('WatchXNearby.count:GetStringWidth()')
print("    stats right edge at %s, count from %s" % (x, -(7 + 18 + 8 + cw)))
check(x is not None and x <= -(7 + 18 + 8 + cw) - 6, "ms / fps left of '2 near', with a gap")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("mini bar:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
