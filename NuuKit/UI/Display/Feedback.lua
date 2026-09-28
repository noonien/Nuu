local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Progress bars. (Notices are in Text.lua, the loading / empty / error
-- states are `container:SetState`, the status strip is `window:Status`.)
--
-- `opts`: label, value, max, tone (the fill: accent by default), marks
-- ({ { at, caption, tone } } along the bar), busy (no end known: a run
-- moves along the track), showValue (false hides "value / max"), height of
-- the bar.
local BAR = 8

UI.Define("ProgressBar", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 30)
    local barHeight = opts.height or BAR
    local label = UI.NewText(frame)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    local readout = UI.NewText(frame)
    readout:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    readout:SetJustifyH("RIGHT")
    local track = frame:CreateTexture(nil, "BACKGROUND")
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
    local run = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    run:SetPoint("TOP", track, "TOP", 0, 0)
    run:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    run:Hide()
    frame.markTicks, frame.markLabels = {}, {}
    frame.kitValue, frame.kitMax = opts.value or 0, opts.max or 1
    frame.kitMarks = opts.marks or {}

    local function hasLabelRow() return (opts.label ~= nil) or (opts.showValue ~= false and not frame.kitBusy) end
    local function markRow()
        for _, mark in ipairs(frame.kitMarks) do if mark.caption then return true end end
        return false
    end
    local function place()
        local top = hasLabelRow() and 16 or 0
        track:ClearAllPoints()
        top = UI.Snap(frame, top)
        track:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
        track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -top)
        UI.Stroke(track, "height", barHeight)
        local width = frame:GetWidth() or 0
        local share = frame.kitMax > 0 and math.max(0, math.min(1, frame.kitValue / frame.kitMax)) or 0
        fill:SetWidth(math.max(0.01, UI.Snap(frame, width * share)))
        fill:SetShown(not frame.kitBusy and share > 0)
        for index, mark in ipairs(frame.kitMarks) do
            local tick = frame.markTicks[index] or frame:CreateTexture(nil, "OVERLAY")
            frame.markTicks[index] = tick
            local x = frame.kitMax > 0 and width * math.max(0, math.min(1, mark.at / frame.kitMax)) or 0
            local mid = x
            x = UI.Snap(frame, x - 1)
            local over = UI.Snap(frame, 3)
            tick:ClearAllPoints()
            tick:SetPoint("TOPLEFT", track, "TOPLEFT", x, over)
            tick:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", x, -over)
            UI.Stroke(tick, "width", 2)
            tick:Show()
            local caption = frame.markLabels[index] or UI.NewText(frame)
            frame.markLabels[index] = caption
            caption:ClearAllPoints()
            caption:SetPoint("TOP", track, "BOTTOMLEFT", mid, -4)
            caption:SetText(mark.caption or "")
        end
        for index = #frame.kitMarks + 1, #frame.markTicks do
            frame.markTicks[index]:Hide()
            frame.markLabels[index]:Hide()
        end
    end
    frame.KitNaturalHeight = function()
        return (hasLabelRow() and 16 or 0) + barHeight + (markRow() and 18 or 0) + 2
    end

    local function text()
        label:SetText(opts.label or "")
        if opts.showValue == false or frame.kitBusy then
            readout:SetText("")
        else
            readout:SetText(opts.format and opts.format(frame.kitValue, frame.kitMax) or (frame.kitValue .. " / " .. frame.kitMax))
        end
    end

    function frame:SetValue(value, max)
        self.kitValue = value or 0
        if max then self.kitMax = max end
        text()
        place()
    end
    function frame:SetMax(max) self:SetValue(self.kitValue, max) end
    function frame:SetLabel(value) opts.label = value; text(); place() end
    function frame:SetMarks(marks) self.kitMarks = marks or {}; place(); self:Repaint() end
    function frame:SetTone(tone) opts.tone = tone; self:Repaint() end
    -- No end known: a run of the fill moves along the track, or under
    -- reduceMotion sits still at a third.
    function frame:SetBusy(busy)
        self.kitBusy = busy and true or false
        run:SetShown(self.kitBusy)
        text()
        place()
        if self.kitParentContainer then UI.Invalidate(self.kitParentContainer) end
        if self.kitBusy and not ui.tokens.reduceMotion then
            self.kitClock = 0
            self:SetScript("OnUpdate", function(f, elapsed)
                f.kitClock = (f.kitClock or 0) + elapsed
                local width = f:GetWidth() or 0
                local runWidth = width * 0.3
                local x = ((f.kitClock * 0.6) % 1.3) * width - runWidth
                run:ClearAllPoints()
                run:SetPoint("TOP", track, "TOP", 0, 0)
                run:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
                run:SetPoint("LEFT", track, "LEFT", UI.Snap(frame, math.max(0, x)), 0)
                run:SetWidth(math.max(0.01, UI.Snap(frame, math.min(runWidth, width - math.max(0, x), x + runWidth))))
            end)
        else
            self:SetScript("OnUpdate", nil)
            if self.kitBusy then
                run:ClearAllPoints()
                run:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
                run:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
                run:SetWidth(math.max(0.01, (self:GetWidth() or 0) * 0.33))
            end
        end
    end
    frame:HookScript("OnSizeChanged", place)
    frame:HookScript("OnHide", function(f) f:SetScript("OnUpdate", nil) end)
    frame:HookScript("OnShow", function(f) if f.kitBusy then f:SetBusy(true) end end)
    text()
    place()
    if opts.busy then frame:SetBusy(true) end
    frame.kitLayout = UI.LayoutOptions(opts, "height")
    return ui:Finish(frame, opts, function(f, t)
        UI.ApplyStyle(label, "label", t, "text")
        UI.ApplyStyle(readout, "number", t, (opts.tone and opts.tone ~= "accent" and UI.ToneColor(t, opts.tone)) or t.text)
        UI.TexColor(track, t.hairline)
        local tone = UI.ToneColor(t, opts.tone) or t.accent
        if opts.tone == "accent" or not opts.tone then tone = t.accent end
        UI.TexColor(fill, tone)
        UI.TexColor(run, UI.Alpha(tone, 0.8))
        for index, mark in ipairs(f.kitMarks) do
            local color = UI.ToneColor(t, mark.tone) or t.muted
            if f.markTicks[index] then UI.TexColor(f.markTicks[index], color) end
            if f.markLabels[index] then UI.ApplyStyle(f.markLabels[index], "fine", t, color) end
        end
        if ui.tokens.reduceMotion ~= f.kitReduced then
            f.kitReduced = ui.tokens.reduceMotion
            if f.kitBusy then f:SetBusy(true) end
        end
    end)
end)

-- Segment bars -------------------------------------------------------------------------------

-- A bar over a range of values, with coloured runs along it and marks at
-- points: the tracker's steps (done, skipped, the one you are on), a
-- recipe's difficulty bands with where you are and the target. Axes, ticks
-- and captions stay with the addon; `bar:XOf(value)` says where a value
-- falls, so it can draw them in line. `opts`:
--   min, max        the range (0 to 1 by default); values are continuous, so
--                   step i of n is the run from i - 1 to i on 0 to n
--   segments        { { from, to, tone (a tone, token or colour),
--                   style ("fill", or "outline" for a run that is not
--                   certain), alpha } }
--   marks           { { at, tone, kind ("line" across the bar and a little
--                   beyond, or "pointer" above it) } }
--   height          of the bar itself (8)
--   tooltipFor(value)  what the value under the cursor is; a line follows
--                   it (not `tooltip`, which is any widget's own)
--   onPick(value)   a click on the bar; with `scrub`, dragging picks too
local SEGMENT_OVER, POINTER = 3, 8

UI.Define("SegmentBar", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame.kitMin, frame.kitMax = opts.min or 0, opts.max or 1
    frame.kitSegments, frame.kitMarks = opts.segments or {}, opts.marks or {}
    local barHeight = opts.height or BAR
    local track = frame:CreateTexture(nil, "BACKGROUND")
    local pools = { fills = {}, outlines = {}, lines = {}, pointers = {} }
    local hoverLine = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    UI.Hairline(hoverLine, "width")
    hoverLine:Hide()

    local function room()
        local above, below = 0, 0
        for _, mark in ipairs(frame.kitMarks) do
            if mark.kind == "pointer" then above = math.max(above, POINTER) else above = math.max(above, SEGMENT_OVER); below = SEGMENT_OVER end
        end
        return above, below
    end
    frame.KitNaturalWidth = function() return 200 end
    frame.KitNaturalHeight = function()
        local above, below = room()
        return barHeight + above + below
    end

    function frame:XOf(value)
        local span = self.kitMax - self.kitMin
        if span <= 0 then return 0 end
        local share = math.max(0, math.min(1, (value - self.kitMin) / span))
        return share * (self:GetWidth() or 0)
    end
    function frame:ValueAt(x)
        local width = self:GetWidth() or 0
        if width <= 0 then return self.kitMin end
        local share = math.max(0, math.min(1, x / width))
        return self.kitMin + share * (self.kitMax - self.kitMin)
    end

    local function take(pool, index, make)
        local item = pool[index]
        if not item then item = make(); pool[index] = item end
        return item
    end
    -- Every edge on a whole screen pixel; a run never thinner than one.
    local function place()
        local f = frame
        local above = room()
        local top = UI.Snap(f, above)
        local h = UI.Snap(f, barHeight)
        local one = UI.Pixels(f, 1)
        track:ClearAllPoints()
        track:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
        track:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
        track:SetHeight(h)
        local fills, outlines = 0, 0
        for _, segment in ipairs(f.kitSegments) do
            local left = UI.Snap(f, f:XOf(segment.from or f.kitMin))
            local right = math.max(left + one, UI.Snap(f, f:XOf(segment.to or f.kitMax)))
            local part
            if segment.style == "outline" then
                outlines = outlines + 1
                part = take(pools.outlines, outlines, function()
                    local box = CreateFrame("Frame", nil, f)
                    box.plate = UI.NewPlate(box, "ARTWORK")
                    return box
                end)
            else
                fills = fills + 1
                part = take(pools.fills, fills, function() return f:CreateTexture(nil, "ARTWORK") end)
            end
            part.kitSegment = segment
            part:ClearAllPoints()
            part:SetPoint("TOPLEFT", track, "TOPLEFT", left, 0)
            part:SetSize(right - left, h)
            part:Show()
        end
        for index = fills + 1, #pools.fills do pools.fills[index]:Hide() end
        for index = outlines + 1, #pools.outlines do pools.outlines[index]:Hide() end
        local lines, pointers = 0, 0
        local over = UI.Snap(f, SEGMENT_OVER)
        for _, mark in ipairs(f.kitMarks) do
            local x = UI.Snap(f, f:XOf(mark.at or f.kitMin))
            if mark.kind == "pointer" then
                pointers = pointers + 1
                local holder = take(pools.pointers, pointers, function()
                    local p = CreateFrame("Frame", nil, f)
                    p:SetSize(10, 6)
                    p.glyph = UI.NewGlyph(p, "down", 9, 1.8)
                    return p
                end)
                holder.kitMark = mark
                holder:ClearAllPoints()
                holder:SetPoint("BOTTOM", track, "TOPLEFT", x, UI.Pixels(f, 1))
                holder:Show()
            else
                lines = lines + 1
                local line = take(pools.lines, lines, function()
                    local l = f:CreateTexture(nil, "OVERLAY")
                    UI.Hairline(l, "width")
                    return l
                end)
                line.kitMark = mark
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", track, "TOPLEFT", x, over)
                line:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", x, -over)
                line:Show()
            end
        end
        for index = lines + 1, #pools.lines do pools.lines[index]:Hide() end
        for index = pointers + 1, #pools.pointers do pools.pointers[index]:Hide() end
    end
    frame.KitSized = place
    frame:HookScript("OnSizeChanged", place)

    local function colorOf(t, tone, fallback)
        if tone == nil then return fallback end
        return UI.ToneColor(t, tone) or UI.TokenColor(t, tone) or fallback
    end
    local function paint(f, t)
        UI.TexColor(track, t.hairline)
        for _, part in ipairs(pools.fills) do
            local segment = part.kitSegment
            if segment then UI.TexColor(part, colorOf(t, segment.tone, t.accent), segment.alpha) end
        end
        for _, part in ipairs(pools.outlines) do
            local segment = part.kitSegment
            if segment then
                local color = colorOf(t, segment.tone, t.accent)
                part.plate:Flat(UI.Alpha(color, 0.12 * (segment.alpha or 1)), color)
            end
        end
        for _, line in ipairs(pools.lines) do
            if line.kitMark then UI.TexColor(line, colorOf(t, line.kitMark.tone, t.text)) end
        end
        for _, holder in ipairs(pools.pointers) do
            if holder.kitMark then holder.glyph:SetColor(colorOf(t, holder.kitMark.tone, t.text)) end
        end
        UI.TexColor(hoverLine, t.text, 0.6)
    end

    function frame:SetRange(min, max)
        self.kitMin, self.kitMax = min or 0, max or 1
        place()
    end
    function frame:SetSegments(segments)
        self.kitSegments = segments or {}
        place()
        if self.Repaint then self:Repaint() end
    end
    function frame:SetMarks(marks)
        local before = select(1, room())
        self.kitMarks = marks or {}
        place()
        if self.Repaint then self:Repaint() end
        if select(1, room()) ~= before and self.kitParentContainer then UI.Invalidate(self.kitParentContainer) end
    end

    -- Pointing, clicking and dragging: the value under the cursor.
    local function cursorValue()
        if type(GetCursorPosition) ~= "function" then return nil end
        local x = GetCursorPosition()
        local scale = frame:GetEffectiveScale() or 1
        local left = frame:GetLeft()
        if not left then return nil end
        return frame:ValueAt(x / scale - left), UI.Snap(frame, x / scale - left)
    end
    local interactive = opts.tooltipFor or opts.onPick
    if interactive then
        frame:EnableMouse(true)
        local shownValue, scrubbing, picked
        local function follow()
            local value, x = cursorValue()
            if not value then return end
            if frame.kitHover then
                hoverLine:ClearAllPoints()
                hoverLine:SetPoint("TOPLEFT", track, "TOPLEFT", x, UI.Snap(frame, SEGMENT_OVER))
                hoverLine:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", x, -UI.Snap(frame, SEGMENT_OVER))
                hoverLine:Show()
                if opts.tooltipFor then
                    local text = opts.tooltipFor(value)
                    if text ~= shownValue then
                        shownValue = text
                        if text then ui:Tooltip(frame, text) else ui:HideTooltip() end
                    end
                end
            end
            if scrubbing then
                if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
                    scrubbing = false
                elseif opts.onPick and value ~= picked then
                    picked = value
                    opts.onPick(value)
                end
            end
        end
        frame:SetScript("OnEnter", function(f)
            f.kitHover = true
            shownValue = nil
            f:SetScript("OnUpdate", follow)
            follow()
        end)
        frame:SetScript("OnLeave", function(f)
            f.kitHover = false
            hoverLine:Hide()
            if opts.tooltipFor then ui:HideTooltip() end
            if not scrubbing then f:SetScript("OnUpdate", nil) end
        end)
        frame:SetScript("OnMouseDown", function(f, button)
            if button ~= "LeftButton" then return end
            local value = cursorValue()
            if value and opts.onPick then
                picked = value
                opts.onPick(value)
            end
            if opts.scrub then
                scrubbing = true
                f:SetScript("OnUpdate", follow)
            end
        end)
        frame:SetScript("OnMouseUp", function(f)
            scrubbing = false
            if not f.kitHover then f:SetScript("OnUpdate", nil) end
        end)
        frame:HookScript("OnHide", function(f)
            scrubbing, f.kitHover = false, false
            hoverLine:Hide()
            f:SetScript("OnUpdate", nil)
        end)
    end

    place()
    frame.kitLayout = UI.LayoutOptions(opts, "height")
    return ui:Finish(frame, opts, paint)
end)
