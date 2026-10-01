# NuuGear status

NuuGear shows the player gear upgrades for their level. Upgrade arrows on item icons are built (2026-10-01) and
not yet tried in the client; best-in-slot targets are not started.

## Plan

1. Curated targets: level 20 best-in-slot lists per class and spec (item ID, slot, source, faction, alternatives),
   taken from the sites below. Ask their owners before shipping anything copied from them.
2. Upgrades while levelling: compare items in game from their tooltips against class stat weights, the way
   ForeverGear does, instead of shipping an offline item database. **Built**, see below.

## Upgrade arrows (built)

- `Data/Weights.lua`: weights for every spec of the nine classes (27, plus feral split into cat and bear).
- `Domain/ItemStats.lua`: an item's stats from `C_Item.GetItemStats`, with the tooltip filling in what it leaves out.
  Hit and Crit are one stat each, as on Forever.
- `Domain/Specs.lua`: the spec is the player's pick (`/nuugear spec <name>`, per character). Without a pick it is
  guessed from the tree with the most talent points, and with no points it is the class's first spec.
- `Domain/Upgrades.lua`: scores an item against what it would replace, using ForeverGear's slot rules.
  - Rings and trinkets compare against the weaker of the pair worn.
  - A two-hander compares against both hands together.
  - A one-hander can go in either hand when the character dual wields, and off-hand weapon DPS counts half.
  - Nothing goes in the off hand under a two-hander.
  - Items the character can't use (`C_PlayerInfo.CanUseItem`) get no arrow.
- `UI/Markers.lua` puts a green arrow (our own, `Tools/Art.py`) on upgrades in:
  - the game's bags and EllesmereUIBags;
  - quest rewards, at the quest giver and in the quest log;
  - the loot window;
  - group loot rolls.
  Settings `markers.bags/quests/loot/rolls` turn each place off; there is no options window yet.
- `/nuugear check <item>` prints the verdict, both scores and the stats read. Use it to check weights and parsing
  in game.

To verify in the client: the "Item stats", "Who may wear it" and "Upgrade arrows" rows in
`docs/api-compatibility.md`. The tooltip parser reads English text only.

Next: a score line in the item tooltip, an options tab (spec, places), Bagnon/Baganator if wanted, weights per
level band once the cap rises past 20 (leprestore reports 30 from 2026-10-02).

## Weights: sources and method

No Forever weights were published as of 2026-10-01: no Pawn scale, and the wowsims Forever fork
(github.com/ElliotWood/Forever) publishes no stat weights. RXPGuides' Forever weights are CC BY-NC-SA and cover damage
specs only, and ForeverGear's carry no licence, so neither is copied. Ours are worked out from:

- Forever's stat conversions (warcrafttavern.com/forever/guides/stats/):
  - Strength gives 2 AP to warriors, paladins, shamans and druids, and 1 to the rest.
  - Agility gives 1 AP to rogues, hunters and cats, and 2 ranged AP to hunters.
  - 14 AP is 1 DPS, so 1 weapon DPS is worth 7 Strength to a 2-AP class.
- Forever's itemization (classicwow.gg/forever/guides/itemization, method.gg):
  - Hit and Crit are single stats for melee, ranged and spells, shown on gear as percentages.
  - Expertise is a percentage reduction in being dodged or parried.
  - Bonus healing also gives a third of its amount as spell damage.
  - Haste is on no gear yet.
- The order, checked against each spec's level 20 priority on Icy Veins' Forever guides. Icy Veins refuses fetches,
  so the priorities were read from leprestore.com's spec guides, which match Icy Veins' search snippets. Each spec's
  priority is quoted above its weights in `Data/Weights.lua`.

Weights are per 1 point of the spec's main stat, and per 1% for Hit, Crit and Expertise. They are estimates for
level 20: tune them as play shows, and keep each spec's quoted priority beside its numbers.

## Sources

Level 20 BiS lists, built from the Forever beta client (1.60.1):

- foreverchanges.pro (https://foreverchanges.pro/bis/warrior): per class and spec (PvE, tank, PvP), with item IDs,
  sources and two or three alternatives per slot; also enchants and consumables.
- realmfirst.net (https://realmfirst.net/world-of-warcraft-forever/classes/shaman/level-20-bis/): per class, with
  stats, source and faction per slot, and the other faction's alternative. Updated 2026-09-23.
- forever-codex.com (https://forever-codex.com/bis/warrior/) and wowforever.games (https://www.wowforever.games/618.html,
  a 1-30 list).
- woweternity.com (https://woweternity.com/forever/bis): level 60 only.

Stat weights: RXPGuides ships Forever stat weights in `AddOns/RXPGuides/DB/forever/StatWeights.lua`; ForeverGear's
profiles use published Forever level 20 stat priorities.

## If we ever need offline item data

Explored on 2026-09-29 and dropped as too much work for now:

- Forever items have no flat stats in the client. `ItemSparse` stores stat types and allocations
  (`StatPercentEditor`); amounts come from `RandPropPoints` by item level, quality and slot
  (`floor(allocation * budget * 0.0001 + 0.5)`). This matched Wowhead's Forever tooltip for Rockslicer (+10 Str).
  Armor and weapon damage come from the `ItemArmor*` and `ItemDamage*` tables, all available for the Forever build
  on wago.tools.
- Dungeon loot items are missing from the client file and arrive as server hotfixes in
  `Cache/ADB/enUS/DBCache.bin` (about 4,400 ItemSparse rows, same layout as the client table).
- `Cache/WDB/enUS/questcache.wdb` holds server quest data for quests the client has seen, including fixed rewards
  (offset 116, item and amount pairs) and choice rewards (offset 180, item, quantity, display ID).
- Dungeon boss loot tables for Classic are in AtlasLootClassic (`_classic_era_`); Forever may differ.
