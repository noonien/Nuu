_G = _G or _ENV
local ns = { modules = {}, db = { settings = {} }, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log(message) table.insert(self.logs, message) end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/QuestIndex.lua")
Load(ns, "Domain/ObservedProgress.lua")
local Steps, Progress, ObservedProgress = ns.modules.Steps, ns.modules.Progress, ns.modules.ObservedProgress

-- Members of a quest group the game reports done are credited where they
-- stand; the pointer moves only through the leading steps.
local guide = Steps:Expand({
    schema = 2, id = "test:observed", updated = 1789862400, map = 1413, meta = { title = "Observed", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { group = {
        { accept = 870, npc = 3448 },
        { accept = 869, npc = 3464 },
        { accept = 871, npc = 3429 },
        } },
        { objectives = 870 },
    } },
},
})
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }
Progress:Select(guide)
local log = {}
ns.modules.Client = {
    IsQuestInLog = function(_, id) return log[id] == true end,
    IsQuestComplete = function() return false end,
    IsQuestReadyToTurnIn = function() return false end,
    GetQuestTitle = function() return nil end,
    MatchesObservedCompletion = function(self, observed)
        if observed.type ~= "quests" or observed.state ~= "acceptedOrFinished" then return false end
        for _, id in ipairs(observed.ids) do if not log[id] then return false end end
        return true
    end,
}

assert(not ObservedProgress:Refresh(), "nothing in the log, nothing moves")
log[871] = true
assert(ObservedProgress:Refresh(), "a later member done is a change worth painting")
local state = Progress:GetState(guide)
assert(state.statuses[3] == "observed" and (Progress:GetCurrentNode(guide)).index == 1, "recorded in place, pointer unmoved")
assert(not ObservedProgress:Refresh(), "and only once")
log[870] = true
assert(ObservedProgress:Refresh())
assert((Progress:GetCurrentNode(guide)).index == 2, "the leading step done moves the pointer to the next outstanding one")
log[869] = true
assert(ObservedProgress:Refresh())
assert((Progress:GetCurrentNode(guide)).index == 4, "the flow walks through the member recorded earlier")
assert(#state.trail == 3, "each step joins the trail once")
-- Plain BACK holds a done step it lands on: the guide stays put.
assert(Progress:Back(guide) and (Progress:GetCurrentNode(guide)).index == 3)
assert(not ObservedProgress:Refresh() and (Progress:GetCurrentNode(guide)).index == 3, "back onto a done step stays there")

-- Shift-BACK walks back past every done step to the first still to do, or
-- the start of the trail, and holds nothing; from there the flow resumes.
assert(ObservedProgress:BackToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 1, "all done: back to the start")
assert(not Progress:IsHeld(guide))
assert(ObservedProgress:Refresh() and (Progress:GetCurrentNode(guide)).index == 4, "and the flow walks forward again")
log[869] = nil
assert(ObservedProgress:BackToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 2, "Shift-BACK stops on the first step no longer done")
assert(ObservedProgress:SkipToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 4, "Shift-SKIP moves one step, then past nothing outstanding")
assert(state.statuses[2] == "observed", "a step passed by Shift-SKIP keeps the status it already had")
log[869] = true
assert(ObservedProgress:BackToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 1)
state.statuses[2] = nil
assert(ObservedProgress:SkipToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 4, "Shift-SKIP walks past the done steps")
assert(state.statuses[2] == "observed", "a step passed because the game reports it done is recorded as observed")

-- Plain SKIP holds the step it lands on only while that step reads done. The
-- hold lapses the moment the step reads incomplete, so finishing it later
-- advances the guide as usual, and the group is credited meanwhile.
assert(ObservedProgress:BackToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 1)
assert(Progress:Forward(guide) and Progress:IsHeld(guide) and (Progress:GetCurrentNode(guide)).index == 2)
assert(not ObservedProgress:Refresh() and (Progress:GetCurrentNode(guide)).index == 2, "a done step landed on by plain SKIP is not passed over")
log[869] = nil
state.statuses[3] = nil
assert(ObservedProgress:Refresh() and state.statuses[3] == "observed", "a later member is still credited on a held step")
assert(not Progress:IsHeld(guide), "and the hold lapses once the step reads incomplete")
log[869] = true
assert(ObservedProgress:Refresh() and (Progress:GetCurrentNode(guide)).index == 4, "doing the step then advances the guide")

-- The hold is judged the moment a step is landed on: one still to do is not
-- held at all, one already done is, until it reads incomplete.
assert(ObservedProgress:BackToOutstanding(guide) and (Progress:GetCurrentNode(guide)).index == 1)
log[869] = nil
assert(Progress:Forward(guide) and Progress:IsHeld(guide) and (Progress:GetCurrentNode(guide)).index == 2)
ObservedProgress:LapseHold()
assert(not Progress:IsHeld(guide), "landing on a step still to do drops the hold at once")
log[869] = true
assert(ObservedProgress:Refresh() and (Progress:GetCurrentNode(guide)).index == 4, "so finishing it continues the guide")
assert(Progress:Back(guide) and Progress:IsHeld(guide))
ObservedProgress:LapseHold()
assert(Progress:IsHeld(guide), "landing on a done step keeps it")

-- A step jumped to whose condition no longer holds (bought water gated on
-- "now gold 150", jumped back to after training) keeps its hold: the flow
-- would pass it over and walk on through every done step after it.
local gated = Steps:Expand({
    schema = 2, id = "test:gated", updated = 1789862400, map = 1413, meta = { title = "Gated", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { buy = 159, count = 20, npc = 2115, only = "now gold 150" },
        { accept = 870, npc = 3448 },
        { accept = 869, npc = 3464 },
        { accept = 872, npc = 3429 },
    } },
},
})
ns.modules.GuideRepository = { Get = function(_, id) return id == gated.id and gated or nil end }
local client = ns.modules.Client
client.CouldOpen = function(_, predicate) return predicate.type ~= "now" end
client.MatchesCondition = function(_, predicate) return predicate.type ~= "now" end
Progress:Select(gated)
assert((Progress:GetCurrentNode(gated)).index == 2, "the gated step is passed over by the flow")
assert(ObservedProgress:Refresh() and (Progress:GetCurrentNode(gated)).index == 4, "and the done steps after it, to the first still to do")
assert(Progress:GoTo(gated, 1))
ObservedProgress:LapseHold()
assert(Progress:IsHeld(gated), "a gated step jumped to keeps its hold")
assert(not ObservedProgress:Refresh() and (Progress:GetCurrentNode(gated)).index == 1, "and the guide stays on it")
client.CouldOpen, client.MatchesCondition = nil, nil

-- A quest accepted or handed in at a step further down the guide is called
-- out in chat: the step card cannot show work that far ahead.
local ahead = Steps:Expand({
    schema = 2, id = "test:ahead", updated = 1789862400, map = 1413, meta = { title = "Ahead", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { group = {
        { accept = 870, npc = 3448 },
        { accept = 869, npc = 3464 },
        } },
        { objectives = 870 },
        { turnin = 870, npc = 3448 },
        { accept = 913, npc = 3441 },
        { turnin = 913, npc = 3441 },
    } },
},
})
ns.modules.GuideRepository = { version = 1, List = function() return { ahead } end, Get = function(_, id) return id == ahead.id and ahead or nil end }
ns.modules.QuestIndex:Invalidate()
local function message(index, event, questID) return ObservedProgress:AheadOfStepMessage(ahead, index, event, questID) end
assert(not message(1, "QUEST_ACCEPTED", 870), "the step the player is on says nothing")
assert(not message(1, "QUEST_ACCEPTED", 869), "nor a step carried in the same group")
assert(not message(1, "QUEST_ACCEPTED", 4242), "nor a quest the guide never names")
assert(not message(1, "QUEST_TURNED_IN", 869), "a turn-in is not announced against a step that only accepts")
local accepted = message(1, "QUEST_ACCEPTED", 913)
assert(accepted and accepted:find("Out of order") and accepted:find("step 5") and accepted:find("you are on step 1"), accepted or "no message for an accept further ahead")
local turned = message(1, "QUEST_TURNED_IN", 870)
assert(turned and turned:find("hands in .* at step 4"), turned or "no message for a turn-in further ahead")
assert(not message(5, "QUEST_ACCEPTED", 913), "the step reached says nothing")
assert(not message(6, "QUEST_TURNED_IN", 870), "nor a step already behind")
assert(not message(nil, "QUEST_ACCEPTED", 913), "a finished guide has nothing ahead")

-- The quick arrival check looks only at a current step completed by arrival
-- and runs the full refresh once the player is there.
do
    local travel = Steps:Expand({
        schema = 2, id = "test:arrival", updated = 1789862400, map = 1413, meta = { title = "Arrival", category = "test" },
        steps = { { section = "Steps", steps = {
            { travel = "Ratchet", at = { 63, 37.2 } },
            { note = "There." },
        } } },
    })
    ns.modules.GuideRepository = { Get = function(_, id) return id == travel.id and travel or nil end }
    Progress:Select(travel)
    local here = false
    local savedClient = ns.modules.Client
    ns.modules.Client = setmetatable({
        MatchesObservedCompletion = function(_, observed) return observed.type == "location" and here end,
    }, { __index = savedClient })
    assert(not ObservedProgress:CheckArrival() and (Progress:GetCurrentNode(travel)).index == 1, "not there yet")
    here = true
    assert(ObservedProgress:CheckArrival() and (Progress:GetCurrentNode(travel)).index == 2, "arriving advances at once")
    assert(not ObservedProgress:CheckArrival(), "a step that is not waiting on a place is left to the full refresh")
    ns.modules.Client = savedClient
end

-- Travel and notes are passed over once the quest step they lead to is done.
do
    local passing = Steps:Expand({
        schema = 2, id = "test:passing", updated = 1789862400, map = 1413, meta = { title = "Passing", category = "test" },
        steps = { { section = "Steps", steps = {
            { travel = "The Crossroads", at = { 51.99, 29.89 } },
            { note = "Hearth if it is up." },
            { accept = 870, npc = 3448, at = { 52.26, 31.93 } },
            { travel = "Camp Taurajo", at = { 44.45, 59.15 } },
            { hearth = "Camp Taurajo", npc = 10378, at = { 44.45, 59.15 } },
            { travel = "Ratchet", at = { 63, 37.2 } },
            { turnin = 887, npc = 3464, at = { 62.5, 37.4 } },
            { note = "Done." },
        } } },
    })
    ns.modules.GuideRepository = { Get = function(_, id) return id == passing.id and passing or nil end }
    Progress:Select(passing)
    local have, bound, moot = {}, false, {}
    local savedClient, savedScan = ns.modules.Client, ns.modules.GuideScan
    local function matches(observed)
        if observed.type == "quests" then
            for _, id in ipairs(observed.ids) do if not have[id] then return false end end
            return true
        end
        return observed.type == "hearth" and bound
    end
    ns.modules.Client = setmetatable({ MatchesObservedCompletion = function(_, observed) return matches(observed) end },
        { __index = savedClient })
    ns.modules.GuideScan = {
        NodeCompleted = function(_, node) return node.completion.type == "observed" and matches(node.completion.observed) end,
        NodeIsMoot = function(_, node) return moot[node.index] == true end,
    }
    local function at() return (Progress:GetCurrentNode(passing)).index end
    local statuses = Progress:GetState(passing).statuses

    ObservedProgress:Refresh()
    assert(at() == 1, "nothing done ahead: the travel waits")
    have[870] = true
    ObservedProgress:Refresh()
    assert(at() == 4, "the travel and the note are looked through to the accept: " .. at())
    assert(statuses[1] == "skipped" and statuses[2] == "skipped" and statuses[3] == "observed",
        "passed over as skipped, the accept observed")
    Progress:Back(passing)
    Progress:Back(passing)
    assert(at() == 2 and Progress:IsHeld(passing))
    ObservedProgress:Refresh()
    assert(at() == 2 and Progress:IsHeld(passing), "BACK onto a note that would be passed keeps its hold")
    Progress:Release(passing)
    ObservedProgress:Refresh()
    assert(at() == 4, "released, it flows on again")
    bound = true
    ObservedProgress:Refresh()
    assert(at() == 4, "a hearth already bound proves no visit")
    Progress:Forward(passing, true)
    Progress:Forward(passing, true)
    moot[7] = true
    ObservedProgress:Refresh()
    assert(at() == 6, "a turn-in with no quest to do proves no visit")
    moot[7] = nil
    have[887] = true
    ObservedProgress:Refresh()
    assert(at() == 8 and statuses[6] == "skipped", "turned in: the travel before it is passed over")
    ns.modules.Client, ns.modules.GuideScan = savedClient, savedScan
end

-- Quests handed in out of order (bug report 20260924-182053 19:39:24): the
-- travel to a turn-in that also accepts the next quest is passed once it is
-- done, and so is travel to turn-ins handed in earlier, which the game
-- already reports done.
do
    local savedClient, savedScan = ns.modules.Client, ns.modules.GuideScan
    local savedGlobal = C_QuestLog
    Load(ns, "API/Client.lua")
    Load(ns, "Domain/GuideScan.lua")
    function ns.modules.Client:HasQuestLog() return true end
    local inLog, done, ready = {}, {}, {}
    C_QuestLog = {
        IsOnQuest = function(id) return inLog[id] == true end,
        IsQuestFlaggedCompleted = function(id) return done[id] == true end,
        IsComplete = function(id) return ready[id] == true end,
    }
    local order = Steps:Expand({
        schema = 2, id = "test:order", updated = 1789862400, map = 1413, meta = { title = "Order", category = "test" },
        steps = { { section = "Turning in", steps = {
            { travel = "the path up the hill", at = { 50.32, 35.44 }, only = "quest 6981" },
            { turnin = 6981, accept = 3369, npc = 8418, only = "quest 6981", at = { 48.18, 32.78 } },
            { travel = "the path down the far side", at = { 47.28, 33.56 } },
            { travel = "the ledge", at = { 45.86, 35.86 } },
            { group = {
                { turnin = 1486, npc = 5767, only = "quest 1486 readyToTurnIn", at = { 45.98, 35.66 } },
                { turnin = 1487, npc = 5768, only = "quest 1487 readyToTurnIn", at = { 46.01, 35.74 } },
            } },
            { group = {
                { turnin = 914, npc = 5770, only = "quest 914 readyToTurnIn", at = { 75.65, 31.60, map = 1456 } },
                { turnin = 3369, npc = 5769, only = "quest 3369", at = { 78.59, 28.56, map = 1456 } },
            } },
            { finish = "Done." },
        } } },
    })
    ns.modules.GuideRepository = { Get = function(_, id) return id == order.id and order or nil end }
    local function at() return (Progress:GetCurrentNode(order)).index end
    for _, lagging in ipairs({ false, true }) do
        inLog, done, ready = { [6981] = true, [914] = true }, { [1486] = true, [1487] = true }, { [914] = true }
        Progress.store, Progress.session = {}, {}
        Progress:Select(order)
        ObservedProgress:Refresh()
        assert(at() == 2, "the shard is still to hand in; the turn-ins already made past it put the scan on it, not on the travel before it")
        inLog[6981], inLog[3369] = nil, true
        if not lagging then done[6981] = true end
        ObservedProgress:Refresh()
        if lagging then
            -- Out of the log but not yet flagged done: its `quest 6981` gate
            -- reads false for a moment, and the guide waits rather than skip it.
            assert(at() == 2, "a turn-in the client has not caught up with is waited on")
            done[6981] = true
            ObservedProgress:Refresh()
        end
        assert(at() == 7, "past the shard and the cave already emptied, to Thunder Bluff: " .. at())
        local statuses = Progress:GetState(order).statuses
        assert(statuses[1] == "skipped" and statuses[3] == "skipped" and statuses[4] == "skipped")
        assert(statuses[2] == "observed", "the shard turn-in is credited")
    end
    C_QuestLog = savedGlobal
    ns.modules.Client, ns.modules.GuideScan = savedClient, savedScan
end

-- A cast of the step's own spell counts on that step; any other cast, or one
-- by another unit, does not, and says so so the event costs no refresh.
local casting = Steps:Expand({
    schema = 2, id = "test:cast", updated = 1789862400, map = 2521, meta = { title = "Cast", category = "test" },
    steps = { { section = "Steps", steps = { { cast = 1259686, at = { 35.91, 33.61 } }, { note = "After." } } } },
})
ns.modules.GuideRepository = { Get = function(_, id) return id == casting.id and casting or nil end }
Progress:Select(casting)
local recorded = {}
function ns:Record(channel, data) table.insert(recorded, { channel = channel, data = data }) end
ns.modules.Client.IsSecret = function() return false end
assert(not ObservedProgress:CheckSpellCast("target", "Cast-1", 1259686), "another unit's cast")
assert(not ObservedProgress:CheckSpellCast("player", "Cast-2", 6673), "another spell")
assert(Progress:CastCount(casting, 1) == 0)
assert(ObservedProgress:CheckSpellCast("player", "Cast-3", 1259686), "the step's spell")
assert(Progress:CastCount(casting, 1) == 1 and recorded[1].data.event == "cast" and recorded[1].data.spell == 1259686)

return true
