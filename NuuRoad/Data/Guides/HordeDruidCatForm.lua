-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeDruidCatForm.lua.
--
-- The Horde Druid Cat Form quests, new in WoW: Forever. Classic taught Cat Form at the
-- trainer at level 20; Forever sends the Druid to the Great Cat Spirit in Moonglade, the
-- way the Great Bear Spirit teaches Bear Form, and To Thunder Bluff rewards Cat Form (768).
--
-- Sources:
--   * A recorded session (Archive/20260924/20260924-182053, a Tauren Druid reaching 20):
--     Turak Runetotem's accept of 98340 at Thunder Bluff 76.59, 27.46, its turn-in to
--     Dendrite Starblaze at Moonglade 56.22, 30.51, and her accept of 98405. The recording
--     ends there.
--   * Wowhead's Forever database (wowhead.com/forever, read 2026-09-24) for the rest: the
--     chain 98405 -> 98342 -> 98739 -> 98362, who starts and ends each, the three relic
--     items of 98342, the Cat Form reward, and the Great Cat Spirit's (11957) map spots
--     (58.4-58.8, 73.2-74.8 and 54.4-54.6, 75.0). Only facts are taken; no text.
--
-- Recorded divergences:
--   * The Great Windborne Cat Spirit (98341), to the Avatar of Saeyleenan, is left out. Its
--     text is for a Druid whose homeland spirit lives on Zephras, not a Tauren.
--
-- Still to check in the client:
--   * where in the Stormrage Barrow Dens the three relics are (Wowhead has no spots for
--     them), and that the objective lines run Fang, Claw, Silent Shadow as Wowhead lists;
--   * which of the Great Cat Spirit's two spots it actually stands at.
--
-- Maps: 1456 Thunder Bluff, 1450 Moonglade.
--
-- Conversion notes:
--   * Guide `only = "Druid | not Alliance"` -> wrapper cond { class = "DRUID",
--     none = { { faction = "Alliance" } } }. No `now` terms or condition-only gates in the source.
--   * Travel `zone` names became map IDs: "Moonglade" -> 1450, "Thunder Bluff" -> 1456
--     (from the guide's own map comment).
--   * The Thunder Bluff travel point 44.29, 45.87 is the Moonglade flight master, on the
--     Moonglade map (HordeBarrens and HordeMulgore612 give it map = 1450), so it has no map of
--     its own and falls to the guide's map 1450.
--   * The Moonglade travel keeps its `at` (Dendrite's spot) as the arrival point.
--   * turnin + accept on one NPC became `talk` steps.
--   * NPC notes moved onto the NPCs: Turak "He is on the Elder Rise.", Dendrite "stands by the
--     road in Nighthaven", the Great Cat Spirit "on the hill over the bridge in southern
--     Moonglade"; the steps keep only the rest of their notes. The two Great Cat Spirit steps
--     each gave the same two spots in their `at`; those became the NPC's `at` list and the steps
--     drop their `at`.
--   * Objective numbers for 98342 come from the source's `part` (1-3), not inferred; their order
--     is still to check in the client (see above).
--   * The relic collect steps have no `at` (none in the source); their shared note stays on the
--     third.
--   * The quest and item names in `names` are dropped: the client names them.
--   * No track/untrack, places, or sticky steps in the source.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:class:horde-druid-cat-form",
    updated = 1790208000,
    title = "Druid Cat Form",
    category = "Class quests/Druid",
    author = "NuuRoad",
    tags = { "horde", "druid", "cat form", "moonglade", "class quest" },
    levels = { from = 20, to = 20 },
    cond = { class = "DRUID", none = { { faction = "Alliance" } } },
    source = "Recorded in play on WoW: Forever (2026-09-24), completed from Wowhead's Forever database.",

    data = {
        map = 1450,

        sections = {
            { title = "Thunder Bluff", map = 1456, steps = {
                { type = "accept", quests = { 98340 }, npc = { 3033 },
                  note = "Turak Runetotem offers it at level 20." },
            } },

            { title = "Moonglade", steps = {
                { type = "travel", to = "Moonglade", zone = 1450, at = { { 5622, 3051 } },
                  note = "Cast Teleport: Moonglade." },
                { type = "talk", turnin = { 98340 }, accept = { 98405 }, npc = { 11802 } },
                { type = "talk", turnin = { 98405 }, accept = { 98342 }, npc = { 11957 } },
                { group = {
                    { type = "collect", item = 280502, quest = { 98342, 1 } },
                    { type = "collect", item = 280679, quest = { 98342, 2 } },
                    { type = "collect", item = 280680, quest = { 98342, 3 },
                      note = "All three relics are in the Stormrage Barrow Dens, just east of the Great Cat Spirit." },
                } },
                { type = "talk", turnin = { 98342 }, accept = { 98739 }, npc = { 11957 } },
                { type = "talk", turnin = { 98739 }, accept = { 98362 }, npc = { 11802 } },
                { type = "travel", to = "Thunder Bluff", zone = 1456, at = { { 4429, 4587 } },
                  note = "Hearth if it is up, otherwise take Bunthen Plainswind's flight from Nighthaven." },
                { type = "turnin", quests = { 98362 }, npc = { 3033 },
                  note = "The quest teaches Cat Form." },
                { type = "finish", note = "You have Cat Form." },
            } },
        },

        npcs = {
            [1456] = { -- Thunder Bluff
                [3033] = { name = "Turak Runetotem", at = { 7659, 2746 }, note = "He is on the Elder Rise." },
            },
            [1450] = { -- Moonglade
                [11802] = { name = "Dendrite Starblaze", at = { 5622, 3051 },
                            note = "Dendrite Starblaze stands by the road in Nighthaven." },
                [11957] = { name = "Great Cat Spirit", at = { { 5860, 7350 }, { 5450, 7500 } },
                            note = "The Great Cat Spirit is on the hill over the bridge in southern Moonglade." },
            },
        },
    },
})
