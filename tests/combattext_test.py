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
ex('PLAYED = {}; PlaySound = function(id) PLAYED[#PLAYED + 1] = id; return true end')
ex('fire("PLAYER_REGEN_DISABLED")')
check(len(list(ev('PLAYED').values())) == 0, "no sound until you pick one")
ex('NS.db.sounds = NS.db.sounds or {}; NS.db.sounds.combatStart = "raid"; fire("PLAYER_REGEN_ENABLED"); fire("PLAYER_REGEN_DISABLED")')
check(len(list(ev('PLAYED').values())) == 1, "+Combat sound picked: played as the fight starts (not at the end)")
ex('NS.OpenNearbySettings(); MINI = NS.minimizeTest')
ex('NS.MinimizeWindow(true)')
check(ev('WatchXSettings:GetHeight()') == 50, "minimize: just the top line")
ex('NS.OpenWindow("kos")')
check(ev('WatchXSettings:GetHeight()') == 660, "opening a page shows it all again")
ex('NS.StartMove()')
check(ev('WatchXCombatText:IsShown()') and not ev('WatchXCombatText.fade:IsPlaying()'), "unlocked: shown to place it")
ex('NS.StopMove()')
check(not ev('WatchXCombatText:IsShown()'), "locked: gone again")
ex('NS.OpenNearbySettings()')
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("combat text:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
