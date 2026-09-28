local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI1 = Kit.UI1 or {}
local UI = Kit.UI1

-- Text ---------------------------------------------------------------------------

-- A line (or with `wrap`, a paragraph) in one of the text styles: title,
-- window, heading, body, label, link, fine, number, key. Spec: [1] the text,
-- style, color (a token name or a colour), justify ("LEFT", "CENTER",
-- "RIGHT"), wrap. The widget is the font string itself.

-- The client's own font string methods, which Text's replace.
local probe = UIParent and UIParent:CreateFontString()
local rawSetText = probe and probe.SetText
local rawShow = probe and probe.Show
local rawHide = probe and probe.Hide

UI.Define("Text", {
    kind = "FontString",
    -- A new font string does not wrap: the first Init has nothing to change.
    Build = function(w) w.kitWrap = false end,
    Init = function(w, spec)
        w.kitStyle = spec.style or "body"
        w.kitColor = spec.color
        local wrap = spec.wrap and true or false
        if w.kitWrap ~= wrap then
            w.kitWrap = wrap
            if w.SetWordWrap then w:SetWordWrap(wrap) end
            w:SetJustifyV(wrap and "TOP" or "MIDDLE")
            if not wrap then w:SetWidth(0) end
        end
        w.kitWraps = wrap or nil
        w:SetJustifyH(spec.justify or "LEFT")
        w.kitText = nil
        w:SetText(spec[1])
    end,
    methods = {
        SetText = function(self, value)
            value = value == nil and "" or tostring(value)
            if value == self.kitText then return end
            self.kitText = value
            rawSetText(self, value)
            self:Changed()
        end,
        GetText = function(self) return self.kitText end,
        Show = function(self)
            if self:IsShown() then return end
            rawShow(self)
            UI.ChildToggled(self)
        end,
        Hide = function(self)
            if not self:IsShown() then return end
            rawHide(self)
            UI.ChildToggled(self)
        end,
        SetShown = function(self, on)
            if on then self:Show() else self:Hide() end
        end,
        SetColor = function(self, color)
            if color == self.kitColor then return end
            self.kitColor = color
            self:Paint(self.ui.tokens)
        end,
        SetStyle = function(self, style)
            if style == self.kitStyle then return end
            self.kitStyle = style
            self:Paint(self.ui.tokens)
            self:Changed()
        end,
        Measure = function(self, width)
            local natural = math.ceil(UI.StringWidth(self)) + 1
            if self.kitWrap and width and width > 0 then self:SetWidth(width) end
            local height = self:GetStringHeight() or 0
            if height <= 0 then height = (self.ui.tokens.sizes[self.kitStyle] or 11) + 2 end
            return natural, math.ceil(height)
        end,
        Paint = function(self, t)
            UI.ApplyStyle(self, self.kitStyle, t, self.kitColor)
        end,
    },
})

-- Sections -----------------------------------------------------------------------

-- A heading with a rule, a hint, and (optional) a reset at the right, over a
-- body the section's own calls stack into. Spec: [1] the caption, hint,
-- foldable, open (default true), onToggle(open), reset { stored, default,
-- onReset } (the reset shows only while `stored`), gap and padding of the
-- body, headerGap, grow.
local function sectionToggle(toggle)
    local w = toggle.kitOwner
    UI.ClickSound()
    w:SetOpen(not w.kitOpen)
    if w.kitOnToggle then w.kitOnToggle(w.kitOpen) end
end

local function sectionReset(link)
    local w = link.kitSection
    if w.kitOnReset then w.kitOnReset(w) end
end

-- The heading's natural width: chevron, caption, hint.
local function toggleMeasure(toggle)
    local w = toggle.kitOwner
    local width = (w.kitFoldable and 16 or 0) + UI.StringWidth(w.title)
    if (w.hint:GetText() or "") ~= "" then width = width + 8 + UI.StringWidth(w.hint) end
    return math.ceil(width) + 2, 22
end

local function toggleSized(toggle, width)
    local w = toggle.kitOwner
    local x = -(width or 0) / 2 + 5
    w.openGlyph:Offset(x, 0)
    w.foldedGlyph:Offset(x, 0)
end

UI.Define("Section", {
    holds = true, fills = false,
    Build = function(w)
        local ui = w.ui
        w:SetSize(1, 1)
        UI.MakeStack(ui, w, "column", {})
        local header = UI.Part(ui, w, "row", { gap = 10 }, { height = 22 })
        w:Append(header)
        w.header = header

        local toggle = CreateFrame("Button", nil, header)
        toggle:SetHeight(22)
        UI.Adopt(toggle, "SectionHeading", { UI.Widget }, { Measure = toggleMeasure, Sized = toggleSized })
        toggle.ui, toggle.kitStretch, toggle.kitLayout = ui, false, {}
        toggle:SetScript("OnClick", sectionToggle)
        -- Hover repaints the section (its PaintState reads toggle.hover).
        UI.Hover(toggle, w)
        w.toggle = toggle
        w.openGlyph = UI.NewGlyph(toggle, "down", 8, 1.5)
        w.foldedGlyph = UI.NewGlyph(toggle, "next", 8, 1.5)
        w.title = UI.NewText(toggle)
        w.hint = UI.NewText(toggle)
        w.hint:SetPoint("LEFT", w.title, "RIGHT", 8, 0)
        header:Append(toggle)
        header:Append(UI.Make(ui, "Rule", header, {}))
        local reset = UI.Make(ui, "Link", header, { "reset", style = "fine" })
        reset.kitSection = w
        reset:SetOnClick(sectionReset)
        header:Append(reset)
        w.reset = reset

        local body = UI.Part(ui, w, "column", {})
        w:Append(body)
        w.kitInner = body
        w.body = body
    end,
    Init = function(w, spec)
        UI.SetStack(w, "column", { gap = spec.headerGap or 8 })
        UI.SetStack(w.body, "column", { gap = spec.gap or 8, padding = spec.padding })
        w.body.kitGrow = spec.grow and 1 or nil
        w.kitFoldable = spec.foldable and true or false
        w.kitOnToggle = spec.onToggle
        w.title:ClearAllPoints()
        w.title:SetPoint("LEFT", w.toggle, "LEFT", w.kitFoldable and 16 or 0, 0)
        w.title:SetText(spec[1] or "")
        w.hint:SetText(spec.hint or "")
        w.toggle:EnableMouse(w.kitFoldable)
        w.toggle.hover = nil
        w.reset:SetShown(spec.reset and true or false)
        w.kitOnReset = spec.reset and spec.reset.onReset
        w:SetOpen(spec.open ~= false)
        if spec.reset then w:SetStored(spec.reset.stored, spec.reset.default) end
        w.toggle:Changed()
    end,
    methods = {
        SetOpen = function(self, open)
            self.kitOpen = open and true or false
            self.body:SetShown(self.kitOpen)
            self.openGlyph:SetShown(self.kitFoldable and self.kitOpen)
            self.foldedGlyph:SetShown(self.kitFoldable and not self.kitOpen)
        end,
        IsOpen = function(self) return self.kitOpen end,
        SetHint = function(self, text)
            self.hint:SetText(text or "")
            self.toggle:Changed()
        end,
        SetCaption = function(self, text)
            self.title:SetText(text or "")
            self.toggle:Changed()
        end,
        SetStored = function(self, stored, defaultText)
            self.reset:SetShown(stored and true or false)
            self.reset:SetTooltip("Back to the default" .. (defaultText and (" (" .. defaultText .. ")") or "")
                .. ". Your choice is forgotten, so the default applies from now on.")
        end,
        Paint = function(self, t)
            UI.ApplyStyle(self.title, "heading", t)
            UI.ApplyStyle(self.hint, "label", t)
            self:PaintState(t)
            self.toggle:Changed()
        end,
        -- Hover: the heading and chevron in the accent.
        PaintState = function(self, t)
            local hover = self.toggle.hover
            UI.TextColor(self.title, hover and t.accent or t.text)
            local color = hover and t.accent or t.muted
            self.openGlyph:SetColor(color)
            self.foldedGlyph:SetColor(color)
        end,
    },
})

-- Tags ---------------------------------------------------------------------------------

-- A small label on a tinted plate: a count, a state, "needs pattern".
-- Spec: [1] the text, tone.
UI.Define("Tag", {
    stretch = false,
    Build = function(w)
        w.plate = UI.NewPlate(w)
        w.label = UI.NewText(w)
        w.label:SetPoint("CENTER", w, "CENTER", 0, 0)
    end,
    Init = function(w, spec)
        w.kitTone = spec.tone
        w.label:SetText(spec[1] or "")
    end,
    methods = {
        SetText = function(self, value)
            value = value or ""
            if value == self.label:GetText() then return end
            self.label:SetText(value)
            self:Changed()
        end,
        GetText = function(self) return self.label:GetText() end,
        SetTone = function(self, tone)
            self.kitTone = tone
            self:Paint(self.ui.tokens)
        end,
        Measure = function(self) return math.ceil(UI.StringWidth(self.label)) + 10, 16 end,
        Paint = function(self, t)
            local base = UI.Tone(t, self.kitTone) or t.muted
            self.plate:Flat(UI.Faded(t, base, 0.14), UI.Faded(t, base, 0.55))
            UI.ApplyStyle(self.label, "fine", t, base)
            self:Changed()
        end,
    },
})

-- Notices --------------------------------------------------------------------------------

local NOTICE_TONES = { info = "accent", warning = "warning", danger = "danger", success = "success" }
local NOTICE_MARK = { info = "i", warning = "!", danger = "x", success = "v" }

local function noticeDismiss(button)
    local w = button.kitNotice
    w:Hide()
    if w.kitOnDismiss then w.kitOnDismiss() end
end

-- A message in the flow of a window. Spec: [1] the text, tone (info,
-- warning, danger, success), action { caption, onClick } for a link under
-- it, dismiss for a close mark, onDismiss.
UI.Define("Notice", {
    wraps = true,
    Build = function(w)
        w:SetSize(1, 40)
        w.plate = UI.NewPlate(w)
        local badge = CreateFrame("Frame", nil, w)
        badge:SetSize(16, 16)
        badge:SetPoint("TOPLEFT", w, "TOPLEFT", 9, -9)
        w.badgeFill = badge:CreateTexture(nil, "ARTWORK")
        w.badgeFill:SetAllPoints()
        w.mark = UI.NewText(badge)
        w.mark:SetPoint("CENTER", badge, "CENTER", 0, 0)
        w.message = UI.NewText(w)
        if w.message.SetWordWrap then w.message:SetWordWrap(true) end
        w.message:SetJustifyV("TOP")
        w.message:SetPoint("TOPLEFT", w, "TOPLEFT", 33, -9)
    end,
    Init = function(w, spec)
        w.kitKind = NOTICE_TONES[spec.tone] and spec.tone or "info"
        w.kitDismiss = spec.dismiss and true or false
        w.kitOnDismiss = spec.onDismiss
        w.mark:SetText(NOTICE_MARK[w.kitKind])
        w.message:SetPoint("RIGHT", w, "RIGHT", w.kitDismiss and -28 or -10, 0)
        w.message:SetText(spec[1] or "")
        if spec.action then
            if not w.action then
                w.action = UI.Make(w.ui, "Link", w, { "" })
                w.action:SetPoint("TOPLEFT", w.message, "BOTTOMLEFT", 0, -4)
            end
            w.action:SetText(spec.action.caption or "")
            w.action:SetOnClick(spec.action.onClick)
            UI.Fit(w.action)
            w.action:Show()
        elseif w.action then
            w.action:Hide()
        end
        if w.kitDismiss then
            if not w.close then
                w.close = UI.Make(w.ui, "GlyphButton", w, { "close", size = 18 })
                w.close.kitNotice = w
                w.close:SetOnClick(noticeDismiss)
                w.close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -6, -6)
                UI.Fit(w.close)
            end
            w.close:Show()
        elseif w.close then
            w.close:Hide()
        end
    end,
    methods = {
        SetText = function(self, value)
            self.message:SetText(value or "")
            self:Changed()
        end,
        Measure = function(self, width)
            if width and width > 0 then self.message:SetWidth(width - 33 - (self.kitDismiss and 28 or 10)) end
            local height = 9 + (self.message:GetStringHeight() or 12) + 9
            if self.action and self.action:IsShown() then height = height + 4 + (self.action:GetHeight() or 14) end
            return 240, math.ceil(math.max(34, height))
        end,
        Paint = function(self, t)
            local base = UI.Tone(t, NOTICE_TONES[self.kitKind])
            self.plate:Flat(UI.Faded(t, base, 0.1), UI.Faded(t, base, 0.45))
            UI.TexColor(self.badgeFill, base)
            UI.ApplyStyle(self.mark, "fine", t, t.window)
            UI.ApplyStyle(self.message, "body", t)
            self:Changed()
        end,
    },
})

-- Cards ------------------------------------------------------------------------------------

-- A raised plate with a coloured rail down its left edge, holding what is
-- made in it as a column: the tracker's current step, a step kept on screen.
-- Spec: tone (the rail; accent by default), padding (12), gap (6).
local RAIL = 3

UI.Define("Card", {
    holds = true, fills = true,
    Build = function(w)
        w:SetSize(1, 1)
        w.plate = UI.NewPlate(w)
        w.rail = w:CreateTexture(nil, "ARTWORK")
        w.rail:SetPoint("TOPLEFT")
        w.rail:SetPoint("BOTTOMLEFT")
        UI.Stroke(w.rail, "width", RAIL)
        local body = CreateFrame("Frame", nil, w)
        UI.MakeStack(w.ui, body, "column", {})
        body.kitLayout = {}
        body.kitParent = w
        w.kitInner = body
        w.body = body
    end,
    Init = function(w, spec)
        w.kitTone = spec.tone
        w.kitPad = spec.padding or 12
        UI.SetStack(w.body, "column", { gap = spec.gap or 6 })
        local left, edge = UI.Snap(w, RAIL + w.kitPad), UI.Snap(w, w.kitPad)
        w.body:ClearAllPoints()
        w.body:SetPoint("TOPLEFT", w, "TOPLEFT", left, -edge)
        w.body:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -edge, edge)
    end,
    methods = {
        SetTone = function(self, tone)
            self.kitTone = tone
            self:Paint(self.ui.tokens)
        end,
        Measure = function(self, width)
            local left, edge = UI.Snap(self, RAIL + self.kitPad), UI.Snap(self, self.kitPad)
            local inner = width and (width - left - edge) or nil
            return self.body:NaturalWidth() + left + edge, self.body:NaturalHeight(inner) + 2 * edge
        end,
        Sized = function(self, width, height)
            local left, edge = UI.Snap(self, RAIL + self.kitPad), UI.Snap(self, self.kitPad)
            self.body.kitPW, self.body.kitPH = width - left - edge, height - 2 * edge
            UI.Invalidate(self.body)
        end,
        Paint = function(self, t)
            self.plate:Flat(t.raisedBg, t.hairline)
            UI.TexColor(self.rail, UI.Tone(t, self.kitTone) or t.accent)
        end,
    },
})
