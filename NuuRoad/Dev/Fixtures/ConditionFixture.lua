local _, ns = ...

-- Fixture for step conditions: one step per thing a guide's `cond` and
-- `show` can say. Open it on any character and the tracker should show only
-- the steps that character meets; the ones it does not are painted amber on
-- the progress bar and passed over by BACK and SKIP. A step whose condition
-- this client cannot answer (season on a client with no season API, a realm
-- answer not given in Options) stays visible, because unknown counts as met.
--
-- The editor's "Shown when" tab must round-trip every line below: open a
-- step, read the condition back as the same text, save, and reopen unchanged.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:conditions", updated = 1789862400,
    title = "Fixture: Conditions", category = "Fixtures/Conditions", author = "NuuRoad",
    tags = { "fixture", "condition", "predicate" },
    data = {
        map = 1412,
        conds = {
            noAH = { any = { { selffound = true }, { none = { { ah = true } } } } },
        },
        sections = {
            { title = "Who the character is", steps = {
                { type = "note", note = "Shown to every character. The steps below are gated one condition at a time." },
                { type = "note", note = "Horde only.", cond = { faction = "Horde" } },
                { type = "note", note = "Warriors and shamans only.", cond = { class = { "WARRIOR", "SHAMAN" } } },
                { type = "note", note = "Not Tauren.", cond = { none = { { race = "tauren" } } } },
                { type = "note", note = "Neither Warrior nor Druid.", cond = { none = { { class = "WARRIOR" }, { class = "DRUID" } } } },
                { type = "note", note = "An Alliance Mage or Druid: every key must hold.", cond = { faction = "Alliance", class = { "MAGE", "DRUID" } } },
                { type = "note", note = "A Troll or an Orc Warrior: `any` of two conditions.", cond = { any = { { race = "troll" }, { race = "orc", class = "WARRIOR" } } } },
            } },
            { title = "The realm", steps = {
                { type = "note", note = "A hardcore character.", cond = { hardcore = true } },
                { type = "note", note = "Season of Discovery. Unknown, so shown, on a client with no season API.", cond = { season = 2 } },
                { type = "note", note = "Any season at all.", cond = { season = true } },
            } },
            { title = "What the character has chosen", steps = {
                { type = "note", note = "Knows Mining.", show = { skill = 186 } },
                { type = "note", note = "Knows Skinning or Mining.", show = { skill = { 393, 186 } } },
                { type = "note", note = "Uses the auction house (Options).", show = { ah = true } },
                { type = "note", note = "Plays self found (Options).", show = { selffound = true } },
                { type = "note", note = "Does not use the auction house: a named condition.", show = { is = "noAH" } },
                { type = "finish", note = "Condition fixture complete." },
            } },
        },
    },
})
