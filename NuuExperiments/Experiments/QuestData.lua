local _, ns = ...

-- Whether the client gives a quest's objectives (type, numRequired) for a
-- quest that is not in the log, once asked to load it. Guide format v1
-- leaves `count` off steps tied to an objective and expects the number from
-- the client, also for steps ahead of the quest being taken
-- (NuuRoad/docs/examples/guide-v1.lua, QUEST WORK).
--
-- Every quest is read three times: before anything is asked, when
-- QUEST_DATA_LOAD_RESULT answers for it, and once more at the end whether or
-- not it answered. The first quest in the log is read the same way, to see the
-- shape an objective has when the client certainly knows it.

-- Seconds the server gets to answer before the last read.
local WAIT = 10

-- Quests unlikely to be in the log or done on whichever character runs this:
-- starting zones of both factions, a Barrens quest, a high-level one, and an
-- ID that does not exist.
local QUESTS = {
    871,    -- Disrupt the Attacks, Horde, The Barrens
    4641,   -- Your Place in the World, orc and troll start
    364,    -- The Mindless Ones, undead start
    783,    -- A Threat Within, human start
    33,     -- Wolves Across the Border, Elwynn Forest
    2770,   -- Gahz'rilla, Tanaris
    999999, -- no such quest
}

-- What fn(...) returned: "<missing>" when there is no such function, the
-- error text when it failed, the one value, or every value in order with a
-- nil kept as "nil".
local function call(fn, ...)
    if type(fn) ~= "function" then return "<missing>" end
    local function collect(ok, ...)
        if not ok then return "<error> " .. tostring((...)) end
        local count = select("#", ...)
        if count == 0 then return "nil" end
        if count == 1 then
            local value = ...
            if value == nil then return "nil" end
            return value
        end
        local out = {}
        for i = 1, count do
            local value = select(i, ...)
            out[i] = value == nil and "nil" or value
        end
        return out
    end
    return collect(pcall(fn, ...))
end

local function read(questID)
    local QL = C_QuestLog or {}
    local snapshot = {
        inLog = call(QL.IsOnQuest, questID),
        logIndex = call(QL.GetLogIndexForQuestID or GetQuestLogIndexByID, questID),
        completed = call(QL.IsQuestFlaggedCompleted, questID),
        title = call(QL.GetTitleForQuestID, questID),
        info = call(QL.GetQuestInfo, questID),
        objectives = call(QL.GetQuestObjectives, questID),
        objective1 = call(GetQuestObjectiveInfo, questID, 1, false),
        objective2 = call(GetQuestObjectiveInfo, questID, 2, false),
    }
    return snapshot
end

-- The first real quest in the log, by whichever log API the client has.
local function firstLoggedQuest()
    local count = call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries)
    if type(count) == "table" then count = count[1] end
    if type(count) ~= "number" then return nil end
    for index = 1, count do
        local questID, isHeader
        if C_QuestLog and C_QuestLog.GetInfo then
            local ok, info = pcall(C_QuestLog.GetInfo, index)
            if ok and type(info) == "table" then questID, isHeader = info.questID, info.isHeader end
        elseif GetQuestLogTitle then
            local ok, _, _, _, header, _, _, _, id = pcall(GetQuestLogTitle, index)
            if ok then questID, isHeader = id, header end
        end
        if questID and questID ~= 0 and not isHeader then return questID end
    end
    return nil
end

ns:Experiment({
    id = "quest-data",
    title = "Quest objectives for quests not in the log",
    run = function(t)
        t:Exists({
            "C_QuestLog.RequestLoadQuestByID", "C_QuestLog.GetQuestObjectives", "C_QuestLog.GetTitleForQuestID",
            "C_QuestLog.GetQuestInfo", "C_QuestLog.IsOnQuest", "C_QuestLog.IsQuestFlaggedCompleted",
            "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetInfo", "C_QuestLog.GetNumQuestLogEntries",
            "GetQuestObjectiveInfo", "GetQuestLogIndexByID", "GetQuestLogTitle", "GetNumQuestLogEntries",
            "GetQuestLogLeaderBoard",
        })

        local logged = firstLoggedQuest()
        t:Set("logged", logged and { questID = logged, read = read(logged) } or "no quest in the log")

        local quests, answered, waited = {}, 0, 0
        -- The bar runs over the wait; its line counts the answers.
        local function progress()
            t:Progress(waited, WAIT, string.format("%d of %d quests answered, last read in %d s",
                answered, #QUESTS, WAIT - waited))
        end
        for _, questID in ipairs(QUESTS) do quests[questID] = { before = read(questID) } end
        t:Set("quests", quests)

        t:Wait(15)
        t:On("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
            local entry = quests[questID]
            if not entry or entry.event then return end
            entry.event = { success = success }
            entry.loaded = read(questID)
            answered = answered + 1
            t:Log("QUEST_DATA_LOAD_RESULT %s %s", tostring(questID), tostring(success))
            t:Set("quests", quests)
            progress()
        end)
        for _, questID in ipairs(QUESTS) do
            local requested = call(C_QuestLog and C_QuestLog.RequestLoadQuestByID, questID)
            quests[questID].requested = requested
        end
        t:Set("quests", quests)

        progress()
        local function second()
            waited = waited + 1
            progress()
            if waited < WAIT then t:After(1, second) end
        end
        t:After(1, second)

        -- Whatever answered by now, and a last read of every quest either way.
        t:After(WAIT, function()
            for _, questID in ipairs(QUESTS) do quests[questID].late = read(questID) end
            t:Set("quests", quests)
            t:Set("answered", answered)
            t:Done()
        end)
    end,
})
