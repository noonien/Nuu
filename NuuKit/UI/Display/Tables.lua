local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Tables, pagers and stat figures: the planner's Plan, Recipes and
-- Materials tabs each built these by hand in OpenRoad.

-- Tables ---------------------------------------------------------------------------------

-- A list with column heads, cells in line under them, groups that fold and a
-- footer, on a List (rows made once and reused). `opts`:
--   columns    { key, caption, width | grow, align ("left", "right",
--              "center"), tooltip (on the head), money (copper, shown in
--              coins), number (the number face), color(item) (a token name
--              or colour), text(item) (what the cell says, else item[key]),
--              make(ui, cell) (a widget for the cell instead of text; once
--              per row), draw(widget, item) (each time the row shows an
--              item) }
--   rowHeight  default 26, or 32 when a column makes a widget
--   rows       how many rows tall it wants to be when not growing
--   footer     true for a footer line (see SetFooter)
--   onPick(item), onActivate(item), onRightClick(item, row), search,
--   filter(item, text) (else the first column's text), empty, grow
-- Items are tables; one with `rows` is a group of them: { caption, rows,
-- open }, folded by a click on its line (the kit keeps `open`).
local PAD_LEFT, PAD_RIGHT, GAP, INDENT, HEAD = 10, 8, 12, 18, 28

-- Where each column sits in a line `width` wide: { x, w } per column.
function UI.TableColumns(columns, width)
    local fixed, weights = 0, 0
    for _, column in ipairs(columns) do
        if column.width then fixed = fixed + column.width
        else weights = weights + ((type(column.grow) == "number" and column.grow) or 1) end
    end
    local spare = math.max(0, width - PAD_LEFT - PAD_RIGHT - GAP * math.max(0, #columns - 1) - fixed)
    local spots, x = {}, PAD_LEFT
    for index, column in ipairs(columns) do
        local w = column.width or (weights > 0 and spare * ((type(column.grow) == "number" and column.grow) or 1) / weights or 0)
        spots[index] = { x = x, w = w }
        x = x + w + GAP
    end
    return spots
end

local function cellText(column, item, t)
    local value
    if column.text then value = column.text(item) elseif column.key then value = item[column.key] end
    if value == nil then return "" end
    if column.money and tonumber(value) then return Kit.FormatMoney(tonumber(value)) end
    return tostring(value)
end

UI.Define("Table", function(ui, parent, opts)
    opts = opts or {}
    local columns = opts.columns or {}
    local widgets = false
    for _, column in ipairs(columns) do if column.make then widgets = true end end
    local rowHeight = opts.rowHeight or (widgets and 32 or 26)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeContainer(ui, frame, "column", { gap = 0 })
    frame.kitItems, frame.kitFilter = {}, ""
    frame.kitEntries = setmetatable({}, { __mode = "k" })

    -- Lays a line's cells out under the columns. A row is the list's width
    -- already; the head and footer (`edge`) are the table's, so they take
    -- the list's inset and leave its scroll bar's room, and every column
    -- lines up. `indent` moves the first cell in.
    local function placeCells(line, cells, indent, edge)
        local width, shift = line:GetWidth() or 0, 0
        if edge then width, shift = width - UI.SCROLLBAR - 2, 1 end
        if width <= 0 then return end
        local spots = UI.TableColumns(columns, width)
        for index, cell in ipairs(cells) do
            local spot = spots[index]
            local x, w = shift + spot.x, spot.w
            if index == 1 and indent then x, w = x + indent, math.max(0, w - indent) end
            local left = UI.Snap(line, x)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", line, "TOPLEFT", left, 0)
            cell:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", left, 0)
            cell:SetWidth(math.max(0.01, UI.Snap(line, x + w) - left))
            local widget = cell.widget
            if widget then
                local h = UI.Snap(line, math.min(UI.NaturalHeight(widget, w), (line:GetHeight() or rowHeight)))
                widget:ClearAllPoints()
                widget:SetPoint("LEFT", cell, "LEFT", 0, 0)
                widget:SetSize(widget.kitStretch == false and UI.NaturalWidth(widget) or cell:GetWidth(), h)
                if widget.KitSized then widget:KitSized() end
            end
        end
    end

    -- A line of text cells (the head, the footer), or a row's cells.
    local function textCell(line, column)
        local cell = CreateFrame("Frame", nil, line)
        cell.text = UI.NewText(cell)
        cell.text:SetPoint("LEFT", cell, "LEFT", 0, 0)
        cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
        cell.text:SetJustifyH(column.align == "right" and "RIGHT" or (column.align == "center" and "CENTER" or "LEFT"))
        return cell
    end

    -- The head: a caption over each column, with the column's tooltip.
    local head = CreateFrame("Frame", nil, frame)
    head.plate = UI.NewPlate(head)
    head.cells = {}
    for index, column in ipairs(columns) do
        local cell = textCell(head, column)
        cell.text:SetText(column.caption or "")
        if column.tooltip then
            cell.ui = ui
            cell.tooltip = column.tooltip
            cell:EnableMouse(true)
            UI.HookTooltip(cell)
        end
        head.cells[index] = cell
    end
    head.KitNaturalHeight = function() return HEAD end
    head.KitSized = function(h) placeCells(h, h.cells, nil, true) end
    frame:KitAppend(head)

    -- Groups flatten into their line and, while open, their rows.
    local function matches(item, text)
        if opts.filter then return opts.filter(item, text) end
        local first = cellText(columns[1] or {}, item, ui.tokens)
        return string.find(string.lower(first), string.lower(text), 1, true) ~= nil
    end
    local function entryOf(item, group)
        local entry = frame.kitEntries[item] or { item = item }
        frame.kitEntries[item] = entry
        entry.isGroup, entry.inGroup = group, false
        return entry
    end
    local function flatten()
        local out, text = {}, frame.kitFilter
        for _, item in ipairs(frame.kitItems) do
            if type(item) == "table" and item.rows then
                local rows = {}
                for _, child in ipairs(item.rows) do
                    if text == "" or matches(child, text) then rows[#rows + 1] = child end
                end
                if text == "" or #rows > 0 then
                    local entry = entryOf(item, true)
                    entry.count = #item.rows
                    out[#out + 1] = entry
                    if item.open ~= false or text ~= "" then
                        for _, child in ipairs(rows) do
                            local childEntry = entryOf(child, false)
                            childEntry.inGroup = true
                            out[#out + 1] = childEntry
                        end
                    end
                end
            elseif text == "" or matches(item, text) then
                out[#out + 1] = entryOf(item, false)
            end
        end
        return out
    end

    local picked
    local list
    list = UI.Proto.List(ui, frame, {
        rowHeight = rowHeight, rows = opts.rows, empty = opts.empty, grow = opts.grow,
        make = function(row)
            row.cells = {}
            for index, column in ipairs(columns) do
                local cell
                if column.make then
                    cell = CreateFrame("Frame", nil, row)
                    cell.widget = column.make(ui, cell)
                else
                    cell = textCell(row, column)
                end
                row.cells[index] = cell
            end
            row.group = CreateFrame("Frame", nil, row)
            row.group:SetAllPoints(row)
            row.group.chevron = CreateFrame("Frame", nil, row.group)
            row.group.chevron:SetSize(10, 10)
            row.group.chevron:SetPoint("LEFT", row.group, "LEFT", PAD_LEFT, 0)
            row.group.open = UI.NewGlyph(row.group.chevron, "down", 8, 1.5)
            row.group.shut = UI.NewGlyph(row.group.chevron, "next", 8, 1.5)
            row.group.caption = UI.NewText(row.group)
            row.group.caption:SetPoint("LEFT", row.group.chevron, "RIGHT", 6, 0)
            row.group.count = UI.NewText(row.group)
            row.group.count:SetPoint("LEFT", row.group.caption, "RIGHT", 8, 0)
            row:HookScript("OnSizeChanged", function(r)
                placeCells(r, r.cells, r.entry and r.entry.inGroup and INDENT or nil)
            end)
        end,
        draw = function(row, entry)
            local t = ui.tokens
            row.entry = entry
            row.group:SetShown(entry.isGroup)
            for index, cell in ipairs(row.cells) do
                cell:SetShown(not entry.isGroup)
                local column = columns[index]
                if not entry.isGroup then
                    if cell.widget then
                        if column.draw then column.draw(cell.widget, entry.item) end
                    else
                        cell.text:SetText(cellText(column, entry.item, t))
                        local color = column.color and column.color(entry.item)
                        UI.ApplyStyle(cell.text, (column.number or column.money) and "number" or "body", t, color)
                    end
                end
            end
            if entry.isGroup then
                local group = row.group
                local open = entry.item.open ~= false
                group.open:SetShown(open)
                group.shut:SetShown(not open)
                group.caption:SetText(entry.item.caption or "")
                group.count:SetText(tostring(entry.count or 0))
                UI.ApplyStyle(group.caption, "body", t, "text")
                UI.ApplyStyle(group.count, "number", t, "muted")
                group.open:SetColor(t.muted)
                group.shut:SetColor(t.muted)
            else
                placeCells(row, row.cells, entry.inGroup and INDENT or nil)
            end
        end,
        onPick = function(entry)
            if entry.isGroup then return end
            picked = entry
            if opts.onPick then opts.onPick(entry.item) end
        end,
        onActivate = function(entry)
            if not entry.isGroup and opts.onActivate then opts.onActivate(entry.item) end
        end,
        onRightClick = function(entry, row)
            if not entry.isGroup and opts.onRightClick then opts.onRightClick(entry.item, row) end
        end,
        -- A group's line folds it, and leaves the selection where it was.
        kitRowClick = function(_, entry)
            if not entry.isGroup then return end
            entry.item.open = entry.item.open == false
            list:Select(picked, true)
            frame:Refresh()
        end,
    })
    frame.list = list
    -- A group's line sits on the surface, set apart from its rows.
    local paintRow = list.PaintRow
    function list:PaintRow(row)
        paintRow(self, row)
        if row.entry and row.entry.isGroup and row.item == row.entry then UI.TexColor(row.bg, ui.tokens.surface) end
    end
    frame:KitAppend(list)

    -- The footer: text under the columns, set with SetFooter.
    local foot
    if opts.footer then
        foot = CreateFrame("Frame", nil, frame)
        foot.plate = UI.NewPlate(foot)
        foot.cells = {}
        for index, column in ipairs(columns) do foot.cells[index] = textCell(foot, column) end
        foot.KitNaturalHeight = function() return HEAD + 2 end
        foot.KitSized = function(f) placeCells(f, f.cells, nil, true) end
        frame:KitAppend(foot)
    end
    frame.kitFooter = {}

    function frame:Refresh()
        list:SetItems(flatten())
    end
    function frame:SetItems(items)
        self.kitItems = items or {}
        self:Refresh()
    end
    function frame:GetItems() return self.kitItems end
    function frame:SetFilter(text)
        self.kitFilter = text or ""
        self:Refresh()
    end
    function frame:GetSelected() return picked and picked.item end
    function frame:Select(item, silent)
        picked = item and entryOf(item, false) or nil
        list:Select(picked, silent)
        if picked then list:ScrollToItem(picked) end
    end
    -- What the footer says under each column: { [key] = text }; money
    -- columns take copper.
    function frame:SetFooter(values)
        self.kitFooter = values or {}
        if not foot then return end
        local t = ui.tokens
        for index, column in ipairs(columns) do
            foot.cells[index].text:SetText(cellText(column, self.kitFooter, t))
        end
        self:Repaint()
    end
    function frame:SetState(kind, text, stateOpts) list:SetState(kind, text, stateOpts) end

    if opts.search then
        local search = opts.search
        search.kitList = list
        local typed = search.kitOnType
        search.kitOnType = function(text, field)
            if typed then typed(text, field) end
            frame:SetFilter(text)
        end
    end

    return ui:Finish(frame, opts, function(f, t)
        head.plate:Flat(t.bandBg, t.hairline)
        head.plate.edges.BOTTOM:Hide()
        for _, cell in ipairs(head.cells) do UI.ApplyStyle(cell.text, "label", t, "text") end
        if foot then
            foot.plate:Flat(t.bandBg, t.hairline)
            foot.plate.edges.TOP:Hide()
            for index, cell in ipairs(foot.cells) do
                local column = columns[index]
                UI.ApplyStyle(cell.text, (column.number or column.money) and "number" or "label", t, "text")
                cell.text:SetText(cellText(column, f.kitFooter, t))
            end
        end
    end)
end, true)

-- Pagers ---------------------------------------------------------------------------------

-- "3 of 7" between a back and a next: pages of a long table, or one record
-- of several. `opts`: caption ("Page", "Choice"), count, at (from 1),
-- onChange(at), words (Previous and Next buttons rather than arrows),
-- onAdd() and onDelete(at) (Add, and a Delete that asks again). With
-- `total` and `pageSize` the count is the pages, and with `noun` too the
-- pager leads with what the page holds: "Recipes 41 to 60 of 132".
UI.Define("Pager", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 26)
    UI.MakeContainer(ui, frame, "row", { gap = 8 })
    frame.kitAt = opts.at or 1

    local summary
    if opts.noun then
        summary = frame:Text("", "label")
        frame:Spacer()
    end
    local back, label, forward
    local function step(delta) frame:SetAt(frame.kitAt + delta) end
    if opts.words then
        back = frame:Button("Previous", { onClick = function() step(-1) end })
        label = frame:Text("", "body")
        forward = frame:Button("Next", { tone = "accent", onClick = function() step(1) end })
    else
        back = frame:GlyphButton("back", { size = 24, boxed = true, bright = true, tooltip = "Back", onClick = function() step(-1) end })
        label = frame:Text("", "body", { justify = "CENTER" })
        forward = frame:GlyphButton("next", { size = 24, boxed = true, bright = true, tooltip = "Next", onClick = function() step(1) end })
    end
    if opts.onAdd then
        frame:Spacer({ size = 4 })
        frame:Button("Add", { onClick = function() opts.onAdd() end })
    end
    if opts.onDelete then
        frame:ConfirmButton("Delete", { tone = "danger", style = "outline",
            onConfirm = function() if frame:GetCount() > 0 then opts.onDelete(frame.kitAt) end end })
    end

    function frame:GetCount()
        if opts.pageSize and self.kitTotal then return math.ceil(self.kitTotal / opts.pageSize) end
        return self.kitCount or 0
    end
    -- The first and last of `total` on the page shown.
    function frame:GetRange()
        if not opts.pageSize then return self.kitAt, self.kitAt end
        local first = (self.kitAt - 1) * opts.pageSize + 1
        return first, math.min(self.kitTotal or 0, first + opts.pageSize - 1)
    end
    local function show()
        local count = frame:GetCount()
        local at = frame.kitAt
        if count == 0 then
            label:SetText("None")
        else
            label:SetText(((opts.caption and opts.caption ~= "") and (opts.caption .. " ") or "") .. at .. " of " .. count)
        end
        back:SetEnabled(at > 1)
        forward:SetEnabled(at < count)
        if summary then
            local first, last = frame:GetRange()
            local total = frame.kitTotal or 0
            summary:SetText(total == 0 and ("No " .. string.lower(opts.noun)) or (opts.noun .. " " .. first .. " to " .. last .. " of " .. total))
        end
    end
    function frame:SetAt(at, silent)
        local count = self:GetCount()
        at = math.max(1, math.min(math.max(1, count), math.floor(tonumber(at) or 1)))
        local moved = at ~= self.kitAt
        self.kitAt = at
        show()
        if moved and not silent and opts.onChange then opts.onChange(at) end
    end
    function frame:GetAt() return self.kitAt end
    -- How many records there are; the one shown stays where it can.
    function frame:SetCount(count)
        self.kitCount = math.max(0, math.floor(tonumber(count) or 0))
        self:SetAt(self.kitAt, true)
    end
    -- How many things the pages hold, with `pageSize`.
    function frame:SetTotal(total)
        self.kitTotal = math.max(0, math.floor(tonumber(total) or 0))
        self:SetAt(self.kitAt, true)
    end
    frame.kitCount = opts.count or 0
    frame.kitTotal = opts.total
    show()
    return ui:Finish(frame, opts)
end)

-- Figures --------------------------------------------------------------------------------

-- A few numbers side by side, each a caption over a large value: a plan's
-- cost, sells, net and crafts. `figures` is a list of { key, caption,
-- money (copper, shown in coins), signed (tone by the sign: gain above
-- nothing, danger below), tone (a tone name), tooltip, value }. Set(key,
-- value, tone) changes one.
local FIGURE_PAD = 12

UI.Define("Figures", function(ui, parent, figures, opts)
    opts = opts or {}
    figures = figures or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame.plate = UI.NewPlate(frame)
    frame.cells, frame.dividers, frame.kitByKey = {}, {}, {}
    for index, figure in ipairs(figures) do
        local cell = CreateFrame("Frame", nil, frame)
        cell.figure = figure
        cell.value = figure.value
        cell.caption = UI.NewText(cell)
        cell.caption:SetPoint("TOPLEFT", cell, "TOPLEFT", FIGURE_PAD, -FIGURE_PAD)
        cell.caption:SetText(figure.caption or "")
        cell.number = UI.NewText(cell)
        cell.number:SetPoint("TOPLEFT", cell.caption, "BOTTOMLEFT", 0, -4)
        if figure.tooltip then
            cell.ui, cell.tooltip = ui, figure.tooltip
            cell:EnableMouse(true)
            UI.HookTooltip(cell)
        end
        frame.cells[index] = cell
        if figure.key then frame.kitByKey[figure.key] = cell end
        if index > 1 then
            local divider = frame:CreateTexture(nil, "ARTWORK")
            UI.Hairline(divider, "width")
            frame.dividers[index - 1] = divider
        end
    end
    local function captionHeight() return math.ceil(UI.textStyles.label.size * (ui.tokens.textScale or 1)) + 3 end
    local function valueHeight() return math.ceil(UI.textStyles.figure.size * (ui.tokens.textScale or 1)) + 3 end
    frame.KitNaturalWidth = function() return 120 * math.max(1, #figures) end
    frame.KitNaturalHeight = function()
        return 2 * FIGURE_PAD + captionHeight() + 4 + valueHeight()
    end
    -- Equal shares of the width, split by hairlines, on whole pixels.
    local function place(f)
        local width, count = f:GetWidth() or 0, #f.cells
        if width <= 0 or count == 0 then return end
        for index, cell in ipairs(f.cells) do
            local left = UI.Snap(f, (index - 1) * width / count)
            local right = UI.Snap(f, index * width / count)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", f, "TOPLEFT", left, 0)
            cell:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, 0)
            cell:SetWidth(math.max(0.01, right - left))
            local divider = f.dividers[index - 1]
            if divider then
                divider:ClearAllPoints()
                divider:SetPoint("TOPLEFT", f, "TOPLEFT", left, 0)
                divider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, 0)
            end
        end
    end
    frame.KitSized = place
    frame:HookScript("OnSizeChanged", place)

    local function paintCell(cell, t)
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
        UI.ApplyStyle(cell.number, "figure", t, tone and (UI.ToneColor(t, tone) or tone) or "text")
    end
    function frame:Set(key, value, tone)
        local cell = self.kitByKey[key]
        if not cell then return end
        cell.value, cell.tone = value, tone
        paintCell(cell, ui.tokens)
    end
    function frame:Get(key)
        local cell = self.kitByKey[key]
        return cell and cell.value
    end
    return ui:Finish(frame, opts, function(f, t)
        f.plate:Flat(t.surfaceBg, t.hairline)
        for _, divider in ipairs(f.dividers) do UI.TexColor(divider, t.hairline) end
        for _, cell in ipairs(f.cells) do paintCell(cell, t) end
    end)
end)
