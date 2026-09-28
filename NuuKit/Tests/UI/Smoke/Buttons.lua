-- Buttons, confirm buttons, links, resets, glyph buttons, attention.

local ctx = ...
local UI, ui, assertTrue, testWindow, layout, tick = ctx.UI, ctx.ui, ctx.assertTrue, ctx.testWindow, ctx.layout, ctx.tick

local _, body = testWindow(ui, 700, 500)
local row = body:Row{ gap = 8 }
local clicks = 0
local save = row:Button{ "Save", tone = "accent", onClick = function() clicks = clicks + 1 end }
local wide = row:Button{ "A much longer caption" }
layout()
assertTrue(wide.kitPW > save.kitPW, "a button is as wide as its caption")
save:Click()
assertTrue(clicks == 1, "a click calls onClick")

-- Hover paints colours only: no font set, no layout.
local fonts = 0
local setFont = save.label.SetFont
save.label.SetFont = function(...) fonts = fonts + 1; return setFont(...) end
save:GetScript("OnEnter")(save)
save:GetScript("OnLeave")(save)
assertTrue(fonts == 0 and UI.LayoutSettled(), "hover sets no font and lays nothing out")
save.label.SetFont = nil

-- Disabled with a reason; enabled again.
save:SetEnabled(false, "Plan a route first.")
assertTrue(not save:IsEnabled() and save.kitReason == "Plan a route first.", "disabled with a reason")
save:Click()
assertTrue(clicks == 1, "a disabled button does not act")
save:SetEnabled(true)
assertTrue(save.kitReason == nil, "enabled: no reason")

-- A caption change: wider, laid out again.
local width = save.kitPW
save:SetText("Save as guide")
layout()
assertTrue(save.kitPW > width, "a longer caption makes it wider")

-- Active, tone.
save:SetActive(true)
assertTrue(save:IsActive(), "active")
save:SetTone("danger", "soft")

-- Confirm: two clicks.
local confirmed = 0
local confirm = row:ConfirmButton{ "Reset guide", onConfirm = function() confirmed = confirmed + 1 end }
confirm:Click()
assertTrue(confirmed == 0 and confirm:GetText() ~= "Reset guide", "the first click arms it")
confirm:Click()
assertTrue(confirmed == 1 and confirm:GetText() == "Reset guide", "the second acts and disarms")

-- Hold: a click alone does nothing.
local held = 0
local hold = row:Button{ "Abandon", tone = "danger", hold = 1.2, onClick = function() held = held + 1 end }
hold:Click()
assertTrue(held == 0, "a held button ignores a plain click")

-- Links and resets.
local linked = 0
local link = body:Link{ "Report a problem", onClick = function() linked = linked + 1 end }
link:Click()
assertTrue(linked == 1, "a link acts")
local reset = body:ResetButton{ stored = false, default = "cheapest", onReset = function() end }
assertTrue(not reset:IsShown(), "a reset hides while nothing is stored")
reset:SetStored(true, "cheapest")
assertTrue(reset:IsShown() and reset.tooltip:find("cheapest"), "shown, with the default in its tooltip")

-- Glyph buttons.
local glyphRow = body:Row{ gap = 6 }
for _, kind in ipairs({ "back", "next", "up", "down", "menu", "close", "plus", "minus" }) do
    glyphRow:GlyphButton{ kind, tooltip = kind }
end
local close = body:GlyphButton{ "close", boxed = true, bright = true, size = 22 }
close:GetScript("OnEnter")(close)
close:GetScript("OnLeave")(close)
close:SetGlyph("up")
layout()
assertTrue(close.kitPW == 22, "a glyph button is its size")

-- Attention, and stopping it.
for _, kind in ipairs({ "breathe", "pulse", "shimmer", "flash", "trail", { "trail", "breathe" } }) do
    save:Attract(kind)
    tick()
end
save:Attract(nil)
ui:SetLook({ reduceMotion = true })
save:Attract("pulse")
save:Attract(nil)
ui:SetLook({})

-- Placed by the caller: sized to its caption, and again when it changes.
local placed = ui:Button(UIParent, { "Placed" })
local before = placed.kitPW
placed:SetText("Placed and longer")
layout()
assertTrue(placed.kitPW > before, "a placed button fits its new caption")

-- Art themes: each plate makes its 9-slice for a theme once, and switching
-- back and forth makes nothing more.
do
    local objects = ctx.objects
    ui:SetLook({ theme = "horde" })
    ui:SetLook({ theme = "alliance" })
    local count = #objects
    for _ = 1, 3 do
        ui:SetLook({ theme = "horde" })
        ui:SetLook({ theme = "alliance" })
        ui:SetLook({ theme = "midnight" })
    end
    assertTrue(#objects == count, "switching art themes again makes no textures: " .. (#objects - count) .. " new")
    ui:SetLook({})
end
