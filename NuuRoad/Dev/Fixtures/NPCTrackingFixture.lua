local _, ns = ...

-- Fixture for NPC tracking: a group of kill steps counted from the combat
-- log, each target with its own marker and each step its own count, and a
-- group of quest-giver steps the tracker shows as one step, whose quests can
-- be taken in any order and whose NPCs all get a star and a panel row at
-- once. Plainstriders and the quest givers are around the Crossroads.
ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    id = "nuuroad:fixture:npc-tracking", updated = 1789862400,
    title = "Fixture: NPC Tracking", category = "Fixtures/NPCs", author = "NuuRoad",
    tags = { "fixture", "npc", "kill", "horde" },
    cond = { faction = "Horde" },
    data = {
        map = 1413,
        sections = {
            { title = "NPC tracking", steps = {
                { type = "note", note = "Target or mouse over a plainstrider: it gets a skull (second kind a cross, third a square). Each kill you or your party land counts below." },
                { group = {
                    { type = "kill", kill = { 3244, 3245 }, count = 3, at = { { 4800, 1320 } }, radius = 600,
                      note = "Plainstriders northwest of the Crossroads. This step and the next show as one card, each with its own count. Hold Shift to keep a mark from being set." },
                    { type = "kill", kill = { 3246 }, count = 2, at = { { 4800, 1320 } }, radius = 600 },
                } },
                { group = {
                    { type = "accept", quests = { 870 }, npc = { 3448 },
                      note = "This step and the next two show as one card. Every quest giver gets a star and a panel row; take the quests in any order. Each checks off as accepted, and the card moves on once all are." },
                    { type = "accept", quests = { 869 }, npc = { 3464 } },
                    { type = "accept", quests = { 871 }, npc = { 3429 } },
                } },
                { type = "accept", quests = { 1502 }, npc = { 5810 }, cond = { class = "WARRIOR" },
                  note = "Warriors only. A separate visit; it never joins the group above." },
                { type = "travel", object = "bubbling rock", quest = { 870, 1 }, at = { { 4507, 2253 } }, radius = 300,
                  note = "The accepts above are explicitly grouped; this objective is its own step." },
                { type = "turnin", quests = { 870 }, npc = { 3448 },
                  note = "Tonga's panel row reads 'needs quest' and gets no star while The Forgotten Pools is not in your log." },
                { type = "finish", note = "NPC tracking fixture complete." },
            } },
        },
        npcs = {
            [1413] = {
                [3244] = "Greater Plainstrider",
                [3245] = "Ornery Plainstrider",
                [3246] = "Fleeting Plainstrider",
                [3429] = { name = "Thork", at = { 5150, 3087 } },
                [3448] = { name = "Tonga Runetotem", at = { 5226, 3193 } },
                [3464] = { name = "Gazrog", at = { 5193, 3032 } },
                [5810] = { name = "Uzzek", at = { 6138, 2111 } },
            },
        },
    },
})
