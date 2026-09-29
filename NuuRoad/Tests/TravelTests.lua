_G = _G or _ENV
local ns = { modules = {} }
function ns:RegisterModule(name, module) self.modules[name] = module end
ns.Kit = ns.Kit or LoadKit()

Load(ns, "Domain/Travel.lua")
local Travel = ns.modules.Travel

-- A small world in the client's conventions: world X grows north and Y grows
-- west, in yards. Map 100 is a 2000-yard zone on continent 1, map 200 a city
-- inside it (the zone's 40-50% square), map 300 a zone on continent 2.
local maps = {
    [100] = { continent = 1, left = 0, top = 0, size = 2000 },
    [200] = { continent = 1, left = 800, top = 800, size = 200 },
    [300] = { continent = 2, left = 0, top = 0, size = 2000 },
}
local function world(map, x, y)
    local m = maps[map]
    if not m then return nil end
    return m.continent, -(m.top + y * m.size), -(m.left + x * m.size)
end

local function at(map, x, y) return { map = map, x = x / 100, y = y / 100 } end

local function context(extra)
    local known = extra.known or {}
    local base = {
        world = world, faction = "Horde",
        data = extra.data or { flights = {}, links = {}, teleports = {}, inns = {}, areas = {} },
        knownFlight = function(name) return known[Travel.FlightKey(name)] == true end,
    }
    for key, value in pairs(extra) do if key ~= "known" then base[key] = value end end
    return base
end

-- A plan that is one straight walk: one waypoint, the target.
local function direct(plan) return plan ~= nil and plan.direct and #plan.legs == 1 and plan.legs[1].final end

local function choiceIds(plan)
    local list = {}
    for _, choice in ipairs(plan.choices) do table.insert(list, choice.id) end
    return table.concat(list, " ")
end

local function keys(plan)
    local list = {}
    for _, leg in ipairs(plan.legs) do table.insert(list, leg.key) end
    return table.concat(list, " ")
end

assert(Travel.FlightKey("Crossroads, The Barrens") == "crossroads")
assert(Travel.FlightKey("The Crossroads") == "crossroads")
assert(Travel.FormatSeconds(130) == "2m10s" and Travel.FormatSeconds(45) == "45s" and Travel.FormatSeconds(360) == "6m")

-- Flights ---------------------------------------------------------------------

local flights = {
    { name = "Alpha, Zone", map = 100, at = { 5, 5 }, faction = "Horde" },
    { name = "Bravo, Zone", map = 100, at = { 90, 90 }, faction = "Horde" },
    { name = "Charlie, Zone", map = 100, at = { 90, 5 }, faction = "Alliance" },
    { name = "Delta, Zone", map = 100, at = { 50, 90 }, faction = "Neutral" },
}
local data = { flights = flights, links = {}, teleports = {}, inns = {}, areas = {} }

-- Walking wins when close.
local plan = Travel:Plan(at(100, 10, 10), at(100, 12, 10), context({ data = data, known = { alpha = true, bravo = true } }))
assert(direct(plan) and plan.summary:match("^walk %(~"), "a short walk is one waypoint")
assert(choiceIds(plan) == "default", "and there is nothing else to pick")

-- A known flight wins when far.
plan = Travel:Plan(at(100, 6, 6), at(100, 89, 89), context({ data = data, known = { alpha = true, bravo = true } }))
assert(plan and plan.legs[1].kind == "flight" and plan.legs[1].text == "Fly to Bravo", "a far target is flown to")
assert(plan.legs[2].final, "the last leg walks to the target")
assert(plan.summary:match("^fly Bravo > walk %(~") and plan.summary:match("walking ~"), plan.summary)
assert(choiceIds(plan) == "default walk" and plan.choices[2].outline == "walk", "walking is on offer instead")
plan = Travel:Plan(at(100, 6, 6), at(100, 89, 89), context({ data = data, known = { alpha = true, bravo = true }, choice = "walk" }))
assert(direct(plan) and plan.choice == "walk", "and taken when picked")

-- An unknown flight is ignored.
plan = Travel:Plan(at(100, 6, 6), at(100, 89, 89), context({ data = data, known = { alpha = true } }))
assert(direct(plan), "a flight the player has not learned is no route")

-- The wrong faction is ignored; a neutral one is used.
plan = Travel:Plan(at(100, 6, 6), at(100, 89, 6), context({ data = data, known = { alpha = true, charlie = true } }))
assert(direct(plan), "an Alliance flight master is no route for the Horde")
plan = Travel:Plan(at(100, 6, 6), at(100, 50, 89), context({ data = data, known = { alpha = true, delta = true } }))
assert(plan and plan.legs[1].text == "Fly to Delta", "a neutral flight master serves both factions")

-- A step with several spots arrives at the one quickest to reach: from
-- Alpha, a far spot beside Bravo beats walking to the one nearest in a line.
local spread = at(100, 5, 70)
spread.spots = { { x = 0.88, y = 0.88 }, { x = 0.05, y = 0.70 } }
plan = Travel:Plan(at(100, 6, 6), spread, context({ data = data, known = { alpha = true, bravo = true } }))
assert(plan and plan.legs[1].text == "Fly to Bravo" and #plan.legs == 2, keys(plan))
assert(plan.legs[2].final and plan.legs[2].key == "spot:1", "the last waypoint is the spot flown to")
plan = Travel:Plan(at(100, 6, 6), at(100, 5, 70), context({ data = data, known = { alpha = true, bravo = true } }))
assert(direct(plan), "without the far spot it is a walk")

-- The mode change penalty: flying saves 20 s of a 100 s walk only before the
-- two changes of mode are counted. 593 yards is about 100 s of walking.
local penaltyData = { flights = {
    { name = "Near", map = 100, at = { 10, 10 } }, { name = "Far", map = 100, at = { 10, 39.15 } },
}, links = {}, teleports = {}, inns = {}, areas = {} }
local function penaltyPlan(seconds)
    return Travel:Plan(at(100, 10, 10), at(100, 10, 39.65), context({ data = penaltyData, known = { near = true, far = true },
        flightTimes = { ["near>far"] = { seconds } }, suggestSeconds = 0, suggestShare = 0 }))
end
assert(direct(penaltyPlan(80)), "a route that adds two legs to save 20 s is not worth it")
assert(penaltyPlan(40) and penaltyPlan(40).legs[1].kind == "flight", "one that saves a minute is")

-- Chained flights collapse into one leg; a saved reachable list overrides
-- the assumption that any two known masters connect.
local chain = { flights = {
    { name = "A", map = 100, at = { 5, 5 } }, { name = "B", map = 100, at = { 50, 50 } }, { name = "C", map = 100, at = { 95, 95 } },
}, links = {}, teleports = {}, inns = {}, areas = {} }
plan = Travel:Plan(at(100, 5, 5), at(100, 95, 95), context({ data = chain, known = { a = true, b = true, c = true },
    reachable = { a = { "B" } } }))
assert(plan and #plan.legs == 2 and plan.legs[1].text == "Fly to C" and plan.legs[1].fromKey == "a", "A to B to C is one leg")
plan = Travel:Plan(at(100, 5, 5), at(100, 95, 95), context({ data = chain, known = { a = true, b = true, c = true },
    reachable = { a = {}, b = {} } }))
assert(direct(plan), "flight masters that fly nowhere are no route")

-- Measured flight times beat the estimate.
local measured = Travel:Plan(at(100, 6, 6), at(100, 89, 89), context({ data = data, known = { alpha = true, bravo = true },
    flightTimes = { ["alpha>bravo"] = { 200, 30, 40 } } }))
assert(measured and measured.legs[1].cost == 40, "the median of the measured times is used")

-- Hysteresis: a route holds through a small change, and gives way when it
-- becomes impossible or far worse.
local twin = { flights = {
    { name = "West", map = 100, at = { 10, 10 } }, { name = "East", map = 100, at = { 12, 10 } }, { name = "Goal", map = 100, at = { 90, 90 } },
}, links = {}, teleports = {}, inns = {}, areas = {} }
local twinContext = context({ data = twin, known = { west = true, east = true, goal = true } })
local first = Travel:Plan(at(100, 10.5, 10), at(100, 90, 90), twinContext)
assert(first and first.legs[1].fromKey == "west", "the nearer master is used first")
twinContext.previous = first
local second = Travel:Plan(at(100, 11.2, 10), at(100, 90, 90), twinContext)
assert(second and second.legs[1].fromKey == "west", "a few seconds' difference keeps the route shown")
local lost = context({ data = twin, known = { east = true, goal = true }, previous = first })
local third = Travel:Plan(at(100, 11.2, 10), at(100, 90, 90), lost)
assert(third and third.legs[1].fromKey == "east", "a route that is no longer possible is replaced")
local near = context({ data = twin, known = { west = true, east = true, goal = true }, previous = first })
local fourth = Travel:Plan(at(100, 89, 89), at(100, 90, 90), near)
assert(direct(fourth), "a route far worse than walking gives way to walking")

-- Teleports ---------------------------------------------------------------------

local hearthData = { flights = {}, links = {}, areas = {},
    teleports = { { item = 6948, spell = 8690, to = "bind", cast = 10, label = "Hearth" } },
    inns = { { name = "The Inn", map = 100, at = { 90, 90 } } } }
local function hearthPlan(cooldown, bind, choice, extra)
    local c = context({ data = extra or hearthData, bind = bind or "The Inn", choice = choice,
        teleport = function() return cooldown end })
    return Travel:Plan(at(100, 5, 5), at(100, 89, 90), c)
end
plan = hearthPlan(0)
assert(direct(plan), "a ready hearth is never the route shown by default")
assert(choiceIds(plan) == "default teleport:1" and plan.choices[2].outline == "hearth > walk", choiceIds(plan))
plan = hearthPlan(0, nil, "teleport:1")
assert(plan and plan.choice == "teleport:1" and plan.legs[1].kind == "teleport" and plan.legs[1].text == "Hearth to The Inn",
    "it is taken when picked")
assert(plan.legs[1].spell == 8690 and plan.legs[1].item == 6948)
assert(plan.choices[1].id == "default" and plan.choices[1].outline == "walk", "the default is still on offer")
plan = hearthPlan(120, nil, "teleport:1")
assert(direct(plan) and choiceIds(plan) == "default", "a hearth on cooldown is not offered, even when it was picked")
assert(choiceIds(hearthPlan(nil)) == "default", "no hearthstone, no hearth")
assert(choiceIds(hearthPlan(0, "Somewhere Else")) == "default", "an inn not in the list has no edge")
plan = Travel:Plan(at(100, 80, 80), at(100, 89, 90), context({ data = hearthData, bind = "The Inn", teleport = function() return 0 end }))
assert(choiceIds(plan) == "default", "a hearth that saves little is not offered")
plan = Travel:Plan(at(100, 80, 80), at(100, 89, 90), context({ data = hearthData, bind = "The Inn", choice = "teleport:1",
    teleport = function() return 0 end }))
assert(plan and plan.choice == "teleport:1", "unless the player picked it: a pick does not lapse")

-- A free teleport (no cooldown worth saving) is the route by default, with
-- walking on offer.
local freeData = { flights = {}, links = {}, areas = {}, inns = {},
    teleports = { { spell = 18960, to = { map = 100, at = { 90, 90 } }, cast = 10, label = "Teleport: Moonglade", free = true } } }
plan = Travel:Plan(at(100, 5, 5), at(100, 89, 90), context({ data = freeData, teleport = function() return 0 end }))
assert(plan and plan.choice == "default" and plan.legs[1].kind == "teleport" and plan.legs[1].text == "Teleport: Moonglade",
    "a free teleport is simply the way: " .. keys(plan))
assert(choiceIds(plan) == "default walk", choiceIds(plan))
assert(#Travel.ValidateData(freeData) == 0 or not table.concat(Travel.ValidateData(freeData), " "):match("free"))

-- With a flight and a hearth both faster than walking: the flight is the
-- default, the hearth the alternative, then walking.
local both = { links = {}, areas = {}, teleports = hearthData.teleports, inns = hearthData.inns,
    flights = { { name = "Alpha", map = 100, at = { 5, 5 } }, { name = "Bravo", map = 100, at = { 80, 80 } } } }
local bothContext = context({ data = both, known = { alpha = true, bravo = true }, bind = "The Inn",
    teleport = function() return 0 end })
plan = Travel:Plan(at(100, 5, 5), at(100, 89, 90), bothContext)
assert(plan and plan.legs[1].kind == "flight" and choiceIds(plan) == "default teleport:1 walk", choiceIds(plan))
bothContext.choice, bothContext.previous = "teleport:1", plan
plan = Travel:Plan(at(100, 5, 5), at(100, 89, 90), bothContext)
assert(plan and plan.legs[1].kind == "teleport", "a pick is not held back by the route shown before it")

-- Links: another continent is reached by boat.
local boatData = { flights = {}, teleports = {}, inns = {}, areas = {}, links = {
    { kind = "boat", wait = 60, ride = 60, both = true,
      from = { map = 100, at = { 90, 10 }, name = "Portside" }, to = { map = 300, at = { 10, 10 }, name = "Farport" } },
} }
plan = Travel:Plan(at(100, 80, 10), at(300, 20, 10), context({ data = boatData }))
assert(plan and plan.legs[1].kind == "link" and plan.legs[1].text == "Take the boat to Farport", "the boat crosses")
plan = Travel:Plan(at(300, 20, 10), at(100, 80, 10), context({ data = boatData }))
assert(plan and plan.legs[1].text == "Take the boat to Portside", "a two-way link rides back")
local _, why = Travel:Plan(at(100, 80, 10), at(300, 20, 10), context({ data = boatData, options = { links = false } }))
assert(why == "unreachable", "without transports another continent is out of reach")

-- Areas ---------------------------------------------------------------------------

local city = { flights = {}, links = {}, teleports = {}, inns = {}, areas = {
    { name = "City", map = 200, doors = {
        { at = { 50, 100 }, label = "the south gate" },
        { at = { 0, 50 }, label = "the west gate" },
        { at = { 100, 50 }, label = "the east drop", kind = "exit" },
    } },
} }
plan = Travel:Plan(at(200, 10, 50), at(100, 30, 45), context({ data = city }))
assert(plan and plan.legs[1].text == "Leave City by the west gate", "the nearest door out is taken")
plan = Travel:Plan(at(200, 90, 50), at(100, 55, 45), context({ data = city }))
assert(plan and plan.legs[1].text == "Leave City by the east drop", "an exit is used outwards")
plan = Travel:Plan(at(100, 55, 45), at(200, 90, 50), context({ data = city }))
assert(plan and plan.legs[1].key ~= "door:1:3", "an exit is never used inwards")
assert(plan.legs[1].text:match("^Enter City by the"), plan.legs[1].text)

-- A point authored on the zone map inside the city is inside it when the
-- client says the city's map lies there.
local function cityAt(map, x, y)
    if map == 100 and x >= 0.4 and x <= 0.5 and y >= 0.4 and y <= 0.5 then return 200 end
    return map
end
plan = Travel:Plan(at(100, 30, 45), at(100, 45, 45), context({ data = city, mapAt = cityAt }))
assert(plan and plan.legs[1].text == "Enter City by the west gate", "a zone point in the city is entered by a gate")
plan = Travel:Plan(at(100, 30, 48), at(100, 45, 42), context({ data = city }))
assert(direct(plan), "without the client's answer the zone map point counts as outside")
plan = Travel:Plan(at(100, 45, 49), at(100, 30, 45), context({ data = city, mapAt = cityAt }))
assert(direct(plan), "the player is where the client's own map says, not where its city area reaches")

-- A lift: the city (map 200) stands on a mesa whose foot is on the city's
-- own map too. The lift's top is the door; its bottom is outside, fourteen
-- yards south on the same map.
local mesa = { flights = {}, links = {}, teleports = {}, inns = {}, areas = {
    { name = "Mesa", map = 200, doors = {
        { at = { 50, 90 }, bottom = { at = { 50, 97 } }, wait = 15, label = "the south lift" },
    } },
} }
plan = Travel:Plan(at(100, 45, 70), at(200, 50, 50), context({ data = mesa }))
assert(plan and plan.legs[1].text == "Take the south lift up" and plan.legs[2].text == "Ride the south lift up",
    "up the mesa by its lift: " .. keys(plan))
plan = Travel:Plan(at(200, 50, 50), at(100, 45, 70), context({ data = mesa }))
assert(plan and plan.legs[1].text == "Take the south lift down" and plan.legs[2].text == "Ride the south lift down",
    "down the mesa by its lift: " .. keys(plan))
plan = Travel:Plan(at(200, 50, 98), at(200, 50, 50), context({ data = mesa }))
assert(direct(plan), "without being told, the foot of the mesa is on the city's map and so counts as on top")
plan = Travel:Plan(at(200, 50, 98), at(200, 50, 50), context({ data = mesa, below = { Mesa = true } }))
assert(plan and plan.legs[1].text == "Ride the south lift up", "standing at the foot, the lift is ridden up: " .. keys(plan))
plan = Travel:Plan(at(200, 45, 99), at(100, 45, 70), context({ data = mesa, below = { Mesa = true } }))
assert(direct(plan), "at the foot, the plain below is a straight walk")
plan = Travel:Plan(at(200, 20, 50), at(100, 45, 70), context({ data = mesa }))
assert(plan and not keys(plan):match("^lift"), "the top of a lift is never walked to from below: " .. keys(plan))
local liftProblems = Travel.ValidateData({ areas = { { name = "Mesa", map = 1456, doors = {
    { at = { 30, 62 }, bottom = { at = { 31.8, 66 } }, wait = 15 },
    { at = { 60, 23 }, bottom = { 1, 2 } },
} } } })
assert(#liftProblems == 1 and liftProblems[1]:match("doors%[2%]%.bottom"), table.concat(liftProblems, "; "))

local nested = { flights = {}, links = {}, teleports = {}, inns = {}, areas = {
    { name = "Outer", map = 100, at = { 20, 20 }, radius = 200, doors = { { at = { 20, 30 }, label = "the outer gate" } } },
    { name = "Inner", map = 100, at = { 20, 20 }, radius = 60, doors = { { at = { 20, 23 }, label = "the inner gate" } } },
} }
plan = Travel:Plan(at(100, 20, 20), at(100, 50, 20), context({ data = nested }))
assert(plan and plan.legs[1].key == "door:2:1" and plan.legs[2].key == "door:1:1", "nested areas pass both doors")
assert(plan.legs[1].text == "Leave Inner by the inner gate" and plan.legs[2].text == "Leave Outer by the outer gate")

local walledFlight = { links = {}, teleports = {}, inns = {}, areas = city.areas, flights = {
    { name = "Town", map = 200, at = { 50, 50 } }, { name = "Field", map = 100, at = { 95, 95 } },
} }
plan = Travel:Plan(at(100, 95, 95), at(200, 55, 50), context({ data = walledFlight, known = { town = true, field = true } }))
assert(plan and plan.legs[1].text == "Fly to Town" and plan.legs[2].final, "flights ignore walls")

-- Guide places ----------------------------------------------------------------------

-- The cave from TRAVEL.md: two mouths, a junction, a loop, a one-way drop
-- from the ledge into the chamber, and a hole out to the river.
local cave = Travel.ResolvePlaces({
    { place = "windfury", name = "Windfury cave", width = 15, points = {
        { at = { 40.1, 20.3 }, kind = "entrance", label = "the north mouth" },   -- 1
        { at = { 44.8, 22.0 }, kind = "entrance" },                              -- 2
        { at = { 40.3, 22.1 }, label = "the crossroads" },                       -- 3
        { at = { 42.6, 22.1 } },                                                 -- 4
        { at = { 42.7, 23.6 }, label = "the ledge" },                            -- 5
        { at = { 38.6, 22.2 }, label = "the gallery" },                          -- 6
        { at = { 38.5, 24.4 } },                                                 -- 7
        { at = { 40.4, 24.5 }, id = "chamber" },                                 -- 8
        { at = { 40.6, 26.0 }, kind = "exit", label = "the hole to the river" }, -- 9
    }, connections = { { 1, 3 }, { 2, 4 }, { 3, 4 }, { 3, 6 }, { 3, 8 }, { 4, 5 }, { 5, 8, true },
                       { 6, 7 }, { 7, 8 }, { 8, 9 } } },
}, 100)
assert(#cave == 1 and #cave[1].connections == 10 and cave[1].byId.chamber == 8)
local function cavePlan(from, to, extra)
    local c = context(extra or {})
    c.places = cave
    return Travel:Plan(from, to, c)
end
local chamber = at(100, 40.4, 24.5)
chamber.point = "windfury.chamber"

plan = cavePlan(at(100, 40.1, 15), chamber)
assert(plan and plan.legs[1].text == "Enter Windfury cave by the north mouth", "led in through an entrance")
assert(plan.legs[2].text == "Go to the crossroads" and plan.legs[3].final, keys(plan))

plan = cavePlan(at(100, 40.6, 28), chamber)
assert(plan and not keys(plan):match("point:windfury:9"), "never led in through an exit")

plan = cavePlan(at(100, 40.4, 24.5), at(100, 40.6, 30), { indoors = true })
assert(plan and plan.legs[1].key == "point:windfury:9" and plan.legs[1].text == "Leave by the hole to the river",
    "led out by the exit when it is shorter")

local ledge = at(100, 42.7, 23.6)
ledge.point = "windfury.5"
plan = cavePlan(at(100, 40.4, 24.4), ledge, { indoors = true })
assert(plan and not keys(plan):match("^point:windfury:5"), "the drop is never climbed back up")
assert(keys(plan):match("point:windfury:4"), keys(plan))

plan = cavePlan(at(100, 41.5, 22.1), chamber, { indoors = true })
assert(plan and plan.legs[1].key == "point:windfury:3", "entering mid-cave starts from the passage the player is in")

plan = cavePlan(at(100, 40.4, 24.0), chamber, { indoors = false })
assert(plan and plan.legs[1].text:match("^Enter Windfury cave"), "a player above the cave who is not indoors is outside")

-- A step placed near a point joins that point's connections.
local nearChamber = at(100, 40.45, 24.6)
nearChamber.near = "windfury.chamber"
plan = cavePlan(at(100, 40.1, 15), nearChamber)
assert(plan and plan.legs[#plan.legs].final and keys(plan):match("point:windfury:8"), keys(plan))

-- A junction reroutes when the player takes the other branch: walking west
-- towards the gallery, carrying on round the loop beats turning back.
local west = math.pi / 2
plan = cavePlan(at(100, 38.9, 22.2), chamber, { indoors = true, facing = west })
assert(plan and plan.legs[1].key == "point:windfury:6", keys(plan))
local _, attachment = Travel:Locate(at(100, 38.9, 22.2), cave, { world = world })
assert(attachment and attachment.place == "windfury" and attachment.index == 4, "the player is on the crossroads-gallery passage")

-- A loop holds its route when both ways are nearly equal.
local ring = Travel.ResolvePlaces({
    { place = "ring", name = "The ring", points = {
        { at = { 50, 10 }, kind = "entrance" },
        { at = { 50, 12 } }, { at = { 52, 14 } }, { at = { 50, 16 }, id = "far" }, { at = { 48, 14 } },
    }, connections = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 5, 2 } } },
}, 100)
local far = at(100, 50, 16)
far.point = "ring.far"
local viaWest = { choice = "default", path = { { key = "point:ring:5", mode = "walk" }, { key = "point:ring:4", mode = "walk" }, { key = "goal", mode = "walk" } } }
local function ringPlan(t, previous)
    local c = context({ indoors = true, previous = previous })
    c.places = ring
    return Travel:Plan(at(100, 50 + 2 * t, 12 + 2 * t), far, c)
end
plan = ringPlan(0.1, viaWest)
assert(plan and plan.legs[1].key == "point:ring:2" and plan.legs[2].key == "point:ring:5", "a nearly equal way round keeps the route")
plan = ringPlan(0.4, viaWest)
assert(plan and plan.legs[1].key == "point:ring:3", "a clearly shorter way round replaces it")

-- The packaged data validates, and the validator catches the usual slips.
Load(ns, "Data/Travel.lua")
local problems = Travel.ValidateData(ns.travel)
assert(#problems == 0, table.concat(problems, "; "))
problems = Travel.ValidateData({ flights = { { name = "X", map = 99, at = { 150, 20 } }, { name = "The X" } },
    areas = { { name = "Walled", map = 1454, doors = { { at = { 1, 1 }, kind = "window" } } } } })
local joined = table.concat(problems, "; ")
assert(joined:match("flights%[1%]%.map") and joined:match("flights%[1%]%.at") and joined:match("flights%[2%]%.name: repeats")
    and joined:match("kind: must be entrance or exit"), joined)

print("NuuRoad travel tests passed")
