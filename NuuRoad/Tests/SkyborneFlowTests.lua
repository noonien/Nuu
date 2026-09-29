_G = _G or _ENV
local ns = { modules = {}, builtInGuides = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

-- The packaged Skyborne guide as the flow walks it for one character: a
-- Horde Skyborne Warrior at level 4 who took the Mining book from Dalia.
-- These are the steps in-game bug reports caught stopping the guide, or
-- showing, for the wrong character.
Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/Schema.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Data/BuiltIn/SkyborneZephrasIsle.lua")
local Progress, Steps = ns.modules.Progress, ns.modules.Steps
local guide = Steps:Expand(ns.builtInGuides["nuuroad:leveling:skyborne-zephras-isle"])

local stubbed = { "UnitClass", "UnitRace", "UnitFactionGroup", "UnitLevel", "GetMoney", "GetItemCount",
    "GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo", "C_QuestLog" }
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Skyborne", "Skyborne" end
UnitFactionGroup = function() return "Horde" end
UnitLevel = function() return 4 end
GetMoney = function() return 250 end
local bags = { [247840] = 1 }
GetItemCount = function(id) return bags[id] or 0 end
local skills = { { "Unarmed", false, 1, 20 }, { "Orcish", false, 300, 300 } }
GetNumSkillLines = function() return #skills end
GetSkillLineInfo = function(index) local s = skills[index]; return s[1], s[2], true, s[3], 0, 0, s[4] end
C_QuestLog = { IsOnQuest = function() return false end, IsQuestFlaggedCompleted = function(id) return id == 93552 end }

local function only(node) return Steps:DescribeCondition(node.condition) or "" end
local function find(test)
    for _, node in ipairs(guide.nodes) do if test(node) then return node end end
end
local function walk(from, count)
    local seen, node = {}, from
    for _ = 1, count do
        local nextIndex = Progress:NextIndex(guide, node)
        node = guide.nodes[nextIndex]
        if not node then break end
        table.insert(seen, node)
    end
    return seen
end

-- The book taken is read; the two not taken are passed over, not waited on.
local turnin = find(function(node) return node.kind == "turnInQuest" and Steps:Title(node):find("Harvesting Windstones") end)
assert(turnin, "the guide turns in Harvesting Windstones")
local after = walk(turnin, 3)
assert(Steps:Title(after[1]) == "Train Mining", "the Mining book is next: " .. Steps:Title(after[1]))
for _, node in ipairs(after) do
    assert(not Steps:Title(node):find("Herbalism") and not Steps:Title(node):find("Skinning"),
        "a book not taken is passed over: " .. Steps:Title(node))
end

-- Once Mining is learned, its tools are bought and the other professions' are not.
skills[3] = { "Mining", false, 1, 75 }
for _, node in ipairs(walk(turnin, 30)) do
    assert(not only(node):find("Herbalism") and not only(node):find("Skinning"), "another profession's step is passed over: " .. Steps:Title(node))
end
local pick = find(function(node) return node.kind == "buy" and only(node):find("Mining") end)
assert(not Progress:IsBypassed(pick) and Progress:IsAvailable(pick), "a miner buys the pick")

-- `|` is AND: a Hunter trainer visit at level 4 is not a Warrior's step.
local hunter = find(function(node) return only(node) == "Hunter | now level 4 | now gold 200" end)
assert(Progress:IsRuledOut(hunter), "the Hunter trainer visit is not in a Warrior's guide")
local druid = find(function(node) return only(node) == "Druid | now level 4 | now gold 200" end)
assert(Progress:IsRuledOut(druid))

-- A Warrior without the silver for training is not held at the trainer.
local warrior = find(function(node) return only(node) == "Warrior | now level 6 | now gold 100" end)
UnitLevel = function() return 6 end
GetMoney = function() return 50 end
assert(Progress:IsBypassed(warrior), "too poor to train: passed over")
GetMoney = function() return 150 end
assert(not Progress:IsBypassed(warrior) and Progress:IsAvailable(warrior))

-- The crystals are clicked while the Agitators are killed: one group.
local crystals = find(function(node) return node.kind ~= "reminder" and Steps:Title(node):find("Windstone Cluster") end)
local range = ns.modules.Schema:GroupAt(guide, crystals.index)
assert(range, "the Windstone Cluster step is in a group")
local convert = find(function(node) return Steps:Title(node):find("Al'Aketh Convert") end)
assert(convert.index >= range.first and convert.index <= range.last, "with the Al'Aketh Converts")

-- Raan Wildwind's Camping 101 quests, on a client that lists no skill lines
-- and names professions only through GetProfessions: its slots come back
-- with gaps (no archaeology, no fishing), and cooking and first aid sit
-- behind them. Only the professions this character knows are offered.
GetNumSkillLines, GetSkillLineInfo = nil, nil
local professions = { "Mining", "Blacksmithing", nil, nil, "Cooking", "First Aid" }
GetProfessions = function() return 1, 2, nil, nil, 5, 6 end
GetProfessionInfo = function(slot) return professions[slot], 0, 5, 75 end
local camping = {}
for _, node in ipairs(guide.nodes) do
    local name = only(node):match("^now profession (.+)$")
    if name and Steps:Title(node):find("Camping 101") then camping[name] = node end
end
assert(camping.Skinning and camping.Mining and camping["First Aid"], "the guide offers each Camping 101 quest")
for name, node in pairs(camping) do
    local known = name == "Mining" or name == "Blacksmithing" or name == "First Aid"
    assert(Progress:IsAvailable(node) == known, "Camping 101: " .. name .. (known and " is offered" or " is not offered"))
    assert(Progress:IsBypassed(node) == not known, "Camping 101: " .. name .. (known and " is waited on" or " is passed over"))
end
assert(ns.modules.Client:GetSkillRank("First Aid") == 5, "a profession behind an empty slot is read")
-- No profession at all is an answer too, not an unknown.
GetProfessions = function() return nil, nil, nil, nil, nil, nil end
assert(not Progress:IsAvailable(camping.Mining), "no professions: nothing is offered")

for _, name in ipairs(stubbed) do _G[name] = nil end
return true
