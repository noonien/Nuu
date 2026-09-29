_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/GuideScan.lua")
local Steps, Progress, GuideScan = ns.modules.Steps, ns.modules.Progress, ns.modules.GuideScan

-- Game state the scan is allowed to read back.
local game = { inLog = {}, completed = {}, readyToTurnIn = {}, objectives = {}, level = 1, items = {} }
ns.modules.Client = {
    IsQuestInLog = function(_, id) return game.inLog[id] == true end,
    IsQuestComplete = function(_, id) return game.completed[id] == true end,
    IsQuestReadyToTurnIn = function(_, id) return game.readyToTurnIn[id] == true end,
    IsQuestMoot = function(self, id)
        -- The real client answers no until it has handed over a quest log.
        if not game.questLogRead then return false end
        return not self:IsQuestInLog(id) and not self:IsQuestComplete(id)
    end,
    IsQuestObjectiveComplete = function(self, id, index)
        if self:IsQuestComplete(id) or self:IsQuestReadyToTurnIn(id) then return true end
        return game.objectives[tostring(id) .. "/" .. tostring(index)] == true
    end,
    MatchesObservedCompletion = function(_, observed)
        if observed.type == "level" then return game.level >= (observed.atLeast or 0) end
        if observed.type == "hearth" then return observed.name == game.hearth end
        return false
    end,
}

local guide = Steps:Expand({
    schema = 2, id = "test:scan", updated = 1789862400, map = 1413,
    meta = { title = "Scan", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 870, npc = 3448, at = { 52, 31 } },   -- 1 accepted long ago, quest turned in
        { travel = "Ratchet", at = { 63, 37 } },         -- 2 nothing durable to read
        { objective = 870, part = 1, kill = 3267, count = 8 }, -- 3 quest turned in
        { turnin = 870, npc = 3448, at = { 52, 31 } },   -- 4 turned in
        { accept = 871, npc = 3448, at = { 52, 31 } },   -- 5 in the log now
        { objective = 871, part = 1, at = { 55, 25 } },  -- 6 objective line finished, quest not turned in
        { objective = 871, part = 2, at = { 55, 25 } },  -- 7 still outstanding
        { objectives = { 871 }, at = { 55, 25 } },       -- 8 outstanding
        { kill = 3267, count = 5, at = { 55, 25 } },     -- 9
        { level = 17 },                                  -- 10
        { finish = "The end." },
    } },
},
})
assert(select(1, ns.modules.Schema:Validate(guide)), "fixture guide must validate")
local byIndex = guide.nodes

Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }

game.completed[870] = true
game.inLog[871] = true
game.objectives["871/1"] = true

-- A quest already handed in proves the accept, the objective, and the turn-in.
assert(GuideScan:NodeCompleted(byIndex[1]), "an accept step is done once the quest was ever accepted")
assert(GuideScan:NodeCompleted(byIndex[3]), "an objective of a turned-in quest is done")
assert(GuideScan:NodeCompleted(byIndex[4]), "a turn-in step is done once the quest is flagged complete")
-- A quest still in the log proves the accept and each finished objective line.
assert(GuideScan:NodeCompleted(byIndex[5]), "an accept step is done while the quest sits in the log")
assert(GuideScan:NodeCompleted(byIndex[6]), "a finished objective line counts before the quest is turned in")
assert(not GuideScan:NodeCompleted(byIndex[7]), "an unfinished objective line is not done")
assert(not GuideScan:NodeCompleted(byIndex[8]), "a quest that is not ready to turn in is not done")
-- Nothing durable backs these, so the scan never claims them.
assert(not GuideScan:NodeCompleted(byIndex[2]), "the player's position says nothing about an earlier walk")
assert(not GuideScan:NodeCompleted(byIndex[9]), "session kill counters say nothing about earlier kills")
assert(not GuideScan:NodeCompleted(byIndex[10]), "level 1 has not reached the level target")

Progress:Select(guide)
local node, state = Progress:GetCurrentNode(guide)
assert(node.index == byIndex[7].index, "the guide resumes on the first step that is still outstanding")
assert(state.statuses[byIndex[1].index] == "observed" and state.statuses[byIndex[6].index] == "observed")
assert(state.statuses[byIndex[2].index] == "skipped", "a step the scan cannot prove is recorded as skipped, never as done")
assert(Progress:CompletedCount(state) == 5, "five steps were proved done")
assert(not Progress:IsHeld(guide), "the resumed step is free to advance on its own")

-- Back still walks every step the scan passed over.
assert(Progress:Back(guide) and (Progress:GetCurrentNode(guide)).index == byIndex[6].index)
assert(Progress:Forward(guide, true) and (Progress:GetCurrentNode(guide)).index == byIndex[7].index)

-- What the tracker paints: the game's own answer for steps ahead of the player.
assert(GuideScan:IsStepDone(guide, byIndex[6], state), "a step behind the player stays checked")
assert(not GuideScan:IsStepDone(guide, byIndex[8], state))
game.readyToTurnIn[871] = true
assert(GuideScan:IsStepDone(guide, byIndex[8], state), "an upcoming step the game reports done is checked")

-- A second scan moves on to what has since been proved, and no further.
game.completed[871] = true
assert(GuideScan:Apply(guide) == 2, "the last objective and the objective group, and nothing past the kill step")
assert((Progress:GetCurrentNode(guide)).index == byIndex[10].index,
    "the kill step the client keeps no record of does not hold the resume point, the level target does")
assert(state.statuses[byIndex[9].index] == "skipped", "the step passed over is recorded as skipped, not as done")

-- A step landed on by plain BACK or SKIP is left alone.
assert(Progress:Back(guide) and Progress:IsHeld(guide))
assert(GuideScan:Apply(guide) == 0, "a held step is never scanned past")
assert(Progress:Back(guide) and Progress:Forward(guide, true) and not Progress:IsHeld(guide), "a Shift move lands without the hold")

-- Level targets are read back from the client, kills are not.
game.level = 20
assert(GuideScan:NodeCompleted(byIndex[10]), "a level target the player has passed is done")

-- An outstanding step stops the resume even when finished steps lie past it:
-- the guide opens on the first step still to do, never on the last one done.
local outOfOrder = Steps:Expand({
    schema = 2, id = "test:scan-order", updated = 1789862400, map = 1413,
    meta = { title = "Out of order", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 900, npc = 3448, at = { 52, 31 } },  -- 1 done
        { travel = "Ratchet", at = { 63, 37 } },        -- 2 no record either way
        { accept = 901, npc = 3448, at = { 52, 31 } },  -- 3 never accepted: outstanding
        { turnin = 900, npc = 3448, at = { 52, 31 } },  -- 4 done out of order
        { level = 17 },                                 -- 5
    } },
},
})
ns.modules.GuideRepository = { Get = function(_, id)
    if id == guide.id then return guide end
    return id == outOfOrder.id and outOfOrder or nil
end }
Progress.store, Progress.session = {}, {}
game.completed[900] = true
Progress:Select(outOfOrder)
local resumed, outState = Progress:GetCurrentNode(outOfOrder)
assert(resumed.index == outOfOrder.nodes[3].index, "the resume point is the first step still to do")
assert(outState.statuses[outOfOrder.nodes[2].index] == "skipped")
assert(outState.statuses[outOfOrder.nodes[4].index] == nil, "a finished step past the resume point is left to the tracker to paint")
assert(GuideScan:IsStepDone(outOfOrder, outOfOrder.nodes[4], outState), "and the tracker does paint it done")
assert(GuideScan:BlocksResume(outOfOrder.nodes[3]) and not GuideScan:BlocksResume(outOfOrder.nodes[2]))

-- A collect step tied to a quest is judged through the quest log: an item
-- that begins a quest holds the resume point until the quest was accepted,
-- and a quest item is moot when the player has no such quest - which holds
-- the resume point too, since the player may still pick the quest up.
local items = Steps:Expand({
    schema = 2, id = "test:scan-items", updated = 1789862400, map = 1413,
    meta = { title = "Items", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { turnin = 905, npc = 3448, at = { 52, 31 } },                             -- 1 done
        { collect = 4926, starts = 819, object = "Chen's Empty Keg", at = { 55, 20 } }, -- 2 keg not found, quest never taken
        { accept = 819 },                                                          -- 3 outstanding
        { collect = 4986, quest = 924, at = { 62, 20 } },                          -- 4 quest item, no such quest
        { accept = 906, npc = 3448, at = { 52, 31 } },                             -- 5 outstanding
    } },
},
})
ns.modules.GuideRepository = { Get = function(_, id) return id == items.id and items or nil end }
Progress.store, Progress.session = {}, {}
game.questLogRead = true
game.completed[905] = true
assert(GuideScan:BlocksResume(items.nodes[2]), "an item that begins a quest is outstanding work until the quest was accepted")
assert(not GuideScan:NodeIsMoot(items.nodes[2]), "and never moot")
assert(GuideScan:NodeIsMoot(items.nodes[4]), "a quest item for a quest the player does not have is moot")
assert(GuideScan:BlocksResume(items.nodes[4]), "a quest the player does not have is waited on, not passed")
Progress:Select(items)
local itemNode, itemState = Progress:GetCurrentNode(items)
assert(itemNode.index == items.nodes[2].index, "the guide resumes on the keg, not on the accept step after it")
assert(itemState.statuses[items.nodes[1].index] == "observed")
game.inLog[819] = true
assert(GuideScan:NodeCompleted(items.nodes[2]), "the keg is done once its quest is in the log")
assert(GuideScan:Apply(items) == 2, "the keg and the accept are proven")
assert((Progress:GetCurrentNode(items)).index == items.nodes[4].index, "the guide waits on the moot quest item")
assert(itemState.statuses[items.nodes[4].index] == nil, "and records nothing on it")
game.inLog[924] = true
assert(not GuideScan:NodeIsMoot(items.nodes[4]) and GuideScan:BlocksResume(items.nodes[4]), "with the quest in the log the item is outstanding work")
game.readyToTurnIn[924] = true
assert(GuideScan:NodeCompleted(items.nodes[4]), "and done once the quest is ready to hand in")
game.questLogRead = nil

-- Shift-SKIP releases the step it lands on and runs the scan from there: a
-- travel step skipped onto, with the quest at its destination already in the
-- log, is passed over to the first step still to do. Plain SKIP holds instead.
local settle = Steps:Expand({
    schema = 2, id = "test:scan-settle", updated = 1789862400, map = 1413,
    meta = { title = "Settle", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 910, npc = 3448, at = { 52, 31 } },  -- 1 never accepted: outstanding
        { travel = "Orgrimmar", at = { 63, 37 } },      -- 2 no record either way
        { accept = 911, npc = 3448, at = { 52, 31 } },  -- 3 in the log
        { objective = 911, part = 1, at = { 55, 25 } }, -- 4 outstanding
    } },
},
})
ns.modules.GuideRepository = { Get = function(_, id) return id == settle.id and settle or nil end }
Progress.store, Progress.session = {}, {}
game.inLog[911] = true
Progress:Select(settle)
assert((Progress:GetCurrentNode(settle)).index == settle.nodes[1].index, "an outstanding first step holds the resume")
assert(Progress:Forward(settle) and Progress:IsHeld(settle), "plain SKIP holds the step it lands on")
assert(GuideScan:Apply(settle) == 0, "and the scan leaves a held step alone")
assert(Progress:Back(settle, true) and Progress:Forward(settle, true) and not Progress:IsHeld(settle), "Shift-SKIP releases it")
assert(GuideScan:Apply(settle) == 1, "the scan run after Shift-SKIP proves the accept past the travel step")
local settled, settleState = Progress:GetCurrentNode(settle)
assert(settled.index == settle.nodes[4].index, "the travel step is passed over to the first step still to do")
assert(settleState.statuses[settle.nodes[2].index] == "skipped" and settleState.statuses[settle.nodes[3].index] == "observed")

-- The hearthstone keeps one binding and no history, so a hearth step is read
-- positively only: the step matching the current binding is done, earlier
-- hearth steps are passed over as superseded, and a later matching step is
-- contained by the first outstanding quest step before it.
local hearths = Steps:Expand({
    schema = 2, id = "test:scan-hearth", updated = 1789862400, map = 1413,
    meta = { title = "Hearths", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { hearth = "The Crossroads", npc = 3934, at = { 52, 30 } }, -- 1
        { accept = 920, npc = 3448, at = { 52, 31 } },              -- 2 done
        { hearth = "Camp Taurajo", npc = 7714, at = { 45, 59 } },   -- 3
        { accept = 921, npc = 3448, at = { 52, 31 } },              -- 4 in the log
        { objective = 921, part = 1, at = { 55, 25 } },             -- 5 outstanding
        { hearth = "The Crossroads", npc = 3934, at = { 52, 30 } }, -- 6
        { accept = 922, npc = 3448, at = { 52, 31 } },              -- 7
    } },
},
})
ns.modules.GuideRepository = { Get = function(_, id) return id == hearths.id and hearths or nil end }
game.completed[920], game.inLog[921] = true, true
Progress.store, Progress.session = {}, {}
game.hearth = "Camp Taurajo"
Progress:Select(hearths)
local hearthNode, hearthState = Progress:GetCurrentNode(hearths)
assert(hearthNode.index == hearths.nodes[5].index, "the guide resumes on the outstanding objective")
assert(hearthState.statuses[hearths.nodes[1].index] == "skipped", "a binding since replaced is passed over, never claimed")
assert(hearthState.statuses[hearths.nodes[3].index] == "observed", "the step matching the current binding is done")
assert(hearthState.statuses[hearths.nodes[6].index] == nil, "nothing past the resume point is touched")
Progress.store, Progress.session = {}, {}
game.hearth = "The Crossroads"
Progress:Select(hearths)
hearthNode, hearthState = Progress:GetCurrentNode(hearths)
assert(hearthNode.index == hearths.nodes[5].index)
assert(hearthState.statuses[hearths.nodes[1].index] == "observed", "the first Crossroads binding is proven")
assert(hearthState.statuses[hearths.nodes[3].index] == "skipped", "an unmatched hearth step never holds the resume point")
assert(hearthState.statuses[hearths.nodes[6].index] == nil, "the later Crossroads step is contained by the outstanding objective")

-- A step the client cannot judge reads as settled once the first decidable
-- step after it is proven, even while the player is held on it; an outstanding
-- quest in between keeps it open.
Progress.store, Progress.session = {}, {}
Progress:Select(settle)
assert(Progress:Forward(settle) and Progress:IsHeld(settle))
assert((Progress:GetCurrentNode(settle)).index == settle.nodes[2].index, "held on the travel step after a plain SKIP")
assert(GuideScan:Settled(settle, settle.nodes[2]), "the travel step is settled by the accept already in the log")
assert(GuideScan:IsStepDone(settle, settle.nodes[2], Progress:GetState(settle)), "and the tracker paints it done")
assert(not GuideScan:Settled(settle, settle.nodes[1]), "an outstanding accept is never settled: it is decidable")
assert(not GuideScan:Settled(settle, settle.nodes[4]), "nothing proven follows the last objective")
game.inLog[911] = nil
assert(not GuideScan:Settled(settle, settle.nodes[2]), "with the accept outstanding the travel step stays open")
assert(not GuideScan:Settled(outOfOrder, outOfOrder.nodes[2]),
    "a travel step followed by an outstanding accept is not settled by the turn-in past it")

-- A step whose quest the player never took, or abandoned, cannot be done as
-- things stand. The scan refuses to guess before the client has handed over a
-- quest log.
local dropped = Steps:Expand({
    schema = 2, id = "test:scan-moot", updated = 1789862400, map = 1413,
    meta = { title = "Moot", category = "test" },
    steps = {
    { section = "Steps", steps = {
        { accept = 930, npc = 3448, at = { 52, 31 } },                -- 1 never accepted: outstanding
        { turnin = 931, npc = 3448, at = { 52, 31 } },                -- 2 never taken: moot
        { objective = 931, part = 1, at = { 55, 25 } },               -- 3 moot as well
        { turnin = 932, accept = 933, npc = 3448, at = { 52, 31 } },  -- 4 the turn-in is moot, the accept is not
        { turnin = { 934, 935 }, npc = 3448, at = { 52, 31 } },       -- 5 one moot, one still to hand in
        { objectives = { 936 }, any = 937, at = { 55, 25 } },         -- 6 either quest would do; both moot
        { level = 30 },                                               -- 7 out of reach
    } },
},
})
local d = dropped.nodes
assert(not GuideScan:NodeIsMoot(d[2]), "nothing is moot before the quest log can be read")
game.questLogRead = true
assert(not GuideScan:NodeIsMoot(d[1]), "an accept step is never moot: the quest is there to be taken")
assert(GuideScan:NodeIsMoot(d[2]), "a turn-in for a quest the player does not have is moot")
assert(GuideScan:NodeIsMoot(d[3]), "so is an objective of it")
assert(not GuideScan:NodeIsMoot(d[4]), "a visit with a quest still to accept is never passed over")
game.inLog[933] = true
assert(GuideScan:NodeIsMoot(d[4]), "once the quest is accepted nothing is left on that step")
game.inLog[935] = true
assert(not GuideScan:NodeIsMoot(d[5]), "a turn-in the player can still make holds the step")
game.completed[935] = true
game.inLog[935] = nil
assert(GuideScan:NodeIsMoot(d[5]), "with the other quest handed in the step is moot")
assert(GuideScan:NodeIsMoot(d[6]), "an either-or step is moot only when neither quest is the player's")
game.inLog[937] = true
assert(not GuideScan:NodeIsMoot(d[6]), "one of the two in the log is enough to keep it")
game.inLog[937] = nil
assert(GuideScan:BlocksResume(d[2]), "a quest the player does not have holds the resume point")
assert(GuideScan:BlocksResume(d[1]), "real outstanding work still does")
assert(not GuideScan:NodeCompleted(d[2]), "a moot step is never claimed as done")

-- The tracker never passes over them of its own accord: it waits on each
-- until the player picks the quest up or presses SKIP.
ns.modules.GuideRepository = { Get = function(_, id) return id == dropped.id and dropped or nil end }
Progress.store, Progress.session = {}, {}
ns.db = { settings = {} }
Load(ns, "Domain/ObservedProgress.lua")
local Observed = ns.modules.ObservedProgress
Progress:Select(dropped)
assert((Progress:GetCurrentNode(dropped)).index == d[1].index, "the outstanding accept is where the guide opens")
assert(Progress:Forward(dropped, true), "the player takes the quest elsewhere and moves on")
Progress:Release(dropped)
assert(not Observed:Refresh(), "the moot step after it is not passed over")
local droppedState = Progress:GetState(dropped)
assert((Progress:GetCurrentNode(dropped)).index == d[2].index, "the guide waits on the turn-in it has no quest for")
assert(droppedState.statuses[d[2].index] == nil, "and records nothing on it")
assert(Progress:Forward(dropped) and (Progress:GetCurrentNode(dropped)).index == d[3].index, "SKIP moves one step")
assert(Observed:SkipToOutstanding(dropped) and (Progress:GetCurrentNode(dropped)).index == d[4].index,
    "Shift-SKIP stops on the next moot step rather than running past it")
assert(Observed:BackToOutstanding(dropped) and (Progress:GetCurrentNode(dropped)).index == d[3].index,
    "Shift-BACK stops on a moot step too")
assert(not Progress:IsHeld(dropped), "without a hold")

-- What the scan may read back after the fact: a skill rank, a standing, and
-- the gear the player is wearing are all still true later; a craft is not.
local matcher = ns.modules.Client.MatchesObservedCompletion
ns.modules.Client.MatchesObservedCompletion = function(self, rule, location, index)
    if rule.type == "skill" then return rule.atLeast <= 150 end
    if rule.type == "reputation" then return rule.standing <= 6 end
    if rule.type == "equipped" then return rule.itemID == 7360 end
    return matcher(self, rule, location, index)
end
assert(GuideScan:Observed({ type = "skill", name = "Mining", atLeast = 150 }))
assert(not GuideScan:Observed({ type = "skill", name = "Mining", atLeast = 225 }))
assert(GuideScan:Observed({ type = "reputation", factionID = 576, standing = 6 }))
assert(GuideScan:Observed({ type = "equipped", itemID = 7360 }))
assert(not GuideScan:Observed({ type = "crafted", itemID = 2862, count = 5 }), "crafting leaves no proof the scan can read")
ns.modules.Client.MatchesObservedCompletion = matcher

-- The rank escape is durable, so a guide loaded on a character who is already
-- past it opens beyond the materials steps instead of asking for them again.
local escape = { type = "any", children = {
    { type = "item", itemID = 2770, count = 20 },
    { type = "skill", name = "Mining", atLeast = 150 },
} }
matcher = ns.modules.Client.MatchesObservedCompletion
ns.modules.Client.MatchesObservedCompletion = function(self, rule, location, index)
    if rule.type == "skill" then return rule.atLeast <= 150 end
    return matcher(self, rule, location, index)
end
assert(GuideScan:Observed(escape), "the rank proves it after the fact")
escape.children[2].atLeast = 225
assert(not GuideScan:Observed(escape), "bags alone never prove it")
ns.modules.Client.MatchesObservedCompletion = matcher

-- A turn-in with nothing to hand in is not a member of the group: it joins
-- once its quest is accepted, here at the group's first member.
local hub = Steps:Expand({
    schema = 2, id = "test:moot-member", updated = 1789862400, map = 1413,
    meta = { title = "Moot member", category = "test" },
    steps = { { section = "Hub", steps = {
        { group = {
            { accept = 950, npc = 3448, at = { 52, 31 } },
            { turnin = 950, npc = 3449, at = { 53, 31 } },
            { turnin = 870, npc = 3449, at = { 53, 31 } },
        } },
        { finish = "Done." },
    } } },
})
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == hub.id and hub or nil end }
Progress:Select(hub)
game.questLogRead = true
local function members() return #Progress:QuestGroup(hub, hub.nodes[1]) end
assert(members() == 2, "a turn-in for a quest not yet taken stays out of the group; one already handed in stays in")
game.inLog[950] = true
assert(members() == 3, "it joins once the quest is in the log")
