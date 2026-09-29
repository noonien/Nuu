local _, ns = ...

-- Guide places fixture: a Mulgore cave described as a small graph, a step
-- placed by a named point past a junction, and the way back out. It checks, in
-- the client:
--   * being led in through an entrance, never through the exit;
--   * leaving by the exit (the hole) when it is shorter;
--   * never walking the one-way drop backwards;
--   * re-routing after taking the other branch at the junction;
--   * holding the route round the loop when both ways are nearly equal;
--   * the indoors check: standing on the hill above the cave is outside.
--
-- Only the south mouth (59.67, 83.33) comes from a guide (HordeMulgore16's
-- "Bristleback cave" step). The inside is a sketch to be replaced by walking
-- it with the editor's Places panel (Record), which is the point of the
-- fixture as much as the arrow is.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:cave-place"] = {
    schema = 2, id = "nuuroad:fixture:cave-place", updated = 1790121600, map = 1412,
    meta = { title = "Fixture: Cave place", author = "NuuRoad", category = "Fixtures/Travel", tags = { "fixture", "travel", "places" } },
    places = {
        { place = "bristleback", name = "Bristleback cave", width = 15,
          points = {
              { at = { 59.67, 83.33 }, kind = "entrance", label = "the south mouth" }, -- 1
              { at = { 61.40, 81.60 }, kind = "entrance", label = "the camp mouth" },  -- 2
              { at = { 60.10, 82.80 }, label = "the fork" },                           -- 3
              { at = { 60.70, 82.20 } },                                               -- 4
              { at = { 60.30, 82.20 }, label = "the ledge" },                          -- 5
              { at = { 60.60, 82.90 }, id = "den" },                                   -- 6
              { at = { 60.90, 83.40 }, kind = "exit", label = "the hole" },            -- 7
          },
          connections = { { 1, 3 }, { 3, 4 }, { 4, 2 }, { 3, 5 }, { 5, 6, true }, { 4, 6 }, { 3, 6 }, { 6, 7 } },
        },
    },
    steps = {
        { section = "Into the cave", steps = {
            { travel = "the den", label = "den", at = "bristleback.den",
                note = "The arrow should lead in through a mouth, never up the hole, and follow the passage you take at the fork." },
            { travel = "the ledge", label = "ledge", at = "bristleback.5",
                note = "From the den the drop cannot be climbed: the arrow goes round by the fork." },
            { travel = "the camp", label = "camp", at = { 62.35, 81.27 },
                note = "Back out: through the camp mouth, or down the hole if that is shorter." },
            { finish = "Cave fixture complete." },
        } },
    },
}
