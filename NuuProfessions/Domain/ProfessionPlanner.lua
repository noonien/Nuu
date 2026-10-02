local _, ns = ...

-- The profession planner: the cheapest route from the player's skill to the one
-- they want, as a list of recipes to make until a skill. See PROF_PLAN.md.
--
-- The measure is net cost: materials and training, minus what the output sells
-- for. A point at skill s with recipe r costs
--
--     (material cost of r - sell value of r's output) / chance(r, s)
--
-- and switching onto a recipe the first time adds what it costs to learn. A
-- dynamic programme over (skill, current recipe) finds the cheapest sum.
-- Goals (things the player wants made anyway) are placed first and give free
-- progress; trainer tiers are forced steps at their caps.
--
-- Pure: no frames and no Blizzard calls. Everything the client knows (skill,
-- known recipes, bag counts, level) is passed in, so the tests can plan toy
-- professions with known answers. The planner recommends; it never crafts,
-- buys, posts or trains.
local Planner = {}

local INF = math.huge
local EPS = 1e-6

Planner.suggestThreshold = 1000 -- 10s: suggestions saving less are not shown
Planner.maxPasses = 6           -- intermediates (their value and their skill) and market depth re-solves
Planner.carriedCraftCost = 1    -- copper: with only what is carried, what a craft costs the route besides its materials
Planner.expensiveFactor = 4     -- a run dearer a point than this many medians is warned about
Planner.expensiveMinimum = 10000 -- 1g a point: cheaper runs are never called expensive
Planner.whens = { best = true, now = true, ["end"] = true, skill = true }
Planner.defaultOptions = {
    confidence = "safe",   -- typical | safe | sure
    auction = "buy",       -- use the auction house to buy, sell, both or none (buy only by default)
    useBags = true,        -- what is carried is used first, costed at its sell value
    materials = "buy",     -- "buy" what is missing, or "carried": plan with only what is carried and
                           -- what vendors sell (and what the route makes from those), as far as it goes
    floor = 0.15,          -- chances below this are a last resort
    sections = "trip",     -- how the plan is split: trip | tier | recipe | band (Planner:Sections)
    bandSize = 25,         -- skill levels a "band" section spans, at least
    recipesPerSection = 1, -- recipes made in a "recipe" section
    suggestThreshold = nil,-- copper; default Planner.suggestThreshold
    estimateFactor = 4,    -- an unpriced material's auction price: its vendor sell price times this
    useAuctionator = true, -- auction prices from Auctionator, when it is installed and has seen them
    recipes = "patterns",  -- what the route may use unasked: "patterns", every recipe (patterns the
                           -- character lacks marked), or "trainer", trainer and known ones only
    optimize = "cost",     -- what the route minimises: "cost" (spending) or "profit" (spending less sales)
    sellOutput = "chosen", -- what counts as sold: only items in `sell`, or "all" of them
}

-- Why a material the route cannot have has no source, in the player's
-- words: `which` after its name, `part` for a recipe one of whose materials
-- it is. Never "no price": what matters is where it could come from.
--   carried  only what is carried: they have none, and no vendor sells it
--   vendor   they do not buy at the auction house, and no vendor sells it
--   auction  no vendor sells it, and the planner knows no auction price
Planner.missingWords = {
    carried = { which = "which you don't have", part = "you don't have a material of it" },
    vendor = { which = "which no vendor sells", part = "no vendor sells a material of it" },
    auction = { which = "which no vendor sells, at no auction price known",
        part = "a material of it has no vendor, and no auction price known" },
}

function Planner:MissingWords(why)
    return self.missingWords[why] or self.missingWords.auction
end

local function SkillUp() return ns.Kit.SkillUp end
local function Config() return ns.modules.Config end
local function Prices() return ns.modules.Prices end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function sortedKeys(set)
    local keys = {}
    for key in pairs(set or {}) do table.insert(keys, key) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) < type(b)
    end)
    return keys
end

local function ascii(text)
    return (tostring(text):gsub("[\128-\255]", "?"))
end

-- Inputs -------------------------------------------------------------------

-- A fresh set of planner inputs for one profession: what the Plan, Recipes
-- and Materials tabs edit, and what is saved per character.
--
--   target    skill wanted (nil: as far as the character can train)
--   goals     { { spell = id, count = n, when = "best"|"now"|"end"|"skill", skill = n } }
--             things the player wants made on the way, kept rather than sold
--   options   the player's choices of Planner.defaultOptions (a default is not
--             stored: see Planner:Option), plus gather = { [itemID] = "opportunity"|"zero" },
--             get = { [itemID] = "buy"|"make" } (only bought, or only made; see Planner:GetMode)
--             and keep = { [itemID] = true } (sold at the vendor price only, never at the
--             auction house), sell = { [itemID] = true } (sold, when sellOutput is "chosen")
--             and nosell = { [itemID] = true } (never counted as sold); see Planner:SaleMode
--   refused   { [spellID] = true }  "Don't use": never used or suggested
--   pinned    { [spellID] = true }  "use this one": preferred wherever it gives skill
--   accepted  { [spellID] = true }  suggestions the player took ("Use it")
--   avoided   { [itemID] = true }   "Don't use" on a material: no recipe that
--             needs it is used, suggested or made as a goal
--   preferred { [itemID] = true }   "Prefer it" on a material: every usable recipe
--             that needs it is treated as pinned
--   chosen    { { fromSkill = a, toSkill = b, spell = s } }  "Use this" on one of a step's
--             choices: from skill a up to (not including) b the route makes only recipe s,
--             where it gives skill; the rest of the route is the planner's own. (Older
--             saves carry leave and rejoin as well; they are ignored.)
function Planner:DefaultInputs()
    local options = { gather = {}, get = {}, keep = {}, sell = {}, nosell = {} }
    return { target = nil, goals = {}, options = options, refused = {}, pinned = {}, accepted = {}, avoided = {},
        preferred = {}, chosen = {} }
end

-- An option is stored only once the player chooses it, as every setting is
-- (Config, "Settings"): `inputs.options[key]` holds the choice, even one
-- equal to the default, and nil means the default. Option reads one as it
-- applies; Options all of them, as a copy.
function Planner:Option(inputs, key)
    return Config().Read(inputs and inputs.options, self.defaultOptions, key)
end

function Planner:Options(inputs)
    return Config().Resolved(inputs and inputs.options, self.defaultOptions)
end

-- Fills in the parts `inputs` lacks, as empty tables, so the tabs can edit
-- them; options stay as the player set them.
local function fillMissing(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = copy(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            fillMissing(target[key], value)
        end
    end
    return target
end

-- A copy without the tables left empty and the values that are not set,
-- which is what is saved.
local function compact(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        child = compact(child)
        if type(child) ~= "table" or next(child) ~= nil then result[key] = child end
    end
    return result
end

-- The planner's record in a character's saved store:
--   store.professionPlanner = { profession = "Leatherworking", plans = { [profession] = inputs } }
--   store.knownRecipes[profession][spellID] = true   (written by API/Client.lua)
-- Made when first written; reading leaves a character without one as it is.
function Planner:CharacterRecord(store)
    store.professionPlanner = store.professionPlanner or {}
    store.professionPlanner.plans = store.professionPlanner.plans or {}
    return store.professionPlanner
end

-- The saved inputs for one profession, with empty tables for what was never
-- set (options keep only the player's choices). A copy: edit it, then
-- SaveInputs.
function Planner:LoadInputs(store, profession)
    local record = store.professionPlanner
    local saved = record and record.plans and record.plans[profession]
    local inputs = saved and copy(saved) or {}
    -- Goals were saved as `wishes` before they were renamed.
    if inputs.goals == nil and type(inputs.wishes) == "table" then inputs.goals = inputs.wishes end
    inputs.wishes = nil
    -- The window plans with every recipe, patterns the character lacks
    -- included; "all" and the old default "trainer" are read that way.
    if type(inputs.options) == "table" then inputs.options.recipes = nil end
    return fillMissing(inputs, self:DefaultInputs())
end

-- Keeps only what the player set: no default option, no empty table. A
-- profession with nothing set has no record at all.
function Planner:SaveInputs(store, profession, inputs)
    local record = self:CharacterRecord(store)
    local saved = compact({
        target = inputs.target, goals = inputs.goals, options = inputs.options,
        refused = inputs.refused, pinned = inputs.pinned, accepted = inputs.accepted,
        avoided = inputs.avoided, preferred = inputs.preferred, chosen = inputs.chosen,
    })
    record.plans[profession] = next(saved) ~= nil and saved or nil
    record.profession = profession
end

function Planner:KnownRecipes(store, profession)
    return store.knownRecipes and store.knownRecipes[profession] or {}
end

-- "Don't use", on any recipe. It also drops a pin, an acceptance or a goal,
-- since those say the opposite.
function Planner:Refuse(inputs, spellID, refused)
    inputs.refused = inputs.refused or {}
    if refused == false then inputs.refused[spellID] = nil; return end
    inputs.refused[spellID] = true
    if inputs.pinned then inputs.pinned[spellID] = nil end
    if inputs.accepted then inputs.accepted[spellID] = nil end
    local _, index = self:FindGoal(inputs, spellID)
    if index then self:RemoveGoal(inputs, index) end
end

-- "Don't use", on a material: every recipe that needs it is left out.
function Planner:Avoid(inputs, itemID, avoided)
    inputs.avoided = inputs.avoided or {}
    inputs.avoided[itemID] = avoided ~= false or nil
    if avoided ~= false and inputs.preferred then inputs.preferred[itemID] = nil end
end

-- The first material of `recipe` the player said not to use, or nil.
function Planner:AvoidedReagent(recipe, avoided)
    if not avoided then return nil end
    for _, reagent in ipairs(recipe and recipe.reagents or {}) do
        if avoided[reagent[1]] then return reagent[1] end
    end
    return nil
end

function Planner:Pin(inputs, spellID, pinned)
    inputs.pinned = inputs.pinned or {}
    inputs.pinned[spellID] = pinned ~= false or nil
    if pinned ~= false and inputs.refused then inputs.refused[spellID] = nil end
end

-- "Use it", on a suggestion: the player has the pattern or will get it.
function Planner:Accept(inputs, spellID, accepted)
    inputs.accepted = inputs.accepted or {}
    inputs.accepted[spellID] = accepted ~= false or nil
    if accepted ~= false and inputs.refused then inputs.refused[spellID] = nil end
end

-- What the route may do with a recipe, as one choice:
--   auto    the planner decides
--   prefer  pinned: used wherever it gives skill
--   never   refused: never used or suggested
--   have    accepted: the player has the pattern or will get it
-- Stored as the pinned, refused and accepted sets, of which a recipe is in
-- one at most.
Planner.planWithModes = { "auto", "prefer", "never", "have" }

-- A recipe's colour skill levels as the planner uses them: a trainer's recorded
-- skill requirement replaces the shipped learn skill, which for most trainer
-- recipes is only a guess.
function Planner:Skills(book, spell, recipe)
    local skills = recipe.skills
    local taught = recipe.learn == "trainer" and book and Prices():TrainerSkill(book, spell)
    if taught and taught ~= skills[1] then
        skills = { taught, skills[2], skills[3], skills[4] }
    end
    return skills
end

function Planner:PlanWith(inputs, spell)
    if inputs.refused and inputs.refused[spell] then return "never" end
    if inputs.pinned and inputs.pinned[spell] then return "prefer" end
    if inputs.accepted and inputs.accepted[spell] then return "have" end
    return "auto"
end

-- "never" also drops the recipe's goal, as Refuse does; "auto" clears all
-- three. Returns false for a mode it does not know.
function Planner:SetPlanWith(inputs, spell, mode)
    if mode ~= "auto" and mode ~= "prefer" and mode ~= "never" and mode ~= "have" then return false end
    inputs.refused, inputs.pinned, inputs.accepted = inputs.refused or {}, inputs.pinned or {}, inputs.accepted or {}
    inputs.refused[spell], inputs.pinned[spell], inputs.accepted[spell] = nil, nil, nil
    if mode == "never" then
        self:Refuse(inputs, spell)
    elseif mode == "prefer" then
        inputs.pinned[spell] = true
    elseif mode == "have" then
        inputs.accepted[spell] = true
    end
    return true
end

-- What the route may do with a material: "auto", "prefer" (every usable
-- recipe needing it is treated as pinned) or "never" (every recipe needing
-- it is left out, as Avoid).
function Planner:MaterialMode(inputs, itemID)
    if inputs.avoided and inputs.avoided[itemID] then return "never" end
    if inputs.preferred and inputs.preferred[itemID] then return "prefer" end
    return "auto"
end

function Planner:SetMaterialMode(inputs, itemID, mode)
    if mode ~= "auto" and mode ~= "prefer" and mode ~= "never" then return false end
    inputs.avoided, inputs.preferred = inputs.avoided or {}, inputs.preferred or {}
    inputs.avoided[itemID] = mode == "never" or nil
    inputs.preferred[itemID] = mode == "prefer" or nil
    return true
end

-- How the player gets a material (Prices Context:GetMode says what each
-- does): "auto" (made or bought, whichever costs less per item), "make", "buy",
-- "gather-valued" or "gather-free". Stored as options.gather (the two gather
-- modes, as they always were) and options.get (make or buy). `craftable`:
-- whether a recipe the route may use makes it, which makes "auto" the
-- default; otherwise it is "buy".
Planner.getModes = { "auto", "make", "buy", "gather-valued", "gather-free" }

function Planner:GetMode(inputs, itemID, craftable)
    local options = inputs.options or {}
    local gather = options.gather and options.gather[itemID]
    if gather == "zero" then return "gather-free" end
    if gather then return "gather-valued" end
    local chosen = options.get and options.get[itemID]
    if chosen == "buy" or not craftable then return "buy" end
    return chosen == "make" and "make" or "auto"
end

function Planner:SetGetMode(inputs, itemID, mode)
    local gather = ({ ["gather-valued"] = "opportunity", ["gather-free"] = "zero" })[mode]
    if mode ~= "auto" and mode ~= "make" and mode ~= "buy" and not gather then return false end
    inputs.options = inputs.options or {}
    local options = inputs.options
    options.gather, options.get = options.gather or {}, options.get or {}
    options.gather[itemID] = gather
    -- Auto is the default, so only make or buy is kept.
    options.get[itemID] = (mode == "make" or mode == "buy") and mode or nil
    return true
end

-- Whether what a recipe makes counts as sold:
--   default  follows options.sellOutput (sold at its best price with "all",
--            not sold with "chosen")
--   sell     sold, at the best allowed price (options.sell)
--   vendor   sold, at the vendor price only (options.keep)
--   keep     never counted as sold (options.nosell)
-- The same in both sellOutput modes, except "default".
Planner.saleModes = { "default", "sell", "vendor", "keep" }

function Planner:SaleMode(inputs, itemID)
    local options = inputs.options or {}
    if options.nosell and options.nosell[itemID] then return "keep" end
    if options.keep and options.keep[itemID] then return "vendor" end
    if options.sell and options.sell[itemID] then return "sell" end
    return "default"
end

function Planner:SetSaleMode(inputs, itemID, mode)
    if mode ~= "default" and mode ~= "sell" and mode ~= "vendor" and mode ~= "keep" then return false end
    inputs.options = inputs.options or {}
    local options = inputs.options
    options.sell, options.keep, options.nosell = options.sell or {}, options.keep or {}, options.nosell or {}
    options.sell[itemID] = mode == "sell" or nil
    options.keep[itemID] = mode == "vendor" or nil
    options.nosell[itemID] = mode == "keep" or nil
    return true
end

-- A goal as the planner reads it, or nil and why not.
function Planner:NormalizeGoal(goal)
    if type(goal) ~= "table" or type(goal.spell) ~= "number" then return nil, "a goal names a recipe spell" end
    local count = math.floor(tonumber(goal.count) or 1)
    if count < 1 then return nil, "a goal makes at least one" end
    local when = goal.when or "best"
    if not self.whens[when] then return nil, "when is best, now, end or skill" end
    local skill = tonumber(goal.skill)
    if when == "skill" and not skill then return nil, "a goal at a skill level needs the skill level" end
    return { spell = goal.spell, count = count, when = when, skill = skill }
end

function Planner:AddGoal(inputs, goal)
    local normal, problem = self:NormalizeGoal(goal)
    if not normal then return false, problem end
    inputs.goals = inputs.goals or {}
    table.insert(inputs.goals, normal)
    return true
end

function Planner:RemoveGoal(inputs, index)
    if inputs.goals and inputs.goals[index] then table.remove(inputs.goals, index) end
end

-- The goal for a recipe, and its index, or nil.
function Planner:FindGoal(inputs, spell)
    for index, goal in ipairs(inputs.goals or {}) do
        if goal.spell == spell then return goal, index end
    end
    return nil
end

-- One more of a recipe: a goal already set gets its count raised; a new one
-- makes one, at its best skill. It clears a refusal, which says the opposite.
function Planner:BumpGoal(inputs, spell)
    local goal = self:FindGoal(inputs, spell)
    if goal then
        goal.count = (goal.count or 1) + 1
        return true
    end
    if inputs.refused then inputs.refused[spell] = nil end
    return self:AddGoal(inputs, { spell = spell, count = 1, when = "best" })
end

-- `count` of an item were made (the client's "You create:" line, however
-- they were made): the goal whose recipe makes it counts them off in
-- crafts, and goes once it is all made. Returns the goal's spell and the
-- crafts left (0 when it went), or nil when no goal makes the item.
function Planner:GoalMade(inputs, data, itemID, count)
    local recipes = type(data) == "table" and data.recipes or {}
    for index, goal in ipairs(inputs and inputs.goals or {}) do
        local recipe = recipes[goal.spell]
        if recipe and recipe.makes == itemID then
            local crafts = math.max(1, math.floor((tonumber(count) or 1) / Prices().AverageMade(recipe) + 0.5))
            local left = math.max((goal.count or 1) - crafts, 0)
            if left == 0 then table.remove(inputs.goals, index) else goal.count = left end
            return goal.spell, left
        end
    end
    return nil
end

-- A goal's count, at least one (remove it to make none).
function Planner:SetGoalCount(inputs, index, count)
    local goal = inputs.goals and inputs.goals[index]
    count = math.floor(tonumber(count) or 0)
    if not goal or count < 1 then return false end
    goal.count = count
    return true
end

-- A goal's when; "skill" keeps the skill given, or the one it had, or `skill`
-- falls back to the recipe's learn skill the caller passes.
Planner.whenOrder = { "best", "now", "end", "skill" }

function Planner:SetGoalWhen(inputs, index, when, skill)
    local goal = inputs.goals and inputs.goals[index]
    if not goal or not self.whens[when] then return false end
    if when == "skill" then
        skill = tonumber(skill) or goal.skill
        if not skill then return false end
        goal.skill = math.floor(skill)
    else
        goal.skill = nil
    end
    goal.when = when
    return true
end

-- The when after a goal's own, for the button that cycles through them.
function Planner:NextWhen(when)
    for index, name in ipairs(self.whenOrder) do
        if name == when then return self.whenOrder[index % #self.whenOrder + 1] end
    end
    return "best"
end

-- A stable text of everything a route depends on except the live skill and
-- bags, so a changed input (a price, a goal, a refusal, a recipe learned) is
-- noticed by NeedsReplan.
local function serialize(value, out)
    local kind = type(value)
    if kind == "table" then
        table.insert(out, "{")
        for _, key in ipairs(sortedKeys(value)) do
            if type(value[key]) ~= "function" then
                table.insert(out, tostring(key) .. "=")
                serialize(value[key], out)
                table.insert(out, ",")
            end
        end
        table.insert(out, "}")
    elseif kind ~= "function" then
        table.insert(out, tostring(value))
    end
end

function Planner:Signature(input)
    local out = {}
    serialize({
        profession = input.profession, target = input.target, level = input.level, maxSkill = input.maxSkill,
        fullScope = input.fullScope, goals = input.goals, options = input.options, refused = input.refused, pinned = input.pinned,
        accepted = input.accepted, avoided = input.avoided, preferred = input.preferred, known = input.known,
        chosen = input.chosen, helpers = input.data and input.data.helpers,
        prices = Prices():Revision(input.book or Prices():Book()),
    }, out)
    return table.concat(out)
end

-- Tiers --------------------------------------------------------------------

local function tierSet(input)
    return input.tiers or ns.modules.ProfessionTiers
end

-- The trained cap: what the client said, or the smallest tier cap at or above
-- the skill (a skill sitting on a cap is taken as needing the next tier).
local function currentCap(tiers, skill, maxSkill)
    if maxSkill then return maxSkill end
    if skill <= 0 then return 0 end
    for _, tier in ipairs(tiers.tiers) do
        if skill <= tier.cap then return tier.cap end
    end
    return tiers:MaxCap()
end

-- The highest skill the character can train to now: the tier cap their level
-- allows, or the cap they have already trained when that is higher (the
-- client's word beats the unverified gates), never past the tiers at this
-- scope.
local function trainableCap(tiers, skill, maxSkill, level)
    local cap = math.max(tiers:CapForLevel(tonumber(level)), currentCap(tiers, skill, tonumber(maxSkill)))
    return math.min(cap, tiers:MaxCap())
end

-- The target a plan takes when the player gave none: as far as the character
-- can train now. `input` as for Plan (skill, maxSkill, level, tiers).
function Planner:DefaultTarget(input)
    input = input or {}
    local skill = math.max(tonumber(input.skill) or 0, 0)
    return trainableCap(tierSet(input), skill, input.maxSkill, input.level)
end

-- Planning -----------------------------------------------------------------

-- What learning a recipe costs, or nil and the kind of suggestion it would
-- be, and what is known of getting it.
--
-- The route uses, unasked, what the character knows, starts with, and learns
-- at a trainer. With `options.recipes = "patterns"` (the default) every
-- pattern the character lacks joins them too, as if it could be had: at its
-- known gold price (a vendor, the player's auction price), else free and
-- `costUnknown` (a BoE pattern nobody priced, and every BoP one, whose price
-- nobody can know). Such a recipe's info carries `needsPattern` = { bind,
-- source, cost, npc, teach }, which the route hands to its runs and learn
-- events so the tabs can mark them. With "trainer" a pattern is only a
-- suggestion carrying its price ("bop", or "boe" with no offer, when there
-- is none), and "Use it" or a pin brings it in at that price. A pattern the
-- player said they have ("have") is in hand in either mode, with no mark; a
-- pin ("prefer") does not say so, and keeps the mark. A pattern a merchant sells only for a currency has no gold price, so
-- it is whatever its binding makes it.
local function learnInfo(ctx, spell, recipe, input, options)
    if input.known and input.known[spell] then return { kind = "known", gold = 0 } end
    if recipe.learn == "start" then return { kind = "start", gold = 0 } end
    if recipe.learn == "trainer" then
        local cost, npc = ctx:TrainerCost(spell)
        return { kind = "trainer", gold = cost or 0, costUnknown = cost == nil or nil, npc = npc }
    end
    local accepted = (input.accepted and input.accepted[spell]) or (input.pinned and input.pinned[spell])
    local teach = recipe.teach
    local bind = recipe.bind == "boe" and "boe" or "bop"
    local offer
    if teach then
        local gold, npc = ctx:VendorPattern(teach)
        if gold then
            offer = { kind = "vendor", gold = gold, npc = npc, item = teach }
        elseif bind == "boe" then
            local price = ctx:AuctionPattern(teach)
            if price then offer = { kind = "boe", gold = price, item = teach } end
        end
    end
    local have = input.accepted and input.accepted[spell]
    if not have and options.recipes ~= "trainer" then
        local info = offer or { kind = bind, gold = 0, item = teach, costUnknown = true }
        info.needsPattern = { bind = bind, source = info.kind, cost = offer and offer.gold or nil,
            npc = offer and offer.npc or nil, teach = teach }
        return info
    end
    if offer then
        if accepted then
            offer.accepted = true
            return offer
        end
        return nil, offer.kind, offer
    end
    if accepted then
        return { kind = bind, gold = 0, item = teach, accepted = true, costUnknown = bind == "boe" or nil }
    end
    return nil, bind
end

-- The candidates at skill s: recipes giving skill at or above the floor, or
-- failing that any that give skill at all; pinned recipes first whenever one
-- is usable. `pick`, the entry of the recipe the player chose for a
-- stretch holding s, is the only candidate when it gives skill at s. A
-- recipe whose carried materials run out (`stopAt`, planning with only what
-- is carried) is none from that skill on.
local function candidatesAt(pool, s, floor, pinned, pick)
    local above, below, pins = {}, {}, {}
    local chance = SkillUp()
    local function chanceOf(entry)
        if entry.stopAt and s >= entry.stopAt then return 0 end
        return chance:Chance(entry.skills, s)
    end
    if pick and chanceOf(pick) > 0 then return { pick } end
    for _, entry in ipairs(pool) do
        local p = chanceOf(entry)
        if p > 0 then
            if p >= floor then
                table.insert(above, entry)
                if pinned[entry.spell] then table.insert(pins, entry) end
            else
                table.insert(below, entry)
            end
        end
    end
    if #pins > 0 then return pins end
    if #above > 0 then return above end
    return below
end

-- A list of chosen stretches with [from, to) carved out of it: one inside
-- goes, one across an end keeps its part outside. Returns the new list and
-- how many stretches it touched. A stretch without number skill levels is kept.
local function carve(list, from, to)
    local kept, touched = {}, 0
    for _, stretch in ipairs(list or {}) do
        local a = type(stretch) == "table" and tonumber(stretch.fromSkill)
        local b = type(stretch) == "table" and tonumber(stretch.toSkill)
        if a and b and a < to and b > from then
            touched = touched + 1
            if a < from then table.insert(kept, { fromSkill = a, toSkill = from, spell = stretch.spell }) end
            if b > to then table.insert(kept, { fromSkill = to, toSkill = b, spell = stretch.spell }) end
        else
            table.insert(kept, stretch)
        end
    end
    return kept, touched
end

local function sameRuns(a, b)
    if #a ~= #b then return false end
    for index, run in ipairs(a) do
        local other = b[index]
        if run.entry ~= other.entry or run.from ~= other.from or run.to ~= other.to then return false end
    end
    return true
end

-- Plans a route. `input`:
--
--   profession  "Leatherworking"
--   data        the profession's recipe data (Data/Professions/*.lua)
--   skill        the live skill (0: not learned)
--   maxSkill     the trained cap, when the client reports it
--   level       the character's level (nil: no level gate)
--   target      skill wanted (nil: the highest the character can train)
--   known       { [spellID] = true }, from the trade skill window
--   bags        function(itemID) -> count carried (the bags; not the bank)
--   goals, options, refused, pinned, accepted, avoided, preferred, chosen   see DefaultInputs
--   book        the price book (default NuuProfessionsDB.professions)
--   tiers       the tier table (default Data/ProfessionTiers.lua)
--   nameOf      function(kind, id) -> name, for the status line (optional)
--   fullData    the full-scope recipe data of the profession (Data/ProfessionsFull),
--               when `data` is the beta's: the route's gap note counts the
--               recipes the beta left out (optional)
--
-- Returns the route; see the end of this function for its shape.
-- The price context's share of the resolved options (Planner:Options).
local function contextOptions(options)
    return { auction = options.auction, gather = options.gather or {}, get = options.get or {}, keep = options.keep or {},
        sellOutput = options.sellOutput, sell = options.sell or {}, nosell = options.nosell or {},
        estimateFactor = options.estimateFactor, useAuctionator = options.useAuctionator }
end

function Planner:Plan(input)
    local S, P = SkillUp(), Prices()
    local data = input.data or {}
    local profession = input.profession or "Profession"
    local options = self:Options(input)
    options.gather, options.keep, options.sell = options.gather or {}, options.keep or {}, options.sell or {}
    options.nosell, options.get = options.nosell or {}, options.get or {}
    -- Only what is carried: the bags are the plan's, whatever useBags says.
    local carriedOnly = options.materials == "carried"
    if carriedOnly then options.useBags = true end
    -- With only what is carried the crafts are known and the skill levels they
    -- reach are the guess: the route plans them at the expected skill-ups,
    -- not at a margin that would end it short with materials in hand. The
    -- confidence is a shopping list's, and here nothing is bought.
    if carriedOnly then options.confidence = "typical" end
    -- On cost, what is sold never steers the route: an output is worth only
    -- the intermediate it replaces. Its sale is still counted in the money.
    local onCost = options.optimize ~= "profit"
    local floor = options.floor or S.floor
    local z = S:Z(options.confidence)
    -- Pins: the player's, then (below) every usable recipe that needs a
    -- material they prefer.
    local refused, pinned = input.refused or {}, copy(input.pinned or {})
    local tiers = tierSet(input)
    local book = input.book or P:Book() or {}
    local bags = input.bags or function() return 0 end
    local warnings = {}
    local function warn(code, text, extra)
        local row = extra or {}
        row.code, row.text = code, text
        table.insert(warnings, row)
    end

    local skill = math.max(tonumber(input.skill) or 0, 0)
    local start = math.max(skill, 1)
    local cap = currentCap(tiers, skill, input.maxSkill)

    -- How far the character can go: the tiers at this scope, their level
    -- gates, then what the recipes allow (found below). With no target, as
    -- far as the character can train now.
    local maxCap = tiers:MaxCap()
    local levelCap = trainableCap(tiers, skill, input.maxSkill, input.level)
    local target = tonumber(input.target) or levelCap
    local wanted = target
    local ceiling = { skill = target, reason = "target" }
    if target > maxCap then
        target, ceiling = maxCap, { skill = maxCap, reason = "tiers", text = "The trainers at this scope stop at " .. maxCap .. "." }
    end
    if target > levelCap then
        local gate
        for _, tier in ipairs(tiers.tiers) do
            if tier.cap > levelCap and not gate then gate = tier end
        end
        target = levelCap
        ceiling = { skill = levelCap, reason = "level", level = gate and gate.level, tier = gate and gate.name,
            text = gate and (gate.name .. " needs level " .. gate.level .. ".") or nil }
    end
    -- A target behind the skill (typed low, or a cap the skill is already
    -- past) plans nothing to grind: what is left, goals and the parts made
    -- for them, is done at the skill the character has, never behind it.
    if target < start then target, ceiling.skill = start, start end

    local ctxOptions = contextOptions(options)
    if carriedOnly then ctxOptions.carried = function(item) return bags(item) or 0 end end
    local entries, bySpell = {}, {}
    local banned = {}
    -- A recipe of another profession the character has (Planner:WithHelpers)
    -- only makes materials: it is always there to make them.
    local ctx = P:Context({ book = book, data = data, options = ctxOptions, canCraft = function(spell)
        local entry = bySpell[spell]
        if entry == nil then
            local recipe = data.recipes and data.recipes[spell]
            return recipe ~= nil and recipe.helper ~= nil
        end
        return entry.usable and not banned[spell]
    end })

    -- Training at each cap the route passes. The fee is the tier's, or what a
    -- trainer window showed for the tier's spell; unknown counts as 0.
    local trainings, boundaries, boundarySet = {}, {}, {}
    for index, tier in ipairs(tiers.tiers) do
        local lower = index > 1 and tiers.tiers[index - 1].cap or 0
        if tier.cap > cap and lower < target then
            local cost, npc = tier.cost, nil
            if cost == nil then cost, npc = P:TierCost(book, profession, tier) end
            table.insert(trainings, { kind = "train", skill = lower, tier = tier.name, cap = tier.cap,
                level = tier.level, cost = cost or 0, costUnknown = cost == nil or nil, npc = npc,
                verified = tier.verified or false })
            if lower > 0 then table.insert(boundaries, lower); boundarySet[lower] = true end
            if cost == nil then
                warn("costUnknown", tier.name .. " training: cost unknown.", { tier = tier.name })
            end
        end
    end

    -- Every recipe the planner may consider, with what it costs to learn.
    for _, spell in ipairs(sortedKeys(data.recipes)) do
        local recipe = data.recipes[spell]
        if type(recipe) == "table" and type(recipe.skills) == "table" and not recipe.sod and not recipe.helper then
            local info, suggestion, offer = learnInfo(ctx, spell, recipe, input, options)
            local skills = self:Skills(book, spell, recipe)
            local entry = {
                spell = spell, recipe = recipe, skills = skills, item = recipe.makes,
                made = P.AverageMade(recipe), refused = refused[spell] or nil,
                avoids = self:AvoidedReagent(recipe, input.avoided),
                info = info, suggestion = (not info) and suggestion or nil, offer = (not info) and offer or nil,
            }
            -- Off: the player turned the recipe, or one of its materials, off.
            entry.off = entry.refused or entry.avoids ~= nil
            entry.usable = info ~= nil and not entry.off
            entry.learnGold = info and info.gold or 0
            bySpell[spell] = entry
            table.insert(entries, entry)
            if not entry.off and input.preferred then
                for _, reagent in ipairs(recipe.reagents or {}) do
                    if input.preferred[reagent[1]] then pinned[spell] = true end
                end
            end
        end
    end
    local unobtainable = {}
    for _, entry in ipairs(entries) do
        local mat, missing, estimated = ctx:ReagentCost(entry.recipe)
        entry.mat, entry.estimated = mat, estimated or nil
        if not mat and missing and not entry.off then
            -- Every reagent without a source, not only the first.
            for _, reagent in ipairs(entry.recipe.reagents or {}) do
                local item = reagent[1]
                if not ctx:BuyCost(item) then
                    unobtainable[item] = unobtainable[item] or {}
                    if unobtainable[item][#unobtainable[item]] ~= entry.spell then
                        table.insert(unobtainable[item], entry.spell)
                    end
                end
            end
        end
    end

    -- Goals, placed by their `when`, as free progress: a jump from the skill
    -- they are made at to the skill they are expected to leave behind.
    local goalPlan
    local function placeGoals()
        local placed = {}
        for index, raw in ipairs(input.goals or {}) do
            local goal, problem = self:NormalizeGoal(raw)
            local entry = goal and bySpell[goal.spell]
            if not goal then
                warn("goal", "Goal " .. index .. ": " .. problem)
            elseif not entry then
                warn("goal", "Goal " .. index .. ": no such recipe in this profession.", { spell = goal.spell })
            elseif entry.refused then
                warn("goal", "Goal " .. index .. " uses a recipe you refused; it is left out.", { spell = goal.spell })
            elseif entry.avoids then
                warn("goal", "Goal " .. index .. " needs a material you don't use; it is left out.",
                    { spell = goal.spell, item = entry.avoids })
            elseif not entry.mat then
                warn("goal", "Goal " .. index .. " needs a material with no source.", { spell = goal.spell })
            else
                local orange = entry.skills[1]
                local fire
                if goal.when == "now" then fire = start
                elseif goal.when == "skill" then fire = goal.skill
                elseif goal.when == "best" then fire = orange
                end
                local atEnd = goal.when == "end"
                if fire and fire < orange then
                    if goal.when == "now" then
                        warn("goal", "Goal " .. index .. " cannot be made until skill " .. orange .. ".", { spell = goal.spell })
                    end
                    fire = orange
                end
                if fire and fire < start then fire = start end
                if not fire or fire >= target then atEnd, fire = true, target end
                if atEnd and orange > target then
                    warn("goal", "Goal " .. index .. " needs skill " .. orange .. ", past this plan.", { spell = goal.spell })
                end
                table.insert(placed, { index = index, goal = goal, entry = entry, fire = fire, atEnd = atEnd })
            end
        end
        table.sort(placed, function(a, b)
            if a.fire ~= b.fire then return a.fire < b.fire end
            return a.index < b.index
        end)
        local jumps, lastEnd = {}, -1
        for _, place in ipairs(placed) do
            if not place.atEnd then
                if place.fire < lastEnd then place.fire = lastEnd end
                local gain = S:Gain(place.entry.skills, place.fire, place.goal.count)
                local finish = place.fire + math.floor(gain + 0.5)
                -- A skill cap stops the skill until the next tier is trained.
                for _, boundary in ipairs(boundaries) do
                    if place.fire < boundary and finish > boundary then finish = boundary end
                end
                place.gain = finish - place.fire
                if place.gain > 0 then
                    jumps[place.fire] = finish
                    lastEnd = finish
                end
            else
                place.gain = 0
            end
        end
        return { placed = placed, jumps = jumps }
    end
    local goalWarnings = #warnings
    goalPlan = placeGoals()
    -- A goal's recipe is learned for the goal, so the grind may use it free.
    local goalSpells = {}
    for _, place in ipairs(goalPlan.placed) do goalSpells[place.entry.spell] = true end

    local function inRange(entry)
        return entry.skills[1] < target and entry.skills[4] > start
    end

    -- The stretches the player chose ("Use this" on one of a step's
    -- choices), inside this route's skill levels. One naming a recipe that is off,
    -- or not in this profession, is left out; a later stretch wins where two
    -- overlap.
    local stretches = {}
    for _, raw in ipairs(input.chosen or {}) do
        local from = type(raw) == "table" and tonumber(raw.fromSkill)
        local to = type(raw) == "table" and tonumber(raw.toSkill)
        local entry = type(raw) == "table" and bySpell[raw.spell]
        if entry and not entry.off and from and to and math.max(from, start) < math.min(to, target) then
            table.insert(stretches, { fromSkill = math.max(from, start), toSkill = math.min(to, target), spell = raw.spell })
        end
    end
    -- Skill -> chosen recipe, from a list of stretches, and the skill levels where
    -- one starts or ends: a run is cut there, so a chosen stretch is a step
    -- of its own and never runs on into a neighbour making the same recipe.
    -- Split every N skill levels, the plan's sections are the skill levels cut at each
    -- multiple of N, and a run is cut there too: a recipe that crosses one
    -- is two steps, each with its own crafts and shopping.
    local bandCuts = {}
    if options.sections == "band" then
        local size = math.max(5, math.floor(tonumber(options.bandSize) or self.defaultOptions.bandSize))
        for at = (math.floor(start / size) + 1) * size, target - 1, size do bandCuts[at] = true end
    end
    local function picksOf(list)
        local picks, cuts = {}, {}
        for at in pairs(bandCuts) do cuts[at] = true end
        for _, stretch in ipairs(list or {}) do
            for at = stretch.fromSkill, stretch.toSkill - 1 do picks[at] = stretch.spell end
            cuts[stretch.fromSkill], cuts[stretch.toSkill] = true, true
        end
        return picks, cuts
    end

    local function makePool(state)
        local pool = {}
        for _, entry in ipairs(entries) do
            local usable = (entry.usable and not state.banned[entry.spell]) or (state.extra[entry.spell] and not entry.off)
            if usable and entry.mat and inRange(entry) then table.insert(pool, entry) end
        end
        return pool
    end

    -- The ways past a skill no usable recipe gives skill at, for the note at
    -- the end of the route (route.gap): `to`, the next skill one does, and
    -- `options`, each { kind, spell, ... }:
    --   pattern    a pattern not in hand: source, cost, npc (as RecipeSource),
    --              item and bind; `continues` when "I have it" carries the
    --              route on (its materials have a source)
    --   refused    a recipe set to Never use
    --   avoided    a recipe needing `item`, a material set to Never use
    --   unlearned  a recipe the route may use but cannot: `reason` "price",
    --              `item` the material with no source
    --   beyond     (one option) recipes of `fullData` that the beta's data
    --              left out: `count`, and the first few { spell, makes, item },
    --              item the reagent that left it out (one the beta's data does
    --              not have, else the highest item level)
    local function gapAt(s, pool, top)
        local gap = { skill = s, options = {} }
        for r = s + 1, top - 1 do
            for _, entry in ipairs(pool) do
                if S:Chance(entry.skills, r) > 0 then gap.to = r; break end
            end
            if gap.to then break end
        end
        local found = {}
        for _, entry in ipairs(entries) do
            if S:Chance(entry.skills, s) > 0 then
                local spell = entry.spell
                if entry.refused then
                    table.insert(found, { kind = "refused", spell = spell })
                elseif entry.avoids then
                    table.insert(found, { kind = "avoided", spell = spell, item = entry.avoids })
                elseif not entry.info then
                    local source, cost, npc = self:RecipeSource(ctx, spell, entry.recipe)
                    table.insert(found, { kind = "pattern", spell = spell, item = entry.recipe.teach,
                        bind = entry.recipe.bind == "boe" and "boe" or "bop", source = source, cost = cost, npc = npc,
                        continues = entry.mat ~= nil })
                elseif not entry.mat then
                    local missing
                    for _, reagent in ipairs(entry.recipe.reagents or {}) do
                        if not missing and not ctx:BuyCost(reagent[1]) then missing = reagent[1] end
                    end
                    table.insert(found, { kind = "unlearned", spell = spell, reason = "price", item = missing })
                end
            end
        end
        -- Patterns that carry the route on first, then the rest as listed.
        local order = { pattern = 1, refused = 2, avoided = 3, unlearned = 4 }
        table.sort(found, function(a, b)
            if order[a.kind] ~= order[b.kind] then return order[a.kind] < order[b.kind] end
            if a.kind == "pattern" and a.continues ~= b.continues then return a.continues == true end
            return a.spell < b.spell
        end)
        gap.options = found
        local full = not input.fullScope and input.fullData
        if type(full) == "table" and type(full.recipes) == "table" then
            local beyond = { kind = "beyond", count = 0, recipes = {} }
            local fullItems, ownItems = full.items or {}, data.items or {}
            for _, spell in ipairs(sortedKeys(full.recipes)) do
                local recipe = full.recipes[spell]
                if type(recipe) == "table" and type(recipe.skills) == "table" and not recipe.sod
                    and not (data.recipes and data.recipes[spell]) and S:Chance(recipe.skills, s) > 0 then
                    beyond.count = beyond.count + 1
                    if #beyond.recipes < 3 then
                        local item, score
                        for _, reagent in ipairs(recipe.reagents or {}) do
                            local row = fullItems[reagent[1]]
                            local mine = (ownItems[reagent[1]] and 0 or 1000) + (row and tonumber(row.ilvl) or 0)
                            if not score or mine > score then item, score = reagent[1], mine end
                        end
                        table.insert(beyond.recipes, { spell = spell, makes = recipe.makes, item = item })
                    end
                end
            end
            if beyond.count > 0 then table.insert(gap.options, beyond) end
        end
        return gap
    end
    local gap

    -- How far the recipes reach: the first skill nothing gives skill at
    -- (goals may carry the player past a gap).
    do
        local pool = makePool({ banned = {}, extra = {} })
        local s = start
        while s < target do
            local jump = goalPlan.jumps[s]
            if jump then
                s = jump
            elseif #candidatesAt(pool, s, floor, pinned) == 0 then
                gap = gapAt(s, pool, target)
                ceiling = { skill = s, reason = "recipes", text = "No usable recipe gives skill at " .. s .. "." }
                target = s
                for index = #warnings, goalWarnings + 1, -1 do warnings[index] = nil end
                goalPlan = placeGoals()
                break
            else
                s = s + 1
            end
        end
    end
    local goalJumps = goalPlan.jumps

    -- Batches: every run and goal in the order the player makes them. A run
    -- is a solve's ({ entry, from, to }) or the route's row ({ entry,
    -- fromSkill, toSkill, expected, count }).
    local function batchesOf(runList)
        local list = {}
        for _, run in ipairs(runList) do
            local from, to = run.fromSkill or run.from, run.toSkill or run.to
            local expected = run.expected or S:Span(run.entry.skills, from, to) or 0
            table.insert(list, { run = run, entry = run.entry, skill = from, toSkill = to,
                expected = expected, count = run.count or expected, order = 4 })
        end
        for _, place in ipairs(goalPlan.placed) do
            local fire = place.atEnd and target or place.fire
            table.insert(list, { goal = place, entry = place.entry, skill = fire, toSkill = fire + (place.gain or 0),
                expected = place.goal.count, count = place.goal.count, order = place.atEnd and 9 or 3 })
        end
        table.sort(list, function(a, b)
            if a.skill ~= b.skill then return a.skill < b.skill end
            return a.order < b.order
        end)
        return list
    end

    -- Walks the batches taking materials from what earlier runs made, then the
    -- bags, then buying or making each as its mode says (Prices
    -- Context:GetMode). `sized` uses the confidence counts in whole crafts;
    -- otherwise expected counts. Each batch gets `intermediates` (spell ->
    -- crafts made for it) and `makeOrder`, those spells in the order they are
    -- made, the parts before what they make. Planning with only what is
    -- carried, `wanted` holds what each batch asks of an item and `short`
    -- what of it neither the route nor the bags had (an item a vendor sells
    -- is never short).
    local function ledger(list, sized)
        local stock, carried, bought, fromBags, lastSkill, firstSkill = {}, {}, {}, {}, {}, {}
        local noEscape, made = {}, {}
        local function have(item)
            if carried[item] == nil then carried[item] = options.useBags and (bags(item) or 0) or 0 end
            return carried[item]
        end
        local function acquire(item, quantity, batch, depth)
            batch.wanted[item] = (batch.wanted[item] or 0) + quantity
            local fromStock = math.min(stock[item] or 0, quantity)
            if fromStock > 0 then
                stock[item] = stock[item] - fromStock
                quantity = quantity - fromStock
                batch.fromRoute[item] = true
            end
            local carriedNow = math.min(have(item), quantity)
            if carriedNow > 0 then
                carried[item] = carried[item] - carriedNow
                fromBags[item] = (fromBags[item] or 0) + carriedNow
                batch.buys[item] = (batch.buys[item] or 0) + carriedNow
                quantity = quantity - carriedNow
            end
            firstSkill[item] = firstSkill[item] or batch.skill
            if batch.goal and batch.goal.atEnd then noEscape[item] = true end
            lastSkill[item] = math.max(lastSkill[item] or 0, batch.toSkill)
            if quantity <= 1e-9 then return end
            local _, source, detail = ctx:BuyCost(item)
            if source == "craft" and depth < 8 then
                local recipe = data.recipes[detail.spell]
                local each = P.AverageMade(recipe)
                local crafts = sized and math.ceil(quantity / each - 1e-9) or quantity / each
                for _, reagent in ipairs(recipe.reagents or {}) do
                    acquire(reagent[1], crafts * (reagent[2] or 1), batch, depth + 1)
                end
                stock[item] = (stock[item] or 0) + crafts * each - quantity
                if not batch.intermediates[detail.spell] then table.insert(batch.makeOrder, detail.spell) end
                batch.intermediates[detail.spell] = (batch.intermediates[detail.spell] or 0) + crafts
                made[item] = true
            else
                bought[item] = (bought[item] or 0) + quantity
                batch.buys[item] = (batch.buys[item] or 0) + quantity
                if source == "carried" then batch.short[item] = (batch.short[item] or 0) + quantity end
            end
        end
        -- A batch's intermediates in the order they can be made: each after
        -- the ones making its parts. They are listed as first needed, and a
        -- part needed later (bronze first made from bars in the bags, more
        -- bronze later needing bars smelted) would come after what it goes into.
        local function partsFirst(order)
            local maker, position, depthOf = {}, {}, {}
            for index, spell in ipairs(order) do
                position[spell] = index
                local recipe = data.recipes[spell]
                if recipe and recipe.makes then maker[recipe.makes] = spell end
            end
            local function depth(spell, guard)
                if depthOf[spell] then return depthOf[spell] end
                if guard > 8 then return 0 end
                local deepest = 0
                for _, reagent in ipairs(data.recipes[spell] and data.recipes[spell].reagents or {}) do
                    local part = maker[reagent[1]]
                    if part and part ~= spell then deepest = math.max(deepest, depth(part, guard + 1) + 1) end
                end
                depthOf[spell] = deepest
                return deepest
            end
            local sorted = {}
            for _, spell in ipairs(order) do depth(spell, 0); table.insert(sorted, spell) end
            table.sort(sorted, function(a, b)
                if depthOf[a] ~= depthOf[b] then return depthOf[a] < depthOf[b] end
                return position[a] < position[b]
            end)
            return sorted
        end
        -- `buys`: what each batch brings from the bags or the shops, which
        -- is its section's shopping when the plan is split (Planner:Sections).
        for _, batch in ipairs(list) do
            batch.fromRoute, batch.intermediates, batch.makeOrder, batch.buys = {}, {}, {}, {}
            batch.wanted, batch.short = {}, {}
            local crafts = sized and batch.count or batch.expected
            for _, reagent in ipairs(batch.entry.recipe.reagents or {}) do
                acquire(reagent[1], crafts * (reagent[2] or 1), batch, 0)
            end
            if not batch.goal and batch.entry.item then
                stock[batch.entry.item] = (stock[batch.entry.item] or 0) + crafts * batch.entry.made
                made[batch.entry.item] = true
            end
            batch.makeOrder = partsFirst(batch.makeOrder)
        end
        return { stock = stock, bought = bought, fromBags = fromBags, carried = carried,
            lastSkill = lastSkill, firstSkill = firstSkill, noEscape = noEscape, made = made }
    end
    -- How many crafts of a batch in `list` the bags cover (sized, as the
    -- ledger walks it), found by trying counts: what is short of a part
    -- the bags partly hold (bars in hand, the rest to smelt from ore) says
    -- nothing by itself of the crafts, since the part in hand came first.
    -- The list is walked again at the batch's own count before returning.
    local function possibleCrafts(list, batch)
        local keep = batch.count
        local low, high = 0, math.floor(keep + 1e-9)
        while low < high do
            local middle = math.floor((low + high + 1) / 2)
            batch.count = middle
            ledger(list, true)
            local short = false
            for _, count in pairs(batch.short) do
                if count > 1e-9 then short = true end
            end
            if short then high = middle - 1 else low = middle end
        end
        batch.count = keep
        ledger(list, true)
        return low
    end

    -- Intermediates as progress. What a run needs made from its parts is
    -- made just before it, at the skill the route has then, and while its
    -- recipe gives skill there those crafts are points, walked skill by skill
    -- as a goal's are (the parts first). The skill levels they cover become a jump,
    -- like a goal's, which the next solve skips: the grind after it is that
    -- much shorter. Only a run's intermediates count; a goal's are made
    -- without skill.
    --
    -- The expected points of a batch's intermediates made at `fire`, in all
    -- and by spell. Its intermediates are the expected ledger's.
    local function makeGains(batch, fire)
        local at, gains = fire, {}
        for _, spell in ipairs(batch.makeOrder or {}) do
            local entry = bySpell[spell]
            local recipe = data.recipes[spell]
            -- Another profession's recipe gives its own skill, not this one's.
            if entry or not recipe.helper then
                local before = at
                at = at + S:Gain(entry and entry.skills or recipe.skills, at, math.floor(batch.intermediates[spell] + 0.5))
                gains[spell] = at - before
            end
        end
        return at - fire, gains
    end
    -- The skill a batch's intermediates are made at: the start of the jump
    -- they made last pass (`endsAt`, finish -> start), else the batch's own.
    local function endsAtOf(made)
        local endsAt = {}
        for start, finish in pairs(made or {}) do endsAt[finish] = start end
        return endsAt
    end
    -- The make jumps (start -> finish) of a route's runs, given the last
    -- pass's. A jump stops at a trainer cap, at a goal and where a stretch
    -- the player chose starts or ends, and leaves its run at least one point
    -- of its own. None starts inside a chosen stretch: that stretch keeps
    -- the skill levels the player chose it for, and its intermediates are counted
    -- as giving no skill.
    local function makeJumpsFor(runList, previous, chosen)
        local endsAt = endsAtOf(previous)
        local picks, cuts = picksOf(chosen)
        local list = batchesOf(runList)
        ledger(list, false)
        local made = {}
        for _, batch in ipairs(list) do
            if not batch.goal and #batch.makeOrder > 0 then
                local fire = endsAt[batch.skill] or batch.skill
                local gain = makeGains(batch, fire)
                local finish = math.min(fire + math.floor(gain + 0.5), batch.toSkill - 1)
                for _, boundary in ipairs(boundaries) do
                    if fire < boundary and finish > boundary then finish = boundary end
                end
                for at in pairs(goalJumps) do
                    if fire < at and finish > at then finish = at end
                end
                for at in pairs(cuts) do
                    if fire < at and finish > at then finish = at end
                end
                if finish > fire and not goalJumps[fire] and not picks[fire] then made[fire] = finish end
            end
        end
        return made
    end
    local function withGoals(made)
        local merged = copy(goalJumps)
        for start, finish in pairs(made) do merged[start] = finish end
        return merged
    end
    local function sameJumps(a, b)
        for start, finish in pairs(a) do if b[start] ~= finish then return false end end
        for start in pairs(b) do if a[start] == nil then return false end end
        return true
    end

    -- Only what is carried: the carried units a craft of an entry takes, its
    -- own reagents and those of the parts it has made (entry.carriedUse,
    -- item -> units a craft). An item the bags hold and no vendor sells is
    -- "carried" (Prices Context:BuyCost).
    local function carriedUse(item, quantity, out, depth)
        local _, source, detail = ctx:BuyCost(item)
        if source == "carried" then
            out[item] = (out[item] or 0) + quantity
        elseif source == "craft" and depth < 8 then
            local recipe = data.recipes[detail.spell]
            local each = P.AverageMade(recipe)
            for _, reagent in ipairs(recipe.reagents or {}) do
                carriedUse(reagent[1], quantity * (reagent[2] or 1) / each, out, depth + 1)
            end
        end
        return out
    end
    local function usesOf(entry)
        if not entry.carriedUse then
            entry.carriedUse = {}
            for _, reagent in ipairs(entry.recipe.reagents or {}) do
                carriedUse(reagent[1], reagent[2] or 1, entry.carriedUse, 0)
            end
        end
        return entry.carriedUse
    end
    -- What the solve weighs a craft at, besides its money: pricing what is
    -- carried (tuneShadow below), a craft costs `perCraft` (so of two free
    -- recipes the one needing fewer crafts wins), and each carried unit its
    -- `shadow` price, raised until the route fits in the bags. The route's
    -- own money (`net`, `value`) stays gold.
    local craftCost = carriedOnly and self.carriedCraftCost or 0
    local shadow, perCraft = {}, 0

    -- One solve: the DP backwards over skill levels, then a walk forwards to read the
    -- route off it. `state.extra` makes recipes available and free (a
    -- suggestion being priced), `state.banned` takes them away,
    -- `state.value` overrides what an output is worth per item
    -- (intermediates and market depth), `state.chosen` holds the
    -- player's chosen stretches, and `state.jumps` the skill levels goals and
    -- intermediates give free (default: the goals').
    local function solve(state)
        local jumps = state.jumps or goalJumps
        local pool = makePool(state)
        local picks, cuts = picksOf(state.chosen)
        local pickable = {}
        for _, entry in ipairs(state.chosen and makePool({ banned = banned, extra = state.extra }) or {}) do
            pickable[entry.spell] = entry
        end
        local netOf, costOf = {}, {}
        local function price(entry)
            local unit = 0
            if entry.item then
                unit = state.value[entry.item]
                if unit == nil then unit = onCost and 0 or (ctx:SellValue(entry.item)) end
            end
            netOf[entry] = entry.mat - entry.made * unit
            local weight = netOf[entry] + perCraft
            for item, units in pairs(carriedOnly and usesOf(entry) or {}) do
                weight = weight + (shadow[item] or 0) * units
            end
            costOf[entry] = weight
        end
        for _, entry in ipairs(pool) do price(entry) end
        for _, entry in pairs(pickable) do price(entry) end
        local function learn(entry)
            if state.extra[entry.spell] or goalSpells[entry.spell] then return 0 end
            return entry.learnGold
        end
        local V = {}
        local function valueOf(s, spell)
            while jumps[s] and s < target do s = jumps[s] end
            if s >= target then return 0 end
            local row = V[s]
            if not row then return INF end
            local stay = spell and row.stay[spell]
            if stay and stay < row.best then return stay end
            return row.best
        end
        for s = target - 1, start, -1 do
            if not jumps[s] then
                local pick = picks[s] and pickable[picks[s]]
                -- Pricing what is carried, the floor gives way: a scarce
                -- recipe's price, not the floor, says when a slow one
                -- beats it, and each craft is counted.
                local list = candidatesAt(pool, s, perCraft > 0 and 0 or floor, pinned, pick)
                if #list > 0 then
                    local row = { stay = {}, best = INF, per = {} }
                    for _, entry in ipairs(list) do
                        local chance = S:Chance(entry.skills, s)
                        local stay = costOf[entry] / chance + valueOf(s + 1, entry.spell)
                        row.stay[entry.spell], row.per[entry.spell] = stay, netOf[entry] / chance
                        local switch = stay + learn(entry)
                        if switch < row.best - EPS then row.best, row.bestEntry = switch, entry end
                    end
                    row.list = list
                    V[s] = row
                end
            end
        end
        local runs, s, prev = {}, start, nil
        local value = valueOf(start, nil)
        if value == INF then return nil end
        local broken = false
        while s < target do
            -- A run ends at a trainer cap, where training comes in between,
            -- and where a chosen stretch starts or ends.
            if boundarySet[s] or cuts[s] then broken = true end
            if jumps[s] then
                s = jumps[s]
                broken = true
            else
                local row = V[s]
                if not row then return nil end
                local choice = row.bestEntry
                if prev and row.stay[prev.spell] and row.stay[prev.spell] <= row.best + EPS then choice = prev end
                local last = runs[#runs]
                if last and not broken and last.entry == choice and last.to == s then
                    last.to = s + 1
                else
                    table.insert(runs, { entry = choice, from = s, to = s + 1 })
                end
                broken = false
                prev = choice
                s = s + 1
            end
        end
        -- The solve weighed crafts and carried units too (perCraft, shadow):
        -- the route's value is its money alone, what its runs cost and the
        -- recipes learned on the way.
        if carriedOnly then
            value, prev = 0, nil
            for _, run in ipairs(runs) do
                if run.entry ~= prev then value = value + learn(run.entry) end
                for at = run.from, run.to - 1 do value = value + netOf[run.entry] / S:Chance(run.entry.skills, at) end
                prev = run.entry
            end
        end
        return { value = value, runs = runs, V = V, net = netOf, learn = learn }
    end

    -- Second passes: an output a later run consumes is worth what it would
    -- cost to replace; past the market's depth, copies are worth the vendor
    -- price. Re-solve until the route stops changing.
    -- `counted`: value the sales too, for the money shown, even on cost.
    local function revalue(runs, counted)
        local produced, consumed = {}, {}
        for _, run in ipairs(runs) do
            local expected = S:Span(run.entry.skills, run.from, run.to) or 0
            if run.entry.item then
                produced[run.entry.item] = (produced[run.entry.item] or 0) + expected * run.entry.made
            end
            for _, reagent in ipairs(run.entry.recipe.reagents or {}) do
                consumed[reagent[1]] = (consumed[reagent[1]] or 0) + expected * (reagent[2] or 1)
            end
        end
        local value = {}
        for item, count in pairs(produced) do
            if count > 0 then
                local used = math.min(count, consumed[item] or 0)
                local replace = used > 0 and ctx:BuyCost(item) or nil
                if not replace then used = 0 end
                local sold = (counted or not onCost) and ctx:SellTotal(item, count - used) or 0
                value[item] = ((replace or 0) * used + sold) / count
            end
        end
        return value
    end

    -- Each pass also places the intermediates' skill (makeJumpsFor), so
    -- `state.made` ends as the make jumps the returned route was solved with.
    local function solvePasses(state)
        local result = solve(state)
        if not result then return nil end
        for _ = 2, self.maxPasses do
            -- An output the new route no longer makes keeps the value the
            -- last pass gave it, or the route would flip back and forth
            -- between a recipe and its capped rival.
            local value = revalue(result.runs)
            for item, unit in pairs(state.value) do
                if value[item] == nil then value[item] = unit end
            end
            state.value = value
            local before, beforeJumps = state.made or {}, state.jumps
            local made = makeJumpsFor(result.runs, before, state.chosen)
            state.made, state.jumps = made, withGoals(made)
            local next = solve(state)
            if not next then
                state.made, state.jumps = before, beforeJumps
                break
            end
            local stable = sameRuns(next.runs, result.runs) and sameJumps(made, before)
            result = next
            if stable then break end
        end
        return result
    end

    -- A chosen stretch that leaves no route is dropped for this plan rather
    -- than losing the whole route: each is tried in turn on top of those
    -- kept, and one that makes the solve fail is left out.
    local state = { banned = banned, extra = {}, value = {}, chosen = stretches }
    local result = target > start and solvePasses(state) or { value = 0, runs = {}, net = {}, learn = function() return 0 end }
    if not result and #stretches > 0 then
        local kept = {}
        for _, stretch in ipairs(stretches) do
            table.insert(kept, stretch)
            if not solve({ banned = banned, extra = {}, value = {}, chosen = kept }) then
                table.remove(kept)
                warn("chosen", "Your pick for " .. stretch.fromSkill .. "-" .. stretch.toSkill
                    .. " leaves no route; it is ignored.", { spell = stretch.spell, skill = stretch.fromSkill })
            end
        end
        stretches = kept
        state = { banned = banned, extra = {}, value = {}, chosen = stretches }
        result = solvePasses(state)
    end
    if not result then
        warn("noRoute", "No route reaches " .. target .. " with the recipes available.")
        result = { value = 0, runs = {}, net = {}, learn = function() return 0 end }
    end

    -- Only what is carried: the bags hold so many of an item no vendor
    -- sells. The route's batches are walked at the confidence counts, each
    -- run with its own spread (at least what the shopping list will ask);
    -- where an item first runs short, the run is cut at the skill the bags
    -- take it to, and from there every recipe needing that item (itself, or
    -- in a part the route makes) is out (`stopAt`). Then the route is solved
    -- again, and stops at the first skill nothing is left for. The cuts only
    -- move down, so this ends.
    local ranOut = {}
    -- A solve's runs as batches at the confidence counts (`low`: the low
    -- end of each run's range, what its Make button orders), walked through
    -- the ledger.
    local function sizedBatches(runList, low)
        local sized = {}
        for _, run in ipairs(runList) do
            local expected, variance = S:Span(run.entry.skills, run.from, run.to)
            local count = low and (S:Range(expected or 0, variance, z, run.to - run.from))
                or S:Count(expected or 0, variance, z)
            table.insert(sized, { entry = run.entry, from = run.from, to = run.to, expected = expected or 0,
                count = count })
        end
        local list = batchesOf(sized)
        ledger(list, true)
        return list
    end
    local function cutRuns(runList)
        local list = sizedBatches(runList)
        local changed, seen = false, {}
        for _, batch in ipairs(list) do
            local possible
            local shortItems = {}
            for item, short in pairs(batch.short) do
                if short > 1e-9 then table.insert(shortItems, item) end
            end
            table.sort(shortItems)
            for _, item in ipairs(shortItems) do
                -- A goal's shortfall is told, not cut (see the shopping check);
                -- the run after it that the goal left short is still cut.
                if not seen[item] and not batch.goal then
                    seen[item] = true
                    do
                        possible = possible or possibleCrafts(list, batch)
                        local reached = batch.skill
                        for s = batch.skill, batch.toSkill - 2 do
                            local expected, variance = S:Span(batch.entry.skills, batch.skill, s + 1)
                            if not expected or S:Count(expected, variance, z) > possible then break end
                            reached = s + 1
                        end
                        -- What is left still makes a craft or more: the next
                        -- point is worth the try, whatever the confidence
                        -- asks, or the route would end with materials in hand.
                        if reached == batch.skill and possible >= 1 then reached = batch.skill + 1 end
                        if not ranOut[item] or reached < ranOut[item] then
                            ranOut[item] = reached
                            changed = true
                        end
                    end
                end
            end
        end
        if not changed then return false end
        for _, entry in ipairs(entries) do
            for item in pairs(usesOf(entry)) do
                if ranOut[item] and (not entry.stopAt or ranOut[item] < entry.stopAt) then entry.stopAt = ranOut[item] end
            end
        end
        return true
    end
    -- The first skill nothing is left for, below the target.
    local function carriedReach()
        local pool = makePool({ banned = banned, extra = {} })
        local s = start
        while s < target do
            if goalPlan.jumps[s] then
                s = goalPlan.jumps[s]
            elseif #candidatesAt(pool, s, floor, pinned) == 0 then
                return s
            else
                s = s + 1
            end
        end
        return nil
    end
    -- The cuts spend a carried item on the first skill levels that use it, which is
    -- not where it does most: a recipe that is orange all the way (a sure
    -- point) loses nothing by waiting, while a yellow rival's chance falls
    -- with every skill. So the route is also solved with a shadow price on
    -- each carried item, raised until the route fits in the bags: the
    -- solve then spends the item where it saves the most crafts. The
    -- price rises per item that runs short, by fours and then halving the
    -- gap, to the lowest that fits. When no price makes it fit (the bags
    -- cannot reach the target): nil, nil and the item that ran short, with
    -- `shadow` left as it was. A route fits when the bags make the low end
    -- of each run's crafts, as the cuts let the last craft try for a point.
    local function shortOf(runList)
        local short = {}
        for _, batch in ipairs(sizedBatches(runList, true)) do
            if not batch.goal then
                for item, count in pairs(batch.short) do
                    if count > 1e-9 then short[item] = (short[item] or 0) + count end
                end
            end
        end
        return short
    end
    -- The lowest price that fits, rising from `from`: `set(price)` puts it
    -- in place and `fits(route)` judges the solve's route. By fours, then
    -- halving the gap (on a log scale). The route and its state, or nil
    -- when none fits.
    local function lowestFit(from, set, fits)
        local low, high, best, bestState = from, nil, nil, nil
        local price = math.max(from * 4, 1)
        for _ = 1, 12 do
            set(price)
            local trial = { banned = banned, extra = {}, value = {}, chosen = stretches }
            local fit = solvePasses(trial)
            if fit and fits(fit) then
                high, best, bestState = price, fit, trial
                break
            end
            low, price = price, price * 4
        end
        if not high then return nil end
        for _ = 1, 6 do
            local middle = low > 0 and math.sqrt(low * high) or high / 4
            set(middle)
            local trial = { banned = banned, extra = {}, value = {}, chosen = stretches }
            local fit = solvePasses(trial)
            if fit and fits(fit) then
                high, best, bestState = middle, fit, trial
            else
                low = middle
            end
        end
        set(high)
        return best, bestState
    end
    -- Each item that runs short is priced in turn to the lowest that fits
    -- it. Two scarce items trade against each other (pricing one pushes
    -- the route onto the other), so a round that leaves any short then
    -- scales every price together until all fit.
    local function tuneShadow()
        local before = copy(shadow)
        local tunedState = { banned = banned, extra = {}, value = {}, chosen = stretches }
        local tuned = target > start and solvePasses(tunedState)
        local short = tuned and sortedKeys(shortOf(tuned.runs)) or {}
        if tuned and #short == 0 then return tuned, tunedState end
        for _, item in ipairs(tuned and short or {}) do
            local fit, fitState = lowestFit(shadow[item] or 0, function(price) shadow[item] = price end,
                function(route) return not shortOf(route.runs)[item] end)
            if not fit then
                shadow = before
                return nil, nil, item
            end
            tuned, tunedState = fit, fitState
        end
        short = tuned and sortedKeys(shortOf(tuned.runs)) or short
        if tuned and #short == 0 then return tuned, tunedState end
        local base = copy(shadow)
        for _, item in ipairs(short) do base[item] = base[item] or math.max(craftCost, 1) end
        local fit, fitState = lowestFit(1, function(scale)
            for item, price in pairs(base) do shadow[item] = price * scale end
        end, function(route) return next(shortOf(route.runs)) == nil end)
        if fit then return fit, fitState end
        shadow = before
        return nil, nil, short[1]
    end
    -- The target moved: the ceiling's skill and the goals placed again.
    local function retarget(skill)
        target = skill
        for index = #warnings, 1, -1 do
            if warnings[index].code == "goal" then table.remove(warnings, index) end
        end
        goalPlan = placeGoals()
        goalJumps = goalPlan.jumps
    end
    -- What a route costs the player, as the solve weighs it: its money and
    -- its crafts.
    local function burden(route)
        local crafts = 0
        for _, run in ipairs(route.runs) do crafts = crafts + (S:Span(run.entry.skills, run.from, run.to) or 0) end
        return route.value + craftCost * crafts
    end

    if carriedOnly then
        -- The priced route at the target asked, before the cuts move it. The
        -- cuts' own route is solved as it always was, on money alone.
        perCraft = craftCost
        local tuned, tunedState = tuneShadow()
        local tunedShadow, tunedAt = shadow, target
        shadow, perCraft = {}, 0
        local asked = { target = target, ceiling = ceiling, gap = gap }
        for _ = 1, 30 do
            if #result.runs == 0 or not cutRuns(result.runs) then break end
            local stop = carriedReach()
            if stop then
                target, gap = stop, nil
                ceiling = { skill = stop, reason = "materials", text = "What you carry runs out at " .. stop .. "." }
                -- The goals again, at the new target.
                for index = #warnings, 1, -1 do
                    if warnings[index].code == "goal" then table.remove(warnings, index) end
                end
                goalPlan = placeGoals()
                goalJumps = goalPlan.jumps
            end
            state = { banned = banned, extra = {}, value = {}, chosen = stretches }
            result = target > start and solvePasses(state) or { value = 0, runs = {}, net = {}, learn = function() return 0 end }
            if not result then
                warn("noRoute", "No route reaches " .. target .. " with what you carry.")
                result = { value = 0, runs = {}, net = {}, learn = function() return 0 end }
                break
            end
        end
        -- Where the cuts stopped short, priced again free of the cuts: at
        -- the skill they reach, then a skill higher while it still fits.
        local stops = {}
        for _, entry in ipairs(entries) do stops[entry] = entry.stopAt; entry.stopAt = nil end
        local cutAt, shortAt = target, nil
        if not tuned and target < asked.target and target > start then
            perCraft = craftCost
            tuned, tunedState = tuneShadow()
            tunedShadow, tunedAt = shadow, target
            shadow = {}
            while tuned and tunedAt < asked.target do
                retarget(tunedAt + 1)
                shadow = copy(tunedShadow)
                local higher, higherState, short = tuneShadow()
                if not higher then
                    shortAt = short
                    break
                end
                tuned, tunedState, tunedShadow, tunedAt = higher, higherState, shadow, target
            end
            shadow, perCraft = {}, 0
            if target ~= cutAt then retarget(cutAt) end
        end
        -- The priced route wins where it reaches further, or as far for less.
        local further = tuned and tunedAt > target
        if tuned and (further or burden(tuned) < burden(result) - EPS) then
            if further then
                retarget(tunedAt)
                if tunedAt == asked.target then
                    ceiling, gap = asked.ceiling, asked.gap
                else
                    ceiling = { skill = tunedAt, reason = "materials", text = "What you carry runs out at " .. tunedAt .. "." }
                end
            end
            result, state, shadow, perCraft = tuned, tunedState, tunedShadow, craftCost
            -- What ran out before the target no longer does; what stopped
            -- the climb runs out at it.
            for item, at in pairs(ranOut) do
                if at < target then ranOut[item] = nil end
            end
            if further and shortAt and tunedAt < asked.target then ranOut[shortAt] = tunedAt end
        else
            for entry, at in pairs(stops) do entry.stopAt = at end
        end
    end

    -- Only what is carried, stopped where the materials run out: the last
    -- steps each make all their materials can, so their order changes only
    -- how far those crafts go. Every point gained lowers the chance of the
    -- crafts after it, so the surest crafts do best last, where that costs
    -- them least (a yellow belt after two green grinding stones reaches
    -- further than before them). Each order of the last steps (up to four,
    -- running on from one another) is walked at the expected skill-ups, and
    -- one reaching further than the solve's is kept, each step given the
    -- skill levels its crafts are expected to cover.
    if carriedOnly and ceiling.reason == "materials" and #result.runs > 1 then
        local list = result.runs
        local _, cuts = picksOf(stretches)
        -- Each run's crafts at the low end, capped in order at what the bags
        -- make, and what the bags hold after them all.
        local sized = {}
        for index, run in ipairs(list) do
            local expected, variance = S:Span(run.entry.skills, run.from, run.to)
            sized[index] = { entry = run.entry, from = run.from, to = run.to, expected = expected or 0,
                count = (S:Range(expected or 0, variance, z, run.to - run.from)) }
        end
        local left
        for _ = 1, #sized + 1 do
            local batches = batchesOf(sized)
            left = ledger(batches, true).carried
            local cap
            for _, batch in ipairs(batches) do
                if not batch.goal and not cap then
                    for _, short in pairs(batch.short) do
                        if short > 1e-9 then cap = { batch = batch } end
                    end
                end
            end
            if cap then cap = { run = cap.batch.run, count = possibleCrafts(batches, cap.batch) } end
            if not cap or cap.count >= cap.run.count then break end
            cap.run.count = math.max(cap.count, 0)
        end
        -- The tail: runs that leave the bags without another craft's worth,
        -- one after another with no trainer cap, chosen stretch or free
        -- progress between them.
        local function spent(index)
            local uses, run = usesOf(list[index].entry), sized[index]
            if run.count < 1 or not next(uses) then return false end
            for item, units in pairs(uses) do
                if (left[item] or 0) >= units - 1e-9 then return false end
            end
            return true
        end
        local first = #list + 1
        while first > 1 and #list - first < 3 and spent(first - 1) do
            local run, after = list[first - 1], list[first]
            if after and (run.to ~= after.from or boundarySet[after.from] or cuts[after.from]) then break end
            first = first - 1
        end
        if #list - first >= 1 then
            local startSkill, endSkill = list[first].from, list[#list].to
            local tail = {}
            for index = first, #list do table.insert(tail, { entry = list[index].entry, crafts = sized[index].count }) end
            -- How far an order goes: the chance of each skill, craft by craft,
            -- and the skill expected after each step (nil when a step gives
            -- no skill where it is expected to start). Exact, where adding
            -- up chances at a rounded skill ties orders that are not equal.
            local function walk(order)
                local odds, ends = { [startSkill] = 1 }, {}
                local function expected()
                    local sum = 0
                    for skill, share in pairs(odds) do sum = sum + skill * share end
                    return sum
                end
                for index, step in ipairs(order) do
                    if S:Chance(step.entry.skills, math.floor(expected() + 1e-9)) <= 0 then return nil end
                    for _ = 1, step.crafts do
                        local after = {}
                        for skill, share in pairs(odds) do
                            local chance = S:Chance(step.entry.skills, skill)
                            after[skill] = (after[skill] or 0) + share * (1 - chance)
                            after[skill + 1] = (after[skill + 1] or 0) + share * chance
                        end
                        odds = after
                    end
                    ends[index] = expected()
                end
                return ends[#ends], ends
            end
            local function reach(order) return (walk(order)) end
            local best, bestReach = nil, reach(tail) or -INF
            -- The steps' own tables: `copy` would copy the recipes too.
            local function listOf(order)
                local out = {}
                for index, step in ipairs(order) do out[index] = step end
                return out
            end
            local function permute(order, from)
                if from > #order then
                    local at = reach(order)
                    if at and at > bestReach + 1e-6 then best, bestReach = listOf(order), at end
                    return
                end
                for index = from, #order do
                    order[from], order[index] = order[index], order[from]
                    permute(order, from + 1)
                    order[from], order[index] = order[index], order[from]
                end
            end
            permute(listOf(tail), 1)
            if best then
                local reordered, from = {}, startSkill
                local _, ends = walk(best)
                for index, step in ipairs(best) do
                    local to = index == #best and endSkill or math.max(from + 1, math.floor(ends[index] + 0.5))
                    to = math.min(to, endSkill - (#best - index))
                    if not S:Span(step.entry.skills, from, to) then reordered = nil; break end
                    table.insert(reordered, { entry = step.entry, from = from, to = to })
                    from = to
                end
                if reordered then
                    for index = #list, first, -1 do table.remove(list, index) end
                    for _, run in ipairs(reordered) do table.insert(list, run) end
                    local value, prev = 0, nil
                    for _, run in ipairs(list) do
                        if run.entry ~= prev then value = value + result.learn(run.entry) end
                        for skill = run.from, run.to - 1 do
                            value = value + (result.net[run.entry] or 0) / S:Chance(run.entry.skills, skill)
                        end
                        prev = run.entry
                    end
                    result.value = value
                end
            end
        end
    end

    -- Suggestions: recipes the player has not said yes to (a pattern with a
    -- known price while the route keeps to the trainer, BoP, or BoE with no
    -- price), each priced by solving again with it free and taking off what
    -- it costs to get. Recipes that are off are never candidates.
    local threshold = options.suggestThreshold or self.suggestThreshold
    local function suggestFor(base, value, chosen, jumps)
        local list = {}
        if #base.runs == 0 then return list end
        -- Per-point cost of the base's own choice at each skill, and what
        -- learning was paid, to prune suggestions that cannot beat it anywhere.
        local chosenPer, learnAt, inRoute = {}, {}, {}
        for _, run in ipairs(base.runs) do
            inRoute[run.entry] = true
            for s = run.from, run.to - 1 do
                chosenPer[s] = base.net[run.entry] / S:Chance(run.entry.skills, s)
                learnAt[s] = base.learn(run.entry)
            end
        end
        for _, entry in ipairs(entries) do
            if entry.suggestion and not entry.off and entry.mat and inRange(entry) and not inRoute[entry] then
                local worth = false
                local unit = entry.item and (value[entry.item] or (onCost and 0 or (ctx:SellValue(entry.item)))) or 0
                local net = entry.mat - entry.made * unit
                for s = math.max(start, entry.skills[1]), math.min(target, entry.skills[4]) - 1 do
                    local p = S:Chance(entry.skills, s)
                    if p > 0 and chosenPer[s] and net / p < chosenPer[s] + (learnAt[s] or 0) - EPS then
                        worth = true
                        break
                    end
                end
                if worth then
                    local trial = solve({ banned = banned, extra = { [entry.spell] = true }, value = value,
                        chosen = chosen, jumps = jumps })
                    local price = entry.offer and entry.offer.gold or 0
                    local saving = trial and (base.value - trial.value - price) or 0
                    -- The skill levels the trial route makes it over: where the pattern
                    -- would take over, and where it would hand back.
                    local used, fromSkill, toSkill = false, nil, nil
                    for _, run in ipairs(trial and trial.runs or {}) do
                        if run.entry == entry then
                            used = true
                            fromSkill = math.min(fromSkill or run.from, run.from)
                            toSkill = math.max(toSkill or run.to, run.to)
                        end
                    end
                    if used and saving >= threshold then
                        local offer = entry.offer
                        table.insert(list, {
                            spell = entry.spell, bind = entry.recipe.bind == "boe" and "boe" or "bop",
                            source = entry.suggestion, item = entry.recipe.teach,
                            saving = math.floor(saving + 0.5),
                            worthUnder = (entry.suggestion == "boe" and not offer) and math.floor(saving + 0.5) or nil,
                            cost = offer and offer.gold or nil,
                            npc = offer and offer.npc or nil,
                            fromSkill = fromSkill or entry.skills[1], toSkill = toSkill,
                        })
                    end
                end
            end
        end
        table.sort(list, function(a, b)
            if a.saving ~= b.saving then return a.saving > b.saving end
            return a.spell < b.spell
        end)
        return list
    end
    local suggestions = suggestFor(result, state.value, stretches, state.jumps)

    -- The recipes a step could be made with instead: every recipe the route
    -- may use, and every pattern it could suggest, that gives skill at each
    -- of the step's skill levels. What the player turned off is never one.
    local function givesAll(entry, from, to)
        for s = from, to - 1 do
            if S:Chance(entry.skills, s) <= 0 then return false end
        end
        return true
    end
    local function offeredOver(from, to)
        local list = {}
        for _, entry in ipairs(entries) do
            if not entry.off and entry.mat and (entry.usable or entry.suggestion) and givesAll(entry, from, to) then
                table.insert(list, entry)
            end
        end
        return list
    end

    -- The choices at one step, for Planner:WaysAround, solved only when
    -- asked. They come from the step alone: its skill levels S and the player's
    -- other stretches, neither of which depends on what the step itself
    -- holds, so the list is the same whichever of them is taken. The
    -- baseline is the route with the step's own stretch carved out (this
    -- route when it has none); its recipes over S are the "planner" choice.
    -- Every other recipe offered over S is solved with it chosen for
    -- exactly S, and priced against the baseline.
    local function waysAround(runIndex)
        local run = result.runs[runIndex]
        if not run then return {} end
        local from, to = run.from, run.to
        local others, touched = carve(stretches, from, to)
        local base = result
        if touched > 0 then base = solvePasses({ banned = banned, extra = {}, value = {}, chosen = others }) end
        if not base then return {} end
        local points = to - from
        -- The planner's choice: the baseline's recipes over S, in order.
        local planner = { kind = "planner", fromSkill = from, toSkill = to, spells = {}, extra = 0, perPoint = 0, crafts = 0 }
        for _, other in ipairs(base.runs) do
            local a, b = math.max(other.from, from), math.min(other.to, to)
            if a < b then
                local expected = S:Span(other.entry.skills, a, b) or 0
                if planner.spells[#planner.spells] ~= other.entry.spell then
                    table.insert(planner.spells, other.entry.spell)
                end
                planner.crafts = planner.crafts + expected
                planner.perPoint = planner.perPoint + expected * (base.net[other.entry] or 0) / points
            end
        end
        if #planner.spells == 0 then return {} end
        planner.spell = planner.spells[1]
        local first = bySpell[planner.spell]
        planner.source = first.info and first.info.kind or nil
        planner.needsPattern = first.info and first.info.needsPattern or nil
        planner.color = S:Color(first.skills, from)
        local only = #planner.spells == 1 and planner.spell or nil
        local ways = { planner }
        for _, entry in ipairs(offeredOver(from, to)) do
            if entry.spell ~= only then
                local pattern = not entry.usable
                local chosen = { { fromSkill = from, toSkill = to, spell = entry.spell } }
                for index, stretch in ipairs(others) do chosen[index + 1] = stretch end
                -- Solved afresh in passes, as a replan with it chosen would
                -- be: its intermediates, and the skill they give, are its own.
                local trial = solvePasses({ banned = banned, extra = pattern and { [entry.spell] = true } or {},
                    value = {}, chosen = chosen })
                if trial then
                    local offer = pattern and entry.offer or nil
                    local crafts = S:Span(entry.skills, from, to) or 0
                    local way = { kind = pattern and "pattern" or "other", fromSkill = from, toSkill = to,
                        spell = entry.spell, spells = { entry.spell },
                        extra = math.floor(trial.value + (offer and offer.gold or 0) - base.value + 0.5),
                        crafts = crafts, perPoint = crafts * (trial.net[entry] or 0) / points,
                        color = S:Color(entry.skills, from),
                        source = pattern and entry.suggestion or (entry.info and entry.info.kind),
                        needsPattern = entry.info and entry.info.needsPattern or nil }
                    if pattern then
                        way.bind = entry.recipe.bind == "boe" and "boe" or "bop"
                        way.item = entry.recipe.teach
                        way.cost = offer and offer.gold or nil
                        way.npc = offer and offer.npc or nil
                    end
                    table.insert(ways, way)
                end
            end
        end
        local order = { planner = 1, other = 2, pattern = 3 }
        table.sort(ways, function(a, b)
            if a.extra ~= b.extra then return a.extra < b.extra end
            if a.spell ~= b.spell then return a.spell < b.spell end
            return order[a.kind] < order[b.kind]
        end)
        -- The one the route takes now: the step's own stretch, else the
        -- planner's. A stretch the route could not honour here is none.
        local picked = picksOf(stretches)[from]
        for _, way in ipairs(ways) do
            if picked then
                if #way.spells == 1 and way.spells[1] == picked then way.using = true end
            elseif way.kind == "planner" then
                way.using = true
            end
        end
        return ways
    end

    -- The route's numbers ---------------------------------------------------

    local shownValue = revalue(result.runs, true)
    local runs, totalVariance = {}, 0
    local picks = picksOf(stretches)
    for _, run in ipairs(result.runs) do
        local expected, variance = S:Span(run.entry.skills, run.from, run.to)
        totalVariance = totalVariance + variance
        -- How many other recipes the step could be made with: a count for
        -- the alts button, without solving (Planner:WaysAround solves).
        local others = 0
        for _, entry in ipairs(offeredOver(run.from, run.to)) do
            if entry ~= run.entry then others = others + 1 end
        end
        table.insert(runs, { entry = run.entry, spell = run.entry.spell, item = run.entry.item,
            fromSkill = run.from, toSkill = run.to, expected = expected, variance = variance,
            estimated = run.entry.estimated, chosen = picks[run.from] == run.entry.spell or nil, others = others,
            needsPattern = run.entry.info and run.entry.info.needsPattern or nil })
    end
    local pooled = math.sqrt(totalVariance)
    for _, run in ipairs(runs) do
        local points = run.toSkill - run.fromSkill
        run.low, run.high = S:Range(run.expected, run.variance, z, points)
        -- The route's spread shared out by each run's variance, so the counts
        -- add up to the expected total plus z deviations of the whole route.
        local extra = pooled > 0 and z * run.variance / pooled or 0
        run.count = math.max(S:Count(run.expected + extra, 0, 0), points)
        -- Only what is carried, nothing is bought on a margin and the plan is
        -- made again after every craft: a step's count is what its Make
        -- button orders, the low end, so the parts made for it, the bags'
        -- sums and the button agree.
        if carriedOnly then run.count = run.low end
        -- The net's two halves: what one craft's materials cost, and what its
        -- output is worth (sold, or as the intermediate it replaces). These
        -- are the money shown; on cost the route was chosen without the sales.
        run.matCraft = run.entry.mat or 0
        run.sellCraft = run.entry.item and run.entry.made * (shownValue[run.entry.item] or 0) or 0
        run.perCraft = run.matCraft - run.sellCraft
        run.perPoint = run.expected > 0 and run.perCraft * run.expected / points or 0
        run.color = S:Color(run.entry.skills, run.fromSkill)
        local rivals = {}
        local row = result.V and result.V[run.fromSkill]
        for _, other in ipairs(row and row.list or {}) do
            if other ~= run.entry then
                table.insert(rivals, { spell = other.spell, perPoint = row.per[other.spell] })
            end
        end
        table.sort(rivals, function(a, b)
            if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
            return a.spell < b.spell
        end)
        for index = #rivals, 4, -1 do rivals[index] = nil end
        run.rivals = rivals
    end

    -- Only what is carried: a step never asks for more than the bags make.
    -- Where the last materials only try for a point (the cuts let them),
    -- the step's crafts are what they make, and its range stops there too.
    -- Steps are capped in order, each leaving the next what it did not use.
    if carriedOnly then
        for _ = 1, #runs do
            local list = batchesOf(runs)
            ledger(list, true)
            local cap
            for _, batch in ipairs(list) do
                if not batch.goal and not cap then
                    for _, short in pairs(batch.short) do
                        if short > 1e-9 then cap = { batch = batch } end
                    end
                end
            end
            if cap then cap = { run = cap.batch.run, count = possibleCrafts(list, cap.batch) } end
            if not cap or cap.count < 1 or cap.count >= cap.run.count then break end
            local run = cap.run
            run.count, run.low, run.high = cap.count, math.min(run.low, cap.count), math.min(run.high, cap.count)
            run.carriedCap = true
        end
        -- Where the materials end the route, the crafts are theirs, not the
        -- skill-up odds': the last step on a material makes all the bags
        -- make of it (its end skill is the guess), and the plan is made again
        -- after every craft from what is left.
        if ceiling.reason == "materials" then
            for index, run in ipairs(runs) do
                local uses, last = usesOf(run.entry), true
                for later = index + 1, #runs do
                    for item in pairs(usesOf(runs[later].entry)) do
                        if uses[item] then last = false end
                    end
                end
                if last and next(uses) then
                    local list = batchesOf(runs)
                    for _, batch in ipairs(list) do
                        if batch.run == run then
                            batch.count = 10000
                            local all = possibleCrafts(list, batch)
                            if all >= 1 then
                                run.count, run.low, run.high, run.carriedCap = all, all, all, true
                            end
                        end
                    end
                end
            end
        end
    end

    -- The last skill levels of a route are often far dearer a point than the rest:
    -- the materials run out and only a green recipe is left. That tail is
    -- said out loud, because stopping short of it or getting a suggested
    -- pattern usually beats grinding it. Measured against the median point of
    -- the route, so one cheap or dear run does not move the yardstick.
    local points = {}
    for _, run in ipairs(runs) do
        for _ = run.fromSkill + 1, run.toSkill do table.insert(points, run.perPoint) end
    end
    table.sort(points)
    local median = points[math.floor((#points + 1) / 2)]
    local tail
    for index = #runs, 1, -1 do
        local run = runs[index]
        if not (median and median > 0 and run.perPoint > self.expensiveFactor * median
            and run.perPoint >= self.expensiveMinimum) then break end
        tail = index
    end
    if tail then
        local first, last = runs[tail], runs[#runs]
        local net, count = 0, 0
        for index = tail, #runs do
            net = net + runs[index].perPoint * (runs[index].toSkill - runs[index].fromSkill)
            count = count + runs[index].toSkill - runs[index].fromSkill
        end
        warn("expensive", ("Skill %d-%d costs about %s a point, %d times the median point of this route. Stopping at %d,"
            .. " or a suggested pattern, may be cheaper."):format(first.fromSkill, last.toSkill,
            P:FormatMoney(math.floor(net / count + 0.5)), math.floor(net / count / median), first.fromSkill),
            { skill = first.fromSkill, spell = first.spell })
    end

    -- The route's batches, and the skill each one's intermediates are made at
    -- (`makeAt`) with what they give (`makeGain`, and by spell `makeGains`):
    -- the make jumps the route was solved with, so the skill levels agree.
    local batches = batchesOf(runs)
    local made = state.made or {}
    local endsAt = endsAtOf(made)
    local expectedLedger = ledger(batches, false)
    for _, batch in ipairs(batches) do
        batch.makeAt = batch.goal and batch.skill or (endsAt[batch.skill] or batch.skill)
        local finish = made[batch.makeAt]
        batch.makeGain, batch.makeGains = 0, {}
        if finish and not batch.goal and #batch.makeOrder > 0 then
            batch.makeGain = finish - batch.makeAt
            -- Each recipe's share, rounded as it adds up; the last one giving
            -- skill takes what is left of the jump, so the shares add up to
            -- the skill levels the route skipped (the passes may stop a little
            -- short of agreeing).
            local _, gains = makeGains(batch, batch.makeAt)
            local last
            for _, spell in ipairs(batch.makeOrder) do
                if (gains[spell] or 0) > 0 then last = spell end
            end
            -- A recipe after the last one giving skill gets none, never less.
            local sum, shown = 0, 0
            for _, spell in ipairs(batch.makeOrder) do
                sum = sum + (gains[spell] or 0)
                local upTo = spell == last and batch.makeGain or math.min(math.floor(sum + 0.5), batch.makeGain)
                upTo = math.max(upTo, shown)
                batch.makeGains[spell] = upTo - shown
                shown = upTo
            end
        end
    end

    -- Learning and training.
    local events, learned = {}, {}
    local training, learning, costUnknown = 0, 0, false
    for _, train in ipairs(trainings) do
        table.insert(events, train)
        training = training + train.cost
        if train.costUnknown then costUnknown = true end
    end
    -- A recipe learned the first time the route makes it, for a run, a goal
    -- or an intermediate.
    local function learnEvent(entry, skill)
        local info = entry.info
        if not info or info.kind == "known" or info.kind == "start" or learned[entry.spell] then return nil end
        learned[entry.spell] = true
        local event = { kind = "learn", skill = skill, spell = entry.spell, source = info.kind,
            cost = info.gold or 0, costUnknown = info.costUnknown, npc = info.npc,
            item = info.item, accepted = info.accepted, needsPattern = info.needsPattern }
        table.insert(events, event)
        learning = learning + (info.gold or 0)
        if info.costUnknown then
            costUnknown = true
            warn("costUnknown", (info.needsPattern and "Pattern for recipe " or "Learning recipe ") .. entry.spell
                .. ": cost unknown.", { spell = entry.spell })
        end
        return event
    end
    for _, batch in ipairs(batches) do
        local entry = batch.entry
        -- The intermediates are made first, so learned first.
        batch.makeLearns = {}
        for _, spell in ipairs(batch.makeOrder) do
            local event = bySpell[spell] and learnEvent(bySpell[spell], batch.makeAt)
            if event then table.insert(batch.makeLearns, event) end
        end
        local event = learnEvent(entry, batch.skill)
        if event then
            batch.learn = event
            if batch.run then batch.run.learn = event end
        elseif not entry.info and not learned[entry.spell] then
            -- A goal on a pattern the player has not said yes to.
            learned[entry.spell] = true
            warn("pattern", "Recipe " .. entry.spell .. " is a goal but its pattern is not in hand.", { spell = entry.spell })
        end
        if batch.goal then
            table.insert(events, { kind = "goal", skill = batch.skill, spell = entry.spell, count = batch.count,
                gain = batch.goal.gain, when = batch.goal.goal.when, atEnd = batch.goal.atEnd or nil })
        end
    end
    local eventOrder = { train = 1, learn = 2, make = 3, goal = 4 }
    local function sortEvents()
        table.sort(events, function(a, b)
            if a.skill ~= b.skill then return a.skill < b.skill end
            if eventOrder[a.kind] ~= eventOrder[b.kind] then return eventOrder[a.kind] < eventOrder[b.kind] end
            return (a.spell or 0) < (b.spell or 0)
        end)
    end
    sortEvents()

    -- Money, from the expected ledger. What rests on estimated prices is
    -- kept per item, to say which estimates matter most.
    local materials, estimatedCost, estimatedTotal = 0, {}, 0
    for item, quantity in pairs(expectedLedger.bought) do
        local each, _, _, estimated = ctx:BuyCost(item)
        materials = materials + quantity * (each or 0)
        if estimated then
            estimatedCost[item] = quantity * (each or 0)
            estimatedTotal = estimatedTotal + estimatedCost[item]
        end
    end
    for item, quantity in pairs(expectedLedger.fromBags) do materials = materials + quantity * ctx:BagValue(item) end
    -- What the stock sells for, at its best sale and all to a vendor.
    local recovered, vendorRecovered = 0, 0
    for item, quantity in pairs(expectedLedger.stock) do
        if quantity > 1e-9 then
            recovered = recovered + ctx:SellTotal(item, quantity)
            vendorRecovered = vendorRecovered + ctx:VendorTotal(item, quantity)
        end
    end
    local spent = materials + training + learning
    local net = spent - recovered
    local spreadVariance = 0
    for _, run in ipairs(runs) do spreadVariance = spreadVariance + run.variance * run.perCraft * run.perCraft end
    local spread = z * math.sqrt(spreadVariance)

    -- Which stretch costs what: one band per trainer tier.
    local bands = {}
    for index, tier in ipairs(tiers.tiers) do
        local lower = index > 1 and tiers.tiers[index - 1].cap or 0
        local from, to = math.max(lower, start), math.min(tier.cap, target)
        if from < to then
            local band = { tier = tier.name, fromSkill = from, toSkill = to, net = 0 }
            for _, run in ipairs(runs) do
                if run.fromSkill >= lower and run.fromSkill < tier.cap then band.net = band.net + run.expected * run.perCraft end
            end
            for _, event in ipairs(events) do
                local inBand = (event.skill >= lower and event.skill < tier.cap) or (event.kind == "train" and event.cap == tier.cap)
                if inBand and event.kind ~= "goal" and event.kind ~= "make" then band.net = band.net + (event.cost or 0) end
            end
            band.net = math.floor(band.net + 0.5)
            table.insert(bands, band)
        end
    end

    -- The shopping list and each step's materials, at the confidence counts.
    local sizedLedger = ledger(batches, true)
    local neededSource = {}
    local function sourceWord(item, batch)
        if batch and batch.fromRoute[item] then return "craft" end
        local _, source = ctx:BuyCost(item)
        -- A plan's material sources have no "estimate": it is still bought
        -- at the auction house.
        if source == "estimate" then return "ah" end
        -- Nor "carried": what is in the bags is the player's own.
        if source == "carried" then return "gather" end
        return source or "gather"
    end
    local function needsFor(batch, crafts)
        local list = {}
        for _, reagent in ipairs(batch.entry.recipe.reagents or {}) do
            table.insert(list, { reagent[1], math.max(math.ceil(crafts * (reagent[2] or 1) - 1e-9), 1), sourceWord(reagent[1], batch) })
        end
        return list
    end
    -- Each batch's intermediates, in the order they are made (the parts
    -- first), at the step counts; each a "make" event, and summed by item
    -- for the Materials tab (`makes`). With only what is carried a step's
    -- count is what its Make button orders, so its parts are made for
    -- exactly that.
    local runIndexOf, makesByItem, makes = {}, {}, {}
    for index, run in ipairs(runs) do runIndexOf[run] = index end
    for _, batch in ipairs(batches) do
        batch.needs = needsFor(batch, batch.count)
        local intermediates = {}
        local at = batch.makeAt
        for _, spell in ipairs(batch.makeOrder) do
            local recipe = data.recipes[spell]
            local list = {}
            for _, reagent in ipairs(recipe.reagents or {}) do
                table.insert(list, { reagent[1], math.max(math.ceil(batch.intermediates[spell] * (reagent[2] or 1) - 1e-9), 1), sourceWord(reagent[1]) })
            end
            local crafts = math.ceil(batch.intermediates[spell] - 1e-9)
            local count = math.max(math.floor(crafts * P.AverageMade(recipe) + 0.5), 1)
            local parts, _, estimated = ctx:ReagentCost(recipe)
            local gain = batch.makeGains[spell] or 0
            local make = { kind = "make", skill = at, spell = spell, item = recipe.makes, crafts = crafts, count = count,
                needs = list, helper = recipe.helper, gain = gain > 0 and gain or nil, forSpell = batch.entry.spell,
                forRun = batch.run and runIndexOf[batch.run] or nil, forGoal = batch.goal and true or nil,
                cost = parts and math.floor(crafts * parts + 0.5) or nil, estimated = estimated or nil }
            at = at + gain
            table.insert(intermediates, make)
            table.insert(events, make)
            if recipe.makes then
                local row = makesByItem[recipe.makes]
                if not row then
                    row = { itemID = recipe.makes, spell = spell, count = 0, crafts = 0, cost = 0, gain = 0,
                        firstSkill = make.skill, each = (ctx:BuyCost(recipe.makes)) }
                    makesByItem[recipe.makes] = row
                    table.insert(makes, row)
                end
                row.count, row.crafts = row.count + count, row.crafts + crafts
                row.cost, row.gain = row.cost + (make.cost or 0), row.gain + gain
                row.estimated = row.estimated or make.estimated
            end
        end
        batch.intermediateList = intermediates
        if batch.run then batch.run.needs, batch.run.intermediates = batch.needs, intermediates end
        for _, need in ipairs(batch.needs) do neededSource[need[1]] = need[3] end
    end
    sortEvents()
    local shopping = {}
    for _, item in ipairs(sortedKeys(sizedLedger.bought)) do
        local buy = sizedLedger.bought[item]
        local fromBags = sizedLedger.fromBags[item] or 0
        local count = math.ceil(buy + fromBags - 1e-9)
        if count > 0 then
            local cost, source, detail, estimated = ctx:BuyCost(item)
            table.insert(shopping, {
                itemID = item, count = count, have = options.useBags and (bags(item) or 0) or 0,
                buy = math.ceil(buy - 1e-9), source = source or "gather", each = cost, npc = detail and detail.npc,
                estimated = estimated or nil,
                -- The route also makes it (what is carried is used first):
                -- not shopping, though it is counted here.
                made = sizedLedger.made[item] or nil,
                firstSkill = sizedLedger.firstSkill[item],
                lastSkill = (not sizedLedger.noEscape[item]) and sizedLedger.lastSkill[item] or nil,
            })
        end
    end
    local sourceOrder = { carried = 0, vendor = 1, ah = 2, estimate = 3, gather = 4, craft = 5 }
    table.sort(shopping, function(a, b)
        local left, right = sourceOrder[a.source] or 9, sourceOrder[b.source] or 9
        if left ~= right then return left < right end
        if (a.firstSkill or 0) ~= (b.firstSkill or 0) then return (a.firstSkill or 0) < (b.firstSkill or 0) end
        return a.itemID < b.itemID
    end)

    -- Only what is carried: a shortfall the cuts left (a goal's, or the
    -- rounding of what the route makes) is told, as the route cannot buy it.
    local ranOutList = {}
    if carriedOnly then
        for _, row in ipairs(shopping) do
            if row.source == "carried" and (row.buy or 0) > 0 then
                local name = input.nameOf and input.nameOf("item", row.itemID) or ("item " .. row.itemID)
                warn("carriedShort", "You may need " .. row.buy .. " more " .. ascii(name) .. " than you carry.",
                    { item = row.itemID })
            end
        end
        for item, at in pairs(ranOut) do
            if at <= target then table.insert(ranOutList, { itemID = item, skill = at }) end
        end
        table.sort(ranOutList, function(a, b)
            if a.skill ~= b.skill then return a.skill < b.skill end
            return a.itemID < b.itemID
        end)
        -- The target's tooltip names what ran out where the route stops.
        local last = ranOutList[#ranOutList]
        if ceiling.reason == "materials" and last and last.skill == target then
            local name = input.nameOf and input.nameOf("item", last.itemID) or ("item " .. last.itemID)
            ceiling.text = ascii(name) .. " runs out at " .. target .. "."
        end
    end

    -- What is left to sell, and what it is worth.
    local selling = {}
    for _, item in ipairs(sortedKeys(expectedLedger.stock)) do
        local quantity = expectedLedger.stock[item]
        if quantity > 1e-9 then
            local each, source = ctx:SellValue(item)
            local lastSkill
            for _, run in ipairs(runs) do
                if run.item == item then lastSkill = run.toSkill end
            end
            table.insert(selling, { itemID = item, count = quantity, each = each, source = source,
                total = math.floor(ctx:SellTotal(item, quantity) + 0.5), skill = lastSkill or target })
        end
    end

    -- Every item the plan touches, for the Prices tab.
    local touched = {}
    for _, batch in ipairs(batches) do
        if batch.entry.item then touched[batch.entry.item] = true end
        for _, reagent in ipairs(batch.entry.recipe.reagents or {}) do touched[reagent[1]] = true end
        for spell in pairs(batch.intermediates) do
            for _, reagent in ipairs(data.recipes[spell].reagents or {}) do touched[reagent[1]] = true end
        end
        if batch.learn and batch.learn.item then touched[batch.learn.item] = true end
    end
    for _, suggestion in ipairs(suggestions) do
        if suggestion.item then touched[suggestion.item] = true end
    end

    -- The items the route touches that Auctionator priced, for a side the
    -- player uses the auction house for.
    local auctionator = 0
    for item in pairs(touched) do
        local _, buySource = ctx:Fact(item, "auctionBuy")
        local _, sellSource = ctx:Fact(item, "auctionSell")
        if (ctx.buyAH and buySource == "auctionator") or (ctx.sellAH and sellSource == "auctionator") then
            auctionator = auctionator + 1
        end
    end

    local missing = {}
    for _, item in ipairs(sortedKeys(unobtainable)) do
        table.insert(missing, { itemID = item, spells = unobtainable[item] })
    end
    if #missing > 0 then
        warn("unobtainable", #missing .. " material(s) have no allowed source; recipes needing them are skipped.")
    end
    if not tiers.verified then
        warn("tiersUnverified", "Trainer caps and level gates are Classic's and unverified on Forever.")
    end

    -- The patterns the route needs that the character lacks, and how many
    -- of them have no known price.
    local patterns, patternsUnknown = 0, 0
    for _, event in ipairs(events) do
        if event.kind == "learn" and event.needsPattern then
            patterns = patterns + 1
            if event.costUnknown then patternsUnknown = patternsUnknown + 1 end
        end
    end
    local cleanRuns = {}
    for _, run in ipairs(runs) do
        run.entry = nil
        table.insert(cleanRuns, run)
    end

    -- The estimated prices the route leans on, the dearest first.
    local estimatedItems = sortedKeys(estimatedCost)
    table.sort(estimatedItems, function(a, b)
        if math.abs(estimatedCost[a] - estimatedCost[b]) > 1e-9 then return estimatedCost[a] > estimatedCost[b] end
        return a < b
    end)

    -- The route:
    --   runs         { { spell, item, fromSkill, toSkill, expected, variance, low, high, count,
    --                    perCraft, perPoint, matCraft, sellCraft (a craft's materials and output
    --                    value: perCraft = matCraft - sellCraft),
    --                    color, learn = event|nil, rivals = { { spell, perPoint } },
    --                    chosen = true when it starts inside a stretch the player chose for it,
    --                    others = how many other recipes give skill at every one of its skill levels,
    --                    needs = { { itemID, count, source } }, intermediates = { make events },
    --                    needsPattern = { bind, source, cost, npc, teach } when its recipe needs a
    --                    pattern the character lacks (see learnInfo) } }
    --   events       { train = { skill, tier, cap, level, cost, costUnknown, npc },
    --                  learn = { skill, spell, source, cost, costUnknown, npc, item, accepted, needsPattern },
    --                  goal  = { skill, spell, count, gain, when, atEnd },
    --                  make  = { skill (where it is made), spell, item, crafts, count (items), gain (points
    --                            its crafts are expected to give, nil when none), forSpell, forRun (the
    --                            run it is made for; forGoal for a goal), cost (its parts), estimated,
    --                            needs } } by skill, each with `kind`
    --   makes        { { itemID, spell, count, crafts, cost, each, gain, estimated, firstSkill } }:
    --                every intermediate made on the way, summed by item
    --   summary      { spent, materials, training, learning, recovered, net, low, high,
    --                  vendorRecovered, vendorNet (the same, every sale at a vendor),
    --                  costUnknown, bands = { { tier, fromSkill, toSkill, net } },
    --                  estimated = n items priced by estimate, estimatedShare = 0..1 of spent,
    --                  auctionator = n items the route touches that Auctionator priced,
    --                  patterns = n patterns the character lacks that the route learns,
    --                  patternsUnknown = how many of those have no known price }
    --   auctionator  true when Auctionator is installed and the plan uses it
    --   shopping     { { itemID, count, have, buy, source, each, npc, firstSkill, lastSkill, estimated,
    --                made = true when the route also makes it } }
    --   made         { [itemID] = true }: what the route makes on the way (its intermediates)
    --   estimated    { itemID } whose price is an estimate, by the share of the cost they carry
    --   status       { kind = "ready"|"short"|"estimated"|"blocked"|"done", text }: see Planner:Status
    --   wanted       the skill asked for (the target given, or the default), before any ceiling
    --   selling      { { itemID, count, each, source, total, skill } }
    --   chosen       { { fromSkill, toSkill, spell } }: the player's chosen stretches this route
    --                kept, clipped to its skill levels
    --   waysAround, ways  Planner:WaysAround's solver and cache (functions: not for saving)
    --   suggestions  { { spell, bind, source = "vendor"|"boe"|"bop", item, saving (net of
    --                cost), worthUnder (an unpriced BoE), cost, npc (a known seller),
    --                fromSkill, toSkill } }: fromSkill and
    --                toSkill are the skill levels the route would make it over, once in hand
    --   ceiling      { skill, reason = "target"|"tiers"|"level"|"recipes"|"materials", text, level, tier };
    --                "materials": planning with only what is carried, it runs out there
    --   materials    the materials option: "buy", or "carried" (only what is carried, and vendors)
    --   ranOut       with "carried": { { itemID, skill } }, the bag-only materials that run out
    --                on the way and the skill each does, the first first
    --   missingWhy   why an unobtainable material has no source: "carried", "vendor" or
    --                "auction" (Planner.missingWords)
    --   gap          with the "recipes" ceiling: { skill, to, options }, the ways past
    --                the skill no usable recipe gives skill at (see gapAt above)
    --   warnings     { { code, text, spell?, tier? } }
    --   unobtainable { { itemID, spells } }
    --   items        every item ID the plan touches
    --   trainings    the train events alone; value  the DP's own figure (for comparisons)
    --   batches      runs and goals in making order, with their recipe entries:
    --                Outline and Sections read them; not for saving
    local route = {
        profession = profession, startSkill = start, skill = skill, target = target, wanted = wanted,
        confidence = options.confidence, z = z, signature = self:Signature(input),
        runs = cleanRuns, events = events, batches = batches, chosen = stretches,
        summary = {
            spent = math.floor(spent + 0.5), materials = math.floor(materials + 0.5),
            training = math.floor(training + 0.5), learning = math.floor(learning + 0.5),
            recovered = math.floor(recovered + 0.5), net = math.floor(net + 0.5),
            vendorRecovered = math.floor(vendorRecovered + 0.5),
            vendorNet = math.floor(spent - vendorRecovered + 0.5),
            low = math.floor(net - spread + 0.5), high = math.floor(net + spread + 0.5),
            costUnknown = costUnknown or nil, bands = bands,
            estimated = #estimatedItems,
            estimatedShare = spent > 0 and math.min(estimatedTotal / spent, 1) or 0,
            auctionator = auctionator,
            patterns = patterns, patternsUnknown = patternsUnknown,
        },
        auctionator = ctx:UsesAuctionator() or nil,
        shopping = shopping, made = sizedLedger.made, makes = makes, selling = selling, suggestions = suggestions, ceiling = ceiling, gap = gap,
        materials = options.materials, ranOut = ranOutList,
        missingWhy = carriedOnly and "carried" or (not ctx.buyAH and "vendor") or "auction",
        warnings = warnings, unobtainable = missing, items = sortedKeys(touched),
        estimated = estimatedItems, trainings = trainings, value = result.value,
        -- Planner:WaysAround's solver and its cache: not for saving.
        waysAround = waysAround, ways = {},
        -- The recipes the route may make an intermediate with, for a price
        -- context that agrees with it (the Materials tab's): not for saving.
        canCraft = ctx.canCraft,
    }
    route.status = self:Status(route, input.nameOf, data)
    return route
end

-- The one sentence at the top of the planner window, and its kind:
--
--   done       the skill is already at the target: "Leatherworking is already at 150."
--   blocked    the recipes stop short of what was asked for want of a price, or
--              no route at all: "Cannot plan past 83: Thick Leather and 3 more
--              no vendor sells them. ..." (a route that simply
--              runs out of recipes is ready or estimated; its ceiling says why)
--   short      a route that stops below the skill asked for because no recipe
--              the player can use gives skill there: "Leatherworking 83 to 170
--              of 225, about 12g: no recipe you can use gives skill at 170. ..."
--              (the ways past it are route.gap, a note at the end of the table)
--   estimated  a route whose cost rests partly on estimated prices, naming the
--              ones that matter most
--   ready      "Leatherworking 83 to 150: about 12g 40s."
--
-- Planning with only what is carried, a route that stops where the
-- materials do (a material the player has none of, or the "materials"
-- ceiling) is what was asked for: ready, the plain sentence; the warnings
-- and the note at the end of the table say the rest. Only an empty route
-- is blocked.
--
-- `nameOf(kind, id)` names items ("item <id>" without it); `data` is the
-- profession's recipe data, to tell which missing materials hold the route
-- up. ASCII only.
function Planner:Status(route, nameOf, data)
    local P = Prices()
    local profession = route.profession or "Profession"
    local function itemName(id)
        local name = nameOf and nameOf("item", id)
        return ascii(name or ("item " .. tostring(id)))
    end
    local function listed(items, limit)
        local names = {}
        for index = 1, math.min(#items, limit) do table.insert(names, itemName(items[index])) end
        if #items > limit then table.insert(names, "...") end
        return table.concat(names, ", ")
    end
    local stopped = route.ceiling and route.ceiling.reason == "recipes"
    local carried = route.materials == "carried"
    local noRoute = false
    for _, warning in ipairs(route.warnings or {}) do
        if warning.code == "noRoute" then noRoute = true end
    end
    if carried and (stopped or noRoute) and #(route.runs or {}) == 0 then
        local at = stopped and route.ceiling.skill or route.startSkill
        return { kind = "blocked", text = "Cannot plan past " .. at .. " with what you carry." }
    end
    if (stopped or noRoute) and not carried then
        local at = stopped and route.ceiling.skill or route.startSkill
        -- The materials that hold the route up: those of the recipes that
        -- would give skill where it stops (with no route at all, every one
        -- without a source).
        local holding, all = {}, {}
        for _, row in ipairs(route.unobtainable or {}) do
            table.insert(all, row.itemID)
            for _, spell in ipairs(row.spells or {}) do
                local recipe = data and data.recipes and data.recipes[spell]
                local skills = recipe and recipe.skills
                if skills and skills[1] <= at and skills[4] > at then
                    table.insert(holding, row.itemID)
                    break
                end
            end
        end
        local empty = #(route.runs or {}) == 0
        if #holding == 0 and (noRoute or empty) then holding = all end
        -- A route that runs out of recipes with nothing unpriced is not
        -- blocked: it stops where the recipes at this scope stop, which the
        -- ceiling says. Only a missing price, or no route at all, blocks.
        if #holding > 0 then
            local what = itemName(holding[1])
            if #holding == 2 then what = what .. " and 1 more"
            elseif #holding > 2 then what = what .. " and " .. (#holding - 1) .. " more" end
            return { kind = "blocked", text = "Cannot plan past " .. at .. ": no vendor sells " .. what
                .. ". Give " .. (#holding == 1 and "it" or "them") .. " a price on the Materials tab." }
        elseif stopped and empty and route.gap then
            return { kind = "blocked", text = "Cannot plan past " .. at .. ": no recipe you can use gives skill at " .. at
                .. ". The ways past it are at the end of the table." }
        elseif noRoute or (empty and route.startSkill < (route.wanted or route.target)) then
            return { kind = "blocked", text = "Cannot plan past " .. at .. ": no usable recipe gives skill there." }
        end
    end
    if route.startSkill >= route.target and #(route.runs or {}) == 0 then
        return { kind = "done", text = profession .. " is already at " .. math.max(route.skill or 0, route.target) .. "." }
    end
    local ranOut = route.ceiling and route.ceiling.reason == "materials"
    if ranOut and route.startSkill >= route.target then
        return { kind = "blocked", text = "Cannot plan past " .. route.target .. " with what you carry." }
    end
    local net = route.summary and route.summary.net or 0
    -- "About": past a gold, to the silver.
    local function rough(copper)
        if copper >= 10000 then copper = math.floor(copper / 100 + 0.5) * 100 end
        return P:FormatMoney(copper)
    end
    local cost = net < 0 and ("a profit of about " .. rough(-net)) or ("about " .. rough(net))
    local head = profession .. " " .. route.startSkill .. " to " .. route.target .. ": " .. cost
    local estimated = route.estimated or {}
    -- With only what is carried, stopping where the materials do is the
    -- answer asked for, not a warning: the plain sentence.
    if carried and (ranOut or stopped) then
        return { kind = "ready", text = head .. "." }
    end
    if stopped and route.gap then
        local wanted = route.wanted or route.target
        return { kind = "short", text = profession .. " " .. route.startSkill .. " to " .. route.target .. " of " .. wanted
            .. ", " .. cost .. ": no recipe you can use gives skill at " .. route.target
            .. ". The ways past it are at the end of the table."
            .. (#estimated > 0 and " Some prices are estimates." or "") }
    end
    if #estimated > 0 then
        -- Auctionator there but silent: it has not seen the auction house
        -- this session (the beta does not restore its prices either).
        local check = "Check prices on the Materials tab."
        if route.auctionator and (route.summary.auctionator or 0) == 0 then
            check = "Check prices on the Materials tab, or open the auction house with Auctionator to read real prices."
        end
        return { kind = "estimated", text = head .. ", but " .. #estimated .. " price" .. (#estimated == 1 and " is an estimate" or "s are estimates")
            .. " (" .. listed(estimated, 3) .. "). " .. check }
    end
    return { kind = "ready", text = head .. "." }
end

-- Replanning ---------------------------------------------------------------

-- Whether a route should be planned again. `live`:
--   skill       the live skill
--   signature  Planner:Signature of the current inputs
--   crafted    crafts made along the route since it was planned (optional)
-- Returns true and a reason ("inputs", "skill", "lucky", "unlucky") or false.
-- With a craft count, the skill is compared with where the route's low and
-- high counts put it: a skill past what even the luckiest dice reach from that
-- many crafts (the player skilled up faster than planned) or short of what
-- the unluckiest do both leave the shopping list wrong.
function Planner:NeedsReplan(route, live)
    if not route then return true, "inputs" end
    if live.signature and live.signature ~= route.signature then return true, "inputs" end
    local skill = live.skill or route.startSkill
    if skill < route.startSkill then return true, "skill" end
    if skill >= route.target then return false end
    local crafted = live.crafted
    if not crafted then return false end
    -- Skill levels reachable by `crafted` crafts at the low and at the high counts.
    local function reach(field)
        local left, at = crafted, route.startSkill
        for _, run in ipairs(route.runs) do
            if left <= 0 then break end
            at = math.max(at, run.fromSkill)
            local points = run.toSkill - run.fromSkill
            local count = math.max(run[field], 1)
            if left >= count then
                at, left = run.toSkill, left - count
            else
                at, left = at + math.floor(points * left / count), 0
            end
        end
        return at
    end
    if skill > reach("low") then return true, "lucky" end
    if skill < reach("high") then return true, "unlucky" end
    return false
end

-- Making at a loss ----------------------------------------------------------
--
-- What the route makes that it would do better not to: an intermediate that
-- costs less to buy than its parts ("paid": the plan pays for the parts), or
-- whose parts the player gathers free but would sell for more than buying it
-- costs ("free": the plan counts them as nothing, the player still gives up
-- the sale). Making stays the default, as Get it says; this is what the
-- windows warn about, so nobody takes the loss unknowingly.
--
--   { { itemID, spell, kind = "paid"|"free", count, gain, make, worth, buy,
--       buyVia = "vendor"|"ah", estimated, free = { itemID, ... },
--       loss (copper: what making `count` gives up against buying them) } }
--
-- `input` is the plan's (Planner:MakeInput). Only a real buy price counts:
-- a guessed one never says making loses.
function Planner:MakeLosses(route, input)
    local list = {}
    if not route or #(route.makes or {}) == 0 then return list end
    input = input or {}
    local P = Prices()
    local ctx = P:Context({ book = input.book or P:Book() or {}, data = input.data or {},
        options = contextOptions(self:Options(input)), canCraft = route.canCraft })
    for _, made in ipairs(route.makes) do
        local both = ctx:MakeOrBuy(made.itemID)
        local buy = both.buy
        local kind
        if buy and both.make and buy < both.make - 1e-9 then
            kind = "paid"
        elseif buy and both.free and both.worth and buy < both.worth - 1e-9 then
            kind = "free"
        end
        if kind then
            local each = kind == "paid" and both.make or both.worth
            table.insert(list, { itemID = made.itemID, spell = both.spell, kind = kind, count = made.count,
                gain = made.gain and made.gain > 0 and made.gain or nil, make = both.make, worth = both.worth,
                buy = buy, buyVia = both.buyVia, estimated = both.makeEstimated, free = both.free,
                loss = math.floor((each - buy) * made.count + 0.5) })
        end
    end
    return list
end

-- What buying `itemID` instead of making it saves over the whole route: the
-- route planned again with it bought, its net against this one's (negative
-- when making pays, as its skill can). nil when that route does not reach
-- as far, or cannot be planned. Also returns that route.
function Planner:BuyingSaves(input, route, itemID)
    if not route or not route.summary then return nil end
    local trial = {}
    for key, value in pairs(input or {}) do trial[key] = value end
    trial.options = copy(trial.options or {})
    trial.options.get = trial.options.get or {}
    trial.options.get[itemID] = "buy"
    local ok, other = pcall(self.Plan, self, trial)
    if not ok or not other or not other.summary or other.target ~= route.target then return nil end
    if (other.gap ~= nil) ~= (route.gap ~= nil) then return nil end
    return route.summary.net - other.summary.net, other
end

-- The route in order -------------------------------------------------------

-- Names for section titles: the window's (`input.nameOf`), then a bare ID.
-- ASCII only. OpenRoad fell back on its guide names (Data/Names.lua) between
-- the two; that table stays with the guides.
local function namer(input)
    local function itemName(id)
        local name = input.nameOf and input.nameOf("item", id)
        return ascii(name or ("item " .. tostring(id)))
    end
    local function recipeName(spell, item)
        local name = input.nameOf and input.nameOf("spell", spell)
        if not name and item then name = itemName(item) end
        return ascii(name or ("recipe " .. tostring(spell)))
    end
    return itemName, recipeName
end

-- One shopping-list item as a sequence element: a "buy" row, from its first
-- skill to the last skill that needs it.
local function shoppingElement(item)
    local row = { kind = "buy", skill = item.firstSkill, toSkill = item.lastSkill, item = item.itemID,
        count = item.count, cost = item.each and math.floor((item.buy or item.count) * item.each + 0.5) or nil,
        estimated = item.estimated, source = item.source, npc = item.npc }
    return { at = item.firstSkill, row = row, part = "shopping" }
end

-- The route in the order it is done, each element one display row (what
-- Planner:Outline returns). Outline and Sections are both read off this, so
-- the table and its headings cannot disagree about the order. Shopping comes
-- first, then everything else by (skill, order), then the goals kept for the
-- end:
--
--   { row = outline row, part = "shopping"|"route"|"goals", at = skill,
--     batch = the route batch it belongs to (nil for training) }
local function sequence(route, input)
    input = input or {}
    local runIndex = {}
    for index, run in ipairs(route.runs or {}) do runIndex[run] = index end
    -- A sale belongs with the last run that made the item.
    local makerOf = {}
    for _, batch in ipairs(route.batches or {}) do
        if batch.run and batch.entry.item then makerOf[batch.entry.item] = batch end
    end

    -- Everything but the shopping, in the order it is done: (skill, order).
    local rows, goalFor = {}, {}
    local function add(skill, order, row, batch)
        table.insert(rows, { at = skill, order = order, seq = #rows, row = row, part = "route", batch = batch })
    end
    for _, event in ipairs(route.events or {}) do
        if event.kind == "train" then
            local row = { kind = "train", skill = event.skill, toSkill = event.cap, tier = event.tier, cap = event.cap,
                level = event.level, cost = event.cost, costUnknown = event.costUnknown, source = "trainer", npc = event.npc,
                spent = event.cost, earned = 0 }
            add(event.skill, 1, row)
        end
    end
    for _, batch in ipairs(route.batches or {}) do
        local entry = batch.entry
        local spell, item = entry.spell, entry.item
        local run = batch.run and runIndex[batch.run] or nil
        -- A pattern is one "learn" row, however it is had: a trainer's, a
        -- vendor's, the auction house's or a drop's.
        local function learnRow(learn, skill)
            local learnt = learn.spell
            if learn.source ~= "trainer" and not learn.item then return end
            add(skill, 2, { kind = "learn", skill = skill, spell = learnt, item = learn.item, cost = learn.cost,
                costUnknown = learn.costUnknown, source = learn.source, npc = learn.npc, run = learnt == spell and run or nil,
                needsPattern = learn.needsPattern, spent = learn.cost or 0, earned = 0 }, batch)
        end
        -- What the batch's intermediates need learned, then the batch's own
        -- recipe; the intermediates are made where the route has the skill
        -- for them (batch.makeAt), just before the batch.
        for _, learn in ipairs(batch.makeLearns or {}) do learnRow(learn, learn.skill) end
        if batch.learn then learnRow(batch.learn, batch.skill) end
        for _, make in ipairs(batch.intermediateList or {}) do
            if make.item then
                local gain = make.gain or 0
                add(make.skill, 3, { kind = "make", skill = make.skill, toSkill = gain > 0 and (make.skill + gain) or nil,
                    spell = make.spell, item = make.item, count = make.count, crafts = make.crafts, gain = make.gain,
                    forSpell = make.forSpell, cost = make.cost, estimated = make.estimated, source = "craft", run = run,
                    helper = make.helper }, batch)
            end
        end
        if batch.goal then
            local gain = batch.goal.gain or 0
            local row = { kind = "goal", skill = batch.skill, toSkill = gain > 0 and (batch.skill + gain) or nil, spell = spell,
                item = item, count = batch.count, cost = entry.mat and math.floor(entry.mat * batch.count + 0.5) or nil,
                estimated = entry.estimated }
            row.spent, row.earned = row.cost, 0
            if batch.goal.atEnd then
                table.insert(goalFor, { at = batch.skill, row = row, part = "goals", batch = batch })
            else
                add(batch.skill, 4, row, batch)
            end
        else
            local runRow = batch.run
            local total = runRow.perCraft * runRow.expected
            add(batch.skill, 5, { kind = "skillup", skill = runRow.fromSkill, toSkill = runRow.toSkill, spell = spell, item = item,
                count = runRow.count, low = runRow.low, high = runRow.high, cost = math.floor(total + 0.5),
                spent = math.floor((runRow.matCraft or 0) * runRow.expected + 0.5),
                earned = math.floor((runRow.sellCraft or 0) * runRow.expected + 0.5),
                estimated = runRow.estimated, run = run }, batch)
        end
    end
    for _, sale in ipairs(route.selling or {}) do
        if sale.each and sale.each > 0 then
            add(sale.skill, 8, { kind = "sell", skill = sale.skill, item = sale.itemID, count = math.floor(sale.count + 0.5),
                cost = -(sale.total or 0), source = sale.source == "ah" and "ah" or "vendor" }, makerOf[sale.itemID])
        end
    end
    table.sort(rows, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)

    -- The shopping list first, then the route, then the goals at the end.
    local list = {}
    for _, item in ipairs(route.shopping or {}) do
        table.insert(list, shoppingElement({ itemID = item.itemID, count = item.count, buy = item.buy, source = item.source,
            each = item.each, npc = item.npc, estimated = item.estimated, firstSkill = item.firstSkill or route.startSkill,
            lastSkill = item.lastSkill }))
    end
    for _, row in ipairs(rows) do table.insert(list, row) end
    for _, row in ipairs(goalFor) do table.insert(list, row) end
    return list
end

-- The route as one list of display rows, in the order it is done (getting
-- a pattern and using it are one "learn" row). Each row:
--
--   { kind = "train"|"learn"|"buy"|"make"|"skillup"|"goal"|"sell", skill, toSkill?,
--     tier?, cap?, level? (train rows: "Journeyman", its cap, its level gate),
--     spell?, item?, count?, crafts?, gain?, forSpell?, low?, high?, cost? (copper, net for the row; a sale is
--     negative), spent?, earned? (the net's halves, on the rows the section
--     totals add up: train, learn, skillup, goal), estimated?, costUnknown?,
--     source? = "vendor"|"ah"|"craft"|"gather"|"estimate"|"trainer"|"boe"|"bop",
--     npc?, run? (index into route.runs) }
--
-- "make" is an intermediate made from its parts for the batch after it
-- (`forSpell`, and `run` for a run), `crafts` crafts giving `count` items;
-- `gain` is the points those crafts are expected to give, over skill to
-- toSkill (no toSkill when none). "skillup" is a grind run, "goal" a goal's
-- item. `input` is optional (profession, nameOf).
function Planner:Outline(route, input)
    local rows = {}
    for _, element in ipairs(sequence(route, input)) do table.insert(rows, element.row) end
    return rows
end

-- How the route is split into sections, as the Plan tab offers it:
--
--   trip    one shopping section with everything, then a section per trainer
--           tier: one trip to the shops covers the whole route
--   tier    a section per trainer tier, each with its own shopping
--   recipe  a section per `recipesPerSection` recipes made (grind runs or
--           goals; 1 by default), each with its own shopping: buy for them,
--           make them, move on
--   band    the skill levels cut at every multiple of `bandSize` (83-100, 100-150 at
--           50); Plan cuts runs at those skill levels, so a recipe crossing one is
--           two steps; each band with its own shopping
Planner.sectionModes = { "trip", "tier", "recipe", "band" }
local SECTION_MODES = { trip = true, tier = true, recipe = true, band = true }

-- What a section's rows cost, net: training, learning in gold, the grind and
-- the goals. A purchase, an intermediate or a sale is already part of a
-- run's net cost, so they are not added again.
local COSTED = { train = true, learn = true, skillup = true, goal = true }

-- The route split into sections, each with the rows it holds and the
-- materials it asks for:
--
--   { { title, kind = "shopping"|"tier"|"recipe"|"band"|"goals", fromSkill, toSkill,
--       elements = { sequence elements, shopping first },
--       shopping = { { itemID, count, source, each, npc, estimated, made, lastSkill } },
--       cost (copper, net), spent, earned (cost = spent - earned),
--       estimated = true|nil, spell? (recipe sections) } }
--
-- `input`: profession, nameOf, tiers, and `sections` (a mode above, default
-- "trip"), `bandSize` (default 25) and `recipesPerSection` (default 1). In a trip, the shopping section holds
-- the whole route's list and the other sections list none.
function Planner:Sections(route, input)
    input = input or {}
    local mode = SECTION_MODES[input.sections] and input.sections or "trip"
    local bandSize = math.max(5, math.floor(tonumber(input.bandSize) or self.defaultOptions.bandSize))
    local perSection = math.max(1, math.floor(tonumber(input.recipesPerSection) or self.defaultOptions.recipesPerSection))
    local tiers = tierSet(input)
    local profession = input.profession or route.profession
    local _, recipeName = namer(input)
    local target = route.target

    local function tierOf(skill)
        for index, tier in ipairs(tiers.tiers) do
            if skill < tier.cap then return index end
        end
        return #tiers.tiers
    end

    local sections, current = {}, nil
    local sectionOfBatch = {}
    local function open(kind)
        current = { kind = kind, elements = {}, batches = {}, holds = {}, shopping = {} }
        table.insert(sections, current)
        return current
    end
    local function put(section, element)
        table.insert(section.elements, element)
        local batch = element.batch
        if batch and not section.holds[batch] then
            section.holds[batch] = true
            table.insert(section.batches, batch)
            sectionOfBatch[batch] = section
        end
    end

    local goals
    for _, element in ipairs(sequence(route, input)) do
        if element.part == "shopping" then
            if mode == "trip" then
                if not sections[1] or sections[1].kind ~= "shopping" then
                    table.insert(sections, 1, { kind = "shopping", title = "Shopping", elements = {}, batches = {},
                        holds = {}, shopping = route.shopping or {} })
                end
                table.insert(sections[1].elements, element)
            end
        elseif element.part == "goals" then
            goals = goals or { kind = "goals", title = "Goals", elements = {}, batches = {}, holds = {}, shopping = {} }
            put(goals, element)
        elseif element.row.kind == "sell" and element.batch and sectionOfBatch[element.batch] and mode ~= "trip" and mode ~= "tier" then
            -- A sale follows the recipe that made it, even when the next
            -- recipe's section has already begun at the same skill.
            put(sectionOfBatch[element.batch], element)
        else
            local fresh
            if not current or current.kind == "shopping" then
                fresh = true
            elseif mode == "trip" or mode == "tier" then
                -- What happens at the target itself (the last sale) closes
                -- the tier it finishes, rather than opening an empty next one.
                fresh = tierOf(math.min(element.at, target - 1)) ~= current.tier
            elseif mode == "recipe" then
                if element.batch then
                    fresh = #current.batches >= perSection and not current.holds[element.batch]
                else
                    -- Training leads the section of the recipe after it.
                    fresh = #current.batches >= perSection and element.row.kind == "train"
                end
            else -- band
                -- Bands are the skill levels cut at every multiple of the size
                -- (83-100, 100-150, 150-200 at 50). Plan has already cut
                -- runs at those skill levels, so a step goes with the band it starts
                -- in; training leads the band it happens in.
                local band = math.floor(element.at / bandSize)
                local starts = element.batch == nil or not current.holds[element.batch]
                fresh = starts and band > (current.band or band)
            end
            if fresh then
                local kind = mode == "trip" and "tier" or mode
                open(kind)
                current.tier = tierOf(math.min(element.at, target - 1))
                current.start = element.at
                current.band = math.floor(element.at / bandSize)
            end
            put(current, element)
        end
    end
    if goals then table.insert(sections, goals) end

    -- Each split section's own shopping, from what its batches bring.
    local listed = {}
    for _, item in ipairs(route.shopping or {}) do listed[item.itemID] = item end
    local sourceOrder = { carried = 0, vendor = 1, ah = 2, estimate = 3, gather = 4, craft = 5 }
    for _, section in ipairs(sections) do
        if mode ~= "trip" then
            local totals, firstSkill, lastSkill, noEscape = {}, {}, {}, {}
            for _, batch in ipairs(section.batches) do
                for item, quantity in pairs(batch.buys or {}) do
                    totals[item] = (totals[item] or 0) + quantity
                    firstSkill[item] = math.min(firstSkill[item] or batch.skill, batch.skill)
                    lastSkill[item] = math.max(lastSkill[item] or 0, batch.toSkill)
                    if batch.goal and batch.goal.atEnd then noEscape[item] = true end
                end
            end
            for _, item in ipairs(sortedKeys(totals)) do
                local count = math.ceil(totals[item] - 1e-6)
                if count > 0 then
                    local info = listed[item] or {}
                    table.insert(section.shopping, { itemID = item, count = count, source = info.source or "gather",
                        each = info.each, npc = info.npc, estimated = info.estimated,
                        made = (route.made and route.made[item]) or info.made, firstSkill = firstSkill[item],
                        lastSkill = (not noEscape[item]) and lastSkill[item] or nil })
                end
            end
            table.sort(section.shopping, function(a, b)
                local left, right = sourceOrder[a.source] or 9, sourceOrder[b.source] or 9
                if left ~= right then return left < right end
                return a.itemID < b.itemID
            end)
            local shoppingElements = {}
            for _, item in ipairs(section.shopping) do
                table.insert(shoppingElements, shoppingElement(item))
            end
            for index = #shoppingElements, 1, -1 do table.insert(section.elements, 1, shoppingElements[index]) end
        end

        -- Skill levels, cost and title.
        local from, to, cost, estimated, spent, earned = nil, nil, 0, nil, 0, 0
        for _, element in ipairs(section.elements) do
            local row = element.row
            if element.part ~= "shopping" and row.kind ~= "sell" then
                if row.skill and (not from or row.skill < from) then from = row.skill end
                local top = row.toSkill or row.skill
                if top and (not to or top > to) then to = top end
            end
            if COSTED[row.kind] and row.cost then
                cost = cost + row.cost
                spent, earned = spent + (row.spent or row.cost), earned + (row.earned or 0)
            end
            if row.estimated then estimated = true end
        end
        -- A section that makes something spans what it makes; training
        -- at its head does not stretch it back.
        for index, batch in ipairs(section.batches) do
            if index == 1 then from, to = batch.skill, batch.toSkill end
            from, to = math.min(from, batch.skill), math.max(to, batch.toSkill)
        end
        section.fromSkill = math.max(from or route.startSkill, route.startSkill, 1)
        section.toSkill = math.min(to or target, target)
        section.cost, section.estimated = math.floor(cost + 0.5), estimated
        section.spent, section.earned = math.floor(spent + 0.5), math.floor(earned + 0.5)
        if section.kind == "tier" then
            local tier = tiers.tiers[section.tier]
            local lower = section.tier > 1 and tiers.tiers[section.tier - 1].cap or 0
            local low = math.max(lower, route.startSkill)
            if lower == 0 then low = math.max(low, 1) end
            section.fromSkill, section.toSkill = low, math.min(tier.cap, target)
            section.title = tier.name .. " " .. low .. "-" .. section.toSkill
        elseif section.kind == "recipe" then
            local batch = section.batches[1]
            if #section.batches > 1 then
                -- Several recipes: the first two by name, then how many more.
                local names, last = {}, nil
                for _, each in ipairs(section.batches) do
                    local name = recipeName(each.entry.spell, each.entry.item)
                    if name ~= last then table.insert(names, name) end
                    last = name
                end
                local shown = { names[1], names[2] }
                section.title = table.concat(shown, ", ") .. (#names > 2 and (" +" .. (#names - 2)) or "")
                    .. " " .. section.fromSkill .. "-" .. section.toSkill
            elseif batch and batch.goal then
                section.title = "Goal: " .. recipeName(batch.entry.spell, batch.entry.item) .. " x" .. batch.count
            elseif batch then
                section.title = recipeName(batch.entry.spell, batch.entry.item) .. " " .. section.fromSkill .. "-" .. section.toSkill
            else
                local row = section.elements[1].row
                section.title = row.kind == "train" and ("Train " .. tostring(row.tier)) or profession
            end
            section.spell = batch and batch.entry.spell or nil
        elseif section.kind == "band" and section.band then
            -- Its own round skill levels, clipped to where the route starts and
            -- ends; a recipe begun inside it may run on past them.
            section.fromSkill = math.max(section.band * bandSize, route.startSkill, 1)
            section.toSkill = math.min((section.band + 1) * bandSize, target)
            section.title = profession .. " " .. section.fromSkill .. "-" .. section.toSkill
        elseif section.kind == "band" then
            section.title = profession .. " " .. section.fromSkill .. "-" .. section.toSkill
        end
        section.holds, section.start, section.band = nil, nil, nil
    end
    return sections, mode
end

-- Live state to planner input ----------------------------------------------
--
-- The planner window (UI/Planner.lua) reads the client and hands plain
-- values here, so what it does with them stays testable.

-- The crafting professions the planner covers (PROF_PLAN.md, scope).
Planner.professions = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring",
    "Cooking", "First Aid" }

-- The key a profession's recipe data is filed under in `ns.professionData`
-- (Data/Professions/*.lua): the client's name without spaces, so "First
-- Aid" is `FirstAid`. Everything else (the client, the tiers, the saved
-- inputs) uses the client's name.
function Planner:DataKey(profession)
    return (tostring(profession):gsub("%s+", ""))
end

-- The client's name of a profession from its data key ("FirstAid" is
-- "First Aid", "Mining" is "Mining").
function Planner:ProfessionOfKey(key)
    for _, name in ipairs(self.professions) do
        if self:DataKey(name) == key then return name end
    end
    return (tostring(key):gsub("(%l)(%u)", "%1 %2"))
end

-- A profession's data with what the character's other professions can make
-- for it: Smelting (Mining) makes the bars Blacksmithing needs. `helpers`:
--   { { profession = "Mining", data = <its recipe data>, skill = n,
--       known = { [spellID] = true } (Planner:ResolveKnown; empty when its
--       window was never read) } }
-- A helper's recipe comes in when the character has its skill and knows it;
-- with nothing known of that profession yet, its starting recipes and the
-- trainer ones its skill allows stand in. Each comes in as a copy marked
-- `helper` (the profession's name): the planner makes materials with it but
-- never plans skill with it, and lists of the profession's own recipes leave
-- it out. The helpers' items join the data's (the data's own rows win).
-- `helpers` on the result lists what came in, by profession, for the plan's
-- signature. Without a helper recipe the data comes back as it is.
function Planner:WithHelpers(data, helpers)
    if type(data) ~= "table" or type(helpers) ~= "table" then return data end
    local recipes, items, came = nil, nil, nil
    for _, helper in ipairs(helpers) do
        local own = type(helper.data) == "table" and helper.data or {}
        local skill = tonumber(helper.skill) or 0
        local known = helper.known or {}
        local guess = next(known) == nil
        for _, spell in ipairs(sortedKeys(own.recipes or {})) do
            local recipe = own.recipes[spell]
            local skills = type(recipe) == "table" and recipe.skills
            local usable = skills and recipe.makes and not recipe.sod and (skills[1] or 0) <= skill
                and (known[spell] or recipe.learn == "start" or (guess and recipe.learn == "trainer"))
            if usable and not (data.recipes and data.recipes[spell]) then
                if not recipes then
                    recipes, items, came = {}, {}, {}
                    for key, value in pairs(data.recipes or {}) do recipes[key] = value end
                    for key, value in pairs(data.items or {}) do items[key] = value end
                end
                local merged = {}
                for key, value in pairs(recipe) do merged[key] = value end
                merged.helper = helper.profession
                recipes[spell] = merged
                came[helper.profession] = came[helper.profession] or {}
                table.insert(came[helper.profession], spell)
            end
        end
        if came and came[helper.profession] then
            for key, value in pairs(own.items or {}) do
                if items[key] == nil then items[key] = value end
            end
        end
    end
    if not recipes then return data end
    local out = {}
    for key, value in pairs(data) do out[key] = value end
    out.recipes, out.items, out.helpers = recipes, items, came
    return out
end

local function lower(text)
    return type(text) == "string" and text:lower() or nil
end

-- The client's known-recipe keys (API/Client.lua: a spell ID, "item:<id>" for
-- a Classic window, which names the product and not the spell, or
-- "name:<lower name>") as the planner's `{ [spellID] = true }`.
--
--   numeric keys      kept as they are
--   "item:<id>"       every recipe of the data whose `makes` is that item
--   "name:<name>"     every recipe whose spell name, or product name, is it;
--                     `nameOf(kind, id)` answers "spell" and "item" names
--                     (the client's), and without it name keys are dropped
function Planner:ResolveKnown(data, clientKnown, nameOf)
    local known = {}
    local recipes = data and data.recipes or {}
    local byItem, byName
    for key, value in pairs(clientKnown or {}) do
        if value then
            if type(key) == "number" then
                known[key] = true
            elseif type(key) == "string" and key:match("^item:%d+$") then
                if not byItem then
                    byItem = {}
                    for spell, recipe in pairs(recipes) do
                        if recipe.makes then
                            byItem[recipe.makes] = byItem[recipe.makes] or {}
                            table.insert(byItem[recipe.makes], spell)
                        end
                    end
                end
                for _, spell in ipairs(byItem[tonumber(key:match("%d+"))] or {}) do known[spell] = true end
            elseif type(key) == "string" and key:sub(1, 5) == "name:" and nameOf then
                if not byName then
                    byName = {}
                    for spell, recipe in pairs(recipes) do
                        local names = { lower(nameOf("spell", spell)), recipe.makes and lower(nameOf("item", recipe.makes)) or nil }
                        for _, name in pairs(names) do
                            byName[name] = byName[name] or {}
                            byName[name][spell] = true
                        end
                    end
                end
                for spell in pairs(byName[key:sub(6)] or {}) do known[spell] = true end
            end
        end
    end
    return known
end

-- The level the testing switch plans at: every tier's gate is behind it.
Planner.fullScopeLevel = 60

-- Planner:Plan's input from the saved inputs and what the client says now.
-- `live`: skill, maxSkill, level, known (client keys), bags (function), book,
-- nameOf (for name keys, and the status line's names), and fullScope, the
-- testing switch: the planner then ignores the level trainers ask for and
-- plans as a character of fullScopeLevel (the data and tiers it plans with
-- are the caller's to switch).
function Planner:MakeInput(profession, data, inputs, live)
    live = live or {}
    inputs = inputs or self:DefaultInputs()
    local level = live.level
    if live.fullScope then level = math.max(tonumber(level) or 0, self.fullScopeLevel) end
    return {
        profession = profession, data = data, fullScope = live.fullScope and true or nil,
        skill = live.skill or 0, maxSkill = live.maxSkill, level = level,
        target = inputs.target, known = self:ResolveKnown(data, live.known, live.nameOf),
        bags = live.bags, book = live.book, nameOf = live.nameOf,
        goals = inputs.goals, options = inputs.options, refused = inputs.refused,
        pinned = inputs.pinned, accepted = inputs.accepted, avoided = inputs.avoided,
        preferred = inputs.preferred, chosen = inputs.chosen,
    }
end

-- Where a recipe comes from, for the Recipes tab: "start", "trainer",
-- "vendor", "boe" or "bop", and its cost in copper when known and the NPC.
-- `ctx` is a Prices context.
function Planner:RecipeSource(ctx, spell, recipe)
    if recipe.learn == "start" then return "start", 0 end
    if recipe.learn == "trainer" then
        local cost, npc = ctx:TrainerCost(spell)
        return "trainer", cost, npc
    end
    local teach = recipe.teach
    if teach then
        local gold, npc = ctx:VendorPattern(teach)
        if gold then return "vendor", gold, npc end
    end
    if recipe.bind == "boe" then return "boe", teach and ctx:AuctionPattern(teach) or nil end
    return "bop"
end

-- Every item the Materials tab should offer for a route: what the route touches,
-- then the materials it could not get (a price is what makes them usable),
-- and with `all`, every reagent of the recipes that give skill between the
-- start and the target (or `upTo`, the skill asked for, when the route stopped
-- short of it for want of materials). Sorted item IDs, each once.
function Planner:PriceItems(route, data, all, upTo)
    local set = {}
    for _, item in ipairs(route and route.items or {}) do set[item] = true end
    for _, missing in ipairs(route and route.unobtainable or {}) do set[missing.itemID] = true end
    if all and route then
        local top = math.max(route.target, upTo or 0, route.startSkill + 1)
        for _, recipe in pairs(data and data.recipes or {}) do
            local skills = type(recipe) == "table" and recipe.skills
            if skills and not recipe.sod and not recipe.helper and skills[1] < top and skills[4] > route.startSkill then
                for _, reagent in ipairs(recipe.reagents or {}) do set[reagent[1]] = true end
            end
        end
    end
    return sortedKeys(set)
end

-- "best", "now", "end" or "at skill N": a goal's `when` in words.
function Planner:WhenText(goal)
    if goal.when == "skill" then return "at skill " .. tostring(goal.skill) end
    return goal.when or "best"
end

-- True once the live skill has passed the route's first run: the counts ahead
-- were sized from a skill the player has left, so the route is planned again
-- from where they are. Done is done.
function Planner:PassedRun(route, skill)
    if not route or not skill or skill >= route.target then return false end
    local first = route.runs[1]
    return first ~= nil and skill >= first.toSkill
end

-- What the live profession window should show for the route's recipes at
-- `skill`: { { spell, item, expected } }, one per recipe the skill can make,
-- for Client:CompareRecipeColor (a disagreement is logged; the window wins).
function Planner:ColorChecks(route, data, skill)
    local checks, seen = {}, {}
    local S = SkillUp()
    for _, run in ipairs(route and route.runs or {}) do
        local recipe = data and data.recipes and data.recipes[run.spell]
        if recipe and not seen[run.spell] then
            seen[run.spell] = true
            local color = S:Color(recipe.skills, skill or 0)
            if color ~= "unknown" then
                table.insert(checks, { spell = run.spell, item = recipe.makes, expected = color })
            end
        end
    end
    return checks
end

-- The choices at one step of a route (route.runs[runIndex]): each is one
-- recipe for exactly the step's skill levels S = [fromSkill, toSkill), cheapest
-- first, at most `limit` (default 12) besides the planner's:
--
--   { kind = "planner"|"other"|"pattern", fromSkill, toSkill (the step's),
--     spell, spells (the planner's may be more than one recipe over S; the
--     others are one), extra (copper the route costs more with it than with
--     the planner's; negative: cheaper; 0 for the planner's), perPoint,
--     crafts (expected over S), color, source (how it is learned; for a
--     pattern "vendor"|"boe"|"bop"), for a pattern bind, item, cost, npc,
--     needsPattern as a run's when the recipe is one the route may use but
--     the character lacks the pattern of, and using = true on the one the
--     route takes }
--
-- The candidates are every recipe the route may use, and every pattern it
-- could suggest, that gives skill at each skill of S. The baseline is the
-- route with the step's own stretch carved out and every other kept; its
-- recipes over S are the "planner" choice. Each other is solved chosen for
-- exactly S. Neither S nor the other stretches depend on what the step
-- holds, so the list, its figures and its order are the same whichever
-- choice is taken; only `using` moves. Sorted by extra, then spell. Solved
-- when first asked and cached on the route. {} when there is no such run
-- or nothing to solve with.
function Planner:WaysAround(route, runIndex, limit)
    limit = math.max(math.floor(tonumber(limit) or 12), 1)
    if not route or type(route.waysAround) ~= "function" then return {} end
    route.ways = route.ways or {}
    local ways = route.ways[runIndex]
    if not ways then
        local ok, list = pcall(route.waysAround, runIndex)
        if not ok or type(list) ~= "table" then
            if not ok and ns.Log then ns:Log("planner: ways around run " .. tostring(runIndex) .. ": " .. tostring(list)) end
            list = {}
        end
        ways = list
        route.ways[runIndex] = ways
    end
    local list, others = {}, 0
    for _, way in ipairs(ways) do
        if way.kind == "planner" then
            table.insert(list, way)
        elseif others < limit then
            others = others + 1
            table.insert(list, way)
        end
    end
    return list
end

-- The chosen stretch holding `skill` (fromSkill <= skill < toSkill), or nil.
-- The last one wins where two overlap, as in Plan.
function Planner:ChosenAt(inputs, skill)
    local found
    for _, stretch in ipairs(inputs and inputs.chosen or {}) do
        if stretch.fromSkill <= skill and skill < stretch.toSkill then found = stretch end
    end
    return found
end

-- Lets the planner choose again over [fromSkill, toSkill): a chosen stretch
-- inside it goes, one reaching past it keeps its skill levels outside. Returns how
-- many were touched.
function Planner:ClearChosen(inputs, fromSkill, toSkill)
    local touched
    inputs.chosen, touched = carve(inputs.chosen, fromSkill, toSkill)
    return touched
end

-- Takes one of Planner:WaysAround's choices for its step's skill levels alone:
-- whatever was chosen there goes, and an "other" or "pattern" choice is
-- chosen for exactly those skill levels; the planner's only clears. A pattern is
-- also marked as in hand ("have"), since owning it holds everywhere.
function Planner:UseWay(inputs, way)
    local from = type(way) == "table" and tonumber(way.fromSkill)
    local to = type(way) == "table" and tonumber(way.toSkill)
    if not from or not to or from >= to or (way.kind ~= "planner" and not way.spell) then return false end
    self:ClearChosen(inputs, from, to)
    if way.kind == "planner" then return true end
    if way.kind == "pattern" then self:SetPlanWith(inputs, way.spell, "have") end
    table.insert(inputs.chosen, { fromSkill = from, toSkill = to, spell = way.spell })
    return true
end

-- How many of the profession's recipes (SoD ones left out) need an item.
function Planner:MaterialRecipeCount(data, itemID)
    local count = 0
    for _, recipe in pairs(data and data.recipes or {}) do
        if type(recipe) == "table" and not recipe.sod and not recipe.helper then
            for _, reagent in ipairs(recipe.reagents or {}) do
                if reagent[1] == itemID then count = count + 1; break end
            end
        end
    end
    return count
end

-- The profession's materials whose name holds `query` (any case; "" or nil:
-- all), by name, at most `limit` (nil: all):
--   { { itemID, name, recipes = n recipes needing it, never = avoided } }
-- `nameOf(kind, id)` names items ("item <id>" without an answer); `inputs`,
-- when given, says which are avoided.
function Planner:MaterialCandidates(data, query, nameOf, limit, inputs)
    local counts = {}
    for _, recipe in pairs(data and data.recipes or {}) do
        if type(recipe) == "table" and not recipe.sod and not recipe.helper then
            local seen = {}
            for _, reagent in ipairs(recipe.reagents or {}) do
                local item = reagent[1]
                if not seen[item] then
                    seen[item] = true
                    counts[item] = (counts[item] or 0) + 1
                end
            end
        end
    end
    local needle = type(query) == "string" and query:lower() or ""
    local avoided = inputs and inputs.avoided or {}
    local list = {}
    for item, count in pairs(counts) do
        local name = nameOf and nameOf("item", item) or nil
        name = type(name) == "string" and name or ("item " .. tostring(item))
        if needle == "" or name:lower():find(needle, 1, true) then
            table.insert(list, { itemID = item, name = name, recipes = count, never = avoided[item] == true })
        end
    end
    table.sort(list, function(a, b)
        local left, right = a.name:lower(), b.name:lower()
        if left ~= right then return left < right end
        return a.itemID < b.itemID
    end)
    limit = tonumber(limit)
    if limit then
        for index = #list, math.max(math.floor(limit), 0) + 1, -1 do list[index] = nil end
    end
    return list
end

ns:RegisterModule("ProfessionPlanner", Planner)
