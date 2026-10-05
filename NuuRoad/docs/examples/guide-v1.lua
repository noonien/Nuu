-- Guide format v1, worked example. NOT LOADED: this file is not in
-- NuuRoad.toc, does not touch `ns`, and registers nothing. It returns a guide
-- value, so it can be read, diffed, or required by a scratch script.
--
-- v1 is the one format NuuRoad's guides are written in: the packaged guides
-- in Data/Guides, the development fixtures in Dev/Fixtures, and, once there
-- is an export, a guide a player shares. A guide is a Lua value, not text:
-- how that value is turned into something a player can share is a later
-- step. It holds what the author decided and nothing that can be worked out
-- again: no titles, no completion rules, no refs, no indexes. Steps:Expand
-- builds those from each step's type and its facts, then Schema:Validate
-- checks the result. docs/guide-schema.md says how each part behaves.
--
-- The guide below is made up to use every feature once; its IDs are
-- illustrative and its route makes no sense on the map.
--
-- VALUES
--
--   * Only strings, whole numbers, `true`, and tables. No floats, no `false`,
--     no empty tables (a field is there or left out), no holes in lists, no
--     table reached twice, no cycles.
--   * Every field is named. The only positional values are lists of like
--     things ({ 871, 844 }) and a point's two coordinates.
--   * A point is { x, y } or { x, y, map = 1454 }, in hundredths of a map
--     percent: 52.26 -> 5226. Each point stands on its own: one without a map
--     is on the section's map, then the guide's, never on the map of another
--     point in the same list, so one step's points may lie on different maps.
--     A point in an NPC's `at` list is on the map the NPC is listed under
--     unless it says otherwise. A radius is hundredths of a percent too
--     (0.02 of the map -> 200).
--   * Nothing refers to anything by position, except a quest objective (see
--     QUEST WORK). A step, group, or section that
--     something points at (a choice option, `with`, a level step's `by`)
--     carries a `label`, and the pointer names it. Place points are named by
--     their `id`, and a step names one as "place.point".
--   * Quests, items, and spells are IDs only: the client names them. NPCs are
--     the exception, since no API names a creature the player has not seen;
--     `npcs` holds them, by the map they are on: { [map] = { [id] = npc } },
--     where an npc is its name, or { name, at, note, instance } for one the
--     guide visits. `at`, when given, is one of:
--       { x, y }                   a point on that map
--       { { x, y }, { x, y } }     several spots it may be at, or a route it
--                                  walks: the arrow takes the nearest
--       "place.point" or "place"   a point of one of the guide's places, or
--                                  any point of it (NuuRoad has no other
--                                  paths to name)
--     `instance` marks an NPC inside a dungeon: the dungeon's instance ID
--     (GetInstanceInfo), listed under the map the dungeon's entrance is on.
--     It has no `at`, since a dungeon has no map the client reports; its
--     note says where. The note is shown on every visit.
--     Factions are IDs too, named by the client or by a table in NuuRoad.
--   * A name is only ever shown, never compared with what the client says,
--     since the client answers in the player's language. Places, areas,
--     flight points, and professions are IDs: a map ID (`zone`), an AreaTable
--     ID (`area`), a TaxiNodes ID (`node`), a SkillLine ID (`skill`). `to`,
--     `note`, `object`, and every other text is shown as written.
--   * An NPC the guide visits stands where `npcs` says, so a step that names
--     it in `npc` has no `at` of its own. A step's `at` is for a place, not a
--     person: an escort's end, a gathering spot, an object to click.
--
-- WRAPPER
--
--   kind = "guide", schema = 1, then the preview (id, updated, title,
--   category, author, tags, levels, cond, source, materials), then `data`.
--   An import can show the guide, check `cond` against the character, and
--   compare `updated` with the copy it has without reading `data`.
--
-- LAYOUT
--
--   data    = { map, conds, sections, places, npcs }
--   section = { title, map, label, cond, show, steps = { step or group, ... } }
--   group   = { label, cond, show, group = { step, step, ... } }, two or more steps
--
-- STEPS
--
-- Every step has a `type`; the fields after it are that type's.
--
--   note          note
--   finish        note; next, the guide to go on with (its ID, or a list of
--                 IDs: the first the player has and may follow is offered)
--   travel        to (shown), and zone (a map), area, or instance (a dungeon's
--                 instance ID, GetInstanceInfo) to finish on entering it
--                 instead of on arriving. With `quest = { id, n }`, the
--                 objective finishes it, not the arrival (an event)
--   accept        quests; level, the level they are taken from (see below).
--                 From an item rather than a person: item, the item
--                 that starts the quest, and no npc. Add kill (the creatures
--                 it drops from) to make one step of kill, loot, and accept:
--                 it reads as the kill until the item is in the bags, then as
--                 using it, and is done once the quest is taken. Or write
--                 the kill and loot as a collect with `starts` and the accept
--                 as its own step
--   turnin        quests; optional = true: passed on arrival unless a quest is
--                 ready to turn in, never waited on (also on talk)
--   talk          turnin, accept (lists of quests); level, as on accept; say,
--                 the dialog options to pick, in order, by gossip option ID
--                 (one per page of the conversation). Option IDs are the
--                 same in every language; the option's text is never matched
--   escort        quest, npc (required); `at` is where it ends
--   collect       item, count, kill (npcs it drops from), starts (a quest)
--                 count defaults to 1 with no quest or a whole quest
--   kill          kill (npcs); never a count (see QUEST WORK)
--   interact      object
--   gather        item, count, skill (the gathering profession)
--   craft         item, count, skill
--   skillup       item, skill, rank (both required)
--   buy           item, count (default 1), npc
--   vendor        sell = true, repair = true, or both
--   equip         item
--   train         skill, rank
--   learn         spells
--   cast          spell, count
--   skill         skill, rank
--   reputation    faction, standing (1 Hated to 8 Exalted)
--   hearth        area (where the hearthstone is bound)
--   flight        node (the flight point learned)
--   level         level, and xp or by (a label), not both. The guide goes no
--                 further until the player is there. `at` is where to grind;
--                 without it the step waits wherever the player is
--   choice        text, options = { { text, go = label }, ... }
--
-- `level` on an accept or a talk that accepts is the level its quests are
-- taken from: the step shows "Reach level 15", with the experience still
-- needed, on the line before the accepts and after any turn-ins, which may be
-- what brings it. It gates nothing: the client will not give the quests any
-- sooner, so the step waits on the accept as always. To stop the guide
-- itself until a level, write a level step.
--
-- Fields any step may carry:
--
--   note    text            label   identifier        cond     condition
--   show    condition (see CONDITIONS)
--   npc     { npc, ... }    object  text
--   at      { point, ... }  loop    true              radius   hundredths of a percent
--   stand   "place.point", the step's coordinates are that place point's
--   near    "place.point", joins the step to that point's passages
--   wait    seconds         use     { item, ... }
--   item    { item, ... }, the item the step is about (one that starts its quest);
--           the item panel offers it
--   with    label           sticky  true            from    label
--   mark    { npc, ... }, creatures to mark and list as targets without killing
--           them counting for anything: the mobs of a grind spot, a creature
--           an item is used on
--
-- Three fields carry a step on the card under whatever step is current,
-- rather than making the player stop on it:
--
--   with = label    from where it is written until the labelled later step
--                   is done
--   sticky = true   from where it is written until it is done itself
--   from = label    from an earlier labelled step until it is done, or until
--                   the guide reaches it and it becomes the current step.
--                   Work that happens in the background - drops off creatures
--                   fought for other reasons - written once, where it is
--                   finished
--   quest   the quest the step's work is for (see QUEST WORK)
--   upto    { skill, rank }, skill a SkillLine ID
--   needs   { { item, count, source }, ... }, source "gather" (default),
--           "vendor", "ah", "drop" or "craft"
--
-- CONDITIONS
--
-- Two fields decide whether a step is in the guide for this character at
-- all. They hide; they never make the guide wait. Both sit on the guide, a
-- section, a group, or a step, and a step's own and every one around it must
-- all hold.
--
--   cond   who the character is, which never changes: read once, when the
--          guide loads
--   show   what the character has chosen, which can change: read when the
--          guide loads and again when it changes
--
-- Both take a condition table:
--
--   { class = "WARRIOR", race = "orc" }   every key must hold
--   { class = { "MAGE", "DRUID" } }       a list: any of them
--   { any = { c, c, ... } }               at least one of these conditions
--   { none = { c, c, ... } }              none of them (there is no `false`)
--   { all = { c, c, ... } }               all of them; only to repeat a key
--   { is = "noAH" }                       a named condition from data.conds
--
-- Each c is a condition table of its own, so they nest. The keys:
--
--   cond   class, race, faction   a token or a list ("WARRIOR", "tauren",
--                                 "Horde")
--          season                 true, or a season number
--          hardcore               true
--   show   skill                  a SkillLine ID, or a list: knows the
--                                 profession; re-read on SKILL_LINES_CHANGED
--          ah, selffound          true: the player's answers under Options ->
--                                 About your realm (uses the auction house,
--                                 plays self found); re-read when they change
--
-- A named condition may hold keys of either kind; it is read as `show` when
-- any of its keys is one.
--
-- WHEN A STEP APPLIES
--
--   * `cond` fails: the step is not in the guide for this character - no row,
--     no number, never waited on.
--   * `show` fails: the same, until it holds. A step that comes to hold later
--     (Mining learned after the guide passed a Mining quest) joins the guide;
--     one that joins behind the current step is carried on the card until it
--     is done or skipped.
--   * A quest whose every accept step is out of the guide (the Tauren and The
--     Demon Seed here) takes its other steps out with it.
--   * An accept from an item (`item`, no `npc`) whose item is not in the bags
--     when the guide reaches it passes: the rare that drops it was never met,
--     the item never looted. Carried until then (sticky, `with`, `from`),
--     it is shown as usual.
--   * A quest that can no longer be taken - a breadcrumb whose follow-up is
--     done, one of two quests that exclude each other - takes its steps out
--     of the guide when the guide reaches them.
--
-- Nothing else hides a step or skips it for the player. A step waits by its
-- own nature (a cast for the cast, a turn-in for the quest to be ready, a
-- train step for the spells) and the player presses Skip whenever they
-- choose. A step is passed without asking only when it has nothing left to
-- do: its quest is finished; it is a turn-in of a quest the player skipped
-- or abandoned and so has nothing to hand in; it is an `optional` turn-in of a
-- quest not ready; or it is an accept from an item that is not in the bags.
--
-- Some steps are marked, derived from their own fields and never written:
--
--   * quest failed - an escort whose NPC died, a timed quest run out: the
--     step's `quest`; its lines turn red and say to abandon and retake it
--   * item needed first - one of the step's `use` items is not in the bags
--     (the horn that summons Echeyakee)
--   * on cooldown - the step's spell (a cast) or one of its `use` items is
--     cooling down: marked with the time left (Skysight)

-- PLACES
--
-- { id, name, width, map, points = { { id, at, kind, label }, ... },
--   links = { { from, to, oneway }, ... } }. A point's `kind` is "entrance" or
-- "exit" (none: inside). Link ends are point ids.
--
-- QUEST WORK
--
-- There is no step type for a quest objective. A step describes the work -
-- kill these, collect that, go there, click this - and `quest` says which
-- quest it is for:
--
--   quest = 924          the quest as a whole: the step is also done once 924
--                        is ready to turn in or finished
--   quest = { 871, 1 }   one objective, by its number in the quest log: the
--                        step is done when the client says that objective is
--                        finished, and shows the client's count for it (so a
--                        kill a party member is credited for counts, and one
--                        made before a reload is not lost)
--
-- A step whose target is unknown - no creature or item ID found yet - may
-- leave it out and give only `quest = { id, n }`: it is titled from the
-- client's objective text and finished by the objective. The editor warns
-- about it when the guide is written, and the guide checkers report it.
--
-- `from` is allowed on any step, group members included.
--
-- Either way the step's own rule (bags, arrival, a click) also finishes it,
-- and the quest being ready finishes it too. The step's type says what the
-- objective should be (kill: monster, collect: item, interact: object), so
-- `/nuuroad audit` can report an objective number that no longer fits its
-- quest.
--
-- How many is the objective's business, not the guide's: the client says how
-- many an objective needs for any quest, in the log or not, taken or never
-- seen (checked on build 1.60.1 (70205) with NuuExperiments' quest-data: the
-- data ships with the client and answers at once). One objective is one kind
-- of creature or item, so a quest asking for two kinds is two steps. `count`
-- is the step's own target only:
--
--   kill with an objective        no count; the objective counts
--   kill without a quest          no count: kill this creature - a boss in the
--                                 way, something a scene sets on the player -
--                                 done when it dies to the player or their
--                                 party. Killing for experience is a level
--                                 step at a spot, never a kill count
--   collect with an objective     no count; the objective's number is known
--                                 before the quest is taken, so the bags are
--                                 measured against it until then
--   collect without a quest,      count required (gather, craft, buy, and a
--   gather, craft, buy            collect with nothing behind it)
--   cast                          count optional, default 1
--
-- A scripted event (a scene, an ambush, a ritual) is the step that sets it off
-- - an interact, a travel, a talk - with the event's objective in `quest`; the
-- click or the arrival starts it, the objective finishes it. A step with
-- `quest = { id, n }` is never finished by its arrival alone.
--
-- HOW THE ADDON READS IT
--
-- Steps:Expand (Data/Steps.lua) reads a guide into the runtime guide, and
-- Schema:Validate checks it; the packaged guides in Data/Guides put their
-- values in ns.packagedGuides as they load, and GuideRepository expands them
-- at login. What Expand does beyond the plain mapping:
--
--   * `cond` becomes a predicate on each step (a section's and a group's on
--     each of theirs). `show` becomes a `now` term: read when the guide
--     reaches the step, which is passed over if it does not hold.
--   * `optional` turn-ins and talks pass on arrival unless a quest is ready;
--     an accept from an item, not carried, passes when the item is not in the
--     bags.
--   * Areas and flight nodes are compared by name: an area's from the client
--     (C_Map.GetAreaInfo) where it answers, otherwise Data/IDNames.lua, which
--     Tools/IDNames.py writes from db/sources/wago/forever; flight nodes and
--     skills from that table. `zone` is checked against the player's map ID;
--     travel `instance` against GetInstanceInfo's instance ID.
--   * `quest = { id, n }` finishes any step type on the objective (a travel
--     only on it); kill and collect steps with one are the runtime's
--     objective steps, titled by the client's objective line, and their count
--     is asked of the client when the step is shown (Steps:Count).
--   * `from` carries a step from the labelled step until done or reached
--     (Progress:Carried); `mark` adds targets that count for nothing; `say`
--     is kept on the step.
--   * `npcs` becomes the runtime's NPC table, its map put on each point.
--   * `level` on an accept or talk is said by Steps:Goals as a "Reach
--     level" line before the accepts.
--
-- STILL TO DO
--
--   * `show` hides a step's row and number, and brings it back on
--     SKILL_LINES_CHANGED or an Options change; today it passes the step over
--     when reached, and a profession learned later does not bring it back.
--   * An accept from an item with `kill` reads as the kill until looted and
--     then as the item's use; today it reads as the accept, with the kill's
--     targets marked.
--   * `say`: highlight the option in the dialog. That Forever's client gives
--     gossipOptionID is unverified (a NuuExperiments check).
--   * Points in one `at` list on different maps: the runtime keeps one map
--     per step, the first point's.
--   * Travel data for dungeon entrances, so the arrow leads to an `instance`.
--   * Quests a guide needs but the player does not have: say what is missing
--     and which guide gives it.
--   * Skill names by spell in the player's language, rather than the English
--     names in Data/IDNames.lua.
--   * Markings derived from a step's own fields: quest failed, item needed
--     first, on cooldown.
--   * `/nuuroad audit` and a guide checker in Tools/ for missing targets,
--     unplaced NPCs, unresolved labels and objective numbers whose type or
--     target does not match the quest.

return {
    kind = "guide",
    schema = 1,

    id = "nuuroad:example:every-feature",
    updated = 1790985600,                -- 2026-10-03
    title = "Example: every feature",
    category = "Fixtures/Examples",
    author = "NuuRoad",
    tags = { "example" },
    levels = { from = 13, to = 16 },
    cond = { faction = "Horde" },
    source = "Hand-written example of guide format v1.",
    materials = "section",

    data = {
        map = 1413,

        -- Conditions named once and used by name (`show = { is = "noAH" }`).
        conds = {
            noAH = { any = { { selffound = true }, { none = { { ah = true } } } } },
        },

        sections = {
            { title = "Crossroads", steps = {
                -- A note to read, done when the player presses on.
                { type = "note", note = "Written for Warriors and Shamans. Other classes see only the steps open to them." },
                -- Hand in Ak'Zeloth and take The Demon Seed in one visit. Done once 809 is finished and 924
                -- is in the log. Not in the guide at all for Tauren.
                { type = "talk", turnin = { 809 }, accept = { 924 }, npc = { 3521 },
                  cond = { none = { { race = "tauren" } } } },
                -- Pick up Flawed Power Stones from the stones on the ground, as many as 924's first objective
                -- asks. Done once the objective is finished. Not in the guide for a Tauren: the only step that
                -- takes 924 is not in theirs (see WHEN A STEP APPLIES).
                { type = "collect", item = 4986, quest = { 924, 1 }, object = "Flawed Power Stones",
                  at = { { 6150, 2150 } } },
                -- Place the stones on the mound. The quest has no objective line for this, so the step names the
                -- whole quest: done once 924 is ready to turn in.
                { type = "interact", object = "Mound of Dirt", use = { 4986 }, quest = 924, at = { { 6180, 2120 } },
                  note = "Place the stones on the mound to finish The Demon Seed." },
                -- Take The Forgotten Pools from Tonga, who stands where `npcs` says. Done once it is in the log.
                { type = "accept", quests = { 870 }, npc = { 3448 } },
                -- Take Tonga's quest for miners. Not in the guide for a character without Mining; one who
                -- learns it later (in Orgrimmar, below) gets the step back, carried until done or skipped.
                { type = "accept", quests = { 97970 }, npc = { 3448 }, show = { skill = 186 } },
                -- Set the hearthstone at the innkeeper. Done once the bind location is The Crossroads (area 380).
                { type = "hearth", area = 380, npc = { 3934 } },
                -- Learn the flight path. Done once the taxi map or the "new flight path" message shows node 25.
                { type = "flight", node = 25, npc = { 3615 } },
                -- Three quest givers a few steps apart, shown together so the player takes them in any order.
                -- Each is done on its own; the guide moves on once all three are.
                { group = {
                    -- Take Disrupt the Attacks from Thork.
                    { type = "accept", quests = { 871 }, npc = { 3429 } },
                    -- Take Harpy Raiders and Supplies for the Crossroads from Darsok.
                    { type = "accept", quests = { 867, 5041 }, npc = { 3449 } },
                    -- Take Plainstrider Menace from Sergra. The beaks step further on is shown from here.
                    { type = "accept", quests = { 844 }, npc = { 3338 }, label = "beaks" },
                } },
                -- "Up the road north", never a step of its own: shown on the card of the group below, which it
                -- names by the group's label, and done when the group is.
                { type = "travel", to = "Up the road north", with = "razormanes", at = { { 5200, 2700 } } },
                -- Disrupt the Attacks asks for three kinds of Razormane, one objective each, so it is three kill
                -- steps. They share the same camps, so they are grouped: every target is marked at once and each
                -- step finishes on its own objective. The counts are the client's, so party kills count.
                { label = "razormanes", group = {
                    { type = "kill", kill = { 3267 }, quest = { 871, 1 },
                      at = { { 5300, 2240 }, { 4740, 2640 }, { 4840, 2960 } } },
                    { type = "kill", kill = { 3268 }, quest = { 871, 2 },
                      at = { { 5300, 2240 }, { 4740, 2640 }, { 4840, 2960 } } },
                    { type = "kill", kill = { 3265 }, quest = { 871, 3 }, at = { { 4840, 2960 } } },
                } },
                -- Kill harpies for Harpy Raiders' first objective.
                { type = "kill", kill = { 3276, 3277 }, quest = { 867, 1 }, at = { { 5690, 2400 } } },
                -- Pick up the supply crates for 5041's first objective, from the crates on the ground.
                { type = "collect", item = 16190, quest = { 5041, 1 }, object = "Supply Crate",
                  at = { { 5650, 2100 } }, note = "The supply crates are on the way to the pools." },
                -- Explore the pools: the arrival is 870's objective, so the step is done on arriving or on the
                -- client marking the pools explored, whichever comes first.
                { type = "travel", to = "The Forgotten Pools", quest = { 870, 1 }, at = { { 5690, 1980 } } },
                -- Pick up Chen's Empty Keg, which starts a quest. Done with it in the bags or once 819 was ever
                -- accepted, so the load-time scan can judge it.
                { type = "collect", item = 4926, starts = 819, object = "Chen's Empty Keg", at = { { 5520, 3000 } } },
                -- Use the keg to start Chen's Empty Keg; the item panel offers it as a button. Done once 819 is
                -- in the log.
                { type = "accept", quests = { 819 }, item = 4926, note = "Use Chen's Empty Keg to start its quest." },
                -- Loot Plainstrider Beaks for 844's first objective. Plainstriders are everywhere around the
                -- Crossroads, so from the moment 844 is taken (the "beaks" label) this step rides on the card
                -- with its count and marks while the player does everything else. Here it becomes the current
                -- step and the player finishes the count, or the guide passes it if the beaks are all looted.
                { type = "collect", item = 5087, kill = { 2955, 2956 }, quest = { 844, 1 }, from = "beaks",
                  at = { { 5300, 2900 } } },
                -- Grind until the turn-ins still ahead, up to the Ratchet section, will take the player to 14.
                -- Done on experience plus what those turn-ins give.
                { type = "level", level = 14, by = "ratchet", at = { { 5420, 2400 } }, mark = { 2955, 2956 },
                  note = "Grind the plainstriders here so the turn-ins before Ratchet bring you to 14." },
            } },

            { title = "Southern Barrens", steps = {
                -- Walk to the cave's north mouth; the step stands on that place point. Done on arrival.
                { type = "travel", to = "Windfury cave", stand = "windfury.mouth" },
                -- Loot Sunscale Feathers off the scytheclaws in the chamber. The arrow follows the cave's
                -- passages to the chamber rather than the ledge that lies over it on the map.
                { type = "collect", item = 5165, kill = { 3256 }, quest = { 905, 1 },
                  at = { { 4050, 2470 } }, near = "windfury.chamber" },
                -- Take the next quest from the spirit in the chamber. It stands on a point of the cave, so its
                -- entry in `npcs` names that point, and the arrow follows the passages to it.
                { type = "accept", quests = { 906 }, npc = { 3434 } },
                -- "Through the cave", never a step of its own: shown on the bristlebacks step's card and done
                -- when that step is, or on arrival, whichever comes first.
                { type = "travel", to = "Through the cave", with = "bristlebacks", at = { { 5967, 8333 } } },
                -- Loot Bristleback Belts for 757's first objective. The belts drop whether or not the player
                -- has the quest; the bags count towards the objective's number even before 757 is taken.
                { type = "collect", item = 4770, quest = { 757, 1 }, label = "bristlebacks",
                  at = { { 5933, 7834 } }, note = "The belts drop with or without the quest; keep them." },
                -- One step for kill, loot, and accept, carried under every step from here: kill Owatanka if he
                -- turns up, loot his tailspike, use it. It reads as the kill until the tailspike is in the
                -- bags, then as using it, and is done once 884 is taken. Reached without the tailspike (he was
                -- never met), it passes.
                { type = "accept", quests = { 884 }, item = 5102, kill = { 3473 }, sticky = true,
                  note = "If you see Owatanka, kill him: his tailspike starts a quest." },
                -- The same as two steps, for when the accept belongs somewhere else: kill Washte Pawne and
                -- loot his feather (carried until looted or 885 was ever taken), then use the feather here,
                -- where the guide reaches it. The accept passes for anyone who never looted it.
                { type = "collect", item = 5103, starts = 885, kill = { 3472 }, sticky = true,
                  note = "If you see Washte Pawne, kill him: his feather starts a quest." },
                { type = "accept", quests = { 885 }, item = 5103,
                  note = "Use Washte Pawne's Feather to start its quest." },
                -- Collect Broken Tools by killing Bael'dun for their picks and pressing the picks at the forge.
                -- The item panel offers the pick; the objective counts the tools.
                { type = "collect", item = 4703, kill = { 2989, 2990 }, quest = { 746, 1 },
                  use = { 4702 }, note = "Smash the picks at the forge." },
                -- A scripted event: clicking the Altar of Fire starts a short ritual, and 1824's first objective
                -- is the ritual finishing. Done on that objective; the eight seconds are shown, not enforced.
                { type = "interact", object = "Altar of Fire", quest = { 1824, 1 }, at = { { 4650, 6000 } }, wait = 8,
                  note = "The flame takes a few seconds to answer." },
                -- Hand in Samophlange and take the manual at the Control Console. Arrival is 2% of the map
                -- instead of the usual radius for a visit. 900 is taken from level 15, so the step reads:
                -- turn in 894, reach level 15, accept 900.
                { type = "talk", turnin = { 894 }, accept = { 900 }, level = 15, object = "Control Console",
                  at = { { 5060, 5480 } }, radius = 200 },
                -- Kill the guardian the hand-in wakes, no quest behind it. Done when it dies to the player or
                -- their party.
                { type = "kill", kill = { 3418 },
                  note = "Handing in the samophlange wakes the console's guardian. It attacks you." },
                -- Take The Escape from the shredder, where it waits before setting off: its position in `npcs`.
                { type = "accept", quests = { 863 }, npc = { 3439 } },
                -- Follow and guard Wizzlecrank's Shredder to the point given. Done once 863 is ready to turn in;
                -- if the shredder dies the line turns red and says to abandon and retake the quest.
                { type = "escort", quest = 863, npc = { 3439 }, at = { { 4880, 5050 } } },
                -- Cast Skysight at the convergence. Done on the cast. While the spell is on cooldown the step
                -- is marked with the time left; the player waits or presses Skip.
                { type = "cast", spell = 1259686, at = { { 4560, 6990 } },
                  note = "Skysight has a long cooldown. If it is not ready, skip this one." },
                -- Blow the Horn of Echeyakee here and kill him when he comes, for 881's first objective. While
                -- the horn is not in the bags, the step is marked: the player needs it first.
                { type = "kill", kill = { 3475 }, quest = { 881, 1 }, use = { 10327 }, at = { { 4400, 5800 } },
                  note = "Blow the horn and Echeyakee comes to you." },
                -- Grind to level 15 and 2000 experience into it.
                { type = "level", level = 15, xp = 2000, at = { { 4700, 6200 } },
                  note = "Grind the Bael'dun until here; the Ratchet quests are a step up." },
            } },

            { title = "Wailing Caverns", steps = {
                -- Enter the dungeon. The arrow leads to the entrance (from NuuRoad's travel data); done once
                -- the client reports the player inside instance 43.
                { type = "travel", to = "Wailing Caverns", instance = 43 },
                -- Kill Lord Cobrahn for 914's first objective. He is inside the dungeon, so his entry in
                -- `npcs` carries the instance and a note instead of a position.
                { type = "kill", kill = { 3669 }, quest = { 914, 1 } },
                -- 914's second objective, whose creature has no known ID yet: the step gives only the quest
                -- pair, is titled from the client's objective text, and the editor and checkers warn.
                { type = "kill", quest = { 914, 2 } },
            } },

            { title = "Ratchet", label = "ratchet", steps = {
                -- Go to Ratchet. The arrow points at the docks; done on entering Ratchet (area 392).
                { type = "travel", to = "Ratchet", area = 392, at = { { 6290, 3700 } } },
                -- Hand in Raptor Horns and Wharfmaster Dizzywig. Optional: a quest not ready to hand in when
                -- the guide gets here is passed over, not waited on.
                { type = "turnin", quests = { 865, 1492 }, npc = { 3453 }, optional = true },
                -- Go no further before level 16. No `at`: the guide waits wherever the player is.
                { type = "level", level = 16, note = "The rest of Ratchet's quests want 16." },
                -- Ask Gazlowe about the stolen goods: two pages of dialog, one option picked on each. The
                -- conversation is 896's first objective, so the step is done when the client says so.
                { type = "talk", npc = { 3391 }, quest = { 896, 1 }, say = { 41231, 41232 },
                  note = "Ask about the stolen goods, then about who took them." },
                -- Shown under every step from here until the player is Friendly with Ratchet.
                { type = "reputation", faction = 470, standing = 5, sticky = true,
                  note = "Every Ratchet quest counts. Friendly gets a discount from the Ratchet vendors." },
                -- Buy two Weak Flux from Kzixx, for the mace later. Done with two in the bags.
                { type = "buy", item = 2880, count = 2, npc = { 3134 } },
                -- Sell junk and repair at Kilxx. Done when the player presses on.
                { type = "vendor", sell = true, repair = true, npc = { 3497 } },
            } },

            { title = "Orgrimmar", map = 1454, steps = {
                -- Go to Orgrimmar. The arrow points at the gate on the Durotar map; done on entering the city.
                { type = "travel", to = "Orgrimmar", zone = 1454, at = { { 4550, 1220, map = 1411 } } },
                -- Learn Mining. Done once the player has any rank in it.
                { type = "train", skill = 186, npc = { 3357 } },
                -- Shown under every step from here until Mining reaches 50, the rank on the goal line.
                { type = "skill", skill = 186, rank = 50, sticky = true,
                  note = "Mine every copper vein you pass." },
                -- Learn Blacksmithing. Done once the player has any rank in it.
                { type = "train", skill = 164, npc = { 3355 } },
                -- Train Charge and Rend. Done once both are known. Not in the guide for anyone but a Warrior; a
                -- Warrior short of gold skips it and trains at the next visit.
                { type = "learn", spells = { 100, 772 }, npc = { 3354 }, cond = { class = "WARRIOR" } },
                -- Equip the Walking Stick. Done once it is worn. A player with a better weapon skips it.
                { type = "equip", item = 2495,
                  note = "The staff from The Escape. Skip this if your weapon is better." },
                -- Buy a bag. Only in the guide for players who said they play self found or do not use the
                -- auction house: the named condition `noAH`, read as `show` since the answers can change.
                { type = "note", note = "Buy a Small Brown Pouch from the general goods vendor if you have no bag yet.",
                  show = { is = "noAH" } },
            } },

            { title = "Copper circuit", steps = {
                -- Go round the copper veins. The arrow takes whichever vein is nearest, and the choice below
                -- can send the player back here for another lap.
                { type = "travel", to = "Copper veins, north road", label = "circuit", loop = true,
                  at = { { 4890, 2540 }, { 5010, 2280 } } },
                -- Mine sixty Rough Stone. Done with sixty in the bags, or once Blacksmithing reaches 50, past
                -- which the stone is not wanted.
                { type = "gather", item = 2835, count = 60, skill = 186,
                  upto = { skill = 164, rank = 50 } },
                -- Ask whether to run the circuit again. Going back resets the lap's steps and shows the lap count.
                { type = "choice", text = "Another lap around the veins?", options = {
                    { text = "Run the circuit again", go = "circuit" },
                    { text = "Done mining", go = "forge" },
                } },
            } },

            { title = "The forge", map = 1454, label = "forge", steps = {
                -- Make a Copper Mace at the anvil. Done on the craft or with one in the bags. Its materials join
                -- the shopping list, each under where it comes from.
                { type = "craft", item = 2844, count = 1, skill = 164, at = { { 7600, 2350 } },
                  needs = {
                      { item = 2840, count = 6, source = "ah" },
                      { item = 2880, count = 2, source = "vendor" },
                      { item = 2589, count = 2, source = "drop" },
                  } },
                -- Make Rough Grinding Stones until Blacksmithing reaches 50, however many that takes.
                { type = "skillup", item = 3470, skill = 164, rank = 50,
                  needs = { { item = 2835, count = 60 } } },
                -- Train Journeyman Blacksmithing. Done once Blacksmithing is at 50, the next visit to the trainer.
                { type = "train", skill = 164, rank = 50, npc = { 3355 },
                  note = "Journeyman Blacksmithing." },
                -- The end of the guide.
                { type = "finish", note = "That is every feature." },
            } },
        },

        places = {
            { id = "windfury", name = "Windfury cave", width = 15,
              points = {
                  { id = "mouth", at = { 4010, 2030 }, kind = "entrance", label = "the north mouth" },
                  { id = "fork", at = { 4030, 2210 }, label = "the crossroads" },
                  { id = "ledge", at = { 4270, 2360 }, label = "the ledge" },
                  { id = "chamber", at = { 4040, 2450 } },
                  { id = "hole", at = { 4060, 2600 }, kind = "exit", label = "the hole to the river" },
              },
              links = {
                  { from = "mouth", to = "fork" },
                  { from = "fork", to = "ledge" },
                  { from = "fork", to = "chamber" },
                  { from = "ledge", to = "chamber", oneway = true },
                  { from = "chamber", to = "hole" },
              },
            },
        },

        npcs = {
            [1413] = { -- The Barrens
                -- Visited: a step goes to them, so they stand where `at` says.
                [3521] = { name = "Ak'Zeloth", at = { 6234, 2007 }, note = "On the road from Durotar." },
                -- Two spots he may be at; the arrow takes the nearer.
                [3448] = { name = "Tonga Runetotem", at = { { 5226, 3193 }, { 5248, 3120 } },
                           note = "Beside the well, or under the tower." },
                -- On a point of the guide's cave.
                [3434] = { name = "Spirit of the Cave", at = "windfury.chamber" },
                -- Where it waits before the escort.
                [3439] = { name = "Wizzlecrank's Shredder", at = { 6260, 3830 } },
                -- Inside Wailing Caverns, whose entrance is on this map.
                [3669] = { name = "Lord Cobrahn", instance = 43, note = "In the first big cavern, past the pools." },
                [3934] = { name = "Innkeeper Boorand Plainswind", at = { 5162, 2971 } },
                [3615] = { name = "Devrak", at = { 5150, 3033 } },
                [3429] = { name = "Thork", at = { 5150, 3087 } },
                [3449] = { name = "Darsok Swiftdagger", at = { 5162, 3089 } },
                [3338] = { name = "Sergra Darkthorn", at = { 5224, 3101 } },
                [3453] = { name = "Wharfmaster Dizzywig", at = { 6295, 3734 } },
                [3134] = { name = "Kzixx", at = { 6270, 3650 } },
                [3497] = { name = "Kilxx", at = { 6250, 3610 } },
                [3391] = { name = "Gazlowe", at = { 6280, 3680 } },

                -- Kill targets: they spawn across an area, many at once, so no one point is where they are.
                -- The step that fights them says where with its own `at` (the Razormanes' three camps).
                [3267] = "Razormane Water Seeker",
                [3268] = "Razormane Thornweaver",
                [3265] = "Razormane Hunter",
                [2955] = "Plainstrider",
                [2956] = "Adult Plainstrider",
                [3256] = "Sunscale Scytheclaw",
                [3276] = "Witchwing Harpy",
                [3277] = "Witchwing Roguefeather",
                [2989] = "Bael'dun Digger",
                [2990] = "Bael'dun Appraiser",

                -- Rares: they wander or turn up at one of several spawns, so the guide never sends the player
                -- to them. Owatanka is here because his drop starts a quest (the sticky collect step).
                [3473] = "Owatanka",
                [3472] = "Washte Pawne",


                -- Brought to the player by a scene or a summoning: it appears where that happens and comes to
                -- them, so the step needs no place.
                [3418] = "Console Guardian",
                [3475] = "Echeyakee",
            },
            [1454] = { -- Orgrimmar
                [3357] = { name = "Makaru", at = { 7300, 2600 } },
                [3355] = { name = "Saru Steelfury", at = { 7650, 2300 } },
                [3354] = { name = "Sorek", at = { 8070, 3200 } },
            },
        },
    },
}
