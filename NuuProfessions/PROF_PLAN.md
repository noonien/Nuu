# NuuProfessions - profession planner plan

Moved from OpenRoad's `PROF_PLAN.md` when the planner became its own addon (2026-09-29, OpenRoad's
`docs/planner-split.md`). The history below is kept; where it names OpenRoad, it means the addon the planner was
part of then.

## Intent

A profession guide that is computed, not written. The player says where they want to go ("Leatherworking to 225"),
what they want made along the way ("a belt, a chest and boots for me, and 10 Medium Armor Kits"), and what things
cost on their realm. NuuProfessions works out the cheapest route to that skill. Each step is a recipe to make until
a skill. The route also produces a shopping list and a cost figure. It stands in the planner's own window, where the
Make button carries it out a step at a time, and it is worked out again whenever the prices, the dice or the
player's goals change.

The measure is **net cost**: what the materials and training cost, minus what the output can be sold for. A recipe
that costs 50s to make but sells for 45s beats one that costs 20s and sells for nothing. The rate of skill-ups is
part of the price: a green recipe that skills up one time in three costs three crafts per point.

### Scope: the beta level cap

The beta stops at **level 20**, and level 30 comes later. The shipped data holds only what a character can use up to
that cap. The cap is one build parameter, `contentLevel` (20 now), recorded in each generated file's header.
Raising it is a rerun of the extractor with `contentLevel = 30`, not a redesign. A recipe is included when all of
these hold:

1. **It can be trained by then.** The trainer tiers reachable by `contentLevel` bound the skill. With Classic's gates
   (Journeyman at level 10 to 150, Expert at level 20 to 225, Artisan at level 35 out of reach), level 20 reaches
   Expert. The gates are **unverified on Forever** and are checked at a trainer before they are trusted.
2. **Its materials exist by then.** Materials limit the skill more than training does: Heavy Leather comes from
   mobs above level 20. Every reagent must pass one of these tests:
   - it is vendor-sold;
   - it is made by a recipe that is itself included (Cured Light Hide);
   - its `ItemSparse` item level is at most `contentLevel + 5`. The 5-level margin is for the dungeons and elite
     areas a capped character still visits, such as Shadowfang Keep. The margin is a parameter, tuned against the
     extraction report.
3. **It can be learned.** It is not a Season of Discovery recipe. BoP and BoE patterns stay in the data: by
   default the planner plans with them and marks them (see recipe availability under player inputs).

The extractor reports the practical ceiling this leaves per profession: "with level-20 materials, Leatherworking
reaches about N". The planner offers targets up to that ceiling and says why it stops there.

Goals list every included product. Products the character cannot wear by the cap (required level above
`contentLevel`) are shown but greyed.

**The testing set.** Routes that stop near 170 cannot test the planner's long-route behaviour, so a second data
set is extracted past the beta's cap: `extract.py --content-level 60 --out Data/ProfessionsFull --table
professionDataFull` writes `Data/ProfessionsFull/<Name>.lua` (`ns.professionDataFull`), same format, header
marked as the full-scope testing set. It is used only behind the per-character switch **Options -> Testing -> Plan
past the beta's level cap**, which also switches `Data/ProfessionTiers.lua` to its full list
(`ProfessionTiers:SetFullScope`, adding Artisan: 300, level 35, skill 200, Classic spells, unverified) and plans as
level 60. Off, nothing changes. The set can name materials and recipes this beta does not have yet; it is a test
fixture, not a promise of what the game offers.

### Scope: crafting professions only

The planner covers professions whose skill-ups come from **making something**, because only those have a
recipe-by-recipe cost to minimise:

- Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking and Tailoring;
- the secondary crafts, First Aid and Cooking.

**Fishing, Mining, Herbalism and Skinning are out for now.** Their skill-ups come from gathering, which means time
and routes rather than gold. Gathering routes and pathing are also out. Mining's Smelting is a crafted skill-up that
would fit the model; planning Mining itself waits with the rest of Mining.

**A character's other professions make materials.** `Data/Professions/Mining.lua` ships Mining's trade-skill recipes
(Smelting, and Forever's camping items), and the planner window hands the planned profession's data, with the
recipes of every other profession the character has, to `Planner:WithHelpers`: Smelting makes Blacksmithing's and
Engineering's bars, Blacksmithing's Golden Rod Enchanting's Runed Golden Rod. Such a recipe comes in when the
character has its skill and knows it (with nothing of that profession known yet, its starting recipes and the
trainer ones its skill allows), marked `helper`. It is a maker of materials only: it follows the materials' modes
like any intermediate (make by default, **Buy it** on the Materials tab), gives no skill in the planned profession,
is never a run, and is left out of the Recipes tab and the profession's material lists. Its make row reads
`Make 20 x Copper Bar (Mining)`. With **Only what I have**, ore
in the bags is smelted into the bars the route needs, and runs out as any carried part does. A make row (any
intermediate, not only a helper's) is sized for the step's count. With **Only what I have** that count is the low
end the Make button orders (`run.count = run.low`; where the materials end the route, all the bags make), so the
parts, the bags' sums and the button agree; buying, it is the confidence count the shopping list covers.

Gathered materials still take part as **materials**. Ore, herbs, leather and fish have buy and sell prices like
anything else. The "I gather this myself" toggle only sets their cost (opportunity or zero). It never produces a
route, and its row just says how many to bring.

For size: Leatherworking, cut by learn skill alone, keeps 174 of 604 recipes at 150 (41 of them trainer recipes) and 210
at 175. The materials test cuts further. The load-on-demand companion is not needed at this scope.

### What Zygor and RestedXP do (researched 2026-09-24)

Neither addon plans anything.

- **Zygor profession guides** are hand-written scripts. Material totals are hard-coded estimates such as
  `collect 804 Silk Cloth`, and every step escapes on `skill >= N`. The one live estimate is on a create step: it
  reads the recipe's current colour from the trade skill window and multiplies (orange x1, yellow x1.5,
  green x3). It does not look ahead to later skill levels, and it has no chance formula.
- **Zygor's Gold/Crafting module** is the only computed part. It finds profit as sell price minus reagent cost,
  using its own auction house scans, and it **generates guide text at runtime** (buy, create sub-reagents, create
  the product) and feeds that text to its own parser. OpenRoad borrowed that pattern, generating a v2 guide table
  instead of text; NuuProfessions keeps the route in its own window instead (see "The plan stands in its own
  window").
- **Zygor's recipe table** (`Data-TBC/Tradeskill_Recipes.lua`) holds the spell, product, number made, reagents and
  the orange skill only. There are no yellow, green or grey skill levels, and the source is "undefined" for most recipes.
- **RestedXP** has no crafting guides. It has gathering routes only. Its `.collect` can scale a count down as the
  skill rises, a small dynamic shopping list.

So the skill-up thresholds, the chance model and the optimiser are new work. The client's own game data (below) is a
better source than either addon.

## Player inputs

All of these are set in a GUI window, the **Profession planner**. None of them are slash commands.

1. **Profession and target skill.** The start is the live skill read from the client. The target is capped by what
   the player can train, and the planner states that cap. See the level requirements for training skill levels below.
2. **Goals.** Recipes and counts the player wants made: `Hillman's Belt x1, Medium Armor Kit x10`. Each goal has a
   **when**:
   - `best` (the default): make it wherever it yields the most skill, which is usually as soon as it is orange.
   - `now`: first thing, because the player wants to wear it.
   - `end`: after the target skill, just for the list.
   - `at skill N`.

   A goal's output is **kept, not sold**, so its value is never subtracted. Its skill-ups are free progress.
   A goal is counted off as it is made, however it is made: the client's "You create:" line (with its `x5`
   quantity) reaches the window through `Client:ProfessionChanged("crafted", item, count)`, and
   `Planner:GoalMade` takes those crafts off the goal whose recipe makes the item, dropping it once all are made.
   Goals are set on the recipe itself, on the Recipes tab.
3. **Prices**, per item, in two columns:
   - **buy**: what one costs the player.
   - **sell**: what one earns them, net of the auction cut.

   The player can override any value. See the price model.
4. **Sourcing options.** These are realm and character facts, several of which already exist as realm answers in
   Options (`auctionHouse`, `selfFound`):
   - Use the auction house to buy, to sell, both or neither.
   - How each material is had (`Planner:GetMode`, the Materials tab's **Get it**): made from its parts (the
     default for an item a usable recipe makes), bought, or gathered myself, costed at **what it would sell for**
     (opportunity cost) or at **zero**.
   - Use what is in my bags first (on by default); the bank is not counted.
5. **Recipe availability.** By default (`recipes = "patterns"`) the route plans with every recipe in the data, as
   if every pattern could be had, and uses whichever is cheapest: what the character knows, starts with and
   learns at a trainer, the patterns they said they have, and every pattern they lack. On Forever most recipes
   are taught by an item (510 of 604 for Leatherworking). A lacking pattern costs:
   - a gold vendor pattern: its price, when the vendor is known;
   - a **BoE pattern** (tradeable): its auction price (the player's, or Auctionator's); with none, 0, flagged
     `costUnknown`;
   - a **BoP pattern** (drops, quests, reputation; only the player can get them): 0, flagged `costUnknown`, since
     no price can be known.
   Each run and learn event whose recipe needs a pattern the character lacks carries
   `needsPattern = { bind, source, cost, npc, teach }`, and `summary.patterns` / `summary.patternsUnknown` count
   them. The Plan tab shows those steps on a pink background with a muted `pattern, vendor|BoE|BoP` tag; **I have the
   pattern** (`accepted`) takes the mark away. **Prefer it** does not: a pin is not the pattern in hand.

   The window always plans this way: `Planner:LoadInputs` drops any saved `recipes` choice, so plans saved with
   the old `trainer` (known and trainer recipes only, patterns as suggestions) or `all` load as `patterns`. The
   planner still understands `recipes = "trainer"` for its tests and for the gap note, but nothing in the window
   sets it.
   - Season of Discovery recipes are in the client but cannot be learned, so they are never offered.
   - Some patterns are sold by merchants for a currency. The planner ignores those prices: such a pattern counts as
     BoE or BoP by its binding.
   - The gap note (`route.gap`, below) still appears when nothing at all gives skill: under `patterns` that is
     only past every pattern too.

   **Suggestions** (with `recipes = "trainer"`; under `patterns` nothing is left to suggest, and a suggestion the
   route already uses is never listed). On the Plan tab a pattern is one of the **alternatives** at every step whose skill levels it gives
   skill at throughout, badged `Vendor`, `BoE` or `BoP`, with what it saves and where it comes from: "BoP Dark
   Leather Boots, saves 1g 20s". **Use this** on it marks it as in hand (below), since owning a pattern holds
   everywhere, and chooses it for that step's skill levels: it joins the route there with a step to obtain it.

   **Plan with it** is one choice per recipe (`Planner:SetPlanWith`), on every recipe, not only suggestions:
   trainer recipes, vendor patterns, BoE patterns, and runs already in the route ("I will not make 40 of these").
   It is a drop-down on the Recipes tab and the right-click menu of a run on the Plan tab:
   - **Planner decides** (`auto`, the default).
   - **Prefer it** (`pinned`): use it wherever it gives skill. (**Use this** on an alternative does not pin: it
     is local, see `chosen` below.)
   - **Never use it** (`refused`): it is never used or suggested, and its goal is dropped.
   - **I have the pattern** (`accepted`), only on a recipe taught by a pattern the character does not know: the
     player has it or will get it.

   A recipe is in one of the sets at most. The choice is saved per character, the planner replans at once, and
   Recipes' Show filters (Prefer, Never use, Patterns I have) list every recipe so set, so any choice can be
   undone; the status strip's **Undo** takes back the last one.

   **Chosen stretches** (`chosen = { { fromSkill, toSkill, spell } }`, saved per profession with the other inputs;
   older saves also carry `leave` and `rejoin`, which are ignored). A pick is "this step, `[fromSkill, toSkill)`,
   uses recipe X": at a skill inside it the only candidate is X, when it gives skill there. The route's runs are cut
   at every stretch's ends, so a picked step keeps exactly its skill levels, never runs on into a neighbour making the
   same recipe, and the planner's runs beside it keep theirs. Everywhere else the route is the planner's. A
   stretch naming a recipe that is refused, needs an avoided material or is not in the profession is ignored; one
   that would leave no route is dropped for that plan with a warning. A chosen recipe that must be learned is
   learned as usual.

   `Planner:WaysAround(route, runIndex, limit)` lists the choices at a step from the step alone. Its span is
   S = the run's `[fromSkill, toSkill)`. The candidates are every recipe the route may use (known, trainer,
   starting, accepted) and every pattern it could suggest that gives skill at every skill of S, less those refused
   or needing an avoided material. The baseline is the route solved with the step's own stretch carved out and
   every other stretch kept (this route when the step has none); its recipes over S are the `planner` choice
   (extra 0, possibly more than one recipe). Every other candidate X is solved with the pick `{ S, X }` added:
   `other` (or `pattern`, priced with what the pattern costs to get) with `extra` = that route's value less the
   baseline's, `perPoint` and the expected `crafts` over S. The list is sorted by extra, then spell, `limit`
   (default 12) caps the non-planner choices, and it is cached per route and run. `using` marks the step's own
   pick, or the planner's choice when it has none. Since S and the other stretches do not depend on the step's
   own pick, the list and its order are the same whichever choice is taken, with only `using` moving; a pattern
   is the exception, since it is then in hand and the baseline may use it. Each run carries `others`, how many
   other recipes give skill over all its skill levels, counted without solving, for the alts button.

   `Planner:UseWay(inputs, way)` acts on the choice's span alone: `planner` clears what was chosen over S,
   `other` replaces it with the pick `{ S, X }`, `pattern` also marks X as in hand (`SetPlanWith(have)`).
   Stretches outside S are never touched. The run says `chosen`; its right-click **Let the planner choose here**
   is `Planner:ClearChosen(inputs, fromSkill, toSkill)`, which carves those skill levels out (a stretch inside goes, one
   reaching past keeps the rest), and `Planner:ChosenAt(inputs, skill)` finds the stretch at a skill.

   Materials have the same choice (`Planner:SetMaterialMode`), on the Materials tab and a material's right-click:
   **Never use it** (`avoided`) leaves out every recipe that needs it, and **Prefer it** (`preferred`) treats every
   usable recipe that needs it as preferred. What a recipe makes has a **Sale** choice (`Planner:SetSaleMode`), on
   the Materials tab's What you make and a run's right-click: as Options says, sold at the best price (`sell`),
   sold to vendors only (`keep`) or kept, never sold (`nosell`).
6. **Confidence.** How safe the shopping list is: `typical` (the expected count), `safe` (about 90% of runs finish
   with it) or `sure` (about 99%). The default is `safe`. See the shopping list section.

The planner **recommends**. It never buys, posts or trains, and it crafts only when the player presses a **Make**
button (below), one batch a press, from the profession window the player opened. The player can override every
choice it makes, and the route is a plan they follow or skip. This keeps it inside the
player-directed rule.
Choosing between recipes is a cost recommendation the player asked for, not a combat, target, quest-order or reward
decision.

## Data

### Recipe table: from the Forever client, at build time

The beta's DB2 tables can already be read offline (`Tools/ClientMap/casc.py` and `db2.py`, product
`wow_classic_beta`). A new tool, `Tools/ProfData/extract.py`, reads:

| DB2 | What it gives |
| --- | --- |
| `SkillLineAbility` | recipe spell -> profession (`SkillLine`); `MinSkillLineRank` (orange, the learn skill); `TrivialSkillLineRankLow` / `High` (yellow and grey); `AcquireMethod` (known when the profession is learned, or trained) |
| `SpellReagents` | reagents and counts |
| `SpellEffect` | `CREATE_ITEM` effect: the product item and the number made (base points plus die sides gives min and max) |
| `ItemSparse` | vendor `SellPrice`, `BuyPrice` / `BuyCount` for vendor-sold materials, `Bonding` (a BoP product cannot be sold), required level |
| `ItemEffect` / `ItemXItemEffect` | recipe items: which item teaches which spell |
| `ItemSparse.Bonding` (on the pattern) | whether the pattern is BoP or BoE: whether it can be bought from other players at all |

Green is taken as the midpoint of yellow and grey, rounded up. Both samples checked so far fit: Light Armor Kit
30/45/60, and Medium Armor Kit 90/98/105. The cross-check against wowforevertalents.com below tests it on every
recipe, and the trade skill window's colours test it in client.

The tool writes `Data/Professions/<Profession>.lua`: IDs only, one table per recipe, with no mixed list and key
tables.

```lua
-- Data/Professions/Leatherworking.lua (generated by Tools/ProfData/extract.py; do not edit)
recipes = {
    [2881] = {                       -- recipe spell ID
        makes = 2318, made = { 1, 1 },  -- item, min and max made
        skill levels = { 1, 20, 30, 40 },      -- orange, yellow, green, grey
        reagents = { { 2934, 3 } },     -- item, count
        learn = "start",                -- start | trainer | item
        teach = nil,                    -- recipe item ID when learn = "item"
        bind = nil,                     -- "bop" | "boe": the pattern's binding, when learn = "item"
        forever = "unchanged",          -- new | changed | unchanged (shown as a mark in Recipes)
    },
},
```

Names are **not** shipped. There are thousands of items, and the client's `GetItemInfo` / `GetSpellInfo` names and
links are the display path (`Client:GetItemName`, `Client:GetSpellName`); a name the client has not cached yet shows
as its ID until it arrives. OpenRoad's `Data/Names.lua` stays with the guides. If the tables prove heavy, they move
to a load-on-demand companion addon loaded when the planner opens. That decision waits for a size measurement.

### Cross-check: wowforevertalents.com/professions

[wowforevertalents.com/professions](https://wowforevertalents.com/professions) (by Milenkas) reads the same Forever
client build (1.60.1.69977). For every recipe it lists:

- the spell ID;
- the learn, yellow, green and grey skill levels;
- the source (`trainer` or `item`);
- whether the recipe is new in Forever, changed from Classic Era, or unchanged;
- whether it belongs to a Season of Discovery group.

It also has per-profession reagent pages. All of this is in the page's HTML as attributes on each recipe row
(`data-r`, `data-learn`, `data-yellow`, `data-green`, `data-grey`, `data-src`, `data-status`), so no
page scraping by eye is needed.

What it shows about Forever, seen 2026-09-24 on Leatherworking:

- 604 recipes: 289 new, 199 changed from Classic Era, and 116 unchanged.
- 94 recipes are taught by a trainer and 510 by an item.
- New recipes have spell IDs around 1255000.
- Colour bands moved on many old recipes.

A Classic recipe table (Zygor's, or memory of Classic) would be wrong for about 80% of the profession. That makes
the client extraction mandatory and a cross-check worth having.

The site is used in two ways, both **at build time only**. The addon never goes online.

1. **Cross-check.** `Tools/ProfData/crosscheck.py` downloads the profession pages and compares each spell's skill levels,
   source and reagents with our extraction. Every disagreement is listed. It either shows an extraction mistake
   (a wrong column, the green formula) or a place where the site knows more than the client.
2. **Facts the client does not hold.** The site takes these from its own beta logging (the "WFT Beta Log" addon,
   merchant windows seen 20 September 2026): the Season of Discovery grouping and which recipes turn up where.

   The site states no licence. Following the borrowing rule in OpenRoad's `CLAUDE.md`, the build uses these facts only to
   **check** our own data until the author gives permission. Shipped rows carry provenance (`src = "client"`,
   `"recorded"` or `"wft"`). Anything that would ship as `wft` is either confirmed by our own in-client recording
   first (the merchant and trainer recording below) or waits for that permission.

### What the client database does not know, and where it comes from

- **Trainer skill caps and required levels.** At the level-20 scope only Apprentice (75), Journeyman (150, level 10)
  and Expert (225, level 20) matter. These are a small authored table, checked at a trainer in client. Artisan
  (300, level 35) is in the table's full list, used only by the testing switch; it joins the beta list when the
  cap passes 35.
- **Trainer costs and which trainer teaches what.** These are recorded when the player opens a trainer
  (`GetTrainerServiceInfo`, `GetTrainerServiceCost`, `GetTrainerServiceSkillReq`, read only) and saved account-wide.
  An unknown cost counts as 0 and is flagged "cost unknown" in the summary. A recorded skill requirement replaces
  the shipped learn skill of a trainer recipe (the client data has none), even for a service shown unavailable.
- **Shipped recordings.** What trainer and merchant windows showed lives in one player's saved variables.
  `Tools/ProfData/recorded.py` merges the live saved file over what is already shipped and writes
  `Data/ProfessionRecorded.lua` (`ns.professionRecorded`, provenance `recorded`); `Domain/Prices.lua` reads it
  beside the session's own book, the book's row winning for the same NPC and key. The first one holds the Orgrimmar
  Leatherworking trainer (NPC 11084, 28 services: Medium Armor Kit 75, Hillman's Cloak 125, ...).
- **Vendor stock for materials.** `ItemSparse.BuyPrice` gives the price. Where it is sold comes from merchant windows
  the player opens (`GetMerchantItemInfo`, read only), recorded the same way. The route's "buy" step then names a
  vendor.
- **Patterns sold for a currency.** Some merchants sell patterns for a currency rather than gold. The merchant
  recording keeps the currency cost as the window shows it (`GetMerchantItemCostInfo` / `GetMerchantItemCostItem`),
  but the planner ignores those prices: such a pattern counts as BoE or BoP by its binding.
- **Other recipe item sources** (gold vendors, drops, quests). These are authored per recipe only as the need
  arises. The planner works without them, because such recipes are opt-in.
- **Obtainability.** The client table includes Season of Discovery recipes that cannot be learned on Forever. The
  extraction marks them from the site's grouping, confirmed by the patterns the in-game merchants actually sell, so
  that the planner never offers them.

### Runtime corrections from the trade skill window

When the player opens their profession window, the planner reads the known recipes and each recipe's current
difficulty colour. It uses `GetTradeSkillInfo` / `GetCraftInfo` on a Classic-shaped client and `C_TradeSkillUI` on a
modern one. Both are feature-detected in `API/Client.lua`, and Enchanting may be on the Craft API. The planner uses
this to:

- mark recipes as known, so they need no training cost or opt-in;
- check the table's colour against the live one at the current skill. A disagreement is logged (a `prof` log
  channel) and the live colour wins for the session, like OpenRoad's `GuideCorrections`. The log is then how the shipped table
  gets fixed.

## Price model

Each item has up to four price facts, stored account-wide in `NuuProfessionsDB.professions.prices[itemID]` with where each fact came
from and when:

| Fact | Source | Trust |
| --- | --- | --- |
| vendor buy | `ItemSparse` / merchant window seen | exact |
| vendor sell | `GetItemInfo` sell price / `ItemSparse` | exact |
| auction buy | **player-entered**, else **Auctionator** | the player's word; Auctionator's last scan |
| auction sell | **player-entered**, else **Auctionator** (the net is taken after the 5% cut) | as above |
| estimated auction buy | vendor sell x `estimateFactor` (4), at least 5c | a guess, flagged everywhere |

- **Priority.** Player-typed, then a merchant window, then Auctionator, then the shipped data, then an estimate.
- **Auctionator.** When it is installed, its public API (`Auctionator.API.v1.GetAuctionPriceByItemID`, and its age
  call) prices both auction facts. It is feature-detected and pcall-guarded in `API/Client.lua` and injected into
  `Domain/Prices.lua` (`Prices:SetAuctionSource`), which stays pure; NuuProfessions never reads its internals or saved
  data. Its database is not restored on this beta either, so it knows only what the player saw at the auction house
  this session, and an auction house visit marks the plan stale. The planner option `useAuctionator` turns it off.
- **Estimates.** A material with no source at all, when the player buys at the auction house, is costed at an
  estimated auction price instead of being unobtainable. Items the data marks `unknown` get none. Any real price
  beats an estimate; making an item from estimated parts is an estimate too. The route lists its estimated items by
  the share of the cost they carry (`route.estimated`, `summary.estimatedShare`), the Materials tab flags them (a
  banner, `~` prices, the Guessed or missing view), and the Plan tab's verdict names them ("... but 6 prices are
  estimates (Light Leather, ...)."), with **Check prices** beside it. Without estimates, a player with no prices typed got an empty plan (seen in client
  2026-09-24, Leatherworking 83).

- **Buy cost of a material** follows how the player gets it (`Prices` `Context:GetMode`, stored as
  `options.gather` and `options.get`; saves from before the modes load unchanged):
  - **make** (the default for an item that a recipe the route may use makes: known, a trainer's, a starting one or
    accepted, not refused, not needing an avoided material): the cost of its own reagents per item made, each
    reagent by its own mode, for intermediates such as Cured Light Hide or Bolt of Linen Cloth, even when buying is
    cheaper. When no recipe can make it (a part has no source) it is bought after all.
  - **buy** (the default for anything else; `get[itemID] = "buy"`): the cheaper of vendor buy and auction buy,
    never made.
  - **gather-valued** and **gather-free** (`gather[itemID]` = `opportunity` or `zero`): gathered at what it would
    sell for or at nothing, competing with the other sources as before.
  An item with no allowed source is unobtainable, and recipes needing it are skipped and listed.
- **What the route optimises** is the player's choice (`optimize`): `cost` (the default) picks recipes on spending
  alone, a sale never steering the choice though it is still counted in the money shown; `profit` picks them on
  spending less sales.
- **What counts as sold** is the player's too (`sellOutput`): by default (`chosen`) only the items they picked
  (`sell[itemID]`, Sale: Sold, best price, in Materials or a run's right-click); with `all` (Options, Count as sold:
  Everything) every output, at the value below.
- **Sell value of an output** is the best allowed of vendor sell and auction sell. BoP output, or output the player
  marked "keep", is worth vendor sell or nothing. The price book can also hold **how many the market takes**
  ("sell up to 10 at this price"; `Prices:SetDepth`), beyond which extra copies fall back to vendor sell; the
  window has no field for it at present.
- **Items already carried** are costed at their sell value when "use bags first" is on. Using them is not free,
  because they could have been sold, but it avoids a purchase.
- **Only what I have** (`materials = "carried"`, one toggle on the Plan tab) plans with what is carried, what
  vendors sell and what the route makes from those: no auction buying, no estimates, no gathering. The crafts are
  known (the bags) and the skill levels they reach are the guess, so it plans at the expected skill-ups
  (`confidence = "typical"` whatever the option says: the margin is a shopping list's), and a recipe row's end
  reads `~41`; the window plans again from wherever the crafts leave the skill (a craft, a bag change or a new skill
  checks within about a second). An item no
  vendor sells comes from the bags (`Context:BuyCost` source `carried`, at its bag value) and has no source when
  none are carried. The DP knows prices, not counts, so the planner cuts: it walks the route's batches at the
  confidence counts (each run with its own spread, at least what the shopping list asks), and where a bag-only
  item first runs short it cuts the run at the skill the bags reach (the crafts the bags cover are found by trying
  counts through the ledger: a part partly in hand, bars already smelted with ore for the rest, says nothing of the
  crafts by its own shortfall) (never short of one more point while the bags
  still make a craft: leftovers under the confidence count are worth the try, or the route would end with
  materials in hand); from there every recipe needing that item,
  directly or through a part the route makes, is out (`entry.stopAt`). It solves again and stops the route at the
  first skill nothing is left for (ceiling `materials`, `route.ranOut`), until no cut moves; cuts only move down, so
  this ends. The cuts are greedy: they spend a carried item on the first skill levels that use it, which is not where it
  does most (a recipe orange all the way loses nothing by waiting, a yellow rival's chance falls every skill). So the
  route is also solved with a shadow price on each carried item (`tuneShadow`), raised until the route fits in
  the bags, and with a craft costing `Planner.carriedCraftCost` (1c) so fewer crafts win a tie; the solve then puts
  the item where it saves the most. While pricing, the chance floor gives way (a scarce recipe's price, not the
  floor, decides when a slow recipe beats it), and a route fits when the bags make the low end of each run's crafts,
  as the cuts let a last craft try for a point. Each short item is priced in turn to the lowest that fits (by fours, then
  halving the gap); a round that leaves any short scales every price together. Where the bags cannot reach the
  target it is tried at the skill the cuts reach and a skill higher while it still fits. The priced route replaces
  the cuts' when it reaches further, or as far for less money plus crafts. The route's money stays gold: the shadow
  prices only steer. Two scarce items that trade against each other can defeat the pricing; the cuts' route stands
  then. Last, each step's crafts are capped at what the bags make (`run.carriedCap`; its low and high with it), in
  order, so the step where the last materials try for a point asks only for those; the table shows those crafts.
  Where the materials end the route (ceiling `materials`), the last step on each material makes all the bags make of
  it, not the crafts the odds say its skill levels need; the Make button orders that count (OpenRoad's tracker asked the
  planner through `Panel:CarriedCrafts`; NuuRoad is to ask through `NuuProfessions.API`, planned).
  When materials end the route, every craft of the last steps is made whatever their order, so the last few (up to
  four, running on from one another, each leaving the bags without another craft) are walked in every order, craft
  by craft on the odds of each skill (summing chances at a rounded skill ties orders that are not equal), and the order
  with the highest expected skill is kept: every point lowers the chance of the crafts after it,
  so the surest crafts go last. A goal's shortfall is warned
  (`carriedShort`), not cut.
- A price the player types always beats one the addon read. The Materials tab shows every item the current plan
  buys, with its effective price, where the price came from (and an Auctionator price's age), and highlights items
  that are guessed or have no price.

Deferred, with a question below: reading auction prices from the open auction house window. This would be a
read-only search, only for the plan's items, and only when the player presses a button.

## Skill-up model

For a recipe with skill levels (orange O, yellow Y, green G, grey R) at skill s:

- s < O: cannot be made.
- O <= s < Y: chance 1 (orange).
- Y <= s < R: chance p(s) = (R - s) / (R - Y). This is the accepted Classic formula, and it puts green at about 50%
  and below.
- s >= R: 0 (grey).

The planner does not use a p below a floor, default 0.15, and only considers such a recipe if nothing else is left.
One craft gives at most one point; this is a constant, to be checked on Forever. A multi-made recipe
(`made = {1, 3}`) is credited with the average output for selling and for feeding later steps.

The number of crafts to take one point at skill s is geometric: expected 1/p, variance (1-p)/p^2. A run of
consecutive points adds them up. That gives an expected count and a spread for every step, which the shopping list
uses.

## The optimiser

Everything is pure Lua in `Domain/ProfessionPlanner.lua`, with no frames and no Blizzard calls, so it can be tested.

### 1. Goals first

Goals are placed by their `when`. `best` means the earliest skill at which the recipe is orange. Their crafts are
simulated in skill order with expected gains. Their material cost is added to the total, but it never steers a
choice, because the player wants those items regardless. The result is a set of **free progress events**: "at
skill 100, make 3 x Hillman's Belt, about +3".

### 2. Grind: dynamic programming over skill levels

The state is `(skill, current recipe)`. The value is the expected net cost to reach the target from that state. The
cost of one point at skill s with recipe r is

```
(material cost of r - sell value of r's output) / p(r, s)
```

To this is added the recipe's learn cost (trainer fee or recipe item price) the first time the route switches onto
it. Recipes only get easier, so a recipe is used over one contiguous run of skill levels in practice, which makes the
switch charge exact. Training to the next tier (a fee, and a level gate) is a forced step at the cap skill levels. Goal
events are applied as the DP passes their skill. The profession has at most 300 skill levels and a few dozen recipes are
usable at any skill, so the table is small: a few thousand cells.

### 3. Intermediates and market depth

These are second-pass refinements:

- **Intermediates.** An intermediate a later run consumes is valued at its replacement cost. The ones a run makes
  from their parts (the batch walk) are made just before that run, at the skill the route has then, and while their
  recipe gives skill there those crafts are progress: the expected points are walked skill by skill, one per success,
  as a goal's are, the parts first. Each pass turns them into a jump like a goal's (it stops at a trainer cap, a
  goal and a stretch the player chose, never starts inside one, and leaves its run at least a point), and the next
  solve skips those skill levels, so the grind after them is shorter; the passes stop when the runs and jumps stop
  changing (`Planner.maxPasses`). A goal's intermediates are made without counting skill. The route reports each as
  a `make` event (item, crafts, items, skill, gain, the run it feeds, the cost of its parts), a make row in the
  outline and the Plan tab, and `route.makes` summed by item. A recipe first used as
  an intermediate is learned there. The alternatives at a step are solved in passes too, so their figures are what
  a replan with them would cost.
- **Making at a loss.** Make stays the default even when buying is cheaper, so the loss is told instead:
  `Planner:MakeLosses` lists each `route.makes` item whose buy price (a real one, never a guess) is under its
  parts ("paid") or under what its free-gathered parts would sell for ("free", `Context:MakeOrBuy`'s `worth`), and
  `Planner:BuyingSaves` replans with one bought to say what that saves over the route (negative when the skill of
  making it pays). The window works this out once per route (`Panel:MakeLosses`, traced as `losses`), warns on the
  Materials tab (banner with Buy it instead / Value <part>, the Cheaper to buy view, the row and its tooltip) and the
  Plan tab (hints, the make row). (OpenRoad also passed the list to `BuildGuide`, whose craft step added a
  "Careful: ..." note; that went with the guide export.) `Gather, valued` costs a part at its market value (`Context:MarketValue`), not by Count as sold.
- **Market depth.** A "sell up to N" cap breaks the per-point independence. The planner solves once without caps,
  lowers the value of the copies beyond each cap, and solves again until the route stops changing (two or three
  passes).

### 4. Suggestions: what a pattern would save

A candidate is either a BoP pattern the player has not accepted, or a BoE pattern with no price. For each one the
planner solves again with that recipe available and free to learn, and the saving is the difference in net cost. A
solve is a few thousand cells, so a few dozen candidates cost nothing noticeable. Candidates that save less than a
threshold (default 10s) are not shown.

- For a BoE pattern, the saving is also the most it is worth paying for it: "worth buying under 1g 20s".
- For a BoP pattern, the saving is weighed against the trouble of getting it, which the planner cannot price. It
  only states the saving and the source.

Recipes the player refused are never candidates. Accepted suggestions, and under `patterns` every pattern the
character lacks, are ordinary recipes in the main solve.

### When the route stops short

A route stops below its target at the first skill no recipe the player can use gives skill at (the ceiling
`recipes`; a route that cannot start stops at the live skill). It then carries `route.gap`: that skill, `to` (the next
skill a usable recipe gives skill at again, if any) and the ways past it, which the Plan tab lists at the end of the
table with a button each: patterns not in hand that give skill there (source, binding, price when known, and whether
"I have it" would carry the route on, judged cheaply: the pattern gives skill there and its materials have a
source), recipes set to Never use, recipes needing a material set to Never use, recipes whose material has no
price, and, when the plan is not full scope, how many recipes of `Data/ProfessionsFull` give skill there but were
left out of the beta's data, each named with the reagent that left it out (one the beta's data lacks, else the
highest item level). The full data comes in as `input.fullData`, so the domain stays pure. On the beta,
Leatherworking at level 20 stops at 170: seven patterns (two BoP, five BoE) and fourteen left-out recipes (Cured
Heavy Hide, Bolt of Silk Cloth, Shadow Oil and others) cover it; the trainer's next recipe is at 175.

### 5. Output

The result is a route of runs `{ recipe, fromSkill, toSkill, expected, low, high }` plus training, goal and purchase
events, and a cost summary:

- spent on materials and training;
- recovered by selling;
- **net**;
- the range at the chosen confidence;
- a per-skill-band breakdown, so the player can see which stretch is expensive.

## The plan stands in its own window

OpenRoad turned the route into an ordinary **v2 guide table**, built in memory the way Zygor's Gold module builds
guide text, validated it by its `Data/Schema.lua` and ran it in its tracker (**Start in tracker**, **Save as
guide**). That export is gone: the planner is its own addon, and the plan stands in its own window, where the Plan
tab's **Make** button carries it out a step at a time. `BuildGuide`, `GuideID`, `ProfessionOfGuide`,
`SectionOfGuide` and the step verbs went with it (OpenRoad's `docs/planner-split.md`). What is left of the
guide-shaped output is what the window reads: `Planner:Outline`, the table's rows in the order they are done, and
`Planner:Sections`, where its headings fall and what each section buys.

- **Sections** are the player's choice (`Planner:Sections`, the Plan tab's **Sections** drop-down):
  - `trip` (the default): a shopping section first, so the whole list can be bought in one trip, then one section
    per trainer tier ("Apprentice 1-75", ...);
  - `tier`: a section per trainer tier, each opening with its own shopping;
  - `recipe`: a section per N recipes made (`recipesPerSection`, 1 by default), grind runs or goals ("Light Armor
    Kit 40-50", or "Light Armor Kit, Cured Light Hide 40-67"), each opening with the shopping for those alone;
  - `band` ("Every N skill levels" in the window): the skill levels cut at every multiple of N (25 by default; at 50,
    83-100, 100-150, 150-200), a run crossing a cut split into two steps of the
    same recipe (Plan cuts runs there, as it does at a pick's edges), so each section holds exactly its skill levels.

  A split section's shopping comes from what its own batches bring (the sized ledger records it per batch), and its
  last skill is the last skill in the section that needs the item. The Materials tab's "this section" view lists one
  section's shopping.
- **The shopping list** is two things: the Materials tab, where what to buy is decided, and the shopping list panel
  (see UI), what to buy, readable with the planner shut. Their counts use the chosen confidence: the sum of expected crafts plus
  z times the square root of the summed variance, with z = 0, 1.3 or 2.3. Each item's last skill means a lucky run
  never leaves the player buying or farming for points they already have.
- **Replanning.** The route is computed again from the live skill and live bags when the skill passes the step's
  `high`, when prices change, when a goal changes, when the bags or a profession, trainer, merchant or auction window
  tell it something new, and before Make acts on a skill that moved. There is no Replan button.
- **Keeping it.** The planner's inputs (target, goals, options, exclusions) are saved per character
  (`NuuProfessionsCharacterDB`), so the same plan comes back next session; only what the player set is stored (no
  default option, no empty table: `Planner:SaveInputs`), and `Planner:Option` reads an option as it applies.

## UI

The **Profession planner** window opens from a **Planner** button on the profession window when the client allows
(and, with NuuRoad installed, from its menu through `NuuProfessions.API.Open`, planned; `/nuuprof` opens it too, as a
developer convenience). `UI/Planner.lua` is the shell, a NuuKit window: the profession drop-down in its band after the
title, where the character stands (trained cap, level) beside it, the tab strip under it; a status strip at the foot, on
every tab, saying what the last change did, with **Undo** (every input change copies the inputs first, so Undo puts
the whole copy back; a typed price puts its old fact back), and the open tab's hint while there is nothing else to
say. The window moves and resizes both ways; its place and size are kept account-wide in
`NuuProfessionsDB.windows` (OpenRoad kept a height per character). Each tab is its own file. Every change plans
again at once.

- **Plan** (`UI/PlanTab.lua`): the summary - the live skill and the target (typed, or **Automatic**), the
  **Only what I have** toggle (the `materials` option; see the price model), four
  figures (cost, sells, net, crafts); the **Sections** drop-down (one trip, tier, N recipes, every N skill levels) and, while prices
  are guessed, **Check prices**, left of **Make**. The table lists the steps under trainer-tier headings, read off `Planner:Outline`: a bar per recipe on a skill axis that follows the scroll (the rows in view set its range, at least 30
  skill levels), the step, its crafts and net. A run's **alts** button (closed by default, counting the choices but the one in use) folds open its choices
  (`Planner:WaysAround`: the planner's pick and every other recipe, pattern or not, that gives skill over the
  whole step, one solve each when first asked, all against the step's baseline), cheapest first, five at a time
  and the one in use wherever it falls, each with its cost a point, its crafts, what it costs more or saves
  against the planner's pick, a bar spanning the step, and **Use this** (`Planner:UseWay`: the recipe chosen for
  the step's skill levels only, a pattern also marked as in hand, the planner's pick clearing the choice; the run then
  shows `your pick`), or
  a highlighted **Using** that does nothing on the one in use. The order never depends on the choice, so taking
  one leaves the rows where they are. A right-click on a run gives Plan
  with it, the Sale of what it makes, Let the planner choose here (`Planner:ClearChosen` over the step's skill levels) and
  Show in Recipes. **Make** is the plan executed a step at a time: it makes the step the
  player clicked last (else the first not yet passed; that row is the table's selected row) from the profession window
  (`Client:Craft`: `C_TradeSkillUI.CraftRecipe` on Forever's modern window, `DoTradeSkill` with a count on a Classic
  one, `DoCraft` one at a time on the Craft window). A run makes what is left of it from the live skill at the
  confidence count (`NuuKit/Core/Crafting.lua`) and stops when the window shows its last skill (`StopTradeSkill`); a
  make or goal row makes its own count, capped by the materials carried. With the window shut the button reads
  **Open <profession>** and opens it on the recipe (`Client:OpenProfession`: `C_TradeSkillUI.OpenTradeSkill` with
  the profession's skill line, then `ProfessionsFrame.CraftingPage:SelectRecipe` once the window shows, as retail
  Zygor does); a left-click on a row does the same, and every order selects its recipe (`Client:FocusRecipe`).
  `Crafting:Button` picks between them. (Casting the recipe with `/cast` from a secure button, no window, was tried
  first and did not craft on Forever, 2026-09-26.) There is no "make the whole plan" button: the client takes one
  recipe per order, and buying, training and learning between steps need their own windows. OpenRoad's tracker
  craft steps carried the same button; NuuRoad keeps them.
- **Recipes** (`UI/RecipesTab.lua`): every recipe, in a list that draws only the rows in view (OpenRoad's pages
  of 50 are gone), with its colour bands drawn against the live skill and the target on a scale the rows in view
  set, where it is learned, what the route does with it, a **Goal** checkbox (a goal gets a row of its own under
  its recipe with its count, when, and what the route made of it) and the **Plan with it** drop-down (also on a
  right-click). Show filters (in range, in route, goals, prefer, never use, patterns I have, all) with counts, a
  Source filter, and a search over recipe, product and reagents, so every choice can be found and undone.
- **Materials** (`UI/MaterialsTab.lua`), which replaced both the old Prices tab and the shopping column: every
  material the route buys, in views (this route, the section holding the skill, guessed or missing, cheaper to buy, every material
  in range, not used), grouped by what each material is (can be made, sold by a vendor, auction house or
  gathered), so a Get it choice never moves a row. Each row has what is carried of what is needed, the price
  used and its source, the player's AH buy and AH sell fields, **Get it** (make it, buy, gather valued, gather free), what
  the rest costs, and **Plan with it** (planner decides, prefer it, never use it). A banner counts the guessed and
  missing prices, and a second what is made at a loss. Under the materials, **What you make**, each output with its sale price, AH sell field and
  **Sale** choice; a foot with what is left to buy, the route's materials and what its output sells for. Not used
  lists the materials turned off, with a field to turn off any other (`Planner:MaterialCandidates`).
- **Options** (`UI/OptionsTab.lua`): the tuning, in three sections - the route (optimise for, count as sold),
  shopping (confidence, auction house, bags) and prices (the estimate factor,
  Auctionator) - then the testing switch, Reset all, and **Appearance**: the kit's look picker for the planner
  window (`NuuProfessionsDB.look`; the kit keeps no settings).

The **Shopping list** (`UI/ShoppingList.lua`) is a small kit panel of its own, shown from the **Shopping list**
button in the planner's band (or `/nuuprof shop`), that stays up with the planner shut and closes from the kit's
close mark. Each section of a profession's plan that buys something is one list: with the default "one trip"
sections that is the whole route, named under the title ("Tailoring: Whole route 41-160"); with several lists
(another split, or a second profession planned) a full-width drop-down there picks one, each named
`<Profession>: <section>`, and **All sections** shows every list of a profession under its section's heading.
The rows stand under a heading per kind of shop (Vendor, Auction house, then Gather and In your bags), each shop's
heading with what is left to buy there, and what is done (carried, or ticked by hand) under Already have, last; an
item moves there when it is done and back when it is not. Each row is the item's icon with the count needed, its name, a second line saying where it comes from with its
price and what is carried ("Abigail Shiel, 10c each, you have 0"), and what the rest costs; the foot says how
many are still needed and what is left to buy. What the player makes on the way (a bolt of cloth) is a step, not
shopping, and is left off. An item is done once the bags hold what it needs (a green ring, a faded icon,
"Carried, 52 of 52"); a click on its icon ticks it by hand (what is in the bank, or what the player will do
without), kept until the item leaves the plan. The lists are what the planner last planned, kept per character
(`shoppingList` in the character's record) after every plan, so they do not move while the player shops: only
the bags and the skill are read live. The bags go to the earliest section first, an item goes once the skill
passes the last step that uses it, and a section with nothing left leaves the drop-down.

Buying is on the vendor's own window (`UI/VendorStrip.lua`): while the open vendor sells something the list in
view still needs, a strip of ours under its window says "From your <profession> list", with **Buy all** and what
everything costs there, and a row per item with its count, cost and **Buy**; those items also wear a mark on the
vendor's page (an accent edge and the count needed, painted after the game draws a page). Pressed, Buy buys what
is missing (`Domain/MerchantBuying.lua`), rounded up to the vendor's batches and held to its stock and the
player's money, one call every fifth of a second, checking the vendor's slot still holds the item, stopping when
the vendor closes, and saying in chat what it bought. Only money is spent: an item costing a currency or other
items is left to the player. The strip and marks are our frames on the vendor window; nothing of the game's is
changed. Nothing is searched or posted at the auction house.

The shared widgets are NuuKit's (`NuuKit/UI/`, see its `README.md` and `status.md`): `Select` (a drop-down),
`UI:OpenMenu` (the one choice menu, under a control or at the cursor, with a check on the current choice, a second
line per choice and a reason on a disabled one), `Disclosure` (a folding button with a chevron), `Table`,
`MoneyInput` and the window chrome with its status strip and Undo. Captions are sentence case.

Money is shown as its two largest coins, rounded to the second, with a zero coin left out: `1g 20s`, `2g`,
`1s 50c`, `75c` (ASCII only, no coin glyphs; the kit colours the coin letters, `Kit.FormatMoney`, and
`Prices:FormatMoney` is the same without colour, for sentences). Values are entered as text with every coin (`1g 20s 5c`), and a field
the player edits shows every coin back, so it reads as what they typed.

## Code layout

Paths are NuuProfessions' unless they say otherwise.

| File | Role |
| --- | --- |
| `Tools/ProfData/extract.py` | DB2 -> `Data/Professions/*.lua` (reuses OpenRoad's `Tools/ClientMap/casc.py`, `db2.py`) |
| `Tools/ProfData/crosscheck.py` | compares the extraction with wowforevertalents.com, lists every difference |
| `Data/Professions/*.lua` | generated recipe tables, one per profession (`Data/ProfessionsFull/` the testing set) |
| `Data/ProfessionTiers.lua` | authored skill caps, level gates, trainer costs known so far |
| `Tools/ProfData/recorded.py` | saved variables -> `Data/ProfessionRecorded.lua`, the trainer and merchant windows seen in play |
| `Config.lua` | `NuuProfessionsDB` (settings, the price book) and `NuuProfessionsCharacterDB` (known recipes, the planner's inputs) |
| `Domain/Prices.lua` | the price store: facts, overrides, effective buy and sell cost, depth |
| `NuuKit/Core/SkillUp.lua` | chance, expected crafts, variance (`Kit.SkillUp`) |
| `NuuKit/Core/Crafting.lua` | what a Make button asks for: crafts left to a skill or a count, and why it cannot (`Kit.Crafting`) |
| `Domain/ProfessionPlanner.lua` | goals, DP, refinements, the route's outline and sections |
| `API/Client.lua` | feature-detected trade skill, craft, trainer and merchant reads; `prof` log channel |
| `UI/Planner.lua` | the window shell: band, tab strip, status strip with Undo; planning; the Planner button on the profession window; `NuuProfessions.API`; traces every plan (inputs and route), change and action to the `planner` trace channel |
| `UI/PlanTab.lua`, `UI/RecipesTab.lua`, `UI/MaterialsTab.lua`, `UI/OptionsTab.lua` | the four tabs |
| `Tests/ProfessionPlannerTests.lua` etc. | pure-Lua tests (`Tests/TestRunner.lua`; the kit's own in `NuuKit/Tests/`); `Tests/UISmokeTests.lua` builds the window on the kit's stand-in for the client, with the kit's reset audit on |
| `Tools/SessionLog/` | the planner's playthrough, fuzz and replay tools the tests share |

## Phases

1. **Data, at `contentLevel = 20`.** Extract Leatherworking first (the example goals are leather). Run the
   wowforevertalents.com cross-check over the recipes in scope until the only disagreements left are explained.
   Hand-check 10 recipes against the client window. Read the scope report (the practical ceiling, and what the
   materials test dropped) and tune the item-level margin. Then extract the other professions at the same cap.
   Level 30 is a rerun when the beta opens it.
2. **Model and optimiser, tested outside the client.** Toy professions with known answers:
   - an orange-only chain;
   - a cheap green beating a dear orange;
   - resale flipping the choice;
   - a learn cost that is not worth paying;
   - a BoP pattern suggested with the right saving, and never used until accepted (trainer only);
   - planning with every pattern: one cheaper than the trainer recipe used and marked, a BoP one used when
     cheapest and flagged, I have the pattern taking the mark away, Never use leaving it out;
   - a BoE pattern's "worth buying under" price;
   - a refused recipe never used or suggested, even when it is the cheapest;
   - goals placed at their best skill and reducing the grind;
   - confidence changing counts and not the route;
   - replanning from a lucky skill;
   - the generated guide passing `Data/Schema.lua` (until the export went).
3. **Prices.** The store, the Prices tab (now part of Materials), and vendor prices from `ItemSparse` and merchant windows.
4. **Planner window and tracker.** The Plan, Goals and Recipes tabs; Start, Replan and Save as guide (Start and
   Save as guide went with the export); the Materials
   list at confidence counts.
5. **Client truth.** Known recipes and live colours from the trade skill window; trainer recording; the Enchanting
   (Craft API) path. Record every result in `docs/api-compatibility.md` and the in-client checklist.
6. **Refinements.** Intermediates as progress (done: make events and their skill), market depth, and the other
   crafting professions. Later, and not
   planned yet: the gathering professions, gathering routes, and "prefer time over gold" as a second cost weight.

## Open questions

1. **Reading the auction house.** May the planner read prices from an open auction house window when the player
   presses a button, searching only the plan's items? It is read-only and player-triggered, but it is more than
   the planner reads today. Reading another addon's saved prices (Auctionator), if installed, is a similar question.
2. **Default `when` for gear goals.** `best` (orange, most skill) can mean making a level 25 chest at level 18 and
   carrying it. Is that fine, or should gear default to the skill where the player can wear it?
3. **Help at the profession window.** Would selecting the step's recipe in the open profession window
   (`SelectTradeSkill`, no crafting) count as an allowed convenience? Pressing Create stays the player's.
4. **Persistence.** Settled for the beta: the client restores no SavedVariables, so the player's inputs, prices and
   known recipes are session-only in practice. What trainers and merchants showed ships as addon data instead
   (`Data/ProfessionRecorded.lua`), unpriced materials are estimated, and a recipe learned at a trainer is marked
   known at once from the learn event.
5. **Which crafting profession comes after Leatherworking.** Gathering professions are out of scope for now.
6. **Forever differences.** Recipes and colour bands are largely new (see the cross-check section). The skill caps,
   level gates and the one-point-per-craft rule still need an in-client check. At the level-20 cap, the key check
   is whether Expert (to 225) can be trained at level 20.
7. **wowforevertalents.com data.** Should we ask Milenkas whether NuuProfessions may ship the facts only the site has
   (merchant stock, the SoD grouping), with credit? Otherwise we use the site only as a cross-check and record those
   facts ourselves in client.
