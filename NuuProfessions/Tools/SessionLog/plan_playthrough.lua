-- Tools/SessionLog/plan_playthrough.lua
-- Plays a Profession Planner plan the way the game does: plan, press Make on
-- the step the button picks with the count it orders (UI/PlannerPlan.lua
-- MakeTarget and MakeOrder, capped by what the bags make as Crafting:Button
-- caps it), craft that batch one craft at a time (the client cannot stop a
-- batch), each craft taking its reagents from the bags, adding what it
-- makes and rolling its skill-up at the chance the planner uses; then plan
-- again from where that leaves the character, until nothing is left to make.
--
-- Playthrough.Exact follows every skill-up outcome with its probability
-- (states met twice are planned once), for the exact odds of where
-- following the plan ends. Playthrough.Sample plays one path with a seeded
-- roll, for reading. Both report what went wrong on the way (`problems`):
-- a plan asking for more than the bags hold, a Make button that cannot
-- make, a plan short of its target with nothing to make.
--
-- `single = true` presses Make for one craft at a time instead of the batch.
local Playthrough = {}

local Snapshot = dofile("Tools/SessionLog/plan_snapshot.lua")

local function state(snapshot)
    local bags = {}
    for _, row in ipairs(snapshot.bags or {}) do bags[row[1]] = row[2] end
    return { skill = snapshot.skill, bags = bags }
end

local function withState(snapshot, now)
    local copy = {}
    for key, value in pairs(snapshot) do copy[key] = value end
    copy.skill = now.skill
    copy.bags = {}
    for item, count in pairs(now.bags) do
        if count > 0 then table.insert(copy.bags, { item, count }) end
    end
    table.sort(copy.bags, function(a, b) return a[1] < b[1] end)
    return copy
end

local function key(now, batch)
    local parts = { now.skill }
    local items = {}
    for item, count in pairs(now.bags) do if count > 0 then table.insert(items, item) end end
    table.sort(items)
    for _, item in ipairs(items) do table.insert(parts, item .. "=" .. now.bags[item]) end
    if batch then table.insert(parts, "batch:" .. batch.spell .. "x" .. batch.left) end
    return table.concat(parts, " ")
end

-- The step the Make button acts on after a plan, and its order: the first
-- row not behind the skill that the button can order (MakeOrder), its count
-- capped by the crafts the bags make. nil when there is none.
local function makeStep(ns, input, route, now)
    local Planner, Crafting = ns.modules.ProfessionPlanner, ns.Kit.Crafting
    local data = input.data
    for _, row in ipairs(Planner:Outline(route, input)) do
        local recipe = row.spell and data.recipes[row.spell]
        local count
        if row.kind == "skillup" and recipe and row.toSkill > now.skill then
            local skills = Planner:Skills(input.book, row.spell, recipe)
            count = Crafting:ToSkill(recipe, math.max(now.skill, row.skill), row.toSkill, route.confidence, skills)
            -- Only what I have: the crafts the bags make (MakeOrder's model.carried).
            local run = row.run and route.runs[row.run]
            if count and run and run.carriedCap then count = run.count end
        elseif row.kind == "make" and recipe then
            local passed = row.gain and (row.toSkill or row.skill) <= now.skill or (not row.gain and row.skill < now.skill)
            if not passed then count = math.floor((row.crafts or 0) + 0.5) end
        end
        if count and count > 0 then
            local carried = Crafting:CanMake(recipe, function(item) return now.bags[item] or 0 end)
            return { row = row, spell = row.spell, recipe = recipe, wanted = count,
                count = carried and math.min(count, carried) or count, carried = carried }
        end
    end
    return nil
end

-- What is wrong with a plan, read against the bags it was made from.
local function check(route, now, step, problems, where, ns, input)
    local function add(text) table.insert(problems, where .. ": " .. text) end
    -- A goal's shortfall is told, not cut: its materials are left out.
    local goalItems = input and Snapshot.GoalItems(input) or {}
    -- Nothing left to make while the bags still make a known recipe that
    -- gives a point here: the plan dropped it.
    if not step and ns and input and not (input.maxSkill and now.skill >= input.maxSkill) then
        local Planner, Crafting, SkillUp = ns.modules.ProfessionPlanner, ns.Kit.Crafting, ns.Kit.SkillUp
        for spell, recipe in pairs(input.data.recipes) do
            if input.known[spell] and not recipe.helper and recipe.skills
                and SkillUp:Chance(Planner:Skills(input.book, spell, recipe), now.skill) > 0
                and (Crafting:CanMake(recipe, function(item) return now.bags[item] or 0 end) or 0) > 0 then
                add("the plan ends with the materials for " .. spell .. " in the bags, which still gives skill")
                break
            end
        end
    end
    for _, warning in ipairs(route.warnings or {}) do
        if warning.code == "carriedShort" and not goalItems[warning.item] then add("the plan asks for more than the bags hold: " .. warning.text) end
    end
    if step and step.carried == 0 and step.row.kind ~= "goal" then
        add("Make is on " .. step.spell .. " with no materials for one")
    end
    if not step and (route.target or 0) > now.skill and #(route.runs or {}) > 0 then
        add("the plan goes to " .. route.target .. " and the Make button has nothing to make")
    end
end

-- One craft of a step: its reagents out of the bags, what it makes in, and
-- the skill after it, with the chance it went up (nil: no roll, a helper's
-- craft or no skill there).
local function craft(ns, input, now, step)
    local Planner, SkillUp = ns.modules.ProfessionPlanner, ns.Kit.SkillUp
    local recipe = step.recipe
    local after = { skill = now.skill, bags = {} }
    for item, count in pairs(now.bags) do after.bags[item] = count end
    for _, reagent in ipairs(recipe.reagents or {}) do
        after.bags[reagent[1]] = (after.bags[reagent[1]] or 0) - (reagent[2] or 1)
        if after.bags[reagent[1]] < 0 then return nil end
    end
    if recipe.makes then after.bags[recipe.makes] = (after.bags[recipe.makes] or 0) + ((recipe.made or {})[1] or 1) end
    if recipe.helper then return after, nil end
    local chance = SkillUp:Chance(Planner:Skills(input.book, step.spell, recipe), now.skill)
    if input.maxSkill and now.skill >= input.maxSkill then chance = 0 end
    return after, chance
end

-- A plan from `now`. Buying (not only what is carried), the player buys the
-- shopping list when the Make button's step needs it, into `now`'s bags.
local function plan(ns, snapshot, now)
    local input = assert(Snapshot.Input(ns, withState(snapshot, now)))
    local route = ns.modules.ProfessionPlanner:Plan(input)
    local step = makeStep(ns, input, route, now)
    if step and step.carried == 0 and route.materials ~= "carried" then
        for _, shop in ipairs(route.shopping or {}) do
            if (shop.buy or 0) > 0 then now.bags[shop.itemID] = (now.bags[shop.itemID] or 0) + shop.buy end
        end
        step = makeStep(ns, input, route, now)
    end
    return input, route, step
end

-- The exact odds of the skill following the plan ends at: { [skill] = chance },
-- the expected skill, how many plans it took, and the problems met.
function Playthrough.Exact(ns, snapshot, options)
    options = options or {}
    local memo, problems, plans, seen = {}, {}, 0, {}
    local function from(now, batch, depth)
        local id = key(now, batch)
        if memo[id] then return memo[id] end
        if depth > 400 then error("playthrough runs away at " .. id) end
        local input, step
        if not batch or batch.left <= 0 then
            local route
            input, route, step = plan(ns, snapshot, now)
            plans = plans + 1
            if not seen[id] then
                seen[id] = true
                check(route, now, step, problems, id, ns, input)
            end
            if not step or step.count <= 0 or step.carried == 0 then
                memo[id] = { [now.skill] = 1 }
                return memo[id]
            end
            batch = { spell = step.spell, step = step, input = input, left = options.single and 1 or step.count }
        end
        local after, chance = craft(ns, batch.input, now, batch.step)
        local odds = {}
        if not after then
            table.insert(problems, id .. ": crafting " .. batch.spell .. " ran out of a reagent mid-batch")
            odds[now.skill] = 1
        else
            local rest = { spell = batch.spell, step = batch.step, input = batch.input, left = batch.left - 1 }
            local function add(share, result)
                for skill, part in pairs(result) do odds[skill] = (odds[skill] or 0) + share * part end
            end
            if chance and chance > 0 then
                add(chance, from({ skill = after.skill + 1, bags = after.bags }, rest, depth + 1))
                if chance < 1 then add(1 - chance, from(after, rest, depth + 1)) end
            else
                add(1, from(after, rest, depth + 1))
            end
        end
        memo[id] = odds
        return odds
    end
    local odds = from(state(snapshot), nil, 0)
    local expected = 0
    for skill, share in pairs(odds) do expected = expected + skill * share end
    return { odds = odds, expected = expected, plans = plans, problems = problems }
end

-- One path, rolled with a seeded generator; `print` gets each press.
function Playthrough.Sample(ns, snapshot, seed, print, options)
    options = options or {}
    local rolls = seed or 1
    local function roll()
        rolls = (rolls * 1103515245 + 12345) % 2147483648
        return rolls / 2147483648
    end
    local now, problems = state(snapshot), {}
    for press = 1, 200 do
        local input, route, step = plan(ns, snapshot, now)
        check(route, now, step, problems, "press " .. press, ns, input)
        if print then
            print(string.format("skill %d  plan: %s  (to %s)", now.skill, Snapshot.Describe(route.runs), tostring(route.target)))
        end
        if not step or step.count <= 0 or step.carried == 0 then break end
        local made, ups = 0, 0
        for _ = 1, options.single and 1 or step.count do
            local after, chance = craft(ns, input, now, step)
            if not after then
                table.insert(problems, "press " .. press .. ": ran out of a reagent mid-batch")
                break
            end
            if chance and roll() < chance then
                after.skill = after.skill + 1
                ups = ups + 1
            end
            now, made = after, made + 1
        end
        if print then
            print(string.format("  Make %s x%d%s -> %d skill-up%s", step.spell, made,
                step.count < step.wanted and (" (of " .. step.wanted .. ", the bags make " .. step.count .. ")") or "",
                ups, ups == 1 and "" or "s"))
        end
    end
    return now.skill, problems
end

return Playthrough
