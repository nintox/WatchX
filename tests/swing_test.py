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
SAFEERRS = {}
local oAdd = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(self, m) if tostring(m):find("error %(") then SAFEERRS[#SAFEERRS + 1] = m end return oAdd(self, m) end
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
# Settings > Swing & wand timer: the page shows the bars while it's open (the off hand's too), your look on them
ex('NS.OpenWindow("swing")')
check(ev('WatchXSwingOptions:IsShown()'), "its own settings page")
check(ev('shown(1) and shown(2) and shown(3)'), "page open: the bars to see (swing, off hand, wand)")
ex('NS.db.swingWidth = 300; NS.db.swingHeight = 22; NS.RefreshSwing()')
check(ev('B(1):GetWidth()') == 300 and ev('B(1):GetHeight()') == 22 and ev('WatchXSwing:GetWidth()') == 300, "width and height")
check(ev('B(1).mover:GetWidth()') == 296, "the fill's room follows the width")
ex('NS.db.swingColors = { mh = { 0.1, 0.2, 0.3 } }; NS.RefreshSwing()')
check(abs(ev('NS.SwingColor("mh")[3]') - 0.3) < 0.001, "your own colour")
check(abs(ev('NS.SwingColor("Wand")[1]') - 0.68) < 0.001, "the others keep theirs")
ex('NS.db.swingNames = false; NS.db.swingTime = false; NS.RefreshSwing()')
check(not ev('B(1).name:IsShown()') and not ev('B(1).left:IsShown()'), "names and seconds can go")
check(ev('NS.SwingFrameStyle()') == "gold" and ev('(select(4, B(1).edge:GetPoint(1)))') == -4, "gold frame by default, a little outside the bar")
ex('NS.db.swingFrame = "none"; NS.RefreshSwing()')
check(ev('NS.SwingFrameStyle()') == "none" and ev('B(1).edgeStyle') == "none", "no frame, if you like")
check(abs(ev('select(5, B(2):GetPoint(1))') - (-(22 + 3))) < 0.01, "no frame: the bars closer")
ex('NS.db.swingOffhand = false; NS.RefreshSwing()')
check(not ev('shown(2)'), "off-hand bar off: gone")
ex('NS.db.swingFrame = nil; NS.db.swingOffhand = nil; NS.db.swingWidth = nil; NS.db.swingHeight = nil; NS.db.swingColors = nil; NS.db.swingNames = nil; NS.db.swingTime = nil')
ex('WatchXSwingOptions:Hide(); NS.RefreshSwing()')
check(not ev('WatchXSwing:IsShown()'), "page closed: the bars go")
ex('OH = 1.8; NS.db.swingOffhand = false; fire("PLAYER_ENTER_COMBAT")')
check(ev('shown(1)') and not ev('shown(2)') and ev('B(1).name:GetText()') == "Swing", "two weapons, off-hand bar off: just one bar, named Swing")
ex('fire("PLAYER_LEAVE_COMBAT"); tick(4, 0.1); OH = nil; NS.db.swingOffhand = nil')
# another weapon on mid-fight: its speed at once (the tooltip's "Speed", with your haste – the game hides the number)
ex(r"""
WEAPONS = { [16] = "2.60" }
C_TooltipInfo.GetInventoryItem = function(u, slot) local sp = WEAPONS[slot]; if not sp then return { lines = {} } end
    return { lines = { { leftText = "Some Sword" }, { leftText = "40 - 60 Damage", rightText = "Speed " .. sp } } } end
MH, OH = 2.6, nil
fire("PLAYER_EQUIPMENT_CHANGED", 16, true)   -- (out of a fight: the weapon's own speed noted)
MH = 2.0; NS.SwingBars()   -- 2.0 with haste
fire("PLAYER_ENTER_COMBAT"); tick(0.5, 0.1)
issecretvalue = function(v) return v == "SECRET" end; MH, OH = "SECRET", "SECRET"
WEAPONS = { [16] = "1.80", [17] = "1.40" }
fire("PLAYER_EQUIPMENT_CHANGED", 17, true)
""")
check(ev('shown(2)'), "a second weapon on mid-fight: the off-hand bar at once")
check(abs(ev('B(1).total') - 1.8 * 2.0 / 2.6) < 0.01 and abs(ev('B(2).total') - 1.4 * 2.0 / 2.6) < 0.01,
      "hidden attack speed: the weapons' own speed with your haste")
check(ev('B(1).name:GetText()') == "Main hand", "named Main hand now")
ex('WEAPONS = { [16] = "3.60" }; fire("PLAYER_EQUIPMENT_CHANGED", 17, false)')
check(not ev('shown(2)') and ev('B(1).name:GetText()') == "Swing", "off hand off: its bar goes, Swing again")
check(abs(ev('B(1).total') - 3.6 * 2.0 / 2.6) < 0.01, "a two-hander: its speed")
ex('issecretvalue = nil; MH, OH = 3.1, nil; fire("PLAYER_EQUIPMENT_CHANGED", 16, true)')
check(abs(ev('B(1).total') - 3.1) < 0.01, "the number shown: read from the game")
ex('fire("PLAYER_LEAVE_COMBAT"); tick(5, 0.1); MH = 2.6')
check(not ev('WatchXSwing:IsShown()'), "after the fight: gone")
# the game's own swings (PLAYER_SWING: duration, 0 main hand / 1 off hand / 2 ranged): exact, no guessing after that
ex('issecretvalue = nil; MH, OH = 2.6, nil; fire("PLAYER_ENTER_COMBAT"); tick(0.3, 0.1)')
ex('fire("PLAYER_SWING", 2.43, 0)')
check(abs(ev('left(1)') - 2.43) < 0.01 and abs(ev('B(1).total') - 2.43) < 0.01, "PLAYER_SWING: the game's own time (2.43 s)")
ex('tick(2.6, 0.1)')
check(ev('shown(1)') and ev('B(1).ends') is None, "the game's swings: full until the next one (not guessed)")
ex('fire("PLAYER_SWING", 2.43, 0); fire("PLAYER_SWING", 1.71, 1)')
check(ev('shown(2)') and abs(ev('left(2)') - 1.71) < 0.01 and ev('B(1).name:GetText()') == "Main hand", "the off hand's own swing: its bar, Main hand / Off hand")
ex('fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g9", 78); fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)')
check(abs(ev('left(1)') - 2.43) < 0.01, "no guessing any more (Heroic Strike, parry): the game's time stands")
ex('fire("PLAYER_LEAVE_COMBAT"); tick(4, 0.1)')
check(not ev('shown(1)') and not ev('shown(2)'), "auto-attack off: gone after the last swing")
ex('fire("START_AUTOREPEAT_SPELL"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w9", 5019); fire("PLAYER_SWING", 1.38, 2)')
check(abs(ev('left(3)') - 1.38) < 0.01 and ev('B(3).name:GetText()') == "Wand", "ranged: the game's time, named Wand")
ex('tick(3, 0.1)')
check(ev('shown(3)') and ev('B(3).ends') is None, "shooting: full until the game's next shot")
ex('fire("STOP_AUTOREPEAT_SPELL"); tick(3, 0.1)')
check(not ev('shown(3)'), "wand stopped: gone")
ex('issecretvalue = function(v) return v == "SECRET" end; fire("PLAYER_SWING", "SECRET", 0); issecretvalue = nil')
check(not ev('shown(1)'), "a hidden PLAYER_SWING: ignored, no error")
# the game's own swing bar: hidden while WatchX's is on, put back when it's off
ex(r"""
CV = { showSwingTimer = "1" }
local oG = GetCVar
GetCVar = function(k) if CV[k] ~= nil then return CV[k] end return oG(k) end
SetCVar = function(k, v) CV[k] = tostring(v) end
fire("PLAYER_ENTERING_WORLD", false, true)
""")
check(ev('CV.showSwingTimer') == "0", "the game's swing bar hidden while WatchX's is on")
ex('NS.db.swingTimer = false; NS.db.wandTimer = false; NS.RefreshSwing()')
check(ev('CV.showSwingTimer') == "1", "both WatchX bars off: the game's back")
ex('NS.db.swingTimer = nil; NS.db.wandTimer = nil; NS.db.swingHideBlizz = false; NS.RefreshSwing()')
check(ev('CV.showSwingTimer') == "1", "untick 'hide the game's': both kept")
ex('NS.db.swingHideBlizz = nil; COMBAT = true; NS.RefreshSwing()')
check(ev('CV.showSwingTimer') == "1", "not in a fight")
ex('COMBAT = false; fire("PLAYER_REGEN_ENABLED")')
check(ev('CV.showSwingTimer') == "0", "after the fight: hidden")
serrs = list(ev('SAFEERRS').values())
check(len(serrs) == 0, "no errors caught by WatchX either " + (str(serrs[0])[:300] if serrs else ""))
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("swing timer:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
