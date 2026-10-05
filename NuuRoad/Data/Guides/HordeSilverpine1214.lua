-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeSilverpine1214.lua.
--
-- Horde 12-14 leveling route through Silverpine Forest and the Sepulcher, with the
-- turn-ins in the Undercity and the walk to Far Watch Post, ported from RestedXP's
-- Forever "12-14 Silverpine Forest". It picks up where the Tirisfal Glades guide
-- ends, at the road into the forest. Step order follows the source; quest IDs, NPC
-- IDs, item IDs and coordinates were checked against db/horde and Questie's
-- Forever database. The source's world coordinates were turned into map
-- percentages with a fit its own map comments give, and every NPC stands where
-- the database puts them.
--
-- Notes:
--   * Softcore shortcuts (dying to reach the spirit healer) are never an
--     instruction; NuuRoad never tells a player to die, so those steps are
--     ordinary travel steps and the shortcut is a note.
--   * The source turns in Wild Hearts at Rane Yorick and then again at
--     Apothecary Renferrel; the quest ends at Renferrel, so it is turned in once,
--     there.
--   * The source's worg heart count (3) disagrees with its own comment (6) and
--     with the quest text, so the step carries no count and the client's own
--     objective counts.
--   * The Ragefire Chasm detour (the zeppelin, Thrall's Hidden Enemies, the
--     dungeon) is its own guide, NuuRoad's Ragefire Chasm; here it is one note.
--   * The Undercity logout skips, which the source already switches off, are
--     left out.
--   * The Undead rogue's Deathstalkers chain repeats the Tirisfal guide's steps,
--     for a rogue who did not finish it there; steps already done pass by.
--
-- Maps: 1421 Silverpine Forest (guide default), 1458 Undercity, 1420 Tirisfal
-- Glades, 1411 Durotar, 1413 The Barrens.
--
-- Conversion notes (judgement calls made converting from authored format v2):
--   * `only` class/race/faction terms became `cond` ("Undead" -> race
--     "scourge"; "Rogue | Undead" -> both; "not Mage | not Priest" -> none of
--     the two classes; "Mage or Priest or Warlock" -> a class list).
--   * Dropped `now` gates: gold (both mushroom and milk buys in both visits,
--     Wise Man's Belt, Agile Boots, Scimitar, Smoldering Wand), weapon slot
--     dps (Scimitar slot 16, Smoldering Wand slot 18), level 14 (the five
--     class trainer notes), and quest 1886 readyToTurnIn / finished (the
--     Undead rogue's Deathstalkers chain in the Undercity). The player skips
--     what does not apply; the chain's steps keep only their class and race.
--   * Quest-state `only` terms "quest 435" (turn in Escorting Erland, take The
--     Deathstalkers' Report, in the first Ivar Patch group) and "quest 445"
--     (Delivery to Silverpine Forest at Renferrel) cannot be a cond/show; those
--     steps are `optional = true` instead, passed on arrival unless ready. The
--     Deathstalkers turn-in of 1886 (gated on readyToTurnIn) is optional too.
--   * track/untrack pairs became `from`: Wild Hearts (429) hearts step carries
--     `from = "wildhearts"`, a label on the group at Rane Yorick that takes 429;
--     the bear hearts step (447, objective 1) carries `from = "deadfield"`, a
--     label on the section where the track started. Each track note was merged
--     into its objective step's note.
--   * `with = "next"` became a label on the following step ("spellbooks",
--     "grimson").
--   * Objective numbers are the source's own `part`s; none inferred. The Dead
--     Field step had `objective = 437` with no part, so it names the whole
--     quest (`quest = 437`). Kill/collect counts on objective steps were
--     dropped (the objective counts); the murloc-eye collect with no quest
--     keeps `count = 3`.
--   * Travel steps with `subzone` (The Sepulcher x4, Valgan's Field, Razor
--     Hill, Far Watch Post) have no AreaTable ID in the repo, so `area` is left
--     out: they finish on arrival at `at`. Travel `zone` names became map IDs
--     (Undercity 1458, Tirisfal Glades 1420, Durotar 1411).
--   * `flight = "The Sepulcher"` became node 10 (db/horde/flightpaths.json,
--     flight master 2226). `train = "First Aid"` became skill 129
--     (NuuProfessions' FirstAid skillLine).
--   * Steps that named an NPC dropped no `at` of their own (none had one); NPC
--     location notes ("down in the crypt", "second floor of the house", the
--     Undercity quarters, the fishing hut) moved to the NPC in `npcs`; notes
--     about the step itself stay on the step.
--   * The five "train your new ranks" steps had no verb, only `npc` and `note`:
--     they are `note` steps with `npc`. The two Corpse Laden Boat / Dalaran
--     Crate hand-ins are `talk` steps with `object` and `at`.
--   * v2 `at` lists put the arrow target first and map pins after; the lists are
--     kept whole and in order (the escort's end, the Sepulcher, first).
--   * Every NPC the guide visits has a position; Astor Hadren (6497, walks the
--     road) and the kill targets are names only. No section needed a map added:
--     the Undercity and Durotar sections already had theirs, and off-map points
--     carry their own.
--   * `source` on the wrapper is taken from the header comment (the v2 meta had
--     none).

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:leveling:horde-silverpine-12-14",
    updated = 1790726400,                -- 2026-09-30
    title = "The Sepulcher",
    category = "Leveling/Silverpine Forest",
    author = "NuuRoad",
    tags = { "horde", "undead", "silverpine", "sepulcher", "undercity" },
    levels = { from = 12, to = 14 },
    cond = { faction = "Horde" },
    source = "Ported from RestedXP's Forever \"12-14 Silverpine Forest\".",

    data = {
        map = 1421,

        sections = {
            { title = "The Ivar Patch", steps = {
                { type = "collect", item = 7231, quest = 1886, kill = { 6497 }, sticky = true,
                  cond = { class = "ROGUE", race = "scourge" },
                  note = "Astor Hadren walks the road between Brill and the Sepulcher. If you meet him, talk to him, kill him and take his letter." },
                { type = "accept", quests = { 435 }, npc = { 1978 },
                  note = "Deathstalker Erland waits just inside the forest. If he is not there, skip this and the next step; you come back past him." },
                { type = "escort", quest = 435, npc = { 1978 }, radius = 300,
                  at = { { 5346, 1345 }, { 5625, 1027 }, { 5625, 1143 }, { 5617, 1262 } },
                  note = "Keep Erland alive on the way to Rane Yorick. Worgs can spawn on top of each other; eat and drink whenever you can." },
                { label = "wildhearts", group = {
                    { type = "talk", turnin = { 435 }, accept = { 449 }, npc = { 1950 }, optional = true },
                    { type = "accept", quests = { 429 }, npc = { 1950 } },
                } },
                { type = "collect", item = 730, count = 3, kill = { 1767, 1768 }, radius = 500,
                  at = { { 6512, 1183 }, { 6356, 1285 }, { 6051, 1751 }, { 5894, 1802 } },
                  note = "The Vile Fin murlocs on the northern shore drop Murloc Eyes. Keep three; a quest asks for them soon. Do not sell them." },
                { type = "accept", quests = { 435 }, npc = { 1978 },
                  note = "Back to Deathstalker Erland for his escort, if you could not take it before." },
                { type = "escort", quest = 435, npc = { 1978 }, radius = 300,
                  at = { { 5346, 1345 }, { 5625, 1027 }, { 5625, 1143 }, { 5617, 1262 } },
                  note = "Keep Erland alive on the way to Rane Yorick." },
                { type = "collect", item = 3164, kill = { 1765, 1766 }, quest = { 429, 1 }, from = "wildhearts", radius = 600,
                  at = { { 5772, 1007 }, { 5596, 1618 }, { 5837, 1556 }, { 5940, 1358 }, { 6011, 1051 } },
                  note = "Worgs and Mottled Worgs drop the Discolored Worg Hearts; kill any that come near. Gorefang, a rare worg, can walk among them." },
                { type = "talk", turnin = { 435 }, accept = { 449 }, npc = { 1950 } },
            } },

            { title = "The Sepulcher", steps = {
                { type = "travel", to = "The Sepulcher", radius = 400,
                  at = { { 4551, 4126 }, { 4977, 2866 }, { 4977, 3305 }, { 4964, 3784 } },
                  note = "South along the road. Without hardcore rules, dying and taking the spirit healer's resurrection puts you at the Sepulcher faster." },
                { type = "accept", quests = { 421 }, npc = { 1938 } },
                { type = "buy", item = 4605, count = 20, npc = { 5886 },
                  cond = { none = { { class = { "MAGE", "PRIEST" } } } },
                  note = "Red-speckled Mushrooms from Gwyn Farrow. Sell her your trash, but keep your Murloc Eyes." },
                { type = "buy", item = 1179, count = 20, npc = { 2140 },
                  cond = { class = { "MAGE", "PRIEST", "WARLOCK" } },
                  note = "Ice Cold Milk from Edwin Harly. He sometimes has Lesser Healing Potions as well. Keep your Murloc Eyes." },
                { group = {
                    { type = "accept", quests = { 477 }, npc = { 2121 } },
                    { type = "accept", quests = { 6321 }, npc = { 6389 }, cond = { race = "scourge" } },
                } },
                { group = {
                    { type = "talk", turnin = { 449 }, accept = { 3221, 437 }, npc = { 1952 } },
                    { type = "talk", turnin = { 429, 3221 }, accept = { 1359, 447, 430 }, npc = { 1937 } },
                    { type = "turnin", quests = { 445 }, npc = { 1937 }, optional = true,
                      note = "Delivery to Silverpine Forest, from Apothecary Johaan in Brill." },
                } },
            } },

            { title = "North of the Sepulcher", steps = {
                { type = "kill", kill = { 1769 }, quest = { 421, 1 }, radius = 600,
                  at = { { 4912, 3672 }, { 5032, 3922 }, { 5186, 4156 }, { 5153, 4306 }, { 5162, 4485 },
                         { 5180, 4660 }, { 5083, 4774 } },
                  note = "Moonrage Whitescalps along the road. Keep clear of the Son of Arugal, a level 25 elite worgen, if you see him." },
                { type = "talk", turnin = { 421 }, accept = { 422 }, npc = { 1938 } },
                { type = "travel", to = "Valgan's Field", with = "spellbooks", at = { { 5274, 2770 } } },
                { type = "collect", item = 3155, quest = { 422, 1 }, object = "Dusty Spellbooks", label = "spellbooks",
                  at = { { 5283, 2856 } },
                  note = "Go into the farmhouse and up to the second floor. The spellbooks lie on the ground." },
                { type = "talk", turnin = { 430 }, accept = { 91920 }, npc = { 1951 } },
                { type = "collect", item = 730, kill = { 1767, 1768 }, quest = { 91920, 1 }, radius = 500,
                  at = { { 6512, 1183 }, { 6356, 1285 }, { 6051, 1751 }, { 5894, 1802 } },
                  note = "Finish the Murloc Eyes from the Vile Fin murlocs on the shore, if you have not got three yet." },
            } },

            { title = "The Dead Field and the spiders", label = "deadfield", steps = {
                { type = "collect", item = 3622, kill = { 1772, 1773, 1983 }, quest = 437, radius = 400,
                  at = { { 4544, 2101 } },
                  note = "Kill Rot Hide gnolls in the Dead Field until Nightlash appears, then kill her and loot her essence. The gnolls cannot be feared." },
                { type = "collect", item = 3254, kill = { 1780 }, quest = { 447, 2 }, radius = 500,
                  at = { { 3633, 1420 }, { 3725, 1599 }, { 3567, 1601 }, { 3496, 1634 }, { 3399, 1724 },
                         { 3414, 1526 }, { 3506, 1450 }, { 3585, 1383 } },
                  note = "Moss Stalkers drop the blood. Krethis Shadowspinner, a rare spider, has a damage shield and a hard hitting shock: leave her alone unless you are a mage or warlock who can burst her down." },
                { type = "vendor", sell = true, npc = { 5748 },
                  note = "Sell your trash." },
                { type = "collect", item = 3253, kill = { 1778, 1797 }, quest = { 447, 1 }, from = "deadfield", radius = 600,
                  at = { { 4160, 2165 }, { 4137, 1964 }, { 4236, 2377 }, { 4467, 2484 }, { 4608, 2662 } },
                  note = "Ferocious and Giant Grizzled Bears drop the hearts; kill any on the way, and finish them here. Old Vicejaw, a rare bear, walks here too." },
            } },

            { title = "The Sepulcher again", steps = {
                { type = "travel", to = "The Sepulcher", at = { { 4551, 4126 } }, radius = 400 },
                { group = {
                    { type = "talk", turnin = { 422 }, accept = { 423 }, npc = { 1938 } },
                    { type = "talk", turnin = { 437 }, accept = { 438 }, npc = { 1952 } },
                    { type = "talk", turnin = { 91920 }, accept = { 91921 }, npc = { 1937 } },
                } },
                { type = "buy", item = 4605, count = 20, npc = { 5886 },
                  cond = { none = { { class = { "MAGE", "PRIEST" } } } },
                  note = "Sell your trash to Gwyn Farrow as well." },
                { type = "buy", item = 1179, count = 20, npc = { 2140 },
                  cond = { class = { "PRIEST", "WARLOCK" } } },
                { type = "buy", item = 4786, npc = { 3554 },
                  cond = { class = { "MAGE", "PRIEST", "WARLOCK" } },
                  note = "Andrea Boynton sometimes has a Wise Man's Belt. Buy it if she does, and wear it from level 15." },
                { type = "buy", item = 4788, npc = { 3552 },
                  cond = { class = "ROGUE" },
                  note = "Alexandre Lefevre sometimes has Agile Boots. Buy them if he does, and wear them from level 15." },
            } },

            { title = "The Moonrage camps and the Ivar Patch", steps = {
                { group = {
                    { type = "collect", item = 3156, kill = { 1779 }, quest = { 423, 1 }, radius = 600,
                      at = { { 4383, 3100 }, { 4422, 3155 }, { 4351, 3238 }, { 4261, 3112 }, { 4128, 3025 },
                             { 3970, 3024 }, { 3896, 2915 }, { 3828, 2710 }, { 3760, 2416 }, { 3856, 2193 },
                             { 3973, 2326 }, { 4149, 2351 }, { 4117, 2826 } },
                      note = "Down the hill west of the Sepulcher. Watch out for the Son of Arugal." },
                    { type = "collect", item = 3157, kill = { 1782 }, quest = { 423, 2 }, radius = 600,
                      at = { { 4383, 3100 }, { 4422, 3155 }, { 4351, 3238 }, { 4261, 3112 }, { 4128, 3025 },
                             { 3970, 3024 }, { 3896, 2915 }, { 3828, 2710 }, { 3760, 2416 }, { 3856, 2193 },
                             { 3973, 2326 }, { 4149, 2351 }, { 4117, 2826 } },
                      note = "Moonrage Darksouls enrage below a quarter of their health; finish them quickly." },
                } },
                { group = {
                    { type = "turnin", quests = { 91921 }, npc = { 1951 } },
                    { type = "accept", quests = { 425 }, npc = { 1950 } },
                } },
                { type = "collect", item = 3621, kill = { 1971 }, quest = { 425, 1 }, radius = 200,
                  at = { { 5154, 1391 }, { 5201, 1402 }, { 5189, 1382 } },
                  note = "Ivar the Foul is in the barn with two Ravenclaw Slaves. One of them patrols forward, so you can pull it alone. They cannot be feared." },
                { type = "turnin", quests = { 425 }, npc = { 1950 } },
                { type = "talk", object = "Corpse Laden Boat", turnin = { 438 }, accept = { 439 }, at = { { 5844, 3490 } },
                  note = "The boat is moored at the side of the old ferry dock on the lake." },
            } },

            { title = "The Sepulcher and the mine", steps = {
                { type = "travel", to = "The Sepulcher", at = { { 4551, 4126 } }, radius = 400 },
                { group = {
                    { type = "talk", turnin = { 423 }, accept = { 424 }, npc = { 1938 } },
                    { type = "turnin", quests = { 439 }, npc = { 1952 } },
                } },
                { type = "travel", to = "The mine", with = "grimson", at = { { 5648, 4594 } },
                  note = "The mine entrance is east of the road, across from the Sepulcher." },
                { type = "collect", item = 3634, kill = { 1972 }, quest = { 424, 1 }, label = "grimson",
                  at = { { 5858, 4486 } },
                  note = "Grimson the Pale is at the back of the mine. Kill him and take his head." },
                { type = "talk", object = "Dalaran Crate", turnin = { 477 }, accept = { 478 }, at = { { 4989, 6033 } },
                  note = "The crate is in the Dalaran camp by Pyrewood Village, to the south. The Dalaran Apprentices cast Frostbolt and run at low health; pull them back and kill them one at a time until you can open the crate safely." },
            } },

            { title = "Leaving the Sepulcher", steps = {
                { type = "travel", to = "The Sepulcher", at = { { 4551, 4126 } }, radius = 400,
                  note = "Without hardcore rules, dying and taking the spirit healer's resurrection is the quick way back." },
                { group = {
                    { type = "talk", turnin = { 478 }, accept = { 481 }, npc = { 2121 } },
                    { type = "talk", turnin = { 424, 481 }, accept = { 482 }, npc = { 1938 } },
                    { type = "turnin", quests = { 482 }, npc = { 2121 } },
                } },
                { type = "talk", turnin = { 6321 }, accept = { 6323 }, npc = { 2226 }, cond = { race = "scourge" } },
                { type = "flight", node = 10, npc = { 2226 }, cond = { none = { { race = "scourge" } } },
                  note = "Take the flight path from Karos Razok and fly to the Undercity; keep your hearthstone for Razor Hill." },
            } },

            { title = "The Undercity", map = 1458, steps = {
                { type = "travel", to = "Undercity", zone = 1458, at = { { 6774, 3789 } }, radius = 400,
                  note = "Undead: hearth to the Undercity. Everyone else: fly there from Karos Razok." },
                { type = "talk", turnin = { 6323 }, accept = { 6322 }, npc = { 4556 }, cond = { race = "scourge" } },
                { type = "buy", item = 2027, npc = { 4557 }, cond = { class = "ROGUE" },
                  note = "The Scimitar costs 38 silver 15 copper; the auction house may have something better for less. Equip it." },
                { type = "turnin", quests = { 6322 }, npc = { 4551 }, cond = { race = "scourge" } },
                { type = "train", skill = 129, npc = { 4591 },
                  note = "Make Linen Bandages to 40, learn Heavy Linen Bandage and make those to 50, then train Journeyman First Aid from her. Skip it if you already have it." },
                { type = "talk", turnin = { 1886 }, accept = { 1898 }, npc = { 6467 }, optional = true,
                  cond = { class = "ROGUE", race = "scourge" } },
                { type = "accept", quests = { 1898 }, npc = { 6467 }, cond = { class = "ROGUE", race = "scourge" } },
                { type = "note", npc = { 4582 }, cond = { class = "ROGUE" },
                  note = "Train your new ranks from Carolyn Ward." },
                { type = "talk", turnin = { 1898 }, accept = { 1899 }, npc = { 6522 }, cond = { class = "ROGUE", race = "scourge" } },
                { type = "collect", item = 7294, quest = { 1899, 1 }, object = "Andron's Bookshelf",
                  cond = { class = "ROGUE", race = "scourge" }, at = { { 5543, 7687 } },
                  note = "The bookshelf is behind Andron Gant." },
                { type = "accept", quests = { 97891 }, npc = { 7683 } },
                { type = "turnin", quests = { 97891 }, npc = { 11044 },
                  note = "Speak with him, then hand the quest in." },
                { group = {
                    { type = "turnin", quests = { 447 }, npc = { 2055 } },
                    { type = "talk", turnin = { 1359 }, accept = { 1358 }, npc = { 5204 } },
                } },
                { type = "talk", turnin = { 1899 }, accept = { 1978 }, npc = { 6467 }, cond = { class = "ROGUE", race = "scourge" } },
                { type = "turnin", quests = { 1978 }, npc = { 2425 }, cond = { class = "ROGUE", race = "scourge" } },
                { type = "note", npc = { 4568 }, cond = { class = "MAGE" },
                  note = "Train your new ranks from Anastasia Hartwell." },
                { type = "note", npc = { 4565 }, cond = { class = "WARLOCK" },
                  note = "Train your new ranks from Richard Kerwin." },
                { type = "note", npc = { 4608 }, cond = { class = "PRIEST" },
                  note = "Train your new ranks from Father Lazarus." },
                { type = "note", npc = { 4595 }, cond = { class = "WARRIOR" },
                  note = "Train your new ranks from Baltus Fowler." },
                { type = "buy", item = 5208, npc = { 5754 }, cond = { class = { "MAGE", "PRIEST", "WARLOCK" } },
                  note = "The Smoldering Wand costs 35 silver 15 copper; the auction house may have something better for less. Equip it at level 15." },
            } },

            { title = "To Durotar", map = 1411, steps = {
                { type = "travel", to = "Tirisfal Glades", zone = 1420, at = { { 6192, 6485, map = 1420 } }, radius = 300,
                  note = "Leave the city through the throne room." },
                { type = "note", note = "Ragefire Chasm fits here if you can find a group: NuuRoad's Ragefire Chasm guide starts in Orgrimmar. Come back to this guide after it." },
                { type = "travel", to = "Durotar", zone = 1411, cond = { race = "scourge" },
                  at = { { 6060, 5850, map = 1420 } }, radius = 300,
                  note = "Take the zeppelin to Orgrimmar from the tower east of the Undercity. Make bandages while you wait." },
                { type = "travel", to = "Razor Hill", at = { { 5080, 4360 } }, radius = 400,
                  note = "Undead: walk south from the zeppelin tower. Everyone else: hearth to Razor Hill." },
                { type = "accept", quests = { 840 }, npc = { 3336 } },
                { type = "travel", to = "Far Watch Post", at = { { 6227, 1938, map = 1413 } }, radius = 300,
                  note = "West over the bridge into the Barrens." },
                { type = "talk", turnin = { 840 }, accept = { 842 }, npc = { 3337 } },
                { type = "finish", note = "Silverpine Forest is done. Continue with The Barrens and Stonetalon. Sample for Helbrim goes to Apothecary Helbrim at the Crossroads." },
            } },
        },

        npcs = {
            [1421] = { -- Silverpine Forest
                [1937] = { name = "Apothecary Renferrel", at = { 4279, 4087 }, note = "In the crypt." },
                [1938] = { name = "Dalar Dawnweaver", at = { 4420, 3979 } },
                [1950] = { name = "Rane Yorick", at = { 5346, 1345 }, note = "Outside the house at the Ivar Patch." },
                [1951] = { name = "Quinn Yorick", at = { 5343, 1259 }, note = "On the second floor of the house at the Ivar Patch." },
                [1952] = { name = "High Executor Hadrec", at = { 4342, 4087 },
                           note = "Down in the crypt. The way in is round the east side of the building." },
                [1978] = { name = "Deathstalker Erland", at = { 5618, 918 } },
                [2121] = { name = "Shadow Priest Allister", at = { 4398, 4093 } },
                [2140] = { name = "Edwin Harly", at = { 4398, 3990 } },
                [2226] = { name = "Karos Razok", at = { 4562, 4258 } },
                [3552] = { name = "Alexandre Lefevre", at = { 4460, 3911 } },
                [3554] = { name = "Andrea Boynton", at = { 4480, 3924 } },
                [5748] = { name = "Killian Sanatha", at = { 3300, 1784 }, note = "At the fishing hut on the shore." },
                [5886] = { name = "Gwyn Farrow", at = { 4404, 3977 } },
                [6389] = { name = "Deathguard Podrig", at = { 4342, 4168 } },

                [1765] = "Worg",
                [1766] = "Mottled Worg",
                [1767] = "Vile Fin Shredder",
                [1768] = "Vile Fin Tidehunter",
                [1769] = "Moonrage Whitescalp",
                [1772] = "Rot Hide Gladerunner",
                [1773] = "Rot Hide Mystic",
                [1778] = "Ferocious Grizzled Bear",
                [1779] = "Moonrage Glutton",
                [1780] = "Moss Stalker",
                [1782] = "Moonrage Darksoul",
                [1797] = "Giant Grizzled Bear",
                [1971] = "Ivar the Foul",
                [1972] = "Grimson the Pale",
                [1983] = "Nightlash",
                [6497] = "Astor Hadren",
            },
            [1458] = { -- Undercity
                [2055] = { name = "Master Apothecary Faranell", at = { 4884, 6925 } },
                [2425] = { name = "Varimathras", at = { 5626, 9219 }, note = "In the Royal Quarter." },
                [4551] = { name = "Michael Garrett", at = { 6327, 4855 } },
                [4556] = { name = "Gordon Wendham", at = { 6148, 4181 }, note = "In the Trade Quarter." },
                [4557] = { name = "Louis Warren", at = { 6115, 4088 } },
                [4565] = { name = "Richard Kerwin", at = { 8891, 1586 } },
                [4568] = { name = "Anastasia Hartwell", at = { 8512, 1007 } },
                [4582] = { name = "Carolyn Ward", at = { 8386, 7207 } },
                [4591] = { name = "Mary Edras", at = { 7316, 5515 }, note = "In the Rogues' Quarter." },
                [4595] = { name = "Baltus Fowler", at = { 4740, 1729 } },
                [4608] = { name = "Father Lazarus", at = { 4757, 1890 } },
                [5204] = { name = "Apothecary Zinge", at = { 5014, 6797 } },
                [5754] = { name = "Zane Bradford", at = { 6956, 2694 } },
                [6467] = { name = "Mennet Carkad", at = { 8352, 6910 } },
                [6522] = { name = "Andron Gant", at = { 5484, 7631 } },
                [7683] = { name = "Alessandro Luca", at = { 5861, 5468 } },
                [11044] = { name = "Doctor Martin Felben", at = { 4661, 7409 }, note = "In the Apothecarium." },
            },
            [1411] = { -- Durotar
                [3336] = { name = "Takrin Pathseeker", at = { 5080, 4360 } },
            },
            [1413] = { -- The Barrens
                [3337] = { name = "Kargal Battlescar", at = { 6227, 1938 } },
            },
        },
    },
})
