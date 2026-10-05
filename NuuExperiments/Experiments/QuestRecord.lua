local _, ns = ...

-- Quest facts as you play, merged into one record per quest and NPC (not an
-- event log). It starts at every login and listens all session ("watching").
--
-- Data (t:Data(), kept across logins and builds; Tools/QuestExport.py turns it
-- into db/ingame/):
--   quests[id] = {
--       title, level,
--       starts = { ["npc:3143"] = true, ["object:1234"] = true },  who offered it
--       ends   = { ... },                                           who took it in
--       startItem = itemID, shared = true (a party member shared it),
--       offered = { lowest, highest } player level it was offered at,
--       objectives[i] = { type, text, required,
--           points = { { map, x, y }, ... }   where it went up (half a map unit)
--           targets = { [npcID] = votes } },  the mob targeted when it did
--       turnins = { { xp, money, level }, ... }  rewards at that player level
--   }
--   npcs[id], objects[id] = { name, level, points = { { map, x, y }, ... } }
--   order = { 871, -871, ... }   quests accepted (+) and turned in (-), in order

local MAX_POINTS, MAX_OBJECTIVE_POINTS, MAX_TURNINS, MAX_ORDER = 8, 40, 5, 2000
local TARGET_WINDOW = 20 -- seconds a mob counts as just targeted

local data, session

local function value(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function clock()
    if type(GetTime) == "function" then return GetTime() end
    return os.time()
end

-- v rounded to 1/per: round(v, 100) to two decimals, round(v, 2) to a half.
local function round(v, per)
    return math.floor(v * per + 0.5) / per
end

-- uiMapID, x, y (0-100, two decimals) where the player stands; nil inside
-- instances and anywhere the map has no position.
local function here()
    local Map = C_Map or {}
    local map = value(Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local pos = value(Map.GetPlayerMapPosition, map, "player")
    if type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then x, y = pos:GetXY() end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return map, round(x * 100, 100), round(y * 100, 100)
end

local function addPoint(points, map, x, y, tolerance, max)
    for _, p in ipairs(points) do
        if p[1] == map and math.abs(p[2] - x) <= tolerance and math.abs(p[3] - y) <= tolerance then return end
    end
    if #points < max then points[#points + 1] = { map, x, y } end
end

-- "npc:3143" or "object:1234" for a unit; nil and true for a player.
local function unitRef(unit)
    local guid = value(UnitGUID, unit)
    if type(guid) ~= "string" then return nil end
    local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Player" or string.match(guid, "^Player%-") then return nil, true end
    if kind == "Creature" or kind == "Vehicle" then return "npc:" .. id end
    if kind == "GameObject" then return "object:" .. id end
    return nil
end

local function bump(key)
    session[key] = (session[key] or 0) + 1
end

-- Names, level and where the player stands, for the NPC or object of `unit`.
local function noteUnit(unit)
    local ref, player = unitRef(unit)
    if not ref then return nil, player end
    local kind, id = string.match(ref, "^(%a+):(%d+)$")
    id = tonumber(id)
    local store = kind == "npc" and data.npcs or data.objects
    local entry = store[id]
    if not entry then
        entry = { points = {} }
        store[id] = entry
        bump(kind == "npc" and "npcs" or "objects")
    end
    local name = value(UnitName, unit)
    if type(name) == "string" and name ~= "" then entry.name = name end
    local level = value(UnitLevel, unit)
    if type(level) == "number" and level > 0 then entry.level = level end
    local map, x, y = here()
    if map then addPoint(entry.points, map, x, y, 0.5, MAX_POINTS) end
    return ref
end

local function quest(id, title)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    local entry = data.quests[id]
    if not entry then
        entry = {}
        data.quests[id] = entry
        bump("quests")
    end
    if type(title) == "string" and title ~= "" then entry.title = title end
    return entry
end

local function mark(entry, field, ref)
    if not entry or not ref then return end
    entry[field] = entry[field] or {}
    if not entry[field][ref] then
        entry[field][ref] = true
        bump(field)
    end
end

local function order(v)
    if #data.order < MAX_ORDER then data.order[#data.order + 1] = v end
end

-- The quest log ------------------------------------------------------------------------

-- questID, title, level for each quest in the log, by whichever API the client has.
local function logQuests()
    local out = {}
    local QL = C_QuestLog or {}
    local n = value(QL.GetNumQuestLogEntries) or value(GetNumQuestLogEntries)
    if type(n) ~= "number" then return out end
    for i = 1, n do
        local info = value(QL.GetInfo, i)
        if type(info) == "table" then
            if not info.isHeader and info.questID and info.questID > 0 then
                out[#out + 1] = { id = info.questID, title = info.title, level = info.level }
            end
        elseif type(GetQuestLogTitle) == "function" then
            local ok, title, level, _, header, _, _, _, id = pcall(GetQuestLogTitle, i)
            if ok and not header and id and id > 0 then out[#out + 1] = { id = id, title = title, level = level } end
        end
    end
    return out
end

local lastTarget  -- { id, seen }
local seen = {}   -- [questID][i] = numFulfilled at the last look

-- The targeted creature, if it is a mob that could have moved an objective.
local function objectiveTargets()
    local ref = unitRef("target")
    local id = ref and tonumber(string.match(ref, "^npc:(%d+)$"))
    if id and (value(UnitCanAttack, "player", "target") or value(UnitIsDead, "target")) then
        noteUnit("target")
        return id
    end
    if lastTarget and clock() - lastTarget.seen <= TARGET_WINDOW then return lastTarget.id end
    return nil
end

-- Reads the log; an objective that went up since the last look gets a point
-- and a vote for the mob targeted. The first look only remembers.
local function readLog(record)
    local QL = C_QuestLog or {}
    for _, q in ipairs(logQuests()) do
        local entry = quest(q.id, q.title)
        if type(q.level) == "number" and q.level > 0 then entry.level = q.level end
        local objectives = value(QL.GetQuestObjectives, q.id)
        if type(objectives) == "table" then
            local before = seen[q.id]
            seen[q.id] = {}
            entry.objectives = entry.objectives or {}
            for i, o in ipairs(objectives) do
                local saved = entry.objectives[i] or { points = {}, targets = {} }
                entry.objectives[i] = saved
                if type(o.type) == "string" then saved.type = o.type end
                if type(o.text) == "string" and o.text ~= "" then saved.text = o.text end
                if type(o.numRequired) == "number" then saved.required = o.numRequired end
                local now = type(o.numFulfilled) == "number" and o.numFulfilled or 0
                seen[q.id][i] = now
                if record and before and before[i] and now > before[i] then
                    bump("progress")
                    local map, x, y = here()
                    if map then addPoint(saved.points, map, round(x, 2), round(y, 2), 0, MAX_OBJECTIVE_POINTS) end
                    local target = objectiveTargets()
                    if target then saved.targets[target] = (saved.targets[target] or 0) + 1 end
                end
            end
        end
    end
end

-- Events -------------------------------------------------------------------------------

local function windowQuest()
    return quest(value(GetQuestID), value(GetTitleText))
end

-- The quest window's NPC (or object); a player there shared the quest.
local function windowGiver()
    local ref, player = noteUnit("questnpc")
    if not ref and not player then ref, player = noteUnit("npc") end
    return ref, player
end

local handlers = {}

function handlers.QUEST_DETAIL(questStartItemID)
    local entry = windowQuest()
    if not entry then return end
    local ref, player = windowGiver()
    if player then entry.shared = true end
    mark(entry, "starts", ref)
    if type(questStartItemID) == "number" and questStartItemID > 0 then entry.startItem = questStartItemID end
    local level = value(UnitLevel, "player")
    if type(level) == "number" then
        entry.offered = entry.offered or { level, level }
        entry.offered[1] = math.min(entry.offered[1], level)
        entry.offered[2] = math.max(entry.offered[2], level)
    end
end

function handlers.QUEST_PROGRESS()
    local entry = windowQuest()
    if entry then mark(entry, "ends", (windowGiver())) end
end
handlers.QUEST_COMPLETE = handlers.QUEST_PROGRESS

function handlers.GOSSIP_SHOW()
    local ref = noteUnit("npc")
    if not ref then return end
    local Gossip = C_GossipInfo or {}
    for fn, field in pairs({ GetAvailableQuests = "starts", GetActiveQuests = "ends" }) do
        local list = value(Gossip[fn])
        if type(list) == "table" then
            for _, g in ipairs(list) do
                if type(g) == "table" then mark(quest(g.questID, g.title), field, ref) end
            end
        end
    end
end

local function noteNpc() noteUnit("npc") end
handlers.QUEST_GREETING = noteNpc
handlers.MERCHANT_SHOW = noteNpc
handlers.TRAINER_SHOW = noteNpc
handlers.TAXIMAP_OPENED = noteNpc

-- (questID) on some clients, (logIndex, questID) on others.
function handlers.QUEST_ACCEPTED(a, b)
    local id = tonumber(b) or tonumber(a)
    if quest(id) then order(id) end
    readLog(false)
end

function handlers.QUEST_TURNED_IN(id, xp, money)
    local entry = quest(id)
    if not entry then return end
    order(-id)
    bump("turnins")
    entry.turnins = entry.turnins or {}
    if #entry.turnins < MAX_TURNINS then
        entry.turnins[#entry.turnins + 1] = { xp = xp, money = money, level = value(UnitLevel, "player") }
    end
end

function handlers.QUEST_LOG_UPDATE()
    readLog(true)
end

function handlers.PLAYER_TARGET_CHANGED()
    if lastTarget then lastTarget.seen = clock() end
    local ref = unitRef("target")
    local id = ref and tonumber(string.match(ref, "^npc:(%d+)$"))
    if id and value(UnitCanAttack, "player", "target") then
        lastTarget = { id = id, seen = clock() }
        noteUnit("target")
    end
end

ns:Experiment({
    id = "quest-record",
    title = "Quest givers, turn-ins and objectives as you play",
    auto = "login",
    combat = true,
    run = function(t)
        data = t:Data()
        data.quests = data.quests or {}
        data.npcs = data.npcs or {}
        data.objects = data.objects or {}
        data.order = data.order or {}
        session = {}
        seen = {}
        lastTarget = nil
        t:Set("session", session)
        readLog(false)
        for event, fn in pairs(handlers) do
            t:On(event, function(_, ...)
                fn(...)
                t:Set("session", session)
            end)
        end
        t:Keep()
    end,
})
