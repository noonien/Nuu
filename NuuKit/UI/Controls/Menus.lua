local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- Menus (ported from OpenRoad's one choice
-- menu): built here rather than from Blizzard's UIDropDownMenu, which
-- differs between clients and taints what touches it. There is one menu
-- (and one submenu) per UI, made on first use; its rows are made once and
-- kept, so a menu opened again makes no new frames, only more rows when it
-- holds more items than ever before.
--
-- An item is one of:
--   { caption, desc, value, onClick(item), key, tone = "danger", disabled, reason, keep }
--   { caption, check = true, value = on, onChange(on, item) }  -- a checkbox; stays open
--   { caption, group = "g", value = v, checked = true }       -- one of a radio group
--   { caption, items = { ... } }                               -- opens a submenu
--   { header = "text" }  or  { separator = true }
--
-- ui:OpenMenu(items, opts): `opts.anchor` a frame to hang under (by its left
-- edge, or `align = "right"`; over it with `above`), or `at = "cursor"`; `current` the value to
-- mark as chosen and `onChoose(value, item, opts)` for a select;
-- `onChange(group, value, item)` for radios; `search` for a filter box on
-- top; `onClose(opts)`. The trailing `opts` of onChoose and onClose is new:
-- it lets a caller keep one opts table and shared functions, no closures.

local PAD, INSET, MARK, GAP = 4, 10, 14, 8
local ROW, HEADER, SEPARATOR, MAX_WIDTH = 24, 22, 9, 380
local KEY_GAP = 18

local function entryVisible(item, filter)
    if not filter or filter == "" then return true end
    if item.separator or item.header then return false end
    return string.find(string.lower(item.caption or tostring(item.value or "")), string.lower(filter), 1, true) ~= nil
end

-- Rows ---------------------------------------------------------------------------------

-- The colours of a row: what hover changes, and nothing that sets a font or
-- allocates.
local function paintRowState(row, t)
    local item = row.item
    if not item then return end
    UI.TexColor(row.line, t.hairline)
    UI.TexColor(row.highlight, row.hover and not item.disabled and not item.header and t.accentWash or nil)
    local color = t.text
    if item.header then color = t.muted
    elseif item.disabled then color = t.muted45
    elseif item.tone == "danger" then color = t.danger
    elseif row.current then color = t.accent end
    UI.TextColor(row.caption, color)
    UI.TextColor(row.desc, item.disabled and t.muted45 or t.muted)
    row.check:SetColor(item.disabled and t.muted45 or t.accent)
    row.arrow:SetColor(row.hover and t.accent or t.muted)
end

-- The whole row: fonts, the box, then the colours.
local function paintRow(row, t)
    local item = row.item
    if not item then return end
    UI.ApplyStyle(row.caption, item.header and "fine" or "body", t, nil, true)
    UI.ApplyStyle(row.desc, "fine", t, nil, true)
    UI.ApplyStyle(row.key, "key", t)
    row.box:Flat(t.surface, t.border)
    paintRowState(row, t)
end

local function rowEnter(row)
    local menu = row.kitMenu
    local ui = menu.ui
    row.hover = true
    paintRowState(row, ui.tokens)
    local item = row.item
    if not item then return end
    -- Only a disabled entry has a tooltip, saying why.
    if item.disabled and item.reason then ui:Tooltip(row, item.reason, { anchor = "ANCHOR_RIGHT" }) end
    if not menu.kitIsSub then
        if item.items and not item.disabled then
            menu:OpenSub(row)
        elseif menu.sub and menu.sub:IsShown() then
            menu.sub:Hide()
        end
    end
end

local function rowLeave(row)
    local ui = row.kitMenu.ui
    row.hover = false
    paintRowState(row, ui.tokens)
    ui:HideTooltip()
end

local function rowClick(row) row.kitMenu:Choose(row) end

-- The menu frame -----------------------------------------------------------------------

local function catcherClick(catcher) catcher.kitMenu:Hide() end

local function searchChanged(box, userInput)
    if not userInput then return end
    local menu = box.kitMenu
    menu:Fill(menu.items, menu.opts, true)
end

local function searchEscape(box) box.kitMenu:Hide() end

-- Enter in the filter takes the first entry left that can be chosen.
local function searchEnter(box)
    local menu = box.kitMenu
    for index = 1, menu.count or 0 do
        local row = menu.rows[index]
        local item = row.item
        if item and not item.separator and not item.header and not item.disabled then
            row:Click()
            return
        end
    end
end

local function menuHidden(menu)
    if menu.catcher then menu.catcher:Hide() end
    if menu.sub then menu.sub:Hide() end
    if menu.search then menu.search:ClearFocus() end
    menu.ui:HideTooltip()
    local opts = menu.opts
    local onClose = opts and opts.onClose
    menu.anchor = nil
    if not menu.kitIsSub then menu.opts = nil end
    if onClose then onClose(opts) end
end

-- A menu whose window went away goes with it.
local function menuTick(menu)
    local anchor = menu.anchor
    if anchor and anchor.IsVisible and not anchor:IsVisible() then menu:Hide() end
end

local Menu = {}

-- Row `index`, made the first time a menu needs that many.
function Menu:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = UI.NewFrame("Button", nil, self)
    row.kitMenu = self
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.line = row:CreateTexture(nil, "ARTWORK")
    UI.Hairline(row.line, "height")
    row.markFrame = UI.NewFrame("Frame", nil, row)
    row.markFrame:SetSize(MARK, MARK)
    row.check = UI.NewGlyph(row.markFrame, "check", 9, 2)
    row.boxFrame = UI.NewFrame("Frame", nil, row.markFrame)
    row.boxFrame:SetSize(12, 12)
    row.boxFrame:SetPoint("CENTER")
    row.box = UI.NewPlate(row.boxFrame)
    row.caption = UI.NewText(row)
    row.desc = UI.NewText(row)
    if row.desc.SetWordWrap then row.desc:SetWordWrap(true) end
    row.desc:SetJustifyV("TOP")
    row.key = UI.NewText(row)
    row.key:SetJustifyH("RIGHT")
    row.key:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)
    local arrowFrame = UI.NewFrame("Frame", nil, row)
    arrowFrame:SetSize(10, 10)
    arrowFrame:SetPoint("RIGHT", row, "RIGHT", -INSET + 2, 0)
    row.arrow = UI.NewGlyph(arrowFrame, "next", 7, 1.5)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    row:SetScript("OnClick", rowClick)
    self.rows[index] = row
    return row
end

-- What a click on a row does.
function Menu:Choose(row)
    local item = row.item
    if not item or item.separator or item.header or item.disabled then return end
    if item.items then
        if not self.kitIsSub then self:OpenSub(row) end
        return
    end
    UI.ClickSound()
    local root = self.kitIsSub and self.kitParentMenu or self
    local opts = root.opts or {}
    if item.check then
        item.value = not item.value
        if item.onChange then item.onChange(item.value, item) end
        self:Fill(self.items, self.opts, true)
        return
    end
    if item.group then
        if opts.onChange then opts.onChange(item.group, item.value, item) end
        if item.onClick then item.onClick(item) end
        root:Hide()
        return
    end
    if item.keep then
        -- Stays open, drawn again: what onClick changed in the items shows.
        if item.onClick then item.onClick(item) end
        self:Fill(self.items, self.opts, true)
        return
    end
    local chosen = not row.current
    root:Hide()
    if item.onClick then item.onClick(item) end
    if chosen and opts.onChoose and item.value ~= nil then opts.onChoose(item.value, item, opts) end
end

function Menu:OpenSub(row)
    local sub = self.sub
    if not sub then
        sub = UI.BuildMenu(self.ui, self)
        self.sub = sub
    end
    if sub:IsShown() and sub.owner == row then return end
    sub.owner = row
    sub:SetFrameLevel(self:GetFrameLevel() + 10)
    sub.kitSubOpts = sub.kitSubOpts or { side = true }
    sub.kitSubOpts.anchor = row
    sub:Fill(row.item.items, sub.kitSubOpts, false)
end

-- The frame's own colours: the plate, the filter box.
function Menu:PaintFrame(t)
    self.plate:Flat(t.raised, t.border)
    local search = self.search
    if search then
        UI.ApplyStyle(search, "body", t)
        search.plate:Flat(t.surface, t.accent)
        search.lens:SetColor(t.muted)
    end
    if self.empty then UI.ApplyStyle(self.empty, "label", t) end
end

-- Lays the rows out for `items`: as wide as the widest line, at least as
-- wide as the anchor, never wider than a column of prose.
function Menu:Fill(items, opts, keepPlace)
    self.items, self.opts = items or {}, opts or {}
    opts = self.opts
    local t = self.ui.tokens
    local root = self.kitIsSub and self.kitParentMenu or self
    local current = root.opts and root.opts.current
    local filter = (not self.kitIsSub and opts.search and self.search:GetText()) or nil
    local visible = self.kitVisible
    local count = 0
    for _, item in ipairs(self.items) do
        if entryVisible(item, filter) then
            count = count + 1
            visible[count] = item
        end
    end
    for index = #visible, count + 1, -1 do visible[index] = nil end

    local textLeft = INSET + MARK + GAP
    local width = 140
    if opts.anchor and opts.anchor.GetWidth and not opts.side and opts.at ~= "cursor" then
        width = math.max(width, opts.anchor:GetWidth() or 0)
    end
    for index = 1, count do
        local item = visible[index]
        local row = self:Row(index)
        row.item, row.hover = item, false
        row.current = not item.separator and not item.header and (
            (item.group and item.checked) or (current ~= nil and item.value == current and not item.check)) or false
        if item.separator then
            row.caption:SetText("")
            row.desc:SetText("")
            row.key:SetText("")
            paintRow(row, t)
        else
            row.caption:SetWidth(0)
            row.caption:SetText(item.header or item.caption or tostring(item.value or ""))
            row.desc:SetText(item.desc or "")
            row.key:SetText(item.key or "")
            paintRow(row, t)
            local wanted = UI.StringWidth(row.caption)
            if item.desc and item.desc ~= "" then
                row.desc:SetWidth(0)
                wanted = math.max(wanted, UI.StringWidth(row.desc))
            end
            if item.key then wanted = wanted + KEY_GAP + UI.StringWidth(row.key) end
            if item.items then wanted = wanted + KEY_GAP end
            width = math.max(width, textLeft + wanted + INSET + 2)
        end
    end
    width = math.floor(math.min(width, MAX_WIDTH) + 0.5)
    local textWidth = width - textLeft - INSET - 2

    local top = PAD
    if self.search then
        self.search:SetShown(opts.search and true or false)
        if opts.search then
            self.search:ClearAllPoints()
            self.search:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -6)
            self.search:SetPoint("TOPRIGHT", self, "TOPRIGHT", -6, -6)
            top = 6 + 24 + 6
        end
    end
    local edge = UI.Pixels(self, 1)
    for index = 1, count do
        local item = visible[index]
        local row = self.rows[index]
        local height
        row:ClearAllPoints()
        row.caption:ClearAllPoints()
        row.desc:ClearAllPoints()
        row.markFrame:ClearAllPoints()
        row.line:ClearAllPoints()
        if item.separator then
            height = SEPARATOR
            -- Across the middle, on a whole pixel.
            local middle = UI.Snap(self, math.floor(SEPARATOR / 2))
            row.line:SetPoint("TOPLEFT", row, "TOPLEFT", UI.Snap(self, INSET), -middle)
            row.line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -UI.Snap(self, INSET), -middle)
            row.line:Show(); row.caption:Hide(); row.desc:Hide(); row.key:Hide()
            row.check:SetShown(false); row.boxFrame:Hide(); row.arrow:SetShown(false)
            row:EnableMouse(false)
        elseif item.header then
            height = HEADER
            row.line:Hide(); row.caption:Show(); row.desc:Hide(); row.key:Hide()
            row.check:SetShown(false); row.boxFrame:Hide(); row.arrow:SetShown(false)
            row.caption:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", INSET, 3)
            row:EnableMouse(false)
        else
            row.line:Hide(); row.caption:Show(); row.key:SetShown(item.key ~= nil)
            row:EnableMouse(true)
            local captionWidth = textWidth - (item.key and (KEY_GAP + UI.StringWidth(row.key)) or 0) - (item.items and KEY_GAP or 0)
            row.caption:SetWidth(captionWidth)
            local hasDesc = item.desc and item.desc ~= ""
            local captionHeight = row.caption:GetStringHeight() or 12
            height = ROW
            if hasDesc then
                row.desc:SetWidth(textWidth)
                height = 5 + captionHeight + 2 + (row.desc:GetStringHeight() or 12) + 6
                row.caption:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -5)
                row.desc:SetPoint("TOPLEFT", row.caption, "BOTTOMLEFT", 0, -2)
                row.desc:Show()
            else
                row.caption:SetPoint("LEFT", row, "LEFT", textLeft, 0)
                row.desc:Hide()
            end
            row.markFrame:SetPoint("CENTER", row.caption, "LEFT", -(GAP + MARK / 2), 0)
            row.boxFrame:SetShown(item.check and true or false)
            row.check:SetShown((item.check and item.value) or (not item.check and row.current) and true or false)
            row.arrow:SetShown(item.items ~= nil)
        end
        height = UI.Snap(self, height)
        row:SetHeight(height)
        row:SetPoint("TOPLEFT", self, "TOPLEFT", edge, -UI.Snap(self, top))
        row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -edge, -UI.Snap(self, top))
        row:Show()
        top = top + height
    end
    self.count = count
    for index = count + 1, #self.rows do
        self.rows[index]:Hide()
        self.rows[index].item = nil
    end
    if count == 0 and filter then
        local empty = self.empty
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", self, "TOPLEFT", INSET, -(top + 4))
        empty:Show()
        top = top + 24
    elseif self.empty then
        self.empty:Hide()
    end
    self:SetSize(UI.Snap(self, width), UI.Snap(self, top + PAD))
    self:PaintFrame(t)

    if not keepPlace then
        self:ClearAllPoints()
        if opts.side then
            self:SetPoint("TOPLEFT", opts.anchor, "TOPRIGHT", UI.Snap(self, 2), UI.Snap(self, PAD))
        elseif opts.at == "cursor" and type(GetCursorPosition) == "function" then
            local x, y = GetCursorPosition()
            local scale = self:GetEffectiveScale() or 1
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", UI.Snap(self, x / scale), UI.Snap(self, y / scale))
        elseif opts.above then
            local side = opts.align == "right" and "RIGHT" or "LEFT"
            self:SetPoint("BOTTOM" .. side, opts.anchor, "TOP" .. side, 0, UI.Snap(self, 3))
        elseif opts.align == "right" then
            self:SetPoint("TOPRIGHT", opts.anchor, "BOTTOMRIGHT", 0, -UI.Snap(self, 3))
        else
            self:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, -UI.Snap(self, 3))
        end
        self.anchor = opts.anchor
        if self.catcher then self.catcher:Show() end
        self:Show()
        self:Raise()
        if self.search and opts.search then self.search:SetFocus() end
    end
end

-- A look change repaints an open menu (and lays it out again, for a new
-- text size); a closed one is painted when it next opens.
local function repaintMenu(menu, t)
    if menu:IsShown() and menu.items then
        menu:Fill(menu.items, menu.opts, true)
    else
        menu:PaintFrame(t)
    end
end

-- The menu of `ui`; with `parentMenu`, its submenu.
function UI.BuildMenu(ui, parentMenu)
    local isSub = parentMenu ~= nil
    local menu = UI.NewFrame("Frame", nil, UIParent)
    for key, fn in pairs(Menu) do menu[key] = fn end
    menu.ui = ui
    menu.kitIsSub = isSub or nil
    menu.kitParentMenu = parentMenu
    menu.rows = {}
    menu.kitVisible = {}
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu.plate = UI.NewPlate(menu)
    menu.shadow = menu:CreateTexture(nil, "BACKGROUND", nil, -7)
    menu.shadow:SetPoint("TOPLEFT", menu, "TOPLEFT", UI.Snap(menu, 3), -UI.Snap(menu, 3))
    menu.shadow:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", UI.Snap(menu, 4), -UI.Snap(menu, 5))
    menu.shadow:SetColorTexture(0, 0, 0, 0.35)

    if not isSub then
        -- A click anywhere else puts the menu away and goes no further, so
        -- the click on the drop-down that opened it closes it rather than
        -- opening it again.
        local catcher = UI.NewFrame("Button", nil, UIParent)
        catcher.kitMenu = menu
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", catcherClick)
        catcher:Hide()
        menu.catcher = catcher
        menu:SetFrameLevel(catcher:GetFrameLevel() + 10)

        -- The filter box of a searchable menu.
        local search = UI.NewFrame("EditBox", nil, menu)
        search.kitMenu = menu
        search.kitField = true
        search:SetAutoFocus(false)
        search:SetHeight(24)
        search:SetTextInsets(22, 6, 2, 2)
        search.plate = UI.NewPlate(search)
        local lens = UI.NewFrame("Frame", nil, search)
        lens:SetSize(12, 12)
        lens:SetPoint("LEFT", search, "LEFT", 6, 0)
        search.lens = UI.NewGlyph(lens, "search", 11, 1.3)
        search:SetScript("OnTextChanged", searchChanged)
        search:SetScript("OnEscapePressed", searchEscape)
        search:SetScript("OnEnterPressed", searchEnter)
        search:Hide()
        menu.search = search

        menu.empty = UI.NewText(menu)
        menu.empty:SetText("Nothing matches.")
        menu.empty:Hide()
    end

    menu:SetScript("OnHide", menuHidden)
    menu:SetScript("OnUpdate", menuTick)
    ui:Paint(menu, function(t) repaintMenu(menu, t) end)
    return menu
end

function Proto:OpenMenu(items, opts)
    opts = opts or {}
    local menu = self.kitMenu
    if not menu then
        menu = UI.BuildMenu(self, nil)
        self.kitMenu = menu
    end
    if menu:IsShown() then
        -- Opened again from the same anchor: the second click closes it.
        local same = opts.anchor ~= nil and menu.anchor == opts.anchor
        menu:Hide()
        if same then return end
    end
    if menu.search then menu.search:SetText("") end
    menu:Fill(items or {}, opts, false)
    return menu
end

function Proto:CloseMenu()
    if self.kitMenu and self.kitMenu:IsShown() then self.kitMenu:Hide() end
end

function Proto:MenuOpenFor(anchor)
    return self.kitMenu and self.kitMenu:IsShown() and self.kitMenu.anchor == anchor or false
end

-- Selects ---------------------------------------------------------------------------------

-- The button of a select: caption at the left, a chevron at the right, an
-- accent edge while open or while the player's choice is stored (or, not
-- bound, differs from the default), and a reset beside it for that case.
-- Optional label above.
--
-- Spec, shared by the three: label, options (menu items: { value, caption,
-- desc, disabled, reason }, headers and separators), value, default, bind,
-- onChange(value, w), boxWidth (the button's width, 170; `width` is the
-- whole widget's, reset included), placeholder, search,
-- tooltip, disabled (or a reason).
local SELECT_HEIGHT, SELECT_WIDTH, LABEL_HEIGHT, RESET_ROOM = 24, 170, 16, 40

local function findOption(list, value)
    for _, item in ipairs(list or {}) do
        if not item.separator and not item.header and item.value == value then return item end
    end
end

local function copySet(set)
    local out = {}
    for key, on in pairs(set or {}) do if on then out[key] = true end end
    return out
end

local function sameSet(a, b)
    a, b = a or {}, b or {}
    for key, on in pairs(a) do if on and not b[key] then return false end end
    for key, on in pairs(b) do if on and not a[key] then return false end end
    return true
end

-- Whether the reset shows: bound, while the table holds a choice; else
-- while the value is not the default.
local function storedOf(w)
    if w.kitDefault == nil then return false end
    if w.kitBind then return w:IsStored() end
    if w.kitMulti then return not sameSet(w.kitSet, w.kitDefault) end
    return w.kitValue ~= w.kitDefault
end

local function refresh(w)
    local button = w.button
    if w.kitMulti then
        local names, total, chosen = {}, 0, 0
        for _, item in ipairs(w.kitOptions) do
            if not item.header and not item.separator then
                total = total + 1
                if w.kitSet[item.value] then
                    chosen = chosen + 1
                    names[#names + 1] = item.caption or tostring(item.value)
                end
            end
        end
        button:SetText(chosen == 0 and "None" or (chosen == total and "All" or table.concat(names, ", ")))
    else
        local item = findOption(w.kitOptions, w.kitValue)
        button:SetText(item and (item.caption or tostring(item.value)) or (w.kitPlaceholder or ""))
    end
    w.kitStored = storedOf(w)
    if w.reset and w.kitDefault ~= nil then
        local text
        if w.kitMulti then
            text = nil
        else
            local default = findOption(w.kitOptions, w.kitDefault)
            text = default and (default.caption or tostring(default.value)) or nil
        end
        w.reset:SetStored(w.kitStored, text)
    end
    w:PaintState(w.ui.tokens)
end

-- The button under the label, and the reset beside it, on whole pixels;
-- again whenever the layout sizes the select.
local function placeParts(w, width)
    local room = w.kitResetRoom
    local buttonWidth = math.max(SELECT_HEIGHT, (width or (w.kitBoxWidth + room)) - room)
    local button = w.button
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -UI.Snap(w, w.kitLabelHeight))
    buttonWidth, room = UI.Snap(w, buttonWidth), UI.Snap(w, SELECT_HEIGHT)
    if button.kitPW ~= buttonWidth or button.kitPH ~= room then
        button:SetSize(buttonWidth, room)
        button.kitPW, button.kitPH = buttonWidth, room
        button:Sized(buttonWidth, room)
    end
end

-- The player's choice, from the menu.
local function selectChosen(value, _, opts)
    local w = opts.kitOwner
    w.kitValue = value
    UI.Commit(w, value)
    refresh(w)
end

local function selectClosed(opts)
    local w = opts.kitOwner
    w.kitOpen = false
    w:PaintState(w.ui.tokens)
end

-- A MultiSelect's menu: its options as checks, then All and None. Made once
-- per list of options; the checks' values are set from the set each time
-- it opens, and again by All and None, so the open menu redraws from them.
local function multiSync(w)
    for _, item in ipairs(w.kitItems) do
        if item.check then item.value = w.kitSet[item.kitKey] and true or false end
    end
end

-- Into the bound table first, so the reset's state is read from it.
local function multiChanged(w)
    UI.Commit(w, copySet(w.kitSet))
    refresh(w)
end

local function multiCheck(on, item)
    local w = item.kitOwner
    w.kitSet[item.kitKey] = on and true or nil
    multiChanged(w)
end

local function multiAll(item)
    local w = item.kitOwner
    for _, option in ipairs(w.kitOptions) do
        if not option.header and not option.separator and not option.disabled then w.kitSet[option.value] = true end
    end
    multiSync(w)
    multiChanged(w)
end

local function multiNone(item)
    local w = item.kitOwner
    for key in pairs(w.kitSet) do w.kitSet[key] = nil end
    multiSync(w)
    multiChanged(w)
end

local function multiItems(w)
    if w.kitItems then return w.kitItems end
    local list = {}
    for _, option in ipairs(w.kitOptions) do
        if option.header or option.separator then
            list[#list + 1] = option
        else
            list[#list + 1] = { caption = option.caption or tostring(option.value), desc = option.desc,
                disabled = option.disabled, reason = option.reason, check = true, value = false,
                onChange = multiCheck, kitOwner = w, kitKey = option.value }
        end
    end
    list[#list + 1] = { separator = true }
    list[#list + 1] = { caption = "All", keep = true, onClick = multiAll, kitOwner = w }
    list[#list + 1] = { caption = "None", keep = true, onClick = multiNone, kitOwner = w }
    w.kitItems = list
    return list
end

local function selectClick(button)
    local w = button.kitSelect
    local ui = w.ui
    local opts = w.kitMenuOpts
    if w.kitMulti then
        local items = multiItems(w)
        multiSync(w)
        opts.current, opts.search, opts.onChoose = nil, nil, nil
        ui:OpenMenu(items, opts)
    else
        opts.current, opts.search, opts.onChoose = w.kitValue, w.kitSearch or nil, selectChosen
        ui:OpenMenu(w.kitOptions, opts)
    end
    w.kitOpen = ui:MenuOpenFor(button)
    w:PaintState(ui.tokens)
end

local function buttonHover(button)
    local w = button.kitSelect
    w:PaintState(w.ui.tokens)
end

local function resetClick(link) link.kitSelect:Reset() end

local function buildSelect(w)
    local ui = w.ui
    w:SetSize(SELECT_WIDTH, SELECT_HEIGHT)
    w.label = UI.NewText(w)
    w.label:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
    local button = UI.Make(ui, "Button", w, { "", width = SELECT_WIDTH, height = SELECT_HEIGHT })
    button.kitSelect = w
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -24, 0)
    button.label:SetJustifyH("LEFT")
    button.kitTextReserve = 34
    local chevronFrame = UI.NewFrame("Frame", nil, button)
    chevronFrame:SetSize(10, 10)
    chevronFrame:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    w.chevron = UI.NewGlyph(chevronFrame, "down", 8, 1.5)
    button.kitPressParts = { button.label, w.chevron }
    button:SetOnClick(selectClick)
    button:HookScript("OnEnter", buttonHover)
    button:HookScript("OnLeave", buttonHover)
    local ring = UI.NewFrame("Frame", nil, button)
    ring:SetAllPoints(button)
    ring.plate = UI.NewPlate(ring, "OVERLAY")
    w.ring = ring
    w.button = button
    w.kitMenuOpts = { anchor = button, kitOwner = w, onClose = selectClosed }
end

local function initSelect(w, spec)
    local ui = w.ui
    w.kitMulti = w.kitType == "MultiSelect" or nil
    w.kitSearch = (w.kitType == "SearchSelect" or spec.search) and true or nil
    w.kitOptions = spec.options or {}
    w.kitItems = nil
    w.kitPlaceholder = spec.placeholder
    w.kitBoxWidth = spec.boxWidth or SELECT_WIDTH
    w.kitOpen = false
    w.label:SetText(spec.label or "")
    w.label:SetShown(spec.label ~= nil)
    w.kitLabelHeight = spec.label and LABEL_HEIGHT or 0
    -- The tooltip is the button's, which also says why it is disabled.
    w.tooltip = nil
    local button = w.button
    button.tooltip = spec.tooltip
    button.hover = false
    button:SetEnabled(not spec.disabled, type(spec.disabled) == "string" and spec.disabled or nil)
    local value = UI.InitValue(w, spec)
    if w.kitDefault ~= nil and not w.reset then
        w.reset = UI.Make(ui, "ResetButton", w, { onReset = resetClick })
        w.reset.kitSelect = w
        w.reset:SetPoint("LEFT", button, "RIGHT", 6, 0)
        UI.Fit(w.reset)
    end
    if w.reset then w.reset:SetShown(false) end
    w.kitResetRoom = w.kitDefault ~= nil and RESET_ROOM or 0
    if w.kitMulti then
        w.kitSet = w.kitSet or {}
        for key in pairs(w.kitSet) do w.kitSet[key] = nil end
        for key, on in pairs(value or {}) do if on then w.kitSet[key] = true end end
        w.kitValue = nil
    else
        w.kitValue = value
    end
    placeParts(w, nil)
    refresh(w)
end

local selectMethods = {
    GetValue = function(self)
        if self.kitMulti then return copySet(self.kitSet) end
        return self.kitValue
    end,
    -- From code: never calls onChange, and leaves the bound table alone.
    SetValue = function(self, value)
        if self.kitMulti then
            for key in pairs(self.kitSet) do self.kitSet[key] = nil end
            for key, on in pairs(value or {}) do if on then self.kitSet[key] = true end end
        else
            self.kitValue = value
        end
        refresh(self)
    end,
    SetOptions = function(self, list)
        self.kitOptions = list or {}
        self.kitItems = nil
        refresh(self)
    end,
    GetOptions = function(self) return self.kitOptions end,
    SetEnabled = function(self, enabled, reason)
        self.button:SetEnabled(enabled, reason)
        self:PaintState(self.ui.tokens)
    end,
    IsEnabled = function(self) return self.button:IsEnabled() end,
    IsOpen = function(self) return self.kitOpen end,
    -- Back to the default; nothing to do with neither a default nor a
    -- bound table.
    Reset = function(self)
        if self.kitDefault == nil and not self.kitBind then return end
        UI.Widget.Reset(self)
    end,
    Measure = function(self)
        return self.kitBoxWidth + self.kitResetRoom, SELECT_HEIGHT + self.kitLabelHeight
    end,
    Sized = function(self, width) placeParts(self, width) end,
    Paint = function(self, t)
        UI.ApplyStyle(self.label, "label", t, "text")
        self:PaintState(t)
    end,
    -- The accent edge and the chevron: colours only.
    PaintState = function(self, t)
        local button = self.button
        local ring = self.ring.plate
        if self.kitOpen or (self.kitStored and button:IsEnabled()) then
            ring:Flat(nil, (self.kitOpen or button.hover) and t.accent or t.accent80)
        else
            ring:Hide()
        end
        local state = UI.ButtonState(button)
        local _, _, ink = UI.ButtonColorsOf(t, nil, nil, state)
        if button.plate.nineShown then
            ink = state == "disabled" and t.muted45 or (state == "active" and t.accent or t.text)
        end
        self.chevron:SetColor(ink)
    end,
}

local function selectType()
    return {
        stretch = false,
        Build = buildSelect,
        Init = initSelect,
        Release = function(w)
            if w.ui:MenuOpenFor(w.button) then w.ui:CloseMenu() end
            w.kitOpen = false
        end,
        methods = selectMethods,
    }
end

-- A choice from a list: `col:Select{ label = "Route by", options = {...},
-- value = "few", default = "cheap", onChange = fn(value, w) }`.
UI.Define("Select", selectType())

-- A select for long lists: typing filters them.
UI.Define("SearchSelect", selectType())

-- Several at once. The value is a set { [value] = true }; GetValue and
-- onChange(set, w) give a new set each time. Headers group the options; All
-- and None at the foot. A `default` set shows the reset, as a Select's.
UI.Define("MultiSelect", selectType())
