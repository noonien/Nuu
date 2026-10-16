-- Build-time guide check, not shipped behaviour: finds quest work that looks
-- like one stop but is authored as separate steps. Run from the addon root:
--
--   lua Tools/CheckGroups.lua [Data/Guides/<Guide>.lua ...] [--near 3] [--near-npc 1]
--
-- With no files it reads every guide in Data/Guides.
--
-- Two kinds of stop are checked, each against its own kind only:
--
--   * Work: kill, loot, pick up, click, and objective steps. Next to one
--     another in a section (with only notes between them) and not in one
--     group, they are reported when a point of one is within `--near` map
--     percent of a point of the other, when they name the same creature or
--     item, or when one's note names the other's target ("killing Highlands
--     Bandits on the way").
--   * Visits: accepts, turn-ins and talks. They are reported when they name
--     the same NPC, or when the NPCs stand within `--near-npc` map percent
--     of each other - tighter than `--near`, since every NPC of a town is
--     within a few percent of the rest. A visit that turns in the quest the
--     one before it accepted is left out: the player does them in that order
--     anyway, group or not.
--
-- The guide itself never groups by distance (docs/guide-source.md): a report
-- is a candidate for an author to read, not a verdict. Two camps that happen
-- to sit close, or a boss the player should kill only after clearing the way,
-- can stay apart; record such a choice in the guide's header comment.
_G = _G or _ENV
-- The addon's files take (addon name, ns), as the client runs them.
dofile("Tests/Support/Namespace.lua")
local ns = NewNamespace()
Load(ns, "Data/GuideCheck.lua"); Load(ns, "Data/Names.lua"); Load(ns, "Data/Steps.lua")
Load(ns, "Data/IDNames.lua")
ns.packagedGuides, ns.builtInGuides = {}, {}
local Names, Steps = ns.modules.Names, ns.modules.Steps

local files, near, nearNPC = {}, 3, 1
local index = 1
while arg[index] do
    if arg[index] == "--near" then
        near = tonumber(arg[index + 1]) or near
        index = index + 1
    elseif arg[index] == "--near-npc" then
        nearNPC = tonumber(arg[index + 1]) or nearNPC
        index = index + 1
    else
        table.insert(files, arg[index])
    end
    index = index + 1
end
if #files == 0 then
    local listing = io.popen('ls Data/Guides/*.lua')
    for path in listing:lines() do table.insert(files, path) end
    listing:close()
end
for _, path in ipairs(files) do Load(ns, path) end
for _, guide in ipairs(ns.packagedGuides) do ns.builtInGuides[guide.id] = guide end

local sorts = { kill = "work", collect = "work", interact = "work", questObjective = "work",
    acceptQuest = "visit", turnInQuest = "visit", talk = "visit" }

-- A group is work when it holds any; a group of quest visits is a visit.
local function sortOf(unit)
    for _, node in ipairs(unit) do
        if sorts[node.kind] == "work" then return "work" end
    end
    return "visit"
end

local function points(node)
    local location, found = node.location, {}
    if not location or not location.x then return found end
    table.insert(found, { x = location.x, y = location.y })
    for _, spot in ipairs(location.spots or {}) do table.insert(found, spot) end
    return found
end

-- The creatures and items a node is about, by ID and by name.
local function targets(node)
    local found = {}
    local auto, refs = node.auto or {}, node.refs or {}
    for _, id in ipairs(auto.kill or refs.npcs or {}) do found["npc" .. id] = Names:NPC(id) end
    for _, id in ipairs(auto.loot or auto.items or refs.items or {}) do found["item" .. id] = Names:Item(id) end
    return found
end

local function mentions(text, name)
    if not text or not name then return false end
    text, name = text:lower(), name:lower()
    -- "Highlands Bandits" names a Highlands Bandit.
    return text:find(name, 1, true) ~= nil
end

-- The factions, classes or races a condition allows, or nil when it does
-- not narrow that kind down.
local function allowed(condition, kind)
    if type(condition) ~= "table" then return nil end
    if condition.type == kind then
        local set = {}
        for _, value in ipairs(condition.values or {}) do set[value] = true end
        return set
    elseif condition.type == "all" then
        local result
        for _, child in ipairs(condition.children or {}) do
            local set = allowed(child, kind)
            if set and result then
                for value in pairs(result) do
                    if not set[value] then result[value] = nil end
                end
            elseif set then
                result = set
            end
        end
        return result
    elseif condition.type == "any" then
        local result = {}
        for _, child in ipairs(condition.children or {}) do
            local set = allowed(child, kind)
            if not set then return nil end
            for value in pairs(set) do result[value] = true end
        end
        return result
    end
    return nil
end

-- The quests a visit accepts or turns in, as a set.
local function quests(node, verb)
    local auto, found = node.auto or {}, {}
    for _, id in ipairs(auto[verb] or (auto.verb == verb and auto.quests) or {}) do found[id] = true end
    return found
end

-- Whether the right visit hands in a quest the left one took.
local function chained(left, right)
    local accepted = quests(left, "accept")
    for id in pairs(quests(right, "turnin")) do
        if accepted[id] then return true end
    end
    return false
end

-- Whether no character sees both steps: the Horde and Alliance halves of one
-- visit, or two class variants of a trainer stop.
local function exclusive(left, right)
    for _, kind in ipairs({ "faction", "class", "race" }) do
        local a, b = allowed(left.condition, kind), allowed(right.condition, kind)
        if a and b then
            local shared = false
            for value in pairs(a) do
                if b[value] then shared = true end
            end
            if not shared then return true end
        end
    end
    return false
end

-- Why two units read as one stop, or nil.
local function reasons(a, b)
    local sort = sortOf(a)
    if sortOf(b) ~= sort then return nil end
    local visit = sort == "visit"
    local why = {}
    local closest
    for _, left in ipairs(a) do
        for _, right in ipairs(b) do
            if not exclusive(left, right) and not (visit and chained(left, right)) then
                if (left.location or {}).mapID == (right.location or {}).mapID then
                    for _, p in ipairs(points(left)) do
                        for _, q in ipairs(points(right)) do
                            local distance = math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2) * 100
                            if not closest or distance < closest then closest = distance end
                        end
                    end
                end
                local leftTargets, rightTargets = targets(left), targets(right)
                for key, name in pairs(leftTargets) do
                    if rightTargets[key] then table.insert(why, "both name " .. tostring(name)) end
                    if not visit and mentions(right.body, name) then
                        table.insert(why, "step " .. right.index .. "'s note names " .. name)
                    end
                end
                for _, name in pairs(rightTargets) do
                    if not visit and mentions(left.body, name) then
                        table.insert(why, "step " .. left.index .. "'s note names " .. name)
                    end
                end
            end
        end
    end
    if closest and closest <= (visit and nearNPC or near) then table.insert(why, 1, string.format("%.1f%% apart", closest)) end
    if #why == 0 then return nil end
    local seen, unique = {}, {}
    for _, reason in ipairs(why) do
        if not seen[reason] then seen[reason] = true; table.insert(unique, reason) end
    end
    return table.concat(unique, ", ")
end

local ids = {}
for id in pairs(ns.builtInGuides) do table.insert(ids, id) end
table.sort(ids)

local total = 0
for _, id in ipairs(ids) do
    local ok, guide = pcall(Steps.Expand, Steps, ns.builtInGuides[id])
    if not ok then
        print("== " .. id .. ": does not load: " .. tostring(guide))
    else
        local groupOf = {}
        for number, range in ipairs(guide.groups or {}) do
            for at = range.first, range.last do groupOf[at] = number end
        end
        local reports = {}
        for _, section in ipairs(guide.sections) do
            -- The section as units: a group, or one work or visit step. A note sits
            -- between units without breaking the run; anything else does.
            local units, run = {}, {}
            local function flush()
                if #run > 1 then table.insert(units, run) end
                run = {}
            end
            local last
            for _, at in ipairs(section.nodeIndexes) do
                local node = guide.nodes[at]
                if groupOf[at] then
                    if last and last.group == groupOf[at] then
                        table.insert(last, node)
                    else
                        last = { node, group = groupOf[at] }
                        table.insert(run, last)
                    end
                elseif sorts[node.kind] then
                    last = { node }
                    table.insert(run, last)
                elseif node.kind ~= "note" then
                    flush()
                    last = nil
                end
            end
            flush()
            for _, list in ipairs(units) do
                local cluster
                for position = 2, #list do
                    local why = reasons(list[position - 1], list[position])
                    if why then
                        if not cluster then
                            cluster = { units = { list[position - 1] }, why = {} }
                            table.insert(reports, cluster)
                        end
                        table.insert(cluster.units, list[position])
                        table.insert(cluster.why, why)
                    else
                        cluster = nil
                    end
                end
            end
        end
        if #reports > 0 then
            print("== " .. id)
            for _, cluster in ipairs(reports) do
                total = total + 1
                local first, lastUnit = cluster.units[1], cluster.units[#cluster.units]
                print(string.format("  steps %d-%d could be one group:", first[1].index, lastUnit[#lastUnit].index))
                for _, unit in ipairs(cluster.units) do
                    for _, node in ipairs(unit) do
                        local mark = unit.group and ("group " .. unit.group) or ""
                        print(string.format("    %4d %-50s %s", node.index, node.title or node.kind, mark))
                    end
                end
                for _, why in ipairs(cluster.why) do print("      - " .. why) end
            end
        end
    end
end
print(total .. " candidate" .. (total == 1 and "" or "s"))
