_G = _G or _ENV
-- The import (Data/Import.lua) on the export format's worked example, which
-- uses every feature once: it must expand and validate like a packaged guide,
-- and each feature must land where the runtime reads it.
local ns = { modules = {}, idNames = nil }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Data/IDNames.lua")
Load(ns, "Data/Import.lua")
local Import, Steps, Schema = ns.modules.GuideImport, ns.modules.Steps, ns.modules.Schema

local example = dofile("docs/examples/guide-export.lua")
-- The example's IDs are made up; the areas, flight node and skills it names
-- are real ones the packaged guides use, but not every one is in the table.
ns.idNames.areas[380] = ns.idNames.areas[380] or "The Crossroads"
ns.idNames.areas[392] = ns.idNames.areas[392] or "Ratchet"
ns.idNames.taxiNodes[25] = ns.idNames.taxiNodes[25] or "Crossroads, The Barrens"

local authored = Import:ToAuthored(example)
local guide = Steps:Expand(authored)
local ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors or {}, "; "))

-- The wrapper.
assert(guide.id == "nuuroad:example:every-feature" and guide.updated == 1790985600)
assert(guide.meta.title == "Example: every feature" and guide.meta.category == "Fixtures/Examples")
assert(guide.meta.levels[1] == 13 and guide.meta.levels[2] == 16, "levels { from, to } -> { 13, 16 }")
assert(guide.meta.materials == "section")
assert(guide.condition.type == "faction" and guide.condition.values[1] == "Horde")
assert(#guide.sections == 7 and guide.sections[1].title == "Crossroads")

local byLabel, byQuest = {}, {}
for _, node in ipairs(guide.nodes) do
    if node.label then byLabel[node.label] = node end
    for _, id in ipairs(node.refs and node.refs.quests or {}) do byQuest[id] = byQuest[id] or node end
end
-- Section and group labels name their first step.
local function sectionStart(title)
    for _, section in ipairs(guide.sections) do
        if section.title == title then return guide.nodes[section.nodeIndexes[1]] end
    end
end
byLabel.ratchet, byLabel.forge = sectionStart("Ratchet"), sectionStart("The forge")
byLabel.razormanes = guide.nodes[guide.groups[2].first]
local n = guide.nodes
local function find(test)
    for _, node in ipairs(n) do if test(node) then return node end end
end

-- Points are hundredths of a percent; an NPC's position comes from `npcs`.
local mound = find(function(node) return node.auto and node.auto.object == "Mound of Dirt" end)
assert(math.abs(mound.location.x - 0.618) < 1e-9 and math.abs(mound.location.y - 0.212) < 1e-9)
assert(mound.completion.observed.type == "quests" and mound.completion.observed.state == "readyToTurnIn",
    "an interact for a whole quest is done once it is ready")
local tonga = find(function(node) return node.auto and node.auto.verb == "accept" and node.auto.quests[1] == 870 end)
assert(tonga.location.npc == 3448 and #tonga.location.spots == 1, "Tonga stands at one of two spots")
assert(tonga.body == "Beside the well, or under the tower.", "the NPC's note is shown on the visit")
local spirit = find(function(node) return node.auto and node.auto.verb == "accept" and node.auto.quests[1] == 906 end)
assert(spirit.location.point == "windfury.chamber", "an NPC on a place point")

-- Conditions: `cond` hides for good, `show` is read when the guide gets there.
local talk = n[1].kind == "note" and n[2] or n[1]
assert(talk.kind == "talk" and talk.condition.type == "not" and talk.condition.child.values[1] == "tauren")
local miners = find(function(node) return node.auto and node.auto.verb == "accept" and node.auto.quests[1] == 97970 end)
assert(miners.condition.type == "now" and miners.condition.child.type == "profession"
    and miners.condition.child.name == "Mining", "show = { skill = 186 } -> now profession Mining")
local bag = find(function(node) return node.kind == "note" and node.body and node.body:find("Small Brown Pouch") end)
local noAH = bag.condition
assert(noAH.type == "now" and noAH.child.type == "any" and noAH.child.children[1].type == "selfFound"
    and noAH.child.children[2].type == "not" and noAH.child.children[2].child.type == "auctionHouse",
    "a named condition is read as show when it asks a realm answer")
local learn = find(function(node) return node.auto and node.auto.verb == "learn" end)
assert(learn.condition.type == "class" and learn.auto.spells[2] == 772)

-- Areas, flight nodes and skills are named for the comparisons.
local hearth = find(function(node) return node.kind == "hearth" end)
assert(hearth.completion.observed.name == "The Crossroads")
local flight = find(function(node) return node.kind == "flight" end)
assert(flight.completion.observed.name == "Crossroads, The Barrens")
local ratchet = byLabel.ratchet
assert(ratchet.kind == "travel" and ratchet.completion.observed.type == "subzone" and ratchet.completion.observed.name == "Ratchet")
local orgrimmar = find(function(node) return node.kind == "travel" and node.auto.label == "Orgrimmar" end)
assert(orgrimmar.completion.observed.type == "zone" and orgrimmar.completion.observed.mapID == 1454)
assert(orgrimmar.location.mapID == 1411, "a point keeps its own map")
local wailing = find(function(node) return node.kind == "travel" and node.auto.label == "Wailing Caverns" end)
assert(wailing.completion.observed.type == "instance" and wailing.completion.observed.instanceID == 43)
local train = find(function(node) return node.kind == "train" and node.auto.skill == "Blacksmithing" and node.auto.rank == 50 end)
assert(train and train.completion.observed.atLeast == 50)
local gather = find(function(node) return node.kind == "gather" end)
assert(gather.auto.skill == "Mining" and gather.auto.upto.skill == "Blacksmithing" and gather.auto.upto.rank == 50)
assert(gather.completion.observed.type == "any", "upto escapes the gather")

-- Quest work.
local razormanes = byLabel.razormanes
assert(razormanes.auto.verb == "objective" and razormanes.auto.part == 1 and razormanes.auto.kill[1] == 3267)
assert(razormanes.auto.count == nil, "the objective says how many")
local pools = find(function(node) return node.kind == "travel" and node.auto.label == "The Forgotten Pools" end)
assert(pools.completion.observed.type == "objective" and pools.completion.observed.questID == 870,
    "a travel with an objective finishes on the objective alone")
local cobrahn = find(function(node) return node.auto and node.auto.part == 1 and node.auto.quests[1] == 914 end)
assert(cobrahn.location == nil, "an NPC inside a dungeon has no position")
local unknown = find(function(node) return node.auto and node.auto.part == 2 and node.auto.quests[1] == 914 end)
assert(unknown and unknown.completion.observed.index == 2, "a step with only its objective")
local gazlowe = find(function(node) return node.auto and node.auto.quests and node.auto.quests[1] == 896 end)
assert(gazlowe.say[1] == 41231 and gazlowe.say[2] == 41232, "a talk step keeps its dialog options")
assert(Steps:Title(gazlowe) == "Talk to Gazlowe")

-- An optional turn-in is passed over unless a quest is ready.
local dizzywig = find(function(node) return node.kind == "turnInQuest" and node.auto.quests[1] == 865 end)
local ready = dizzywig.condition
assert(ready.type == "now" and ready.child.type == "any" and ready.child.children[2].id == 1492
    and ready.child.children[2].state == "readyToTurnIn")

-- An accept from an item passes when the item is not in the bags; carried,
-- it waits like any carried step.
local keg = find(function(node) return node.kind == "acceptQuest" and node.auto.quests[1] == 819 end)
assert(keg.condition.type == "now" and keg.condition.child.type == "item" and keg.condition.child.id == 4926)
local owatanka = find(function(node) return node.kind == "acceptQuest" and node.auto.quests[1] == 884 end)
assert(owatanka.sticky and owatanka.condition == nil and owatanka.auto.kill[1] == 3473, "kill, loot and accept in one step")
assert(owatanka.refs.items[1] == 5102, "the item that starts it is the step's")

-- Carried steps.
local beaks = find(function(node) return node.auto and node.auto.collect and node.auto.collect[1] == 5087 end)
assert(beaks.carriedFrom == byLabel.beaks.index, "`from` names the step the work starts at")
local road = find(function(node) return node.kind == "travel" and node.auto.label == "Up the road north" end)
assert(road.companionOf == byLabel.razormanes.index)
local grind = find(function(node) return node.kind == "levelTarget" and node.auto.level == 14 end)
assert(grind.auto.by == byLabel.ratchet.index and grind.mark[2] == 2956)
local kill, _ = Steps:NPCs(grind)
assert(kill[1] == 2955 and kill[2] == 2956, "marked creatures are targets")
local choice = find(function(node) return node.kind == "choice" end)
assert(choice.choices[1]["next"] == byLabel.circuit.index and choice.choices[2]["next"] == byLabel.forge.index)

-- Groups, materials, places.
assert(#guide.groups == 2)
local craft = find(function(node) return node.kind == "craft" end)
assert(#craft.needs == 3 and craft.needs[1].source == "ah" and craft.needs[3].count == 2)
assert(guide.places[1].place == "windfury" and #guide.places[1].points == 5)
assert(guide.places[1].connections[4][3] == true and guide.places[1].connections[1][3] == nil)

-- The objective's count is the client's, asked when the step is shown.
ns.modules.Client = { GetQuestObjectives = function(_, questID)
    return questID == 871 and { { text = "Razormane Water Seeker slain: 2/8", need = 8 } } or {}
end }
assert(Steps:Count(razormanes) == 8)
assert(Steps:Title(razormanes, true) == "Kill 8 Razormane Water Seeker", Steps:Title(razormanes, true))
ns.modules.Client = nil

-- What the import refuses.
local function refuses(mutate, expected)
    local copy = dofile("docs/examples/guide-export.lua")
    mutate(copy)
    local fine, message = pcall(Import.ToAuthored, Import, copy)
    assert(not fine and tostring(message):find(expected, 1, true), tostring(message))
end
refuses(function(value) value.format = 2 end, "guide.format")
refuses(function(value) value.data.sections[1].steps[1].type = "teleport" end, "unknown step type 'teleport'")
refuses(function(value) value.data.sections[1].steps[1].cond = { colour = "red" } end, "is not a condition")
refuses(function(value) value.data.sections[1].steps[1].cond = { is = "missing" } end, "no condition named 'missing'")
refuses(function(value) value.data.sections[3].steps[3].quest = { 914 } end, "must be { quest, objective }")
refuses(function(value) value.data.sections[4].steps[1].area = 999999 end, "no name for areas 999999")

-- Every packaged guide reads, expands and validates.
local packaged = { modules = {}, Kit = ns.Kit }
function packaged:RegisterModule(name, module) self.modules[name] = module end
Load(packaged, "Data/Schema.lua")
Load(packaged, "Data/Names.lua")
Load(packaged, "Data/Steps.lua")
LoadBuiltIns(packaged)
local count = 0
for id, source in pairs(packaged.builtInGuides) do
    if not id:find("^nuuroad:fixture:") then
        count = count + 1
        local expanded = packaged.modules.Steps:Expand(source)
        local valid, problems = packaged.modules.Schema:Validate(expanded)
        assert(valid, id .. ": " .. table.concat(problems or {}, "; "))
    end
end
assert(count == 22, "the 22 packaged guides read, got " .. count)

-- A step carried from a label rides on the card from there until reached.
Load(packaged, "Domain/Progress.lua")
local Progress = packaged.modules.Progress
Progress.store, Progress.session = {}, {}
local carriedGuide = packaged.modules.Steps:Expand(Import:ToAuthored(dofile("docs/examples/guide-export.lua")))
packaged.modules.GuideRepository = { Get = function(_, id) return id == carriedGuide.id and carriedGuide or nil end }
local carried = carriedGuide.nodes[beaks.index]
local function carriedOn(index)
    for _, node in ipairs(Progress:Carried(carriedGuide, carriedGuide.nodes[index])) do
        if node == carried then return true end
    end
    return false
end
assert(not carriedOn(carried.carriedFrom), "not on the labelled step itself")
assert(carriedOn(carried.carriedFrom + 1), "from the step after the label")
assert(carriedOn(carried.index - 1), "up to the step before it")
assert(not carriedOn(carried.index), "the step itself once reached")

print("NuuRoad import tests passed")
return true
