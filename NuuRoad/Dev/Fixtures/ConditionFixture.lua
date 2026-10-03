local _, ns = ...

-- Fixture for step conditions: one step per predicate kind the `only` keywords
-- reach, plus the `when` expression fallback and the two combined. Open it on
-- any character and the tracker should show only the steps that character
-- meets; the ones it does not are painted amber on the progress bar and passed
-- over by BACK and SKIP. A step whose predicate this client cannot answer
-- (season on a client with no season API) stays visible, because unknown
-- counts as met.
--
-- The editor's SHOWN WHEN tab must round-trip every line below: open a step,
-- read the condition back as the same text, save, and reopen unchanged.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:conditions"] = {
    schema = 2, id = "nuuroad:fixture:conditions", updated = 1789862400, map = 1412,
    meta = { title = "Fixture: Conditions", author = "NuuRoad", category = "Fixtures/Conditions",
        tags = { "fixture", "condition", "predicate" } },
    steps = {
        { section = "Who the character is", steps = {
            { note = "Shown to every character. The steps below are gated one predicate at a time." },
            { note = "Horde only.", only = "Horde" },
            { note = "Warriors and shamans only.", only = "Warrior or Shaman" },
            { note = "Not Tauren.", only = "not Tauren" },
            { note = "Neither Warrior nor Druid: a bar joins two negated terms.", only = "not Warrior | not Druid" },
            { note = "A Mage at level 4 with a silver: a bar joins terms that must all hold.", only = "Mage | level 4 | gold 100" },
            { note = "An Alliance Mage or Druid: `or` inside a group, the bar between groups.", only = "Alliance | Mage or Druid" },
        } },

        { section = "What the character has done", steps = {
            { note = "Level 10 or above.", only = "level 10" },
            { note = "Chen's Empty Keg is in the log or finished.", only = "quest 819" },
            { note = "Chen's Empty Keg is finished, not merely accepted.", only = "quest 819 finished" },
            { note = "Mining at 75 or better.", only = "skill Mining 75" },
            { note = "Skinning at any rank at all.", only = "profession Skinning" },
            { note = "Friendly with Thunder Bluff or better.", only = "reputation 729 Friendly" },
        } },

        { section = "What the character is carrying", steps = {
            { note = "A Walking Stick is in the bags.", only = "item 2495" },
            { note = "A Walking Stick in the bags right now; without one the guide passes over this step rather than waiting.", only = "now item 2495" },
            { note = "Three or more Walking Sticks.", only = "item 2495 x3" },
            { note = "A Walking Stick is worn, which bag counts never see.", only = "equipped 2495" },
            { note = "Rockbiter Weapon is known.", only = "spell 8017" },
            { note = "Five silver or more, counted in copper.", only = "gold 500" },
        } },

        { section = "Where and when", steps = {
            { note = "Standing in Mulgore.", only = "zone 1412" },
            { note = "Inside an instance.", only = "instance" },
            { note = "A hardcore character.", only = "hardcore" },
            { note = "Season of Discovery. Unknown, so shown, on a client with no season API.", only = "season 2" },
        } },

        { section = "The Lua fallback", steps = {
            { note = "An expression, for what no keyword says: under level 10 and without a Walking Stick.",
                when = "level() < 10 and itemCount(2495) == 0" },
            { note = "A read with no helper of its own, through the api() allowlist.",
                when = "api('IsResting') == true" },
            { note = "Keywords and expression together: both must pass.",
                only = "Warrior", when = "money() > 100" },
            { finish = "Condition fixture complete." },
        } },
    },
    names = {
        quests = {
            [819] = "Chen's Empty Keg",
        },
        items = {
            [2495] = "Walking Stick",
        },
    },
}
