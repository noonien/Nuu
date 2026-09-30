_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
local Client = ns.modules.Client

-- Stub the client APIs the matcher consults.
local log, flagged, ready = {}, {}, {}
C_QuestLog = {
    IsOnQuest = function(id) return log[id] == true end,
    IsQuestFlaggedCompleted = function(id) return flagged[id] == true end,
    IsComplete = function(id) return ready[id] == true end,
    GetTitleForQuestID = function(id) return id == 870 and "The Forgotten Pools" or nil end,
}
UnitLevel = function() return 15 end

assert(Client:MatchesObservedCompletion({ type = "always" }))
assert(Client:MatchesObservedCompletion({ type = "level", atLeast = 15 }))
assert(not Client:MatchesObservedCompletion({ type = "level", atLeast = 16 }))

local accepted = { type = "quests", state = "acceptedOrFinished", ids = { 870 } }
assert(not Client:MatchesObservedCompletion(accepted))
log[870] = true
assert(Client:MatchesObservedCompletion(accepted), "a quest in the log counts as accepted")
log[870] = nil; flagged[870] = true
assert(Client:MatchesObservedCompletion(accepted), "a flagged-complete quest counts as finished")

local all = { type = "quests", state = "readyToTurnIn", match = "all", ids = { 1, 2 } }
ready[1] = true
assert(not Client:MatchesObservedCompletion(all), "match all needs every quest")
ready[2] = true
assert(Client:MatchesObservedCompletion(all))
local any = { type = "quests", state = "finished", match = "any", ids = { 5, 870 } }
assert(Client:MatchesObservedCompletion(any), "match any needs one quest")
assert(not Client:MatchesObservedCompletion({ type = "quests", state = "bogus", ids = { 870 } }))

assert(Client:GetQuestTitle(870) == "The Forgotten Pools")
assert(Client:GetQuestTitle(999) == nil)

-- Map ID zero resolves to the current map.
C_Map = { GetBestMapForUnit = function() return 1413 end }
assert(Client:ResolveMapID(0) == 1413)
assert(Client:ResolveMapID(1414) == 1414)

-- Level targets with an XP threshold, objective lines, and all-of completions.
UnitXP = function() return 5000 end
assert(not Client:MatchesObservedCompletion({ type = "level", atLeast = 15, xp = 9200 }), "same level but short of xp")
UnitXP = function() return 9200 end
assert(Client:MatchesObservedCompletion({ type = "level", atLeast = 15, xp = 9200 }))
assert(Client:MatchesObservedCompletion({ type = "level", atLeast = 14, xp = 99999 }), "a higher level ignores xp")
-- `by` asks Experience, which counts the turn-ins ahead; while it cannot say,
-- the plain level check stands.
ns.modules.Experience = { Reached = function(_, observed, stepIndex) return stepIndex == 4 or nil end }
assert(Client:MatchesObservedCompletion({ type = "level", atLeast = 16, by = 9 }, nil, 4), "the turn-ins ahead bring it")
assert(not Client:MatchesObservedCompletion({ type = "level", atLeast = 16, by = 9 }, nil, 5), "unknown: level alone")
ns.modules.Experience = nil
C_QuestLog.GetQuestObjectives = function(id) return id == 821 and { { text = "Savannah Lion Tusk: 5/5", finished = true }, { text = "Plainstrider Kidney: 2/5", finished = false } } or nil end
assert(Client:MatchesObservedCompletion({ type = "objective", questID = 821, index = 1 }))
assert(not Client:MatchesObservedCompletion({ type = "objective", questID = 821, index = 2 }))
local finished, text = Client:GetQuestObjective(821, 2)
assert(finished == false and text == "Plainstrider Kidney: 2/5")
assert(not Client:MatchesObservedCompletion({ type = "objective", questID = 999, index = 1 }), "an unknown quest is not complete")
ready[821] = true
assert(Client:MatchesObservedCompletion({ type = "objective", questID = 821, index = 2 }), "a quest ready to turn in counts every objective as done")
assert(Client:MatchesObservedCompletion({ type = "all", children = { { type = "always" }, { type = "level", atLeast = 15 } } }))
assert(not Client:MatchesObservedCompletion({ type = "all", children = { { type = "always" }, { type = "level", atLeast = 16 } } }))

-- A failed quest: C_QuestLog.IsFailed where the client has it, else the
-- classic log row's -1. Neither readable is never a failure.
assert(Client:IsQuestFailed(863) == false, "no reader: not failed")
GetQuestLogIndexByID = function(id) return id == 863 and 4 or 0 end
local rowComplete
GetQuestLogTitle = function(index) return "The Escape", 16, 0, false, false, rowComplete, 0, 863 end
assert(Client:IsQuestFailed(863) == false)
rowComplete = -1
assert(Client:IsQuestFailed(863) == true, "the classic row says -1")
assert(Client:IsQuestFailed(870) == false, "a quest not in the log")
C_QuestLog.IsFailed = function(id) return id == 870 end
assert(Client:IsQuestFailed(870) == true and Client:IsQuestFailed(863) == false, "IsFailed wins where it exists")
C_QuestLog.IsFailed, GetQuestLogIndexByID, GetQuestLogTitle = nil, nil, nil

-- Conditions: class and race tokens, quest state, and combinators.
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Tauren", "Tauren" end
assert(Client:MatchesCondition({ type = "class", values = { "WARRIOR" } }))
assert(not Client:MatchesCondition({ type = "class", values = { "SHAMAN" } }))
assert(Client:MatchesCondition({ type = "race", values = { "tauren" } }), "race tokens compare case-insensitively")
assert(not Client:MatchesCondition({ type = "not", child = { type = "race", values = { "tauren" } } }))
assert(Client:MatchesCondition({ type = "any", children = { { type = "class", values = { "SHAMAN" } }, { type = "class", values = { "WARRIOR" } } } }))
assert(not Client:MatchesCondition({ type = "all", children = { { type = "class", values = { "WARRIOR" } }, { type = "race", values = { "orc" } } } }))
assert(not Client:MatchesCondition({ type = "quest", id = 858 }))
log[858] = true
assert(Client:MatchesCondition({ type = "quest", id = 858 }))
assert(Client:MatchesCondition({ type = "profession", name = "Mining" }), "conditions the client cannot judge pass")
UnitClass = nil
assert(Client:MatchesCondition({ type = "class", values = { "SHAMAN" } }), "no class API means no gating")

-- Items in bags, the hearthstone bind, and learned flight paths.
local bags = { [4926] = 0 }
GetItemCount = function(id) return bags[id] or 0 end
assert(not Client:MatchesObservedCompletion({ type = "item", itemID = 4926 }))
bags[4926] = 1
assert(Client:MatchesObservedCompletion({ type = "item", itemID = 4926 }))
assert(not Client:MatchesObservedCompletion({ type = "item", itemID = 4926, count = 5 }))
-- An item tied to a quest is satisfied through the quest once it is gone from the bags.
bags[4926] = 0
assert(not Client:MatchesObservedCompletion({ type = "item", itemID = 4926, startsQuestID = 819 }))
log[819] = true
assert(Client:MatchesObservedCompletion({ type = "item", itemID = 4926, startsQuestID = 819 }), "the quest the item begins is in the log")
log[819] = nil
assert(not Client:MatchesObservedCompletion({ type = "item", itemID = 4986, questID = 924 }))
log[924] = true
assert(not Client:MatchesObservedCompletion({ type = "item", itemID = 4986, questID = 924 }), "a quest item is still needed while its quest is open")
flagged[924] = true
assert(Client:MatchesObservedCompletion({ type = "item", itemID = 4986, questID = 924 }), "and accounted for once the quest is finished")
GetItemInfo = function(id) return id == 4926 and "Chen's Empty Keg" or nil end
assert(Client:GetItemName(4926) == "Chen's Empty Keg" and Client:GetItemName(1) == nil)
GetBindLocation = function() return "The Crossroads" end
assert(Client:MatchesObservedCompletion({ type = "hearth", name = "The Crossroads" }))
assert(Client:MatchesObservedCompletion({ type = "hearth", name = "Crossroads" }), "a leading 'The' does not matter")
assert(not Client:MatchesObservedCompletion({ type = "hearth", name = "Camp Taurajo" }))
ns.modules.Progress = { store = {} }
assert(not Client:MatchesObservedCompletion({ type = "flightpath", name = "Ratchet" }))
NumTaxiNodes = function() return 2 end
TaxiNodeName = function(i) return i == 1 and "Ratchet, The Barrens" or "Orgrimmar" end
TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "DISTANT" end
Client:RecordFlightPathsFromTaxiMap()
assert(Client:MatchesObservedCompletion({ type = "flightpath", name = "Ratchet" }), "the current taxi node is learned")
assert(not Client:MatchesObservedCompletion({ type = "flightpath", name = "Orgrimmar" }), "a distant node is not")
assert(ns.modules.Progress.store.flightPaths.ratchet == true, "flight paths persist per character")
Client:RecordFlightPath("Camp Taurajo")
assert(Client:HasFlightPath("Camp Taurajo"))

-- Creature names come from a hidden tooltip, cached, with a timed retry on a miss.
local tooltipName
GetTime = function() return 100 end
UIParent = {}
CreateFrame = function(_, name)
    local frame = { SetOwner = function() end, ClearLines = function() end, Hide = function() end }
    frame.SetHyperlink = function() _G[name .. "TextLeft1"] = { GetText = function() return tooltipName end } end
    return frame
end
assert(Client:GetNPCName(3429) == nil, "an unseen creature has no name yet")
tooltipName = "Thork"
assert(Client:GetNPCName(3429) == nil, "a miss is not retried immediately")
GetTime = function() return 102 end
assert(Client:GetNPCName(3429) == "Thork")
tooltipName = "|cffffffffTonga Runetotem|r"
assert(Client:GetNPCName(3448) == "Tonga Runetotem", "colour codes are stripped")
tooltipName = nil
assert(Client:GetNPCName(3448) == "Tonga Runetotem", "names are cached")

-- Secret tooltip strings are misses, and must not enter the name cache.
tooltipName = "Restricted creature name"
issecretvalue = function(value) return value == "Restricted creature name" end
assert(Client:GetNPCName(3265) == nil, "secret tooltip text is discarded")
tooltipName = "Razormane Hunter"
assert(Client:GetNPCName(3265) == nil, "secret misses use the normal retry delay")
GetTime = function() return 104 end
assert(Client:GetNPCName(3265) == "Razormane Hunter", "a readable name is retried and cached")
tooltipName = "Restricted creature name"
assert(Client:GetNPCName(3265) == "Razormane Hunter", "a secret read cannot replace a cached name")
issecretvalue = nil
tooltipName = nil

-- Creature IDs from GUIDs, kills kept per step, and the combat log entry.
assert(Client:CreatureIDFromGUID("Creature-0-4379-1413-8-3244-00001A2B3C") == 3244)
assert(Client:CreatureIDFromGUID("Vehicle-0-4379-1413-8-3439-00001A2B3C") == 3439)
assert(Client:CreatureIDFromGUID("Player-4379-00ABCDEF") == nil and Client:CreatureIDFromGUID("Pet-0-4379-1413-8-416-0000000001") == nil)
local kills = { ["kill:3244"] = 0 }
ns.modules.Progress = {
    store = {},
    GetActiveGuide = function() return { id = "g" } end,
    KillCount = function(_, _, nodeID) return kills[nodeID] or 0 end,
}
assert(not Client:MatchesObservedCompletion({ type = "kills", npcs = { 3244 }, count = 3 }, nil, "kill:3244"))
kills["kill:3244"] = 3
assert(Client:MatchesObservedCompletion({ type = "kills", npcs = { 3244 }, count = 3 }, nil, "kill:3244"))
assert(not Client:MatchesObservedCompletion({ type = "kills", npcs = { 3244 }, count = 3 }), "kills need the step they belong to")
assert(Client:MatchesObservedCompletion({ type = "all", children = { { type = "always" }, { type = "kills", npcs = { 3244 }, count = 1 } } }, nil, "kill:3244"), "the step is passed down to children")
ns.modules.Progress = nil
CombatLogGetCurrentEventInfo = function() return 1, "PARTY_KILL", false, "Player-1-0A", "Me", 0, 0, "Creature-0-1-1413-8-3244-0000000001", "Greater Plainstrider" end
local entry = Client:GetCombatLogEvent()
assert(entry.subevent == "PARTY_KILL" and entry.sourceGUID == "Player-1-0A" and entry.destGUID == "Creature-0-1-1413-8-3244-0000000001")
CombatLogGetCurrentEventInfo = nil
entry = Client:GetCombatLogEvent(2, "UNIT_DIED", false, nil, nil, 0, 0, "Creature-0-1-1413-8-3245-0000000002", "Ornery Plainstrider")
assert(entry.subevent == "UNIT_DIED" and entry.destGUID == "Creature-0-1-1413-8-3245-0000000002", "older clients pass the entry as arguments")
UnitGUID = function(unit) return unit == "player" and "Player-1-0A" or (unit == "pet" and "Pet-0-1-1413-8-416-0000000003") or nil end
assert(Client:IsPlayerOrGroupGUID("Player-1-0A") and Client:IsPlayerOrGroupGUID("Pet-0-1-1413-8-416-0000000003"))
assert(not Client:IsPlayerOrGroupGUID("Player-1-0B"), "another player's kill is not ours")

-- Gossip quest lists: by ID on newer clients, as flat tuples without IDs on older ones.
C_GossipInfo = {
    GetAvailableQuests = function() return { { questID = 870, title = "The Forgotten Pools" } } end,
    GetActiveQuests = function() return { { questID = 845, title = "The Zhevra", isComplete = true } } end,
}
local quests = Client:GetGossipQuests()
assert(quests.available[1].questID == 870 and quests.active[1].questID == 845 and quests.active[1].isComplete == true)
C_GossipInfo = nil
GetGossipAvailableQuests = function() return "The Forgotten Pools", 10, false, 1, false, false, false, "Supplies for the Crossroads", 12, false, 1, false, false, false end
GetGossipActiveQuests = function() return "The Zhevra", 10, false, true, false, false, "Raptor Thieves", 12, false, false, false, false end
quests = Client:GetGossipQuests()
assert(#quests.available == 2 and quests.available[2].title == "Supplies for the Crossroads" and quests.available[2].index == 2 and quests.available[2].questID == nil)
assert(#quests.active == 2 and quests.active[1].isComplete == true and quests.active[2].isComplete == false)
GetGossipAvailableQuests, GetGossipActiveQuests = nil, nil
GetNumAvailableQuests = function() return 1 end
GetAvailableTitle = function() return "The Forgotten Pools" end
GetNumActiveQuests = function() return 1 end
GetActiveTitle = function() return "The Zhevra", true end
GetActiveQuestID = function() return 845 end
quests = Client:GetGreetingQuests()
assert(quests.available[1].title == "The Forgotten Pools" and quests.active[1].questID == 845 and quests.active[1].isComplete == true)

-- Secret values: the client hands back a value of the right type that throws
-- as soon as it is compared, so every read goes through Client:Read first.
local secrets = {}
issecretvalue = function(value) return secrets[value] == true end
local hiddenIndex = setmetatable({}, { __lt = function() error("attempt to compare a secret value") end })
secrets[hiddenIndex] = true
GetRaidTargetIndex = function(unit) return unit == "hidden" and hiddenIndex or (unit == "marked" and 8 or nil) end
local index, known = Client:GetRaidTargetIndex("marked")
assert(index == 8 and known == true)
index, known = Client:GetRaidTargetIndex("unmarked")
assert(index == nil and known == true, "no marker is an answer")
index, known = Client:GetRaidTargetIndex("hidden")
assert(index == nil and known == false, "a hidden marker is not an answer")
UnitExists = function() return hiddenIndex end
assert(Client:UnitExists("hidden") == false, "a secret value never passes for true")
issecretvalue = nil

-- Skill ranks, worn gear, and reputation standing.
local skills = { { "Professions", true }, { "Mining", false, 73, 150 }, { "First Aid", false, 40, 75 } }
GetNumSkillLines = function() return #skills end
GetSkillLineInfo = function(index)
    local entry = skills[index]
    return entry[1], entry[2], true, entry[3], 0, 0, entry[4]
end
assert(Client:GetSkillRank("Mining") == 73 and select(2, Client:GetSkillRank("Mining")) == 150)
assert(Client:GetSkillRank("mining") == 73, "skill names are matched without case")
assert(Client:GetSkillRank("Herbalism") == nil, "a skill the player does not have has no rank")
assert(Client:EvaluateCondition({ type = "profession", name = "Herbalism" }) == false,
    "a profession missing from a skill list the client handed over is a no, not unknown")
assert(Client:EvaluateCondition({ type = "skill", name = "Herbalism", atLeast = 1 }) == false)
assert(Client:EvaluateCondition({ type = "profession", name = "Mining" }) == true)
assert(Client:MatchesObservedCompletion({ type = "skill", name = "Mining", atLeast = 73 }))
assert(not Client:MatchesObservedCompletion({ type = "skill", name = "Mining", atLeast = 150 }))
assert(not Client:MatchesObservedCompletion({ type = "skill", name = "Herbalism", atLeast = 1 }))

local worn = {}
IsEquippedItem = function(id) return worn[id] == true end
assert(not Client:MatchesObservedCompletion({ type = "equipped", itemID = 7360 }))
worn[7360] = true
assert(Client:MatchesObservedCompletion({ type = "equipped", itemID = 7360 }))

GetFactionInfoByID = function(id)
    if id ~= 576 then return nil end
    return "Timbermaw Hold", "", 5, 3000, 9000, 5400
end
local standing, value, ceiling, name = Client:GetFactionStanding(576)
assert(standing == 5 and value == 2400 and ceiling == 6000 and name == "Timbermaw Hold")
assert(Client:GetFactionName(576) == "Timbermaw Hold" and Client:GetFactionStanding(1) == nil)
assert(Client:MatchesObservedCompletion({ type = "reputation", factionID = 576, standing = 5 }))
assert(not Client:MatchesObservedCompletion({ type = "reputation", factionID = 576, standing = 6 }))
assert(not Client:MatchesObservedCompletion({ type = "reputation", factionID = 1, standing = 1 }), "no standing is not a match")

-- Crafting: the stack in the bags counts, otherwise the session's tally does.
local made, bags = 0, {}
C_Item = { GetItemCount = function(id) return bags[id] or 0 end }
ns.modules.Progress = { GetActiveGuide = function() return { id = "g" } end, CraftCount = function() return made end }
local crafted = { type = "crafted", itemID = 2862, count = 5 }
assert(not Client:MatchesObservedCompletion(crafted, nil, 3))
made = 5
assert(Client:MatchesObservedCompletion(crafted, nil, 3))
made, bags[2862] = 0, 5
assert(Client:MatchesObservedCompletion(crafted, nil, 3), "a full stack in the bags proves it")
made, bags[2862] = 5, 0
assert(not Client:MatchesObservedCompletion(crafted, nil, nil), "with no step there is no tally to read")
ns.modules.Progress = nil

-- The bank counts unless only the bags are asked for (what a craft can use).
local bank = { [2770] = 22 }
C_Item = { GetItemCount = function(id, includeBank) return (bags[id] or 0) + (includeBank and bank[id] or 0) end }
bags[2770] = 42
assert(Client:GetItemCount(2770) == 64 and Client:GetItemCount(2770, true) == 42)
C_Item = { GetItemCount = function(id) return bags[id] or 0 end }

-- An any-of completion: whichever child lands first.
local escape = { type = "any", children = {
    { type = "item", itemID = 2770, count = 20 },
    { type = "skill", name = "Mining", atLeast = 150 },
} }
bags[2770] = 0
skills[2] = { "Mining", false, 73, 150 }
assert(not Client:MatchesObservedCompletion(escape))
bags[2770] = 20
assert(Client:MatchesObservedCompletion(escape), "the items finish it")
bags[2770] = 0
skills[2] = { "Mining", false, 150, 150 }
assert(Client:MatchesObservedCompletion(escape), "so does the rank, with no items at all")
assert(not Client:MatchesObservedCompletion({ type = "any", children = {} }), "an empty any-of is never met")

-- Which raid marker a texture is drawing, from its coordinates alone. This
-- is how a marker is read on a client that hands back the index as a secret
-- value: SetRaidTargetIconTexture takes cell `index - 1` of the atlas, four
-- to a row, so the top-left corner of the cell names the marker.
local function cell(index)
    local zero = index - 1
    local left, top = (zero % 4) * 0.25, math.floor(zero / 4) * 0.25
    return left, top, left, top + 0.25, left + 0.25, top, left + 0.25, top + 0.25
end
for index = 1, 8 do
    assert(Client.RaidIconFromTexCoords(cell(index)) == index, "marker " .. index .. " reads back from its cell")
end
assert(Client.RaidIconFromTexCoords(0, 0.25, 0, 0.25) == 1, "the four-value form is the left/right/top/bottom one")
assert(Client.RaidIconFromTexCoords(cell(9)) == nil, "the atlas has eight markers, not sixteen")
assert(Client.RaidIconFromTexCoords(0, 1, 0, 1) == 1, "a whole-texture coordinate set is the first cell")
assert(Client.RaidIconFromTexCoords() == nil and Client.RaidIconFromTexCoords("a", "b", "c", "d") == nil,
    "nothing usable reads as no marker")
assert(Client:GetRaidTargetIconFromFrame("mouseover") == nil, "a unit with no frame of its own reads as nothing")

-- Quest waypoints: the client's own POI reads. Nothing in the addon depends
-- on them yet, so what matters is that a missing call, a wrong type, or a
-- secret value comes back as nil instead of a value the probe would print as
-- fact.
assert(not Client:HasQuestWaypoints(), "no GetNextWaypoint means no waypoints")
assert(Client:GetQuestWaypoint(821) == nil)
C_QuestLog.GetNextWaypoint = function(id)
    if id == 821 then return 1413, 0.473, 0.621 end
    if id == 822 then return nil end
    return 1413, "east", 0.5
end
C_QuestLog.GetNextWaypointText = function(id) return id == 821 and "Travel to the Sludge Fen" or nil end
C_QuestLog.IsOnMap = function(id) return id == 821, id == 821 end
C_QuestLog.GetQuestsOnMap = function(mapID)
    if mapID ~= 1413 then return nil end
    return { { questID = 821, x = 0.473, y = 0.621 }, { questID = "bogus", x = 0.1, y = 0.1 } }
end
QuestHasPOIInfo = function(id) return id == 821 end
GetQuestPOIBlobCount = function(id) return id == 821 and 1 or 0 end
assert(Client:HasQuestWaypoints())
local mapID, x, y = Client:GetQuestWaypoint(821)
assert(mapID == 1413 and x == 0.473 and y == 0.621)
assert(Client:GetQuestWaypoint(822) == nil, "a quest the client has nothing for reads as nothing")
assert(Client:GetQuestWaypoint(823) == nil, "a non-number coordinate is not a position")
assert(Client:GetQuestWaypoint("821") == nil)
assert(Client:GetQuestWaypointText(821) == "Travel to the Sludge Fen")
assert(Client:GetQuestWaypointText(822) == nil)
local hasPOI, onMap, localPOI = Client:QuestHasPOI(821)
assert(hasPOI == true and onMap == true and localPOI == true)
assert(select(1, Client:QuestHasPOI(822)) == false)
assert(Client:GetQuestPOICount(821) == 1)
local onMapQuests = Client:GetQuestsOnMap(1413)
assert(#onMapQuests == 1 and onMapQuests[1].questID == 821, "an entry without a usable quest ID is dropped")
assert(#Client:GetQuestsOnMap(1414) == 0)
assert(#Client:GetQuestsOnMap(nil) == 0)

-- A client that hides the numbers: every read has to come back empty rather
-- than hand the probe a secret value to print.
issecretvalue = function(value) return value == 0.473 or value == 821 or value == 1413 end
assert(Client:GetQuestWaypoint(821) == nil, "a secret coordinate is no coordinate")
assert(#Client:GetQuestsOnMap(1413) == 0, "a secret quest ID drops the entry")
issecretvalue = nil

-- Travel arrival is the arrow's own answer, and never claimed from a flight.
local onTaxi = false
local savedIsOnTaxi, savedNavigation = Client.IsOnTaxi, ns.modules.Navigation
Client.IsOnTaxi = function() return onTaxi end
local measured
ns.modules.Navigation = { Measure = function(_, location) measured = location; return "Arrived", 3, true, true end }
local spot = { mapID = 1413, x = 0.5, y = 0.5, arrivalRadiusNormalized = 0.03 }
assert(Client:MatchesObservedCompletion({ type = "location" }, spot) and measured == spot, "arrival is what the arrow measures")
ns.modules.Navigation.Measure = function() return "180 yd NE", 180, true, false end
assert(not Client:IsAtLocation(spot), "a map-fraction radius no longer calls 180 yards arrived")
ns.modules.Navigation.Measure = function() return "Arrived", 3, true, true end
onTaxi = true
assert(not Client:IsAtLocation(spot), "a flight passing over the spot is not arrival")
Client.IsOnTaxi, ns.modules.Navigation = savedIsOnTaxi, savedNavigation

-- Spells learned: every one named must be known. A cast step reads the
-- casts counted on it.
local savedPlayerSpell, savedProgress = _G.IsPlayerSpell, ns.modules.Progress
local knownSpells = { [100] = true }
_G.IsPlayerSpell = function(id) return knownSpells[id] == true end
assert(Client:MatchesObservedCompletion({ type = "spell", ids = { 100 } }))
assert(not Client:MatchesObservedCompletion({ type = "spell", ids = { 100, 772 } }), "Rend not learned yet")
knownSpells[772] = true
assert(Client:MatchesObservedCompletion({ type = "spell", ids = { 100, 772 } }))
-- A pet's spell (Blood Pact, read to the imp from its grimoire) is in the
-- pet's spellbook, not the player's.
local savedSpellKnown = _G.IsSpellKnown
_G.IsSpellKnown = function(id, isPet) return isPet == true and id == 6307 end
assert(Client:IsSpellKnown(6307), "a pet's spell counts as known")
assert(not Client:IsSpellKnown(6308))
_G.IsSpellKnown = savedSpellKnown
local castsSoFar = 0
ns.modules.Progress = { GetActiveGuide = function() return {} end, CastCount = function() return castsSoFar end }
assert(not Client:MatchesObservedCompletion({ type = "cast", spellID = 1259686, count = 1 }, nil, 4))
castsSoFar = 1
assert(Client:MatchesObservedCompletion({ type = "cast", spellID = 1259686, count = 1 }, nil, 4))
_G.IsPlayerSpell, ns.modules.Progress = savedPlayerSpell, savedProgress

-- The profession window, as a craft step's Make button reads it --------------
-- (the same reads as NuuProfessions' Client; the planner's own are not here).
local profRecords = {}
function ns:RecordHere(channel, data) table.insert(profRecords, { channel = channel, data = data }) end
function ns:Log() end
assert(Client.MarkRecipeLearned == nil and Client.RecordTrainer == nil and Client.GetAuctionatorPrice == nil
    and Client.KnownRecipeStore == nil, "the planner's reads went with it")
assert(Client:ProfessionSkillLine("Leatherworking") == 165 and Client:ProfessionSkillLine("first aid") == 129)
assert(Client:ProfessionSkillLine("Juggling") == nil)

local function itemLink(id, name) return "|cffffffff|Hitem:" .. id .. "::::::::20:::::|h[" .. name .. "]|h|r" end
local rows = {
    { "Armor Kits", "header", 0, true },
    { "Light Armor Kit", "optimal", 3, nil, nil, 1, item = 2304 },
    { "Cured Light Hide", "easy", 0, nil, nil, 1, item = 4231 },
}
local line = { "Leatherworking", 45, 75 }
GetTradeSkillLine = function() return line[1], line[2], line[3] end
GetNumTradeSkills = function() return #rows end
GetTradeSkillInfo = function(i) local r = rows[i]; return r[1], r[2], r[3], r[4], r[5], r[6] end
GetTradeSkillItemLink = function(i) return rows[i].item and itemLink(rows[i].item, rows[i][1]) end
local made, stopped = {}, 0
DoTradeSkill = function(index, count) table.insert(made, { index, count }) end
StopTradeSkill = function() stopped = stopped + 1 end
local heard = {}
Client:OnProfessionChange(function(kind, subject) table.insert(heard, kind .. ":" .. tostring(subject)) end)

assert(select(2, Client:FindCraft("Leatherworking", nil, 2304)) == "closed", "no window yet")
Client:OnProfessionEvent("TRADE_SKILL_SHOW")
assert(heard[1] == "tradeskill:Leatherworking" and heard[2] == "window:tradeskill",
    "the Make button hears the window read and open")
local snapshot = Client:GetTradeSkillSnapshot("leatherworking")
assert(snapshot and snapshot.skill == 45 and snapshot.maxSkill == 75 and #snapshot.order == 2, "read at once without C_Timer")
assert(Client:GetSnapshotRecipe("Leatherworking", "item:2304").name == "Light Armor Kit")
local found = Client:FindCraft("leatherworking", nil, 2304)
assert(found and found.api == "tradeskill" and found.index == 2 and found.available == 3 and found.skill == 45)
local why, other = select(2, Client:FindCraft("Tailoring", nil, 2304))
assert(why == "closed" and other == "Leatherworking", "another profession's window is not this one's")
assert(select(2, Client:FindCraft("Leatherworking", nil, 99999)) == "missing")
assert(Client:Craft("Leatherworking", nil, 2304, 10) == 3, "as many as the window says the materials allow")
assert(made[1][1] == 2 and made[1][2] == 3)
assert(select(2, Client:Craft("Leatherworking", nil, 4231, 2)) == "materials", "nothing to make it from")
assert(Client:Craft("Leatherworking", nil, 4231, 2, nil, 1) == 1, "what the bags make, when the window says none (Kit.Crafting)")

-- A batch made to a skill stops when the window shows it.
Client:Craft("Leatherworking", nil, 2304, 2, 47)
assert(Client.craftUntil and Client.craftUntil.skill == 47)
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
assert(stopped == 0, "still short of the skill")
line[2] = 47
Client:OnProfessionEvent("TRADE_SKILL_UPDATE")
assert(stopped == 1 and Client.craftUntil == nil, "stopped at the skill")
Client:OnProfessionEvent("TRADE_SKILL_CLOSE")
assert(heard[#heard] == "window:closed" and select(2, Client:FindCraft("Leatherworking", nil, 2304)) == "closed")
local crafts = 0
for _, record in ipairs(profRecords) do
    if record.channel == "prof" and record.data.event == "craft" then crafts = crafts + 1 end
end
assert(crafts >= 4, "every press goes to the prof channel")
assert(Client:CanOpenProfession("Leatherworking") == false, "no modern window to open on this client")
GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillItemLink = nil, nil, nil, nil
DoTradeSkill, StopTradeSkill = nil, nil

return true
