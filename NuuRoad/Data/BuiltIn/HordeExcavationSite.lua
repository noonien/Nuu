local _, ns = ...

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
--   * The zone text inside ("Excavation Site: Wetlands") that completes the entrance step,
--     and that "Wetlands" comes back on leaving although the subzone outside carries the
--     dungeon's name.
--   * The order of the three Open the Maw objective lines (parts 1 to 3 below follow
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
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1437 Wetlands (guide default), 1454 Orgrimmar, 1417 Arathi Highlands,
-- 1456 Thunder Bluff, 1412 Mulgore.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:dungeon:horde-excavation-site-quests"] = {
    schema = 2,
    id = "nuuroad:dungeon:horde-excavation-site-quests",
    updated = 1790985600,
    map = 1437,
    only = "Horde",
    meta = {
        title = "Excavation Site: Wetlands",
        author = "NuuRoad",
        category = "Dungeons/Excavation Site",
        tags = { "horde", "dungeon", "excavation site", "wetlands", "whelgar", "titan", "forever" },
        levels = { 24, 30 },
        source = "Written from WoW: Forever client data and Wowhead's Forever database; no recorded run yet.",
    },
    steps = {
        { section = "Orgrimmar", map = 1454, steps = {
            { note = "Excavation Site: Wetlands is new in WoW: Forever and no run of it is recorded yet: the inside of the dungeon, where its fights are, and the boss order are not in this guide." },
            { accept = 95697, npc = 3368, at = { 57.40, 53.40 }, note = "Borstan, the meat vendor in the Drag." },
        } },

        { section = "Hammerfall", map = 1417, steps = {
            { accept = 95663, npc = 2787, at = { 74.40, 35.40 },
                note = "Zaruk in Hammerfall. Dragonmaw Rumors sends you to the Deathstalker Agent in the Wetlands, who gives Open the Maw. Whether he offers it without this quest is not recorded; press > to pass it over if you are not coming this way." },
        } },

        { section = "The Wetlands", steps = {
            { travel = "the hills above the Dragonmaw camp", at = { 51.40, 59.20 },
                note = "From Hammerfall, ride south over the Thandol Span into the Wetlands." },
            { turnin = 95663, npc = 13155, only = "quest 95663 readyToTurnIn", at = { 51.40, 59.20 },
                note = "The Deathstalker Agent, in the hills above the Dragonmaw camp." },
            { accept = 95682, npc = 13155, at = { 51.40, 59.20 } },
            { travel = "Excavation Site: Wetlands", zone = "Excavation Site: Wetlands", at = { 47.80, 56.30 },
                note = "A blue mist portal under a large tree, in the hills southeast of Whelgar's Excavation, reached from Thelgen Rock. Step through with your group." },
        } },

        { section = "Inside the excavation site", steps = {
            { objective = 95682, part = 1, kill = 275045, count = 2, sticky = true, only = "quest 95682",
                note = "Dragonmaw Saboteurs. Where they stand inside is not recorded yet." },
            { objective = 95682, part = 2, kill = 275044, count = 4, sticky = true, only = "quest 95682",
                note = "Dragonmaw Warders." },
            { objective = 95682, part = 3, collect = 284844, sticky = true, only = "quest 95682",
                note = "One of the Dragonmaw inside carries it; which one is not recorded yet." },
            { objective = 95697, part = 1, collect = 271100, count = 4, sticky = true, only = "quest 95697",
                note = "The Thicket raptors of Stalker's Thicket, the part of the dig site Shadetooth leads." },
            { note = "Three bosses: Saltspine, a white crocolisk; Shadetooth, the giant violet raptor of Stalker's Thicket; and the Relic Guardian, a stone Titan construct, last." },
            { collect = 270866, starts = 95664, kill = 260326, only = "not quest 95664 finished",
                note = "The Relic Guardian, the last boss. If no relic comes to you, press > to pass it and its quest over." },
            { accept = 95664, only = "now item 270866", note = "Use the Titan Relic to start its quest." },
            { travel = "the way out", zone = "Wetlands", at = { 47.80, 56.30 },
                note = "Leave through the portal." },
        } },

        { section = "Turning in", steps = {
            { turnin = 95682, npc = 13155, only = "quest 95682 readyToTurnIn", at = { 51.40, 59.20 },
                note = "Back to the Deathstalker Agent with the Dispatch." },
            { turnin = 95697, npc = 3368, only = "quest 95697 readyToTurnIn", at = { 57.40, 53.40, map = 1454 },
                note = "Borstan in the Drag, Orgrimmar." },
            { turnin = 95664, accept = 98823, npc = 9087, only = "quest 95664 readyToTurnIn", at = { 70.80, 33.40, map = 1456 },
                note = "Bashana Runetotem on the Elder Rise, Thunder Bluff." },
            { turnin = 98823, npc = 259118, only = "quest 98823 readyToTurnIn", at = { 33.40, 22.40, map = 1412 },
                note = "Muln Earthfury on Skywatcher Plateau, northwest Mulgore." },
            { finish = "Every Horde quest of Excavation Site: Wetlands is done or left for another run." },
        } },
    },
}
