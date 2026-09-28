-- Layout on whole pixels, and cards.

local ctx = ...
local Kit, UI, g, objects, Object, tick, find, show, assertTrue =
    ctx.Kit, ctx.UI, ctx.g, ctx.objects, ctx.Object, ctx.tick, ctx.find, ctx.show, ctx.assertTrue

-- At a UI scale that is no whole number, every place and size the layout
-- sets is still whole screen pixels, so 1 pixel edges draw 1 pixel wide.
do
    -- On a 1440p screen: a pixel is the effective scale times 1440 / 768.
    local effective = 0.71
    local scale = effective * 1440 / 768
    local oldScale = Object.GetEffectiveScale
    Object.GetEffectiveScale = function() return effective end
    _G.GetPhysicalScreenSize = function() return 2560, 1440 end
    local function whole(v) return v == 0.01 or math.abs(v * scale - math.floor(v * scale + 0.5)) < 1e-6 end
    g.win:SetSize(811.3, 553.7)
    for _, o in ipairs(objects) do if o.kitChildren then UI.Invalidate(o) end end
    UI.LayoutNow()
    local checked = 0
    for _, o in ipairs(objects) do
        local p = o.points[1]
        if o.kitParentContainer and p and p[1] == "TOPLEFT" and type(p[4]) == "number" and o.shown then
            assertTrue(whole(p[4]) and whole(p[5]) and whole(o.width) and whole(o.height),
                "laid out on whole pixels: " .. p[4] .. ", " .. p[5] .. " " .. o.width .. " x " .. o.height)
            checked = checked + 1
        end
    end
    assertTrue(checked > 50, "the pixel check saw the layout: " .. checked)
    -- Every plate edge is one screen pixel once the scale change is heard.
    UI.PixelScaleChanged()
    local edges = 0
    for _, o in ipairs(objects) do
        local plate = type(o.plate) == "table" and o.plate.edges and o.plate
        if plate then
            assertTrue(math.abs(plate.edges.TOP.height * scale - 1) < 1e-6 and math.abs(plate.edges.LEFT.width * scale - 1) < 1e-6,
                "a plate edge is one pixel: " .. plate.edges.TOP.height * scale)
            edges = edges + 1
        end
    end
    assertTrue(edges > 30, "the edge check saw the plates: " .. edges)
    -- The window's own parts too, with and without a status line: the body
    -- they hold must start on the grid for the snapped layout to land on it.
    for _, text in ipairs({ "Saved.", false }) do
        g.win:Status(text or nil)
        for _, part in ipairs({ g.win.body, g.win.band, g.win.statusStrip }) do
            for _, p in ipairs(part.points) do
                if type(p[4]) == "number" then
                    assertTrue(whole(p[4]) and whole(p[5]), "window parts on whole pixels: " .. p[1] .. " " .. p[4] .. ", " .. p[5])
                end
            end
        end
    end
    Object.GetEffectiveScale = oldScale
    _G.GetPhysicalScreenSize = nil
    UI.PixelScaleChanged()
    g.win:SetSize(900, 640)
    for _, o in ipairs(objects) do if o.kitChildren then UI.Invalidate(o) end end
    UI.LayoutNow()
end

show("tables")

-- A card: what is made in it goes in its body, which tells the column
-- the card sits in when it changes.
local card = find(function(o) return o.rail and o.body and o.body.kitChildren and #o.body.kitChildren >= 4 end)
assertTrue(card and card.body.kitParentContainer == card.kitParentContainer, "a card's body reports to the card's container")
assertTrue(card:KitNaturalHeight(320) > 60, "a card is as tall as what it holds")
