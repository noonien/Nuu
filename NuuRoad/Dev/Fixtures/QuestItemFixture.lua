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
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:quest-items", updated = 1789862400,
    title = "Fixture: Quest Items", category = "Fixtures/Quest items", author = "NuuRoad",
    tags = { "fixture", "item", "quest", "horde" },
    cond = { faction = "Horde" },
    data = {
        map = 1413,
        sections = {
            { title = "Items that begin a quest", steps = {
                { type = "collect", object = "Chen's Empty Keg", item = 4926, starts = 819, at = { { 5578, 2001 } },
                  note = "The keg spawns on the ground here. Loading the guide with it neither in your bags nor its quest in your log lands on this step." },
                { type = "accept", quests = { 819 },
                  note = "Use the keg to start its quest. Both this step and the one before turn green once the quest is in your log." },
            } },
            { title = "Quest items", steps = {
                { type = "collect", object = "Flawed Power Stones", item = 4986, quest = 924, at = { { 6234, 2003 } },
                  note = "Reads red (not yours to do) unless The Demon Seed is in your log, done once the stone is in your bags or the quest is finished." },
            } },
            { title = "Items to press", steps = {
                { type = "collect", item = 4703, quest = { 746, 1 }, kill = { 2989, 2990 }, use = { 4702 }, at = { { 3127, 4987 } },
                  note = "Counts Broken Tools, presses Prospector's Picks: while a pick is in your bags the item panel offers the pick, never the tools." },
                { type = "finish", note = "Quest item fixture complete." },
            } },
        },
        npcs = {
            [1413] = {
                [2989] = "Bael'dun Digger",
                [2990] = "Bael'dun Appraiser",
            },
        },
    },
})
