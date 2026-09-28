-- Tables, pagers, figures, lists, segment bars and slots.

local ctx = ...
local Kit, UI, g, objects, Object, tick, find, show, assertTrue =
    ctx.Kit, ctx.UI, ctx.g, ctx.objects, ctx.Object, ctx.tick, ctx.find, ctx.show, ctx.assertTrue

show("tables")

-- A table: groups fold, the filter finds rows inside them, a group's line
-- never counts as a pick, and every cell sits under its head.
local grid = find(function(o) return rawget(o, "SetFooter") and o.list end)
assertTrue(grid, "the gallery has a table")
local view = grid.list:GetView()
assertTrue(#view == 8, "three groups, the open ones' rows showing: " .. #view)
assertTrue(view[1].isGroup and view[1].count == 3, "a group's line counts its rows")
local cloth = view[1]
local groupRow
for _, row in ipairs(grid.list.rows) do if row.item == cloth then groupRow = row end end
assertTrue(groupRow, "the group's line is drawn")
groupRow:Click()
assertTrue(cloth.item.open == false and #grid.list:GetView() == 5, "a click on a group's line folds it")
assertTrue(grid:GetSelected() == nil, "and picks nothing")
groupRow:Click()
assertTrue(#grid.list:GetView() == 8, "and a second click opens it")
grid:SetFilter("silk")
view = grid.list:GetView()
assertTrue(#view == 2 and view[1].isGroup and view[2].item.name == "Silk Cloth", "the filter finds a row and its group")
grid:SetFilter("dye")
assertTrue(#grid.list:GetView() == 3, "even in a folded group")
grid:SetFilter("")
tick()
local row
for _, r in ipairs(grid.list.rows) do if r:IsShown() and r.entry and not r.entry.isGroup then row = r; break end end
assertTrue(row, "a row of cells is drawn")
local head = grid.kitChildren[1]
for index = 2, #head.cells do
    local hx, rx = head.cells[index].points[1][4], row.cells[index].points[1][4]
    assertTrue(math.abs(hx - (rx + 1)) < 1e-6 and math.abs(head.cells[index].width - row.cells[index].width) < 1e-6,
        "column " .. index .. " sits under its head: " .. hx .. " and " .. rx)
end
assertTrue(row.cells[4].widget and row.cells[4].widget.GetValue, "a column can hold a field")
assertTrue(string.find(grid.kitChildren[3].cells[4].text.text, "g", 1, true), "the footer shows money in coins")
row:Click()
assertTrue(grid:GetSelected() == row.entry.item, "a click on a row picks its item")

-- A pager: held to its range, its ends dimmed, its range of a page.
local pager = find(function(o) return rawget(o, "GetRange") and o.kitTotal end)
local first, last = pager:GetRange()
assertTrue(first == 41 and last == 60, "page 3 of 20 a page holds 41 to 60")
assertTrue(pager.kitChildren[1].text == "Recipes 41 to 60 of 132", "and says so: " .. tostring(pager.kitChildren[1].text))
pager:SetAt(99)
first, last = pager:GetRange()
assertTrue(pager:GetAt() == 7 and last == 132, "the last page ends at the total")
local records = find(function(o) return rawget(o, "GetRange") and not o.kitTotal and o.kitCount == 3 end)
records:SetAt(1)
local back = records.kitChildren[1]
assertTrue(not back.enabled, "back is dimmed on the first")
records:SetAt(3)
assertTrue(not records.kitChildren[3].enabled, "and next on the last")
records:SetCount(2)
assertTrue(records:GetAt() == 2, "fewer records keep the one shown in range")

-- Figures: money in coins, a signed one toned by its sign.
local figures = find(function(o) return o.kitByKey end)
assertTrue(string.find(figures.kitByKey.cost.number.text, "g", 1, true), "a money figure shows coins")
figures:Set("net", 5000)
assertTrue(figures:Get("net") == 5000, "a figure takes a new value")
figures:Set("crafts", 190)
assertTrue(figures.kitByKey.crafts.number.text == "190", "and shows it")

-- A list takes the wheel only once pressed, only while it scrolls, and
-- gives it back when the pointer leaves; a table is a list.
show("lists")
local guides = find(function(o) return rawget(o, "GetView") and o:IsVisible() and #o:GetView() > 10 end)
assertTrue(guides and not guides.wheel, "a list leaves the wheel to the page")
local firstRow = guides.rows[1]
firstRow:Fire("OnMouseDown", "LeftButton")
assertTrue(guides.wheel and guides.kitHeld, "until a row is pressed")
firstRow:Fire("OnLeave")
assertTrue(not guides.wheel and not guides.kitHeld, "and gives it back when the pointer leaves")
show("tables")
grid.list:Fire("OnMouseDown", "LeftButton")
grid:SetItems({ { name = "Linen Cloth", have = 1, need = 2 } })
assertTrue(grid.list.kitHeld and not grid.list.wheel, "a held list with nothing to scroll leaves the wheel alone")
grid.list:Fire("OnLeave")
grid:SetItems({})

-- A segment bar: values to places and back, runs and marks where they
-- fall, and the value under the cursor for a click, a drag and a tooltip.
local picks, asked = {}, {}
local segBar = g.ui:SegmentBar(UIParent, { min = 0, max = 10, scrub = true,
    segments = { { from = 2, to = 5, tone = "success" }, { from = 5, to = 6, tone = "accent", style = "outline" } },
    marks = { { at = 5.5, kind = "pointer" }, { at = 8, tone = "accent" } },
    onPick = function(value) picks[#picks + 1] = value end,
    tooltipFor = function(value) asked[#asked + 1] = value; return "Step " .. math.floor(value) + 1 end })
assertTrue(segBar:KitNaturalHeight() == 8 + 8 + 3, "room for a pointer above and a line's overhang below: " .. segBar:KitNaturalHeight())
segBar:SetSize(400, segBar:KitNaturalHeight())
assertTrue(segBar:XOf(5) == 200 and segBar:ValueAt(200) == 5 and segBar:XOf(99) == 400, "values map to places and back, held to the range")
local fill
for _, o in ipairs(objects) do if o.parent == segBar and o.kind == "Texture" and o.kitSegment then fill = o end end
assertTrue(fill and fill.points[1][4] == 80 and fill.width == 120, "a run covers its values: " .. tostring(fill and fill.points[1][4]))
local outlined
for _, o in ipairs(objects) do if o.parent == segBar and o.kind == "Frame" and o.kitSegment and o.plate then outlined = o end end
assertTrue(outlined and outlined.shown and outlined.width == 40, "an outlined run is drawn as a box")
_G.GetCursorPosition = function() return 300, 300 end  -- 200 in from the bar's left at 100
segBar.scripts.OnMouseDown(segBar, "LeftButton")
assertTrue(picks[1] == 5, "a click picks the value under the cursor: " .. tostring(picks[1]))
_G.GetCursorPosition = function() return 340, 300 end
segBar.scripts.OnUpdate(segBar, 0.016)
assertTrue(picks[2] == 6, "dragging picks as it goes: " .. tostring(picks[2]))
segBar.scripts.OnMouseUp(segBar, "LeftButton")
-- Fired as the client does, hooks and all: only ever asked about a value.
segBar:Fire("OnEnter")
assertTrue(asked[#asked] == 6, "the tooltip asks about the value under the cursor")
for _, value in ipairs(asked) do assertTrue(type(value) == "number", "the tooltip is only asked about values") end
segBar:Fire("OnLeave")
assertTrue(segBar.scripts.OnUpdate == nil, "and stops following once the cursor leaves")
_G.GetCursorPosition = function() return 300, 300 end
segBar:Hide()

-- A list with a gutter and a value.
local gutter = find(function(o) return o.number and o.valueText and o:IsShown() and o.item and o.item.yards end)
assertTrue(gutter and gutter.number.text == "14" and gutter.valueText.text == "120 yd", "a list row shows its number and value")

-- Slot badges: a quest mark, a raid marker in its place, a count on a strip.
local slot = g.ui:Slot(UIParent, { quest = true, count = 14 })
assertTrue(slot.questMark.shown and slot.countStrip.shown, "a quest item shows its mark, a count its strip")
slot:SetMarker(8)
assertTrue(slot.marker.shown and not slot.questMark.shown and string.find(slot.marker.texture, "Icon_8", 1, true),
    "a raid marker takes the corner")
slot:SetMarker(nil)
slot:SetCount(1)
assertTrue(slot.questMark.shown and not slot.marker.shown and not slot.countStrip.shown, "and gives it back; one of a thing has no count")
slot:Hide()

-- Lists: move, activate, states.
for _, o in ipairs(objects) do
    if o.MoveSelection and o.SetItems and o.kitNodes == nil then
        o:SetFilter("w")
        o:MoveSelection(1)
        o:Activate()
        o:SetState("loading", "Reading")
        tick()
        o:SetState(nil)
        o:SetFilter("")
    end
end
