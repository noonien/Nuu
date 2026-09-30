local _, ns = ...

-- The guide's client adapter: every game call NuuRoad makes goes through
-- here, feature-detected and guarded, so a client that lacks a call or
-- changes it degrades to "not known" rather than an error. Taken from
-- OpenRoad's API/Client.lua, less the profession planner's reads (they are
-- NuuProfessions'). The profession-window reads the Make button of a craft
-- step needs (the Professions section at the end) are duplicated with
-- NuuProfessions' API/Client.lua until they move to the kit.
local Client = { capabilities = {} }

local function exists(name)
    return type(rawget(_G, name)) == "function" or type(rawget(_G, name)) == "table"
end

-- Values the client hides from addons (the "secret values" of 12.0). They
-- carry the right type, but comparing, concatenating, or printing one raises
-- "attempt to compare a secret value", and pcall around the call that
-- produced it does not help: the error comes later, where it is used. So
-- every value read out of the client is checked here first. The client hands
-- out secrets for whatever an addon is not meant to know, and what counts as
-- that depends on how execution got there: the same call can answer plainly
-- after the player targets something and secretly after one of our macros did.
local function secret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, hidden = pcall(issecretvalue, value)
    return ok and hidden == true
end

function Client:IsSecret(value)
    return secret(value)
end

-- A non-empty string read from the client, or nil. Checks for a secret first:
-- even taking the length of a secret string throws.
local function text(value)
    if type(value) ~= "string" or secret(value) or #value == 0 then return nil end
    return value
end

-- Calls a client function and hands back nil when the call fails or the value
-- it returns is secret, so callers can compare what they get.
function Client:Read(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if not ok or secret(value) then return nil end
    return value
end

local function plainNumber(value)
    if type(value) ~= "number" or secret(value) then return nil end
    return value
end

local function positionXY(position)
    if not position then return nil end
    if position.GetXY then return position:GetXY() end
    return position.x, position.y
end

function Client:Initialize()
    local info = rawget(_G, "GetBuildInfo")
    if type(info) == "function" then
        local ok, version, build, date, toc = pcall(info)
        if ok then self.build = { version = version, build = build, date = date, toc = toc } end
    end
    self.capabilities = {
        playerIdentity = exists("UnitName") and exists("UnitLevel"),
        questData = exists("C_QuestLog") or exists("GetQuestLogTitle"),
        mapCoordinates = exists("C_Map"),
        minimapPins = exists("C_Minimap"),
        professions = exists("C_TradeSkillUI") or exists("GetProfessions"),
        skillRanks = exists("GetSkillLineInfo") or exists("GetProfessionInfo"),
        reputation = exists("C_Reputation") or exists("GetFactionInfoByID"),
        equippedItems = exists("IsEquippedItem") or exists("GetInventoryItemID"),
        achievements = exists("GetAchievementInfo"),
        auraState = exists("C_UnitAuras") or exists("UnitAura"),
        questDialog = exists("AcceptQuest") or exists("C_GossipInfo"),
        -- Those clients also protect SetRaidTarget; calling it from an addon is
        -- forbidden the same way, so marking is off there from the start.
        targetMarkers = exists("SetRaidTarget") and not exists("issecretvalue") and not exists("C_SecretValues"),
        -- The sanctioned way to mark on those clients: macro text ("/tm N")
        -- the addon rewrites on a secure button, fired by the player's key.
        secureMarking = exists("CreateFrame") and exists("SetBindingClick"),
        playerFacing = exists("GetPlayerFacing"),
        taxiState = exists("UnitOnTaxi"),
        corpsePosition = exists("C_DeathInfo") or exists("GetCorpseMapPosition"),
        -- Clients with secret values (the restricted API) forbid registering the
        -- combat log; asking is an ADDON_ACTION_FORBIDDEN error, so never try there.
        combatLog = exists("CombatLogGetCurrentEventInfo") and not exists("issecretvalue") and not exists("C_SecretValues"),
        nameplates = exists("C_NamePlate"),
        -- The modern quest map-pin reads. Detected only; nothing depends on
        -- them yet, and `/nuuroad poi` is what says whether they answer.
        questWaypoints = type(rawget(_G, "C_QuestLog")) == "table" and type(rawget(_G, "C_QuestLog").GetNextWaypoint) == "function",
        -- The Make button's reads (the Professions section below).
        tradeSkillWindow = exists("GetTradeSkillInfo")
            or (type(rawget(_G, "C_TradeSkillUI")) == "table" and type(rawget(_G, "C_TradeSkillUI").GetAllRecipeIDs) == "function"),
        craftWindow = exists("GetCraftInfo"),
    }
    self:WatchProfessionWindows()
end

function Client:GetCurrentMapID()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return mapID end
    return nil
end

-- `mapID = 0` is the portable-fixture convention for "the player's current map".
function Client:ResolveMapID(mapID)
    if mapID == 0 then return self:GetCurrentMapID() end
    return mapID
end

function Client:GetPlayerMapPosition(mapID)
    if not C_Map or not C_Map.GetPlayerMapPosition or not mapID then return nil end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok then return nil end
    return positionXY(position)
end

-- The map the player is on and where on it (0 to 1), for the session log
-- (Core.lua's recorder): map, x, y, or nil. OpenRoad's recorder read the two
-- calls above itself; here they are one call, as in NuuProfessions' Client.
function Client:GetPlayerPosition()
    local mapID = self:GetCurrentMapID()
    if not mapID then return nil end
    local x, y = self:GetPlayerMapPosition(mapID)
    if plainNumber(x) and plainNumber(y) then return mapID, x, y end
    return mapID
end

-- The player has released and is a ghost walking back to the corpse. Dead
-- but unreleased is not a ghost: the corpse is underfoot then.
function Client:IsPlayerGhost()
    return self:Read(UnitIsGhost, "player") == true
end

-- Where the player's corpse lies on a map, normalized, or nil when it is not
-- on that map or the client cannot say. Modern clients take any map; the
-- legacy call only answers for the map the player is on.
function Client:GetCorpseMapPosition(mapID)
    if not mapID then return nil end
    if C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        local ok, position = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
        if not ok or not position then return nil end
        local x, y = positionXY(position)
        if type(x) ~= "number" or type(y) ~= "number" or secret(x) or secret(y) then return nil end
        return x, y
    end
    if type(GetCorpseMapPosition) == "function" and mapID == self:GetCurrentMapID() then
        local ok, x, y = pcall(GetCorpseMapPosition)
        if not ok or type(x) ~= "number" or type(y) ~= "number" or secret(x) or secret(y) then return nil end
        if x == 0 and y == 0 then return nil end -- The legacy call's "no corpse here".
        return x, y
    end
    return nil
end

-- A map position as world coordinates. The client's world axes are X north
-- and Y west; the continent ID says whether two answers are comparable.
function Client:GetWorldPosition(mapID, x, y)
    if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D or not mapID then return nil end
    local ok, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not worldPos then return nil end
    local wx, wy = positionXY(worldPos)
    if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
    return continentID, wx, wy
end

-- The map the client says lies at a spot on a zone map: a city's own map for
-- a point inside it (Orgrimmar for a Durotar point in the city), the zone
-- itself, or nil when the client cannot say. The world map's hover data.
function Client:GetMapAtPosition(mapID, x, y)
    if not C_Map or not C_Map.GetMapInfoAtPosition or not mapID or type(x) ~= "number" then return nil end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if ok and type(info) == "table" and type(info.mapID) == "number" then return info.mapID end
    return nil
end

-- A map's extent in yards, width then height, when the client can size it.
function Client:GetMapWorldSize(mapID)
    if not C_Map or not C_Map.GetMapWorldSize or not mapID then return nil end
    local ok, width, height = pcall(C_Map.GetMapWorldSize, mapID)
    if ok and type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
        return width, height
    end
    return nil
end

function Client:GetMapName(mapID)
    if not C_Map or not C_Map.GetMapInfo or not mapID then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" then return info.name end
    return nil
end

function Client:IsQuestInLog(questID)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, isOnQuest = pcall(C_QuestLog.IsOnQuest, questID)
        if ok then return isOnQuest == true end
    end
    return false
end

function Client:IsQuestComplete(questID)
    local check = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if check then
        local ok, complete = pcall(check, questID)
        if ok then return complete == true end
    end
    return false
end

function Client:IsQuestReadyToTurnIn(questID)
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, complete = pcall(C_QuestLog.IsComplete, questID)
        if ok then return complete == true end
    end
    return false
end

-- A quest in the log that can no longer be completed: an escort whose NPC
-- died, or a timed quest that ran out. Only abandoning it and taking it again
-- helps. `C_QuestLog.IsFailed` where the client has it, else the classic log
-- row, whose completion flag is -1 for a failed quest. False when neither
-- says, so an unreadable log never shows a quest as failed.
function Client:IsQuestFailed(questID)
    if type(questID) ~= "number" then return false end
    if C_QuestLog and C_QuestLog.IsFailed then
        local ok, failed = pcall(C_QuestLog.IsFailed, questID)
        if ok then return failed == true end
    end
    if GetQuestLogIndexByID and GetQuestLogTitle then
        local ok, index = pcall(GetQuestLogIndexByID, questID)
        if ok and index and index > 0 then
            local titleOK, _, _, _, _, _, isComplete = pcall(GetQuestLogTitle, index)
            if titleOK then return isComplete == -1 end
        end
    end
    return false
end

-- True once the client has handed over a quest log with something in it. The
-- log is empty for the first frames after login, so nothing that reasons from
-- the absence of a quest may believe it before this says so. Sticky: a log
-- that was read once stays read, even after the player empties it.
function Client:HasQuestLog()
    if self.questLogSeen then return true end
    self.questLogSeen = #self:GetQuestLogEntries() > 0
    return self.questLogSeen
end

-- A quest the player does not have and has never finished. Nothing that acts
-- on it - a turn-in, an objective - can be done, so the tracker greys those
-- steps out and passes over them instead of asking for work that is not there.
function Client:IsQuestMoot(questID)
    if type(questID) ~= "number" or not self:HasQuestLog() then return false end
    return not self:IsQuestInLog(questID) and not self:IsQuestComplete(questID)
end

-- Best-effort quest title, used only for diagnostics when a quest ID does not
-- match what a guide expected. Returns nil when the client cannot say.
function Client:GetQuestTitle(questID)
    if not questID then return nil end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and text(title) then return title end
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and index then
            local infoOK, info = pcall(C_QuestLog.GetInfo, index)
            if infoOK and type(info) == "table" and info.title then return info.title end
        end
    end
    if GetQuestLogIndexByID and GetQuestLogTitle then
        local ok, index = pcall(GetQuestLogIndexByID, questID)
        if ok and index and index > 0 then
            local titleOK, title = pcall(GetQuestLogTitle, index)
            if titleOK and type(title) == "string" then return title end
        end
    end
    return nil
end

-- Creature names by ID: set a creature hyperlink on a hidden tooltip and
-- read its first line. The client only
-- answers for creatures it has cached this session, so a miss is remembered
-- with a timestamp and retried after a short delay.
local npcNames = {}
local npcTooltip
function Client:GetNPCName(id)
    if type(id) ~= "number" then return nil end
    local cached = npcNames[id]
    if type(cached) == "string" then return cached end
    if type(cached) == "number" and (GetTime and GetTime() or 0) - cached < 1.5 then return nil end
    if not CreateFrame then return nil end
    if not npcTooltip then
        npcTooltip = CreateFrame("GameTooltip", "NuuRoadNameTooltip", UIParent, "GameTooltipTemplate")
        npcTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    npcTooltip:ClearLines()
    local ok = pcall(npcTooltip.SetHyperlink, npcTooltip, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
    local line = ok and _G["NuuRoadNameTooltipTextLeft1"]
    -- Tooltip text can be secret in instances; discard it before string operations.
    local name = line and self:Read(line.GetText, line)
    npcTooltip:Hide()
    if type(name) == "string" and #name > 0 then
        name = name:match("^|c%x%x%x%x%x%x%x%x(.-)|r$") or name
        npcNames[id] = name
        return name
    end
    npcNames[id] = GetTime and GetTime() or 0
    return nil
end

-- One objective line of a quest in the log: returns finished, and the client's
-- progress text ("Razormane Hunter slain: 2/3") when it has one.
function Client:GetQuestObjective(questID, index)
    if type(questID) ~= "number" or type(index) ~= "number" then return nil end
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
        local objective = ok and type(objectives) == "table" and objectives[index]
        if objective then return objective.finished == true, objective.text end
    end
    if GetQuestLogIndexByID and GetQuestLogLeaderBoard then
        local ok, logIndex = pcall(GetQuestLogIndexByID, questID)
        if ok and logIndex and logIndex > 0 then
            local textOK, text, _, finished = pcall(GetQuestLogLeaderBoard, index, logIndex)
            if textOK and text then return finished == true, text end
        end
    end
    return nil
end

-- Every objective line of a quest in the log as
-- { text, finished, type, have, need }. The counts are what the recorder
-- watches: an objective that moves from 3 to 4 is the one signal the client
-- gives for a kill, a pickup, or a step of an escort, and it is the same
-- signal whatever produced it. The modern call answers them outright; the
-- classic one only prints them, so they are read back out of its own text and
-- left nil when it says nothing countable.
local function objectiveCounts(text)
    if type(text) ~= "string" then return nil end
    local have, need = text:match("(%d+)%s*/%s*(%d+)%s*$")
    return tonumber(have), tonumber(need)
end

function Client:GetQuestObjectives(questID)
    local lines = {}
    if type(questID) ~= "number" then return lines end
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and type(objectives) == "table" then
            for _, objective in ipairs(objectives) do
                local line = { text = objective.text, finished = objective.finished == true }
                line.type = self:Read(function() return objective.type end)
                line.have = plainNumber(self:Read(function() return objective.numFulfilled end))
                line.need = plainNumber(self:Read(function() return objective.numRequired end))
                if not line.have then line.have, line.need = objectiveCounts(line.text) end
                table.insert(lines, line)
            end
            return lines
        end
    end
    if GetQuestLogIndexByID and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local ok, logIndex = pcall(GetQuestLogIndexByID, questID)
        if ok and logIndex and logIndex > 0 then
            local countOK, count = pcall(GetNumQuestLeaderBoards, logIndex)
            for index = 1, countOK and tonumber(count) or 0 do
                local textOK, text, objectiveType, finished = pcall(GetQuestLogLeaderBoard, index, logIndex)
                if textOK then
                    local line = { text = text, finished = finished == true }
                    if type(objectiveType) == "string" and not secret(objectiveType) then line.type = objectiveType end
                    line.have, line.need = objectiveCounts(type(text) == "string" and text or nil)
                    table.insert(lines, line)
                end
            end
        end
    end
    return lines
end

function Client:IsQuestObjectiveComplete(questID, index)
    if self:IsQuestComplete(questID) or self:IsQuestReadyToTurnIn(questID) then return true end
    local finished = self:GetQuestObjective(questID, index)
    return finished == true
end

-- Quest POI: where the client itself thinks a quest's next objective is.
-- This client carries the modern map-pin machinery (QuestPOIPoint and
-- QuestPOIBlob tables, `C_QuestLog.GetNextWaypoint`) and not the Classic-era
-- `QuestPOIGetIconInfo`, so the modern call is the one to ask. Whether the
-- data behind it is filled in for this client's quests is a
-- separate question, and an offline one cannot answer it: nothing in the
-- tracker reads any of this yet. It is here for `/nuuroad poi`, which
-- reports per quest and per map what the client will say, so a decision to
-- lean on it can rest on what the live client actually answers.
function Client:HasQuestWaypoints()
    return type(C_QuestLog) == "table" and type(C_QuestLog.GetNextWaypoint) == "function"
end

-- The map and normalized position of a quest's next objective, or nil.
function Client:GetQuestWaypoint(questID)
    if type(questID) ~= "number" or not self:HasQuestWaypoints() then return nil end
    local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
    if not ok then return nil end
    mapID, x, y = plainNumber(mapID), plainNumber(x), plainNumber(y)
    if not mapID or not x or not y then return nil end
    return mapID, x, y
end

-- The client's own wording for that waypoint ("Travel to Ratchet"), when it
-- has one. Quests without waypoint text return nothing, not an error.
function Client:GetQuestWaypointText(questID)
    if type(questID) ~= "number" or type(C_QuestLog) ~= "table" then return nil end
    local text = self:Read(C_QuestLog.GetNextWaypointText, questID)
    if type(text) ~= "string" or #text == 0 then return nil end
    return text
end

-- Whether the client believes it has POI data for the quest at all: the
-- legacy flag, then whether the quest shows on the current map and whether
-- that showing is a local POI rather than an off-map arrow.
function Client:QuestHasPOI(questID)
    if type(questID) ~= "number" then return nil end
    local hasPOI, onMap, localPOI
    if type(rawget(_G, "QuestHasPOIInfo")) == "function" then
        local ok, value = pcall(QuestHasPOIInfo, questID)
        if ok and not secret(value) then hasPOI = value == true end
    end
    if type(C_QuestLog) == "table" and type(C_QuestLog.IsOnMap) == "function" then
        local ok, first, second = pcall(C_QuestLog.IsOnMap, questID)
        if ok then
            if not secret(first) then onMap = first == true end
            if not secret(second) then localPOI = second == true end
        end
    end
    return hasPOI, onMap, localPOI
end

-- How many blobs (objective areas) the client holds for a quest. A blob is an
-- area, not a point: this only says whether there is area data behind the
-- waypoint.
function Client:GetQuestPOICount(questID)
    if type(questID) ~= "number" or type(rawget(_G, "GetQuestPOIBlobCount")) ~= "function" then return nil end
    return plainNumber(self:Read(GetQuestPOIBlobCount, questID))
end

-- The map the client files a quest under, whatever map the player is on.
function Client:GetQuestMapID(questID)
    if type(questID) ~= "number" then return nil end
    if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestUiMapID) == "function" then
        local mapID = plainNumber(self:Read(C_QuestLog.GetQuestUiMapID, questID))
        if mapID and mapID > 0 then return mapID end
    end
    if type(rawget(_G, "GetQuestUiMapID")) == "function" then
        local mapID = plainNumber(self:Read(GetQuestUiMapID, questID))
        if mapID and mapID > 0 then return mapID end
    end
    return nil
end

-- Every quest the client would draw on a map, as { questID, x, y }. Empty
-- when the call is missing or the client has nothing for that map.
function Client:GetQuestsOnMap(mapID)
    local quests = {}
    if type(mapID) ~= "number" or type(C_QuestLog) ~= "table" or type(C_QuestLog.GetQuestsOnMap) ~= "function" then return quests end
    self:SetMapForQuestPOIs(mapID)
    local ok, entries = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not ok or type(entries) ~= "table" then return quests end
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local questID = plainNumber(entry.questID)
            if questID then table.insert(quests, { questID = questID, x = plainNumber(entry.x), y = plainNumber(entry.y) }) end
        end
    end
    return quests
end

-- The rest of what the client draws on a map: area POIs (towns, landmarks,
-- the things the world map labels), flight points, and the quests it would pin
-- there. Same rules as the waypoint reads above - guarded, secret-safe, and
-- read by nothing but the POI log.
function Client:GetMapInfoTable(mapID)
    if type(mapID) ~= "number" or not C_Map or not C_Map.GetMapInfo then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if not ok or type(info) ~= "table" then return nil end
    return { mapID = mapID, name = self:Read(function() return info.name end),
        mapType = plainNumber(info.mapType), parentMapID = plainNumber(info.parentMapID) }
end

-- Every map under one, the whole way down. `mapType` nil asks for all of them.
function Client:GetMapChildren(mapID)
    local maps = {}
    if type(mapID) ~= "number" or not C_Map or not C_Map.GetMapChildrenInfo then return maps end
    local ok, children = pcall(C_Map.GetMapChildrenInfo, mapID, nil, true)
    if not ok or type(children) ~= "table" then return maps end
    for _, info in ipairs(children) do
        if type(info) == "table" then
            local id = plainNumber(info.mapID)
            if id then table.insert(maps, { mapID = id, name = self:Read(function() return info.name end), mapType = plainNumber(info.mapType) }) end
        end
    end
    return maps
end

-- The map's area POIs as { id, name, x, y, atlas }.
function Client:GetAreaPOIs(mapID)
    local pois = {}
    if type(mapID) ~= "number" or type(C_AreaPoiInfo) ~= "table" then return pois end
    local list = C_AreaPoiInfo.GetAreaPOIForMap
    if type(list) ~= "function" then return pois end
    local ok, ids = pcall(list, mapID)
    if not ok or type(ids) ~= "table" then return pois end
    for _, poiID in ipairs(ids) do
        local id = plainNumber(poiID)
        local infoOK, info = id and pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
        if infoOK and type(info) == "table" then
            local x, y = positionXY(info.position)
            table.insert(pois, { id = id, name = self:Read(function() return info.name end),
                x = plainNumber(x), y = plainNumber(y),
                atlas = self:Read(function() return info.atlasName end) })
        end
    end
    return pois
end

-- The map's flight points as { id, name, x, y, faction, undiscovered }. These
-- are the client's own, not the ones the player has learned: taking them from
-- here would spare a guide every flight master coordinate.
function Client:GetTaxiNodes(mapID)
    local nodes = {}
    if type(mapID) ~= "number" or type(C_TaxiMap) ~= "table" then return nodes end
    local list = C_TaxiMap.GetAllTaxiNodes or C_TaxiMap.GetTaxiNodesForMap
    if type(list) ~= "function" then return nodes end
    local ok, entries = pcall(list, mapID)
    if not ok or type(entries) ~= "table" then return nodes end
    for _, info in ipairs(entries) do
        if type(info) == "table" then
            local x, y = positionXY(info.position)
            table.insert(nodes, { id = plainNumber(info.nodeID), name = self:Read(function() return info.name end),
                x = plainNumber(x), y = plainNumber(y),
                faction = plainNumber(info.faction), undiscovered = self:Read(function() return info.isUndiscovered end) })
        end
    end
    return nodes
end

-- Where the client would pin one quest on one map. `GetNextWaypoint` came
-- back empty for every quest in the log on build 69913 while `GetQuestsOnMap`
-- answered for 39 of them, so this is the call that actually carries the data
-- on this client. The map's list is cached for a few seconds, since a tracker
-- beat would otherwise rescan it for every quest of the step.
local questPins = {}
-- Every pin the map holds for one quest, not just the first: a quest with
-- objectives in several places can be pinned more than once on the same map,
-- and which of them is "the" position is the guide's question, not the
-- client's.
function Client:GetQuestPinsOnMap(questID, mapID)
    if type(questID) ~= "number" or type(mapID) ~= "number" then return {} end
    local cached = questPins[mapID]
    local at = GetTime and GetTime() or 0
    if not cached or at - cached.at > 5 then
        cached = { at = at, quests = {} }
        self:SetMapForQuestPOIs(mapID)
        for _, quest in ipairs(self:GetQuestsOnMap(mapID)) do
            if type(quest.x) == "number" and type(quest.y) == "number" then
                local list = cached.quests[quest.questID] or {}
                table.insert(list, { x = quest.x, y = quest.y })
                cached.quests[quest.questID] = list
            end
        end
        questPins[mapID] = cached
    end
    return cached.quests[questID] or {}
end

function Client:GetQuestPinOnMap(questID, mapID)
    local pins = self:GetQuestPinsOnMap(questID, mapID)
    local first = pins[1]
    if not first then return nil end
    return first.x, first.y, #pins
end

-- The POI system is map-scoped: the client answers for whichever map it was
-- last pointed at, which is what the quest map frame does before it draws.
-- Nothing here pointed it anywhere, so every POI read was asking about
-- whatever map the client happened to be holding - a likely reason
-- `GetNextWaypoint` answered nothing. Set the map, then read.
function Client:SetMapForQuestPOIs(mapID)
    if type(mapID) ~= "number" or type(C_QuestLog) ~= "table" then return false end
    if type(C_QuestLog.SetMapForQuestPOIs) ~= "function" then return false end
    return (pcall(C_QuestLog.SetMapForQuestPOIs, mapID))
end

function Client:GetMapForQuestPOIs()
    if type(C_QuestLog) == "table" and type(C_QuestLog.GetMapForQuestPOIs) == "function" then
        local mapID = plainNumber(self:Read(C_QuestLog.GetMapForQuestPOIs))
        if mapID then return mapID end
    end
    if type(rawget(_G, "GetMapForQuestPOIs")) == "function" then
        return plainNumber(self:Read(GetMapForQuestPOIs))
    end
    return nil
end

-- How many the character has, the bank included (GetItemCount's
-- includeBank). `bagsOnly`: what the bags hold, which is all a craft can use.
function Client:GetItemCount(itemID, bagsOnly)
    if type(itemID) ~= "number" then return 0 end
    local getter = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not getter then return 0 end
    local ok, count = pcall(getter, itemID, not bagsOnly)
    return ok and tonumber(count) or 0
end

function Client:GetItemName(itemID)
    if type(itemID) ~= "number" then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and text(name) then return name end
    end
    if GetItemInfo then
        local ok, name = pcall(GetItemInfo, itemID)
        if ok and text(name) then return name end
    end
    return nil
end

-- The game's own link for an item: its quality colour, its name, and the
-- hyperlink the client answers for on hover and on click. Nil until the item
-- is in the client's cache, so callers keep the plain name as a fallback and
-- ask again on the next repaint. RequestItemData primes the cache.
function Client:GetItemLink(itemID)
    if type(itemID) ~= "number" then return nil end
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getter) ~= "function" then return nil end
    local ok, _, link = pcall(getter, itemID)
    if not ok or secret(link) or type(link) ~= "string" then return nil end
    -- A link is only useful to us whole: the escape, the item payload, and
    -- the bracketed name. Anything else is a name, which the caller has.
    if not link:find("|H", 1, true) then return nil end
    return link
end

-- Three ways to the same texture, because no one of them is everywhere: the
-- by-ID call is the modern one, GetItemInfoInstant answers from the client's
-- own files without the item being cached, and the full GetItemInfo returns
-- it tenth once the server has answered. A caller that still gets nil should
-- ask with RequestItemData and paint again when the data lands.
function Client:GetItemIcon(itemID)
    if type(itemID) ~= "number" then return nil end
    local function usable(icon)
        return type(icon) == "number" or (type(icon) == "string" and icon ~= "")
    end
    local byID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if type(byID) == "function" then
        local icon = self:Read(byID, itemID)
        if usable(icon) then return icon end
    end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(instant) == "function" then
        local ok, _, _, _, _, icon = pcall(instant, itemID)
        if ok and not secret(icon) and usable(icon) then return icon end
    end
    local full = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(full) == "function" then
        local ok, _, _, _, _, _, _, _, _, _, icon = pcall(full, itemID)
        if ok and not secret(icon) and usable(icon) then return icon end
    end
    return nil
end

-- Whether an item can be clicked at all: an item with no "Use:" on it is a
-- reagent, not a button, and the item strip leaves it out.
function Client:IsItemUsable(itemID)
    if type(itemID) ~= "number" then return false end
    local getter = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if type(getter) ~= "function" then return false end
    local ok, spell = pcall(getter, itemID)
    return ok and not secret(spell) and type(spell) == "string" and spell ~= ""
end

-- "ffa335ee" and friends: the quality colour of an item as a colour escape
-- body, for painting a name the client has no link for yet.
function Client:GetItemQualityColor(itemID)
    if type(itemID) ~= "number" then return nil end
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = self:Read(C_Item.GetItemQualityByID, itemID)
    end
    if quality == nil then
        local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if type(getter) == "function" then
            local ok, _, _, itemQuality = pcall(getter, itemID)
            if ok and not secret(itemQuality) then quality = itemQuality end
        end
    end
    if type(quality) ~= "number" or type(GetItemQualityColor) ~= "function" then return nil end
    local ok, _, _, _, hex = pcall(GetItemQualityColor, quality)
    if not ok or type(hex) ~= "string" then return nil end
    return hex
end

-- Skill ranks. The classic skill window lists every skill line, including the
-- professions; modern clients answer through GetProfessions/GetProfessionInfo
-- and keep the skill window for the rest. Both are read here so a profession
-- guide works on either. nil means the player does not have that skill, or
-- the client cannot say.
local function sameSkill(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- The subzone text the client shows under the minimap, because a subzone
-- says where the player is in a way a zone-wide coordinate cannot.
function Client:GetSubzone()
    local name = self:Read(GetSubZoneText)
    if type(name) ~= "string" or name == "" then name = self:Read(GetMinimapZoneText) end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

function Client:GetZoneName()
    local name = self:Read(GetRealZoneText)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- What is worn in an equipment slot, for the "only buy this if what you have
-- is worse" steps. Quality the client answers directly; damage per second is
-- only ever printed on the tooltip, so it is read there and comes back nil
-- wherever that fails, which the predicate reports as unknown rather than no.
function Client:GetEquippedQuality(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    local quality = self:Read(GetInventoryItemQuality, "player", slot)
    if type(quality) == "number" then return quality end
    local link = self:Read(GetInventoryItemLink, "player", slot)
    if type(link) ~= "string" then return nil end
    local _, _, linkQuality = self:Read(GetItemInfo, link)
    return type(linkQuality) == "number" and linkQuality or nil
end

-- A tooltip nobody sees, for reading what the client only prints there.
function Client:HiddenTooltip()
    if self.statTooltip then return self.statTooltip end
    if type(CreateFrame) ~= "function" then return nil end
    local ok, created = pcall(CreateFrame, "GameTooltip", "NuuRoadStatTooltip", nil, "GameTooltipTemplate")
    if not ok or not created then return nil end
    self.statTooltip = created
    if created.SetOwner and UIParent then pcall(created.SetOwner, created, UIParent, "ANCHOR_NONE") end
    return created
end

function Client:GetEquippedDPS(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    local link = self:Read(GetInventoryItemLink, "player", slot)
    if type(link) ~= "string" then return nil end
    local tooltip = self:HiddenTooltip()
    if not tooltip or not tooltip.SetHyperlink or not tooltip.NumLines then return nil end
    pcall(tooltip.ClearLines, tooltip)
    local ok = pcall(tooltip.SetHyperlink, tooltip, link)
    if not ok then return nil end
    local lines = self:Read(tooltip.NumLines, tooltip)
    for index = 1, (tonumber(lines) or 0) do
        local fontString = _G["NuuRoadStatTooltipTextLeft" .. index]
        local text = fontString and fontString.GetText and self:Read(fontString.GetText, fontString)
        if type(text) == "string" then
            local dps = text:match("([%d%.]+) damage per second")
            if dps then return tonumber(dps) end
        end
    end
    return nil
end

function Client:GetSkillRank(name)
    if type(name) ~= "string" then return nil end
    if GetNumSkillLines and GetSkillLineInfo then
        local count = self:Read(GetNumSkillLines)
        for index = 1, tonumber(count) or 0 do
            local ok, skillName, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, index)
            if ok and not isHeader and sameSkill(skillName, name) and not secret(rank) then
                return tonumber(rank) or 0, tonumber(maxRank)
            end
        end
    end
    for skillName, entry in pairs(self:GetProfessionRanks() or {}) do
        if sameSkill(skillName, name) then return entry.rank, entry.maxRank end
    end
    return nil
end

-- The professions the modern call hands over, as { [name] = { rank, maxRank } },
-- or nil when the client has no such call. GetProfessions returns a fixed row
-- of slots with nil for each one empty (no second profession, no archaeology),
-- so the slots are walked by position: `ipairs` would stop at the first gap
-- and never reach cooking or fishing behind it. An empty table is an answer:
-- the character has no profession.
function Client:GetProfessionRanks()
    local list, info = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
    if type(list) ~= "function" or type(info) ~= "function" then return nil end
    local results = { pcall(list) }
    if not results[1] then return nil end
    local ranks = {}
    for index = 2, table.maxn(results) do
        local slot = results[index]
        if slot ~= nil and not secret(slot) then
            local ok, skillName, _, rank, maxRank = pcall(info, slot)
            if ok and type(skillName) == "string" and not secret(skillName) and not secret(rank) then
                ranks[skillName] = { rank = tonumber(rank) or 0, maxRank = tonumber(maxRank) }
            end
        end
    end
    return ranks
end

function Client:HasSkillRank(name, atLeast)
    local rank = self:GetSkillRank(name)
    if rank == nil then return false end
    return rank >= (tonumber(atLeast) or 1)
end

-- Reputation with one faction: standing (1 Hated to 8 Exalted), the bar value
-- inside that standing, and what the bar needs to fill. nil when the player
-- has no standing with the faction yet or the client cannot say.
function Client:GetFactionStanding(factionID)
    if type(factionID) ~= "number" then return nil end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and type(data) == "table" and not secret(data.reaction) then
            local standing = tonumber(data.reaction)
            if standing then
                local floor = tonumber(data.currentReactionThreshold) or 0
                local ceiling = tonumber(data.nextReactionThreshold) or 0
                local value = (tonumber(data.currentStanding) or 0) - floor
                return standing, value, math.max(ceiling - floor, 0), data.name
            end
        end
    end
    if GetFactionInfoByID then
        local ok, name, _, standing, barMin, barMax, barValue = pcall(GetFactionInfoByID, factionID)
        if ok and tonumber(standing) and not secret(barValue) then
            barMin, barMax, barValue = tonumber(barMin) or 0, tonumber(barMax) or 0, tonumber(barValue) or 0
            return tonumber(standing), barValue - barMin, math.max(barMax - barMin, 0), name
        end
    end
    return nil
end

function Client:GetFactionName(factionID)
    local _, _, _, name = self:GetFactionStanding(factionID)
    if type(name) == "string" and #name > 0 then return name end
    return nil
end

-- Worn gear, which GetItemCount does not count: an equipped item is no longer
-- in the bags. The slot scan is the fallback where IsEquippedItem is missing.
function Client:IsItemEquipped(itemID)
    if type(itemID) ~= "number" then return false end
    if IsEquippedItem then
        local ok, equipped = pcall(IsEquippedItem, itemID)
        if ok and not secret(equipped) then return equipped == true end
    end
    if GetInventoryItemID then
        for slot = 1, 19 do
            local ok, id = pcall(GetInventoryItemID, "player", slot)
            if ok and not secret(id) and tonumber(id) == itemID then return true end
        end
    end
    return false
end

-- Creature ID out of a GUID ("Creature-0-1234-1413-5-3448-00001234").
-- Players, pets, and anything the client cannot see answer nil.
function Client:CreatureIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

function Client:GetUnitGUID(unit)
    local guid = self:Read(UnitGUID, unit)
    if type(guid) == "string" then return guid end
    return nil
end

function Client:GetUnitCreatureID(unit)
    return self:CreatureIDFromGUID(self:GetUnitGUID(unit))
end

function Client:UnitIsDead(unit)
    return self:Read(UnitIsDeadOrGhost, unit) == true
end

function Client:UnitInCombat(unit)
    return self:Read(UnitAffectingCombat, unit) == true
end

-- True when another player or group has the creature tagged.
function Client:UnitIsTapDenied(unit)
    return self:Read(UnitIsTapDenied, unit) == true
end

-- Registers an event for one unit where the client supports it, otherwise for all.
function Client:RegisterUnitEvent(frame, event, unit)
    if frame.RegisterUnitEvent then
        local ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
        if ok then return true end
    end
    return pcall(frame.RegisterEvent, frame, event) == true
end

-- True while the player is riding a flight path. Nothing they do steers a
-- taxi, so the arrow has nothing to say until they land.
function Client:IsOnTaxi()
    if not self.capabilities.taxiState then return false end
    return self:Read(UnitOnTaxi, "player") == true
end

function Client:UnitExists(unit)
    return self:Read(UnitExists, unit) == true
end

-- Raid target markers, 1 (star) to 8 (skull). In a raid only the leader and
-- assistants may mark; solo and in a party anyone may.
function Client:MayMarkInGroup()
    if self:Read(IsInRaid) == true then
        return self:Read(UnitIsGroupLeader, "player") == true or self:Read(UnitIsGroupAssistant, "player") == true
    end
    return true
end

-- True when the addon may call SetRaidTarget itself: never in combat, never
-- on clients that protect it, and never again once a call was refused.
function Client:CanMarkTargets()
    if not SetRaidTarget or not self.capabilities.targetMarkers or self.markingForbidden then return false end
    if self:InCombatLockdown() then return false end
    return self:MayMarkInGroup()
end

-- A hidden button that runs its own macro text when its key is pressed. Only
-- the key-down click is registered, so a press cannot fire the text twice.
function Client:CreateSecureMacroButton(name, macrotext)
    if not CreateFrame then return nil end
    local ok, button = pcall(CreateFrame, "Button", name, UIParent, "SecureActionButtonTemplate")
    if not ok or not button or not button.SetAttribute then return nil end
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macrotext or "")
    if button.RegisterForClicks then button:RegisterForClicks("AnyDown") end
    return button
end

-- Rewrites the macro text behind a secure button. False in combat, when the
-- attribute is locked.
function Client:SetSecureMacroText(button, macrotext)
    if not button or not button.SetAttribute or self:InCombatLockdown() then return false end
    return pcall(button.SetAttribute, button, "macrotext", macrotext) == true
end

function Client:GetBindingKeyForButton(buttonName)
    if not GetBindingKey then return nil end
    local ok, key = pcall(GetBindingKey, "CLICK " .. buttonName .. ":LeftButton")
    return ok and type(key) == "string" and key or nil
end

-- Binds `key` to clicking the button, saved with the character's bindings.
-- `key` nil removes the current binding. False in combat.
function Client:BindKeyToButton(key, buttonName)
    if not SetBindingClick or not SetBinding or self:InCombatLockdown() then return false end
    local current = self:GetBindingKeyForButton(buttonName)
    if current then pcall(SetBinding, current) end
    if key then
        local ok, done = pcall(SetBindingClick, key, buttonName, "LeftButton")
        if not ok or done == false then return false end
    end
    if SaveBindings and GetCurrentBindingSet then pcall(SaveBindings, GetCurrentBindingSet()) end
    return true
end

-- The marker `unit` carries, or nil when it carries none. The second value is
-- false when the client hid the answer, which is not the same as "no marker":
-- it happens while our own macro drove the targeting. Callers that would mark
-- must not treat an unreadable marker as an absent one, since "/tm" toggles.
function Client:GetRaidTargetIndex(unit)
    if not GetRaidTargetIndex then return nil, true end
    local ok, index = pcall(GetRaidTargetIndex, unit)
    if not ok or secret(index) then return nil, false end
    if type(index) == "number" and index > 0 then return index, true end
    return nil, true
end

-- Reading a marker off the frame that draws it, for a client that will not
-- report the number (see docs/api-compatibility.md: on 1.60.1 a marker that
-- is present always comes back secret, and only its absence reads plainly).
-- Every raid target icon is one cell of a single atlas, and the cell is
-- chosen with SetTexCoord, so the texture coordinates say which marker it is
-- without anything ever looking at the index. Those coordinates are the
-- frame's own numbers, not a value the client is guarding.
-- The atlas is "UI-RaidTargetingIcons" and the textures that draw from it
-- are named "...RaidTargetIcon": "raidtarget" is the longest needle that
-- catches both, since one spells it "targeting" and the other "target".
local RAID_ICON_NEEDLE = "raidtarget"
local TEXTURE_SEARCH_DEPTH = 4
local unitFrame -- defined below; the icon lookup above it needs the name

local function call(object, method, ...)
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local results = { pcall(fn, object, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

-- SetRaidTargetIconTexture cuts the atlas into quarters both ways and takes
-- cell `index - 1`, left to right and top to bottom. This undoes it.
function Client.RaidIconFromTexCoords(...)
    local values = { ... }
    local left, top
    if #values >= 8 then left, top = values[1], values[2]      -- UL x, UL y
    elseif #values == 4 then left, top = values[1], values[3]  -- left, right, top, bottom
    else return nil end
    if type(left) ~= "number" or type(top) ~= "number" then return nil end
    -- On 1.60.1 the coordinates come back secret as well, and the first
    -- multiplication below throws rather than returning anything. Nothing is
    -- learned from a secret, so the answer is no answer; Client:CopyRaidIcon
    -- is how the icon is shown without ever knowing which one it is.
    if secret(left) or secret(top) then return nil end
    local column, row = math.floor(left * 4 + 0.5), math.floor(top * 4 + 0.5)
    if column < 0 or column > 3 or row < 0 or row > 3 then return nil end
    local index = row * 4 + column + 1
    if index < 1 or index > 8 then return nil end
    return index
end

-- Whether a region is the raid marker: by the file it draws, by its atlas,
-- or by its own name. The file can come back as a numeric file ID rather
-- than a path, which is why the name is checked too.
local function isRaidIcon(region)
    if call(region, "GetObjectType") ~= "Texture" then return false end
    for _, method in ipairs({ "GetTexture", "GetAtlas", "GetName", "GetDebugName" }) do
        local value = call(region, method)
        if type(value) == "string" and string.find(string.lower(value), RAID_ICON_NEEDLE, 1, true) then return true end
    end
    return false
end

-- Where the client has kept this texture in past layouts. Tried before the
-- search, since a named path costs nothing and cannot pick up a stray.
local KNOWN_ICON_PATHS = {
    { "raidTargetIcon" },
    { "RaidTargetFrame", "RaidTargetIcon" },
    { "TargetFrameContent", "TargetFrameContentMain", "RaidTargetFrame", "RaidTargetIcon" },
    { "UnitFrame", "RaidTargetFrame", "RaidTargetIcon" },
    { "UnitFrame", "raidTargetIcon" },
}

local function atPath(frame, path)
    local node = frame
    for _, key in ipairs(path) do
        local ok, value = pcall(function() return node[key] end)
        if not ok or (type(value) ~= "table" and type(value) ~= "userdata") then return nil end
        node = value
    end
    return node
end

local function raidIconTexture(frame, depth)
    if depth > TEXTURE_SEARCH_DEPTH or (type(frame) ~= "table" and type(frame) ~= "userdata") then return nil end
    if call(frame, "IsShown") == false then return nil end
    if depth == 0 then
        for _, path in ipairs(KNOWN_ICON_PATHS) do
            local region = atPath(frame, path)
            if region and call(region, "IsShown") == true and call(region, "GetObjectType") == "Texture" then return region end
        end
    end
    for _, region in ipairs({ call(frame, "GetRegions") }) do
        if call(region, "IsShown") == true and isRaidIcon(region) then return region end
    end
    for _, child in ipairs({ call(frame, "GetChildren") }) do
        local found = raidIconTexture(child, depth + 1)
        if found then return found end
    end
    return nil
end

-- Every texture under `frame`, as "where it is = what it draws", for the
-- marking diagnostics: what to read when the search above finds nothing.
function Client:DescribeTextures(frame, depth, out, trail)
    out, trail, depth = out or {}, trail or "", depth or 0
    if depth > TEXTURE_SEARCH_DEPTH or (type(frame) ~= "table" and type(frame) ~= "userdata") then return out end
    for index, region in ipairs({ call(frame, "GetRegions") }) do
        if call(region, "GetObjectType") == "Texture" then
            local name = call(region, "GetName") or call(region, "GetDebugName") or (trail .. "region " .. index)
            local file = call(region, "GetTexture")
            local atlas = call(region, "GetAtlas")
            table.insert(out, string.format("%s = %s%s%s", tostring(name),
                type(file) == "string" and file or ("file " .. tostring(file)),
                atlas and (" atlas " .. tostring(atlas)) or "",
                call(region, "IsShown") == true and "" or " (hidden)"))
        end
    end
    for index, child in ipairs({ call(frame, "GetChildren") }) do
        self:DescribeTextures(child, depth + 1, out, trail .. index .. ".")
    end
    return out
end

-- The frame's own icon texture for `unit`, or nil. Kept apart from reading
-- it so the diagnostics can say whether the texture was found at all.
function Client:GetRaidTargetIconTexture(unit)
    local frame = unitFrame(unit)
    return frame and raidIconTexture(frame, 0) or nil
end

-- The frame the client draws `unit` in, for the units a marker can be read
-- off. Nothing for "mouseover", which has no frame of its own.
function unitFrame(unit) -- fills the local declared above, not a global
    if unit == "target" then return rawget(_G, "TargetFrame") end
    if unit == "focus" then return rawget(_G, "FocusFrame") end
    if type(unit) == "string" and string.find(unit, "^nameplate")
        and C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok then return plate end
    end
    return nil
end

-- Puts the marker `unit` is wearing onto `dest`, by copying the source
-- texture and its coordinates straight across. Nothing here looks at a
-- value: the file and the coordinates go from one texture to the other
-- untouched, so a client that guards them can still be asked to draw them.
-- The caller learns whether it worked, never which marker it is.
local RAID_ICON_FILE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- Kept for the diagnostics and for a client that guards less than this one.
-- Nothing on screen uses it: on 1.60.1 the coordinates copied here are
-- secret and the texture renders as nothing, tested 2026-09-21.
function Client:CopyRaidIcon(dest, unit)
    local source = self:GetRaidTargetIconTexture(unit)
    if not source or (type(dest) ~= "table" and type(dest) ~= "userdata") then return false end
    return pcall(function()
        -- The file is public and fixed, so it is set from a constant rather
        -- than copied: only the cell within it is guarded, and only that is
        -- taken across. Handing a texture a file the client handed us is the
        -- part most likely to draw nothing.
        dest:SetTexture(RAID_ICON_FILE)
        dest:SetTexCoord(source:GetTexCoord())
    end) == true
end

-- The marker `unit` wears, read off the frame that draws it, or nil when
-- there is no frame for the unit and no icon texture shown in it. Absence
-- here is never evidence: "carries nothing" and "no frame to look at" come
-- back the same way.
function Client:GetRaidTargetIconFromFrame(unit)
    local frame = unitFrame(unit)
    if not frame then return nil end
    local texture = raidIconTexture(frame, 0)
    if not texture then return nil end
    return Client.RaidIconFromTexCoords(call(texture, "GetTexCoord"))
end

-- Called for ADDON_ACTION_FORBIDDEN. A protected call does not raise a Lua
-- error (pcall cannot catch it), so this is the only way to learn the client
-- refused SetRaidTarget; after that, marking stays off for the session.
function Client:OnActionForbidden(addon, func)
    if addon ~= ns.name or self.markingForbidden then return false end
    if func ~= nil and func ~= "UNKNOWN()" and not tostring(func):find("SetRaidTarget", 1, true) then return false end
    self.markingForbidden = true
    ns:Log("this client protects SetRaidTarget; marking targets is disabled")
    return true
end

function Client:SetRaidTarget(unit, index)
    if not SetRaidTarget or self.markingForbidden then return false end
    return pcall(SetRaidTarget, unit, index or 0) == true
end

-- Unit tokens of every visible nameplate.
function Client:GetNamePlateUnits()
    local units = {}
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return units end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return units end
    for _, plate in ipairs(plates) do
        local unit = type(plate) == "table" and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
        if type(unit) == "string" then table.insert(units, unit) end
    end
    return units
end

-- The current combat log entry as { subevent, sourceGUID, destGUID, destName }.
-- Newer clients expose it through CombatLogGetCurrentEventInfo; older ones
-- pass the same values as event arguments.
function Client:GetCombatLogEvent(...)
    local timestamp, subevent, _, sourceGUID, _, _, _, destGUID, destName
    if CombatLogGetCurrentEventInfo then
        local ok
        ok, timestamp, subevent, _, sourceGUID, _, _, _, destGUID, destName = pcall(CombatLogGetCurrentEventInfo)
        if not ok then return nil end
    else
        timestamp, subevent, _, sourceGUID, _, _, _, destGUID, destName = ...
    end
    if type(subevent) ~= "string" then return nil end
    return { subevent = subevent, sourceGUID = sourceGUID, destGUID = destGUID, destName = destName }
end

function Client:IsPlayerOrGroupGUID(guid)
    if type(guid) ~= "string" then return false end
    local playerGUID = self:GetUnitGUID("player")
    if guid == playerGUID then return true end
    if guid == self:GetUnitGUID("pet") then return true end
    if guid:match("^Pet%-") then return true end
    for index = 1, 4 do
        if guid == self:GetUnitGUID("party" .. index) or guid == self:GetUnitGUID("partypet" .. index) then return true end
    end
    return false
end

function Client:IsShiftDown()
    return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end

-- Quest lines of an open gossip window as { available = {...}, active = {...} }.
-- Each entry carries `title`, `index`, and `questID` when the client gives
-- IDs; active entries also carry `isComplete`. Classic-era clients list
-- gossip quests as flat tuples without IDs, so callers match by title then.
function Client:GetGossipQuests()
    local result = { available = {}, active = {} }
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetActiveQuests then
        local ok, available = pcall(C_GossipInfo.GetAvailableQuests)
        for index, quest in ipairs(ok and type(available) == "table" and available or {}) do
            table.insert(result.available, { index = index, questID = quest.questID, title = quest.title })
        end
        local activeOK, active = pcall(C_GossipInfo.GetActiveQuests)
        for index, quest in ipairs(activeOK and type(active) == "table" and active or {}) do
            table.insert(result.active, { index = index, questID = quest.questID, title = quest.title, isComplete = quest.isComplete == true })
        end
        return result
    end
    if GetGossipAvailableQuests then
        local ok, values = pcall(function() return { GetGossipAvailableQuests() } end)
        local stride = 7 -- title, level, isTrivial, frequency, isRepeatable, isLegendary, isIgnored
        for position = 1, ok and #values or 0, stride do
            table.insert(result.available, { index = #result.available + 1, title = values[position] })
        end
    end
    if GetGossipActiveQuests then
        local ok, values = pcall(function() return { GetGossipActiveQuests() } end)
        local stride = 6 -- title, level, isTrivial, isComplete, isLegendary, isIgnored
        for position = 1, ok and #values or 0, stride do
            table.insert(result.active, { index = #result.active + 1, title = values[position], isComplete = values[position + 3] == true })
        end
    end
    return result
end

function Client:SelectGossipAvailableQuest(entry)
    if C_GossipInfo and C_GossipInfo.SelectAvailableQuest and entry.questID then
        return pcall(C_GossipInfo.SelectAvailableQuest, entry.questID) == true
    end
    if SelectGossipAvailableQuest then return pcall(SelectGossipAvailableQuest, entry.index) == true end
    return false
end

function Client:SelectGossipActiveQuest(entry)
    if C_GossipInfo and C_GossipInfo.SelectActiveQuest and entry.questID then
        return pcall(C_GossipInfo.SelectActiveQuest, entry.questID) == true
    end
    if SelectGossipActiveQuest then return pcall(SelectGossipActiveQuest, entry.index) == true end
    return false
end

-- Quest lines of a QUEST_GREETING window (quest givers without gossip), same
-- shape as GetGossipQuests. Only active quests carry an ID, and only on
-- clients that have GetActiveQuestID.
function Client:GetGreetingQuests()
    local result = { available = {}, active = {} }
    if GetNumAvailableQuests and GetAvailableTitle then
        local ok, count = pcall(GetNumAvailableQuests)
        for index = 1, ok and tonumber(count) or 0 do
            local titleOK, title = pcall(GetAvailableTitle, index)
            table.insert(result.available, { index = index, title = titleOK and title or nil })
        end
    end
    if GetNumActiveQuests and GetActiveTitle then
        local ok, count = pcall(GetNumActiveQuests)
        for index = 1, ok and tonumber(count) or 0 do
            local titleOK, title, isComplete = pcall(GetActiveTitle, index)
            local entry = { index = index, title = titleOK and title or nil, isComplete = titleOK and isComplete == true }
            if GetActiveQuestID then
                local idOK, questID = pcall(GetActiveQuestID, index)
                if idOK and type(questID) == "number" and questID > 0 then entry.questID = questID end
            end
            table.insert(result.active, entry)
        end
    end
    return result
end

function Client:SelectGreetingAvailableQuest(entry)
    if not SelectAvailableQuest then return false end
    return pcall(SelectAvailableQuest, entry.index) == true
end

function Client:SelectGreetingActiveQuest(entry)
    if not SelectActiveQuest then return false end
    return pcall(SelectActiveQuest, entry.index) == true
end

-- The quest shown in an open QUEST_DETAIL, QUEST_PROGRESS, or QUEST_COMPLETE dialog.
function Client:GetOpenQuestID()
    if not GetQuestID then return nil end
    local ok, questID = pcall(GetQuestID)
    if ok and type(questID) == "number" and questID > 0 then return questID end
    return nil
end

-- Experience the open quest dialog offers (QUEST_DETAIL, QUEST_COMPLETE).
function Client:GetOpenQuestRewardXP()
    local xp = plainNumber(self:Read(rawget(_G, "GetRewardXP")))
    return xp and xp > 0 and xp or nil
end

-- Experience a quest in the log gives. The modern call takes the quest ID;
-- an older one reads the selected quest, so the answer is taken only for a
-- quest the log holds.
function Client:GetQuestLogRewardXP(questID)
    if not self:IsQuestInLog(questID) then return nil end
    local xp = plainNumber(self:Read(rawget(_G, "GetQuestLogRewardXP"), questID))
    return xp and xp > 0 and xp or nil
end

function Client:AcceptOpenQuest()
    if not AcceptQuest then return false end
    return pcall(AcceptQuest) == true
end

function Client:IsOpenQuestCompletable()
    if not IsQuestCompletable then return false end
    local ok, completable = pcall(IsQuestCompletable)
    return ok and completable == true
end

function Client:CompleteOpenQuest()
    if not CompleteQuest then return false end
    return pcall(CompleteQuest) == true
end

function Client:GetOpenQuestChoiceCount()
    if not GetNumQuestChoices then return 0 end
    local ok, count = pcall(GetNumQuestChoices)
    return ok and tonumber(count) or 0
end

-- Finishes an open QUEST_COMPLETE dialog. `choice` is 0 when the quest offers
-- no choice of reward, otherwise the index of the reward to take.
function Client:TakeOpenQuestReward(choice)
    if not GetQuestReward then return false end
    return pcall(GetQuestReward, choice or 0) == true
end

-- True while the client forbids changes to secure frames (in combat).
function Client:InCombatLockdown()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

-- Paints a unit's portrait onto a texture; false when the unit is not in view.
function Client:SetUnitPortrait(texture, unit)
    if not SetPortraitTexture or not self:UnitExists(unit) then return false end
    return pcall(SetPortraitTexture, texture, unit) == true
end

-- A live 3D model for a creature, the way the game's own unit frames draw a
-- portrait: the model is drawn on nothing, so it has none of the black disc
-- that SetPortraitTexture bakes into its picture. Nil where the client has no
-- PlayerModel or no SetUnit on it; the caller keeps the flat portrait then.
function Client:CreatePortraitModel(parent)
    if not CreateFrame then return nil end
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
    if not ok or not model or type(model.SetUnit) ~= "function" then return nil end
    -- The portrait camera is only placed once the creature's model has
    -- loaded, which can be after SetUnit returns, so the model is framed
    -- again then.
    if model.HasScript and model:HasScript("OnModelLoaded") then
        model:SetScript("OnModelLoaded", function(self) Client:FramePortrait(self) end)
    end
    return model
end

-- The game's head shot (portrait zoom 1) crops a creature to its face in a
-- 32 px slot, too close to tell one from another, and sat low in it. The
-- strip uses the whole-body shot (zoom 0) instead, centred on the body.
local PORTRAIT_ZOOM = 0

function Client:FramePortrait(model)
    if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, PORTRAIT_ZOOM) end
    if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
    if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
end

-- Puts the unit on the model. False when the call failed, so the caller can
-- fall back to the flat portrait.
function Client:SetModelUnit(model, unit)
    if not model or not self:UnitExists(unit) then return false end
    if model.ClearModel then pcall(model.ClearModel, model) end
    if not pcall(model.SetUnit, model, unit) then return false end
    self:FramePortrait(model)
    return true
end

-- Puts a creature back on a model by ID, for a model the client emptied while
-- it was hidden. Only a creature the client has seen this session is cached,
-- which is every one a slot has shown by unit.
function Client:SetModelCreature(model, creatureID)
    if not model or type(model.SetCreature) ~= "function" or not creatureID then return false end
    if not pcall(model.SetCreature, model, creatureID) then return false end
    self:FramePortrait(model)
    return true
end

function Client:GetUnitName(unit)
    if not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    if ok and text(name) then return name end
    return nil
end

-- The player's name as the game shows it, surname included where the client
-- answers one. UnitName("player") gave "Dill Douse" on build 69977 and "Dill"
-- on 70009; which call still carries the surname is not known yet (see
-- DescribePlayerNames), so this is UnitName until one is found.
function Client:GetPlayerFullName()
    return self:GetUnitName("player")
end

-- For `/nuuroad db`: what each candidate call answers for the player's name.
-- Forever characters have a surname that UnitName stopped returning (build
-- 70009), and which call still carries it is not known yet.
function Client:DescribePlayerNames()
    local function show(ok, ...)
        if not ok then return "error" end
        local parts = {}
        for index = 1, math.max(select("#", ...), 1) do
            local value = select(index, ...)
            parts[index] = secret(value) and "secret" or (type(value) == "string" and ('"' .. value .. '"') or tostring(value))
        end
        return table.concat(parts, ", ")
    end
    local function try(label, func, ...)
        if type(func) ~= "function" then return label .. ": missing" end
        return label .. ": " .. show(pcall(func, ...))
    end
    local function frameText(label, frame)
        if type(frame) ~= "table" or type(frame.GetText) ~= "function" then return label .. ": missing" end
        return label .. ": " .. show(pcall(frame.GetText, frame))
    end
    local lines = {
        try("UnitName", rawget(_G, "UnitName"), "player"),
        try("UnitFullName", rawget(_G, "UnitFullName"), "player"),
        try("GetUnitName(true)", rawget(_G, "GetUnitName"), "player", true),
        try("UnitPVPName", rawget(_G, "UnitPVPName"), "player"),
        frameText("CharacterNameText", rawget(_G, "CharacterNameText")),
        frameText("CharacterFrameTitleText", rawget(_G, "CharacterFrameTitleText")),
    }
    local info, location = rawget(_G, "C_PlayerInfo"), rawget(_G, "PlayerLocation")
    if type(info) == "table" and type(location) == "table" and type(location.CreateFromUnit) == "function" then
        local ok, here = pcall(location.CreateFromUnit, location, "player")
        table.insert(lines, ok and try("C_PlayerInfo.GetName", info.GetName, here) or "C_PlayerInfo.GetName: no location")
    else
        table.insert(lines, "C_PlayerInfo.GetName: missing")
    end
    -- Any call the client names after a surname.
    local found = {}
    local function scan(tableName, source)
        for key, value in pairs(source) do
            if type(key) == "string" and key:lower():find("surname", 1, true) then
                table.insert(found, tableName .. key .. (type(value) == "function" and "()" or ""))
            end
        end
    end
    scan("", _G)
    for key, value in pairs(_G) do
        if type(key) == "string" and key:find("^C_") and type(value) == "table" then scan(key .. ".", value) end
    end
    table.sort(found)
    table.insert(lines, "Names with 'surname': " .. (#found > 0 and table.concat(found, ", ") or "none"))
    return lines
end

-- Title shown in an open quest dialog (QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE).
function Client:GetQuestDialogTitle()
    if not GetTitleText then return nil end
    local ok, title = pcall(GetTitleText)
    if ok and text(title) then return title end
    return nil
end

-- The quest selected in the quest log, as ID and title; nil while a header or
-- nothing is selected. The retail-style log answers by ID, the classic one by
-- log index.
function Client:GetSelectedQuestLogQuest()
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local ok, questID = pcall(C_QuestLog.GetSelectedQuest)
        if ok and type(questID) == "number" and questID > 0 then return questID, self:GetQuestTitle(questID) end
    end
    if GetQuestLogSelection then
        local ok, index = pcall(GetQuestLogSelection)
        if ok and type(index) == "number" and index > 0 then
            if GetQuestLogTitle then
                local titleOK, title, _, _, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, index)
                if titleOK and not isHeader and type(questID) == "number" and questID > 0 then return questID, title end
            end
            if C_QuestLog and C_QuestLog.GetInfo then
                local infoOK, info = pcall(C_QuestLog.GetInfo, index)
                if infoOK and type(info) == "table" and not info.isHeader and type(info.questID) == "number" and info.questID > 0 then return info.questID, info.title end
            end
        end
    end
    return nil
end

-- The row the quest log is parked on, on the clients whose log is addressed by
-- position; nil on a log that remembers a quest ID, where the position cannot
-- go stale. Callers use it to tell a log that renumbered under a stored
-- selection from a player who clicked another quest.
function Client:GetSelectedQuestLogIndex()
    if C_QuestLog and C_QuestLog.GetSelectedQuest then return nil end
    if not GetQuestLogSelection then return nil end
    local ok, index = pcall(GetQuestLogSelection)
    if ok and type(index) == "number" and index > 0 then return index end
    return nil
end

-- The quest log index of a quest, for the clients whose log is addressed by
-- position rather than by ID.
function Client:GetQuestLogIndex(questID)
    if type(questID) ~= "number" then return nil end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and type(index) == "number" and index > 0 then return index end
    end
    if GetQuestLogIndexByID then
        local ok, index = pcall(GetQuestLogIndexByID, questID)
        if ok and type(index) == "number" and index > 0 then return index end
    end
    return nil
end

-- Repaints an open quest log so it shows a selection set from code; harmless
-- while the log is closed, and nothing at all on a client with neither call.
function Client:RefreshQuestLogUI()
    for _, name in ipairs({ "QuestLog_Update", "QuestMapFrame_UpdateAll" }) do
        if type(_G[name]) == "function" then pcall(_G[name]) end
    end
end

-- Points the quest log at a quest, the way clicking its row does. The classic
-- log's own `QuestLog_SetSelection` is preferred where it exists, since it
-- selects and repaints in one go (other addons watching the log still hear
-- about it); otherwise the retail-style `C_QuestLog.SetSelectedQuest` takes
-- the ID and the legacy `SelectQuestLogEntry` the log index, each followed by
-- a repaint.
function Client:SelectQuestInLog(questID)
    if type(questID) ~= "number" then return false end
    local index = self:GetQuestLogIndex(questID)
    if index and type(QuestLog_SetSelection) == "function" and pcall(QuestLog_SetSelection, index) then return true end
    if C_QuestLog and C_QuestLog.SetSelectedQuest and pcall(C_QuestLog.SetSelectedQuest, questID) then
        self:RefreshQuestLogUI()
        return true
    end
    if index and SelectQuestLogEntry and pcall(SelectQuestLogEntry, index) then
        self:RefreshQuestLogUI()
        return true
    end
    return false
end

-- The frame that shows the selected quest's text, for a button to hang on:
-- the classic log's detail page, else the retail map's details pane.
function Client:GetQuestLogDetailFrame()
    for _, name in ipairs({ "QuestLogDetailScrollChildFrame", "QuestLogFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden()) then return frame end
    end
    if type(QuestMapFrame) == "table" and type(QuestMapFrame.DetailsFrame) == "table" then return QuestMapFrame.DetailsFrame end
    return nil
end

-- The panel of an open quest offer (QUEST_DETAIL), for the same button.
function Client:GetQuestOfferFrame()
    for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden()) then return frame end
    end
    return nil
end

-- Runs `callback` after the quest log shows another quest. Returns the names
-- of the UI functions hooked, empty when this client has none of them.
function Client:OnQuestLogSelection(callback)
    local hooked = {}
    if not hooksecurefunc then return hooked end
    for _, name in ipairs({ "QuestLog_SetSelection", "QuestMapFrame_ShowQuestDetails", "QuestLogPopupDetailFrame_Show" }) do
        if type(_G[name]) == "function" and pcall(hooksecurefunc, name, callback) then table.insert(hooked, name) end
    end
    return hooked
end

-- Runs `callback(tooltip, questID, title)` whenever a tooltip shows a quest:
-- a quest link (`SetHyperlink("quest:<id>")`, so the ID is known), the retail
-- tooltip data pipeline (Enum.TooltipDataType.Quest, ID from the data), or the
-- classic OnTooltipSetQuest script, where only the title line is known.
-- Returns the names of the hooks placed.
function Client:OnQuestTooltip(callback)
    local hooked = {}
    if type(GameTooltip) ~= "table" then return hooked end
    if hooksecurefunc and type(GameTooltip.SetHyperlink) == "function" then
        local ok = pcall(hooksecurefunc, GameTooltip, "SetHyperlink", function(tooltip, link)
            local id = type(link) == "string" and link:match("quest:(%d+)")
            if id then callback(tooltip, tonumber(id), nil) end
        end)
        if ok then table.insert(hooked, "GameTooltip.SetHyperlink") end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Quest then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Quest, function(tooltip, data)
            local id = type(data) == "table" and tonumber(data.id)
            callback(tooltip, id, nil)
        end)
        if ok then table.insert(hooked, "TooltipDataProcessor") end
    elseif GameTooltip.HookScript then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetQuest", function(tooltip)
            local name = tooltip.GetName and tooltip:GetName()
            local line = name and _G[name .. "TextLeft1"]
            callback(tooltip, nil, line and line.GetText and line:GetText() or nil)
        end)
        if ok then table.insert(hooked, "OnTooltipSetQuest") end
    end
    return hooked
end

-- Runs `callback(button, questID, title)` when the mouse enters a quest row of
-- the quest log: the classic list (rows carry the log index) or the retail
-- map list (rows carry the quest ID). Returns the names of the hooks placed.
function Client:OnQuestLogRowEnter(callback)
    local hooked = {}
    if not hooksecurefunc then return hooked end
    if type(QuestLogTitleButton_OnEnter) == "function" then
        local ok = pcall(hooksecurefunc, "QuestLogTitleButton_OnEnter", function(button)
            if type(button) ~= "table" or button.isHeader then return end
            local index = button.GetID and button:GetID()
            if type(index) ~= "number" or index <= 0 then return end
            if GetQuestLogTitle then
                local titleOK, title, _, _, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, index)
                if titleOK and not isHeader and type(questID) == "number" and questID > 0 then callback(button, questID, title) end
            elseif C_QuestLog and C_QuestLog.GetInfo then
                local infoOK, info = pcall(C_QuestLog.GetInfo, index)
                if infoOK and type(info) == "table" and not info.isHeader and type(info.questID) == "number" then callback(button, info.questID, info.title) end
            end
        end)
        if ok then table.insert(hooked, "QuestLogTitleButton_OnEnter") end
    end
    if type(QuestMapLogTitleButton_OnEnter) == "function" then
        local ok = pcall(hooksecurefunc, "QuestMapLogTitleButton_OnEnter", function(button)
            if type(button) == "table" and type(button.questID) == "number" then callback(button, button.questID, nil) end
        end)
        if ok then table.insert(hooked, "QuestMapLogTitleButton_OnEnter") end
    end
    return hooked
end

-- Whether `tooltip` is currently anchored to `owner`.
function Client:TooltipOwnedBy(tooltip, owner)
    if type(tooltip) ~= "table" or not tooltip.GetOwner then return false end
    local ok, current = pcall(tooltip.GetOwner, tooltip)
    return ok and current == owner
end

-- Every quest in the log as { questID, title }, headers skipped.
function Client:GetQuestLogEntries()
    local entries = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
        for index = 1, ok and tonumber(count) or 0 do
            local infoOK, info = pcall(C_QuestLog.GetInfo, index)
            if infoOK and type(info) == "table" and not info.isHeader and type(info.questID) == "number" and info.questID > 0 then
                table.insert(entries, { questID = info.questID, title = info.title })
            end
        end
        return entries
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        local ok, count = pcall(GetNumQuestLogEntries)
        for index = 1, ok and tonumber(count) or 0 do
            local titleOK, title, _, _, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, index)
            if titleOK and not isHeader and type(questID) == "number" and questID > 0 then
                table.insert(entries, { questID = questID, title = title })
            end
        end
    end
    return entries
end

local function nameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h")
end

-- Every item in the backpack and bags as { itemID, name }, one entry per stack.
function Client:GetBagItems()
    local items = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return items end
    local lastBag = NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        local ok, slots = pcall(numSlots, bag)
        for slot = 1, ok and tonumber(slots) or 0 do
            local itemID, link
            if C_Container and C_Container.GetContainerItemInfo then
                local infoOK, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if infoOK and type(info) == "table" then itemID, link = info.itemID, info.hyperlink end
            else
                local idOK, id = pcall(GetContainerItemID, bag, slot)
                if idOK then itemID = id end
                if GetContainerItemLink then
                    local linkOK, itemLink = pcall(GetContainerItemLink, bag, slot)
                    if linkOK then link = itemLink end
                end
            end
            if type(itemID) == "number" then
                table.insert(items, { itemID = itemID, name = nameFromLink(link) or self:GetItemName(itemID) })
            end
        end
    end
    return items
end

local POOR_QUALITY = 0

-- The item in one bag slot as its ID, stack size, quality, and whether it is
-- locked or has no value, from C_Container where the client has it and the
-- old tuple otherwise.
local function bagSlot(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if not ok or type(info) ~= "table" then return nil end
        return info.itemID, info.stackCount, info.quality, info.isLocked, info.hasNoValue
    end
    if type(rawget(_G, "GetContainerItemInfo")) ~= "function" then return nil end
    local ok, _, count, locked, quality, _, _, _, _, noValue, itemID = pcall(GetContainerItemInfo, bag, slot)
    if not ok then return nil end
    if type(itemID) ~= "number" and GetContainerItemID then
        local idOK, id = pcall(GetContainerItemID, bag, slot)
        if idOK then itemID = id end
    end
    return itemID, count, quality, locked, noValue
end

-- Every grey stack in the backpack and bags that a vendor pays for, as
-- { bag, slot, itemID, count, price }, `price` being the whole stack's in
-- copper. A stack whose sell price the client has not cached yet is left
-- out rather than guessed at, and so is a locked one.
function Client:GetJunkSlots()
    local junk = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
    if not numSlots then return junk end
    local getter = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local ok, slots = pcall(numSlots, bag)
        for slot = 1, ok and tonumber(slots) or 0 do
            local itemID, count, quality, locked, noValue = bagSlot(bag, slot)
            if type(itemID) == "number" and not locked and not noValue then
                local price, infoQuality
                if getter then
                    local infoOK, _, _, q, _, _, _, _, _, _, _, sellPrice = pcall(getter, itemID)
                    if infoOK then price, infoQuality = plainNumber(sellPrice), plainNumber(q) end
                end
                -- The old tuple reports -1 for a quality it does not know.
                if type(quality) ~= "number" or quality < 0 then quality = infoQuality end
                if quality == POOR_QUALITY and price and price > 0 then
                    count = tonumber(count) or 1
                    table.insert(junk, { bag = bag, slot = slot, itemID = itemID, count = count, price = price * count })
                end
            end
        end
    end
    return junk
end

-- The game's own Sell All Junk, what the button on the vendor window does
-- without its confirmation. False when the client has no such call. The
-- confirmation belongs to the button, which asks first and calls this on
-- Yes, so calling it directly never raises it; should this client's
-- build raise it anyway, it is closed, since the sale has already happened.
local SELL_JUNK_POPUP = "SELL_ALL_JUNK_ITEMS"
function Client:SellAllJunk()
    local merchant = rawget(_G, "C_MerchantFrame")
    if type(merchant) ~= "table" or type(merchant.SellAllJunkItems) ~= "function" then return false end
    if not pcall(merchant.SellAllJunkItems) then return false end
    local find, hide = rawget(_G, "StaticPopup_FindVisible"), rawget(_G, "StaticPopup_Hide")
    if type(find) == "function" and type(hide) == "function" then
        local ok, shown = pcall(find, SELL_JUNK_POPUP)
        if ok and shown then pcall(hide, SELL_JUNK_POPUP) end
    end
    return true
end

-- Sells what is in a bag slot to the open vendor, the way a right-click on it
-- does, but only while the slot still holds `itemID`: a stack the player moved
-- since the bags were read is never swapped for whatever took its place.
function Client:SellBagItem(bag, slot, itemID)
    local current = bagSlot(bag, slot)
    if current ~= itemID then return false end
    local use = (C_Container and C_Container.UseContainerItem) or rawget(_G, "UseContainerItem")
    if type(use) ~= "function" then return false end
    return (pcall(use, bag, slot))
end

-- Every line of the tooltip the client shows for a quest link, as
-- { { left = text, right = text }, ... }, the way the player sees it when
-- they click a linked quest in chat. The client fills it from quest data it
-- has cached: for a quest it has not seen, the list is empty and the second
-- value is false, and RequestQuestData asks the server for it. Read through
-- C_TooltipInfo where the client has it, otherwise from a hidden tooltip.
local questTooltip
function Client:GetQuestTooltipLines(questID)
    if type(questID) ~= "number" then return {}, false end
    local have = not HaveQuestData or HaveQuestData(questID) == true
    local link = ("quest:%d"):format(questID)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, entry in ipairs(data.lines) do
                if type(entry) == "table" and (entry.leftText or entry.rightText) then
                    table.insert(lines, { left = entry.leftText, right = entry.rightText })
                end
            end
            return lines, have
        end
    end
    if not CreateFrame then return lines, have end
    if not questTooltip then
        questTooltip = CreateFrame("GameTooltip", "NuuRoadQuestTooltip", UIParent, "GameTooltipTemplate")
        questTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    questTooltip:ClearLines()
    local ok = pcall(questTooltip.SetHyperlink, questTooltip, link)
    if ok then
        for index = 1, (questTooltip.NumLines and questTooltip:NumLines()) or 0 do
            local left = _G["NuuRoadQuestTooltipTextLeft" .. index]
            local right = _G["NuuRoadQuestTooltipTextRight" .. index]
            local leftText = left and left.GetText and left:GetText()
            local rightText = right and right.GetText and right:GetText()
            if leftText or rightText then table.insert(lines, { left = leftText, right = rightText }) end
        end
    end
    questTooltip:Hide()
    return lines, have
end

-- Ask the server for quest or item data the client has not cached. The answer
-- arrives as QUEST_DATA_LOAD_RESULT or GET_ITEM_INFO_RECEIVED. Returns true when
-- a request was sent.
function Client:RequestQuestData(questID)
    if type(questID) ~= "number" or not C_QuestLog or not C_QuestLog.RequestLoadQuestByID then return false end
    return pcall(C_QuestLog.RequestLoadQuestByID, questID) == true
end

function Client:RequestItemData(itemID)
    if type(itemID) ~= "number" or not C_Item or not C_Item.RequestLoadItemDataByID then return false end
    return pcall(C_Item.RequestLoadItemDataByID, itemID) == true
end

local function sameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    a = a:lower():gsub("^the%s+", ""):gsub(",.*$", "")
    b = b:lower():gsub("^the%s+", ""):gsub(",.*$", "")
    return a == b
end

function Client:GetBindLocation()
    if not GetBindLocation then return nil end
    local ok, name = pcall(GetBindLocation)
    return ok and name or nil
end

function Client:IsHearthSetAt(name)
    return sameName(self:GetBindLocation(), name)
end

-- Learned flight paths are recorded per character by ObservedProgress from the
-- taxi map and the "new flight path" message; there is no query API for them.
function Client:FlightPathStore()
    local Progress = ns.modules.Progress
    if not Progress or not Progress.store then return {} end
    Progress.store.flightPaths = Progress.store.flightPaths or {}
    return Progress.store.flightPaths
end

function Client:RecordFlightPath(name)
    if type(name) ~= "string" then return end
    self:FlightPathStore()[name:lower():gsub(",.*$", "")] = true
end

function Client:HasFlightPath(name)
    if type(name) ~= "string" then return false end
    return self:FlightPathStore()[name:lower():gsub("^the%s+", ""):gsub(",.*$", "")] == true
        or self:FlightPathStore()[name:lower():gsub(",.*$", "")] == true
end

-- Calls back with the destination's name when the player takes a flight.
-- A secure post-hook on TakeTaxiNode: it watches the click and changes
-- nothing. False when the client has no such function, and then flights are
-- only known by where they land.
function Client:HookTakeTaxi(callback)
    local hook, take = rawget(_G, "hooksecurefunc"), rawget(_G, "TakeTaxiNode")
    if type(hook) ~= "function" or type(take) ~= "function" then return false end
    return pcall(hook, "TakeTaxiNode", function(index)
        local ok, name = pcall(TaxiNodeName, index)
        if ok and type(name) == "string" and not secret(name) then callback(name) end
    end) == true
end

-- The flight master's own node while the taxi map is open.
function Client:GetCurrentTaxiNodeName()
    if not NumTaxiNodes or not TaxiNodeName or not TaxiNodeGetType then return nil end
    local ok, count = pcall(NumTaxiNodes)
    for index = 1, ok and tonumber(count) or 0 do
        local typeOK, nodeType = pcall(TaxiNodeGetType, index)
        if typeOK and nodeType == "CURRENT" then
            local nameOK, name = pcall(TaxiNodeName, index)
            if nameOK and type(name) == "string" then return name end
        end
    end
    return nil
end

function Client:RecordFlightPathsFromTaxiMap()
    if not NumTaxiNodes or not TaxiNodeName then return end
    local ok, count = pcall(NumTaxiNodes)
    if not ok then return end
    for index = 1, count or 0 do
        local typeOK, nodeType = pcall(TaxiNodeGetType, index)
        if typeOK and (nodeType == "CURRENT" or nodeType == "REACHABLE") then
            local nameOK, name = pcall(TaxiNodeName, index)
            if nameOK then self:RecordFlightPath(name) end
        end
    end
end

-- What the flight master says the player can fly to from here, saved per
-- character as `reachableFlights[origin] = { names }`. It overrides the
-- travel planner's guess that any two known masters connect: a chain through
-- a master the player has not learned is not offered by the client, so it is
-- not offered by the planner either.
function Client:RecordReachableFlights()
    if not NumTaxiNodes or not TaxiNodeName or not TaxiNodeGetType then return nil end
    local ok, count = pcall(NumTaxiNodes)
    if not ok then return nil end
    local origin, names = nil, {}
    for index = 1, tonumber(count) or 0 do
        local typeOK, nodeType = pcall(TaxiNodeGetType, index)
        local nameOK, name = pcall(TaxiNodeName, index)
        if typeOK and nameOK and type(name) == "string" then
            if nodeType == "CURRENT" then origin = name
            elseif nodeType == "REACHABLE" then table.insert(names, name) end
        end
    end
    local Progress = ns.modules.Progress
    local Travel = ns.modules.Travel
    if not origin or not Travel or not Progress or not Progress.store then return origin end
    Progress.store.reachableFlights = Progress.store.reachableFlights or {}
    Progress.store.reachableFlights[Travel.FlightKey(origin)] = names
    return origin
end

function Client:ReachableFlights()
    local Progress = ns.modules.Progress
    return Progress and Progress.store and Progress.store.reachableFlights or {}
end

-- The taxi map's buttons by the node each one stands for, for highlighting a
-- destination. Blizzard's classic frame names them TaxiButton1..N in node
-- order; nothing is clicked.
function Client:GetTaxiButtons()
    local buttons = {}
    if not NumTaxiNodes or not TaxiNodeName then return buttons end
    local ok, count = pcall(NumTaxiNodes)
    for index = 1, ok and tonumber(count) or 0 do
        local nameOK, name = pcall(TaxiNodeName, index)
        local button = rawget(_G, "TaxiButton" .. index)
        if nameOK and type(name) == "string" and type(button) == "table" then
            table.insert(buttons, { name = name, button = button })
        end
    end
    return buttons
end

-- Indoors, for guide places: a player on the hill above a cave is not in it.
-- Nil when the client cannot say.
function Client:IsIndoors()
    local value = self:Read(rawget(_G, "IsIndoors"))
    if value == nil then return nil end
    return value == true or value == 1
end

-- How fast the player is moving under their own power, in yards per second:
-- nought standing still, and nought riding a boat or a zeppelin while the
-- world carries them, which is how the travel planner tells riding from
-- walking off. Nil when the client cannot say.
function Client:GetMoveSpeed()
    local getter = rawget(_G, "GetUnitSpeed")
    if type(getter) ~= "function" then return nil end
    local ok, current = pcall(getter, "player")
    if not ok then return nil end
    return plainNumber(current)
end

-- Falling, for the place recorder: a fall between two points makes their
-- connection one way (a drop off a ledge). Nil when the client cannot say.
function Client:IsFalling()
    local value = self:Read(rawget(_G, "IsFalling"))
    if value == nil then return nil end
    return value == true or value == 1
end

-- The player's height, the third value of `UnitPosition`, or nil. On the
-- 1.60.1 client it is always 0 (docs/api-compatibility.md); the travel
-- probe still logs it once a session, in case a later build fills it in.
function Client:GetPlayerHeight()
    local getter = rawget(_G, "UnitPosition")
    if type(getter) ~= "function" then return nil end
    local ok, _, _, z = pcall(getter, "player")
    if not ok then return nil end
    return plainNumber(z)
end

-- The player's current ground speed in yards per second, or nil.
function Client:GetRunSpeed()
    local getter = rawget(_G, "GetUnitSpeed")
    if type(getter) ~= "function" then return nil end
    local ok, current, run = pcall(getter, "player")
    if not ok then return nil end
    run = plainNumber(run) or plainNumber(current)
    if run and run > 0 then return run end
    return nil
end

function Client:GetPlayerFaction()
    return self:Read(UnitFactionGroup, "player")
end

function Client:GetPlayerClass()
    if not UnitClass then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" and not secret(token) then return token:upper() end
    return nil
end

-- Seconds until a cooldown is over, 0 when ready, nil when unknown.
local function cooldownLeft(getter, id)
    if type(getter) ~= "function" then return nil end
    local ok, start, duration = pcall(getter, id)
    if ok and type(start) == "table" then start, duration = start.startTime, start.duration end
    start, duration = plainNumber(start), plainNumber(duration)
    if not ok or not start or not duration then return nil end
    if start == 0 or duration == 0 then return 0 end
    local now = GetTime and GetTime() or start
    -- The global cooldown is not a wait worth planning around.
    if duration <= 1.5 then return 0 end
    return math.max(0, start + duration - now)
end

-- The player's own spells, and the pet's: a grimoire read to the imp (Blood
-- Pact) is in the pet's spellbook, which IsPlayerSpell never looks at. The
-- pet's is read while the pet is out.
function Client:IsSpellKnown(spellID)
    if type(spellID) ~= "number" then return false end
    if self:Read(rawget(_G, "IsPlayerSpell"), spellID) == true then return true end
    local isSpellKnown = rawget(_G, "IsSpellKnown")
    if self:Read(isSpellKnown, spellID) == true then return true end
    return self:Read(isSpellKnown, spellID, true) == true
end

function Client:GetSpellName(spellID)
    if type(spellID) ~= "number" then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local name = self:Read(C_Spell.GetSpellName, spellID)
        if type(name) == "string" then return name end
    end
    local name = self:Read(rawget(_G, "GetSpellInfo"), spellID)
    return type(name) == "string" and name or nil
end

function Client:GetSpellIcon(spellID)
    if type(spellID) ~= "number" then return nil end
    local getter = (C_Spell and C_Spell.GetSpellTexture) or rawget(_G, "GetSpellTexture")
    return self:Read(getter, spellID)
end

-- A travel teleport row (`Data/Travel.lua`): seconds of cooldown left, 0 when
-- ready, or nil when the player cannot use it at all (no stone in the bags,
-- the spell not learned, no rune for a mage teleport). A cooldown the client
-- will not report counts as ready, since the stone is right there.
function Client:TeleportCooldown(row)
    if type(row) ~= "table" then return nil end
    if row.class and self:GetPlayerClass() and row.class ~= self:GetPlayerClass() then return nil end
    if row.item then
        if self:GetItemCount(row.item) <= 0 then return nil end
        local getter = (C_Container and C_Container.GetItemCooldown) or rawget(_G, "GetItemCooldown")
        return cooldownLeft(getter, row.item) or 0
    end
    if not self:IsSpellKnown(row.spell) then return nil end
    if row.reagent and self:GetItemCount(row.reagent) <= 0 then
        -- GetItemCount answering 0 for a rune the player has would hide the
        -- teleport; only a count the client really gave is believed.
        if (C_Item and C_Item.GetItemCount) or rawget(_G, "GetItemCount") then return nil end
    end
    local getter = (C_Spell and C_Spell.GetSpellCooldown) or rawget(_G, "GetSpellCooldown")
    return cooldownLeft(getter, row.spell) or 0
end

-- Node conditions. Anything the client cannot judge counts as true so a step
-- is never hidden by accident.
local function playerClass()
    if not UnitClass then return nil end
    local _, token = UnitClass("player")
    return token and token:upper()
end

local function playerRace()
    if not UnitRace then return nil end
    local _, token = UnitRace("player")
    return token and token:lower()
end

-- Predicates ---------------------------------------------------------------
--
-- A predicate is data: `{ type = "class", values = { "SHAMAN" } }`. What each
-- type means is a Lua function registered here, so a new kind of condition is
-- one `RegisterPredicate` call and one `only` keyword, and nothing executable
-- ever enters a guide table. Schema validates authored conditions against this
-- same registry, so the two can no longer drift apart.
--
-- Evaluation is three-valued. `true` and `false` are answers; `nil` means the
-- client cannot say, which is not the same as "no" on a beta client where half
-- these APIs may be missing. Callers decide what unknown costs them:
-- Progress treats it as met, so a condition we cannot judge never hides a step.
Client.predicates = {}

function Client:RegisterPredicate(kind, evaluate)
    if type(kind) ~= "string" or kind == "" then error("NuuRoad: a predicate kind is a name") end
    if type(evaluate) ~= "function" then error("NuuRoad: a predicate needs an evaluator") end
    self.predicates[kind] = evaluate
end

function Client:HasPredicate(kind)
    return kind == "all" or kind == "any" or kind == "not" or kind == "now" or self.predicates[kind] ~= nil
end

function Client:PredicateKinds()
    local kinds = {}
    for kind in pairs(self.predicates) do table.insert(kinds, kind) end
    table.sort(kinds)
    return kinds
end

local function matchesValue(values, actual)
    if actual == nil then return nil end
    for _, value in ipairs(values or {}) do
        if tostring(value):lower() == tostring(actual):lower() then return true end
    end
    return false
end

Client:RegisterPredicate("class", function(predicate) return matchesValue(predicate.values, playerClass()) end)
Client:RegisterPredicate("race", function(predicate) return matchesValue(predicate.values, playerRace()) end)
Client:RegisterPredicate("faction", function(predicate)
    return matchesValue(predicate.values, Client:Read(UnitFactionGroup, "player"))
end)

Client:RegisterPredicate("quest", function(predicate)
    local id = tonumber(predicate.id)
    if not id then return nil end
    -- No quest API at all is unknown; an empty log is a real answer.
    local readable = (C_QuestLog and (C_QuestLog.IsOnQuest or C_QuestLog.IsQuestFlaggedCompleted))
        or IsQuestFlaggedCompleted
    if not readable then return nil end
    if predicate.state == "accepted" then return Client:IsQuestInLog(id) end
    if predicate.state == "finished" then return Client:IsQuestComplete(id) end
    if predicate.state == "readyToTurnIn" then return Client:IsQuestReadyToTurnIn(id) end
    return Client:IsQuestInLog(id) or Client:IsQuestComplete(id)
end)

Client:RegisterPredicate("level", function(predicate)
    local level = Client:Read(UnitLevel, "player")
    if type(level) ~= "number" or level <= 0 then return nil end
    if predicate.atLeast and level < tonumber(predicate.atLeast) then return false end
    if predicate.atMost and level > tonumber(predicate.atMost) then return false end
    return true
end)

Client:RegisterPredicate("experience", function(predicate)
    local xp = Client:Read(UnitXP, "player")
    if type(xp) ~= "number" then return nil end
    return xp >= (tonumber(predicate.atLeast) or 0)
end)

-- A skill missing from a skill list the client did hand over is a real no,
-- rank 0: every character lists weapon skills and languages, so an empty or
-- unreadable list is the only unknown. The modern profession call is an
-- answer too, even an empty one; the Forever client lists no skill lines at
-- all, so without it "profession Herbalism" read as unknown - met - for
-- everyone without Herbalism.
local function conditionRank(name)
    local rank = Client:GetSkillRank(name)
    if rank ~= nil then return rank end
    if next(Client:GetSkillRanks()) ~= nil or Client:GetProfessionRanks() ~= nil then return 0 end
    return nil
end

Client:RegisterPredicate("skill", function(predicate)
    if type(predicate.name) ~= "string" then return nil end
    local rank = conditionRank(predicate.name)
    if rank == nil then return nil end
    return rank >= (tonumber(predicate.atLeast) or 1)
end)

-- A profession is a skill the player has any rank in at all.
Client:RegisterPredicate("profession", function(predicate)
    if type(predicate.name) ~= "string" then return nil end
    local rank = conditionRank(predicate.name)
    if rank == nil then return nil end
    return rank >= 1
end)

Client:RegisterPredicate("item", function(predicate)
    local id = tonumber(predicate.id)
    if not id then return nil end
    local count = Client:GetItemCount(id)
    if count == nil then return nil end
    return count >= (tonumber(predicate.count) or 1)
end)

Client:RegisterPredicate("equippedItem", function(predicate)
    local id = tonumber(predicate.id)
    if not id then return nil end
    return Client:IsItemEquipped(id)
end)

Client:RegisterPredicate("gold", function(predicate)
    local money = Client:Read(GetMoney)
    if type(money) ~= "number" then return nil end
    return money >= (tonumber(predicate.atLeast) or 0)
end)

Client:RegisterPredicate("reputation", function(predicate)
    local factionID = tonumber(predicate.factionID)
    if not factionID then return nil end
    local standing = Client:GetFactionStanding(factionID)
    if standing == nil then return nil end
    return standing >= (tonumber(predicate.standing) or 1)
end)

Client:RegisterPredicate("spell", function(predicate)
    local id = tonumber(predicate.id)
    if not id then return nil end
    local known = Client:Read(IsPlayerSpell, id)
    if known == nil then known = Client:Read(IsSpellKnown, id) end
    if known == nil then return nil end
    return known and true or false
end)

Client:RegisterPredicate("zone", function(predicate)
    local mapID = tonumber(predicate.mapID)
    if not mapID then return nil end
    local current = Client:GetCurrentMapID()
    if not current then return nil end
    return current == mapID
end)

Client:RegisterPredicate("instance", function(predicate)
    local inside = Client:Read(IsInInstance)
    if inside == nil then return nil end
    if predicate.inside == false then return not inside end
    return inside and true or false
end)

-- Season of Discovery and the like. Unknown on a client without the API,
-- which is why the Mulgore port could not gate its rune steps before this.
Client:RegisterPredicate("season", function(predicate)
    if type(C_Seasons) ~= "table" or type(C_Seasons.GetActiveSeason) ~= "function" then return nil end
    local active = Client:Read(C_Seasons.GetActiveSeason)
    if type(active) ~= "number" then return nil end
    if predicate.id == nil then return active > 0 end
    return active == tonumber(predicate.id)
end)

Client:RegisterPredicate("hardcore", function(predicate)
    if type(C_GameRules) ~= "table" or type(C_GameRules.IsHardcoreActive) ~= "function" then return nil end
    local active = Client:Read(C_GameRules.IsHardcoreActive)
    if active == nil then return nil end
    active = active and true or false
    if predicate.active == false then return not active end
    return active
end)

-- Where the hearthstone points, for a step that assumes the player can
-- hearth back.
Client:RegisterPredicate("hearth", function(predicate)
    if type(predicate.name) ~= "string" then return nil end
    local bind = Client:GetBindLocation()
    if bind == nil then return nil end
    return tostring(bind):lower() == predicate.name:lower()
end)

Client:RegisterPredicate("subzone", function(predicate)
    if type(predicate.name) ~= "string" then return nil end
    local here = Client:GetSubzone()
    if here == nil then return nil end
    return here:lower() == predicate.name:lower()
end)

-- `{ type = "slot", slot = 16, stat = "dps", below = 4.2 }`: the step is for a
-- player whose gear in that slot is worse than what the step offers.
Client:RegisterPredicate("slot", function(predicate)
    local value
    if predicate.stat == "quality" then value = Client:GetEquippedQuality(predicate.slot)
    elseif predicate.stat == "dps" then value = Client:GetEquippedDPS(predicate.slot)
    else return nil end
    -- Nothing worn at all is worse than anything, which is the case these
    -- steps are really written for.
    if value == nil then
        local link = Client:Read(GetInventoryItemLink, "player", tonumber(predicate.slot))
        if link == nil then return true end
        return nil
    end
    if predicate.below then return value < tonumber(predicate.below) end
    if predicate.atLeast then return value >= tonumber(predicate.atLeast) end
    return nil
end)

Client:RegisterPredicate("aura", function(predicate)
    local id = tonumber(predicate.id)
    if not id then return nil end
    if type(C_UnitAuras) ~= "table" or type(C_UnitAuras.GetPlayerAuraBySpellID) ~= "function" then return nil end
    local aura = Client:Read(C_UnitAuras.GetPlayerAuraBySpellID, id)
    return aura ~= nil
end)

Client:RegisterPredicate("cooldown", function(predicate)
    local id = tonumber(predicate.id)
    if not id then return nil end
    local start, duration
    if predicate.kind == "item" then start, duration = Client:Read(GetItemCooldown, id)
    else start, duration = Client:Read(GetSpellCooldown, id) end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    local ready = start == 0 or duration == 0
    if predicate.ready == false then return not ready end
    return ready
end)

-- Three things nothing observable can answer: how fast the realm gives
-- experience, whether the player will use the auction house, and whether they
-- are playing self found. The player says so once in Options, and the guide
-- reads the answer. Unknown until they have, so nothing is hidden by a
-- question that was never asked.
local function playerSetting(key)
    return ns.modules.Config:Get("realm." .. key)
end

Client:RegisterPredicate("xprate", function(predicate)
    local rate = tonumber(playerSetting("xpRate"))
    if not rate then return nil end
    if predicate.below then return rate < tonumber(predicate.below) end
    if predicate.atLeast then return rate >= tonumber(predicate.atLeast) end
    return nil
end)

Client:RegisterPredicate("auctionHouse", function(predicate)
    local value = playerSetting("auctionHouse")
    if value == nil then return nil end
    if predicate.uses == false then return not value end
    return value and true or false
end)

Client:RegisterPredicate("selfFound", function(predicate)
    local value = playerSetting("selfFound")
    if value == nil then return nil end
    if predicate.active == false then return not value end
    return value and true or false
end)

-- The Lua fallback ---------------------------------------------------------
--
-- `{ type = "lua", body = "level() >= 10 and skill('Mining')" }` is the escape
-- hatch for a condition no registered kind covers. It is still data: a string,
-- which serializes into SavedVariables and renders in the editor, where a
-- function would do neither.
--
-- What keeps it from being arbitrary code:
--   * it is compiled as `return (<body>)`, so a statement -- any loop, any
--     assignment, any function definition -- is a syntax error, and an
--     expression cannot spin the client;
--   * it runs under a sandbox environment with no `_G`, so a name the sandbox
--     does not define is nil rather than the real global;
--   * the client is reachable only through the helpers below and `api(name)`,
--     which resolves against an allowlist of read-only calls, so nothing a
--     guide writes can send, sell, delete, target, or move anything;
--   * errors are unknown, not false, exactly like a missing API.
-- It is a fallback, not the first choice: a predicate used twice belongs in
-- `RegisterPredicate`, where the editor and the audit can see it by name.
local luaSourceLimit = 400

-- Rejected at load with a message rather than silently resolving to nil, so a
-- guide that tries to break out says so instead of quietly never matching.
local forbiddenNames = {
    "_G", "_ENV", "getfenv", "setfenv", "loadstring", "load", "loadfile", "dofile", "require",
    "rawget", "rawset", "rawequal", "rawlen", "newproxy", "collectgarbage", "coroutine",
    "debug", "os", "io", "package", "getmetatable", "setmetatable", "pcall", "xpcall",
    "SlashCmdList", "RunScript", "CreateFrame", "hooksecurefunc", "securecall",
}

function Client:InspectLuaPredicate(body)
    if type(body) ~= "string" or body == "" then return nil, "is empty" end
    if #body > luaSourceLimit then return nil, "is longer than " .. luaSourceLimit .. " characters" end
    if body:find("[^\32-\126]") then return nil, "must be ASCII" end
    for _, name in ipairs(forbiddenNames) do
        if body:find("%f[%w_]" .. name .. "%f[^%w_]") then return nil, "may not name '" .. name .. "'" end
    end
    local chunk = "return (" .. body .. ")"
    local compiled, err
    if type(loadstring) == "function" then
        compiled, err = loadstring(chunk, "nuuroad-condition")
    elseif type(load) == "function" then
        compiled, err = load(chunk, "nuuroad-condition")
    else
        return nil, "cannot be compiled on this client"
    end
    if not compiled then
        return nil, "is not a single expression (" .. tostring(err) .. ")"
    end
    return compiled
end

-- Exact names only, resolved through Client:Read so a secret value or a
-- missing API comes back as nil instead of raising. Adding a call here is the
-- supported way to widen the fallback's reach.
local readableAPIs = {
    "UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitName", "UnitSex",
    "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitXP", "UnitXPMax",
    "UnitAffectingCombat", "UnitIsDeadOrGhost", "UnitBuff", "UnitDebuff", "UnitAura",
    "GetMoney", "GetTime", "GetXPExhaustion", "IsResting", "IsMounted", "IsStealthed",
    "IsIndoors", "IsInInstance", "IsSpellKnown", "IsPlayerSpell", "IsUsableSpell",
    "GetSpellInfo", "GetSpellCooldown", "GetItemCooldown", "GetItemCount",
    "GetInventoryItemID", "GetRealZoneText", "GetSubZoneText", "GetMinimapZoneText",
    "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
    "IsQuestFlaggedCompleted", "GetQuestsCompleted", "GetInstanceInfo", "GetAverageItemLevel",
    "C_QuestLog.IsOnQuest", "C_QuestLog.IsComplete", "C_QuestLog.IsQuestFlaggedCompleted",
    "C_Map.GetBestMapForUnit", "C_Seasons.GetActiveSeason", "C_Seasons.HasActiveSeason",
    "C_GameRules.IsHardcoreActive", "C_Container.GetContainerItemInfo",
}
local readable = {}
for _, name in ipairs(readableAPIs) do readable[name] = true end

local function resolveAPI(name)
    if not readable[name] then return nil end
    local namespace, member = name:match("^([%w_]+)%.([%w_]+)$")
    if namespace then
        local container = rawget(_G, namespace)
        if type(container) ~= "table" then return nil end
        return container[member]
    end
    local func = rawget(_G, name)
    if type(func) == "function" then return func end
    return nil
end

local sandbox
local function buildSandbox()
    local env = {
        -- Plain Lua, minus everything that can build a string big enough or
        -- reach back out of the environment.
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        ipairs = ipairs, pairs = pairs, unpack = unpack, next = next,
        math = { abs = math.abs, ceil = math.ceil, floor = math.floor, max = math.max,
                 min = math.min, huge = math.huge, fmod = math.fmod },
        string = { lower = string.lower, upper = string.upper, sub = string.sub,
                   find = string.find, match = string.match, len = string.len, byte = string.byte },

        level = function() return Client:Read(UnitLevel, "player") end,
        class = function() return playerClass() end,
        race = function() return playerRace() end,
        faction = function() return Client:Read(UnitFactionGroup, "player") end,
        questInLog = function(id) return Client:IsQuestInLog(tonumber(id) or 0) end,
        questFinished = function(id) return Client:IsQuestComplete(tonumber(id) or 0) end,
        questReady = function(id) return Client:IsQuestReadyToTurnIn(tonumber(id) or 0) end,
        itemCount = function(id) return Client:GetItemCount(tonumber(id) or 0) end,
        equipped = function(id) return Client:IsItemEquipped(tonumber(id) or 0) end,
        skill = function(name) return Client:GetSkillRank(name) end,
        standing = function(id) return Client:GetFactionStanding(tonumber(id) or 0) end,
        money = function() return Client:Read(GetMoney) end,
        zone = function() return Client:GetCurrentMapID() end,
        season = function()
            if type(C_Seasons) ~= "table" or type(C_Seasons.GetActiveSeason) ~= "function" then return nil end
            return Client:Read(C_Seasons.GetActiveSeason)
        end,
        api = function(name, ...)
            local func = resolveAPI(name)
            if not func then return nil end
            return Client:Read(func, ...)
        end,
    }
    env._G = nil
    return env
end

-- Compiled bodies are cached beside the guide, never on it: a predicate table
-- is guide data and has to stay free of functions to serialize and validate.
local compiledBodies = setmetatable({}, { __mode = "k" })

function Client:EvaluateLua(predicate)
    local cached = compiledBodies[predicate]
    if cached == nil then
        local compiled, problem = self:InspectLuaPredicate(predicate.body)
        cached = { func = compiled, problem = problem }
        compiledBodies[predicate] = cached
    end
    if not cached.func then return nil end
    sandbox = sandbox or buildSandbox()
    if type(setfenv) == "function" then setfenv(cached.func, sandbox) end
    local ok, result = pcall(cached.func)
    if not ok then return nil end
    if result == nil then return nil end
    if result == false then return false end
    return true
end

Client:RegisterPredicate("lua", function(predicate) return Client:EvaluateLua(predicate) end)

-- Kleene logic: `all` is false as soon as one child is, true only when every
-- child is, and unknown in between. `any` is its mirror. `kinds`, when given,
-- is the set of leaf kinds to read; any other leaf counts as unknown.
function Client:EvaluateCondition(predicate, kinds)
    if type(predicate) ~= "table" then return true end
    local kind = predicate.type
    -- `now` only changes whether the step is waited on (see `couldHold`); read
    -- plainly, it is the term it wraps.
    if kind == "now" then return self:EvaluateCondition(predicate.child, kinds) end
    if kind == "not" then
        local child = self:EvaluateCondition(predicate.child, kinds)
        if child == nil then return nil end
        return not child
    end
    if kind == "all" or kind == "any" then
        local unknown = false
        for _, child in ipairs(predicate.children or {}) do
            local result = self:EvaluateCondition(child, kinds)
            if result == nil then
                unknown = true
            elseif kind == "all" and not result then
                return false
            elseif kind == "any" and result then
                return true
            end
        end
        if unknown then return nil end
        return kind == "all"
    end
    if kinds and not kinds[kind] then return nil end
    local evaluate = self.predicates[kind]
    if not evaluate then return nil end
    local ok, result = pcall(evaluate, predicate)
    if not ok then return nil end
    if result == nil then return nil end
    return result and true or false
end

-- What a step asks: a condition the client cannot judge never hides a step.
function Client:MatchesCondition(predicate)
    return self:EvaluateCondition(predicate) ~= false
end

-- The terms a character cannot change by playing: who they are and the realm
-- they are on. Everything else (quests, level, items, skills) can still come.
local fixedKinds = { class = true, race = true, faction = true, season = true, hardcore = true }

-- A condition that fails on those terms alone, whatever the rest turn out to
-- be: the step is never for this character.
function Client:RulesOut(predicate)
    return self:EvaluateCondition(predicate, fixedKinds) == false
end

-- What the player gains by playing: a quest taken or finished, a level, gold,
-- an item, a spell, a skill, standing, a place, a buff, a cooldown come back.
-- A term asking for one of these may not hold yet and still come to.
local gainableKinds = {
    quest = true, level = true, experience = true, gold = true, item = true, equippedItem = true,
    spell = true, skill = true, profession = true, reputation = true, zone = true, subzone = true,
    instance = true, hearth = true, aura = true, cooldown = true,
}

-- Whether a condition could still hold: every gainable term the condition
-- asks for is taken as gained, and the rest are read as they are now. A term
-- under `not` is read as it is, so "not quest 858" with the quest already
-- taken can never hold again, while "quest 858 readyToTurnIn" can. The
-- fixed terms, `slot` and `xprate` comparisons, the realm settings, a `now`
-- term, and a `when` expression are always read as they are. Unknown is not
-- a no.
local function couldHold(client, predicate, negated)
    if type(predicate) ~= "table" then return true end
    local kind = predicate.type
    -- A `now` term is read as it stands: if it does not hold as the guide
    -- reaches the step, the step is passed over rather than waited on.
    if kind == "now" then return client:EvaluateCondition(predicate.child) end
    if kind == "not" then
        local child = couldHold(client, predicate.child, not negated)
        if child == nil then return nil end
        return not child
    end
    if kind == "all" or kind == "any" then
        local unknown = false
        for _, child in ipairs(predicate.children or {}) do
            local result = couldHold(client, child, negated)
            if result == nil then
                unknown = true
            elseif kind == "all" and not result then
                return false
            elseif kind == "any" and result then
                return true
            end
        end
        if unknown then return nil end
        return kind == "all"
    end
    if gainableKinds[kind] and not negated then return true end
    return client:EvaluateCondition(predicate)
end

function Client:CouldOpen(predicate)
    return couldHold(self, predicate, false) ~= false
end

-- Arrival is whatever the arrow says it is: the same yards, the nearest of
-- the step's points, the step's own yard radius, and a neighbouring map
-- measured through world coordinates, so the step never completes while the
-- arrow still points hundreds of yards on. Nothing is arrived at from a
-- flight, which passes over places the player has not been. Without the
-- navigation module the map-fraction radius is the fallback.
function Client:IsAtLocation(location)
    if not location then return false end
    if self:IsOnTaxi() then return false end
    local Navigation = ns.modules.Navigation
    if Navigation and Navigation.Measure then
        local _, _, _, arrived = Navigation:Measure(location)
        return arrived == true
    end
    local mapID = self:GetCurrentMapID()
    if not mapID or mapID ~= self:ResolveMapID(location.mapID) then return false end
    local x, y = self:GetPlayerMapPosition(mapID)
    if not x or not y then return false end
    local radius = tonumber(location.arrivalRadiusNormalized) or 0.015
    local dx, dy = x - location.x, y - location.y
    return dx * dx + dy * dy <= radius * radius
end

-- `stepIndex` identifies the step for observations kept per step, such as kills
-- counted from the combat log.
function Client:MatchesObservedCompletion(observed, location, stepIndex)
    if type(observed) ~= "table" then return false end
    if observed.type == "always" then return true end
    if observed.type == "location" then return self:IsAtLocation(location) end
    -- Arrival by name rather than by coordinate.
    if observed.type == "zone" then
        local here = self:GetZoneName()
        return here ~= nil and type(observed.name) == "string" and here:lower() == observed.name:lower()
    end
    if observed.type == "subzone" then
        local here = self:GetSubzone()
        return here ~= nil and type(observed.name) == "string" and here:lower() == observed.name:lower()
    end
    -- A companion step: done because the step it was carried alongside is.
    if observed.type == "step" then
        local Progress = ns.modules.Progress
        local guide = Progress and Progress.GetActiveGuide and Progress:GetActiveGuide()
        if not guide or not observed.index then return false end
        local state = Progress.PeekState and Progress:PeekState(guide)
        local status = state and state.status and state.status[observed.index]
        return Progress:IsDone(status)
    end
    if observed.type == "kills" then
        local Progress = ns.modules.Progress
        local guide = Progress and Progress.GetActiveGuide and Progress:GetActiveGuide()
        if not guide or not stepIndex then return false end
        return Progress:KillCount(guide, stepIndex) >= (tonumber(observed.count) or 1)
    end
    if observed.type == "level" then
        -- Counting the turn-ins ahead of the step, when it names where the
        -- level is needed by.
        local Experience = ns.modules.Experience
        if observed.by and Experience then
            local reached = Experience:Reached(observed, stepIndex)
            if reached ~= nil then return reached end
        end
        local level = UnitLevel and UnitLevel("player") or 0
        local atLeast = tonumber(observed.atLeast) or math.huge
        if level > atLeast then return true end
        if level < atLeast then return false end
        return not observed.xp or (UnitXP and UnitXP("player") or 0) >= observed.xp
    end
    if observed.type == "objective" then return self:IsQuestObjectiveComplete(observed.questID, observed.index) end
    if observed.type == "item" then
        if self:GetItemCount(observed.itemID) >= (observed.count or 1) then return true end
        -- An item that begins a quest is gone once used, so the quest stands in
        -- for it; a quest item is accounted for once its quest is done.
        if observed.startsQuestID and (self:IsQuestInLog(observed.startsQuestID) or self:IsQuestComplete(observed.startsQuestID)) then return true end
        if observed.questID and (self:IsQuestComplete(observed.questID) or self:IsQuestReadyToTurnIn(observed.questID)) then return true end
        return false
    end
    if observed.type == "skill" then return self:HasSkillRank(observed.name, observed.atLeast) end
    if observed.type == "spell" then
        if type(observed.ids) ~= "table" or #observed.ids == 0 then return false end
        for _, id in ipairs(observed.ids) do
            if not self:IsSpellKnown(id) then return false end
        end
        return true
    end
    if observed.type == "cast" then
        local Progress = ns.modules.Progress
        local guide = Progress and Progress.GetActiveGuide and Progress:GetActiveGuide()
        if not guide or not stepIndex then return false end
        return Progress:CastCount(guide, stepIndex) >= (tonumber(observed.count) or 1)
    end
    if observed.type == "equipped" then return self:IsItemEquipped(observed.itemID) end
    if observed.type == "reputation" then
        local standing = self:GetFactionStanding(observed.factionID)
        return standing ~= nil and standing >= (tonumber(observed.standing) or 8)
    end
    if observed.type == "crafted" then
        -- Either the player made that many this session, or the output is
        -- still in their bags: a stack of 30 bracers proves the crafting.
        if self:GetItemCount(observed.itemID) >= (observed.count or 1) then return true end
        local Progress = ns.modules.Progress
        local guide = Progress and Progress.GetActiveGuide and Progress:GetActiveGuide()
        if not guide or not stepIndex then return false end
        return Progress:CraftCount(guide, stepIndex) >= (tonumber(observed.count) or 1)
    end
    if observed.type == "hearth" then return self:IsHearthSetAt(observed.name) end
    if observed.type == "flightpath" then return self:HasFlightPath(observed.name) end
    if observed.type == "all" then
        for _, child in ipairs(observed.children or {}) do
            if not self:MatchesObservedCompletion(child, location, stepIndex) then return false end
        end
        return true
    end
    -- Whichever comes first: a materials step that a profession rank has made
    -- moot is done, however little of it was gathered.
    if observed.type == "any" then
        for _, child in ipairs(observed.children or {}) do
            if self:MatchesObservedCompletion(child, location, stepIndex) then return true end
        end
        return false
    end
    if observed.type ~= "quests" or type(observed.ids) ~= "table" or #observed.ids == 0 then return false end
    local matchAll = observed.match ~= "any"
    for _, questID in ipairs(observed.ids) do
        local matches
        if observed.state == "accepted" then
            matches = self:IsQuestInLog(questID)
        elseif observed.state == "readyToTurnIn" then
            -- A quest handed in out of order never reports "ready" again, so the
            -- completed flag stands in for it.
            matches = self:IsQuestReadyToTurnIn(questID) or self:IsQuestComplete(questID)
        elseif observed.state == "finished" then
            matches = self:IsQuestComplete(questID)
        elseif observed.state == "acceptedOrFinished" then
            matches = self:IsQuestInLog(questID) or self:IsQuestComplete(questID)
        else
            return false
        end
        if matchAll and not matches then return false end
        if not matchAll and matches then return true end
    end
    return matchAll
end

-- The words a quest dialog is showing while it is open: the title, the story,
-- and the objective line the quest gives itself. Nothing in the addon acts on
-- any of it. It is authoring material - the quest as the player read it - kept
-- beside the accept and turn-in rows `Domain/Recording.lua` writes, so a guide
-- can be written afterwards from what was actually said.
-- The description and objective text of a quest already in the log. The
-- classic call answers for whichever quest the log has selected, so the quest
-- is selected quietly (no UI refresh), read, and the selection put back: the
-- quest log window, and the module that keeps it on the step's quest, never
-- see it move. Either string may be secret, and then it is simply missing.
function Client:GetQuestLogText(questID)
    local index = self:GetQuestLogIndex(questID)
    if not index then return nil, nil end
    local function select(target, targetIndex)
        if C_QuestLog and C_QuestLog.SetSelectedQuest and target and pcall(C_QuestLog.SetSelectedQuest, target) then return true end
        if SelectQuestLogEntry and targetIndex and pcall(SelectQuestLogEntry, targetIndex) then return true end
        return false
    end
    local previous = self:GetSelectedQuestLogQuest()
    if previous ~= questID and not select(questID, index) then return nil, nil end
    local text, objectiveText
    if GetQuestLogQuestText then
        local ok, description, objectives = pcall(GetQuestLogQuestText)
        if ok then
            text = self:Read(function() return description end)
            objectiveText = self:Read(function() return objectives end)
        end
    end
    if previous ~= questID then select(previous, previous and self:GetQuestLogIndex(previous)) end
    if type(text) ~= "string" or text == "" then text = nil end
    if type(objectiveText) ~= "string" or objectiveText == "" then objectiveText = nil end
    return text, objectiveText
end

function Client:GetQuestOfferText()
    local function text(name)
        local value = self:Read(rawget(_G, name))
        if type(value) ~= "string" or value == "" then return nil end
        return value
    end
    return text("GetTitleText"), text("GetQuestText"), text("GetObjectiveText")
end

-- What the finished quest says over its rewards, and what it says while it is
-- still being handed in. Both are nil wherever the client will not answer.
function Client:GetQuestRewardText()
    local value = self:Read(rawget(_G, "GetRewardText"))
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

function Client:GetQuestProgressText()
    local value = self:Read(rawget(_G, "GetProgressText"))
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

-- The item a reward slot offers, by index into the quest's choices.
function Client:GetQuestRewardChoice(index)
    local link = self:Read(rawget(_G, "GetQuestItemLink"), "choice", index)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("|Hitem:(%d+)")), link:match("|h%[(.-)%]|h")
end

-- Which reward the player took. The client has no event for it, and the value
-- is gone by the time QUEST_TURNED_IN fires, so the UI's own call is watched:
-- `GetQuestReward(choice)` is what every reward button runs, ours included.
-- The hook only listens; it never calls anything.
function Client:OnQuestRewardChosen(callback)
    if type(hooksecurefunc) ~= "function" or type(rawget(_G, "GetQuestReward")) ~= "function" then return false end
    return pcall(hooksecurefunc, "GetQuestReward", function(choice)
        local index = plainNumber(choice)
        pcall(callback, index)
    end) == true
end

-- What is in the open loot window, slot by slot: the item, how many, whether
-- the game itself calls it a quest item, and which creature or object it came
-- off. `GetLootSourceInfo` answers GUID/quantity pairs and is missing on older
-- clients, so the source is left out rather than guessed.
function Client:GetLootSlots()
    local slots = {}
    if type(rawget(_G, "GetNumLootItems")) ~= "function" or type(rawget(_G, "GetLootSlotInfo")) ~= "function" then return slots end
    local count = plainNumber(self:Read(GetNumLootItems))
    for index = 1, count or 0 do
        local ok, _, name, quantity, _, _, _, isQuestItem = pcall(GetLootSlotInfo, index)
        if ok then
            local slot = { index = index, count = plainNumber(quantity) or 1 }
            if type(name) == "string" and not secret(name) then slot.name = name end
            slot.questItem = not secret(isQuestItem) and isQuestItem == true or false
            local link = self:Read(rawget(_G, "GetLootSlotLink"), index)
            if type(link) == "string" then
                slot.itemID = tonumber(link:match("|Hitem:(%d+)"))
                slot.name = slot.name or link:match("|h%[(.-)%]|h")
            end
            local guid = self:Read(rawget(_G, "GetLootSourceInfo"), index)
            if type(guid) == "string" then
                local kind, id = self:GUIDInfo(guid)
                slot.fromKind, slot.from = kind, id
            end
            table.insert(slots, slot)
        end
    end
    return slots
end

-- The kind and the ID out of any GUID the client hands back. A loot source is
-- usually a creature, but a herb, a chest or a quest object is a GameObject,
-- and a guide step is written differently for each, so the kind is kept.
function Client:GUIDInfo(guid)
    if type(guid) ~= "string" then return nil end
    local kind = guid:match("^(%a+)%-")
    if not kind then return nil end
    local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return kind, tonumber(id)
end

function Client:GetMoney()
    return plainNumber(self:Read(rawget(_G, "GetMoney")))
end

-- Every skill the skill window lists, and every profession, as { [name] =
-- rank }. Read whole so a
-- trainer visit can be told by what changed across it rather than by asking
-- about a skill the player might not have yet.
function Client:GetSkillRanks()
    local ranks = {}
    local count = type(rawget(_G, "GetSkillLineInfo")) == "function" and plainNumber(self:Read(rawget(_G, "GetNumSkillLines")))
    for index = 1, count or 0 do
        local ok, name, isHeader, _, rank = pcall(GetSkillLineInfo, index)
        if ok and not isHeader and type(name) == "string" and not secret(name) and not secret(rank) then
            ranks[name] = tonumber(rank) or 0
        end
    end
    for name, entry in pairs(self:GetProfessionRanks() or {}) do
        if ranks[name] == nil then ranks[name] = entry.rank end
    end
    return ranks
end

-- The spell an item casts, which is the only thread back from a cast the
-- client reports to the item the player actually clicked.
function Client:GetItemSpellID(itemID)
    if type(itemID) ~= "number" then return nil end
    local getter = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
    if type(getter) ~= "function" then return nil end
    local ok, name, spellID = pcall(getter, itemID)
    if not ok or secret(spellID) then return nil end
    local id = tonumber(spellID)
    if not id then return nil end
    return id, (type(name) == "string" and not secret(name)) and name or nil
end

function Client:GetBagItemForSpell(spellID)
    if type(spellID) ~= "number" then return nil end
    for _, item in ipairs(self:GetBagItems()) do
        local id = self:GetItemSpellID(item.itemID)
        if id == spellID then return item.itemID, item.name end
    end
    return nil
end

function Client:GetEquippedItemID(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    return plainNumber(self:Read(rawget(_G, "GetInventoryItemID"), "player", slot))
end

-- Professions ----------------------------------------------------------------
--
-- What a guide's `craft` and `skillup` steps need from the profession window:
-- their Make button reads the open window (a snapshot of its recipes, for the
-- recipe a step names) and asks it to make a batch. The profession planner's
-- own reads (known recipes kept per character, trainers, merchants,
-- Auctionator prices) went with it to NuuProfessions; nothing here saves
-- anything, and a read is only a read: nothing is expanded or filtered, so a
-- recipe the window hides is simply not seen.
--
-- These reads are the same code as NuuProfessions' API/Client.lua (its
-- "Profession window" and "Making from the planner" parts), duplicated until
-- they move to the kit; a fix to one belongs in the other.
--
-- Three shapes of profession window are read, whichever this client has:
--   * the Classic trade skill tuples (`GetTradeSkillInfo` and friends), which
--     give no recipe spell ID: a recipe is known by its product item;
--   * the Classic Craft API (`GetCraftInfo`), which Enchanting uses there; its
--     "product" link is an `enchant:<spellID>` link, which is the spell;
--   * `C_TradeSkillUI` on a modern client, which answers by recipe spell ID.
-- The Classic calls are tried first: a Classic-shaped client can carry a
-- `C_TradeSkillUI` table with only a few functions in it.
--
-- Other modules hear the window open, shut and change through
-- `Client:OnProfessionChange`. Everything worth reading later goes to the
-- `prof` channel of the session log (`ns:RecordHere`).

local unpackValues = unpack or table.unpack

local function pack(...) return { n = select("#", ...), ... } end

local function plainString(value)
    if type(value) ~= "string" or secret(value) or value == "" then return nil end
    return value
end

-- Every value a call returns, each secret one turned to nil, or nothing at
-- all when the call is missing or fails. The tuple readers need all of them.
local function readAll(func, ...)
    if type(func) ~= "function" then return nil end
    local results = pack(pcall(func, ...))
    if not results[1] then return nil end
    for index = 2, results.n do
        if secret(results[index]) then results[index] = nil end
    end
    return unpackValues(results, 2, results.n)
end

local function global(name) return rawget(_G, name) end

local function epoch()
    local clock = global("time") or (os and os.time)
    if type(clock) ~= "function" then return nil end
    local ok, value = pcall(clock)
    return ok and type(value) == "number" and value or nil
end

-- A hyperlink's kind, ID and shown name: "|Hitem:2304:...|h[Light Armor
-- Kit]|h" is ("item", 2304, "Light Armor Kit"), an Enchanting craft's is
-- ("enchant", <spellID>, ...).
function Client.ParseLink(link)
    link = plainString(link)
    if not link then return nil end
    local kind, id = link:match("|H(%a+):(%d+)")
    return kind, tonumber(id), link:match("|h%[(.-)%]|h")
end
local parseLink = Client.ParseLink

-- The window's words for a recipe's difficulty, and the colour the player
-- sees. `relativeDifficulty` is the modern client's number for the same four.
local DIFFICULTY_COLOR = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey", difficult = "red" }
local RELATIVE_DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
Client.difficultyColors = DIFFICULTY_COLOR

local function colorOf(word)
    if type(word) ~= "string" then return nil end
    word = word:lower()
    if word == "gray" then return "grey" end
    return DIFFICULTY_COLOR[word] or word
end

-- A recipe's identity in a snapshot: its spell where the client gave one,
-- else its product item, else (a craft with neither) its name.
function Client.RecipeKey(recipe)
    if type(recipe) ~= "table" then return nil end
    if recipe.spellID then return recipe.spellID end
    if recipe.itemID then return "item:" .. recipe.itemID end
    if recipe.name then return "name:" .. recipe.name:lower() end
    return nil
end

-- Listeners -------------------------------------------------------------------

Client.professionListeners = {}

-- `callback(kind, subject, data)` runs whenever the window changed:
-- ("tradeskill", professionName, snapshot) when a read found something new,
-- and ("window", "tradeskill"|"craft"|"closed") when the window opens or
-- shuts (or first reads as before). The tracker's Make button follows both.
-- Errors in a listener are swallowed.
function Client:OnProfessionChange(callback)
    if type(callback) ~= "function" then return end
    table.insert(self.professionListeners, callback)
end

function Client:ProfessionChanged(kind, subject, data)
    for _, callback in ipairs(self.professionListeners) do pcall(callback, kind, subject, data) end
end

local function logProf(event, data)
    data = data or {}
    data.event = event
    if ns.RecordHere then ns:RecordHere("prof", data) end
end

-- Profession window ---------------------------------------------------------------

-- The Classic tuple APIs, as one shape. `info` normalises the row to
-- (name, type, numAvailable, isExpanded, numSkillUps).
local CLASSIC_WINDOWS = {
    tradeskill = {
        line = "GetTradeSkillLine", count = "GetNumTradeSkills",
        info = function(index)
            local name, kind, available, expanded, _, skillUps = readAll(global("GetTradeSkillInfo"), index)
            return name, kind, available, expanded, skillUps
        end,
        itemLink = "GetTradeSkillItemLink", recipeLink = "GetTradeSkillRecipeLink",
        numMade = "GetTradeSkillNumMade", numReagents = "GetTradeSkillNumReagents",
        reagentInfo = "GetTradeSkillReagentInfo", reagentLink = "GetTradeSkillReagentItemLink",
        linked = "IsTradeSkillLinked",
    },
    craft = {
        line = "GetCraftDisplaySkillLine", count = "GetNumCrafts",
        info = function(index)
            local name, _, kind, available, expanded = readAll(global("GetCraftInfo"), index)
            return name, kind, available, expanded, nil
        end,
        itemLink = "GetCraftItemLink", recipeLink = "GetCraftRecipeLink",
        numMade = "GetCraftNumMade", numReagents = "GetCraftNumReagents",
        reagentInfo = "GetCraftReagentInfo", reagentLink = "GetCraftReagentItemLink",
    },
}

-- An item link names the product; an enchant or spell link names the recipe.
local function takeLink(recipe, link)
    local kind, id, name = parseLink(link)
    if not id then return end
    if kind == "item" then
        recipe.itemID = recipe.itemID or id
    elseif kind == "enchant" or kind == "spell" then
        recipe.spellID = recipe.spellID or id
    end
    recipe.name = recipe.name or name
end

local function readClassicWindow(which)
    local api = CLASSIC_WINDOWS[which]
    if not api or type(global(api.count)) ~= "function" then return nil end
    local profession, skill, maxSkill = readAll(global(api.line))
    profession = plainString(profession)
    -- "UNKNOWN" is what the trade skill line says while no window is open.
    if not profession or profession == "UNKNOWN" then return nil end
    local snapshot = { profession = profession, skill = plainNumber(skill), maxSkill = plainNumber(maxSkill),
        api = which, recipes = {}, order = {} }
    if api.linked and readAll(global(api.linked)) == true then snapshot.linked = true end
    local count = plainNumber(readAll(global(api.count))) or 0
    for index = 1, count do
        local name, kind, available, expanded, skillUps = api.info(index)
        if kind == "header" or kind == "subheader" then
            if expanded == false then snapshot.partial = true end
        elseif plainString(name) then
            local recipe = { name = name, difficulty = plainString(kind), available = plainNumber(available),
                skillUps = plainNumber(skillUps), known = true, reagents = {} }
            recipe.color = colorOf(recipe.difficulty)
            takeLink(recipe, readAll(global(api.recipeLink), index))
            takeLink(recipe, readAll(global(api.itemLink), index))
            local low, high = readAll(global(api.numMade), index)
            if plainNumber(low) then recipe.made = { low, plainNumber(high) or low } end
            local reagents = plainNumber(readAll(global(api.numReagents), index)) or 0
            for slot = 1, reagents do
                local reagentName, _, needed = readAll(global(api.reagentInfo), index, slot)
                local _, itemID = parseLink(readAll(global(api.reagentLink), index, slot))
                table.insert(recipe.reagents, { itemID = itemID, count = plainNumber(needed) or 1, name = plainString(reagentName) })
            end
            table.insert(snapshot.order, recipe)
        end
    end
    return snapshot
end

-- The modern client's profession name and skill: the base profession names
-- it, the child (the expansion's own line) may carry the skill.
local function modernLine(ui)
    local base = type(ui.GetBaseProfessionInfo) == "function" and Client:Read(ui.GetBaseProfessionInfo) or nil
    if type(base) == "table" and plainString(base.professionName) then
        local skill, maxSkill = plainNumber(base.skillLevel), plainNumber(base.maxSkillLevel)
        local child = type(ui.GetChildProfessionInfo) == "function" and Client:Read(ui.GetChildProfessionInfo) or nil
        if type(child) == "table" and (plainNumber(child.skillLevel) or 0) > (skill or 0) then
            skill, maxSkill = plainNumber(child.skillLevel), plainNumber(child.maxSkillLevel)
        end
        return base.professionName, skill, maxSkill
    end
    if type(ui.GetTradeSkillLine) == "function" then
        local _, name, skill, maxSkill = readAll(ui.GetTradeSkillLine)
        return plainString(name), plainNumber(skill), plainNumber(maxSkill)
    end
    return nil
end

local function modernReagents(ui, recipeID, recipe)
    local schematic = type(ui.GetRecipeSchematic) == "function" and Client:Read(ui.GetRecipeSchematic, recipeID, false) or nil
    if type(schematic) == "table" then
        local low, high = plainNumber(schematic.quantityMin), plainNumber(schematic.quantityMax)
        if low then recipe.made = { low, high or low } end
        recipe.itemID = recipe.itemID or plainNumber(schematic.outputItemID)
        for _, slot in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
            local first = type(slot.reagents) == "table" and slot.reagents[1] or nil
            -- Optional and finishing reagents are the player's choice, not the recipe's cost.
            if slot.required ~= false and type(first) == "table" and plainNumber(first.itemID) then
                table.insert(recipe.reagents, { itemID = first.itemID, count = plainNumber(slot.quantityRequired) or 1 })
            end
        end
        return
    end
    local low, high = readAll(ui.GetRecipeNumItemsProduced, recipeID)
    if plainNumber(low) then recipe.made = { low, plainNumber(high) or low } end
    local count = plainNumber(readAll(ui.GetRecipeNumReagents, recipeID)) or 0
    for slot = 1, count do
        local name, _, needed = readAll(ui.GetRecipeReagentInfo, recipeID, slot)
        local _, itemID = parseLink(readAll(ui.GetRecipeReagentItemLink, recipeID, slot))
        table.insert(recipe.reagents, { itemID = itemID, count = plainNumber(needed) or 1, name = plainString(name) })
    end
end

local function readModernWindow()
    local ui = global("C_TradeSkillUI")
    if type(ui) ~= "table" or type(ui.GetAllRecipeIDs) ~= "function" then return nil end
    -- Reagents are missing until the client says the window is ready; the
    -- update that follows readiness reads it again.
    if type(ui.IsTradeSkillReady) == "function" and readAll(ui.IsTradeSkillReady) == false then return nil end
    local profession, skill, maxSkill = modernLine(ui)
    profession = plainString(profession)
    if not profession then return nil end
    local snapshot = { profession = profession, skill = skill, maxSkill = maxSkill, api = "modern", recipes = {}, order = {} }
    if readAll(ui.IsTradeSkillLinked) == true or readAll(ui.IsTradeSkillGuild) == true then snapshot.linked = true end
    local ids = Client:Read(ui.GetAllRecipeIDs)
    for _, recipeID in ipairs(type(ids) == "table" and ids or {}) do
        local info = plainNumber(recipeID) and Client:Read(ui.GetRecipeInfo, recipeID) or nil
        if type(info) == "table" and info.type ~= "header" and info.type ~= "subheader" and plainString(info.name) then
            local difficulty = plainString(info.difficulty) or RELATIVE_DIFFICULTY[plainNumber(info.relativeDifficulty) or -1]
            local recipe = { name = info.name, spellID = recipeID, difficulty = difficulty, color = colorOf(difficulty),
                available = plainNumber(info.numAvailable), skillUps = plainNumber(info.numSkillUps),
                known = info.learned ~= false, reagents = {} }
            takeLink(recipe, readAll(ui.GetRecipeItemLink, recipeID))
            modernReagents(ui, recipeID, recipe)
            table.insert(snapshot.order, recipe)
        end
    end
    return snapshot
end

-- Reads the open profession window into a snapshot, or nil when none is
-- open or readable:
--   { profession, skill, maxSkill, api = "tradeskill"|"craft"|"modern",
--     time, partial = true when a header was collapsed, linked = true for
--     another player's (or a guild's) window,
--     recipes = { [key] = recipe }, order = { recipe, ... } in window order,
--     index = { [spellID | "item:<id>" | "name:<name>"] = key } }
-- where a recipe is { key, name, spellID, itemID, difficulty, color,
-- made = { min, max }, reagents = { { itemID, count, name } }, available,
-- skillUps, known }. `which` picks the Classic window ("tradeskill" or
-- "craft"); the modern API is the fallback for either.
function Client:ReadTradeSkillWindow(which)
    local snapshot = readClassicWindow(which or "tradeskill")
    if not snapshot or #snapshot.order == 0 then snapshot = readModernWindow() or snapshot end
    if not snapshot then return nil end
    snapshot.time = epoch()
    snapshot.index = {}
    for _, recipe in ipairs(snapshot.order) do
        recipe.key = Client.RecipeKey(recipe)
        if recipe.key ~= nil then
            snapshot.recipes[recipe.key] = recipe
            snapshot.index[recipe.key] = recipe.key
            if recipe.spellID then snapshot.index[recipe.spellID] = recipe.key end
            if recipe.itemID then snapshot.index["item:" .. recipe.itemID] = recipe.key end
            if recipe.name then snapshot.index["name:" .. recipe.name:lower()] = recipe.key end
        end
    end
    return snapshot
end

-- This session's snapshots, by lowercased profession. Never saved.
Client.tradeSkillSnapshots = {}

local function snapshotSignature(snapshot)
    local parts = { tostring(snapshot.skill), tostring(snapshot.maxSkill) }
    for _, recipe in ipairs(snapshot.order) do
        table.insert(parts, tostring(recipe.key) .. "=" .. tostring(recipe.color) .. (recipe.known and "" or "?"))
    end
    return table.concat(parts, ",")
end

-- Keeps a snapshot for the session, logs it and tells the listeners - the
-- last two only when something changed, since the window updates after
-- every craft. A linked window is somebody else's profession and is left
-- alone.
function Client:StoreTradeSkillSnapshot(snapshot)
    if type(snapshot) ~= "table" or not snapshot.profession then return false end
    if snapshot.linked then
        logProf("linked", { profession = snapshot.profession, api = snapshot.api })
        return false
    end
    local name = snapshot.profession:lower()
    local previous = self.tradeSkillSnapshots[name]
    self.tradeSkillSnapshots[name] = snapshot
    snapshot.signature = snapshotSignature(snapshot)
    if previous and previous.signature == snapshot.signature then return false end
    logProf("window", { profession = snapshot.profession, skill = snapshot.skill, maxSkill = snapshot.maxSkill,
        api = snapshot.api, recipes = #snapshot.order, partial = snapshot.partial })
    ns:Log("prof: " .. snapshot.profession .. " " .. tostring(snapshot.skill) .. ", " .. #snapshot.order .. " recipes read")
    self:ProfessionChanged("tradeskill", snapshot.profession, snapshot)
    return true
end

function Client:ScanTradeSkill(which)
    local snapshot = self:ReadTradeSkillWindow(which)
    if snapshot then
        local news = self:StoreTradeSkillSnapshot(snapshot)
        -- The Make buttons drew when the window showed, before the client had
        -- its recipes ("Not learned"); a reopened window that reads as before
        -- is no news, so the first read after a show tells them to look again.
        if self.windowShown and not news then self:ProfessionChanged("window", which) end
        self.windowShown = nil
    end
    return snapshot
end

-- The latest snapshot of a profession's window this session (see
-- ReadTradeSkillWindow for its shape), or nil until the player opened it.
function Client:GetTradeSkillSnapshot(professionName)
    if type(professionName) ~= "string" then return nil end
    return self.tradeSkillSnapshots[professionName:lower()]
end

function Client:GetTradeSkillSnapshots()
    return self.tradeSkillSnapshots
end

-- A recipe of the snapshot by any of its identities: a spell ID, "item:<id>",
-- "name:<name>", or the snapshot's own key.
function Client:GetSnapshotRecipe(professionName, key)
    local snapshot = self:GetTradeSkillSnapshot(professionName)
    if not snapshot or key == nil then return nil end
    local found = snapshot.index and snapshot.index[key]
    return found ~= nil and snapshot.recipes[found] or nil
end

-- Making from a guide step ----------------------------------------------------------
--
-- A Make button on a craft or skillup step asks the open profession window
-- to make a recipe: `DoTradeSkill` with the window's row and a count on the
-- Classic window, `DoCraft` (one at a time; an enchant then waits for its
-- target) on the Craft window, and `C_TradeSkillUI.CraftRecipe` on a modern
-- client. On the modern client (Forever's) the button opens the window on
-- the recipe first (`OpenProfession`), and every order selects its recipe in
-- the window (`FocusRecipe`), so the player sees what is being made. A press
-- is one batch. A batch made to a skill stops when the window shows that
-- skill (`StopTradeSkill`), so luck with skill-ups spends no extra materials.

local function sameProfession(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- nil asks for whichever profession's window is open.
local function wanted(line, professionName)
    return professionName == nil or sameProfession(line, professionName)
end

-- The open window's row for a recipe, by its spell or its product:
-- { api, index, available, profession, skill, spellID } or nil and why:
-- "closed" (no window, or another profession's; `other` names it),
-- "missing" (not in the window: not learned, or under a collapsed header
-- or a filter). `professionName` nil takes whichever window is open.
function Client:FindCraft(professionName, spellID, itemID)
    spellID, itemID = tonumber(spellID), tonumber(itemID)
    local which = self.professionWindow
    local api = which and CLASSIC_WINDOWS[which]
    if api and type(global(api.count)) == "function" then
        local line, skill = readAll(global(api.line))
        line = plainString(line)
        local count = plainNumber(readAll(global(api.count))) or 0
        -- A client with the Classic calls that lists nothing through them
        -- (Forever) answers through C_TradeSkillUI below.
        if line and line ~= "UNKNOWN" and count > 0 then
            if not wanted(line, professionName) then return nil, "closed", line end
            for index = 1, count do
                local name, kind, available = api.info(index)
                if plainString(name) and kind ~= "header" and kind ~= "subheader" then
                    local recipe = {}
                    takeLink(recipe, readAll(global(api.recipeLink), index))
                    takeLink(recipe, readAll(global(api.itemLink), index))
                    -- By the spell where the window gives one: two recipes can make one item.
                    local match
                    if spellID and recipe.spellID then match = recipe.spellID == spellID
                    else match = itemID ~= nil and recipe.itemID == itemID end
                    if match then
                        return { api = which, index = index, available = plainNumber(available) or 0,
                            profession = line, skill = plainNumber(skill), spellID = recipe.spellID }
                    end
                end
            end
            return nil, "missing"
        end
    end
    local ui = global("C_TradeSkillUI")
    if which and type(ui) == "table" and type(ui.CraftRecipe) == "function" then
        local line, skill = modernLine(ui)
        if not line then return nil, "closed" end
        if not wanted(line, professionName) then return nil, "closed", line end
        if not spellID and itemID then
            local recipe = self:GetSnapshotRecipe(line, "item:" .. itemID)
            spellID = recipe and recipe.spellID
        end
        local info = spellID and self:Read(ui.GetRecipeInfo, spellID)
        if type(info) ~= "table" or info.learned == false then return nil, "missing" end
        -- numAvailable may be missing on Forever: nil is "not said", not none.
        return { api = "modern", spellID = spellID, available = plainNumber(info.numAvailable),
            profession = line, skill = skill }
    end
    return nil, "closed"
end

-- Makes `count` of a recipe in the open window (as many as the materials
-- carried allow), stopping early at `untilSkill` when given. `carried` is
-- how many crafts the bags make by the recipe data (Kit.Crafting:CanMake),
-- for a window that does not say or says too few. Returns the count asked
-- of the client, or nil and FindCraft's reason, or "materials" when nothing
-- can be made from what is carried.
function Client:Craft(professionName, spellID, itemID, count, untilSkill, carried)
    local found, why, other = self:FindCraft(professionName, spellID, itemID)
    if found then
        local said = found.available
        local Crafting = ns.Kit.Crafting
        found.available = Crafting and Crafting:Available(said, carried) or said
        found.said = said
    end
    if found and found.available == 0 then found, why = nil, "materials" end
    if not found then
        logProf("craft", { profession = professionName, spell = spellID, item = itemID, why = why, other = other,
            window = self.professionWindow, craftRecipe = type(global("C_TradeSkillUI")) == "table"
                and type(global("C_TradeSkillUI").CraftRecipe) == "function" })
        return nil, why, other
    end
    self:FocusRecipe(spellID, itemID)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if found.available then count = math.min(count, found.available) end
    if found.api == "craft" then count = 1 end
    local ok
    if found.api == "tradeskill" then
        ok = pcall(global("DoTradeSkill"), found.index, count)
    elseif found.api == "craft" then
        ok = pcall(global("DoCraft"), found.index)
    else
        ok = pcall(global("C_TradeSkillUI").CraftRecipe, found.spellID, count)
    end
    self.craftUntil = (ok and tonumber(untilSkill)) and { profession = found.profession, skill = tonumber(untilSkill) } or nil
    logProf("craft", { profession = found.profession, api = found.api, spell = found.spellID or spellID, item = itemID,
        count = count, available = found.available, said = found.said, carried = carried, skill = found.skill,
        untilSkill = untilSkill, ok = ok })
    if not ok then return nil, "failed" end
    return count
end

-- Each profession's skill line, which C_TradeSkillUI.OpenTradeSkill takes.
-- OpenRoad read these from its recipe data, which is NuuProfessions' now;
-- they are the client's fixed skill line IDs.
Client.professionSkillLines = {
    ["alchemy"] = 171, ["blacksmithing"] = 164, ["enchanting"] = 333, ["engineering"] = 202,
    ["herbalism"] = 182, ["leatherworking"] = 165, ["mining"] = 186, ["skinning"] = 393,
    ["tailoring"] = 197, ["cooking"] = 185, ["first aid"] = 129, ["fishing"] = 356,
}

-- The profession's skill line (Blacksmithing 164, Mining 186), or nil.
function Client:ProfessionSkillLine(professionName)
    if type(professionName) ~= "string" then return nil end
    return self.professionSkillLines[professionName:lower()]
end

-- True where NuuRoad can open a profession's window itself: the modern
-- C_TradeSkillUI.OpenTradeSkill. The Classic window opens only by casting
-- the profession, which an addon may not.
function Client:CanOpenProfession(professionName)
    local ui = global("C_TradeSkillUI")
    return type(ui) == "table" and type(ui.OpenTradeSkill) == "function"
        and self:ProfessionSkillLine(professionName) ~= nil
end

-- Opens a profession's window and, once it shows, selects the recipe in it.
-- Returns whether the client took the call.
function Client:OpenProfession(professionName, spellID, itemID)
    local line = self:ProfessionSkillLine(professionName)
    local ui = global("C_TradeSkillUI")
    if not line or type(ui) ~= "table" or type(ui.OpenTradeSkill) ~= "function" then return false end
    self.pendingFocus = { spell = tonumber(spellID), item = tonumber(itemID) }
    local ok, result = pcall(ui.OpenTradeSkill, line)
    logProf("open", { profession = professionName, skillLine = line, spell = spellID, item = itemID, ok = ok,
        result = ok and tostring(result) or nil })
    -- Already open on that profession: no show event will come.
    if ok and self.professionWindow then self:ScheduleFocus() end
    return ok
end

-- Selects a recipe in the open profession window, so the player sees what
-- a click makes: the modern window's CraftingPage:SelectRecipe, else the
-- Classic list's TradeSkillFrame_SetSelection, scrolled to it. Returns the
-- way that worked, or nil.
function Client:FocusRecipe(spellID, itemID)
    spellID, itemID = tonumber(spellID), tonumber(itemID)
    local how
    local ui = global("C_TradeSkillUI")
    local frame = global("ProfessionsFrame")
    local page = type(frame) == "table" and frame.CraftingPage
    if spellID and type(ui) == "table" and type(page) == "table" and type(page.SelectRecipe) == "function" then
        local info = self:Read(ui.GetRecipeInfo, spellID)
        if type(info) == "table" and pcall(page.SelectRecipe, page, info) then how = "SelectRecipe" end
    end
    if not how and self.professionWindow == "tradeskill" and type(global("TradeSkillFrame_SetSelection")) == "function" then
        local found = self:FindCraft(nil, spellID, itemID)
        if found and found.index and pcall(global("TradeSkillFrame_SetSelection"), found.index) then
            how = "TradeSkillFrame_SetSelection"
            local scroll = global("TradeSkillListScrollFrame")
            local offset = math.max(0, found.index - 3)
            if scroll and type(global("FauxScrollFrame_SetOffset")) == "function" then
                pcall(global("FauxScrollFrame_SetOffset"), scroll, offset)
                local bar = global("TradeSkillListScrollFrameScrollBar")
                if bar and bar.SetValue then pcall(bar.SetValue, bar, offset * (tonumber(global("TRADE_SKILL_HEIGHT")) or 16)) end
            end
            if type(global("TradeSkillFrame_Update")) == "function" then pcall(global("TradeSkillFrame_Update")) end
        end
    end
    logProf("focus", { spell = spellID, item = itemID, how = how, window = self.professionWindow,
        professionsFrame = type(page) == "table" })
    return how
end

-- A window opened for a recipe selects it once its list is there: a moment
-- after the show, and again a little later for a list still loading.
function Client:ScheduleFocus()
    local focus = self.pendingFocus
    if not focus then return end
    local run = function()
        if self.pendingFocus ~= focus then return end
        if self:FocusRecipe(focus.spell, focus.item) then self.pendingFocus = nil end
    end
    local timer = global("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        pcall(timer.After, 0.2, run)
        pcall(timer.After, 0.8, function() run(); self.pendingFocus = nil end)
    else
        run()
        self.pendingFocus = nil
    end
end

-- Called on every profession window update: a batch made to a skill stops
-- once the window shows it.
function Client:CheckCraftStop()
    local stop = self.craftUntil
    if not stop then return end
    local skill
    local api = self.professionWindow and CLASSIC_WINDOWS[self.professionWindow]
    if api and type(global(api.line)) == "function" then
        local line, lineSkill = readAll(global(api.line))
        if sameProfession(plainString(line), stop.profession) then skill = plainNumber(lineSkill) end
    end
    skill = skill or self:GetSkillRank(stop.profession)
    if skill and skill >= stop.skill then
        self.craftUntil = nil
        local ok = pcall(global("StopTradeSkill"))
        logProf("craftStop", { profession = stop.profession, skill = skill, untilSkill = stop.skill, ok = ok })
    end
end

-- Events --------------------------------------------------------------------------

-- The window updates in bursts (every craft, every item that arrives from
-- the server), so a read waits for the burst to settle.
local SETTLE = 0.5

function Client:ScheduleProfessionRead()
    if self.professionPending then return end
    local run = function()
        self.professionPending = nil
        if self.professionWindow then self:ScanTradeSkill(self.professionWindow) end
    end
    local timer = global("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        self.professionPending = true
        if not pcall(timer.After, SETTLE, run) then run() end
    else
        run()
    end
end

local PROFESSION_EVENTS = {
    TRADE_SKILL_SHOW = "tradeskill", TRADE_SKILL_UPDATE = "tradeskill", TRADE_SKILL_LIST_UPDATE = "tradeskill",
    TRADE_SKILL_DATA_SOURCE_CHANGED = "tradeskill", CRAFT_SHOW = "craft", CRAFT_UPDATE = "craft",
    TRADE_SKILL_CLOSE = "close", CRAFT_CLOSE = "close",
}

function Client:OnProfessionEvent(event)
    local kind = PROFESSION_EVENTS[event]
    if kind == "tradeskill" or kind == "craft" then
        -- An update with no window open (a skill-up elsewhere) has nothing to read.
        local shown = event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW"
        if shown then self.professionWindow, self.windowShown = kind, true end
        if self.professionWindow then
            self:CheckCraftStop()
            self:ScheduleProfessionRead()
        end
        -- The Make buttons follow the window open and shut; a window opened
        -- for a recipe selects it.
        if shown then
            self:ProfessionChanged("window", kind)
            self:ScheduleFocus()
        end
    elseif kind == "close" then
        self.professionWindow, self.craftUntil = nil, nil
        self:ProfessionChanged("window", "closed")
    end
end

function Client:WatchProfessionWindows()
    if self.professionFrame or type(global("CreateFrame")) ~= "function" then return end
    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or not frame or not frame.SetScript then return end
    for event in pairs(PROFESSION_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    pcall(frame.SetScript, frame, "OnEvent", function(_, event, ...) self:OnProfessionEvent(event, ...) end)
    self.professionFrame = frame
end

function Client:GetDiagnostics()
    return self.build, self.capabilities
end

function Client:Has(capability)
    return self.capabilities[capability] == true
end

function Client:GetDiagnosticLines()
    local build = self.build or {}
    local lines = {
        "Build " .. tostring(build.version) .. " (" .. tostring(build.build) .. ")",
        "Date " .. tostring(build.date) .. " - TOC " .. tostring(build.toc),
        "Detected symbols are not verified Forever support. Run the smoke checklist before enabling an integration.",
        "Saved data sessions: " .. tostring(ns.db and ns.db.sessionCount or "?") .. " (stays at 1 when the client never restores SavedVariables)",
    }
    local names = {}
    for name in pairs(self.capabilities) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        table.insert(lines, name .. ": " .. (self.capabilities[name] and "detected - unverified" or "not detected - manual fallback"))
    end
    return lines
end

ns:RegisterModule("Client", Client)
