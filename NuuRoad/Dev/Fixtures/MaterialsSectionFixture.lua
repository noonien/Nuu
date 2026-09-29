local _, ns = ...

-- Fixture for a materials list kept to one section at a time
-- (`meta.materials = "section"`), the shape of a profession route the
-- planner splits by recipe: each section buys its own materials, then makes
-- the thing. Walking it, the list beside the tracker shows only the stones
-- in the first section and only the linen in the second, and its title
-- names the section.
--
-- Blacksmithing and Tailoring starter recipes; any character can read it,
-- and the gather steps finish on the items however they arrive.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:materials-by-section"] = {
    schema = 2, id = "nuuroad:fixture:materials-by-section", updated = 1789862400, map = 1413,
    meta = {
        title = "Fixture: Materials by Section", author = "NuuRoad", category = "Fixtures/Professions",
        tags = { "fixture", "profession" }, materials = "section",
    },
    steps = {
        { section = "Rough Sharpening Stone 1-10", steps = {
            { gather = 2835, count = 10, note = "Only the stones are on the materials list here: the linen belongs to the next section." },
            { craft = 2862, count = 10, skill = "Blacksmithing", needs = { { 2835, 10 } },
                note = "The list shows 10 Rough Stone and nothing else." },
        } },
        { section = "Bolt of Linen Cloth 10-20", steps = {
            { gather = 2589, count = 20, note = "Now the list has moved on: Linen Cloth only, and its title names this section." },
            { craft = 2996, count = 10, skill = "Tailoring", needs = { { 2589, 20 } },
                note = "The list shows 20 Linen Cloth." },
            { finish = "Materials-by-section fixture complete." },
        } },
    },
}
