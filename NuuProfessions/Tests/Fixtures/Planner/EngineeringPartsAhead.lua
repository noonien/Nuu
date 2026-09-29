-- Tests/Fixtures/Planner/EngineeringPartsAhead.lua
-- From Tools/SessionLog/fuzz.lua --seed 78 --dump 4; `expect` is what was planned (edit it to what should be).
return {
    playthrough = "sample",
    note = "Fuzz seed 78: Engineering 191, buying. The parts made for the grind give 3 skills (191 to 194). A part after the last one giving skill got a share of -1, and the parts were listed from the low-end ledger while their skill came from the route's: a make step landed at 190, behind the skill, where the Make button counts it done, and the grind came up 44 parts short.",
    bags = {
        { 1206, 12 },
        { 2319, 82 },
        { 2589, 6 },
        { 2592, 392 },
        { 2838, 208 },
        { 2840, 9 },
        { 2841, 380 },
        { 2880, 6 },
        { 4375, 8 },
        { 4382, 22 },
    },
    book = {
        merchants = {},
        prices = {
            [4234] = {
                auctionBuy = { source = "player", value = 5000 },
            },
        },
        revision = 1,
        trainers = {
            [99999] = {
                [3923] = { cost = 10, skill = 35, profession = "Engineering", spellID = 3923 },
                [3956] = { cost = 1000, skill = 156, profession = "Engineering", spellID = 3956 },
            },
        },
    },
    expect = "3955:194-200 x100",
    helpers = {},
    inputs = {
        accepted = {},
        avoided = {},
        chosen = {},
        goals = {
            { count = 3, skill = 189, spell = 6458, when = "end" },
        },
        options = {
            gather = {},
            get = {},
            keep = {},
            materials = "buy",
            nosell = {},
            recipes = "trainer",
            sections = "band",
            sell = {},
        },
        pinned = {},
        preferred = {},
        refused = {},
    },
    known = { 3918, 3919, 3920, 3922, 3923, 3924, 3925, 3926, 3930, 3931, 3932, 3933, 3934, 3936, 3937, 3938, 3942, 3945, 3947, 3949, 3950, 3953, 3955, 3956, 3977, 6458, 7430, 8334, 9271, 12584, 23067, 26420, 26421, 1230656, 1266905, 1266907, 1319155, 1319157 },
    level = 12,
    maxSkill = 225,
    profession = "Engineering",
    skill = 191,
}
