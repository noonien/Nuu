local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI1 = Kit.UI1 or {}
local UI = Kit.UI1
local types = UI.types

-- The Appearance section of an options window: theme, accent, opacity, text
-- size and motion, as in UI/Theme/LookPicker.lua on shared methods and
-- pooling. It keeps nothing: every change calls `onChange(look)` with a new
-- look, and the addon stores it and calls `ui:SetLook(look)`.
--
--   section:LookPicker{ look = db.look, onChange = function(look) end }
--
-- Spec: look, onChange(look), gap (between its sections, 18).

local CARD_W, CARD_H, PREVIEW_H, PER_ROW = 118, 72, 42, 4
local SWATCH = 26

local TEXT_SIZES = {
    { value = "small", caption = "Small" },
    { value = "normal", caption = "Normal" },
    { value = "large", caption = "Large" },
}

local function copy(look)
    local out = {}
    for key, value in pairs(look or {}) do out[key] = value end
    return out
end

-- A theme's colours with an accent, for its card: worked out once for each
-- pair, not on every paint.
local previews = {}
local function previewTokens(theme, accent)
    local key = theme .. "|" .. tostring(accent)
    local p = previews[key]
    if not p then
        p = UI.Tokens({ theme = theme, accent = accent })
        previews[key] = p
    end
    return p
end

-- Theme cards --------------------------------------------------------------------------

-- A small window in that theme's colours, and its name. Hover and selection
-- repaint colours only; the preview is painted with the look (and again when
-- the accent changes). Spec: [1] the theme's key, picker.
UI.Define("LookCard", UI.ClickableType({
    stretch = false,
    Build = function(w)
        w.plate = UI.NewPlate(w)
        local preview = CreateFrame("Frame", nil, w)
        preview:SetPoint("TOPLEFT", w, "TOPLEFT", 6, -6)
        preview:SetPoint("TOPRIGHT", w, "TOPRIGHT", -6, -6)
        preview:SetHeight(PREVIEW_H)
        w.window = preview:CreateTexture(nil, "BACKGROUND")
        w.window:SetAllPoints()
        w.band = preview:CreateTexture(nil, "ARTWORK")
        w.band:SetPoint("TOPLEFT")
        w.band:SetPoint("TOPRIGHT")
        w.band:SetHeight(9)
        w.line = preview:CreateTexture(nil, "ARTWORK")
        w.line:SetPoint("TOPLEFT", preview, "TOPLEFT", 6, -14)
        w.line:SetSize(50, 3)
        w.mutedLine = preview:CreateTexture(nil, "ARTWORK")
        w.mutedLine:SetPoint("TOPLEFT", w.line, "BOTTOMLEFT", 0, -3)
        w.mutedLine:SetSize(34, 3)
        local chip = CreateFrame("Frame", nil, preview)
        chip:SetPoint("TOPLEFT", w.mutedLine, "BOTTOMLEFT", 0, -4)
        chip:SetSize(26, 8)
        w.chip = UI.NewPlate(chip)
        w.edge = UI.NewPlate(preview, "OVERLAY")
        w.name = UI.NewText(w)
        w.name:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 7, 6)
        UI.WireButton(w)
    end,
    Init = function(w, spec)
        w:SetSize(CARD_W, CARD_H)
        w.kitKey, w.kitPicker = spec[1], spec.picker
        local theme = UI.themes[w.kitKey]
        w.name:SetText(theme and theme.name or tostring(w.kitKey))
        w.tooltip = theme and theme.desc
        UI.InitClickable(w, spec)
    end,
    methods = {
        Activate = function(self) self.kitPicker:Change("theme", self.kitKey) end,
        Measure = function() return CARD_W, CARD_H end,
        Paint = function(self, t)
            local p = previewTokens(self.kitKey, self.kitPicker.kitLook.accent)
            UI.TexColor(self.window, p.window)
            UI.TexColor(self.band, p.band)
            UI.TexColor(self.line, p.text)
            UI.TexColor(self.mutedLine, p.muted)
            self.chip:Flat(p.accentFill, p.accent)
            self.edge:Flat(nil, p.hairline)
            UI.ApplyStyle(self.name, "body", t, nil, true)
            self:PaintState(t)
        end,
        PaintState = function(self, t)
            local on = self.kitPicker.kitLook.theme == self.kitKey
            self.plate:Flat(t.surface, on and t.accent or (self.hover and t.accent65 or t.border))
            UI.TextColor(self.name, on and t.accent or t.text)
        end,
    },
}))

-- Swatches ---------------------------------------------------------------------------------

-- A square of the colour, ringed while chosen. Spec: value (a "#rrggbb", or
-- nil for the theme's own), name (its tooltip), picker.
UI.Define("LookSwatch", UI.ClickableType({
    stretch = false,
    Build = function(w)
        w.ring = UI.NewPlate(w)
        w.fill = w:CreateTexture(nil, "ARTWORK")
        w.fill:SetPoint("TOPLEFT", 4, -4)
        w.fill:SetPoint("BOTTOMRIGHT", -4, 4)
        UI.WireButton(w)
    end,
    Init = function(w, spec)
        w:SetSize(SWATCH + 6, SWATCH + 6)
        w.kitValue, w.kitPicker = spec.value, spec.picker
        w.tooltip = spec.name
        UI.InitClickable(w, spec)
    end,
    methods = {
        Activate = function(self) self.kitPicker:Change("accent", self.kitValue) end,
        Measure = function() return SWATCH + 6, SWATCH + 6 end,
        Paint = function(self, t) self:PaintState(t) end,
        -- The theme's own follows the theme picked; colours only.
        PaintState = function(self, t)
            local look = self.kitPicker.kitLook
            local color = self.kitValue and UI.Colour(t, self.kitValue)
            if not color then
                local theme = UI.themes[look.theme]
                color = UI.Colour(t, theme and theme.accent or "#4dc9f0")
            end
            UI.TexColor(self.fill, color)
            local on = look.accent == self.kitValue
            self.ring:Flat(nil, on and t.text or (self.hover and t.muted or nil))
        end,
    },
}))

-- The picker --------------------------------------------------------------------------------

-- The controls call back with themselves; each knows its picker.
local function classChanged(on, toggle) toggle.kitPicker:Change("accent", on and "class" or nil) end
local function opacityChanged(value, slider) slider.kitPicker:Change("opacity", value / 100) end
local function sizeChanged(value, select) select.kitPicker:Change("textSize", value) end
local function motionChanged(on, toggle) toggle.kitPicker:Change("reduceMotion", on and true or false) end

-- A control's value from code: silent.
local function setValue(w, value)
    if not w then return end
    if w.SetValue then w:SetValue(value) elseif w.SetChecked then w:SetChecked(value) end
end

-- A control from a file not loaded yet is left out (the parts of the kit
-- are ported one by one).
local function control(stack, name, spec, picker)
    if not types[name] then return nil end
    local w = stack[name](stack, spec)
    w.kitPicker = picker
    return w
end

-- A look set elsewhere (in code, or by another picker) shows in every
-- picker of that UI. One listener per UI, the same function for all.
local function lookChanged(look, ui)
    for w in pairs(ui.widgets) do
        if w.kitType == "LookPicker" and not w.kitPooled then w:Sync(look) end
    end
end

local function listen(ui)
    if ui.kitLookPickerListening then return end
    ui.kitLookPickerListening = true
    ui:OnLook(lookChanged)
end

-- The accent section's reset; the section knows its picker.
local function pickerReset(section) section.kitPicker:Change("accent", nil) end

UI.Define("LookPicker", {
    stack = true, fills = false,
    Build = function(w)
        types.Column.Build(w)
        w.cards, w.swatches = {}, {}
    end,
    Init = function(w, spec)
        UI.SetStack(w, "column", { gap = spec.gap or 18 })
        local look = spec.look
        w.kitOnChange = spec.onChange
        w.kitLook = UI.ResolveLook(look)
        w.kitLook.accent = type(look) == "table" and look.accent or nil
        w.kitPaintedAccent = w.kitLook.accent
        local cards, swatches = w.cards, w.swatches
        for index = #cards, 1, -1 do cards[index] = nil end
        for index = #swatches, 1, -1 do swatches[index] = nil end
        listen(w.ui)

        -- Theme
        local themes = w:Section{ "Theme", hint = "every window repaints at once", gap = 8 }
        local row
        for index, key in ipairs(UI.themeOrder) do
            if (index - 1) % PER_ROW == 0 then row = themes:Row{ gap = 8 } end
            cards[#cards + 1] = row:LookCard{ key, picker = w }
        end
        w.desc = themes:Text{ "", style = "label", wrap = true }

        -- Accent
        local accents = w:Section{ "Accent", hint = "selection, focus, the call to action", reset = {
            stored = w.kitLook.accent ~= nil, default = "the theme's own", onReset = pickerReset,
        } }
        accents.kitPicker = w
        w.accents = accents
        local strip = accents:Row{ gap = 4 }
        swatches[1] = strip:LookSwatch{ picker = w, value = nil, name = "The theme's own" }
        for _, entry in ipairs(UI.accents) do
            swatches[#swatches + 1] = strip:LookSwatch{ picker = w, value = entry.hex, name = entry.name }
        end
        w.classToggle = control(accents, "Toggle", { "Use my class colour",
            value = w.kitLook.accent == "class", onChange = classChanged }, w)

        -- Windows
        local windows = w:Section{ "Windows" }
        w.opacity = control(windows, "Slider", {
            label = "Background opacity", min = 40, max = 100, step = 5, format = "%d%%", width = 260,
            value = math.floor(w.kitLook.opacity * 100 + 0.5), onChange = opacityChanged,
        }, w)
        w.size = control(windows, "Select", {
            label = "Text size", width = 160, value = w.kitLook.textSize, options = TEXT_SIZES, onChange = sizeChanged,
        }, w)
        w.motion = control(windows, "Toggle", { "Less motion", value = w.kitLook.reduceMotion,
            tooltip = "Stills the animations that draw the eye.", onChange = motionChanged }, w)

        local theme = UI.themes[w.kitLook.theme]
        w.desc:SetText(theme and theme.desc or "")
    end,
    Release = function(w)
        w.kitOnChange = nil
        w.desc, w.accents, w.classToggle, w.opacity, w.size, w.motion = nil, nil, nil, nil, nil, nil
    end,
    methods = {
        -- A change by the player: reported, then shown.
        Change = function(self, key, value)
            self.kitLook[key] = value
            if self.kitOnChange then self.kitOnChange(copy(self.kitLook)) end
            self:Sync(self.kitLook)
        end,
        GetLook = function(self) return copy(self.kitLook) end,
        -- Takes a look from elsewhere (another window changed it). Selection
        -- repaints colours only; a new accent repaints the cards' previews.
        Sync = function(self, newLook)
            local accent = type(newLook) == "table" and newLook.accent or nil
            local accentChanged = accent ~= self.kitPaintedAccent
            self.kitPaintedAccent = accent
            self.kitLook = UI.ResolveLook(newLook)
            self.kitLook.accent = accent
            local theme = UI.themes[self.kitLook.theme]
            if self.desc then self.desc:SetText(theme and theme.desc or "") end
            if self.accents then self.accents:SetStored(accent ~= nil, "the theme's own") end
            setValue(self.classToggle, accent == "class")
            setValue(self.opacity, math.floor(self.kitLook.opacity * 100 + 0.5))
            setValue(self.size, self.kitLook.textSize)
            setValue(self.motion, self.kitLook.reduceMotion)
            local t = self.ui.tokens
            for _, card in ipairs(self.cards) do
                if accentChanged then card:Paint(t) else card:PaintState(t) end
            end
            for _, swatch in ipairs(self.swatches) do swatch:PaintState(t) end
        end,
    },
})
