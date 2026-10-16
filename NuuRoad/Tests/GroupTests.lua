local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()
Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
local GuideCheck, Steps, Progress = ns.modules.GuideCheck, ns.modules.Steps, ns.modules.Progress

local function compact(sections)
    return { kind = "guide", id = "test:groups", updated = 1789862400,
        title = "Groups", category = "test", data = { map = 1413, sections = sections } }
end
local source = compact({
    { title = "Visit", steps = {
        { type = "accept", quests = { 870 }, npc = { 3448 } },
        { group = {
            { type = "accept", quests = { 869 }, npc = { 3464 } },
            { type = "talk", turnin = { 871 }, accept = { 872 }, npc = { 3429 }, cond = { class = "WARRIOR" } },
            { type = "accept", quests = { 844 }, npc = { 3338 } },
        } },
        { group = { { type = "accept", quests = { 867 } }, { type = "accept", quests = { 848 } } } },
        { type = "choice", text = "Continue?", options = { { text = "Done", go = "end" } } },
        { type = "finish", note = "Done", label = "end" },
    } },
})
local guide = Steps:Expand(source)
local ok, errors = GuideCheck:Validate(guide)
assert(ok, table.concat(errors, "; "))
assert(#guide.nodes == 8 and #guide.groups == 2)
assert(guide.groups[1].first == 2 and guide.groups[1].last == 4)
assert(guide.groups[2].first == 5 and guide.groups[2].last == 6)
assert(guide.nodes[7].choices[1]["next"] == 8, "a label resolves to the flattened index")
for index, node in ipairs(guide.nodes) do
    assert(node.id == nil and node.index == index)
    assert(guide.sections[1].nodeIndexes[index] == index)
end
assert(source.data.sections[1].steps[2].group[1].index == nil, "source steps are not annotated")
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
for index = 1, 12 do visits[index] = { type = "accept", quests = { 800 + index } } end
local function oneSection(steps) return compact({ { title = "Visit", steps = steps } }) end
local large = Steps:Expand(oneSection({ { group = visits } }))
assert(#Progress:QuestGroup(large, large.nodes[1]) == 12, "no eight-step limit")

local camp = Steps:Expand(oneSection({ { group = {
    { type = "kill", kill = { 3265 }, count = 3 },
    { type = "kill", kill = { 3267 }, quest = { 871, 1 } },
    { type = "collect", item = 5087, count = 7, kill = { 3244 } },
    { type = "accept", quests = { 870 }, npc = { 3448 } },
} } }))
assert(GuideCheck:Validate(camp) and #camp.groups == 1, "kills, objectives, and collects can share a group")
assert(#Progress:QuestGroup(camp, camp.nodes[1]) == 4)

local accept870 = { type = "accept", quests = { 870 } }
local accept871 = { type = "accept", quests = { 871 } }
local invalid = {
    { { group = { { type = "kill", kill = { 3265 } }, { type = "travel", to = "Ratchet", at = { { 6200, 3700 } } } } },
        "group members are quest visits or quest objectives" },
    { { group = {} }, "a group holds two or more steps" },
    { { group = { accept870 } }, "a group holds two or more steps" },
    { { group = { accept870, { type = "note", note = "Not a visit" } } }, "group members are quest visits or quest objectives" },
    { { group = { accept870, { title = "Break", steps = {} } } }, "unknown step type 'nil'" },
    { { group = { accept870, { group = visits } } }, "groups do not nest" },
    { { group = { accept870, accept871 }, id = "unnecessary" }, "steps[1].id: is not a field of a group" },
    { { group = { [1] = accept870, [3] = accept871 } }, "a group holds two or more steps" },
}
for _, case in ipairs(invalid) do
    local fine, message = pcall(Steps.Expand, Steps, oneSection({ case[1] }))
    assert(not fine and tostring(message):find(case[2], 1, true), "invalid wrappers are rejected: " .. tostring(message))
end
-- A guide source has no authored positions: a step carries no edge or ID of its own (an
-- unknown field is not read), a branch goes to a label, and two things
-- cannot share one label.
local plain = Steps:Expand(oneSection({ { type = "accept", quests = { 870 }, id = "old", ["next"] = 5 } }))
assert(plain.nodes[1].id == nil and plain.nodes[1]["next"] == nil and GuideCheck:Validate(plain))
assert(not pcall(Steps.Expand, Steps, oneSection({
    { type = "choice", text = "?", options = { { text = "Go", go = 2 } } }, { type = "finish", note = "." } })))
assert(not pcall(Steps.Expand, Steps, oneSection({ { type = "choice", text = "?", options = { { text = "Go", go = "nowhere" } } } })))
assert(not pcall(Steps.Expand, Steps, oneSection({
    { type = "accept", quests = { 870 }, label = "one" }, { type = "accept", quests = { 871 }, label = "one" } })))
assert(not pcall(Steps.Expand, Steps, compact({ accept870 })), "steps live in sections")
assert(not pcall(Steps.Expand, Steps, compact({ { title = "Empty", steps = {} } })), "a section needs steps")
-- A section may carry a map for its whole span, and a label of its own.
local mapped = Steps:Expand(compact({
    { title = "Barrens", steps = { { type = "accept", quests = { 870 }, at = { { 5226, 3193 } }, label = "back" } } },
    { title = "Orgrimmar", map = 1454, steps = {
        { type = "accept", quests = { 1061 }, at = { { 3893, 3838 } } },
        { type = "travel", to = "Thunder Bluff", at = { { 4581, 6471, map = 1456 } } },
        { type = "choice", text = "Back?", options = { { text = "Return", go = "back" } } },
    } },
}))
assert(mapped.nodes[1].location.mapID == 1413 and mapped.nodes[2].location.mapID == 1454, "a section map covers its span")
assert(mapped.nodes[3].location.mapID == 1456, "one point can name its own map")
assert(mapped.nodes[4].choices[1]["next"] == 1, "a label can point backwards")
assert(#mapped.sections == 2 and mapped.sections[2].title == "Orgrimmar")
local function invalidRanges(ranges)
    local candidate = Steps:Expand(source)
    candidate.groups = ranges
    assert(not GuideCheck:Validate(candidate), "invalid ranges are rejected")
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
assert(not GuideCheck:Validate(split), "groups cannot cross sections")
local branch = Steps:Expand(source)
branch.nodes[7].choices[1]["next"] = "8"
assert(not GuideCheck:Validate(branch), "branch indexes must be numbers")

return true
