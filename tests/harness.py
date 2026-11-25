# The whole addon in a stand-in game: every file in WatchX.toc loaded with WoW-like stubs, then logged in.
# Used by the tests next to it. Needs Python 3 with lupa (pip install lupa).
#   from harness import load;  lua, ex, ev = load()
import os, sys
import lupa.lua51 as L

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")) + "/"

STUBS = r'''
T=1000
function GetTime() return T end
function time() return 1700000000 + math.floor(T) end
function date(f, t) return "01.01 12:00" end
function debugprofilestop() return T*1000 end
FRAMES={} EVENTS={} ONUPDATE={} TIMERS={}
methods={}
function NewFrame(kind, name, parent, tmpl)
  local f={__kind=kind or "Frame", __name=name, __parent=parent, __tmpl=tmpl, __shown=true, __scripts={}, __events={}, __attrs={},
    __w=100, __h=20, __scale=1, __alpha=1, __level=1, __text="", __points={}}
  setmetatable(f, FrameMT)
  if name then _G[name]=f end
  FRAMES[#FRAMES+1]=f
  return f
end
function methods:SetScript(k,fn) self.__scripts[k]=fn; if k=="OnUpdate" then ONUPDATE[self]=fn end end
function methods:GetScript(k) return self.__scripts[k] end
function methods:HookScript(k,fn) local old=self.__scripts[k]; self.__scripts[k]=function(...) if old then old(...) end fn(...) end; if k=="OnUpdate" then ONUPDATE[self]=self.__scripts[k] end end
function methods:RegisterEvent(e) self.__events[e]=true; EVENTS[e]=EVENTS[e] or {}; EVENTS[e][self]=true end
function methods:RegisterUnitEvent(e) self:RegisterEvent(e) end
function methods:UnregisterEvent(e) self.__events[e]=nil; if EVENTS[e] then EVENTS[e][self]=nil end end
function methods:IsEventRegistered(e) return self.__events[e] and true or false end
-- like the game: OnShow/OnHide run when a frame really changes visibility
function methods:Show() local was=self.__shown; self.__shown=true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function methods:Hide() local was=self.__shown; self.__shown=false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.__shown end
function methods:IsVisible() return self.__shown end
function methods:GetWidth() return self.__w end function methods:GetHeight() return self.__h end
function methods:SetWidth(w) self.__w=w end function methods:SetHeight(h) self.__h=h end
function methods:SetSize(w,h) self.__w=w; self.__h=h or w end
function methods:GetSize() return self.__w, self.__h end
function methods:GetScale() return self.__scale end function methods:SetScale(s) self.__scale=s end
function methods:GetEffectiveScale() return self.__scale end
function methods:GetAlpha() return self.__alpha end function methods:SetAlpha(a) self.__alpha=a end
function methods:GetFrameLevel() return self.__level end function methods:SetFrameLevel(l) self.__level=l end
function methods:GetFrameStrata() return "MEDIUM" end
function methods:GetLeft() return 100 end function methods:GetRight() return 200 end
function methods:GetTop() return 500 end function methods:GetBottom() return 480 end
function methods:GetCenter() return 150, 490 end
function methods:GetRect() return 100, 480, 100, 20 end
function methods:GetNumPoints() return #self.__points end
function methods:SetPoint(...) self.__points[#self.__points+1]={...} end
function methods:ClearAllPoints() self.__points={} end
function methods:GetPoint(i) local p=self.__points[i or 1]; if p then return unpack(p) end end
function methods:SetAllPoints() end
function methods:CreateTexture() local t=NewFrame("Texture"); t.__parent=self; return t end
function methods:CreateFontString() local t=NewFrame("FontString"); t.__parent=self; return t end
function methods:CreateAnimationGroup() local g=NewFrame("AnimationGroup"); g.__playing=false; return g end
function methods:CreateAnimation() return NewFrame("Animation") end
function methods:Play() self.__playing=true end function methods:Stop() self.__playing=false end function methods:IsPlaying() return self.__playing end
function methods:SetText(t) self.__text=t end function methods:GetText() return self.__text end
function methods:GetStringWidth() return #(tostring(self.__text or ""))*6 end
function methods:GetStringHeight() return 12 end
function methods:GetLineHeight() return 12 end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function methods:SetAttribute(k,v) self.__attrs[k]=v end function methods:GetAttribute(k) return self.__attrs[k] end
function methods:GetChecked() return self.__checked end function methods:SetChecked(v) self.__checked=v end
function methods:GetParent() return self.__parent end
function methods:GetName() return self.__name end
function methods:GetObjectType() return self.__kind end
function methods:IsMouseOver() return false end
function methods:GetNumber() return tonumber(self.__text) or 0 end
function methods:HasFocus() return false end
function methods:GetCursorPosition() return 0 end
function methods:IsProtected() return false end
function methods:GetChildren() return end
function methods:GetRegions() return end
function methods:GetFontString() if not self.__fs then self.__fs=NewFrame("FontString") end return self.__fs end
function methods:GetNormalTexture() if not self.__nt then self.__nt=NewFrame("Texture") end return self.__nt end
function methods:GetHighlightTexture() return self:GetNormalTexture() end
function methods:GetPushedTexture() return self:GetNormalTexture() end
function methods:GetMinMaxValues() return 0, 100 end
function methods:GetValue() return 0 end
function methods:GetVerticalScroll() return 0 end
function methods:GetVerticalScrollRange() return 0 end
function methods:IsDragging() return false end
FrameMT={__index=function(t,k)
  local m=methods[k]; if m then return m end
  if type(k)=="string" and k:match("^%u") then return function() end end
end}
function CreateVector2D(x,y) return {x=x,y=y, GetXY=function(s) return s.x,s.y end} end
function CreateFromMixins(...) local o={} for i=1,select("#",...) do for k,v in pairs((select(i,...))) do o[k]=v end end return o end
function CreateFrame(kind, name, parent, tmpl) local f=NewFrame(kind, name, parent, tmpl)
  if tmpl and tostring(tmpl):find("ScrollFrame") then f.ScrollBar=NewFrame("Slider") end
  return f end
UIParent=NewFrame("Frame","UIParent"); UIParent.__w=1920; UIParent.__h=1080
WorldFrame=NewFrame("Frame","WorldFrame"); Minimap=NewFrame("Frame","Minimap")
GameTooltip=NewFrame("GameTooltip","GameTooltip"); function GameTooltip_Hide() end
DEFAULT_CHAT_FRAME=NewFrame("Frame","ChatFrame1"); CHATLINES={}
function DEFAULT_CHAT_FRAME:AddMessage(m) CHATLINES[#CHATLINES+1]=m end
ChatFrame1=DEFAULT_CHAT_FRAME; NUM_CHAT_WINDOWS=1
RaidWarningFrame=NewFrame("Frame"); ChatTypeInfo={RAID_WARNING={r=1,g=1,b=1}}
WARNS={}
function RaidNotice_AddMessage(_, m) WARNS[#WARNS+1]=m end
SOUNDKIT={RAID_WARNING=1, IG_QUEST_LIST_COMPLETE=2, LOOT_WINDOW_COIN_SOUND=3}
function PlaySound() end function PlaySoundFile() end
StaticPopupDialogs={} function StaticPopup_Show() end function StaticPopup_Hide() end
UISpecialFrames={} tinsert=table.insert tremove=table.remove wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
strsplit=function(sep, s) local out={} for p in (s..sep):gmatch("(.-)"..sep) do out[#out+1]=p end return unpack(out) end
SlashCmdList={}
hooksecurefunc=function(a,b,c) end
C_Timer={After=function(d,f) TIMERS[#TIMERS+1]={T+d,f} end, NewTicker=function(d,f) local tk={} local function again() if tk.cancel then return end f() TIMERS[#TIMERS+1]={T+d, again} end TIMERS[#TIMERS+1]={T+d, again} tk.Cancel=function() tk.cancel=true end return tk end, NewTimer=function(d,f) local tk={} TIMERS[#TIMERS+1]={T+d,function() if not tk.cancel then f() end end} tk.Cancel=function() tk.cancel=true end return tk end}
COMBAT=false; INFIGHT=false
function InCombatLockdown() return COMBAT or false end
function UnitAffectingCombat() return INFIGHT or COMBAT or false end
function IsResting() return false end
function UnitName(u) if u=="player" then return "Rikerud", nil end return nil end
function UnitGUID() return "Player-1-0001" end
function UnitLevel() return 31 end function UnitXP() return 24000 end function UnitXPMax() return 47000 end
function GetXPExhaustion() return 13000 end function GetMaxPlayerLevel() return 60 end
function UnitClass() return "Mage","MAGE" end function UnitRace() return "Human" end function UnitFactionGroup() return "Alliance" end
function UnitExists() return false end function UnitIsPlayer() return false end function UnitIsUnit() return false end
function UnitIsDeadOrGhost() return false end
function UnitHealth() return 3000 end function UnitHealthMax() return 3000 end function UnitPower() return 1000 end function UnitPowerMax() return 5000 end
function UnitIsAFK() return false end function UnitCanAttack() return false end function UnitIsEnemy() return false end
function UnitReaction() return 4 end function UnitIsFriend() return true end function UnitInParty() return false end function UnitInRaid() return false end
function GetNumGroupMembers() return 0 end function IsInGroup() return false end function IsInRaid() return false end function IsInGuild() return true end
function GetGuildInfo() return nil end function GetRealmName() return "Forever" end
function GetZoneText() return "Hillsbrad Foothills" end function GetSubZoneText() return "Southshore" end function GetRealZoneText() return "Hillsbrad Foothills" end
function IsInInstance() return false, "none" end
function GetCVar(k) local v={nameplateShowEnemies="1", screenshotFormat="jpeg", screenshotQuality="8", scriptProfile="0"} return v[k] end
function SetCVar() end function GetCVarBool() return false end
function GetNetStats() return 0,0,32,32 end function GetFramerate() return 120 end
function GetCursorPosition() return 0,0 end
function GetBuildInfo() return "1.60.1", "1", "Nov 2026", 16001 end function GetVersion() return "2" end
function IsLoggedIn() return true end function GetLocale() return "enUS" end
function Screenshot() end function LoggingChat() return false end
function GetSpellInfo(id) return "Spell"..tostring(id) end
C_Spell={GetSpellInfo=function(id) return {name="Spell"..tostring(id), iconID=1} end, GetSpellName=function(id) return "Spell"..tostring(id) end, GetSpellTexture=function() return 1 end, GetSpellDescription=function() return "" end}
C_Item={GetItemInfoInstant=function(id) return id, nil, nil, nil, 1, 0 end, GetItemCount=function() return 0 end, GetItemIconByID=function() return 1 end, GetItemNameByID=function(id) return "Item"..id end, GetItemSpell=function() return nil end}
function GetItemInfo(id) return "Item"..tostring(id) end function GetItemIcon() return 1 end function GetItemCount() return 0 end function GetItemSpell() return nil end
C_Container={GetContainerNumSlots=function(b) return b==0 and 16 or 0 end, GetContainerItemInfo=function() return nil end, GetItemCooldown=function() return 0,0,1 end, GetContainerItemCooldown=function() return 0,0,1 end}
C_TooltipInfo={GetHyperlink=function() return {lines={}} end, GetBagItem=function() return {lines={}} end, GetUnitAura=function() return {lines={}} end, GetItemByID=function() return {lines={}} end}
-- your buffs: AURAS (HELPFUL) / HARM, as aura data tables
AURAS={} HARM={}
C_UnitAuras={GetAuraDataByIndex=function(u, i, f) if u~="player" then return nil end if f=="HARMFUL" then return HARM[i] end return AURAS[i] end, GetPlayerAuraBySpellID=function() return nil end}
C_Map={GetBestMapForUnit=function() return 1424 end, GetPlayerMapPosition=function() return {x=0.5,y=0.5, GetXY=function(self) return 0.5,0.5 end} end, GetAreaInfo=function(id) return "Zone"..id end, GetMapInfo=function() return {name="Map"} end}
C_NamePlate={GetNamePlates=function() return {} end, GetNamePlateForUnit=function() return nil end}
C_ChatInfo={SendAddonMessage=function() end, RegisterAddonMessagePrefix=function() return true end}
C_FriendList={GetNumFriends=function() return 0 end, GetFriendInfoByIndex=function() return nil end}
C_QuestLog={GetNumQuestLogEntries=function() return 0 end, GetInfo=function() return nil end, IsComplete=function() return false end}
function GetQuestLogRewardXP() return 0 end
C_AddOns={GetAddOnMemoryUsage=function() return 2000 end, UpdateAddOnMemoryUsage=function() end, GetAddOnMetadata=function() return "test" end, IsAddOnLoaded=function() return true end}
function GetAddOnMetadata() return "test" end
C_TradeSkillUI=nil
Settings={RegisterCanvasLayoutCategory=function(p,n) return {GetID=function() return n end} end, RegisterAddOnCategory=function() end, RegisterCanvasLayoutSubcategory=function(c,p,n) return {GetID=function() return n end} end, OpenToCategory=function() end}
BackdropTemplateMixin={SetBackdrop=function(self, i) self.__bd=i end, SetBackdropColor=function() end, SetBackdropBorderColor=function() end, OnBackdropSizeChanged=function() end}
function Mixin(o, m) for k,v in pairs(m) do o[k]=v end return o end
RAID_CLASS_COLORS=setmetatable({}, {__index=function() return {r=1,g=1,b=1, colorStr="ffffffff"} end})
CLASS_ICON_TCOORDS=setmetatable({}, {__index=function() return {0,1,0,1} end})
LOCALIZED_CLASS_NAMES_MALE=setmetatable({}, {__index=function(t,k) return k end})
UNKNOWNOBJECT="Unknown" RETRIEVING_ITEM_INFO="Retrieving item information" OKAY="Okay" CANCEL="Cancel" YES="Yes" NO="No"
SECRET=setmetatable({}, {__mode="k"})
function issecretvalue(v) return v ~= nil and SECRET[v] == true end
function GetNumSkillLines() return 0 end function GetProfessions() return end
function ReloadUI() end function RequestTimePlayed() end
function GetSendMailMoney() return 0 end SendMail=function() end
function GetMoney() return 0 end GetCoinTextureString=function(c) return tostring(c).."c" end
function SecondsToTime(s) return tostring(s).."s" end
LibStub=nil
strmatch=string.match strfind=string.find strsub=string.sub strlower=string.lower strupper=string.upper format=string.format gsub=string.gsub strlen=string.len strrep=string.rep strbyte=string.byte strchar=string.char
strtrim=function(s) return (s or ""):match("^%s*(.-)%s*$") end
geterrorhandler=function() return function(e) print("ERRHANDLER", e) end end
securecall=function(f, ...) return pcall(f, ...) end
function CopyTable(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and CopyTable(v) or v end return o end
floor=math.floor ceil=math.ceil abs=math.abs max=math.max min=math.min sqrt=math.sqrt
WorldMapFrame=NewFrame("Frame","WorldMapFrame") MinimapCluster=NewFrame("Frame","MinimapCluster")
function GetMinimapShape() return "ROUND" end
C_Minimap=nil
function GetPlayerFacing() return 0 end
function UnitPosition() return 0,0,0,1 end
function GetUnitSpeed() return 0 end
'''

RUNTIME = r'''
function fire(ev, ...)
  for f in pairs(EVENTS[ev] or {}) do
    local fn = f.__scripts.OnEvent
    if fn then local args={...} local ok, err = xpcall(function() return fn(f, ev, unpack(args)) end, debug.traceback) if not ok then ERRS[#ERRS+1] = ev .. ": " .. tostring(err) end end
  end
end
function tick(sec, step)
  step = step or 0.1
  local t = 0
  while t < sec - 1e-9 do
    T = T + step; t = t + step
    for f, fn in pairs(ONUPDATE) do
      if f.__shown and f.__scripts.OnUpdate then local ok, err = pcall(f.__scripts.OnUpdate, f, step) if not ok then ERRS[#ERRS+1] = "OnUpdate: " .. tostring(err) end end
    end
    local due = {}
    for i = #TIMERS, 1, -1 do if TIMERS[i][1] <= T then due[#due+1] = TIMERS[i][2]; table.remove(TIMERS, i) end end
    for _, fn in ipairs(due) do local ok, err = pcall(fn) if not ok then ERRS[#ERRS+1] = "timer: " .. tostring(err) end end
  end
end
ERRS = {}
'''


def load(extra_stubs="", quiet=True):
    """Loads every file of WatchX.toc (libraries that need more of the game may fail – that's reported, not fatal),
    logs in and runs 40 seconds. Returns (lua, ex, ev)."""
    lua = L.LuaRuntime()
    ex, ev = lua.execute, lua.eval
    ex(STUBS)
    if extra_stubs:
        ex(extra_stubs)
    toc = open(ROOT + "WatchX.toc", encoding="utf-8").read().splitlines()
    files = [l.strip() for l in toc if l.strip() and not l.startswith("#")]
    ex("NS={}")
    run = lua.eval('function(s, n) local f, e = loadstring(s, n) if not f then return e end '
                   'local ok, err = pcall(f, "WatchX", NS) if not ok then return err end return "ok" end')
    for f in files:
        r = run(open(ROOT + f.replace("\\", "/"), encoding="utf-8").read(), f)
        if not quiet:
            print(f, r)
        if r != "ok" and not f.startswith("Libs"):
            raise SystemExit("could not load %s: %s" % (f, r))
    ex("ns=NS")
    ex(RUNTIME)
    # like the game: when a test puts new auras on you (AURAS = {...} / HARM = {...}), UNIT_AURA fires
    ex('''
    local store = { AURAS = AURAS, HARM = HARM }
    rawset(_G, "AURAS", nil); rawset(_G, "HARM", nil)
    setmetatable(_G, { __index = function(_, k) return store[k] end,
      __newindex = function(t, k, v)
        if k == "AURAS" or k == "HARM" then store[k] = v; if fire then fire("UNIT_AURA", "player") end
        else rawset(t, k, v) end
      end })
    ''')
    ex('fire("ADDON_LOADED", "WatchX"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)')
    ex("tick(40, 0.05)")
    return lua, ex, ev


def errors(ev):
    return list(ev("ERRS").values())
