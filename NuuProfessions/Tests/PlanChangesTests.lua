-- The plan's change history (Domain/PlanChanges.lua): what counts as a
-- change, why it happened, what it did, and how many are kept. The routes
-- here are the few fields the history reads, shaped as Planner:Plan and
-- Planner:Sections answer them.
local ns = NewNamespace()
Load(ns, "Domain/PlanChanges.lua")
local Changes = ns.modules.PlanChanges

local function check(value, message)
    if not value then error(message, 2) end
end

local DRESS, BAG, GLOVES = 8467, 6688, 3852
local WOOL, THREAD, BOLT = 2592, 2321, 2997
local NAMES = { [DRESS] = "White Woolen Dress", [BAG] = "Red Woolen Bag", [GLOVES] = "Gloves of Meditation",
    [WOOL] = "Wool Cloth", [THREAD] = "Fine Thread", [BOLT] = "Bolt of Woolen Cloth" }
local names = {
    item = function(id) return NAMES[id] or ("item " .. id) end,
    recipe = function(spell) return NAMES[spell] or ("recipe " .. spell) end,
    money = function(copper) return ns.Kit.FormatMoney(copper, false, false) end,
}

-- A Tailoring plan from `skill`: the Dress to `dressTo`, then the Bag to
-- `bagTo`, then the Gloves to 150, wool at `wool` copper, `carried` wool in
-- the bags. The Dress takes 9 wool a craft, the Bag 12.
local function plan(skill, dressTo, bagTo, wool, carried)
    local dress = dressTo - skill
    local route = {
        startSkill = skill, target = 160, summary = { net = 2600000 + wool * 1000 + dress * 100 },
        runs = {
            { spell = DRESS, fromSkill = skill, toSkill = dressTo, count = dress },
            { spell = BAG, fromSkill = dressTo, toSkill = bagTo, count = bagTo - dressTo },
            { spell = GLOVES, fromSkill = bagTo, toSkill = 150, count = 150 - bagTo },
        },
        shopping = {
            { itemID = WOOL, count = 1000, have = carried or 0, each = wool, source = "ah" },
            { itemID = THREAD, count = 200, have = 0, each = 100, source = "vendor" },
        },
    }
    local sections = {
        { kind = "recipe", spell = DRESS, title = "White Woolen Dress " .. skill .. "-" .. dressTo,
            shopping = { { itemID = THREAD, count = dress, source = "vendor" }, { itemID = WOOL, count = dress * 9, source = "ah" },
                { itemID = BOLT, count = 1, source = "gather", made = true } } },
        { kind = "recipe", spell = BAG, title = "Red Woolen Bag " .. dressTo .. "-" .. bagTo,
            shopping = { { itemID = WOOL, count = (bagTo - dressTo) * 12, source = "ah" } } },
    }
    return route, sections
end

local known = { [DRESS] = true, [BAG] = true, ["item:4307"] = true }

local function snapshot(skill, dressTo, bagTo, wool, carried, knownSet)
    local route, sections = plan(skill, dressTo, bagTo, wool, carried)
    return Changes:Snapshot(route, sections, knownSet or known)
end

local function effect(entry, kind, item)
    for _, each in ipairs(entry.effects) do
        if each.kind == kind and (item == nil or each.item == item) then return each end
    end
end

local function cause(entry, kind)
    for _, each in ipairs(entry.causes) do
        if each.kind == kind then return each end
    end
end

-- The snapshot keeps what the comparison reads, and only spells as known.
local snap = snapshot(102, 113, 142, 31)
check(#snap.runs == 3 and snap.runs[1].to == 113, "the steps")
check(snap.section.spell == DRESS and snap.section.items[WOOL] == 99, "the first section's buys")
check(snap.section.items[BOLT] == nil, "what the route makes is not bought")
check(snap.prices[WOOL].each == 31 and snap.prices[WOOL].source == "ah", "what each item costs")
check(#snap.known == 2, "spells only in known")

-- The first plan of a profession has nothing to compare with.
local store = {}
check(Changes:Note(store, "Tailoring", snap, "open", nil, 100) == nil, "no entry for the first plan")
check(store.planChanges.Tailoring.last == snap, "but it is kept to compare with")

-- The same plan again (a /reload, a check with nothing new) is no change.
check(Changes:Note(store, "Tailoring", snapshot(102, 113, 142, 31), "open", nil, 110) == nil, "same plan, no entry")

-- Progress: a craft gives its point, the bags lose what it took. Not a change.
check(Changes:Note(store, "Tailoring", snapshot(103, 113, 142, 31, 0), "skill", nil, 120) == nil,
    "a skill-up on the same steps is progress")
-- Wool bought into the bags: progress too.
check(Changes:Note(store, "Tailoring", snapshot(103, 113, 142, 31, 90), "bags", nil, 130) == nil,
    "buying what the plan asks is not a change")

-- The case that started it: wool goes up at the auction house, the Bag (more
-- wool a craft) loses its first two points to the Dress.
local entry = Changes:Note(store, "Tailoring", snapshot(103, 115, 137, 49, 90), "auction", nil, 140)
check(entry, "a price that moves the steps is a change")
check(entry.at == 140 and entry.reason == "auction" and not entry.own, "when, what asked, not the player's")
local price = cause(entry, "price")
check(price and price.item == WOOL and price.before == 31 and price.after == 49 and price.source == "ah", "why: the wool price")
check(not cause(entry, "skill") and not cause(entry, "bags"), "nothing else moved")
local run = effect(entry, "run")
check(run and run.spell == DRESS and run.fromBefore == 103 and run.toBefore == 113 and run.to == 115, "the Dress runs on")
check(run.countBefore == 10 and run.count == 12, "with its crafts")
local buy = effect(entry, "buy", WOOL)
check(buy and buy.item == WOOL and buy.before == 90 and buy.after == 108, "the section's wool")
check(entry.effects[1] == run and entry.effects[2].kind == "buy", "the section's step leads, then its buys")
check(effect(entry, "net"), "and the route's cost")
local said, lines = Changes:Words(entry, names)
check(said == "Wool Cloth went up at the auction house (31c -> 49c).", "the cause in words: " .. said)
check(lines[1] == "White Woolen Dress: 103-113 -> 103-115, 10 -> 12 crafts", "the step in words: " .. lines[1])
check(lines[2] == "Wool Cloth to get for White Woolen Dress 103-115: 90 -> 108"
    and lines[3] == "Fine Thread to get for White Woolen Dress 103-115: 10 -> 12", "the buys in words, the biggest first:\n"
    .. table.concat(lines, "\n"))
check(lines[4] == "Red Woolen Bag: 113-142 -> 115-137, 29 -> 22 crafts", "the next step: " .. tostring(lines[4]))
local summary = Changes:Summary(entry, names)
check(summary == said .. " " .. lines[1] .. ".", "the strip: " .. summary)

-- Prices alone, on the same steps: an entry when the route's cost moved
-- enough, none for a copper's wobble.
check(Changes:Note(store, "Tailoring", snapshot(103, 115, 137, 50, 90), "auction", nil, 150) == nil,
    "a copper on wool is not news")
entry = Changes:Note(store, "Tailoring", snapshot(103, 115, 137, 90, 90), "auction", nil, 160)
check(entry and cause(entry, "price") and effect(entry, "net") and not effect(entry, "run"),
    "a price that moves the cost a lot is an entry, with no steps changed")

-- A recipe learned that changes the steps: named as the cause.
local more = { [DRESS] = true, [BAG] = true, [GLOVES] = true }
entry = Changes:Note(store, "Tailoring", snapshot(103, 115, 140, 90, 90, more), "trainer", nil, 170)
local learned = cause(entry, "learned")
check(learned and learned.spells[1] == GLOVES, "the recipe learned")
said = Changes:Words(entry, names)
check(said:find("Learned Gloves of Meditation.", 1, true), "in words: " .. said)

-- The player's own change is always an entry, in the strip's words, even
-- when the plan stays the same.
entry = Changes:Note(store, "Tailoring", snapshot(103, 115, 140, 90, 90, more), "split", "split", 180)
check(entry and entry.own == "split" and cause(entry, "own"), "the player's change")
said, lines = Changes:Words(entry, names)
check(said == "You changed how the plan is cut into sections.", "its words without the strip's: " .. said)
check(lines[1] == "The plan stayed the same.", "and nothing moved")
entry.text = "Target set to 151."
check(Changes:Words(entry, names) == "Target set to 151.", "the strip's words when it had some")

-- A step dropped and one added, and the steps past the third counted.
local route, sections = plan(103, 115, 140, 90, 90)
route.runs[2] = { spell = 9999, fromSkill = 115, toSkill = 140, count = 25 }
entry = Changes:Compare(store.planChanges.Tailoring.last, Changes:Snapshot(route, sections, more), "auction")
check(effect(entry, "added").spell == 9999 and effect(entry, "dropped").spell == BAG, "added and dropped")
_, lines = Changes:Words(entry, names)
local joined = table.concat(lines, "\n")
check(joined:find("Now recipe 9999 115-140, 25 crafts", 1, true) and joined:find("No more Red Woolen Bag 115-140", 1, true),
    "in words:\n" .. joined)

-- Newest first, at most `limit`, per profession.
store = {}
Changes:Note(store, "Tailoring", snapshot(102, 113, 142, 31), "open", nil, 0)
for index = 1, Changes.limit + 5 do
    Changes:Note(store, "Tailoring", snapshot(102, 113, 142, 31), "target", "target", index)
end
local entries = Changes:Entries(store, "Tailoring")
check(#entries == Changes.limit, "kept to the limit: " .. #entries)
check(entries[1].at == Changes.limit + 5 and entries[#entries].at == 6, "newest first, the oldest gone")
check(#Changes:Entries(store, "Cooking") == 0, "one list per profession")

print("plan changes: ok")
