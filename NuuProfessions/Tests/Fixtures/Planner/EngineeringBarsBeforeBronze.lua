-- Tests/Fixtures/Planner/EngineeringBarsBeforeBronze.lua
-- From Tools/SessionLog/fuzz.lua --seed 548 --dump 1; `expect` is what was planned (edit it to what should be).
return {
    note = "Fuzz seed 548: Engineering 133, buying. Bronze was first needed while the bags held copper bars; more bronze later needed bars smelted, and the smelting was listed after the bronze it goes into, so the Make button started on bronze 17 bars short. Parts now come before what is made of them.",
    playthrough = "sample",
    bags = {
        { 818, 4 },
        { 2592, 12 },
        { 2840, 8 },
        { 2841, 2 },
        { 4364, 6 },
        { 4382, 4 },
    },
    book = {
        merchants = {},
        prices = {
            [2838] = {
                auctionBuy = { source = "player", value = 120 },
            },
            [4402] = {
                auctionBuy = { source = "player", value = 120 },
            },
        },
        revision = 2,
        trainers = {},
    },
    expect = "3942:133-135 x3  424641:143-144 x10  3942:144-150 x13",
    helpers = {
        Mining = { 2657, 2658, 2659, 3308 },
    },
    inputs = {
        accepted = {},
        avoided = {},
        chosen = {},
        goals = {
            { count = 1, skill = 147, spell = 3973, when = "end" },
        },
        options = {
            confidence = "safe",
            gather = {},
            get = {},
            keep = {},
            materials = "buy",
            nosell = {},
            optimize = "profit",
            sell = {},
        },
        pinned = {},
        preferred = { [4382] = true },
        refused = {},
    },
    known = { 3918, 3919, 3920, 3922, 3924, 3925, 3926, 3929, 3930, 3931, 3932, 3934, 3936, 3937, 3938, 3941, 3942, 3945, 3947, 3973, 3977, 3978, 7430, 8334, 9269, 23067, 1266905, 1266908 },
    level = 12,
    maxSkill = 150,
    profession = "Engineering",
    skill = 133,
}
