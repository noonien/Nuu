local _, ns = ...

-- Every Horde quest of Ragefire Chasm, from Rahauro in Thunder Bluff to the last
-- Hidden Enemies turn-in with Thrall. Quest, NPC and item IDs, coordinates, the pickup
-- order (Thunder Bluff, the Undercity, then Orgrimmar), the Skull Rock camps, the
-- Orgrimmar order before the run, and the Hidden Enemies follow-ups 5729 and 5730 after
-- it are NuuRoad's own. Rahauro's spot is the one the Mulgore guide
-- (HordeMulgore612.lua) already uses.
--
-- The guide stands on its own. Each Hidden Enemies step is gated on the next quest of the
-- chain, so a player who already did part of it walks past, and every dungeon objective is
-- gated on its quest being in the log, so a quest left behind (or never shared) hides its
-- steps instead of asking for them.
--
-- Recorded choices:
--   * Neeru Fireblade's Slaying the Beast is taken on the visit that gauges his reaction,
--     instead of on a second trip down to the Cleft of Shadow.
--   * After the run Thrall comes first, then Neeru, then Thrall again: Neeru's heart
--     turn-in and the 5729 hand-in share one visit, which saves a leg over doing
--     Neeru, Thrall, Neeru, Thrall.
--   * The Power to Destroy... (Varimathras) is carried. It and Rahauro's two quests are
--     far from Orgrimmar, so the guide says the pickups may be passed over and shared
--     inside instead.
--   * No hearth step, and no step to destroy the Lieutenant's Insignia.
--   * The inside of the dungeon has no coordinates. Maur Grimtotem and the bosses are
--     placed by note; the instance map is not in the travel data.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1454 Orgrimmar (guide default), 1411 Durotar, 1456 Thunder Bluff, 1458 Undercity.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-ragefire-chasm-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-ragefire-chasm-quests",
    updated = 1790208000,
    map = 1454,
    only = "Horde",
    meta = {
        title = "Ragefire Chasm",
        author = "NuuRoad",
        category = "Dungeons/Ragefire Chasm",
        tags = { "horde", "dungeon", "ragefire chasm", "rfc", "orgrimmar" },
        levels = { 13, 18 },
    },
    steps = {
        { section = "The far pickups", steps = {
            { note = "Rahauro in Thunder Bluff and Varimathras in the Undercity give three of the dungeon quests, far from Orgrimmar. Press > to pass over a pickup you will not travel for; a group member who has it can share it inside." },
            { accept = { 5722, 5723 }, npc = 11833,
                note = "On the Elder Rise. He walks around the area." },
            { accept = 5725, npc = 2425,
                note = "The zeppelin to Tirisfal leaves from the tower outside Orgrimmar. In the Undercity, take the tunnel at 51.93, 64.78 down to the Royal Quarter." },
        } },

        { section = "Orgrimmar and Skull Rock", steps = {
            { accept = 5726, npc = 4949, only = "not quest 5727",
                note = "Inside Grommash Hold. The door is at 40.07, 37.01." },
            { objective = 5726, part = 1, collect = 14544, kill = { 3198, 3197 }, radius = 0.04, only = "not quest 5726 finished",
                at = { { 54.98, 9.67, map = 1411 }, { 52.40, 10.00, map = 1411 }, { 53.00, 7.40, map = 1411 } },
                note = "Inside Skull Rock, the cave just outside Orgrimmar's front gate. Any Burning Blade there can drop it." },
            { turnin = 5726, accept = 5727, npc = 4949, only = "not quest 5728",
                note = "Back through the front gate to Grommash Hold." },
            { group = {
                { accept = 5761, npc = 3216,
                    note = "In the Cleft of Shadow, inside the building. The way down is near 55.22, 40.76." },
                { objective = 5727, part = 1, npc = 3216, only = "not quest 5728",
                    note = "Pick the gossip option that invites him to speak freely." },
            } },
            { turnin = 5727, accept = 5728, npc = 4949, only = "not quest 5728",
                note = "Report how Neeru took it." },
            { travel = "Ragefire Chasm", zone = "Ragefire Chasm", at = { 52.75, 48.86 },
                note = "Back down in the Cleft of Shadow. Step into the portal with your group." },
        } },

        { section = "Inside Ragefire Chasm", steps = {
            { objective = 5723, part = 1, kill = 11318, count = 8, sticky = true, only = "quest 5723",
                note = "Throughout the first halls. A group member can share Testing an Enemy's Strength if you did not take it." },
            { objective = 5723, part = 2, kill = 11319, count = 8, sticky = true, only = "quest 5723" },
            { objective = 5725, part = 1, collect = 14395, kill = { 11322, 11324 }, sticky = true, only = "quest 5725",
                note = "Only the Searing Blade Cultists and Warlocks drop it." },
            { objective = 5725, part = 2, collect = 14396, kill = { 11322, 11324 }, sticky = true, only = "quest 5725",
                note = "Only the Searing Blade Cultists and Warlocks drop it." },
            { turnin = 5722, accept = 5724, npc = 11834, only = "quest 5722",
                note = "Take the first right off the long path down and climb the ramp into the trogg room. Maur Grimtotem lies on the floor at the top." },
            { objective = 5761, part = 1, collect = 14540, kill = 11520, only = "quest 5761",
                note = "The second boss, on a platform over the lava. Keep away from its edges." },
            { objective = 5728, part = 2, kill = 11518, only = "quest 5728",
                note = "The third boss, with two guards beside him." },
            { objective = 5728, part = 1, kill = 11519, only = "quest 5728",
                note = "The last boss, at the far end of the chasm." },
            { travel = "the Cleft of Shadow", zone = "Orgrimmar", at = { 52.75, 48.86 },
                note = "Leave through the portal." },
        } },

        { section = "Turning in", steps = {
            { turnin = 5728, accept = 5729, npc = 4949, only = "quest 5728 readyToTurnIn or quest 5728 finished",
                note = "Up to Grommash Hold." },
            { group = {
                { turnin = 5761, npc = 3216, only = "quest 5761 readyToTurnIn",
                    note = "Back down in the Cleft of Shadow." },
                { turnin = 5729, accept = 5730, npc = 3216, only = "quest 5729",
                    note = "Thrall sends you back to Neeru, then Neeru back to Thrall." },
            } },
            { turnin = 5730, npc = 4949, only = "quest 5730" },
            { turnin = 5725, npc = 2425, only = "quest 5725 readyToTurnIn",
                note = "Take the zeppelin to Tirisfal and go down to the Royal Quarter." },
            { group = {
                { turnin = 5724, npc = 11833, only = "quest 5724",
                    note = "On the Elder Rise. He walks around the area." },
                { turnin = 5723, npc = 11833, only = "quest 5723 readyToTurnIn" },
            } },
            { finish = "Every Horde quest of Ragefire Chasm is done or left for another run." },
        } },
    },
    names = {
        npcs = {
            [2425] = { "Varimathras", at = { 56.26, 92.19, map = 1458 } },
            [3197] = "Burning Blade Fanatic",
            [3198] = "Burning Blade Apprentice",
            [3216] = { "Neeru Fireblade", at = { 49.47, 50.63 } },
            [4949] = { "Thrall", at = { 31.74, 37.83 } },
            [11318] = "Ragefire Trogg",
            [11319] = "Ragefire Shaman",
            [11322] = "Searing Blade Cultist",
            [11324] = "Searing Blade Warlock",
            [11518] = "Jergosh the Invoker",
            [11519] = "Bazzalan",
            [11520] = "Taragaman the Hungerer",
            [11833] = { "Rahauro", at = { 70.38, 29.60, map = 1456 } },
            [11834] = "Maur Grimtotem",
        },
        quests = {
            [5722] = "Searching for the Lost Satchel",
            [5723] = "Testing an Enemy's Strength",
            [5724] = "Returning the Lost Satchel",
            [5725] = "The Power to Destroy...",
            [5726] = "Hidden Enemies",
            [5727] = "Hidden Enemies",
            [5728] = "Hidden Enemies",
            [5729] = "Hidden Enemies",
            [5730] = "Hidden Enemies",
            [5761] = "Slaying the Beast",
        },
        items = {
            [14395] = "Spells of Shadow",
            [14396] = "Incantations from the Nether",
            [14540] = "Taragaman the Hungerer's Heart",
            [14544] = "Lieutenant's Insignia",
        },
    },
}
