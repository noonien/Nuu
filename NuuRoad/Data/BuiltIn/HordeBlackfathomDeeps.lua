local _, ns = ...

-- Every Horde quest of Blackfathom Deeps, from Tsunaman at Sun Rock Retreat to the last
-- turn-ins at Zoram'gar Outpost and Thunder Bluff. The quest list and chains follow
-- ForeverDungeonJournal's Forever beta quest cache (Data/Dungeons.lua, QuestChains.lua,
-- QuestMaps.lua), with Baron Aquanis (6922) added from the local Questie Forever database
-- and Wowhead's Forever database. Quest, NPC, item and object IDs and the quest givers'
-- spots come from the Questie Forever database (reference only), checked against Wowhead
-- Forever; the Tide Priestess and Sapphire spots in the outer caves are Questie's and
-- Wowhead Forever's spawn points; the surface entrance is Questie's and the portal
-- ForeverDungeonJournal's (DungeonEntrances.lua). RestedXP's Forever Barrens dungeon guide
-- and its Horde 20-30 guide were read for where the route picks the quests up. Doan
-- Karhan's spot is the one the Shadowfang Keep guide (HordeShadowfangKeep.lua) uses.
--
-- The guide stands on its own. Every dungeon objective is gated on its quest being in the
-- log, so a quest left behind (or never shared) hides its steps, and every turn-in after
-- the run waits for its quest to be ready.
--
-- Recorded choices:
--   * Trouble in the Deeps (6562) is a lead-in from Stonetalon, far from Ashenvale, so the
--     guide says it may be passed over; Je'neu offers The Essence of Aku'Mai without it.
--   * The Damp Note and the Sapphires of Aku'Mai are in the flooded caves outside the
--     instance. The guide walks back to Je'neu once before the run, so the Damp Note
--     turns into Lorgus Jett's quest (6565) in time for the run; both hand-ins there are
--     passed over when there is nothing to hand in, and a player whose group is waiting
--     can press > and do Lorgus Jett another time.
--   * Baron Aquanis is carried although ForeverDungeonJournal's quest cache does not
--     list it: the Questie Forever database and Wowhead Forever both have it, and its
--     Strange Water Globe is in ForeverDungeonJournal's loot for him.
--   * The Orb of Soran'ruk (Warlocks only) is carried: its three small fragments drop here,
--     the large one in Shadowfang Keep. The turn-in shows only once all four are in the
--     bags.
--   * Je'neu of the Earthen Ring (824) is not a dungeon quest and is left out.
--   * No hearth step, and no step to destroy leftover Sapphires; leaving is a walk back
--     to the portal.
--   * The inside of the dungeon has no coordinates. Thaelrid, Lorgus Jett, the Fathom
--     Stone and the bosses are placed by note; the instance map is not in the travel data.
--
-- Check in client:
--   * The zone text inside the instance ("Blackfathom Deeps") and back in the caves
--     ("Ashenvale") that complete the two travel steps.
--   * That the Damp Note starts Allegiance to the Old Gods without Trouble in the Deeps
--     done: the Questie database lists 6562 as its prerequisite, Wowhead Forever does not.
--   * That Baron Aquanis (6922) is on the Forever client, and that taking the Fathom Core
--     summons him.
--   * The surface entrance (14.50, 14.20) and the portal (16.50, 11.00); that every
--     Sapphire of Aku'Mai is in the outer caves (none are listed inside).
--   * The notes placing Argent Guard Thaelrid, Lorgus Jett, the Fathom Stone and Twilight
--     Lord Kelris, and Tsunaman's ledge above Sun Rock Retreat.
--   * Bashana Runetotem's spot on the Elder Rise (Wowhead Forever 70.8, 33.4; the Questie
--     database has 71.06, 34.19).
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1440 Ashenvale (guide default), 1442 Stonetalon Mountains, 1456 Thunder Bluff,
-- 1413 The Barrens.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-blackfathom-deeps-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-blackfathom-deeps-quests",
    updated = 1790985600,
    map = 1440,
    only = "Horde",
    meta = {
        title = "Blackfathom Deeps",
        author = "NuuRoad",
        category = "Dungeons/Blackfathom Deeps",
        tags = { "horde", "dungeon", "blackfathom deeps", "bfd", "ashenvale", "zoram'gar" },
        levels = { 22, 30 },
    },
    steps = {
        { section = "The far pickups", steps = {
            { note = "Doan Karhan in the Barrens and Tsunaman in Stonetalon give two of the quests, far from Ashenvale. Press > to pass over a pickup you will not travel for." },
            { accept = 1740, npc = 6247, only = "Warlock", at = { 49.31, 57.21, map = 1413 },
                note = "Warlocks only. Its three small fragments drop in Blackfathom Deeps; the large one is in Shadowfang Keep." },
            { accept = 6562, npc = 11862, only = "not quest 6563", at = { 47.36, 64.25, map = 1442 },
                note = "On a ledge above Sun Rock Retreat; take the path that climbs the mountainside from the village." },
        } },

        { section = "Zoram'gar Outpost", steps = {
            { group = {
                { turnin = 6562, npc = 12736, only = "now quest 6562", at = { 11.56, 34.29 },
                    note = "Zoram'gar Outpost is on the shore in the far west of Ashenvale. Andruk, its flight master, stands at 12.24, 33.80; learn the flight path while you are here." },
                { accept = { 6563, 6921 }, npc = 12736, at = { 11.56, 34.29 } },
            } },
        } },

        { section = "The flooded caves", steps = {
            { travel = "the ruins on the Zoram Strand", at = { 14.50, 14.20 },
                note = "North along the shore. Drop into the opening among the ruins and swim down into the caves beneath." },
            { collect = 16790, starts = 6564, kill = 4802, only = "not quest 6564",
                at = { { 13.55, 12.06 }, { 13.40, 9.40 }, { 15.80, 11.40 } },
                note = "Blackfathom Tide Priestesses in the caves drop it. Not every one does." },
            { accept = 6564, note = "Use the Damp Note to start its quest." },
            { objective = 6563, part = 1, collect = 16784, count = 20, object = "Sapphire of Aku'Mai", only = "quest 6563",
                at = { { 13.69, 12.27 }, { 13.07, 12.87 }, { 13.79, 11.15 }, { 16.60, 11.20 } },
                note = "Crystals on the cave walls, all the way along the tunnels to the portal." },
        } },

        { section = "Back to Je'neu", steps = {
            { note = "Handing the Damp Note in before the run unlocks Lorgus Jett's quest for it. If your group is waiting, press > and leave it for another run." },
            { group = {
                { turnin = 6564, accept = 6565, npc = 12736, only = "now quest 6564", at = { 11.56, 34.29 } },
                { turnin = 6563, npc = 12736, only = "now quest 6563 readyToTurnIn", at = { 11.56, 34.29 } },
            } },
            { travel = "Blackfathom Deeps", zone = "Blackfathom Deeps", at = { 16.50, 11.00 },
                note = "Back into the ruins and down through the caves. The portal is at the far end of the flooded tunnels; step in with your group." },
        } },

        { section = "Inside Blackfathom Deeps", steps = {
            { objective = 1740, part = 1, collect = 6914, count = 3, kill = 4809, sticky = true, only = "Warlock | quest 1740",
                note = "Only the Twilight Acolytes among the cultists drop them." },
            { accept = 6561, npc = 4787,
                note = "Argent Guard Thaelrid stands among his fallen guards in the first half of the dungeon, past Ghamoo-ra and Lady Sarevess. A group member can share the quest." },
            { objective = 6565, part = 1, kill = 12902, only = "quest 6565",
                note = "Lorgus Jett walks with Twilight's Hammer cultists past Gelihast's murloc cave, on the way to the Moonshrine Ruins. He has more than one spawn point." },
            { objective = 6921, part = 1, collect = 16762, object = "Fathom Stone", only = "quest 6921",
                note = "On the floor of the water under the bridge at the Moonshrine Ruins. Taking the core summons Baron Aquanis; get the group ready first." },
            { collect = 16782, starts = 6922, kill = 12876, only = "quest 6921 or item 16782",
                note = "Baron Aquanis drops it." },
            { accept = 6922, only = "quest 6921 or item 16782", note = "Use the Strange Water Globe to start its quest." },
            { objective = 6561, part = 1, collect = 5881, kill = 4832, only = "quest 6561",
                note = "Twilight Lord Kelris waits in the shrine past the Moonshrine Ruins. Aku'mai, beyond him, is the last boss and no quest needs him." },
            { travel = "the caves outside", zone = "Ashenvale", at = { 14.50, 14.20 },
                note = "Walk back to the entrance and leave through the portal, then swim up out of the caves." },
        } },

        { section = "Turning in", steps = {
            { group = {
                { turnin = 6563, npc = 12736, only = "quest 6563 readyToTurnIn", at = { 11.56, 34.29 },
                    note = "South along the shore to Zoram'gar Outpost." },
                { turnin = 6564, npc = 12736, only = "quest 6564", at = { 11.56, 34.29 },
                    note = "Je'neu then offers Lorgus Jett's quest for another run." },
                { turnin = 6565, npc = 12736, only = "quest 6565 readyToTurnIn", at = { 11.56, 34.29 } },
                { turnin = 6921, npc = 12736, only = "quest 6921 readyToTurnIn", at = { 11.56, 34.29 } },
                { turnin = 6922, npc = 12736, only = "quest 6922", at = { 11.56, 34.29 } },
            } },
            { turnin = 6561, npc = 9087, only = "quest 6561 readyToTurnIn", at = { 70.80, 33.40, map = 1456 },
                note = "Fly to Thunder Bluff from Andruk (12.24, 33.80). Bashana Runetotem is on the Elder Rise." },
            { turnin = 1740, npc = 6247, only = "Warlock | quest 1740 readyToTurnIn", at = { 49.31, 57.21, map = 1413 },
                note = "Once you also have the Large Soran'ruk Fragment from Shadowfang Keep." },
            { finish = "Every Horde quest of Blackfathom Deeps is done or left for another run." },
        } },
    },
}
