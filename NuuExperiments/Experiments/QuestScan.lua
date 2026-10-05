local _, ns = ...

-- Every quest the server knows, read from the client without taking it: its
-- title, level and objectives (type, text, how many), for each ID in the
-- client's quest table (QuestScanIDs.lua). Only by hand: /nuux run quest-scan.
--
-- What quest-data saw on 1.60.1 (70205): C_QuestLog.RequestLoadQuestByID gets
-- QUEST_DATA_LOAD_RESULT(id, true) for a real quest, within a frame, and
-- (id, false) for one the server does not have, after a quarter second; then
-- C_QuestLog.GetQuestObjectives answers numRequired for a quest not in the
-- log. ForeverGuide saw the server go silent when asked too fast, so requests
-- go out at a steady rate that halves when an answer is late and grows again
-- after a run of prompt ones; an ID not answered in TRIES tries is left for
-- the next run.
--
-- Data (t:Data(), started over on a new client build):
--   quests[id]  = { title, level, xp, objectives = { { type, text, required }, ... } }
--   missing[id] = true    the server answered false: it has no such quest
--   silent[id]  = tries   never answered; asked again by the next run
-- A run asks only IDs in neither quests nor missing, so a stopped or timed-out
-- scan carries on; a run after one that answered everything starts over.
-- Tools/QuestExport.py turns it into db/ingame/.
--
-- Quest data the client has cached is read from the cache, which keeps what
-- the server said when the quest was first loaded, (as far as we know, unchecked) until the build changes.
-- To see a server change (dungeon quest XP was cut), close the game, delete
-- Cache/WDB/<locale>/questcache.wdb and scan again: every quest is then asked
-- of the server, and the game writes the fresh cache when it closes, where
-- QuestExport.py reads each quest's XP difficulty and multiplier.
--
-- xp is GetQuestLogRewardXP(id): the quest's XP at the scanning character's
-- level (playerLevel), which QuestExport.py checks its XP formula against.

local RATE, MIN_RATE, MAX_RATE = 10, 2, 40 -- requests a second
local TICK, TIMEOUT, TRIES = 0.1, 5, 3
local GROW_AFTER = 50                      -- prompt answers in a row before the rate grows
local REPORT_EVERY = 15                    -- seconds between progress lines

local function value(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- Title, level, objectives and XP as the client has them now; nil without a title.
local function read(id)
    local QL = C_QuestLog or {}
    local title = value(QL.GetTitleForQuestID, id)
    if type(title) ~= "string" or title == "" then return nil end
    local entry = { title = title }
    local level = value(QL.GetQuestDifficultyLevel, id)
    if type(level) == "number" and level > 0 then entry.level = level end
    local objectives = value(QL.GetQuestObjectives, id)
    if type(objectives) == "table" and #objectives > 0 then
        entry.objectives = {}
        for i, o in ipairs(objectives) do
            entry.objectives[i] = {
                type = type(o.type) == "string" and o.type or nil,
                text = type(o.text) == "string" and o.text or nil,
                required = type(o.numRequired) == "number" and o.numRequired or nil,
            }
        end
    end
    local xp = value(GetQuestLogRewardXP, id)
    if type(xp) == "number" and xp > 0 then entry.xp = xp end
    return entry
end

local function expand(spans)
    local ids = {}
    for _, span in ipairs(spans or {}) do
        for id = span[1], span[2] do ids[#ids + 1] = id end
    end
    return ids
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function clock()
    if type(GetTime) == "function" then return GetTime() end
    return os.time()
end

ns:Experiment({
    id = "quest-scan",
    title = "Every quest the server knows, with its objectives",
    auto = false,
    run = function(t)
        t:Exists({
            "C_QuestLog.RequestLoadQuestByID", "C_QuestLog.GetTitleForQuestID", "C_QuestLog.GetQuestObjectives",
            "C_QuestLog.GetQuestDifficultyLevel", "GetQuestLogRewardXP", "HaveQuestData",
        })
        local QL = C_QuestLog or {}
        if type(QL.RequestLoadQuestByID) ~= "function" then
            t:Log("no C_QuestLog.RequestLoadQuestByID: nothing to scan with")
            return
        end

        local data = t:Data()
        local build = ns.Build()
        if data.build ~= build then
            for k in pairs(data) do data[k] = nil end
            data.build = build
        end
        data.quests = data.quests or {}
        data.missing = data.missing or {}
        data.silent = {}
        data.playerLevel = type(UnitLevel) == "function" and UnitLevel("player") or nil

        local ids = expand(ns.QuestScanIDs)
        local left = false
        for _, id in ipairs(ids) do
            if not data.quests[id] and not data.missing[id] then
                left = true
                break
            end
        end
        if not left then
            data.quests, data.missing = {}, {}
            t:Log("every ID was answered: starting over")
        end
        local cursor, inflight, inflightCount, retry = 1, {}, 0, {}
        local rate, budget, prompt, lastTick = RATE, RATE, 0, clock()
        local started, lastReport, lastBar = clock(), clock(), clock()
        local stats = { asked = 0, found = 0, cached = 0, missing = 0, late = 0, slowDowns = 0 }

        -- The window's bar: cheap, so twice a second.
        local function bar()
            local done = count(data.quests) + count(data.missing)
            t:Progress(done, #ids, string.format("%d of %d quests answered", done, #ids))
        end

        local function progress()
            bar()
            t:Set("progress", {
                ids = #ids, done = count(data.quests) + count(data.missing), quests = count(data.quests),
                missing = count(data.missing), silent = count(data.silent), rate = rate, stats = stats,
                seconds = math.floor(clock() - started),
            })
            if ns.Changed then ns:Changed() end
        end

        local function nextID()
            local item = table.remove(retry, 1)
            if item then return item.id, item.tries end
            while ids[cursor] do
                local id = ids[cursor]
                cursor = cursor + 1
                if not data.quests[id] and not data.missing[id] then return id, 1 end
            end
            return nil
        end

        local function ask(id, tries)
            -- Quest data the client already holds never gets an event.
            if value(HaveQuestData, id) == true then
                local entry = read(id)
                if entry then
                    data.quests[id] = entry
                    stats.found, stats.cached = stats.found + 1, stats.cached + 1
                    return false
                end
            end
            inflight[id] = { sent = clock(), tries = tries }
            inflightCount = inflightCount + 1
            stats.asked = stats.asked + 1
            pcall(QL.RequestLoadQuestByID, id)
            return true
        end

        local function answered(id)
            local entry = inflight[id]
            if not entry then return nil end
            inflight[id] = nil
            inflightCount = inflightCount - 1
            prompt = prompt + 1
            if prompt >= GROW_AFTER then
                prompt = 0
                rate = math.min(MAX_RATE, rate * 1.25)
            end
            return entry
        end

        t:On("QUEST_DATA_LOAD_RESULT", function(_, id, success)
            if not answered(id) then return end
            if success then
                local entry = read(id)
                if entry then
                    data.quests[id] = entry
                    stats.found = stats.found + 1
                    return
                end
                -- Loaded but no title yet: ask again later.
                data.silent[id] = (data.silent[id] or 0) + 1
            else
                data.missing[id] = true
                stats.missing = stats.missing + 1
            end
        end)

        local function tick()
            local now = clock()
            budget = math.min(rate, budget + rate * math.min(1, now - lastTick))
            lastTick = now

            local late = false
            for id, entry in pairs(inflight) do
                if now - entry.sent > TIMEOUT then
                    inflight[id] = nil
                    inflightCount = inflightCount - 1
                    stats.late = stats.late + 1
                    late = true
                    if entry.tries < TRIES then
                        retry[#retry + 1] = { id = id, tries = entry.tries + 1 }
                    else
                        data.silent[id] = entry.tries
                    end
                end
            end
            if late then
                rate, prompt, budget = math.max(MIN_RATE, rate / 2), 0, 0
                stats.slowDowns = stats.slowDowns + 1
            end

            while budget >= 1 do
                local id, tries = nextID()
                if not id then break end
                if ask(id, tries) then budget = budget - 1 end
            end

            if now - lastBar >= 0.5 then
                lastBar = now
                bar()
            end
            if now - lastReport >= REPORT_EVERY then
                lastReport = now
                progress()
                t:Log("%d of %d answered, %.1f a second", count(data.quests) + count(data.missing), #ids, rate)
            end
            if inflightCount == 0 and #retry == 0 and not ids[cursor] then
                progress()
                t:Done()
                return
            end
            t:After(TICK, tick)
        end

        progress()
        t:Wait(3600)
        tick()
    end,
})
