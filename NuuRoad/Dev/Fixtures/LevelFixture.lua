local _, ns = ...

-- Fixture for a level step that counts the turn-ins ahead of it (`by`): the
-- grind line reads the experience and kills still owed after the Crossroads
-- turn-ins between it and the step it names, and says how many turn-ins it
-- could not price yet. Take the three quests first so the client can price
-- them from the log; a quest's offer or turn-in teaches its experience for
-- every character on the account.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:level-by"] = {
    schema = 2, id = "nuuroad:fixture:level-by", updated = 1790380800, map = 1413, only = "Horde",
    meta = { title = "Fixture: Level By Step", author = "NuuRoad", category = "Fixtures/Levels", tags = { "fixture", "level", "horde" } },
    steps = {
        { section = "Crossroads", steps = {
            { group = {
                { accept = 870, npc = 3448 },
                { accept = 869, npc = 3464 },
                { accept = 871, npc = 3429 },
            } },
            { level = 14, by = "done", at = { 48.0, 13.2 }, radius = 0.06,
                note = "The line counts the three turn-ins below as experience on the way, so it asks only for what they will not bring. Hand one in early and the figure grows by what it gave." },
            { turnin = 870, npc = 3448 },
            { turnin = 869, npc = 3464 },
            { turnin = 871, npc = 3429 },
            { finish = "Level fixture complete.", label = "done" },
        } },
    },
    names = {
        npcs = {
            [3429] = { "Thork", at = { 51.50, 30.87 } },
            [3448] = { "Tonga Runetotem", at = { 52.26, 31.93 } },
            [3464] = { "Gazrog", at = { 51.93, 30.32 } },
        },
        quests = {
            [869] = "Raptor Thieves",
            [870] = "The Forgotten Pools",
            [871] = "Disrupt the Attacks",
        },
    },
}
