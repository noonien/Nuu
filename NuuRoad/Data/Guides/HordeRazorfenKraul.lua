-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeRazorfenKraul.lua.
--
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
-- The guide stands on its own. A quest left behind (or never shared) has no accept the
-- player took, and its dungeon steps wait on the player to skip them.
--
-- Levels: ForeverDungeonJournal lists the Kraul at 29-38, and Forever's bosses run 28 to
-- 33. With the cap at 30 the dungeon is the top of what a character can do, so the guide
-- is marked 28-30:
--   * A Vengeful Fate (1102) needs level 29, Going, Going, Guano! (1109) needs level 30,
--     and An Unholy Alliance (6522, from the Small Scroll) needs level 28. A character
--     too low for one skips its pickup.
--   * Blueleaf Tubers (1221, level 20) and Willix the Importer (1144, level 22) need no
--     more than the guide's range.
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
--     note (on their `npcs` entries); the instance map is not in the travel data.
--
-- Check in client: Razorfen Kraul's instance ID (GetInstanceInfo), to finish the entrance
-- step on entering and to mark the NPCs inside; the walk from Camp Taurajo to the
-- entrance; where Willix the Importer is held and that his escort ends at the entrance;
-- which objective line of Blueleaf Tubers counts the tubers (1 assumed); Auld
-- Stonespire's spot in Thunder Bluff; that the Small Scroll starts 6522 when used.
--
-- Maps: 1413 The Barrens (guide default), 1456 Thunder Bluff, 1458 Undercity.
--
-- Conversion notes:
--   * Guide `only = "Horde"` -> wrapper cond = { faction = "Horde" }; meta levels { 28, 30 }
--     -> levels = { from = 28, to = 30 }. Same id and updated.
--   * Dropped `now level` gates: "now level 30" (1109 accept), "now level 29" (1102
--     accept), "now level 28" (Small Scroll collect) and "now level 28 | now item 17008"
--     (6522 accept). The format has no level predicate. The opening note said a quest
--     the player is too low for is passed over; it now says to skip it. The 6522 accept
--     became an accept from an item (item = 17008, no npc), which passes when the scroll
--     is not in the bags, covering the "now item" half.
--   * Dropped quest-state gates "quest 1109", "quest 1221", "quest 1144", "quest 1102" on
--     the dungeon steps: the format cannot carry them.
--   * Turn-ins gated on "quest N readyToTurnIn" (1144, 1221, 1102, 1109) and on "quest
--     6522" became `optional = true`: passed on arrival unless ready, never waited on.
--   * `objective`/`part` -> quest = { id, 1 } on collect steps (1109, 1221, 1102), as the
--     source has them. The Blueleaf Tubers objective number (1) was assumed in the source
--     too. Count dropped: the tubers' count = 6 is the objective's business.
--   * The escort became type "escort" with quest = 1144 and npc = { 4508 }; it has no `at`
--     (the source gives no end point).
--   * Travel `zone = "Razorfen Kraul"` (a name): the dungeon's instance ID is not in the
--     repo, so `instance` is left out and the step finishes on arrival at the portal
--     point (4290, 9020). Add instance = 47 (Razorfen Kraul's usual GetInstanceInfo ID)
--     once confirmed on the Forever client. Travel `zone = "The Barrens"` -> zone = 1413.
--   * NPCs inside the dungeon (Willix 4508, Charlga 4421, the bats 4538, 4539 and the
--     Blind Hunter 4425) are listed under 1413, the entrance's map, without `instance`
--     (ID not in the repo) and without a position. Willix and Charlga get notes saying
--     where they are; the bats and the Blind Hunter are kill targets, names only.
--   * Where-notes moved from steps to the NPC they place: Faranell in the Apothecarium,
--     Varimathras in the Royal Quarter with the tunnel (kept as text, 51.93, 64.78; no
--     place made for it), Willix a prisoner inside, Charlga at the far end. Route notes
--     (zeppelin, flights, sharing) and "He waits where the escort ends" stay on the steps.
--   * `names.quests` and `names.items` dropped: the client names them.
--   * No track/untrack pairs, no places, no section maps needed (every off-map point is an
--     NPC listed under its own map).

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:dungeon:horde-razorfen-kraul-quests",
    updated = 1790985600,
    title = "Razorfen Kraul",
    category = "Dungeons/Razorfen Kraul",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "razorfen kraul", "rfk", "barrens", "thunder bluff", "undercity" },
    levels = { from = 28, to = 30 },
    cond = { faction = "Horde" },
    source = "Converted from NuuRoad's earlier Razorfen Kraul guide (format v2).",

    data = {
        map = 1413,

        sections = {
            { title = "The far pickup", steps = {
                { type = "note", note = "Razorfen Kraul is the top of the level 30 cap: its bosses run to level 33, and three of its quests need level 28 to 30. Skip a quest you are too low for." },
                { type = "accept", quests = { 1109 }, npc = { 2055 },
                  note = "Far from the Barrens: press > to pass it over. A group member who has it can share it inside. The zeppelin to Tirisfal leaves from the tower outside Orgrimmar." },
            } },

            { title = "Thunder Bluff and Ratchet", steps = {
                { type = "accept", quests = { 1102 }, npc = { 4451 } },
                { type = "accept", quests = { 1221 }, npc = { 3446 },
                  note = "He hands you a crate, a command stick and a manual. Keep the crate and the stick: he wants them back with the tubers." },
            } },

            { title = "The road to the Kraul", steps = {
                { type = "travel", to = "Razorfen Kraul", at = { { 4290, 9020 } },
                  note = "Fly to Camp Taurajo and head south to the bottom of the Barrens. The Kraul is a maze of giant thorns; follow it to the portal and step in with your group." },
            } },

            { title = "Inside Razorfen Kraul", steps = {
                { type = "collect", item = 5801, kill = { 4538, 4539, 4425 }, quest = { 1109, 1 }, sticky = true,
                  note = "Kraul Bats and Greater Kraul Bats drop it, and so does the Blind Hunter if he is up." },
                { type = "collect", item = 5876, quest = { 1221, 1 }, use = { 5880, 6684 }, sticky = true,
                  note = "Use the Crate with Holes to call a Snufflenose Gopher, then use the Command Stick on it to send it looking. Loot each tuber it turns up. Call it again whenever the group stops." },
                { type = "accept", quests = { 1144 }, npc = { 4508 },
                  note = "Talk to him when you find him; each player takes the quest." },
                { type = "escort", quest = 1144, npc = { 4508 },
                  note = "He walks back towards the entrance. Stay close and keep attackers off him." },
                { type = "turnin", quests = { 1144 }, npc = { 4508 }, optional = true,
                  note = "He waits where the escort ends." },
                { type = "collect", item = 5793, kill = { 4421 }, quest = { 1102, 1 } },
                { type = "collect", item = 17008, starts = 6522, kill = { 4421 },
                  note = "Charlga drops a Small Scroll for every member of the group." },
                { type = "accept", quests = { 6522 }, item = 17008,
                  note = "Use the Small Scroll to start its quest." },
                { type = "travel", to = "the Kraul's entrance", zone = 1413, at = { { 4290, 9020 } },
                  note = "Leave through the portal." },
            } },

            { title = "Turning in", steps = {
                { type = "turnin", quests = { 1221 }, npc = { 3446 }, optional = true,
                  note = "Fly to Ratchet from Camp Taurajo. Bring the crate and the command stick along with the tubers." },
                { type = "turnin", quests = { 1102 }, npc = { 4451 }, optional = true },
                { group = {
                    { type = "turnin", quests = { 1109 }, npc = { 2055 }, optional = true,
                      note = "Fly to Orgrimmar and take the zeppelin to Tirisfal." },
                    { type = "turnin", quests = { 6522 }, npc = { 2425 }, optional = true,
                      note = "He offers a follow-up for Razorfen Downs, which is beyond the level cap." },
                } },
                { type = "finish", note = "Every Horde quest of Razorfen Kraul is done or left for another run." },
            } },
        },

        npcs = {
            [1413] = { -- The Barrens
                [3446] = { name = "Mebok Mizzyrix", at = { 6237, 3762 } },
                -- Inside Razorfen Kraul, whose entrance is on this map.
                [4508] = { name = "Willix the Importer",
                           note = "A prisoner inside the Kraul." },
                [4421] = { name = "Charlga Razorflank",
                           note = "The last boss, at the far end of the Kraul." },
                [4425] = "Blind Hunter",
                [4538] = "Kraul Bat",
                [4539] = "Greater Kraul Bat",
            },
            [1456] = { -- Thunder Bluff
                [4451] = { name = "Auld Stonespire", at = { 3640, 5960 } },
            },
            [1458] = { -- Undercity
                [2055] = { name = "Master Apothecary Faranell", at = { 4884, 6925 },
                           note = "In the Apothecarium." },
                [2425] = { name = "Varimathras", at = { 5626, 9219 },
                           note = "In the Royal Quarter. The tunnel down starts at 51.93, 64.78." },
            },
        },
    },
})
