# Tools/ProfData

Build-time tools for the profession planner (`PROF_PLAN.md`). They read the Forever beta client's own tables
offline and write `Data/Professions/<Name>.lua` (in NuuProfessions), one generated recipe table per crafting
profession. Nothing here runs in the game, and the addon never reads the site used for the cross-check. Run them
from the `NuuProfessions` folder.

## Running

Python 3 is enough. The CASC and DB2 readers are OpenRoad's and were not copied: `extract.py` imports them from
`Interface/AddOns/OpenRoad/Tools/ClientMap` (set `CLIENTMAP` to use another copy). CascLib must be built there first
(`Tools/ClientMap/setup.sh`, see `Tools/ClientMap/README.md` in OpenRoad). `crosscheck.py` and `recorded.py` need
neither.

```
python3 Tools/ProfData/extract.py                     # all nine professions at contentLevel 20, margin 5
python3 Tools/ProfData/extract.py --content-level 30  # the next beta cap: a rerun, nothing else
python3 Tools/ProfData/extract.py --only Leatherworking --dry-run   # report only
python3 Tools/ProfData/extract.py --content-level 60 --out Data/ProfessionsFull --table professionDataFull
                                                      # the full-scope testing set (below)
python3 Tools/ProfData/crosscheck.py                  # every disagreement with wowforevertalents.com
python3 Tools/ProfData/crosscheck.py --scope --quiet  # summary, shipped recipes only
```

`extract.py` caches the DB2 tables per build in `.cache/tables-<product>-<build>.pickle` (delete it after a
`db2.py` change) and writes `.cache/extract.json`, every client recipe with the rule that dropped it, which
`crosscheck.py` reads (a run with another `--table` writes `.cache/extract.<table>.json` instead, so the
beta set's cache stays the one cross-checked). `crosscheck.py` downloads each profession page and its category pages into `.cache/` once
(`--refresh` fetches them again). `.cache/` is gitignored.

Check that the output loads in plain Lua 5.1:

```
nix-shell -p lua5_1 --run "lua -e 'local ns = {} loadfile(\"Data/Professions/Leatherworking.lua\")(\"NuuProfessions\", ns) print(ns.professionData.Leatherworking.skillLine)'"
```

### The full-scope testing set

`--out DIR` (default `Data/Professions`, relative to the addon) and `--table NAME` (default `professionData`)
write a second data set beside the beta's. The run above writes `Data/ProfessionsFull/<Name>.lua`, filling
`ns.professionDataFull.<Name>`, with every recipe a level-60 character could train and gather for (training ceiling
300, reagents to item level 65). Its header says it is the full-scope testing set and gives its `contentLevel`.
The planner uses it only behind **Options -> Testing -> Plan past the beta's level cap** (`PROF_PLAN.md`, scope);
the default run and its output are unchanged. `NuuProfessions.toc` loads the files after `Data/Professions`.

Reach it printed (build 1.60.1.70009, 2026-09-25; orange / orange or yellow / before all grey): Leatherworking
300/300/300, Tailoring 300/300/300, Blacksmithing 20/300/300, Alchemy 300/300/300, Enchanting 300/300/300,
Engineering 30/53/300, Cooking 300/300/300, First Aid 30/45/300.

## Sources and provenance

| Table (Forever client, 1.60.1.69977) | What it gives |
| --- | --- |
| `SkillLineAbility` | recipe spell per profession; `TrivialSkillLineRankLow` = yellow, `TrivialSkillLineRankHigh` = grey; `AcquireMethod` 1 = known when the profession is learned, 3 = taken out of the game; `TradeSkillCategoryID` |
| `TradeSkillCategory` | the category named `SEASON OF DISCOVERY` (one per profession): those recipes are dropped |
| `SpellReagents` | reagents and counts |
| `SpellEffect` | `CREATE_ITEM` (24): product; `EffectBasePointsF` is the middle of the number made and `Variance` its spread, min = base * (1 - v/2), max = base * (1 + v/2) (checked against Classic Era's `BasePoints + DieSides` on every multi-made recipe) |
| `ItemEffect` + `ItemXItemEffect` | the item whose `TriggerType` 6 ("on learn") effect is the recipe spell teaches it |
| `ItemSparse` | `SellPrice`, `BuyPrice`, `VendorStackCount`, `ItemLevel`, `RequiredLevel`, `Bonding`; on the recipe item, `RequiredSkillRank` (its learn skill) |
| `SpellName`, `SkillLine` | names, for the reports only (names are never shipped) |

The Classic Era client (`wow_classic_era`, same CASC store) is read for three things only:

- the `forever` mark (below);
- a **trainer** recipe's learn skill, when Classic Era has the recipe in the same profession with the same yellow and
  grey skill levels (Forever's `MinSkillLineRank` is 1 on every recipe; Classic Era's still holds the trainer's
  requirement);
- the row of an item that Forever's `ItemSparse` lacks (the Item table has it; the game fetches such rows from the
  server). Such items carry a comment `-- Classic Era's row` in the output.

The one authored input is `VENDOR` in `extract.py`: trade goods a vendor sells (thread, dye, salt, vials, flux,
spices, stock, rods, milk and water, and Mote of Magic, whose own item text says "Available from enchanting
vendors"). The client cannot tell a vendor good from a drop (`BuyPrice` is set on nearly everything), so this is
Classic knowledge, marked `vendor = true` in the output.

## Output (`Data/Professions/<Name>.lua`)

The field names are the contract with `Domain/ProfessionPlanner.lua`. Keys: `Leatherworking`, `Tailoring`,
`Blacksmithing`, `Alchemy`, `Enchanting`, `Engineering`, `Cooking`, `FirstAid` (no space), and `Mining`: not planned
itself, but its smelting recipes make other professions' bars for a character who has it (`Planner:WithHelpers`).

```lua
ns.professionData.Leatherworking = {
    skillLine = 165, contentLevel = 20,
    recipes = {
        [2152] = { makes = 2304, made = { 1, 1 }, skill levels = { 1, 30, 45, 60 }, reagents = { { 2318, 1 } },
                   learn = "start", forever = "unchanged" },
    },
    items = {
        [2318] = { sell = 15, buy = 60, buyCount = 1, ilvl = 10, reqLevel = 0 },
    },
}
```

| Field | Meaning |
| --- | --- |
| `makes`, `made` | product item and { min, max } made; absent for an enchant (no `CREATE_ITEM`) |
| `skills` | { learn, yellow, green, grey }. Orange runs from learn to yellow - 1 |
| `skills[1]` | `start`: 1. `item`: the recipe item's `RequiredSkillRank` (Classic Era's when Forever lacks the item, the yellow skill when neither has it). `trainer`: Classic Era's `MinSkillLineRank` when the bands are unchanged, else **the yellow skill**, because the trainer's requirement is held by the server |
| `skills[3]` | green = ceil((yellow + grey) / 2); the client does not store it (see the cross-check) |
| `reagents` | { itemID, count } pairs |
| `learn` | `start` (`AcquireMethod` 1), `item` (a recipe item teaches it), `trainer` (anything else) |
| `teach` | the recipe item, when `learn = "item"`; with several, one with an `ItemSparse` row first, then a tradeable one, then the lowest ID |
| `bind` | the recipe item's binding: `bop` (on pickup, quest) or `boe` (on equip, on use, or none); absent when the item's row is unknown |
| `forever` | against Classic Era's same profession: `new` (not there), `changed` (bands, reagents, product or number made differ), `unchanged` |
| `items[id]` | `sell`, `buy` (copper), `buyCount`, `ilvl`, `reqLevel`, `bind` (`bop` / `boe` as above, absent when unbound), `vendor = true` for the authored list; `{ unknown = true }` when neither client has the item's row |

Two things the planner has to allow for:

- `skills[1]` can exceed `skills[2]`: some Forever patterns ask more skill than the yellow skill (Cooking 1249958 is
  { 100, 85, 105, 125 }, 1249963 { 25, 5, 10, 15 }). Such a recipe is never orange.
- 32 recipe items (18 Leatherworking, 14 Blacksmithing "Wisdom's / Veteran's ..." sets, all new in Forever) are in
  neither client's `ItemSparse`: `{ unknown = true }`, learn skill = yellow, no `bind`. Those recipes are also
  yellow = green = grey, so they never give skill; they matter only as goals.

## Scope (contentLevel 20, margin 5)

A recipe ships when, in this order:

1. it is not in a `SEASON OF DISCOVERY` category (`sod`);
2. its `AcquireMethod` is not 3 (`removed`: Classic Era recipes Forever took out, most without a name or product);
3. it has a category and colour bands (`no skill-up`: tier training spells, the "Adaptive" upgrades, 1277779-84);
4. its learn skill is at most the training ceiling, 225 at level 20 (Journeyman 150 at 10, Expert 225 at 20; unverified
   on Forever) (`skill`);
5. every reagent is on the vendor list, has `ItemLevel <= contentLevel + margin` (25), or is made by a recipe that
   passes, to a fixpoint (`materials`). The fixpoint runs over all nine professions together, so a reagent made
   by another profession counts.

| Profession | In client | Shipped (item / start / trainer) | sod | removed | no skill-up | skill | materials | Reach, orange / yellow / non-grey | Size |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Leatherworking | 616 | 178 (129 / 6 / 43) | 80 | 0 | 23 | 238 | 97 | 185 / 225 / 225 | 67.5 KB |
| Tailoring | 486 | 93 (54 / 5 / 34) | 54 | 0 | 14 | 124 | 201 | 125 / 143 / 160 | 34.0 KB |
| Blacksmithing | 526 | 130 (81 / 5 / 44) | 65 | 0 | 19 | 192 | 120 | 20 / 170 / 185 | 47.5 KB |
| Alchemy | 213 | 51 (28 / 3 / 20) | 15 | 9 | 8 | 86 | 44 | 210 / 225 / 225 | 18.7 KB |
| Enchanting | 272 | 63 (29 / 5 / 29) | 39 | 0 | 9 | 109 | 52 | 170 / 210 / 225 | 16.8 KB |
| Engineering | 295 | 72 (35 / 3 / 34) | 28 | 5 | 15 | 88 | 87 | 30 / 53 / 200 | 25.9 KB |
| Cooking | 141 | 61 (51 / 4 / 6) | 7 | 1 | 9 | 25 | 38 | 200 / 215 / 225 | 26.3 KB |
| First Aid | 40 | 17 (6 / 1 / 10) | 0 | 0 | 8 | 10 | 5 | 30 / 45 / 225 | 7.7 KB |
| Mining | 33 | 6 (0 / 1 / 5) | 0 | 0 | 16 | 7 | 4 | 25 / 48 / 125 | 2.5 KB |

Mining ships for its smelting (and Forever's camping items); the planner does not plan it. Its Smelt Gold brings
Gold Bar (ilvl 30) in through the fixpoint, and with it Golden Rod, Golden Skeleton Key (Blacksmithing), Runed
Golden Rod (Enchanting) and Gold Power Core (Engineering).

All nine files together: 247 KB. Well inside what loads at login; no load-on-demand companion is needed at this
scope.

"Reach" walks up from skill 1 and stops at the first skill where no shipped recipe is learnable and still orange
(or orange/yellow, or not grey). The last column is the practical ceiling. The orange figure is low wherever
trainer recipes dominate, because their learn skill stands in as their yellow skill (Blacksmithing 20, Engineering 30).

What the materials rule stops on (recipes dropped per reagent, ilvl):

- **Leatherworking** reaches 225 only through the leather conversions (Light -> Medium -> Heavy -> Thick Leather are
  trainer recipes with ilvl-10 input). Without them it would stop at 170. Stoppers: Cured Heavy Hide (47, 30),
  Forever's Pristine Hide (25, 45), Cured Thick Hide (11, 40), Scorpid Scale, Jade, Citrine, Wildvine.
- **Tailoring** stops at 160: Silk Cloth is ilvl 30, so Bolt of Silk Cloth (92) and everything after it drops, with
  Bolt of Mageweave (77) and Forever's Magenta Dye (38, ilvl 45). A margin of 10 would bring Silk in; that is the
  obvious knob to tune in client.
- **Blacksmithing** stops at 185: Iron (33), Steel (34), Mithril (39) and Gold (22) bars, Solid Grinding Stone (27),
  Forever's Sandpaper (15, ilvl 45).
- **Alchemy**: the level-30 herbs (Goldthorn, Fadeleaf, Khadgar's Whisker, Liferoot, Wintersbite). Its healing
  potions moved to First Aid on Forever (the Alchemy ones are `AcquireMethod` 3).
- **Enchanting**: Vision Dust (20), Dream Dust (13), the nether and mystic essences, glowing and radiant shards,
  Star Wood.
- **Engineering** has a gap: after 53 nothing shipped is orange or yellow until the green recipes carry it to 200.
  Stoppers: Mithril Bar, Solid Blasting Powder, Unstable Trigger, Gyrochronatom, Mithril Tube, Iron Bar.
- **Cooking**: level-30 meats and fish, Simple Flour.
- **First Aid**: Silk and Mageweave Cloth; it still reaches 225 through the new poultices and tourniquets.

## Cross-check with wowforevertalents.com

Run 2026-09-24 against the same build. The site's groups are the client's `TradeSkillCategoryID` (`data-group`), so
the comparison is spell by spell with no name matching.

- **Green**: 2462 recipes compared (661 of them shipped), 0 disagree. Green = ceil((yellow + grey) / 2) holds on every
  recipe, including Light Armor Kit 30/45/60 and Medium Armor Kit 90/98/105. The client stores no green skill.
- **Yellow and grey**: `TrivialSkillLineRankLow` / `High` agree on every recipe that has bands. The only
  "disagreements" are the band-less Adaptive upgrades (site none, client 0/0), which are dropped.
- **Season of Discovery**: the client knows it. The site's `data-kind="sod"` section is exactly the client's
  `SEASON OF DISCOVERY` category, for all 8 professions (0 disagreements). Nothing from the site is used to drop them.
- **Removed**: the site's "Not in Forever" rows are the client's `AcquireMethod` 3 rows, or not in the client at all.
- **Reagents, product, source**: agree on every recipe with bands. Two exceptions, both explained:
  - Engineering's random-count recipes (Coarse Dynamite, bombs, EZ-Thro Dynamite): the site shows the middle
    (2, 3), we show the range (1-3, 2-4, 1-5), which matches Classic Era's dice.
  - Herb Baked Egg (8604): site "item"; the client (Forever and Classic Era) has `AcquireMethod` 1, so `start`.
    Its recipe item 6891 exists as well.
- **Learn skill**, shipped recipes (16):
  - Blacksmithing 9 trainer recipes (Coarse Sharpening Stone, Runed Copper Belt, Bronze weapons ...): the site uses
    Classic Era's `MinSkillLineRank` even where Forever moved the bands (it gives Coarse Sharpening Stone learn 75
    with yellow 40). We use the yellow skill there. Only a trainer window can settle it.
  - Runed Copper Breastplate (2667): site 90 (Classic Era's trainer skill), Forever's plan item 2881 asks 55.
  - 6 trainer recipes (Minor Mana Potion, Handstitched Leather Pants, four Cooking) where we take Classic Era's learn
    skill because the bands are unchanged; the site leaves them blank.
- **forever mark**, shipped recipes (21), all "site changed, ours unchanged": the site also counts a change in what the
  product does (Enchant Chest - Inferior Stamina went from "Health +5" to "Stamina +2"; elixir and food buffs;
  Handstitched Leather Pants became Uncommon). Ours compares the recipe only.

Out of scope, the rest are the site capping pattern learn skill levels at 300, and the one nameless client spell per
profession (1277779-84, learn 315).

**Vendor list.** The site names no vendors, so the check is indirect: every listed item is a reagent the site shows
too, and each has a client `BuyPrice`. Imbued Vial is used by no recipe at this scope. Forever's new white
Engineering parts (EZ-Thro Fireproof Fuse, No Slip SAF-T Padding, SAF-T Casing, SAF-T Bell) and Thick Logs look like
vendor goods but are not listed; they matter only above the current scope. Confirm them from a merchant window.

## Changes to Tools/ClientMap/db2.py (OpenRoad's)

Needed for these tables, checked not to change what the map tools read (`UiMap*` tables row for row, except
`UiMapAssignment.OrderIndex`, which was wrong before and is not used):

- variable-size records with an offset map (ItemSparse);
- encrypted sections the file leaves out entirely are skipped;
- common-data columns in tables whose ID is in the record (SkillLineAbility) were always read as the default;
- strings in tables with more than one section were read at the wrong place (SpellName, Map, AreaTable).

## Recorded trainers and merchants (`recorded.py`)

What trainer and merchant windows showed (`NuuProfessionsDB.professions.trainers` and `.merchants`, written by
`API/Client.lua`; OpenRoad kept the same rows in `OpenRoadDB.professions`) lives in one player's saved variables.
`recorded.py` turns it into shipped data:

```
python3 Tools/ProfData/recorded.py            # writes Data/ProfessionRecorded.lua
python3 Tools/ProfData/recorded.py --dry-run  # lists the trainers and merchants found, writes nothing
```

It reads the live `WTF/Account/*/SavedVariables/NuuProfessions.lua` (and `OpenRoad.lua`, while OpenRoad is still
played), parsed with `Tools/SessionLog/lua_table.py` (never run), and merges its rows over what
`Data/ProfessionRecorded.lua` already ships, so a run never loses a shipped row: the latest `seen` wins per NPC and
key. A file that will not parse is skipped with a message. The output:

```lua
ns.professionRecorded = {
    trainers = { [11084] = { [2165] = { name = "Medium Armor Kit", cost = 225, skill = "Leatherworking", skill = 75,
                                        level = 0, spellID = 2165, itemID = 2313, seen = 1790275797 } } },
    merchants = { [npcID] = { [itemID] = { price, count, stock, currency = { [3402] = 30 }, items, seen } } },
}
```

Keys are the NPC's creature ID and the row's key as the client recorder saved it (a spell ID, `item:<id>` or
`name:<service> (<tier>)` for a trainer; an item ID for a merchant). ASCII only. `Domain/Prices.lua` reads it beside the
session's own book for every trainer and merchant read (fees, learn skill levels, tier fees and vendor prices; a merchant row
that asks for a currency is kept as recorded but never priced); the book's row wins for the same NPC and key. Rerun it
after a session that opened a trainer or merchant.
