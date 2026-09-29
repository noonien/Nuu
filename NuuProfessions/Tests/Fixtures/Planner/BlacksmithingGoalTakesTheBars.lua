-- Tests/Fixtures/Planner/BlacksmithingGoalTakesTheBars.lua
-- From Tools/SessionLog/fuzz.lua --seed 22 --dump 16; `expect` is what was planned (edit it to what should be).
return {
    note = "Fuzz seed 22: only what is carried, 5 Copper Bars, a goal made now that takes 10. The goal's shortfall is told, not cut, but it left the grind after it with no bars at all: that run was never cut (its item was marked seen at the goal), and the plan asked for 120 crafts. Nothing is left to grind.",
    bags = {
        { 2318, 4 },
        { 2840, 5 },
        { 2842, 24 },
        { 3470, 4 },
        { 3481, 3 },
        { 3489, 8 },
        { 5500, 3 },
        { 251355, 14 },
        { 277017, 3 },
    },
    book = {
        merchants = {},
        prices = {
            [10938] = {
                auctionBuy = { source = "player", value = 5000 },
            },
        },
        revision = 1,
        trainers = {},
    },
    expect = "",
    helpers = {
        Mining = { 2657, 3308 },
    },
    inputs = {
        accepted = {},
        avoided = {},
        chosen = {
            { fromSkill = 112, spell = 7408, toSkill = 114 },
        },
        goals = {
            { count = 1, skill = 134, spell = 3294, when = "now" },
        },
        options = {
            confidence = "safe",
            gather = {},
            get = {},
            keep = {},
            materials = "carried",
            nosell = {},
            sell = {},
        },
        pinned = {},
        preferred = {},
        refused = { [7408] = true },
        target = 136,
    },
    known = { 2660, 2661, 2662, 2663, 2664, 2665, 2666, 2668, 2670, 2674, 2737, 2738, 2739, 2741, 3115, 3116, 3293, 3294, 3319, 3320, 3323, 3324, 3326, 3328, 3330, 3337, 6518, 7408, 7817, 7818, 9983, 12260, 19666, 1230171, 1245287, 1252236, 1252240, 1252244, 1252248, 1252263, 1252266, 1252271, 1252277, 1252279, 1301446 },
    level = 6,
    maxSkill = 150,
    profession = "Blacksmithing",
    skill = 114,
}
