-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeSouthernBarrens2425.lua.
--
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
--     left out: every class hearths to Thunder Bluff next and trains there.
--     Its Trial of the Sea Lion steps are TBC-only in the source and stay out.
--   * The source's Tauren riding step is WotLK-only and stays out.
--   * The Flying Machine Airport: the source takes it only at the 1x
--     experience rate; the Stonetalon guide places the fogger.
--   * Owatanka and Washte Pawne are rares that drop quest starters. Each pickup
--     rides along with a later step (Owatanka with Gann's first quest, Washte
--     Pawne with the last Gann turn-in), and the accept that follows passes by
--     unless the item is in the bags.
--   * The source turns in Revenge of Gann and takes the next one as two
--     steps; here it is one visit.
--   * A New Ore Sample needs level 25. Its accept is a step of its own after
--     the Camp Taurajo turn-ins, outside the group.
--   * Gann Stonespire walks the road south of Camp Taurajo; his entry in
--     `npcs` carries points along his path.
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
-- Conversion notes:
--   * `now` gates dropped (the format has no waiting conditions): "now quest
--     1067" on the Zamah turn-in and accept, "now quest 1536" on Brine's
--     visit (its "Shaman" term is kept as cond), "now item 5102" and "now
--     item 5103" on the item accepts (an item accept now passes by itself
--     when the item is not in the bags), "now quest 893/885/884/883" on the
--     Camp Taurajo turn-ins (a turn-in with nothing to hand in passes), and
--     "now level 25 | now quest 893 finished" on A New Ore Sample (left to
--     the player; its note still says it needs level 25).
--   * "xprate < 1.1" on The Flying Machine Airport is dropped (the format has
--     no experience rate); the step note loses "Only worth taking at the
--     normal experience rate."
--   * Class trainer visits (`npc` and a note, no action) become `talk` steps
--     with `cond = { class = ... }`: the source names no spell IDs, so they
--     cannot be `learn` steps.
--   * Where a step note said where an NPC stands (inside the building, in
--     the cage, by the forge, on the Elder Rise / Hunter Rise, in the Pools
--     of Vision, the cave entrance at 29.84, 29.88), that text moved to the
--     NPC's `note`; the step keeps the rest.
--   * Gann Stonespire's five path points (written on each of his steps,
--     sometimes in reverse order) became his `at` list; his steps keep only
--     their radius (400). The order does not matter: the arrow takes the
--     nearest.
--   * Objectives: every `objective`/`part` became `quest = { id, n }` with
--     the source's part numbers; none inferred. Kill and collect `count`s
--     (15, 5, 5, 6, 6, 6) were dropped: the objective counts.
--   * No track/untrack pairs. The two rare pickups keep `with` on the step
--     they ride along with ("gann", "gann-done").
--   * Travel ends: Thunder Bluff gets zone = 1456. The Crossroads gets
--     area = 380 (the AreaTable ID used in docs/examples/guide-export.lua).
--     No AreaTable ID for Camp Taurajo was found in the repo, so that travel
--     step has no `area` and finishes on arrival at its point.
--   * Sections: "Thunder Bluff" keeps map = 1456 from the source; its last
--     step's point carries map = 1413. Other sections use the guide's 1413.
--   * Every NPC has a position except kill targets and the two rares, which
--     are named only; their steps carry the spawn points.
--   * No `materials`. The source's `names.quests` and `names.items`
--     are dropped (the client names them).

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:leveling:horde-southern-barrens-24-25",
    updated = 1791025067,
    title = "Camp Taurajo and Bael Modan",
    category = "Leveling/The Barrens",
    author = "NuuRoad",
    tags = { "horde", "barrens", "taurajo", "bael modan", "thunder bluff" },
    levels = { from = 24, to = 25 },
    cond = { faction = "Horde" },
    source = "Ported from RestedXP's Classic \"22-25 Hillsbrad / South Barrens\" (RestedXP Horde 20-30.lua).",

    data = {
        map = 1413,

        sections = {
            { title = "Thunder Bluff", map = 1456, steps = {
                { type = "travel", to = "Thunder Bluff", zone = 1456, at = { { 4581, 6471 } }, radius = 400,
                  note = "Hearth to Thunder Bluff; the Barrens guide bound your hearthstone there." },
                { type = "talk", npc = { 3036 }, cond = { class = "DRUID" },
                  note = "Train your new ranks from Kym Wildmane." },
                { type = "talk", npc = { 3040 }, cond = { class = "HUNTER" },
                  note = "Train your new ranks from Urek Thunderhorn." },
                { type = "talk", npc = { 10086 }, cond = { class = "HUNTER" },
                  note = "Train your pet's new ranks from Hesuwa Thunderhorn." },
                { type = "talk", npc = { 3043 }, cond = { class = "WARRIOR" },
                  note = "Train your new ranks from Ker Ragetotem." },
                { type = "talk", npc = { 3030 }, cond = { class = "SHAMAN" },
                  note = "Train your new ranks from Siln Skychaser." },
                { group = {
                    { type = "turnin", quests = { 1067 }, npc = { 3419 } },
                    { type = "accept", quests = { 1086 }, npc = { 3419 },
                      note = "The Stonetalon guide places the fogger." },
                } },
                { type = "talk", npc = { 3045 }, cond = { class = "PRIEST" },
                  note = "Train your new ranks from Malakai Cross." },
                { type = "talk", npc = { 3049 }, cond = { class = "MAGE" },
                  note = "Train your new ranks from Thurston Xane." },
                { type = "travel", to = "Camp Taurajo", at = { { 4445, 5915, map = 1413 } }, radius = 400,
                  note = "Fly to Camp Taurajo from Tal, at the top of the totem tower in the middle of the Bluff." },
            } },

            { title = "Camp Taurajo", steps = {
                { group = {
                    { type = "talk", turnin = { 1823 }, accept = { 1824 }, npc = { 6394 }, cond = { class = "WARRIOR" } },
                    { type = "accept", quests = { 879 }, npc = { 3430 } },
                    { type = "accept", quests = { 893 }, npc = { 3433 },
                      note = "Skip this if you already have Weapons of Choice." },
                } },
                { type = "collect", item = 5102, starts = 884, kill = { 3473 }, with = "gann", radius = 600,
                  at = { { 4420, 6200 }, { 4540, 6280 }, { 4920, 6160 }, { 4940, 5920 } },
                  note = "Owatanka, a blue thunder lizard, wanders south of the camp. If you meet him, kill him and take his Tailspike; if not, let him go." },
                { type = "collect", item = 7119, kill = { 3250, 3251, 3252 }, quest = { 1824, 1 },
                  cond = { class = "WARRIOR" }, radius = 600,
                  at = { { 4810, 7030 }, { 4913, 6910 }, { 4729, 7045 }, { 4490, 7255 }, { 4392, 6999 }, { 4251, 7207 } },
                  note = "Silithid on the Field of Giants. The antennae spoil after fifteen minutes, so hand them in straight away." },
                { type = "talk", turnin = { 1824 }, accept = { 1825 }, npc = { 6394 }, cond = { class = "WARRIOR" },
                  note = "Back to Ruga Ragetotem." },
            } },

            { title = "Blackthorn Ridge", steps = {
                { type = "collect", item = 5103, starts = 885, kill = { 3472 }, with = "gann-done", radius = 600,
                  at = { { 4481, 7493 }, { 4481, 7888 }, { 4744, 7987 }, { 4315, 8085 } },
                  note = "Washte Pawne, a red wind serpent, flies over the ridge and the road. If you meet him, kill him and take his feather; if not, let him go." },
                { type = "talk", turnin = { 1536 }, accept = { 1534 }, npc = { 5899 }, cond = { class = "SHAMAN" },
                  note = "Brine takes the Filled Red Waterskin from Tarren Mill." },
                { type = "accept", quests = { 843 }, npc = { 3341 }, label = "gann", radius = 400,
                  note = "Gann Stonespire walks the road south from here. Follow it until you meet him." },
                { type = "accept", quests = { 884 }, item = 5102,
                  note = "Use Owatanka's Tailspike to start its quest." },
                { group = {
                    { type = "collect", item = 5093, kill = { 3456, 3457 }, quest = { 893, 1 }, radius = 600,
                      at = { { 4434, 7996 }, { 4319, 8123 }, { 4382, 8412 }, { 4267, 8288 } },
                      note = "Razormane Pathfinders and Stalkers carry the Backstabber." },
                    { type = "collect", item = 5092, kill = { 3458 }, quest = { 893, 2 }, radius = 600,
                      at = { { 4217, 7834 }, { 4212, 8203 }, { 4299, 8328 }, { 4447, 8334 } },
                      note = "Razormane Seers carry the wand." },
                    { type = "collect", item = 5094, kill = { 3459 }, quest = { 893, 3 }, radius = 600,
                      at = { { 4129, 7880 }, { 4203, 8218 }, { 4116, 7986 }, { 4077, 8146 } },
                      note = "Razormane Warfrenzies carry the shield." },
                    { type = "collect", item = 5074, kill = { 3436 }, quest = { 879, 1 }, radius = 300,
                      at = { { 4512, 8007 }, { 4364, 7901 }, { 4330, 8015 }, { 4399, 8153 }, { 4524, 8083 } },
                      note = "Kuz walks all round the ridge." },
                    { type = "collect", item = 5072, kill = { 3435 }, quest = { 879, 3 }, radius = 200,
                      at = { { 4015, 8054 } },
                      note = "Lok Orcbane is in the building at the top of the ramp." },
                    { type = "collect", item = 5073, kill = { 3434 }, quest = { 879, 2 }, radius = 300,
                      at = { { 4375, 8326 }, { 4405, 8418 }, { 4452, 8439 }, { 4431, 8333 } },
                      note = "Nak is on the southern end of the ridge." },
                } },
            } },

            { title = "Bael'dun digsite", steps = {
                { group = {
                    { type = "kill", kill = { 3374 }, quest = { 843, 1 }, radius = 500,
                      at = { { 4755, 8426 }, { 4706, 8387 }, { 4727, 8574 }, { 4842, 8601 } } },
                    { type = "kill", kill = { 3375 }, quest = { 843, 2 }, radius = 500,
                      at = { { 4741, 8432 }, { 4772, 8491 }, { 4751, 8538 }, { 4810, 8594 } } },
                    { type = "collect", item = 5006, kill = { 3392 }, quest = { 843, 3 }, radius = 300,
                      at = { { 4744, 8575 }, { 4750, 8506 }, { 4794, 8568 }, { 4833, 8616 } },
                      note = "Prospector Khazgorm walks among the diggers. Kill him and take his journal." },
                } },
                { type = "talk", turnin = { 843 }, accept = { 846 }, npc = { 3341 }, radius = 400,
                  note = "Find Gann on the road again." },
                { group = {
                    { type = "collect", item = 5017, kill = { 3376, 3377, 3378 }, quest = { 846, 1 }, radius = 400,
                      at = { { 4943, 8394 }, { 4915, 8413 }, { 4869, 8483 }, { 4971, 8395 } },
                      note = "The soldiers, riflemen and officers in the Bael Modan camp drop all three." },
                    { type = "collect", item = 5018, kill = { 3376, 3377, 3378 }, quest = { 846, 2 }, radius = 400,
                      at = { { 4943, 8394 }, { 4915, 8413 }, { 4869, 8483 }, { 4971, 8395 } } },
                    { type = "collect", item = 5019, kill = { 3376, 3377, 3378 }, quest = { 846, 3 }, radius = 400,
                      at = { { 4943, 8394 }, { 4915, 8413 }, { 4869, 8483 }, { 4971, 8395 } } },
                } },
                { type = "talk", turnin = { 846 }, accept = { 849 }, npc = { 3341 }, radius = 400,
                  note = "Back to Gann on the road." },
                { type = "interact", object = "Bael Modan Flying Machine", use = { 5021 }, quest = { 849, 1 },
                  at = { { 4697, 8563 } },
                  note = "Use the Explosive Stick of Gann on the flying machine on its platform. It reaches a long way, so you can use it from the ground below." },
                { type = "turnin", quests = { 849 }, npc = { 3341 }, label = "gann-done", radius = 400,
                  note = "Find Gann once more." },
                { type = "accept", quests = { 885 }, item = 5103,
                  note = "Use Washte Pawne's Feather to start its quest." },
            } },

            { title = "Back to Camp Taurajo", steps = {
                { group = {
                    { type = "talk", turnin = { 879 }, accept = { 906 }, npc = { 3430 } },
                    { type = "turnin", quests = { 893 }, npc = { 3433 } },
                    { type = "turnin", quests = { 885 }, npc = { 3387 } },
                    { type = "turnin", quests = { 884 }, npc = { 3387 } },
                    { type = "turnin", quests = { 883 }, npc = { 3387 },
                      note = "Lakota'mani, if you still carry it from the northern Barrens." },
                } },
                { type = "accept", quests = { 1153 }, npc = { 3433 },
                  note = "Tatternack's next job needs level 25. Leave it if you are not there yet." },
                { type = "travel", to = "The Crossroads", area = 380, at = { { 5150, 3034 } }, radius = 400,
                  note = "Fly to the Crossroads from Omusa Thunderhorn." },
                { type = "turnin", quests = { 906 }, npc = { 3429 } },
                { type = "finish", note = "The southern Barrens are done. Stonetalon is next. Keep A New Ore Sample, Speak with Thun'grim (warriors), Call of Water (shamans) and The Flying Machine Airport for later." },
            } },
        },

        npcs = {
            [1456] = { -- Thunder Bluff
                [3030] = { name = "Siln Skychaser", at = { 2282, 2111 },
                           note = "In the Pools of Vision under the Spirit Rise." },
                [3036] = { name = "Kym Wildmane", at = { 7715, 2982 }, note = "On the Elder Rise." },
                [3040] = { name = "Urek Thunderhorn", at = { 5913, 8687 }, note = "On the Hunter Rise." },
                [3043] = { name = "Ker Ragetotem", at = { 5758, 8550 }, note = "On the Hunter Rise." },
                [3045] = { name = "Malakai Cross", at = { 2456, 2257 }, note = "In the Pools of Vision." },
                [3049] = { name = "Thurston Xane", at = { 2518, 2096 }, note = "In the Pools of Vision." },
                [3419] = { name = "Apothecary Zamah", at = { 2282, 2090 },
                           note = "In the Pools of Vision, the cave under the Spirit Rise; enter at 29.84, 29.88." },
                [10086] = { name = "Hesuwa Thunderhorn", at = { 5407, 8400 } },
            },
            [1413] = { -- The Barrens
                -- Visited.
                [3341] = { name = "Gann Stonespire",
                           at = { { 4601, 7620 }, { 4580, 7781 }, { 4614, 7957 }, { 4613, 8227 }, { 4607, 8419 } },
                           note = "Walks the road south of Camp Taurajo." },
                [3387] = { name = "Jorn Skyseer", at = { 4486, 5914 } },
                [3429] = { name = "Thork", at = { 5150, 3087 } },
                [3430] = { name = "Mangletooth", at = { 4455, 5924 }, note = "In the cage." },
                [3433] = { name = "Tatternack Steelforge", at = { 4510, 5768 }, note = "By the forge." },
                [5899] = { name = "Brine", at = { 4342, 7741 } },
                [6394] = { name = "Ruga Ragetotem", at = { 4467, 5942 }, note = "Inside the building." },

                -- Kill targets.
                [3250] = "Silithid Creeper",
                [3251] = "Silithid Grub",
                [3252] = "Silithid Swarmer",
                [3374] = "Bael'dun Excavator",
                [3375] = "Bael'dun Foreman",
                [3376] = "Bael'dun Soldier",
                [3377] = "Bael'dun Rifleman",
                [3378] = "Bael'dun Officer",
                [3392] = "Prospector Khazgorm",
                [3434] = "Nak",
                [3435] = "Lok Orcbane",
                [3436] = "Kuz",
                [3456] = "Razormane Pathfinder",
                [3457] = "Razormane Stalker",
                [3458] = "Razormane Seer",
                [3459] = "Razormane Warfrenzy",

                -- Rares whose drops start quests.
                [3472] = "Washte Pawne",
                [3473] = "Owatanka",
            },
        },
    },
})
