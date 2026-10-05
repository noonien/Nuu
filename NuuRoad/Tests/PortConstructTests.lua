_G = _G or _ENV
local ns = { modules = {}, builtInGuides = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/IDNames.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/Navigation.lua")
local Client, Schema, Steps = ns.modules.Client, ns.modules.Schema, ns.modules.Steps
local Progress, Navigation = ns.modules.Progress, ns.modules.Navigation

local stubbed = { "C_Item", "C_QuestLog", "C_Map", "GetItemCount", "UnitLevel", "GetRealZoneText",
    "GetSubZoneText", "GetMinimapZoneText", "GetInventoryItemLink", "GetInventoryItemQuality" }
local function clearStubs() for _, name in ipairs(stubbed) do _G[name] = nil end end
clearStubs()

local function v1(steps)
    return { kind = "guide", schema = 1, id = "nuuroad:test:port", updated = 1,
        title = "Port constructs", category = "test",
        data = { map = 1412, sections = { { title = "S", steps = steps } } } }
end
local function expand(steps)
    local expanded = Steps:Expand(v1(steps))
    local ok, problems = Schema:Validate(expanded)
    assert(ok, table.concat(problems or {}, "; "))
    return expanded
end

-- #completewith: a step carried alongside a later one ------------------------
local guide = expand({
    { type = "travel", to = "Through the cave", with = "cave", at = { { 5967, 8333 } } },
    { type = "collect", item = 4770, quest = { 757, 1 }, label = "cave", at = { { 6393, 7834 } } },
    { type = "travel", to = "The belts camp", with = "belts", at = { { 6000, 8000 } } },
    { type = "turnin", quests = { 757 }, npc = { 2981 }, label = "belts", at = { { 4418, 7607 } } },
    { type = "finish", note = "Done." },
})
assert(guide.nodes[1].companionOf == 2, "a label on the next step names it")
assert(guide.nodes[3].companionOf == 4, "a label names any later step")
assert(guide.nodes[2].companionOf == nil and guide.nodes[4].companionOf == nil)
-- The carried step keeps its own rule; either finishes it.
local carriedCompletion = guide.nodes[1].completion.observed
assert(carriedCompletion.type == "any" and #carriedCompletion.children == 2)
assert(carriedCompletion.children[2].type == "step" and carriedCompletion.children[2].index == 2)

local badForward, message = pcall(Steps.Expand, Steps, v1({
    { type = "note", note = "target", label = "earlier" },
    { type = "note", note = "carried", with = "earlier" },
}))
assert(not badForward and message:find("steps[2].with: a step is carried alongside a later step", 1, true),
    "a step cannot be carried alongside an earlier one")

local badLabel
badLabel, message = pcall(Steps.Expand, Steps, v1({ { type = "note", note = "carried", with = "nowhere" }, { type = "note", note = "other" } }))
assert(not badLabel and message:find("no step is labelled 'nowhere'", 1, true), "`with` naming no label is refused at load")
-- `with = "next"` is gone: it names a label like any other.
badLabel, message = pcall(Steps.Expand, Steps, v1({ { type = "note", note = "carried", with = "next" }, { type = "note", note = "other" } }))
assert(not badLabel and message:find("no step is labelled 'next'", 1, true))

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
    { type = "note", note = "Keep an eye out for Ghost Howl.", sticky = true },
    { type = "note", note = "One" },
    { type = "note", note = "Two" },
    { type = "finish", note = "Done." },
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
    { type = "accept", quests = { 1487 }, npc = { 5768 } },
    { type = "kill", kill = { 5755 }, quest = { 1487, 2 }, sticky = true },
    { type = "kill", kill = { 5761 }, quest = { 1487, 3 }, sticky = true },
    { type = "note", note = "One" },
    { type = "finish", note = "Done." },
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
    { type = "kill", kill = { 2949 }, quest = { 745, 1 }, loop = true,
        at = { { 5350, 7300 }, { 4830, 7200 } } },
    { type = "finish", note = "Done." },
})
local location = loop.nodes[1].location
assert(location.loop == true and #location.spots == 1)
local x, y = Navigation.NearestPoint(location, 0.49, 0.72)
assert(math.abs(x - 0.483) < 0.001 and math.abs(y - 0.72) < 0.001, "the nearer point wins")
x, y = Navigation.NearestPoint(location, 0.54, 0.73)
assert(math.abs(x - 0.535) < 0.001, "and so does the other one, from the other side")
local plain = expand({ { type = "travel", to = "A", at = { { 5350, 7300 }, { 4830, 7200 } } }, { type = "finish", note = "." } })
x = Navigation.NearestPoint(plain.nodes[1].location, 0.49, 0.72)
assert(math.abs(x - 0.483) < 0.001, "without loop the nearest point wins too")

-- .vendor, .timer ------------------------------------------------------------
local misc = expand({
    { type = "vendor", sell = true, npc = { 3072 }, at = { { 4530, 7652 } } },
    { type = "vendor", repair = true, npc = { 3080 }, at = { { 4590, 5873 } } },
    { type = "turnin", quests = { 748 }, npc = { 2948 }, wait = 8, at = { { 4853, 6040 } } },
    { type = "vendor", sell = true, repair = true, npc = { 3080 } },
    { type = "finish", note = "Done." },
})
assert(misc.nodes[1].kind == "vendor")
assert(Steps:Title(misc.nodes[1]):find("Sell your junk"), Steps:Title(misc.nodes[1]))
assert(Steps:Title(misc.nodes[2]):find("^Repair at "), Steps:Title(misc.nodes[2]))
assert(misc.nodes[3].wait == 8)
assert(Steps:Title(misc.nodes[4]):find("^Sell and repair at "), Steps:Title(misc.nodes[4]))
assert(not pcall(Steps.Expand, Steps, v1({ { type = "vendor", npc = { 3080 } } })), "a vendor step sells, repairs, or both")

-- Arrival by zone (a map ID) or by area (an AreaTable ID, named) ----------
local byName = expand({
    { type = "travel", to = "The Barrens", zone = 1413, at = { { 6960, 6040 } } },
    { type = "travel", to = "Bloodhoof Village", area = 222, at = { { 4735, 6070 } } },
    { type = "finish", note = "Done." },
})
assert(byName.nodes[1].completion.observed.type == "zone" and byName.nodes[1].completion.observed.mapID == 1413)
assert(byName.nodes[2].completion.observed.type == "subzone" and byName.nodes[2].completion.observed.name == "Bloodhoof Village")
local here = 1412
C_Map = { GetBestMapForUnit = function() return here end }
GetSubZoneText = function() return "Bloodhoof Village" end
assert(not Client:MatchesObservedCompletion(byName.nodes[1].completion.observed))
assert(Client:MatchesObservedCompletion(byName.nodes[2].completion.observed))
here = 1413
assert(Client:MatchesObservedCompletion(byName.nodes[1].completion.observed))
C_Map = nil
local badArea, areaMessage = pcall(Steps.Expand, Steps, v1({ { type = "travel", to = "Nowhere", area = 999999 } }))
assert(not badArea and areaMessage:find("steps[1].area: no name for areas 999999", 1, true), tostring(areaMessage))
badArea, areaMessage = pcall(Steps.Expand, Steps, v1({ { type = "travel", to = "Bloodhoof", area = "Bloodhoof Village" } }))
assert(not badArea and areaMessage:find("an area is an AreaTable ID", 1, true), "areas are IDs, not names")

-- The realm answers behind #ah and #ssf: `show` keys, read as they stand -----
local gated = expand({
    { type = "note", note = "buyer", show = { ah = true } },
    { type = "note", note = "self found", show = { selffound = true } },
    { type = "finish", note = "Done." },
})
for index = 1, 2 do
    local condition = gated.nodes[index].condition
    assert(condition.type == "now" and Client:HasPredicate(condition.child.type), "a show key is a `now` term")
end
assert(Steps:DescribeCondition(gated.nodes[1].condition) == "ah")
assert(Steps:DescribeCondition(gated.nodes[2].condition) == "selffound")

-- The realm answers are unknown until the player gives them, and unknown
-- never hides a step.
ns.db = { settings = {} }
assert(Client:EvaluateCondition(gated.nodes[1].condition) == nil)
assert(Client:MatchesCondition(gated.nodes[1].condition), "an unanswered question hides nothing")
ns.db.settings.realm = { xpRate = 1, auctionHouse = false, selfFound = true }
assert(Client:EvaluateCondition(gated.nodes[1].condition) == false, "the player said no auction house")
assert(Client:EvaluateCondition(gated.nodes[2].condition) == true)

-- The shipped fixture: what its header says to look for.
ns.packagedGuides = {}
Load(ns, "Dev/Fixtures/PortConstructFixture.lua")
local fixture = Steps:Expand(ns.packagedGuides[1])
ns.packagedGuides = nil
local valid, fixtureProblems = Schema:Validate(fixture)
assert(valid, table.concat(fixtureProblems or {}, "; "))
local fn = fixture.nodes
assert(fn[1].companionOf == 2 and fn[4].companionOf == 7, "steps 1 and 4 are carried")
assert(fn[2].location.loop and #fn[2].location.spots == 3 and math.abs(fn[2].location.arrivalRadiusNormalized - 0.06) < 1e-9)
assert(fn[3].sticky)
assert(fn[5].auto.action == "sell" and fn[6].auto.action == "repair" and fn[7].wait == 8)
assert(fn[8].completion.observed.name == "Bloodhoof Village" and fn[9].completion.observed.mapID == 1413)
assert(fn[10].condition.child.type == "auctionHouse" and fn[11].condition.child.type == "selfFound")
assert(#fn == 12 and fn[12].kind == "end")

clearStubs()
ns.db = nil

return true
