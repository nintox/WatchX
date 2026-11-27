# Swing timer & wand timer: a melee bar that starts with your auto-attack and runs at your attack speed (haste,
# Heroic Strike, a finished cast, a parry), and a wand / Auto Shot bar started by each shot. Off: nothing.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
MH, OH, RS = 2.6, nil, 1.5
UnitAttackSpeed = function(u) return MH, OH end
UnitRangedDamage = function(u) return RS, 10, 20 end
NAMES = { [5019] = "Shoot", [78] = "Heroic Strike", [116] = "Frostbolt", [133] = "Fireball" }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return NAMES[id] end
function B(i) return NS.SwingBars and NS.SwingBars() and NS.SwingBars()[i] end
function shown(i) local b = B(i) return b and b:IsShown() and WatchXSwing:IsShown() or false end
function left(i) local b = B(i) return b and b.ends and (b.ends - T) or -1 end
''')
check(not ev('WatchXSwing and WatchXSwing:IsShown()'), "nothing before you attack")
ex('fire("PLAYER_ENTER_COMBAT")')
check(ev('shown(1)'), "auto-attack: the swing bar")
check(abs(ev('left(1)') - 2.6) < 0.01, "a full swing to go (2.6 s)")
check(ev('B(1).name:GetText()') == "Swing", "named Swing (one weapon)")
check(not ev('shown(2)'), "no off-hand bar with one weapon")
ex('tick(1.0, 0.1)')
check(ev('B(1).left:GetText()') == "1.6", "the seconds left written (1.6)")
ex('tick(1.7, 0.1)')
check(abs(ev('left(1)') - 2.5) < 0.15, "still attacking: the next swing starts by itself")
# haste: 2.6 -> 2.0 mid-swing, the rest shrinks to match
ex('local l = left(1); MH = 2.0; fire("UNIT_ATTACK_SPEED", "player"); L0 = l')
check(abs(ev('left(1)') - ev('L0') * 2.0 / 2.6) < 0.02 and abs(ev('B(1).total') - 2.0) < 0.001, "haste: the rest at the new speed")
# Heroic Strike lands with a swing: start over
ex('tick(0.5, 0.1); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g1", 78)')
check(abs(ev('left(1)') - 2.0) < 0.01, "Heroic Strike: a fresh swing")
# a parry early in the swing: 40 % sooner
ex('fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)')
check(abs(ev('left(1)') - 1.2) < 0.01, "parry: 40 % of the swing sooner")
# a finished cast (with a cast time) starts it over; an instant one doesn't
ex('tick(0.3, 0.1); fire("UNIT_SPELLCAST_START", "player", "g2", 116); tick(0.2, 0.1); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g2", 116)')
check(abs(ev('left(1)') - 2.0) < 0.01, "a finished cast: the swing starts over")
ex('tick(0.4, 0.1); L1 = left(1); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g3", 133)')
check(abs(ev('left(1)') - ev('L1')) < 0.01, "an instant spell: no change")
# stop attacking: the bar fills once more, then goes
ex('fire("PLAYER_LEAVE_COMBAT"); tick(3.5, 0.1)')
check(not ev('shown(1)'), "auto-attack off: gone after the last swing")
check(ev('NS.SwingBars()[1].left:GetText()') == "", "no number left behind")
# dual-wield: two bars
ex('OH = 1.8; fire("PLAYER_ENTER_COMBAT")')
check(ev('shown(1) and shown(2)'), "two weapons: main hand and off hand")
check(ev('B(1).name:GetText()') == "Main hand" and ev('B(2).name:GetText()') == "Off hand", "named Main hand / Off hand")
check(abs(ev('left(2)') - 1.8) < 0.01, "the off hand at its own speed")
ex('fire("PLAYER_LEAVE_COMBAT"); tick(4, 0.1); OH = nil')
check(not ev('WatchXSwing:IsShown()'), "all gone after the fight")
# wand: each Shoot starts the bar at the ranged speed
ex('fire("START_AUTOREPEAT_SPELL"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w1", 5019)')
check(ev('shown(3)') and not ev('shown(1)'), "a wand shot: the wand bar (alone, at the top)")
check(ev('select(5, B(3):GetPoint(1))') == 0, "the wand bar at the top when it's the only one")
check(abs(ev('left(3)') - 1.5) < 0.01 and ev('B(3).name:GetText()') == "Wand", "1.5 s to the next shot, named Wand")
ex('tick(1.6, 0.1)')
check(ev('shown(3)') and ev('left(3)') > 1.0, "wanding: the next shot runs by itself")
ex('fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w2", 5019)')
check(abs(ev('left(3)') - 1.5) < 0.01, "the next shot: again")
ex('fire("STOP_AUTOREPEAT_SPELL"); tick(3, 0.1)')
check(not ev('shown(3)'), "wand stopped: gone")
# in a fight the game hides the spell: the shots still keep it in step, and a hidden speed uses the one from before
ex('fire("START_AUTOREPEAT_SPELL"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w4", 5019); tick(1.0, 0.1)')
ex('issecretvalue = function(v) return v == "SECRET" end; RS = "SECRET"; MH = "SECRET"')
ex('tick(0.2, 0.1); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "SECRET", "SECRET")')
check(abs(ev('left(3)') - 1.5) < 0.01, "hidden spell in a fight: the shot still seen, the speed from before")
ex('tick(0.3, 0.1); L2 = left(3); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "SECRET", "SECRET")')
check(abs(ev('left(3)') - ev('L2')) < 0.01, "a hidden cast right after a shot: not a shot")
ex('tick(6, 0.1)')
check(ev('shown(3)') and ev('left(3)') > 0, "still shooting: keeps going with no events")
ex('fire("PLAYER_ENTER_COMBAT"); tick(0.1)')
check(ev('shown(1)') and abs(ev('left(1)') - 2.0) < 0.15, "melee with a hidden speed: the speed from before")
ex('tick(5, 0.1)')
check(ev('shown(1)') and ev('left(1)') > 0, "melee keeps swinging with a hidden speed")
ex('fire("PLAYER_LEAVE_COMBAT"); fire("STOP_AUTOREPEAT_SPELL"); tick(4, 0.1); issecretvalue = nil; RS = 1.5; MH = 2.6')
check(not ev('WatchXSwing:IsShown()'), "stopped: gone")
ex('CHATLINES = {}; SlashCmdList.WATCHX("swing why")')
check(any("SUCCEEDED" in str(l) for l in ev('CHATLINES').values()) and any("hidden" in str(l) for l in ev('CHATLINES').values()), "/wx swing why: what the game said, hidden ones too")
# switched off
ex('NS.db.swingTimer = false; NS.db.wandTimer = false; fire("PLAYER_ENTER_COMBAT"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w3", 5019)')
check(not ev('WatchXSwing:IsShown()'), "switched off: nothing")
ex('fire("PLAYER_LEAVE_COMBAT"); NS.db.swingTimer = nil; NS.db.wandTimer = nil')
# secret values in a fight: ignored, no error
ex('issecretvalue = function(v) return v == "SECRET" end; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "SECRET", "SECRET"); issecretvalue = nil')
# unlocked: examples to place it by, gone when locked
ex('NS.StartMove(true)')
check(ev('shown(1) and shown(3) and not shown(2)'), "unlocked: a swing and a wand bar to place it by")
check(ev('WatchXSwingLabel and WatchXSwingLabel:IsShown()'), "unlocked: its label")
ex('NS.StopMove()')
check(not ev('WatchXSwing:IsShown()'), "locked: the examples go")
# /wx swing: a test
ex('SlashCmdList.WATCHX("swing"); tick(0.2, 0.1)')
check(ev('shown(1) and shown(2) and shown(3)'), "/wx swing: main hand, off hand and wand")
ex('tick(5, 0.1)')
check(ev('shown(3) and left(3) > 0'), "the test keeps shooting")
ex('tick(20, 0.2)')
check(not ev('WatchXSwing:IsShown()'), "the test over: gone")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("swing timer:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
