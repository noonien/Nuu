-- The planner window, built from NuuKit on the kit's stand-in for the
-- client's frame API (../NuuKit/Tests/Support/Frames.lua), planning a real
-- profession from the shipped data: every tab is drawn, and the player's
-- ways through it (alternatives, Use this, Undo, the menus, goals, prices,
-- options, the look, another profession, the testing switch) are taken.
-- Nothing may reach the error handler, and the kit's reset audit (on, as in
-- development) must find every change the planner makes to a kit widget
-- marked.
--
-- Last in the runner: it installs the stand-in in _G.
_G = _G or _ENV

local frames = dofile("../NuuKit/Tests/Support/Frames.lua")
local Object = frames.Object

-- Text measured from its font size, as the kit's smoke tests do: about 6
-- units a letter and 2 of leading at size 12.
function Object:SetFont(_, size) self.fontSize = size; return true end
function Object:GetFont() return "Fonts\\FRIZQT__.TTF", self.fontSize or 11, "" end
function Object:GetStringHeight() return (self.fontSize or 12) + 2 end
function Object:GetStringWidth() return #(self.text or "") * 6 * (self.fontSize or 12) / 12 end
function Object:GetUnboundedStringWidth() return self:GetStringWidth() end
local createFontString = Object.CreateFontString
function Object:CreateFontString(name, layer, template)
    local text = createFontString(self, name, layer, template)
    if template then text.fontSize = 12 end
    return text
end
function Object:SetToDefaults()
    self.alpha, self.strata = 1, nil
    self.level = (self.parent and self.parent.level or 0) + 1
    self.shown, self.enabled = true, true
    self.width, self.height, self.points = 0, 0, {}
    self.scripts, self.hooks = {}, {}
    self.mouse, self.attributes = false, nil
    self.text = nil
    if self.kind == "FontString" then self.fontSize = nil end
end
function Object:EnableMouse(on) self.mouse = on and true or false end
function Object:IsMouseEnabled() return self.mouse ~= false end

-- Where each line of the stack is, as the client names addon files: the
-- kit's under NuuKit, the planner's under NuuProfessions, so the audit tells
-- the planner's calls from the kit's.
_G.debugstack = function(start, count)
    local lines, level = {}, (start or 1) + 1
    for _ = 1, count or 12 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.what == "C" then
            lines[#lines + 1] = "[C]: ?"
        elseif info.what == "tail" then
            lines[#lines + 1] = "(tail call): ?"
        else
            local src = info.short_src:gsub("^%./", "")
            local path = src:match("^%.%./NuuKit/(.*)$")
            path = path and ("Interface/AddOns/NuuKit/" .. path) or ("Interface/AddOns/NuuProfessions/" .. src)
            lines[#lines + 1] = path .. ":" .. (info.currentline or 0) .. ": in function"
        end
        level = level + 1
    end
    return table.concat(lines, "\n") .. "\n"
end

-- What reaches the error handler: the planner's tabs report there, and the
-- audit's findings on release.
local errors = {}
_G.geterrorhandler = function() return function(err) table.insert(errors, tostring(err)) end end

-- The kit as the client loads it in development, the audit included.
local kitNS = {}
for line in io.lines("../NuuKit/NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and (not file:match("^Dev/") or file == "Dev/Audit.lua") then
        assert(loadfile("../NuuKit/" .. file))("NuuKit", kitNS)
    end
end
local Kit = kitNS.Kit
local UI = Kit.UI
_G.NuuKit = Kit
assert(UI.SetAudit(true), "the audit runs on the stand-in")

-- The addon, every file in its TOC's order, then PLAYER_LOGIN.
local ns = {}
for line in io.lines("NuuProfessions.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file then assert(loadfile(file))("NuuProfessions", ns) end
end
ns:Initialize()

local function check(value, message)
    if not value then error(message, 2) end
end
local function settle()
    UI.LayoutNow()
    frames.tick()
    UI.LayoutNow()
end
local function noErrors(when)
    if #errors > 0 then error(when .. ": " .. table.concat(errors, "\n"), 2) end
end

local Panel = ns.modules.PlannerPanel
local Planner = ns.modules.ProfessionPlanner
check(Panel and ns.modules.PlannerTabPlan and ns.modules.PlannerTabRecipes and ns.modules.PlannerTabMaterials
    and ns.modules.PlannerTabOptions, "the window and its four tabs are registered")
check(ns.API and ns.API.apiVersion == 1 and type(ns.API.Open) == "function", "the optional API")
-- Recipe answers the spell as well as the recipe, found by the item it makes.
do
    local spell, recipe
    for id, entry in pairs(ns.professionData.Leatherworking.recipes) do
        if entry.makes and (not spell or id < spell) then spell, recipe = id, entry end
    end
    local found, foundSpell = ns.API.Recipe("Leatherworking", nil, recipe.makes)
    check(found and foundSpell and ns.professionData.Leatherworking.recipes[foundSpell] == found,
        "the API's Recipe gives the recipe and its spell: " .. tostring(spell))
end

-- Opening: a plan for Leatherworking from the shipped data, even with the
-- profession not learned (the stand-in knows no skills).
Panel:Open("Leatherworking")
settle()
noErrors("open")
check(Panel.win:IsShown(), "the window shows")
check(Panel.route and #Panel.route.runs > 0, "a route with steps")
check(Panel.professionSelect:GetValue() == "Leatherworking", "the profession in the band")

-- The Plan tab.
local Plan = ns.modules.PlannerTabPlan
check(#Plan.list:GetView() > 0, "the route table has rows")
check(Plan.list:GetSelected() == Plan.makeTarget and Plan.makeTarget ~= nil, "the step Make acts on is selected")
check(Plan.figures.crafts:GetText() ~= "-", "the figures are set")
-- The skill past the first step, drawn without planning again: Make moves to
-- the next step, and the button is drawn for it, not for the step passed.
do
    local first = Plan.makeTarget
    local saved = Panel.live
    Panel.live = setmetatable({ skill = first.b }, { __index = saved })
    Panel:Render()
    local next = Plan.makeTarget
    check(next and next ~= first and Plan:MakeOrder(next), "Make moves past the step the skill passed")
    local text, enabled, reason = Plan.make:GetText(), Plan.make:IsEnabled(), Plan.make.kitReason
    Plan:RenderMake(Panel)
    check(Plan.make:GetText() == text and Plan.make:IsEnabled() == enabled and Plan.make.kitReason == reason,
        "the Make button is drawn for the step Make acts on: " .. tostring(reason))
    Panel.live = saved
    Panel:Render()
    settle()
end
local firstRow = Plan.list.rows[1]
local barred = 0
for _, row in ipairs(Plan.list.rows) do
    if row:IsShown() and row.segments:IsShown() then
        barred = barred + 1
        check(#row.segments.kitSegments > 0 or #row.segments.kitMarks > 0, "a shown bar has something on it")
    end
end
check(barred > 0 and firstRow.segments ~= firstRow.bar, "steps draw their skills on a segment bar of their own")

-- A step's alternatives: open, take one, undo.
local run
for _, model in ipairs(Plan.list:GetView()) do
    if model.t == "run" and model.mayHaveWays then run = model; break end
end
check(run, "a step with alternatives")
Plan:ToggleWays(run)
settle()
local way
for _, model in ipairs(Plan.list:GetView()) do
    if model.t == "way" and not model.way.using then way = model; break end
end
if way then
    local before = Planner:ChosenAt(Panel.inputs, way.way.fromSkill)
    Plan:UseWay(way)
    settle()
    check(Panel.statusUndo ~= nil, "a pick can be undone")
    Panel.statusUndo()
    settle()
    check(Planner:ChosenAt(Panel.inputs, way.way.fromSkill) == before, "undo takes the pick back")
end
Plan:ToggleWays(run)
settle()
noErrors("alternatives")

-- Scrolling the table draws the rows in view again and moves the axis.
Plan.list:ScrollSet(3)
settle()
Plan.list:ScrollSet(0)
settle()
check(Plan.axisRange and Plan.axisRange[2] > Plan.axisRange[1], "the axis spans the rows in view")

-- The run menu: prefer the recipe, then back to the planner.
Plan:OpenRunMenu(run)
check(Panel:UI().kitMenu and Panel:UI().kitMenu:IsShown(), "the run's menu opens")
Panel:UI():CloseMenu()
Plan:Picked(run)
Plan:MakeNext()
settle()
noErrors("plan tab")

-- Only what I have, and the target typed.
Plan:CarriedToggled(true)
settle()
check(Panel.inputs.options.materials == "carried", "planning with what is carried")
Plan:CarriedToggled(false)
Plan:TargetCommitted("120")
settle()
check(Panel.inputs.target == 120, "the target typed")
Plan:AutoToggled(true)
Plan:SectionsPicked("band")
Plan:SizeCommitted("50")
settle()
check(Panel.inputs.options.bandSize == 50, "sections every 50 skills")
Plan:SectionsPicked("trip")
settle()
noErrors("summary")

-- The shopping list: one list in a trip (no drop-down), one a section when
-- split, All sections under headings, the bags ticking items off, and the
-- list staying up with the planner shut.
local Shopping = ns.modules.ShoppingList
local function shoppingSelect()
    for _, child in ipairs(Shopping.area.kitInner:GetChildren()) do
        if child.kitType == "Select" then return child end
    end
end
check(#Shopping:Record(false).lists.Leatherworking.sections == 1, "a trip keeps one list")
Shopping:Toggle()
settle()
check(Shopping:IsShown(), "the list shows")
check(#Shopping.rows > 0, "the list has items")
check(not shoppingSelect(), "one list, no drop-down")
Plan:SectionsPicked("tier")
settle()
local kept = Shopping:Record(false).lists.Leatherworking.sections
check(#kept > 1, "split by tier, a list a section (" .. #kept .. ")")
check(shoppingSelect(), "several lists, a drop-down under the title")
for _, option in ipairs(Shopping:Options(Shopping:Professions())) do
    check(option.separator or option.caption:find("^Leatherworking: "), "a list reads <Profession>: <section>")
end
local first = #Shopping.rows
local lines = 0
for _, section in ipairs(Shopping:Live("Leatherworking", Shopping:Record(false).lists.Leatherworking)) do
    lines = lines + #section.items
end
Shopping:Record(true).pick = "Leatherworking:all"
Shopping:Refresh()
settle()
check(#Shopping.rows == lines and lines > first, "all sections lists every section's items")
local frameHeight = Shopping.frame:GetHeight()
check(frameHeight > 0 and frameHeight <= 520, "as tall as the list, up to its cap (" .. frameHeight .. ")")
_G.GetItemCount = function() return 1e9 end
Shopping:Refresh()
check(Shopping.summary == "All carried", "the bags tick everything off")
_G.GetItemCount = nil
Shopping:Refresh()

-- A row: the name with its price, "| 10c" from a vendor and "| 15c @ AH" at
-- the auction house, and a bar of what is carried with "15 / 21" at its end.
for _, line in ipairs(Shopping.rows) do
    local item, name = line.item, line.name:GetText()
    if item.each and (item.source == "ah" or item.source == "estimate") then
        check(name:find("@ AH", 1, true) and name:find("| ", 1, true), "an auction house item says so: " .. name)
    elseif item.each and item.source == "vendor" then
        check(name:find("| ", 1, true) and not name:find("@ AH", 1, true), "a vendor item has its price: " .. name)
    end
    check(line.bar:GetValue() == math.min(item.have, item.count) and line.count:GetText() == item.have .. " / " .. item.count,
        "the bar and its count")
end

-- What the route also makes (a bolt of cloth, the carried part used first)
-- is a step, not shopping.
do
    local live = Shopping:Live("Test", { sections = { { title = "T", items = {
        { itemID = 2996, count = 15, source = "gather", made = true },
        { itemID = 2320, count = 21, source = "vendor", each = 10 },
    } } } })
    check(#live == 1 and #live[1].items == 1 and live[1].items[1].itemID == 2320, "what the route makes is left off")
end

-- No made items, no Buy buttons; a click on the icon ticks by hand.
for _, line in ipairs(Shopping.rows) do
    check(line.item.source ~= "craft", "what is made on the way is not shopping")
    check(line.buy == nil and line.slot ~= nil, "a row is an icon, its words and a cost")
end
-- Rows under a heading per kind of shop, each heading with what is left to buy there.
local headings = {}
for _, group in ipairs(Shopping.groups) do headings[group.key] = group end
check(headings.vendor or headings.ah, "the rows are grouped by where they are bought")
for _, group in ipairs(Shopping.groups) do
    if (group.key == "vendor" or group.key == "ah") and group.items > 1 then
        check(group.cost:GetText() ~= "", "a shop's heading says what is left to buy there")
    elseif group.cost and group.items == 1 then
        check(group.cost:GetText() == "", "but not for one item, whose row says it")
    end
end
local function lineOf(itemID)
    for _, line in ipairs(Shopping.rows) do
        if line.item.itemID == itemID then return line end
    end
end
local tickedID = Shopping.rows[1].item.itemID
local before = Shopping.summary
Shopping.rows[1].slot:Click()
check(Shopping.summary ~= before and not lineOf(tickedID), "a click on the icon ticks it: it leaves for Collected")
local last = Shopping.groups[#Shopping.groups]
check(last.key == "have", "what is collected has its own section, last, folded")
local fold = last.fold
check(fold and not Shopping:Record(false).haveOpen and not lineOf(tickedID), "Collected folds")
check(fold.kitType == "Disclosure" and not fold:IsOpen(), "a fold on a line across the list")
fold:Activate()
check(Shopping:Record(false).haveOpen and lineOf(tickedID) and lineOf(tickedID).item.ticked
    and Shopping.rows[#Shopping.rows].item.itemID == tickedID, "opened, it lists what is had")
lineOf(tickedID).slot:Click()
check(not lineOf(tickedID).item.ticked and Shopping.summary == before, "and a second click takes the tick off")
check(Shopping.rows[1].item.itemID == tickedID, "and it goes back to its shop")
Shopping:Record(true).haveOpen = nil
Shopping:Refresh()
check(Shopping.frame.statusStrip and Shopping.frame.statusStrip:IsShown(), "where the list stands is in the strip at the foot")

-- Buying: the batches and calls.
local Buying = ns.modules.MerchantBuying
local plan = Buying:Plan({ price = 50, count = 5, stock = 3, index = 1 }, 22)
check(plan.purchases == 3 and plan.items == 15 and plan.cost == 150 and #plan.calls == 3 and plan.calls[1] == false,
    "batches of 5, held to the stock of 3, one batch a call")
plan = Buying:Plan({ price = 10, count = 1, maxStack = 20, index = 1 }, 45)
check(plan.cost == 450 and #plan.calls == 3 and plan.calls[1] == 20 and plan.calls[3] == 5, "one at a time, 20 a call")

-- The strip under the vendor's window: a vendor selling two list items.
local Strip = ns.modules.VendorStrip
local wantedItems = {}
for _, line in ipairs(Shopping.rows) do
    if #wantedItems < 2 and line.item.count > line.item.have then table.insert(wantedItems, line.item) end
end
check(#wantedItems == 2, "two list items still to buy")
local Client = ns.modules.Client
local bought = {}
_G.MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
MerchantFrame:SetSize(336, 444)
MerchantFrame.page, MerchantFrame.selectedTab = 1, 1
_G.MERCHANT_ITEMS_PER_PAGE = 10
_G.MerchantItem1ItemButton = CreateFrame("Button", nil, MerchantFrame)
_G.MerchantItem2ItemButton = CreateFrame("Button", nil, MerchantFrame)
_G.GetMerchantNumItems = function() return 2 end
_G.GetMerchantItemInfo = function() return "Thing", "icon", 10, 1, -1, true, true, false end
_G.GetMerchantItemLink = function(index)
    local item = wantedItems[index]
    return item and ("|cffffffff|Hitem:" .. item.itemID .. "::::::::|h[Thing]|h|r") or nil
end
_G.GetMerchantItemMaxStack = function() return 20 end
-- Money only: no currency or item costs (an earlier suite leaves its own).
_G.GetMerchantItemCostInfo = function() return 0 end
_G.GetMoney = function() return 1e9 end
_G.BuyMerchantItem = function(index, quantity) table.insert(bought, { index, quantity }) end
Strip:Refresh()
check(not (Strip.frame and Strip.frame:IsShown()), "no vendor open, no strip")
Client.merchantOpen = true
Strip:Refresh()
settle()
check(Strip.frame:IsShown() and #Strip.rows == 2, "the strip lists what this vendor sells")
check(Strip.buyAll:IsEnabled() and Strip.buyAll:GetText():find("Buy all", 1, true), "Buy all is on")
check(Strip.badges[1] and Strip.badges[1]:IsShown() and Strip.badges[2]:IsShown(), "both items marked on the vendor's page")
_G.GetMoney = function() return 0 end
Strip:Refresh()
check(not Strip.buyAll:IsEnabled() and not Strip.rows[1].buy:IsEnabled(), "no money, no buying")
_G.GetMoney = function() return 1e9 end
Strip:Refresh()
Strip:Buy(Strip.wanted)
local total = {}
for _, call in ipairs(bought) do total[call[1]] = (total[call[1]] or 0) + (call[2] or 1) end
-- With All sections, an item in several sections is bought for all of them.
local function missingOf(itemID)
    local sum = 0
    for _, line in ipairs(Shopping.rows) do
        if line.item.itemID == itemID then sum = sum + line.item.count - line.item.have end
    end
    return sum
end
check(total[1] == missingOf(wantedItems[1].itemID) and total[2] == missingOf(wantedItems[2].itemID)
    and not Buying:Busy(), "Buy all bought what is missing of both")
_G.GetMerchantNumItems = function() return 0 end
Strip:Refresh()
check(not Strip.frame:IsShown() and not Strip.badges[1]:IsShown(), "a vendor selling nothing on the list: no strip, no marks")
Client.merchantOpen = nil
_G.GetMerchantNumItems, _G.GetMerchantItemInfo, _G.GetMerchantItemLink = nil, nil, nil
_G.GetMerchantItemMaxStack, _G.GetMoney, _G.BuyMerchantItem = nil, nil, nil
_G.GetMerchantItemCostInfo = nil
Shopping:Refresh()
Panel.win:Hide()
Shopping:Refresh()
check(Shopping:IsShown(), "the list stays up with the planner shut")
Panel:Open()
Shopping:Record(true).pick = nil
Plan:SectionsPicked("trip")
settle()
check(Shopping.frame.closeButton, "the kit's close mark")
Shopping.frame.closeButton:Click()
check(not Shopping:IsShown() and not Shopping:Record(false).shown, "the close mark puts the list away")
Shopping:SetShown(true)
Shopping:SetShown(false)
settle()
check(not Shopping:IsShown(), "the list put away")
noErrors("shopping list")

-- The Recipes tab: every Show, a goal and its line.
Panel:ShowTab("recipes")
settle()
local Recipes = ns.modules.PlannerTabRecipes
check(#Recipes.list:GetView() > 0, "recipes in range")
local recipe = Recipes.list:GetView()[1]
local priced, routed = false, false
for _, item in ipairs(Recipes.list:GetView()) do
    local profit = item.entry.profit
    if profit and (profit.ah or profit.vendor) then priced = true end
    if item.entry.use then routed = true end
end
check(priced, "a recipe in range has a profit at the auction house or a vendor")
check(routed, "a recipe in range is in the route")
Recipes.stocked = true
Recipes:Render(Panel, true)
Recipes.stocked = false
for _, filter in ipairs({ "route", "goals", "prefer", "never", "have", "all", "range" }) do
    Recipes.filter = filter
    Recipes:Render(Panel, true)
    settle()
end
local spell = recipe.entry.spell
local goalWas = Planner:FindGoal(Panel.inputs, spell)
if goalWas then
    local _, index = Planner:FindGoal(Panel.inputs, spell)
    Planner:RemoveGoal(Panel.inputs, index)
end
Panel:Change("goal", function(inputs) Planner:BumpGoal(inputs, spell) end, "goal")
settle()
local goalLine
for _, item in ipairs(Recipes.list:GetView()) do
    if item.kind == "goal" and item.entry.spell == spell then goalLine = item end
end
check(goalLine, "a goal has its line under its recipe")
Recipes.search:SetText("a")
settle()
Recipes.search:SetText("")
settle()
Recipes:RightClicked(recipe)
Panel:UI():CloseMenu()
Panel:ShowTab("recipes", { spell = spell })
settle()
noErrors("recipes tab")

-- The Materials tab: every view, a price typed and taken back.
Panel:ShowTab("materials")
settle()
local Materials = ns.modules.PlannerTabMaterials
for _, filter in ipairs({ "section", "guessed", "loss", "range", "avoided", "route" }) do
    Materials:SetFilter(filter)
    settle()
end
local material
for _, group in ipairs(Materials.table:GetItems()) do
    for _, item in ipairs(group.rows or {}) do
        if item.kind == "material" and not material then material = item end
    end
end
check(material, "the route buys materials")
Materials:SetPrice(material.itemID, "auctionBuy", 1234)
settle()
local book = ns.modules.Prices:Book()
check(book.prices[material.itemID].auctionBuy.value == 1234, "the price typed is in the book")
Panel.statusUndo()
settle()
check(not (book.prices[material.itemID] and book.prices[material.itemID].auctionBuy), "undo takes the price back")
Materials:SetMaterialMode(material.itemID, "never")
settle()
Materials:SetFilter("avoided")
settle()
Materials:SetMaterialMode(material.itemID, "auto")
Materials:SetFilter("route")
settle()
Materials.neverField:SetText("leather")
Materials:Suggest()
Panel:UI():CloseMenu()
noErrors("materials tab")

-- The Options tab: every option changed, then all reset.
Panel:ShowTab("options")
settle()
local Options = ns.modules.PlannerTabOptions
Options:SetOption({ kind = "select", option = "optimize", label = "Optimise for" }, "profit")
Options:SetOption({ kind = "select", option = "confidence", label = "Confidence" }, "sure")
Options:SetOption({ kind = "toggle", option = "useBags", caption = "Use what I carry first" }, false)
Options:SetOption({ kind = "estimate", option = "estimateFactor" }, 2.5)
settle()
check(Panel.inputs.options.optimize == "profit" and Panel.inputs.options.estimateFactor == 2.5, "options kept")
Options:Reset(Panel, Options.rows, "all")
settle()
check(Panel.inputs.options.optimize == nil and Panel.inputs.options.estimateFactor == nil, "reset all forgets them")
noErrors("options tab")

-- A new look draws the window again; another profession, the testing set.
Panel:UI():SetLook({ theme = "horde", accent = "#ff8a4c" })
settle()
Panel:UI():SetLook(nil)
Panel:ShowTab("plan")
Panel:SelectProfession("Tailoring")
settle()
check(Panel.profession == "Tailoring", "another profession")
Panel:SetFullScope(true)
settle()
check(Panel:FullScope(), "the testing set")
Panel:SetFullScope(false)
Panel:SelectProfession("Leatherworking")
settle()
noErrors("look and professions")

-- Closing and opening again builds nothing twice.
Panel.win:Hide()
local objects = #frames.objects
Panel:Toggle()
settle()
check(Panel.win:IsShown(), "opened again")
Panel:ShowTab("recipes")
Panel:ShowTab("materials")
Panel:ShowTab("plan")
settle()
check(#frames.objects - objects < 50, "opening again makes few frames (" .. (#frames.objects - objects) .. ")")
noErrors("reopen")

-- The audit is live here: a change to a kit widget from the planner's code
-- without its mark is caught when the widget is cleared.
local page = Panel.tabByKey.plan.page
local probe = page:Button{ "probe" }
probe:SetFrameStrata("HIGH")
page:Remove(probe)
check(#errors == 1 and errors[1]:find("not marked", 1, true), "the audit catches an unmarked change")
errors = {}

print("NuuProfessions UI smoke tests passed (" .. #frames.objects .. " objects)")
return true
