local _, ns = ...

-- Horde 26-30 leveling route through Ashenvale: class training in Orgrimmar,
-- the walk west to Splintertree Post, the hunt for Sharptalon, Shadumbra and
-- Ursangous, Mystral Lake, Thistlefur Village and the Zoram'gar turn-ins.
-- Ported from the Ashenvale leg of RestedXP's Classic "26-30 Ashenvale /
-- Thousand Needles" (RestedXP Horde 20-30.lua); it picks up where the
-- Stonetalon guide ends, at Sun Rock Retreat, and stops where the source
-- heads for Thunder Bluff and Thousand Needles. Step order follows the
-- source. Quest IDs, NPC IDs, item IDs and positions were checked against
-- Questie's Forever database (db/questie), the Forever client's quest list
-- (ForeverGuide's scan: every quest here exists on Forever) and ForeverGuide's
-- Ashenvale routes; NPCs stand where the database puts them, and the
-- source's coordinates are kept for areas and patrol loops.
--
-- Notes:
--   * The source is a Classic guide. Forever adds no new quests in Ashenvale
--     that could be placed (none in Questie's Forever data or ForeverGuide's
--     Ashenvale chapters); RestedXP's own Forever guides only send hunters
--     here, for Torek's Assault, which this route does as well.
--   * The source's experience-rate branches are read for a normal rate:
--     Ordanus and the steps marked for rates below 1.5 stay in, and the
--     early Kuray'bin turn-in written for faster rates is left out.
--   * The Ashenvale Hunt: the source only turns it in. On Forever Senani
--     both gives and takes it (6383), and the three hunt quests need it
--     done first, so the guide accepts and hands it in. The breadcrumbs
--     from the Barrens and Orgrimmar (6382, 235, 742) are turned in to her
--     if they are in the log. The source also hands in The Hunt Completed
--     without taking it; here it is accepted and handed in at Senani. Both
--     hand-backs sit in the same group card as the visit that gives them.
--   * Tideress's globe is one sticky step that starts The Befouled Element
--     when used, since she can turn up anywhere on the lake; the source's
--     separate accept line rides on it.
--   * Quests that an earlier guide may or may not have given (Ordanus, The
--     Sacred Flame, Between a Rock and a Thistlefur, Troll Charm, Trouble in
--     the Deeps, Call of Water) are gated on being in the log, so their steps
--     pass by for a character who never took them. As in the source,
--     Thistlefur Village and Ruul are only visited by a character carrying
--     Between a Rock and a Thistlefur; only rogues pick it up in this guide.
--   * The source sets a rogue's hearthstone at Splintertree only when they
--     already carry Between a Rock and a Thistlefur, yet every rogue hearths
--     back there from Blackfathom Deeps; here every rogue sets it.
--   * Orgrimmar has no paladin trainer in the Forever data (Horde paladins
--     train in Brill), so the source's paladin trainer visit is left out. The
--     source's riding steps belong to a later expansion and are left out.
--   * The source's "abandon The Befouled Element, destroy the globe" step is
--     left out: NuuRoad never tells a player to abandon or destroy anything,
--     and the globe is wanted for Je'neu of the Earthen Ring.
--   * Blackfathom Deeps: the rogue's pickups outside the dungeon (Amongst the
--     Ruins, The Essence of Aku'Mai, the Damp Note, the sapphires at the
--     entrance) stay in. Baron Aquanis is inside the dungeon and is left to
--     NuuRoad's Blackfathom Deeps guide, as one note.
--   * No death skips: the source has none in this stretch.
--
-- Check in client:
--   * The source's walk from Orgrimmar's west gate up the river into
--     Ashenvale (the ramp at 90.8, 66.9 and the lumber camp) is Classic
--     data; Forever may route it differently.
--   * The gazebo scouting for Stonetalon Standstill is a travel step to the
--     gazebo (the format has no explore objective title); confirm arriving
--     there completes the objective.
--   * Tideress is placed at the Questie spawn (46, 70) and the lake loop;
--     confirm she still patrols Mystral Lake.
--   * The rogue's Damp Note (Blackfathom Tide Priestess) and the sapphires
--     are placed outside the instance at Questie's Ashenvale positions;
--     confirm they are reachable there on Forever.
--   * The Splintertree bind location name ("Splintertree Post").
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1440 Ashenvale (guide default), 1454 Orgrimmar, 1450 Moonglade.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:leveling:horde-ashenvale-26-30"] = {
    schema = 2,
    id = "nuuroad:leveling:horde-ashenvale-26-30",
    updated = 1790985600,
    map = 1440,
    only = "Horde",
    meta = {
        title = "Splintertree and Zoram'gar",
        author = "NuuRoad",
        category = "Leveling/Ashenvale",
        tags = { "horde", "ashenvale", "splintertree", "zoramgar", "orgrimmar" },
        levels = { 26, 30 },
    },
    steps = {
        { section = "Orgrimmar", map = 1454, steps = {
            { travel = "Orgrimmar", zone = "Orgrimmar", at = { 45.12, 63.89 }, radius = 0.04,
                note = "Fly to Orgrimmar from Tharm at Sun Rock Retreat, or from the Crossroads if you are there." },
            { only = "Shaman", npc = 3344, at = { 38.80, 36.37 }, note = "Train your new ranks from Kardris Dreamseeker in the Valley of Wisdom." },
            { only = "Hunter", npc = 3352, at = { 66.05, 18.52 }, note = "Train your new ranks from Ormak Grimshot in the Valley of Honor." },
            { only = "Hunter", npc = 10088, at = { 66.32, 14.81 }, note = "Xao'tsu, nearby, teaches your pet's new ranks." },
            { only = "Warrior", npc = 3353, at = { 79.79, 31.42 }, note = "Train your new ranks from Grezz Ragefist in the Valley of Honor." },
            { only = "Rogue", npc = 3328, at = { 43.90, 54.63 }, note = "Train your new ranks from Ormok in the Cleft of Shadow." },
            { only = "Warlock", npc = 3324, at = { 47.98, 45.93 }, note = "Train your new ranks from Grol'dar in the Cleft of Shadow." },
            { only = "Mage", npc = 5883, at = { 38.78, 85.67 }, note = "Train your new ranks from Enyo in the Valley of Spirits." },
            { only = "Priest", npc = 6018, at = { 35.59, 87.80 }, note = "Train your new ranks from Ur'kyo in the Valley of Spirits." },
        } },

        { section = "To Splintertree Post", steps = {
            { travel = "Orgrimmar's west gate", with = "next", at = { 16.20, 62.20, map = 1454 } },
            { travel = "The ramp into Ashenvale", at = { { 94.70, 76.80 }, { 90.80, 66.90 } },
                note = "Follow the river north along the edge of Ashenvale, then take the ramp up. Spiders of level 28 and 29 live around it." },
            { travel = "Splintertree Post", subzone = "Splintertree Post", at = { { 88.50, 64.90 }, { 81.70, 62.90 }, { 73.20, 61.60 } },
                radius = 0.04, note = "Through the lumber camp and west along the road." },
            { flight = "Splintertree Post", npc = 12616, at = { 73.18, 61.59 } },
        } },

        { section = "Splintertree Post", steps = {
            { group = {
                { accept = 6441, npc = 12724, at = { 73.06, 61.48 } },
                { turnin = { 235, 742, 6382 }, npc = 12696, at = { 73.78, 61.46 },
                    only = "now quest 235 accepted or now quest 742 accepted or now quest 6382 accepted",
                    note = "The Ashenvale Hunt from the Barrens or Orgrimmar, if you carry it." },
                { accept = 6383, npc = 12696, at = { 73.78, 61.46 } },
                { turnin = 6383, npc = 12696, at = { 73.78, 61.46 },
                    note = "Hand it straight back: the three hunt quests open once it is done." },
            } },
            { hearth = "Splintertree Post", npc = 12196, only = "Rogue", at = { 73.99, 60.65 },
                note = "Rogues come back here from Blackfathom Deeps. Innkeeper Kaylisk is in the inn." },
            { accept = 25, npc = 12737, at = { 73.67, 60.00 } },
            { accept = 6503, npc = 12867, at = { 71.11, 68.12 },
                note = "Kuray'bin stands south of the post, by the road." },
            { objective = 6503, part = 1, kill = 12856, count = 9, radius = 0.06,
                at = { { 72.50, 72.50 }, { 76.30, 71.10 }, { 76.30, 67.30 } },
                note = "The Ashenvale Outrunners are stealthed. Walk the woods south and east of the post until they show themselves." },
            { accept = 6544, npc = 12858, at = { 68.34, 75.30 },
                note = "If Torek is not there, wait a few minutes for him to come back." },
            { escort = 6544, npc = 12858, at = { 64.65, 75.35 },
                note = "Follow Torek into Silverwing Outpost and let him and his raiders take the first blows. Waves of defenders come out inside the building, and Duriel Moonfire last. Warlocks: bring the voidwalker." },
        } },

        { section = "The satyrs and the hunt", steps = {
            { travel = "Along the river", with = "next", at = { 72.30, 49.80 } },
            { objective = 6441, part = 1, collect = 5481, count = 16, kill = { 3758, 3759, 3762, 3763 }, radius = 0.05,
                at = { { 68.20, 54.00 }, { 66.80, 52.57 }, { 66.43, 53.96 }, { 67.33, 55.38 }, { 66.73, 57.17 } },
                note = "Felmusk satyrs at the camp in the hills." },
            { group = {
                { objective = 1088, part = 1, collect = 5686, kill = 4273, only = "now quest 1088 accepted", at = { 62.05, 51.37 },
                    note = "Keeper Ordanus is at the top of the building. Burst him down, loot his head and jump off the building to get away." },
                { collect = 16304, starts = 24, kill = 12677, radius = 0.06,
                    at = { { 62.20, 49.60 }, { 58.00, 56.20 }, { 51.90, 54.30 }, { 61.20, 51.50 } },
                    note = "Shadumbra is a panther who roams these woods. Kill her and take her head." },
                { collect = 5867, kill = 4054, only = "now quest 1195 accepted", radius = 0.05,
                    at = { { 61.30, 51.90 }, { 60.74, 51.83 }, { 59.25, 54.42 }, { 58.66, 56.87 } },
                    note = "Laughing Sisters drop the Etched Phial for The Sacred Flame. One is enough." },
            } },
            { accept = 24, item = 16304, note = "Use Shadumbra's Head to start its quest. Skip this if you could not find her." },
        } },

        { section = "Zoram'gar Outpost", steps = {
            { travel = "Zoram'gar Outpost", subzone = "Zoram'gar Outpost", only = "Rogue", at = { 16.30, 29.80 }, radius = 0.05,
                note = "The long way west. Keep clear of the Astranaar guards on the road." },
            { flight = "Zoram'gar Outpost", npc = 11901, only = "Rogue", at = { 12.24, 33.80 } },
            { group = {
                { accept = 216, npc = 12757, only = "Rogue", at = { 11.90, 34.54 } },
                { accept = 6462, npc = 12721, only = "Rogue", at = { 11.65, 34.85 },
                    note = "Mitsuwa is in the hut with the trolls." },
                { turnin = 6562, npc = 12736, only = "Rogue | now quest 6562 accepted", at = { 11.56, 34.29 } },
                { accept = 6641, npc = 12717, only = "Rogue", at = { 12.06, 34.63 },
                    note = "Taking it starts an escort. Muglash walks to the brazier on the shore." },
            } },
            { escort = 6641, npc = 12717, only = "Rogue | now quest 6641 accepted", at = { 9.59, 27.58 },
                note = "Put out the brazier. Naga come in waves; when Vorsha the Lasher arrives, let Muglash take her attention before you attack." },
        } },

        { section = "Thistlefur Village", steps = {
            { track = 216, only = "now quest 216 accepted" },
            { travel = "Thistlefur Village", subzone = "Thistlefur Village", only = "now quest 216 accepted", at = { 38.50, 36.10 }, radius = 0.04,
                note = "Kill Thistlefur Avengers and Shaman on the way to the cave." },
            { travel = "Thistlefur Hold", only = "now quest 216 accepted", at = { 38.40, 30.60 } },
            { objective = 6462, part = 1, collect = 16602, count = 8, object = "Troll Chest", only = "now quest 6462 accepted", radius = 0.04,
                at = { { 40.19, 30.99 }, { 40.76, 32.81 }, { 39.96, 33.08 }, { 40.86, 33.64 }, { 41.34, 34.18 }, { 41.51, 34.77 }, { 41.67, 35.70 } },
                note = "The small chests along the tunnels of the hold." },
            { accept = 6482, npc = 12818, only = "now quest 216 accepted", at = { 41.53, 34.49 },
                note = "Taking it starts the escort. Be ready before you do." },
            { escort = 6482, npc = 12818, only = "now quest 6482 accepted", at = { 38.53, 37.32 },
                note = "Keep Ruul alive on the way out of the village. The furbolgs that attack count for your kills." },
            { untrack = 216, only = "now quest 216 accepted" },
            { group = {
                { objective = 216, part = 1, kill = 3925, count = 8, only = "now quest 216 accepted", radius = 0.05,
                    at = { { 39.56, 37.73 }, { 37.93, 34.52 }, { 39.26, 36.28 } } },
                { objective = 216, part = 2, kill = 3924, count = 8, only = "now quest 216 accepted", radius = 0.05,
                    at = { { 36.14, 36.98 }, { 39.64, 36.84 }, { 35.70, 36.94 } } },
            } },
        } },

        { section = "Mystral Lake", steps = {
            { objective = 1534, part = 1, collect = 7770, use = 7767, object = "Ruins of Stardust Fountain",
                only = "Shaman | now quest 1534 accepted", at = { 33.55, 67.47 },
                note = "Fill the Empty Blue Waterskin at the fountain in the Ruins of Stardust." },
            { collect = 16303, starts = 23, kill = 12678, radius = 0.05,
                at = { { 41.50, 67.40 }, { 44.30, 68.60 }, { 43.80, 63.60 }, { 41.40, 65.90 }, { 39.76, 65.21 } },
                note = "Ursangous is a bear who walks a clockwise loop here. Kill him and take his paw." },
            { accept = 23, item = 16303, note = "Use Ursangous's Paw to start its quest. Skip this if you could not find him." },
            { collect = 16408, starts = 1918, kill = 12759, sticky = true, at = { 46.00, 70.00 },
                note = "Tideress swims around the middle of Mystral Lake. Kill her whenever you find her, and use the Befouled Water Globe she drops to start its quest." },
            { travel = "The gazebo on Mystral Lake", at = { 48.93, 69.56 }, radius = 0.02,
                note = "Swim under the gazebo in the middle of the lake: that is the scouting for Stonetalon Standstill." },
            { objective = 25, part = 1, kill = 3917, count = 12, radius = 0.06,
                at = { { 48.90, 69.60 }, { 45.08, 69.30 }, { 46.26, 70.66 }, { 48.35, 72.76 }, { 51.22, 73.36 } },
                note = "Befouled Water Elementals all over the lake." },
            { objective = 1195, part = 1, collect = 5868, use = 5867, object = "Ashenvale Moonwell",
                only = "now quest 1195 accepted", at = { 60.20, 72.91 },
                note = "Fill the Etched Phial at the moonwell." },
        } },

        { section = "Back to Splintertree", steps = {
            { turnin = 6503, npc = 12867, at = { 71.11, 68.12 } },
            { collect = 16305, starts = 2, kill = 12676, radius = 0.06,
                at = { { 72.40, 72.10 }, { 75.70, 70.00 }, { 78.20, 65.50 }, { 75.30, 72.00 } },
                note = "Sharptalon is a big bird who flies a clockwise loop. Bring him to about 60% health, then pull him back to the post and finish him there." },
            { accept = 2, item = 16305, note = "Use Sharptalon's Claw to start its quest. Skip this if you could not kill him." },
            { group = {
                { turnin = 6544, npc = 12877, only = "now quest 6544 readyToTurnIn", at = { 73.03, 62.47 } },
                { turnin = { 2, 24, 23 }, accept = 247, npc = 12696, at = { 73.78, 61.46 } },
                { turnin = 247, npc = 12696, at = { 73.78, 61.46 } },
                { turnin = { 25, 1918 }, npc = 12737, at = { 73.67, 60.00 } },
                { accept = 824, npc = 12737, only = "now quest 216 accepted", at = { 73.67, 60.00 },
                    note = "Keep the Befouled Water Globe: Je'neu wants it." },
                { turnin = 6482, npc = 12837, only = "now quest 6482 readyToTurnIn", at = { 74.11, 60.92 },
                    note = "Yama Snowhoof is in the inn." },
                { turnin = 6441, npc = 12724, at = { 73.06, 61.48 } },
            } },
        } },

        { section = "Zoram'gar again", steps = {
            { travel = "Zoram'gar Outpost", subzone = "Zoram'gar Outpost", only = "now quest 216 accepted", at = { 12.24, 33.80 }, radius = 0.04,
                note = "Fly there from Vhulgra." },
            { group = {
                { turnin = 216, npc = 12757, only = "now quest 216 accepted", at = { 11.90, 34.54 } },
                { turnin = 6462, npc = 12721, only = "now quest 6462 accepted", at = { 11.65, 34.85 } },
                { turnin = 824, npc = 12736, only = "now quest 824 accepted", at = { 11.56, 34.29 } },
                { turnin = 6641, npc = 12863, only = "Rogue | now quest 6641 readyToTurnIn", at = { 12.22, 34.22 } },
                { accept = { 6921, 6563 }, npc = 12736, only = "Rogue", at = { 11.56, 34.29 } },
            } },
            { travel = "Blackfathom Deeps", only = "Rogue", at = { 14.00, 15.00 }, radius = 0.04,
                note = "North along the shore to the sunken temple." },
            { collect = 16790, starts = 6564, kill = 4802, only = "Rogue", at = { 13.55, 12.06 },
                note = "Kill Blackfathom Tide Priestesses until one drops the Damp Note." },
            { accept = 6564, item = 16790, only = "Rogue", note = "Use the Damp Note to start its quest." },
            { objective = 6563, part = 1, collect = 16784, count = 20, object = "Sapphire of Aku'Mai", only = "Rogue",
                radius = 0.03, at = { { 13.59, 13.14 }, { 12.90, 13.22 }, { 13.69, 12.27 } },
                note = "Stealth along the way in and pick the sapphires off the walls." },
            { note = "Baron Aquanis and the Fathom Core for Amongst the Ruins are inside the dungeon. NuuRoad's Blackfathom Deeps guide covers them; a rogue who is ready can try them alone now.",
                only = "Rogue" },
            { travel = "Splintertree Post", subzone = "Splintertree Post", only = "Rogue", at = { 73.99, 60.65 }, radius = 0.04,
                note = "Hearth back to Splintertree Post. Buy food and drink if you need them." },
        } },

        { section = "Moonglade", map = 1450, steps = {
            { travel = "Moonglade", zone = "Moonglade", only = "Druid", at = { 52.53, 40.57 }, radius = 0.04,
                note = "Cast Teleport: Moonglade." },
            { only = "Druid", npc = 12042, at = { 52.53, 40.57 }, note = "Train your new ranks from Loganaar." },
            { finish = "Ashenvale is done. Go on to Thunder Bluff and continue with the Thousand Needles guide: hearth there if your stone is bound to Thunder Bluff, otherwise fly. Rogues fly to Orgrimmar first to train. The Sacred Flame goes to Zangen Stonehoof in Thunder Bluff." },
        } },
    },
}
