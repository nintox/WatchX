# Your bounties in guild chat (when ticked): posted, claimed, paid – plain words with the reward.
# And the bounty card: who did it is on the name's line, not over the heading.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex('SAID = {}; function SendChatMessage(msg, kind) SAID[#SAID+1] = kind .. ": " .. msg end')
def said(): return list(ev('SAID').values())

ex('NS.SetWanted(NS.KeyFromName("ola nordmann"), "ola nordmann", 52000, "ninja")')
check(said() == [], "not ticked: nothing in guild chat " + str(said()))
ex('NS.RemoveWanted("Ola-Nordmann"); tick(1); NS.db.wantedAnnounce = true')
ex('NS.SetWanted("Ola-Nordmann", "Ola Nordmann", 52000, "ninja")')
check(said() == ["GUILD: WANTED: Ola Nordmann – 5g 20s reward (ninja). Kill them and claim it!"], "posted: " + str(said()))
ex('SAID = {}; NS.SetWanted("Ola-Nordmann", "Ola Nordmann", 52000, "a new note")')
check(said() == [], "only the note changed: not said again " + str(said()))
ex('SAID = {}; tick(2); fire("CHAT_MSG_ADDON", "WatchX", table.concat({ "W1", "C", "Ola-Nordmann", "Kari-Nordmann", time(), NS.db.enemies["Ola-Nordmann"].wanted.t, "Kari-Nordmann", "Duskwood" }, "~"), "GUILD", "Kari-Nordmann")')
s = said()
check(len(s) == 1 and s[0].startswith("GUILD: BOUNTY CLAIMED: Kari Nordmann killed Ola Nordmann in Duskwood") and "5g 20s reward" in s[0], "claimed: " + str(s))
ex('SAID = {}; NS.MarkPaid("Ola-Nordmann")')
s = said()
check(len(s) == 1 and s[0].startswith("GUILD: BOUNTY PAID:") and "5g 20s for Ola Nordmann" in s[0], "paid: " + str(s))
check(not any("|c" in x or "|T" in x for x in said()), "plain words (no colours or coin icons)")

# the card: "by Kari" on the name line, the corner empty
ex('NS.db.nearby = true; NS.db.warnDock = false; NS.BountyCard("bountyKill", "Ola Nordmann", "5g", "by Kari Nordmann"); tick(0.2)')
check("Ola Nordmann" in str(ev('WatchXStealthToast.name:GetText()')) and "by Kari Nordmann" in str(ev('WatchXStealthToast.name:GetText()')),
      "card: who did it on the name line: " + str(ev('WatchXStealthToast.name:GetText()')))
check(ev('WatchXStealthToast.hint:GetText()') == "", "card: nothing in the corner over the heading")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("announce & card:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
