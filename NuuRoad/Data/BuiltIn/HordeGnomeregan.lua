local _, ns = ...

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
-- The guide stands on its own. Every dungeon objective is gated on its quest being in the
-- log, every turn-in waits for its quest to be ready, and the optional ring and
-- Sparklematic quests are passed over unless the item that starts them is in the bags
-- when the guide gets there.
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
--     silver from outside the dungeon; its turn-in is passed over unless it is ready.
--   * The Alliance quests (Save Techbot's Brain!, Gnogaine, Data Rescue and the rest) are
--     Alliance-only on Forever and left out.
--   * No hearth step; the Orgrimmar hearth is a note.
--   * The inside of the dungeon has no coordinates. Kernobee, the Sparklematic and the
--     bosses are placed by note; the instance map is not in the travel data.
--
-- Check in client:
--   * that the goblin transporter beside Scooty works on Forever with the Goblin
--     Transponder, where it lands, and where the pad back to Booty Bay is;
--   * the zone text inside the instance ("Gnomeregan") that completes the entrance step,
--     and "Dun Morogh" outside for the exit step;
--   * Kernobee in the Dormitory past the Clean Zone, and the Sparklematic 5200 that takes
--     quests 2945 and 2951 in the Clean Zone;
--   * that Rig Wars must be in the log before Sovik offers Chief Engineer Scooty.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1454 Orgrimmar (guide default), 1434 Stranglethorn Vale, 1426 Dun Morogh.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-gnomeregan-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-gnomeregan-quests",
    updated = 1790985600,
    map = 1454,
    only = "Horde",
    meta = {
        title = "Gnomeregan",
        author = "NuuRoad",
        category = "Dungeons/Gnomeregan",
        tags = { "horde", "dungeon", "gnomeregan", "gnomer", "dun morogh", "booty bay", "orgrimmar" },
        levels = { 29, 35 },
    },
    steps = {
        { section = "Orgrimmar", steps = {
            { note = "Gnomeregan is above the level 30 cap: its bosses are level 32 to 34. Go with a full group of level 30s." },
            { group = {
                { accept = 2841, npc = 3412,
                    note = "In the Valley of Honor. Take Rig Wars first: Sovik's quest, and the transponder after it, open only while it is in your log." },
                { accept = 2842, npc = 3413,
                    note = "Next to Nogg. Talk him through his dialogue to get the quest." },
            } },
        } },

        { section = "Booty Bay", map = 1434, steps = {
            { turnin = 2842, accept = 2843, npc = 7853,
                note = "Take the zeppelin to Grom'gol from the tower outside Orgrimmar and follow the road south, or the boat from Ratchet." },
            { turnin = 2843, npc = 7853,
                note = "Wait a few seconds while he calibrates the transponder, then hand the quest in." },
            { travel = "Gnomeregan", zone = "Gnomeregan", at = { 24.30, 39.30, map = 1426 },
                note = "With the Goblin Transponder in your bags, step onto the transporter pad beside Scooty. It puts you down in the tunnels outside the dungeon; keep left to the portal and go in with your group. Without the transponder the only other way is a long walk through Alliance land past Ironforge." },
        } },

        { section = "Inside Gnomeregan", steps = {
            { note = "Most creatures here can drop a Grime-Encrusted Object, and the Dark Iron Agents sometimes drop a Grime-Encrusted Ring. Keep either for the Sparklematic 5200." },
            { accept = 2945, only = "now item 9326 | now level 28",
                note = "Use the Grime-Encrusted Ring to start its quest." },
            { group = {
                { turnin = 2945, accept = 2949, object = "The Sparklematic 5200", only = "now quest 2945",
                    note = "The machine stands in the Clean Zone. Return of the Ring is optional: Nogg can rework the ring later." },
                { accept = 2951, object = "The Sparklematic 5200", only = "now item 9308 | now level 25",
                    note = "Have three silver to start the machine." },
            } },
            { turnin = 2951, object = "The Sparklematic 5200", only = "now quest 2951" },
            { accept = 2904, npc = 7850,
                note = "In the Dormitory past the Clean Zone, among the leper gnomes." },
            { escort = 2904, npc = 7850, only = "quest 2904",
                note = "Keep him alive back to the exit of the Clockwerk Run. He is fragile; clear the way first." },
            { objective = 2841, part = 2, collect = 9299, kill = 7800, only = "quest 2841",
                note = "The last boss, in Tinkers' Court at the bottom of the dungeon, past Viscous Fallout, Electrocutioner 6000 and Crowd Pummeler 9-60. Press the buttons around the room to stop the walking bombs." },
            { objective = 2841, part = 1, collect = 9153, object = "Thermaplugg's Safe", only = "quest 2841",
                note = "The safe is on the north side of his room. It opens with the combination he drops." },
            { travel = "the transporter pad", zone = "Dun Morogh", at = { 24.30, 39.30, map = 1426 },
                note = "Leave through the portal and take the goblin pad in the tunnels back to Booty Bay." },
        } },

        { section = "Turning in", steps = {
            { turnin = 2904, npc = 7853, only = "quest 2904 readyToTurnIn",
                note = "Scooty, in Booty Bay." },
            { group = {
                { turnin = 2841, npc = 3412, only = "quest 2841 readyToTurnIn",
                    note = "Back to Orgrimmar by the zeppelin from Grom'gol, or by your hearthstone if it is set there." },
                { turnin = 2949, accept = 2950, npc = 3412, only = "now quest 2949",
                    note = "Nogg's Ring Redo asks for a Silver Bar, a Moss Agate and 30 silver. Take it only if you mean to bring them." },
            } },
            { turnin = 2950, npc = 3412, only = "now quest 2950 readyToTurnIn" },
            { finish = "Every Horde quest of Gnomeregan is done or left for another run." },
        } },
    },
    names = {
        npcs = {
            [3412] = { "Nogg", at = { 75.99, 25.41 } },
            [3413] = { "Sovik", at = { 75.49, 25.36 } },
            [7800] = "Mekgineer Thermaplugg",
            [7850] = "Kernobee",
            [7853] = { "Scooty", at = { 27.60, 77.48, map = 1434 } },
        },
        quests = {
            [2841] = "Rig Wars",
            [2842] = "Chief Engineer Scooty",
            [2843] = "Gnomer-gooooone!",
            [2904] = "A Fine Mess",
            [2945] = "Grime-Encrusted Ring",
            [2949] = "Return of the Ring",
            [2950] = "Nogg's Ring Redo",
            [2951] = "The Sparklematic 5200!",
        },
        items = {
            [9153] = "Rig Blueprints",
            [9299] = "Thermaplugg's Safe Combination",
            [9308] = "Grime-Encrusted Object",
            [9326] = "Grime-Encrusted Ring",
        },
    },
}
