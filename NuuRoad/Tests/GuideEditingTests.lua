local ns = { modules = {}, db = { account = { guides = {}, nextUserGuideNumber = 0 } } }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()
for _, file in ipairs({ "Data/Schema.lua", "Data/Names.lua", "Data/Steps.lua",
    "Domain/GuideRepository.lua", "Domain/GuideEditing.lua", "Domain/Progress.lua", "UI/Editor.lua" }) do Load(ns, file) end
local Schema, Editing, Repository, Progress = ns.modules.Schema, ns.modules.GuideEditing, ns.modules.GuideRepository, ns.modules.Progress
local function fresh()
    return ns.modules.Steps:Expand({ schema = 2, id = "test:edit", updated = 1789862400,
        meta = { title = "Edit", category = "test" }, steps = {
            { section = "Edit", steps = {
                { group = { { accept = 870, label = "start" }, { accept = 871 }, { turnin = 844 } } },
                { choice = "Choose", options = { { "Start", goto = "start" }, { "Finish", goto = "end" } } },
                { finish = "Done", label = "end" },
            } },
        } })
end
local function valid(guide)
    local ok, errors = Schema:Validate(guide)
    assert(ok, table.concat(errors, "; "))
    for index, node in ipairs(guide.nodes) do assert(node.index == index) end
end
local guide = fresh()
Editing:Insert(guide, 1)
valid(guide)
assert(guide.nodes[2].kind == "action")
assert(#guide.groups == 1 and guide.groups[1].first == 3 and guide.groups[1].last == 4,
    "inserting standalone work splits a group, dropping singleton ranges")
assert(guide.nodes[5].choices[2]["next"] == 6, "insertion adjusts branch targets")
assert(#guide.sections[1].nodeIndexes == 6)
assert(Editing:Delete(guide, 2))
valid(guide)
assert(guide.groups[1].first == 2 and guide.groups[1].last == 3)
assert(guide.nodes[4].choices[2]["next"] == 5)
assert(Editing:GroupNext(guide, 1))
assert(#guide.groups == 1 and guide.groups[1].first == 1 and guide.groups[1].last == 3)
assert(not Editing:GroupNext(guide, 1), "a group cannot absorb a choice")
assert(not Editing:Move(guide, 3, 1), "moving across group boundaries requires ungrouping")
assert(Editing:Move(guide, 1, 1))
valid(guide)
assert(guide.nodes[4].choices[1]["next"] == 2, "moving a target preserves the branch destination")
assert(Editing:Delete(guide, 2))
valid(guide)
assert(#guide.nodes[3].choices == 1, "deleting a target removes its choice")
assert(guide.groups[1].first == 1 and guide.groups[1].last == 2)
assert(Editing:Ungroup(guide, 2) and #guide.groups == 0)
assert(not Editing:Ungroup(guide, 2))

guide = fresh()
guide.nodes[5]["next"] = 2
assert(Editing:Delete(guide, 2))
assert(guide.nodes[4]["next"] == 2, "direct edges to deleted steps follow their successor")
valid(guide)
Editing:Insert(guide, 4)
assert(guide.nodes[4]["next"] == 5 and guide.nodes[5]["next"] == 2,
    "inserting after an explicit edge wires the new step into the flow")
valid(guide)

guide = fresh()
assert(Repository:SaveUserGuide(guide))
Progress.store, Progress.session = {}, {}
Progress:Select(guide)
Progress:GoTo(guide, 3)
Progress:RecordKill(guide, 3)
assert(Editing:Delete(guide, 3))
assert(Repository:SaveUserGuide(guide))
assert(Progress:PeekState(guide) == nil and guide.updated > 1789862400, "saving invalidates positional progress and restamps the guide")
Progress:Select(guide)
assert(Progress:GetCurrentIndex(guide) == 1 and Progress:KillCount(guide, 3) == 0)

-- Applying an unchanged quest kill objective must not turn it into a kill counter.
local node = ns.modules.Steps:Expand({ schema = 2, id = "t", updated = 1, meta = { title = "t", category = "test" },
    steps = { { section = "s", steps = { { objective = 871, part = 1, kill = 3267, count = 8 } } } } }).nodes[1]
ns.modules.Editor:ApplyNPCs(node, { 3267 }, nil)
assert(node.auto.verb == "objective" and node.completion.observed.type == "objective")

return true
