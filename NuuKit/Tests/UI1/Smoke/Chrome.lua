-- Windows, panels, tabs and disclosures.

local ctx = ...
local UI, ui, assertTrue, layout, objects, Object, tick = ctx.UI, ctx.ui, ctx.assertTrue, ctx.layout, ctx.objects,
    ctx.Object, ctx.tick

-- Colours are kept where the test can read them.
local oldColorTexture = rawget(Object, "SetColorTexture")
function Object:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
local function sameColor(texture, color)
    local c = texture.color
    if not color then return c ~= nil and c[4] == 0 end
    return c ~= nil and math.abs(c[1] - color[1]) < 1e-6 and math.abs(c[2] - color[2]) < 1e-6
        and math.abs(c[4] - (color[4] or 1)) < 1e-6
end
local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- Moving and sizing follow the cursor's whole travel since the press, not
-- its motion frame by frame: a frame skipped loses nothing.
local function drag(handle, fromX, fromY, toX, toY)
    _G.GetCursorPosition = function() return fromX, fromY end
    handle:Fire("OnMouseDown", "LeftButton")
    local driver = handle.kitDragDriver
    if not driver.shown then return false end
    _G.GetCursorPosition = function() return toX, toY end
    driver.scripts.OnUpdate(driver, 0.016)
    handle:Fire("OnMouseUp", "LeftButton")
    assertTrue(not driver.shown, "letting go ends the drag")
    _G.GetCursorPosition = function() return 300, 300 end
    return true
end

-- A window with every option ----------------------------------------------------------

local place = {}
local folds = {}
local win
win = ui:Window({ key = "main", place = place, title = "Planner", subtitle = "tailoring",
    width = 900.4, height = 640, resizable = true, minWidth = 700, minHeight = 460, collapsible = true,
    onCollapse = function(collapsed, w) folds[#folds + 1] = collapsed; assertTrue(w == win, "onCollapse gets the window") end,
    status = "What a change did shows here, with Undo." })
layout()
assertTrue(win.kitIsWindow and win.kitInner == win.body and win.body.kitFillChildren and win.body.kitWindow == win,
    "a window is a holder of its body")
assertTrue(win:GetWidth() == 900 and win:GetHeight() == 640, "made on whole pixels: " .. win:GetWidth())
assertTrue(contains(UISpecialFrames, "TestChrome_main_Window"), "Escape closes it")
assertTrue(win.closeButton and win.collapseButton and win.grip and win.header, "close, fold, grip and header")
assertTrue(win.title:GetText() == "Planner" and win.subtitle:GetText() == "tailoring", "title and subtitle")
win:SetTitle("Tailoring planner")
win:SetSubtitle(nil)
assertTrue(win.title:GetText() == "Tailoring planner" and win.subtitle:GetText() == "", "SetTitle, SetSubtitle")
assertTrue(win.statusStrip and win.statusStrip:IsShown() and win.statusStrip.text:GetText():match("^What"),
    "a window made with status keeps its strip, with the hint")

-- The header row takes the addon's own controls.
local headerButton = win.header:Button{ "Options" }
win.header:SetWidth(300)
layout()
assertTrue(headerButton.kitParent == win.header and headerButton.kitPW > 0, "the header lays out its controls")
assertTrue(UI.WindowOf(headerButton) == win, "a header control is in the window")

-- Tabs made straight on the window fill its body.
local changes = {}
local tabs, ways
tabs = win:Tabs{
    { key = "plan", caption = "Plan" },
    { key = "shop", caption = "Shopping", badge = 3 },
    { key = "log", caption = "Log", disabled = true },
    value = "shop", pagePadding = 12,
    onChange = function(key, t) changes[#changes + 1] = key; assertTrue(t == tabs, "onChange gets the tabs") end,
}
local planText = tabs:Page("plan"):Text{ "Linen Cloth" }
local shopText = tabs:Page("shop"):Text{ "Buy 40 Linen Cloth", wrap = true }
ways = tabs:Page("shop"):Disclosure{ "Ways around", open = false,
    onToggle = function(open, d) changes[#changes + 1] = open and "open" or "shut"; assertTrue(d == ways, "onToggle gets it") end }
layout()
local bodyHeight = 640 - 1 - 30 - 24 - 1
assertTrue(tabs.kitParent == win.body and tabs.kitPH == bodyHeight, "the tabs fill the body: " .. tostring(tabs.kitPH))
local shopPage = tabs:Page("shop")
assertTrue(shopPage:IsShown() and not tabs:Page("plan"):IsShown(), "the chosen page shows, the others hide")
assertTrue(shopPage.kitPH == bodyHeight - 30, "a page fills under the strip: " .. tostring(shopPage.kitPH))
assertTrue(shopText.kitPX == 12 and shopText.kitPW == 900 - 2 - 24, "pagePadding pads a page")
assertTrue(tabs:GetValue() == "shop" and tabs:GetSelected() == "shop", "value chooses the first tab")
assertTrue(#changes == 0, "nothing heard while it is made")

-- Badges.
local shopTab, planTab, logTab = tabs.kitTabs.shop, tabs.kitTabs.plan, tabs.kitTabs.log
assertTrue(shopTab.badge:IsShown() and shopTab.badge:GetText() == "3", "a badge from the spec")
assertTrue(not planTab.badge:IsShown(), "no badge without one")
local planWidth = planTab.kitPW
tabs:SetBadge("plan", 12)
layout()
assertTrue(planTab.badge:IsShown() and planTab.kitPW > planWidth, "a new badge widens its tab")
tabs:SetBadge("plan", nil)
layout()
assertTrue(not planTab.badge:IsShown() and planTab.kitPW == planWidth, "and taking it away narrows it")

-- Chosen from code: never heard.
tabs:Select("plan")
assertTrue(tabs:GetValue() == "plan" and tabs:Page("plan"):IsShown() and not shopPage:IsShown(), "Select")
tabs:SetValue("shop")
assertTrue(tabs:GetValue() == "shop" and #changes == 0, "SetValue, silent")
layout()

-- Chosen by the player: heard.
planTab:Click()
assertTrue(tabs:GetValue() == "plan" and changes[1] == "plan", "a click chooses and is heard")
planTab:Click()
assertTrue(#changes == 1, "the chosen tab again changes nothing")
logTab:Click()
assertTrue(tabs:GetValue() == "plan" and #changes == 1, "a disabled tab cannot be chosen")

-- Hover paints colours only.
layout()
local fonts = 0
local setFont = shopTab.label.SetFont
shopTab.label.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
shopTab:GetScript("OnEnter")(shopTab)
assertTrue(shopTab.hover, "hover")
shopTab:GetScript("OnLeave")(shopTab)
assertTrue(fonts == 0 and UI.LayoutSettled(), "tab hover sets no font and lays nothing out")
shopTab.label.SetFont = nil

-- Full keyboard control: arrows move between tabs that can be chosen.
win:TakeKeyboard(true)
UI.FocusWidget(win, planTab)
win:Fire("OnKeyDown", "RIGHT")
assertTrue(tabs:GetValue() == "shop" and changes[2] == "shop" and win.kitFocused == shopTab, "an arrow chooses the next tab")
win:Fire("OnKeyDown", "RIGHT")
assertTrue(tabs:GetValue() == "plan" and win.kitFocused == planTab, "past a disabled one: " .. tostring(tabs:GetValue()))
win:Fire("OnKeyDown", "LEFT")
assertTrue(tabs:GetValue() == "shop", "left goes back")
tabs:SetTabEnabled("log", true)
win:Fire("OnKeyDown", "RIGHT")
assertTrue(tabs:GetValue() == "log", "an enabled tab is reached")
win:Fire("OnKeyDown", "TAB")
assertTrue(win.kitFocused and win.kitFocused ~= logTab, "Tab moves the focus")
tabs:Select("shop")
layout()

-- Tab order.
win:TabOrder({ ways, headerButton })
local order = UI.FocusOrder(win)
assertTrue(order[1] == ways and order[2] == headerButton and #order == 2, "TabOrder replaces the order")
win:TabOrder(nil)
assertTrue(#UI.FocusOrder(win) > 2, "and nil puts it back")

-- Escape under full keyboard control closes it; Toggle opens it laid out.
win:Fire("OnKeyDown", "ESCAPE")
assertTrue(not win:IsShown(), "Escape closes it")
win:TakeKeyboard(false)
assertTrue(win.kitFocused == nil, "giving the keyboard back drops the focus")
local late = win:Text{ "Made while it was shut" }
win:Toggle()
assertTrue(win:IsShown() and UI.LayoutSettled() and late.kitPW ~= nil, "a window shows laid out, never a frame late")
win:Toggle()
assertTrue(not win:IsShown(), "Toggle shuts it")
win:Toggle()
late:Release()
layout()
-- With a spec, Toggle is the maker, as on any holder (when Forms is loaded).
if UI.Makers.Toggle then
    local sellBack = win:Toggle{ "Sell back" }
    assertTrue(win:IsShown() and sellBack.kitParent == win.body, "win:Toggle{ ... } makes a toggle in the body")
    sellBack:Release()
    layout()
end

-- Disclosure.
assertTrue(not ways:IsOpen() and ways.foldedGlyph.lines[1].shown and not ways.openGlyph.lines[1].shown,
    "folded: the chevron points right")
assertTrue(math.abs(ways.foldedGlyph.dx - (-ways.kitPW / 2 + 12)) < 1e-6, "the chevron sits at the left")
ways:Click()
assertTrue(ways:IsOpen() and ways:IsActive() and changes[#changes] == "open", "a click opens it and is heard")
ways:SetOpen(false)
assertTrue(not ways:IsOpen() and changes[#changes] == "open", "SetOpen from code is not heard")
local waysWidth = ways.kitPW
assertTrue(waysWidth >= UI.StringWidth(ways.label) + 34, "room for the chevron: " .. tostring(waysWidth))

-- Status: a message with Undo, then the hint again; the body keeps its size.
do
    local strip = win.statusStrip
    local bottom = win.body.points[2][5]
    local undone = 0
    win:Status("Guide reset.", { undo = function() undone = undone + 1 end })
    assertTrue(strip:IsShown() and strip.text:GetText() == "Guide reset." and strip.undo:IsShown(), "a message with Undo")
    assertTrue(win.body.points[2][5] == bottom, "a message leaves the body alone")
    strip.undo:Click()
    assertTrue(undone == 1 and not strip.undo:IsShown(), "Undo undoes, once")
    win:Status("Saved.")
    assertTrue(not strip.undo:IsShown(), "no Undo without one")
    win:Status(nil)
    assertTrue(strip:IsShown() and strip.text:GetText():match("^What") and win.body.points[2][5] == bottom,
        "clearing it shows the hint")

    local plain = ui:Window({ title = "Plain" })
    local plainBottom = plain.body.points[2][5]
    plain:Status("Saved.")
    assertTrue(plain.statusStrip:IsShown() and plain.body.points[2][5] > plainBottom, "a plain window shows a message")
    plain:Status(nil)
    assertTrue(not plain.statusStrip:IsShown() and plain.body.points[2][5] == plainBottom, "and puts the strip away after")
    assertTrue(not contains(UISpecialFrames, "TestChrome__Window"), "a window without a key has no name")
    plain.closeButton:Click()
    assertTrue(not plain:IsShown(), "the close mark shuts it")
end

-- Moving, sizing, locking; the place is kept. The stand-in's frames are
-- always at 100, 500; this one answers where it was put.
local function placedAt(frame)
    frame.GetLeft = function(self)
        local q = self.points[1]
        return (q and q[1] == "TOPLEFT" and q[3] == "BOTTOMLEFT") and q[4] or 100
    end
    frame.GetTop = function(self)
        local q = self.points[1]
        return (q and q[1] == "TOPLEFT" and q[3] == "BOTTOMLEFT") and q[5] or 500
    end
end
placedAt(win)
-- It opened pinned by its top left; the move is from there.
local x0, y0 = win:GetLeft(), win:GetTop()
assertTrue(drag(win.band, 300, 300, 340, 280), "a press on the band starts a move")
local point = win.points[1]
assertTrue(point[1] == "TOPLEFT" and point[4] == x0 + 40 and point[5] == y0 - 20,
    "the window moves by the cursor's travel: " .. tostring(point[4]) .. ", " .. tostring(point[5]))
assertTrue(place.main and place.main.x == x0 + 40 and place.main.y == y0 - 20, "and its place is kept")
win:SetLocked(true)
assertTrue(not drag(win.band, 300, 300, 400, 400), "a locked window does not move")
win:SetLocked(false)
local widthBefore, heightBefore = win:GetWidth(), win:GetHeight()
assertTrue(drag(win.grip, 300, 300, 330, 250), "a press on the grip starts sizing")
assertTrue(win:GetWidth() == widthBefore + 30 and win:GetHeight() == heightBefore + 50,
    "the grip sizes by the cursor's travel: " .. win:GetWidth() .. " x " .. win:GetHeight())
drag(win.grip, 300, 300, -5000, 5000)
assertTrue(win:GetWidth() == 700 and win:GetHeight() == 460, "and holds to the window's bounds")
drag(win.grip, 300, 300, 9000, -9000)
assertTrue(win:GetWidth() == 2000 and win:GetHeight() == 2000, "both ways")
drag(win.grip, 300, 300, -5000, 5000)
assertTrue(place.main.w == 700 and place.main.h == 460, "the size is kept")
layout()
assertTrue(tabs.kitPH == 460 - 1 - 30 - 24 - 1, "the body follows the window's size: " .. tostring(tabs.kitPH))

-- Grip hover: colours only.
win.grip:GetScript("OnEnter")(win.grip)
assertTrue(sameColor(win.grip.glyph.lines[1], ui.tokens.accent), "the grip lights on hover")
win.grip:GetScript("OnLeave")(win.grip)
assertTrue(sameColor(win.grip.glyph.lines[1], ui.tokens.muted), "and dims after")

-- Collapse: by the player (heard), by code (not).
win.collapseButton:Click()
assertTrue(win:IsCollapsed() and win:GetHeight() == 32 and not win.body:IsShown(), "folded to its band")
assertTrue(not win.statusStrip:IsShown() and not win.grip:IsShown(), "no status or grip while folded")
assertTrue(win.collapseButton.glyph.kind == "down", "the fold mark points down")
assertTrue(folds[1] == true and place.main.collapsed and place.main.h == 460, "heard, and kept with the open size")
win:SetCollapsed(false)
assertTrue(not win:IsCollapsed() and win:GetHeight() == 460 and win.body:IsShown() and win.statusStrip:IsShown(),
    "unfolded to its size")
assertTrue(#folds == 1 and place.main.collapsed == nil and win.collapseButton.glyph.kind == "up", "code is not heard")

-- A window made again where it was kept.
do
    local kept = { again = { x = 140, y = 480, w = 720, h = 500, collapsed = true } }
    local oldLeft, oldTop = rawget(Object, "GetLeft"), rawget(Object, "GetTop")
    placedAt(Object)
    local again = ui:Window({ key = "again", place = kept, resizable = true, collapsible = true, width = 400, height = 300 })
    local p = again.points[1]
    assertTrue(p[1] == "TOPLEFT" and p[4] == 140 and p[5] == 480, "it opens where it was")
    assertTrue(again:GetWidth() == 720 and again:IsCollapsed() and again.kitExpandedHeight == 500, "its size and fold")
    again:SetCollapsed(false)
    assertTrue(again:GetHeight() == 500, "unfolds to the kept size")
    assertTrue(kept.again.x == 140 and kept.again.collapsed == nil, "and keeps that")
    Object.GetLeft, Object.GetTop = oldLeft, oldTop
    local hidden = ui:Window({ key = "hidden", hidden = true, close = false, escape = false })
    assertTrue(not hidden:IsShown() and not hidden.closeButton and not contains(UISpecialFrames, "TestChrome_hidden_Window"),
        "hidden, no close mark, no Escape")
    again:Hide()
end

-- Panels -------------------------------------------------------------------------------

local panel = ui:Panel({ key = "tracker", title = "Northshire Valley", width = 340, height = 180,
    resizable = "width", collapsible = true, point = { "RIGHT", UIParent, "RIGHT", -80, 0 } })
local steps = panel:Column{ padding = 10, gap = 4 }
steps:Text{ "Kill Kobold Vermin 6/10", color = "warning" }
layout()
assertTrue(panel.kitInPlay and not panel.closeButton and panel.collapseButton, "a panel folds but has no close mark")
assertTrue(not contains(UISpecialFrames, "TestChrome_tracker_Window"), "Escape leaves a panel be")
assertTrue(steps.kitParent == panel.body and steps.kitPH == 180 - 2 - 30, "a column made on it fills it")
assertTrue(sameColor(panel.bandBg, nil), "a panel's band is bare")
fonts = 0
setFont = panel.title.SetFont
panel.title.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
panel.band:GetScript("OnEnter")(panel.band)
assertTrue(sameColor(panel.bandBg, ui.tokens.raisedBg), "until the cursor is on it")
panel.band:GetScript("OnLeave")(panel.band)
assertTrue(sameColor(panel.bandBg, nil) and fonts == 0, "band hover paints colours only")
panel.title.SetFont = nil
local panelHeight = panel:GetHeight()
drag(panel.grip, 300, 300, 340, 200)
assertTrue(panel:GetWidth() == 380 and panel:GetHeight() == panelHeight, "a width grip sizes the width only")
local bare = ui:Panel({ width = 200, height = 100 })
assertTrue(not bare.band:IsShown() and bare.body.points[1][5] == -1, "no title, no fold: no band")
bare:Hide()

-- A look change repaints every window ------------------------------------------------

ui:SetLook({ theme = "horde" })
layout()
assertTrue(win.nine and win.nine.loaded and win.kitInset == 17, "an art theme frames the window")
assertTrue(win.bg:IsShown() and win.kitBanded, "with its tiled background and band")
assertTrue(win.body.points[1][4] == 17 and win.body.points[1][5] == -47, "the body inside the frame")
assertTrue(panel.nine == nil and panel.kitInset == 1 and not panel.bg:IsShown(), "a panel stays flat")
assertTrue(tabs.kitPH == 460 - 17 - 30 - 24 - 17, "the body laid out again: " .. tostring(tabs.kitPH))
ui:SetLook({ theme = "midnight" })
layout()
assertTrue(win.kitInset == 1 and not win.bg:IsShown() and not win.nine.pieces[1].shown, "back to flat")
assertTrue(sameColor(win.bandBg, ui.tokens.bandBg) and sameColor(win.plate.fill, ui.tokens.windowBg), "flat colours")
assertTrue(tabs.kitPH == 460 - 1 - 30 - 24 - 1, "and the body again")

-- A body cleared and built again from the pool ----------------------------------------

do
    local pool = ui:Window({ key = "pool", width = 600, height = 500, padding = 8, gap = 6 })
    local heard, toggled
    local function build(round)
        pool:Text{ "Round " .. round, style = "heading" }
        local list = round == 1 and {
            { key = "a", caption = "Alpha" }, { key = "b", caption = "Beta", badge = 2, disabled = true },
            { key = "c", caption = "Gamma" }, value = "c",
        } or { { key = "x", caption = "Ex" }, { key = "y", caption = "Why" } }
        list.onChange = function(key) heard = round .. ":" .. key end
        list.pagePadding = round == 1 and 4 or 0
        local t = pool:Tabs(list)
        for _, entry in ipairs(list) do
            t:Page(entry.key):Text{ entry.caption .. " page, round " .. round }
        end
        t:Page(list[1].key):Disclosure{ "More", open = round == 1, onToggle = function(open) toggled = round .. ":" .. tostring(open) end }
        return t
    end
    local first = build(1)
    layout()
    assertTrue(first:GetValue() == "c" and not first.kitTabs.b:IsEnabled() and first.kitTabs.b.badge:IsShown(), "round one")
    local made = #objects
    pool:Clear()
    layout()
    assertTrue(#pool.body.kitChildren == 0, "the window's body is cleared")
    local second = build(2)
    layout()
    assertTrue(second == first, "the tabs come from the pool")
    assertTrue(#objects == made, "a rebuild takes every frame from the pools: " .. (#objects - made) .. " new")
    assertTrue(second:GetValue() == "x" and #second.strip.kitChildren == 2, "the new tabs, the first chosen")
    local y = second.kitTabs.y
    assertTrue(y:IsEnabled() and not y.badge:IsShown() and not y.kitSelected, "no old badge, disable or choice")
    assertTrue(first.kitTabFrames[3].kitPooled and not first.kitTabFrames[3]:IsShown(), "the unused tab waits")
    for _, w in ipairs(UI.FocusOrder(pool)) do assertTrue(not w.kitPooled, "no waiting tab in the focus order") end
    assertTrue(#second:Page("x").kitChildren == 2 and #second:Page("y").kitChildren == 1, "each page holds only this round's")
    assertTrue(second:Page("x").kitPadding == 0, "the new page padding")
    y:Click()
    assertTrue(heard == "2:y", "the new onChange: " .. tostring(heard))
    local more = second:Page("x").kitChildren[2]
    assertTrue(not more:IsOpen() and not more:IsActive(), "a disclosure from the pool takes the new open state")
    more:Click()
    assertTrue(toggled == "2:true", "and the new onToggle")
    pool:Clear()
    build(1)
    layout()
    assertTrue(#objects == made, "round one again makes nothing new: " .. (#objects - made) .. " new")
    pool:Hide()
end

-- Whole pixels at a fractional scale ------------------------------------------------------

do
    -- On a 1440p screen: a pixel is the effective scale times 1440 / 768.
    local effective = 0.71
    local scale = effective * 1440 / 768
    local oldScale = Object.GetEffectiveScale
    Object.GetEffectiveScale = function() return effective end
    _G.GetPhysicalScreenSize = function() return 2560, 1440 end
    local function whole(v) return v == 0.01 or math.abs(v * scale - math.floor(v * scale + 0.5)) < 1e-6 end
    win:SetSize(811.3, 553.7)
    UI.PixelScaleChanged()
    UI.LayoutNow()
    assertTrue(whole(win:GetWidth()) and whole(win:GetHeight()), "the window settles on whole pixels: " .. win:GetWidth())
    local p = win.points[1]
    assertTrue(p[1] == "TOPLEFT" and whole(p[4]) and whole(p[5]), "and is placed on them")
    -- The window's own parts, with and without a status line: the body they
    -- hold must start on the grid for the snapped layout to land on it.
    for _, text in ipairs({ "Saved.", false }) do
        win:Status(text or nil)
        for _, part in ipairs({ win.body, win.band, win.statusStrip }) do
            for _, q in ipairs(part.points) do
                if type(q[4]) == "number" then
                    assertTrue(whole(q[4]) and whole(q[5]), "window parts on whole pixels: " .. q[1] .. " " .. q[4] .. ", " .. q[5])
                end
            end
        end
    end
    UI.LayoutNow()
    local checked = 0
    for _, o in ipairs(objects) do
        local q = o.points[1]
        if o.kitParent and q and q[1] == "TOPLEFT" and type(q[4]) == "number" and o.shown and UI.WindowOf(o) == win then
            assertTrue(whole(q[4]) and whole(q[5]) and whole(o.width) and whole(o.height),
                "laid out on whole pixels: " .. q[4] .. ", " .. q[5] .. " " .. o.width .. " x " .. o.height)
            checked = checked + 1
        end
    end
    assertTrue(checked >= 8, "the pixel check saw the layout: " .. checked)
    assertTrue(math.abs(win.statusStrip.line.height * scale - 1) < 1e-6, "the status hairline is one pixel")
    Object.GetEffectiveScale = oldScale
    _G.GetPhysicalScreenSize = nil
    UI.PixelScaleChanged()
    win:SetSize(900, 640)
    UI.LayoutNow()
end

tick()
rawset(Object, "SetColorTexture", oldColorTexture)

-- A window opened centred on a screen whose size is no whole number of
-- pixels still starts on whole pixels: it is pinned by its top left before
-- the client knows where it is.
do
    local scale = 0.64 * 2071 / 768
    local oldScale = ctx.Object.GetEffectiveScale
    ctx.Object.GetEffectiveScale = function() return 0.64 end
    _G.GetPhysicalScreenSize = function() return 3840, 2071 end
    UI.PixelScaleChanged()
    UIParent:SetSize(3840 / scale, 2071 / scale)
    local centred = ui:Window({ width = 900, height = 640 })
    local p = centred.points[1]
    local function whole(v) return math.abs(v * scale - math.floor(v * scale + 0.5)) < 1e-6 end
    assertTrue(p[1] == "TOPLEFT" and whole(p[4]) and whole(p[5]), "a centred window starts on whole pixels: " .. tostring(p[4]) .. ", " .. tostring(p[5]))
    centred:Show()
    local mark = centred.closeButton.points[1]
    assertTrue(mark[1] == "TOPRIGHT" and whole(mark[4]) and whole(mark[5]) and whole(centred.closeButton.width),
        "the close mark sits on whole pixels in the band: " .. tostring(mark[4]) .. ", " .. tostring(mark[5]))
    local header = centred.header
    assertTrue(whole(header.width) and whole(header.height) and whole(header.points[1][4]),
        "the header row sits on whole pixels: " .. tostring(header.width) .. " x " .. tostring(header.height))
    ctx.Object.GetEffectiveScale = oldScale
    _G.GetPhysicalScreenSize = nil
    UI.PixelScaleChanged()
    centred:Hide()
end
