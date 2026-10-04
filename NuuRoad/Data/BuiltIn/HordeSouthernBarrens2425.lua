local _, ns = ...

-- Horde 24-25 leveling route through the southern Barrens: Thunder Bluff's
-- trainers, Camp Taurajo, the Razormane at Blackthorn Ridge, the Bael'dun
-- digsite and Bael Modan, ending at the Crossroads. Ported from RestedXP's
-- Classic "22-25 Hillsbrad / South Barrens" (RestedXP Horde 20-30.lua), from
-- where the route leaves Hillsbrad to the end of that registration; the
-- Hillsbrad half before it is its own guide, and "25-26 Stonetalon" follows.
-- Step order follows the source; quest IDs, NPC IDs, item IDs and coordinates
-- were checked against db/horde and Questie's Forever database (db/questie),
-- and Mangletooth and Jorn Skyseer stand where a recorded session
-- (Archive/20260923) met them. Wandering NPCs and rares take the database's
-- spawn points and patrol paths rather than the source's single markers.
-- "27-28 Southern Barrens JJ" covers the same quests in another order and was
-- used only to cross-check.
--
-- Forever differences: none found. db/horde and Questie's Forever data list no
-- new (9xxxx) quests in the southern Barrens, Camp Taurajo or Thunder Bluff
-- for this level range, and every quest here keeps its Classic ID, givers and
-- objectives.
--
-- Notes:
--   * The source's druid trip to Moonglade (teleport, train with Loganaar) is
--     left out: every class hearths to Thunder Bluff next and trains there,
--     and a trainer step cannot tell whether the ranks were already bought.
--     Its Trial of the Sea Lion steps are TBC-only in the source and stay out.
--   * The source's Tauren riding step is WotLK-only and stays out.
--   * The Flying Machine Airport is taken only at the 1x experience rate, as
--     in the source; the Stonetalon guide places the fogger.
--   * Owatanka and Washte Pawne are rares that drop quest starters. The source
--     hunts them alongside other steps; here each rides along with a later
--     step (Owatanka with Gann's first quest, Washte Pawne with the last Gann
--     turn-in), and the accept that follows passes by unless the item is in
--     the bags.
--   * The source turns in Revenge of Gann and takes the next one as two
--     steps; here it is one visit.
--   * A New Ore Sample needs level 25. Its accept is a step of its own after
--     the Camp Taurajo turn-ins and passes by below level 25 or without
--     Weapons of Choice handed in. It stays out of the Camp Taurajo group
--     (CheckGroups reports it beside the Weapons of Choice turn-in) because
--     its `now` gates must be read after that turn-in, not when the group
--     opens.
--   * CompareGuideOrder reports Accept Owatanka and Accept Washte Pawne behind
--     their neighbours: the source takes them on #completewith steps, and
--     here they follow the steps their pickups ride along with. It reports
--     Accept A New Ore Sample after the Jorn Skyseer turn-ins for the reason
--     above.
--   * Gann Stonespire walks the road south of Camp Taurajo; his steps carry
--     points along his path.
--
-- Check in client:
--   * The Thunder Bluff trainers the source names by coordinate: Kym Wildmane
--     (druid), Urek Thunderhorn (hunter), Hesuwa Thunderhorn (pets), Ker
--     Ragetotem (warrior), Siln Skychaser (shaman), Malakai Cross (priest) and
--     Thurston Xane (mage), from db/horde positions.
--   * The Bael Modan Flying Machine (object 3644) still stands at 46.97, 85.63
--     and the Explosive Stick of Gann (5021) is the item to press.
--   * Return to Thunder Bluff (1067) and The Flying Machine Airport (1086)
--     still start and end with Apothecary Zamah.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1413 The Barrens (guide default), 1456 Thunder Bluff.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:leveling:horde-southern-barrens-24-25"] = {
    schema = 2,
    id = "nuuroad:leveling:horde-southern-barrens-24-25",
    updated = 1791025067,
    map = 1413,
    only = "Horde",
    meta = {
        title = "Camp Taurajo and Bael Modan",
        author = "NuuRoad",
        category = "Leveling/The Barrens",
        tags = { "horde", "barrens", "taurajo", "bael modan", "thunder bluff" },
        levels = { 24, 25 },
    },
    steps = {
        { section = "Thunder Bluff", map = 1456, steps = {
            { travel = "Thunder Bluff", zone = "Thunder Bluff", at = { 45.81, 64.71 }, radius = 0.04,
                note = "Hearth to Thunder Bluff; the Barrens guide bound your hearthstone there." },
            { only = "Druid", npc = 3036,
                note = "Train your new ranks from Kym Wildmane, on the Elder Rise." },
            { only = "Hunter", npc = 3040,
                note = "Train your new ranks from Urek Thunderhorn, on the Hunter Rise." },
            { only = "Hunter", npc = 10086,
                note = "Train your pet's new ranks from Hesuwa Thunderhorn." },
            { only = "Warrior", npc = 3043,
                note = "Train your new ranks from Ker Ragetotem, on the Hunter Rise." },
            { only = "Shaman", npc = 3030,
                note = "Train your new ranks from Siln Skychaser, in the Pools of Vision under the Spirit Rise." },
            { group = {
                { turnin = 1067, npc = 3419, only = "now quest 1067",
                    note = "Apothecary Zamah is in the Pools of Vision, the cave under the Spirit Rise; enter at 29.84, 29.88." },
                { accept = 1086, npc = 3419, only = "now quest 1067 | xprate < 1.1",
                    note = "Only worth taking at the normal experience rate. The Stonetalon guide places the fogger." },
            } },
            { only = "Priest", npc = 3045,
                note = "Train your new ranks from Malakai Cross, in the Pools of Vision." },
            { only = "Mage", npc = 3049,
                note = "Train your new ranks from Thurston Xane, in the Pools of Vision." },
            { travel = "Camp Taurajo", subzone = "Camp Taurajo", at = { 44.45, 59.15, map = 1413 }, radius = 0.04,
                note = "Fly to Camp Taurajo from Tal, at the top of the totem tower in the middle of the Bluff." },
        } },

        { section = "Camp Taurajo", steps = {
            { group = {
                { turnin = 1823, accept = 1824, npc = 6394, only = "Warrior",
                    note = "Ruga Ragetotem is inside the building." },
                { accept = 879, npc = 3430,
                    note = "Mangletooth is in the cage." },
                { accept = 893, npc = 3433,
                    note = "Tatternack Steelforge, by the forge. Skip this if you already have Weapons of Choice." },
            } },
            { collect = 5102, starts = 884, kill = 3473, with = "gann", radius = 0.06,
                at = { { 44.20, 62.00 }, { 45.40, 62.80 }, { 49.20, 61.60 }, { 49.40, 59.20 } },
                note = "Owatanka, a blue thunder lizard, wanders south of the camp. If you meet him, kill him and take his Tailspike; if not, let him go." },
            { objective = 1824, part = 1, collect = 7119, count = 5, kill = { 3250, 3251, 3252 }, only = "Warrior", radius = 0.06,
                at = { { 48.10, 70.30 }, { 49.13, 69.10 }, { 47.29, 70.45 }, { 44.90, 72.55 }, { 43.92, 69.99 }, { 42.51, 72.07 } },
                note = "Silithid on the Field of Giants. The antennae spoil after fifteen minutes, so hand them in straight away." },
            { turnin = 1824, accept = 1825, npc = 6394, only = "Warrior",
                note = "Back to Ruga Ragetotem, inside the building." },
        } },

        { section = "Blackthorn Ridge", steps = {
            { collect = 5103, starts = 885, kill = 3472, with = "gann-done", radius = 0.06,
                at = { { 44.81, 74.93 }, { 44.81, 78.88 }, { 47.44, 79.87 }, { 43.15, 80.85 } },
                note = "Washte Pawne, a red wind serpent, flies over the ridge and the road. If you meet him, kill him and take his feather; if not, let him go." },
            { turnin = 1536, accept = 1534, npc = 5899, only = "Shaman | now quest 1536",
                note = "Brine, with the Filled Red Waterskin from Tarren Mill." },
            { accept = 843, npc = 3341, label = "gann", radius = 0.04,
                at = { { 46.01, 76.20 }, { 45.80, 77.81 }, { 46.14, 79.57 }, { 46.13, 82.27 }, { 46.07, 84.19 } },
                note = "Gann Stonespire walks the road south from here. Follow it until you meet him." },
            { accept = 884, use = 5102, only = "now item 5102",
                note = "Use Owatanka's Tailspike to start its quest." },
            { group = {
                { objective = 893, part = 1, collect = 5093, kill = { 3456, 3457 }, radius = 0.06,
                    at = { { 44.34, 79.96 }, { 43.19, 81.23 }, { 43.82, 84.12 }, { 42.67, 82.88 } },
                    note = "Razormane Pathfinders and Stalkers carry the Backstabber." },
                { objective = 893, part = 2, collect = 5092, kill = 3458, radius = 0.06,
                    at = { { 42.17, 78.34 }, { 42.12, 82.03 }, { 42.99, 83.28 }, { 44.47, 83.34 } },
                    note = "Razormane Seers carry the wand." },
                { objective = 893, part = 3, collect = 5094, kill = 3459, radius = 0.06,
                    at = { { 41.29, 78.80 }, { 42.03, 82.18 }, { 41.16, 79.86 }, { 40.77, 81.46 } },
                    note = "Razormane Warfrenzies carry the shield." },
                { objective = 879, part = 1, collect = 5074, kill = 3436, radius = 0.03,
                    at = { { 45.12, 80.07 }, { 43.64, 79.01 }, { 43.30, 80.15 }, { 43.99, 81.53 }, { 45.24, 80.83 } },
                    note = "Kuz walks all round the ridge." },
                { objective = 879, part = 3, collect = 5072, kill = 3435, radius = 0.02, at = { 40.15, 80.54 },
                    note = "Lok Orcbane is in the building at the top of the ramp." },
                { objective = 879, part = 2, collect = 5073, kill = 3434, radius = 0.03,
                    at = { { 43.75, 83.26 }, { 44.05, 84.18 }, { 44.52, 84.39 }, { 44.31, 83.33 } },
                    note = "Nak is on the southern end of the ridge." },
            } },
        } },

        { section = "Bael'dun digsite", steps = {
            { group = {
                { objective = 843, part = 1, kill = 3374, count = 15, radius = 0.05,
                    at = { { 47.55, 84.26 }, { 47.06, 83.87 }, { 47.27, 85.74 }, { 48.42, 86.01 } } },
                { objective = 843, part = 2, kill = 3375, count = 5, radius = 0.05,
                    at = { { 47.41, 84.32 }, { 47.72, 84.91 }, { 47.51, 85.38 }, { 48.10, 85.94 } } },
                { objective = 843, part = 3, collect = 5006, kill = 3392, radius = 0.03,
                    at = { { 47.44, 85.75 }, { 47.50, 85.06 }, { 47.94, 85.68 }, { 48.33, 86.16 } },
                    note = "Prospector Khazgorm walks among the diggers. Kill him and take his journal." },
            } },
            { turnin = 843, accept = 846, npc = 3341, radius = 0.04,
                at = { { 46.07, 84.19 }, { 46.13, 82.27 }, { 46.14, 79.57 }, { 45.80, 77.81 }, { 46.01, 76.20 } },
                note = "Find Gann on the road again." },
            { group = {
                { objective = 846, part = 1, collect = 5017, count = 6, kill = { 3376, 3377, 3378 }, radius = 0.04,
                    at = { { 49.43, 83.94 }, { 49.15, 84.13 }, { 48.69, 84.83 }, { 49.71, 83.95 } },
                    note = "The soldiers, riflemen and officers in the Bael Modan camp drop all three." },
                { objective = 846, part = 2, collect = 5018, count = 6, kill = { 3376, 3377, 3378 }, radius = 0.04,
                    at = { { 49.43, 83.94 }, { 49.15, 84.13 }, { 48.69, 84.83 }, { 49.71, 83.95 } } },
                { objective = 846, part = 3, collect = 5019, count = 6, kill = { 3376, 3377, 3378 }, radius = 0.04,
                    at = { { 49.43, 83.94 }, { 49.15, 84.13 }, { 48.69, 84.83 }, { 49.71, 83.95 } } },
            } },
            { turnin = 846, accept = 849, npc = 3341, radius = 0.04,
                at = { { 46.07, 84.19 }, { 46.13, 82.27 }, { 46.14, 79.57 }, { 45.80, 77.81 }, { 46.01, 76.20 } },
                note = "Back to Gann on the road." },
            { objective = 849, part = 1, object = "Bael Modan Flying Machine", use = 5021, at = { 46.97, 85.63 },
                note = "Use the Explosive Stick of Gann on the flying machine on its platform. It reaches a long way, so you can use it from the ground below." },
            { turnin = 849, npc = 3341, label = "gann-done", radius = 0.04,
                at = { { 46.07, 84.19 }, { 46.13, 82.27 }, { 46.14, 79.57 }, { 45.80, 77.81 }, { 46.01, 76.20 } },
                note = "Find Gann once more." },
            { accept = 885, use = 5103, only = "now item 5103",
                note = "Use Washte Pawne's Feather to start its quest." },
        } },

        { section = "Back to Camp Taurajo", steps = {
            { group = {
                { turnin = 879, accept = 906, npc = 3430,
                    note = "Mangletooth, in the cage." },
                { turnin = 893, npc = 3433, only = "now quest 893" },
                { turnin = 885, npc = 3387, only = "now quest 885" },
                { turnin = 884, npc = 3387, only = "now quest 884" },
                { turnin = 883, npc = 3387, only = "now quest 883",
                    note = "Lakota'mani, if you still carry it from the northern Barrens." },
            } },
            { accept = 1153, npc = 3433, only = "now level 25 | now quest 893 finished",
                note = "Tatternack's next job needs level 25. Leave it if you are not there yet." },
            { travel = "The Crossroads", subzone = "The Crossroads", at = { 51.50, 30.34 }, radius = 0.04,
                note = "Fly to the Crossroads from Omusa Thunderhorn." },
            { turnin = 906, npc = 3429 },
            { finish = "The southern Barrens are done. Stonetalon is next. Keep A New Ore Sample, Speak with Thun'grim (warriors), Call of Water (shamans) and The Flying Machine Airport for later." },
        } },
    },
    names = {
        npcs = {
            [3030] = { "Siln Skychaser", at = { 22.82, 21.11, map = 1456 } },
            [3036] = { "Kym Wildmane", at = { 77.15, 29.82, map = 1456 } },
            [3040] = { "Urek Thunderhorn", at = { 59.13, 86.87, map = 1456 } },
            [3043] = { "Ker Ragetotem", at = { 57.58, 85.50, map = 1456 } },
            [3045] = { "Malakai Cross", at = { 24.56, 22.57, map = 1456 } },
            [3049] = { "Thurston Xane", at = { 25.18, 20.96, map = 1456 } },
            [3250] = "Silithid Creeper",
            [3251] = "Silithid Grub",
            [3252] = "Silithid Swarmer",
            [3341] = "Gann Stonespire",
            [3374] = "Bael'dun Excavator",
            [3375] = "Bael'dun Foreman",
            [3376] = "Bael'dun Soldier",
            [3377] = "Bael'dun Rifleman",
            [3378] = "Bael'dun Officer",
            [3387] = { "Jorn Skyseer", at = { 44.86, 59.14 } },
            [3392] = "Prospector Khazgorm",
            [3419] = { "Apothecary Zamah", at = { 22.82, 20.90, map = 1456 } },
            [3429] = { "Thork", at = { 51.50, 30.87 } },
            [3430] = { "Mangletooth", at = { 44.55, 59.24 } },
            [3433] = { "Tatternack Steelforge", at = { 45.10, 57.68 } },
            [3434] = "Nak",
            [3435] = "Lok Orcbane",
            [3436] = "Kuz",
            [3456] = "Razormane Pathfinder",
            [3457] = "Razormane Stalker",
            [3458] = "Razormane Seer",
            [3459] = "Razormane Warfrenzy",
            [3472] = "Washte Pawne",
            [3473] = "Owatanka",
            [5899] = { "Brine", at = { 43.42, 77.41 } },
            [6394] = { "Ruga Ragetotem", at = { 44.67, 59.42 } },
            [10086] = { "Hesuwa Thunderhorn", at = { 54.07, 84.00, map = 1456 } },
        },
        quests = {
            [843] = "Gann's Reclamation",
            [846] = "Revenge of Gann",
            [849] = "Revenge of Gann",
            [879] = "Betrayal from Within",
            [883] = "Lakota'mani",
            [884] = "Owatanka",
            [885] = "Washte Pawne",
            [893] = "Weapons of Choice",
            [906] = "Betrayal from Within",
            [1067] = "Return to Thunder Bluff",
            [1086] = "The Flying Machine Airport",
            [1153] = "A New Ore Sample",
            [1534] = "Call of Water",
            [1536] = "Call of Water",
            [1823] = "Speak with Ruga",
            [1824] = "Trial at the Field of Giants",
            [1825] = "Speak with Thun'grim",
        },
        items = {
            [5006] = "Khazgorm's Journal",
            [5017] = "Nitroglycerin",
            [5018] = "Wood Pulp",
            [5019] = "Sodium Nitrate",
            [5021] = "Explosive Stick of Gann",
            [5072] = "Lok's Skull",
            [5073] = "Nak's Skull",
            [5074] = "Kuz's Skull",
            [5092] = "Charred Razormane Wand",
            [5093] = "Razormane Backstabber",
            [5094] = "Razormane War Shield",
            [5102] = "Owatanka's Tailspike",
            [5103] = "Washte Pawne's Feather",
            [7119] = "Twitching Antenna",
        },
    },
}
