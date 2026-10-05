-- A packaged guide, in guide format v1 (docs/examples/guide-v1.lua).
--
-- Every Horde quest of Gnomeregan, from Nogg and Sovik in Orgrimmar to the last turn-in
-- with Nogg. Quest, NPC and item IDs, quest levels, prerequisites, the drops of the quest
-- items, and the spots of Nogg, Sovik and Scooty were checked against Questie's Forever
-- database (QuestieDB_Forever, reference only); the entrance point and the Rig Wars gate on
-- Chief Engineer Scooty come from ForeverDungeonJournal (DungeonEntrances.lua,
-- QuestChains.lua). The pickup order, the boss notes and the turn-in order (Scooty in
-- Booty Bay on the way home, then Nogg) are NuuRoad's own.
--
-- Gnomeregan sits past the level 30 cap of the beta: ForeverDungeonJournal lists it at
-- 29-38, its bosses are 32 to 34 and the quests are level 30 to 35. Every quest here can
-- be taken at 30 or below (the highest minimum is 28, for the Grime-Encrusted Ring and
-- its follow-ups), so nothing is left out for its level, but the run wants a full group.
--
-- The guide stands on its own. Every turn-in waits for its quest to be ready, and the
-- optional ring and Sparklematic quests pass when the item that starts them is not in the
-- bags (or the quest is not in the log) when the guide gets there.
--
-- Recorded choices:
--   * The way in is Scooty's goblin transporter in Booty Bay. Gnomer-gooooone! hands over
--     the Goblin Transponder that the pad needs, and its chain opens only with Rig Wars in
--     the log, so Rig Wars is taken before Sovik's quest. Walking to Dun Morogh through
--     Alliance land is only mentioned, not routed.
--   * The Sparklematic 5200! (2951) is carried, once, for whoever has a Grime-Encrusted
--     Object. Its repeatable follow-ups (2952, 2953) and the copies at the other two
--     machines (4601-4606) are left out.
--   * Return of the Ring (2949) and Nogg's Ring Redo (2950) are carried for whoever finds
--     the Grime-Encrusted Ring. Nogg's Ring Redo needs a Silver Bar, a Moss Agate and 30
--     silver from outside the dungeon; its turn-in is optional, passed over unless ready.
--   * The Alliance quests (Save Techbot's Brain!, Gnogaine, Data Rescue and the rest) are
--     Alliance-only on Forever and left out.
--   * No hearth step; the Orgrimmar hearth is a note.
--   * The inside of the dungeon has no coordinates. Kernobee, the Sparklematic and the
--     bosses are placed by note; the instance map is not in the travel data.
--
-- Check in client:
--   * that the goblin transporter beside Scooty works on Forever with the Goblin
--     Transponder, where it lands, and where the pad back to Booty Bay is;
--   * Gnomeregan's instance ID (GetInstanceInfo), to give the entrance step `instance`
--     and Kernobee `instance`; and that the exit step's zone (Dun Morogh, 1426) is the map
--     the client reports outside;
--   * Kernobee in the Dormitory past the Clean Zone, and the Sparklematic 5200 that takes
--     quests 2945 and 2951 in the Clean Zone;
--   * that Rig Wars must be in the log before Sovik offers Chief Engineer Scooty;
--   * Sovik's gossip option IDs, to turn "talk him through his dialogue" into `say`.
--
-- Maps: 1454 Orgrimmar (guide default), 1434 Stranglethorn Vale, 1426 Dun Morogh.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    schema = 1,

    id = "nuuroad:dungeon:horde-gnomeregan-quests",
    updated = 1790985600,
    title = "Gnomeregan",
    category = "Dungeons/Gnomeregan",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "gnomeregan", "gnomer", "dun morogh", "booty bay", "orgrimmar" },
    levels = { from = 29, to = 35 },
    cond = { faction = "Horde" },

    data = {
        map = 1454,

        sections = {
            { title = "Orgrimmar", steps = {
                { type = "note", note = "Gnomeregan is above the level 30 cap: its bosses are level 32 to 34. Go with a full group of level 30s." },
                { group = {
                    { type = "accept", quests = { 2841 }, npc = { 3412 },
                      note = "Take Rig Wars first: Sovik's quest, and the transponder after it, open only while it is in your log." },
                    { type = "accept", quests = { 2842 }, npc = { 3413 },
                      note = "Talk him through his dialogue to get the quest." },
                } },
            } },

            { title = "Booty Bay", map = 1434, steps = {
                { type = "talk", turnin = { 2842 }, accept = { 2843 }, npc = { 7853 },
                  note = "Take the zeppelin to Grom'gol from the tower outside Orgrimmar and follow the road south, or the boat from Ratchet." },
                { type = "turnin", quests = { 2843 }, npc = { 7853 },
                  note = "Wait a few seconds while he calibrates the transponder, then hand the quest in." },
                { type = "travel", to = "Gnomeregan", at = { { 2430, 3930, map = 1426 } },
                  note = "With the Goblin Transponder in your bags, step onto the transporter pad beside Scooty. It puts you down in the tunnels outside the dungeon; keep left to the portal and go in with your group. Without the transponder the only other way is a long walk through Alliance land past Ironforge." },
            } },

            { title = "Inside Gnomeregan", steps = {
                { type = "note", note = "Most creatures here can drop a Grime-Encrusted Object, and the Dark Iron Agents sometimes drop a Grime-Encrusted Ring. Keep either for the Sparklematic 5200." },
                { type = "accept", quests = { 2945 }, item = 9326,
                  note = "Use the Grime-Encrusted Ring to start its quest." },
                { group = {
                    { type = "talk", turnin = { 2945 }, accept = { 2949 }, object = "The Sparklematic 5200",
                      note = "The machine stands in the Clean Zone. Return of the Ring is optional: Nogg can rework the ring later." },
                    { type = "accept", quests = { 2951 }, object = "The Sparklematic 5200",
                      note = "Only with a Grime-Encrusted Object in your bags; skip this otherwise. Have three silver to start the machine." },
                } },
                { type = "turnin", quests = { 2951 }, object = "The Sparklematic 5200" },
                { type = "accept", quests = { 2904 }, npc = { 7850 } },
                { type = "escort", quest = 2904, npc = { 7850 },
                  note = "Keep him alive back to the exit of the Clockwerk Run. He is fragile; clear the way first." },
                { type = "collect", item = 9299, kill = { 7800 }, quest = { 2841, 2 },
                  note = "The last boss, in Tinkers' Court at the bottom of the dungeon, past Viscous Fallout, Electrocutioner 6000 and Crowd Pummeler 9-60. Press the buttons around the room to stop the walking bombs." },
                { type = "collect", item = 9153, object = "Thermaplugg's Safe", quest = { 2841, 1 },
                  note = "The safe is on the north side of his room. It opens with the combination he drops." },
                { type = "travel", to = "the transporter pad", zone = 1426, at = { { 2430, 3930, map = 1426 } },
                  note = "Leave through the portal and take the goblin pad in the tunnels back to Booty Bay." },
            } },

            { title = "Turning in", steps = {
                { type = "turnin", quests = { 2904 }, npc = { 7853 } },
                { group = {
                    { type = "turnin", quests = { 2841 }, npc = { 3412 },
                      note = "Back to Orgrimmar by the zeppelin from Grom'gol, or by your hearthstone if it is set there." },
                    { type = "talk", turnin = { 2949 }, accept = { 2950 }, npc = { 3412 },
                      note = "Nogg's Ring Redo asks for a Silver Bar, a Moss Agate and 30 silver. Take it only if you mean to bring them." },
                } },
                { type = "turnin", quests = { 2950 }, npc = { 3412 }, optional = true },
                { type = "finish", note = "Every Horde quest of Gnomeregan is done or left for another run." },
            } },
        },

        npcs = {
            [1454] = { -- Orgrimmar
                [3412] = { name = "Nogg", at = { 7599, 2541 }, note = "In the Valley of Honor." },
                [3413] = { name = "Sovik", at = { 7549, 2536 }, note = "Next to Nogg." },
            },
            [1434] = { -- Stranglethorn Vale
                [7853] = { name = "Scooty", at = { 2760, 7748 }, note = "In Booty Bay." },
            },
            [1426] = { -- Dun Morogh
                -- Inside Gnomeregan, whose entrance is on this map. No instance ID yet.
                [7850] = { name = "Kernobee", note = "In the Dormitory past the Clean Zone, among the leper gnomes." },
                [7800] = "Mekgineer Thermaplugg",
            },
        },
    },
})
