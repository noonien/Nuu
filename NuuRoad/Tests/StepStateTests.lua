_G = _G or _ENV
local ns = { modules = {}, db = { settings = {} }, logs = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log(message) table.insert(self.logs, message) end
local rows = {}
function ns:Record(channel, data) local row = { at = #rows, d = data, channel = channel }; table.insert(rows, row); return row end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/QuestIndex.lua")
Load(ns, "Domain/ObservedProgress.lua")
Load(ns, "Domain/StepState.lua")
local Steps, Progress, ObservedProgress, StepState = ns.modules.Steps, ns.modules.Progress, ns.modules.ObservedProgress, ns.modules.StepState

-- Snapshots of what the flow sees, recorded only when they change.
local guide = Steps:Expand({
    kind = "guide", id = "test:stepstate", updated = 1789862400, title = "Step state", category = "test",
    data = { map = 1413, sections = {
    { title = "Steps", steps = {
        { type = "accept", quests = { 870 }, npc = { 3448 } },
        { group = {
            { type = "kill", kill = { 3267 }, quest = { 870, 1 }, count = 8 },
            { type = "kill", kill = { 3268 }, quest = { 870, 2 }, cond = { class = "SHAMAN" } },
            { type = "kill", kill = { 3269 }, quest = { 870, 3 } },
        } },
        { type = "note", note = "Only with the book." },
        { type = "turnin", quests = { 870 }, npc = { 3448 } },
    } },
} },
})
-- Shown only while the book is carried: a term no guide writes any more, as
-- the runtime predicate the flow still reads.
guide.nodes[5].condition = { type = "now", child = { type = "item", id = 4470 } }
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }
Progress:Select(guide)
local log, objectives, shaman, book = {}, {}, false, false
local function holds(predicate)
    if predicate.type == "now" then return holds(predicate.child) end
    if predicate.type == "class" then return shaman end
    if predicate.type == "item" then return book end
    return true
end
ns.modules.Client = {
    IsQuestInLog = function(_, id) return log[id] == true end,
    IsQuestComplete = function() return false end,
    IsQuestReadyToTurnIn = function() return false end,
    IsQuestObjectiveComplete = function(_, quest, index) return objectives[index] == true end,
    GetQuestObjective = function() return nil end,
    GetQuestTitle = function() return nil end,
    MatchesCondition = function(_, predicate) return holds(predicate) end,
    RulesOut = function(_, predicate) return predicate.type == "class" and not shaman end,
    CouldOpen = function(_, predicate) return holds(predicate) end,
    MatchesObservedCompletion = function(_, observed)
        if observed.type == "objective" then return objectives[observed.index] == true end
        if observed.type == "quests" then
            for _, id in ipairs(observed.ids) do if not log[id] then return false end end
            return true
        end
        return false
    end,
}

-- Nothing is written before the session log has opened this session.
assert(StepState:Observe("early") == nil and #rows == 0)
ns.recorder = { identity = {}, Records = function(_, channel)
    local list = {}
    for _, row in ipairs(rows) do if row.channel == channel then table.insert(list, row) end end
    return list
end }

local first = StepState:Observe("login")
assert(first and first.d.event == "state" and first.d.step == 1 and first.d.cause == "login")
assert(first.d.auto == "incomplete", "an accept not taken is still to do: " .. tostring(first.d.auto))
assert(first.d.group == nil, "the first step is in no group")
assert(first.d.ahead[1] == 2, "the flow stops next on the first kill")
assert(StepState:Observe("poll") == nil, "the same state is not written twice")

-- Accepting moves the flow; the move and its reason ride on the row.
log[870] = true
assert(ObservedProgress:Refresh("QUEST_ACCEPTED"))
local row = rows[#rows].d
assert(row.event == "state" and row.step == 2 and row.cause == "QUEST_ACCEPTED")
assert(row.moves and row.moves[1].from == 1 and row.moves[1].to == 2 and row.moves[1].why == "observed")
assert(row.group and row.group.first == 2 and row.group.last == 4, "the kill group is recorded")
local whys = {}
for _, member in ipairs(row.group.members) do whys[member.i] = member.why end
assert(whys[2] == "current" and whys[4] == "shown")
assert(whys[3]:find("^unavailable"), "a member for another class is left out, and says why: " .. whys[3])
-- The note gated on a book not carried is passed over, not stopped on.
local passedNote = false
for _, entry in ipairs(row.passed or {}) do if entry.i == 5 and entry.why == "bypassed" then passedNote = true end end
assert(passedNote, "the `now` note without the book is passed over")

-- A kill count changing is a change of state.
local before = #rows
Progress:Back(guide)
assert(rows[#rows].d.event == "step", "BACK is a move on the guide channel")
StepState:Observe("poll")
assert(rows[#rows].d.cause == "poll after back" and rows[#rows].d.held, "the row after BACK says so, and the step is held")

-- A held step that reads done is a stall, named as such.
assert(rows[#rows].d.step == 1 and rows[#rows].d.stall == "held", "done but held: " .. tostring(rows[#rows].d.stall))
assert(#rows > before)

local lines = StepState:Describe(rows[#rows].d)
assert(lines[1]:find("Step 1 of 6") and lines[1]:find("HELD"), lines[1])
local history = StepState:HistoryLines(4)
assert(#history == 4 and history[#history]:find("STALLED held"), history[#history])

-- The stable form ignores key order.
assert(StepState.Stable({ a = 1, b = { 2, 3 } }) == StepState.Stable({ b = { 2, 3 }, a = 1 }))

ns.modules.Client, ns.recorder, ns.modules.GuideRepository = nil, nil, nil
return true
