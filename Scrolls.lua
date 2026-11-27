-- WatchX: right-click a scroll you can't read yet (a mage's "Scroll: …") to cast Comprehend Scroll on it – one
-- click instead of the spell and then the scroll.
--
-- How: while the mouse is over such a scroll in your bags (out of combat), a secure button sits over it whose
-- right-click is "/cast Comprehend Scroll" + "/use <bag> <slot>" (the pending spell then lands on that item). A
-- left-click goes through to the bag as usual (drag, move). Never in a fight (the game hides it then), and not
-- while you're writing a letter (right-click puts the scroll in the mail).
local _, ns = ...

-- Comprehend Scroll's IDs on WoW Forever (the client has several ranks / versions of it)
local SPELL_IDS = { 1309973, 1310030, 1296017, 1309965, 1310029 }
local SPELL_NAME = "Comprehend Scroll"

local function On()
    return ns.db and ns.db.comprehendClick ~= false
end
local function Plain(v)
    if issecretvalue and v ~= nil and issecretvalue(v) then return nil end
    return v
end

-- The spell's name if you know it, else nil. (Asked on each hover: cheap, and a new rank counts at once.)
function ns.ComprehendSpell()
    for _, id in ipairs(SPELL_IDS) do
        local known = false
        local SB = C_SpellBook or {}
        for _, f in ipairs({ SB.IsSpellKnown or false, SB.IsSpellInSpellBook or false, IsPlayerSpell or false,
                IsSpellKnown or false }) do
            if f then
                local ok, yes = pcall(f, id)
                if ok and Plain(yes) == true then known = true break end
            end
        end
        if known then
            local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
            local ok, n = pcall(get or function() end, id)
            n = ok and Plain(n)
            return type(n) == "string" and n or SPELL_NAME
        end
    end
    -- not found by ID: by name (the spellbook answers only for spells you have)
    local info = C_Spell and C_Spell.GetSpellInfo
    if info then
        local ok, t = pcall(info, SPELL_NAME)
        if ok and type(t) == "table" and Plain(t.name) then return SPELL_NAME end
    end
    return nil
end

-- Is the item in that bag slot a scroll you can't read yet? Its name starts with "Scroll:".
function ns.IsUnreadScroll(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return false end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" then return false end
    if Plain(info.isLocked) == true then return false end
    local link = Plain(info.hyperlink)
    local name = type(link) == "string" and link:match("%[(.-)%]") or nil
    if not name and C_Item and C_Item.GetItemNameByID and Plain(info.itemID) then
        local okN, n = pcall(C_Item.GetItemNameByID, Plain(info.itemID))
        name = okN and Plain(n) or nil
    end
    return type(name) == "string" and name:match("^Scroll:%s") ~= nil
end

local function WritingMail()
    return SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown() and true or false
end

local btn
local function Build()
    btn = CreateFrame("Button", "WatchXComprehend", UIParent, "SecureActionButtonTemplate")
    btn:SetFrameStrata("TOOLTIP")
    btn:RegisterForClicks("RightButtonUp", "RightButtonDown")   -- (either: the "cast on key down" setting)
    btn:SetAttribute("type2", "macro")
    if btn.SetPassThroughButtons then pcall(btn.SetPassThroughButtons, btn, "LeftButton") end   -- left: the bag's own
    -- the scroll under the mouse: a clear purple – a fill and an edge, gently pulsing (the game's animation)
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetColorTexture(0.7, 0.4, 1, 0.38)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetColorTexture(0.85, 0.6, 1, 1)
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetHeight(2) else t:SetWidth(2) end
    end
    if glow.CreateAnimationGroup then
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0.45); a:SetDuration(0.6)
        btn:SetScript("OnShow", function() ag:Play() end)
        btn:SetScript("OnHide", function() ag:Stop() end)
    end
    btn:SetScript("OnEnter", function(self)
        if not self.bag then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.bag, self.slot)
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not InCombatLockdown() then self:Hide() end
        self.bag, self.slot = nil, nil
    end)
    btn:Hide()
    -- a fight: the game hides it (addon code may not then)
    if RegisterAttributeDriver then pcall(RegisterAttributeDriver, btn, "visibility", "[combat] hide") end
end

-- Over that bag button, in UIParent's coordinates (anchored to it, the bag button would turn protected).
local function Cover(owner)
    local l, b, w, h
    if owner.GetScaledRect then l, b, w, h = owner:GetScaledRect() end
    if not (l and b and w and h) then
        local s = owner:GetEffectiveScale() or 1
        l, b = owner:GetLeft(), owner:GetBottom()
        w, h = owner:GetWidth(), owner:GetHeight()
        if not (l and b and w and h) then return false end
        l, b, w, h = l * s, b * s, w * s, h * s
    end
    if w <= 0 or h <= 0 then return false end
    local u = UIParent:GetEffectiveScale() or 1
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l / u, b / u)
    btn:SetSize(w / u, h / u)
    return true
end

local saidAt, saidFor   -- (both ways below may see one tooltip: its line once)
local function Why(text) ns.comprehendWhy = text end
local function Hover(tip, bag, slot)
    ns.comprehendSeen = (ns.comprehendSeen or 0) + 1
    if tip ~= GameTooltip then return end
    if not On() then Why("switched off (Settings > WatchX)") return end
    if InCombatLockdown() then Why("in a fight") return end
    local owner = tip:GetOwner()
    if btn and owner == btn then bag, slot = btn.bag, btn.slot end
    local key = tostring(owner) .. ":" .. tostring(bag) .. ":" .. tostring(slot)
    if saidAt == GetTime() and saidFor == key then return end
    if btn and owner == btn then   -- (our own tooltip, over the scroll)
        if not bag then return end
        saidAt, saidFor = GetTime(), key
        tip:AddLine("Right-click: " .. (ns.ComprehendSpell() or SPELL_NAME), 0.75, 0.55, 1)
        tip:Show()
        return
    end
    if not (owner and bag and slot) then Why("the bag didn't say which slot") return end
    if WritingMail() then Why("writing a letter") return end
    local spell = ns.ComprehendSpell()
    if not spell then Why("Comprehend Scroll isn't in your spellbook") return end
    if not ns.IsUnreadScroll(bag, slot) then Why(("bag %s slot %s isn't a \"Scroll: …\""):format(tostring(bag), tostring(slot))) return end
    if not btn then Build() end
    if not Cover(owner) then Why("couldn't find where the bag slot is on screen") return end
    Why(("ready over bag %d slot %d – right-click"):format(bag, slot))
    btn.bag, btn.slot = bag, slot
    btn:SetAttribute("macrotext2", ("/cast %s\n/use %d %d"):format(spell, bag, slot))
    btn:Show()
    saidAt, saidFor = GetTime(), key
    tip:AddLine("Right-click: " .. spell, 0.75, 0.55, 1)
    tip:Show()
end
ns.ComprehendHover = Hover   -- (tests)

-- The bag's tooltip says which slot the mouse is over.
if GameTooltip and hooksecurefunc then
    hooksecurefunc(GameTooltip, "SetBagItem", function(tip, bag, slot) ns.Safe("comprehend", Hover, tip, bag, slot) end)
end
-- Bag addons that show the item another way: the slot from the button under it.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
        if tip ~= GameTooltip then return end
        local owner = tip.GetOwner and tip:GetOwner()
        if not owner then return end
        if owner == btn then ns.Safe("comprehend", Hover, tip) return end
        local bag, slot
        if owner.GetSlotAndBagID then slot, bag = owner:GetSlotAndBagID()
        elseif owner.GetBagID and owner.GetID then bag, slot = owner:GetBagID(), owner:GetID() end
        if type(bag) == "number" and type(slot) == "number" and bag >= 0 and bag <= 5 then
            ns.Safe("comprehend", Hover, tip, bag, slot)
        end
    end)
end
-- a letter opened while it's up: away (right-click is the mail's then)
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("MAIL_SHOW")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:SetScript("OnEvent", function()
        if btn and btn:IsShown() and not InCombatLockdown() then btn:Hide(); btn.bag, btn.slot = nil, nil end
    end)
end

-- /wx scroll: what the right-click sees (the spell, your scrolls, the last hover)
function ns.ScrollDebug()
    local P = ns.Print or print
    local spell = ns.ComprehendSpell()
    P("Comprehend Scroll: " .. (spell and ("|cff40ff40known|r (" .. spell .. ")") or "|cffff6060not found in your spellbook|r"))
    P("Right-click: " .. (On() and "on" or "|cffff6060off|r (Settings > WatchX)"))
    local n = 0
    for bag = 0, 5 do
        local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okN and tonumber(Plain(slots)) or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            local link = ok and type(info) == "table" and Plain(info.hyperlink)
            local name = type(link) == "string" and link:match("%[(.-)%]")
            if type(name) == "string" and name:lower():find("scroll", 1, true) then
                n = n + 1
                P(("  bag %d slot %d: %s  %s"):format(bag, slot, name,
                    ns.IsUnreadScroll(bag, slot) and "|cff40ff40– can be comprehended|r" or "|cff999999– not a \"Scroll: …\"|r"))
            end
        end
    end
    if n == 0 then P("  No scrolls in your bags.") end
    P("Tooltips seen: " .. (ns.comprehendSeen or 0) .. (ns.comprehendWhy and (" · last: " .. ns.comprehendWhy) or " · none over a bag yet"))
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("MageFamiliar") then
        P("|cffff8040Mage Familiar is on too|r – both put a button over the scroll. Switch it off.")
    end
end
