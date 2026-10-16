-- A packaged guide: a guide source (docs/examples/guide-source.lua).
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
local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",

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
