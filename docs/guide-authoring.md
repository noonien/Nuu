# Guide authoring: tips and tricks

Practical advice for writing NuuRoad guides, by hand in `NuuRoad/Data/Guides/` or in the in-game editor.
This is not the reference. For what every field means, see:

- [`NuuRoad/docs/examples/guide-v1.lua`](../NuuRoad/docs/examples/guide-v1.lua): guide format v1, the one format
  guides are written in: every step type, condition and field, with one worked example of each.
- [`NuuRoad/docs/guide-schema.md`](../NuuRoad/docs/guide-schema.md): how each part of the format behaves once the
  addon reads it, and the runtime shapes under it.
- [`NuuRoad/docs/authoring.md`](../NuuRoad/docs/authoring.md): the editor, the tracker, and how a step behaves in play.
- [`NuuRoad/GUIDE_PORTING_PLAN.md`](../NuuRoad/GUIDE_PORTING_PLAN.md): the rules for porting from RestedXP and Zygor.

The best worked example is [`HordeTirisfal612.lua`](../NuuRoad/Data/Guides/HordeTirisfal612.lua). Read its header
comment and first few sections before you start a new guide.

## The workflow in one list

1. Pick the route and its source (your own play, a session recording, or an authorized RestedXP/Zygor guide).
2. Create the file, register it in `NuuRoad.toc`, and fill in the header comment as you go.
3. Write the steps section by section, checking every ID against the database as you write it.
4. Add every NPC the guide names to its `npcs`, and every area, flight node and skill to `Data/IDNames.lua` by
   running `python3 Tools/IDNames.py`.
5. Run the tests, `Tools/CheckGroups.lua`, and `Tools/CompareGuideOrder.lua` for a RestedXP port.
6. Play it in the client with **Debug log** on, run `/nuuroad audit`, and fix what it reports.
7. Play it again on a character that is part way through, so you exercise the resume scan.

## Starting a file

Copy the shape of an existing guide:

```lua
-- What the route is, where it came from, and what was checked against what.
--
-- Notes:
--   * Every place you depart from the source on purpose, and why.
--
-- Maps: 1420 Tirisfal Glades (guide default), 1458 Undercity.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    schema = 1,

    id = "nuuroad:leveling:horde-tirisfal-6-12",
    updated = 1790640000,
    title = "Brill and the Undercity",
    category = "Leveling/Tirisfal Glades",
    author = "NuuRoad",
    tags = { "horde", "undead", "tirisfal" },
    levels = { from = 6, to = 12 },
    cond = { faction = "Horde" },

    data = {
        map = 1420,
        sections = { ... },
        npcs = { ... },
    },
})
```

- **IDs** follow `nuuroad:<kind>:<slug>` (`leveling`, `dungeon`, `class`, `fixture`). Never change an ID once it has
  shipped: saved resume points use it.
- **`updated`** is seconds since the epoch (`date +%s`). Bump it whenever you add, remove or reorder steps. A changed
  stamp discards players' saved resume position, which is what you want when step positions have moved.
- **`category`** is the browser folder path. Leave the faction out of it; the guide's `cond` decides who sees it.
  Test guides go under `Fixtures/`.
- **`map`** in `data` is the default. Give a section its own `map` when the whole section is in a city, and a
  single point `map = ...` for the odd point elsewhere. Forgetting a map sends the arrow to the right numbers in the
  wrong zone.
- **Register the file** in `NuuRoad.toc` with the other `Data/Guides` files. `Steps:Expand` reads each one at
  login; `Tests/BuiltInGuideTests.lua` and `Tests/GuideFormatTests.lua` read every guide listed there.
- **The header comment** is where deviations from the source live. Reviewers and tools (`CompareGuideOrder`,
  `CheckGroups`) report candidates, not verdicts, and the header is how the next author knows a report was
  considered and kept on purpose.

## Getting IDs right

Forever is not Classic. Quests, NPCs and items that look familiar can have new IDs, and Forever adds content of its
own. Most porting bugs are wrong IDs.

- **Check every ID as you write it**, not afterwards. Look it up in `db/horde/` (`quests.json`, `npcs.json`,
  `items.json`, `objects.json`), which merges Questie, ForeverGuide's in-game scan, RestedXP, the client tables and our own in-game data
  (`db/ingame/`, from NuuExperiments' quest-scan and quest-record).
  `db/horde/REPORT.md` says what each zone is missing.
- **For new Forever NPCs and items**, check ForeverGuide's scan (`db/sources/ForeverGuide`) and the client item table.
- **Places, flight paths and skills are IDs too**: an AreaTable ID (`area`), a TaxiNodes ID (`node`) and a SkillLine
  ID (`skill`), from `db/sources/wago/forever`. Run `python3 Tools/IDNames.py` after adding one: it writes their
  names to `Data/IDNames.lua`, and stops on an ID it cannot name. A skill line it does not list goes in its table.
- **Never guess an ID from a name.** When no ID is known, say so: write one step that names the creatures in its
  `note` rather than inventing one step per kill line (the Tirisfal guide does this for the Cult of the Damned).
- **Do not take data straight from cMaNGOS, VMaNGOS or TrinityCore.** Questie's database is fine.
- **Name every NPC in `npcs`**, under the map it is on: `npcs = { [1420] = { [1496] = ..., [1515] = "Rotting Dead" } }`.
  Quests, items and spells are not named: the client names them in the player's language. Two guides naming one NPC
  must agree. The tests fail on any title that reads `NPC 5678`.
- **Say once where each NPC you visit stands**, in its entry: `[1496] = { name = "Deathguard Dillinger", at = { 5820,
  5145 } }`. Steps that visit the NPC then leave `at` out. An NPC that stands in one of two places takes a list of
  points (the arrow takes the nearest); one on a point of a guide place takes `at = "cave.chamber"`; one inside a
  dungeon takes `instance` and a `note` saying where. Something true of every visit ("Upstairs in the inn.") goes
  in the entry's `note`, shown above the step's own note. The tests fail on a step that repeats its NPC's point.

## Writing steps

### Let the type do the talking

Every step has a `type`, and its title writes itself. `{ type = "accept", quests = { 404 }, npc = { 1496 } }`
already reads "Accept A Putrid Task from Deathguard Dillinger". Use `note` only for what the line cannot say: where
exactly someone stands, which floor of the inn, what to do if something went wrong.

Good notes are short, concrete and plain ASCII:

- "Gretchen Dedmar is on the second floor of the inn."
- "Skip it if you never picked it up."
- "The Stiletto costs 3 silver 81 copper. Equip it."

### Quest visits

- **Always put `npc` on accepts and turn-ins.** It gives the card its "Talk to" line, lets the target strip mark the
  NPC, and lets the audit catch a quest handed in somewhere else.
- **Combine a hand-in and the next pickup at one NPC** into one visit:
  `{ type = "talk", turnin = { 383 }, accept = { 427, 99141 }, npc = { 1515 } }`. A `talk` with neither is a plain
  visit, such as a trainer: "Talk to ...", ticked off by the player.
- **A turn-in the player may not be ready for** (an optional letter, a quest from another start zone) is
  `optional = true`: passed over on arrival unless a quest is ready, never waited on.
- **Wrap a hub in a `group`** so the player sees one card and can talk to the givers in any order. Groups stay
  within a section and cannot branch.

### Quest work

- **There is no objective step.** A step says what the work is (`kill`, `collect`, `interact`, `travel`) and
  `quest = { id, n }` which objective it is for. It is done when the client says the objective is, and the count is
  the client's: no `count` on such a step.
- **Loot is a `collect`, not a `kill`.** An objective looted from mobs names the item and the mobs
  (`{ type = "collect", item = 5087, kill = { 2955 }, quest = { 844, 1 } }`), so it reads "Collect 7 Plainstrider
  Beak from Plainstrider". A `kill` step whose note says "loot" or "drop" fails the tests.
- **One objective is one kind of creature or item**, so a quest asking for two kinds is two steps, usually grouped.
- **Use `object`** for things picked up off the ground or clicked ("Collect 6 Dry Branch from Dry Branch").
- **Use `use`** for the item the player has to press. It is often not the item being counted.
- **Items that start a quest** get `starts = <quest>`; **quest items with no objective line** get `quest = <quest>`.
  The step is then judged by the quest log rather than the bags, and the resume scan treats it correctly.
- **An accept from an item** (`item`, no `npc`) passes when the item is not in the bags. Add `kill` and
  `sticky = true` for a rare whose drop starts a quest.

### Camps and pickups along the way

- **Kills in one camp belong in one group**, so every target is marked at once and each keeps its own count.
- **A walk on the way to something else** is `with = "<label>"`: it rides on that step's card and never stops the
  guide.
- **Something to do whenever the chance comes** ("use the Motivator on any Deathguard") is `sticky = true`.
- **Background work** (drops off creatures fought for other reasons) is written once, where it is finished, with
  `from = "<label>"` naming the earlier step where it starts. It rides on the card from there until it is done or
  the guide reaches it.
- **Creatures to mark without counting them** (a grind spot's mobs, a beast to tame) go in `mark`.

### Places and points

- **Points are hundredths of a map percent**: 52.26, 31.93 on the map is `{ 5226, 3193 }`, and a radius of 2% of the
  map is `radius = 200`.
- **Roaming NPCs and spawn areas** take a list of points: `at = { { x, y }, { x, y }, ... }`. The arrow goes to the
  nearest one, so a player already at a later point is not sent back. Order the points along the path the player
  walks. Gordo in Tirisfal is the example: a list along the road he patrols.
- **Widen `radius` for areas** (400 to 600 for a camp or a town) and leave the default for a single NPC.
- **Arriving in a town, zone or dungeon** is better judged by ID: `area = 159` (Brill), `zone = 1458` (a map) or
  `instance = 43` (a dungeon) on a travel step.
- **Caves and tunnels** want a `places` entry so the arrow does not point through rock. Walk the cave with
  **Menu -> Authoring -> Place recorder** rather than writing points by hand.

### Levels and grinding

Do not work out by hand how far into a level to grind. Name the step the level is needed by and let the tracker
count the turn-ins in between:

```lua
{ type = "level", level = 14, by = "ratchet", at = { { 5300, 2240 } },
  note = "Grind here so the turn-ins before Ratchet bring you to 14." },
```

## Conditions

- **`cond` is who the character is**: class, race, faction, season, hardcore. A step whose `cond` fails is not in
  the guide for that character at all.
- **`show` is what the character has chosen**: a profession (`skill`), or the realm answers under Options
  (`ah`, `selffound`). It is read when the guide reaches the step, and the step is passed over if it does not hold.
- **Nothing else gates a step.** There are no level, gold, item or quest conditions: a step waits by its own nature
  (a turn-in for the quest to be ready, a train step for the skill) and the player presses Skip. Say in the note
  when skipping is expected ("Skip this if you took another book.").
- **Put a condition on the section or group** when all of its steps share it.
- **The realm answers** stay unknown until the player sets them in Options. Both branches show until then, so write
  both so they make sense on their own.

## Things a guide never says

The Nuu addons are player-directed. A guide tells the player what to do and leaves the doing to them.

- **Never tell the player to die.** A corpse-run shortcut becomes an ordinary travel step, with the shortcut
  mentioned in a note for softcore players at most.
- **No macros, frame names, scripts or Lua functions** in any field.
- **No automation.** Target marking, quest accept and turn-in, and junk selling are player-controlled conveniences in
  Options. The guide provides IDs, never actions.
- **ASCII only**, and sentence case in titles and notes.
- **Collapse busywork.** Eight vendor and trainer stops for a self-made wand read better as one note than eight
  steps. Keep a step when it has something to observe (a purchase, a quest, a skill rank).
- **Do not ask twice for something the tracker cannot tell apart.** The Tirisfal port keeps only the second of two
  identical trainer visits because a trainer step cannot tell whether the ranks were already bought.

## Porting from RestedXP or Zygor

- **Follow the source's order** unless you have a reason not to, and record the reason in the header.
- **Check the source's coordinates.** Ports have found campfires that point into another continent and NPCs placed
  in the wrong zone. When the source and `db/horde` disagree, stand where the NPC actually is in the client.
- **RestedXP files hold the same route several times** (per experience rate, per season). Know which `#name` you
  are porting from.
- **Run the source audit** to see what the source uses that the format cannot express yet:
  `lua Tools/GuidePort/Audit.lua "<source guide>.lua"`.
- **Leave out steps that only make sense for someone else's route**, such as abandoning quests from a start zone this
  character never saw.

## Checking your work outside the client

From `NuuRoad/`:

```sh
# Full test suite; reads and validates every guide in the TOC
nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"

# Steps next to each other that look like one stop but are not grouped
nix-shell -p lua5_1 --run "lua Tools/CheckGroups.lua Data/Guides/HordeTirisfal612.lua"

# Order and map check against the RestedXP source (RestedXP ports only)
nix-shell -p lua5_1 --run "lua Tools/CompareGuideOrder.lua Data/Guides/HordeTirisfal612.lua \
  '<path to RXPGuides>/Guides/Forever/<file>.lua' '6-12 Tirisfal Glades'"
```

`CompareGuideOrder` has caught steps ported in the wrong order (sending the player east and back again) and a
dropped `map` (Thunder Bluff steps pointing into Mulgore). `CheckGroups` has caught a named mob ported as its own
step ahead of the camp it stands in. Read the source around each report before you move anything.

Add a block for a new guide to `Tests/BuiltInGuideTests.lua`, like the Mulgore and Tirisfal ones: it registers, has
the right `cond` and `map`, every step has a title with no raw NPC IDs, and the last step is a `finish`.

## Checking your work in the client

- **Turn on Menu -> Options -> Debug log.** Every auto-advance then reports the quest IDs the next step expects, and
  the `[audit]` checks report any NPC whose live name differs from the guide's `npcs`. Anything you target, mouse
  over, talk to or loot that carries a guide name under a different ID is reported with the right ID.
- **Run `/nuuroad audit`** on a new guide. It checks every quest, item, NPC and objective at once, asks the server
  for anything it does not know yet, and reports IDs that do not exist on this client.
- **Read `/nuuroad log`** for everything the audit found, grouped by guide and character, ready to paste.
- **Leave recording on** (**Menu -> Options -> Recording**). A session log of you playing the route has exact
  positions for every accept, turn-in, kill and loot, which beats reading coordinates off the map.
  `Tools/SessionLog/sessions.py` reads it outside the game.
- **Play the guide twice**: once from a fresh character, and once from one that is part way through, with a quest
  skipped and one done out of order. The resume scan should open on the first step that is really left to do. If it
  stops somewhere odd, a step is probably missing `starts`, `quest` or an `npc`.

## Common mistakes

| Symptom | Likely cause |
| --- | --- |
| A guide is missing at login, "was rejected" | A field `Steps:Expand` refuses; the message names its path in the guide. |
| Title reads `NPC 5678` | NPC missing from the guide's `npcs`. |
| Title reads `quest 1234` outside the client | Normal: the client names quests. In the client it means a wrong ID. |
| Title reads "<quest>, objective 1" | Step with `quest = { id, n }` and no `item`, `kill`, `object`, `npc`, `use` or `mark`. |
| "Kill Rotting Dead" for a loot objective | Used `kill` where the step should `collect` the item. |
| Arrow points somewhere in the wrong zone | Missing `map` on the section or point. |
| Card is red, "You do not have this quest" | Accept step missing before it, or the accept is gated out for this character. |
| Guide waits on a turn-in the player may not have | Turn-in without `optional = true`. |
| Players' saved position lands on the wrong step | Steps reordered without bumping `updated`. |
| Audit says the quest was handed in elsewhere | Wrong `npc` on the turn-in, or the source used the Classic ID. |
| Resume scan skips past work the player has not done | Quest item or starter without `quest` / `starts`. |
