local _, ns = ...

-- The planner's Recipes tab (PROF_PLAN.md, "UI"): every recipe of the
-- profession as a table row, with its colour bands against the live skill,
-- where it is learned, what a craft makes at the auction house and at a
-- vendor, a tint on the recipes the route uses, and what the player
-- decides about it: Goal (make some on the way, with how many and when on a
-- line under the row) and Plan with it (the planner decides, prefer it,
-- never use it, or I have the pattern). A right-click on a row opens the
-- same Plan with it choices at the cursor; hovering it shows the recipe.
--
-- The toolbar narrows the list: Show (in range, in the route, goals, the
-- recipes preferred, never used, the patterns the player has, all, each with
-- its count), Source (where it is learned), Have materials (only what the
-- bags can make at least once), and a search over the recipe's name, the
-- item it makes and its reagents. The window shell (UI/Planner.lua) plans;
-- this file only reads the panel and calls the planner's input setters
-- through panel:Change, so every choice here can be undone from the status
-- strip.
--
-- Ported from OpenRoad's UI/PlannerRecipes.lua. The table is a kit List,
-- which draws only the rows in view, so the fifty-a-page pager is gone; the
-- colour bands are scaled to the rows in view, as the pages were to theirs.
-- A goal's line is a row of its own under its recipe.
local Tab = { key = "recipes", caption = "Recipes",
    filter = "range", source = "any", stocked = false,
    hint = "Hover a recipe for its reagents and where it is taught. Right-click a row for the same choices as Plan with it." }

local function Planner() return ns.modules.ProfessionPlanner end
local function Prices() return ns.modules.Prices end
local function Tiers() return ns.modules.ProfessionTiers end
local function SkillUp() return ns.Kit.SkillUp end

-- Geometry: the columns, left to right.
local ROW_HEIGHT = 30
local NAME_W, BAR_W, SOURCE_W, PROFIT_W, GOAL_W = 210, 150, 124, 122, 50
local ROW_GAP = 10
local NEVER_ALPHA = 0.55

-- Show: which recipes the table lists.
local SHOWS = {
    { "range", "In range", "Recipes that give skill between your skill and the target" },
    { "route", "In route", "Recipes the route makes: its runs, the parts it makes on the way, and your goals" },
    { "goals", "Goals", "Recipes you want made on the way, with how many and when" },
    { "prefer", "Prefer", "Recipes you asked the planner to use wherever they give skill" },
    { "never", "Never use", "Recipes you turned off, or that need a material you turned off" },
    { "have", "Patterns I have", "Patterns you said you have or will get" },
    { "all", "All", "Every recipe of the profession" },
}
-- What the table says when a Show has nothing in it (and nothing is searched).
local EMPTY = {
    range = "No recipe gives skill between your skill and the target.",
    route = "The route makes no recipe yet.",
    goals = "No goals yet: tick Goal on any recipe to have some made on the way.",
    prefer = "You prefer no recipe. Plan with it: Prefer it, on any row, has the route use it wherever it gives skill.",
    never = "You have not turned any recipe, or any material, off.",
    have = "You have not said you have any pattern. Plan with it: I have the pattern, on a recipe taught by one.",
    all = "No recipes for this profession yet.",
}
-- Source: where the recipe is learned.
local SOURCES = {
    { value = "any", caption = "Any source" },
    { value = "known", caption = "Known", desc = "Recipes this character already knows" },
    { value = "trainer", caption = "Trainer", desc = "Recipes a trainer teaches" },
    { value = "vendor", caption = "Vendor pattern", desc = "Patterns a vendor sells" },
    { value = "boe", caption = "BoE pattern", desc = "Patterns that bind on equip: the auction house has them" },
    { value = "bop", caption = "BoP pattern",
        desc = "Patterns that bind on pickup: a drop, quest or reputation reward only you can get" },
}
local SOURCE_TEXT = { trainer = "trainer", vendor = "vendor", boe = "BoE pattern", bop = "BoP pattern" }
local LEARN_FROM = {
    trainer = "at the trainer", vendor = "from a vendor",
    boe = "from the auction house", bop = "from its pattern (bind on pickup)",
}
-- Recipes learned from a pattern the player may take: I have the pattern.
local PATTERN_SOURCES = { vendor = true, boe = true, bop = true }

-- Plan with it, and what the status strip says after each.
local PLAN_WITH = {
    { "auto", "Planner decides", "Use it where it is cheapest", "The planner decides where to use %s." },
    { "prefer", "Prefer it", "Use it wherever it gives skill", "Preferring %s wherever it gives skill." },
    { "never", "Never use it", "Leave it out, never suggest it", "Never using %s." },
}
local HAVE_MESSAGE = "Planning with %s: you have its pattern or will get it."

-- The choices, twice: with I have the pattern offered, for a recipe taught by
-- a pattern the character lacks, and without.
local function planList(offered)
    local list = {}
    for _, choice in ipairs(PLAN_WITH) do
        table.insert(list, { value = choice[1], caption = choice[2], desc = choice[3] })
    end
    table.insert(list, { separator = true })
    table.insert(list, { value = "have", caption = "I have the pattern",
        desc = offered and "Plan with it; the route adds a step to get it" or "Only for recipes taught by a pattern",
        disabled = not offered or nil,
        reason = "Only for a recipe taught by a pattern this character does not know yet" })
    return list
end
local PLAN_OFFERED, PLAN_PLAIN = planList(true), planList(false)

-- When a goal is made.
local WHENS = {
    { value = "best", caption = "Where it gives most skill", desc = "Usually as soon as it is orange" },
    { value = "now", caption = "First thing", desc = "Made first, because you want to use it" },
    { value = "end", caption = "After the target", desc = "Made after the target skill, just for the list" },
    { value = "skill", caption = "At skill", desc = "Made at the skill level typed beside this" },
}

local function fill(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

-- Reading the panel ------------------------------------------------------------

-- What the route does with each recipe, by spell: the skill levels its runs make it
-- over ("50-67, 90-95"), "part" when it is made as another recipe's
-- material, "goal, 120" for a goal and where it is made. nil for a recipe
-- the route does not use.
local function routeUses(route)
    local uses = {}
    local function of(spell)
        uses[spell] = uses[spell] or { ranges = {} }
        return uses[spell]
    end
    for _, run in ipairs(route and route.runs or {}) do
        if run.spell then
            local ranges = of(run.spell).ranges
            local last = ranges[#ranges]
            if last and last[2] == run.fromSkill then last[2] = run.toSkill
            else table.insert(ranges, { run.fromSkill, run.toSkill }) end
        end
        for _, part in ipairs(run.intermediates or {}) do
            if part.spell then of(part.spell).part = true end
        end
    end
    for _, event in ipairs(route and route.events or {}) do
        if event.kind == "goal" and event.spell then
            of(event.spell).goal = event.atEnd and "after" or tostring(event.skill or "")
        end
    end
    local text = {}
    for spell, use in pairs(uses) do
        local words = {}
        if use.goal then table.insert(words, use.goal ~= "" and ("goal, " .. use.goal) or "goal") end
        for _, range in ipairs(use.ranges) do table.insert(words, range[1] .. "-" .. range[2]) end
        if use.part then table.insert(words, "part") end
        text[spell] = table.concat(words, ", ")
    end
    return text
end

-- What one craft makes, its reagents bought: { ah, vendor, estimated }, ah
-- at the auction price less its cut (nil when unpriced, or the item is
-- soulbound), vendor at the vendor price (nil without one). nil for a recipe
-- that makes no item or whose reagents cannot be had. Every sale counts
-- here, whatever the player chose to sell.
local function profitOf(ctx, recipe)
    if not ctx or not recipe.makes then return nil end
    local cost, _, estimated = ctx:ReagentCost(recipe)
    if not cost then return nil end
    local made = Prices().AverageMade(recipe)
    local profit = { estimated = estimated }
    local item = ctx:Item(recipe.makes)
    profit.bound = item and item.bind == "bop" or nil
    if not profit.bound then
        local listed = ctx:Fact(recipe.makes, "auctionSell")
        if listed then profit.ah = math.floor(listed * (1 - Prices().auctionCut)) * made - cost end
    end
    local vendor = ctx:Fact(recipe.makes, "vendorSell")
    if vendor then profit.vendor = vendor * made - cost end
    return profit
end

-- "+12s", "-3s 20c", or "-" for no price.
local function profitWords(panel, copper)
    if not copper then return "-" end
    copper = math.floor(copper + 0.5)
    if copper > 0 then return panel:Tint("+" .. panel:Money(copper), "gain") end
    return panel:Money(copper)
end

-- What the route made of each goal, by spell: where it is made, or why it
-- is not. Problems win.
local function goalNotes(panel)
    local notes, problems = {}, {}
    local route = panel.route
    for _, event in ipairs(route and route.events or {}) do
        if event.kind == "goal" and event.spell then
            local words = { event.atEnd and "Made after the route" or ("Made at " .. tostring(event.skill)) }
            if (event.gain or 0) > 0 then table.insert(words, "about +" .. event.gain .. " skill") end
            table.insert(words, "kept")
            notes[event.spell] = table.concat(words, ", ")
        end
    end
    for _, warning in ipairs(route and route.warnings or {}) do
        if warning.code == "goal" and warning.spell and not problems[warning.spell] then
            -- "Goal 2 needs skill 125, past this plan." reads, on the goal's
            -- own line, as "Needs skill 125, past this plan."
            local text = tostring(warning.text or ""):gsub("^Goal %d+:? ?", "")
            if warning.item then
                text = "Needs " .. panel:ItemName(warning.item) .. ", which you don't use: it is left out."
            end
            problems[warning.spell] = text:sub(1, 1):upper() .. text:sub(2)
        end
    end
    return notes, problems
end

-- Does the recipe, what it makes, or one of its reagents answer the search?
local function matches(panel, entry, search)
    if search == "" then return true end
    if entry.name:lower():find(search, 1, true) then return true end
    local recipe = entry.recipe
    if recipe.makes and panel:ItemName(recipe.makes):lower():find(search, 1, true) then return true end
    for _, reagent in ipairs(recipe.reagents or {}) do
        if panel:ItemName(reagent[1]):lower():find(search, 1, true) then return true end
    end
    return false
end

-- Can one craft of the recipe be had from what the bags hold? A reagent a
-- vendor sells does not count against it (it can be bought), and one short
-- in the bags may be made, as the route would, by a recipe the character
-- knows (or a helper's, such as Smelting's bars) from what is carried.
-- `stock` is the search's shared state: the bags, what vendors sell, and
-- who makes what.
local MAKE_DEPTH = 4

local function stockOf(panel, ctx, known)
    local makers = {}
    for spell, recipe in pairs(panel.data and panel.data.recipes or {}) do
        if type(recipe) == "table" and recipe.makes and not recipe.sod
            and (known[spell] or recipe.helper or recipe.learn == "start") then
            makers[recipe.makes] = makers[recipe.makes] or {}
            table.insert(makers[recipe.makes], recipe)
        end
    end
    return { bags = panel.live and panel.live.bags, ctx = ctx, makers = makers, sold = {} }
end

local function copy(pool)
    local out = {}
    for key, value in pairs(pool) do out[key] = value end
    return out
end

-- Takes `count` of `item` out of `pool` (what is used so far), making what
-- the bags lack; false when it cannot be had.
local function take(stock, pool, item, count, depth)
    local sold = stock.sold[item]
    if sold == nil then
        sold = (stock.ctx and stock.ctx:Fact(item, "vendorBuy")) and true or false
        stock.sold[item] = sold
    end
    if sold then return true end
    local carried = (stock.bags(item) or 0) - (pool[item] or 0)
    if carried >= count then
        pool[item] = (pool[item] or 0) + count
        return true
    end
    if depth >= MAKE_DEPTH then return false end
    local short = count - math.max(carried, 0)
    for _, maker in ipairs(stock.makers[item] or {}) do
        local made = maker.made
        local each = (type(made) == "table" and tonumber(made[1])) or 1
        local crafts = math.ceil(short / math.max(each, 1))
        local trial = copy(pool)
        trial[item] = (trial[item] or 0) + math.max(carried, 0)
        local ok = true
        for _, reagent in ipairs(maker.reagents or {}) do
            if not take(stock, trial, reagent[1], (reagent[2] or 1) * crafts, depth + 1) then ok = false; break end
        end
        if ok then
            for key, value in pairs(trial) do pool[key] = value end
            return true
        end
    end
    return false
end

local function stocked(stock, recipe)
    if not stock.bags then return false end
    local pool = {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        if not take(stock, pool, reagent[1], reagent[2] or 1, 0) then return false end
    end
    return true
end

-- Changes ------------------------------------------------------------------------

local function setPlanWith(panel, spell, mode)
    local message = HAVE_MESSAGE
    for _, choice in ipairs(PLAN_WITH) do if choice[1] == mode then message = choice[4] end end
    local name = panel:RecipeName(spell)
    panel:Change("planwith", function(inputs) Planner():SetPlanWith(inputs, spell, mode) end, message:format(name))
end

-- A goal's count, at least one; anything else puts the field back.
local function setGoalCount(panel, spell, value)
    local goal, index = Planner():FindGoal(panel.inputs, spell)
    local count = math.floor(tonumber(value) or 0)
    if not index or count < 1 or count == (goal.count or 1) then Tab:Render(panel); return end
    local name = panel:RecipeName(spell)
    panel:Change("goal", function(inputs)
        local _, at = Planner():FindGoal(inputs, spell)
        if at then Planner():SetGoalCount(inputs, at, count) end
    end, "Making " .. count .. " x " .. name .. " on the way.")
end

local function setGoalWhen(panel, spell, when, skill)
    local goal, index = Planner():FindGoal(panel.inputs, spell)
    if not index then return end
    local recipe = panel.data and panel.data.recipes and panel.data.recipes[spell]
    local fallback = skill or goal.skill
        or (recipe and recipe.skills and Planner():Skills(Prices():Book(), spell, recipe)[1])
    if when == "skill" and not tonumber(fallback) then Tab:Render(panel); return end
    local caption = when
    for _, entry in ipairs(WHENS) do if entry.value == when then caption = entry.caption:lower() end end
    if when == "skill" then caption = "at skill " .. math.floor(tonumber(fallback)) end
    panel:Change("goal", function(inputs)
        local _, at = Planner():FindGoal(inputs, spell)
        if at then Planner():SetGoalWhen(inputs, at, when, fallback) end
    end, panel:RecipeName(spell) .. ": made " .. caption .. ".")
end

local function toggleGoal(panel, spell)
    local name = panel:RecipeName(spell)
    local _, index = Planner():FindGoal(panel.inputs, spell)
    if index then
        panel:Change("goal", function(inputs)
            local _, at = Planner():FindGoal(inputs, spell)
            if at then Planner():RemoveGoal(inputs, at) end
        end, "No longer making " .. name .. " on the way.")
    else
        panel:Change("goal", function(inputs) Planner():BumpGoal(inputs, spell) end,
            "Making " .. name .. " on the way: set how many and when under it.")
    end
end

-- The row's controls hand the player's changes on for the item it shows. A
-- field whose row moved on to another item has no row (dropFocus).
local function itemOf(widget)
    local row = widget.data
    return row and row.item
end

local function goalToggled(_, toggle)
    local item = itemOf(toggle)
    if item then toggleGoal(Tab.panel, item.spell) end
end
local function planPicked(value, select)
    local item = itemOf(select)
    if item then setPlanWith(Tab.panel, item.spell, value) end
end
local function countChanged(value, field)
    local item = itemOf(field)
    if item then setGoalCount(Tab.panel, item.spell, value) end
end
local function whenPicked(value, select)
    local item = itemOf(select)
    if item then setGoalWhen(Tab.panel, item.spell, value) end
end
local function skillCommitted(text, field)
    local item = itemOf(field)
    if not item then return end
    local skill = tonumber(text)
    if not skill then Tab:Render(Tab.panel); return end
    setGoalWhen(Tab.panel, item.spell, "skill", skill)
end

-- Building -----------------------------------------------------------------------

local function showPicked(value)
    Tab.filter, Tab.focus = value, nil
    Tab:Render(Tab.panel, true)
end
local function sourcePicked(value)
    Tab.source, Tab.focus = value, nil
    Tab:Render(Tab.panel, true)
end
local function stockedToggled(on)
    Tab.stocked, Tab.focus = on, nil
    Tab:Render(Tab.panel, true)
end

-- The search draws the list again once typing pauses.
local function searchTyped()
    Tab.searchSerial = (Tab.searchSerial or 0) + 1
    local serial = Tab.searchSerial
    Tab.panel.After(0.15, function()
        if serial ~= Tab.searchSerial then return end
        Tab.focus = nil
        Tab:Render(Tab.panel, true)
    end)
end

local STOCKED_TIP = function(tooltip)
    tooltip:SetText("Have materials", 1, 1, 1)
    tooltip:AddLine("Only the recipes your bags hold every reagent for, at least one craft's worth.",
        0.8, 0.8, 0.8, true)
    tooltip:AddLine("A reagent a vendor sells does not count: you can buy it. One you can make from what you"
        .. " carry, with a recipe you know (Smelting's bars too), counts as had.", 0.6, 0.6, 0.6, true)
end

function Tab:Build(panel, page)
    self.panel, self.page = panel, page
    local ui = panel:UI()

    -- The toolbar: Show, Source, Have materials, the search, and the count.
    local bar = page:Row{ gap = 8 }
    bar:Text{ "Show", style = "label" }
    self.show = bar:Select{ boxWidth = 170, options = {}, onChange = showPicked }
    self.sourceSelect = bar:Select{ boxWidth = 140, options = SOURCES, value = self.source, default = "any",
        onChange = sourcePicked }
    self.stockedToggle = bar:Toggle{ "Have materials", onChange = stockedToggled, tooltip = STOCKED_TIP }
    self.search = bar:Search{ width = 240, placeholder = "Search recipes, items made, reagents", onType = searchTyped,
        valign = "center" }
    bar:Spacer{}
    self.count = bar:Text{ "", style = "label" }

    -- The heads over the columns.
    local head = page:Row{ gap = ROW_GAP, padLeft = 11, padRight = 8 + ns.Kit.UI.SCROLLBAR + 2, height = 28 }
    local plate = head:AddTexture("BACKGROUND")
    plate:SetAllPoints(head)
    ui:Paint(plate, function(t) fill(plate, t.bandBg) end)
    head:Text{ "Recipe", style = "label", width = NAME_W }
    self.barHead = head:Text{ "Colours", style = "label", width = BAR_W }
    head:Text{ "Learned from", style = "label", width = SOURCE_W }
    head:Text{ "Profit AH / vendor", style = "label", width = PROFIT_W }
    head:Text{ "Goal", style = "label", width = GOAL_W }
    head:Text{ "Plan with it", style = "label", grow = true }

    self.list = page:List{
        grow = true, rowHeight = ROW_HEIGHT, gap = ROW_GAP,
        make = function(row) Tab:MakeRow(row) end,
        draw = function(row, item, at) Tab:DrawRow(row, item, at) end,
        onRightClick = function(item, row) Tab:RightClicked(item, row) end,
        tooltip = function(item) return Tab:RowTip(item) end,
    }

    -- The legend under the table: what a name's colour says.
    self.legendNote = page:Text{ "", style = "label" }
end

-- Once per row of the list: a recipe's columns and a goal's line, both in
-- the row; each draw shows the one its item needs.
function Tab:MakeRow(row)
    row.wash = row:AddTexture("BACKGROUND", 2)
    row.wash:SetAllPoints(row)
    row.rail = row:AddTexture("BORDER")
    row.rail:SetPoint("TOPLEFT", row, "TOPLEFT", 12, 0)
    row.rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 8)
    row.rail:SetWidth(2)
    -- The edge of a recipe the route uses.
    row.edge = row:AddTexture("BORDER")
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 3)
    row.edge:SetWidth(3)

    -- A recipe.
    row.name = row:Text{ "", width = NAME_W }
    row.bars = row:Spacer{ size = BAR_W }
    row.bed = row:AddTexture("BORDER")
    row.bed:SetPoint("LEFT", row.bars, "LEFT", 0, 0)
    row.bed:SetSize(BAR_W, 6)
    row.bands = {}
    for index = 1, 4 do
        local band = row:AddTexture("ARTWORK")
        band:SetHeight(6)
        row.bands[index] = band
    end
    row.source = row:Text{ "", width = SOURCE_W }
    row.profit = row:Text{ "", width = PROFIT_W }
    row.goal = row:Toggle{ "", width = GOAL_W, data = row, onChange = goalToggled,
        tooltip = "Make some on the way: how many and when go on the line under it" }
    row.plan = row:Select{ boxWidth = 160, default = "auto", options = PLAN_PLAIN, data = row, onChange = planPicked }

    -- A goal's line.
    row.indent = row:Spacer{ size = 16 }
    row.makeLabel = row:Text{ "Make", style = "label" }
    row.count = row:NumberInput{ min = 1, max = 999, boxWidth = 44, help = "", data = row, onChange = countChanged,
        valign = "center" }
    row.whenLabel = row:Text{ "When", style = "label" }
    row.when = row:Select{ boxWidth = 180, options = WHENS, data = row, onChange = whenPicked }
    row.skill = row:Input{ width = 52, numeric = true, placeholder = "skill", data = row, onChange = skillCommitted,
        valign = "center" }
    row.note = row:Text{ "", grow = true }
    row.recipeParts = { row.name, row.bars, row.source, row.profit, row.goal, row.plan }
    row.goalParts = { row.indent, row.makeLabel, row.count, row.whenLabel, row.when, row.note }
end

-- A field that shows another recipe's goal drops what was typed in it
-- without committing: it was meant for the recipe that left.
local function dropFocus(field)
    if field:HasFocus() then
        field.data = nil
        field:ClearFocus()
    end
end

-- Draws the four bands of a recipe on the rows' scale, skill levels `low` to
-- `high` across the bar.
local function drawBands(row, skills, context)
    local low, high = context.low, context.high
    local span = math.max(1, high - low)
    local function x(value) return math.max(0, math.min(BAR_W, BAR_W * (value - low) / span)) end
    local edges = { skills[1], skills[2], skills[3] or skills[2], skills[4], math.max(high, skills[4]) }
    local colors = context.bands
    for index, band in ipairs(row.bands) do
        local left, right = x(edges[index]), x(edges[index + 1])
        if right - left >= 1 then
            fill(band, colors[index])
            band:ClearAllPoints()
            band:SetPoint("LEFT", row.bars, "LEFT", left, 0)
            band:SetWidth(right - left)
            band:Show()
        else
            band:Hide()
        end
    end
end

-- The rows' scale for the bands: from the lower of your skill and the first
-- learn skill in view, to a little past the target, so a skill is more than a
-- pixel and both marks sit inside the bar.
function Tab:BandScale(first)
    local view = self.list:GetView()
    local context = self.context
    local skill, target = context.skill, context.target
    local low = skill
    local last = math.min(#view, first + self.list:ScrollView() - 1)
    for index = first, last do
        local item = view[index]
        if item.kind == "recipe" then low = math.min(low, item.entry.skills[1]) end
    end
    low = math.max(0, low)
    local high = math.max(target, skill + 1)
    high = high + math.max(5, math.ceil((high - low) * 0.08))
    context.low, context.high = low, high
    self.barHead:SetText("Colours, " .. low .. " to " .. high)
end

-- The source column's words: "known" in the done colour, or where it is
-- learned and what that costs; a recipe off for a material says which.
local function sourceText(panel, entry)
    if entry.avoids then return "needs " .. panel:ItemName(entry.avoids), "warning" end
    if entry.known then return "known", "done" end
    local words = SOURCE_TEXT[entry.source] or tostring(entry.source)
    if (entry.source == "trainer" or entry.source == "vendor") and entry.cost and entry.cost > 0 then
        words = words .. ", " .. panel:Money(entry.cost)
    end
    local forever = entry.recipe.forever
    if forever == "new" or forever == "changed" then words = words .. ", " .. forever end
    return words, "muted"
end

function Tab:DrawRow(row, item, at)
    local panel = self.panel
    if at == self.list:ScrollAt() + 1 then self:BandScale(at) end
    local t = panel:UI().tokens
    local entry = item.entry
    local spell = entry.spell
    local goalLine = item.kind == "goal"
    if row.shownSpell ~= spell or row.shownKind ~= item.kind then
        dropFocus(row.count)
        dropFocus(row.skill)
        row.shownSpell, row.shownKind = spell, item.kind
    end
    for _, part in ipairs(row.recipeParts) do part:SetShown(not goalLine) end
    for _, part in ipairs(row.goalParts) do part:SetShown(goalLine) end
    row.bed:SetShown(not goalLine)
    row.rail:SetShown(goalLine)
    row.edge:SetShown(not goalLine and entry.use ~= nil)
    local context = self.context
    local inputs = panel.inputs or {}

    if goalLine then
        for _, band in ipairs(row.bands) do band:Hide() end
        local goal = entry.goal
        fill(row.rail, t.warning)
        row.wash:SetColorTexture(0, 0, 0, 0)
        if not row.count:HasFocus() then row.count:SetValue(goal.count or 1) end
        local when = goal.when or "best"
        row.when:SetValue(when)
        row.skill:SetShown(when == "skill")
        if not row.skill:HasFocus() then row.skill:SetText(goal.skill and tostring(goal.skill) or "") end
        local problem = context.problems[spell]
        row.note:SetText(problem or context.notes[spell] or "Kept, not sold")
        row.note:SetColor(problem and "warning" or "muted")
        row.count.data, row.skill.data = row, row
        return
    end

    local mode = Planner():PlanWith(inputs, spell)
    local never = mode == "never" or entry.avoids ~= nil
    local pattern = not entry.known and PATTERN_SOURCES[entry.source] and true or false
    row.name:SetText(entry.name)
    local difficulty = SkillUp():Color(entry.skills, context.skill)
    -- A pattern the character lacks (and has not said they have) is in the
    -- pattern colour, as the Plan tab marks the steps that need one; its bar
    -- still shows how hard it is.
    local nameColor = panel:DifficultyColor(difficulty) or t.text
    if never then nameColor = t.muted
    elseif difficulty == "unknown" then nameColor = t.muted45 end
    row.name:SetColor(nameColor)
    fill(row.bed, t.text, 0.05)
    drawBands(row, entry.skills, context)
    local words, color = sourceText(panel, entry)
    row.source:SetText(words)
    row.source:SetColor(color)
    local profit = entry.profit
    if profit then
        row.profit:SetText(profitWords(panel, profit.ah) .. " / " .. profitWords(panel, profit.vendor)
            .. (profit.estimated and " ~" or ""))
    else
        row.profit:SetText("")
    end
    fill(row.edge, t.accent)
    row.goal:SetValue(entry.goal ~= nil)
    row.plan:SetOptions(pattern and PLAN_OFFERED or PLAN_PLAIN)
    row.plan:SetValue(mode)
    -- Never used: the row dims, the choice that brings it back stays clear.
    local alpha = never and NEVER_ALPHA or 1
    for _, part in ipairs({ row.name, row.source, row.profit, row.goal }) do part:SetAlpha(alpha) end
    for _, band in ipairs(row.bands) do band:SetAlpha(alpha) end

    if spell == self.focus then
        fill(row.wash, t.accent, 0.12)
    elseif pattern and mode ~= "have" and not never then
        -- A pattern the character lacks: a pink background, as on Plan.
        fill(row.wash, t.pattern, 0.11)
    elseif entry.use then
        -- In the route: an accent wash under the accent edge.
        fill(row.wash, t.accent, 0.06)
    else
        row.wash:SetColorTexture(0, 0, 0, 0)
    end
end

-- Drawing ---------------------------------------------------------------------------

-- Every recipe of the profession that passes Source and the search, each
-- with what the table needs, and how many each Show holds of them.
function Tab:Gather(panel)
    local inputs = panel.inputs or {}
    local live = panel.live or {}
    local skill = live.skill or 0
    local target = (panel.route and panel.route.target) or tonumber(inputs.target) or Tiers():MaxCap()
    local known = (panel.input and panel.input.known)
        or Planner():ResolveKnown(panel.data, live.known, live.nameOf) or {}
    local goalOf = {}
    for _, goal in ipairs(inputs.goals or {}) do goalOf[goal.spell] = goal end
    local refused, pinned, accepted = inputs.refused or {}, inputs.pinned or {}, inputs.accepted or {}
    local avoided = inputs.avoided or {}
    local uses = routeUses(panel.route)
    local ctx = panel:PriceContext()
    local search = (self.search:GetText() or ""):lower()
    local stock = self.stocked and stockOf(panel, ctx, known) or nil

    local counts, lists = {}, {}
    for _, show in ipairs(SHOWS) do counts[show[1]], lists[show[1]] = 0, {} end
    for spell, recipe in pairs(panel.data and panel.data.recipes or {}) do
        if type(recipe) == "table" and type(recipe.skills) == "table" and not recipe.sod and not recipe.helper then
            local source, cost = "start", nil
            if ctx then source, cost = Planner():RecipeSource(ctx, spell, recipe) end
            local isKnown = known[spell] or source == "start"
            local passes
            if self.source == "any" then passes = true
            elseif self.source == "known" then passes = isKnown and true or false
            else passes = not isKnown and source == self.source end
            if passes and self.stocked then passes = stocked(stock, recipe) end
            if passes then
                local skills = Planner():Skills(ctx and ctx.book, spell, recipe)
                local entry = { spell = spell, recipe = recipe, skills = skills, name = panel:RecipeName(spell), source = source,
                    cost = cost, known = isKnown and true or false, goal = goalOf[spell], use = uses[spell],
                    profit = profitOf(ctx, recipe),
                    avoids = Planner():AvoidedReagent(recipe, avoided) }
                if matches(panel, entry, search) then
                    local member = {
                        range = skills[1] < target and skills[4] > skill,
                        route = uses[spell] ~= nil,
                        goals = goalOf[spell] ~= nil,
                        prefer = pinned[spell] == true,
                        never = refused[spell] == true or entry.avoids ~= nil,
                        have = accepted[spell] == true,
                        all = true,
                    }
                    for key, isIn in pairs(member) do
                        if isIn then
                            counts[key] = counts[key] + 1
                            table.insert(lists[key], entry)
                        end
                    end
                end
            end
        end
    end
    return lists, counts, skill, target, search
end

-- `toTop`: the list changed under the player (a filter, the search), so the
-- table goes back to its first row.
function Tab:Render(panel, toTop)
    panel = panel or self.panel
    if not self.list then return end
    local lists, counts, skill, target, search = self:Gather(panel)

    local showList = {}
    for _, show in ipairs(SHOWS) do
        table.insert(showList, { value = show[1], caption = show[2] .. " (" .. (counts[show[1]] or 0) .. ")",
            desc = show[3] })
    end
    self.show:SetOptions(showList)
    self.show:SetValue(self.filter)
    self.sourceSelect:SetValue(self.source)
    self.stockedToggle:SetValue(self.stocked)
    self.legendNote:SetText("Names are coloured by how they craft at your skill now; muted text cannot be made yet; a "
        .. panel:Tint("pink", "pattern") .. " row needs a pattern you lack; an " .. panel:Tint("edged", "accent")
        .. " row is in the route. Profit is a craft's, its reagents bought.")

    local list = lists[self.filter] or lists.all
    table.sort(list, function(a, b)
        if a.skills[1] ~= b.skills[1] then return a.skills[1] < b.skills[1] end
        if a.name ~= b.name then return a.name < b.name end
        return a.spell < b.spell
    end)
    self.count:SetText(#list == 0 and "none" or (#list .. (#list == 1 and " recipe" or " recipes")))

    local notes, problems = goalNotes(panel)
    local t = panel:UI().tokens
    self.context = { skill = skill, target = target, low = skill, high = target, notes = notes, problems = problems,
        bands = { t.difficulty.orange, t.difficulty.yellow, t.difficulty.green, t.difficulty.grey } }

    -- The rows: each recipe, and under a goal its line.
    local rows, focusRow = {}, nil
    for _, entry in ipairs(list) do
        local row = { kind = "recipe", entry = entry }
        table.insert(rows, row)
        if entry.spell == self.focus then focusRow = row end
        if entry.goal then table.insert(rows, { kind = "goal", entry = entry }) end
    end

    if not panel.data or #list == 0 then
        local text
        if not panel.data then
            text = panel.problem or "No recipes for this profession yet."
        elseif search ~= "" then
            text = "No recipe, item made or reagent matches."
        elseif self.source ~= "any" then
            text = "No recipe from this source here."
        elseif self.stocked then
            text = "Your bags hold the materials for none of these."
        else
            text = EMPTY[self.filter] or ""
        end
        self.list:SetState("empty", text)
    else
        self.list:SetState(nil)
    end
    self.list:SetItems(rows, not toTop)
    if focusRow and self.scrollToFocus then
        self.scrollToFocus = nil
        self.list:ScrollToItem(focusRow)
    end
end

-- opts.spell: show that recipe, lit. When the chosen Show, Source or search
-- hides it, the table falls back to every recipe.
function Tab:OnShow(panel, opts)
    if not (opts and opts.spell) then return end
    self.focus, self.scrollToFocus = opts.spell, true
    if not self.list then return end
    local lists = self:Gather(panel)
    local shown = false
    for _, entry in ipairs(lists[self.filter] or {}) do
        if entry.spell == opts.spell then shown = true; break end
    end
    if not shown then
        self.filter, self.source, self.stocked = "all", "any", false
        self.search:SetText("")
    end
end

-- Another profession: its own recipes, from the top.
function Tab:OnProfession()
    self.focus = nil
    if self.list then self.list:SetItems({}, false) end
end

-- Menus and tooltips ------------------------------------------------------------------

function Tab:RightClicked(item)
    if item.kind ~= "recipe" then return end
    local panel = self.panel
    local spell = item.entry.spell
    local mode = Planner():PlanWith(panel.inputs or {}, spell)
    local entry = item.entry
    local pattern = not entry.known and PATTERN_SOURCES[entry.source] and true or false
    panel:HideTip()
    panel:UI():OpenMenu(pattern and PLAN_OFFERED or PLAN_PLAIN, { at = "cursor", current = mode,
        onChoose = function(value) setPlanWith(panel, spell, value) end })
end

function Tab:RowTip(item)
    if item.kind ~= "recipe" then return nil end
    local panel = self.panel
    local entry = item.entry
    local spell, recipe, skills = entry.spell, entry.recipe, entry.skills
    local source = entry.known and "known" or entry.source
    return function(tooltip)
        tooltip:SetText(panel:RecipeName(spell), 1, 1, 1)
        tooltip:AddLine("Orange " .. skills[1] .. ", yellow " .. skills[2] .. ", green " .. tostring(skills[3])
            .. ", grey " .. skills[4], 0.8, 0.8, 0.8)
        local where
        if source == "known" then where = "Known"
        elseif LEARN_FROM[source] then where = "Learned " .. LEARN_FROM[source]
        else where = "Known from the start" end
        if source ~= "known" and entry.cost and entry.cost > 0 then where = where .. ": " .. panel:Money(entry.cost) end
        tooltip:AddLine(where, 0.8, 0.8, 0.8, true)
        -- The recipe's own tooltip under this one has its materials and the
        -- item; only a batch of more than one is not in it.
        local made = recipe.made or { 1, 1 }
        if recipe.makes and made[2] > 1 then
            local count = made[1] == made[2] and tostring(made[1]) or (made[1] .. "-" .. made[2])
            tooltip:AddLine("Makes " .. count .. " a craft", 0.8, 0.8, 0.8)
        end
        if recipe.forever and recipe.forever ~= "unchanged" then
            tooltip:AddLine(recipe.forever == "new" and "New in Forever" or "Changed in Forever", 0.5, 0.5, 0.5)
        end
        if entry.use then panel:TipLine(tooltip, "The route: " .. entry.use, "accent") end
        local profit = entry.profit
        if profit then
            tooltip:AddDoubleLine("A craft at the auction house", profit.ah and panel:Money(math.floor(profit.ah + 0.5))
                or (profit.bound and "soulbound" or "no price"), 0.7, 0.7, 0.7, 1, 1, 1)
            tooltip:AddDoubleLine("A craft at a vendor", profit.vendor and panel:Money(math.floor(profit.vendor + 0.5))
                or "no price", 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if entry.avoids then
            panel:TipLine(tooltip, "Needs " .. panel:ItemName(entry.avoids)
                .. ", which you turned off in Materials: the route leaves it out.", "warning")
        end
        tooltip:AddLine("Right-click: plan with it.", 0.6, 0.6, 0.6)
    end, panel:TipOpts({ spell = spell, item = recipe.makes })
end

ns:RegisterModule("PlannerTabRecipes", Tab)
