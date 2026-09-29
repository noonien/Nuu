-- Run from the addon root with a standalone Lua interpreter:
--   lua Tests/TestRunner.lua
_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/Schema.lua")
local Schema = ns.modules.Schema

local function validGuide()
    return {
        schema = 2, id = "test:guide", updated = 1789862400,
        meta = { title = "Test", category = "test" },
        sections = { { id = "one", title = "One", nodeIndexes = { 1, 2 } } },
        nodes = {
            { kind = "action", title = "First", ["next"] = 2, completion = { type = "manual" } },
            { kind = "end", title = "Last", completion = { type = "manual" } },
        },
    }
end

local guide = validGuide()
local ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))

guide.nodes[2]["next"] = 99
ok = Schema:Validate(guide)
assert(not ok, "dangling edges must be rejected")

-- A category is a path of folders, any depth, each folder named.
for _, category in ipairs({ "Leveling/The Barrens", "Dungeons / Wailing Caverns / Horde", "leveling" }) do
    guide = validGuide(); guide.meta.category = category
    ok, errors = Schema:Validate(guide)
    assert(ok, category .. ": " .. table.concat(errors or {}, "; "))
end
for _, category in ipairs({ "Leveling//Barrens", "/Leveling", "Leveling/", "Leveling/  /Barrens" }) do
    guide = validGuide(); guide.meta.category = category
    ok, errors = Schema:Validate(guide)
    assert(not ok and errors[1]:find("guide.meta.category", 1, true), "an unnamed folder must be rejected: " .. category)
end

guide = validGuide()
guide.nodes[2].id = "old-id"
ok = Schema:Validate(guide)
assert(not ok, "authored node IDs must be rejected")

guide = validGuide()
guide.nodes[1].condition = { type = "all", children = { { type = "not", child = { type = "level" } } } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))

guide.nodes[1].completion = { type = "observed", observed = { type = "quests", state = "finished", match = "all", ids = { 1 } } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))

guide.nodes[1].completion = { type = "observed", observed = { type = "quests", state = "invalid", ids = { 1 } } }
ok = Schema:Validate(guide)
assert(not ok, "invalid observed completion state must be rejected")

guide = validGuide()

guide.nodes[1].location = { mapID = 1, x = 1.2, y = 0.5 }
ok = Schema:Validate(guide)
assert(not ok, "out-of-bounds locations must be rejected")

guide = validGuide()
guide.nodes[1].completion = { type = "observed", observed = { type = "location" } }
ok = Schema:Validate(guide)
assert(not ok, "an observed location completion needs a location")
guide.nodes[1].location = { mapID = 1, x = 0.5, y = 0.5 }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))

-- Kills counted from the combat log need creature IDs and a positive count.
guide = validGuide()
guide.nodes[1].completion = { type = "observed", observed = { type = "kills", npcs = { 3244, 3245 }, count = 3 } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
guide.nodes[1].completion = { type = "observed", observed = { type = "kills", npcs = {} } }
ok = Schema:Validate(guide)
assert(not ok, "a kills completion without creatures must be rejected")
guide.nodes[1].completion = { type = "observed", observed = { type = "kills", npcs = { "Plainstrider" } } }
ok = Schema:Validate(guide)
assert(not ok, "creature names are not creature IDs")
guide.nodes[1].completion = { type = "observed", observed = { type = "kills", npcs = { 3244 }, count = 0 } }
ok = Schema:Validate(guide)
assert(not ok, "a kill count must be positive")

-- An item rule may name the quest it begins or the quest it is for, by ID.
guide = validGuide()
guide.nodes[1].completion = { type = "observed", observed = { type = "item", itemID = 4926, startsQuestID = 819 } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
guide.nodes[1].completion = { type = "observed", observed = { type = "item", itemID = 4986, questID = "924" } }
ok = Schema:Validate(guide)
assert(not ok, "a quest tie on an item rule must be a number")

-- Skill, craft, gear, and reputation rules.
guide = validGuide()
guide.nodes[1].completion = { type = "observed", observed = { type = "skill", name = "Mining", atLeast = 150 } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
guide.nodes[1].completion = { type = "observed", observed = { type = "skill", name = "Mining" } }
ok = Schema:Validate(guide)
assert(not ok, "a skill rule needs a rank")
guide.nodes[1].completion = { type = "observed", observed = { type = "skill", name = "", atLeast = 1 } }
ok = Schema:Validate(guide)
assert(not ok, "a skill rule needs a name")
guide.nodes[1].completion = { type = "observed", observed = { type = "crafted", itemID = 2862, count = 5 } }
assert(Schema:Validate(guide))
guide.nodes[1].completion = { type = "observed", observed = { type = "crafted", itemID = 2862, count = 0 } }
assert(not Schema:Validate(guide), "a craft count must be positive")
guide.nodes[1].completion = { type = "observed", observed = { type = "equipped", itemID = 7360 } }
assert(Schema:Validate(guide))
guide.nodes[1].completion = { type = "observed", observed = { type = "equipped", itemID = "Ornate Mail Gloves" } }
assert(not Schema:Validate(guide), "gear is named by ID")
guide.nodes[1].completion = { type = "observed", observed = { type = "reputation", factionID = 576, standing = 6 } }
assert(Schema:Validate(guide))
guide.nodes[1].completion = { type = "observed", observed = { type = "reputation", factionID = 576, standing = 9 } }
assert(not Schema:Validate(guide), "there is no standing past Exalted")
guide.nodes[1].completion = { type = "observed", observed = { type = "reputation", factionID = 576, standing = "Honored" } }
assert(not Schema:Validate(guide), "a stored standing is a number")

-- Materials on a node.
guide = validGuide()
guide.nodes[1].needs = { { itemID = 2835, count = 5, source = "gather" } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
guide.nodes[1].needs = { { itemID = 2835, count = 5, source = "mailbox" } }
assert(not Schema:Validate(guide), "a material comes from a known kind of place")
guide.nodes[1].needs = { { itemID = 2835, count = 0, source = "gather" } }
assert(not Schema:Validate(guide), "a material count is positive")
guide.nodes[1].needs = { { count = 5, source = "gather" } }
assert(not Schema:Validate(guide), "a material is named by item ID")
guide.nodes[1].needs = {}
assert(not Schema:Validate(guide), "an empty material list is not a list")

-- Any-of completions validate their children like all-of does.
guide = validGuide()
guide.nodes[1].completion = { type = "observed", observed = { type = "any", children = {
    { type = "item", itemID = 2770, count = 20 },
    { type = "skill", name = "Mining", atLeast = 150 },
} } }
ok, errors = Schema:Validate(guide)
assert(ok, table.concat(errors, "; "))
guide.nodes[1].completion = { type = "observed", observed = { type = "any", children = { { type = "skill", name = "Mining" } } } }
assert(not Schema:Validate(guide), "a broken child breaks the any-of")
guide.nodes[1].completion = { type = "observed", observed = { type = "any", children = {} } }
assert(not Schema:Validate(guide), "an any-of needs children")

return true
