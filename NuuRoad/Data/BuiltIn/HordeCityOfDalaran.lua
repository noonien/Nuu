local _, ns = ...

-- The Horde quests of the City of Dalaran, a five-player dungeon new in WoW: Forever, from
-- the pickups in the Undercity, Tarren Mill and at the sewer entrance to the last turn-in.
-- No guide addon covers it and no recorded session has been near it, so this is built from
-- quest data and is thinner than Ruins of Lordaeron:
--   * Quest IDs, titles, givers and enders, and what each quest asks for come from
--     Wowhead's Forever database (wowhead.com/forever, quests 96986, 96987 and 96988, read
--     2026-10-03): Melisara (2278) gives and takes The Grave Knight, kill Atrexis the Grave
--     Knight (247126); Doctor Martin Felben (11044) gives and takes Source of Power, 6
--     Cracked Sentry Cores (275997); Rexxie Copperclutch gives and takes Opportunistic
--     Education, The Founding of Dalaran (275996). Wowhead lists no NPC ID for Rexxie, so
--     the guide names him in notes only. Only the facts are taken.
--   * ForeverDungeonJournal (Data/Dungeons.lua, 1.4.3) agrees on all three and adds: the
--     quests are Horde, level 33, and can be taken from level 24; Rexxie stands "near the
--     Dalaran sewer entrance"; Felben's cores come from "the constructs in Dalaran";
--     Atrexis is in the Underbelly. Its map spots, used here: Melisara, Tarren Mill
--     62.6, 20.6 (Hillsbrad); Rexxie and the dungeon entrance both at Alterac Mountains
--     15.0, 66.0. They are that addon's, not a recording's.
--   * Doctor Martin Felben's spot in the Apothecarium is the one the Silverpine guide
--     already uses (46.61, 74.09), which ForeverDungeonJournal matches.
--   * The instance's own name, "City of Dalaran", is the Forever area the client maps the
--     instance to (QuestieDB support/Forever/Zones/instanceIdToAreaId.lua, instance 2959),
--     and the name ForeverDungeonJournal reads from the zone text to know it is inside.
--   * Dalaran is the city on the Alterac Mountains map (1416) where the Skyborne starting
--     zone's zeppelin sets Alliance players down (SkyborneZephrasIsle.lua, 12.30, 56.31).
--     The dungeon is that city's sewers and streets, entered from a sewer entrance; inside,
--     the way runs through the Underbelly to a portal at the end of the pipe, then up into
--     the streets and on to the Violet Citadel. The boss order and where each stands come
--     from ForeverDungeonJournal's notes on the BlizzCon demo, kept to notes.
--
-- All three quests are level 33, above the level 30 cap of the beta as of 2026-10-03; the
-- dungeon runs 28 to 33. They can be taken from level 24.
--
-- Check in client (not in the evidence, so kept to notes or left out):
--   * How a Horde player reaches the sewer entrance: whether the Dalaran city the Alliance
--     zeppelin uses is open, neutral or hostile to the Horde, and whether the entrance is in
--     the streets (a grate, as ForeverDungeonJournal says) or outside the walls.
--   * Rexxie Copperclutch's NPC ID and where he stands; the entrance spot (both 15.0, 66.0
--     here, from ForeverDungeonJournal, never recorded).
--   * Melisara's spot in Tarren Mill.
--   * The zone text inside ("City of Dalaran") that completes the travel step, and the zone
--     text on leaving ("Alterac Mountains").
--   * Which constructs drop the Cracked Sentry Cores, and where The Founding of Dalaran is
--     found (a book? an object? which wing?).
--   * Boss creature IDs other than Atrexis, the boss order, and whether every boss must die
--     on the way to the Violet Citadel.
--   * Whether Opportunistic Education is turned in to Rexxie at the entrance, as the quest
--     data says, or somewhere inside.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1416 Alterac Mountains (guide default), 1458 Undercity, 1424 Hillsbrad Foothills.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-city-of-dalaran-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-city-of-dalaran-quests",
    updated = 1790985600,
    map = 1416,
    only = "Horde",
    meta = {
        title = "City of Dalaran",
        author = "NuuRoad",
        category = "Dungeons/City of Dalaran",
        tags = { "horde", "dungeon", "city of dalaran", "dalaran", "underbelly", "alterac mountains", "tarren mill", "undercity", "forever" },
        levels = { 28, 33 },
        source = "Written from WoW: Forever quest data (Wowhead's Forever database and ForeverDungeonJournal); no recorded run yet.",
    },
    steps = {
        { section = "The Undercity", map = 1458, steps = {
            { note = "City of Dalaran is new in WoW: Forever and no run of it is recorded yet: the way in for the Horde, where the quest items are, and the spots outside the Undercity come from quest data, not from play. Its quests are level 33, above the level cap of 30." },
            { accept = 96988, npc = 11044 },
        } },

        { section = "Tarren Mill", map = 1424, steps = {
            { accept = 96986, npc = 2278,
                note = "Melisara in Tarren Mill. Fly there from the Undercity if you know the flight path. Her spot is not recorded yet." },
        } },

        { section = "Dalaran", steps = {
            { accept = 96987, at = { 15.00, 66.00 },
                note = "Rexxie Copperclutch, by the Dalaran sewer entrance. Dalaran stands north-west of Hillsbrad, on the shore of Lordamere Lake. Neither his spot nor the way in for the Horde is recorded yet." },
            { travel = "the City of Dalaran", zone = "City of Dalaran", at = { 15.00, 66.00 },
                note = "Into the sewers with your group." },
        } },

        { section = "Inside the City of Dalaran", steps = {
            { objective = 96988, part = 1, collect = 275997, count = 6, sticky = true, only = "quest 96988",
                note = "The constructs in Dalaran drop them. Which ones is not recorded yet." },
            { objective = 96986, part = 1, kill = 247126, only = "quest 96986",
                note = "The first boss, at the ritual circle in the Underbelly among necromancers and rising skeletons. He disarms." },
            { note = "Past Atrexis, the portal at the end of the Underbelly pipe leads up into the streets. Arcane Anomaly waits on a round terrace, then Fel Ancient among treants and Unstable Sentinel by the Magus Commerce Exchange; its Malfunction hits everyone within 25 yards." },
            { objective = 96987, part = 1, collect = 275996, only = "quest 96987",
                note = "Somewhere in the city. Where it lies is not recorded yet." },
            { note = "Shade of the Archmage is the last boss, in the Purple Parlor of the Violet Citadel. Keep out of line with the Bounding Mana target, and nobody leaves the room during the fight or he resets." },
            { travel = "the sewer entrance", zone = "Alterac Mountains", at = { 15.00, 66.00 },
                note = "Leave the dungeon." },
        } },

        { section = "Turning in", steps = {
            { turnin = 96987, only = "quest 96987 readyToTurnIn", at = { 15.00, 66.00 },
                note = "Rexxie Copperclutch, by the sewer entrance." },
            { turnin = 96986, npc = 2278, only = "quest 96986 readyToTurnIn",
                note = "Melisara in Tarren Mill." },
            { turnin = 96988, npc = 11044, only = "quest 96988 readyToTurnIn" },
            { finish = "Every Horde quest of the City of Dalaran is done or left for another run." },
        } },
    },
    names = {
        npcs = {
            [2278] = { "Melisara", at = { 62.60, 20.60, map = 1424 } },
            [11044] = { "Doctor Martin Felben", at = { 46.61, 74.09, map = 1458 },
                note = "Doctor Martin Felben in the Apothecarium." },
            [247126] = "Atrexis the Grave Knight",
        },
        quests = {
            [96986] = "The Grave Knight",
            [96987] = "Opportunistic Education",
            [96988] = "Source of Power",
        },
        items = {
            [275996] = "The Founding of Dalaran",
            [275997] = "Cracked Sentry Core",
        },
    },
}
