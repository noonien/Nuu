-- Windows: collapse, status, keyboard. Runs last on the gallery: Tab lands on
-- the close button first, so Space closes it.

local ctx = ...
local Kit, UI, g, objects, Object, tick, find, show, assertTrue =
    ctx.Kit, ctx.UI, ctx.g, ctx.objects, ctx.Object, ctx.tick, ctx.find, ctx.show, ctx.assertTrue

g.win:Status("Saved.", { undo = function() end })
g.win:SetCollapsed(true)
g.win:SetCollapsed(false)
g.win:TakeKeyboard(true)
UI.WindowKey(g.win, "TAB")
UI.WindowKey(g.win, "SPACE")
g.win:TakeKeyboard(false)
tick()
