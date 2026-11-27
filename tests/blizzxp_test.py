# The game's own XP bar: quests ready to hand in (gold) and in progress (faint) painted on it, and WatchX's lines
# under its tooltip – also with WatchX's own XP bar switched off. Off in the settings: gone.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
function UnitXP() return 40000 end function UnitXPMax() return 100000 end
function UnitLevel() return 30 end
QUESTS = { { id = 1, xp = 10000, done = true }, { id = 2, xp = 5000, done = false }, { id = 3, xp = 15000, done = true } }
C_QuestLog.GetNumQuestLogEntries = function() return #QUESTS end
C_QuestLog.GetInfo = function(i) local q = QUESTS[i] if q then return { questID = q.id } end end
C_QuestLog.IsComplete = function(id) for _, q in ipairs(QUESTS) do if q.id == id then return q.done end end end
function GetQuestLogRewardXP(id) for _, q in ipairs(QUESTS) do if q.id == id then return q.xp end end return 0 end
-- the game's XP bar: a container with bars, the XP one with its StatusBar (500 wide)
EXP = CreateFrame("Frame", nil, UIParent); EXP.ExhaustionTick = CreateFrame("Frame", nil, EXP)
EXP.StatusBar = CreateFrame("StatusBar", nil, EXP); EXP.StatusBar.GetWidth = function() return 500 end
EXP.StatusBar.IsVisible = function() return true end
REP = CreateFrame("Frame", nil, UIParent); REP.StatusBar = CreateFrame("StatusBar", nil, REP)
StatusTrackingBarManager = { barContainers = { { bars = { [1] = REP, [4] = EXP } } } }
-- the tooltip, written down
TIP = {}; local owner, shown
GameTooltip.SetOwner = function(self, o) owner = o; TIP = {}; shown = true end
GameTooltip.GetOwner = function() return owner end
GameTooltip.IsShown = function() return shown end
GameTooltip.Show = function() shown = true end
GameTooltip.AddLine = function(self, t) TIP[#TIP + 1] = tostring(t) end
GameTooltip.AddDoubleLine = function(self, a, b) TIP[#TIP + 1] = tostring(a) .. " = " .. tostring(b) end
NS.db.xpBar = false   -- (WatchX's own XP bar off: the game's still gets it)
fire("QUEST_LOG_UPDATE"); tick(1.5, 0.5)
''')
seg = lambda name: ev('(function() local t = NS.BlizzXPBarSegs and NS.BlizzXPBarSegs().%s if t and t:IsShown() then local _, _, _, x = t:GetPoint(1) return x .. ":" .. t:GetWidth() end return "hidden" end)()' % name)
ex('NS.BlizzXPBarSegs = NS.BlizzXPBarSegs')
print("    done:", seg("done"), " todo:", seg("todo"))
check(seg("done") == "200:125.0" or seg("done") == "200:125", "ready to hand in (25k): from 40% (200 px), 125 px wide, in gold")
check(seg("todo") == "325:25.0" or seg("todo") == "325:25", "in progress (5k): after it, 25 px")
ex('GetXPExhaustion = function() return 8000 end; NS.RefreshXPBar()')
print("    rest:", seg("rest"))
check(seg("rest") == "200:40.0" or seg("rest") == "200:40", "rested (8k): from your XP, 40 px – drawn over the quests")
# the game's tooltip, then WatchX's lines under it
ex('GameTooltip:SetOwner(EXP, "ANCHOR_TOP"); GameTooltip:AddLine("Experience 40000 / 100000"); EXP:GetScript("OnEnter")(EXP)')
tip = " | ".join(ev('table.concat(TIP, "\\n")').split("\n"))
print("    tooltip:", tip[:300])
check("Experience 40000" in tip and "WatchX" in tip, "the game's tooltip kept, WatchX's lines under it")
check("Ready to hand in" in tip and "+25.0k" in tip, "ready to hand in: +25k")
check("Level 30" not in tip, "not its level / XP lines twice")
ex('NS.db.blizzXPBar = false; NS.RefreshXPBar()')
check(seg("done") == "hidden" and seg("todo") == "hidden" and seg("rest") == "hidden", "switched off: gone from the game's bar")
# finished quests past this level: how far into the next one
check(ev('NS.XPWithDone({ level = 38, cur = 73800, max = 80800 }, 12700)') == "= level 39 · 6.7%", "past the level: level 39 · 6.7% (5.7k of 85.7k): " + str(ev('NS.XPWithDone({ level = 38, cur = 73800, max = 80800 }, 12700)')))
check(ev('NS.XPWithDone({ level = 38, cur = 70000, max = 80800 }, 5000)') == "= 92.8%", "not past it: the %")
check(ev('NS.XPWithDone({ level = 20, cur = 20000, max = 23200 }, 30000)') == "= level 22 · 5.9%", "two levels on: level 22 · 5.9%")
check(ev('NS.XPWithDone({ level = 31, cur = 40000, max = 47000 }, 10000)') == "= level 32 · 6.4%", "a level that isn't classic's: the next as big as this")
check(ev('NS.XPWithDone({ level = 59, cur = 200000, max = 209800 }, 20000)') == "= level 60", "to the top level: just the level")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("game's XP bar:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
