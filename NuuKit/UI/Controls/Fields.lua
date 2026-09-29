local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Fields, toggles and sliders.
--
-- A field is a small frame: an optional `label` over the box, and under it
-- a line for `help` or for why the text is wrong; a `compact` field (in a
-- table's cell, which has no room under it) has no such line, and tells
-- why the text is wrong to `onInvalid(message, field)` instead, for the
-- window to say elsewhere. Every field has GetText,
-- SetText, GetValue, SetValue, SetInvalid(message or nil), IsInvalid,
-- ShowMessage, SetLabel, SetPlaceholder, SetFocus, ClearFocus, HasFocus,
-- SetEnabled, and Reset / IsStored (Core). `field.box` is the EditBox.
--
-- The box commits on Enter, on Tab and when it loses the focus to a click
-- elsewhere, if the text changed and `validate` lets it; Escape puts back
-- what was there. A commit writes a bound table and calls onChange(value,
-- field); code that sets a value never calls onChange.

local BOX_HEIGHT = 24
local LABEL_GAP, MESSAGE_GAP = 4, 3
local WHITE = { 1, 1, 1, 1 }
local DIM = { 0.55, 0.55, 0.55, 1 }

-- In a row, fields line up by their tops (every field type says
-- `valign = "top"`), so a help line under one does not lift its box above
-- the others.

-- The frame around a box --------------------------------------------------------------

-- The room a field's label takes above its box, from the label style's size
-- (a string's height reads 0 until the client first draws it). A text
-- area's letter count sits in the same band, so it has one without a label.
local function labelBand(w, t)
    if not w.kitHasLabel then return 0 end
    return math.max(12, math.ceil(t.sizes.label or 12)) + LABEL_GAP
end

local function placeField(w)
    local top = UI.Snap(w, w.kitBand)
    local line = w.line
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -top)
    line:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -top)
    line:SetHeight(UI.Snap(w, w.kitBoxHeight))
    w.message:ClearAllPoints()
    w.message:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -MESSAGE_GAP)
    w.message:SetPoint("RIGHT", w, "RIGHT", 0, 0)
end

-- The parts every field has: label, message, and the line the box (and
-- anything beside it: a preview, the - and + of a number) sits in.
local function buildField(w)
    w:SetSize(1, BOX_HEIGHT)
    w.label = UI.NewText(w)
    w.label:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
    w.message = UI.NewText(w)
    if w.message.SetWordWrap then w.message:SetWordWrap(true) end
    w.message:SetJustifyV("TOP")
    w.message:Hide()
    w.line = UI.NewFrame("Frame", nil, w)
    w.line:SetHeight(BOX_HEIGHT)
end

-- The box ------------------------------------------------------------------------------

local function refreshPlaceholder(box)
    local placeholder = box.placeholder
    if (placeholder:GetText() or "") == "" or (box:GetText() or "") ~= "" then
        placeholder:Hide()
        return
    end
    -- At rest in full, so coin colours in it read true; dimmed while typing.
    placeholder:SetAlpha(box:HasFocus() and 0.45 or 1)
    placeholder:Show()
end

-- Sets the box's text as code does: no commit, no onChange.
local function setText(w, text)
    local box = w.box
    box:SetText(text == nil and "" or tostring(text))
    if box.kitBaseline ~= nil then box.kitBaseline = box:GetText() or "" end
    refreshPlaceholder(box)
    if w.kitFieldText then w:kitFieldText() end
end

local function commit(box)
    if box.kitBaseline == nil then return end
    local w = box.kitOwner
    local text = box:GetText() or ""
    if text == box.kitBaseline then return end
    local problem = w:kitFieldCheck(text)
    if problem then
        w:SetInvalid(problem)
        return
    end
    box.kitBaseline = text
    w:kitFieldCommit(text)
end

-- Focus selects the text; the type may do more (a money field shows plain
-- coins, a number takes the wheel).
local function focusGained(box)
    local w = box.kitOwner
    box.kitBaseline = box:GetText() or ""
    if not box.kitMulti then box:HighlightText() end
    refreshPlaceholder(box)
    if w.kitFieldFocus then w:kitFieldFocus(true) end
    w:PaintState(w.ui.tokens)
end

-- Leaving by a click or Tab commits if the text changed.
local function focusLost(box)
    local w = box.kitOwner
    commit(box)
    box.kitBaseline = nil
    if box.HighlightText then box:HighlightText(0, 0) end
    refreshPlaceholder(box)
    if w.kitFieldFocus then w:kitFieldFocus(false) end
    w:PaintState(w.ui.tokens)
end

-- Enter commits and leaves (a search picks from its list first).
local function enterPressed(box)
    local w = box.kitOwner
    if w.kitFieldEnter then w:kitFieldEnter() return end
    commit(box)
    box:ClearFocus()
end

-- Escape puts back what was there and leaves (a search empties first).
local function escapePressed(box)
    local w = box.kitOwner
    if w.kitFieldEscape then w:kitFieldEscape() return end
    if box.kitBaseline ~= nil then setText(w, box.kitBaseline) end
    box:ClearFocus()
end

local function textChanged(box, userInput)
    local w = box.kitOwner
    if userInput and w.kitInvalid then w:SetInvalid(nil) end
    refreshPlaceholder(box)
    if w.kitFieldText then w:kitFieldText() end
    if userInput and w.kitOnType then w.kitOnType(box:GetText() or "", w) end
end

local function shiftDown()
    return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
end

-- Tab moves through the window's fields in the order they were made (or
-- every focusable, under full keyboard control), or along a TabChain.
local function tabPressed(box)
    local step = shiftDown() and -1 or 1
    local chain = box.kitChain
    if chain then
        local count, at = #chain, 0
        for index = 1, count do if chain[index] == box then at = index end end
        for offset = 1, count - 1 do
            local candidate = chain[((at - 1 + step * offset) % count) + 1]
            if candidate.kitField and candidate:IsVisible() and (not candidate.IsEnabled or candidate:IsEnabled()) then
                box:ClearFocus()
                candidate:SetFocus()
                return
            end
        end
        return
    end
    local win = UI.WindowOf(box)
    if not win then return end
    local nextOne = UI.NextFocus(win, box, step, not win.kitKeyboard)
    if not nextOne then return end
    -- Leaving commits before the next one takes the keys.
    box:ClearFocus()
    if win.kitKeyboard then
        UI.FocusWidget(win, nextOne)
    elseif nextOne.SetFocus then
        nextOne:SetFocus()
    end
end

local function arrowPressed(box, key)
    local w = box.kitOwner
    if w.kitFieldArrow then w:kitFieldArrow(key) end
end

-- An EditBox with the kit's plate and placeholder in `parent`. `holder`
-- carries the plate and placeholder when it is not the box (a text area's
-- frame); `inset` is where the text starts.
local function newBox(w, parent, multiLine, holder, inset)
    local box = UI.NewFrame("EditBox", nil, parent)
    box.kitField = true
    box.kitOwner = w
    box.kitMulti = multiLine or nil
    box:SetAutoFocus(false)
    box:SetFont(UI.FontFile(), 11, "")
    box:SetTextInsets(inset or 7, 7, 2, 2)
    if multiLine then box:SetMultiLine(true) end
    local art = holder or box
    box.plate = UI.NewPlate(art)
    box.placeholder = UI.NewText(art)
    if multiLine then
        box.placeholder:SetPoint("TOPLEFT", box, "TOPLEFT", inset or 8, -4)
    else
        box.placeholder:SetPoint("LEFT", box, "LEFT", inset or 8, 0)
    end
    box:SetScript("OnEditFocusGained", focusGained)
    box:SetScript("OnEditFocusLost", focusLost)
    if not multiLine then box:SetScript("OnEnterPressed", enterPressed) end
    box:SetScript("OnEscapePressed", escapePressed)
    box:SetScript("OnTextChanged", textChanged)
    box:SetScript("OnTabPressed", tabPressed)
    return box
end

-- What a field's Init shares: every piece of state from the spec, so a
-- field from the pool keeps nothing of its last use.
local function initField(w, spec, boxHeight, hasBand)
    w.kitHelp = spec.help
    w.kitHasLabel = (spec.label ~= nil) or hasBand or nil
    w.label:SetText(spec.label or "")
    w.label:SetShown(spec.label ~= nil)
    w.kitBoxHeight = boxHeight
    w.kitInvalid, w.kitMessageError = false, false
    w.kitValidate = spec.validate
    w.kitOnType = spec.onType
    w.kitCompact = spec.compact or nil
    w.kitOnInvalid = spec.onInvalid
    w.kitMinWidth = nil
    w.kitTextStyle = nil
    w.kitPlaceholderColor = nil
    local box = w.box
    box.kitPooled, box.kitChain, box.kitBaseline = nil, nil, nil
    pcall(box.SetMaxLetters, box, spec.maxLetters or 0)
    box.placeholder:SetText(spec.placeholder or "")
    if box.SetEnabled then box:SetEnabled(not spec.disabled) end
    UI.RegisterFocusable(w.ui, box, true)
    w.kitBand = labelBand(w, w.ui.tokens)
    placeField(w)
end

local function releaseField(w)
    local box = w.box
    -- Leaving now must not commit into the last use's callbacks.
    box.kitBaseline = nil
    if box:HasFocus() then box:ClearFocus() end
    w.kitOnInvalid, w.kitOnType, w.kitValidate = nil, nil, nil
    box.kitPooled = true
    w.ui.focusables[box] = nil
end

-- The methods every field shares.
local Field = {}

function Field:GetText() return self.box:GetText() or "" end
function Field:SetText(text) setText(self, text) end
function Field:GetValue() return self:GetText() end
function Field:SetValue(text) setText(self, text) end

-- Shows `text` under the box (nil: the help line, if any).
function Field:ShowMessage(text, isError)
    local value = text or self.kitHelp
    self.kitMessageError = (text ~= nil and isError) and true or false
    if self.kitCompact then
        -- No line under it: an error goes to onInvalid, the edge shows it.
        if self.message:IsShown() then
            self.message:Hide()
            self:Changed()
        end
        if self.kitMessageError and self.kitOnInvalid then self.kitOnInvalid(text, self) end
        self:PaintState(self.ui.tokens)
        return
    end
    self.message:SetText(value or "")
    self.message:SetShown(value ~= nil and value ~= "")
    self:Changed()
    self:PaintState(self.ui.tokens)
end

function Field:SetInvalid(message)
    self.kitInvalid = message and true or false
    self:ShowMessage(type(message) == "string" and message or nil, true)
end
function Field:IsInvalid() return self.kitInvalid end

function Field:SetLabel(text)
    self.label:SetText(text or "")
    self.label:SetShown(text ~= nil)
    self.kitHasLabel = (text ~= nil) or (self.counter and self.counter:IsShown()) or nil
    self.kitBand = labelBand(self, self.ui.tokens)
    placeField(self)
    self:Changed()
end

function Field:SetPlaceholder(text)
    self.box.placeholder:SetText(text or "")
    refreshPlaceholder(self.box)
end

function Field:SetFocus() self.box:SetFocus() end
function Field:ClearFocus() self.box:ClearFocus() end
function Field:HasFocus() return self.box:HasFocus() end
function Field:IsEnabled() return not self.box.IsEnabled or self.box:IsEnabled() end

function Field:SetEnabled(enabled)
    local box = self.box
    if box.SetEnabled then
        box:SetEnabled(enabled and true or false)
    elseif enabled and box.Enable then
        box:Enable()
    elseif box.Disable then
        box:Disable()
    end
    if not enabled then box:ClearFocus() end
    if self.kitFieldEnabled then self:kitFieldEnabled(enabled and true or false) end
    self:PaintState(self.ui.tokens)
end

-- `validate(text)` answers a message to refuse the text.
function Field:kitFieldCheck(text)
    if self.kitValidate then return self.kitValidate(text) end
    return nil
end

function Field:kitFieldCommit(text) UI.Commit(self, text) end

function Field:Measure(width)
    local height = self.kitBoxHeight + self.kitBand
    if self.message:IsShown() then
        if width and width > 0 then self.message:SetWidth(width) end
        height = height + MESSAGE_GAP + (self.message:GetStringHeight() or 12)
    end
    return self.kitMinWidth or 160, math.ceil(height)
end

-- Fonts; a new text size moves the box, and the field grows or shrinks.
function Field:Paint(t)
    UI.ApplyStyle(self.box, self.kitTextStyle or "body", t, nil, true)
    UI.ApplyStyle(self.box.placeholder, "body", t, nil, true)
    UI.ApplyStyle(self.label, "label", t, nil, true)
    UI.ApplyStyle(self.message, "fine", t, nil, true)
    local band = labelBand(self, t)
    if band ~= self.kitBand then
        self.kitBand = band
        placeField(self)
        self:Changed()
    end
    self:PaintState(t)
end

-- Focus, error and disabled: colours only.
function Field:PaintState(t)
    local box = self.box
    local focused = box:HasFocus()
    local enabled = not box.IsEnabled or box:IsEnabled()
    local edge = self.kitInvalid and t.danger or (focused and t.accent or t.border)
    local fill = focused and t.raised or t.surface
    if not enabled then fill, edge = t.surface, t.border50 end
    box.plate:Flat(fill, edge)
    UI.TextColor(box, enabled and t.text or t.muted45)
    UI.TextColor(box.placeholder, UI.Colour(t, self.kitPlaceholderColor or "muted"))
    UI.TextColor(self.label, t.text)
    UI.TextColor(self.message, self.kitMessageError and t.danger or t.muted)
end

local function methodsWith(extra)
    local methods = {}
    for key, fn in pairs(Field) do methods[key] = fn end
    for key, fn in pairs(extra or {}) do methods[key] = fn end
    return methods
end

-- Input -------------------------------------------------------------------------------

-- A one-line field. Spec: label, value, bind, default, placeholder, help,
-- onChange(text, field) when the player finishes a change, onType(text,
-- field) as they type, validate(text) returning a message to refuse it,
-- maxLetters, numeric, disabled.
local function buildInput(w, inset)
    buildField(w)
    local box = newBox(w, w.line, false, nil, inset)
    box:SetAllPoints(w.line)
    w.box = box
end

local function initInput(w, spec)
    initField(w, spec, BOX_HEIGHT)
    pcall(w.box.SetNumeric, w.box, spec.numeric and true or false)
    setText(w, UI.InitValue(w, spec))
    w:ShowMessage(nil)
end

UI.Define("Input", {
    wraps = true, valign = "top",
    Build = function(w) buildInput(w) end,
    Init = initInput,
    Release = releaseField,
    methods = methodsWith(),
})

-- Search ------------------------------------------------------------------------------

-- An input with a lens. Its text is told to `field.kitOnType(text, field)`
-- (spec.onType) on every change: typed, emptied by Escape, or set by code,
-- so a list filtered by it never shows a stale filter. Given to a List as
-- `search`, the List sets `kitList`: then UP / DOWN move through the list
-- and Enter picks from it. Escape empties it, then leaves.
local SEARCH_INSET = 22

UI.Define("Search", {
    wraps = true, valign = "top",
    Build = function(w)
        buildInput(w, SEARCH_INSET)
        local lens = UI.NewFrame("Frame", nil, w.box)
        lens:SetSize(12, 12)
        lens:SetPoint("LEFT", w.box, "LEFT", 7, 0)
        w.lens = UI.NewGlyph(lens, "search", 11, 1.3)
        w.box:SetScript("OnArrowPressed", arrowPressed)
    end,
    Init = function(w, spec)
        w.kitList = nil
        initInput(w, spec)
    end,
    Release = function(w)
        releaseField(w)
        w.kitList = nil
    end,
    methods = methodsWith({
        SetText = function(self, text)
            local before = self:GetText()
            setText(self, text)
            local now = self:GetText()
            if now ~= before and self.kitOnType then self.kitOnType(now, self) end
        end,
        SetValue = function(self, text) self:SetText(text) end,
        kitFieldEnter = function(self)
            if self.kitList then self.kitList:Activate() end
            self.box:ClearFocus()
        end,
        kitFieldEscape = function(self)
            if self:GetText() ~= "" then
                self:SetText("")
            else
                self.box:ClearFocus()
            end
        end,
        kitFieldArrow = function(self, key)
            local list = self.kitList
            if not list then return end
            if key == "UP" then list:MoveSelection(-1) elseif key == "DOWN" then list:MoveSelection(1) end
        end,
        PaintState = function(self, t)
            Field.PaintState(self, t)
            self.lens:SetColor(t.muted)
        end,
    }),
})

-- Text areas --------------------------------------------------------------------------

-- A field of several lines that scrolls, with the slim bar. Spec: label,
-- boxHeight (of the box, 90), value, bind, default, placeholder, help,
-- maxLetters (shows the count), onType(text), onChange(text) when it loses
-- focus changed, validate. Enter makes a new line; Tab and a click
-- elsewhere commit.
local function areaFit(w)
    local scroll, box = w.scroll, w.box
    local width = (scroll:GetWidth() or 0) - UI.SCROLLBAR
    if width > 0 then
        box:SetWidth(width)
        w.scrollContent:SetWidth(width)
    end
    w.scrollContent:SetHeight(math.max(scroll:GetHeight() or 0, box:GetHeight() or 0, 1))
    scroll:Sync()
end

local function areaSized(scroll) areaFit(scroll.kitOwner) end
local function areaMouseDown(frame) frame.kitOwner.box:SetFocus() end

-- Not typing, the text takes the wheel only where nothing around it scrolls.
local function areaEnter(frame)
    local w = frame.kitOwner
    if not w.box:HasFocus() then w.scroll:EnableMouseWheel(not UI.PageScrolls(w)) end
end

-- Keeps the cursor in view while typing past the bottom.
local function areaCursor(box, _, y, _, h)
    local scroll = box.kitOwner.scroll
    local top, view = -(y or 0), scroll:GetHeight() or 0
    local at = scroll:GetVerticalScroll() or 0
    h = h or 0
    if top < at then scroll:ScrollTo(top) elseif top + h > at + view then scroll:ScrollTo(top + h - view) end
end

-- Letters, not bytes, as maxLetters counts them.
local function letters(text)
    local _, count = string.gsub(text, "[^\128-\191]", "")
    return count
end

UI.Define("TextArea", {
    wraps = true, valign = "top",
    Build = function(w)
        buildField(w)
        local boxFrame = UI.NewFrame("Frame", nil, w.line)
        boxFrame:SetAllPoints(w.line)
        boxFrame:EnableMouse(true)
        boxFrame.kitOwner = w
        boxFrame:SetScript("OnMouseDown", areaMouseDown)
        w.boxFrame = boxFrame
        local scroll, content = UI.NewScroll(w.ui, boxFrame)
        scroll:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 1, -4)
        scroll:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -1, 4)
        scroll.kitOwner = w
        scroll:HookScript("OnSizeChanged", areaSized)
        w.scroll, w.scrollContent = scroll, content
        local box = newBox(w, content, true, boxFrame)
        box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        box:SetScript("OnCursorChanged", areaCursor)
        box:HookScript("OnEnter", areaEnter)
        boxFrame:HookScript("OnEnter", areaEnter)
        w.box = box
        w.counter = UI.NewText(w)
        w.counter:SetPoint("BOTTOMRIGHT", w.line, "TOPRIGHT", 0, LABEL_GAP)
        w.counter:Hide()
    end,
    Init = function(w, spec)
        w.kitMaxLetters = spec.maxLetters
        w.counter:SetShown(spec.maxLetters ~= nil)
        initField(w, spec, spec.boxHeight or 90, spec.maxLetters ~= nil)
        -- Inside a page that scrolls, the wheel is the text's only while the
        -- player is typing in it; until then it scrolls the page, so the page
        -- does not stop when the field passes under the pointer.
        w.scroll:EnableMouseWheel(false)
        w.scroll:ScrollSet(0)
        setText(w, UI.InitValue(w, spec))
        w:ShowMessage(nil)
    end,
    Release = releaseField,
    methods = methodsWith({
        kitFieldFocus = function(self, on) self.scroll:EnableMouseWheel(on) end,
        kitFieldText = function(self)
            areaFit(self)
            if self.kitMaxLetters then
                self.counter:SetText(letters(self.box:GetText() or "") .. " / " .. self.kitMaxLetters)
            end
        end,
        Sized = function(self) areaFit(self) end,
        Paint = function(self, t)
            UI.ApplyStyle(self.counter, "fine", t)
            Field.Paint(self, t)
        end,
    }),
})

-- Money ---------------------------------------------------------------------------------

-- Money in copper. The player types "1g 20s 5c" or a number of copper; the
-- box shows it in coin colours, plain only while the player types in it,
-- and the rounded amount shows beside it. Spec: label, value, bind, default
-- (nil: nothing set), guess (copper, shown as the placeholder in the
-- estimate colour), placeholder, help, onChange(copper or nil, field),
-- boxWidth (120; `width` is the whole field's, as for any widget), preview
-- (false: no rounded amount beside the box, where there is no room for it),
-- compact and onInvalid (see the top of the file).

-- Coloured coins, except under the player's cursor: colour codes in the
-- text being edited would get in the way of typing.
local function moneyText(w, copper)
    if copper == nil then return "" end
    return Kit.FormatMoney(copper, true, not w.box:HasFocus())
end

-- Whether the box shows the value (and not something typed over it).
local function moneyShowing(w)
    return w.kitValue ~= nil and Kit.ParseMoney(w.box:GetText()) == w.kitValue
end

UI.Define("MoneyInput", {
    wraps = true, valign = "top",
    Build = function(w)
        buildField(w)
        local box = newBox(w, w.line, false)
        box:SetPoint("TOPLEFT", w.line, "TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMLEFT", w.line, "BOTTOMLEFT", 0, 0)
        w.box = box
        w.preview = UI.NewText(w.line)
        w.preview:SetPoint("LEFT", box, "RIGHT", 8, 0)
        w.kitPreviewShown = true
    end,
    Init = function(w, spec)
        initField(w, spec, BOX_HEIGHT)
        local boxWidth = spec.boxWidth or 120
        w.box:SetWidth(boxWidth)
        w.kitPreview = spec.preview ~= false
        if w.kitPreviewShown ~= w.kitPreview then
            w.kitPreviewShown = w.kitPreview
            w.preview:SetShown(w.kitPreview)
        end
        w.kitMinWidth = boxWidth + (w.kitPreview and 90 or 0)
        if spec.guess then
            w.box.placeholder:SetText("~" .. Kit.FormatMoney(spec.guess) .. ", a guess")
            w.kitPlaceholderColor = "estimate"
        end
        w:SetValue(UI.InitValue(w, spec))
        w:ShowMessage(nil)
    end,
    Release = releaseField,
    methods = methodsWith({
        GetValue = function(self) return self.kitValue end,
        SetValue = function(self, copper)
            self.kitValue = copper
            setText(self, moneyText(self, copper))
            self.preview:SetText(copper and Kit.FormatMoney(copper) or "")
        end,
        kitFieldFocus = function(self, on)
            if moneyShowing(self) then
                setText(self, moneyText(self, self.kitValue))
                if on then self.box:HighlightText() end
            end
        end,
        kitFieldCheck = function(_, text)
            if text == "" or Kit.ParseMoney(text) then return nil end
            return Kit.MoneyHint()
        end,
        kitFieldCommit = function(self, text)
            if text == "" then
                self.kitValue = nil
                self.preview:SetText("")
                UI.Commit(self, nil)
                return
            end
            local copper = Kit.ParseMoney(text)
            self.kitValue = copper
            setText(self, moneyText(self, copper))
            self.preview:SetText(Kit.FormatMoney(copper))
            UI.Commit(self, copper)
        end,
        Paint = function(self, t)
            UI.ApplyStyle(self.preview, "number", t)
            Field.Paint(self, t)
        end,
    }),
})

-- Numbers --------------------------------------------------------------------------------

-- A number with - and + either side. Spec: label, value, bind, default,
-- min, max, step, help (else the range), onChange(n, field), boxWidth (56).
-- Out of range is held to the range. UP / DOWN step it, and the wheel does
-- while it has focus.
local function clamp(w, n)
    if w.kitMin and n < w.kitMin then n = w.kitMin end
    if w.kitMax and n > w.kitMax then n = w.kitMax end
    return n
end

-- A change by the player.
local function numberChange(w, n)
    n = clamp(w, n)
    if n == w.kitValue then
        setText(w, tostring(n))
        return
    end
    w:SetValue(n)
    UI.Commit(w, n)
end

local function numberStep(w, direction)
    numberChange(w, (w.kitValue or w.kitMin or 0) + direction * w.kitStep)
end

local function numberMinus(button) numberStep(button.kitOwner, -1) end
local function numberPlus(button) numberStep(button.kitOwner, 1) end

-- The wheel steps it while it has focus (and so its accent edge), never
-- while the page scrolls past it.
local function numberWheel(box, delta)
    if delta > 0 then numberStep(box.kitOwner, 1) elseif delta < 0 then numberStep(box.kitOwner, -1) end
end

UI.Define("NumberInput", {
    wraps = true, stretch = false, valign = "top",
    Build = function(w)
        buildField(w)
        local ui = w.ui
        local minus = UI.Make(ui, "GlyphButton", w.line, { "minus", size = BOX_HEIGHT, boxed = true, bright = true, onClick = numberMinus })
        UI.Fit(minus)
        minus:SetPoint("LEFT", w.line, "LEFT", 0, 0)
        minus.kitOwner = w
        local box = newBox(w, w.line, false)
        box:SetJustifyH("CENTER")
        box:SetPoint("TOPLEFT", minus, "TOPRIGHT", 4, 0)
        box:SetPoint("BOTTOMLEFT", minus, "BOTTOMRIGHT", 4, 0)
        box:SetScript("OnArrowPressed", arrowPressed)
        box:SetScript("OnMouseWheel", numberWheel)
        local plus = UI.Make(ui, "GlyphButton", w.line, { "plus", size = BOX_HEIGHT, boxed = true, bright = true, onClick = numberPlus })
        UI.Fit(plus)
        plus:SetPoint("LEFT", box, "RIGHT", 4, 0)
        plus.kitOwner = w
        w.box, w.minus, w.plus = box, minus, plus
        -- The range or the error sits centred under the value, as the value
        -- does in its box.
        w.message:SetJustifyH("CENTER")
    end,
    Init = function(w, spec)
        w.kitMin, w.kitMax, w.kitStep = spec.min, spec.max, spec.step or 1
        local help = spec.help
        if help == nil and spec.min and spec.max then help = spec.min .. " to " .. spec.max end
        local fieldSpec = spec
        if help ~= spec.help then
            -- The range as help, without touching the caller's spec.
            fieldSpec = w.kitHelpSpec or {}
            for key in pairs(fieldSpec) do fieldSpec[key] = nil end
            for key, value in pairs(spec) do fieldSpec[key] = value end
            fieldSpec.help = help
            w.kitHelpSpec = fieldSpec
        end
        -- The - first, then the box, then the +, for the Tab order.
        UI.RegisterFocusable(w.ui, w.minus, false)
        initField(w, fieldSpec, BOX_HEIGHT)
        UI.RegisterFocusable(w.ui, w.plus, false)
        w.minus.kitPooled, w.plus.kitPooled = nil, nil
        local boxWidth = spec.boxWidth or 56
        w.box:SetWidth(boxWidth)
        w.kitMinWidth = boxWidth + 2 * (BOX_HEIGHT + 4)
        w.kitTextStyle = "number"
        w.box:EnableMouseWheel(false)
        w.minus:SetEnabled(not spec.disabled)
        w.plus:SetEnabled(not spec.disabled)
        w:SetValue(UI.InitValue(w, spec))
        w:ShowMessage(nil)
    end,
    Release = function(w)
        releaseField(w)
        w.box:EnableMouseWheel(false)
        w.ui.focusables[w.minus], w.ui.focusables[w.plus] = nil, nil
        w.minus.kitPooled, w.plus.kitPooled = true, true
    end,
    methods = methodsWith({
        GetValue = function(self) return self.kitValue end,
        SetValue = function(self, n)
            n = tonumber(n)
            self.kitValue = n and clamp(self, n) or nil
            setText(self, self.kitValue and tostring(self.kitValue) or "")
        end,
        kitFieldFocus = function(self, on) self.box:EnableMouseWheel(on) end,
        kitFieldArrow = function(self, key)
            if key == "UP" then numberStep(self, 1) elseif key == "DOWN" then numberStep(self, -1) end
        end,
        -- The - and + go with the box.
        kitFieldEnabled = function(self, enabled)
            self.minus:SetEnabled(enabled)
            self.plus:SetEnabled(enabled)
        end,
        kitFieldCheck = function(self, text)
            if tonumber(text) then return nil end
            local min, max = self.kitMin, self.kitMax
            return "A number" .. ((min and max) and (" from " .. min .. " to " .. max) or "") .. "."
        end,
        kitFieldCommit = function(self, text) numberChange(self, tonumber(text)) end,
    }),
})

-- Toggles ----------------------------------------------------------------------------------

-- On or off, read as state rather than an action: a box and its caption, no
-- plate around them. The caption turns accent while on. Spec: [1] the
-- caption, value, bind, default, onChange(on, toggle), tooltip, disabled.
local CHECK = 14

UI.Define("Toggle", UI.ClickableType({
    stretch = false,
    Build = function(w)
        w:SetHeight(20)
        local box = UI.NewFrame("Frame", nil, w)
        box:SetSize(CHECK, CHECK)
        box:SetPoint("LEFT", w, "LEFT", 0, 0)
        w.plate = UI.NewPlate(box)
        w.check = UI.NewGlyph(box, "check", 9, 2)
        w.label = UI.NewText(w)
        w.label:SetPoint("LEFT", box, "RIGHT", 7, 0)
        w.kitPressParts = { w.label }
        UI.WireButton(w)
    end,
    Init = function(w, spec)
        UI.InitClickable(w, spec)
        w.kitClick = nil
        w.label:SetText(spec[1] or "")
        w:SetValue(UI.InitValue(w, spec))
    end,
    methods = {
        -- A click: the player's change.
        Activate = function(self)
            self:SetValue(not self.kitChecked)
            UI.Commit(self, self.kitChecked)
        end,
        SetValue = function(self, on)
            self.kitChecked = on and true or false
            self.check:SetShown(self.kitChecked)
            self:PaintState(self.ui.tokens)
        end,
        GetValue = function(self) return self.kitChecked end,
        SetChecked = function(self, on) self:SetValue(on) end,
        GetChecked = function(self) return self.kitChecked end,
        SetText = function(self, text)
            text = text or ""
            if text == self.label:GetText() then return end
            self.label:SetText(text)
            self:Changed()
        end,
        GetText = function(self) return self.label:GetText() end,
        Measure = function(self)
            local text = self.label:GetText() or ""
            return CHECK + (text ~= "" and (7 + math.ceil(UI.StringWidth(self.label))) or 0), 20
        end,
        Paint = function(self, t)
            UI.ApplyStyle(self.label, "body", t, nil, true)
            self:PaintState(t)
            self:Changed()
        end,
        PaintState = function(self, t)
            local enabled = self:IsEnabled()
            local color = t.text
            if not enabled then color = t.muted45 elseif self.kitChecked then color = t.accent end
            UI.TextColor(self.label, color)
            local drew = t.art and self.plate:Art(t.art.plate, 4, enabled and WHITE or DIM)
            if not drew then self.plate:Flat(t.surface, self.hover and enabled and t.accent65 or t.border) end
            self.check:SetColor(enabled and t.accent or t.muted45)
        end,
    },
}))

-- Sliders -------------------------------------------------------------------------------------

-- A plain horizontal slider with no Blizzard template. Spec: label, value,
-- bind, default, min (0), max (100), step (1), format (for the value beside
-- it, "%d%%"), onChange(value, slider). The wheel only turns a slider the
-- player has taken hold of (pressed, and not left since); passing over one
-- while scrolling the page must not change it unseen.
local function sliderShow(w, value)
    w.readout:SetText(w.kitFormat and string.format(w.kitFormat, value) or tostring(value))
    local width = w.slider:GetWidth() or 0
    local range = w.kitMax - w.kitMin
    local share = range > 0 and (value - w.kitMin) / range or 0
    if share < 0 then share = 0 elseif share > 1 then share = 1 end
    w.filled:SetWidth(math.max(0.01, width * share))
end

-- Sets the bar, held to the range; its OnValueChanged commits.
local function sliderMove(w, value)
    if value < w.kitMin then value = w.kitMin elseif value > w.kitMax then value = w.kitMax end
    w.slider:SetValue(value)
end

local function sliderChanged(slider, value)
    local w = slider.kitOwner
    local step = w.kitStep
    value = math.floor(value / step + 0.5) * step
    sliderShow(w, value)
    if w.kitSilent or value == w.kitValue then return end
    w.kitValue = value
    UI.Commit(w, value)
end

local function sliderWheel(slider, delta)
    local w = slider.kitOwner
    sliderMove(w, (w.kitValue or w.kitMin) + delta * w.kitStep)
end

local function sliderResized(slider)
    local w = slider.kitOwner
    sliderShow(w, w.kitValue or w.kitMin)
end

-- Held: the slider has the wheel, and shows it as a field shows focus. The
-- thumb fills and grows, the readout lights.
local function hold(w, held, quiet)
    w.kitHeld = held
    w.slider:EnableMouseWheel(held)
    if w.thumb then w.thumb:SetSize(held and 12 or 10, held and 16 or 14) end
    if not quiet then w:PaintState(w.ui.tokens) end
end

local function sliderEnter(slider)
    local w = slider.kitOwner
    w.hover = true
    w:PaintState(w.ui.tokens)
end

local function sliderLeave(slider)
    local w = slider.kitOwner
    w.hover = false
    hold(w, false)
end

local function sliderDown(slider) hold(slider.kitOwner, true) end
local function sliderHidden(slider)
    local w = slider.kitOwner
    if w.kitHeld then hold(w, false) end
end

-- Under full keyboard control the arrows move it.
local function sliderArrow(slider, key)
    local w = slider.kitOwner
    local delta = (key == "LEFT" or key == "DOWN") and -w.kitStep or w.kitStep
    sliderMove(w, (w.kitValue or w.kitMin) + delta)
end

UI.Define("Slider", {
    Build = function(w)
        w:SetSize(200, 18)
        w.label = UI.NewText(w)
        w.label:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
        w.readout = UI.NewText(w)
        w.readout:SetJustifyH("RIGHT")
        local slider = UI.NewFrame("Slider", nil, w)
        slider.kitOwner = w
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(16)
        w.track = slider:CreateTexture(nil, "BACKGROUND")
        w.track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        w.track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        UI.Stroke(w.track, "height", 2)
        w.filled = slider:CreateTexture(nil, "ARTWORK")
        w.filled:SetPoint("LEFT", slider, "LEFT", 0, 0)
        UI.Stroke(w.filled, "height", 2)
        pcall(slider.SetThumbTexture, slider, "Interface\\Buttons\\WHITE8x8")
        w.thumb = slider.GetThumbTexture and slider:GetThumbTexture()
        if w.thumb then
            w.thumb:SetSize(10, 14)
            local edge = UI.NewFrame("Frame", nil, slider)
            edge:SetAllPoints(w.thumb)
            w.thumbPlate = UI.NewPlate(edge, "OVERLAY")
        end
        slider:SetScript("OnValueChanged", sliderChanged)
        slider:SetScript("OnMouseWheel", sliderWheel)
        slider:SetScript("OnSizeChanged", sliderResized)
        slider:SetScript("OnEnter", sliderEnter)
        slider:SetScript("OnLeave", sliderLeave)
        slider:HookScript("OnMouseDown", sliderDown)
        slider:HookScript("OnHide", sliderHidden)
        slider.kitKeyArrow = sliderArrow
        w.slider = slider
    end,
    Init = function(w, spec)
        -- Quiet while it is set up: the bar may report the last use's value.
        w.kitSilent = true
        w.kitMin, w.kitMax, w.kitStep = spec.min or 0, spec.max or 100, spec.step or 1
        w.kitFormat = spec.format
        local labelled = spec.label ~= nil
        w.kitHeight = labelled and 36 or 18
        w.label:SetText(spec.label or "")
        w.label:SetShown(labelled)
        local slider, readout = w.slider, w.readout
        slider:ClearAllPoints()
        slider:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, 1)
        slider:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", labelled and 0 or -48, 1)
        readout:ClearAllPoints()
        if labelled then readout:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0) else readout:SetPoint("RIGHT", w, "RIGHT", 0, 0) end
        slider:SetMinMaxValues(w.kitMin, w.kitMax)
        slider:SetValueStep(w.kitStep)
        if slider.SetObeyStepOnDrag then pcall(slider.SetObeyStepOnDrag, slider, true) end
        w.hover = nil
        hold(w, false, true)
        slider.kitPooled = nil
        UI.RegisterFocusable(w.ui, slider, false)
        w.kitValue = nil
        w:SetValue(UI.InitValue(w, spec))
        w.kitSilent = false
    end,
    Release = function(w)
        hold(w, false, true)
        w.slider.kitPooled = true
        w.ui.focusables[w.slider] = nil
    end,
    methods = {
        SetValue = function(self, value)
            value = tonumber(value) or self.kitMin
            local silent = self.kitSilent
            self.kitSilent = true
            self.kitValue = value
            self.slider:SetValue(value)
            sliderShow(self, value)
            self.kitSilent = silent
        end,
        GetValue = function(self) return self.kitValue end,
        Measure = function(self) return 200, self.kitHeight end,
        Sized = function(self) sliderShow(self, self.kitValue or self.kitMin) end,
        Paint = function(self, t)
            UI.ApplyStyle(self.label, "label", t, "text")
            UI.ApplyStyle(self.readout, "number", t, nil, true)
            self:PaintState(t)
        end,
        PaintState = function(self, t)
            UI.TextColor(self.readout, self.kitHeld and t.accent or UI.Colour(t, UI.textStyles.number.color) or t.text)
            UI.TexColor(self.track, t.border)
            UI.TexColor(self.filled, t.accent)
            if self.thumb then
                UI.VertexColor(self.thumb, self.kitHeld and t.accent or (self.hover and t.raised or t.surface))
                self.thumbPlate:Flat(nil, t.accent)
            end
        end,
    },
})

-- Tab chains ------------------------------------------------------------------------------

-- A Tab order of the caller's own, for fields outside a window or in an
-- order other than the one they were made in. In a window it becomes the
-- window's order; outside one, Tab in each field goes to the next field of
-- the list that shows. A field made again from the pool leaves its chain.
function UI.Proto:TabChain(fields)
    if not fields or not fields[1] then return end
    local list = {}
    for _, field in ipairs(fields) do list[#list + 1] = field.box or field.slider or field end
    local win = UI.WindowOf(list[1])
    if win then
        win.kitTabOrder = list
        return
    end
    for _, box in ipairs(list) do
        if box.kitField then box.kitChain = list end
    end
end
