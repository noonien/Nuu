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
-- a change just did, with Undo where it can be undone, or what changed the
-- plan on its own). Every plan goes to the change history
-- (Domain/PlanChanges.lua), which the Changes button shows in a panel of
-- its own (UI/PlanChanges.lua). The tabs draw
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
-- (ns:Trace, kept for every session that traced in the last day, at least
-- the last three): each plan with its inputs and route, each change with the
-- inputs before and after, and the window's own actions. The plan row is built once a replan, and only while the
-- trace is kept.
--
-- The route is not exported to a guide tracker: it stands in this window,
-- and the Plan tab's Make button works through it a step at a time. The planner recommends; nothing
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

-- Item names are the kit's (Kit.Items:Name): "Item 2318" until the client has
-- the name, and the window, drawn under Kit.Items:Track (Panel:Render), draws
-- again once it came.
local function itemName(id)
    if not id then return nil end
    return ns.Kit.Items:Name(id)
end

-- The planner's own lookup, for the Domain: a spell's name or nil, an item's
-- name or its stand-in.
local function nameOf(kind, id)
    if kind == "spell" then return Client():GetSpellName(id) end
    if kind == "item" then return itemName(id) end
    return nil
end
Panel.NameOf = nameOf

-- Never nil: "Item 2318" until the client knows the name.
function Panel:ItemName(itemID)
    return ns.Kit.Items:Name(itemID)
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

-- A profession's items, asked of the server once a session if the client has
-- not loaded them: the plan names them in sentences it makes before anything
-- is drawn (its status, its warnings), which a redraw would not change.
local preloaded = setmetatable({}, { __mode = "k" })
local function preload(data)
    if type(data) ~= "table" or preloaded[data] then return end
    preloaded[data] = true
    local ids = {}
    for itemID in pairs(data.items or {}) do ids[#ids + 1] = itemID end
    ns.Kit.Items:Preload(ids)
end

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
        tail = pick(route.tail, { "fromSkill", "toSkill", "runIndex", "net", "perPoint", "times" }),
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

-- Whether a plan reads the bags: using what is carried first, or only that.
local function readsBags(inputs)
    if not inputs then return false end
    return inputs.options.useBags ~= false or inputs.options.materials == "carried"
end

-- What the open tab draws from a route, as one string: when a replan gives
-- the same, nothing on screen moved and the route need not be drawn again.
local function routePrint(route, sections)
    if not route then return "none" end
    local out = { route.signature or "", route.startSkill or "", route.skill or "", route.target or "", tostring(route.committed),
        route.status and route.status.kind or "", route.status and route.status.text or "",
        route.ceiling and route.ceiling.skill or "", route.ceiling and route.ceiling.reason or "" }
    local summary = route.summary or {}
    for _, field in ipairs({ "spent", "recovered", "net", "materials", "training", "learning", "low", "high" }) do
        table.insert(out, tostring(summary[field]))
    end
    for _, run in ipairs(route.runs or {}) do
        table.insert(out, table.concat({ run.spell or "", run.fromSkill or "", run.toSkill or "", run.count or "",
            run.low or "", run.high or "", tostring(run.committed), run.color or "" }, ":"))
    end
    table.insert(out, "e" .. #(route.events or {}))
    for _, item in ipairs(route.shopping or {}) do
        table.insert(out, table.concat({ item.itemID or "", item.count or "", item.have or "", item.buy or "" }, ":"))
    end
    table.insert(out, "w" .. #(route.warnings or {}) .. "s" .. #(route.suggestions or {}) .. "x" .. #(sections or {}))
    return table.concat(out, "|")
end

-- What the band and the Make button read of the client besides the route.
local function livePrint(live)
    if not live then return "none" end
    return table.concat({ tostring(live.learned), live.skill or "", live.maxSkill or "", live.level or "",
        tostring(live.fullScope) }, ":")
end

-- Plans the route again from the live skill, bags and inputs. `triggers`:
-- what the check that asked gathered ("crafted,bags,skill"), for the log.
function Panel:Replan(reason, triggers)
    local profession = self.profession
    -- A plan the player asked for (Changed) goes in the history as theirs.
    local own = self.ownReason
    self.ownReason, self.ownEntry = nil, nil
    if not profession then return end
    self.data = self:Data(profession)
    preload(self.data)
    self.problem = nil
    local live = self:Live(profession)
    self.live = live
    local tracing = self:Tracing()
    if not self.data then
        self.route, self.input, self.sections = nil, nil, nil
        self.problem = "No recipes for " .. profession .. " yet in this version of NuuProfessions."
        self.routePrint, self.bagPrint = "problem:" .. self.problem, nil
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
    -- Planning on old auction prices, once the player said so (PlanAnyway).
    input.auctionScanAge = self:AuctionScanAge()
    input.acceptStale = self.staleAccepted == profession or nil
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
        self.routePrint, self.bagPrint = "problem:" .. self.problem, nil
        ns:Log("planner: " .. tostring(route))
        if tracing then
            self:Trace("plan-failed", { reason = reason, error = tostring(route), live = liveTrace(live),
                fullScope = live.fullScope or false, inputs = self.inputs, ms = took })
        end
        return
    end
    self.route = route
    self.committed = route.committed and { profession = profession, spell = route.committed } or nil
    -- Fresh prices again: the next old ones hold the route again.
    if not route.staleAuction and self.staleAccepted == profession then self.staleAccepted = nil end
    -- A route on old auction prices is held back (Planner:Status "stale"):
    -- nothing of it reaches the shopping list or the trainer strip.
    local held = route.status and route.status.kind == "stale"
    local split, sections = pcall(Planner().Sections, Planner(), route, self:SplitInput())
    self.sections = split and sections or {}
    if not split then ns:Log("planner: sections failed: " .. tostring(sections)) end
    -- What the route shows and the bags it read, for the next check
    -- (CheckStale): the same route is not drawn again, and only bags that
    -- moved plan again.
    self.routePrint = routePrint(route, self.sections)
    self.bagPrint = readsBags(self.inputs) and self:BagPrint() or nil
    -- The shopping list keeps what this plan buys, to show with the window shut.
    local list = ns.modules.ShoppingList
    if list then
        local kept, err = pcall(list.Keep, list, profession, route, not held and self.sections or {})
        if not kept then report(err) end
    end
    -- And what it learns at a trainer, for the strip under the trainer's window.
    local training = ns.modules.TrainerTraining
    if training and not held then
        local kept, err = pcall(training.Keep, training, profession, route, self.data)
        if not kept then report(err) end
    end
    local noted, err = pcall(self.NoteChange, self, reason, route, input, own)
    if not noted then report(err) end
    if tracing then
        local traced, row = pcall(self.TraceRoute, self, route)
        if not traced then report(row) end
        self:Trace("plan", { reason = reason, triggers = triggers, data = true, profession = profession, live = liveTrace(live),
            fullScope = live.fullScope or false,
            inputs = self.inputs,
            input = { level = input.level, known = countKeys(input.known), target = input.target, skill = input.skill,
                maxSkill = input.maxSkill },
            replay = replayTrace(input),
            route = traced and row or nil, ms = took, sections = #self.sections,
            sectionsFailed = not split and tostring(sections) or nil })
    end
    local first = route.runs[1]
    ns:Record("prof", { event = "plan", profession = profession, reason = reason, triggers = triggers,
        skill = live.skill, target = route.target, net = route.summary.net, runs = #route.runs,
        suggestions = #route.suggestions, status = route.status and route.status.kind,
        split = self.inputs.options.sections, committed = route.committed,
        first = first and first.spell, firstCount = first and first.count })
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
    self.ownReason = reason or "inputs"
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

-- The change history ------------------------------------------------------------------

local function now()
    local clock = rawget(_G, "time")
    return type(clock) == "function" and clock() or 0
end

-- The names and money an entry's words are made with (PlanChanges:Words).
function Panel:ChangeNames()
    local names = self.changeNames
    if not names then
        names = {
            item = function(id) return self:ItemName(id) end,
            recipe = function(spell) return self:RecipeName(spell) end,
            money = function(copper) return self:Money(copper) end,
        }
        self.changeNames = names
    end
    return names
end

-- A plan was made: the history compares it with the last one and keeps an
-- entry when it changed something the player would see. One the player
-- asked for (`own`) takes the strip's words when they come (SetStatus);
-- one the addon made on its own says what changed in the strip.
function Panel:NoteChange(reason, route, input, own)
    local changes = ns.modules.PlanChanges
    local store = self:Store()
    if not changes or not store then return end
    local snapshot = changes:Snapshot(route, self.sections, input.known)
    local entry = changes:Note(store, self.profession, snapshot, reason, own, now())
    if entry then
        self:Trace("history", { reason = reason, own = own, causes = entry.causes, effects = entry.effects })
        if own then
            self.ownEntry = entry
        else
            self:SetStatus(changes:Summary(entry, self:ChangeNames()))
        end
    end
    local view = ns.modules.PlanChangesView
    if view then view:Refresh() end
end

-- The Changes button: the history's panel shown or put away.
local function changesClicked()
    local view = ns.modules.PlanChangesView
    if view then view:Toggle() end
end

-- The history's panel shown or put away: its button follows.
function Panel:ChangesShown(shown)
    if self.changesButton then self.changesButton:SetActive(shown) end
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

-- The held route's "Plan anyway": plans this profession on the old auction
-- prices, until they are fresh again.
function Panel:PlanAnyway()
    if not self.profession then return end
    self:Trace("plan-anyway", { age = self.route and self.route.staleAuction and self.route.staleAuction.age })
    self.staleAccepted = self.profession
    self:Replan("stale")
    self:Render()
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
    local view = ns.modules.PlanChangesView
    self.changesButton = header:Button{ "Changes", onClick = changesClicked,
        active = view and view:IsShown() or false,
        tooltip = "What changed in this plan and why, newest first" }
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
-- Undo beside it. The next change clears it (Changed). What the player's
-- own change did is also the words of its entry in the history.
function Panel:SetStatus(text, isError, undo)
    self.statusText, self.statusError, self.statusUndo = text, isError, undo
    local entry = self.ownEntry
    self.ownEntry = nil
    if entry and text and not isError then
        entry.text = text
        local view = ns.modules.PlanChangesView
        if view then view:Refresh() end
    end
    self:PaintStatus()
end

-- The strip's Undo: the message goes, then the change is taken back.
local function undoStatus()
    local undo = Panel.statusUndo
    Panel.statusText, Panel.statusError, Panel.statusUndo = nil, nil, nil
    if undo then undo() end
    Panel:PaintStatus()
end

-- Seconds since the last full Auctionator scan on this realm, or nil.
function Panel:AuctionScanAge()
    local at = Client():LastAuctionScan()
    local now = rawget(_G, "time")
    if not at or type(now) ~= "function" then return nil end
    return math.max(now() - at, 0)
end

-- The strip's right, while the plan uses Auctionator's prices: how long ago
-- the last full scan with it was, in the warning colour once the planner
-- holds a route for it (Planner.auctionMaxAge).
function Panel:AuctionAside()
    local route = self.route
    if not (route and route.summary and (route.summary.auctionator or 0) > 0) then return nil end
    local age = self:AuctionScanAge()
    local text = age and ("Auction scan " .. Planner().Ago(age)) or "No auction scan yet"
    local old = age == nil or age > Planner().auctionMaxAge
    return { text = text, tone = old and "warning" or "muted",
        tooltip = (age and ("The last full scan with Auctionator on this realm ended " .. Planner().Ago(age) .. ".")
            or "No full scan with Auctionator on this realm yet.")
            .. " Run a full scan to bring the auction prices up to date." }
end

-- With nothing to say, the strip shows the open tab's hint, muted; at its
-- right, how long ago the last full auction scan was (AuctionAside).
function Panel:PaintStatus()
    local win = self.win
    if not win then return end
    local aside = self:AuctionAside()
    local text = self.statusText
    if text and text ~= "" then
        local opts = self.statusOpts or {}
        self.statusOpts = opts
        opts.tone = self.statusError and "danger" or "text"
        opts.undo = self.statusUndo and undoStatus or nil
        opts.aside = aside
        win:Status(text, opts)
        return
    end
    local tab = self.tabByKey and self.tabByKey[self.tab]
    local hint = tab and tab.module and tab.module.hint
    if type(hint) == "function" then
        local ok, said = pcall(hint, tab.module, self)
        hint = ok and said or nil
    end
    win:Status(type(hint) == "string" and hint ~= "" and hint or nil, aside and { aside = aside } or nil)
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

-- Draws the band, the status and the open tab, under the kit's Track: a name
-- the client did not have yet shows as "Item <id>", and the window draws
-- again once the names are in.
local function draw() Panel:Draw() end

function Panel:Render()
    ns.Kit.Items:Track(draw)
end

function Panel:Draw()
    if not self.win or not self.win:IsShown() then return end
    -- The status sentence names items: made again with the names there are
    -- now, under Track, not kept from when the plan was made.
    local route = self.route
    if route then route.status = Planner():Status(route, nameOf, self.input and self.input.data or self.data) end
    self.drawnLive = livePrint(self.live)
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

-- What changes the route needs a check for arrive in bursts: one craft is a
-- "You create" line, a bag update, a skill line and a profession window
-- read, a few tenths of a second apart, and the first of them sees the
-- others' state half done (the skill not yet up). So every trigger feeds one
-- settle timer, started again by each new one, and the check runs SETTLE
-- seconds after the last: one check (and at most one plan) a craft, on the
-- state the whole burst left.
local SETTLE = 0.5
-- While the Make button's batch runs, the bags change at every craft; what
-- they change is planned again when the skill moves or the batch stops, and
-- a batch quiet this long has stopped (one that ran out of materials short
-- of its skill keeps its stop until the window shuts).
local HOLD = 6

-- The reason a coalesced check is traced and recorded under: the most telling
-- of its triggers. A kind not named here ranks above the bags.
local TRIGGER_RANK = { auction = 1, trainer = 2, merchant = 3, skill = 4, crafted = 5, tradeskill = 6, craft = 7,
    window = 9, bags = 10 }

local function rank(trigger) return TRIGGER_RANK[trigger] or 8 end

-- The count carried of every item a recipe of the data takes or makes, as one
-- string: the bags are not part of the inputs' signature, so a bag update
-- replans only when one of these moved (loot of anything else does not).
function Panel:BagPrint()
    local data = self.data
    if not data then return nil end
    local items = self.bagItems
    if not items or items.data ~= data then
        local seen, list = {}, {}
        for _, recipe in pairs(data.recipes or {}) do
            if type(recipe) == "table" then
                if recipe.makes and not seen[recipe.makes] then seen[recipe.makes] = true; table.insert(list, recipe.makes) end
                for _, reagent in ipairs(recipe.reagents or {}) do
                    if not seen[reagent[1]] then seen[reagent[1]] = true; table.insert(list, reagent[1]) end
                end
            end
        end
        table.sort(list)
        items = { data = data, list = list }
        self.bagItems = items
    end
    local api, counts = Client(), {}
    for index, item in ipairs(items.list) do counts[index] = api:GetItemCount(item, true) or 0 end
    return table.concat(counts, ",")
end

-- The Make button's batch, while it runs for the profession on screen.
function Panel:MakeRunning()
    local stop = Client().craftUntil
    return type(stop) == "table" and self.profession ~= nil and type(stop.profession) == "string"
        and stop.profession:lower() == self.profession:lower() or false
end

-- Plans again when something the route depends on changed: a price, a
-- trainer fee or merchant stock, a recipe learned, the skill moving (or
-- passing a run, or falling behind where the route started), or what is
-- carried. Only while the window is open; otherwise the next opening plans.
-- `pending` is what ScheduleCheck gathered: { triggers, force, quiet }.
-- The route is drawn again only when the plan changed what it shows.
function Panel:CheckStale(reason, pending)
    pending = pending or { triggers = { reason } }
    if not self.profession or not self.data then return end
    if not self:IsOpen() then return end
    local live = self:Live(self.profession)
    -- The data afresh: what the other professions make changes with them.
    local signature = Planner():Signature(Planner():MakeInput(self.profession, self:Data(self.profession), self.inputs, live))
    local again = Planner():NeedsReplan(self.route, { skill = live.skill, signature = signature })
    local forced = pending.force
    local passed = Planner():PassedRun(self.route, live.skill)
    -- The counts ahead were sized from the skill the route was planned at.
    local moved = self.route ~= nil and self.route.skill ~= live.skill
    local bags = readsBags(self.inputs) and self.bagPrint ~= nil and self:BagPrint() ~= self.bagPrint
    -- During a Make batch the bags alone wait for the skill or the batch's end.
    local held = bags and not (again or forced or passed or moved) and not pending.quiet and self:MakeRunning()
    local replan = (again or forced or passed or moved or (bags and not held)) and true or false
    local triggers = table.concat(pending.triggers, ",")
    self:Trace("check", { trigger = reason, triggers = triggers, replan = replan, stale = again and true or false,
        forced = forced or nil, passed = passed and true or false, moved = moved or nil, bags = bags or nil,
        held = held or nil, skill = live.skill, open = true })
    if held then
        self:HoldCheck(pending)
        return
    end
    local before = self.routePrint
    if replan then
        self:Replan(reason, triggers)
    else
        self.live = live
    end
    if self.routePrint ~= before or livePrint(self.live) ~= self.drawnLive then
        self:Render()
    else
        self:RefreshMake()
    end
end

-- Asks for a check once things settle, with what asked (`reason`: "skill",
-- "bags", "crafted", "tradeskill", "auction", ...). Every call starts the
-- settle timer again; the triggers gathered meanwhile go to the one check.
function Panel:ScheduleCheck(reason, force)
    local pending = self.pendingCheck
    if not pending then
        pending = { triggers = {}, seen = {} }
        self.pendingCheck = pending
    end
    if not pending.seen[reason] then
        pending.seen[reason] = true
        table.insert(pending.triggers, reason)
    end
    if force then pending.force = true end
    pending.quiet = nil
    self:ArmCheck(pending, SETTLE)
end

-- `quiet`: the hold's timer, which fires only when nothing came since.
function Panel:ArmCheck(pending, seconds, quiet)
    self.checkGeneration = (self.checkGeneration or 0) + 1
    local generation = self.checkGeneration
    after(seconds, function()
        if generation ~= self.checkGeneration then return end
        self.pendingCheck = nil
        pending.quiet = quiet
        local reason = pending.triggers[1]
        for _, trigger in ipairs(pending.triggers) do
            if rank(trigger) < rank(reason) then reason = trigger end
        end
        self:CheckStale(reason, pending)
    end)
end

-- The bags moved during a Make batch: the triggers wait for the next one (a
-- skill line, the window shutting), or for HOLD seconds without one, when
-- the batch has stopped and the bags count.
function Panel:HoldCheck(pending)
    self.pendingCheck = pending
    self:ArmCheck(pending, HOLD, true)
end

-- The Make button against the live profession window, when the route on
-- screen stays as it is.
function Panel:RefreshMake()
    if not self.win or not self.win:IsShown() then return end
    local tab = self.tabByKey and self.tabByKey[self.tab]
    local module = tab and tab.module
    if not module or type(module.RenderMake) ~= "function" then return end
    local ok, err = pcall(module.RenderMake, module, self)
    if not ok then report(err) end
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
    -- Not a goal: the skill and the bags move with it, and their own triggers
    -- follow; this one joins them in the one check after the craft.
    if self.profession and self:IsOpen() then self:ScheduleCheck("crafted") end
end

-- The bags changed: every tab shows what is carried somewhere, so the open
-- one is drawn again (at most twice a second) while the window is open; and
-- a plan counting the bags is checked once they have been still for a
-- moment (planned again when what a recipe takes or makes moved).
function Panel:BagsChanged()
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
    if self.profession and readsBags(self.inputs) then self:ScheduleCheck("bags") end
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
    -- The window opened or shut: only the Plan tab's Make button cares, and
    -- a check held for a Make batch (shut, the batch is over).
    if kind == "window" then
        self:Render()
        if self.pendingCheck then self:ScheduleCheck("window") end
        return
    end
    if kind == "tradeskill" and self.profession and type(subject) == "string"
        and subject:lower() ~= self.profession:lower()
        and not (type(ns.professionData) == "table" and ns.professionData[Planner():DataKey(subject)]) then return end
    -- The auction house closed: Auctionator may have scanned new prices,
    -- which are not part of the inputs' signature.
    self:ScheduleCheck(kind, kind == "auction")
end

function Panel:Initialize()
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "CRAFT_SHOW", "ADDON_LOADED" }) do
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

    -- Developer convenience: opens the window. The
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
