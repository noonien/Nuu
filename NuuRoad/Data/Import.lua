local _, ns = ...

-- Guide export format 1 (docs/examples/guide-export.lua) in, an authored v2
-- guide (Data/Steps.lua) out. The export holds what the author decided and
-- nothing that can be worked out again; v2 is what Steps:Expand already turns
-- into a runtime guide, so a guide read here goes on through Expand and
-- Schema:Validate like any packaged guide. What v2 cannot say is given to it
-- in the fields Expand reads for this (`quest`, `from`, `mark`, `say`, a zone
-- or instance ID on a travel step), and what the export leaves to the client
-- - an objective's count, a quest's name - is asked of the client when the
-- step is shown.
--
-- The packaged guides (Data/Guides) register their values in
-- ns.packagedGuides; RegisterPackaged turns each into ns.builtInGuides[id].
--
-- How the format maps onto v2:
--   * Points are hundredths of a map percent: { 5226, 3193 } -> { 52.26, 31.93 }.
--     A radius is the same unit and becomes a map fraction (200 -> 0.02).
--   * `cond` becomes a predicate tree on the step. `show` (professions, the
--     realm answers) is wrapped in `now`: read when the guide reaches the
--     step, and the step is passed over if it does not hold. A section's and
--     a group's conditions are put on each of their steps.
--   * An `optional` turn-in is passed over unless one of its quests is ready
--     (`now` quest ... readyToTurnIn). An accept from an item, not carried,
--     is passed over unless the item is in the bags.
--   * Areas, flight nodes, and skills are IDs in the export and names in v2:
--     an area from the client where it answers, otherwise ns.idNames
--     (Data/IDNames.lua, written by Tools/IDNames.py).
--   * `npcs` becomes names.npcs, with the map the NPC is listed under put on
--     each of its points.
local Import = { format = 1 }

local function fail(path, message)
    error("NuuRoad: " .. path .. ": " .. message, 0)
end

local function list(value)
    if type(value) == "table" then return value end
    if value ~= nil then return { value } end
    return nil
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- { 5226, 3193, map = 1454 } -> { 52.26, 31.93, map = 1454 }. `map` stands
-- in for a point that names none, where the format says whose map it is on.
local function point(value, path, map)
    if type(value) ~= "table" or type(value[1]) ~= "number" or type(value[2]) ~= "number" then
        fail(path, "a point is { x, y }")
    end
    return { value[1] / 100, value[2] / 100, map = value.map or map }
end

local function points(value, path, map)
    if type(value) ~= "table" or #value == 0 then fail(path, "must be a list of points") end
    local out = {}
    for index, entry in ipairs(value) do out[index] = point(entry, path .. "[" .. index .. "]", map) end
    return out
end

-- Names for the IDs the client cannot be asked about by ID.
local function idName(kind, id, path)
    local names = ns.idNames and ns.idNames[kind]
    local name = names and names[id]
    if not name then fail(path, "no name for " .. kind .. " " .. tostring(id) .. " (Tools/IDNames.py)") end
    return name
end

local function areaName(id, path)
    if type(id) ~= "number" then fail(path, "an area is an AreaTable ID") end
    local Client = ns.modules and ns.modules.Client
    local live = Client and Client.GetAreaName and Client:GetAreaName(id)
    return live or idName("areas", id, path)
end

local function skillName(id, path)
    if type(id) ~= "number" then fail(path, "a skill is a SkillLine ID") end
    return idName("skills", id, path)
end

-- CONDITIONS

local function values(value, path)
    if type(value) == "string" then return { value } end
    if type(value) == "table" and #value > 0 then return value end
    fail(path, "must be a token or a list of them")
end

local function combine(kind, parts)
    if #parts == 0 then return nil end
    if #parts == 1 then return parts[1] end
    return { type = kind, children = parts }
end

-- A condition table -> a predicate, and whether it asks anything `show` asks
-- (a profession, a realm answer), which makes it a `now` term.
local predicate
local function predicates(entries, conds, path, seen)
    if type(entries) ~= "table" or #entries == 0 then fail(path, "must be a list of conditions") end
    local out, show = {}, false
    for index, entry in ipairs(entries) do
        local child, childShow = predicate(entry, conds, path .. "[" .. index .. "]", seen)
        table.insert(out, child)
        show = show or childShow
    end
    return out, show
end

predicate = function(condition, conds, path, seen)
    if type(condition) ~= "table" then fail(path, "a condition is a table") end
    local parts, show = {}, false
    for _, key in ipairs(sortedKeys(condition)) do
        local value, at = condition[key], path .. "." .. tostring(key)
        if key == "class" or key == "race" or key == "faction" then
            table.insert(parts, { type = key, values = values(value, at) })
        elseif key == "season" then
            table.insert(parts, value == true and { type = "season" } or { type = "season", id = value })
        elseif key == "hardcore" then
            table.insert(parts, { type = "hardcore" })
        elseif key == "skill" then
            local each = {}
            for index, id in ipairs(type(value) == "table" and value or { value }) do
                table.insert(each, { type = "profession", name = skillName(id, at .. "[" .. index .. "]") })
            end
            table.insert(parts, combine("any", each))
            show = true
        elseif key == "ah" then
            table.insert(parts, { type = "auctionHouse" })
            show = true
        elseif key == "selffound" then
            table.insert(parts, { type = "selfFound" })
            show = true
        elseif key == "any" or key == "all" then
            local children, childShow = predicates(value, conds, at, seen)
            table.insert(parts, combine(key, children))
            show = show or childShow
        elseif key == "none" then
            local children, childShow = predicates(value, conds, at, seen)
            table.insert(parts, { type = "not", child = combine("any", children) })
            show = show or childShow
        elseif key == "is" then
            local named = conds and conds[value]
            if named == nil then fail(at, "no condition named '" .. tostring(value) .. "' in data.conds") end
            if seen[value] then fail(at, "condition '" .. value .. "' names itself") end
            seen[value] = true
            local child, childShow = predicate(named, conds, "data.conds." .. value, seen)
            seen[value] = nil
            table.insert(parts, child)
            show = show or childShow
        else
            fail(at, "is not a condition")
        end
    end
    if #parts == 0 then fail(path, "an empty condition") end
    return combine("all", parts), show
end

-- The predicates a wrapper's `cond` and `show` put on everything inside it.
local function conditions(source, conds, path)
    local out = {}
    for _, field in ipairs({ "cond", "show" }) do
        if source[field] ~= nil then
            local tree, show = predicate(source[field], conds, path .. "." .. field, {})
            if show or field == "show" then tree = { type = "now", child = tree } end
            table.insert(out, tree)
        end
    end
    return out
end

local function append(target, source)
    local out = {}
    for _, entry in ipairs(target) do table.insert(out, entry) end
    for _, entry in ipairs(source) do table.insert(out, entry) end
    return out
end

-- STEPS

local function questPair(quest)
    return type(quest) == "table" and type(quest[1]) == "number" and type(quest[2]) == "number"
end

local vendorActions = { [1] = "sell", [2] = "repair", [3] = "sell and repair" }

-- The fields any step may carry, onto the v2 step.
local function common(step, out, path, conds, inherited)
    out.note = out.note == nil and step.note or out.note
    out.label = step.label
    out.npc = step.npc
    out.object = out.object or step.object
    if step.at ~= nil and step.stand ~= nil then fail(path, "a step has `at` or `stand`, not both") end
    if step.at ~= nil then out.at = points(step.at, path .. ".at") end
    if step.stand ~= nil then out.at = step.stand end
    if step.radius ~= nil then out.radius = step.radius / 10000 end
    out.loop, out.near, out.wait, out.use = step.loop, step.near, step.wait, step.use
    if type(step.item) == "table" then out.item = step.item end
    out.with, out.sticky, out.from = step.with, step.sticky, step.from
    out.mark, out.say = step.mark, step.say
    if step.upto ~= nil then
        if type(step.upto) ~= "table" then fail(path .. ".upto", "is { skill, rank }") end
        out.upto = { skillName(step.upto.skill, path .. ".upto.skill"), step.upto.rank }
    end
    if step.needs ~= nil then
        out.needs = {}
        for index, need in ipairs(step.needs) do
            if type(need) ~= "table" then fail(path .. ".needs[" .. index .. "]", "is { item, count, source }") end
            out.needs[index] = { need.item, need.count, need.source }
        end
    end
    local terms = append(inherited, conditions(step, conds, path))
    if step.optional then
        if step.type ~= "turnin" and step.type ~= "talk" then fail(path .. ".optional", "is for turn-ins") end
        local ready = {}
        for _, id in ipairs(step.quests or step.turnin or {}) do
            table.insert(ready, { type = "quest", id = id, state = "readyToTurnIn" })
        end
        if #ready == 0 then fail(path .. ".optional", "the step turns in no quest") end
        table.insert(terms, { type = "now", child = combine("any", ready) })
    end
    -- An accept from an item the player never looted passes: the rare that
    -- drops it was never met. Carried, it waits like any carried step.
    if step.type == "accept" and type(step.item) == "number" and step.npc == nil
        and not (step.sticky or step.with or step.from) then
        table.insert(terms, { type = "now", child = { type = "item", id = step.item } })
    end
    out.only = combine("all", terms)
    return out
end

local function needQuestPair(step, path)
    if not questPair(step.quest) then fail(path .. ".quest", "must be { quest, objective }") end
end

local converters = {}

function converters.note(step) return { note = step.note or "" } end

function converters.finish(step)
    -- The closing text is the step itself; `common` must not add it again.
    return { finish = step.note or "", note = false }
end

function converters.travel(step, path)
    local out = { travel = step.to or true }
    if step.zone ~= nil then out.zone = step.zone end
    if step.area ~= nil then out.subzone = areaName(step.area, path .. ".area") end
    if step.instance ~= nil then out.instance = step.instance end
    out.quest = step.quest
    return out
end

function converters.accept(step)
    return { accept = step.quests, item = type(step.item) == "number" and step.item or nil, kill = step.kill }
end

function converters.turnin(step) return { turnin = step.quests } end

function converters.talk(step, path)
    local turnin, accept = step.turnin, step.accept
    if turnin and accept then return { turnin = turnin, accept = accept } end
    if turnin then return { turnin = turnin } end
    if accept then return { accept = accept } end
    if step.quest == nil then return { talk = true } end
    needQuestPair(step, path)
    return { objective = step.quest[1], part = step.quest[2] }
end

function converters.escort(step, path)
    if step.npc == nil then fail(path .. ".npc", "an escort names the NPC escorted") end
    if questPair(step.quest) then return { escort = step.quest[1], quest = step.quest } end
    return { escort = step.quest }
end

function converters.collect(step)
    if questPair(step.quest) then
        return { objective = step.quest[1], part = step.quest[2], collect = step.item, kill = step.kill, count = step.count }
    end
    return { collect = step.item, count = step.count, starts = step.starts, quest = step.quest, kill = step.kill }
end

function converters.kill(step, path)
    if questPair(step.quest) then return { objective = step.quest[1], part = step.quest[2], kill = step.kill } end
    if type(step.quest) == "number" then return { objective = step.quest, kill = step.kill } end
    if step.kill == nil then fail(path .. ".kill", "a kill step names its creatures") end
    return { kill = step.kill }
end

function converters.interact(step, path)
    if questPair(step.quest) then return { objective = step.quest[1], part = step.quest[2] } end
    if type(step.quest) == "number" then return { objective = step.quest } end
    if step.object == nil then fail(path .. ".object", "an interact step names its object") end
    return {}
end

function converters.gather(step, path)
    return { gather = step.item, count = step.count, skill = step.skill and skillName(step.skill, path .. ".skill") }
end

function converters.craft(step, path)
    return { craft = step.item, count = step.count, skill = step.skill and skillName(step.skill, path .. ".skill") }
end

function converters.skillup(step, path)
    return { skillup = step.item, skill = skillName(step.skill, path .. ".skill"), rank = step.rank }
end

function converters.buy(step)
    return { buy = step.item, count = step.count, quest = step.quest }
end

function converters.vendor(step, path)
    local action = vendorActions[(step.sell and 1 or 0) + (step.repair and 2 or 0)]
    if not action then fail(path, "a vendor step sells, repairs, or both") end
    return { vendor = action }
end

function converters.equip(step) return { equip = step.item } end

function converters.train(step, path)
    return { train = skillName(step.skill, path .. ".skill"), rank = step.rank }
end

function converters.learn(step) return { learn = step.spells } end

function converters.cast(step) return { cast = step.spell, count = step.count } end

function converters.skill(step, path)
    return { skill = skillName(step.skill, path .. ".skill"), rank = step.rank }
end

function converters.reputation(step) return { reputation = step.faction, standing = step.standing } end

function converters.hearth(step, path) return { hearth = areaName(step.area, path .. ".area") } end

function converters.flight(step, path)
    if type(step.node) ~= "number" then fail(path .. ".node", "a flight step names its TaxiNodes ID") end
    return { flight = idName("taxiNodes", step.node, path .. ".node") }
end

function converters.level(step) return { level = step.level, xp = step.xp, by = step.by } end

function converters.choice(step, path)
    local options = {}
    for index, option in ipairs(step.options or {}) do
        if type(option) ~= "table" then fail(path .. ".options[" .. index .. "]", "is { text, go }") end
        options[index] = { option.text, goto = option.go }
    end
    return { choice = step.text, options = options }
end

local function convertStep(step, path, conds, inherited)
    if type(step) ~= "table" then fail(path, "a step is a table") end
    local convert = converters[step.type]
    if not convert then fail(path .. ".type", "unknown step type '" .. tostring(step.type) .. "'") end
    if type(step.quest) == "table" then needQuestPair(step, path) end
    local out = common(step, convert(step, path), path, conds, inherited)
    if out.note == false then out.note = nil end
    return out
end

-- PLACES AND NPCS

local function convertPlace(place, path)
    if type(place) ~= "table" then fail(path, "a place is a table") end
    local out = { place = place.id, name = place.name, width = place.width, map = place.map, points = {}, connections = {} }
    for index, entry in ipairs(place.points or {}) do
        local at = point(entry.at, path .. ".points[" .. index .. "].at")
        out.points[index] = { at = { at[1], at[2] }, map = at.map, kind = entry.kind, label = entry.label, id = entry.id }
    end
    for index, link in ipairs(place.links or {}) do
        out.connections[index] = { link.from, link.to, link.oneway and true or nil }
    end
    return out
end

-- "cave" (any point of the place) -> every point of it, for the arrow to take
-- the nearest; "cave.chamber" stays a reference.
local function placeSpots(places, reference, path)
    for _, place in ipairs(places or {}) do
        if place.place == reference then
            local spots = {}
            for _, entry in ipairs(place.points) do
                table.insert(spots, { entry.at[1], entry.at[2], map = entry.map or place.map })
            end
            return spots
        end
    end
    fail(path, "no place '" .. reference .. "'")
end

local function convertNPCs(npcs, places, guideMap)
    local out = {}
    if npcs == nil then return out end
    for _, map in ipairs(sortedKeys(npcs)) do
        local path = "data.npcs[" .. tostring(map) .. "]"
        if type(npcs[map]) ~= "table" then fail(path, "is { [id] = npc }") end
        for _, id in ipairs(sortedKeys(npcs[map])) do
            local entry, at = npcs[map][id], path .. "[" .. tostring(id) .. "]"
            local converted
            if type(entry) == "string" then
                converted = entry
            elseif type(entry) == "table" then
                converted = { entry.name, note = entry.note, instance = entry.instance }
                local where = entry.at
                local stamp = map ~= guideMap and map or nil
                if type(where) == "string" then
                    converted.at = where:find(".", 1, true) and where or placeSpots(places, where, at .. ".at")
                elseif type(where) == "table" and type(where[1]) == "table" then
                    converted.at = points(where, at .. ".at", stamp)
                elseif where ~= nil then
                    converted.at = point(where, at .. ".at", stamp)
                end
            else
                fail(at, "is a name or { name, at, note, instance }")
            end
            -- An NPC listed twice keeps the entry that says where it stands.
            if out[id] == nil or type(out[id]) == "string" then out[id] = converted end
        end
    end
    return out
end

-- THE GUIDE

function Import:ToAuthored(value)
    if type(value) ~= "table" or value.kind ~= "guide" then fail("guide", "is not a guide export") end
    if value.format ~= self.format then fail("guide.format", "must be " .. self.format) end
    local data = value.data
    if type(data) ~= "table" or type(data.sections) ~= "table" then fail("guide.data", "has no sections") end
    local conds = data.conds
    local levels = value.levels
    local guide = {
        schema = 2, id = value.id, updated = value.updated, map = data.map,
        meta = {
            title = value.title, author = value.author, category = value.category, tags = value.tags,
            levels = type(levels) == "table" and { levels.from, levels.to } or nil,
            source = value.source, materials = value.materials,
        },
        steps = {},
    }
    if value.cond ~= nil then
        guide.only = combine("all", conditions({ cond = value.cond }, conds, "guide"))
    end
    if data.places ~= nil then
        guide.places = {}
        for index, place in ipairs(data.places) do guide.places[index] = convertPlace(place, "data.places[" .. index .. "]") end
    end
    guide.names = { npcs = convertNPCs(data.npcs, guide.places, data.map) }
    for sectionIndex, section in ipairs(data.sections) do
        local path = "data.sections[" .. sectionIndex .. "]"
        if type(section) ~= "table" or type(section.steps) ~= "table" then fail(path, "is { title, steps }") end
        local inherited = conditions(section, conds, path)
        local out = { section = section.title, map = section.map, label = section.label, steps = {} }
        for stepIndex, entry in ipairs(section.steps) do
            local at = path .. ".steps[" .. stepIndex .. "]"
            if type(entry) == "table" and entry.group ~= nil then
                local groupTerms = append(inherited, conditions(entry, conds, at))
                local members = {}
                for memberIndex, member in ipairs(entry.group) do
                    members[memberIndex] = convertStep(member, at .. ".group[" .. memberIndex .. "]", conds, groupTerms)
                end
                table.insert(out.steps, { group = members, label = entry.label })
            else
                table.insert(out.steps, convertStep(entry, at, conds, inherited))
            end
        end
        table.insert(guide.steps, out)
    end
    return guide
end

-- Every value in ns.packagedGuides, as an authored guide in
-- ns.builtInGuides. A guide that cannot be read is reported and left out, as
-- one that fails validation is. Returns the problems, one line per guide.
function Import:RegisterPackaged()
    ns.builtInGuides = ns.builtInGuides or {}
    local problems = {}
    for _, value in ipairs(ns.packagedGuides or {}) do
        local ok, result = pcall(self.ToAuthored, self, value)
        local id = type(value) == "table" and value.id or "?"
        if ok then
            ns.builtInGuides[result.id] = result
        else
            table.insert(problems, "Packaged guide '" .. tostring(id) .. "' could not be read: " .. tostring(result))
        end
    end
    ns.packagedGuides = nil
    if ns.Print then
        for _, problem in ipairs(problems) do ns:Print(problem) end
    end
    return problems
end

ns:RegisterModule("GuideImport", Import)
