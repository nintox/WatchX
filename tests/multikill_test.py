# Bounties for several kills: the reward per kill, open until the limit, owed per player, paid per player.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
SAID = {}
C_ChatInfo.SendAddonMessage = function(prefix, msg, chan, to) SAID[#SAID+1] = msg end
function hear(from, ...) fire("CHAT_MSG_ADDON", "WatchX", table.concat({ "W1", ... }, "~"), "GUILD", from) end
function now() return time() end
''')

# --- your bounty: 1g a kill, 3 kills
ex('NS.SetWanted("Ola-Nordmann", "Ola Nordmann", 10000, "ganker", nil, 3); WT = NS.db.enemies["Ola-Nordmann"].wanted.t; tick(3)')
check(ev('NS.db.enemies["Ola-Nordmann"].wanted.kills') == 3, "posted with 3 kills")
check(any("~A~Ola-Nordmann~" in m and m.endswith("~3") for m in ev('SAID').values()), "the limit goes along in the message")
ex('tick(5); hear("Kari-Nordmann", "C", "Ola-Nordmann", "Kari-Nordmann", now(), WT, "Kari-Nordmann", "Duskwood")')
check(ev('NS.Wanted("Ola-Nordmann") ~= nil'), "1 kill of 3: still open")
ex('tick(5); hear("Kari-Nordmann", "C", "Ola-Nordmann", "Kari-Nordmann", now(), WT, "Kari-Nordmann", "Duskwood")')
ex('tick(5); hear("Kari-Nordmann", "C", "Ola-Nordmann", "Kari-Nordmann", now() - 5, WT, "Kari-Nordmann", "Duskwood")')
check(ev('#NS.db.enemies["Ola-Nordmann"].wanted.claims') == 2, "the same kill heard twice counts once")
ex('tick(5); hear("Per-Hansen", "C", "Ola-Nordmann", "Per-Hansen", now(), WT, "Per-Hansen", "Westfall")')
check(ev('NS.Wanted("Ola-Nordmann") == nil'), "3 of 3: closed")
ex('tick(5); hear("Kari-Nordmann", "C", "Ola-Nordmann", "Kari-Nordmann", now(), WT, "Kari-Nordmann", "Duskwood")')
check(ev('#NS.db.enemies["Ola-Nordmann"].wanted.claims') == 3, "a 4th kill doesn't count")
ex('OWED = NS.OwedBounties()')
check(ev('#OWED') == 2 and ev('OWED[1].to') == "Kari-Nordmann" and ev('OWED[1].copper') == 20000 and ev('OWED[1].n') == 2
      and ev('OWED[2].to') == "Per-Hansen" and ev('OWED[2].copper') == 10000, "owed per player: Kari 2g (2 kills), Per 1g")
ex('SAID = {}; NS.MarkPaid("Ola-Nordmann", "Kari-Nordmann"); tick(3)')
check(ev('#NS.OwedBounties()') == 1 and any("~P~Ola-Nordmann~" in m and "Kari-Nordmann" in m for m in ev('SAID').values()),
      "Kari paid: one debt left, the payment names her")
ex('NS.MarkPaid("Ola-Nordmann")')
check(ev('NS.WantedState(NS.db.enemies["Ola-Nordmann"].wanted).settled') == True, "all paid: settled")
check("3/3 kills" in ev('NS.WantedLine(NS.db.enemies["Ola-Nordmann"].wanted)'), "the line says 3/3 kills")

# --- someone else's: 50s a kill, 2 kills; you kill twice
ex('tick(5); hear("Stian-Berg", "A", "Bob-Smith", "Bob Smith", "ROGUE", "5000", "camper", "Stian-Berg", now(), "", "0", "", "0", "", "0", "2")')
check(ev('NS.db.enemies["Bob-Smith"].wanted.kills') == 2, "learned with its 2 kills")
ex('SAID = {}; NS.OnWantedKill("Bob-Smith"); tick(30); NS.OnWantedKill("Bob-Smith"); tick(3)')
check(ev('#NS.db.enemies["Bob-Smith"].wanted.claims') == 2 and ev('NS.Wanted("Bob-Smith") == nil'), "two kills by you: closed")
check(sum("~C~Bob-Smith~" in m for m in ev('SAID').values()) == 2, "each kill claimed")
ex('DUE = NS.OwedToMe()')
check(ev('#DUE') == 1 and ev('DUE[1].copper') == 10000 and ev('DUE[1].n') == 2, "owed to you: 1g for 2 kills")
ex('hear("Stian-Berg", "P", "Bob-Smith", "Stian-Berg", NS.db.enemies["Bob-Smith"].wanted.t, "Rikerud", now())')
check(ev('#NS.OwedToMe()') == 0, "Stian paid you")

# --- a one-kill bounty works as always
ex('tick(5); hear("Stian-Berg", "A", "Tom-Lie", "Tom Lie", "MAGE", "20000", "", "Stian-Berg", now(), "", "0", "", "0", "", "0")')
ex('NS.OnWantedKill("Tom-Lie")')
check(ev('NS.db.enemies["Tom-Lie"].wanted.claimed ~= nil') and ev('NS.db.enemies["Tom-Lie"].wanted.claims') is None and ev('NS.Wanted("Tom-Lie") == nil'),
      "one kill: claimed the old way, closed")
# the bounty window: a Kills box, filled in for one you have
ex('NS.ShowBounty("Ola-Nordmann")')
check(ev('WatchXBounty.kills:GetText()') == "3", "the window shows 3 kills: " + str(ev('WatchXBounty.kills:GetText()')))
# the History list: 3/3 kills, the reward ×3
ex('NS.ShowHistory("wanted"); tick(1)')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:400] if errs else ""))
print("multi-kill:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
