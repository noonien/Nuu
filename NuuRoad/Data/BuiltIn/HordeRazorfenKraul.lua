local _, ns = ...

-- Every Horde quest of Razorfen Kraul a character at the level 30 cap can take, from
-- Master Apothecary Faranell in the Undercity to the last turn-in. The quest list, quest
-- levels, required levels, givers, enders, and quest items come from Wowhead's Forever
-- database (zone 491 lists exactly 1102, 1109, 1144, 1221 and 6522 for the Horde) and
-- agree with ForeverDungeonJournal's Data/Dungeons.lua. Coordinates: Mebok Mizzyrix is the
-- spot the Wailing Caverns guide (HordeWailingCaverns.lua) already uses, Faranell the one
-- the Silverpine guide (HordeSilverpine1214.lua) uses, Varimathras and the Royal Quarter
-- tunnel the ones the Ragefire Chasm guide (HordeRagefireChasm.lua) uses, Auld Stonespire
-- the middle of his Wowhead Forever spawn points (36.2-36.8, 59.4-59.8), and the entrance
-- the point ForeverDungeonJournal (42.7, 90.0) and the Questie dungeon table (42.9, 90.2)
-- agree on. The pickup and turn-in order is NuuRoad's own.
--
-- The guide stands on its own. Every dungeon objective is gated on its quest being in the
-- log, so a quest left behind (or never shared) hides its steps, and every turn-in waits
-- for its quest to be ready.
--
-- Levels: ForeverDungeonJournal lists the Kraul at 29-38, and Forever's bosses run 28 to
-- 33. With the cap at 30 the dungeon is the top of what a character can do, so the guide
-- is marked 28-30 and the pickups that need a level are gated on it:
--   * A Vengeful Fate (1102) needs level 29, Going, Going, Guano! (1109) needs level 30,
--     and An Unholy Alliance (6522, from the Small Scroll) needs level 28. Each is offered
--     only if the character has the level when the guide reaches it ("now level"), so a
--     lower character is never stopped on a quest it cannot take.
--   * Blueleaf Tubers (1221, level 20) and Willix the Importer (1144, level 22) have no
--     such gate.
--
-- Recorded choices:
--   * Left out: An Unholy Alliance (6521), Varimathras' follow-up, which is for
--     Razorfen Downs; Hearts of Zeal (1113), Faranell's follow-up, which is for Scarlet
--     Monastery; and the Warrior quest Brutal Armor (1838), whose materials come from
--     several dungeons and which no Forever source ties to this one.
--   * The Undercity pickup is far from the Barrens, so the guide says it may be passed
--     over; Faranell's quest can be shared inside.
--   * Blueleaf Tubers and Willix the Importer cannot be shared on Forever; each player
--     takes them.
--   * Mebok wants the crate and the command stick back with the tubers, so the guide says
--     to keep them. No step asks to destroy anything.
--   * No hearth step and no step asking the player to die and run back; leaving is a
--     plain walk out through the portal.
--   * The inside of the dungeon has no coordinates. Willix and the bosses are placed by
--     note; the instance map is not in the travel data.
--
-- Check in client: the zone text inside the instance ("Razorfen Kraul") that completes
-- the entrance step, and that the Barrens outside still reads "The Barrens" after the run;
-- the walk from Camp Taurajo to the entrance; where Willix the Importer is held and
-- that his escort ends at the entrance; which objective line of Blueleaf Tubers counts the
-- tubers (part 1 assumed); Auld Stonespire's spot in Thunder Bluff; that the Small Scroll
-- starts 6522 when used.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1413 The Barrens (guide default), 1456 Thunder Bluff, 1458 Undercity.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-razorfen-kraul-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-razorfen-kraul-quests",
    updated = 1790985600,
    map = 1413,
    only = "Horde",
    meta = {
        title = "Razorfen Kraul",
        author = "NuuRoad",
        category = "Dungeons/Razorfen Kraul",
        tags = { "horde", "dungeon", "razorfen kraul", "rfk", "barrens", "thunder bluff", "undercity" },
        levels = { 28, 30 },
    },
    steps = {
        { section = "The far pickup", steps = {
            { note = "Razorfen Kraul is the top of the level 30 cap: its bosses run to level 33, and three of its quests need level 28 to 30. A quest you are too low for is passed over." },
            { accept = 1109, npc = 2055, only = "now level 30",
                note = "In the Apothecarium in the Undercity, far from the Barrens: press > to pass it over. A group member who has it can share it inside. The zeppelin to Tirisfal leaves from the tower outside Orgrimmar." },
        } },

        { section = "Thunder Bluff and Ratchet", steps = {
            { accept = 1102, npc = 4451, only = "now level 29" },
            { accept = 1221, npc = 3446,
                note = "He hands you a crate, a command stick and a manual. Keep the crate and the stick: he wants them back with the tubers." },
        } },

        { section = "The road to the Kraul", steps = {
            { travel = "Razorfen Kraul", zone = "Razorfen Kraul", at = { 42.90, 90.20 },
                note = "Fly to Camp Taurajo and head south to the bottom of the Barrens. The Kraul is a maze of giant thorns; follow it to the portal and step in with your group." },
        } },

        { section = "Inside Razorfen Kraul", steps = {
            { objective = 1109, part = 1, collect = 5801, kill = { 4538, 4539, 4425 }, sticky = true, only = "quest 1109",
                note = "Kraul Bats and Greater Kraul Bats drop it, and so does the Blind Hunter if he is up." },
            { objective = 1221, part = 1, collect = 5876, count = 6, use = { 5880, 6684 }, sticky = true, only = "quest 1221",
                note = "Use the Crate with Holes to call a Snufflenose Gopher, then use the Command Stick on it to send it looking. Loot each tuber it turns up. Call it again whenever the group stops." },
            { accept = 1144, npc = 4508,
                note = "Willix the Importer is a prisoner inside the Kraul. Talk to him when you find him; each player takes the quest." },
            { escort = 1144, npc = 4508, only = "quest 1144",
                note = "He walks back towards the entrance. Stay close and keep attackers off him." },
            { turnin = 1144, npc = 4508, only = "quest 1144 readyToTurnIn",
                note = "He waits where the escort ends." },
            { objective = 1102, part = 1, collect = 5793, kill = 4421, only = "quest 1102",
                note = "Charlga Razorflank is the last boss, at the far end of the Kraul." },
            { collect = 17008, starts = 6522, kill = 4421, only = "now level 28",
                note = "Charlga drops a Small Scroll for every member of the group." },
            { accept = 6522, only = "now level 28 | now item 17008",
                note = "Use the Small Scroll to start its quest." },
            { travel = "the Kraul's entrance", zone = "The Barrens", at = { 42.90, 90.20 },
                note = "Leave through the portal." },
        } },

        { section = "Turning in", steps = {
            { turnin = 1221, npc = 3446, only = "quest 1221 readyToTurnIn",
                note = "Fly to Ratchet from Camp Taurajo. Bring the crate and the command stick along with the tubers." },
            { turnin = 1102, npc = 4451, only = "quest 1102 readyToTurnIn" },
            { group = {
                { turnin = 1109, npc = 2055, only = "quest 1109 readyToTurnIn",
                    note = "Fly to Orgrimmar and take the zeppelin to Tirisfal. Faranell is in the Apothecarium." },
                { turnin = 6522, npc = 2425, only = "quest 6522",
                    note = "In the Royal Quarter. The tunnel down starts at 51.93, 64.78. He offers a follow-up for Razorfen Downs, which is beyond the level cap." },
            } },
            { finish = "Every Horde quest of Razorfen Kraul is done or left for another run." },
        } },
    },
    names = {
        npcs = {
            [2055] = { "Master Apothecary Faranell", at = { 48.84, 69.25, map = 1458 } },
            [2425] = { "Varimathras", at = { 56.26, 92.19, map = 1458 } },
            [3446] = { "Mebok Mizzyrix", at = { 62.37, 37.62 } },
            [4421] = "Charlga Razorflank",
            [4425] = "Blind Hunter",
            [4451] = { "Auld Stonespire", at = { 36.40, 59.60, map = 1456 } },
            [4508] = "Willix the Importer",
            [4538] = "Kraul Bat",
            [4539] = "Greater Kraul Bat",
        },
        quests = {
            [1102] = "A Vengeful Fate",
            [1109] = "Going, Going, Guano!",
            [1144] = "Willix the Importer",
            [1221] = "Blueleaf Tubers",
            [6522] = "An Unholy Alliance",
        },
        items = {
            [5793] = "Razorflank's Heart",
            [5801] = "Kraul Guano",
            [5876] = "Blueleaf Tuber",
            [5880] = "Crate With Holes",
            [6684] = "Snufflenose Command Stick",
            [17008] = "Small Scroll",
        },
    },
}
