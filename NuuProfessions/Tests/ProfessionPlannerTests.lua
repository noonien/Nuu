local ns = NewNamespace()
Load(ns, "Config.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
local Prices, Planner, SkillUp = ns.modules.Prices, ns.modules.ProfessionPlanner, ns.Kit.SkillUp

local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-6) end

-- Toy professions. Materials: 100 at 10c, 101 at 20c, 102 at 50c, 103 at
-- 1g, all vendor-sold; outputs sell for nothing unless a test prices them.
local function items()
    return {
        [100] = { buy = 10, vendor = true }, [101] = { buy = 20, vendor = true },
        [102] = { buy = 50, vendor = true }, [103] = { buy = 10000, vendor = true },
    }
end
local function recipe(makes, skills, reagents, fields)
    local row = { makes = makes, made = { 1, 1 }, skills = skills, reagents = reagents, learn = "start" }
    for key, value in pairs(fields or {}) do row[key] = value end
    return row
end
local function newBook() return { prices = {}, trainers = {}, merchants = {} } end
-- These tests plan with every recipe, patterns the character lacks included
-- (the default); the trainer-only mode, where patterns are suggestions, is
-- asked for by the tests of suggestions.
local function plan(data, fields)
    local input = { profession = "Leatherworking", data = data, skill = 1, level = 20, book = newBook(), known = {} }
    for key, value in pairs(fields or {}) do input[key] = value end
    input.options = input.options or {}
    if input.options.recipes == nil then input.options.recipes = "patterns" end
    if input.options.sellOutput == nil then input.options.sellOutput = "all" end
    if input.options.optimize == nil then input.options.optimize = "profit" end
    -- The window's default is to buy at the auction house only; these
    -- tests sell there too unless they say otherwise.
    if input.options.auction == nil then input.options.auction = "both" end
    return Planner:Plan(input), input
end
assert(Planner.defaultOptions.auction == "buy", "the auction house is for buying only unless the player says")
local function spells(route)
    local list = {}
    for _, run in ipairs(route.runs) do table.insert(list, run.spell .. ":" .. run.fromSkill .. "-" .. run.toSkill) end
    return table.concat(list, " ")
end
local function used(route, spell)
    for _, run in ipairs(route.runs) do if run.spell == spell then return true end end
    return false
end
local function suggestion(route, spell)
    for _, row in ipairs(route.suggestions) do if row.spell == spell then return row end end
    return nil
end

-- An orange-only chain: each recipe while it is orange, one craft a point.
-- At its yellow skill a recipe still gives a point every time ((R-Y)/(R-Y)),
-- and staying on it beats switching at the same price.
local chain = { recipes = {
    [1] = recipe(1001, { 1, 10, 15, 20 }, { { 100, 1 } }),
    [2] = recipe(1002, { 10, 20, 25, 30 }, { { 100, 1 } }),
}, items = items() }
local route = plan(chain, { target = 20 })
assert(spells(route) == "1:1-11 2:11-20", spells(route))
assert(route.runs[1].expected == 10 and route.runs[1].variance == 0 and route.runs[1].low == 10 and route.runs[1].high == 10)
assert(route.runs[2].count == 9, "orange runs need exactly one craft a point")
assert(route.summary.spent == 190 and route.summary.net == 190 and route.summary.recovered == 0)
assert(route.summary.low == 190 and route.summary.high == 190, "no dice, no range")
assert(#route.events == 0, "nothing to learn or train below 75")
assert(route.shopping[1].itemID == 100 and route.shopping[1].count == 19 and route.shopping[1].lastSkill == 20)
assert(route.ceiling.reason == "target")
-- Split every N skill levels, a recipe crossing a multiple of N is two steps.
route = plan(chain, { target = 20, options = { sections = "band", bandSize = 5 } })
assert(spells(route) == "1:1-5 1:5-10 1:10-11 2:11-15 2:15-20", spells(route))

-- A cheap green beats a dear orange: 10c at a half chance is 20c a point.
local green = { recipes = {
    [1] = recipe(1001, { 1, 1, 11, 21 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 102, 2 } }),
}, items = items() }
route = plan(green, { skill = 11, target = 16 })
assert(spells(route) == "1:11-16", spells(route))
assert(route.runs[1].color == "green")
assert(near(route.runs[1].expected, 20 / 10 + 20 / 9 + 20 / 8 + 20 / 7 + 20 / 6))
assert(#route.runs[1].rivals == 1 and route.runs[1].rivals[1].spell == 2 and route.runs[1].rivals[1].perPoint == 100,
    "the run says which rival it beat, and by how much a point")

-- Resale flips the choice: 50c in, 47c back beats 20c in, nothing back.
local resale = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 101, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 102, 1 } }),
}, items = items() }
local book = newBook()
route = plan(resale, { target = 20, book = book })
assert(spells(route) == "1:1-20", "without a sell price, the cheap one")
Prices:SetFact(book, 1002, "auctionSell", 50)
route = plan(resale, { target = 20, book = book })
assert(spells(route) == "2:1-20", "with a sell price, the one that pays back: " .. spells(route))
assert(route.summary.recovered == 19 * 47 and route.summary.net == 19 * 50 - 19 * 47)
assert(route.selling[1].itemID == 1002 and route.selling[1].source == "ah")
assert(route.summary.vendorRecovered == 0 and route.summary.vendorNet == 19 * 50, "no vendor price, nothing at a vendor")
Prices:SetFact(book, 1002, "vendorSell", 12)
route = plan(resale, { target = 20, book = book })
assert(route.summary.recovered == 19 * 47 and route.summary.vendorRecovered == 19 * 12
    and route.summary.vendorNet == 19 * 50 - 19 * 12, "all to a vendor: " .. route.summary.vendorRecovered)
Prices:SetFact(book, 1002, "vendorSell", nil)
route = plan(resale, { target = 20, book = book, options = { auction = "none" } })
assert(spells(route) == "1:1-20", "not when the player does not sell at the auction house")
route = plan(resale, { target = 20, book = book, options = { keep = { [1002] = true } } })
assert(spells(route) == "1:1-20", "nor when they keep it")

-- By default the plan is on cost: nothing made is counted as sold, unless
-- the player chose to sell it.
route = plan(resale, { target = 20, book = book, options = { sellOutput = "chosen" } })
assert(spells(route) == "1:1-20" and route.summary.recovered == 0, "on cost, the cheap one: " .. spells(route))
route = plan(resale, { target = 20, book = book, options = { sellOutput = "chosen", sell = { [1002] = true } } })
assert(spells(route) == "2:1-20" and route.summary.recovered == 19 * 47, "sold because chosen: " .. spells(route))
route = Planner:Plan({ profession = "Leatherworking", data = resale, skill = 1, level = 20, book = book, known = {}, target = 20 })
assert(spells(route) == "1:1-20" and route.summary.recovered == 0, "and that is the default")
-- Optimising on cost, a sale never steers the route, but it is still counted.
route = plan(resale, { target = 20, book = book, options = { optimize = "cost", sellOutput = "chosen", sell = { [1002] = true } } })
assert(spells(route) == "1:1-20", "on cost, the cheap one even when the other pays back: " .. spells(route))
route = plan(resale, { target = 20, book = book, options = { optimize = "cost", sellOutput = "chosen", sell = { [1001] = true } } })
Prices:SetFact(book, 1001, "auctionSell", 10)
route = plan(resale, { target = 20, book = book, options = { optimize = "cost", sellOutput = "chosen", sell = { [1001] = true } } })
assert(spells(route) == "1:1-20" and route.summary.recovered == 19 * 9 and route.runs[1].sellCraft == 9,
    "and what it makes that is chosen to sell is counted: " .. route.summary.recovered)
Prices:SetFact(book, 1001, "auctionSell", nil)

-- A learn cost not worth paying: saving 5c a point over 19 points is 95c.
local learning = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 101, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 100, 1 } }, { learn = "trainer" }),
}, items = items() }
book = newBook()
book.trainers[900] = { [2] = { cost = 5000 } }
route = plan(learning, { target = 20, book = book })
assert(spells(route) == "1:1-20", "a 50s fee for 95c of saving is not paid")
book.trainers[900][2].cost = 50
route = plan(learning, { target = 20, book = book })
assert(spells(route) == "2:1-20", "a 50c fee is")
assert(route.events[1].kind == "learn" and route.events[1].source == "trainer" and route.events[1].cost == 50 and route.events[1].npc == 900)
assert(route.summary.learning == 50 and route.summary.spent == 19 * 10 + 50)
route = plan(learning, { target = 20, book = newBook() })
assert(spells(route) == "2:1-20" and route.summary.costUnknown, "an unknown fee counts as 0 and is flagged")
local flagged = false
for _, warning in ipairs(route.warnings) do if warning.code == "costUnknown" and warning.spell == 2 then flagged = true end end
assert(flagged, "and the summary says so")
route = plan(learning, { target = 20, book = newBook(), known = { [2] = true } })
assert(spells(route) == "2:1-20" and #route.events == 0, "a known recipe costs nothing to learn")

-- A BoP pattern, planning with trainer recipes only: suggested with its
-- saving, never used until accepted.
local patterns = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [3] = recipe(1003, { 1, 30, 40, 50 }, { { 100, 1 } }),
}, items = items() }
patterns.items[104] = { buy = 1, vendor = true }
patterns.recipes[3] = recipe(1003, { 1, 30, 40, 50 }, { { 104, 1 } }, { learn = "item", teach = 5000, bind = "bop" })
local trainerOnly = { recipes = "trainer" }
route = plan(patterns, { target = 20, options = trainerOnly })
assert(spells(route) == "1:1-20", "a BoP pattern is never assumed")
assert(#route.suggestions == 0, "a saving under 10s is not worth showing")
local small = { suggestThreshold = 100, recipes = "trainer" }
route = plan(patterns, { target = 20, options = small })
local row = suggestion(route, 3)
assert(row and row.bind == "bop" and row.saving == 19 * 10 - 19 * 1 and row.item == 5000 and row.worthUnder == nil,
    "suggested with the saving: " .. tostring(row and row.saving))
assert(row.fromSkill == 1 and row.toSkill == 20, "and the skills it would be made over: " .. tostring(row.fromSkill) .. "-" .. tostring(row.toSkill))
route = plan(patterns, { target = 20, accepted = { [3] = true }, options = trainerOnly })
assert(spells(route) == "3:1-20", "used once accepted")
assert(route.events[1].kind == "learn" and route.events[1].source == "bop" and route.events[1].item == 5000)
assert(#route.suggestions == 0, "an accepted pattern is no longer a suggestion")
assert(route.runs[1].needsPattern == nil and route.events[1].needsPattern == nil, "and carries no mark")

-- A BoE pattern with no price: what it is worth buying under. Priced, it is
-- an ordinary recipe, bought only when the price is below the saving.
patterns.recipes[3].bind = "boe"
book = newBook()
route = plan(patterns, { target = 20, book = book, options = small })
row = suggestion(route, 3)
assert(row and row.bind == "boe" and row.worthUnder == 171, "worth buying under the saving")
Prices:SetFact(book, 5000, "auctionBuy", 100)
route = plan(patterns, { target = 20, book = book, options = { recipes = "trainer", suggestThreshold = 1 } })
assert(spells(route) == "1:1-20" and suggestion(route, 3), "trainer only: a priced pattern is still a suggestion")
route = plan(patterns, { target = 20, book = book })
assert(spells(route) == "3:1-20" and route.events[1].source == "boe" and route.events[1].cost == 100, "bought at 1s")
assert(route.summary.net == 19 + 100 and #route.suggestions == 0)
Prices:SetFact(book, 5000, "auctionBuy", 200)
route = plan(patterns, { target = 20, book = book })
assert(spells(route) == "1:1-20" and #route.suggestions == 0, "not at 2s, and a priced pattern is not a suggestion")

-- A refused recipe is never used or suggested, even when it is the cheapest.
patterns.recipes[3].bind = "bop"
route = plan(patterns, { target = 20, refused = { [3] = true }, options = small })
assert(spells(route) == "1:1-20" and suggestion(route, 3) == nil, "refused: not suggested")
route = plan(patterns, { target = 20, refused = { [3] = true }, accepted = { [3] = true } })
assert(not used(route, 3), "refused beats accepted")
local cheapest = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 101, 1 } }),
}, items = items() }
route = plan(cheapest, { target = 20, refused = { [1] = true } })
assert(spells(route) == "2:1-20", "a refused starting recipe is dropped too")
local inputs = Planner:DefaultInputs()
Planner:Accept(inputs, 3)
Planner:Pin(inputs, 3)
Planner:Refuse(inputs, 3)
assert(inputs.refused[3] and not inputs.accepted[3] and not inputs.pinned[3], "refusing drops the pin and the acceptance")
Planner:Refuse(inputs, 3, false)
assert(not inputs.refused[3], "and a refusal can be undone")
Planner:BumpGoal(inputs, 3)
Planner:Refuse(inputs, 3)
assert(Planner:FindGoal(inputs, 3) == nil, "refusing drops the goal too")
Planner:BumpGoal(inputs, 3)
assert(not inputs.refused[3] and Planner:FindGoal(inputs, 3), "and a goal clears the refusal")

-- A material the player does not use takes out every recipe that needs it,
-- and is not listed as a material with no source.
route = plan(cheapest, { target = 20, avoided = { [100] = true } })
assert(spells(route) == "2:1-20", "a recipe needing an avoided material is dropped: " .. spells(route))
route = plan(patterns, { target = 20, avoided = { [104] = true }, accepted = { [3] = true } })
assert(not used(route, 3), "avoided beats accepted")
route = plan(patterns, { target = 20, avoided = { [104] = true }, options = small })
assert(suggestion(route, 3) == nil, "and is never suggested")
route = plan(cheapest, { target = 20, avoided = { [100] = true }, goals = { { spell = 1, count = 2 } } })
local avoidedGoal = false
for _, warning in ipairs(route.warnings) do
    if warning.code == "goal" and warning.spell == 1 and warning.item == 100 then avoidedGoal = true end
end
assert(avoidedGoal and spells(route) == "2:1-20", "a goal that needs it is left out, and says which material")
local noSource = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 100, 1 }, { 900, 1 } }),
}, items = items() }
route = plan(noSource, { target = 20, avoided = { [100] = true, [900] = true } })
assert(#route.unobtainable == 0, "an avoided recipe's missing materials are not asked for")
assert(Planner:AvoidedReagent(noSource.recipes[2], { [900] = true }) == 900)
assert(Planner:AvoidedReagent(noSource.recipes[1], { [900] = true }) == nil)
Planner:Avoid(inputs, 100)
assert(inputs.avoided[100])
Planner:Avoid(inputs, 100, false)
assert(inputs.avoided[100] == nil, "and a material can be used again")

-- How many other recipes could make each step, counted without solving:
-- those giving skill at every one of its skill levels.
route = plan(cheapest, { target = 20 })
assert(route.runs[1].others == 1, "recipe 2 could make the whole step")
route = plan(chain, { target = 20 })
assert(route.runs[1].others == 0 and route.runs[2].others == 1,
    "recipe 2 is not learned for the first step; recipe 1 is green to grey over the second")
assert(route.alternatives == nil, "no detours any more")

-- A pinned recipe is preferred wherever it gives skill.
route = plan(cheapest, { target = 20, pinned = { [2] = true } })
assert(spells(route) == "2:1-20", "pinned beats cheaper")

-- Goals at their best skill: five orange crafts at 10 are five free points.
local goals = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [7] = recipe(1007, { 10, 15, 20, 25 }, { { 103, 1 } }),
}, items = items() }
route = plan(goals, { target = 20, goals = { { spell = 7, count = 5 } } })
assert(spells(route) == "1:1-10 1:15-20", "the grind skips what the goal gives: " .. spells(route))
local goal
for _, event in ipairs(route.events) do if event.kind == "goal" then goal = event end end
assert(goal and goal.skill == 10 and goal.gain == 5 and goal.count == 5 and goal.when == "best")
assert(route.summary.spent == 14 * 10 + 5 * 10000, "the goal's materials are paid, its output kept")
assert(route.summary.recovered == 0)
route = plan(goals, { target = 20, goals = { { spell = 7, count = 5, when = "end" } } })
assert(spells(route) == "1:1-20", "a goal at the end gives the grind nothing")
route = plan(goals, { target = 20, goals = { { spell = 7, count = 2, when = "skill", skill = 12 } } })
assert(spells(route) == "1:1-12 1:14-20", spells(route))
route = plan(goals, { target = 20, goals = { { spell = 7, count = 2, when = "now" } } })
assert(route.warnings[1].code == "goal", "made now, before its skill, is a warning")
assert(spells(route) == "1:1-10 1:12-20", "and it is made as soon as it can be")

-- Confidence changes the counts, not the route.
local dice = { recipes = {
    [1] = recipe(1001, { 1, 1, 30, 60 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 102, 1 } }),
}, items = items() }
local typical = plan(dice, { target = 20, options = { confidence = "typical" } })
local sure = plan(dice, { target = 20, options = { confidence = "sure" } })
assert(spells(typical) == spells(sure) and spells(sure) == "1:1-20")
assert(sure.runs[1].count > typical.runs[1].count, "more crafts for a sure list")
assert(typical.runs[1].count == SkillUp:Count(typical.runs[1].expected, 0, 0))
assert(sure.shopping[1].count > typical.shopping[1].count)
assert(sure.summary.net == typical.summary.net, "the expected cost does not move")
assert(sure.summary.high > sure.summary.net and typical.summary.high == typical.summary.net)
assert(sure.runs[1].high > sure.runs[1].low)

-- Replanning from a lucky skill.
local safe, safeInput = plan(dice, { target = 20 })
local run = safe.runs[1]
assert(Planner:NeedsReplan(safe, { skill = 10, crafted = 10, signature = Planner:Signature(safeInput) }) == false,
    "ten crafts, nine points: as planned")
local again, why = Planner:NeedsReplan(safe, { skill = 15, crafted = 10 })
assert(again and why == "lucky", "fourteen points from ten crafts is luck the list did not plan on")
again, why = Planner:NeedsReplan(safe, { skill = 3, crafted = 20 })
assert(again and why == "unlucky")
safeInput.goals = { { spell = 2, count = 1 } }
again, why = Planner:NeedsReplan(safe, { skill = 10, signature = Planner:Signature(safeInput) })
assert(again and why == "inputs", "a changed input replans")
assert(Planner:NeedsReplan(safe, { skill = 20 }) == false, "done is done")
local bagged = { [100] = 5 }
local lucky = plan(dice, { skill = 15, target = 20, bags = function(id) return bagged[id] or 0 end })
assert(lucky.startSkill == 15 and lucky.runs[1].fromSkill == 15, "the new route starts from the live skill")
assert(lucky.shopping[1].have == 5 and lucky.shopping[1].buy == lucky.shopping[1].count - 5, "and counts the bags")
assert(lucky.summary.spent < safe.summary.spent)

-- The first step made from the bags: committed once they cover its expected
-- crafts, then nothing is made or bought for it until they run out.
do
    local cloth = { recipes = {
        [1] = recipe(1001, { 1, 1, 10, 30 }, { { 1003, 1 } }),
        [3] = recipe(1003, { 1, 1, 2, 3 }, { { 100, 2 } }),
    }, items = items() }
    local function bolts(count)
        return function(id) return id == 1003 and count or 0 end
    end
    local function makes(route)
        local count = 0
        for _, event in ipairs(route.events) do if event.kind == "make" then count = count + event.count end end
        return count
    end
    local fresh = plan(cloth, { skill = 20, target = 22 })
    local expected = SkillUp:Count(fresh.runs[1].expected, 0, 0)
    assert(fresh.runs[1].count > expected and makes(fresh) > 0, "a safe step with no bags makes its margin")
    local started = plan(cloth, { skill = 20, target = 22, bags = bolts(expected) })
    assert(started.committed == 1 and started.runs[1].committed and started.runs[1].count == expected,
        "the bags cover the expected crafts: committed, at what they make")
    assert(makes(started) == 0 and #started.shopping == 0, "nothing made or bought")
    local missed = plan(cloth, { skill = 20, target = 22, bags = bolts(expected - 1) })
    assert(not missed.committed and makes(missed) > 0, "not committed, a miss would ask for more")
    missed = plan(cloth, { skill = 20, target = 22, bags = bolts(expected - 1), committed = 1 })
    assert(missed.committed == 1 and missed.runs[1].count == expected - 1 and makes(missed) == 0,
        "committed, a miss asks for nothing")
    local out = plan(cloth, { skill = 20, target = 22, bags = bolts(0), committed = 1 })
    assert(not out.committed and makes(out) > 0, "the bags make no craft: the step asks for the rest")
    local other = plan(cloth, { skill = 20, target = 22, bags = bolts(expected - 1), committed = 7 })
    assert(not other.committed, "another step's commitment is not this one's")
    local carried = plan(cloth, { skill = 20, target = 22, bags = bolts(expected), options = { materials = "carried" } })
    assert(not carried.committed, "only what I have caps every step its own way")
end

-- Trainer tiers: training at the cap, gated by level.
local long = { recipes = {
    [1] = recipe(1001, { 1, 240, 245, 250 }, { { 100, 1 } }),
}, items = items() }
route = plan(long, { target = 100, level = 20 })
assert(route.events[1].kind == "train" and route.events[1].skill == 75 and route.events[1].tier == "Journeyman")
assert(route.events[1].costUnknown and route.events[1].level == 10)
assert(#route.summary.bands == 2 and route.summary.bands[1].tier == "Apprentice" and route.summary.bands[2].fromSkill == 75)
route = plan(long, { target = 100, level = 5 })
assert(route.target == 75 and route.ceiling.reason == "level" and route.ceiling.level == 10, "Journeyman needs level 10")
route = plan(long, { target = 300, level = 60 })
assert(route.target == 225 and route.ceiling.reason == "tiers")
route = plan(chain, { target = 60 })
assert(route.target == 30 and route.ceiling.reason == "recipes", "the recipes stop at 30")

-- A pattern a merchant sells only for a currency has no gold price: the
-- planner does not price currencies, so it is what its binding makes it
-- (with trainer recipes only, a suggestion), and never a priced vendor
-- pattern.
local coin = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [4] = recipe(1004, { 1, 30, 40, 50 }, { { 104, 1 } }, { learn = "item", teach = 5004, bind = "bop" }),
}, items = items() }
coin.items[104] = { buy = 1, vendor = true }
book = newBook()
book.merchants[800] = { [5004] = { price = 0, count = 1, currency = { [3402] = 30 } } }
route = plan(coin, { target = 20, book = book, options = { recipes = "trainer", suggestThreshold = 1 } })
assert(not used(route, 4), "a currency-only pattern is not bought")
local coinTip = suggestion(route, 4)
assert(coinTip and coinTip.source == "bop" and coinTip.cost == nil and coinTip.npc == nil,
    "a currency-only pattern is suggested as its binding makes it")
route = plan(coin, { target = 20, book = book, accepted = { [4] = true }, options = { recipes = "trainer" } })
assert(used(route, 4) and route.events[1].source == "bop" and route.events[1].cost == 0, "and used, unpriced, once accepted")
route = plan(coin, { target = 20, book = book })
assert(used(route, 4) and route.runs[1].needsPattern and route.runs[1].needsPattern.source == "bop"
    and route.runs[1].needsPattern.cost == nil, "planning with every pattern, it is used as a BoP one, unpriced")

-- With trainer recipes only, the route keeps to the trainer: a pattern with
-- a known price is a suggestion carrying that price and its seller, and Use
-- it brings it in at that price.
local function planTrainer(data, fields)
    local input = { profession = "Leatherworking", data = data, skill = 1, level = 20, book = newBook(), known = {},
        options = { suggestThreshold = 1, recipes = "trainer" } }
    for key, value in pairs(fields or {}) do input[key] = value end
    return Planner:Plan(input)
end
local shop = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 101, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 100, 1 } }, { learn = "item", teach = 5002, bind = "boe" }),
    [4] = recipe(1004, { 1, 30, 40, 50 }, { { 100, 1 } }, { learn = "item", teach = 5004, bind = "bop" }),
}, items = items() }
book = newBook()
book.merchants[700] = { [5002] = { price = 50, count = 1 } }
route = planTrainer(shop, { target = 20, book = book })
assert(spells(route) == "1:1-20", "trainer and known recipes only: " .. spells(route))
local vendorTip = suggestion(route, 2)
assert(vendorTip and vendorTip.source == "vendor" and vendorTip.cost == 50 and vendorTip.npc == 700,
    "a vendor pattern is suggested with its price and seller")
assert(vendorTip.saving == 19 * 10 - 50 and vendorTip.worthUnder == nil, "its saving is net of the price: " .. vendorTip.saving)
route = planTrainer(shop, { target = 20, book = book, accepted = { [2] = true } })
assert(used(route, 2) and route.events[1].source == "vendor" and route.events[1].cost == 50, "used at its price once accepted")
assert(route.runs[1].needsPattern == nil, "and, said to be in hand, is not marked")

-- By default the route plans with every recipe, as if every pattern could be
-- had, and marks what needs a pattern the character lacks.
local function planDefault(data, fields)
    local input = { profession = "Leatherworking", data = data, skill = 1, level = 20, book = newBook(), known = {} }
    for key, value in pairs(fields or {}) do input[key] = value end
    return Planner:Plan(input)
end
assert(Planner.defaultOptions.recipes == "patterns", "planning with every pattern is the default")
local vendorShop = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 101, 1 } }, { learn = "trainer" }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 100, 1 } }, { learn = "item", teach = 5002, bind = "boe" }),
}, items = items() }
book.trainers[900] = { [1] = { cost = 10 } }
route = planDefault(vendorShop, { target = 20, book = book })
local mark = route.runs[1].needsPattern
assert(spells(route) == "2:1-20" and mark and mark.bind == "boe" and mark.source == "vendor" and mark.cost == 50
    and mark.npc == 700 and mark.teach == 5002, "a vendor pattern cheaper than the trainer recipe is used, marked")
assert(route.events[1].kind == "learn" and route.events[1].needsPattern == mark and route.events[1].cost == 50,
    "and so is its learn event, at the vendor price")
assert(route.summary.patterns == 1 and route.summary.patternsUnknown == 0 and #route.suggestions == 0,
    "the summary counts it, and nothing is left to suggest")
route = planDefault(vendorShop, { target = 20, book = book, options = { recipes = "trainer" } })
assert(spells(route) == "1:1-20" and route.runs[1].needsPattern == nil, "trainer only: never an unowned pattern")
route = planDefault(shop, { target = 20, book = book })
mark = route.runs[1].needsPattern
assert(spells(route) == "4:1-20" and mark and mark.bind == "bop" and mark.cost == nil,
    "a BoP pattern, free, is used when cheapest: " .. spells(route))
assert(route.events[1].costUnknown and route.summary.costUnknown and route.summary.patternsUnknown == 1,
    "and flagged: its price cannot be known")
inputs = Planner:DefaultInputs()
Planner:SetPlanWith(inputs, 4, "have")
route = planDefault(shop, { target = 20, book = book, accepted = inputs.accepted })
assert(used(route, 4) and route.runs[1].needsPattern == nil and route.summary.patterns == 0,
    "I have the pattern: used, no longer marked")
Planner:SetPlanWith(inputs, 4, "never")
route = planDefault(shop, { target = 20, book = book, refused = inputs.refused, accepted = inputs.accepted })
assert(not used(route, 4) and used(route, 2), "never: the BoP pattern is left out, the vendor one takes over")
route = planDefault(shop, { target = 20, book = book, options = { recipes = "all" } })
assert(used(route, 4) and route.runs[1].needsPattern, "an old \"all\" plans as \"patterns\"")
local oldStore = { professionPlanner = { plans = { Leatherworking = { options = { recipes = "all" } } } } }
assert(Planner:Option(Planner:LoadInputs(oldStore, "Leatherworking"), "recipes") == "patterns", "and loads as it")

-- Market depth: past the cap, the rest sell to a vendor, and the route
-- goes back to the plain recipe.
local depth = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 102, 1 }, { 101, 2 } }),
}, items = items() }
book = newBook()
Prices:SetFact(book, 1002, "auctionSell", 100)
route = plan(depth, { target = 20, book = book })
assert(spells(route) == "2:1-20", "90c in, 95c back")
Prices:SetDepth(book, 1002, 2)
route = plan(depth, { target = 20, book = book })
assert(spells(route) == "1:1-20", "but the market takes two: " .. spells(route))

-- Inputs saved per character.
local store = {}
local saved = Planner:LoadInputs(store, "Leatherworking")
assert(Planner:Option(saved, "confidence") == "safe" and Planner:Option(saved, "useBags") and #saved.goals == 0)
assert(saved.options.confidence == nil and store.professionPlanner == nil, "loading stores nothing, and no default")
assert(Planner:AddGoal(saved, { spell = 7, count = 2, when = "skill", skill = 50 }))
assert(not Planner:AddGoal(saved, { spell = 7, when = "skill" }), "a goal at a skill needs the skill")
local bumped = Planner:DefaultInputs()
assert(Planner:BumpGoal(bumped, 9) and Planner:BumpGoal(bumped, 9) and Planner:BumpGoal(bumped, 4))
assert(#bumped.goals == 2 and bumped.goals[1].count == 2 and bumped.goals[1].when == "best", "ADD twice is one goal for two")
assert(Planner:SetGoalCount(bumped, 1, 5) and bumped.goals[1].count == 5)
assert(not Planner:SetGoalCount(bumped, 1, 0) and bumped.goals[1].count == 5, "a count never falls below one")
assert(not Planner:SetGoalWhen(bumped, 2, "skill"), "at a skill needs the skill")
assert(Planner:SetGoalWhen(bumped, 2, "skill", 60) and bumped.goals[2].skill == 60)
assert(Planner:SetGoalWhen(bumped, 2, "end") and bumped.goals[2].skill == nil)
assert(Planner:NextWhen("best") == "now" and Planner:NextWhen("skill") == "best")
saved.target, saved.refused[3] = 150, true
Planner:SaveInputs(store, "Leatherworking", saved)
local loaded = Planner:LoadInputs(store, "Leatherworking")
assert(loaded.target == 150 and loaded.refused[3] and loaded.goals[1].skill == 50)
saved.avoided[100] = true
Planner:SaveInputs(store, "Leatherworking", saved)
assert(Planner:LoadInputs(store, "Leatherworking").avoided[100], "avoided materials are saved")
store.professionPlanner.plans.Tailoring = { wishes = { { spell = 7, count = 3 } } }
local old = Planner:LoadInputs(store, "Tailoring")
assert(old.goals[1].count == 3 and old.wishes == nil, "goals saved as wishes are read as goals")
assert(store.professionPlanner.profession == "Leatherworking")
store.knownRecipes = { Leatherworking = { [2] = true } }
assert(Planner:KnownRecipes(store, "Leatherworking")[2])
loaded.options.confidence = "sure"
assert(Planner:Option(Planner:LoadInputs(store, "Leatherworking"), "confidence") == "safe", "loaded inputs are a copy")

-- Only what the player set is saved: no default option, no empty table.
local plain = store.professionPlanner.plans.Leatherworking
assert(plain.options == nil and plain.pinned == nil and plain.chosen == nil, "nothing the player left alone is saved")
local chosen = Planner:LoadInputs(store, "Leatherworking")
chosen.options.confidence, chosen.options.auction = "safe", "none"
Planner:SaveInputs(store, "Leatherworking", chosen)
plain = store.professionPlanner.plans.Leatherworking
assert(plain.options.confidence == "safe" and plain.options.auction == "none" and plain.options.useBags == nil,
    "a choice is saved, even one equal to the default")
assert(plain.options.gather == nil and plain.options.sell == nil, "an empty item map is not")
chosen = Planner:LoadInputs(store, "Leatherworking")
assert(Planner:Option(chosen, "auction") == "none" and Planner:Option(chosen, "useBags") == true, "and read back")
chosen.options.confidence, chosen.options.auction = nil, nil
Planner:SaveInputs(store, "Leatherworking", chosen)
assert(store.professionPlanner.plans.Leatherworking.options == nil, "a reset forgets the choice")
Planner:SaveInputs(store, "Tailoring", Planner:DefaultInputs())
assert(store.professionPlanner.plans.Tailoring == nil, "a profession with nothing set has no record")
local resolved = Planner:Options(chosen)
assert(resolved.confidence == "safe" and resolved.sections == "trip" and type(resolved.gather) == "table",
    "Options: every option as it applies")

-- A whole route: tiers, shopping, patterns, goals, an intermediate made
-- from its parts.
local full = { recipes = {
    [1] = recipe(1001, { 20, 200, 210, 220 }, { { 2000, 1 } }),
    [3] = recipe(1003, { 1, 20, 25, 30 }, { { 104, 1 } }, { learn = "item", teach = 5000, bind = "bop" }),
    [5] = recipe(nil, { 76, 200, 210, 220 }, { { 100, 1 } }, { learn = "trainer" }),
    [6] = recipe(2000, { 1, 2, 3, 4 }, { { 101, 1 } }),
    [7] = recipe(1007, { 10, 15, 20, 25 }, { { 103, 1 } }),
    [8] = recipe(1008, { 50, 60, 70, 80 }, { { 101, 1 } }),
}, items = items() }
full.items[104] = { buy = 5, vendor = true }
book = newBook()
book.merchants[3000] = { [100] = { price = 10, count = 1 } }
Prices:SetFact(book, 1003, "auctionSell", 20)
route = plan(full, { skill = 0, target = 100, level = 20, book = book, accepted = { [3] = true },
    goals = { { spell = 7, count = 3 }, { spell = 8, count = 1, when = "end" } } })
-- Its sections and rows (OpenRoad checked the same through the guide it
-- built from them).
local sections = Planner:Sections(route, { profession = "Leatherworking" })
assert(sections[1].kind == "shopping" and sections[1].title == "Shopping", "the shopping comes first")
assert(sections[2].title == "Apprentice 1-75" and sections[3].title == "Journeyman 75-100", sections[2].title)
assert(sections[4].title == "Goals")
local outline = Planner:Outline(route)
local firstRoute
for _, row in ipairs(outline) do
    if row.kind ~= "buy" then firstRoute = row; break end
end
assert(firstRoute.kind == "train" and firstRoute.skill == 0, "learning the profession comes first")
local seen = { upto = false, skillup = false, learn = false, make = false, goal = false, train = false, sell = false }
for _, row in ipairs(outline) do
    if row.kind == "buy" and row.toSkill then seen.upto = true end
    if row.kind == "skillup" then seen.skillup = true; assert(row.toSkill and row.low and row.high) end
    if row.kind == "learn" and row.item == 5000 then seen.learn = true; assert(row.spell == 3 and row.source == "bop") end
    if row.kind == "make" and row.item == 2000 then seen.make = true end
    if row.kind == "goal" and row.item == 1007 then seen.goal = true end
    if row.kind == "train" and row.skill == 75 then seen.train = true end
    if row.kind == "sell" then seen.sell = true end
    if row.kind == "buy" then assert(row.count >= 1) end
end
for key, value in pairs(seen) do assert(value, "the outline has a " .. key .. " row") end
-- An enchant-like recipe (no item made) is a grind row with no item.
local enchanting = { recipes = { [9] = recipe(nil, { 1, 30, 40, 50 }, { { 100, 1 } }) }, items = items() }
route = plan(enchanting, { target = 20 })
outline = Planner:Outline(route)
assert(outline[#outline].kind == "skillup" and outline[#outline].item == nil and outline[#outline].spell == 9)
-- A route with nothing to do has nothing to show.
route = plan(chain, { skill = 20, target = 20 })
assert(#route.runs == 0 and #Planner:Outline(route) == 0 and #Planner:Sections(route) == 0)

-- The client's known-recipe keys as spell IDs: a spell ID as it is, a
-- product item to the recipes that make it, a name to the recipe it names.
local names = { spell = { [1] = "Light Armor Kit", [2] = "Handstitched Boots" }, item = { [1002] = "Handstitched Boots" } }
local function nameOf(kind, id) return names[kind][id] end
local twoKits = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [3] = recipe(1001, { 50, 60, 70, 80 }, { { 100, 1 } }),
    [4] = recipe(1004, { 1, 30, 40, 50 }, { { 100, 1 } }),
}, items = items() }
local known = Planner:ResolveKnown(twoKits, { [4] = true, ["item:1001"] = true, ["name:handstitched boots"] = true,
    ["item:9999"] = true, ["name:nothing"] = true, [77] = false }, nameOf)
assert(known[1] and known[3], "an item key marks every recipe making that item")
assert(known[2], "a name key marks the recipe of that name")
assert(known[4], "a spell key is kept")
local count = 0
for _ in pairs(known) do count = count + 1 end
assert(count == 4, "nothing else")
assert(next(Planner:ResolveKnown(twoKits, { ["name:light armor kit"] = true })) == nil, "without names, name keys are dropped")
known = Planner:ResolveKnown(twoKits, { ["name:light armor kit"] = true }, nameOf)
assert(known[1] and not known[3], "a name matches the spell's own name")

-- Planner input from the live state; the resolved known set costs nothing to learn.
local liveInputs = Planner:DefaultInputs()
liveInputs.target = 20
local liveInput = Planner:MakeInput("Leatherworking", learning, liveInputs,
    { skill = 1, level = 20, known = { ["item:1002"] = true }, book = newBook() })
assert(liveInput.known[2] and liveInput.target == 20 and Planner:Option(liveInput, "confidence") == "safe")
route = Planner:Plan(liveInput)
assert(spells(route) == "2:1-20" and #route.events == 0, "a recipe the window showed is known")

-- Recipe data is filed without spaces.
assert(Planner:DataKey("First Aid") == "FirstAid" and Planner:DataKey("Leatherworking") == "Leatherworking")
assert(Planner:ProfessionOfKey("FirstAid") == "First Aid")

-- Where a recipe comes from.
book = newBook()
book.merchants[800] = { [5004] = { price = 0, count = 1, currency = { [3402] = 30 } } }
book.merchants[801] = { [5005] = { price = 900, count = 1 } }
book.trainers[900] = { [11] = { cost = 50 } }
local ctx = Prices:Context({ book = book, data = { items = {} } })
assert(Planner:RecipeSource(ctx, 10, { learn = "start" }) == "start")
local source, cost = Planner:RecipeSource(ctx, 11, { learn = "trainer" })
assert(source == "trainer" and cost == 50)
source, cost = Planner:RecipeSource(ctx, 12, { learn = "item", teach = 5004, bind = "bop" })
assert(source == "bop" and cost == nil, "a currency-only pattern is not a vendor pattern")
source, cost = Planner:RecipeSource(ctx, 13, { learn = "item", teach = 5005, bind = "boe" })
assert(source == "vendor" and cost == 900)
assert(Planner:RecipeSource(ctx, 14, { learn = "item", teach = 5006, bind = "boe" }) == "boe")
assert(Planner:RecipeSource(ctx, 15, { learn = "item", teach = 5007, bind = "bop" }) == "bop")

assert(Planner:WhenText({ when = "skill", skill = 50 }) == "at skill 50" and Planner:WhenText({}) == "best")

-- The Materials tab: the route's items, the ones it could not get, and on
-- asking every material in range.
local stuck = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 900, 1 } }),
    [3] = recipe(1003, { 60, 70, 80, 90 }, { { 102, 1 } }),
    [4] = recipe(1004, { 1, 30, 40, 50 }, { { 101, 1 } }),
}, items = items() }
route = plan(stuck, { target = 20 })
local priced = Planner:PriceItems(route, stuck)
assert(table.concat(priced, ",") == "100,900,1001", table.concat(priced, ","))
priced = Planner:PriceItems(route, stuck, true)
assert(table.concat(priced, ",") == "100,101,900,1001", "every material in range, and none past the target: " .. table.concat(priced, ","))
priced = Planner:PriceItems(route, stuck, true, 70)
assert(table.concat(priced, ",") == "100,101,102,900,1001", "up to the skill asked for")

-- A skill past the first run replans; the colours the window should show.
route = plan(chain, { target = 20 })
assert(not Planner:PassedRun(route, 5) and Planner:PassedRun(route, 11) and not Planner:PassedRun(route, 20))
local checks = Planner:ColorChecks(route, chain, 12)
assert(#checks == 2 and checks[1].spell == 1 and checks[1].expected == "yellow" and checks[2].expected == "orange")
assert(#Planner:ColorChecks(route, chain, 5) == 1, "a recipe the skill cannot make yet is not checked")

-- A trainer's recorded skill requirement replaces the shipped learn skill,
-- which for a trainer recipe is only the extraction's guess (its yellow).
local late = { recipes = {
    [1] = recipe(1001, { 1, 10, 15, 20 }, { { 100, 1 } }),
    [2] = recipe(1002, { 20, 20, 30, 40 }, { { 100, 1 } }, { learn = "trainer" }),
}, items = items() }
route = plan(late, { target = 30 })
assert(spells(route) == "1:1-20 2:20-30", "without a trainer's word, recipe 2 waits for 20: " .. spells(route))
book = newBook()
book.trainers[3000] = { [2] = { cost = 100, skill = 10, level = 5 } }
route = plan(late, { target = 30, book = book })
assert(route.runs[#route.runs].spell == 2 and route.runs[#route.runs].toSkill == 30, spells(route))
assert(Prices:TrainerSkill(book, 2) == 10 and Prices:TrainerSkill(book, 1) == nil)

-- A stretch far dearer a point than the rest is warned about.
local dear = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 25, 60, 70, 80 }, { { 103, 1 } }),
}, items = items() }
route = plan(dear, { target = 60 })
local found
for _, warning in ipairs(route.warnings) do if warning.code == "expensive" then found = warning end end
assert(found and found.spell == 2, "the 1g-a-point stretch is called out")
-- The tail, for the window: where it starts, what it costs, and the cost
-- said apart in the status sentence.
local tail = route.tail
assert(tail and tail.fromSkill == found.skill and tail.toSkill == 60 and tail.runIndex == #route.runs
    and route.runs[tail.runIndex].spell == 2, "the tail is its runs: " .. spells(route))
assert(tail.perPoint >= Planner.expensiveMinimum and tail.times >= Planner.expensiveFactor
    and math.abs(tail.net - tail.perPoint * (tail.toSkill - tail.fromSkill)) <= tail.toSkill - tail.fromSkill,
    "its net and cost a point agree")
assert(tail.net < route.summary.net, "the tail is part of the route's net")
assert(route.status.text:find(" to " .. tail.fromSkill .. ", then about ", 1, true)
    and route.status.text:find("for " .. tail.fromSkill .. "-60.", 1, true), route.status.text)
route = plan(chain, { target = 20 })
for _, warning in ipairs(route.warnings) do assert(warning.code ~= "expensive", "an even route has no warning") end
assert(route.tail == nil, "an even route has no tail")

-- The last sale at the target closes the tier it finishes: no empty
-- "Journeyman 75-75" section after an Apprentice route to 75.
local sold = { recipes = { [1] = recipe(1001, { 1, 80, 90, 100 }, { { 100, 1 } }) }, items = items() }
sold.items[1001] = { sell = 50 }
route = plan(sold, { target = 75 })
for _, section in ipairs(Planner:Sections(route, { profession = "Leatherworking" })) do
    assert(not section.title:find("Journeyman"), "no section past the target: " .. section.title)
end

-- Estimated prices: a material nobody priced gets an auction estimate from
-- its sell price, flagged all the way to the status line.
local guessed = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 105, 1 }, { 106, 3 } }),
}, items = items() }
guessed.items[105] = { sell = 5 }
guessed.items[106] = { sell = 10 }
local guessNames = { item = { [105] = "Light Leather", [106] = "Medium Leather", [107] = "Thick Leather" } }
local function guessName(kind, id) return guessNames[kind] and guessNames[kind][id] end
route = plan(guessed, { target = 20, nameOf = guessName })
assert(spells(route) == "1:1-20", "estimated materials make a route: " .. spells(route))
assert(#route.estimated == 2 and route.estimated[1] == 106 and route.estimated[2] == 105,
    "the estimate carrying the most cost first")
assert(route.summary.estimated == 2 and near(route.summary.estimatedShare, 1), "all of the cost rests on estimates")
assert(route.summary.spent == 19 * (20 + 3 * 40))
for _, line in ipairs(route.shopping) do assert(line.estimated and line.source == "estimate") end
assert(route.status.kind == "estimated", route.status.text)
assert(route.status.text == "Leatherworking 1 to 20: about 26s 60c, but 2 prices are estimates (Medium Leather, Light Leather). Check prices on the Materials tab.",
    route.status.text)
local estimatedRow = Planner:Outline(route)[1]
assert(estimatedRow.kind == "buy" and estimatedRow.estimated and estimatedRow.source == "estimate",
    "an estimated material is bought, and says it is an estimate")
local estimatedShop = Planner:Sections(route, { sections = "recipe" })[1].shopping[1]
assert(estimatedShop.estimated and estimatedShop.source == "estimate")

-- A real price beats the estimate and takes its flag away.
book = newBook()
Prices:SetFact(book, 105, "auctionBuy", 30)
route = plan(guessed, { target = 20, book = book })
assert(#route.estimated == 1 and route.estimated[1] == 106 and route.summary.estimatedShare < 1)
Prices:SetFact(book, 106, "auctionBuy", 30)
route = plan(guessed, { target = 20, book = book, nameOf = guessName })
assert(#route.estimated == 0 and route.summary.estimated == 0 and route.summary.estimatedShare == 0)
assert(route.status.kind == "ready" and route.status.text == "Leatherworking 1 to 20: about 22s 80c.", route.status.text)

-- No buying at the auction house: no estimates, and the plan is blocked.
route = plan(guessed, { target = 20, options = { auction = "sell" }, nameOf = guessName })
assert(#route.runs == 0 and route.status.kind == "blocked", route.status.text)
assert(route.status.text == "Cannot plan past 1: no vendor sells Light Leather and 1 more. Give them a price on the Materials tab.",
    route.status.text)
local unknownOnly = { recipes = { [1] = recipe(1001, { 1, 30, 40, 50 }, { { 107, 1 } }) }, items = items() }
unknownOnly.items[107] = { unknown = true }
route = plan(unknownOnly, { target = 20, nameOf = guessName })
assert(route.status.kind == "blocked" and route.status.text ==
    "Cannot plan past 1: no vendor sells Thick Leather. Give it a price on the Materials tab.", "an unknown item is never estimated")
assert(route.missingWhy == "auction" and plan(guessed, { target = 20, options = { auction = "sell" } }).missingWhy == "vendor")

-- Made from estimated parts: the intermediate's cost is an estimate too.
local fromParts = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 2000, 1 } }),
    [6] = recipe(2000, { 1, 2, 3, 4 }, { { 105, 2 } }),
}, items = items() }
fromParts.items[105] = { sell = 5 }
route = plan(fromParts, { skill = 5, target = 20 })
assert(spells(route) == "1:5-20" and route.runs[1].estimated, "the run rests on an estimate")
assert(route.estimated[1] == 105 and #route.estimated == 1, "the estimated part is named, not the intermediate")
local outline = Planner:Outline(route)
local made
for _, row in ipairs(outline) do if row.kind == "make" then made = row end end
assert(made and made.item == 2000 and made.estimated and made.source == "craft" and made.cost == made.count * 40,
    "the intermediate made from estimated parts is flagged")

-- How each material is had. An item a usable recipe makes is on make or buy
-- by default: whichever costs less per item. 2000 costs 5c at a vendor and
-- 20c made (1g of 103 makes five). The consumer, recipe 1,
-- is the grind. "make" pins making it, which the tests below use.
local interData = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 2000, 1 } }),
    [6] = recipe(2000, { 1, 10, 15, 20 }, { { 103, 1 } }, { made = { 5, 5 } }),
}, items = items() }
interData.items[2000] = { buy = 5, vendor = true }
local function makesOf(r)
    local list = {}
    for _, event in ipairs(r.events) do if event.kind == "make" then table.insert(list, event) end end
    return list
end
local makeIt = { [2000] = "make" }
route = plan(interData, { target = 20, options = { optimize = "cost", sellOutput = "chosen" } })
assert(#makesOf(route) == 0 and route.shopping[1].itemID == 2000 and route.shopping[1].source == "vendor",
    "make or buy: bought, as 5c at a vendor beats 20c made")
route = plan(interData, { target = 20, options = { optimize = "cost", sellOutput = "chosen", get = makeIt } })
local makeEvents = makesOf(route)
assert(#makeEvents == 1 and makeEvents[1].item == 2000 and makeEvents[1].spell == 6 and makeEvents[1].forSpell == 1
    , "make: made, though buying is cheaper")
assert(route.runs[1].spell == 1 and route.shopping[1].itemID == 103, "its parts are what is bought: " .. spells(route))
-- Its crafts, orange at skill 1, are points: the grind after them starts
-- higher, and the make says how many.
local made1 = makeEvents[1]
assert(made1.skill == 1 and made1.gain and made1.gain > 0 and route.runs[1].fromSkill == 1 + made1.gain,
    "the intermediates' skill shortens the grind: " .. spells(route) .. " gain " .. tostring(made1.gain))
assert(made1.crafts >= 3 and made1.count == made1.crafts * 5 and made1.forRun == 1)
assert(route.makes[1].itemID == 2000 and route.makes[1].gain == made1.gain, "summed by item for the Materials tab")
local makeRow
for _, row in ipairs(Planner:Outline(route)) do if row.kind == "make" then makeRow = row end end
assert(makeRow and makeRow.gain == made1.gain and makeRow.toSkill == 1 + made1.gain and makeRow.forSpell == 1
    and makeRow.crafts == made1.crafts, "the outline's make row")
-- Grey where it is made: no points, and the grind is the whole stretch.
route = plan(interData, { skill = 20, target = 30, options = { optimize = "cost", sellOutput = "chosen", get = makeIt } })
makeEvents = makesOf(route)
assert(#makeEvents == 1 and makeEvents[1].gain == nil and spells(route) == "1:20-30", "grey intermediates give nothing")
-- Buy: never made.
route = plan(interData, { target = 20, options = { optimize = "cost", sellOutput = "chosen", get = { [2000] = "buy" } } })
assert(#makesOf(route) == 0 and spells(route) == "1:1-20" and route.shopping[1].itemID == 2000
    and route.shopping[1].source == "vendor", "bought, never made")
-- Making at a loss: 2000 costs 20s made (1g of 103 makes five) and 5c at a
-- vendor. The route still makes it (the default), but says so.
local lossOptions = { optimize = "cost", sellOutput = "chosen", get = makeIt }
local lossInput
route, lossInput = plan(interData, { skill = 20, target = 30, options = lossOptions })
local losses = Planner:MakeLosses(route, lossInput)
assert(#losses == 1 and losses[1].itemID == 2000 and losses[1].kind == "paid" and near(losses[1].make, 2000)
    and losses[1].buy == 5 and losses[1].buyVia == "vendor" and losses[1].loss == 1995 * route.makes[1].count,
    "a make that costs more than buying it is a paid loss")
-- Grey where it is made, so nothing is lost by buying: buying saves.
local saves, bought = Planner:BuyingSaves(lossInput, route, 2000)
assert(saves and saves > 0 and #makesOf(bought) == 0, "buying it instead saves: " .. tostring(saves))
assert(lossInput.options.get[2000] == "make", "the trial leaves the player's options alone")
-- Where its crafts give skill, the trial still runs; what it says depends on
-- whether the skill is worth the loss.
route, lossInput = plan(interData, { target = 20, options = lossOptions })
assert(#Planner:MakeLosses(route, lossInput) == 1 and type((Planner:BuyingSaves(lossInput, route, 2000))) == "number")
-- Parts gathered free: the plan pays nothing, but they sell for more than
-- buying it costs.
interData.items[103].sell = 200
route, lossInput = plan(interData, { skill = 20, target = 30,
    options = { optimize = "cost", sellOutput = "chosen", gather = { [103] = "zero" } } })
losses = Planner:MakeLosses(route, lossInput)
assert(#losses == 1 and losses[1].kind == "free" and losses[1].free[1] == 103 and near(losses[1].worth, 40)
    and near(losses[1].make, 0), "free parts worth more than buying it: a hidden loss")
-- Valued instead, they cost what they would sell for, even when only the
-- output chosen counts as sold: the loss is then paid, and buying fixes it.
route, lossInput = plan(interData, { skill = 20, target = 30,
    options = { optimize = "cost", sellOutput = "chosen", gather = { [103] = "opportunity" }, get = makeIt } })
losses = Planner:MakeLosses(route, lossInput)
assert(#losses == 1 and losses[1].kind == "paid" and near(losses[1].make, 40), "valued parts are paid for")
interData.items[103].sell = 1
route, lossInput = plan(interData, { skill = 20, target = 30,
    options = { optimize = "cost", sellOutput = "chosen", gather = { [103] = "zero" } } })
assert(#Planner:MakeLosses(route, lossInput) == 0, "free parts worth less than it: no loss")
interData.items[103].sell = nil
-- Made recursively, each part as its own mode says: 2001 (made) is made of
-- 2000, which is bought here and made in the next.
interData.recipes[7] = recipe(2001, { 1, 2, 3, 4 }, { { 2000, 2 } })
interData.recipes[8] = recipe(1008, { 1, 30, 40, 50 }, { { 2001, 1 } })
interData.recipes[1] = nil
interData.items[2001] = { buy = 1, vendor = true }
route = plan(interData, { skill = 5, target = 20,
    options = { optimize = "cost", sellOutput = "chosen", get = { [2000] = "buy", [2001] = "make" } } })
makeEvents = makesOf(route)
assert(#makeEvents == 1 and makeEvents[1].item == 2001 and route.shopping[1].itemID == 2000, "the part to buy is bought")
route = plan(interData, { skill = 5, target = 20,
    options = { optimize = "cost", sellOutput = "chosen", get = { [2000] = "make", [2001] = "make" } } })
makeEvents = makesOf(route)
assert(#makeEvents == 2 and makeEvents[1].item == 2000 and makeEvents[2].item == 2001 and route.shopping[1].itemID == 103,
    "the part is made first, then what it makes")

-- The modes as the Materials tab sets them, and saves from before them.
local modeInputs = Planner:DefaultInputs()
assert(Planner:GetMode(modeInputs, 2000, true) == "auto" and Planner:GetMode(modeInputs, 100, false) == "buy")
assert(Planner:SetGetMode(modeInputs, 2000, "buy") and modeInputs.options.get[2000] == "buy"
    and Planner:GetMode(modeInputs, 2000, true) == "buy")
assert(Planner:SetGetMode(modeInputs, 2000, "gather-free") and modeInputs.options.gather[2000] == "zero"
    and modeInputs.options.get[2000] == nil and Planner:GetMode(modeInputs, 2000, true) == "gather-free")
assert(Planner:SetGetMode(modeInputs, 2000, "gather-valued") and modeInputs.options.gather[2000] == "opportunity")
assert(Planner:SetGetMode(modeInputs, 2000, "make") and modeInputs.options.gather[2000] == nil
    and modeInputs.options.get[2000] == "make" and Planner:GetMode(modeInputs, 2000, true) == "make")
assert(Planner:SetGetMode(modeInputs, 2000, "auto") and modeInputs.options.get[2000] == nil
    and Planner:GetMode(modeInputs, 2000, true) == "auto")
assert(Planner:SetGetMode(modeInputs, 2000, "steal") == false)
local oldStore = { professionPlanner = { plans = { Alchemy = { options = { gather = { [100] = "zero", [101] = "opportunity" } } } } } }
local oldInputs = Planner:LoadInputs(oldStore, "Alchemy")
assert(type(oldInputs.options.get) == "table" and Planner:GetMode(oldInputs, 100, true) == "gather-free"
    and Planner:GetMode(oldInputs, 101, false) == "gather-valued" and Planner:GetMode(oldInputs, 102, true) == "auto",
    "a save from before the modes loads, its gathering kept")
assert(Planner:Signature({ options = { get = { [1] = "buy" } } }) ~= Planner:Signature({ options = { get = {} } }),
    "a mode changed is a replan")

-- Status: done, and a route of known prices.
route = plan(chain, { skill = 20, target = 20 })
assert(route.status.kind == "done" and route.status.text == "Leatherworking is already at 20.", route.status.text)
route = plan(chain, { target = 20 })
assert(route.status.kind == "ready" and route.status.text == "Leatherworking 1 to 20: about 1s 90c.", route.status.text)
route = plan(chain, { target = 60 })
assert(route.status.kind == "short" and route.ceiling.reason == "recipes" and route.status.text
    == "Leatherworking 1 to 30 of 60, about 4s 83c: no recipe you can use gives skill at 30. The ways past it are at the end of the table.",
    "running out of recipes with every price known is not a block; the ceiling says why: " .. route.status.text)
route = plan(chain, { skill = 30, target = 60 })
assert(route.status.kind == "blocked" and route.status.text
    == "Cannot plan past 30: no recipe you can use gives skill at 30. The ways past it are at the end of the table.",
    route.status.text)
assert(route.wanted == 60 and route.target == 30 and route.gap and route.gap.skill == 30 and route.gap.to == nil
    and #route.gap.options == 0, "a route that cannot start has a gap too")

-- The gap: where a route stops short, the ways past it. With trainer
-- recipes only, at 20 only a BoP pattern, a refused recipe and one needing a material turned off give
-- skill; the trainer's next recipe starts at 25. The full-scope set has two
-- more that the beta left out for their materials.
local gapData = { recipes = {
    [1] = recipe(1001, { 1, 10, 15, 20 }, { { 100, 1 } }),
    [2] = recipe(1002, { 20, 30, 35, 40 }, { { 100, 1 } }, { learn = "item", teach = 5002, bind = "bop" }),
    [3] = recipe(1003, { 20, 30, 35, 40 }, { { 100, 1 } }),
    [4] = recipe(1004, { 20, 30, 35, 40 }, { { 101, 1 } }),
    [5] = recipe(1005, { 25, 30, 35, 40 }, { { 100, 1 } }),
}, items = items() }
local gapFull = { recipes = {}, items = items() }
for spell, row in pairs(gapData.recipes) do gapFull.recipes[spell] = row end
gapFull.recipes[6] = recipe(1006, { 20, 30, 35, 40 }, { { 100, 1 }, { 900, 1 } })
gapFull.recipes[7] = recipe(1007, { 15, 25, 30, 35 }, { { 902, 1 }, { 901, 1 } })
gapFull.recipes[8] = recipe(1008, { 25, 30, 35, 40 }, { { 900, 1 } })
gapFull.items[900] = { buy = 100, vendor = true, ilvl = 45 }
gapFull.items[901] = { buy = 100, vendor = true, ilvl = 40 }
gapFull.items[902] = { buy = 100, vendor = true, ilvl = 30 }
local gapInput = { target = 40, refused = { [3] = true }, avoided = { [101] = true }, fullData = gapFull }
route = plan(gapData, gapInput)
assert(route.target == 40 and not route.gap and used(route, 2) and route.summary.patterns == 1,
    "planning with every pattern, the BoP one carries the route past 20")
gapInput.options = { recipes = "trainer" }
route = plan(gapData, gapInput)
assert(route.target == 20 and route.ceiling.reason == "recipes" and route.status.kind == "short", route.status.text)
local gap = route.gap
assert(gap and gap.skill == 20 and gap.to == 25, "stops at 20, the next usable recipe is at 25")
local kinds = {}
for _, option in ipairs(gap.options) do table.insert(kinds, option.kind .. ":" .. tostring(option.spell or option.count)) end
assert(table.concat(kinds, " ") == "pattern:2 refused:3 avoided:4 beyond:2", table.concat(kinds, " "))
assert(gap.options[1].bind == "bop" and gap.options[1].source == "bop" and gap.options[1].item == 5002
    and gap.options[1].continues == true, "the pattern, and that having it carries the route on")
assert(gap.options[3].item == 101, "the avoided recipe names the material turned off")
local beyond = gap.options[4]
assert(beyond.recipes[1].spell == 6 and beyond.recipes[1].item == 900 and beyond.recipes[2].spell == 7
    and beyond.recipes[2].item == 901, "each left-out recipe names its highest-level material")
gapInput.accepted = { [2] = true }
route = plan(gapData, gapInput)
assert(route.target == 40 and route.gap == nil and route.ceiling.reason == "target" and used(route, 2),
    "I have it: the route goes on to the target: " .. spells(route))
gapInput.accepted, gapInput.fullScope = nil, true
route = plan(gapData, gapInput)
assert(route.gap and #route.gap.options == 3, "planning in full scope, nothing is left out")
assert(plan(chain, { target = 20 }).gap == nil, "no gap when the route reaches its target")

-- The default target: as far as the character can train now, never the
-- current skill.
assert(Planner:DefaultTarget({ skill = 83, level = 20 }) == 225)
assert(Planner:DefaultTarget({ skill = 83, level = 15 }) == 150)
assert(Planner:DefaultTarget({ skill = 83, level = 5 }) == 150, "a trained Journeyman keeps 150 whatever the level gate says")
assert(Planner:DefaultTarget({ skill = 83, level = 5, maxSkill = 150 }) == 150)
assert(Planner:DefaultTarget({ skill = 1, level = 5 }) == 75)
assert(Planner:DefaultTarget({ skill = 1 }) == 225, "no level: no level gate")
route = plan(long, { skill = 83 })
assert(route.target == 225 and route.wanted == 225 and route.runs[#route.runs].toSkill == 225, "level 20: to Expert's cap")
route = plan(long, { skill = 83, level = 12 })
assert(route.target == 150 and #route.runs > 0, "level 12: to Journeyman's cap")
route = plan(long, { skill = 83, level = 5 })
assert(route.target == 150 and #route.runs > 0 and route.status.kind == "ready", route.status.text)

-- The outline's rows: a pattern's getting and using are one "learn" row.
local fullRoute = plan(full, { skill = 0, target = 100, level = 20, book = (function()
    local b = newBook()
    b.merchants[3000] = { [100] = { price = 10, count = 1 } }
    Prices:SetFact(b, 1003, "auctionSell", 20)
    return b
end)(), accepted = { [3] = true }, goals = { { spell = 7, count = 3 }, { spell = 8, count = 1, when = "end" } } })
local kinds = {}
for _, row in ipairs(Planner:Outline(fullRoute)) do
    kinds[row.kind] = true
    if row.run then assert(fullRoute.runs[row.run], "a row's run is an index into route.runs") end
    if row.kind == "skillup" then
        local run = fullRoute.runs[row.run]
        assert(run.spell == row.spell and run.fromSkill == row.skill and run.toSkill == row.toSkill and row.low <= row.high)
    end
end
for _, kind in ipairs({ "train", "learn", "buy", "skillup", "goal", "sell" }) do
    assert(kinds[kind], "the outline has a " .. kind .. " row")
end
assert(Planner:Outline(fullRoute)[1].kind == "buy", "shopping first")

-- Splitting the plan: by tier, by recipe, by bands of skill levels. Each split
-- section brings its own shopping, only for what it makes.
local function sectionTitles(split)
    local list = {}
    for _, section in ipairs(split) do table.insert(list, section.title) end
    return table.concat(list, " | ")
end
local craftsAll = 0
for _, row in ipairs(Planner:Outline(fullRoute)) do
    if row.kind == "skillup" or row.kind == "goal" then craftsAll = craftsAll + 1 end
end
for _, mode in ipairs({ "tier", "recipe", "band" }) do
    local split = Planner:Sections(fullRoute, { profession = "Leatherworking", sections = mode, bandSize = 10 })
    assert(split[1].kind ~= "shopping", mode .. " has no shopping section up front")
    local crafts = 0
    for _, section in ipairs(split) do
        -- What a section buys is what its own recipes bring from the shops.
        local brought = {}
        for _, batch in ipairs(section.batches) do
            for item in pairs(batch.buys or {}) do brought[item] = true end
        end
        for _, item in ipairs(section.shopping) do
            assert(brought[item.itemID], mode .. ": " .. section.title .. " buys only what it uses (" .. item.itemID .. ")")
        end
        for _, element in ipairs(section.elements) do
            if element.row.kind == "skillup" or element.row.kind == "goal" then crafts = crafts + 1 end
        end
    end
    assert(crafts == craftsAll, mode .. ": every run and goal is still made once: " .. crafts .. " of " .. craftsAll)
end
local tiers = sectionTitles(Planner:Sections(fullRoute, { profession = "Leatherworking", sections = "tier" }))
assert(tiers:match("^Apprentice 1%-75 | Journeyman 75%-100 | Goals$"), tiers)
local byRecipe = Planner:Sections(fullRoute, { profession = "Leatherworking", sections = "recipe" })
local runsAndGoals = 0
for _, batch in ipairs(fullRoute.batches) do if not (batch.goal and batch.goal.atEnd) then runsAndGoals = runsAndGoals + 1 end end
assert(#byRecipe == runsAndGoals + 1, "a section per recipe made, and the goals kept for the end: " .. #byRecipe)
assert(byRecipe[1].elements[1].row.kind == "buy" and byRecipe[1].shopping[1], "a recipe section opens with its shopping")
for _, section in ipairs(byRecipe) do
    assert(section.fromSkill <= section.toSkill and section.title ~= "", section.title)
end
for _, run in ipairs(fullRoute.runs) do
    assert(math.abs(run.matCraft - run.sellCraft - run.perCraft) < 1e-6, "a craft's net is its cost less its value")
end
for _, section in ipairs(byRecipe) do
    assert(math.abs(section.spent - section.earned - section.cost) <= 2, section.title .. ": cost and sale add up to the net")
end
local byTwo = Planner:Sections(fullRoute, { profession = "Leatherworking", sections = "recipe", recipesPerSection = 2 })
assert(#byTwo == math.ceil(runsAndGoals / 2) + 1, "two recipes a section: " .. #byTwo)
assert(#byTwo[1].batches == 2 and byTwo[1].title:find(", "), "named by both: " .. byTwo[1].title)
local wide = Planner:Sections(fullRoute, { profession = "Leatherworking", sections = "band", bandSize = 1000 })
assert(#wide == 2 and wide[2].kind == "goals", "one band wider than the route is one section and the goals")
local narrow = Planner:Sections(fullRoute, { profession = "Leatherworking", sections = "band", bandSize = 5 })
assert(#narrow > 2, "narrow bands split the route")
-- Bands are cut at round skill levels: every one but the first starts on a multiple
-- of the size, every one but the last ends on one, and each recipe is in the
-- band it starts in.
local round = Planner:Sections(fullRoute, { profession = "Leatherworking", sections = "band", bandSize = 5 })
for index, section in ipairs(round) do
    if section.kind == "band" then
        if index > 1 then assert(section.fromSkill % 5 == 0, "a band starts at a round skill: " .. section.fromSkill) end
        assert(section.toSkill % 5 == 0 or section.toSkill == fullRoute.target, "a band ends at a round skill")
        for _, element in ipairs(section.elements) do
            if element.row.kind == "skillup" then
                assert(element.row.skill >= section.fromSkill and element.row.skill < section.toSkill,
                    "a recipe sits in the band it starts in")
            end
        end
    end
end

-- Shipped trainer recordings count like this session's windows, which win.
ns.professionRecorded = { trainers = { [3000] = { [2] = { cost = 100, skill = 10, level = 5, spellID = 2, seen = 1 } } } }
route = plan(late, { target = 30 })
assert(spells(route) ~= "1:1-20 2:20-30" and route.runs[#route.runs].spell == 2, "the recorded skill opens recipe 2 early: " .. spells(route))
local learnEvent
for _, event in ipairs(route.events) do if event.kind == "learn" then learnEvent = event end end
assert(learnEvent and learnEvent.cost == 100 and learnEvent.npc == 3000, "at the recorded fee")
book = newBook()
book.trainers[3000] = { [2] = { cost = 150, skill = 20, level = 5 } }
route = plan(late, { target = 30, book = book })
assert(spells(route) == "1:1-20 2:20-30", "this session's window wins over the recording: " .. spells(route))
ns.professionRecorded = nil

-- Auctionator: its prices replace estimates, are counted, and the status
-- asks for an auction house visit while it has none.
Prices:SetAuctionSource(function() return nil end, function() return true end)
route = plan(guessed, { target = 20, nameOf = guessName })
assert(route.auctionator and route.summary.auctionator == 0 and route.status.kind == "estimated")
assert(route.status.text:match("open the auction house with Auctionator to read real prices%.$"), route.status.text)
Prices:SetAuctionSource(function(itemID) if itemID == 105 then return 25, 0 end end, function() return true end)
route = plan(guessed, { target = 20, nameOf = guessName })
assert(route.summary.auctionator == 1 and #route.estimated == 1 and route.estimated[1] == 106,
    "an item Auctionator prices is never estimated")
assert(route.status.text:match("Check prices on the Materials tab%.$"), "Auctionator has spoken: no visit asked for")
route = plan(guessed, { target = 20, options = { useAuctionator = false } })
assert(not route.auctionator and route.summary.auctionator == 0 and #route.estimated == 2, "the option turns it off")
Prices:SetAuctionSource(nil)
route = plan(guessed, { target = 20 })
assert(not route.auctionator and route.status.text:match("Check prices on the Materials tab%.$"), "no Auctionator: no mention of it")

-- Plan with: one choice a recipe, stored as pinned, refused or accepted.
inputs = Planner:DefaultInputs()
assert(Planner:PlanWith(inputs, 2) == "auto")
Planner:BumpGoal(inputs, 2)
Planner:SetPlanWith(inputs, 2, "prefer")
assert(Planner:PlanWith(inputs, 2) == "prefer" and inputs.pinned[2] and not inputs.refused[2] and not inputs.accepted[2])
Planner:SetPlanWith(inputs, 2, "have")
assert(Planner:PlanWith(inputs, 2) == "have" and inputs.accepted[2] and not inputs.pinned[2] and not inputs.refused[2],
    "the modes exclude each other")
assert(Planner:FindGoal(inputs, 2), "prefer and have keep the goal")
Planner:SetPlanWith(inputs, 2, "never")
assert(Planner:PlanWith(inputs, 2) == "never" and inputs.refused[2] and not inputs.accepted[2] and not inputs.pinned[2])
assert(Planner:FindGoal(inputs, 2) == nil, "never drops the goal, as refusing does")
Planner:SetPlanWith(inputs, 2, "auto")
assert(Planner:PlanWith(inputs, 2) == "auto" and not inputs.refused[2] and not inputs.accepted[2] and not inputs.pinned[2])
assert(not Planner:SetPlanWith(inputs, 2, "bogus"), "an unknown mode is refused")
Planner:BumpGoal(inputs, 1)
Planner:SetPlanWith(inputs, 2, "never")
assert(Planner:FindGoal(inputs, 1), "never on one recipe keeps another's goal")

-- Material modes: prefer and never exclude each other; a preferred material
-- pins every usable recipe that needs it.
inputs = Planner:DefaultInputs()
assert(Planner:MaterialMode(inputs, 101) == "auto")
Planner:SetMaterialMode(inputs, 101, "prefer")
assert(Planner:MaterialMode(inputs, 101) == "prefer" and inputs.preferred[101] and not inputs.avoided[101])
Planner:SetMaterialMode(inputs, 101, "never")
assert(Planner:MaterialMode(inputs, 101) == "never" and inputs.avoided[101] and not inputs.preferred[101])
Planner:SetMaterialMode(inputs, 101, "prefer")
Planner:Avoid(inputs, 101)
assert(Planner:MaterialMode(inputs, 101) == "never", "Avoid drops the preference")
Planner:SetMaterialMode(inputs, 101, "auto")
assert(Planner:MaterialMode(inputs, 101) == "auto" and not inputs.avoided[101] and not inputs.preferred[101])
route = plan(cheapest, { target = 20, preferred = { [101] = true } })
assert(spells(route) == "2:1-20", "a recipe using a preferred material is used where it gives skill: " .. spells(route))
route = plan(cheapest, { target = 20, preferred = { [101] = true }, refused = { [2] = true } })
assert(spells(route) == "1:1-20", "not when refused")
local mixed = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 101, 1 }, { 102, 1 } }),
}, items = items() }
route = plan(mixed, { target = 20, preferred = { [101] = true }, avoided = { [102] = true } })
assert(spells(route) == "1:1-20", "nor when it needs an avoided material")
route = plan(patterns, { target = 20, preferred = { [104] = true }, options = { recipes = "trainer" } })
assert(spells(route) == "1:1-20", "trainer only: a preference does not bring in a pattern the player does not have")
route = plan(patterns, { target = 20, preferred = { [104] = true } })
assert(spells(route) == "3:1-20" and route.runs[1].needsPattern, "planning with every pattern it is used, still marked")
route = plan(patterns, { target = 20, pinned = { [3] = true } })
assert(route.runs[1].needsPattern, "a pin is not the pattern in hand")
route = plan(mixed, { target = 20, preferred = { [102] = true } })
assert(spells(route) == "2:1-20", "any of a recipe's materials will do")

-- Preferred materials and the no-sell set are saved, loaded and signed.
inputs = Planner:DefaultInputs()
assert(inputs.preferred and inputs.options.nosell, "fresh inputs have both")
inputs.preferred[101] = true
Planner:SetSaleMode(inputs, 1002, "keep")
local store = {}
Planner:SaveInputs(store, "Leatherworking", inputs)
local loaded = Planner:LoadInputs(store, "Leatherworking")
assert(loaded.preferred[101] and loaded.options.nosell[1002], "a round trip keeps them")
local made = Planner:MakeInput("Leatherworking", cheapest, loaded, { skill = 1 })
assert(made.preferred[101], "MakeInput passes the preferences on")
local plain = Planner:MakeInput("Leatherworking", cheapest, Planner:DefaultInputs(), { skill = 1 })
assert(Planner:Signature(made) ~= Planner:Signature(plain), "and the signature notices them")

-- Sale modes: the same in both Count-as-sold settings, but for "default".
-- 1002 lists at 50 (47 after the cut) and a vendor pays 10 for it.
local sales = { recipes = resale.recipes, items = items() }
sales.items[1002] = { sell = 10 }
book = newBook()
Prices:SetFact(book, 1002, "auctionSell", 50)
local function worth(mode, sellOutput)
    local saleInputs = Planner:DefaultInputs()
    assert(Planner:SetSaleMode(saleInputs, 1002, mode))
    assert(Planner:SaleMode(saleInputs, 1002) == mode, mode)
    local options = saleInputs.options
    options.sellOutput = sellOutput
    return (Prices:Context({ book = book, data = sales, options = options }):SellValue(1002))
end
assert(worth("default", "all") == 47 and worth("default", "chosen") == 0, "default follows the setting")
assert(worth("sell", "all") == 47 and worth("sell", "chosen") == 47, "sell: at its best price")
assert(worth("vendor", "all") == 10 and worth("vendor", "chosen") == 10, "vendor: sold, at the vendor price")
assert(worth("keep", "all") == 0 and worth("keep", "chosen") == 0, "keep: never counted as sold")
inputs = Planner:DefaultInputs()
Planner:SetSaleMode(inputs, 1002, "sell")
Planner:SetSaleMode(inputs, 1002, "vendor")
assert(inputs.options.keep[1002] and not inputs.options.sell[1002] and not inputs.options.nosell[1002], "exclusive")
Planner:SetSaleMode(inputs, 1002, "default")
assert(Planner:SaleMode(inputs, 1002) == "default" and not inputs.options.keep[1002])
assert(not Planner:SetSaleMode(inputs, 1002, "bogus"))
route = plan(sales, { target = 20, book = book, options = { sellOutput = "all", nosell = { [1002] = true } } })
assert(spells(route) == "1:1-20" and route.summary.recovered == 0, "kept output is not sold, even counting all")
route = plan(sales, { target = 20, book = book, options = { sellOutput = "chosen", sell = { [1002] = true } } })
assert(spells(route) == "2:1-20" and route.summary.recovered == 19 * 47, "chosen to sell: " .. spells(route))
route = plan(sales, { target = 20, book = book, options = { sellOutput = "chosen", keep = { [1002] = true } } })
assert(spells(route) == "1:1-20", "at 10 back it does not pay: " .. spells(route))

-- The choices at a step: the planner's own pick and every recipe that gives
-- skill at each of the step's skill levels, one recipe for exactly those skill levels,
-- the suggested patterns among them, cheapest first.
local around4 = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 101, 1 } }),
    [3] = recipe(1003, { 1, 30, 40, 50 }, { { 102, 1 } }),
    [4] = recipe(1004, { 1, 30, 40, 50 }, { { 103, 1 } }),
    [5] = recipe(1005, { 1, 30, 40, 50 }, { { 104, 1 } }, { learn = "item", teach = 5005, bind = "bop" }),
}, items = items() }
around4.items[104] = { buy = 1, vendor = true }
local function wayList(list)
    local out = {}
    for _, way in ipairs(list) do
        table.insert(out, way.kind .. ":" .. table.concat(way.spells, ",") .. ":" .. way.fromSkill .. "-" .. way.toSkill
            .. ":" .. way.extra)
    end
    return table.concat(out, " ")
end
local function usingOf(list)
    local found
    for index, way in ipairs(list) do
        if way.using then
            assert(found == nil, "one choice in use")
            found = index
        end
    end
    return found
end
route = plan(around4, { target = 20, options = small })
assert(spells(route) == "1:1-20" and route.runs[1].others == 4, spells(route))
local ways = Planner:WaysAround(route, 1)
assert(wayList(ways) == "pattern:5:1-20:-171 planner:1:1-20:0 other:2:1-20:190 other:3:1-20:760 other:4:1-20:189810",
    wayList(ways))
assert(usingOf(ways) == 2, "the planner's pick is the one in use")
for _, way in ipairs(ways) do
    assert(way.spell == way.spells[1] and way.crafts == 19, "one craft a point over the step")
end
assert(ways[1].bind == "bop" and ways[1].source == "bop" and ways[1].item == 5005 and near(ways[1].perPoint, 1),
    "a pattern choice says what it is")
assert(ways[3].source == "start" and near(ways[3].perPoint, 20))
assert(route.ways[1] and Planner:WaysAround(route, 1)[2] == ways[2], "solved once, then cached on the route")
assert(#Planner:WaysAround(route, 1, 2) == 3, "at most `limit` besides the planner's pick")
assert(#Planner:WaysAround(route, 9) == 0 and #Planner:WaysAround(nil, 1) == 0, "no such step")
route = plan(chain, { target = 20 })
ways = Planner:WaysAround(route, 2)
assert(wayList(ways) == "planner:2:11-20:0 other:1:11-20:193" and ways[1].using,
    "recipe 1, green to grey, costs more crafts: " .. wayList(ways))

-- Using a choice is local to the step's skill levels: its recipe is chosen for
-- exactly them, and the rest of the route is the planner's as before.
-- Recipe 3 would also do for 1-11, so a pin would have moved run 1 too.
-- Recipe 7 goes grey at 16, inside the second step, so it is no choice there.
local three = { recipes = {
    [1] = recipe(1001, { 1, 11, 11, 11 }, { { 100, 1 } }),
    [2] = recipe(1002, { 11, 21, 21, 21 }, { { 100, 1 } }),
    [3] = recipe(1003, { 1, 21, 21, 21 }, { { 101, 1 } }),
    [4] = recipe(1004, { 11, 21, 21, 21 }, { { 102, 1 } }),
    [5] = recipe(1005, { 21, 30, 30, 30 }, { { 100, 1 } }),
    [6] = recipe(1006, { 1, 11, 11, 11 }, { { 102, 1 } }),
    [7] = recipe(1007, { 11, 16, 16, 16 }, { { 101, 1 } }),
}, items = items() }
route = plan(three, { target = 30 })
assert(spells(route) == "1:1-11 2:11-21 5:21-30", spells(route))
local firstWays = wayList(Planner:WaysAround(route, 1))
assert(firstWays == "planner:1:1-11:0 other:3:1-11:100 other:6:1-11:400", firstWays)
ways = Planner:WaysAround(route, 2)
local stepWays = wayList(ways)
assert(stepWays == "planner:2:11-21:0 other:3:11-21:100 other:4:11-21:400", stepWays)
inputs = Planner:DefaultInputs()
assert(#inputs.chosen == 0, "nothing chosen at first")
assert(Planner:UseWay(inputs, ways[2]))
assert(#inputs.chosen == 1 and inputs.chosen[1].fromSkill == 11 and inputs.chosen[1].toSkill == 21
    and inputs.chosen[1].spell == 3, "chosen for exactly the step")
assert(Planner:ChosenAt(inputs, 10) == nil and Planner:ChosenAt(inputs, 21) == nil, "only over its skills")
assert(Planner:PlanWith(inputs, 3) == "auto" and not next(inputs.pinned), "no pin")
route = plan(three, { target = 30, chosen = inputs.chosen })
assert(spells(route) == "1:1-11 3:11-21 5:21-30", "the rest stays put: " .. spells(route))
assert(route.runs[2].chosen and not route.runs[1].chosen and not route.runs[3].chosen, "the chosen run says so")
assert(#route.chosen == 1 and route.chosen[1].fromSkill == 11, "the route keeps the stretch")
assert(wayList(Planner:WaysAround(route, 1)) == firstWays, "an earlier step's choices do not move")

-- The list at a step is the same whichever choice is taken, and in the same
-- order; only `using` moves. Taking each in turn, then the planner's pick,
-- which clears the stretch.
local function stepAt(chosen, skill)
    route = plan(three, { target = 30, chosen = chosen })
    for index, run in ipairs(route.runs) do
        if run.fromSkill <= skill and skill < run.toSkill then return Planner:WaysAround(route, index), route.runs[index] end
    end
end
for pick = 3, 1, -1 do
    assert(Planner:UseWay(inputs, stepAt(inputs.chosen, 11)[pick]))
    local list, run = stepAt(inputs.chosen, 11)
    assert(wayList(list) == stepWays, "the same list with choice " .. pick .. " taken: " .. wayList(list))
    assert(usingOf(list) == pick, "the taken choice is in use: " .. tostring(usingOf(list)))
    assert(run.fromSkill == 11 and run.toSkill == 21, "and the step keeps its skills")
end
assert(#inputs.chosen == 0, "the planner's pick clears the stretch")

-- A stretch is a step of its own: it never runs on into a neighbour making
-- the same recipe, and the neighbours keep their own skill levels.
route = plan(cheapest, { target = 20, chosen = { { fromSkill = 5, toSkill = 10, spell = 1 } } })
assert(spells(route) == "1:1-5 1:5-10 1:10-20", spells(route))
assert(route.runs[2].chosen and not route.runs[1].chosen and not route.runs[3].chosen)
route = plan(cheapest, { target = 20, chosen = { { fromSkill = 5, toSkill = 10, spell = 2 } } })
assert(spells(route) == "1:1-5 2:5-10 1:10-20", spells(route))
ways = Planner:WaysAround(route, 2)
assert(wayList(ways) == "planner:1:5-10:0 other:2:5-10:50" and usingOf(ways) == 2, wayList(ways))
assert(Planner:UseWay(inputs, ways[1]) and #inputs.chosen == 0)

-- ChosenAt and ClearChosen: only the skill levels asked for are cleared; a stretch
-- reaching past them keeps the rest.
inputs.chosen = { { fromSkill = 1, toSkill = 5, spell = 3 }, { fromSkill = 11, toSkill = 15, spell = 4 },
    { fromSkill = 13, toSkill = 21, spell = 3 } }
assert(Planner:ChosenAt(inputs, 14).spell == 3 and Planner:ChosenAt(inputs, 12).spell == 4, "the last one wins")
assert(Planner:ClearChosen(inputs, 5, 12) == 1 and #inputs.chosen == 3, "one touched")
assert(inputs.chosen[1].fromSkill == 1 and inputs.chosen[1].toSkill == 5, "the one before untouched")
assert(inputs.chosen[2].fromSkill == 12 and inputs.chosen[2].toSkill == 15 and inputs.chosen[2].spell == 4, "trimmed")
assert(inputs.chosen[3].fromSkill == 13 and inputs.chosen[3].toSkill == 21)
assert(Planner:ClearChosen(inputs, 21, 30) == 0 and Planner:ClearChosen(inputs, 14, 16) == 2 and #inputs.chosen == 4)
assert(Planner:ClearChosen(inputs, 1, 30) == 4 and #inputs.chosen == 0)
-- Using a choice replaces only what lies inside its step.
inputs.chosen = { { fromSkill = 1, toSkill = 11, spell = 3 }, { fromSkill = 5, toSkill = 15, spell = 6 } }
assert(Planner:UseWay(inputs, { kind = "other", fromSkill = 11, toSkill = 21, spell = 4 }))
assert(#inputs.chosen == 3 and inputs.chosen[1].toSkill == 11 and inputs.chosen[2].fromSkill == 5
    and inputs.chosen[2].toSkill == 11 and inputs.chosen[3].spell == 4, "the stretch before keeps its skills")
assert(not Planner:UseWay(inputs, nil) and not Planner:UseWay(inputs, { kind = "other", fromSkill = 1, toSkill = 5 }))
-- A stretch the route cannot use is ignored, not fatal: a recipe that gives
-- no skill there, one refused, one this profession does not have.
local ignored = { { fromSkill = 1, toSkill = 11, spell = 5 }, { fromSkill = 11, toSkill = 21, spell = 4 },
    { fromSkill = 21, toSkill = 30, spell = 99 } }
route = plan(three, { target = 30, chosen = ignored, refused = { [4] = true } })
assert(spells(route) == "1:1-11 2:11-21 5:21-30" and #route.chosen == 1, spells(route))
-- A save from before the redesign, its stretches tagged with the detour
-- they came with: the tags are ignored.
local tagged = { { fromSkill = 11, toSkill = 21, spell = 3, leave = 1, rejoin = 30 } }
route = plan(three, { target = 30, chosen = tagged })
assert(spells(route) == "1:1-11 3:11-21 5:21-30", spells(route))
ways = Planner:WaysAround(route, 2)
assert(wayList(ways) == stepWays and usingOf(ways) == 2, wayList(ways))
-- Saved, loaded, passed on and noticed like the other inputs.
inputs = Planner:DefaultInputs()
inputs.chosen = tagged
store = {}
Planner:SaveInputs(store, "Leatherworking", inputs)
loaded = Planner:LoadInputs(store, "Leatherworking")
assert(loaded.chosen[1].spell == 3 and loaded.chosen ~= inputs.chosen, "a copy round trip")
made = Planner:MakeInput("Leatherworking", three, loaded, { skill = 1 })
assert(made.chosen[1].toSkill == 21)
assert(Planner:Signature(made) ~= Planner:Signature(Planner:MakeInput("Leatherworking", three, nil, { skill = 1 })))
assert(Planner:ClearChosen(loaded, 11, 21) == 1 and #loaded.chosen == 0, "and cleared like any other")
-- A pattern choice: the pattern is in hand everywhere, and chosen over the step.
route = plan(around4, { target = 20, options = small })
ways = Planner:WaysAround(route, 1)
inputs = Planner:DefaultInputs()
assert(ways[1].kind == "pattern" and Planner:UseWay(inputs, ways[1]))
assert(Planner:PlanWith(inputs, 5) == "have" and #inputs.chosen == 1 and inputs.chosen[1].spell == 5
    and inputs.chosen[1].fromSkill == 1 and inputs.chosen[1].toSkill == 20)
route = plan(around4, { target = 20, accepted = inputs.accepted, chosen = inputs.chosen })
assert(spells(route) == "5:1-20", "the pattern is used: " .. spells(route))
-- In hand, the pattern is a recipe like any other: the planner's own pick
-- now, so the stretch is its choice and in use.
local after = Planner:WaysAround(route, 1)
assert(wayList(after) == "planner:5:1-20:0 other:1:1-20:171 other:2:1-20:361 other:3:1-20:931 other:4:1-20:189981"
    and usingOf(after) == 1, wayList(after))
assert(Planner:UseWay(inputs, after[1]) and #inputs.chosen == 0)

-- Material candidates: the profession's reagents by name, filtered.
local stuff = { recipes = {
    [1] = recipe(1001, { 1, 30, 40, 50 }, { { 100, 1 }, { 102, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 101, 2 }, { 100, 1 } }),
    [3] = recipe(1003, { 1, 30, 40, 50 }, { { 103, 1 } }, { sod = true }),
}, items = items() }
local stuffNames = { [100] = "Light Leather", [101] = "Heavy Leather", [102] = "Salt" }
local function stuffName(kind, id) return kind == "item" and stuffNames[id] or nil end
local found = Planner:MaterialCandidates(stuff, "LEATHER", stuffName, nil, { avoided = { [101] = true } })
assert(#found == 2 and found[1].itemID == 101 and found[1].name == "Heavy Leather" and found[1].recipes == 1 and found[1].never)
assert(found[2].itemID == 100 and found[2].recipes == 2 and not found[2].never, "by name, with their recipe counts")
found = Planner:MaterialCandidates(stuff, "", stuffName)
assert(#found == 3 and found[3].name == "Salt", "an empty query lists them all, SoD recipes left out")
assert(#Planner:MaterialCandidates(stuff, nil, nil, 1) == 1, "a limit, and item names without nameOf")
assert(Planner:MaterialCandidates(stuff, "item 102", nil)[1].itemID == 102)
assert(Planner:MaterialRecipeCount(stuff, 100) == 2 and Planner:MaterialRecipeCount(stuff, 103) == 0)


-- The testing switch: the full tier list runs to Artisan (300), then back.
local Tiers = ns.modules.ProfessionTiers
assert(Tiers:MaxCap() == 225 and not Tiers.fullScope, "the beta's scope stops at Expert")
Tiers:SetFullScope(true)
assert(Tiers:MaxCap() == 300 and Tiers.tiers[4].name == "Artisan" and Tiers.tiers[4].level == 35)
assert(Tiers:CapForLevel(60) == 300 and Tiers:CapForLevel(20) == 225)
Tiers:SetFullScope(false)
assert(Tiers:MaxCap() == 225 and #Tiers.tiers == 3 and Tiers:CapForLevel(60) == 225, "and back")

-- Only what I have (materials = "carried"): what is carried and what
-- vendors sell, never the auction house or a guess, as far as it goes. 200
-- and 201 no vendor sells; the player carries ten of 200 and none of 201.
local carried = { recipes = {
    [1] = recipe(1001, { 1, 10, 15, 20 }, { { 200, 2 } }),
    [2] = recipe(1002, { 1, 10, 15, 20 }, { { 103, 1 } }),
    [3] = recipe(1003, { 12, 20, 25, 30 }, { { 201, 1 } }),
}, items = items() }
carried.items[200], carried.items[201] = { sell = 5 }, { sell = 5 }
local carrying = { [200] = 10 }
local function carriedBags(id) return carrying[id] or 0 end
route = plan(carried, { target = 20, bags = carriedBags })
assert(used(route, 1) and not used(route, 2), "buying, never the dear vendor recipe: " .. spells(route))
route = plan(carried, { target = 20, bags = carriedBags, options = { materials = "carried" } })
assert(spells(route) == "1:1-6 2:6-20", "the ten hides make five points, then the vendor's: " .. spells(route))
assert(route.materials == "carried" and route.ceiling.reason == "target" and #route.ranOut == 1
    and route.ranOut[1].itemID == 200 and route.ranOut[1].skill == 6, "and it says where they ran out")
for _, row in ipairs(route.shopping) do
    assert(row.source ~= "ah" and row.source ~= "estimate", "nothing from the auction house")
    assert(row.itemID ~= 200, "the hides are all in the bags: nothing to shop for")
end
assert(route.shopping[1] and route.shopping[1].itemID == 103 and route.shopping[1].source == "vendor")
assert(route.unobtainable[1].itemID == 201 and route.missingWhy == "carried", "none carried and no vendor: no source")
-- The steps' materials say the hides are the player's own.
assert(route.runs[1].needs[1][1] == 200 and route.runs[1].needs[1][3] == "gather")

-- Without the vendor's recipe the route stops where the hides run out.
local onlyHides = { recipes = { [1] = carried.recipes[1] }, items = carried.items }
route = plan(onlyHides, { target = 20, bags = carriedBags, options = { materials = "carried" } })
assert(spells(route) == "1:1-6" and route.target == 6 and route.wanted == 20, spells(route))
assert(route.ceiling.text == "item 200 runs out at 6.", route.ceiling.text)
assert(route.ceiling.reason == "materials" and route.status.kind == "ready"
    and route.status.text:find("^Leatherworking 1 to 6: about [%w ]+%.$"), route.status.text)
-- With only what is carried the skill levels are the guess, planned at the
-- expected skill-ups whatever the confidence says ("sure" is a shopping
-- list's margin), and the shopping list never asks for more hides.
carrying[200] = 30
local typical = plan(onlyHides, { skill = 8, target = 20, bags = carriedBags,
    options = { materials = "carried", confidence = "typical" } })
local sure = plan(onlyHides, { skill = 8, target = 20, bags = carriedBags,
    options = { materials = "carried", confidence = "sure" } })
assert(sure.target == typical.target and typical.target < 20 and sure.confidence == "typical",
    sure.target .. " " .. typical.target)
for _, row in ipairs(sure.shopping) do
    assert(row.itemID ~= 200 or row.buy == 0, "no hides to buy at sure")
end
-- The hides end the route, so its crafts are theirs, not the odds': thirty
-- hides, fifteen crafts, whatever the skill levels they are expected to reach.
do
    local crafts = 0
    for _, run in ipairs(typical.runs) do
        assert(run.carriedCap, "a step on the last of the hides makes all of them")
        crafts = crafts + run.count
    end
    assert(crafts == 15, "thirty hides make fifteen crafts: " .. crafts)
    -- A target typed short of where the hides go: the target stops the
    -- step, and its crafts are the odds' again.
    local short = plan(onlyHides, { skill = 8, target = 12, bags = carriedBags, options = { materials = "carried" } })
    assert(short.ceiling.reason == "target" and not short.runs[1].carriedCap and short.runs[1].count < 15,
        "to 12: the crafts to reach it, not all the hides")
end
-- Leftovers short of the confidence count for a point still try for it:
-- two hides (one craft) at a green skill are one more point, not the end.
carrying[200] = 2
route = plan(onlyHides, { skill = 17, target = 20, bags = carriedBags, options = { materials = "carried", confidence = "sure" } })
assert(spells(route) == "1:17-18" and route.target == 18 and route.status.kind == "ready", spells(route))
-- Carrying none, nothing can start.
carrying[200] = 0
route = plan(onlyHides, { target = 20, bags = carriedBags, options = { materials = "carried" } })
assert(#route.runs == 0 and route.status.kind == "blocked"
    and route.status.text == "Cannot plan past 1 with what you carry.", route.status.text)
-- A material carried by none stops the route where it must: the plain
-- sentence, and the warnings name it.
carrying[200] = 10
local noCloth = { recipes = { [1] = recipe(1001, { 1, 10, 15, 20 }, { { 103, 1 } }),
    [2] = recipe(1002, { 10, 20, 25, 30 }, { { 201, 1 } }) }, items = carried.items }
route = plan(noCloth, { target = 25, bags = carriedBags, options = { materials = "carried" } })
assert(route.target == 20 and route.status.kind == "ready"
    and route.status.text:find("^Leatherworking 1 to 20: about [%w ]+%.$"), route.status.text)
assert(route.unobtainable[1].itemID == 201)
carrying[200] = 10

-- A carried material goes where it saves the most crafts. The belt (200,
-- six a craft, 42 carried: seven crafts) is orange all the way, a sure
-- point anywhere; the stone (201, plenty) is yellow, its chance falling
-- with every skill. Stones first and the belts last beat spending the
-- belts on the first skill levels, as the cuts alone would. Neither has a price.
do
    local scarce = { recipes = {
        [1] = recipe(1001, { 1, 25, 30, 40 }, { { 200, 6 } }),
        [2] = recipe(1002, { 1, 1, 20, 30 }, { { 201, 2 } }),
    }, items = { [200] = {}, [201] = {} } }
    local bags = { [200] = 42, [201] = 200 }
    route = plan(scarce, { target = 21, bags = function(id) return bags[id] or 0 end,
        options = { materials = "carried" } })
    assert(spells(route) == "2:1-14 1:14-21", "stones first, the belts last: " .. spells(route))
    assert(route.ceiling.reason == "target" and #route.ranOut == 0, "the belts last to the target")
    local crafts = 0
    for _, run in ipairs(route.runs) do crafts = crafts + run.expected end
    assert(crafts < 7 + SkillUp:Span(scarce.recipes[2].skills, 8, 21), "fewer crafts than the belts first")
    for _, row in ipairs(route.shopping) do assert(row.buy == 0, "nothing to buy") end
    -- Money still steers first: hides that sell dear are kept, and the
    -- stones go all the way.
    local dear = { recipes = scarce.recipes, items = { [200] = { sell = 500 }, [201] = {} } }
    route = plan(dear, { target = 21, bags = function(id) return bags[id] or 0 end,
        options = { materials = "carried" } })
    assert(spells(route) == "2:1-21", "the dear hides kept: " .. spells(route))
    -- One belt's worth left, a yellow belt against a green stone whose chance
    -- is under the floor: the belt goes last, on the one craft the bags
    -- make (the low end, as the cuts let the last craft try for a point).
    local late = { recipes = {
        [1] = recipe(1001, { 1, 10, 40, 60 }, { { 200, 6 } }),
        [2] = recipe(1002, { 1, 1, 5, 25 }, { { 201, 2 } }),
    }, items = { [200] = {}, [201] = {} } }
    local one = { [200] = 6, [201] = 200 }
    route = plan(late, { skill = 20, target = 22, bags = function(id) return one[id] or 0 end,
        options = { materials = "carried" } })
    assert(spells(route) == "2:20-21 1:21-22", "the stone first, the belt last: " .. spells(route))
    route = plan(late, { skill = 20, target = 40, bags = function(id) return one[id] or 0 end,
        options = { materials = "carried" } })
    assert(spells(route) == "2:20-25 1:25-26" and route.target == 26,
        "the belt kept for where the stone is grey, a skill further: " .. spells(route))
    -- Both short: each step asks only what the bags make, and nothing is
    -- owed. Every craft is made whatever the order, so the order is the one
    -- that goes furthest: the two green stones while their chance is
    -- highest, the surer belt after them (its chance falls less for the
    -- point they may add). The stones only try for their point.
    local few = { [200] = 6, [201] = 4 }
    route = plan(late, { skill = 20, target = 40, bags = function(id) return few[id] or 0 end,
        options = { materials = "carried" } })
    assert(spells(route) == "2:20-21 1:21-22", "the stones first, the belt last: " .. spells(route))
    assert(route.runs[1].count == 2 and route.runs[1].high == 2 and route.runs[1].carriedCap, "two stones make two crafts")
    assert(route.runs[2].count == 1, "one belt's worth")
    for _, warning in ipairs(route.warnings) do assert(warning.code ~= "carriedShort", warning.text) end
end

-- A part the route makes from carried materials runs out with them: the
-- hide is cured (60, a part) before the belt is made.
local cured = { recipes = {
    [1] = recipe(300, { 1, 40, 50, 60 }, { { 200, 1 } }),
    [2] = recipe(1002, { 1, 30, 40, 50 }, { { 300, 1 } }),
}, items = carried.items }
route = plan(cured, { target = 30, bags = carriedBags, options = { materials = "carried", get = {} } })
assert(route.ceiling.reason == "materials" and route.target <= 11, "ten hides, at most ten points: " .. route.target)
for _, row in ipairs(route.shopping) do assert(row.itemID ~= 200 or row.buy == 0, "no hides to buy") end

-- Another profession the character has makes materials (Planner:WithHelpers):
-- Mining smelts the bars (400) Blacksmithing needs from ore (401). Its 50 is
-- a starting recipe; 51 asks more Mining than the character has.
local mining = { recipes = {
    [50] = recipe(400, { 1, 25, 48, 70 }, { { 401, 1 } }),
    [51] = recipe(402, { 50, 50, 63, 75 }, { { 403, 1 } }, { learn = "trainer" }),
}, items = { [400] = { sell = 10 }, [401] = { sell = 5 }, [402] = { sell = 35 }, [403] = { sell = 25 } } }
local smithing = { recipes = {
    [1] = recipe(1001, { 1, 10, 15, 20 }, { { 400, 2 } }),
}, items = { [400] = { sell = 10 } } }
local miner = { profession = "Mining", data = mining, skill = 10, known = {} }
local helped = Planner:WithHelpers(smithing, { miner })
assert(helped.recipes[50].helper == "Mining" and not helped.recipes[51], "a recipe past the skill stays out")
assert(helped.items[401] and helped.items[400] == smithing.items[400], "its items join; the data's own rows win")
assert(helped.helpers.Mining[1] == 50 and not smithing.recipes[50] and not mining.recipes[50].helper,
    "the data sets themselves are left as they are")
assert(Planner:WithHelpers(smithing, {}) == smithing, "no helper: the data as it is")
local window = { profession = "Mining", data = mining, skill = 60, known = { [51] = true } }
helped = Planner:WithHelpers(smithing, { window })
assert(helped.recipes[51] and helped.recipes[50], "a read window: what it knows, and the starting recipes")
assert(Planner:MaterialRecipeCount(helped, 401) == 0 and #Planner:MaterialCandidates(helped, "", nil) == 1,
    "the ore is not one of Blacksmithing's materials")
helped = Planner:WithHelpers(smithing, { miner })
-- Only what I have: twenty ore carried, no bars. Without Mining nothing
-- starts; with it the ore is smelted into twenty bars, ten crafts, ten
-- points. The smelting gives Mining skill, not Blacksmithing's, and its
-- step is a Mining craft.
local ore = { [401] = 20 }
local function oreBags(id) return ore[id] or 0 end
route = plan(smithing, { profession = "Blacksmithing", target = 20, bags = oreBags, options = { materials = "carried" } })
assert(#route.runs == 0, "without Mining the ore is no use")
local smithInput
route, smithInput = plan(helped, { profession = "Blacksmithing", target = 20, bags = oreBags,
    options = { materials = "carried" } })
assert(spells(route) == "1:1-11" and route.ceiling.reason == "materials", spells(route))
assert(not used(route, 50), "Mining's recipe is never a run")
local smelt
for _, event in ipairs(route.events) do if event.kind == "make" then smelt = event end end
assert(smelt and smelt.spell == 50 and smelt.count == 20 and smelt.helper == "Mining" and smelt.gain == nil,
    "twenty bars smelted, no Blacksmithing skill")
for _, row in ipairs(route.shopping) do assert(row.itemID ~= 401 or row.buy == 0, "the ore is all carried") end
local smeltRow
for _, row in ipairs(Planner:Outline(route, smithInput)) do
    if row.kind == "make" and row.item == 400 then smeltRow = row end
end
assert(smeltRow and smeltRow.helper == "Mining", "a Mining make row")
-- With only what is carried, a step's count is what its Make button orders
-- (the low end), and the bars are smelted for exactly that: the rest stays
-- ore until the plan is made again from the skill the crafts leave. Buying,
-- they are smelted for the step's count, which the shopping list covers.
do
    local yellow = { recipes = { [1] = recipe(1001, { 1, 1, 15, 30 }, { { 400, 2 } }) }, items = smithing.items }
    local plenty = { [401] = 100 }
    local function smeltedFor(options)
        local route = plan(Planner:WithHelpers(yellow, { miner }), { profession = "Blacksmithing", target = 16,
            bags = function(id) return plenty[id] or 0 end, options = options })
        local smelted
        for _, event in ipairs(route.events) do if event.kind == "make" then smelted = event end end
        return route.runs[1], smelted
    end
    local run, smelted = smeltedFor({ materials = "carried" })
    assert(run.count == run.low and smelted and smelted.count == 2 * run.count,
        "only what is carried: bars for the low end, " .. tostring(smelted and smelted.count) .. " for " .. run.low)
    run, smelted = smeltedFor({ confidence = "safe" })
    assert(run.low < run.count and smelted and smelted.count == 2 * run.count, "buying: bars for the step's count")
end
-- What Mining brings in is part of the plan's signature.
assert(Planner:Signature({ data = helped }) ~= Planner:Signature({ data = smithing }))

-- Full scope plans a low-level character to 300 when the data allows: the
-- level the input carries is the switch's, not the character's. A toy set
-- (not Data/ProfessionsFull) with one recipe to 300.
local full = { recipes = {
    [1] = recipe(1001, { 1, 295, 298, 300 }, { { 100, 1 } }),
}, items = items() }
local low = Planner:MakeInput("Leatherworking", full, Planner:DefaultInputs(), { skill = 1, level = 12 })
assert(low.level == 12 and not low.fullScope, "off: the real level")
route = Planner:Plan(low)
assert(route.target == 150, "off: as far as level 12 can train (Expert needs 20)")
Tiers:SetFullScope(true)
local wide = Planner:MakeInput("Leatherworking", full, Planner:DefaultInputs(), { skill = 1, level = 12, fullScope = true })
assert(wide.level == 60 and wide.fullScope, "on: planned as level 60")
assert(Planner:Signature(wide) ~= Planner:Signature(low), "the switch is part of the signature")
route = Planner:Plan(wide)
assert(route.target == 300, "on: to 300, got " .. tostring(route.target))
local artisan
for _, event in ipairs(route.events) do
    if event.kind == "train" and event.tier == "Artisan" then artisan = event end
end
assert(artisan and artisan.skill == 225 and artisan.cap == 300, "Artisan trained at 225")
route = plan(chain, { skill = 1, level = 12, fullScope = true })
assert(route.target == 30 and route.ceiling.reason == "recipes", "the data still stops a route")
Tiers:SetFullScope(false)

-- Goals are counted off as they are made, and go once all are made.
do
    local data = { recipes = { [100] = { makes = 500, made = { 1, 1 } }, [200] = { makes = 600, made = { 2, 2 } } } }
    local inputs = Planner:DefaultInputs()
    Planner:AddGoal(inputs, { spell = 100, count = 3 })
    Planner:AddGoal(inputs, { spell = 200, count = 2 })
    local spell, left = Planner:GoalMade(inputs, data, 500, 1)
    assert(spell == 100 and left == 2 and inputs.goals[1].count == 2)
    spell, left = Planner:GoalMade(inputs, data, 600, 2)
    assert(spell == 200 and left == 1, "two made by one craft is one craft")
    spell, left = Planner:GoalMade(inputs, data, 500, 5)
    assert(spell == 100 and left == 0 and #inputs.goals == 1 and inputs.goals[1].spell == 200, "all made: the goal goes")
    assert(Planner:GoalMade(inputs, data, 999, 1) == nil, "no goal makes it")
end

return true
