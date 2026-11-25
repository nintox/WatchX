# PvP sounds: one choice per kind, "Sounds" off silences all, the new-enemy one at most every 5 s.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
SOUNDKIT.ALARM_CLOCK_WARNING_3 = 11; SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING = 12; SOUNDKIT.MAP_PING = 13
PLAYED = {}
function PlaySound(id) table.insert(PLAYED, id) end
function played() local t = PLAYED; PLAYED = {}; return table.concat(t, ",") end
''')
ns = 'NS'
ex('NS.AlertSound("stealth")'); check(ev('played()') == "1", "stealth: raid warning")
ex('NS.AlertSound("kos")'); check(ev('played()') == "11", "KOS: alarm")
ex('NS.AlertSound("wanted")'); check(ev('played()') == "12", "WANTED: boss whisper")
ex('NS.AlertSound("bounty")'); check(ev('played()') == "3", "bounty news: coins")
ex('NS.AlertSound("enemy")'); check(ev('played()') == "", "new enemy: off by default")
ex('NS.db.sounds.enemy = "ping"; NS.AlertSound("enemy"); NS.AlertSound("enemy")')
check(ev('played()') == "13", "new enemy: map ping, once in 5 s")
ex('tick(6, 1); NS.AlertSound("enemy")'); check(ev('played()') == "13", "and again after 5 s")
ex('NS.db.sounds.kos = "quest"; NS.AlertSound("kos")'); check(ev('played()') == "2", "a choice: quest done")
ex('NS.db.sounds.kos = "pvp"; NS.AlertSound("kos")'); check(ev('played()') == "8459", "its name missing on the client: its number is used")
ex('local p = PlaySound; PlaySound = function(id) table.insert(PLAYED, id); return id ~= 12 end; NS.db.sounds.kos = "boss"; NS.AlertSound("kos"); PlaySound = p')
check(ev('played()') == "12,37666", "the game says it won't play it: the next one is tried")
ex('PlaySound = function(id) table.insert(PLAYED, id); return false end; OUTN = 0; local pr = NS.Print; NS.Print = function(m) OUTN = OUTN + 1 end; NS.TrySound("raid"); NS.Print = pr; PlaySound = function(id) table.insert(PLAYED, id) end')
check(ev('OUTN') == 1, "nothing played when you test it: it says so")
ex('played()')
ex('NS.db.stealthSound = false; NS.AlertSound("stealth"); NS.AlertSound("bounty")'); check(ev('played()') == "", "Sounds off: none")
ex('NS.db.stealthSound = true')
# the settings page: a click picks the next sound and plays it, right-click goes back
ex('if not WatchXNearbyOptions then NS.BuildNearbySettings() end; SB = NS.soundBtns; PLAYED = {}; NS.db.sounds.kos = "alarm"')
check(ev('#SB') == 5, "five sound rows")
ex('SB[2]:GetScript("OnClick")(SB[2], "LeftButton")')
check(ev('NS.db.sounds.kos') == "boss" and ev('played()') == "12", "click: the next one (boss whisper), and you hear it")
ex('SB[2]:GetScript("OnClick")(SB[2], "RightButton"); SB[2]:GetScript("OnClick")(SB[2], "RightButton")')
check(ev('NS.db.sounds.kos') == "raid", "right-click: back")
ex('SB[1]:GetScript("OnClick")(SB[1], "RightButton"); SB[1]:GetScript("OnClick")(SB[1], "RightButton")')
check(ev('NS.db.sounds.stealth') == "quest", "it wraps round: raid, off, then the last one")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("sounds:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
