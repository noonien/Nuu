local _, ns = ...

-- The step guides of the travel tests (`/nuuroad traveltest`,
-- UI/TravelTestPanel.lua). Each test that runs with a guide loads one of
-- these; the test panel finds its steps by label. They are ordinary travel
-- steps, so they also check that a real guide step is routed the way a typed-in
-- waypoint is. Coordinates are the ones the planner's data and the packaged
-- guides already use; see Data/Travel.lua.
ns.builtInGuides = ns.builtInGuides or {}

local function fixture(id, title, map, sections)
    ns.builtInGuides[id] = {
        schema = 2, id = id, updated = 1790208000, map = map,
        meta = { title = title, author = "NuuRoad", category = "Fixtures/Travel tests", tags = { "fixture", "travel" } },
        steps = sections,
    }
end

fixture("nuuroad:fixture:travel-flight", "Fixture: Travel test, flight", 1454, {
    { section = "Fly to the Crossroads", steps = {
        { travel = "the Crossroads", label = "crossroads", at = { 51.5, 30.3, map = 1413 }, radius = 0.01,
            note = "Start at the Orgrimmar flight master. The route should be the flight, with walking on offer." },
        { finish = "Flight test complete." },
    } },
})

fixture("nuuroad:fixture:travel-zeppelin", "Fixture: Travel test, zeppelin", 1411, {
    { section = "To Brill and back", steps = {
        { travel = "Brill", label = "brill", at = { 61, 52, map = 1420 }, radius = 0.01,
            note = "Start outside Orgrimmar's front gate. Take the zeppelin to the Undercity." },
        { travel = "the Orgrimmar flight master", label = "back", at = { 45.1, 63.9, map = 1454 }, radius = 0.01,
            note = "Take the zeppelin back to Orgrimmar and walk in by the front gate." },
        { finish = "Zeppelin test complete." },
    } },
})

fixture("nuuroad:fixture:travel-hearth", "Fixture: Travel test, hearthstone", 1413, {
    { section = "Hearth", steps = {
        { hearth = "The Crossroads", label = "bind", npc = 3934, at = { 51.99, 29.90 } },
        { travel = "Orgrimmar", label = "away", at = { 45.1, 63.9, map = 1454 }, radius = 0.01,
            note = "Fly to Orgrimmar from the Crossroads flight master." },
        { travel = "the Crossroads", label = "home", at = { 52, 31 }, radius = 0.01,
            note = "The route should be the flight, with the hearth on offer." },
        { travel = "the Thunder Bluff inn", label = "far", at = { 45.81, 64.71, map = 1456 }, radius = 0.01,
            note = "With the hearth on cooldown, nothing should offer it." },
        { finish = "Hearthstone test complete." },
    } },
})

fixture("nuuroad:fixture:travel-other-flight", "Fixture: Travel test, another flight", 1413, {
    { section = "Fly somewhere else", steps = {
        { travel = "Camp Taurajo", label = "taurajo", at = { 44.45, 59.15 }, radius = 0.01,
            note = "At the Crossroads flight master, fly to Thunder Bluff instead of Camp Taurajo." },
        { finish = "Test complete." },
    } },
})

fixture("nuuroad:fixture:travel-lifts", "Fixture: Travel test, Thunder Bluff lifts", 1456, {
    { section = "Down and up", steps = {
        { travel = "Bloodhoof Village", label = "down", at = { 46.6, 61.1, map = 1412 }, radius = 0.01,
            note = "Start inside Thunder Bluff. Take a lift down." },
        { travel = "the Thunder Bluff inn", label = "up", at = { 45.81, 64.71 }, radius = 0.01,
            note = "From Mulgore, take a lift back up." },
        { finish = "Lift test complete." },
    } },
})
