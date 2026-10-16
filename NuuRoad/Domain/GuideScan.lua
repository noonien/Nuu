local _, ns = ...

-- Retroactive completion scan: picks a guide up in the middle, since a player
-- who loads a guide has often already done part of it, so
-- every step is checked against game state the client still holds after the
-- fact and the ones it can prove are recorded as observed.
--
-- Only durable evidence counts. Quest history, the quest log, objective lines,
-- level, hearth, and known flight paths survive the act; kill counters, bag
-- contents, and the player's position say nothing about what happened earlier,
-- so those steps stay undecided rather than being guessed at. Nothing the scan
-- cannot prove is ever recorded as complete: undecided steps that sit before a
-- proven one are recorded as skipped, exactly as pressing SKIP would.
local GuideScan = { pending = 0 }

-- The quest log is not populated on the first frame after login, so the scan
-- is repeated over the first few updates before it settles.
local PENDING_PASSES = 5

local function questDone(Client, questID, state)
    if type(questID) ~= "number" then return false end
    if state == "finished" then return Client:IsQuestComplete(questID) end
    if state == "readyToTurnIn" then
        -- A quest already handed in satisfies a "finish the objectives" step.
        return Client:IsQuestComplete(questID) or Client:IsQuestReadyToTurnIn(questID)
    end
    if state == "accepted" or state == "acceptedOrFinished" then
        return Client:IsQuestInLog(questID) or Client:IsQuestComplete(questID)
    end
    return false
end

-- True only when the client can still prove the rule was satisfied earlier.
function GuideScan:Observed(observed, node)
    local Client = ns.modules.Client
    if type(observed) ~= "table" or not Client then return false end
    local kind = observed.type
    if kind == "all" or kind == "any" then
        local matchAll = kind == "all"
        local children = observed.children or {}
        if #children == 0 then return false end
        for _, child in ipairs(children) do
            local done = self:Observed(child, node)
            if matchAll and not done then return false end
            if not matchAll and done then return true end
        end
        return matchAll
    end
    if kind == "objective" then
        -- Covers both halves of the question: an objective line the log reports
        -- as finished on a quest still in the log, and one on a quest whose
        -- turn-in has already removed it from the log.
        return Client:IsQuestObjectiveComplete(observed.questID, observed.index) == true
    end
    if kind == "quests" then
        local ids = observed.ids
        if type(ids) ~= "table" or #ids == 0 then return false end
        local matchAll = observed.match ~= "any"
        for _, questID in ipairs(ids) do
            local done = questDone(Client, questID, observed.state)
            if matchAll and not done then return false end
            if not matchAll and done then return true end
        end
        return matchAll
    end
    -- A skill rank, a reputation standing, and the gear on the player's back
    -- are all durable: they read the same now as they did when the step was
    -- done. So is a spell once learned. Crafting and casting are not, so
    -- those steps stay undecided.
    if kind == "level" or kind == "hearth" or kind == "flightpath" or kind == "skill" or kind == "reputation" or kind == "equipped"
        or kind == "spell" then
        return Client:MatchesObservedCompletion(observed, node and node.location, node and node.index) == true
    end
    if kind == "item" then
        -- Bags say nothing about the past, but the quest an item begins, or
        -- the quest it was picked up for, does.
        if observed.startsQuestID then return questDone(Client, observed.startsQuestID, "acceptedOrFinished") end
        if observed.questID then return questDone(Client, observed.questID, "readyToTurnIn") end
        return false
    end
    -- location, kills, crafted, cast, always: nothing durable to read.
    return false
end

-- The mirror of Observed: evidence that a step cannot be done as things
-- stand, because the quest it acts on is not in the log and was never
-- finished - the player skipped the pickup, abandoned the quest, or joined
-- the guide partway. The guide does not pass such a step over: it stops and
-- says so, and the player picks the quest up or presses SKIP. The rule is "nothing left here to do", not "one part is impossible": a step
-- is moot only when some part of it can never be true and every other part is
-- already done, so a visit that still has a quest to accept is never passed
-- over for the turn-in it cannot make.
function GuideScan:Moot(observed, node)
    local Client = ns.modules.Client
    if type(observed) ~= "table" or not Client or not Client.IsQuestMoot then return false end
    local kind = observed.type
    if kind == "all" then
        local moot = false
        for _, child in ipairs(observed.children or {}) do
            if self:Moot(child, node) then
                moot = true
            elseif not self:Observed(child, node) then
                return false
            end
        end
        return moot
    end
    if kind == "any" then
        local children = observed.children or {}
        if #children == 0 then return false end
        for _, child in ipairs(children) do
            if not self:Moot(child, node) then return false end
        end
        return true
    end
    if kind == "objective" then
        return Client:IsQuestMoot(observed.questID) and not self:Observed(observed, node)
    end
    if kind == "item" then
        -- A quest item for a quest the player does not have is nothing to
        -- collect; an item that begins a quest is always there to pick up.
        if observed.startsQuestID or not observed.questID then return false end
        return Client:IsQuestMoot(observed.questID) and not self:Observed(observed, node)
    end
    if kind == "quests" then
        local ids = observed.ids
        if type(ids) ~= "table" or #ids == 0 then return false end
        -- Accepting is always open to the player, so such a rule is never moot.
        if observed.state == "accepted" or observed.state == "acceptedOrFinished" then return false end
        local matchAll = observed.match ~= "any"
        local moot = false
        for _, questID in ipairs(ids) do
            if Client:IsQuestMoot(questID) then
                moot = true
            elseif matchAll and not questDone(Client, questID, observed.state) then
                -- Still a quest on this step the player can finish.
                return false
            elseif not matchAll then
                return false
            end
        end
        return moot
    end
    return false
end

function GuideScan:NodeIsMoot(node)
    if not node or not node.completion or node.completion.type ~= "observed" then return false end
    if node.kind == "choice" and #(node.choices or {}) > 0 then return false end
    return self:Moot(node.completion.observed, node)
end

-- Completion rules the scan can judge either way. A step that rests on one of
-- these and is not done is real outstanding work, so the resume point stops
-- there. An item tied to a quest (one that begins it, or one collected for
-- it) counts too. Everything else - travel, kills, loose items, a hearth, a
-- flight path, a note - is work the client keeps no record of, so it never
-- holds the resume point: the guide opens on the first step that is genuinely
-- still to do, not on the untracked step that happens to follow the last
-- finished one.
local decidableTypes = { quests = true, objective = true, level = true }

local function decides(observed)
    if type(observed) ~= "table" then return false end
    if observed.type == "all" or observed.type == "any" then
        for _, child in ipairs(observed.children or {}) do
            if decides(child) then return true end
        end
        return false
    end
    if observed.type == "item" then return observed.startsQuestID ~= nil or observed.questID ~= nil end
    return decidableTypes[observed.type] == true
end

function GuideScan:BlocksResume(node)
    if not node then return false end
    -- A branch the player has to pick is theirs to pick, never passed over.
    if node.kind == "choice" and #(node.choices or {}) > 0 then return true end
    -- A step waiting to open (a quest to pick up first, a level) is the
    -- player's to open or skip, so it holds the resume point like any other
    -- work not done; so is a quest the player does not have.
    local Progress = ns.modules.Progress
    if Progress and Progress.IsWaiting and Progress:IsWaiting(node) then return true end
    if not node.completion or node.completion.type ~= "observed" then return false end
    if self:NodeIsMoot(node) then return true end
    return decides(node.completion.observed)
end

function GuideScan:NodeCompleted(node)
    if not node or not node.completion or node.completion.type ~= "observed" then return false end
    return self:Observed(node.completion.observed, node)
end

-- A step the client keeps no record of is settled once the first step after
-- it that the client can judge is proven: travel, a note, or a kill count has
-- no value of its own once the work it leads to is done. Only the first
-- decidable step counts, so an outstanding quest in between keeps the step
-- open, and positive proof on the way there (a hearth, a flight path) counts
-- too. This is a display rule; the resume point is decided by Apply.
function GuideScan:Settled(guide, node)
    if not guide or not node or self:BlocksResume(node) then return false end
    local Progress, GuideCheck = ns.modules.Progress, ns.modules.GuideCheck
    if not Progress or not GuideCheck then return false end
    local nodeMap = guide.nodes
    local nextIndex = Progress:NextIndex(guide, node)
    for _ = 1, #guide.nodes do
        local candidate = nodeMap[nextIndex]
        if not candidate then return false end
        if self:NodeCompleted(candidate) then return true end
        if self:BlocksResume(candidate) then return false end
        nextIndex = Progress:NextIndex(guide, candidate)
    end
    return false
end

-- What the tracker paints a checkbox on: a step the player's own progress
-- records as done, one the game still shows as done, or one settled by the
-- proven work after it.
function GuideScan:IsStepDone(guide, node, state)
    if not node then return false end
    local Progress = ns.modules.Progress
    if state and Progress:IsDone(state.statuses[node.index]) then return true end
    return self:NodeCompleted(node) or self:Settled(guide, node)
end

-- Walks forward from the step the player is on, finds the furthest step the
-- game can still prove was done, and leaves the guide on the step after it.
-- Returns how many steps were recorded as observed.
function GuideScan:Apply(guide)
    local Progress, GuideCheck = ns.modules.Progress, ns.modules.GuideCheck
    if not guide or not Progress or not GuideCheck or not ns.modules.Client then return 0 end
    if Progress:IsHeld(guide) then return 0 end
    local nodeMap = guide.nodes
    local state = Progress:GetState(guide)
    local order, proven, lastProven, stop = {}, {}, 0, nil
    local stepIndex = state.currentStep
    for _ = 1, #guide.nodes do
        local node = nodeMap[stepIndex]
        if not node then break end
        table.insert(order, node)
        proven[#order] = self:NodeCompleted(node)
        if proven[#order] then
            lastProven = #order
        elseif not stop and self:BlocksResume(node) then
            stop = #order
        end
        stepIndex = Progress:NextIndex(guide, node)
    end
    -- Nothing proved: the player is where they belong, wherever that is.
    if lastProven == 0 then return 0 end
    -- Stop on the first step that is really outstanding, even when finished
    -- steps lie past it; with no such step, stop just past the last proven one.
    local limit = stop and (stop - 1) or lastProven
    if limit <= 0 then return 0 end
    local marked = 0
    for index = 1, limit do
        local node = order[index]
        -- A condition or a choice edge can send the flow somewhere the walk did
        -- not predict; stop rather than record a step the player is not on.
        if (Progress:GetCurrentNode(guide)) ~= node then break end
        if proven[index] then
            if not Progress:Complete(guide, nil, "observed") then break end
            marked = marked + 1
        elseif not Progress:Forward(guide, true) then
            break
        end
    end
    state.holdStep = nil
    if marked > 0 then
        ns:Log("scan of '" .. guide.meta.title .. "' found " .. marked .. " step(s) already done; resuming at '"
            .. tostring(state.currentStep) .. "'")
    end
    return marked
end

-- Re-run the scan over the next few quest-log updates, for a guide selected
-- before the client has finished handing over the quest log.
function GuideScan:Queue()
    self.pending = PENDING_PASSES
end

-- A player who resets a guide means to run it again, so the pending passes
-- from login are dropped rather than re-advancing the fresh state.
function GuideScan:Cancel()
    self.pending = 0
end

function GuideScan:Tick()
    if (self.pending or 0) <= 0 then return false end
    self.pending = self.pending - 1
    local guide = ns.modules.Progress:GetActiveGuide()
    if not guide then return false end
    if self:Apply(guide) == 0 then return false end
    local MainWindow = ns.modules.MainWindow
    if MainWindow and MainWindow.frame and MainWindow.frame:IsShown() then MainWindow:Refresh() end
    return true
end

function GuideScan:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:SetScript("OnEvent", function() self:Tick() end)
    self.frame = frame
    self:Queue()
    self:Tick()
end

ns:RegisterModule("GuideScan", GuideScan)
