local _, ns = ...

-- The profession planner window (PROF_PLAN.md, "UI"): where the player says
-- which profession, how far, what they want made on the way and what things
-- cost on their realm, and reads back the cheapest route.
--
-- This file is the window's shell and the state every tab shares. It reads
-- the client, hands the numbers to Domain/ProfessionPlanner.lua, keeps the
-- route current, and owns what every tab has in common: the window (a kit
-- Window, with the profession drop-down in its band and where the character
-- stands beside it), the tabs, and the status strip at the foot (what
-- a change just did, with Undo where it can be undone). The tabs draw
-- themselves, one file each, from NuuKit's widgets:
--
--   Plan       UI/PlanTab.lua       the route, its ways around, the Make button
--   Recipes    UI/RecipesTab.lua    every recipe, goals, what to plan with
--   Materials  UI/MaterialsTab.lua  every material: prices, how to get it, sale
--   Options    UI/OptionsTab.lua    the tuning, and the window's look
--
-- A tab is a module (PlannerTabPlan, ...) with Build(panel, page) once,
-- Render(panel) on show and after every change, and optional OnShow(panel,
-- opts), OnProfession(panel) and hint(panel) (what the strip says while it
-- has nothing else to say). It reads the panel's fields (profession, data,
-- inputs, route, input, live, sections, problem) and changes the inputs
-- through panel:Change or panel:Changed, which plan again at once.
--
-- Everything the window does is traced to the `planner` trace channel
-- (ns:Trace, kept for the last three sessions): each plan with its inputs
-- and route, each change with the inputs before and after, and the window's
-- own actions. The plan row is built once a replan, and only while the
-- trace is kept.
--
-- Unlike OpenRoad's planner, the route is not exported to a guide tracker:
-- it stands in this window, and the Plan tab's Make button works through it
-- a step at a time (docs/planner-split.md). The planner recommends; nothing
-- here buys, posts or trains, and it crafts only when the player presses
-- Make, from the profession window the player opened.
local Panel = { tab = "plan" }

-- Opens wide enough for the Plan tab's first row (the figures, Sections and
-- Make beside the target) and the Materials table's eight columns; the
-- player may make it smaller, and what does not fit is cut at the edge.
local WIDTH, HEIGHT, MIN_WIDTH, MIN_HEIGHT = 1100, 700, 900, 400

-- The tabs, in order, and the modules that draw them. A missing module
-- leaves its tab in the strip with a line saying it is not there.
local TABS = {
    { key = "plan", caption = "Plan", module = "PlannerTabPlan" },
    { key = "recipes", caption = "Recipes", module = "PlannerTabRecipes" },
    { key = "materials", caption = "Materials", module = "PlannerTabMaterials" },
    { key = "options", caption = "Options", module = "PlannerTabOptions" },
}

local function Planner() return ns.modules.ProfessionPlanner end
local function Prices() return ns.modules.Prices end
local function Client() return ns.modules.Client end
local function Tiers() return ns.modules.ProfessionTiers end

local function after(seconds, callback)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        timer.After(seconds, callback)
    else
        callback()
    end
end
Panel.After = after

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = deepCopy(child) end
    return result
end

-- A tab's error goes to the game's error handler (so a bug report sees it)
-- without stopping the window.
local function report(err)
    local handler = rawget(_G, "geterrorhandler")
    if type(handler) == "function" then pcall(handler(), err) end
end
Panel.Report = report

-- The UI and its colours --------------------------------------------------------------

function Panel:UI() return ns:GetUI() end

-- A colour of the look: a token name ("muted", "estimate") or a colour.
function Panel:Color(name)
    local t = self:UI().tokens
    if type(name) == "table" then return name end
    return ns.Kit.UI.TokenColor(t, name) or t.text
end

-- The r, g, b of a colour, for GameTooltip lines.
function Panel:RGB(name)
    local color = self:Color(name)
    return color[1], color[2], color[3]
end

-- A line of a tooltip in a colour of the look, wrapped.
function Panel:TipLine(tooltip, text, color)
    local r, g, b = self:RGB(color or "text")
    tooltip:AddLine(text, r, g, b, true)
end

-- Text in `color` inside a line of another colour; a coin's "|r" inside it
-- goes back to `color`. Drawn again on every render, so a new look shows.
function Panel:Tint(text, color)
    local open = ns.Kit.UI.ColorCode(self:Color(color))
    -- The client stacks colours (|r goes back to the one before), so the tint
    -- is closed before each colour inside it and opened again after it: a
    -- coin letter's colour ends with its letter.
    text = tostring(text):gsub("|r", "\001"):gsub("|c", "|r|c"):gsub("\001", "|r" .. open)
    return open .. text .. "|r"
end

-- A recipe's difficulty colour: the profession window's orange, yellow,
-- green and grey, flattened by the kit's look (tokens.difficulty); red for a
-- recipe that cannot be made yet.
function Panel:DifficultyColor(name)
    local difficulty = self:UI().tokens.difficulty
    if name == "unknown" then return difficulty.red end
    return difficulty[name]
end

-- Tooltips stand beside the window, level with what they are about, so they
-- never cover the rows and columns the cursor is reading. `links` ({ item,
-- spell }) adds the game's own tooltip of the recipe (or item) under it.
function Panel:Tip(owner, filler, links)
    if filler then self:UI():Tooltip(owner, filler, self:TipOpts(links)) end
end

function Panel:HideTip() self:UI():HideTooltip() end

-- The options a list's tooltip(item, row) answers with: beside the window.
function Panel:TipOpts(links)
    local opts = self.tipOpts or {}
    self.tipOpts = opts
    opts.anchor, opts.links = self.win or "ANCHOR_RIGHT", links
    return opts
end

-- Tracing ----------------------------------------------------------------------

-- A clock for how long planning takes, in milliseconds: the profiler's where
-- the client has it, else the precise one; nil where neither is (the row
-- then leaves the timing out).
local function clock()
    local profile = rawget(_G, "debugprofilestop")
    if type(profile) == "function" then
        local ok, value = pcall(profile)
        if ok and type(value) == "number" then return value end
    end
    local precise = rawget(_G, "GetTimePreciseSec")
    if type(precise) == "function" then
        local ok, value = pcall(precise)
        if ok and type(value) == "number" then return value * 1000 end
    end
    return nil
end

Panel.Clock = clock

-- Milliseconds since `started` (a clock() reading), to a hundredth; nil when
-- there was no clock.
function Panel:Since(started)
    local stopped = started and clock()
    if not stopped then return nil end
    return math.floor((stopped - started) * 100 + 0.5) / 100
end

-- True while a trace row would be kept: the big rows are only built then.
function Panel:Tracing()
    return ns.Tracing ~= nil and ns:Tracing() or false
end

-- One row on the `planner` trace channel. `data` is the caller's own table,
-- copied by the recorder; the event and the profession are added to it.
-- Returns the row (whose `d` a caller may add to afterwards), or nil.
function Panel:Trace(event, data)
    if not self:Tracing() then return nil end
    data = data or {}
    data.event = event
    if data.profession == nil then data.profession = self.profession end
    return ns:Trace("planner", data)
end

-- Names ------------------------------------------------------------------------

-- Item names come from the client's cache; one that is not there yet is asked
-- for, and the window draws again when GET_ITEM_INFO_RECEIVED says it came.
local function itemName(id)
    if not id then return nil end
    local api = Client()
    local name = api and api:GetItemName(id)
    if not name then
        if api then api:RequestItemData(id) end
        Panel.waitingForItems = true
    end
    return name
end

-- The planner's own lookup: nil while a name is unknown, so the Domain can
-- say something else.
local function nameOf(kind, id)
    if kind == "spell" then return Client():GetSpellName(id) end
    if kind == "item" then return itemName(id) end
    return nil
end
Panel.NameOf = nameOf

-- Never nil: "item 2318" until the client knows the name.
function Panel:ItemName(itemID)
    return itemName(itemID) or ("item " .. tostring(itemID))
end

function Panel:RecipeName(spell)
    local name = Client():GetSpellName(spell)
    if name then return name end
    local recipe = self.data and self.data.recipes and self.data.recipes[spell]
    if recipe and recipe.makes then return self:ItemName(recipe.makes) end
    return "recipe " .. tostring(spell)
end

-- A trainer's or vendor's name, when the recordings know it.
function Panel:NPCName(npcID)
    local api = Client()
    return npcID and api and api.GetNPCName and api:GetNPCName(npcID) or nil
end

-- Money ------------------------------------------------------------------------------

-- Money as the window shows it: the kit's, with each coin's letter in the
-- coin's colour. PlainMoney is for what the player types and the log keeps.
function Panel:Money(copper, exact) return ns.Kit.FormatMoney(copper, exact) end
function Panel:PlainMoney(copper, exact) return ns.Kit.FormatMoney(copper, exact, false) end
function Panel:ParseMoney(text) return ns.Kit.ParseMoney(text) end

-- What a change did to the route's money, for a status line: " The route
-- now costs 1g 40s more." Empty when either side has no route or nothing
-- moved.
function Panel:NetChange(before, after)
    if not before or not after or before.net == nil or after.net == nil then return "" end
    local delta = after.net - before.net
    if math.abs(delta) < 1 then return "" end
    if delta > 0 then return " The route costs " .. self:Money(delta) .. " more." end
    return " The route costs " .. self:Money(-delta) .. " less."
end

-- Live state -----------------------------------------------------------------------

function Panel:Store()
    local Config = ns.modules.Config
    return Config and Config:CharacterStore() or nil
end

-- The testing switch (Options, Testing): per character, in the planner's
-- record. On, the planner plans past the beta's cap: the full-scope recipe
-- set (Data/ProfessionsFull), Artisan training, and no level gate. Reading
-- it keeps the tiers in step, so whatever asks first sets them.
function Panel:FullScope()
    local store = self:Store()
    local on = store and store.professionPlanner and store.professionPlanner.fullScope == true or false
    local tiers = Tiers()
    if tiers and tiers.SetFullScope and tiers.fullScope ~= on then tiers:SetFullScope(on) end
    return on
end

-- Turns the switch and plans again at once. The recipe data changes under
-- the tabs, so they hear it as they hear a new profession.
function Panel:SetFullScope(on)
    local store = self:Store()
    if not store then return end
    Planner():CharacterRecord(store).fullScope = on and true or nil
    self:Trace("fullscope", { on = on and true or false })
    self:FullScope()
    self.data = self.profession and self:Data(self.profession) or nil
    self:TellTabs("OnProfession", "options")
    self:Changed("scope")
    self:SetStatus(on and "Planning past the beta's cap: every recipe to 300, Artisan, no level gate."
        or "Planning within the beta's cap again.")
end

-- A profession's recipe data: the full-scope testing set while the switch is
-- on (the beta's when that set lacks the profession), else the beta's.
-- With it come the recipes of the character's other professions that make
-- its materials (Planner:WithHelpers): Smelting's bars for Blacksmithing.
function Panel:Data(profession)
    local key = Planner():DataKey(profession)
    local all, full = ns.professionData, false
    if self:FullScope() and type(ns.professionDataFull) == "table" and ns.professionDataFull[key] then
        all, full = ns.professionDataFull, true
    end
    local data = type(all) == "table" and all[key] or nil
    if not data then return nil, false end
    return Planner():WithHelpers(data, self:Helpers(profession, all)), full
end

-- The character's other professions with recipe data in `all`, for
-- Planner:WithHelpers: each one's data, skill and known recipes.
function Panel:Helpers(profession, all)
    local api, helpers, keys = Client(), {}, {}
    local own = Planner():DataKey(profession)
    for key in pairs(all) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local name = Planner():ProfessionOfKey(key)
        local skill = key ~= own and api:GetSkillLevel(name) or nil
        if skill then
            table.insert(helpers, { profession = name, data = all[key], skill = skill,
                known = Planner():ResolveKnown(all[key], api:GetKnownRecipes(name), nameOf) })
        end
    end
    return helpers
end

-- What the client says now about a profession: the skill and the trained cap,
-- the level, the recipes the window showed, the bags.
function Panel:Live(profession)
    local api = Client()
    local skill, maxSkill = api:GetSkillLevel(profession)
    local snapshot = api:GetTradeSkillSnapshot(profession)
    -- The profession window's line is read after every craft; the skill
    -- lines may lag behind it, so the higher skill is the one to believe.
    if snapshot and snapshot.skill and (skill == nil or snapshot.skill > skill) then
        skill, maxSkill = snapshot.skill, snapshot.maxSkill or maxSkill
    end
    local level = api:Read(rawget(_G, "UnitLevel"), "player")
    return {
        learned = skill ~= nil, skill = skill or 0, maxSkill = (skill and maxSkill and maxSkill > 0) and maxSkill or nil,
        level = (type(level) == "number" and level > 0) and level or nil,
        fullScope = self:FullScope() or nil,
        known = api:GetKnownRecipes(profession),
        -- The bags only: the bank is a trip away, and a craft cannot reach it.
        bags = function(itemID) return api:GetItemCount(itemID, true) end,
        book = Prices():Book(), nameOf = nameOf,
    }
end

-- The profession the window opens on: the last one planned while the
-- character still has it, else the first in-scope profession they have,
-- else the last one planned, else Leatherworking.
function Panel:DefaultProfession()
    local store = self:Store()
    local record = store and store.professionPlanner
    local last = record and record.profession
    if last and Client():GetSkillLevel(last) ~= nil then return last end
    for _, profession in ipairs(Planner().professions) do
        if Client():GetSkillLevel(profession) ~= nil then return profession end
    end
    return last or "Leatherworking"
end

-- Tabs -------------------------------------------------------------------------------

-- Calls `method` on every tab that has it, but the one keyed `except`.
function Panel:TellTabs(method, except)
    for _, tab in ipairs(self.tabList or {}) do
        local module = tab.module
        if tab.key ~= except and module and module[method] then
            local ok, err = pcall(module[method], module, self)
            if not ok then report(err) end
        end
    end
end

-- Planning ---------------------------------------------------------------------------

function Panel:LoadProfession(profession)
    self.profession = profession
    self.data = self:Data(profession)
    local store = self:Store()
    self.inputs = store and Planner():LoadInputs(store, profession) or Planner():DefaultInputs()
    self.route, self.input, self.sections = nil, nil, nil
    self:TellTabs("OnProfession")
end

function Panel:SaveInputs()
    local store = self:Store()
    if store and self.profession and self.inputs then Planner():SaveInputs(store, self.profession, self.inputs) end
end

-- How the route is cut into sections, from the inputs: Planner:Sections'
-- `sections` and `bandSize`. The Plan tab's headings and the Materials tab's
-- "This section" follow it.
function Panel:SplitInput()
    local options = self.inputs and self.inputs.options or {}
    return { profession = self.profession, nameOf = nameOf, sections = options.sections, bandSize = options.bandSize,
        recipesPerSection = options.recipesPerSection }
end

-- What the plan row says about the route: the numbers a bug in the planner
-- shows in, not the whole route (its solver and batches are not data).
local function pick(source, keys)
    if type(source) ~= "table" then return nil end
    local out = {}
    for _, key in ipairs(keys) do out[key] = source[key] end
    return out
end

function Panel:TraceRoute(route)
    local out = {
        startSkill = route.startSkill, skill = route.skill, target = route.target, wanted = route.wanted,
        confidence = route.confidence, signature = route.signature,
        ceiling = pick(route.ceiling, { "skill", "reason", "text", "level", "tier" }),
        status = pick(route.status, { "kind", "text", "code" }),
        summary = pick(route.summary, { "spent", "recovered", "net", "materials", "training", "learning", "low", "high",
            "estimated", "estimatedShare", "costUnknown", "auctionator", "patterns", "patternsUnknown" }),
        runs = {}, events = {}, warnings = {}, suggestions = {}, shopping = {}, chosen = {},
    }
    for index, run in ipairs(route.runs or {}) do
        local row = pick(run, { "spell", "item", "fromSkill", "toSkill", "expected", "low", "high", "count", "perCraft",
            "perPoint", "matCraft", "sellCraft", "color", "chosen", "others", "estimated", "carriedCap", "committed" })
        row.index = index
        row.name = self:RecipeName(run.spell)
        if run.learn then row.learn = pick(run.learn, { "source", "cost", "costUnknown", "item", "npc" }) end
        if run.needsPattern then
            row.needsPattern = pick(run.needsPattern, { "bind", "source", "cost", "npc", "teach" })
        end
        table.insert(out.runs, row)
    end
    for _, event in ipairs(route.events or {}) do
        table.insert(out.events, pick(event, { "kind", "skill", "spell", "tier", "cap", "cost", "count", "source", "item",
            "crafts", "gain", "forSpell" }))
    end
    for _, warning in ipairs(route.warnings or {}) do
        table.insert(out.warnings, pick(warning, { "code", "text", "spell", "tier" }))
    end
    for _, suggestion in ipairs(route.suggestions or {}) do
        table.insert(out.suggestions, pick(suggestion, { "spell", "fromSkill", "toSkill", "saving", "source", "cost" }))
    end
    for _, item in ipairs(route.shopping or {}) do
        table.insert(out.shopping, pick(item, { "itemID", "count", "have", "buy", "each", "source", "estimated" }))
    end
    for _, stretch in ipairs(route.chosen or {}) do
        table.insert(out.chosen, pick(stretch, { "fromSkill", "toSkill", "spell" }))
    end
    -- The ways past where a route stops short (the note at the end of the table).
    if route.gap then
        out.gap = { skill = route.gap.skill, to = route.gap.to, options = {} }
        for _, option in ipairs(route.gap.options or {}) do
            local row = pick(option, { "kind", "spell", "item", "source", "cost", "npc", "bind", "continues", "reason",
                "count" })
            if option.spell then row.name = self:RecipeName(option.spell) end
            if option.recipes then
                row.recipes = {}
                for _, left in ipairs(option.recipes) do table.insert(row.recipes, pick(left, { "spell", "makes", "item" })) end
            end
            table.insert(out.gap.options, row)
        end
    end
    return out
end

local function countKeys(list)
    local count = 0
    for _ in pairs(list or {}) do count = count + 1 end
    return count
end

-- What the client said, as the plan row keeps it (the bags and the price
-- book are functions and tables too big to copy every plan).
local function liveTrace(live)
    return { learned = live.learned, skill = live.skill, maxSkill = live.maxSkill, level = live.level,
        fullScope = live.fullScope, known = countKeys(live.known) }
end

-- Only what I have: the crafts a planned step makes, set by the bags (a
-- Make button elsewhere, NuuRoad's through the API below, asks here), or
-- nil.
function Panel:CarriedCrafts(profession, spell, toSkill)
    local route = self.route
    if not route or self.profession ~= profession or route.materials ~= "carried" then return nil end
    for _, run in ipairs(route.runs or {}) do
        if run.carriedCap and run.spell == spell and run.toSkill == toSkill then return run.count end
    end
    return nil
end

-- What the plan read that its row does not otherwise keep, so the session
-- tools can plan it again outside the game: the known recipes as resolved,
-- the other professions' recipes it could use (data.helpers), and the count
-- in the bags of every item a recipe in the data takes or makes.
local function replayTrace(input)
    local known, bags, seen = {}, {}, {}
    for spell in pairs(input.known or {}) do table.insert(known, spell) end
    table.sort(known)
    local function count(item)
        if seen[item] then return end
        seen[item] = true
        local carried = input.bags and input.bags(item) or 0
        if carried > 0 then table.insert(bags, { item, carried }) end
    end
    for _, recipe in pairs(input.data and input.data.recipes or {}) do
        if recipe.makes then count(recipe.makes) end
        for _, reagent in ipairs(recipe.reagents or {}) do count(reagent[1]) end
    end
    table.sort(bags, function(a, b) return a[1] < b[1] end)
    return { known = known, helpers = input.data and input.data.helpers, bags = bags }
end

-- Plans the route again from the live skill, bags and inputs.
function Panel:Replan(reason)
    local profession = self.profession
    if not profession then return end
    self.data = self:Data(profession)
    self.problem = nil
    local live = self:Live(profession)
    self.live = live
    local tracing = self:Tracing()
    if not self.data then
        self.route, self.input, self.sections = nil, nil, nil
        self.problem = "No recipes for " .. profession .. " yet in this version of NuuProfessions."
        if tracing then
            self:Trace("plan", { reason = reason, data = false, problem = self.problem, live = liveTrace(live),
                fullScope = live.fullScope or false, inputs = self.inputs })
        end
        return
    end
    local input = Planner():MakeInput(profession, self.data, self.inputs, live)
    -- The step made from the bags, kept for this session (Planner:Plan's
    -- input.committed): not saved, a /reload finds it again from the bags.
    local committed = self.committed
    input.committed = committed and committed.profession == profession and committed.spell or nil
    -- The status sentence names items and recipes with the window's names.
    input.nameOf = input.nameOf or nameOf
    -- The full-scope set, for the note on a route that stops short: which
    -- recipes the beta's data left out.
    local full = ns.professionDataFull
    if not input.fullScope and type(full) == "table" then input.fullData = full[Planner():DataKey(profession)] end
    self.input = input
    local started = tracing and clock() or nil
    local ok, route = pcall(Planner().Plan, Planner(), input)
    local took = self:Since(started)
    if not ok then
        self.route, self.sections = nil, nil
        self.problem = "The planner could not plan this: " .. tostring(route)
        ns:Log("planner: " .. tostring(route))
        if tracing then
            self:Trace("plan-failed", { reason = reason, error = tostring(route), live = liveTrace(live),
                fullScope = live.fullScope or false, inputs = self.inputs, ms = took })
        end
        return
    end
    self.route = route
    self.committed = route.committed and { profession = profession, spell = route.committed } or nil
    local split, sections = pcall(Planner().Sections, Planner(), route, self:SplitInput())
    self.sections = split and sections or {}
    if not split then ns:Log("planner: sections failed: " .. tostring(sections)) end
    -- The shopping list keeps what this plan buys, to show with the window shut.
    local list = ns.modules.ShoppingList
    if list then
        local kept, err = pcall(list.Keep, list, profession, route, self.sections)
        if not kept then report(err) end
    end
    -- And what it learns at a trainer, for the strip under the trainer's window.
    local training = ns.modules.TrainerTraining
    if training then
        local kept, err = pcall(training.Keep, training, profession, route, self.data)
        if not kept then report(err) end
    end
    if tracing then
        local traced, row = pcall(self.TraceRoute, self, route)
        if not traced then report(row) end
        self:Trace("plan", { reason = reason, data = true, profession = profession, live = liveTrace(live),
            fullScope = live.fullScope or false,
            inputs = self.inputs,
            input = { level = input.level, known = countKeys(input.known), target = input.target, skill = input.skill,
                maxSkill = input.maxSkill },
            replay = replayTrace(input),
            route = traced and row or nil, ms = took, sections = #self.sections,
            sectionsFailed = not split and tostring(sections) or nil })
    end
    ns:Record("prof", { event = "plan", profession = profession, reason = reason, skill = live.skill, target = route.target,
        net = route.summary.net, runs = #route.runs, suggestions = #route.suggestions,
        status = route.status and route.status.kind, split = self.inputs.options.sections })
    self:CheckColors()
end

-- The table's colour for each recipe of the route against the one the
-- profession window showed, at the skill the window showed; a disagreement is
-- logged to the `prof` channel by the client adapter.
function Panel:CheckColors()
    local api = Client()
    local snapshot = api:GetTradeSkillSnapshot(self.profession)
    if not snapshot or not self.route then return end
    local skill = snapshot.skill or (self.live and self.live.skill) or 0
    for _, check in ipairs(Planner():ColorChecks(self.route, self.data, skill)) do
        local shown = api:CompareRecipeColor(self.profession, check.spell, check.expected)
        if shown == nil and check.item then api:CompareRecipeColor(self.profession, "item:" .. check.item, check.expected) end
    end
end

-- An input changed: keep it, plan again, draw again. What the status strip
-- said was about the last change, so it goes; a caller with something to say
-- about this one (and an Undo) sets it after, as Change does.
function Panel:Changed(reason)
    self.statusText, self.statusError, self.statusUndo = nil, nil, nil
    self:SaveInputs()
    self:Replan(reason or "inputs")
    self:Render()
end

-- One change the player can take back: the inputs are copied whole, `fn`
-- changes them, the route is planned again, and the status strip says
-- `message` (a string, or function(before, after) given the route summaries
-- before and after) with Undo putting the copy back.
function Panel:Change(reason, fn, message)
    if not self.inputs then return end
    local snapshot = deepCopy(self.inputs)
    local profession = self.profession
    local before = self.route and self.route.summary
    fn(self.inputs)
    -- Traced before the replan, so the change reads ahead of the plan it
    -- made; what the strip said is added to the row once it is known.
    local traced = self:Trace("change", { reason = reason, before = snapshot, after = self.inputs })
    self:Changed(reason)
    local text = message
    if type(message) == "function" then
        local ok, said = pcall(message, before, self.route and self.route.summary)
        text = ok and said or nil
        if not ok then report(said) end
    end
    if traced and type(traced.d) == "table" then
        -- Plain text, as the log keeps it: the coin colours come off.
        traced.d.message = tostring(text or "Changed."):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    self:SetStatus(text or "Changed.", false, function()
        -- A profession switch drops the strip, so this is the same profession.
        if self.profession ~= profession then return end
        self.inputs = snapshot
        self:Trace("undo", { reason = reason, inputs = snapshot })
        self:Changed("undo")
    end)
end

-- Making at a loss --------------------------------------------------------------------

-- What the route makes at a loss (Planner:MakeLosses), each paid one with
-- `saves`: what buying it instead saves over the whole route, from a trial
-- plan. Worked out once per route.
function Panel:MakeLosses()
    if not self.route or not self.input then return {} end
    if self.lossesRoute == self.route then return self.losses end
    local ok, list = pcall(Planner().MakeLosses, Planner(), self.route, self.input)
    if not ok then report(list); list = {} end
    local traced = {}
    for _, loss in ipairs(list) do
        if loss.kind == "paid" then loss.saves = Planner():BuyingSaves(self.input, self.route, loss.itemID) end
        table.insert(traced, { item = loss.itemID, name = self:ItemName(loss.itemID), kind = loss.kind,
            make = loss.make, worth = loss.worth, buy = loss.buy, count = loss.count, loss = loss.loss, saves = loss.saves })
    end
    if #traced > 0 then self:Trace("losses", { items = traced }) end
    self.lossesRoute, self.losses = self.route, list
    return list
end

function Panel:MakeLoss(itemID)
    for _, loss in ipairs(self:MakeLosses()) do
        if loss.itemID == itemID then return loss end
    end
end

-- Whether the player should do something about a loss: buying saves over the
-- route, or free parts would sell for more. A paid loss that the skill it
-- gives makes up for is only told, not pressed.
function Panel:LossToAct(loss)
    return loss.kind == "free" or (loss.saves ~= nil and loss.saves > 0)
end

-- A loss in words: the headline, then what to do about it.
function Panel:LossWords(loss)
    local name = self:ItemName(loss.itemID)
    local buy = self:Money(loss.buy) .. (loss.buyVia == "ah" and " at the auction house" or " at a vendor")
    if loss.kind == "free" then
        local part = loss.free and loss.free[1] and self:ItemName(loss.free[1]) or "its parts"
        return "The " .. part .. " for one " .. name .. " would sell for " .. self:Money(math.floor(loss.worth + 0.5))
            .. ", more than buying one (" .. buy .. ").",
            "The plan counts your " .. part .. " as free. Value it to weigh the sale you give up"
            .. " (about " .. self:Money(loss.loss) .. " here)."
    end
    local head = name .. " costs less to buy (" .. buy .. ") than to make (" .. self:Money(math.floor(loss.make + 0.5))
        .. " of parts each)."
    if loss.saves and loss.saves > 0 then
        return head, "Buying it instead saves about " .. self:Money(loss.saves) .. " over the route."
    elseif loss.saves then
        return head, "Making it still pays" .. (loss.gain and (": its +" .. loss.gain .. " skill") or "")
            .. " saves more than the " .. self:Money(loss.loss) .. " lost on its parts."
    end
    return head, "Set Get it to Buy to see what buying it does to the route."
end

-- Does what a loss asks: buy it instead, or value the free part.
function Panel:ActOnLoss(loss)
    local name = self:ItemName(loss.itemID)
    if loss.kind == "free" and loss.free and loss.free[1] then
        local part, partName = loss.free[1], self:ItemName(loss.free[1])
        self:Change("get", function(inputs) Planner():SetGetMode(inputs, part, "gather-valued") end,
            function(before, after) return partName .. ": gathered, valued at what it sells for." .. self:NetChange(before, after) end)
    else
        self:Change("get", function(inputs) Planner():SetGetMode(inputs, loss.itemID, "buy") end,
            function(before, after) return name .. ": bought, not made." .. self:NetChange(before, after) end)
    end
end

-- A price context with the planner's options; `everySale` values every
-- output as sold, to say what one would fetch. It makes an item with the
-- recipes the route may use, as the plan does.
function Panel:PriceContext(everySale)
    if not self.data then return nil end
    local options = Planner():Options(self.inputs)
    return Prices():Context({ book = Prices():Book(), data = self.data,
        canCraft = self.route and self.route.canCraft or nil,
        options = { auction = options.auction, gather = options.gather, get = options.get, keep = options.keep,
            nosell = options.nosell, sellOutput = not everySale and options.sellOutput or "all", sell = options.sell,
            estimateFactor = options.estimateFactor, useAuctionator = options.useAuctionator,
            carried = options.materials == "carried" and self.live and self.live.bags or nil } })
end

-- The window -----------------------------------------------------------------------------

-- The tabs as the strip lists them: the known four, each with the module
-- that draws it when that module is loaded.
function Panel:CollectTabs()
    local list, byKey = {}, {}
    for _, spec in ipairs(TABS) do
        local module = ns.modules[spec.module]
        if type(module) ~= "table" or type(module.Build) ~= "function" or type(module.Render) ~= "function" then
            module = nil
        end
        local tab = { key = spec.key, caption = spec.caption, module = module }
        table.insert(list, tab)
        byKey[spec.key] = tab
    end
    self.tabList, self.tabByKey = list, byKey
end

-- A tab's page, and what the tab builds on it. A tab that is missing, or
-- fails to build, says so there.
function Panel:BuildTab(tab)
    local page = self.win:Page(tab.key)
    tab.page = page
    local failure
    if tab.module then
        local ok, err = pcall(tab.module.Build, tab.module, self, page)
        if ok then return end
        report(err)
        failure = "This tab could not be built: " .. tostring(err)
        tab.module = nil
    end
    page:Text{ failure or "This tab is not available.", color = "muted", wrap = true }
end

local function professionPicked(value) Panel:SelectProfession(value) end
local function tabPicked(key) Panel:ShowTab(key) end

local function shoppingClicked()
    local list = ns.modules.ShoppingList
    if list then list:Toggle() end
end

local function shoppingFollows()
    local list = ns.modules.ShoppingList
    if list then list:Refresh() end
end

local function windowHidden()
    Panel:Trace("close", { tab = Panel.tab })
    Panel:HideTip()
    shoppingFollows()
end

function Panel:Build()
    if self.win then return end
    local ui = self:UI()
    local places = ns.db and ns.db.windows
    if not places then
        places = {}
        if ns.db then ns.db.windows = places end
    end
    self:CollectTabs()
    if not self.tabByKey[self.tab] then self.tab = self.tabList[1].key end
    -- The tabs in the band after the title (the kit's), each with its page.
    local tabs = { value = self.tab, onChange = tabPicked, padding = 10 }
    for index, tab in ipairs(self.tabList) do tabs[index] = { key = tab.key, caption = tab.caption } end
    local win = ui:Window({
        key = "planner", title = "Profession planner", width = WIDTH, height = HEIGHT,
        resizable = true, minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, place = places,
        status = true, hidden = true, tabs = tabs,
    })
    win:HookScript("OnHide", windowHidden)
    -- The shopping list warns while the planner is shut.
    win:HookScript("OnShow", shoppingFollows)
    self.win = win
    -- At the right of the band: the profession, and where the character
    -- stands in it.
    local header = win.header
    self.professionSelect = header:Select{ boxWidth = 180, options = {}, onChange = professionPicked,
        tooltip = "The profession to plan. Each keeps its own plan." }
    header:Spacer{ size = 6 }
    self.standing = header:Text{ "", style = "label" }
    header:Spacer{ size = 10 }
    -- Active (the selected look) while the list is up.
    local list = ns.modules.ShoppingList
    self.shoppingButton = header:Button{ "Shopping list", onClick = shoppingClicked,
        active = list and list:IsShown() or false,
        tooltip = "Shows what the plan buys in a small list of its own, which stays up with the planner shut" }
    header:Spacer{ size = 6 }

    for _, tab in ipairs(self.tabList) do self:BuildTab(tab) end

    -- Money and tints in the tabs' text are worked out from the look when
    -- drawn, so a new look draws the window again.
    ui:OnLook(function() self:Render() end)
end

-- The shopping list shown or put away: its button follows.
function Panel:ShoppingShown(shown)
    if self.shoppingButton then self.shoppingButton:SetActive(shown) end
end

-- Status -------------------------------------------------------------------------------------

-- What a change just did, or why it could not. `undo`, a function, puts an
-- Undo beside it. The next change clears it (Changed).
function Panel:SetStatus(text, isError, undo)
    self.statusText, self.statusError, self.statusUndo = text, isError, undo
    self:PaintStatus()
end

-- The strip's Undo: the message goes, then the change is taken back.
local function undoStatus()
    local undo = Panel.statusUndo
    Panel.statusText, Panel.statusError, Panel.statusUndo = nil, nil, nil
    if undo then undo() end
    Panel:PaintStatus()
end

-- With nothing to say, the strip shows the open tab's hint, muted.
function Panel:PaintStatus()
    local win = self.win
    if not win then return end
    local text = self.statusText
    if text and text ~= "" then
        local opts = self.statusOpts or {}
        self.statusOpts = opts
        opts.tone = self.statusError and "danger" or "text"
        opts.undo = self.statusUndo and undoStatus or nil
        win:Status(text, opts)
        return
    end
    local tab = self.tabByKey and self.tabByKey[self.tab]
    local hint = tab and tab.module and tab.module.hint
    if type(hint) == "function" then
        local ok, said = pcall(hint, tab.module, self)
        hint = ok and said or nil
    end
    win:Status(type(hint) == "string" and hint ~= "" and hint or nil)
end

-- Opening and switching ----------------------------------------------------------------------

-- The drop-down's list: the professions the character has, with the skill
-- under each; one with no recipe data is there, greyed, with the reason on
-- hover. The one shown is listed even when not learned (the window opened
-- on it, or the character has none), marked "not learned".
function Panel:ProfessionEntries()
    local list = {}
    for _, profession in ipairs(Planner().professions) do
        local skill = Client():GetSkillLevel(profession)
        if skill ~= nil or profession == self.profession then
            local entry = { value = profession, caption = profession, desc = skill and ("skill " .. skill) or "not learned" }
            local data, full = self:Data(profession)
            if full then entry.desc = entry.desc .. ", testing set to 300" end
            if not data then
                entry.disabled = true
                entry.reason = "No recipe data for " .. profession .. ": its recipe table has not been extracted from"
                    .. " the client yet, so it cannot be planned."
            end
            table.insert(list, entry)
        end
    end
    return list
end

function Panel:SelectProfession(profession)
    if profession == self.profession then return end
    self:Trace("profession", { from = self.profession, to = profession })
    self:SaveInputs()
    self.statusText, self.statusError, self.statusUndo = nil, nil, nil
    self:LoadProfession(profession)
    self:SaveInputs() -- remembers it as the profession to open on
    self:Replan("profession")
    self:Render()
end

-- Shows a tab; `opts` goes to its OnShow (ShowTab("materials", { show =
-- "guessed" })).
function Panel:ShowTab(key, opts)
    self:Build()
    local tab = self.tabByKey[key]
    if not tab then return end
    if key ~= self.tab or not self.win:IsShown() then
        self:Trace("tab", { tab = key, from = self.tab, opts = opts })
    end
    self.tab = key
    if self.win:GetTab() ~= key then self.win:SetTab(key) end
    if tab.module and tab.module.OnShow then
        local ok, err = pcall(tab.module.OnShow, tab.module, self, opts)
        if not ok then report(err) end
    end
    if self.win:IsShown() then self:Render() end
end

function Panel:Open(profession)
    self:Build()
    if profession or not self.profession then
        self:LoadProfession(profession or self:DefaultProfession())
    end
    self:Trace("open", { asked = profession, tab = self.tab })
    self:Replan("open")
    self.win:Show()
    self:Render()
end

function Panel:Toggle(profession)
    if self.win and self.win:IsShown() and not profession then self.win:Hide(); return end
    self:Open(profession)
end

function Panel:IsOpen()
    return self.win ~= nil and self.win:IsShown() or false
end

-- Rendering ------------------------------------------------------------------------------

function Panel:RenderHeader()
    local picker = self.professionSelect
    picker:SetOptions(self:ProfessionEntries())
    picker:SetValue(self.profession)
    local live = self.live or (self.profession and self:Live(self.profession)) or {}
    local words = {}
    if not live.learned then table.insert(words, "not learned yet")
    elseif live.maxSkill then table.insert(words, "trained to " .. live.maxSkill)
    else table.insert(words, "skill " .. live.skill) end
    if live.level then table.insert(words, "level " .. live.level) end
    local full = self.profession and select(2, self:Data(self.profession))
    if full then table.insert(words, self:Tint("testing set, to 300", "warning")) end
    self.standing:SetText(table.concat(words, ", "))
end

-- Draws the band, the status and the open tab.
function Panel:Render()
    if not self.win or not self.win:IsShown() then return end
    self.waitingForItems = false
    self:RenderHeader()
    self:PaintStatus()
    local tab = self.tabByKey[self.tab]
    local module = tab and tab.module
    if not module then return end
    local ok, err = pcall(module.Render, module, self)
    if not ok then
        report(err)
        ns:Log("planner: the " .. tab.key .. " tab failed to draw: " .. tostring(err))
    end
end

-- Keeping the route current ------------------------------------------------------------------

-- Plans again when something the route depends on changed: a price, a
-- trainer fee or merchant stock, a recipe learned, or the skill passing a run
-- (or falling behind where the route started). Only while the window is
-- open; otherwise the next opening plans.
function Panel:CheckStale(reason)
    if not self.profession or not self.data then return end
    if not self:IsOpen() then return end
    local live = self:Live(self.profession)
    -- The data afresh: what the other professions make changes with them.
    local signature = Planner():Signature(Planner():MakeInput(self.profession, self:Data(self.profession), self.inputs, live))
    local again = Planner():NeedsReplan(self.route, { skill = live.skill, signature = signature })
    local forced = self.forceReplan
    self.forceReplan = nil
    local passed = Planner():PassedRun(self.route, live.skill)
    self:Trace("check", { trigger = reason, replan = (again or forced or passed) and true or false,
        stale = again and true or false, forced = forced or nil, passed = passed and true or false,
        skill = live.skill, open = true })
    if again or forced or passed then
        self:Replan(reason)
    else
        self.live = live
    end
    self:Render()
end

function Panel:ScheduleCheck(reason)
    if self.checkPending then return end
    self.checkPending = true
    after(0.3, function()
        self.checkPending = false
        self:CheckStale(reason)
    end)
end

-- Something was made (the "You create:" line): a goal making it counts it
-- off, in the plan on screen through Change (so Undo takes it back and the
-- route is planned again), in any other profession's saved plan directly.
function Panel:Crafted(itemID, count)
    local store = self:Store()
    for _, profession in ipairs(Planner().professions or {}) do
        local data = self:Data(profession)
        local current = profession == self.profession and self.inputs
        local inputs = current or (store and data and Planner():LoadInputs(store, profession))
        if inputs and data then
            local probe = deepCopy(inputs)
            local spell = Planner():GoalMade(probe, data, itemID, count)
            if spell then
                local name = self:RecipeName(spell)
                if current then
                    self:Change("made", function(changed) Planner():GoalMade(changed, data, itemID, count) end,
                        function()
                            local goal = Planner():FindGoal(self.inputs, spell)
                            return goal and ("Made " .. name .. ": " .. goal.count .. " left for the goal.")
                                or ("Made " .. name .. ": the goal is done.")
                        end)
                else
                    Planner():SaveInputs(store, profession, probe)
                end
                self:Trace("made", { profession = profession, item = itemID, count = count, spell = spell })
                return
            end
        end
    end
    -- Not a goal: the skill or the bags moved with it, so the plan on screen
    -- is checked now rather than when the bags settle.
    if self.profession and self:IsOpen() then
        self.forceReplan = true
        self:ScheduleCheck("crafted")
    end
end

-- The bags changed: every tab shows what is carried somewhere, so the open
-- one is drawn again (at most twice a second) while the window is open; and
-- a plan counting the bags is planned again once they have been still for a
-- moment, so crafting a stack does not replan at every craft.
function Panel:BagsChanged()
    self.bagGeneration = (self.bagGeneration or 0) + 1
    local generation = self.bagGeneration
    if not self:IsOpen() then return end
    if not self.bagRenderPending then
        self.bagRenderPending = true
        after(0.5, function()
            self.bagRenderPending = false
            self:Render()
        end)
    end
    -- Planning with only what is carried, the bags are the route; and an
    -- intermediate made or a material bought changes what is left to make
    -- and buy.
    local carried = self.inputs and self.inputs.options.materials == "carried"
    if self.profession and self.inputs and (self.inputs.options.useBags ~= false or carried) then
        after(0.5, function()
            if generation ~= self.bagGeneration then return end
            self.forceReplan = true
            self:ScheduleCheck("bags")
        end)
    end
end

-- The profession window --------------------------------------------------------------------

-- A small Planner button on the profession window: the Classic windows
-- (TradeSkillFrame, CraftFrame) below their title, and the modern one
-- (ProfessionsFrame, which Forever uses) in its title bar left of the close
-- button, or of the maximize button where the client has one. The button is
-- ours, parented to their frame; nothing of theirs is changed.
local function placeClassic(button, window)
    button:SetPoint("TOPRIGHT", window, "TOPRIGHT", -44, -40)
    button:SetFrameLevel((window:GetFrameLevel() or 0) + 5)
end

local function placeModern(button, window)
    local left = window.MaximizeMinimize or window.CloseButton
    if type(left) == "table" and left.GetObjectType then
        button:SetPoint("RIGHT", left, "LEFT", -2, 0)
    else
        button:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, -2)
    end
    -- The frame's own art covers a button at its strata, even one above the
    -- crafting page (level 100 in Blizzard's XML), so it draws a strata up.
    button:SetFrameStrata("HIGH")
    local level = window:GetFrameLevel() or 0
    local page = window.CraftingPage
    if type(page) == "table" and page.GetFrameLevel then level = math.max(level, page:GetFrameLevel() or 0) end
    button:SetFrameLevel(level + 10)
end

-- The window's own profession, when the planner covers it.
local function windowButtonClicked(button)
    local snapshot = Client():ReadTradeSkillWindow(button.data)
    local profession = snapshot and snapshot.profession
    local inScope
    for _, name in ipairs(Planner().professions) do
        if profession and name:lower() == profession:lower() then inScope = name end
    end
    Panel:Toggle(inScope)
end

function Panel:AttachWindowButton(frameName, which, place)
    self.windowButtons = self.windowButtons or {}
    if self.windowButtons[frameName] then return end
    local window = rawget(_G, frameName)
    if type(window) ~= "table" or type(window.GetObjectType) ~= "function" then return end
    local ui = self:UI()
    local ok, button = pcall(ui.Button, ui, window, { "Planner", width = 64, height = 18, data = which,
        tooltip = "Open the profession planner for this profession", onClick = windowButtonClicked })
    if not ok or not button then
        ns:Record("prof", { event = "plannerButton", frame = frameName, ok = false, err = tostring(button) })
        return
    end
    -- Its strata and level are set by hand, beside Blizzard's frame; it is
    -- never cleared, but marked as a changed frame all the same.
    button:Customize(ui.Custom.frame)
    local placed, err = pcall(place, button, window)
    if not placed then button:ClearAllPoints(); placeClassic(button, window) end
    self.windowButtons[frameName] = button
    local anchor = select(2, button:GetPoint(1))
    ns:Record("prof", { event = "plannerButton", frame = frameName, ok = true, placeErr = not placed and tostring(err) or nil,
        anchor = anchor and anchor.GetName and anchor:GetName() or (anchor == window.CloseButton and "CloseButton")
            or (anchor == window.MaximizeMinimize and "MaximizeMinimize") or tostring(anchor),
        level = button:GetFrameLevel(), windowLevel = window:GetFrameLevel(), strata = button:GetFrameStrata() })
end

function Panel:AttachWindowButtons()
    self:AttachWindowButton("TradeSkillFrame", "tradeskill", placeClassic)
    self:AttachWindowButton("CraftFrame", "craft", placeClassic)
    self:AttachWindowButton("ProfessionsFrame", "tradeskill", placeModern)
end

-- Events --------------------------------------------------------------------------------

function Panel:OnEvent(event, ...)
    if event == "SKILL_LINES_CHANGED" then
        self:ScheduleCheck("skill")
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        self:BagsChanged()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if self.waitingForItems and self:IsOpen() and not self.renderPending then
            self.renderPending = true
            after(0.3, function() self.renderPending = false; self:Render() end)
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        self:AttachWindowButtons()
        after(0.1, function() self:AttachWindowButtons() end)
    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" or name == "Blizzard_Professions" then
            self:AttachWindowButtons()
        end
    end
end

-- The profession window, a trainer or a merchant told us something new.
-- Another profession's window counts too when it has recipe data: its
-- recipes may make this one's materials (Planner:WithHelpers).
function Panel:ProfessionChanged(kind, subject, data)
    if kind == "crafted" then
        self:Crafted(subject, data)
        return
    end
    -- The window opened or shut: only the Plan tab's Make button cares.
    if kind == "window" then
        self:Render()
        return
    end
    if kind == "tradeskill" and self.profession and type(subject) == "string"
        and subject:lower() ~= self.profession:lower()
        and not (type(ns.professionData) == "table" and ns.professionData[Planner():DataKey(subject)]) then return end
    -- The auction house closed: Auctionator may have scanned new prices,
    -- which are not part of the inputs' signature.
    if kind == "auction" then self.forceReplan = true end
    self:ScheduleCheck(kind)
end

function Panel:Initialize()
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "TRADE_SKILL_SHOW", "CRAFT_SHOW", "ADDON_LOADED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    -- One event after a burst of bag changes where the client has it; each
    -- change otherwise (BagsChanged coalesces them).
    local delayed = pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
    if not delayed then pcall(frame.RegisterEvent, frame, "BAG_UPDATE") end
    frame:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self.eventFrame = frame
    self:AttachWindowButtons()
    Client():OnProfessionChange(function(kind, subject, data) self:ProfessionChanged(kind, subject, data) end)

    -- Developer convenience, as OpenRoad's /openroad: opens the window. The
    -- player's way in is the Planner button on the profession window (and
    -- NuuRoad's menu, through the API below).
    local slash = rawget(_G, "SlashCmdList")
    if type(slash) == "table" then
        _G.SLASH_NUUPROFESSIONS1 = "/nuuprofessions"
        _G.SLASH_NUUPROFESSIONS2 = "/nuuprof"
        -- `/nuuprof shop` shows or hides the shopping list.
        slash.NUUPROFESSIONS = function(text)
            local word = type(text) == "string" and text:lower():match("^%s*(%S+)") or nil
            if word == "shop" or word == "list" then
                local list = ns.modules.ShoppingList
                if list then list:Toggle() end
                return
            end
            Panel:Toggle()
        end
    end
end

ns:RegisterModule("PlannerPanel", Panel)

-- The optional API ---------------------------------------------------------------------------

-- What NuuRoad (or another addon) may ask, when this addon is installed
-- (docs/planner-split.md, "The optional APIs"): plain functions taking and
-- returning IDs, numbers, strings and plain tables. A new function is a
-- minor change; changing or removing one bumps apiVersion.
ns.API = {
    apiVersion = 1,

    -- Opens the planner on a profession (or the last one planned).
    Open = function(profession)
        Panel:Open(profession)
        return true
    end,

    -- A plain recipe table of the planner's data and its spell, or nil.
    Recipe = function(profession, spellID, itemID)
        if type(profession) ~= "string" then return nil end
        local data = Panel:Data(profession)
        if not data then return nil end
        return ns.Kit.Crafting:Recipe(data, spellID, itemID)
    end,

    -- A recipe's skill levels as the plan uses them: a trainer may teach it before
    -- the data's orange skill.
    Skills = function(profession, spellID)
        if type(profession) ~= "string" then return nil end
        local data = Panel:Data(profession)
        local recipe = data and data.recipes and data.recipes[spellID]
        if not recipe then return nil end
        return Planner():Skills(Prices():Book(), spellID, recipe)
    end,

    -- Planning with only what is carried: the crafts a step makes.
    CarriedCrafts = function(profession, spellID, untilSkill)
        return Panel:CarriedCrafts(profession, spellID, untilSkill)
    end,
}
