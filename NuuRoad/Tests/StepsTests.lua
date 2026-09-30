_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
local Steps, Schema, Names = ns.modules.Steps, ns.modules.Schema, ns.modules.Names

local guide = Steps:Expand({
    schema = 2, id = "test:compact", updated = 1789862400, map = 1413,
    meta = { title = "Compact", category = "test" },
    steps = {
        { section = "First Part", steps = {
            { travel = "Ratchet", at = { 0.63, 0.37 } },
            { note = "Only notes carry text." },
            { accept = 870, npc = 3448, at = { 0.52, 0.31 } },
            { accept = 870, npc = 3448, at = { 0.52, 0.31 } },
            { objectives = { 871, 844 }, at = { 0.55, 0.25 }, radius = 0.06 },
            { objective = 870, any = 848, at = { 0.45, 0.22 } },
            { turnin = { 870, 845 }, at = { 0.52, 0.31, map = 1414 } },
            { choice = "Which way?", options = { { "Camp", goto = "camp" }, { "Level", goto = "level" } } },
            { objectives = { 887 }, at = { 0.63, 0.45 }, label = "camp" },
            { level = 17, label = "level" },
            { finish = "The end." },
        } },
    },
})
local ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
assert(guide.steps == nil and guide.map == nil, "compact keys are consumed")
assert(#guide.sections == 1 and guide.sections[1].id == "first-part" and #guide.sections[1].nodeIndexes == 11)

local n = guide.nodes
assert(n[1].index == 1 and n[1].kind == "travel" and n[1].completion.observed.type == "location")
assert(Steps:Title(n[1]) == "Travel to Ratchet")
assert(n[1].location.mapID == 1413 and n[1].location.arrivalRadiusNormalized == 0.03, "default map and travel radius apply")
assert(n[2].kind == "note" and n[2].body == "Only notes carry text." and n[2].completion.type == "manual")
assert(n[3].index == 3 and n[4].index == 4, "repeated steps have distinct positions")
assert(n[3].kind == "acceptQuest" and n[3].completion.observed.state == "acceptedOrFinished")
assert(n[3].refs.npcs[1] == 3448 and n[3].location.arrivalRadiusNormalized == 0.02)
assert(Steps:Title(n[3]) == "Accept The Forgotten Pools", Steps:Title(n[3]))
assert(n[5].kind == "objectiveGroup" and n[5].completion.observed.state == "readyToTurnIn" and n[5].completion.observed.match == "all")
assert(n[5].location.arrivalRadiusNormalized == 0.06 and Steps:Title(n[5]) == "Complete Disrupt the Attacks and Plainstrider Menace")
assert(n[6].kind == "questObjective" and n[6].completion.observed.match == "any" and #n[6].completion.observed.ids == 2)
assert(n[7].index == 7 and n[7].location.mapID == 1414 and Steps:Title(n[7]) == "Turn in The Forgotten Pools and The Zhevra")
assert(n[8].kind == "choice" and n[8].choices[1].title == "Camp" and n[8].choices[1]["next"] == 9 and n[8].choices[2]["next"] == 10)
assert(n[9].index == 9, "branch targets are step indexes")
assert(n[10].index == 10 and n[10].completion.observed.atLeast == 17 and Steps:Title(n[10]) == "Reach level 17")
assert(n[11].kind == "end" and n[11].body == "The end." and n[11].completion.type == "manual")
for _, node in ipairs(n) do assert(node["next"] == nil, "ordered flow needs no edges") end

-- Bundled talk steps, objective parts, XP levels, and conditions.
local extra = Steps:Expand({
    schema = 2, id = "test:extra", updated = 1789862400, map = 1413, meta = { title = "Extra", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { turnin = 871, accept = { 872, 5041 }, npc = 3429, at = { 51.50, 30.87 } },
        { objective = 821, part = 2, at = { 48, 13.2 } },
        { level = 13, xp = 9200 },
        { note = "Warriors and Shamans only.", only = "Warrior or Shaman" },
        { turnin = 809, npc = 3521, at = { 62.34, 20.07 }, only = "not Tauren" },
        { objective = 858, at = { 56.2, 8.25 }, only = "quest 858" },
        { note = "mixed", only = "not Tauren or Orc" },
    } },
},
})
ok, errors = Schema:Validate(extra)
assert(ok, table.concat(errors, "; "))
local e = extra.nodes
assert(e[1].index == 1 and e[1].kind == "talk")
assert(e[1].completion.observed.type == "all" and e[1].completion.observed.children[1].state == "finished" and e[1].completion.observed.children[2].ids[2] == 5041)
assert(Steps:Title(e[1]) == "Turn in Disrupt the Attacks, accept The Disruption Ends and Supplies for the Crossroads", Steps:Title(e[1]))
assert(#e[1].refs.quests == 3, "a talk step lists every quest it touches")
assert(e[1].location.x == 0.515 and e[1].location.arrivalRadiusNormalized == 0.02, "percent coordinates and the talk radius apply")
assert(e[2].index == 2 and e[2].completion.observed.type == "objective" and e[2].completion.observed.questID == 821 and e[2].completion.observed.index == 2)
assert(Steps:Title(e[2]) == "Chen's Empty Keg, objective 2", Steps:Title(e[2]))
assert(e[3].completion.observed.xp == 9200 and Steps:Title(e[3]) == "Reach level 13 with 9200 XP")
assert(e[4].condition.type == "any" and e[4].condition.children[1].values[1] == "WARRIOR" and e[4].condition.children[2].values[1] == "SHAMAN")
assert(e[5].condition.type == "not" and e[5].condition.child.type == "race" and e[5].condition.child.values[1] == "tauren")
assert(e[6].condition.type == "quest" and e[6].condition.id == 858)
assert(e[7].condition.type == "all" and e[7].condition.children[1].type == "race" and e[7].condition.children[2].type == "not")
assert(not pcall(Steps.Expand, Steps, { steps = {
    { note = "x", only = "Gnome Warrior" }
} }), "unknown condition terms are rejected")

-- Items, hearth, flight paths, sticky tracks, objects, map pins, kill and collect counts.
Names.items[4926] = "Chen's Empty Keg"; Names.items[5087] = "Plainstrider Beak"; Names.npcs[3267] = "Razormane Water Seeker"
local more = Steps:Expand({
    schema = 2, id = "test:more", updated = 1789862400, map = 1413, meta = { title = "More", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { collect = 4926, object = "Chen's Empty Keg", at = { 55.78, 20.01 } },
        { hearth = "The Crossroads", npc = 3934, at = { 51.99, 29.90 } },
        { flight = "Ratchet", npc = 16227, at = { 63.09, 37.16 } },
        { track = 869 },
        { objective = 871, part = 1, kill = 3267, count = 8, at = { { 55.6, 25.4 }, { 53, 25.2 }, { 54.4, 27.2 } } },
        { objective = 844, part = 1, collect = 5087, count = 7, at = { 53, 22.4 } },
        { object = "Fuel Control Valve", objective = 900, part = 2, at = { 52.4, 11.41 } },
        { object = "Control Console", turnin = 894, accept = 900, at = { 52.41, 11.64 } },
        { untrack = 869 },
        { object = "Altar of Fire", at = { 47.96, 19.07 } },
    } },
},
})
ok, errors = Schema:Validate(more)
assert(ok, table.concat(errors, "; "))
local m = more.nodes
assert(m[1].index == 1 and m[1].kind == "collect" and m[1].completion.observed.type == "item" and m[1].completion.observed.itemID == 4926 and m[1].completion.observed.count == 1)
assert(Steps:Title(m[1]) == "Collect Chen's Empty Keg at Chen's Empty Keg", Steps:Title(m[1]))
assert(m[2].index == 2 and m[2].kind == "hearth" and m[2].completion.observed.type == "hearth" and m[2].completion.observed.name == "The Crossroads")
assert(Steps:Title(m[2]) == "Set your hearthstone at The Crossroads")
assert(m[3].kind == "flight" and m[3].completion.observed.type == "flightpath" and Steps:Title(m[3]) == "Learn the Ratchet flight path")
assert(m[4].index == 4 and m[4].kind == "reminder" and m[4].completion.observed.type == "always" and Steps:Title(m[4]) == "Meanwhile: Raptor Thieves")
assert(m[5].kind == "kill" and m[5].refs.npcs[1] == 3267 and Steps:Title(m[5]) == "Kill 8 Razormane Water Seeker", Steps:Title(m[5]))
assert(#m[5].location.spots == 2 and m[5].location.spots[1].x == 0.53 and m[5].location.spots[2].y == 0.272, "the points after the first are map pins")
assert(m[6].kind == "collect" and m[6].refs.items[1] == 5087 and m[6].completion.observed.type == "objective" and Steps:Title(m[6]) == "Collect 7 Plainstrider Beak")
assert(m[7].kind == "interact" and m[7].completion.observed.questID == 900 and Steps:Title(m[7]) == "Click Fuel Control Valve")
assert(m[8].kind == "talk" and Steps:Title(m[8]) == "Turn in Samophlange, accept Samophlange at Control Console", Steps:Title(m[8]))
assert(m[9].index == 9 and m[9].kind == "reminder")
assert(m[10].kind == "interact" and m[10].completion.type == "manual" and Steps:Title(m[10]) == "Click Altar of Fire")

-- A collect step tied to a quest: the item that begins it, or a quest item.
local tied = Steps:Expand({
    schema = 2, id = "test:tied", updated = 1789862400, map = 1413, meta = { title = "Tied", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { collect = 4926, starts = 819, object = "Chen's Empty Keg", at = { 55.78, 20.01 } },
        { collect = 4986, quest = 924, at = { 62.34, 20.03 } },
    } },
},
})
ok, errors = Schema:Validate(tied)
assert(ok, table.concat(errors, "; "))
assert(tied.nodes[1].completion.observed.startsQuestID == 819 and tied.nodes[1].completion.observed.questID == nil and tied.nodes[1].refs.quests[1] == 819)
assert(tied.nodes[2].completion.observed.questID == 924 and tied.nodes[2].completion.observed.startsQuestID == nil and tied.nodes[2].refs.quests[1] == 924)
assert(Steps:Title(tied.nodes[1]) == "Collect Chen's Empty Keg at Chen's Empty Keg", "the tie does not change the title")
local tiedGoals = Steps:Goals(tied.nodes[1])
assert(#tiedGoals == 1 and tiedGoals[1].item == 4926 and tiedGoals[1].quest == 819 and tiedGoals[1].startsQuest == true)
assert(Steps:Goals(tied.nodes[2])[1].quest == 924 and Steps:Goals(tied.nodes[2])[1].startsQuest == nil)
do
    local bags, inLog, complete, ready, logRead = {}, {}, {}, {}, true
    ns.modules.Client = {
        GetItemCount = function(_, id) return bags[id] or 0 end,
        IsQuestInLog = function(_, id) return inLog[id] == true end,
        IsQuestComplete = function(_, id) return complete[id] == true end,
        IsQuestReadyToTurnIn = function(_, id) return ready[id] == true end,
        IsQuestMoot = function(self, id) return logRead and not self:IsQuestInLog(id) and not self:IsQuestComplete(id) end,
    }
    local starter, questItem = Steps:Goals(tied.nodes[1])[1], Steps:Goals(tied.nodes[2])[1]
    assert(Steps:GoalStatus(starter, tied.nodes[1]) == "todo", "an item that begins a quest is never moot")
    inLog[819] = true
    assert(Steps:GoalStatus(starter, tied.nodes[1]) == "done", "the item was used once its quest is in the log")
    inLog[819], complete[819] = nil, true
    assert(Steps:GoalStatus(starter, tied.nodes[1]) == "done", "or once that quest is finished")
    assert(Steps:GoalStatus(questItem, tied.nodes[2]) == "moot", "a quest item for a quest the player does not have")
    inLog[924] = true
    assert(Steps:GoalStatus(questItem, tied.nodes[2]) == "todo")
    bags[4986] = 1
    assert(Steps:GoalStatus(questItem, tied.nodes[2]) == "done", "in bags")
    bags[4986], ready[924] = nil, true
    assert(Steps:GoalStatus(questItem, tied.nodes[2]) == "done", "used up, the quest is ready to hand in")
    ns.modules.Client = nil
end
-- Escorts: done when the quest is ready, titled by the NPC, and a failed
-- quest says so instead of waiting as if under way.
do
    local escorts = Steps:Expand({
        schema = 2, id = "test:escort", updated = 1789862400, map = 1413,
        meta = { title = "Escort", category = "test" },
        steps = { { section = "Drill site", steps = {
            { escort = 863, npc = 3439, at = { 55.35, 7.70 } },
        } } },
    })
    ok, errors = Schema:Validate(escorts)
    assert(ok, table.concat(errors, "; "))
    local node = escorts.nodes[1]
    assert(node.kind == "escort" and node.completion.observed.state == "readyToTurnIn" and node.completion.observed.ids[1] == 863)
    assert(node.refs.npcs[1] == 3439 and node.refs.quests[1] == 863 and node.location.arrivalRadiusNormalized == 0.05)
    assert(Steps:Title(node) == "Escort Wizzlecrank's Shredder", Steps:Title(node))
    local goals = Steps:Goals(node)
    assert(#goals == 1 and goals[1].verb == "escort" and Steps:GoalText(goals[1]) == "Escort Wizzlecrank's Shredder")
    local inLog, ready, failed = {}, {}, {}
    ns.modules.Client = {
        IsQuestInLog = function(_, id) return inLog[id] == true end,
        IsQuestComplete = function() return false end,
        IsQuestReadyToTurnIn = function(_, id) return ready[id] == true end,
        IsQuestFailed = function(_, id) return failed[id] == true end,
        IsQuestMoot = function(_, id) return not inLog[id] end,
    }
    assert(Steps:GoalStatus(goals[1], node) == "moot", "not taken")
    inLog[863] = true
    assert(Steps:GoalStatus(goals[1], node) == "active")
    failed[863] = true
    assert(Steps:GoalStatus(goals[1], node) == "failed", "the NPC died")
    failed[863], ready[863] = nil, true
    assert(Steps:GoalStatus(goals[1], node) == "done")
    ns.modules.Client = nil
    assert(not pcall(Steps.Expand, Steps, { schema = 2, id = "test:bad", updated = 1, map = 1413, meta = { title = "x", category = "test" },
        steps = { { section = "s", steps = { { escort = 863, at = { 1, 1 } } } } } }), "an escort names its NPC")
end
local tracks = Steps:ActiveTracks(more, m[6])
assert(#tracks == 1 and tracks[1] == 869, "a track is active between track and untrack")
assert(#Steps:ActiveTracks(more, m[10]) == 0, "untrack closes it")
assert(#Steps:ActiveTracks(more, m[4]) == 0, "the track step itself is not yet active")
do
    local again = Steps:Expand({ schema = 2, id = "test:retrack", updated = 1789862400, map = 1413,
        meta = { title = "R", category = "test" }, steps = { { section = "S", steps = {
            { track = 869 }, { untrack = 869 }, { track = 869 }, { note = "Here." },
        } } } })
    local open = Steps:ActiveTracks(again, again.nodes[4])
    assert(#open == 1 and open[1] == 869, "a quest tracked again is one line, not two")
end

-- A note on a step is that step's body; a bare note is still its own step.
local noted = Steps:Expand({ schema = 2, id = "test:noted", updated = 1789862400, map = 1413, meta = { title = "N", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 870, npc = 3448, at = { 52.26, 31.93 }, note = "Inside the inn." }, { note = "Alone." }, { finish = "End", note = "ignored" }
    } },
} })
assert(noted.nodes[1].kind == "acceptQuest" and noted.nodes[1].body == "Inside the inn." and Steps:Title(noted.nodes[1]) == "Accept The Forgotten Pools")
assert(noted.nodes[2].kind == "note" and noted.nodes[2].body == "Alone.")
assert(noted.nodes[3].kind == "end" and noted.nodes[3].body == "End")

-- Unknown ids fall back to a readable placeholder, and a v1 guide passes through untouched.
assert(Steps:Title({ auto = { verb = "accept", quests = { 424242 } } }) == "Accept quest 424242")
assert(Names:DescribeNPC(3429) == "Thork" and Names:DescribeNPC(1) == "NPC 1")
local plain = { nodes = {}, sections = {} }
assert(Steps:Expand(plain) == plain)


-- Goal lines: one per thing to do, with roles for colouring and status hooks.
local function plain(goal) return Steps:GoalText(goal) end
local function roles(goal) local out = {} for _, p in ipairs(goal.parts) do if p.role ~= "plain" then table.insert(out, p.role) end end return table.concat(out, ",") end

local g = Steps:Goals(n[3]) -- accept 870 from npc 3448
assert(#g == 2 and g[1].verb == "talk" and plain(g[1]) == "Talk to Tonga Runetotem" and roles(g[1]) == "npc", plain(g[1]))
assert(g[2].verb == "accept" and plain(g[2]) == "Accept The Forgotten Pools" and g[2].quest == 870 and g[2].state == "acceptedOrFinished" and roles(g[2]) == "quest")
assert(Steps:GoalText(g[2], function(role, text) return role == "quest" and ("<" .. text .. ">") or text end) == "Accept <The Forgotten Pools>")

g = Steps:Goals(n[7]) -- turnin 870 and 845, no npc
assert(#g == 2 and g[1].verb == "turnin" and g[1].quest == 870 and g[1].state == "finished" and g[2].quest == 845, plain(g[1]))

g = Steps:Goals(n[5]) -- objectives 871 and 844
assert(#g == 2 and g[1].verb == "objective" and plain(g[1]) == "Complete Disrupt the Attacks" and g[1].state == "readyToTurnIn")

g = Steps:Goals(n[1]) -- travel
assert(#g == 1 and g[1].verb == "travel" and plain(g[1]) == "Travel to Ratchet" and roles(g[1]) == "location" and g[1].observed.type == "location")

g = Steps:Goals(n[10]) -- level 17
assert(#g == 1 and g[1].verb == "level" and plain(g[1]) == "Reach level 17" and roles(g[1]) == "count" and g[1].observed.atLeast == 17)

g = Steps:Goals(n[2]) -- note
assert(#g == 1 and g[1].verb == "note" and plain(g[1]) == "Note")

g = Steps:Goals(m[5]) -- objective with part and kill
assert(#g == 1 and g[1].verb == "kill" and plain(g[1]) == "Kill 8 Razormane Water Seeker" and roles(g[1]) == "count,monster" and g[1].objective.quest == 871 and g[1].objective.index == 1, plain(g[1]))

g = Steps:Goals(m[6]) -- objective with part and collect
assert(g[1].verb == "collect" and plain(g[1]) == "Collect 7 Plainstrider Beak" and roles(g[1]) == "count,item")
-- The item part carries the item it names, which is what lets the tracker
-- turn it into the game's own link instead of a coloured string.
assert(g[1].parts[3].role == "item" and g[1].parts[3].id == 5087, tostring(g[1].parts[3].id))

-- With the client reading the quest's own objective line, the number in
-- front is what is left rather than what the step first asked for.
ns.modules.Client = {
    GetQuestObjective = function(_, questID, index)
        if questID == 844 and index == 1 then return false, "Plainstrider Beak: 4/7" end
    end,
    GetItemCount = function() return 0 end,
}
assert(Steps:Have(m[6]) == 4 and Steps:CountText(m[6]) == "3 ", Steps:CountText(m[6]))
assert(Steps:Title(m[6]) == "Collect 3 Plainstrider Beak", Steps:Title(m[6]))
-- A report about the guide itself wants the step as authored.
assert(Steps:Title(m[6], true) == "Collect 7 Plainstrider Beak", Steps:Title(m[6], true))
ns.modules.Client = nil
assert(Steps:Title(m[6]) == "Collect 7 Plainstrider Beak", "without a client the authored count stands")

g = Steps:Goals(m[1]) -- collect item at object
assert(g[1].verb == "collect" and plain(g[1]) == "Collect Chen's Empty Keg at Chen's Empty Keg" and g[1].item == 4926 and g[1].count == 1 and roles(g[1]) == "count,item,location")

g = Steps:Goals(m[8]) -- talk at object: Control Console
assert(#g == 3 and g[1].verb == "interact" and plain(g[1]) == "Click Control Console" and g[2].verb == "turnin" and g[3].verb == "accept", plain(g[1]))

g = Steps:Goals(m[2]); assert(g[1].verb == "hearth" and plain(g[1]) == "Set your hearthstone at The Crossroads" and g[1].observed.type == "hearth")
g = Steps:Goals(m[3]); assert(g[1].verb == "flight" and plain(g[1]) == "Learn the Ratchet flight path")
g = Steps:Goals(m[4]); assert(g[1].verb == "reminder" and plain(g[1]) == "Meanwhile: Raptor Thieves" and g[1].quest == 869)
g = Steps:Goals(m[10]); assert(g[1].verb == "interact" and plain(g[1]) == "Click Altar of Fire")

-- Without a client there is no status; with one, statuses follow the quest log.
assert(Steps:GoalStatus(Steps:Goals(n[3])[2], n[3]) == nil)
ns.modules.Client = {
    IsQuestInLog = function(_, id) return id == 870 end,
    IsQuestComplete = function(_, id) return id == 845 end,
    IsQuestReadyToTurnIn = function(_, id) return id == 870 end,
    IsQuestObjectiveComplete = function() return false end,
    GetQuestObjective = function() return false, "Razormane Water Seeker slain: 3/8" end,
    GetItemCount = function() return 2 end,
    MatchesObservedCompletion = function() return true end,
}
g = Steps:Goals(n[3])
assert(Steps:GoalStatus(g[2], n[3]) == "done", "an accepted quest is done")
-- The "Talk to" line of a quest visit is judged by the quests it is there
-- for, never by the dialog: the visit whose quest is accepted reads done, and
-- one whose quests are outstanding stays open however much was said.
assert(Steps:GoalStatus(g[1], n[3]) == "done", "the visit's only quest is accepted")
local visit = Steps:Goals(e[1])
assert(visit[1].verb == "talk" and #visit[1].settles == 3, "the visit carries all three of its quests")
assert(Steps:GoalStatus(visit[1], e[1]) == nil, "talking is neither turning in nor accepting")
g = Steps:Goals(n[7])
assert(Steps:GoalStatus(g[1], n[7]) == "active", "ready to turn in is in progress for a turn-in goal")
assert(Steps:GoalStatus(g[2], n[7]) == "done", "a flagged quest is done")
g = Steps:Goals(n[5])
assert(Steps:GoalStatus(g[1], n[5]) == "todo", "a quest not in the log is to do")
local status, progress = Steps:GoalStatus(Steps:Goals(m[5])[1], m[5])
assert(status == "todo" and progress == "3/8", tostring(status) .. " " .. tostring(progress))
status, progress = Steps:GoalStatus(Steps:Goals(m[1])[1], m[1])
assert(status == "done" and progress == nil)
assert(Steps:GoalStatus(Steps:Goals(n[1])[1], n[1]) == "done")

-- A quest the player never took and never finished: the goals that act on it
-- read as moot rather than to do, so the tracker can grey them out instead of
-- asking for work that is not there. Accepting is always open, so an accept
-- goal for the same quest stays to do.
ns.modules.Client.IsQuestMoot = function(self, id)
    return not self:IsQuestInLog(id) and not self:IsQuestComplete(id)
end
g = Steps:Goals(e[1]) -- turn in 871, accept 872 and 5041
assert(Steps:GoalStatus(g[2], e[1]) == "moot", "a turn-in for a quest never taken is moot")
assert(Steps:GoalStatus(g[3], e[1]) == "todo" and Steps:GoalStatus(g[4], e[1]) == "todo", "accepting is never moot")
assert(Steps:GoalStatus(Steps:Goals(n[5])[1], n[5]) == "moot", "so is completing one")
assert(Steps:GoalStatus(Steps:Goals(n[7])[1], n[7]) == "active", "a quest in the log is untouched")
status, progress = Steps:GoalStatus(Steps:Goals(m[5])[1], m[5])
assert(status == "moot" and progress == "3/8", "an objective line of a quest never taken is moot")
ns.modules.Client = nil

-- Standalone kill steps: counted from the combat log, no quest involved.
local killed = Steps:Expand({
    schema = 2, id = "test:kill", updated = 1789862400, map = 1413, meta = { title = "Kill", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { kill = { 3244, 3245 }, count = 3, at = { 48, 13.2 } },
        { kill = 3267, note = "One is enough." },
        { collect = 4926, kill = 3267, at = { 55, 20 } },
        { objective = 871, part = 1, kill = 3267, count = 8, npc = 3448 },
        { accept = 870, npc = 3448 },
    } },
},
})
ok, errors = Schema:Validate(killed)
assert(ok, table.concat(errors, "; "))
local k = killed.nodes
assert(k[1].index == 1 and k[1].kind == "kill" and k[1].completion.observed.type == "kills" and k[1].completion.observed.count == 3 and #k[1].completion.observed.npcs == 2)
assert(k[1].refs.npcs[2] == 3245 and k[1].location.arrivalRadiusNormalized == 0.05)
assert(Steps:Title(k[1]) == "Kill 3 Greater Plainstrider and Ornery Plainstrider", Steps:Title(k[1]))
assert(k[2].index == 2 and k[2].completion.observed.count == 1 and k[2].body == "One is enough." and Steps:Title(k[2]) == "Kill Razormane Water Seeker")
assert(k[3].kind == "collect" and k[3].auto.verb == "collect" and k[3].auto.kill[1] == 3267, "collect wins over kill")
local kill, talk = Steps:NPCs(k[1])
assert(#kill == 2 and kill[1] == 3244 and #talk == 0)
kill, talk = Steps:NPCs(k[4])
assert(#kill == 1 and kill[1] == 3267 and #talk == 1 and talk[1] == 3448, "a quest objective's kill list and its npc are told apart")
kill, talk = Steps:NPCs(k[5])
assert(#kill == 0 and talk[1] == 3448)
kill, talk = Steps:NPCs(k[3])
assert(kill[1] == 3267 and #talk == 0, "kill targets on a collect step are targets")
assert(#Steps:NPCs(nil) == 0)

g = Steps:Goals(k[1])
assert(#g == 1 and g[1].verb == "kill" and plain(g[1]) == "Kill 3 Greater Plainstrider and Ornery Plainstrider" and g[1].kills.count == 3 and g[1].kills.npcs[2] == 3245 and roles(g[1]) == "count,monster,monster")
assert(Steps:KillCount(k[1]) == 0 and not Steps:HasTalkedTo(k[5], { 3448 }), "no progress module means no tally")
local tally, talked = {}, {}
ns.modules.Progress = {
    GetActiveGuide = function() return killed end,
    KillCount = function(_, _, stepIndex) return tally[stepIndex] or 0 end,
    HasTalked = function(_, _, stepIndex, npcID) return talked[stepIndex .. ":" .. npcID] == true end,
}
ns.modules.Client = { IsQuestInLog = function() return false end, IsQuestComplete = function() return false end, IsQuestReadyToTurnIn = function() return false end, IsQuestObjectiveComplete = function() return false end, GetQuestObjective = function() return nil end, GetItemCount = function() return 0 end, MatchesObservedCompletion = function() return false end }
status, progress = Steps:GoalStatus(g[1], k[1])
assert(status == "todo" and progress == "0/3", tostring(status) .. " " .. tostring(progress))
tally[1] = 2
status, progress = Steps:GoalStatus(g[1], k[1])
assert(status == "active" and progress == "2/3")
-- The number in front counts down: two of the three are dead, so one is left.
assert(Steps:Title(k[1]) == "Kill 1 Greater Plainstrider and Ornery Plainstrider (2/3)", Steps:Title(k[1]))
assert(Steps:Have(k[1]) == 2 and Steps:CountText(k[1]) == "1 ")
tally[1] = 5
status, progress = Steps:GoalStatus(g[1], k[1])
assert(status == "done" and progress == "3/3", "the tally never shows past the target")
-- Past the count the whole figure comes back, so no line ever reads "Kill 0".
assert(Steps:Title(k[1]) == "Kill 3 Greater Plainstrider and Ornery Plainstrider (3/3)", Steps:Title(k[1]))
assert(Steps:GoalStatus(Steps:Goals(k[2])[1], k[2]) == "todo" and select(2, Steps:GoalStatus(Steps:Goals(k[2])[1], k[2])) == nil, "a single kill has no fraction")
g = Steps:Goals(k[5])
assert(g[1].verb == "talk" and Steps:GoalStatus(g[1], k[5]) == nil, "an NPC not yet spoken to has no state")
talked["5:3448"] = true
-- The dialog is work under way, not work done: the quest is still not taken,
-- so the line goes amber rather than green.
assert(Steps:GoalStatus(g[1], k[5]) == "active", "talking to the NPC is not accepting the quest")
ns.modules.Progress, ns.modules.Client = nil, nil

-- Profession, gear, and reputation steps.
Names.items[2862] = "Rough Sharpening Stone"
Names.items[2901] = "Mining Pick"
Names.items[2770] = "Copper Ore"
Names.npcs[3357] = "Mining Trainer"
local trades = Steps:Expand({
    schema = 2, id = "test:trades", updated = 1789862400, map = 1413,
    meta = { title = "Trades", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { train = "Mining", npc = 3357, at = { 48.5, 59.3 } },
        { train = "Mining", rank = 75 },
        { skill = "Mining", rank = 150 },
        { craft = 2862, count = 5, skill = "Blacksmithing" },
        { skillup = 2862, skill = "Blacksmithing", rank = 100 },
        { gather = 2770, count = 20, skill = "Mining" },
        { buy = 2901, count = 2, npc = 3357 },
        { equip = 2901 },
        { reputation = 76, standing = "Honored" },
    } },
},
})
ok, errors = Schema:Validate(trades)
assert(ok, table.concat(errors, "; "))
local t = trades.nodes
assert(t[1].kind == "train" and t[1].completion.observed.type == "skill" and t[1].completion.observed.atLeast == 1, "learning a skill is rank 1")
assert(t[1].refs.npcs[1] == 3357 and t[1].location.arrivalRadiusNormalized == 0.02)
assert(Steps:Title(t[1]) == "Train Mining", Steps:Title(t[1]))
assert(t[2].completion.observed.atLeast == 75 and Steps:Title(t[2]) == "Train Mining to 75")
assert(t[3].kind == "skillTarget" and Steps:Title(t[3]) == "Raise Mining to 150", Steps:Title(t[3]))
assert(t[4].kind == "craft" and t[4].completion.observed.type == "crafted" and t[4].completion.observed.count == 5)
assert(t[4].refs.items[1] == 2862, "the crafted item is referenced")
assert(Steps:Title(t[4]) == "Craft 5 Rough Sharpening Stone using Blacksmithing", Steps:Title(t[4]))
-- Crafting to a rank: the skill is the goal, the item only the means.
assert(t[5].kind == "skillUp" and t[5].completion.observed.type == "skill" and t[5].completion.observed.atLeast == 100)
assert(t[5].refs.items[1] == 2862 and Steps:Title(t[5]) == "Craft Rough Sharpening Stone until Blacksmithing 100", Steps:Title(t[5]))
assert(not pcall(Steps.Expand, Steps, { steps = {
    { skillup = 2862, rank = 100 }
} }), "skillup needs a profession")
assert(not pcall(Steps.Expand, Steps, { steps = {
    { skillup = 2862, skill = "Blacksmithing" }
} }), "skillup needs a rank")
-- Gathering is its own verb: the same detector as a purchase, its own word.
assert(t[6].kind == "gather" and t[6].completion.observed.type == "item" and t[6].completion.observed.count == 20)
assert(Steps:Title(t[6]) == "Gather 20 Copper Ore with Mining", Steps:Title(t[6]))
assert(t[7].kind == "buy" and t[7].completion.observed.type == "item" and t[7].completion.observed.count == 2)
assert(Steps:Title(t[7]) == "Buy 2 Mining Pick from Mining Trainer", Steps:Title(t[7]))
assert(t[8].kind == "equip" and t[8].completion.observed.type == "equipped" and Steps:Title(t[8]) == "Equip Mining Pick")
assert(t[9].kind == "reputationTarget" and t[9].completion.observed.standing == 6, "Honored is standing 6")
assert(Steps:Title(t[9]) == "Reach Honored with Orgrimmar", Steps:Title(t[9]))
assert(not pcall(Steps.Expand, Steps, { steps = {
    { skill = "Mining" }
} }), "a skill step needs a rank")
assert(not pcall(Steps.Expand, Steps, { steps = {
    { reputation = 76, standing = "Chummy" }
} }), "an unknown standing is refused")
-- `craft` wins over `skill` when a step names both.
local both = Steps:Expand({ schema = 2, id = "t", updated = 1789862400, meta = { title = "t", category = "test" }, steps = {
    { section = "Steps", steps = {
        { craft = 2862, skill = "Blacksmithing", count = 1 }
    } },
} })
assert(both.nodes[1].kind == "craft", both.nodes[1].kind)

-- Goal lines read the live client.
local rank, standing, equipped, crafted, bags = nil, nil, false, 0, {}
ns.modules.Progress = {
    GetActiveGuide = function() return trades end,
    CraftCount = function() return crafted end,
}
ns.modules.Client = {
    GetSkillRank = function(_, name) return rank, name == "Mining" and 300 or nil end,
    GetFactionStanding = function() return standing, 2400, 6000 end,
    IsItemEquipped = function() return equipped end,
    GetItemCount = function(_, id) return bags[id] or 0 end,
}
local trainGoal = Steps:Goals(t[3])[1]
rank = nil
assert(trainGoal.verb == "skill" and Steps:GoalStatus(trainGoal, t[3]) == "todo", "a skill the player does not have is not started")
rank = 73
status, progress = Steps:GoalStatus(trainGoal, t[3])
assert(status == "active" and progress == "73/150", tostring(progress))
rank = 150
assert(Steps:GoalStatus(trainGoal, t[3]) == "done")
local craftGoal = Steps:Goals(t[4])[1]
assert(Steps:GoalStatus(craftGoal, t[4]) == "todo")
crafted = 3
status, progress = Steps:GoalStatus(craftGoal, t[4])
assert(status == "active" and progress == "3/5")
crafted, bags[2862] = 0, 5
assert(Steps:GoalStatus(craftGoal, t[4]) == "done", "a full stack in the bags proves the crafting")
-- A craft-to-a-rank step reads the rank, not the output.
rank = 73
local skillUpGoal = Steps:Goals(t[5])[1]
assert(skillUpGoal.verb == "craft", "it still wears the craft icon")
status, progress = Steps:GoalStatus(skillUpGoal, t[5])
assert(status == "active" and progress == "73/100", tostring(progress))
rank = 100
assert(Steps:GoalStatus(skillUpGoal, t[5]) == "done", "the rank finishes it, however many were made")
local gatherGoal = Steps:Goals(t[6])[1]
assert(gatherGoal.verb == "gather" and Steps:GoalStatus(gatherGoal, t[6]) == "todo")
bags[2770] = 20
assert(Steps:GoalStatus(gatherGoal, t[6]) == "done", "bought at the auction house counts the same as picked")
local equipGoal = Steps:Goals(t[8])[1]
bags[2901] = 1
assert(Steps:GoalStatus(equipGoal, t[8]) == "active", "carried but not worn")
equipped = true
assert(Steps:GoalStatus(equipGoal, t[8]) == "done")
local repGoal = Steps:Goals(t[9])[1]
assert(Steps:GoalStatus(repGoal, t[9]) == "todo", "no standing yet")
standing = 5
status, progress = Steps:GoalStatus(repGoal, t[9])
assert(status == "active" and progress == "Friendly 2400/6000", tostring(progress))
standing = 7
assert(Steps:GoalStatus(repGoal, t[9]) == "done", "past the target standing counts")
ns.modules.Progress, ns.modules.Client = nil, nil

-- Materials ride on any step, and the source defaults to gathering.
local withNeeds = Steps:Expand({
    schema = 2, id = "test:needs", updated = 1789862400, map = 1413,
    meta = { title = "Needs", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { craft = 2862, count = 5, needs = { { 2835, 5 }, { 2589, 2, "ah" } } }, { travel = "Ratchet", at = { 63, 37 } }
    } },
},
})
ok, errors = Schema:Validate(withNeeds)
assert(ok, table.concat(errors, "; "))
local needy = withNeeds.nodes[1]
assert(#needy.needs == 2 and needy.needs[1].source == "gather" and needy.needs[2].source == "ah")
assert(needy.needs[1].itemID == 2835 and needy.needs[1].count == 5)
assert(#needy.refs.items == 3, "the materials join the step's item references")
assert(withNeeds.nodes[2].needs == nil)
assert(not pcall(Steps.Expand, Steps, { steps = {
    { travel = "x", needs = "Rough Stone" }
} }), "needs is a list")

-- `upto`: the profession rank that makes a materials step moot.
Names.items[2835] = "Rough Stone"
local escapes = Steps:Expand({
    schema = 2, id = "test:upto", updated = 1789862400, map = 1413,
    meta = { title = "Upto", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { gather = 2770, count = 20, skill = "Mining", upto = 150 },
        { gather = 2835, count = 40, upto = { "Blacksmithing", 100 } },
        { buy = 2320, count = 10, skill = "Tailoring", upto = 60 },
    } },
},
})
ok, errors = Schema:Validate(escapes)
assert(ok, table.concat(errors, "; "))
local e = escapes.nodes
assert(e[1].completion.observed.type == "any", "the escape is an any-of completion")
assert(e[1].completion.observed.children[1].type == "item" and e[1].completion.observed.children[2].type == "skill")
assert(e[1].auto.upto.skill == "Mining" and e[1].auto.upto.rank == 150, "a bare rank means the step's own profession")
assert(e[2].auto.upto.skill == "Blacksmithing" and e[2].auto.upto.rank == 100, "a pair names another profession")
assert(e[3].auto.upto.skill == "Tailoring" and e[3].auto.upto.rank == 60)
assert(not pcall(Steps.Expand, Steps, { steps = {
    { gather = 2770, upto = 100 }
} }), "no profession to fall back on")
assert(not pcall(Steps.Expand, Steps, { steps = {
    { gather = 2770, skill = "Mining", upto = { "Mining" } }
} }), "a pair still needs its rank")
assert(not pcall(Steps.Expand, Steps, { steps = {
    { note = "text", upto = { "Mining", 10 } }
} }), "a manual step has nothing to escape from")

rank, bags = nil, {}
ns.modules.Client = {
    GetSkillRank = function(_, name) return name == "Mining" and rank or nil end,
    GetItemCount = function(_, id) return bags[id] or 0 end,
    HasSkillRank = function(self, name, atLeast) local have = self:GetSkillRank(name); return have ~= nil and have >= atLeast end,
}
local escapeGoal = Steps:Goals(e[1])[1]
assert(Steps:GoalText(escapeGoal) == "Gather 20 Copper Ore with Mining or Mining 150", Steps:GoalText(escapeGoal))
assert(Steps:GoalStatus(escapeGoal, e[1]) == "todo")
bags[2770] = 20
assert(Steps:GoalStatus(escapeGoal, e[1]) == "done", "the ore finishes it")
bags[2770] = 0
rank = 150
assert(Steps:GoalStatus(escapeGoal, e[1]) == "done", "so does the rank, with no ore at all")
ns.modules.Client = nil

-- `use`: the item the step asks the player to press, which is not always the
-- item the step counts. The Bael'dun step counts Broken Tools and presses
-- Prospector's Picks.
local used = Steps:Expand({
    schema = 2, id = "test:use", updated = 1789862400, map = 1412,
    meta = { title = "Use", category = "test" },
    steps = { { section = "Digsite", steps = {
        { objective = 746, part = 1, collect = 4703, count = 5, kill = { 2989, 2990 }, use = 4702 },
        { note = "Smash them.", use = { 4702, 4851 } },
        { travel = "Camp", at = { 30, 40 } },
    } } },
})
assert(Schema:Validate(used))
assert(#used.nodes[1].use == 1 and used.nodes[1].use[1] == 4702, "the pressed item is kept apart from the counted one")
-- It joins the step's item references, so the audit and the names table see
-- it, without displacing the item the step counts.
assert(used.nodes[1].refs.items[1] == 4703 and used.nodes[1].refs.items[2] == 4702)
assert(#used.nodes[2].use == 2 and used.nodes[2].use[2] == 4851, "a step may press more than one item")
assert(used.nodes[3].use == nil, "a step that presses nothing carries no list")
-- An item step that names its killers says where the item drops: the name of
-- a quest item on its own leaves the player with nowhere to go for it.
local sourced = Steps:Goals(used.nodes[1])[1]
assert(Steps:GoalText(sourced) == "Use Prospector's Pick from Bael'dun Digger and Bael'dun Appraiser, and Collect 5 Broken Tools", Steps:GoalText(sourced))
local sourceRoles = {}
for _, piece in ipairs(sourced.parts) do if piece.role ~= "plain" then table.insert(sourceRoles, piece.role) end end
assert(table.concat(sourceRoles, ",") == "item,monster,monster,count,item", table.concat(sourceRoles, ","))
assert(#Steps:Goals(used.nodes[1]) == 1, "the press stays on the count's own line")

-- The same for an item that comes out of something on the ground, and for an
-- objective that is really a conversation: both are authored on the step, and
-- both used to be dropped from the line.
local sourced2 = Steps:Expand({
    schema = 2, id = "test:sources", updated = 1789862400, map = 1413,
    meta = { title = "Sources", category = "test" },
    steps = { { section = "Pools", steps = {
        { objective = 848, part = 1, collect = 5012, count = 4, object = "Laden Mushroom", at = { 44, 23 } },
        { objective = 5930, part = 1, npc = 11956, at = { 39, 27 } },
        { collect = 4926, starts = 819, object = "Chen's Empty Keg", at = { 55, 20 } },
    } } },
})
assert(Schema:Validate(sourced2))
local fromObject = Steps:Goals(sourced2.nodes[1])[1]
assert(Steps:GoalText(fromObject) == "Collect 4 Fungal Spores from Laden Mushroom", Steps:GoalText(fromObject))
assert(Steps:Title(sourced2.nodes[1], true) == "Collect 4 Fungal Spores from Laden Mushroom", Steps:Title(sourced2.nodes[1], true))
local talkGoal = Steps:Goals(sourced2.nodes[2])[1]
assert(talkGoal.verb == "talk" and Steps:GoalText(talkGoal) == "Talk to Great Bear Spirit", Steps:GoalText(talkGoal))
assert(talkGoal.objective and talkGoal.objective.quest == 5930, "the objective still decides when it is done")
-- A collect step of its own already says where it is with "at", so the object
-- is not said twice.
assert(Steps:GoalText(Steps:Goals(sourced2.nodes[3])[1]) == "Collect Chen's Empty Keg at Chen's Empty Keg",
    Steps:GoalText(Steps:Goals(sourced2.nodes[3])[1]))
-- It does not change the completion rule -- pressing is the player's
-- business, and the step is still judged by its own objective -- but the
-- count line leads with the press, since smashing the picks is what yields
-- the tools, and on the Lunaclaw step the press is what summons the target.
-- The creatures drop what is pressed, not what is counted: the diggers carry
-- the picks, and the tools only come off the forge.
assert(Steps:Title(used.nodes[1], true) == "Use Prospector's Pick from Bael'dun Digger and Bael'dun Appraiser, and Collect 5 Broken Tools", Steps:Title(used.nodes[1], true))
assert(used.nodes[1].completion.observed.type == "objective")
assert(not pcall(Steps.Expand, Steps, { schema = 2, id = "x", updated = 1, meta = { title = "x", category = "t" },
    steps = { { section = "s", steps = { { note = "n", use = "Prospector's Pick" } } } } }), "use names items by ID")
local badUse = { schema = 2, id = "x", updated = 1, meta = { title = "x", category = "t" },
    sections = { { id = "s", title = "s", nodeIndexes = { 1 } } },
    nodes = { { index = 1, kind = "note", title = "n", completion = { type = "manual" }, use = { 0 } } } }
local okUse, useErrors = Schema:Validate(badUse)
assert(not okUse and table.concat(useErrors, ";"):find("use[1]", 1, true), table.concat(useErrors, ";"))

-- An objective the player meets by pressing something often has no objective
-- line for the client to read - a well is cleansed, nothing is counted. With
-- nothing to count and nothing to kill, the item the author named to press is
-- the instruction, ahead of the client's own line and of the quest's name and
-- an index. A step that counts something keeps its count.
local pressed = Steps:Expand({
    schema = 2, id = "test:press", updated = 1789862400, map = 1412,
    meta = { title = "Press", category = "test" },
    steps = { { section = "Well", steps = {
        { objective = 758, part = 1, item = 5415, use = 5415, at = { 44.49, 45.36 } },
        { objective = 759, part = 1, at = { 44.49, 45.36 } },
    } } },
})
assert(Steps:Title(pressed.nodes[1], true) == "Use Thunderhorn Cleansing Totem", Steps:Title(pressed.nodes[1], true))
local pressedGoal = Steps:Goals(pressed.nodes[1])[1]
assert(pressedGoal.verb == "use", pressedGoal.verb)
assert(pressedGoal.useItem == 5415, "the line carries the item so the tracker can show its own icon")
assert(pressedGoal.objective.quest == 758 and pressedGoal.objective.index == 1, "it is still the quest objective that finishes the step")
-- The item is a part of its own, so the tracker can paint it as a link.
assert(pressedGoal.parts[2].role == "item" and pressedGoal.parts[2].id == 5415)
-- A step with nothing to press keeps the old fallback.
assert(Steps:Title(pressed.nodes[2], true):find(", objective 1", 1, true), Steps:Title(pressed.nodes[2], true))

-- One creature under two IDs (a copy per phase) is named once.
Names.npcs[251314] = "Skyhopper"; Names.npcs[251727] = "Skyhopper"
local twins = Steps:Expand({
    schema = 2, id = "test:twins", updated = 1789862400, map = 2521, meta = { title = "Twins", category = "test" },
    steps = { { section = "Steps", steps = { { kill = { 251314, 251727 }, count = 8, at = { 60, 75 } } } } },
})
assert(Steps:Title(twins.nodes[1], true) == "Kill 8 Skyhopper", Steps:Title(twins.nodes[1], true))

-- Class spells from a trainer: done once every spell is known. A cast step
-- counts the casts made while the guide is on it.
Names.spells[100] = "Charge"; Names.spells[772] = "Rend"; Names.spells[1259686] = "Skysight"
Names.npcs[251964] = "Blademaster Ren"
local spells = Steps:Expand({
    schema = 2, id = "test:spells", updated = 1789862400, map = 2521, meta = { title = "Spells", category = "test" },
    steps = { { section = "Steps", steps = {
        { learn = { 100, 772 }, npc = 251964, at = { 43.66, 24.14 } },
        { cast = 1259686, at = { 35.91, 33.61 } },
        { cast = 1259686, count = 3 },
    } } },
})
ok, errors = Schema:Validate(spells)
assert(ok, table.concat(errors, "; "))
local learnNode, castNode, castThrice = spells.nodes[1], spells.nodes[2], spells.nodes[3]
assert(learnNode.kind == "train" and learnNode.completion.observed.type == "spell", learnNode.completion.observed.type)
assert(learnNode.completion.observed.ids[2] == 772 and learnNode.location.arrivalRadiusNormalized == 0.02)
assert(Steps:Title(learnNode, true) == "Train Charge and Rend from Blademaster Ren", Steps:Title(learnNode, true))
assert(castNode.kind == "cast" and castNode.completion.observed.type == "cast" and castNode.completion.observed.spellID == 1259686)
assert(castNode.completion.observed.count == 1, "one cast unless the step says more")
assert(Steps:Title(castNode, true) == "Cast Skysight", Steps:Title(castNode, true))
assert(Steps:Title(castThrice, true) == "Cast Skysight 3 times", Steps:Title(castThrice, true))
assert(not pcall(Steps.Expand, Steps, { steps = { { section = "s", steps = { { learn = "Charge" } } } } }), "learn names spells by ID")
assert(not pcall(Steps.Expand, Steps, { steps = { { section = "s", steps = { { cast = { 1, 2 } } } } } }), "cast names one spell")
local known, casts = {}, 0
ns.modules.Progress = { GetActiveGuide = function() return spells end, CastCount = function() return casts end }
ns.modules.Client = { IsSpellKnown = function(_, id) return known[id] == true end }
local learnGoal = Steps:Goals(learnNode)[1]
assert(learnGoal.verb == "train" and Steps:GoalStatus(learnGoal, learnNode) == "todo")
known[100] = true
status, progress = Steps:GoalStatus(learnGoal, learnNode)
assert(status == "active" and progress == "1/2", tostring(progress))
known[772] = true
assert(Steps:GoalStatus(learnGoal, learnNode) == "done")
-- Spell names are painted as names: an id on the part would link an item.
for _, piece in ipairs(learnGoal.parts) do assert(piece.id == nil, "no item link for a spell") end
local castGoal = Steps:Goals(castThrice)[1]
assert(castGoal.verb == "use" and Steps:GoalStatus(castGoal, castThrice) == "todo")
casts = 2
status, progress = Steps:GoalStatus(castGoal, castThrice)
assert(status == "active" and progress == "2/3", tostring(progress))
casts = 3
assert(Steps:GoalStatus(castGoal, castThrice) == "done")

-- ApplyCarried: the carried half of a completion follows companionOf, and the
-- step's own completion survives whole. An `any` of the step's own (an item
-- or a rank, from `upto`) keeps both children; OpenRoad kept only the last.
local item = { type = "item", itemID = 2318, count = 10 }
local rank = { type = "skill", name = "Leatherworking", atLeast = 50 }
local node = { index = 4, completion = { type = "observed", observed = { type = "any", children = { item, rank } } } }
Steps:ApplyCarried(node)
local own = node.completion.observed
assert(own.type == "any" and #own.children == 2 and own.children[1] == item and own.children[2] == rank, "both halves of upto kept")
node.companionOf = 2
Steps:ApplyCarried(node)
local carried = node.completion.observed
assert(carried.type == "any" and #carried.children == 2 and carried.children[1].type == "any"
    and carried.children[2].type == "step" and carried.children[2].index == 2, "carried alongside step 2")
assert(#carried.children[1].children == 2, "with the step's own whole")
node.companionOf = 3
Steps:ApplyCarried(node)
assert(node.completion.observed.children[2].index == 3 and #node.completion.observed.children[1].children == 2, "carried by another step")
node.companionOf = nil
Steps:ApplyCarried(node)
own = node.completion.observed
assert(own.type == "any" and #own.children == 2 and own.children[1] == item, "no longer carried: its own again")
local single = { index = 5, companionOf = 1, completion = { type = "observed", observed = item } }
Steps:ApplyCarried(single)
single.companionOf = nil
Steps:ApplyCarried(single)
assert(single.completion.observed == item, "a single completion round-trips")
local onlyCarried = { index = 6, companionOf = 1, completion = { type = "manual" } }
Steps:ApplyCarried(onlyCarried)
assert(onlyCarried.completion.observed.type == "step")
onlyCarried.companionOf = nil
Steps:ApplyCarried(onlyCarried)
assert(onlyCarried.completion.type == "manual", "nothing of its own: manual")

return true
