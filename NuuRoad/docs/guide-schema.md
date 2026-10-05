# Guide format v2

v2 is what `Data/Steps.lua` expands: what the editor writes, what the fixtures in `Dev/Fixtures` are written in, and what `Data/Import.lua` turns a guide in the export format into. The packaged guides in `Data/Guides` are written in the export format (`docs/examples/guide-export.lua`); see [Read from the export format](#read-from-the-export-format) for the fields v2 gained for them. It is not the shape the addon runs on. `Data/Steps.lua` converts a guide once, on the way in, and everything downstream sees runtime nodes. Anything derived - titles, step positions, section and group spans, reference lists, completion rules - is built during that conversion and never authored.

A guide requires `schema = 2`, a stable `id`, `updated` (seconds since the epoch), `meta` with a `title` and `category`, and `steps`, a list of sections. It may carry a guide-level `map`, an `only` condition, and in `meta`: `author`, `tags`, `levels = { from, to }`, `source`, and `materials` (`"section"` or `"guide"`, see Materials).

`category` is where the guide browser files the guide: a path of folders, outermost first, split on `/` and as deep as it needs to be (`"Leveling/Kalimdor/The Barrens"`, `"Dungeons/Wailing Caverns"`, or one word). Spaces around a `/` are ignored, folders match without regard to case, and every folder must have a name, so a leading, trailing, or doubled `/` is rejected. Packaged guides do not put the faction in the path: the browser checks the guide's `only` against the character instead. Test and regression guides go under a top folder named `Fixtures`, which the browser hides unless the debug log is on.

```lua
{
    schema = 2,
    id = "nuuroad:leveling:horde-barrens-13-21",
    updated = 1789862400,
    map = 1413,
    only = "Horde",
    meta = { title = "The Barrens", author = "NuuRoad", category = "Leveling/The Barrens",
             tags = { "horde", "barrens" }, levels = { 13, 21 }, source = "..." },
    steps = {
        { section = "Crossroads", steps = { ... } },
        { section = "Orgrimmar", map = 1454, steps = { ... } },
    },
}
```

`updated` replaces a revision counter: the client stamps it with `time()`, prints it with `date()`, and comparing two copies is a subtraction. It settles which copy is newer and tells a player when a guide last changed, where a counter needed its own prior value to increment.

Steps run in order; there is no `next` and no authored step position. A branch is a `choice` whose options name labels: any step, group, or section may carry `label = "..."`, and an option says `goto = "<label>"`. The importer resolves labels to flattened positions, and a label behind the choice runs that stretch again, which is how a farming circuit is written. Two things sharing one label, or a `goto` naming a label that does not exist, is an error at load.

The importer rejects authored step IDs, `next` or `goto` on a step, a step outside a section, an empty section, malformed groups, an unknown verb, and an unresolvable label. The validator then rejects invalid node kinds, group ranges, predicate trees, cyclic tables, executable values, and observed location completions on nodes without a location.

## Steps

Each step is one table whose single verb key names the kind. There is no `id`, `title`, `kind`, or `completion` field; text goes in `note`, either as a step of its own or on the step it describes. Every field name is one word.

| Step | Expands to |
| --- | --- |
| `{ note = "..." }` | manual `note` with the text as body; on any other step, `note` is that step's body instead |
| `{ travel = "Ratchet", at = { x, y } }` or `{ travel = { x, y } }` | `travel`, completes on arrival |
| `{ accept = 870, npc = 3448, at = { x, y } }` | `acceptQuest`, completes when accepted or finished |
| `{ turnin = { 870, 845 }, npc = 3448, at = { x, y } }` | `turnInQuest`, completes when every quest is finished |
| `{ turnin = 871, accept = { 872, 5041 }, npc = 3429, at = { x, y } }` | `talk`, one visit; completes when the turn-ins are finished and the accepts are in the log |
| `{ objective = 821, part = 2, at = { x, y } }` | `questObjective` for one objective line, shown with the client's progress text |
| `{ objective = 870, any = 848, at = { x, y } }` | `questObjective`, ready to turn in (`any` widens the match) |
| `{ objectives = { 871, 844 }, at = { x, y } }` | `objectiveGroup`, all ready to turn in |
| `{ escort = 99144, npc = 275954, at = { x, y } }` | `escort`, ready to turn in; titled "Escort <npc>", and `npc` (required) is followed and marked like any step's NPC. `at` is where the escort ends. When the client reports the quest failed (the NPC died), the line turns red and the card says to abandon the quest and take it again |
| `{ objective = 871, part = 1, kill = 3267, count = 8 }` | as above; `kill` and `count` give the fallback title "Kill 8 ..." and list the mobs in `refs` |
| `{ objective = 844, part = 1, collect = 5087, count = 7 }` | as above with "Collect 7 ..."; `collect` wins over `kill` in the title, and a `kill` beside it is named as the drop's source ("Collect 7 Plainstrider Beak from Greater Plainstrider and Fleeting Plainstrider"). An `object` beside it is named the same way, since such a step carries no "at" of its own ("Collect 4 Fungal Spores from Laden Mushroom"), and an `npc` on an objective with nothing to count reads "Talk to ..." An objective that is looted from kills always names its item: `kill` alone reads "Kill ..." and the tracker cannot tell the loot from the kills. `Tests/BuiltInGuideTests.lua` fails a packaged objective step with `kill`, no `collect`, and a note that says loot or drop, and `/nuuroad audit` reports a `kill`-only step for a line the client calls an item |
| `{ collect = 4926, object = "Chen's Empty Keg", at = { x, y } }` | `collect`, completes when the item is in bags (`count`, default 1) |
| `{ collect = 4926, starts = 819, object = "Chen's Empty Keg" }` | `collect` of an item that begins quest 819: also complete once that quest was ever accepted, and never passed over by the resume scan |
| `{ collect = 4986, quest = 924, object = "Flawed Power Stones" }` | `collect` of a quest item for quest 924: also complete once the quest is ready to turn in or finished, moot (waited on, not passed over) when the player has no such quest |
| `{ kill = { 3244, 3245 }, count = 3, at = { x, y } }` | `kill` with no quest behind it; completes when the combat log shows that many killing blows by the player, their pet, or their party on those creatures (`count`, default 1). A `collect` step with `kill` stays a collect step, and names those creatures as where the item drops |
| `{ hearth = "The Crossroads", npc = 3934, at = { x, y } }` | `hearth`, completes when the bind location matches |
| `{ flight = "Ratchet", npc = 16227, at = { x, y } }` | `flight`, completes once the taxi map or the "new flight path" message shows it learned |
| `{ track = 869 }` / `{ untrack = 869 }` | `reminder`, auto-passes; between them the tracker shows the quest's first unfinished objective under every step while it is in the log |
| `{ object = "Control Console", turnin = 894, accept = 900 }` | any step: the interaction target, appended to the title or shown as a "Click:" line |
| `{ object = "Altar of Fire", at = { x, y } }` | `interact`, manual |
| `{ objective = 844, at = { { 53, 22.4 }, { 47.4, 26.4 }, { 48.4, 29.6 } } }` | a list of points: the first is the arrow target, the rest are pins on the world map and the minimap |
| `{ train = "Mining", npc = 3357, at = { x, y } }` | `train`; completes once the client reports any rank in that skill |
| `{ train = "Mining", rank = 75, npc = 3357 }` | as above, waiting for that rank: the next trainer visit |
| `{ learn = { 100, 772 }, npc = 251964, at = { x, y } }` | `train` for class spells, by spell ID (one, or a list); completes once the client knows every one (`IsPlayerSpell`). Titled "Train Charge and Rend from Blademaster Ren", names from the guide's `names.spells`. A later rank is its own ID |
| `{ cast = 1259686, at = { x, y } }` | `cast`; completes on a cast of that spell (`count`, default 1) made while the guide is on the step, counted from `UNIT_SPELLCAST_SUCCEEDED`. For RestedXP's `.cast`: Skysight at a convergence. A cast before the step was reached does not count, so pair it with `now cooldown <spell>` to pass over a spell already used |
| `{ skill = "Mining", rank = 150 }` | `skillTarget`; the goal line shows the live rank against the target |
| `{ gather = 2770, count = 20, skill = "Mining", at = { x, y } }` | `gather`; pick, mine, or skin that many. Completes on the item in the bags however it arrived, so buying it at the auction house counts. `skill` is the gathering profession |
| `{ craft = 2862, count = 5, skill = "Blacksmithing" }` | `craft`; counts the client's "You create:" messages on this step, and is also done once that many are in the bags. `skill` is the profession, shown as "using Blacksmithing" |
| `{ skillup = 2862, skill = "Blacksmithing", rank = 100 }` | `skillUp`; make that item over and over until the rank lands, however many that takes. Done on the rank, not on a count |
| `{ buy = 2320, count = 10, npc = 3134, at = { x, y } }` | `buy`; from the vendor in `npc`, who is named in the step ("from Zargh"). Completes when the items are in the bags |
| `{ equip = 7360 }` | `equip`; reads the equipment slots, not the bags |
| `{ reputation = 576, standing = "Honored" }` | `reputationTarget`; the standing is authored by name and stored as 1 (Hated) to 8 (Exalted) |
| `{ craft = 2862, count = 5, needs = { { 2835, 5 }, { 2589, 2, "ah" } } }` | any step: the materials it asks the player to bring, added up into the materials list |
| `{ level = 17 }` or `{ level = 13, xp = 9200 }` | `levelTarget`, optionally level plus experience into it |
| `{ level = 14, by = "ratchet" }` | `levelTarget` that counts the turn-ins ahead: see Level by a later step |
| `{ vendor = "sell", npc = 3072, at = { x, y } }` | `vendor`, manual; `"repair"` and `"sell and repair"` are the other words |
| `{ choice = "...", options = { { "Label", goto = "name" } } }` | `choice` with edges to labels |
| `{ finish = "..." }` | manual `end` with the text as body |

## Conditions

Any step may carry `only`, a condition string. `|` joins groups that must all hold, and ` or ` joins the terms of one group: `"Mage | level 4 | gold 100"` is a Mage at level 4 with a silver, `"Alliance | Mage or Druid"` an Alliance Mage or Druid, and `"not Warrior | not Druid"` neither of the two. Inside one group, negated terms are AND-ed with the rest (`"not Tauren or Orc"` is an Orc who is not a Tauren). The expander turns it into a `condition` predicate. A step whose condition fails on class, race, faction, season, or hardcore alone is not in the guide for that character: no row, no number, no room on the progress bar. The flow also passes over a step whose condition can never hold again, a settled `not` term such as `not quest 858` once the quest is taken. A step waiting on something the player can still gain - a quest to take or finish, a level, gold, an item - is stopped on: the guide waits there until it opens or the player presses Skip.

A term written with `now` in front (`"now item 247840"`, `"Hunter | now level 4 | now gold 200"`, `"not now aura 1254832"`) is read as it stands when the guide reaches the step and is never waited on: if it does not hold, the flow passes over the step, recorded as skipped. Use it for a step that only applies to players who already have something - the book they picked as a reward, the gold for a trainer visit, a cooldown that is ready - the way RestedXP's `.itemcount`, `.money`, `.xp <N,1`, `.cooldown` and `.train` gates skip a step. It changes nothing else: the tracker shows and evaluates the term as the term it wraps.

| `only` term | Predicate |
| --- | --- |
| `"Warrior"`, `"Warrior or Shaman"` | `class` |
| `"Tauren"`, `"Orc or Troll"`, `"not Tauren"`, `"Skyborne"` | `race`; Skyborne is Forever's own race and can be either faction |
| `"Horde"` | `faction` |
| `"quest 858"` (in the log or finished), `"not quest 819"` | `quest` |
| `"quest 858 accepted"`, `"quest 858 finished"`, `"quest 858 readyToTurnIn"` | `quest` with a state |
| `"level 10"` | `level`, at least |
| `"experience 3020"` | `experience` |
| `"season 2"`, `"season"` | `season`; unknown where the client has no season API |
| `"hardcore"` | `hardcore` |
| `"instance"` | `instance` |
| `"skill Mining 75"`, `"skill Mining"` | `skill`; the name keeps its capitalization |
| `"profession Skinning"` | `profession`, any rank at all |
| `"item 2495"`, `"item 2495 x3"` | `item`, counted in bags |
| `"equipped 2495"` | `equippedItem` |
| `"spell 8017"` | `spell` |
| `"gold 5000"` | `gold`, in copper |
| `"reputation 576 Honored"` | `reputation` |
| `"zone 1412"` | `zone` |
| `"subzone Bloodhoof Village"` | `subzone`, the name under the minimap |
| `"hearth Bloodhoof Village"` | `hearth`, where the stone already points |
| `"aura 408828"` | `aura` |
| `"cooldown 6948"`, `"cooldown item 6948"` | `cooldown`, ready |
| `"slot 16 dps < 4.2"`, `"slot 16 quality < 7"` | `slot`: what is worn there is worse than what the step offers. An empty slot is worse than anything |
| `"xprate < 1.5"`, `"xprate >= 1.5"` | `xprate` |
| `"auctionhouse"` | `auctionHouse` |
| `"selffound"` | `selfFound` |

A guide carries `only` the same way, for the whole guide.

The last three are answers no API can give: how fast the realm grants experience, whether the player uses the auction house, and whether they play self found. The player gives them once under Options -> About your realm, and they stay unanswered until then, so a guide that branches on one shows both branches rather than hiding work behind a question nobody asked.

Each term names a predicate that `API/Client.lua` registers with `Client:RegisterPredicate(kind, evaluate)`. That registry is the list of what a condition may say: `Data/Schema.lua` validates authored conditions against it, so a kind nothing implements is refused at load rather than passing forever. Adding a condition is one evaluator and one entry in the `only` table in `Data/Steps.lua`.

Evaluation is three-valued. `true` and `false` are answers; `nil` means the client cannot say, which on a beta client is the common case. `all` is false as soon as one child is and true only when every child is; `any` is its mirror; `not` leaves unknown alone. Progress treats unknown as met, so a check that could not run never hides a step.

### The Lua fallback

`when` is a step field holding one Lua expression, for a condition no registered kind covers:

```lua
{ note = "...", only = "Warrior", when = "level() >= 10 and itemCount(2495) == 0" }
```

`only` and `when` are AND-ed when both are present. The expression is a string, not a function: guide tables still carry nothing executable, so they serialize into SavedVariables, validate, and render in the editor.

It is compiled as `return (<body>)`, so any statement - a loop, an assignment, a function definition - is a syntax error and an expression cannot spin the client. It runs in a sandbox with no `_G`: a name the sandbox does not define is nil, not the real global. The game is reachable through `level()`, `class()`, `race()`, `faction()`, `questInLog(id)`, `questFinished(id)`, `questReady(id)`, `itemCount(id)`, `equipped(id)`, `skill(name)`, `standing(factionID)`, `money()`, `zone()`, `season()`, and `api(name, ...)`, which resolves against an allowlist of read-only calls in `API/Client.lua`. Nothing a guide writes can send, sell, delete, target, or move anything. A body that will not compile, exceeds 400 characters, is not ASCII, or names one of the forbidden identifiers is refused by `Schema:Validate` at load; at runtime an error is unknown, not false.

Prefer a registered kind. A predicate used twice belongs in `RegisterPredicate`, where the tracker, the editor, and the audit can name it; `when` is the one-off that never will be.

Four verbs put an item in the bags, and they differ by where it comes from, because that is what the player has to go and do:

- `gather` is a gathering profession's work, or the auction house. The step says so and takes either.
- `buy` is one named vendor's stock. The vendor is the step's `npc`, and the title names them, because the next vendor over does not sell it.
- `craft` is output the player will use or sell: five sharpening stones are five sharpening stones.
- `collect` is everything else: quest items, drops, things on the ground.

Any of them may carry `upto`, the profession rank that makes the step moot: `upto = 150` for the step's own profession, `upto = { "Blacksmithing", 100 }` for another one, which is what a crafting guide's gather steps need. The step is then done on the items **or** the rank, whichever comes first, because past that rank the materials are not wanted at all. This is the escape Zygor and RestedXP put on every materials step of a profession guide, where the counts are estimates and a run of lucky skill-ups should not leave the player farming ore they will never use. It expands to an `any` observed completion and is said out loud on the goal line ("Gather 20 Copper Ore with Mining or Mining 150"), not hidden, so a step going green early is never a mystery. A step the client cannot judge on its own has nothing to escape from and is refused at load.

`skillup` is the fifth, and it is not about the item at all. It is the skill-up grind, where the number made is whatever the rank takes and a lucky run of skill-ups should finish the step early; both `skill` and `rank` are required on it, and it completes on the rank.

A step naming both a profession verb and `skill` keeps the verb: the `skill` is the profession it uses. `rank` belongs to `train` and `skill`, `standing` to `reputation`, and `count` to `craft` and `buy` as it does to `collect` and `kill`. Faction IDs are named in the guide's `names` like every other ID; standings are the client's own eight, so `"Honored"` is written out and an unknown word is refused at load.

`at` is one point `{ x, y }` or a list of points whose first is the arrow target and whose rest are map pins. A point may carry its own `map = 1454`, and a section carries `map` for its whole span; otherwise the guide's `map` applies. A step itself has no `map`. A step that visits an NPC (`npc`) with no `at` of its own goes where the guide's `names.npcs` says that NPC stands (below); a step's own `at` wins, which is how an escort's end or an NPC that walks is placed. Coordinates may be percentages or normalized; `radius` overrides the per-verb arrival radius (talk steps 0.02, travel 0.03, objectives 0.05). The arrow reads that map fraction in yards once the client can size the map and caps it at 7 yards, so a 5% radius on a zone-sized map does not announce arrival hundreds of yards out; inside it the arrow gives way to a pin icon that hops in place, rather than pointing at the player's own feet. `npc` and `item` accept one ID or a list and land in `refs`. Flattened positions include each group member; sections and group wrappers consume none. Nothing authored refers to a position: branches name labels.

Titles are rendered at display time from the verb and the names in the guide's `names` table: `names = { npcs = { [3448] = "Tonga Runetotem" }, quests = { [870] = "The Forgotten Pools" }, items = {}, factions = {}, spells = {} }`, any kind left out. An NPC the guide visits is written `[3448] = { "Tonga Runetotem", at = { 52.26, 31.93 }, note = "Upstairs in the inn." }`: `at` is one point, on the guide's map unless it carries `map` (a section's map does not apply), and `note`, when given, is shown above the step's own note on every visit. Monsters and anyone never visited are their name alone. A guide names every ID it uses, so it stands on its own; the names of every loaded guide are shared at run time, so two guides naming one ID must agree (the tests check both). The client's quest title and creature tooltip lookups override the table when they answer. An ID missing from the table shows as `quest 870` or `NPC 3448` until the client resolves it, so add every referenced quest and quest giver to the table when porting.

## Read from the export format

`Data/Import.lua` writes v2 for a guide in the export format, and uses a few fields an author of v2 would not:

| Field | Meaning |
| --- | --- |
| `{ talk = true, npc = 3344 }` | a visit with nothing to hand in or take (a trainer): "Talk to ...", manual |
| `quest = { 870, 1 }` on a travel, buy, or escort step | done when the client says that objective is; a travel step only then, since the arrival starts what the objective ends |
| `quest = 924` on a travel, buy, or escort step | also done once the quest is ready to hand in |
| `zone = 1454` (a number) on a travel step | arrival is the player's map ID, not a zone name |
| `instance = 43` on a travel step | arrival is entering that dungeon (GetInstanceInfo's instance ID) |
| `from = "beaks"` | carried on the card from the labelled earlier step until done or reached, where it is an ordinary step |
| `mark = { 2955, 2956 }` | creatures marked and listed as targets; their kills count for nothing |
| `say = { 41231 }` | gossip option IDs to pick on a talk step, kept on the node; nothing reads them yet |

`only` takes a predicate tree as well as text, which is what the import writes; `show` conditions are wrapped in `now`. An objective step's `count` may be left out: `Steps:Count` asks the client how many the objective needs. A group may also hold any step that finishes a quest objective. An NPC entry in `names.npcs` may give a list of points or a place point as its `at`, and `instance` for one inside a dungeon.

## Carried steps

Not every instruction deserves a stop. "Travel through the cave" belongs with the step it prepares for, and "kill Owatanka if he turns up" belongs with all of them. Two fields say so, and neither is ever the current step: the flow walks past them and the tracker draws them on the card under whatever step is current.

```lua
{ travel = "Through the cave", with = "next", at = { 59.67, 83.33 } },
{ objective = 757, part = 1, collect = 4770, count = 12, at = { 63.93, 78.34 } },
{ collect = 5102, starts = 884, kill = 3473, sticky = true, note = "If you see Owatanka, kill him: his tailspike starts a quest." },
```

`with` names the step this one rides along with: `"next"` for the following step, or any `label` further on. Naming an earlier step, or one that does not exist, is an error at load. The carried step is done when the step that carries it is - skipped when it is skipped - and its own rule still counts, so whichever lands first finishes it.

`sticky = true` carries a step alongside every step after it until it is done, rather than tying it to one.

## Circuits and waits

When a step's `at` is a list, every point is an equal target and the arrow takes whichever is nearest, so a player who is already beside a later point is not sent back to the first. Every point gets a map pin carrying the step's number. `loop = true` marks the list as a circuit (RestedXP's #loop); it is kept for ported guides and changes nothing, since every list behaves that way.

`wait = 8` says the step keeps the player waiting about that many seconds - a scene playing out, a timed quest starting. It is shown, never enforced.

## The item to press

```lua
{ objective = 746, part = 1, collect = 4703, count = 5, kill = { 2989, 2990 }, use = 4702 },
```

`use = 4702` (or a list) names the item the step asks the player to press. It is often not the item the step counts: this step counts Broken Tools and presses Prospector's Picks, because smashing a looted pick at the forge is what yields a tool. Only the guide can know which of the items in play is the one to press, so it is authored rather than guessed; RestedXP writes the same thing as `.use`.

It gates nothing and completes nothing. Its only effect is that, while the item is in the player's bags, the item panel beside the tracker offers it as a button they can click or bind. NuuRoad never presses it for them. The IDs also join the step's item references, so the audit and the guide's `names` cover them.

It does, though, title an objective step that is nothing but a press. Cleansing a well or planting a seed counts nothing and kills nothing, and such a quest often carries no objective line in the quest log at all, so the step would otherwise read "Thunderhorn Cleansing, objective 1". With a `use` it reads `Use Thunderhorn Cleansing Totem`, with the item as an item - its quality colour, its tooltip, its link - and the line wears the item's own icon rather than a quest mark. It beats the client's objective line, which says whether the thing is done rather than what to do, and `object`'s "Click". It never beats `collect` or `kill`: a step with a count to keep is titled by the count, which is why the Bael'dun step still leads with the tools. The press joins that same line rather than taking one of its own, and leads it, since it is what the player does first - "Use Prospector's Pick from Bael'dun Digger and Bael'dun Appraiser, and Collect 5 Broken Tools", "Use Cenarion Lunardust, and Kill Lunaclaw", where the press is what summons the thing to kill. A `kill` on such a step is where the pressed item comes from, not where the counted one does: the diggers carry the picks, and the tools are what the forge makes of them.

An item with no `use` still reaches the panel when the client says it has a use of its own, or when the step's `starts` says it begins a quest - a quest starter carries no use spell for the client to report.

## Arrival by name

A `travel` step normally completes on reaching its coordinate. Where the real target is an area, the client's own name for it is better:

```lua
{ travel = "Bloodhoof Village", subzone = "Bloodhoof Village", at = { 47.35, 60.70 } },
{ travel = "The Barrens", zone = "The Barrens", at = { 69.60, 60.40 } },
```

The coordinate still points the arrow; the name decides when the step is done.

## Level by a later step

A grind step usually wants the player at a level by some later step, with the turn-ins in between doing part of the work. Rather than working out by hand how far into a lower level to grind (`{ level = 13, xp = 9200 }`, "so the turn-ins bring you to 14"), name the step the level is needed by and let the tracker do the sum:

```lua
{ level = 14, by = "ratchet", at = { 53.0, 22.4 }, note = "Grind here so the turn-ins before Ratchet bring you to 14." },
...
{ section = "Ratchet", label = "ratchet", steps = { ... } },
```

`by` names a `label` on a later step, group, or section, resolved at load like `with`; an earlier step, a missing label, or `xp` beside it (the level is the one needed at that step, so it takes no experience of its own) is an error. The step is done once the player's experience plus the experience of the turn-ins still ahead of them reaches the level. A turn-in counts when it sits after the grind step and before the named one, is open to the character now (its `only` holds), has not been handed in, and its quest is in the log or is accepted by a step in the same stretch; a quest the player skipped is not counted. What a quest gives is the client's figure for a quest in the log, else what this account saw it give before, on the quest's offer or at its turn-in. A turn-in whose experience is still unknown is left out, so the player grinds a little more rather than arriving short, and the tracker says how many it left out: "Reach level 14 by step 57 (1300 XP, ~14 kills, 1 turn-in not counted)".

## Explicit quest groups

Wrap two or more quest visits, or quest objectives done in one place, that should be available together:

```lua
steps = {
  { section = "Crossroads", steps = {
        { turnin = 871, accept = { 872, 5041 }, npc = 3429, at = { 51.50, 30.87 } },
        { accept = 867, npc = 3449, at = { 51.62, 30.89 } },
        { turnin = 844, accept = 845, npc = 3338, at = { 52.24, 31.01 } },
    } },
    { finish = "Finished visiting the Crossroads." },
  } },
}
```

This produces four nodes, one section spanning them, and
`groups = { { first = 1, last = 3 } }`. A group wrapper holds `group` and an
optional `label`. Members keep their own conditions, NPCs,
locations, notes, and completion rules. Expanded guides may author these ranges
directly. Ranges must be ordered, disjoint, contain at least two consecutive
`acceptQuest`, `turnInQuest`, `talk`, `kill`, `collect`, `interact`, or `questObjective` nodes, and stay within one
section. Kill and objective steps are grouped when their mobs share a camp (the three Razormane kinds of
Thorn Hill), and a pickup joins the kills around it (Baron Longshore's head with the Southsea pirates): each target
gets its own marker, and a kill counts for the member that names the creature.
Members cannot branch. Nested groups, and sections inside groups, are rejected.

The tracker and NPC conveniences use the current member and the available
members after it in that same range. Each member can complete independently;
progress advances through finished leading members. Back/Forward and the arrow
still refer to individual steps. Ungrouped steps stand alone, even when adjacent
or at the same NPC. Distance, map APIs, and a fixed member limit never determine
membership. A group does not imply that prerequisite quests are already offered.

Saving from the editor clears the guide's session progress and restamps
`updated`. The character's saved resume point stores a step position and that
stamp; a changed or missing stamp discards the position and allows a fresh scan.
No converter is provided from the earlier format: the packaged guides were
converted by hand, and until the beta client restored SavedVariables nothing
authored had ever persisted.

## Materials

Any step may carry `needs`, the materials the player has to bring to it:

```lua
{ craft = 2862, count = 5, needs = { { 2835, 5 }, { 2320, 2, "vendor" }, { 2589, 2, "ah" } } }
```

Each entry is `{ itemID, count, source }`. The count is the whole step's, not
per item made, so what the author writes is what the list asks for. `source`
is one of `gather` (the default), `vendor`, `ah`, `drop`, or `craft`, and it
is part of the step: a written guide authors it, and a guide the profession
planner generates fills it from the recipe data and the player's own price
book. Nothing reads the auction house, and nothing buys, searches, or posts
anything. Materials expand to
`node.needs = { { itemID, count, source } }` and join `node.refs.items`, so
they are named from the guide's `names` and audited like every other ID.

`Domain/Materials.lua` adds them up from the current step to the end of the
guide, skipping steps already finished and steps the character is gated out
of, and subtracts what is in the bags. A guide with `meta.materials =
"section"` stops the list at the end of the section holding the current step,
for a guide whose every section begins with its own shopping (a profession
route the planner splits by tier, recipe or rank band sets it). `"guide"`, or
nothing, is the whole guide ahead. A step that is only partly done still
counts in full: the guide cannot know how much of its work is left, and
asking for too much is recoverable while arriving short is not. The tracker
shows the current step's own materials under its goals, and the panel
beside it shows the whole remaining list grouped by source.

## Farming circuits

A circuit is an edge back to an earlier step, usually the option of a `choice`:

```lua
{ section = "Copper circuit", steps = {
    { travel = "Copper vein, north road", label = "circuit", at = { { 48.9, 25.4 }, { 50.1, 22.8 } } },
    { gather = 2770, count = 20, skill = "Mining" },
    { choice = "Another lap around the veins?", options = {
        { "Run the circuit again", goto = "circuit" },
        { "Done farming", goto = "done" },
    } },
    { finish = "Bags full.", label = "done" },
} },
```

Taking an option whose label sits behind the choice starts a new lap: every step from the destination
through the step just finished goes back to undone, and its kills, crafts, and
NPCs talked to are cleared, so the loop can be run again. Steps before the
destination and after the step that jumped are untouched, and the trail keeps
every step walked so `<` still steps back through the laps already run. The
tracker shows `LAP 2` beside the step count from the second lap on. There is no `circuit` wrapper and no repeat
count: a loop with no way out is an authoring mistake, so give the player an
exit, which a `choice` does.

## Places

A guide can describe the way through a place the packaged travel data does not know: a cave, a tunnel, a ramp, a building with one door. `places` sits beside `steps`; the travel arrow follows it instead of pointing through rock, and it applies to every step of the guide (a step never names a place to be led in or out of it).

```lua
places = {
    { place = "windfury", name = "Windfury cave", width = 15, map = 1413,
      points = {
          { at = { 40.1, 20.3 }, kind = "entrance", label = "the north mouth" },   -- 1
          { at = { 40.3, 22.1 }, label = "the crossroads" },                       -- 2
          { at = { 42.7, 23.6 }, label = "the ledge" },                            -- 3
          { at = { 40.4, 24.5 }, id = "chamber" },                                 -- 4
          { at = { 40.6, 26.0 }, kind = "exit", label = "the hole to the river" }, -- 5
      },
      connections = { { 1, 2 }, { 2, 3 }, { 2, "chamber" }, { 3, "chamber", true }, { "chamber", 5 } },
    },
},
```

- `place`: an ID, unique in the guide, ASCII, no dot. `name`: what the tracker says ("Enter Windfury cave by the north mouth"). `width`: how many yards from a connection still count as inside, 5 to 60 (default 20). `map`: the map of its points (default the guide's).
- `points`: a plain list. Each point is `{ at = { x, y } }` in map percentages, with optional `kind`, `label`, `id` and `map` (beside `at`, not inside it). `kind = "entrance"` walks in or out; `kind = "exit"` only out (a hole, a drop: put it where the player lands); no kind is a point inside. `label` is what the arrow says ("Go to the gallery"); without one it shows the place's name and the distance. `id` is unique in its place, one word, no dot, not a number.
- `connections`: a plain list of `{ a, b }` (both ways) or `{ a, b, true }` (one way, `a` to `b` only). An end is a point's position in the list or its `id`. Connections are the only walks inside a place; loops and junctions need no syntax. Add new points at the end of the list, so no existing connection changes meaning (the editor renumbers for you).
- A step stands on a point with `at = "windfury.chamber"` (or `"windfury.4"`): the point's coordinates become the step's. A step with its own coordinates can add `near = "windfury.chamber"`, which joins it to that point's passages rather than whichever passage is nearest, for levels that lie over each other on the map.

Validation, reported at load like a bad label: unique place IDs and point IDs, ASCII, no dots; every connection end names a point, no point joined to itself, a third value other than `true`, and the same two points joined both one way and both ways are errors (a plain repeat is merged, and the editor says so); at least one entrance; every point reachable from an entrance and able to reach an entrance or exit; width 5 to 60; every step `at` or `near` string names a place point. Unknown fields on a place or a point are kept.

At runtime the location carries `point` (the `"place.point"` a step stands on) and `near` beside the usual fields.

## Completion and progress

These are runtime shapes, built by the import; nothing below is authored.

`completion = { type = "manual" }` waits for the player. `completion = { type = "observed", observed = ... }` advances automatically when the client reports the declared state; supported observations are `always`, `location` (arrival as the arrow measures it: in yards once the map can be sized, the nearest of the step's points, the 7-yard cap or the step's own yard radius, also from a neighbouring map on the same continent through world coordinates, never during a flight, and checked five times a second while the step waits on it), `level` (`atLeast`, optional `xp`, optional `by`, a later step's position), `objective` (`questID`, `index`, one objective line), `item` (`itemID`, `count`, bags plus bank; optional `startsQuestID` for an item that begins a quest, satisfied once that quest was accepted or finished, or `questID` for a quest item, satisfied once that quest is ready to turn in or finished and moot when the player has no such quest), `hearth` (`name`), `flightpath` (`name`, recorded per character from the taxi map), `kills` (`npcs`, `count`; killing blows counted per step from the combat log), `skill` (`name`, `atLeast`; the rank read from the skill window or the profession slots), `crafted` (`itemID`, `count`; crafts counted per step from the client's create message, or that many already in the bags), `equipped` (`itemID`; the equipment slots, which bag counts never see), `reputation` (`factionID`, `standing` from 1 to 8), `all` (`children`, every child observation), `any` (`children`, the first child observation to land; what `upto` expands to), and `quests` (`ids`, `state` of `accepted`, `readyToTurnIn`, `finished`, or `acceptedOrFinished`, optional `match = "any"`). The quest and map APIs behind these are unverified on Forever; see `docs/api-compatibility.md`.

Guide progress is kept in memory for the session only and never saved; the load-time scan places the player afresh at every login. Per character, only the active guide and the flight paths learned are saved. Progress uses step indexes for `currentStep`, `holdStep`, the trail, and per-step tables. It holds a status per node (`complete`, `observed`, or `skipped`), the current node, a trail of nodes the player has moved past, the kills counted for each step (`kills`), the items crafted on each step (`crafts`), the laps run around each circuit (`laps`), and the NPCs the player has opened a dialog with on each step (`talked`). `<` walks back along the trail and holds observed auto-advance on that step until the player presses `>` or completes it. `>` keeps a finished status or records a skip and holds the next step; Shift-`>` releases it and runs the load-time scan from it. Only `complete` and `observed` count toward the progress figure.

## NPCs

Every creature a step references is followed while that step is current. The step's kill targets (`kill` on a quest objective, collect, or kill step) are marked skull, cross, square, moon, triangle, diamond, and circle in the order listed; every other referenced NPC (`npc`) is marked with a star. A mark is set by the player's own click or keypress (a slot of the target strip, its Mark all button, or the NuuRoad mark keys), and on sight where the client still allows an addon to set one, only when the unit carries no mark yet. Kills are counted per step from the combat log and a dialog opened with a step's NPC turns its "Talk to" line green. All of it is optional (Options -> NPC conveniences) and unverified on Forever; see `docs/api-compatibility.md`.

## Navigation

The location shape is `{ mapID, x, y, arrivalRadiusNormalized, spots }`, where `spots` is an optional list of `{ x, y }` secondary points. When the client reports the map's world size, distances display in yards and bearings use the true map proportions; otherwise the tracker shows a percentage of the map and applies a conventional aspect correction. `mapID = 0` is reserved for portable fixtures and resolves to the player's current map; authored guides must use a real map ID.

Run `lua Tests/TestRunner.lua` from the addon root when a standalone Lua interpreter is available. The suite covers valid data, dangling numeric edges, group validation and editing, nested predicates, branch selection, back/forward, reset, arrow bearing math, and the observed-completion matcher.
