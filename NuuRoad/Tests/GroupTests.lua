local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
local Schema, Steps, Progress = ns.modules.Schema, ns.modules.Steps, ns.modules.Progress

local function compact(steps)
    return { schema = 2, id = "test:groups", updated = 1789862400, map = 1413,
        meta = { title = "Groups", category = "test" }, steps = steps }
end
local source = compact({
    { section = "Visit", steps = {
        { accept = 870, npc = 3448 },
        { group = {
            { accept = 869, npc = 3464 },
            { turnin = 871, accept = 872, npc = 3429, only = "Warrior" },
            { accept = 844, npc = 3338 },
        } },
        { group = { { accept = 867 }, { accept = 848 } } },
        { choice = "Continue?", options = { { "Done", goto = "end" } } },
        { finish = "Done", label = "end" },
    } },
})
local guide = Steps:Expand(source)
local ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
assert(#guide.nodes == 8 and #guide.groups == 2)
assert(guide.groups[1].first == 2 and guide.groups[1].last == 4)
assert(guide.groups[2].first == 5 and guide.groups[2].last == 6)
assert(guide.nodes[7].choices[1]["next"] == 8, "a label resolves to the flattened index")
for index, node in ipairs(guide.nodes) do
    assert(node.id == nil and node.index == index)
    assert(guide.sections[1].nodeIndexes[index] == index)
end
assert(source.steps[1].steps[2].group[1].index == nil, "source steps are not annotated")
assert(#Steps:Expand(source).nodes == 8, "expansion can repeat")

Progress.store, Progress.session = {}, {}
ns.modules.Client = { MatchesCondition = function() return false end,
    GetMapWorldSize = function() error("membership must not depend on map APIs") end }
Progress:Select(guide)
assert(#Progress:QuestGroup(guide) == 1, "adjacent ungrouped quests stay standalone")
Progress:GoTo(guide, 2)
local group = Progress:QuestGroup(guide)
assert(#group == 2 and group[1].index == 2 and group[2].index == 4, "conditions filter members")
Progress:GoTo(guide, 4)
assert(#Progress:QuestGroup(guide) == 1, "entering partway uses only remaining members")
Progress:GoTo(guide, 5)
assert(#Progress:QuestGroup(guide) == 2, "adjacent groups do not merge")
ns.modules.Client.MatchesCondition = function() return true end
assert(#Progress:QuestGroup(guide, guide.nodes[2]) == 3)

local visits = {}
for index = 1, 12 do visits[index] = { accept = 800 + index } end
local function oneSection(steps) return compact({ { section = "Visit", steps = steps } }) end
local large = Steps:Expand(oneSection({ { group = visits } }))
assert(#Progress:QuestGroup(large, large.nodes[1]) == 12, "no eight-step limit")

local camp = Steps:Expand(oneSection({ { group = {
    { kill = 3265, count = 3 },
    { objective = 871, part = 1, kill = 3267, count = 8 },
    { collect = 5087, count = 7, kill = 3244 },
    { accept = 870, npc = 3448 },
} } }))
assert(Schema:Validate(camp) and #camp.groups == 1, "kills, objectives, and collects can share a group")
assert(#Progress:QuestGroup(camp, camp.nodes[1]) == 4)

local invalid = {
    { group = { { kill = 3265 }, { travel = "Ratchet", at = { 62.0, 37.0 } } } },
    { group = {} },
    { group = { { accept = 870 } } },
    { group = { { accept = 870 }, { note = "Not a visit" } } },
    { group = { { accept = 870 }, { section = "Break", steps = {} } } },
    { group = { { accept = 870 }, { group = visits } } },
    { group = { { accept = 870 }, { accept = 871, ["next"] = 1 } } },
    { group = { { accept = 870 }, { accept = 871 } }, id = "unnecessary" },
    { group = { [1] = { accept = 870 }, [3] = { accept = 871 } } },
}
for _, step in ipairs(invalid) do
    assert(not pcall(Steps.Expand, Steps, oneSection({ step })), "invalid wrappers are rejected")
end
assert(not pcall(Steps.Expand, Steps, oneSection({ { id = "old", accept = 870 } })))
-- v2 has no authored positions: a step cannot carry an edge of its own, a
-- branch goes to a label, and two things cannot share one label.
assert(not pcall(Steps.Expand, Steps, oneSection({ { accept = 870, ["next"] = 1 } })))
assert(not pcall(Steps.Expand, Steps, oneSection({ { choice = "?", options = { { "Go", goto = 2 } } }, { finish = "." } })))
assert(not pcall(Steps.Expand, Steps, oneSection({ { choice = "?", options = { { "Go", goto = "nowhere" } } } })))
assert(not pcall(Steps.Expand, Steps, oneSection({ { accept = 870, label = "one" }, { accept = 871, label = "one" } })))
assert(not pcall(Steps.Expand, Steps, compact({ { accept = 870 } })), "steps live in sections")
assert(not pcall(Steps.Expand, Steps, compact({ { section = "Empty", steps = {} } })), "a section needs steps")
-- A section may carry a map for its whole span, and a label of its own.
local mapped = Steps:Expand(compact({
    { section = "Barrens", steps = { { accept = 870, at = { 52.26, 31.93 }, label = "back" } } },
    { section = "Orgrimmar", map = 1454, steps = {
        { accept = 1061, at = { 38.93, 38.38 } },
        { travel = "Thunder Bluff", at = { 45.81, 64.71, map = 1456 } },
        { choice = "Back?", options = { { "Return", goto = "back" } } },
    } },
}))
assert(mapped.nodes[1].location.mapID == 1413 and mapped.nodes[2].location.mapID == 1454, "a section map covers its span")
assert(mapped.nodes[3].location.mapID == 1456, "one point can name its own map")
assert(mapped.nodes[4].choices[1]["next"] == 1, "a label can point backwards")
assert(#mapped.sections == 2 and mapped.sections[2].title == "Orgrimmar")
local function invalidRanges(ranges)
    local candidate = Steps:Expand(source)
    candidate.groups = ranges
    assert(not Schema:Validate(candidate), "invalid ranges are rejected")
end
invalidRanges({ { first = 2, last = 9 } })
invalidRanges({ { first = 2, last = 2 } })
invalidRanges({ { first = 2.5, last = 4 } })
invalidRanges({ { first = 2, last = 4 }, { first = 4, last = 6 } })
invalidRanges({ { first = 5, last = 7 } }) -- choice inside group
invalidRanges({ { first = 2, last = 4, id = "old" } })
local split = Steps:Expand(source)
split.sections = { { id = "a", title = "A", nodeIndexes = { 1, 2 } },
    { id = "b", title = "B", nodeIndexes = { 3, 4, 5, 6, 7, 8 } } }
assert(not Schema:Validate(split), "groups cannot cross sections")
local branch = Steps:Expand(source)
branch.nodes[7].choices[1]["next"] = "8"
assert(not Schema:Validate(branch), "branch indexes must be numbers")

return true
