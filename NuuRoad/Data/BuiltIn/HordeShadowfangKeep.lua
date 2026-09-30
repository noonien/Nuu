local _, ns = ...

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
-- The guide stands on its own. Every dungeon objective is gated on its quest being in the
-- log, so a quest left behind (or never shared) hides its steps, and every turn-in waits
-- for its quest to be ready.
--
-- Recorded choices:
--   * The Orb of Soran'ruk (Warlocks only) is carried. Its three small fragments drop in
--     Blackfathom Deeps, not here, so the guide takes the quest and the Large Soran'ruk
--     Fragment and says where the rest come from; the turn-in shows only once all four
--     are in the bags. The pickup is far from Silverpine, so the guide says it may be
--     passed over.
--   * Deathstalkers in Shadowfang is turned in to Deathstalker Vincent inside.
--   * No hearth step and no step asking the player to die and run back; leaving is a
--     plain walk out through the portal.
--   * The inside of the dungeon has no coordinates. Deathstalker Adamant, Vincent and the
--     bosses are placed by note; the instance map is not in the travel data.
--
-- Check in client: the zone text inside the instance ("Shadowfang Keep") that completes
-- the entrance step, and that Deathstalker Vincent is still alive to take 1098 on the
-- Forever client.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1421 Silverpine Forest (guide default), 1458 Undercity, 1413 The Barrens.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-shadowfang-keep-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-shadowfang-keep-quests",
    updated = 1790208000,
    map = 1421,
    only = "Horde",
    meta = {
        title = "Shadowfang Keep",
        author = "NuuRoad",
        category = "Dungeons/Shadowfang Keep",
        tags = { "horde", "dungeon", "shadowfang keep", "sfk", "silverpine forest", "undercity" },
        levels = { 18, 26 },
    },
    steps = {
        { section = "The pickups", steps = {
            { accept = 1740, npc = 6247, only = "Warlock", at = { 49.31, 57.21, map = 1413 },
                note = "Warlocks only, and far from Silverpine: press > to pass it over. Its three small fragments drop from Twilight Acolytes in Blackfathom Deeps; only the large one is in Shadowfang Keep." },
            { accept = 1013, npc = 2934, at = { 53.72, 54.45, map = 1458 },
                note = "In the Apothecarium. The zeppelin from Orgrimmar lands in Tirisfal, a short walk from the Undercity." },
            { group = {
                { accept = 1014, npc = 1938, at = { 44.20, 39.79 },
                    note = "At the Sepulcher. Fly from Michael Garrett (Undercity 63.25, 48.56) if you know the flight path; otherwise leave the Undercity and walk south into Silverpine." },
                { accept = 1098, npc = 1952, at = { 43.42, 40.87 },
                    note = "Down in the crypt. The way in is at 43.09, 41.38." },
            } },
        } },

        { section = "The road to the keep", steps = {
            { travel = "the path up to the keep", at = { 47.14, 69.72 },
                note = "South along the road. The keep stands on the hill to the west." },
            { travel = "Shadowfang Keep", zone = "Shadowfang Keep", at = { 44.80, 67.84 },
                note = "Step into the portal at the gate with your group." },
        } },

        { section = "Inside Shadowfang Keep", steps = {
            { objective = 1740, part = 2, collect = 6915, kill = 3855, sticky = true, only = "quest 1740",
                note = "Only the Shadowfang Darksouls drop it." },
            { kill = 3914,
                note = "The first boss. Then pull the lever to open the cells, ask Deathstalker Adamant to unlock the courtyard door, and follow him." },
            { turnin = 1098, npc = 4444, only = "quest 1098",
                note = "Once the door opens, drop down to the right of the stairs into the courtyard. Deathstalker Vincent is there." },
            { objective = 1013, part = 1, collect = 6283, object = "the bookshelf", only = "quest 1013",
                note = "Past Baron Silverlaine and Commander Springvale, down and along the outside path, then Odo the Blindwatcher. Kill Fenrus the Devourer; the book is a blue book on the shelf on the left side of his room." },
            { objective = 1014, part = 1, collect = 5442, kill = 4275, only = "quest 1014",
                note = "The last boss, at the top of the keep." },
            { travel = "the keep gate", zone = "Silverpine Forest", at = { 44.80, 67.84 },
                note = "Leave through the portal." },
        } },

        { section = "Turning in", steps = {
            { turnin = 1014, npc = 1938, only = "quest 1014 readyToTurnIn", at = { 44.20, 39.79 },
                note = "North to the Sepulcher." },
            { turnin = 1013, npc = 2934, only = "quest 1013 readyToTurnIn", at = { 53.72, 54.45, map = 1458 },
                note = "Fly to the Undercity from Karos Razok (45.62, 42.58) and go down to the Apothecarium." },
            { turnin = 1740, npc = 6247, only = "quest 1740 readyToTurnIn", at = { 49.31, 57.21, map = 1413 },
                note = "Once you also have the three fragments from Blackfathom Deeps." },
            { finish = "Every Horde quest of Shadowfang Keep is done or left for another run." },
        } },
    },
}
