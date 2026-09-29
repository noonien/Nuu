_G = _G or _ENV
local ns = { modules = {}, builtInGuides = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/Navigation.lua")
local Client, Schema, Steps = ns.modules.Client, ns.modules.Schema, ns.modules.Steps
local Progress, Navigation = ns.modules.Progress, ns.modules.Navigation

local stubbed = { "C_Item", "C_QuestLog", "C_Map", "GetItemCount", "UnitLevel", "GetRealZoneText",
    "GetSubZoneText", "GetMinimapZoneText", "GetInventoryItemLink", "GetInventoryItemQuality" }
local function clearStubs() for _, name in ipairs(stubbed) do _G[name] = nil end end
clearStubs()

local function expand(steps, extra)
    local guide = { schema = 2, id = "nuuroad:test:port", updated = 1, map = 1412,
        meta = { title = "Port constructs", category = "test" },
        steps = { { section = "S", steps = steps } } }
    for key, value in pairs(extra or {}) do guide[key] = value end
    local expanded = Steps:Expand(guide)
    local ok, problems = Schema:Validate(expanded)
    assert(ok, table.concat(problems or {}, "; "))
    return expanded
end

-- #completewith: a step carried alongside a later one ------------------------
local guide = expand({
    { travel = "Through the cave", with = "next", at = { 59.67, 83.33 } },
    { objective = 757, part = 1, collect = 4770, count = 12, at = { 63.93, 78.34 } },
    { travel = "The belts camp", with = "belts", at = { 60.00, 80.00 } },
    { turnin = 757, npc = 2981, label = "belts", at = { 44.18, 76.07 } },
    { finish = "Done." },
})
assert(guide.nodes[1].companionOf == 2, "`with = \"next\"` names the following step")
assert(guide.nodes[3].companionOf == 4, "a label names any later step")
assert(guide.nodes[2].companionOf == nil and guide.nodes[4].companionOf == nil)
-- The carried step keeps its own rule; either finishes it.
local carriedCompletion = guide.nodes[1].completion.observed
assert(carriedCompletion.type == "any" and #carriedCompletion.children == 2)
assert(carriedCompletion.children[2].type == "step" and carriedCompletion.children[2].index == 2)

local badForward = pcall(Steps.Expand, Steps, { schema = 2, id = "x", updated = 1, map = 1412,
    meta = { title = "x", category = "test" },
    steps = { { section = "S", steps = {
        { note = "target", label = "earlier" },
        { note = "carried", with = "earlier" },
    } } } })
assert(not badForward, "a step cannot be carried alongside an earlier one")

local badLabel = pcall(Steps.Expand, Steps, { schema = 2, id = "x", updated = 1, map = 1412,
    meta = { title = "x", category = "test" },
    steps = { { section = "S", steps = { { note = "carried", with = "nowhere" }, { note = "other" } } } } })
assert(not badLabel, "`with` naming no label is refused at load")

-- The flow never stops on a carried step, and the step that carries it
-- finishes it.
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }
Progress:Select(guide)
Progress:SkipUnavailable(guide)
assert(Progress:GetCurrentNode(guide).index == 2, "the guide opens on the step, not on what it carries")
local carried = Progress:Carried(guide, guide.nodes[2])
assert(#carried == 1 and carried[1].index == 1, "the tracker gets the carried step to draw")
assert(Progress:Complete(guide, 2))
local state = Progress:PeekState(guide)
assert(Progress:IsDone(state.statuses[1]), "completing the step completes what it carried")
assert(Progress:GetCurrentNode(guide).index == 4, "step 3 is carried too, so the flow walks past it")
assert(Progress:Complete(guide, 4, "skipped"))
assert(state.statuses[3] == "skipped", "a skip carries its companions with it")

-- #sticky: stays up alongside the steps after it until it is done ------------
local sticky = expand({
    { note = "Keep an eye out for Ghost Howl.", sticky = true },
    { note = "One" },
    { note = "Two" },
    { finish = "Done." },
})
assert(sticky.nodes[1].sticky == true)
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == sticky.id and sticky or nil end }
Progress:Select(sticky)
Progress:SkipUnavailable(sticky)
assert(Progress:GetCurrentNode(sticky).index == 2, "a sticky step is not stopped on either")
assert(#Progress:Carried(sticky, sticky.nodes[2]) == 1, "it is drawn alongside the step after it")
assert(#Progress:Carried(sticky, sticky.nodes[3]) == 1, "and the one after that")
Progress:Record(sticky, 1, "complete")
assert(#Progress:Carried(sticky, sticky.nodes[3]) == 0, "until it is done")

-- A sticky objective leaves the card once the game shows it finished, though
-- the flow, never stopping on it, records nothing.
local stickyKills = expand({
    { accept = 1487, npc = 5768 },
    { objective = 1487, part = 2, kill = 5755, count = 7, sticky = true },
    { objective = 1487, part = 3, kill = 5761, count = 7, sticky = true },
    { note = "One" },
    { finish = "Done." },
})
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == stickyKills.id and stickyKills or nil end }
Progress:Select(stickyKills)
Progress:Complete(stickyKills, 1)
local finishedParts = {}
ns.modules.GuideScan = { NodeCompleted = function(_, candidate)
    return candidate.completion.observed.index ~= nil and finishedParts[candidate.completion.observed.index] == true
end }
assert(#Progress:Carried(stickyKills, stickyKills.nodes[4]) == 2, "both kill objectives ride along")
finishedParts[2] = true
local left = Progress:Carried(stickyKills, stickyKills.nodes[4])
assert(#left == 1 and left[1].index == 3, "the finished one leaves the card")
finishedParts[3] = true
assert(#Progress:Carried(stickyKills, stickyKills.nodes[4]) == 0, "and so does the other")
ns.modules.GuideScan = nil

-- #loop, and any step with several points: the arrow takes the nearest -----
local loop = expand({
    { objective = 745, part = 1, kill = 2949, count = 10, loop = true,
        at = { { 53.50, 73.00 }, { 48.30, 72.00 } } },
    { finish = "Done." },
})
local location = loop.nodes[1].location
assert(location.loop == true and #location.spots == 1)
local x, y = Navigation.NearestPoint(location, 0.49, 0.72)
assert(math.abs(x - 0.483) < 0.001 and math.abs(y - 0.72) < 0.001, "the nearer point wins")
x, y = Navigation.NearestPoint(location, 0.54, 0.73)
assert(math.abs(x - 0.535) < 0.001, "and so does the other one, from the other side")
local plain = expand({ { travel = "A", at = { { 53.50, 73.00 }, { 48.30, 72.00 } } }, { finish = "." } })
x = Navigation.NearestPoint(plain.nodes[1].location, 0.49, 0.72)
assert(math.abs(x - 0.483) < 0.001, "without loop the nearest point wins too")

-- .vendor, .unitscan, .timer -------------------------------------------------
local misc = expand({
    { vendor = "sell", npc = 3072, at = { 45.30, 76.52 } },
    { vendor = "repair", npc = 3080, at = { 45.90, 58.73 } },
    { note = "Grind here.", watch = 3056, at = { 52.00, 45.00 } },
    { turnin = 748, npc = 2948, wait = 8, at = { 48.53, 60.40 } },
    { finish = "Done." },
})
assert(misc.nodes[1].kind == "vendor")
assert(Steps:Title(misc.nodes[1]):find("Sell your junk"), Steps:Title(misc.nodes[1]))
assert(Steps:Title(misc.nodes[2]):find("^Repair at "), Steps:Title(misc.nodes[2]))
assert(misc.nodes[3].watch[1] == 3056, "a watched rare is recorded")
assert(misc.nodes[3].refs.npcs[1] == 3056, "and referenced, so the NPC panel lists it")
assert(misc.nodes[4].wait == 8)

-- .zone / .subzone: arrival by name -----------------------------------------
local byName = expand({
    { travel = "The Barrens", zone = "The Barrens", at = { 69.60, 60.40 } },
    { travel = "Bloodhoof Village", subzone = "Bloodhoof Village", at = { 47.35, 60.70 } },
    { finish = "Done." },
})
assert(byName.nodes[1].completion.observed.type == "zone")
assert(byName.nodes[2].completion.observed.type == "subzone")
GetRealZoneText = function() return "Mulgore" end
GetSubZoneText = function() return "Bloodhoof Village" end
assert(not Client:MatchesObservedCompletion(byName.nodes[1].completion.observed))
assert(Client:MatchesObservedCompletion(byName.nodes[2].completion.observed))
GetRealZoneText = function() return "The Barrens" end
assert(Client:MatchesObservedCompletion(byName.nodes[1].completion.observed))

-- The predicates behind .bindlocation, .itemStat, #xprate, #ah and #ssf ------
local gated = expand({
    { note = "bound", only = "hearth Bloodhoof Village" },
    { note = "here", only = "subzone Camp Narache" },
    { note = "worse weapon", only = "slot 16 dps < 4.2" },
    { note = "poor weapon", only = "slot 16 quality < 7" },
    { note = "slow realm", only = "xprate < 1.5" },
    { note = "fast realm", only = "xprate >= 1.5" },
    { note = "buyer", only = "auctionhouse" },
    { note = "self found", only = "selffound" },
    { note = "buffed", only = "aura 408828" },
    { note = "ready", only = "cooldown item 6948" },
    { finish = "Done." },
})
assert(gated.nodes[3].condition.slot == 16 and gated.nodes[3].condition.stat == "dps")
assert(gated.nodes[3].condition.below == 4.2)
assert(gated.nodes[5].condition.below == 1.5 and gated.nodes[6].condition.atLeast == 1.5)
for index = 1, 10 do
    assert(Client:HasPredicate(gated.nodes[index].condition.type),
        "unregistered: " .. gated.nodes[index].condition.type)
    assert(Steps:DescribeCondition(gated.nodes[index].condition), "must render back as text")
end

-- The realm answers are unknown until the player gives them, and unknown
-- never hides a step.
ns.db = { settings = {} }
assert(Client:EvaluateCondition(gated.nodes[5].condition) == nil)
assert(Client:MatchesCondition(gated.nodes[5].condition), "an unanswered question hides nothing")
ns.db.settings.realm = { xpRate = 1, auctionHouse = false, selfFound = true }
assert(Client:EvaluateCondition(gated.nodes[5].condition) == true, "1x is below 1.5")
assert(Client:EvaluateCondition(gated.nodes[6].condition) == false)
assert(Client:EvaluateCondition(gated.nodes[7].condition) == false, "the player said no auction house")
assert(Client:EvaluateCondition(gated.nodes[8].condition) == true)

-- An empty slot is worse than anything, which is what those steps are for.
assert(Client:EvaluateCondition(gated.nodes[3].condition) == true, "nothing worn is worse than anything")
GetInventoryItemLink = function() return "|cff9d9d9d|Hitem:2495::::::::1:::::|h[Walking Stick]|h|r" end
GetInventoryItemQuality = function() return 1 end
assert(Client:EvaluateCondition(gated.nodes[4].condition) == true, "quality 1 is below 7")
GetInventoryItemQuality = function() return 7 end
assert(Client:EvaluateCondition(gated.nodes[4].condition) == false)
assert(Client:EvaluateCondition(gated.nodes[3].condition) == nil,
    "damage per second is only on the tooltip, so it is unknown with no client")

clearStubs()
ns.db = nil

return true
