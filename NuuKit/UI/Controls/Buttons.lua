local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Buttons, ported from OpenRoad's Theme:Button and its relatives, with tones
-- and styles, the theme's art plates, and repainting.

local BUTTON_HEIGHT, ART_CORNER = 24, 5
local WHITE = { 1, 1, 1, 1 }
local DIM = { 0.55, 0.55, 0.55, 1 }

-- The window a widget sits in, through the containers above it.
function UI.WindowOf(widget)
    local frame = widget
    while frame do
        if frame.kitIsWindow then return frame end
        frame = frame.kitParentContainer or (frame.GetParent and frame:GetParent())
    end
    return nil
end

local function stateOf(button)
    if not button:IsEnabled() then return "disabled" end
    if button.kitActive then return "active" end
    if button.hover then return "hover" end
    return "rest"
end

-- Whether a button of this tone and style wears the theme's plate art.
local function usesArt(t, tone, style)
    if not t.art then return false end
    if tone ~= nil and tone ~= "neutral" and tone ~= "accent" then return false end
    return style == nil or style == "plate" or style == "solid"
end

local function paintButton(button, t)
    local state = stateOf(button)
    local tone, style = button.kitTone, button.kitStyle
    local fill, edge, ink = UI.ButtonColors(t, tone, style, state)
    local drew = false
    if usesArt(t, tone, style) then
        local spec = tone == "accent" and t.art.platePrimary or t.art.plate
        drew = button.plate:Art(spec, ART_CORNER, state == "disabled" and DIM or WHITE)
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
    if not drew then button.plate:Flat(fill, edge) end
    UI.TexColor(button.shine, WHITE, drew and state == "hover" and 0.08 or 0)
    UI.ApplyStyle(button.label, button.kitTextStyle or "body", t, ink)
    if button.glyph then button.glyph:SetColor(ink) end
    if button.holdFill then
        UI.TexColor(button.holdFill, UI.Alpha(UI.ToneColor(t, tone) or t.accentRaw, 0.35))
    end
    button:Fit()
end

-- Everything a clickable widget shares: hover, the press nudge, the click
-- sound, taking the focus from a field, enabled with a reason.
local function wire(button, ui)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnEnter", function(b) b.hover = true; b:Repaint() end)
    button:SetScript("OnLeave", function(b) b.hover = false; b:Repaint() end)
    button.kitPressParts = button.kitPressParts or {}
    local function release(b)
        if not b.pressed then return end
        b.pressed = false
        for _, part in ipairs(b.kitPressParts) do
            if part.Nudge then part:Nudge(-1, 1) else UI.ShiftPoints(part, -1, 1) end
        end
    end
    button:HookScript("OnMouseDown", function(b, mouse)
        if mouse ~= "LeftButton" or b.pressed or not b:IsEnabled() then return end
        b.pressed = true
        for _, part in ipairs(b.kitPressParts) do
            if part.Nudge then part:Nudge(1, -1) else UI.ShiftPoints(part, 1, -1) end
        end
    end)
    button:HookScript("OnMouseUp", release)
    button:HookScript("OnHide", release)
    button:SetScript("PreClick", function(b, mouse)
        if mouse == "RightButton" then return end
        UI.ClearTypingFocus(b)
        UI.ClickSound()
    end)
    button:SetScript("OnClick", function(b, mouse)
        if mouse == "RightButton" or b.kitHold then return end
        if b.kitClick then b.kitClick(b) end
    end)
    -- A builder may disable its button before Finish gives it Repaint;
    -- Finish paints it then.
    pcall(button.HookScript, button, "OnEnable", function(b) if b.Repaint then b:Repaint() end end)
    pcall(button.HookScript, button, "OnDisable", function(b) if b.Repaint then b:Repaint() end end)
    button.kitTooltipAlways = true
    UI.RegisterFocusable(ui, button, false)

    -- Disabled, with the reason its tooltip gives.
    button.SetEnabled = function(b, enabled, reason)
        b.kitReason = (not enabled) and reason or nil
        if enabled then b:Enable() else b:Disable(); release(b) end
        b:Repaint()
    end
    button.SetOnClick = function(b, fn) b.kitClick = fn end
    return button
end
UI.WireButton = wire

-- Buttons --------------------------------------------------------------------------

-- `opts`: tone (accent, neutral, success, danger, warning, quest, or a
-- colour), style (solid, soft, outline, ghost; neutral buttons are "plate"),
-- width (else as wide as the caption), height, tooltip, onClick(button),
-- disabled (or a reason string), active, hold (seconds to hold instead of a
-- click), textStyle.
UI.Define("Button", function(ui, parent, caption, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent)
    local height = opts.height or BUTTON_HEIGHT
    button:SetSize(opts.width or BUTTON_HEIGHT, height)
    button.kitStretch = opts.stretch == true
    button.kitTone = opts.tone
    button.kitStyle = opts.style
    button.kitTextStyle = opts.textStyle
    button.kitClick = opts.onClick
    button.kitActive = opts.active and true or false
    button.plate = UI.NewPlate(button)
    button.shine = button:CreateTexture(nil, "BORDER", nil, 7)
    button.shine:SetAllPoints()
    local label = UI.NewText(button)
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText(caption or "")
    button.label = label
    button.kitPressParts = { label }
    local autoWidth = opts.width == nil

    -- Whether the layout sizes it (growing or stretching in a container): then
    -- its width is the layout's, and a repaint must not put it back to the
    -- caption's, or it jumps for a frame until the layout runs again.
    local function laidOut(b)
        local lay = b.kitLayout
        return b.kitStretch or (lay and lay.grow and lay.grow ~= 0) and true or false
    end

    function button:Fit()
        label:SetWidth(0)
        local wanted = UI.StringWidth(label)
        if autoWidth and not laidOut(self) then
            local width = math.max(BUTTON_HEIGHT, math.ceil(wanted + (self.kitTextPad or 20)))
            if math.abs((self:GetWidth() or 0) - width) > 0.5 then
                self:SetWidth(width)
                if self.kitParentContainer then UI.Invalidate(self.kitParentContainer) end
            end
        else
            local room = (self:GetWidth() or 0) - (self.kitTextReserve or 8)
            if room > 0 and wanted > room then label:SetWidth(room) end
        end
    end
    button.KitNaturalWidth = function(b)
        if not autoWidth then return b:GetWidth() end
        label:SetWidth(0)
        return math.max(BUTTON_HEIGHT, math.ceil(UI.StringWidth(label) + (b.kitTextPad or 20)))
    end
    button.KitNaturalHeight = function() return height end

    button.SetText = function(b, text)
        label:SetText(text or "")
        b:Fit()
        -- A laid-out button's caption changes what it needs: ask again.
        if laidOut(b) and b.kitParentContainer then UI.Invalidate(b.kitParentContainer) end
    end
    button.GetText = function() return label:GetText() end
    button.SetActive = function(b, active) b.kitActive = active and true or false; b:Repaint() end
    button.IsActive = function(b) return b.kitActive end
    button.SetTone = function(b, tone, style) b.kitTone, b.kitStyle = tone, style; b:Repaint() end

    wire(button, ui)
    if opts.hold then UI.MakeHold(button, opts.hold) end
    if opts.disabled then
        button:Disable()
        if type(opts.disabled) == "string" then button.kitReason = opts.disabled end
    end
    button:HookScript("OnSizeChanged", function(b) if not autoWidth then b:Fit() end end)
    return ui:Finish(button, opts, paintButton)
end)

-- Hold to act: the button fills while held and acts when full.
function UI.MakeHold(button, seconds)
    button.kitHold = seconds
    local fill = button:CreateTexture(nil, "BORDER", nil, 6)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetWidth(0.01)
    fill:Hide()
    button.holdFill = fill
    local function stop(b)
        b.kitHeldAt = nil
        b:SetScript("OnUpdate", nil)
        fill:Hide()
    end
    button:HookScript("OnMouseDown", function(b, mouse)
        if mouse ~= "LeftButton" or not b:IsEnabled() then return end
        b.kitHeldAt = UI.Now()
        fill:SetWidth(0.01)
        fill:Show()
        b:SetScript("OnUpdate", function(self)
            local progress = (UI.Now() - (self.kitHeldAt or UI.Now())) / seconds
            if progress >= 1 then
                stop(self)
                if self.kitClick then self.kitClick(self) end
                return
            end
            fill:SetWidth(math.max(0.01, (self:GetWidth() or 0) * progress))
        end)
    end)
    button:HookScript("OnMouseUp", stop)
    button:HookScript("OnHide", stop)
end

-- Two clicks for what cannot be taken back: the first arms it and says so, a
-- second within four seconds acts. Left alone, or hidden, it disarms.
local CONFIRM_SECONDS = 4

UI.Define("ConfirmButton", function(ui, parent, caption, opts)
    opts = opts or {}
    local onConfirm = opts.onConfirm or opts.onClick
    local copy = {}
    for key, value in pairs(opts) do copy[key] = value end
    copy.onClick = nil
    local button = UI.Proto.Button(ui, parent, caption, copy)
    local armedAt
    local function disarm(b)
        armedAt = nil
        b:SetScript("OnUpdate", nil)
        b:SetTone(opts.tone, opts.style)
        b:SetText(caption)
    end
    button.kitClick = function(b)
        if armedAt and UI.Now() - armedAt < CONFIRM_SECONDS then
            disarm(b)
            if onConfirm then onConfirm(b) end
            return
        end
        armedAt = UI.Now()
        b:SetTone("danger", "soft")
        b:SetText(opts.confirmText or "Sure? Click again")
        b:SetScript("OnUpdate", function(self)
            if armedAt and UI.Now() - armedAt >= CONFIRM_SECONDS then disarm(self) end
        end)
    end
    button:HookScript("OnHide", function(b) if armedAt then disarm(b) end end)
    return button
end)

-- Links ------------------------------------------------------------------------------

-- Words that act: "Undo", "Report a problem", a notice's action. `opts.color`
-- (a token name) for the resting colour, accent by default; `style` a text
-- style.
UI.Define("Link", function(ui, parent, caption, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent)
    button.kitStretch = false
    button.kitClick = opts.onClick
    local label = UI.NewText(button)
    label:SetPoint("LEFT", button, "LEFT", 0, 0)
    label:SetText(caption or "")
    button.label = label
    button.kitPressParts = { label }
    local function fit(b)
        b:SetSize(math.ceil(UI.StringWidth(label)) + 2, math.ceil((label:GetStringHeight() or 12)) + 4)
    end
    button.KitNaturalWidth = function() return math.ceil(UI.StringWidth(label)) + 2 end
    button.KitNaturalHeight = function() return math.ceil((label:GetStringHeight() or 12)) + 4 end
    button.SetText = function(b, text)
        label:SetText(text or "")
        fit(b)
        if b.kitParentContainer then UI.Invalidate(b.kitParentContainer) end
    end
    button.GetText = function() return label:GetText() end
    wire(button, ui)
    return ui:Finish(button, opts, function(b, t)
        local state = stateOf(b)
        local color
        if state == "disabled" then
            color = t.muted45
        elseif state == "hover" then
            color = opts.color and t.accent or t.text
        else
            color = UI.TokenColor(t, opts.color) or t.accent
        end
        UI.ApplyStyle(label, opts.style or "body", t, color)
        fit(b)
    end)
end)

-- The reset beside a setting. It shows only while the player's choice is
-- stored, so seeing it says the setting was changed; a click forgets the
-- choice. The owner calls SetStored(stored, defaultText) when it redraws.
UI.Define("ResetButton", function(ui, parent, opts)
    opts = opts or {}
    local link = UI.Proto.Link(ui, parent, "reset", { style = "fine", color = "text", onClick = opts.onReset or opts.onClick })
    link.SetStored = function(l, stored, defaultText)
        l:SetTooltip("Back to the default" .. (defaultText and (" (" .. defaultText .. ")") or "")
            .. ". Your choice is forgotten, so the default applies from now on.")
        l:SetShown(stored and true or false)
    end
    link:SetStored(opts.stored, opts.default)
    return link
end)

-- Glyph buttons -------------------------------------------------------------------------

-- A mark with no plate: back, next, up, down, menu, close, plus, minus. Muted
-- until the cursor is on it. `opts.boxed` gives it a faint square (the close
-- mark of a window), `opts.bright` the text colour at rest, `opts.size` the
-- square it sits in and `opts.glyphSize` the mark.
UI.Define("GlyphButton", function(ui, parent, kind, opts)
    opts = opts or {}
    local size = opts.size or BUTTON_HEIGHT
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.kitStretch = false
    button.kitClick = opts.onClick
    button.KitNaturalWidth = function() return size end
    button.KitNaturalHeight = function() return size end
    local plate = opts.boxed and UI.NewPlate(button) or nil
    local glyph = UI.NewGlyph(button, kind, opts.glyphSize or math.floor(size * 0.42), opts.thickness or 1.6)
    button.glyph = glyph
    button.kitPressParts = { glyph }
    button.SetHighlighted = function(b, on)
        b.kitHighlighted = on and true or false
        b:Attract(on and "breathe" or nil)
        b:Repaint()
    end
    wire(button, ui)
    return ui:Finish(button, opts, function(b, t)
        local state = stateOf(b)
        local lit = state == "hover" or b.kitHighlighted
        local color = state == "disabled" and t.muted45 or (lit and t.accent or (opts.bright and t.text or t.muted))
        if opts.color and state == "rest" and not b.kitHighlighted then color = UI.TokenColor(t, opts.color) end
        glyph:SetColor(color)
        if plate then
            local drew = false
            if state == "hover" and t.art then drew = plate:Art(t.art.plate, ART_CORNER, WHITE) end
            if not drew then
                plate:Flat({ 0, 0, 0, 0.25 }, state == "hover" and t.accent65 or UI.Alpha(t.border, 0.9))
            end
            if state == "hover" and t.art and drew then glyph:SetColor(t.text) end
        end
    end)
end)

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

-- The pulse's ring at `progress` (0 to 1) of its way out.
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
    local edges = { { "top", w }, { "right", h }, { "bottom", w }, { "left", h } }
    local used, start = 0, 0
    for _, edge in ipairs(edges) do
        local side, length = edge[1], edge[2]
        local p = start + ((phase - start) % period) - period
        while p < start + length do
            local a, b = math.max(p, start) - start, math.min(p + DASH, start + length) - start
            -- Whole pixels, one thick, so a dash never smears as it moves.
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
                local one = UI.Pixels(widget, 1)
                if side == "top" then
                    dash:SetPoint("TOPLEFT", widget, "TOPLEFT", a, 0); dash:SetSize(b - a, one)
                elseif side == "right" then
                    dash:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, -a); dash:SetSize(one, b - a)
                elseif side == "bottom" then
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

local function buildEffects(widget)
    local fx = { widget = widget, dashes = {}, running = {} }
    fx.wash = widget:CreateTexture(nil, "BORDER", nil, 7)
    fx.wash:SetAllPoints(widget)
    fx.wash:Hide()

    fx.ring = CreateFrame("Frame", nil, widget)
    fx.ring.plate = UI.NewPlate(fx.ring, "OVERLAY")
    fx.ring:Hide()

    -- Runs the hand-drawn kinds; hidden, and so still, the rest of the time.
    fx.ticker = CreateFrame("Frame", nil, widget)
    fx.ticker:Hide()
    fx.ticker:SetScript("OnUpdate", function(_, elapsed)
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
    end)

    fx.clip = CreateFrame("Frame", nil, widget)
    fx.clip:SetAllPoints(widget)
    if fx.clip.SetClipsChildren then pcall(fx.clip.SetClipsChildren, fx.clip, true) end
    fx.glint = CreateFrame("Frame", nil, fx.clip)
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

    widget.ui:Paint(fx, function(t)
        local base = widget.kitAttractTone and UI.ToneColor(t, widget.kitAttractTone) or t.accentRaw
        UI.TexColor(fx.wash, UI.Alpha(base, 0.3))
        local line = widget.kitAttractTone and UI.ToneColor(t, widget.kitAttractTone) or t.accent
        fx.ring.plate:Flat(nil, line)
        UI.TexColor(fx.glintTexture, UI.Alpha(line, 0.45))
        fx.dashColor = line
        for _, dash in ipairs(fx.dashes) do UI.TexColor(dash, line) end
        -- A change of reduceMotion restarts the effect the new way; not while
        -- the effects are still being built.
        if widget.kitFx == fx and widget.kitAttractKind and fx.reduced ~= (t.reduceMotion and true or false) then
            UI.Attract(widget, widget.kitAttractKind, widget.kitAttractTone)
        end
    end)
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

-- Starts one kind on `fx`; the kinds are layers, so several can run at once.
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

-- Draws the eye to a widget: "breathe" (press this next), "pulse" (a ring
-- leaves the edge), "shimmer" (a glint sweeps across), "flash" (two blinks,
-- then still), "trail" (dashes march round the edge), or a list of them run
-- together, such as { "trail", "breathe" }. Breathe and flash both light the
-- same wash, so a list takes the first of the two and leaves the other. nil
-- stops. One per window: a new one stops the last. Under the look's
-- reduceMotion, or without animation groups, a still wash stands in; the
-- trail's dashes stand still.
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
    -- The colours follow this call's tone, not the one the effects were made in.
    local paint = widget.ui.painters[fx]
    if paint then paint(widget.ui.tokens) end
    fx.clock = 0
    local washed = false
    for _, one in ipairs(type(kind) == "table" and kind or { kind }) do
        local wash = one == "breathe" or one == "flash"
        if not (wash and washed) then startEffect(fx, one) end
        washed = washed or wash
    end
end
