local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local types = UI.types

-- Buttons, with tones and styles, the theme's art plates, and repainting.

local BUTTON_HEIGHT, ART_CORNER = 24, 5
local WHITE = { 1, 1, 1, 1 }
local DIM = { 0.55, 0.55, 0.55, 1 }

local function stateOf(button)
    if not button:IsEnabled() then return "disabled" end
    if button.kitActive then return "active" end
    if button.hover then return "hover" end
    return "rest"
end
UI.ButtonState = stateOf

-- Everything a clickable widget shares ----------------------------------------------------

-- Hover repaints the colours; the press nudges `w.kitPressParts` a pixel;
-- a click takes the focus from a field, ticks, and calls `w:Activate()`.
local function pressParts(w, dx, dy)
    for _, part in ipairs(w.kitPressParts) do
        if part.Nudge then part:Nudge(dx, dy) else UI.ShiftPoints(part, dx, dy) end
    end
end

local function release(w)
    if not w.kitPressed then return end
    w.kitPressed = false
    pressParts(w, -1, 1)
end

local function onEnter(w)
    w.hover = true
    w:PaintState(w.ui.tokens)
    if w.kitTooltipHooked then UI.TipEnter(w) end
end

local function onLeave(w)
    w.hover = false
    w:PaintState(w.ui.tokens)
    if w.kitTooltipHooked then UI.TipLeave(w) end
end

local holdStart, holdStop

local function onMouseDown(w, mouse)
    if mouse ~= "LeftButton" or w.kitPressed or not w:IsEnabled() then return end
    w.kitPressed = true
    pressParts(w, 1, -1)
    if w.kitHold then holdStart(w, mouse) end
end

local function onMouseUp(w)
    release(w)
    if w.kitHeldAt then holdStop(w) end
end

local function onHide(w)
    release(w)
    if w.kitHeldAt then holdStop(w) end
    if w.kitOnHide then w.kitOnHide(w) end
end

local function preClick(w, mouse)
    if mouse == "RightButton" then return end
    UI.ClearTypingFocus(w)
    UI.ClickSound()
end

local function onClick(w, mouse)
    if mouse == "RightButton" or w.kitHold or not w:IsEnabled() then return end
    w:Activate()
end

local function enabledChanged(w)
    if w.ui then w:PaintState(w.ui.tokens) end
end

-- Wires a clickable widget's scripts; from its type's Build. The kit owns
-- the frame, so each event has one script doing all its parts (press, hold,
-- tooltip), not a hook per part. `w.kitOnHide(w)` adds to the hide.
function UI.WireButton(w)
    w:RegisterForClicks("LeftButtonUp")
    w:SetScript("OnEnter", onEnter)
    w:SetScript("OnLeave", onLeave)
    w:SetScript("OnMouseDown", onMouseDown)
    w:SetScript("OnMouseUp", onMouseUp)
    w:SetScript("OnHide", onHide)
    w:SetScript("PreClick", preClick)
    w:SetScript("OnClick", onClick)
    pcall(w.SetScript, w, "OnEnable", enabledChanged)
    pcall(w.SetScript, w, "OnDisable", enabledChanged)
    -- Its tooltip comes from its own OnEnter and OnLeave.
    w.kitTipInline = true
    w.kitPressParts = w.kitPressParts or {}
end

-- The methods every clickable widget has.
UI.Clickable = {
    -- Disabled, with the reason its tooltip gives.
    SetEnabled = function(self, enabled, reason)
        self.kitReason = (not enabled) and reason or nil
        if enabled then
            self:Enable()
        else
            self:Disable()
            release(self)
        end
        self:PaintState(self.ui.tokens)
    end,
    SetOnClick = function(self, fn) self.kitClick = fn end,
    Activate = function(self) if self.kitClick then self.kitClick(self) end end,
}

-- The common part of a clickable type's Init: enabled, click, reason.
function UI.InitClickable(w, spec)
    w.kitClick = spec.onClick
    w.kitPressed = false
    if spec.disabled then
        w:Disable()
        if type(spec.disabled) == "string" then w.kitReason = spec.disabled end
    else
        w:Enable()
    end
end

local function clickableType(def)
    def.kind = def.kind or "Button"
    def.focusable = def.focusable == nil and true or def.focusable
    def.tooltip = true
    local methods = {}
    for key, fn in pairs(UI.Clickable) do methods[key] = fn end
    for key, fn in pairs(def.methods or {}) do methods[key] = fn end
    def.methods = methods
    return def
end
UI.ClickableType = clickableType

-- A clickable type made from another: the base's Build and methods, with
-- `def`'s own on top (ConfirmButton on Button, ResetButton on Link).
local function extend(base, def)
    def.Build = def.Build or base.Build
    local methods = {}
    for key, fn in pairs(base.methods) do methods[key] = fn end
    for key, fn in pairs(def.methods or {}) do methods[key] = fn end
    def.methods = methods
    return clickableType(def)
end

-- Buttons --------------------------------------------------------------------------------

-- Whether a button of this tone and style wears the theme's plate art.
local function usesArt(t, tone, style)
    if not t.art then return false end
    if tone ~= nil and tone ~= "neutral" and tone ~= "accent" then return false end
    return style == nil or style == "plate" or style == "solid"
end

-- Hold to act: the button fills while held and acts when full.
local function holdTick(w)
    local progress = (UI.Now() - (w.kitHeldAt or UI.Now())) / w.kitHold
    if progress >= 1 then
        w.kitHeldAt = nil
        w:SetScript("OnUpdate", nil)
        w.holdFill:Hide()
        w:Activate()
        return
    end
    w.holdFill:SetWidth(math.max(0.01, (w:GetWidth() or 0) * progress))
end

function holdStart(w, mouse)
    if not w.kitHold or mouse ~= "LeftButton" or not w:IsEnabled() then return end
    w.kitHeldAt = UI.Now()
    w.holdFill:SetWidth(0.01)
    w.holdFill:Show()
    w:SetScript("OnUpdate", holdTick)
end

function holdStop(w)
    if not w.kitHeldAt then return end
    w.kitHeldAt = nil
    w:SetScript("OnUpdate", nil)
    w.holdFill:Hide()
end

-- The caption held inside the button when the layout makes it narrower.
local function clip(w)
    local label = w.label
    label:SetWidth(0)
    local width = w.kitPW or w:GetWidth() or 0
    local room = width - (w.kitTextReserve or 8)
    if room > 0 and UI.StringWidth(label) > room then label:SetWidth(room) end
end

-- A button's or a link's caption: answers whether it changed.
local function setCaption(self, text)
    text = text == nil and "" or tostring(text)
    if text == self.kitCaption then return false end
    self.kitCaption = text
    self.label:SetText(text)
    return true
end

local function getCaption(self) return self.kitCaption end

-- A button's own mark beside its caption: an icon (a texture, in its own
-- colours or tinted), or a line glyph; and a chevron after the caption for
-- a button that opens a menu. With `iconAbove` the icon sits over the
-- caption, for a tall button. Placed whenever the size or caption changes.
local ICON_GAP, CHEVRON = 6, 8

local function markWidth(w)
    if w.kitOwnLabel then return 0 end
    if w.kitIconAbove then return 0 end
    if w.icon and w.icon:IsShown() then return w.kitIconSize + ICON_GAP end
    if w.markGlyph then return w.kitIconSize + ICON_GAP end
    return 0
end

-- `kitOwnLabel`: a type built on the button that places its caption itself
-- (a select's box, a disclosure) is left alone.
local function placeContent(w)
    -- A plain button keeps the centred caption its Build gave it: no calls.
    if w.kitOwnLabel or not w.kitMarked then return end
    local label = w.label
    local width = w.kitPW or w:GetWidth() or 0
    local hasIcon = w.icon and w.icon:IsShown()
    if w.kitIconAbove and (hasIcon or w.markGlyph) then
        local size = w.kitIconSize
        local textHeight = math.ceil(label:GetStringHeight() or 12)
        local total = size + 3 + textHeight
        local top = UI.Snap(w, ((w.kitPH or w:GetHeight() or total) - total) / 2)
        if hasIcon then
            w.icon:ClearAllPoints()
            w.icon:SetPoint("TOP", w, "TOP", 0, -top)
        end
        if w.markGlyph then w.markGlyph:Offset(0, (w.kitPH or 0) / 2 - top - size / 2) end
        label:ClearAllPoints()
        label:SetPoint("TOP", w, "TOP", 0, -(top + size + 3))
        return
    end
    local mark, chevron = markWidth(w), w.chevron and (ICON_GAP + CHEVRON) or 0
    local total = mark + math.ceil(UI.StringWidth(label)) + chevron
    local x = UI.Snap(w, math.max(4, (width - total) / 2))
    if hasIcon then
        w.icon:ClearAllPoints()
        w.icon:SetPoint("LEFT", w, "LEFT", x, 0)
    end
    if w.markGlyph then w.markGlyph:Offset(x + w.kitIconSize / 2 - width / 2, 0) end
    label:ClearAllPoints()
    if mark == 0 and chevron == 0 then
        label:SetPoint("CENTER", w, "CENTER", 0, 0)
    else
        label:SetPoint("LEFT", w, "LEFT", x + mark, 0)
    end
    if w.chevron then w.chevron:Offset(x + total - CHEVRON / 2 - width / 2, 0) end
end

-- The spec's mark and chevron: made the first time a spec asks, shown or
-- hidden on every Init.
local function initMarks(w, spec)
    if w.kitOwnLabel then return end
    w.kitIconSize = spec.iconSize or 14
    w.kitIconAbove = spec.iconAbove and true or false
    w.kitIconColor = spec.iconColor
    local wasMarked = w.kitMarked
    if spec.icon then
        if not w.icon then w.icon = w:CreateTexture(nil, "ARTWORK") end
        w.icon:SetSize(w.kitIconSize, w.kitIconSize)
        local loaded = w.icon:SetTexture(spec.icon) ~= false and w.icon:GetTexture() ~= nil
        local cropped = type(spec.icon) == "number" or tostring(spec.icon):lower():gsub("\\", "/"):find("^interface/icons/") ~= nil
        w.icon:SetTexCoord(cropped and 0.08 or 0, cropped and 0.92 or 1, cropped and 0.08 or 0, cropped and 0.92 or 1)
        w.icon:SetShown(loaded)
    elseif w.icon and w.kitMarked then
        w.icon:Hide()
    end
    if w.kitGlyphSet and w.kitMarked then for _, glyph in pairs(w.kitGlyphSet) do glyph:SetShown(false) end end
    w.markGlyph, w.chevron = nil, nil
    local function glyph(kind, size)
        w.kitGlyphSet = w.kitGlyphSet or {}
        local key = kind .. ":" .. size
        local made = w.kitGlyphSet[key]
        if not made then
            made = UI.NewGlyph(w, kind, size, 1.6)
            w.kitGlyphSet[key] = made
        end
        made:Offset(0, 0)
        made:SetShown(true)
        return made
    end
    if spec.glyph and not (w.icon and w.icon:IsShown()) then w.markGlyph = glyph(spec.glyph, w.kitIconSize) end
    if spec.chevron then w.chevron = glyph("down", CHEVRON) end
    local hasIcon = w.icon and w.icon:IsShown()
    w.kitMarked = (hasIcon or w.markGlyph or w.chevron) and true or false
    if not w.kitMarked then
        -- Plain, as most buttons are: the caption centred once more only
        -- when the last use had marks.
        if wasMarked then
            w.label:ClearAllPoints()
            w.label:SetPoint("CENTER", w, "CENTER", 0, 0)
        end
        w.kitPlainParts = w.kitPlainParts or { w.label }
        w.kitPressParts = w.kitPlainParts
        w.kitTextReserve = nil
        return
    end
    local parts = { w.label }
    if hasIcon then parts[#parts + 1] = w.icon end
    if w.markGlyph then parts[#parts + 1] = w.markGlyph end
    if w.chevron then parts[#parts + 1] = w.chevron end
    w.kitPressParts = parts
    w.kitTextReserve = 8 + markWidth(w) + (w.chevron and (ICON_GAP + CHEVRON) or 0)
end

local buttonMethods = {
    SetText = function(self, text)
        if not setCaption(self, text) then return end
        clip(self)
        placeContent(self)
        self:Changed()
    end,
    GetText = getCaption,
    -- Another icon (a texture), in place of the one the spec gave.
    SetIcon = function(self, icon)
        if not self.icon then return end
        local loaded = icon ~= nil and self.icon:SetTexture(icon) ~= false and self.icon:GetTexture() ~= nil
        self.icon:SetShown(loaded and true or false)
        placeContent(self)
        self:PaintState(self.ui.tokens)
    end,
    SetActive = function(self, active)
        self.kitActive = active and true or false
        self:PaintState(self.ui.tokens)
    end,
    IsActive = function(self) return self.kitActive end,
    SetTone = function(self, tone, style)
        self.kitTone, self.kitStyle = tone, style
        self:PaintState(self.ui.tokens)
    end,
    Measure = function(self)
        local width = self.kitFixedWidth
        local extra = markWidth(self) + (self.chevron and (ICON_GAP + CHEVRON) or 0)
        if not width then width = math.max(BUTTON_HEIGHT, math.ceil(UI.StringWidth(self.label) + (self.kitTextPad or 20) + extra)) end
        local height = self.kitHeight
        if self.kitIconAbove and ((self.icon and self.icon:IsShown()) or self.markGlyph) then
            height = math.max(height, self.kitIconSize + 3 + math.ceil(self.label:GetStringHeight() or 12) + 12)
            if not self.kitFixedWidth then
                width = math.max(width - extra, math.ceil(UI.StringWidth(self.label)) + 16, self.kitIconSize + 16)
            end
        end
        return width, height
    end,
    Sized = function(self)
        clip(self)
        placeContent(self)
    end,
    Paint = function(self, t)
        UI.ApplyStyle(self.label, self.kitTextStyle or "body", t, nil, true)
        self:PaintState(t)
        self:Changed()
    end,
    PaintState = function(self, t)
        local state = stateOf(self)
        local tone, style = self.kitTone, self.kitStyle
        local fill, edge, ink = UI.ButtonColorsOf(t, tone, style, state)
        local drew = false
        if usesArt(t, tone, style) then
            local spec = tone == "accent" and t.art.platePrimary or t.art.plate
            drew = self.plate:Art(spec, ART_CORNER, state == "disabled" and DIM or WHITE)
            if drew then
                if state == "disabled" then
                    ink = t.muted45
                elseif tone == "accent" then
                    ink = t.onFill
                else
                    ink = state == "active" and t.accent or t.text
                end
            end
        end
        if not drew then self.plate:Flat(fill, edge) end
        UI.TexColor(self.shine, WHITE, drew and state == "hover" and 0.08 or 0)
        UI.TextColor(self.label, ink)
        if self.markGlyph then self.markGlyph:SetColor(UI.Colour(t, self.kitIconColor) or ink) end
        if self.chevron then self.chevron:SetColor(state == "disabled" and ink or t.muted) end
        if self.icon and self.icon:IsShown() then
            local tint = self.kitIconColor and UI.Colour(t, self.kitIconColor) or WHITE
            self.icon:SetVertexColor(tint[1], tint[2], tint[3], state == "disabled" and 0.45 or 1)
        end
        if self.holdFill and self.kitHold then
            UI.TexColor(self.holdFill, UI.Faded(t, UI.Tone(t, tone) or t.accentRaw, 0.35))
        end
    end,
}

-- Spec: [1] the caption, tone (accent, neutral, success, danger, warning,
-- quest, or a colour), style (solid, soft, outline, ghost; neutral buttons
-- are "plate"), width (else as wide as the caption), height, tooltip,
-- onClick(button), disabled (or a reason string), active, hold (seconds to
-- hold instead of a click), textStyle, stretch; icon (a texture before the
-- caption, in its own colours unless iconColor tints it), glyph (a line
-- glyph there instead: "undo", "play"), iconSize (14), iconAbove (the icon
-- over the caption, for a tall button), chevron (a down mark after the
-- caption, for a button that opens a menu).
local function buildButton(w)
    w.plate = UI.NewPlate(w)
    w.shine = w:CreateTexture(nil, "BORDER", nil, 7)
    w.shine:SetAllPoints()
    w.label = UI.NewText(w)
    w.label:SetPoint("CENTER", w, "CENTER", 0, 0)
    w.kitPressParts = { w.label }
    UI.WireButton(w)
end

local function initButton(w, spec)
    w.kitTone, w.kitStyle, w.kitTextStyle = spec.tone, spec.style, spec.textStyle
    w.kitActive = spec.active and true or false
    w.kitHeight = spec.height or BUTTON_HEIGHT
    w.kitFixedWidth = spec.width
    w.kitHold = spec.hold
    if spec.hold and not w.holdFill then
        w.holdFill = w:CreateTexture(nil, "BORDER", nil, 6)
        w.holdFill:SetPoint("TOPLEFT")
        w.holdFill:SetPoint("BOTTOMLEFT")
        w.holdFill:SetWidth(0.01)
    end
    if w.holdFill then w.holdFill:Hide() end
    w.kitCaption = nil
    initMarks(w, spec)
    UI.InitClickable(w, spec)
    w:SetText(spec[1])
    placeContent(w)
end

UI.Define("Button", clickableType({
    stretch = false,
    Build = buildButton,
    Init = initButton,
    methods = buttonMethods,
}))

-- Two clicks for what cannot be taken back: the first arms it and says so, a
-- second within four seconds acts. Left alone, or hidden, it disarms.
-- Spec: a button's, with onConfirm (else onClick) and confirmText.
local CONFIRM_SECONDS = 4

local function disarm(w)
    w.kitArmedAt = nil
    w:SetScript("OnUpdate", nil)
    w:SetTone(w.kitRestTone, w.kitRestStyle)
    w:SetText(w.kitRestCaption)
end

-- Hidden while armed, it disarms.
local function confirmHidden(w) if w.kitArmedAt then disarm(w) end end

local function confirmTick(w)
    if w.kitArmedAt and UI.Now() - w.kitArmedAt >= CONFIRM_SECONDS then disarm(w) end
end

UI.Define("ConfirmButton", extend(types.Button, {
    stretch = false,
    Init = function(w, spec)
        initButton(w, spec)
        w.kitClick = nil
        w.kitConfirm = spec.onConfirm or spec.onClick
        w.kitConfirmText = spec.confirmText or "Sure? Click again"
        w.kitRestTone, w.kitRestStyle, w.kitRestCaption = spec.tone, spec.style, spec[1] or ""
        w.kitArmedAt = nil
        w:SetScript("OnUpdate", nil)
        w.kitOnHide = confirmHidden
    end,
    Release = function(w) if w.kitArmedAt then disarm(w) end end,
    methods = {
        Activate = function(self)
            if self.kitArmedAt and UI.Now() - self.kitArmedAt < CONFIRM_SECONDS then
                disarm(self)
                if self.kitConfirm then self.kitConfirm(self) end
                return
            end
            self.kitArmedAt = UI.Now()
            self:SetTone("danger", "soft")
            self:SetText(self.kitConfirmText)
            self:SetScript("OnUpdate", confirmTick)
        end,
    },
}))

-- Links ------------------------------------------------------------------------------

-- Words that act: "Undo", "Report a problem", a notice's action. Spec: [1]
-- the caption, color (a token name for the resting colour, accent by
-- default), style (a text style), onClick.
UI.Define("Link", clickableType({
    stretch = false,
    Build = function(w)
        w.label = UI.NewText(w)
        w.label:SetPoint("LEFT", w, "LEFT", 0, 0)
        w.kitPressParts = { w.label }
        UI.WireButton(w)
    end,
    Init = function(w, spec)
        w.kitColor, w.kitTextStyle = spec.color, spec.style or "body"
        w.kitCaption = nil
        UI.InitClickable(w, spec)
        w:SetText(spec[1])
    end,
    methods = {
        SetText = function(self, text) if setCaption(self, text) then self:Changed() end end,
        GetText = getCaption,
        Measure = function(self)
            return math.ceil(UI.StringWidth(self.label)) + 2, math.ceil(self.label:GetStringHeight() or 12) + 4
        end,
        Paint = function(self, t)
            UI.ApplyStyle(self.label, self.kitTextStyle, t, nil, true)
            self:PaintState(t)
            self:Changed()
        end,
        PaintState = function(self, t)
            local state = stateOf(self)
            local color
            if state == "disabled" then
                color = t.muted45
            elseif state == "hover" then
                color = self.kitColor and t.accent or t.text
            else
                color = UI.Colour(t, self.kitColor) or t.accent
            end
            UI.TextColor(self.label, color)
        end,
    },
}))

-- The reset beside a setting. It shows only while the player's choice is
-- stored; a click forgets the choice. Spec: stored, default (words for the
-- tooltip), onReset. The owner calls SetStored(stored, defaultText).
UI.Define("ResetButton", extend(types.Link, {
    stretch = false,
    Init = function(w, spec)
        types.Link.Init(w, { "reset", style = "fine", color = "text", onClick = spec.onReset or spec.onClick,
            disabled = spec.disabled })
        w:SetStored(spec.stored, spec.default)
    end,
    methods = {
        SetStored = function(self, stored, defaultText)
            self.tooltip = "Back to the default" .. (defaultText and (" (" .. defaultText .. ")") or "")
                .. ". Your choice is forgotten, so the default applies from now on."
            self:SetShown(stored and true or false)
        end,
    },
}))

-- Glyph buttons -------------------------------------------------------------------------

-- A mark with no plate: back, next, up, down, menu, close, plus, minus.
-- Muted until the cursor is on it. Spec: [1] the kind, boxed (a faint
-- square: a window's close mark), bright (the text colour at rest), color
-- (a token at rest), size (the square), glyphSize, thickness, onClick.
local function glyphOf(w, kind, size, thickness)
    w.kitGlyphs = w.kitGlyphs or {}
    local key = kind .. ":" .. size .. ":" .. thickness
    local glyph = w.kitGlyphs[key]
    if not glyph then
        glyph = UI.NewGlyph(w, kind, size, thickness)
        w.kitGlyphs[key] = glyph
    end
    for other, g in pairs(w.kitGlyphs) do g:SetShown(other == key) end
    return glyph
end

UI.Define("GlyphButton", clickableType({
    stretch = false,
    Build = function(w)
        UI.WireButton(w)
    end,
    Init = function(w, spec)
        local size = spec.size or BUTTON_HEIGHT
        w.kitSize = size
        w:SetSize(size, size)
        w.kitBright, w.kitColor, w.kitHighlighted = spec.bright, spec.color, nil
        w.kitBoxed = spec.boxed and true or false
        if w.kitBoxed and not w.plate then w.plate = UI.NewPlate(w) end
        if w.plate then
            if w.kitBoxed then w.plate:Flat(nil, nil) else w.plate:Hide() end
        end
        w.glyph = glyphOf(w, spec[1] or "close", spec.glyphSize or math.floor(size * 0.42), spec.thickness or 1.6)
        w.glyph:Offset(0, 0)
        w.kitPressParts = { w.glyph }
        UI.InitClickable(w, spec)
    end,
    methods = {
        -- The mark a GlyphButton shows: another kind, the same size.
        SetGlyph = function(self, kind)
            local old = self.glyph
            self.glyph = glyphOf(self, kind, self.kitLayout.glyphSize or math.floor(self.kitSize * 0.42), self.kitLayout.thickness or 1.6)
            self.kitPressParts = { self.glyph }
            if old ~= self.glyph then self:PaintState(self.ui.tokens) end
        end,
        SetHighlighted = function(self, on)
            self.kitHighlighted = on and true or false
            self:Attract(on and "breathe" or nil)
            self:PaintState(self.ui.tokens)
        end,
        Measure = function(self) return self.kitSize, self.kitSize end,
        Paint = function(self, t) self:PaintState(t) end,
        PaintState = function(self, t)
            local state = stateOf(self)
            local lit = state == "hover" or self.kitHighlighted
            local color = state == "disabled" and t.muted45 or (lit and t.accent or (self.kitBright and t.text or t.muted))
            if self.kitColor and state == "rest" and not self.kitHighlighted then color = UI.Colour(t, self.kitColor) end
            if self.kitBoxed then
                local drew = false
                if state == "hover" and t.art then drew = self.plate:Art(t.art.plate, ART_CORNER, WHITE) end
                if not drew then
                    self.plate:Flat(UI.Faded(t, UI.Colour(t, "#000000"), 0.25), state == "hover" and t.accent65 or UI.Faded(t, t.border, 0.9))
                end
                if drew then color = t.text end
            end
            self.glyph:SetColor(color)
        end,
    },
}))

-- Attention ------------------------------------------------------------------------------

local function alphaAnim(group, from, to, duration, order)
    local anim = group:CreateAnimation("Alpha")
    if anim.SetFromAlpha then
        anim:SetFromAlpha(from)
        anim:SetToAlpha(to)
    else
        anim:SetChange(to - from)
    end
    anim:SetDuration(duration)
    if order then anim:SetOrder(order) end
    return anim
end

-- Pulse and trail are drawn by hand each frame, not with Scale animations:
-- scaling a ring scales its lines too, so a 1 pixel edge came out thick and
-- soft. By hand every line stays one crisp pixel.
local PULSE_GROW, PULSE_SECONDS, PULSE_REST = 4, 1.1, 0.35
local DASH, DASH_GAP, TRAIL_SPEED = 4, 3, 14

local function placeRing(fx, progress)
    local eased = 1 - (1 - progress) * (1 - progress)
    local d = UI.Snap(fx.widget, 1 + PULSE_GROW * eased)
    fx.ring:ClearAllPoints()
    fx.ring:SetPoint("TOPLEFT", fx.widget, "TOPLEFT", -d, d)
    fx.ring:SetPoint("BOTTOMRIGHT", fx.widget, "BOTTOMRIGHT", d, -d)
    fx.ring:SetAlpha((1 - progress) * 0.9)
end

-- The trail's dashes, `phase` pixels along the edge, clockwise from the top
-- left. A dash that turns a corner is drawn as two.
local function placeTrail(fx, phase)
    local widget = fx.widget
    local w, h = widget:GetWidth() or 0, widget:GetHeight() or 0
    local period = DASH + DASH_GAP
    local used, start = 0, 0
    local one = UI.Pixels(widget, 1)
    for side = 1, 4 do
        local length = (side == 1 or side == 3) and w or h
        local p = start + ((phase - start) % period) - period
        while p < start + length do
            local a, b = math.max(p, start) - start, math.min(p + DASH, start + length) - start
            a, b = UI.Snap(widget, a), UI.Snap(widget, b)
            if b - a > UI.Pixels(widget, 0.5) then
                used = used + 1
                local dash = fx.dashes[used]
                if not dash then
                    dash = widget:CreateTexture(nil, "OVERLAY", nil, 7)
                    fx.dashes[used] = dash
                    UI.TexColor(dash, fx.dashColor)
                end
                dash:ClearAllPoints()
                if side == 1 then
                    dash:SetPoint("TOPLEFT", widget, "TOPLEFT", a, 0); dash:SetSize(b - a, one)
                elseif side == 2 then
                    dash:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, -a); dash:SetSize(one, b - a)
                elseif side == 3 then
                    dash:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -a, 0); dash:SetSize(b - a, one)
                else
                    dash:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 0, a); dash:SetSize(one, b - a)
                end
                dash:Show()
            end
            p = p + period
        end
        start = start + length
    end
    for index = used + 1, #fx.dashes do fx.dashes[index]:Hide() end
end

local function hideTrail(fx)
    for _, dash in ipairs(fx.dashes) do dash:Hide() end
end

local function effectTick(ticker, elapsed)
    local fx = ticker.kitFx
    fx.clock = (fx.clock or 0) + (elapsed or 0)
    if fx.running.pulse then
        local at = fx.clock % (PULSE_SECONDS + PULSE_REST)
        if at < PULSE_SECONDS then
            fx.ring:Show()
            placeRing(fx, at / PULSE_SECONDS)
        else
            fx.ring:Hide()
        end
    end
    if fx.running.trail then placeTrail(fx, fx.clock * TRAIL_SPEED) end
end

local function paintEffects(fx, t)
    local widget = fx.widget
    local tone = widget.kitAttractTone and UI.Tone(t, widget.kitAttractTone)
    UI.TexColor(fx.wash, UI.Faded(t, tone or t.accentRaw, 0.3))
    local line = tone or t.accent
    fx.ring.plate:Flat(nil, line)
    UI.TexColor(fx.glintTexture, UI.Faded(t, line, 0.45))
    fx.dashColor = line
    for _, dash in ipairs(fx.dashes) do UI.TexColor(dash, line) end
    -- A change of reduceMotion restarts the effect the new way.
    if widget.kitFx == fx and widget.kitAttractKind and fx.reduced ~= (t.reduceMotion and true or false) then
        UI.Attract(widget, widget.kitAttractKind, widget.kitAttractTone)
    end
end

-- The effects' parts, made the first time a widget draws the eye.
local function buildEffects(widget)
    local fx = { widget = widget, dashes = {}, running = {} }
    fx.wash = widget:CreateTexture(nil, "BORDER", nil, 7)
    fx.wash:SetAllPoints(widget)
    fx.wash:Hide()
    fx.ring = UI.NewFrame("Frame", nil, widget)
    fx.ring.plate = UI.NewPlate(fx.ring, "OVERLAY")
    fx.ring:Hide()
    fx.ticker = UI.NewFrame("Frame", nil, widget)
    fx.ticker.kitFx = fx
    fx.ticker:Hide()
    fx.ticker:SetScript("OnUpdate", effectTick)
    fx.clip = UI.NewFrame("Frame", nil, widget)
    fx.clip:SetAllPoints(widget)
    if fx.clip.SetClipsChildren then pcall(fx.clip.SetClipsChildren, fx.clip, true) end
    fx.glint = UI.NewFrame("Frame", nil, fx.clip)
    fx.glint:SetPoint("TOPRIGHT", fx.clip, "TOPLEFT", 0, 0)
    fx.glint:SetPoint("BOTTOMRIGHT", fx.clip, "BOTTOMLEFT", 0, 0)
    fx.glint:SetWidth(18)
    fx.glintTexture = fx.glint:CreateTexture(nil, "OVERLAY")
    fx.glintTexture:SetAllPoints()
    fx.glint:Hide()
    if widget.CreateAnimationGroup then
        fx.breathe = fx.wash:CreateAnimationGroup()
        alphaAnim(fx.breathe, 0.25, 1, 0.8)
        fx.breathe:SetLooping("BOUNCE")
        fx.shimmer = fx.glint:CreateAnimationGroup()
        local move = fx.shimmer:CreateAnimation("Translation")
        fx.shimmerMove = move
        move:SetDuration(1.1)
        move:SetOrder(1)
        alphaAnim(fx.shimmer, 1, 1, 1.2, 2)
        fx.shimmer:SetLooping("REPEAT")
        fx.flash = fx.wash:CreateAnimationGroup()
        alphaAnim(fx.flash, 0, 0.9, 0.12, 1)
        alphaAnim(fx.flash, 0.9, 0.1, 0.15, 2)
        alphaAnim(fx.flash, 0.1, 0.9, 0.12, 3)
        alphaAnim(fx.flash, 0.9, 0, 0.3, 4)
        fx.flash:SetScript("OnFinished", function() fx.wash:Hide() end)
    end
    widget.ui:Paint(fx, function(t) paintEffects(fx, t) end)
    return fx
end

local function stopEffects(fx)
    for _, name in ipairs({ "breathe", "shimmer", "flash" }) do
        if fx[name] then fx[name]:Stop() end
    end
    fx.running = {}
    fx.ticker:Hide()
    fx.wash:Hide()
    fx.ring:Hide()
    fx.glint:Hide()
    hideTrail(fx)
end

local function startEffect(fx, kind)
    local widget = fx.widget
    if kind == "trail" then
        placeTrail(fx, 0)
        if fx.reduced then return end
        fx.running.trail = true
        fx.ticker:Show()
        return
    end
    if kind == "pulse" and not fx.reduced then
        fx.running.pulse = true
        fx.ticker:Show()
        return
    end
    if fx.reduced or not fx[kind] then
        fx.wash:SetAlpha(0.6)
        fx.wash:Show()
        return
    end
    if kind == "breathe" or kind == "flash" then
        fx.wash:SetAlpha(kind == "flash" and 0 or 1)
        fx.wash:Show()
    elseif kind == "shimmer" then
        fx.shimmerMove:SetOffset((widget:GetWidth() or 100) + 18, 0)
        fx.glint:Show()
    end
    fx[kind]:Play()
end

-- Draws the eye to a widget: "breathe", "pulse", "shimmer", "flash",
-- "trail", or a list of them run together. nil stops. One per window: a new
-- one stops the last. Under reduceMotion a still wash stands in.
function UI.Attract(widget, kind, tone)
    local window = UI.WindowOf(widget)
    if kind and window then
        if window.kitAttracting and window.kitAttracting ~= widget then UI.Attract(window.kitAttracting, nil) end
        window.kitAttracting = widget
    elseif not kind and window and window.kitAttracting == widget then
        window.kitAttracting = nil
    end
    widget.kitAttractKind = kind
    widget.kitAttractTone = tone
    if not kind and not widget.kitFx then return end
    local fx = widget.kitFx or buildEffects(widget)
    widget.kitFx = fx
    stopEffects(fx)
    if not kind then return end
    fx.reduced = widget.ui.tokens.reduceMotion and true or false
    paintEffects(fx, widget.ui.tokens)
    fx.clock = 0
    local washed = false
    for _, one in ipairs(type(kind) == "table" and kind or { kind }) do
        local wash = one == "breathe" or one == "flash"
        if not (wash and washed) then startEffect(fx, one) end
        washed = washed or wash
    end
end

function UI.Widget:Attract(kind, tone) UI.Attract(self, kind, tone) end
