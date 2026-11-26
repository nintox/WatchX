# +Combat / -Combat on screen (PvP > Enemies list > Combat): red as a fight starts, green when it's over.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex('fire("PLAYER_REGEN_DISABLED")')
check(ev('WatchXCombatText == nil or not WatchXCombatText:IsShown()'), "off by default: nothing")
ex('NS.db.combatText = true; fire("PLAYER_REGEN_DISABLED")')
check(ev('WatchXCombatText:IsShown()') and ev('WatchXCombatText.text:GetText()') == "+Combat", "a fight starts: +Combat")
check(ev('WatchXCombatText.fade:IsPlaying()'), "  and it fades by itself")
ex('fire("PLAYER_REGEN_ENABLED")')
check(ev('WatchXCombatText.text:GetText()') == "-Combat", "over: -Combat")
ex('NS.StartMove()')
check(ev('WatchXCombatText:IsShown()') and not ev('WatchXCombatText.fade:IsPlaying()'), "unlocked: shown to place it")
ex('NS.StopMove()')
check(not ev('WatchXCombatText:IsShown()'), "locked: gone again")
ex('NS.OpenNearbySettings()')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("combat text:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
