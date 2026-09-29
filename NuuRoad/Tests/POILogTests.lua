_G = _G or _ENV
local ns = { modules = {}, db = { poi = { rows = {}, order = {} } }, printed = {}, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Print(message) table.insert(self.printed, message) end
function ns:Log(message) table.insert(self.logs, message) end
ns.Kit = ns.Kit or LoadKit()

-- Initialize builds an event frame in the client; outside it, a stub is
-- enough to prove the wiring is guarded rather than assumed.
-- The creature the player is talking to, when a test sets one.
local targetNPC, targetNPCName
local previousCreateFrame = CreateFrame
CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    return frame
end

Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/QuestIndex.lua")
Load(ns, "Domain/POILog.lua")
local Steps, POILog = ns.modules.Steps, ns.modules.POILog

local guide = Steps:Expand({
    schema = 2, id = "test:poi", updated = 1789862400, map = 1413, meta = { title = "POI", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 869, npc = 3464, at = { 44, 59 } },
        { objectives = 869, at = { 46, 62 } },
        { travel = "South road", at = { 50, 70 } },
    } },
},
})
local nodes = guide.nodes

-- A stand-in client. The map is 1000 yards square, so a map percent is ten
-- yards and a gap is easy to reason about.
local waypoints, inLog = {}, { [869] = true }
local mapQuests, questMaps, objectives = {}, {}, {}
local ready, finished = {}, {}
local playerPosition
local repositoryGuides
-- The Barrens sits under Kalimdor, which sits under the cosmic map: a quest
-- pinned on the continent rather than the zone has to be reachable from the
-- zone the step is in.
local mapInfos = {
    [946] = { mapID = 946, name = "Cosmic", mapType = 0 },
    [1413] = { mapID = 1413, name = "The Barrens", mapType = 3, parentMapID = 1414 },
    [1412] = { mapID = 1412, name = "Mulgore", mapType = 3, parentMapID = 1414 },
    [1414] = { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 946 },
}
local areaPOIs, taxiNodes, logQuests
local Client = {
    build = { version = "1.60.1" },
    HasQuestWaypoints = function() return true end,
    ResolveMapID = function(_, mapID) return mapID end,
    GetCurrentMapID = function() return 1413 end,
    GetUnitCreatureID = function() return targetNPC end,
    GetUnitName = function() return targetNPCName end,
    GetPlayerMapPosition = function() if playerPosition then return playerPosition[1], playerPosition[2] end end,
    -- The POI system is map-scoped; the stub records which map it was pointed
    -- at so the tests can check the reads point it somewhere.
    SetMapForQuestPOIs = function(self, mapID) self.poiMap = mapID; return true end,
    GetMapForQuestPOIs = function(self) return self.poiMap end,
    IsQuestInLog = function(_, id) return inLog[id] == true end,
    IsQuestReadyToTurnIn = function(_, id) return ready[id] == true end,
    IsQuestComplete = function(_, id) return finished[id] == true end,
    GetQuestWaypoint = function(_, id)
        local point = waypoints[id]
        if not point then return nil end
        return point.map, point.x, point.y
    end,
    QuestHasPOI = function(_, id) return waypoints[id] ~= nil, true, true end,
    -- The call that actually answers on the live client: the map's own pin
    -- list, asked per quest.
    GetQuestPinsOnMap = function(_, id, mapID)
        local pins = {}
        for _, quest in ipairs(mapQuests[mapID] or {}) do
            if quest.questID == id then table.insert(pins, { x = quest.x, y = quest.y }) end
        end
        return pins
    end,
    GetQuestPinOnMap = function(_, id, mapID)
        local found
        for _, quest in ipairs(mapQuests[mapID] or {}) do
            if quest.questID == id then
                found = found or { quest.x, quest.y, 0 }
                found[3] = found[3] + 1
            end
        end
        if not found then return nil end
        return found[1], found[2], found[3]
    end,
    -- The map the client files a quest under, whatever map the player is on.
    GetQuestMapID = function(_, id) return questMaps[id] end,
    GetMapInfoTable = function(_, id) return mapInfos[id] end,
    GetQuestObjectives = function(_, id) return objectives[id] or {} end,
    GetQuestWaypointText = function(_, id) return waypoints[id] and waypoints[id].text or nil end,
    GetQuestPOICount = function() return 1 end,
    -- World coordinates: same continent, a percent to ten yards, and nil for
    -- a map the stub does not know, so "not comparable" can be exercised.
    GetWorldPosition = function(_, mapID, x, y)
        if mapID ~= 1413 and mapID ~= 1412 then return nil end
        return 1, x * 1000, y * 1000
    end,
}
ns.modules.Client = Client

local function reading(node, questID)
    return POILog:Reading(guide, node, questID, "objective")
end

-- Nothing from the client is not an error: the row records the blank, which
-- is the answer the question is really asking about.
local blank = reading(nodes[2], 869)
assert(blank.wmap == nil and blank.gap == nil and blank.inLog == true)
assert(blank.ax == 46 and blank.ay == 62, "authored coordinates are kept as map percent")

-- A waypoint near the authored point: same map, a small gap in yards.
waypoints[869] = { map = 1413, x = 0.465, y = 0.623, text = "Travel to the Sludge Fen" }
local close = reading(nodes[2], 869)
assert(close.wmap == 1413 and close.wx == 46.5 and close.sameMap == true)
assert(close.gap == 6, "5 yards east and 3 north is a 6 yard gap")
assert(close.text == "Travel to the Sludge Fen")

-- A waypoint on another map is recorded as such rather than as a distance.
waypoints[869] = { map = 1412, x = 0.5, y = 0.5 }
local elsewhere = reading(nodes[2], 869)
assert(elsewhere.sameMap == false and elsewhere.gap ~= nil)

-- A map the client cannot place has no gap to give.
waypoints[869] = { map = 9999, x = 0.5, y = 0.5 }
assert(reading(nodes[2], 869).gap == nil)

-- A step with no authored coordinates still asks; there is simply nothing to
-- compare the answer against.
waypoints[869] = { map = 1413, x = 0.465, y = 0.623 }
local noCoords = POILog:Reading(guide, { index = 7, kind = "note" }, 869, "step")
assert(noCoords.ax == nil and noCoords.gap == nil)

-- One row per step and quest: a reading that agrees counts up, one whose
-- waypoint has moved overwrites the position and counts the move.
POILog:Clear()
POILog:Record(reading(nodes[2], 869))
POILog:Record(reading(nodes[2], 869))
assert(#POILog:Rows() == 1 and POILog:Rows()[1].seen == 2 and POILog:Rows()[1].moves == 0)
waypoints[869] = { map = 1413, x = 0.40, y = 0.60 }
local movedRow = POILog:Record(reading(nodes[2], 869))
assert(#POILog:Rows() == 1, "the same step and quest stays one row")
assert(movedRow.moves == 1 and movedRow.wx == 40, "a waypoint that moved is recorded where it moved to")
POILog:Record(reading(nodes[1], 869))
assert(#POILog:Rows() == 2, "another step is another row")

-- The oldest rows are dropped when the log is full.
POILog:Clear()
local limit = POILog.limit
POILog.limit = 3
for step = 1, 5 do POILog:Record(POILog:Reading(guide, { index = step, kind = "note" }, 869, "step")) end
local rows = POILog:Rows()
assert(#rows == 3 and rows[1].step == 3 and rows[3].step == 5, "the log keeps the newest rows")
POILog.limit = limit

-- The summary sorts answers into the buckets the decision rests on.
POILog:Clear()
waypoints[869] = { map = 1413, x = 0.462, y = 0.621 } -- ~2 yd from the step
POILog:Record(reading(nodes[2], 869))
waypoints[869] = { map = 1413, x = 0.48, y = 0.63 }   -- ~22 yd
POILog:Record(reading(nodes[1], 869))
waypoints[871] = { map = 1413, x = 0.60, y = 0.70 }   -- far from step 2
inLog[871] = true
POILog:Record(POILog:Reading(guide, nodes[2], 871, "objective"))
inLog[873] = true -- in the log, and the client has nothing for it
POILog:Record(POILog:Reading(guide, nodes[3], 873, "step"))
POILog:Record(POILog:Reading(guide, nodes[3], 872, "step")) -- never in the log
local summary = POILog:Summarize(POILog:Rows())
assert(summary.rows == 5 and summary.inLog == 4 and summary.notInLog == 1)
assert(summary.answered == 3 and summary.blank == 1, "a quest in the log the client will not place is a blank")
assert(summary.near == 1 and summary.close == 1 and summary.far == 1, "the far row is the one the step disagrees with")
assert(summary.worst[1].quest == 871, "the worst disagreement leads the list")
assert(summary.roles.objective.rows == 3 and summary.roles.objective.answered == 3 and summary.roles.objective.usable == 2,
    "the objective rows are the ones the authored coordinates compete with")
assert(summary.roles.step.inLog == 1 and summary.roles.step.blank == 1 and summary.roles.step.notInLog == 1)

-- Accepts and turn-ins are sampled like anything else, and the roles are
-- counted apart because they are not the same question: a quest being
-- accepted is not in the log, so the client has nothing to place; the same
-- quest at its turn-in is in the log, and that is when the client's own pin
-- points at the turn-in NPC.
POILog:Clear()
inLog[880] = false
POILog:Record(POILog:Reading(guide, nodes[1], 880, "accept"))
inLog[881] = true
waypoints[881] = { map = 1413, x = 0.501, y = 0.701 }
POILog:Record(POILog:Reading(guide, nodes[3], 881, "turnin"))
local roles = POILog:Summarize(POILog:Rows()).roles
assert(roles.accept.rows == 1 and roles.accept.notInLog == 1 and roles.accept.answered == 0,
    "a quest not taken yet cannot be placed, and is not counted against the client")
assert(roles.turnin.rows == 1 and roles.turnin.inLog == 1 and roles.turnin.answered == 1 and roles.turnin.usable == 1,
    "a turn-in is in the log, so the client can place it")
assert(POILog.Describe(POILog:Rows()[1]):find("accept"), "every row names its role")

-- Before a step's quest is asked about, the client is pointed at the step's
-- map: the POI reads answer for whichever map the client was last given.
Client.poiMap = nil
reading(nodes[2], 869)
assert(Client.poiMap == 1413, "the step's map is set before the question is put")

-- A quest is not pinned on one map. The step's own map is asked first, the
-- others are recorded as also pinning it, and a pin on a continent map is
-- marked as the coarse thing it is: one pin standing for a whole zone.
POILog:Clear()
waypoints[869] = nil
questMaps[869] = 1413
mapQuests[1414] = { { questID = 869, x = 0.55, y = 0.30 } }             -- Kalimdor, the continent
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 },              -- the zone, pinned twice
                    { questID = 869, x = 0.48, y = 0.64 } }
ns.db.poi.maps = { ["1413"] = { mapID = 1413, mapType = 3 }, ["1414"] = { mapID = 1414, mapType = 2 } }
local spread = reading(nodes[2], 869)
assert(spread.wmap == 1413 and spread.wmapType == 3, "the step's own map answers first, and it is a zone map")
assert(spread.pins == 2, "both pins on that map are counted")
assert(spread.maps >= 2 and spread.alsoOn, "the continent map pins it too, and that is kept")
local wider = POILog:PlaceQuest(869, { 1414 })
assert(wider.mapID == 1414 and wider.mapType == 2, "asked about the continent first, the continent answers")
POILog:Record(spread)
local spreadSummary = POILog:Summarize(POILog:Rows())
assert(spreadSummary.multiPin == 1 and spreadSummary.multiMap == 1 and spreadSummary.onZoneMap == 1)
assert(POILog.Describe(POILog:Rows()[1]):find("2 pins here"))
mapQuests[1414], questMaps[869] = nil, nil
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- Where the player stood when the question was put is kept per row, because
-- an answer of "nothing" from another continent is not the same evidence as
-- one from the quest's own zone. An answer once given is never unsaid by a
-- later blank.
POILog:Clear()
waypoints[869] = nil
mapQuests[1413] = nil
Client.GetCurrentMapID = function() return 1450 end -- far away: nothing to place
POILog:Record(reading(nodes[2], 869))
local far = POILog:Rows()[1]
assert(far.wmap == nil and far.askedOn["1450"].asked == 1 and far.askedOn["1450"].placed == 0)
Client.GetCurrentMapID = function() return 1413 end -- in the zone: the map pins it
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }
local placed = POILog:Record(reading(nodes[2], 869))
assert(placed.wmap == 1413 and placed.source == "pin", "asked from the right place, the client answers")
assert(placed.askedOn["1413"].placed == 1 and placed.askedOn["1450"].placed == 0, "each map keeps its own tally")
assert(placed.placedFrom == 1413 and placed.blanks == 1)
Client.GetCurrentMapID = function() return 1450 end
mapQuests[1413] = nil
local again = POILog:Record(reading(nodes[2], 869))
assert(again.wmap == 1413, "a later blank from far away does not erase an answer already given")
local byMapSummary = POILog:Summarize(POILog:Rows())
assert(byMapSummary.byPlayerMap["1450"].asked == 2 and byMapSummary.byPlayerMap["1450"].placed == 0)
assert(byMapSummary.byPlayerMap["1413"].placed == 1)
Client.GetCurrentMapID = function() return 1413 end
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- The sweep: everything the client draws on a map, whether or not the player
-- is there or has the quest.
areaPOIs, taxiNodes, logQuests = {}, {}, {}
Client.GetCurrentMapID = function() return 1413 end
Client.GetMapChildren = function(_, root)
    if root ~= 946 then return {} end
    return { { mapID = 1413, name = "The Barrens", mapType = 3 }, { mapID = 1412, name = "Mulgore", mapType = 3 } }
end
Client.GetAreaPOIs = function(_, mapID) return areaPOIs[mapID] or {} end
Client.GetTaxiNodes = function(_, mapID) return taxiNodes[mapID] or {} end
Client.GetQuestsOnMap = function(_, mapID) return mapQuests[mapID] or {} end
Client.GetQuestLogEntries = function() return logQuests end
Client.GetQuestTitle = function(_, id) return "Quest " .. id end

areaPOIs[1413] = { { id = 5, name = "Crossroads", x = 0.516, y = 0.306, atlas = "poi-town" } }
taxiNodes[1413] = { { id = 66, name = "Crossroads, Northern Barrens", x = 0.517, y = 0.303, faction = 1 } }
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

POILog:Clear()
assert(POILog:SweepMap({ mapID = 1413, name = "The Barrens" }) == 3, "a POI, a flight point and a pinned quest")
assert(POILog:SweepMap({ mapID = 1412, name = "Mulgore" }, true) == 0, "a map the client has nothing for counts as empty")
assert(POILog:SweepMap({ mapID = 1412, name = "Mulgore" }) == 0, "and a read outside a pass does not add to that count")
local store = ns.db.poi
assert(store.pois["1413:5"].name == "Crossroads" and store.pois["1413:5"].x == 51.6, "coordinates are kept as map percent")
assert(store.taxi["1413:66"].name == "Crossroads, Northern Barrens")
assert(store.mapQuests["1413:869"].title == "Quest 869")
assert(store.sweep.maps == 2 and store.sweep.pois == 1 and store.sweep.taxi == 1 and store.sweep.quests == 1)
assert(store.sweep.emptyMaps == 1)
POILog:SweepMap({ mapID = 1413, name = "The Barrens" })
assert(POILog.Count(store.pois) == 1, "a second pass over the same map overwrites rather than doubles")

-- The map list comes from the cosmic map's children, and the current map is
-- never missed.
local maps = POILog:MapList()
assert(#maps >= 3, "the cosmic map's descendants plus the current map")

-- Every quest in the log is recorded, not just the ones a step names.
logQuests = {
    { questID = 869, title = "Lost in Battle" },        -- no waypoint, but the map pins it
    { questID = 905, title = "Supervisor Fizsprocket" }, -- a waypoint of its own
    { questID = 906, title = "Nothing Known" },          -- neither
}
waypoints[869] = nil
waypoints[905] = { map = 1413, x = 0.62, y = 0.41 }
POILog:Clear()
assert(POILog:SweepQuestLog() == 3)
local logRows = POILog:Rows()
assert(#logRows == 3 and logRows[1].role == "log" and logRows[1].guide == "log")
assert(logRows[2].wmap == 1413 and logRows[2].source == "waypoint", "a quest the waypoint call places says so")
assert(logRows[1].wmap == 1413 and logRows[1].source == "pin",
    "a quest the waypoint call will not place still comes from the map's pin list")
assert(logRows[3].wmap == nil and logRows[3].source == nil, "and one neither call places is a blank, which is the answer too")

-- The entry cap stops a sweep from filling SavedVariables without bound.
POILog:Clear()
local entryLimit = POILog.entryLimit
POILog.entryLimit = 2
POILog:SweepMap({ mapID = 1413, name = "The Barrens" })
assert(POILog.Count(store.pois) + POILog.Count(store.taxi) + POILog.Count(store.mapQuests) == 2, "the cap holds")
POILog.entryLimit = entryLimit

-- The listing renders whatever was swept.
POILog:Clear()
POILog:SweepMap({ mapID = 1413, name = "The Barrens" })
local mapLines = table.concat(POILog:MapLines(), "\n")
assert(mapLines:find("Crossroads") and mapLines:find("Flight points") and mapLines:find("Area POIs"))

-- A quest sitting in the log with no step in front of the player is still
-- compared: every packaged guide is indexed by quest, so the guide's own
-- coordinates for that quest are the yardstick. This is what turns a quest
-- log into evidence instead of a list of blanks.
POILog:Clear()
repositoryGuides = { guide }
ns.modules.GuideRepository = {
    version = 1,
    List = function() return repositoryGuides end,
}
ns.modules.QuestIndex:Invalidate()
mapQuests[1413] = { { questID = 869, x = 0.462, y = 0.621 } }
waypoints[869] = nil
logQuests = { { questID = 869, title = "Lost in Battle" } }
assert(POILog:SweepQuestLog() == 1)
local indexed = POILog:Rows()[1]
assert(indexed.amap == 1413 and indexed.ax == 46, "the guide's objective step is the yardstick")
assert(indexed.against and indexed.against:find("test:poi"), "and the row says which step it was measured against")
assert(indexed.source == "pin" and indexed.gap == 2, "a pin two yards off the authored point")
assert(indexed.sameMap == true)
ns.modules.GuideRepository = nil
ns.modules.QuestIndex:Invalidate()

-- Two clusters in one zone: the guide has two steps for one quest on the same
-- map, far apart. The row has to say so, and a pin sitting on the far cluster
-- has to read as a pin on the other cluster rather than as a bad pin.
POILog:Clear()
local clusterGuide = Steps:Expand({
    schema = 2, id = "test:clusters", updated = 1789862400, map = 1413, meta = { title = "Clusters", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { objectives = 890, at = { 40, 30 } },   -- north side of the zone
        { objectives = 890, at = { 60, 70 } },   -- south side, ~450 yd away
    } },
},
})
repositoryGuides = { clusterGuide }
ns.modules.GuideRepository = { version = 2, List = function() return repositoryGuides end }
ns.modules.QuestIndex:Invalidate()
inLog[890] = true
waypoints[890] = nil
objectives[890] = { { text = "Plainstriders slain: 0/10" } }
mapQuests[1413] = { { questID = 890, x = 0.60, y = 0.70 } } -- the client pins the south cluster only

local clustered = POILog:Reading(clusterGuide, clusterGuide.nodes[1], 890, "objective")
assert(clustered.spots == 2 and clustered.spread == 447, "the guide puts this quest in two places, 447 yd apart")
assert(clustered.pins == 1, "the client pins it once")
assert(clustered.gap == 447, "measured against the step in front of the player, the pin looks badly wrong")
assert(clustered.gapNear == 0, "measured against the nearest authored spot, it is exactly the other cluster")
assert(clustered.nearestStep:find("step 2"), "and the row names which step that was")
assert(clustered.objectives == 1)
POILog:Record(clustered)
local clusterSummary = POILog:Summarize(POILog:Rows())
assert(clusterSummary.multiSpot == 1 and clusterSummary.multiSpotPinnedOnce == 1,
    "a quest worked in two places that the client pins only once is the case that decides this")
assert(clusterSummary.nearerOtherSpot == 1)
POILog:ProbeQuest(890)
local detail = table.concat(POILog:QuestDetailLines(), "\n")
assert(detail:find("guides place it in 2 spot") and detail:find("pin 1 at"),
    "the collected detail lists the authored spots and every pin")
ns.modules.GuideRepository, repositoryGuides = nil, nil
ns.modules.QuestIndex:Invalidate()
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- The per-quest detail is collected while playing, not asked for: the quest
-- log pass records every map that could place each quest, and the most pins
-- any map ever gave is kept even when a later read gives fewer.
POILog:Clear()
logQuests = { { questID = 869, title = "Lost in Battle" } }
questMaps[869] = 1413
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 }, { questID = 869, x = 0.52, y = 0.58 } }
POILog:SweepQuestLog()
local detailed = ns.db.poi.quests["869"]
assert(detailed and detailed.maps["1413"], "the quest log pass collects the detail by itself")
assert(#detailed.maps["1413"].pins == 2 and detailed.maps["1413"].best == 2, "both pins on that map are kept")
assert(detailed.maps["1414"], "the continent above it is asked too")
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }
POILog:SweepQuestLog()
assert(detailed.maps["1413"].best == 2, "the most pins a map ever gave survives a later read that gives fewer")
assert(detailed.reads == 2)
local detailLines = table.concat(POILog:QuestDetailLines(), "\n")
assert(detailLines:find("Quests recorded: 1") and detailLines:find("most ever 2"))

-- Session only: Initialize empties whatever a previous session left behind.
ns.db.poi.rows["stale"] = { guide = "old", step = 1, quest = 1 }
ns.db.poi.order = { "stale" }
POILog:Initialize()
assert(#POILog:Rows() == 0 and POILog.Count(ns.db.poi.quests) == 0, "a reload starts from scratch")
assert(ns.db.poi.session ~= nil, "and the session is stamped")

-- A pin that lands on the turn-in NPC rather than the objectives. A guide
-- that accepts, works and hands in one quest gives all three kinds of step,
-- so the distance to each is measured and the report can say which the client
-- is actually pinning.
POILog:Clear()
local handInGuide = Steps:Expand({
    schema = 2, id = "test:handin", updated = 1789862400, map = 1413, meta = { title = "Hand in", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 891, npc = 3464, at = { 48, 28 } },
        { objectives = 891, at = { 62, 44 } },
        { turnin = 891, npc = 3464, at = { 48, 28 } },
    } },
},
})
repositoryGuides = { handInGuide }
ns.modules.GuideRepository = { version = 3, List = function() return repositoryGuides end }
ns.modules.QuestIndex:Invalidate()
inLog[891], ready[891] = true, true
waypoints[891] = nil
objectives[891] = { { text = "Wing: 1/1", finished = true } }
mapQuests[1413] = { { questID = 891, x = 0.481, y = 0.287 } } -- on the quest giver, not the field

local handIn = POILog:Reading(handInGuide, handInGuide.nodes[2], 891, "objective")
assert(handIn.ready == true, "the quest was ready to hand in when it was asked about")
assert(handIn.gapTurnin ~= nil and handIn.gapTurnin < 20, "the pin sits on the authored turn-in step")
assert(handIn.gapObjective > 200, "and nowhere near the authored objective step")
assert(handIn.nearestRole == "accept" or handIn.nearestRole == "turnin",
    "the nearest authored step is the quest giver's, which accept and turn-in share")
POILog:Record(handIn)
local handInSummary = POILog:Summarize(POILog:Rows())
assert(handInSummary.readyPlaced == 1 and handInSummary.readyNearTurnin == 1,
    "a finished quest pinned at its turn-in is exactly what the summary counts")
assert(handInSummary.unreadyPlaced == 0)
assert(POILog.Describe(POILog:Rows()[1]):find("READY to hand in"))
ns.modules.GuideRepository, repositoryGuides = nil, nil
ns.modules.QuestIndex:Invalidate()
inLog[891], ready[891] = nil, nil
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- An unfinished quest whose pin sits in the middle of everywhere the guide
-- sends the player, rather than on any one of those places: the area-centre
-- shape, measured rather than eyeballed.
POILog:Clear()
local spreadGuide = Steps:Expand({
    schema = 2, id = "test:centre", updated = 1789862400, map = 1413, meta = { title = "Centre", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { objectives = 892, at = { 20, 20 } },
        { objectives = 892, at = { 60, 50 } },
        { objectives = 892, at = { 40, 80 } },
    } },
},
})
repositoryGuides = { spreadGuide }
ns.modules.GuideRepository = { version = 4, List = function() return repositoryGuides end }
ns.modules.QuestIndex:Invalidate()
inLog[892] = true
waypoints[892] = nil
objectives[892] = { { text = "Spores: 0/4" } }
mapQuests[1413] = { { questID = 892, x = 0.40, y = 0.50 } } -- the middle of the three

local middle = POILog:Reading(spreadGuide, spreadGuide.nodes[1], 892, "objective")
assert(middle.gapCentroid ~= nil and middle.gapCentroid < 5, "the pin is the middle of the three places")
assert(middle.gapNear == 200, "and is 200 yd from the nearest of them")
assert(middle.centroidCloser == true)
POILog:Record(middle)
local middleSummary = POILog:Summarize(POILog:Rows())
assert(middleSummary.centroidMeasured == 1 and middleSummary.centroidCloser == 1)
assert(middleSummary.unreadyPlaced == 1 and middleSummary.unreadyNearObjective == 0,
    "an area centre is not an objective position, however well it centres them")
assert(POILog.Describe(POILog:Rows()[1]):find("nearer the middle than any spot"))
ns.modules.GuideRepository, repositoryGuides = nil, nil
ns.modules.QuestIndex:Invalidate()
inLog[892] = nil
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- Neither the guide nor the client is ground truth: the guides are ports and
-- a ported coordinate can be wrong. So both are scored against where the game
-- said things happened - the player's own position at the moment it did.
POILog:Clear()
local portedGuide = Steps:Expand({
    schema = 2, id = "test:ported", updated = 1789862400, map = 1413, meta = { title = "Ported", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { objectives = 893, at = { 20, 20 } }, -- a wrong coordinate, as a bad port gives
    } },
},
})
repositoryGuides = { portedGuide }
ns.modules.GuideRepository = { version = 5, List = function() return repositoryGuides end }
ns.modules.QuestIndex:Invalidate()
inLog[893] = true
waypoints[893] = nil
objectives[893] = { { text = "Spores: 0/4" } }
mapQuests[1413] = { { questID = 893, x = 0.503, y = 0.601 } }
playerPosition = { 0.50, 0.60 } -- where the player stood when the objective ticked
logQuests = { { questID = 893, title = "Fungal Spores" } }

-- The game's word that progress happened here.
POILog:OnQuestLogUpdate()                         -- first look: nothing to compare against
objectives[893] = { { text = "Spores: 1/4" } }
POILog:OnQuestLogUpdate()                         -- the line changed, so this is a real place
local observations = POILog:Observations(893)
assert(#observations == 1 and observations[1].kind == "objective" and observations[1].x == 50)
-- The pin as it stood at that instant is kept with it: both halves of the
-- pair come from the same moment, so neither depends on an authored coordinate.
assert(observations[1].pin and observations[1].pin.map == 1413 and observations[1].pinGap ~= nil)
assert(observations[1].pinGap < 15, "the client's pin at that instant was where the objective advanced")
assert(observations[1].ready == false)
local pairs_ = POILog:PairedSamples()
assert(pairs_.total == 1 and pairs_.near == 1 and pairs_.byKind.objective.total == 1 and pairs_.byKind.objective.median ~= nil)
-- The guide is scored against the same event, not against whichever
-- observation happens to be nearest: an objective event is measured against
-- the guide's objective step.
assert(observations[1].guideGap == 500 and observations[1].guideSameKind == true)
assert(pairs_.guideMeasured == 1 and pairs_.clientWon == 1 and pairs_.guideWon == 0)
assert(pairs_.byKind.objective.guideMedian == 500)

-- An accept fires before the quest reaches the log, so its pin is empty at
-- that instant and is filled on the next look rather than left blank forever.
POILog:RecordObservation(893, "accept")
local acceptEntry = POILog:Observations(893)[2]
assert(acceptEntry.kind == "accept" and acceptEntry.pin ~= nil, "the stub client places it straight away")
acceptEntry.pin, acceptEntry.pinGap, acceptEntry.pinFilled = nil, nil, nil
POILog:OnQuestLogUpdate()
assert(acceptEntry.pin ~= nil and acceptEntry.pinFilled == true, "an empty pin is filled in on the next look")

-- A quest no guide names at all is still scored against where things
-- happened: the observations are the yardstick, and they do not need a step.
local guides = ns.modules.GuideRepository
ns.modules.GuideRepository = nil
ns.modules.QuestIndex:Invalidate()
local unguided = POILog:QuestLogReading(893)
assert(unguided.gapObserved ~= nil and (unguided.spots or 0) == 0)
assert(unguided.authoredObserved == nil, "with nothing authored, only the client is scored")
ns.modules.GuideRepository = guides
ns.modules.QuestIndex:Invalidate()

local scored = POILog:Reading(portedGuide, portedGuide.nodes[1], 893, "objective")
assert(scored.gapObserved ~= nil and scored.gapObserved < 15, "the client's pin is where the objective actually advanced")
assert(scored.authoredObserved == 500, "the guide's coordinate is 500 yd from it: a porting error, not a client error")
POILog:Record(scored)
local scoredSummary = POILog:Summarize(POILog:Rows())
assert(scoredSummary.observedCompared == 1 and scoredSummary.clientNearObserved == 1 and scoredSummary.authoredNearObserved == 0)
assert(scoredSummary.clientBeatAuthored == 1 and scoredSummary.authoredBeatClient == 0)
assert(table.concat(POILog:ObservationLines(), "\n"):find("objective"))
ns.modules.GuideRepository, repositoryGuides = nil, nil
ns.modules.QuestIndex:Invalidate()
inLog[893], playerPosition = nil, nil
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- Spawns are scattered: a quest is worked in several places in a zone, and
-- sometimes in several zones. The log groups the places the player actually
-- worked, so a pin that sits on another cluster is told apart from a pin that
-- is simply out.
POILog:Clear()
inLog[894] = true
waypoints[894] = nil
objectives[894] = { { text = "Claws: 0/4" } }
logQuests = { { questID = 894, title = "Two Camps" } }

-- The player works the north camp while the client pins it.
playerPosition = { 0.30, 0.30 }
mapQuests[1413] = { { questID = 894, x = 0.305, y = 0.302 } }
POILog:OnQuestLogUpdate()
objectives[894] = { { text = "Claws: 1/4" } }
POILog:OnQuestLogUpdate()
POILog:ProbeQuest(894)

-- Then the south camp, 600 yd away, and the client's pin moves with them.
playerPosition = { 0.30, 0.60 }
mapQuests[1413] = { { questID = 894, x = 0.301, y = 0.604 } }
objectives[894] = { { text = "Claws: 2/4" } }
POILog:OnQuestLogUpdate()
POILog:ProbeQuest(894)

local camps = POILog:ClusterObservations(894, "objective")
assert(#camps == 2, "two camps 600 yd apart are two places, not one")
assert(camps[1].medianPinGap < 50 and camps[2].medianPinGap < 50,
    "the pin was near the player in both, which is a pin that follows rather than a fixed one")
local clusterSummary = POILog:ClusterSummary()
assert(clusterSummary.quests == 1 and clusterSummary.multiPlace == 1 and clusterSummary.multiMap == 0)
assert(clusterSummary.pinFollowed == 1 and clusterSummary.pinStayed == 0)
assert(clusterSummary.pinPlaces == 1, "and the client itself pinned the quest in two distinct places")

-- A pin that stays on the first camp while the player moves to the second
-- reads as "near in some, far in others" instead.
POILog:Clear()
objectives[894] = { { text = "Claws: 0/4" } }
playerPosition = { 0.30, 0.30 }
mapQuests[1413] = { { questID = 894, x = 0.305, y = 0.302 } }
POILog:OnQuestLogUpdate()
objectives[894] = { { text = "Claws: 1/4" } }
POILog:OnQuestLogUpdate()
playerPosition = { 0.30, 0.60 }
objectives[894] = { { text = "Claws: 2/4" } }
POILog:OnQuestLogUpdate()
local fixed = POILog:ClusterSummary()
assert(fixed.multiPlace == 1 and fixed.pinStayed == 1 and fixed.pinFollowed == 0)
inLog[894], playerPosition = nil, nil
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- Whether a guide could stop authoring a coordinate depends on the client
-- answering from where the step begins, so every placement is filed by how
-- far the player was from it at the time.
POILog:Clear()
inLog[895], ready[895] = true, true
waypoints[895] = nil
logQuests = { { questID = 895, title = "Long Walk Home" } }
mapQuests[1413] = { { questID = 895, x = 0.50, y = 0.50 } }

playerPosition = { 0.50, 0.505 }   -- standing on it
POILog:ProbeQuest(895)
playerPosition = { 0.50, 0.90 }    -- 400 yd away
POILog:ProbeQuest(895)
playerPosition = nil               -- the client will not place the player
POILog:ProbeQuest(895)
local range = ns.db.poi.range.ready
assert(range["under 100 yd"] == 1 and range["100-500 yd"] == 1, "each placement is filed by its distance")
assert(range["elsewhere (another map)"] == 1, "a placement the player cannot be compared to is its own band")
assert(POILog.Count(ns.db.poi.range.working) == 0, "a quest ready to hand in is not counted as one being worked")
inLog[895], ready[895], playerPosition = nil, nil, nil
mapQuests[1413] = { { questID = 869, x = 0.46, y = 0.62 } }

-- The report renders without a client, a guide, or a single row.
POILog:Clear()
local lines = POILog:ReportLines()
local report = table.concat(lines, "\n")
assert(#lines > 0 and report:find("nothing sampled yet"))
-- One command carries everything: the parts have their own commands, but the
-- plain report is not allowed to leave any of them out.
assert(report:find("WHERE THINGS ACTUALLY HAPPENED") and report:find("PER%-QUEST DETAIL")
    and report:find("THE CLIENT'S OWN MAP DATA") and report:find("Every row"),
    "the one report holds every section")

-- Sampling needs a database and the client's calls; neither present is quiet.
Client.HasQuestWaypoints = function() return false end
assert(not POILog:Enabled())
POILog:Sync(nodes[2])
assert(#POILog:Rows() == 0, "a client without the calls records nothing")

-- The suites share a Lua state; leave the globals as they were found.
CreateFrame = previousCreateFrame

return true
