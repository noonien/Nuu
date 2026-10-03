local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local L = UI.ListParts

-- Tables, pagers and stat figures, for the planner's Plan, Recipes and Materials tabs and
-- the like.

-- Tables ---------------------------------------------------------------------------------

-- A list with column heads, cells in line under them, groups that fold and a
-- footer, on a List (rows made once and reused). Spec:
--   columns    { key, caption, width | grow, align ("left", "right",
--              "center"), tooltip (on the head), money (copper, shown in
--              coins), number (the number face), color(item) (a token name
--              or colour), text(item) (what the cell says, else item[key]),
--              make(ui, cell) (a widget for the cell instead of text, made
--              in the placed form: `ui:Button(cell, {...})`; once per row),
--              draw(widget, item) (each time the row shows an item) }
--   rowHeight  default 26, or 32 when a column makes a widget
--   rows       how many rows tall it wants to be when not growing
--   footer     true for a footer line (see SetFooter)
--   onPick(item), onActivate(item), onRightClick(item, row), tooltip(item,
--   row) (as a List's), search,
--   filter(item, text) (else the first column's text), empty, grow
-- Items are tables; one with `rows` is a group of them: { caption, rows,
-- open }, folded by a click on its line (the kit keeps `open`).
-- Select(item) from code does not call onPick (see Lists.lua).
local PAD_LEFT, PAD_RIGHT, GAP, INDENT, HEAD = 10, 8, 12, 18, 28

-- Where each column sits in a line `width` wide: { x, w } per column.
function UI.TableColumns(columns, width, spots)
    local fixed, weights = 0, 0
    for _, column in ipairs(columns) do
        if column.width then fixed = fixed + column.width
        else weights = weights + ((type(column.grow) == "number" and column.grow) or 1) end
    end
    local spare = math.max(0, width - PAD_LEFT - PAD_RIGHT - GAP * math.max(0, #columns - 1) - fixed)
    spots = spots or {}
    local x = PAD_LEFT
    for index, column in ipairs(columns) do
        local w = column.width or (weights > 0 and spare * ((type(column.grow) == "number" and column.grow) or 1) / weights or 0)
        local spot = spots[index] or {}
        spot.x, spot.w = x, w
        spots[index] = spot
        x = x + w + GAP
    end
    for index = #columns + 1, #spots do spots[index] = nil end
    return spots
end

local function cellText(column, item)
    local value
    if column.text then value = column.text(item) elseif column.key then value = item[column.key] end
    if value == nil then return "" end
    if column.money and tonumber(value) then return Kit.FormatMoney(tonumber(value)) end
    return tostring(value)
end

local JUSTIFY = { right = "RIGHT", center = "CENTER" }

-- The spots for a line `width` wide, kept while the width and columns stay:
-- every row, the head and the footer share one width.
local function spotsFor(tbl, width)
    if tbl.kitSpotsWidth ~= width or tbl.kitSpotsColumns ~= tbl.kitColumns then
        tbl.kitSpots = UI.TableColumns(tbl.kitColumns, width, tbl.kitSpots)
        tbl.kitSpotsWidth, tbl.kitSpotsColumns = width, tbl.kitColumns
    end
    return tbl.kitSpots
end

-- A cell's widget at the cell's left: across it, unless its type keeps its
-- own width; no taller than the line.
local function placeWidget(widget, cell, width, lineHeight)
    local w = widget.kitStretch == false and widget:NaturalWidth() or width
    local h = math.min(widget:NaturalHeight(w), lineHeight)
    w, h = math.max(0.01, UI.Snap(cell, w)), math.max(0.01, UI.Snap(cell, h))
    if widget.kitCell ~= cell then
        widget.kitCell = cell
        widget:ClearAllPoints()
        widget:SetPoint("LEFT", cell, "LEFT", 0, 0)
    end
    if widget.kitPW ~= w or widget.kitPH ~= h then
        widget.kitPW, widget.kitPH = w, h
        widget:SetSize(w, h)
        if widget.Sized then widget:Sized(w, h) end
        if widget.kitChildren or widget.kitInner then UI.Invalidate(widget) end
    end
end

-- Lays a line's cells out under the columns, skipping what did not move. A
-- row is the list's width already; the head and footer are the table's, so
-- they take the list's inset (`shift`) and leave its scroll bar's room, and
-- every column lines up. `indent` moves the first cell in.
local function placeCells(tbl, line, cells, indent, shift, width, lineHeight)
    if not width or width <= 0 then return end
    local spots = spotsFor(tbl, width)
    for index = 1, #tbl.kitColumns do
        local cell, spot = cells[index], spots[index]
        local x, w = shift + spot.x, spot.w
        if index == 1 and indent then x, w = x + indent, math.max(0, w - indent) end
        local left = UI.Snap(line, x)
        local cw = math.max(0.01, UI.Snap(line, x + w) - left)
        if cell.kitX ~= left then
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", line, "TOPLEFT", left, 0)
            cell:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", left, 0)
            cell.kitX = left
        end
        if cell.kitW ~= cw then
            cell.kitW = cw
            cell:SetWidth(cw)
        end
        if cell.widget then placeWidget(cell.widget, cell, cw, lineHeight) end
    end
end

-- A cell: a frame with a line of text, or holding a column's widget.
local function newCell(line)
    local cell = UI.NewFrame("Frame", nil, line)
    cell.text = UI.NewText(cell)
    cell.text:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    return cell
end

-- A cell for `column`: its words' justify, its widget gone.
local function resetCell(cell, column)
    if cell.widget then
        cell.widget.kitCell = nil
        UI.Release(cell.widget)
        cell.widget = nil
    end
    cell.kitX, cell.kitW = nil, nil
    cell.text:SetJustifyH(JUSTIFY[column.align] or "LEFT")
    cell.text:SetText("")
    cell:Show()
end

-- The head and the footer: lines of text cells the table stacks. They
-- answer the layout as widgets do.
local function lineSized(line, width)
    local tbl = line.kitTable
    placeCells(tbl, line, line.cells, nil, 1, (width or line.kitPW or 0) - UI.SCROLLBAR - 2, HEAD)
end

local function lineMeasure(line) return 0, line.kitHeight end

local function newLine(w, height)
    local line = UI.NewFrame("Frame", nil, w)
    UI.Adopt(line, "TableLine", { UI.Widget }, { Measure = lineMeasure, Sized = lineSized })
    line.ui, line.kitTable, line.kitHeight = w.ui, w, height
    line.kitLayout = {}
    line.plate = UI.NewPlate(line)
    line.cells = {}
    return line
end

-- Its cells for the table's columns, made once and kept for the next.
local function setLineColumns(line, columns, head)
    for index, column in ipairs(columns) do
        local cell = line.cells[index] or newCell(line)
        line.cells[index] = cell
        resetCell(cell, column)
        if head then
            cell.text:SetText(column.caption or "")
            cell.ui, cell.tooltip = line.ui, column.tooltip
            cell:EnableMouse(column.tooltip ~= nil)
            if column.tooltip ~= nil then UI.HookTooltip(cell) end
        end
    end
    for index = #columns + 1, #line.cells do line.cells[index]:Hide() end
    if line.kitPW then lineSized(line, line.kitPW) end
end

-- Rows -------------------------------------------------------------------------------------

-- A row's cells are remade only when the table's columns are not the ones
-- they were made for (a pooled list, another table); text cells are kept.
local function ensureCells(tbl, row)
    local columns = tbl.kitColumns
    if row.kitColumns == columns then return end
    for index, column in ipairs(columns) do
        local cell = row.cells[index] or newCell(row)
        row.cells[index] = cell
        resetCell(cell, column)
        if column.make then
            cell.text:Hide()
            local widget = column.make(tbl.ui, cell)
            -- The table places it, not its own size.
            widget.kitFree = nil
            cell.widget = widget
        else
            cell.text:Show()
        end
    end
    for index = #columns + 1, #row.cells do
        local cell = row.cells[index]
        if cell.widget then
            cell.widget.kitCell = nil
            UI.Release(cell.widget)
            cell.widget = nil
        end
        cell:Hide()
    end
    row.kitColumns = columns
end

local function tableMake(row)
    row.cells = {}
    local group = UI.NewFrame("Frame", nil, row)
    group:SetAllPoints(row)
    group.chevron = L.newChevron(group, 10)
    group.chevron:SetPoint("LEFT", group, "LEFT", PAD_LEFT, 0)
    group.caption = UI.NewText(group)
    group.caption:SetPoint("LEFT", group.chevron, "RIGHT", 6, 0)
    group.count = UI.NewText(group)
    group.count:SetPoint("LEFT", group.caption, "RIGHT", 8, 0)
    row.group = group
end

local function tableDraw(row, entry)
    local tbl = row.kitList.kitTable
    local t = tbl.ui.tokens
    local columns = tbl.kitColumns
    ensureCells(tbl, row)
    row.entry = entry
    local isGroup = entry.isGroup
    row.group:SetShown(isGroup)
    for index, column in ipairs(columns) do
        local cell = row.cells[index]
        cell:SetShown(not isGroup)
        if not isGroup then
            if cell.widget then
                if column.draw then column.draw(cell.widget, entry.item) end
            else
                cell.text:SetText(cellText(column, entry.item))
                local color = column.color and column.color(entry.item)
                UI.ApplyStyle(cell.text, (column.number or column.money) and "number" or "body", t, color)
            end
        end
    end
    if isGroup then
        local group, item = row.group, entry.item
        L.drawChevron(group.chevron, true, item.open ~= false, t)
        group.caption:SetText(item.caption or "")
        group.count:SetText(tostring(entry.count or 0))
        UI.ApplyStyle(group.caption, "body", t, "text")
        UI.ApplyStyle(group.count, "number", t, "muted")
    else
        placeCells(tbl, row, row.cells, entry.inGroup and INDENT or nil, 0, row.kitPW, row.kitPH or 26)
    end
end

-- The table's list hands the player's actions to the table; a group's line
-- is never a pick.
local TABLE_HOOK = {
    pick = function(list, entry)
        if entry.isGroup then return end
        local tbl = list.kitTable
        tbl.kitPicked = entry
        if tbl.kitOnPick then tbl.kitOnPick(entry.item) end
    end,
    activate = function(list, entry)
        local tbl = list.kitTable
        if not entry.isGroup and tbl.kitOnActivate then tbl.kitOnActivate(entry.item) end
    end,
    rightClick = function(list, entry, row)
        local tbl = list.kitTable
        if not entry.isGroup and tbl.kitOnRightClick then tbl.kitOnRightClick(entry.item, row) end
    end,
    -- A row's tooltip is the table's `tooltip(item, row)`; a group's line has none.
    tooltip = function(list, entry, row)
        local tbl = list.kitTable
        if entry.isGroup or not tbl.kitTooltip then return nil end
        return tbl.kitTooltip(entry.item, row)
    end,
    -- A group's line folds it, and leaves the selection where it was.
    rowClick = function(list, _, entry)
        if not entry.isGroup then return end
        local tbl = list.kitTable
        entry.item.open = entry.item.open == false
        list:Select(tbl.kitPicked)
        tbl:Refresh(true)
    end,
    -- A group's line sits on the surface, set apart from its rows.
    paintRow = function(_, row, t)
        if row.entry and row.entry.isGroup and row.item == row.entry then UI.TexColor(row.bg, t.surface) end
    end,
    paint = L.refresh,
}

-- The table's own list: a List type of its own, so its rows (with their
-- cells) pool with other tables' and never meet a plain list's make. Not a
-- widget the addon makes: internal, so it is not given a constructor.
UI.Define("TableList", {
    internal = true, fills = true, focusable = true,
    Build = L.build,
    Init = function(w, spec)
        w.kitTable = spec.kitTable
        L.init(w, spec, TABLE_HOOK)
    end,
    Release = function(w)
        L.release(w)
        w.kitTable = nil
    end,
    methods = L.methods,
})

-- Groups flatten into their line and, while open, their rows.
local function matches(tbl, item, text)
    if tbl.kitFilterFn then return tbl.kitFilterFn(item, text) end
    local first = cellText(tbl.kitColumns[1] or {}, item)
    return string.find(string.lower(first), string.lower(text), 1, true) ~= nil
end

local function entryOf(tbl, item, group)
    local entry = tbl.kitEntries[item] or { item = item }
    tbl.kitEntries[item] = entry
    entry.isGroup, entry.inGroup = group, false
    return entry
end

local function flatten(tbl)
    local out, text = {}, tbl.kitFilter
    for _, item in ipairs(tbl.kitItems) do
        if type(item) == "table" and item.rows then
            local rows = {}
            for _, child in ipairs(item.rows) do
                if text == "" or matches(tbl, child, text) then rows[#rows + 1] = child end
            end
            if text == "" or #rows > 0 then
                local entry = entryOf(tbl, item, true)
                entry.count = #item.rows
                out[#out + 1] = entry
                -- Searching opens every group with a match.
                if item.open ~= false or text ~= "" then
                    for _, child in ipairs(rows) do
                        local childEntry = entryOf(tbl, child, false)
                        childEntry.inGroup = true
                        out[#out + 1] = childEntry
                    end
                end
            end
        elseif text == "" or matches(tbl, item, text) then
            out[#out + 1] = entryOf(tbl, item, false)
        end
    end
    return out
end

local function tableSized(w)
    if w.kitParent == nil and not w.kitPooled then UI.Invalidate(w) end
end

local WEAK = { __mode = "k" }
local TABLE_STACK, PAGER_STACK = { gap = 0 }, { gap = 8 }

UI.Define("Table", {
    stack = true,
    Build = function(w)
        w:SetSize(1, 1)
        w:HookScript("OnSizeChanged", tableSized)
        w.head = newLine(w, HEAD)
        w.foot = newLine(w, HEAD + 2)
    end,
    Init = function(w, spec)
        UI.SetStack(w, "column", TABLE_STACK)
        local columns = spec.columns or {}
        w.kitColumns = columns
        local widgets = false
        for _, column in ipairs(columns) do if column.make then widgets = true end end
        w.kitItems, w.kitFilter, w.kitPicked, w.kitFooter = {}, "", nil, {}
        w.kitEntries = setmetatable({}, WEAK)
        w.kitFilterFn = spec.filter
        w.kitOnPick, w.kitOnActivate, w.kitOnRightClick = spec.onPick, spec.onActivate, spec.onRightClick
        w.kitTooltip = spec.tooltip

        setLineColumns(w.head, columns, true)
        w:Append(w.head)
        w.head:Show()
        w.list = UI.Make(w.ui, "TableList", w, {
            rowHeight = spec.rowHeight or (widgets and 32 or 26), rows = spec.rows, empty = spec.empty,
            grow = spec.grow, make = tableMake, draw = tableDraw, kitTable = w,
        })
        w:Append(w.list)
        w.kitHasFoot = spec.footer and true or false
        if w.kitHasFoot then
            setLineColumns(w.foot, columns, false)
            w:Append(w.foot)
            w.foot:Show()
        else
            w.foot:Hide()
        end
        w.kitSearch = spec.search
        if spec.search then UI.LinkSearch(spec.search, w.list, w) end
    end,
    Release = function(w)
        if w.kitSearch then UI.UnlinkSearch(w.kitSearch, w) end
        w.kitSearch, w.list, w.kitPicked, w.kitTooltip = nil, nil, nil, nil
    end,
    methods = {
        -- `keep` leaves the table scrolled where it was (a fold, new items
        -- of the same table); otherwise it goes back to the top.
        Refresh = function(self, keep) self.list:SetItems(flatten(self), keep) end,
        SetItems = function(self, items, keep)
            self.kitItems = items or {}
            self:Refresh(keep)
        end,
        GetItems = function(self) return self.kitItems end,
        SetFilter = function(self, text)
            self.kitFilter = text or ""
            self:Refresh()
        end,
        GetFilter = function(self) return self.kitFilter end,
        GetSelected = function(self) return self.kitPicked and self.kitPicked.item end,
        -- From code: shown and kept in view; onPick is not called.
        Select = function(self, item)
            local entry = item ~= nil and (self.kitEntries[item] or entryOf(self, item, false)) or nil
            self.kitPicked = entry
            self.list:Select(entry)
            if entry then self.list:ScrollToItem(entry) end
        end,
        -- What the footer says under each column: { [key] = text }; money
        -- columns take copper.
        SetFooter = function(self, values)
            self.kitFooter = values or {}
            if not self.kitHasFoot then return end
            for index, column in ipairs(self.kitColumns) do
                self.foot.cells[index].text:SetText(cellText(column, self.kitFooter))
            end
        end,
        SetState = function(self, kind, text, opts) self.list:SetState(kind, text, opts) end,
        GetState = function(self) return self.list:GetState() end,
        Paint = function(self, t)
            local head, foot = self.head, self.foot
            head.plate:Flat(t.bandBg, t.hairline)
            head.plate.edges.BOTTOM:Hide()
            for index = 1, #self.kitColumns do UI.ApplyStyle(head.cells[index].text, "label", t, "text") end
            if self.kitHasFoot then
                foot.plate:Flat(t.bandBg, t.hairline)
                foot.plate.edges.TOP:Hide()
                for index, column in ipairs(self.kitColumns) do
                    local cell = foot.cells[index]
                    UI.ApplyStyle(cell.text, (column.number or column.money) and "number" or "label", t, "text")
                    cell.text:SetText(cellText(column, self.kitFooter))
                end
            end
        end,
    },
})

-- Pagers ---------------------------------------------------------------------------------

-- "3 of 7" between a back and a next: pages of a long table, or one record
-- of several. Spec: caption ("Page", "Choice"), count, at (from 1),
-- onChange(at, pager), words (Previous and Next buttons rather than
-- arrows), onAdd() and onDelete(at) (Add, and a Delete that asks again).
-- With `total` and `pageSize` the count is the pages, and with `noun` too
-- the pager leads with what the page holds: "Recipes 41 to 60 of 132".
-- SetAt(at) from code does not call onChange; the back and next buttons do.

local function pagerCount(w)
    if w.kitPageSize and w.kitTotal then return math.ceil(w.kitTotal / w.kitPageSize) end
    return w.kitCount or 0
end

local function pagerRange(w)
    if not w.kitPageSize then return w.kitAt, w.kitAt end
    local first = (w.kitAt - 1) * w.kitPageSize + 1
    return first, math.min(w.kitTotal or 0, first + w.kitPageSize - 1)
end

local function pagerShow(w)
    local count = pagerCount(w)
    local at = w.kitAt
    if count == 0 then
        w.label:SetText("None")
    else
        local caption = w.kitCaption
        w.label:SetText(((caption and caption ~= "") and (caption .. " ") or "") .. at .. " of " .. count)
    end
    w.back:SetEnabled(at > 1)
    w.forward:SetEnabled(at < count)
    if w.summary then
        local first, last = pagerRange(w)
        local total = w.kitTotal or 0
        local noun = w.kitNoun
        w.summary:SetText(total == 0 and ("No " .. string.lower(noun)) or (noun .. " " .. first .. " to " .. last .. " of " .. total))
    end
end

-- Answers whether the place moved.
local function pagerSetAt(w, at)
    local count = pagerCount(w)
    at = math.max(1, math.min(math.max(1, count), math.floor(tonumber(at) or 1)))
    local moved = at ~= w.kitAt
    w.kitAt = at
    pagerShow(w)
    return moved
end

local function pagerStep(w, delta)
    if pagerSetAt(w, w.kitAt + delta) then
        if w.kitOnChange then w.kitOnChange(w.kitAt, w) end
    end
end

local function pagerBack(button) pagerStep(button.kitPager, -1) end
local function pagerForward(button) pagerStep(button.kitPager, 1) end
local function pagerAdd(button)
    local w = button.kitPager
    if w.kitOnAdd then w.kitOnAdd() end
end
local function pagerDelete(button)
    local w = button.kitPager
    if w.kitOnDelete and pagerCount(w) > 0 then w.kitOnDelete(w.kitAt) end
end

UI.Define("Pager", {
    stack = true,
    Build = function(w)
        w:SetSize(1, 26)
        w:HookScript("OnSizeChanged", tableSized)
    end,
    Init = function(w, spec)
        UI.SetStack(w, "row", PAGER_STACK)
        w.kitCaption, w.kitNoun, w.kitPageSize = spec.caption, spec.noun, spec.pageSize
        w.kitOnChange, w.kitOnAdd, w.kitOnDelete = spec.onChange, spec.onAdd, spec.onDelete
        w.kitAt = spec.at or 1
        w.kitCount = spec.count or 0
        w.kitTotal = spec.total
        w.summary = nil
        if spec.noun then
            w.summary = w:Text{ "", style = "label" }
            w:Spacer{}
        end
        if spec.words then
            w.back = w:Button{ "Previous", onClick = pagerBack }
            w.label = w:Text{ "" }
            w.forward = w:Button{ "Next", tone = "accent", onClick = pagerForward }
        else
            w.back = w:GlyphButton{ "back", size = 24, boxed = true, bright = true, tooltip = "Back", onClick = pagerBack }
            w.label = w:Text{ "", justify = "CENTER" }
            w.forward = w:GlyphButton{ "next", size = 24, boxed = true, bright = true, tooltip = "Next", onClick = pagerForward }
        end
        w.back.kitPager, w.forward.kitPager = w, w
        w.addButton, w.deleteButton = nil, nil
        if spec.onAdd then
            w:Spacer{ size = 4 }
            w.addButton = w:Button{ "Add", onClick = pagerAdd }
            w.addButton.kitPager = w
        end
        if spec.onDelete then
            w.deleteButton = w:ConfirmButton{ "Delete", tone = "danger", style = "outline", onConfirm = pagerDelete }
            w.deleteButton.kitPager = w
        end
        pagerShow(w)
    end,
    methods = {
        GetCount = function(self) return pagerCount(self) end,
        -- The first and last of `total` on the page shown.
        GetRange = function(self) return pagerRange(self) end,
        SetAt = function(self, at) pagerSetAt(self, at) end,
        GetAt = function(self) return self.kitAt end,
        SetValue = function(self, at) pagerSetAt(self, at) end,
        GetValue = function(self) return self.kitAt end,
        -- How many records there are; the one shown stays where it can.
        SetCount = function(self, count)
            self.kitCount = math.max(0, math.floor(tonumber(count) or 0))
            pagerSetAt(self, self.kitAt)
        end,
        -- How many things the pages hold, with `pageSize`.
        SetTotal = function(self, total)
            self.kitTotal = math.max(0, math.floor(tonumber(total) or 0))
            pagerSetAt(self, self.kitAt)
        end,
    },
})

-- Figures --------------------------------------------------------------------------------

-- A few numbers side by side, each a caption over a large value: a plan's
-- cost, sells, net and crafts. The spec's array part is the figures:
-- { key, caption, money (copper, shown in coins), signed (tone by the sign:
-- gain above nothing, danger below), tone (a tone name), tooltip, value }.
-- Set(key, value, tone) changes one.
local FIGURE_PAD = 12

local function newFigure(w)
    local cell = UI.NewFrame("Frame", nil, w)
    cell.caption = UI.NewText(cell)
    cell.caption:SetPoint("TOPLEFT", cell, "TOPLEFT", FIGURE_PAD, -FIGURE_PAD)
    cell.number = UI.NewText(cell)
    cell.number:SetPoint("TOPLEFT", cell.caption, "BOTTOMLEFT", 0, -4)
    cell.ui = w.ui
    return cell
end

-- Equal shares of the width, split by hairlines, on whole pixels.
local function placeFigures(w)
    local width, count = w:GetWidth() or 0, #w.kitFigures
    if width <= 0 or count == 0 then return end
    for index = 1, count do
        local cell = w.cells[index]
        local left = UI.Snap(w, (index - 1) * width / count)
        local right = UI.Snap(w, index * width / count)
        if cell.kitX ~= left then
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", w, "TOPLEFT", left, 0)
            cell:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", left, 0)
            cell.kitX = left
            local divider = w.dividers[index - 1]
            if divider then
                divider:ClearAllPoints()
                divider:SetPoint("TOPLEFT", w, "TOPLEFT", left, 0)
                divider:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", left, 0)
            end
        end
        local cw = math.max(0.01, right - left)
        if cell.kitW ~= cw then
            cell.kitW = cw
            cell:SetWidth(cw)
        end
    end
end

local function paintFigure(cell, t)
    local figure = cell.figure
    local value = cell.value
    local text = ""
    if value ~= nil then
        text = (figure.money and tonumber(value)) and Kit.FormatMoney(tonumber(value)) or tostring(value)
    end
    local tone = cell.tone or figure.tone
    if figure.signed and tonumber(value) then
        local n = tonumber(value)
        tone = n < 0 and "danger" or (n > 0 and "gain" or nil)
    end
    cell.number:SetText(text)
    UI.ApplyStyle(cell.caption, "label", t)
    UI.ApplyStyle(cell.number, "figure", t, tone and (UI.Tone(t, tone) or UI.Colour(t, tone)) or "text")
end

UI.Define("Figures", {
    Build = function(w)
        w:SetSize(1, 1)
        w.plate = UI.NewPlate(w)
        w.cells, w.dividers, w.kitByKey = {}, {}, {}
        w:HookScript("OnSizeChanged", placeFigures)
    end,
    Init = function(w, spec)
        w.kitFigures = {}
        for key in pairs(w.kitByKey) do w.kitByKey[key] = nil end
        for index, figure in ipairs(spec) do
            w.kitFigures[index] = figure
            local cell = w.cells[index] or newFigure(w)
            w.cells[index] = cell
            cell.figure, cell.value, cell.tone = figure, figure.value, nil
            cell.kitX, cell.kitW = nil, nil
            cell.caption:SetText(figure.caption or "")
            cell.tooltip = figure.tooltip
            cell:EnableMouse(figure.tooltip ~= nil)
            if figure.tooltip ~= nil then UI.HookTooltip(cell) end
            cell:Show()
            if figure.key then w.kitByKey[figure.key] = cell end
            if index > 1 and not w.dividers[index - 1] then
                local divider = w:CreateTexture(nil, "ARTWORK")
                UI.Hairline(divider, "width")
                w.dividers[index - 1] = divider
            end
            if w.dividers[index - 1] then w.dividers[index - 1]:Show() end
        end
        for index = #spec + 1, #w.cells do w.cells[index]:Hide() end
        for index = math.max(1, #spec), #w.dividers do w.dividers[index]:Hide() end
        placeFigures(w)
    end,
    methods = {
        Measure = function(self)
            local scale = self.ui.tokens.textScale or 1
            local caption = math.ceil(UI.textStyles.label.size * scale) + 3
            local value = math.ceil(UI.textStyles.figure.size * scale) + 3
            return 120 * math.max(1, #self.kitFigures), 2 * FIGURE_PAD + caption + 4 + value
        end,
        Sized = function(self) placeFigures(self) end,
        Set = function(self, key, value, tone)
            local cell = self.kitByKey[key]
            if not cell then return end
            cell.value, cell.tone = value, tone
            paintFigure(cell, self.ui.tokens)
        end,
        Get = function(self, key)
            local cell = self.kitByKey[key]
            return cell and cell.value
        end,
        Paint = function(self, t)
            self.plate:Flat(t.surfaceBg, t.hairline)
            for index = 1, #self.kitFigures do
                if self.dividers[index - 1] then UI.TexColor(self.dividers[index - 1], t.hairline) end
                paintFigure(self.cells[index], t)
            end
        end,
    },
})
