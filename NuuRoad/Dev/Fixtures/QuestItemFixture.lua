local _, ns = ...

-- Fixture for collect steps tied to a quest: an item on the ground that begins
-- a quest (Chen's Empty Keg, `starts`), and a quest item picked up for a quest
-- already in the log (the Flawed Power Stone for The Demon Seed, `quest`).
-- The first is never passed over until its quest was accepted; the second
-- reads as moot when the player does not have the quest.
--
-- It also covers `use`: the item the step asks the player to press, which is
-- not always the item the step counts. The Bael'dun step counts Broken Tools
-- and presses Prospector's Picks, so the item panel must offer the pick and
-- not the tools.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:quest-items"] = {
    schema = 2, id = "nuuroad:fixture:quest-items", updated = 1789862400, map = 1413, only = "Horde",
    meta = { title = "Fixture: Quest Items", author = "NuuRoad", category = "Fixtures/Quest items", tags = { "fixture", "item", "quest", "horde" } },
    steps = {
        { section = "Items that begin a quest", steps = {
            { object = "Chen's Empty Keg", collect = 4926, starts = 819, at = { 55.78, 20.01 }, note = "The keg spawns on the ground here. Loading the guide with it neither in your bags nor its quest in your log lands on this step." },
            { accept = 819, note = "Use the keg to start its quest. Both this step and the one before turn green once the quest is in your log." },
        } },

        { section = "Quest items", steps = {
            { object = "Flawed Power Stones", collect = 4986, quest = 924, at = { 62.34, 20.03 }, note = "Reads red (not yours to do) unless The Demon Seed is in your log, done once the stone is in your bags or the quest is finished." },
        } },

        { section = "Items to press", steps = {
            { objective = 746, part = 1, collect = 4703, count = 5, kill = { 2989, 2990 }, use = 4702, at = { 31.27, 49.87 },
                note = "Counts Broken Tools, presses Prospector's Picks: while a pick is in your bags the item panel offers the pick, never the tools." },
            { finish = "Quest item fixture complete." },
        } },
    },
}
