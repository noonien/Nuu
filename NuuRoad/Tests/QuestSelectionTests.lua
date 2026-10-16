_G = _G or _ENV
local ns = { modules = {}, db = { settings = { automation = { selectQuestInLog = true } } }, printed = {}, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log(message) table.insert(self.logs, message) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/QuestIndex.lua")
Load(ns, "Domain/QuestSelection.lua")
local Steps, QuestSelection = ns.modules.Steps, ns.modules.QuestSelection

local guide = Steps:Expand({
    kind = "guide", id = "test:selection", updated = 1789862400, title = "Selection", category = "test",
    data = { map = 1413, sections = {
    { title = "Steps", steps = {
        { type = "accept", quests = { 869 }, npc = { 3464 } },
        { type = "kill", quest = 869 },
        { type = "talk", turnin = { 869 }, accept = { 871 }, npc = { 3464 } },
        { type = "travel", to = "South road", at = { { 4400, 5900 } } },
        { type = "collect", item = 4926, starts = 819, object = "Chen's Empty Keg" },
    } },
} },
})
local nodes = guide.nodes

-- A quest the player is not on is never selected, however the step names it.
local function onNone() return false end
assert(QuestSelection:QuestForNode(nodes[1], onNone) == nil)

-- An accept step selects its quest only once it is in the log.
local function onAll() return true end
assert(QuestSelection:QuestForNode(nodes[1], onAll) == 869)

-- An objective step names the quest being worked on.
assert(QuestSelection:QuestForNode(nodes[2], onAll) == 869)

-- A step that turns one quest in and accepts the next shows the turn-in: the
-- follow-up is not in the log yet, and even when it is the accept ranks last.
local function onlyTurnin(id) return id == 869 end
assert(QuestSelection:QuestForNode(nodes[3], onlyTurnin) == 869)
assert(QuestSelection:QuestForNode(nodes[3], onAll) == 869)

-- A step with no quest at all selects nothing.
assert(QuestSelection:QuestForNode(nodes[4], onAll) == nil)

-- A collect step names the quest the item belongs to.
assert(QuestSelection:QuestForNode(nodes[5], onAll) == 819)

-- A missing node, and a caller with no predicate, answer nil rather than throw.
assert(QuestSelection:QuestForNode(nil, onAll) == nil)
assert(QuestSelection:QuestForNode(nodes[1], nil) == nil)

-- Sync: one selection per step, and none while the setting is off.
local selected, log = {}, {}
local selection = nil
ns.modules.Client = {
    IsQuestInLog = function(_, id) return log[id] == true end,
    GetSelectedQuestLogQuest = function() return selection end,
    SelectQuestInLog = function(_, id) table.insert(selected, id); selection = id; return true end,
}
ns.modules.Progress = { store = {}, GetActiveGuide = function() return guide end }

log[869] = true
assert(QuestSelection:Sync(nodes[2]) == 869)
assert(#selected == 1 and selected[1] == 869)
-- The same step again leaves the log alone, so a quest the player clicked
-- themselves in the meantime stays selected.
selection = 871
assert(QuestSelection:Sync(nodes[2]) == nil)
assert(#selected == 1 and selection == 871)
-- The guide moving on selects again.
assert(QuestSelection:Sync(nodes[3]) == 869)
assert(#selected == 2)
-- A step whose quest is not in the log yet selects nothing, and then selects
-- once the quest arrives.
selection = nil
log[869] = false
assert(QuestSelection:Sync(nodes[1]) == nil)
assert(#selected == 2)
log[869] = true
assert(QuestSelection:Sync(nodes[1]) == 869)
assert(#selected == 3)
-- A step already showing in the log costs no call.
assert(QuestSelection:Sync(nodes[2]) == 869)
assert(#selected == 3)
-- No step (no guide, or a finished one) clears the memory, and the setting
-- being off stops all of it.
assert(QuestSelection:Sync(nil) == nil)
ns.db.settings.automation.selectQuestInLog = false
selection = nil
assert(QuestSelection:Sync(nodes[2]) == nil)
assert(#selected == 3)
ns.db.settings.automation.selectQuestInLog = true
assert(QuestSelection:Sync(nodes[2]) == 869)
assert(#selected == 4)

-- A log addressed by position: a quest turned in above ours renumbers the
-- rows, the stored row now shows someone else's quest, and the step gets its
-- quest back without the guide having moved.
local rows = {}
local selectedIndex = nil
ns.modules.Client.GetSelectedQuestLogIndex = function() return selectedIndex end
ns.modules.Client.GetSelectedQuestLogQuest = function() return rows[selectedIndex] end
ns.modules.Client.SelectQuestInLog = function(_, id)
    table.insert(selected, id)
    for index, quest in ipairs(rows) do if quest == id then selectedIndex = index; return true end end
    return false
end
rows = { 869, 871 }
selectedIndex = nil
QuestSelection:Sync(nil)
log[871] = true
assert(QuestSelection:Sync(nodes[3]) == 869 and selectedIndex == 1)
local before = #selected
-- The same step, the same quest, the same row: nothing to do.
assert(QuestSelection:Sync(nodes[3]) == nil and #selected == before)
-- Another quest turned in ahead of ours shifts it up, leaving row 1 on 871.
table.insert(rows, 1, 5000)
assert(QuestSelection:Sync(nodes[3]) == 869 and #selected == before + 1 and selectedIndex == 2)
-- A player clicking another row keeps it: the row moved, so it is theirs.
selectedIndex = 3
assert(QuestSelection:Sync(nodes[3]) == nil and selectedIndex == 3)

-- A client that will not select says so rather than pretending it did.
ns.modules.Client.SelectQuestInLog = function() return false end
selection = nil
assert(QuestSelection:Sync(nodes[3]) == nil)

print("NuuRoad quest selection tests passed")
