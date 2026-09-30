local _, ns = ...

-- Every Horde quest of Wailing Caverns, from the Barrens chains that unlock them to the
-- last turn-in at Thunder Bluff. Quest, NPC and item IDs, coordinates, the waypoints up
-- the hill, and the turn-in order after the dungeon (Ratchet, then Falla on the hill,
-- then the ledge, then Thunder Bluff, climbing the hill once instead of twice) are
-- NuuRoad's own. The raptor horn camps are the ones the Barrens guide
-- (HordeBarrens.lua) already uses.
--
-- The guide stands on its own. Each prerequisite step is gated on the quest it serves
-- being finished, so a player arriving from the Barrens guide with Hamuul Runetotem and
-- Raptor Horns done walks straight past them.
--
-- Recorded choices:
--   * The Barrens Oases (886) is left out: Tonga offers The Forgotten Pools without it.
--   * Apothecary Zamah (853) is taken last at the Crossroads, as the Barrens guide does,
--     because it is timed once accepted.
--   * Only the Glowing Shard drop 6981 is carried, not the alternate 3366.
--   * No hearth step: binding at Ratchet before the run saves a flight afterwards, but it
--     is the player's hearthstone, so it is a note.
--   * The inside of the dungeon has no coordinates. The bosses are placed by note; the
--     instance map is not in the travel data.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1413 The Barrens (guide default), 1456 Thunder Bluff.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-wailing-caverns-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-wailing-caverns-quests",
    updated = 1790208000,
    map = 1413,
    only = "Horde",
    meta = {
        title = "Wailing Caverns",
        author = "NuuRoad",
        category = "Dungeons/Wailing Caverns",
        tags = { "horde", "dungeon", "wailing caverns", "wc", "barrens" },
        levels = { 17, 24 },
    },
    steps = {
        { section = "Unlocking the quests", steps = {
            { note = "Hamuul Runetotem, Apothecary Zamah and Raptor Horns lead to three of the dungeon quests. Steps for any of them you have already finished are passed over." },
            { group = {
                { accept = 870, npc = 3448, only = "not quest 1489", at = { 52.26, 31.93 } },
                { accept = 848, npc = 3390, only = "not quest 853", at = { 51.44, 30.15 } },
            } },
            { object = "bubbling rock", objective = 870, part = 1, radius = 0.03, only = "not quest 870 finished", at = { 45.07, 22.53 },
                note = "Swim down beside the bubbling rock in the Forgotten Pools." },
            { object = "Laden Mushroom", objective = 848, part = 1, collect = 5012, count = 4, radius = 0.04, only = "not quest 848 finished",
                at = { { 44.70, 23.10 }, { 43.90, 24.40 }, { 45.53, 21.80 } }, note = "Large blue mushrooms around the pools." },
            { group = {
                { turnin = 870, accept = 877, npc = 3448, only = "not quest 1489", at = { 52.26, 31.93 } },
                { turnin = 848, npc = 3390, only = "not quest 853", at = { 51.44, 30.15 } },
            } },
            { accept = 865, npc = 3446, only = "not quest 1491", at = { 62.37, 37.62 } },
            { object = "Bubbling Fissure", objective = 877, part = 1, radius = 0.03, only = "not quest 877 finished", at = { 55.61, 42.74 },
                note = "Underwater in the Stagnant Oasis, on the way back from Ratchet." },
            { turnin = 877, accept = 880, npc = 3448, only = "not quest 1489", at = { 52.26, 31.93 } },
            { objective = 880, part = 1, collect = 5098, count = 8, kill = 3461, radius = 0.05, only = "not quest 880 finished", at = { 55.53, 42.70 },
                note = "Turtles in and around the Stagnant Oasis." },
            { objective = 865, part = 1, collect = 5055, count = 5, kill = 3256, radius = 0.05, only = "not quest 865 finished",
                at = { { 57.36, 52.38 }, { 57.01, 54.45 }, { 57.85, 53.90 } }, note = "Purple raptors south of the oasis." },
        } },

        { section = "Ratchet and the Crossroads", steps = {
            { group = {
                { turnin = 865, accept = 1491, npc = 3446, at = { 62.37, 37.62 },
                    note = "Innkeeper Wiley is here. Binding your hearthstone to Ratchet now saves a flight after the dungeon, whose first turn-ins are in Ratchet." },
                { accept = 959, npc = 3665, at = { 63.09, 37.61 } },
            } },
            { group = {
                { turnin = 880, accept = 1489, npc = 3448, only = "not quest 1489", at = { 52.26, 31.93 } },
                { accept = 853, npc = 3390, only = "not quest 853", at = { 51.44, 30.15 },
                    note = "Apothecary Zamah is timed. Fly to Thunder Bluff straight away." },
            } },
        } },

        { section = "Thunder Bluff", map = 1456, steps = {
            { group = {
                { turnin = 1489, accept = 1490, npc = 5769, at = { 78.59, 28.56 },
                    note = "Elder Rise, inside the building." },
                { turnin = 1490, accept = 914, npc = 5770, at = { 75.65, 31.60 } },
            } },
            { turnin = 853, accept = 962, npc = 3419, at = { 22.82, 20.90 },
                note = "In the Pools of Vision, the cave under the Spirit Rise. The way in is at 29.89, 29.80." },
        } },

        { section = "The hidden cave above the entrance", steps = {
            { travel = "the path up the hill", at = { 50.32, 35.44 },
                note = "Fly back to the Crossroads. The two quest givers at Wailing Caverns stand in a small cave above the entrance, reached over the hill by jumping down onto a stone." },
            { travel = "the top of the hill", at = { 48.09, 32.95 } },
            { travel = "the path down the far side", at = { 47.28, 33.56 } },
            { travel = "the ledge over the cave mouth", at = { 45.86, 35.86 },
                note = "Drop carefully onto the stone at 45.77, 36.16 below you, then walk into the small cave." },
            { group = {
                { accept = 1486, npc = 5767, at = { 45.98, 35.66 } },
                { accept = 1487, npc = 5768, at = { 46.01, 35.74 } },
            } },
        } },

        { section = "The outer caverns", steps = {
            { travel = "the cave mouth", at = { 45.97, 36.33 }, note = "Drop down from the ledge and walk into the caverns below." },
            { objective = 959, part = 1, collect = 5334, kill = 3655, radius = 0.04,
                at = { { 45.69, 33.60 }, { 46.84, 34.63 }, { 46.47, 35.50 } },
                note = "Mad Magglish is stealthed and slow to respawn. Skip this if he is not up; you can look again on the way out." },
            { travel = "Wailing Caverns", zone = "Wailing Caverns", at = { 47.75, 34.86 },
                note = "Go north through the caverns, cross the water and the bridge, and step into the portal with your group." },
        } },

        { section = "Inside Wailing Caverns", steps = {
            { objective = 1491, part = 1, collect = 6464, count = 6, sticky = true,
                note = "Ectoplasms throughout the dungeon drop it." },
            { objective = 962, part = 1, collect = 5339, count = 10, sticky = true,
                note = "Small green, purple and pink plants along the walls. There are not enough for a whole group in one run; agree who picks." },
            { objective = 1486, part = 1, collect = 6443, count = 20, sticky = true,
                note = "Any Deviate beast can drop one." },
            { objective = 1487, part = 1, kill = 3636, count = 7, sticky = true, note = "In the Screaming Gully." },
            { objective = 1487, part = 2, kill = 5755, count = 7, sticky = true, note = "In the Pit of Fangs." },
            { objective = 1487, part = 3, kill = 5761, count = 7, sticky = true, note = "In the Crag of the Everliving." },
            { objective = 1487, part = 4, kill = 5056, count = 7, sticky = true, note = "In the Winding Chasm." },
            { objective = 914, part = 2, collect = 9739, kill = 3671,
                note = "The first boss. She stands in the Screaming Gully, in one of several spots." },
            { objective = 914, part = 1, collect = 9738, kill = 3669,
                note = "Take the water path west out of the Screaming Gully into the Pit of Fangs and climb around it. He is at the top." },
            { objective = 914, part = 3, collect = 9740, kill = 3670,
                note = "Back through the Screaming Gully, follow the water east through the Crag of the Everliving into the Winding Chasm. Go right through the small pool; he is at its north end." },
            { objective = 914, part = 4, collect = 9741, kill = 3673,
                note = "From Pythas head southeast, turn left at the candles, and pass the pool on your left to the fence where Skum waits. Go right of the fence, southwest to the Crag of the Everliving, jump the gap by the small waterfall and follow the upper path to him." },
            { npc = 3678, note = "With the four Fanglords dead, talk to the Disciple of Naralex at the entrance and escort him to Naralex. Guard him through the waves that come." },
            { collect = 10441, starts = 6981, kill = 3654,
                note = "Mutanus the Devourer comes last, at Dreamer's Rock." },
            { accept = 6981, note = "Use the Glowing Shard to start its quest." },
            { travel = "the cave mouth", zone = "The Barrens", at = { 45.97, 36.33 },
                note = "Leave through the portal and walk back out of the caverns." },
        } },

        { section = "Turning in", steps = {
            { group = {
                { turnin = 1491, npc = 3446, only = "quest 1491 readyToTurnIn", at = { 62.37, 37.62 } },
                { turnin = 959, npc = 3665, only = "quest 959 readyToTurnIn", at = { 63.09, 37.61 } },
                { objective = 6981, part = 1, npc = 3442, only = "quest 6981", at = { 62.98, 37.22 },
                    note = "Ask Sputtervalve about the Glowing Shard." },
            } },
            { travel = "the path up the hill", at = { 50.32, 35.44 }, only = "quest 6981",
                note = "Fly to the Crossroads and walk back to the hill." },
            { turnin = 6981, accept = 3369, npc = 8418, only = "quest 6981", at = { 48.18, 32.78 },
                note = "Falla Sagewind is inside the building on top of the hill." },
            { travel = "the path down the far side", at = { 47.28, 33.56 },
                note = "Without a Glowing Shard to hand in, fly to the Crossroads and take the path up the hill from 50.32, 35.44." },
            { travel = "the ledge over the cave mouth", at = { 45.86, 35.86 },
                note = "Drop onto the stone at 45.77, 36.16 and walk into the small cave." },
            { group = {
                { turnin = 1486, npc = 5767, only = "quest 1486 readyToTurnIn", at = { 45.98, 35.66 } },
                { turnin = 1487, npc = 5768, only = "quest 1487 readyToTurnIn", at = { 46.01, 35.74 } },
            } },
            { group = {
                { turnin = 914, npc = 5770, only = "quest 914 readyToTurnIn", at = { 75.65, 31.60, map = 1456 } },
                { turnin = 3369, npc = 5769, only = "quest 3369", at = { 78.59, 28.56, map = 1456 } },
                { turnin = 962, npc = 3419, only = "quest 962 readyToTurnIn", at = { 22.82, 20.90, map = 1456 },
                    note = "Back down in the Pools of Vision." },
            } },
            { finish = "Every Horde quest of Wailing Caverns is done or left for another run." },
        } },
    },
}
