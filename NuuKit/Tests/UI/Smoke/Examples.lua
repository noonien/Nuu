-- The API examples (UI/examples.lua) run as written, against the kit as built.

local ctx = ...
local Kit, UI, assertTrue, tick, layout = ctx.Kit, ctx.UI, ctx.assertTrue, ctx.tick, ctx.layout

local addon = { name = "NuuRoad", Kit = Kit }
function addon:Trace() end
addon.LevelColor = function() return "muted" end
addon.ZoneOptions = function() return { { value = 40, caption = "Westfall" } } end
_G.NuuRoadDB = { windows = {}, look = { theme = "alliance" } }
_G.NuuProfessionsDB = { routeBy = "few", sellBack = false }
local examples = assert(loadfile("UI/examples.lua"))("NuuRoad", addon)
local Setup, GuideBrowser, Looks, Layout, SectionsAndTabs, Buttons, Fields, Menus, Panes, Feedback, InPlay, Keyboard, Tables = unpack(examples)
Setup()
local ui = addon.UI
assertTrue(ui and ui:GetLook().theme == "alliance", "Setup makes the addon's UI in its look")
local started
local browser = GuideBrowser({ { name = "Westfall", min = 10, max = 15, forMe = true } }, function(guide) started = guide end)
tick()
layout()
local win = ui:Window({ key = "examples", title = "Examples", width = 700, height = 600 })
local col = win:Column{ padding = 10 }
Looks(col:Section{ "Appearance" })
Layout(ui:Window({ key = "layout", width = 400, height = 300 }))
SectionsAndTabs(ui:Window({ key = "tabs", width = 600, height = 400 }))
Buttons(col:Row{ gap = 6 })
local prices = { silk = 3200 }
Fields(col, prices)
local list = col:List{ rows = 4 }
Menus(col, col:Button{ "Step 12" }, { { caption = "Kobold camp" } })
Panes(ui:Window({ key = "panes", width = 900, height = 500 }), { { caption = "Alliance", children = { { caption = "Elwynn" } } } }, function() end)
Feedback(col, list, win)
InPlay()
local a = col:Input{}
Keyboard(win, a, col:Input{}, col:Input{})
Tables(ui:Window({ key = "tables", width = 700, height = 600 }), { { caption = "Cloth", rows = { { name = "Silk Cloth", need = 80, price = 410 } } } })
tick()
layout()
assertTrue(browser:IsShown(), "the example window is built")
assertTrue(NuuProfessionsDB.sellBack == nil, "Reset forgot the stored choice")
assertTrue(NuuProfessionsDB.routeBy == "few", "a bound select reads its table and writes nothing on its own")
for _, key in ipairs(UI.themeOrder) do ui:SetLook({ theme = key }); tick() end
layout()
