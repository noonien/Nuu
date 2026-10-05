local _, ns = ...

-- What C_QuestLog.GetQuestsOnMap gives on this client. NeverQuestAlone sends
-- its points to the AI as quest positions; NuuRoad wraps the call
-- (Client:GetQuestsOnMap, after SetMapForQuestPOIs) but nothing has recorded
-- what it answers. This run asks:
--
--   shape    every field an entry carries, as the client fills it
--   cold     whether it answers before SetMapForQuestPOIs is called
--   maps     which maps answer: the player's, each map above it, and every
--            zone in the world (run 1, Undercity, asked only the Eastern
--            Kingdoms and missed the 25 quests in Kalimdor)
--   quests   for each quest in the log: on which maps it shows and where,
--            next to GetNextWaypoint, IsOnMap, GetQuestUiMapID and
--            QuestHasPOIInfo, and how far the point is from the player when
--            both are on the same map; ready-to-turn-in quests show whether
--            the point moves to the turn-in
--   strays   quests on a map that are not in the log
--
-- Best run with a few quests in the log: one ready to turn in, one with
-- objectives left, and one in another zone. The map the client keeps for
-- quest POIs is put back at the end.
--
-- Run 2 (1.60.1 (70205), 2026-10-06, Undercity, 27 quests) is written up in
-- docs/api-compatibility.md, "Quest points on the map".

-- Ask about at most this many zones.
local MAX_ZONES = 250

-- Map types (Enum.UIMapType): 1 world, 2 continent, 3 zone.
local WORLD, CONTINENT, ZONE = 1, 2, 3

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function round(value)
    if type(value) ~= "number" then return value end
    return math.floor(value * 10000 + 0.5) / 10000
end

-- An entry as it came, every field kept with its value.
local function raw(entry)
    local out = {}
    for key, value in pairs(entry) do
        out[tostring(key)] = type(value) == "number" and round(value) or value
    end
    return out
end

-- The client's answer for one map: nil when the call is missing or fails.
local function questsOn(mapID)
    local QL = C_QuestLog
    if not (QL and QL.GetQuestsOnMap) then return nil, "missing" end
    local ok, entries = pcall(QL.GetQuestsOnMap, mapID)
    if not ok then return nil, tostring(entries) end
    if type(entries) ~= "table" then return nil, "returned " .. type(entries) end
    return entries
end

local function setMap(mapID)
    if C_QuestLog and C_QuestLog.SetMapForQuestPOIs then return (pcall(C_QuestLog.SetMapForQuestPOIs, mapID)) end
    return false
end

local function mapName(mapID)
    local info = call(C_Map and C_Map.GetMapInfo, mapID)
    return type(info) == "table" and info.name or nil, type(info) == "table" and info.mapType or nil,
        type(info) == "table" and info.parentMapID or nil
end

-- Every quest in the log, by whichever log API the client has.
local function questLog()
    local quests = {}
    local QL = C_QuestLog or {}
    local count = call(QL.GetNumQuestLogEntries or GetNumQuestLogEntries)
    if type(count) ~= "number" then return quests end
    for index = 1, count do
        local questID, title, isHeader
        if QL.GetInfo then
            local info = call(QL.GetInfo, index)
            if type(info) == "table" then questID, title, isHeader = info.questID, info.title, info.isHeader end
        elseif GetQuestLogTitle then
            local ok, name, _, _, header, _, _, _, id = pcall(GetQuestLogTitle, index)
            if ok then questID, title, isHeader = id, name, header end
        end
        if type(questID) == "number" and questID > 0 and not isHeader then
            quests[#quests + 1] = { questID = questID, title = title }
        end
    end
    return quests
end

local function objectives(questID)
    local out = {}
    for _, o in ipairs(call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID) or {}) do
        if type(o) == "table" then
            out[#out + 1] = { text = o.text, type = o.type, have = o.numFulfilled, need = o.numRequired,
                finished = o.finished }
        end
    end
    return out
end

ns:Experiment({
    id = "quests-on-map",
    title = "Quest points from GetQuestsOnMap",
    run = function(t)
        t:Exists({
            "C_QuestLog.GetQuestsOnMap", "C_QuestLog.SetMapForQuestPOIs", "C_QuestLog.GetMapForQuestPOIs",
            "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetNextWaypointText", "C_QuestLog.IsOnMap",
            "C_QuestLog.GetQuestUiMapID", "C_QuestLog.IsComplete", "C_QuestLog.ReadyForTurnIn",
            "QuestHasPOIInfo", "GetQuestPOIBlobCount", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition",
            "C_Map.GetMapChildrenInfo",
        })
        if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
            t:Log("C_QuestLog.GetQuestsOnMap is missing")
            return
        end

        local before = call(C_QuestLog.GetMapForQuestPOIs)
        t:Set("poiMapBefore", before or "nil")

        -- Where the player is, and the maps above.
        local here = call(C_Map and C_Map.GetBestMapForUnit, "player")
        local px, py
        local pos = here and call(C_Map.GetPlayerMapPosition, here, "player")
        if pos and pos.GetXY then px, py = pos:GetXY() end
        local chain, world = {}, nil
        local id = here
        while type(id) == "number" and id > 0 and #chain < 8 do
            local name, mapType, parent = mapName(id)
            chain[#chain + 1] = { mapID = id, name = name, mapType = mapType }
            if mapType == WORLD then world = id end
            id = parent
        end
        t:Set("player", { mapID = here, x = round(px), y = round(py), chain = chain })

        -- Before any SetMapForQuestPOIs from this run.
        if here then
            local entries, err = questsOn(here)
            t:Set("cold", entries and { count = #entries, first = entries[1] and raw(entries[1]) } or err)
        end

        -- The maps to ask: the chain, then every continent and zone in the world.
        local maps, seen = {}, {}
        local function add(mapID, name, mapType)
            if type(mapID) == "number" and not seen[mapID] then
                seen[mapID] = true
                maps[#maps + 1] = { mapID = mapID, name = name, mapType = mapType }
            end
        end
        for _, m in ipairs(chain) do add(m.mapID, m.name, m.mapType) end
        if world then
            local children = call(C_Map.GetMapChildrenInfo, world, nil, true)
            local zones = 0
            for _, info in ipairs(type(children) == "table" and children or {}) do
                if zones >= MAX_ZONES then break end
                if type(info) == "table" and (info.mapType == CONTINENT or info.mapType == ZONE) then
                    add(info.mapID, info.name, info.mapType)
                    zones = zones + 1
                end
            end
        end

        -- Ask each map, before and after setting it as the quest POI map.
        local logged = questLog()
        local inLog = {}
        for _, q in ipairs(logged) do inLog[q.questID] = q end
        local onMaps, shape, strays, answers = {}, {}, {}, {}
        for _, m in ipairs(maps) do
            local plain = questsOn(m.mapID)
            setMap(m.mapID)
            local entries, err = questsOn(m.mapID)
            local row = { mapID = m.mapID, name = m.name, mapType = m.mapType,
                plain = plain and #plain or "error", count = entries and #entries or err }
            if entries and #entries > 0 then
                answers[#answers + 1] = row
                for _, entry in ipairs(entries) do
                    if type(entry) == "table" then
                        for key, value in pairs(entry) do shape[tostring(key)] = type(value) end
                        local qid = entry.questID
                        if type(qid) == "number" then
                            local point = raw(entry)
                            point.mapID = m.mapID
                            if inLog[qid] then
                                onMaps[qid] = onMaps[qid] or {}
                                table.insert(onMaps[qid], point)
                            else
                                point.title = call(C_QuestLog.GetTitleForQuestID, qid)
                                strays[#strays + 1] = point
                            end
                        end
                    end
                end
            elseif plain and #plain > 0 then
                answers[#answers + 1] = row
            end
        end
        t:Set("mapsAsked", #maps)
        t:Set("mapsAnswering", answers)
        t:Set("shape", shape)
        t:Set("strays", strays)

        -- Each quest in the log, next to the client's other quest-position calls.
        local QL = C_QuestLog
        local quests = {}
        for _, q in ipairs(logged) do
            local qid = q.questID
            local wMap, wx, wy = call(QL.GetNextWaypoint, qid)
            local onMap, localPOI = call(QL.IsOnMap, qid)
            local row = {
                questID = qid, title = q.title,
                complete = call(QL.IsComplete, qid),
                ready = call(QL.ReadyForTurnIn, qid),
                objectives = objectives(qid),
                uiMapID = call(QL.GetQuestUiMapID, qid),
                hasPOI = call(QuestHasPOIInfo, qid),
                blobs = call(GetQuestPOIBlobCount, qid),
                onMap = onMap, localPOI = localPOI,
                waypoint = wMap and { mapID = wMap, x = round(wx), y = round(wy) } or nil,
                waypointText = call(QL.GetNextWaypointText, qid),
                points = onMaps[qid],
            }
            -- Distance in map fractions when the point is on the player's map.
            if px and onMaps[qid] then
                for _, point in ipairs(onMaps[qid]) do
                    if point.mapID == here and type(point.x) == "number" then
                        point.fromPlayer = round(math.sqrt((point.x - px) ^ 2 + (point.y - py) ^ 2))
                    end
                end
            end
            quests[#quests + 1] = row
        end
        t:Set("quests", quests)
        local shown = 0
        for _ in pairs(onMaps) do shown = shown + 1 end
        t:Log("%d quests in the log, %d on some map; %d of %d maps answered; %d not in the log",
            #logged, shown, #answers, #maps, #strays)

        if type(before) == "number" then setMap(before) elseif here then setMap(here) end
        t:Set("poiMapAfter", call(C_QuestLog.GetMapForQuestPOIs) or "nil")
    end,
})
