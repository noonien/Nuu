local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto, Makers = UI.Proto, UI.Makers

-- Strips of icon slots, ported from OpenRoad's StripPanel and SlotChrome:
-- a header plate
-- the player drags, and a body with no plate at all, so only the slots
-- themselves sit on the world.

local HEADER, SLOT = 20, 36
local WHITE = { 1, 1, 1, 1 }

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

-- A quality's colour, worked out once: painting allocates nothing.
local qualityColors = {}
local function qualityColor(quality)
    if not quality then return nil end
    local cached = qualityColors[quality]
    if cached ~= nil then return cached or nil end
    local color
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and r then color = { r, g, b, 1 } end
    end
    if not color then
        local colors = _G.ITEM_QUALITY_COLORS
        local entry = colors and colors[quality]
        if entry and entry.r then color = { entry.r, entry.g, entry.b, 1 } end
    end
    qualityColors[quality] = color or false
    return color
end

local function itemCooldown(id)
    local fn = C_Container and C_Container.GetItemCooldown or _G.GetItemCooldown
    if type(fn) ~= "function" then return nil end
    local ok, start, duration, enabled = pcall(fn, id)
    if not ok then return nil end
    return start, duration, enabled
end

-- The strip --------------------------------------------------------------------------

-- `ui:StripPanel(spec)`: key, place (the addon's table), title, summary,
-- rail (a tone for the coloured edge of the header), point (where it goes
-- the first time), size (of a slot: the body's height), strata, hidden.
-- `strip:Slot(spec)` adds a slot; `strip:Clear()` takes them away (plain
-- slots back to their pool).

-- Anchored by its top-left corner, so the saved place does not move when
-- the strip changes length.
local function stripMoved(panel)
    local left, top = panel:GetLeft(), panel:GetTop()
    if not left or not top then return end
    local place, key = panel.kitPlace, panel.kitKey
    if place and key then
        local entry = place[key] or {}
        entry.x, entry.y = math.floor(left + 0.5), math.floor(top + 0.5)
        place[key] = entry
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local DRAG = { onStop = stripMoved }

UI.Define("StripPanel", {
    holds = true,
    Build = function(w)
        local ui = w.ui
        w.kitIsWindow = true
        w:SetClampedToScreen(true)
        w:SetMovable(true)
        w:SetSize(200, HEADER + 4 + SLOT)

        local header = CreateFrame("Frame", nil, w)
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
        header.summary = UI.NewText(header)
        header.summary:SetPoint("RIGHT", header, "RIGHT", -7, 0)
        UI.DragFrame(header, w, "move", DRAG)
        w.header = header

        local body = CreateFrame("Frame", nil, w)
        body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        UI.MakeStack(ui, body, "row", { gap = 4 })
        body.kitLayout = {}
        body.kitParent, body.kitDepth, body.kitWindow = w, 1, w
        w.body = body
        w.kitInner = body
    end,
    Init = function(w, spec)
        w.kitPlace, w.kitKey = spec.place, spec.key
        w.kitRail = spec.rail
        w.kitSlotSize = spec.size or SLOT
        w:SetFrameStrata(spec.strata or "MEDIUM")
        w.header.title:SetText(spec.title or "")
        w.header.summary:SetText(spec.summary or "")
        w:ClearAllPoints()
        local placed = spec.place and spec.key and spec.place[spec.key]
        if placed and placed.x then
            w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", placed.x, placed.y)
        else
            local point = spec.point or { "CENTER", UIParent, "CENTER", 0, -120 }
            w:SetPoint(point[1], point[2] or UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
        end
    end,
    methods = {
        SetTitle = function(self, text)
            self.header.title:SetText(text or "")
            self:Changed()
        end,
        SetSummary = function(self, text)
            self.header.summary:SetText(text or "")
            self:Changed()
        end,
        -- Fits it to its slots now, not on the next frame.
        Fit = function(self)
            self:Changed()
            UI.LayoutNow()
        end,
        -- The strip is as long as its slots, and its header at least as long
        -- as its words.
        Measure = function(self)
            local header = self.header
            local slots = self.body:NaturalWidth()
            local words = math.ceil(UI.StringWidth(header.title) + UI.StringWidth(header.summary) + 30)
            local tall = math.max(self.kitSlotSize, self.body:NaturalHeight())
            return math.max(slots, words), HEADER + 4 + tall
        end,
        Sized = function(self, width) self:StackLayout() end,
        -- The header across the strip, the body as long as its slots. The
        -- pass calls this too when the slots change and the strip does not
        -- (its title is the longer).
        StackLayout = function(self)
            local body = self.body
            local width = self.kitPW or self:GetWidth() or 0
            local height = self.kitPH or self:GetHeight() or 0
            local slots = math.max(1, body:NaturalWidth())
            local tall = math.max(1, height - HEADER - 4)
            self.header:SetWidth(math.max(1, width))
            if body.kitPW ~= slots or body.kitPH ~= tall then
                body:SetSize(slots, tall)
                body.kitPW, body.kitPH = slots, tall
            end
            UI.Invalidate(body)
        end,
        Paint = function(self, t)
            local header = self.header
            header.plate:Flat(t.raisedBg, t.border)
            UI.TexColor(header.rail, UI.Tone(t, self.kitRail) or t.accent, 0.9)
            UI.ApplyStyle(header.title, "fine", t)
            UI.ApplyStyle(header.summary, "fine", t)
            self:Changed()
        end,
    },
})

-- Placed on the screen, not in a parent: `ui:StripPanel(spec)`.
Proto.StripPanel = function(ui, spec)
    spec = spec or {}
    local w = UI.Make(ui, "StripPanel", UIParent, spec)
    w.kitFree = true
    UI.Fit(w)
    return w
end

-- One slot ---------------------------------------------------------------------------------

-- Spec: item (an item id: icon, quality edge and cooldown come from it),
-- icon (a texture, instead), key (a binding, shortened to fit the corner),
-- count (on a shaded strip), quest (a "!" in the top-left corner), marker (a
-- raid target, 1 to 8, in that corner instead), edge (a tone for the ring
-- instead of the quality), missing, onClick(slot, mouse), tooltip, size,
-- secure (attributes for a SecureActionButtonTemplate, set out of combat:
-- { type = "item", item = ... }).
--
-- A secure slot is its own type, SecureSlot, made from the template and
-- never pooled: a secure frame keeps its attributes and cannot be handed to
-- another use in combat. Plain slots come from the pool.

local function slotClicked(w, mouse)
    if w.kitOnClick then w.kitOnClick(w, mouse) end
end

-- Slot text sits on art, not on a plate: always the hard shadow.
local function hardShadow(text)
    text.kitShadowed = true
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
end

local function buildSlot(w)
    w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- The plate and the ring of shadow only tint the world behind the art:
    -- enough that the edge holds over snow or sky.
    w.shadow = w:CreateTexture(nil, "BACKGROUND", nil, -3)
    w.shadow:SetPoint("TOPLEFT", -2, 2)
    w.shadow:SetPoint("BOTTOMRIGHT", 2, -2)
    w.shadow:SetColorTexture(0, 0, 0, 0.25)
    w.border = w:CreateTexture(nil, "BACKGROUND", nil, -2)
    w.border:SetPoint("TOPLEFT", -1, 1)
    w.border:SetPoint("BOTTOMRIGHT", 1, -1)
    w.backing = w:CreateTexture(nil, "BACKGROUND", nil, -1)
    w.backing:SetAllPoints()
    w.backing:SetColorTexture(0.03, 0.04, 0.05, 0.3)
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetPoint("TOPLEFT", 2, -2)
    w.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    w.highlight = w:CreateTexture(nil, "HIGHLIGHT")
    w.highlight:SetAllPoints()
    w.keyText = UI.NewText(w)
    w.keyText:SetPoint("TOPRIGHT", -2, -2)
    -- The count sits on a shaded strip, so it reads over a bright icon.
    w.countStrip = w:CreateTexture(nil, "OVERLAY", nil, -1)
    w.countStrip:SetPoint("BOTTOMLEFT", w.icon, "BOTTOMLEFT", 0, 0)
    w.countStrip:SetPoint("BOTTOMRIGHT", w.icon, "BOTTOMRIGHT", 0, 0)
    w.countStrip:SetHeight(UI.Snap(w, 12))
    w.countStrip:SetColorTexture(0, 0, 0, 0.55)
    w.countStrip:Hide()
    w.countText = UI.NewText(w)
    w.countText:SetPoint("BOTTOMRIGHT", -2, 2)
    -- The top-left corner: a raid marker, else a quest mark.
    w.marker = w:CreateTexture(nil, "OVERLAY")
    w.marker:SetSize(UI.Snap(w, 14), UI.Snap(w, 14))
    w.marker:SetPoint("TOPLEFT", w.icon, "TOPLEFT", 0, 0)
    w.marker:Hide()
    w.questMark = UI.NewText(w)
    w.questMark:SetPoint("TOPLEFT", w.icon, "TOPLEFT", 2, -1)
    w.questMark:SetText("!")
    w.questMark:Hide()
    hardShadow(w.keyText)
    hardShadow(w.countText)
    hardShadow(w.questMark)
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, w, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints(w.icon)
        w.cooldown = cooldown
    end
    w:HookScript("OnClick", slotClicked)
end

local function initSlot(w, spec)
    local size = spec.size or SLOT
    w.kitSize = size
    w:SetSize(size, size)
    w.kitOnClick = spec.onClick
    w.kitEdge = spec.edge
    -- Whatever the last use left: no item, no icon, no marks, not missing.
    w.kitItem, w.kitQuality, w.kitQuest, w.kitMarker = nil, nil, false, nil
    w.icon:SetTexture(nil)
    w.kitMissing = false
    w.icon:SetDesaturated(false)
    w:SetAlpha(1)
    if w.cooldown then pcall(w.cooldown.Clear, w.cooldown) end
    if spec.icon then w:SetIcon(spec.icon) end
    if spec.item then w:SetItem(spec.item) end
    w:SetKey(spec.key)
    w:SetCount(spec.count)
    w:SetQuest(spec.quest)
    w:SetMarker(spec.marker)
    if spec.missing then w:SetMissing(true) end
    if spec.secure then w:SetSecure(spec.secure) end
end

local slotMethods = {
    SetItem = function(self, id)
        self.kitItem = id
        local icon = id and itemIcon(id)
        if icon then self.icon:SetTexture(icon) end
        self.kitQuality = id and itemQuality(id) or nil
        self.kitLinks = id and { item = id } or nil
        self:UpdateCooldown()
        self:PaintState(self.ui.tokens)
    end,
    GetItem = function(self) return self.kitItem end,
    SetIcon = function(self, texture) self.icon:SetTexture(texture) end,
    SetKey = function(self, key) self.keyText:SetText(UI.ShortKey(key) or "") end,
    SetCount = function(self, count)
        local shown = count and count ~= 1
        self.countText:SetText(shown and tostring(count) or "")
        self.countStrip:SetShown(shown and true or false)
    end,
    -- A quest item: a gold "!" in the top-left corner.
    SetQuest = function(self, on)
        self.kitQuest = on and true or false
        self.questMark:SetShown(self.kitQuest and not self.kitMarker)
    end,
    -- A raid target marker (1 star to 8 skull) in the top-left corner, or nil.
    SetMarker = function(self, index)
        index = tonumber(index)
        self.kitMarker = (index and index >= 1 and index <= 8) and math.floor(index) or nil
        if self.kitMarker then
            pcall(self.marker.SetTexture, self.marker, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. self.kitMarker)
        end
        self.marker:SetShown(self.kitMarker ~= nil)
        self.questMark:SetShown(self.kitQuest and not self.kitMarker)
    end,
    -- Not there to use: dimmed, with a danger ring.
    SetMissing = function(self, missing)
        self.kitMissing = missing and true or false
        self.icon:SetDesaturated(self.kitMissing)
        self:SetAlpha(self.kitMissing and 0.6 or 1)
        self:PaintState(self.ui.tokens)
    end,
    SetEdge = function(self, tone)
        self.kitEdge = tone
        self:PaintState(self.ui.tokens)
    end,
    UpdateCooldown = function(self)
        if not self.cooldown or not self.kitItem then return end
        local start, duration, enabled = itemCooldown(self.kitItem)
        if start and duration and duration > 0 and enabled ~= 0 and enabled ~= false then
            pcall(self.cooldown.SetCooldown, self.cooldown, start, duration)
        else
            pcall(self.cooldown.Clear, self.cooldown)
        end
    end,
    -- Secure attributes can only change out of combat.
    SetSecure = function(self, attributes)
        if not self.SetAttribute or (type(InCombatLockdown) == "function" and InCombatLockdown()) then return false end
        for key, value in pairs(attributes or {}) do self:SetAttribute(key, value) end
        return true
    end,
    IsSecure = function(self) return self.kitSecure and true or false end,
    Measure = function(self) return self.kitSize, self.kitSize end,
    Paint = function(self, t)
        UI.ApplyStyle(self.keyText, "key", t, WHITE)
        UI.ApplyStyle(self.countText, "number", t, WHITE)
        UI.ApplyStyle(self.questMark, "heading", t, t.quest)
        self:PaintState(t)
    end,
    -- The ring: danger while missing, else the edge's tone, else the item's
    -- quality.
    PaintState = function(self, t)
        local edge
        if self.kitMissing then
            edge = t.danger
        elseif self.kitEdge then
            edge = UI.Tone(t, self.kitEdge) or UI.Colour(t, self.kitEdge)
        else
            edge = qualityColor(self.kitQuality) or t.border
        end
        UI.TexColor(self.border, edge)
        UI.TexColor(self.highlight, t.accentRaw, 0.22)
    end,
}

local function slotDef(extra)
    local def = { kind = "Button", stretch = false, tooltip = true, Build = buildSlot, Init = initSlot, methods = slotMethods }
    for key, value in pairs(extra or {}) do def[key] = value end
    return def
end

UI.Define("Slot", slotDef())

-- The template may be missing or refused: then a plain button, still never
-- pooled.
UI.Define("SecureSlot", slotDef({
    pool = false,
    Create = function(ui, parent, spec)
        local ok, made = pcall(CreateFrame, "Button", nil, parent, "SecureActionButtonTemplate")
        local w = ok and made or CreateFrame("Button", nil, parent)
        w.kitSecure = true
        return w
    end,
}))

-- `Slot` makes a SecureSlot when the spec has `secure`.
local plainPlaced, plainMaker = Proto.Slot, Makers.Slot
local securePlaced, secureMaker = Proto.SecureSlot, Makers.SecureSlot
Proto.Slot = function(ui, parent, spec)
    if type(spec) == "table" and spec.secure then return securePlaced(ui, parent, spec) end
    return plainPlaced(ui, parent, spec)
end
Makers.Slot = function(self, spec)
    if type(spec) == "table" and spec.secure then return secureMaker(self, spec) end
    return plainMaker(self, spec)
end
