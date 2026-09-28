-- Menus: OpenMenu and its items, rows made once and kept, Select,
-- SearchSelect and MultiSelect, and selects rebuilt from the pool.

local ctx = ...
local UI, ui, assertTrue, testWindow, layout, objects, tick =
    ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.objects, ctx.tick

local function rowFor(menu, caption)
    for index = 1, menu.count do
        local row = menu.rows[index]
        if row.item and (row.item.caption == caption or row.item.header == caption) then return row end
    end
end

-- A menu, filled, filtered and chosen from ------------------------------------------------

local checked, clicked = nil, nil
local items = {
    { header = "Step 12" },
    { caption = "Go", key = "Click", onClick = function() clicked = "go" end },
    { caption = "Sub", items = { { caption = "Inner", onClick = function() clicked = "inner" end } } },
    { caption = "Check", check = true, value = false, onChange = function(on) checked = on end },
    { caption = "Radio", group = "g", value = 1, checked = true },
    { separator = true },
    { caption = "Danger", tone = "danger", desc = "A second line." },
}
local closed = 0
ui:OpenMenu(items, { at = "cursor", search = true, onClose = function() closed = closed + 1 end })
local menu = ui.kitMenu
assertTrue(menu and menu:IsShown() and menu.count == 7, "the menu fills every item")
assertTrue(menu.search:IsShown() and menu.catcher:IsShown(), "with its filter box, and a catcher for clicks elsewhere")
local danger = rowFor(menu, "Danger")
assertTrue(danger.height > rowFor(menu, "Go").height, "a description makes its row taller")
assertTrue(rowFor(menu, "Radio").current, "a checked radio is marked")
assertTrue(rowFor(menu, "Go").key:GetText() == "Click", "a key shows at the right")

-- Hover repaints colours only.
local go = rowFor(menu, "Go")
local fonts = 0
local setFont = go.caption.SetFont
go.caption.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
go:GetScript("OnEnter")(go)
assertTrue(go.hover, "hovered")
go:GetScript("OnLeave")(go)
assertTrue(fonts == 0, "a row's hover sets no font")
go.caption.SetFont = nil

-- The filter narrows it, and says when nothing matches.
menu.search:SetText("ch")
menu.search.scripts.OnTextChanged(menu.search, true)
assertTrue(menu.count == 1 and menu.rows[1].item.caption == "Check", "the filter narrows it")
menu.rows[1]:Click()
assertTrue(checked == true and items[4].value == true and menu:IsShown(), "a check flips, calls onChange, and stays open")
menu.search:SetText("zzz")
menu.search.scripts.OnTextChanged(menu.search, true)
assertTrue(menu.count == 0 and menu.empty:IsShown(), "nothing matches")
menu.search:SetText("go")
menu.search.scripts.OnTextChanged(menu.search, true)
menu.search.scripts.OnEnterPressed(menu.search)
assertTrue(clicked == "go" and not menu:IsShown() and closed == 1, "Enter takes the first match; the menu closes")

-- Rows are made once: the same menu opened again makes no new frames.
local made = #objects
ui:OpenMenu(items, { at = "cursor" })
assertTrue(#objects == made, "a menu opened again makes no new frames: " .. (#objects - made) .. " new")
assertTrue(not menu.search:IsShown() and menu.count == 7, "no filter box this time")
ui:CloseMenu()
ui:OpenMenu({ { caption = "One" } }, { at = "cursor" })
assertTrue(menu.count == 1 and not menu.rows[2]:IsShown() and menu.rows[2].item == nil, "the rows not needed hide")
ui:CloseMenu()
ui:OpenMenu(items, { at = "cursor" })
assertTrue(#objects == made, "and fewer then more items still reuse them")

-- A submenu opens on hover and its choice closes both.
local sub = rowFor(menu, "Sub")
sub:GetScript("OnEnter")(sub)
local inner = menu.sub
assertTrue(inner and inner:IsShown() and inner.count == 1, "hover opens the submenu")
go = rowFor(menu, "Go")
go:GetScript("OnEnter")(go)
assertTrue(not inner:IsShown(), "hover on another row closes it")
sub:Click()
assertTrue(inner:IsShown(), "a click opens it too")
inner.rows[1]:Click()
assertTrue(clicked == "inner" and not menu:IsShown() and not inner:IsShown(), "its choice closes both")
made = #objects
ui:OpenMenu(items, { at = "cursor" })
rowFor(menu, "Sub"):GetScript("OnEnter")(rowFor(menu, "Sub"))
assertTrue(#objects == made, "the submenu keeps its rows too")
ui:CloseMenu()

-- Radios, onChoose and the current value, keep, disabled with a reason.
local radio
ui:OpenMenu({
    { header = "List shows" },
    { caption = "Next 10 steps", group = "list", value = "next" },
    { caption = "This section", group = "list", value = "section", checked = true },
}, { at = "cursor", onChange = function(group, value) radio = group .. "=" .. value end })
rowFor(menu, "Next 10 steps"):Click()
assertTrue(radio == "list=next" and not menu:IsShown(), "a radio calls onChange(group, value) and closes")

local chose, kept, tipped = nil, 0, nil
local anchor = ui:Button(UIParent, { "Open" })
local plain = {
    { caption = "Two", value = 2 },
    { caption = "Three", value = 3 },
    { caption = "Keep", keep = true, onClick = function() kept = kept + 1 end },
    { caption = "Locked", value = 4, disabled = true, reason = "Learn it first." },
}
local function openPlain(extra)
    local opts = { anchor = anchor, current = 2, onChoose = function(value) chose = value end }
    for key, value in pairs(extra or {}) do opts[key] = value end
    return ui:OpenMenu(plain, opts)
end
openPlain()
assertTrue(ui:MenuOpenFor(anchor) and menu.anchor == anchor, "open for its anchor")
assertTrue(menu.points[1][1] == "TOPLEFT" and menu.points[1][2] == anchor, "hung under the anchor's left edge")
assertTrue(rowFor(menu, "Two").current and rowFor(menu, "Two").check.lines[1].shown ~= false, "the current value is marked")
rowFor(menu, "Keep"):Click()
assertTrue(kept == 1 and menu:IsShown(), "a keep item acts and stays open")
local locked = rowFor(menu, "Locked")
local tooltip = ui.Tooltip
ui.Tooltip = function(_, _, text) tipped = text end
locked:GetScript("OnEnter")(locked)
ui.Tooltip = tooltip
assertTrue(tipped == "Learn it first.", "a disabled item says why")
locked:Click()
assertTrue(chose == nil and menu:IsShown(), "and cannot be chosen")
rowFor(menu, "Two"):Click()
assertTrue(chose == nil and not menu:IsShown(), "choosing the current value closes without onChoose")
openPlain()
rowFor(menu, "Three"):Click()
assertTrue(chose == 3, "onChoose hears a new value")
openPlain()
assertTrue(openPlain() == nil and not menu:IsShown(), "opened again from the same anchor, it closes")
openPlain({ align = "right" })
assertTrue(menu.points[1][1] == "TOPRIGHT", "align right hangs it by the right edge")
anchor:Hide()
tick()
assertTrue(not menu:IsShown() and not ui:MenuOpenFor(anchor), "a menu goes when its anchor does")
menu.catcher:Click()

-- A look change repaints an open menu.
ui:OpenMenu(items, { at = "cursor" })
ui:SetLook({ textScale = 1.2 })
ui:SetLook({})
ui:CloseMenu()

-- Selects -------------------------------------------------------------------------------

local _, body = testWindow(ui, 600, 700)
local ROUTE = {
    { value = "cheap", caption = "Cheapest" },
    { value = "few", caption = "Fewest steps" },
    { separator = true },
    { value = "fast", caption = "Fastest", disabled = true, reason = "Needs a mount." },
}
local changes, heard, heardWidget = 0, nil, nil
local select = body:Select{ label = "Route by", options = ROUTE, value = "few", default = "cheap",
    onChange = function(value, w) changes = changes + 1; heard, heardWidget = value, w end }
layout()
assertTrue(select.button:GetText() == "Fewest steps" and select.label:IsShown(), "a select shows its caption and label")
assertTrue(select.reset:IsShown() and select.kitStored, "not the default: the reset and accent edge show")
assertTrue(select.kitPW == 170 + 40 and select.kitPH == 24 + 16, "sized for its button, label and reset: "
    .. select.kitPW .. " x " .. select.kitPH)
assertTrue(select.button.kitPW == 170, "the button is 170 wide")

-- Hover on the button: colours only.
fonts = 0
local labelFont = select.label.SetFont
select.label.SetFont = function(...) fonts = fonts + 1; return labelFont(...) end
select.button:GetScript("OnEnter")(select.button)
select.button:GetScript("OnLeave")(select.button)
select.label.SetFont = nil
assertTrue(fonts == 0, "hovering a select sets no font")

select.button:Click()
assertTrue(ui:MenuOpenFor(select.button) and select:IsOpen(), "a click opens its menu")
assertTrue(rowFor(menu, "Fewest steps").current, "with its value marked")
rowFor(menu, "Cheapest"):Click()
assertTrue(select:GetValue() == "cheap" and changes == 1 and heard == "cheap" and heardWidget == select,
    "a choice calls onChange(value, w)")
assertTrue(not select:IsOpen() and not select.reset:IsShown(), "closed; the default again: no reset")
select:SetValue("few")
assertTrue(changes == 1 and select.button:GetText() == "Fewest steps" and select.reset:IsShown(), "SetValue from code is silent")
select:Reset()
assertTrue(select:GetValue() == "cheap" and changes == 2 and heard == "cheap", "Reset shows the default and says so")
select:SetValue("few")
select.reset:Click()
assertTrue(select:GetValue() == "cheap" and changes == 3, "the reset link resets")
select:SetOptions({ { value = "cheap", caption = "Cheap" }, { value = "new", caption = "New" } })
assertTrue(select.button:GetText() == "Cheap", "new options, new caption")
select:SetEnabled(false, "Plan first.")
assertTrue(not select:IsEnabled() and select.button.kitReason == "Plan first.", "disabled with a reason")
select:SetEnabled(true)

-- Placeholder, and no default: no reset.
local empty = body:Select{ options = ROUTE, placeholder = "Pick one" }
assertTrue(empty.button:GetText() == "Pick one" and not empty.label:IsShown() and not empty.reset, "a placeholder, no label, no reset")
empty:Reset()
assertTrue(empty:GetValue() == nil, "Reset with no default does nothing")

-- Bound to the addon's table.
local db = {}
changes = 0
local bound = body:Select{ bind = { db, "routeBy" }, options = ROUTE, default = "cheap",
    onChange = function(value) changes = changes + 1; heard = value end }
assertTrue(bound:GetValue() == "cheap" and not bound:IsStored() and not bound.reset:IsShown(), "bound: the default, nothing stored")
bound.button:Click()
rowFor(menu, "Fewest steps"):Click()
assertTrue(db.routeBy == "few" and bound:IsStored() and bound.reset:IsShown() and changes == 1, "a choice writes the table")
bound:SetValue("cheap")
assertTrue(db.routeBy == "few" and changes == 1, "SetValue leaves the table and onChange alone")
bound:Reset()
assertTrue(db.routeBy == nil and bound:GetValue() == "cheap" and not bound.reset:IsShown() and changes == 2,
    "Reset forgets the choice")
bound.button:Click()
rowFor(menu, "Cheapest"):Click()
assertTrue(db.routeBy == nil and changes == 2 and not bound.reset:IsShown(), "choosing the value already shown changes nothing")
db.routeBy = "few"
local fromTable = body:Select{ bind = { db, "routeBy" }, options = ROUTE, value = "cheap", default = "cheap" }
assertTrue(fromTable:GetValue() == "few" and fromTable.reset:IsShown(), "the table's value wins over spec.value")

-- SearchSelect: a filter box on its menu.
local zones = {}
for index = 1, 30 do zones[index] = { value = index, caption = "Zone " .. index } end
local zone
local search = body:SearchSelect{ label = "Zone", options = zones, value = 4, onChange = function(value) zone = value end }
assertTrue(search.button:GetText() == "Zone 4", "a search select shows its value")
search.button:Click()
assertTrue(menu.search:IsShown() and menu.count == 30, "its menu has a filter")
menu.search:SetText("Zone 2")
menu.search.scripts.OnTextChanged(menu.search, true)
assertTrue(menu.count == 1 + 10, "the filter narrows it: " .. menu.count)
rowFor(menu, "Zone 21"):Click()
assertTrue(zone == 21 and search:GetValue() == 21, "a filtered choice")

-- MultiSelect: checks, All and None.
local SOURCES = {
    { header = "Buy" },
    { value = "vendor", caption = "Vendor" },
    { value = "ah", caption = "Auction house" },
    { header = "Make" },
    { value = "craft", caption = "Craft" },
    { value = "farm", caption = "Farm", disabled = true, reason = "Not yet." },
}
local sets, lastSet = 0, nil
local multi = body:MultiSelect{ label = "Sources", options = SOURCES, value = { vendor = true, ah = true },
    onChange = function(set, w) sets = sets + 1; lastSet = set; assertTrue(w, "onChange gets the widget") end }
assertTrue(multi.button:GetText() == "Vendor, Auction house", "a multi select names what is chosen")
multi.button:Click()
local craft = rowFor(menu, "Craft")
assertTrue(craft.item.check and not craft.item.value and rowFor(menu, "Vendor").item.value, "its options are checks")
craft:Click()
assertTrue(sets == 1 and lastSet.craft and multi:GetValue().craft and menu:IsShown(), "a check changes the set; open still")
rowFor(menu, "None"):Click()
assertTrue(sets == 2 and next(lastSet) == nil and multi.button:GetText() == "None", "None empties it")
assertTrue(not rowFor(menu, "Vendor").item.value and not rowFor(menu, "Vendor").check.lines[1].shown,
    "and the open menu shows it")
rowFor(menu, "All"):Click()
assertTrue(sets == 3 and lastSet.vendor and lastSet.ah and lastSet.craft and not lastSet.farm, "All takes every enabled one")
assertTrue(rowFor(menu, "Craft").item.value and menu.count == 9, "the open menu shows it, nothing added")
lastSet.vendor = nil
assertTrue(multi:GetValue().vendor, "onChange's set is a copy")
ui:CloseMenu()
assertTrue(not multi:IsOpen(), "closed")
multi:SetValue({ farm = true })
assertTrue(sets == 3 and multi.button:GetText() == "Farm", "SetValue from code is silent")
multi:SetValue({ vendor = true, ah = true, craft = true, farm = true })
assertTrue(multi.button:GetText() == "All", "every option: All")

-- A bound MultiSelect with a default.
local mdb = {}
local mbound = body:MultiSelect{ bind = { mdb, "sources" }, options = SOURCES, default = { vendor = true } }
assertTrue(mbound:GetValue().vendor and not mbound.reset:IsShown(), "bound multi: the default")
mbound.button:Click()
rowFor(menu, "Craft"):Click()
assertTrue(mdb.sources and mdb.sources.craft and mdb.sources.vendor and mbound.reset:IsShown(), "a check writes the table")
ui:CloseMenu()
mbound:Reset()
assertTrue(mdb.sources == nil and not mbound:GetValue().craft and mbound:GetValue().vendor and not mbound.reset:IsShown(),
    "Reset forgets it")

-- Placed by the caller.
local placed = ui:Select(UIParent, { options = ROUTE, value = "cheap", boxWidth = 120 })
layout()
assertTrue(placed.kitPW == 120 and placed.button.kitPW == 120, "a placed select is its box width")

-- Stretched by its column: the button takes the room left of the reset.
local wide = body:Select{ options = ROUTE, value = "few", default = "cheap", stretch = true }
layout()
assertTrue(wide.button.kitPW == wide.kitPW - 40, "stretched, the button fills it but for the reset")

-- An open select's menu closes when the select goes back to the pool.
select.button:Click()
assertTrue(ui:MenuOpenFor(select.button), "open")
select:Release()
assertTrue(not menu:IsShown() and select.kitPooled, "released: its menu closes")

-- Cleared and built again from the pool with other options ---------------------------------

body:Clear()
layout()
local function build(round)
    local list = {}
    for index = 1, 4 do
        if round == 1 then
            list[#list + 1] = body:Select{ label = "L" .. index, options = ROUTE, value = "few", default = "cheap",
                disabled = index == 2 and "No." or nil }
            list[#list + 1] = body:MultiSelect{ label = "M" .. index, options = SOURCES, value = { vendor = true },
                default = {} }
            list[#list + 1] = body:SearchSelect{ options = zones, value = 1, default = 2 }
        else
            list[#list + 1] = body:Select{ options = { { value = "a", caption = "Alpha" } }, value = "a" }
            list[#list + 1] = body:MultiSelect{ options = { { value = "x", caption = "Ex" } } }
            list[#list + 1] = body:SearchSelect{ options = zones }
        end
    end
    return list
end
local first = build(1)
layout()
first[1].button:Click()
assertTrue(first[1]:IsOpen(), "a select from round one is open")
made = #objects
body:Clear()
layout()
local second = build(2)
layout()
assertTrue(#objects == made, "selects rebuilt from the pool make no frames: " .. (#objects - made) .. " new")
assertTrue(not menu:IsShown(), "clearing closed the open menu")
for _, w in ipairs(second) do
    assertTrue(not w.label:IsShown() and not w.reset:IsShown() and not w.kitStored and not w:IsOpen(),
        "no label, reset, edge or open state left from the last use")
    assertTrue(w:IsEnabled() and w.button.kitReason == nil, "enabled again")
    assertTrue(w.kitPH == 24 and w.kitPW == 170, "sized for the new spec: " .. w.kitPW .. " x " .. w.kitPH)
end
assertTrue(second[1]:GetValue() == nil or second[1]:GetValue() == "a", "a select takes its new value")
local s1 = second[1].kitType == "Select" and second[1] or nil
for _, w in ipairs(second) do
    if w.kitType == "Select" then s1 = w end
end
assertTrue(s1:GetValue() == "a" and s1.button:GetText() == "Alpha", "the new options and value")
local m1
for _, w in ipairs(second) do if w.kitType == "MultiSelect" then m1 = w end end
assertTrue(next(m1:GetValue()) == nil and m1.button:GetText() == "None", "a multi select from the pool starts empty")
m1.button:Click()
assertTrue(menu.count == 4 and rowFor(menu, "Ex"), "its menu has the new options, All and None")
ui:CloseMenu()
local ss
for _, w in ipairs(second) do if w.kitType == "SearchSelect" then ss = w end end
ss.button:Click()
assertTrue(menu.search:IsShown(), "a search select from the pool still searches")
ui:CloseMenu()
