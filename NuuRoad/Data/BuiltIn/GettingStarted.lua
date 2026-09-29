local _, ns = ...

ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:getting-started"] = {
    schema = 2,
    id = "nuuroad:getting-started",
    updated = 1789862400,
    meta = {
        title = "NuuRoad: First Steps",
        author = "NuuRoad",
        category = "Getting started",
        tags = { "example", "alliance", "horde" },
        levels = { 1, 60 },
    },
    steps = {
        { section = "Welcome", steps = {
            { note = "NuuRoad is ready. Steps complete on their own as you play; SKIP and BACK move you around by hand." },
            -- A branch names a label, never a step position. Both of these go
            -- to the same place: the point here is the buttons, not the route.
            { choice = "Choose your pace", options = {
                { "Continue", goto = "finish" },
                { "Finish later", goto = "finish" },
            }, note = "This example makes no game-state decisions for you." },
            { finish = "Example complete. You can reset this guide at any time.", label = "finish" },
        } },
    },
}
