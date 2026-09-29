-- Tools/SessionLog/plan_snapshot.lua
-- A Profession Planner plan as read in the game, made plannable outside it.
-- A snapshot is plain data:
--
--   profession, skill, maxSkill, level, fullScope   the live reads
--   inputs     the planner's saved inputs (target, options, chosen, ...)
--   known      { spell, ... } the recipes known, as resolved
--   helpers    { [profession] = { spell, ... } } other professions' recipes it could use
--   bags       { { itemID, count }, ... } the bags, as the plan reads them
--   book       the price book (NuuProfessionsDB.professions)
--   expect     the route the game planned, "spell:from-to xcount  ..." (fixtures)
--
-- Used by replay_plan.lua (from a trace row) and Tests/PlannerFixtureTests.lua
-- (from Tests/Fixtures/Planner/*.lua). Expects ns with the planner and
-- ns.professionData loaded.
local Snapshot = {}

-- The data as the game built it (Planner:WithHelpers): the profession's own
-- recipes and each helper recipe the plan could use.
function Snapshot.Data(ns, snapshot)
    local Planner = ns.modules.ProfessionPlanner
    local base = ns.professionData[Planner:DataKey(snapshot.profession)]
    if not base then return nil end
    local helpers = snapshot.helpers or {}
    if not next(helpers) then return base end
    local data = { recipes = {}, items = {}, helpers = helpers }
    for key, value in pairs(base) do if key ~= "recipes" and key ~= "items" then data[key] = value end end
    for key, value in pairs(base.recipes) do data.recipes[key] = value end
    for key, value in pairs(base.items or {}) do data.items[key] = value end
    for name, spells in pairs(helpers) do
        local own = ns.professionData[Planner:DataKey(name)]
        for _, spell in ipairs(spells) do
            local recipe = own and own.recipes[spell]
            if recipe then
                local merged = { helper = name }
                for key, value in pairs(recipe) do merged[key] = value end
                data.recipes[spell] = merged
            end
        end
        for key, value in pairs(own and own.items or {}) do
            if data.items[key] == nil then data.items[key] = value end
        end
    end
    return data
end

function Snapshot.Input(ns, snapshot)
    local Planner = ns.modules.ProfessionPlanner
    local data = Snapshot.Data(ns, snapshot)
    if not data then return nil, "no recipe data for " .. tostring(snapshot.profession) end
    local known, bags = {}, {}
    for _, spell in ipairs(snapshot.known or {}) do known[spell] = true end
    for _, row in ipairs(snapshot.bags or {}) do bags[row[1]] = row[2] end
    return Planner:MakeInput(snapshot.profession, data, snapshot.inputs, {
        skill = snapshot.skill, maxSkill = snapshot.maxSkill, level = snapshot.level, fullScope = snapshot.fullScope,
        known = known, bags = function(item) return bags[item] or 0 end, book = snapshot.book,
    })
end

-- The materials of the input's goals and of the parts made for them. A
-- goal is the player's to ask for: its shortfall is told (the carriedShort
-- warning, a row to get), not cut, so checks leave these out.
function Snapshot.GoalItems(input)
    local items = {}
    for _, goal in ipairs(input.goals or {}) do
        local recipe = input.data.recipes[goal.spell]
        for _, reagent in ipairs(recipe and recipe.reagents or {}) do
            items[reagent[1]] = true
            for _, maker in pairs(input.data.recipes) do
                if maker.makes == reagent[1] then
                    for _, part in ipairs(maker.reagents or {}) do items[part[1]] = true end
                end
            end
        end
    end
    return items
end

-- The runs of a route, as `expect` holds them.
function Snapshot.Describe(runs)
    local out = {}
    for _, run in ipairs(runs or {}) do
        table.insert(out, string.format("%s:%s-%s x%s", run.spell, run.fromSkill, run.toSkill, run.count))
    end
    return table.concat(out, "  ")
end

-- A value as Lua source, keys sorted, for a fixture file.
function Snapshot.Serialize(value, indent)
    indent = indent or ""
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind ~= "table" then return tostring(value) end
    local keys, list = {}, #value
    for key in pairs(value) do
        if not (type(key) == "number" and key >= 1 and key <= list and key % 1 == 0) then table.insert(keys, key) end
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    local inner, parts, flat = indent .. "    ", {}, true
    for _, item in pairs(value) do if type(item) == "table" then flat = false end end
    for index = 1, list do table.insert(parts, Snapshot.Serialize(value[index], inner)) end
    for _, key in ipairs(keys) do
        local name = (type(key) == "string" and key:match("^[%a_][%w_]*$")) and key
            or ("[" .. Snapshot.Serialize(key) .. "]")
        table.insert(parts, name .. " = " .. Snapshot.Serialize(value[key], inner))
    end
    if #parts == 0 then return "{}" end
    -- Plain values on one line; a table of tables a row each.
    if flat then return "{ " .. table.concat(parts, ", ") .. " }" end
    return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
end

return Snapshot
