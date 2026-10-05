_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
Load(ns, "Domain/Progress.lua")

local guide = {
    schema = 2, id = "test:progress", updated = 1789862400,
    meta = { title = "Progress", category = "test" },
    sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3, 4, 5 } } },
    nodes = {
        { kind = "action", title = "Start", ["next"] = 2 },
        { kind = "choice", title = "Route", choices = { { title = "Left", ["next"] = 3 }, { title = "Right", ["next"] = 4 } } },
        { kind = "action", title = "Left", ["next"] = 5 },
        { kind = "action", title = "Right", ["next"] = 5 },
        { kind = "end", title = "Finish" },
    },
}

local Progress = ns.modules.Progress
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }

assert(Progress:PeekState(guide) == nil, "peeking must not create state")
Progress:Select(guide)
assert(Progress:GetActiveGuide() == guide, "the selected guide must be recoverable from saved progress")

assert(Progress:GetCurrentNode(guide).index == 1)
assert(Progress:Complete(guide))
assert(Progress:GetCurrentNode(guide).index == 2)

local ok = Progress:Complete(guide)
assert(not ok, "a choice must require a selected edge")
assert(Progress:GetCurrentNode(guide).index == 2)

ok = Progress:Complete(guide, nil, "complete", "missing")
assert(not ok, "a choice must reject an edge it does not own")
assert(Progress:Complete(guide, nil, "complete", 4))
assert(Progress:GetCurrentNode(guide).index == 4)

-- Back walks the trail and keeps statuses; the returned-to step is held.
assert(Progress:Back(guide))
assert(Progress:GetCurrentNode(guide).index == 2, "back returns to the step the player left")
assert(Progress:IsHeld(guide), "a step the player came back to is held while it reads done")
local _, state = Progress:GetCurrentNode(guide)
assert(state.statuses[2] == "complete", "back keeps the earlier status")
assert(Progress:CompletedCount(state) == 2)

-- Forward keeps a finished status and holds the step it lands on.
assert(Progress:Forward(guide))
assert(Progress:IsHeld(guide), "forward holds the step it lands on")
assert(Progress:GetCurrentNode(guide).index == 3, "a choice skipped with forward uses the ordered fallback")
assert(state.statuses[2] == "complete", "forward on a finished step keeps it finished")

-- With `release` (a Shift move), neither direction holds, and a hold can be
-- let go of by hand.
assert(Progress:Forward(guide, true))
assert(not Progress:IsHeld(guide), "released forward does not hold")
assert(state.statuses[3] == "skipped", "forward on an unfinished step records a skip")
assert(Progress:Back(guide, true))
assert(not Progress:IsHeld(guide), "released back does not hold")
assert(Progress:Forward(guide) and Progress:IsHeld(guide))
Progress:Release(guide)
assert(not Progress:IsHeld(guide), "release lets go of a hold")
assert(Progress:Back(guide))
assert(Progress:GetCurrentNode(guide).index == 3)
assert(Progress:Forward(guide))
assert(Progress:CompletedCount(state) == 2, "skipped steps are not counted as completed")

-- Steps whose condition fails are passed over in the flow and the upcoming list.
local gated = {
    schema = 2, id = "test:gated", updated = 1789862400,
    meta = { title = "Gated", category = "test" },
    sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3, 4 } } },
    nodes = {
        { kind = "action", title = "A" },
        { kind = "action", title = "Warriors only", condition = { type = "class", values = { "WARRIOR" } } },
        { kind = "action", title = "B" },
        { kind = "end", title = "Shamans only", condition = { type = "class", values = { "SHAMAN" } } },
    },
}
ns.modules.Client = { MatchesCondition = function(_, predicate) return predicate.values[1] == "SHAMAN" end }
ns.modules.GuideRepository.Get = function(_, id) return id == gated.id and gated or nil end
Progress:Select(gated)
assert(Progress:NextIndex(gated, gated.nodes[1]) == 3, "an unavailable step is skipped in the ordered flow")
assert(Progress:Complete(gated))
assert(Progress:GetCurrentNode(gated).index == 3)
assert(Progress:Complete(gated))
assert(Progress:GetCurrentNode(gated).index == 4, "an available gated step is reached normally")
ns.modules.Client.MatchesCondition = function() return false end
Progress:Select(gated)
assert(Progress:GetCurrentNode(gated) == nil, "selecting with the current step unavailable moves on")
ns.modules.Client = nil
ns.modules.GuideRepository.Get = function(_, id) return id == guide.id and guide or nil end
Progress:Select(guide)

assert(Progress:Back(guide) and Progress:Back(guide) and Progress:Back(guide))
assert(Progress:GetCurrentNode(guide).index == 1)
assert(not Progress:Back(guide), "back stops at the first step")

Progress:Reset(guide)
_, state = Progress:GetCurrentNode(guide)
assert(state.currentStep == 1 and #state.trail == 0, "reset restores the guide start")
assert(Progress:GetActiveGuide() == guide, "reset must preserve the active guide selection")

-- Kills and dialogs are kept per step inside the guide state.
Progress:Reset(guide)
assert(Progress:KillCount(guide, 1) == 0)
assert(Progress:RecordKill(guide, 1) == 1 and Progress:RecordKill(guide, 1) == 2)
assert(Progress:KillCount(guide, 1) == 2 and Progress:KillCount(guide, 3) == 0, "kills are counted per step")
assert(not Progress:HasTalked(guide, 1, 3448))
assert(Progress:RecordTalk(guide, 1, 3448) == true, "the first dialog with an NPC is new")
assert(Progress:RecordTalk(guide, 1, 3448) == false, "a repeat dialog changes nothing")
assert(Progress:HasTalked(guide, 1, 3448) and not Progress:HasTalked(guide, 3, 3448))
assert(Progress:Complete(guide) and Progress:Back(guide))
assert(Progress:KillCount(guide, 1) == 2, "back keeps the tally")
Progress:Reset(guide)
assert(Progress:KillCount(guide, 1) == 0 and not Progress:HasTalked(guide, 1, 3448), "reset clears both")

-- GoTo is navigation, not skipping: it moves either way, rewrites no status,
-- and holds the step it lands on like BACK and SKIP do.
Progress.store, Progress.session = {}, {}
Progress:Select(guide)
assert(Progress:GoTo(guide, 3))
local _, jumped = Progress:GetCurrentNode(guide)
assert((Progress:GetCurrentNode(guide)).index == 3)
assert(Progress:IsHeld(guide), "a step jumped to is held while it reads done")
assert(Progress:CompletedCount(jumped) == 0, "a jump completes nothing")
assert(jumped.statuses[1] == nil and jumped.statuses[2] == nil, "a jump records no skips")
-- The steps passed over stay on the trail, so BACK walks them one at a time.
assert(Progress:Back(guide) and (Progress:GetCurrentNode(guide)).index == 2)
assert(Progress:Back(guide) and (Progress:GetCurrentNode(guide)).index == 1)
-- Jumping forward and then back to a step on the trail unwinds to it.
assert(Progress:GoTo(guide, 5) and (Progress:GetCurrentNode(guide)).index == 5)
assert(Progress:GoTo(guide, 2) and (Progress:GetCurrentNode(guide)).index == 2)
assert(Progress:Back(guide) and (Progress:GetCurrentNode(guide)).index == 1, "the trail is unwound, not appended to")
assert(not Progress:GoTo(guide, "nowhere"), "an unknown step is refused")
assert((Progress:GetCurrentNode(guide)).index == 1)

-- Quest groups: the current and remaining available members of an authored range.
local hub = {
    groups = { { first = 1, last = 4 }, { first = 6, last = 7 } },
    schema = 2, id = "test:hub", updated = 1789862400,
    meta = { title = "Hub", category = "test" },
    sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3, 4, 5, 6, 7, 8 } } },
    nodes = {
        { kind = "acceptQuest", title = "Accept 1" },
        { kind = "acceptQuest", title = "Accept 2" },
        { kind = "acceptQuest", title = "Gated", condition = { type = "class", values = { "WARRIOR" } } },
        { kind = "talk", title = "Turn in 1, accept 3" },
        { kind = "objectiveGroup", title = "Objective" },
        { kind = "acceptQuest", title = "Accept 4" },
        { kind = "turnInQuest", title = "Turn in 2" },
        { kind = "end", title = "End" },
    },
}
ns.modules.Client = { MatchesCondition = function(_, predicate) return predicate.values[1] == "SHAMAN" end }
ns.modules.GuideRepository = { Get = function(_, id) return id == hub.id and hub or nil end }
Progress.store, Progress.session = {}, {}
Progress:Select(hub)
local function ids(group) local out = {} for _, node in ipairs(group) do table.insert(out, node.index) end return table.concat(out, ",") end
assert(ids(Progress:QuestGroup(hub)) == "1,2,4", "the group runs to the objective step and skips a gated member: " .. ids(Progress:QuestGroup(hub)))
assert(ids(Progress:QuestGroup(hub, hub.nodes[5])) == "5", "a step of another kind is a group of one")
assert(ids(Progress:QuestGroup(hub, hub.nodes[6])) == "6,7", "a turn-in joins the run")
assert(ids(Progress:QuestGroup(hub, hub.nodes[8])) == "8")
-- A nearby ungrouped quest is always standalone; maps and distance cannot
-- alter author-selected membership.
local authored = hub.groups
hub.groups = nil
assert(ids(Progress:QuestGroup(hub)) == "1", "ungrouped quests never merge")
hub.groups = authored
ns.modules.Client.GetMapWorldSize = function() error("grouping must not query map size") end
hub.nodes[1].location = { mapID = 1413, x = 0, y = 0 }
hub.nodes[2].location = { mapID = 1454, x = 1, y = 1 }
assert(ids(Progress:QuestGroup(hub)) == "1,2,4", "authored group ignores proximity")
assert(ids(Progress:QuestGroup(hub, hub.nodes[2])) == "2,4", "resume in a group uses its remaining members")
ns.modules.Client.GetMapWorldSize = nil
ns.modules.GuideRepository = { Get = function(_, id) return id == hub.id and hub or nil end }
Progress.store, Progress.session = {}, {}
Progress:Select(hub)
-- Recording a member done ahead of its turn leaves the pointer where it is.
assert(Progress:Record(hub, 4, "observed"))
assert((Progress:GetCurrentNode(hub)).index == 1, "the pointer did not move")
assert(Progress:GetState(hub).statuses[4] == "observed" and #Progress:GetState(hub).trail == 0, "the status is recorded, the trail untouched")
assert(not Progress:Record(hub, 4, "observed"), "recording it again changes nothing")
assert(not Progress:Record(hub, "nowhere"), "an unknown step is refused")
assert(Progress:CompletedCount(Progress:GetState(hub)) == 1)
assert(Progress:Complete(hub, nil, "observed") and Progress:Complete(hub, nil, "observed"))
assert((Progress:GetCurrentNode(hub)).index == 4, "the flow reaches the recorded member in its turn")
assert(Progress:Complete(hub, nil, "observed") and (Progress:GetCurrentNode(hub)).index == 5)
assert(#Progress:GetState(hub).trail == 3, "walking through it adds it to the trail once")
ns.modules.Client = nil

-- Farming circuits: an edge back to an earlier step starts a new lap, and the
-- steps it covers go back to undone so the loop can be run again.
local circuit = {
    schema = 2, id = "test:circuit", updated = 1789862400,
    meta = { title = "Circuit", category = "test" },
    sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3, 4, 5 } } },
    nodes = {
        { kind = "action", title = "Ride out" },
        { kind = "travel", title = "First vein" },
        { kind = "collect", title = "Mine it" },
        { kind = "choice", title = "Again?", choices = { { title = "Another lap", ["next"] = 2 }, { title = "Done", ["next"] = 5 } } },
        { kind = "end", title = "Finish" },
    },
}
ns.modules.Schema:IndexNodes(circuit)
Progress.session[circuit.id] = nil
assert(Progress:Complete(circuit) and Progress:Complete(circuit) and Progress:Complete(circuit))
Progress:RecordKill(circuit, 3); Progress:RecordCraft(circuit, 3); Progress:RecordTalk(circuit, 3, 3357)
assert(Progress:CraftCount(circuit, 3) == 1 and Progress:KillCount(circuit, 3) == 1)
assert(Progress:CurrentLap(circuit, 3) == 1 and Progress:LapCount(circuit, 2) == 1, "no lap until the loop comes round")
assert((Progress:GetCurrentNode(circuit)).index == 4)
assert(Progress:Complete(circuit, nil, nil, 2), "the choice sends the player back to the first vein")
local state = Progress:GetState(circuit)
assert(state.currentStep == 2 and state.statuses[2] == nil and state.statuses[3] == nil and state.statuses[4] == nil, "the lap is undone again")
assert(state.statuses[1] == "complete", "steps before the circuit are left alone")
assert(Progress:CraftCount(circuit, 3) == 0 and Progress:KillCount(circuit, 3) == 0, "tallies restart with the lap")
assert(not Progress:HasTalked(circuit, 3, 3357))
assert(Progress:LapCount(circuit, 2) == 2 and Progress:CurrentLap(circuit, 3) == 2, "the second lap is counted")
assert(Progress:CurrentLap(circuit, 1) == 1 and Progress:CurrentLap(circuit, 5) == 1, "steps outside the circuit are on no lap")
assert(#state.trail == 4, "the trail keeps every step walked, so BACK still works")
assert(Progress:Complete(circuit) and Progress:Complete(circuit) and Progress:Complete(circuit, nil, nil, 2))
assert(Progress:LapCount(circuit, 2) == 3)
assert(Progress:Complete(circuit) and Progress:Complete(circuit) and Progress:Complete(circuit, nil, nil, 5))
assert((Progress:GetCurrentNode(circuit)).index == 5 and Progress:LapCount(circuit, 2) == 3, "leaving the circuit starts no lap")

-- Landing on a step this character never stops on. The saved resume step, and the default guide's opening step, are both plain numbers: when
-- the step they name is gated out (a race or class the player is not, or a
-- quest gate that reads false while the client has not handed over the quest
-- log yet), the guide must land on the next step the flow does reach, not
-- walk the pointer off the end of the guide and read as finished.
local gated = {
    schema = 2, id = "test:landon", updated = 1789862400,
    meta = { title = "Land", category = "test" },
    sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3, 4, 5 } } },
    nodes = {
        { kind = "action", title = "A" },
        { kind = "action", title = "B" },
        { kind = "action", title = "Tauren only", condition = { type = "race", values = { "tauren" } } },
        { kind = "action", title = "D" },
        { kind = "end", title = "E" },
    },
}
ns.modules.Schema:IndexNodes(gated)
ns.modules.Client = { MatchesCondition = function(_, predicate) return predicate.values[1] ~= "tauren" end }
Progress.session = {}
assert(Progress:LandOn(gated, 3), "a gated step lands on the step after it")
assert((Progress:GetCurrentNode(gated)).index == 4, "the pointer stops at the next step the flow reaches")

-- A gated step at the very end has nothing after it to land on, so the guide
-- stays where it was rather than finishing itself.
gated.nodes[5].condition = { type = "race", values = { "tauren" } }
gated.nodes[4].condition = { type = "race", values = { "tauren" } }
Progress.session = {}
assert(not Progress:LandOn(gated, 4), "with no reachable step at or past it, nothing moves")
assert((Progress:GetCurrentNode(gated)).index == 1, "the guide is left on its first step")
ns.modules.Client = nil

-- The resume step: saved at logout for every open guide, used at the next
-- login only while the guide is unchanged and the step still fits it.
local repositoryGet = ns.modules.GuideRepository.Get
ns.modules.GuideRepository.Get = function(_, id) return (id == gated.id and gated) or repositoryGet(nil, id) end
gated.nodes[4].condition, gated.nodes[5].condition = nil, nil
Progress.store, Progress.session = { activeGuideID = gated.id, openGuides = { gated.id } }, {}
assert(Progress:LandOn(gated, 4))
Progress:SaveResume()
local resume = Progress.store.resumes[gated.id]
assert(resume.step == 4 and resume.updated == gated.updated)
assert(Progress:ResumeStep() == 4 and Progress:ResumeStep(gated) == 4)
resume.updated = gated.updated - 1
assert(Progress:ResumeStep() == nil, "a guide edited since the save discards the step")
resume.updated, resume.step = gated.updated, 99
assert(Progress:ResumeStep() == nil, "a step past the end is not restored")
Progress.store.resumes = { ["test:other"] = { step = 4, updated = gated.updated } }
assert(Progress:ResumeStep() == nil, "a step saved for another guide is not restored")
Progress.store.activeGuideID, Progress.store.openGuides = nil, nil
Progress:SaveResume()
assert(Progress.store.resumes == nil, "no open guide saves no step")

-- Tabs: a guide shown is open; shutting one moves to the tab in its place.
do
    local function tabGuide(id)
        return { schema = 2, id = id, updated = 1789862400, meta = { title = id, category = "test" },
            sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3 } } },
            nodes = { { kind = "action", title = "A" }, { kind = "action", title = "B" }, { kind = "end", title = "C" } } }
    end
    local one, two, three = tabGuide("test:tab-one"), tabGuide("test:tab-two"), tabGuide("test:tab-three")
    local byID = { [one.id] = one, [two.id] = two, [three.id] = three }
    local repository, scan = ns.modules.GuideRepository, ns.modules.GuideScan
    ns.modules.GuideRepository, ns.modules.GuideScan = { Get = function(_, id) return byID[id] end }, nil
    local function open() return table.concat(Progress:OpenIDs(), ",") end
    Progress.store, Progress.session = {}, {}
    Progress:Select(one)
    Progress:Select(two)
    Progress:Select(three)
    assert(open() == "test:tab-one,test:tab-two,test:tab-three" and Progress:GetActiveGuide() == three, "each guide opens a tab")
    Progress:Forward(two)
    Progress:Select(two)
    assert(open() == "test:tab-one,test:tab-two,test:tab-three", "a guide already open keeps its tab")
    assert(Progress:GetCurrentIndex(two) == 2, "and its place")
    assert(Progress:IsOpen(one) and #Progress:OpenGuides() == 3)
    -- The saved steps, one per open guide that has moved.
    Progress:SaveResume()
    assert(Progress.store.resumes[two.id].step == 2 and Progress.store.resumes[one.id].step == 1, "a step saved for each open guide")
    assert(Progress:ResumeStep(two) == 2 and Progress:ResumeStep(one) == nil, "a guide on its first step has nothing to resume")
    assert(Progress:Close(one) == two and open() == "test:tab-two,test:tab-three", "shutting a tab not shown leaves the shown one")
    assert(Progress.store.resumes[one.id] == nil, "and forgets its saved step")
    assert(Progress:Close(two) == three and Progress:GetActiveGuide() == three, "shutting the shown tab shows the next")
    Progress:Select(two)
    assert(open() == "test:tab-three,test:tab-two" and Progress:GetCurrentIndex(two) == 1, "opened again at the end, from the start")
    assert(Progress:Close(two) == three, "shutting the last tab shows the one before")
    assert(Progress:Close(three) == nil and Progress:GetActiveGuide() == nil and open() == "", "shutting every tab leaves no guide")
    -- A character saved before tabs: its guide is open, its step kept; a
    -- guide the repository no longer has is not.
    Progress.store = { activeGuideID = two.id, resume = { guideID = two.id, step = 2, updated = two.updated },
        openGuides = { "test:gone", one.id } }
    Progress:SettleOpenGuides()
    assert(open() == "test:tab-two,test:tab-one", "the active guide is open, the missing one is not: " .. open())
    assert(Progress.store.resume == nil and Progress:ResumeStep(two) == 2, "the old saved step carries over")
    ns.modules.GuideRepository, ns.modules.GuideScan = repository, scan
end

-- Forward passes over reminders: they are done on arrival, and are no stop.
do
    local tracked = {
        schema = 2, id = "test:progress-reminder", updated = 1789862400,
        meta = { title = "Reminders", category = "test" },
        sections = { { id = "one", title = "One", nodeIndexes = { 1, 2, 3, 4 } } },
        nodes = {
            { kind = "action", title = "Start" },
            { kind = "reminder", title = "Track", auto = { verb = "track", track = 1 } },
            { kind = "reminder", title = "Untrack", auto = { verb = "untrack", untrack = 2 } },
            { kind = "end", title = "Finish" },
        },
    }
    local repository = ns.modules.GuideRepository
    ns.modules.GuideRepository = { Get = function(_, id) return id == tracked.id and tracked or nil end }
    Progress:Select(tracked)
    assert(Progress:Forward(tracked))
    local node, trackedState = Progress:GetCurrentNode(tracked)
    assert(node.index == 4, "forward lands past the reminders")
    assert(Progress:IsDone(trackedState.statuses[2]) and Progress:IsDone(trackedState.statuses[3]), "passed reminders read done")
    assert(Progress:Back(tracked) and Progress:GetCurrentNode(tracked).index == 1, "back skips them too")
    ns.modules.GuideRepository = repository
    Progress:Select(guide)
end

-- Deselect leaves the tracker with no guide, no tabs and no step to resume.
Progress.store = { activeGuideID = gated.id, openGuides = { gated.id }, resumes = { [gated.id] = { step = 2 } } }
Progress:Deselect()
assert(Progress.store.activeGuideID == nil and Progress.store.resumes == nil and Progress.store.openGuides == nil,
    "deselect clears the active guide and the tabs")
assert(Progress:GetActiveGuide() == nil)

-- A guide rebuilt under the same ID keeps the progress of the steps it still
-- has, found by what they are, not where they sit; counts may change.
local function planned(nodes)
    return { schema = 2, id = "test:planned", updated = 1, meta = { title = "Planned", category = "test" }, nodes = nodes }
end
local first = planned({
    { kind = "train", auto = { verb = "train", skill = "Leatherworking" } },
    { kind = "buy", auto = { verb = "buy", item = 2318, count = 20 } },
    { kind = "buy", auto = { verb = "buy", item = 2320, count = 5 } },
    { kind = "skillUp", auto = { verb = "skillup", item = 2304, skill = "Leatherworking", rank = 30 } },
    { kind = "end", title = "Guide complete", body = "Done." },
})
Progress.store, Progress.session = {}, {}
Progress:Forward(first, true)            -- train: skipped by hand
assert(Progress:Complete(first))         -- 2318: ticked
Progress:RecordCraft(first, 4)
assert(Progress:GetCurrentIndex(first) == 3)
local second = planned({
    { kind = "train", auto = { verb = "train", skill = "Leatherworking" } },
    { kind = "buy", auto = { verb = "buy", item = 2318, count = 12 } },
    { kind = "craft", auto = { verb = "craft", item = 2318 } },
    { kind = "buy", auto = { verb = "buy", item = 2320, count = 3 } },
    { kind = "skillUp", auto = { verb = "skillup", item = 2304, skill = "Leatherworking", rank = 30 } },
    { kind = "end", title = "Guide complete", body = "Done." },
})
local carried = Progress:Carry(first, second)
assert(Progress.session["test:planned"] == carried, "the carried state is the guide's session state")
assert(carried.statuses[1] == "skipped", "a manual skip survives the rebuild")
assert(carried.statuses[2] == "complete", "a tick survives with a new count")
assert(carried.statuses[3] == nil, "a new step starts undone")
assert(carried.currentStep == 4, "the player stays on the step they were on, wherever it moved")
assert(carried.crafts[5] == 1, "crafts counted follow their step")
assert(#carried.trail == 2 and carried.trail[1] == 1 and carried.trail[2] == 2, "the trail follows its steps")
-- With the current step gone, the first step neither done nor skipped.
local third = planned({
    { kind = "train", auto = { verb = "train", skill = "Leatherworking" } },
    { kind = "buy", auto = { verb = "buy", item = 2318, count = 12 } },
    { kind = "skillUp", auto = { verb = "skillup", item = 2304, skill = "Leatherworking", rank = 30 } },
    { kind = "end", title = "Guide complete", body = "Done." },
})
Progress.session["test:planned"] = nil
Progress:Forward(first, true); assert(Progress:Complete(first))
carried = Progress:Carry(first, third)
assert(carried.currentStep == 3, "a vanished current step lands on the first outstanding one")
-- No earlier progress: a fresh state.
Progress.session = {}
carried = Progress:Carry(first, third)
assert(carried.currentStep == 1 and next(carried.statuses) == nil, "nothing to carry starts afresh")

-- The guide as the character has it: a step ruled out is not numbered; one
-- only gated for now still is.
local numbered = {
    nodes = {
        { index = 1, kind = "action" },
        { index = 2, kind = "action", condition = { type = "race", values = { "TAUREN" } } },
        { index = 3, kind = "action", condition = { type = "level", atLeast = 10 } },
        { index = 4, kind = "action" },
    },
}
ns.modules.Client = { RulesOut = function(_, predicate) return predicate.type == "race" end }
assert(Progress:IsRuledOut(numbered.nodes[2]) and not Progress:IsRuledOut(numbered.nodes[3]))
local steps, numbers = Progress:CharacterSteps(numbered)
assert(#steps == 3 and steps[2] == numbered.nodes[3], "the ruled-out step is left out")
assert(numbers[1] == 1 and numbers[2] == nil and numbers[3] == 2 and numbers[4] == 3)
ns.modules.Client = nil
assert(#Progress:CharacterSteps(numbered) == 4, "without a client nothing is ruled out")

-- The flow passes over only what can never open, and stops on what may.
local waiting = {
    nodes = {
        { index = 1, kind = "action" },
        { index = 2, kind = "action", condition = { type = "race", values = { "TAUREN" } } },
        { index = 3, kind = "action", condition = { type = "level", atLeast = 10 } },
        { index = 4, kind = "action" },
    },
}
ns.modules.Client = {
    MatchesCondition = function() return false end,
    CouldOpen = function(_, predicate) return predicate.type ~= "race" end,
}
assert(Progress:IsBypassed(waiting.nodes[2]) and not Progress:IsWaiting(waiting.nodes[2]))
assert(Progress:IsWaiting(waiting.nodes[3]) and not Progress:IsBypassed(waiting.nodes[3]))
assert(Progress:NextIndex(waiting, waiting.nodes[1]) == 3, "the wrong race is passed over, the level is stopped on")
ns.modules.Client = nil

return true
