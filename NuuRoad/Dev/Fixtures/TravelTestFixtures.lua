local _, ns = ...

-- The step guides of the travel tests (`/nuuroad traveltest`,
-- Dev/TravelTestPanel.lua). Each test that runs with a guide loads one of
-- these; the test panel finds its steps by label. They are ordinary travel
-- steps, so they also check that a real guide step is routed the way a typed-in
-- waypoint is. Coordinates are the ones the planner's data and the packaged
-- guides already use; see Data/Travel.lua.
ns.packagedGuides = ns.packagedGuides or {}

local function fixture(id, title, map, sections, npcs)
    table.insert(ns.packagedGuides, {
        kind = "guide", schema = 1, id = id, updated = 1790208000,
        title = title, category = "Fixtures/Travel tests", author = "NuuRoad", tags = { "fixture", "travel" },
        data = { map = map, sections = sections, npcs = npcs },
    })
end

fixture("nuuroad:fixture:travel-flight", "Fixture: Travel test, flight", 1454, {
    { title = "Fly to the Crossroads", steps = {
        { type = "travel", to = "the Crossroads", label = "crossroads", at = { { 5150, 3030, map = 1413 } }, radius = 100,
          note = "Start at the Orgrimmar flight master. The route should be the flight, with walking on offer." },
        { type = "finish", note = "Flight test complete." },
    } },
})

fixture("nuuroad:fixture:travel-zeppelin", "Fixture: Travel test, zeppelin", 1411, {
    { title = "To Brill and back", steps = {
        { type = "travel", to = "Brill", label = "brill", at = { { 6100, 5200, map = 1420 } }, radius = 100,
          note = "Start outside Orgrimmar's front gate. Take the zeppelin to the Undercity." },
        { type = "travel", to = "the Orgrimmar flight master", label = "back", at = { { 4510, 6390, map = 1454 } }, radius = 100,
          note = "Take the zeppelin back to Orgrimmar and walk in by the front gate." },
        { type = "finish", note = "Zeppelin test complete." },
    } },
})

fixture("nuuroad:fixture:travel-hearth", "Fixture: Travel test, hearthstone", 1413, {
    { title = "Hearth", steps = {
        { type = "hearth", area = 380, label = "bind", npc = { 3934 } },
        { type = "travel", to = "Orgrimmar", label = "away", at = { { 4510, 6390, map = 1454 } }, radius = 100,
          note = "Fly to Orgrimmar from the Crossroads flight master." },
        { type = "travel", to = "the Crossroads", label = "home", at = { { 5200, 3100 } }, radius = 100,
          note = "The route should be the flight, with the hearth on offer." },
        { type = "travel", to = "the Thunder Bluff inn", label = "far", at = { { 4581, 6471, map = 1456 } }, radius = 100,
          note = "With the hearth on cooldown, nothing should offer it." },
        { type = "finish", note = "Hearthstone test complete." },
    } },
}, { [1413] = { [3934] = { name = "Innkeeper Boorand Plainswind", at = { 5199, 2990 } } } })

fixture("nuuroad:fixture:travel-other-flight", "Fixture: Travel test, another flight", 1413, {
    { title = "Fly somewhere else", steps = {
        { type = "travel", to = "Camp Taurajo", label = "taurajo", at = { { 4445, 5915 } }, radius = 100,
          note = "At the Crossroads flight master, fly to Thunder Bluff instead of Camp Taurajo." },
        { type = "finish", note = "Test complete." },
    } },
})

fixture("nuuroad:fixture:travel-lifts", "Fixture: Travel test, Thunder Bluff lifts", 1456, {
    { title = "Down and up", steps = {
        { type = "travel", to = "Bloodhoof Village", label = "down", at = { { 4660, 6110, map = 1412 } }, radius = 100,
          note = "Start inside Thunder Bluff. Take a lift down." },
        { type = "travel", to = "the Thunder Bluff inn", label = "up", at = { { 4581, 6471 } }, radius = 100,
          note = "From Mulgore, take a lift back up." },
        { type = "finish", note = "Lift test complete." },
    } },
})
