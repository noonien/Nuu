# Guide authoring: tips and tricks

Practical advice for writing NuuRoad guides, whether by hand in `NuuRoad/Data/BuiltIn/` or in the in-game editor.
This is not the reference. For what every field means, see:

- [`NuuRoad/docs/guide-schema.md`](../NuuRoad/docs/guide-schema.md): the v2 format, every verb, condition and field.
- [`NuuRoad/docs/authoring.md`](../NuuRoad/docs/authoring.md): the editor, the tracker, and how a step behaves in play.
- [`NuuRoad/GUIDE_PORTING_PLAN.md`](../NuuRoad/GUIDE_PORTING_PLAN.md): the rules for porting from RestedXP and Zygor.

The best worked example is [`HordeTirisfal612.lua`](../NuuRoad/Data/BuiltIn/HordeTirisfal612.lua). Read its header
comment and first few sections before you start a new guide.

## The workflow in one list

1. Pick the route and its source (your own play, a session recording, or an authorized RestedXP/Zygor guide).
2. Create the file, register it in `NuuRoad.toc`, and fill in the header comment as you go.
3. Write the steps section by section, checking every ID against the database as you write it.
4. Add every name the guide uses to `Data/Names.lua`.
5. Run the tests, `Tools/CheckGroups.lua`, and `Tools/CompareGuideOrder.lua` for a RestedXP port.
6. Play it in the client with **Debug log** on, run `/nuuroad audit`, and fix what it reports.
7. Play it again on a character that is part way through, so you exercise the resume scan.

## Starting a file

Copy the shape of an existing guide:

```lua
local _, ns = ...

-- What the route is, where it came from, and what was checked against what.
--
-- Notes:
--   * Every place you depart from the source on purpose, and why.
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1420 Tirisfal Glades (guide default), 1458 Undercity.
ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:leveling:horde-tirisfal-6-12"] = {
    schema = 2,
    id = "nuuroad:leveling:horde-tirisfal-6-12",
    updated = 1790640000,
    map = 1420,
    only = "Horde",
    meta = { title = "Horde 6-12: Tirisfal Glades", author = "NuuRoad", category = "Leveling/Tirisfal Glades",
             tags = { "horde", "undead", "tirisfal" }, levels = { 6, 12 } },
    steps = { ... },
}
```

- **IDs** follow `nuuroad:<kind>:<slug>` (`leveling`, `dungeon`, `class`, `fixture`). Never change an ID once it has
  shipped: saved resume points use it.
- **`updated`** is seconds since the epoch (`date +%s`). Bump it whenever you add, remove or reorder steps. A changed
  stamp discards players' saved resume position, which is what you want when step positions have moved.
- **`category`** is the browser folder path. Leave the faction out of it; the guide's `only` decides who sees it.
  Test guides go under `Fixtures/`.
- **`map`** on the guide is the default. Give a section its own `map` when the whole section is in a city, and a
  single point `map = ...` for the odd step elsewhere. Forgetting a map sends the arrow to the right numbers in the
  wrong zone.
- **Register the file** in `NuuRoad.toc` with the other `Data/BuiltIn` guides, before the fixtures.
  `Tests/BuiltInGuideTests.lua` validates every guide listed there.
- **The header comment** is where deviations from the source live. Reviewers and tools (`CompareGuideOrder`,
  `CheckGroups`) report candidates, not verdicts, and the header is how the next author knows a report was
  considered and kept on purpose.

## Getting IDs right

Forever is not Classic. Quests, NPCs and items that look familiar can have new IDs, and Forever adds content of its
own. Most porting bugs are wrong IDs.

- **Check every ID as you write it**, not afterwards. Look it up in `db/horde/` (`quests.json`, `npcs.json`,
  `items.json`, `objects.json`), which merges Questie, ForeverGuide's in-game scan, RestedXP and the client tables.
  `db/horde/REPORT.md` says what each zone is missing.
- **For new Forever NPCs and items**, check ForeverGuide's scan (`db/sources/ForeverGuide`) and the client item table.
- **Never guess an ID from a name.** When no ID is known, say so: write one step that names the creatures in its
  `note` rather than inventing one step per kill line (the Tirisfal guide does this for the Cult of the Damned).
- **Do not take data straight from cMaNGOS, VMaNGOS or TrinityCore.** Questie's database is fine.
- **Add every name to `Data/Names.lua`**, in the right table: `npcs`, `quests`, `items`, `factions` or `spells`.
  The client only answers name lookups for creatures it has seen this session, so without the table a fresh login
  shows `quest 870` or `NPC 3448`. The tests fail on any title that still reads like that.

## Writing steps

### Let the verb do the talking

One verb per step, and let the title generate itself. `{ accept = 404, npc = 1496, at = { 58.20, 51.45 } }` already
reads "Accept A Putrid Task from Deathguard Dillinger". Use `note` only for what the line cannot say: where exactly
someone stands, which floor of the inn, what to do if something went wrong.

Good notes are short, concrete and plain ASCII:

- "Gretchen Dedmar is on the second floor of the inn."
- "Skip it if you never picked it up."
- "The Stiletto costs 3 silver 81 copper. Equip it."

### Quest visits

- **Always put `npc` on accepts and turn-ins.** It gives the card its "Talk to" line, lets the target strip mark the
  NPC, and lets the audit catch a quest handed in somewhere else.
- **Combine a hand-in and the next pickup at one NPC** into one visit:
  `{ turnin = 383, accept = { 427, 99141 }, npc = 1515, at = { ... } }`.
- **Wrap a hub in a `group`** so the player sees one card and can talk to the givers in any order. Groups stay
  within a section and cannot branch.

### Objectives

- **Loot is a `collect`, not a `kill`.** An objective looted from mobs names the item with `collect` and the mobs
  with `kill`, so it reads "Collect 7 Putrid Claw from Rotting Dead and Ravaged Corpse". A `kill`-only step whose
  note says "loot" or "drop" fails the tests.
- **Give objective steps `part`, `collect`/`kill` and `count`**, so the tracker can name the target and show the
  count. A step with nothing of its own reads "<quest>, objective 1" until the quest is in the log.
- **Use `object`** for things picked up off the ground or clicked ("Collect 6 Dry Branch from Dry Branch").
- **Use `use`** for the item the player has to press. It is often not the item being counted.
- **Items that start a quest** get `starts = <quest>`; **quest items** get `quest = <quest>`. The step is then judged
  by the quest log rather than the bags, and the resume scan treats it correctly.

### Camps and pickups along the way

- **Kills in one camp belong in one group**, so every target is marked at once and each keeps its own count.
- **A pickup that happens on the way to something else** is `with = "next"`: it rides on the next step's card and
  never stops the guide.
- **Something to do whenever the chance comes** ("use the Motivator on any Deathguard") is `sticky = true`.
- **Quest work spread over several sections** is a `track` / `untrack` pair. Every `track` must be closed by the end
  of the guide; the tests check it.
- **A rare worth stopping for** is `watch = <npc>`. It gates nothing.

### Places and points

- **Roaming NPCs and spawn areas** take a list of points: `at = { { x, y }, { x, y }, ... }`. The arrow goes to the
  nearest one, so a player already at a later point is not sent back. Order the points along the path the player
  walks. Gordo in Tirisfal is the example: a list along the road he patrols.
- **Widen `radius` for areas** (0.04 to 0.06 for a camp or a town) and leave the default for a single NPC.
- **Arriving in a town or zone** is better judged by name: `{ travel = "Brill", subzone = "Brill", at = { ... } }`.
- **Caves and tunnels** want a `places` entry so the arrow does not point through rock. Walk the cave with
  **Menu -> Authoring -> Place recorder** rather than writing points by hand.
- **Coordinates are map percentages** with two decimals, as the client's map shows them.

### Levels and grinding

Do not work out by hand how far into a level to grind. Name the step the level is needed by and let the tracker
count the turn-ins in between:

```lua
{ level = 14, by = "ratchet", at = { 53.0, 22.4 }, note = "Grind here so the turn-ins before Ratchet bring you to 14." },
```

## Conditions

- **Prefer keywords over `when`.** `only = "Warrior | now gold 100"` reads as words in the tracker, can be edited in
  the editor and is checked by the audit. A Lua `when` can do none of that.
- **Know the difference between "never" and "not yet".** Class, race, faction, season and hardcore remove a step
  for that character entirely. Level, quest, item and gold keep the step and make the guide wait on it.
- **Use `now` for optional steps.** `only = "Rogue | now slot 16 dps < 3.3 | now gold 381"` offers the Stiletto only
  to a rogue whose weapon is worse and who can pay for it when they arrive; otherwise the guide passes the step over
  rather than waiting. Use `now level 6` for a quest the player may not be high enough for yet, with a note saying
  they will pass by again.
- **For a quest the player may or may not have** (an optional letter, a quest from another start zone), write
  "Skip it if you do not have it" in the note. The card turns red and waits, and the note tells them what to do.
- **The realm answers** (`xprate`, `auctionhouse`, `selffound`) stay unknown until the player sets them in Options.
  Both branches show until then, so write both so they make sense on their own.

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
# Full test suite; validates every guide in the TOC
nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"

# Steps next to each other that look like one stop but are not grouped
nix-shell -p lua5_1 --run "lua Tools/CheckGroups.lua Data/BuiltIn/HordeTirisfal612.lua"

# Order and map check against the RestedXP source (RestedXP ports only)
nix-shell -p lua5_1 --run "lua Tools/CompareGuideOrder.lua Data/BuiltIn/HordeTirisfal612.lua \
  '<path to RXPGuides>/Guides/Forever/<file>.lua' '6-12 Tirisfal Glades'"
```

`CompareGuideOrder` has caught steps ported in the wrong order (sending the player east and back again) and a
dropped `map` (Thunder Bluff steps pointing into Mulgore). `CheckGroups` has caught a named mob ported as its own
step ahead of the camp it stands in. Read the source around each report before you move anything.

Add a block for a new guide to `Tests/BuiltInGuideTests.lua`, like the Mulgore and Tirisfal ones: it registers, has
the right `only` and `map`, every step has a title with no raw IDs, every `track` is closed, and the last step is a
`finish`.

## Checking your work in the client

- **Turn on Menu -> Options -> Debug log.** Every auto-advance then reports the quest IDs the next step expects, and
  the `[audit]` checks report any quest, NPC or item whose live name differs from `Data/Names.lua`. Anything you
  target, mouse over, talk to or loot that carries a guide name under a different ID is reported with the right ID.
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
| Title reads `quest 1234` or `NPC 5678` | Name missing from `Data/Names.lua`, or in the wrong table. |
| Title reads "<quest>, objective 1" | Objective step with no `collect`, `kill`, `npc` or `use`. |
| "Kill Rotting Dead" for a loot objective | Used `kill` where the step should `collect` the item. |
| Arrow points somewhere in the wrong zone | Missing `map` on the section or point. |
| Card is red, "You do not have this quest" | Accept step missing before it, or the accept is gated out for this character. |
| Guide waits forever on a purchase | Optional step without `now` in its `only`. |
| Players' saved position lands on the wrong step | Steps reordered without bumping `updated`. |
| Audit says the quest was handed in elsewhere | Wrong `npc` on the turn-in, or the source used the Classic ID. |
| Resume scan skips past work the player has not done | Quest item or starter without `quest` / `starts`. |
