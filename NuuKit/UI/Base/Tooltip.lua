local addonName, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- Tooltips are Blizzard's GameTooltip, as in OpenRoad: it matches the game's
-- own item and recipe tooltips the kit chains under it. Ported from
-- OpenRoad's Theme:Tooltip.

-- The game's own tooltip of what a tooltip is about, under it: a GameTooltip
-- of its own, so the addon's lines stay apart from the game's.
local linkTips = {}

local function hideLinkTips()
    for _, frame in pairs(linkTips) do frame:Hide() end
end

local function linkTip(key)
    if linkTips[key] then return linkTips[key] end
    local ok, frame = pcall(CreateFrame, "GameTooltip", addonName .. "Kit" .. key .. "Tooltip", UIParent, "GameTooltipTemplate")
    if not ok or not frame then return nil end
    if next(linkTips) == nil and GameTooltip.HookScript then GameTooltip:HookScript("OnHide", hideLinkTips) end
    linkTips[key] = frame
    return frame
end

-- Fills one chained tooltip with the game's own: false when the client
-- knows nothing to show.
local function fillLinkTip(frame, kind, id)
    frame:SetOwner(GameTooltip, "ANCHOR_NONE")
    local function filled() return frame.NumLines and (frame:NumLines() or 0) > 0 end
    local set, link = frame.SetItemByID, "item:" .. id
    if kind ~= "item" then set, link = frame.SetSpellByID, "enchant:" .. id end
    local shown = set and pcall(set, frame, id) and filled()
    if not shown then
        frame:SetOwner(GameTooltip, "ANCHOR_NONE")
        shown = pcall(frame.SetHyperlink, frame, link) and filled()
    end
    if shown then return true end
    frame:Hide()
    return false
end

-- The recipe's tooltip already holds the item it makes, so the item's own
-- shows only where there is no recipe, or the client cannot draw it.
local function drawLinks(links)
    hideLinkTips()
    if not links then return end
    local frame = links.spell and linkTip("Recipe")
    if not (frame and fillLinkTip(frame, "spell", links.spell)) then
        frame = links.item and linkTip("Item")
        if not (frame and fillLinkTip(frame, "item", links.item)) then return end
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
    frame:Show()
end

-- `filler` is a string (wrapped) or `fn(GameTooltip)` for text that depends
-- on the moment. `opts.anchor` is an ANCHOR_ name, or a window to stand
-- beside, level with the widget; the cursor otherwise. `opts.links` is
-- { item = id, spell = id } for the game's own tooltip under it. `opts.reason`
-- adds a line in the danger colour: why a control is disabled.
function Proto:Tooltip(owner, filler, opts)
    opts = opts or {}
    if not GameTooltip or not owner or (filler == nil and not opts.reason) then return end
    local anchor = opts.anchor
    if type(anchor) == "table" then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        local top, windowTop = owner:GetTop(), anchor:GetTop()
        local offset = 0
        if top and windowTop then
            offset = (top * owner:GetEffectiveScale() - windowTop * anchor:GetEffectiveScale()) / GameTooltip:GetEffectiveScale()
        end
        GameTooltip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, offset)
    else
        GameTooltip:SetOwner(owner, anchor or "ANCHOR_CURSOR")
    end
    if type(filler) == "function" then
        filler(GameTooltip)
    elseif filler ~= nil then
        GameTooltip:SetText(tostring(filler), 1, 1, 1, 1, true)
    end
    if opts.reason then
        local c = self.tokens.danger
        if filler == nil then
            GameTooltip:SetText(opts.reason, c[1], c[2], c[3], 1, true)
        else
            GameTooltip:AddLine(opts.reason, c[1], c[2], c[3], true)
        end
    end
    GameTooltip:Show()
    drawLinks(opts.links)
end

function Proto:HideTooltip()
    hideLinkTips()
    if GameTooltip then GameTooltip:Hide() end
end

-- A widget's own tooltip: `widget.tooltip` (string or function), plus
-- `widget.kitReason` while it is disabled. Above the widget, where it covers
-- nothing the cursor is about to reach.
function UI.HookTooltip(widget)
    if widget.kitTooltipHooked or not widget.HookScript then return end
    widget.kitTooltipHooked = true
    widget:HookScript("OnEnter", function(w)
        local reason = w.kitReason
        local item = w.kitLinks and w.kitLinks.item
        if w.tooltip == nil and not reason and item and GameTooltip then
            -- An item and nothing to add: the game's own tooltip of it.
            GameTooltip:SetOwner(w, w.kitTooltipAnchor or "ANCHOR_TOP")
            if pcall(GameTooltip.SetItemByID, GameTooltip, item) then GameTooltip:Show() end
            return
        end
        if w.tooltip == nil and not reason then return end
        w.ui:Tooltip(w, w.tooltip, { anchor = w.kitTooltipAnchor or "ANCHOR_TOP", reason = reason, links = w.kitLinks })
    end)
    widget:HookScript("OnLeave", function(w)
        if w.tooltip ~= nil or w.kitReason or w.kitLinks then w.ui:HideTooltip() end
    end)
    -- A disabled button is sent no hover without this, and its tooltip is
    -- where it says why it is disabled.
    if widget.SetMotionScriptsWhileDisabled then pcall(widget.SetMotionScriptsWhileDisabled, widget, true) end
end
