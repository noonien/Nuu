# Guide format v1

v1 is the one format NuuRoad's guides are written in: the packaged guides in `Data/Guides`, the development fixtures in `Dev/Fixtures`, and the guide value an export will one day hand a player. [`docs/examples/guide-v1.lua`](examples/guide-v1.lua) is the field-by-field reference, with one worked example of every step type, condition and field; this document says how those parts behave once the addon reads them.

A guide is not the shape the addon runs on. `Steps:Expand` (`Data/Steps.lua`) reads it once, on the way in, and everything downstream sees runtime nodes. Anything derived - titles, step positions, section and group spans, reference lists, completion rules - is built during that read and never written in a guide. `Schema:Validate` (`Data/Schema.lua`) then checks the runtime guide. The packaged guides and fixtures put their values in `ns.packagedGuides` as they load, and `GuideRepository:Initialize` expands and validates each at login; one that fails is reported and left out.

A guide is `kind = "guide"`, `schema = 1`, a stable `id`, `updated` (seconds since the epoch), a `title` and a `category`, and `data`, which holds the guide's `map`, its `sections`, and optionally `conds`, `places` and `npcs`. It may also carry `author`, `tags`, `levels = { from, to }`, `cond`, `source`, and `materials` (`"section"` or `"guide"`, see Materials).

`category` is where the guide browser files the guide: a path of folders, outermost first, split on `/` and as deep as it needs to be (`"Leveling/Kalimdor/The Barrens"`, `"Dungeons/Wailing Caverns"`, or one word). Spaces around a `/` are ignored, folders match without regard to case, and every folder must have a name, so a leading, trailing, or doubled `/` is rejected. Packaged guides do not put the faction in the path: the browser checks the guide's `cond` against the character instead. Test and regression guides go under a top folder named `Fixtures`, which the browser hides unless the debug log is on.

```lua
{
    kind = "guide", schema = 1,
    id = "nuuroad:leveling:horde-barrens-13-21",
    updated = 1789862400,
    title = "The Barrens", category = "Leveling/The Barrens", author = "NuuRoad",
    tags = { "horde", "barrens" }, levels = { from = 13, to = 21 }, source = "...",
    cond = { faction = "Horde" },
    data = {
        map = 1413,
        sections = {
            { title = "Crossroads", steps = { ... } },
            { title = "Orgrimmar", map = 1454, steps = { ... } },
        },
        npcs = { [1413] = { ... }, [1454] = { ... } },
    },
}
```

`updated` replaces a revision counter: the client stamps it with `time()`, prints it with `date()`, and comparing two copies is a subtraction. It settles which copy is newer and tells a player when a guide last changed, where a counter needed its own prior value to increment.

Steps run in order; there is no `next` and no step position written anywhere. A branch is a `choice` whose options name labels: any step, group, or section may carry `label = "..."`, and an option says `go = "<label>"`. Expand resolves labels to flattened positions, and a label behind the choice runs that stretch again, which is how a farming circuit is written. Two things sharing one label, or a pointer naming a label that does not exist, is an error at load.

Expand rejects an unknown step type, a field a section or group does not have, an empty section, a group of fewer than two steps or a nested one, a quest objective that is not `{ quest, objective }`, an area, flight node or skill it cannot name, and an unresolvable label; every error names the field, as in `NuuRoad: data.sections[2].steps[4].quest: must be { quest, objective }`. The validator then rejects invalid node kinds, group ranges, predicate trees, cyclic tables, executable values, and observed location completions on nodes without a location.

## Steps

Every step has a `type`; `docs/examples/guide-v1.lua` lists each type's fields. What each becomes:

| `type` | Runtime node |
| --- | --- |
| `note` | `note`, the text as body; on any other step, `note` is that step's body |
| `finish` | `end`, the text as body |
| `travel` | `travel`; done on arrival at `at`, or on entering `zone` (a map ID), `area` (an AreaTable ID, compared by the name the client gives the subzone) or `instance` (GetInstanceInfo's instance ID). With `quest = { id, n }`, only on that objective |
| `accept` | `acceptQuest`, done when every quest is accepted or finished. From an item: `item`, no `npc` |
| `turnin` | `turnInQuest`, done when every quest is finished |
| `talk` | `talk`: one visit that turns in and accepts, done when the turn-ins are finished and the accepts are in the log; with no quests, "Talk to ..." and manual; with `quest = { id, n }`, a quest objective that is a conversation |
| `escort` | `escort`, done when the quest is ready to turn in; titled "Escort <npc>", and the NPC is followed and marked like any step's. `at` is where the escort ends. When the client reports the quest failed (the NPC died), the line turns red and the card says to abandon the quest and take it again |
| `collect` | with `quest = { id, n }`: the objective, its count the client's. Otherwise `collect`, done with `count` (default 1) in the bags; `starts` (an item that begins that quest) also done once the quest was ever accepted; `quest` (a quest item) also done once the quest is ready or finished, and moot when the player has no such quest |
| `kill` | with `quest`: the objective, or the whole quest. Otherwise `kill`, done when the combat log shows `count` (default 1) killing blows by the player, their pet, or their party on those creatures |
| `interact` | `interact`, manual; with `quest`, the objective or the whole quest |
| `train` | `train`; done once the client reports any rank in the skill, or `rank` |
| `learn` | `train` for class spells, by spell ID; done once the client knows every one (`IsPlayerSpell`). Titled "Train Charge and Rend from Blademaster Ren" |
| `cast` | `cast`; done on `count` (default 1) casts of the spell made while the guide is on the step, counted from `UNIT_SPELLCAST_SUCCEEDED` |
| `skill` | `skillTarget`; the goal line shows the live rank against the target |
| `gather` | `gather`; done on the items in the bags however they arrived, so buying them counts. `skill` is the gathering profession |
| `craft` | `craft`; counts the client's "You create:" messages on this step, and is also done once that many are in the bags |
| `skillup` | `skillUp`; make the item over and over until the rank lands. Done on the rank, not on a count |
| `buy` | `buy`; from the vendor in `npc`, who is named in the step ("from Zargh"). Done when the items are in the bags |
| `vendor` | `vendor`, manual: sell, repair, or both |
| `equip` | `equip`; reads the equipment slots, not the bags |
| `reputation` | `reputationTarget`; `standing` from 1 (Hated) to 8 (Exalted) |
| `hearth` | `hearth`, done when the bind location is the area |
| `flight` | `flight`, done once the taxi map or the "new flight path" message shows the node learned |
| `level` | `levelTarget`, the level and optionally `xp` into it, or `by` (see Level by a later step). `at` is where to grind; without it the step waits wherever the player is |
| `choice` | `choice` with edges to labels |

A quest objective is never a step type of its own: the step describes the work - kill these, collect that, go there, click this - and `quest = { id, n }` says which objective it is for (QUEST WORK in the example). An objective step whose target is not known yet gives only the quest pair: it is titled from the client's objective text and finished by the objective.

Titles are rendered at display time from the step and the names the client gives: quests, items, spells and factions by ID. NPCs are the exception, since no API names a creature the player has not seen, so a guide names its NPCs in `npcs`, by the map they are on. An NPC the guide visits is written `{ name = "Tonga Runetotem", at = { 5226, 3193 }, note = "Upstairs in the inn." }`: `at` is a point, a list of the spots it may be at, or a place point; `note`, when given, is shown above the step's own note on every visit; `instance` marks one inside a dungeon. A step that visits an NPC with no `at` of its own goes where `npcs` says that NPC stands; a step's own `at` wins, which is how an escort's end is placed. Monsters and anyone never visited are their name alone. The names of every loaded guide are shared at run time, so two guides naming one ID must agree (the tests check it). An ID nothing names shows as `quest 870` or `NPC 3448` until the client resolves it.

Points are hundredths of a map percent: `{ 5226, 3193 }` is 52.26, 31.93. A point may carry its own `map = 1454`, and a section carries `map` for its whole span; otherwise the guide's `map` applies. A step's `at` is a list of points: the first is the arrow target and every one is an equal target (see Circuits and waits). `radius`, in hundredths too, overrides the per-type arrival radius (a visit 200, a travel 300, an objective 500). The arrow reads that map fraction in yards once the client can size the map and caps it at 7 yards, so a 5% radius on a zone-sized map does not announce arrival hundreds of yards out; inside it the arrow gives way to a pin icon that hops in place, rather than pointing at the player's own feet. Flattened positions include each group member; sections and group wrappers consume none.

## Conditions

Two fields decide whether a step is in the guide for a character at all, and both take a condition table:

- `cond`: who the character is, which never changes - `class`, `race`, `faction`, `season`, `hardcore`. Read once, when the guide loads.
- `show`: what the character has chosen, which can change - `skill` (a SkillLine ID: knows the profession), `ah` and `selffound` (the player's answers under Options -> About your realm). Read when the guide reaches the step: if it does not hold, the step is passed over rather than waited on.

```lua
cond = { class = { "WARRIOR", "SHAMAN" }, race = "orc" }   -- every key must hold; a list is any of them
cond = { none = { { race = "tauren" } } }                   -- none of them
cond = { any = { { race = "troll" }, { class = "MAGE" } } } -- at least one
show = { is = "noAH" }                                      -- a named condition from data.conds
```

Both sit on the guide, a section, a group, or a step, and a step's own and every one around it must all hold. A condition that fails on class, race, faction, season, or hardcore leaves the step out for that character: no row, no number, no room on the progress bar. A quest whose every accept step is out of the guide takes its other steps out with it.

Expand turns a condition into a predicate tree on the node (`node.condition`). Two more terms come from a step's own fields, never from a condition: an `optional` turn-in passes unless one of its quests is ready to hand in, and an accept from an item passes when the item is not in the bags (the rare that drops it was never met). They are marked `derived = true`, and the editor keeps them as they are.

Each predicate kind is evaluated by a function `API/Client.lua` registers with `Client:RegisterPredicate(kind, evaluate)`: `class`, `race`, `faction`, `season`, `hardcore`, `profession`, `auctionHouse`, `selfFound`, and `quest` and `item` for the derived terms. That registry is the list of what a condition may say: `Data/Schema.lua` validates conditions against it, so a kind nothing implements is refused at load rather than passing forever.

Evaluation is three-valued. `true` and `false` are answers; `nil` means the client cannot say, which on a beta client is the common case. `all` is false as soon as one child is and true only when every child is; `any` is its mirror; `not` leaves unknown alone. Progress treats unknown as met, so a check that could not run never hides a step. The realm answers stay unanswered until the player gives them, so a guide that branches on one shows both branches rather than hiding work behind a question nobody asked.

## Items

Four step types put an item in the bags, and they differ by where it comes from, because that is what the player has to go and do:

- `gather` is a gathering profession's work, or the auction house. The step says so and takes either.
- `buy` is one named vendor's stock. The vendor is the step's `npc`, and the title names them, because the next vendor over does not sell it.
- `craft` is output the player will use or sell: five sharpening stones are five sharpening stones.
- `collect` is everything else: quest items, drops, things on the ground.

Any of them may carry `upto = { skill, rank }`, the profession rank that makes the step moot; a crafting guide's gather steps name the craft's profession. The step is then done on the items **or** the rank, whichever comes first, because past that rank the materials are not wanted at all. This is the escape Zygor and RestedXP put on every materials step of a profession guide, where the counts are estimates and a run of lucky skill-ups should not leave the player farming ore they will never use. It expands to an `any` observed completion and is said out loud on the goal line ("Gather 20 Copper Ore with Mining or Mining 150"), not hidden, so a step going green early is never a mystery. A step the client cannot judge on its own has nothing to escape from and is refused at load.

`skillup` is the fifth, and it is not about the item at all. It is the skill-up grind, where the number made is whatever the rank takes and a lucky run of skill-ups should finish the step early; both `skill` and `rank` are required on it, and it completes on the rank.

## Carried steps

Not every instruction deserves a stop. "Travel through the cave" belongs with the step it prepares for, and "kill Owatanka if he turns up" belongs with all of them. Three fields say so, and a step carrying `with` or `sticky` is never the current step: the flow walks past it and the tracker draws it on the card under whatever step is current.

```lua
{ type = "travel", to = "Through the cave", with = "bristlebacks", at = { { 5967, 8333 } } },
{ type = "collect", item = 4770, quest = { 757, 1 }, label = "bristlebacks", at = { { 5933, 7834 } } },
{ type = "accept", quests = { 884 }, item = 5102, kill = { 3473 }, sticky = true,
  note = "If you see Owatanka, kill him: his tailspike starts a quest." },
```

`with` names a `label` further on: the step rides along with it. Naming an earlier step, or one that does not exist, is an error at load. The carried step is done when the step that carries it is - skipped when it is skipped - and its own rule still counts, so whichever lands first finishes it.

`sticky = true` carries a step alongside every step after it until it is done, rather than tying it to one.

`from = label` is background work written once, where it is finished: the step rides on the card from the labelled earlier step until it is done, or until the guide reaches it and it becomes the current step (the drops off creatures fought for other reasons).

## Circuits and waits

When a step's `at` is a list, every point is an equal target and the arrow takes whichever is nearest, so a player who is already beside a later point is not sent back to the first. Every point gets a map pin carrying the step's number. `loop = true` marks the list as a circuit (RestedXP's #loop); it is kept for ported guides and changes nothing, since every list behaves that way.

`wait = 8` says the step keeps the player waiting about that many seconds - a scene playing out, a timed quest starting. It is shown, never enforced.

## The item to press

```lua
{ type = "collect", item = 4703, kill = { 2989, 2990 }, quest = { 746, 1 }, use = { 4702 } },
```

`use` names the items the step asks the player to press. It is often not the item the step counts: this step counts Broken Tools and presses Prospector's Picks, because smashing a looted pick at the forge is what yields a tool. Only the guide can know which of the items in play is the one to press, so it is written rather than guessed; RestedXP writes the same thing as `.use`.

It gates nothing and completes nothing. Its only effect is that, while the item is in the player's bags, the item panel beside the tracker offers it as a button they can click or bind. NuuRoad never presses it for them. The IDs also join the step's item references, so the audit covers them.

It does, though, title an objective step that is nothing but a press. Cleansing a well or planting a seed counts nothing and kills nothing, and such a quest often carries no objective line in the quest log at all, so the step would otherwise read "Thunderhorn Cleansing, objective 1". With a `use` it reads `Use Thunderhorn Cleansing Totem`, with the item as an item - its quality colour, its tooltip, its link - and the line wears the item's own icon rather than a quest mark. It beats the client's objective line, which says whether the thing is done rather than what to do, and `object`'s "Click". It never beats a count: a step with a count to keep is titled by the count, which is why the Bael'dun step still leads with the tools. The press joins that same line rather than taking one of its own, and leads it, since it is what the player does first - "Use Prospector's Pick from Bael'dun Digger and Bael'dun Appraiser, and Collect 5 Broken Tools", "Use Cenarion Lunardust, and Kill Lunaclaw", where the press is what summons the thing to kill. A `kill` on such a step is where the pressed item comes from, not where the counted one does: the diggers carry the picks, and the tools are what the forge makes of them.

An item with no `use` still reaches the panel when the client says it has a use of its own, or when the step's `starts` says it begins a quest - a quest starter carries no use spell for the client to report.

## Arrival by name

A `travel` step normally completes on reaching its coordinate. Where the real target is an area, the client's own name for it is better:

```lua
{ type = "travel", to = "Bloodhoof Village", area = 222, at = { { 4735, 6070 } } },
{ type = "travel", to = "The Barrens", zone = 1413, at = { { 6960, 6040 } } },
```

The coordinate still points the arrow; the area or zone decides when the step is done. An area is compared by name - the client's (`C_Map.GetAreaInfo`) where it answers, otherwise `Data/IDNames.lua`, which `Tools/IDNames.py` writes from the client's tables - and a zone by the player's map ID.

## Level by a later step

A grind step usually wants the player at a level by some later step, with the turn-ins in between doing part of the work. Rather than working out by hand how far into a lower level to grind (`level = 13, xp = 9200`, "so the turn-ins bring you to 14"), name the step the level is needed by and let the tracker do the sum:

```lua
{ type = "level", level = 14, by = "ratchet", at = { { 5300, 2240 } }, note = "Grind here so the turn-ins before Ratchet bring you to 14." },
...
{ title = "Ratchet", label = "ratchet", steps = { ... } },
```

`by` names a `label` on a later step, group, or section, resolved at load like `with`; an earlier step, a missing label, or `xp` beside it (the level is the one needed at that step, so it takes no experience of its own) is an error. The step is done once the player's experience plus the experience of the turn-ins still ahead of them reaches the level. A turn-in counts when it sits after the grind step and before the named one, is open to the character now (its condition holds), has not been handed in, and its quest is in the log or is accepted by a step in the same stretch; a quest the player skipped is not counted. What a quest gives is the client's figure for a quest in the log, else what this account saw it give before, on the quest's offer or at its turn-in. A turn-in whose experience is still unknown is left out, so the player grinds a little more rather than arriving short, and the tracker says how many it left out: "Reach level 14 by step 57 (1300 XP, ~14 kills, 1 turn-in not counted)".

## Level on a pickup

`level` on an `accept`, or on a `talk` that accepts, is the level its quests are taken from:

```lua
{ type = "talk", turnin = { 894 }, accept = { 900 }, level = 15, object = "Control Console" },
```

The step shows "Reach level 15", with the experience still needed, on the line before the accepts and after any turn-ins, which may be what brings it. It gates nothing: the client will not give the quests any sooner, so the step waits on the accept as always. To stop the guide itself until a level, write a level step.

## Explicit quest groups

Wrap two or more quest visits, or quest objectives done in one place, that should be available together:

```lua
{ title = "Crossroads", steps = {
    { group = {
        { type = "talk", turnin = { 871 }, accept = { 872, 5041 }, npc = { 3429 } },
        { type = "accept", quests = { 867 }, npc = { 3449 } },
        { type = "talk", turnin = { 844 }, accept = { 845 }, npc = { 3338 } },
    } },
    { type = "finish", note = "Finished visiting the Crossroads." },
} },
```

This produces four nodes, one section spanning them, and `groups = { { first = 1, last = 3 } }`. A group holds `group` and optionally `label`, `cond` and `show`. Members keep their own conditions, NPCs, locations, notes, and completion rules. Ranges must be ordered, disjoint, contain at least two consecutive `acceptQuest`, `turnInQuest`, `talk`, `kill`, `collect`, `interact`, or `questObjective` nodes (or any other step that finishes a quest objective), and stay within one section. Kill and objective steps are grouped when their mobs share a camp (the three Razormane kinds of Thorn Hill), and a pickup joins the kills around it (Baron Longshore's head with the Southsea pirates): each target gets its own marker, and a kill counts for the member that names the creature. Members cannot branch. Nested groups are rejected.

The tracker and NPC conveniences use the current member and the available members after it in that same range. Each member can complete independently; progress advances through finished leading members. Back/Forward and the arrow still refer to individual steps. Ungrouped steps stand alone, even when adjacent or at the same NPC. Distance, map APIs, and a fixed member limit never determine membership. A group does not imply that prerequisite quests are already offered.

Saving from the editor clears the guide's session progress and restamps `updated`. The character's saved resume point stores a step position and that stamp; a changed or missing stamp discards the position and allows a fresh scan.

## Materials

Any step may carry `needs`, the materials the player has to bring to it:

```lua
{ type = "craft", item = 2862, count = 5, skill = 164,
  needs = { { item = 2835, count = 5 }, { item = 2320, count = 2, source = "vendor" }, { item = 2589, count = 2, source = "ah" } } }
```

The count is the whole step's, not per item made, so what the author writes is what the list asks for. `source` is one of `gather` (the default), `vendor`, `ah`, `drop`, or `craft`, and it is part of the step: a written guide states it, and a guide the profession planner generates fills it from the recipe data and the player's own price book. Nothing reads the auction house, and nothing buys, searches, or posts anything. Materials expand to `node.needs = { { itemID, count, source } }` and join `node.refs.items`, so they are audited like every other ID.

`Domain/Materials.lua` adds them up from the current step to the end of the guide, skipping steps already finished and steps the character is gated out of, and subtracts what is in the bags. A guide with `materials = "section"` stops the list at the end of the section holding the current step, for a guide whose every section begins with its own shopping (a profession route the planner splits by tier, recipe or rank band sets it). `"guide"`, or nothing, is the whole guide ahead. A step that is only partly done still counts in full: the guide cannot know how much of its work is left, and asking for too much is recoverable while arriving short is not. The tracker shows the current step's own materials under its goals, and the panel beside it shows the whole remaining list grouped by source.

## Farming circuits

A circuit is an edge back to an earlier step, usually the option of a `choice`:

```lua
{ title = "Copper circuit", steps = {
    { type = "travel", to = "Copper vein, north road", label = "circuit", at = { { 4890, 2540 }, { 5010, 2280 } } },
    { type = "gather", item = 2770, count = 20, skill = 186 },
    { type = "choice", text = "Another lap around the veins?", options = {
        { text = "Run the circuit again", go = "circuit" },
        { text = "Done farming", go = "done" },
    } },
    { type = "finish", note = "Bags full.", label = "done" },
} },
```

Taking an option whose label sits behind the choice starts a new lap: every step from the destination through the step just finished goes back to undone, and its kills, crafts, and NPCs talked to are cleared, so the loop can be run again. Steps before the destination and after the step that jumped are untouched, and the trail keeps every step walked so `<` still steps back through the laps already run. The tracker shows `LAP 2` beside the step count from the second lap on. There is no circuit wrapper and no repeat count: a loop with no way out is an authoring mistake, so give the player an exit, which a `choice` does.

## Places

A guide can describe the way through a place the packaged travel data does not know: a cave, a tunnel, a ramp, a building with one door. `places` sits in `data` beside `sections`; the travel arrow follows it instead of pointing through rock, and it applies to every step of the guide (a step never names a place to be led in or out of it).

```lua
places = {
    { id = "windfury", name = "Windfury cave", width = 15, map = 1413,
      points = {
          { id = "mouth", at = { 4010, 2030 }, kind = "entrance", label = "the north mouth" },
          { id = "crossroads", at = { 4030, 2210 }, label = "the crossroads" },
          { id = "ledge", at = { 4270, 2360 }, label = "the ledge" },
          { id = "chamber", at = { 4040, 2450 } },
          { id = "hole", at = { 4060, 2600 }, kind = "exit", label = "the hole to the river" },
      },
      links = {
          { from = "mouth", to = "crossroads" }, { from = "crossroads", to = "ledge" },
          { from = "crossroads", to = "chamber" }, { from = "ledge", to = "chamber", oneway = true },
          { from = "chamber", to = "hole" },
      },
    },
},
```

- `id`: unique in the guide, ASCII, no dot. `name`: what the tracker says ("Enter Windfury cave by the north mouth"). `width`: how many yards from a link still count as inside, 5 to 60 (default 20). `map`: the map of its points (default the guide's).
- `points`: each `{ id, at, kind, label }`. `kind = "entrance"` walks in or out; `kind = "exit"` only out (a hole, a drop: put it where the player lands); no kind is a point inside. `label` is what the arrow says ("Go to the gallery"); without one it shows the place's name and the distance. `id` is unique in its place, one word, no dot, not a number.
- `links`: `{ from, to }` (both ways) or `{ from, to, oneway = true }` (`from` to `to` only), by point id. Links are the only walks inside a place; loops and junctions need no syntax.
- A step stands on a point with `stand = "windfury.chamber"`: the point's coordinates become the step's. A step with its own coordinates can add `near = "windfury.chamber"`, which joins it to that point's passages rather than whichever passage is nearest, for levels that lie over each other on the map. An NPC's `at` may be `"windfury.chamber"`, or `"windfury"` for any point of the place.

At runtime a place keeps its points (`at` in map percentages) and its links as `connections = { { a, b, oneWay } }`; that is the shape the editor's Places panel edits and SavedVariables stores. Validation, reported at load like a bad label: unique place IDs and point IDs, ASCII, no dots; every link end names a point, no point joined to itself, and the same two points joined both one way and both ways are errors (a plain repeat is merged, and the editor says so); at least one entrance; every point reachable from an entrance and able to reach an entrance or exit; width 5 to 60; every step `stand` or `near` names a place point.

At runtime the location carries `point` (the `"place.point"` a step stands on) and `near` beside the usual fields.

## Completion and progress

These are runtime shapes, built by Expand; nothing below is written in a guide.

`completion = { type = "manual" }` waits for the player. `completion = { type = "observed", observed = ... }` advances automatically when the client reports the declared state; supported observations are `always`, `location` (arrival as the arrow measures it: in yards once the map can be sized, the nearest of the step's points, the 7-yard cap or the step's own yard radius, also from a neighbouring map on the same continent through world coordinates, never during a flight, and checked five times a second while the step waits on it), `zone` (`mapID`), `subzone` (`name`), `instance` (`instanceID`), `level` (`atLeast`, optional `xp`, optional `by`, a later step's position), `objective` (`questID`, `index`, one objective line), `item` (`itemID`, `count`, bags plus bank; optional `startsQuestID` for an item that begins a quest, satisfied once that quest was accepted or finished, or `questID` for a quest item, satisfied once that quest is ready to turn in or finished and moot when the player has no such quest), `hearth` (`name`), `flightpath` (`name`, recorded per character from the taxi map), `kills` (`npcs`, `count`; killing blows counted per step from the combat log), `skill` (`name`, `atLeast`; the rank read from the skill window or the profession slots), `spell` (`ids`), `cast` (`spellID`, `count`), `crafted` (`itemID`, `count`; crafts counted per step from the client's create message, or that many already in the bags), `equipped` (`itemID`; the equipment slots, which bag counts never see), `reputation` (`factionID`, `standing` from 1 to 8), `step` (a carried step's carrier), `all` (`children`, every child observation), `any` (`children`, the first child observation to land; what `upto` expands to), and `quests` (`ids`, `state` of `accepted`, `readyToTurnIn`, `finished`, or `acceptedOrFinished`, optional `match = "any"`). The quest and map APIs behind these are unverified on Forever; see `docs/api-compatibility.md`.

Guide progress is kept in memory for the session only and never saved; the load-time scan places the player afresh at every login. Per character, only the active guide and the flight paths learned are saved. Progress uses step indexes for `currentStep`, `holdStep`, the trail, and per-step tables. It holds a status per node (`complete`, `observed`, or `skipped`), the current node, a trail of nodes the player has moved past, the kills counted for each step (`kills`), the items crafted on each step (`crafts`), the laps run around each circuit (`laps`), and the NPCs the player has opened a dialog with on each step (`talked`). `<` walks back along the trail and holds observed auto-advance on that step until the player presses `>` or completes it. `>` keeps a finished status or records a skip and holds the next step; Shift-`>` releases it and runs the load-time scan from it. Only `complete` and `observed` count toward the progress figure.

## NPCs

Every creature a step references is followed while that step is current. The step's kill targets (`kill` on a quest objective, collect, or kill step) and its `mark` creatures are marked skull, cross, square, moon, triangle, diamond, and circle in the order listed; every other referenced NPC (`npc`) is marked with a star. A mark is set by the player's own click or keypress (a slot of the target strip, its Mark all button, or the NuuRoad mark keys), and on sight where the client still allows an addon to set one, only when the unit carries no mark yet. Kills are counted per step from the combat log and a dialog opened with a step's NPC turns its "Talk to" line green. All of it is optional (Options -> NPC conveniences) and unverified on Forever; see `docs/api-compatibility.md`.

## Navigation

The location shape is `{ mapID, x, y, arrivalRadiusNormalized, spots }`, where `spots` is an optional list of `{ x, y }` secondary points. When the client reports the map's world size, distances display in yards and bearings use the true map proportions; otherwise the tracker shows a percentage of the map and applies a conventional aspect correction. `map = 0` is reserved for portable fixtures and resolves to the player's current map; packaged guides must use a real map ID.

Run `lua Tests/TestRunner.lua` from the addon root when a standalone Lua interpreter is available. The suite covers valid data, dangling numeric edges, group validation and editing, nested predicates, branch selection, back/forward, reset, arrow bearing math, and the observed-completion matcher.
