local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- Strips of icon slots, ported from OpenRoad's StripPanel and SlotChrome:
-- a header plate the player drags, and a body with no plate at all, so only
-- the slots themselves sit on the world.

local HEADER, SLOT = 20, 36

-- Item facts from whichever API the client has.
local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and icon then return icon end
    end
    if type(GetItemIcon) == "function" then
        local ok, icon = pcall(GetItemIcon, id)
        if ok then return icon end
    end
    return nil
end

local function itemQuality(id)
    if C_Item and C_Item.GetItemQualityByID then
        local ok, quality = pcall(C_Item.GetItemQualityByID, id)
        if ok and quality then return quality end
    end
    if type(GetItemInfo) == "function" then
        local ok, _, _, quality = pcall(GetItemInfo, id)
        if ok then return quality end
    end
    return nil
end

local function qualityColor(quality)
    if not quality then return nil end
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and r then return { r, g, b, 1 } end
    end
    local colors = _G.ITEM_QUALITY_COLORS
    local color = colors and colors[quality]
    if color and color.r then return { color.r, color.g, color.b, 1 } end
    return nil
end

local function itemCooldown(id)
    local fn = C_Container and C_Container.GetItemCooldown or _G.GetItemCooldown
    if type(fn) ~= "function" then return nil end
    local ok, start, duration, enabled = pcall(fn, id)
    if not ok then return nil end
    return start, duration, enabled
end

-- The strip: `opts` key, place (the addon's table), title, summary, rail
-- (a tone for the coloured edge of the header), point (where it goes the
-- first time), size of a slot. `strip:Slot(opts)` adds a slot; `strip:Clear()`
-- takes them away.
function Proto:StripPanel(opts)
    opts = opts or {}
    local ui = self
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.kitIsWindow, panel.ui = true, ui
    panel:SetFrameStrata(opts.strata or "MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetSize(200, HEADER + 4 + (opts.size or SLOT))
    local placed = opts.place and opts.key and opts.place[opts.key]
    if placed and placed.x then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", placed.x, placed.y)
    else
        local point = opts.point or { "CENTER", UIParent, "CENTER", 0, -120 }
        panel:SetPoint(point[1], point[2] or UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
    end

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT")
    header:SetHeight(HEADER)
    header:EnableMouse(true)
    header.plate = UI.NewPlate(header)
    header.rail = header:CreateTexture(nil, "OVERLAY")
    local edge = UI.Pixels(header, 1)
    header.rail:SetPoint("TOPLEFT", edge, -edge)
    header.rail:SetPoint("BOTTOMLEFT", edge, edge)
    UI.Stroke(header.rail, "width", 2)
    header.title = UI.NewText(header)
    header.title:SetPoint("LEFT", header, "LEFT", 8, 0)
    header.title:SetText(opts.title or "")
    header.summary = UI.NewText(header)
    header.summary:SetPoint("RIGHT", header, "RIGHT", -7, 0)
    header.summary:SetText(opts.summary or "")
    UI.DragFrame(header, panel, "move", { onStop = function()
        -- Anchored by its top-left corner, so the saved place does not move
        -- when the strip changes length.
        local left, top = panel:GetLeft(), panel:GetTop()
        if not left or not top then return end
        if opts.place and opts.key then
            local entry = opts.place[opts.key] or {}
            entry.x, entry.y = math.floor(left + 0.5), math.floor(top + 0.5)
            opts.place[opts.key] = entry
        end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end })
    panel.header = header

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    body:SetHeight(opts.size or SLOT)
    UI.MakeContainer(ui, body, "row", { gap = 4 })
    body.kitParentContainer = nil
    panel.body = body
    for method, fn in pairs(UI.Container) do panel[method] = fn end
    panel.kitInner = body

    -- The strip is as long as its slots, and its header at least as long as
    -- its words.
    local function fit()
        local width = math.max(UI.NaturalWidth(body), math.ceil(UI.StringWidth(header.title) + UI.StringWidth(header.summary) + 30))
        body:SetWidth(math.max(1, UI.NaturalWidth(body)))
        header:SetWidth(width)
        panel:SetWidth(width)
    end
    panel.Fit = fit
    body:HookScript("OnShow", fit)
    local append = body.KitAppend
    body.KitAppend = function(b, child)
        append(b, child)
        fit()
        return child
    end
    function panel:SetTitle(text) header.title:SetText(text or ""); fit() end
    function panel:SetSummary(text) header.summary:SetText(text or ""); fit() end

    ui:Finish(panel, opts, function(p, t)
        header.plate:Flat(t.raisedBg, t.border)
        UI.TexColor(header.rail, UI.ToneColor(t, opts.rail) or t.accent, 0.9)
        UI.ApplyStyle(header.title, "fine", t)
        UI.ApplyStyle(header.summary, "fine", t)
        fit()
    end)
    if opts.hidden then panel:Hide() end
    return panel
end

-- One slot. `opts`: item (an item id: icon, quality edge and cooldown come
-- from it), icon (a texture, instead), key (a binding, shortened to fit the
-- corner), count (on a shaded strip), quest (a "!" in the top-left corner),
-- marker (a raid target, 1 to 8, in that corner instead), edge (a tone for
-- the ring instead of the quality),
-- onClick(slot, mouse), tooltip, size, secure (attributes for a
-- SecureActionButtonTemplate, set out of combat: { type = "item", item = ... }).
UI.Define("Slot", function(ui, parent, opts)
    opts = opts or {}
    local size = opts.size or SLOT
    local slot
    if opts.secure then
        local ok, made = pcall(CreateFrame, "Button", nil, parent, "SecureActionButtonTemplate")
        slot = ok and made or CreateFrame("Button", nil, parent)
    else
        slot = CreateFrame("Button", nil, parent)
    end
    slot:SetSize(size, size)
    slot.kitStretch = false
    slot.KitNaturalWidth = function() return size end
    slot.KitNaturalHeight = function() return size end
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- The plate and the ring of shadow only tint the world behind the art:
    -- enough that the edge holds over snow or sky.
    slot.shadow = slot:CreateTexture(nil, "BACKGROUND", nil, -3)
    slot.shadow:SetPoint("TOPLEFT", -2, 2)
    slot.shadow:SetPoint("BOTTOMRIGHT", 2, -2)
    slot.shadow:SetColorTexture(0, 0, 0, 0.25)
    slot.border = slot:CreateTexture(nil, "BACKGROUND", nil, -2)
    slot.border:SetPoint("TOPLEFT", -1, 1)
    slot.border:SetPoint("BOTTOMRIGHT", 1, -1)
    slot.backing = slot:CreateTexture(nil, "BACKGROUND", nil, -1)
    slot.backing:SetAllPoints()
    slot.backing:SetColorTexture(0.03, 0.04, 0.05, 0.3)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.highlight:SetAllPoints()
    slot.keyText = UI.NewText(slot)
    slot.keyText:SetPoint("TOPRIGHT", -2, -2)
    -- The count sits on a shaded strip, so it reads over a bright icon.
    slot.countStrip = slot:CreateTexture(nil, "OVERLAY", nil, -1)
    slot.countStrip:SetPoint("BOTTOMLEFT", slot.icon, "BOTTOMLEFT", 0, 0)
    slot.countStrip:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 0, 0)
    slot.countStrip:SetHeight(UI.Snap(slot, 12))
    slot.countStrip:SetColorTexture(0, 0, 0, 0.55)
    slot.countStrip:Hide()
    slot.countText = UI.NewText(slot)
    slot.countText:SetPoint("BOTTOMRIGHT", -2, 2)
    -- The top-left corner: a raid marker, else a quest mark.
    slot.marker = slot:CreateTexture(nil, "OVERLAY")
    slot.marker:SetSize(UI.Snap(slot, 14), UI.Snap(slot, 14))
    slot.marker:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
    slot.marker:Hide()
    slot.questMark = UI.NewText(slot)
    slot.questMark:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 2, -1)
    slot.questMark:SetText("!")
    slot.questMark:Hide()
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, slot, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints(slot.icon)
        slot.cooldown = cooldown
    end

    function slot:SetItem(id)
        self.kitItem = id
        local icon = id and itemIcon(id)
        if icon then self.icon:SetTexture(icon) end
        self.kitQuality = id and itemQuality(id)
        if id then self.kitLinks = { item = id } end
        self:UpdateCooldown()
        -- The builder sets opts.item before Finish gives the slot Repaint;
        -- Finish paints it then.
        if self.Repaint then self:Repaint() end
    end
    function slot:SetIcon(texture)
        self.icon:SetTexture(texture)
    end
    function slot:SetKey(key)
        self.keyText:SetText(UI.ShortKey(key) or "")
    end
    function slot:SetCount(count)
        local shown = count and count ~= 1
        self.countText:SetText(shown and tostring(count) or "")
        self.countStrip:SetShown(shown and true or false)
    end
    -- A quest item: a gold "!" in the top-left corner.
    function slot:SetQuest(on)
        self.kitQuest = on and true or false
        self.questMark:SetShown(self.kitQuest and not self.kitMarker)
    end
    -- A raid target marker (1 star to 8 skull) in the top-left corner, or nil.
    function slot:SetMarker(index)
        index = tonumber(index)
        self.kitMarker = (index and index >= 1 and index <= 8) and math.floor(index) or nil
        if self.kitMarker then
            pcall(self.marker.SetTexture, self.marker, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. self.kitMarker)
        end
        self.marker:SetShown(self.kitMarker ~= nil)
        self.questMark:SetShown(self.kitQuest and not self.kitMarker)
    end
    -- Not there to use: dimmed, with a danger ring.
    function slot:SetMissing(missing)
        self.kitMissing = missing and true or false
        self.icon:SetDesaturated(self.kitMissing)
        self:SetAlpha(self.kitMissing and 0.6 or 1)
        self:Repaint()
    end
    function slot:SetEdge(tone) opts.edge = tone; self:Repaint() end
    function slot:UpdateCooldown()
        if not self.cooldown or not self.kitItem then return end
        local start, duration, enabled = itemCooldown(self.kitItem)
        if start and duration and duration > 0 and enabled ~= 0 and enabled ~= false then
            pcall(self.cooldown.SetCooldown, self.cooldown, start, duration)
        else
            pcall(self.cooldown.Clear, self.cooldown)
        end
    end
    -- Secure attributes can only change out of combat.
    function slot:SetSecure(attributes)
        if not self.SetAttribute or (type(InCombatLockdown) == "function" and InCombatLockdown()) then return false end
        for key, value in pairs(attributes or {}) do self:SetAttribute(key, value) end
        return true
    end

    if opts.onClick then
        slot:HookScript("OnClick", function(s, mouse) opts.onClick(s, mouse) end)
    end
    slot.kitTooltipAlways = true
    if opts.icon then slot:SetIcon(opts.icon) end
    if opts.item then slot:SetItem(opts.item) end
    slot:SetKey(opts.key)
    slot:SetCount(opts.count)
    slot:SetQuest(opts.quest)
    slot:SetMarker(opts.marker)
    if opts.secure then slot:SetSecure(opts.secure) end
    ui:Finish(slot, opts, function(s, t)
        local edge
        if s.kitMissing then
            edge = t.danger
        elseif opts.edge then
            edge = UI.ToneColor(t, opts.edge)
        else
            edge = qualityColor(s.kitQuality) or t.border
        end
        UI.TexColor(s.border, edge)
        UI.TexColor(s.highlight, t.accentRaw, 0.22)
        UI.ApplyStyle(s.keyText, "key", t, { 1, 1, 1, 1 }, false)
        UI.ApplyStyle(s.countText, "number", t, { 1, 1, 1, 1 }, false)
        UI.ApplyStyle(s.questMark, "heading", t, t.quest, false)
        -- Slot text sits on art, not on a plate: always the hard shadow.
        for _, text in ipairs({ s.keyText, s.countText, s.questMark }) do
            text:SetShadowColor(0, 0, 0, 1)
            text:SetShadowOffset(1, -1)
        end
    end)
    UI.HookTooltip(slot)
    slot.kitLinks = opts.item and { item = opts.item } or nil
    return slot
end)
