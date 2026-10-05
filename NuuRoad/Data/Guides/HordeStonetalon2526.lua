-- A packaged guide, in guide format v1 (docs/examples/guide-v1.lua).
--
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
--     it collects the Mirkweed Pods at Mirkfallon Lake with the Gaea Seeds.
--   * Bloodfury Bloodline's rewards changed in Forever; the quest itself did
--     not.
--
-- Deliberate divergences from the source:
--   * The Flying Machine Airport (1086) is only worked for a character who
--     carries it from Apothecary Zamah, as the source does; it is handed in at
--     Thunder Bluff in the Ashenvale guide.
--   * Gerenzo Wrenchwhistle is only offered once Further Instructions (1095)
--     has been handed in, since Ziz will not give it otherwise.
--   * The source sends the player for Incendrites "as you go" during the first
--     harpy fight and plants the seeds alongside the Ripper; both are the real
--     steps carried with `from` from the start of their sections.
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
-- Maps: 1442 Stonetalon Mountains (guide default). Every point is on it.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    schema = 1,

    id = "nuuroad:leveling:horde-stonetalon-25-26",
    updated = 1790985600,
    title = "Sun Rock Retreat",
    category = "Leveling/Stonetalon Mountains",
    author = "NuuRoad",
    tags = { "horde", "stonetalon", "sun rock retreat", "charred vale", "windshear crag" },
    levels = { from = 25, to = 26 },
    cond = { faction = "Horde" },
    source = "Ported from RestedXP's Classic \"25-26 Stonetalon\" (RestedXP Horde 20-30.lua).",

    data = {
        map = 1442,

        sections = {
            { title = "Sun Rock Retreat", steps = {
                { type = "travel", to = "Sun Rock Retreat", area = 460, at = { { 4513, 5984 } }, radius = 400,
                  note = "Fly from the Crossroads to Sun Rock Retreat." },
                { type = "flight", node = 29, npc = { 4312 },
                  note = "Tharm, if you do not have this flight path yet." },
                { group = {
                    { type = "accept", quests = { 1087 }, npc = { 4198 } },
                    { type = "accept", quests = { 6393 }, npc = { 11862 } },
                    { type = "accept", quests = { 6301 }, npc = { 11864 } },
                    { type = "accept", quests = { 5881, 6282, 86576 }, npc = { 11860 },
                      note = "Calling in the Reserves needs level 23." },
                } },
            } },

            { title = "Windshear Crag", steps = {
                { type = "accept", quests = { 1096 }, npc = { 4201 },
                  note = "Ziz Fizziks is inside the building at Windshear Crag. He only offers this once Further Instructions is handed in; skip it otherwise." },
                { type = "travel", to = "The Venture Co. sky port", use = { 5638 }, quest = { 1086, 1 },
                  at = { { 6644, 4546 } },
                  note = "Use the Toxic Fogger on the Venture Co. sky port. Only if you carry The Flying Machine Airport; skip this otherwise." },
                { type = "collect", item = 5736, kill = { 4202 }, quest = { 1096, 1 }, radius = 300,
                  at = { { 6449, 4025 } },
                  note = "Gerenzo Wrenchwhistle is at the top of the sky port with his builders around him. Clear them first, then kill him and take his arm." },
                { type = "note", npc = { 4085 },
                  note = "Nizzik, at the end of the platform, sells armor that changes from time to time. Have a look for an upgrade while you are here." },
                { type = "turnin", quests = { 1096 }, npc = { 4201 } },
            } },

            { title = "Mirkfallon Lake and the Cenarion grove", steps = {
                { group = {
                    { type = "collect", item = 16205, quest = { 6301, 1 }, object = "Gaea Seed", radius = 600,
                      at = { { 5063, 3656 }, { 4839, 3587 }, { 4669, 3753 }, { 4631, 3960 }, { 4805, 3976 },
                             { 5019, 3920 }, { 5096, 4113 }, { 5177, 4262 }, { 4969, 4329 }, { 4974, 4511 },
                             { 4799, 4432 }, { 4581, 4311 } },
                      note = "The seeds lie in and around Mirkfallon Lake. Swim across and pick them up on both shores." },
                    { type = "collect", item = 278201, quest = { 97538, 1 }, object = "Mirkweed", radius = 600,
                      at = { { 5063, 3656 }, { 4839, 3587 }, { 4669, 3753 }, { 5019, 3920 }, { 4969, 4329 } },
                      note = "Pigments for Paints, from Tah Winterhoof in Thunder Bluff: the Mirkweed grows in the lake. Skip this if you do not have the quest." },
                } },
                { group = {
                    { type = "kill", kill = { 4057 }, quest = { 1087, 1 }, radius = 500,
                      at = { { 3584, 1309 }, { 3544, 1528 }, { 3822, 1142 }, { 3590, 1051 }, { 3719, 1238 }, { 3745, 1314 } },
                      note = "North of the lake, where the night elves keep their grove." },
                    { type = "kill", kill = { 4053 }, quest = { 1087, 2 }, radius = 500,
                      at = { { 3584, 1309 }, { 3535, 1210 }, { 3528, 1104 }, { 3831, 1329 }, { 3671, 1559 }, { 3645, 1309 } } },
                    { type = "kill", kill = { 4051 }, quest = { 1087, 3 }, radius = 500,
                      at = { { 3584, 1309 }, { 3468, 1243 }, { 3596, 1457 }, { 3636, 1185 }, { 3697, 1498 } } },
                } },
            } },

            { title = "The Charred Vale", label = "elemental-war", steps = {
                { group = {
                    { type = "kill", kill = { 4022 }, quest = { 6282, 1 }, radius = 600,
                      at = { { 3110, 6127 }, { 3093, 5923 }, { 3183, 5876 }, { 3257, 6066 }, { 3451, 6080 }, { 3275, 6445 }, { 3195, 6651 } },
                      note = "The harpies nest in the west of the Charred Vale." },
                    { type = "kill", kill = { 4025 }, quest = { 6282, 2 }, radius = 600,
                      at = { { 3110, 6127 }, { 2964, 6262 }, { 2998, 6188 }, { 3111, 5855 }, { 3079, 6529 }, { 3207, 6043 } },
                      note = "Ambushers hit hard with a lightning shock that comes back quickly. Pull them one at a time." },
                    { type = "kill", kill = { 4024 }, quest = { 6282, 3 }, radius = 600,
                      at = { { 2920, 7114 }, { 2679, 6953 }, { 2737, 6971 }, { 3024, 6958 }, { 3006, 6749 }, { 3698, 6978 }, { 3728, 6574 } },
                      note = "Slayers try to finish you off once your health runs low. Do not let a fight drag on with one." },
                    { type = "kill", kill = { 4023 }, quest = { 6282, 4 }, radius = 600,
                      at = { { 2949, 6863 }, { 2930, 7031 }, { 3080, 6891 }, { 3553, 6992 }, { 3675, 6766 }, { 3486, 6912 } },
                      note = "Roguefeathers lash out at everything near them every few seconds." },
                    { type = "collect", item = 277936, kill = { 4022, 4025, 4024, 4023 }, quest = { 86576, 1 }, radius = 600,
                      at = { { 3110, 6127 }, { 2964, 6262 }, { 3024, 6958 }, { 3486, 6912 } },
                      note = "Any Bloodfury harpy can carry a Glittering Sunstone. Keep them for Mor'rogal." },
                } },
                { type = "travel", to = "The way up to Sun Rock Retreat", at = { { 3870, 6860 } }, radius = 300,
                  note = "Leave the vale on its east side and take the path up into Sun Rock Retreat." },
            } },

            { title = "Back to Sun Rock Retreat", steps = {
                { group = {
                    { type = "talk", turnin = { 1087 }, accept = { 1088 }, npc = { 4198 } },
                    { type = "talk", turnin = { 6282 }, accept = { 6283 }, npc = { 11860 } },
                    { type = "talk", turnin = { 6301 }, accept = { 6381 }, npc = { 11864 }, label = "new-life" },
                } },
            } },

            { title = "The Charred Vale again", steps = {
                { group = {
                    { type = "collect", item = 16312, kill = { 4036, 4037, 4038 }, quest = { 6393, 1 }, radius = 600,
                      from = "elemental-war",
                      at = { { 3260, 6740 }, { 2853, 6332 }, { 3108, 6704 }, { 3542, 6627 }, { 2998, 6544 },
                             { 3164, 7082 }, { 3264, 7351 }, { 3414, 6366 }, { 3450, 5988 } },
                      note = "Rogue Flame Spirits, Burning Ravagers and Burning Destroyers drop the Incendrites. Kill any you pass on the way down and among the harpies, then finish them from the fire elementals in the middle and south of the vale." },
                    { type = "collect", item = 277936, kill = { 4022, 4025, 4024, 4023 }, quest = { 86576, 1 }, radius = 600,
                      at = { { 3110, 6127 }, { 2964, 6262 }, { 3024, 6958 }, { 3486, 6912 } },
                      note = "Finish the Glittering Sunstones from the harpies, if you are still short." },
                    { type = "collect", item = 16190, kill = { 12579 }, quest = { 6283, 1 }, radius = 300,
                      at = { { 3075, 6191 } },
                      note = "Bloodfury Ripper is an elite harpy on the western hills of the vale. Clear the harpies around her before you pull, and bring a friend if you can." },
                } },
                { type = "interact", object = "Gaea Dirt Mound", use = { 16208 }, quest = { 6381, 1 }, radius = 600,
                  from = "new-life",
                  at = { { 3110, 6127 }, { 3133, 6138 }, { 3388, 6192 }, { 3422, 6126 }, { 3521, 6373 }, { 3190, 6424 },
                         { 3081, 6656 }, { 3224, 6815 }, { 3366, 6702 }, { 3606, 6796 }, { 3585, 7031 }, { 3134, 7238 } },
                  note = "Plant the Enchanted Gaea Seeds in the Gaea Dirt Mounds you pass in the vale, ten in all. The mounds are small heaps of earth all over the vale." },
                { type = "travel", to = "The way up to Sun Rock Retreat", at = { { 3870, 6860 } }, radius = 300,
                  note = "Back up the path into Sun Rock Retreat." },
            } },

            { title = "Sun Rock Retreat, last visit", steps = {
                { group = {
                    { type = "turnin", quests = { 6393 }, npc = { 11862 } },
                    { type = "turnin", quests = { 86576 }, npc = { 11861 } },
                    { type = "turnin", quests = { 6283 }, npc = { 11860 }, optional = true,
                      note = "Only if Bloodfury Ripper is dead." },
                    { type = "turnin", quests = { 6381 }, npc = { 11864 } },
                } },
                { type = "finish", note = "Stonetalon is done. Keep Ordanus and Calling in the Reserves for the Ashenvale and Thousand Needles guide, and The Flying Machine Airport if you carry it, for Apothecary Zamah in Thunder Bluff." },
            } },
        },

        npcs = {
            [1442] = { -- Stonetalon Mountains
                [4085] = { name = "Nizzik", at = { 6270, 4018 } },
                [4198] = { name = "Braelyn Firehand", at = { 4594, 6042 } },
                [4201] = { name = "Ziz Fizziks", at = { 5899, 6260 } },
                [4312] = { name = "Tharm", at = { 4513, 5984 } },
                [11860] = { name = "Maggran Earthbinder", at = { 4720, 6116 } },
                [11861] = { name = "Mor'rogal", at = { 4722, 6404 }, note = "On the ledge beside Tsunaman." },
                [11862] = { name = "Tsunaman", at = { 4736, 6425 }, note = "On the lower ledge, south of the camp." },
                [11864] = { name = "Tammra Windfield", at = { 4746, 5838 } },

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
                [4202] = "Gerenzo Wrenchwhistle",
                [12579] = "Bloodfury Ripper",
            },
        },
    },
})
