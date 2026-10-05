-- A packaged guide, in guide format v1 (docs/examples/guide-v1.lua).
--
-- Horde 28-30 leveling route through Thousand Needles, from Thunder Bluff to the
-- Shimmering Flats, with a run to Feralas and Tanaris for their flight paths and
-- the closing trip by way of Ratchet, Booty Bay and Orgrimmar. Ported from the
-- second half of RestedXP's Classic "26-30 Ashenvale / Thousand Needles": it
-- picks up where that route leaves Ashenvale (the Ashenvale half is its own
-- guide) and ends at the level 30 cap. "28-30 Thousand Needles JJ" was read to
-- cross-check. You arrive at about 27 or 28.
--
-- The source is Classic, not Forever. Quest, NPC, item and object IDs and the
-- NPC positions were checked against Questie's Forever database (db/questie),
-- ForeverGuide's Forever overlay (which marks the quests the client lacks) and
-- the Forever client tables (QuestV2, ItemSparse, TaxiNodes). No Forever-only
-- quest is known for Thousand Needles, Feralas or Tanaris at these levels.
--
-- Notes:
--   * The Thunder Bluff stop at the start (The Sacred Flame, Steelsnap, The
--     Flying Machine Airport): a player whose Ashenvale guide already made it
--     has nothing to hand in there, and those turn-ins pass. Only the second
--     Thunder Bluff visit keeps class trainer steps: a trainer step cannot tell
--     whether the ranks were bought.
--   * A Different Approach, A Dip in the Moonwell and Testing the Tonic (9431,
--     9433, 9434) are Burning Crusade quests that the Forever client does not
--     have. They are left out, and with them the Thundering Boulderkin, the
--     Robotron and the Thalanaar moonwell. Hypercapacitor Gizmo comes straight
--     from Wizlo Bearingshiner, as it did before them.
--   * Calling in the Reserves ends at Grish Longrunner, who stands beside Brave
--     Moonhorn in Thousand Needles; the source gives his spot in Barrens
--     coordinates (CompareGuideOrder reports the map, on purpose).
--   * Goblin Sponsorship ends at Gazlowe in Ratchet and the next part starts
--     there; the source skips that visit. It is added here.
--   * The second Unrefined Ore Sample step (the kobolds at 9.2, 21.0) is the
--     source's later `.collect 5842`, which names no quest; CompareGuideOrder
--     matches it to the first ore sample step and reports it, on purpose.
--   * Mahren Skyseer and Isha Awak are offered to everyone who carries Mahren
--     Skyseer, not only warriors: every class passes Ratchet here.
--   * The cap is 30. Kept: everything a level 30 can finish. Left out, as level
--     30+ content: Frostmaw (37), Test of Lore (the source abandons it later;
--     NuuRoad never asks for an abandon, so it is simply not taken), Martek the
--     Exiled and Encrusted Tail Fins (35), the Silithid hive (The Swarm Grows
--     and Parts of the Swarm in the Shimmering Flats, 35), the next Goblin
--     Sponsorship (Fuel Regulator Blueprints, 37), the Booty Bay pickups
--     (Supply and Demand, Singing Blue Shards, Bloodscalp Ears, Hostile
--     Takeover, Investigate the Camp), the turtle meat the source saves for
--     later, the Warrior's Brutal Armor abandon and the riding and mount steps
--     (Burning Crusade only in the source).
--   * Kept as pickups that carry on past 30: Parts for Kravel, Hemet
--     Nesingwary, The Swarm Grows (Belgrom to Moktar Krin), Alliance Relations,
--     and the class quests the source starts here: The Islander and The Affray
--     (warrior, whose Windwatcher chain goes on), Call of Water and Call of Air
--     (shaman), Seeking Strahad and Tome of the Cabal (warlock).
--   * The source grinds to 30 before the Shimmering Flats. Here the grind step
--     counts the racetrack turn-ins, so the quests bring you to the cap rather
--     than overshooting it.
--   * The rogue trains in Booty Bay; the source's second rogue trainer stop in
--     Orgrimmar is left out. The source's warrior and shaman hearth in the
--     Valley of Strength is left out (the guide ends there).
--   * Weapon purchases (Sturdy Recurve, Dense Shortbow, Merciless Axe, Big
--     Stick, Staff of Protection) are notes: the vendors are not verified.
--   * Test of Faith: Dorn's ritual moves you onto a high wooden platform and
--     walking off its end returns you safely. That is not a death.
--
-- Check in client:
--   * Objective numbers follow the source's `part` (Galak 1 scouts, 2
--     wranglers, 3 windchasers; basilisks 1, crystalhides 2, gazers 3; secret
--     notes 1 to 3). The source's counts (Galak 12/10/6, eggs 10, agave 10,
--     racetrack 30/6/10/9, basilisks 10/10/6) are dropped: the objective
--     counts. Questie's Forever data has no counts for these quests.
--   * The grind target 28 + 25000 experience follows the source's Classic
--     experience table.
--   * The Horde paladin trainer in Orgrimmar (no Forever ID known; the step
--     stands at the source's spot, 32.4, 35.8).
--   * Craven Drok: Questie puts him at 51.3, 45.9 in Orgrimmar, the source at
--     49.8, 47.6.
--   * The hearth bind location at Freewind Post: area 484 (Freewind Post).
--   * Thousand Needles, Feralas, Tanaris and Booty Bay flight masters are not in
--     Data/Travel.lua yet, so the planner cannot route through them.
--
-- Maps: 1441 Thousand Needles (guide default), 1456 Thunder Bluff, 1413 The
-- Barrens, 1444 Feralas, 1446 Tanaris, 1434 Stranglethorn Vale, 1454 Orgrimmar.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    schema = 1,

    id = "nuuroad:leveling:horde-thousand-needles-28-30",
    updated = 1790974800,
    title = "Thousand Needles",
    category = "Leveling/Thousand Needles",
    author = "NuuRoad",
    tags = { "horde", "thousand needles", "freewind post", "shimmering flats", "thunder bluff" },
    levels = { from = 28, to = 30 },
    cond = { faction = "Horde" },
    source = "Ported from the second half of RestedXP's Classic \"26-30 Ashenvale / Thousand Needles\", cross-checked with \"28-30 Thousand Needles JJ\"; IDs checked against Questie's Forever database, ForeverGuide and the Forever client tables.",

    data = {
        map = 1441,

        sections = {
            { title = "Thunder Bluff", map = 1456, steps = {
                { type = "travel", to = "Thunder Bluff", zone = 1456, at = { { 4581, 6471 } }, radius = 400,
                  note = "Hearth to Thunder Bluff from Ashenvale. Rogues fly there by way of Orgrimmar." },
                { group = {
                    { type = "talk", turnin = { 1195 }, accept = { 1196 }, npc = { 4721 } },
                    { type = "turnin", quests = { 1086 }, npc = { 3419 } },
                    { type = "accept", quests = { 1131 }, npc = { 3441 } },
                } },
                { type = "note", note = "Hunters: the bow vendors here sometimes sell a Sturdy Recurve. Warriors and shamans who missed a Merciless Axe in Hillsbrad can look for one at the weapon vendors." },
                { type = "travel", to = "Camp Taurajo", area = 378, at = { { 4445, 5915, map = 1413 } }, radius = 400,
                  note = "Fly to Camp Taurajo from Tal, on the totem tower." },
            } },

            { title = "To Thousand Needles", steps = {
                { type = "talk", turnin = { 1534 }, accept = { 220 }, npc = { 5899 }, cond = { class = "SHAMAN" } },
                { group = {
                    { type = "turnin", quests = { 5881 }, npc = { 12576 } },
                    { type = "accept", quests = { 4542 }, npc = { 10079 } },
                } },
                { type = "collect", item = 12564, starts = 4881, kill = { 10617 }, sticky = true,
                  note = "The Galak Messenger walks between the centaur camps. If you see him, kill him and loot his note; it starts a quest. You look for him properly later." },
                { type = "travel", to = "Freewind Post", area = 484, at = { { 4600, 5150 } }, radius = 300,
                  note = "Ride the Great Lift down, follow the road east and take Freewind Post's lift up the mesa." },
            } },

            { title = "Freewind Post", steps = {
                { group = {
                    { type = "accept", quests = { 5147 }, object = "Wanted Poster - Arnak Grimtotem", at = { { 4600, 5086 } } },
                    { type = "talk", turnin = { 1196 }, accept = { 1197 }, npc = { 4722 } },
                    { type = "talk", turnin = { 4542 }, accept = { 4841 }, npc = { 10537 } },
                    { type = "accept", quests = { 4767 }, npc = { 10377 } },
                    { type = "accept", quests = { 4821 }, npc = { 10539 } },
                } },
                { type = "note", note = "Hunters: the bow vendor here sometimes has a Dense Shortbow." },
                { type = "flight", node = 30, npc = { 4317 } },
            } },

            { title = "Galak Hold and Dorn", steps = {
                { type = "travel", to = "Galak Hold", at = { { 4400, 3740 } }, radius = 300,
                  note = "The Galak cave is north of Freewind Post. Keep to the left side and kill centaurs on the way in." },
                { type = "collect", item = 5869, quest = { 1197, 1 }, object = "Ancient Brazier", at = { { 4201, 3147 } },
                  note = "Take the left turn where the tunnels meet. The brazier is at the far end of the caves." },
                { group = {
                    { type = "kill", kill = { 4096 }, quest = { 4841, 3 }, radius = 600,
                      at = { { 4130, 3770 }, { 4210, 3790 }, { 4470, 3620 }, { 4880, 4170 } } },
                    { type = "kill", kill = { 4094 }, quest = { 4841, 1 }, radius = 600,
                      at = { { 4130, 3770 }, { 3980, 3460 }, { 4060, 3680 }, { 4550, 4350 } } },
                    { type = "kill", kill = { 4093 }, quest = { 4841, 2 }, radius = 600,
                      at = { { 4130, 3770 }, { 3990, 3800 }, { 4450, 3960 }, { 4870, 4110 } } },
                } },
                { type = "travel", to = "Dorn Plainstalker's cave", at = { { 5460, 4430 } }, radius = 200, with = "dorn",
                  note = "Run up the path here; Dorn is inside the cave above." },
                { type = "accept", quests = { 1149 }, npc = { 2986 }, label = "dorn" },
                { type = "travel", to = "Dorn's ritual", quest = 1149, at = { { 2663, 3423 } }, radius = 300,
                  note = "Wait out Dorn's ritual: it carries you to a high wooden platform. Walk off its end; you are caught and brought back instead of falling." },
                { type = "talk", turnin = { 1149 }, accept = { 1150 }, npc = { 2986 } },
            } },

            { title = "The Gravelsnout kobolds", steps = {
                { type = "collect", item = 5842, kill = { 4113, 4116, 14427 }, quest = { 1153, 1 }, radius = 600,
                  at = { { 6574, 4989 }, { 6787, 5833 }, { 6603, 6214 }, { 5895, 5784 } },
                  note = "Gravelsnout Diggers and Surveyors, and the rare Gibblesnik, drop the Unrefined Ore Sample for A New Ore Sample. If you do not have the quest, skip this; you get another chance later." },
                { type = "collect", item = 12467, quest = { 4821, 1 }, object = "Alien Egg", radius = 200,
                  at = { { 5636, 5039 }, { 5234, 5525 }, { 3763, 5613 } },
                  note = "The egg looks like a clutch of spider eggs and lies in one of these camps." },
            } },

            { title = "Freewind Post again", steps = {
                { group = {
                    { type = "talk", turnin = { 4841 }, accept = { 5064 }, npc = { 10537 } },
                    { type = "turnin", quests = { 1197 }, npc = { 4722 } },
                    { type = "talk", turnin = { 4821 }, accept = { 4865 }, npc = { 10539 } },
                } },
            } },

            { title = "Grenka and Highperch", steps = {
                { type = "travel", to = "Roguefeather Den", at = { { 2730, 5120 } }, radius = 200,
                  note = "Go down from Freewind Post and west to the path up at 27.7, 50.0, then into the cave. The harpies here can silence everyone around them." },
                { type = "collect", item = 5843, kill = { 4490 }, quest = { 1150, 1 }, at = { { 2590, 5460 } },
                  note = "Open the crate at the end of the cave. Grenka Bloodscreech comes out; kill her and loot her claw." },
                { type = "travel", to = "Highperch", at = { { 1320, 3970 } }, radius = 200,
                  note = "Leave the cave, run up the path at 13.9, 31.7 and on up at 13.2, 39.7." },
                { type = "accept", quests = { 4770 }, npc = { 10427 }, label = "eggs",
                  note = "Accepting starts an escort. Try to have five or six eggs first, so you can finish them on the way out." },
                { type = "escort", quest = 4770, npc = { 10427 }, at = { { 1515, 3265 } },
                  note = "Take Pao'ka down the mountain. Three wyverns attack half way down." },
                { type = "collect", item = 12356, quest = { 4767, 1 }, object = "Highperch Wyvern Egg", from = "eggs", radius = 400,
                  at = { { 1080, 3470 }, { 1111, 3454 }, { 1219, 3613 }, { 1256, 3737 }, { 1757, 4225 } },
                  note = "Pick up every Highperch Wyvern Egg you pass on the ground. Finish the eggs here." },
                { group = {
                    { type = "talk", turnin = { 4865, 4770 }, accept = { 5062 }, npc = { 10428 } },
                    { type = "accept", quests = { 5151 }, npc = { 10941 } },
                } },
            } },

            { title = "Steelsnap and the Galak Messenger", steps = {
                { type = "level", level = 28, xp = 25000, label = "steelsnap", radius = 600,
                  at = { { 1870, 2220 }, { 1710, 1840 }, { 1830, 2680 } },
                  note = "Grind on the centaurs and kobolds here." },
                { type = "collect", item = 5837, kill = { 4548 }, quest = { 1131, 1 }, from = "steelsnap", radius = 400,
                  at = { { 1090, 2320 }, { 1710, 1840 }, { 1830, 2680 }, { 1520, 3050 } },
                  note = "Steelsnap, a hyena, patrols the hills to the north and west. Kill him and take his rib if you see him. He walks counter-clockwise around these points." },
                { type = "collect", item = 12564, starts = 4881, kill = { 10617 }, radius = 400,
                  at = { { 1840, 2220 }, { 2520, 3380 }, { 3600, 2900 }, { 3960, 3360 } },
                  note = "The Galak Messenger starts at one centaur camp, follows the road and goes to the other. Kill him and loot his note." },
                { type = "accept", quests = { 4881 }, item = 12564, note = "Use the Assassination Note to start its quest." },
                { type = "collect", item = 12732, quest = { 5062, 1 }, object = "Incendia Agave", radius = 400,
                  at = { { 3750, 3840 }, { 3350, 3240 }, { 3659, 3877 }, { 3495, 3321 } },
                  note = "The yellow plants grow at the edges of the pool and under the water. The fire elementals here resist fire and are immune to frost; avoid them." },
            } },

            { title = "Thunder Bluff again", map = 1456, steps = {
                { type = "travel", to = "Thunder Bluff", zone = 1456, at = { { 4581, 6471 } }, radius = 400,
                  note = "Hearth to Thunder Bluff, or fly there from Freewind Post if it is on cooldown." },
                { type = "note", npc = { 3033 }, cond = { class = "DRUID" }, note = "Train your new ranks from Turak Runetotem." },
                { type = "note", npc = { 3040 }, cond = { class = "HUNTER" }, note = "Train your new ranks from Urek Thunderhorn." },
                { type = "note", npc = { 10086 }, cond = { class = "HUNTER" }, note = "Train your pet's new ranks from Hesuwa Thunderhorn." },
                { type = "note", npc = { 3043 }, cond = { class = "WARRIOR" }, note = "Train your new ranks from Ker Ragetotem." },
                { type = "note", npc = { 3030 }, cond = { class = "SHAMAN" }, note = "Train your new ranks from Siln Skychaser." },
                { type = "note", npc = { 3045 }, cond = { class = "PRIEST" }, note = "Train your new ranks from Malakai Cross." },
                { type = "note", npc = { 3049 }, cond = { class = "MAGE" }, note = "Train your new ranks from Thurston Xane." },
                { group = {
                    { type = "turnin", quests = { 1131 }, npc = { 3441 } },
                    { type = "talk", turnin = { 5062 }, accept = { 5088 }, npc = { 4046 } },
                } },
                { type = "travel", to = "Camp Taurajo", area = 378, at = { { 4445, 5915, map = 1413 } }, radius = 400,
                  note = "Fly to Camp Taurajo to hand in the ore sample. Skip this if it is not ready yet." },
                { type = "turnin", quests = { 1153 }, npc = { 3433 } },
                { type = "travel", to = "Freewind Post", area = 484, at = { { 4514, 4911, map = 1441 } }, radius = 300,
                  note = "Fly to Freewind Post." },
            } },

            { title = "Darkcloud Pinnacle", steps = {
                { type = "turnin", quests = { 4767 }, npc = { 10377 } },
                { type = "hearth", area = 484, npc = { 11116 }, cond = { none = { { class = "WARRIOR" } } } },
                { type = "talk", turnin = { 1150 }, accept = { 1151 }, npc = { 2986 },
                  note = "Keep killing Gravelsnout kobolds for the ore sample if you still need it." },
                { type = "collect", item = 5844, kill = { 4499 }, quest = { 1151, 1 }, radius = 500,
                  at = { { 2930, 3360 }, { 2710, 2870 }, { 2250, 3130 }, { 1750, 2700 }, { 1280, 2090 },
                         { 930, 2100 }, { 2110, 4060 }, { 3430, 3750 }, { 3320, 5350 } },
                  note = "Rok'Alim the Pounder is an elite rock elemental who walks a wide circle around western Thousand Needles." },
                { type = "travel", to = "Darkcloud Pinnacle", at = { { 3120, 3690 } }, radius = 200,
                  note = "Run up the path here to the Grimtotem bridges." },
                { group = {
                    { type = "collect", item = 12765, quest = { 5064, 1 }, object = "Document Chest", at = { { 3179, 3258 } } },
                    { type = "collect", item = 12766, quest = { 5064, 2 }, object = "Document Chest", at = { { 3376, 3999 } } },
                    { type = "collect", item = 12768, quest = { 5064, 3 }, object = "Document Chest", at = { { 3934, 4153 } } },
                } },
                { type = "collect", item = 12925, kill = { 10882 }, quest = 5088, at = { { 3809, 3538 } },
                  note = "Clear the Grimtotem around the bonfire, use the Incendia Powder to light the Sacred Fire of Life, then kill Arikara and loot her skin. She is elite." },
                { type = "collect", item = 12884, kill = { 10896 }, quest = { 5147, 1 }, at = { { 3811, 2687 } } },
                { type = "accept", quests = { 4904 }, npc = { 10646 } },
                { type = "escort", quest = 4904, npc = { 10646 }, at = { { 3093, 3712 } },
                  note = "Keep Lakota Windsong alive across the pinnacle. Grimtotem spawn on the platforms as you go." },
                { type = "collect", item = 12946, kill = { 10992 }, quest = 5151, at = { { 2330, 2330 } },
                  note = "Open the panther cage with Wizlo's key and kill the Enraged Panther. It is elite; have your cooldowns and potions ready." },
                { type = "talk", turnin = { 4881 }, accept = { 4966 }, npc = { 10638 },
                  note = "Three Galak Assassins appear as soon as you take the next quest." },
                { type = "kill", kill = { 10720 }, quest = { 4966, 1 }, at = { { 2140, 3180 } },
                  note = "Let Kanati take their attention, then kill them." },
                { group = {
                    { type = "turnin", quests = { 4966 }, npc = { 10638 } },
                    { type = "turnin", quests = { 5088 }, npc = { 10428 } },
                    { type = "turnin", quests = { 5151 }, npc = { 10941 } },
                } },
                { type = "collect", item = 5842, kill = { 4113, 4116 }, quest = { 1153, 1 }, radius = 400,
                  at = { { 920, 2100 }, { 1185, 2131 }, { 1241, 1401 } },
                  note = "Gravelsnout Diggers and Surveyors here drop the Unrefined Ore Sample, if you still need it." },
            } },

            { title = "Feralas and back", steps = {
                { type = "travel", to = "Camp Mojache", area = 1099, at = { { 7545, 4436, map = 1444 } }, radius = 300,
                  note = "Run west into Feralas, through 88.9, 41.2, for the flight path." },
                { type = "flight", node = 42, npc = { 8020 } },
                { type = "travel", to = "Freewind Post", area = 484, at = { { 4514, 4911 } }, radius = 300,
                  note = "Fly back to Freewind Post." },
                { group = {
                    { type = "turnin", quests = { 5064, 5147 }, npc = { 10537 } },
                    { type = "turnin", quests = { 4904 }, npc = { 10645 } },
                } },
                { type = "turnin", quests = { 1151 }, npc = { 2986 },
                  note = "Dorn offers Test of Lore next. It belongs to later levels; leave it." },
            } },

            { title = "The Shimmering Flats", steps = {
                { type = "level", level = 30, by = "racetrack", radius = 600,
                  at = { { 6760, 6400 }, { 6574, 4989 }, { 6787, 5833 } },
                  note = "Grind on the way down so the racetrack turn-ins ahead bring you to 30. Experience past the cap is lost." },
                { group = {
                    { type = "accept", quests = { 1110, 1111, 5762 }, npc = { 4452 } },
                    { type = "accept", quests = { 1104 }, npc = { 4454 } },
                    { type = "accept", quests = { 1105 }, npc = { 4453 } },
                    { type = "accept", quests = { 1176 }, npc = { 4630 } },
                    { type = "accept", quests = { 1175 }, npc = { 4629 } },
                } },
                { group = {
                    { type = "kill", kill = { 4150 }, quest = { 1175, 3 }, radius = 500,
                      at = { { 7840, 8910 }, { 7690, 8940 }, { 7290, 8790 }, { 7860, 9030 } },
                      note = "Saltstone Gazers in the south of the flats. They are a few levels above you." },
                    { type = "collect", item = 5798, quest = { 1110, 1 }, object = "Rocket Car Rubble", radius = 600,
                      at = { { 7306, 5966 }, { 7955, 5912 }, { 8727, 7347 }, { 8375, 8666 }, { 7631, 8951 } } },
                    { type = "collect", item = 5794, kill = { 4139, 4140 }, quest = { 1104, 1 }, radius = 600,
                      at = { { 8450, 6143 }, { 8268, 6909 }, { 8657, 6857 }, { 8140, 8683 } } },
                    { type = "collect", item = 5848, kill = { 4154, 4158 }, quest = { 1176, 1 }, radius = 600,
                      at = { { 8071, 5947 }, { 7372, 5886 }, { 8299, 7069 }, { 7116, 7922 } } },
                    { type = "collect", item = 5795, kill = { 4142, 4143, 4144 }, quest = { 1105, 1 }, radius = 600,
                      at = { { 8133, 5268 }, { 7757, 5392 }, { 8377, 6074 }, { 7989, 8572 } } },
                    { type = "kill", kill = { 4147 }, quest = { 1175, 1 }, radius = 600,
                      at = { { 7690, 5760 }, { 7630, 5290 }, { 7740, 5960 }, { 6870, 6190 } } },
                    { type = "kill", kill = { 4151 }, quest = { 1175, 2 }, radius = 600,
                      at = { { 8350, 6520 }, { 8000, 7050 }, { 8590, 5850 }, { 7940, 8960 } } },
                } },
                { label = "racetrack", group = {
                    { type = "turnin", quests = { 1110 }, npc = { 4452 } },
                    { type = "turnin", quests = { 1104 }, npc = { 4454 } },
                    { type = "turnin", quests = { 1105 }, npc = { 4453 } },
                    { type = "talk", turnin = { 1176 }, accept = { 1178 }, npc = { 4630 } },
                    { type = "turnin", quests = { 1175 }, npc = { 4629 } },
                } },
                { type = "note", note = "Fizzle and Wizzle offer Martek the Exiled and Encrusted Tail Fins next. Both are level 35 quests; leave them." },
            } },

            { title = "Tanaris", steps = {
                { type = "travel", to = "Gadgetzan", area = 976, at = { { 5160, 2544, map = 1446 } }, radius = 300,
                  note = "Follow the flats south-east into Tanaris for the flight path." },
                { type = "flight", node = 40, npc = { 7824 } },
                { type = "travel", to = "Freewind Post", area = 484, at = { { 4607, 5152 } }, radius = 300,
                  cond = { none = { { class = "WARRIOR" } } },
                  note = "Hearth to Freewind Post, or fly there if it is on cooldown." },
                { type = "travel", to = "Camp Taurajo", area = 378, at = { { 4445, 5915, map = 1413 } }, radius = 400,
                  cond = { none = { { class = "WARRIOR" } } },
                  note = "Fly to Camp Taurajo." },
            } },

            { title = "Thunder Bluff for warriors", map = 1456, steps = {
                { type = "travel", to = "Thunder Bluff", zone = 1456, at = { { 4665, 4990 } }, radius = 400,
                  cond = { class = "WARRIOR" },
                  note = "Hearth or fly to Thunder Bluff." },
                { type = "accept", quests = { 1718 }, npc = { 3041 }, cond = { class = "WARRIOR" } },
                { type = "note", npc = { 3043 }, cond = { class = "WARRIOR" }, note = "Train your level 30 ranks from Ker Ragetotem." },
                { type = "travel", to = "Camp Taurajo", area = 378, at = { { 4445, 5915, map = 1413 } }, radius = 400,
                  cond = { class = "WARRIOR" },
                  note = "Fly to Camp Taurajo." },
            } },

            { title = "The Barrens", map = 1413, steps = {
                { type = "turnin", quests = { 1153 }, npc = { 3433 } },
                { type = "travel", to = "The Crossroads", area = 380, at = { { 5150, 3034 } }, radius = 400,
                  note = "Fly to the Crossroads." },
                { type = "accept", quests = { 1145 }, npc = { 3428 } },
                { type = "hearth", area = 380, npc = { 3934 }, cond = { none = { { class = { "SHAMAN", "WARRIOR" } } } } },
                { type = "travel", to = "Ratchet", area = 392, at = { { 6308, 3716 } }, radius = 400,
                  note = "Fly to Ratchet." },
                { type = "talk", turnin = { 1111 }, accept = { 1112 }, npc = { 3453 } },
                { type = "talk", turnin = { 1178 }, accept = { 1180 }, npc = { 3391 } },
                { type = "talk", turnin = { 874 }, accept = { 873 }, npc = { 3388 } },
                { type = "collect", item = 5104, kill = { 3476 }, quest = { 873, 1 }, radius = 400,
                  at = { { 6560, 4710 }, { 6340, 5020 }, { 6400, 5200 }, { 6330, 5420 } },
                  note = "Isha Awak, a red threshadon, swims in the bay. Kill it and loot its heart." },
                { type = "talk", turnin = { 1718 }, accept = { 1719 }, npc = { 6236 }, cond = { class = "WARRIOR" } },
                { type = "kill", kill = { 6238 }, quest = 1719, at = { { 6860, 4870 } }, cond = { class = "WARRIOR" },
                  note = "Step onto the grate to start the Affray, beat the challengers, then Big Will." },
                { type = "turnin", quests = { 1719 }, npc = { 6236 }, cond = { class = "WARRIOR" },
                  note = "The Windwatcher comes next. It is a long chain for level 30 and later; take it when you want to." },
                { type = "turnin", quests = { 873 }, npc = { 3388 } },
            } },

            { title = "Booty Bay", map = 1434, steps = {
                { type = "travel", to = "Booty Bay", area = 35, at = { { 2580, 7310 } }, radius = 400,
                  note = "Take the boat from the Ratchet dock, at 63.7, 38.6 in the Barrens." },
                { type = "note", note = "Shamans: the weapon vendor upstairs sometimes sells a Big Stick or a Staff of Protection." },
                { type = "talk", turnin = { 1180 }, accept = { 1181 }, npc = { 4631 } },
                { type = "turnin", quests = { 1181 }, npc = { 2496 },
                  note = "His next Goblin Sponsorship is a level 37 quest; leave it." },
                { type = "note", npc = { 1411 }, cond = { class = "ROGUE" }, note = "Train your level 30 ranks from Ian Strom." },
                { type = "flight", node = 18, npc = { 2858 } },
                { type = "note", note = "The Booty Bay quests (Supply and Demand, Singing Blue Shards, Bloodscalp Ears and the rest) are for later levels." },
                { type = "travel", to = "Ratchet", area = 392, at = { { 6370, 3860, map = 1413 } }, radius = 300,
                  note = "Take the boat back to Ratchet." },
            } },

            { title = "Orgrimmar", map = 1454, steps = {
                { type = "travel", to = "Orgrimmar", zone = 1454, at = { { 4529, 6389 } }, radius = 400,
                  note = "Fly to Orgrimmar from Bragok." },
                { type = "note", at = { { 3240, 3580 } }, cond = { class = "PALADIN" }, note = "Train your level 30 ranks from your paladin trainer." },
                { type = "note", npc = { 3344 }, cond = { class = "SHAMAN" }, note = "Train your level 30 ranks from Kardris Dreamseeker." },
                { type = "accept", quests = { 1531 }, npc = { 5892 }, cond = { class = "SHAMAN" } },
                { type = "note", npc = { 3352 }, cond = { class = "HUNTER" }, note = "Train your level 30 ranks from Ormak Grimshot." },
                { type = "note", npc = { 10088 }, cond = { class = "HUNTER" }, note = "Train your pet's new ranks from Xao'tsu." },
                { type = "accept", quests = { 2996 }, npc = { 5875 }, cond = { class = "WARLOCK" },
                  note = "Train your level 30 ranks from Gan'rul Bloodeye as well. Kurgul, beside him, sells the Grimoire of Lash of Pain rank 2." },
                { type = "accept", quests = { 1431 }, npc = { 5639 } },
                { type = "talk", turnin = { 1145 }, accept = { 1146 }, npc = { 4485 },
                  note = "The Swarm Grows goes on to Moktar Krin in the Shimmering Flats." },
                { type = "note", npc = { 5883 }, cond = { class = "MAGE" }, note = "Train your level 30 ranks from Enyo." },
                { type = "note", npc = { 6018 }, cond = { class = "PRIEST" }, note = "Train your level 30 ranks from Ur'kyo." },
                { type = "talk", turnin = { 1431 }, accept = { 1432 }, npc = { 5640 } },
                { type = "note", npc = { 2704 }, cond = { class = "WARRIOR" },
                  note = "Train Thrown from Hanashi, who teaches thrown weapons." },
            } },

            { title = "Ratchet for warlocks and shamans", map = 1413, steps = {
                { type = "travel", to = "Ratchet", area = 392, at = { { 6308, 3716 } }, radius = 400,
                  cond = { class = { "WARLOCK", "SHAMAN" } },
                  note = "Fly to Ratchet." },
                { type = "talk", turnin = { 2996 }, accept = { 1801 }, npc = { 6251 }, cond = { class = "WARLOCK" } },
                { type = "talk", turnin = { 220 }, accept = { 63 }, npc = { 5901 }, cond = { class = "SHAMAN" } },
                { type = "finish", note = "Thousand Needles is done, and so is the climb to 30. Still in your log for later: Parts for Kravel, Hemet Nesingwary, The Swarm Grows and Alliance Relations, and your class quests (Call of Water and Call of Air, Tome of the Cabal)." },
            } },
        },

        npcs = {
            [1441] = { -- Thousand Needles
                [2986] = { name = "Dorn Plainstalker", at = { 5400, 4150 } },
                [4317] = { name = "Nyse", at = { 4514, 4911 } },
                [4452] = { name = "Kravel Koalbeard", at = { 7780, 7730 } },
                [4453] = { name = "Wizzle Brassbolts", at = { 7810, 7710 } },
                [4454] = { name = "Fizzle Brassbolts", at = { 7810, 7710 } },
                [4629] = { name = "Trackmaster Zherin", at = { 8160, 7800 } },
                [4630] = { name = "Pozzik", at = { 8020, 7590 } },
                [4722] = { name = "Rau Cliffrunner", at = { 4610, 5170 } },
                [10079] = { name = "Brave Moonhorn", at = { 3220, 2220 } },
                [10377] = { name = "Elu", at = { 4490, 4890 } },
                [10427] = { name = "Pao'ka Swiftmountain", at = { 1790, 4060 } },
                [10428] = { name = "Motega Firemane", at = { 2150, 3240 } },
                [10537] = { name = "Cliffwatcher Longhorn", at = { 4570, 5070 } },
                [10539] = { name = "Hagar Lightninghoof", at = { 4460, 5030 } },
                [10638] = { name = "Kanati Greycloud", at = { 2130, 3210 } },
                [10645] = { name = "Thalia Amberhide", at = { 4600, 5160 } },
                [10646] = { name = "Lakota Windsong", at = { 3800, 2650 } },
                [10941] = { name = "Wizlo Bearingshiner", at = { 2140, 3260 } },
                [11116] = { name = "Innkeeper Abeqwa", at = { 4607, 5152 } },
                [12576] = { name = "Grish Longrunner", at = { 3190, 2170 }, note = "At the top of the Great Lift." },

                [4093] = "Galak Wrangler",
                [4094] = "Galak Scout",
                [4096] = "Galak Windchaser",
                [4113] = "Gravelsnout Digger",
                [4116] = "Gravelsnout Surveyor",
                [4139] = "Scorpid Terror",
                [4140] = "Scorpid Reaver",
                [4142] = "Sparkleshell Tortoise",
                [4143] = "Sparkleshell Snapper",
                [4144] = "Sparkleshell Borer",
                [4147] = "Saltstone Basilisk",
                [4150] = "Saltstone Gazer",
                [4151] = "Saltstone Crystalhide",
                [4154] = "Salt Flats Scavenger",
                [4158] = "Salt Flats Vulture",
                [4490] = "Grenka Bloodscreech",
                [4499] = "Rok'Alim the Pounder",
                [4548] = "Steelsnap",
                [10617] = "Galak Messenger",
                [10720] = "Galak Assassin",
                [10882] = "Arikara",
                [10896] = "Arnak Grimtotem",
                [10992] = "Enraged Panther",
                [14427] = "Gibblesnik",
            },
            [1456] = { -- Thunder Bluff
                [3030] = { name = "Siln Skychaser", at = { 2282, 2111 } },
                [3033] = { name = "Turak Runetotem", at = { 7648, 2722 } },
                [3040] = { name = "Urek Thunderhorn", at = { 5913, 8687 } },
                [3041] = { name = "Torm Ragetotem", at = { 5724, 8737 } },
                [3043] = { name = "Ker Ragetotem", at = { 5758, 8550 } },
                [3045] = { name = "Malakai Cross", at = { 2456, 2257 } },
                [3049] = { name = "Thurston Xane", at = { 2518, 2096 } },
                [3419] = { name = "Apothecary Zamah", at = { 2280, 2090 }, note = "In the Pools of Vision under the Spirit Rise." },
                [3441] = { name = "Melor Stonehoof", at = { 6150, 8090 } },
                [4046] = { name = "Magatha Grimtotem", at = { 6990, 3090 }, note = "On the Elder Rise." },
                [4721] = { name = "Zangen Stonehoof", at = { 5500, 5140 } },
                [10086] = { name = "Hesuwa Thunderhorn", at = { 5409, 8399 } },
            },
            [1413] = { -- The Barrens
                [3388] = { name = "Mahren Skyseer", at = { 6580, 4390 }, note = "On the shore south of Ratchet." },
                [3391] = { name = "Gazlowe", at = { 6270, 3620 }, note = "In Ratchet." },
                [3428] = { name = "Korran", at = { 5110, 2960 } },
                [3433] = { name = "Tatternack Steelforge", at = { 4510, 5770 } },
                [3453] = { name = "Wharfmaster Dizzywig", at = { 6340, 3850 } },
                [3934] = { name = "Innkeeper Boorand Plainswind", at = { 5199, 2989 } },
                [5899] = { name = "Brine", at = { 4340, 7740 }, note = "On the way south." },
                [5901] = { name = "Islen Waterseer", at = { 6580, 4380 }, note = "On the shore south of Ratchet." },
                [6236] = { name = "Klannoc Macleod", at = { 6860, 4920 }, note = "On the island off the coast. Swim there." },
                [6251] = { name = "Strahad Farsan", at = { 6260, 3550 } },

                [3476] = "Isha Awak",
                [6238] = "Big Will",
            },
            [1454] = { -- Orgrimmar
                [2704] = { name = "Hanashi", at = { 8150, 1960 } },
                [3344] = { name = "Kardris Dreamseeker", at = { 3880, 3637 } },
                [3352] = { name = "Ormak Grimshot", at = { 6605, 1853 } },
                [4485] = { name = "Belgrom Rockmaul", at = { 7520, 3420 } },
                [5639] = { name = "Craven Drok", at = { 5130, 4590 } },
                [5640] = { name = "Keldran", at = { 2260, 5260 }, note = "In the Valley of Spirits." },
                [5875] = { name = "Gan'rul Bloodeye", at = { 4830, 4530 } },
                [5883] = { name = "Enyo", at = { 3878, 8567 } },
                [5892] = { name = "Searn Firewarder", at = { 3800, 3770 } },
                [6018] = { name = "Ur'kyo", at = { 3559, 8782 } },
                [10088] = { name = "Xao'tsu", at = { 6632, 1481 } },
            },
            [1434] = { -- Stranglethorn Vale
                [1411] = { name = "Ian Strom", at = { 2682, 7715 }, note = "In the inn." },
                [2496] = { name = "Baron Revilgaz", at = { 2720, 7690 }, note = "On the top floor of the inn." },
                [2858] = { name = "Gringer", at = { 2687, 7710 } },
                [4631] = { name = "Wharfmaster Lozgil", at = { 2640, 7360 } },
            },
            [1446] = { -- Tanaris
                [7824] = { name = "Bulkrek Ragefist", at = { 5160, 2544 } },
            },
            [1444] = { -- Feralas
                [8020] = { name = "Shyn", at = { 7545, 4436 } },
            },
        },
    },
})
