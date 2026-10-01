local _, ns = ...

-- The planner's Plan tab (PROF_PLAN.md, "UI"): the route as an answer. From
-- the top:
--
--   the summary  the skill and the target to type over (Automatic keeps the
--                planner's own), Only what I have, the figures
--                (what the route costs, sells for, nets, and how many crafts
--                it takes), Check prices (while prices are guessed), how the
--                route is cut into sections, and Make
--   the table    the steps under their sections: a bar a recipe on a skill
--                axis that follows the scroll (the rows in view set its
--                range), the recipe, its crafts and its net. A recipe's
--                alts button folds open its choices: the planner's pick and
--                the other recipes that could make exactly that step, in an
--                order that does not move when one is taken; the one in use
--                says Using, the others Use this (for that step only: the
--                row then says "your pick"); a right-click gives the
--                recipe's choices; a click picks the step Make acts on (the
--                selected row) and selects its recipe in the profession
--                window
--   the gap note at the end, when the route stops short of the skill asked
--                for because no recipe the player can use gives skill there:
--                the skill, and a row for each way past it with a button that
--                takes it
--
-- Everything the planner does is Domain/ProfessionPlanner.lua; the window
-- shell (UI/Planner.lua) holds the route and the inputs and plans again on
-- every change. This file draws and hands changes back through
-- panel:Change. The table is a kit List: a screenful of rows drawn again as
-- it scrolls, so scrolling costs the rows in view and nothing more.
--
-- Ported from OpenRoad's UI/PlannerPlan.lua. Gone with the guide export:
-- Start in tracker, Stop, Save as guide and Edit saved (docs/planner-split.md);
-- Make is how the plan is worked through now. Every row is one height, as a
-- kit List's are.
local Tab = { key = "plan", caption = "Plan", open = {}, all = {} }

local function Planner() return ns.modules.ProfessionPlanner end
local function Client() return ns.modules.Client end
local function Tiers() return ns.modules.ProfessionTiers end
local function Prices() return ns.modules.Prices end
local function SkillUp() return ns.Kit.SkillUp end
local function Crafting() return ns.Kit.Crafting end

-- Geometry ---------------------------------------------------------------------

-- The table's columns, left to right in each row: the bar on the skill axis,
-- the step's skill levels, its name (taking what is left), its crafts, its net, and
-- room for the row's button.
local ROW_HEIGHT = 26
local BAR_W = 300
local RANGE_W = 58
local CRAFTS_W = 76
local NET_W = 84
local ACTION_W = 104
local ROW_GAP = 10
local BAR_H = 10

-- The rows whose skill levels set the axis (and a Make row that gives skill).
local ON_AXIS = { run = true, train = true, goal = true, way = true }
local function onAxis(model) return ON_AXIS[model.t] or (model.t == "make" and model.gain ~= nil) end
local WAYS_SHOWN = 5
-- The most choices besides the planner's pick a step lists (Planner:WaysAround's limit).
local WAYS_LIMIT = 12
local MIN_SPAN = 30

local ESTIMATE_TIP = "~ marks a guessed price: nobody has told the planner what this costs on your realm."
    .. " Correct it on the Materials tab."

-- How the route is cut into sections (Planner:Sections): the table's
-- headings, and what the Materials tab's This section lists.
local function sectionList(options)
    local defaults = Planner().defaultOptions or {}
    local per = math.floor(tonumber(options.recipesPerSection or defaults.recipesPerSection) or 1)
    local band = math.floor(tonumber(options.bandSize or defaults.bandSize) or 25)
    return {
        { value = "trip", caption = "One trip, then tiers",
            desc = "One shopping trip for everything, then a section per trainer tier" },
        { value = "tier", caption = "A section per tier", desc = "A section per trainer tier; each buys its own materials" },
        { value = "recipe", caption = per == 1 and "A section per recipe" or ("Every " .. per .. " recipes"),
            desc = "A section per recipe, or per as many as the number beside it: buy for them, make them, move on" },
        { value = "band", caption = "Every " .. band .. " skill points",
            desc = "Cut at every multiple of this many skill points (100, 150, 200 at 50)" },
    }
end

local PATTERN_BADGE = { vendor = "vendor", boe = "BoE", bop = "BoP" }
local LEARN_FROM = { trainer = "at the trainer", vendor = "from a vendor", boe = "from the auction house",
    bop = "from its pattern (bind on pickup)" }

-- Helpers --------------------------------------------------------------------------

local function round(value) return math.floor((value or 0) + 0.5) end

-- A step's identity across redraws, for the one the Make button acts on.
local function stepKey(model)
    return model.t .. ":" .. tostring(model.spell or model.item) .. ":" .. tostring(model.a)
end

local function panelOf() return Tab.panel end

local function tint(text, color) return panelOf():Tint(text, color) end

-- The pattern a row's recipe needs and the character lacks
-- (route.runs[i].needsPattern, or its learn row's), and the tag said after
-- its name: pattern, vendor / BoE / BoP.
local function patternOf(model)
    return (model.run and model.run.needsPattern) or (model.learn and model.learn.needsPattern) or nil
end
local function patternTag(mark)
    local word = mark.source == "vendor" and "vendor" or (mark.bind == "boe" and "BoE" or "BoP")
    return tint("pattern, " .. word, "muted")
end
-- The tooltip line: where the pattern comes from and what it costs.
local function patternWords(panel, mark)
    local text
    if mark.source == "vendor" then
        local seller = panel:NPCName(mark.npc)
        text = "sold by " .. (seller or "a vendor") .. (mark.cost and (" for " .. panel:Money(mark.cost)) or "")
    elseif mark.bind == "boe" then
        text = "bind on equip, from the auction house, " .. (mark.cost and ("about " .. panel:Money(mark.cost))
            or "price unknown, counted as 0")
    else
        text = "bind on pickup (a drop, quest or reputation reward): no price can be known, counted as 0"
    end
    return "Needs a pattern you lack: " .. text .. ". Right-click, I have the pattern, once you have it."
end

-- A money figure as the table and the summary show it: money made with a
-- "+" in the gain colour, a figure resting on a guessed price with "~" in the
-- estimate colour. Returns the text and its colour.
local function figure(panel, copper, estimated)
    if copper == nil then return "-", "muted" end
    local mark = estimated and " ~" or ""
    if copper < 0 then return "+" .. panel:Money(round(-copper)) .. mark, "gain" end
    return panel:Money(round(copper)) .. mark, estimated and "estimate" or "text"
end

-- "3s to 5s", "a profit of 2s to 4s", or "a profit of 2s to a cost of 1s".
local function rangeText(panel, low, high)
    if high <= 0 then return "a profit of " .. panel:Money(-high) .. " to " .. panel:Money(-low) end
    if low >= 0 then return panel:Money(low) .. " to " .. panel:Money(high) end
    return "a profit of " .. panel:Money(-low) .. " to a cost of " .. panel:Money(high)
end

local function fill(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

-- Building ---------------------------------------------------------------------------

local function targetCommitted(text) Tab:TargetCommitted(text) end
local function autoToggled(on) Tab:AutoToggled(on) end
local function carriedToggled(on) Tab:CarriedToggled(on) end
local function makeClicked() Tab:MakeNext() end
local function checkClicked() panelOf():ShowTab("materials", { show = "guessed" }) end
local function sectionsPicked(value) Tab:SectionsPicked(value) end
local function sizeCommitted(text) Tab:SizeCommitted(text) end
local function collapseClicked()
    Tab.open, Tab.all = {}, {}
    Tab.layoutWhy = "collapse-all"
    Tab:Layout()
end

function Tab:Build(panel, page)
    self.panel, self.page = panel, page
    self.open, self.all = {}, {}
    self:BuildSummary(page)
    self:BuildTable(page)
end

-- The tooltips of the target and the figures read the route when shown.
local function targetTip(tooltip) Tab:TargetTip(tooltip) end
local function costTip(tooltip) Tab:CostTip(tooltip) end
local function sellsTip(tooltip) Tab:SellsTip(tooltip) end
local function netTip(tooltip) Tab:NetTip(tooltip) end

local CARRIED_TIP = function(tooltip)
    tooltip:SetText("Only what I have", 1, 1, 1)
    tooltip:AddLine("Plan with what is in your bags, what vendors sell, and what the route makes"
        .. " from those. Nothing from the auction house, nothing gathered.", 0.8, 0.8, 0.8, true)
    tooltip:AddLine("The route goes as far as your materials do, and plans again when your bags change.",
        0.6, 0.6, 0.6, true)
end

-- A figure of the summary: its caption and value side by side, with a
-- tooltip over both. The row takes the mouse for the tooltip, so it is
-- marked as a changed frame.
local function summaryFigure(row, caption, tip)
    local ui = Tab.panel:UI()
    local box = row:Row{ gap = 6, tooltip = tip }
    if tip then box:Customize(ui.Custom.frame):EnableMouse(true) end
    box:Text{ caption, style = "label" }
    return box:Text{ "-", style = "figure" }
end

-- A thin upright line between the controls and the figures.
local function divider(row)
    local spacer = row:Spacer{ size = 1 }
    local line = spacer:AddTexture("ARTWORK")
    line:SetPoint("CENTER", spacer, "CENTER", 0, 0)
    line:SetSize(1, 22)
    Tab.panel:UI():Paint(line, function(t) line:SetColorTexture(t.border[1], t.border[2], t.border[3], 1) end)
end

function Tab:BuildSummary(page)
    -- Row one: "83 -> [300] [x] Automatic [x] Only what I have | Cost ...
    -- Sells ... Net ... Crafts ... [Check prices] [Sections] Make". There is no Replan:
    -- every change, and every event the route depends on, plans again.
    -- A fixed height: its controls are 24 at most, and the row must not
    -- take a taller measure from any of them (the client measured it about
    -- twice that, and the page opened with a band of space above and below).
    local top = page:Row{ gap = 6, height = 28 }
    self.from = top:Text{ "0", style = "title" }
    top:Text{ "->", style = "heading", color = "muted" }
    self.target = top:Input{ width = 56, numeric = true, onChange = targetCommitted, valign = "center" }
    self.auto = top:Toggle{ "Automatic", onChange = autoToggled, tooltip = targetTip }
    self.carried = top:Toggle{ "Only what I have", onChange = carriedToggled, tooltip = CARRIED_TIP }
    divider(top)
    self.figures = {
        cost = summaryFigure(top, "Cost", costTip),
        sells = summaryFigure(top, "Sells", sellsTip),
        net = summaryFigure(top, "Net", netTip),
        crafts = summaryFigure(top, "Crafts"),
    }
    top:Spacer{}
    -- Check prices, only while the route rests on guessed or missing prices.
    self.check = top:Button{ "Check prices", onClick = checkClicked,
        tooltip = "Open Materials with the prices the planner guessed or could not find first" }
    -- How the table is cut into sections, left of Make.
    self.sections = top:Select{ boxWidth = 156, options = {}, onChange = sectionsPicked,
        tooltip = "Sections: how the table is cut, and what Materials lists as this section" }
    self.size = top:Input{ width = 44, numeric = true, onChange = sizeCommitted, valign = "center" }
    self.make = top:Button{ "Make", tone = "accent", width = 140, onClick = makeClicked }


end

-- The table's head: the skill axis over the bars, and the column heads.
function Tab:BuildTable(page)
    local ui = self.panel:UI()
    local head = page:Row{ gap = ROW_GAP, padLeft = 11, padRight = 8 + ns.Kit.UI.SCROLLBAR + 2, height = 28 }
    self.head = head
    local plate = head:AddTexture("BACKGROUND")
    plate:SetAllPoints(head)
    ui:Paint(plate, function(t) fill(plate, t.bandBg) end)
    self.axis = head:Spacer{ size = BAR_W }
    self.ticks = {}
    head:Text{ "Step", style = "label", grow = true }
    head:Text{ "Crafts", style = "label", width = CRAFTS_W, justify = "RIGHT" }
    head:Text{ "Net", style = "label", width = NET_W, justify = "RIGHT" }
    local slot = head:Row{ width = ACTION_W, align = "right", gap = 0 }
    self.collapse = slot:Button{ "Collapse", height = 20, onClick = collapseClicked,
        tooltip = "Fold every step's alternatives away" }

    self.list = page:List{
        grow = true, rowHeight = ROW_HEIGHT, gap = ROW_GAP,
        make = function(row) Tab:MakeRow(row) end,
        draw = function(row, model, at) Tab:DrawRow(row, model, at) end,
        onPick = function(model) Tab:Picked(model) end,
        onRightClick = function(model, row) Tab:RightClicked(model, row) end,
        tooltip = function(model) return Tab:RowTip(model), Tab.panel:TipOpts(Tab:RowLinks(model)) end,
        empty = "Nothing planned yet.",
    }
end

-- The model ---------------------------------------------------------------------------

-- The table's rows from the route, in the order the route takes them: the
-- section headings, the recipes (with Learn when the recipe must be learned
-- first), training, goals, and Make before the step an intermediate is made
-- for. Read off Planner:Outline, so the order is the planner's own.
function Tab:BuildItems(panel)
    local route = panel.route
    local items = {}
    if not route then return items end
    local input = panel.input or { profession = panel.profession, nameOf = panel.live and panel.live.nameOf }
    local outline = Planner():Outline(route, input)
    local learnOfRun, learnOfSpell = {}, {}
    for _, row in ipairs(outline) do
        if row.kind == "learn" then
            if row.run then learnOfRun[row.run] = row
            elseif row.spell and not learnOfSpell[row.spell] then learnOfSpell[row.spell] = row end
        end
    end
    local atEnd = {}
    for _, event in ipairs(route.events or {}) do
        if event.kind == "goal" and event.atEnd then atEnd[event.spell] = true end
    end

    -- The table is cut where the Sections choice cuts: a heading for every
    -- section that holds a step, then its steps in order. A shopping section
    -- holds no steps and gets no heading.
    local heading
    local function sectionHeading(section)
        heading = { t = "tier", title = section.title, name = section.title, a = section.fromSkill or 0,
            b = section.toSkill or section.fromSkill or 0, steps = 0, crafts = 0, net = 0, estimated = false }
        table.insert(items, heading)
    end
    local sections = panel.sections
    local rows = {}
    -- A section per recipe would only repeat the recipe's own row, so that
    -- split draws no headings.
    local options = Planner():Options(panel.inputs or {})
    local oneRecipe = options.sections == "recipe" and (tonumber(options.recipesPerSection) or 1) <= 1
    if type(sections) == "table" and #sections > 0 then
        for _, section in ipairs(sections) do
            local first = not oneRecipe
            for _, element in ipairs(section.elements or {}) do
                local kind = element.row and element.row.kind
                if kind == "skillup" or kind == "goal" or kind == "make" or kind == "train" then
                    if first then table.insert(rows, { heading = section }); first = false end
                    table.insert(rows, element.row)
                end
            end
        end
    else
        rows = outline
    end
    for _, row in ipairs(rows) do
        if row.heading then sectionHeading(row.heading) end
        local kind = row.kind
        local item
        if kind == "skillup" then
            local run = row.run and route.runs[row.run]
            local learn = (row.run and learnOfRun[row.run]) or learnOfSpell[row.spell]
            if learn then learnOfSpell[row.spell] = nil end
            item = { t = "run", runIndex = row.run, run = run, spell = row.spell, item = row.item,
                a = row.skill, b = row.toSkill, expected = run and run.expected or row.count,
                low = row.low, high = row.high, net = row.cost, estimated = row.estimated, learn = learn,
                chosen = run and run.chosen or nil,
                -- Only what I have: the crafts the bags make, where they are fewer.
                carried = run and run.carriedCap and run.count or nil }
        elseif kind == "goal" then
            local learn = learnOfSpell[row.spell]
            if learn then learnOfSpell[row.spell] = nil end
            item = { t = "goal", spell = row.spell, item = row.item, a = row.skill, b = row.skill, count = row.count,
                net = row.cost, estimated = row.estimated, learn = learn, atEnd = atEnd[row.spell] }
        elseif kind == "train" then
            item = { t = "train", a = row.skill, b = row.skill, tier = row.tier, cap = row.cap, level = row.level,
                net = row.cost, costUnknown = row.costUnknown }
        elseif kind == "make" then
            -- Its parts are already in the net of the step it is made for.
            local learn = learnOfSpell[row.spell]
            if learn then learnOfSpell[row.spell] = nil end
            item = { t = "make", spell = row.spell, item = row.item, a = row.skill, b = row.toSkill or row.skill,
                count = row.count, crafts = row.crafts, gain = row.gain, forSpell = row.forSpell, cost = row.cost,
                estimated = row.estimated, learn = learn, helper = row.helper }
        end
        if item then
            table.insert(items, item)
            if heading and item.t == "make" then
                heading.crafts = heading.crafts + (item.crafts or 0)
            elseif heading and item.t ~= "train" then
                heading.steps = heading.steps + 1
                heading.crafts = heading.crafts + (item.t == "run" and (item.carried or item.expected or 0) or (item.count or 0))
                heading.net = heading.net + (item.net or 0)
                if item.estimated then heading.estimated = true end
            elseif heading and item.t == "train" then
                heading.net = heading.net + (item.net or 0)
            end
        end
    end
    -- The note on a route that stops short, and the ways past where it stops.
    local gap = route.gap
    if gap then
        table.insert(items, { t = "gap", a = gap.skill, b = gap.skill, gap = gap, wanted = route.wanted or route.target })
        for _, option in ipairs(gap.options or {}) do
            table.insert(items, { t = "gapway", a = gap.skill, b = gap.skill, option = option })
        end
    end
    return items
end

-- A recipe's name for the gap note: one the beta's data left out is named
-- by what it makes when the client does not know the spell.
local function gapRecipeName(panel, spell, makes)
    local name = panel:RecipeName(spell)
    if name == "recipe " .. tostring(spell) and makes then name = panel:ItemName(makes) end
    return name
end

-- Where a pattern of the gap note comes from, in a few words.
local function gapSource(panel, option)
    if option.source == "vendor" then
        local seller = panel:NPCName(option.npc)
        return "sold by " .. (seller or "a vendor") .. (option.cost and (" " .. panel:Money(option.cost)) or "")
    end
    if option.source == "boe" then return "BoE, auction house" .. (option.cost and (" " .. panel:Money(option.cost)) or "") end
    return "BoP, drop or quest"
end

-- Why the route cannot have a material, in words (Planner:MissingWords).
local function missingWords(panel)
    return Planner():MissingWords(panel.route and panel.route.missingWhy)
end

-- The gap note's words: its heading, or one way past the gap.
function Tab:GapText(model)
    local panel = self.panel
    if model.t == "gap" then
        local gap = model.gap
        local resumes = gap.to and (" (the next is at " .. gap.to .. ")")
            or (" (nothing you can use gives skill again below " .. tostring(model.wanted) .. ")")
        return "Stops at " .. gap.skill .. " of " .. tostring(model.wanted) .. ": no recipe you can use gives skill at "
            .. gap.skill .. resumes .. "."
    end
    local option = model.option
    local kind = option.kind
    if kind == "pattern" then
        return tint("Pattern:", "pattern") .. " " .. panel:RecipeName(option.spell) .. tint(" - " .. gapSource(panel, option)
            .. (option.continues and "" or (", but " .. missingWords(panel).part)), "muted")
    elseif kind == "refused" then
        return panel:RecipeName(option.spell) .. tint(" - you set it to Never use", "muted")
    elseif kind == "avoided" then
        return panel:RecipeName(option.spell) .. tint(" - needs " .. panel:ItemName(option.item)
            .. ", which you set to Never use", "muted")
    elseif kind == "unlearned" then
        return panel:RecipeName(option.spell) .. tint(" - needs " .. (option.item and panel:ItemName(option.item)
            or "a material") .. ", " .. missingWords(panel).which, "muted")
    elseif kind == "beyond" then
        local first = option.recipes and option.recipes[1]
        local example = first and (" (e.g. " .. gapRecipeName(panel, first.spell, first.makes)
            .. (first.item and (" needs " .. panel:ItemName(first.item)) or "") .. ")") or ""
        return option.count .. (option.count == 1 and " recipe" or " recipes") .. " left out of this beta's data because"
            .. (option.count == 1 and " its" or " their") .. " materials come from higher levels" .. example
    end
    return tostring(kind)
end

-- The button a way past the gap wears, and what it does.
local GAP_BUTTON = {
    pattern = { "I have it", "Count the pattern as in hand, and plan again past this skill level" },
    refused = { "Use it again", "Let the planner decide on this recipe again" },
    avoided = { "Allow it", "Let the planner decide on this material again" },
    unlearned = { "Price it", "Give the material a price on the Materials tab" },
    beyond = { "Plan with them", "Turn on Options, Plan past the beta's level cap: every recipe to 300 (for testing)" },
}

function Tab:TakeGapWay(option)
    local panel = self.panel
    local planner = Planner()
    local kind = option.kind
    panel:Trace("gap-way", { kind = kind, spell = option.spell, item = option.item,
        name = option.spell and panel:RecipeName(option.spell) or nil })
    local function said(text)
        return function(before, afterSummary) return text .. panel:NetChange(before, afterSummary) end
    end
    if kind == "pattern" then
        local name = panel:RecipeName(option.spell)
        panel:Change("planwith", function(inputs) planner:SetPlanWith(inputs, option.spell, "have") end,
            said("Planning with " .. name .. ": you have the pattern."))
    elseif kind == "refused" then
        local name = panel:RecipeName(option.spell)
        panel:Change("planwith", function(inputs) planner:SetPlanWith(inputs, option.spell, "auto") end,
            said("Leaving " .. name .. " to the planner."))
    elseif kind == "avoided" then
        local name = panel:ItemName(option.item)
        panel:Change("material", function(inputs) planner:SetMaterialMode(inputs, option.item, "auto") end,
            said("Leaving " .. name .. " to the planner."))
    elseif kind == "unlearned" then
        panel:ShowTab("materials", { show = "guessed" })
    elseif kind == "beyond" then
        panel:SetFullScope(true)
    end
end

-- Whether a step has any choice besides its recipe, from what the plan
-- already knows: how many other recipes give skill at all its skill levels, and
-- whether the player chose it (the planner's pick is then one). Without the
-- count every recipe gets a button, and opening it says when there is none.
function Tab:MayHaveWays(route, item)
    local run = item.runIndex and route.runs and route.runs[item.runIndex]
    if not run then return false end
    if run.chosen or run.others == nil then return true end
    return run.others > 0
end

-- The ways around one run, asked of the planner the first time and kept for
-- this route.
function Tab:Ways(route, runIndex)
    if self.waysRoute ~= route then self.waysRoute, self.waysCache = route, {} end
    local cached = self.waysCache[runIndex]
    if cached then return cached end
    local planner = Planner()
    local list = {}
    local panel = self.panel
    local tracing = panel:Tracing()
    local started = tracing and panel.Clock() or nil
    if type(planner.WaysAround) == "function" then list = planner:WaysAround(route, runIndex) or {} end
    self.waysCache[runIndex] = list
    if tracing then self:TraceWays(route, runIndex, list, panel:Since(started)) end
    return list
end

-- A choice's recipes: the planner's may be more than one.
local function waySpells(way)
    return way.spells or { way.spell }
end

-- A way's recipes by name, for a trace row that reads without the data.
function Tab:WayNames(way)
    local names = {}
    for _, spell in ipairs(waySpells(way)) do table.insert(names, self.panel:RecipeName(spell)) end
    return names
end

-- The `alts` trace row: the choices at one step, once a route (the cache
-- above keeps a second asking from tracing again).
function Tab:TraceWays(route, runIndex, list, took)
    local run = route.runs and route.runs[runIndex]
    local options = {}
    for position, way in ipairs(list) do
        table.insert(options, { position = position, kind = way.kind, spells = waySpells(way), names = self:WayNames(way),
            extra = way.extra, perPoint = way.perPoint, crafts = way.crafts, source = way.source,
            using = way.using or nil, planner = way.kind == "planner" or nil,
            needsPattern = way.needsPattern and way.needsPattern.source or nil })
    end
    self.panel:Trace("alts", { runIndex = runIndex, spell = run and run.spell,
        name = run and self.panel:RecipeName(run.spell),
        span = run and { run.fromSkill, run.toSkill } or nil, count = #list, options = options, ms = took })
end

-- The `view` trace row: what the table shows, as the player sees it - every
-- step by range and name, which are open, and under an open one its choices
-- in the order drawn (hidden ones counted). Written after a layout only when
-- it differs from the last one written, so a redraw that changes nothing adds
-- nothing.
function Tab:TraceView(list, why)
    local panel = self.panel
    if not panel:Tracing() then return end
    local rows, open, parts = {}, nil, {}
    for _, model in ipairs(list or {}) do
        local t = model.t
        if t == "tier" or t == "run" or t == "train" or t == "goal" or t == "make" then
            open = nil
            local row = { t = t, range = { model.a, model.b } }
            if t == "run" then
                row.name = panel:RecipeName(model.spell)
                row.spell = model.spell
                row.runIndex = model.runIndex
                row.open = self:OpenKey(model.a, model.b) and true or nil
                local cached = self.waysRoute == panel.route and self.waysCache and self.waysCache[model.runIndex]
                row.alts = cached and #cached or nil
                if row.open then row.choices, row.shownAll = {}, self.all[self:OpenKey(model.a, model.b)] and true or nil end
                open = row.open and row or nil
            elseif t == "tier" then
                row.name = model.name
            elseif t == "train" then
                row.name = model.tier
            elseif t == "make" then
                row.name = panel:ItemName(model.item)
                row.gain = model.gain
            else
                row.name = model.name
            end
            table.insert(rows, row)
            table.insert(parts, t .. model.a .. "-" .. model.b .. ":" .. tostring(row.spell or row.name)
                .. (row.open and "+" or ""))
        elseif t == "way" and open then
            local way = model.way
            table.insert(open.choices, { position = #open.choices + 1, kind = way.kind, names = self:WayNames(way),
                spells = waySpells(way), extra = way.extra, using = way.using or nil })
            table.insert(parts, "w" .. table.concat(waySpells(way), ",") .. (way.using and "*" or ""))
        elseif t == "more" and open then
            open.hidden = model.allShown and 0 or model.rest
            table.insert(parts, "more" .. tostring(open.hidden))
        elseif t == "gap" or t == "gapway" then
            open = nil
            local option = model.option or {}
            -- The words as drawn, without the colour codes.
            local text = self:GapText(model):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            table.insert(rows, { t = t, range = { model.a, model.b }, kind = option.kind, spell = option.spell,
                item = option.item, text = text })
            table.insert(parts, t .. model.a .. ":" .. tostring(option.kind) .. tostring(option.spell or option.count or ""))
        end
    end
    local key = table.concat(parts, "|")
    if key == self.lastView then return end
    self.lastView = key
    panel:Trace("view", { why = why, rows = rows, scroll = self.list and self.list:ScrollAt() or nil,
        axis = self.axisRange })
end

-- How many ways there are besides the one the route takes now.
local function altCount(ways)
    local count = #ways
    for _, way in ipairs(ways) do
        if way.using then return count - 1 end
    end
    return count
end

-- The flat list of rows: the items, and under every open recipe its
-- choices, in the planner's order (by cost against its own pick), which
-- does not depend on which is taken.
function Tab:Flatten(route)
    local list = {}
    local anyOpen = false
    for _, item in ipairs(self.items or {}) do
        table.insert(list, item)
        local key = item.t == "run" and item.spell and self:OpenKey(item.a, item.b)
        if key then
            local ways = self:Ways(route, item.runIndex)
            item.ways = ways
            anyOpen = true
            local count = altCount(ways)
            table.insert(list, { t = "wayhead", a = item.a, b = item.b, run = item, count = count })
            local sorted = count > 0 and ways or {}
            -- The first few, and the one in use wherever it falls, in its place.
            local shown = 0
            for index, way in ipairs(sorted) do
                if self.all[key] or index <= WAYS_SHOWN or way.using then
                    shown = shown + 1
                    table.insert(list, { t = "way", way = way, a = item.a, b = item.b, run = item })
                end
            end
            if #sorted > WAYS_SHOWN and (self.all[key] or shown < #sorted) then
                table.insert(list, { t = "more", a = item.a, b = item.b, run = item, rest = #sorted - shown,
                    allShown = self.all[key] and true or false })
            end
        end
    end
    return list, anyOpen
end

-- Rows ---------------------------------------------------------------------------------

-- The controls a row kind needs, placed by hand over the row: they come
-- and go with the row's kind, and nothing in the row moves for them.
local function altsToggled(_, button) Tab:ToggleWays(button.data.item) end
local function useClicked(button)
    local model = button.data.item
    if model and model.way and not model.way.using then Tab:UseWay(model) end
end
local function moreClicked(link)
    local model = link.data.item
    local run = model and model.run
    if not run then return end
    local openKey = Tab:OpenKey(run.a, run.b)
    if openKey then Tab.all[openKey] = not Tab.all[openKey] or nil end
    Tab.layoutWhy = "show-more " .. tostring(run.a) .. "-" .. tostring(run.b)
    Tab:Layout()
end
local function gapClicked(button)
    local model = button.data.item
    if model and model.option then Tab:TakeGapWay(model.option) end
end

-- Once per row of the list: its columns (a row stack), the wash and rail of
-- a heading or an open step it draws by hand, the step's segment bar, and
-- the buttons placed over it.
function Tab:MakeRow(row)
    local ui = self.panel:UI()
    row.axis = row:Spacer{ size = BAR_W }
    row.range = row:Text{ "", width = RANGE_W, color = "muted" }
    row.name = row:Text{ "", grow = true }
    row.crafts = row:Text{ "", width = CRAFTS_W, justify = "RIGHT" }
    row.net = row:Text{ "", width = NET_W, justify = "RIGHT" }
    -- The action column: a heading's step count, under the buttons placed
    -- over the row.
    row.aside = row:Text{ "", width = ACTION_W, justify = "RIGHT", color = "muted" }

    row.wash = row:AddTexture("BACKGROUND", 2)
    row.wash:SetAllPoints(row)
    row.rail = row:AddTexture("BORDER")
    row.rail:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.rail:SetWidth(2)
    -- Not `row.bar`, `row.bg` or `row.line`: those are the list row's own.
    -- The step's skill on the axis: a kit SegmentBar placed by hand over the
    -- axis column, as long as the step's skill range there, so it comes and
    -- goes without moving the columns.
    row.segments = ui:SegmentBar(row, { barHeight = BAR_H })
    row.segments:Hide()

    row.alts = ui:Disclosure(row, { "Alts", height = 22, data = row, onToggle = altsToggled })
    row.alts:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.use = ui:Button(row, { "Use this", height = 20, data = row, onClick = useClicked })
    row.use:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.moreLink = ui:Link(row, { "", data = row, onClick = moreClicked })
    row.moreLink:SetPoint("LEFT", row.axis, "RIGHT", ROW_GAP, 0)
    row.gapButton = ui:Button(row, { "", height = 20, data = row, onClick = gapClicked })
    row.gapButton:SetPoint("RIGHT", row, "RIGHT", -8, 0)
end

-- True for a row the live skill has left behind.
function Tab:Passed(model)
    local live = self.panel and self.panel.live or {}
    local t = model.t
    if t == "run" and live.skill then return model.b <= live.skill end
    if t == "train" and live.maxSkill and model.cap then return live.maxSkill >= model.cap end
    if t == "make" and live.skill then
        if model.gain then return model.b <= live.skill end
        return model.a < live.skill
    end
    return false
end

-- A recipe's colour where the row starts, or at the live skill when that is
-- higher: what the profession window would show for it there.
function Tab:DifficultyColor(spell, skill, noGrey)
    local panel = self.panel
    local recipe = spell and panel.data and panel.data.recipes and panel.data.recipes[spell]
    if not recipe or type(recipe.skills) ~= "table" then return nil end
    local live = panel.live and panel.live.skill or 0
    local name = SkillUp():Color(recipe.skills, math.max(skill or 0, live))
    -- A step ends where its recipe still gives skill, so its end is shown
    -- green rather than the grey the next skill may already be.
    if noGrey and name == "grey" then name = "green" end
    return panel:DifficultyColor(name)
end

-- The row's wash and rail: an open step or its choices in the accent, a
-- heading in a light grey, the gap note in the warning colour, a recipe
-- needing a pattern the character lacks in the pattern colour. The kit's
-- own wash under it shows hover and the selection (the step Make acts on).
function Tab:PaintRow(row, model)
    local t = self.panel:UI().tokens
    local kind = model.t
    local open = kind == "run" and model.spell and self:OpenKey(model.a, model.b)
    local way = kind == "way" and model.way
    local rail
    if patternOf(model) or (way and (way.needsPattern or way.kind == "pattern")) then
        fill(row.wash, t.pattern, 0.11)
    elseif open then
        fill(row.wash, t.accent, 0.07)
        rail = t.accent
    elseif kind == "way" or kind == "wayhead" or kind == "more" then
        fill(row.wash, t.accent, 0.04)
        rail = ns.Kit.UI.Faded(t, t.accent, 0.35)
    elseif kind == "gap" or kind == "gapway" then
        fill(row.wash, t.warning, kind == "gap" and 0.09 or 0.05)
        rail = t.warning
    elseif kind == "tier" then
        fill(row.wash, t.text, 0.06)
    else
        row.wash:SetColorTexture(0, 0, 0, 0)
    end
    if rail then fill(row.rail, rail); row.rail:Show() else row.rail:Hide() end
end

-- One row drawn for its model: the words, the figures, the bar. The list
-- calls it for every row in view, the first one first, so the axis for the
-- rows in view is worked out there.
function Tab:DrawRow(row, model, at)
    local panel = self.panel
    local list = self.list
    if at == list:ScrollAt() + 1 then self:UpdateAxis(at) end
    local t = model.t
    row.alts:Hide(); row.use:Hide(); row.moreLink:Hide(); row.gapButton:Hide()
    row.axis:Show(); row.range:Show(); row.name:Show()
    row.range:SetText(""); row.name:SetText(""); row.crafts:SetText(""); row.net:SetText(""); row.aside:SetText("")
    row.name:SetColor(nil); row.crafts:SetColor(nil); row.net:SetColor(nil)
    local rangeWords = (model.a == model.b) and tostring(model.a) or (tostring(model.a) .. "-" .. tostring(model.b))

    if t == "tier" then
        row.range:Hide()
        row.name:SetText(model.title or (model.name .. " " .. model.a .. "-" .. model.b))
        row.aside:SetText(model.steps .. (model.steps == 1 and " step" or " steps"))
        row.name:SetColor("accent")
        row.crafts:SetText("~" .. round(model.crafts) .. " crafts")
        row.crafts:SetColor("muted")
        local text, color = figure(panel, model.net, model.estimated)
        row.net:SetText(text); row.net:SetColor(color)
    elseif t == "run" then
        -- With only what is carried the crafts are known and the skill they
        -- end at is the guess: "35-~41".
        if panel.route and panel.route.materials == "carried" and model.a ~= model.b then
            rangeWords = tostring(model.a) .. "-~" .. tostring(model.b)
        end
        row.range:SetText(rangeWords)
        local name = panel:RecipeName(model.spell)
        local mark = patternOf(model)
        if mark then name = name .. " " .. patternTag(mark) end
        if model.learn then name = tint("Learn", "accent") .. " " .. name end
        if model.chosen then name = name .. " " .. tint("your pick", "accent") end
        row.name:SetText(name)
        local crafts = tostring(round(model.expected))
        if model.carried then
            -- What the bags make, a try at the step's last point.
            crafts = tostring(model.carried)
        elseif model.low and model.high and model.high > model.low then
            crafts = crafts .. " (" .. model.low .. "-" .. model.high .. ")"
        end
        row.crafts:SetText(crafts)
        local text, color = figure(panel, model.net, model.estimated)
        row.net:SetText(text); row.net:SetColor(color)
        if model.mayHaveWays then
            local open = self:OpenKey(model.a, model.b) and true or false
            -- The count comes with the plan (how many other recipes give skill
            -- over the step, as many as the list can hold), so every button is
            -- set in the same draw; an opened step says exactly.
            local ways = self.waysCache and self.waysRoute == panel.route and self.waysCache[model.runIndex]
            local run = panel.route and panel.route.runs and panel.route.runs[model.runIndex]
            local count = ways and altCount(ways) or (run and run.others and math.min(run.others, WAYS_LIMIT))
            if count ~= 0 or open then
                row.alts:SetText(count and (count .. (count == 1 and " alt" or " alts")) or "Alts")
                row.alts:SetOpen(open)
                row.alts:Show()
            end
        end
    elseif t == "train" then
        row.range:SetText(rangeWords)
        local detail = {}
        if model.level and model.level > 1 then table.insert(detail, "level " .. model.level) end
        if model.cap then table.insert(detail, "to " .. model.cap) end
        row.name:SetText(tint("Train", "accent") .. " " .. tostring(model.tier or panel.profession or "")
            .. (#detail > 0 and tint(" - " .. table.concat(detail, ", "), "muted") or ""))
        if model.costUnknown then
            row.net:SetText("unknown"); row.net:SetColor("warning")
        else
            local text, color = figure(panel, model.net)
            row.net:SetText(text); row.net:SetColor(color)
        end
    elseif t == "goal" then
        row.range:SetText(rangeWords)
        local recipeName = panel:RecipeName(model.spell)
        local mark = patternOf(model)
        if mark then recipeName = recipeName .. " " .. patternTag(mark) end
        local name = tint("Goal", "warning") .. " " .. round(model.count) .. " x " .. recipeName
        if model.learn then name = tint("Learn", "accent") .. " " .. name end
        if model.atEnd then name = name .. tint(" - at the end", "muted") end
        row.name:SetText(name)
        row.crafts:SetText(tostring(round(model.count)))
        local text, color = figure(panel, model.net, model.estimated)
        row.net:SetText(text); row.net:SetColor(color)
    elseif t == "make" then
        row.range:SetText(rangeWords)
        local itemName = panel:ItemName(model.item)
        local mark = patternOf(model)
        if mark then itemName = itemName .. " " .. patternTag(mark) end
        local name = tint("Make", "accent") .. " " .. round(model.count) .. " x " .. itemName
        if model.helper then name = name .. tint(" (" .. model.helper .. ")", "muted") end
        if model.learn then name = tint("Learn", "accent") .. " " .. name end
        if model.forSpell then name = name .. tint(" for " .. panel:RecipeName(model.forSpell), "muted") end
        if model.gain then name = name .. " " .. tint("+" .. model.gain .. " skill", "gain") end
        -- Made at a loss: in the estimate colour when something should be
        -- done about it.
        local loss = panel:MakeLoss(model.item)
        if loss then
            name = name .. " " .. tint(loss.kind == "free" and "- its parts sell for more" or "- cheaper to buy",
                panel:LossToAct(loss) and "estimate" or "muted")
        end
        row.name:SetText(name)
        row.crafts:SetText(tostring(round(model.crafts)))
        -- Muted: what its parts cost is part of the step after it.
        local text = figure(panel, model.cost, model.estimated)
        row.net:SetText(text); row.net:SetColor(model.estimated and "estimate" or "muted")
    elseif t == "wayhead" then
        row.range:Hide()
        if model.count == 0 then
            row.name:SetText("No alternatives: nothing else the planner may use gives skill at every skill of this step.")
        else
            row.name:SetText(model.count .. (model.count == 1 and " alternative" or " alternatives")
                .. " for this skill range, the cheapest first")
        end
        row.name:SetColor("muted")
    elseif t == "way" then
        local way = model.way
        -- Every choice is for the step's own skill levels, so they are not said again.
        -- One needing a pattern the character lacks is in the pattern colour:
        -- an unasked pattern (trainer recipes only) or one the route may use.
        local name = table.concat(self:WayNames(way), ", ")
        if way.kind == "pattern" then
            local badge = PATTERN_BADGE[way.bind] or PATTERN_BADGE[way.source] or "BoP"
            name = name .. " " .. tint("pattern, " .. badge, "muted")
        elseif way.needsPattern then
            name = name .. " " .. patternTag(way.needsPattern)
        end
        if way.kind == "planner" then name = name .. tint(" planner's pick", "muted") end
        if way.perPoint then name = name .. tint(" - " .. panel:Money(round(way.perPoint)) .. "/pt", "muted") end
        row.name:SetText(name)
        if way.crafts then row.crafts:SetText(tostring(round(way.crafts))) end
        row.crafts:SetColor("muted")
        -- What it costs against the planner's pick, whichever is in use.
        local extra = way.extra or 0
        if way.kind == "planner" then
            row.net:SetText("-"); row.net:SetColor("muted")
        elseif extra < 0 then
            row.net:SetText("saves " .. panel:Money(round(-extra))); row.net:SetColor("gain")
        else
            row.net:SetText("+" .. panel:Money(round(extra))); row.net:SetColor("muted")
        end
        local use = row.use
        if way.using then
            use:SetText("Using")
            use:SetTooltip(nil)
        else
            use:SetText("Use this")
            use:SetTooltip((way.kind == "pattern" and "Plan with this pattern: the route gets a step to get it")
                or (way.kind == "planner" and "Let the planner choose here again, and plan again")
                or "Make this recipe for this step, and plan again")
        end
        use:SetActive(way.using and true or false)
        use:Show()
    elseif t == "gap" or t == "gapway" then
        -- Across the row: the note has nothing on the axis.
        row.axis:Hide(); row.range:Hide()
        row.name:SetText((t == "gapway" and "   " or "") .. self:GapText(model))
        if t == "gap" then
            row.name:SetColor("warning")
        else
            local words = GAP_BUTTON[model.option.kind]
            -- Planning with only what is carried, a price changes nothing:
            -- the material is simply not there, and the note says so.
            local carried = model.option.kind == "unlearned" and panel.route and panel.route.missingWhy == "carried"
            if not carried then
                row.gapButton:SetText(words and words[1] or "Use")
                row.gapButton:SetTooltip(words and words[2] or nil)
                row.gapButton:Show()
            end
        end
    elseif t == "more" then
        row.range:Hide(); row.name:Hide()
        row.moreLink:SetText(model.allShown and ("Show the best " .. WAYS_SHOWN .. " only")
            or ("Show " .. model.rest .. " more alternatives"))
        row.moreLink:Show()
    end
    -- Placed by hand, the controls are sized to their captions.
    ns.Kit.UI.Fit(row.alts); ns.Kit.UI.Fit(row.use); ns.Kit.UI.Fit(row.moreLink); ns.Kit.UI.Fit(row.gapButton)

    -- Rows the skill has passed are dimmed.
    row:SetAlpha(self:Passed(model) and 0.5 or 1)
    self:PaintRow(row, model)
    self:DrawBar(row, model)
end

-- The runs of a recipe's colour over skill levels `from` to `to`: where the
-- profession window would show it orange, yellow or green (at the live skill
-- when that is higher), each piece clipped to the axis in view. A step ends
-- where its recipe still gives skill, so its end is never grey.
function Tab:ColorRuns(spell, from, to, lo, hi, out)
    local panel = self.panel
    local recipe = spell and panel.data and panel.data.recipes and panel.data.recipes[spell]
    local skills = recipe and type(recipe.skills) == "table" and recipe.skills
    local live = panel.live and panel.live.skill or 0
    local cuts = { from }
    for _, edge in ipairs(skills or {}) do
        if edge > from and edge < to then table.insert(cuts, edge) end
    end
    if live > from and live < to then table.insert(cuts, live) end
    table.sort(cuts)
    table.insert(cuts, to)
    for index = 1, #cuts - 1 do
        local a, b = math.max(cuts[index], lo), math.min(cuts[index + 1], hi)
        if b > a then
            local name = skills and SkillUp():Color(skills, math.max(cuts[index], live)) or nil
            if name == "grey" then name = "green" end
            table.insert(out, { from = a, to = b, tone = name and panel:DifficultyColor(name) or "accent" })
        end
    end
end

-- A row's bar on the axis the rows in view set, only over the skill the
-- step is made at: in its recipe's colours (a pattern the character lacks
-- as an outline in the pattern colour), a goal as a short tick where it is
-- made. Training gives no points, so it draws nothing on the axis.
local GOAL_TICK = 3

function Tab:DrawBar(row, model)
    local t = model.t
    local bar = row.segments
    local lo, hi = self.lo or 0, self.hi or 1
    local span = math.max(1, hi - lo)
    local function x(skill) return (skill - lo) / span * BAR_W end
    -- A Make row has a bar only over the skill its crafts give.
    local barred = t == "run" or t == "way" or (t == "make" and model.gain ~= nil)
    local from, to = math.max(model.a, lo), math.min(model.b or model.a, hi)
    local segments = {}
    local left, right
    if barred and to > from then
        if t == "way" and model.way.kind == "pattern" then
            table.insert(segments, { from = from, to = to, tone = "pattern", style = "outline" })
        else
            local spells = t == "way" and waySpells(model.way) or { model.spell }
            self:ColorRuns(spells[1], model.a, model.b, from, to, segments)
        end
        left, right = x(from), x(to)
    elseif t == "goal" and model.a >= lo and model.a <= hi then
        from, to = model.a, model.a + 1
        table.insert(segments, { from = from, to = to, tone = "warning" })
        left = math.min(BAR_W - GOAL_TICK, math.max(0, x(model.a) - 1))
        right = left + GOAL_TICK
    end
    if #segments == 0 then
        bar:Hide()
        return
    end
    -- Held at both ends, so the bar's length is the step's.
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", row.axis, "LEFT", left, 0)
    bar:SetPoint("RIGHT", row.axis, "LEFT", math.max(left + 1, right), 0)
    bar:SetRange(from, to)
    bar:SetSegments(segments)
    bar:Show()
end

-- Laying out -----------------------------------------------------------------------------

-- The rows again from the items: after a render, and after a step's ways
-- open or close. The table stays scrolled where it was.
function Tab:Layout()
    local route = self.panel.route
    local list, anyOpen = self:Flatten(route)
    self.rows = list
    self.makeTarget = self:MakeTarget()
    self.collapse:SetShown(anyOpen)
    self.list:SetItems(list, true)
    self.list:Select(self.makeTarget)
    if #list == 0 then self:UpdateAxis(nil) end
    self:TraceView(list, self.layoutWhy or "draw")
    self.layoutWhy = nil
end

-- The axis follows the rows in view: their lowest to highest skill, rounded
-- out to 5, never narrower than 30 skill levels, and never outside the plan's own
-- skill levels. `first` is the first row in view.
function Tab:UpdateAxis(first)
    local view = self.list:GetView()
    local head = self.axis
    if not self.maxSkill or not first then
        for _, tick in ipairs(self.ticks) do tick:Hide() end
        return
    end
    local last = math.min(#view, first + self.list:ScrollView() - 1)
    local lo, hi = math.huge, -1
    for index = first, last do
        local model = view[index]
        if onAxis(model) then
            lo = math.min(lo, model.a); hi = math.max(hi, model.b)
        end
    end
    local minSkill, maxSkill = self.minSkill or 0, self.maxSkill
    if hi < 0 then lo, hi = minSkill, maxSkill end
    lo = math.max(minSkill, math.floor((lo - 2) / 5) * 5)
    hi = math.min(maxSkill, math.ceil((hi + 2) / 5) * 5)
    if hi - lo < MIN_SPAN then
        hi = math.min(maxSkill, lo + MIN_SPAN)
        lo = math.max(minSkill, hi - MIN_SPAN)
    end
    if hi <= lo then hi = lo + 1 end
    self.axisRange = { lo, hi }
    if self.lo == lo and self.hi == hi and self.axisTokens == self.panel:UI().tokens then return end
    self.lo, self.hi = lo, hi
    self.axisTokens = self.panel:UI().tokens

    -- Ticks: both ends of the axis, and every 5, 10 or 25 skill levels
    -- between by the span shown, leaving out one that would crowd an end.
    -- In the column heads' style, on their line; the ends sit inside the
    -- axis, the rest centred on their skill.
    local span = hi - lo
    local step = span <= 40 and 5 or (span <= 90 and 10 or 25)
    local values = { lo }
    local tick = math.floor(lo / step) * step + step
    while tick < hi do
        if tick - lo >= step / 2 and hi - tick >= step / 2 then table.insert(values, tick) end
        tick = tick + step
    end
    table.insert(values, hi)
    local count = 0
    for index, value in ipairs(values) do
        count = count + 1
        local text = self.ticks[count]
        if not text then
            text = head:AddText("label")
            self.ticks[count] = text
        end
        ns.Kit.UI.ApplyStyle(text, "label", self.axisTokens)
        text:SetText(tostring(value))
        text:ClearAllPoints()
        local x = (value - lo) / span * BAR_W
        if index == 1 then
            text:SetPoint("LEFT", head, "LEFT", 0, 0)
        elseif index == #values then
            text:SetPoint("RIGHT", head, "LEFT", BAR_W, 0)
        else
            text:SetPoint("CENTER", head, "LEFT", x, 0)
        end
        text:Show()
    end
    for index = count + 1, #self.ticks do self.ticks[index]:Hide() end
end

-- Scrolls the table so the row holding `skill` is in view, with the heading
-- over it when it is its section's first row.
function Tab:ScrollToSkill(skill)
    local list = self.rows
    if not list then return end
    local chosen
    for index, model in ipairs(list) do
        if (model.t == "run" or model.t == "train" or model.t == "goal") and (model.b > skill or model.a >= skill) then
            chosen = (index > 1 and list[index - 1].t == "tier") and list[index - 1] or model
            break
        end
    end
    chosen = chosen or list[#list]
    if chosen then self.list:ScrollToItem(chosen) end
end

function Tab:ScrollToSpell(spell)
    for index, model in ipairs(self.rows or {}) do
        if model.t == "run" and model.spell == spell then
            local target = (index > 1 and self.rows[index - 1].t == "tier") and self.rows[index - 1] or model
            self.list:ScrollToItem(target)
            self.list:ScrollToItem(model)
            return true
        end
    end
    return false
end

-- Rendering ------------------------------------------------------------------------------

function Tab:OnShow(panel, opts)
    if opts and opts.spell then self.pendingSpell = opts.spell end
    if opts and opts.skill then self.pendingSkill = opts.skill end
end

-- Another profession: other recipes, so nothing stays open.
function Tab:OnProfession()
    self.open, self.all = {}, {}
    self.waysRoute, self.waysCache = nil, nil
    self.makeKey = nil
    self.toTop = true
end

-- Why the target is what it is.
function Tab:TargetReason(panel, route)
    local inputs = panel.inputs or {}
    local ceiling = route and route.ceiling
    if ceiling and ceiling.reason ~= "target" and ceiling.text then return (ceiling.text:gsub("%.$", "")) end
    if inputs.target ~= nil then return "set by you" end
    if not route then return nil end
    local tiers = Tiers()
    -- The level the route was planned at: the testing set plans past the
    -- character's own.
    local level = (panel.input and panel.input.level) or (panel.live and panel.live.level)
    for _, tier in ipairs(tiers.tiers) do
        if tier.cap > route.target and level and tier.level > level then
            return "the most you can train now: " .. tier.name .. " needs level " .. tier.level
        end
    end
    if route.target >= tiers:MaxCap() then
        return (panel.input and panel.input.fullScope) and "the highest skill level there is" or "the highest skill level on this beta"
    end
    return "the most you can train now"
end

function Tab:TargetTip(tooltip)
    tooltip:SetText("Target skill", 1, 1, 1)
    local reason = self:TargetReason(self.panel, self.panel.route)
    if reason then tooltip:AddLine("Now: " .. reason .. ".", 0.8, 0.8, 0.8, true) end
    tooltip:AddLine("Type a skill level to plan to it. Automatic plans to the most you can train now, and rises with"
        .. " your level.", 0.6, 0.6, 0.6, true)
end

function Tab:CostTip(tooltip)
    local panel = self.panel
    local route = panel.route
    local summary = route and route.summary
    tooltip:SetText("Cost", 1, 1, 1)
    tooltip:AddLine("Everything the route spends: materials at the expected number of crafts, trainer fees"
        .. " and patterns.", 0.8, 0.8, 0.8, true)
    if not summary then return end
    tooltip:AddDoubleLine("Materials", panel:Money(summary.materials or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    tooltip:AddDoubleLine("Training", panel:Money(summary.training or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    tooltip:AddDoubleLine("Learning recipes", panel:Money(summary.learning or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    local patterns = summary.patterns or 0
    if patterns > 0 then
        local unknown = summary.patternsUnknown or 0
        panel:TipLine(tooltip, "The route needs " .. patterns .. (patterns == 1 and " pattern" or " patterns")
            .. " you lack, marked pattern in the table"
            .. (unknown > 0 and ("; " .. unknown .. " of them with no known price, counted as 0") or "")
            .. ".", "pattern")
    end
    if summary.costUnknown then
        panel:TipLine(tooltip, "Some fees are not known yet and counted as 0: open the trainer's window once.", "warning")
    end
    if (summary.estimated or 0) > 0 then panel:TipLine(tooltip, ESTIMATE_TIP, "estimate") end
end

-- "a profit of 2s" or "a cost of 3s", for a net (a cost when above 0).
local function netWords(panel, net)
    if net < 0 then return "a profit of " .. panel:Money(-net) end
    return "a cost of " .. panel:Money(net)
end

function Tab:SellsTip(tooltip)
    local panel = self.panel
    local route = panel.route
    local summary = route and route.summary
    tooltip:SetText("Sells", 1, 1, 1)
    tooltip:AddLine("What the route's output sells for: each item at its best sale, the auction house less its cut"
        .. " or a vendor.", 0.8, 0.8, 0.8, true)
    if not summary then return end
    tooltip:AddDoubleLine("At its best sale", panel:Money(summary.recovered or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    tooltip:AddDoubleLine("All to a vendor", panel:Money(summary.vendorRecovered or 0), 0.7, 0.7, 0.7, 1, 1, 1)
end

function Tab:NetTip(tooltip)
    local panel = self.panel
    local route = panel.route
    local summary = route and route.summary
    tooltip:SetText("Net", 1, 1, 1)
    tooltip:AddLine("Cost less what it sells for, at the expected number of crafts. A + is money made.",
        0.8, 0.8, 0.8, true)
    if not summary then return end
    if summary.low and summary.high then
        tooltip:AddLine("At " .. tostring(route.confidence or "safe") .. " confidence it comes to "
            .. rangeText(panel, summary.low, summary.high) .. ".", 1, 1, 1, true)
    end
    if summary.vendorNet and (summary.recovered or 0) > 0 then
        tooltip:AddLine("Selling it all to a vendor instead: " .. netWords(panel, summary.vendorNet) .. ".",
            0.8, 0.8, 0.8, true)
    end
    if (summary.estimated or 0) > 0 then panel:TipLine(tooltip, ESTIMATE_TIP, "estimate") end
end

function Tab:RenderSummary(panel)
    local route = panel.route
    local inputs = panel.inputs or {}
    local options = inputs.options or {}
    local live = panel.live or {}

    self.from:SetText(tostring(live.skill or (route and route.startSkill) or 0))
    self.autoTarget = (route and inputs.target == nil) and route.target or nil
    if not self.target:HasFocus() then
        self.target:SetText(inputs.target and tostring(inputs.target) or (route and tostring(route.target)) or "")
    end
    self.auto:SetValue(inputs.target == nil)
    self.auto:SetEnabled(panel.inputs ~= nil)
    self.carried:SetValue(options.materials == "carried")
    self.carried:SetEnabled(panel.inputs ~= nil)

    -- The four figures.
    local figures = self.figures
    local function set(key, text, color)
        figures[key]:SetText(text)
        figures[key]:SetColor(color ~= "text" and color or nil)
    end
    if route and route.summary then
        local summary = route.summary
        local estimated = (summary.estimated or 0) > 0
        local text, color = figure(panel, summary.spent, estimated)
        set("cost", text, color)
        local recovered = summary.recovered or 0
        set("sells", recovered > 0 and ("+" .. panel:Money(recovered)) or "-", recovered > 0 and "gain" or "muted")
        text, color = figure(panel, summary.net, estimated)
        set("net", text, color)
        local crafts = 0
        for _, run in ipairs(route.runs or {}) do crafts = crafts + (run.carriedCap and run.count or run.expected or 0) end
        set("crafts", tostring(round(crafts)))
    else
        for _, key in ipairs({ "cost", "sells", "net", "crafts" }) do set(key, "-", "muted") end
    end

    self:RenderMake(panel)

    -- Check prices while the route rests on guesses, and how it is cut.
    local status = route and route.status or { kind = "blocked" }
    self.check:SetShown(route ~= nil and (status.kind == "estimated" or status.kind == "blocked"))

    local split = options.sections or "trip"
    local defaults = Planner().defaultOptions or {}
    self.sections:SetOptions(sectionList(options))
    self.sections:SetValue(split)
    local sized = split == "recipe" or split == "band"
    self.size:SetShown(sized)
    if not self.size:HasFocus() then
        if split == "recipe" then self.size:SetText(tostring(options.recipesPerSection or defaults.recipesPerSection or 1))
        elseif sized then self.size:SetText(tostring(options.bandSize or defaults.bandSize or 25)) end
    end
end

function Tab:Render(panel)
    self.panel = panel
    local route = panel.route
    self.maxSkill = route and math.max(route.target or 0, 1) or nil
    self.minSkill = route and math.min(route.startSkill or 0, self.maxSkill - 1) or nil
    local items = self:BuildItems(panel)
    for _, item in ipairs(items) do
        if item.t == "run" then item.mayHaveWays = route and self:MayHaveWays(route, item) or false end
    end
    self.items = items

    self:RenderSummary(panel)

    -- What the table says with no steps: why, in the planner's words.
    local empty
    if not route then
        empty = panel.problem or "Nothing planned yet."
    elseif #(route.runs or {}) == 0 and not route.gap then
        local status = route.status or {}
        empty = status.kind == "done" and "Nothing to do: you are at the target."
            or (status.text ~= "" and status.text) or "No steps."
    end
    if empty and #items == 0 then
        self.list:SetState("empty", empty)
    else
        self.list:SetState(nil)
    end

    if self.toTop then
        self.toTop = nil
        self.list:SetItems({}, false)
    end
    self:Layout()
    if self.pendingSpell then
        local spell = self.pendingSpell
        self.pendingSpell = nil
        self:ScrollToSpell(spell)
    elseif self.pendingSkill then
        local skill = self.pendingSkill
        self.pendingSkill = nil
        self:ScrollToSkill(skill)
    end
end

-- What the status strip says while nothing else is said.
function Tab:hint(panel)
    if not panel.route then return "" end
    return "Click a step to make it next. Right-click a step for its choices; its alts button shows the alternatives."
end

-- Ways --------------------------------------------------------------------------------------

-- Open steps are kept by the skill a step started at when it was opened, and
-- a step is open while its skill levels still hold that skill: a choice keeps the
-- step's skill levels, but the planner's pick of several recipes splits it, and
-- the part holding that skill stays open.
function Tab:OpenKey(a, b)
    if not a or not b then return nil end
    local found
    for key in pairs(self.open) do
        if key >= a and key < b and (not found or key < found) then found = key end
    end
    return found
end

function Tab:ToggleWays(model)
    if not model or not model.spell then return end
    local key = self:OpenKey(model.a, model.b)
    if key then
        for other in pairs(self.open) do
            if other >= model.a and other < model.b then self.open[other], self.all[other] = nil, nil end
        end
    else
        -- One step is open at a time: opening one folds the rest.
        self.open, self.all = { [model.a] = true }, {}
    end
    self.layoutWhy = (key and "collapse " or "expand ") .. tostring(model.a) .. "-" .. tostring(model.b) .. " "
        .. tostring(self.panel:RecipeName(model.spell))
    self:Layout()
end

function Tab:UseWay(model)
    local panel = self.panel
    local way = model and model.way
    if not way or way.using then return end
    local what = table.concat(self:WayNames(way), ", ")
    local range = tostring(way.fromSkill) .. "-" .. tostring(way.toSkill)
    local position
    for index, other in ipairs(model.run and model.run.ways or {}) do
        if other == way then position = index end
    end
    panel:Trace("use-way", { way = { kind = way.kind, spells = waySpells(way), names = self:WayNames(way),
        extra = way.extra, position = position },
        step = { way.fromSkill, way.toSkill }, runIndex = model.run and model.run.runIndex,
        stepName = model.run and panel:RecipeName(model.run.spell) })
    self.layoutWhy = "after use-way " .. range
    panel:Change("way", function(inputs) Planner():UseWay(inputs, way) end, function(before, afterSummary)
        local head
        if way.kind == "planner" then
            head = "The planner chooses again for " .. range .. "."
        elseif way.kind == "pattern" then
            head = "Using the pattern for " .. what .. " for " .. range .. ", with a step to get it."
        else
            head = "Using " .. what .. " for " .. range .. "."
        end
        local change = panel:NetChange(before, afterSummary)
        if change == "" and before and afterSummary then change = " The route costs the same." end
        return head .. change
    end)
end

-- The summary's controls ----------------------------------------------------------------

-- Committed on Enter, Tab or a click elsewhere. The automatic skill
-- committed unchanged stays automatic, so it rises with the level.
function Tab:TargetCommitted(text)
    local panel = self.panel
    local value = tonumber(text)
    local inputs = panel.inputs
    if not inputs then return end
    if (value and inputs.target == nil and value == self.autoTarget) or not value or value <= 0 then
        self:Render(panel)
        return
    end
    panel:Change("target", function(changed) changed.target = value end, "Target set to " .. value .. ".")
end

function Tab:AutoToggled(on)
    local panel = self.panel
    local inputs = panel.inputs
    if not inputs then return end
    if on then
        panel:Change("target", function(changed) changed.target = nil end, "Target back to automatic.")
    else
        -- Off: the target shown becomes the player's own, to type over.
        local keep = self.autoTarget or (panel.route and panel.route.target)
        if not keep then self.auto:SetValue(true); return end
        panel:Change("target", function(changed) changed.target = keep end, "Target kept at " .. keep .. ".")
        self.target:SetFocus()
    end
end

-- Only what I have: the route uses what is carried and what vendors sell,
-- as far as that goes (the `materials` option).
function Tab:CarriedToggled(on)
    local panel = self.panel
    if not panel.inputs then return end
    panel:Change("materials", function(inputs) inputs.options.materials = on and "carried" or nil end,
        function(before, afterSummary)
            return (on and "Planning with only what you have and what vendors sell."
                or "Planning with buying what is missing.") .. panel:NetChange(before, afterSummary)
        end)
end

function Tab:SectionsPicked(value)
    local panel = self.panel
    local options = panel.inputs and panel.inputs.options
    if not options or options.sections == value then return end
    options.sections = value
    panel:Changed("split")
end

function Tab:SizeCommitted(text)
    local panel = self.panel
    local value = tonumber(text)
    local options = panel.inputs and panel.inputs.options
    if not options then return end
    if options.sections == "recipe" then
        if not value or value < 1 then self:Render(panel); return end
        options.recipesPerSection = math.floor(value)
    else
        if not value or value < 5 then self.size:SetInvalid(true); return end
        options.bandSize = math.floor(value)
    end
    panel:Changed("split")
end

-- Making a step --------------------------------------------------------------------

-- What a step's Make asks the profession window for:
-- { profession, spell, item, count, untilSkill }, or nil for a row that
-- makes nothing. A run makes what is left of it from the live skill and
-- stops at its end; a Make or Goal row makes its own count.
function Tab:MakeOrder(model)
    local t = model.t
    if (t ~= "run" and t ~= "make" and t ~= "goal") or not (model.spell or model.item) then return nil end
    local panel = self.panel
    local recipe = Crafting():Recipe(panel.data, model.spell, model.item)
    local order = { profession = model.helper or panel.profession, spell = model.spell, item = model.item }
    if t == "run" then
        local skill = math.max(panel.live and panel.live.skill or 0, model.a or 0)
        local confidence = panel.route and panel.route.confidence or Planner():Options(panel.inputs or {}).confidence
        if skill >= model.b then return nil end
        order.untilSkill = model.b
        -- The skill levels the plan used: a trainer may teach it before the data's skill.
        local skills = recipe and Planner():Skills(Prices():Book(), model.spell, recipe)
        order.count = Crafting():ToSkill(recipe, skill, model.b, confidence, skills)
        -- A recipe that gives no skill somewhere between the skill now and
        -- the step's end is past its use here: the plan must be made again.
        if not order.count then
            if recipe then return nil end
            order.count = model.high or round(model.expected)
        end
        -- Only what I have: the crafts the bags make, whatever the odds.
        if model.carried then order.count = model.carried end
    elseif t == "make" then
        order.count = round(model.crafts)
    else
        -- A goal's count is crafts (Planner:GoalMade counts them off so).
        order.count = model.count
    end
    if not order.profession or not order.count or order.count <= 0 then return nil end
    return order
end

-- How many crafts the bags make by the recipe data (the window's own count
-- is not always there to be read). The bags only, as the plan counts.
function Tab:Carried(order)
    local recipe = Crafting():Recipe(self.panel.data, order.spell, order.item)
    return Crafting():CanMake(recipe, function(item) return Client():GetItemCount(item, true) end)
end

function Tab:MakeName(order)
    local panel = self.panel
    return order.item and panel:ItemName(order.item) or panel:RecipeName(order.spell)
end

-- The step Make acts on: the row clicked last, while it is not passed, else
-- the first step still to make. It is the table's selected row.
function Tab:MakeTarget()
    local first
    for _, item in ipairs(self.items or {}) do
        if not self:Passed(item) and self:MakeOrder(item) then
            if self.makeKey and stepKey(item) == self.makeKey then return item end
            first = first or item
        end
    end
    return first
end

-- A click on a step: Make acts on it next, and its recipe shows in the
-- profession window. A row that makes nothing leaves the choice as it was.
function Tab:Picked(model)
    if self:MakeOrder(model) then
        self.makeKey = stepKey(model)
        self.makeTarget = model
        self:RenderMake(self.panel)
        self:Focus(model)
    else
        self.list:Select(self.makeTarget)
    end
end

function Tab:RightClicked(model, row)
    if model.t == "run" then self:OpenRunMenu(model, row) end
end

-- The Make button: Make N, Open (the window, on the recipe), or greyed with
-- the reason on hover. It reads the open profession window each draw: it
-- makes only when that window shows the recipe and the materials for one.
function Tab:RenderMake(panel)
    local button = self.make
    local target = self.makeTarget
    local order = target and self:MakeOrder(target)
    if not order then
        -- No step to make: the route is done, or the skill ran past its
        -- steps, and the window plans again from the new skill by itself.
        button:SetText("Make")
        button:SetEnabled(false, "Nothing left to make on this route.")
        button:SetTooltip(nil)
        return
    end
    local name = self:MakeName(order)
    local found, why, other = Client():FindCraft(order.profession, order.spell, order.item)
    local carried = self:Carried(order)
    local state = Crafting():Button(order, name, found, why, other, Client():CanOpenProfession(order.profession), carried)
    -- What the button saw, once per change, for the session log.
    local seen = table.concat({ tostring(order.spell), tostring(state.mode), tostring(state.why),
        tostring(found and found.api), tostring(found and found.available), tostring(carried) }, "|")
    if seen ~= self.makeSeen then
        self.makeSeen = seen
        ns:RecordHere("prof", { event = "make", profession = order.profession, spell = order.spell, item = order.item,
            mode = state.mode, why = state.why, api = found and found.api, said = found and found.available,
            carried = carried, count = state.count })
    end
    local text
    if state.mode == "window" then text = "Make " .. state.count
    elseif state.mode == "open" then text = "Open " .. order.profession
    elseif state.why == "materials" then text = "No materials"
    elseif state.why == "missing" then text = "Not learned"
    else text = "Open " .. order.profession end
    button:SetText(text)
    local range = (target.a == target.b) and tostring(target.a) or (tostring(target.a) .. "-" .. tostring(target.b))
    local words = "The step at " .. range .. ", selected in the table: " .. tostring(state.words)
        .. " Click another step to make that one instead."
    button:SetEnabled(state.mode ~= nil, words)
    button:SetTooltip(state.mode ~= nil and words or nil)
end

-- A click on a step's row shows its recipe in the profession window:
-- selected where the window is open on it, else the window opened on it.
function Tab:Focus(model)
    local order = self:MakeOrder(model)
    if not order then return end
    local panel = self.panel
    local found, why = Client():FindCraft(order.profession, order.spell, order.item)
    if found or why == "missing" then
        if Client():FocusRecipe(order.spell, order.item) then
            panel:SetStatus(self:MakeName(order) .. " is selected in the " .. order.profession .. " window.")
        elseif why == "missing" then
            panel:SetStatus(Crafting():Why(why, order.profession), true)
        end
    elseif Client():CanOpenProfession(order.profession) then
        if Client():OpenProfession(order.profession, order.spell, order.item) then
            panel:SetStatus("Opening " .. order.profession .. " on " .. self:MakeName(order) .. ".")
        end
    end
end

-- Make: the plan made again first when the skill moved since it was made (a
-- step may be behind the player, or its recipe past its use), then the step
-- it acts on.
function Tab:MakeNext()
    local panel = self.panel
    local route = panel.route
    local live = panel.profession and panel:Live(panel.profession)
    local moved = route and live and live.skill ~= (route.skill or route.startSkill)
    if moved or (route and live and not self.makeTarget and live.skill < (route.target or 0)) then
        panel:Replan("make")
        panel:Render()
    end
    local target = self.makeTarget
    if not target then
        panel:SetStatus("Nothing left to make on this plan at " .. tostring(panel.profession) .. " "
            .. tostring(live and live.skill) .. ".", true)
        return
    end
    self:Make(target)
    if moved then
        local status = panel.statusText
        panel:SetStatus("Planned again from " .. live.skill .. ". " .. tostring(status or ""), panel.statusError)
    end
end

function Tab:Make(model)
    local order = self:MakeOrder(model)
    if not order then return end
    local panel = self.panel
    -- Shut: the first press opens the window on the recipe; the next makes.
    local found, why = Client():FindCraft(order.profession, order.spell, order.item)
    if not found and why == "closed" and Client():CanOpenProfession(order.profession) then
        if Client():OpenProfession(order.profession, order.spell, order.item) then
            panel:SetStatus(order.profession .. " is open on " .. self:MakeName(order) .. ". Press Make again to make it.")
        else
            panel:SetStatus("The game did not open " .. order.profession .. ". Open it from your spellbook.", true)
        end
        return
    end
    local count, whyNot, other = Client():Craft(order.profession, order.spell, order.item, order.count, order.untilSkill,
        self:Carried(order))
    if count then
        panel:SetStatus("Making " .. count .. " x " .. self:MakeName(order)
            .. (order.untilSkill and (", until " .. order.profession .. " " .. order.untilSkill) or "") .. ".")
    else
        panel:SetStatus(Crafting():Why(whyNot, order.profession, other), true)
    end
end

-- Tooltips ------------------------------------------------------------------------------------

-- The recipe a row is about and the item it makes, for the game's own
-- tooltips under the planner's. A way of several recipes names none.
function Tab:RowLinks(model)
    local t, spell, item = model.t, nil, nil
    if t == "run" or t == "goal" then spell = model.spell
    elseif t == "make" then spell, item = model.spell, model.item
    elseif t == "way" then spell = #waySpells(model.way) == 1 and waySpells(model.way)[1] or nil
    elseif t == "gapway" and model.option and model.option.kind ~= "beyond" then spell = model.option.spell end
    if not spell then return nil end
    local recipe = self.panel.data and self.panel.data.recipes and self.panel.data.recipes[spell]
    return { spell = spell, item = item or (recipe and recipe.makes) }
end

function Tab:RowTip(model)
    local panel = self.panel
    local t = model.t
    if t == "run" then return self:RunTip(model) end
    if t == "way" then return self:WayTip(model) end
    if t == "gapway" then return self:GapTip(model) end
    if t == "gap" then return self:GapText(model) end
    if t == "train" then
        return function(tooltip)
            tooltip:SetText("Train " .. tostring(model.tier or ""), 1, 1, 1)
            local words = {}
            if model.cap then table.insert(words, "lets you go to " .. model.cap) end
            if model.level and model.level > 1 then table.insert(words, "needs level " .. model.level) end
            if #words > 0 then tooltip:AddLine("At the trainer: " .. table.concat(words, ", ") .. ".", 0.8, 0.8, 0.8, true) end
            if model.costUnknown then
                panel:TipLine(tooltip, "Its fee is not known yet and counted as 0: open the trainer's window once.", "warning")
            end
        end
    end
    if t == "goal" then
        return function(tooltip)
            tooltip:SetText(round(model.count) .. " x " .. panel:RecipeName(model.spell), 1, 1, 1)
            tooltip:AddLine("A goal: made on the way and kept, not sold" .. (model.atEnd and ", at the end of the route." or "."),
                0.8, 0.8, 0.8, true)
            local mark = patternOf(model)
            if mark then panel:TipLine(tooltip, patternWords(panel, mark), "pattern") end
            tooltip:AddLine("Change how many and when on the Recipes tab.", 0.6, 0.6, 0.6, true)
        end
    end
    if t == "make" then
        return function(tooltip)
            tooltip:SetText(round(model.count) .. " x " .. panel:ItemName(model.item), 1, 1, 1)
            local what = model.forSpell and ("for " .. panel:RecipeName(model.forSpell)) or "on the way"
            tooltip:AddLine("Made from its parts " .. what .. ": " .. round(model.crafts)
                .. (round(model.crafts) == 1 and " craft" or " crafts") .. " at skill " .. tostring(model.a) .. ".",
                0.8, 0.8, 0.8, true)
            if model.helper then
                tooltip:AddLine("Made with " .. model.helper .. ", which you also have: they give " .. model.helper
                    .. " skill, not " .. tostring(panel.profession) .. ".", 0.6, 0.6, 0.6, true)
            elseif model.gain then
                panel:TipLine(tooltip, "They should give about +" .. model.gain .. " skill, so the grind after them is"
                    .. " that much shorter.", "gain")
            else
                tooltip:AddLine("They give no skill points at this skill level.", 0.6, 0.6, 0.6, true)
            end
            if model.cost then
                tooltip:AddLine("Its parts cost about " .. panel:Money(round(model.cost)) .. ", counted in the step it is made for.",
                    0.8, 0.8, 0.8, true)
            end
            local learn = model.learn
            if learn and learn.needsPattern then
                panel:TipLine(tooltip, patternWords(panel, learn.needsPattern), "pattern")
            elseif learn then
                local cost = learn.costUnknown and "cost unknown" or panel:Money(learn.cost or 0)
                panel:TipLine(tooltip, "Learn " .. panel:RecipeName(model.spell) .. " first, "
                    .. (LEARN_FROM[learn.source] or tostring(learn.source or "")) .. ": " .. cost .. ".", "accent")
            end
            if model.estimated then panel:TipLine(tooltip, ESTIMATE_TIP, "estimate") end
            local loss = panel:MakeLoss(model.item)
            if loss then
                local head, advice = panel:LossWords(loss)
                local color = panel:LossToAct(loss) and "estimate" or { 0.8, 0.8, 0.8 }
                panel:TipLine(tooltip, head, color)
                panel:TipLine(tooltip, advice, color)
            end
            tooltip:AddLine("Buy it instead: Get it, on the Materials tab.", 0.6, 0.6, 0.6, true)
        end
    end
    return nil
end

function Tab:GapTip(model)
    local panel = self.panel
    local option = model.option
    return function(tooltip)
        if option.kind == "pattern" then
            tooltip:SetText(panel:RecipeName(option.spell), 1, 1, 1)
            local where = gapSource(panel, option)
            tooltip:AddLine(where:sub(1, 1):upper() .. where:sub(2) .. ".", 0.8, 0.8, 0.8, true)
            if option.continues then
                panel:TipLine(tooltip, "With it in hand the route goes on past " .. model.a .. ".", "gain")
            else
                local part = missingWords(panel).part
                panel:TipLine(tooltip, part:sub(1, 1):upper() .. part:sub(2) .. ", so the route cannot use it yet.", "warning")
            end
            tooltip:AddLine("I have it: count the pattern as in hand (Recipes tab: Plan with it, I have the pattern).",
                0.6, 0.6, 0.6, true)
        elseif option.kind == "beyond" then
            tooltip:SetText("Left out of this beta's data", 1, 1, 1)
            tooltip:AddLine("Their materials are above this beta's item level, so they cannot be made here yet.",
                0.8, 0.8, 0.8, true)
            for _, row in ipairs(option.recipes or {}) do
                tooltip:AddDoubleLine(gapRecipeName(panel, row.spell, row.makes),
                    row.item and panel:ItemName(row.item) or "", 1, 1, 1, 0.7, 0.7, 0.7)
            end
            if option.count > #(option.recipes or {}) then
                tooltip:AddLine("and " .. (option.count - #option.recipes) .. " more", 0.6, 0.6, 0.6)
            end
            tooltip:AddLine("Plan with them turns on Options, Plan past the beta's level cap, for testing.",
                0.6, 0.6, 0.6, true)
        else
            tooltip:SetText(panel:RecipeName(option.spell), 1, 1, 1)
            local words = GAP_BUTTON[option.kind]
            if words then tooltip:AddLine(words[1] .. ": " .. words[2] .. ".", 0.8, 0.8, 0.8, true) end
        end
    end
end

function Tab:RunTip(model)
    local panel = self.panel
    return function(tooltip)
        local run = model.run or {}
        local data = panel.data or {}
        local recipe = data.recipes and data.recipes[model.spell]
        tooltip:SetText(panel:RecipeName(model.spell), 1, 1, 1)
        if model.carried then
            panel:TipLine(tooltip, model.carried .. (model.carried == 1 and " craft is" or " crafts are")
                .. " all your bags make, where about " .. round(model.expected) .. " would take you to "
                .. tostring(model.b) .. ": a chance at it, not a sure point. The plan is made again from wherever"
                .. " they leave you.", "accent")
        elseif panel.route and panel.route.materials == "carried" then
            panel:TipLine(tooltip, "About " .. round(model.expected) .. " crafts from what you carry, which should take"
                .. " you to about " .. tostring(model.b) .. ": the skill it reaches is the guess. The plan is made again from"
                .. " wherever they leave you.", "accent")
        end
        local fromSkill = run.fromSkill or model.a
        local chance = (recipe and SkillUp():Chance(recipe.skills, fromSkill)) or 0
        -- The recipe's own tooltip under this one has its materials and what
        -- it makes; this says why the route took it. Money only where some
        -- is spent: with free materials every figure would read 0c.
        local own = run.perCraft and (chance > 0 and run.perCraft / chance or run.perPoint or 0)
        local rivals = run.rivals or {}
        local priced = own and round(own) ~= 0
        for _, rival in ipairs(rivals) do if round(rival.perPoint or 0) ~= 0 then priced = true end end
        if own and priced then
            tooltip:AddLine("A point costs about " .. panel:Money(round(own)) .. " at skill " .. fromSkill .. " ("
                .. panel:Money(round(run.perCraft)) .. " a craft, net of what it sells for).", 0.8, 0.8, 0.8, true)
        elseif own then
            tooltip:AddLine("Its materials cost you nothing here.", 0.8, 0.8, 0.8, true)
        end
        if #rivals == 0 then
            tooltip:AddLine("Nothing else gives skill here.", 0.6, 0.6, 0.6, true)
        elseif priced then
            tooltip:AddLine("Other recipes here, per point:", 0.8, 0.8, 0.8, true)
            local cheaper = false
            for _, rival in ipairs(rivals) do
                tooltip:AddDoubleLine(panel:RecipeName(rival.spell), panel:Money(round(rival.perPoint or 0)), 1, 1, 1, 1, 1, 1)
                if own and (rival.perPoint or 0) < own then cheaper = true end
            end
            if cheaper then
                tooltip:AddLine("A cheaper point can still lose: learning it costs, or it goes grey sooner.", 0.6, 0.6, 0.6, true)
            end
        else
            local names = {}
            for _, rival in ipairs(rivals) do table.insert(names, panel:RecipeName(rival.spell)) end
            tooltip:AddLine("Also gives skill here: " .. table.concat(names, ", ") .. ".", 0.8, 0.8, 0.8, true)
        end
        local learn = model.learn
        local mark = patternOf(model)
        if mark then
            panel:TipLine(tooltip, patternWords(panel, mark), "pattern")
        elseif learn then
            local cost = learn.costUnknown and "cost unknown" or panel:Money(learn.cost or 0)
            panel:TipLine(tooltip, "Learn it first, " .. (LEARN_FROM[learn.source] or tostring(learn.source or "")) .. ": "
                .. cost .. ".", "accent")
        end
        if model.estimated then panel:TipLine(tooltip, ESTIMATE_TIP, "estimate") end
        if model.chosen then
            local stretch = Planner():ChosenAt(panel.inputs or {}, fromSkill)
            local span = stretch and (" for " .. stretch.fromSkill .. "-" .. stretch.toSkill) or ""
            panel:TipLine(tooltip, "Your pick" .. span .. ": you chose this alternative here. Right-click, Let the planner"
                .. " choose here, to undo it.", "accent")
        end
        tooltip:AddLine("Click to make it next. Right-click for choices.", 0.5, 0.5, 0.5, true)
    end
end

-- Where to get a pattern, when that is known.
local function patternSource(panel, way)
    local seller = panel:NPCName(way.npc)
    local source = way.source or way.bind
    if source == "vendor" then return "Sold by " .. (seller or "a vendor") .. (way.cost and (", " .. panel:Money(way.cost)) or "") end
    if source == "boe" then return "Bind on equip: from the auction house" .. (way.cost and (", about " .. panel:Money(way.cost)) or "") end
    if source == "bop" or way.bind == "bop" then return "Bind on pickup: only you can get it" end
    return nil
end

function Tab:WayTip(model)
    local panel = self.panel
    local way = model.way
    return function(tooltip)
        local range = tostring(way.fromSkill) .. "-" .. tostring(way.toSkill)
        local planner = way.kind == "planner"
        tooltip:SetText((planner and "The planner's pick for " or "Alternative for ") .. tostring(way.fromSkill) .. " to "
            .. tostring(way.toSkill), 1, 1, 1)
        tooltip:AddLine(table.concat(self:WayNames(way), ", "), 0.9, 0.9, 0.9, true)
        if way.perPoint then
            tooltip:AddDoubleLine("A point", panel:Money(round(way.perPoint)), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if way.crafts then tooltip:AddDoubleLine("Crafts", "about " .. round(way.crafts), 0.7, 0.7, 0.7, 1, 1, 1) end
        -- Figures are against the planner's pick, the same whichever is in use.
        local base = "the planner's pick"
        for _, other in ipairs(model.run and model.run.ways or {}) do
            if other.kind == "planner" then base = base .. " (" .. table.concat(self:WayNames(other), ", ") .. ")" end
        end
        local extra = way.extra or 0
        if planner then
            tooltip:AddLine("What the planner would make here, with every other choice of yours kept.", 0.8, 0.8, 0.8, true)
        elseif extra < 0 then
            panel:TipLine(tooltip, "Against " .. base .. ", the route would cost about " .. panel:Money(round(-extra))
                .. " less.", "gain")
        else
            tooltip:AddLine("Against " .. base .. ", the route would cost about " .. panel:Money(round(extra)) .. " more.",
                0.8, 0.8, 0.8, true)
        end
        if way.kind == "pattern" then
            local where = patternSource(panel, way)
            if where then panel:TipLine(tooltip, where .. ".", "pattern") end
        elseif way.needsPattern then
            panel:TipLine(tooltip, patternWords(panel, way.needsPattern), "pattern")
        end
        if way.using then
            panel:TipLine(tooltip, "Using: the route takes this one now.", "accent")
        elseif planner then
            tooltip:AddLine("Use this: drop your pick here and let the planner choose again for " .. range .. ".",
                0.6, 0.6, 0.6, true)
        elseif way.kind == "pattern" then
            tooltip:AddLine("Use this: count the pattern as in hand, with a step to get it, and use it for "
                .. range .. ".", 0.6, 0.6, 0.6, true)
        else
            tooltip:AddLine("Use this: make this recipe for " .. range
                .. " only; the rest of the route stays as it is.", 0.6, 0.6, 0.6, true)
        end
    end
end

-- The right-click menu ------------------------------------------------------------------------

local PLAN_WITH_WORDS = {
    auto = "Leaving %s to the planner.",
    prefer = "Preferring %s wherever it gives skill.",
    never = "Not using %s.",
    have = "Planning with %s: you have its pattern or will get it.",
}
local SALE_WORDS = {
    default = "%s: sold or kept as Options says.",
    sell = "%s: counted as sold, at the best price.",
    vendor = "%s: counted as sold to vendors only.",
    keep = "%s: kept, never counted as sold.",
}

-- Two choices at once, each a radio group: what to plan with the recipe,
-- and what becomes of what it makes; then undoing a pick, and the recipe on
-- the Recipes tab.
function Tab:OpenRunMenu(model)
    local panel = self.panel
    local inputs = panel.inputs
    if not inputs or not model.spell then return end
    local planner = Planner()
    local spell = model.spell
    local name = panel:RecipeName(spell)
    local plan = planner:PlanWith(inputs, spell)
    local list = {
        { header = "Plan with it" },
        { caption = "Planner decides", desc = "Plan with " .. name .. " when it is cheapest", group = "plan", value = "auto",
            checked = plan == "auto" },
        { caption = "Prefer it", desc = "Use it wherever it gives skill", group = "plan", value = "prefer",
            checked = plan == "prefer" },
        { caption = "Never use it", desc = "Plan the route without it", group = "plan", value = "never",
            checked = plan == "never" },
    }
    -- I have the pattern: for a recipe needing one the character lacks (and
    -- kept, to be undone, on one already said to be in hand).
    if patternOf(model) or plan == "have" then
        table.insert(list, { caption = "I have the pattern", desc = "Count it as in hand: the pattern mark goes",
            group = "plan", value = "have", checked = plan == "have" })
    end
    local itemID = model.item
    local sale
    if itemID then
        sale = planner:SaleMode(inputs, itemID)
        local itemName = panel:ItemName(itemID)
        table.insert(list, { header = "What it makes" })
        table.insert(list, { caption = "As in Options", desc = "What becomes of " .. itemName .. " follows Options",
            group = "sale", value = "default", checked = sale == "default" })
        table.insert(list, { caption = "Sold, best price", group = "sale", value = "sell", checked = sale == "sell" })
        table.insert(list, { caption = "Sold to vendors only", group = "sale", value = "vendor", checked = sale == "vendor" })
        table.insert(list, { caption = "Kept, never sold", group = "sale", value = "keep", checked = sale == "keep" })
    end
    -- Undoing a Use this: what was chosen over the step's skill levels goes.
    local fromSkill, toSkill = model.a, model.b
    local overlaps = false
    for _, stretch in ipairs(inputs.chosen or {}) do
        if fromSkill and toSkill and stretch.fromSkill < toSkill and stretch.toSkill > fromSkill then overlaps = true end
    end
    table.insert(list, { separator = true })
    table.insert(list, { caption = "Let the planner choose here", desc = "Drop your pick for this skill range",
        disabled = not overlaps or nil, reason = "You have not picked an alternative for this skill range.",
        onClick = function()
            panel:Change("chosen", function(changed) planner:ClearChosen(changed, fromSkill, toSkill) end,
                function(before, afterSummary)
                    return "The planner chooses again for " .. fromSkill .. "-" .. toSkill .. "."
                        .. panel:NetChange(before, afterSummary)
                end)
        end })
    table.insert(list, { caption = "Show in Recipes", onClick = function() panel:ShowTab("recipes", { spell = spell }) end })
    panel:UI():OpenMenu(list, { at = "cursor", onChange = function(group, value)
        if group == "plan" and value ~= plan then
            panel:Change("planwith", function(changed) planner:SetPlanWith(changed, spell, value) end,
                function(before, afterSummary)
                    return (PLAN_WITH_WORDS[value] or "%s."):format(name) .. panel:NetChange(before, afterSummary)
                end)
        elseif group == "sale" and value ~= sale then
            local itemName = panel:ItemName(itemID)
            panel:Change("sale", function(changed) planner:SetSaleMode(changed, itemID, value) end,
                function(before, afterSummary)
                    return (SALE_WORDS[value] or "%s."):format(itemName) .. panel:NetChange(before, afterSummary)
                end)
        end
    end })
end

ns:RegisterModule("PlannerTabPlan", Tab)
