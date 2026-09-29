-- Tests/Fixtures/Planner/EngineeringGoalCountIsCrafts.lua
-- From Tools/SessionLog/fuzz.lua --seed 908 --dump 25; `expect` is what was planned (edit it to what should be).
return {
    note = "Fuzz seed 908: Engineering 75, only what is carried, a goal of 3 of a recipe making 1-3 a craft. A goal's count is crafts (GoalMade counts them off so) and the planner reserved 3 crafts' materials, but the Make button ordered crafts for 3 items (2): the last step, sized to all the bags make, left a craft of its own in the bags.",
    playthrough = "sample",
    bags = {
        { 774, 2 },
        { 2319, 47 },
        { 2570, 1 },
        { 2589, 31 },
        { 2592, 12 },
        { 2770, 40 },
        { 2836, 97 },
        { 2838, 7 },
        { 2840, 1 },
        { 2842, 21 },
        { 2880, 6 },
        { 3576, 4 },
        { 4357, 29 },
        { 4358, 22 },
        { 4359, 2 },
        { 4360, 40 },
        { 4409, 9 },
        { 249410, 8 },
        { 260784, 2 },
        { 260793, 4 },
    },
    book = {
        merchants = {},
        prices = {
            [2770] = {
                auctionBuy = { source = "player", value = 800 },
            },
            [2840] = {
                auctionBuy = { source = "player", value = 5000 },
            },
            [3576] = {
                auctionBuy = { source = "player", value = 800 },
            },
        },
        revision = 3,
        trainers = {},
    },
    expect = "3923:75-80 x11  3924:80-84 x4  3928:84-85 x1  3929:85-90 x6  3931:95-100 x9  8339:105-110 x5  3973:110-125 x21  3945:125-128 x7  26416:128-147 x46",
    helpers = {
        Mining = { 2657, 2659, 1230161 },
    },
    inputs = {
        accepted = {},
        avoided = {},
        chosen = {},
        goals = {
            { count = 3, skill = 4, spell = 8339, when = "skill" },
        },
        options = {
            confidence = "typical",
            gather = {},
            get = {},
            keep = {},
            materials = "carried",
            nosell = {},
            sell = {},
        },
        pinned = {},
        preferred = {},
        refused = {},
    },
    known = { 3918, 3919, 3920, 3952, 8339, 9269, 26416, 26417, 26418, 26421, 1317959, 1319159, 3922, 1266893, 1266906, 3923 },
    level = 11,
    maxSkill = 75,
    profession = "Engineering",
    skill = 75,
}
