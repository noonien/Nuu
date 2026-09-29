local _, ns = ...

-- Portable arrow fixture: `map = 0` means the player's current map, so the
-- destination is wherever they are standing, whichever zone that is.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:travel-poi"] = {
    schema = 2, id = "nuuroad:fixture:travel-poi", updated = 1789862400, map = 0,
    meta = { title = "Fixture: Travel POI", author = "NuuRoad", category = "Fixtures/Travel", tags = { "fixture", "travel" } },
    steps = {
        { section = "Travel", steps = {
            { travel = "the middle of this map", at = { 50, 50 }, radius = 0.015,
                note = "This fixture verifies the map-local arrow. If the client cannot report a position, the text stands on its own and the step can be passed by hand." },
            { finish = "Travel fixture complete. The arrow should now hide." },
        } },
    },
}
