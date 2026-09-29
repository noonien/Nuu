local _, ns = ...

-- Structural edits remap numeric references before assigning new positions.
local Editing = {}

local function remap(guide, removed)
    local indexes = {}
    for index, node in ipairs(guide.nodes) do
        if node.index then indexes[node.index] = index end
    end
    for _, node in ipairs(guide.nodes) do
        local target = node["next"]
        if removed and target == removed.index then target = removed["next"] or removed.index + 1 end
        node["next"] = indexes[target]
        for index = #(node.choices or {}), 1, -1 do
            local choice = node.choices[index]
            choice["next"] = indexes[choice["next"]]
            if not choice["next"] then table.remove(node.choices, index) end
        end
        if node.choices and #node.choices == 0 then node.choices = nil end
        -- A level step's `by`: a step removed hands it to the one after.
        local observed = node.completion and node.completion.observed
        if observed and observed.type == "level" and observed.by then
            local by = observed.by
            if removed and by == removed.index then by = by + 1 end
            by = indexes[by]
            observed.by = by
            if node.auto and node.auto.verb == "level" then node.auto.by = by end
        end
    end
    for _, section in ipairs(guide.sections) do
        local members = {}
        for _, index in ipairs(section.nodeIndexes) do
            if indexes[index] then table.insert(members, indexes[index]) end
        end
        table.sort(members)
        section.nodeIndexes = members
    end
    local groups = {}
    for _, group in ipairs(guide.groups or {}) do
        local members = {}
        for index = group.first, group.last do
            if indexes[index] then table.insert(members, indexes[index]) end
        end
        table.sort(members)
        local first, last
        local function finish()
            if first and last > first then table.insert(groups, { first = first, last = last }) end
        end
        for _, index in ipairs(members) do
            if not last or index ~= last + 1 then finish(); first = index end
            last = index
        end
        finish()
    end
    guide.groups = groups
    ns.modules.Schema:IndexNodes(guide)
end

function Editing:Insert(guide, after)
    ns.modules.Schema:IndexNodes(guide)
    local section = guide.sections[1]
    for _, candidate in ipairs(guide.sections) do
        for _, index in ipairs(candidate.nodeIndexes) do
            if index == after then section = candidate end
        end
    end
    local current = guide.nodes[after]
    local node = { kind = "action", title = "New step", body = "", completion = { type = "manual" } }
    table.insert(guide.nodes, after + 1, node)
    remap(guide)
    table.insert(section.nodeIndexes, after + 1)
    table.sort(section.nodeIndexes)
    if current and current["next"] then node["next"], current["next"] = current["next"], after + 1 end
    return after + 1
end

function Editing:Delete(guide, index)
    if #guide.nodes <= 1 then return false, "A guide needs at least one step." end
    ns.modules.Schema:IndexNodes(guide)
    local removed = table.remove(guide.nodes, index)
    remap(guide, removed)
    return true
end

function Editing:Move(guide, index, direction)
    local target = index + direction
    if not guide.nodes[target] then return false, "Already at the edge of the guide." end
    local Schema = ns.modules.Schema
    if Schema:GroupAt(guide, index) ~= Schema:GroupAt(guide, target) then
        return false, "Ungroup these steps before moving across a group boundary."
    end
    Schema:IndexNodes(guide)
    guide.nodes[index], guide.nodes[target] = guide.nodes[target], guide.nodes[index]
    remap(guide)
    return true
end

function Editing:GroupNext(guide, index)
    local Schema = ns.modules.Schema
    local left = Schema:GroupAt(guide, index)
    local first, last = left and left.first or index, left and left.last or index
    local right = Schema:GroupAt(guide, last + 1)
    last = right and right.last or last + 1
    local candidate = { first = first, last = last }
    local groups = {}
    for _, group in ipairs(guide.groups or {}) do
        if group ~= left and group ~= right then table.insert(groups, group) end
    end
    table.insert(groups, candidate)
    table.sort(groups, function(a, b) return a.first < b.first end)
    local errors = {}
    Schema:ValidateGroups({ nodes = guide.nodes, sections = guide.sections, groups = groups }, errors)
    if #errors > 0 then return false, errors[1] end
    guide.groups = groups
    return true
end

function Editing:Ungroup(guide, index)
    local current = ns.modules.Schema:GroupAt(guide, index)
    for position, group in ipairs(guide.groups or {}) do
        if group == current then table.remove(guide.groups, position); return true end
    end
    return false, "This step is not grouped."
end

ns:RegisterModule("GuideEditing", Editing)
