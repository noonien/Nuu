local _, ns = ...

-- Fixture for a materials list kept to one section at a time
-- (`materials = "section"`), the shape of a profession route the planner
-- splits by recipe: each section buys its own materials, then makes the
-- thing. Walking it, the list beside the tracker shows only the stones in the
-- first section and only the linen in the second, and its title names the
-- section.
--
-- Blacksmithing and Tailoring starter recipes; any character can read it,
-- and the gather steps finish on the items however they arrive.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:materials-by-section", updated = 1789862400,
    title = "Fixture: Materials by Section", category = "Fixtures/Professions", author = "NuuRoad",
    tags = { "fixture", "profession" }, materials = "section",
    data = {
        map = 1413,
        sections = {
            { title = "Rough Sharpening Stone 1-10", steps = {
                { type = "gather", item = 2835, count = 10,
                  note = "Only the stones are on the materials list here: the linen belongs to the next section." },
                { type = "craft", item = 2862, count = 10, skill = 164, needs = { { item = 2835, count = 10 } },
                  note = "The list shows 10 Rough Stone and nothing else." },
            } },
            { title = "Bolt of Linen Cloth 10-20", steps = {
                { type = "gather", item = 2589, count = 20,
                  note = "Now the list has moved on: Linen Cloth only, and its title names this section." },
                { type = "craft", item = 2996, count = 10, skill = 197, needs = { { item = 2589, count = 20 } },
                  note = "The list shows 20 Linen Cloth." },
                { type = "finish", note = "Materials-by-section fixture complete." },
            } },
        },
    },
})
