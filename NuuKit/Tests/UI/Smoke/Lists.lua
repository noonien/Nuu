-- Scroll areas, lists, trees, split panes, tables, pagers and figures.

local ctx = ...
local Kit, UI, ui, assertTrue, testWindow, layout, objects, Object =
    ctx.Kit, ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.objects, ctx.Object

-- The room inside a test window's column (a window's body, or a column).
local function room(body)
    local stack = body.kitInner or body
    local pad = 2 * (stack.kitPadding or 0)
    return (stack.kitPW or stack:GetWidth()) - pad, (stack.kitPH or stack:GetHeight()) - pad
end

local function shownRows(list)
    local count = 0
    for _, row in ipairs(list.rows) do if row:IsShown() then count = count + 1 end end
    return count
end

-- Scroll areas ------------------------------------------------------------------------

do
    local _, body = testWindow(ui, 400, 300)
    local area = body:ScrollArea{ gap = 6, padding = 4 }
    local first
    for i = 1, 30 do
        local line = area:Text{ "Line " .. i }
        first = first or line
    end
    layout()
    assertTrue(first.kitParent == area.content, "what is made on a scroll area stacks in its content")
    assertTrue(area.kitPH >= 250, "a scroll area fills its column: " .. tostring(area.kitPH))
    assertTrue(area.content.kitPW == area.kitPW - UI.SCROLLBAR, "its content leaves the bar's room: " .. tostring(area.content.kitPW))
    assertTrue(area.content:GetHeight() > area.kitPH, "its content is as tall as what it holds: " .. area.content:GetHeight())
    assertTrue(area.scroll:ScrollRange() > 0, "and scrolls")
    area:ScrollTo(50)
    assertTrue(area.scroll:GetVerticalScroll() == 50, "ScrollTo")
    area:ScrollToTop()
    assertTrue(area.scroll:GetVerticalScroll() == 0, "ScrollToTop")
    -- More in it lays out the content, not the column above it.
    local laid = 0
    local layoutFn = body.StackLayout
    body.StackLayout = function(self) laid = laid + 1; return layoutFn(self) end
    local height = area.content:GetHeight()
    area:Text{ "One more" }
    layout()
    assertTrue(area.content:GetHeight() > height and laid == 0, "a new line grows the content only: " .. laid)
    body.StackLayout = nil
end

-- Lists --------------------------------------------------------------------------------

local GUIDES = {}
for i = 1, 40 do GUIDES[i] = { name = "Guide " .. i, min = i, horde = (i % 7 == 0) } end

local picked, activated, righted = {}, {}, {}
local function makeGuide(row)
    row.name = row:Text{ "", grow = true }
end
local function drawGuide(row, guide)
    row.name:SetText(guide.name)
    row:SetDisabled(guide.horde, "Horde only")
end

local _, listBody = testWindow(ui, 500, 400)
local typed
local field = { kitOnType = function(text) typed = text end }
local list = listBody:List{
    numbers = true, value = function(guide) return guide.min .. " lv" end,
    make = makeGuide, draw = drawGuide, search = field, empty = "No guides match.",
    onPick = function(guide) picked[#picked + 1] = guide end,
    onActivate = function(guide) activated[#activated + 1] = guide end,
    onRightClick = function(guide, row) righted[#righted + 1] = { guide, row } end,
}
list:SetItems(GUIDES)
layout()
local rows = list.rows
assertTrue(#list:GetView() == 40, "every item in the view")
local _, roomHeight = room(listBody)
assertTrue(list.kitPH == roomHeight, "a list fills its column: " .. tostring(list.kitPH))
local visible = math.floor((list.kitPH - 2) / 26)
assertTrue(visible >= 12 and #rows == visible and shownRows(list) == visible, "a screenful of rows: " .. #rows)
assertTrue(rows[1].item == GUIDES[1] and rows[1].name:GetText() == "Guide 1", "rows draw their items")
assertTrue(rows[1].number:GetText() == "1" and rows[1].valueText:GetText() == "1 lv", "the gutter and the value")
assertTrue(rows[1].name.kitPW > 150, "a row's content is laid out: " .. tostring(rows[1].name.kitPW))
assertTrue(rows[1].kitPW == list.kitPW - UI.SCROLLBAR - 2, "a row leaves the bar's room")

-- A hairline under each row, unless the list asks for none.
do
    local _, plainBody = testWindow(ui, 300, 200)
    local plain = plainBody:List{ make = makeGuide, draw = drawGuide, dividers = false }
    plain:SetItems(GUIDES)
    layout()
    local seen = {}
    local function watch(line) line.SetColorTexture = function(_, r, g, b, a) seen[line] = a end end
    watch(rows[1].line); watch(plain.rows[1].line)
    list:PaintState(ui.tokens); plain:PaintState(ui.tokens)
    assertTrue((seen[rows[1].line] or 0) > 0, "a row has its hairline")
    assertTrue(seen[plain.rows[1].line] == 0, "dividers = false draws none")
    rows[1].line.SetColorTexture, plain.rows[1].line.SetColorTexture = nil, nil
end

-- At a scale where a row snaps taller than its units (19 units at 1.5
-- pixels a unit: 29 pixels, not 28.5), the list still asks for room for
-- every row it wants.
do
    local saved = rawget(_G, "GetPhysicalScreenSize")
    GetPhysicalScreenSize = function() return 2048, 1152 end
    UI.PixelScaleChanged()
    local _, snapBody = testWindow(ui, 300, 400)
    local col = snapBody:Column{ gap = 0 }
    local snapped = col:List{ rows = 8, rowHeight = 19, make = makeGuide, draw = drawGuide }
    snapped:SetItems(GUIDES)
    layout()
    assertTrue(shownRows(snapped) == 8, "every row wanted shows at a snapped scale: " .. shownRows(snapped))
    GetPhysicalScreenSize = saved
    UI.PixelScaleChanged()
end

-- Disabled rows: dimmed, with a reason, and no pick.
local horde = rows[7]
assertTrue(horde.kitDisabled and horde.kitReason == "Horde only" and horde:GetAlpha() == 0.5, "a disabled row is dimmed with its reason")
horde:Click()
assertTrue(#picked == 0 and list:GetSelected() == nil, "a disabled row is not picked")

-- Picks, right clicks, double clicks.
rows[2]:Click()
assertTrue(picked[1] == GUIDES[2] and list:GetSelected() == GUIDES[2], "a click picks")
rows[3]:Click("RightButton")
assertTrue(righted[1][1] == GUIDES[3] and righted[1][2] == rows[3] and list:GetSelected() == GUIDES[2], "a right click asks, and picks nothing")
rows[4]:Fire("OnDoubleClick")
assertTrue(activated[1] == GUIDES[4], "a double click activates")
list:Select(GUIDES[5])
assertTrue(list:GetSelected() == GUIDES[5] and #picked == 1, "Select from code does not call onPick")

-- The keys.
list:MoveSelection(1)
assertTrue(list:GetSelected() == GUIDES[6] and picked[2] == GUIDES[6], "down moves the selection and picks")
list:kitKeyArrow("UP")
assertTrue(list:GetSelected() == GUIDES[5], "up")
list:Select(GUIDES[visible])
list:MoveSelection(1)
assertTrue(list.offset == 1 and rows[visible].item == GUIDES[visible + 1], "moving past the last row scrolls it into view")
list:kitKeyPress("ENTER")
assertTrue(activated[2] == GUIDES[visible + 1], "Enter activates the selection")
list:Select(nil)
list:Activate()
assertTrue(activated[3] == GUIDES[1], "with none, the first in the view")

-- Hover and selection repaint colours only: no font, no layout.
layout()
local fonts = 0
local setFont = Object.SetFont
Object.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
rows[1]:GetScript("OnEnter")(rows[1])
rows[1]:GetScript("OnLeave")(rows[1])
list:Select(GUIDES[3])
Object.SetFont = setFont
assertTrue(fonts == 0 and UI.LayoutSettled(), "hover and selection set no font and lay nothing out")

-- With nothing around it that scrolls, the wheel is the list's while it scrolls.
assertTrue(list.wheel and not list.kitHeld, "a list in a page that does not scroll takes the wheel untouched")
local at = list.offset
list:GetScript("OnMouseWheel")(list, -1)
assertTrue(list.offset == at + 3 and rows[1].item == list:GetView()[at + 4], "a notch moves three rows")
rows[1]:Fire("OnMouseDown", "LeftButton")
rows[1]:Fire("OnLeave")
assertTrue(list.wheel and not list.kitHeld, "and keeps it after it was held")

-- In a page that scrolls, the wheel is the list's only once taken.
do
    local _, body = testWindow(ui, 400, 300)
    local area = body:ScrollArea{ gap = 6 }
    local inner = area:List{ rows = 4, make = makeGuide, draw = drawGuide }
    inner:SetItems(GUIDES)
    local lines = {}
    for i = 1, 30 do lines[i] = area:Text{ "Line " .. i } end
    layout()
    assertTrue(area.scroll:ScrollRange() > 0 and UI.PageScrolls(inner), "the page scrolls")
    inner.rows[1]:Fire("OnEnter")
    assertTrue(not inner.wheel, "a list leaves the wheel to the page")
    inner.rows[1]:Fire("OnMouseDown", "LeftButton")
    assertTrue(inner.wheel and inner.kitHeld, "until a row is pressed")
    inner.rows[1]:Fire("OnLeave")
    assertTrue(not inner.wheel and not inner.kitHeld, "and gives it back when the pointer leaves")
    -- The page stops scrolling: the next time the pointer comes, it is the list's.
    for _, line in ipairs(lines) do line:Release() end
    layout()
    assertTrue(area.scroll:ScrollRange() == 0, "the page no longer scrolls")
    inner:Fire("OnEnter")
    assertTrue(inner.wheel and not inner.kitHeld, "so the list takes the wheel on hover")
    inner:Release()
end

-- Scrolling makes no frames, lays out nothing above the list, and lays each
-- row's content out at once.
layout()
local laid = 0
local layoutFn = listBody.StackLayout
listBody.StackLayout = function(self) laid = laid + 1; return layoutFn(self) end
local made = #objects
list:ScrollSet(0)
local valueWidth = rows[1].valueText.kitPW
list:ScrollSet(12)
assertTrue(rows[1].valueText:GetText() == "13 lv" and rows[1].valueText.kitPW > valueWidth,
    "a row's content is laid out as it is drawn: " .. tostring(rows[1].valueText.kitPW) .. " after " .. tostring(valueWidth))
for _ = 1, 10 do list:GetScript("OnMouseWheel")(list, 1) end
list:ScrollSet(26)
layout()
assertTrue(#objects == made and #rows == visible, "scrolling makes no frames: " .. (#objects - made) .. " new")
assertTrue(laid == 0, "and lays out nothing above the list: " .. laid)
listBody.StackLayout = nil
list:ScrollSet(0)

-- The filter, and the search field's contract.
list:SetFilter("guide 1")
assertTrue(#list:GetView() == 11 and list.offset == 0, "the filter: " .. #list:GetView())
list:SetFilter("zzz")
assertTrue(#list:GetView() == 0 and list.emptyText:IsShown() and list.emptyText:GetText() == "No guides match.", "an empty view says so")
assertTrue(shownRows(list) == 0, "and shows no rows")
assertTrue(field.kitList == list, "a search field sends its keys to the list")
field.kitOnType("guide 2", field)
assertTrue(typed == "guide 2" and #list:GetView() == 11, "and its typing filters it, after its own kitOnType")
field.kitOnType("", field)
assertTrue(#list:GetView() == 40 and not list.emptyText:IsShown(), "cleared, all again")
if ctx.loaded["UI/Controls/Fields.lua"] and listBody.Search then
    local search = listBody:Search{ placeholder = "Search guides" }
    local searched = listBody:List{ rows = 4, make = makeGuide, draw = drawGuide, search = search }
    searched:SetItems(GUIDES)
    assertTrue(search.kitList == searched and search.kitOnType, "a Search field is linked")
    search.kitOnType("guide 3", search)
    assertTrue(#searched:GetView() == 11, "and filters as it is typed")
    searched:Release()
end

-- States put the rows aside.
list:SetState("loading", "Reading guides")
assertTrue(list:GetState() == "loading" and shownRows(list) == 0, "a state hides the rows")
list:SetState(nil)
assertTrue(shownRows(list) == visible, "and they come back")

-- A held list with nothing to scroll leaves the wheel alone.
list:Fire("OnMouseDown", "LeftButton")
list:SetItems({ GUIDES[1], GUIDES[2] })
assertTrue(list.kitHeld and not list.wheel, "a held list with nothing to scroll leaves the wheel alone")
list:Fire("OnLeave")
assertTrue(shownRows(list) == 2, "rows past the items hide")
list:SetItems(GUIDES)

-- A long list: a thousand items, a screenful of frames.
do
    local _, body = testWindow(ui, 400, 300)
    local long = body:List{ make = makeGuide, draw = drawGuide }
    local many = {}
    for i = 1, 1000 do many[i] = { name = "Item " .. i } end
    long:SetItems(many)
    layout()
    local count = #objects
    for step = 1, 200 do long:ScrollSet(step * 4) end
    long:GetScript("OnMouseWheel")(long, -1)
    layout()
    assertTrue(#objects == count, "scrolling a long list makes no frames: " .. (#objects - count))
    assertTrue(#long.rows == math.floor((long.kitPH - 2) / 26), "only the rows that show: " .. #long.rows)
    assertTrue(long.bar:IsShown(), "its bar shows")
    long:Release()
end

-- New items can keep the place; a row shows the tooltip its item asks for.
do
    local _, body = testWindow(ui, 400, 300)
    local tipped
    local kept = body:List{ make = makeGuide, draw = drawGuide,
        tooltip = function(guide) tipped = guide; return guide.name, { links = { item = 6948 } } end }
    kept:SetItems(GUIDES)
    layout()
    kept:ScrollSet(10)
    kept:SetItems(GUIDES, true)
    assertTrue(kept:ScrollAt() == 10, "keep holds the place: " .. kept:ScrollAt())
    kept:SetItems(GUIDES)
    assertTrue(kept:ScrollAt() == 0, "new items otherwise go back to the top")
    local row = kept.rows[1]
    row:GetScript("OnEnter")(row)
    assertTrue(tipped == GUIDES[1] and UI.tipOwner == row, "a row's tooltip is its item's")
    row:GetScript("OnLeave")(row)
    assertTrue(UI.tipOwner == nil, "and goes with the pointer")
    kept:Release()
end

-- At a pixel scale that is not whole (1329 screen pixels high: 1.73 a unit),
-- every row still starts and ends on a whole screen pixel.
do
    local saved = rawget(_G, "GetPhysicalScreenSize")
    _G.GetPhysicalScreenSize = function() return 2360, 1329 end
    UI.PixelScaleChanged()
    local scale = UI.PixelsPerUnit()
    local _, body = testWindow(ui, 400, 300)
    local rows = body:List{ make = makeGuide, draw = drawGuide, rowHeight = 30 }
    rows:SetItems(GUIDES)
    layout()
    local function whole(units) local px = units * scale; return math.abs(px - math.floor(px + 0.5)) < 1e-6 end
    for index = 1, 4 do
        local row = rows.rows[index]
        assertTrue(whole(row.kitPY) and whole(row.kitPY + row.kitPH),
            "row " .. index .. " sits on whole pixels: " .. row.kitPY * scale .. " to " .. (row.kitPY + row.kitPH) * scale)
    end
    rows:Release()
    _G.GetPhysicalScreenSize = saved
    UI.PixelScaleChanged()
end

-- Trees ---------------------------------------------------------------------------------

local NODES = {
    { caption = "Elwynn Forest", count = 2, open = true, children = {
        { caption = "Northshire", value = 1 }, { caption = "Goldshire", value = 2 } } },
    { caption = "Westfall", count = 1, children = { { caption = "Sentinel Hill", value = 3 } } },
    { caption = "Loose notes", value = 4 },
}

do
    local _, body = testWindow(ui, 400, 300)
    local nodePicked, toggled = {}, {}
    local tree = body:Tree{ nodes = NODES,
        onPick = function(node) nodePicked[#nodePicked + 1] = node end,
        onToggle = function(node, open) toggled[#toggled + 1] = { node, open } end }
    layout()
    assertTrue(#tree:GetView() == 5, "an open folder shows its children: " .. #tree:GetView())
    local trows = tree.rows
    assertTrue(trows[1].caption:GetText() == "Elwynn Forest" and trows[1].count:GetText() == "2", "a folder's caption and count")
    assertTrue(trows[2].guides[1] and trows[2].guides[1]:IsShown(), "a child has a guide")
    trows[2]:Click()
    assertTrue(nodePicked[1] == NODES[1].children[1] and tree:GetSelectedNode() == NODES[1].children[1], "a click picks the node")
    trows[1]:Fire("OnDoubleClick")
    assertTrue(not NODES[1].open and #tree:GetView() == 3 and toggled[1][1] == NODES[1] and toggled[1][2] == false,
        "a double click folds a folder")
    assertTrue(tree:GetSelectedNode() == NODES[1].children[1], "the selection survives folding")
    assertTrue(not trows[4]:IsShown(), "rows past the view hide")
    -- A click on the chevron opens.
    local cursor = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 110, 300 end
    trows[2]:Click()
    _G.GetCursorPosition = cursor
    assertTrue(NODES[2].open and #tree:GetView() == 4 and nodePicked[2] == NODES[2], "a click on the chevron opens it")
    trows[1]:Fire("OnDoubleClick")
    tree:SetNodes({ { caption = "One" } })
    assertTrue(#tree:GetView() == 1 and trows[1].caption:GetText() == "One", "new nodes")
    tree:Release()
end

-- Split panes -----------------------------------------------------------------------------

local places = {}
do
    local _, body = testWindow(ui, 800, 400)
    local panes = body:SplitPanes{
        { key = "places", width = 200, min = 120 },
        { key = "list", grow = true, min = 200 },
        { key = "details", width = 180, min = 100 },
        place = places, key = "guides",
    }
    local tree = panes.places:Tree{ nodes = NODES }
    local inner = panes.list:List{ make = makeGuide, draw = drawGuide }
    inner:SetItems(GUIDES)
    local detail = panes.details:Text{ "Elwynn Forest", style = "title" }
    layout()
    assertTrue(panes.places == panes.panes.places and panes.panes[3] == panes.details, "panes by key and by place")
    assertTrue(panes.places.kitPW == 200 and panes.details.kitPW == 180, "fixed panes: " .. tostring(panes.places.kitPW))
    assertTrue(panes.list.kitPW == room(body) - 200 - 180 - 18, "the growing pane takes the rest: " .. tostring(panes.list.kitPW))
    assertTrue(tree.kitPW == 180 and tree.kitPH == panes.places.kitPH - 20, "a tree fills its pane: " .. tostring(tree.kitPH))
    assertTrue(detail.kitPW == 160, "a pane lays out what it holds")
    -- Dragging a bar resizes the fixed pane beside it, and keeps its place.
    local cursor = _G.GetCursorPosition
    local bar = panes.kitBars[1]
    bar:GetScript("OnEnter")(bar)
    bar:GetScript("OnMouseDown")(bar, "LeftButton")
    _G.GetCursorPosition = function() return 340, 300 end
    bar:GetScript("OnUpdate")(bar)
    bar:GetScript("OnMouseUp")(bar, "LeftButton")
    layout()
    assertTrue(panes.places.kitPW == 240 and tree.kitPW == 220, "a drag widens the pane: " .. tostring(panes.places.kitPW))
    assertTrue(places.guides.places == 240 and places.guides.details == 180, "the widths are kept")
    local right = panes.kitBars[2]
    _G.GetCursorPosition = function() return 300, 300 end
    right:GetScript("OnMouseDown")(right, "LeftButton")
    _G.GetCursorPosition = function() return 320, 300 end
    right:GetScript("OnUpdate")(right)
    right:GetScript("OnMouseUp")(right, "LeftButton")
    _G.GetCursorPosition = cursor
    layout()
    assertTrue(panes.details.kitPW == 160 and places.guides.details == 160, "the right bar resizes the right pane: " .. tostring(panes.details.kitPW))
    panes:Release()
    layout()
end

-- Tables ---------------------------------------------------------------------------------

local MATERIALS = {
    { caption = "Cloth", rows = {
        { name = "Linen Cloth", have = 40, need = 120, price = 10 },
        { name = "Wool Cloth", have = 12, need = 60 },
        { name = "Silk Cloth", have = 0, need = 80, price = 410 },
    } },
    { caption = "Thread and dye", open = false, rows = {
        { name = "Red Dye", have = 0, need = 10, price = 50 },
        { name = "Gray Dye", have = 2, need = 12, price = 35 },
    } },
    { caption = "From a vendor", rows = {
        { name = "Coarse Thread", have = 0, need = 40, price = 10 },
        { name = "Fine Thread", have = 5, need = 35, price = 50 },
    } },
}

local drawn = 0
local COLUMNS = {
    { key = "name", caption = "Material", grow = true },
    { key = "have", caption = "Have", width = 50, align = "right", number = true },
    { key = "need", caption = "Need", width = 50, align = "right", number = true,
      color = function(item) return item.need > 100 and "warning" or nil end },
    { key = "price", caption = "Price used", width = 150, money = true, tooltip = "What each is costed at.",
      make = function(ui2, cell) return ui2:Button(cell, { "Set", width = 100 }) end,
      draw = function(button, item)
          drawn = drawn + 1
          button:SetText(item.price and Kit.FormatMoney(item.price) or "none")
      end },
}

local tablePicked = {}
local tableField = {}
local _, tableBody = testWindow(ui, 600, 500)
local grid = tableBody:Table{ rows = 8, footer = true, columns = COLUMNS, search = tableField, empty = "No materials match.",
    onPick = function(item) tablePicked[#tablePicked + 1] = item end }
grid:SetItems(MATERIALS)
grid:SetFooter({ name = "7 materials", price = 182000 })
layout()
local view = grid.list:GetView()
assertTrue(#view == 8, "three groups, the open ones' rows showing: " .. #view)
assertTrue(view[1].isGroup and view[1].count == 3, "a group's line counts its rows")
assertTrue(grid.list.kitRowHeight == 32, "a table with widgets has taller rows")
local cloth = view[1]
local groupRow
for _, row in ipairs(grid.list.rows) do if row.item == cloth then groupRow = row end end
assertTrue(groupRow and groupRow.group:IsShown() and groupRow.group.caption:GetText() == "Cloth", "the group's line is drawn")
groupRow:Click()
assertTrue(cloth.item.open == false and #grid.list:GetView() == 5, "a click on a group's line folds it")
assertTrue(grid:GetSelected() == nil and #tablePicked == 0, "and picks nothing")
groupRow:Click()
assertTrue(#grid.list:GetView() == 8, "and a second click opens it")
grid:SetFilter("silk")
view = grid.list:GetView()
assertTrue(#view == 2 and view[1].isGroup and view[2].item.name == "Silk Cloth", "the filter finds a row and its group")
grid:SetFilter("dye")
assertTrue(#grid.list:GetView() == 3, "even in a folded group")
assertTrue(tableField.kitList == grid.list, "a table's search sends its keys to the list")
tableField.kitOnType("thread", tableField)
assertTrue(#grid.list:GetView() == 3, "and filters the table: " .. #grid.list:GetView())
tableField.kitOnType("", tableField)
assertTrue(#grid.list:GetView() == 8, "cleared")

local row
for _, r in ipairs(grid.list.rows) do if r:IsShown() and r.entry and not r.entry.isGroup then row = r; break end end
assertTrue(row, "a row of cells is drawn")
local head = grid.kitChildren[1]
for index = 2, #head.cells do
    local hx, rx = head.cells[index].points[1][4], row.cells[index].points[1][4]
    assertTrue(math.abs(hx - (rx + 1)) < 1e-6 and math.abs(head.cells[index].width - row.cells[index].width) < 1e-6,
        "column " .. index .. " sits under its head: " .. hx .. " and " .. rx)
end
assertTrue(row.cells[1].points[1][4] == 10 + 18, "a grouped row's first cell is indented")
assertTrue(head.cells[4].tooltip == "What each is costed at.", "a head carries its column's tooltip")
local button = row.cells[4].widget
assertTrue(button and button.kitType == "Button" and button:GetText():find("c", 1, true), "a column can hold a widget: " .. tostring(button and button:GetText()))
assertTrue(button.kitPW == 100 and button:GetParent() == row.cells[4], "placed in its cell at its own width")
assertTrue(row.cells[2].text:GetText() == "40", "a text cell")
assertTrue(string.find(grid.kitChildren[3].cells[4].text:GetText(), "g", 1, true), "the footer shows money in coins")
assertTrue(grid.kitChildren[3].cells[1].text:GetText() == "7 materials", "and words")
row:Click()
assertTrue(grid:GetSelected() == row.entry.item and tablePicked[1] == row.entry.item, "a click on a row picks its item")
grid:Select(MATERIALS[3].rows[2])
assertTrue(grid:GetSelected() == MATERIALS[3].rows[2] and #tablePicked == 1, "Select from code, silently")
grid:SetState("error", "Could not read the bags.")
assertTrue(grid:GetState() == "error", "a table takes a state")
grid:SetState(nil)
local count = #objects
grid.list:ScrollSet(3)
grid.list:ScrollSet(0)
assertTrue(#objects == count, "scrolling a table makes no frames")

-- Pagers -----------------------------------------------------------------------------------

local _, pagerBody = testWindow(ui, 600, 300)
local recipes = pagerBody:Pager{ noun = "Recipes", total = 132, pageSize = 20, at = 3, caption = "Page" }
local first, last = recipes:GetRange()
assertTrue(first == 41 and last == 60, "page 3 of 20 a page holds 41 to 60")
assertTrue(recipes.kitChildren[1]:GetText() == "Recipes 41 to 60 of 132", "and says so: " .. tostring(recipes.kitChildren[1]:GetText()))
assertTrue(recipes.label:GetText() == "Page 3 of 7", "the place: " .. recipes.label:GetText())
recipes:SetAt(99)
first, last = recipes:GetRange()
assertTrue(recipes:GetAt() == 7 and last == 132, "the last page ends at the total")
recipes:SetTotal(0)
assertTrue(recipes.label:GetText() == "None" and recipes.kitChildren[1]:GetText() == "No recipes", "nothing to page")

local changes, added, deleted = {}, 0, {}
local records = pagerBody:Pager{ caption = "Choice", count = 3, at = 2,
    onChange = function(value) changes[#changes + 1] = value end,
    onAdd = function() added = added + 1 end,
    onDelete = function(value) deleted[#deleted + 1] = value end }
records:SetAt(1)
assertTrue(#changes == 0, "SetAt from code does not call onChange")
local back = records.kitChildren[1]
assertTrue(back == records.back and not back.enabled, "back is dimmed on the first")
records.forward:Click()
assertTrue(records:GetAt() == 2 and changes[1] == 2, "next moves and tells")
records:SetAt(3)
assertTrue(not records.forward.enabled, "and next on the last")
records:SetCount(2)
assertTrue(records:GetAt() == 2, "fewer records keep the one shown in range")
records.back:Click()
assertTrue(changes[2] == 1, "back tells")
records.addButton:Click()
assertTrue(added == 1, "add")
records.deleteButton:Click()
assertTrue(#deleted == 0, "delete asks first")
records.deleteButton:Click()
assertTrue(deleted[1] == 1, "then deletes the one shown")

local steps = pagerBody:Pager{ caption = "Step", count = 12, at = 4, words = true }
assertTrue(steps.back:GetText() == "Previous" and steps.forward:GetText() == "Next", "words")
steps.forward:Click()
assertTrue(steps:GetAt() == 5 and steps.label:GetText() == "Step 5 of 12", "a word button steps")
layout()
assertTrue(steps.kitPH > 0 and steps.forward.kitPX > steps.back.kitPX, "a pager lays out as a row")

-- Figures ----------------------------------------------------------------------------------

local figures = pagerBody:Figures{
    { key = "cost", caption = "Cost", money = true, value = 124000 },
    { key = "net", caption = "Net", money = true, signed = true, value = -43000 },
    { key = "crafts", caption = "Crafts", value = 186, tooltip = "Crafts in the plan." },
}
layout()
assertTrue(string.find(figures.kitByKey.cost.number:GetText(), "g", 1, true), "a money figure shows coins")
figures:Set("net", 5000)
assertTrue(figures:Get("net") == 5000, "a figure takes a new value")
figures:Set("crafts", 190)
assertTrue(figures.kitByKey.crafts.number:GetText() == "190", "and shows it")
assertTrue(figures.kitPH == figures:NaturalHeight(), "as tall as a caption over a figure")
local third = figures.cells[3]
assertTrue(math.abs(third.points[1][4] - math.floor(figures.kitPW * 2 / 3 + 0.5)) < 1e-6, "each takes an equal share")
assertTrue(#figures.dividers == 2 and third.tooltip == "Crafts in the plan.", "split by hairlines, with tooltips")

-- A look change repaints them all.
ui:SetLook({ theme = "slate", textSize = "large" })
layout()
ui:SetLook({})
layout()

-- Pooling: cleared and made again with other specs -----------------------------------------------

local _, poolBody = testWindow(ui, 600, 600)
local function makeOther(row)
    row.caption = row:Text{ "", grow = true }
    row.tag = row:Text{ "", style = "fine" }
end
local function drawOther(row, item)
    row.caption:SetText(item.name)
    row.tag:SetText("tag")
end
local OTHER_COLUMNS = {
    { key = "name", caption = "Name", grow = true },
    { key = "go", caption = "Go", width = 80, make = function(ui2, cell) return ui2:Link(cell, { "Open" }) end },
}
local function build(round)
    local l
    if round == 1 then
        l = poolBody:List{ rows = 5, numbers = true, value = function(g) return g.min end, make = makeGuide, draw = drawGuide }
    else
        l = poolBody:List{ rows = 5, rowHeight = 30, make = makeOther, draw = drawOther }
    end
    l:SetItems(GUIDES)
    local tbl = poolBody:Table{ rows = 4, footer = round == 1, columns = round == 1 and COLUMNS or OTHER_COLUMNS }
    tbl:SetItems(round == 1 and MATERIALS or { { name = "Plain" } })
    local tree = poolBody:Tree{ rows = 3, nodes = round == 1 and NODES or { { caption = "Only" } } }
    local pager = poolBody:Pager{ caption = "Page", count = round == 1 and 3 or 9, at = round }
    local figs = poolBody:Figures(round == 1 and { { key = "a", caption = "A", value = 1 }, { key = "b", caption = "B", value = 2 } }
        or { { key = "c", caption = "C", value = 3 } })
    local panes = poolBody:SplitPanes(round == 1 and { { key = "left", width = 200 }, { key = "right", grow = true } }
        or { { key = "one", grow = true }, { key = "two", width = 150 }, { key = "three", width = 150 }, minHeight = 120 })
    local area = poolBody:ScrollArea{ minHeight = 60 }
    area:Text{ "Round " .. round }
    return l, tbl, tree, pager, figs, panes, area
end

build(1)
layout()
local firstList = poolBody.kitChildren[1]
firstList.rows[1]:Fire("OnMouseDown", "LeftButton")
firstList.rows[2]:Click()
poolBody:Clear()
layout()
build(2)
layout()
poolBody:Clear()
layout()
local before = #objects
local l, tbl, tree, pager, figs, panes, area = build(1)
layout()
assertTrue(#objects == before, "a rebuild takes every frame from the pools: " .. (#objects - before) .. " new")
assertTrue(l == firstList, "the list comes from its pool")
assertTrue(l:GetSelected() == nil and not l.kitHeld and l.offset == 0, "with no old selection, hold or scroll")
assertTrue(l.rows[1].number and l.rows[1].number:GetText() == "1" and l.rows[1].name:GetText() == "Guide 1", "rows made again for this make")
assertTrue(l.rows[1].kitPH == 26, "at this row height")
local laidOut
for _, child in ipairs(l.rows[1].kitChildren) do if child == l.rows[1].name then laidOut = child.kitPW end end
assertTrue(laidOut and laidOut > 100, "its content laid out: " .. tostring(laidOut))
assertTrue(#tbl.list:GetView() == 8 and tbl.head.cells[1].text:GetText() == "Material" and tbl.foot:IsShown(), "a table from the pool takes the new columns")
local cellRow = tbl.list.rows[2]
assertTrue(cellRow.cells[4].widget and cellRow.cells[4].widget.kitType == "Button", "and its rows the new cells")
assertTrue(#tree:GetView() >= 3 and tree.rows[1].caption:GetText() == "Elwynn Forest", "a tree from the pool shows its nodes")
assertTrue(pager.label:GetText() == "Page 1 of 3", "a pager from the pool: " .. pager.label:GetText())
assertTrue(figs:Get("a") == 1 and figs:Get("c") == nil and #figs.kitFigures == 2 and figs.cells[2]:IsShown(), "figures from the pool")
assertTrue(panes.left and panes.one == nil and panes.three == nil and #panes.kitChildren == 2, "panes from the pool, no old keys")
assertTrue(#area.content.kitChildren == 1 and area.content.kitChildren[1]:GetText() == "Round 1", "a scroll area holds only this round's")
