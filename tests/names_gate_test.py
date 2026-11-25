# Only names the game would take go on the bounty list (and are taken in from others).
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

def problem(n): return ev('NS.NameProblem(%r)' % n)
for good in ["Ola-Nordmann", "Bob", "Ørjan-Åsheim", "Élise-Dubois", "Anna-Lee", "Иван-Петров"]:
    check(problem(good) is None, "fine: " + good)
for bad, why in [("Sug-Kuk", "rude"), ("Kurwa-Mac", "Polish"), ("Сука-Иван", "Russian, capital"), ("Пиздец", "Russian inside"), ("Merde-Bob", "French"), ("Hurensohnx-Ab", "German inside"), ("Kuk", "rude"), ("Fuckface-Bob", "rude inside"), ("Aaa-Bob", "three in a row"),
                 ("B-Smith", "too short"), ("Abcdefghijklm-Smith", "too long"), ("Bob1-Smith", "digits"), ("A-B-C", "three parts")]:
    check(problem(bad) is not None, "refused (%s): %s – %s" % (why, bad, problem(bad)))
ex('NS.SetWanted(NS.KeyFromName("sug kuk"), "sug kuk", 10000, "x")')
check(ev('NS.db.enemies["Sug-Kuk"] == nil or NS.db.enemies["Sug-Kuk"].wanted == nil'), "typed 'sug kuk': no bounty")
ex('fire("CHAT_MSG_ADDON", "WatchX", table.concat({ "W1", "A", "Sug-Kuk", "Sug Kuk", "", "10000", "", "Troll-Man", time(), "", "0", "", "0", "", "0" }, "~"), "GUILD", "Troll-Man")')
check(ev('NS.db.enemies["Sug-Kuk"] == nil'), "one like that from someone else: not taken in")
ex('NS.SetWanted(NS.KeyFromName("ola nordmann"), "ola nordmann", 10000, "ok")')
check(ev('NS.db.enemies["Ola-Nordmann"].wanted ~= nil'), "a real name still works")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("name gate:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
