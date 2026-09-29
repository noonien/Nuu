-- Tools/SessionLog/plan_orders.lua
-- The yardstick for a plan's order, kept apart from the planner's own code:
-- the crafts of a fixture's first plan (each run's count) in every distinct
-- order, each made straight through without replanning, with the exact odds
-- of the skill it ends at. Following the plan, replanning as the game does
-- (plan_playthrough.lua), should end at least as high as the best of them.
local Orders = {}

local Snapshot = dofile("Tools/SessionLog/plan_snapshot.lua")

-- The exact odds after making `crafts` ({ entry = { spell, skill levels }, ... }) in
-- order from `skill`, no point past `maxSkill`.
function Orders.Odds(ns, crafts, skill, maxSkill)
    local SkillUp = ns.Kit.SkillUp
    local odds = { [skill] = 1 }
    for _, craft in ipairs(crafts) do
        local after = {}
        for at, share in pairs(odds) do
            local chance = (maxSkill and at >= maxSkill) and 0 or SkillUp:Chance(craft.skills, at)
            after[at] = (after[at] or 0) + share * (1 - chance)
            after[at + 1] = (after[at + 1] or 0) + share * chance
        end
        odds = after
    end
    return odds
end

-- Every distinct order of the first plan's crafts, best first: { expected,
-- odds, text }. nil when there are more than `limit` (default 5000).
function Orders.All(ns, fixture, limit)
    local Planner = ns.modules.ProfessionPlanner
    local input = assert(Snapshot.Input(ns, fixture))
    local route = Planner:Plan(input)
    local kinds, counts = {}, {}
    for _, run in ipairs(route.runs) do
        if not counts[run.spell] then
            table.insert(kinds, { spell = run.spell, skills = Planner:Skills(input.book, run.spell, input.data.recipes[run.spell]) })
            counts[run.spell] = 0
        end
        counts[run.spell] = counts[run.spell] + run.count
    end
    if #kinds == 0 then return nil end
    local out, sequence, tooMany = {}, {}, false
    limit = limit or 5000
    local function walk()
        if tooMany then return end
        local left = false
        for _, kind in ipairs(kinds) do
            if counts[kind.spell] > 0 then
                left = true
                counts[kind.spell] = counts[kind.spell] - 1
                table.insert(sequence, kind)
                walk()
                table.remove(sequence)
                counts[kind.spell] = counts[kind.spell] + 1
            end
        end
        if not left then
            if #out >= limit then tooMany = true; return end
            local odds = Orders.Odds(ns, sequence, fixture.skill, fixture.maxSkill)
            local expected = 0
            for skill, share in pairs(odds) do expected = expected + skill * share end
            local parts, last, run = {}, nil, 0
            for index = 1, #sequence + 1 do
                local spell = sequence[index] and sequence[index].spell
                if spell ~= last and last then table.insert(parts, last .. " x" .. run); run = 0 end
                last, run = spell, run + 1
            end
            table.insert(out, { expected = expected, odds = odds, text = table.concat(parts, ", ") })
        end
    end
    walk()
    if tooMany then return nil end
    table.sort(out, function(a, b) return a.expected > b.expected end)
    return out
end

return Orders
