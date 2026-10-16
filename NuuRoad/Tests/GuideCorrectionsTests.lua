_G = _G or _ENV
local ns = { modules = {}, db = { poi = { rows = {}, order = {} } }, printed = {}, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log(message) table.insert(self.logs, message) end
ns.recorded = {}
function ns:Record(channel, data) table.insert(self.recorded, { channel = channel, d = data }) end
ns.Kit = ns.Kit or LoadKit()

-- The creature the player is talking to, when a test sets one.
local targetNPC, targetNPCName
local previousCreateFrame = CreateFrame
CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    return frame
end

Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/QuestIndex.lua")
Load(ns, "Domain/POILog.lua")
Load(ns, "Domain/GuideCorrections.lua")
local Steps, POILog, Corrections = ns.modules.Steps, ns.modules.POILog, ns.modules.GuideCorrections

-- A ported guide with a turn-in coordinate a long way from the truth, and an
-- objective coordinate that is also out - only the first is correctable.
local guide = Steps:Expand({
    kind = "guide", id = "nuuroad:test:ported", updated = 1789862400, title = "Ported", category = "test",
    data = { map = 1413, sections = {
        { title = "Steps", steps = {
            { type = "accept", quests = { 900 }, npc = { 3464 }, at = { { 5000, 5000 } } },
            { type = "kill", quest = 900, at = { { 2000, 2000 } } },
            -- Wrong: the NPC is at 50, 50.
            { type = "turnin", quests = { 900 }, npc = { 3464 }, at = { { 3000, 3000 } } },
        } },
    } },
})
local nodes = guide.nodes

local inLog, ready = { [900] = true }, { [900] = true }
local playerPosition, mapQuests = nil, {}
local Client = {
    build = {},
    HasQuestWaypoints = function() return true end,
    ResolveMapID = function(_, mapID) return mapID end,
    GetCurrentMapID = function() return 1413 end,
    GetUnitCreatureID = function() return targetNPC end,
    GetUnitName = function() return targetNPCName end,
    GetPlayerMapPosition = function() if playerPosition then return playerPosition[1], playerPosition[2] end end,
    IsQuestInLog = function(_, id) return inLog[id] == true end,
    IsQuestReadyToTurnIn = function(_, id) return ready[id] == true end,
    IsQuestComplete = function() return false end,
    GetQuestTitle = function(_, id) return "Quest " .. id end,
    GetQuestObjectives = function() return {} end,
    GetQuestWaypoint = function() return nil end,
    GetQuestPOICount = function() return 0 end,
    QuestHasPOI = function() return false, false, false end,
    GetQuestWaypointText = function() return nil end,
    GetQuestMapID = function() return 1413 end,
    GetMapInfoTable = function(_, id) return { mapID = id, name = "Map " .. id, mapType = 3 } end,
    GetQuestLogEntries = function() return { { questID = 900, title = "Quest 900" } } end,
    GetQuestPinsOnMap = function(_, id, mapID)
        local pins = {}
        for _, quest in ipairs(mapQuests[mapID] or {}) do
            if quest.questID == id then table.insert(pins, { x = quest.x, y = quest.y }) end
        end
        return pins
    end,
    GetQuestPinOnMap = function(self, id, mapID)
        local pins = self:GetQuestPinsOnMap(id, mapID)
        if not pins[1] then return nil end
        return pins[1].x, pins[1].y, #pins
    end,
    GetQuestsOnMap = function(_, mapID) return mapQuests[mapID] or {} end,
    GetAreaPOIs = function() return {} end,
    GetTaxiNodes = function() return {} end,
    GetMapChildren = function() return {} end,
    SetMapForQuestPOIs = function() return true end,
    GetMapForQuestPOIs = function() return 1413 end,
    -- A thousand yards square, so a map percent is ten yards.
    GetWorldPosition = function(_, mapID, x, y)
        if mapID ~= 1413 then return nil end
        return 1, x * 1000, y * 1000
    end,
}
ns.modules.Client = Client
local repositoryGuides = { guide }
ns.modules.GuideRepository = {
    version = 1,
    List = function() return repositoryGuides end,
    IsBuiltIn = function(_, id) return id == "nuuroad:test:ported" end,
}
ns.modules.QuestIndex:Invalidate()

-- Nothing to judge until the game has confirmed something.
assert(Corrections:Consider(guide, nodes[3], 900, "turnin") == nil, "no evidence, no finding")

-- The player hands the quest in at 50, 50: the game's own word.
playerPosition = { 0.50, 0.50 }
POILog:RecordObservation(900, "turnin")
local finding = Corrections:Consider(guide, nodes[3], 900, "turnin")
assert(finding and finding.source == "observed", "the player's own position at the turn-in is the evidence")
assert(finding.gap == 283, "the authored coordinate is 283 yd out")
assert(finding.applied == nil and nodes[3].location.x == 0.30, "nothing is changed until applying is turned on")

-- Turned on, a packaged guide's coordinate is corrected for this session.
Corrections:SetApplying(true)
Corrections:Consider(guide, nodes[3], 900, "turnin")
assert(nodes[3].location.x == 0.50 and nodes[3].location.y == 0.50, "the step now points where the quest was handed in")
assert(nodes[3].location.correctedFrom.x == 0.30 and nodes[3].location.correctedBy == "observed",
    "and what was there is kept, so nothing mistakes it for an authored coordinate")

-- An objective step is never corrected this way: a quest's mobs spawn in
-- several places and one point cannot stand for the route.
POILog:RecordObservation(900, "objective", "Claws: 1/4")
assert(Corrections:Consider(guide, nodes[2], 900, "objective") == nil, "objective steps are reported, never rewritten")
assert(nodes[2].location.x == 0.20)

-- A user guide is left alone: the editor copies it wholesale into
-- SavedVariables, so a correction could outlive the session.
local userGuide = Steps:Expand({
    kind = "guide", id = "user:guide-1", updated = 1789862400, title = "Mine", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "turnin", quests = { 900 }, npc = { 3464 }, at = { { 3000, 3000 } } },
    } } } },
})
repositoryGuides = { guide, userGuide }
ns.modules.QuestIndex:Invalidate()
local userFinding = Corrections:Consider(userGuide, userGuide.nodes[1], 900, "turnin")
assert(userFinding and userFinding.applied == nil and userFinding.skipped, "a user guide is reported, not rewritten")
assert(userGuide.nodes[1].location.x == 0.30)

-- A coordinate that agrees with the game is not a finding at all.
local goodGuide = Steps:Expand({
    kind = "guide", id = "nuuroad:test:good", updated = 1789862400, title = "Good", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "turnin", quests = { 900 }, npc = { 3464 }, at = { { 5020, 5010 } } },
    } } } },
})
assert(Corrections:Consider(goodGuide, goodGuide.nodes[1], 900, "turnin") == nil, "2 yd out is nobody's problem")

-- Every step of every guide that names the quest is judged at once, so a
-- correction lands ahead of the player as well as under them.
Corrections:Clear()
repositoryGuides = { guide }
ns.modules.QuestIndex:Invalidate()
nodes[3].location.x, nodes[3].location.y = 0.30, 0.30
Corrections:ConsiderQuest(900)
assert(#Corrections:Findings() == 1 and Corrections:Findings()[1].step == nodes[3].index)
assert(nodes[3].location.x == 0.50, "and it was applied without the player standing on the step")

-- The report says what it did, and gives the coordinate in authored form.
local report = table.concat(Corrections:ReportLines(), "\n")
assert(report:find("APPLIED for this session") and report:find("at = { 50.0, 50.0 }"))
assert(report:find("Applying corrections is ON"))

-- A step that takes its point from the NPC is corrected in the guide's names.npcs.
Corrections:Clear()
nodes[3].location.x, nodes[3].location.y, nodes[3].location.npc = 0.30, 0.30, 3464
Corrections:ConsiderQuest(900)
report = table.concat(Corrections:ReportLines(), "\n")
assert(report:find("authored form: names.npcs[3464] at = { 50.0, 50.0 }", 1, true), report)
nodes[3].location.npc = nil

-- The pin stands in when the game has not confirmed a turn-in, but only while
-- the quest is ready to hand in.
Corrections:Clear()
ns.db.poi.observed = {}
mapQuests[1413] = { { questID = 900, x = 0.62, y = 0.62 } }
nodes[3].location.x, nodes[3].location.y = 0.30, 0.30
local fromPin = Corrections:Consider(guide, nodes[3], 900, "turnin")
assert(fromPin and fromPin.source == "pin" and nodes[3].location.x == 0.62)
ready[900] = false
Corrections:Clear()
nodes[3].location.x, nodes[3].location.y = 0.30, 0.30
assert(Corrections:Consider(guide, nodes[3], 900, "turnin") == nil,
    "a quest that is not ready is pinned at its objective, which is not the turn-in")

-- A creature that walks a route. One sighting of it is a moment on that
-- round, so a step is pointed at the middle of the sightings and given a
-- radius wide enough to hold the route rather than at wherever it happened to
-- be standing once.
Corrections:Clear()
ns.db.poi.observed, ns.db.poi.npcs = {}, {}
ready[900] = true
mapQuests[1413] = {}
targetNPC, targetNPCName = 3464, "Ahab Wheathoof"
-- Talked to three times, up and down a 300 yd stretch.
playerPosition = { 0.40, 0.40 }
POILog:OnDialog()
playerPosition = { 0.40, 0.55 }
POILog:OnDialog()
playerPosition = { 0.40, 0.70 }
POILog:RecordObservation(900, "turnin")
local sighted = POILog:NPCSighting(3464)
assert(sighted and #sighted.places == 3 and sighted.roams == true, "three sightings 300 yd apart is a route, not a place")
assert(sighted.spread == 300 and sighted.middle and math.abs(sighted.middle.y - 55) < 0.01)

-- Recording that sighting already judged the step, so the reset needs a fresh
-- findings list or the second look counts as "already applied".
nodes[3].location.x, nodes[3].location.y = 0.30, 0.30
nodes[3].location.arrivalYards = nil
Corrections:Clear()
local patrol = Corrections:Consider(guide, nodes[3], 900, "turnin")
assert(patrol.roams == 300 and patrol.sightings == 3, "the finding says the creature walks and how far")
assert(math.abs(nodes[3].location.y - 0.55) < 0.001, "the step is pointed at the middle of the round")
assert(nodes[3].location.arrivalYards == 150, "and given a radius that holds it")
local patrolReport = table.concat(Corrections:ReportLines(), "\n")
assert(patrolReport:find("walks a route") and patrolReport:find("radius = 150"))

-- A creature seen twice in the same spot is standing still, and is corrected
-- to that spot with no radius of its own.
Corrections:Clear()
ns.db.poi.observed, ns.db.poi.npcs = {}, {}
targetNPC, targetNPCName = 3465, "Baine"
playerPosition = { 0.60, 0.60 }
POILog:OnDialog()
playerPosition = { 0.601, 0.601 }
POILog:RecordObservation(900, "turnin")
assert(POILog:NPCSighting(3465).roams ~= true, "a couple of yards is standing still")
nodes[3].location.x, nodes[3].location.y = 0.30, 0.30
nodes[3].location.arrivalYards = nil
Corrections:Clear()
local still = Corrections:Consider(guide, nodes[3], 900, "turnin")
assert(still.roams == nil and nodes[3].location.arrivalYards == nil)
assert(math.abs(nodes[3].location.x - 0.601) < 0.001, "and the step lands on them")
targetNPC, targetNPCName = nil, nil

-- A step that names no NPC and no spot is not corrected, but what the game
-- showed goes on the discover channel so the guide can be filled in later.
local thin = Steps:Expand({
    kind = "guide", id = "nuuroad:test:thin", updated = 1789862400, title = "Thin", category = "test",
    data = { map = 1413, sections = { { title = "Steps", steps = {
        { type = "accept", quests = { 900 }, note = "Somebody in town. Not recorded yet." },
        { type = "turnin", quests = { 900 }, npc = { 3464 }, at = { { 6000, 6000 } } },
    } } } },
})
Corrections:Initialize()
ns.recorded = {}
ns.db.poi.observed, ns.db.poi.npcs = {}, {}
targetNPC, targetNPCName = 3465, "Baine"
playerPosition = { 0.42, 0.37 }
local gap = Corrections:Discover(thin, thin.nodes[1], 900, "accept")
assert(gap == nil, "nothing is said before the game has confirmed anything")
POILog:RecordObservation(900, "accept")
gap = Corrections:Discover(thin, thin.nodes[1], 900, "accept")
assert(gap and gap.missing == "npc, at" and gap.npc == 3465 and gap.npcName == "Baine", "the step lacks both, and the game named who")
assert(gap.x == 42 and gap.y == 37 and gap.map == 1413)
assert(gap.authored == "npc = 3465, at = { 42.00, 37.00 }, map = 1413", gap.authored)
assert(ns.recorded[#ns.recorded].channel == "discover" and ns.recorded[#ns.recorded].d == gap, "it goes on the discover channel")
local rows = #ns.recorded
assert(Corrections:Discover(thin, thin.nodes[1], 900, "accept") == nil and #ns.recorded == rows, "once a session")
ns.db.poi.observed = {}
playerPosition = { 0.60, 0.60 }
POILog:RecordObservation(900, "turnin")
local other = Corrections:Discover(thin, thin.nodes[2], 900, "turnin")
assert(other == nil or other.missing ~= nil)
local found
for _, row in ipairs(ns.recorded) do if row.d.step == 2 then found = row.d end end
assert(found and found.missing == "other npc" and found.authoredNPCs[1] == 3464 and found.authored == "npc = 3465",
    "an NPC other than the authored one is a gap too; the spot is fine")
targetNPC, targetNPCName = nil, nil
ns.db.poi.observed, ns.db.poi.npcs = {}, {}

-- Initialize starts a session clean.
Corrections:Initialize()
assert(#Corrections:Findings() == 0 and Corrections.applying == false)

CreateFrame = previousCreateFrame

return true
