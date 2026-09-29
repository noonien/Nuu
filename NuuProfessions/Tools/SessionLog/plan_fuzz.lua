-- Tools/SessionLog/plan_fuzz.lua
-- Random Profession Planner play, to find what the fixtures do not show.
-- A seed makes a character from the real recipe data (profession, skill,
-- trained cap, known recipes, bags, a few prices, options, goals; Mining
-- beside Blacksmithing and Engineering) and plays it as a player would:
-- mostly pressing Make on the step the button picks and crafting part or
-- all of the batch, with a plan after every craft, and between crafts
-- doing what players do - crafting some other recipe, looting or losing
-- materials, buying the shopping list, changing options and the target,
-- taking another way for a step, refusing a recipe, adding a goal,
-- training at the cap. Both Only what I have and buying are played.
--
-- After every plan the invariants below are checked; a broken one is a
-- problem, named with the seed and the step, and the same seed plays the
-- same game again (Fuzz.Play with `log` shows it move by move).
--
--   no error from Plan, Sections, Outline, Status, WaysAround
--   the same input plans the same route twice
--   runs in skill order inside [start, target], each giving skill over its
--     skill levels, with whole counts of at least one and finite figures
--   every step made at the count its Make button orders, from the bags and
--     the plan's own shopping, never runs short of a material
--   Only what I have: nothing to buy but from a vendor, no shortfall
--     warned, the Make button's step makeable from the bags, and where the
--     materials end the route no step leaves a craft of its recipe unmade
--   buying: once the shopping list is bought the Make button can make
local Fuzz = {}

local Snapshot = dofile("Tools/SessionLog/plan_snapshot.lua")

local function sortedKeys(set)
    local keys = {}
    for key in pairs(set) do table.insert(keys, key) end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = deepCopy(item) end
    return out
end

-- A seeded generator: the same seed, the same game.
local function generator(seed)
    local state = (tonumber(seed) or 1) % 2147483648
    local rng = {}
    function rng.float()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
    function rng.int(low, high) return low + math.floor(rng.float() * (high - low + 1)) end
    function rng.chance(p) return rng.float() < p end
    function rng.pick(list) return list[rng.int(1, #list)] end
    return rng
end

local function finite(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end

local function usable(recipe)
    return type(recipe) == "table" and type(recipe.skills) == "table" and not recipe.sod
end

-- A character: the snapshot Snapshot.Input plans from, with its inputs.
function Fuzz.Scenario(ns, seed)
    local Planner, Prices = ns.modules.ProfessionPlanner, ns.modules.Prices
    local rng = generator(seed * 7919 + 17)
    local keys = sortedKeys(ns.professionData)
    local key = rng.pick(keys)
    local data = ns.professionData[key]
    local profession = Planner:ProfessionOfKey(key)
    local spells = {}
    for _, spell in ipairs(sortedKeys(data.recipes)) do
        if usable(data.recipes[spell]) then table.insert(spells, spell) end
    end
    local anchor = data.recipes[rng.pick(spells)]
    local skill = math.max(1, math.min(220, anchor.skills[1] + rng.int(0, 15)))
    if rng.chance(0.1) then skill = 1 end
    local maxSkill = 75
    for _, cap in ipairs({ 75, 150, 225 }) do
        if cap > skill then maxSkill = cap; break end
    end
    if skill >= 225 then skill, maxSkill = 224, 225 end
    if rng.chance(0.08) then skill = maxSkill end
    -- Not learned yet: skill 0.
    if rng.chance(0.04) then skill, maxSkill = 0, 75 end
    local known = {}
    for _, spell in ipairs(spells) do
        local recipe = data.recipes[spell]
        if recipe.learn == "start" or (recipe.learn == "trainer" and recipe.skills[1] <= skill + 10 and rng.chance(0.75))
            or (recipe.learn ~= "start" and recipe.learn ~= "trainer" and rng.chance(0.2)) then
            table.insert(known, spell)
        end
    end
    local helpers = {}
    if (profession == "Blacksmithing" or profession == "Engineering") and ns.professionData.Mining and rng.chance(0.6) then
        local mining = ns.professionData.Mining
        local list = {}
        for _, spell in ipairs(sortedKeys(mining.recipes)) do
            local recipe = mining.recipes[spell]
            if usable(recipe) and recipe.makes and (recipe.learn == "start" or rng.chance(0.5)) then table.insert(list, spell) end
        end
        if #list > 0 then helpers.Mining = list end
    end
    -- Bags: materials of recipes near the skill, in amounts from a craft's
    -- worth to plenty, now and then what a recipe makes.
    local pool = {}
    local seen = {}
    local function addPool(item)
        if not seen[item] then seen[item] = true; table.insert(pool, item) end
    end
    for _, spell in ipairs(spells) do
        local recipe = data.recipes[spell]
        if recipe.skills[1] <= skill + 10 and recipe.skills[4] > skill then
            for _, reagent in ipairs(recipe.reagents or {}) do addPool(reagent[1]) end
        end
    end
    for name, list in pairs(helpers) do
        for _, spell in ipairs(list) do
            for _, reagent in ipairs(ns.professionData[Planner:DataKey(name)].recipes[spell].reagents or {}) do
                addPool(reagent[1])
            end
        end
    end
    table.sort(pool)
    local bags = {}
    local amounts = { 1, 2, 3, 4, 5, 6, 8, 12, 20, 40, 100, 1000 }
    for _ = 1, rng.int(0, 7) do
        if #pool > 0 then bags[rng.pick(pool)] = rng.pick(amounts) end
    end
    if rng.chance(0.2) then
        local recipe = data.recipes[rng.pick(spells)]
        if recipe.makes then bags[recipe.makes] = rng.int(1, 10) end
    end
    local bagList = {}
    for _, item in ipairs(sortedKeys(bags)) do table.insert(bagList, { item, bags[item] }) end
    -- A few auction prices, now and then.
    local book = { prices = {}, trainers = {}, merchants = {} }
    -- A trainer that teaches a recipe before the data's learn skill (the
    -- Forever belt taught at 30, 70 in the data), or after it.
    if rng.chance(0.2) then
        local rows = {}
        for _ = 1, rng.int(1, 3) do
            local spell = rng.pick(spells)
            local recipe = data.recipes[spell]
            if recipe.learn == "trainer" then
                rows[spell] = { spellID = spell, profession = profession, cost = rng.pick({ 10, 100, 1000 }),
                    skill = math.max(1, recipe.skills[1] + rng.int(-40, 10)) }
            end
        end
        book.trainers[99999] = rows
    end
    if rng.chance(0.4) and #pool > 0 then
        for _ = 1, rng.int(1, 4) do
            Prices:SetFact(book, rng.pick(pool), "auctionBuy", rng.pick({ 1, 5, 25, 120, 800, 5000 }), "player")
        end
    end
    -- The planner's inputs, as the window keeps them.
    local inputs = Planner:DefaultInputs()
    inputs.options.materials = rng.chance(0.55) and "carried" or "buy"
    if rng.chance(0.4) then inputs.options.confidence = rng.pick({ "typical", "safe", "sure" }) end
    if rng.chance(0.2) then inputs.options.optimize = "profit" end
    if rng.chance(0.3) then inputs.options.sections = rng.pick({ "trip", "tier", "recipe", "band" }) end
    if rng.chance(0.2) then inputs.options.recipes = "trainer" end
    if rng.chance(0.15) then inputs.options.auction = rng.pick({ "none", "both", "sell" }) end
    if rng.chance(0.45) then inputs.target = math.min(skill + rng.int(1, 40), 225) end
    if rng.chance(0.04) then inputs.target = math.max(0, skill - rng.int(0, 5)) end
    -- A material never used, or preferred.
    if rng.chance(0.1) and #pool > 0 then
        Planner:SetMaterialMode(inputs, rng.pick(pool), rng.pick({ "never", "prefer" }))
    end
    -- A chosen stretch the planner has to cope with: backwards, past the
    -- target, or naming a recipe not in the data.
    if rng.chance(0.05) then
        local from = skill + rng.int(-5, 20)
        table.insert(inputs.chosen, { fromSkill = from, toSkill = from + rng.int(-3, 10),
            spell = rng.chance(0.5) and rng.pick(spells) or 424242 })
    end
    if rng.chance(0.15) and #known > 0 then
        Planner:AddGoal(inputs, { spell = rng.pick(known), count = rng.int(1, 3),
            when = rng.pick({ "best", "now", "end", "skill" }), skill = skill + rng.int(-5, 30) })
    end
    return {
        profession = profession, skill = skill, maxSkill = maxSkill, level = rng.int(5, 25), fullScope = nil,
        inputs = inputs, known = known, helpers = helpers, bags = bagList, book = book,
    }
end

-- The count the Make button orders for an outline row when the skill is
-- `skill` (UI/PlannerPlan.lua MakeOrder), or nil.
local function makeCount(ns, input, route, row, skill)
    local Planner, Crafting = ns.modules.ProfessionPlanner, ns.Kit.Crafting
    local recipe = row.spell and input.data.recipes[row.spell]
    if not recipe then return nil end
    if row.kind == "skillup" then
        if row.toSkill <= skill then return nil end
        local skills = Planner:Skills(input.book, row.spell, recipe)
        local count = Crafting:ToSkill(recipe, math.max(skill, row.skill), row.toSkill, route.confidence, skills)
        local run = row.run and route.runs[row.run]
        if count and run and run.carriedCap then count = run.count end
        return count
    elseif row.kind == "make" then
        local passed = row.gain and (row.toSkill or row.skill) <= skill or (not row.gain and row.skill < skill)
        if passed then return nil end
        return math.floor((row.crafts or 0) + 0.5)
    elseif row.kind == "goal" then
        return row.count or 1
    end
    return nil
end

-- The Make button's step: the first row it can order, with its count.
local function makeStep(ns, input, route, skill)
    for _, row in ipairs(ns.modules.ProfessionPlanner:Outline(route, input)) do
        local count = makeCount(ns, input, route, row, skill)
        if count and count > 0 then return row, count end
    end
    return nil
end

local function canMake(ns, recipe, bags)
    return ns.Kit.Crafting:CanMake(recipe, function(item) return bags[item] or 0 end)
end

-- Every check on one plan. `add(text)` records a broken invariant.
local function checkPlan(ns, input, route, bags, skill, add)
    local Planner, SkillUp = ns.modules.ProfessionPlanner, ns.Kit.SkillUp
    local Crafting = ns.Kit.Crafting
    local carried = route.materials == "carried"
    -- The rest of what the window does with a plan.
    local split = { profession = input.profession, sections = input.options and input.options.sections }
    local ok, err = pcall(Planner.Sections, Planner, route, split)
    if not ok then add("Sections: " .. tostring(err)) end
    local outlineOK, outline = pcall(Planner.Outline, Planner, route, input)
    if not outlineOK then add("Outline: " .. tostring(outline)); outline = {} end
    ok, err = pcall(Planner.Status, Planner, route, nil, input.data)
    if not ok then add("Status: " .. tostring(err)) end
    -- The runs themselves.
    local last = route.startSkill
    for index, run in ipairs(route.runs) do
        local where = "run " .. index .. " (" .. run.spell .. " " .. run.fromSkill .. "-" .. run.toSkill .. ")"
        if run.fromSkill < last then add(where .. " starts before the one before it ends") end
        if run.fromSkill >= run.toSkill then add(where .. " covers no skill") end
        if run.toSkill > route.target then add(where .. " runs past the target " .. route.target) end
        last = run.toSkill
        local recipe = input.data.recipes[run.spell]
        local skills = Planner:Skills(input.book, run.spell, recipe)
        for at = run.fromSkill, run.toSkill - 1 do
            if SkillUp:Chance(skills, at) <= 0 then add(where .. " gives no skill at " .. at); break end
        end
        if type(run.count) ~= "number" or run.count < 1 or run.count % 1 ~= 0 then
            add(where .. " has a count of " .. tostring(run.count))
        end
        if not (run.low and run.high and run.low <= run.high) then
            add(where .. " has the range " .. tostring(run.low) .. "-" .. tostring(run.high))
        end
        for _, field in ipairs({ "expected", "perCraft", "perPoint", "matCraft" }) do
            if run[field] ~= nil and not finite(run[field]) then add(where .. " has " .. field .. " = " .. tostring(run[field])) end
        end
    end
    for _, field in ipairs({ "spent", "recovered", "net", "low", "high" }) do
        local value = route.summary and route.summary[field]
        if value ~= nil and not finite(value) then add("summary." .. field .. " = " .. tostring(value)) end
    end
    -- A goal's shortfall is told, not cut: its materials are left out.
    local goalItems = Snapshot.GoalItems(input)
    -- Only what I have buys nothing but from vendors, and never falls short.
    if carried then
        for _, row in ipairs(route.shopping or {}) do
            if (row.buy or 0) > 0 and row.source ~= "vendor" and not goalItems[row.itemID] then
                add("with only what is carried, the plan buys " .. row.buy .. " of " .. row.itemID .. " (" .. tostring(row.source) .. ")")
            end
        end
        for _, warning in ipairs(route.warnings or {}) do
            if warning.code == "carriedShort" and not goalItems[warning.item] then add("a shortfall is warned: " .. warning.text) end
        end
    end
    -- Every step at its own count (a grind step's run count: what a later
    -- step takes from it is counted on that; its Make button orders no
    -- more), from the bags and the plan's shopping.
    local stock = {}
    for item, count in pairs(bags) do stock[item] = count end
    for _, row in ipairs(route.shopping or {}) do
        if (row.buy or 0) > 0 and (not carried or row.source == "vendor") then
            stock[row.itemID] = (stock[row.itemID] or 0) + row.buy
        end
    end
    local at = skill
    local short
    for _, row in ipairs(outline) do
        local count = makeCount(ns, input, route, row, math.max(at, row.skill or at))
        local run = row.kind == "skillup" and row.run and route.runs[row.run]
        if run and count then
            if count > run.count then
                add(string.format("the Make button orders %d of %s where the step's count is %d", count, row.spell, run.count))
            end
            count = run.count
        end
        local recipe = row.spell and input.data.recipes[row.spell]
        if count and count > 0 and recipe then
            for _, reagent in ipairs(recipe.reagents or {}) do
                local item = reagent[1]
                stock[item] = (stock[item] or 0) - count * (reagent[2] or 1)
                if stock[item] < 0 and not short and not goalItems[item] then
                    short = item
                    add(string.format("made at its count, the %s step (%s x%d) is %d of %s short", row.kind,
                        row.spell, count, -stock[item], item))
                end
            end
            -- What a craft makes, on average, as the planner counts it.
            if recipe.makes then stock[recipe.makes] = (stock[recipe.makes] or 0) + count * Crafting:AverageMade(recipe) end
        end
        if row.kind == "skillup" then at = math.max(at, row.toSkill) end
    end
    -- The Make button: a step to make short of the target, makeable with
    -- only what is carried.
    local row, count = makeStep(ns, input, route, skill)
    if not row and #route.runs > 0 and route.target > skill then
        add("the plan goes to " .. route.target .. " and the Make button has nothing to make")
    end
    local forGoal = row and (row.kind == "goal" or (row.kind == "make" and row.item and goalItems[row.item]))
    if row and carried and not forGoal then
        -- What vendors sell is the plan's to buy, even with only what is carried.
        local reach = {}
        for item, count in pairs(bags) do reach[item] = count end
        for _, shop in ipairs(route.shopping or {}) do
            if (shop.buy or 0) > 0 and shop.source == "vendor" then
                reach[shop.itemID] = (reach[shop.itemID] or 0) + shop.buy
            end
        end
        if (canMake(ns, input.data.recipes[row.spell], reach) or 0) < 1 then
            add("the Make button is on " .. row.spell .. " (" .. row.kind .. ") with no materials for one")
        end
    end
    -- Where the materials end the route, no step's recipe is left makeable
    -- once every step has made its own count (a step before the last on a
    -- material orders fewer, and the next plan finds what it left).
    if carried and route.ceiling and route.ceiling.reason == "materials" and not short then
        local left = {}
        for item, count in pairs(bags) do left[item] = count end
        for _, shop in ipairs(route.shopping or {}) do
            if (shop.buy or 0) > 0 and shop.source == "vendor" then left[shop.itemID] = (left[shop.itemID] or 0) + shop.buy end
        end
        for _, step in ipairs(outline) do
            local recipe = step.spell and input.data.recipes[step.spell]
            local crafts = step.kind == "skillup" and step.run and route.runs[step.run] and route.runs[step.run].count
                or (step.kind == "make" and step.crafts) or (step.kind == "goal" and makeCount(ns, input, route, step, skill))
            if recipe and crafts then
                -- Each step makes what it can of its count from what is left,
                -- never from nothing. A goal and its parts keep their share
                -- even when short of one material: the planner holds the rest
                -- for it, to be made once that material is had.
                local can = math.min(crafts, canMake(ns, recipe, left) or crafts)
                local forGoal = step.kind == "goal" or (step.kind == "make" and step.item and goalItems[step.item])
                local used = forGoal and crafts or can
                for _, reagent in ipairs(recipe.reagents or {}) do
                    left[reagent[1]] = math.max(0, (left[reagent[1]] or 0) - used * (reagent[2] or 1))
                end
                if recipe.makes then left[recipe.makes] = (left[recipe.makes] or 0) + can * Crafting:AverageMade(recipe) end
            end
        end
        for _, run in ipairs(route.runs) do
            if run.carriedCap and (canMake(ns, input.data.recipes[run.spell], left) or 0) > 0 then
                add("the plan leaves crafts of " .. run.spell .. " in the bags where the materials end the route")
            end
        end
    end
    return row, count
end

local function describe(route)
    return Snapshot.Describe(route.runs) .. " to " .. tostring(route.target)
end

local function shoppingText(route)
    local parts = {}
    for _, row in ipairs(route.shopping or {}) do
        table.insert(parts, row.itemID .. ":" .. tostring(row.buy) .. ":" .. tostring(row.source))
    end
    return table.concat(parts, " ")
end

-- Plays a seed's character for up to `options.moves` moves. Returns the
-- problems ({ text }), how many plans were made, and the moves (for `log`).
function Fuzz.Play(ns, seed, options)
    options = options or {}
    local Planner, SkillUp, Crafting = ns.modules.ProfessionPlanner, ns.Kit.SkillUp, ns.Kit.Crafting
    local rng = generator(seed * 104729 + 3)
    local snapshot = Fuzz.Scenario(ns, seed)
    local bags = {}
    for _, row in ipairs(snapshot.bags) do bags[row[1]] = row[2] end
    local skill, maxSkill = snapshot.skill, snapshot.maxSkill
    local inputs = deepCopy(snapshot.inputs)
    local problems, plans, moves, reported = {}, 0, {}, {}
    local log = options.log
    local function note(text)
        table.insert(moves, text)
        if log then log(text) end
    end
    note(string.format("seed %d: %s %d/%d, %s, bags %s", seed, snapshot.profession, skill, maxSkill,
        tostring(inputs.options.materials), Snapshot.Serialize(snapshot.bags):gsub("%s+", " ")))

    local function current()
        local now = {}
        for key, value in pairs(snapshot) do now[key] = value end
        now.skill, now.maxSkill, now.inputs = skill, maxSkill, inputs
        now.bags = {}
        for _, item in ipairs(sortedKeys(bags)) do
            if bags[item] > 0 then table.insert(now.bags, { item, bags[item] }) end
        end
        return now
    end
    local function craft(input, spell, times)
        local recipe = input.data.recipes[spell]
        local made, ups = 0, 0
        for _ = 1, times do
            if (canMake(ns, recipe, bags) or 0) < 1 then break end
            for _, reagent in ipairs(recipe.reagents or {}) do bags[reagent[1]] = bags[reagent[1]] - (reagent[2] or 1) end
            -- A craft makes what the game rolls in the recipe's range.
            if recipe.makes then
                local made = recipe.made or {}
                bags[recipe.makes] = (bags[recipe.makes] or 0) + rng.int(made[1] or 1, made[2] or made[1] or 1)
            end
            if not recipe.helper and skill < maxSkill then
                local chance = SkillUp:Chance(Planner:Skills(input.book, spell, recipe), skill)
                if rng.float() < chance then skill, ups = skill + 1, ups + 1 end
            end
            made = made + 1
            -- The game plans again after every craft; the first few of a
            -- batch and a sample of the rest are planned here.
            if made < times and (made <= 3 or rng.chance(0.15)) then
                local again = Snapshot.Input(ns, current())
                local planned, route = pcall(Planner.Plan, Planner, again)
                plans = plans + 1
                if not planned then
                    table.insert(problems, string.format("seed %d move %d: Plan failed mid-batch: %s", seed, #moves, tostring(route)))
                    break
                end
            end
        end
        return made, ups
    end

    for move = 1, options.moves or 24 do
        local input = Snapshot.Input(ns, current())
        local planned, route = pcall(Planner.Plan, Planner, input)
        plans = plans + 1
        -- Each problem once a seed, at the first move it shows.
        local function add(text)
            local kind = text:gsub("%d+", "#")
            if reported[kind] then return end
            reported[kind] = true
            table.insert(problems, string.format("seed %d move %d (%s %d/%d, %s): %s", seed, move, snapshot.profession,
                skill, maxSkill, tostring(inputs.options.materials), text))
        end
        if not planned then
            add("Plan failed: " .. tostring(route))
            break
        end
        -- The same input plans the same route.
        if move % 3 == 1 then
            local again = pcall(Planner.Plan, Planner, Snapshot.Input(ns, current()))
            local second = select(2, pcall(Planner.Plan, Planner, Snapshot.Input(ns, current())))
            if again and type(second) == "table" and (describe(second) ~= describe(route)
                or shoppingText(second) ~= shoppingText(route)) then
                add("planned twice, two routes: " .. describe(route) .. " | " .. describe(second))
            end
        end
        if options.dump and options.dump == move then return current(), route, input end
        local checked, row, count = pcall(checkPlan, ns, input, route, bags, skill, add)
        if not checked then add("the checks failed: " .. tostring(row)); row = nil end
        if log then log(string.format("  plan: %s", describe(route))) end

        local roll = rng.float()
        if roll < 0.62 then
            -- Follow the plan: learn the step's recipe if the plan has it
            -- learned, buy what it asks when the step needs it, then Make.
            if row and not input.known[row.spell] and not input.data.recipes[row.spell].helper then
                table.insert(snapshot.known, row.spell)
                input = Snapshot.Input(ns, current())
                note("learn " .. row.spell)
            end
            if row then
                local recipe = input.data.recipes[row.spell]
                if (canMake(ns, recipe, bags) or 0) < 1 then
                    local carriedOnly = route.materials == "carried"
                    for _, shop in ipairs(route.shopping or {}) do
                        if (shop.buy or 0) > 0 and (not carriedOnly or shop.source == "vendor") then
                            bags[shop.itemID] = (bags[shop.itemID] or 0) + shop.buy
                        end
                    end
                    note(carriedOnly and "buy from the vendor" or "buy the shopping list")
                    local forGoal = row.kind == "goal"
                        or (row.kind == "make" and row.item and Snapshot.GoalItems(input)[row.item])
                    if (canMake(ns, recipe, bags) or 0) < 1 and not forGoal then
                        add("after buying the shopping list the Make button's step " .. row.spell .. " has no materials")
                    end
                end
            end
            if row then
                local times = rng.chance(0.6) and count or rng.int(1, count)
                local made, ups = craft(input, row.spell, times)
                note(string.format("Make %s x%d (ordered %d): %d skill-up%s, now %d", row.spell, made, count, ups,
                    ups == 1 and "" or "s", skill))
            elseif skill >= maxSkill and maxSkill < 225 then
                maxSkill = maxSkill + 75
                note("train to " .. maxSkill)
            else
                note("nothing to make")
                if rng.chance(0.5) then break end
            end
        elseif roll < 0.74 then
            -- Craft something else the bags make.
            local choices = {}
            for _, spell in ipairs(sortedKeys(input.data.recipes)) do
                local recipe = input.data.recipes[spell]
                if (input.known[spell] or recipe.helper) and (canMake(ns, recipe, bags) or 0) > 0 then
                    table.insert(choices, spell)
                end
            end
            if #choices > 0 then
                local spell = rng.pick(choices)
                local made, ups = craft(input, spell, rng.int(1, 3))
                note(string.format("switch: make %s x%d, %d skill-up%s, now %d", spell, made, ups, ups == 1 and "" or "s", skill))
            end
        elseif roll < 0.80 then
            local items = sortedKeys(input.data.items or {})
            if #items > 0 then
                local item, gained = rng.pick(items), rng.int(1, 20)
                bags[item] = (bags[item] or 0) + gained
                note("loot " .. gained .. " of " .. item)
            end
        elseif roll < 0.84 then
            local items = sortedKeys(bags)
            if #items > 0 then
                local item = rng.pick(items)
                local lost = rng.int(1, math.max(1, bags[item]))
                bags[item] = math.max(0, bags[item] - lost)
                note("lose " .. lost .. " of " .. item)
            end
        elseif roll < 0.90 then
            local change = rng.int(1, 6)
            if change == 1 then
                inputs.options.materials = inputs.options.materials == "carried" and "buy" or "carried"
                note("materials: " .. inputs.options.materials)
            elseif change == 2 then
                inputs.target = rng.chance(0.5) and math.min(skill + rng.int(1, 30), 225) or nil
                note("target " .. tostring(inputs.target))
            elseif change == 3 then
                inputs.options.confidence = rng.pick({ "typical", "safe", "sure" })
                note("confidence " .. inputs.options.confidence)
            elseif change == 4 then
                inputs.options.sections = rng.pick({ "trip", "tier", "recipe", "band" })
                note("sections " .. inputs.options.sections)
            elseif change == 5 then
                inputs.options.optimize = inputs.options.optimize == "profit" and "cost" or "profit"
                note("optimize " .. inputs.options.optimize)
            else
                inputs.options.recipes = inputs.options.recipes == "trainer" and "patterns" or "trainer"
                note("recipes " .. inputs.options.recipes)
            end
        elseif roll < 0.94 then
            if #route.runs > 0 then
                local index = rng.int(1, #route.runs)
                local ways = Planner:WaysAround(route, index, 6)
                if #ways > 0 then
                    local way = rng.pick(ways)
                    Planner:UseWay(inputs, way)
                    note("use another way for run " .. index .. ": " .. tostring(way.kind) .. " " .. tostring(way.spell))
                end
            end
        elseif roll < 0.96 then
            if rng.chance(0.15) then
                for _, run in ipairs(route.runs) do Planner:Refuse(inputs, run.spell, true) end
                note("never use any recipe of the route")
            elseif rng.chance(0.4) then
                local items = sortedKeys(input.data.items or {})
                if #items > 0 then
                    local item, mode = rng.pick(items), rng.pick({ "never", "prefer", "auto" })
                    Planner:SetMaterialMode(inputs, item, mode)
                    note("material " .. item .. ": " .. mode)
                end
            elseif #route.runs > 0 then
                local spell = route.runs[rng.int(1, #route.runs)].spell
                Planner:Refuse(inputs, spell, true)
                note("never use " .. spell)
            end
        elseif roll < 0.98 then
            local known = sortedKeys(input.known)
            if rng.chance(0.3) and #(inputs.goals or {}) > 0 then
                Planner:RemoveGoal(inputs, 1)
                note("remove a goal")
            elseif #known > 0 then
                local spell = rng.pick(known)
                Planner:AddGoal(inputs, { spell = spell, count = rng.int(1, 3), when = rng.pick({ "best", "now", "end" }) })
                note("goal " .. spell)
            end
        else
            if skill < maxSkill then
                skill = skill + 1
                note("a point from elsewhere, now " .. skill)
            end
        end
    end
    return problems, plans, moves
end

return Fuzz
