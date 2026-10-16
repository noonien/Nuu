_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
function ns:Log() end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Data/GuideCheck.lua")
Load(ns, "Data/Names.lua")
Load(ns, "Data/Steps.lua")
Load(ns, "Domain/Progress.lua")
Load(ns, "Domain/Materials.lua")
local Steps, GuideCheck, Progress, Materials = ns.modules.Steps, ns.modules.GuideCheck, ns.modules.Progress, ns.modules.Materials

local bags = {}
ns.modules.Client = {
    GetItemCount = function(_, id) return bags[id] or 0 end,
    MatchesCondition = function(_, predicate)
        -- Only the Warrior gating of the last craft step matters here.
        return not (predicate and predicate.type == "class")
    end,
}

local guide = Steps:Expand({
    kind = "guide", id = "test:materials", updated = 1789862400, title = "Materials", category = "test",
    data = { map = 1413, sections = {
    { title = "Steps", steps = {
        { type = "travel", to = "The Crossroads", at = { { 5150, 3030 } } }, -- 1 no materials
        { type = "craft", item = 2862, count = 5,                            -- 2
          needs = { { item = 2835, count = 5 }, { item = 2320, count = 2, source = "vendor" } } },
        { type = "craft", item = 2862, count = 5,                            -- 3
          needs = { { item = 2835, count = 5 }, { item = 2589, count = 2, source = "ah" } } },
        { type = "craft", item = 2862, count = 1,                            -- 4 gated out
          needs = { { item = 2835, count = 3 } }, cond = { class = "WARRIOR" } },
        { type = "finish", note = "The end." },
    } },
} },
})
local ok, errors = GuideCheck:Validate(guide)
assert(ok, table.concat(errors, "; "))

local needs = guide.nodes[2].needs
assert(#needs == 2 and needs[1].itemID == 2835 and needs[1].count == 5 and needs[1].source == "gather", "a source defaults to gather")
assert(needs[2].source == "vendor")
assert(guide.nodes[1].needs == nil, "a step that asks for nothing carries no list")
local items = guide.nodes[2].refs.items
assert(#items == 3, "the crafted item and its materials are all referenced for naming: " .. #items)

-- A bad source or a missing item ID is refused at load, not silently dropped.
local function expands(needs)
    return (pcall(Steps.Expand, Steps, { kind = "guide", id = "t", updated = 1, title = "t", category = "t",
        data = { sections = { { title = "s", steps = { { type = "craft", item = 1, needs = needs } } } } } }))
end
assert(expands({ { item = 2835, count = 5 } }), "a well-formed list expands")
assert(not expands({ { item = 2835, count = 5, source = "mailbox" } }), "an unknown source")
assert(not expands({ { item = "Rough Stone", count = 5 } }), "an item not named by ID")

-- One step's own list, against the bags.
bags[2835] = 2
local step = Materials:StepNeeds(guide.nodes[2])
assert(step[1].have == 2 and step[1].short == 3, "the shortfall is what is missing")
assert(step[2].have == 0 and step[2].short == 2)
bags[2835] = 9
assert(Materials:StepNeeds(guide.nodes[2])[1].short == 0, "enough carried is no shortfall")

-- The whole guide from a step, added up across steps and grouped by source.
Progress.store, Progress.session = {}, {}
ns.modules.GuideRepository = { Get = function(_, id) return id == guide.id and guide or nil end }
bags = {}
local outstanding = Materials:Outstanding(guide, 1)
assert(#outstanding == 3, "the gated step asks for nothing on this character: " .. #outstanding)
assert(outstanding[1].itemID == 2835 and outstanding[1].count == 10, "the same material adds up across steps")
assert(outstanding[1].firstStep == 2, "and remembers where it is first needed")
assert(outstanding[2].source == "vendor" and outstanding[3].source == "ah", "gathered first, then the vendor, then the auction house")
assert(outstanding[1].short == 10 and outstanding[1].have == 0)
bags[2835] = 6
outstanding = Materials:Outstanding(guide, 1)
assert(outstanding[1].have == 6 and outstanding[1].short == 4, "the bags count against the total")

-- From a later step, only what is still ahead is asked for.
outstanding = Materials:Outstanding(guide, 3)
assert(#outstanding == 2 and outstanding[1].count == 5, "the step behind no longer asks")

-- A step already finished drops out, even when the list starts before it.
local state = Progress:GetState(guide)
state.statuses[2] = "complete"
outstanding = Materials:Outstanding(guide, 1)
assert(outstanding[1].count == 5 and #outstanding == 2, "a finished step asks for nothing")

bags[2835] = 0
local missing, total = Materials:Summary(guide, 1)
assert(total == 2 and missing == 2, "the summary counts the materials still short")
bags[2835], bags[2589] = 99, 99
missing, total = Materials:Summary(guide, 1)
assert(total == 2 and missing == 0, "carrying everything leaves nothing missing")

-- A guide listed by section asks only for the section it is in.
local sectioned = Steps:Expand({
    kind = "guide", id = "test:materials:sections", updated = 1789862400,
    title = "Materials by section", category = "test", materials = "section",
    data = { map = 1413, sections = {
        { title = "Stones", steps = {
            { type = "gather", item = 2835, count = 5 },                                     -- 1
            { type = "craft", item = 2862, count = 5, needs = { { item = 2835, count = 5 } } }, -- 2
        } },
        { title = "Cloth", steps = {
            { type = "gather", item = 2589, count = 4 },                                     -- 3
            { type = "craft", item = 2996, count = 2, needs = { { item = 2589, count = 4 } } }, -- 4
        } },
    } },
})
assert(GuideCheck:Validate(sectioned))
bags = {}
outstanding = Materials:Outstanding(sectioned, 1)
assert(#outstanding == 1 and outstanding[1].itemID == 2835, "only the first section's stones")
outstanding = Materials:Outstanding(sectioned, 3)
assert(#outstanding == 1 and outstanding[1].itemID == 2589, "then only the cloth")
local last, section = Materials:ListEnd(sectioned, 2)
assert(last == 2 and section.title == "Stones")
assert(Materials:ListEnd(guide, 1) == #guide.nodes, "an ordinary guide lists to its end")
sectioned.meta.materials = "sometimes"
assert(not GuideCheck:Validate(sectioned), "only section or guide")

assert(Materials:GuideHasMaterials(guide))
assert(not Materials:GuideHasMaterials({ nodes = { { kind = "note", title = "n" } } }), "a guide with no materials shows no list")
assert(Materials:SourceWord("ah") == "auction house" and Materials:SourceWord(nil) == "gather")

return true
