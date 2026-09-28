local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- Menus, ported from OpenRoad's one choice menu: built here rather than from
-- Blizzard's UIDropDownMenu, which differs between clients and taints what
-- touches it. There is one menu (and one submenu) per UI, made on first use.
--
-- An item is one of:
--   { caption, desc, value, onClick(item), key, tone = "danger", disabled, reason, keep }
--   { caption, check = true, value = on, onChange(on) }       -- a checkbox; stays open
--   { caption, group = "g", value = v, checked = true }       -- one of a radio group
--   { caption, items = { ... } }                               -- opens a submenu
--   { header = "text" }  or  { separator = true }
--
-- UI:OpenMenu(items, opts): `opts.anchor` a frame to hang under (by its left
-- edge, or `align = "right"`), or `at = "cursor"`; `current` the value to
-- mark as chosen and `onChoose(value, item)` for a select; `onChange(group,
-- value)` for radios; `search` for a filter box on top; `onClose`.

local PAD, INSET, MARK, GAP = 4, 10, 14, 8
local ROW, HEADER, SEPARATOR, MAX_WIDTH = 24, 22, 9, 380
local KEY_GAP = 18

local function entryVisible(item, filter)
    if not filter or filter == "" then return true end
    if item.separator or item.header then return false end
    return string.find(string.lower(item.caption or tostring(item.value or "")), string.lower(filter), 1, true) ~= nil
end

local function buildMenu(ui, isSub)
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu.plate = UI.NewPlate(menu)
    menu.shadow = menu:CreateTexture(nil, "BACKGROUND", nil, -7)
    menu.shadow:SetPoint("TOPLEFT", menu, "TOPLEFT", UI.Snap(menu, 3), -UI.Snap(menu, 3))
    menu.shadow:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", UI.Snap(menu, 4), -UI.Snap(menu, 5))
    menu.shadow:SetColorTexture(0, 0, 0, 0.35)
    menu.rows = {}
    menu.ui = ui

    if not isSub then
        -- A click anywhere else puts the menu away and goes no further, so
        -- the click on the drop-down that opened it closes it rather than
        -- opening it again.
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", function() menu:Hide() end)
        catcher:Hide()
        menu.catcher = catcher
        menu:SetFrameLevel(catcher:GetFrameLevel() + 10)

        -- The filter box of a searchable menu.
        local search = CreateFrame("EditBox", nil, menu)
        search.kitField = true
        search:SetAutoFocus(false)
        search:SetHeight(24)
        search:SetTextInsets(22, 6, 2, 2)
        search:SetFont(UI.FontFile(), 11, "")
        search.plate = UI.NewPlate(search)
        local lens = CreateFrame("Frame", nil, search)
        lens:SetSize(12, 12)
        lens:SetPoint("LEFT", search, "LEFT", 6, 0)
        search.lens = UI.NewGlyph(lens, "search", 11, 1.3)
        search:SetScript("OnTextChanged", function(b, userInput)
            if userInput then menu:Fill(menu.items, menu.opts, true) end
        end)
        search:SetScript("OnEscapePressed", function() menu:Hide() end)
        search:SetScript("OnEnterPressed", function()
            for index = 1, menu.count or 0 do
                local row = menu.rows[index]
                if row.item and not row.item.separator and not row.item.header and not row.item.disabled then
                    row:Click()
                    return
                end
            end
        end)
        search:Hide()
        menu.search = search
    end

    menu:SetScript("OnHide", function(m)
        if m.catcher then m.catcher:Hide() end
        if m.sub then m.sub:Hide() end
        if m.search then m.search:ClearFocus() end
        ui:HideTooltip()
        local onClose = m.opts and m.opts.onClose
        m.anchor = nil
        if not isSub then m.opts = nil end
        if onClose then onClose() end
    end)
    -- A menu whose window went away goes with it.
    menu:SetScript("OnUpdate", function(m)
        local anchor = m.anchor
        if anchor and anchor.IsVisible and not anchor:IsVisible() then m:Hide() end
    end)

    local function paintRow(row, t)
        local item = row.item
        if not item then return end
        UI.TexColor(row.line, t.hairline)
        UI.TexColor(row.highlight, row.hover and not item.disabled and not item.header and t.accentWash or nil)
        local color = t.text
        if item.header then color = t.muted
        elseif item.disabled then color = t.muted45
        elseif item.tone == "danger" then color = t.danger
        elseif row.current then color = t.accent end
        UI.ApplyStyle(row.caption, item.header and "fine" or "body", t, color)
        UI.ApplyStyle(row.desc, "fine", t, item.disabled and t.muted45 or t.muted)
        UI.ApplyStyle(row.key, "key", t)
        row.check:SetColor(item.disabled and t.muted45 or t.accent)
        row.arrow:SetColor(row.hover and t.accent or t.muted)
        row.box:Flat(t.surface, t.border)
    end
    menu.PaintRow = paintRow

    function menu:Row(index)
        local row = self.rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, self)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.line = row:CreateTexture(nil, "ARTWORK")
        UI.Hairline(row.line, "height")
        row.markFrame = CreateFrame("Frame", nil, row)
        row.markFrame:SetSize(MARK, MARK)
        row.check = UI.NewGlyph(row.markFrame, "check", 9, 2)
        row.boxFrame = CreateFrame("Frame", nil, row.markFrame)
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
        local arrowFrame = CreateFrame("Frame", nil, row)
        arrowFrame:SetSize(10, 10)
        arrowFrame:SetPoint("RIGHT", row, "RIGHT", -INSET + 2, 0)
        row.arrow = UI.NewGlyph(arrowFrame, "next", 7, 1.5)
        row:SetScript("OnEnter", function(r)
            r.hover = true
            paintRow(r, ui.tokens)
            local item = r.item
            if not item then return end
            -- Only a disabled entry has a tooltip, saying why.
            if item.disabled and item.reason then ui:Tooltip(r, item.reason, { anchor = "ANCHOR_RIGHT" }) end
            if not isSub then
                if item.items and not item.disabled then
                    menu:OpenSub(r)
                elseif menu.sub and menu.sub:IsShown() then
                    menu.sub:Hide()
                end
            end
        end)
        row:SetScript("OnLeave", function(r) r.hover = false; paintRow(r, ui.tokens); ui:HideTooltip() end)
        row:SetScript("OnClick", function(r) menu:Choose(r) end)
        self.rows[index] = row
        return row
    end

    -- What a click on a row does.
    function menu:Choose(row)
        local item = row.item
        if not item or item.separator or item.header or item.disabled then return end
        if item.items then
            if not isSub then self:OpenSub(row) end
            return
        end
        UI.ClickSound()
        local root = isSub and self.parentMenu or self
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
            if item.onClick then item.onClick(item) end
            self:Fill(self.items, self.opts, true)
            return
        end
        local chosen = not row.current
        root:Hide()
        if item.onClick then item.onClick(item) end
        if chosen and opts.onChoose and item.value ~= nil then opts.onChoose(item.value, item) end
    end

    function menu:OpenSub(row)
        if not self.sub then
            self.sub = buildMenu(ui, true)
            self.sub.parentMenu = self
        end
        local sub = self.sub
        if sub:IsShown() and sub.owner == row then return end
        sub.owner = row
        sub:SetFrameLevel(self:GetFrameLevel() + 10)
        sub:Fill(row.item.items, { anchor = row, side = true }, false)
    end

    -- Lays the rows out for `items`: as wide as the widest line, at least as
    -- wide as the anchor, never wider than a column of prose.
    function menu:Fill(items, opts, keepPlace)
        self.items, self.opts = items or {}, opts or {}
        opts = self.opts
        local t = ui.tokens
        local root = isSub and self.parentMenu or self
        local current = (root.opts or {}).current
        local filter = (not isSub and opts.search and self.search:GetText()) or nil
        local visible = {}
        for _, item in ipairs(self.items) do
            if entryVisible(item, filter) then visible[#visible + 1] = item end
        end
        local textLeft = INSET + MARK + GAP
        local width = 140
        if opts.anchor and opts.anchor.GetWidth and not opts.side and opts.at ~= "cursor" then
            width = math.max(width, opts.anchor:GetWidth() or 0)
        end
        for index, item in ipairs(visible) do
            local row = self:Row(index)
            row.item, row.hover = item, false
            row.current = not item.separator and not item.header and (
                (item.group and item.checked) or (current ~= nil and item.value == current and not item.check))
            if not (item.separator) then
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
        for index, item in ipairs(visible) do
            local row = self.rows[index]
            local height
            row:ClearAllPoints()
            row.caption:ClearAllPoints()
            row.desc:ClearAllPoints()
            row.markFrame:ClearAllPoints()
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
            local edge = UI.Pixels(self, 1)
            row:SetPoint("TOPLEFT", self, "TOPLEFT", edge, -UI.Snap(self, top))
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -edge, -UI.Snap(self, top))
            row:Show()
            paintRow(row, t)
            top = top + height
        end
        self.count = #visible
        for index = #visible + 1, #self.rows do
            self.rows[index]:Hide()
            self.rows[index].item = nil
        end
        if #visible == 0 and filter then
            self.empty = self.empty or UI.NewText(self)
            self.empty:ClearAllPoints()
            self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", INSET, -(top + 4))
            self.empty:SetText("Nothing matches.")
            UI.ApplyStyle(self.empty, "label", t)
            self.empty:Show()
            top = top + 24
        elseif self.empty then
            self.empty:Hide()
        end
        self:SetSize(UI.Snap(self, width), UI.Snap(self, top + PAD))
        self.plate:Flat(t.raised, t.border)
        if self.search then
            self.search.plate:Flat(t.surface, t.accent)
            self.search.lens:SetColor(t.muted)
            self.search:SetTextColor(t.text[1], t.text[2], t.text[3], 1)
        end

        if not keepPlace then
            self:ClearAllPoints()
            if opts.side then
                self:SetPoint("TOPLEFT", opts.anchor, "TOPRIGHT", UI.Snap(self, 2), UI.Snap(self, PAD))
            elseif opts.at == "cursor" and type(GetCursorPosition) == "function" then
                local x, y = GetCursorPosition()
                local scale = self:GetEffectiveScale() or 1
                self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", UI.Snap(self, x / scale), UI.Snap(self, y / scale))
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

    return menu
end

function Proto:OpenMenu(items, opts)
    opts = opts or {}
    self.kitMenu = self.kitMenu or buildMenu(self, false)
    local menu = self.kitMenu
    if menu:IsShown() then
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

local SELECT_HEIGHT = 24

-- The button of a select: caption at the left, a chevron at the right, an
-- accent edge while open or while the player's choice differs from the
-- default, and a reset beside it for that case. Optional label above.
local function selectFrame(ui, parent, opts)
    local frame = CreateFrame("Frame", nil, parent)
    local width = opts.width or 170
    frame.kitStretch = false
    local labelHeight = 0
    if opts.label then
        frame.label = UI.NewText(frame)
        frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.label:SetText(opts.label)
        labelHeight = 16
    end
    local button = UI.Proto.Button(ui, frame, "", { width = width, height = SELECT_HEIGHT })
    -- Under the label on a whole pixel; again whenever the layout sizes it,
    -- so a change of UI scale lands it back on the grid.
    local function placeButton()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -UI.Snap(frame, labelHeight))
        button:SetSize(UI.Snap(frame, width), UI.Snap(frame, SELECT_HEIGHT))
    end
    placeButton()
    frame.KitSized = placeButton
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -24, 0)
    button.label:SetJustifyH("LEFT")
    button.kitTextReserve = 34
    local chevronFrame = CreateFrame("Frame", nil, button)
    chevronFrame:SetSize(10, 10)
    chevronFrame:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.glyph = UI.NewGlyph(chevronFrame, "down", 8, 1.5)
    button.kitPressParts = { button.label, button.glyph }
    local ring = CreateFrame("Frame", nil, button)
    ring:SetAllPoints(button)
    ring.plate = UI.NewPlate(ring, "OVERLAY")
    local basePaint = ui.painters[button]
    ui.painters[button] = function(t)
        basePaint(t)
        local lit = button.kitOpen or (frame.kitStored and button:IsEnabled())
        if lit then ring.plate:Flat(nil, (button.kitOpen or button.hover) and t.accent or t.accent80) else ring.plate:Hide() end
    end
    frame.button = button
    if opts.default ~= nil then
        frame.reset = ui:ResetButton(frame, { onReset = function() frame:Reset() end })
        frame.reset:SetPoint("LEFT", button, "RIGHT", 6, 0)
    end
    frame:SetSize(width + (frame.reset and 40 or 0), SELECT_HEIGHT + labelHeight)
    frame.KitNaturalWidth = function() return width + (frame.reset and 40 or 0) end
    frame.KitNaturalHeight = function() return SELECT_HEIGHT + labelHeight end
    return frame
end

local function paintSelectFrame(frame, t)
    if frame.label then UI.ApplyStyle(frame.label, "label", t, "text") end
    frame.button:Repaint()
end

local function findOption(list, value)
    for _, item in ipairs(list or {}) do
        if not item.separator and not item.header and item.value == value then return item end
    end
end

-- A choice from a list. `opts`: label, options (menu items: { value,
-- caption, desc, disabled, reason } and separators), value, default (shows
-- the changed edge and a reset), onChange(value), width, placeholder,
-- search (a filter box on top).
UI.Define("Select", function(ui, parent, opts)
    opts = opts or {}
    local frame = selectFrame(ui, parent, opts)
    local button = frame.button
    frame.kitOptions = opts.options or {}

    local function refresh()
        local item = findOption(frame.kitOptions, frame.kitValue)
        button:SetText(item and (item.caption or tostring(item.value)) or (opts.placeholder or ""))
        frame.kitStored = opts.default ~= nil and frame.kitValue ~= opts.default
        if frame.reset then
            local default = findOption(frame.kitOptions, opts.default)
            frame.reset:SetStored(frame.kitStored, default and default.caption or nil)
        end
        button:Repaint()
    end
    function frame:GetValue() return self.kitValue end
    function frame:SetValue(value) self.kitValue = value; refresh() end
    function frame:SetOptions(list) self.kitOptions = list or {}; refresh() end
    function frame:SetEnabled(enabled, reason) button:SetEnabled(enabled, reason) end
    function frame:Reset()
        if opts.default == nil then return end
        self.kitValue = opts.default
        refresh()
        if opts.onChange then opts.onChange(self.kitValue) end
    end
    button.kitClick = function()
        ui:OpenMenu(frame.kitOptions, {
            anchor = button,
            current = frame.kitValue,
            search = opts.search,
            onChoose = function(value)
                frame.kitValue = value
                refresh()
                if opts.onChange then opts.onChange(value) end
            end,
            onClose = function() button.kitOpen = false; button:Repaint() end,
        })
        button.kitOpen = ui:MenuOpenFor(button)
        button:Repaint()
    end
    frame.kitValue = opts.value
    refresh()
    frame.kitLayout = UI.LayoutOptions(opts, "width")
    return ui:Finish(frame, opts, paintSelectFrame)
end)

-- A select for long lists: typing filters them.
UI.Define("SearchSelect", function(ui, parent, opts)
    local copy = {}
    for key, value in pairs(opts or {}) do copy[key] = value end
    copy.search = true
    return UI.Proto.Select(ui, parent, copy)
end)

-- Several at once. `opts.value` is a set { [value] = true }; onChange(set)
-- gets a new set each time. Headers group the options; All and None at the
-- foot.
UI.Define("MultiSelect", function(ui, parent, opts)
    opts = opts or {}
    local frame = selectFrame(ui, parent, opts)
    local button = frame.button
    local set = {}
    for key, on in pairs(opts.value or {}) do if on then set[key] = true end end

    local function copySet()
        local out = {}
        for key in pairs(set) do out[key] = true end
        return out
    end
    local function refresh()
        local names, total, chosen = {}, 0, 0
        for _, item in ipairs(opts.options or {}) do
            if not item.header and not item.separator then
                total = total + 1
                if set[item.value] then
                    chosen = chosen + 1
                    names[#names + 1] = item.caption or tostring(item.value)
                end
            end
        end
        local caption = chosen == 0 and "None" or (chosen == total and "All" or table.concat(names, ", "))
        button:SetText(caption)
    end
    local function changed()
        refresh()
        if opts.onChange then opts.onChange(copySet()) end
    end
    local function items()
        local list = {}
        for _, item in ipairs(opts.options or {}) do
            if item.header or item.separator then
                list[#list + 1] = item
            else
                list[#list + 1] = { caption = item.caption, desc = item.desc, disabled = item.disabled, reason = item.reason,
                    check = true, value = set[item.value] and true or false,
                    onChange = function(on) set[item.value] = on or nil; changed() end }
            end
        end
        list[#list + 1] = { separator = true }
        list[#list + 1] = { caption = "All", keep = true, onClick = function(_)
            for _, item in ipairs(opts.options or {}) do
                if not item.header and not item.separator and not item.disabled then set[item.value] = true end
            end
            changed()
            ui.kitMenu.items = items()
        end }
        list[#list + 1] = { caption = "None", keep = true, onClick = function(_)
            set = {}
            changed()
            ui.kitMenu.items = items()
        end }
        return list
    end
    function frame:GetValue() return copySet() end
    function frame:SetValue(value)
        set = {}
        for key, on in pairs(value or {}) do if on then set[key] = true end end
        refresh()
    end
    button.kitClick = function()
        ui:OpenMenu(items(), {
            anchor = button,
            onClose = function() button.kitOpen = false; button:Repaint() end,
        })
        button.kitOpen = ui:MenuOpenFor(button)
        button:Repaint()
    end
    refresh()
    frame.kitLayout = UI.LayoutOptions(opts, "width")
    return ui:Finish(frame, opts, paintSelectFrame)
end)
