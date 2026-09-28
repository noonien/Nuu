local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Container = UI.Container

-- Scroll areas, lists, trees and split panes.

-- Scroll areas -------------------------------------------------------------------------

-- A scrolling area with a slim bar inside its own right edge, ported from
-- OpenRoad's Theme:ScrollFrame: the bar hides when the content fits. Callers
-- keep UI.SCROLLBAR clear at the right of the content.
UI.SCROLLBAR = 10
local SCROLL_STEP, THUMB_MIN = 40, 20

-- A slim bar for anything that scrolls: `range()` how far, `current()` where,
-- `scrollTo(value)`, `view()` how much shows. Returns the bar with Sync.
local function slimBar(ui, parent, range, current, scrollTo, view, step)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(UI.SCROLLBAR)
    bar:SetFrameLevel(parent:GetFrameLevel() + 10)
    bar:EnableMouse(true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    UI.Stroke(track, "width", 4)
    local thumb = CreateFrame("Frame", nil, bar)
    bar.thumb = thumb
    thumb:SetWidth(UI.Snap(bar, 6))
    thumb:SetHeight(THUMB_MIN)
    thumb:EnableMouse(true)
    local fill = thumb:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    ui:Paint(bar, function(t)
        UI.TexColor(track, t.border, 0.6)
        UI.TexColor(fill, t.accent, (thumb.hover or thumb.drag) and 1 or 0.65)
    end)
    local function paint() bar.ui = ui; ui.painters[bar](ui.tokens) end

    function bar.Sync()
        local maxScroll = range()
        local at = current()
        if at > maxScroll then
            at = maxScroll
            scrollTo(at)
        end
        if maxScroll < (step and 1 or 1) then bar:Hide(); return end
        bar:Show()
        local length = bar:GetHeight() or 0
        local shown = view()
        local size = math.max(THUMB_MIN, length * shown / (shown + maxScroll))
        if size > length then size = length end
        thumb:SetHeight(UI.Snap(bar, size))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -UI.Snap(bar, (length - size) * at / maxScroll))
    end

    local function cursorY()
        local _, y = GetCursorPosition()
        return y / (bar:GetEffectiveScale() or 1)
    end
    local function stopDrag()
        thumb.drag = nil
        thumb:SetScript("OnUpdate", nil)
        paint()
    end
    thumb:SetScript("OnEnter", function() thumb.hover = true; paint() end)
    thumb:SetScript("OnLeave", function() thumb.hover = false; paint() end)
    thumb:SetScript("OnMouseDown", function(_, mouse)
        if mouse ~= "LeftButton" then return end
        thumb.drag = { y = cursorY(), from = current() }
        paint()
        thumb:SetScript("OnUpdate", function()
            local drag = thumb.drag
            if not drag then return end
            local travel = (bar:GetHeight() or 0) - (thumb:GetHeight() or 0)
            if travel <= 0 then return end
            scrollTo(drag.from + (drag.y - cursorY()) * range() / travel)
            bar.Sync()
        end)
    end)
    thumb:SetScript("OnMouseUp", stopDrag)
    bar:SetScript("OnHide", stopDrag)
    -- A click on the track above or below the thumb turns a page.
    bar:SetScript("OnMouseDown", function(_, mouse)
        if mouse ~= "LeftButton" then return end
        local y, top, bottom = cursorY(), thumb:GetTop(), thumb:GetBottom()
        if not top or not bottom then return end
        local page = math.max(step or SCROLL_STEP, view() - (step or SCROLL_STEP))
        if y > top then scrollTo(current() - page) elseif y < bottom then scrollTo(current() + page) end
        bar.Sync()
    end)
    bar:Hide()
    return bar
end

-- A ScrollFrame and its content frame with the slim bar. Returns scroll,
-- content; `scroll:ScrollTo(y)`, `scroll:ScrollToTop()`, `scroll.Sync()`.
function UI.NewScroll(ui, parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local function range() return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0)) end
    local function current() return scroll:GetVerticalScroll() or 0 end
    -- On whole screen pixels, so what scrolls keeps the layout's pixel grid.
    local function scrollTo(value)
        local maxScroll = range()
        if value > maxScroll then value = maxScroll end
        if value < 0 then value = 0 end
        scroll:SetVerticalScroll(UI.Snap(scroll, value))
    end
    local bar = slimBar(ui, scroll, range, current, scrollTo, function() return scroll:GetHeight() or 0 end)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 2)
    scroll.Sync = bar.Sync
    scroll.ScrollTo = function(_, value) scrollTo(value or 0); bar.Sync() end
    scroll.ScrollToTop = function() scrollTo(0); bar.Sync() end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(current() - delta * SCROLL_STEP); bar.Sync() end)
    scroll:SetScript("OnScrollRangeChanged", bar.Sync)
    scroll:SetScript("OnVerticalScroll", bar.Sync)
    scroll:HookScript("OnSizeChanged", bar.Sync)
    content:SetScript("OnSizeChanged", bar.Sync)
    return scroll, content
end

-- Free-form content that scrolls. What is made in it stacks in a column as
-- tall as its content; `area:ScrollToTop()`.
UI.Define("ScrollArea", function(ui, parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, opts.height or 100)
    for method, fn in pairs(Container) do frame[method] = fn end
    frame.ui = ui
    local scroll, content = UI.NewScroll(ui, frame)
    scroll:SetAllPoints(frame)
    UI.MakeContainer(ui, content, "column", { gap = opts.gap or 8, padding = opts.padding or 0 })
    content.kitAutoHeight = true
    frame.kitInner = content
    frame.KitNaturalHeight = function() return opts.minHeight or opts.height or 100 end
    scroll:HookScript("OnSizeChanged", function(s)
        content:SetWidth(math.max(1, (s:GetWidth() or 0) - UI.SCROLLBAR))
        UI.Invalidate(content)
    end)
    frame.ScrollTo = function(_, y) scroll:ScrollTo(y) end
    frame.ScrollToTop = function() scroll:ScrollToTop() end
    frame.scroll = scroll
    return ui:Finish(frame, opts)
end, true)

-- Lists ----------------------------------------------------------------------------------

-- A list of items drawn into rows made once and reused, so a thousand items
-- cost a screenful of frames. `opts`:
--   rowHeight          default 26
--   make(row)          once per row: what it holds (a row is a Row container)
--   draw(row, item, i) each time a row shows an item
--   onPick(item, row)  a click (not on a disabled row)
--   onActivate(item)   a double click, or Enter from the search field
--   onRightClick(item, row)
--   search             a Search field that filters the list as it is typed
--   filter(item, text) whether an item matches, else its `name` or caption
--   empty              what an empty list says
--   rows               how many rows tall it wants to be when not growing
--   numbers            a gutter of numbers at the left: true for the place
--                      in the list, or fn(item, i) for the text
--   value(item)        a muted figure at the right of each row (a distance)
-- In draw, `row:SetDisabled(on, reason)` dims a row and refuses the pick.
local ROW_HEIGHT = 26

local function defaultFilter(item, text)
    local name = type(item) == "table" and (item.name or item.caption) or tostring(item)
    return string.find(string.lower(tostring(name or "")), string.lower(text), 1, true) ~= nil
end

UI.Define("List", function(ui, parent, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or ROW_HEIGHT
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, (opts.rows or 6) * rowHeight)
    UI.MakeContainer(ui, frame, "column", {})
    frame.KitNaturalHeight = function() return (opts.rows or 6) * rowHeight + 2 end
    frame.plate = UI.NewPlate(frame)
    frame.items, frame.view, frame.rows, frame.offset = {}, {}, {}, 0
    frame.filterText = ""
    frame:EnableMouse(true)

    local function visibleCount()
        return math.max(1, math.floor(((frame:GetHeight() or 0) - 2) / rowHeight))
    end
    local function maxOffset()
        return math.max(0, #frame.view - visibleCount())
    end
    local bar = slimBar(ui, frame, maxOffset, function() return frame.offset end, function(value)
        frame.offset = math.max(0, math.min(maxOffset(), math.floor(value + 0.5)))
        frame:Refresh()
    end, visibleCount, 1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -3)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 3)

    -- The wheel is the list's only once the player has taken hold of it (a
    -- click on a row, the list or its bar), only while it has more than it
    -- shows, and until the pointer leaves it: the page scrolling past a list
    -- must not stop at it. Held, its edge lights, as a field's does.
    local function holdWheel(held)
        frame.kitHeld = held and true or false
        frame:EnableMouseWheel(frame.kitHeld and maxOffset() > 0)
        if frame.Repaint then frame:Repaint() end
    end
    local function take() if not frame.kitHeld then holdWheel(true) end end
    -- Leaving the list for one of its own rows is not leaving it.
    local function leave() if frame.kitHeld and not frame:IsMouseOver() then holdWheel(false) end end
    frame:EnableMouseWheel(false)
    frame:HookScript("OnMouseDown", take)
    frame:HookScript("OnLeave", leave)
    frame:HookScript("OnHide", function() if frame.kitHeld then holdWheel(false) end end)
    for _, part in ipairs({ bar, bar.thumb }) do
        part:HookScript("OnMouseDown", take)
        part:HookScript("OnLeave", leave)
    end

    local function makeRow(index)
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        UI.MakeContainer(ui, row, "row", { gap = opts.gap or 10, padding = 0, padLeft = 10, padRight = 8 })
        row.kitIndex = index
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        UI.Stroke(row.bar, "width", 3)
        row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
        UI.Hairline(row.line, "height")
        row.SetDisabled = function(r, disabled, reason)
            r.kitDisabled = disabled and true or false
            r.kitReason = disabled and reason or nil
            r:SetAlpha(r.kitDisabled and 0.5 or 1)
        end
        row:SetScript("OnEnter", function(r)
            r.hover = true
            frame:PaintRow(r)
            if r.kitReason then ui:Tooltip(r, nil, { reason = r.kitReason, anchor = "ANCHOR_RIGHT" }) end
        end)
        row:SetScript("OnLeave", function(r) r.hover = false; frame:PaintRow(r); ui:HideTooltip(); leave() end)
        row:HookScript("OnMouseDown", take)
        row:SetScript("OnClick", function(r, mouse)
            UI.ClearTypingFocus(nil)
            if not r.item then return end
            if mouse == "RightButton" then
                if opts.onRightClick then opts.onRightClick(r.item, r) end
                return
            end
            if r.kitDisabled then return end
            frame:Select(r.item)
            if frame.kitRowClick then frame.kitRowClick(r, r.item) end
        end)
        row:SetScript("OnDoubleClick", function(r)
            if r.item and not r.kitDisabled and opts.onActivate then opts.onActivate(r.item) end
            if r.item and frame.kitRowDouble then frame.kitRowDouble(r, r.item) end
        end)
        if opts.numbers then
            row.number = row:Text("", "number", { width = opts.numberWidth or 24, justify = "RIGHT", color = "muted" })
        end
        if opts.make then opts.make(row) end
        if opts.value then
            row:Spacer()
            row.valueText = row:Text("", "number", { color = "muted" })
        end
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(1 + (index - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(UI.SCROLLBAR + 1), -(1 + (index - 1) * rowHeight))
        return row
    end

    function frame:PaintRow(row)
        local t = ui.tokens
        local selected = row.item ~= nil and row.item == self.selected
        UI.TexColor(row.bg, selected and t.accentWash or (row.hover and not row.kitDisabled and UI.Alpha(t.text, 0.06) or nil))
        UI.TexColor(row.bar, selected and t.accent or nil)
        UI.TexColor(row.line, t.hairline)
    end

    function frame:Refresh()
        local count = visibleCount()
        self.offset = math.max(0, math.min(self.offset, maxOffset()))
        for index = 1, math.max(count, #self.rows) do
            local row = self.rows[index]
            if index <= count and not self.kitState then
                row = row or makeRow(index)
                self.rows[index] = row
                local item = self.view[self.offset + index]
                row.item = item
                if item ~= nil then
                    row:SetDisabled(false)
                    row:Show()
                    if opts.draw then opts.draw(row, item, self.offset + index) end
                    if row.number then
                        local at = self.offset + index
                        row.number:SetText(type(opts.numbers) == "function" and opts.numbers(item, at) or at)
                    end
                    if row.valueText then row.valueText:SetText(opts.value(item) or "") end
                    UI.Invalidate(row)
                    self:PaintRow(row)
                else
                    row:Hide()
                end
            elseif row then
                row:Hide()
            end
        end
        if #self.view == 0 and not self.kitState and opts.empty then
            self.emptyText = self.emptyText or UI.NewText(self)
            self.emptyText:ClearAllPoints()
            self.emptyText:SetPoint("CENTER", self, "CENTER", 0, 0)
            self.emptyText:SetText(opts.empty)
            UI.ApplyStyle(self.emptyText, "body", ui.tokens, "muted")
            self.emptyText:Show()
        elseif self.emptyText then
            self.emptyText:Hide()
        end
        -- More or fewer items: held, it takes the wheel only if it scrolls.
        self:EnableMouseWheel(self.kitHeld and maxOffset() > 0)
        bar.Sync()
    end

    local function applyFilter()
        local text = frame.filterText
        if text == "" then
            frame.view = frame.items
        else
            local match = opts.filter or defaultFilter
            local view = {}
            for _, item in ipairs(frame.items) do
                if match(item, text) then view[#view + 1] = item end
            end
            frame.view = view
        end
        frame.offset = 0
        frame:Refresh()
    end

    function frame:SetItems(items)
        self.items = items or {}
        applyFilter()
    end
    function frame:GetItems() return self.items end
    function frame:GetView() return self.view end
    function frame:SetFilter(text)
        self.filterText = text or ""
        applyFilter()
    end
    function frame:GetSelected() return self.selected end
    function frame:Select(item, silent)
        self.selected = item
        for _, row in ipairs(self.rows) do if row:IsShown() then self:PaintRow(row) end end
        if not silent and item ~= nil and opts.onPick then opts.onPick(item) end
    end
    -- Keeps `item` in view.
    function frame:ScrollToItem(item)
        for index, value in ipairs(self.view) do
            if value == item then
                local count = visibleCount()
                if index <= self.offset then
                    self.offset = index - 1
                elseif index > self.offset + count then
                    self.offset = index - count
                end
                self:Refresh()
                return
            end
        end
    end
    function frame:MoveSelection(step)
        if #self.view == 0 then return end
        local at = 0
        for index, value in ipairs(self.view) do if value == self.selected then at = index end end
        local target = at + step
        if at == 0 then target = step > 0 and 1 or #self.view end
        target = math.max(1, math.min(#self.view, target))
        self:Select(self.view[target])
        self:ScrollToItem(self.view[target])
    end
    function frame:Activate()
        local item = self.selected or self.view[1]
        if item ~= nil and opts.onActivate then opts.onActivate(item) end
    end
    frame.kitKeyArrow = function(f, key)
        if key == "UP" then f:MoveSelection(-1) elseif key == "DOWN" then f:MoveSelection(1) end
    end
    frame.kitKeyPress = function(f) f:Activate() end
    UI.RegisterFocusable(ui, frame, false)

    -- A state (loading, empty, error) puts the rows aside too.
    local setState = frame.SetState
    function frame:SetState(kind, text, stateOpts)
        setState(self, kind, text, stateOpts)
        self:Refresh()
    end

    frame:SetScript("OnMouseWheel", function(f, delta)
        f.offset = math.max(0, math.min(maxOffset(), f.offset - delta * (opts.wheelRows or 3)))
        f:Refresh()
    end)
    frame:HookScript("OnSizeChanged", function(f) f:Refresh() end)

    if opts.search then
        local search = opts.search
        search.kitList = frame
        local typed = search.kitOnType
        search.kitOnType = function(text, field)
            if typed then typed(text, field) end
            frame:SetFilter(text)
        end
    end
    frame.kitRowClick = opts.kitRowClick
    frame:Refresh()
    return ui:Finish(frame, opts, function(f, t)
        f.plate:Flat(t.art and { 0, 0, 0, 0.28 } or t.surfaceBg, f.kitHeld and t.accent65 or t.hairline)
        for _, row in ipairs(f.rows) do if row:IsShown() then f:PaintRow(row) end end
    end)
end, true)

-- Trees ------------------------------------------------------------------------------------

-- Folders any depth deep, on a List. Nodes are { caption, count, children,
-- open, value }; a node with children is a folder. A click picks
-- (`onPick(node)`), a click on the chevron or a double click opens or closes
-- (`onToggle(node, open)`; the kit keeps `node.open`).
local INDENT = 14

UI.Define("Tree", function(ui, parent, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or 24
    local frame
    local function flatten()
        local out = {}
        -- One entry per node for good, so the selection survives folding.
        frame.kitEntries = frame.kitEntries or setmetatable({}, { __mode = "k" })
        local function walk(nodes, depth)
            for _, node in ipairs(nodes or {}) do
                local entry = frame.kitEntries[node] or { node = node }
                frame.kitEntries[node] = entry
                entry.depth = depth
                out[#out + 1] = entry
                if node.children and node.open then walk(node.children, depth + 1) end
            end
        end
        walk(frame.kitNodes, 0)
        return out
    end
    local function toggle(entry)
        local node = entry.node
        if not node.children then return end
        node.open = not node.open
        frame:SetItems(flatten())
        if opts.onToggle then opts.onToggle(node, node.open) end
    end
    frame = UI.Proto.List(ui, parent, {
        rowHeight = rowHeight, rows = opts.rows, grow = opts.grow, empty = opts.empty,
        make = function(row)
            row.guides = {}
            row.chevronFrame = CreateFrame("Frame", nil, row)
            row.chevronFrame:SetSize(12, 12)
            row.open = UI.NewGlyph(row.chevronFrame, "down", 8, 1.5)
            row.shut = UI.NewGlyph(row.chevronFrame, "next", 8, 1.5)
            row.caption = UI.NewText(row)
            row.count = UI.NewText(row)
            row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.count:SetJustifyH("RIGHT")
            row.caption:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        end,
        draw = function(row, entry)
            local t = ui.tokens
            local node, depth = entry.node, entry.depth
            local left = 8 + depth * INDENT
            for index = 1, math.max(depth, #row.guides) do
                local guide = row.guides[index]
                if index <= depth then
                    guide = guide or row:CreateTexture(nil, "ARTWORK")
                    row.guides[index] = guide
                    guide:ClearAllPoints()
                    local x = UI.Snap(row, 8 + (index - 1) * INDENT + 5)
                    guide:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
                    guide:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
                    UI.Hairline(guide, "width")
                    UI.TexColor(guide, t.hairline)
                    guide:Show()
                elseif guide then
                    guide:Hide()
                end
            end
            row.chevronFrame:ClearAllPoints()
            row.chevronFrame:SetPoint("LEFT", row, "LEFT", left, 0)
            local folder = node.children ~= nil
            row.open:SetShown(folder and node.open and true or false)
            row.shut:SetShown(folder and not node.open)
            row.open:SetColor(t.muted)
            row.shut:SetColor(t.muted)
            row.caption:ClearAllPoints()
            row.caption:SetPoint("LEFT", row, "LEFT", left + 16, 0)
            row.caption:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
            row.caption:SetText(node.caption or tostring(node.value or ""))
            row.count:SetText(node.count ~= nil and tostring(node.count) or "")
            UI.ApplyStyle(row.caption, "body", t, entry == frame.selected and "accent" or "text")
            UI.ApplyStyle(row.count, "number", t, "muted")
            row.kitChevronRight = left + 14
        end,
        onPick = function(entry) if opts.onPick then opts.onPick(entry.node) end end,
        onActivate = function(entry) toggle(entry) end,
    })
    frame.kitRowClick = function(row, entry)
        if type(GetCursorPosition) ~= "function" then return end
        local x = GetCursorPosition() / (row:GetEffectiveScale() or 1)
        local left = row:GetLeft() or 0
        if x - left <= (row.kitChevronRight or 0) then toggle(entry) end
        frame:Refresh()
    end
    frame.kitNodes = opts.nodes or {}
    function frame:SetNodes(nodes)
        self.kitNodes = nodes or {}
        self:SetItems(flatten())
    end
    function frame:GetSelectedNode() return self.selected and self.selected.node end
    frame:SetItems(flatten())
    return frame
end, true)

-- Split panes -----------------------------------------------------------------------------

-- Panes side by side with bars to drag between them. `specs` are
-- { key, width, min, grow }; a pane is a column, reached as `panes[key]`.
-- With `opts.place` and `opts.key` the widths are kept in place[key].
local BAR = 9

UI.Define("SplitPanes", function(ui, parent, specs, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame.KitNaturalHeight = function() return opts.minHeight or 200 end
    frame.panes, frame.bars, frame.specs = {}, {}, specs or {}
    local saved = opts.place and opts.key and opts.place[opts.key] or {}
    local widths = {}
    for index, spec in ipairs(frame.specs) do
        widths[index] = (not spec.grow) and (saved[spec.key] or spec.width or 200) or nil
        local pane = CreateFrame("Frame", nil, frame)
        UI.MakeContainer(ui, pane, "column", { gap = spec.gap or 8, padding = spec.padding or 10 })
        pane.kitFillChildren = true
        pane.kitParentContainer = nil
        ui:Finish(pane, {})
        frame.panes[spec.key] = pane
        frame[spec.key] = frame[spec.key] or pane
        frame.panes[index] = pane
    end

    local function arrange()
        local total = frame:GetWidth() or 0
        if total <= 0 then return end
        local items = {}
        for index, spec in ipairs(frame.specs) do
            if spec.grow then
                items[#items + 1] = { grow = spec.grow == true and 1 or spec.grow, min = spec.min or 0 }
            else
                items[#items + 1] = { size = math.max(spec.min or 0, widths[index] or 0) }
            end
        end
        local placed = UI.Distribute(items, total - BAR * (#items - 1), 0)
        local x = 0
        for index in ipairs(frame.specs) do
            local pane = frame.panes[index]
            pane:ClearAllPoints()
            pane:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
            pane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 0)
            pane:SetWidth(math.max(1, placed[index].size))
            x = x + placed[index].size
            local bar = frame.bars[index]
            if bar then
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
                bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 0)
                x = x + BAR
            end
        end
    end
    frame.Arrange = arrange

    local function save()
        if not (opts.place and opts.key) then return end
        local entry = opts.place[opts.key] or {}
        for index, spec in ipairs(frame.specs) do
            if not spec.grow then entry[spec.key] = math.floor((widths[index] or 0) + 0.5) end
        end
        opts.place[opts.key] = entry
    end

    for index = 1, #frame.specs - 1 do
        local bar = CreateFrame("Button", nil, frame)
        bar:SetWidth(BAR)
        bar.wash = bar:CreateTexture(nil, "BACKGROUND")
        bar.wash:SetAllPoints()
        bar.line = bar:CreateTexture(nil, "ARTWORK")
        bar.line:SetPoint("TOP")
        bar.line:SetPoint("BOTTOM")
        UI.Hairline(bar.line, "width")
        -- The pane a drag resizes: the fixed one beside the bar.
        local left, right = frame.specs[index], frame.specs[index + 1]
        local target, sign = index, 1
        if left.grow and not right.grow then target, sign = index + 1, -1 end
        bar:SetScript("OnEnter", function(b) b.hover = true; b:Repaint() end)
        bar:SetScript("OnLeave", function(b) if not b.drag then b.hover = false; b:Repaint() end end)
        bar:SetScript("OnMouseDown", function(b, mouse)
            if mouse ~= "LeftButton" then return end
            local x = GetCursorPosition() / (b:GetEffectiveScale() or 1)
            b.drag = { x = x, from = widths[target] or 0 }
            b:SetScript("OnUpdate", function(self)
                local now = GetCursorPosition() / (self:GetEffectiveScale() or 1)
                local spec = frame.specs[target]
                widths[target] = math.max(spec.min or 60, self.drag.from + (now - self.drag.x) * sign)
                arrange()
            end)
        end)
        bar:SetScript("OnMouseUp", function(b)
            b.drag = nil
            b:SetScript("OnUpdate", nil)
            b.hover = b:IsMouseOver()
            b:Repaint()
            save()
        end)
        ui:Finish(bar, {}, function(b, t)
            UI.TexColor(b.wash, b.hover and t.accentWash or nil)
            UI.TexColor(b.line, b.hover and t.accent or t.hairline)
        end)
        frame.bars[index] = bar
    end
    frame:HookScript("OnSizeChanged", arrange)
    return ui:Finish(frame, opts)
end, true)
