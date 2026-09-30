-- Run from the addon root with a standalone Lua interpreter:
--   lua Tests/TestRunner.lua
_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Domain/GuideCatalog.lua")
local Catalog = ns.modules.GuideCatalog

local function guide(id, category, levels, extra)
    local result = { id = id, meta = { title = id, category = category, levels = levels, tags = extra and extra.tags }, nodes = {} }
    if extra then result.condition = extra.condition end
    return result
end
local function titles(list)
    local names = {}
    for _, item in ipairs(list) do table.insert(names, item.id) end
    return table.concat(names, ",")
end

-- A path splits on "/" and trims; a single word is a path of one, and a
-- guide with no category files under Other.
local path = Catalog:Path(guide("a", " Leveling / Kalimdor/The Barrens "))
assert(#path == 3 and path[1] == "Leveling" and path[3] == "The Barrens", "a path splits and trims")
assert(Catalog:Path(guide("b", "dungeon"))[1] == "dungeon", "one word is one folder")
assert(Catalog:Path({ meta = {} })[1] == "Other", "no category files under Other")
assert(Catalog:PathText(path) == "Leveling / Kalimdor / The Barrens")
assert(Catalog:PathText(path, 2) == "Kalimdor / The Barrens", "a path can be read from a depth on")
assert(Catalog:Key(path, 2) == "leveling/kalimdor")
assert(Catalog:IsFixture(guide("f", "Fixtures/Travel")) and Catalog:IsFixture(guide("g", "fixture")))
assert(not Catalog:IsFixture(guide("h", "Leveling/Fixtures")), "only a top folder marks a fixture")

-- The tree: any depth, folders merged without regard to case (the first
-- spelling wins), counts over the whole subtree, folders by their lowest
-- level then name, and guides by level then title.
local barrens2 = guide("barrens2", "Leveling/Kalimdor/The Barrens", { 20, 25 })
local barrens1 = guide("barrens1", "leveling/kalimdor/the barrens", { 13, 21 })
local mulgore = guide("mulgore", "Leveling/Kalimdor/Mulgore", { 1, 12 })
local kalimdor = guide("kalimdor", "Leveling/Kalimdor", { 1, 60 })
local wc = guide("wc", "Dungeons/Wailing Caverns", { 17, 24 })
local tree = Catalog:Tree({ barrens2, wc, barrens1, mulgore, kalimdor })
assert(tree.total == 5)
assert(#tree.children == 2 and tree.children[1].name == "Leveling" and tree.children[2].name == "Dungeons", "folders sort by level")
assert(tree.byKey["leveling"].level == 1 and tree.byKey["dungeons"].level == 17, "a folder's level is its lowest")
local leveling = tree.byKey["leveling"]
assert(leveling.total == 4 and #leveling.guides == 0 and leveling.depth == 1)
local kalimdorFolder = tree.byKey["leveling/kalimdor"]
assert(kalimdorFolder.total == 4 and titles(kalimdorFolder.guides) == "kalimdor", "a folder holds its own guides and counts its subtree")
local barrens = tree.byKey["leveling/kalimdor/the barrens"]
assert(barrens.name == "The Barrens" and barrens.depth == 3, "the first spelling met is the one shown")
assert(barrens.path[1] == "Leveling" and barrens.path[2] == "Kalimdor" and barrens.path[3] == "The Barrens", "a folder knows its path")
assert(titles(barrens.guides) == "barrens1,barrens2", "guides by level")
assert(titles(Catalog:Under(leveling)) == "kalimdor,mulgore,barrens1,barrens2", "a folder lists everything beneath it, in tree order")
assert(#Catalog:Under(nil) == 0)
assert(titles(Catalog:Sort({ barrens2, wc, mulgore, barrens1 })) == "mulgore,barrens1,wc,barrens2", "sorted by level, whatever the folder")
local rfc = guide("rfc", "Dungeons/Ragefire Chasm", { 13, 18 })
local dungeons = Catalog:Tree({ wc, rfc }).byKey["dungeons"]
assert(dungeons.children[1].name == "Ragefire Chasm", "folders by level, not name")

-- Level fit.
assert(Catalog:LevelFit(barrens1, 15) == "now" and Catalog:LevelFit(barrens1, 13) == "now" and Catalog:LevelFit(barrens1, 21) == "now")
assert(Catalog:LevelFit(barrens1, 12) == "later" and Catalog:LevelFit(barrens1, 22) == "past")
assert(Catalog:LevelFit(barrens1, nil) == nil and Catalog:LevelFit(guide("x", "x"), 15) == nil, "unknown either way is nil")

-- Only a definite no rules a guide out.
local horde = guide("horde", "Leveling", nil, { condition = { type = "faction", value = "Horde" } })
assert(Catalog:ForCharacter(horde, function() return false end) == false)
assert(Catalog:ForCharacter(horde, function() return nil end) == true, "unknown is not a no")
assert(Catalog:ForCharacter(barrens1, function() return false end) == true, "a guide with no condition is for everyone")

-- Search: every word must match; a number is a level where the guide has a range.
local tagged = guide("The Barrens", "Leveling/Kalimdor/The Barrens", { 13, 21 }, { tags = { "crossroads" } })
local text = Catalog:SearchText(tagged, "Chen's Empty Keg")
assert(Catalog:Matches(tagged, "barrens", text) and Catalog:Matches(tagged, "KALIMDOR crossroads", text))
assert(Catalog:Matches(tagged, "chen's", text), "extra text is searched")
assert(not Catalog:Matches(tagged, "barrens mulgore", text), "every word must match")
assert(Catalog:Matches(tagged, "barrens 15", text) and not Catalog:Matches(tagged, "barrens 30", text), "a number is a level")
assert(not Catalog:Matches(tagged, "2", text), "a number is not a digit search when the guide has a range")
local unranged = guide("Scarlet 40", "Dungeons")
assert(Catalog:Matches(unranged, "40", Catalog:SearchText(unranged)), "without a range, digits are searched as text")
assert(Catalog:Matches(tagged, "   ", text), "an empty search matches")

print("guide catalog tests passed")
