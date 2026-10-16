-- A packaged guide: a guide source (docs/examples/guide-source.lua).
--
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
-- The guide stands on its own. A quest left behind (or never shared) has its steps
-- passed (its accept never happened, so its turn-in has nothing to hand in), and the
-- turn-ins after the run are optional: passed unless the quest is ready.
--
-- Recorded choices:
--   * Trouble in the Deeps (6562) is a lead-in from Stonetalon, far from Ashenvale, so the
--     guide says it may be passed over; Je'neu offers The Essence of Aku'Mai without it.
--   * The Damp Note and the Sapphires of Aku'Mai are in the flooded caves outside the
--     instance. The guide walks back to Je'neu once before the run, so the Damp Note
--     turns into Lorgus Jett's quest (6565) in time for the run; both hand-ins there are
--     optional, passed when there is nothing ready to hand in, and a player whose group is
--     waiting can skip and do Lorgus Jett another time.
--   * Baron Aquanis is carried although ForeverDungeonJournal's quest cache does not
--     list it: the Questie Forever database and Wowhead Forever both have it, and its
--     Strange Water Globe is in ForeverDungeonJournal's loot for him.
--   * The Orb of Soran'ruk (Warlocks only) is carried: its three small fragments drop here,
--     the large one in Shadowfang Keep. The turn-in is optional, so it is passed until all
--     four are handed in at once.
--   * Je'neu of the Earthen Ring (824) is not a dungeon quest and is left out.
--   * No hearth step, and no step to destroy leftover Sapphires; leaving is a walk back
--     to the portal.
--   * The inside of the dungeon has no coordinates. Thaelrid, Lorgus Jett, the Fathom
--     Stone and the bosses are placed by note; the instance map is not in the travel data.
--
-- Check in client:
--   * The dungeon's instance ID (GetInstanceInfo) for the travel into it and for the NPCs
--     inside (see the conversion notes), and that map 1440 is reported back in the caves.
--   * That the Damp Note starts Allegiance to the Old Gods without Trouble in the Deeps
--     done: the Questie database lists 6562 as its prerequisite, Wowhead Forever does not.
--   * That Baron Aquanis (6922) is on the Forever client, and that taking the Fathom Core
--     summons him.
--   * The surface entrance (1450, 1420) and the portal (1650, 1100); that every
--     Sapphire of Aku'Mai is in the outer caves (none are listed inside).
--   * The notes placing Argent Guard Thaelrid, Lorgus Jett, the Fathom Stone and Twilight
--     Lord Kelris, and Tsunaman's ledge above Sun Rock Retreat.
--   * Bashana Runetotem's spot on the Elder Rise (Wowhead Forever 70.8, 33.4; the Questie
--     database has 71.06, 34.19).
--   * The objective numbers: 6563, 6565, 6921 and 6561 each have one objective (1); 1740's
--     small fragments are objective 1 (the Shadowfang Keep guide has the large one as 2).
--
-- Maps: 1440 Ashenvale (guide default), 1442 Stonetalon Mountains, 1456 Thunder Bluff,
-- 1413 The Barrens.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",

    id = "nuuroad:dungeon:horde-blackfathom-deeps-quests",
    updated = 1790985600,
    title = "Blackfathom Deeps",
    category = "Dungeons/Blackfathom Deeps",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "blackfathom deeps", "bfd", "ashenvale", "zoram'gar" },
    levels = { from = 22, to = 30 },
    cond = { faction = "Horde" },
    source = "NuuRoad's own route through Blackfathom Deeps.",

    data = {
        map = 1440,

        sections = {
            { title = "The far pickups", steps = {
                { type = "note", note = "Doan Karhan in the Barrens and Tsunaman in Stonetalon give two of the quests, far from Ashenvale. Skip a pickup you will not travel for." },
                { type = "accept", quests = { 1740 }, npc = { 6247 }, cond = { class = "WARLOCK" },
                  note = "Warlocks only. Its three small fragments drop in Blackfathom Deeps; the large one is in Shadowfang Keep." },
                { type = "accept", quests = { 6562 }, npc = { 11862 } },
            } },

            { title = "Zoram'gar Outpost", steps = {
                { group = {
                    { type = "turnin", quests = { 6562 }, npc = { 12736 }, optional = true,
                      note = "Andruk, the flight master, stands at 12.24, 33.80; learn the flight path while you are here." },
                    { type = "accept", quests = { 6563, 6921 }, npc = { 12736 } },
                } },
            } },

            { title = "The flooded caves", steps = {
                { type = "travel", to = "the ruins on the Zoram Strand", at = { { 1450, 1420 } },
                  note = "North along the shore. Drop into the opening among the ruins and swim down into the caves beneath." },
                { type = "collect", item = 16790, starts = 6564, kill = { 4802 },
                  at = { { 1355, 1206 }, { 1340, 940 }, { 1580, 1140 } },
                  note = "Blackfathom Tide Priestesses in the caves drop it. Not every one does." },
                { type = "accept", quests = { 6564 }, item = 16790, note = "Use the Damp Note to start its quest." },
                { type = "collect", item = 16784, quest = { 6563, 1 }, object = "Sapphire of Aku'Mai",
                  at = { { 1369, 1227 }, { 1307, 1287 }, { 1379, 1115 }, { 1660, 1120 } },
                  note = "Crystals on the cave walls, all the way along the tunnels to the portal." },
            } },

            { title = "Back to Je'neu", steps = {
                { type = "note", note = "Handing the Damp Note in before the run unlocks Lorgus Jett's quest for it. If your group is waiting, skip and leave it for another run." },
                { group = {
                    { type = "talk", turnin = { 6564 }, accept = { 6565 }, npc = { 12736 }, optional = true },
                    { type = "turnin", quests = { 6563 }, npc = { 12736 }, optional = true },
                } },
                { type = "travel", to = "Blackfathom Deeps", at = { { 1650, 1100 } },
                  note = "Back into the ruins and down through the caves. The portal is at the far end of the flooded tunnels; step in with your group." },
            } },

            { title = "Inside Blackfathom Deeps", steps = {
                { type = "collect", item = 6914, kill = { 4809 }, quest = { 1740, 1 }, sticky = true,
                  cond = { class = "WARLOCK" },
                  note = "Only the Twilight Acolytes among the cultists drop them." },
                { type = "accept", quests = { 6561 }, npc = { 4787 },
                  note = "A group member can share the quest." },
                { type = "kill", kill = { 12902 }, quest = { 6565, 1 },
                  note = "Lorgus Jett walks with Twilight's Hammer cultists past Gelihast's murloc cave, on the way to the Moonshrine Ruins. He has more than one spawn point." },
                { type = "collect", item = 16762, quest = { 6921, 1 }, object = "Fathom Stone",
                  note = "On the floor of the water under the bridge at the Moonshrine Ruins. Taking the core summons Baron Aquanis; get the group ready first." },
                { type = "collect", item = 16782, starts = 6922, kill = { 12876 },
                  note = "Baron Aquanis drops it." },
                { type = "accept", quests = { 6922 }, item = 16782, note = "Use the Strange Water Globe to start its quest." },
                { type = "collect", item = 5881, kill = { 4832 }, quest = { 6561, 1 },
                  note = "Twilight Lord Kelris waits in the shrine past the Moonshrine Ruins. Aku'mai, beyond him, is the last boss and no quest needs him." },
                { type = "travel", to = "the caves outside", zone = 1440, at = { { 1450, 1420 } },
                  note = "Walk back to the entrance and leave through the portal, then swim up out of the caves." },
            } },

            { title = "Turning in", steps = {
                { group = {
                    { type = "turnin", quests = { 6563 }, npc = { 12736 }, optional = true,
                      note = "South along the shore to Zoram'gar Outpost." },
                    { type = "turnin", quests = { 6564 }, npc = { 12736 }, optional = true,
                      note = "Je'neu then offers Lorgus Jett's quest for another run." },
                    { type = "turnin", quests = { 6565 }, npc = { 12736 }, optional = true },
                    { type = "turnin", quests = { 6921 }, npc = { 12736 }, optional = true },
                    { type = "turnin", quests = { 6922 }, npc = { 12736 }, optional = true },
                } },
                { type = "turnin", quests = { 6561 }, npc = { 9087 }, optional = true,
                  note = "Fly to Thunder Bluff from Andruk (12.24, 33.80)." },
                { type = "turnin", quests = { 1740 }, npc = { 6247 }, optional = true, cond = { class = "WARLOCK" },
                  note = "Once you also have the Large Soran'ruk Fragment from Shadowfang Keep." },
                { type = "finish", note = "Every Horde quest of Blackfathom Deeps is done or left for another run." },
            } },
        },

        npcs = {
            [1440] = { -- Ashenvale
                [12736] = { name = "Je'neu Sancrea", at = { 1156, 3429 },
                            note = "In Zoram'gar Outpost, on the shore in the far west of Ashenvale." },
                [4802] = "Blackfathom Tide Priestess",

                -- Inside Blackfathom Deeps, whose entrance is on this map. Instance ID not yet known.
                [4787] = { name = "Argent Guard Thaelrid",
                           note = "Inside Blackfathom Deeps, among his fallen guards in the first half of the dungeon, past Ghamoo-ra and Lady Sarevess." },
                [4809] = "Twilight Acolyte",
                [4832] = "Twilight Lord Kelris",
                [12876] = "Baron Aquanis",
                [12902] = "Lorgus Jett",
            },
            [1413] = { -- The Barrens
                [6247] = { name = "Doan Karhan", at = { 4931, 5721 } },
            },
            [1442] = { -- Stonetalon Mountains
                [11862] = { name = "Tsunaman", at = { 4736, 6425 },
                            note = "On a ledge above Sun Rock Retreat; take the path that climbs the mountainside from the village." },
            },
            [1456] = { -- Thunder Bluff
                [9087] = { name = "Bashana Runetotem", at = { 7080, 3340 }, note = "On the Elder Rise." },
            },
        },
    },
})
