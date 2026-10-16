-- A packaged guide: a guide source (docs/examples/guide-source.lua).
--
-- Every Horde quest of Shadowfang Keep, from Keeper Bel'dugur in the Undercity to the
-- last turn-in. Quest, NPC and item IDs, coordinates, the pickup order (the Undercity,
-- Dalar Dawnweaver, then High Executor Hadrec in the crypt), the path up to the keep,
-- the boss notes, and the turn-in order after the run (Dalar at the Sepulcher, then the
-- Undercity) are NuuRoad's own; the two flight masters named in notes (Michael Garrett
-- in the Undercity, Karos Razok at the Sepulcher) are placed the same way. The Orb of
-- Soran'ruk's giver, Doan Karhan in the Barrens, his spot, and the drops of the two
-- fragments were cross-checked in the local Questie database (Database/Classic), which is
-- reference only.
--
-- Recorded choices:
--   * The Orb of Soran'ruk (Warlocks only) is carried. Its three small fragments drop in
--     Blackfathom Deeps, not here, so the guide takes the quest and the Large Soran'ruk
--     Fragment and says where the rest come from; the turn-in waits for the quest to be
--     ready, which needs all four. The pickup is far from Silverpine, so the guide says
--     it may be passed over.
--   * Deathstalkers in Shadowfang is turned in to Deathstalker Vincent inside.
--   * No hearth step and no step asking the player to die and run back; leaving is a
--     plain walk out through the portal.
--   * The inside of the dungeon has no coordinates. Deathstalker Adamant, Vincent and the
--     bosses are placed by note; the instance map is not in the travel data.
--
-- Check in client: Shadowfang Keep's instance ID (GetInstanceInfo), to give the entrance
-- step `instance` and Deathstalker Vincent `instance`; and that Deathstalker Vincent is
-- still alive to take 1098 on the Forever client.
--
-- Maps: 1421 Silverpine Forest (guide default), 1458 Undercity, 1413 The Barrens.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",

    id = "nuuroad:dungeon:horde-shadowfang-keep-quests",
    updated = 1790208000,
    title = "Shadowfang Keep",
    category = "Dungeons/Shadowfang Keep",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "shadowfang keep", "sfk", "silverpine forest", "undercity" },
    levels = { from = 18, to = 26 },
    cond = { faction = "Horde" },

    data = {
        map = 1421,

        sections = {
            { title = "The pickups", steps = {
                { type = "accept", quests = { 1740 }, npc = { 6247 }, cond = { class = "WARLOCK" },
                  note = "Warlocks only, and far from Silverpine: press > to pass it over. Its three small fragments drop from Twilight Acolytes in Blackfathom Deeps; only the large one is in Shadowfang Keep." },
                { type = "accept", quests = { 1013 }, npc = { 2934 },
                  note = "The zeppelin from Orgrimmar lands in Tirisfal, a short walk from the Undercity." },
                { group = {
                    { type = "accept", quests = { 1014 }, npc = { 1938 } },
                    { type = "accept", quests = { 1098 }, npc = { 1952 } },
                } },
            } },

            { title = "The road to the keep", steps = {
                { type = "travel", to = "the path up to the keep", at = { { 4714, 6972 } },
                  note = "South along the road. The keep stands on the hill to the west." },
                { type = "travel", to = "Shadowfang Keep", at = { { 4480, 6784 } },
                  note = "Step into the portal at the gate with your group." },
            } },

            { title = "Inside Shadowfang Keep", steps = {
                { type = "collect", item = 6915, kill = { 3855 }, quest = { 1740, 2 }, sticky = true,
                  cond = { class = "WARLOCK" },
                  note = "Only the Shadowfang Darksouls drop it." },
                { type = "kill", kill = { 3914 },
                  note = "The first boss. Then pull the lever to open the cells, ask Deathstalker Adamant to unlock the courtyard door, and follow him." },
                { type = "turnin", quests = { 1098 }, npc = { 4444 } },
                { type = "collect", item = 6283, quest = { 1013, 1 }, object = "the bookshelf",
                  note = "Past Baron Silverlaine and Commander Springvale, down and along the outside path, then Odo the Blindwatcher. Kill Fenrus the Devourer; the book is a blue book on the shelf on the left side of his room." },
                { type = "collect", item = 5442, kill = { 4275 }, quest = { 1014, 1 },
                  note = "The last boss, at the top of the keep." },
                { type = "travel", to = "the keep gate", zone = 1421, at = { { 4480, 6784 } },
                  note = "Leave through the portal." },
            } },

            { title = "Turning in", steps = {
                { type = "turnin", quests = { 1014 }, npc = { 1938 },
                  note = "North to the Sepulcher." },
                { type = "turnin", quests = { 1013 }, npc = { 2934 },
                  note = "Fly to the Undercity from Karos Razok (45.62, 42.58) and go down to the Apothecarium." },
                { type = "turnin", quests = { 1740 }, npc = { 6247 }, cond = { class = "WARLOCK" },
                  note = "Once you also have the three fragments from Blackfathom Deeps." },
                { type = "finish", note = "Every Horde quest of Shadowfang Keep is done or left for another run." },
            } },
        },

        npcs = {
            [1421] = { -- Silverpine Forest
                [1938] = { name = "Dalar Dawnweaver", at = { 4420, 3979 },
                           note = "At the Sepulcher. Fly from Michael Garrett (Undercity 63.25, 48.56) if you know the flight path; otherwise leave the Undercity and walk south into Silverpine." },
                [1952] = { name = "High Executor Hadrec", at = { 4342, 4087 },
                           note = "Down in the crypt. The way in is at 43.09, 41.38." },
                -- Inside Shadowfang Keep, whose entrance is on this map. No instance ID yet.
                [4444] = { name = "Deathstalker Vincent",
                           note = "In the courtyard: once the door opens, drop down to the right of the stairs." },
                [3855] = "Shadowfang Darksoul",
                [3914] = "Rethilgore",
                [4275] = "Archmage Arugal",
            },
            [1458] = { -- Undercity
                [2934] = { name = "Keeper Bel'dugur", at = { 5372, 5445 }, note = "In the Apothecarium." },
            },
            [1413] = { -- The Barrens
                [6247] = { name = "Doan Karhan", at = { 4931, 5721 } },
            },
        },
    },
})
