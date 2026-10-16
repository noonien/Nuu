local _, ns = ...

-- Fixture for the non-quest step types: training and skill ranks, class spells
-- learned and a spell cast, gathering,
-- crafting by the count and for the skill, a purchase from a named vendor,
-- worn gear, reputation standing, materials, and a farming circuit.
--
-- Mining and Blacksmithing on a Horde character: the training and the pick
-- are at Makaru in Orgrimmar, everything after that is the Barrens. IDs are
-- from the Classic creature and item tables; the in-client audit reports any
-- the server names differently.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:professions", updated = 1789862400,
    title = "Fixture: Professions and Circuits", category = "Fixtures/Professions", author = "NuuRoad",
    tags = { "fixture", "profession", "reputation", "gold", "horde" },
    cond = { faction = "Horde" },
    data = {
        map = 1413,
        sections = {
            { title = "Training", map = 1454, steps = {
                { type = "travel", to = "Orgrimmar", at = { { 4950, 6850 } },
                  note = "The mining trainer is in the Valley of Honor. The rest of the fixture is in the Barrens." },
                { type = "train", skill = 186, npc = { 3357 }, note = "Turns green as soon as the client reports any rank in Mining." },
                { type = "train", skill = 186, rank = 75, npc = { 3357 }, note = "The same trainer for Journeyman; this one waits for rank 75." },
                { type = "buy", item = 2901, count = 1, npc = { 3357 },
                  note = "The NPC names the vendor, so the step reads 'from Makaru' and his row appears in the step NPC panel." },
                { type = "cast", spell = 2580,
                  note = "A cast step: cast Find Minerals, now that Mining is trained. It counts casts made while the guide is on the step, so one cast before reaching it does not." },
                { type = "learn", spells = { 6673 }, npc = { 3353 }, cond = { class = "WARRIOR" },
                  note = "Class spells from a trainer, by spell ID: goes green once the client knows Battle Shout, trained from level 1; already green for a Warrior who has it. Grezz Ragefist trains Warriors in the Valley of Honor." },
            } },
            { title = "Skill and crafting", steps = {
                { type = "skill", skill = 186, rank = 65, note = "A skill target: the goal line shows the live rank against the target." },
                { type = "craft", item = 2862, count = 5, skill = 164,
                  needs = { { item = 2835, count = 5 }, { item = 2320, count = 2, source = "vendor" }, { item = 2589, count = 2, source = "ah" } },
                  note = "Crafting for the items: five sharpening stones, counted from the client's 'You create:' message, and done outright once five are in the bags. Its three materials show the three sources: gathered, vendor, auction house." },
                { type = "craft", item = 2862, count = 5, skill = 164, upto = { skill = 164, rank = 65 }, needs = { { item = 2835, count = 5 } },
                  note = "A second batch, with the rank escape: 5 more stones OR Blacksmithing 65, whichever comes first. Past the rank the batch is not wanted at all, so the step finishes however few were made. The goal line says so rather than hiding it." },
                { type = "skillup", item = 2862, skill = 164, rank = 65, needs = { { item = 2835, count = 20 } },
                  note = "Crafting for the skill: keep making them until the rank lands, however many that takes. It goes green on the rank, not on a count, so a run of skill-ups finishes it early. Its materials are an author's estimate like any other." },
                { type = "equip", item = 2901, note = "Worn gear is not in the bags, so this reads the equipment slots." },
            } },
            { title = "Reputation", steps = {
                { type = "reputation", faction = 76, standing = 5,
                  note = "Orgrimmar standing. Every Horde character starts here, so this fixture step should already be green." },
                { type = "reputation", faction = 470, standing = 6, note = "Ratchet. Outstanding on a fresh character." },
            } },
            { title = "Farming circuit", steps = {
                { type = "travel", to = "The Crossroads", at = { { 5150, 3030 } } },
                -- The lap begins here. The choice below names this label, so
                -- the circuit needs no step positions at all.
                { type = "travel", to = "Copper vein, north road", label = "circuit", at = { { 4890, 2540 }, { 5010, 2280 }, { 4670, 2790 } } },
                { type = "gather", item = 2770, count = 20, skill = 186, upto = { skill = 186, rank = 65 },
                  note = "A gather step completes on the item however it arrives, so buying the ore at the auction house finishes it too, and Mining 65 finishes it with no ore at all. The pins show the other veins on the loop." },
                { type = "travel", to = "Copper vein, south of the Crossroads", at = { { 5270, 3960 }, { 5520, 4210 } } },
                { type = "choice", text = "Another lap around the veins?", options = {
                    { text = "Run the circuit again", go = "circuit" },
                    { text = "Done farming", go = "finish" },
                } },
                { type = "finish", note = "Profession fixture complete.", label = "finish" },
            } },
        },
        npcs = {
            [1454] = {
                [3353] = "Grezz Ragefist",
                [3357] = { name = "Makaru", at = { 7312, 2608 } },
            },
        },
    },
})
