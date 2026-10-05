-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeTirisfal16.lua.
--
-- Horde 1-6 leveling route through Deathknell, ported from RestedXP's Forever
-- "1-6 Tirisfal Glades". Step order follows the source; quest IDs, NPC IDs,
-- item IDs and coordinates were checked against db/horde, ForeverGuide's
-- Forever scan (Aramis Hammerhand) and the Forever client's item table.
--
-- Notes from the authored guide:
--   * The source's first step has the player destroy their Hearthstone. It is
--     left out: NuuRoad does not tell a player to throw things away.
--   * Softcore shortcuts (dying to reach the spirit healer) are never an
--     instruction, only a note on the travel step. The logout skip out of
--     Night Web's Hollow, which the source already switches off, is left out.
--   * Forever's new creatures (the Injured Deathguards, the Frightened Paladin,
--     the Webbed Forsaken) and the Mining trainer Walter Mason have no known
--     IDs, so their steps name them in `object` or the note.
--
-- Map: 1420 Tirisfal Glades. Every point is on it.
--
-- Conversion notes:
--   * `only = "Horde"` on the guide became the wrapper's cond = { faction = "Horde" }.
--     "Undead" is the race token "scourge"; "X | Undead" is { class = X, race = "scourge" };
--     "not Warrior | not Rogue | not Paladin" is none of the three classes.
--   * Dropped `now` gates: "now level 2" on the first accept of The Damned (376; its note
--     already says to come back), and "now gold 50", "now gold 150", "now gold 75" on the
--     water-buying steps (their class terms kept as cond). Nothing else waited on a condition.
--   * Steps with only `at` and a note (the vendor-trash loops at the start) became note
--     steps keeping their `at` and radius.
--   * Kill and collect objectives lose their `count`; the objective counts. Every
--     `objective` with a `part` kept that part as quest = { id, n }.
--   * Whole-quest objectives (90902, 91208, 98389) got their objective number 1 from
--     db/horde/quests.json, which lists one "other" objective for each ("Injured
--     Deathguard healed", "Offer aid to the Frightened Paladin", "Webbed Forsaken freed").
--     They are interact steps naming the creature as `object`, since the creatures have no
--     IDs. Holy Light has no spell ID in the repo, so the Deathguard steps are not casts.
--   * The 90902 sticky step and its later "finish healing" step are kept as two steps
--     (sticky, then the step itself); the 98389 `with = "next"` step is kept with
--     with = "spiders", the label added to the Night Web Spider kill step that followed it.
--     Neither was a track/untrack pair, so no `from`.
--   * Samuel's Remains: the authored collect named quest = 6395 (the whole quest); kept as
--     quest = 6395, with the default count of 1.
--   * train = "Mining" became skill = 186 (Blacksmithing 164 / Mining 186, API/Client.lua).
--     Walter Mason has no NPC ID, so the step keeps its own `at` (the trainer upstairs).
--   * NPC positions moved from `names` to npcs[1420]. Joshua Kien's "inside the building"
--     and Calvin Montague's "by the house outside Deathknell" moved to their NPC notes.
--     Kill targets (zombies, scavengers, bats, skeletons, spiders, Scarlets, Meven
--     Korgal, Samuel Fipps) are names only; their steps keep their own `at`.
--   * The travel steps "Out of the crypt" and "Deathknell" stand on Undertaker Mordo's
--     and Deathguard Saltain's spots; they are travel steps, so they keep `at`.
--   * No area IDs were found for Deathknell or Night Web's Hollow, so the travel steps
--     finish on arrival at their points. No section needed a map of its own.
--   * Quest, item and spell names are left to the client, as the format asks.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:leveling:horde-tirisfal-1-6",
    updated = 1790640000,
    title = "Deathknell",
    category = "Leveling/Tirisfal Glades",
    author = "NuuRoad",
    tags = { "horde", "undead", "tirisfal", "deathknell" },
    levels = { from = 1, to = 6 },
    cond = { faction = "Horde" },
    source = "Ported from RestedXP's Forever \"1-6 Tirisfal Glades\".",

    data = {
        map = 1420,

        sections = {
            { title = "Deathknell", steps = {
                { type = "note", note = "Written for Undead starting in Deathknell. Another race is better off in its own starting zone.",
                  cond = { none = { { race = "scourge" } } } },
                { type = "travel", to = "Out of the crypt", at = { { 3022, 7165 } }, radius = 200,
                  note = "Run up the stairs and out of the crypt." },
                { type = "accept", quests = { 363 }, npc = { 1568 } },
                { type = "note", cond = { class = "MAGE" }, radius = 500,
                  at = { { 2992, 7030 }, { 3070, 6928 }, { 2918, 6894 }, { 2910, 6766 }, { 3019, 6532 } },
                  note = "Kill Young Scavengers and Duskbats on the way down and loot them until you have about 60 copper of vendor trash, your starting armour included." },
                { type = "note", cond = { class = "PRIEST" }, radius = 500,
                  at = { { 2992, 7030 }, { 3070, 6928 }, { 2918, 6894 }, { 2910, 6766 }, { 3019, 6532 } },
                  note = "Kill Young Scavengers and Duskbats on the way down and loot them until you have about 50 copper of vendor trash, your starting armour included." },
                { type = "note", cond = { class = { "WARRIOR", "WARLOCK" } }, radius = 500,
                  at = { { 2992, 7030 }, { 3070, 6928 } },
                  note = "Kill Young Scavengers and Duskbats on the way down and loot them until you have about 10 copper of vendor trash, your starting armour included." },
                { type = "buy", item = 159, count = 10, npc = { 2115 }, cond = { class = { "PRIEST", "MAGE" } },
                  note = "Sell him your trash first." },
                { type = "accept", quests = { 1470 }, npc = { 5667 }, cond = { class = "WARLOCK" } },
                { type = "talk", turnin = { 363 }, accept = { 364 }, npc = { 1569 } },
                { type = "accept", quests = { 376 }, npc = { 1661 },
                  note = "Novice Elreth offers The Damned from level 2. You come back to her soon if you are not there yet." },
                { type = "learn", spells = { 1459 }, npc = { 2124 }, cond = { class = "MAGE" } },
                { type = "vendor", sell = true, npc = { 5749 }, cond = { class = "WARLOCK" } },
                { type = "learn", spells = { 348 }, npc = { 2126 }, cond = { class = "WARLOCK" } },
                { type = "vendor", sell = true, npc = { 2113 }, cond = { class = "WARRIOR" } },
                { type = "learn", spells = { 6673 }, npc = { 2119 }, cond = { class = "WARRIOR" } },
                { type = "collect", item = 6281, kill = { 1890 }, quest = { 1470, 1 }, cond = { class = "WARLOCK" }, radius = 400,
                  at = { { 3182, 6148 }, { 3111, 6071 }, { 3207, 6017 }, { 3226, 5921 }, { 3328, 5953 },
                         { 3366, 6076 }, { 3394, 6181 }, { 3421, 6305 }, { 3301, 6301 } } },
                { type = "buy", item = 159, count = 5, npc = { 2115 }, cond = { class = "WARLOCK" },
                  note = "Loot the zombies on the way back until you have about 25 copper of trash, and sell it to Joshua Kien." },
                { type = "turnin", quests = { 1470 }, npc = { 5667 }, cond = { class = "WARLOCK" },
                  note = "Summon your imp." },
            } },

            { title = "The Mindless Ones", steps = {
                { group = {
                    { type = "kill", kill = { 1501 }, quest = { 364, 1 }, radius = 500,
                      at = { { 3172, 6398 }, { 3069, 6388 }, { 3090, 6220 }, { 3073, 6166 }, { 3114, 6141 },
                             { 3180, 6183 }, { 3285, 6302 }, { 3290, 6354 }, { 3341, 6306 }, { 3375, 6286 },
                             { 3351, 6382 }, { 3355, 6457 }, { 3329, 6496 } } },
                    { type = "kill", kill = { 1502 }, quest = { 364, 2 }, radius = 500,
                      at = { { 3172, 6398 }, { 3069, 6388 }, { 3090, 6220 }, { 3073, 6166 }, { 3114, 6141 },
                             { 3180, 6183 }, { 3285, 6302 }, { 3290, 6354 }, { 3341, 6306 }, { 3375, 6286 },
                             { 3351, 6382 }, { 3355, 6457 }, { 3329, 6496 } } },
                } },
                { type = "buy", item = 159, count = 10, npc = { 2115 }, cond = { class = { "MAGE", "WARLOCK", "PRIEST" } },
                  note = "Loot the zombies until you have about 33 copper of trash, and sell it to Joshua Kien." },
                { group = {
                    { type = "talk", turnin = { 364 }, accept = { 3901 }, npc = { 1569 } },
                    { type = "accept", quests = { 3095 }, npc = { 1569 }, cond = { class = "WARRIOR", race = "scourge" } },
                    { type = "accept", quests = { 3096 }, npc = { 1569 }, cond = { class = "ROGUE", race = "scourge" } },
                    { type = "accept", quests = { 3097 }, npc = { 1569 }, cond = { class = "PRIEST", race = "scourge" } },
                    { type = "accept", quests = { 3098 }, npc = { 1569 }, cond = { class = "MAGE", race = "scourge" } },
                    { type = "accept", quests = { 3099 }, npc = { 1569 }, cond = { class = "WARLOCK", race = "scourge" } },
                    { type = "accept", quests = { 98601 }, npc = { 1569 }, cond = { class = "PALADIN" } },
                    { type = "accept", quests = { 376 }, npc = { 1661 } },
                    { type = "turnin", quests = { 3099 }, npc = { 2126 }, cond = { class = "WARLOCK", race = "scourge" } },
                    { type = "turnin", quests = { 3098 }, npc = { 2124 }, cond = { class = "MAGE", race = "scourge" } },
                    { type = "turnin", quests = { 3097 }, npc = { 2123 }, cond = { class = "PRIEST", race = "scourge" } },
                    { type = "talk", turnin = { 98601 }, accept = { 90902 }, npc = { 244808 }, cond = { class = "PALADIN" } },
                } },
                { type = "interact", object = "Injured Deathguard", quest = { 90902, 1 }, cond = { class = "PALADIN" }, sticky = true,
                  note = "Cast Holy Light on five Injured Deathguards around Deathknell whenever you pass one." },
            } },

            { title = "The fields north of the village", steps = {
                { group = {
                    { type = "collect", item = 3265, kill = { 1508, 1509 }, quest = { 376, 1 }, radius = 500,
                      at = { { 2921, 6668 }, { 2948, 6570 }, { 2960, 6404 }, { 2967, 6339 }, { 3009, 6151 },
                             { 3097, 5966 }, { 3161, 5857 }, { 3207, 5774 }, { 3285, 5835 }, { 3432, 5679 } } },
                    { type = "collect", item = 3264, kill = { 1512, 1513 }, quest = { 376, 2 }, radius = 500,
                      at = { { 2921, 6668 }, { 2948, 6570 }, { 2960, 6404 }, { 2967, 6339 }, { 3009, 6151 },
                             { 3097, 5966 }, { 3161, 5857 }, { 3207, 5774 }, { 3285, 5835 }, { 3432, 5679 } },
                      note = "Mangy Duskbats are much tougher than the plain ones; leave them alone if you can." },
                } },
                { type = "kill", kill = { 1890 }, quest = { 3901, 1 }, radius = 400,
                  at = { { 3182, 6148 }, { 3111, 6071 }, { 3207, 6017 }, { 3226, 5921 }, { 3328, 5953 },
                         { 3366, 6076 }, { 3394, 6181 }, { 3421, 6305 }, { 3301, 6301 } } },
                { type = "level", level = 3, xp = 980, radius = 400,
                  cond = { none = { { class = { "WARRIOR", "ROGUE", "PALADIN" } } } },
                  at = { { 3182, 6148 }, { 3111, 6071 }, { 3207, 6017 }, { 3226, 5921 }, { 3328, 5953 },
                         { 3366, 6076 }, { 3394, 6181 }, { 3421, 6305 }, { 3301, 6301 } },
                  note = "Grind the zombies and skeletons until you are 980 experience into level 3." },
                { type = "level", level = 3, xp = 940, cond = { class = { "WARRIOR", "ROGUE" } }, radius = 400,
                  at = { { 3182, 6148 }, { 3111, 6071 }, { 3207, 6017 }, { 3226, 5921 }, { 3328, 5953 },
                         { 3366, 6076 }, { 3394, 6181 }, { 3421, 6305 }, { 3301, 6301 } },
                  note = "Grind the zombies and skeletons until you are 940 experience into level 3." },
                { type = "level", level = 3, xp = 895, cond = { class = "PALADIN" }, radius = 400,
                  at = { { 3182, 6148 }, { 3111, 6071 }, { 3207, 6017 }, { 3226, 5921 }, { 3328, 5953 },
                         { 3366, 6076 }, { 3394, 6181 }, { 3421, 6305 }, { 3301, 6301 } },
                  note = "Grind the zombies and skeletons until you are 895 experience into level 3." },
                { type = "interact", object = "Injured Deathguard", quest = { 90902, 1 }, cond = { class = "PALADIN" },
                  at = { { 3186, 6510 } },
                  note = "Finish healing the Injured Deathguards with Holy Light." },
            } },

            { title = "Back in Deathknell", steps = {
                { type = "buy", item = 159, count = 20, npc = { 2115 }, cond = { class = { "MAGE", "WARLOCK", "PRIEST" } },
                  note = "Sell your trash to Joshua Kien first, and keep at least 1 silver for training." },
                { type = "vendor", sell = true, npc = { 2115 }, cond = { class = "PALADIN" } },
                { group = {
                    { type = "turnin", quests = { 3901 }, npc = { 1569 } },
                    { type = "talk", turnin = { 376 }, accept = { 6395 }, npc = { 1661 } },
                    { type = "talk", turnin = { 90902 }, accept = { 91208, 91209 }, npc = { 244808 }, cond = { class = "PALADIN" } },
                    { type = "accept", quests = { 98389 }, npc = { 244808 } },
                } },
                { type = "learn", spells = { 20271 }, npc = { 244808 }, cond = { class = "PALADIN" },
                  note = "Blessing of Might as well if you can afford both." },
                { type = "learn", spells = { 589 }, npc = { 2123 }, cond = { class = "PRIEST" },
                  note = "Then Lesser Heal rank 2 and Power Word: Fortitude as far as your money goes." },
                { type = "learn", spells = { 172 }, npc = { 2126 }, cond = { class = "WARLOCK" } },
                { type = "learn", spells = { 116 }, npc = { 2124 }, cond = { class = "MAGE" } },
                { group = {
                    { type = "accept", quests = { 3902 }, npc = { 1740 } },
                    { type = "accept", quests = { 380 }, npc = { 1570 } },
                } },
                { type = "vendor", sell = true, npc = { 2113 }, cond = { class = { "ROGUE", "WARRIOR", "PALADIN" } } },
                { type = "turnin", quests = { 3095 }, npc = { 2119 }, cond = { class = "WARRIOR", race = "scourge" } },
                { type = "learn", spells = { 772 }, npc = { 2119 }, cond = { class = "WARRIOR", race = "scourge" },
                  note = "Charge as well if you can afford both." },
                { type = "turnin", quests = { 3096 }, npc = { 2122 }, cond = { class = "ROGUE", race = "scourge" } },
                { type = "train", skill = 186, cond = { class = { "ROGUE", "WARRIOR", "PALADIN" } }, at = { { 3223, 6582 } },
                  note = "Optional. Walter Mason, upstairs, teaches Mining and sells the Mining Pick. Rough Stone makes sharpening stones: two more weapon damage for half an hour. Skip it if you have other plans for your professions." },
                { type = "collect", item = 11127, quest = { 3902, 1 }, object = "Equipment Box", radius = 200,
                  at = { { 3237, 6437 }, { 3281, 6439 }, { 3289, 6460 }, { 3301, 6538 }, { 3379, 6457 },
                         { 3313, 6308 }, { 3279, 6311 }, { 3186, 6149 }, { 3175, 6196 }, { 3170, 6253 },
                         { 3134, 6244 } },
                  note = "The Equipment Boxes lie on the ground around the village." },
                { type = "interact", object = "Frightened Paladin", quest = { 91208, 1 }, cond = { class = "PALADIN" },
                  note = "Offer aid to the Frightened Paladin near the village. She turns on you; kill her." },
            } },

            { title = "Night Web's Hollow", steps = {
                { type = "kill", kill = { 1504 }, quest = { 380, 1 }, radius = 500,
                  at = { { 2994, 5733 }, { 2982, 5603 }, { 2925, 5577 }, { 2840, 5651 }, { 2768, 5710 },
                         { 2829, 5831 }, { 2825, 5941 }, { 2880, 5953 }, { 2929, 5940 }, { 2967, 5853 },
                         { 2842, 5907 }, { 2786, 6057 }, { 2717, 5918 }, { 2694, 5642 } },
                  note = "Young Night Web Spiders outside the cave." },
                { type = "travel", to = "Night Web's Hollow", at = { { 2631, 5960 } }, radius = 200,
                  note = "Go into the cave." },
                { type = "interact", object = "Webbed Forsaken", quest = { 98389, 1 }, with = "spiders",
                  note = "Attack the Webbed Forsaken inside the cave to free them: six of them." },
                { type = "kill", kill = { 1505 }, quest = { 380, 2 }, label = "spiders", radius = 300,
                  at = { { 2561, 5955 }, { 2511, 6033 }, { 2418, 6077 }, { 2323, 5991 }, { 2389, 5836 },
                         { 2468, 5954 } } },
                { type = "interact", object = "Webbed Forsaken", quest = { 98389, 1 }, at = { { 2460, 5945 } },
                  note = "Finish freeing the Webbed Forsaken." },
                { type = "travel", to = "Deathknell", at = { { 3161, 6562 } }, radius = 300,
                  note = "Walk back. Without hardcore rules, dying and taking the spirit healer's resurrection is quicker." },
                { group = {
                    { type = "turnin", quests = { 3902 }, npc = { 1740 } },
                    { type = "talk", turnin = { 380 }, accept = { 381 }, npc = { 1570 } },
                    { type = "turnin", quests = { 91208 }, npc = { 244808 }, cond = { class = "PALADIN" } },
                    { type = "turnin", quests = { 98389 }, npc = { 244808 } },
                } },
                { type = "vendor", sell = true, npc = { 2113 }, cond = { class = { "ROGUE", "WARRIOR", "PALADIN" } } },
                { type = "buy", item = 159, count = 15, npc = { 2115 }, cond = { class = { "MAGE", "WARLOCK", "PRIEST" } },
                  note = "Sell your trash to Joshua Kien first." },
            } },

            { title = "The Scarlet camp", steps = {
                { type = "collect", item = 3266, kill = { 1506, 1507 }, quest = { 381, 1 }, radius = 400,
                  at = { { 3613, 6874 }, { 3646, 6949 }, { 3685, 7002 }, { 3742, 6958 }, { 3805, 6979 },
                         { 3791, 6922 }, { 3803, 6877 }, { 3849, 6828 }, { 3872, 6707 }, { 3859, 6625 },
                         { 3865, 6507 }, { 3762, 6536 }, { 3693, 6538 }, { 3651, 6542 }, { 3685, 6659 },
                         { 3745, 6795 }, { 3693, 6816 } },
                  note = "Leave Meven Korgal alone for now. Warriors and rogues: the Initiates' Frost Armor slows your attacks, so favour the Converts." },
                { type = "collect", item = 16333, quest = 6395, kill = { 1919 }, at = { { 3669, 6167 } },
                  note = "Samuel Fipps is north of the camp. Kill him and take his remains." },
                { type = "interact", object = "Marla's Grave", quest = { 6395, 1 }, at = { { 3117, 6508 } },
                  note = "Marla's Grave is on the ground at the edge of Deathknell." },
                { group = {
                    { type = "turnin", quests = { 6395 }, npc = { 1661 } },
                    { type = "accept", quests = { 5651 }, npc = { 2123 }, cond = { class = "PRIEST", race = "scourge" } },
                    { type = "talk", turnin = { 381 }, accept = { 382 }, npc = { 1570 } },
                } },
                { type = "vendor", sell = true, npc = { 2113 } },
                { type = "collect", item = 2885, kill = { 1667 }, quest = { 382, 1 }, at = { { 3650, 6882 } },
                  note = "Meven Korgal is in the Scarlet camp. Kill him and take the documents." },
                { type = "talk", turnin = { 382 }, accept = { 383, 96656 }, npc = { 1570 } },
                { type = "level", level = 5, xp = 1940, cond = { none = { { class = "PALADIN" } } }, radius = 500,
                  at = { { 3408, 5951 }, { 3534, 5655 }, { 3683, 5685 }, { 3776, 5938 }, { 3751, 6299 },
                         { 3613, 6874 }, { 3742, 6958 }, { 3849, 6828 }, { 3865, 6507 }, { 3693, 6538 } },
                  note = "Grind on your way north-east until you are 1940 experience into level 5." },
                { type = "level", level = 5, xp = 1850, cond = { class = "PALADIN" }, radius = 500,
                  at = { { 3408, 5951 }, { 3534, 5655 }, { 3683, 5685 }, { 3776, 5938 }, { 3751, 6299 },
                         { 3613, 6874 }, { 3742, 6958 }, { 3849, 6828 }, { 3865, 6507 }, { 3693, 6538 } },
                  note = "Grind on your way north-east until you are 1850 experience into level 5." },
                { type = "accept", quests = { 8 }, npc = { 6784 },
                  note = "His letter turns in at Brill." },
                { type = "finish", note = "Deathknell is done. Continue with Brill and the Undercity." },
            } },
        },

        npcs = {
            [1420] = { -- Tirisfal Glades
                -- Visited.
                [1568] = { name = "Undertaker Mordo", at = { 3022, 7165 } },
                [1569] = { name = "Shadow Priest Sarvis", at = { 3084, 6620 } },
                [1570] = { name = "Executor Arren", at = { 3215, 6601 } },
                [1661] = { name = "Novice Elreth", at = { 3086, 6605 } },
                [1740] = { name = "Deathguard Saltain", at = { 3161, 6562 } },
                [2113] = { name = "Archibald Kava", at = { 3242, 6566 } },
                [2115] = { name = "Joshua Kien", at = { 3229, 6544 }, note = "Inside the building." },
                [2119] = { name = "Dannal Stern", at = { 3268, 6556 } },
                [2122] = { name = "David Trias", at = { 3253, 6565 } },
                [2123] = { name = "Dark Cleric Duesten", at = { 3111, 6602 } },
                [2124] = { name = "Isabella", at = { 3094, 6606 } },
                [2126] = { name = "Maximillion", at = { 3091, 6634 } },
                [5667] = { name = "Venya Marthand", at = { 3098, 6641 } },
                [5749] = { name = "Kayla Smithe", at = { 3081, 6641 } },
                [6784] = { name = "Calvin Montague", at = { 3824, 5677 }, note = "By the house outside Deathknell." },
                [244808] = { name = "Aramis Hammerhand", at = { 3109, 6640 } },

                -- Kill targets: the steps that fight them say where.
                [1501] = "Mindless Zombie",
                [1502] = "Wretched Zombie",
                [1504] = "Young Night Web Spider",
                [1505] = "Night Web Spider",
                [1506] = "Scarlet Convert",
                [1507] = "Scarlet Initiate",
                [1508] = "Young Scavenger",
                [1509] = "Ragged Scavenger",
                [1512] = "Duskbat",
                [1513] = "Mangy Duskbat",
                [1667] = "Meven Korgal",
                [1890] = "Rattlecage Skeleton",
                [1919] = "Samuel Fipps",
            },
        },
    },
})
