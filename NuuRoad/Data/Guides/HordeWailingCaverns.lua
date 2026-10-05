-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeWailingCaverns.lua.
--
-- Every Horde quest of Wailing Caverns, from the Barrens chains that unlock them to the
-- last turn-in at Thunder Bluff. Quest, NPC and item IDs, coordinates, the waypoints up
-- the hill, and the turn-in order after the dungeon (Ratchet, then Falla on the hill,
-- then the ledge, then Thunder Bluff, climbing the hill once instead of twice) are
-- NuuRoad's own. The raptor horn camps are the ones the Barrens guide
-- (HordeBarrens.lua) already uses.
--
-- The guide stands on its own. A player arriving from the Barrens guide with Hamuul
-- Runetotem and Raptor Horns done has those quests finished, so their steps pass.
--
-- Recorded choices:
--   * The Barrens Oases (886) is left out: Tonga offers The Forgotten Pools without it.
--   * Apothecary Zamah (853) is taken last at the Crossroads, as the Barrens guide does,
--     because it is timed once accepted.
--   * Only the Glowing Shard drop 6981 is carried, not the alternate 3366.
--   * No hearth step: binding at Ratchet before the run saves a flight afterwards, but it
--     is the player's hearthstone, so it is a note.
--   * The inside of the dungeon has no coordinates. The bosses are placed by note (on
--     their `npcs` entries, with `instance`); the instance map is not in the travel data.
--
-- Maps: 1413 The Barrens (guide default), 1456 Thunder Bluff.
--
-- Conversion notes:
--   * `only = "Horde"` became the wrapper's `cond = { faction = "Horde" }`.
--   * Dropped quest-state gates, which the format cannot carry (a step whose quest is
--     finished passes on its own): "not quest 1489" on Tonga's accept and turn-ins
--     (870, 870/877, 877/880, 880/1489), "not quest 853" on Helbrim's (848, 848, 853),
--     "not quest 1491" on Mebok's 865 accept, and "not quest N finished" on the
--     objective steps for 870, 848, 877, 880 and 865.
--   * Turn-ins gated on "quest N readyToTurnIn" (1491, 959, 1486, 1487, 914, 962) and
--     on "quest N" in the log (the 6981/3369 talk with Falla, 3369 to Hamuul) became
--     `optional = true`: passed on arrival unless ready, never waited on.
--   * "only = quest 6981" on the Sputtervalve talk step and on the travel up the hill
--     cannot be expressed; dropped. Without the shard, the player skips them (the talk
--     step's note and the next travel's note say so).
--   * Objective counts dropped (4 spores, 8 shells, 5 horns, 6 essences, 10 blooms, 20
--     hides, 7 of each Deviate): the objective says how many. No objective numbers were
--     inferred; every `quest = { id, n }` is the source's objective/part.
--   * The Glowing Shard accept (6981) gained `item = 10441`, the item the step before
--     collects with `starts = 6981`; the source accept named no item.
--   * The Disciple of Naralex step (npc only, no quest) stays a `note` step with `npc`.
--   * Sputtervalve's objective step (6981 part 1, with npc) became a `talk` step with
--     `quest = { 6981, 1 }`.
--   * Travel `zone = "Wailing Caverns"` became `instance = 43` (the instance ID the
--     format's example uses for Wailing Caverns); the source's `at` on that step is kept
--     as the portal point. `zone = "The Barrens"` became `zone = 1413`.
--   * Location notes moved from steps to NPCs: Hamuul (Elder Rise), Zamah (Pools of
--     Vision and the way in), Falla (the building on the hill), the four Fanglords,
--     Mutanus and the Disciple (inside the dungeon, `instance = 43`, listed under 1413).
--     Lady Anacondra's step-specific wording "The first boss" is kept on her step.
--   * NPCs with no position: the kill targets (Sunscale Scytheclaw, Oasis Snapjaw, the
--     Deviates, Mad Magglish) and the dungeon NPCs, which carry `instance` instead.
--   * Quest and item names from `names` are dropped: the client names them.
--   * The Thunder Bluff section keeps `map = 1456`; no other section needed a map.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:dungeon:horde-wailing-caverns-quests",
    updated = 1790208000,
    title = "Wailing Caverns",
    category = "Dungeons/Wailing Caverns",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "wailing caverns", "wc", "barrens" },
    levels = { from = 17, to = 24 },
    cond = { faction = "Horde" },

    data = {
        map = 1413,

        sections = {
            { title = "Unlocking the quests", steps = {
                { type = "note", note = "Hamuul Runetotem, Apothecary Zamah and Raptor Horns lead to three of the dungeon quests. Steps for any of them you have already finished are passed over." },
                { group = {
                    { type = "accept", quests = { 870 }, npc = { 3448 } },
                    { type = "accept", quests = { 848 }, npc = { 3390 } },
                } },
                { type = "interact", object = "bubbling rock", quest = { 870, 1 }, radius = 300, at = { { 4507, 2253 } },
                  note = "Swim down beside the bubbling rock in the Forgotten Pools." },
                { type = "collect", item = 5012, object = "Laden Mushroom", quest = { 848, 1 }, radius = 400,
                  at = { { 4470, 2310 }, { 4390, 2440 }, { 4553, 2180 } }, note = "Large blue mushrooms around the pools." },
                { group = {
                    { type = "talk", turnin = { 870 }, accept = { 877 }, npc = { 3448 } },
                    { type = "turnin", quests = { 848 }, npc = { 3390 } },
                } },
                { type = "accept", quests = { 865 }, npc = { 3446 } },
                { type = "interact", object = "Bubbling Fissure", quest = { 877, 1 }, radius = 300, at = { { 5561, 4274 } },
                  note = "Underwater in the Stagnant Oasis, on the way back from Ratchet." },
                { type = "talk", turnin = { 877 }, accept = { 880 }, npc = { 3448 } },
                { type = "collect", item = 5098, kill = { 3461 }, quest = { 880, 1 }, radius = 500, at = { { 5553, 4270 } },
                  note = "Turtles in and around the Stagnant Oasis." },
                { type = "collect", item = 5055, kill = { 3256 }, quest = { 865, 1 }, radius = 500,
                  at = { { 5736, 5238 }, { 5701, 5445 }, { 5785, 5390 } }, note = "Purple raptors south of the oasis." },
            } },

            { title = "Ratchet and the Crossroads", steps = {
                { group = {
                    { type = "talk", turnin = { 865 }, accept = { 1491 }, npc = { 3446 },
                      note = "Innkeeper Wiley is here. Binding your hearthstone to Ratchet now saves a flight after the dungeon, whose first turn-ins are in Ratchet." },
                    { type = "accept", quests = { 959 }, npc = { 3665 } },
                } },
                { group = {
                    { type = "talk", turnin = { 880 }, accept = { 1489 }, npc = { 3448 } },
                    { type = "accept", quests = { 853 }, npc = { 3390 },
                      note = "Apothecary Zamah is timed. Fly to Thunder Bluff straight away." },
                } },
            } },

            { title = "Thunder Bluff", map = 1456, steps = {
                { group = {
                    { type = "talk", turnin = { 1489 }, accept = { 1490 }, npc = { 5769 } },
                    { type = "talk", turnin = { 1490 }, accept = { 914 }, npc = { 5770 } },
                } },
                { type = "talk", turnin = { 853 }, accept = { 962 }, npc = { 3419 } },
            } },

            { title = "The hidden cave above the entrance", steps = {
                { type = "travel", to = "the path up the hill", at = { { 5032, 3544 } },
                  note = "Fly back to the Crossroads. The two quest givers at Wailing Caverns stand in a small cave above the entrance, reached over the hill by jumping down onto a stone." },
                { type = "travel", to = "the top of the hill", at = { { 4809, 3295 } } },
                { type = "travel", to = "the path down the far side", at = { { 4728, 3356 } } },
                { type = "travel", to = "the ledge over the cave mouth", at = { { 4586, 3586 } },
                  note = "Drop carefully onto the stone at 45.77, 36.16 below you, then walk into the small cave." },
                { group = {
                    { type = "accept", quests = { 1486 }, npc = { 5767 } },
                    { type = "accept", quests = { 1487 }, npc = { 5768 } },
                } },
            } },

            { title = "The outer caverns", steps = {
                { type = "travel", to = "the cave mouth", at = { { 4597, 3633 } },
                  note = "Drop down from the ledge and walk into the caverns below." },
                { type = "collect", item = 5334, kill = { 3655 }, quest = { 959, 1 }, radius = 400,
                  at = { { 4569, 3360 }, { 4684, 3463 }, { 4647, 3550 } },
                  note = "Mad Magglish is stealthed and slow to respawn. Skip this if he is not up; you can look again on the way out." },
                { type = "travel", to = "Wailing Caverns", instance = 43, at = { { 4775, 3486 } },
                  note = "Go north through the caverns, cross the water and the bridge, and step into the portal with your group." },
            } },

            { title = "Inside Wailing Caverns", steps = {
                { type = "collect", item = 6464, quest = { 1491, 1 }, sticky = true,
                  note = "Ectoplasms throughout the dungeon drop it." },
                { type = "collect", item = 5339, quest = { 962, 1 }, sticky = true,
                  note = "Small green, purple and pink plants along the walls. There are not enough for a whole group in one run; agree who picks." },
                { type = "collect", item = 6443, quest = { 1486, 1 }, sticky = true,
                  note = "Any Deviate beast can drop one." },
                { type = "kill", kill = { 3636 }, quest = { 1487, 1 }, sticky = true, note = "In the Screaming Gully." },
                { type = "kill", kill = { 5755 }, quest = { 1487, 2 }, sticky = true, note = "In the Pit of Fangs." },
                { type = "kill", kill = { 5761 }, quest = { 1487, 3 }, sticky = true, note = "In the Crag of the Everliving." },
                { type = "kill", kill = { 5056 }, quest = { 1487, 4 }, sticky = true, note = "In the Winding Chasm." },
                { type = "collect", item = 9739, kill = { 3671 }, quest = { 914, 2 }, note = "The first boss." },
                { type = "collect", item = 9738, kill = { 3669 }, quest = { 914, 1 } },
                { type = "collect", item = 9740, kill = { 3670 }, quest = { 914, 3 } },
                { type = "collect", item = 9741, kill = { 3673 }, quest = { 914, 4 } },
                { type = "note", npc = { 3678 },
                  note = "With the four Fanglords dead, talk to the Disciple of Naralex and escort him to Naralex. Guard him through the waves that come." },
                { type = "collect", item = 10441, starts = 6981, kill = { 3654 } },
                { type = "accept", quests = { 6981 }, item = 10441, note = "Use the Glowing Shard to start its quest." },
                { type = "travel", to = "the cave mouth", zone = 1413, at = { { 4597, 3633 } },
                  note = "Leave through the portal and walk back out of the caverns." },
            } },

            { title = "Turning in", steps = {
                { group = {
                    { type = "turnin", quests = { 1491 }, npc = { 3446 }, optional = true },
                    { type = "turnin", quests = { 959 }, npc = { 3665 }, optional = true },
                    { type = "talk", npc = { 3442 }, quest = { 6981, 1 },
                      note = "Ask Sputtervalve about the Glowing Shard." },
                } },
                { type = "travel", to = "the path up the hill", at = { { 5032, 3544 } },
                  note = "Fly to the Crossroads and walk back to the hill." },
                { type = "talk", turnin = { 6981 }, accept = { 3369 }, npc = { 8418 }, optional = true },
                { type = "travel", to = "the path down the far side", at = { { 4728, 3356 } },
                  note = "Without a Glowing Shard to hand in, fly to the Crossroads and take the path up the hill from 50.32, 35.44." },
                { type = "travel", to = "the ledge over the cave mouth", at = { { 4586, 3586 } },
                  note = "Drop onto the stone at 45.77, 36.16 and walk into the small cave." },
                { group = {
                    { type = "turnin", quests = { 1486 }, npc = { 5767 }, optional = true },
                    { type = "turnin", quests = { 1487 }, npc = { 5768 }, optional = true },
                } },
                { group = {
                    { type = "turnin", quests = { 914 }, npc = { 5770 }, optional = true },
                    { type = "turnin", quests = { 3369 }, npc = { 5769 }, optional = true },
                    { type = "turnin", quests = { 962 }, npc = { 3419 }, optional = true,
                      note = "Back down in the Pools of Vision." },
                } },
                { type = "finish", note = "Every Horde quest of Wailing Caverns is done or left for another run." },
            } },
        },

        npcs = {
            [1413] = { -- The Barrens
                [3390] = { name = "Apothecary Helbrim", at = { 5144, 3015 } },
                [3442] = { name = "Sputtervalve", at = { 6298, 3722 } },
                [3446] = { name = "Mebok Mizzyrix", at = { 6237, 3762 } },
                [3448] = { name = "Tonga Runetotem", at = { 5226, 3193 } },
                [3665] = { name = "Crane Operator Bigglefuzz", at = { 6309, 3761 } },
                [5767] = { name = "Nalpak", at = { 4598, 3566 } },
                [5768] = { name = "Ebru", at = { 4601, 3574 } },
                [8418] = { name = "Falla Sagewind", at = { 4818, 3278 },
                           note = "Inside the building on top of the hill." },

                -- Inside Wailing Caverns, whose entrance is on this map.
                [3671] = { name = "Lady Anacondra", instance = 43,
                           note = "She stands in the Screaming Gully, in one of several spots." },
                [3669] = { name = "Lord Cobrahn", instance = 43,
                           note = "Take the water path west out of the Screaming Gully into the Pit of Fangs and climb around it. He is at the top." },
                [3670] = { name = "Lord Pythas", instance = 43,
                           note = "Back through the Screaming Gully, follow the water east through the Crag of the Everliving into the Winding Chasm. Go right through the small pool; he is at its north end." },
                [3673] = { name = "Lord Serpentis", instance = 43,
                           note = "From Pythas head southeast, turn left at the candles, and pass the pool on your left to the fence where Skum waits. Go right of the fence, southwest to the Crag of the Everliving, jump the gap by the small waterfall and follow the upper path to him." },
                [3678] = { name = "Disciple of Naralex", instance = 43, note = "At the entrance of the dungeon." },
                [3654] = { name = "Mutanus the Devourer", instance = 43,
                           note = "He comes last, at Dreamer's Rock." },

                -- Kill targets.
                [3256] = "Sunscale Scytheclaw",
                [3461] = "Oasis Snapjaw",
                [3655] = "Mad Magglish",
                [3636] = "Deviate Ravager",
                [5755] = "Deviate Viper",
                [5761] = "Deviate Shambler",
                [5056] = "Deviate Dreadfang",
            },
            [1456] = { -- Thunder Bluff
                [3419] = { name = "Apothecary Zamah", at = { 2282, 2090 },
                           note = "In the Pools of Vision, the cave under the Spirit Rise. The way in is at 29.89, 29.80." },
                [5769] = { name = "Arch Druid Hamuul Runetotem", at = { 7859, 2856 },
                           note = "Elder Rise, inside the building." },
                [5770] = { name = "Nara Wildmane", at = { 7565, 3160 } },
            },
        },
    },
})
