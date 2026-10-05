local _, ns = ...

-- Advances only NuuRoad's local progress when declared game state is observed.
-- It never calls movement, combat, targeting, quest-dialog, or reward APIs.
-- A step that waits on the player's position is checked five times a second
-- rather than once: a mount crosses the arrow's few yards of arrival in about
-- a second, and a once-a-second look can land either side of it.
local ObservedProgress = { elapsed = 0, pollInterval = 1, arrivalElapsed = 0, arrivalInterval = 0.2 }

local function expectedQuestIDs(node)
    local ids, seen = {}, {}
    local function add(list)
        for _, id in ipairs(type(list) == "table" and list or {}) do
            if type(id) == "number" and not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
    end
    if node and node.completion and node.completion.type == "observed" and node.completion.observed then
        add(node.completion.observed.ids)
    end
    if node and node.refs then add(node.refs.quests) end
    return ids, seen
end

local function describeQuest(questID)
    local title = ns.modules.Client:GetQuestTitle(questID)
    return tostring(questID) .. (title and (" '" .. title .. "'") or " (title unknown to client)")
end

-- Debug aid for porting: when the client reports a quest event whose ID is not
-- one the current step expects, say so, with titles where the client has them.
function ObservedProgress:CheckQuestEvent(event, questID)
    if not ns.modules.Config:Get("debug") or type(questID) ~= "number" then return end
    local guide = ns.modules.Progress:GetActiveGuide()
    if not guide then return end
    local node = ns.modules.Progress:GetCurrentNode(guide)
    if not node then return end
    local ids, seen = expectedQuestIDs(node)
    if #ids == 0 or seen[questID] then return end
    local expected = {}
    for _, id in ipairs(ids) do table.insert(expected, describeQuest(id)) end
    ns:Log(event .. " reported quest " .. describeQuest(questID) .. " but step '" .. ns.modules.Steps:Title(node) .. "' expects " .. table.concat(expected, ", "))
end

-- A quest picked up or handed in out of order. The client already says that
-- a quest was accepted or turned in, so the chat line says only the part it
-- cannot: the guide wants this one later, and where the player stands now.
local aheadWords = {
    QUEST_ACCEPTED = { role = "accept", asks = "picks up" },
    QUEST_TURNED_IN = { role = "turnin", asks = "hands in" },
}

-- The message for a quest the active guide accepts or turns in at a step the
-- player has not reached yet, or nil when there is nothing to say: the guide
-- does not do that with the quest, the step is the one they are on or one
-- carried alongside it in the current group, or it is already behind them.
function ObservedProgress:AheadOfStepMessage(guide, currentIndex, event, questID)
    local words = aheadWords[event]
    if not words or type(questID) ~= "number" or not guide or not currentIndex then return nil end
    local QuestIndex = ns.modules.QuestIndex
    if not QuestIndex then return nil end
    -- Steps carried with the current one are on the step card already.
    local group = ns.modules.Schema:GroupAt(guide, currentIndex)
    local last = group and group.last or currentIndex
    local ahead
    for _, entry in ipairs(QuestIndex:GuidesFor(questID)) do
        if entry.guide.id == guide.id then
            for _, step in ipairs(entry.steps or {}) do
                if step.role == words.role then
                    if step.index <= last then return nil end
                    if not ahead or step.index < ahead then ahead = step.index end
                end
            end
        end
    end
    if not ahead then return nil end
    return "Out of order: the guide " .. words.asks .. " " .. ns.modules.Names:DescribeQuest(questID)
        .. " at step " .. tostring(ahead) .. ", and you are on step " .. tostring(currentIndex) .. "."
end

function ObservedProgress:AnnounceAheadQuest(event, questID)
    local Progress = ns.modules.Progress
    local guide = Progress and Progress:GetActiveGuide()
    if not guide then return end
    local message = self:AheadOfStepMessage(guide, Progress:GetCurrentIndex(guide), event, questID)
    if message then ns:Print(message) end
end

function ObservedProgress:LogStepExpectations(node)
    if not ns.modules.Config:Get("debug") or not node then return end
    local ids = expectedQuestIDs(node)
    if #ids == 0 then return end
    local described = {}
    for _, id in ipairs(ids) do table.insert(described, describeQuest(id)) end
    ns:Log("Step '" .. ns.modules.Steps:Title(node) .. "' expects quest " .. table.concat(described, ", "))
end

-- "New flight path discovered!" names nothing, so it is credited to the flight
-- path the current step is asking for.
function ObservedProgress:CheckFlightPathMessage(message)
    local expected = _G.ERR_NEWTAXIPATH
    if type(message) ~= "string" or (expected and message ~= expected) then return end
    if not expected and not message:lower():find("flight path") then return end
    local guide = ns.modules.Progress:GetActiveGuide()
    local node = guide and ns.modules.Progress:GetCurrentNode(guide)
    local observed = node and node.completion and node.completion.observed
    if observed and observed.type == "flightpath" then ns.modules.Client:RecordFlightPath(observed.name) end
end

-- "You create: [Rough Sharpening Stone]" is the only word the client gives
-- that a craft happened, so crafts are counted from the loot message and
-- credited to the current step when it is asking for that item. Like kills,
-- nothing made before the player reached the step counts.
function ObservedProgress:CheckCraftMessage(message)
    if type(message) ~= "string" then return end
    -- The client's own wording up to the item link ("You create: "), so the
    -- locale decides and a "You receive loot:" line is never taken for a craft.
    local created = _G.LOOT_ITEM_CREATED_SELF
    local prefix = type(created) == "string" and created:match("^(.-)%%s") or "You create"
    if prefix == "" or message:sub(1, #prefix) ~= prefix then return end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    if not itemID then return end
    -- The profession planner (NuuProfessions) reads the same line itself for
    -- its own goals; nothing here passes it on.
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    local node = guide and Progress:GetCurrentNode(guide)
    local observed = node and node.completion and node.completion.observed
    if not observed or observed.type ~= "crafted" or observed.itemID ~= itemID then return end
    Progress:RecordCraft(guide, node.index)
end

-- The spell a step asks to be cast, whether it is the step's own completion
-- or one child of it (a carried step is done by its own work or its owner's).
local function castObserved(observed)
    if type(observed) ~= "table" then return nil end
    if observed.type == "cast" then return observed end
    for _, child in ipairs(observed.children or {}) do
        local found = castObserved(child)
        if found then return found end
    end
    return nil
end

-- UNIT_SPELLCAST_SUCCEEDED ("player", castGUID, spellID): a cast of the spell
-- the current step asks for counts on that step. Casts before the step was
-- reached do not, like kills. A secret spell ID reads as no cast at all.
-- True when the cast counted.
function ObservedProgress:CheckSpellCast(unit, ...)
    if unit ~= "player" then return false end
    local Client = ns.modules.Client
    local spellID
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "number" and not (Client.IsSecret and Client:IsSecret(value)) then spellID = value end
    end
    if not spellID then return false end
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    local node = guide and Progress:GetCurrentNode(guide)
    local observed = node and node.completion and castObserved(node.completion.observed)
    if not observed or observed.spellID ~= spellID then return false end
    local count = Progress:RecordCast(guide, node.index)
    ns:Record("guide", { event = "cast", guide = guide.id, step = node.index, spell = spellID, count = count })
    return true
end

-- A step held by a plain BACK, SKIP or jump is not walked past while it reads
-- done, moot, or passed over. The moment it reads incomplete the hold has nothing left to guard,
-- so it lapses and finishing the step advances the guide as usual, unpausing
-- as soon as the step it paused on is no longer complete.
function ObservedProgress:LapseHold()
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    if not guide or not Progress:IsHeld(guide) then return end
    local node = Progress:GetCurrentNode(guide)
    if not node then return end
    local observed = node.completion and node.completion.type == "observed" and node.completion.observed
    if observed and ns.modules.Client:MatchesObservedCompletion(observed, node.location, node.index) then return end
    -- A travel or a note the flow would pass over reads done for the hold too,
    -- or BACK onto one would be undone at once.
    if self.PassedTo and self:PassedTo(guide, node) then return end
    -- So does a step whose condition no longer holds ("now gold 150" after
    -- training): the flow would pass it over, and the player picked it anyway.
    if Progress:IsBypassed(node) then return end
    Progress:Release(guide)
end

function ObservedProgress:CurrentNodeIsComplete()
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    if not guide or Progress:IsHeld(guide) then return nil end
    local node = Progress:GetCurrentNode(guide)
    if not node or not node.completion or node.completion.type ~= "observed" then return nil end
    return guide, node, ns.modules.Client:MatchesObservedCompletion(node.completion.observed, node.location, node.index)
end

-- A step the player is on whose condition has since become one that can
-- never hold ("not quest 858" and the quest was just taken elsewhere). It is
-- recorded as skipped, never as complete. A step whose quest the player never
-- took, or one still waiting on a quest or a level, is not passed over: the
-- guide waits on it until the player picks the quest up or presses SKIP.
function ObservedProgress:CurrentNodeIsBypassed()
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    if not guide or Progress:IsHeld(guide) then return nil end
    local node = Progress:GetCurrentNode(guide)
    if not node or not Progress:IsBypassed(node) then return nil end
    return guide, node
end

-- Travel and notes lead to the step after them. Once that step is done the
-- player got there, so the travel and the note have nothing left to say and
-- are passed over, recorded as skipped. A run of them is looked through to
-- the first real step. Only quest work proves the visit: an accept, a
-- turn-in, or an objective. A hearth binding, a known flight path, a level,
-- or items in the bags can be older than this trip, and a quest the player
-- never took proves nothing at all.
local passable = { travel = true, note = true }

-- A step that hands one quest in and takes the next has both under an `all`:
-- any quest part of it proves the visit, since all of it has to be done. An
-- `any` proves it only when every way of finishing it is quest work.
local function provesVisit(observed)
    if type(observed) ~= "table" then return false end
    if observed.type == "quests" or observed.type == "objective" then return true end
    local children = observed.children or {}
    if observed.type == "all" then
        for _, child in ipairs(children) do
            if provesVisit(child) then return true end
        end
    elseif observed.type == "any" and #children > 0 then
        for _, child in ipairs(children) do
            if not provesVisit(child) then return false end
        end
        return true
    end
    return false
end

-- The done quest step a travel or note leads to, or nil.
function ObservedProgress:PassedTo(guide, node)
    local Progress, GuideScan = ns.modules.Progress, ns.modules.GuideScan
    if not guide or not node or not GuideScan or not passable[node.kind] then return nil end
    local function proves(candidate)
        local observed = candidate.completion and candidate.completion.type == "observed" and candidate.completion.observed
        return provesVisit(observed) and not GuideScan:NodeIsMoot(candidate) and GuideScan:NodeCompleted(candidate)
    end
    -- The walk is the flow's, except that a step gated out because its quest
    -- was already handed in (an optional turn-in, passed unless the quest is
    -- ready) still proves
    -- the visit: the player did it out of order, and the travel to it has
    -- nothing left to lead to.
    local ahead, cursor = node, node
    for _ = 1, #guide.nodes do
        local following = guide.nodes[cursor["next"] or cursor.index + 1]
        if not following then return nil end
        cursor = following
        if not Progress:IsCarried(following) then
            if not Progress:IsBypassed(following) then
                ahead = following
                if not passable[ahead.kind] then break end
            elseif proves(following) then
                return following
            end
        end
    end
    if ahead == node or passable[ahead.kind] then return nil end
    return proves(ahead) and ahead or nil
end

function ObservedProgress:CurrentNodeIsPassed()
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    if not guide or Progress:IsHeld(guide) then return nil end
    local node = Progress:GetCurrentNode(guide)
    local ahead = self:PassedTo(guide, node)
    if not ahead then return nil end
    return guide, node, ahead
end

-- The members of the current quest group past the first that the game now
-- reports done are credited where they stand, so a quest picked up or handed
-- in ahead of its turn checks off on the step card at once. Returns true when
-- any was newly recorded. The pointer is not moved: the ordinary flow walks
-- through them once the leading steps are done.
function ObservedProgress:RecordGroupMembers()
    local Progress, Client = ns.modules.Progress, ns.modules.Client
    local guide = Progress:GetActiveGuide()
    if not guide then return false end
    local group = Progress:QuestGroup(guide)
    local recorded = false
    for index = 2, #group do
        local node = group[index]
        local observed = node.completion and node.completion.type == "observed" and node.completion.observed
        if observed and Client:MatchesObservedCompletion(observed, node.location, node.index) and Progress:Record(guide, node.index, "observed") then
            ns:Log("Observed completion of step '" .. ns.modules.Steps:Title(node) .. "' ahead of its turn")
            recorded = true
        end
    end
    return recorded
end

-- What Shift-BACK and Shift-SKIP walk past: a step the game reports done
-- right now (a quest, the player's position, a kill count), or one settled by
-- proven work after it. A step with no quest to do, or one waiting on a quest
-- or a level, stops the walk: it is not done, only not open. What the player's own
-- progress recorded earlier does not count: a quest abandoned since is
-- outstanding again, whatever the record says.
function ObservedProgress:StepReadsDone(guide, node)
    if not node then return false end
    local GuideScan, Client = ns.modules.GuideScan, ns.modules.Client
    local observed = node.completion and node.completion.type == "observed" and node.completion.observed
    if observed and Client and Client.MatchesObservedCompletion and Client:MatchesObservedCompletion(observed, node.location, node.index) then return true end
    if not GuideScan then return false end
    return GuideScan:NodeCompleted(node) or GuideScan:Settled(guide, node)
end

-- Shift-SKIP: one step forward, then on past every step that reads done, to
-- the first still to do or the end of the guide. Nothing is held. A step
-- passed because the game reports it done is recorded as observed; one
-- passed as settled is recorded as skipped, the same as plain SKIP.
function ObservedProgress:SkipToOutstanding(guide)
    local Progress = ns.modules.Progress
    if not Progress:Forward(guide, true) then return false end
    local nodeMap = guide.nodes
    for _ = 1, #guide.nodes do
        local node = nodeMap[Progress:GetState(guide).currentStep]
        if not node or not self:StepReadsDone(guide, node) then break end
        local state = Progress:GetState(guide)
        local observed = node.completion and node.completion.type == "observed" and node.completion.observed
        local proven = Progress:IsDone(state.statuses[node.index])
            or (observed and ns.modules.Client:MatchesObservedCompletion(observed, node.location, node.index))
            or (ns.modules.GuideScan and ns.modules.GuideScan:NodeCompleted(node))
        local ok
        if proven then ok = Progress:Complete(guide, nil, "observed") else ok = Progress:Forward(guide, true) end
        if not ok then break end
    end
    return true
end

-- Shift-BACK: one step back along the trail, then on back past every step
-- that reads done, to the first still to do or the start of the trail.
-- Nothing is held, so a done step landed on at the start of the trail flows
-- forward again on its own.
function ObservedProgress:BackToOutstanding(guide)
    local Progress = ns.modules.Progress
    if not Progress:Back(guide, true) then return false end
    local nodeMap = guide.nodes
    for _ = 1, #guide.nodes do
        local node = nodeMap[Progress:GetState(guide).currentStep]
        if not node or not self:StepReadsDone(guide, node) then break end
        if not Progress:Back(guide, true) then break end
    end
    return true
end

-- Returns true when progress advanced. The UI is refreshed only in that case.
local function observesLocation(observed)
    if type(observed) ~= "table" then return false end
    if observed.type == "location" then return true end
    for _, child in ipairs(observed.children or {}) do
        if observesLocation(child) then return true end
    end
    return false
end

-- The quick check between full refreshes: only a current step completed by
-- arrival is looked at, and the full refresh runs once it reads done.
function ObservedProgress:CheckArrival()
    local Progress = ns.modules.Progress
    local guide = Progress:GetActiveGuide()
    if not guide or Progress:IsHeld(guide) then return false end
    local node = Progress:GetCurrentNode(guide)
    local observed = node and node.completion and node.completion.type == "observed" and node.completion.observed
    if not observesLocation(observed) then return false end
    if not ns.modules.Client:MatchesObservedCompletion(observed, node.location, node.index) then return false end
    return self:Refresh("arrival")
end

-- `cause` is what made the flow look (an event name, "poll", "arrival"); it
-- goes on the step-state record with every move made and why
-- (`Domain/StepState.lua`).
function ObservedProgress:Refresh(cause)
    local Progress = ns.modules.Progress
    self:LapseHold()
    local advanced = self:RecordGroupMembers()
    local moves = {}
    local function moved(guide, node, why)
        table.insert(moves, { from = node.index, to = Progress:GetState(guide).currentStep, why = why })
    end
    -- A bounded loop permits informational nodes to flow into the next observed task.
    for _ = 1, 24 do
        local guide, node, complete = self:CurrentNodeIsComplete()
        if guide and complete then
            if not Progress:Complete(guide, nil, "observed") then break end
            moved(guide, node, "observed")
            ns:Log("Observed completion of step '" .. ns.modules.Steps:Title(node) .. "'")
        else
            local ahead
            guide, node = self:CurrentNodeIsBypassed()
            if guide then
                if not Progress:Complete(guide, nil, "skipped") then break end
                moved(guide, node, "bypassed: " .. tostring(ns.modules.Steps:DescribeCondition(node.condition)))
                ns:Log("Passed over step '" .. ns.modules.Steps:Title(node) .. "': its condition can no longer hold")
            else
                guide, node, ahead = self:CurrentNodeIsPassed()
                if not guide then break end
                if not Progress:Complete(guide, nil, "skipped") then break end
                moved(guide, node, "passed: #" .. ahead.index .. " is done")
                ns:Log("Passed over step '" .. ns.modules.Steps:Title(node) .. "': '" .. ns.modules.Steps:Title(ahead) .. "' after it is done")
            end
        end
        advanced = true
        self:LogStepExpectations((Progress:GetCurrentNode(guide)))
    end
    local StepState = ns.modules.StepState
    if StepState then pcall(StepState.Observe, StepState, cause or "refresh", moves) end
    if advanced then
        local MainWindow = ns.modules.MainWindow
        if MainWindow and MainWindow.frame and MainWindow.frame:IsShown() then MainWindow:Refresh() end
    end
    return advanced
end

function ObservedProgress:Initialize()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
        "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
        "TAXIMAP_OPENED", "UI_INFO_MESSAGE", "BAG_UPDATE_DELAYED", "HEARTHSTONE_BOUND",
        "CHAT_MSG_LOOT", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "PLAYER_EQUIPMENT_CHANGED",
    }) do
        frame:RegisterEvent(event)
    end
    -- Experience moves the level goal's count; a kill's chat line says what
    -- the kill was worth. Guarded, as a client without them is still playable.
    pcall(frame.RegisterEvent, frame, "PLAYER_XP_UPDATE")
    pcall(frame.RegisterEvent, frame, "CHAT_MSG_COMBAT_XP_GAIN")
    -- A quest's offer and its reward window say what it gives, which a level
    -- step counting the turn-ins ahead of it reads (Domain/Experience.lua).
    pcall(frame.RegisterEvent, frame, "QUEST_DETAIL")
    pcall(frame.RegisterEvent, frame, "QUEST_COMPLETE")
    -- A spell cast on a cast step, and a spell learned at a trainer. The cast
    -- is a unit event, not the combat log; the hearth recorder already reads
    -- it on Forever.
    ns.modules.Client:RegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_TAB")
    pcall(frame.RegisterEvent, frame, "SPELLS_CHANGED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "QUEST_ACCEPTED" then
            -- Classic passes (questLogIndex, questID); newer clients pass (questID).
            local questID = select(select("#", ...), ...)
            self:CheckQuestEvent(event, questID)
            self:AnnounceAheadQuest(event, questID)
        elseif event == "QUEST_TURNED_IN" then
            local Experience = ns.modules.Experience
            if Experience then Experience:LearnQuestXP(...) end
            self:CheckQuestEvent(event, (...))
            self:AnnounceAheadQuest(event, (...))
        elseif event == "TAXIMAP_OPENED" then
            ns.modules.Client:RecordFlightPathsFromTaxiMap()
        elseif event == "UI_INFO_MESSAGE" then
            self:CheckFlightPathMessage(select(2, ...))
        elseif event == "CHAT_MSG_LOOT" then
            self:CheckCraftMessage((...))
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Every cast in a fight lands here; only the step's own spell
            -- is worth a refresh.
            if not self:CheckSpellCast(...) then return end
        elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
            local Client, Experience = ns.modules.Client, ns.modules.Experience
            if Experience then Experience:LearnQuestXP(Client:GetOpenQuestID(), Client:GetOpenQuestRewardXP()) end
        elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
            local Experience = ns.modules.Experience
            if Experience then Experience:OnMessage((...)) end
        end
        -- Even when nothing advanced, the state the tracker paints may have
        -- moved: a quest finished out of order checks off a step further down
        -- the guide and lights its band on the progress bar.
        if not self:Refresh(event) and ns.modules.MainWindow then ns.modules.MainWindow:RequestRefresh() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        self.elapsed = self.elapsed + elapsed
        self.arrivalElapsed = self.arrivalElapsed + elapsed
        if self.elapsed >= self.pollInterval then
            self.elapsed, self.arrivalElapsed = 0, 0
            self:Refresh("poll")
        elseif self.arrivalElapsed >= self.arrivalInterval then
            self.arrivalElapsed = 0
            self:CheckArrival()
        end
    end)
    self.frame = frame
    self:Refresh("login")
end

ns:RegisterModule("ObservedProgress", ObservedProgress)
