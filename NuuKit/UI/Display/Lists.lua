local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Stack = UI.Stack

-- Scroll areas, lists, trees and split panes. The slim bar and the scroll
-- frame are in Base/Scroll.lua.

-- Scroll areas -------------------------------------------------------------------------

-- Free-form content that scrolls. What is made in it stacks in a column as
-- tall as its content; `area:ScrollToTop()`. Spec: gap (8), padding (0),
-- padLeft and padRight (the padding's, at a side: the content keeps room for
-- the scrollbar at its right as well), minHeight (100: the height it asks for
-- when not growing).
local function fitContent(area, width)
    local content = area.kitInner
    width = math.max(1, UI.Snap(area, (width or area:GetWidth() or 0) - UI.SCROLLBAR))
    if content.kitPW ~= width then
        -- Its place first, so its own size hook sees nothing new.
        content.kitPW = width
        content:SetWidth(width)
        UI.Invalidate(content)
    end
end

local function scrollSized(scroll) fitContent(scroll.kitArea, scroll:GetWidth()) end

UI.Define("ScrollArea", {
    holds = true, fills = true,
    Build = function(w)
        w:SetSize(1, 100)
        local scroll, content = UI.NewScroll(w.ui, w)
        scroll:SetAllPoints(w)
        scroll.kitArea = w
        scroll:HookScript("OnSizeChanged", scrollSized)
        UI.MakeStack(w.ui, content, "column", {})
        content.kitLayout = {}
        content.kitAutoHeight = true
        -- The area answers for its content: a new height inside it stops
        -- here, as the area's own size does not follow it.
        content.kitParent = w
        w.kitInner, w.content, w.scroll = content, content, scroll
    end,
    Init = function(w, spec)
        UI.SetStack(w.kitInner, "column", { gap = spec.gap or 8, padding = spec.padding or 0, padLeft = spec.padLeft,
            padRight = spec.padRight })
        w.scroll:ScrollTo(0)
    end,
    Release = function(w)
        if w.kitInner.kitStateFrame then w.kitInner:SetState(nil) end
    end,
    methods = {
        -- As wide as it is given; as tall as asked, whatever it holds.
        Measure = function(self) return 0, self.kitLayout.minHeight or 100 end,
        Sized = function(self, width) fitContent(self, width) end,
        ScrollTo = function(self, y) self.scroll:ScrollTo(y) end,
        ScrollToTop = function(self) self.scroll:ScrollToTop() end,
    },
})

-- Lists ----------------------------------------------------------------------------------

-- A list of items drawn into rows made once and reused, so a thousand items
-- cost a screenful of frames. Spec:
--   rowHeight          default 26
--   make(row)          once per row: what it holds (a row is a row stack:
--                      row:Text{...}, row:Button{...})
--   draw(row, item, i) each time a row shows an item
--   onPick(item, row)  the player's click (not on a disabled row), or a move
--                      of the selection by the keys
--   onActivate(item)   a double click, or Enter from the search field
--   onRightClick(item, row)
--   tooltip(item, row) what hovering a row shows: a filler (a string, or
--                      fn(GameTooltip)) and optionally opts { links, anchor }
--                      as for ui:Tooltip; nil shows none
--   search             a Search field that filters the list as it is typed
--   filter(item, text) whether an item matches, else its `name` or caption
--   empty              what an empty list says
--   rows               how many rows tall it wants to be when not growing
--   numbers            a gutter of numbers at the left: true for the place
--                      in the list, or fn(item, i) for the text
--   numberWidth        the gutter's width (24)
--   value(item)        a muted figure at the right of each row (a distance)
--   gap                between a row's parts (10)
--   wheelRows          rows a notch of the wheel moves (3)
--   dividers           false for no hairline under each row (true)
--   padLeft            room before a row's first part (10); the selection
--                      rail is 3 wide
-- In draw, `row:SetDisabled(on, reason)` dims a row and refuses the pick.
--
-- Rows are the hot path: scrolling draws the rows again and lays out only
-- their own content, at once (row:StackLayout), so nothing above the list
-- moves and no row shows its last item's places for a frame. Hover and
-- selection repaint colours only.
--
-- Select(item) from code never calls onPick (the kit's
-- rule: callbacks are for the player's changes); a click and the arrow keys
-- do. A pooled list keeps its rows while `make` stays the same function;
-- given another make, its rows' widgets go back to their pools and what the
-- last make drew by hand is hidden.
local ROW_HEIGHT = 26
local ART_WELL = { 0, 0, 0, 0.28 }

local function defaultFilter(item, text)
    local name = type(item) == "table" and (item.name or item.caption) or tostring(item)
    return string.find(string.lower(tostring(name or "")), string.lower(text), 1, true) ~= nil
end

-- A row's height on whole screen pixels: rows stack from the list's top, so
-- every row and everything laid out in it stays on the pixel grid (off it,
-- the client drops some one-pixel edges, as a checkbox's).
local function rowStep(w) return UI.Snap(w, w.kitRowHeight) end

local function visibleCount(w)
    -- A hair over, so a height measured for whole rows is not a row short
    -- to rounding.
    return math.max(1, math.floor(((w:GetHeight() or 0) - 2 * UI.Pixels(w, 1)) / rowStep(w) + 0.01))
end

local function maxOffset(w)
    return math.max(0, #w.view - visibleCount(w))
end

-- Row colours: the wash and rail of the selection, the hover. Colours only.
local function paintRow(w, row, t)
    local selected = row.item ~= nil and row.item == w.selected
    local wash
    if selected then
        wash = t.accentWash
    elseif row.hover and not row.kitDisabled then
        wash = UI.Faded(t, t.text, 0.06)
    end
    UI.TexColor(row.bg, wash)
    UI.TexColor(row.bar, selected and t.accent or nil)
    UI.TexColor(row.line, w.kitDividers and t.hairline or nil)
    local hook = w.kitHook
    if hook and hook.paintRow then hook.paintRow(w, row, t, selected) end
end

local function paintRows(w, t)
    for _, row in ipairs(w.rows) do
        if row:IsShown() then paintRow(w, row, t) end
    end
end

-- The wheel is the list's only while it has more than it shows. Where
-- nothing around it scrolls, that is all; inside a page that scrolls, only
-- once the player has taken hold of it (a click on a row, the list or its
-- bar) and until the pointer leaves it: the page scrolling past a list must
-- not stop at it. Held, its edge lights, as a field's does.
local function syncWheel(w)
    w:EnableMouseWheel(maxOffset(w) > 0 and (w.kitHeld or not UI.PageScrolls(w)))
end

local function holdWheel(w, held)
    w.kitHeld = held and true or false
    syncWheel(w)
    w:PaintState(w.ui.tokens)
end

local function listOf(frame) return frame.kitList or frame end

local function take(frame)
    local w = listOf(frame)
    if not w.kitHeld then holdWheel(w, true) end
end

-- The page may have come to scroll, or stopped, since the list last looked.
local function enter(frame) syncWheel(listOf(frame)) end

-- Leaving the list for one of its own rows is not leaving it.
local function leave(frame)
    local w = listOf(frame)
    if w.kitHeld and not w:IsMouseOver() then holdWheel(w, false) end
end

local function listHidden(w)
    if w.kitHeld then holdWheel(w, false) end
end

-- What the player's actions call: the type's own hook (a tree, a table),
-- else the spec's callbacks.
local function selectItem(w, item)
    w.selected = item
    paintRows(w, w.ui.tokens)
end

local function pick(w, item, row)
    selectItem(w, item)
    local hook = w.kitHook
    if hook and hook.pick then
        hook.pick(w, item, row)
    elseif w.kitOnPick then
        w.kitOnPick(item, row)
    end
end

local function activate(w, item)
    local hook = w.kitHook
    if hook and hook.activate then
        hook.activate(w, item)
    elseif w.kitOnActivate then
        w.kitOnActivate(item)
    end
end

local function rightClick(w, item, row)
    local hook = w.kitHook
    if hook and hook.rightClick then
        hook.rightClick(w, item, row)
    elseif w.kitOnRightClick then
        w.kitOnRightClick(item, row)
    end
end

-- Rows ---------------------------------------------------------------------------------

local function rowSetDisabled(row, disabled, reason)
    row.kitDisabled = disabled and true or false
    row.kitReason = disabled and reason or nil
    local alpha = row.kitDisabled and 0.5 or 1
    if row.kitAlpha ~= alpha then
        row.kitAlpha = alpha
        row:SetAlpha(alpha)
    end
end

-- A row's tooltip: what `tooltip(item, row)` answers (a filler, and opts
-- with `links` and `anchor`), and the reason a disabled row gives. One
-- table for the options, filled again on each hover.
local TIP = {}

local function rowEnter(row)
    row.hover = true
    local w = row.kitList
    syncWheel(w)
    paintRow(w, row, w.ui.tokens)
    local filler, opts
    if row.item ~= nil then
        local hook = w.kitHook
        if hook and hook.tooltip then
            filler, opts = hook.tooltip(w, row.item, row)
        elseif w.kitTooltip then
            filler, opts = w.kitTooltip(row.item, row)
        end
    end
    if filler == nil and not row.kitReason then return end
    TIP.anchor = opts and opts.anchor or "ANCHOR_RIGHT"
    TIP.links = opts and opts.links or nil
    TIP.reason = row.kitReason
    w.ui:Tooltip(row, filler, TIP)
    TIP.links = nil
    row.kitTipShown = true
end

local function rowLeave(row)
    row.hover = false
    local w = row.kitList
    paintRow(w, row, w.ui.tokens)
    if row.kitTipShown then
        row.kitTipShown = nil
        w.ui:HideTooltip()
    end
    leave(row)
end

local function rowClick(row, mouse)
    UI.ClearTypingFocus(nil)
    local w, item = row.kitList, row.item
    if item == nil then return end
    if mouse == "RightButton" then
        rightClick(w, item, row)
        return
    end
    if row.kitDisabled then return end
    pick(w, item, row)
    local hook = w.kitHook
    if hook and hook.rowClick then hook.rowClick(w, row, item) end
end

local function rowDoubleClick(row)
    local item = row.kitList and row.item
    if item ~= nil and not row.kitDisabled then activate(row.kitList, item) end
end

-- A row: a row stack with its own parts; what it holds comes from make.
-- It belongs to its list for good (`row.kitList`), never to a pool.
UI.Define("ListRow", {
    kind = "Button", stack = true, internal = true,
    Build = function(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
        row:SetScript("OnEnter", rowEnter)
        row:SetScript("OnLeave", rowLeave)
        row:SetScript("OnClick", rowClick)
        row:SetScript("OnDoubleClick", rowDoubleClick)
        row:HookScript("OnMouseDown", take)
    end,
    Init = function(row, spec) UI.SetStack(row, "row", spec) end,
    methods = { SetDisabled = rowSetDisabled },
})

-- Its place in the list: one row height below the last, the list's width
-- less the bar's room. Answers whether its size changed.
local function placeRow(w, row, index)
    local width = math.max(1, UI.Snap(w, (w:GetWidth() or 0) - UI.SCROLLBAR - 2))
    local height = rowStep(w)
    local edge = UI.Pixels(w, 1)
    local y = edge + (index - 1) * height
    if row.kitPY ~= y then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", w, "TOPLEFT", edge, -y)
        row.kitPY = y
    end
    if row.kitPW ~= width or row.kitPH ~= height then
        row.kitPW, row.kitPH = width, height
        row:SetSize(width, height)
        return true
    end
    return false
end

-- Whether the row was made for this list's make, gutter and value.
local function rowCurrent(w, row)
    return row.kitMadeBy == (w.kitMake or false) and row.kitNumbered == (w.kitNumbers ~= nil)
        and row.kitNumberWidth == w.kitNumberWidth and row.kitValued == (w.kitValue ~= nil)
end

-- What an earlier make put in a row: its widgets back to their pools; what
-- it drew by hand (regions, plain frames) hidden, as the kit cannot know it.
local function hideLoose(row, ok, ...)
    if not ok then return end
    for index = 1, select("#", ...) do
        local part = select(index, ...)
        if type(part) == "table" and part ~= row.bg and part ~= row.bar and part ~= row.line then
            if part.kitType then
                if not part.kitPooled and part.kitParent == nil then UI.Release(part) end
            elseif part.Hide then
                part:Hide()
            end
        end
    end
end

local function clearRow(row)
    row:ReleaseChildren()
    row.number, row.valueText = nil, nil
    if row.GetRegions then hideLoose(row, pcall(row.GetRegions, row)) end
    if row.GetChildren then hideLoose(row, pcall(row.GetChildren, row)) end
end

local function makeRow(w, row)
    if row.kitMadeBy ~= nil then clearRow(row) end
    if w.kitNumbers then
        row.number = row:Text{ "", style = "number", width = w.kitNumberWidth, justify = "RIGHT", color = "muted" }
    end
    if w.kitMake then w.kitMake(row) end
    if w.kitValue then
        row:Spacer{}
        row.valueText = row:Text{ "", style = "number", color = "muted" }
    end
    row.kitMadeBy = w.kitMake or false
    row.kitNumbered = w.kitNumbers ~= nil
    row.kitNumberWidth = w.kitNumberWidth
    row.kitValued = w.kitValue ~= nil
end

-- Draws the rows for the offset: made as the list grows taller, never as it
-- scrolls. Each row's content is laid out now, only inside the row, the
-- layout pass's own included.
local function refresh(w)
    local count = visibleCount(w)
    local view, rows = w.view, w.rows
    local top = maxOffset(w)
    if w.offset > top then w.offset = top end
    if w.offset < 0 then w.offset = 0 end
    local t = w.ui.tokens
    local numbers, value, draw = w.kitNumbers, w.kitValue, w.kitDraw
    for index = 1, math.max(count, #rows) do
        local row = rows[index]
        if index <= count and not w.kitState then
            if not row then
                row = UI.Make(w.ui, "ListRow", w, w.kitRowOpts)
                row.kitList = w
                rows[index] = row
                placeRow(w, row, index)
            end
            if not rowCurrent(w, row) then makeRow(w, row) end
            local at = w.offset + index
            local item = view[at]
            row.item = item
            if item ~= nil then
                rowSetDisabled(row, false)
                row:Show()
                if draw then draw(row, item, at) end
                if row.number then
                    row.number:SetText(type(numbers) == "function" and numbers(item, at) or at)
                end
                if row.valueText then row.valueText:SetText(value(item) or "") end
                if row.kitChildren[1] then row:StackLayout() end
                paintRow(w, row, t)
            else
                row:Hide()
            end
        elseif row then
            row.item = nil
            row:Hide()
        end
    end
    if #view == 0 and not w.kitState and w.kitEmpty then
        local empty = w.emptyText
        if not empty then
            empty = UI.NewText(w)
            empty:SetPoint("CENTER", w, "CENTER", 0, 0)
            UI.ApplyStyle(empty, "body", t, "muted")
            w.emptyText = empty
        end
        empty:SetText(w.kitEmpty)
        empty:Show()
    elseif w.emptyText then
        w.emptyText:Hide()
    end
    -- More or fewer items: it takes the wheel only if it scrolls.
    syncWheel(w)
    w.bar:Sync()
end

-- `keep` holds the place in the list (as far as it still goes), for new
-- items of the same list; otherwise it goes back to the top.
local function applyFilter(w, keep)
    local text = w.filterText
    if text == "" then
        w.view = w.items
    else
        local match = w.kitFilterFn or defaultFilter
        local view = {}
        for _, item in ipairs(w.items) do
            if match(item, text) then view[#view + 1] = item end
        end
        w.view = view
    end
    if not keep then w.offset = 0 end
    refresh(w)
end

-- A new size: the rows placed again, as many as now fit.
local function listResized(w)
    local width, height = w:GetWidth() or 0, w:GetHeight() or 0
    if w.kitSizedW == width and w.kitSizedH == height then return end
    w.kitSizedW, w.kitSizedH = width, height
    for index, row in ipairs(w.rows) do placeRow(w, row, index) end
    refresh(w)
end

local function listWheel(w, delta)
    w.offset = math.max(0, math.min(maxOffset(w), w.offset - delta * w.kitWheelRows))
    refresh(w)
end

-- Search to List -----------------------------------------------------------------------

-- The contract with Controls/Fields.lua: the field calls kitOnType on each
-- change of its text, and sends the arrows and Enter to kitList. The field's
-- own kitOnType, if any, is kept and called first.
local function searchTyped(text, field)
    if field.kitListTyped then field.kitListTyped(text, field) end
    local target = field.kitFilterTarget
    if target then target:SetFilter(text) end
end

-- `list` takes the keys; `target` (a table on the list) takes the filter.
function UI.LinkSearch(field, list, target)
    if not field then return end
    if field.kitOnType ~= searchTyped then field.kitListTyped = field.kitOnType end
    field.kitOnType = searchTyped
    field.kitList = list
    field.kitFilterTarget = target or list
end

function UI.UnlinkSearch(field, target)
    if not field or field.kitFilterTarget ~= target then return end
    if field.kitOnType == searchTyped then field.kitOnType = field.kitListTyped end
    field.kitListTyped, field.kitList, field.kitFilterTarget = nil, nil, nil
end

-- The list type, shared with Tree and the table's list ---------------------------------

local function buildList(w)
    w:SetSize(1, 1)
    w.plate = UI.NewPlate(w)
    w.rows = {}
    -- For SetState, which puts a stack's children aside: a list has none.
    w.kitChildren = {}
    w.items, w.view, w.offset, w.filterText = {}, {}, 0, ""
    w:EnableMouse(true)
    local bar = UI.NewScrollBar(w.ui, w, w, 1)
    bar:SetPoint("TOPRIGHT", w, "TOPRIGHT", -2, -3)
    bar:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -2, 3)
    bar.kitList, bar.thumb.kitList = w, w
    w.bar = bar
    w:EnableMouseWheel(false)
    w:HookScript("OnMouseDown", take)
    w:HookScript("OnEnter", enter)
    w:HookScript("OnLeave", leave)
    w:HookScript("OnHide", listHidden)
    for _, part in ipairs({ bar, bar.thumb }) do
        part:HookScript("OnMouseDown", take)
        part:HookScript("OnEnter", enter)
        part:HookScript("OnLeave", leave)
    end
    w:SetScript("OnMouseWheel", listWheel)
    w:HookScript("OnSizeChanged", listResized)
end

-- Everything from the spec. `hook` is the type's own handling (a tree's, a
-- table's): pick, activate, rightClick, rowClick, paintRow, paint.
local function initList(w, spec, hook)
    w.kitHook = hook
    w.kitRowHeight = spec.rowHeight or ROW_HEIGHT
    w.kitRowsWanted = spec.rows or 6
    w.kitMake, w.kitDraw = spec.make, spec.draw
    w.kitNumbers, w.kitNumberWidth, w.kitValue = spec.numbers or nil, spec.numberWidth or 24, spec.value
    w.kitOnPick, w.kitOnActivate, w.kitOnRightClick = spec.onPick, spec.onActivate, spec.onRightClick
    w.kitTooltip = spec.tooltip
    w.kitFilterFn, w.kitEmpty = spec.filter, spec.empty
    w.kitWheelRows = spec.wheelRows or 3
    w.kitDividers = spec.dividers ~= false
    w.items, w.view, w.offset, w.filterText, w.selected = {}, {}, 0, "", nil
    w.kitHeld = false
    w:EnableMouseWheel(false)
    w.kitSizedW, w.kitSizedH = nil, nil
    local rowOpts = { gap = spec.gap or 10, padding = 0, padLeft = spec.padLeft or 10, padRight = 8 }
    w.kitRowOpts = rowOpts
    for index, row in ipairs(w.rows) do
        UI.SetStack(row, "row", rowOpts)
        row.hover, row.item = nil, nil
        placeRow(w, row, index)
    end
    w.kitSearch = spec.search
    if spec.search then UI.LinkSearch(spec.search, w, w) end
    refresh(w)
end

local function releaseList(w)
    if w.kitStateFrame then Stack.SetState(w, nil) end
    if w.kitSearch then UI.UnlinkSearch(w.kitSearch, w) end
    w.kitSearch = nil
    w.kitHeld = false
    w.kitTooltip = nil
    w.selected, w.items, w.view = nil, {}, {}
    for _, row in ipairs(w.rows) do
        row.item, row.hover, row.kitTipShown = nil, nil, nil
        row:Hide()
    end
end

local listMethods = {
    -- Rows on the pixel grid and the edge above and below: a row snapped
    -- taller than its units must not push the last row out.
    Measure = function(self) return 0, self.kitRowsWanted * rowStep(self) + 2 * UI.Pixels(self, 1) end,
    Sized = function(self) listResized(self) end,
    Paint = function(self, t)
        if self.emptyText then UI.ApplyStyle(self.emptyText, "body", t, "muted") end
        local hook = self.kitHook
        if hook and hook.paint then hook.paint(self, t) end
        self:PaintState(t)
    end,
    PaintState = function(self, t)
        self.plate:Flat(t.art and ART_WELL or t.surfaceBg, self.kitHeld and t.accent65 or t.hairline)
        paintRows(self, t)
    end,
    Refresh = function(self) refresh(self) end,
    -- New items; `keep` leaves the list scrolled where it was.
    SetItems = function(self, items, keep)
        self.items = items or {}
        applyFilter(self, keep)
    end,
    GetItems = function(self) return self.items end,
    GetView = function(self) return self.view end,
    SetFilter = function(self, text)
        self.filterText = text or ""
        applyFilter(self)
    end,
    GetFilter = function(self) return self.filterText end,
    GetSelected = function(self) return self.selected end,
    -- From code: the selection shows, and onPick is not called.
    Select = function(self, item) selectItem(self, item) end,
    -- Keeps `item` in view.
    ScrollToItem = function(self, item)
        for index, value in ipairs(self.view) do
            if value == item then
                local count = visibleCount(self)
                if index <= self.offset then
                    self.offset = index - 1
                elseif index > self.offset + count then
                    self.offset = index - count
                end
                refresh(self)
                return
            end
        end
    end,
    -- The keys' move: the player's, so onPick hears it.
    MoveSelection = function(self, step)
        local view = self.view
        if #view == 0 then return end
        local at = 0
        for index, value in ipairs(view) do if value == self.selected then at = index end end
        local target = at + step
        if at == 0 then target = step > 0 and 1 or #view end
        target = math.max(1, math.min(#view, target))
        pick(self, view[target], nil)
        self:ScrollToItem(view[target])
    end,
    Activate = function(self)
        local item = self.selected
        if item == nil then item = self.view[1] end
        if item ~= nil then activate(self, item) end
    end,
    kitKeyArrow = function(self, key)
        if key == "UP" then self:MoveSelection(-1) elseif key == "DOWN" then self:MoveSelection(1) end
    end,
    kitKeyPress = function(self) self:Activate() end,
    -- A state (loading, empty, error) puts the rows aside too.
    SetState = function(self, kind, text, opts)
        Stack.SetState(self, kind, text, opts)
        refresh(self)
    end,
    GetState = Stack.GetState,
    -- The scroll bar's source: it scrolls by rows.
    ScrollRange = function(self) return maxOffset(self) end,
    ScrollAt = function(self) return self.offset end,
    ScrollView = function(self) return visibleCount(self) end,
    ScrollSet = function(self, value)
        self.offset = math.max(0, math.min(maxOffset(self), math.floor(value + 0.5)))
        refresh(self)
    end,
}

UI.Define("List", {
    fills = true, focusable = true,
    Build = buildList,
    Init = function(w, spec) initList(w, spec, nil) end,
    Release = releaseList,
    methods = listMethods,
})

-- A folder's chevron, pointing down while open: a tree's, a table group's.
local function newChevron(parent, size)
    local chevron = UI.NewFrame("Frame", nil, parent)
    chevron:SetSize(size, size)
    chevron.open = UI.NewGlyph(chevron, "down", 8, 1.5)
    chevron.shut = UI.NewGlyph(chevron, "next", 8, 1.5)
    return chevron
end

local function drawChevron(chevron, folder, open, t)
    chevron.open:SetShown(folder and open)
    chevron.shut:SetShown(folder and not open)
    chevron.open:SetColor(t.muted)
    chevron.shut:SetColor(t.muted)
end

-- For Tree and Tables.lua: a list type with its own make, draw and hook.
UI.ListParts = {
    build = buildList, init = initList, release = releaseList, methods = listMethods,
    refresh = refresh, select = selectItem, newChevron = newChevron, drawChevron = drawChevron,
}

local function withMethods(extra)
    local methods = {}
    for key, fn in pairs(listMethods) do methods[key] = fn end
    for key, fn in pairs(extra or {}) do methods[key] = fn end
    return methods
end

-- Trees ------------------------------------------------------------------------------------

-- Folders any depth deep, on a List. Nodes are { caption, count, children,
-- open, value }; a node with children is a folder. A click picks
-- (`onPick(node)`), a click on the chevron or a double click opens or closes
-- (`onToggle(node, open)`; the kit keeps `node.open`). Spec: nodes,
-- rowHeight (24), rows, empty, onPick, onToggle. Its rows draw their own
-- guides, chevron and words.
local INDENT = 14
local WEAK = { __mode = "k" }

local function flatten(w)
    local out = {}
    -- One entry per node for good, so the selection survives folding.
    local entries = w.kitEntries
    local function walk(nodes, depth)
        for _, node in ipairs(nodes or {}) do
            local entry = entries[node] or { node = node }
            entries[node] = entry
            entry.depth = depth
            out[#out + 1] = entry
            if node.children and node.open then walk(node.children, depth + 1) end
        end
    end
    walk(w.kitNodes, 0)
    return out
end

local function toggleNode(w, entry)
    local node = entry.node
    if not node.children then return end
    node.open = not node.open
    -- Folding keeps the place in the list where it can.
    w.items = flatten(w)
    w.view = w.items
    refresh(w)
    if w.kitOnToggle then w.kitOnToggle(node, node.open) end
end

local function treeMake(row)
    row.guides = {}
    row.chevron = newChevron(row, 12)
    row.caption = UI.NewText(row)
    row.count = UI.NewText(row)
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.count:SetJustifyH("RIGHT")
end

local function treeDraw(row, entry)
    local w = row.kitList
    local t = w.ui.tokens
    local node, depth = entry.node, entry.depth
    local left = 8 + depth * INDENT
    for index = 1, math.max(depth, #row.guides) do
        local guide = row.guides[index]
        if index <= depth then
            if not guide then
                guide = row:CreateTexture(nil, "ARTWORK")
                local x = UI.Snap(row, 8 + (index - 1) * INDENT + 5)
                guide:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
                guide:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
                UI.Hairline(guide, "width")
                row.guides[index] = guide
            end
            UI.TexColor(guide, t.hairline)
            guide:Show()
        elseif guide then
            guide:Hide()
        end
    end
    if row.kitLeft ~= left then
        row.kitLeft = left
        row.chevron:ClearAllPoints()
        row.chevron:SetPoint("LEFT", row, "LEFT", left, 0)
        row.caption:ClearAllPoints()
        row.caption:SetPoint("LEFT", row, "LEFT", left + 16, 0)
        row.caption:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    end
    drawChevron(row.chevron, node.children ~= nil, node.open and true or false, t)
    row.caption:SetText(node.caption or tostring(node.value or ""))
    row.count:SetText(node.count ~= nil and tostring(node.count) or "")
    UI.ApplyStyle(row.caption, "body", t, nil, true)
    UI.ApplyStyle(row.count, "number", t, "muted")
    row.kitChevronRight = left + 14
end

local TREE_HOOK = {
    pick = function(w, entry) if w.kitTreePick then w.kitTreePick(entry.node) end end,
    activate = function(w, entry) toggleNode(w, entry) end,
    -- A click on the chevron (or left of it) opens or closes the folder.
    rowClick = function(w, row, entry)
        if type(GetCursorPosition) ~= "function" then return end
        local x = GetCursorPosition() / (row:GetEffectiveScale() or 1)
        local left = row:GetLeft() or 0
        if x - left <= (row.kitChevronRight or 0) then toggleNode(w, entry) end
    end,
    -- The selected node's caption in the accent: a colour.
    paintRow = function(w, row, t, selected)
        if row.caption then UI.TextColor(row.caption, selected and t.accent or t.text) end
    end,
    -- A new look: the rows' words drawn again in its fonts.
    paint = refresh,
}

UI.Define("Tree", {
    fills = true, focusable = true,
    Build = buildList,
    Init = function(w, spec)
        w.kitNodes = spec.nodes or {}
        w.kitEntries = setmetatable({}, WEAK)
        w.kitTreePick, w.kitOnToggle = spec.onPick, spec.onToggle
        initList(w, { rowHeight = spec.rowHeight or 24, rows = spec.rows, empty = spec.empty,
            make = treeMake, draw = treeDraw }, TREE_HOOK)
        w:SetItems(flatten(w))
    end,
    Release = releaseList,
    methods = withMethods({
        SetNodes = function(self, nodes)
            self.kitNodes = nodes or {}
            self:SetItems(flatten(self))
        end,
        GetSelectedNode = function(self) return self.selected and self.selected.node end,
    }),
})

-- Split panes -----------------------------------------------------------------------------

-- Panes side by side with bars to drag between them. The spec's array part
-- is the panes: { key, width, min, grow, gap, padding }; a pane is a column,
-- reached as `panes[key]` (or panes.panes[key], panes.panes[index]). With
-- `place` and `key` the fixed panes' widths are kept in place[key].
-- minHeight (200) is the height it asks for when not growing.
local BAR = 9
local sizes = {}

-- Puts a pane at x, the full height, skipping what did not move; a pane
-- whose size changed lays out what it holds.
local function placePane(w, pane, x, width, height)
    local left = UI.Snap(w, x)
    width = math.max(1, UI.Snap(w, x + width) - left)
    if pane.kitPX ~= left then
        pane:ClearAllPoints()
        pane:SetPoint("TOPLEFT", w, "TOPLEFT", left, 0)
        pane.kitPX, pane.kitPY = left, 0
    end
    if pane.kitPW ~= width or pane.kitPH ~= height then
        pane.kitPW, pane.kitPH = width, height
        pane:SetSize(width, height)
        UI.Invalidate(pane)
    end
end

local function arrange(w)
    local total, height = w:GetWidth() or 0, w:GetHeight() or 0
    local specs, panes = w.kitSpecs, w.kitChildren
    local count = #panes
    if total <= 0 or count == 0 then return end
    height = UI.Snap(w, height)
    local fixed, weights = 0, 0
    for index = 1, count do
        local spec = specs[index]
        if spec.grow then
            weights = weights + (spec.grow == true and 1 or spec.grow)
        else
            sizes[index] = math.max(spec.min or 0, w.kitWidths[index] or 0)
            fixed = fixed + sizes[index]
        end
    end
    local spare = math.max(0, total - BAR * (count - 1) - fixed)
    for index = 1, count do
        local spec = specs[index]
        if spec.grow then
            local weight = spec.grow == true and 1 or spec.grow
            sizes[index] = math.max(spec.min or 0, weights > 0 and spare * weight / weights or 0)
        end
    end
    local x = 0
    for index = 1, count do
        placePane(w, panes[index], x, sizes[index], height)
        x = x + sizes[index]
        local bar = w.kitBars[index]
        if index < count and bar then
            local left = UI.Snap(w, x)
            if bar.kitPX ~= left then
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", w, "TOPLEFT", left, 0)
                bar:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", left, 0)
                bar.kitPX = left
            end
            x = x + BAR
        end
    end
end

local function saveWidths(w)
    local place, key = w.kitPlace, w.kitPlaceKey
    if not (place and key) then return end
    local entry = place[key] or {}
    for index, spec in ipairs(w.kitSpecs) do
        if not spec.grow and spec.key then entry[spec.key] = math.floor((w.kitWidths[index] or 0) + 0.5) end
    end
    place[key] = entry
end

local function paintSplitBar(bar, t)
    UI.TexColor(bar.wash, bar.hover and t.accentWash or nil)
    UI.TexColor(bar.line, bar.hover and t.accent or t.hairline)
end

local function cursorX(frame)
    return GetCursorPosition() / (frame:GetEffectiveScale() or 1)
end

local function barFollow(bar)
    local w = bar.kitSplit
    local spec = w.kitSpecs[bar.kitTarget]
    if not spec or not bar.kitDragging then return end
    w.kitWidths[bar.kitTarget] = math.max(spec.min or 60, bar.kitDragFrom + (cursorX(bar) - bar.kitDragX) * bar.kitSign)
    arrange(w)
end

local function barEnter(bar)
    bar.hover = true
    paintSplitBar(bar, bar.kitSplit.ui.tokens)
end

local function barLeave(bar)
    if bar.kitDragging then return end
    bar.hover = false
    paintSplitBar(bar, bar.kitSplit.ui.tokens)
end

local function barDown(bar, mouse)
    if mouse ~= "LeftButton" or type(GetCursorPosition) ~= "function" then return end
    bar.kitDragging = true
    bar.kitDragX = cursorX(bar)
    bar.kitDragFrom = bar.kitSplit.kitWidths[bar.kitTarget] or 0
    bar:SetScript("OnUpdate", barFollow)
end

local function barUp(bar)
    if not bar.kitDragging then return end
    bar.kitDragging = false
    bar:SetScript("OnUpdate", nil)
    bar.hover = bar:IsMouseOver() and true or false
    paintSplitBar(bar, bar.kitSplit.ui.tokens)
    saveWidths(bar.kitSplit)
end

local function newSplitBar(w)
    local bar = UI.NewFrame("Button", nil, w)
    bar:SetWidth(BAR)
    bar.kitSplit = w
    bar.wash = bar:CreateTexture(nil, "BACKGROUND")
    bar.wash:SetAllPoints()
    bar.line = bar:CreateTexture(nil, "ARTWORK")
    bar.line:SetPoint("TOP")
    bar.line:SetPoint("BOTTOM")
    UI.Hairline(bar.line, "width")
    bar:SetScript("OnEnter", barEnter)
    bar:SetScript("OnLeave", barLeave)
    bar:SetScript("OnMouseDown", barDown)
    bar:SetScript("OnMouseUp", barUp)
    bar:HookScript("OnHide", barUp)
    return bar
end

local function splitSized(w) arrange(w) end

UI.Define("SplitPanes", {
    fills = true,
    Build = function(w)
        w:SetSize(1, 1)
        w.kitChildren, w.kitBars, w.kitWidths, w.kitPaneKeys = {}, {}, {}, {}
        w:HookScript("OnSizeChanged", splitSized)
    end,
    Init = function(w, spec)
        w.kitSpecs = {}
        for index, pane in ipairs(spec) do w.kitSpecs[index] = pane end
        w.kitPlace, w.kitPlaceKey = spec.place, spec.key
        local saved = spec.place and spec.key and spec.place[spec.key] or {}
        w.panes = {}
        for index, paneSpec in ipairs(w.kitSpecs) do
            w.kitWidths[index] = (not paneSpec.grow) and (saved[paneSpec.key] or paneSpec.width or 200) or nil
            local pane = UI.Make(w.ui, "Column", w, { gap = paneSpec.gap or 8, padding = paneSpec.padding or 10 })
            -- A list, tree or scroll area made in a pane fills it.
            pane.kitFillChildren = true
            pane.kitParent = w
            w.kitChildren[index] = pane
            w.panes[index] = pane
            if paneSpec.key then
                w.panes[paneSpec.key] = pane
                if w[paneSpec.key] == nil then
                    w[paneSpec.key] = pane
                    w.kitPaneKeys[#w.kitPaneKeys + 1] = paneSpec.key
                end
            end
        end
        for index = #w.kitSpecs + 1, #w.kitWidths do w.kitWidths[index] = nil end
        -- The pane a drag resizes: the fixed one beside the bar.
        for index = 1, #w.kitSpecs - 1 do
            local bar = w.kitBars[index] or newSplitBar(w)
            w.kitBars[index] = bar
            local left, right = w.kitSpecs[index], w.kitSpecs[index + 1]
            bar.kitTarget, bar.kitSign = index, 1
            if left.grow and not right.grow then bar.kitTarget, bar.kitSign = index + 1, -1 end
            bar.hover, bar.kitDragging, bar.kitPX = false, false, nil
            bar:SetScript("OnUpdate", nil)
            bar:Show()
        end
        for index = #w.kitSpecs, #w.kitBars do
            if index >= 1 and w.kitBars[index] then w.kitBars[index]:Hide() end
        end
        arrange(w)
    end,
    Release = function(w)
        for index = #w.kitChildren, 1, -1 do
            local pane = w.kitChildren[index]
            w.kitChildren[index] = nil
            pane.kitParent = nil
            UI.Release(pane)
        end
        for index = #w.kitPaneKeys, 1, -1 do
            w[w.kitPaneKeys[index]] = nil
            w.kitPaneKeys[index] = nil
        end
        for _, bar in ipairs(w.kitBars) do
            bar.kitDragging = false
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
        end
        w.panes, w.kitPlace, w.kitPlaceKey = nil, nil, nil
    end,
    methods = {
        Measure = function(self) return 0, self.kitLayout.minHeight or 200 end,
        -- The layout sizes it, or a pane's content changed: the panes placed.
        StackLayout = function(self) arrange(self) end,
        Arrange = function(self) arrange(self) end,
        GetWidths = function(self) return self.kitWidths end,
        Paint = function(self, t)
            for index = 1, #self.kitSpecs - 1 do paintSplitBar(self.kitBars[index], t) end
        end,
    },
})
