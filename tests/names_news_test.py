# Names typed in small letters find the player; bounty news shows a coin in the Nearby header; header clicks.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

P = lambda s: ev('NS.ProperName(%r)' % s)
check(P("bob smith") == "Bob Smith" and P("BOB-SMITH") == "Bob-Smith", "bob smith -> Bob Smith, BOB-SMITH -> Bob-Smith")
check(P("ørjan åsheim") == "Ørjan Åsheim" and P("ÉLISE") == "Élise", "æøå é: " + P("ørjan åsheim") + " " + P("ÉLISE"))
check(ev('NS.KeyFromName("bob smith")') == "Bob-Smith", "the key of a typed name: " + str(ev('NS.KeyFromName("bob smith")')))
ex('NS.SetWanted(NS.KeyFromName("ola nordmann"), "ola nordmann", 50000, "ninja")')
check(ev('NS.db.enemies["Ola-Nordmann"] ~= nil and NS.db.enemies["Ola-Nordmann"].wanted ~= nil'), "a bounty typed in small letters is on Ola-Nordmann")
check(ev('NS.Wanted("Ola-Nordmann") ~= nil'), "and the real player (as the game names him) is wanted")

# bounty news: the coin comes with a count, click opens the Wanted list, and it's gone once seen
ex('NS.db.nearby = true; NS.RefreshUI(); tick(1)')
check(not ev('WatchXNearby.news:IsShown()'), "no news: no coin")
ex('NS.AddBountyNews("bountyKill", "Ola Nordmann", "5g", "Kari", "Kari claimed the bounty on Ola Nordmann"); NS.AddBountyNews("bountyPaid", "X", "1g", "Y", "Y paid"); tick(1)')
check(ev('WatchXNearby:IsShown()') and ev('WatchXNearby.news:IsShown()') and ev('WatchXNearby.news.num:GetText()') == 2, "news: the coin with 2, the list shown for it")
ex('WatchXNearby.news.__scripts.OnClick(WatchXNearby.news, "LeftButton"); tick(1)')
check(ev('WatchXHistory ~= nil and WatchXHistory:IsShown()') or ev('NS.bountyUnread') == 0, "click: the Wanted list, news seen")
check(not ev('WatchXNearby.news:IsShown()'), "seen: the coin goes")
# the header: click = History, right-click = settings
ex('OPENED = nil; NS.OpenNearbySettings = function() OPENED = "settings" end; local old = NS.ShowHistory; NS.ShowHistory = function(...) OPENED = "history"; return old(...) end')
ex('WatchXNearby.__scripts.OnMouseUp(WatchXNearby, "LeftButton")'); check(ev('OPENED') == "history", "click on Nearby: the list")
ex('WatchXNearby.__scripts.OnMouseUp(WatchXNearby, "RightButton")'); check(ev('OPENED') == "settings", "right-click: settings")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("names & news:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
