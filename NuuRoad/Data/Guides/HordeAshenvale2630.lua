-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeAshenvale2630.lua.
--
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
--     if they are in the log (an optional turn-in). The source also hands in
--     The Hunt Completed without taking it; here it is accepted and handed in
--     at Senani. Both hand-backs sit in the same group as the visit that
--     gives them.
--   * Tideress's globe is one sticky accept-from-item step with her as the
--     kill: kill her, loot the Befouled Water Globe, use it to start The
--     Befouled Element, since she can turn up anywhere on the lake; the
--     source's separate accept line rides on it.
--   * Quests that an earlier guide may or may not have given (Ordanus, The
--     Sacred Flame, Call of Water, Trouble in the Deeps) are no longer gated
--     on being in the log (see Conversion notes). As in the source,
--     Thistlefur Village and Ruul are only visited by a character carrying
--     Between a Rock and a Thistlefur; only rogues pick it up in this guide,
--     so those sections are for rogues.
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
--     gazebo with quest = { 25, 2 }; confirm the explore objective is the
--     quest's second (see Conversion notes) and that arriving there
--     completes it.
--   * Tideress is placed at the Questie spawn (46, 70) and the lake loop;
--     confirm she still patrols Mystral Lake.
--   * The rogue's Damp Note (Blackfathom Tide Priestess) and the sapphires
--     are placed outside the instance at Questie's Ashenvale positions;
--     confirm they are reachable there on Forever.
--   * The Splintertree bind location: area 431 (Splintertree Post).
--
-- Maps: 1440 Ashenvale (guide default), 1454 Orgrimmar, 1450 Moonglade.
--
-- Conversion notes:
--   * Guide `only = "Horde"` -> wrapper cond = { faction = "Horde" }; meta
--     levels { 26, 30 } -> levels = { from = 26, to = 30 }. The wrapper's
--     `source` is taken from the header (meta had none).
--   * IDs looked up in db/sources/wago/forever: AreaTable 431 Splintertree
--     Post, 2897 Zoram'gar Outpost, 2301 Thistlefur Village (each travel
--     `subzone` -> `area`); TaxiNodes 61 Splintertree Post, 58 Zoram'gar
--     Outpost. zone "Orgrimmar" -> 1454, "Moonglade" ->
--     1450 (db/horde/maps.json). The hearth step's name -> area = 431.
--   * Class trainer visits (npc + note, no verb) -> talk steps with cond
--     class; no spells listed, since the source names none. The "where"
--     half of each note (Valley of Wisdom, Cleft of Shadow, ...) moved to the
--     NPC's note; the step keeps "Train your new ranks." Likewise "Kuray'bin
--     stands south of the post", "Mitsuwa is in the hut", "Yama Snowhoof is in
--     the inn" and "Innkeeper Kaylisk is in the inn" became NPC notes.
--   * `with = "next"` -> with = a label added to the next step ("ramp",
--     "horns").
--   * Dropped `now` / quest-state gates (no quest predicates in the format):
--       - turnin 235/742/6382 `now quest ... accepted` -> optional = true.
--       - turnin 6544 and 6482 `now quest ... readyToTurnIn`, turnin 6641
--         `Rogue | now quest 6641 readyToTurnIn` -> optional = true (6641
--         also covered by its section's cond ROGUE).
--       - turnin 6562 `Rogue | now quest 6562 accepted` -> cond ROGUE (from
--         the section) and optional = true.
--       - Ordanus collect `now quest 1088 accepted`: dropped. 1088 comes from
--         the Stonetalon guide; a character without it would stop on the
--         step (the addon's to handle, see ADDON CHANGES).
--       - Etched Phial collect `now quest 1195 accepted`: dropped; written as
--         quest = 1195 (the whole quest), count 1 by default, so the step is
--         tied to The Sacred Flame.
--       - Moonwell collect `now quest 1195 accepted`, Call of Water `Shaman |
--         now quest 1534 accepted` (-> cond SHAMAN): quest part dropped; both
--         are objective steps of quests accepted in earlier guides.
--       - escort 6641 `Rogue | now quest 6641 accepted` -> cond ROGUE.
--       - Every `now quest 216 accepted` (Thistlefur Village section, accept
--         824, the "Zoram'gar again" section) and `now quest 6462/6482/824
--         accepted` -> cond = { class = "ROGUE" } on the step or section,
--         since 216 (and 6462, 6482) are only taken by rogues in this guide;
--         a non-rogue carrying 216 from elsewhere no longer gets them.
--   * Sections given cond = { class = "ROGUE" }: "Zoram'gar Outpost",
--     "Thistlefur Village", "Zoram'gar again" (every step there was rogue-
--     only or gated on 216).
--   * track 216 / untrack 216 -> label "thistlefur" on the Thistlefur Village
--     travel (the first step after the track), from = "thistlefur" on both
--     216 kill steps in the closing group.
--   * Objectives: objective/part -> quest = { id, n }; counts on objective
--     steps dropped (9 Outrunners, 16 Satyr Horns, 8 Troll Charms, 8 each
--     Thistlefur, 12 elementals, 20 sapphires). Inferred: the gazebo travel
--     gets quest = { 25, 2 } (Questie lists the explore objective after the
--     kill, which the source numbers 1).
--   * Tideress: `collect 16408 starts 1918, sticky` -> accept quests 1918
--     with item 16408, kill 12759, sticky (the format's one-step kill, loot,
--     accept), since the guide has no other accept for 1918.
--   * "Skip this if you could not find/kill him/her" dropped from the three
--     accept-from-item notes: such an accept passes when the item is not in
--     the bags.
--   * Multi-point `at` lists: the source's first point was the arrow target
--     and the rest pins; here the arrow takes the nearest (the ramp walk and
--     the Splintertree approach in particular).
--   * Only explicit radii are kept; the old per-verb defaults are not
--     written.
--   * NPCs grouped by map: Orgrimmar trainers under 1454, Loganaar under
--     1450, the rest under 1440. Every visited NPC has a position.
--   * The trailing `travel "Blackfathom Deeps"` stays a plain travel to the
--     entrance (the player is not sent inside), no instance.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:leveling:horde-ashenvale-26-30",
    updated = 1790985600,
    title = "Splintertree and Zoram'gar",
    category = "Leveling/Ashenvale",
    author = "NuuRoad",
    tags = { "horde", "ashenvale", "splintertree", "zoramgar", "orgrimmar" },
    levels = { from = 26, to = 30 },
    cond = { faction = "Horde" },
    source = "Ported from the Ashenvale leg of RestedXP's Classic \"26-30 Ashenvale / Thousand Needles\" (RestedXP Horde 20-30.lua).",

    data = {
        map = 1440,

        sections = {
            { title = "Orgrimmar", map = 1454, steps = {
                { type = "travel", to = "Orgrimmar", zone = 1454, at = { { 4512, 6389 } }, radius = 400,
                  note = "Fly to Orgrimmar from Tharm at Sun Rock Retreat, or from the Crossroads if you are there." },
                { type = "talk", npc = { 3344 }, cond = { class = "SHAMAN" }, note = "Train your new ranks." },
                { type = "talk", npc = { 3352 }, cond = { class = "HUNTER" }, note = "Train your new ranks." },
                { type = "talk", npc = { 10088 }, cond = { class = "HUNTER" }, note = "Train your pet's new ranks." },
                { type = "talk", npc = { 3353 }, cond = { class = "WARRIOR" }, note = "Train your new ranks." },
                { type = "talk", npc = { 3328 }, cond = { class = "ROGUE" }, note = "Train your new ranks." },
                { type = "talk", npc = { 3324 }, cond = { class = "WARLOCK" }, note = "Train your new ranks." },
                { type = "talk", npc = { 5883 }, cond = { class = "MAGE" }, note = "Train your new ranks." },
                { type = "talk", npc = { 6018 }, cond = { class = "PRIEST" }, note = "Train your new ranks." },
            } },

            { title = "To Splintertree Post", steps = {
                { type = "travel", to = "Orgrimmar's west gate", with = "ramp", at = { { 1620, 6220, map = 1454 } } },
                { type = "travel", to = "The ramp into Ashenvale", label = "ramp", at = { { 9470, 7680 }, { 9080, 6690 } },
                  note = "Follow the river north along the edge of Ashenvale, then take the ramp up. Spiders of level 28 and 29 live around it." },
                { type = "travel", to = "Splintertree Post", area = 431,
                  at = { { 8850, 6490 }, { 8170, 6290 }, { 7320, 6160 } }, radius = 400,
                  note = "Through the lumber camp and west along the road." },
                { type = "flight", node = 61, npc = { 12616 } },
            } },

            { title = "Splintertree Post", steps = {
                { group = {
                    { type = "accept", quests = { 6441 }, npc = { 12724 } },
                    { type = "turnin", quests = { 235, 742, 6382 }, npc = { 12696 }, optional = true,
                      note = "The Ashenvale Hunt from the Barrens or Orgrimmar, if you carry it." },
                    { type = "accept", quests = { 6383 }, npc = { 12696 } },
                    { type = "turnin", quests = { 6383 }, npc = { 12696 },
                      note = "Hand it straight back: the three hunt quests open once it is done." },
                } },
                { type = "hearth", area = 431, npc = { 12196 }, cond = { class = "ROGUE" },
                  note = "Rogues come back here from Blackfathom Deeps." },
                { type = "accept", quests = { 25 }, npc = { 12737 } },
                { type = "accept", quests = { 6503 }, npc = { 12867 } },
                { type = "kill", kill = { 12856 }, quest = { 6503, 1 }, radius = 600,
                  at = { { 7250, 7250 }, { 7630, 7110 }, { 7630, 6730 } },
                  note = "The Ashenvale Outrunners are stealthed. Walk the woods south and east of the post until they show themselves." },
                { type = "accept", quests = { 6544 }, npc = { 12858 },
                  note = "If Torek is not there, wait a few minutes for him to come back." },
                { type = "escort", quest = 6544, npc = { 12858 }, at = { { 6465, 7535 } },
                  note = "Follow Torek into Silverwing Outpost and let him and his raiders take the first blows. Waves of defenders come out inside the building, and Duriel Moonfire last. Warlocks: bring the voidwalker." },
            } },

            { title = "The satyrs and the hunt", steps = {
                { type = "travel", to = "Along the river", with = "horns", at = { { 7230, 4980 } } },
                { type = "collect", item = 5481, kill = { 3758, 3759, 3762, 3763 }, quest = { 6441, 1 }, label = "horns",
                  radius = 500, at = { { 6820, 5400 }, { 6680, 5257 }, { 6643, 5396 }, { 6733, 5538 }, { 6673, 5717 } },
                  note = "Felmusk satyrs at the camp in the hills." },
                { group = {
                    { type = "collect", item = 5686, kill = { 4273 }, quest = { 1088, 1 }, at = { { 6205, 5137 } },
                      note = "Keeper Ordanus is at the top of the building. Burst him down, loot his head and jump off the building to get away." },
                    { type = "collect", item = 16304, starts = 24, kill = { 12677 }, radius = 600,
                      at = { { 6220, 4960 }, { 5800, 5620 }, { 5190, 5430 }, { 6120, 5150 } },
                      note = "Shadumbra is a panther who roams these woods. Kill her and take her head." },
                    { type = "collect", item = 5867, kill = { 4054 }, quest = 1195, radius = 500,
                      at = { { 6130, 5190 }, { 6074, 5183 }, { 5925, 5442 }, { 5866, 5687 } },
                      note = "Laughing Sisters drop the Etched Phial for The Sacred Flame. One is enough." },
                } },
                { type = "accept", quests = { 24 }, item = 16304, note = "Use Shadumbra's Head to start its quest." },
            } },

            { title = "Zoram'gar Outpost", cond = { class = "ROGUE" }, steps = {
                { type = "travel", to = "Zoram'gar Outpost", area = 2897, at = { { 1630, 2980 } }, radius = 500,
                  note = "The long way west. Keep clear of the Astranaar guards on the road." },
                { type = "flight", node = 58, npc = { 11901 } },
                { group = {
                    { type = "accept", quests = { 216 }, npc = { 12757 } },
                    { type = "accept", quests = { 6462 }, npc = { 12721 } },
                    { type = "turnin", quests = { 6562 }, npc = { 12736 }, optional = true },
                    { type = "accept", quests = { 6641 }, npc = { 12717 },
                      note = "Taking it starts an escort. Muglash walks to the brazier on the shore." },
                } },
                { type = "escort", quest = 6641, npc = { 12717 }, at = { { 959, 2758 } },
                  note = "Put out the brazier. Naga come in waves; when Vorsha the Lasher arrives, let Muglash take her attention before you attack." },
            } },

            { title = "Thistlefur Village", cond = { class = "ROGUE" }, steps = {
                { type = "travel", to = "Thistlefur Village", area = 2301, label = "thistlefur", at = { { 3850, 3610 } }, radius = 400,
                  note = "Kill Thistlefur Avengers and Shaman on the way to the cave." },
                { type = "travel", to = "Thistlefur Hold", at = { { 3840, 3060 } } },
                { type = "collect", item = 16602, quest = { 6462, 1 }, object = "Troll Chest", radius = 400,
                  at = { { 4019, 3099 }, { 4076, 3281 }, { 3996, 3308 }, { 4086, 3364 }, { 4134, 3418 }, { 4151, 3477 }, { 4167, 3570 } },
                  note = "The small chests along the tunnels of the hold." },
                { type = "accept", quests = { 6482 }, npc = { 12818 },
                  note = "Taking it starts the escort. Be ready before you do." },
                { type = "escort", quest = 6482, npc = { 12818 }, at = { { 3853, 3732 } },
                  note = "Keep Ruul alive on the way out of the village. The furbolgs that attack count for your kills." },
                { group = {
                    { type = "kill", kill = { 3925 }, quest = { 216, 1 }, from = "thistlefur", radius = 500,
                      at = { { 3956, 3773 }, { 3793, 3452 }, { 3926, 3628 } } },
                    { type = "kill", kill = { 3924 }, quest = { 216, 2 }, from = "thistlefur", radius = 500,
                      at = { { 3614, 3698 }, { 3964, 3684 }, { 3570, 3694 } } },
                } },
            } },

            { title = "Mystral Lake", steps = {
                { type = "collect", item = 7770, use = { 7767 }, object = "Ruins of Stardust Fountain", quest = { 1534, 1 },
                  cond = { class = "SHAMAN" }, at = { { 3355, 6747 } },
                  note = "Fill the Empty Blue Waterskin at the fountain in the Ruins of Stardust." },
                { type = "collect", item = 16303, starts = 23, kill = { 12678 }, radius = 500,
                  at = { { 4150, 6740 }, { 4430, 6860 }, { 4380, 6360 }, { 4140, 6590 }, { 3976, 6521 } },
                  note = "Ursangous is a bear who walks a clockwise loop here. Kill him and take his paw." },
                { type = "accept", quests = { 23 }, item = 16303, note = "Use Ursangous's Paw to start its quest." },
                { type = "accept", quests = { 1918 }, item = 16408, kill = { 12759 }, sticky = true, at = { { 4600, 7000 } },
                  note = "Tideress swims around the middle of Mystral Lake. Kill her whenever you find her, and use the Befouled Water Globe she drops to start its quest." },
                { type = "travel", to = "The gazebo on Mystral Lake", quest = { 25, 2 }, at = { { 4893, 6956 } }, radius = 200,
                  note = "Swim under the gazebo in the middle of the lake: that is the scouting for Stonetalon Standstill." },
                { type = "kill", kill = { 3917 }, quest = { 25, 1 }, radius = 600,
                  at = { { 4890, 6960 }, { 4508, 6930 }, { 4626, 7066 }, { 4835, 7276 }, { 5122, 7336 } },
                  note = "Befouled Water Elementals all over the lake." },
                { type = "collect", item = 5868, use = { 5867 }, object = "Ashenvale Moonwell", quest = { 1195, 1 },
                  at = { { 6020, 7291 } }, note = "Fill the Etched Phial at the moonwell." },
            } },

            { title = "Back to Splintertree", steps = {
                { type = "turnin", quests = { 6503 }, npc = { 12867 } },
                { type = "collect", item = 16305, starts = 2, kill = { 12676 }, radius = 600,
                  at = { { 7240, 7210 }, { 7570, 7000 }, { 7820, 6550 }, { 7530, 7200 } },
                  note = "Sharptalon is a big bird who flies a clockwise loop. Bring him to about 60% health, then pull him back to the post and finish him there." },
                { type = "accept", quests = { 2 }, item = 16305, note = "Use Sharptalon's Claw to start its quest." },
                { group = {
                    { type = "turnin", quests = { 6544 }, npc = { 12877 }, optional = true },
                    { type = "talk", turnin = { 2, 24, 23 }, accept = { 247 }, npc = { 12696 } },
                    { type = "turnin", quests = { 247 }, npc = { 12696 } },
                    { type = "turnin", quests = { 25, 1918 }, npc = { 12737 } },
                    { type = "accept", quests = { 824 }, npc = { 12737 }, cond = { class = "ROGUE" },
                      note = "Keep the Befouled Water Globe: Je'neu wants it." },
                    { type = "turnin", quests = { 6482 }, npc = { 12837 }, optional = true },
                    { type = "turnin", quests = { 6441 }, npc = { 12724 } },
                } },
            } },

            { title = "Zoram'gar again", cond = { class = "ROGUE" }, steps = {
                { type = "travel", to = "Zoram'gar Outpost", area = 2897, at = { { 1224, 3380 } }, radius = 400,
                  note = "Fly there from Vhulgra." },
                { group = {
                    { type = "turnin", quests = { 216 }, npc = { 12757 } },
                    { type = "turnin", quests = { 6462 }, npc = { 12721 } },
                    { type = "turnin", quests = { 824 }, npc = { 12736 } },
                    { type = "turnin", quests = { 6641 }, npc = { 12863 }, optional = true },
                    { type = "accept", quests = { 6921, 6563 }, npc = { 12736 } },
                } },
                { type = "travel", to = "Blackfathom Deeps", at = { { 1400, 1500 } }, radius = 400,
                  note = "North along the shore to the sunken temple." },
                { type = "collect", item = 16790, starts = 6564, kill = { 4802 }, at = { { 1355, 1206 } },
                  note = "Kill Blackfathom Tide Priestesses until one drops the Damp Note." },
                { type = "accept", quests = { 6564 }, item = 16790, note = "Use the Damp Note to start its quest." },
                { type = "collect", item = 16784, quest = { 6563, 1 }, object = "Sapphire of Aku'Mai", radius = 300,
                  at = { { 1359, 1314 }, { 1290, 1322 }, { 1369, 1227 } },
                  note = "Stealth along the way in and pick the sapphires off the walls." },
                { type = "note", note = "Baron Aquanis and the Fathom Core for Amongst the Ruins are inside the dungeon. NuuRoad's Blackfathom Deeps guide covers them; a rogue who is ready can try them alone now." },
                { type = "travel", to = "Splintertree Post", area = 431, at = { { 7399, 6065 } }, radius = 400,
                  note = "Hearth back to Splintertree Post. Buy food and drink if you need them." },
            } },

            { title = "Moonglade", map = 1450, steps = {
                { type = "travel", to = "Moonglade", zone = 1450, cond = { class = "DRUID" }, at = { { 5253, 4057 } }, radius = 400,
                  note = "Cast Teleport: Moonglade." },
                { type = "talk", npc = { 12042 }, cond = { class = "DRUID" }, note = "Train your new ranks." },
                { type = "finish", note = "Ashenvale is done. Go on to Thunder Bluff and continue with the Thousand Needles guide: hearth there if your stone is bound to Thunder Bluff, otherwise fly. Rogues fly to Orgrimmar first to train. The Sacred Flame goes to Zangen Stonehoof in Thunder Bluff." },
            } },
        },

        npcs = {
            [1454] = { -- Orgrimmar
                [3324] = { name = "Grol'dar", at = { 4798, 4593 }, note = "In the Cleft of Shadow." },
                [3328] = { name = "Ormok", at = { 4390, 5463 }, note = "In the Cleft of Shadow." },
                [3344] = { name = "Kardris Dreamseeker", at = { 3880, 3637 }, note = "In the Valley of Wisdom." },
                [3352] = { name = "Ormak Grimshot", at = { 6605, 1852 }, note = "In the Valley of Honor." },
                [3353] = { name = "Grezz Ragefist", at = { 7979, 3142 }, note = "In the Valley of Honor." },
                [5883] = { name = "Enyo", at = { 3878, 8567 }, note = "In the Valley of Spirits." },
                [6018] = { name = "Ur'kyo", at = { 3559, 8780 }, note = "In the Valley of Spirits." },
                [10088] = { name = "Xao'tsu", at = { 6632, 1481 }, note = "In the Valley of Honor, near Ormak Grimshot." },
            },
            [1450] = { -- Moonglade
                [12042] = { name = "Loganaar", at = { 5253, 4057 } },
            },
            [1440] = { -- Ashenvale
                [11901] = { name = "Andruk", at = { 1224, 3380 } },
                [12196] = { name = "Innkeeper Kaylisk", at = { 7399, 6065 }, note = "In the inn." },
                [12616] = { name = "Vhulgra", at = { 7318, 6159 } },
                [12696] = { name = "Senani Thunderheart", at = { 7378, 6146 } },
                [12717] = { name = "Muglash", at = { 1206, 3463 } },
                [12721] = { name = "Mitsuwa", at = { 1165, 3485 }, note = "In the hut with the trolls." },
                [12724] = { name = "Pixel", at = { 7306, 6148 } },
                [12736] = { name = "Je'neu Sancrea", at = { 1156, 3429 } },
                [12737] = { name = "Mastok Wrilehiss", at = { 7367, 6000 } },
                [12757] = { name = "Karang Amakkar", at = { 1190, 3454 } },
                [12818] = { name = "Ruul Snowhoof", at = { 4153, 3449 } },
                [12837] = { name = "Yama Snowhoof", at = { 7411, 6092 }, note = "In the inn." },
                [12858] = { name = "Torek", at = { 6834, 7530 } },
                [12863] = { name = "Warsong Runner", at = { 1222, 3422 } },
                [12867] = { name = "Kuray'bin", at = { 7111, 6812 }, note = "South of the post, by the road." },
                [12877] = { name = "Ertog Ragetusk", at = { 7303, 6247 } },

                -- Kill targets: the steps that fight them say where.
                [3758] = "Felmusk Satyr",
                [3759] = "Felmusk Rogue",
                [3762] = "Felmusk Felsworn",
                [3763] = "Felmusk Shadowstalker",
                [3917] = "Befouled Water Elemental",
                [3924] = "Thistlefur Shaman",
                [3925] = "Thistlefur Avenger",
                [4054] = "Laughing Sister",
                [4273] = "Keeper Ordanus",
                [4802] = "Blackfathom Tide Priestess",
                [12856] = "Ashenvale Outrunner",

                -- Rares who wander a loop; their drops start quests.
                [12676] = "Sharptalon",
                [12677] = "Shadumbra",
                [12678] = "Ursangous",
                [12759] = "Tideress",
            },
        },
    },
})
