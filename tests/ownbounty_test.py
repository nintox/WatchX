# Your own bounty can't be claimed by you: your kill claims nothing (it stays up), a claim from the one who put it
# up is ignored, and old own claims (allowed before) are taken off at login.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
SAID = {}
C_ChatInfo.SendAddonMessage = function(p, msg) table.insert(SAID, msg) end
function now() return time() end
function hear(from, ...) fire("CHAT_MSG_ADDON", "WatchX", table.concat({ "W1", ... }, "~"), "GUILD", from) end
function sent(s) local n = 0 for _, m in ipairs(SAID) do if m:find(s, 1, true) then n = n + 1 end end return n end
''')
# yours, one kill
ex('NS.SetWanted("Ola-Nordmann", "Ola Nordmann", 10000, "ganker"); tick(3); SAID = {}')
ex('NS.OnWantedKill("Ola-Nordmann"); tick(3)')
check(ev('NS.db.enemies["Ola-Nordmann"].wanted.claimed == nil'), "your kill on your own bounty: no claim")
check(ev('NS.Wanted("Ola-Nordmann") ~= nil'), "it stays up for someone else")
check(ev('sent("~C~Ola-Nordmann~")') == 0, "nothing sent")
# yours, 3 kills
ex('NS.SetWanted("Bob-Smith", "Bob Smith", 5000, "", nil, 3); tick(3); NS.OnWantedKill("Bob-Smith"); tick(3)')
check(ev('NS.db.enemies["Bob-Smith"].wanted.claims == nil'), "a several-kill bounty of yours: no claim either")
# someone else's, claimed by the one who put it up (an older WatchX): ignored
ex('tick(5); hear("Stian-Berg", "A", "Tom-Lie", "Tom Lie", "MAGE", "20000", "", "Stian-Berg", now(), "", "0", "", "0", "", "0")')
ex('hear("Stian-Berg", "C", "Tom-Lie", "Stian-Berg", now(), NS.db.enemies["Tom-Lie"].wanted.t, "Stian-Berg", "Duskwood")')
check(ev('NS.db.enemies["Tom-Lie"].wanted.claimed == nil') and ev('NS.Wanted("Tom-Lie") ~= nil'), "Stian claiming Stian's own bounty: ignored")
ex('hear("Kari-Nordmann", "C", "Tom-Lie", "Kari-Nordmann", now(), NS.db.enemies["Tom-Lie"].wanted.t, "Kari-Nordmann", "Duskwood")')
check(ev('NS.db.enemies["Tom-Lie"].wanted.claimed ~= nil'), "someone else claiming it: counts")
# an own claim from before: taken off at login, open again
ex('local w = NS.db.enemies["Ola-Nordmann"].wanted; w.claimed = { by = NS.MyName(), full = NS.MyName(), t = time() - 100 }; w.paid = time() - 50')
check(ev('NS.Wanted("Ola-Nordmann") == nil'), "(before: closed by your own old claim)")
ex('fire("PLAYER_LOGIN"); tick(14)')
check(ev('NS.db.enemies["Ola-Nordmann"].wanted.claimed == nil') and ev('NS.Wanted("Ola-Nordmann") ~= nil'), "after login: the old own claim is gone, open again")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("own bounty:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
