local _, ns = ...

-- Fixture for a level step that counts the turn-ins ahead of it (`by`): the
-- grind line reads the experience and kills still owed after the Crossroads
-- turn-ins between it and the step it names, and says how many turn-ins it
-- could not price yet. Take the three quests first so the client can price
-- them from the log; a quest's offer or turn-in teaches its experience for
-- every character on the account.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:level-by", updated = 1790380800,
    title = "Fixture: Level By Step", category = "Fixtures/Levels", author = "NuuRoad",
    tags = { "fixture", "level", "horde" },
    cond = { faction = "Horde" },
    data = {
        map = 1413,
        sections = {
            { title = "Crossroads", steps = {
                { group = {
                    { type = "accept", quests = { 870 }, npc = { 3448 } },
                    { type = "accept", quests = { 869 }, npc = { 3464 } },
                    { type = "accept", quests = { 871 }, npc = { 3429 } },
                } },
                { type = "level", level = 14, by = "done", at = { { 4800, 1320 } }, radius = 600,
                  note = "The line counts the three turn-ins below as experience on the way, so it asks only for what they will not bring. Hand one in early and the figure grows by what it gave." },
                { type = "turnin", quests = { 870 }, npc = { 3448 } },
                { type = "turnin", quests = { 869 }, npc = { 3464 } },
                { type = "turnin", quests = { 871 }, npc = { 3429 } },
                { type = "finish", note = "Level fixture complete.", label = "done" },
            } },
        },
        npcs = {
            [1413] = {
                [3429] = { name = "Thork", at = { 5150, 3087 } },
                [3448] = { name = "Tonga Runetotem", at = { 5226, 3193 } },
                [3464] = { name = "Gazrog", at = { 5193, 3032 } },
            },
        },
    },
})
