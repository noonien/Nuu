local _, ns = ...

-- What the client's own quest waypoints say, recorded on the steps the player
-- actually walks. The question behind it is whether `C_QuestLog.GetNextWaypoint`
-- could stand in for authored coordinates on this client: the calls are in the
-- bindings (see `docs/api-compatibility.md`), but only play says whether the
-- data behind them is there, is on the right map, and lands where the step
-- really is. Asking quest by quest is work, so this asks for the player: every
-- repaint of the tracker samples the current step's quests, and one row per
-- step and quest keeps what came back.
--
-- It is evidence, not a feature. Nothing in the tracker, the arrow, or the
-- guides reads a recorded waypoint; the reads are the `Client:GetQuestWaypoint`
-- family and every one of them is guarded and secret-safe, so a client that
-- answers nothing simply fills the log with blanks - which is itself the
-- answer. `/nuuroad poi` reports it and `/nuuroad poi clear` empties it.
--
-- Pure logic apart from the Client calls: `Reading` builds a row, `Record`
-- files it, and `Summarize` counts rows, so all three are testable outside the
-- client.
local POILog = { lastSampleAt = 0, interval = 3 }

-- Rows kept, oldest dropped first. One row per step and quest, so a guide of
-- 300 steps fits with room for a second guide.
POILog.limit = 600
-- How far a waypoint has to move before it counts as a new answer rather than
-- the same one read again, in map percent.
POILog.movedPercent = 0.2

local function now() return GetTime and GetTime() or 0 end

local function stamp()
    if type(date) ~= "function" then return nil end
    local ok, text = pcall(date, "%m-%d %H:%M")
    return ok and text or nil
end

local function percent(value)
    if type(value) ~= "number" then return nil end
    return math.floor(value * 1000 + 0.5) / 10
end

local function yards(value)
    if type(value) ~= "number" then return nil end
    return math.floor(value + 0.5)
end

function POILog:Store()
    if not ns.db then return nil end
    local store = ns.db.poi or {}
    ns.db.poi = store
    store.rows = store.rows or {}
    store.order = store.order or {}
    -- The sweep's harvest, keyed so a second pass overwrites rather than
    -- doubles: maps by ID, area POIs and flight points by map and ID, and the
    -- quests the client would pin on a map by map and quest.
    store.maps = store.maps or {}
    store.quests = store.quests or {}
    store.pois = store.pois or {}
    store.taxi = store.taxi or {}
    store.mapQuests = store.mapQuests or {}
    store.sweep = store.sweep or { maps = 0, pois = 0, taxi = 0, quests = 0, emptyMaps = 0, done = false }
    -- How far the player was from a quest's pin when the client agreed to
    -- give it. An authored coordinate can only be dropped if the client
    -- answers from wherever the step begins, which is usually not next to the
    -- place it points at.
    store.range = store.range or { ready = {}, working = {} }
    return store
end

local function count(table_)
    local total = 0
    for _ in pairs(table_ or {}) do total = total + 1 end
    return total
end

POILog.Count = count

function POILog:Rows()
    local store = self:Store()
    local rows = {}
    for _, key in ipairs(store and store.order or {}) do
        local row = store.rows[key]
        if row then table.insert(rows, row) end
    end
    return rows
end

function POILog:Clear()
    local store = self:Store()
    if not store then return end
    store.rows, store.order = {}, {}
    store.maps, store.pois, store.taxi, store.mapQuests, store.quests = {}, {}, {}, {}, {}
    store.observed = {}
    store.npcs = {}
    store.range = { ready = {}, working = {} }
    self.objectiveTexts = nil
    store.sweep = { maps = 0, pois = 0, taxi = 0, quests = 0, emptyMaps = 0, done = false }
    self.queue, self.queued = nil, nil
end

-- Yards between two map points, through world coordinates so two maps on one
-- continent can still be compared. Nil when either side cannot be placed or
-- they sit on different continents.
function POILog:GapYards(firstMap, firstX, firstY, secondMap, secondX, secondY)
    local Client = ns.modules.Client
    if not Client or not firstMap or not secondMap then return nil end
    if type(firstX) ~= "number" or type(firstY) ~= "number" then return nil end
    if type(secondX) ~= "number" or type(secondY) ~= "number" then return nil end
    local firstContinent, ax, ay = Client:GetWorldPosition(firstMap, firstX, firstY)
    local secondContinent, bx, by = Client:GetWorldPosition(secondMap, secondX, secondY)
    if not firstContinent or not secondContinent or firstContinent ~= secondContinent then return nil end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function POILog:Key(guideID, stepIndex, questID)
    return tostring(guideID) .. "#" .. tostring(stepIndex) .. "#" .. tostring(questID)
end

-- A quest is not pinned on one map. It can be pinned on its zone map, on the
-- continent above it (where the pin marks the zone rather than the spot), on
-- a neighbouring zone when the objective straddles a border, and more than
-- once on any of them. So the maps are asked in the order that makes the
-- answer most useful - the step's own map first, then the map the client
-- files the quest under, then the map underfoot, then any map a sweep has
-- seen pin it - and what the other maps said is kept alongside.
function POILog:PlaceQuest(questID, candidates)
    local Client, store = ns.modules.Client, self:Store()
    if not Client then return nil end
    local seen, tried, best = {}, {}, nil
    local function ask(mapID)
        if type(mapID) ~= "number" or seen[mapID] then return end
        seen[mapID] = true
        local x, y, pins = Client:GetQuestPinOnMap(questID, mapID)
        if not x then return end
        local swept = store and store.maps[tostring(mapID)]
        local info = Client:GetMapInfoTable(mapID)
        local entry = { mapID = mapID, x = x, y = y, pins = pins or 1,
            mapType = (info and info.mapType) or (swept and swept.mapType) }
        table.insert(tried, entry)
        -- The first map asked that answers is the one the row is built from;
        -- the rest are recorded as also-placing, since a continent pin and a
        -- zone pin are different facts about the same quest.
        best = best or entry
    end
    -- A map's parents are asked too: a quest is often pinned on the continent
    -- as well as the zone, and the continent pin is the one that exists when
    -- the zone map holds nothing.
    local function askUp(mapID)
        for _ = 1, 3 do
            if type(mapID) ~= "number" or mapID == 0 then return end
            ask(mapID)
            local info = Client:GetMapInfoTable(mapID)
            mapID = info and info.parentMapID
        end
    end
    for _, mapID in ipairs(candidates or {}) do askUp(mapID) end
    askUp(Client:GetQuestMapID(questID))
    askUp(Client:GetCurrentMapID())
    for _, pinned in pairs(store and store.mapQuests or {}) do
        if pinned.quest == questID then ask(pinned.map) end
    end
    if not best then return nil end
    best.maps = #tried
    best.alsoOn = {}
    for _, entry in ipairs(tried) do
        if entry.mapID ~= best.mapID then table.insert(best.alsoOn, entry.mapID) end
    end
    return best
end

-- One reading of one quest of one step: what the guide says, what the client
-- says, and how far apart they are. Returns nil when there is nothing to ask
-- about.
function POILog:Reading(guide, node, questID, role)
    local Client = ns.modules.Client
    if not Client or type(questID) ~= "number" or not node then return nil end
    local location = node.location
    local authoredMap = location and Client:ResolveMapID(location.mapID)
    -- The POI system answers for the map it was last pointed at, so point it
    -- at the step's map before asking anything about the step's quest.
    if authoredMap then Client:SetMapForQuestPOIs(authoredMap) end
    local waypointMap, waypointX, waypointY = Client:GetQuestWaypoint(questID)
    local source = waypointMap and "waypoint" or nil
    -- `GetNextWaypoint` answered nothing before the map was being set, so the map's own pin
    -- list is the fallback and, so far, the only source that says anything.
    -- It is asked on the step's map, which is the map the answer has to be on
    -- for the comparison to mean anything.
    local placed
    if not waypointMap then
        placed = self:PlaceQuest(questID, { authoredMap })
        if placed then waypointMap, waypointX, waypointY, source = placed.mapID, placed.x, placed.y, "pin" end
    end
    local hasPOI, onMap, localPOI = Client:QuestHasPOI(questID)
    local reading = {
        source = source,
        -- Where the player stood when the question was put. The client may
        -- only hold POI data for quests near the player, so an answer of
        -- "nothing" from another continent says less than one from the zone
        -- the quest is in; the report counts asks and answers by this map.
        atMap = Client:GetCurrentMapID(),
        guide = guide and guide.id or "?",
        step = node.index,
        quest = questID,
        role = role,
        kind = node.kind,
        title = ns.modules.Steps and ns.modules.Steps:Title(node) or nil,
        inLog = Client:IsQuestInLog(questID) == true,
        amap = authoredMap,
        ax = percent(location and location.x),
        ay = percent(location and location.y),
        wmap = waypointMap,
        wx = percent(waypointX),
        wy = percent(waypointY),
        text = Client:GetQuestWaypointText(questID),
        poi = hasPOI,
        onMap = onMap,
        localPOI = localPOI,
        blobs = Client:GetQuestPOICount(questID),
        poiMap = Client:GetMapForQuestPOIs(),
        -- How many pins that map holds for the quest, how many maps pin it at
        -- all, which other maps those were, and what kind of map answered: a
        -- continent pin marks a zone, so it is coarse by nature and has to be
        -- told apart from a zone pin.
        pins = placed and placed.pins,
        maps = placed and placed.maps,
        alsoOn = placed and #placed.alsoOn > 0 and placed.alsoOn or nil,
        wmapType = placed and placed.mapType,
    }
    if authoredMap and waypointMap then
        reading.gap = yards(self:GapYards(authoredMap, location.x, location.y, waypointMap, waypointX, waypointY))
        reading.sameMap = authoredMap == waypointMap
    end
    -- The multi-spot picture: how many places the guides put this quest, how
    -- far apart they are, and how near the client's answer came to the
    -- nearest of them. A pin 300 yd from the authored step but 20 yd from
    -- another step of the same quest is not a bad pin, it is a pin on the
    -- other cluster - the case of mobs spawning on two sides of one zone.
    local spots = self:AuthoredSpots(questID)
    if #spots > 0 then
        reading.spots = #spots
        reading.spread = self:SpotSpread(spots)
        if waypointMap then
            local nearest, spot = self:NearestSpot(spots, waypointMap, waypointX, waypointY)
            reading.gapNear = nearest
            reading.nearestStep = spot and (tostring(spot.guide) .. " step " .. tostring(spot.step)) or nil
            reading.nearestRole = spot and spot.role or nil
            -- The same distance measured against each kind of step, so "the
            -- pin is the turn-in NPC" stops being a guess.
            reading.gapAccept = self:NearestSpotOfRole(spots, "accept", waypointMap, waypointX, waypointY)
            reading.gapTurnin = self:NearestSpotOfRole(spots, "turnin", waypointMap, waypointX, waypointY)
            reading.gapObjective = self:NearestSpotOfRole(spots, "objective", waypointMap, waypointX, waypointY)
            local centroid = self:Centroid(spots)
            if centroid then
                reading.gapCentroid = yards(self:GapYards(centroid.mapID, centroid.x, centroid.y, waypointMap, waypointX, waypointY))
                -- Nearer the middle of the quest's places than to any one of
                -- them: the signature of an area centre rather than a spot.
                reading.centroidCloser = reading.gapCentroid ~= nil and reading.gapNear ~= nil
                    and reading.gapCentroid < reading.gapNear
            end
        end
    end
    reading.objectives = #Client:GetQuestObjectives(questID)
    -- Scored against where the game said things happened. This is asked for
    -- every placed quest, not only ones a guide names: the observations are
    -- the yardstick, and they exist whether or not anybody wrote a step.
    if waypointMap then
        local kinds = Client:IsQuestReadyToTurnIn(questID) and { "turnin" } or { "objective", "accept" }
        local observed, entry = self:NearestObservation(questID, kinds, waypointMap, waypointX, waypointY)
        if not observed then
            observed, entry = self:NearestObservation(questID, { "objective", "accept", "turnin" }, waypointMap, waypointX, waypointY)
        end
        reading.gapObserved, reading.observedKind = observed, entry and entry.kind
    end
    -- And the same score for the guide's own coordinate, so the two can be
    -- compared without either being assumed right.
    if #spots > 0 then
        local best
        for _, spot in ipairs(spots) do
            local gap = self:NearestObservation(questID, { "objective", "accept", "turnin" }, spot.mapID, spot.x, spot.y)
            if gap and (not best or gap < best) then best = gap end
        end
        reading.authoredObserved = best
    end
    -- Whether the quest was done when it was asked about: the client pins the
    -- turn-in for a finished quest and the objectives for an unfinished one,
    -- so a reading means nothing without knowing which this was.
    reading.ready = Client:IsQuestReadyToTurnIn(questID) == true
    reading.finished = Client:IsQuestComplete(questID) == true
    -- How near the player was to the client's waypoint while on this step:
    -- the check that a waypoint sitting on the right map is also in the right
    -- place, since the player is standing where the step really happens.
    local Navigation = ns.modules.Navigation
    if waypointMap and Navigation then
        local _, distance, inYards = Navigation:Measure({ mapID = waypointMap, x = waypointX, y = waypointY })
        if inYards then reading.near = yards(distance) end
    end
    return reading
end

-- Everything an answer carries, copied onto the row it belongs to.
local function copyAnswer(row, reading)
    row.wmap, row.wx, row.wy = reading.wmap, reading.wx, reading.wy
    row.gap, row.sameMap, row.text, row.source = reading.gap, reading.sameMap, reading.text, reading.source
    row.pins, row.maps, row.alsoOn, row.wmapType = reading.pins, reading.maps, reading.alsoOn, reading.wmapType
    row.gapNear, row.nearestStep, row.spots, row.spread = reading.gapNear, reading.nearestStep, reading.spots, reading.spread
    row.nearestRole, row.gapAccept, row.gapTurnin, row.gapObjective =
        reading.nearestRole, reading.gapAccept, reading.gapTurnin, reading.gapObjective
    row.gapCentroid, row.centroidCloser = reading.gapCentroid, reading.centroidCloser
    row.gapObserved, row.observedKind, row.authoredObserved =
        reading.gapObserved, reading.observedKind, reading.authoredObserved
    row.ready, row.finished = reading.ready, reading.finished
    row.poi, row.onMap, row.localPOI = reading.poi, reading.onMap, reading.localPOI
    row.blobs, row.objectives, row.poiMap = reading.blobs, reading.objectives, reading.poiMap
end

local function moved(row, reading)
    if row.wmap ~= reading.wmap then return true end
    if row.wx == nil or reading.wx == nil then return row.wx ~= reading.wx end
    return math.abs(row.wx - reading.wx) > POILog.movedPercent
        or math.abs(row.wy - reading.wy) > POILog.movedPercent
end

-- Every ask, counted against the map the player was on at the time, so the
-- log can tell "the client never answers" apart from "the client never
-- answers from over there".
local function tally(row, reading)
    local key = tostring(reading.atMap or "?")
    row.askedOn = row.askedOn or {}
    local entry = row.askedOn[key]
    if not entry then
        entry = { asked = 0, placed = 0 }
        row.askedOn[key] = entry
    end
    entry.asked = entry.asked + 1
    if reading.wmap then
        entry.placed = entry.placed + 1
        row.placedFrom = row.placedFrom or reading.atMap
    else
        row.blanks = (row.blanks or 0) + 1
    end
end

-- Files a reading. The same step and quest keeps one row: a reading that
-- agrees only counts up, and one whose waypoint has moved overwrites the
-- position and counts the move, so a quest whose POI follows its objectives
-- says so without filling the log.
function POILog:Record(reading)
    local store = self:Store()
    if not store or not reading then return nil end
    local key = self:Key(reading.guide, reading.step, reading.quest)
    local row = store.rows[key]
    if not row then
        reading.seen, reading.moves, reading.first, reading.last = 1, 0, stamp(), stamp()
        reading.blanks = 0
        tally(reading, reading)
        store.rows[key] = reading
        table.insert(store.order, key)
        -- Oldest first: the rows in front are steps the player has long left.
        while #store.order > self.limit do
            local dropped = table.remove(store.order, 1)
            store.rows[dropped] = nil
        end
        return reading
    end
    row.seen = (row.seen or 0) + 1
    row.last = stamp() or row.last
    tally(row, reading)
    -- An answer never unsays itself: a row placed once keeps the position, so
    -- a later blank from the far side of the world does not erase it.
    if reading.wmap and not row.wmap then copyAnswer(row, reading) end
    if reading.near and (not row.near or reading.near < row.near) then row.near = reading.near end
    -- Only an answer can move a row. A blank means the client said nothing
    -- this time, which the tallies record; it is not the waypoint moving to
    -- nowhere.
    if reading.wmap and moved(row, reading) then
        row.moves = (row.moves or 0) + 1
        copyAnswer(row, reading)
    end
    -- Counts that do not depend on an answer: the client's blob and objective
    -- counts, and what the guides say, are worth keeping fresh either way.
    row.blobs, row.objectives = reading.blobs or row.blobs, reading.objectives or row.objectives
    row.spots, row.spread = reading.spots or row.spots, reading.spread or row.spread
    row.inLog = row.inLog or reading.inLog
    return row
end

-- The sweep: everything the client itself would draw, map by map, whether or
-- not the player is standing there or has the quest. Area POIs are the world
-- map's own labels, the taxi nodes are every flight point the client knows
-- (not just the learned ones), and the quests on a map are what its pins would
-- show. Together they are the answer to "what could a guide take from the
-- client instead of an author typing it", and none of it is read by anything
-- but the report.
--
-- It walks a queue a few maps at a time on the tracker's beat, so a full pass
-- costs no visible hitch, and it runs once a session unless asked again.
POILog.mapsPerPump = 4
POILog.entryLimit = 5000
POILog.sweepDelay = 15    -- seconds after login before the first pass
POILog.sweepEvery = 300   -- and every five minutes after that, for good
POILog.questLogEvery = 30
POILog.currentMapEvery = 20 -- the map underfoot, oftener than the full pass

-- Every map the client knows, from the cosmic map down. Falls back to walking
-- IDs when a client will not enumerate children, since an empty list would
-- otherwise read as "the client has no maps".
function POILog:MapList()
    local Client = ns.modules.Client
    if not Client then return {} end
    local seen, maps = {}, {}
    local function add(entry)
        if entry and entry.mapID and not seen[entry.mapID] then
            seen[entry.mapID] = true
            table.insert(maps, entry)
        end
    end
    for _, root in ipairs({ 946, 947 }) do -- Cosmic, then Azeroth
        add(Client:GetMapInfoTable(root))
        for _, child in ipairs(Client:GetMapChildren(root)) do add(child) end
    end
    local current = Client:GetCurrentMapID()
    if current then add(Client:GetMapInfoTable(current)) end
    if #maps > 10 then return maps end
    for mapID = 1, 2000 do add(Client:GetMapInfoTable(mapID)) end
    return maps
end

-- One map's worth of the client's own data. Returns how many entries it found,
-- so a map the client has nothing for can be counted as such.
function POILog:SweepMap(entry, inPass)
    local Client, store = ns.modules.Client, self:Store()
    if not Client or not store or not entry or not entry.mapID then return 0 end
    local mapID = entry.mapID
    Client:SetMapForQuestPOIs(mapID)
    local record = store.maps[tostring(mapID)] or { mapID = mapID, reads = 0, best = 0 }
    record.name, record.mapType = entry.name or record.name, entry.mapType or record.mapType
    record.reads = record.reads + 1
    store.maps[tostring(mapID)] = record
    local found = 0
    local function room()
        return count(store.pois) + count(store.taxi) + count(store.mapQuests) < self.entryLimit
    end
    for _, poi in ipairs(Client:GetAreaPOIs(mapID)) do
        if not room() then break end
        store.pois[mapID .. ":" .. tostring(poi.id)] = {
            map = mapID, id = poi.id, name = poi.name,
            x = percent(poi.x), y = percent(poi.y), atlas = poi.atlas,
        }
        found = found + 1
    end
    for _, node in ipairs(Client:GetTaxiNodes(mapID)) do
        if not room() then break end
        store.taxi[mapID .. ":" .. tostring(node.id)] = {
            map = mapID, id = node.id, name = node.name,
            x = percent(node.x), y = percent(node.y),
            faction = node.faction, undiscovered = node.undiscovered,
        }
        found = found + 1
    end
    -- A quest can be pinned more than once on one map, so the index is part
    -- of the key: collapsing them would hide exactly the case where the
    -- client knows about several places and the guide has to choose one.
    local pinCounts = {}
    for _, quest in ipairs(Client:GetQuestsOnMap(mapID)) do
        if not room() then break end
        local index = (pinCounts[quest.questID] or 0) + 1
        pinCounts[quest.questID] = index
        store.mapQuests[mapID .. ":" .. tostring(quest.questID) .. (index > 1 and (":" .. index) or "")] = {
            map = mapID, quest = quest.questID, x = percent(quest.x), y = percent(quest.y), pin = index,
            title = Client:GetQuestTitle(quest.questID), inLog = Client:IsQuestInLog(quest.questID) == true,
        }
        found = found + 1
    end
    -- What this pass found here, and the most any pass ever did: a map that
    -- answers only sometimes is the interesting kind, and overwriting would
    -- hide it.
    record.last, record.best = found, math.max(record.best or 0, found)
    record.at = stamp()
    store.sweep.maps = count(store.maps)
    store.sweep.pois, store.sweep.taxi, store.sweep.quests = count(store.pois), count(store.taxi), count(store.mapQuests)
    if found == 0 and inPass then store.sweep.emptyMaps = (store.sweep.emptyMaps or 0) + 1 end
    return found
end

-- Neither side is ground truth. The packaged guides are ports, and a ported
-- coordinate can be wrong; the client's pin can be an NPC or an area centre.
-- So the log keeps a third source that is nobody's opinion: where the player
-- actually stood when the game said something happened - a quest accepted, an
-- objective advanced, a quest handed in. That is a real position in the world,
-- and both the guide's coordinate and the client's pin can be scored against
-- it without assuming either is right.
POILog.observedLimit = 400
POILog.observedPerQuest = 6

function POILog:Observations(questID)
    local store = self:Store()
    if not store then return {} end
    store.observed = store.observed or {}
    store.npcs = store.npcs or {}
    return store.observed[tostring(questID)] or {}
end

function POILog:RecordObservation(questID, kind, text)
    local Client, store = ns.modules.Client, self:Store()
    if not Client or not store or type(questID) ~= "number" then return nil end
    local mapID = Client:GetCurrentMapID()
    if not mapID then return nil end
    -- `mapID and Client:...` would truncate the pair to one value, which is
    -- how a position loses its y.
    local x, y = Client:GetPlayerMapPosition(mapID)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    store.observed = store.observed or {}
    if count(store.observed) >= self.observedLimit and not store.observed[tostring(questID)] then return nil end
    local list = store.observed[tostring(questID)] or {}
    -- One entry per kind per place: standing still while three objectives tick
    -- should not fill the list with the same position.
    for _, entry in ipairs(list) do
        if entry.kind == kind and entry.map == mapID
            and math.abs(entry.x - percent(x)) < 1 and math.abs(entry.y - percent(y)) < 1 then
            entry.times = (entry.times or 1) + 1
            entry.last = stamp()
            return entry
        end
    end
    if #list >= self.observedPerQuest then table.remove(list, 1) end
    local entry = { kind = kind, map = mapID, x = percent(x), y = percent(y), text = text, times = 1, at = stamp(), last = stamp() }
    -- What the client was saying about this quest at this instant, paired
    -- with the place it actually happened. A pin moves as objectives finish
    -- and again when a quest becomes ready to hand in, so a pin read minutes
    -- later is a different fact; only the pair taken together is evidence.
    entry.ready = Client:IsQuestReadyToTurnIn(questID) == true
    local placed = self:PlaceQuest(questID, { mapID })
    if placed then
        entry.pin = { map = placed.mapID, x = percent(placed.x), y = percent(placed.y), pins = placed.pins }
        entry.pinGap = yards(self:GapYards(mapID, x, y, placed.mapID, placed.x, placed.y))
    end
    entry.blobs = Client:GetQuestPOICount(questID)
    -- Who the player was talking to. A quest is accepted and handed in face to
    -- face, so the target at that moment is the NPC, and its position is the
    -- player's own. Recording it per creature rather than per quest is what
    -- makes a patrolling NPC visible: one quest gives one sighting, but one
    -- NPC usually hands in several.
    entry.npc = Client:GetUnitCreatureID("target")
    entry.npcName = Client:GetUnitName("target")
    if entry.npc and (kind == "accept" or kind == "turnin") then
        self:RecordNPCSighting(entry.npc, entry.npcName, mapID, percent(x), percent(y), questID)
    end
    -- The guide's own coordinate for this kind of event, measured against the
    -- same moment. Scoring a turn-in pin against an objective step (or the
    -- other way round) compares two different things and flatters whichever
    -- side happens to match.
    local spots = self:AuthoredSpots(questID)
    if #spots > 0 then
        local sameKind = self:NearestSpotOfRole(spots, kind, mapID, x, y)
        entry.guideGap = sameKind or self:NearestSpot(spots, mapID, x, y)
        entry.guideSameKind = sameKind ~= nil
    end
    table.insert(list, entry)
    store.observed[tostring(questID)] = list
    local Corrections = ns.modules.GuideCorrections
    if Corrections then Corrections:ConsiderQuest(questID) end
    ns:Log(string.format("quest POI: %s for quest %d observed at map %s %s, %s; client's pin was %s yd away",
        kind, questID, tostring(mapID), tostring(entry.x), tostring(entry.y), tostring(entry.pinGap or "nowhere")))
    return entry
end

-- Where an NPC has been seen, across every time the player talked to it. Some
-- creatures walk a route, so one sighting is a point on that route and not the
-- place to send anybody; several sightings spread far apart are how a walked
-- route announces itself, and the middle of them is the fairest single point.
-- The client will not say where a creature is, so the only position available
-- is the player's own, and it is only worth anything at talking distance.
POILog.npcLimit = 200
POILog.patrolYards = 100

function POILog:RecordNPCSighting(creatureID, name, mapID, x, y, questID)
    local store = self:Store()
    if not store or type(creatureID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    store.npcs = store.npcs or {}
    local key = tostring(creatureID)
    local record = store.npcs[key]
    if not record then
        if count(store.npcs) >= self.npcLimit then return nil end
        record = { id = creatureID, places = {}, quests = {} }
        store.npcs[key] = record
    end
    record.name = name or record.name
    if questID then record.quests[tostring(questID)] = true end
    local known
    for _, place in ipairs(record.places) do
        if place.map == mapID and math.abs(place.x - x) < 0.5 and math.abs(place.y - y) < 0.5 then
            place.times, place.last, known = (place.times or 1) + 1, stamp(), true
            break
        end
    end
    if not known and #record.places < 12 then
        table.insert(record.places, { map = mapID, x = x, y = y, times = 1, at = stamp(), last = stamp() })
    end
    -- How far apart the sightings are, and the middle of them.
    local widest = 0
    for i = 1, #record.places do
        for j = i + 1, #record.places do
            local first, second = record.places[i], record.places[j]
            local gap = self:GapYards(first.map, first.x / 100, first.y / 100, second.map, second.x / 100, second.y / 100)
            if gap and gap > widest then widest = gap end
        end
    end
    record.spread = yards(widest)
    record.roams = (record.spread or 0) > self.patrolYards
    local sumX, sumY, total = 0, 0, 0
    for _, place in ipairs(record.places) do
        if place.map == record.places[1].map then
            sumX, sumY, total = sumX + place.x, sumY + place.y, total + 1
        end
    end
    if total > 0 then
        record.middle = { map = record.places[1].map, x = sumX / total, y = sumY / total, of = total }
    end
    return record
end

function POILog:NPCSighting(creatureID)
    local store = self:Store()
    return store and store.npcs and store.npcs[tostring(creatureID)] or nil
end

-- Every other moment the player is standing next to an NPC: a gossip window, a
-- quest being offered, its progress page, its reward page. Plenty of NPCs give
-- a single quest, so quest events alone would never show that one of them
-- walks; these fill in the repeat sightings.
function POILog:OnDialog()
    if not self:Enabled() then return end
    local Client = ns.modules.Client
    local creatureID = Client:GetUnitCreatureID("target")
    if not creatureID then return end
    local mapID = Client:GetCurrentMapID()
    if not mapID then return end
    local x, y = Client:GetPlayerMapPosition(mapID)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    self:RecordNPCSighting(creatureID, Client:GetUnitName("target"), mapID, percent(x), percent(y))
end

-- The NPCs seen in more than one place, which is what a walked route looks
-- like from outside.
function POILog:NPCLines()
    local store = self:Store() or {}
    local lines = {
        "NPCs, and where they were standing when the player talked to them. A creature seen in several places",
        "walks a route, so no single sighting is its position and a step pointed at one of them is pointed at a",
        "moment rather than a place. The middle of the sightings is the fairest single point for such a creature,",
        "and the spread is what a step's arrival radius has to cover.",
        "",
    }
    local records = {}
    for _, record in pairs(store.npcs or {}) do table.insert(records, record) end
    table.sort(records, function(left, right) return (left.id or 0) < (right.id or 0) end)
    table.insert(lines, "NPCs seen: " .. #records)
    for _, record in ipairs(records) do
        local quests = {}
        for questID in pairs(record.quests or {}) do table.insert(quests, questID) end
        table.sort(quests)
        table.insert(lines, "")
        table.insert(lines, string.format("[%s] %s%s | %d sighting(s), spread %s yd | quests %s", tostring(record.id),
            tostring(record.name), record.roams and "  -- WALKS A ROUTE" or "", #record.places,
            tostring(record.spread or 0), #quests > 0 and table.concat(quests, ", ") or "-"))
        for _, place in ipairs(record.places) do
            table.insert(lines, string.format("  map %-6s %s, %s  x%d  %s", tostring(place.map),
                tostring(place.x), tostring(place.y), place.times or 1, tostring(place.at)))
        end
        if record.middle and #record.places > 1 then
            table.insert(lines, string.format("  middle of %d sighting(s): map %s %.1f, %.1f -> authored form: at = { %.1f, %.1f }%s",
                record.middle.of, tostring(record.middle.map), record.middle.x, record.middle.y,
                record.middle.x, record.middle.y,
                record.roams and string.format(", radius = %d", math.max(math.floor((record.spread or 0) / 2 + 0.5), 20)) or ""))
        end
    end
    return lines
end

-- The nearest observation of a kind to a point, in yards.
function POILog:NearestObservation(questID, kinds, mapID, x, y)
    local best, bestEntry
    for _, entry in ipairs(self:Observations(questID)) do
        local wanted = false
        for _, kind in ipairs(kinds) do wanted = wanted or entry.kind == kind end
        if wanted then
            local gap = self:GapYards(entry.map, entry.x / 100, entry.y / 100, mapID, x, y)
            if gap and (not best or gap < best) then best, bestEntry = gap, entry end
        end
    end
    return yards(best), bestEntry
end

-- The game's own word that something happened, wired from the events the
-- audit frame already listens to.
function POILog:OnQuestAccepted(questID)
    if self:Enabled() then self:RecordObservation(tonumber(questID), "accept") end
end

function POILog:OnQuestTurnedIn(questID)
    if self:Enabled() then self:RecordObservation(tonumber(questID), "turnin") end
end

-- An objective line that changed since the last look means progress was made
-- where the player is standing now. The text is kept so a later reading can
-- say which objective it was.
function POILog:OnQuestLogUpdate()
    if not self:Enabled() then return end
    local Client = ns.modules.Client
    -- `QUEST_ACCEPTED` fires before the quest is in the log, so the client has
    -- nothing to pin at that instant. The pin is taken on the next look, which
    -- is still the same place and the same moment for the player's purposes.
    local store = self:Store()
    for key, list in pairs(store and store.observed or {}) do
        for _, entry in ipairs(list) do
            if not entry.pin and not entry.pinFilled then
                local placed = self:PlaceQuest(tonumber(key), { entry.map })
                if placed then
                    entry.pin = { map = placed.mapID, x = percent(placed.x), y = percent(placed.y), pins = placed.pins }
                    entry.pinGap = yards(self:GapYards(entry.map, entry.x / 100, entry.y / 100, placed.mapID, placed.x, placed.y))
                    entry.pinFilled = true
                end
            end
        end
    end
    self.objectiveTexts = self.objectiveTexts or {}
    for _, entry in ipairs(Client:GetQuestLogEntries()) do
        local questID = entry.questID
        local seen = self.objectiveTexts[questID] or {}
        for index, objective in ipairs(Client:GetQuestObjectives(questID)) do
            local text = objective.text
            if type(text) == "string" and seen[index] ~= nil and seen[index] ~= text then
                self:RecordObservation(questID, "objective", text)
            end
            seen[index] = text
        end
        self.objectiveTexts[questID] = seen
    end
end

-- The maps worth asking about one quest: where the guides put it and the maps
-- above those, the map the client files it under, the map underfoot, and any
-- map a sweep saw pin it.
function POILog:CandidateMaps(questID, spots)
    local Client, store = ns.modules.Client, self:Store()
    local seen, order = {}, {}
    local function consider(mapID)
        if type(mapID) ~= "number" or mapID == 0 or seen[mapID] then return end
        seen[mapID] = true
        table.insert(order, mapID)
    end
    if not Client then return order end
    for _, spot in ipairs(spots or {}) do
        consider(spot.mapID)
        local info = Client:GetMapInfoTable(spot.mapID)
        consider(info and info.parentMapID)
    end
    consider(Client:GetQuestMapID(questID))
    local current = Client:GetCurrentMapID()
    consider(current)
    local currentInfo = current and Client:GetMapInfoTable(current)
    consider(currentInfo and currentInfo.parentMapID)
    for _, pinned in pairs(store and store.mapQuests or {}) do
        if pinned.quest == questID then consider(pinned.map) end
    end
    return order
end

-- Distance bands, in yards, for "how far away was the player when the client
-- still answered". `elsewhere` is another map entirely, which is the case a
-- turn-in step usually starts from.
POILog.rangeBands = { { 100, "under 100 yd" }, { 500, "100-500 yd" }, { 2000, "500-2000 yd" }, { math.huge, "over 2000 yd" } }

function POILog:RecordRange(questID, ready, mapID, x, y)
    local Client, store = ns.modules.Client, self:Store()
    if not Client or not store then return end
    local playerMap = Client:GetCurrentMapID()
    if not playerMap then return end
    local bucket = ready and store.range.ready or store.range.working
    local px, py = Client:GetPlayerMapPosition(playerMap)
    local band = "elsewhere (another map)"
    if type(px) == "number" and type(py) == "number" then
        local gap = self:GapYards(playerMap, px, py, mapID, x, y)
        if gap then
            for _, entry in ipairs(self.rangeBands) do
                if gap < entry[1] then band = entry[2] break end
            end
        end
    end
    bucket[band] = (bucket[band] or 0) + 1
end

-- One quest, asked of every map that could answer, recorded as it goes. This
-- is the per-quest view collected rather than typed: for each map, every pin
-- it holds with the distance to the nearest place a guide puts the quest, the
-- blob count that map yields, and what `GetNextWaypoint` says with the POI
-- system pointed there. The most pins any map ever gave is kept, so a client
-- that models two clusters shows it even if a later read gives one.
POILog.questDetailLimit = 300
function POILog:ProbeQuest(questID)
    local Client, store = ns.modules.Client, self:Store()
    if not Client or not store or type(questID) ~= "number" then return nil end
    store.quests = store.quests or {}
    local key = tostring(questID)
    local record = store.quests[key]
    if not record then
        if count(store.quests) >= self.questDetailLimit then return nil end
        record = { quest = questID, maps = {}, first = stamp() }
        store.quests[key] = record
    end
    local spots = self:AuthoredSpots(questID)
    record.title = Client:GetQuestTitle(questID) or record.title
    record.inLog = Client:IsQuestInLog(questID) == true
    record.ready = Client:IsQuestReadyToTurnIn(questID) == true
    record.objectives = #Client:GetQuestObjectives(questID)
    record.spots, record.spread = #spots, self:SpotSpread(spots)
    record.last = stamp()
    record.reads = (record.reads or 0) + 1
    for _, mapID in ipairs(self:CandidateMaps(questID, spots)) do
        Client:SetMapForQuestPOIs(mapID)
        local info = Client:GetMapInfoTable(mapID)
        local pins = Client:GetQuestPinsOnMap(questID, mapID)
        local entry = record.maps[tostring(mapID)] or { map = mapID, best = 0 }
        entry.name, entry.type = (info and info.name) or entry.name, (info and info.mapType) or entry.type
        entry.reads = (entry.reads or 0) + 1
        entry.blobs = Client:GetQuestPOICount(questID)
        local waypointMap, wx, wy = Client:GetQuestWaypoint(questID)
        if waypointMap then entry.waypoint = { map = waypointMap, x = percent(wx), y = percent(wy) } end
        if #pins > 0 then
            entry.pins = {}
            for _, pin in ipairs(pins) do
                local nearest, spot = self:NearestSpot(spots, mapID, pin.x, pin.y)
                table.insert(entry.pins, { x = percent(pin.x), y = percent(pin.y), near = nearest,
                    step = spot and (tostring(spot.guide) .. " step " .. tostring(spot.step)) or nil })
                -- Every distinct place this quest has ever been pinned, not
                -- only the latest. A quest whose mobs spawn in several places
                -- shows here as the pin moving between them; one that never
                -- moves is the client naming a single spot whatever the
                -- player does.
                entry.seenAt = entry.seenAt or {}
                local known
                for _, place in ipairs(entry.seenAt) do
                    if math.abs(place.x - percent(pin.x)) < 1 and math.abs(place.y - percent(pin.y)) < 1 then
                        place.times, place.last, known = (place.times or 1) + 1, stamp(), true
                        break
                    end
                end
                if not known and #entry.seenAt < 12 then
                    table.insert(entry.seenAt, { x = percent(pin.x), y = percent(pin.y), times = 1, at = stamp(), last = stamp() })
                end
            end
            entry.best = math.max(entry.best or 0, #pins)
        end
        record.maps[tostring(mapID)] = entry
        if entry.blobs and entry.blobs > (record.blobs or 0) then record.blobs = entry.blobs end
        if #pins > 0 then self:RecordRange(questID, record.ready, mapID, pins[1].x, pins[1].y) end
    end
    record.blobs = record.blobs or 0
    return record
end

-- Every quest in the log, not only the ones the current step names: the same
-- row shape, filed under the log rather than a guide step, so a quest the
-- player is carrying is on record even when no step is about it.
function POILog:QuestLogReading(questID)
    local Client = ns.modules.Client
    if not Client or type(questID) ~= "number" then return nil end
    local waypointMap, waypointX, waypointY = Client:GetQuestWaypoint(questID)
    local source = waypointMap and "waypoint" or nil
    local currentMap = Client:GetCurrentMapID()
    local placed
    local hasPOI, onMap, localPOI = Client:QuestHasPOI(questID)
    -- No step is in front of the player, but a guide still knows where this
    -- quest is done, so the comparison is made against that.
    local authored = self:AuthoredFor(questID)
    if not waypointMap then
        placed = self:PlaceQuest(questID, { authored and authored.mapID })
        if placed then waypointMap, waypointX, waypointY, source = placed.mapID, placed.x, placed.y, "pin" end
    end
    local reading = {
        source = source,
        atMap = currentMap,
        guide = "log", step = "-", quest = questID, role = "log",
        kind = "questlog", title = Client:GetQuestTitle(questID),
        inLog = true,
        wmap = waypointMap, wx = percent(waypointX), wy = percent(waypointY),
        text = Client:GetQuestWaypointText(questID),
        poi = hasPOI, onMap = onMap, localPOI = localPOI,
        blobs = Client:GetQuestPOICount(questID),
        pins = placed and placed.pins,
        maps = placed and placed.maps,
        alsoOn = placed and #placed.alsoOn > 0 and placed.alsoOn or nil,
        wmapType = placed and placed.mapType,
    }
    -- The multi-spot picture: how many places the guides put this quest, how
    -- far apart they are, and how near the client's answer came to the
    -- nearest of them. A pin 300 yd from the authored step but 20 yd from
    -- another step of the same quest is not a bad pin, it is a pin on the
    -- other cluster - the case of mobs spawning on two sides of one zone.
    local spots = self:AuthoredSpots(questID)
    if #spots > 0 then
        reading.spots = #spots
        reading.spread = self:SpotSpread(spots)
        if waypointMap then
            local nearest, spot = self:NearestSpot(spots, waypointMap, waypointX, waypointY)
            reading.gapNear = nearest
            reading.nearestStep = spot and (tostring(spot.guide) .. " step " .. tostring(spot.step)) or nil
            reading.nearestRole = spot and spot.role or nil
            -- The same distance measured against each kind of step, so "the
            -- pin is the turn-in NPC" stops being a guess.
            reading.gapAccept = self:NearestSpotOfRole(spots, "accept", waypointMap, waypointX, waypointY)
            reading.gapTurnin = self:NearestSpotOfRole(spots, "turnin", waypointMap, waypointX, waypointY)
            reading.gapObjective = self:NearestSpotOfRole(spots, "objective", waypointMap, waypointX, waypointY)
            local centroid = self:Centroid(spots)
            if centroid then
                reading.gapCentroid = yards(self:GapYards(centroid.mapID, centroid.x, centroid.y, waypointMap, waypointX, waypointY))
                -- Nearer the middle of the quest's places than to any one of
                -- them: the signature of an area centre rather than a spot.
                reading.centroidCloser = reading.gapCentroid ~= nil and reading.gapNear ~= nil
                    and reading.gapCentroid < reading.gapNear
            end
        end
    end
    reading.objectives = #Client:GetQuestObjectives(questID)
    -- Scored against where the game said things happened. This is asked for
    -- every placed quest, not only ones a guide names: the observations are
    -- the yardstick, and they exist whether or not anybody wrote a step.
    if waypointMap then
        local kinds = Client:IsQuestReadyToTurnIn(questID) and { "turnin" } or { "objective", "accept" }
        local observed, entry = self:NearestObservation(questID, kinds, waypointMap, waypointX, waypointY)
        if not observed then
            observed, entry = self:NearestObservation(questID, { "objective", "accept", "turnin" }, waypointMap, waypointX, waypointY)
        end
        reading.gapObserved, reading.observedKind = observed, entry and entry.kind
    end
    -- And the same score for the guide's own coordinate, so the two can be
    -- compared without either being assumed right.
    if #spots > 0 then
        local best
        for _, spot in ipairs(spots) do
            local gap = self:NearestObservation(questID, { "objective", "accept", "turnin" }, spot.mapID, spot.x, spot.y)
            if gap and (not best or gap < best) then best = gap end
        end
        reading.authoredObserved = best
    end
    -- Whether the quest was done when it was asked about: the client pins the
    -- turn-in for a finished quest and the objectives for an unfinished one,
    -- so a reading means nothing without knowing which this was.
    reading.ready = Client:IsQuestReadyToTurnIn(questID) == true
    reading.finished = Client:IsQuestComplete(questID) == true
    if authored then
        reading.amap, reading.ax, reading.ay = authored.mapID, percent(authored.x), percent(authored.y)
        reading.against = authored.guide .. " step " .. tostring(authored.step) .. " (" .. tostring(authored.role) .. ")"
        if waypointMap then
            reading.gap = yards(self:GapYards(authored.mapID, authored.x, authored.y, waypointMap, waypointX, waypointY))
            reading.sameMap = authored.mapID == waypointMap
        end
    end
    return reading
end

-- Where a guide puts a quest, for a quest nobody is standing on. Every packaged
-- guide is indexed by quest, so a quest merely sitting in the log can still be
-- compared against authored coordinates: the objective step first, since that
-- is the reading the client's pin is really competing with, then whatever step
-- of the quest has coordinates at all.
-- Every place any guide puts a quest, including the extra points of a
-- circuit. A quest whose mobs spawn on two sides of one zone is authored as
-- two steps in the same zone, and that is the case the client's single pin
-- may or may not model: if it does, it shows up as several pins or several
-- blobs; if it does not, the pin sits near one cluster or between both.
function POILog:AuthoredSpots(questID)
    local QuestIndex, Client = ns.modules.QuestIndex, ns.modules.Client
    local spots = {}
    if not QuestIndex or not Client or type(questID) ~= "number" then return spots end
    for _, entry in ipairs(QuestIndex:GuidesFor(questID)) do
        for _, step in ipairs(entry.steps or {}) do
            local node = entry.guide and entry.guide.nodes and entry.guide.nodes[step.index]
            local location = node and node.location
            if location then
                local mapID = Client:ResolveMapID(location.mapID)
                table.insert(spots, { mapID = mapID, x = location.x, y = location.y,
                    guide = entry.guide.id, step = step.index, role = step.role })
                for _, extra in ipairs(location.spots or {}) do
                    table.insert(spots, { mapID = mapID, x = extra.x, y = extra.y,
                        guide = entry.guide.id, step = step.index, role = step.role, extra = true })
                end
            end
        end
    end
    return spots
end

-- How far apart the authored places are, and how near the client's answer
-- comes to the nearest of them. The spread is what says "this quest happens
-- in more than one place"; the nearest gap is the fair reading of a pin when
-- it does.
function POILog:SpotSpread(spots)
    local widest = 0
    for i = 1, math.min(#spots, 8) do
        for j = i + 1, math.min(#spots, 8) do
            local gap = self:GapYards(spots[i].mapID, spots[i].x, spots[i].y, spots[j].mapID, spots[j].x, spots[j].y)
            if gap and gap > widest then widest = gap end
        end
    end
    return yards(widest)
end

-- The middle of everywhere a guide sends the player for a quest, on the map
-- that holds most of those places. A pin for an unfinished quest is not the
-- quest giver and is not any one authored spot, so the remaining candidate is
-- the middle of the quest's area - which this measures instead of leaving it
-- to be read off a list of distances.
function POILog:Centroid(spots)
    local byMap, counts = {}, {}
    for _, spot in ipairs(spots) do
        local key = spot.mapID
        if key then
            local sum = byMap[key] or { x = 0, y = 0, n = 0 }
            sum.x, sum.y, sum.n = sum.x + spot.x, sum.y + spot.y, sum.n + 1
            byMap[key] = sum
            counts[key] = sum.n
        end
    end
    local bestMap, bestCount
    for mapID, total in pairs(counts) do
        if not bestCount or total > bestCount then bestMap, bestCount = mapID, total end
    end
    if not bestMap or bestCount < 2 then return nil end
    local sum = byMap[bestMap]
    return { mapID = bestMap, x = sum.x / sum.n, y = sum.y / sum.n, spots = sum.n }
end

-- The nearest authored spot of one role. A pin that keeps landing on the
-- turn-in step of every quest is the client pinning the turn-in NPC, not the
-- objectives - which is what the numbers below are for.
function POILog:NearestSpotOfRole(spots, role, mapID, x, y)
    local ofRole = {}
    for _, spot in ipairs(spots) do
        if spot.role == role then table.insert(ofRole, spot) end
    end
    if #ofRole == 0 then return nil end
    return self:NearestSpot(ofRole, mapID, x, y)
end

function POILog:NearestSpot(spots, mapID, x, y)
    local best, bestSpot
    for _, spot in ipairs(spots) do
        local gap = self:GapYards(spot.mapID, spot.x, spot.y, mapID, x, y)
        if gap and (not best or gap < best) then best, bestSpot = gap, spot end
    end
    return yards(best), bestSpot
end

function POILog:AuthoredFor(questID)
    local QuestIndex, Client = ns.modules.QuestIndex, ns.modules.Client
    if not QuestIndex or not Client or type(questID) ~= "number" then return nil end
    local preference = { objective = 1, collect = 2, turnin = 3, track = 4, step = 5, accept = 6 }
    local best, bestRank, bestEntry, bestStep
    for _, entry in ipairs(QuestIndex:GuidesFor(questID)) do
        for _, step in ipairs(entry.steps or {}) do
            local node = entry.guide and entry.guide.nodes and entry.guide.nodes[step.index]
            local location = node and node.location
            local rank = preference[step.role] or 9
            if location and (not bestRank or rank < bestRank) then
                best, bestRank, bestEntry, bestStep = location, rank, entry, step
            end
        end
    end
    if not best then return nil end
    return { mapID = Client:ResolveMapID(best.mapID), x = best.x, y = best.y,
        guide = bestEntry.guide.id, step = bestStep.index, role = bestStep.role }
end

function POILog:SweepQuestLog()
    local Client = ns.modules.Client
    if not Client then return 0 end
    local recorded = 0
    for _, entry in ipairs(Client:GetQuestLogEntries()) do
        local reading = self:QuestLogReading(entry.questID)
        if reading then
            reading.title = reading.title or entry.title
            self:Record(reading)
            -- The per-quest detail, collected rather than asked for: every map
            -- that could place this quest, and every pin each one holds.
            self:ProbeQuest(entry.questID)
            recorded = recorded + 1
        end
    end
    return recorded
end

-- Queues a full pass. Called once a session from the beat, and by
-- `/nuuroad poi sweep`.
function POILog:StartSweep()
    if not self:Enabled() then return 0 end
    local store = self:Store()
    self.queue, self.queued = self:MapList(), true
    store.sweep.done = false
    -- Per pass, so a second sweep does not add its empty maps to the first's.
    store.sweep.emptyMaps = 0
    store.sweep.passes = (store.sweep.passes or 0) + 1
    return #self.queue
end

-- A few maps per beat. Also re-reads the quest log on its own timer, so a
-- quest picked up between steps is on record.
function POILog:Pump()
    if not self:Enabled() then return end
    local store = self:Store()
    local Client = ns.modules.Client
    local at = now()
    self.startedAt = self.startedAt or at
    -- Sweeps repeat for as long as the session lasts. The client's answer is
    -- not a constant: it may depend on where the player is standing, what is
    -- loaded, and what the server has sent, so one pass settles nothing and
    -- the log is built to show a later pass disagreeing with an earlier one.
    local due = self.lastSweepAt and (at - self.lastSweepAt > self.sweepEvery)
        or (not self.queued and at - self.startedAt > self.sweepDelay)
    if due and (not self.queue or #self.queue == 0) then
        self.lastSweepAt = at
        local queued = self:StartSweep()
        ns:Log("quest POI sweep " .. tostring(store.sweep.passes) .. ": " .. queued .. " maps to read")
    end
    if at - (self.lastQuestLogAt or 0) > self.questLogEvery then
        self.lastQuestLogAt = at
        self:SweepQuestLog()
    end
    -- The map underfoot on its own beat, and immediately when it changes:
    -- whatever the client only answers for nearby, this is where it shows.
    local current = Client and Client:GetCurrentMapID()
    if current and (current ~= self.lastMap or at - (self.lastMapAt or 0) > self.currentMapEvery) then
        if current ~= self.lastMap then
            self.lastQuestLogAt = 0 -- a new map is a reason to ask the whole log again
            ns:Log("quest POI: map changed to " .. tostring(current) .. ", asking again from here")
        end
        self.lastMap, self.lastMapAt = current, at
        self:SweepMap(Client:GetMapInfoTable(current) or { mapID = current })
    end
    local queue = self.queue
    if not queue or #queue == 0 then
        if queue and not store.sweep.done then
            store.sweep.done = true
            store.sweep.lastFinished = stamp()
            ns:Log(string.format("quest POI sweep: %d maps, %d area POIs, %d flight points, %d map quests (%d maps had nothing)",
                store.sweep.maps, store.sweep.pois, store.sweep.taxi, store.sweep.quests, store.sweep.emptyMaps or 0))
        end
        return
    end
    for _ = 1, self.mapsPerPump do
        local entry = table.remove(queue, 1)
        if not entry then break end
        self:SweepMap(entry, true)
    end
end

function POILog:Enabled()
    local Client = ns.modules.Client
    return ns.db ~= nil and Client ~= nil and Client:HasQuestWaypoints()
end

-- Called from the tracker's repaint with the step it has just drawn. Throttled,
-- because a repaint can happen several times a second and the answer moves
-- with the player, not with the frame.
function POILog:Sync(node)
    if not node or not self:Enabled() then return end
    local at = now()
    if at - (self.lastSampleAt or 0) < self.interval then return end
    self.lastSampleAt = at
    local Progress, QuestIndex = ns.modules.Progress, ns.modules.QuestIndex
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    if not guide or not QuestIndex then return end
    for _, quest in ipairs(QuestIndex:NodeQuests(node)) do
        local reading = self:Reading(guide, node, quest.id, quest.role)
        if reading then
            self:Record(reading)
            self:ProbeQuest(quest.id)
            local Corrections = ns.modules.GuideCorrections
            if Corrections then Corrections:Consider(guide, node, quest.id, quest.role) end
        end
    end
end

-- The counts that answer the question. Rows whose quest was never in the log
-- are held apart: the client has no reason to place a quest the player has
-- not taken, so they are not evidence against the data.
function POILog:Summarize(rows)
    local summary = {
        rows = 0, inLog = 0, answered = 0, blank = 0, notInLog = 0,
        fromWaypoint = 0, fromPin = 0, multiPin = 0, multiMap = 0, onZoneMap = 0, onWiderMap = 0,
        multiSpot = 0, multiSpotPinnedOnce = 0, multiSpotBlobbed = 0, nearerOtherSpot = 0, blobbed = 0,
        -- Which kind of authored step the pin turned out to be nearest to,
        -- split by whether the quest was ready to hand in when it was asked.
        nearestByRole = {}, readyPlaced = 0, readyNearTurnin = 0, readyOnTurnin = 0,
        unreadyPlaced = 0, unreadyNearObjective = 0, centroidCloser = 0, centroidMeasured = 0,
        -- Scored against where the game said things happened. Neither the
        -- guide nor the client is assumed right, so both are counted the
        -- same way against the same third source.
        observedCompared = 0, clientNearObserved = 0, authoredNearObserved = 0,
        clientBeatAuthored = 0, authoredBeatClient = 0,
        wrongMap = 0, notComparable = 0, noCoordinates = 0, moved = 0,
        near = 0, close = 0, far = 0, distant = 0, worst = {},
        roles = {}, roleOrder = {}, byPlayerMap = {},
    }
    local function asked(row)
        for mapID, entry in pairs(row.askedOn or {}) do
            local tallied = summary.byPlayerMap[mapID]
            if not tallied then
                tallied = { asked = 0, placed = 0 }
                summary.byPlayerMap[mapID] = tallied
            end
            tallied.asked = tallied.asked + (entry.asked or 0)
            tallied.placed = tallied.placed + (entry.placed or 0)
        end
    end
    -- Per role, because the roles are not the same question. A quest being
    -- accepted is not in the log yet, so the client has nothing to say about
    -- it and never will; a turn-in is in the log and complete, which is when
    -- the client's own pin points at the turn-in NPC; an objective is the one
    -- the guide's coordinates are really competing with.
    local function role(row)
        local name = row.role or "step"
        local entry = summary.roles[name]
        if not entry then
            entry = { rows = 0, inLog = 0, answered = 0, blank = 0, notInLog = 0, usable = 0 }
            summary.roles[name] = entry
            table.insert(summary.roleOrder, name)
        end
        entry.rows = entry.rows + 1
        return entry
    end
    for _, row in ipairs(rows) do
        summary.rows = summary.rows + 1
        asked(row)
        local roleEntry = role(row)
        if row.inLog then
            roleEntry.inLog = roleEntry.inLog + 1
            if row.wmap then
                roleEntry.answered = roleEntry.answered + 1
                -- Usable means it could carry an arrow: right map, and near
                -- enough to the authored point to be the same place.
                if row.sameMap and row.gap and row.gap < 150 then roleEntry.usable = roleEntry.usable + 1 end
            else
                roleEntry.blank = roleEntry.blank + 1
            end
        else
            roleEntry.notInLog = roleEntry.notInLog + 1
        end
        if not row.inLog then
            summary.notInLog = summary.notInLog + 1
        else
            summary.inLog = summary.inLog + 1
            if not row.wmap then
                summary.blank = summary.blank + 1
            else
                summary.answered = summary.answered + 1
                if row.source == "pin" then summary.fromPin = summary.fromPin + 1 else summary.fromWaypoint = summary.fromWaypoint + 1 end
                if (row.pins or 1) > 1 then summary.multiPin = summary.multiPin + 1 end
                if (row.maps or 1) > 1 then summary.multiMap = summary.multiMap + 1 end
                -- Map types: 3 and above are zones and below them, 2 is a
                -- continent, where one pin stands for a whole zone.
                if row.wmapType and row.wmapType >= 3 then summary.onZoneMap = summary.onZoneMap + 1
                elseif row.wmapType then summary.onWiderMap = summary.onWiderMap + 1 end
                if (row.blobs or 0) > 1 then summary.blobbed = summary.blobbed + 1 end
                -- The case that decides whether a single pin can carry a
                -- quest whose work happens in two places.
                if (row.spots or 0) > 1 and (row.spread or 0) > 150 then
                    summary.multiSpot = summary.multiSpot + 1
                    if (row.pins or 1) <= 1 then summary.multiSpotPinnedOnce = summary.multiSpotPinnedOnce + 1 end
                    if (row.blobs or 0) > 1 then summary.multiSpotBlobbed = summary.multiSpotBlobbed + 1 end
                end
                -- A pin that is nearer a different step of the same quest than
                -- the one it was measured against: the pin is on another
                -- cluster, not simply wrong.
                if row.gap and row.gapNear and row.gap - row.gapNear > 100 then
                    summary.nearerOtherSpot = summary.nearerOtherSpot + 1
                end
                if row.nearestRole then
                    summary.nearestByRole[row.nearestRole] = (summary.nearestByRole[row.nearestRole] or 0) + 1
                end
                -- The hypothesis, counted: a finished quest should pin its
                -- turn-in, an unfinished one its objectives.
                if row.gapObserved and row.authoredObserved then
                    summary.observedCompared = summary.observedCompared + 1
                    if row.gapObserved < 150 then summary.clientNearObserved = summary.clientNearObserved + 1 end
                    if row.authoredObserved < 150 then summary.authoredNearObserved = summary.authoredNearObserved + 1 end
                    -- A disagreement is only evidence about the guide once
                    -- something outside it says which side was nearer.
                    if row.gapObserved + 50 < row.authoredObserved then summary.clientBeatAuthored = summary.clientBeatAuthored + 1
                    elseif row.authoredObserved + 50 < row.gapObserved then summary.authoredBeatClient = summary.authoredBeatClient + 1 end
                end
                if row.gapCentroid then
                    summary.centroidMeasured = summary.centroidMeasured + 1
                    if row.centroidCloser then summary.centroidCloser = summary.centroidCloser + 1 end
                end
                if row.ready then
                    summary.readyPlaced = summary.readyPlaced + 1
                    if row.gapTurnin and row.gapTurnin < 150 then summary.readyNearTurnin = summary.readyNearTurnin + 1 end
                    if row.gapTurnin and row.gapTurnin < 50 then summary.readyOnTurnin = summary.readyOnTurnin + 1 end
                else
                    summary.unreadyPlaced = summary.unreadyPlaced + 1
                    if row.gapObjective and row.gapObjective < 150 then summary.unreadyNearObjective = summary.unreadyNearObjective + 1 end
                end
                if (row.moves or 0) > 0 then summary.moved = summary.moved + 1 end
                if row.ax == nil then
                    summary.noCoordinates = summary.noCoordinates + 1
                elseif row.sameMap == false then
                    summary.wrongMap = summary.wrongMap + 1
                    table.insert(summary.worst, row)
                elseif row.gap == nil then
                    summary.notComparable = summary.notComparable + 1
                elseif row.gap < 50 then
                    summary.near = summary.near + 1
                elseif row.gap < 150 then
                    summary.close = summary.close + 1
                elseif row.gap < 500 then
                    summary.far = summary.far + 1
                    table.insert(summary.worst, row)
                else
                    summary.distant = summary.distant + 1
                    table.insert(summary.worst, row)
                end
            end
        end
    end
    table.sort(summary.roleOrder)
    table.sort(summary.worst, function(left, right)
        local a = left.sameMap == false and math.huge or (left.gap or 0)
        local b = right.sameMap == false and math.huge or (right.gap or 0)
        if a == b then return tostring(left.step) < tostring(right.step) end
        return a > b
    end)
    return summary
end

local function describe(row)
    local where = row.wmap and string.format("map %s %s, %s", tostring(row.wmap), tostring(row.wx), tostring(row.wy)) or "nothing"
    local authored = row.ax and string.format("map %s %s, %s", tostring(row.amap), tostring(row.ax), tostring(row.ay)) or "no coordinates"
    local gap = (row.sameMap == false and "another map")
        or (row.gap and (tostring(row.gap) .. " yd"))
        or (row.wmap and "not comparable")
        or "-"
    return string.format("%s step %s %-24s %-9s quest %s%s | guide %s | client %s | gap %s%s%s%s%s%s%s%s%s%s%s",
        tostring(row.last or row.first or "?"), tostring(row.step),
        string.sub(tostring(row.title or row.kind or "?"), 1, 24),
        tostring(row.role or "step") .. (row.source == "pin" and "/pin" or ""),
        tostring(row.quest), row.inLog and "" or " (never in log)",
        authored, where, gap,
        ((row.pins or 1) > 1 or (row.maps or 1) > 1)
            and string.format(" | %d pins here, %d maps pin it%s", row.pins or 1, row.maps or 1,
                row.alsoOn and (" (" .. table.concat(row.alsoOn, ", ") .. ")") or "") or "",
        row.wmapType and row.wmapType < 3 and " | continent map, so the pin is a zone not a spot" or "",
        string.format(" | %s blobs, %s objective lines, guides place it in %s spot(s)%s",
            tostring(row.blobs), tostring(row.objectives), tostring(row.spots or 0),
            (row.spread or 0) > 0 and (" spread over " .. row.spread .. " yd") or ""),
        row.gapNear and (" | nearest authored spot " .. row.gapNear .. " yd" .. (row.nearestStep and (" (" .. row.nearestStep .. ")") or "")) or "",
        string.format(" | %s | to authored accept %s / objective %s / turnin %s / middle %s%s",
            row.ready and "READY to hand in" or (row.finished and "finished" or "not ready"),
            tostring(row.gapAccept or "-"), tostring(row.gapObjective or "-"), tostring(row.gapTurnin or "-"),
            tostring(row.gapCentroid or "-"), row.centroidCloser and " (nearer the middle than any spot)" or ""),
        (row.gapObserved or row.authoredObserved)
            and string.format(" | to where it happened: client %s, guide %s%s",
                tostring(row.gapObserved or "-"), tostring(row.authoredObserved or "-"),
                row.observedKind and (" (" .. row.observedKind .. ")") or "") or "",
        row.against and (" | vs " .. tostring(row.against)) or "",
        row.near and (" | nearest approach " .. row.near .. " yd") or "",
        (row.moves or 0) > 0 and (" | moved " .. row.moves .. "x") or "",
        row.text and (" | \"" .. tostring(row.text) .. "\"") or "")
end

POILog.Describe = describe

-- The report: what the log adds up to, then the rows that disagree most, then
-- everything when asked for it.
function POILog:ReportLines()
    local Client = ns.modules.Client
    local rows = self:Rows()
    local summary = self:Summarize(rows)
    local lines = {
        "What the client's own POI data said, collected while playing. Everything the log holds is in this one report:",
        "the scoreboard, every row, where things actually happened, the per-quest detail, and the swept map data.",
        "Nothing in NuuRoad reads any of it; it is evidence about what a guide could take from the client.",
        "",
        "Waypoint calls present: " .. tostring(Client and Client:HasQuestWaypoints()),
        "Session started " .. tostring((self:Store() or {}).session and (self:Store().session.started or "?"))
            .. " - the log is emptied at every login and /reload, so nothing here is stale",
        "Saved data restored this session: " .. tostring(ns.db and ns.db.sessionCount and ns.db.sessionCount > 1)
            .. " (this client does not restore SavedVariables, so the log covers this session; the file on disk keeps it)",
        "",
        string.format("Rows: %d (%d asked while the quest was in the log, %d never in the log)",
            summary.rows, summary.inLog, summary.notInLog),
        string.format("Of those in the log: %d placed, %d answered with nothing", summary.answered, summary.blank),
        string.format("  of the placed: %d from C_QuestLog.GetNextWaypoint, %d from the map's own pin list (GetQuestsOnMap)",
            summary.fromWaypoint, summary.fromPin),
        string.format("  %d were pinned in more than one place on the map they answered on, %d were pinned on more than one map",
            summary.multiPin, summary.multiMap),
        string.format("  %d answered on a zone map, %d only on a continent or wider map (where one pin stands for a whole zone)",
            summary.onZoneMap, summary.onWiderMap),
        "",
        "Quests whose work happens in more than one place (the guides put them over 150 yd apart):",
        string.format("  %d such quests placed; %d of them the client pinned only once, %d have more than one blob (area)",
            summary.multiSpot, summary.multiSpotPinnedOnce, summary.multiSpotBlobbed),
        string.format("  %d placements sat over 100 yd nearer a different step of the same quest than the one measured against",
            summary.nearerOtherSpot),
        string.format("  %d placements had more than one blob at all", summary.blobbed),
        "",
        "What the pin turns out to be. Distances are from the client's pin to the nearest authored step of each kind,",
        "which is how \"it pins the turn-in NPC\" or \"it pins the objectives\" stops being a guess:",
        string.format("  nearest authored step was an %s",
            (function()
                local parts = {}
                for role, total in pairs(summary.nearestByRole) do table.insert(parts, role .. " x" .. total) end
                table.sort(parts)
                return #parts > 0 and table.concat(parts, ", ") or "-"
            end)()),
        string.format("  quests ready to hand in: %d placed, %d within 150 yd of the authored turn-in step, %d within 50",
            summary.readyPlaced, summary.readyNearTurnin, summary.readyOnTurnin),
        string.format("  quests not ready: %d placed, %d of them within 150 yd of an authored objective step",
            summary.unreadyPlaced, summary.unreadyNearObjective),
        string.format("  %d of %d measurable pins sat nearer the middle of the quest's authored places than to any one of them",
            summary.centroidCloser, summary.centroidMeasured),
        "",
        "Scored against where the game said things happened - the player's own position when a quest was accepted, an",
        "objective advanced, or a quest was handed in. The packaged guides are ports and their coordinates can be wrong,",
        "so this is the only yardstick here that belongs to neither side:",
        "  (Rough: this compares the LATEST pin against ANY observation, so a turn-in pin can be scored against an",
        "  objective event. The paired samples above are the same-instant, same-event version and are the ones to read.)",
        string.format("  %d placements had an observation to be scored against", summary.observedCompared),
        string.format("  within 150 yd of where it actually happened: the client's pin %d times, the guide's coordinate %d times",
            summary.clientNearObserved, summary.authoredNearObserved),
        string.format("  clearly nearer (by over 50 yd): the client %d times, the guide %d times",
            summary.clientBeatAuthored, summary.authoredBeatClient),
        "  A guide coordinate that loses badly here is a porting error worth fixing, not evidence about the client.",
        string.format("Of the answers: %d within 50 yd of the authored point, %d within 150, %d within 500, %d further",
            summary.near, summary.close, summary.far, summary.distant),
        string.format("%d landed on another map, %d could not be compared, %d were steps with no authored coordinates",
            summary.wrongMap, summary.notComparable, summary.noCoordinates),
        string.format("%d waypoints moved while the step was in front of the player", summary.moved),
        "",
        "By the step's role (accept: the quest is not in the log yet, so the client has nothing to place and never will;",
        "turnin: in the log and complete, which is when the client points at the turn-in NPC; objective: the reading the",
        "guide's own coordinates are competing with):",
    }
    for _, name in ipairs(summary.roleOrder) do
        local entry = summary.roles[name]
        table.insert(lines, string.format("  %-9s %d rows: %d in the log, %d placed, %d blank, %d not taken yet; %d within 150 yd on the right map",
            name, entry.rows, entry.inLog, entry.answered, entry.blank, entry.notInLog, entry.usable))
    end
    table.insert(lines, "")
    -- The cleanest evidence in the report: both halves of each pair were read
    -- at the same instant, so neither depends on anybody's coordinates.
    local paired = self:PairedSamples()
    table.insert(lines, "Paired samples - the client's pin read at the moment the game confirmed something, beside the place it")
    table.insert(lines, "happened. No authored coordinate takes part in this comparison:")
    table.insert(lines, string.format("  %d pairs: %d within 50 yd, %d within 150, %d further, %d with no pin at the time",
        paired.total, paired.near, paired.close, paired.far, paired.blank))
    for _, kind in ipairs({ "accept", "objective", "turnin" }) do
        local entry = paired.byKind[kind]
        if entry then
            table.insert(lines, string.format("  %-9s %d pairs | client's pin: median %s yd, %d within 50 | the guide's own %s step: median %s yd",
                kind, entry.total, tostring(entry.median or "-"), entry.near, kind, tostring(entry.guideMedian or "-")))
        end
    end
    table.insert(lines, string.format("  head to head on the same event: the client nearer %d times, the guide nearer %d (by over 50 yd), of %d compared",
        paired.clientWon, paired.guideWon, paired.guideMeasured))
    table.insert(lines, "")
    -- Spawns are scattered: several spots in a zone and sometimes several
    -- zones. A pin a few hundred yards from where the player worked may be
    -- sitting on another spawn cluster, which is a different thing from being
    -- imprecise, and only grouping the places told apart tells them apart.
    local clustered = self:ClusterSummary()
    table.insert(lines, "Spawn clusters - objectives are worked in several places in a zone and sometimes in several zones, so a pin")
    table.insert(lines, "that is far from where the player stood may be on another cluster rather than wrong:")
    table.insert(lines, string.format("  %d quests had objective progress recorded; %d were worked in more than one place, %d in more than one zone",
        clustered.quests, clustered.multiPlace, clustered.multiMap))
    table.insert(lines, string.format("  of the multi-place ones: the pin was near the player in every place %d times, near in some and far in others %d times",
        clustered.pinFollowed, clustered.pinStayed))
    table.insert(lines, string.format("  %d quests were pinned by the client in more than one distinct place over the session",
        clustered.pinPlaces))
    table.insert(lines, "")
    -- The question behind "could a guide stop authoring turn-in coordinates":
    -- a step has to be pointed at from where it begins, not from on top of it.
    table.insert(lines, "How far away the player was when the client still answered. A guide could only drop an authored coordinate")
    table.insert(lines, "if the client answers from where the step begins, which for a turn-in is usually another zone:")
    local store = self:Store() or {}
    for _, kind in ipairs({ { "ready", "ready to hand in" }, { "working", "still being worked" } }) do
        local bucket = (store.range or {})[kind[1]] or {}
        local parts, total = {}, 0
        for _, band in ipairs({ "under 100 yd", "100-500 yd", "500-2000 yd", "over 2000 yd", "elsewhere (another map)" }) do
            if bucket[band] then
                table.insert(parts, string.format("%s x%d", band, bucket[band]))
                total = total + bucket[band]
            end
        end
        table.insert(lines, string.format("  quests %s: %d placements - %s", kind[2], total,
            #parts > 0 and table.concat(parts, ", ") or "none"))
    end
    table.insert(lines, "")
    if summary.byPlayerMap and next(summary.byPlayerMap) then
        table.insert(lines, "Where the asking happened (the player's map at the time). The client may only hold POI data near the")
        table.insert(lines, "player, so a run of blanks from one map says nothing about the same quest asked from its own zone:")
        local maps = {}
        for mapID in pairs(summary.byPlayerMap) do table.insert(maps, mapID) end
        table.sort(maps)
        for _, mapID in ipairs(maps) do
            local entry = summary.byPlayerMap[mapID]
            table.insert(lines, string.format("  map %-6s %-28s %d asks, %d placed",
                mapID, tostring(Client and Client:GetMapName(tonumber(mapID))), entry.asked, entry.placed))
        end
        table.insert(lines, "")
    end
    if summary.answered == 0 and summary.inLog > 0 then
        table.insert(lines, "SO FAR: nothing placed from where these questions were asked. That is not the same as the client")
        table.insert(lines, "having no data - ask again from the zone the quests are in before drawing any conclusion.")
    elseif summary.answered > 0 then
        table.insert(lines, string.format("VERDICT so far: %d of %d log quests placed. Read the gaps before trusting them: a waypoint",
            summary.answered, summary.inLog))
        table.insert(lines, "that is on the right map and within ~50 yd is usable; one that is further is the quest's area, not the step's spot.")
    else
        table.insert(lines, "VERDICT so far: nothing sampled yet. Run a guide for a few steps and read this again.")
    end
    table.insert(lines, "")
    if #summary.worst > 0 then
        table.insert(lines, "Biggest disagreements between the guide and the client. Neither is ground truth: the packaged guides are")
        table.insert(lines, "ports and a ported coordinate can be wrong, so read the \"to where it happened\" figures to see which side erred:")
        for index, row in ipairs(summary.worst) do
            if index > 10 then break end
            table.insert(lines, "  " .. describe(row))
        end
        table.insert(lines, "")
    end
    local store = self:Store() or {}
    local sweep = store.sweep or {}
    table.insert(lines, "")
    table.insert(lines, "The client's own map data, swept map by map (everything it would draw, whether or not the player is there):")
    table.insert(lines, string.format("  pass %d%s, last finished %s; a new pass runs every %d seconds and the map underfoot every %d",
        sweep.passes or 0, sweep.done and "" or " (still reading)", tostring(sweep.lastFinished or "-"),
        self.sweepEvery, self.currentMapEvery))
    table.insert(lines, string.format("  %d maps read, %d with nothing on them this pass", sweep.maps or 0, sweep.emptyMaps or 0))
    table.insert(lines, string.format("  %d area POIs, %d flight points, %d quests pinned on a map",
        sweep.pois or 0, sweep.taxi or 0, sweep.quests or 0))
    table.insert(lines, string.format("  %d quests have per-map detail collected (every map asked, every pin it held)",
        count((self:Store() or {}).quests)))
    table.insert(lines, "  /nuuroad poi maps lists the swept data; /nuuroad poi quests lists the per-quest detail; /nuuroad poi sweep reads again.")
    table.insert(lines, "")
    table.insert(lines, "Every row (" .. #rows .. "):")
    for _, row in ipairs(rows) do table.insert(lines, "  " .. describe(row)) end

    -- Everything in one command, by request: the observations, the per-quest
    -- detail and the swept map data follow here rather than behind their own
    -- commands, which stay for looking at one part on its own.
    local function section(title, body)
        table.insert(lines, "")
        table.insert(lines, "================ " .. title .. " ================")
        for _, line in ipairs(body) do table.insert(lines, line) end
    end
    local Corrections = ns.modules.GuideCorrections
    if Corrections then section("GUIDE COORDINATES THAT DISAGREE WITH THE GAME", Corrections:ReportLines()) end
    section("WHERE THINGS ACTUALLY HAPPENED", self:ObservationLines())
    section("NPCS, AND WHICH OF THEM WALK A ROUTE", self:NPCLines())
    section("PER-QUEST DETAIL", self:QuestDetailLines())
    section("THE CLIENT'S OWN MAP DATA", self:MapLines())

    -- The window holds a lot but not everything; say so rather than cutting
    -- silently, and name the command that shows the rest on its own.
    local limit = 3000
    if #lines > limit then
        local trimmed = {}
        for index = 1, limit do trimmed[index] = lines[index] end
        table.insert(trimmed, "")
        table.insert(trimmed, string.format("... %d more lines. /nuuroad poi maps, poi quests and poi observed show the parts on their own.",
            #lines - limit))
        return trimmed
    end
    return lines
end

local function sorted(entries, compare)
    local list = {}
    for _, entry in pairs(entries or {}) do table.insert(list, entry) end
    table.sort(list, compare)
    return list
end

-- The swept data itself, for copying out: this is the part that could seed
-- guide coordinates, so it is listed in full rather than counted.
function POILog:MapLines()
    local store = self:Store() or {}
    local lines = {
        "Everything the client draws on a map, as swept. Coordinates are map percent.",
        "Nothing here is used by a guide; it is what a guide could have taken from the client.",
        "",
    }
    local byMap = function(left, right)
        if left.map == right.map then return tostring(left.name or left.quest) < tostring(right.name or right.quest) end
        return (left.map or 0) < (right.map or 0)
    end
    local maps = sorted(store.maps, function(left, right) return (left.mapID or 0) < (right.mapID or 0) end)
    table.insert(lines, "Maps (" .. #maps .. "):")
    for _, map in ipairs(maps) do
        table.insert(lines, string.format("  %-6s %-34s type %-4s read %dx, last pass found %s, best ever %s",
            tostring(map.mapID), tostring(map.name), tostring(map.mapType), map.reads or 0,
            tostring(map.last or 0), tostring(map.best or 0)))
    end
    local pois = sorted(store.pois, byMap)
    table.insert(lines, "")
    table.insert(lines, "Area POIs (" .. #pois .. "):")
    for _, poi in ipairs(pois) do
        table.insert(lines, string.format("  map %-6s %-34s %s, %s  [%s]", tostring(poi.map), tostring(poi.name),
            tostring(poi.x), tostring(poi.y), tostring(poi.atlas)))
    end
    local taxi = sorted(store.taxi, byMap)
    table.insert(lines, "")
    table.insert(lines, "Flight points (" .. #taxi .. "):")
    for _, node in ipairs(taxi) do
        table.insert(lines, string.format("  map %-6s node %-6s %-30s %s, %s  faction %s%s",
            tostring(node.map), tostring(node.id), tostring(node.name), tostring(node.x), tostring(node.y),
            tostring(node.faction), node.undiscovered and " (undiscovered)" or ""))
    end
    local quests = sorted(store.mapQuests, byMap)
    table.insert(lines, "")
    table.insert(lines, "Quests the client pins on a map (" .. #quests .. "):")
    for _, quest in ipairs(quests) do
        table.insert(lines, string.format("  map %-6s quest %-6s %-34s %s, %s%s%s", tostring(quest.map), tostring(quest.quest),
            tostring(quest.title), tostring(quest.x), tostring(quest.y),
            (quest.pin or 1) > 1 and (" (pin " .. quest.pin .. ")") or "", quest.inLog and " (in log)" or ""))
    end
    return lines
end

-- One map, asked live. The sweep found no area POIs and no flight points on
-- build 69913, and the calls that answer for those are map-scoped, so this is
-- how a particular map (a continent rather than a zone, say) or a particular
-- moment (the flight map open) gets tested without waiting for a whole pass.
-- The flight map, open in front of the player, is the one moment the client
-- is certainly holding taxi data. The sweep found none from cold, so this
-- takes the reading when it is most likely to answer: the current map and
-- every map above it.
function POILog:OnTaxiMap()
    if not self:Enabled() then return end
    local Client = ns.modules.Client
    local mapID = Client and Client:GetCurrentMapID()
    if not mapID then return end
    local taken = 0
    for _ = 1, 4 do
        local info = Client:GetMapInfoTable(mapID)
        taken = taken + self:SweepMap(info or { mapID = mapID })
        mapID = info and info.parentMapID
        if not mapID or mapID == 0 then break end
    end
    ns:Log("quest POI: flight map open, read " .. taken .. " entries from here up")
end

-- The places a quest was actually worked, grouped. Mobs and objects spawn in
-- several spots in a zone and sometimes in several zones, so the observations
-- for one quest are not one place but a handful; grouping them is what lets
-- "the pin was 300 yd out" be told apart from "the pin was on the other
-- spawn cluster, which is also correct".
POILog.clusterYards = 200
function POILog:ClusterObservations(questID, kind)
    local clusters = {}
    for _, entry in ipairs(self:Observations(questID)) do
        if not kind or entry.kind == kind then
            local placed
            for _, cluster in ipairs(clusters) do
                local gap = self:GapYards(cluster.map, cluster.x / 100, cluster.y / 100, entry.map, entry.x / 100, entry.y / 100)
                if cluster.map == entry.map and gap and gap < self.clusterYards then
                    cluster.count = cluster.count + (entry.times or 1)
                    if entry.pinGap then
                        cluster.pinGaps = cluster.pinGaps or {}
                        table.insert(cluster.pinGaps, entry.pinGap)
                    end
                    placed = true
                    break
                end
            end
            if not placed then
                local cluster = { map = entry.map, x = entry.x, y = entry.y, count = entry.times or 1, kind = entry.kind }
                if entry.pinGap then cluster.pinGaps = { entry.pinGap } end
                table.insert(clusters, cluster)
            end
        end
    end
    -- How near the client's pin was while the player worked in each place: the
    -- number that says whether the pin follows the player between clusters.
    for _, cluster in ipairs(clusters) do
        if cluster.pinGaps then
            table.sort(cluster.pinGaps)
            cluster.medianPinGap = cluster.pinGaps[math.ceil(#cluster.pinGaps / 2)]
        end
    end
    return clusters
end

-- Across every quest: how many were worked in more than one place, in more
-- than one zone, and whether the pin kept up.
function POILog:ClusterSummary()
    local store = self:Store() or {}
    local result = { quests = 0, multiPlace = 0, multiMap = 0, pinFollowed = 0, pinStayed = 0, pinPlaces = 0 }
    for key in pairs(store.observed or {}) do
        local questID = tonumber(key)
        local clusters = self:ClusterObservations(questID, "objective")
        if #clusters > 0 then
            result.quests = result.quests + 1
            local maps = {}
            for _, cluster in ipairs(clusters) do maps[cluster.map] = true end
            local mapCount = 0
            for _ in pairs(maps) do mapCount = mapCount + 1 end
            if #clusters > 1 then
                result.multiPlace = result.multiPlace + 1
                -- Followed: the pin was near the player in every place they
                -- worked. Stayed: near in one and far in the others, which is
                -- a fixed pin rather than a tracking one.
                local near, far = 0, 0
                for _, cluster in ipairs(clusters) do
                    if cluster.medianPinGap then
                        if cluster.medianPinGap < 150 then near = near + 1 else far = far + 1 end
                    end
                end
                if near > 0 and far == 0 then result.pinFollowed = result.pinFollowed + 1
                elseif near > 0 and far > 0 then result.pinStayed = result.pinStayed + 1 end
            end
            if mapCount > 1 then result.multiMap = result.multiMap + 1 end
        end
        -- The other half of the same question: how many distinct places the
        -- client itself ever pinned this quest on one map.
        local record = (store.quests or {})[key]
        for _, entry in pairs(record and record.maps or {}) do
            if entry.seenAt and #entry.seenAt > 1 then
                result.pinPlaces = result.pinPlaces + 1
                break
            end
        end
    end
    return result
end

-- The paired samples across every quest: the client's pin at the instant the
-- game confirmed something, against the place it happened. Both halves come
-- from the same moment, so this is the one comparison in the log that needs
-- no assumption about anybody's coordinates.
function POILog:PairedSamples()
    local store = self:Store() or {}
    local result = { total = 0, near = 0, close = 0, far = 0, blank = 0, byKind = {},
        guideNear = 0, guideMeasured = 0, clientWon = 0, guideWon = 0 }
    local gapsByKind, guideGaps = {}, {}
    for _, list in pairs(store.observed or {}) do
        for _, entry in ipairs(list) do
            result.total = result.total + 1
            local kind = entry.kind or "?"
            local byKind = result.byKind[kind] or { total = 0, near = 0 }
            byKind.total = byKind.total + 1
            if not entry.pin or entry.pinGap == nil then
                result.blank = result.blank + 1
            else
                local gap = entry.pinGap
                if gap < 50 then
                    result.near, byKind.near = result.near + 1, byKind.near + 1
                elseif gap < 150 then
                    result.close = result.close + 1
                else
                    result.far = result.far + 1
                end
                gapsByKind[kind] = gapsByKind[kind] or {}
                table.insert(gapsByKind[kind], gap)
                -- The guide measured against the very same event, so neither
                -- side is scored against something it was not describing.
                if entry.guideGap then
                    result.guideMeasured = result.guideMeasured + 1
                    if entry.guideGap < 50 then result.guideNear = result.guideNear + 1 end
                    if gap + 50 < entry.guideGap then result.clientWon = result.clientWon + 1
                    elseif entry.guideGap + 50 < gap then result.guideWon = result.guideWon + 1 end
                    guideGaps[kind] = guideGaps[kind] or {}
                    table.insert(guideGaps[kind], entry.guideGap)
                end
            end
            result.byKind[kind] = byKind
        end
    end
    for kind, gaps in pairs(gapsByKind) do
        table.sort(gaps)
        result.byKind[kind].median = gaps[math.ceil(#gaps / 2)]
    end
    for kind, gaps in pairs(guideGaps) do
        table.sort(gaps)
        if result.byKind[kind] then result.byKind[kind].guideMedian = gaps[math.ceil(#gaps / 2)] end
    end
    return result
end

-- The observations themselves: every place the game confirmed something for a
-- quest. This is the part that can correct a ported coordinate, so it is
-- listed rather than only counted.
function POILog:ObservationLines()
    local store = self:Store() or {}
    local lines = {
        "Where the game said things happened: the player's own position when a quest was accepted, an objective",
        "advanced, or a quest was handed in. Nobody's opinion, and the only ground truth in this report.",
        "",
    }
    local quests = {}
    for key in pairs(store.observed or {}) do table.insert(quests, key) end
    table.sort(quests, function(left, right) return (tonumber(left) or 0) < (tonumber(right) or 0) end)
    table.insert(lines, "Quests with observations: " .. #quests)
    for _, key in ipairs(quests) do
        local questID = tonumber(key)
        table.insert(lines, "")
        table.insert(lines, string.format("[%s] %s", key, tostring(ns.modules.Client and ns.modules.Client:GetQuestTitle(questID))))
        for _, entry in ipairs(store.observed[key]) do
            table.insert(lines, string.format("  %-9s map %-6s %s, %s  x%d  %s | client's pin then: %s (%s yd)%s%s%s",
                entry.kind, tostring(entry.map), tostring(entry.x), tostring(entry.y), entry.times or 1, tostring(entry.at),
                entry.pin and string.format("map %s %s, %s", tostring(entry.pin.map), tostring(entry.pin.x), tostring(entry.pin.y)) or "none",
                tostring(entry.pinGap or "-"),
                entry.guideGap and string.format(" | guide's own %s step: %s yd%s", entry.kind, tostring(entry.guideGap),
                    entry.guideSameKind and "" or " (no step of this kind; nearest of any)") or "",
                entry.ready and " | quest was ready to hand in" or "",
                entry.text and (" | " .. tostring(entry.text)) or ""))
        end
        local clusters = self:ClusterObservations(questID, "objective")
        if #clusters > 1 then
            table.insert(lines, string.format("  worked in %d places:", #clusters))
            for index, cluster in ipairs(clusters) do
                table.insert(lines, string.format("    place %d: map %-6s %s, %s  %d event(s), client's pin was a median %s yd away while here",
                    index, tostring(cluster.map), tostring(cluster.x), tostring(cluster.y), cluster.count,
                    tostring(cluster.medianPinGap or "-")))
            end
        end
        -- What each source said about the same quest, beside it.
        local spots = self:AuthoredSpots(questID)
        for _, spot in ipairs(spots) do
            local gap = self:NearestObservation(questID, { "objective", "accept", "turnin" }, spot.mapID, spot.x, spot.y)
            table.insert(lines, string.format("  guide     %s step %-4s map %-6s %s, %s -> %s yd from an observation",
                tostring(spot.guide), tostring(spot.step), tostring(spot.mapID),
                tostring(percent(spot.x)), tostring(percent(spot.y)), tostring(gap or "-")))
        end
    end
    return lines
end

-- The collected per-quest detail, as a listing: one block per quest, one line
-- per map that could place it. This is `/nuuroad poi quest <id>` for every
-- quest at once, built from what was collected while playing rather than
-- asked for a quest at a time.
function POILog:QuestDetailLines()
    local store = self:Store() or {}
    local records = {}
    for _, record in pairs(store.quests or {}) do table.insert(records, record) end
    table.sort(records, function(left, right) return (left.quest or 0) < (right.quest or 0) end)
    local lines = {
        "Every quest the log has asked about, and what each map said about it.",
        "Collected while playing; a quest worked in two places shows here as two pins, two blobs, or neither.",
        "",
        "Quests recorded: " .. #records,
        "",
    }
    for _, record in ipairs(records) do
        table.insert(lines, string.format("[%d] %s%s", record.quest, tostring(record.title), record.inLog and "" or " (not in the log)"))
        table.insert(lines, string.format("  read %sx | %s objective lines | %s blobs last read | guides place it in %s spot(s)%s",
            tostring(record.reads), tostring(record.objectives), tostring(record.blobs or "?"), tostring(record.spots or 0),
            (record.spread or 0) > 0 and (" spread over " .. record.spread .. " yd") or ""))
        local maps = {}
        for _, entry in pairs(record.maps or {}) do table.insert(maps, entry) end
        table.sort(maps, function(left, right) return (left.map or 0) < (right.map or 0) end)
        for _, entry in ipairs(maps) do
            table.insert(lines, string.format("    map %-6s %-26s type %-4s read %sx | %s pin(s), most ever %s | blobs %s | waypoint %s",
                tostring(entry.map), tostring(entry.name), tostring(entry.type), tostring(entry.reads),
                tostring(entry.pins and #entry.pins or 0), tostring(entry.best or 0), tostring(entry.blobs),
                entry.waypoint and string.format("map %s %s, %s", tostring(entry.waypoint.map), tostring(entry.waypoint.x), tostring(entry.waypoint.y)) or "none"))
            for index, pin in ipairs(entry.pins or {}) do
                table.insert(lines, string.format("      pin %d at %s, %s -> nearest authored spot %s yd%s", index,
                    tostring(pin.x), tostring(pin.y), tostring(pin.near), pin.step and (" (" .. pin.step .. ")") or ""))
            end
            if entry.seenAt and #entry.seenAt > 1 then
                table.insert(lines, string.format("      pinned in %d distinct places on this map over the session:", #entry.seenAt))
                for _, place in ipairs(entry.seenAt) do
                    table.insert(lines, string.format("        %s, %s  x%d  %s to %s", tostring(place.x), tostring(place.y),
                        place.times or 1, tostring(place.at), tostring(place.last)))
                end
            end
        end
    end
    return lines
end

function POILog:Initialize()
    -- Session only, by request. The store still lives in SavedVariables so a
    -- session's harvest reaches `WTF/.../NuuRoad.lua` when the client writes
    -- it at logout, but it is emptied at every login and every `/reload`, so
    -- nothing read here is ever left over from a previous session, a previous
    -- build, or a previous character.
    self:Clear()
    local store = self:Store()
    if store then store.session = { started = stamp(), build = ns.modules.Client and ns.modules.Client.build and ns.modules.Client.build.build } end
    self.startedAt, self.lastSweepAt, self.lastQuestLogAt, self.lastMap, self.lastMapAt = nil, nil, nil, nil, nil
    -- Its own frame, not the audit's: the audit only listens while the debug
    -- log is on, and these observations have to be collected whether or not
    -- anyone is watching.
    if type(CreateFrame) == "function" then
        local frame = CreateFrame("Frame")
        for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "TAXIMAP_OPENED",
            "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" }) do
            pcall(frame.RegisterEvent, frame, event)
        end
        frame:SetScript("OnEvent", function(_, event, ...)
            if event == "QUEST_ACCEPTED" then
                -- Classic passes (questLogIndex, questID); newer clients pass (questID).
                self:OnQuestAccepted(select(select("#", ...), ...))
            elseif event == "QUEST_TURNED_IN" then
                self:OnQuestTurnedIn((...))
            elseif event == "QUEST_LOG_UPDATE" then
                self:OnQuestLogUpdate()
            elseif event == "TAXIMAP_OPENED" then
                self:OnTaxiMap()
            else
                -- A dialog of any kind: the player is at talking distance.
                self:OnDialog()
            end
        end)
        self.frame = frame
    end
    if self:Enabled() then
        ns:Log("quest POI log: cleared for this session; recording what the client says on each step")
    else
        ns:Log("quest POI log: the client has no C_QuestLog.GetNextWaypoint, so there is nothing to record")
    end
end

ns:RegisterModule("POILog", POILog)
