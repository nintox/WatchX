-- WatchX – Made by Rikerud
-- UI: panel (/wx), mini bar, settings page (Esc > Options > AddOns > WatchX), guide, minimap button,
-- the secure chat log bar and the "held back" send bar.
-- Look: Blizzard's own. Windows (panel, History, guide) get the dark stone frame with a gold trim and a
-- header plate; the small bars (mini bar, Nearby, XP, alerts, menus) the tooltip edge. Red Blizzard buttons,
-- gold headings.

local _, ns = ...

local PAD = 12
local PANEL_W = 250
local MINI_H, TARGET_H = 26, 42   -- the mini bar, and the bar it grows into when something is up
local BG = { 0.05, 0.045, 0.04, 0.92 }     -- warm near-black
local EDGE = { 0.80, 0.64, 0.30, 1 }       -- WoW Forever's gold (the unit frame rings)
local ACCENT = { 1, 0.82, 0 }              -- Blizzard gold
local LOGO = "Interface\\AddOns\\WatchX\\Media\\logo"   -- Media/logo.tga (made by Media/make_logo.py)

local panel, mini, settingsPage, settingsCategory, helpFrame, prompt, sendBar
local promptPending = false
local db = function() return ns.db end

-- ---------------------------------------------------------------- style helpers

-- The tooltip look for the small bars and menus: blue-black, a rounded silver edge. (Plain textures if the
-- client has no backdrops.) Built once, out of combat; the backdrop only redraws textures, so it's fine on frames
-- that turn protected later.
local function Backdrop(f, info)
    if not BackdropTemplateMixin then return false end
    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
        f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
    end
    f:SetBackdrop(info)
    return true
end
local TOOLTIP_LOOK = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local function Flat(f, alpha)
    if Backdrop(f, TOOLTIP_LOOK) then
        f:SetBackdropColor(BG[1], BG[2], BG[3], alpha or BG[4])
        f:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
        return
    end
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(BG[1], BG[2], BG[3], alpha or BG[4])
    f.bg = bg
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = f:CreateTexture(nil, "BORDER")
        line:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
        line:SetPoint(side[1], f, side[1], 0, 0)
        line:SetPoint(side[2], f, side[2], 0, 0)
        if side[3] then line:SetHeight(1) else line:SetWidth(1) end
    end
end

-- The window look: dark stone with Blizzard's gold trim, and the title on a header plate over the top edge.
local WINDOW_LOOK = { bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", tile = true, tileSize = 256, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 } }
local function Window(f, title, plateW)
    if Backdrop(f, WINDOW_LOOK) then
        f:SetBackdropColor(0.16, 0.15, 0.14, 0.98)
    else
        Flat(f, 0.97)
    end
    if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 12, 0) end   -- the plate may stick out at the top
    local plate = f:CreateTexture(nil, "ARTWORK")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(plateW or 220, 64)
    plate:SetPoint("TOP", f, "TOP", 0, 12)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", plate, "TOP", 0, -14)
    text:SetText(title or "")
    f.plate, f.plateText = plate, text
    return text
end

-- A red tooltip edge on a child frame (the alert bar is a secure button: nothing is added to the button itself).
local function RedEdge(f)
    local e = CreateFrame("Frame", nil, f)
    e:SetAllPoints()
    e:EnableMouse(false)
    if Backdrop(e, { edgeFile = TOOLTIP_LOOK.edgeFile, edgeSize = 12 }) then
        e:SetBackdropBorderColor(1, 0.35, 0.35, 1)
    end
    return e
end

-- A line of text bound on both sides, so nothing runs out of its field.
local function Text(parent, font, y, rightInset, leftInset, lines)
    lines = lines or 1
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", leftInset or PAD, y)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(rightInset or PAD), y)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(lines > 1)
    if fs.SetMaxLines then fs:SetMaxLines(lines) end
    local h = math.ceil((fs:GetLineHeight() or 12) * lines)
    fs:SetHeight(h)
    return fs, y - h
end

-- A button's label stays inside the button: one wider than the button drops to the small font.
local function SetButtonText(button, text)
    button:SetNormalFontObject("GameFontNormal")
    button:SetHighlightFontObject("GameFontHighlight")
    button:SetDisabledFontObject("GameFontDisable")
    button:SetText(text)
    local fs = button:GetFontString()
    if fs and (fs:GetStringWidth() or 0) > button:GetWidth() - 14 then
        button:SetNormalFontObject("GameFontNormalSmall")
        button:SetHighlightFontObject("GameFontHighlightSmall")
        button:SetDisabledFontObject("GameFontDisableSmall")
    end
end

local function Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 24)
    SetButtonText(b, text)
    b:SetScript("OnClick", onClick)
    return b
end

-- The small buttons: Blizzard's red ones (the name stays for the old call sites).
local function FlatButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    SetButtonText(b, text)
    b:SetScript("OnClick", onClick)
    return b
end

-- A line in a drop-down menu: plain text that lights up under the mouse, like Blizzard's menus.
local function MenuRow(parent, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 18)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetText(" ")
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "LEFT", 6, 0)
        fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    b:SetScript("OnClick", onClick)
    return b
end

-- Is the mouse over this frame? (Forever has no MouseIsOver(); the frame method is always there.)
local function Hovered(f)
    if not (f and f.IsMouseOver and f:IsShown()) then return false end
    local ok, over = pcall(f.IsMouseOver, f)
    return ok and over and true or false
end

local function Tip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function SavePoint(frame, key)
    local p, _, rp, x, y = frame:GetPoint()
    db()[key] = { p, rp, x, y }
end

local function LoadPoint(frame, key, default)
    local pt = db()[key] or default
    frame:ClearAllPoints()
    frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
end

-- ---------------------------------------------------------------- popups

StaticPopupDialogs["WATCHX_REMOVE"] = {
    text = "Remove %s from WatchX?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) ns.RemoveCustom(data) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function PopupEditBox(self)
    return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
end

StaticPopupDialogs["WATCHX_RESPAWN"] = {
    text = "Respawn time for %s in minutes\n(leave empty to let WatchX learn it):",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        local m = ns.MobState(data)
        if eb then eb:SetText(m.manualRespawn and tostring(math.floor(m.manualRespawn / 6 + 0.5) / 10) or "") end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        local v = eb and ns.Trim(eb:GetText()):gsub(",", ".") or ""
        ns.SetManualRespawn(data, v)
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local d = StaticPopupDialogs["WATCHX_RESPAWN"]
        d.OnAccept(parent, parent.data)
        parent:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["WATCHX_RESET"] = {
    text = "Reset all kill and respawn data for all mobs?",
    button1 = YES, button2 = NO,
    OnAccept = function() ns.ResetData() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function NewProfileAccept(self)
    local eb = PopupEditBox(self)
    local ok, err = ns.NewProfile(eb and eb:GetText() or "")
    if not ok then ns.Print(err) end
end
StaticPopupDialogs["WATCHX_NEWPROFILE"] = {
    text = "Name of the new profile (e.g. Leveling, Camping, PvP).\nIt starts as a copy of your current settings:",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self) local eb = PopupEditBox(self); if eb then eb:SetText(""); eb:SetFocus() end end,
    OnAccept = NewProfileAccept,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        NewProfileAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function NoteAccept(self, data)
    local eb = PopupEditBox(self)
    if data then ns.SetNote(data, eb and eb:GetText() or "") end
end
StaticPopupDialogs["WATCHX_NOTE"] = {
    text = "Note for %s:",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 120,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        local r = data and ns.db.enemies[data]
        if eb then eb:SetText(r and r.note or ""); eb:SetFocus() end
    end,
    OnAccept = NoteAccept,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        NoteAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["WATCHX_DELPROFILE"] = {
    text = "Delete the profile %s?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) ns.DeleteProfile(data) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ---------------------------------------------------------------- profile menu
-- A small list under the button that opened it: click a profile to switch, or make a new one.
local profileMenu

local function BuildProfileMenu()
    local m = CreateFrame("Frame", "WatchXProfileMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:SetWidth(190)
    Flat(m)
    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.title:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -8)
    m.title:SetText("PROFILES")
    m.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    m.hint = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    m.hint:SetPoint("TOPLEFT", m.title, "BOTTOMLEFT", 0, -3)
    m.hint:SetWidth(170)
    m.hint:SetJustifyH("LEFT")
    m.hint:SetText("What you watch, alerts and bars. Phone links are shared.")
    m.rows = {}
    m.new = FlatButton(m, "+ New profile", 170, 20, function()
        m:Hide()
        StaticPopup_Show("WATCHX_NEWPROFILE")
    end)
    m.del = FlatButton(m, "Delete", 170, 20, function()
        m:Hide()
        local cur = db().profile
        if cur then StaticPopup_Show("WATCHX_DELPROFILE", cur, nil, cur) end
    end)
    tinsert(UISpecialFrames, "WatchXProfileMenu")   -- Esc closes it
    m:Hide()
    return m
end

function ns.ToggleProfileMenu(anchor)
    profileMenu = profileMenu or BuildProfileMenu()
    local m = profileMenu
    if m:IsShown() and m.anchor == anchor then m:Hide() return end
    m.anchor = anchor
    local names, cur = ns.ProfileNames(), db().profile
    local y = -36
    for i, name in ipairs(names) do
        local r = m.rows[i]
        if not r then
            r = MenuRow(m, 170, function(self) m:Hide(); ns.SwitchProfile(self.profile) end)
            m.rows[i] = r
        end
        r.profile = name
        r:SetText(name == cur and ("|cffffd100> " .. name .. "|r") or name)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m, "TOPLEFT", 10, y)
        r:Show()
        y = y - 23
    end
    for i = #names + 1, #m.rows do m.rows[i]:Hide() end
    y = y - 6
    m.new:ClearAllPoints(); m.new:SetPoint("TOPLEFT", m, "TOPLEFT", 10, y)
    y = y - 23
    m.del:SetText("Delete \"" .. tostring(cur) .. "\"")
    m.del:SetShown(#names > 1)
    m.del:ClearAllPoints(); m.del:SetPoint("TOPLEFT", m, "TOPLEFT", 10, y)
    if #names > 1 then y = y - 23 end
    m:SetHeight(-y + 8)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    m:Show()
end

-- A small menu of flat buttons under (or next to) whatever opened it. items: { { text, fn }, ... }
local menu
function ns.ShowMenu(anchor, title, items)
    if not menu then
        menu = CreateFrame("Frame", "WatchXMenu", UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetWidth(200)
        Flat(menu)
        menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
        menu.title:SetPoint("RIGHT", menu, "RIGHT", -10, 0)
        menu.title:SetJustifyH("LEFT")
        menu.title:SetWordWrap(false)
        menu.buttons = {}
        tinsert(UISpecialFrames, "WatchXMenu")   -- Esc closes it
    end
    menu.title:SetText(title or "")
    local y = -26
    for i, it in ipairs(items) do
        local b = menu.buttons[i]
        if not b then
            b = MenuRow(menu, 180, function(self) menu:Hide(); if self.fn then self.fn() end end)
            menu.buttons[i] = b
        end
        b:SetText(it[1])
        b.fn = it[2]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
        b:Show()
        y = y - 23
    end
    for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetHeight(-y + 6)
    menu:ClearAllPoints()
    local aw = (anchor.GetWidth and anchor:GetWidth() or 0) * (anchor.GetEffectiveScale and anchor:GetEffectiveScale() or 1)
    if aw > 320 * (UIParent:GetEffectiveScale() or 1) and GetCursorPosition then   -- a wide row: right where you clicked
        local cx, cy = GetCursorPosition()
        local es = menu:GetEffectiveScale() or 1
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / es + 2, cy / es + 2)
    else
        menu:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    end
    menu:Show()
end

-- The menu for one player: KOS, avoid, the guild, a note, forget.
function ns.EnemyMenu(anchor, key)
    local r = ns.db.enemies[key]
    if not r then return end
    local items = {
        { r.kos and "Remove from KOS" or "|cffff4040Kill on sight (KOS)|r", function() ns.SetKOS(key, not r.kos) end },
        { r.avoid and "Remove from avoid list" or "|cffff8040Avoid|r – don't play with", function() ns.SetAvoid(key, not r.avoid) end },
    }
    if r.guild then
        local gk = ns.db.kosGuilds[r.guild:lower()]
        items[#items + 1] = { (gk and "Guild off KOS: " or "KOS the guild: ") .. r.guild, function() ns.SetGuildKOS(r.guild, not gk) end }
    end
    if r.wanted then
        items[#items + 1] = { "|cffffa000Edit bounty|r", function() ns.ShowBounty(key) end }
        items[#items + 1] = { "Take the bounty down", function() ns.RemoveWanted(key) end }
    else
        items[#items + 1] = { "|cffffa000WANTED|r – put a bounty on them", function() ns.ShowBounty(key) end }
    end
    items[#items + 1] = { r.note and "Edit note" or "Add note", function() StaticPopup_Show("WATCHX_NOTE", r.name, nil, key) end }
    items[#items + 1] = { "|cff909090Forget this player|r", function() ns.ForgetEnemy(key) end }
    ns.ShowMenu(anchor, r.name, items)
end

-- A close button of our own (Blizzard's UIPanelCloseButton calls HideUIPanel, which taints – see above).
local function CloseX(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    b:SetScript("OnClick", onClick or function() parent:Hide() end)
    return b
end

-- A small x inside a search box that empties it (shown while there's text).
local function ClearX(box)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(14, 14)
    b:SetPoint("RIGHT", box, "RIGHT", -3, 0)
    b:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    b:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    local t = b:GetNormalTexture()
    if t then t:SetVertexColor(0.75, 0.65, 0.45) end
    b:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)
    b:Hide()
    return b
end

-- The bounty window: a reward and a note, sent to your guild and friends (ns.SetWanted in WatchX.lua).
do
    local bw
    local function Box(parent, w, maxLetters, hint)
        local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        e:SetSize(w, 20)
        e:SetAutoFocus(false)
        e:SetMaxLetters(maxLetters)
        e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        e.hint:SetPoint("LEFT", e, "LEFT", 2, 0)
        e.hint:SetText(hint)
        e:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "" and not self:HasFocus()) end)
        e:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
        e:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
        e:SetScript("OnEscapePressed", function() parent:Hide() end)
        return e
    end
    local function Build()
        local f = CreateFrame("Frame", "WatchXBounty", UIParent)
        f:SetSize(320, 150)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        f.title = Window(f, "WANTED", 160)
        tinsert(UISpecialFrames, "WatchXBounty")
        CloseX(f)
        f.who = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        f.who:SetPoint("TOP", f, "TOP", 0, -26)
        local lr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lr:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -56)
        lr:SetText("Reward")
        f.reward = Box(f, 100, 24, "e.g. 50g")
        f.reward:SetPoint("TOPLEFT", f, "TOPLEFT", 80, -52)
        local ln = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ln:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -82)
        ln:SetText("Note")
        f.note = Box(f, 216, 100, "why – ninja looter, camps the flight path...")
        f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 80, -78)
        local function post()
            ns.SetWanted(f.key, f.name, f.reward:GetText(), f.note:GetText())
            f:Hide()
        end
        f.reward:SetScript("OnEnterPressed", function() f.note:SetFocus() end)
        f.reward:SetScript("OnTabPressed", function() f.note:SetFocus() end)
        f.note:SetScript("OnEnterPressed", post)
        f.note:SetScript("OnTabPressed", function() f.reward:SetFocus() end)
        f.post = Button(f, "Post bounty", 110, 22, post)
        f.post:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
        f.down = Button(f, "Take down", 90, 22, function() ns.RemoveWanted(f.key); f:Hide() end)
        f.down:SetPoint("LEFT", f.post, "RIGHT", 6, 0)
        local cancel = Button(f, CANCEL or "Cancel", 80, 22, function() f:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
        f.shareHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.shareHint:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
        f:Hide()
        return f
    end
    function ns.ShowBounty(key, name)
        if not key then return end
        bw = bw or Build()
        local r = db().enemies[key]
        local w = r and r.wanted
        bw.key, bw.name = key, name or (r and r.name) or key
        bw.who:SetText(bw.name)
        bw.reward:SetText(w and w.reward or "")
        bw.note:SetText(w and w.note or "")
        bw.down:SetShown(w and true or false)
        local d = db()
        local to = (d.wantedGuild ~= false and d.wantedFriends ~= false) and "your guild and online friends"
            or d.wantedGuild ~= false and "your guild" or d.wantedFriends ~= false and "your online friends" or "nobody (sharing is off)"
        bw.shareHint:SetText("Sent to " .. to .. " who run WatchX.")
        bw:Show()
        bw:Raise()
        bw.reward:SetFocus()
    end
end

local profileLabels = {}   -- fn(name) for each place that shows the active profile
function ns.UpdateProfileLabels()
    local name = db().profile or "?"
    for _, fn in ipairs(profileLabels) do fn(name) end
end

-- ---------------------------------------------------------------- settings page (Esc > Options > AddOns)

-- Adds the current target (a mob or a player) to the watch list. Returns true when added.
function ns.AddTarget()
    local name = UnitExists("target") and not UnitIsUnit("target", "player") and UnitName("target")
    if type(issecretvalue) == "function" and name and issecretvalue(name) then name = nil end
    if type(name) ~= "string" then
        ns.Print("Target a mob or a player first.")
        return false
    end
    local ok, err = ns.AddCustom(name)
    if not ok then ns.Print(err) end
    return ok
end

function ns.OpenAlertSettings()
    local cat = settingsPage and settingsPage.alertsCat
    if cat and Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, cat:GetID())
    elseif settingsPage and settingsPage.alerts and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, settingsPage.alerts)
        pcall(InterfaceOptionsFrame_OpenToCategory, settingsPage.alerts)
    else
        ns.OpenSettings()
    end
end

function ns.OpenSettings()
    if settingsCategory and Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, settingsCategory:GetID())
    elseif settingsPage and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, settingsPage)
        pcall(InterfaceOptionsFrame_OpenToCategory, settingsPage)
    end
end

-- Never close Blizzard's windows from addon code: HideUIPanel/ShowUIPanel from an addon taints the
-- game's window system, and then Character, Spellbook and the menu buttons can stop working. WatchX's
-- own windows sit above the options window instead; this only says how to get it out of the way.
local hintShown
local function HideBlizzardMenus()
    local open = (SettingsPanel and SettingsPanel:IsShown()) or (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown())
    if open and not hintShown then
        hintShown = true
        ns.Print("|cffaaaaaaPress Esc to close the options window if it's in the way.|r")
    end
end


local function BuildSettings()
    -- Two pages here: the main one (the modules – PvP first – phone links, general things) and "Alerts & scan"
    -- (the rare scan and how alerts look). Each scrolls when the window is too small: everything sits on "o",
    -- inside a scroll frame. The helpers below always add to the current "o" and "y".
    local W = 580            -- content width: everything stays inside it
    local L, COL2 = 20, 310  -- left edge, second column
    local o, y
    local function NewPage(globalName, name, titleText, subText)
        local pg = CreateFrame("Frame", globalName, UIParent)
        pg.name = name
        pg:Hide()
        local scroll = CreateFrame("ScrollFrame", nil, pg, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", pg, "BOTTOMRIGHT", -28, 4)
        local c = CreateFrame("Frame", nil, scroll)
        c:SetSize(620, 900)
        scroll:SetScrollChild(c)
        local title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -16)
        title:SetText(titleText)
        local sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
        sub:SetText(subText)
        o, y = c, -46
        return pg, c
    end
    local page = NewPage("WatchXOptions", "WatchX", "WatchX", "PvP: the enemies around you, KOS, alerts on your phone  ·  by " .. ns.AUTHOR)
    local mainO = o
    local prof = Button(o, "Profile", 180, 22, function(self) ns.ToggleProfileMenu(self) end)
    prof:SetPoint("TOPLEFT", o, "TOPLEFT", 16 + W - 180, -12)
    prof:SetScript("OnEnter", function(self)
        Tip(self, "Profiles", "Switch between sets of choices – e.g. Camping, Leveling, PvP. What you watch, "
            .. "alerts and the bars are saved per profile; phone links are shared.")
    end)
    prof:SetScript("OnLeave", GameTooltip_Hide)
    profileLabels[#profileLabels + 1] = function(name) SetButtonText(prof, "Profile: " .. name) end

    local fields, checks = {}, {}
    local chips   -- the watch list's names (Alerts & scan page)
    -- A section: a small accent-colored heading with a thin line after it.
    local function section(label)
        y = y - 10
        local h = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", o, "TOPLEFT", 16, y)
        h:SetText(label)
        h:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        local line = o:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.12)
        line:SetHeight(1)
        line:SetPoint("LEFT", h, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", o, "TOPLEFT", 16 + W, 0)
        y = y - 18
    end

    -- A text field: label at the left, the box on the same row. x/labelW/boxW for two per row.
    local function field(key, label, tip, x, labelW, boxW, load, store)
        x, labelW, boxW = x or L, labelW or 120, boxW or (W - 130)
        local name = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("TOPLEFT", o, "TOPLEFT", x, y - 4)
        name:SetWidth(labelW)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(label)
        local e = CreateFrame("EditBox", nil, o, "InputBoxTemplate")
        e:SetSize(boxW, 20)
        e:SetPoint("TOPLEFT", o, "TOPLEFT", x + labelW + 6, y)
        e:SetAutoFocus(false)
        e:SetMaxLetters(512)
        e:SetFontObject("ChatFontNormal")
        e:SetScript("OnEscapePressed", e.ClearFocus)
        e:SetScript("OnEnterPressed", e.ClearFocus)
        e:SetScript("OnEditFocusLost", function(self) self:SetCursorPosition(0) end)
        e:SetScript("OnEnter", function(self) Tip(self, label, tip) end)
        e:SetScript("OnLeave", GameTooltip_Hide)
        e.Load = function(self) self:SetText(load and load() or db()[key] or ""); self:SetCursorPosition(0) end
        e.Store = function(self)
            if store then store(ns.Trim(self:GetText())) else db()[key] = ns.Trim(self:GetText()) end
        end
        if store then   -- a list: stored when you leave the box or press Enter, not on every letter
            e:SetScript("OnEnterPressed", function(self) self:Store(); self:Load(); self:ClearFocus() end)
            e:SetScript("OnEditFocusLost", function(self) self:Store(); self:Load() end)
        else
            e:SetScript("OnTextChanged", function(self, user) if user then self:Store() end end)
        end
        fields[#fields + 1] = e
        return e
    end

    -- A check box: label with a grey hint on the same line. col2 puts it in the second column.
    local function check(label, hint, get, set, col2)
        if col2 then y = y + 26 end
        local cb = CreateFrame("CheckButton", nil, o, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", o, "TOPLEFT", col2 and COL2 or (L - 4), y + 2)
        local name = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        name:SetWidth(COL2 - L - 40)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(label .. (hint and ("  |cff808080" .. hint .. "|r") or ""))
        cb.get = get
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            self:SetChecked(get())
            if ns.UpdateChatLogPrompt then ns.UpdateChatLogPrompt() end
            if ns.RefreshUI then ns.RefreshUI() end
        end)
        checks[#checks + 1] = cb
        y = y - 26
    end


    -- A module: on/off, what it is, and a button to its own page.
    local function module(label, hint, get, set, open)
        check(label, hint, get, set)
        if open then
            local b = Button(o, "Settings", 80, 20, function() open() end)
            b:SetPoint("TOPLEFT", o, "TOPLEFT", L + W - 84, y + 26 + 1)
        end
    end
    local function openAlerts() ns.OpenAlertSettings() end

    section("PVP")
    module("Nearby enemies", "the players around you, KOS, avoid list, stealth warnings",
        function() return db().nearby end, function(v) ns.SetNearby(v) end, function() ns.OpenNearbySettings() end)
    module("Class icons on nameplates", "class, healers and KOS over enemy players",
        function() return db().plateIcons == true end, function(v) db().plateIcons = v; ns.UpdatePlates() end,
        function() ns.OpenNearbySettings() end)
    module("WANTED bounties", "shared with your guild and friends – reward and note",
        function() return db().wantedOn ~= false end, function(v) db().wantedOn = v end,
        function() ns.OpenNearbySettings() end)
    module("Alert on any enemy player", "phone + the red bar, outside instances",
        function() return db().enemyPlayers end, function(v) ns.SetEnemyPlayers(v) end, openAlerts)
    module("Attacked while idle or AFK", "phone alert",
        function() return db().attackAlert end, function(v) db().attackAlert = v end, openAlerts)

    section("MORE")
    module("Rare scan", "like unitscan: rare mobs and the names you add",
        function() return db().scanOn ~= false end, function(v) ns.SetScan(v) end, openAlerts)
    module("XP boosts", "rested, XP food, sleeping bag – below max level",
        function() return db().levelHelper ~= false end,
        function(v) db().levelHelper = v; if ns.RefreshLevel then ns.RefreshLevel() end end,
        function() ns.OpenLevelSettings() end)
    module("Buff warnings", "before and when a buff runs out",
        function() return db().buffWarn ~= false end, function(v) db().buffWarn = v end,
        function() ns.OpenBuffSettings() end)
    module("Spots on the map", "where to stand for the rares you watch",
        function() return db().mapSpots ~= false end,
        function(v) db().mapSpots = v; ns.Safe("map pins", ns.UpdateMapPins) end)
    module("AFK logout warning", "a phone alert 5 min before",
        function() return db().afkWarn end, function(v) db().afkWarn = v end)
    module("Minimap button", nil,
        function() return not db().minimap.hide end, function(v) ns.SetMinimapShown(v) end)

    section("PHONE")
    field("ntfyUrl", "ntfy link", "From the ntfy app, e.g. ntfy.sh/your-secret-topic")
    y = y - 28
    field("discordWebhook", "Discord webhook", "Server Settings > Integrations > Webhooks > Copy Webhook URL")
    y = y - 28
    field("ntfyToken", "ntfy token", "Optional – only for protected topics", L, 120, 150)
    field("discordMention", "Mention", "Discord: @here, <@userID> or empty", COL2, 70, W - (COL2 - L) - 80)
    y = y - 28

    local save = Button(o, "Save & reload", 130, 24, function()
        for _, e in ipairs(fields) do e:Store() end
        -- "ntfy.sh/topic" is fine too: https:// is added when it's missing
        for _, key in ipairs({ "ntfyUrl", "discordWebhook" }) do
            local v = db()[key]
            if v ~= "" and not v:match("^%a+://") then db()[key] = "https://" .. v end
        end
        for _, e in ipairs(fields) do e:Load() end
        ns.Print("Saved – reloading so the bridge can read it.")
        ReloadUI()
    end)
    save:SetPoint("TOPLEFT", o, "TOPLEFT", L, y)
    save:SetScript("OnEnter", function(self)
        Tip(self, "Save & reload", "WoW only writes settings to disk on a reload – that is when the bridge picks up new links.")
    end)
    save:SetScript("OnLeave", GameTooltip_Hide)
    local test = Button(o, "Send test", 110, 24, function() ns.SendTest() end)
    test:SetPoint("LEFT", save, "RIGHT", 8, 0)
    local guide = Button(o, "How it works", 120, 24, function() HideBlizzardMenus(); ns.ShowHelp() end)
    guide:SetPoint("LEFT", test, "RIGHT", 8, 0)
    local unlock = Button(o, "Unlock bars", 110, 24, function()
        HideBlizzardMenus()
        ns.StartMove()
        if panel and not panel:IsShown() then ns.TogglePanel() end
    end)
    unlock:SetPoint("LEFT", guide, "RIGHT", 8, 0)
    y = y - 34

    local status = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", o, "TOPLEFT", L, y)
    status:SetWidth(W - 4)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    status:SetSpacing(3)

    local function OnShow()
        chips:Refresh()
        for _, e in ipairs(fields) do e:Load() end
        for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end
        local d = db()
        status:SetText("Instant alerts: " .. (d.instant == false and "|cff808080off|r"
                or d.instantOK == false and "|cffff8040not working here – the chat log is used (yellow bar)|r"
                or d.instantOK and "|cff40ff40working|r" or "|cffffd100press Send test to check|r")
            .. "\n|cff808080Install the bridge once: get |cffffd100WatchX-Bridge.zip|cff808080 from |cffffd100" .. ns.BRIDGE_URL
            .. "|cff808080, unzip it and double-click \"Install (Mac)\" or \"Install (Windows)\".|r")
    end


    page:SetScript("OnShow", OnShow)
    o:SetHeight(-y + 70)   -- the whole page, for the scroll bar

    -- the second page: the rare scan and how alerts look
    local alertsPage = NewPage(nil, "Alerts & scan", "Alerts & scan", "the rare scan, the mini bar and the red alert")
    section("RARE SCAN")
    check("Any enemy player", "PvP",
        function() return db().enemyPlayers end, function(v) ns.SetEnemyPlayers(v) end)
    check("Any friendly player", "not in cities",
        function() return db().friendlyPlayers end, function(v) ns.SetFriendlyPlayers(v) end, true)
    y = y - 4
    -- The watch list: type a name and press Add (or target something and press Add target). Every name
    -- shows below with an × to remove it; click a name to switch it off/on.
    local lab = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lab:SetPoint("TOPLEFT", o, "TOPLEFT", L, y - 4)
    lab:SetWidth(114)
    lab:SetJustifyH("LEFT")
    lab:SetText("Watch list")
    local entry = CreateFrame("EditBox", nil, o, "InputBoxTemplate")
    local boxW = W - 120 - 6 - 60 - 6 - 90 - 6 - 104
    entry:SetSize(boxW, 20)
    entry:SetPoint("TOPLEFT", o, "TOPLEFT", L + 126, y)
    entry:SetAutoFocus(false)
    entry:SetMaxLetters(48)
    entry:SetFontObject("ChatFontNormal")
    entry.hint = entry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    entry.hint:SetPoint("LEFT", entry, "LEFT", 2, 0)
    entry.hint:SetText("Type a mob or player name...")
    local function AddTyped()
        local name = ns.Trim(entry:GetText())
        if name == "" then return end
        local ok, err = ns.AddCustom(name)
        if ok then entry:SetText("") else ns.Print(err) end
        entry:ClearFocus()
        chips:Refresh()
    end
    entry:SetScript("OnEnterPressed", AddTyped)
    entry:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    entry:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "" and not self:HasFocus()) end)
    entry:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    entry:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    entry:SetScript("OnEnter", function(self)
        Tip(self, "Watch list", "Exact name of a rare mob or a player (friendly or enemy), then press Enter or Add.")
    end)
    entry:SetScript("OnLeave", GameTooltip_Hide)
    local addB = Button(o, "Add", 60, 22, AddTyped)
    addB:SetPoint("LEFT", entry, "RIGHT", 6, 0)
    local addT = Button(o, "Add target", 90, 22, function()
        if ns.AddTarget() then chips:Refresh() end
    end)
    addT:SetPoint("LEFT", addB, "RIGHT", 6, 0)
    local browse = Button(o, "Browse rares", 104, 22, function() ns.ShowRares() end)
    browse:SetPoint("LEFT", addT, "RIGHT", 6, 0)
    browse:SetScript("OnEnter", function(self)
        Tip(self, "Rare catalogue", "Every rare mob in the game – search by name or zone, near your level or in "
            .. "this zone, and click one to watch it.")
    end)
    browse:SetScript("OnLeave", GameTooltip_Hide)
    y = y - 26

    -- the names, three per row
    local COLS, CHIP_H = 3, 20
    local chipW = math.floor((W - 126 - (COLS - 1) * 6) / COLS)
    chips = { list = {} }
    chips.empty = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    chips.empty:SetPoint("TOPLEFT", o, "TOPLEFT", L + 128, y - 4)
    chips.empty:SetText("Nothing watched yet – type a name, or press Browse rares.")
    for i = 1, ns.MAX_CUSTOM + #ns.PRESETS do
        local c = CreateFrame("Button", nil, o)
        c:SetSize(chipW, CHIP_H - 2)
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        c:SetPoint("TOPLEFT", o, "TOPLEFT", L + 126 + col * (chipW + 6), y - row * CHIP_H)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.13, 0.10, 0.06, 0.95)
        c.edge = c:CreateTexture(nil, "BORDER")
        c.edge:SetPoint("TOPLEFT"); c.edge:SetPoint("BOTTOMLEFT")
        c.edge:SetWidth(2)
        local hl = c:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        -- on/off: a check box at the left (off keeps the name on the list; × takes it off)
        c.box = c:CreateTexture(nil, "ARTWORK")
        c.box:SetSize(16, 16)
        c.box:SetPoint("LEFT", c, "LEFT", 4, 0)
        c.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        c.check = c:CreateTexture(nil, "OVERLAY")
        c.check:SetAllPoints(c.box)
        c.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.text:SetPoint("LEFT", c, "LEFT", 23, 0)
        c.text:SetPoint("RIGHT", c, "RIGHT", -18, 0)
        c.text:SetJustifyH("LEFT")
        c.text:SetWordWrap(false)
        c.del = CreateFrame("Button", nil, c)
        c.del:SetSize(10, 10)
        c.del:SetPoint("RIGHT", c, "RIGHT", -5, 0)
        c.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        c.del:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
        local dt = c.del:GetNormalTexture()
        if dt then dt:SetVertexColor(0.6, 0.6, 0.6) end
        c.del:SetScript("OnClick", function()
            if not c.name then return end
            if c.preset then ns.SetWatched(c.name, nil) else ns.RemoveCustom(c.name) end
            chips:Refresh()
        end)
        c.del:SetScript("OnEnter", function(self) Tip(self, "Remove", "Take " .. (c.name or "?") .. " off the list.") end)
        c.del:SetScript("OnLeave", GameTooltip_Hide)
        c:SetScript("OnClick", function()
            if c.name then ns.SetWatched(c.name, not db().watch[c.name], true); chips:Refresh() end
        end)
        c:SetScript("OnEnter", function(self)
            Tip(self, c.name or "?", db().watch[c.name or ""] and "On – it's looked for." or "Off – kept on the list, not looked for.",
                "|cffffd100Click:|r on/off", "|cffffd100×:|r take it off the list")
        end)
        c:SetScript("OnLeave", GameTooltip_Hide)
        c:Hide()
        chips.list[i] = c
    end
    function chips:Refresh()
        -- the built-in rares you watch (Prince Nazjak – he has map spots), then your own names
        local names, preset = {}, {}
        for _, p in ipairs(ns.PRESETS) do   -- on (true) or switched off but kept (false)
            if db().watch[p.name] ~= nil then names[#names + 1] = p.name; preset[p.name] = true end
        end
        for _, n in ipairs(db().custom) do names[#names + 1] = n end
        for i, c in ipairs(self.list) do
            local name = names[i]
            c.name, c.preset = name, name and preset[name] or nil
            if name then
                local on = db().watch[name] and true or false
                c.text:SetText(on and name or ("|cff808080" .. name .. "|r"))
                c.check:SetShown(on)
                c.box:SetAlpha(on and 1 or 0.6)
                c.edge:SetColorTexture(on and ACCENT[1] or 0.4, on and ACCENT[2] or 0.4, on and ACCENT[3] or 0.4, 1)
                c:Show()
            else
                c:Hide()
            end
        end
        self.empty:SetShown(#names == 0)
    end
    ns.RefreshWatchChips = function() if alertsPage:IsShown() then chips:Refresh() end end
    page.watchEntry, page.watchChips = entry, chips
    y = y - math.ceil((ns.MAX_CUSTOM + #ns.PRESETS) / COLS) * CHIP_H - 4

    section("ALERTS")
    check("Phone alerts", "ntfy / Discord",
        function() return db().whisper end, function(v) db().whisper = v end)
    check("Instant alerts", "with a screenshot",
        function() return db().instant ~= false end, function(v) db().instant = v; db().instantOK = nil end, true)
    check("Alert on death", "when it's killed",
        function() return db().notifyDeath end, function(v) db().notifyDeath = v end)
    check("Sound", "raid warning",
        function() return db().sound end, function(v) db().sound = v end, true)

    section("DISPLAY")
    check("Mini bar", "status on screen",
        function() return db().show end, function(v) ns.SetMiniShown(v) end)
    check("Only on alerts", "hidden until a hit",
        function() return db().miniQuiet end, function(v) db().miniQuiet = v end, true)
    check("Auto-hide", "when nothing is watched",
        function() return db().hideIdle end, function(v) db().hideIdle = v end)
    check("Alert in the mini bar's spot", "off: own spot",
        function() return db().alertSame ~= false end, function(v) db().alertSame = v end, true)
    local move = Button(o, "Unlock bars", 110, 22, function()
        HideBlizzardMenus()
        ns.StartMove()
        if panel and not panel:IsShown() then ns.TogglePanel() end   -- its Lock button locks them again
    end)
    move:SetPoint("TOPLEFT", o, "TOPLEFT", L, y - 4)
    move:SetScript("OnEnter", function(self)
        Tip(self, "Unlock bars", "Shows the mini bar – and the red alert, if it has its own spot – so you can drag "
            .. "them. Press Lock (top of the screen) or type /wx lock when done.")
    end)
    move:SetScript("OnLeave", GameTooltip_Hide)
    local reset = Button(o, "Reset timers", 110, 22, function() StaticPopup_Show("WATCHX_RESET") end)
    reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
    y = y - 34

    alertsPage:SetScript("OnShow", OnShow)
    o:SetHeight(-y + 70)
    page.alerts = alertsPage

    settingsPage = page
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, page, "WatchX")
        if ok and cat then
            settingsCategory = cat
            pcall(Settings.RegisterAddOnCategory, cat)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
    ns.BuildNearbySettings()   -- "PvP" first, then the rest
    alertsPage.parent = "WatchX"
    if settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutSubcategory, settingsCategory, alertsPage, "Alerts & scan")
        if ok and cat then page.alertsCat = cat end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(alertsPage)
    end
    ns.BuildLevelSettings()
    ns.BuildBuffSettings()
end

-- ---------------------------------------------------------------- rare catalogue
-- Every rare mob in the game (Data/Rares.lua, from the Questie database): search by name or zone, near your
-- level or in this zone, and click one to put it on the watch list (or take it off).
do
    local cat
    local CAT_ROW_H = 18
    local areaNames = {}
    local function AreaName(id)
        if areaNames[id] == nil then
            local ok, n = false, nil
            if C_Map and C_Map.GetAreaInfo then ok, n = pcall(C_Map.GetAreaInfo, id) end
            areaNames[id] = (ok and type(n) == "string" and n) or false
        end
        return areaNames[id] or ("zone " .. id)
    end
    local function IsWatched(name) return db().watch[name] and true or false end
    local function Toggle(name)
        local known = ns.FindAny(name)
        if known then
            local custom = false
            for _, n in ipairs(db().custom) do if n == known then custom = true end end
            if IsWatched(known) then
                if custom then ns.RemoveCustom(known) else ns.SetWatched(known, false) end
            else
                ns.SetWatched(known, true)
            end
        else
            local ok, err = ns.AddCustom(name)
            if not ok then ns.Print(err) end
        end
        if db().scanOn == false then ns.Print("|cffffd100The rare scan is off|r – switch it on under Settings > WatchX.") end
        if ns.RefreshWatchChips then ns.RefreshWatchChips() end
    end

    local function Filtered()
        local q = ns.Trim(cat.search:GetText() or ""):lower()
        local lvl = tonumber(ns.Plain and ns.Plain(UnitLevel("player")) or UnitLevel("player")) or 0
        local here = GetZoneText and GetZoneText() or ""
        if type(here) ~= "string" then here = "" end
        local list = {}
        for _, r in ipairs(ns.RARES or {}) do
            local zone = AreaName(r[5])
            local ok = true
            if q ~= "" and not (r[2]:lower():find(q, 1, true) or zone:lower():find(q, 1, true)) then ok = false end
            if ok and cat.near and lvl > 0 and (r[4] < lvl - 5 or r[3] > lvl + 5) then ok = false end
            if ok and cat.zoneOnly and zone ~= here then ok = false end
            if ok and cat.watchedOnly and not IsWatched(r[2]) then ok = false end
            if ok then list[#list + 1] = r end
        end
        return list
    end

    local function Row(i)
        local b = cat.rows[i]
        if b then return b end
        b = CreateFrame("Button", nil, cat.child)
        b:SetHeight(CAT_ROW_H)
        b:SetPoint("TOPLEFT", cat.child, "TOPLEFT", 0, -(i - 1) * CAT_ROW_H)
        b:SetPoint("RIGHT", cat.child, "RIGHT", 0, 0)
        b:RegisterForClicks("LeftButtonUp")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.12)
        b.check = b:CreateTexture(nil, "ARTWORK")
        b.check:SetSize(14, 14)
        b.check:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.name:SetPoint("LEFT", b, "LEFT", 22, 0)
        b.name:SetWidth(190)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.lvl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.lvl:SetPoint("LEFT", b, "LEFT", 216, 0)
        b.lvl:SetWidth(50)
        b.lvl:SetJustifyH("LEFT")
        b.zone = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.zone:SetPoint("LEFT", b, "LEFT", 270, 0)
        b.zone:SetPoint("RIGHT", b, "RIGHT", -70, 0)
        b.zone:SetJustifyH("LEFT")
        b.zone:SetWordWrap(false)
        b.where = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.where:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b:SetScript("OnClick", function(self)
            if self.r then Toggle(self.r[2]); ns.RefreshRares() end
        end)
        b:SetScript("OnEnter", function(self)
            local r = self.r
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(r[2])
            GameTooltip:AddLine((r[6] and "Rare Elite" or "Rare") .. " · level " .. (r[3] == r[4] and r[3] or (r[3] .. "-" .. r[4])), 1, 0.82, 0)
            GameTooltip:AddLine(AreaName(r[5]) .. ((r[7] or 0) > 0 and ("  " .. r[7] .. ", " .. r[8]) or ""), 1, 1, 1)
            if (r[9] or 0) > 1 then GameTooltip:AddLine(r[9] .. " spawn points – the place is the middle of them", 0.7, 0.7, 0.7, true) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(IsWatched(r[2]) and "|cffffd100Click:|r stop watching" or "|cffffd100Click:|r watch it (phone alert when it's up)", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        cat.rows[i] = b
        return b
    end

    function ns.RefreshRares()
        if not (cat and cat:IsShown()) then return end
        local list = Filtered()
        for i, r in ipairs(list) do
            local b = Row(i)
            b.r = r
            local on = IsWatched(r[2])
            b.check:SetShown(on)
            b.name:SetText((r[6] and "|cffffd100" or "") .. r[2] .. (r[6] and "|r" or ""))
            b.lvl:SetText(r[3] == r[4] and tostring(r[3]) or (r[3] .. "-" .. r[4]))
            b.zone:SetText(AreaName(r[5]))
            b.where:SetText((r[7] or 0) > 0 and (r[7] .. ", " .. r[8]) or "")
            b:Show()
        end
        for i = #list + 1, #cat.rows do cat.rows[i]:Hide(); cat.rows[i].r = nil end
        cat.child:SetHeight(math.max(1, #list * CAT_ROW_H))
        local n = 0
        for _, nm in ipairs(db().custom) do n = n + 1 end
        cat.count:SetText(#list .. " rares  ·  your list: " .. n .. "/" .. ns.MAX_CUSTOM
            .. (db().scanOn == false and "  ·  |cffff6060the rare scan is off|r" or ""))
    end

    local function Build()
        local f = CreateFrame("Frame", "WatchXRares", UIParent)
        f:SetSize(560, 470)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        Window(f, "Rare catalogue", 200)
        tinsert(UISpecialFrames, "WatchXRares")
        CloseX(f)
        cat = f
        f.rows = {}
        f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.search:SetSize(200, 20)
        f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -36)
        f.search:SetAutoFocus(false)
        f.search.hint = f.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.search.hint:SetPoint("LEFT", f.search, "LEFT", 2, 0)
        f.search.hint:SetText("Search a name or a zone...")
        f.search.clear = ClearX(f.search)
        f.search:SetScript("OnTextChanged", function(self)
            self.hint:SetShown(self:GetText() == "" and not self:HasFocus())
            self.clear:SetShown(self:GetText() ~= "")
            ns.RefreshRares()
        end)
        f.search:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
        f.search:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
        f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local x = 236
        for _, opt in ipairs({ { "near", "Near my level" }, { "zoneOnly", "This zone" }, { "watchedOnly", "Watched" } }) do
            local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", f, "TOPLEFT", x, -34)
            local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", cb, "RIGHT", 0, 1)
            t:SetText(opt[2])
            cb:SetScript("OnClick", function(self) f[opt[1]] = self:GetChecked() and true or false; ns.RefreshRares() end)
            if opt[1] == "near" then cb:SetChecked(true); f.near = true end
            x = x + 30 + (t:GetStringWidth() or 60) + 8
        end
        local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + 22, -66)
        head:SetText("Name")
        local hl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hl:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + 216, -66)
        hl:SetText("Level")
        local hz = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hz:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + 270, -66)
        hz:SetText("Zone")
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -82)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 40)
        f.child = CreateFrame("Frame", nil, scroll)
        f.child:SetSize(500, 1)
        scroll:SetScrollChild(f.child)
        scroll:SetScript("OnSizeChanged", function(self, w) f.child:SetWidth(w) end)
        f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 16)
        local done = Button(f, "Done", 80, 22, function() f:Hide() end)
        done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 12)
        f:SetScript("OnShow", function() ns.RefreshRares() end)
        f:Hide()
        return f
    end

    function ns.ShowRares()
        if not ns.RARES then ns.Print("The rare list didn't load (Data/Rares.lua).") return end
        cat = cat or Build()
        HideBlizzardMenus()
        cat:Show()
        cat:Raise()
        ns.RefreshRares()
    end
end

-- ---------------------------------------------------------------- enemy history window
-- A big table of every enemy player you've met (kept between sessions). Click a column to sort, search,
-- and tabs: All, KOS, Notes, Guilds (every guild you've met, with a KOS switch = the guild blacklist).
local history
local HIST_ROW_H, HIST_MAX = 18, 400
local function ClassColor(c) return ns.ClassColor(c) end   -- defined with the Nearby list
local function ClassName(c) return ns.ClassName(c) end

local PCOLS = {   -- players
    { key = "name", label = "Name", w = 150, j = "LEFT" },
    { key = "level", label = "Lvl", w = 34, j = "CENTER", num = true },
    { key = "class", label = "Class", w = 70, j = "LEFT" },
    { key = "guild", label = "Guild", w = 125, j = "LEFT" },
    { key = "kills", label = "Kills", w = 40, j = "CENTER", num = true },
    { key = "deaths", label = "Deaths", w = 48, j = "CENTER", num = true },
    { key = "seen", label = "Seen", w = 40, j = "CENTER", num = true },
    { key = "lastSeen", label = "Last seen", w = 66, j = "RIGHT", num = true },
    { key = "zone", label = "Zone", w = 110, j = "LEFT" },
    { key = "note", label = "Note", w = 120, j = "LEFT" },
}
local GCOLS = {   -- guilds
    { key = "name", label = "Guild", w = 190, j = "LEFT" },
    { key = "players", label = "Players", w = 60, j = "CENTER", num = true },
    { key = "kosPlayers", label = "KOS players", w = 80, j = "CENTER", num = true },
    { key = "kills", label = "Kills", w = 50, j = "CENTER", num = true },
    { key = "deaths", label = "Deaths", w = 56, j = "CENTER", num = true },
    { key = "lastSeen", label = "Last seen", w = 80, j = "RIGHT", num = true },
    { key = "kos", label = "Blacklist", w = 100, j = "CENTER", num = true },
}
local HIST_W = 12 + 803 + 40

local function BuildHistory()
    local f = CreateFrame("Frame", "WatchXHistory", UIParent)
    f:SetSize(HIST_W, 480)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Window(f, "Players met", 200)
    tinsert(UISpecialFrames, "WatchXHistory")
    CloseX(f)

    f.tab, f.sort = "all", { all = { "lastSeen", true }, guilds = { "lastSeen", true } }
    f.tabs = {}
    local prev
    for _, t in ipairs({ { "all", "All players" }, { "kos", "KOS" }, { "avoid", "Avoid" }, { "wanted", "Wanted" }, { "notes", "Notes" }, { "guilds", "Guilds" } }) do
        local b = FlatButton(f, t[2], 84, 22, function()
            f.tab = t[1]
            f.backTo = nil
            ns.RefreshHistory()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -40) end
        b.key = t[1]
        f.tabs[#f.tabs + 1] = b
        prev = b
    end
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(170, 20)
    f.search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -41)
    f.search:SetAutoFocus(false)
    f.search:SetScript("OnTextChanged", function() ns.RefreshHistory() end)
    f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.search.hint = f.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.search.hint:SetPoint("LEFT", f.search, "LEFT", 2, 0)
    f.search.hint:SetText("Search name, guild, zone, note...")
    f.search:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    f.search:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    f.clear = ClearX(f.search)
    -- "Show its players" (Guilds tab) remembers where you came from: Back goes there again
    f.back = FlatButton(f, "< Back", 80, 22, function()
        local b = f.backTo
        f.backTo = nil
        f.tab = b and b.tab or "guilds"
        f.search:SetText(b and b.search or "")
        ns.RefreshHistory()
    end)
    f.back:SetPoint("RIGHT", f.search, "LEFT", -12, 0)
    f.back:Hide()

    -- column headers (click = sort; again = the other way)
    f.heads = {}
    for i = 1, #PCOLS do
        local h = CreateFrame("Button", nil, f)
        h:SetHeight(20)
        local bg = h:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.22, 0.17, 0.09, 1)
        local hl = h:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetPoint("LEFT", h, "LEFT", 4, 0)
        h.text:SetPoint("RIGHT", h, "RIGHT", -4, 0)
        h:SetScript("OnClick", function(self)
            local srt = f.sort[f.tab == "guilds" and "guilds" or "all"]
            if srt[1] == self.key then srt[2] = not srt[2] else srt[1], srt[2] = self.key, self.num and true or false end
            ns.RefreshHistory()
        end)
        f.heads[i] = h
    end

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -92)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 40)
    f.child = CreateFrame("Frame", nil, scroll)
    f.child:SetSize(HIST_W - 46, 10)
    scroll:SetScrollChild(f.child)
    f.rows = {}

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 15)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 15)
    -- Guilds tab: add a guild to the blacklist by name
    f.addG = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.addG:SetSize(150, 20)
    f.addG:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 240, 11)
    f.addG:SetAutoFocus(false)
    f.addG.hint = f.addG:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.addG.hint:SetPoint("LEFT", f.addG, "LEFT", 2, 0)
    f.addG.hint:SetText("Guild to blacklist...")
    local function addGuild()
        local t = ns.Trim(f.addG:GetText())
        if t ~= "" then ns.SetGuildKOS(t, true); f.addG:SetText("") end
        f.addG:ClearFocus()
    end
    f.addG:SetScript("OnEnterPressed", addGuild)
    f.addG:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    f.addG:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    f.addGB = FlatButton(f, "Blacklist", 70, 20, addGuild)
    f.addGB:SetPoint("LEFT", f.addG, "RIGHT", 6, 0)

    f:SetScript("OnShow", function() ns.RefreshHistory() end)
    f:Hide()
    return f
end

local function HistoryRow(i)
    local f = history
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f.child)
    r:SetHeight(HIST_ROW_H - 1)
    r:SetPoint("TOPLEFT", f.child, "TOPLEFT", 0, -(i - 1) * HIST_ROW_H)
    r:SetPoint("TOPRIGHT", f.child, "TOPRIGHT", 0, -(i - 1) * HIST_ROW_H)
    r.bar = r:CreateTexture(nil, "BACKGROUND")
    r.bar:SetAllPoints()
    r.edge = r:CreateTexture(nil, "BORDER")
    r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(3)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    r.cells = {}
    for c = 1, #PCOLS do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        r.cells[c] = fs
    end
    r:SetScript("OnClick", function(self)
        if self.guild then
            local g, on = self.guild, ns.db.kosGuilds[self.guild:lower()] ~= nil
            ns.ShowMenu(self, "<" .. g .. ">", {
                { on and "Take off the blacklist" or "|cffff4040Blacklist (KOS guild)|r", function() ns.SetGuildKOS(g, not on) end },
                { "Show its players", function()
                    f.backTo = { tab = "guilds", search = f.search:GetText() }
                    f.tab = "all"; f.search:SetText(g); f.search.hint:Hide(); ns.RefreshHistory()
                end },
            })
        elseif self.key then
            ns.EnemyMenu(self, self.key)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.key then return end
        local rec = ns.db.enemies[self.key]
        if not rec then return end
        local cr, cg, cb = ClassColor(rec.class)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(rec.name, cr, cg, cb)
        GameTooltip:AddLine(((rec.level and rec.level > 0) and rec.level or "??") .. " " .. (rec.race and (rec.race .. " ") or "")
            .. ClassName(rec.class) .. (rec.guild and ("  <" .. rec.guild .. ">") or ""), 1, 1, 1)
        if rec.lastSeen then
            GameTooltip:AddLine("Last seen " .. ns.AgoLong(time() - rec.lastSeen) .. " ago" .. (rec.zone and (" · " .. rec.zone) or ""), 0.7, 0.7, 0.7)
        end
        ns.AddEnemyHistoryLines(self.key)
        GameTooltip:AddLine("|cffffd100Click:|r KOS, note, forget", 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    f.rows[i] = r
    return r
end

-- Lays out the header and a row's cells for a column set.
local function PlaceColumns(cols, cells, parent, y)
    local x = 0
    for c, col in ipairs(cols) do
        local fs = cells[c]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 6, y)
        fs:SetWidth(col.w - 8)
        fs:SetHeight(HIST_ROW_H - 1)
        fs:SetJustifyH(col.j)
        fs:Show()
        x = x + col.w
    end
    for c = #cols + 1, #cells do cells[c]:Hide() end
end

function ns.RefreshHistory()
    if not (history and history:IsShown()) then return end
    local f, d, now = history, db(), time()
    local guildsTab = f.tab == "guilds"
    local cols = guildsTab and GCOLS or PCOLS
    for _, b in ipairs(f.tabs) do b:SetAlpha(b.key == f.tab and 1 or 0.5) end
    f.addG:SetShown(guildsTab); f.addGB:SetShown(guildsTab)
    f.hint:SetText(guildsTab and "Click a guild: blacklist, show its players" or "Click a player: KOS, note, forget")
    -- headers
    local srt = f.sort[guildsTab and "guilds" or "all"]
    local x = 12
    for i, h in ipairs(f.heads) do
        local col = cols[i]
        if col then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", f, "TOPLEFT", x, -68)
            h:SetWidth(col.w - 2)
            h.key, h.num = col.key, col.num
            h.text:SetJustifyH(col.j)
            h.text:SetText(col.label .. (srt[1] == col.key and (srt[2] and " v" or " ^") or ""))
            h:Show()
            x = x + col.w
        else
            h:Hide()
        end
    end
    local q = ns.Trim(f.search:GetText() or ""):lower()
    f.search.hint:SetShown(q == "" and not f.search:HasFocus())
    f.clear:SetShown(q ~= "")
    f.back:SetShown(f.backTo ~= nil and f.tab ~= "guilds")
    local function match(...)
        if q == "" then return true end
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and v:lower():find(q, 1, true) then return true end
        end
    end
    local items, total = {}, 0
    if guildsTab then
        local byG = {}
        for key, r in pairs(d.enemies) do
            if r.guild then
                local g = byG[r.guild:lower()]
                if not g then
                    g = { name = r.guild, players = 0, kosPlayers = 0, kills = 0, deaths = 0, lastSeen = 0 }
                    byG[r.guild:lower()] = g
                end
                g.players = g.players + 1
                if r.kos then g.kosPlayers = g.kosPlayers + 1 end
                g.kills, g.deaths = g.kills + (r.kills or 0), g.deaths + (r.deaths or 0)
                g.lastSeen = math.max(g.lastSeen, r.lastSeen or 0)
            end
        end
        for lower, name in pairs(d.kosGuilds) do   -- blacklisted guilds you haven't met yet
            if not byG[lower] then byG[lower] = { name = name, players = 0, kosPlayers = 0, kills = 0, deaths = 0, lastSeen = 0 } end
        end
        for lower, g in pairs(byG) do
            total = total + 1
            g.kos = d.kosGuilds[lower] and 1 or 0
            if match(g.name) then items[#items + 1] = g end
        end
    else
        for key, r in pairs(d.enemies) do
            total = total + 1
            local kos = ns.IsKOS(key, nil, r.guild)
            local ok = f.tab == "all" or (f.tab == "kos" and kos) or (f.tab == "avoid" and r.avoid) or (f.tab == "wanted" and r.wanted) or (f.tab == "notes" and r.note)
            if ok and match(r.name, key, r.guild, r.zone, r.note, r.class) then
                items[#items + 1] = { key = key, r = r, kos = kos, name = (r.name or key):lower(), level = r.level or 0,
                    class = r.class or "", guild = (r.guild or "~"):lower(), kills = r.kills or 0, deaths = r.deaths or 0,
                    seen = r.seen or 0, lastSeen = r.lastSeen or 0, zone = r.zone or "~", note = r.note or "~" }
            end
        end
    end
    local sk, desc = srt[1], srt[2]
    table.sort(items, function(a, b)
        local va, vb = a[sk], b[sk]
        if type(va) == "string" then va, vb = va:lower(), tostring(vb or ""):lower() end
        if va == vb then return (a.lastSeen or 0) > (b.lastSeen or 0) end
        if desc then return va > vb end
        return va < vb
    end)
    local n = math.min(#items, HIST_MAX)
    for i = 1, n do
        local it, row = items[i], HistoryRow(i)
        PlaceColumns(cols, row.cells, row, 0)
        local alt = (i % 2 == 0) and 0.05 or 0
        if guildsTab then
            row.key, row.guild = nil, it.name
            row.bar:SetColorTexture(0.11 + alt, 0.09 + alt, 0.06 + alt, 0.9)
            row.edge:SetColorTexture(it.kos == 1 and 1 or 0.3, it.kos == 1 and 0.2 or 0.3, it.kos == 1 and 0.2 or 0.3, 1)
            local v = { "<" .. it.name .. ">", it.players, it.kosPlayers > 0 and ("|cffff5050" .. it.kosPlayers .. "|r") or "0",
                "|cffffd100" .. it.kills .. "|r", "|cffff6060" .. it.deaths .. "|r",
                it.lastSeen > 0 and ns.AgoLong(now - it.lastSeen) or "-",
                it.kos == 1 and "|cffff3030KOS|r" or "|cff808080-|r" }
            for c = 1, #GCOLS do row.cells[c]:SetText(v[c]); row.cells[c]:SetTextColor(1, 1, 1) end
        else
            local r = it.r
            local cr, cg, cb = ClassColor(r.class)
            row.key, row.guild = it.key, nil
            row.bar:SetColorTexture(0.11 + alt, 0.09 + alt, 0.06 + alt, 0.9)
            row.edge:SetColorTexture(cr, cg, cb, 1)
            local v = { (it.kos and "|cffff3030KOS|r " or "") .. (r.wanted and (r.wanted.claimed and "|cff40ff40CLAIMED|r " or "|cffffa000WANTED|r ") or "")
                .. (r.avoid and "|cffff8040AVOID|r " or "") .. (r.name or it.key),
                (r.level and r.level > 0) and r.level or "??", ClassName(r.class), r.guild or "|cff606060-|r",
                (r.kills or 0) > 0 and ("|cffffd100" .. r.kills .. "|r") or "0",
                (r.deaths or 0) > 0 and ("|cffff6060" .. r.deaths .. "|r") or "0",
                r.seen or 1, r.lastSeen and ns.AgoLong(now - r.lastSeen) or "-",
                r.zone or "|cff606060-|r", r.note or "" }
            for c = 1, #PCOLS do row.cells[c]:SetText(v[c]); row.cells[c]:SetTextColor(1, 1, 1) end
            row.cells[1]:SetTextColor(cr, cg, cb)
            row.cells[3]:SetTextColor(cr, cg, cb)
            row.cells[10]:SetTextColor(1, 1, 0.6)
        end
        row:Show()
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    f.child:SetHeight(math.max(10, n * HIST_ROW_H))
    f.count:SetText("Showing " .. #items .. " of " .. total .. (guildsTab and " guilds" or " players")
        .. (#items > HIST_MAX and (" (first " .. HIST_MAX .. ")") or ""))
end

function ns.ShowHistory(tab)
    history = history or BuildHistory()
    if tab then history.tab = tab end
    history:Show()
    history:Raise()
    ns.RefreshHistory()
end

-- Hovering an enemy player in the world: WatchX adds KOS, kills, last seen and the note to the tooltip.
local function TooltipUnit(tip)
    if not (tip and tip.GetUnit) then return end
    local _, unit = tip:GetUnit()
    if type(issecretvalue) == "function" and unit and issecretvalue(unit) then return end
    if type(unit) ~= "string" or not UnitIsPlayer(unit) then return end
    local key, _, first = ns.PlayerKey(unit)
    if not key then return end
    local rec = ns.db.enemies[key]
    local guild = GetGuildInfo(unit)
    if type(issecretvalue) == "function" and guild and issecretvalue(guild) then guild = nil end
    local kos, why = ns.IsKOS(key, first, guild)
    local role, how = ns.Role(key, unit)
    local avoid = rec and rec.avoid
    if not rec and not kos and not role then return end
    if rec and rec.wanted and ns.db.wantedOn ~= false then tip:AddLine("WatchX: " .. ns.WantedLine(rec.wanted), 1, 1, 1, true) end
    if avoid then tip:AddLine(ns.AvoidLine(rec), 1, 0.5, 0.25, true) end
    if role == "healer" then tip:AddLine("WatchX: healer (" .. tostring(how) .. ")", 0.3, 1, 0.4)
    elseif role == "dps" then tip:AddLine("WatchX: not a healer (" .. tostring(how) .. ")", 0.7, 0.7, 0.7) end
    if kos then tip:AddLine(why == "guild" and "WatchX: KOS guild" or "WatchX: KOS – kill on sight", 1, 0.2, 0.2) end
    if rec then
        if (rec.seen or 0) > 0 or (rec.kills or 0) > 0 or (rec.deaths or 0) > 0 then
            tip:AddLine("WatchX: you killed " .. (rec.kills or 0) .. " · killed you " .. (rec.deaths or 0)
                .. " · seen " .. (rec.seen or 1) .. "x", 1, 0.82, 0)
        end
        if rec.note and not avoid then tip:AddLine("Note: " .. rec.note, 1, 1, 0.6, true) end
    end
    tip:Show()
end
function ns.HookTooltip()
    if ns.tooltipHooked then return end
    ns.tooltipHooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tip)
            if tip == GameTooltip then pcall(TooltipUnit, tip) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tip) pcall(TooltipUnit, tip) end)
    end
end

-- ---------------------------------------------------------------- Nearby settings page (WatchX > Nearby)
-- The Spy-like list is its own thing: its own page under WatchX.
local nearbyPage, nearbyCategory

function ns.OpenNearbySettings()
    if nearbyCategory and Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, nearbyCategory:GetID())
    elseif nearbyPage and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, nearbyPage)
        pcall(InterfaceOptionsFrame_OpenToCategory, nearbyPage)
    else
        ns.OpenSettings()
    end
end

function ns.BuildNearbySettings()
    local page = CreateFrame("Frame", "WatchXNearbyOptions", UIParent)
    page.name, page.parent = "PvP", "WatchX"
    page:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 4)
    local o = CreateFrame("Frame", nil, scroll)
    o:SetSize(600, 900)
    scroll:SetScrollChild(o)
    local L, W = 20, 560

    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -16)
    title:SetText("PvP")
    local sub = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("the Nearby list, KOS, avoid list and nameplate icons")

    local y = -50
    local checks = {}
    local function check(label, hint, get, set)
        local cb = CreateFrame("CheckButton", nil, o, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", o, "TOPLEFT", L - 4, y + 2)
        local name = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        name:SetText(label .. (hint and ("  |cff808080" .. hint .. "|r") or ""))
        cb.get = get
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            self:SetChecked(get())
            ns.RefreshUI()
        end)
        checks[#checks + 1] = cb
        y = y - 28
    end
    check("Show the Nearby list", "the enemy players around you",
        function() return db().nearby end, function(v) ns.SetNearby(v) end)
    check("Stealth warning", "a card mid-screen when a player goes into stealth",
        function() return db().stealthWarn ~= false end, function(v) db().stealthWarn = v end)
    check("Sound with the warning", nil,
        function() return db().stealthSound ~= false end, function(v) db().stealthSound = v end)
    check("New enemy card", "for every new enemy (Stealth and KOS always show)",
        function() return db().newEnemyCard == true end, function(v) db().newEnemyCard = v end)
    check("Attach under the mini bar", "they move and grow together",
        function() return db().nearbyAttach ~= false end, function(v) db().nearbyAttach = v; ns.AttachNearby() end)
    check("Warnings on top of the list", "off: top of the screen (Unlock to move)",
        function() return db().warnDock == true end, function(v) db().warnDock = v end)
    check("Show the list when it's empty", "off: it only shows when enemies are around",
        function() return db().nearbyShowEmpty == true end, function(v) db().nearbyShowEmpty = v end)
    check("KOS alert", "a red card + sound when a KOS player shows up",
        function() return db().kosAlert ~= false end, function(v) db().kosAlert = v end)
    check("Hide in dungeons", "off: faded",
        function() return db().nearbyHideDungeon == true end, function(v) db().nearbyHideDungeon = v end)
    check("Hide in raids", "off: faded",
        function() return db().nearbyHideRaid == true end, function(v) db().nearbyHideRaid = v end)
    check("Hide in battlegrounds", "and arenas · off: the list works there",
        function() return db().nearbyNoBG ~= false end, function(v) db().nearbyNoBG = v end)
    -- how many players the list shows: [-] 10 [+]
    local maxLab = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    maxLab:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, y - 4)
    maxLab:SetText("Max players shown")
    local minus = FlatButton(o, "-", 22, 20, function()
        db().nearbyMax = math.max(3, ns.NearbyMax() - 1); ns.RefreshUI(); o.maxVal:SetText(ns.NearbyMax())
    end)
    minus:SetPoint("TOPLEFT", o, "TOPLEFT", L + 150, y - 1)
    o.maxVal = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.maxVal:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    o.maxVal:SetWidth(22)
    local plus = FlatButton(o, "+", 22, 20, function()
        db().nearbyMax = math.min(ns.NB_ROWS, ns.NearbyMax() + 1); ns.RefreshUI(); o.maxVal:SetText(ns.NearbyMax())
    end)
    plus:SetPoint("LEFT", o.maxVal, "RIGHT", 6, 0)
    local maxHint = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    maxHint:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    maxHint:SetText("3 – 20 · the newest first")
    y = y - 28
    -- how long a player stays after he was last seen: [-] 5 [+] min
    local keepLab = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keepLab:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, y - 4)
    keepLab:SetText("Keep players for")
    local kminus = FlatButton(o, "-", 22, 20, function()
        db().nearbyKeep = math.max(1, ns.NearbyKeepMin() - 1); ns.RefreshUI(); o.keepVal:SetText(ns.NearbyKeepMin())
    end)
    kminus:SetPoint("TOPLEFT", o, "TOPLEFT", L + 150, y - 1)
    o.keepVal = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.keepVal:SetPoint("LEFT", kminus, "RIGHT", 6, 0)
    o.keepVal:SetWidth(22)
    local kplus = FlatButton(o, "+", 22, 20, function()
        db().nearbyKeep = math.min(30, ns.NearbyKeepMin() + 1); ns.RefreshUI(); o.keepVal:SetText(ns.NearbyKeepMin())
    end)
    kplus:SetPoint("LEFT", o.keepVal, "RIGHT", 6, 0)
    local keepHint = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    keepHint:SetPoint("LEFT", kplus, "RIGHT", 8, 0)
    keepHint:SetText("minutes after last seen (bright the first 30 s)")
    y = y - 28
    y = y - 8

    local ex = Button(o, "Show example", 130, 24, function() HideBlizzardMenus(); ns.NearbyTest() end)
    ex:SetPoint("TOPLEFT", o, "TOPLEFT", L, y)
    local mv = Button(o, "Move / resize", 130, 24, function()
        HideBlizzardMenus()
        if not db().nearby then ns.SetNearby(true) end
        ns.StartMove()
        if panel and not panel:IsShown() then ns.TogglePanel() end   -- its Lock button locks them again
    end)
    mv:SetPoint("LEFT", ex, "RIGHT", 8, 0)
    local clr = Button(o, "Clear list", 110, 24, function() wipe(ns.nearby); ns.RefreshUI() end)
    clr:SetPoint("LEFT", mv, "RIGHT", 8, 0)
    local hist = Button(o, "History...", 110, 24, function() HideBlizzardMenus(); ns.ShowHistory() end)
    hist:SetPoint("LEFT", clr, "RIGHT", 8, 0)
    y = y - 40

    -- KOS: players and guilds
    local function heading(text)
        local h = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", o, "TOPLEFT", 16, y)
        h:SetText(text)
        h:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        local line = o:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3)
        line:SetHeight(1)
        line:SetPoint("LEFT", h, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", o, "TOPLEFT", L + W, 0)
        y = y - 20
    end
    local function addRow(label, hint, onAdd, targetText, onTarget)
        local lab = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lab:SetPoint("TOPLEFT", o, "TOPLEFT", L, y - 4)
        lab:SetText(label)
        local eb = CreateFrame("EditBox", nil, o, "InputBoxTemplate")
        eb:SetSize(190, 20)
        eb:SetPoint("TOPLEFT", o, "TOPLEFT", L + 100, y)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(48)
        eb.hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        eb.hint:SetPoint("LEFT", eb, "LEFT", 2, 0)
        eb.hint:SetText(hint)
        local function go()
            local t = ns.Trim(eb:GetText())
            if t ~= "" then onAdd(t); eb:SetText("") end
            eb:ClearFocus()
            eb.hint:SetShown(eb:GetText() == "")
        end
        eb:SetScript("OnEnterPressed", go)
        eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
        eb:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
        eb:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
        local add = Button(o, "Add", 60, 22, go)
        add:SetPoint("LEFT", eb, "RIGHT", 6, 0)
        local tb = Button(o, targetText, 130, 22, onTarget)
        tb:SetPoint("LEFT", add, "RIGHT", 6, 0)
        y = y - 28
    end
    heading("NAMEPLATE ICONS")
    check("Class icon over enemy players", "on their nameplates · works without the list",
        function() return db().plateIcons == true end, function(v) db().plateIcons = v; ns.UpdatePlates() end)
    check("Class icon over friendly players", "needs friendly nameplates (Shift+V)",
        function() return db().plateFriendly == true end, function(v) db().plateFriendly = v; ns.UpdatePlates() end)
    check("Healer mark", "a green + on proven healers, on nameplates and in the list",
        function() return db().plateHealer ~= false end, function(v) db().plateHealer = v; ns.UpdatePlates() end)
    check("KOS mark", "a red ring and a skull on KOS players and guilds",
        function() return db().plateKOS ~= false end, function(v) db().plateKOS = v; ns.UpdatePlates() end)
    -- the icon's size: [-] 22 [+]
    local sizeLab = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLab:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, y - 4)
    sizeLab:SetText("Icon size")
    local function setSize(v)
        db().plateSize = math.max(12, math.min(40, v))
        o.sizeVal:SetText(ns.PlateSize())
        ns.UpdatePlates()
    end
    local sminus = FlatButton(o, "-", 22, 20, function() setSize(ns.PlateSize() - 2) end)
    sminus:SetPoint("TOPLEFT", o, "TOPLEFT", L + 150, y - 1)
    o.sizeVal = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.sizeVal:SetPoint("LEFT", sminus, "RIGHT", 6, 0)
    o.sizeVal:SetWidth(22)
    local splus = FlatButton(o, "+", 22, 20, function() setSize(ns.PlateSize() + 2) end)
    splus:SetPoint("LEFT", o.sizeVal, "RIGHT", 6, 0)
    local sizeHint = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sizeHint:SetPoint("LEFT", splus, "RIGHT", 8, 0)
    sizeHint:SetText("12 – 40 · normal 22")
    y = y - 28
    y = y - 10
    heading("KILL ON SIGHT")
    addRow("KOS player", "Name (e.g. Shixa Nightblade)", function(t)
        local key = ns.KeyFromName(t)
        if key then ns.SetKOS(key, true) end
    end, "Add target", function()
        local key, full
        if UnitExists("target") then key, full = ns.PlayerKey("target") end
        if key and UnitIsPlayer("target") then ns.EnemyRecord(key, full); ns.SetKOS(key, true)
        else ns.Print("Target a player first.") end
    end)
    addRow("KOS guild", "Guild name", function(t) ns.SetGuildKOS(t, true) end, "Target's guild", function()
        local g = UnitExists("target") and GetGuildInfo("target")
        if type(issecretvalue) == "function" and g and issecretvalue(g) then g = nil end
        if type(g) == "string" and g ~= "" then ns.SetGuildKOS(g, true) else ns.Print("Target a player in a guild first.") end
    end)
    -- the KOS guilds and players as small chips with an ×
    local chips, CH, CW = {}, 20, 180
    local chipTop = y
    local function chip(i)
        if chips[i] then return chips[i] end
        local c = CreateFrame("Button", nil, o)
        c:SetSize(CW, CH - 2)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        c:SetPoint("TOPLEFT", o, "TOPLEFT", L + col * (CW + 6), chipTop - row * CH)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.16, 0.06, 0.06, 0.95)
        local edge = c:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(2)
        edge:SetColorTexture(1, 0.25, 0.25, 1)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.text:SetPoint("LEFT", c, "LEFT", 7, 0)
        c.text:SetPoint("RIGHT", c, "RIGHT", -18, 0)
        c.text:SetJustifyH("LEFT")
        c.text:SetWordWrap(false)
        c.del = CreateFrame("Button", nil, c)
        c.del:SetSize(10, 10)
        c.del:SetPoint("RIGHT", c, "RIGHT", -5, 0)
        c.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        c.del:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
        c.del:SetScript("OnClick", function() if c.remove then c.remove() end end)
        chips[i] = c
        return c
    end
    local CHIP_MAX = 18
    local kosEmpty = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    kosEmpty:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, chipTop - 4)
    kosEmpty:SetText("No KOS yet – right-click a player in the Nearby list, or add one above.")
    local function RefreshKOS()
        local items = {}
        local guilds = {}
        for _, g in pairs(db().kosGuilds) do guilds[#guilds + 1] = g end
        table.sort(guilds)
        for _, g in ipairs(guilds) do
            items[#items + 1] = { "|cffff8080Guild|r <" .. g .. ">", function() ns.SetGuildKOS(g, false) end }
        end
        local players = {}
        for key, r in pairs(db().enemies) do if r.kos then players[#players + 1] = { key, r.name or key } end end
        table.sort(players, function(a, b) return a[2] < b[2] end)
        for _, p in ipairs(players) do
            items[#items + 1] = { p[2], function() ns.SetKOS(p[1], false) end }
        end
        local more = #items - CHIP_MAX
        for i = 1, CHIP_MAX do
            local it = items[i]
            if it then
                local c = chip(i)
                if i == CHIP_MAX and more > 0 then
                    c.text:SetText("|cffaaaaaa+" .. (more + 1) .. " more – see History|r")
                    c.remove = nil
                    c.del:Hide()
                else
                    c.text:SetText(it[1])
                    c.remove = function() it[2](); RefreshKOS() end
                    c.del:Show()
                end
                c:Show()
            elseif chips[i] then
                chips[i]:Hide()
            end
        end
        kosEmpty:SetShown(#items == 0)
    end
    ns.RefreshKOSChips = function() if page:IsShown() then RefreshKOS() end end
    y = chipTop - math.ceil(CHIP_MAX / 3) * CH - 12

    -- WANTED: bounties shared with the guild and friends
    y = y - 6
    heading("WANTED – BOUNTIES")
    check("Share with my guild", "send and get bounties in guild",
        function() return db().wantedGuild ~= false end, function(v) db().wantedGuild = v end)
    check("Share with my friends", "online friends who run WatchX",
        function() return db().wantedFriends ~= false end, function(v) db().wantedFriends = v end)
    check("Card + sound when one shows up", nil,
        function() return db().wantedAlert ~= false end, function(v) db().wantedAlert = v end)
    addRow("Bounty", "Name: 50g note", function(t)
        local name, rest = t:match("^([^:]+):%s*(.*)$")
        name = ns.Trim(name or t)
        local reward, note = (rest or ""):match("^(%d+%s*[gGsS]%S*)%s*(.*)$")
        ns.SetWanted(ns.KeyFromName(name), name, reward, reward and note or rest)
    end, "Bounty on target", function()
        local key, full
        if UnitExists("target") and UnitIsPlayer("target") then key, full = ns.PlayerKey("target") end
        if not key then ns.Print("Target a player first.") return end
        ns.EnemyRecord(key, full)
        ns.ShowBounty(key, full)
    end)
    local wantedList = Button(o, "Wanted list...", 110, 22, function() ns.ShowHistory("wanted") end)
    wantedList:SetPoint("TOPLEFT", o, "TOPLEFT", L + W - 110, y)
    local wantedHelp = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wantedHelp:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, y - 4)
    wantedHelp:SetWidth(W - 130)
    wantedHelp:SetJustifyH("LEFT")
    wantedHelp:SetText("A kill by you or your group claims it, and everyone hears who did. Pay the gold by hand.")
    y = y - 34

    -- avoid list: a mark on the same players (and the same notes) as KOS – any player, not just enemies
    y = y - 6
    heading("AVOID LIST")
    check("Warn when they invite you or are in your group", "mid-screen + sound",
        function() return db().avoidGroup ~= false end, function(v) db().avoidGroup = v end)
    check("Mark their chat lines", "a red [Avoid] in front: say, yell, whispers, channels, group, guild",
        function() return db().avoidChat ~= false end, function(v) db().avoidChat = v end)
    addRow("Avoid player", "Name: note (Bob Smith: ninja looter)", function(t)
        local name, note = t:match("^([^:]+):%s*(.*)$")
        ns.SetAvoid(name or t, true, note)
        if ns.RefreshAvoidCount then ns.RefreshAvoidCount() end
    end, "Add target", function()
        local key, full
        if UnitExists("target") and UnitIsPlayer("target") then key, full = ns.PlayerKey("target") end
        if not key then ns.Print("Target a player first.") return end
        ns.EnemyRecord(key, full)
        ns.SetAvoid(key, true)
        StaticPopup_Show("WATCHX_NOTE", full, nil, key)   -- type the note right away
        if ns.RefreshAvoidCount then ns.RefreshAvoidCount() end
    end)
    local avoidCount = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    avoidCount:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, y - 4)
    local avoidList = Button(o, "Avoid list...", 110, 22, function() ns.ShowHistory("avoid") end)
    avoidList:SetPoint("TOPLEFT", o, "TOPLEFT", L + W - 110, y)
    ns.RefreshAvoidCount = function()
        local n = 0
        for _, r in pairs(db().enemies) do if r.avoid then n = n + 1 end end
        avoidCount:SetText(n == 0 and "Nobody yet – right-click a player in the Nearby list, or add one above."
            or (n .. (n == 1 and " player" or " players") .. " on your avoid list. Their notes are the same notes as in History."))
    end
    y = y - 34

    local help = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOPLEFT", o, "TOPLEFT", L, y)
    help:SetWidth(W)
    help:SetJustifyH("LEFT")
    help:SetSpacing(4)
    help:SetText(table.concat({
        "|cffffd100HOW IT WORKS|r",
        "|cffaaaaaa•|r  Every enemy player your nameplates, target or mouseover show is listed, newest first.",
        "|cffaaaaaa•|r  Bright row = near now (last 30 seconds). Dim row = seen in the last few minutes.",
        "|cffaaaaaa•|r  |cffffd100Click a row|r to target that player.  |cffff5050> you|r = has you targeted.",
        "|cffaaaaaa•|r  |cff40ff60+|r before a name = proven healer (see Nameplate icons below).",
        "|cffaaaaaa•|r  |cffd8a0ffSTEALTH|r = went into Stealth, Vanish, Prowl or Shadowmeld – and the warning pops up.",
        "|cffaaaaaa•|r  The warnings sit on top of the list: |cffd8a0ffStealthed player|r and |cffff5959Enemy player detected|r.",
        "|cffaaaaaa•|r  Needs |cffffd100enemy nameplates|r (key V). In dungeons and raids it's faded (or hidden, if ticked).",
        "|cffaaaaaa•|r  |cffffd100Right-click a row|r: KOS, avoid, KOS the guild, a note. |cffff3030KOS|r players get a red card.",
        "|cffaaaaaa•|r  |cffff8040Avoid|r = people you don't want to play with (any player): tooltip, group warning, [Avoid] in chat.",
        "|cffaaaaaa•|r  |cffffd100Nameplate icons|r: the class over each player, |cff40ff60+|r = proven healer, |cffff3030red ring + skull|r = KOS.",
        "|cffaaaaaa•|r  Friendly: their talents (inspected). Enemies: a healing-talent spell like Riptide or Wild Growth.",
        "|cffaaaaaa•|r  |cffffd100History|r: everyone you've seen, with kills, deaths, last seen and notes.",
        "|cffaaaaaa•|r  Nothing goes to your phone – that's the WatchX page (Any enemy player).",
        "",
        "|cff808080/wx nearby on · off · test|r",
    }, "\n"))

    page:SetScript("OnShow", function()
        for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end
        o.maxVal:SetText(ns.NearbyMax())
        o.keepVal:SetText(ns.NearbyKeepMin())
        o.sizeVal:SetText(ns.PlateSize())
        RefreshKOS()
        ns.RefreshAvoidCount()
    end)
    o:SetHeight(-y + 200)
    nearbyPage = page
    if settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutSubcategory, settingsCategory, page, "PvP")
        if ok and cat then nearbyCategory = cat end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
end

-- WatchX's own look: a dark card, a thin status-colored strip at the top, one row per mob with a
-- colored dot, small "ready" checks, and flat buttons with an accent edge.
local ROWS = 2 + #ns.PRESETS + ns.MAX_CUSTOM   -- mobs + the enemy-player and friendly-player rows
local GREEN, RED, ORANGE, GREY = { 0.25, 0.85, 0.40 }, { 1, 0.27, 0.27 }, { 1, 0.6, 0.2 }, { 0.45, 0.45, 0.45 }

local function Dot(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size or 7, size or 7)
    t:SetColorTexture(1, 1, 1, 1)
    if t.SetMask then pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    t.Paint = function(self, c) self:SetVertexColor(c[1], c[2], c[3], 1) end
    return t
end

local function BuildPanel()
    local p = CreateFrame("Frame", "WatchXPanel", UIParent)
    p:SetWidth(PANEL_W)
    p:SetFrameStrata("MEDIUM")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint(self, "panelPoint") end)
    LoadPoint(p, "panelPoint", { "CENTER", "CENTER", 320, 120 })
    p.title = Window(p, "WatchX", 170)
    p:Hide()
    tinsert(UISpecialFrames, "WatchXPanel")

    -- the strip at the top: green watching, red when something is up, orange when something is missing
    p.strip = p:CreateTexture(nil, "ARTWORK")
    p.strip:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -24)
    p.strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -24)
    p.strip:SetHeight(2)

    p.logo = p:CreateTexture(nil, "OVERLAY")
    p.logo:SetSize(16, 16)
    p.logo:SetPoint("RIGHT", p.title, "LEFT", -4, 0)
    p.logo:SetTexture(LOGO)

    CloseX(p)

    -- the status tag, right under the header plate
    p.tag = CreateFrame("Frame", nil, p)
    p.tag:SetHeight(16)
    p.tag:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -28)
    p.tag.bg = p.tag:CreateTexture(nil, "BACKGROUND")
    p.tag.bg:SetAllPoints()
    p.tag.text = p.tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.tag.text:SetPoint("CENTER", 0, 0)

    local y = -48
    p.rowsTop = y
    p.rows = {}
    for i = 1, ROWS do
        local hit = CreateFrame("Button", nil, p)
        hit:SetHeight(18)
        hit:SetPoint("TOPLEFT", p, "TOPLEFT", PAD - 4, y - (i - 1) * 19)
        hit:SetPoint("TOPRIGHT", p, "TOPRIGHT", -(PAD - 4), y - (i - 1) * 19)
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local lit = hit:CreateTexture(nil, "HIGHLIGHT")
        lit:SetAllPoints()
        lit:SetColorTexture(1, 1, 1, 0.06)
        hit.dot = Dot(hit)
        hit.dot:SetPoint("LEFT", hit, "LEFT", 6, 0)
        hit.name = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hit.name:SetPoint("LEFT", hit, "LEFT", 19, 0)
        hit.name:SetPoint("RIGHT", hit, "RIGHT", -96, 0)
        hit.name:SetJustifyH("LEFT")
        hit.name:SetWordWrap(false)
        hit.state = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hit.state:SetPoint("RIGHT", hit, "RIGHT", -22, 0)
        -- × at the right: removes the row (your own mobs), or switches it off (built-in ones, enemy players)
        hit.del = CreateFrame("Button", nil, hit)
        hit.del:SetSize(11, 11)
        hit.del:SetPoint("RIGHT", hit, "RIGHT", -5, 0)
        hit.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        hit.del:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
        local dt = hit.del:GetNormalTexture()
        if dt then dt:SetVertexColor(0.55, 0.55, 0.55) end
        hit.del:SetScript("OnClick", function()
            if hit.enemy then ns.SetEnemyPlayers(false)
            elseif hit.friend then ns.SetFriendlyPlayers(false)
            elseif hit.near then ns.SetNearby(false)
            elseif hit.mob and hit.mob.preset then ns.SetWatched(hit.mob.name, false)
            elseif hit.mob then ns.RemoveCustom(hit.mob.name) end
        end)
        hit.del:SetScript("OnEnter", function(self)
            Tip(self, (hit.mob and hit.mob.preset or hit.enemy or hit.friend or hit.near) and "Switch off" or "Remove",
                hit.enemy and "Stop alerting on enemy players."
                    or hit.friend and "Stop alerting on friendly players."
                    or hit.near and "Hide the Nearby list." or hit.mob and hit.mob.preset
                    and ("Stop watching " .. hit.mob.name .. " (built in – click the row to switch it on again).")
                    or hit.mob and ("Remove " .. hit.mob.name .. " from the list.") or nil)
        end)
        hit.del:SetScript("OnLeave", GameTooltip_Hide)
        hit.state:SetWidth(92)
        hit.state:SetJustifyH("RIGHT")
        hit.state:SetWordWrap(false)
        hit:SetScript("OnClick", function(self, button)
            if self.enemy then ns.SetEnemyPlayers(not db().enemyPlayers) return end
            if self.friend then ns.SetFriendlyPlayers(not db().friendlyPlayers) return end
            if self.near then ns.SetNearby(not db().nearby) return end
            local mob = self.mob
            if not mob then return end
            if IsShiftKeyDown() then
                StaticPopup_Show("WATCHX_RESPAWN", mob.name, nil, mob.name)
            elseif button == "RightButton" then
                if not mob.preset then StaticPopup_Show("WATCHX_REMOVE", mob.name, nil, mob.name) end
            else
                ns.SetWatched(mob.name, not mob.enabled)
            end
        end)
        hit:SetScript("OnEnter", function(self)
            if self.near then
                Tip(self, "Nearby enemies", "A list of the enemy players around you, like Spy – click one to "
                    .. "target it. A player going into stealth pops up a warning. In game only.",
                    " ", "|cffffd100Click:|r on/off", "|cffffd100See an example:|r /wx nearby test")
                return
            end
            if self.friend then
                local last = ns.lastFriend
                Tip(self, "Any friendly player", "An alert when a friendly player shows up – not in instances, "
                    .. "cities or inns, and not your group. Needs friendly nameplates (Shift+V).",
                    last and ("Last: " .. last.name .. ", " .. ns.Fmt(time() - last.at) .. " ago") or nil,
                    " ", "|cffffd100Click:|r on/off")
                return
            end
            if self.enemy then
                local last = ns.lastEnemy
                Tip(self, "Any enemy player", "An alert when a hostile player shows up (not in instances).",
                    last and ("Last: " .. last.name .. ", " .. ns.Fmt(time() - last.at) .. " ago") or nil,
                    " ", "|cffffd100Click:|r on/off")
                return
            end
            local mob = self.mob
            if not mob then return end
            local m = ns.MobState(mob.name)
            local _, short, detail = ns.GetMobStatus(mob.name)
            local est, how = ns.EstimatedRespawn(mob.name)
            Tip(self, mob.name .. (mob.note and ("  |cffaaaaaa(" .. mob.note .. ")|r") or ""),
                short .. (detail ~= "" and (" · " .. detail) or ""),
                "Kills seen: " .. #m.kills .. " · Respawn: " .. (est and (ns.Fmt(est) .. " (" .. how .. ")") or "not known yet"),
                " ", "|cffffd100Click:|r watch on/off", "|cffffd100Shift-click:|r set respawn time",
                "|cffffd100×:|r " .. (mob.preset and "switch off" or "remove"))
        end)
        hit:SetScript("OnLeave", GameTooltip_Hide)
        p.rows[i] = hit
    end

    -- everything under the rows moves with the number of rows
    local low = CreateFrame("Frame", nil, p)
    low:SetPoint("LEFT", p, "LEFT", 0, 0)
    low:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    p.low = low
    local ly = -2

    local add = CreateFrame("Button", nil, low)
    add:SetHeight(16)
    add:SetPoint("TOPLEFT", low, "TOPLEFT", PAD + 2, ly)
    add:SetNormalFontObject("GameFontNormalSmall")
    add:SetHighlightFontObject("GameFontHighlightSmall")
    add:SetText("+ Watch your target")
    local afs = add:GetFontString()
    if afs then afs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3]); add:SetWidth((afs:GetStringWidth() or 110) + 4) else add:SetWidth(120) end
    add:SetScript("OnClick", function() ns.AddTarget() end)
    add:SetScript("OnEnter", function(self) Tip(self, "Watch your target", "Target a rare mob or a player first, then click.") end)
    add:SetScript("OnLeave", GameTooltip_Hide)
    -- the active profile, at the right: click to switch
    local prof = CreateFrame("Button", nil, low)
    prof:SetHeight(16)
    prof:SetPoint("TOPRIGHT", low, "TOPRIGHT", -(PAD + 2), ly)
    prof:SetNormalFontObject("GameFontHighlightSmall")
    prof:SetHighlightFontObject("GameFontNormalSmall")
    prof:SetText("Profile")
    prof:SetScript("OnClick", function(self) ns.ToggleProfileMenu(self) end)
    prof:SetScript("OnEnter", function(self)
        Tip(self, "Profile", "Click to switch profile (e.g. Camping, Leveling, PvP) or make a new one.")
    end)
    prof:SetScript("OnLeave", GameTooltip_Hide)
    profileLabels[#profileLabels + 1] = function(name)
        prof:SetText("|cff808080Profile:|r " .. name)
        local fs = prof:GetFontString()
        prof:SetWidth(math.min(120, ((fs and fs:GetStringWidth()) or 80) + 4))
    end
    ly = ly - 24

    local line = low:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", low, "TOPLEFT", PAD, ly)
    line:SetPoint("TOPRIGHT", low, "TOPRIGHT", -PAD, ly)
    ly = ly - 8

    -- three small "ready" checks: a dot and a word each, with a tooltip
    p.ready = {}
    local prev
    for i, item in ipairs({ { "plates", "Nameplates" }, { "phone", "Phone" }, { "afk", "AFK warning" } }) do
        local b = CreateFrame("Button", nil, low)
        b:SetSize(70, 16)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 14, 0) else b:SetPoint("TOPLEFT", low, "TOPLEFT", PAD, ly) end
        prev = b
        b.dot = Dot(b, 6)
        b.dot:SetPoint("LEFT", b, "LEFT", 2, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", b, "LEFT", 12, 0)
        b.text:SetText(item[2])
        b:SetWidth(12 + math.ceil(b.text:GetStringWidth() or 60))
        b.key = item[1]
        b:SetScript("OnEnter", function(self) if self.tip then Tip(self, item[2], self.tip) end end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", function(self) if self.key ~= "plates" then ns.OpenAlertSettings() end end)
        p.ready[item[1]] = b
    end
    ly = ly - 22

    p.note = low:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.note:SetPoint("TOPLEFT", low, "TOPLEFT", PAD, ly)
    p.note:SetPoint("TOPRIGHT", low, "TOPRIGHT", -PAD, ly)
    p.note:SetJustifyH("LEFT")
    p.note:SetJustifyV("TOP")
    p.note:SetWordWrap(true)
    p.noteY = ly

    p.buttons = CreateFrame("Frame", nil, low)
    p.buttons:SetHeight(22)
    p.buttons:SetPoint("LEFT", low, "LEFT", 0, 0)
    p.buttons:SetPoint("RIGHT", low, "RIGHT", 0, 0)
    local bw = (PANEL_W - PAD * 2 - 12) / 3
    local test = FlatButton(p.buttons, "Send test", bw, 22, function() ns.SendTest() end)
    test:SetPoint("TOPLEFT", p.buttons, "TOPLEFT", PAD, 0)
    local set = FlatButton(p.buttons, "Settings", bw, 22, function() ns.OpenAlertSettings() end)
    set:SetPoint("LEFT", test, "RIGHT", 6, 0)
    p.lock = FlatButton(p.buttons, "Unlock", bw, 22, function() ns.ToggleUnlock() end)
    p.lock:SetPoint("LEFT", set, "RIGHT", 6, 0)
    p.lock:SetScript("OnEnter", function(self)
        Tip(self, "Unlock / Lock", "Unlock shows the mini bar and the alert so you can drag them. Lock keeps them there.")
    end)
    p.lock:SetScript("OnLeave", GameTooltip_Hide)

    p:SetScript("OnShow", function() ns.RefreshUI() end)
    return p
end

local function Paint(row, color, name, state, removable)
    row.del:SetShown(removable and true or false)
    row.dot:Paint(color)
    row.name:SetText(name)
    row.state:SetText(state)
end

local function RefreshPanel()
    local p, d = panel, db()
    local list = ns.GetMobList()
    local shown, anyUp = 0, false
    for i, row in ipairs(p.rows) do
        local mob = list[i]
        row.mob, row.enemy, row.friend, row.near = mob, nil, nil, nil
        if mob then
            shown = i
            local state, short, detail, left = ns.GetMobStatus(mob.name)
            if not mob.enabled then
                Paint(row, GREY, "|cff808080" .. mob.name .. "|r", "|cff606060off|r")
            elseif state == "up" then
                anyUp = true
                Paint(row, RED, mob.name, (ns.IsPlayerEntry(mob.name) and "|cff66ccffFOUND|r" or "|cffff4545UP|r")
                    .. " |cffaaaaaa" .. detail:gsub("^seen ", ""):gsub(" ago$", "") .. "|r", true)
            elseif state == "dead" then
                Paint(row, ORANGE, mob.name, left and (left > 0 and ("|cffaaaaaarespawn ~" .. ns.Fmt(left) .. "|r")
                    or "|cffffd100due|r") or "|cffaaaaaadead|r", true)
            else
                Paint(row, GREEN, mob.name, "|cffaaaaaawatching|r", true)
            end
        end
        row:SetShown(mob ~= nil)
    end
    -- the enemy-player row, under the mobs
    local er = p.rows[shown + 1]
    if er then
        er.mob, er.enemy, er.near = nil, true, nil
        local last = ns.lastEnemy
        if not d.enemyPlayers then
            Paint(er, GREY, "|cff808080Enemy players|r", "|cff606060off|r")
        elseif last and time() - last.at < 60 then
            anyUp = true
            Paint(er, RED, "Enemy players", "|cffff4545" .. last.name .. "|r", true)
        else
            Paint(er, GREEN, "Enemy players", "|cffaaaaaawatching|r", true)
        end
        er:Show()
        shown = shown + 1
    end
    -- the friendly-player row
    local fr = p.rows[shown + 1]
    if fr then
        fr.mob, fr.enemy, fr.friend, fr.near = nil, nil, true, nil
        local last = ns.lastFriend
        if not d.friendlyPlayers then
            Paint(fr, GREY, "|cff808080Friendly players|r", "|cff606060off|r")
        elseif last and time() - last.at < 60 then
            anyUp = true
            Paint(fr, RED, "Friendly players", "|cff66ccff" .. last.name .. "|r", true)
        elseif ns.FriendPlatesMissing() then
            Paint(fr, ORANGE, "Friendly players", "|cffff9933Shift+V|r", true)
        else
            Paint(fr, GREEN, "Friendly players", "|cffaaaaaawatching|r", true)
        end
        fr:Show()
        shown = shown + 1
    end
    for i = shown + 1, #p.rows do p.rows[i]:Hide() end

    -- ready checks
    local plates = GetCVar("nameplateShowEnemies") == "1"
    local phoneSet = d.ntfyUrl ~= "" or d.discordWebhook ~= ""
    local instant = d.instant ~= false and d.instantOK ~= false
    local r = p.ready
    r.plates.dot:Paint(plates and GREEN or RED)
    r.plates.tip = plates and ("On – WatchX sees mobs within " .. (GetCVar("nameplateMaxDistance") or "41") .. " yards.")
        or "Enemy nameplates are OFF – press V. Nothing can be spotted without them."
    local phoneOk = d.whisper and phoneSet and (instant or d.chatlogOn == true)
    r.phone.dot:Paint(phoneOk and (d.instantOK and GREEN or { 1, 0.82, 0 }) or RED)
    r.phone.tip = not d.whisper and "Phone alerts are off (Settings)."
        or not phoneSet and "Not set up yet – click to open Settings and paste your ntfy or Discord link."
        or not instant and (d.chatlogOn == true and "Slow alerts through the chat log (instant alerts don't work here)."
            or "Instant alerts don't work here – turn on the chat log (yellow bar).")
        or d.instantOK and "Instant alerts with a screenshot – working."
        or "Set up – press Send test to check it reaches your phone."
    local afkLeft = ns.AfkStatus and ns.AfkStatus()
    r.afk.dot:Paint(d.afkWarn and (afkLeft and { 1, 0.82, 0 } or GREEN) or GREY)
    r.afk.tip = not d.afkWarn and "Off (Settings)."
        or afkLeft and ("You are AFK – logged out in about " .. ns.Fmt(math.max(afkLeft, 0)) .. ".")
        or "Your phone is told 5 minutes before an AFK logout, and when you're logged out."

    -- one short note, only when something needs doing
    local note
    if not plates and ns.NeedsEnemyPlates() then
        note = "|cffff9933Enemy nameplates are off.|r Press V."
    elseif ns.FriendPlatesMissing() then
        note = "|cffff9933Friendly nameplates are off.|r Press Shift+V."
    elseif not phoneSet then
        note = "|cffff9933Phone alerts aren't set up.|r Open Settings and paste your ntfy or Discord link."
    elseif not instant and d.chatlogOn ~= true then
        note = "|cffff9933Turn on the chat log|r with the yellow bar – instant alerts don't work here."
    elseif afkLeft and d.afkWarn then
        note = "|cffffd100You are AFK|r – logged out in about " .. ns.Fmt(math.max(afkLeft, 0)) .. "."
    end
    p.note:SetText(note or "")
    p.note:SetShown(note ~= nil)
    local noteH = note and (math.ceil(p.note:GetStringHeight() or 12) + 8) or 0
    p.buttons:ClearAllPoints()
    p.buttons:SetPoint("TOPLEFT", p.low, "TOPLEFT", 0, p.noteY - noteH)
    p.buttons:SetPoint("TOPRIGHT", p.low, "TOPRIGHT", 0, p.noteY - noteH)

    local lowTop = p.rowsTop - shown * 19 - 6
    p.low:ClearAllPoints()
    p.low:SetPoint("TOPLEFT", p, "TOPLEFT", 0, lowTop)
    p.low:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, lowTop)
    local lowH = -(p.noteY - noteH) + 22 + PAD
    p.low:SetHeight(lowH)
    p:SetHeight(-lowTop + lowH)

    -- the strip and the tag: the most important state
    local c, tag
    if anyUp then c, tag = RED, "UP!"
    elseif (not plates and ns.NeedsEnemyPlates()) or ns.FriendPlatesMissing() or not phoneOk then
        c, tag = ORANGE, "CHECK"
    elseif ns.IsWatchingAnything() then c, tag = ACCENT, "WATCHING"
    else c, tag = GREY, "IDLE" end
    p.strip:SetColorTexture(c[1], c[2], c[3], 0.9)
    p.tag.text:SetText(tag)
    p.tag.text:SetTextColor(c[1], c[2], c[3])
    p.tag.bg:SetColorTexture(c[1], c[2], c[3], 0.14)
    p.tag:SetWidth((p.tag.text:GetStringWidth() or 50) + 12)
end

function ns.TogglePanel()
    if not panel then return end
    panel:SetShown(not panel:IsShown())
end

-- ---------------------------------------------------------------- mini bar
-- One line per watched mob (and enemy players), stacked. "Only on alerts" hides the quiet lines, and
-- the whole bar when nothing is going on – the big target bar still pops up in the same spot.
-- The bar is never really hidden (only see-through), so its spot is always known for the other bars.

local LINE_H, MINI_MAX = 18, 8
local targetBtn, targetName, targetDismissed = nil, nil, {}
local moving = false
local function TargetShown() return targetBtn and targetBtn:IsShown() end
-- The big alert pops up in the mini bar's spot (the bar steps aside), or in a spot of its own.
local function OwnSpot() return db().alertSame == false end
local alertSpot   -- the stand-in shown while moving the alert's own spot
-- Sizes: while unlocked, drag a bar's edges (right: width, bottom: size, corner: both) or scroll over
-- it. In the mini bar's spot the alert has the mini bar's size.
local function ClampScale(v) return math.floor(math.min(2.5, math.max(0.6, v or 1)) * 100 + 0.5) / 100 end
local function MiniScale() return ClampScale(db().miniScale) end
local function AlertScale() return OwnSpot() and ClampScale(db().alertScale) or MiniScale() end
local function AlertWidth() return (OwnSpot() and db().alertWidth or db().miniWidth) or 0 end
local function Pct(sc) return math.floor(sc * 100 + 0.5) .. "%" end
-- The mini bar's centre x, top and bottom in UIParent units (it may be scaled).
local function MiniRect()
    if not mini then return end
    local x, top, bottom = mini:GetCenter(), mini:GetTop(), mini:GetBottom()
    if not (x and top) then return end
    local sc = mini:GetScale() or 1
    return x * sc, top * sc, (bottom or (top - MINI_H)) * sc
end
-- A new size, keeping the top centre where it is.
local function SetScaleKeepTop(f, new)
    local old = f:GetScale() or 1
    local x, top = f:GetCenter(), f:GetTop()
    f:SetScale(new)
    if x and top then
        f:ClearAllPoints()
        f:SetPoint("TOP", UIParent, "BOTTOMLEFT", x * old / new, top * old / new)
    end
end
-- One wheel step: 10 % bigger or smaller.
local function Rescale(f, key, delta)
    local new = ClampScale((f:GetScale() or 1) + (delta > 0 and 0.1 or -0.1))
    db()[key] = new
    SetScaleKeepTop(f, new)
    return new
end

local function CursorUI()
    local x, y = GetCursorPosition()
    local es = UIParent:GetEffectiveScale() or 1
    return x / es, y / es
end

-- Grab handles on the right edge, the bottom edge and the corner. apply(f, state, cx, cy) runs while
-- the mouse is held; finish(f) when it's let go.
local GRIP = 7
local function AddGrips(f, apply, finish)
    f.grips = {}
    for _, mode in ipairs({ "R", "B", "BR" }) do
        local g = CreateFrame("Frame", nil, f)
        g:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
        local t = g:CreateTexture(nil, "OVERLAY")
        if mode == "R" then
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", -1, -3); t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -1, 0)
            t:SetWidth(2)
        elseif mode == "B" then
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 3, 1); t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 1)
            t:SetHeight(2)
        else
            t:SetAllPoints()
        end
        if mode == "R" then
            g:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, GRIP * 2)
            g:SetWidth(GRIP)
        elseif mode == "B" then
            g:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
            g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -GRIP * 2, 0)
            g:SetHeight(GRIP)
        else
            g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
            g:SetSize(GRIP * 2, GRIP * 2)
        end
        if mode == "BR" then
            t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        else
            t:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        end
        t:SetAlpha(mode == "BR" and 0.9 or 0.7)
        g:EnableMouse(true)
        g:SetScript("OnEnter", function() t:SetAlpha(1) end)
        g:SetScript("OnLeave", function() if not f.sizing then t:SetAlpha(mode == "BR" and 0.9 or 0.7) end end)
        g:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local sc = f:GetScale() or 1
            local left, top = f:GetLeft(), f:GetTop()
            if not (left and top) then return end
            local _, cy = CursorUI()
            f.sizing = { mode = mode, left = left * sc, top = top * sc, scale = sc, y = cy }
            g:SetScript("OnUpdate", function() if f.sizing then apply(f, f.sizing, CursorUI()) end end)
        end)
        g:SetScript("OnMouseUp", function()
            g:SetScript("OnUpdate", nil)
            if not f.sizing then return end
            f.sizing = nil
            t:SetAlpha(mode == "BR" and 0.9 or 0.7)
            finish(f)
        end)
        g:Hide()
        f.grips[#f.grips + 1] = g
    end
end
local function ShowGrips(f, show)
    for _, g in ipairs(f and f.grips or {}) do g:SetShown(show) end
end

-- While sizing: the right edge and the corner set the width (the text stays as it is); the bottom edge the
-- text size, gently (150 px of dragging = 100 %), so a small slip doesn't shrink it. The top-left corner stays put.
local function SizeTo(f, st, cx, cy, naturalH, scaleKey, widthKey)
    local sc = f:GetScale() or 1
    if st.mode == "B" then sc = ClampScale((st.scale or sc) + ((st.y or cy) - cy) / 150) end
    db()[scaleKey] = sc
    if st.mode ~= "B" then db()[widthKey] = math.max(120, math.floor((cx - st.left) / sc + 0.5)) end
    f:SetScale(sc)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.left / sc, st.top / sc)
end

-- A small label above a bar while unlocked (not part of the bar, so it doesn't grow with it).
local function MakeLabel(name)
    local l = CreateFrame("Frame", name, UIParent)
    l:SetFrameStrata("DIALOG")
    l:SetHeight(18)
    local bg = l:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.text:SetPoint("TOPLEFT", l, "TOPLEFT", 6, -3)
    l.text:SetJustifyH("LEFT")
    l.text:SetWordWrap(true)
    l.text:SetSpacing(2)
    -- never wider than the bar it sits on: a long hint wraps onto more lines instead
    l.Set = function(self, anchor, text)
        local barW = (anchor:GetWidth() or 200) * (anchor:GetEffectiveScale() or 1) / (self:GetEffectiveScale() or 1)
        self.text:SetWidth(2000)
        self.text:SetText(text)
        local w = math.min(self.text:GetStringWidth() + 2, math.max(120, barW - 12))
        self.text:SetWidth(w)
        self:SetWidth(w + 12)
        self:SetHeight((self.text:GetStringHeight() or 12) + 6)
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 3)
        self:Show()
    end
    l:Hide()
    return l
end
local miniLabel, alertLabel

local function MiniLines(all)
    local d = db()
    local quiet = d.miniQuiet and not all
    local lines = {}
    local function add(name, state, news)
        if news or not quiet then lines[#lines + 1] = { name, state or "" } end
    end
    local afkLeft = d.afkWarn and ns.AfkStatus and ns.AfkStatus()
    if afkLeft and afkLeft < 10 * 60 then
        add("|cffffd100AFK|r", "logout in ~" .. ns.Fmt(math.max(afkLeft, 0)) .. "  |cffaaaaaa– move!|r", true)
    end
    if GetCVar("nameplateShowEnemies") ~= "1" and ns.NeedsEnemyPlates() then
        add("|cffff6060Nameplates OFF|r", "|cffaaaaaapress V|r", true)
    end
    if ns.FriendPlatesMissing() then
        add("|cffff6060Friendly nameplates OFF|r", "|cffaaaaaaShift+V|r", true)
    end
    for _, mob in ipairs(ns.GetMobList()) do
        if mob.enabled then
            local state, short, _, left = ns.GetMobStatus(mob.name)
            if state == "up" then
                add(mob.name, ns.IsPlayerEntry(mob.name) and "|cff66ccffFOUND|r" or short, true)
            elseif left then
                add(mob.name, left > 0 and ("|cffaaaaaarespawn ~|r" .. ns.Fmt(left)) or "|cffffd100due|r")
            else
                add(mob.name, short)
            end
        end
    end
    if d.enemyPlayers then
        local last = ns.lastEnemy
        if last and time() - last.at < 30 then
            add("|cffff4040ENEMY|r  " .. last.name, "", true)
        else
            add("Enemy players", "|cff808080watching|r")
        end
    end
    if d.friendlyPlayers then
        local last = ns.lastFriend
        if last and time() - last.at < 30 then
            add("|cff66ccffFRIEND|r  " .. last.name, "", true)
        else
            add("Friendly players", "|cff808080watching|r")
        end
    end
    -- nothing watched: a hint to pick something, or (auto-hide) nothing at all – unlocked it still shows
    if #lines == 0 and not quiet and (all or not d.hideIdle) then
        add("|cff808080Nothing watched – click to pick|r")
    end
    if #lines > MINI_MAX then
        local more = #lines - MINI_MAX + 1
        for i = #lines, MINI_MAX, -1 do lines[i] = nil end
        lines[MINI_MAX] = { "|cff808080+" .. more .. " more – click for the panel|r", "" }
    end
    return lines
end

local RefreshMini
local function BuildMini()
    local m = CreateFrame("Button", "WatchXMini", UIParent)
    m:SetFrameStrata("MEDIUM")
    m:SetClampedToScreen(true)
    m:SetMovable(true)
    m:SetHeight(MINI_H)
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    m:SetScale(MiniScale())
    LoadPoint(m, "miniPoint", { "TOP", "TOP", 0, -120 })
    m:SetScript("OnMouseWheel", function(self, delta)
        if not moving then return end
        Rescale(self, "miniScale", delta)
        SavePoint(self, "miniPoint")
        RefreshMini()
        ns.UpdateChatLogPrompt()
    end)
    Flat(m, 0.85)
    local lit = m:CreateTexture(nil, "HIGHLIGHT")
    lit:SetPoint("TOPLEFT", 3, -3); lit:SetPoint("BOTTOMRIGHT", -3, 3)
    lit:SetColorTexture(1, 1, 1, 0.06)
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetSize(20, 20)
    m.icon:SetPoint("TOPLEFT", m, "TOPLEFT", 5, -3)
    m.icon:SetTexture(LOGO)
    m.rows = {}
    for i = 1, MINI_MAX do
        local name = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("TOPLEFT", m, "TOPLEFT", 31, -4 - (i - 1) * LINE_H)
        name:SetHeight(LINE_H)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local state = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        state:SetHeight(LINE_H)
        state:SetJustifyH("RIGHT")
        state:SetWordWrap(false)
        m.rows[i] = { name = name, state = state }
    end
    m.text = m.rows[1].name
    m.count = 0
    m.naturalH = MINI_H
    AddGrips(m, function(self, st, cx, cy)
        SizeTo(self, st, cx, cy, self.naturalH, "miniScale", "miniWidth")
        RefreshMini()
    end, function(self)
        SavePoint(self, "miniPoint")
        ns.UpdateTargetButton()
        ns.UpdateChatLogPrompt()
    end)
    m:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        SavePoint(self, "miniPoint")
        ns.UpdateTargetButton()
        ns.UpdateChatLogPrompt()
    end)
    m:SetScript("OnClick", function(_, button)
        if moving then   -- unlocked: dragging only; right-click puts the size back
            if button == "RightButton" then
                db().miniScale, db().miniWidth = nil, nil
                SetScaleKeepTop(mini, 1)
                SavePoint(mini, "miniPoint")
                RefreshMini()
                ns.UpdateChatLogPrompt()
            end
            return
        end
        if button == "RightButton" then
            if IsShiftKeyDown() then ns.SetMiniShown(false) else ns.OpenSettings() end
        else
            ns.TogglePanel()
        end
    end)
    m:SetScript("OnEnter", function(self)
        if moving then return end
        Tip(self, "WatchX", "|cffffd100Click:|r panel", "|cffffd100Right-click:|r settings",
            "|cffffd100Shift-right-click:|r hide the mini bar", "|cffffd100Move it:|r Unlock in the panel")
    end)
    m:SetScript("OnLeave", GameTooltip_Hide)
    return m
end

-- With the Nearby list hanging under it, the mini bar counts as protected (a secure frame is anchored to
-- it): in combat it can't be resized, shown or get the mouse – only its text and alpha change then.
local function MiniFrozen()
    return InCombatLockdown() and ((mini.IsProtected and mini:IsProtected()) or mini.holdsSecure) and true or false
end

-- See-through (not hidden) when it has nothing to show, is switched off, or the big target bar is there.
local function ApplyMini()
    if not mini then return end
    local vis = moving or (db().show and mini.count > 0 and (OwnSpot() or not TargetShown()))
    mini.visible = vis and true or false
    mini:SetAlpha(vis and 1 or 0)
    if MiniFrozen() then return end
    if not mini:IsShown() then mini:Show() end
    mini:EnableMouse(vis and true or false)
end

function RefreshMini()
    local lines = MiniLines(moving)   -- unlocked: everything it can show, so the size is easy to judge
    local nameW, stateW = 0, 0
    for i, row in ipairs(mini.rows) do
        local l = lines[i]
        if l then
            row.name:SetText(l[1]); row.state:SetText(l[2])
            row.name:Show(); row.state:Show()
            nameW = math.max(nameW, row.name:GetStringWidth())
            if l[2] ~= "" then stateW = math.max(stateW, row.state:GetStringWidth()) end
        else
            row.name:SetText(""); row.state:SetText("")
            row.name:Hide(); row.state:Hide()
        end
    end
    for i, row in ipairs(mini.rows) do
        row.state:ClearAllPoints()
        row.state:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -12, -4 - (i - 1) * LINE_H)
    end
    mini.count = #lines
    mini.naturalH = math.max(MINI_H, 8 + #lines * LINE_H)
    if not MiniFrozen() then   -- in combat (when protected) the size waits; it's fixed right after
        -- the width you dragged it to wins (long text gets "..."); without one it fits the text and the Nearby list
        local w = db().miniWidth and math.max(120, db().miniWidth)
            or math.max(100, 31 + nameW + (stateW > 0 and (14 + stateW) or 0) + 12, ns.NearbyAttachWidth and ns.NearbyAttachWidth() or 0)
        mini:SetWidth(w)
        mini:SetHeight(mini.naturalH)
    end
    local roomW = (mini:GetWidth() or 200) - 31 - 12 - (stateW > 0 and (14 + stateW) or 0)
    for _, row in ipairs(mini.rows) do row.name:SetWidth(math.max(20, roomW)) end
    if moving then
        miniLabel = miniLabel or MakeLabel("WatchXMiniLabel")
        miniLabel:Set(mini, "|cffffd100Mini bar|r · drag to move · right edge: width · bottom edge: text size (" .. Pct(mini:GetScale() or 1)
            .. ") · right-click: reset size · Lock: top of the screen")
    elseif miniLabel then
        miniLabel:Hide()
    end
    ApplyMini()
    if ns.AttachNearby then ns.AttachNearby() end
end

function ns.SetMiniShown(show)
    db().show = show and true or false
    if not show then ns.Print("Mini bar hidden – /wx mini or Settings shows it again.") end
    ns.RefreshUI()
    ns.UpdateChatLogPrompt()
end

-- Where the alert goes when it has its own spot (UIParent coordinates: centre x, top).
local function AlertSpot()
    local p = db().alertPoint
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if type(p) == "table" and p.x and p.top then
        return math.min(math.max(p.x, 120), W - 120), math.min(math.max(p.top, TARGET_H), H)
    end
    return W / 2, H * 0.72
end

local function BuildAlertSpot()
    local f = CreateFrame("Button", "WatchXAlertSpot", UIParent)
    f:SetSize(240, TARGET_H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("RightButtonUp")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 3, -3); bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetColorTexture(0.50, 0.06, 0.06, 0.95)
    RedEdge(f)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", f, "LEFT", 9, 0)
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -5)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -2)
    hint:SetTextColor(1, 0.75, 0.75)
    hint:SetText("Click: target + skull")
    -- looks like the real thing, with the first watched name
    local function Place(self)
        local sample
        for _, mob in ipairs(ns.GetMobList()) do if mob.enabled then sample = mob.name; break end end
        self.text:SetText("|cffffd100UP|r  " .. (sample or "Example mob"))
        local sc = AlertScale()
        local x, top = AlertSpot()
        self:SetScale(sc)
        self:SetWidth(math.max(220, self.text:GetStringWidth() + 64, db().alertWidth or 0))
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "BOTTOMLEFT", x / sc, top / sc)
        alertLabel = alertLabel or MakeLabel("WatchXAlertLabel")
        alertLabel:Set(self, "|cffff6060Alert|r · drag to move · right edge: width · bottom edge: text size (" .. Pct(sc)
            .. ") · right-click: reset size")
    end
    f.Place = Place
    local function Remember(self)
        local x, top, sc = self:GetCenter(), self:GetTop(), self:GetScale() or 1
        if x and top then db().alertPoint = { x = x * sc, top = top * sc } end
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        Remember(self)
        Place(self)
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        Rescale(self, "alertScale", delta)
        Remember(self)
        Place(self)
    end)
    f:SetScript("OnClick", function(self)   -- right-click: size back to normal
        db().alertScale, db().alertWidth = nil, nil
        SetScaleKeepTop(self, 1)
        Remember(self)
        Place(self)
    end)
    AddGrips(f, function(self, st, cx, cy)
        SizeTo(self, st, cx, cy, TARGET_H, "alertScale", "alertWidth")
        self:SetWidth(math.max(220, self.text:GetStringWidth() + 64, db().alertWidth or 0))
        Remember(self)
        alertLabel:Set(self, "|cffff6060Alert|r · drag to move · right edge: width · bottom edge: text size (" .. Pct(self:GetScale() or 1)
            .. ") · right-click: reset size")
    end, function(self) Place(self) end)
    f:Hide()
    return f
end

-- Unlocked: the mini bar and the alert (when it has its own spot) show themselves and can be dragged,
-- until Lock. Always locked after a login or reload.
-- While unlocked: a small bar at the top of the screen with a Lock button, above everything (the options
-- window included), so you can always lock again – wherever you unlocked from.
local lockBar
local function LockBar()
    if lockBar then return lockBar end
    local f = CreateFrame("Frame", "WatchXLockBar", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(430, 34)
    f:SetPoint("TOP", UIParent, "TOP", 0, -70)
    Flat(f)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", f, "LEFT", 12, -1)
    text:SetText("|cffffd100WatchX unlocked|r – drag the bars, pull their edges")
    f.lock = Button(f, "Lock", 80, 22, function() ns.StopMove() end)
    f.lock:SetPoint("RIGHT", f, "RIGHT", -8, -1)
    f:Hide()
    lockBar = f
    return f
end

function ns.StartMove()
    if not mini then return end
    if InCombatLockdown() then ns.Print("Not in combat – unlock the bars when the fight is over.") return end
    moving = true
    if ns.ShowGrid then ns.ShowGrid(true) end
    mini:SetFrameStrata("DIALOG")
    mini:EnableMouseWheel(true)
    ShowGrips(mini, true)
    RefreshMini()
    if OwnSpot() then
        alertSpot = alertSpot or BuildAlertSpot()
        alertSpot:Show()
        alertSpot:EnableMouseWheel(true)
        ShowGrips(alertSpot, true)
        alertSpot:Place()
        ns.Print("Unlocked – drag the mini bar and the red alert, pull their edges to resize, then press Lock "
            .. "at the top of the screen (or /wx lock).")
    else
        ns.Print("Unlocked – drag the mini bar (the alert pops up there too, same size), pull its edges to "
            .. "resize, then press Lock at the top of the screen (or /wx lock).")
    end
    if panel then panel.lock:SetText("|cffffd100Lock|r") end
    LockBar():Show()
    ns.UpdateTargetButton()
    if ns.NearbyMove then ns.NearbyMove(true) end
    if ns.LevelMove then ns.LevelMove(true) end
end

function ns.ToggleUnlock()
    if moving then ns.StopMove() else ns.StartMove() end
end

function ns.StopMove()
    if not moving then return end
    moving = false
    if ns.ShowGrid then ns.ShowGrid(false) end
    mini:SetFrameStrata("MEDIUM")
    mini:EnableMouseWheel(false)   -- otherwise it eats camera zoom
    ShowGrips(mini, false)
    if miniLabel then miniLabel:Hide() end
    if alertLabel then alertLabel:Hide() end
    SavePoint(mini, "miniPoint")
    if alertSpot then alertSpot:Hide() end
    if panel then panel.lock:SetText("Unlock") end
    if lockBar then lockBar:Hide() end
    if ns.NearbyMove then ns.NearbyMove(false) end
    if ns.LevelMove then ns.LevelMove(false) end
    ns.Print("Locked.")
    ns.RefreshUI()
    ns.UpdateTargetButton()
    ns.UpdateChatLogPrompt()
end

-- ---------------------------------------------------------------- nearby enemies (like Spy)
-- A list of the enemy players around, newest first, each row in its class colour: bright while they
-- are near (seen in the last 30 s), dim for a few minutes after. Click a row to target that player.
-- Rows are secure buttons, so in combat they keep their player; newcomers get a free row and can be
-- clicked once combat ends. A stealth cast pops up a small warning.
local NB_ROWS, NB_ROW_H, NB_W = 20, 18, 270   -- rows made; how many show is a setting (nearbyMax)
local function NearbyMax() return math.max(3, math.min(NB_ROWS, tonumber(db().nearbyMax) or 10)) end
ns.NearbyMax, ns.NB_ROWS = NearbyMax, NB_ROWS
local nb, nbLabel, toast, toastLabel
local Attached
local function NearbyScale() return ClampScale(db().nearbyScale) end
local function NearbyWidth() return math.max(160, db().nearbyWidth or NB_W) end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.55, 0.55, 0.55
end
local function ClassName(class)
    if not class then return "" end
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    return n or (class:sub(1, 1) .. class:sub(2):lower())
end
ns.ClassColor, ns.ClassName = ClassColor, ClassName
local function Ago(sec)
    if sec < 60 then return sec .. "s" end
    return math.floor(sec / 60) .. "m"
end

-- History lines for a tooltip: KOS, kills, seen, note.
local function AgoLong(sec)
    if sec < 3600 then return math.max(1, math.floor(sec / 60)) .. " min" end
    if sec < 86400 then return math.floor(sec / 3600) .. " h" end
    return math.floor(sec / 86400) .. " d"
end
ns.AgoLong = AgoLong
function ns.AddEnemyHistoryLines(key)
    local r = ns.db.enemies[key]
    if not r then return end
    local e = ns.nearby[key]
    local kos, why = ns.IsKOS(key, e and e.first, r.guild)
    if kos then GameTooltip:AddLine(why == "guild" and "KOS (guild)" or "KOS – kill on sight", 1, 0.25, 0.25) end
    GameTooltip:AddLine("You killed: " .. (r.kills or 0) .. "   Killed you: " .. (r.deaths or 0), 1, 0.82, 0)
    GameTooltip:AddLine("Seen " .. (r.seen or 1) .. " time" .. ((r.seen or 1) == 1 and "" or "s")
        .. (r.firstSeen and (" · first " .. AgoLong(time() - r.firstSeen) .. " ago") or ""), 0.7, 0.7, 0.7)
    if r.avoid then GameTooltip:AddLine("Avoid – you don't play with this one", 1, 0.5, 0.25) end
    if r.note then GameTooltip:AddLine("Note: " .. r.note, 1, 1, 0.6, true) end
end

local function NearbyRowTip(self)
    local e = self.shownKey and ns.nearby[self.shownKey]
    if not e then return end
    local now = time()
    local r, g, b = ClassColor(e.class)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(e.name, r, g, b)
    GameTooltip:AddLine(((e.level and e.level > 0) and e.level or "??") .. " " .. (e.race and (e.race .. " ") or "")
        .. ClassName(e.class), 1, 1, 1)
    if e.guild then GameTooltip:AddLine("<" .. e.guild .. ">", 0.25, 1, 0.25) end
    GameTooltip:AddLine("Seen " .. Ago(now - e.last) .. " ago · first " .. Ago(now - e.firstSeen) .. " ago", 0.7, 0.7, 0.7)
    if e.stealth then GameTooltip:AddLine((e.stealthHow or "Stealth") .. " " .. Ago(now - e.stealth) .. " ago", 0.75, 0.5, 1) end
    if e.targetingMe and now - e.targetingMe < 30 then GameTooltip:AddLine("Had you targeted", 1, 0.3, 0.3) end
    local role, how = ns.Role(e.key)
    if role == "healer" then GameTooltip:AddLine("Healer (" .. tostring(how) .. ")", 0.3, 1, 0.4)
    elseif role == "dps" then GameTooltip:AddLine("Not a healer (" .. tostring(how) .. ")", 0.7, 0.7, 0.7) end
    ns.AddEnemyHistoryLines(e.key)
    GameTooltip:AddLine(self.key == e.key and "|cffffd100Click:|r target" or "|cffffd100Click:|r target (after combat)", 1, 1, 1)
    GameTooltip:AddLine("|cffffd100Right-click:|r KOS, note", 1, 1, 1)
    GameTooltip:Show()
end

local function BuildNearby()
    local f = CreateFrame("Frame", "WatchXNearby", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetSize(NearbyWidth(), 24 + NB_ROW_H)
    f:SetScale(NearbyScale())
    LoadPoint(f, "nearbyPoint", { "TOPRIGHT", "TOPRIGHT", -240, -220 })
    Flat(f)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    f.title:SetText("Nearby")
    -- History: the big list of everyone you've met
    f.hist = CreateFrame("Button", nil, f)   -- a small list icon (≡), on the title's line
    f.hist:SetSize(18, 16)
    f.hist:SetPoint("TOPRIGHT", f, "TOPRIGHT", -7, -5)
    f.hist:SetScript("OnClick", function() ns.ShowHistory() end)
    local hhl = f.hist:CreateTexture(nil, "HIGHLIGHT")
    hhl:SetAllPoints()
    hhl:SetColorTexture(1, 0.82, 0, 0.2)
    for i = 0, 2 do   -- three short lines: ≡
        local ln = f.hist:CreateTexture(nil, "ARTWORK")
        ln:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
        ln:SetSize(10, 2)
        ln:SetPoint("CENTER", f.hist, "CENTER", 0, 4 - i * 4)
    end
    f.hist:SetScript("OnEnter", function(self)
        Tip(self, "History", "Everyone you've met: kills, deaths, last seen, KOS, guilds and notes.")
    end)
    f.hist:SetScript("OnLeave", GameTooltip_Hide)
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.count:SetPoint("RIGHT", f.hist, "LEFT", -8, 0)
    f.count:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -26)
    f.empty:SetText("No enemy players seen")
    f.rows = {}
    for i = 1, NB_ROWS do
        local r = CreateFrame("Button", "WatchXNearbyRow" .. i, f, "SecureActionButtonTemplate")
        r:SetHeight(NB_ROW_H - 1)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -22 - (i - 1) * NB_ROW_H)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -22 - (i - 1) * NB_ROW_H)
        r:RegisterForClicks("AnyUp")
        r:SetAttribute("useOnKeyDown", false)
        r:SetAttribute("type1", "macro")
        r:SetAttribute("macrotext1", "")
        r.bar = r:CreateTexture(nil, "BACKGROUND")
        r.bar:SetAllPoints()
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("RIGHT", r, "RIGHT", -5, 0)
        r.info:SetJustifyH("RIGHT")
        r.info:SetWordWrap(false)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", r, "LEFT", 5, 0)
        r.name:SetPoint("RIGHT", r.info, "LEFT", -6, 0)   -- the name gets the room the info leaves
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r:SetScript("OnEnter", NearbyRowTip)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:SetScript("PostClick", function(self, button)   -- left click = the secure macro (target)
            if button == "RightButton" and self.shownKey then ns.EnemyMenu(self, self.shownKey) end
        end)
        r:SetAlpha(0)
        r:EnableMouse(false)
        f.rows[i] = r
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" and not moving then ns.OpenNearbySettings() end end)
    f:SetScript("OnEnter", function(self)
        if moving then return end
        Tip(self, "Nearby", "Enemy players around you. Click a row to target.", "|cffffd100Right-click here:|r settings")
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:SetScript("OnDragStart", function(self)
        if moving and not self.attached and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        SavePoint(self, "nearbyPoint")
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not moving or InCombatLockdown() then return end
        Rescale(self, "nearbyScale", delta)
        SavePoint(self, "nearbyPoint")
        if ns.NearbyLabel then ns.NearbyLabel() end
    end)
    AddGrips(f, function(self, st, cx, cy)
        if InCombatLockdown() then return end
        SizeTo(self, st, cx, cy, self:GetHeight(), "nearbyScale", "nearbyWidth")
        self:SetWidth(NearbyWidth())
        if ns.NearbyLabel then ns.NearbyLabel() end
    end, function(self) SavePoint(self, "nearbyPoint") end)
    f:Hide()
    return f
end

-- Attached: the list hangs under the mini bar – same width and size, it moves with it. (Not in combat:
-- the list holds secure rows, so it can't be moved then.)
function Attached() return db().nearbyAttach ~= false and mini ~= nil end

function ns.NearbyAttachWidth()   -- what the mini bar should be at least, so the two line up
    if not (nb and Attached() and db().nearby and nb:IsShown()) then return 0 end
    return NearbyWidth()
end

-- The stack under the mini bar (1 px apart): the compact XP bar, then the Nearby list. below: the room the frames
-- above it take. Under the big red bar when that's up in the mini bar's spot; in the mini bar's spot when it's hidden.
local STACK_GAP = 1
function ns.UnderMini(f, below)
    if not mini then return end
    local sc = mini:GetScale() or 1
    below = below or 0
    f:ClearAllPoints()
    if mini.visible then
        f:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 0, -STACK_GAP - below)
    elseif TargetShown() and not OwnSpot() then
        f:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, -(TARGET_H * AlertScale() / sc) - STACK_GAP - below)
    else
        f:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, -below)
    end
end
-- One width for the whole stack: the one you gave the mini bar, else the wider of the mini bar and the Nearby list.
function ns.StackWidth()
    if not mini then return NearbyWidth() end
    if db().miniWidth then return mini:GetWidth() or NearbyWidth() end
    return math.max(mini:GetWidth() or 0, NearbyWidth())
end
function ns.StackKey()
    return mini and (tostring(mini.visible) .. tostring(TargetShown() and not OwnSpot())) or ""
end

function ns.AttachNearby()
    if ns.PlaceXPBar then ns.PlaceXPBar() end
    if not nb or InCombatLockdown() then return end
    if Attached() then
        local sc = mini:GetScale() or 1
        nb:SetScale(sc)
        nb:SetWidth(ns.StackWidth())
        ns.UnderMini(nb, ns.XPBarSlot and ns.XPBarSlot() or 0)
        nb.attached = true
        mini.holdsSecure = true
    elseif nb.attached then
        nb.attached = false
        mini.holdsSecure = false
        nb:SetScale(NearbyScale())
        nb:SetWidth(NearbyWidth())
        LoadPoint(nb, "nearbyPoint", { "TOPRIGHT", "TOPRIGHT", -240, -220 })
    end
end

local function PaintNearbyRow(r, e, now)
    local cr, cg, cb = ClassColor(e.class)
    local near = now - e.last <= ns.NEARBY_ACTIVE
    r.bar:SetColorTexture(cr * 0.6, cg * 0.6, cb * 0.6, near and 0.9 or 0.35)
    local rec = ns.db.enemies[e.key]
    local healer = ns.db.plateHealer ~= false and ns.IsHealer(e.key)
    local wanted = rec and rec.wanted and not rec.wanted.claimed and ns.db.wantedOn ~= false
    r.name:SetText((e.kos and "|cffff3030KOS|r " or "") .. (wanted and "|cffffa000WANTED|r " or "")
        .. ((rec and rec.avoid) and "|cffff8040AVOID|r " or "")
        .. (healer and "|cff40ff60+|r " or "") .. e.name
        .. ((rec and rec.note) and " |cffffd100*|r" or ""))
    r.name:SetTextColor(near and 1 or 0.7, near and 1 or 0.7, near and 1 or 0.7)
    local tags = ""
    if e.stealth and now - e.stealth < 60 then tags = tags .. "|cffd8a0ffSTEALTH|r  " end
    if e.targetingMe and now - e.targetingMe < 10 then tags = tags .. "|cffff5050> you|r  " end
    local lvl = (e.level and e.level > 0) and tostring(e.level) or "??"
    r.info:SetText(tags .. lvl .. " " .. ClassName(e.class) .. (near and "" or ("  |cffaaaaaa" .. Ago(now - e.last) .. "|r")))
    r.shownKey = e.key
    r:SetAlpha(1)
end

local PlaceToast
local function RefreshNearby()
    if not nb then return end
    nb:SetAlpha((not moving and ns.NearbyZoneMode() == "fade") and 0.35 or 1)   -- alpha is fine in combat
    if toast and toast:IsShown() and PlaceToast then PlaceToast() end
    local d = db()
    local combat = InCombatLockdown()
    local list = d.nearby and ns.NearbyList() or {}
    local now, near = time(), 0
    for _, e in ipairs(list) do if now - e.last <= ns.NEARBY_ACTIVE then near = near + 1 end end
    local hidden = #list - NearbyMax()
    nb.count:SetText((near > 0 and (near .. " near") or (#list > 0 and (#list .. " recent") or ""))
        .. (hidden > 0 and ("  |cffaaaaaa+" .. hidden .. "|r") or ""))
    if not combat then
        local zone = ns.NearbyZoneMode()
        local want = d.nearby and (moving or (zone ~= "hide" and (#list > 0 or d.nearbyShowEmpty == true)))
        nb:SetShown(want and true or false)
        if not want then return end
        local n = math.min(#list, NearbyMax())
        for i, r in ipairs(nb.rows) do
            local e = i <= n and list[i] or nil
            r.key = e and e.key or nil
            r:SetAttribute("macrotext1", e and ns.TargetMacro(e.first, e.name, e.key) or "")
            r:EnableMouse(e ~= nil)
            if e then PaintNearbyRow(r, e, now) else r.shownKey = nil; r:SetAlpha(0) end
        end
        nb.empty:Hide()   -- empty = just the header, no text
        nb:SetHeight(n > 0 and (26 + n * NB_ROW_H) or 24)
        if nb.attached or Attached() then ns.AttachNearby() else nb:SetWidth(NearbyWidth()) end
    elseif nb:IsShown() then
        -- secure rows can't change in combat: each row keeps its player, newcomers fill the empty rows
        local onRow = {}
        for _, r in ipairs(nb.rows) do
            local e = r.key and ns.nearby[r.key]
            if e then PaintNearbyRow(r, e, now); onRow[e.key] = true end
        end
        local i = 1
        for _, e in ipairs(list) do
            if not onRow[e.key] then
                while nb.rows[i] and nb.rows[i].key do i = i + 1 end
                local r = i <= NearbyMax() and nb.rows[i]
                if not r then break end
                PaintNearbyRow(r, e, now)
                i = i + 1
            end
        end
        nb.empty:Hide()
    end
end
ns.RefreshNearby = RefreshNearby

-- "Stealthed player detected!" – a small card that fades after a few seconds.
-- The warning card: "Stealthed player detected!" (purple) or "Enemy player detected!" (red). With the
-- Nearby list on (and "on top of the list" ticked) it sits on top of the list, as part of it – same
-- width, moves and grows with it. Otherwise it has its own spot.
local TOAST_KINDS = {
    stealth = { head = "Stealthed player detected!", r = 0.8, g = 0.55, b = 1, icon = "Interface\\Icons\\Ability_Stealth" },
    enemy = { head = "Enemy player detected!", r = 1, g = 0.35, b = 0.35, icon = "Interface\\Icons\\Ability_DualWield" },
    kos = { head = "Kill on sight!", r = 1, g = 0.15, b = 0.15, icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
    wanted = { head = "WANTED!", r = 1, g = 0.63, b = 0, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
}

local function ToastDocked()
    return db().warnDock == true and db().nearby and nb and nb:IsShown()
end

function PlaceToast()
    if not toast then return end
    toast:ClearAllPoints()
    if ToastDocked() then
        toast:SetScale(nb:GetScale() or 1)
        toast:SetPoint("BOTTOMLEFT", nb, "TOPLEFT", 0, 2)
        toast:SetPoint("BOTTOMRIGHT", nb, "TOPRIGHT", 0, 2)
        toast.docked = true
    else
        toast:SetScale(1)
        LoadPoint(toast, "toastPoint", { "TOP", "TOP", 0, -250 })
        toast:SetWidth(math.max(200, toast.name:GetStringWidth() + 60, toast.head:GetStringWidth() + 60))
        toast.docked = false
    end
end

function ns.ShowStealthToast(e, kind)
    if not toast then
        toast = CreateFrame("Frame", "WatchXStealthToast", UIParent)
        toast:SetSize(230, 40)
        toast:SetFrameStrata("HIGH")
        toast:SetMovable(true)
        toast:SetClampedToScreen(true)
        toast:RegisterForDrag("LeftButton")
        toast:SetScript("OnDragStart", function(self) if moving and not self.docked then self:StartMoving() end end)
        toast:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            if ns.Snap then ns.Snap(self) end
            SavePoint(self, "toastPoint")
        end)
        Flat(toast)
        toast.edge = toast:CreateTexture(nil, "BORDER")
        toast.edge:SetPoint("TOPLEFT", 4, -4); toast.edge:SetPoint("BOTTOMLEFT", 4, 4)
        toast.edge:SetWidth(3)
        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(28, 28)
        toast.icon:SetPoint("LEFT", toast, "LEFT", 9, 0)
        toast.head = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        toast.head:SetPoint("TOPLEFT", toast, "TOPLEFT", 44, -6)
        toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        toast.name:SetPoint("TOPLEFT", toast.head, "BOTTOMLEFT", 0, -2)
        toast.name:SetPoint("RIGHT", toast, "RIGHT", -6, 0)
        toast.name:SetJustifyH("LEFT")
        toast.name:SetWordWrap(false)
        toast.hint = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        toast.hint:SetPoint("TOPRIGHT", toast, "TOPRIGHT", -6, -7)
        toast:SetScript("OnUpdate", function(self)
            if moving and self.sample then self:SetAlpha(1) return end   -- stays while unlocked
            if self.waitCombat and InCombatLockdown() then self:SetAlpha(1) return end   -- clickable after combat
            local left = (self.untilT or 0) - GetTime()
            if left <= 0 then self:Hide() elseif left < 1 then self:SetAlpha(left) end
        end)
        toast:SetScript("OnHide", function() if ns.DisarmCard then ns.DisarmCard() end end)
    end
    local k = TOAST_KINDS[kind or "stealth"] or TOAST_KINDS.stealth
    toast.head:SetText(k.head)
    toast.head:SetTextColor(k.r, k.g, k.b)
    toast.edge:SetColorTexture(k.r, k.g, k.b, 1)
    if toast.SetBackdropBorderColor then toast:SetBackdropBorderColor(k.r, k.g, k.b, 1) end
    local coords = e.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]
    if coords then
        toast.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        toast.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        toast.icon:SetTexture(k.icon)
        toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local cr, cg, cb = ClassColor(e.class)
    toast.name:SetText(e.name .. ((e.level and e.level > 0) and ("  |cffaaaaaa" .. e.level .. " " .. ClassName(e.class) .. "|r") or ""))
    toast.name:SetTextColor(cr, cg, cb)
    toast.sample = e.sample
    -- the list may not be up yet (the first enemy): show it first, so the card can sit on it
    if db().nearby and nb and not nb:IsShown() and not InCombatLockdown() then RefreshNearby() end
    PlaceToast()
    toast.untilT = GetTime() + 6
    toast:EnableMouse((e.sample and not toast.docked) and true or false)
    toast:SetAlpha(1)
    toast:Show()
    toast.hint:SetText("")
    toast.player = (not e.sample) and e or nil
    toast.waitCombat = false
    if toast.player then
        if InCombatLockdown() then
            toast.waitCombat = true   -- secure buttons can't change in combat: armed when it ends
            toast.hint:SetText("click after combat")
        else
            ns.ArmCard()
        end
    end
end

-- Click the card = target the player. The card itself isn't secure (it moves and fades freely), so a
-- see-through secure button is laid exactly over it while it's up – placed and armed out of combat only.
local cardBtn
function ns.ArmCard()
    if not (toast and toast:IsShown() and toast.player) or InCombatLockdown() then return end
    local e = toast.player
    if not cardBtn then
        cardBtn = CreateFrame("Button", "WatchXCardButton", UIParent, "SecureActionButtonTemplate")
        cardBtn:SetFrameStrata("HIGH")
        cardBtn:SetFrameLevel((toast:GetFrameLevel() or 1) + 20)
        cardBtn:RegisterForClicks("AnyUp")
        cardBtn:SetAttribute("useOnKeyDown", false)
        cardBtn:SetAttribute("type1", "macro")
        local hl = cardBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        cardBtn:SetScript("PostClick", function(self, button)
            if button == "RightButton" and toast and not InCombatLockdown() then toast:Hide() end
        end)
        cardBtn:SetScript("OnEnter", function(self)
            local p = toast and toast.player
            Tip(self, p and p.name or "?", "|cffffd100Click:|r target", "|cffffd100Right-click:|r dismiss")
        end)
        cardBtn:SetScript("OnLeave", GameTooltip_Hide)
        cardBtn:SetScript("OnUpdate", function(self)   -- fades with the card (alpha is allowed in combat)
            if toast then self:SetAlpha(toast:IsShown() and toast:GetAlpha() or 0) end
        end)
    end
    cardBtn:SetAttribute("macrotext1", ns.TargetMacro(e.first or e.name, e.name, e.key or e.name))
    local l, t, r, b = toast:GetLeft(), toast:GetTop(), toast:GetRight(), toast:GetBottom()
    if not (l and t and r and b) then return end
    local sc = toast:GetScale() or 1
    cardBtn:ClearAllPoints()
    cardBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * sc, t * sc)
    cardBtn:SetSize((r - l) * sc, (t - b) * sc)
    cardBtn:Show()
    toast.hint:SetText("click: target")
    toast.waitCombat = false
end

function ns.DisarmCard()
    if cardBtn and not InCombatLockdown() then cardBtn:Hide() end
end

-- A KOS player showed up: the KOS card always wins, with a sound.
function ns.OnKOS(e)
    if not db().nearby then return end
    ns.Print("|cffff3030Kill on sight:|r " .. e.name .. (e.guild and (" <" .. e.guild .. ">") or ""))
    if db().stealthSound ~= false then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    ns.ShowStealthToast(e, "kos")
end

-- A wanted player showed up: the WANTED card with the reward, and a sound.
function ns.OnWantedSeen(e, w)
    if not db().nearby then return end
    ns.Print("|cffffa000WANTED|r nearby: " .. e.name .. (w.reward and (" – " .. w.reward) or "") .. (w.by and (" (from " .. w.by .. ")") or ""))
    if db().stealthSound ~= false then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    ns.ShowStealthToast(e, "wanted")
    if toast and w.reward then toast.head:SetText("WANTED!  |cffffd100" .. w.reward .. "|r") end
end

-- A new enemy in the list: the red card (not more often than every few seconds).
local lastEnemyToast = 0
function ns.OnNewEnemy(e)
    if db().newEnemyCard ~= true or not db().nearby then return end
    local shownHead = toast and toast:IsShown() and toast.head:GetText()
    if GetTime() - lastEnemyToast < 3 or shownHead == TOAST_KINDS.stealth.head or shownHead == TOAST_KINDS.kos.head
            or (shownHead and shownHead:find("WANTED", 1, true)) then
        return   -- a stealth or KOS card is more important: let it stay
    end
    lastEnemyToast = GetTime()
    ns.ShowStealthToast(e, "enemy")
end

-- The help label while unlocked: above the warning card when it sits on the list, else above the list.
function ns.NearbyLabel()
    if not (nbLabel and nb) then return end
    if toast and toast:IsShown() then PlaceToast() end
    local top = (toast and toast:IsShown() and toast.docked) and toast or nb
    if nb.attached then
        nbLabel:Hide()   -- it moves and grows with the mini bar: the mini bar's label says how
    else
        nbLabel:Set(top, "|cffffd100Nearby|r · drag to move · right edge: width · bottom edge: text size (" .. Pct(nb:GetScale() or 1) .. ")")
    end
end

function ns.NearbyMove(on)
    if not nb or InCombatLockdown() then return end
    ShowGrips(nb, on and db().nearby and not nb.attached)
    nb:EnableMouseWheel(on and true or false)
    if on and db().nearby then
        nbLabel = nbLabel or MakeLabel("WatchXNearbyLabel")
        RefreshNearby()
        -- the warning card too: on top of the list, or (not docked) at its own spot, with its own label
        local docked = db().warnDock == true
        ns.ShowStealthToast({ sample = true, class = "ROGUE",
            name = docked and "Warnings show here, on the list" or "Example Rogue  60 Rogue" })
        ns.NearbyLabel()
        if not docked then
            toastLabel = toastLabel or MakeLabel("WatchXToastLabel")
            toastLabel:Set(toast, "|cffffd100Warnings|r (stealth, KOS, new enemy) · drag to move")
        elseif toastLabel then
            toastLabel:Hide()
        end
    else
        if nbLabel then nbLabel:Hide() end
        if toastLabel then toastLabel:Hide() end
        if not nb.attached then SavePoint(nb, "nearbyPoint") end
        if toast and toast.sample then toast:Hide(); toast.sample = nil end
        RefreshNearby()
    end
end

-- ---------------------------------------------------------------- grid and snapping (while unlocked)
-- A faint grid over the screen while unlocked; a dropped bar snaps to the other WatchX bars (lined up,
-- or right under/over/next to them), to the middle of the screen, or to the grid.
local GRID, SNAP, GAP = 32, 10, 2
local grid

function ns.ShowGrid(on)
    if not on then
        if grid then grid:Hide() end
        return
    end
    if not grid then
        grid = CreateFrame("Frame", "WatchXGrid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid:EnableMouse(false)
        local W, H = UIParent:GetWidth(), UIParent:GetHeight()
        local cx, cy = W / 2, H / 2
        local function line(vertical, pos, center)
            local t = grid:CreateTexture(nil, "BACKGROUND")
            if center then t:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.45)
            else t:SetColorTexture(1, 1, 1, 0.07) end
            if vertical then
                t:SetPoint("TOPLEFT", grid, "TOPLEFT", pos, 0)
                t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", pos, 0)
                t:SetWidth(center and 2 or 1)
            else
                t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, pos)
                t:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, pos)
                t:SetHeight(center and 2 or 1)
            end
        end
        -- lines out from the middle, so the middle lines are always there
        for x = cx % GRID, W, GRID do line(true, x, math.abs(x - cx) < 1) end
        for y = cy % GRID, H, GRID do line(false, y, math.abs(y - cy) < 1) end
    end
    grid:Show()
end

-- left, top, right, bottom of a frame in UIParent units
local function Rect(f)
    local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
    if not (l and t and r and b) then return end
    local sc = f:GetScale() or 1
    return l * sc, t * sc, r * sc, b * sc
end

function ns.Snap(f)
    local l, t, r, b = Rect(f)
    if not l then return end
    local w, h = r - l, t - b
    local others = {}
    for _, o in ipairs({ mini, nb, toast, alertSpot, ns.levelFrame }) do
        if o and o ~= f and o:IsShown() and (o ~= nb or not nb.attached) and (o ~= mini or mini.visible)
            and not (o == toast and toast.docked) then
            local ol, ot, orr, ob = Rect(o)
            if ol then others[#others + 1] = { ol, ot, orr, ob } end
        end
    end
    -- the best x for the left edge and the best y for the top edge, each within SNAP
    local bestX, dX, bestY, dY = nil, SNAP + 1, nil, SNAP + 1
    local function tryX(newLeft) local d = math.abs(newLeft - l); if d < dX then bestX, dX = newLeft, d end end
    local function tryY(newTop) local d = math.abs(newTop - t); if d < dY then bestY, dY = newTop, d end end
    for _, o in ipairs(others) do
        local ol, ot, orr, ob = o[1], o[2], o[3], o[4]
        tryX(ol); tryX(orr - w); tryX((ol + orr) / 2 - w / 2)      -- lined up: left, right, centre
        tryX(orr + GAP); tryX(ol - GAP - w)                      -- next to it
        tryY(ot); tryY(ob + h)                                    -- lined up: top, bottom
        tryY(ob - GAP); tryY(ot + GAP + h)                        -- under it, over it
    end
    local W = UIParent:GetWidth()
    tryX(W / 2 - w / 2)                                           -- the middle of the screen
    if not bestX then tryX(math.floor(l / GRID + 0.5) * GRID) end -- the grid
    if not bestY then tryY(math.floor(t / GRID + 0.5) * GRID) end
    if not (bestX or bestY) then return end
    local sc = f:GetScale() or 1
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bestX or l) / sc, (bestY or t) / sc)
end

-- ---------------------------------------------------------------- chat log bar (secure) and send bar
-- The chat log bar is a secure button running /chatlog (LoggingChat is protected on this client;
-- a click on a secure button is allowed). It is placed by coordinates under the mini bar – never
-- anchored to it – so dragging the mini bar can't touch a protected frame in combat.

local function BarLook(b, r, g, bl, font)
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, bl, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.text = b:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
end

local function CreatePrompt()
    if prompt then return end
    if InCombatLockdown() then promptPending = true; return end
    prompt = CreateFrame("Button", "WatchXChatLogButton", UIParent, "SecureActionButtonTemplate")
    prompt:SetSize(300, 20)
    prompt:SetFrameStrata("MEDIUM")
    prompt:RegisterForClicks("AnyUp")
    prompt:SetAttribute("useOnKeyDown", false)
    prompt:SetAttribute("type", "macro")
    prompt:SetAttribute("macrotext", "/chatlog")
    BarLook(prompt, 0.45, 0.32, 0, "GameFontNormalSmall")
    prompt:SetScript("OnEnter", function(self)
        if self.mode == "plates" then
            Tip(self, "WatchX – enemy nameplates", "WatchX spots mobs and players through enemy nameplates. "
                .. "Click here to turn them on (same as pressing V).")
        elseif self.mode == "friends" then
            Tip(self, "WatchX – friendly nameplates", "Any friendly player works through friendly nameplates. "
                .. "Click here to turn them on (same as pressing Shift+V).")
        else
            Tip(self, "WatchX – chat log", "Phone alerts travel through WoW's chat log file. WoW only lets you turn it "
                .. "on yourself, so click here (same as typing /chatlog).")
        end
    end)
    prompt:SetScript("OnLeave", GameTooltip_Hide)
    prompt:Hide()
end

-- x, top: where the bars under the mini bar go – under the big target bar, the mini bar, or (when the
-- mini bar is see-through) in its spot
local function BarSpot()
    local x, top, bottom = MiniRect()
    if not x then return UIParent:GetWidth() / 2, UIParent:GetHeight() - 100 end
    if nb and nb.attached and nb:IsShown() and nb:GetBottom() then   -- under the list that hangs under it
        return x, nb:GetBottom() * (nb:GetScale() or 1) - 2
    end
    if TargetShown() and not OwnSpot() then return x, top - TARGET_H * AlertScale() - 2 end
    if mini.visible then return x, bottom - 2 end
    return x, top
end

-- ---------------------------------------------------------------- target button (secure)
-- When a watched mob is up (or an enemy player was just seen), the mini bar grows into a big red
-- button in the same spot: one click targets it (/targetexact – a click on a secure button is allowed)
-- and puts a skull on it. Right-click goes back to the small bar until the next one. Secure frames
-- can't be changed in combat: it waits for combat to end.
-- The macro that targets a watched name: players are targeted by their full name (Forever has surnames).
local function TargetLine(name)
    local m = ns.MobState(name)
    if m.isPlayer and m.full and m.key then return ns.TargetMacro(name, m.full, m.key) end
    return "/targetexact " .. name
end

local function CreateTargetButton()
    if targetBtn or InCombatLockdown() then return end
    local b = CreateFrame("Button", "WatchXTargetButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(240, TARGET_H)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type1", "macro")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 3, -3); bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetColorTexture(0.50, 0.06, 0.06, 0.95)
    RedEdge(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(28, 28)
    b.icon:SetPoint("LEFT", b, "LEFT", 9, 0)
    b.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 46, -5)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.hint = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.hint:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -2)
    b.hint:SetTextColor(1, 0.75, 0.75)
    b.hint:SetText("Click: target + skull")
    b:SetScript("PostClick", function(self, button)
        if button == "RightButton" then
            if targetName and not InCombatLockdown() then
                targetDismissed[targetName] = true
                ns.UpdateTargetButton()
                ns.UpdateChatLogPrompt()
            end
            return
        end
        -- The macro targeted it and put the skull on (/tm). /tm takes the skull off again on a second
        -- click, so once the skull is on, later clicks only target. (SetRaidTarget from addon code is
        -- blocked on this client – the macro line is what works.)
        if InCombatLockdown() or not targetName then return end
        local tname = UnitExists("target") and UnitName("target")
        if type(issecretvalue) == "function" and tname and issecretvalue(tname) then return end
        if tname == targetName and GetRaidTargetIndex and GetRaidTargetIndex("target") == 8 then
            self:SetAttribute("macrotext1", TargetLine(targetName))
        end
    end)
    b:SetScript("OnEnter", function(self)
        Tip(self, "Target " .. (targetName or "?"), "|cffffd100Click:|r target it and mark it with a skull",
            "|cffffd100Right-click:|r back to the small bar")
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    targetBtn = b
end

-- What could be targeted right now: watched mobs that are up, then an enemy player seen in the last minute.
local function TargetCandidates()
    local list = {}
    for _, mob in ipairs(ns.GetMobList()) do
        if mob.enabled and ns.GetMobStatus(mob.name) == "up" then
            list[#list + 1] = { mob.name, ns.IsPlayerEntry(mob.name) and "FOUND" or "UP" }
        end
    end
    local last = ns.lastEnemy
    if db().enemyPlayers and last and time() - last.at < 60 then list[#list + 1] = { last.name, "ENEMY" } end
    local friend = ns.lastFriend
    if db().friendlyPlayers and friend and time() - friend.at < 60 then list[#list + 1] = { friend.name, "FRIEND" } end
    return list
end


function ns.UpdateTargetButton()
    if not targetBtn then CreateTargetButton() end
    if not targetBtn or InCombatLockdown() then return end
    local list, still, name, why = TargetCandidates(), {}, nil, nil
    for _, c in ipairs(list) do
        still[c[1]] = true
        if not name and not targetDismissed[c[1]] then name, why = c[1], c[2] end
    end
    for n in pairs(targetDismissed) do   -- hidden until it's gone; the next spawn shows it again
        if not still[n] then targetDismissed[n] = nil end
    end
    if name and not moving then
        if name ~= targetName then
            targetBtn:SetAttribute("macrotext1", TargetLine(name) .. "\n/tm 8")
            targetName = name
        end
        targetBtn.text:SetText("|cffffd100" .. why .. "|r  " .. name)
        targetBtn:SetWidth(math.max(220, targetBtn.text:GetStringWidth() + 64, AlertWidth()))
        -- in the mini bar's place or its own (by coordinates – a secure frame is never anchored to an
        -- addon frame)
        local x, top
        if OwnSpot() then
            x, top = AlertSpot()
        else
            x, top = MiniRect()
            if not x then x, top = UIParent:GetWidth() / 2, UIParent:GetHeight() - 100 end
        end
        local sc = AlertScale()
        targetBtn:SetScale(sc)
        targetBtn:ClearAllPoints()
        targetBtn:SetPoint("TOP", UIParent, "BOTTOMLEFT", x / sc, top / sc)
        targetBtn:Show()
    else
        targetBtn:Hide()
    end
    -- in the same spot, the small bar steps aside while the big one is there (kept in place)
    ApplyMini()
end

function ns.UpdateChatLogPrompt()
    if not prompt then
        if promptPending and not InCombatLockdown() then CreatePrompt() end
        if not prompt then return end
    end
    if InCombatLockdown() then promptPending = true; return end
    promptPending = false
    local d = db()
    local x, top = BarSpot()
    prompt:ClearAllPoints()
    prompt:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top)
    -- the one thing missing, most important first: enemy nameplates, then the chat log
    local mode, text
    if GetCVar("nameplateShowEnemies") ~= "1" and ns.NeedsEnemyPlates() then
        mode, text = "plates", "Enemy nameplates are OFF – click here to turn them on (needed to spot anything)"
    elseif ns.FriendPlatesMissing() then
        mode, text = "friends", "Friendly nameplates are OFF – click here to turn them on (for Any friendly player)"
    elseif ns.HasTargets() and (d.instant == false or d.instantOK == false) and d.chatlogOn ~= true then
        -- only needed when instant alerts (screenshots) don't work
        mode = "chatlog"
        text = d.chatlogOn == false and "Chat log is OFF – click here to turn it on (needed for phone alerts)"
            or "Click here to turn on the chat log (needed for phone alerts)"
    end
    if mode then
        if prompt.mode ~= mode then
            prompt:SetAttribute("macrotext", mode == "plates" and "/console nameplateShowEnemies 1"
                or mode == "friends" and "/console nameplateShowFriends 1" or "/chatlog")
            prompt.mode = mode
        end
        prompt.text:SetText(text)
        prompt:SetWidth(prompt.text:GetStringWidth() + 20)
        prompt:Show()
    else
        prompt:Hide()
    end
    if sendBar and sendBar:IsShown() then ns.ShowSendBar(true) end
end

function ns.ShowSendBar(show)
    if not sendBar then
        sendBar = CreateFrame("Button", "WatchXSendBar", UIParent)
        sendBar:SetSize(300, 20)
        sendBar:SetFrameStrata("HIGH")
        BarLook(sendBar, 0.55, 0.08, 0.08)
        sendBar.text:SetText("The game held back the phone alert – click here to send it")
        sendBar:SetWidth(sendBar.text:GetStringWidth() + 20)
        sendBar:SetScript("OnClick", function() ns.SendPending() end)
    end
    local x, top = BarSpot()
    if prompt and prompt:IsShown() then top = top - 22 end
    sendBar:ClearAllPoints()
    sendBar:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top)
    sendBar:SetShown(show)
end

-- ---------------------------------------------------------------- guide

local H, Y, G = "|cff4d85b3", "|cffffd100", "|cffaaaaaa"
-- The guide: short sections, each a heading with a thin line under it.
local function Step(n, text) return Y .. n .. "|r   " .. text end
local function Bullet(text) return G .. "•|r  " .. text end
local function Sub(text) return "      " .. G .. text .. "|r" end
local HELP = {
    { nil, {
        "Stand AFK at the spawn. When the mob shows up, your " .. Y .. "phone beeps within a second|r – "
            .. "with a screenshot of the game.",
    } },
    { "QUICK START  ·  once", {
        Step("1", "Get the free " .. Y .. "ntfy|r app on your phone. Tap " .. Y .. "+|r and make up a topic name."),
        Sub("Example: |r" .. Y .. "watchx-rikerud-7k2p|r" .. G .. "  – use your own name + a few random letters."),
        Sub("Anyone who knows the name can read your alerts, so keep it secret."),
        Sub("Your link is then |r" .. Y .. "ntfy.sh/|r" .. G .. "and your topic name."),
        Sub("Discord instead? Server Settings > Integrations > Webhooks > Copy Webhook URL."),
        Step("2", "Open " .. Y .. "Settings|r, paste the link and press " .. Y .. "Save & reload|r."),
        Step("3", "Download " .. Y .. "WatchX-Bridge.zip|r from " .. Y .. ns.BRIDGE_URL .. "|r, unzip it and"),
        Sub("double-click |r" .. Y .. "Install (Mac)|r" .. G .. " or |r" .. Y .. "Install (Windows)|r" .. G .. ". It finds the game by itself."),
        Sub("Mac: if it won't open, right-click > Open.  Windows: More info > Run anyway."),
        Step("4", "Press " .. Y .. "Send test|r. Your phone should beep."),
    } },
    { "WHAT TO WATCH", {
        Bullet(Y .. "Prince Nazjak|r is built in."),
        Bullet("More mobs or players: target it and click " .. Y .. "+ Watch your target|r in the panel,"),
        "     or type the name under " .. Y .. "Watch list|r in Settings.",
        Bullet(Y .. "Any enemy player|r / " .. Y .. "Any friendly player|r: every player who shows up."),
        Bullet("The " .. Y .. "×|r removes a name."),
    } },
    { "WHEN SOMETHING SHOWS UP", {
        Bullet("Phone: an alert within a second, with a screenshot."),
        Bullet("Screen: a big red bar. " .. Y .. "Click|r = target it + skull.  " .. Y .. "Right-click|r = hide it."),
        Bullet("Up = a mob · Found = a player on your list · Spotted = any enemy player."),
    } },
    { "EXTRAS  ·  in Settings", {
        Bullet(Y .. "Attacked|r – an alert when something attacks you while you stand idle or AFK."),
        Bullet(Y .. "AFK logout warning|r – 5 minutes before the game logs you out."),
        Bullet(Y .. "Nearby|r – its own page under WatchX: a list of enemy players around you (like Spy)."),
        "     Click one to target it. A player going into stealth pops up a warning.",
        Bullet(Y .. "Profiles|r – switch between sets of choices, e.g. Camping, Leveling, PvP."),
    } },
    { "THE BARS", {
        Bullet(Y .. "Unlock|r (in the panel) – drag the bars, pull their edges to resize. Then " .. Y .. "Lock|r."),
        Bullet(Y .. "Only on alerts|r – the mini bar hides until something happens."),
        Bullet(Y .. "Auto-hide|r – the mini bar hides when nothing is watched."),
    } },
    { "IN GAME, CHECK THAT", {
        Bullet(Y .. "Enemy nameplates are on|r (key V – or click the yellow bar)."),
        Bullet("You stand " .. Y .. "within about 40 yards|r of the spawn."),
        Bullet("The computer doesn't go to sleep."),
    } },
    { "GOOD TO KNOW", {
        Bullet(G .. "The bridge is a small program on your computer that sends the alerts. It starts by itself. "
            .. "Remove it with Uninstall in the same folder.|r"),
        Bullet(G .. "A small black-and-white block flashes in the top-left corner when an alert goes out – that's "
            .. "the code the bridge reads. Your own screenshots are never sent.|r"),
        Bullet(G .. "Something odd? Type /wx log.|r"),
    } },
}
local HELP_FOOT = G .. "/wx|r  panel     " .. G .. "/wx settings     /wx test     /wx guide|r\n\n"
    .. G .. "WatchX – Made by|r " .. H .. ns.AUTHOR .. "|r"

local function BuildHelp()
    local f = CreateFrame("Frame", "WatchXHelp", UIParent)
    f:SetSize(560, 500)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Window(f, "WatchX – how it works", 240)
    f:Hide()
    tinsert(UISpecialFrames, "WatchXHelp")

    CloseX(f)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -40)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 44)
    local CW = 505
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CW, 10)
    scroll:SetScrollChild(child)

    -- one heading + line + text block per section, laid out when shown (heights are known then)
    local blocks = {}
    for _, sec in ipairs(HELP) do
        local blk = {}
        if sec[1] then
            blk.head = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            blk.head:SetText(sec[1])
            blk.head:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            blk.line = child:CreateTexture(nil, "ARTWORK")
            blk.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
            blk.line:SetHeight(1)
        end
        blk.body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        blk.body:SetWidth(CW - 4)
        blk.body:SetJustifyH("LEFT")
        blk.body:SetSpacing(4)
        blk.body:SetText(table.concat(sec[2], "\n"))
        blocks[#blocks + 1] = blk
    end
    local foot = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetWidth(CW - 4)
    foot:SetJustifyH("LEFT")
    foot:SetText(HELP_FOOT)

    local function Layout()
        local y = 0
        for _, blk in ipairs(blocks) do
            if blk.head then
                y = y - 14
                blk.head:ClearAllPoints()
                blk.head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                y = y - ((blk.head:GetStringHeight() or 14) + 4)
                blk.line:ClearAllPoints()
                blk.line:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                blk.line:SetPoint("TOPRIGHT", child, "TOPLEFT", CW, y)
                y = y - 8
            end
            blk.body:ClearAllPoints()
            blk.body:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            y = y - (blk.body:GetStringHeight() or 20)
        end
        y = y - 20
        foot:ClearAllPoints()
        foot:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
        y = y - (foot:GetStringHeight() or 30)
        child:SetHeight(-y + 10)
    end
    f:SetScript("OnShow", Layout)

    local bw = 120
    local b1 = Button(f, "Open panel", bw, 24, function() if panel then panel:Show() end end)
    b1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    local b2 = Button(f, "Settings", bw, 24, function() f:Hide(); ns.OpenSettings() end)
    b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
    local b3 = Button(f, "Send test", bw, 24, function() ns.SendTest() end)
    b3:SetPoint("LEFT", b2, "RIGHT", 8, 0)
    return f
end

function ns.ShowHelp()
    helpFrame = helpFrame or BuildHelp()
    helpFrame:Show()
    helpFrame:Raise()
end

-- ---------------------------------------------------------------- minimap button

local LDBIcon

function ns.SetMinimapShown(show)
    db().minimap.hide = not show
    if LDBIcon then
        if show then LDBIcon:Show("WatchX") else LDBIcon:Hide("WatchX") end
    end
end

local function InitMinimap()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and LDBIcon) then return end
    local obj = LDB:NewDataObject("WatchX", {
        type = "launcher",
        text = "WatchX",
        icon = LOGO,
        OnClick = function(_, button)
            if IsShiftKeyDown() then ns.ShowHelp()
            elseif button == "RightButton" then ns.OpenSettings()
            else ns.TogglePanel() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("WatchX")
            tt:AddLine("by " .. ns.AUTHOR, 0.5, 0.5, 0.5)
            tt:AddLine(" ")
            local any = false
            for _, mob in ipairs(ns.GetMobList()) do
                if mob.enabled then
                    any = true
                    local _, short, detail = ns.GetMobStatus(mob.name)
                    tt:AddDoubleLine(mob.name, short .. (detail ~= "" and ("|cffaaaaaa · " .. detail .. "|r") or ""), 1, 1, 1)
                end
            end
            if not any then tt:AddLine("No mobs watched", 0.6, 0.6, 0.6) end
            tt:AddLine(" ")
            tt:AddLine("|cffffd100Click:|r panel   |cffffd100Right-click:|r settings", 1, 1, 1)
            tt:AddLine("|cffffd100Shift-click:|r how it works", 1, 1, 1)
        end,
    })
    LDBIcon:Register("WatchX", obj, db().minimap)
end

do   -- (its own block: UI.lua is near Lua's 200-locals limit)
-- ---------------------------------------------------------------- where to stand: pins on the map
-- The best spots to stand for a built-in rare (e.g. Prince Nazjak), shown on the world map and the
-- minimap with HereBeDragons. Shown while that rare is watched and "Spots on the map" is ticked.
local spotPins = {}

local function ZoneMapID(preset)
    if C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(preset.mapID)
        if info and info.name == preset.zone then return preset.mapID end
        for id = 1, 2500 do   -- another client: find the zone by name (once)
            local i = C_Map.GetMapInfo(id)
            if i and i.name == preset.zone and (i.mapType == 3 or i.mapType == nil) then preset.mapID = id; return id end
        end
    end
    return preset.mapID
end

local function SpotPin(preset, i, spot, mini)
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(mini and 16 or 22, mini and 16 or 22)
    local ring = f:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("CENTER")
    ring:SetSize(mini and 18 or 25, mini and 18 or 25)
    ring:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(LOGO)
    local num = f:CreateFontString(nil, "OVERLAY", mini and "GameFontHighlightSmall" or "GameFontHighlight")
    num:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    num:SetText(i)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("WatchX – " .. preset.name, ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine(spot.text, 1, 1, 1, true)
        GameTooltip:AddLine(string.format("%.1f, %.1f  ·  stand here (nameplates reach 41 yards)", spot.x, spot.y), 0.7, 0.7, 0.7)
        if preset.spawns then
            GameTooltip:AddLine("Circle = what you see from here. Dots = spawn points:", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff40ff40green|r seen from a spot · |cffff4040red|r out of reach", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

-- Yards between two map points (in %) on a zone of zw x zh yards.
local function Yards(x1, y1, x2, y2, zw, zh)
    return math.sqrt(((x1 - x2) / 100 * zw) ^ 2 + ((y1 - y2) / 100 * zh) ^ 2)
end
local function ZoneSize(mapID)
    local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    local w, h
    if HBD and HBD.GetZoneSize then w, h = HBD:GetZoneSize(mapID) end
    if not (w and w > 0) then w, h = 3600, 2400 end   -- Arathi Highlands
    return w, h
end
local function SeeRange() return tonumber(GetCVar("nameplateMaxDistance")) or 41 end

-- Is a spawn point seen from one of the spots? (which one, or nil)
local function SpawnSeenFrom(preset, sx, sy, zw, zh)
    for i, spot in ipairs(preset.spots) do
        if Yards(sx, sy, spot.x, spot.y, zw, zh) <= SeeRange() then return i end
    end
end

-- On the world map: a circle of nameplate range around each spot and a dot per spawn point. They sit on
-- the map canvas itself, so they zoom with the map.
local overlay
local function OverlayTex(list, i, layer)
    local t = list[i]
    if not t then
        t = overlay:CreateTexture(nil, layer)
        t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")   -- a round white disc
        list[i] = t
    end
    return t
end

function ns.UpdateMapOverlay()
    if not (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame.GetMapID) then return end
    local canvas = WorldMapFrame:GetCanvas()
    if not canvas then return end
    if not overlay then
        overlay = CreateFrame("Frame", "WatchXMapOverlay", canvas)
        overlay:SetAllPoints(canvas)
        overlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 3)
        overlay:EnableMouse(false)
        overlay.circles, overlay.dots = {}, {}
    end
    for _, t in ipairs(overlay.circles) do t:Hide() end
    for _, t in ipairs(overlay.dots) do t:Hide() end
    if db().mapSpots == false then return end
    local mapID = WorldMapFrame:GetMapID()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not (w and h and w > 0) then return end
    local nc, nd = 0, 0
    for _, preset in ipairs(ns.PRESETS) do
        if preset.spots and db().watch[preset.name] and ZoneMapID(preset) == mapID then
            local zw, zh = ZoneSize(mapID)
            local R = SeeRange()
            for _, spot in ipairs(preset.spots) do
                nc = nc + 1
                local c = OverlayTex(overlay.circles, nc, "ARTWORK")
                c:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
                c:SetSize(2 * R / zw * w, 2 * R / zh * h)
                c:ClearAllPoints()
                c:SetPoint("CENTER", overlay, "TOPLEFT", spot.x / 100 * w, -spot.y / 100 * h)
                c:Show()
            end
            for _, sp in ipairs(preset.spawns or {}) do
                nd = nd + 1
                local dsz = math.max(5, w / 180)
                local d = OverlayTex(overlay.dots, nd, "OVERLAY")
                if SpawnSeenFrom(preset, sp[1], sp[2], zw, zh) then d:SetVertexColor(0.25, 1, 0.25, 0.95)
                else d:SetVertexColor(1, 0.25, 0.25, 0.95) end
                d:SetSize(dsz, dsz)
                d:ClearAllPoints()
                d:SetPoint("CENTER", overlay, "TOPLEFT", sp[1] / 100 * w, -sp[2] / 100 * h)
                d:Show()
            end
        end
    end
end

local function HookWorldMap()
    if ns.mapHooked or not WorldMapFrame then return end
    ns.mapHooked = true
    local function later() C_Timer.After(0, function() ns.Safe("map overlay", ns.UpdateMapOverlay) end) end
    if WorldMapFrame.OnMapChanged then pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", later) end
    WorldMapFrame:HookScript("OnShow", later)
end

local spawnPins = {}
local function SpawnPin(seen)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(8, 8)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f.tex = t
    f:EnableMouse(false)
    return f
end

function ns.UpdateMapPins()
    HookWorldMap()
    ns.Safe("map overlay", ns.UpdateMapOverlay)
    local HBDP = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if not HBDP then return end
    HBDP:RemoveAllWorldMapIcons("WatchX")
    HBDP:RemoveAllMinimapIcons("WatchX")
    if db().mapSpots == false then return end
    for _, preset in ipairs(ns.PRESETS) do
        if preset.spots and db().watch[preset.name] then
            local mapID = ZoneMapID(preset)
            for i, spot in ipairs(preset.spots) do
                local key = preset.name .. i
                spotPins[key] = spotPins[key] or { world = SpotPin(preset, i, spot), mini = SpotPin(preset, i, spot, true) }
                HBDP:AddWorldMapIconMap("WatchX", spotPins[key].world, mapID, spot.x / 100, spot.y / 100)
                HBDP:AddMinimapIconMap("WatchX", spotPins[key].mini, mapID, spot.x / 100, spot.y / 100, false, true)
            end
            local zw, zh = ZoneSize(mapID)
            for j, sp in ipairs(preset.spawns or {}) do   -- spawn points on the minimap: green seen, red not
                local key = preset.name .. "s" .. j
                spawnPins[key] = spawnPins[key] or SpawnPin()
                local seen = SpawnSeenFrom(preset, sp[1], sp[2], zw, zh)
                if seen then spawnPins[key].tex:SetVertexColor(0.25, 1, 0.25, 0.9)
                else spawnPins[key].tex:SetVertexColor(1, 0.25, 0.25, 0.9) end
                HBDP:AddMinimapIconMap("WatchX", spawnPins[key], mapID, sp[1] / 100, sp[2] / 100, false, false)
            end
        end
    end
end
end

-- ---------------------------------------------------------------- init / refresh

local lastPlates
local function RefreshUIInner()
    -- nameplates switched on/off (V key or the bar): the yellow bar follows
    local plates = tostring(GetCVar("nameplateShowEnemies")) .. tostring(GetCVar("nameplateShowFriends"))
    if plates ~= lastPlates then
        lastPlates = plates
        ns.UpdateChatLogPrompt()
    end
    if mini then RefreshMini() end
    RefreshNearby()
    if ns.RefreshLevel then ns.RefreshLevel() end
    ns.UpdateProfileLabels()
    if ns.RefreshWatchChips then ns.RefreshWatchChips() end
    if ns.RefreshKOSChips then ns.RefreshKOSChips() end
    if ns.RefreshAvoidCount and nearbyPage and nearbyPage:IsShown() then ns.RefreshAvoidCount() end
    local wasShown = TargetShown()
    ns.UpdateTargetButton()
    if (TargetShown() or false) ~= (wasShown or false) then ns.UpdateChatLogPrompt() end
    if panel and panel:IsShown() then RefreshPanel() end
end
-- Guarded: an error is shown once in chat (and in /wx log) instead of stopping the bars and the panel.
function ns.RefreshUI() ns.Safe("refresh", RefreshUIInner) end

-- a chat log bar that couldn't be made or moved in combat is done once combat ends
local uiEvents = CreateFrame("Frame")
uiEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
uiEvents:SetScript("OnEvent", function()
    if not ns.db then return end
    if toast and toast:IsShown() and toast.waitCombat then
        toast.untilT = GetTime() + 6
        ns.ArmCard()
    elseif not (toast and toast:IsShown()) then
        ns.DisarmCard()   -- a card that went away during combat
    end
    if not nb then nb = BuildNearby() end
    RefreshNearby()
    ns.UpdateTargetButton()
    if promptPending then ns.UpdateChatLogPrompt() end
end)

-- After a profile switch: the bars' spot and size, and the settings page if it's open.
function ns.ApplyLayout()
    if mini and not MiniFrozen() then
        mini:SetScale(MiniScale())
        LoadPoint(mini, "miniPoint", { "TOP", "TOP", 0, -120 })
        RefreshMini()
    end
    ns.UpdateTargetButton()
    if nb and not InCombatLockdown() then
        nb:SetScale(NearbyScale())
        LoadPoint(nb, "nearbyPoint", { "TOPRIGHT", "TOPRIGHT", -240, -220 })
        RefreshNearby()
    end
    for _, pg in ipairs({ settingsPage or false, settingsPage and settingsPage.alerts or false }) do
        if pg and pg:IsShown() then
            local fn = pg:GetScript("OnShow")
            if fn then fn(pg) end
        end
    end
    ns.UpdateProfileLabels()
    ns.Safe("map pins", ns.UpdateMapPins)
end

-- ---------------------------------------------------------------- XP boosts icons (until max level)
-- A small strip of icons: what gives you extra XP right now and what you're missing (ns.LevelStatus in
-- WatchX.lua). The border says how it stands (green you have it, red missing, yellow soon/running out, grey
-- worth getting), the time left is under the icon, and the tooltip says the rest.
-- Moves and resizes with the other bars (Unlock). Plain frames only – nothing protected.
local LV_MAX, LV_ICON, LV_GAP, LV_PAD, LV_TIME = 5, 30, 5, 5, 13
local LV_H = LV_PAD + LV_ICON + LV_TIME + 3
local LV_BADGES = { ok = "Interface\\RaidFrame\\ReadyCheck-Ready", todo = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    wait = "Interface\\RaidFrame\\ReadyCheck-Waiting" }
local LV_COLORS = { ok = { 0.25, 0.9, 0.3 }, todo = { 1, 0.2, 0.2 }, wait = { 1, 0.82, 0 }, info = { 0.4, 0.4, 0.4 } }
local LV_STATUS = { ok = "|cff40ff40You have it|r", todo = "|cffff6060Missing|r", wait = "|cffffd100Soon|r",
    info = "|cffaaaaaaWorth getting|r" }
local lv, lvLabel
local function LevelScale() return ClampScale(db().levelScale) end
local function LevelWidth(n) return LV_PAD * 2 + n * LV_ICON + math.max(0, n - 1) * LV_GAP end

local function LevelLabel()
    if not (lv and moving and lv:IsShown()) then return end
    lvLabel = lvLabel or MakeLabel("WatchXLevelLabel")
    lvLabel:Set(lv, "|cffffd100XP boosts|r · drag to move")
end

-- What a click does: /use the item (by name for a toy, which isn't in your bags).
local function UseMacro(o)
    if not o then return "" end
    if o.craft then return "/cast " .. o.craft.prof end   -- one you can make: open the profession
    return o.toy and ("/use " .. o.name) or ("/use item:" .. o.id)
end
local function RememberPick(slot, id)
    local d = db()
    if type(d.levelPick) ~= "table" then d.levelPick = {} end
    d.levelPick[slot] = id
    if ns.LevelDirty then ns.LevelDirty() end
end

-- Hover an icon: everything you can use for it pops up in a column right above it (your XP food; your
-- campfires, tent and other camp features) – click one to use it now. A plain tooltip beside it says how it
-- stands. The column's buttons are secure, so it only opens out of combat and closes when a fight starts.
local LVF_PER_COL, LVF_MAX = 6, 30
local lvMenu, OpenLevelMenu

-- Is the strip on the right half of the screen? Then the column grows and the tooltip sits to the left.
local function LevelOnRight()
    local x = lv and lv:GetCenter()
    local w = UIParent:GetWidth()
    if not (x and w) then return false end
    return x * (lv:GetEffectiveScale() or 1) > w * (UIParent:GetEffectiveScale() or 1) / 2
end

-- The tooltip goes beside the strip (and beside the column when that sticks out), never on top of them.
local function LevelTipOwner(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local m = lvMenu and lvMenu:IsShown() and lvMenu or nil
    local right = LevelOnRight()
    local dx = 0
    if m and m:GetLeft() and lv:GetLeft() then
        local d = right and (m:GetLeft() - lv:GetLeft()) or (m:GetRight() - lv:GetRight())
        if (right and d < 0) or (not right and d > 0) then
            dx = d * lv:GetEffectiveScale() / GameTooltip:GetEffectiveScale()
        end
    end
    if right then GameTooltip:SetPoint("BOTTOMRIGHT", lv, "BOTTOMLEFT", dx - 4, 0)
    else GameTooltip:SetPoint("BOTTOMLEFT", lv, "BOTTOMRIGHT", dx + 4, 0) end
end

local function LevelIconTip(self)
    local r = self.row
    if not r or moving then return end
    LevelTipOwner(self)
    local c = r.state == "info" and { 0.75, 0.75, 0.75 } or LV_COLORS[r.state] or { 1, 1, 1 }
    GameTooltip:SetText(r.name or "XP boost")
    GameTooltip:AddLine(r.text or "", c[1], c[2], c[3], true)
    if r.timer then GameTooltip:AddLine("Time left: " .. ns.Clock(r.timer), 1, 0.82, 0) end
    local n = r.options and #r.options or 0
    if n == 0 and r.tip then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(r.tip, 0.7, 0.7, 0.7, true)
    elseif r.use then
        if not (r.text or ""):find("Click:", 1, true) then
            GameTooltip:AddLine("|cffffd100Click:|r " .. (r.slot == "food" and "eat " or "use ") .. r.use.name, 1, 1, 1, true)
        end
        if n > 1 then GameTooltip:AddLine("Or click another one in the column.", 0.7, 0.7, 0.7, true) end
    end
    if (r.slot == "tent" or r.slot == "food") and ns.UnseenProfessions then
        local unseen = ns.UnseenProfessions()
        if #unseen > 0 then
            GameTooltip:AddLine("Open " .. table.concat(unseen, ", ") .. " once – then WatchX shows what you can make.", 0.6, 0.8, 1, true)
        end
    end
    GameTooltip:Show()
end

local function LevelFlyButton(m, i)
    local b = CreateFrame("Button", "WatchXLevelMenuRow" .. i, m, "SecureActionButtonTemplate")
    b:SetSize(LV_ICON, LV_ICON)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type1", "macro")   -- left-click: use it; right-click: just pick it (PostClick)
    b:SetAttribute("macrotext1", "")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2); b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetColorTexture(0.15, 0.15, 0.15, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.badge:SetSize(13, 13)
    b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 4, 4)
    b.badge:SetTexture(LV_BADGES.ok)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
    b.make = b:CreateTexture(nil, "OVERLAY", nil, 3)   -- a hammer: one you can make, not one you carry
    b.make:SetSize(13, 13)
    b.make:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -2, -2)
    b.make:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    b.make:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        if not self.opt then return end
        LevelTipOwner(self)   -- the item's own tooltip (what a camp feature gives)
        local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, self.opt.id)
        if not ok then GameTooltip:SetText(self.opt.name or "") end
        GameTooltip:AddLine(" ")
        local c = self.opt.craft
        if c then
            GameTooltip:AddLine("You don't have one – you can make it (" .. c.prof .. ")", 0.4, 1, 0.4, true)
            if c.can > 0 then GameTooltip:AddLine("Reagents for " .. c.can .. " in your bags.", 1, 1, 1)
            elseif c.missing ~= "" then GameTooltip:AddLine("Missing: " .. c.missing, 1, 0.4, 0.4, true) end
            GameTooltip:AddLine("|cffffd100Click:|r open " .. c.prof, 1, 1, 1)
        else
            GameTooltip:AddLine("|cffffd100Left-click:|r use it now", 1, 1, 1)
            GameTooltip:AddLine("|cffffd100Right-click:|r use this one when you click the icon", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("PostClick", function(self)
        if not self.opt or self.opt.craft then return end
        RememberPick(self.opt.fire and "fire" or m.slot, self.opt.id)
        ns.RefreshLevel()
    end)
    return b
end

local function BuildLevelMenu()
    local m = CreateFrame("Frame", "WatchXLevelMenu", lv)
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    Flat(m)
    m:EnableMouse(true)
    m.buttons = {}
    -- closes by itself a moment after the mouse leaves it (and its icon)
    local away = 0
    m:SetScript("OnUpdate", function(self, elapsed)
        if Hovered(self) or Hovered(self.owner) then away = 0 return end
        away = away + elapsed
        if away > 0.5 and not InCombatLockdown() then self:Hide() end
    end)
    m:SetScript("OnShow", function() away = 0 end)
    m:Hide()
    return m
end

-- Lay the column out for one icon (out of combat: the buttons are secure).
local function FillLevelMenu(m, r)
    local opts = r.options or {}
    local mark = r.picks or (r.use and { [r.use.id] = true }) or {}
    local n = math.min(#opts, LVF_MAX)
    local step = LV_ICON + LV_GAP
    local cols, rows = math.ceil(n / LVF_PER_COL), math.min(n, LVF_PER_COL)
    m:SetSize(LV_PAD * 2 + cols * step - LV_GAP, LV_PAD * 2 + rows * step - LV_GAP)
    local corner = (m.up and "BOTTOM" or "TOP") .. (m.left and "RIGHT" or "LEFT")
    for i = 1, math.max(n, #m.buttons) do
        local b = m.buttons[i]
        if i <= n then
            local o = opts[i]
            if not b then b = LevelFlyButton(m, i); m.buttons[i] = b end
            local c, k = math.floor((i - 1) / LVF_PER_COL), (i - 1) % LVF_PER_COL
            b:ClearAllPoints()
            b:SetPoint(corner, m, corner, (m.left and -1 or 1) * (LV_PAD + c * step), (m.up and 1 or -1) * (LV_PAD + k * step))
            b.opt = o
            b:SetAttribute("macrotext1", UseMacro(o))
            b.icon:SetTexture(ns.ItemIcon(o.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            if r.use and r.use.id == o.id then b.border:SetColorTexture(1, 0.82, 0, 1)   -- what the icon click does
            else b.border:SetColorTexture(0.15, 0.15, 0.15, 1) end
            b.badge:SetAlpha((mark[o.id] and not o.craft) and 1 or 0)
            b.icon:SetDesaturated(o.craft and true or false)
            b.icon:SetAlpha(o.craft and 0.75 or 1)
            b.make:SetShown(o.craft and true or false)
            if o.craft then
                b.count:SetText(o.craft.can > 0 and ("|cff40ff40" .. o.craft.can .. "|r") or "|cffff40400|r")
            else
                b.count:SetText((not o.toy and o.count and o.count > 1) and o.count or "")
            end
            b:Show()
        elseif b then
            b.opt = nil
            b:SetAttribute("macrotext1", "")
            b:Hide()
        end
    end
end

OpenLevelMenu = function(owner)
    if InCombatLockdown() or moving or not (owner and owner.row) then return end
    local r = owner.row
    if not (r.options and #r.options > 0) then
        if lvMenu then lvMenu:Hide() end
        return
    end
    lvMenu = lvMenu or BuildLevelMenu()
    local m = lvMenu
    if m:IsShown() and m.owner == owner and m.row == r then return end   -- nothing new
    m.owner, m.slot, m.row = owner, r.slot, r
    -- above the icon, unless it sits near the top of the screen; more columns grow towards the middle
    local _, oy = owner:GetCenter()
    local sh = UIParent:GetHeight()
    m.up = not (oy and sh and oy * (owner:GetEffectiveScale() or 1) > sh * (UIParent:GetEffectiveScale() or 1) * 0.7)
    m.left = LevelOnRight()
    FillLevelMenu(m, r)
    m:ClearAllPoints()
    local h = m.left and "RIGHT" or "LEFT"
    local x = m.left and LV_PAD or -LV_PAD
    if m.up then m:SetPoint("BOTTOM" .. h, owner, "TOP" .. h, x, LV_PAD + 3)
    else m:SetPoint("TOP" .. h, owner, "BOTTOM" .. h, x, -(LV_TIME + 6)) end
    m:Show()
end

local function BuildLevel()
    local f = CreateFrame("Frame", "WatchXLeveling", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetSize(LevelWidth(3), LV_H)
    f:SetScale(LevelScale())
    LoadPoint(f, "levelPoint", { "TOPRIGHT", "TOPRIGHT", -240, -440 })
    Flat(f)
    f.icons = {}
    for i = 1, LV_MAX do
        local b = CreateFrame("Button", "WatchXLevelIcon" .. i, f, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
        b:SetAttribute("type1", "macro")   -- left-click: use it; right-click: the menu (PostClick)
        b:SetAttribute("macrotext1", "")
        b:SetSize(LV_ICON, LV_ICON)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", LV_PAD + (i - 1) * (LV_ICON + LV_GAP), -LV_PAD)
        b.border = b:CreateTexture(nil, "BACKGROUND")   -- coloured edge: how it stands
        b.border:SetPoint("TOPLEFT", -2, 2); b.border:SetPoint("BOTTOMRIGHT", 2, -2)
        b.border:SetColorTexture(1, 1, 1, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.flash = b:CreateTexture(nil, "OVERLAY")       -- a red glow that pulses on a missing one
        b.flash:SetAllPoints()
        b.flash:SetColorTexture(1, 0.15, 0.15, 1)
        b.flash:SetAlpha(0)
        b.badge = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.badge:SetSize(13, 13)
        b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 4, 4)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
        b.timer = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.timer:SetPoint("TOP", b, "BOTTOM", 0, -2)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        b:SetScript("OnEnter", function(self) ns.Safe("xp tooltip", function(s) OpenLevelMenu(s); LevelIconTip(s) end, self) end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("PostClick", function(self, button)
            if button == "RightButton" and not InCombatLockdown() and ns.OpenLevelSettings then ns.OpenLevelSettings() end
        end)
        b:Hide()
        f.icons[i] = b
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not moving and ns.OpenLevelSettings then ns.OpenLevelSettings() end
    end)
    f:SetScript("OnEnter", function(self)
        if moving then return end
        Tip(self, "XP boosts", "Extra XP you have, and what you're missing. Hover an icon for how to get it.",
            "|cffffd100Right-click:|r settings  ·  gone at level " .. ns.MaxLevel())
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        SavePoint(self, "levelPoint")
        LevelLabel()
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not moving then return end
        Rescale(self, "levelScale", delta)
        SavePoint(self, "levelPoint")
        LevelLabel()
    end)
    -- the missing ones pulse (a red glow and the icon), about once a second
    local t = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local on = db().levelFlash ~= false and not moving
        local wave = (math.sin(t * 5) + 1) / 2   -- 0..1
        for _, b in ipairs(self.icons) do
            if b.flashing and on then
                b.flash:SetAlpha(0.05 + wave * 0.35)
                b.border:SetAlpha(0.4 + wave * 0.6)
            elseif b.flash:GetAlpha() ~= 0 then
                b.flash:SetAlpha(0)
                b.border:SetAlpha(1)
            end
        end
    end)
    -- any edge only changes the size (the icons keep their shape); the top-left corner stays put
    AddGrips(f, function(self, st, cx, cy)
        local sc
        if st.mode == "R" then sc = ClampScale((cx - st.left) / (self.naturalW or LevelWidth(3)))
        else sc = ClampScale((st.top - cy) / LV_H) end
        db().levelScale = sc
        self:SetScale(sc)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.left / sc, st.top / sc)
        LevelLabel()
    end, function(self) SavePoint(self, "levelPoint") end)
    f:Hide()
    return f
end

-- Looks only (icon, border, numbers, clock) – fine in combat.
local function PaintLevelIcon(b, r)
    b.row = r
    b.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.icon:SetDesaturated(r.state == "info")
    b.icon:SetAlpha(r.state == "info" and 0.6 or 1)
    local c = LV_COLORS[r.state] or LV_COLORS.info
    b.border:SetColorTexture(c[1], c[2], c[3], 1)
    b.badge:SetTexture(LV_BADGES[r.state])
    b.badge:SetAlpha(LV_BADGES[r.state] and 1 or 0)
    b.count:SetText(r.count or "")
    if r.timer then
        b.timer:SetText(ns.Clock(r.timer))
        if r.timer < 120 then b.timer:SetTextColor(1, 0.35, 0.35)
        elseif r.state == "wait" then b.timer:SetTextColor(1, 0.82, 0)
        else b.timer:SetTextColor(0.25, 1, 0.25) end
    else
        b.timer:SetText("")
    end
    b.flashing = r.state == "todo"
    if lvMenu and lvMenu:IsShown() and lvMenu.owner == b then OpenLevelMenu(b) end   -- keep the column current
end

function ns.RefreshLevel()
    if not lv then return end
    local d = db()
    local all = d.levelHelper ~= false and ns.LevelStatus() or nil
    if InCombatLockdown() then
        -- the icons are secure buttons: in a fight they can't be shown, hidden, moved or given a new item,
        -- so only the ones already showing are repainted (it hides just before a fight, see below)
        if lv:IsShown() then
            local bySlot = {}
            for _, r in ipairs(all or {}) do if r.slot then bySlot[r.slot] = r end end
            for _, b in ipairs(lv.icons) do
                local r = b.row and bySlot[b.row.slot]
                if r and b:IsShown() then PaintLevelIcon(b, r) end
            end
        end
        return
    end
    local show = all ~= nil
    if show and not moving and d.levelHideInstance and IsInInstance then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") then show = false end
    end
    local rows = {}
    for _, r in ipairs(all or {}) do
        if not d.levelMissing or r.state == "todo" or r.state == "wait" or moving then rows[#rows + 1] = r end
    end
    if #rows == 0 then show = false end
    if not show then
        lv.painted = nil
        lv:Hide()
        if lvLabel then lvLabel:Hide() end
        if lvMenu then lvMenu:Hide() end
        return
    end
    -- nothing new since last time (the list is worked out once a second): leave it be
    local key = tostring(all) .. tostring(moving) .. tostring(d.levelMissing)
    if lv.painted == key and lv:IsShown() then return end
    lv.painted = key
    for i, b in ipairs(lv.icons) do
        local r = rows[i]
        if r then
            PaintLevelIcon(b, r)
            b:SetAttribute("macrotext1", UseMacro(r.use))
            b:EnableMouse(not moving)   -- while unlocked the whole strip drags
            b:Show()
        else
            b.row, b.flashing = nil, false
            b:SetAttribute("macrotext1", "")
            b:Hide()
        end
    end
    local n = math.min(#rows, LV_MAX)
    lv.naturalW = LevelWidth(n)
    lv:SetSize(lv.naturalW, LV_H)
    lv:Show()
    LevelLabel()
end

-- Hide just before a fight starts (still allowed then), back when it's over.
local lvEvents = CreateFrame("Frame")
lvEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
lvEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
lvEvents:SetScript("OnEvent", function(_, event) ns.Safe("xp boosts", function()
    if not (ns.db and lv) then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if lvMenu then lvMenu:Hide() end
        if db().levelHideCombat ~= false and not moving then
            lv:Hide()
            if lvLabel then lvLabel:Hide() end
        end
    else
        ns.RefreshLevel()
    end
end) end)

function ns.LevelMove(on)
    if not lv then return end
    ShowGrips(lv, on)
    lv:EnableMouseWheel(on and true or false)
    if not on then
        SavePoint(lv, "levelPoint")
        if lvLabel then lvLabel:Hide() end
    end
    ns.RefreshLevel()
    if ns.XPBarMove then ns.XPBarMove(on) end
end

-- ---------------------------------------------------------------- XP bar (until max level)
-- Under the XP boosts icons: your XP with rested, finished quests (orange) and unfinished ones (yellow) on the
-- bar, time this level and this session, XP an hour and when you'll level. A plain frame: shows in combat too.
-- Its own function (not a do-block): UI.lua's main chunk is close to Lua's 200-locals limit.
(function()
    local xb, xbLabel
    local XB_W, XB_H, XB_BAR = 330, 52, 18
    local session = { start = time(), xp = 0 }
    local played = { level = nil, at = nil }
    local quests = { done = 0, todo = 0, at = 0 }
    local lastXP, lastMax

    local function Num(n)
        n = n or 0
        if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
        if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
        return tostring(math.floor(n + 0.5))
    end
    local function Dur(s)
        s = math.max(0, math.floor(s or 0))
        local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
        if d > 0 then return ("%dd %dh"):format(d, h) end
        if h > 0 then return ("%dh %dm"):format(h, m) end
        if m > 0 then return ("%dm %ds"):format(m, s % 60) end
        return s .. "s"
    end
    local function N(v) v = v and (issecretvalue and issecretvalue(v) and nil or v); return tonumber(v) end

    -- XP from the quests in your log: finished ones (hand them in) and the rest.
    -- Two ways, by client: the modern quest log (C_QuestLog: the reward by quest ID) or the classic one (the reward
    -- of the selected quest: each one is selected in turn and your selection put back, skipped while the quest log
    -- is open so nothing jumps under your mouse).
    local function ScanQuests()
        quests.at = GetTime()
        local done, todo = 0, 0
        local Q = C_QuestLog
        if Q and Q.GetInfo and Q.GetNumQuestLogEntries and GetQuestLogRewardXP then
            local n = N(Q.GetNumQuestLogEntries()) or 0
            for i = 1, n do
                local ok, info = pcall(Q.GetInfo, i)
                local id = ok and type(info) == "table" and not info.isHeader and not info.isHidden and N(info.questID)
                if id then
                    local okx, v = pcall(GetQuestLogRewardXP, id)
                    local xp = okx and N(v) or 0
                    local okc, c = pcall(Q.IsComplete or function() return info.isComplete end, id)
                    if okc and (c == true or c == 1) then done = done + xp else todo = todo + xp end
                end
            end
        elseif GetQuestLogTitle and GetQuestLogRewardXP and SelectQuestLogEntry and GetQuestLogSelection then
            if QuestLogFrame and QuestLogFrame:IsShown() then return end
            local n = N(GetNumQuestLogEntries and (GetNumQuestLogEntries())) or 0
            local sel = N(GetQuestLogSelection()) or 0
            for i = 1, n do
                local ok, title, _, _, isHeader, _, isComplete = pcall(GetQuestLogTitle, i)
                if ok and title and not isHeader then
                    pcall(SelectQuestLogEntry, i)
                    local okx, v = pcall(GetQuestLogRewardXP)
                    local xp = okx and N(v) or 0
                    if isComplete == 1 or isComplete == true then done = done + xp else todo = todo + xp end
                end
            end
            pcall(SelectQuestLogEntry, sel)
        else
            return
        end
        quests.done, quests.todo = done, todo
    end

    local function Seg(parent, layer, r, g, b, a)
        local t = parent:CreateTexture(nil, layer)
        t:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        t:SetVertexColor(r, g, b, a or 1)
        t:Hide()
        return t
    end
    local function Place(t, x0, x1, bar)
        if x1 - x0 < 0.5 then t:Hide() return end
        bar = bar or xb.bar
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", bar, "TOPLEFT", x0, 0)
        t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x0, 0)
        t:SetWidth(x1 - x0)
        t:Show()
    end
    -- Blizzard's XP colours: blue while you have rested, purple without; rested a darker blue. Quests in soft gold.
    local XP_RESTED, XP_NORMAL = { 0.0, 0.39, 0.88 }, { 0.58, 0.0, 0.55 }
    local function Ticks(parent, layer)   -- the nine marks every 10 %, like Blizzard's bar
        local t = {}
        for i = 1, 9 do
            local tex = parent:CreateTexture(nil, layer or "OVERLAY")
            tex:SetColorTexture(0, 0, 0, 0.55)
            tex:SetWidth(1)
            t[i] = tex
        end
        return t
    end
    local function PlaceTicks(ticks, bar, w)
        for i, tex in ipairs(ticks) do
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", bar, "TOPLEFT", math.floor(w * i / 10 + 0.5), 0)
            tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", math.floor(w * i / 10 + 0.5), 0)
        end
    end
    local function ShowXPTip(owner, d, settingsLine)
        if not d then return end
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText("XP – level " .. d.level)
        GameTooltip:AddDoubleLine("XP", Num(d.cur) .. " / " .. Num(d.max) .. ("  (%.1f%%, "):format(d.cur / d.max * 100) .. Num(d.max - d.cur) .. " to go)", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Rested", Num(d.rested) .. ("  (%.1f%%)"):format(d.rested / d.max * 100), 0.3, 0.6, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Finished quests", Num(quests.done) .. ("  (with them: %.1f%%)"):format(math.min(100, (d.cur + quests.done) / d.max * 100)), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Unfinished quests", Num(quests.todo), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Time this level", played.level and Dur(played.level + time() - played.at) or "–", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("This session", Num(session.xp) .. " XP in " .. Dur(time() - session.start), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("XP an hour", d.rate and Num(d.rate) or "–", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Level in", d.rate and Dur((d.max - d.cur) / d.rate * 3600) or "– (kill something first)", 1, 0.82, 0, 1, 1, 1)
        if settingsLine then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100Right-click:|r settings", 1, 1, 1)
        end
        GameTooltip:Show()
    end

    local function Build()
        local f = CreateFrame("Frame", "WatchXXPBar", UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:SetSize(db().xpBarWidth or XB_W, XB_H)
        f:SetScale(ClampScale(db().xpBarScale))
        Flat(f)
        f.top1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.top1:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -5)
        f.top2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.top2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -7, -5)
        f.bar = CreateFrame("Frame", nil, f)
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -18)
        f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -18)
        f.bar:SetHeight(XB_BAR)
        local back = f.bar:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0.08, 0.06, 0.04, 0.9)
        f.rest = Seg(f.bar, "BORDER", 0.0, 0.25, 0.6, 0.6)       -- rested: the darker blue
        f.todo = Seg(f.bar, "ARTWORK", 1, 0.82, 0, 0.18)          -- unfinished quests
        f.done = Seg(f.bar, "ARTWORK", 1, 0.82, 0, 0.5)           -- finished quests
        f.cur = Seg(f.bar, "ARTWORK", XP_RESTED[1], XP_RESTED[2], XP_RESTED[3], 1)   -- your XP
        f.cur:SetDrawLayer("ARTWORK", 2)
        f.ticks = Ticks(f.bar, "ARTWORK")
        for _, t in ipairs(f.ticks) do t:SetDrawLayer("ARTWORK", 3) end
        local edge = CreateFrame("Frame", nil, f.bar)
        edge:SetAllPoints()
        edge:SetFrameLevel(f.bar:GetFrameLevel() + 1)
        if Backdrop(edge, { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 }) then
            edge:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 0.9)
        end
        f.lvl = edge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.lvl:SetPoint("LEFT", f.bar, "LEFT", 6, 0)
        f.mid = edge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.mid:SetPoint("CENTER", f.bar, "CENTER", 0, 0)
        f.pct = edge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.pct:SetPoint("RIGHT", f.bar, "RIGHT", -6, 0)
        f.bot1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.bot1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 7, 5)
        f.bot2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.bot2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -7, 5)
        f.bot2:SetPoint("LEFT", f.bot1, "RIGHT", 8, 0)
        f.bot2:SetJustifyH("RIGHT")
        f.bot2:SetWordWrap(false)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) if moving and not self.compact then self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self)
            if self.compact then return end
            self:StopMovingOrSizing()
            if ns.Snap then ns.Snap(self) end
            SavePoint(self, "xpBarPoint")
            ns.RefreshXPBar()
        end)
        f:SetScript("OnMouseUp", function(_, button)
            if button ~= "RightButton" then return end
            if moving then ns.ResetXPBar() elseif ns.OpenLevelSettings then ns.OpenLevelSettings() end
        end)
        f:SetScript("OnEnter", function(self)
            if not moving then ShowXPTip(self, self.data, true) end
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        AddGrips(f, function(self, st, cx, cy)
            SizeTo(self, st, cx, cy, XB_H, "xpBarScale", "xpBarWidth")
            self:SetWidth(db().xpBarWidth or XB_W)
            ns.RefreshXPBar()
        end, function(self) SavePoint(self, "xpBarPoint") end)
        f:Hide()
        return f
    end

    -- On Blizzard's own XP bar: found by what it shows (a status bar with your XP as value and max), so it works
    -- whatever the frame is called. Our marks sit on a frame of our own laid over it (nothing is added to theirs).
    local blizz, ov, lastLook = nil, nil, 0
    local function IsXPBar(f, cur, max)
        if not (f and f.GetObjectType and f:GetObjectType() == "StatusBar" and f:IsVisible()) then return false end
        local ok, _, hi = pcall(f.GetMinMaxValues, f)
        local okv, v = pcall(f.GetValue, f)
        return ok and okv and N(hi) == max and N(v) == cur
    end
    local function FindBlizzBar(cur, max)
        if MainMenuExpBar and IsXPBar(MainMenuExpBar, cur, max) then return MainMenuExpBar end
        local function walk(f, depth)
            if IsXPBar(f, cur, max) then return f end
            if depth >= 5 or not f.GetChildren then return end
            for _, c in ipairs({ f:GetChildren() }) do
                local r = walk(c, depth + 1)
                if r then return r end
            end
        end
        for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
                                "StatusTrackingBarManager", "MainMenuBar", "MainActionBar" }) do
            local f = _G[name]
            if f then
                local r = walk(f, 0)
                if r then return r end
            end
        end
    end
    local function BlizzBar(cur, max)
        if blizz and blizz:IsVisible() then return blizz end
        if GetTime() - lastLook < 10 then return nil end   -- not every second
        lastLook = GetTime()
        blizz = FindBlizzBar(cur, max)
        return blizz
    end
    local function Overlay(bar)
        if ov then
            if ov.bar ~= bar then ov:ClearAllPoints(); ov:SetAllPoints(bar); ov.bar = bar end
            return ov
        end
        ov = CreateFrame("Frame", "WatchXXPOverlay", UIParent)
        ov:SetAllPoints(bar)
        ov.bar = bar
        ov:SetFrameStrata(bar:GetFrameStrata() or "MEDIUM")
        -- above the bar's own marks and frame (they sit on frames a few levels up)
        local top = bar:GetFrameLevel() or 1
        local parent = bar:GetParent()
        for _, c in ipairs(parent and parent.GetChildren and { parent:GetChildren() } or {}) do
            top = math.max(top, c.GetFrameLevel and c:GetFrameLevel() or 0)
        end
        ov:SetFrameLevel(math.min(9000, top + 20))
        ov.done = Seg(ov, "ARTWORK", 1, 0.82, 0, 0.45)
        ov.todo = Seg(ov, "ARTWORK", 1, 0.82, 0, 0.15)
        -- the text on a soft dark band, outlined, so the marks under it don't cut through the letters
        ov.band = ov:CreateTexture(nil, "BORDER")
        ov.band:SetPoint("TOP", ov, "TOP", 0, 0)
        ov.band:SetPoint("BOTTOM", ov, "BOTTOM", 0, 0)
        ov.band:SetColorTexture(0, 0, 0, 0.55)
        ov.text = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local font, size = ov.text:GetFont()
        if font then ov.text:SetFont(font, math.max(10, math.min(12, (ov:GetHeight() or 12) - 1)), "OUTLINE") end
        ov.text:SetPoint("CENTER", ov, "CENTER", 0, 0)
        ov.text:SetShadowOffset(0, 0)
        ov:EnableMouse(true)
        ov:SetScript("OnEnter", function(self) ShowXPTip(self, self.data, true) end)
        ov:SetScript("OnLeave", GameTooltip_Hide)
        ov:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and ns.OpenLevelSettings then ns.OpenLevelSettings() end
        end)
        return ov
    end

    -- Compact (under the Nearby list): just the bar; the rest is in the tooltip.
    local XB_SMALL = 12   -- the bar's height in the compact one
    local function Layout(compact)
        if xb.compact == compact then return end
        xb.compact = compact
        for _, fs in ipairs({ xb.top1, xb.top2, xb.bot1, xb.bot2, xb.mid }) do fs:SetShown(not compact) end
        for _, fs in ipairs({ xb.lvl, xb.pct }) do fs:SetFontObject(compact and "GameFontHighlightSmall" or "GameFontHighlight") end
        xb.bar:ClearAllPoints()
        local y = compact and -4 or -18
        xb.bar:SetPoint("TOPLEFT", xb, "TOPLEFT", compact and 4 or 6, y)
        xb.bar:SetPoint("TOPRIGHT", xb, "TOPRIGHT", compact and -4 or -6, y)
        xb.bar:SetHeight(compact and XB_SMALL or XB_BAR)
        xb:SetHeight(compact and (XB_SMALL + 8) or XB_H)
    end
    -- the room it takes in the stack under the mini bar (for the Nearby list under it)
    function ns.XPBarSlot()
        if xb and xb.compact and xb:IsShown() then return (xb:GetHeight() or 0) + 1 end
        return 0
    end
    local function Position()
        xb:ClearAllPoints()
        xb.attachedTo = nil
        if db().xpBarAttach and mini and ns.UnderMini then   -- between the mini bar and the Nearby list
            xb.attachedTo = mini
            xb:SetScale(mini:GetScale() or 1)
            xb:SetWidth(ns.StackWidth())
            ns.UnderMini(xb, 0)
            return
        end
        xb:SetScale(ClampScale(db().xpBarScale))
        xb:SetWidth(db().xpBarWidth or XB_W)
        if db().xpBarPoint then
            LoadPoint(xb, "xpBarPoint", { "TOP", "TOP", 0, -200 })
        elseif lv then   -- under the XP boosts icons until you move it
            xb:SetPoint("TOPLEFT", lv, "BOTTOMLEFT", 0, -4)
        else
            LoadPoint(xb, "xpBarPoint", { "TOPRIGHT", "TOPRIGHT", -240, -500 })
        end
    end

    function ns.RefreshXPBar()
        if not ns.db then return end
        local d = db()
        local level = N(UnitLevel("player")) or 0
        local show = d.xpBar ~= false and level > 0 and level < (ns.MaxLevel and ns.MaxLevel() or 60)
        if show and not moving and d.levelHideInstance and IsInInstance then
            local inside, kind = IsInInstance()
            if inside and (kind == "party" or kind == "raid") then show = false end
        end
        local function HideOwn()
            if xb and xb:IsShown() then
                xb:Hide()
                if xb.compact and ns.AttachNearby then ns.AttachNearby() end
            end
            if xbLabel then xbLabel:Hide() end
        end
        if not show then
            HideOwn()
            if ov then ov:Hide() end
            return
        end
        local cur, max = N(UnitXP("player")) or 0, N(UnitXPMax("player")) or 1
        if max <= 0 then max = 1 end
        local rested = N(GetXPExhaustion and GetXPExhaustion()) or 0
        if GetTime() - quests.at > 30 then ScanQuests() end
        local now = time()
        local spent = now - session.start
        local rate = (session.xp > 0 and spent > 60) and (session.xp / spent * 3600) or nil
        local data = { level = level, cur = cur, max = max, rested = rested, rate = rate }
        if d.xpBarBlizz ~= false and not moving and blizz and not blizz:IsVisible() then
            HideOwn()   -- the game hid its bar (a vehicle, a cutscene): so do we, rather than pop ours up
            if ov then ov:Hide() end
            return
        end
        local bar = d.xpBarBlizz ~= false and not moving and BlizzBar(cur, max)
        if bar then
            HideOwn()
            local o = Overlay(bar)
            local w = bar:GetWidth() or 0
            local function X(v) return math.min(w, math.max(0, v / max * w)) end
            Place(o.done, X(cur), X(cur + quests.done), o)
            Place(o.todo, X(cur + quests.done), X(cur + quests.done + quests.todo), o)
            o.data = data
            o.text:SetText(("%.1f%%  |cffcccccc%s to go|r"):format(cur / max * 100, Num(max - cur))
                .. (rested > 0 and ("   |cff80b8ffrested %s|r"):format(Num(rested)) or "")
                .. (quests.done > 0 and ("   |cffffd100+%s quests|r"):format(Num(quests.done)) or "")
                .. (rate and ("   |cffcccccc%s|r"):format(Dur((max - cur) / rate * 3600)) or ""))
            o.band:SetWidth((o.text:GetStringWidth() or 100) + 24)
            o:Show()
            return
        end
        if ov then ov:Hide() end
        if not xb then xb = Build() end
        local compact = d.xpBarAttach and true or false
        Layout(compact)
        local key = compact and (ns.StackKey() .. math.floor(ns.StackWidth() + 0.5) .. tostring(mini and mini:GetScale())) or "own"
        local wasShown = xb:IsShown()
        if xb.placedKey ~= key then
            xb.placedKey = key
            Position()
        end
        local w = xb.bar:GetWidth() or 300
        local function X(v) return math.min(w, math.max(0, v / max * w)) end
        local c = rested > 0 and XP_RESTED or XP_NORMAL
        xb.cur:SetVertexColor(c[1], c[2], c[3], 1)
        PlaceTicks(xb.ticks, xb.bar, w)
        Place(xb.cur, 0, X(cur))
        Place(xb.done, X(cur), X(cur + quests.done))
        Place(xb.todo, X(cur + quests.done), X(cur + quests.done + quests.todo))
        Place(xb.rest, X(cur), X(cur + rested))
        xb.data = data
        xb.lvl:SetText(compact and ("Lvl " .. level) or ("Level " .. level))
        xb.mid:SetText(Num(cur) .. " / " .. Num(max) .. "  |cffffd100(" .. Num(max - cur) .. ")|r")
        xb.pct:SetText(("%.1f%%"):format(cur / max * 100)
            .. ((quests.done > 0 and not compact) and ("  |cffffa020(%.1f%%)|r"):format(math.min(100, (cur + quests.done) / max * 100)) or ""))
        xb.top1:SetText("This level: |cffffd100" .. (played.level and Dur(played.level + now - played.at) or "–") .. "|r")
        xb.top2:SetText("Session: |cffffd100" .. Dur(spent) .. "|r  ·  +" .. Num(session.xp) .. " XP"
            .. (rate and ("  ·  " .. Num(rate) .. "/h") or ""))
        xb.bot1:SetText("Level in: |cffffd100" .. (rate and Dur((max - cur) / rate * 3600) or "–") .. "|r")
        xb.bot2:SetText(("|cffffd100Done %s|r  ·  |cffbfa060Quests %s|r  ·  |cff80b8ffRested %s (%.0f%%)|r"):format(
            Num(quests.done), Num(quests.todo), Num(rested), rested / max * 100))
        xb:EnableMouse(true)
        xb:Show()
        if compact and not wasShown and ns.AttachNearby then ns.AttachNearby() end   -- make room under it
        if moving and not compact then
            xbLabel = xbLabel or MakeLabel("WatchXXPBarLabel")
            xbLabel:Set(xb, "|cffffd100XP bar|r · drag to move · right edge: width · bottom edge: text size · right-click: back under the icons")
        elseif xbLabel then
            xbLabel:Hide()
        end
    end

    -- the mini bar or the red bar changed: the compact one moves with them at once (not on its next tick)
    function ns.PlaceXPBar()
        if xb and xb.compact and xb:IsShown() then Position() end
    end

    function ns.XPBarMove(on)
        if not xb then return end
        ShowGrips(xb, on and not xb.compact)
        if not on and not xb.compact then SavePoint(xb, "xpBarPoint") end
        ns.RefreshXPBar()
    end
    function ns.ResetXPBar()
        local d = db()
        d.xpBarPoint, d.xpBarWidth, d.xpBarScale = nil, nil, nil
        if xb then xb:SetScale(1); xb:SetWidth(XB_W); Position() end
        ns.RefreshXPBar()
    end

    -- XP this session (level-ups included), time this level (/played, without the chat lines), quests.
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
                         "QUEST_LOG_UPDATE", "TIME_PLAYED_MSG" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local asked
    -- the clocks on it, once a second (cheap: quests every 30 s, looking for Blizzard's bar every 10 s until found)
    local tick = 0
    ev:SetScript("OnUpdate", function(_, elapsed)
        tick = tick + elapsed
        if tick >= 1 then tick = 0; ns.Safe("xp bar", ns.RefreshXPBar) end
    end)
    ev:SetScript("OnEvent", function(_, event, a1, a2) ns.Safe("xp bar", function()
        if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then
            local cur, max = N(UnitXP("player")) or 0, N(UnitXPMax("player")) or 0
            if lastXP then
                local gain = (cur >= lastXP) and (cur - lastXP) or ((lastMax or 0) - lastXP + cur)
                if gain > 0 and gain < max * 2 then session.xp = session.xp + gain end
            end
            lastXP, lastMax = cur, max
            if event == "PLAYER_LEVEL_UP" then played.level, played.at = 0, time() end
            if event == "PLAYER_ENTERING_WORLD" and not asked and RequestTimePlayed then
                asked = true
                C_Timer.After(4, function()
                    -- ask quietly: the game prints /played to chat, so that one answer is kept out of it
                    local orig = ChatFrame_DisplayTimePlayed
                    if orig then ChatFrame_DisplayTimePlayed = function() end end
                    pcall(RequestTimePlayed)
                    C_Timer.After(3, function() if orig and ChatFrame_DisplayTimePlayed ~= orig then ChatFrame_DisplayTimePlayed = orig end end)
                end)
            end
        elseif event == "TIME_PLAYED_MSG" then
            local lvlTime = N(a2)
            if lvlTime then played.level, played.at = lvlTime, time() end
        elseif event == "QUEST_LOG_UPDATE" then
            quests.at = 0
        end
        ns.RefreshXPBar()
    end) end)
end)()

-- Settings > WatchX > XP boosts
local levelPage, levelCategory
function ns.OpenLevelSettings()
    if levelCategory and Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, levelCategory:GetID())
    elseif levelPage and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, levelPage)
        pcall(InterfaceOptionsFrame_OpenToCategory, levelPage)
    else
        ns.OpenSettings()
    end
end

function ns.BuildLevelSettings()
    local page = CreateFrame("Frame", "WatchXLevelOptions", UIParent)
    page.name, page.parent = "XP boosts", "WatchX"
    page:Hide()
    local L, W = 20, 560
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
    title:SetText("XP boosts")
    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("what gives you extra XP, and what you're missing  ·  until level " .. ns.MaxLevel())
    local y, checks = -50, {}
    local function check(label, hint, get, set)
        local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", page, "TOPLEFT", L - 4, y + 2)
        local name = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        name:SetText(label .. (hint and ("  |cff808080" .. hint .. "|r") or ""))
        cb.get = get
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            self:SetChecked(get())
            ns.RefreshUI()
        end)
        checks[#checks + 1] = cb
        y = y - 28
    end
    check("Show the XP boosts icons", "on every character below level " .. ns.MaxLevel(),
        function() return db().levelHelper ~= false end, function(v) db().levelHelper = v end)
    check("Only what's missing", "hides what you have and the grey tips (and the icons when all is set)",
        function() return db().levelMissing == true end, function(v) db().levelMissing = v end)
    check("Flash what's missing", "the missing icons pulse red",
        function() return db().levelFlash ~= false end, function(v) db().levelFlash = v end)
    check("Warn when a boost runs out", "mid-screen + sound: Well Fed, Well-Rested, tent and bag ready again",
        function() return db().levelWarn ~= false end, function(v) db().levelWarn = v end)
    check("XP bar", "under the icons: XP, rested, quests, time this level, when you'll level",
        function() return db().xpBar ~= false end, function(v) db().xpBar = v; ns.RefreshXPBar() end)
    check("On Blizzard's own XP bar", "the text and the quest marks on the game's bar (off, or not found: WatchX's own)",
        function() return db().xpBarBlizz ~= false end,
        function(v) db().xpBarBlizz = v; ns.RefreshXPBar(); if ns.AttachNearby then ns.AttachNearby() end end)
    check("XP bar between the mini bar and Nearby", "just level and %, same width – the rest when you hover it",
        function() return db().xpBarAttach == true end,
        function(v) db().xpBarAttach = v; ns.RefreshXPBar(); if ns.AttachNearby then ns.AttachNearby() end end)
    check("Hide in combat", "the icons (the XP bar stays)",
        function() return db().levelHideCombat ~= false end, function(v) db().levelHideCombat = v end)
    check("Hide in dungeons and raids", nil,
        function() return db().levelHideInstance == true end, function(v) db().levelHideInstance = v end)
    y = y - 8
    local mv = Button(page, "Move / resize", 130, 24, function()
        HideBlizzardMenus()
        db().levelHelper = true
        ns.StartMove()
        if panel and not panel:IsShown() then ns.TogglePanel() end   -- its Lock button locks them again
    end)
    mv:SetPoint("TOPLEFT", page, "TOPLEFT", L, y)
    y = y - 44
    local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOPLEFT", page, "TOPLEFT", L, y)
    help:SetWidth(W)
    help:SetJustifyH("LEFT")
    help:SetSpacing(4)
    help:SetText(table.concat({
        "|cffffd100WHAT IT CHECKS|r",
        "|cffaaaaaa•|r  |cffffd100Camp Tent|r – at a campfire, tops rested up to 5% of a level. Then |cffffd100Boosted Rest|r: 1 hour wait.",
        "|cffaaaaaa•|r  |cffffd100Well Fed|r – XP food, +5% kill XP for about 15 minutes. Gone when you die.",
        "|cffaaaaaa•|r  |cffffd100XP food|r – food whose tooltip says \"Experience gained from kills is increased\". None left: a warning.",
        "|cffaaaaaa•|r  |cffffd100Cozy Sleeping Bag|r – lie on it: +1% XP a minute, up to +3%. A quest chain from level 14.",
        "",
        "Border: |cff40ff40green|r you have it    |cffff6060red|r missing    |cffffd100yellow|r soon or running out    "
            .. "|cffaaaaaagrey|r worth getting",
        "The clock under an icon is the time left, the number on it how many you carry. When something runs out",
        "you get a warning mid-screen. Hover an icon for what it is and how to get it. The numbers come from the",
        "Forever guides and may change.",
        "",
        "|cffffd100CLICKS|r",
        "|cffaaaaaa•|r  |cffffd100Hover|r an icon: everything you can use for it pops up in a column above it – your XP food,",
        "    campfires, tent and other camp features. Click one to use it now (right-click: just pick it).",
        "|cffaaaaaa•|r  |cffffd100Click|r an icon: eat the food or use the sleeping bag. The camp icon puts the campfire down",
        "    first (unless there's one close by) – click again for your tent or the camp feature you picked.",
        "Not in combat: the icons hide just before a fight and come back after it.",
        "",
        "|cff808080/wx xp – the icons on or off|r",
    }, "\n"))
    page:SetScript("OnShow", function() for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end end)
    levelPage = page
    if settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutSubcategory, settingsCategory, page, "XP boosts")
        if ok and cat then levelCategory = cat end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
end

do   -- (its own block: UI.lua is near Lua's 200-locals limit)
-- Settings > WatchX > Buff warnings
local buffPage, buffCategory
function ns.OpenBuffSettings()
    if buffCategory and Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, buffCategory:GetID())
    elseif buffPage and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, buffPage)
        pcall(InterfaceOptionsFrame_OpenToCategory, buffPage)
    else
        ns.OpenSettings()
    end
end

local BUFF_SOON = { 0, 10, 15, 30, 60, 120, 300, 600 }
local BUFF_LIST_ROWS = 12   -- two columns of 6
function ns.BuildBuffSettings()
    local page = CreateFrame("Frame", "WatchXBuffOptions", UIParent)
    page.name, page.parent = "Buff warnings", "WatchX"
    page:Hide()
    local L, W = 20, 560
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
    title:SetText("Buff warnings")
    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("a warning before a buff runs out, and when it has")
    local y, checks = -46, {}
    local Refresh
    local function check(label, hint, get, set)
        local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", page, "TOPLEFT", L - 4, y + 2)
        local name = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        name:SetText(label .. (hint and ("  |cff808080" .. hint .. "|r") or ""))
        cb.get = get
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            self:SetChecked(get())
        end)
        checks[#checks + 1] = cb
        y = y - 26
    end
    local function heading(text)
        y = y - 8
        local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", page, "TOPLEFT", L - 4, y)
        h:SetText(text)
        h:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        local line = page:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3)
        line:SetHeight(1)
        line:SetPoint("LEFT", h, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", page, "TOPLEFT", L + W, 0)
        y = y - 20
    end
    local function groups() local d = db(); if type(d.buffGroups) ~= "table" then d.buffGroups = {} end return d.buffGroups end

    check("Buff warnings", "mid-screen + sound + chat, also in combat",
        function() return db().buffWarn ~= false end, function(v) db().buffWarn = v end)
    -- warn [-] 1:00 [+] before it runs out
    local soonLab = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    soonLab:SetPoint("TOPLEFT", page, "TOPLEFT", L + 2, y - 4)
    soonLab:SetText("Warn before it runs out")
    local soonVal
    local function stepSoon(dir)
        local cur, at = tonumber(db().buffSoon) or 60, 1
        for i, v in ipairs(BUFF_SOON) do if v <= cur then at = i end end
        at = math.max(1, math.min(#BUFF_SOON, at + dir))
        db().buffSoon = BUFF_SOON[at]
        Refresh()
    end
    local sminus = FlatButton(page, "-", 22, 20, function() stepSoon(-1) end)
    sminus:SetPoint("TOPLEFT", page, "TOPLEFT", L + 180, y - 1)
    soonVal = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    soonVal:SetPoint("LEFT", sminus, "RIGHT", 6, 0)
    soonVal:SetWidth(36)
    local splus = FlatButton(page, "+", 22, 20, function() stepSoon(1) end)
    splus:SetPoint("LEFT", soonVal, "RIGHT", 6, 0)
    local soonHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    soonHint:SetPoint("LEFT", splus, "RIGHT", 8, 0)
    soonHint:SetText("off = only when it's gone")
    y = y - 28
    check("Warn when it has run out", nil,
        function() return db().buffGone ~= false end, function(v) db().buffGone = v end)
    local test = Button(page, "Test", 70, 22, function() ns.BuffTest() end)
    test:SetPoint("TOPLEFT", page, "TOPLEFT", L, y - 2)
    y = y - 30

    heading("WHAT TO WATCH")
    check("Underwater breathing", "Water Breathing, Unending Breath, the elixirs and potions",
        function() return groups().breath ~= false end, function(v) groups().breath = v end)
    check("Potions, elixirs, flasks and scrolls", "anything you used from your bags, 1 min or longer",
        function() return groups().consumables ~= false end, function(v) groups().consumables = v end)
    check("Your own buffs", "armors, shields, Inner Fire … (5 min or longer)",
        function() return groups().own == true end, function(v) groups().own = v end)
    check("Buffs from others", "Fortitude, Arcane Intellect, Mark of the Wild … (5 min or longer)",
        function() return groups().others == true end, function(v) groups().others = v end)

    heading("YOUR OWN LIST")
    local eb = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    eb:SetSize(220, 20)
    eb:SetPoint("TOPLEFT", page, "TOPLEFT", L + 6, y)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(60)
    eb.hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eb.hint:SetPoint("LEFT", eb, "LEFT", 2, 0)
    eb.hint:SetText("Buff name or spell ID")
    local function go()
        local t = ns.Trim(eb:GetText())
        if t ~= "" then ns.AddBuffWatch(t); eb:SetText("") end
        eb:ClearFocus()
        eb.hint:SetShown(eb:GetText() == "")
        Refresh()
    end
    eb:SetScript("OnEnterPressed", go)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    eb:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    local add = Button(page, "Add", 60, 22, go)
    add:SetPoint("LEFT", eb, "RIGHT", 6, 0)

    -- "From my buffs": the buffs you have now – click one to put it on (or take it off) your list
    local pick
    local function OpenPick(owner)
        if pick and pick:IsShown() then pick:Hide() return end
        if InCombatLockdown() then ns.Print("Your buffs can't be read in combat – try again after the fight.") return end
        if not pick then
            pick = CreateFrame("Frame", nil, page)
            pick:SetFrameStrata("DIALOG")
            pick:SetWidth(230)
            Flat(pick)
            pick:EnableMouse(true)
            pick.title = pick:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pick.title:SetPoint("TOPLEFT", pick, "TOPLEFT", 8, -6)
            pick.title:SetText("Click a buff to watch it")
            pick.rows = {}
            local away = 0
            pick:SetScript("OnShow", function() away = 0 end)
            pick:SetScript("OnUpdate", function(self, el)
                if Hovered(self) or Hovered(owner) then away = 0 return end
                away = away + el
                if away > 1.5 then self:Hide() end
            end)
        end
        local list = ns.ReadBuffs()
        for i = 1, math.max(#list, #pick.rows) do
            local r = pick.rows[i]
            local a = list[i]
            if a and i <= 24 then
                if not r then
                    r = CreateFrame("Button", nil, pick)
                    r:SetHeight(18)
                    r:SetPoint("TOPLEFT", pick, "TOPLEFT", 4, -20 - (i - 1) * 18)
                    r:SetPoint("TOPRIGHT", pick, "TOPRIGHT", -4, -20 - (i - 1) * 18)
                    local hl = r:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 1, 1, 0.12)
                    r.icon = r:CreateTexture(nil, "ARTWORK")
                    r.icon:SetSize(16, 16)
                    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
                    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                    r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                    r.text:SetJustifyH("LEFT")
                    r.text:SetWordWrap(false)
                    r:SetScript("OnClick", function(self)
                        local at = ns.BuffOnList(self.buff.name, self.buff.sid)
                        if at then ns.RemoveBuffWatch(at) else ns.AddBuffWatch(self.buff.name) end
                        pick:Hide()
                        Refresh()
                    end)
                    pick.rows[i] = r
                end
                r.buff = a
                r.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local on = ns.BuffOnList(a.name, a.sid)
                local g = not on and ns.BuffGroup(a)
                r.text:SetText((on and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or "") .. a.name
                    .. (g and "  |cff808080(watched already)|r" or "")
                    .. ((a.dur or 0) > 0 and "" or "  |cff808080(no time limit)|r"))
                r:Show()
            elseif r then
                r:Hide()
            end
        end
        pick.empty = pick.empty or pick:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        pick.empty:SetPoint("TOPLEFT", pick, "TOPLEFT", 8, -22)
        pick.empty:SetText("You have no buffs right now.")
        pick.empty:SetShown(#list == 0)
        pick:SetHeight(26 + math.max(1, math.min(#list, 24)) * 18)
        pick:ClearAllPoints()
        pick:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
        pick:Show()
    end
    local mine
    mine = Button(page, "From my buffs", 120, 22, function() OpenPick(mine) end)
    mine:SetPoint("LEFT", add, "RIGHT", 6, 0)
    y = y - 30

    -- the list: two columns, a red x to take one off
    local rows = {}
    for i = 1, BUFF_LIST_ROWS do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local r = CreateFrame("Frame", nil, page)
        r:SetSize(260, 20)
        r:SetPoint("TOPLEFT", page, "TOPLEFT", L + col * 275, y - row * 22)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
        r.del = FlatButton(r, "|cffff6060x|r", 18, 18, function(self)
            ns.RemoveBuffWatch(self:GetParent().index)
            Refresh()
        end)
        r.del:SetPoint("RIGHT", r, "RIGHT", -1, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.text:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:Hide()
        rows[i] = r
    end
    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", page, "TOPLEFT", L + 2, y - 3)
    empty:SetText("Nothing yet – type a buff's name above, or pick one of yours.")
    local more = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    more:SetPoint("TOPLEFT", page, "TOPLEFT", L + 2, y - (BUFF_LIST_ROWS / 2) * 22 - 2)
    y = y - (BUFF_LIST_ROWS / 2) * 22 - 22

    local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", page, "TOPLEFT", L, y)
    help:SetWidth(W)
    help:SetJustifyH("LEFT")
    help:SetSpacing(3)
    help:SetText(table.concat({
        "|cffaaaaaaThe name as it shows on the buff (any case), or its spell ID. The list is the same for all profiles.",
        "Your buffs can't be seen in combat on Forever: in a fight it goes by the clock, so a buff renewed mid-fight",
        "may get a warning it didn't need. A buff you click off or that's dispelled gives no warning.|r",
        "|cff808080/wx buffs – this page   ·   /wx buffs <name> – add one   ·   /wx buffs test – a test warning|r",
    }, "\n"))

    Refresh = function()
        for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end
        local s = tonumber(db().buffSoon) or 60
        soonVal:SetText(s == 0 and "off" or ns.Clock(s))
        local list = db().buffCustom or {}
        for i, r in ipairs(rows) do
            local c = list[i]
            if c then
                r.index = i
                local id = tonumber(c)
                r.text:SetText(id and ((ns.SpellName and ns.SpellName(id) or ("Spell " .. id)) .. "  |cff808080#" .. id .. "|r") or tostring(c))
                r:Show()
            else
                r:Hide()
            end
        end
        empty:SetShown(#list == 0)
        more:SetText(#list > BUFF_LIST_ROWS and ("+" .. (#list - BUFF_LIST_ROWS) .. " more (take some off to see them)") or "")
    end
    page:SetScript("OnShow", function() Refresh() end)
    page:SetScript("OnHide", function() if pick then pick:Hide() end end)
    buffPage = page
    if settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutSubcategory, settingsCategory, page, "Buff warnings")
        if ok and cat then buffCategory = cat end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
end
end

do   -- (its own block: UI.lua is near Lua's 200-locals limit)
-- ---------------------------------------------------------------- nameplate icons (WatchX > Nearby)
-- A class icon over enemy (and, if ticked, friendly) players' nameplates, with a green + on proven healers
-- (ns.Role in WatchX.lua: talents, group role, or a spell only a healing talent gives).
-- It's a plain frame parented to Blizzard's nameplate (like Questie's quest icons and DoesItDie's marker), so it
-- moves, scales and hides with the plate. Plates are recycled between units, so each one is checked again when
-- it shows a new unit. Hidden or unreadable values (Forever's secrets) just mean no icon.
local CLASS_COORDS = {   -- Interface\TargetingFrame\UI-Classes-Circles, if the client has no CLASS_ICON_TCOORDS
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 }, DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
}
local PLATE_ICON = 22   -- the size the healer + is drawn for; it's scaled with the icon
function ns.PlateSize() return math.max(12, math.min(40, tonumber(db().plateSize) or PLATE_ICON)) end
local plateIcons, plateUnits = {}, {}   -- nameplate frame -> icon; nameplate unit -> true while it's up

local function Readable(v)
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return nil end
    end
    return v
end

local function PlateFor(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or type(plate) ~= "table" then return end
    local okF, forbidden = pcall(function() return plate.IsForbidden and plate:IsForbidden() end)
    if not okF or forbidden then return end
    return plate
end

local function PlateIcon(plate)
    local f = plateIcons[plate]
    if f then return f end
    f = CreateFrame("Frame", nil, plate)
    f:SetSize(PLATE_ICON, PLATE_ICON)
    f:SetPoint("BOTTOM", plate, "TOP", 0, 0)
    pcall(f.SetFrameLevel, f, (plate:GetFrameLevel() or 0) + 20)
    -- KOS: a red disc behind the round class icon (a red ring around it) and a skull on its upper left
    f.kosRing = f:CreateTexture(nil, "BACKGROUND")
    f.kosRing:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    f.kosRing:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    f.kosRing:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f.kosRing:SetVertexColor(1, 0.1, 0.1, 1)
    f.kosRing:Hide()
    f.class = f:CreateTexture(nil, "ARTWORK")
    f.class:SetAllPoints()
    f.class:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    -- healer: a green + with a black edge, on the icon's lower right
    f.heal = CreateFrame("Frame", nil, f)
    f.heal:SetSize(12, 12)
    f.heal:SetPoint("CENTER", f, "BOTTOMRIGHT", -2, 3)
    local function bar(w, h, r, g, b, layer)
        local t = f.heal:CreateTexture(nil, layer)
        t:SetColorTexture(r, g, b, 1)
        t:SetSize(w, h)
        t:SetPoint("CENTER")
    end
    bar(12, 6, 0, 0, 0, "ARTWORK"); bar(6, 12, 0, 0, 0, "ARTWORK")
    bar(10, 3, 0.2, 1, 0.3, "OVERLAY"); bar(3, 10, 0.2, 1, 0.3, "OVERLAY")
    f.heal:Hide()
    f.skull = f:CreateTexture(nil, "OVERLAY")
    f.skull:SetSize(12, 12)
    f.skull:SetPoint("CENTER", f, "TOPLEFT", 2, -3)
    f.skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    f.skull:Hide()
    plateIcons[plate] = f
    return f
end

local function UpdatePlate(unit, fresh)
    local plate = PlateFor(unit)
    if not plate then return end
    local d, coords, friendly, hostile = db(), nil, false, false
    if Readable(UnitIsPlayer(unit)) == true and Readable(UnitIsUnit(unit, "player")) ~= true then
        hostile = ns.IsHostilePlayer(unit)
        friendly = not hostile
        if (hostile and d.plateIcons) or (friendly and d.plateFriendly) then
            local _, class = UnitClass(unit)
            class = Readable(class)
            if type(class) == "string" then coords = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or CLASS_COORDS[class] end
        end
    end
    local f = plateIcons[plate]
    if not coords then
        if f then f:Hide() end
        return
    end
    if fresh and d.plateHealer ~= false then
        ns.Safe("role auras", ns.ScanRoleAuras, unit)
        if friendly then ns.Safe("inspect", ns.MaybeInspect, unit) end
    end
    f = PlateIcon(plate)
    local size = ns.PlateSize()
    if f.size ~= size then
        f.size = size
        f:SetSize(size, size)
        f.heal:SetScale(size / PLATE_ICON)
        f.skull:SetSize(math.floor(size * 0.55 + 0.5), math.floor(size * 0.55 + 0.5))
        local edge = math.max(2, math.floor(size / 7 + 0.5))
        f.kosRing:SetPoint("TOPLEFT", f, "TOPLEFT", -edge, edge)
        f.kosRing:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", edge, -edge)
    end
    local kos = false
    if hostile and d.plateKOS ~= false then
        local key, _, first = ns.PlayerKey(unit)
        local guild = Readable((GetGuildInfo(unit)))
        kos = (key or guild) and ns.IsKOS(key or "", first, guild) and true or false
    end
    f.kosRing:SetShown(kos)
    f.skull:SetShown(kos)
    f.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    f.heal:SetShown(d.plateHealer ~= false and ns.IsHealer(ns.PlayerKey(unit), unit) == true)
    f:Show()
end

function ns.UpdatePlates()
    for unit in pairs(plateUnits) do UpdatePlate(unit) end
end

local function OnPlateEvent(_, event, unit)
    if type(unit) ~= "string" or not unit:find("^nameplate%d+$") then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        plateUnits[unit] = nil
        local plate = PlateFor(unit)
        if plate and plateIcons[plate] then plateIcons[plate]:Hide() end
    else   -- added, or the player's PvP status changed
        if event == "NAME_PLATE_UNIT_ADDED" then plateUnits[unit] = true end
        if plateUnits[unit] then UpdatePlate(unit, true) end
    end
end

local function InitPlates()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FACTION" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(...) ns.Safe("nameplate icons", OnPlateEvent, ...) end)
    -- friendly players wait their turn for an inspect: one is asked every few seconds
    local wait = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        wait = wait + elapsed
        if wait < 3 then return end
        wait = 0
        local d = db()
        if not (d.plateFriendly and d.plateHealer ~= false) or InCombatLockdown() then return end
        for unit in pairs(plateUnits) do ns.Safe("inspect", ns.MaybeInspect, unit) end
    end)
    if C_NamePlate and C_NamePlate.GetNamePlates then   -- plates already up (after a /reload)
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        for _, plate in ipairs(ok and type(plates) == "table" and plates or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if type(unit) == "string" and unit:find("^nameplate%d+$") then plateUnits[unit] = true end
        end
        ns.UpdatePlates()
    end
end

function ns.InitUI()
    panel = BuildPanel()
    mini = BuildMini()
    InitMinimap()
    local ok, err = pcall(BuildSettings)
    if not ok then ns.Print("Could not add the settings page: " .. tostring(err)) end
    CreatePrompt()
    CreateTargetButton()
    if not InCombatLockdown() then nb = BuildNearby() end
    ns.HookTooltip()
    lv = BuildLevel()
    ns.levelFrame = lv
    ns.Safe("nameplate icons", InitPlates)
    ns.Safe("map pins", ns.UpdateMapPins)
    ns.UpdateChatLogPrompt()
    RefreshMini()
    if not db().helpSeen then   -- the guide opens by itself the first time
        db().helpSeen = true
        C_Timer.After(4, ns.ShowHelp)
    end
end
end
