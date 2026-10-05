local _, ns = ...

-- Portable arrow fixture: `map = 0` means the player's current map, so the
-- destination is wherever they are standing, whichever zone that is.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide", schema = 1,
    id = "nuuroad:fixture:travel-poi", updated = 1789862400,
    title = "Fixture: Travel POI", category = "Fixtures/Travel", author = "NuuRoad", tags = { "fixture", "travel" },
    data = {
        map = 0,
        sections = {
            { title = "Travel", steps = {
                { type = "travel", to = "the middle of this map", at = { { 5000, 5000 } }, radius = 150,
                  note = "This fixture verifies the map-local arrow. If the client cannot report a position, the text stands on its own and the step can be passed by hand." },
                { type = "finish", note = "Travel fixture complete. The arrow should now hide." },
            } },
        },
    },
})
