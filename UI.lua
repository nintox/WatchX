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
    local p, rel, rp, x, y = frame:GetPoint()
    if rel and rel ~= UIParent then   -- hangs on another frame: keep where it is now, against the screen
        local l, t = frame:GetLeft(), frame:GetTop()
        if not (l and t) then return end
        p, rp, x, y = "TOPLEFT", "BOTTOMLEFT", l, t
    end
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
        if eb then eb:SetText(m.manualRespawn and tostring(math.floor(m.manualRespawn / 6 + 0.5) / 10) or ""); eb:SetFocus() end
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
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Things that can't be undone (or go out to others) ask first.
StaticPopupDialogs["WATCHX_FORGET"] = {
    text = "Forget %s?\nKills, deaths, notes and marks for them are deleted.",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) ns.ForgetEnemy(data); if ns.RefreshHistory then ns.RefreshHistory() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["WATCHX_TAKEDOWN"] = {
    text = "Take down the bounty on %s?\nIt goes away for your guild and friends too.",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) ns.RemoveWanted(data); if ns.RefreshHistory then ns.RefreshHistory() end end,
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
    if not ok then ns.Print(err) return true end   -- (true: the box stays open with the name to fix)
end
StaticPopupDialogs["WATCHX_NEWPROFILE"] = {
    text = "Name of the new profile (e.g. Leveling, Camping, PvP).\nIt starts as a copy of your current settings:",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self) local eb = PopupEditBox(self); if eb then eb:SetText(""); eb:SetFocus() end end,
    OnAccept = NewProfileAccept,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if not NewProfileAccept(parent) then parent:Hide() end
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
    m.exp = FlatButton(m, "Export / import...", 170, 20, function() m:Hide(); ns.ShowExport() end)
    m.del = FlatButton(m, "Delete", 170, 20, function()
        m:Hide()
        local cur = db().profile
        if cur then StaticPopup_Show("WATCHX_DELPROFILE", cur, nil, cur) end
    end)
    tinsert(UISpecialFrames, "WatchXProfileMenu")   -- Esc closes it
    ns.MenuAutoClose(m)
    m:Hide()
    return m
end

function ns.ToggleProfileMenu(anchor)
    profileMenu = profileMenu or BuildProfileMenu()
    local m = profileMenu
    if m:IsShown() and m.anchor == anchor then m:Hide() return end
    m.anchor = anchor
    local names, cur = ns.ProfileNames(), db().profile
    local y = -(31 + math.ceil(m.hint:GetStringHeight() or 12))   -- under the hint (two lines at this width)
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
    m.exp:ClearAllPoints(); m.exp:SetPoint("TOPLEFT", m, "TOPLEFT", 10, y)
    y = y - 23
    m:SetHeight(-y + 8)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    m:Show()
end

-- A menu goes away with a click anywhere else (not on it or its button), and when what opened it is hidden.
function ns.MenuAutoClose(m)
    m:HookScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    m:HookScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    m:SetScript("OnEvent", function(self, event)
        if event ~= "GLOBAL_MOUSE_DOWN" or not self:IsShown() or self:IsMouseOver() then return end
        local a = self.anchor
        if a and a.IsMouseOver and a:IsMouseOver() then return end   -- its own button toggles it
        self:Hide()
    end)
    m:HookScript("OnUpdate", function(self)   -- (only while it's open)
        local a = self.anchor
        if a and a.IsVisible and not a:IsVisible() then self:Hide() end
    end)
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
        ns.MenuAutoClose(menu)
    end
    menu.anchor = anchor
    menu.title:SetText(title or "")
    local y = -26
    for i, it in ipairs(items) do
        local b = menu.buttons[i]
        if not b then
            b = MenuRow(menu, 180, function(self)
                menu:Hide()
                if self.fn then self.fn() end
                if ns.RefreshHistory then ns.RefreshHistory() end   -- the list behind it shows the change at once
            end)
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
    -- tell your party / guild about this one: who, level, class, guild, KOS / WANTED with the reward, where you are
    local function Tell(where)
        local live = ns.nearby and ns.nearby[key]
        local e = { name = r.name or (live and live.name), class = r.class or (live and live.class),
            level = r.level or (live and live.level), guild = r.guild or (live and live.guild) }
        local kind = (r.wanted and ns.WantedState(r.wanted).open) and "wanted" or (r.kos or (live and live.kos)) and "kos"
            or (live and live.stealth and time() - live.stealth < 60) and "stealth" or "enemy"
        ns.ShareSpot(e, kind, kind == "wanted" and r.wanted or (kind == "stealth" and live.stealthHow) or nil, where)
    end
    items[#items + 1] = { "Announce in |cffffffffsay|r", function() Tell("say") end }
    if IsInGroup and IsInGroup() then
        items[#items + 1] = { "Announce in |cffaad4ff" .. ((IsInRaid and IsInRaid()) and "raid" or "party") .. "|r", function() Tell("party") end }
    end
    if IsInGuild and IsInGuild() then items[#items + 1] = { "Announce in |cff40ff40guild|r", function() Tell("guild") end } end
    if r.guild then
        local gk = ns.db.kosGuilds[r.guild:lower()]
        items[#items + 1] = { (gk and "Guild off KOS: " or "KOS the guild: ") .. r.guild, function() ns.SetGuildKOS(r.guild, not gk) end }
    end
    local mineW = r.wanted and ns.WantedMine(r.wanted)
    if r.wanted and not mineW then
        items[#items + 1] = { "|cff909090Bounty by " .. ((r.wanted.by or "?"):gsub("%-", " ")) .. " – only they can change it|r", nil }
    elseif r.wanted then
        local st = ns.WantedState(r.wanted)
        local shown = 0
        for _, e in ipairs(st.debts) do   -- what you owe, per player (paid by trade: mark it here)
            if shown < 3 and not ns.IsMe(e.full) then
                shown = shown + 1
                local who = e.full
                items[#items + 1] = { "|cff40ff40Mark paid|r: " .. (who:gsub("%-", " ")) .. " " .. ns.Money(e.copper)
                    .. (e.n > 1 and (" (" .. e.n .. " kills)") or ""), function() ns.MarkPaid(key, who) end }
            end
        end
        if st.open then items[#items + 1] = { "|cffffa000Edit bounty|r", function() ns.ShowBounty(key) end } end
        items[#items + 1] = { "Take the bounty down...", function() StaticPopup_Show("WATCHX_TAKEDOWN", r.name, nil, key) end }
    else
        items[#items + 1] = { "|cffffa000WANTED|r – put a bounty on them", function() ns.ShowBounty(key) end }
    end
    items[#items + 1] = { r.note and "Edit note" or "Add note", function() StaticPopup_Show("WATCHX_NOTE", r.name, nil, key) end }
    if r.wanted and not ns.WantedMine(r.wanted) and not ns.WantedState(r.wanted).settled then   -- someone else's bounty keeps them here
        items[#items + 1] = { "|cff606060Can't forget – " .. (r.wanted.by or "someone") .. " has a bounty on them|r", nil }
    else
        items[#items + 1] = { "|cff909090Forget this player...|r", function() StaticPopup_Show("WATCHX_FORGET", r.name, nil, key) end }
    end
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
        f:SetSize(340, 244)
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
        -- three rows, label at the left and the boxes lined up after it
        local LX, BX = 22, 96   -- label x, box x
        local function Label(text, y)
            local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l:SetPoint("TOPLEFT", f, "TOPLEFT", LX, y - 4)
            l:SetText(text)
            return l
        end
        Label("Player", -40)
        f.who = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        f.who:SetPoint("TOPLEFT", f, "TOPLEFT", BX, -42)
        -- first name and surname in their own boxes (every name on WoW Forever has both)
        f.whoBox = Box(f, 106, 24, "First")
        f.whoBox:SetPoint("TOPLEFT", f, "TOPLEFT", BX + 4, -40)
        f.whoBox:Hide()
        f.lastBox = Box(f, 106, 24, "Last")
        f.lastBox:SetPoint("LEFT", f.whoBox, "RIGHT", 10, 0)
        f.lastBox:Hide()
        Label("Reward", -72)
        -- gold, silver, copper: numbers only, a coin after each (like Blizzard's money boxes)
        f.coins = {}
        local x = BX + 4
        for i, c in ipairs({ { 60, 6, "Interface\\MoneyFrame\\UI-GoldIcon" }, { 34, 2, "Interface\\MoneyFrame\\UI-SilverIcon" },
                             { 34, 2, "Interface\\MoneyFrame\\UI-CopperIcon" } }) do
            local e = Box(f, c[1], c[2], "")
            e:SetNumeric(true)
            e:SetJustifyH("RIGHT")
            if e.SetTextInsets then e:SetTextInsets(0, 4, 0, 0) end
            e:SetPoint("TOPLEFT", f, "TOPLEFT", x, -72)
            local icon = f:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("LEFT", e, "RIGHT", 4, 0)
            icon:SetTexture(c[3])
            f.coins[i] = e
            x = x + c[1] + 30
        end
        f.reward = f.coins[1]
        f.whoBox:SetScript("OnEnterPressed", function() f.lastBox:SetFocus() end)
        f.whoBox:SetScript("OnTabPressed", function() f.lastBox:SetFocus() end)
        f.lastBox:SetScript("OnEnterPressed", function() f.coins[1]:SetFocus() end)
        f.lastBox:SetScript("OnTabPressed", function() f.coins[1]:SetFocus() end)
        -- several kills: the reward is for each one, up to this many
        Label("Kills", -132)
        f.kills = Box(f, 40, 3, "")
        f.kills:SetNumeric(true)
        f.kills:SetJustifyH("CENTER")
        f.kills:SetPoint("TOPLEFT", f, "TOPLEFT", BX + 4, -132)
        local kl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        kl:SetPoint("LEFT", f.kills, "RIGHT", 8, 0)
        kl:SetText("|cff808080the reward is paid for each kill, up to this many|r")
        f.forever = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        f.forever:SetSize(22, 22)
        f.forever:SetPoint("TOPLEFT", f, "TOPLEFT", BX, -158)
        local fl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fl:SetPoint("LEFT", f.forever, "RIGHT", 2, 1)
        fl:SetText("No end date  |cff808080(else it ends after 14 days)|r")
        f.err = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
        f.err:SetPoint("TOP", f, "TOP", 0, -182)
        Label("Note", -104)
        f.note = Box(f, 222, 100, "why? e.g. ninja looter")
        f.note:SetPoint("TOPLEFT", f, "TOPLEFT", BX + 4, -104)
        local function copper()
            local g, sv, cp = tonumber(f.coins[1]:GetText()) or 0, tonumber(f.coins[2]:GetText()) or 0, tonumber(f.coins[3]:GetText()) or 0
            return g * 10000 + math.min(99, sv) * 100 + math.min(99, cp)
        end
        local function post()
            local c = copper()
            if c <= 0 then
                f.err:SetText("Put in a reward"); f.shareHint:Hide()
                f.coins[1]:SetFocus()
                return
            end
            local key, name = f.key, f.name
            if f.whoBox:IsShown() then
                local first, last = ns.Trim(f.whoBox:GetText() or ""), ns.Trim(f.lastBox:GetText() or "")
                first, last = first:gsub("%s+", ""), last:gsub("%s+", "")
                if first == "" then f.err:SetText("Who? Put in the first name"); f.shareHint:Hide(); f.whoBox:SetFocus() return end
                if last == "" then f.err:SetText("And the last name – every name has one"); f.shareHint:Hide(); f.lastBox:SetFocus() return end
                name = ns.ProperName(first .. " " .. last)   -- "bob smith" is Bob Smith
                key = ns.KeyFromName(name)
            end
            local ok, why = ns.SetWanted(key, name, c, f.note:GetText(), f.forever:GetChecked() and true or false,
                math.max(1, tonumber(f.kills:GetText()) or 1))
            if ok then f:Hide() else f.err:SetText(why or "Couldn't post it – see chat."); f.shareHint:Hide() end
        end
        for i, e in ipairs(f.coins) do
            local nextBox = f.coins[i + 1] or f.note
            e:SetScript("OnEnterPressed", function() nextBox:SetFocus() end)
            e:SetScript("OnTabPressed", function() nextBox:SetFocus() end)
            local changed = e:GetScript("OnTextChanged")
            e:SetScript("OnTextChanged", function(self, ...) if changed then changed(self, ...) end f.err:SetText(""); f.shareHint:Show() end)
        end
        f.note:SetScript("OnEnterPressed", post)
        f.note:SetScript("OnTabPressed", function() f.coins[1]:SetFocus() end)
        f.post = Button(f, "Post bounty", 96, 24, post)
        f.post:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
        f.down = Button(f, "Take down", 96, 24, function() ns.RemoveWanted(f.key); f:Hide() end)
        f.down:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
        local cancel = Button(f, CANCEL or "Cancel", 96, 24, function() f:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
        f.shareHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.shareHint:SetPoint("BOTTOM", f, "BOTTOM", 0, 48)
        f:Hide()
        return f
    end
    -- key: the player (from a menu); none: you type the name (your target is filled in).
    function ns.ShowBounty(key, name)
        bw = bw or Build()
        local typed = not key
        if typed and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
            local tk, full = ns.PlayerKey("target")
            if tk then key, name = tk, full end
        end
        local r = key and db().enemies[key]
        local w = r and r.wanted
        bw.key, bw.name = key, name or (r and r.name) or key
        bw.who:SetShown(not typed)
        bw.whoBox:SetShown(typed)
        bw.lastBox:SetShown(typed)
        bw.who:SetText(bw.name or "")
        local first, last = (typed and bw.name or ""):match("^(%S+)%s*(.-)$")
        bw.whoBox:SetText(first or "")
        bw.lastBox:SetText(last or "")
        local c = w and w.copper or 0
        bw.coins[1]:SetText(c >= 10000 and tostring(math.floor(c / 10000)) or "")
        bw.coins[2]:SetText((c % 10000) >= 100 and tostring(math.floor(c / 100) % 100) or "")
        bw.coins[3]:SetText((c % 100) > 0 and tostring(c % 100) or "")
        bw.err:SetText("")
        bw.shareHint:Show()
        bw.forever:SetChecked(w and w.forever and true or false)
        bw.kills:SetText(tostring(w and w.kills or 1))
        bw.note:SetText(w and w.note or "")
        bw.down:SetShown((w and ns.WantedMine(w)) and true or false)
        local d = db()
        local to = (d.wantedGuild ~= false and d.wantedFriends ~= false) and "your guild and online friends"
            or d.wantedGuild ~= false and "your guild" or d.wantedFriends ~= false and "your online friends" or "nobody (sharing is off)"
        bw.shareHint:SetText("Sent to " .. to .. " who run WatchX.")
        bw:Show()
        bw:Raise()
        if typed and (bw.name or "") == "" then bw.whoBox:SetFocus() else bw.coins[1]:SetFocus() end
    end
end

local profileLabels = {}   -- fn(name) for each place that shows the active profile
function ns.UpdateProfileLabels()
    local name = db().profile or "?"
    if name == profileLabels.shown and #profileLabels == profileLabels.n then return end   -- nothing new
    profileLabels.shown, profileLabels.n = name, #profileLabels
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
    local function check(label, hint, get, set, col2, width)
        if col2 then y = y + 26 end
        local cb = CreateFrame("CheckButton", nil, o, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", o, "TOPLEFT", col2 and COL2 or (L - 4), y + 2)
        local name = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        name:SetWidth(width or (COL2 - L - 40))
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
        check(label, hint, get, set, nil, W - (open and 114 or 30))   -- one column: the whole row, up to its button
        if open then
            local b = Button(o, "Settings", 80, 20, function() open() end)
            b:SetPoint("TOPLEFT", o, "TOPLEFT", L + W - 84, y + 26 + 1)
        end
    end
    local function openAlerts() ns.OpenAlertSettings() end

    section("PVP")
    module("Enemies", "the enemy players around you, KOS, avoid list, stealth warnings",
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
        function() return db().attackAlert end, function(v) db().attackAlert = v end)

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
    module("Eating & drinking timer", "time left and how much health / mana you'll get, mid-screen",
        function() return db().eatTimer ~= false end, function(v) db().eatTimer = v; if ns.RefreshEating then ns.RefreshEating() end end)
    module("Spots on the map", "where to stand for the rares you watch",
        function() return db().mapSpots ~= false end,
        function(v) db().mapSpots = v; ns.Safe("map pins", ns.UpdateMapPins) end)
    module("AFK logout warning", "a phone alert 5 min before",
        function() return db().afkWarn end, function(v) db().afkWarn = v end)
    module("Minimap button", nil,
        function() return not db().minimap.hide end, function(v) ns.SetMinimapShown(v) end)

    section("PHONE")
    -- (a bit shorter: room for the "New topic" button – anyone who knows a topic can read it, screenshots too)
    local ntfyBox = field("ntfyUrl", "ntfy link", "From the ntfy app, e.g. ntfy.sh/your-secret-topic. Anyone who knows the "
        .. "topic can read its alerts (screenshots too): make it long and secret – \"New topic\" picks one.", nil, nil, W - 130 - 96)
    local newTopic = Button(o, "New topic", 90, 20, function()
        local chars, t = "abcdefghijkmnpqrstuvwxyz23456789", {}
        for i = 1, 16 do local n = math.random(1, #chars); t[i] = chars:sub(n, n) end
        ntfyBox:SetText("ntfy.sh/wx-" .. table.concat(t))
        ntfyBox:Store()
        ns.Print("New ntfy topic: |cffffd100" .. ntfyBox:GetText() .. "|r – subscribe to it in the ntfy app (+, the part "
            .. "after ntfy.sh/), then Save & reload.")
    end)
    newTopic:SetPoint("LEFT", ntfyBox, "RIGHT", 6, 0)
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
    ns.BuildRebuffSettings()
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
        cat.lower = cat.lower or {}   -- each rare's "name zone" in lower case, made once (not per letter typed)
        for _, r in ipairs(ns.RARES or {}) do
            local zone = AreaName(r[5])
            local ok = true
            if q ~= "" then
                local low = cat.lower[r]
                if not low then low = r[2]:lower() .. "\1" .. zone:lower(); cat.lower[r] = low end
                if not low:find(q, 1, true) then ok = false end
            end
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
            -- one refresh a moment after the last letter, not one per letter
            if not (C_Timer and C_Timer.NewTimer) then ns.RefreshRares() return end
            if f.searchT then f.searchT:Cancel() end
            f.searchT = C_Timer.NewTimer(0.15, function() f.searchT = nil; ns.RefreshRares() end)
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
        if cat:IsShown() then ns.RefreshRares() else cat:Show() end   -- (showing it refreshes it)
        cat:Raise()
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
local WCOLS = {   -- the Wanted tab: one bounty a row
    { key = "name", label = "Name", w = 150, j = "LEFT" },
    { key = "reward", label = "Reward", w = 96, j = "RIGHT", num = true },
    { key = "by", label = "Posted by", w = 100, j = "LEFT" },
    { key = "posted", label = "Posted", w = 66, j = "RIGHT", num = true },
    { key = "status", label = "Status", w = 250, j = "LEFT" },
    { key = "note", label = "Note", w = 141, j = "LEFT" },
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

    f.tab, f.sort = "all", { all = { "lastSeen", true }, guilds = { "lastSeen", true }, wanted = { "posted", true } }
    f.tabs = {}
    local prev
    for _, t in ipairs({ { "all", "All players" }, { "kos", "KOS" }, { "avoid", "Avoid" }, { "wanted", "Wanted" }, { "notes", "Notes" }, { "guilds", "Guilds" } }) do
        local b = FlatButton(f, t[2], 84, 22, function()
            f.tab = t[1]
            f.backTo, f.guildFilter = nil, nil
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
    f.search:SetScript("OnTextChanged", function(self)
        -- typing: one refresh a moment after the last letter, not one per letter (it sorts up to 2000 players)
        if ns.Trim(self:GetText() or ""):lower() == f.lastQ then return end
        if not (C_Timer and C_Timer.NewTimer) then ns.RefreshHistory() return end
        if f.searchT then f.searchT:Cancel() end
        f.searchT = C_Timer.NewTimer(0.15, function() f.searchT = nil; ns.RefreshHistory() end)
    end)
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
        f.backTo, f.guildFilter = nil, nil
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
            local srt = f.sort[f.tab == "guilds" and "guilds" or f.tab == "wanted" and "wanted" or "all"]
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
        if t ~= "" then ns.SetGuildKOS(t, true); f.addG:SetText("") end   -- (History follows: SetGuildKOS marks it)
        f.addG:ClearFocus()
    end
    f.addG:SetScript("OnEnterPressed", addGuild)
    f.addG:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    f.addG:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
    f.addGB = FlatButton(f, "Blacklist", 70, 20, addGuild)
    f.addGB:SetPoint("LEFT", f.addG, "RIGHT", 6, 0)
    f.addW = FlatButton(f, "+ Add bounty", 120, 22, function() ns.ShowBounty() end)
    f.addW:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 240, 10)
    f.addW:SetScript("OnEnter", function(self)
        Tip(self, "Add a bounty", "Anyone: type the name (your target is filled in), a reward and a note. "
            .. "It goes to your guild and friends who run WatchX.")
    end)
    f.addW:SetScript("OnLeave", GameTooltip_Hide)
    f.addW:Hide()

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
                    f.tab, f.guildFilter, f.guildName = "all", g:lower(), g
                    f.search:SetText("")
                    ns.RefreshHistory()
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
        if rec.wanted and ns.AddWantedLines then ns.AddWantedLines(GameTooltip, rec.wanted) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd100Click:|r KOS, note, bounty, forget", 1, 1, 1)
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
    local wantedTab = f.tab == "wanted"
    local cols = guildsTab and GCOLS or wantedTab and WCOLS or PCOLS
    for _, b in ipairs(f.tabs) do b:SetAlpha(b.key == f.tab and 1 or 0.5) end
    f.addG:SetShown(guildsTab); f.addGB:SetShown(guildsTab)
    f.addW:SetShown(f.tab == "wanted")
    f.hint:SetText(guildsTab and "Click a guild: blacklist, show its players"
        or wantedTab and "Click a bounty: edit, take down, mark paid  ·  hover: the whole story"
        or "Click a player: KOS, note, forget")
    -- headers
    local srt = f.sort[guildsTab and "guilds" or wantedTab and "wanted" or "all"]
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
    f.lastQ = q
    if f.searchT then f.searchT:Cancel(); f.searchT = nil end
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
            if ok and f.guildFilter and (r.guild or ""):lower() ~= f.guildFilter then ok = false end   -- one guild's players
            if ok and match(r.name, key, r.guild, r.zone, r.note, r.class) then
                -- the text columns in lower case once here, so the sort compares them as they are
                items[#items + 1] = { key = key, r = r, kos = kos, name = (r.name or key):lower(), level = r.level or 0,
                    class = r.class or "", guild = (r.guild or "~"):lower(), kills = r.kills or 0, deaths = r.deaths or 0,
                    seen = r.seen or 0, lastSeen = r.lastSeen or 0, zone = (r.zone or "~"):lower(), note = (r.note or "~"):lower() }
                local w = r.wanted
                if wantedTab and w then
                    local it = items[#items]
                    it.reward, it.by, it.posted = w.copper or 0, (w.by or "~"):lower(), w.t or 0
                    local st = ns.WantedState(w)
                    it.st = st
                    it.status = st.settled and "4" or (st.kills > 0 and "3") or "1"
                    it.note = (w.note or "~"):lower()
                    -- what you owe first, then what you're owed, the open ones, the rest
                    it.group = (st.owe > 0) and 1 or (st.owed > 0) and 2 or st.open and 3 or (not st.settled) and 4 or 5
                end
            end
        end
    end
    local sk, desc = srt[1], srt[2]
    table.sort(items, function(a, b)
        if wantedTab and a.group ~= b.group then return (a.group or 9) < (b.group or 9) end   -- what you owe first
        local va, vb = a[sk], b[sk]
        if guildsTab and type(va) == "string" then va, vb = va:lower(), tostring(vb or ""):lower() end   -- (players: lower already)
        if va == vb then return (a.lastSeen or 0) > (b.lastSeen or 0) end
        if desc then return va > vb end
        return va < vb
    end)
    local n = math.min(#items, HIST_MAX)
    for i = 1, n do
        local it, row = items[i], HistoryRow(i)
        if row.cols ~= cols then PlaceColumns(cols, row.cells, row, 0); row.cols = cols end   -- (only when the tab's kind changed)
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
            local wst = r.wanted and ns.WantedState(r.wanted)
            local v = { (it.kos and "|cffff3030KOS|r " or "") .. (wst and ((wst.owe > 0 and "|cffff8040OWED|r ")
                    or (wst.open and "|cffffa000WANTED|r ") or (wst.settled and "|cff40ff40PAID|r ") or "|cffffd100CLAIMED|r ") or "")
                .. (r.avoid and "|cffff8040AVOID|r " or "") .. (r.name or it.key),
                (r.level and r.level > 0) and r.level or "??", ClassName(r.class), r.guild or "|cff606060-|r",
                (r.kills or 0) > 0 and ("|cffffd100" .. r.kills .. "|r") or "0",
                (r.deaths or 0) > 0 and ("|cffff6060" .. r.deaths .. "|r") or "0",
                r.seen or 1, r.lastSeen and ns.AgoLong(now - r.lastSeen) or "-",
                r.zone or "|cff606060-|r", r.note or "" }
            if wantedTab and r.wanted then
                -- one bounty: name (class colour), reward, who put it up and when, where it stands, the note
                local w = r.wanted
                local mine = ns.WantedMine(w)
                local st = it.st or ns.WantedState(w)
                local status
                if st.limit > 1 then   -- several kills: how many are in, and the latest
                    local c = st.last
                    status = (st.open and "|cffffa000OPEN|r" or (st.settled and "|cff40ff40PAID|r" or "|cffffd100DONE|r"))
                        .. "  |cffffd100" .. st.kills .. "/" .. st.limit .. " kills|r"
                        .. (c and ("  |cffaaaaaalast by " .. ((c.by or "?"):gsub("%-", " ")) .. " " .. ns.AgoLong(now - (c.t or now)) .. " ago|r") or "")
                elseif w.paid then
                    status = "|cff40ff40PAID|r  |cffaaaaaa" .. (w.claimed and ("to " .. (w.claimed.by or "?")) or "") .. "|r"
                elseif w.claimed then
                    local c = w.claimed
                    status = (mine and "|cffff8040OWED|r  " or "|cffffd100KILLED|r  ") .. "by " .. (c.by or "?")
                        .. (c.zone and ("  |cffaaaaaa" .. c.zone .. "|r") or "") .. (c.t and ("  |cff808080" .. ns.AgoLong(now - c.t) .. " ago|r") or "")
                else
                    status = "|cffffa000OPEN|r  |cffaaaaaa" .. (w.forever and "no end date"
                        or ("ends in " .. math.max(0, math.ceil(((w.t or now) + 14 * 86400 - now) / 86400)) .. " d")) .. "|r"
                end
                local v = { r.name or it.key, (ns.WantedReward(w) or "?") .. (st.limit > 1 and (" ×" .. st.limit) or ""),
                    mine and "|cffffd100you|r" or (w.by or "?"), w.t and ns.AgoLong(now - w.t) or "-", status, w.note or "" }
                if it.group == 1 then        -- you owe it: orange row, can't be missed
                    row.bar:SetColorTexture(0.45, 0.18, 0.04, 0.95)
                    row.edge:SetColorTexture(1, 0.5, 0.1, 1)
                    local e
                    for _, x in ipairs(st.debts) do if not ns.IsMe(x.full) then e = e or x end end
                    v[5] = "|cffff9040YOU OWE|r  " .. ns.Money(st.owe) .. " to " .. ((e and e.full or "?"):gsub("%-", " "))
                        .. ((#st.debts > 1) and (" +" .. (#st.debts - 1)) or "") .. "  |cffffd100– pay at a mailbox|r"
                elseif it.group == 2 then    -- owed to you
                    row.bar:SetColorTexture(0.32, 0.26, 0.05, 0.95)
                    row.edge:SetColorTexture(1, 0.82, 0, 1)
                    v[5] = "|cffffd100OWED TO YOU|r  " .. ns.Money(st.owed) .. " by " .. (w.by or "?")
                        .. ((st.last and st.last.zone) and ("  |cffaaaaaa" .. st.last.zone .. "|r") or "")
                end
                for c = 1, #WCOLS do row.cells[c]:SetText(v[c]); row.cells[c]:SetTextColor(1, 1, 1) end
                for c = #WCOLS + 1, #row.cells do row.cells[c]:SetText("") end
                row.cells[1]:SetTextColor(cr, cg, cb)
                row.cells[6]:SetTextColor(1, 0.85, 0.5)
            else
                for c = 1, #PCOLS do row.cells[c]:SetText(v[c]); row.cells[c]:SetTextColor(1, 1, 1) end
                row.cells[1]:SetTextColor(cr, cg, cb)
                row.cells[3]:SetTextColor(cr, cg, cb)
                row.cells[10]:SetTextColor(1, 1, 0.6)
            end
        end
        row:Show()
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    f.child:SetHeight(math.max(10, n * HIST_ROW_H))
    local owe, oweC, due, dueC = 0, 0, 0, 0
    if wantedTab then
        for _, it in ipairs(items) do
            if it.st and it.st.owe > 0 then owe, oweC = owe + 1, oweC + it.st.owe end
            if it.st and it.st.owed > 0 then due, dueC = due + 1, dueC + it.st.owed end
        end
    end
    local M = ns.Money or tostring
    local money = (owe > 0 and ("|cffff9040You owe " .. owe .. ": " .. M(oweC) .. "|r   ") or "")
        .. (due > 0 and ("|cffffd100Owed to you " .. due .. ": " .. M(dueC) .. "|r   ") or "")
    if wantedTab and money ~= "" then
        f.count:SetText(money)   -- (the "+ Add bounty" button sits right of it: what you owe wins the room)
    else
        f.count:SetText(money .. "Showing " .. #items .. " of " .. total .. (guildsTab and " guilds" or " players")
            .. (f.guildFilter and not guildsTab and ("  |cffffd100in <" .. (f.guildName or f.guildFilter) .. ">|r") or "")
            .. (#items > HIST_MAX and (" (first " .. HIST_MAX .. ")") or ""))
    end
end

function ns.ShowHistory(tab)
    history = history or BuildHistory()
    if tab then   -- opened for a tab: no old search, guild or Back from last time
        history.tab, history.backTo, history.guildFilter = tab, nil, nil
        if (history.search:GetText() or "") ~= "" then history.search:SetText("") end
    end
    if history:IsShown() then ns.RefreshHistory() else history:Show() end   -- (showing it refreshes it)
    history:Raise()
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
    local avoidRec = rec and rec.avoid and rec or (ns.Avoided and ns.Avoided(key)) or nil   -- by full or first name
    local avoid = avoidRec ~= nil
    local ww = ns.Wanted and ns.Wanted(key) or (rec and rec.wanted and ns.db.wantedOn ~= false and rec.wanted)
    if not rec and not kos and not role and not ww and not avoid then return end
    if ww then tip:AddLine("WatchX: " .. ns.WantedLine(ww), 1, 1, 1, true) end
    if avoid then tip:AddLine(ns.AvoidLine(avoidRec), 1, 0.5, 0.25, true) end
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
    sub:SetText("the Enemies list, KOS, avoid list and nameplate icons")

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
    check("Show the Enemies list", "the enemy players around you",
        function() return db().nearby end, function(v) ns.SetNearby(v) end)
    check("Stealth warning", "a card mid-screen when a player goes into stealth",
        function() return db().stealthWarn ~= false end, function(v) db().stealthWarn = v end)
    check("Sounds", "off: no sound for any of the warnings below",
        function() return db().stealthSound ~= false end, function(v) db().stealthSound = v end)
    check("New enemy card", "for every new enemy (Stealth and KOS always show)",
        function() return db().newEnemyCard == true end, function(v) db().newEnemyCard = v end)
    check("Attach under the mini bar", "they move and grow together",
        function() return db().nearbyAttach ~= false end, function(v) db().nearbyAttach = v; ns.AttachNearby() end)
    check("Warnings on top of the list", "off: top of the screen (Unlock to move)",
        function() return db().warnDock == true end, function(v) db().warnDock = v end)
    check("Ping and fps in the list's title", "ms and frames a second, coloured green / yellow / red",
        function() return db().nearbyStats ~= false end, function(v) db().nearbyStats = v end)
    check("Show the list when it's empty", "off: it only shows when enemies are around",
        function() return db().nearbyShowEmpty == true end, function(v) db().nearbyShowEmpty = v end)
    check("KOS alert", "a red card + sound when a KOS player shows up",
        function() return db().kosAlert ~= false end, function(v) db().kosAlert = v end)
    -- a sound for each: [ Raid warning v ] [>]  (click: the list to pick from; > plays it)
    o.soundBtns = {}
    ns.soundBtns = o.soundBtns   -- (for the tests)
    for _, k in ipairs(ns.SOUND_KINDS) do
        local lab = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lab:SetPoint("TOPLEFT", o, "TOPLEFT", L + 2, y - 4)
        lab:SetText("Sound: " .. k.label)
        local b = FlatButton(o, "", 140, 20)
        b:SetPoint("TOPLEFT", o, "TOPLEFT", L + 190, y - 1)
        function b.Paint()
            local cur = ns.SoundChoice(k.kind)
            SetButtonText(b, (cur == "off" and "|cff808080Off|r" or ns.SoundLabel(cur)) .. "  |cff999999v|r")
        end
        b:SetScript("OnClick", function(self) ns.ToggleSoundMenu(self, k.kind, b.Paint) end)
        local play = FlatButton(o, ">", 22, 20, function() ns.TrySound(ns.SoundChoice(k.kind)) end)
        play:SetPoint("LEFT", b, "RIGHT", 4, 0)
        if k.hint then
            local h = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            h:SetPoint("LEFT", play, "RIGHT", 8, 0)
            h:SetText(k.hint)
        end
        b.Paint()
        o.soundBtns[#o.soundBtns + 1] = b
        y = y - 26
    end
    y = y - 4
    -- tell your party / guild what you spot
    check("Tell my party / raid", "a line in party chat when you spot one of the ticked below",
        function() return db().shareParty == true end, function(v) db().shareParty = v end)
    check("Tell my guild", "the same in guild chat",
        function() return db().shareGuild == true end, function(v) db().shareGuild = v end)
    L = L + 24   -- (what to tell: indented under them)
    check("Stealth", nil, function() return db().shareStealth ~= false end, function(v) db().shareStealth = v end)
    check("Kill on sight", nil, function() return db().shareKOS ~= false end, function(v) db().shareKOS = v end)
    check("WANTED", "with the reward", function() return db().shareWanted ~= false end, function(v) db().shareWanted = v end)
    check("Every new enemy", "at most one line every 10 s", function() return db().shareAll == true end, function(v) db().shareAll = v end)
    L = L - 24
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
            if t ~= "" and onAdd(t) ~= false then eb:SetText("") end   -- refused (it says why): the text stays to fix
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
        if not key then ns.Print("That isn't a player name: " .. t) return false end
        ns.SetKOS(key, true)
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
    kosEmpty:SetText("No KOS yet – right-click a player in the Enemies list, or add one above.")
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
    check("Announce my bounties in guild chat", "posted, claimed (by whom, where) and paid – with the reward",
        function() return db().wantedAnnounce == true end, function(v) db().wantedAnnounce = v end)
    addRow("Bounty", "Name: 1g x10 note", function(t)
        local name, rest = t:match("^([^:]+):%s*(.*)$")
        name = ns.Trim(name or t)
        local copper, note = ns.ParseMoney(rest or "")
        local kills = note:match("^[xX](%d+)%s*")   -- "1g x10 ninja": 1g a kill, up to ten kills
        if kills then note = note:gsub("^[xX]%d+%s*", "") end
        local key = ns.KeyFromName(name)
        if not key then ns.Print("That isn't a player name: " .. name) return false end
        return ns.SetWanted(key, name, copper, note, nil, tonumber(kills)) ~= false
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
        if not ns.SetAvoid(name or t, true, note) then ns.Print("That isn't a player name: " .. (name or t)) return false end
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
        avoidCount:SetText(n == 0 and "Nobody yet – right-click a player in the Enemies list, or add one above."
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
        "|cffaaaaaa•|r  |cff40ff60+|r before a name = proven healer (see Nameplate icons above).",
        "|cffaaaaaa•|r  |cffd8a0ffSTEALTH|r = went into Stealth, Vanish, Prowl or Shadowmeld – and the warning pops up.",
        "|cffaaaaaa•|r  The warnings sit on top of the list: |cffd8a0ffStealthed player|r and |cffff5959Enemy player detected|r.",
        "|cffaaaaaa•|r  Needs |cffffd100enemy nameplates|r (key V). In dungeons and raids it's faded (or hidden, if ticked).",
        "|cffaaaaaa•|r  |cffffd100Right-click a row|r: KOS, avoid, KOS the guild, announce them (say, party, guild), a note. |cffff3030KOS|r players get a red card.",
        "|cffaaaaaa•|r  |cffff8040Avoid|r = people you don't want to play with (any player): tooltip, group warning, [Avoid] in chat.",
        "|cffaaaaaa•|r  |cffffd100Nameplate icons|r: the class over each player, |cff40ff60+|r = proven healer, |cffff3030red ring + skull|r = KOS.",
        "|cffaaaaaa•|r  Friendly: their talents (inspected). Enemies: a healing-talent spell like Riptide or Wild Growth.",
        "|cffaaaaaa•|r  |cffffd100History|r: everyone you've seen, with kills, deaths, last seen and notes.",
        "|cffaaaaaa•|r  Nothing goes to your phone – that's the WatchX page (Any enemy player).",
        "",
        "|cff808080/wx enemies on · off · test|r",
    }, "\n"))

    page:SetScript("OnShow", function()
        for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end
        for _, b in ipairs(o.soundBtns) do b.Paint() end   -- (a profile switch may have changed them)
        o.maxVal:SetText(ns.NearbyMax())
        o.keepVal:SetText(ns.NearbyKeepMin())
        o.sizeVal:SetText(ns.PlateSize())
        RefreshKOS()
        ns.RefreshAvoidCount()
    end)
    o:SetHeight(-y + (help:GetStringHeight() or 300) + 30)   -- the help text in full, for the scroll bar
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
                    or hit.near and "Hide the Enemies list." or hit.mob and hit.mob.preset
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
                Tip(self, "Enemies", "A list of the enemy players around you, like Spy – click one to "
                    .. "target it. A player going into stealth pops up a warning. In game only.",
                    " ", "|cffffd100Click:|r on/off", "|cffffd100See an example:|r /wx enemies test")
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
        b:SetScript("OnClick", function(self) if self.key ~= "plates" then ns.OpenSettings() end end)   -- links + AFK: main page
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
    local set = FlatButton(p.buttons, "Settings", bw, 22, function() ns.OpenSettings() end)
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
local function AlertWidth()   -- its own spot: its own width (as the unlock preview shows it); else the mini bar's
    if OwnSpot() then return db().alertWidth or 0 end
    return db().miniWidth or 0
end
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
        if not moving or InCombatLockdown() then return end
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
        if InCombatLockdown() then return end
        SizeTo(self, st, cx, cy, self.naturalH, "miniScale", "miniWidth")
        RefreshMini()
    end, function(self)
        if InCombatLockdown() then return end
        SavePoint(self, "miniPoint")
        ns.UpdateTargetButton()
        ns.UpdateChatLogPrompt()
    end)
    -- only a drag that really started moves and saves it (never a stray drag while locked, never in combat)
    m:SetScript("OnDragStart", function(self)
        if moving and not InCombatLockdown() then self.dragging = true; self:StartMoving() end
    end)
    m:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        SavePoint(self, "miniPoint")
        ns.UpdateTargetButton()
        ns.UpdateChatLogPrompt()
    end)
    m:SetScript("OnClick", function(_, button)
        if moving then   -- unlocked: dragging only; right-click puts the size back
            if button == "RightButton" and not InCombatLockdown() then
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
    -- the very same as last time (most seconds): only its visibility may have changed
    local parts = { tostring(moving), tostring(mini:GetScale()), tostring(db().miniWidth),
        tostring(ns.NearbyAttachWidth and ns.NearbyAttachWidth() or 0), tostring(MiniFrozen()) }
    for i, l in ipairs(lines) do parts[#parts + 1] = l[1] .. "\1" .. l[2] end
    local sig = table.concat(parts, "\2")
    if sig == mini.sig then
        ApplyMini()
        -- the mini bar shown/hidden or the red bar up/down: the stack under it moves
        local k = ns.StackKey and ns.StackKey()
        if k ~= mini.stackKey then mini.stackKey = k; if ns.AttachNearby then ns.AttachNearby() end end
        return
    end
    mini.sig = sig
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
    mini.stackKey = ns.StackKey and ns.StackKey()
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
    f:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
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
    if ns.EatingMove then ns.EatingMove(true) end
    if ns.RebuffMove then ns.RebuffMove(true) end
end

function ns.ToggleUnlock()
    if moving then ns.StopMove() else ns.StartMove() end
end

function ns.StopMove(why)
    if not moving then return end
    moving = false
    for _, f in ipairs({ mini, alertSpot or false, ns.levelFrame or false, WatchXRebuff or false }) do   -- (the list and card: NearbyMove)
        if f and f.dragging then f.dragging = nil; f:StopMovingOrSizing() end   -- a drag still going (a fight starts)
    end
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
    if ns.EatingMove then ns.EatingMove(false) end
    if ns.RebuffMove then ns.RebuffMove(false) end
    ns.Print(why or "Locked.")
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
    f.title:SetText("Enemies")
    -- Bounty news (a new bounty, a claim, a debt, paid): a coin with a count, on the title's line where you can't
    -- miss it. Click: the Wanted list; right-click: seen. Hover: what happened. (A plain button: fine in a fight.)
    f.news = CreateFrame("Button", nil, f)
    f.news:SetSize(18, 16)
    f.news:SetPoint("TOPRIGHT", f, "TOPRIGHT", -7, -5)
    f.news:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local coin = f.news:CreateTexture(nil, "ARTWORK")
    coin:SetSize(15, 15)
    coin:SetPoint("CENTER")
    coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local glow = f.news:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.63, 0, 0.35)
    if glow.CreateAnimationGroup then   -- a soft pulse while there's something new (the game's animation)
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.1); a:SetToAlpha(0.6); a:SetDuration(0.7)
        f.news.pulse = ag
    end
    f.news.num = f.news:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.news.num:SetPoint("BOTTOMRIGHT", f.news, "BOTTOMRIGHT", 3, -2)
    f.news:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then ns.ShowHistory("wanted") end
        ns.BountyNewsSeen()
    end)
    f.news:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Bounty news")
        local now = time()
        for i = #(ns.bountyNews or {}), math.max(1, #(ns.bountyNews or {}) - 7), -1 do
            local n = ns.bountyNews[i]
            GameTooltip:AddLine(n.msg .. "  |cff808080" .. ns.AgoLong(now - n.t) .. " ago|r", 1, 1, 1, true)
        end
        GameTooltip:AddLine("|cffffd100Click:|r the Wanted list  ·  |cffffd100Right-click:|r seen", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f.news:SetScript("OnLeave", GameTooltip_Hide)
    f.news:Hide()
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.count:SetPoint("RIGHT", f.news, "LEFT", -8, 0)   -- (the coin's place stays: nothing moves when it shows)
    f.count:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    -- ms and fps after the title, once a second (two cheap calls): green / yellow / red by how good it is
    f.stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.stats:SetPoint("RIGHT", f.count, "LEFT", -8, 0)   -- left of the count, so the two never overlap
    -- a timer, not a check every frame; nothing to do while the list is hidden
    local function Stats()
        local self = f
        if not self:IsShown() then return end
        if db().nearbyStats == false then self.stats:SetText("") return end
        local ms = select(4, GetNetStats())
        ms = tonumber(ms) or 0
        local fps = math.floor((tonumber(GetFramerate()) or 0) + 0.5)
        local mc = ms < 100 and "|cff40ff40" or ms < 250 and "|cffffd100" or "|cffff4040"
        local fc = fps >= 50 and "|cff40ff40" or fps >= 25 and "|cffffd100" or "|cffff4040"
        self.stats:SetText(mc .. ms .. "|r|cff999999ms|r " .. fc .. fps .. "|r|cff999999fps|r")
        -- no room next to the title: leave it out rather than write over it
        local tr, sl = self.title:GetRight(), self.stats:GetLeft()
        if tr and sl and sl < tr + 4 then self.stats:SetText("") end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() ns.Safe("nearby stats", Stats) end) end
    f:HookScript("OnShow", function() ns.Safe("nearby stats", Stats) end)   -- right away when it comes up
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
    -- the header: click = the list (History), right-click = settings
    f:SetScript("OnMouseUp", function(_, button)
        if moving then return end
        if button == "RightButton" then ns.OpenNearbySettings() elseif button == "LeftButton" then ns.ShowHistory() end
    end)
    f:SetScript("OnEnter", function(self)
        if moving then return end
        Tip(self, "Enemies", "Enemy players around you. Click a row to target.",
            "|cffffd100Click here:|r everyone you've met (History)  ·  |cffffd100Right-click:|r settings")
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:SetScript("OnDragStart", function(self)
        if moving and not self.attached and not InCombatLockdown() then self.dragging = true; self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        if not self.dragging then return end   -- a stray drag (locked, attached, in combat) doesn't touch it
        self.dragging = nil
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        SavePoint(self, "nearbyPoint")
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not moving or self.attached or InCombatLockdown() then return end   -- attached: sized with the mini bar
        Rescale(self, "nearbyScale", delta)
        SavePoint(self, "nearbyPoint")
        if ns.NearbyLabel then ns.NearbyLabel() end
    end)
    AddGrips(f, function(self, st, cx, cy)
        if InCombatLockdown() then return end
        SizeTo(self, st, cx, cy, self:GetHeight(), "nearbyScale", "nearbyWidth")
        self:SetWidth(NearbyWidth())
        if ns.NearbyLabel then ns.NearbyLabel() end
    end, function(self) if not InCombatLockdown() then SavePoint(self, "nearbyPoint") end end)
    f:Hide()
    return f
end

-- Attached: the list hangs under the mini bar – same width and size, it moves with it. (Not in combat:
-- the list holds secure rows, so it can't be moved then.) Only with the list switched on: a list hanging
-- under it makes the mini bar count as protected in combat.
function Attached() return db().nearbyAttach ~= false and db().nearby and mini ~= nil and true or false end

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
    return math.max(mini:GetWidth() or 0, ns.NearbyAttachWidth())   -- (a list that isn't there doesn't widen it)
end
function ns.StackKey()
    return mini and (tostring(mini.visible) .. tostring(TargetShown() and not OwnSpot())) or ""
end

function ns.AttachNearby()
    -- in a fight the attached list can't move: the XP bar above it stays put too, so it can't slide over the list
    if ns.PlaceXPBar and not (InCombatLockdown() and nb and nb.attached) then ns.PlaceXPBar() end
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

-- A row is only touched where something changed (it's painted every second, mostly the same).
local function PaintNearbyRow(r, e, now)
    local cr, cg, cb = ClassColor(e.class)
    local near = now - e.last <= ns.NEARBY_ACTIVE
    local rec = ns.db.enemies[e.key]
    local healer = ns.db.plateHealer ~= false and ns.IsHealer(e.key)
    local wanted = ns.Wanted and ns.Wanted(e.key)   -- also a bounty on just the first name
    local name = (e.kos and "|cffff3030KOS|r " or "") .. (wanted and "|cffffa000WANTED|r " or "")
        .. ((rec and rec.avoid) and "|cffff8040AVOID|r " or "")
        .. (healer and "|cff40ff60+|r " or "") .. e.name
        .. ((rec and rec.note) and " |cffffd100*|r" or "")
    local tags = ""
    if e.stealth and now - e.stealth < 60 then tags = tags .. "|cffd8a0ffSTEALTH|r  " end
    if e.targetingMe and now - e.targetingMe < 10 then tags = tags .. "|cffff5050> you|r  " end
    local lvl = (e.level and e.level > 0) and tostring(e.level) or "??"
    local info = tags .. lvl .. " " .. ClassName(e.class) .. (near and "" or ("  |cffaaaaaa" .. Ago(now - e.last) .. "|r"))
    local look = (e.class or "") .. (near and "1" or "0")
    if r.look ~= look then
        r.look = look
        r.bar:SetColorTexture(cr * 0.6, cg * 0.6, cb * 0.6, near and 0.9 or 0.35)
        r.name:SetTextColor(near and 1 or 0.7, near and 1 or 0.7, near and 1 or 0.7)
    end
    if r.nameText ~= name then r.nameText = name; r.name:SetText(name) end
    if r.infoText ~= info then r.infoText = info; r.info:SetText(info) end
    r.shownKey = e.key
    if r:GetAlpha() ~= 1 then r:SetAlpha(1) end
end

local PlaceToast
local function RefreshNearby()
    if not nb then return end
    nb:SetAlpha((not moving and ns.NearbyZoneMode() == "fade") and 0.35 or 1)   -- alpha is fine in combat
    -- the warning card follows the list once it's shown/hidden and placed (out of combat: it can't move then)
    local function Card() if toast and toast:IsShown() and PlaceToast then PlaceToast() end end
    local d = db()
    local combat = InCombatLockdown()
    local list = d.nearby and ns.NearbyList() or {}
    -- the coin: shown while there's bounty news you haven't looked at (a plain button: also in a fight)
    local news = (ns.bountyUnread or 0) > 0
    if nb.news.shown ~= news then
        nb.news.shown = news
        nb.news:SetShown(news)
        if nb.news.pulse then if news then nb.news.pulse:Play() else nb.news.pulse:Stop() end end
    end
    if news then nb.news.num:SetText(ns.bountyUnread > 1 and ns.bountyUnread or "") end
    local now, near = time(), 0
    for _, e in ipairs(list) do if now - e.last <= ns.NEARBY_ACTIVE then near = near + 1 end end
    local hidden = #list - NearbyMax()
    nb.count:SetText((near > 0 and (near .. " near") or (#list > 0 and (#list .. " recent") or ""))
        .. (hidden > 0 and ("  |cffaaaaaa+" .. hidden .. "|r") or ""))
    if not combat then
        local zone = ns.NearbyZoneMode()
        local want = d.nearby and (moving or (zone ~= "hide" and (#list > 0 or d.nearbyShowEmpty == true or news)))
        nb:SetShown(want and true or false)
        if not want then nb.rowSig = nil; Card() return end
        local n = math.min(#list, NearbyMax())
        local keys = {}
        for i = 1, n do keys[i] = list[i].key end
        local sig = table.concat(keys, "|") .. "#" .. n .. tostring(moving)
        if sig == nb.rowSig then   -- the same players: just repaint what changed
            for i = 1, n do PaintNearbyRow(nb.rows[i], list[i], now) end
            Card()
            return
        end
        nb.rowSig = sig
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
        Card()
    elseif nb:IsShown() then
        nb.rowSig = nil   -- redo the rows properly after the fight
        -- secure rows can't change in combat: each row keeps its player, newcomers fill the empty rows
        -- (shown only – a click there does nothing until the fight is over)
        local onRow = {}
        for _, r in ipairs(nb.rows) do
            local e = r.key and ns.nearby[r.key]
            if e then PaintNearbyRow(r, e, now); onRow[e.key] = true end
        end
        local i, painted = 1, {}
        for _, e in ipairs(list) do
            if not onRow[e.key] then
                while nb.rows[i] and nb.rows[i].key do i = i + 1 end
                local r = i <= NearbyMax() and nb.rows[i]
                if not r then break end
                PaintNearbyRow(r, e, now)
                painted[r] = true
                i = i + 1
            end
        end
        for _, r in ipairs(nb.rows) do   -- a newcomer that left again: its row empties (alpha is fine in combat)
            if not r.key and not painted[r] and r.shownKey then r.shownKey = nil; r:SetAlpha(0) end
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
    bountyNew = { head = "NEW BOUNTY", r = 1, g = 0.63, b = 0, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    bountyKill = { head = "BOUNTY CLAIMED", r = 0.35, g = 1, b = 0.35, icon = "Interface\\Icons\\Ability_Rogue_Eviscerate" },
    bountyOwe = { head = "YOU OWE A BOUNTY", r = 1, g = 0.45, b = 0.15, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    bountyPaid = { head = "BOUNTY PAID", r = 0.35, g = 1, b = 0.35, icon = "Interface\\Icons\\INV_Misc_Coin_01" },
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
    if ns.PlaceCard then ns.PlaceCard() end   -- the click on it goes along (out of combat)
end

function ns.ShowStealthToast(e, kind)
    if not toast then
        toast = CreateFrame("Frame", "WatchXStealthToast", UIParent)
        toast:SetSize(230, 40)
        toast:SetFrameStrata("HIGH")
        toast:SetMovable(true)
        toast:SetClampedToScreen(true)
        toast:RegisterForDrag("LeftButton")
        toast:SetScript("OnDragStart", function(self)
            if moving and not self.docked and not InCombatLockdown() then self.dragging = true; self:StartMoving() end
        end)
        toast:SetScript("OnDragStop", function(self)
            if not self.dragging then return end
            self.dragging = nil
            self:StopMovingOrSizing()
            if ns.Snap then ns.Snap(self) end
            SavePoint(self, "toastPoint")
            if ns.PlaceCard then ns.PlaceCard() end
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
            -- its secure click can't be taken away in a fight: the card stays up as long as that click is there,
            -- so what you click is what you see
            if self.armed and InCombatLockdown() then self:SetAlpha(1) return end
            local left = (self.untilT or 0) - GetTime()
            if left <= 0 then self:Hide() elseif left < 1 then self:SetAlpha(left) end
        end)
        toast:SetScript("OnHide", function() if ns.DisarmCard then ns.DisarmCard() end end)
    end
    -- a card with a click on it can't change player in a fight: the newest one waits until it's over
    if InCombatLockdown() and toast.armed and toast:IsShown() and not e.sample then
        toast.queue = function() return ns.ShowStealthToast(e, kind) end
        return false
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
    elseif ns.DisarmCard then
        ns.DisarmCard()   -- the example card: no click left over from the last one
    end
    return true
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
            local p = self.player   -- the one its click targets (the card may show someone newer)
            Tip(self, p and p.name or "?", "|cffffd100Click:|r target", "|cffffd100Right-click:|r dismiss")
        end)
        cardBtn:SetScript("OnLeave", GameTooltip_Hide)
        cardBtn:SetScript("OnUpdate", function(self)   -- fades with the card (alpha is allowed in combat)
            if toast then self:SetAlpha(toast:IsShown() and toast:GetAlpha() or 0) end
        end)
    end
    cardBtn:SetAttribute("macrotext1", ns.TargetMacro(e.first or e.name, e.name, e.key or e.name))
    cardBtn.player = e
    if not ns.PlaceCard() then return end
    cardBtn:Show()
    toast.armed = true
    toast.hint:SetText("click: target")
    toast.waitCombat = false
end

-- Lay the click exactly over the card (out of combat only: it's a secure button). False when the card has no spot yet.
function ns.PlaceCard()
    if not (cardBtn and toast) or InCombatLockdown() then return false end
    local l, t, r, b = toast:GetLeft(), toast:GetTop(), toast:GetRight(), toast:GetBottom()
    if not (l and t and r and b) then return false end
    local sc = toast:GetScale() or 1
    cardBtn:ClearAllPoints()
    cardBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * sc, t * sc)
    cardBtn:SetSize((r - l) * sc, (t - b) * sc)
    return true
end

function ns.DisarmCard()
    if cardBtn and not InCombatLockdown() then
        cardBtn:Hide()
        cardBtn.player = nil
        if toast then toast.armed = nil end
    end
end

-- ---------------------------------------------------------------- PvP sounds, one choice per kind
-- The game's own sounds (SOUNDKIT names, with stand-ins if WoW Forever lacks one). db.sounds[kind] = a key
-- below, or "off"; "Sounds" (db.stealthSound) switches them all off at once.
-- Each: SOUNDKIT names and the game's sound kit numbers (what other addons on Forever use), tried in order until
-- the game says it plays one. Sounds this client doesn't have are left out of the list (ns.SoundList).
ns.SOUND_CHOICES = {
    { key = "off",       label = "Off" },
    { head = "Alarms" },
    { key = "raid",      label = "Raid warning",     kit = { "RAID_WARNING", 8959 } },
    { key = "bossemote", label = "Boss warning",     kit = { "RAID_BOSS_EMOTE_WARNING" } },
    { key = "boss",      label = "Boss whisper",     kit = { "UI_RAID_BOSS_WHISPER_WARNING", 37666 } },
    { key = "alarm",     label = "Alarm clock",      kit = { "ALARM_CLOCK_WARNING_3", 12889 } },
    { key = "alarm2",    label = "Alarm, short",     kit = { "ALARM_CLOCK_WARNING_2", 12867 } },
    { key = "alarm1",    label = "Alarm, soft",      kit = { "ALARM_CLOCK_WARNING_1" } },
    { key = "horn",      label = "War horn",         kit = { "UI_GARRISON_TOAST_INVASION_ALERT" } },
    { key = "ready",     label = "Ready check",      kit = { "READY_CHECK", 8960 } },
    { key = "pvp",       label = "PvP queue",        kit = { "PVP_THROUGH_QUEUE", 8459 } },
    { key = "pvpenter",  label = "PvP join",         kit = { "PVP_ENTER_QUEUE" } },
    { key = "count",     label = "Countdown tick",   kit = { "UI_BATTLEGROUND_COUNTDOWN_TIMER" } },
    { key = "countend",  label = "Countdown end",    kit = { "UI_BATTLEGROUND_COUNTDOWN_FINISHED" } },
    { head = "Soft" },
    { key = "ping",      label = "Map ping",         kit = { "MAP_PING", 3175 } },
    { key = "whisper",   label = "Whisper",          kit = { "TELL_MESSAGE", 3081 } },
    { key = "toast",     label = "Friend online",    kit = { "UI_BNET_TOAST" } },
    { key = "invite",    label = "Invite",           kit = { "IG_PLAYER_INVITE", 880 } },
    { head = "Rewards" },
    { key = "coins",     label = "Coins",            kit = { "LOOT_WINDOW_COIN_SOUND", 120 } },
    { key = "quest",     label = "Quest done",       kit = { "IG_QUEST_LIST_COMPLETE", 878 } },
    { key = "levelup",   label = "Level up",         kit = { "LEVELUPSOUND", "LEVEL_UP" } },
    { key = "epic",      label = "Epic loot",        kit = { "UI_EPICLOOT_TOAST" } },
    { key = "legendary", label = "Legendary loot",   kit = { "UI_LEGENDARY_LOOT_TOAST" } },
    { key = "auction",   label = "Auction house",    kit = { "AUCTION_WINDOW_OPEN" } },
}
-- the ones this client has (a number always counts; a name only if the game knows it), headings kept when
-- something is under them
function ns.SoundList()
    if ns.soundList then return ns.soundList end
    local out, head = {}, nil
    for _, c in ipairs(ns.SOUND_CHOICES) do
        if c.head then head = c
        else
            local have = c.key == "off"
            for _, k in ipairs(c.kit or {}) do
                if type(k) == "number" or (SOUNDKIT and SOUNDKIT[k]) then have = true end
            end
            if have then
                if head then out[#out + 1] = head; head = nil end
                out[#out + 1] = c
            end
        end
    end
    ns.soundList = out
    return out
end
function ns.SoundLabel(key)
    for _, c in ipairs(ns.SOUND_CHOICES) do if c.key == key then return c.label end end
    return key
end
-- The list to pick from, under the sound's button: click one to hear it and choose it (it stays open to try more;
-- a click anywhere else or Esc closes it).
function ns.ToggleSoundMenu(anchor, kind, onPick)
    local m = ns.soundMenu
    if not m then
        m = CreateFrame("Frame", "WatchXSoundMenu", UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m:SetWidth(170)
        Flat(m)
        m.rows, m.heads = {}, {}
        tinsert(UISpecialFrames, "WatchXSoundMenu")
        ns.MenuAutoClose(m)
        ns.soundMenu = m
    end
    if m:IsShown() and m.anchor == anchor then m:Hide() return end
    m.anchor, m.kind, m.onPick = anchor, kind, onPick
    local cur, y, nr, nh = ns.SoundChoice(kind), -6, 0, 0
    for _, c in ipairs(ns.SoundList()) do
        if c.head then
            nh = nh + 1
            local h = m.heads[nh]
            if not h then
                h = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                h:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
                m.heads[nh] = h
            end
            h:SetText(c.head:upper())
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", m, "TOPLEFT", 10, y - 4)
            h:Show()
            y = y - 18
        else
            nr = nr + 1
            local r = m.rows[nr]
            if not r then
                r = MenuRow(m, 154, function(self)
                    if type(db().sounds) ~= "table" then db().sounds = {} end
                    db().sounds[m.kind] = self.key
                    ns.TrySound(self.key)
                    if m.onPick then m.onPick() end
                    ns.ToggleSoundMenu(m.anchor, m.kind, m.onPick)   -- (closes:)
                    ns.ToggleSoundMenu(m.anchor, m.kind, m.onPick)   -- (open again, marked)
                end)
                m.rows[nr] = r
            end
            r.key = c.key
            r:SetText(c.key == cur and ("|cffffd100> " .. c.label .. "|r") or ("   " .. c.label))
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", m, "TOPLEFT", 8, y)
            r:Show()
            y = y - 18
        end
    end
    for i = nr + 1, #m.rows do m.rows[i]:Hide() end
    for i = nh + 1, #m.heads do m.heads[i]:Hide() end
    m:SetHeight(-y + 6)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    m:Show()
end
ns.SOUND_KINDS = {   -- (in the settings in this order)
    { kind = "stealth", label = "Stealth",          def = "raid" },
    { kind = "kos",     label = "Kill on sight",    def = "alarm" },
    { kind = "wanted",  label = "WANTED nearby",    def = "boss" },
    { kind = "enemy",   label = "New enemy nearby", def = "off", hint = "at most every 5 s" },
    { kind = "bounty",  label = "Bounty news",      def = "coins", hint = "posted, claimed, paid" },
}
function ns.SoundChoice(kind)
    local v = type(db().sounds) == "table" and db().sounds[kind]
    if v then return v end
    for _, k in ipairs(ns.SOUND_KINDS) do if k.kind == kind then return k.def end end
    return "off"
end
-- true when the game said it plays it. PlaySound answers "will it play" first; a false or an error: the next one.
function ns.PlayChoice(key)
    if not PlaySound then return false end
    for _, c in ipairs(ns.SOUND_CHOICES) do
        if c.key == key and c.kit then
            for _, k in ipairs(c.kit) do
                local id = type(k) == "number" and k or (SOUNDKIT and SOUNDKIT[k])
                if id then
                    local ok, will = pcall(PlaySound, id, "Master")
                    if ok and will ~= false then return true end
                end
            end
        end
    end
    return false
end
-- From the settings (a pick or the > button): say so when nothing could be heard.
function ns.TrySound(key)
    if key == "off" then return end
    -- the game's sound switched off (or the Master volume at 0): the game says "it plays", but nothing is heard
    local on, vol = GetCVar and GetCVar("Sound_EnableAllSound"), GetCVar and tonumber(GetCVar("Sound_MasterVolume"))
    if on == "0" or vol == 0 then
        ns.Print("|cffff8040Your game sound is off|r" .. (on == "0" and "" or " (Master volume 0)")
            .. " – turn it on in |cffffd100System > Audio|r to hear WatchX's sounds.")
    end
    if not ns.PlayChoice(key) then
        ns.Print("|cffff8040No sound played|r – the game wouldn't play it. Is |cffffd100Sound Effects|r on "
            .. "(System > Audio), and the Master volume up?")
    end
end
function ns.AlertSound(kind)
    if db().stealthSound == false then return end   -- "Sounds" off: none of them
    local choice = ns.SoundChoice(kind)
    if choice == "off" then return end
    if kind == "enemy" then
        if GetTime() - (ns.lastEnemySound or -99) < 5 then return end
        ns.lastEnemySound = GetTime()
    end
    ns.PlayChoice(choice)
end

-- ---------------------------------------------------------------- telling your party / guild what you spot
-- When ticked: a line in party (raid) and / or guild chat for stealth, KOS, WANTED – or every new enemy. Plain words
-- (chat takes no colours), the name in [ ] so other WatchX can read it back. Once a minute per player and kind, a line
-- at most every 3 s (10 s for "every enemy"); what another WatchX here just said isn't said again. Not in
-- battlegrounds or arenas.
ns.spotSaid = {}   -- lower-case name .. ":" .. kind -> when it was said (by you or someone else)
ns.SPOT_HEAD = { stealth = "Stealth", kos = "Kill on sight", wanted = "WANTED", enemy = "Enemy" }
-- force = "say" / "party" / "guild": you asked for it (the player's menu) – said there, whatever the ticks. (Say
-- outdoors needs a click on this client: the menu is one.)
function ns.ShareSpot(e, kind, extra, force)
    local d = db()
    if not (d and e and type(e.name) == "string") then return end
    local now = GetTime()
    local k = e.name:lower() .. ":" .. kind
    if force then
        if now - (ns.spotLast or -99) < 1 then return end   -- (a double click)
    else
        if not (d.shareParty or d.shareGuild) then return end
        local want = (kind == "stealth" and d.shareStealth ~= false) or (kind == "kos" and d.shareKOS ~= false)
            or (kind == "wanted" and d.shareWanted ~= false) or (kind == "enemy" and d.shareAll == true)
        if not want then return end
        if IsInInstance then
            local _, it = IsInInstance()
            if it == "pvp" or it == "arena" then return end
        end
        if ns.spotSaid[k] and now - ns.spotSaid[k] < 60 then return end
        if now - (ns.spotLast or -99) < (kind == "enemy" and 10 or 3) then return end
    end
    -- who, what, where
    local info = ((e.level and e.level > 0) and (" " .. e.level) or (e.level == -1 and " ??" or ""))
        .. (e.class and (" " .. e.class:sub(1, 1) .. e.class:sub(2):lower()) or "")
    local more = ""
    if kind == "stealth" and type(extra) == "string" and extra ~= "" then more = " (" .. extra .. ")" end
    if kind == "wanted" and type(extra) == "table" then
        local c = math.floor(tonumber(extra.copper) or 0)
        if c > 0 then
            local g, sv = math.floor(c / 10000), math.floor(c / 100) % 100
            more = " – " .. (g > 0 and (g .. "g") or "") .. (sv > 0 and ((g > 0 and " " or "") .. sv .. "s") or "")
                .. ((tonumber(extra.kills) or 1) > 1 and " a kill" or "")
        end
    end
    local function P(v) if issecretvalue and v ~= nil and issecretvalue(v) then return nil end return v end
    local where = GetZoneText and P(GetZoneText()) or nil
    local map, x, y
    if ns.PlayerPos then map, x, y = ns.PlayerPos() end   -- (not "a and f()": that keeps only the first value)
    if map and x then where = (where or "") .. (" %d,%d"):format(math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5)) end
    local msg = "WatchX: " .. ns.SPOT_HEAD[kind] .. " – [" .. e.name .. "]" .. info
        .. (e.guild and (" <" .. e.guild .. ">") or "") .. more .. (where and where ~= "" and (" · " .. where) or "")
    local sent = false
    if force == "say" then sent = (ns.SendChat and ns.SendChat(msg:sub(1, 255), "SAY")) or sent end
    local toParty = (force == "party") or (not force and d.shareParty)
    local toGuild = (force == "guild") or (not force and d.shareGuild)
    if toParty and IsInGroup and IsInGroup() then
        local chan = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
        if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then chan = "INSTANCE_CHAT" end
        sent = (ns.SendChat and ns.SendChat(msg:sub(1, 255), chan)) or sent
    end
    if toGuild and IsInGuild and IsInGuild() then
        sent = (ns.SendChat and ns.SendChat(msg:sub(1, 255), "GUILD")) or sent
    end
    if sent then
        ns.spotSaid[k], ns.spotLast = now, now
        ns.spotCount = (ns.spotCount or 0) + 1
        if ns.spotCount > 300 then   -- (an old list is cleared now and then)
            for key, t in pairs(ns.spotSaid) do if now - t >= 60 then ns.spotSaid[key] = nil end end
            ns.spotCount = 0
        end
    end
end
-- Someone's WatchX said it already (party, raid or guild): yours keeps quiet about that player for a minute.
do
    local hear = CreateFrame("Frame")
    for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD",
                          "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do pcall(hear.RegisterEvent, hear, ev) end
    hear:SetScript("OnEvent", function(_, _, msg)
        if issecretvalue and msg ~= nil and issecretvalue(msg) then return end   -- (a hidden chat line: can't be read)
        if type(msg) ~= "string" or msg:sub(1, 8) ~= "WatchX: " then return end
        local head, name = msg:match("^WatchX: (.-) – %[(.-)%]")
        if not (head and name) then return end
        for kind, h in pairs(ns.SPOT_HEAD) do
            if h == head then ns.spotSaid[name:lower() .. ":" .. kind] = GetTime() end
        end
    end)
end

-- A KOS player showed up: the KOS card always wins, with a sound.
function ns.OnKOS(e)
    if not db().nearby then return end
    ns.Print("|cffff3030Kill on sight:|r " .. e.name .. (e.guild and (" <" .. e.guild .. ">") or ""))
    ns.AlertSound("kos")
    ns.ShowStealthToast(e, "kos")
end

-- A wanted player showed up: the WANTED card with the reward, and a sound.
function ns.OnWantedSeen(e, w)
    if not db().nearby then return end
    local rw = ns.WantedReward(w)
    ns.Print("|cffffa000WANTED|r nearby: " .. e.name .. (rw and (" – " .. rw) or "") .. (w.by and (" (from " .. w.by .. ")") or ""))
    ns.AlertSound("wanted")
    local function Card()   -- (waits until the fight is over when a card with a click is up)
        if not ns.ShowStealthToast(e, "wanted") then
            if toast then toast.queue = Card end
        elseif rw then
            toast.head:SetText("WANTED!  " .. rw)
        end
    end
    Card()
end

-- Bounty news for the Nearby header: the last 10, and how many you haven't looked at.
function ns.AddBountyNews(kind, who, reward, from, msg)
    ns.bountyNews = ns.bountyNews or {}
    table.insert(ns.bountyNews, { kind = kind, who = who, msg = msg or (tostring(who) .. " – " .. tostring(kind)), t = time() })
    while #ns.bountyNews > 10 do table.remove(ns.bountyNews, 1) end
    ns.bountyUnread = (ns.bountyUnread or 0) + 1
    if ns.RefreshUI then ns.RefreshUI() end
end
function ns.BountyNewsSeen()
    ns.bountyUnread = 0
    GameTooltip_Hide()
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Bounty news as a card, like the stealth one: kind = bountyNew / bountyKill / bountyOwe / bountyPaid.
-- who: the wanted player; reward: shown in the head; from: small, top right (who posted it / who killed).
function ns.BountyCard(kind, who, reward, from, class)
    local k = TOAST_KINDS[kind]
    if not k then return false end
    local function Card()   -- (waits until the fight is over when a card with a click is up)
        if not ns.ShowStealthToast({ name = who or "?", class = class }, kind) then
            if toast then toast.queue = Card end
            return
        end
        toast.head:SetText(k.head .. (reward and ("   " .. reward) or ""))
        -- who did it / who posted it: on the name's line (in the corner it ran into the heading)
        toast.name:SetText((who or "?") .. (from and ("  |cffcccccc" .. from .. "|r") or ""))
        toast.hint:SetText("")
        PlaceToast()   -- as wide as the new lines need (on its own spot)
        toast.untilT = GetTime() + 9
        toast.bountyUntil = toast.untilT   -- a new-enemy card doesn't push it away
    end
    Card()
    if not toast then return false end
    ns.AlertSound("bounty")
    return true
end

-- A new enemy in the list: the red card (not more often than every few seconds).
local lastEnemyToast = 0
function ns.OnNewEnemy(e)
    if not db().nearby then return end
    ns.AlertSound("enemy")   -- (its own choice: works with the card off too)
    if db().newEnemyCard ~= true then return end
    if toast and toast:IsShown() and GetTime() < (toast.bountyUntil or 0) then return end
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
        nbLabel:Set(top, "|cffffd100Enemies|r · drag to move · right edge: width · bottom edge: text size (" .. Pct(nb:GetScale() or 1) .. ")")
    end
end

function ns.NearbyMove(on)
    if not nb or InCombatLockdown() then return end
    if not on then   -- a drag still going (a fight starts): stopped while that's still allowed
        for _, f in ipairs({ nb, toast or false }) do
            if f and f.dragging then f.dragging = nil; f:StopMovingOrSizing() end
        end
    end
    ShowGrips(nb, on and db().nearby and not nb.attached)
    nb:EnableMouseWheel((on and not nb.attached) and true or false)   -- attached: sized with the mini bar
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
    local xpBottom = ns.XPBarBottom and ns.XPBarBottom()   -- or under the small XP bar there
    if xpBottom then return x, xpBottom - 2 end
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
    if type(name) ~= "string" or name:find("[%c/;%[%]|]") then return "" end   -- a name, nothing that runs more
    local m = ns.db and ns.db.mobs and ns.db.mobs[name]   -- read only: a player who pops the bar isn't saved as a mob
    if m and m.isPlayer and m.full and m.key then return ns.TargetMacro(name, m.full, m.key) end
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
        local spot = math.floor(x + 0.5) .. ":" .. math.floor(top + 0.5) .. ":" .. sc
        if targetBtn.spot ~= spot or not targetBtn:IsShown() then   -- placed again only when its spot moved
            targetBtn.spot = spot
            targetBtn:SetScale(sc)
            targetBtn:ClearAllPoints()
            targetBtn:SetPoint("TOP", UIParent, "BOTTOMLEFT", x / sc, top / sc)
            targetBtn:Show()
        end
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
        Bullet(Y .. "Enemies|r – its own page under WatchX (PvP): a list of enemy players around you (like Spy)."),
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
    if preset.mapFound then return preset.mapFound end   -- looked up once, found or not (a miss isn't searched again)
    local id = preset.mapID
    if C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(preset.mapID)
        if not (info and info.name == preset.zone) then
            for i = 1, 2500 do   -- another client: find the zone by name
                local m = C_Map.GetMapInfo(i)
                if m and m.name == preset.zone and (m.mapType == 3 or m.mapType == nil) then id = i; break end
            end
        end
    end
    preset.mapFound = id
    return id
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
    if ns.kosDirty then   -- the PvP page's KOS and avoid lists: only when they changed (they scan every player)
        ns.kosDirty = nil
        if ns.RefreshKOSChips then ns.RefreshKOSChips() end
        if ns.RefreshAvoidCount and nearbyPage and nearbyPage:IsShown() then ns.RefreshAvoidCount() end
    end
    if ns.historyDirty then ns.historyDirty = nil; ns.RefreshHistory() end   -- KOS / avoid / forget changed
    local wasShown = TargetShown()
    ns.UpdateTargetButton()
    -- the red bar came or went: the stack under it moves now (it was placed before the bar changed)
    if (TargetShown() or false) ~= (wasShown or false) and ns.AttachNearby then ns.AttachNearby() end
    -- the yellow bar sits under the stack: placed again whenever the stack's bottom moved (a line more, the list…)
    local bx, btop = BarSpot()
    local spot = math.floor(bx + 0.5) .. ":" .. math.floor(btop + 0.5)
    if spot ~= ns.barSpotKey then ns.barSpotKey = spot; ns.UpdateChatLogPrompt() end
    if panel and panel:IsShown() then RefreshPanel() end
end
-- Guarded: an error is shown once in chat (and in /wx log) instead of stopping the bars and the panel.
-- Lots of events want a refresh (a burst of nameplates at login can be dozens a second): they're gathered into at
-- most one refresh every 0.15 s – the first right away, the rest a moment later.
local refreshAt, refreshQueued = 0, false
local function RunRefresh()
    refreshQueued = false
    refreshAt = GetTime()
    ns.Safe("refresh", RefreshUIInner)
end
function ns.RefreshUI()
    local wait = 0.15 - (GetTime() - refreshAt)
    if wait <= 0 then RunRefresh() return end
    if refreshQueued or not C_Timer then return end
    refreshQueued = true
    C_Timer.After(wait, RunRefresh)
end

-- a chat log bar that couldn't be made or moved in combat is done once combat ends
local uiEvents = CreateFrame("Frame")
uiEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
uiEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
uiEvents:SetScript("OnEvent", ns.Timed(function(_, event)
    if not ns.db then return end
    if event == "PLAYER_REGEN_DISABLED" then
        -- a fight starts (the last moment protected frames may still change): unlocked bars lock now
        if moving then ns.StopMove("Locked – a fight started (the bars can't move in combat).") end
        return
    end
    if toast and toast.queue then   -- the newest card, which waited for the fight to end
        local q = toast.queue
        toast.queue = nil
        q()
    elseif toast and toast:IsShown() and toast.waitCombat then
        toast.untilT = GetTime() + 6
        ns.ArmCard()
    elseif not (toast and toast:IsShown()) then
        ns.DisarmCard()   -- a card that went away during combat
    end
    if not nb then nb = BuildNearby() end
    if ns.layoutPending then ns.layoutPending = nil; ns.ApplyLayout() end   -- a profile switched during the fight
    RefreshNearby()
    ns.UpdateTargetButton()
    if promptPending then ns.UpdateChatLogPrompt() end
end, "UI events"))

-- After a profile switch: the bars' spot and size, and the settings page if it's open.
function ns.ApplyLayout()
    if InCombatLockdown() then ns.layoutPending = true end   -- what can't change in a fight is done right after it
    if mini and not MiniFrozen() then
        mini:SetScale(MiniScale())
        LoadPoint(mini, "miniPoint", { "TOP", "TOP", 0, -120 })
        mini.sig = nil
        RefreshMini()
    end
    ns.UpdateTargetButton()
    if nb and not InCombatLockdown() then
        nb.rowSig = nil   -- the rows and the spot are worked out again
        if Attached() or nb.attached then ns.AttachNearby() end   -- under the mini bar, or back to its own spot
        if not nb.attached then
            nb:SetScale(NearbyScale())
            nb:SetWidth(NearbyWidth())
            LoadPoint(nb, "nearbyPoint", { "TOPRIGHT", "TOPRIGHT", -240, -220 })
        end
        RefreshNearby()
    end
    if ns.ApplyLevelLayout then ns.ApplyLevelLayout() end
    if toast and toast:IsShown() and not InCombatLockdown() then PlaceToast() end
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
local LV_MAX, LV_ICON, LV_GAP, LV_PAD, LV_TIME = 5, 30, 5, 5, 0   -- the time sits on the icon (no line under it)
local LV_H = LV_PAD * 2 + LV_ICON
local LV_BADGES = { ok = "Interface\\RaidFrame\\ReadyCheck-Ready", todo = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    wait = "Interface\\RaidFrame\\ReadyCheck-Waiting" }
local LV_COLORS = { ok = { 0.25, 0.9, 0.3 }, todo = { 1, 0.2, 0.2 }, wait = { 1, 0.82, 0 }, info = { 0.4, 0.4, 0.4 } }
local LV_STATUS = { ok = "|cff40ff40You have it|r", todo = "|cffff6060Missing|r", wait = "|cffffd100Soon|r",
    info = "|cffaaaaaaWorth getting|r" }
local lv, lvLabel
local function LevelScale() return ClampScale(db().levelScale) end
local function LevelWidth(n) return LV_PAD * 2 + n * LV_ICON + math.max(0, n - 1) * LV_GAP end
-- seconds left on a row now (it's worked out every few seconds; the clock runs on from when it ends)
function ns.RowLeft(r) return r.ends and (r.ends - GetTime()) or r.timer end

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
    -- past the "+8%" box too: it sits on the same side (the one facing the middle of the screen)
    local edge = (lv.bonusBox and lv.bonusBox:IsShown()) and lv.bonusBox or lv
    if right then GameTooltip:SetPoint("BOTTOMRIGHT", edge, "BOTTOMLEFT", dx - 4, 0)
    else GameTooltip:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", dx + 4, 0) end
end

local function LevelIconTip(self)
    local r = self.row
    if not r or moving then return end
    LevelTipOwner(self)
    local c = r.state == "info" and { 0.75, 0.75, 0.75 } or LV_COLORS[r.state] or { 1, 1, 1 }
    GameTooltip:SetText(r.name or "XP boost")
    GameTooltip:AddLine(r.text or "", c[1], c[2], c[3], true)
    local left = ns.RowLeft(r)
    if left then GameTooltip:AddLine("Time left: " .. ns.Clock(math.max(0, left)), 1, 0.82, 0) end
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
        if m.slot == "food" then ns.foodUsedAt = GetTime() end   -- (an XP food eaten: its buff can be learned)
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
        b.dim = b:CreateTexture(nil, "ARTWORK", nil, 1)   -- a soft shade under the time, so it reads on any icon
        b.dim:SetPoint("LEFT", b, "LEFT", 0, 0); b.dim:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        b.dim:SetHeight(14)
        b.dim:SetColorTexture(0, 0, 0, 0.55)
        b.dim:Hide()
        b.timer = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.timer:SetPoint("CENTER", b, "CENTER", 0, 1)   -- on the icon, outlined like a cooldown
        local tf = b.timer:GetFont()
        if tf then b.timer:SetFont(tf, 11, "OUTLINE") end
        b.timer:SetShadowOffset(0, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        b:SetScript("OnEnter", function(self) ns.Safe("xp tooltip", function(s) OpenLevelMenu(s); LevelIconTip(s) end, self) end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("PostClick", function(self, button)
            if button == "LeftButton" and self.row and self.row.slot == "food" then ns.foodUsedAt = GetTime() end
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
        local b = ns.levelBonus
        LevelTipOwner(self)   -- beside the strip and the box, not on top of them
        GameTooltip:SetText("XP boosts")
        for _, line in ipairs({ "Extra XP you have, and what you're missing. Hover an icon for how to get it.",
            b and ("|cff40ff40+" .. (b.food + b.bag) .. "% XP from kills|r: XP food " .. b.food .. "%, sleeping bag " .. b.bag .. "%"
                .. ((b.rested or 0) > 0 and ("\n|cff80b8ffRested " .. b.rested .. "% of a level|r: kills give double XP until it's spent" .. (b.tent and " (the tent filled it)" or "")) or "")) or false,
            "|cffffd100Right-click:|r settings  ·  gone at level " .. ns.MaxLevel() }) do
            if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        local c = ns.levelCamp
        if c then
            GameTooltip:AddLine(" ")
            if c.expires then
                GameTooltip:AddDoubleLine("Camp Benefits", ns.Clock(math.max(0, c.expires - GetTime())), 1, 0.82, 0, 1, 0.82, 0)
                local lines = c.lines or {}
                for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.25, 1, 0.35, true) end
                if #lines == 0 then GameTooltip:AddLine("(its text couldn't be read – hover the buff)", 0.6, 0.6, 0.6, true) end
            end
            if c.sitExpires then
                GameTooltip:AddLine("Sitting by the fire – Camp Benefits in " .. math.ceil(math.max(0, c.sitExpires - GetTime())) .. " s"
                    .. (c.expires and " (adds what's new)" or ""), 1, 0.82, 0, true)
            end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    -- the extra XP all together, in a small window beside the strip with one tile the size of the icons:
    -- "+8%" (food + sleeping bag) and "XP", or "R 12%" under it when you're rested. A plain frame, not secure:
    -- it may show, hide and change in a fight (it hangs on the strip; nothing protected hangs on it).
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(LV_H, LV_H)
    Flat(box)
    box.edge = box:CreateTexture(nil, "BORDER", nil, 1)
    box.edge:SetSize(LV_ICON + 4, LV_ICON + 4)
    box.edge:SetPoint("CENTER")
    box.edge:SetColorTexture(0.25, 0.9, 0.3, 1)
    box.inner = box:CreateTexture(nil, "BORDER", nil, 2)
    box.inner:SetSize(LV_ICON, LV_ICON)
    box.inner:SetPoint("CENTER")
    box.inner:SetColorTexture(0.06, 0.06, 0.06, 1)
    local function Text(size, y)
        local t = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local fnt = t:GetFont()
        if fnt then t:SetFont(fnt, size, "OUTLINE") end
        t:SetShadowOffset(0, 0)
        t:SetPoint("CENTER", box, "CENTER", 0, y)
        return t
    end
    f.bonus, f.bonus2 = Text(12, 5), Text(9, -7)
    box.camp = box:CreateTexture(nil, "OVERLAY", nil, 3)   -- Camp Benefits (or sitting for it): a little fire in the corner
    box.camp:SetSize(13, 13)
    box.camp:SetPoint("TOPRIGHT", box.inner, "TOPRIGHT", 4, 4)
    box.camp:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
    box.camp:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.camp:Hide()
    box:EnableMouse(true)
    box:SetScript("OnEnter", function() local h = f:GetScript("OnEnter"); if h then h(f) end end)
    box:SetScript("OnLeave", GameTooltip_Hide)
    box:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not moving and ns.OpenLevelSettings then ns.OpenLevelSettings() end
    end)
    box:Hide()
    f.bonusBox = box
    -- (secure icons inside: it can't move in a fight, and a stray drag while locked doesn't move or save it)
    f:SetScript("OnDragStart", function(self)
        if moving and not InCombatLockdown() then self.dragging = true; self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        self:StopMovingOrSizing()
        if ns.Snap then ns.Snap(self) end
        SavePoint(self, "levelPoint")
        LevelLabel()
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not moving or InCombatLockdown() then return end
        Rescale(self, "levelScale", delta)
        SavePoint(self, "levelPoint")
        LevelLabel()
    end)
    -- the missing ones pulse (a red glow and the edge), about once a second: the game's own animation, so it
    -- costs no Lua time at all (it used to be an OnUpdate every frame)
    for _, b in ipairs(f.icons) do
        local function Pulse(tex, from, to)
            if not tex.CreateAnimationGroup then return nil end
            local ag = tex:CreateAnimationGroup()
            if not ag then return nil end
            ag:SetLooping("BOUNCE")
            local an = ag:CreateAnimation("Alpha")
            an:SetFromAlpha(from)
            an:SetToAlpha(to)
            an:SetDuration(0.63)
            if an.SetSmoothing then an:SetSmoothing("IN_OUT") end
            return ag
        end
        b.pulse1 = Pulse(b.flash, 0.05, 0.4)
        b.pulse2 = Pulse(b.border, 0.4, 1)
        b.pulses = {}   -- (made once: painting doesn't make a new list every time)
        if b.pulse1 then b.pulses[#b.pulses + 1] = b.pulse1 end
        if b.pulse2 then b.pulses[#b.pulses + 1] = b.pulse2 end
    end
    -- any edge only changes the size (the icons keep their shape); the top-left corner stays put
    AddGrips(f, function(self, st, cx, cy)
        if InCombatLockdown() then return end
        local sc
        if st.mode == "R" then sc = ClampScale((cx - st.left) / (self.naturalW or LevelWidth(3)))
        else sc = ClampScale((st.top - cy) / LV_H) end
        db().levelScale = sc
        self:SetScale(sc)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.left / sc, st.top / sc)
        LevelLabel()
    end, function(self) if not InCombatLockdown() then SavePoint(self, "levelPoint") end end)
    f:Hide()
    return f
end

-- The clock on an icon: short, to fit (1h / 13m / 45), red under 2 minutes. Every second, from row.ends.
function ns.PaintLevelTimer(b, r)
    local left = ns.RowLeft(r)
    if left then
        local sec = math.max(0, math.floor(left))
        local t = sec >= 3600 and (math.floor(sec / 3600) .. "h") or sec >= 60 and (math.floor(sec / 60) .. "m") or tostring(sec)
        local col = left < 120 and 1 or (r.state == "wait" and 2 or 3)
        if b.timerText ~= t then b.timerText = t; b.timer:SetText(t) end
        if b.timerCol ~= col then
            b.timerCol = col
            if col == 1 then b.timer:SetTextColor(1, 0.35, 0.35)
            elseif col == 2 then b.timer:SetTextColor(1, 0.82, 0)
            else b.timer:SetTextColor(0.25, 1, 0.25) end
        end
        b.dim:Show()
    else
        if b.timerText ~= "" then b.timerText = ""; b.timer:SetText("") end
        b.dim:Hide()
    end
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
    b.timerCol = nil   -- (a new row: its colour is set again)
    ns.PaintLevelTimer(b, r)
    b.flashing = r.state == "todo"
    local pulse = b.flashing and db().levelFlash ~= false and not moving
    for _, ag in ipairs(b.pulses or {}) do
        if pulse and not ag:IsPlaying() then ag:Play() elseif not pulse and ag:IsPlaying() then ag:Stop() end
    end
    if lvMenu and lvMenu:IsShown() and lvMenu.owner == b then OpenLevelMenu(b) end   -- keep the column current
end

-- "+8% / XP" in the small window beside the icons (not secure: fine in a fight too). It sits on the side
-- that faces the middle of the screen, so it never goes off the edge.
local function PaintBonus()
    local box = lv and lv.bonusBox
    if not box then return end
    local b = ns.levelBonus
    local pct = b and (b.food + b.bag) or 0
    local rested = b and b.rested or 0
    local top = pct > 0 and ("|cff40ff40+" .. pct .. "%|r") or (rested > 0 and "|cff80b8ffR|r" or "")
    local bottom = rested > 0 and ("|cff80b8ff" .. (pct > 0 and "R " or "") .. rested .. "%|r") or (pct > 0 and "|cffccccccXP|r" or "")
    local c = ns.levelCamp
    if top == "" and bottom == "" and c then   -- no XP bonus, but a camp: "Camp" and its time
        local left = c.expires and (c.expires - GetTime()) or (c.sitExpires and (c.sitExpires - GetTime())) or 0
        top = "|cffffd100Camp|r"
        bottom = "|cffcccccc" .. (left >= 60 and (math.floor(left / 60) .. "m") or (math.ceil(math.max(0, left)) .. "s")) .. "|r"
    end
    box.camp:SetShown(c ~= nil)
    if c then box.camp:SetDesaturated(c.expires == nil) end   -- grey while you're still sitting for it
    local key = top .. "|" .. bottom
    if lv.bonusText ~= key then
        lv.bonusText = key
        lv.bonus:SetText(top)
        lv.bonus2:SetText(bottom)
        if pct > 0 then box.edge:SetColorTexture(0.25, 0.9, 0.3, 1)
        elseif rested > 0 then box.edge:SetColorTexture(0.5, 0.72, 1, 1)
        else box.edge:SetColorTexture(1, 0.6, 0.2, 1) end   -- only the camp
        box:SetShown(key ~= "|")
    end
    local right = LevelOnRight()
    if box.onRight ~= right then
        box.onRight = right
        box:ClearAllPoints()
        if right then box:SetPoint("RIGHT", lv, "LEFT", -3, 0) else box:SetPoint("LEFT", lv, "RIGHT", 3, 0) end
    end
end

function ns.RefreshLevel()
    if not lv then return end
    local d = db()
    local all = d.levelHelper ~= false and ns.LevelStatus() or nil
    PaintBonus()
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
    local key = tostring(ns.levelVersion) .. tostring(moving) .. tostring(d.levelMissing)   -- (a count: never a reused table)
    if lv.painted == key and lv:IsShown() then
        for _, b in ipairs(lv.icons) do   -- only the clocks run on
            if b.row and b:IsShown() then ns.PaintLevelTimer(b, b.row) end
        end
        return
    end
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
            if b.pulse1 then b.pulse1:Stop() end
            if b.pulse2 then b.pulse2:Stop() end
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
    if event == "PLAYER_REGEN_ENABLED" and ns.levelPending and ns.db then   -- a reload in a fight: made now
        ns.levelPending = nil
        lv = BuildLevel()
        ns.levelFrame = lv
    end
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
    if not lv or InCombatLockdown() then return end
    ShowGrips(lv, on)
    lv:EnableMouseWheel(on and true or false)
    if not on then
        SavePoint(lv, "levelPoint")
        if lvLabel then lvLabel:Hide() end
    end
    ns.RefreshLevel()
    if ns.XPBarMove then ns.XPBarMove(on) end
end

-- A profile switch: its spot and size (out of combat – it holds secure icons).
function ns.ApplyLevelLayout()
    if not lv or InCombatLockdown() then return end
    lv:SetScale(LevelScale())
    LoadPoint(lv, "levelPoint", { "TOPRIGHT", "TOPRIGHT", -240, -440 })
    lv.painted = nil
    ns.RefreshLevel()
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
    -- A small colour key, the same colours as on the bar.
    local function Key(r, g, b)
        return ("|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(r * 255, g * 255, b * 255)
    end
    local function ShowXPTip(owner, d, settingsLine)
        if not d then return end
        local pct = d.cur / d.max * 100
        local withDone = math.min(100, (d.cur + quests.done) / d.max * 100)
        local xc = d.rested > 0 and XP_RESTED or XP_NORMAL
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:AddDoubleLine("Level " .. d.level, ("%.1f%%"):format(pct), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(Key(xc[1], xc[2], xc[3]) .. "XP", Num(d.cur) .. " / " .. Num(d.max) .. "  |cffaaaaaa(" .. Num(d.max - d.cur) .. " to go)|r",
            1, 1, 1, 1, 1, 1)
        if d.rested > 0 then
            GameTooltip:AddDoubleLine(Key(0.0, 0.25, 0.6) .. "Rested |cffaaaaaa– double XP from kills|r", Num(d.rested)
                .. ("  |cffaaaaaa(%.0f%%)|r"):format(d.rested / d.max * 100), 0.5, 0.75, 1, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine(Key(0.25, 0.25, 0.25) .. "Rested", "none", 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        end
        GameTooltip:AddDoubleLine(Key(1, 0.82, 0) .. "Ready to hand in", (quests.done > 0 and ("+" .. Num(quests.done) .. ("  |cffaaaaaa= %.1f%%|r"):format(withDone)) or "none"),
            1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(Key(0.55, 0.47, 0.2) .. "Quests in progress", quests.todo > 0 and Num(quests.todo) or "none", 0.8, 0.7, 0.4, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Time this level", played.level and Dur(played.level + time() - played.at) or "–", 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine(session.reset and "Since you reset" or "This session", "+" .. Num(session.xp) .. " XP  |cffaaaaaain " .. Dur(time() - session.start) .. "|r", 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("XP an hour", d.rate and Num(d.rate) or "–", 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Next level in", d.rate and ("|cff40ff40" .. Dur((d.max - d.cur) / d.rate * 3600) .. "|r") or "|cffaaaaaa– after your first kill|r", 0.7, 0.7, 0.7, 1, 1, 1)
        if settingsLine then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100Shift-click:|r count XP an hour again from now (farming)", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|cffffd100Right-click:|r settings", 0.8, 0.8, 0.8)
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
        f:SetScript("OnDragStart", function(self)
            if moving and not self.compact then self.dragging = true; self:StartMoving() end
        end)
        f:SetScript("OnDragStop", function(self)
            if not self.dragging then return end   -- a stray drag while locked doesn't move or save it
            self.dragging = nil
            self:StopMovingOrSizing()
            if ns.Snap then ns.Snap(self) end
            SavePoint(self, "xpBarPoint")
            ns.RefreshXPBar()
        end)
        f:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and IsShiftKeyDown() and not moving then   -- farming: count from now
                ns.ResetXPSession()
                if self:IsMouseOver() then ShowXPTip(self, self.data, true) end
                return
            end
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
    -- the bottom of the small one in the stack (UIParent units), for the yellow bar under it
    function ns.XPBarBottom()
        if not (xb and xb.compact and xb:IsShown()) then return nil end
        local b = xb:GetBottom()
        return b and b * (xb:GetScale() or 1) or nil
    end
    local function Position()
        xb:ClearAllPoints()
        xb.attachedTo = nil
        if db().xpBarAttach ~= false and mini and ns.UnderMini then   -- between the mini bar and the Nearby list
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
        if not xb then xb = Build() end
        local compact = d.xpBarAttach ~= false
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
        -- XP an hour first, when ticked (on unless switched off) and there's been a kill or a quest to measure
        local perHour = (rate and d.xpRateOnBar ~= false) and ("|cffaaaaaa" .. Num(rate) .. "/h|r  ") or ""
        xb.pct:SetText(perHour .. ("%.1f%%"):format(cur / max * 100)
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

    -- Shift-click the bar (or /wx xp reset): XP an hour counts again from now – to see what a farming spot gives
    function ns.ResetXPSession()
        session.start, session.xp, session.reset = time(), 0, true
        ns.Print("XP an hour: counting again from now.")
        ns.RefreshXPBar()
    end

    -- the mini bar or the red bar changed: the compact one moves with them at once (not on its next tick)
    function ns.PlaceXPBar()
        if xb and xb.compact and xb:IsShown() then Position() end
    end

    function ns.XPBarMove(on)
        if not xb then return end
        if not on and xb.dragging then xb.dragging = nil; xb:StopMovingOrSizing() end
        ShowGrips(xb, on and not xb.compact)
        -- saved only when it has its own spot (dragged there): one still hanging under the icons keeps following them
        local rel = select(2, xb:GetPoint())
        if not on and not xb.compact and (rel == nil or rel == UIParent) then SavePoint(xb, "xpBarPoint") end
        ns.RefreshXPBar()
    end
    function ns.ResetXPBar()
        local d = db()
        d.xpBarPoint, d.xpBarWidth, d.xpBarScale = nil, nil, nil
        if xb then xb:SetScale(1); xb:SetWidth(XB_W); Position() end
        ns.RefreshXPBar()
    end

    -- XP this session (level-ups included), time this level, quests.
    -- Time this level: /played is asked once per character (it prints its two lines in chat, as if you typed it –
    -- the chat windows aren't touched), then counted here and kept per character in the saved settings.
    local function PlayedKey() return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "") end
    local function SavePlayed(level)   -- level: the new one at a level-up (UnitLevel still says the old one then)
        if not (ns.db and played.level and played.at) then return end
        if type(ns.db.playedLevel) ~= "table" then ns.db.playedLevel = {} end
        ns.db.playedLevel[PlayedKey()] = { lvl = level or N(UnitLevel("player")) or 0, secs = played.level + (time() - played.at) }
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
                         "QUEST_LOG_UPDATE", "TIME_PLAYED_MSG", "PLAYER_LOGOUT" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local asked
    -- the clocks on it, once a second (a timer, not a check every frame; quests at most every 30 s or when they changed)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, function() ns.Safe("xp bar", ns.RefreshXPBar) end)
    end
    ev:SetScript("OnEvent", function(_, event, a1, a2) ns.Safe("xp bar", function()
        if event == "QUEST_LOG_UPDATE" then
            -- comes in bursts: the quest log is read on the next tick (within a second), once
            quests.at = math.min(quests.at, GetTime() - 29.5)   -- read on the first refresh half a second on
            return
        elseif event == "PLAYER_LOGOUT" then
            SavePlayed()
            return
        elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then
            local cur, max = N(UnitXP("player")) or 0, N(UnitXPMax("player")) or 0
            if lastXP then
                local gain = (cur >= lastXP) and (cur - lastXP) or ((lastMax or 0) - lastXP + cur)
                if gain > 0 and gain < max * 2 then session.xp = session.xp + gain end
            end
            lastXP, lastMax = cur, max
            if event == "PLAYER_LEVEL_UP" then
                played.level, played.at = 0, time()
                SavePlayed(N(a1))
            end
            if event == "PLAYER_ENTERING_WORLD" and not asked then
                asked = true
                local saved = ns.db and type(ns.db.playedLevel) == "table" and ns.db.playedLevel[PlayedKey()]
                if type(saved) == "table" and saved.lvl == N(UnitLevel("player")) and N(saved.secs) then
                    played.level, played.at = N(saved.secs), time()   -- counted on from last time
                elseif RequestTimePlayed then
                    C_Timer.After(4, function() pcall(RequestTimePlayed) end)   -- once for this character
                end
            end
        elseif event == "TIME_PLAYED_MSG" then   -- (also when you type /played: it sets the clock right)
            local lvlTime = N(a2)
            if lvlTime then played.level, played.at = lvlTime, time(); SavePlayed() end
        end
        ns.RefreshXPBar()
    end) end)
end)()

-- ---------------------------------------------------------------- eating & drinking timer
-- While you eat or drink: the buff's icon and the seconds left in the middle of the screen, and how much more health
-- or mana you'll get – and whether you'll be full. The rate comes from the buff's text ("... mana per second"), or is
-- measured while you sit. Moves with the other bars (Unlock). Its own function: the main chunk is at the locals limit.
do (function()
    local f, ft, Draw
    local KINDS = { Food = "hp", Drink = "mp", ["Food & Drink"] = "both", Refreshment = "both" }
    local seen = {}   -- kind -> { start value, start time } while it's up

    local function N(v) if issecretvalue and v ~= nil and issecretvalue(v) then return nil end return tonumber(v) end
    local function Short(n)
        n = math.floor(n + 0.5)
        if n >= 10000 then return ("%.1fk"):format(n / 1000) end
        return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    end
    -- "Restores 151 mana per second." / "Restoring 4410 mana over 30 sec." / "... 45 health every 3 sec."
    local function RateFromText(i, what)
        if not (C_TooltipInfo and C_TooltipInfo.GetUnitAura) then return nil end
        local ok, data = pcall(C_TooltipInfo.GetUnitAura, "player", i, "HELPFUL")
        if not ok or type(data) ~= "table" then return nil end
        for _, line in ipairs(data.lines or {}) do
            local t = line.leftText
            if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then
                t = t:lower():gsub(",", "")
                -- returns: per second, one tick's amount, seconds between ticks
                local n = tonumber(t:match("(%d+) " .. what .. " per second"))
                if n then return n, n, 1 end
                local m, sec = t:match("(%d+) " .. what .. " every (%d+%.?%d*) sec")
                if m then
                    sec = math.max(1, tonumber(sec))
                    return tonumber(m) / sec, tonumber(m), sec
                end
                local tot, over = t:match("(%d+) " .. what .. " over (%d+%.?%d*) sec")
                if tot then
                    local ps = tonumber(tot) / math.max(1, tonumber(over))
                    return ps, ps, 1
                end
            end
        end
    end

    -- The sleeping bag: one Well-Rested stack a minute, up to 3. You lie down by clicking the bag on the ground (no
    -- cast to see), so the count starts at a "sleep" buff, a new stack, or using the bag item (ns.bagStart).
    local bag = {}
    -- The bag was put down within the last 10 minutes (its 1-hour cooldown just started): "Resting" is the bag then,
    -- not an inn.
    local function BagUsedLately()
        local f = C_Container and C_Container.GetItemCooldown
        if not f then return true end
        local ok, start, dur = pcall(f, 211527)
        start, dur = ok and N(start), ok and N(dur)
        return start and dur and start > 0 and dur > 60 and GetTime() - start < 600 or false
    end
    local function BagState(lying, wr, wrAge)
        local now = GetTime()
        lying = lying and BagUsedLately()
        -- a stack less than 70 s ago means you're on the bag: the next one is a minute after it
        if wr and wr > 0 and wr < 3 and wrAge and wrAge < 70 then
            if not ns.bagStart then ns.bagStart = now - wrAge end
            bag.start, bag.at, bag.stacks = ns.bagStart, now - wrAge, wr
        end
        local stacks = wr or 0   -- Well-Rested's stacks, found by name in Find (its spell ID differs between clients)
        if bag.stacks == nil then bag.stacks = stacks end                       -- first look: just the baseline
        if lying and not ns.bagStart then ns.bagStart = now end
        if ns.bagStart and bag.start ~= ns.bagStart then bag.start, bag.at = ns.bagStart, ns.bagStart end
        if stacks > bag.stacks and not (wrAge and wrAge >= 70) then              -- a new stack: you're lying on it
            if not ns.bagStart then ns.bagStart = now; bag.start = now end
            bag.at = now
        end
        bag.stacks = stacks
        -- full: the tile blinks "get up!" while you still lie on the bag (Resting, bag put down lately)
        -- full: blink "get up!" for 2 minutes after the 3rd stack (its time since then comes from Well-Rested's clock),
        -- longer while WatchX can tell you still lie there
        if stacks >= 3 then
            ns.bagStart = nil
            -- you moved: you're up (nobody walks lying on a bag) – the tile goes for this round, even in town, where
            -- Forever's "Resting" looks just like the bag's, and even if Well-Rested's clock still renews
            if not bag.up and GetUnitSpeed and (N(GetUnitSpeed("player")) or 0) > 0 then bag.up = true end
            if bag.up then return nil end
            local fresh = wrAge and wrAge < 120
            if fresh or lying then return { kind = "bag", stacks = 3, done = true } end
            return nil
        end
        bag.up = nil   -- under 3/3 again: a new round
        bag.doneAt = nil
        if not ns.bagStart then return nil end
        local nextAt = (bag.at or now) + 60
        if now > nextAt + 15 and not lying then ns.bagStart = nil return nil end -- no new stack: you got up
        return { kind = "bag", stacks = stacks, left = math.max(0, nextAt - now), full = math.max(0, nextAt - now) + (2 - stacks) * 60 }
    end

    -- One look at your buffs: when they change (UNIT_AURA, gathered), not on every tick. The ticks work out the
    -- times from it (the end times don't change between two looks).
    local scan
    local function Scan()
        local s = { list = {} }
        scan = s
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return s end
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            local name = a.name
            if issecretvalue and issecretvalue(name) then name = nil end
            local kind = name and KINDS[name]
            local lower = name and name:lower() or ""
            -- the fire's own buff (with a clock, by the fire); "Campfire Nearby" reaches far and lingers: only a hint
            if not kind and lower:find("campfire", 1, true) then
                if lower:find("nearby", 1, true) then s.nearFire = true else kind = "fire" end
            end
            -- lying on the bag: Forever gives "Resting" (no end); a "sleep" buff counts too
            if not kind and (lower == "resting" or N(a.spellId) == 1331671
                    or (lower:find("sleep", 1, true) and not lower:find("well", 1, true))) then s.lying = true end
            if lower == "well-rested" or lower == "well rested" or N(a.spellId) == 429959 then
                s.wr = math.max(s.wr or 0, N(a.applications) or 1)
                -- each new stack gives it its full time again: its end time says how long since the last stack
                local ex, dur = N(a.expirationTime), N(a.duration)
                if ex and ex > 0 and dur and dur > 0 then s.wrEx, s.wrDur = ex, dur end
            end
            if kind then
                s.list[#s.list + 1] = { kind = kind, index = i, icon = a.icon, ex = N(a.expirationTime), dur = N(a.duration),
                    sid = N(a.spellId) }
            end
        end
        return s
    end

    -- What you're eating or drinking: the item in your bags whose Use: is this buff's spell – its name, icon, and
    -- whether it makes you Well Fed (its text says "well fed", or XP from kills). Looked up once per buff; not found
    -- (you ate the last one) is tried again in 20 s. The buff's own text is asked too, for "well fed".
    local foodInfo = {}
    local function FoodInfo(a)
        local sid = a and a.src and a.src.sid
        if not sid then return nil end
        local c = foodInfo[sid]
        if c and (c.id or GetTime() < c.retry) then return c end
        c = { retry = GetTime() + 20 }
        foodInfo[sid] = c
        local C, I = C_Container, C_Item
        if C and C.GetContainerNumSlots and C.GetContainerItemID and I and I.GetItemSpell then
            for bag = 0, 4 do
                local okN, n = pcall(C.GetContainerNumSlots, bag)
                for slot = 1, (okN and N(n) or 0) do
                    local okI, id = pcall(C.GetContainerItemID, bag, slot)
                    id = okI and N(id)
                    if id and not c.id then
                        local okS, _, spell = pcall(I.GetItemSpell, id)
                        if okS and N(spell) == sid then c.id = id end
                    end
                end
                if c.id then break end
            end
        end
        local text = c.id and ns.ItemTooltipText and ns.ItemTooltipText(c.id)
        if c.id then
            c.name = ns.ItemName and ns.ItemName(c.id, nil)
            c.icon = ns.ItemIcon and ns.ItemIcon(c.id)
        end
        if not text and C_TooltipInfo and C_TooltipInfo.GetUnitAura and a.index then   -- the buff's own words
            local ok, data = pcall(C_TooltipInfo.GetUnitAura, "player", a.index, "HELPFUL")
            if ok and type(data) == "table" and not (issecretvalue and issecretvalue(data)) then
                local parts = {}
                for _, l in ipairs(type(data.lines) == "table" and data.lines or {}) do
                    local t = type(l) == "table" and l.leftText
                    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then parts[#parts + 1] = t end
                end
                text = table.concat(parts, " ")
            end
        end
        text = type(text) == "string" and text:lower() or ""
        c.buff = text:find("well fed", 1, true) ~= nil or text:find("experience gained from kills", 1, true) ~= nil
            or text:find("experience from kills", 1, true) ~= nil
        return c
    end

    local function Find()
        local s = scan or Scan()
        local now = GetTime()
        local out = {}
        for _, a in ipairs(s.list) do
            local left = (a.ex and a.ex > 0) and math.max(0, a.ex - now) or nil   -- nil = no end
            out[#out + 1] = { kind = a.kind, index = a.index, icon = a.icon, left = left, dur = a.dur, src = a }
        end
        -- one Campfire tile, however many campfire buffs: the one with a clock (it renews each minute by the fire)
        local fire, keep = nil, {}
        for _, a in ipairs(out) do
            if a.kind == "fire" then
                if not fire or (a.left and not fire.left) then fire = a end
            else
                keep[#keep + 1] = a
            end
        end
        if fire then keep[#keep + 1] = fire end
        out = keep
        local wrAge = (s.wrEx and s.wrDur) and math.max(0, s.wrDur - (s.wrEx - now)) or nil
        local b = BagState(s.lying, s.wr, wrAge)
        if b then out[#out + 1] = b end
        -- a fire you lit here, when there's no Campfire buff to show
        local hasFire = false
        for _, a in ipairs(out) do if a.kind == "fire" then hasFire = true end end
        if not hasFire and s.nearFire and ns.CampFireLit then
            local ago = ns.CampFireLit()
            if ago then out[#out + 1] = { kind = "fire", lit = ago } end
        end
        return out
    end

    -- One icon per buff, like the classic drinking aura: the % above it, the seconds left big on it, and under it
    -- whether you'll be full (or where you'll end).
    local ICON = 46
    local function Big(fs, size)
        local font = fs:GetFont()
        if font then fs:SetFont(font, size, "OUTLINE") end
        fs:SetShadowOffset(0, 0)
    end
    local WATER, FOOD = "Interface\\Icons\\INV_Drink_18", "Interface\\Icons\\INV_Misc_Fork&Knife"   -- high-level water and food
    local function Tile(parent)
        local t = CreateFrame("Frame", nil, parent)
        t:SetSize(ICON, ICON)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetAllPoints()
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- how full you are, as a colour rising in the icon (blue mana, green health)
        t.fill = t:CreateTexture(nil, "ARTWORK", nil, 2)
        t.fill:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
        t.fill:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
        t.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        t.fill:SetHeight(1)
        t.fillTop = t:CreateTexture(nil, "ARTWORK", nil, 3)   -- a bright line on the surface
        t.fillTop:SetPoint("BOTTOMLEFT", t.fill, "TOPLEFT", 0, -1)
        t.fillTop:SetPoint("BOTTOMRIGHT", t.fill, "TOPRIGHT", 0, -1)
        t.fillTop:SetHeight(1)
        t.fillTop:SetTexture("Interface\\Buttons\\WHITE8X8")
        -- WoW Forever's gold edge, a little outside the icon
        t.frame = CreateFrame("Frame", nil, t)
        t.frame:SetPoint("TOPLEFT", -4, 4); t.frame:SetPoint("BOTTOMRIGHT", 4, -4)
        t.frame:SetFrameLevel(t:GetFrameLevel() + 1)
        if Backdrop(t.frame, { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                bgFile = nil }) then
            t.frame:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 1)
        end
        t.time = t.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        t.time:SetPoint("CENTER", t, "CENTER", 0, 0)
        Big(t.time, 17)
        t.pct = t.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t.pct:SetPoint("BOTTOM", t, "TOP", 0, 6)
        Big(t.pct, 14)
        t.food = t.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")   -- what it is, and Well Fed in 7s
        t.food:SetPoint("TOP", t, "BOTTOM", 0, -6)
        t.food:SetWidth(ICON + 44)
        t.food:SetWordWrap(false)   -- a long name ends in "…" (explicit lines still break)
        Big(t.food, 10)
        t.info = t.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t.info:SetPoint("TOP", t.food, "BOTTOM", 0, -2)
        Big(t.info, 10)
        -- a tick: "+151" rises from above the icon and fades, each time the food or drink gives (the game's own
        -- animation – no Lua per frame)
        t.tick = t.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t.tick:SetPoint("BOTTOM", t, "TOP", 0, 6)
        Big(t.tick, 13)
        t.tick:SetAlpha(0)
        if t.tick.CreateAnimationGroup then
            local ag = t.tick:CreateAnimationGroup()
            local up = ag:CreateAnimation("Translation")
            if up.SetOffset then up:SetOffset(0, 14) end
            up:SetDuration(0.85)
            if up.SetSmoothing then up:SetSmoothing("OUT") end
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1); fade:SetToAlpha(0)
            fade:SetStartDelay(0.45); fade:SetDuration(0.4)
            if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
            t.tickAnim = ag
        end
        -- the fill when your health/mana can only be read by the game itself (hidden values): a status bar takes them
        t.bar = CreateFrame("StatusBar", nil, t)
        t.bar:SetAllPoints(t)
        t.bar:SetFrameLevel(t:GetFrameLevel())
        if t.bar.SetOrientation then t.bar:SetOrientation("VERTICAL") end
        t.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        t.bar:Hide()
        return t
    end

    local function Build()
        f = CreateFrame("Frame", "WatchXEating", UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetSize(ICON * 4 + 110, ICON + 40)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(false)
        f:RegisterForDrag("LeftButton")
        LoadPoint(f, "eatPoint", { "CENTER", "CENTER", 0, -170 })
        f.rows = { Tile(f), Tile(f), Tile(f), Tile(f) }
        f:SetScript("OnDragStart", function(self) if moving then self.dragging = true; self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self)
            if not self.dragging then return end
            self.dragging = nil
            self:StopMovingOrSizing()
            if ns.Snap then ns.Snap(self) end
            SavePoint(self, "eatPoint")
        end)
        local t = 0
        local work = ns.Timed(function() ns.Safe("eating timer", Draw) end, "eating timer")
        f:SetScript("OnUpdate", function(self, elapsed)
            t = t + elapsed
            if t < (self.every or 0.1) then return end   -- tenths (eating, blinking) or a quarter second (camp)
            t = 0
            work()
        end)
        f:Hide()
    end

    -- Damage over time on you (debuffs with a clock): how many. Counted once per look at the auras.
    local function Dots()
        if scan and scan.dots then return scan.dots end
        local n = 0
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
                if not ok or type(a) ~= "table" then break end
                local ex = N(a.expirationTime)
                if ex and ex > 0 then n = n + 1 end
            end
        end
        if scan then scan.dots = n end
        return n
    end
    -- The real change per second over the last few seconds (food minus whatever is hurting you).
    local function NetRate(s, cur)
        local now = GetTime()
        s.samples = s.samples or {}
        local list = s.samples
        list[#list + 1] = { now, cur }
        while #list > 2 and now - list[1][1] > 4 do table.remove(list, 1) end
        local first = list[1]
        if now - first[1] < 1.5 then return nil end
        return (cur - first[2]) / (now - first[1])
    end

    -- Where you'll end, when your numbers are hidden from addons: the game itself runs your % through a curve
    -- "now + gain, at most 100" (addons may not add to a hidden number). One curve per gain, made once.
    local endCurves = {}
    local function EndCurve(gain)
        gain = math.floor(gain + 0.5)
        if endCurves[gain] == nil then
            local ok, c = pcall(function()
                local c = C_CurveUtil.CreateCurve()
                if c.SetType and Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
                c:AddPoint(0, gain)
                if gain < 100 then c:AddPoint(1 - gain / 100, 100) end
                c:AddPoint(1, 100)
                return c
            end)
            endCurves[gain] = ok and c or false
        end
        return endCurves[gain] or nil
    end

    -- One tile: the power it restores (health or mana), what's left of the buff, and how far it'll get you.
    local function Paint(r, a, what, label, color)
        local cur, max   -- (not "a and b or c": mana that can't be read must not turn into health)
        if what == "mp" then cur, max = N(UnitPower("player", 0)), N(UnitPowerMax("player", 0))
        else cur, max = N(UnitHealth("player")), N(UnitHealthMax("player")) end
        -- the food or drink itself: its icon, its name under the tile, and for buff food the 10 seconds until Well Fed
        local fi = a.src and FoodInfo(a)
        r.icon:SetTexture((fi and fi.icon) or (what == "mp" and WATER or FOOD))
        local foodLine = ""
        if fi and not (a.kind == "both" and what == "mp") then   -- (food & drink: said once, on the food)
            foodLine = fi.name and ("|cffdddddd" .. fi.name .. "|r") or ""
            if fi.buff and a.dur and a.left then
                local wait = 10 - (a.dur - a.left)
                local wf = wait > 0 and ("|cffffd100Well Fed in " .. math.ceil(wait) .. "s|r") or "|cff40ff40Well Fed!|r"
                foodLine = foodLine ~= "" and (foodLine .. "\n" .. wf) or wf
            end
        end
        if r.foodLine ~= foodLine then r.foodLine = foodLine; r.food:SetText(foodLine) end
        r.time:SetText(a.left and ("%.1f"):format(a.left) or "")
        -- what the buff gives, from its own text (read once, then kept with it): per second, a tick, its interval
        local tk
        if a.src and a.index then
            local k = "tick" .. label
            if a.src[k] == nil then
                local ps, amount, period = RateFromText(a.index, label)
                a.src[k] = ps and { ps = ps, amount = amount, period = period } or false
            end
            tk = a.src[k] or nil
        end
        -- the tick over the icon: one "+N" per interval while it lasts
        local id = (a.src and (tostring(a.kind) .. label .. tostring(a.src.ex))) or a
        if r.tickFor ~= id then r.tickFor, r.nextTick = id, nil end
        local tickY = (cur and max and max > 0) and 24 or 6
        if r.tick and r.tickY ~= tickY then
            r.tickY = tickY
            r.tick:ClearAllPoints()
            r.tick:SetPoint("BOTTOM", r, "TOP", 0, tickY)
        end
        if tk and a.left and a.left > 0 and r.tick then
            local now = GetTime()
            if not r.nextTick or now >= r.nextTick then
                r.nextTick = (r.nextTick and now - r.nextTick < tk.period) and (r.nextTick + tk.period) or (now + tk.period)
                r.tick:SetText(color .. "+" .. Short(tk.amount) .. "|r")
                r.tick:SetAlpha(1)
                if r.tickAnim then r.tickAnim:Stop(); r.tickAnim:Play() end
            end
        end
        if r.bar then r.bar:Hide() end
        if not (cur and max and max > 0) then
            -- your health / mana can't be read here: what's still to come, from the buff's own words – and the fill
            -- and % as far as the game shows hidden values itself
            r.pct:SetText(""); r.fill:Hide(); r.fillTop:Hide()
            local rawCur, rawMax
            if what == "mp" then rawCur, rawMax = UnitPower("player", 0), UnitPowerMax("player", 0)
            else rawCur, rawMax = UnitHealth("player"), UnitHealthMax("player") end
            if r.bar and rawCur ~= nil and rawMax ~= nil
                    and pcall(r.bar.SetMinMaxValues, r.bar, 0, rawMax) and pcall(r.bar.SetValue, r.bar, rawCur) then
                if what == "mp" then r.bar:SetStatusBarColor(0.15, 0.45, 1, 0.45) else r.bar:SetStatusBarColor(0.15, 0.8, 0.2, 0.45) end
                r.bar:Show()
            end
            local pf = (what == "mp") and UnitPowerPercent or UnitHealthPercent
            local scale = CurveConstants and CurveConstants.ScaleTo100
            local function P(curve)   -- your % through a curve (a hidden number the game can show)
                if what == "mp" then return pf("player", 0, false, curve) end
                return pf("player", false, curve)
            end
            -- what the rest of the buff gives, as % of your maximum (the maximum may be readable when the value isn't)
            local maxR = N(rawMax)
            local gain = (tk and a.left and maxR and maxR > 0) and math.min(100, tk.ps * a.left / maxR * 100) or nil
            local pctShown = false
            if pf and scale then
                -- "26% » 95%": now, and where you'll be when it's done; else "26% +69%"; else just "26%"
                local curve = gain and EndCurve(gain)
                pctShown = (curve and pcall(function()
                        r.pct:SetFormattedText(color .. "%d%%|r |cffcccccc»|r " .. color .. "%d%%|r", P(scale), P(curve))
                    end))
                    or (gain and pcall(function()
                        r.pct:SetFormattedText(color .. "%d%%|r |cffcccccc+" .. math.floor(gain + 0.5) .. "%%|r", P(scale))
                    end))
                    or pcall(function() r.pct:SetFormattedText(color .. "%d%%|r", P(scale)) end)
            end
            -- the tick over the %, when the game could show it
            local y = pctShown and 24 or 6
            if r.tick and r.tickY ~= y then r.tickY = y; r.tick:ClearAllPoints(); r.tick:SetPoint("BOTTOM", r, "TOP", 0, y) end
            r.info:SetText("")   -- (the % and the tick say it; a line under each icon only crowded them)
            return
        end
        r.pct:SetText(color .. math.floor(cur / max * 100 + 0.5) .. "%|r")   -- (with where you'll end, below)
        local fr, fg, fb = (what == "mp") and 0.15 or 0.15, (what == "mp") and 0.45 or 0.8, (what == "mp") and 1 or 0.2
        r.fill:SetVertexColor(fr, fg, fb, 0.45)
        r.fillTop:SetVertexColor(fr + 0.4, fg + 0.3, fb, 0.9)
        r.fill:SetHeight(math.max(1, ICON * math.min(1, cur / max)))
        r.fill:Show(); r.fillTop:Show()
        local s = seen[what]
        if not s then s = { v = cur, t = GetTime() }; seen[what] = s end
        if cur < s.v then s.v, s.t = cur, GetTime() end   -- took damage / cast: measure from here
        -- per second ("X over Y sec" is divided already); read from the buff's text once, then kept with it
        local rate = tk and tk.ps
        if not rate and not a.src and a.index then rate = RateFromText(a.index, label) end
        if not rate and GetTime() - s.t >= 2 then rate = (cur - s.v) / (GetTime() - s.t) end
        local missing = max - cur
        -- eating with damage over time on you: will the food keep you alive?
        local dots = what == "hp" and Dots() or 0
        local net = what == "hp" and NetRate(s, cur) or nil
        r.danger = nil
        if dots > 0 and a.left then
            local tag = "|cffaaaaaa" .. dots .. (dots == 1 and " debuff" or " debuffs") .. "|r  "
            if not net then
                r.info:SetText(tag .. "|cffccccccchecking...|r")
            elseif net < 0 then
                local deadIn = cur / -net
                if deadIn < a.left then
                    r.danger = true
                    r.info:SetText(tag .. "|cffff3030dies in " .. math.ceil(deadIn) .. "s!|r")
                else
                    r.info:SetText(tag .. ("|cffff8040%d/s · ends at %d%%|r"):format(math.floor(net), math.max(0, math.floor((cur + net * a.left) / max * 100))))
                end
            else
                local fullIn = net > 0 and missing / net or math.huge
                r.info:SetText(tag .. "|cff40ff40survives|r " .. (fullIn <= a.left and ("|cff40ff40· full in " .. math.ceil(fullIn) .. "s|r")
                    or ("|cffcccccc· ends at " .. math.min(100, math.floor((cur + net * a.left) / max * 100)) .. "%|r")))
            end
            return
        end
        -- now » where you'll be when it's done (or full)
        if rate and rate > 0 and a.left and missing > 0 then
            local endPct = math.min(100, math.floor((cur + rate * a.left) / max * 100))
            r.pct:SetText(color .. math.floor(cur / max * 100 + 0.5) .. "%|r |cffcccccc»|r " .. color .. endPct .. "%|r")
        end
        if missing <= 0 then
            r.info:SetText("|cff40ff40full|r")
        elseif rate and rate > 0 and a.left and missing / rate <= a.left then
            r.info:SetText("|cff40ff40full in " .. math.ceil(missing / rate) .. "s|r")
        else
            r.info:SetText("")
        end
    end

    local BAGICON, FIREICON = "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Icons\\Spell_Fire_Fire"
    local function PaintCamp(r, a)
        if r.foodLine ~= "" then r.foodLine = ""; r.food:SetText("") end   -- (the tile may have shown a food before)
        r.fill:Hide(); r.fillTop:Hide()
        r:SetAlpha(1)
        if a.kind == "bag" and a.done then
            r.icon:SetTexture((ns.ItemIcon and ns.ItemIcon(211527)) or BAGICON)
            r.pct:SetText("|cff40ff403/3|r")
            r.time:SetText("|cff40ff40OK|r")
            r.info:SetText("|cff40ff40get up!|r")
            r:SetAlpha(0.35 + 0.65 * math.abs(math.sin(GetTime() * 4)))   -- blinks until you get up
        elseif a.kind == "bag" then
            r.icon:SetTexture((ns.ItemIcon and ns.ItemIcon(211527)) or BAGICON)
            r.pct:SetText("|cffffd100" .. a.stacks .. "/3|r")
            r.time:SetText(tostring(math.ceil(a.left)))
            r.info:SetText(("|cffccccccfull in %d:%02d|r"):format(math.floor(a.full / 60), math.floor(a.full % 60)))
        else
            r.icon:SetTexture(a.icon or FIREICON)
            r.pct:SetText("|cffff9030Campfire|r")
            if a.lit then   -- one you lit: how long ago
                r.time:SetText(a.lit >= 60 and (math.floor(a.lit / 60) .. "m") or tostring(math.floor(a.lit)))
                r.info:SetText("|cffcccccclit " .. (a.lit >= 60 and (math.floor(a.lit / 60) .. " min") or (math.floor(a.lit) .. " s")) .. " ago|r")
            elseif a.left then
                local l = a.left
                r.time:SetText(l >= 60 and (math.floor(l / 60) .. "m") or tostring(math.ceil(l)))
                r.info:SetText("|cffccccccby the fire|r")
            else
                r.time:SetText("")
                r.info:SetText("|cffccccccby the fire|r")
            end
        end
    end

    function Draw()
        if not ns.db then return end
        if db().eatTimer == false and not moving then
            if f then f:Hide() end
            if ft then ft:Hide() end   -- (the "drag to move" label goes with it when you lock)
            return
        end
        local list = Find()
        if #list == 0 and not moving then
            wipe(seen)
            if f then f:Hide() end
            if ft then ft:Hide() end
            return
        end
        if not f then Build() end
        local lines = {}
        for _, a in ipairs(list) do   -- drink first (the one you sit for), then food
            if a.kind == "mp" or a.kind == "both" then lines[#lines + 1] = { a, "mp", "mana", "|cff4da6ff" } end
        end
        for _, a in ipairs(list) do
            if a.kind == "hp" or a.kind == "both" then lines[#lines + 1] = { a, "hp", "health", "|cff40ff40" } end
        end
        for _, a in ipairs(list) do   -- the camp: the sleeping bag's next stack, the fire's time
            if a.kind == "bag" or a.kind == "fire" then lines[#lines + 1] = { a, "camp" } end
        end
        if #lines == 0 and moving then   -- unlocked: an example to place it by
            lines[1] = { { left = 20.2 }, "mp", "mana", "|cff4da6ff" }
        end
        local n = math.min(#f.rows, #lines)
        for i, r in ipairs(f.rows) do
            local l = lines[i]
            if l then
                if l[2] == "camp" then PaintCamp(r, l[1]) else
                    r:SetAlpha(1)
                    Paint(r, l[1], l[2], l[3], l[4])
                    if r.danger then r:SetAlpha(0.35 + 0.65 * math.abs(math.sin(GetTime() * 6))) end
                end
                local x = (i - (n + 1) / 2) * (ICON + 48)   -- (just room for "100% » 100%" over each, side by side)
                if r.x ~= x then r.x = x; r:ClearAllPoints(); r:SetPoint("CENTER", f, "CENTER", x, 0) end
                r:Show()
            else
                r:Hide()
            end
        end
        -- the tick: tenths while eating or drinking (and for blinking), else a quarter second is plenty
        local quick = false
        for i = 1, n do
            local l = lines[i]
            if l[2] ~= "camp" or l[1].done or f.rows[i].danger then quick = true end
        end
        f.every = quick and 0.1 or 0.25
        f:EnableMouse(moving and true or false)
        f:Show()
        if moving then
            ft = ft or MakeLabel("WatchXEatingLabel")
            ft:Set(f, "|cffffd100Eating, drinking & camp|r · drag to move")
        elseif ft then
            ft:Hide()
        end
    end
    function ns.RefreshEating() scan = nil; Draw() end   -- a fresh look at the buffs, drawn now
    function ns.EatingMove() ns.RefreshEating() end

    -- Your buffs changed: looked at again on the next tick – or, while nothing shows, once a moment later (a burst
    -- of aura changes in a fight is one look, not dozens).
    local ev, waiting = CreateFrame("Frame"), false
    if not pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") then ev:RegisterEvent("UNIT_AURA") end
    ev:SetScript("OnEvent", function(_, _, unit)
        if unit ~= "player" then return end
        scan = nil
        if (f and f:IsShown()) or waiting or not C_Timer then return end
        waiting = true
        C_Timer.After(0.2, function() waiting = false; ns.Safe("eating timer", Draw) end)
    end)
end)() end

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
    check("Warnings in cities and inns too", "off: quiet while you're resting in town",
        function() return db().warnInCity == true end, function(v) db().warnInCity = v end)
    check("XP bar", "under the icons: XP, rested, quests, time this level, when you'll level",
        function() return db().xpBar ~= false end, function(v) db().xpBar = v; ns.RefreshXPBar() end)
    check("XP bar between the mini bar and the Enemies list", "just level and %, same width – the rest when you hover it",
        function() return db().xpBarAttach ~= false end,
        function(v) db().xpBarAttach = v; ns.RefreshXPBar(); if ns.AttachNearby then ns.AttachNearby() end end)
    check("XP an hour on the XP bar", "Shift-click the bar: count again from now (to see what a farming spot gives)",
        function() return db().xpRateOnBar ~= false end, function(v) db().xpRateOnBar = v; ns.RefreshXPBar() end)
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
        "|cffaaaaaa•|r  |cffffd100Cozy Sleeping Bag|r – lie on it: +1% XP a minute, up to +3%. A quest chain from level 14."
            .. " At 3/3, once it's ready again, lying on it sets the timer back to 2 hours (it turns yellow).",
        "|cffaaaaaa•|r  |cffffd100Camp Benefits|r – sit a minute by a campfire: a little fire on the \"+%\" box; hover it for what the camp gave you (Fish Bowl, Camp Chair …) and the time left.",
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
    check("Also in cities and inns", "off: quiet while you're resting in town (same as on the XP boosts page)",
        function() return db().warnInCity == true end, function(v) db().warnInCity = v end)
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

-- ---------------------------------------------------------------- rebuff icons (WatchX > Rebuff icons)
-- Your own buffs to keep up (per class: Ice Armor on a mage, Battle Shout on a warrior …): an icon for each one you're
-- missing, pulsing; click it to cast it on yourself. A line may hold alternatives – "Arcane Intellect / Arcane
-- Brilliance": any of them counts, the first is cast. Spells you don't know are left out. In a row or a column.
-- The icons are secure buttons (they cast): they're laid out out of combat only – your buffs can't be read in a
-- fight on Forever anyway, so in a fight they stay as they were. Read again only when your buffs change.
do (function()
    local ICON, GAP, PAD = 32, 5, 4
    local f, label
    local function ClassKey() local _, c = UnitClass("player"); return type(c) == "string" and c or "ANY" end
    function ns.RebuffList()
        local d = db()
        if type(d.rebuff) ~= "table" then d.rebuff = {} end
        local k = ClassKey()
        if type(d.rebuff[k]) ~= "table" then d.rebuff[k] = {} end
        local list = d.rebuff[k]
        if ns.FixRebuffLines and not list.fixed then list.fixed = true; ns.FixRebuffLines(list) end
        return list
    end
    local function Names(line)   -- "A / B" -> { "A", "B" }
        local t = {}
        for part in tostring(line):gmatch("[^/]+") do
            part = part:match("^%s*(.-)%s*$")
            if part ~= "" then t[#t + 1] = part end
        end
        return t
    end
    local function SpellIcon(name)
        local get = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
        if not get then return nil end
        local ok, t = pcall(get, name)
        if ok and (type(t) == "number" or type(t) == "string") and not (issecretvalue and issecretvalue(t)) then return t end
    end
    local function Known(name)   -- in your spellbook (a name only finds spells you have)
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, i = pcall(C_Spell.GetSpellInfo, name)
            if ok and type(i) == "table" then return true end
        end
        if GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, name)
            if ok and n then return true end
        end
        return false
    end

    -- Weapon lines: "Main hand: Instant Poison / Deadly Poison" (or "Off hand: …"). Poisons, oils and stones are
    -- weapon enchants, not buffs: missing when the weapon has none. Click: the first that you have – a spell you know
    -- (a shaman's Windfury Weapon) is cast, an item in your bags (any rank: "Instant Poison" finds "Instant Poison
    -- VI", the highest) is put on that weapon. The off hand only counts with a weapon there (not a shield).
    local function WeaponLine(line)
        local l = tostring(line):lower()
        local rest = tostring(line):match("^%s*[Mm]ain[%s%-]*[Hh]and%s*:%s*(.+)$")
        if rest then return 16, rest end
        rest = tostring(line):match("^%s*[Oo]ff[%s%-]*[Hh]and%s*:%s*(.+)$")
        if rest then return 17, rest end
    end
    local function Plain0(v) if issecretvalue and v ~= nil and issecretvalue(v) then return nil end return v end
    local function HasWeapon(slot)
        local id = Plain0(GetInventoryItemID and GetInventoryItemID("player", slot))
        if not id then return false end
        if slot == 16 then return true end
        local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        local ok, _, _, _, _, _, classID = pcall(get or function() end, id)
        return ok and classID == 2   -- (2 = a weapon; a shield or an off-hand item has no enchant to put on)
    end
    local function WeaponEnchanted(slot)   -- true / false / nil (can't tell)
        if not GetWeaponEnchantInfo then return nil end
        local ok, mh, _, _, _, oh = pcall(GetWeaponEnchantInfo)
        if not ok then return nil end
        local v = Plain0(slot == 16 and mh or oh)
        if v == nil then return nil end
        return v and true or false
    end
    -- the item in your bags whose name starts with this (the highest rank: the last in a bag scan by item ID)
    local function BagItem(base)
        local C = C_Container
        if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return nil end
        base = base:lower()
        local best, bestName
        for bag = 0, 4 do
            local okN, n = pcall(C.GetContainerNumSlots, bag)
            for slot = 1, (okN and Plain0(n) or 0) do
                local okI, id = pcall(C.GetContainerItemID, bag, slot)
                id = okI and Plain0(id)
                if id then
                    local name = ns.ItemName and ns.ItemName(id, nil)
                    if type(name) == "string" and name:lower():sub(1, #base) == base and (not best or id > best) then
                        best, bestName = id, name
                    end
                end
            end
        end
        return best, bestName
    end

    -- A poison, oil or stone typed as a buff ("Instant Poison IV"): it goes on a weapon – made a weapon line, any
    -- rank ("Main hand: Instant Poison"); the main hand first, then the off hand.
    local WEAPON_ITEM = { "poison", "wizard oil", "mana oil", "sharpening stone", "weightstone", "weapon oil" }
    local function WeaponItemName(text)
        local l = tostring(text):lower()
        for _, w in ipairs(WEAPON_ITEM) do if l:find(w, 1, true) then return true end end
        return false
    end
    local function NoRank(text) return (tostring(text):gsub("%s+[IVX]+%s*$", "")) end
    -- every rogue poison: a weapon line holds them all, and you pick the one it uses (settings, or hover the icon)
    local POISONS = { "Instant Poison", "Deadly Poison", "Wound Poison", "Crippling Poison", "Mind-numbing Poison" }
    -- returns the line and the one you typed (to pick it)
    function ns.WeaponLineFor(list, text)
        if WeaponLine(text) or not WeaponItemName(text) or Known(text) then return nil end
        local mh, oh = false, false
        for _, l in ipairs(list) do
            local slot = WeaponLine(l)
            if slot == 16 then mh = true elseif slot == 17 then oh = true end
        end
        local base = NoRank(text)
        local names = { base }
        if base:lower():find("poison", 1, true) then
            for _, p in ipairs(POISONS) do if p:lower() ~= base:lower() then names[#names + 1] = p end end
        end
        return ((mh and not oh) and "Off hand: " or "Main hand: ") .. table.concat(names, " / "), base
    end
    function ns.RebuffPick(line, base)
        local d = db()
        if type(d.rebuffPick) ~= "table" then d.rebuffPick = {} end
        d.rebuffPick[line] = base
    end
    -- the one a weapon line uses: what you picked, else the first
    function ns.RebuffPicked(line)
        local _, what = WeaponLine(line)
        local names = Names(what or line)
        local p = type(db().rebuffPick) == "table" and db().rebuffPick[line]
        for _, n in ipairs(names) do if n == p then return n, names end end
        return names[1], names
    end
    function ns.FixRebuffLines(list)
        local i = 1
        while list[i] do
            local w, base = ns.WeaponLineFor(list, list[i])
            if w then ns.RebuffPick(w, base) end
            local dup = false
            if w then for _, l in ipairs(list) do if l:lower() == w:lower() then dup = true end end end
            if w and dup then table.remove(list, i)
            else
                if w then list[i] = w end
                i = i + 1
            end
        end
    end

    local function Build()
        f = CreateFrame("Frame", "WatchXRebuff", UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:SetSize(ICON + PAD * 2, ICON + PAD * 2)
        f:SetScale(ClampScale(db().rebuffScale))
        LoadPoint(f, "rebuffPoint", { "CENTER", "CENTER", 0, -170 })
        f.bg = f:CreateTexture(nil, "BACKGROUND")   -- only while unlocked: something to grab
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0, 0, 0, 0.45)
        f.bg:Hide()
        f.icons = {}
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            if moving and not InCombatLockdown() then self.dragging = true; self:StartMoving() end
        end)
        f:SetScript("OnDragStop", function(self)
            if not self.dragging then return end
            self.dragging = nil
            self:StopMovingOrSizing()
            if ns.Snap then ns.Snap(self) end
            SavePoint(self, "rebuffPoint")
        end)
        f:SetScript("OnMouseWheel", function(self, delta)
            if not moving or InCombatLockdown() then return end
            Rescale(self, "rebuffScale", delta)
            SavePoint(self, "rebuffPoint")
        end)
        f:Hide()
    end
    local function Icon(i)
        local b = CreateFrame("Button", "WatchXRebuffIcon" .. i, f, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
        b:SetAttribute("type1", "spell")   -- (a weapon line: "macro", set when it's laid out)
        b:SetAttribute("unit", "player")
        b:SetSize(ICON, ICON)
        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetPoint("TOPLEFT", -2, 2); b.border:SetPoint("BOTTOMRIGHT", 2, -2)
        b.border:SetColorTexture(1, 0.2, 0.2, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.flash = b:CreateTexture(nil, "OVERLAY")
        b.flash:SetAllPoints()
        b.flash:SetColorTexture(1, 0.15, 0.15, 1)
        b.flash:SetAlpha(0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        -- the missing ones pulse: the game's own animation (no Lua each frame)
        if b.flash.CreateAnimationGroup then
            local ag = b.flash:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local an = ag:CreateAnimation("Alpha")
            an:SetFromAlpha(0.05); an:SetToAlpha(0.5); an:SetDuration(0.6)
            if an.SetSmoothing then an:SetSmoothing("IN_OUT") end
            b.pulse = ag
        end
        b:SetScript("OnEnter", function(self)
            if moving or not self.line then return end
            if self.opts and #self.opts > 1 and ns.RebuffFlyout then ns.RebuffFlyout(self) end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.line)
            GameTooltip:AddLine(self.have and "|cff40ff40You have it.|r"
                or self.noItem and "|cffff6060Missing|r – and none of it in your bags."
                or "|cffff6060Missing|r – click to put it on.", 1, 1, 1, true)
            GameTooltip:AddLine("|cffffd100Right-click:|r settings", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("PostClick", function(_, button)
            if button == "RightButton" and not InCombatLockdown() and ns.OpenRebuffSettings then ns.OpenRebuffSettings() end
        end)
        b:Hide()
        f.icons[i] = b
        return b
    end

    -- which lines are up: your buffs' names, read again only when they changed (UNIT_AURA) or after 10 s
    local have, haveGen, haveAt = {}, nil, 0
    local function ReadHave()
        if haveGen == ns.auraGen and GetTime() - haveAt < 10 then return true end
        if ns.AurasUnsure and ns.AurasUnsure() then return false end
        local list = ns.ReadBuffs and ns.ReadBuffs() or {}
        if list.unreadable then return false end
        wipe(have)
        for _, a in ipairs(list) do if type(a.name) == "string" then have[a.name:lower()] = true end end
        haveGen, haveAt = ns.auraGen, GetTime()
        return true
    end

    function ns.RefreshRebuff()
        if InCombatLockdown() then return end   -- (secure icons; and your buffs are hidden in a fight)
        local d = db()
        if not d then return end
        local rows = {}
        if d.rebuffOn ~= false and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") == true) and ReadHave() then
            for _, line in ipairs(ns.RebuffList()) do
                local slot, what = WeaponLine(line)
                if slot then
                    local on = WeaponEnchanted(slot)
                    if on ~= nil and HasWeapon(slot) then
                        -- what you could put on (spells you know, items you have); the one you picked last time first
                        local opts, cast, item, itemName = {}, nil, nil, nil
                        local pick = type(d.rebuffPick) == "table" and d.rebuffPick[line] or nil
                        for _, n in ipairs(Names(what)) do
                            if Known(n) then opts[#opts + 1] = { base = n, cast = n }
                            else
                                local id, nm = BagItem(n)
                                if id then opts[#opts + 1] = { base = n, item = id, itemName = nm } end
                            end
                        end
                        local first = opts[1]
                        for _, o in ipairs(opts) do if o.base == pick then first = o end end
                        if first then cast, item, itemName = first.cast, first.item, first.itemName end
                        if not on or d.rebuffAll == true then
                            rows[#rows + 1] = { line = line, cast = cast, item = item, itemName = itemName, slot = slot, have = on, opts = opts }
                        end
                    end
                else
                    local names, got, cast = Names(line), false, nil
                    for _, n in ipairs(names) do
                        if have[n:lower()] then got = true end
                        if not cast and Known(n) then cast = n end
                    end
                    if cast and (not got or d.rebuffAll == true) then
                        rows[#rows + 1] = { line = line, cast = cast, have = got }
                    end
                end
            end
        end
        if #rows == 0 and moving and d.rebuffOn ~= false then   -- unlocked: an example to place it by
            rows[1] = { line = "Your buff", cast = nil, have = false, example = true }
        end
        if #rows == 0 then
            if f then f:Hide() end
            if label then label:Hide() end
            return
        end
        if not f then Build() end
        local vertical = d.rebuffVertical == true
        for i, r in ipairs(rows) do
            local b = f.icons[i] or Icon(i)
            b.line, b.have, b.noItem = r.line, r.have, r.slot and not r.cast and not r.item
            b.opts, b.slot = r.opts, r.slot
            if r.item then   -- a poison / oil from your bags onto that weapon
                b:SetAttribute("type1", "macro")
                b:SetAttribute("macrotext1", "/use " .. r.itemName .. "\n/use " .. r.slot)
                b:SetAttribute("spell1", nil)
            else
                b:SetAttribute("type1", "spell")
                b:SetAttribute("spell1", r.cast or "")
                b:SetAttribute("macrotext1", nil)
            end
            b.icon:SetTexture((r.cast and SpellIcon(r.cast)) or (r.item and ns.ItemIcon and ns.ItemIcon(r.item))
                or (r.slot and "Interface\\Icons\\Trade_BrewPoison") or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(r.have)
            b.icon:SetAlpha(r.have and 0.5 or 1)
            if r.have then b.border:SetColorTexture(0.25, 0.9, 0.3, 1) else b.border:SetColorTexture(1, 0.2, 0.2, 1) end
            if b.pulse then
                if not r.have and not moving then if not b.pulse:IsPlaying() then b.pulse:Play() end
                elseif b.pulse:IsPlaying() then b.pulse:Stop(); b.flash:SetAlpha(0) end
            end
            b:ClearAllPoints()
            local off = PAD + (i - 1) * (ICON + GAP)
            if vertical then b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -off) else b:SetPoint("TOPLEFT", f, "TOPLEFT", off, -PAD) end
            b:EnableMouse(not moving)
            b:Show()
        end
        for i = #rows + 1, #f.icons do f.icons[i]:Hide() end
        local long = PAD * 2 + #rows * ICON + (#rows - 1) * GAP
        if vertical then f:SetSize(ICON + PAD * 2, long) else f:SetSize(long, ICON + PAD * 2) end
        f:EnableMouse(moving and true or false)
        f:EnableMouseWheel(moving and true or false)
        f.bg:SetShown(moving)
        f:Show()
        if moving then
            label = label or MakeLabel("WatchXRebuffLabel")
            label:Set(f, "|cffffd100Rebuff icons|r · drag to move · wheel: size")
        elseif label then
            label:Hide()
        end
    end
    function ns.RebuffMove() ns.RefreshRebuff() end

    -- Which poison (or imbue): hover a weapon icon and a column of what you have comes up beside it – click one to
    -- put it on that weapon; it's then the one the icon uses. Secure buttons (they use an item): out of combat only.
    local fly
    local function FlyButton(i)
        local x = CreateFrame("Button", "WatchXRebuffFly" .. i, fly, "SecureActionButtonTemplate")
        x:RegisterForClicks("AnyUp")
        x:SetAttribute("useOnKeyDown", false)
        x:SetSize(ICON - 4, ICON - 4)
        x.border = x:CreateTexture(nil, "BACKGROUND")
        x.border:SetPoint("TOPLEFT", -1, 1); x.border:SetPoint("BOTTOMRIGHT", 1, -1)
        x.border:SetColorTexture(0.15, 0.15, 0.15, 1)
        x.icon = x:CreateTexture(nil, "ARTWORK")
        x.icon:SetAllPoints()
        x.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = x:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.2)
        x:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label or "?")
            GameTooltip:AddLine("Click: put it on your " .. (fly.slot == 17 and "off hand" or "main hand") .. " – and use it from now on.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        x:SetScript("OnLeave", GameTooltip_Hide)
        x:SetScript("PostClick", function(self)
            local d = db()
            if type(d.rebuffPick) ~= "table" then d.rebuffPick = {} end
            d.rebuffPick[fly.line] = self.base
            if not InCombatLockdown() then fly:Hide() end
        end)
        fly.buttons[i] = x
        return x
    end
    function ns.RebuffFlyout(owner)
        if InCombatLockdown() then return end
        if not fly then
            fly = CreateFrame("Frame", "WatchXRebuffFlyout", UIParent)
            fly:SetFrameStrata("DIALOG")
            fly:SetClampedToScreen(true)
            Flat(fly)
            fly.buttons = {}
            fly:Hide()
            -- gone when the mouse is on neither the icon nor the column (looked at while it's up only)
            fly:SetScript("OnShow", function(self)
                if self.ticker then self.ticker:Cancel() end
                self.ticker = C_Timer.NewTicker(0.25, function()
                    if InCombatLockdown() then return end
                    local over = (self.owner and self.owner:IsMouseOver()) or self:IsMouseOver()
                    self.misses = over and 0 or (self.misses or 0) + 1
                    if self.misses >= 2 then self:Hide() end   -- (twice: crossing the gap to it isn't leaving)
                end)
            end)
            fly:SetScript("OnHide", function(self) if self.ticker then self.ticker:Cancel(); self.ticker = nil end end)
        end
        fly.owner, fly.line, fly.slot = owner, owner.line, owner.slot
        local n = 0
        for _, o in ipairs(owner.opts or {}) do
            n = n + 1
            local x = fly.buttons[n] or FlyButton(n)
            x.base, x.label = o.base, o.itemName or o.cast
            if o.item then
                x:SetAttribute("type1", "macro")
                x:SetAttribute("macrotext1", "/use " .. o.itemName .. "\n/use " .. owner.slot)
                x.icon:SetTexture(ns.ItemIcon and ns.ItemIcon(o.item) or "Interface\\Icons\\Trade_BrewPoison")
            else
                x:SetAttribute("type1", "spell")
                x:SetAttribute("spell1", o.cast)
                x.icon:SetTexture(SpellIcon(o.cast) or "Interface\\Icons\\INV_Misc_QuestionMark")
            end
            x:ClearAllPoints()
            x:SetPoint("TOPLEFT", fly, "TOPLEFT", 4, -4 - (n - 1) * ICON)
            x:Show()
        end
        for i = n + 1, #fly.buttons do fly.buttons[i]:Hide() end
        fly:SetSize(ICON + 4, n * ICON + 4)
        fly:ClearAllPoints()
        local _, y = owner:GetCenter()
        local up = y and y < (UIParent:GetHeight() or 768) * 0.5
        if up then fly:SetPoint("BOTTOM", owner, "TOP", 0, 4) else fly:SetPoint("TOP", owner, "BOTTOM", 0, -4) end
        fly:Show()
    end

    -- your buffs changed (a moment later: one look for a burst), a fight ended, you came into the world
    local ev, waiting = CreateFrame("Frame"), false
    if not pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") then ev:RegisterEvent("UNIT_AURA") end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_INVENTORY_CHANGED", "player")   -- (a poison put on, a weapon changed)
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_DEAD", "PLAYER_UNGHOST",
                         "PLAYER_ALIVE", "BAG_UPDATE_DELAYED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function(_, event, unit)
        if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
        if waiting or not C_Timer or not ns.db then return end
        waiting = true
        C_Timer.After(event == "PLAYER_REGEN_ENABLED" and 3.5 or 0.4, function()
            waiting = false
            ns.Safe("rebuff icons", ns.RefreshRebuff)
        end)
    end)
    if C_Timer and C_Timer.NewTicker then   -- (a buff that ran out by the clock; cheap: it reads only on a change)
        C_Timer.NewTicker(5, function() if ns.db then ns.Safe("rebuff icons", ns.RefreshRebuff) end end)
    end

    -- ---- the settings page
    local page, cat
    function ns.OpenRebuffSettings()
        if cat and Settings and Settings.OpenToCategory then pcall(Settings.OpenToCategory, cat:GetID())
        elseif page and InterfaceOptionsFrame_OpenToCategory then
            pcall(InterfaceOptionsFrame_OpenToCategory, page); pcall(InterfaceOptionsFrame_OpenToCategory, page)
        else ns.OpenSettings() end
    end
    function ns.AddRebuff(text)
        text = tostring(text or ""):match("^%s*(.-)%s*$")
        if text == "" then return false end
        local list = ns.RebuffList()
        local w, base = ns.WeaponLineFor(list, text)
        if w then
            ns.Print("|cffffd100" .. text .. "|r goes on a weapon – added for your |cffffd100" .. (w:find("^Off") and "off hand" or "main hand")
                .. "|r with " .. base .. " picked (any rank you have; pick another in the list).")
            ns.RebuffPick(w, base)
            text = w
        end
        for _, l in ipairs(list) do if l:lower() == text:lower() then return false end end
        list[#list + 1] = text
        local known = WeaponLine(text) ~= nil
        for _, n in ipairs(Names(text)) do if Known(n) then known = true end end
        ns.Print("Rebuff icon: |cffffd100" .. text .. "|r" .. (known and "" or " |cffff8040(not in your spellbook – it shows when you know it)|r"))
        haveGen = nil
        ns.Safe("rebuff icons", ns.RefreshRebuff)
        return true
    end
    local ROWS = 10
    -- one click to add: the usual self buffs of each class (a line's alternatives: any of them counts). Shown only
    -- when you know one of them.
    ns.REBUFF_SUGGEST = {
        MAGE = { "Ice Armor / Frost Armor / Mage Armor / Molten Armor", "Arcane Intellect / Arcane Brilliance", "Dampen Magic / Amplify Magic" },
        PRIEST = { "Power Word: Fortitude / Prayer of Fortitude", "Inner Fire", "Divine Spirit / Prayer of Spirit",
                   "Shadow Protection / Prayer of Shadow Protection", "Shadowform" },
        WARRIOR = { "Battle Shout", "Commanding Shout" },
        DRUID = { "Mark of the Wild / Gift of the Wild", "Thorns", "Omen of Clarity" },
        PALADIN = { "Blessing of Might / Greater Blessing of Might / Blessing of Kings / Greater Blessing of Kings / Blessing of Wisdom / Greater Blessing of Wisdom",
                    "Devotion Aura / Retribution Aura / Concentration Aura / Fire Resistance Aura / Frost Resistance Aura / Shadow Resistance Aura / Sanctity Aura",
                    "Righteous Fury" },
        WARLOCK = { "Demon Armor / Demon Skin / Fel Armor", "Soul Link", "Unending Breath" },
        HUNTER = { "Aspect of the Hawk / Aspect of the Monkey / Aspect of the Viper / Aspect of the Dragonhawk", "Trueshot Aura" },
        SHAMAN = { "Lightning Shield / Water Shield", "Main hand: Windfury Weapon / Flametongue Weapon / Rockbiter Weapon / Frostbrand Weapon",
                   "Off hand: Flametongue Weapon / Windfury Weapon / Frostbrand Weapon / Rockbiter Weapon" },
        ROGUE = { "Main hand: Instant Poison / Deadly Poison / Wound Poison / Crippling Poison / Mind-numbing Poison",
                  "Off hand: Deadly Poison / Instant Poison / Crippling Poison / Wound Poison / Mind-numbing Poison" },
    }
    local function Short(line)   -- "Ice Armor / Frost Armor / …" -> "Ice Armor …" (for a button)
        local n = Names(line)
        return n[1] and (n[1] .. (#n > 1 and " …" or "")) or line
    end
    function ns.BuildRebuffSettings()
        page = CreateFrame("Frame", "WatchXRebuffOptions", UIParent)
        page.name, page.parent = "Rebuff icons", "WatchX"
        page:Hide()
        local L, W = 20, 560
        local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
        title:SetText("Rebuff icons")
        local sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
        sub:SetText("a pulsing icon for each of your buffs you're missing – click it to cast it")
        local y, checks = -50, {}
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
                ns.Safe("rebuff icons", ns.RefreshRebuff)
            end)
            checks[#checks + 1] = cb
            y = y - 26
        end
        check("Show rebuff icons", nil, function() return db().rebuffOn ~= false end, function(v) db().rebuffOn = v end)
        check("In a column", "off: in a row", function() return db().rebuffVertical == true end, function(v) db().rebuffVertical = v end)
        check("Also the ones you have", "dimmed, with a green edge", function() return db().rebuffAll == true end, function(v) db().rebuffAll = v end)
        y = y - 8
        -- add one
        local lab = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lab:SetPoint("TOPLEFT", page, "TOPLEFT", L, y - 4)
        lab:SetText("Add a buff")
        local eb = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
        eb:SetSize(240, 20)
        eb:SetPoint("TOPLEFT", page, "TOPLEFT", L + 100, y)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(80)
        eb.hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        eb.hint:SetPoint("LEFT", eb, "LEFT", 2, 0)
        eb.hint:SetText("e.g. Ice Armor")
        local function go()
            if ns.AddRebuff(eb:GetText()) then eb:SetText("") end
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
        local mv = Button(page, "Move", 70, 22, function()
            HideBlizzardMenus()
            if not moving then ns.StartMove() end
        end)
        mv:SetPoint("LEFT", add, "RIGHT", 6, 0)
        y = y - 30
        -- suggestions for your class: "+ Ice Armor …" (filled in when the page shows: your class, what you know)
        local sugLab = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sugLab:SetPoint("TOPLEFT", page, "TOPLEFT", L, y - 4)
        sugLab:SetText("Quick add:")
        local sugs = {}
        for i = 1, 6 do
            local b = Button(page, "", 150, 20, function(self)
                if self.line and ns.AddRebuff(self.line) then Refresh() end
            end)
            b:SetPoint("TOPLEFT", page, "TOPLEFT", L + 70 + ((i - 1) % 3) * 156, y - math.floor((i - 1) / 3) * 24)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Add: " .. tostring(self.line):gsub(" / ", "\n  or "), 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", GameTooltip_Hide)
            b:Hide()
            sugs[i] = b
        end
        page.sugs = sugs   -- (for the tests)
        y = y - 52
        local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", page, "TOPLEFT", L - 4, y)
        head:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        y = y - 18
        local rows = {}
        for i = 1, ROWS do
            local r = CreateFrame("Frame", nil, page)
            r:SetSize(430, 20)
            r:SetPoint("TOPLEFT", page, "TOPLEFT", L, y - (i - 1) * 22)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.del = FlatButton(r, "x", 20, 18, function()
                local list = ns.RebuffList()
                if r.index and list[r.index] then table.remove(list, r.index) end
                ns.Safe("rebuff icons", ns.RefreshRebuff)
                Refresh()
            end)
            r.del:SetPoint("LEFT", r, "LEFT", 400, 0)
            r.pick = FlatButton(r, "v", 20, 18, function(self)
                local line = r.line
                local cur, names = ns.RebuffPicked(line)
                local items = {}
                for _, n in ipairs(names) do
                    items[#items + 1] = { (n == cur and "|cffffd100> " .. n .. "|r") or ("   " .. n), function()
                        ns.RebuffPick(line, n); Refresh(); ns.Safe("rebuff icons", ns.RefreshRebuff)
                    end }
                end
                ns.ShowMenu(self, "Use on your " .. (line:find("^%s*[Oo]ff") and "off hand" or "main hand"), items)
            end)
            r.pick:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
            r.pick:Hide()
            r:Hide()
            rows[i] = r
        end
        local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", page, "TOPLEFT", L + 2, y - 3)
        empty:SetText("Nothing yet – add a buff above (its name as in your spellbook).")
        y = y - ROWS * 22 - 10
        local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("TOPLEFT", page, "TOPLEFT", L, y)
        help:SetWidth(W)
        help:SetJustifyH("LEFT")
        help:SetSpacing(3)
        help:SetText("|cffaaaaaaThe list is for this class (a mage's Ice Armor doesn't show on your warrior); spells you don't know "
            .. "yet are left out. Your buffs can't be seen in a fight on Forever: the icons change when it's over.|r\n"
            .. "|cff808080/wx rebuff – this page   ·   /wx rebuff <name> – add one|r")
        Refresh = function()
            for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end
            local list = ns.RebuffList()
            local _, cls = UnitClass("player")
            head:SetText("YOUR " .. tostring(cls or ""):upper() .. " BUFFS")
            for i, r in ipairs(rows) do
                local line = list[i]
                if line then
                    r.index = i
                    local cast
                    local wslot, wwhat = WeaponLine(line)
                    for _, n in ipairs(Names(wwhat or line)) do if not cast and Known(n) then cast = n end end
                    r.icon:SetTexture((cast and SpellIcon(cast)) or (wslot and "Interface\\Icons\\Trade_BrewPoison") or "Interface\\Icons\\INV_Misc_QuestionMark")
                    r.line = line
                    if wslot then   -- a weapon: the one it uses, and how many to pick from
                        local cur, names = ns.RebuffPicked(line)
                        r.text:SetText((wslot == 17 and "Off hand: " or "Main hand: ") .. "|cffffd100" .. cur .. "|r"
                            .. (#names > 1 and ("  |cff808080(" .. (#names - 1) .. " more to pick from)|r") or ""))
                    else
                        r.text:SetText(line .. (cast and "" or "  |cff808080(not known)|r"))
                    end
                    r.pick:SetShown(wslot ~= nil and #(select(2, ns.RebuffPicked(line))) > 1)
                    r:Show()
                else
                    r:Hide()
                end
            end
            empty:SetShown(#list == 0)
            -- quick add: your class's usual ones you know and haven't added
            local added = {}
            for _, l in ipairs(list) do added[l:lower()] = true end
            local n = 0
            for _, line in ipairs(ns.REBUFF_SUGGEST[cls or ""] or {}) do
                local wslot, wwhat = WeaponLine(line)
                local known = wslot ~= nil and cls == "ROGUE"   -- (poisons: from your bags, nothing to know)
                for _, nm in ipairs(Names(wwhat or line)) do if Known(nm) then known = true end end
                if known and not added[line:lower()] and n < #sugs then
                    n = n + 1
                    sugs[n].line = line
                    SetButtonText(sugs[n], "+ " .. Short(line))
                    sugs[n]:Show()
                end
            end
            for i = n + 1, #sugs do sugs[i]:Hide() end
            sugLab:SetShown(n > 0)
        end
        page:SetScript("OnShow", function() Refresh() end)
        if settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
            local ok, c = pcall(Settings.RegisterCanvasLayoutSubcategory, settingsCategory, page, "Rebuff icons")
            if ok and c then cat = c end
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(page)
        end
    end
end)() end

-- ---------------------------------------------------------------- export / import (/wx export)
-- Everything WatchX keeps is for the whole account (all your characters): settings and profiles (and which profile
-- each character uses), and – if ticked – the Enemies history (KOS, avoid, notes), KOS guilds and bounties, and your
-- phone links (private: off unless ticked). One line of text to copy and keep; pasting it back shows what's in it
-- first. It's read by a small parser of our own, never run as code: a pasted text can only set saved values.
do (function()
    -- what goes where. Caches the addon fills by itself, and the logs, are never exported.
    local NEVER = { roles = true, log = true, previousLog = true, recipes = true, xpFoods = true, methodFailed = true,
        mobs = true, exitAt = true, exitWhy = true, chatlogOn = true }
    local ENEMIES = { enemies = true, kosGuilds = true, wanted = true }
    local SECRET = { discordWebhook = true, ntfyUrl = true, discordMention = true, bridgeKey = true }

    -- ---- the text: s<len>:<bytes> | n<number>; | t | f | { key value … }
    local function Ser(v, out, depth)
        local t = type(v)
        if t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
        elseif t == "number" then out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
        elseif t == "boolean" then out[#out + 1] = v and "t" or "f"
        elseif t == "table" and depth < 24 then
            out[#out + 1] = "{"
            for k, x in pairs(v) do
                local kt, xt = type(k), type(x)
                if (kt == "string" or kt == "number") and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
                    Ser(k, out, depth + 1); Ser(x, out, depth + 1)
                end
            end
            out[#out + 1] = "}"
        else
            out[#out + 1] = "f"
        end
    end
    local function Parse(s, i, depth)   -- value, next position (nil when it isn't ours)
        local c = s:sub(i, i)
        if c == "s" then
            local len, rest = s:match("^(%d+):()", i + 1)
            len = tonumber(len)
            if not len or rest + len - 1 > #s then return nil end
            return s:sub(rest, rest + len - 1), rest + len
        elseif c == "n" then
            local num, rest = s:match("^([%-%d%.eE+naif]+);()", i + 1)
            num = tonumber(num)
            if not num then return nil end
            return num, rest
        elseif c == "t" then return true, i + 1
        elseif c == "f" then return false, i + 1
        elseif c == "{" and depth < 24 then
            local t = {}
            i = i + 1
            while s:sub(i, i) ~= "}" do
                if i > #s then return nil end
                local k, v
                k, i = Parse(s, i, depth + 1)
                if k == nil or (type(k) ~= "string" and type(k) ~= "number") then return nil end
                v, i = Parse(s, i, depth + 1)
                if v == nil then return nil end
                t[k] = v
            end
            return t, i + 1
        end
        return nil
    end
    -- base64: the text has no "|" (the chat box reads those as codes) and no line breaks
    local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local ENC, DEC = {}, {}
    for i = 1, 64 do ENC[i - 1] = B:sub(i, i); DEC[B:byte(i)] = i - 1 end
    local function Enc(s)
        local out, n = {}, #s
        for i = 1, n, 3 do
            local a, b, c = s:byte(i, i + 2)
            local v = a * 65536 + (b or 0) * 256 + (c or 0)
            local d1, d2 = math.floor(v / 262144) % 64, math.floor(v / 4096) % 64
            local d3, d4 = math.floor(v / 64) % 64, v % 64
            out[#out + 1] = ENC[d1] .. ENC[d2] .. (b and ENC[d3] or "=") .. (c and ENC[d4] or "=")
        end
        return table.concat(out)
    end
    local function Dec(s)
        s = s:gsub("[^%w%+/=]", "")
        local out = {}
        for i = 1, #s, 4 do
            local c1, c2, c3, c4 = s:byte(i, i + 3)
            local d1, d2, d3, d4 = DEC[c1], DEC[c2], DEC[c3 or 0], DEC[c4 or 0]
            if d1 == nil or d2 == nil then break end
            local v = d1 * 262144 + d2 * 4096 + (d3 or 0) * 64 + (d4 or 0)
            local a, b, c = math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
            out[#out + 1] = string.char(a) .. (d3 and string.char(b) or "") .. (d4 and string.char(c) or "")
        end
        return table.concat(out)
    end
    local function Sum(s)   -- a check that it came back whole
        local h = 0
        for i = 1, #s do h = (h * 31 + s:byte(i)) % 16777213 end
        return h
    end

    function ns.MakeExport(opts)
        local d = db()
        if ns.SaveProfile then ns.SaveProfile() end   -- (the active profile as it is now)
        local pick = {}
        for k, v in pairs(d) do
            local enemy = ENEMIES[k]
            if not NEVER[k] and ((enemy and opts.enemies) or (SECRET[k] and opts.secrets)
                    or (not enemy and not SECRET[k] and opts.settings)) then
                pick[k] = v
            end
        end
        local out = {}
        Ser({ v = 1, what = { settings = opts.settings or nil, enemies = opts.enemies or nil, secrets = opts.secrets or nil },
              at = time(), data = pick }, out, 0)
        local body = table.concat(out)
        return "WATCHX1:" .. #body .. ":" .. Sum(body) .. ":" .. Enc(body)
    end
    function ns.ReadExport(text)   -- the export table, or nil + why
        text = tostring(text or ""):gsub("%s", "")
        local len, sum, data = text:match("^WATCHX1:(%d+):(%d+):(.+)$")
        if not len then return nil, "That isn't a WatchX export (it starts with WATCHX1:)." end
        local body = Dec(data)
        if #body ~= tonumber(len) or Sum(body) ~= tonumber(sum) then
            return nil, "The text is cut or changed – copy all of it (Ctrl+A, Ctrl+C) and try again."
        end
        local t = Parse(body, 1, 0)
        if type(t) ~= "table" or type(t.data) ~= "table" then return nil, "The text couldn't be read." end
        return t
    end
    -- settings: replaced (yours are lost – an export first is a good idea); enemies, KOS guilds, bounties: merged
    function ns.ApplyExport(t)
        local d = db()
        local n = { settings = 0, enemies = 0 }
        for k, v in pairs(t.data) do
            if k == "enemies" and type(v) == "table" then
                d.enemies = d.enemies or {}
                for key, r in pairs(v) do
                    if type(r) == "table" then
                        local mine = d.enemies[key]
                        if not mine then d.enemies[key] = r; n.enemies = n.enemies + 1
                        else
                            mine.kos = mine.kos or r.kos
                            mine.avoid = mine.avoid or r.avoid
                            mine.note = mine.note or r.note
                            mine.kills = math.max(tonumber(mine.kills) or 0, tonumber(r.kills) or 0)
                            mine.deaths = math.max(tonumber(mine.deaths) or 0, tonumber(r.deaths) or 0)
                        end
                    end
                end
            elseif (k == "kosGuilds" or k == "wanted") and type(v) == "table" then
                d[k] = type(d[k]) == "table" and d[k] or {}
                for key, x in pairs(v) do if d[k][key] == nil then d[k][key] = x end end
            elseif not NEVER[k] then
                d[k] = v
                n.settings = n.settings + 1
            end
        end
        return n
    end

    -- ---- the window
    local win
    local function Build()
        win = CreateFrame("Frame", "WatchXExport", UIParent)
        win:SetFrameStrata("DIALOG")
        win:SetSize(520, 390)
        win:SetPoint("CENTER")
        win:SetClampedToScreen(true)
        win:EnableMouse(true)
        win:SetMovable(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        Flat(win)
        tinsert(UISpecialFrames, "WatchXExport")
        local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("Export / import")
        local sub = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
        sub:SetText("all your characters – keep it in a text file, or move it to another PC")
        local x = Button(win, "x", 22, 22, function() win:Hide() end)
        x:SetPoint("TOPRIGHT", -8, -8)
        win.opts = { settings = true, enemies = true, secrets = false }
        local y = -40
        local function check(key, label, hint)
            local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", 10, y)
            local t = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("LEFT", cb, "RIGHT", 2, 1)
            t:SetText(label .. (hint and ("  |cff808080" .. hint .. "|r") or ""))
            cb:SetChecked(win.opts[key])
            cb:SetScript("OnClick", function(self) win.opts[key] = self:GetChecked() and true or false end)
            y = y - 24
        end
        check("settings", "Settings & profiles", "and which profile each character uses")
        check("enemies", "Enemies, KOS, notes & bounties", "the players you've met")
        check("secrets", "Phone links", "|cffff8040private – your Discord / ntfy links: only for yourself|r")
        local mk = Button(win, "Export", 100, 22, function()
            local ok, text = pcall(ns.MakeExport, win.opts)
            win.box:SetText(ok and text or "")
            win.box:SetFocus()
            win.box:HighlightText()
            win.status:SetText(ok and ("|cff40ff40Ready|r – Ctrl+C to copy (" .. math.floor(#text / 1024 + 0.5) .. " kB of text).")
                or ("|cffff6060Couldn't make it:|r " .. tostring(text)))
            win.pending = nil
            win.imp:SetText("Import")
        end)
        mk:SetPoint("TOPLEFT", 14, y - 4)
        win.imp = Button(win, "Import", 100, 22, function()
            if win.pending then   -- the second click: do it
                local n = ns.ApplyExport(win.pending)
                win.pending = nil
                win.imp:SetText("Import")
                win.status:SetText("|cff40ff40Imported|r: " .. n.settings .. " settings, " .. n.enemies
                    .. " new players. |cffffd100Reload to use it all.|r")
                win.reload:Show()
                return
            end
            local t, why = ns.ReadExport(win.box:GetText())
            if not t then win.status:SetText("|cffff6060" .. why .. "|r") return end
            local w, parts = t.what or {}, {}
            if w.settings then parts[#parts + 1] = "settings & profiles (yours are replaced)" end
            if w.enemies then parts[#parts + 1] = "enemies, KOS & bounties (added to yours)" end
            if w.secrets then parts[#parts + 1] = "|cffff8040phone links|r" end
            win.pending = t
            win.imp:SetText("|cffffd100Yes, import|r")
            win.status:SetText("From " .. (t.at and date("%d %b %Y %H:%M", t.at) or "?") .. ": " .. table.concat(parts, ", ")
                .. ". Click again to import.")
        end)
        win.imp:SetPoint("LEFT", mk, "RIGHT", 8, 0)
        win.reload = Button(win, "Reload now", 100, 22, function() ReloadUI() end)
        win.reload:SetPoint("LEFT", win.imp, "RIGHT", 8, 0)
        win.reload:Hide()
        win.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        win.status:SetPoint("TOPLEFT", 14, y - 32)
        win.status:SetWidth(490)
        win.status:SetJustifyH("LEFT")
        -- the text: a scrolling box (paste an export here to import it)
        local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, y - 52)
        sf:SetPoint("BOTTOMRIGHT", -32, 14)
        local bg = win:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetPoint("TOPLEFT", sf, -4, 4); bg:SetPoint("BOTTOMRIGHT", sf, 4, -4)
        bg:SetColorTexture(0, 0, 0, 0.5)
        local box = CreateFrame("EditBox", nil, sf)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        box:SetWidth(460)
        if box.SetMaxLetters then box:SetMaxLetters(0) end
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnTextChanged", function(_, user) if user then win.pending = nil; win.imp:SetText("Import") end end)
        sf:SetScrollChild(box)
        win.box = box
        win:Hide()
    end
    function ns.ShowExport(import)
        if not win then Build() end
        win.pending = nil
        win.imp:SetText("Import")
        win.reload:Hide()
        win.box:SetText("")
        win.status:SetText(import and "Paste an export below (Ctrl+V), then click Import."
            or "Tick what to take with you, then click Export – or paste one below and click Import.")
        win:Show()
        if import then win.box:SetFocus() end
    end
end)() end

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
    local work = ns.Timed(function()
        local d = db()
        if not (d.plateFriendly and d.plateHealer ~= false) or InCombatLockdown() then return end
        for unit in pairs(plateUnits) do ns.Safe("inspect", ns.MaybeInspect, unit) end
    end, "nameplate icons tick")
    if C_Timer and C_Timer.NewTicker then   -- every 3 s (a timer, not a check every frame)
        C_Timer.NewTicker(3, function() ns.Safe("nameplate icons", work) end)
    else
        f:SetScript("OnUpdate", function(_, elapsed)
            wait = wait + elapsed
            if wait < 3 then return end
            wait = 0
            work()
        end)
    end
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
    if InCombatLockdown() then   -- a reload in a fight: its secure icons are made when it's over
        ns.levelPending = true
    else
        lv = BuildLevel()
        ns.levelFrame = lv
    end
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
