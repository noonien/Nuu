local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- The Appearance section of an options window: theme, accent, opacity, text
-- size and motion. It keeps nothing: every change calls `onChange(look)`
-- with a new look, and the addon stores it and calls `ui:SetLook(look)`.

local CARD_W, CARD_H, PREVIEW_H, PER_ROW = 118, 72, 42, 4
local SWATCH = 26

local function copy(look)
    local out = {}
    for key, value in pairs(look or {}) do out[key] = value end
    return out
end

-- A theme card: a small window in that theme's colours, and its name.
local function themeCard(ui, parent, key, picker)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(CARD_W, CARD_H)
    card.kitStretch = false
    card.KitNaturalWidth = function() return CARD_W end
    card.KitNaturalHeight = function() return CARD_H end
    card.plate = UI.NewPlate(card)
    local preview = CreateFrame("Frame", nil, card)
    preview:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -6)
    preview:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
    preview:SetHeight(PREVIEW_H)
    local parts = {}
    parts.window = preview:CreateTexture(nil, "BACKGROUND")
    parts.window:SetAllPoints()
    parts.band = preview:CreateTexture(nil, "ARTWORK")
    parts.band:SetPoint("TOPLEFT")
    parts.band:SetPoint("TOPRIGHT")
    parts.band:SetHeight(9)
    parts.text = preview:CreateTexture(nil, "ARTWORK")
    parts.text:SetPoint("TOPLEFT", preview, "TOPLEFT", 6, -14)
    parts.text:SetSize(50, 3)
    parts.muted = preview:CreateTexture(nil, "ARTWORK")
    parts.muted:SetPoint("TOPLEFT", parts.text, "BOTTOMLEFT", 0, -3)
    parts.muted:SetSize(34, 3)
    local chip = CreateFrame("Frame", nil, preview)
    chip:SetPoint("TOPLEFT", parts.muted, "BOTTOMLEFT", 0, -4)
    chip:SetSize(26, 8)
    chip.plate = UI.NewPlate(chip)
    parts.edge = UI.NewPlate(preview, "OVERLAY")
    local name = UI.NewText(card)
    name:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 7, 6)
    name:SetText(UI.themes[key].name)
    card:SetScript("OnEnter", function(c) c.hover = true; c:Repaint() end)
    card:SetScript("OnLeave", function(c) c.hover = false; c:Repaint() end)
    card:SetScript("OnClick", function()
        UI.ClickSound()
        picker:Change("theme", key)
    end)
    UI.RegisterFocusable(ui, card, false)
    return ui:Finish(card, { tooltip = UI.themes[key].desc }, function(c, t)
        local on = picker.kitLook.theme == key
        local p = UI.Tokens({ theme = key, accent = picker.kitLook.accent })
        c.plate:Flat(t.surface, on and t.accent or (c.hover and t.accent65 or t.border))
        UI.TexColor(parts.window, p.window)
        UI.TexColor(parts.band, p.band)
        UI.TexColor(parts.text, p.text)
        UI.TexColor(parts.muted, p.muted)
        chip.plate:Flat(p.accentFill, p.accent)
        parts.edge:Flat(nil, p.hairline)
        UI.ApplyStyle(name, "body", t, on and "accent" or "text")
    end)
end

-- A swatch: a square of the colour, ringed while chosen.
local function swatch(ui, parent, entry, picker)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(SWATCH + 6, SWATCH + 6)
    button.kitStretch = false
    button.KitNaturalWidth = function() return SWATCH + 6 end
    button.KitNaturalHeight = function() return SWATCH + 6 end
    button.ring = UI.NewPlate(button)
    local fill = button:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", -4, 4)
    button:SetScript("OnEnter", function(b) b.hover = true; b:Repaint() end)
    button:SetScript("OnLeave", function(b) b.hover = false; b:Repaint() end)
    button:SetScript("OnClick", function()
        UI.ClickSound()
        picker:Change("accent", entry.value)
    end)
    UI.RegisterFocusable(ui, button, false)
    return ui:Finish(button, { tooltip = entry.name }, function(b, t)
        local look = picker.kitLook
        local on = look.accent == entry.value
        local color = entry.hex and UI.Color(entry.hex) or UI.Color(UI.themes[look.theme] and UI.themes[look.theme].accent or "#4dc9f0")
        UI.TexColor(fill, color)
        b.ring:Flat(nil, on and t.text or (b.hover and t.muted or nil))
    end)
end

UI.Define("LookPicker", function(ui, parent, look, onChange, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeContainer(ui, frame, "column", { gap = opts.gap or 18 })
    frame.kitLook = UI.ResolveLook(look)
    frame.kitLook.accent = (type(look) == "table") and look.accent or nil

    function frame:Change(key, value)
        self.kitLook[key] = value
        if onChange then onChange(copy(self.kitLook)) end
        self:Sync(self.kitLook)
    end

    -- Theme -----------------------------------------------------------------
    local themes = frame:Section("Theme", { hint = "every window repaints at once", gap = 8 })
    local row
    for index, key in ipairs(UI.themeOrder) do
        if (index - 1) % PER_ROW == 0 then row = themes:Row({ gap = 8 }) end
        row:KitAppend(themeCard(ui, row, key, frame))
    end
    local desc = themes:Text("", "label", { wrap = true })

    -- Accent ----------------------------------------------------------------
    local accents = frame:Section("Accent", { hint = "selection, focus, the call to action", reset = {
        stored = frame.kitLook.accent ~= nil, default = "the theme's own",
        onReset = function() frame:Change("accent", nil) end,
    } })
    local swatches = accents:Row({ gap = 4 })
    swatches:KitAppend(swatch(ui, swatches, { name = "The theme's own", value = nil }, frame))
    for _, entry in ipairs(UI.accents) do
        swatches:KitAppend(swatch(ui, swatches, { name = entry.name, hex = entry.hex, value = entry.hex }, frame))
    end
    local classToggle = accents:Toggle("Use my class colour", {
        value = frame.kitLook.accent == "class",
        onChange = function(on) frame:Change("accent", on and "class" or nil) end,
    })

    -- Windows ---------------------------------------------------------------
    local windows = frame:Section("Windows")
    local opacity = windows:Slider({
        label = "Background opacity", min = 40, max = 100, step = 5, format = "%d%%", width = 260,
        value = math.floor(frame.kitLook.opacity * 100 + 0.5),
        onChange = function(value) frame:Change("opacity", value / 100) end,
    })
    local size = windows:Select({
        label = "Text size", width = 160, value = frame.kitLook.textSize,
        options = {
            { value = "small", caption = "Small" },
            { value = "normal", caption = "Normal" },
            { value = "large", caption = "Large" },
        },
        onChange = function(value) frame:Change("textSize", value) end,
    })
    local motion = windows:Toggle("Less motion", {
        value = frame.kitLook.reduceMotion,
        tooltip = "Stills the animations that draw the eye.",
        onChange = function(on) frame:Change("reduceMotion", on) end,
    })

    -- Takes a look from elsewhere (another window changed it).
    function frame:Sync(newLook)
        local accent = type(newLook) == "table" and newLook.accent or nil
        self.kitLook = UI.ResolveLook(newLook)
        self.kitLook.accent = accent
        local theme = UI.themes[self.kitLook.theme]
        desc:SetText(theme and theme.desc or "")
        accents:SetStored(accent ~= nil, "the theme's own")
        classToggle:SetChecked(accent == "class")
        opacity:SetValue(math.floor(self.kitLook.opacity * 100 + 0.5))
        size:SetValue(self.kitLook.textSize)
        motion:SetChecked(self.kitLook.reduceMotion)
        ui:RepaintAll()
    end
    -- A look set elsewhere (in code, or by another picker) shows here too.
    ui:OnLook(function(l) frame.kitLook = UI.ResolveLook(l) end)
    local theme = UI.themes[frame.kitLook.theme]
    desc:SetText(theme and theme.desc or "")
    return ui:Finish(frame, opts)
end)
