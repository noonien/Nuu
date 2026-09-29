local _, ns = ...

local Progress = { schemaVersion = 1, session = {} }

local function newState(guide)
    ns.modules.Schema:IndexNodes(guide)
    -- `trail` is the ordered list of step indexes the player has moved past; Back
    -- walks it. `holdStep` pauses observed auto-advance on a node the player
    -- navigated to by hand (Back or Forward), until they leave it again.
    return { schemaVersion = Progress.schemaVersion, statuses = {}, trail = {}, currentStep = guide.nodes[1].index }
end

function Progress:Initialize()
    -- Saved per character: the active guide and the flight paths learned.
    self.store = ns.modules.Config:CharacterStore()
    -- Guide progress is deliberately not saved. It lives for the session only,
    -- and the load-time scan places the player afresh at every login from what
    -- the client still knows. Progress an earlier version saved is dropped.
    self.store.guides = nil
    self.session = {}
    -- No guide is chosen for the player. A login that recovers none opens on
    -- the empty tracker, which asks them to pick one: a guessed guide is a
    -- route nobody asked for, on a character it may not even be written for.
    local step = self:ResumeStep()
    if step then
        -- The step the player was on at logout. The login scan still walks
        -- forward from it as the quest log arrives.
        local guide = self:GetActiveGuide()
        if self:LandOn(guide, step) then
            ns:Log("resuming '" .. guide.meta.title .. "' at step " .. step)
        end
    end
    if CreateFrame then
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_LOGOUT")
        frame:SetScript("OnEvent", function() self:SaveResume() end)
        self.frame = frame
    end
    ns:Log("progress store for " .. tostring(ns.modules.Config.characterKey) .. ": active guide " .. tostring(self.store.activeGuideID))
end

-- The one piece of progress that is saved: the active guide's current step,
-- stamped with the guide's `updated` so a guide edited since cannot hand back
-- a position that now means another step. Everything else about progress is
-- rebuilt by the login scan.
function Progress:SaveResume()
    local guide = self.store and self:GetActiveGuide()
    local state = guide and self:PeekState(guide)
    if not state or type(state.currentStep) ~= "number" then
        if self.store then self.store.resume = nil end
        return
    end
    self.store.resume = { guideID = guide.id, step = state.currentStep, updated = guide.updated }
end

-- The saved step to resume the active guide at, or nil when there is none or
-- it no longer fits the guide.
function Progress:ResumeStep()
    local resume, guide = self.store.resume, self.store.activeGuideID and self:GetActiveGuide()
    if type(resume) ~= "table" or not guide or resume.guideID ~= guide.id or resume.updated ~= guide.updated then return nil end
    local step = resume.step
    if type(step) ~= "number" or step % 1 ~= 0 or step <= 1 or step > #guide.nodes then return nil end
    return step
end

-- Moves a guide still on its first step ahead to the step at `index` (1-based
-- position in the node list), recording the earlier steps as skipped so Back
-- still walks them. The landed step is not held, so observed progress may
-- move on from it. False when the guide has already moved or the index is
-- out of range.
--
-- The step asked for is not always one the flow stops on: it can be gated out
-- for this character, carried alongside another step, or off the branch the
-- guide takes - and at login a quest gate reads false until the client hands
-- over the quest log. So the walk is worked out first and the guide lands on
-- the first step at or past the one asked for that the flow really reaches.
-- Without that the search for a step that never comes walked the pointer off
-- the end of the guide, which read as having finished it.
function Progress:LandOn(guide, index)
    local state = self:GetState(guide)
    local target = guide.nodes[index or 1]
    if not target or state.currentStep ~= guide.nodes[1].index then return false end
    local landing, cursor = nil, state.currentStep
    for _ = 1, #guide.nodes do
        if not cursor then break end
        if cursor >= target.index then landing = cursor break end
        cursor = self:NextIndex(guide, guide.nodes[cursor])
    end
    if not landing then return false end
    for _ = 1, #guide.nodes do
        if not state.currentStep or state.currentStep >= landing then break end
        if not self:Forward(guide, true) then break end
    end
    return state.currentStep == landing
end

-- The current step's 1-based position in the node list, or nil past the end.
function Progress:GetCurrentIndex(guide)
    return self:GetState(guide).currentStep
end

-- Read-only lookup: never creates a state entry for guides the player has not used.
function Progress:PeekState(guide)
    return self.session[guide.id]
end

function Progress:GetState(guide)
    local state = self.session[guide.id]
    if not state then
        state = newState(guide)
        self.session[guide.id] = state
    end
    return state
end

function Progress:Select(guide)
    self.store.activeGuideID = guide.id
    local state = self:GetState(guide)
    state.holdStep = nil
    self:SkipUnavailable(guide)
    -- Loading a guide scans it for work the player has already done, so a guide
    -- picked up mid-zone opens on the first step that is still outstanding.
    local GuideScan = ns.modules.GuideScan
    if GuideScan then
        GuideScan:Queue()
        GuideScan:Apply(guide)
    end
    return state
end

function Progress:GetActiveGuide()
    if not self.store.activeGuideID then return nil end
    local guide = ns.modules.GuideRepository:Get(self.store.activeGuideID)
    if not guide and not self.warnedMissing then
        self.warnedMissing = true
        ns:Log("active guide '" .. tostring(self.store.activeGuideID) .. "' is not in the repository")
    end
    return guide
end

function Progress:GetCurrentNode(guide)
    local state = self:GetState(guide)
    return guide.nodes[state.currentStep], state
end

function Progress:IsHeld(guide)
    local state = self:GetState(guide)
    return state.holdStep ~= nil and state.holdStep == state.currentStep
end

function Progress:IsDone(status)
    return status == "complete" or status == "observed"
end

function Progress:CompletedCount(state)
    local count = 0
    for _, status in pairs(state and state.statuses or {}) do
        if self:IsDone(status) then count = count + 1 end
    end
    return count
end

local function orderedNext(guide, index)
    return index and guide.nodes[index + 1] and index + 1 or nil
end

-- A step the guide never stops on: it rides along with a later step
-- (`companionOf`) or stays up alongside the steps after it until it is done
-- (`sticky`). The tracker draws these under the step they belong to;
-- the ordered flow walks past them, because stopping on one would ask the
-- player to finish something the guide has not reached the point of yet.
function Progress:IsCarried(node)
    return node ~= nil and (node.companionOf ~= nil or node.sticky == true)
end

-- The carried steps to draw with `node`: the ones explicitly carried alongside
-- it, then any sticky step earlier in the guide that is still outstanding.
-- The flow never stops on a sticky step, so nothing records it as done: once
-- the game shows its work finished (seven kills of seven) it leaves the card
-- on that evidence.
function Progress:Carried(guide, node)
    if not guide or not node then return {} end
    local state, carried = self:PeekState(guide), {}
    local statuses = state and state.statuses or {}
    local GuideScan = ns.modules.GuideScan
    for _, candidate in ipairs(guide.nodes) do
        local show = false
        if candidate.companionOf == node.index then
            show = true
        elseif candidate.sticky and candidate.index < node.index and not self:IsDone(statuses[candidate.index])
            and not (GuideScan and GuideScan:NodeCompleted(candidate)) then
            show = true
        end
        if show and self:IsAvailable(candidate) then table.insert(carried, candidate) end
    end
    return carried
end

function Progress:IsAvailable(node)
    if not node or not node.condition then return true end
    local Client = ns.modules.Client
    if not Client or not Client.MatchesCondition then return true end
    return Client:MatchesCondition(node.condition)
end

-- A step this character can never do: its condition fails on class, race,
-- faction, or realm alone. One gated on a quest or a level is not ruled out.
function Progress:IsRuledOut(node)
    if not node or not node.condition then return false end
    local Client = ns.modules.Client
    if not Client or not Client.RulesOut then return false end
    return Client:RulesOut(node.condition)
end

-- The guide as this character has it: every step not ruled out, in order, and
-- each one's number among them (by step index). The tracker counts, numbers,
-- and draws progress over these, so a step for another race or faction is not
-- a step at all.
function Progress:CharacterSteps(guide)
    local steps, numbers = {}, {}
    for _, node in ipairs(guide and guide.nodes or {}) do
        if not self:IsRuledOut(node) then
            table.insert(steps, node)
            numbers[node.index] = #steps
        end
    end
    return steps, numbers
end

-- A step whose condition can never hold for this character now: ruled out,
-- or gated by a `not` term already settled ("not quest 858" with the quest
-- taken). Nothing the player does brings it back, so the flow passes over it.
-- A step waiting on something the player can still gain - a quest, a level,
-- an item - is not passed over: the guide stops on it until it opens, or the
-- player presses SKIP.
function Progress:IsBypassed(node)
    if not node or not node.condition then return false end
    local Client = ns.modules.Client
    if not Client then return false end
    if not Client.CouldOpen then return not self:IsAvailable(node) end
    return not Client:CouldOpen(node.condition)
end

-- A step the guide stops on although its condition does not hold yet.
function Progress:IsWaiting(node)
    return not self:IsAvailable(node) and not self:IsBypassed(node)
end

-- Steps that can never open are passed over silently, in both the ordered
-- flow and the upcoming list; a step still waiting to open is stopped on.
function Progress:NextIndex(guide, node)
    if not node then return nil end
    local nodeMap = guide.nodes
    local nextIndex = node["next"] or orderedNext(guide, node.index)
    for _ = 1, #guide.nodes do
        local candidate = nodeMap[nextIndex]
        if not candidate or (not self:IsBypassed(candidate) and not self:IsCarried(candidate)) then return nextIndex end
        nextIndex = candidate["next"] or orderedNext(guide, candidate.index)
    end
    return nextIndex
end

-- Only groups authored in the guide are concurrent. Membership is an
-- inclusive range of step indexes; availability is evaluated per member.
-- A member with nothing the player can do yet -- a turn-in whose quest is not
-- in the log and was never finished -- is not in the group either: it joins
-- once the quest is accepted, which is often at another member of the same
-- group. The step the guide is on always leads, however it reads, and the
-- flow stops on a moot member when it gets there.
function Progress:IsQuestVisit(node)
    return ns.modules.Schema:IsQuestVisit(node)
end

function Progress:QuestGroup(guide, node)
    node = node or self:GetCurrentNode(guide)
    if not node then return {} end
    local group = { node }
    local range = ns.modules.Schema:GroupAt(guide, node.index)
    if not range then return group end
    local GuideScan = ns.modules.GuideScan
    for index = node.index + 1, range.last do
        local member = guide.nodes[index]
        if self:IsAvailable(member) and not (GuideScan and GuideScan:NodeIsMoot(member)) then
            table.insert(group, member)
        end
    end
    return group
end

-- Records a status on a step without moving the pointer or the trail: a
-- member of the current quest group the game reports done ahead of its turn.
-- The pointer catches up through the ordinary flow when it reaches the step.
function Progress:Record(guide, stepIndex, status)
    local state = self:GetState(guide)
    if not guide.nodes[stepIndex] then return false end
    if self:IsDone(state.statuses[stepIndex]) then return false end
    state.statuses[stepIndex] = status or "observed"
    return true
end

-- The current step can be one that never opens when a guide is opened on
-- another character; the flow then resumes at the next step it stops on.
function Progress:SkipUnavailable(guide)
    local state = self:GetState(guide)
    local node = guide.nodes[state.currentStep]
    if node and (self:IsBypassed(node) or self:IsCarried(node)) then
        state.currentStep = self:NextIndex(guide, node)
    end
end

-- Every move of the pointer goes on the session log's `guide` channel, so a
-- bug report about a step that would not advance (or advanced too soon) can
-- be read against what the flow actually did: which step, why, and where it
-- went. `how` is the status recorded, or the button (back, goto).
local function recordMove(guide, how, from, to)
    -- The next step-state row says which move it follows.
    local StepState = ns.modules.StepState
    if StepState then StepState.lastMove = how end
    if not ns.Record then return end
    ns:Record("guide", { event = "step", guide = guide.id, how = how, from = from, to = to })
end

function Progress:Complete(guide, stepIndex, status, selectedNextIndex)
    local nodeMap = guide.nodes
    local state = self:GetState(guide)
    stepIndex = stepIndex or state.currentStep
    local node = nodeMap[stepIndex]
    if not node then return false, "Unknown guide node" end
    if selectedNextIndex then
        local isChoiceEdge = false
        for _, choice in ipairs(node.choices or {}) do
            if choice["next"] == selectedNextIndex then
                isChoiceEdge = true
                break
            end
        end
        if not isChoiceEdge then return false, "That is not a valid choice for this step" end
    elseif node.kind == "choice" and #(node.choices or {}) > 0 and status ~= "skipped" then
        return false, "Choose a route before completing this step"
    end
    table.insert(state.trail, stepIndex)
    state.statuses[stepIndex] = status or "complete"
    -- Anything carried alongside this step is finished by it, which is what
    -- being carried means. A skip carries them too: the player has moved past
    -- the work either way.
    for _, candidate in ipairs(nodeMap) do
        if candidate.companionOf == stepIndex and not self:IsDone(state.statuses[candidate.index]) then
            state.statuses[candidate.index] = status == "skipped" and "skipped" or "observed"
        end
    end
    state.holdStep = nil
    state.currentStep = selectedNextIndex or self:NextIndex(guide, node)
    recordMove(guide, status or "complete", stepIndex, state.currentStep)
    self:StartLap(guide, stepIndex, state.currentStep)
    return true
end

-- A farming circuit is authored as an edge back to an earlier step, usually
-- from a choice ("another lap" / "done"). The lap only means something if the
-- steps run again, so everything from the destination through the step just
-- finished is wiped back to undone: statuses, kills, crafts, casts, and the NPCs
-- talked to. The trail is left alone, so BACK still walks the laps already
-- run. A forward edge changes nothing.
function Progress:StartLap(guide, fromIndex, toIndex)
    if type(fromIndex) ~= "number" or type(toIndex) ~= "number" or toIndex > fromIndex then return false end
    local state = self:GetState(guide)
    for index = toIndex, fromIndex do
        state.statuses[index] = nil
        if state.kills then state.kills[index] = nil end
        if state.crafts then state.crafts[index] = nil end
        if state.casts then state.casts[index] = nil end
        if state.talked then state.talked[index] = nil end
    end
    state.laps = state.laps or {}
    local lap = state.laps[toIndex] or { count = 1, last = fromIndex }
    lap.count, lap.last = lap.count + 1, math.max(lap.last, fromIndex)
    state.laps[toIndex] = lap
    return true
end

-- Which lap of the circuit starting at `stepIndex` the player is on; 1 before
-- they have gone round at all.
function Progress:LapCount(guide, stepIndex)
    local state = self:PeekState(guide)
    local lap = state and state.laps and state.laps[stepIndex]
    return lap and lap.count or 1
end

-- The lap of the circuit `stepIndex` sits inside, for the tracker to show.
-- 1 when the step is on no circuit, or on one that has not come round yet.
function Progress:CurrentLap(guide, stepIndex)
    local state = self:PeekState(guide)
    if not state or not state.laps or type(stepIndex) ~= "number" then return 1 end
    local best = 1
    for start, lap in pairs(state.laps) do
        if stepIndex >= start and stepIndex <= lap.last and lap.count > best then best = lap.count end
    end
    return best
end

-- Back moves to the step the player most recently left. Statuses are kept so
-- returning to a finished step does not erase what the player already did.
-- Like Forward, it holds the step it lands on unless `release` is set.
function Progress:Back(guide, release)
    local state = self:GetState(guide)
    local previous = table.remove(state.trail)
    if not previous then return false, "Already at the first step" end
    recordMove(guide, "back", state.currentStep, previous)
    state.currentStep = previous
    state.holdStep = not release and previous or nil
    return true
end

-- Forward is an explicit player navigation choice. A step that was already
-- finished keeps its status; anything else is recorded as skipped so observed
-- progress never represents an unobserved step as complete. A plain move holds
-- the step it lands on: one the game already reports done is not passed over
-- again on arrival, pausing on a step reached by hand. The hold
-- is not a mode. It lapses as soon as the step reads incomplete (see
-- `Release`) or the pointer moves, and `release` (a Shift move) lands
-- without it.
function Progress:Forward(guide, release)
    local state = self:GetState(guide)
    local node = guide.nodes[state.currentStep]
    if not node then return false, "Guide is complete" end
    local existing = state.statuses[node.index]
    table.insert(state.trail, node.index)
    state.statuses[node.index] = self:IsDone(existing) and existing or "skipped"
    state.currentStep = self:NextIndex(guide, node)
    -- A reminder (track, untrack) is done the moment the flow reaches it and
    -- is no stop: holding on one would show its card with no list row under
    -- it, so forward carries on past it to the next real step.
    for _ = 1, #guide.nodes do
        local landed = guide.nodes[state.currentStep]
        if not landed or landed.kind ~= "reminder" then break end
        if not self:IsDone(state.statuses[landed.index]) then state.statuses[landed.index] = "observed" end
        state.currentStep = self:NextIndex(guide, landed)
    end
    recordMove(guide, "forward", node.index, state.currentStep)
    state.holdStep = not release and state.currentStep or nil
    return true
end

-- Lets go of a hold, so the step advances on its own once done.
function Progress:Release(guide)
    local state = self:GetState(guide)
    state.holdStep = nil
end

-- A direct jump to a step the player named, in either direction. Unlike SKIP,
-- it is navigation only: no step it passes is recorded as skipped, and no
-- status is rewritten, so the progress count still means what was really done.
-- The step landed on is held the same way as after BACK or SKIP: one already
-- finished is not advanced past on arrival, and the hold lapses once the step
-- reads incomplete.
function Progress:GoTo(guide, stepIndex)
    local nodeMap = guide.nodes
    if not nodeMap[stepIndex] then return false, "Unknown guide node" end
    local state = self:GetState(guide)
    if state.currentStep ~= stepIndex then
        local unwound = false
        -- Backward: unwind the trail to that step, so BACK keeps walking from it.
        for index = #state.trail, 1, -1 do
            if state.trail[index] == stepIndex then
                for _ = index, #state.trail do table.remove(state.trail) end
                unwound = true
                break
            end
        end
        if not unwound then
            -- Forward: the steps passed over join the trail untouched, so BACK
            -- walks back through them one at a time.
            local walk, cursor = {}, state.currentStep
            for _ = 1, #guide.nodes do
                if not cursor or cursor == stepIndex then break end
                table.insert(walk, cursor)
                cursor = self:NextIndex(guide, nodeMap[cursor])
            end
            -- A step off the current flow (a branch not taken, or one gated out
            -- for this character) is reached in one move instead.
            if cursor ~= stepIndex then walk = { state.currentStep } end
            for _, id in ipairs(walk) do table.insert(state.trail, id) end
        end
    end
    recordMove(guide, "goto", state.currentStep, stepIndex)
    state.currentStep = stepIndex
    state.holdStep = stepIndex
    return true
end

-- Kills of a step's targets and NPCs the player has spoken to, recorded per
-- step by NPCTracking. They live in the guide state so they reset with it and
-- last for the session; Back and Forward leave them alone.
function Progress:KillCount(guide, stepIndex)
    local state = self:GetState(guide)
    return state.kills and state.kills[stepIndex] or 0
end

function Progress:RecordKill(guide, stepIndex)
    local state = self:GetState(guide)
    state.kills = state.kills or {}
    state.kills[stepIndex] = (state.kills[stepIndex] or 0) + 1
    return state.kills[stepIndex]
end

-- Items made on a step, counted by ObservedProgress from the client's "You
-- create:" message. Session-only, like the kill counts.
function Progress:CraftCount(guide, stepIndex)
    local state = self:GetState(guide)
    return state.crafts and state.crafts[stepIndex] or 0
end

function Progress:RecordCraft(guide, stepIndex)
    local state = self:GetState(guide)
    state.crafts = state.crafts or {}
    state.crafts[stepIndex] = (state.crafts[stepIndex] or 0) + 1
    return state.crafts[stepIndex]
end

-- Casts of a step's spell, counted by ObservedProgress from the client's
-- UNIT_SPELLCAST_SUCCEEDED. Session-only, like the kill counts.
function Progress:CastCount(guide, stepIndex)
    local state = self:GetState(guide)
    return state.casts and state.casts[stepIndex] or 0
end

function Progress:RecordCast(guide, stepIndex)
    local state = self:GetState(guide)
    state.casts = state.casts or {}
    state.casts[stepIndex] = (state.casts[stepIndex] or 0) + 1
    return state.casts[stepIndex]
end

function Progress:HasTalked(guide, stepIndex, npcID)
    local state = self:GetState(guide)
    return state.talked ~= nil and state.talked[stepIndex] ~= nil and state.talked[stepIndex][npcID] == true
end

function Progress:RecordTalk(guide, stepIndex, npcID)
    local state = self:GetState(guide)
    state.talked = state.talked or {}
    state.talked[stepIndex] = state.talked[stepIndex] or {}
    if state.talked[stepIndex][npcID] then return false end
    state.talked[stepIndex][npcID] = true
    return true
end

-- The tracker follows no guide: it asks for one, as at a login that recovers
-- none. The session's progress on the guide it left is kept.
function Progress:Deselect()
    if not self.store then return end
    self.store.activeGuideID = nil
    self.store.resume = nil
end

-- What a step is, apart from where it sits: its kind and what it names (the
-- item, skill, rank, vendor), not its count, which a rebuilt guide revises as
-- the player buys and crafts. The same step twice in one guide is told apart
-- by which time it comes.
local IDENTITY = { "verb", "item", "skill", "rank", "vendor", "name", "level", "faction", "action", "label" }

local function identity(node)
    local parts = { tostring(node.kind) }
    local auto = type(node.auto) == "table" and node.auto or nil
    if auto then
        for _, key in ipairs(IDENTITY) do
            local value = auto[key]
            if value ~= nil and type(value) ~= "table" then table.insert(parts, key .. "=" .. tostring(value)) end
        end
    else
        table.insert(parts, tostring(node.title))
        table.insert(parts, tostring(node.body))
    end
    return table.concat(parts, "|")
end

local function identities(guide)
    local keys, seen = {}, {}
    for index, node in ipairs(guide.nodes) do
        local key = identity(node)
        seen[key] = (seen[key] or 0) + 1
        keys[index] = key .. "#" .. seen[key]
    end
    return keys
end

-- A guide rebuilt under the same ID (a session guide built again while the
-- tracker follows it) keeps the progress made on the steps it
-- still has: their statuses, kills, crafts and talks, the trail through them,
-- and the step the player is on. A step that is gone takes its progress with
-- it; with the current step gone, the player lands on the first step not yet
-- done or skipped. Nothing is observed here: the load-time scan still runs
-- when the guide is selected.
function Progress:Carry(old, new)
    local before = old and self.session[old.id]
    local state = newState(new)
    self.session[new.id] = state
    if not before then return state end
    local oldKeys, newIndex = identities(old), {}
    for index, key in ipairs(identities(new)) do newIndex[key] = index end
    local function map(index)
        local key = type(index) == "number" and oldKeys[index]
        return key and newIndex[key] or nil
    end
    for index, status in pairs(before.statuses or {}) do
        local to = map(index)
        if to then state.statuses[to] = status end
    end
    for _, field in ipairs({ "kills", "crafts", "casts", "talked" }) do
        for index, value in pairs(before[field] or {}) do
            local to = map(index)
            if to then
                state[field] = state[field] or {}
                state[field][to] = value
            end
        end
    end
    for _, index in ipairs(before.trail or {}) do
        local to = map(index)
        if to then table.insert(state.trail, to) end
    end
    local current = map(before.currentStep)
    if not current then
        for index = 1, #new.nodes do
            local status = state.statuses[index]
            if not self:IsDone(status) and status ~= "skipped" then current = index break end
        end
    end
    state.currentStep = current or new.nodes[1].index
    state.holdStep = before.holdStep and map(before.holdStep) or nil
    return state
end

function Progress:Reset(guide)
    self.session[guide.id] = newState(guide)
    self:SkipUnavailable(guide)
    -- Reset means "run it again", so the load-time scan does not undo it.
    if ns.modules.GuideScan then ns.modules.GuideScan:Cancel() end
end

ns:RegisterModule("Progress", Progress)
