local _, ns = ...

-- Horde 25-26 leveling route through the Stonetalon Mountains: Sun Rock
-- Retreat, the Venture Co. sky port at Windshear Crag, Mirkfallon Lake, the
-- Cenarion grove to the north and the harpies of the Charred Vale. Ported from
-- RestedXP's Classic "25-26 Stonetalon" (RestedXP Horde 20-30.lua). It picks up
-- at the Crossroads, where the Southern Barrens guide ends, and ends at Sun Rock
-- Retreat before Ashenvale. Step order follows the source; quest IDs, NPC IDs,
-- item IDs and coordinates were checked against Questie's Forever database (the
-- db/questie extract) and Wowhead's Forever database, and every NPC stands where
-- Questie puts them.
--
-- The early Stonetalon quests (Sun Rock's Kaya chain, the Deepmoss spiders,
-- Super Reaper 6000, Further Instructions) belong to The Barrens and Stonetalon
-- guide (13-21), which ends here having handed Further Instructions to Ziz
-- Fizziks. This guide only takes the follow-up from him when that is done.
--
-- Forever differences:
--   * Bloodfury Trinkets (86576) is new in Forever: Maggran Earthbinder gives
--     it, with no prerequisite on Wowhead's Forever page, and Mor'rogal takes
--     15 Glittering Sunstones from any Bloodfury harpy. It rides along with
--     Harpies Threaten and is handed in beside Tsunaman at the end.
--   * Pigments for Paints (97538) is new as well, but starts with Tah
--     Winterhoof in Thunder Bluff, off this route. A character who already has
--     it collects the Mirkweed Pods at Mirkfallon Lake with the Gaea Seeds;
--     everyone else never sees the step.
--   * Bloodfury Bloodline's rewards changed in Forever; the quest itself did
--     not.
--
-- Deliberate divergences from the source:
--   * The Flying Machine Airport (1086) is only placed for a character who
--     carries it from Apothecary Zamah, as the source does; it is handed in at
--     Thunder Bluff in the Ashenvale guide.
--   * Gerenzo Wrenchwhistle is only offered once Further Instructions (1095)
--     has been handed in, since Ziz will not give it otherwise.
--   * The source sends the player for Incendrites "as you go" during the first
--     harpy fight and plants the seeds alongside the Ripper; both are kept as
--     tracked quests (`track`) shown alongside those steps.
--   * Ordanus and Calling in the Reserves are accepted here and left for the
--     Ashenvale and Thousand Needles guide.
--
-- Check in client:
--   * Bloodfury Trinkets is offered by Maggran with no prerequisite, and the
--     Glittering Sunstones (277936) drop from every Bloodfury harpy.
--   * Where the Mirkweed for Pigments for Paints grows at Mirkfallon Lake: the
--     pins are the lake's Gaea Seed spots, not the plant's own.
--   * The path up into Sun Rock Retreat from the Charred Vale at 38.70, 68.60
--     (the source's point, not checked against Forever data).
--   * Nizzik's stock at the sky port (the source says he can sell upgrades for
--     every class).
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1442 Stonetalon Mountains (guide default), 1413 The Barrens.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:leveling:horde-stonetalon-25-26"] = {
    schema = 2,
    id = "nuuroad:leveling:horde-stonetalon-25-26",
    updated = 1790985600,
    map = 1442,
    only = "Horde",
    meta = {
        title = "Sun Rock Retreat",
        author = "NuuRoad",
        category = "Leveling/Stonetalon Mountains",
        tags = { "horde", "stonetalon", "sun rock retreat", "charred vale", "windshear crag" },
        levels = { 25, 26 },
    },
    steps = {
        { section = "Sun Rock Retreat", steps = {
            { travel = "Sun Rock Retreat", subzone = "Sun Rock Retreat", at = { 45.13, 59.84 }, radius = 0.04,
                note = "Fly from the Crossroads to Sun Rock Retreat." },
            { flight = "Sun Rock Retreat", npc = 4312,
                note = "Tharm, if you do not have this flight path yet." },
            { group = {
                { accept = 1087, npc = 4198 },
                { accept = 6393, npc = 11862,
                    note = "Tsunaman stands on the lower ledge, south of the camp." },
                { accept = 6301, npc = 11864 },
                { accept = { 5881, 6282, 86576 }, npc = 11860,
                    note = "Calling in the Reserves needs level 23." },
            } },
        } },

        { section = "Windshear Crag", steps = {
            { accept = 1096, npc = 4201, only = "now quest 1095 finished",
                note = "Ziz Fizziks is inside the building at Windshear Crag." },
            { objective = 1086, part = 1, use = 5638, only = "now quest 1086", at = { 66.44, 45.46 },
                note = "Use the Toxic Fogger on the Venture Co. sky port." },
            { objective = 1096, part = 1, collect = 5736, kill = 4202, only = "now quest 1096", radius = 0.03,
                at = { 64.49, 40.25 },
                note = "Gerenzo Wrenchwhistle is at the top of the sky port with his builders around him. Clear them first, then kill him and take his arm." },
            { npc = 4085,
                note = "Nizzik, at the end of the platform, sells armor that changes from time to time. Have a look for an upgrade while you are here." },
            { turnin = 1096, npc = 4201, only = "now quest 1096" },
        } },

        { section = "Mirkfallon Lake and the Cenarion grove", steps = {
            { group = {
                { objective = 6301, part = 1, collect = 16205, count = 10, object = "Gaea Seed", radius = 0.06,
                    at = { { 50.63, 36.56 }, { 48.39, 35.87 }, { 46.69, 37.53 }, { 46.31, 39.60 }, { 48.05, 39.76 },
                           { 50.19, 39.20 }, { 50.96, 41.13 }, { 51.77, 42.62 }, { 49.69, 43.29 }, { 49.74, 45.11 },
                           { 47.99, 44.32 }, { 45.81, 43.11 } },
                    note = "The seeds lie in and around Mirkfallon Lake. Swim across and pick them up on both shores." },
                { objective = 97538, part = 1, collect = 278201, count = 30, object = "Mirkweed", radius = 0.06,
                    only = "now quest 97538",
                    at = { { 50.63, 36.56 }, { 48.39, 35.87 }, { 46.69, 37.53 }, { 50.19, 39.20 }, { 49.69, 43.29 } },
                    note = "Pigments for Paints, from Tah Winterhoof in Thunder Bluff: the Mirkweed grows in the lake." },
            } },
            { group = {
                { objective = 1087, part = 1, kill = 4057, count = 4, radius = 0.05,
                    at = { { 35.84, 13.09 }, { 35.44, 15.28 }, { 38.22, 11.42 }, { 35.90, 10.51 }, { 37.19, 12.38 }, { 37.45, 13.14 } },
                    note = "North of the lake, where the night elves keep their grove." },
                { objective = 1087, part = 2, kill = 4053, count = 4, radius = 0.05,
                    at = { { 35.84, 13.09 }, { 35.35, 12.10 }, { 35.28, 11.04 }, { 38.31, 13.29 }, { 36.71, 15.59 }, { 36.45, 13.09 } } },
                { objective = 1087, part = 3, kill = 4051, count = 4, radius = 0.05,
                    at = { { 35.84, 13.09 }, { 34.68, 12.43 }, { 35.96, 14.57 }, { 36.36, 11.85 }, { 36.97, 14.98 } } },
            } },
        } },

        { section = "The Charred Vale", steps = {
            { track = 6393,
                note = "Rogue Flame Spirits, Burning Ravagers and Burning Destroyers drop the Incendrites. Kill any you pass on the way down and among the harpies." },
            { group = {
                { objective = 6282, part = 1, kill = 4022, count = 7, radius = 0.06,
                    at = { { 31.10, 61.27 }, { 30.93, 59.23 }, { 31.83, 58.76 }, { 32.57, 60.66 }, { 34.51, 60.80 }, { 32.75, 64.45 }, { 31.95, 66.51 } },
                    note = "The harpies nest in the west of the Charred Vale." },
                { objective = 6282, part = 2, kill = 4025, count = 7, radius = 0.06,
                    at = { { 31.10, 61.27 }, { 29.64, 62.62 }, { 29.98, 61.88 }, { 31.11, 58.55 }, { 30.79, 65.29 }, { 32.07, 60.43 } },
                    note = "Ambushers hit hard with a lightning shock that comes back quickly. Pull them one at a time." },
                { objective = 6282, part = 3, kill = 4024, count = 7, radius = 0.06,
                    at = { { 29.20, 71.14 }, { 26.79, 69.53 }, { 27.37, 69.71 }, { 30.24, 69.58 }, { 30.06, 67.49 }, { 36.98, 69.78 }, { 37.28, 65.74 } },
                    note = "Slayers try to finish you off once your health runs low. Do not let a fight drag on with one." },
                { objective = 6282, part = 4, kill = 4023, count = 7, radius = 0.06,
                    at = { { 29.49, 68.63 }, { 29.30, 70.31 }, { 30.80, 68.91 }, { 35.53, 69.92 }, { 36.75, 67.66 }, { 34.86, 69.12 } },
                    note = "Roguefeathers lash out at everything near them every few seconds." },
                { objective = 86576, part = 1, collect = 277936, count = 15, kill = { 4022, 4025, 4024, 4023 }, radius = 0.06,
                    at = { { 31.10, 61.27 }, { 29.64, 62.62 }, { 30.24, 69.58 }, { 34.86, 69.12 } },
                    note = "Any Bloodfury harpy can carry a Glittering Sunstone. Keep them for Mor'rogal." },
            } },
            { travel = "The way up to Sun Rock Retreat", at = { 38.70, 68.60 }, radius = 0.03,
                note = "Leave the vale on its east side and take the path up into Sun Rock Retreat." },
        } },

        { section = "Back to Sun Rock Retreat", steps = {
            { group = {
                { turnin = 1087, accept = 1088, npc = 4198 },
                { turnin = 6282, accept = 6283, npc = 11860 },
                { turnin = 6301, accept = 6381, npc = 11864 },
            } },
        } },

        { section = "The Charred Vale again", steps = {
            { track = 6381,
                note = "Plant the Enchanted Gaea Seeds in the Gaea Dirt Mounds you pass in the vale." },
            { untrack = 6393 },
            { group = {
                { objective = 6393, part = 1, collect = 16312, count = 10, kill = { 4036, 4037, 4038 }, radius = 0.06,
                    at = { { 32.60, 67.40 }, { 28.53, 63.32 }, { 31.08, 67.04 }, { 35.42, 66.27 }, { 29.98, 65.44 },
                           { 31.64, 70.82 }, { 32.64, 73.51 }, { 34.14, 63.66 }, { 34.50, 59.88 } },
                    note = "Finish the Incendrites from the fire elementals in the middle and south of the vale." },
                { objective = 86576, part = 1, collect = 277936, count = 15, kill = { 4022, 4025, 4024, 4023 }, radius = 0.06,
                    at = { { 31.10, 61.27 }, { 29.64, 62.62 }, { 30.24, 69.58 }, { 34.86, 69.12 } },
                    note = "Finish the Glittering Sunstones from the harpies, if you are still short." },
                { objective = 6283, part = 1, collect = 16190, kill = 12579, radius = 0.03, at = { 30.75, 61.91 },
                    note = "Bloodfury Ripper is an elite harpy on the western hills of the vale. Clear the harpies around her before you pull, and bring a friend if you can." },
            } },
            { untrack = 6381 },
            { objective = 6381, part = 1, use = 16208, object = "Gaea Dirt Mound", radius = 0.06,
                at = { { 31.10, 61.27 }, { 31.33, 61.38 }, { 33.88, 61.92 }, { 34.22, 61.26 }, { 35.21, 63.73 }, { 31.90, 64.24 },
                       { 30.81, 66.56 }, { 32.24, 68.15 }, { 33.66, 67.02 }, { 36.06, 67.96 }, { 35.85, 70.31 }, { 31.34, 72.38 } },
                note = "Plant the rest of the ten seeds. The mounds are small heaps of earth all over the vale." },
            { travel = "The way up to Sun Rock Retreat", at = { 38.70, 68.60 }, radius = 0.03,
                note = "Back up the path into Sun Rock Retreat." },
        } },

        { section = "Sun Rock Retreat, last visit", steps = {
            { group = {
                { turnin = 6393, npc = 11862 },
                { turnin = 86576, npc = 11861,
                    note = "Mor'rogal stands on the ledge beside Tsunaman." },
                { turnin = 6283, npc = 11860, only = "now quest 6283 readyToTurnIn",
                    note = "Only if Bloodfury Ripper is dead." },
                { turnin = 6381, npc = 11864 },
            } },
            { finish = "Stonetalon is done. Keep Ordanus and Calling in the Reserves for the Ashenvale and Thousand Needles guide, and The Flying Machine Airport if you carry it, for Apothecary Zamah in Thunder Bluff." },
        } },
    },
    names = {
        npcs = {
            [4022] = "Bloodfury Harpy",
            [4023] = "Bloodfury Roguefeather",
            [4024] = "Bloodfury Slayer",
            [4025] = "Bloodfury Ambusher",
            [4036] = "Rogue Flame Spirit",
            [4037] = "Burning Ravager",
            [4038] = "Burning Destroyer",
            [4051] = "Cenarion Botanist",
            [4053] = "Daughter of Cenarius",
            [4057] = "Son of Cenarius",
            [4085] = { "Nizzik", at = { 62.70, 40.18 } },
            [4198] = { "Braelyn Firehand", at = { 45.94, 60.42 } },
            [4201] = { "Ziz Fizziks", at = { 58.99, 62.60 } },
            [4202] = "Gerenzo Wrenchwhistle",
            [4312] = { "Tharm", at = { 45.13, 59.84 } },
            [11860] = { "Maggran Earthbinder", at = { 47.20, 61.16 } },
            [11861] = { "Mor'rogal", at = { 47.22, 64.04 } },
            [11862] = { "Tsunaman", at = { 47.36, 64.25 } },
            [11864] = { "Tammra Windfield", at = { 47.46, 58.38 } },
            [12579] = "Bloodfury Ripper",
        },
        quests = {
            [1086] = "The Flying Machine Airport",
            [1087] = "Cenarius' Legacy",
            [1088] = "Ordanus",
            [1095] = "Further Instructions",
            [1096] = "Gerenzo Wrenchwhistle",
            [5881] = "Calling in the Reserves",
            [6282] = "Harpies Threaten",
            [6283] = "Bloodfury Bloodline",
            [6301] = "Cycle of Rebirth",
            [6381] = "New Life",
            [6393] = "Elemental War",
            [86576] = "Bloodfury Trinkets",
            [97538] = "Pigments for Paints",
        },
        items = {
            [5638] = "Toxic Fogger",
            [5736] = "Gerenzo's Mechanical Arm",
            [16190] = "Bloodfury Ripper's Remains",
            [16205] = "Gaea Seed",
            [16208] = "Enchanted Gaea Seeds",
            [16312] = "Incendrites",
            [277936] = "Glittering Sunstone",
            [278201] = "Mirkweed Pods",
        },
    },
}
