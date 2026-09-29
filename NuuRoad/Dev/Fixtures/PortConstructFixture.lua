local _, ns = ...

-- Fixture for guide constructs shared with other addon guide formats: a step
-- carried alongside a later one, a sticky step, a circuit the arrow cycles, a
-- vendor stop, a rare to watch for, a wait, and arrival judged by zone name
-- rather than by coordinate. The realm answers in Options gate the last three
-- steps; leave them unanswered and all three stay visible, which is what
-- unknown is meant to do.
--
-- What to look for in the tracker: steps 1 and 3 never become the current
-- step. They are drawn on the card under it, and tick off when the step that
-- carries them does. The sticky step stays on that card until you mark it.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:port-constructs"] = {
    schema = 2, id = "nuuroad:fixture:port-constructs", updated = 1789862400, map = 1412,
    meta = { title = "Fixture: Ported Constructs", author = "NuuRoad", category = "Fixtures/Ported constructs",
        tags = { "fixture", "carried", "loop", "vendor" } },
    steps = {
        { section = "Carried steps", steps = {
            { travel = "Through the cave", with = "next", at = { 59.67, 83.33 },
                note = "Carried with the step after it: never the current step, done when that one is." },
            { objective = 757, part = 1, collect = 4770, count = 12, loop = true, radius = 0.06,
                at = { { 63.93, 78.34 }, { 63.81, 76.65 }, { 62.92, 76.91 }, { 61.31, 77.22 } },
                note = "Several points: the arrow takes whichever is nearest, not the first." },
            { note = "Keep an eye out for Ghost Howl.", sticky = true, watch = 3056,
                at = { 52.00, 45.00 },
                note = "Sticky: stays on the card under every step from here until you mark it done." },
            { travel = "Camp Narache", with = "turnin", at = { 46.00, 78.00 },
                note = "Carried with a labelled step further on, not just the next one." },
        } },

        { section = "Arrival, vendors and waits", steps = {
            { vendor = "sell", npc = 3072, at = { 45.30, 76.52 } },
            { vendor = "repair", npc = 3080, at = { 45.90, 58.73 } },
            { turnin = 757, npc = 2981, label = "turnin", wait = 8, at = { 44.18, 76.07 },
                note = "The wait is shown, never enforced: Chief Hawkwind plays out a scene first." },
            { travel = "Bloodhoof Village", subzone = "Bloodhoof Village", at = { 47.35, 60.70 },
                note = "Done when the client names the subzone, not when a coordinate is reached." },
            { travel = "The Barrens", zone = "The Barrens", at = { 69.60, 60.40 },
                note = "The same, by zone." },
        } },

        { section = "The realm answers", steps = {
            { note = "Shown on a normal-rate realm. Set the rate in Options to 2 and this goes away.",
                only = "xprate < 1.5" },
            { note = "Shown once you say you use the auction house.", only = "auctionhouse" },
            { note = "Shown once you say you are playing self found.", only = "selffound" },
            { finish = "Ported construct fixture complete." },
        } },
    },
}
