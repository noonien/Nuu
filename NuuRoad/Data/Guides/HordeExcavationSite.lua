-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeExcavationSite.lua.
--
-- The Horde quests of Excavation Site: Wetlands, a dungeon new in WoW: Forever, from the
-- pickups in Orgrimmar and Hammerfall to the last turn-in in Mulgore. No recorded session
-- has been near the dungeon yet (nothing in Archive/ or the NuuRoad session logs names it
-- or its quests), so this guide is built from data alone and claims little:
--   * The quest IDs (95663, 95664, 95682, 95697, 98823) are in the client's own quest table
--     (QuestV2, build 1.60.1.70009, db/sources/wago/forever), and so are the dungeon's area
--     names (AreaTable): "Excavation Site: Wetlands" for the instance (16732) and for a
--     subzone of the Wetlands outside it (17732), and inside it Lost Marsh, Stalker's
--     Thicket, Site of the Guardian and Lost Dig Site. The item IDs and names of the
--     Dragonmaw Dispatch (284844), Thicket Raptor Meat (271100) and the Titan Relic
--     (270866, which the client says starts Elder Knowledge) are from ItemSparse there.
--   * Who gives and takes each quest, the levels (31, requires 24), the objectives, the NPC
--     IDs, and the givers' spots come from Wowhead's Forever database (wowhead.com/forever,
--     read 2026-10-03). Only facts are taken:
--       Dragonmaw Rumors (95663): Zaruk (2787), Hammerfall, Arathi 74.4, 35.4, to the
--         Deathstalker Agent (13155), in the hills above the Dragonmaw camp, Wetlands
--         51.4, 59.2 (both of his spawns).
--       Open the Maw (95682): from and to the Deathstalker Agent. Slay 2 Dragonmaw
--         Saboteurs (275045) and 4 Dragonmaw Warders (275044), obtain the Dragonmaw
--         Dispatch, in that order on the page. Dragonmaw Rumors comes before it in the
--         series.
--       Changing Tastes (95697): from and to Borstan (3368), Orgrimmar 57.4, 53.4.
--         Collect 4 Thicket Raptor Meat.
--       Elder Knowledge (95664): starts from the Titan Relic, ends with Bashana Runetotem
--         (9087), Thunder Bluff 70.8, 33.4, who starts Earthen Echo (98823).
--       Earthen Echo (98823): to Muln Earthfury at Skywatcher Plateau, northwest Mulgore.
--         The Muln Earthfury standing in Mulgore is 259118, at 33.4, 22.4; his page does
--         not list the quest, so the ID is matched by place.
--       The bosses' IDs: Saltspine (260322), Shadetooth (260325), Relic Guardian (260326).
--   * ForeverDungeonJournal (Data/Dungeons.lua, DungeonEntrances.lua, QuestUpdates.lua,
--     SOURCES.txt) agrees on all of the above and adds: the entrance, a blue mist portal
--     under a large tree in the hills southeast of Whelgar's Excavation, reached from
--     Thelgen Rock, Wetlands 47.8, 56.3; the raptor meat from the Thicket raptors in
--     Stalker's Thicket, Shadetooth's area; the Relic Guardian as the last boss and the
--     Titan Relic as its drop; Saltspine a white crocolisk. The journal marks the dungeon a
--     preview without full data.
--   * Questie's Forever database and RestedXP's Forever data have nothing on these quests.
--
-- Check in client (not in the evidence, so left out or only noted):
--   * Whether Open the Maw is offered without Dragonmaw Rumors turned in. The Hammerfall
--     pickup is far out of the way at this level; if the Agent offers Open the Maw anyway,
--     the Zaruk step can be dropped.
--   * The Deathstalker Agent's spot (Wowhead 51.4, 59.2; the journal puts him at the
--     entrance, 47.8, 56.3) and the entrance itself.
--   * The zone text inside ("Excavation Site: Wetlands") that completed the entrance step
--     in the source, and that "Wetlands" comes back on leaving although the subzone outside
--     carries the dungeon's name.
--   * The order of the three Open the Maw objective lines (objectives 1 to 3 below follow
--     Wowhead's list), and which Dragonmaw carries the Dispatch.
--   * The creature IDs of the Thicket raptors, where the Dragonmaw stand inside, and the
--     boss order and where each boss is.
--   * That the Titan Relic always drops for a Horde player, and that Muln Earthfury 259118
--     takes Earthen Echo.
--   * The real level range: every quest requires 24 and is level 31; the journal's card
--     says 26 to 31, its boss levels 28, 29 and 31 are unverified.
--
-- Recorded divergences: none from a source guide, since there is none.
--
-- Maps: 1437 Wetlands (guide default), 1454 Orgrimmar, 1417 Arathi Highlands,
-- 1456 Thunder Bluff, 1412 Mulgore.
--
-- Conversion notes:
--   * Guide `only = "Horde"` became the wrapper's cond = { faction = "Horde" }; meta
--     levels { 24, 30 } became levels = { from = 24, to = 30 }.
--   * Every step-level `only` was a quest-state predicate, which the format drops:
--       - "quest N readyToTurnIn" on the 95663, 95682, 95697 and 95664/98823 hand-ins and
--         the 98823 turn-in became optional = true (passed on arrival unless ready).
--       - "quest 95682" / "quest 95697" on the four objective steps: dropped. Without the
--         quest the step stops for the player to skip (the format's default).
--       - "not quest 95664 finished" on the Titan Relic collect: dropped; the collect has
--         starts = 95664, so it is done once 95664 was ever taken.
--       - "now item 270866" on the relic accept: dropped (a `now` gate); an accept from an
--         item passes when the item is not in the bags.
--   * The relic is kept as two steps (collect with starts, then accept with item), as in
--     the source, rather than merged into one accept with kill.
--   * Objective numbers are the source's `part` values; none was inferred. kill
--     `count = 2` / `count = 4` and collect `count = 4` dropped: the objective counts.
--     The four objective steps keep `sticky = true`.
--   * No track/untrack pairs, no `with`, no labels needed.
--   * Turn-in 95664 plus accept 98823 at Bashana became a `talk` (turnin + accept),
--     optional.
--   * Travel `zone = "Excavation Site: Wetlands"` was a name; the dungeon's instance ID
--     (GetInstanceInfo) is not in the repo, so the step carries no zone/instance and
--     finishes on arrival at the portal point (4780, 5630). AreaTable 16732 is the
--     instance's area, but `area` is compared with the subzone text, which inside is not
--     known, so it is left out too. Travel out: zone = 1437 (Wetlands).
--   * Step notes that only placed an NPC moved to the NPC's note: Borstan ("the meat
--     vendor in the Drag"), the Deathstalker Agent ("in the hills above the Dragonmaw
--     camp"), Bashana Runetotem (Elder Rise), Muln Earthfury (Skywatcher Plateau), Zaruk
--     (Hammerfall; the rest of that step's note stays on the step).
--   * The travel to the hills above the Dragonmaw camp keeps its own `at`, which is the
--     same spot as the Agent's.
--   * Kill targets inside the dungeon (Relic Guardian, Dragonmaw Warder and Saboteur) are
--     listed under 1437, the map of the entrance, by name only, without `instance` (ID
--     unknown) and without positions. Saltspine (260322) and Shadetooth (260325) are only
--     named in a note in the source and are not listed.
--   * Sections Orgrimmar (1454) and Hammerfall (1417) keep their maps; the others need
--     none (their points are on the Wetlands, and the turn-in NPCs carry their own maps).
--   * Quest and item names (`names.quests`, `names.items`) dropped: the client names them.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:dungeon:horde-excavation-site-quests",
    updated = 1790985600,
    title = "Excavation Site: Wetlands",
    category = "Dungeons/Excavation Site",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "excavation site", "wetlands", "whelgar", "titan", "forever" },
    levels = { from = 24, to = 30 },
    cond = { faction = "Horde" },
    source = "Written from WoW: Forever client data and Wowhead's Forever database; no recorded run yet.",

    data = {
        map = 1437,

        sections = {
            { title = "Orgrimmar", map = 1454, steps = {
                { type = "note", note = "Excavation Site: Wetlands is new in WoW: Forever and no run of it is recorded yet: the inside of the dungeon, where its fights are, and the boss order are not in this guide." },
                { type = "accept", quests = { 95697 }, npc = { 3368 } },
            } },

            { title = "Hammerfall", map = 1417, steps = {
                { type = "accept", quests = { 95663 }, npc = { 2787 },
                  note = "Dragonmaw Rumors sends you to the Deathstalker Agent in the Wetlands, who gives Open the Maw. Whether he offers it without this quest is not recorded; press > to pass it over if you are not coming this way." },
            } },

            { title = "The Wetlands", steps = {
                { type = "travel", to = "the hills above the Dragonmaw camp", at = { { 5140, 5920 } },
                  note = "From Hammerfall, ride south over the Thandol Span into the Wetlands." },
                { type = "turnin", quests = { 95663 }, npc = { 13155 }, optional = true },
                { type = "accept", quests = { 95682 }, npc = { 13155 } },
                { type = "travel", to = "Excavation Site: Wetlands", at = { { 4780, 5630 } },
                  note = "A blue mist portal under a large tree, in the hills southeast of Whelgar's Excavation, reached from Thelgen Rock. Step through with your group." },
            } },

            { title = "Inside the excavation site", steps = {
                { type = "kill", kill = { 275045 }, quest = { 95682, 1 }, sticky = true,
                  note = "Dragonmaw Saboteurs. Where they stand inside is not recorded yet." },
                { type = "kill", kill = { 275044 }, quest = { 95682, 2 }, sticky = true,
                  note = "Dragonmaw Warders." },
                { type = "collect", item = 284844, quest = { 95682, 3 }, sticky = true,
                  note = "One of the Dragonmaw inside carries it; which one is not recorded yet." },
                { type = "collect", item = 271100, quest = { 95697, 1 }, sticky = true,
                  note = "The Thicket raptors of Stalker's Thicket, the part of the dig site Shadetooth leads." },
                { type = "note", note = "Three bosses: Saltspine, a white crocolisk; Shadetooth, the giant violet raptor of Stalker's Thicket; and the Relic Guardian, a stone Titan construct, last." },
                { type = "collect", item = 270866, starts = 95664, kill = { 260326 },
                  note = "The Relic Guardian, the last boss. If no relic comes to you, press > to pass it and its quest over." },
                { type = "accept", quests = { 95664 }, item = 270866, note = "Use the Titan Relic to start its quest." },
                { type = "travel", to = "the way out", zone = 1437, at = { { 4780, 5630 } },
                  note = "Leave through the portal." },
            } },

            { title = "Turning in", steps = {
                { type = "turnin", quests = { 95682 }, npc = { 13155 }, optional = true,
                  note = "Back to the Deathstalker Agent with the Dispatch." },
                { type = "turnin", quests = { 95697 }, npc = { 3368 }, optional = true },
                { type = "talk", turnin = { 95664 }, accept = { 98823 }, npc = { 9087 }, optional = true },
                { type = "turnin", quests = { 98823 }, npc = { 259118 }, optional = true },
                { type = "finish", note = "Every Horde quest of Excavation Site: Wetlands is done or left for another run." },
            } },
        },

        npcs = {
            [1454] = { -- Orgrimmar
                [3368] = { name = "Borstan", at = { 5740, 5340 }, note = "The meat vendor in the Drag." },
            },
            [1417] = { -- Arathi Highlands
                [2787] = { name = "Zaruk", at = { 7440, 3540 }, note = "In Hammerfall." },
            },
            [1437] = { -- Wetlands
                [13155] = { name = "Deathstalker Agent", at = { 5140, 5920 },
                            note = "In the hills above the Dragonmaw camp." },
                -- Inside Excavation Site: Wetlands, whose entrance is on this map. The instance ID
                -- is not in the repo, so they carry no `instance`.
                [260326] = "Relic Guardian",
                [275044] = "Dragonmaw Warder",
                [275045] = "Dragonmaw Saboteur",
            },
            [1456] = { -- Thunder Bluff
                [9087] = { name = "Bashana Runetotem", at = { 7080, 3340 }, note = "On the Elder Rise." },
            },
            [1412] = { -- Mulgore
                [259118] = { name = "Muln Earthfury", at = { 3340, 2240 },
                             note = "On Skywatcher Plateau, northwest Mulgore." },
            },
        },
    },
})
