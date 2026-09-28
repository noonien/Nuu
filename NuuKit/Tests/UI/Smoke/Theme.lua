-- Themes and looks, on the whole gallery.

local ctx = ...
local Kit, UI, g, objects, Object, tick, find, show, assertTrue =
    ctx.Kit, ctx.UI, ctx.g, ctx.objects, ctx.Object, ctx.tick, ctx.find, ctx.show, ctx.assertTrue

-- Every theme, including the art ones, and the look's other settings.
for _, key in ipairs(UI.themeOrder) do
    g.ui:SetLook({ theme = key, accent = "#6f9dff", opacity = 0.6, textSize = "large", reduceMotion = true })
    tick()
end
g.ui:SetLook({ theme = "horde", accent = "class" })
tick()
