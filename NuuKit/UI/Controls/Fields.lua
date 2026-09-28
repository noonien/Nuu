local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Fields, toggles and sliders, ported from OpenRoad's Theme:Input, Toggle
-- and Slider.
--
-- A field is a small column: an optional `label` over the box, and under it
-- a line for `help` or for why the text is wrong. Methods on the field:
-- GetText, SetText, SetInvalid(message or nil), SetFocus, ClearFocus,
-- SetEnabled, SetPlaceholder. `field.box` is the EditBox itself.

local BOX_HEIGHT = 24
local LABEL_GAP, MESSAGE_GAP = 4, 3

-- The room a field's label takes above its box. Worked out from the font
-- size, not the string's height: that reads 0 until the client first draws
-- the label, and a field measured then comes out short. At the kit's 11 point
-- body size it is 16, the same as a Select's.
local function labelBand(frame)
    if not frame.label then return 0 end
    local _, size = frame.label:GetFont()
    return math.max(12, math.ceil(size or 12)) + LABEL_GAP
end

-- The frame around a box: label above, message below, and a row for the box
-- and anything beside it (a preview, the - and + of a number).
local function fieldFrame(ui, parent, opts)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(opts.width or 1, BOX_HEIGHT)
    if opts.width then frame.kitStretch = false end
    if opts.label then
        frame.label = UI.NewText(frame)
        frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.label:SetText(opts.label)
    end
    frame.message = UI.NewText(frame)
    if frame.message.SetWordWrap then frame.message:SetWordWrap(true) end
    frame.message:SetJustifyV("TOP")
    frame.message:Hide()
    frame.line = CreateFrame("Frame", nil, frame)
    frame.line:SetHeight(opts.boxHeight or BOX_HEIGHT)
    frame.kitBoxHeight = opts.boxHeight or BOX_HEIGHT
    frame.help = opts.help

    local function place(f)
        local top = UI.Snap(f, labelBand(f))
        f.line:ClearAllPoints()
        f.line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
        f.line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
        f.line:SetHeight(UI.Snap(f, f.kitBoxHeight))
        f.message:ClearAllPoints()
        f.message:SetPoint("TOPLEFT", f.line, "BOTTOMLEFT", 0, -MESSAGE_GAP)
        f.message:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    end
    frame.KitNaturalWidth = function(f) return opts.width or f.kitMinWidth or 160 end
    frame.KitNaturalHeight = function(f, width)
        local h = f.kitBoxHeight + labelBand(f)
        if f.message:IsShown() then
            if width and width > 0 then f.message:SetWidth(width) end
            h = h + MESSAGE_GAP + (f.message:GetStringHeight() or 12)
        end
        return math.ceil(h)
    end
    frame:HookScript("OnSizeChanged", place)
    frame.KitSized = place
    -- In a row, fields line up by their tops, so a help line under one does
    -- not lift its box above the others.
    frame.kitRowAlign = "top"
    place(frame)

    -- Shows `text` under the box (nil: the help line, if any).
    function frame:ShowMessage(text, isError)
        local value = text or self.help
        self.kitMessageError = text ~= nil and isError
        self.message:SetText(value or "")
        self.message:SetShown(value ~= nil and value ~= "")
        if self.kitParentContainer then UI.Invalidate(self.kitParentContainer) end
        -- Builders call this before Finish gives the field Repaint; Finish paints it then.
        if self.Repaint then self:Repaint() end
    end
    function frame:SetLabel(text)
        if self.label then self.label:SetText(text or "") end
        place(self)
    end
    return frame
end

local function paintFieldFrame(frame, t)
    if frame.label then
        UI.ApplyStyle(frame.label, "label", t, "text")
        -- A new text size moves the box, and the field grows or shrinks.
        local band = labelBand(frame)
        if frame.kitLabelBand and frame.kitLabelBand ~= band then
            frame:KitSized()
            if frame.kitParentContainer then UI.Invalidate(frame.kitParentContainer) end
        end
        frame.kitLabelBand = band
    end
    UI.ApplyStyle(frame.message, "fine", t, frame.kitMessageError and "danger" or "muted")
end

-- An EditBox with the kit's plate, placeholder and commit behaviour: focus
-- selects the text, Enter commits and leaves, leaving by a click or Tab
-- commits if the text changed, Escape puts back what was there.
local function newBox(ui, frame, opts, multiLine)
    local box = CreateFrame("EditBox", nil, multiLine and frame.scrollContent or frame.line)
    box.kitField = true
    box:SetAutoFocus(false)
    box:SetFont(UI.FontFile(), 11, "")
    box:SetTextInsets(opts.insetLeft or 7, 7, 2, 2)
    if multiLine then
        box:SetMultiLine(true)
    end
    box.plate = UI.NewPlate(multiLine and frame.boxFrame or box)
    box.placeholder = UI.NewText(multiLine and frame.boxFrame or box)
    box.placeholder:SetPoint("TOPLEFT", box, "TOPLEFT", opts.insetLeft or 8, multiLine and -4 or 0)
    if not multiLine then
        box.placeholder:ClearAllPoints()
        box.placeholder:SetPoint("LEFT", box, "LEFT", opts.insetLeft or 8, 0)
    end
    box.placeholder:SetText(opts.placeholder or "")
    box.kitFrame = frame

    local function refreshPlaceholder(b)
        if (b.placeholder:GetText() or "") == "" or (b:GetText() or "") ~= "" then b.placeholder:Hide(); return end
        -- At rest in full, so coin colours in it read true; dimmed while typing.
        b.placeholder:SetAlpha(b:HasFocus() and 0.45 or 1)
        b.placeholder:Show()
    end
    box.RefreshPlaceholder = refreshPlaceholder

    local function commit(b)
        if b.kitBaseline == nil then return end
        local text = b:GetText() or ""
        if text == b.kitBaseline then return end
        if frame.kitValidate then
            local problem = frame.kitValidate(text)
            if problem then
                frame:SetInvalid(problem)
                return
            end
        end
        b.kitBaseline = text
        if frame.kitCommit then frame.kitCommit(text, frame) end
    end
    local function commitAndLeave(b)
        commit(b)
        b:ClearFocus()
    end
    box:SetScript("OnEditFocusGained", function(b)
        b.kitBaseline = b:GetText() or ""
        if not multiLine then b:HighlightText() end
        refreshPlaceholder(b)
        frame:Repaint()
    end)
    box:SetScript("OnEditFocusLost", function(b)
        commit(b)
        b.kitBaseline = nil
        if b.HighlightText then b:HighlightText(0, 0) end
        refreshPlaceholder(b)
        frame:Repaint()
    end)
    if not multiLine then box:SetScript("OnEnterPressed", commitAndLeave) end
    box:SetScript("OnEscapePressed", function(b)
        if b.kitBaseline ~= nil then b:SetText(b.kitBaseline) end
        b:ClearFocus()
    end)
    box:SetScript("OnTextChanged", function(b, userInput)
        if userInput and frame.kitInvalid then frame:SetInvalid(nil) end
        refreshPlaceholder(b)
        if userInput and frame.kitOnType then frame.kitOnType(b:GetText() or "", frame) end
    end)
    -- Tab moves through the window's fields in the order they were made.
    box:SetScript("OnTabPressed", function(b)
        local win = UI.WindowOf(b)
        if not win then return end
        local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
        local nextField = UI.NextFocus(win, b, shift and -1 or 1, not win.kitKeyboard)
        if nextField then
            if win.kitKeyboard then UI.FocusWidget(win, nextField) elseif nextField.SetFocus then nextField:SetFocus() end
        end
    end)
    UI.RegisterFocusable(ui, box, true)
    refreshPlaceholder(box)
    return box
end

local function paintBox(frame, t)
    local box = frame.box
    local focused = box:HasFocus()
    local edge = frame.kitInvalid and t.danger or (focused and t.accent or t.border)
    local fill = focused and t.raised or t.surface
    local enabled = not box.IsEnabled or box:IsEnabled()
    if not enabled then fill, edge = t.surface, t.border50 end
    box.plate:Flat(fill, edge)
    local style = UI.textStyles[frame.kitTextStyle or "body"]
    pcall(box.SetFont, box, UI.FontFile(style.face), math.floor(style.size * (t.textScale or 1) + 0.5), "")
    local ink = enabled and (UI.TokenColor(t, frame.kitInk) or t.text) or t.muted45
    box:SetTextColor(ink[1], ink[2], ink[3], ink[4] or 1)
    box:SetShadowColor(0, 0, 0, 0.9)
    box:SetShadowOffset(1, -1)
    UI.ApplyStyle(box.placeholder, "body", t, frame.kitPlaceholderColor or "muted")
    paintFieldFrame(frame, t)
end

-- The methods every field shares.
local function fieldMethods(frame)
    local box = frame.box
    function frame:GetText() return box:GetText() or "" end
    function frame:SetText(text)
        box:SetText(text == nil and "" or tostring(text))
        if box.kitBaseline ~= nil then box.kitBaseline = box:GetText() end
        box:RefreshPlaceholder()
    end
    function frame:SetInvalid(message)
        self.kitInvalid = message and true or false
        self:ShowMessage(type(message) == "string" and message or nil, true)
    end
    function frame:IsInvalid() return self.kitInvalid end
    function frame:SetFocus() box:SetFocus() end
    function frame:ClearFocus() box:ClearFocus() end
    function frame:HasFocus() return box:HasFocus() end
    function frame:SetPlaceholder(text) box.placeholder:SetText(text or ""); box:RefreshPlaceholder() end
    function frame:SetEnabled(enabled)
        if box.SetEnabled then
            box:SetEnabled(enabled and true or false)
        elseif enabled and box.Enable then
            box:Enable()
        elseif box.Disable then
            box:Disable()
        end
        if not enabled then box:ClearFocus() end
        self:Repaint()
    end
end

-- Input -------------------------------------------------------------------------------

-- A one-line field. `opts`: label, value, placeholder, help, width,
-- onCommit(text, field) when the player finishes a change, onChange(text,
-- field) as they type, validate(text) returning a message to refuse it,
-- maxLetters, numeric.
UI.Define("Input", function(ui, parent, opts)
    opts = opts or {}
    local frame = fieldFrame(ui, parent, opts)
    local box = newBox(ui, frame, opts, false)
    box:SetAllPoints(frame.line)
    frame.box = box
    frame.kitCommit = opts.onCommit
    frame.kitOnType = opts.onChange
    frame.kitValidate = opts.validate
    if opts.maxLetters then box:SetMaxLetters(opts.maxLetters) end
    if opts.numeric and box.SetNumeric then box:SetNumeric(true) end
    fieldMethods(frame)
    if opts.value ~= nil then frame:SetText(opts.value) end
    frame:ShowMessage(nil)
    return ui:Finish(frame, opts, paintBox)
end)

-- Search ------------------------------------------------------------------------------

-- An input with a lens that reports every keystroke (`onChange(text)`).
-- Given to a List as `search`, its arrow keys and Enter move through and
-- pick from the list. Escape empties it, then leaves.
UI.Define("Search", function(ui, parent, opts)
    opts = opts or {}
    local copy = {}
    for key, value in pairs(opts) do copy[key] = value end
    copy.insetLeft = 22
    local frame = UI.Proto.Input(ui, parent, copy)
    local box = frame.box
    local lens = CreateFrame("Frame", nil, box)
    lens:SetSize(12, 12)
    lens:SetPoint("LEFT", box, "LEFT", 7, 0)
    frame.lens = UI.NewGlyph(lens, "search", 11, 1.3)
    box:SetScript("OnEscapePressed", function(b)
        if (b:GetText() or "") ~= "" then
            b:SetText("")
            if frame.kitOnType then frame.kitOnType("", frame) end
        else
            b:ClearFocus()
        end
    end)
    box:SetScript("OnEnterPressed", function(b)
        if frame.kitList then frame.kitList:Activate() end
        b:ClearFocus()
    end)
    box:SetScript("OnArrowPressed", function(_, key)
        if not frame.kitList then return end
        if key == "UP" then frame.kitList:MoveSelection(-1) elseif key == "DOWN" then frame.kitList:MoveSelection(1) end
    end)
    ui:Paint(lens, function(t) frame.lens:SetColor(t.muted) end)
    return frame
end)

-- Text areas --------------------------------------------------------------------------

-- A field of several lines that scrolls, with the slim bar. `opts`: label,
-- height (of the box), value, placeholder, maxLetters (shows the count),
-- onChange(text), onCommit(text) when it loses focus changed.
UI.Define("TextArea", function(ui, parent, opts)
    opts = opts or {}
    local frame = fieldFrame(ui, parent, { label = opts.label, help = opts.help, width = opts.width, boxHeight = opts.height or 90 })
    local boxFrame = CreateFrame("Frame", nil, frame.line)
    boxFrame:SetAllPoints(frame.line)
    boxFrame:EnableMouse(true)
    frame.boxFrame = boxFrame
    local scroll, content = UI.NewScroll(ui, boxFrame)
    scroll:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 1, -4)
    scroll:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -1, 4)
    frame.scrollContent = content
    local box = newBox(ui, frame, opts, true)
    box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    frame.box = box
    frame.kitCommit = opts.onCommit
    frame.kitOnType = opts.onChange
    frame.kitValidate = opts.validate
    boxFrame:SetScript("OnMouseDown", function() box:SetFocus() end)
    -- The wheel is the text's only while the player is typing in it; until
    -- then it scrolls whatever holds the field, so the page does not stop
    -- when the field passes under the pointer.
    scroll:EnableMouseWheel(false)
    box:HookScript("OnEditFocusGained", function() scroll:EnableMouseWheel(true) end)
    box:HookScript("OnEditFocusLost", function() scroll:EnableMouseWheel(false) end)

    local function fit()
        local width = (scroll:GetWidth() or 0) - UI.SCROLLBAR
        if width > 0 then
            box:SetWidth(width)
            content:SetWidth(width)
        end
        content:SetHeight(math.max(scroll:GetHeight() or 0, box:GetHeight() or 0))
        scroll.Sync()
    end
    scroll:HookScript("OnSizeChanged", fit)
    box:HookScript("OnTextChanged", function(b)
        fit()
        if frame.counter then frame.counter:SetText((string.len(b:GetText() or "")) .. " / " .. opts.maxLetters) end
    end)
    -- Keeps the cursor in view while typing past the bottom.
    box:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, view = -y, scroll:GetHeight() or 0
        local at = scroll:GetVerticalScroll() or 0
        if top < at then scroll:ScrollTo(top) elseif top + h > at + view then scroll:ScrollTo(top + h - view) end
    end)
    if opts.maxLetters then
        box:SetMaxLetters(opts.maxLetters)
        frame.counter = UI.NewText(frame)
        frame.counter:SetPoint("BOTTOMRIGHT", frame.line, "TOPRIGHT", 0, LABEL_GAP)
        frame.counter:SetText("0 / " .. opts.maxLetters)
    end
    fieldMethods(frame)
    if opts.value ~= nil then frame:SetText(opts.value) end
    frame:ShowMessage(nil)
    frame.kitLayout = UI.LayoutOptions(opts, "height")
    return ui:Finish(frame, opts, function(f, t)
        paintBox(f, t)
        if f.counter then UI.ApplyStyle(f.counter, "fine", t) end
    end)
end)

-- Money ---------------------------------------------------------------------------------

-- Money in copper. The player types "1g 20s 5c" or a number of copper; the
-- box shows it in coin colours, plain only while the player types in it,
-- and the rounded amount shows beside it. `opts`: label, value (nil:
-- nothing set), guess (copper, shown as the placeholder in the estimate
-- colour), onChange(copper or nil), width of the box.
UI.Define("MoneyInput", function(ui, parent, opts)
    opts = opts or {}
    local frame = fieldFrame(ui, parent, { label = opts.label, help = opts.help })
    local box = newBox(ui, frame, { placeholder = opts.guess and ("~" .. Kit.FormatMoney(opts.guess) .. ", a guess") or opts.placeholder }, false)
    local boxWidth = opts.width or 120
    box:SetPoint("TOPLEFT", frame.line, "TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMLEFT", frame.line, "BOTTOMLEFT", 0, 0)
    box:SetWidth(boxWidth)
    frame.box = box
    frame.kitMinWidth = boxWidth + 90
    frame.kitPlaceholderColor = opts.guess and "estimate" or "muted"
    local preview = UI.NewText(frame.line)
    preview:SetPoint("LEFT", box, "RIGHT", 8, 0)
    fieldMethods(frame)

    -- Coloured coins, except under the player's cursor: colour codes in
    -- the text being edited would get in the way of typing.
    local function boxText(copper)
        if copper == nil then return "" end
        return Kit.FormatMoney(copper, true, not box:HasFocus())
    end
    local function showing(b) return frame.kitValue ~= nil and Kit.ParseMoney(b:GetText()) == frame.kitValue end
    box:HookScript("OnEditFocusGained", function(b)
        if showing(b) then
            frame:SetText(boxText(frame.kitValue))
            b:HighlightText()
        end
    end)
    box:HookScript("OnEditFocusLost", function(b)
        if showing(b) then frame:SetText(boxText(frame.kitValue)) end
    end)

    function frame:GetValue() return self.kitValue end
    function frame:SetValue(copper)
        self.kitValue = copper
        self:SetText(boxText(copper))
        preview:SetText(copper and Kit.FormatMoney(copper) or "")
    end
    frame.kitCommit = function(text)
        if text == "" then
            frame.kitValue = nil
            preview:SetText("")
            if opts.onChange then opts.onChange(nil) end
            return
        end
        local copper = Kit.ParseMoney(text)
        frame.kitValue = copper
        frame:SetText(boxText(copper))
        preview:SetText(Kit.FormatMoney(copper))
        if opts.onChange then opts.onChange(copper) end
    end
    frame.kitValidate = function(text)
        if text == "" or Kit.ParseMoney(text) then return nil end
        return Kit.MoneyHint()
    end
    frame:SetValue(opts.value)
    frame:ShowMessage(nil)
    frame.kitLayout = UI.LayoutOptions(opts, "width")
    return ui:Finish(frame, opts, function(f, t)
        paintBox(f, t)
        UI.ApplyStyle(preview, "number", t)
        if f.kitValue then preview:SetText(Kit.FormatMoney(f.kitValue)) end
    end)
end)

-- Numbers --------------------------------------------------------------------------------

-- A number with - and + either side. `opts`: label, value, min, max, step,
-- onChange(n), width of the box. Out of range is held to the range.
UI.Define("NumberInput", function(ui, parent, opts)
    opts = opts or {}
    local frame = fieldFrame(ui, parent, { label = opts.label, help = opts.help or
        ((opts.min and opts.max) and (opts.min .. " to " .. opts.max) or nil) })
    local step = opts.step or 1
    local boxWidth = opts.width or 56
    local minus = ui:GlyphButton(frame.line, "minus", { size = BOX_HEIGHT, boxed = true, bright = true })
    minus:SetPoint("LEFT", frame.line, "LEFT", 0, 0)
    local box = newBox(ui, frame, {}, false)
    box:SetJustifyH("CENTER")
    box:SetPoint("TOPLEFT", minus, "TOPRIGHT", 4, 0)
    box:SetPoint("BOTTOMLEFT", minus, "BOTTOMRIGHT", 4, 0)
    box:SetWidth(boxWidth)
    local plus = ui:GlyphButton(frame.line, "plus", { size = BOX_HEIGHT, boxed = true, bright = true })
    plus:SetPoint("LEFT", box, "RIGHT", 4, 0)
    frame.box = box
    frame.kitMinWidth = boxWidth + 2 * (BOX_HEIGHT + 4)
    frame.kitTextStyle = "number"
    frame.kitStretch = false
    -- The range or the error sits centred under the value, as the value does
    -- in its box.
    frame.message:SetJustifyH("CENTER")
    fieldMethods(frame)

    local function clamp(n)
        if opts.min and n < opts.min then n = opts.min end
        if opts.max and n > opts.max then n = opts.max end
        return n
    end
    function frame:GetValue() return self.kitValue end
    function frame:SetValue(n)
        self.kitValue = n and clamp(n) or nil
        self:SetText(self.kitValue and tostring(self.kitValue) or "")
    end
    local function change(n)
        n = clamp(n)
        if n == frame.kitValue then frame:SetText(tostring(n)); return end
        frame:SetValue(n)
        if opts.onChange then opts.onChange(n) end
    end
    minus.kitClick = function() change((frame.kitValue or opts.min or 0) - step) end
    plus.kitClick = function() change((frame.kitValue or opts.min or 0) + step) end
    frame.kitCommit = function(text) change(tonumber(text)) end
    frame.kitValidate = function(text)
        if tonumber(text) then return nil end
        return "A number" .. ((opts.min and opts.max) and (" from " .. opts.min .. " to " .. opts.max) or "") .. "."
    end
    box:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then plus.kitClick() elseif key == "DOWN" then minus.kitClick() end
    end)
    -- The wheel steps it while it has focus (and so its accent edge), never
    -- while the page scrolls past it.
    box:EnableMouseWheel(false)
    box:HookScript("OnEditFocusGained", function(b) b:EnableMouseWheel(true) end)
    box:HookScript("OnEditFocusLost", function(b) b:EnableMouseWheel(false) end)
    box:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 then plus.kitClick() elseif delta < 0 then minus.kitClick() end
    end)
    frame:SetValue(opts.value)
    frame:ShowMessage(nil)
    frame.kitLayout = UI.LayoutOptions(opts, "width")
    return ui:Finish(frame, opts, paintBox)
end)

-- Toggles ----------------------------------------------------------------------------------

-- On or off, read as state rather than an action: a box and its caption, no
-- plate around them. The caption turns accent while on. `opts`: value,
-- onChange(on), tooltip, disabled.
local CHECK = 14

UI.Define("Toggle", function(ui, parent, caption, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(20)
    button.kitStretch = false
    local box = CreateFrame("Frame", nil, button)
    box:SetSize(CHECK, CHECK)
    box:SetPoint("LEFT", button, "LEFT", 0, 0)
    local plate = UI.NewPlate(box)
    local check = UI.NewGlyph(box, "check", 9, 2)
    local label = UI.NewText(button)
    label:SetPoint("LEFT", box, "RIGHT", 7, 0)
    label:SetText(caption or "")
    button.label = label
    button.kitPressParts = { label }
    button.kitChecked = opts.value and true or false

    local function fit(b)
        local width = CHECK + ((label:GetText() or "") ~= "" and (7 + math.ceil(UI.StringWidth(label))) or 0)
        b:SetWidth(width)
        return width
    end
    button.KitNaturalWidth = function(b) return fit(b) end
    button.KitNaturalHeight = function() return 20 end
    function button:SetValue(on, silent)
        self.kitChecked = on and true or false
        check:SetShown(self.kitChecked)
        self:Repaint()
        if not silent and opts.onChange then opts.onChange(self.kitChecked) end
    end
    function button:GetValue() return self.kitChecked end
    button.SetChecked = function(b, on) b:SetValue(on, true) end
    button.GetChecked = button.GetValue
    function button:SetText(text)
        label:SetText(text or "")
        fit(self)
        if self.kitParentContainer then UI.Invalidate(self.kitParentContainer) end
    end
    button.kitClick = function(b) b:SetValue(not b.kitChecked) end
    UI.WireButton(button, ui)
    if opts.disabled then button:Disable() end
    check:SetShown(button.kitChecked)
    return ui:Finish(button, opts, function(b, t)
        local enabled = b:IsEnabled()
        local color = t.text
        if not enabled then color = t.muted45
        elseif b.kitChecked then color = t.accent end
        UI.ApplyStyle(label, "body", t, color)
        local drew = t.art and plate:Art(t.art.plate, 4, enabled and { 1, 1, 1, 1 } or { 0.55, 0.55, 0.55, 1 })
        if not drew then plate:Flat(t.surface, b.hover and enabled and t.accent65 or t.border) end
        check:SetColor(enabled and t.accent or t.muted45)
        fit(b)
    end)
end)

-- Sliders -------------------------------------------------------------------------------------

-- A plain horizontal slider with no Blizzard template. `opts`: label,
-- value, min, max, step, format (for the value beside it, "%d%%"),
-- onChange(value), width.
UI.Define("Slider", function(ui, parent, opts)
    opts = opts or {}
    local minValue, maxValue, step = opts.min or 0, opts.max or 100, opts.step or 1
    local frame = CreateFrame("Frame", nil, parent)
    local height = opts.label and 36 or 18
    frame:SetSize(opts.width or 200, height)
    if opts.width then frame.kitStretch = false end
    frame.KitNaturalWidth = function() return opts.width or 200 end
    frame.KitNaturalHeight = function() return height end
    local label, readout
    if opts.label then
        label = UI.NewText(frame)
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        label:SetText(opts.label)
    end
    readout = UI.NewText(frame)
    readout:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
    slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", opts.label and 0 or -48, 1)
    if opts.label then readout:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0) else readout:SetPoint("RIGHT", frame, "RIGHT", 0, 0) end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    UI.Stroke(track, "height", 2)
    local filled = slider:CreateTexture(nil, "ARTWORK")
    filled:SetPoint("LEFT", slider, "LEFT", 0, 0)
    UI.Stroke(filled, "height", 2)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(10, 14)
    local thumbEdge = CreateFrame("Frame", nil, slider)
    thumbEdge:SetAllPoints(thumb)
    thumbEdge.plate = UI.NewPlate(thumbEdge, "OVERLAY")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    -- The wheel only turns a slider the player has taken hold of (pressed,
    -- and not left since); passing over one while scrolling the page must
    -- not change it unseen.
    slider:EnableMouseWheel(false)

    local function show(value)
        readout:SetText(opts.format and string.format(opts.format, value) or tostring(value))
        local width = slider:GetWidth() or 0
        local share = maxValue > minValue and (value - minValue) / (maxValue - minValue) or 0
        filled:SetWidth(math.max(0.01, width * share))
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        show(value)
        if frame.kitSilent or value == frame.kitValue then return end
        frame.kitValue = value
        if opts.onChange then opts.onChange(value) end
    end)
    slider:SetScript("OnMouseWheel", function(_, delta) slider:SetValue((frame.kitValue or minValue) + delta * step) end)
    slider:SetScript("OnSizeChanged", function() show(frame.kitValue or minValue) end)
    -- Held: the slider has the wheel, and shows it as a field shows focus.
    -- The thumb fills and grows, the readout lights.
    local function hold(held)
        frame.kitHeld = held
        slider:EnableMouseWheel(held)
        thumb:SetSize(held and 12 or 10, held and 16 or 14)
        frame:Repaint()
    end
    slider:SetScript("OnEnter", function() frame.hover = true; frame:Repaint() end)
    slider:SetScript("OnLeave", function() frame.hover = false; hold(false) end)
    slider:HookScript("OnMouseDown", function() hold(true) end)
    slider:HookScript("OnHide", function() if frame.kitHeld then hold(false) end end)

    function frame:SetValue(value)
        self.kitSilent = true
        self.kitValue = value
        slider:SetValue(value)
        show(value)
        self.kitSilent = false
    end
    function frame:GetValue() return self.kitValue end
    frame.slider = slider
    slider.kitKeyArrow = function(_, key)
        local delta = (key == "LEFT" or key == "DOWN") and -step or step
        slider:SetValue((frame.kitValue or minValue) + delta)
    end
    UI.RegisterFocusable(ui, slider, false)
    frame:SetValue(opts.value or minValue)
    return ui:Finish(frame, opts, function(f, t)
        if label then UI.ApplyStyle(label, "label", t, "text") end
        UI.ApplyStyle(readout, "number", t, f.kitHeld and "accent" or nil)
        UI.TexColor(track, t.border)
        UI.TexColor(filled, t.accent)
        UI.VertexColor(thumb, f.kitHeld and t.accent or (f.hover and t.raised or t.surface))
        thumbEdge.plate:Flat(nil, t.accent)
    end)
end)

-- A Tab order of the caller's own, for fields outside a window or in an
-- order other than the one they were made in.
function UI.Proto:TabChain(fields)
    if not fields or not fields[1] then return end
    local list = {}
    for _, field in ipairs(fields) do list[#list + 1] = field.box or field end
    local win = UI.WindowOf(list[1])
    if win then
        win.kitTabOrder = list
        return
    end
    for index, box in ipairs(list) do
        box:SetScript("OnTabPressed", function()
            local stepBy = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and -1 or 1
            for offset = 1, #list - 1 do
                local candidate = list[((index - 1 + stepBy * offset) % #list) + 1]
                if candidate:IsVisible() then candidate:SetFocus(); return end
            end
        end)
    end
end
