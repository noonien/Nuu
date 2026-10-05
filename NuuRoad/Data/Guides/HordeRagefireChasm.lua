-- A packaged guide, in guide format v1 (docs/examples/guide-v1.lua).
--
-- Every Horde quest of Ragefire Chasm, from Rahauro in Thunder Bluff to the last
-- Hidden Enemies turn-in with Thrall. Quest, NPC and item IDs, coordinates, the pickup
-- order (Thunder Bluff, the Undercity, then Orgrimmar), the Skull Rock camps, the
-- Orgrimmar order before the run, and the Hidden Enemies follow-ups 5729 and 5730 after
-- it are NuuRoad's own. Rahauro's spot is the one the Mulgore guide
-- (HordeMulgore612.lua) already uses.
--
-- The guide stands on its own. A player who already did part of the Hidden Enemies chain
-- walks past its accepts (a quest that can no longer be taken leaves the guide), and a
-- dungeon quest left behind (or never shared) stops on its step for the player to skip.
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
-- Maps: 1454 Orgrimmar (guide default), 1411 Durotar, 1456 Thunder Bluff, 1458 Undercity.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    schema = 1,

    id = "nuuroad:dungeon:horde-ragefire-chasm-quests",
    updated = 1790208000,
    title = "Ragefire Chasm",
    category = "Dungeons/Ragefire Chasm",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "ragefire chasm", "rfc", "orgrimmar" },
    levels = { from = 13, to = 18 },
    cond = { faction = "Horde" },

    data = {
        map = 1454,

        sections = {
            { title = "The far pickups", steps = {
                { type = "note", note = "Rahauro in Thunder Bluff and Varimathras in the Undercity give three of the dungeon quests, far from Orgrimmar. Press > to pass over a pickup you will not travel for; a group member who has it can share it inside." },
                { type = "accept", quests = { 5722, 5723 }, npc = { 11833 } },
                { type = "accept", quests = { 5725 }, npc = { 2425 },
                  note = "The zeppelin to Tirisfal leaves from the tower outside Orgrimmar. In the Undercity, take the tunnel at 51.93, 64.78 down to the Royal Quarter." },
            } },

            { title = "Orgrimmar and Skull Rock", steps = {
                { type = "accept", quests = { 5726 }, npc = { 4949 } },
                { type = "collect", item = 14544, kill = { 3198, 3197 }, quest = { 5726, 1 }, radius = 400,
                  at = { { 5498, 967, map = 1411 }, { 5240, 1000, map = 1411 }, { 5300, 740, map = 1411 } },
                  note = "Inside Skull Rock, the cave just outside Orgrimmar's front gate. Any Burning Blade there can drop it." },
                { type = "talk", turnin = { 5726 }, accept = { 5727 }, npc = { 4949 },
                  note = "Back through the front gate to Grommash Hold." },
                { group = {
                    { type = "accept", quests = { 5761 }, npc = { 3216 } },
                    { type = "talk", npc = { 3216 }, quest = { 5727, 1 },
                      note = "Pick the gossip option that invites him to speak freely." },
                } },
                { type = "talk", turnin = { 5727 }, accept = { 5728 }, npc = { 4949 },
                  note = "Report how Neeru took it." },
                { type = "travel", to = "Ragefire Chasm", at = { { 5275, 4886 } },
                  note = "Back down in the Cleft of Shadow. Step into the portal with your group." },
            } },

            { title = "Inside Ragefire Chasm", steps = {
                { type = "kill", kill = { 11318 }, quest = { 5723, 1 }, sticky = true,
                  note = "Throughout the first halls. A group member can share Testing an Enemy's Strength if you did not take it." },
                { type = "kill", kill = { 11319 }, quest = { 5723, 2 }, sticky = true },
                { type = "collect", item = 14395, kill = { 11322, 11324 }, quest = { 5725, 1 }, sticky = true,
                  note = "Only the Searing Blade Cultists and Warlocks drop it." },
                { type = "collect", item = 14396, kill = { 11322, 11324 }, quest = { 5725, 2 }, sticky = true,
                  note = "Only the Searing Blade Cultists and Warlocks drop it." },
                { type = "talk", turnin = { 5722 }, accept = { 5724 }, npc = { 11834 } },
                { type = "collect", item = 14540, kill = { 11520 }, quest = { 5761, 1 },
                  note = "The second boss, on a platform over the lava. Keep away from its edges." },
                { type = "kill", kill = { 11518 }, quest = { 5728, 2 },
                  note = "The third boss, with two guards beside him." },
                { type = "kill", kill = { 11519 }, quest = { 5728, 1 },
                  note = "The last boss, at the far end of the chasm." },
                { type = "travel", to = "the Cleft of Shadow", zone = 1454, at = { { 5275, 4886 } },
                  note = "Leave through the portal." },
            } },

            { title = "Turning in", steps = {
                { type = "talk", turnin = { 5728 }, accept = { 5729 }, npc = { 4949 },
                  note = "Up to Grommash Hold." },
                { group = {
                    { type = "turnin", quests = { 5761 }, npc = { 3216 }, optional = true,
                      note = "Back down in the Cleft of Shadow." },
                    { type = "talk", turnin = { 5729 }, accept = { 5730 }, npc = { 3216 },
                      note = "Thrall sends you back to Neeru, then Neeru back to Thrall." },
                } },
                { type = "turnin", quests = { 5730 }, npc = { 4949 } },
                { type = "turnin", quests = { 5725 }, npc = { 2425 }, optional = true,
                  note = "Take the zeppelin to Tirisfal and go down to the Royal Quarter." },
                { group = {
                    { type = "turnin", quests = { 5724 }, npc = { 11833 } },
                    { type = "turnin", quests = { 5723 }, npc = { 11833 }, optional = true },
                } },
                { type = "finish", note = "Every Horde quest of Ragefire Chasm is done or left for another run." },
            } },
        },

        npcs = {
            [1454] = { -- Orgrimmar
                [4949] = { name = "Thrall", at = { 3174, 3783 },
                           note = "Inside Grommash Hold. The door is at 40.07, 37.01." },
                [3216] = { name = "Neeru Fireblade", at = { 4947, 5063 },
                           note = "In the Cleft of Shadow, inside the building. The way down is near 55.22, 40.76." },

                -- Inside Ragefire Chasm, whose entrance is on this map. The instance ID is not
                -- in the repo, so they carry no `instance`.
                [11834] = { name = "Maur Grimtotem",
                            note = "Take the first right off the long path down and climb the ramp into the trogg room. Maur Grimtotem lies on the floor at the top." },
                [11318] = "Ragefire Trogg",
                [11319] = "Ragefire Shaman",
                [11322] = "Searing Blade Cultist",
                [11324] = "Searing Blade Warlock",
                [11518] = "Jergosh the Invoker",
                [11519] = "Bazzalan",
                [11520] = "Taragaman the Hungerer",
            },
            [1411] = { -- Durotar
                [3197] = "Burning Blade Fanatic",
                [3198] = "Burning Blade Apprentice",
            },
            [1456] = { -- Thunder Bluff
                [11833] = { name = "Rahauro", at = { 7038, 2960 },
                            note = "On the Elder Rise. He walks around the area." },
            },
            [1458] = { -- Undercity
                [2425] = { name = "Varimathras", at = { 5626, 9219 } },
            },
        },
    },
})
