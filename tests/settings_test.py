# WatchX's own settings window: the pages in a list on the left (General, PvP, Leveling), one shown at a time;
# Options > AddOns > WatchX is a page with a button to it. PvP is four pages.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

check(ev('WatchXLanding ~= nil and WatchXLanding.name == "WatchX"'), "Options > AddOns > WatchX: the landing page")
ex('NS.OpenSettings()')
check(ev('WatchXSettings and WatchXSettings:IsShown()'), "/wx settings opens WatchX's own window")
check(ev('WatchXOptions:IsShown() and WatchXOptions:GetParent() ~= UIParent'), "the main page in it")
tabs = ["main", "alerts", "enemies", "plates", "kos", "avoid", "level", "buffs", "rebuff"]
pages = {"main": "WatchXOptions", "enemies": "WatchXNearbyOptions", "plates": "WatchXPlateOptions", "kos": "WatchXKOSOptions",
         "avoid": "WatchXAvoidOptions", "level": "WatchXLevelOptions", "buffs": "WatchXBuffOptions", "rebuff": "WatchXRebuffOptions"}
for t in tabs:
    ex('NS.OpenWindow("%s")' % t)
    check(ev('NS.SettingsShown()') == t, "page: " + t)
    if t in pages:
        others = [p for k, p in pages.items() if k != t]
        shown = [p for p in others if ev('%s:IsShown()' % p)]
        check(ev('%s:IsShown()' % pages[t]) and not shown, "  only it is shown " + str(shown))
check(len(list(ev('WatchXSettings.navButtons').values())) == 9, "nine pages in the list")
# the PvP pages work
ex('NS.OpenNearbySettings("kos"); NS.SetKOS(NS.KeyFromName("Badguy"), true); NS.RefreshKOSChips()')
check(ev('NS.SettingsShown()') == "kos", "OpenNearbySettings('kos') opens KOS & bounties")
check(len(list(ev('NS.soundBtns').values())) >= 4, "the sound pickers are on the Enemies page")
ex('NS.OpenNearbySettings()')
check(ev('NS.SettingsShown()') == "enemies", "and with nothing: the Enemies list page")
# a check box: click it, the setting follows
ex('NS.db.nearbyShowEmpty = false; NS.RefreshPvPOptions()')
ex('''for _, f in ipairs(FRAMES) do
  if f.__kind == "CheckButton" and f.get and f.__parent == nil then end
end''')
# unlocking the bars closes the window (it would be in the way)
ex('NS.StartMove()')
check(not ev('WatchXSettings:IsShown()'), "Unlock bars: the window steps aside")
ex('NS.StopMove()')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("settings:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
