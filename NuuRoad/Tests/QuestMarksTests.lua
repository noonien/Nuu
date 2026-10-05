_G = _G or _ENV
local ns = { modules = {}, db = { poi = { rows = {}, order = {} } } }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log() end
ns.recorded = {}
function ns:Record(channel, data) table.insert(self.recorded, { channel = channel, d = data }) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/QuestIndex.lua")
Load(ns, "Domain/POILog.lua")
Load(ns, "Domain/QuestMarks.lua")
local Steps, Marks = ns.modules.Steps, ns.modules.QuestMarks

-- Quest 900 has an objective spot at 20, 20 and its turn-in at 30, 30; quest
-- 901 is only accepted in the guide; quest 902 is in no guide.
local guide = Steps:Expand({
    kind = "guide", schema = 1, id = "nuuroad:test:marks", updated = 1789862400, title = "Marks", category = "test",
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { type = "accept", quests = { 900, 901 }, npc = { 3464 }, at = { { 5000, 5000 } } },
            { type = "kill", quest = 900, at = { { 2000, 2000 } } },
            { type = "turnin", quests = { 900 }, npc = { 3464 }, at = { { 3000, 3000 } } },
        } },
    } },
})

local ready, marks, log = {}, {}, {}
ns.modules.Client = {
    ResolveMapID = function(_, mapID) return mapID end,
    IsQuestReadyToTurnIn = function(_, id) return ready[id] == true end,
    GetQuestTitle = function(_, id) return "Quest " .. id end,
    GetQuestLogEntries = function() return log end,
    -- A thousand yards square, so a map percent is ten yards.
    GetWorldPosition = function(_, mapID, x, y)
        if mapID ~= 1413 then return nil end
        return 1, x * 1000, y * 1000
    end,
}
ns.modules.Navigation = {
    QuestMarker = function(_, id)
        local mark = marks[id]
        if mark then return mark[1], mark[2], mark[3] end
    end,
}
ns.modules.GuideRepository = { version = 1, List = function() return { guide } end, IsBuiltIn = function() return true end }
ns.modules.QuestIndex:Invalidate()

local function check(id) return Marks:Check(id) end

-- Agreeing marks are not written.
marks[900] = { 1413, 0.22, 0.22 }
assert(check(900) == nil, "an objective mark beside the guide's spot says nothing new")
ready[900] = true
marks[900] = { 1413, 0.302, 0.30 }
assert(check(900) == nil, "a turn-in mark on the guide's turn-in says nothing new")
assert(#ns.recorded == 0)

-- A turn-in mark a long way from the guide's.
marks[900] = { 1413, 0.50, 0.50 }
local row = check(900)
assert(row and row.status == "differs" and row.role == "turnin" and row.gap == 283, "the turn-in is 283 yd out")
assert(row.x == 5000 and row.y == 5000 and row.map == 1413, "the mark in the guides' own units")
assert(row.guide == "nuuroad:test:marks" and row.step == 3 and row.guideX == 3000, "beside the step it disagrees with")
assert(ns.recorded[1].channel == "marks" and ns.recorded[1].d == row, "on the session log's marks channel")

-- Once a session, again when it moves.
assert(check(900) == nil, "the same mark is written once")
marks[900] = { 1413, 0.51, 0.50 }
assert(check(900) == nil, "a mark that moved ten yards is the same mark")
marks[900] = { 1413, 0.60, 0.50 }
assert(check(900) and #ns.recorded == 2, "a mark that moved a hundred yards is written again")

-- An objective area a long way from every objective spot; an objective a
-- guide accepts but never places; a quest no guide names.
ready[900] = nil
marks[900] = { 1413, 0.70, 0.70 }
row = check(900)
assert(row and row.status == "differs" and row.role == "objective" and row.step == 2, "objectives over 300 yd out")
marks[901] = { 1413, 0.40, 0.40 }
row = check(901)
assert(row and row.status == "missing" and row.guide == nil, "no guide places the work")
marks[902] = { 1413, 0.10, 0.10 }
row = check(902)
assert(row and row.status == "unguided" and row.title == "Quest 902", "no guide names the quest")
assert(check(903) == nil, "a quest with no mark has nothing to write")

-- A scan reads every quest in the log.
Marks.written, ns.recorded = {}, {}
log = { { questID = 900, title = "Quest 900" }, { questID = 902, title = "Quest 902" } }
Marks:Scan(true)
assert(#ns.recorded == 2, "a scan writes each quest in the log that says something new")

return true
