local _, ns = ...

-- Fixture for guide constructs shared with other addon guide formats: a step
-- carried alongside a later one, a sticky step, a circuit the arrow cycles, a
-- vendor stop, a wait, and arrival judged by area or zone rather than by
-- coordinate. The realm answers in Options gate the last two steps; leave
-- them unanswered and both stay visible, which is what unknown is meant to
-- do.
--
-- What to look for in the tracker: steps 1 and 4 never become the current
-- step. They are drawn on the card under it, and tick off when the step that
-- carries them does. The sticky step stays on that card until you mark it.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:port-constructs", updated = 1789862400,
    title = "Fixture: Ported Constructs", category = "Fixtures/Ported constructs", author = "NuuRoad",
    tags = { "fixture", "carried", "loop", "vendor" },
    data = {
        map = 1412,
        sections = {
            { title = "Carried steps", steps = {
                { type = "travel", to = "Through the cave", with = "belts", at = { { 5967, 8333 } },
                  note = "Carried with the step after it: never the current step, done when that one is." },
                { type = "collect", item = 4770, quest = { 757, 1 }, label = "belts", loop = true, radius = 600,
                  at = { { 6393, 7834 }, { 6381, 7665 }, { 6292, 7691 }, { 6131, 7722 } },
                  note = "Several points: the arrow takes whichever is nearest, not the first." },
                { type = "note", sticky = true, at = { { 5200, 4500 } },
                  note = "Keep an eye out for Ghost Howl. Sticky: stays on the card under every step from here until you mark it done." },
                { type = "travel", to = "Camp Narache", with = "turnin", at = { { 4600, 7800 } },
                  note = "Carried with a labelled step further on, not just the next one." },
            } },
            { title = "Arrival, vendors and waits", steps = {
                { type = "vendor", sell = true, npc = { 3072 } },
                { type = "vendor", repair = true, npc = { 3080 } },
                { type = "turnin", quests = { 757 }, npc = { 2981 }, label = "turnin", wait = 8,
                  note = "The wait is shown, never enforced: Chief Hawkwind plays out a scene first." },
                { type = "travel", to = "Bloodhoof Village", area = 222, at = { { 4735, 6070 } },
                  note = "Done when the client names the area, not when a coordinate is reached." },
                { type = "travel", to = "The Barrens", zone = 1413, at = { { 6960, 6040 } },
                  note = "The same, by zone." },
            } },
            { title = "The realm answers", steps = {
                { type = "note", note = "Shown once you say you use the auction house.", show = { ah = true } },
                { type = "note", note = "Shown once you say you are playing self found.", show = { selffound = true } },
                { type = "finish", note = "Ported construct fixture complete." },
            } },
        },
        npcs = {
            [1412] = {
                [2981] = { name = "Chief Hawkwind", at = { 4418, 7607 } },
                [3072] = { name = "Kawnie Softbreeze", at = { 4530, 7652 } },
                [3080] = { name = "Harant Ironbrace", at = { 4590, 5873 } },
            },
        },
    },
})
