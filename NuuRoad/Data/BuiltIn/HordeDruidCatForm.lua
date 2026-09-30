local _, ns = ...

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
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1456 Thunder Bluff, 1450 Moonglade.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:class:horde-druid-cat-form"] = {
    schema = 2,
    id = "nuuroad:class:horde-druid-cat-form",
    updated = 1790208000,
    map = 1450,
    only = "Druid | not Alliance",
    meta = {
        title = "Druid: Cat Form",
        author = "NuuRoad",
        category = "Class quests/Druid",
        tags = { "horde", "druid", "cat form", "moonglade", "class quest" },
        levels = { 20, 20 },
        source = "Recorded in play on WoW: Forever (2026-09-24), completed from Wowhead's Forever database.",
    },
    steps = {
        { section = "Thunder Bluff", map = 1456, steps = {
            { accept = 98340, npc = 3033, at = { 76.59, 27.46 },
                note = "Turak Runetotem offers it at level 20. He is on the Elder Rise." },
        } },

        { section = "Moonglade", steps = {
            { travel = "Moonglade", zone = "Moonglade", at = { 56.22, 30.51 },
                note = "Cast Teleport: Moonglade." },
            { turnin = 98340, accept = 98405, npc = 11802, at = { 56.22, 30.51 },
                note = "Dendrite Starblaze stands by the road in Nighthaven." },
            { turnin = 98405, accept = 98342, npc = 11957, at = { { 58.60, 73.50 }, { 54.50, 75.00 } },
                note = "The Great Cat Spirit is on the hill over the bridge in southern Moonglade." },
            { group = {
                { objective = 98342, part = 1, collect = 280502 },
                { objective = 98342, part = 2, collect = 280679 },
                { objective = 98342, part = 3, collect = 280680,
                    note = "All three relics are in the Stormrage Barrow Dens, just east of the Great Cat Spirit." },
            } },
            { turnin = 98342, accept = 98739, npc = 11957, at = { { 58.60, 73.50 }, { 54.50, 75.00 } } },
            { turnin = 98739, accept = 98362, npc = 11802, at = { 56.22, 30.51 } },
            { travel = "Thunder Bluff", zone = "Thunder Bluff", at = { 44.29, 45.87 },
                note = "Hearth if it is up, otherwise take Bunthen Plainswind's flight from Nighthaven." },
            { turnin = 98362, npc = 3033, at = { 76.59, 27.46, map = 1456 },
                note = "Turak Runetotem is on the Elder Rise. The quest teaches Cat Form." },
            { finish = "You have Cat Form." },
        } },
    },
}
