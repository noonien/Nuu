-- Guide schema v2, worked example. NOT LOADED: this file is not in
-- NuuRoad.toc, does not touch `ns`, and registers nothing. It returns a table
-- so it can be read, diffed, or required by a scratch script, and nothing else.
--
-- SCOPE: v2 is the export/import format only. It is what an author writes, what
-- a packaged guide ships as, and what the editor writes out -- the interchange
-- shape, nothing more. It is not the shape the addon runs on. Import converts a
-- guide once, and the runtime is free to hold whatever serves the tracker best:
-- flattened steps, resolved spans, prebuilt titles, per-step caches, indexes
-- that only exist in memory. None of that belongs here, and none of it has to
-- share these names.
--
-- Two consequences worth stating, since they decide where work goes:
--
--   * validation is an import concern. A guide is checked once, on the way in;
--     nothing downstream re-validates, and the runtime may assume a well-formed
--     guide because a malformed one never becomes a runtime guide.
--   * anything derived is built at import, not authored and not stored here.
--     Titles, step positions, section and group spans, reference lists and
--     completion rules are all computed from the fields below. Nothing derived
--     is written back: the saved resume step is dropped when the guide changes,
--     and the load-time scan places the player from the quest log each login,
--     so no stored position can go stale against a changed guide.
--
-- It is a slice of the ported Barrens route (quest, creature, item, and map IDs
-- follow Data/BuiltIn/HordeBarrens.lua) chosen so that every v2 feature appears
-- at least once. What changed from v1:
--
--   * sections nest, like groups: a guide is a list of sections, a section is
--     a list of steps and groups. Both wrappers flatten to a span, so no
--     `nodeIndexes` array and no step position is ever authored
--   * no `next` and no authored step position: steps run in order, `only`
--     skips. A branch is a `choice` whose options name labels -- any step,
--     group, or section may carry `label = "..."`, an option says
--     `goto = "<label>"`, and the import resolves it. A label behind the
--     choice runs that stretch again, which is how a circuit is written
--   * no `requirements`: a guide carries `only`, same as a step
--   * `spots` folded into `at`: one point, or a list of points the arrow
--     treats as equals, pointing at whichever is nearest
--   * `revision` -> `updated`, seconds since the epoch. A number the client can
--     use directly: `time()` stamps it, `date()` prints it, and comparing two
--     copies on import is a subtraction. It settles which copy is newer and
--     tells a player when a guide last changed, where a counter did neither
--     and needed its own prior value to increment
--   * every field name is one word; two-word names were merged or deleted
--     (`minLevel`/`maxLevel` -> `levels`, `estimatedMinutes` dropped,
--     `schemaVersion` -> `schema`, `flightpath` -> `flight`, `done` -> `finish`,
--     `items` -> `item`, `arrivalRadiusNormalized` -> `radius`)
--
-- Coordinates are map percentages, read against the guide `map`. A section
-- overrides it for its whole span; a single `at` overrides it for one point.
-- A step itself has no `map`. IDs only; display names come from
-- Data/Names.lua. `object` is the
-- one deliberate exception: world objects are named, not numbered. ASCII only.

return {
    schema = 2,
    id = "nuuroad:example:barrens-v2",
    updated = 1789862400,                -- 2026-09-20, seconds since the epoch
    map = 1413,
    only = "Horde",
    meta = {
        title = "Schema v2 Example: The Barrens",
        author = "NuuRoad",
        category = "Leveling/The Barrens",
        tags = { "example", "horde", "barrens" },
        levels = { 13, 16 },
        source = "Slice of the local Zygor Barrens & Stonetalon (13-21) port; text is NuuRoad's own.",
    },
    steps = {
        { section = "Into the Barrens", steps = {
            { note = "Written for Warriors and Shamans. Other classes can follow it; class-only steps are hidden for them." },

            -- A visit that hands one quest over and takes another is one step.
            { turnin = 809, accept = 924, npc = 3521, at = { 62.34, 20.07 }, only = "not Tauren",
              note = "Ak'Zeloth is on the road from Durotar." },

            -- `quest` marks a quest item: done once 924 is ready to turn in, and
            -- passed over entirely for a character who never took 924.
            { collect = 4986, quest = 924, object = "Flawed Power Stones", at = { 62.34, 20.03 }, only = "not Tauren",
              note = "The Demon Seed is timed: 30 minutes from picking up the stone." },

            { turnin = 1498, accept = 1502, npc = 5810, at = { 61.38, 21.11 }, only = "Warrior" },
            { turnin = 1527, npc = 5907, at = { 56.04, 19.89 }, only = "Shaman", note = "Kranal Fiss walks around here." },

            -- `starts` marks an item that begins a quest: also done once 819 has
            -- ever been accepted, so the step is never offered twice.
            { collect = 4926, starts = 819, object = "Chen's Empty Keg", at = { 55.78, 20.01 },
              note = "Skip if it is not on the ground; you pass by here again later." },
            { accept = 819, note = "Use the keg to start its quest." },

            { objective = 924, part = 1, object = "The Altar of Fire", at = { 47.96, 19.07 }, radius = 0.03, only = "not Tauren",
              note = "Run up Dreadmist Peak from 50.93, 22.55. The altar is inside the small cave." },
        } },

        { section = "Crossroads", steps = {
            { travel = "The Crossroads", at = { 51.99, 29.90 } },
            { hearth = "The Crossroads", npc = 3934, at = { 51.99, 29.90 },
              note = "Innkeeper Boorand Plainswind is inside the inn." },

            -- A group is two or more quest visits available together. Members keep
            -- their own conditions, NPCs, and coordinates, and each completes on
            -- its own; the tracker shows them as one card.
            { group = {
                { accept = 870, npc = 3448, at = { 52.26, 31.93 } },
                { turnin = 842, npc = 3338, at = { 52.24, 31.01 }, only = "Tauren" },
                { accept = 844, npc = 3338, at = { 52.24, 31.01 } },
                { accept = 869, npc = 3464, at = { 51.93, 30.32 } },
                { accept = 871, npc = 3429, at = { 51.50, 30.87 } },
                { accept = { 1492, 848 }, npc = 3390, at = { 51.44, 30.15 } },
                { turnin = 6386, npc = 3489, at = { 52.62, 29.84 }, only = "Orc or Troll" },
            } },

            { turnin = 1502, accept = 1503, npc = 5878, at = { 57.23, 30.34 }, only = "Warrior",
              note = "Thun'grim Firegaze is on the mountain east of the Crossroads. Run up from 54.50, 27.94." },
            { objective = 1503, part = 1, collect = 6534, object = "Stolen Iron Chest", at = { 55.05, 26.65 }, radius = 0.03, only = "Warrior" },
            { turnin = 1503, npc = 5878, at = { 57.23, 30.34 }, only = "Warrior" },
        } },

        { section = "Thorn Hill", steps = {

            -- Sticky objectives: between `track` and `untrack` the tracker shows
            -- the quest's first unfinished objective under every step.
            { track = 869 },
            { track = 844 },

            { note = "Chen's Empty Keg can also spawn here.", at = { 55.70, 27.29 }, only = "not quest 819" },

            -- One objective line of a quest. `kill` and `count` name the mobs and
            -- give the fallback title until the client answers with its own text.
            { objective = 871, part = 3, kill = 3265, count = 3, radius = 0.055,
              at = { { 55.60, 25.40 }, { 53.00, 25.20 }, { 54.40, 27.20 } } },
            { objective = 871, part = 1, kill = 3267, count = 8, radius = 0.055,
              at = { { 55.60, 25.40 }, { 53.00, 25.20 }, { 54.40, 27.20 } } },
            { objective = 871, part = 2, kill = 3268, count = 8, radius = 0.055,
              at = { { 55.60, 25.40 }, { 53.00, 25.20 }, { 54.40, 27.20 } } },

            -- A gather line: `collect` names the drop, `kill` the mobs that carry it.
            { objective = 844, part = 1, collect = 5087, count = 7, kill = { 3244, 3246 }, radius = 0.06,
              at = { { 53.00, 22.40 }, { 47.40, 26.40 }, { 48.40, 29.60 }, { 50.40, 33.40 }, { 51.00, 27.40 }, { 55.40, 25.20 } } },
            { untrack = 844 },

            { level = 13, xp = 9200, radius = 0.06,
              at = { { 53.00, 22.40 }, { 47.40, 26.40 }, { 48.40, 29.60 }, { 50.40, 33.40 } },
              note = "Grind here so the turn-ins bring you to 14." },

            { group = {
                { turnin = 871, accept = { 872, 5041 }, npc = 3429, at = { 51.50, 30.87 } },
                { accept = 867, npc = 3449, at = { 51.62, 30.89 }, note = "Darsok Swiftdagger is on top of the tower." },
                { turnin = 844, accept = 845, npc = 3338, at = { 52.24, 31.01 } },
            } },

            { objective = 872, part = 3, kill = 3438, collect = 5063, at = { 58.53, 27.04 }, radius = 0.04,
              note = "Kreenig Snarlsnout walks the north side of the mountain." },
            { objective = 5041, part = 1, collect = 12708, object = "Crossroads' Supply Crates", radius = 0.04,
              at = { { 58.40, 27.00 }, { 58.50, 25.80 }, { 59.10, 24.40 } },
              note = "Piles of brown boxes, several places around the camp." },
            { turnin = 924, npc = 3521, at = { 62.34, 20.07 }, only = "not Tauren" },
        } },

        { section = "Ratchet", steps = {
            { flight = "Ratchet", npc = 16227, at = { 63.09, 37.16 } },

            -- `npc` and `item` each take one ID or a list, and only say what the
            -- step is about; they carry no completion of their own.
            { note = "Fuzruckle is the banker. Bag space is tight in this zone.",
              npc = 3494, item = { 4986, 5087 }, at = { 62.64, 37.42 } },

            { group = {
                { accept = 887, npc = 3391, at = { 62.68, 36.23 }, note = "Gazlowe is upstairs." },
                { accept = 894, npc = 3442, at = { 62.98, 37.22 } },
                { turnin = 1492, npc = 3453, at = { 63.35, 38.45 } },
                { accept = 895, object = "WANTED", at = { 62.59, 37.47 } },
                { turnin = 819, accept = 821, npc = 3292, at = { 62.26, 38.39 }, only = "quest 819" },
            } },

            { track = 821 },
            { objective = 895, part = 1, kill = 3467, collect = 5084, radius = 0.05,
              at = { { 64.20, 47.20 }, { 62.40, 49.40 }, { 63.40, 49.20 } },
              note = "Baron Longshore wears a red trenchcoat and walks the coast south of Ratchet." },
            { objective = 887, part = 2, kill = 3382, count = 6, radius = 0.06,
              at = { { 63.40, 45.80 }, { 62.80, 49.80 }, { 63.40, 43.20 } } },

            -- A kill step with no quest behind it: counted from the combat log.
            { kill = { 3382, 3381 }, count = 5, at = { 63.40, 45.80 }, radius = 0.06,
              note = "Top up here if either objective is still short." },

            { level = 14, xp = 10200, at = { 63.40, 45.80 }, radius = 0.06 },
            { untrack = 821 },

            -- One coordinate on another map: `at` names it, and the section
            -- keeps its own. The destination of a zone change is the usual case.
            { travel = "Orgrimmar", at = { 49.90, 63.50, map = 1454 },
              note = "Take the zeppelin from the tower north of Ratchet." },
        } },

        -- A whole section in another zone carries the map instead. Every
        -- coordinate below reads against 1454.
        { section = "Orgrimmar", map = 1454, steps = {
            { turnin = 6362, npc = 3143, at = { 49.60, 62.40 }, only = "Warrior or Shaman",
              note = "Train if you have not since level 12." },
            { finish = "The Crossroads and Ratchet loop is done. Zhevra and the Oases comes next." },
        } },
    },
}

-- Import, for illustration only. Nothing below is part of v2: it is one
-- possible runtime shape, shown so the authored fields can be read against
-- something concrete. The importer may produce any shape it likes, under any
-- names, and change it without touching the format above or the guides written
-- in it. What matters is the direction: every derived value is computed here,
-- on the way in, and no index, ID, or edge is ever written down by an author.
--
--   { accept = 870, npc = 3448, at = { 52.26, 31.93 } }
--
--     {
--         type = "accept",
--         title = "Accept Lost in Battle",                     -- rebuilt on render
--         at = { map = 1413, x = 0.5226, y = 0.3193, radius = 0.02 },
--         when = { type = "quest", quests = { 870 }, state = "taken", match = "all" },
--     }
--
--   { objective = 844, part = 1, collect = 5087, count = 7, kill = { 3244, 3246 },
--     radius = 0.06, at = { { 53.00, 22.40 }, { 47.40, 26.40 } } }
--
--     {
--         type = "collect",
--         title = "Collect 7 Plainstrider Feathers",
--         at = { map = 1413, x = 0.53, y = 0.224, radius = 0.06,
--                pins = { { x = 0.474, y = 0.264 } } },
--         when = { type = "objective", quest = 844, part = 1 },
--     }
--
--   { objective = 924, part = 1, object = "The Altar of Fire", only = "not Tauren", ... }
--
--     {
--         type = "interact",
--         title = "Click The Altar of Fire",
--         only = { type = "not", child = { type = "race", values = { "tauren" } } },
--         when = { type = "objective", quest = 924, part = 1 },
--     }
--
-- Neither wrapper adds a node of its own. Each records a span over the
-- flattened list, the only place a step position is ever written down:
--
--     sections = { { first = 1,  last = 8,  title = "Into the Barrens" },
--                  { first = 9,  last = 21, title = "Crossroads" } }
--     groups   = { { first = 12, last = 18 }, { first = 27, last = 29 } }
--
-- A section is an annotation over a span, not a step: it is never current,
-- never enters the trail, and never counts toward progress. It does give the
-- tracker a per-section denominator ("Crossroads 6/13") and the dividers in
-- the upcoming list.
--
-- Wrapper rules: a section holds `section` and `steps` and nothing else; a
-- group holds `group` and nothing else. Sections do not nest and groups do not
-- nest; a group lives inside a section, which is structural rather than
-- checked. Every step is inside exactly one section, so there is no unnamed
-- leading span to synthesize.
--
-- `when` absent means the player marks the step done. Its types are `always`,
-- `arrive`, `level`, `quest`, `objective`, `item`, `kill`, `hearth`, `flight`,
-- and `all`; quest states are `taken`, `ready`, and `done`.
