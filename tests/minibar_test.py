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
# the Enemies list's title: how many at the very end, ms / fps in the room between the title and it
ex('NS.db.nearby = true; NS.db.nearbyStats = true; NS.db.nearbyShowEmpty = true; NS.RefreshUI(); tick(1.5)')
ex('WatchXNearby:Show(); WatchXNearby.news:Hide(); tick(1.5)')
cp = ev('table.concat({ tostring(select(1, WatchXNearby.count:GetPoint(1))), tostring(select(3, WatchXNearby.count:GetPoint(1))), tostring(select(4, WatchXNearby.count:GetPoint(1))) }, " ")')
check(cp == "TOPRIGHT TOPRIGHT -8", "the count at the very end of the title's line, the title's top")
check(ev('select(2, WatchXNearby.stats:GetPoint(1)) == WatchXNearby.title and select(2, WatchXNearby.stats:GetPoint(2)) == WatchXNearby.count'),
      "ms / fps between the title and the count")
# room for it (the harness's font: 6 px a letter)
ex('local st = WatchXNearby.stats; st.GetUnboundedStringWidth = nil; st.GetStringWidth = function(self) local t = (self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") return #t * 6 end')
ex('WatchXNearby.stats.GetWidth = function() return 100 end; tick(1.5)')
check("ms" in str(ev('WatchXNearby.stats.__text')) and "fps" in str(ev('WatchXNearby.stats.__text')), "room: ms and fps")
ex('WatchXNearby.stats.GetWidth = function() return 40 end; tick(1.5)')
t = str(ev('WatchXNearby.stats.__text'))
print("    narrow:", t)
check("fps" in t and "ms" not in t, "a narrow list (the one in the picture): just the fps, not nothing")
ex('WatchXNearby.stats.GetWidth = function() return 10 end; tick(1.5)')
check(str(ev('WatchXNearby.stats.__text')) == "", "no room at all: nothing (never over the title)")
# unlocked: each bar's label is just its name (and its size); the how-to is in the tooltip when you hover it
ex('NS.StartMove(true); tick(1.5)')
lt = str(ev('WatchXMiniLabel and WatchXMiniLabel.text.__text'))
print("    mini bar label:", lt)
check("Mini bar" in lt and "%" in lt and "drag" not in lt, "the mini bar's label: its name and size, no how-to")
check("drag to move" in str(ev('WatchXMini.moveHint')), "the how-to kept for its tooltip")
ex('TIPL = {}; GameTooltip.SetText = function(self, t) TIPL = { t } end; GameTooltip.AddLine = function(self, t) TIPL[#TIPL + 1] = t end; NS.MoveHoversOn(); WatchXMini:GetScript("OnEnter")(WatchXMini)')
tip = str(ev('table.concat(TIPL, " | ")'))
print("    hover:", tip)
check("drag to move" in tip and "right edge: width" in tip, "hover while unlocked: how to move and size it")
ex('NS.StopMove()')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("mini bar:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
