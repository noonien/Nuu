# NuuGear status

NuuGear will show the player gear upgrades for their level. Nothing is built yet; this records what we found
so we can pick it up later.

## Plan

1. Curated targets: level 20 best-in-slot lists per class and spec (item ID, slot, source, faction, alternatives),
   taken from the sites below. Ask their owners before shipping anything copied from them.
2. Upgrades while levelling: compare items in game from their tooltips against class stat weights, the way
   ForeverGear does, instead of shipping an offline item database.

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
