-- A packaged guide: a guide source (docs/examples/guide-source.lua).
--
-- The Horde quests of Ruins of Lordaeron, a dungeon new in WoW: Forever, from the
-- pickups in Brill, the Sepulcher, and the Undercity to the last turn-in. Everything
-- here comes from recorded sessions. The first (Archive/, 2026-09-23 and 2026-09-24)
-- are of a level 20 Undead priest who had four of the quests in the log, objectives
-- done, but never accepted or turned one in while recording:
--   * Quest IDs, titles, objectives, and who each quest is for come from the recorder's
--     quest log snapshots (rec/questlog, first in 20260923-181533.jsonl).
--   * Theodore Griffs (The New Plague, 95216) and the body of Othmar (Unending Torment,
--     97289) are placed by the client's own quest markers for the ready quests
--     (C_QuestLog.GetQuestsOnMap on the Undercity map, logged in the poi tables of every
--     session from 20260923-181533.lua to 20260924-024444.lua): 46.3, 71.9 and 45.9,
--     61.7. The client drew no marker for the other two on any map.
--   * The ruins are the subzone "Ruins of Lordaeron", which a place walk recorded at the
--     top of the Undercity map (placetrail, 20260923-211549 and -215649, outdoors).
--   * Where each fight happens is only what the quest text says: Rath'mael at the
--     Lordamere Overlook, Witherfang "stalking the ruins above our fair city", and Edward
--     Heartweaver last seen going to the graveyard in the ruins.
--   * The NPC IDs of Deathguard Kristof (251001) and Theodore Griffs (11835) come from
--     Wowhead's Forever database (wowhead.com/forever, read 2026-09-25), so the NPC panel
--     can list them even where their spot is unknown. Only the IDs are taken.
--   * Where the givers stand is where the player stood accepting from them (rec channel,
--     sessions 20260925-175441 to 20260927-161826, a level 15 Horde warrior who picked up
--     every quest but has not been into the ruins yet): Deathguard Kristof in Brill,
--     Tirisfal 65.2, 60.1; Tabitha Heartweaver (250686, A Frightened Request) in the
--     Sepulcher, Silverpine 44.5, 43.0; Morbin Lightbane (266484, Light's Justice) in the
--     Royal Quarter, Undercity 58.0, 89.8; Theodore Griffs, Undercity 46.5, 71.9.
--   * Light's Justice (92421) is a fifth quest for the ruins that the quest log files under
--     the Undercity: collect 25 Intact Limbs "within The Ruins of Lordaeron" for Morbin
--     Lightbane. A warrior could take it, so it is not held back for paladins.
--
-- Record in client (not in the evidence, so left out rather than guessed):
--   * The creature IDs of Rath'mael and Witherfang, and what drops the Intact Limbs.
--   * How Unending Torment (97289) starts: its text has an Apothecarium crafter hand over
--     the Head of the Baron, but no recording shows the pickup. The item IDs of the Head
--     of the Baron and the Highly Toxic Strain.
--   * The dungeon entrance within the ruins, the zone text inside, the boss order, and
--     the level range (a level 15 character could accept every quest; only a level 20
--     one is known to have finished their objectives).
--   * The AreaTable ID of the "Ruins of Lordaeron" subzone (see the conversion notes).
--
-- Recorded divergences: none from a source guide, since there is none. Turn-ins no
-- recording shows go back to the giver: Theodore Griffs for the sample, Morbin Lightbane
-- for the limbs (his quest text names him), Tabitha Heartweaver for news of her husband.
-- The discover channel logs it if the game hands a turn-in to someone else.
--
-- Maps: 1458 Undercity (guide default), 1420 Tirisfal Glades, 1421 Silverpine Forest.
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",

    id = "nuuroad:dungeon:horde-ruins-of-lordaeron-quests",
    updated = 1790467200,
    title = "Ruins of Lordaeron",
    category = "Dungeons/Ruins of Lordaeron",
    author = "NuuRoad",
    tags = { "horde", "dungeon", "ruins of lordaeron", "rol", "undercity", "brill", "tirisfal", "forever" },
    levels = { from = 20, to = 24 },
    cond = { faction = "Horde" },
    source = "Written from recorded WoW: Forever sessions: quest log snapshots and the client's own quest map markers.",

    data = {
        map = 1458,

        sections = {
            { title = "Brill", map = 1420, steps = {
                { type = "note", note = "Ruins of Lordaeron is new in WoW: Forever and this guide is still thin: the way into the dungeon and where its fights are is not recorded yet." },
                { type = "accept", quests = { 92422 }, npc = { 251001 } },
            } },

            { title = "The Sepulcher", map = 1421, steps = {
                { type = "accept", quests = { 92401 }, npc = { 250686 },
                  note = "Tabitha Heartweaver asks after her husband Edward." },
            } },

            { title = "The Undercity", steps = {
                { group = {
                    { type = "accept", quests = { 92421 }, npc = { 266484 },
                      note = "The quest log files it under the Undercity, but the limbs are collected in the ruins." },
                    { type = "accept", quests = { 95216 }, npc = { 11835 } },
                } },
            } },

            { title = "The ruins", steps = {
                { type = "travel", to = "the Ruins of Lordaeron", at = { { 6601, 1571 } },
                  note = "The ruins above the Undercity. The way into the dungeon is not recorded yet; the quests point deep into the ruins, to the Lordamere Overlook." },
                { group = {
                    { type = "kill", quest = { 92422, 1 },
                      note = "Rath'mael, a necromancer conjuring the fog at the Lordamere Overlook." },
                    { type = "collect", quest = { 95216, 1 },
                      note = "Witherfang, a venomous creature stalking the ruins, carries it." },
                    { type = "travel", to = "The graveyard in the ruins", quest = { 92401, 1 },
                      note = "Edward went to the graveyard in the ruins to look for his lost son." },
                    { type = "collect", quest = { 92421, 1 },
                      note = "25 Intact Limbs, collected in the ruins. What drops them is not recorded yet." },
                } },
            } },

            { title = "Turning in", steps = {
                { group = {
                    { type = "turnin", quests = { 95216 }, npc = { 11835 }, optional = true,
                      note = "Back down in the Apothecarium, to Theodore Griffs." },
                    { type = "turnin", quests = { 92421 }, npc = { 266484 }, optional = true },
                    { type = "turnin", quests = { 97289 }, object = "the body of Othmar", optional = true,
                      at = { { 4590, 6170 } },
                      note = "Set the Head of the Baron beside the body. Where the client marks the turn-in." },
                } },
                { type = "turnin", quests = { 92422 }, npc = { 251001 }, optional = true },
                { type = "turnin", quests = { 92401 }, npc = { 250686 }, optional = true,
                  note = "Back to Tabitha Heartweaver, with news of her husband." },
                { type = "finish", note = "Every Horde quest of Ruins of Lordaeron is done or left for another run." },
            } },
        },

        npcs = {
            [1458] = { -- Undercity
                [11835] = { name = "Theodore Griffs", at = { 4650, 7190 }, note = "In the Apothecarium." },
                [266484] = { name = "Morbin Lightbane", at = { 5800, 8980 }, note = "In the Royal Quarter." },
            },
            [1420] = { -- Tirisfal Glades
                [251001] = { name = "Deathguard Kristof", at = { 6520, 6010 }, note = "In Brill." },
            },
            [1421] = { -- Silverpine Forest
                [250686] = { name = "Tabitha Heartweaver", at = { 4450, 4300 }, note = "In the Sepulcher." },
            },
        },
    },
})
