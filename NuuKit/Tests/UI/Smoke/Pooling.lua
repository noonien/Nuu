-- Pooling: a cleared screen built again makes no new frames, and every
-- widget made from the pool starts from its spec, not from its last use.

local ctx = ...
local UI, ui, assertTrue, testWindow, layout, objects = ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.objects

local _, body = testWindow(ui, 500, 900)
local clicked
local function build(round)
    for i = 1, 20 do
        local row = body:Row{ gap = 8 }
        row:Text{ "Item " .. i .. " round " .. round, grow = true }
        row:Button{ round == 1 and "+1" or "Add", tone = round == 1 and "accent" or nil,
            disabled = (round == 1 and i == 3) and "Not now" or nil,
            onClick = function() clicked = round .. ":" .. i end }
        local section = row:Section{ "S" .. i, foldable = round == 1, open = round ~= 1 }
        section:Text{ "inside " .. round }
    end
end

build(1)
layout()
local firstButton = body.kitChildren[1].kitChildren[2]
firstButton:GetScript("OnEnter")(firstButton)
assertTrue(firstButton.hover, "hovered")
local third = body.kitChildren[3].kitChildren[2]
assertTrue(not third:IsEnabled() and third.kitReason == "Not now", "disabled with a reason")

local made = #objects
body:Clear()
layout()
assertTrue(#body.kitChildren == 0, "cleared")
build(2)
layout()
assertTrue(#objects == made, "a rebuild takes every frame from the pools: " .. (#objects - made) .. " new")

-- Fresh state, from the new spec.
local reused = body.kitChildren[1].kitChildren[2]
assertTrue(not reused.hover, "hover does not survive the pool")
assertTrue(reused:GetText() == "Add" and reused.kitTone == nil, "the new caption and tone")
reused:Click()
assertTrue(clicked == "2:1", "the new onClick: " .. tostring(clicked))
local again = body.kitChildren[3].kitChildren[2]
assertTrue(again:IsEnabled() and again.kitReason == nil, "enabled again, no old reason")
local section = body.kitChildren[1].kitChildren[3]
assertTrue(section:IsOpen() and not section.kitFoldable, "a section from the pool takes the new fold options")
assertTrue(#section.body.kitChildren == 1 and section.body.kitChildren[1]:GetText() == "inside 2",
    "a section from the pool holds only what was made in it this time")

-- Removing one child puts it back in its pool, and it is made again from it.
local row = body.kitChildren[5]
body:Remove(row)
layout()
assertTrue(row.kitPooled and not row:IsShown(), "a removed row is pooled")
local before = #objects
body:Row{ gap = 8 }:Text{ "back" }
assertTrue(#objects == before, "a new row comes from the pool")
