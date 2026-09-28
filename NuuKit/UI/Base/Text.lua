local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Text ---------------------------------------------------------------------------

-- A line (or with `wrap`, a paragraph) in one of the text styles: title,
-- window, heading, body, label, link, fine, number, key. `opts.color` is a
-- token name or a colour; `opts.justify` "LEFT", "CENTER" or "RIGHT".
-- SetText, SetColor and SetStyle lay the container out again.
UI.Define("Text", function(ui, parent, text, style, opts)
    opts = opts or {}
    local label = UI.NewText(parent)
    label.kitStyle = style or "body"
    label.kitColor = opts.color
    label.kitNoTooltip = true
    if opts.wrap then
        if label.SetWordWrap then label:SetWordWrap(true) end
        label:SetJustifyV("TOP")
    end
    label:SetJustifyH(opts.justify or "LEFT")

    local setText, show, hide = label.SetText, label.Show, label.Hide
    local function changed(l)
        if l.kitParentContainer then UI.Invalidate(l.kitParentContainer) end
    end
    label.SetText = function(l, value)
        setText(l, value == nil and "" or tostring(value))
        changed(l)
    end
    label.Show = function(l) show(l); changed(l) end
    label.Hide = function(l) hide(l); changed(l) end
    label.SetShown = function(l, on) if on then l:Show() else l:Hide() end end
    label.SetColor = function(l, color) l.kitColor = color; l:Repaint() end
    label.SetStyle = function(l, value) l.kitStyle = value; l:Repaint(); changed(l) end

    label.KitNaturalWidth = function(l) return math.ceil(UI.StringWidth(l)) + 1 end
    label.KitNaturalHeight = function(l, width)
        if opts.wrap and width and width > 0 then l:SetWidth(width) end
        local h = l:GetStringHeight() or 0
        if h <= 0 then
            local spec = UI.textStyles[l.kitStyle] or UI.textStyles.body
            h = spec.size * (ui.tokens.textScale or 1) + 2
        end
        return math.ceil(h)
    end

    setText(label, text == nil and "" or tostring(text))
    return ui:Finish(label, opts, function(l, t)
        UI.ApplyStyle(l, l.kitStyle, t, l.kitColor)
        changed(l)
    end)
end)

-- Sections -----------------------------------------------------------------------

-- A heading with a rule, a hint, and (optional) a reset at the right, over a
-- body the section's own calls stack into. With `foldable`, the heading folds
-- the body away. `opts.reset` is { stored, default, onReset }: the reset shows
-- only while `stored` is true, as OpenRoad's ResetButton did.
UI.Define("Section", function(ui, parent, caption, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeContainer(ui, frame, "column", { gap = opts.headerGap or 8 })

    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(1, 22)
    UI.MakeContainer(ui, header, "row", { gap = 10 })
    header.kitLayout = { height = 22 }
    frame:KitAppend(header)

    -- The heading itself: chevron, caption, hint; the click target to fold.
    local toggle = CreateFrame("Button", nil, header)
    toggle:SetHeight(22)
    toggle.kitStretch = false
    local open, folded
    if opts.foldable then
        open = UI.NewGlyph(toggle, "down", 8, 1.5)
        folded = UI.NewGlyph(toggle, "next", 8, 1.5)
    end
    local title = UI.NewText(toggle)
    local hint = UI.NewText(toggle)
    title:SetPoint("LEFT", toggle, "LEFT", opts.foldable and 16 or 0, 0)
    hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
    title:SetText(caption or "")
    hint:SetText(opts.hint or "")
    toggle.KitNaturalWidth = function()
        local w = (opts.foldable and 16 or 0) + UI.StringWidth(title)
        if (hint:GetText() or "") ~= "" then w = w + 8 + UI.StringWidth(hint) end
        return math.ceil(w) + 2
    end
    toggle.kitLayout = {}
    toggle.KitSized = function()
        if open then
            local x = -(toggle:GetWidth() or 0) / 2 + 5
            open:Offset(x, 0)
            folded:Offset(x, 0)
        end
    end
    header:KitAppend(toggle)
    local rule = ui:Rule(header, {})
    header:KitAppend(rule)

    local reset
    if opts.reset then
        reset = ui:Link(header, "reset", { style = "fine", onClick = function()
            if opts.reset.onReset then opts.reset.onReset() end
        end })
        header:KitAppend(reset)
    end

    local body = CreateFrame("Frame", nil, frame)
    body:SetSize(1, 1)
    UI.MakeContainer(ui, body, "column", { gap = opts.gap or 8, padding = opts.padding })
    body.kitLayout = { grow = opts.grow and true or nil }
    frame:KitAppend(body)
    frame.kitInner = body

    frame.open = opts.open ~= false
    function frame:SetOpen(value)
        self.open = value and true or false
        body:SetShown(self.open)
        if open then
            open:SetShown(self.open)
            folded:SetShown(not self.open)
        end
        UI.Invalidate(self)
    end
    function frame:IsOpen() return self.open end
    function frame:SetHint(text)
        hint:SetText(text or "")
        UI.Invalidate(header)
    end
    function frame:SetCaption(text)
        title:SetText(text or "")
        UI.Invalidate(header)
    end
    function frame:SetStored(stored, defaultText)
        if not reset then return end
        reset:SetShown(stored and true or false)
        reset:SetTooltip("Back to the default" .. (defaultText and (" (" .. defaultText .. ")") or "")
            .. ". Your choice is forgotten, so the default applies from now on.")
    end
    if opts.foldable then
        toggle:SetScript("OnClick", function()
            UI.ClickSound()
            frame:SetOpen(not frame.open)
            if opts.onToggle then opts.onToggle(frame.open) end
        end)
        toggle:SetScript("OnEnter", function() toggle.hover = true; frame:Repaint() end)
        toggle:SetScript("OnLeave", function() toggle.hover = false; frame:Repaint() end)
    else
        toggle:EnableMouse(false)
    end
    frame:SetOpen(frame.open)
    if reset then frame:SetStored(opts.reset.stored, opts.reset.default) end

    return ui:Finish(frame, opts, function(f, t)
        UI.ApplyStyle(title, "heading", t, toggle.hover and "accent" or "text")
        UI.ApplyStyle(hint, "label", t)
        if open then
            open:SetColor(toggle.hover and t.accent or t.muted)
            folded:SetColor(toggle.hover and t.accent or t.muted)
        end
        UI.Invalidate(header)
    end)
end)

-- Tags ---------------------------------------------------------------------------------

-- A small label on a tinted plate: a count, a state, "needs pattern".
UI.Define("Tag", function(ui, parent, text, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame.kitStretch = false
    local plate = UI.NewPlate(frame)
    local label = UI.NewText(frame)
    label:SetPoint("CENTER", frame, "CENTER", 0, 0)
    label:SetText(text or "")
    local function fit()
        frame:SetSize(math.ceil(UI.StringWidth(label)) + 10, 16)
    end
    frame.SetText = function(f, value)
        label:SetText(value or "")
        fit()
        if f.kitParentContainer then UI.Invalidate(f.kitParentContainer) end
    end
    frame.GetText = function() return label:GetText() end
    frame.SetTone = function(f, tone) opts.tone = tone; f:Repaint() end
    fit()
    return ui:Finish(frame, opts, function(_, t)
        local base = UI.ToneColor(t, opts.tone) or t.muted
        plate:Flat(UI.Alpha(base, 0.14), UI.Alpha(base, 0.55))
        UI.ApplyStyle(label, "fine", t, base)
        fit()
    end)
end)

-- Notices --------------------------------------------------------------------------------

local NOTICE_TONES = { info = "accent", warning = "warning", danger = "danger", success = "success" }
local NOTICE_MARK = { info = "i", warning = "!", danger = "x", success = "v" }

-- A message in the flow of a window: `tone` info (the default), warning,
-- danger or success; `action` { caption, onClick } for a link under it;
-- `dismiss` for a close mark, `onDismiss` told when it is used.
UI.Define("Notice", function(ui, parent, text, opts)
    opts = opts or {}
    local kind = NOTICE_TONES[opts.tone] and opts.tone or "info"
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 40)
    local plate = UI.NewPlate(frame)
    local badge = CreateFrame("Frame", nil, frame)
    badge:SetSize(16, 16)
    badge:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -9)
    local badgeFill = badge:CreateTexture(nil, "ARTWORK")
    badgeFill:SetAllPoints()
    local mark = UI.NewText(badge)
    mark:SetPoint("CENTER", badge, "CENTER", 0, 0)
    mark:SetText(NOTICE_MARK[kind])
    local message = UI.NewText(frame)
    if message.SetWordWrap then message:SetWordWrap(true) end
    message:SetJustifyV("TOP")
    message:SetPoint("TOPLEFT", frame, "TOPLEFT", 33, -9)
    message:SetPoint("RIGHT", frame, "RIGHT", opts.dismiss and -28 or -10, 0)
    message:SetText(text or "")

    local action
    if opts.action then
        action = ui:Link(frame, opts.action.caption or "", { onClick = opts.action.onClick })
        action:SetPoint("TOPLEFT", message, "BOTTOMLEFT", 0, -4)
    end
    if opts.dismiss then
        local close = ui:GlyphButton(frame, "close", { size = 18, onClick = function()
            frame:Hide()
            if opts.onDismiss then opts.onDismiss() end
        end })
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    end

    frame.SetText = function(f, value)
        message:SetText(value or "")
        if f.kitParentContainer then UI.Invalidate(f.kitParentContainer) end
    end
    frame.KitNaturalHeight = function(_, width)
        if width and width > 0 then message:SetWidth(width - 33 - (opts.dismiss and 28 or 10)) end
        local h = 9 + (message:GetStringHeight() or 12) + 9
        if action then h = h + 4 + (action:GetHeight() or 14) end
        return math.ceil(math.max(34, h))
    end
    return ui:Finish(frame, opts, function(_, t)
        local base = UI.ToneColor(t, NOTICE_TONES[kind])
        plate:Flat(UI.Alpha(base, 0.1), UI.Alpha(base, 0.45))
        UI.TexColor(badgeFill, base)
        UI.ApplyStyle(mark, "fine", t, t.window)
        UI.ApplyStyle(message, "body", t)
        if frame.kitParentContainer then UI.Invalidate(frame.kitParentContainer) end
    end)
end)

-- Cards ------------------------------------------------------------------------------------

-- A raised plate with a coloured rail down its left edge, holding what is
-- made in it as a column: the tracker's current step, a step kept on screen.
-- `opts`: tone (the rail; accent by default), padding (12), gap (6).
-- SetTone changes the rail.
local RAIL = 3

UI.Define("Card", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame.plate = UI.NewPlate(frame)
    frame.rail = frame:CreateTexture(nil, "ARTWORK")
    frame.rail:SetPoint("TOPLEFT")
    frame.rail:SetPoint("BOTTOMLEFT")
    UI.Stroke(frame.rail, "width", RAIL)
    local body = CreateFrame("Frame", nil, frame)
    UI.MakeContainer(ui, body, "column", { gap = opts.gap or 6 })
    for method, fn in pairs(UI.Container) do frame[method] = fn end
    frame.kitInner = body
    frame.body = body
    local pad = opts.padding or 12
    local function insets(f)
        return UI.Snap(f, RAIL + pad), UI.Snap(f, pad)
    end
    local function place(f)
        local left, edge = insets(f)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", f, "TOPLEFT", left, -edge)
        body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge, edge)
    end
    place(frame)
    frame.KitNaturalWidth = function(f)
        local left, edge = insets(f)
        return body:KitNaturalWidth() + left + edge
    end
    frame.KitNaturalHeight = function(f, width)
        local left, edge = insets(f)
        return body:KitNaturalHeight(width and (width - left - edge) or nil) + 2 * edge
    end
    -- Sized by its parent: its body alone lays out again.
    frame.KitSized = function(f)
        place(f)
        UI.LayoutOnly(body)
    end
    -- What is made in it changes the card's height, so the body reports to
    -- the container the card sits in.
    frame.KitAttached = function(_, container) body.kitParentContainer = container end
    function frame:SetTone(tone) opts.tone = tone; self:Repaint() end
    return ui:Finish(frame, opts, function(f, t)
        f.plate:Flat(t.raisedBg, t.hairline)
        UI.TexColor(f.rail, UI.ToneColor(t, opts.tone) or t.accent)
    end)
end, true)
