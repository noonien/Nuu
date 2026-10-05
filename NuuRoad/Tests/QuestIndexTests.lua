_G = _G or _ENV
local ns = { modules = {}, db = { account = { guides = {} }, settings = {} }, printed = {}, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log(message) table.insert(self.logs, message) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
AddBuiltInNames(ns)
Load(ns, "Data/Steps.lua")
Load(ns, "Data/GuideText.lua")
Load(ns, "Domain/GuideDraft.lua")
Load(ns, "Domain/GuideRepository.lua")
Load(ns, "Domain/QuestIndex.lua")
local Steps, Repository, QuestIndex, Names = ns.modules.Steps, ns.modules.GuideRepository, ns.modules.QuestIndex, ns.modules.Names

ns.packagedGuides = {
    { kind = "guide", schema = 1, id = "test:barrens", updated = 1789862400, title = "Barrens", category = "test",
        data = { map = 1413, sections = {
            { title = "Steps", steps = {
                { type = "accept", quests = { 869 }, npc = { 3464 } },
                { type = "kill", quest = 869 },
                { type = "talk", turnin = { 869 }, accept = { 871 }, npc = { 3464 } },
                { type = "kill", kill = { 3267 }, quest = { 871, 1 } },
                { type = "collect", item = 4926, starts = 819, object = "Chen's Empty Keg" },
                { type = "turnin", quests = { 871 }, npc = { 3464 } },
            } },
        } } },
    { kind = "guide", schema = 1, id = "test:alpha", updated = 1789862400, title = "Alpha", category = "test",
        data = { map = 1413, sections = {
            { title = "Steps", steps = {
                { type = "accept", quests = { 871 }, npc = { 3464 } },
                { type = "turnin", quests = { 871 }, npc = { 3464 } },
            } },
        } } },
}
Repository:Initialize()

-- Roles come from the verb.
local barrens = Repository:Get("test:barrens")
local function nodeByIndex(guide, index) return guide.nodes[index] end
local q = QuestIndex:NodeQuests(nodeByIndex(barrens, 2))
assert(#q == 1 and q[1].id == 869 and q[1].role == "objective", "whole-quest objective step")
q = QuestIndex:NodeQuests(nodeByIndex(barrens, 3))
assert(#q == 2 and q[1].id == 869 and q[1].role == "turnin" and q[2].id == 871 and q[2].role == "accept", "talk step yields turnin then accept")
q = QuestIndex:NodeQuests(nodeByIndex(barrens, 4))
assert(#q == 1 and q[1].id == 871 and q[1].role == "objective", "objective part step")
q = QuestIndex:NodeQuests(nodeByIndex(barrens, 5))
assert(#q == 1 and q[1].id == 819 and q[1].role == "collect", "collect step with starts")
assert(#QuestIndex:NodeQuests(nil) == 0 and #QuestIndex:NodeQuests({ kind = "note" }) == 0, "nodes without quests")

-- Hand-written nodes are read through their completion rule.
q = QuestIndex:NodeQuests({ kind = "action", completion = { type = "observed", observed = { type = "all", children = {
    { type = "quests", state = "finished", ids = { 870 } },
    { type = "objective", questID = 845, index = 2 },
    { type = "item", itemID = 4986, count = 1, questID = 924 },
} } } })
assert(#q == 3 and q[1].id == 870 and q[1].role == "turnin" and q[2].id == 845 and q[2].role == "objective" and q[3].id == 924 and q[3].role == "collect", "observed rules give roles")
q = QuestIndex:NodeQuests({ kind = "action", refs = { quests = { 809 } } })
assert(#q == 1 and q[1].role == "step", "a bare reference is a step role")

-- Guides for a quest, alphabetical, with every step in guide order.
local entries = QuestIndex:GuidesFor(871)
assert(#entries == 2, "871 is in two guides, got " .. #entries)
assert(entries[1].guide.id == "test:alpha" and entries[2].guide.id == "test:barrens", "sorted by title")
local steps = entries[2].steps
assert(#steps == 3, "barrens handles 871 on three steps, got " .. #steps)
assert(steps[1].index == 3 and steps[1].role == "accept", "first is the accept on step 3")
assert(steps[2].index == 4 and steps[2].role == "objective", "then the objective")
assert(steps[3].index == 6 and steps[3].role == "turnin", "then the turn-in")
assert(steps[1].index == barrens.nodes[3].index, "step carries the flattened index")
assert(QuestIndex:DescribeSteps(entries[2]) == "accepted at step 3, worked on at step 4, turned in at step 6", QuestIndex:DescribeSteps(entries[2]))
assert(QuestIndex:FirstStep(entries[2]).index == 3, "the accept is the first step")
assert(QuestIndex:FirstStep({ steps = {
    { index = 9, role = "turnin" }, { index = 4, role = "objective" }
} }).index == 4, "without an accept the earliest by role")
assert(#QuestIndex:GuidesFor(819) == 1 and QuestIndex:GuidesFor(819)[1].steps[1].role == "collect", "the keg quest is found through its item")
assert(#QuestIndex:GuidesFor(99999) == 0 and #QuestIndex:GuidesFor(nil) == 0 and #QuestIndex:GuidesFor("871") == 0, "unknown quests find nothing")

-- Titles resolve through the names table, ignoring colour codes and case.
assert(QuestIndex:QuestIDByTitle("|cffffd100" .. Names:Quest(869) .. "|r") == 869, "title with colour codes")
assert(QuestIndex:QuestIDByTitle(string.upper(Names:Quest(871))) == 871, "title case-insensitive")
assert(QuestIndex:QuestIDByTitle("No Such Quest") == nil and QuestIndex:QuestIDByTitle(nil) == nil, "unknown titles")

-- Search text names every quest of a guide, by title and by ID token.
local text = QuestIndex:SearchText(barrens)
assert(text:find("quest:869", 1, true) and text:find("quest:819", 1, true), "search text has quest IDs: " .. text)
assert(text:find(Names:Quest(869):lower(), 1, true), "search text has quest titles")
assert(QuestIndex:SearchText({ id = "nope" }) == "" and QuestIndex:SearchText(nil) == "", "unknown guides search as nothing")

-- The index follows the repository: saving a personal guide is picked up.
local personal = ns.modules.GuideDraft:Open({
    kind = "guide", schema = 1, id = Repository.pendingID, updated = 1789862400, title = "Personal", category = "custom",
    data = { map = 1413, sections = {
        { title = "Steps", steps = { { type = "accept", quests = { 264 }, npc = { 3464 } } } },
    } },
})
assert(#QuestIndex:GuidesFor(264) == 0, "not yet")
local _, saved = Repository:SaveDraft(personal)
assert(saved, "saved")
assert(#QuestIndex:GuidesFor(264) == 1 and QuestIndex:GuidesFor(264)[1].guide.meta.title == "Personal", "saved guide indexed")
assert(#QuestIndex:GuidesFor(871) == 2, "others unchanged")
