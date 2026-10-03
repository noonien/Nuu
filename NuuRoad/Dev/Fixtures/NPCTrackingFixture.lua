local _, ns = ...

-- Fixture for NPC tracking: a group of kill steps counted from the combat
-- log, each target with its own marker and each step its own count, and a
-- group of quest-giver steps the tracker shows as one step, whose quests can
-- be taken in any order and whose NPCs all get a star and a panel row at
-- once. Plainstriders and the quest givers are around the Crossroads.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:fixture:npc-tracking"] = {
    schema = 2, id = "nuuroad:fixture:npc-tracking", updated = 1789862400, map = 1413, only = "Horde",
    meta = { title = "Fixture: NPC Tracking", author = "NuuRoad", category = "Fixtures/NPCs", tags = { "fixture", "npc", "kill", "horde" } },
    steps = {
        { section = "NPC tracking", steps = {
            { note = "Target or mouse over a plainstrider: it gets a skull (second kind a cross, third a square). Each kill you or your party land counts below." },
            { group = {
                { kill = { 3244, 3245 }, count = 3, at = { 48.0, 13.2 }, radius = 0.06, note = "Plainstriders northwest of the Crossroads. This step and the next show as one card, each with its own count. Hold Shift to keep a mark from being set." },
                { kill = 3246, count = 2, at = { 48.0, 13.2 }, radius = 0.06 },
            } },
            { group = {
                { accept = 870, npc = 3448, note = "This step and the next two show as one card. Every quest giver gets a star and a panel row; take the quests in any order. Each checks off as accepted, and the card moves on once all are." },
                { accept = 869, npc = 3464 },
                { accept = 871, npc = 3429 },
        } },
        { accept = 1502, npc = 5810, only = "Warrior", note = "Warriors only. A separate authored visit; it never joins the group above." },
        { object = "bubbling rock", objective = 870, part = 1, at = { 45.07, 22.53 }, radius = 0.03, note = "The accepts above are explicitly grouped; this objective is its own step." },
        { turnin = 870, npc = 3448, note = "Tonga's panel row reads 'needs quest' and gets no star while The Forgotten Pools is not in your log." },
        { finish = "NPC tracking fixture complete." },
        } },
    },
    names = {
        npcs = {
            [3244] = "Greater Plainstrider",
            [3245] = "Ornery Plainstrider",
            [3246] = "Fleeting Plainstrider",
            [3429] = { "Thork", at = { 51.50, 30.87 } },
            [3448] = { "Tonga Runetotem", at = { 52.26, 31.93 } },
            [3464] = { "Gazrog", at = { 51.93, 30.32 } },
            [5810] = { "Uzzek", at = { 61.38, 21.11 } },
        },
        quests = {
            [869] = "Raptor Thieves",
            [870] = "The Forgotten Pools",
            [871] = "Disrupt the Attacks",
            [1502] = "Thun'grim Firegaze",
        },
    },
}
