-- A packaged guide: a guide source (docs/examples/guide-source.lua).
--
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
--   * That GetInstanceInfo reports instance 2959 inside (the travel step and Atrexis use
--     it), and that the exit lands on the Alterac Mountains map (1416).
--   * Which constructs drop the Cracked Sentry Cores, and where The Founding of Dalaran is
--     found (a book? an object? which wing?).
--   * Boss creature IDs other than Atrexis, the boss order, and whether every boss must die
--     on the way to the Violet Citadel.
--   * Whether Opportunistic Education is turned in to Rexxie at the entrance, as the quest
--     data says, or somewhere inside.
--
-- Maps: 1416 Alterac Mountains (guide default), 1458 Undercity, 1424 Hillsbrad Foothills.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",

    id = "nuuroad:dungeon:horde-city-of-dalaran-quests",
    updated = 1790985600,                -- 2026-10-03
    title = "City of Dalaran",
    category = "Dungeons/City of Dalaran",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "city of dalaran", "dalaran", "underbelly", "alterac mountains", "tarren mill", "undercity", "forever" },
    levels = { from = 28, to = 33 },
    cond = { faction = "Horde" },
    source = "Written from WoW: Forever quest data (Wowhead's Forever database and ForeverDungeonJournal); no recorded run yet.",

    data = {
        map = 1416,

        sections = {
            { title = "The Undercity", map = 1458, steps = {
                { type = "note", note = "City of Dalaran is new in WoW: Forever and no run of it is recorded yet: the way in for the Horde, where the quest items are, and the spots outside the Undercity come from quest data, not from play. Its quests are level 33, above the level cap of 30." },
                { type = "accept", quests = { 96988 }, npc = { 11044 } },
            } },

            { title = "Tarren Mill", map = 1424, steps = {
                { type = "accept", quests = { 96986 }, npc = { 2278 },
                  note = "Fly there from the Undercity if you know the flight path." },
            } },

            { title = "Dalaran", steps = {
                { type = "accept", quests = { 96987 }, at = { { 1500, 6600 } },
                  note = "Rexxie Copperclutch, by the Dalaran sewer entrance. Dalaran stands north-west of Hillsbrad, on the shore of Lordamere Lake. Neither his spot nor the way in for the Horde is recorded yet." },
                { type = "travel", to = "the City of Dalaran", instance = 2959, at = { { 1500, 6600 } },
                  note = "Into the sewers with your group." },
            } },

            { title = "Inside the City of Dalaran", steps = {
                { type = "collect", item = 275997, quest = { 96988, 1 }, sticky = true,
                  note = "The constructs in Dalaran drop them. Which ones is not recorded yet." },
                { type = "kill", kill = { 247126 }, quest = { 96986, 1 },
                  note = "The first boss, at the ritual circle in the Underbelly among necromancers and rising skeletons. He disarms." },
                { type = "note", note = "Past Atrexis, the portal at the end of the Underbelly pipe leads up into the streets. Arcane Anomaly waits on a round terrace, then Fel Ancient among treants and Unstable Sentinel by the Magus Commerce Exchange; its Malfunction hits everyone within 25 yards." },
                { type = "collect", item = 275996, quest = { 96987, 1 },
                  note = "Somewhere in the city. Where it lies is not recorded yet." },
                { type = "note", note = "Shade of the Archmage is the last boss, in the Purple Parlor of the Violet Citadel. Keep out of line with the Bounding Mana target, and nobody leaves the room during the fight or he resets." },
                { type = "travel", to = "the sewer entrance", zone = 1416, at = { { 1500, 6600 } },
                  note = "Leave the dungeon." },
            } },

            { title = "Turning in", steps = {
                { type = "turnin", quests = { 96987 }, optional = true, at = { { 1500, 6600 } },
                  note = "Rexxie Copperclutch, by the sewer entrance." },
                { type = "turnin", quests = { 96986 }, npc = { 2278 }, optional = true },
                { type = "turnin", quests = { 96988 }, npc = { 11044 }, optional = true },
                { type = "finish", note = "Every Horde quest of the City of Dalaran is done or left for another run." },
            } },
        },

        npcs = {
            [1416] = { -- Alterac Mountains
                -- Inside the City of Dalaran, whose sewer entrance is on this map.
                [247126] = { name = "Atrexis the Grave Knight", instance = 2959,
                             note = "The first boss, at the ritual circle in the Underbelly." },
            },
            [1424] = { -- Hillsbrad Foothills
                [2278] = { name = "Melisara", at = { 6260, 2060 },
                           note = "In Tarren Mill. Her spot is not recorded yet." },
            },
            [1458] = { -- Undercity
                [11044] = { name = "Doctor Martin Felben", at = { 4661, 7409 },
                            note = "In the Apothecarium." },
            },
        },
    },
})
