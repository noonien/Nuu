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
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:cave-place", updated = 1790121600,
    title = "Fixture: Cave place", category = "Fixtures/Travel", author = "NuuRoad", tags = { "fixture", "travel", "places" },
    data = {
        map = 1412,
        places = {
            { id = "bristleback", name = "Bristleback cave", width = 15,
              points = {
                  { id = "south", at = { 5967, 8333 }, kind = "entrance", label = "the south mouth" },
                  { id = "camp", at = { 6140, 8160 }, kind = "entrance", label = "the camp mouth" },
                  { id = "fork", at = { 6010, 8280 }, label = "the fork" },
                  { id = "bend", at = { 6070, 8220 } },
                  { id = "ledge", at = { 6030, 8220 }, label = "the ledge" },
                  { id = "den", at = { 6060, 8290 } },
                  { id = "hole", at = { 6090, 8340 }, kind = "exit", label = "the hole" },
              },
              links = {
                  { from = "south", to = "fork" }, { from = "fork", to = "bend" }, { from = "bend", to = "camp" },
                  { from = "fork", to = "ledge" }, { from = "ledge", to = "den", oneway = true },
                  { from = "bend", to = "den" }, { from = "fork", to = "den" }, { from = "den", to = "hole" },
              },
            },
        },
        sections = {
            { title = "Into the cave", steps = {
                { type = "travel", to = "the den", label = "den", stand = "bristleback.den",
                  note = "The arrow should lead in through a mouth, never up the hole, and follow the passage you take at the fork." },
                { type = "travel", to = "the ledge", label = "ledge", stand = "bristleback.ledge",
                  note = "From the den the drop cannot be climbed: the arrow goes round by the fork." },
                { type = "travel", to = "the camp", label = "camp", at = { { 6235, 8127 } },
                  note = "Back out: through the camp mouth, or down the hole if that is shorter." },
                { type = "finish", note = "Cave fixture complete." },
            } },
        },
    },
})
