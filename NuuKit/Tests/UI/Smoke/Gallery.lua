-- The gallery: /nuukit ui builds every widget in every state; every
-- tab lays out, every theme repaints, and the Pooling tab rebuilds without
-- making frames.

local ctx = ...
local Kit, UI, assertTrue, layout, tick, objects = ctx.Kit, ctx.UI, ctx.assertTrue, ctx.layout, ctx.tick, ctx.objects

assertTrue(type(SlashCmdList.NUUKIT) == "function", "the gallery registers /nuukit")
SlashCmdList.NUUKIT("ui")
tick()
local g = UI.gallery
assertTrue(g and g.win and g.win:IsShown(), "/nuukit ui opens the gallery")
layout()

for _, key in ipairs({ "look", "controls", "lists", "tables", "inplay", "pooling" }) do
    g.tabs:SetValue(key)
    tick()
    layout()
end

for _, theme in ipairs(UI.themeOrder) do
    g.ui:SetLook({ theme = theme })
    layout()
end
g.ui:SetLook({ theme = "midnight", textSize = "large" })
layout()
g.ui:SetLook({})
layout()

-- The Pooling tab: its rebuilds make no frames.
local rebuild
for _, o in ipairs(objects) do
    if o.kitType == "Button" and o:GetText() == "Rebuild" then rebuild = o end
end
assertTrue(rebuild, "the Pooling tab has its Rebuild button")
rebuild:Click()
local made = #objects
for _ = 1, 5 do rebuild:Click() end
layout()
assertTrue(#objects == made, "rebuilds take every frame from the pools: " .. (#objects - made) .. " new")

-- In play: the tracker panel and the item strip.
g.tabs:SetValue("inplay")
for _, o in ipairs(objects) do
    if o.kitType == "Button" and (o:GetText() == "Tracker panel" or o:GetText() == "Item strip") then o:Click() end
end
layout()
assertTrue(g.panel and g.strip, "the tracker panel and the item strip open")

g.win:Hide()
tick()
