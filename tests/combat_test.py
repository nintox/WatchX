# Combat lockdown, like the game: a frame from a Secure template, one holding a protected child, and one a
# protected frame hangs on are protected. Changing one in a fight (show/hide, points, size, scale, mouse, strata,
# attributes, moving) is recorded as BLOCKED – the game would refuse it.
import sys
from harness import load, errors

lua, ex, ev = load()
ex(r'''
BLOCKED = {}
local function IsProt(f, seen)
  if type(f) ~= "table" then return false end
  if f.__secure or f.__secureKids then return true end
  seen = seen or {}
  if seen[f] then return false end
  seen[f] = true
  for d in pairs(f.__deps or {}) do if IsProt(d, seen) then return true end end
  return false
end
PROT = IsProt
local function where() return debug.traceback("", 3):sub(1, 400) end
local oldCreate = CreateFrame
function CreateFrame(kind, name, parent, tmpl)
  local f = oldCreate(kind, name, parent, tmpl)
  if tmpl and tostring(tmpl):find("Secure") then
    f.__secure = true
    if COMBAT then BLOCKED[#BLOCKED+1] = "CreateFrame secure " .. tostring(name) end
    local p = parent while type(p) == "table" do p.__secureKids = true; p = p.__parent end
  end
  return f
end
for _, m in ipairs({ "Show", "Hide", "SetShown", "SetWidth", "SetHeight", "SetSize", "SetScale", "SetAttribute",
    "EnableMouse", "EnableMouseWheel", "SetFrameStrata", "SetFrameLevel", "StartMoving", "StopMovingOrSizing",
    "SetAllPoints", "SetParent", "RegisterForClicks" }) do
  local old = methods[m]
  methods[m] = function(self, ...)
    if COMBAT and IsProt(self) then BLOCKED[#BLOCKED+1] = m .. " on " .. tostring(self.__name or self.__kind) .. where() end
    if old then return old(self, ...) end
  end
end
local oldSet, oldClear = methods.SetPoint, methods.ClearAllPoints
methods.SetPoint = function(self, point, rel, ...)
  if COMBAT and IsProt(self) then BLOCKED[#BLOCKED+1] = "SetPoint on " .. tostring(self.__name or self.__kind) .. where() end
  if type(rel) == "table" and rel.__points then
    rel.__deps = rel.__deps or {}; rel.__deps[self] = true
    self.__anchors = self.__anchors or {}; self.__anchors[rel] = true
  end
  return oldSet(self, point, rel, ...)
end
methods.ClearAllPoints = function(self)
  if COMBAT and IsProt(self) then BLOCKED[#BLOCKED+1] = "ClearAllPoints on " .. tostring(self.__name or self.__kind) .. where() end
  for rel in pairs(self.__anchors or {}) do if rel.__deps then rel.__deps[self] = nil end end
  self.__anchors = {}
  return oldClear(self)
end
-- frames made before these rules: mark them now
for _, f in ipairs(FRAMES) do
  if f.__tmpl and tostring(f.__tmpl):find("Secure") then
    f.__secure = true
    local p = f.__parent while type(p) == "table" do p.__secureKids = true; p = p.__parent end
  end
  for _, pt in ipairs(f.__points or {}) do
    local rel = pt[2]
    if type(rel) == "table" and rel.__points then rel.__deps = rel.__deps or {}; rel.__deps[f] = true; f.__anchors = f.__anchors or {}; f.__anchors[rel] = true end
  end
end
function startFight() fire("PLAYER_REGEN_DISABLED"); COMBAT = true; INFIGHT = true end
function endFight() COMBAT = false; INFIGHT = false; fire("PLAYER_REGEN_ENABLED") end
''')
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)
def blocked():
    b = list(ev('BLOCKED').values())
    return (" – " + b[0][:300]) if b else ""

# Nearby off (the default): the mini bar isn't protected, a fight blocks nothing
ex('NS.db.nearby = false; NS.RefreshUI(); tick(1)')
check(not ev('WatchXMini.holdsSecure') and not ev('PROT(WatchXMini)'), "Nearby off: the mini bar isn't protected")
ex('BLOCKED = {}; startFight(); NS.RefreshUI(); tick(5); endFight(); tick(2)')
check(blocked() == "", "Nearby off: a fight with refreshes blocks nothing" + blocked())

# Nearby on, enemies coming in a fight
ex('NS.db.nearby = true; NS.db.nearbyShowEmpty = true; NS.RefreshUI(); tick(1)')
check(ev('WatchXNearby ~= nil and WatchXNearby.attached == true') and ev('PROT(WatchXMini)'), "Nearby on: the list hangs under the mini bar")
ex('BLOCKED = {}; startFight(); for i = 1, 4 do pcall(SlashCmdList.WATCHX, "nearby test"); NS.RefreshUI(); tick(1) end; endFight(); tick(2)')
check(blocked() == "", "Nearby on: new enemies in a fight block nothing" + blocked())

# unlocked when a fight starts: locked just before it; the wheel and drags do nothing in it
ex('CHATLINES = {}; SlashCmdList.WATCHX("unlock"); tick(1); BLOCKED = {}; startFight(); tick(1)')
check(any("a fight started" in str(l) for l in ev('CHATLINES').values()), "unlocked: locked at the start of a fight")
ex('local m = WatchXMini; if m.__scripts.OnMouseWheel then m.__scripts.OnMouseWheel(m, 1) end; m.__scripts.OnDragStart(m); m.__scripts.OnDragStop(m); tick(1)')
check(blocked() == "", "in the fight: wheel and drag on the mini bar do nothing" + blocked())
ex('endFight(); tick(2)')

# a stray drag while locked doesn't move or save it
ex('NS.db.miniPoint = { "TOP", "TOP", 11, -22 }; local m = WatchXMini; m.__scripts.OnDragStart(m); m.__scripts.OnDragStop(m)')
check(ev('NS.db.miniPoint[3]') == 11 and ev('NS.db.miniPoint[4]') == -22, "locked: a stray drag saves nothing")

# the warning card: its click stays true to what's shown
ex('BLOCKED = {}; NS.db.warnDock = false; NS.ShowStealthToast({ name = "Rogue A", key = "Rogue A", class = "ROGUE", level = 30 }, "stealth"); tick(0.5)')
check(ev('WatchXCardButton ~= nil and WatchXCardButton:IsShown()') and "Rogue A" in str(ev('WatchXCardButton:GetAttribute("macrotext1")')), "card: armed for Rogue A")
ex('startFight(); tick(10)')
check(ev('WatchXStealthToast:IsShown()') == True, "card: stays up in the fight while its click is there")
check(ev('NS.ShowStealthToast({ name = "Mage B", key = "Mage B", class = "MAGE", level = 30 }, "kos")') == False, "card: a new one in the fight waits")
ex('tick(3)')
check(blocked() == "", "card: nothing blocked in the fight" + blocked())
ex('endFight(); tick(0.5)')
check("Mage B" in str(ev('WatchXStealthToast.name:GetText()')) and ev('WatchXCardButton.player.name') == "Mage B", "card: after the fight Mage B shows, its click targets Mage B")
ex('tick(12)')
check(not ev('WatchXStealthToast:IsShown()') and not ev('WatchXCardButton:IsShown()'), "card: gone after its time, click too")

# the XP icons after a reload in a fight; a long fight with everything on
ex('OLDLV = NS.levelFrame; NS.levelPending = true; fire("PLAYER_REGEN_ENABLED"); tick(1)')
check(ev('NS.levelFrame ~= OLDLV and NS.levelPending == nil'), "XP icons: made when the fight is over")
ex('BLOCKED = {}; NS.db.xpBarAttach = true; NS.RefreshUI(); tick(1); startFight(); for i = 1, 5 do pcall(SlashCmdList.WATCHX, "nearby test"); NS.RefreshUI(); tick(1) end; tick(10); endFight(); tick(2)')
check(blocked() == "", "everything on: a long fight blocks nothing" + blocked())
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("combat:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
