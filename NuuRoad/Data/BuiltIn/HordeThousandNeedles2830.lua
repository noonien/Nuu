local _, ns = ...

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
--     Flying Machine Airport) is gated on the quest log, so a player whose
--     Ashenvale guide already made it passes straight through. Only the second
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
--   * Objective counts follow the source (Galak 12/10/6, eggs 10, agave 10,
--     racetrack 30/6/10/9, basilisks 10/10/6). Questie's Forever data has no
--     counts for these quests.
--   * The grind target 28 + 25000 experience follows the source's Classic
--     experience table.
--   * The Horde paladin trainer in Orgrimmar (no Forever ID known; the step
--     stands at the source's spot, 32.4, 35.8).
--   * Craven Drok: Questie puts him at 51.3, 45.9 in Orgrimmar, the source at
--     49.8, 47.6.
--   * The hearth bind name at Freewind Post ("Freewind Post").
--   * Thousand Needles, Feralas, Tanaris and Booty Bay flight masters are not in
--     Data/Travel.lua yet, so the planner cannot route through them.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1441 Thousand Needles (guide default), 1456 Thunder Bluff, 1413 The
-- Barrens, 1444 Feralas, 1446 Tanaris, 1434 Stranglethorn Vale, 1454 Orgrimmar.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:leveling:horde-thousand-needles-28-30"] = {
    schema = 2,
    id = "nuuroad:leveling:horde-thousand-needles-28-30",
    updated = 1790974800,
    map = 1441,
    only = "Horde",
    meta = {
        title = "Thousand Needles",
        author = "NuuRoad",
        category = "Leveling/Thousand Needles",
        tags = { "horde", "thousand needles", "freewind post", "shimmering flats", "thunder bluff" },
        levels = { 28, 30 },
    },
    steps = {
        { section = "Thunder Bluff", map = 1456, steps = {
            { travel = "Thunder Bluff", zone = "Thunder Bluff", at = { 45.81, 64.71 }, radius = 0.04,
                note = "Hearth to Thunder Bluff from Ashenvale. Rogues fly there by way of Orgrimmar." },
            { group = {
                { turnin = 1195, accept = 1196, npc = 4721, only = "now quest 1195", at = { 55.00, 51.40 } },
                { turnin = 1086, npc = 3419, only = "now quest 1086", at = { 22.80, 20.90 },
                    note = "Apothecary Zamah is in the Pools of Vision under the Spirit Rise. Skip it if you do not have the quest." },
                { accept = 1131, npc = 3441, at = { 61.50, 80.90 } },
            } },
            { note = "Hunters: the bow vendors here sometimes sell a Sturdy Recurve. Warriors and shamans who missed a Merciless Axe in Hillsbrad can look for one at the weapon vendors." },
            { travel = "Camp Taurajo", subzone = "Camp Taurajo", at = { 44.45, 59.15, map = 1413 }, radius = 0.04,
                note = "Fly to Camp Taurajo from Tal, on the totem tower." },
        } },

        { section = "To Thousand Needles", steps = {
            { turnin = 1534, accept = 220, npc = 5899, only = "Shaman | now quest 1534", at = { 43.40, 77.40, map = 1413 },
                note = "Brine, on the way south." },
            { group = {
                { turnin = 5881, npc = 12576, only = "now quest 5881", at = { 31.90, 21.70 },
                    note = "Grish Longrunner, at the top of the Great Lift. Skip it if you do not have Calling in the Reserves." },
                { accept = 4542, npc = 10079, at = { 32.20, 22.20 } },
            } },
            { collect = 12564, starts = 4881, kill = 10617, sticky = true,
                note = "The Galak Messenger walks between the centaur camps. If you see him, kill him and loot his note; it starts a quest. You look for him properly later." },
            { travel = "Freewind Post", subzone = "Freewind Post", at = { 46.00, 51.50 }, radius = 0.03,
                note = "Ride the Great Lift down, follow the road east and take Freewind Post's lift up the mesa." },
        } },

        { section = "Freewind Post", steps = {
            { group = {
                { accept = 5147, object = "Wanted Poster - Arnak Grimtotem", at = { 46.00, 50.86 } },
                { turnin = 1196, accept = 1197, npc = 4722, only = "now quest 1196", at = { 46.10, 51.70 } },
                { turnin = 4542, accept = 4841, npc = 10537, at = { 45.70, 50.70 } },
                { accept = 4767, npc = 10377, at = { 44.90, 48.90 } },
                { accept = 4821, npc = 10539, at = { 44.60, 50.30 } },
            } },
            { note = "Hunters: the bow vendor here sometimes has a Dense Shortbow." },
            { flight = "Freewind Post", npc = 4317, at = { 45.14, 49.11 } },
        } },

        { section = "Galak Hold and Dorn", steps = {
            { travel = "Galak Hold", at = { 44.00, 37.40 }, radius = 0.03, only = "now quest 1197",
                note = "The Galak cave is north of Freewind Post. Keep to the left side and kill centaurs on the way in." },
            { objective = 1197, part = 1, collect = 5869, object = "Ancient Brazier", only = "now quest 1197", at = { 42.01, 31.47 },
                note = "Take the left turn where the tunnels meet. The brazier is at the far end of the caves." },
            { group = {
                { objective = 4841, part = 3, kill = 4096, count = 6, radius = 0.06,
                    at = { { 41.30, 37.70 }, { 42.10, 37.90 }, { 44.70, 36.20 }, { 48.80, 41.70 } } },
                { objective = 4841, part = 1, kill = 4094, count = 12, radius = 0.06,
                    at = { { 41.30, 37.70 }, { 39.80, 34.60 }, { 40.60, 36.80 }, { 45.50, 43.50 } } },
                { objective = 4841, part = 2, kill = 4093, count = 10, radius = 0.06,
                    at = { { 41.30, 37.70 }, { 39.90, 38.00 }, { 44.50, 39.60 }, { 48.70, 41.10 } } },
            } },
            { travel = "Dorn Plainstalker's cave", at = { 54.60, 44.30 }, radius = 0.02, with = "next",
                note = "Run up the path here; Dorn is inside the cave above." },
            { accept = 1149, npc = 2986, at = { 54.00, 41.50 } },
            { objective = 1149, at = { 26.63, 34.23 }, radius = 0.03,
                note = "Wait out Dorn's ritual: it carries you to a high wooden platform. Walk off its end; you are caught and brought back instead of falling." },
            { turnin = 1149, accept = 1150, npc = 2986, at = { 54.00, 41.50 } },
        } },

        { section = "The Gravelsnout kobolds", steps = {
            { objective = 1153, part = 1, collect = 5842, kill = { 4113, 4116, 14427 }, only = "now quest 1153", radius = 0.06,
                at = { { 65.74, 49.89 }, { 67.87, 58.33 }, { 66.03, 62.14 }, { 58.95, 57.84 } },
                note = "Gravelsnout Diggers and Surveyors, and the rare Gibblesnik, drop the Unrefined Ore Sample for A New Ore Sample. Skip it if you do not have the quest; you get another chance later." },
            { objective = 4821, part = 1, collect = 12467, object = "Alien Egg", radius = 0.02,
                at = { { 56.36, 50.39 }, { 52.34, 55.25 }, { 37.63, 56.13 } },
                note = "The egg looks like a clutch of spider eggs and lies in one of these camps." },
        } },

        { section = "Freewind Post again", steps = {
            { group = {
                { turnin = 4841, accept = 5064, npc = 10537, at = { 45.70, 50.70 } },
                { turnin = 1197, npc = 4722, only = "now quest 1197", at = { 46.10, 51.70 } },
                { turnin = 4821, accept = 4865, npc = 10539, at = { 44.60, 50.30 } },
            } },
        } },

        { section = "Grenka and Highperch", steps = {
            { travel = "Roguefeather Den", at = { 27.30, 51.20 }, radius = 0.02, only = "now quest 1150",
                note = "Go down from Freewind Post and west to the path up at 27.7, 50.0, then into the cave. The harpies here can silence everyone around them." },
            { objective = 1150, part = 1, collect = 5843, kill = 4490, at = { 25.90, 54.60 },
                note = "Open the crate at the end of the cave. Grenka Bloodscreech comes out; kill her and loot her claw." },
            { travel = "Highperch", at = { 13.20, 39.70 }, radius = 0.02, only = "now quest 4767",
                note = "Leave the cave, run up the path at 13.9, 31.7 and on up at 13.2, 39.7." },
            { track = 4767, note = "Pick up every Highperch Wyvern Egg you pass on the ground." },
            { accept = 4770, npc = 10427, at = { 17.90, 40.60 },
                note = "Accepting starts an escort. Try to have five or six eggs first, so you can finish them on the way out." },
            { escort = 4770, npc = 10427, at = { 15.15, 32.65 },
                note = "Take Pao'ka down the mountain. Three wyverns attack half way down." },
            { untrack = 4767 },
            { objective = 4767, part = 1, collect = 12356, count = 10, object = "Highperch Wyvern Egg", radius = 0.04,
                at = { { 10.80, 34.70 }, { 11.11, 34.54 }, { 12.19, 36.13 }, { 12.56, 37.37 }, { 17.57, 42.25 } },
                note = "Finish the eggs." },
            { group = {
                { turnin = { 4865, 4770 }, accept = 5062, npc = 10428, at = { 21.50, 32.40 } },
                { accept = 5151, npc = 10941, at = { 21.40, 32.60 } },
            } },
        } },

        { section = "Steelsnap and the Galak Messenger", steps = {
            { track = 1131, note = "Steelsnap, a hyena, patrols the hills to the north and west. Kill him and take his rib if you see him." },
            { level = 28, xp = 25000, radius = 0.06, at = { { 18.70, 22.20 }, { 17.10, 18.40 }, { 18.30, 26.80 } },
                note = "Grind on the centaurs and kobolds here." },
            { untrack = 1131 },
            { objective = 1131, part = 1, collect = 5837, kill = 4548, radius = 0.04,
                at = { { 10.90, 23.20 }, { 17.10, 18.40 }, { 18.30, 26.80 }, { 15.20, 30.50 } },
                note = "Steelsnap walks counter-clockwise around these points." },
            { collect = 12564, starts = 4881, kill = 10617, radius = 0.04,
                at = { { 18.40, 22.20 }, { 25.20, 33.80 }, { 36.00, 29.00 }, { 39.60, 33.60 } },
                note = "The Galak Messenger starts at one centaur camp, follows the road and goes to the other. Kill him and loot his note." },
            { accept = 4881, note = "Use the Assassination Note to start its quest." },
            { objective = 5062, part = 1, collect = 12732, count = 10, object = "Incendia Agave", radius = 0.04,
                at = { { 37.50, 38.40 }, { 33.50, 32.40 }, { 36.59, 38.77 }, { 34.95, 33.21 } },
                note = "The yellow plants grow at the edges of the pool and under the water. The fire elementals here resist fire and are immune to frost; avoid them." },
        } },

        { section = "Thunder Bluff again", map = 1456, steps = {
            { travel = "Thunder Bluff", zone = "Thunder Bluff", at = { 45.81, 64.71 }, radius = 0.04,
                note = "Hearth to Thunder Bluff, or fly there from Freewind Post if it is on cooldown." },
            { only = "Druid", npc = 3033, at = { 76.48, 27.22 }, note = "Train your new ranks from Turak Runetotem." },
            { only = "Hunter", npc = 3040, at = { 59.13, 86.87 }, note = "Train your new ranks from Urek Thunderhorn." },
            { only = "Hunter", npc = 10086, at = { 54.09, 83.99 }, note = "Train your pet's new ranks from Hesuwa Thunderhorn." },
            { only = "Warrior", npc = 3043, at = { 57.58, 85.50 }, note = "Train your new ranks from Ker Ragetotem." },
            { only = "Shaman", npc = 3030, at = { 22.82, 21.11 }, note = "Train your new ranks from Siln Skychaser." },
            { only = "Priest", npc = 3045, at = { 24.56, 22.57 }, note = "Train your new ranks from Malakai Cross." },
            { only = "Mage", npc = 3049, at = { 25.18, 20.96 }, note = "Train your new ranks from Thurston Xane." },
            { group = {
                { turnin = 1131, npc = 3441, at = { 61.50, 80.90 } },
                { turnin = 5062, accept = 5088, npc = 4046, at = { 69.90, 30.90 },
                    note = "Magatha Grimtotem is on the Elder Rise." },
            } },
            { travel = "Camp Taurajo", subzone = "Camp Taurajo", only = "now quest 1153 readyToTurnIn", at = { 44.45, 59.15, map = 1413 }, radius = 0.04,
                note = "Fly to Camp Taurajo to hand in the ore sample." },
            { turnin = 1153, npc = 3433, only = "now quest 1153 readyToTurnIn", at = { 45.10, 57.70, map = 1413 } },
            { travel = "Freewind Post", subzone = "Freewind Post", at = { 45.14, 49.11, map = 1441 }, radius = 0.03,
                note = "Fly to Freewind Post." },
        } },

        { section = "Darkcloud Pinnacle", steps = {
            { turnin = 4767, npc = 10377, at = { 44.90, 48.90 } },
            { hearth = "Freewind Post", npc = 11116, only = "not Warrior", at = { 46.07, 51.52 } },
            { turnin = 1150, accept = 1151, npc = 2986, at = { 54.00, 41.50 },
                note = "Keep killing Gravelsnout kobolds for the ore sample if you still need it." },
            { objective = 1151, part = 1, collect = 5844, kill = 4499, radius = 0.05,
                at = { { 29.30, 33.60 }, { 27.10, 28.70 }, { 22.50, 31.30 }, { 17.50, 27.00 }, { 12.80, 20.90 },
                       { 9.30, 21.00 }, { 21.10, 40.60 }, { 34.30, 37.50 }, { 33.20, 53.50 } },
                note = "Rok'Alim the Pounder is an elite rock elemental who walks a wide circle around western Thousand Needles." },
            { travel = "Darkcloud Pinnacle", at = { 31.20, 36.90 }, radius = 0.02, only = "now quest 5064",
                note = "Run up the path here to the Grimtotem bridges." },
            { group = {
                { objective = 5064, part = 1, collect = 12765, object = "Document Chest", at = { 31.79, 32.58 } },
                { objective = 5064, part = 2, collect = 12766, object = "Document Chest", at = { 33.76, 39.99 } },
                { objective = 5064, part = 3, collect = 12768, object = "Document Chest", at = { 39.34, 41.53 } },
            } },
            { objective = 5088, collect = 12925, kill = 10882, at = { 38.09, 35.38 },
                note = "Clear the Grimtotem around the bonfire, use the Incendia Powder to light the Sacred Fire of Life, then kill Arikara and loot her skin. She is elite." },
            { objective = 5147, part = 1, collect = 12884, kill = 10896, at = { 38.11, 26.87 } },
            { accept = 4904, npc = 10646, at = { 38.00, 26.50 } },
            { escort = 4904, npc = 10646, at = { 30.93, 37.12 },
                note = "Keep Lakota Windsong alive across the pinnacle. Grimtotem spawn on the platforms as you go." },
            { objective = 5151, collect = 12946, kill = 10992, at = { 23.30, 23.30 },
                note = "Open the panther cage with Wizlo's key and kill the Enraged Panther. It is elite; have your cooldowns and potions ready." },
            { turnin = 4881, accept = 4966, npc = 10638, only = "now quest 4881", at = { 21.30, 32.10 },
                note = "Kanati Greycloud. Three Galak Assassins appear as soon as you take the next quest." },
            { objective = 4966, part = 1, kill = 10720, count = 3, only = "now quest 4966", at = { 21.40, 31.80 },
                note = "Let Kanati take their attention, then kill them." },
            { group = {
                { turnin = 4966, npc = 10638, only = "now quest 4966", at = { 21.30, 32.10 } },
                { turnin = 5088, npc = 10428, at = { 21.50, 32.40 } },
                { turnin = 5151, npc = 10941, at = { 21.40, 32.60 } },
            } },
            { objective = 1153, part = 1, collect = 5842, kill = { 4113, 4116 }, only = "now quest 1153", radius = 0.04,
                at = { { 9.20, 21.00 }, { 11.85, 21.31 }, { 12.41, 14.01 } },
                note = "Gravelsnout Diggers and Surveyors here drop the Unrefined Ore Sample, if you still need it." },
        } },

        { section = "Feralas and back", steps = {
            { travel = "Camp Mojache", subzone = "Camp Mojache", at = { 75.45, 44.36, map = 1444 }, radius = 0.03,
                note = "Run west into Feralas, through 88.9, 41.2, for the flight path." },
            { flight = "Camp Mojache", npc = 8020, at = { 75.45, 44.36, map = 1444 } },
            { travel = "Freewind Post", subzone = "Freewind Post", at = { 45.14, 49.11 }, radius = 0.03,
                note = "Fly back to Freewind Post." },
            { group = {
                { turnin = { 5064, 5147 }, npc = 10537, at = { 45.70, 50.70 } },
                { turnin = 4904, npc = 10645, at = { 46.00, 51.60 } },
            } },
            { turnin = 1151, npc = 2986, at = { 54.00, 41.50 },
                note = "Dorn offers Test of Lore next. It belongs to later levels; leave it." },
        } },

        { section = "The Shimmering Flats", steps = {
            { level = 30, by = "racetrack", radius = 0.06, at = { { 67.60, 64.00 }, { 65.74, 49.89 }, { 67.87, 58.33 } },
                note = "Grind on the way down so the racetrack turn-ins ahead bring you to 30. Experience past the cap is lost." },
            { group = {
                { accept = { 1110, 1111, 5762 }, npc = 4452, at = { 77.80, 77.30 } },
                { accept = 1104, npc = 4454, at = { 78.10, 77.10 } },
                { accept = 1105, npc = 4453, at = { 78.10, 77.10 } },
                { accept = 1176, npc = 4630, at = { 80.20, 75.90 } },
                { accept = 1175, npc = 4629, at = { 81.60, 78.00 } },
            } },
            { group = {
                { objective = 1175, part = 3, kill = 4150, count = 6, radius = 0.05,
                    at = { { 78.40, 89.10 }, { 76.90, 89.40 }, { 72.90, 87.90 }, { 78.60, 90.30 } },
                    note = "Saltstone Gazers in the south of the flats. They are a few levels above you." },
                { objective = 1110, part = 1, collect = 5798, count = 30, object = "Rocket Car Rubble", radius = 0.06,
                    at = { { 73.06, 59.66 }, { 79.55, 59.12 }, { 87.27, 73.47 }, { 83.75, 86.66 }, { 76.31, 89.51 } } },
                { objective = 1104, part = 1, collect = 5794, count = 6, kill = { 4139, 4140 }, radius = 0.06,
                    at = { { 84.50, 61.43 }, { 82.68, 69.09 }, { 86.57, 68.57 }, { 81.40, 86.83 } } },
                { objective = 1176, part = 1, collect = 5848, count = 10, kill = { 4154, 4158 }, radius = 0.06,
                    at = { { 80.71, 59.47 }, { 73.72, 58.86 }, { 82.99, 70.69 }, { 71.16, 79.22 } } },
                { objective = 1105, part = 1, collect = 5795, count = 9, kill = { 4142, 4143, 4144 }, radius = 0.06,
                    at = { { 81.33, 52.68 }, { 77.57, 53.92 }, { 83.77, 60.74 }, { 79.89, 85.72 } } },
                { objective = 1175, part = 1, kill = 4147, count = 10, radius = 0.06,
                    at = { { 76.90, 57.60 }, { 76.30, 52.90 }, { 77.40, 59.60 }, { 68.70, 61.90 } } },
                { objective = 1175, part = 2, kill = 4151, count = 10, radius = 0.06,
                    at = { { 83.50, 65.20 }, { 80.00, 70.50 }, { 85.90, 58.50 }, { 79.40, 89.60 } } },
            } },
            { label = "racetrack", group = {
                { turnin = 1110, npc = 4452, at = { 77.80, 77.30 } },
                { turnin = 1104, npc = 4454, at = { 78.10, 77.10 } },
                { turnin = 1105, npc = 4453, at = { 78.10, 77.10 } },
                { turnin = 1176, accept = 1178, npc = 4630, at = { 80.20, 75.90 } },
                { turnin = 1175, npc = 4629, at = { 81.60, 78.00 } },
            } },
            { note = "Fizzle and Wizzle offer Martek the Exiled and Encrusted Tail Fins next. Both are level 35 quests; leave them." },
        } },

        { section = "Tanaris", steps = {
            { travel = "Gadgetzan", subzone = "Gadgetzan", at = { 51.60, 25.44, map = 1446 }, radius = 0.03,
                note = "Follow the flats south-east into Tanaris for the flight path." },
            { flight = "Gadgetzan", npc = 7824, at = { 51.60, 25.44, map = 1446 } },
            { travel = "Freewind Post", subzone = "Freewind Post", only = "not Warrior", at = { 46.07, 51.52 }, radius = 0.03,
                note = "Hearth to Freewind Post, or fly there if it is on cooldown." },
            { travel = "Camp Taurajo", subzone = "Camp Taurajo", only = "not Warrior", at = { 44.45, 59.15, map = 1413 }, radius = 0.04,
                note = "Fly to Camp Taurajo." },
        } },

        { section = "Thunder Bluff for warriors", map = 1456, steps = {
            { travel = "Thunder Bluff", zone = "Thunder Bluff", only = "Warrior", at = { 46.65, 49.90 }, radius = 0.04,
                note = "Hearth or fly to Thunder Bluff." },
            { accept = 1718, npc = 3041, only = "Warrior | now level 30", at = { 57.24, 87.37 } },
            { only = "Warrior", npc = 3043, at = { 57.58, 85.50 }, note = "Train your level 30 ranks from Ker Ragetotem." },
            { travel = "Camp Taurajo", subzone = "Camp Taurajo", only = "Warrior", at = { 44.45, 59.15, map = 1413 }, radius = 0.04,
                note = "Fly to Camp Taurajo." },
        } },

        { section = "The Barrens", map = 1413, steps = {
            { turnin = 1153, npc = 3433, only = "now quest 1153", at = { 45.10, 57.70 } },
            { travel = "The Crossroads", subzone = "The Crossroads", at = { 51.50, 30.34 }, radius = 0.04,
                note = "Fly to the Crossroads." },
            { accept = 1145, npc = 3428, at = { 51.10, 29.60 } },
            { hearth = "The Crossroads", npc = 3934, only = "not Shaman | not Warrior", at = { 51.99, 29.89 } },
            { travel = "Ratchet", subzone = "Ratchet", at = { 63.08, 37.16 }, radius = 0.04,
                note = "Fly to Ratchet." },
            { turnin = 1111, accept = 1112, npc = 3453, at = { 63.40, 38.50 } },
            { turnin = 1178, accept = 1180, npc = 3391, at = { 62.70, 36.20 },
                note = "Gazlowe, in Ratchet." },
            { turnin = 874, accept = 873, npc = 3388, only = "now quest 874", at = { 65.80, 43.90 },
                note = "Mahren Skyseer is on the shore south of Ratchet. Skip it if you do not have the quest." },
            { objective = 873, part = 1, collect = 5104, kill = 3476, only = "now quest 873", radius = 0.04,
                at = { { 65.60, 47.10 }, { 63.40, 50.20 }, { 64.00, 52.00 }, { 63.30, 54.20 } },
                note = "Isha Awak, a red threshadon, swims in the bay. Kill it and loot its heart." },
            { turnin = 1718, accept = 1719, npc = 6236, only = "Warrior | now quest 1718", at = { 68.60, 49.20 },
                note = "Klannoc Macleod is on the island off the coast. Swim there." },
            { objective = 1719, kill = 6238, only = "Warrior | now quest 1719", at = { 68.60, 48.70 },
                note = "Step onto the grate to start the Affray, beat the challengers, then Big Will." },
            { turnin = 1719, npc = 6236, only = "Warrior | now quest 1719", at = { 68.60, 49.20 },
                note = "The Windwatcher comes next. It is a long chain for level 30 and later; take it when you want to." },
            { turnin = 873, npc = 3388, only = "now quest 873", at = { 65.80, 43.90 } },
        } },

        { section = "Booty Bay", map = 1434, steps = {
            { travel = "Booty Bay", subzone = "Booty Bay", at = { 25.80, 73.10 }, radius = 0.04,
                note = "Take the boat from the Ratchet dock, at 63.7, 38.6 in the Barrens." },
            { note = "Shamans: the weapon vendor upstairs sometimes sells a Big Stick or a Staff of Protection." },
            { turnin = 1180, accept = 1181, npc = 4631, at = { 26.40, 73.60 } },
            { turnin = 1181, npc = 2496, at = { 27.20, 76.90 },
                note = "Baron Revilgaz is on the top floor of the inn. His next Goblin Sponsorship is a level 37 quest; leave it." },
            { only = "Rogue", npc = 1411, at = { 26.82, 77.15 }, note = "Train your level 30 ranks from Ian Strom, in the inn." },
            { flight = "Booty Bay", npc = 2858, at = { 26.87, 77.10 } },
            { note = "The Booty Bay quests (Supply and Demand, Singing Blue Shards, Bloodscalp Ears and the rest) are for later levels." },
            { travel = "Ratchet", subzone = "Ratchet", at = { 63.70, 38.60, map = 1413 }, radius = 0.03,
                note = "Take the boat back to Ratchet." },
        } },

        { section = "Orgrimmar", map = 1454, steps = {
            { travel = "Orgrimmar", zone = "Orgrimmar", at = { 45.29, 63.89 }, radius = 0.04,
                note = "Fly to Orgrimmar from Bragok." },
            { only = "Paladin", at = { 32.40, 35.80 }, note = "Train your level 30 ranks from your paladin trainer." },
            { only = "Shaman", npc = 3344, at = { 38.80, 36.37 }, note = "Train your level 30 ranks from Kardris Dreamseeker." },
            { accept = 1531, npc = 5892, only = "Shaman | now level 30", at = { 38.00, 37.70 } },
            { only = "Hunter", npc = 3352, at = { 66.05, 18.53 }, note = "Train your level 30 ranks from Ormak Grimshot." },
            { only = "Hunter", npc = 10088, at = { 66.32, 14.81 }, note = "Train your pet's new ranks from Xao'tsu." },
            { accept = 2996, npc = 5875, only = "Warlock | now level 30", at = { 48.30, 45.30 },
                note = "Train your level 30 ranks from Gan'rul Bloodeye as well. Kurgul, beside him, sells the Grimoire of Lash of Pain rank 2." },
            { accept = 1431, npc = 5639, at = { 51.30, 45.90 } },
            { turnin = 1145, accept = 1146, npc = 4485, at = { 75.20, 34.20 },
                note = "The Swarm Grows goes on to Moktar Krin in the Shimmering Flats." },
            { only = "Mage", npc = 5883, at = { 38.78, 85.67 }, note = "Train your level 30 ranks from Enyo." },
            { only = "Priest", npc = 6018, at = { 35.59, 87.82 }, note = "Train your level 30 ranks from Ur'kyo." },
            { turnin = 1431, accept = 1432, npc = 5640, at = { 22.60, 52.60 },
                note = "Keldran, in the Valley of Spirits." },
            { train = "Thrown", npc = 2704, only = "Warrior", at = { 81.50, 19.60 },
                note = "Hanashi teaches thrown weapons." },
        } },

        { section = "Ratchet for warlocks and shamans", map = 1413, steps = {
            { travel = "Ratchet", subzone = "Ratchet", only = "Warlock or Shaman", at = { 63.08, 37.16 }, radius = 0.04,
                note = "Fly to Ratchet." },
            { turnin = 2996, accept = 1801, npc = 6251, only = "Warlock | now quest 2996", at = { 62.60, 35.50 } },
            { turnin = 220, accept = 63, npc = 5901, only = "Shaman | now quest 220", at = { 65.80, 43.80 },
                note = "Islen Waterseer, on the shore south of Ratchet." },
            { finish = "Thousand Needles is done, and so is the climb to 30. Still in your log for later: Parts for Kravel, Hemet Nesingwary, The Swarm Grows and Alliance Relations, and your class quests (Call of Water and Call of Air, Tome of the Cabal)." },
        } },
    },
}
