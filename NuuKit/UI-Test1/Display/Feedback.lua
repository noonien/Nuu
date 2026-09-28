local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI1 = Kit.UI1 or {}
local UI = Kit.UI1

-- Progress bars and segment bars, as in UI/Display/Feedback.lua on shared
-- methods and pooling. (Notices are in Text.lua, the loading / empty / error
-- states are `stack:SetState`, the status strip is `window:Status`.)

local BAR = 8
-- Neither bar has a width of its own: across a column it is stretched, and
-- in a row or placed by the caller it starts at this. (UI/ left it at the
-- frame's width, 1, until the caller sized it.)
local NATURAL_WIDTH = 200

-- Progress bars ---------------------------------------------------------------------------

-- Spec: label, value, max, tone (the fill: accent by default), marks
-- ({ { at, caption, tone } } along the bar), busy (no end known: a run
-- moves along the track), showValue (false hides "value / max"), format
-- (fn(value, max) for the readout), barHeight (of the bar itself; `height`
-- is layout only).

local function hasLabelRow(w)
    return w.kitLabel ~= nil or (w.kitShowValue and not w.kitBusy)
end

local function hasMarkRow(w)
    for _, mark in ipairs(w.kitMarks) do if mark.caption then return true end end
    return false
end

local function barText(w)
    w.label:SetText(w.kitLabel or "")
    if not w.kitShowValue or w.kitBusy then
        w.readout:SetText("")
    elseif w.kitFormat then
        w.readout:SetText(w.kitFormat(w.kitValue, w.kitMax))
    else
        w.readout:SetText(w.kitValue .. " / " .. w.kitMax)
    end
end

-- Under reduceMotion the run sits still over the first third.
local function placeStillRun(w)
    w.run:ClearAllPoints()
    w.run:SetPoint("TOPLEFT", w.track, "TOPLEFT", 0, 0)
    w.run:SetPoint("BOTTOMLEFT", w.track, "BOTTOMLEFT", 0, 0)
    w.run:SetWidth(math.max(0.01, (w:GetWidth() or 0) * 0.33))
end

-- Every part where it goes for the bar's width.
local function placeBar(w)
    local top = UI.Snap(w, hasLabelRow(w) and 16 or 0)
    local track = w.track
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -top)
    track:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -top)
    UI.Stroke(track, "height", w.kitBarHeight)
    local width = w:GetWidth() or 0
    local max = w.kitMax
    local share = max > 0 and math.max(0, math.min(1, w.kitValue / max)) or 0
    w.fill:SetWidth(math.max(0.01, UI.Snap(w, width * share)))
    w.fill:SetShown(not w.kitBusy and share > 0)
    local over = UI.Snap(w, 3)
    for index, mark in ipairs(w.kitMarks) do
        local tick = w.markTicks[index]
        if not tick then
            tick = w:CreateTexture(nil, "OVERLAY")
            UI.Stroke(tick, "width", 2)
            w.markTicks[index] = tick
        end
        local mid = max > 0 and width * math.max(0, math.min(1, (mark.at or 0) / max)) or 0
        local x = UI.Snap(w, mid - 1)
        tick:ClearAllPoints()
        tick:SetPoint("TOPLEFT", track, "TOPLEFT", x, over)
        tick:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", x, -over)
        tick:Show()
        local caption = w.markLabels[index]
        if not caption then
            caption = UI.NewText(w)
            w.markLabels[index] = caption
        end
        caption:ClearAllPoints()
        caption:SetPoint("TOP", track, "BOTTOMLEFT", mid, -4)
        caption:SetText(mark.caption or "")
        caption:Show()
    end
    for index = #w.kitMarks + 1, #w.markTicks do
        w.markTicks[index]:Hide()
        w.markLabels[index]:Hide()
    end
    if w.kitBusy and not w.kitRunning then placeStillRun(w) end
end

local function barSized(w) placeBar(w) end

-- The run of a busy bar, moving along the track.
local function busyTick(w, elapsed)
    w.kitClock = (w.kitClock or 0) + (elapsed or 0)
    local width = w:GetWidth() or 0
    local runWidth = width * 0.3
    local x = ((w.kitClock * 0.6) % 1.3) * width - runWidth
    local run, track = w.run, w.track
    run:ClearAllPoints()
    run:SetPoint("TOP", track, "TOP", 0, 0)
    run:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    run:SetPoint("LEFT", track, "LEFT", UI.Snap(w, math.max(0, x)), 0)
    run:SetWidth(math.max(0.01, UI.Snap(w, math.min(runWidth, width - math.max(0, x), x + runWidth))))
end

local function stopBusy(w)
    w.kitRunning = false
    w:SetScript("OnUpdate", nil)
end

-- Starts or stills the run for the look's reduceMotion.
local function startBusy(w)
    w.kitReduced = w.ui.tokens.reduceMotion and true or false
    if not w.kitBusy then
        stopBusy(w)
        return
    end
    if w.kitReduced or not w:IsShown() then
        stopBusy(w)
        placeStillRun(w)
        return
    end
    w.kitClock = 0
    w.kitRunning = true
    w:SetScript("OnUpdate", busyTick)
end

local function barHidden(w) stopBusy(w) end
local function barShown(w) if w.kitBusy then startBusy(w) end end

UI.Define("ProgressBar", {
    Build = function(w)
        w:SetSize(1, 30)
        w.label = UI.NewText(w)
        w.label:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
        w.readout = UI.NewText(w)
        w.readout:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
        w.readout:SetJustifyH("RIGHT")
        w.track = w:CreateTexture(nil, "BACKGROUND")
        w.fill = w:CreateTexture(nil, "ARTWORK")
        w.fill:SetPoint("TOPLEFT", w.track, "TOPLEFT", 0, 0)
        w.fill:SetPoint("BOTTOMLEFT", w.track, "BOTTOMLEFT", 0, 0)
        w.run = w:CreateTexture(nil, "ARTWORK", nil, 1)
        w.run:Hide()
        w.markTicks, w.markLabels = {}, {}
        w:HookScript("OnSizeChanged", barSized)
        w:HookScript("OnHide", barHidden)
        w:HookScript("OnShow", barShown)
    end,
    Init = function(w, spec)
        w.kitLabel = spec.label
        w.kitValue, w.kitMax = spec.value or 0, spec.max or 1
        w.kitMarks = spec.marks or {}
        w.kitTone = spec.tone
        w.kitShowValue = spec.showValue ~= false
        w.kitFormat = spec.format
        w.kitBarHeight = spec.barHeight or BAR
        w.kitBusy = false
        stopBusy(w)
        w.run:Hide()
        barText(w)
        placeBar(w)
        if spec.busy then w:SetBusy(true) end
    end,
    Release = function(w)
        w.kitBusy = false
        stopBusy(w)
        w.run:Hide()
    end,
    methods = {
        SetValue = function(self, value, max)
            self.kitValue = value or 0
            if max then self.kitMax = max end
            barText(self)
            placeBar(self)
        end,
        GetValue = function(self) return self.kitValue end,
        SetMax = function(self, max) self:SetValue(self.kitValue, max) end,
        GetMax = function(self) return self.kitMax end,
        SetLabel = function(self, value)
            self.kitLabel = value
            barText(self)
            placeBar(self)
            self:Changed()
        end,
        SetMarks = function(self, marks)
            self.kitMarks = marks or {}
            placeBar(self)
            self:Paint(self.ui.tokens)
            self:Changed()
        end,
        SetTone = function(self, tone)
            self.kitTone = tone
            self:PaintState(self.ui.tokens)
        end,
        -- No end known: a run of the fill moves along the track, or under
        -- reduceMotion sits still over a third.
        SetBusy = function(self, busy)
            self.kitBusy = busy and true or false
            self.run:SetShown(self.kitBusy)
            barText(self)
            startBusy(self)
            placeBar(self)
            self:Changed()
        end,
        IsBusy = function(self) return self.kitBusy end,
        Measure = function(self)
            return NATURAL_WIDTH, (hasLabelRow(self) and 16 or 0) + self.kitBarHeight + (hasMarkRow(self) and 18 or 0) + 2
        end,
        Sized = function(self) placeBar(self) end,
        Paint = function(self, t)
            UI.ApplyStyle(self.label, "label", t, "text")
            UI.ApplyStyle(self.readout, "number", t, nil, true)
            for index = 1, #self.kitMarks do
                if self.markLabels[index] then UI.ApplyStyle(self.markLabels[index], "fine", t, nil, true) end
            end
            self:PaintState(t)
            -- A change of reduceMotion starts or stills the run.
            if self.kitBusy and (t.reduceMotion and true or false) ~= self.kitReduced then startBusy(self) end
            self:Changed()
        end,
        -- The tone's colours: fill, run, readout, marks.
        PaintState = function(self, t)
            local tone = self.kitTone
            local base = (tone ~= nil and tone ~= "accent") and UI.Tone(t, tone) or nil
            UI.TextColor(self.readout, base or t.text)
            UI.TexColor(self.track, t.hairline)
            local fill = base or t.accent
            UI.TexColor(self.fill, fill)
            UI.TexColor(self.run, fill, 0.8)
            for index, mark in ipairs(self.kitMarks) do
                local color = UI.Tone(t, mark.tone) or t.muted
                if self.markTicks[index] then UI.TexColor(self.markTicks[index], color) end
                if self.markLabels[index] then UI.TextColor(self.markLabels[index], color) end
            end
        end,
    },
})

-- Segment bars -------------------------------------------------------------------------------

-- A bar over a range of values, with coloured runs along it and marks at
-- points: the tracker's steps (done, skipped, the one you are on), a
-- recipe's difficulty bands with where you are and the target. Axes, ticks
-- and captions stay with the addon; `bar:XOf(value)` says where a value
-- falls, so it can draw them in line. Spec:
--   min, max        the range (0 to 1 by default); values are continuous, so
--                   step i of n is the run from i - 1 to i on 0 to n
--   segments        { { from, to, tone (a tone, token or colour),
--                   style ("fill", or "outline" for a run that is not
--                   certain), alpha } }
--   marks           { { at, tone, kind ("line" across the bar and a little
--                   beyond, or "pointer" above it) } }
--   barHeight       of the bar itself (8); `height` is layout only
--   tooltipFor(value)  what the value under the cursor is; a line follows
--                   it (not `tooltip`, which is any widget's own)
--   onPick(value)   a click on the bar; with `scrub`, dragging picks too
local SEGMENT_OVER, POINTER = 3, 8

local function room(w)
    local above, below = 0, 0
    for _, mark in ipairs(w.kitMarks) do
        if mark.kind == "pointer" then
            above = math.max(above, POINTER)
        else
            above = math.max(above, SEGMENT_OVER)
            below = SEGMENT_OVER
        end
    end
    return above, below
end

local function newOutline(w)
    local box = CreateFrame("Frame", nil, w)
    box.plate = UI.NewPlate(box, "ARTWORK")
    return box
end

local function newPointer(w)
    local p = CreateFrame("Frame", nil, w)
    p:SetSize(10, 6)
    p.glyph = UI.NewGlyph(p, "down", 9, 1.8)
    return p
end

-- Every edge on a whole screen pixel; a run never thinner than one.
local function placeSegments(w)
    local above = room(w)
    local top = UI.Snap(w, above)
    local h = UI.Snap(w, w.kitBarHeight)
    local one = UI.Pixels(w, 1)
    local track = w.track
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -top)
    track:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -top)
    track:SetHeight(h)
    local pools = w.kitParts
    local fills, outlines = 0, 0
    for _, segment in ipairs(w.kitSegments) do
        local left = UI.Snap(w, w:XOf(segment.from or w.kitMin))
        local right = math.max(left + one, UI.Snap(w, w:XOf(segment.to or w.kitMax)))
        local part
        if segment.style == "outline" then
            outlines = outlines + 1
            part = pools.outlines[outlines]
            if not part then
                part = newOutline(w)
                pools.outlines[outlines] = part
            end
        else
            fills = fills + 1
            part = pools.fills[fills]
            if not part then
                part = w:CreateTexture(nil, "ARTWORK")
                pools.fills[fills] = part
            end
        end
        part.kitSegment = segment
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", track, "TOPLEFT", left, 0)
        part:SetSize(right - left, h)
        part:Show()
    end
    for index = fills + 1, #pools.fills do
        pools.fills[index]:Hide()
        pools.fills[index].kitSegment = nil
    end
    for index = outlines + 1, #pools.outlines do
        pools.outlines[index]:Hide()
        pools.outlines[index].kitSegment = nil
    end
    local lines, pointers = 0, 0
    local over = UI.Snap(w, SEGMENT_OVER)
    for _, mark in ipairs(w.kitMarks) do
        local x = UI.Snap(w, w:XOf(mark.at or w.kitMin))
        if mark.kind == "pointer" then
            pointers = pointers + 1
            local holder = pools.pointers[pointers]
            if not holder then
                holder = newPointer(w)
                pools.pointers[pointers] = holder
            end
            holder.kitMark = mark
            holder:ClearAllPoints()
            holder:SetPoint("BOTTOM", track, "TOPLEFT", x, UI.Pixels(w, 1))
            holder:Show()
        else
            lines = lines + 1
            local line = pools.lines[lines]
            if not line then
                line = w:CreateTexture(nil, "OVERLAY")
                UI.Hairline(line, "width")
                pools.lines[lines] = line
            end
            line.kitMark = mark
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", track, "TOPLEFT", x, over)
            line:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", x, -over)
            line:Show()
        end
    end
    for index = lines + 1, #pools.lines do
        pools.lines[index]:Hide()
        pools.lines[index].kitMark = nil
    end
    for index = pointers + 1, #pools.pointers do
        pools.pointers[index]:Hide()
        pools.pointers[index].kitMark = nil
    end
end

local function segmentsSized(w) placeSegments(w) end

local function colorOf(t, tone, fallback)
    if tone == nil then return fallback end
    return UI.Tone(t, tone) or UI.Colour(t, tone) or fallback
end

-- Pointing, clicking and dragging: the value under the cursor.
local function cursorValue(w)
    if type(GetCursorPosition) ~= "function" then return nil end
    local x = GetCursorPosition()
    local scale = w:GetEffectiveScale() or 1
    local left = w:GetLeft()
    if not x or not left then return nil end
    return w:ValueAt(x / scale - left), UI.Snap(w, x / scale - left)
end

-- Each frame while the cursor is on the bar or it is being scrubbed.
local function follow(w)
    local value, x = cursorValue(w)
    if not value then return end
    if w.kitHover then
        local over = UI.Snap(w, SEGMENT_OVER)
        local line = w.hoverLine
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", w.track, "TOPLEFT", x, over)
        line:SetPoint("BOTTOMLEFT", w.track, "BOTTOMLEFT", x, -over)
        line:Show()
        if w.kitTooltipFor then
            local text = w.kitTooltipFor(value)
            if text ~= w.kitShownTip then
                w.kitShownTip = text
                if text then w.ui:Tooltip(w, text) else w.ui:HideTooltip() end
            end
        end
    end
    if w.kitScrubbing then
        if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
            w.kitScrubbing = false
        elseif w.kitOnPick and value ~= w.kitPicked then
            w.kitPicked = value
            w.kitOnPick(value)
        end
    end
end

local function segEnter(w)
    if not w.kitInteractive then return end
    w.kitHover = true
    w.kitShownTip = nil
    w:SetScript("OnUpdate", follow)
    follow(w)
end

local function segLeave(w)
    if not w.kitInteractive then return end
    w.kitHover = false
    w.hoverLine:Hide()
    if w.kitTooltipFor then w.ui:HideTooltip() end
    if not w.kitScrubbing then w:SetScript("OnUpdate", nil) end
end

local function segDown(w, button)
    if not w.kitInteractive or button ~= "LeftButton" then return end
    local value = cursorValue(w)
    if value and w.kitOnPick then
        w.kitPicked = value
        w.kitOnPick(value)
    end
    if w.kitScrub then
        w.kitScrubbing = true
        w:SetScript("OnUpdate", follow)
    end
end

local function segUp(w)
    w.kitScrubbing = false
    if not w.kitHover then w:SetScript("OnUpdate", nil) end
end

-- Hover, scrub and the follow stop together.
local function segStop(w)
    w.kitScrubbing, w.kitHover, w.kitShownTip, w.kitPicked = false, false, nil, nil
    w.hoverLine:Hide()
    w:SetScript("OnUpdate", nil)
end

UI.Define("SegmentBar", {
    Build = function(w)
        w:SetSize(1, 1)
        w.track = w:CreateTexture(nil, "BACKGROUND")
        w.kitParts = { fills = {}, outlines = {}, lines = {}, pointers = {} }
        w.hoverLine = w:CreateTexture(nil, "OVERLAY", nil, 2)
        UI.Hairline(w.hoverLine, "width")
        w.hoverLine:Hide()
        w:SetScript("OnEnter", segEnter)
        w:SetScript("OnLeave", segLeave)
        w:SetScript("OnMouseDown", segDown)
        w:SetScript("OnMouseUp", segUp)
        w:HookScript("OnHide", segStop)
        w:HookScript("OnSizeChanged", segmentsSized)
    end,
    Init = function(w, spec)
        w.kitMin, w.kitMax = spec.min or 0, spec.max or 1
        w.kitSegments, w.kitMarks = spec.segments or {}, spec.marks or {}
        w.kitBarHeight = spec.barHeight or BAR
        w.kitTooltipFor, w.kitOnPick, w.kitScrub = spec.tooltipFor, spec.onPick, spec.scrub and true or false
        w.kitInteractive = (spec.tooltipFor or spec.onPick) and true or false
        w:EnableMouse(w.kitInteractive or spec.tooltip ~= nil)
        segStop(w)
        placeSegments(w)
    end,
    Release = segStop,
    methods = {
        XOf = function(self, value)
            local span = self.kitMax - self.kitMin
            if span <= 0 then return 0 end
            local share = math.max(0, math.min(1, (value - self.kitMin) / span))
            return share * (self:GetWidth() or 0)
        end,
        ValueAt = function(self, x)
            local width = self:GetWidth() or 0
            if width <= 0 then return self.kitMin end
            local share = math.max(0, math.min(1, x / width))
            return self.kitMin + share * (self.kitMax - self.kitMin)
        end,
        SetRange = function(self, min, max)
            self.kitMin, self.kitMax = min or 0, max or 1
            placeSegments(self)
        end,
        GetRange = function(self) return self.kitMin, self.kitMax end,
        SetSegments = function(self, segments)
            self.kitSegments = segments or {}
            placeSegments(self)
            self:Paint(self.ui.tokens)
        end,
        SetMarks = function(self, marks)
            local above, below = room(self)
            self.kitMarks = marks or {}
            placeSegments(self)
            self:Paint(self.ui.tokens)
            local newAbove, newBelow = room(self)
            if newAbove ~= above or newBelow ~= below then self:Changed() end
        end,
        Measure = function(self)
            local above, below = room(self)
            return NATURAL_WIDTH, self.kitBarHeight + above + below
        end,
        Sized = function(self) placeSegments(self) end,
        Paint = function(self, t)
            local parts = self.kitParts
            UI.TexColor(self.track, t.hairline)
            for _, part in ipairs(parts.fills) do
                local segment = part.kitSegment
                if segment then UI.TexColor(part, colorOf(t, segment.tone, t.accent), segment.alpha) end
            end
            for _, part in ipairs(parts.outlines) do
                local segment = part.kitSegment
                if segment then
                    local color = colorOf(t, segment.tone, t.accent)
                    part.plate:Flat(UI.Faded(t, color, 0.12 * (segment.alpha or 1)), color)
                end
            end
            for _, line in ipairs(parts.lines) do
                if line.kitMark then UI.TexColor(line, colorOf(t, line.kitMark.tone, t.text)) end
            end
            for _, holder in ipairs(parts.pointers) do
                if holder.kitMark then holder.glyph:SetColor(colorOf(t, holder.kitMark.tone, t.text)) end
            end
            UI.TexColor(self.hoverLine, t.text, 0.6)
        end,
    },
})
