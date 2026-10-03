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
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:professions"] = {
    schema = 2, id = "nuuroad:fixture:professions", updated = 1789862400, map = 1413, only = "Horde",
    meta = {
        title = "Fixture: Professions and Circuits", author = "NuuRoad", category = "Fixtures/Professions",
        tags = { "fixture", "profession", "reputation", "gold", "horde" },
    },
    steps = {
        { section = "Training", map = 1454, steps = {
            { travel = "Orgrimmar", at = { 49.5, 68.5 }, note = "The mining trainer is in the Valley of Honor. The rest of the fixture is in the Barrens." },
            { train = "Mining", npc = 3357, note = "Turns green as soon as the client reports any rank in Mining." },
            { train = "Mining", rank = 75, npc = 3357, note = "The same trainer for Journeyman; this one waits for rank 75." },
            { buy = 2901, count = 1, npc = 3357, note = "The NPC names the vendor, so the step reads 'from Makaru' and his row appears in the step NPC panel." },
            { cast = 2580, note = "A cast step: cast Find Minerals, now that Mining is trained. It counts casts made while the guide is on the step, so one cast before reaching it does not." },
            { learn = { 6673 }, npc = 3353, only = "Warrior",
                note = "Class spells from a trainer, by spell ID: goes green once the client knows Battle Shout, trained from level 1; already green for a Warrior who has it. Grezz Ragefist trains Warriors in the Valley of Honor." },
        } },

        { section = "Skill and crafting", steps = {
            { skill = "Mining", rank = 65, note = "A skill target: the goal line shows the live rank against the target." },
            { craft = 2862, count = 5, skill = "Blacksmithing", needs = { { 2835, 5 }, { 2320, 2, "vendor" }, { 2589, 2, "ah" } },
                note = "Crafting for the items: five sharpening stones, counted from the client's 'You create:' message, and done outright once five are in the bags. Its three materials show the three sources: gathered, vendor, auction house." },
            { craft = 2862, count = 5, skill = "Blacksmithing", upto = 65, needs = { { 2835, 5 } },
                note = "A second batch, with the rank escape: 5 more stones OR Blacksmithing 65, whichever comes first. Past the rank the batch is not wanted at all, so the step finishes however few were made. The goal line says so rather than hiding it." },
            { skillup = 2862, skill = "Blacksmithing", rank = 65, needs = { { 2835, 20 } },
                note = "Crafting for the skill: keep making them until the rank lands, however many that takes. It goes green on the rank, not on a count, so a run of skill-ups finishes it early. Its materials are an author's estimate like any other." },
            { equip = 2901, note = "Worn gear is not in the bags, so this reads the equipment slots." },
        } },

        { section = "Reputation", steps = {
            { reputation = 76, standing = "Friendly", note = "Orgrimmar standing. Every Horde character starts here, so this fixture step should already be green." },
            { reputation = 470, standing = "Honored", note = "Ratchet. Outstanding on a fresh character." },
        } },

        { section = "Farming circuit", steps = {
            { travel = "The Crossroads", at = { 51.5, 30.3 } },
            -- The lap begins here. The choice below names this label, so the
            -- circuit needs no step positions at all.
            { travel = "Copper vein, north road", label = "circuit", at = { { 48.9, 25.4 }, { 50.1, 22.8 }, { 46.7, 27.9 } } },
            { gather = 2770, count = 20, skill = "Mining", upto = 65,
                note = "A gather step completes on the item however it arrives, so buying the ore at the auction house finishes it too, and Mining 65 finishes it with no ore at all. The pins show the other veins on the loop." },
            { travel = "Copper vein, south of the Crossroads", at = { { 52.7, 39.6 }, { 55.2, 42.1 } } },
            { choice = "Another lap around the veins?", options = {
                { "Run the circuit again", goto = "circuit" },
                { "Done farming", goto = "finish" },
            } },
            { finish = "Profession fixture complete.", label = "finish" },
        } },
    },
    names = {
        npcs = {
            [3353] = "Grezz Ragefist",
            [3357] = { "Makaru", at = { 73.12, 26.08, map = 1454 } },
        },
        items = {
            [2320] = "Coarse Thread",
            [2589] = "Linen Cloth",
            [2770] = "Copper Ore",
            [2835] = "Rough Stone",
            [2862] = "Rough Sharpening Stone",
            [2901] = "Mining Pick",
        },
        factions = {
            [76] = "Orgrimmar",
            [470] = "Ratchet",
        },
        spells = {
            [2580] = "Find Minerals",
            [6673] = "Battle Shout",
        },
    },
}
