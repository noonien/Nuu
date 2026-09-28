-- Windows and tabs.

local ctx = ...
local Kit, UI, g, objects, Object, tick, find, show, assertTrue =
    ctx.Kit, ctx.UI, ctx.g, ctx.objects, ctx.Object, ctx.tick, ctx.find, ctx.show, ctx.assertTrue

-- Moving and sizing follow the cursor's whole travel since the press, not
-- its motion frame by frame: a frame skipped loses nothing.
local function driverOf(handle)
    for _, o in ipairs(objects) do
        if o.parent == handle and o.scripts.OnUpdate and o.kind == "Frame" then return o end
    end
end
local function drag(handle, fromX, fromY, toX, toY)
    _G.GetCursorPosition = function() return fromX, fromY end
    handle:Fire("OnMouseDown", "LeftButton")
    local driver = driverOf(handle)
    assertTrue(driver and driver.shown, "a press on the handle starts the drag")
    _G.GetCursorPosition = function() return toX, toY end
    driver.scripts.OnUpdate(driver, 0.016)
    handle:Fire("OnMouseUp", "LeftButton")
    assertTrue(not driver.shown, "letting go ends it")
    _G.GetCursorPosition = function() return 300, 300 end
end
drag(g.win.band, 300, 300, 340, 280)
local point = g.win.points[1]
assertTrue(point[1] == "TOPLEFT" and point[4] == 140 and point[5] == 480,
    "the window moves by the cursor's travel: " .. tostring(point[4]) .. ", " .. tostring(point[5]))
local widthBefore, heightBefore = g.win:GetWidth(), g.win:GetHeight()
drag(g.win.grip, 300, 300, 330, 250)
assertTrue(g.win:GetWidth() == widthBefore + 30 and g.win:GetHeight() == heightBefore + 50,
    "the grip sizes by the cursor's travel: " .. g.win:GetWidth() .. " x " .. g.win:GetHeight())
drag(g.win.grip, 300, 300, -5000, 5000)
assertTrue(g.win:GetWidth() == 700 and g.win:GetHeight() == 460, "and holds to the window's bounds")
tick()

-- A window made with `status` keeps its strip: a message coming or going
-- leaves the body its size.
do
    local strip = g.win.statusStrip
    assertTrue(strip and strip.shown, "the gallery keeps its status strip")
    local body = g.win.body.points[2][5]
    g.win:Status("Guide reset.", { undo = function() end })
    assertTrue(strip.shown and g.win.body.points[2][5] == body, "a message leaves the body alone")
    g.win:Status(nil)
    assertTrue(strip.shown and strip.text.text ~= "" and g.win.body.points[2][5] == body, "and clearing it shows the hint")
    local plain = g.ui:Window({ title = "Plain" })
    plain:Status("Saved.")
    assertTrue(plain.statusStrip.shown, "a plain window shows a message")
    plain:Status(nil)
    assertTrue(not plain.statusStrip.shown, "and puts the strip away after")
    plain:Hide()
end

-- Walk every tab.
local tabs = ctx.tabs
assertTrue(tabs and tabs:GetHeight() > 300, "the tabs fill the window body: " .. tostring(tabs and tabs:GetHeight()))
assertTrue(g.win.body:GetWidth() > 0 or #g.win.body.points > 0, "the body is placed")
local placedButtons = 0
for _, o in ipairs(objects) do
    if o.kind == "Button" and o.kitParentContainer and #o.points > 0 and o.width > 0 then placedButtons = placedButtons + 1 end
end
assertTrue(placedButtons > 20, "containers lay their buttons out: " .. placedButtons)
for _, key in ipairs({ "controls", "lists", "tables", "inplay", "look" }) do
    tabs.tabs[key]:Click()
    tick()
end
