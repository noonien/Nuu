# NuuRoad - WoW: Forever guide addon plan

## Product intent

NuuRoad is an in-game guide reader and authoring tool for WoW: Forever. It helps players follow curated or personal
guides for leveling, professions, achievements, collections, and other non-combat goals. A guide is useful at a glance,
but can also explain the *why* behind a step. Players can duplicate a guide, adjust it for their character, and publish
a portable version without needing to edit Lua.

### Principles

- **Player-directed:** automate only low-risk, user-configured convenience actions that Forever permits; never make
  combat, target-selection, quest-order, reward-choice, or route decisions for the player.
- **Offline first:** all packaged and user-created guides work without a web service. Local creation, editing, and use
  take priority; sharing is explicitly deferred.
- **GUI-only:** all player-facing features, including diagnostics, guide selection, progress controls, settings, and
  authoring, are accessed through in-game windows and buttons. Do not ship slash commands, console commands, or other
  text-command workflows.
- **Player-tunable presentation:** provide a compact in-game Options window for visual preferences such as panel
  opacity and navigation presentation. Persist these preferences locally and keep the tracker readable at every value.
- **Usable while playing:** a compact tracker handles the current task; a full browser/editor is available out of
  combat.
- **Creator-friendly:** structured editing, preview, validation, undo, and safe drafts make basic authoring
  approachable.
- **Viewer/editor parity:** whenever the viewer gains a user-visible guide feature, add the corresponding editor
  controls and validation in the same change so creators can build a test guide in-client. Preserve unsupported
  existing data without silently changing its node type or fields.
- **ASCII-only text:** use only ASCII characters in addon source, guide data, and player-facing strings. The Forever
  client cannot reliably render UTF-8; use plain ASCII labels such as `N`, `NE`, and `>` for direction and controls.
- **Beta-resilient:** isolate game APIs behind adapters and test against the actual Forever client on every beta update.

## Constraints and assumptions

WoW: Forever's beta is reported to use the modern restricted addon API. The exact supported surface is still moving, so
do not assume Classic-era APIs, secure-frame behavior, map pins, quest data, achievement APIs, or external networking
work until verified in the beta client. This addon must remain informational and avoid combat automation by design.

Maintain `docs/api-compatibility.md` as an evidence-based matrix of each API we need, its observed Forever-beta
behavior, build number, fallback, and test date. Use feature detection and graceful degradation, not a hard-coded
client-version guess, where practical.

## Guide-porting reference addons

Use the Zygor and RestedXP addons at
`/mnt/d/BNet/World of Warcraft/anniversary/Interface/AddOns` as implementation and UX inspiration while planning or
building guide-porting support. In this workspace the installed client directory is currently named
`/mnt/d/BNet/World of Warcraft/_anniversary_/Interface/AddOns`; use that equivalent path when the requested path is
not present. Study their guide taxonomy, navigation presentation, progress affordances, and edge cases, but keep
NuuRoad's player-directed behavior and declarative, non-executable data model. Do not copy source code or content
unless its license and explicit permission allow the intended distribution. The complete implementation plan is in
`GUIDE_PORTING_PLAN.md`.

## Target experience

1. On first use, a player selects a guide or imports one.
2. The tracker shows the current section, one actionable step, optional notes, manual controls, and a progress
   indicator. It can also show concurrent kill/collect objectives.
3. When available, an arrow, target markers, quest/item/map context, achievements, and profession state make the step
   richer; when unavailable, the text remains fully usable.
4. The Guide Browser filters guides by category, faction, race/class, level, profession, expansion/content phase, and
   completion state.
5. Creator Mode lets a player create, edit, reorder, validate, preview, clone, export, import, and delete only their own
   guides. Packaged guides are immutable and can be cloned into a personal draft.

## Guide data model

Use a versioned, declarative Lua-table schema. Packaged guides live in separate load-on-demand modules; user guides are
stored in SavedVariables. Keep guide data independent of UI and Blizzard API return shapes.

```lua
Guide = {
  kind = "guide", schema = 1,
  id = "nuuroad:leveling:human-1-10",
  updated = 1789862400,                     -- seconds since the epoch
  title = "Human 1-10", author = "NuuRoad", category = "leveling",
  tags = { "alliance", "human" }, levels = { from = 1, to = 10 },
  source = "...",
  cond = { faction = "Alliance" },
  data = {
    map = 1429,
    sections = {
      { title = "Northshire", steps = {
        { type = "accept", quests = { 12345, 12346 }, npc = { 67890 },
          note = "Group if the area is busy." },
      } },
    },
    npcs = { [1429] = { [67890] = { name = "...", at = { 5000, 5000 } } } },
  },
}
```

This is guide format v1 (`docs/examples/guide-v1.lua`), not the runtime
shape. `Steps:Expand` reads it once and builds everything derived - titles, step positions, section and group
spans, references, completion rules - so the runtime is free to hold whatever
serves the tracker. Steps run in order; a branch is a `choice` whose options
name labels, never positions, so nothing authored has to be renumbered when a
step is inserted.

### Node and action taxonomy

Model a guide as a directed graph of typed nodes, rather than a flat script. A section is a presentation grouping; nodes
define the actual flow. Every node has text, optional location/references, a completion policy, and an explicit `next`
edge (or choice edges). Authors work through friendly forms; no expressions, Lua, macros, or arbitrary scripts are
stored in guide data.

- **Flow:** `section`, `action`, `note`, `choice`, `checkpoint`, and `end` explain, branch, resume safely, or finish.
- **Movement:** `travel`, `hearth`, `flight`, `portal`, and `instance` give destinations, routes, and map context.
- **Quest:** `acceptQuest`, `questObjective`, `turnInQuest`, and `abandonQuest` track the quest lifecycle and
  objectives.
- **World interaction:** `talk`, `kill`, `loot`, `collect`, `gather`, `useItem`, `interact`, `equip`, `buy`, `sell`, and `bank`
  describe player actions with item/NPC/object references and counts.
- **Guidance:** `arrow`, `poi`, `targetMarker`, `mobRoute`, and `travelRoute` provide an arrow destination,
  map/minimap points of interest, optional kill-target marks, multi-point farming areas, and alternate travel paths.
- **Character growth:** `levelTarget`, `xpTarget`, `train`, `talent`, `skillTarget`, `professionRecipe`, `craft`, and `skillUp`
  handle level, exact XP, training, profession rank, and crafting goals; `skillUp` makes an item until a skill rank lands, which is how profession guides really read.
- **Progression:** `achievement`, `reputationTarget`, `currencyTarget`, `collectionTarget`, and `itemCountTarget`
  support achievements, standing, currencies, collections, and inventory goals.
- **Time and availability:** `waitFor`, `dailyReset`, `weeklyReset`, `cooldownReady`, and `eventWindow` represent
  time-gated work without blocking the guide.
- **Parallel work:** a step carried alongside a later one (`with`), from an earlier one (`from`), or `sticky` stays
  on the card until done.

Use `action` as the flexible text-first escape hatch for uncommon behavior, rather than creating a special node for
every verb.

### Route model

Routes are small, declarative waypoint graphs, not one fixed polyline. A route has named points and directed or
bidirectional links, optional map transitions, arrival radii, and author notes. Links may carry a cost, requirements,
and a route role.
At activation, Navigation chooses the reachable lowest-cost path from the player's nearest valid point to the requested
destination; the player can always choose another offered path or advance manually.

- **Travel routes** model approach paths with intermediate points: for example, road junction -> cave entrance -> tunnel
  fork -> chamber. They support alternate entries and exits, one-way drops, flight/boat transitions, and a fallback route
  selected from the player's current position.
- **Mob routes** model an area or circuit, not a predicted live spawn. A node can reference several clusters or loops,
  each with bounds, waypoints, eligible mobs, and a weight/priority. The arrow cycles the selected loop; POIs show all
  viable clusters so the player can choose a less crowded location.
- **Branch rules** are simple predicates, such as current zone, nearest entrance, known flight path, quest state, or
  faction. They may select among authored alternatives; they cannot run arbitrary pathfinding or hidden scripts.

```lua
route = {
  kind = "travel", destination = "cave-chamber",
  points = {
    { id = "west-road", mapID = 1, x = .42, y = .58 },
    { id = "cave-mouth", mapID = 1, x = .51, y = .63, note = "Enter the cave" },
    { id = "fork", mapID = 2, x = .31, y = .44 },
    { id = "cave-chamber", mapID = 2, x = .56, y = .71 },
  },
  links = {
    { from = "west-road", to = "cave-mouth", cost = 1 },
    { from = "cave-mouth", to = "fork", mapTransition = true },
    { from = "fork", to = "cave-chamber" },
  },
}
```

### Conditions, targets, and completion

All state logic uses a small declarative predicate tree: `all`, `any`, `not`, plus named predicates. A predicate can
control visibility, eligibility, a branch, a reminder, or observed completion. It cannot run code. The Creator Mode
renders it as a readable condition builder (for example, "Show if Herbalism skill is at least 150").

- **Character:** faction, race, class, level, specialization, content phase, difficulty, and hardcore mode.
- **Quest and achievement:** accepted/completed/turned-in quest, objective count, achievement, and criteria count.
- **Profession:** has profession, current/max rank, known recipe, craftable count, or a target such as `Mining >= 125`.
- **Inventory and equipment:** item quantity, equipped item, currency/gold threshold, known spell, or collected
  mount/pet/toy.
- **Player state:** aura present/absent by spell ID and stacks, reputation standing/value, zone/subzone, and
  instance/group.
- **Experience:** level at least/exactly; current-level XP at least an exact amount or percentage; total earned XP
  only if Forever exposes it reliably.
- **Time:** server window, daily or weekly reset elapsed, cooldown ready, or duration elapsed after the node began.
- **Local guide state:** manually checked node, named checkpoint reached, or another node/group completed.

`waitFor` is a non-blocking node, never an instruction to freeze the guide. It has a condition, optional expected/reset
time, explanatory text, and `whileWaiting` choices such as "continue to side activities," "snooze," or "mark manually."
If the requirement cannot be observed on Forever, the UI labels it as manual rather than pretending it knows the state.

Store numeric progress precisely: XP as `{ level = 3, currentXP = 1150 }` or `{ level = 3, percent = 82.1 }`, profession
rank as `{ professionID = ..., atLeast = 150 }`, and auras by spell ID with optional minimum stacks. The UI may display
percentages, but completion comparison should use the underlying integer API value to avoid rounding errors.

Every node supports `manual`, `observed`, `allChildren`, or `anyChild` completion. Observed completion is an enhancement
only: preserve a manual "complete / skip / undo" control for API gaps, stale quest data, unusual character history, and
beta regressions. Conditions that cannot be evaluated are `unknown`, not false; show the author/player why and offer the
manual route.

## Architecture and initial layout

```text
NuuRoad/
  NuuRoad.toc                 # metadata, SavedVariables, load order
  Core.lua                     # bootstrap, event bus, module registry
  Config.lua                   # defaults and migrations
  Data/
    Schema.lua                 # schema versions and validation
    BuiltIn/                   # curated guide packs, load on demand
  Domain/
    GuideRepository.lua        # packaged/user/draft lookup and lifecycle
    Progress.lua               # per-character progress and manual completion
    KillTracking.lua           # guide kill/collect objectives and target-marker policy
    Navigation.lua             # arrow, POIs, routes, and minimap/map integration
    QuestInteraction.lua       # permitted quest-dialog convenience actions
    Eligibility.lua            # character/profile matching
  API/
    Client.lua                 # feature-detected WoW API adapter
    Quest.lua Map.lua Minimap.lua Targeting.lua Profession.lua Achievement.lua
  UI/
    MainWindow.lua Diagnostics.lua Tracker.lua Browser.lua GuideView.lua Editor.lua Preview.lua
    Widgets/                   # reusable scroll lists, forms, dialogs
  Tests/                       # pure-Lua test runner and fixtures
  docs/
    api-compatibility.md
    guide-schema.md
    authoring.md
```

Use a small module registry and explicit dependencies; avoid a large global namespace. Saved data lives under one root
(`NuuRoadDB`) with separate account-wide user guides/drafts/settings and character-keyed progress. All saved records
carry schema versions; migrations are idempotent, backed up, and logged.

## Implementation order and delivery phases

### Recommended implementation order

Build in thin vertical slices. Each slice must be playable with a tiny fixture guide before adding the next capability;
do not build the full editor, route engine, or large guide library in isolation.

### Living fixture guides

Maintain a small set of intentionally playable built-in **fixture guides** alongside production content. A fixture is
both a player-visible example and an in-client regression test: it uses only the capability under development, has a
clear expected result, and includes a manual fallback where an API integration is unavailable. Update the relevant
fixture in the same change as every schema, progress, UI, navigation, or adapter change; do not let fixtures drift from
the supported model. Keep fixture IDs stable so saved-progress and migration testing remains meaningful.

- Add one narrowly scoped fixture per new slice (for example `nuuroad:fixture:choice`, `:travel-poi`,
  `:quest-objective`, `:objective-group`, and `:predicate`).
- Fixtures must be short, understandable without developer tools, and tagged `fixture`; production guides must not
  depend on them.
- The in-client smoke checklist records each fixture's expected state and the exact fallback exercised.

1. **Client spike:** create the loadable shell, a GUI Diagnostics panel, SavedVariables, and the Forever compatibility matrix.
   Verify the API boundaries first, especially pins, quest dialogs, target markers, and quest/objective events.
2. **Stable domain core:** implement the versioned schema, validator, migrations, repository, local progress, and
   pure-Lua fixtures. Include node IDs, choice edges, predicates, and route data now, even if the first UI ignores
   advanced nodes.
3. **Minimal reader and editor:** load one short fixture, show one step in a movable tracker/full reader, and support
   manual complete, skip, undo, reset, reload, and resume. In the same slice, support GUI creation and clone-to-edit
   for the node types the reader can render well. This is the first end-to-end usable build.
4. **Navigation slice:** add one destination POI, the arrow, and map/minimap rendering; then add ordered intermediate
   points. Add the matching editor fields and a playable fixture in the same slice; validate arrival radius and manual
   next-point controls before graph path selection.
5. **Quest slice:** add read-only quest state and objective completion, then optional accept/turn-in at an already open
   dialog. Keep the feature independent of guide order, with reward selection and fallback clicks left to the player.
6. **Kill/grind slice:** implement `kill`/`collect` counts and concurrent objective groups; then add multi-cluster grind
   POIs, loop cycling, and only afterward the API-gated target-marker option.
7. **Route graph slice:** implement alternate links, map transitions, path picking, and nearest-valid-entry selection.
   Test cave entrance and multi-loop grinding fixtures before applying it to production guides.
8. **Stateful guidance:** add the predicate evaluator and displays for level/precise XP, professions, auras, reputation,
   cooldowns, and non-blocking waits. Ship each integration only after its API adapter is verified on Forever.
9. **Advanced Creator Mode:** extend the lock-step editor with typed-node forms, conditions, choices, POIs, routes,
   objective groups, drafts, undo/redo, reorder, and validation previews as their matching reader features ship.
10. **Content and hardening:** create representative leveling, profession, and achievement guides; profile the tracker;
    add migration/regression fixtures, accessibility work, and release checks.

### 0. Beta discovery and technical spike

- Create a minimal enabled addon that records client build/flavor and exposes it in a GUI Diagnostics panel.
- Verify the actual Forever `.toc` interface number, loading rules, Lua runtime, SavedVariables, GUI-frame behavior,
  and error reporting.
- Test the read-only APIs needed for player identity/level, quests, professions, achievements, map/coordinates,
  minimap, target/aura state, combat-log/objective events, tooltips, links, and UI frames.
- Separately test permitted convenience actions: quest acceptance/turn-in at an open quest dialog, quest reward choice,
  quest watch/tracking, raid target markers, and map/minimap pins. Record combat and hardware-event restrictions.
- Record findings and fallbacks in `docs/api-compatibility.md`; add a manual smoke-test checklist for each beta patch.
- Decide which integrations enter MVP only after this evidence exists.

**Exit:** the addon loads cleanly on the beta client, persists a setting, and has a documented compatibility baseline.

### 1. Foundation and read-only guide player

- Add the TOC, namespace, lifecycle events, defaults, error-safe logging, and an in-game NuuRoad window. Its landing
  view provides guide browsing, settings, diagnostics, and help without slash commands.
- Implement schema validation, repository lookup, guide selection, manual progress, resume state, reset, and
  per-character/account-wide scope choices.
- Build the compact movable tracker and full guide-reader window. Provide visible Complete, Skip, Undo, Reset, and
  Close controls; no text command is required for any reader action.
- Ship the matching basic GUI editor: New guide, clone-to-edit, title/action/note fields, add-step, validation, local
  save, and production-tracker preview. A node type may be authorable only when the reader has a clear presentation
  and manual fallback for it.
- Ship 2-3 short representative built-in guides (one leveling, one profession, one achievement) to prove the schema
  instead of filling a huge content library.
- Add text search and filters over guide metadata.

**Exit:** a player can install the addon, choose a packaged guide, complete it manually, reload, and resume at the
correct step without errors.

### 2. Contextual enhancements with fallbacks

- Add API-adapter-backed display of validated quest/item/spell/NPC links and tooltips; preserve text when a reference is
  unknown.
- Add optional objective/profession/achievement status indicators when observed safely. Provide a visible "API
  unavailable / mark manually" state otherwise.
- Build the movable guide arrow with one simple, deterministic bundled TGA texture, smoothly rotated at runtime rather
  than separate image files for each heading. Apply a small heading dead zone to ignore facing noise, and show distance,
  destination, arrival radius, and an explicit hide/snooze control. It points at the current node's POI or selected
  route waypoint; it does not move or steer the character.
- Render guide POIs on the world map and minimap when permitted: destination, quest giver/turn-in, vendor/trainer,
  objective area, route waypoint, and kill target. Let players filter categories, hide individual POIs, and disable
  minimap icons. Never make a pin necessary to follow a guide.
- Add waypoint-graph routes with intermediate points, map transitions, arrival radii, link costs, and a text fallback.
  Select an authored alternate path from the player's current position; always show a path picker/next-point control.
- Support multi-cluster mob routes: several spawn areas and/or loops can belong to one grind target, appear together as
  POIs, and be cycled or manually selected. Use area/route guidance only; do not claim exact live mob positions.
- Track kill targets from quest objectives and explicit `kill` nodes using verified quest/combat events. Show count,
  remaining amount, and target name; when detection is unavailable, keep a manual counter and completion control.
- When allowed by the Forever client, apply a configured raid-target marker only to a matching current-guide kill
  target. Never change the player's selected target, marker a nonmatching unit, or run protected marker actions in
  combat.
- Add optional quest-dialog convenience: at an already open dialog, accept or turn in any eligible guide-relevant
  quest regardless of the guide's current order. Do not auto-select multi-item rewards, abandon quests, or hide
  unavailable quests; show the player what was handled and fall back to a normal click when the API/hardware event
  requires it.
- Add eligibility warnings (level/faction/profession) that can be overridden.

**Exit:** arrow, POIs, routes, kill tracking, target marks, and quest-dialog actions work when permitted; each one
degrades to clear prose and manual controls without blocking reading or progression.

### 3. Advanced Creator Mode

- Extend the existing New guide and clone-to-edit flow with a dedicated Creator Mode, drafts, and recovery.
- Build a section/step editor with add, edit, duplicate, delete, drag/reorder, optional-step and choice controls. Use a
  simple rich-text subset - plain text, line breaks, links/IDs - not arbitrary executable Lua.
- Provide guided reference fields for IDs and locations; look up/display resolved names only through the adapter when
  available.
- Implement draft autosave, explicit Save/Discard, undo/redo within a session, preview using the production Guide View,
  and blocking validation before publish.
- Enforce safe limits: title/body lengths, nesting depth, step count, total saved size, and no functions, frame names,
  scripts, or executable expressions in data.

**Exit:** a nontechnical user can make a playable multi-section guide entirely in game and retain it after reload.

### 4. Content, quality, accessibility, and release

- Establish a content contribution template, editorial checklist, attribution and license policy, and a
  content-versioning/review workflow.
- Expand only validated guide categories, prioritizing complete routes over many partial ones. Keep guide packs separate
  for optional loading.
- Add keyboard navigation, scalable fonts, high-contrast states, screen-reader compatible labels where the UI supports
  them, and color-independent status cues.
- Profile startup, memory, UI redraws, and SavedVariables size; defer noncritical guide packs and avoid polling when
  events suffice.
- Add release notes, migration tests, beta feedback instructions, packaging checks, and a compatibility/support matrix.

## Deferred: sharing and external integrations

Do not build import/export strings, addon-message transfers, a guide-exchange API, website publishing, or cross-addon
compatibility in the current implementation. Preserve the versioned declarative schema and validation boundary so a
future sharing feature can use them without redesigning stored guides. Revisit this only after Creator Mode is reliable
and users can comfortably make and maintain guides locally.

This does not prevent the reviewed, developer-only, build-time source conversion described in
`GUIDE_PORTING_PLAN.md`. It must never load, execute, distribute, or dynamically import a third-party addon in the
game client.

## Quality gates

- **Pure Lua tests:** schema validation, migrations, ordering, progress rules, eligibility, serialization round trips,
  malformed-import rejection, and size limits; run outside the client when possible.
- **In-client smoke tests:** fresh install, reload, login/logout persistence, guide switching, reset, editor draft
  recovery, arrow/POI route display, kill progress, marker restrictions, quest-dialog actions, missing API fallback,
  and combat-state UI behavior.
- **Regression fixtures:** save representative guide payloads from every schema version and test migrations forward.
- **Performance budget:** document baseline measurements on the beta client; block release for recurring errors,
  unbounded SavedVariables growth, or visible tracker hitches.

## Decisions to make before Phase 3

1. The project license and whether authors retain their guide copyright.
2. MVP locales: launch with `enUS` only, or establish localization keys now.
3. The initial content scope - recommended: 1-10 leveling, one primary profession, and one achievement route - based on what
   Forever beta actually contains.

## Definition of a first public beta

NuuRoad is ready for users when it loads on the current Forever beta without errors; resumes manual progress reliably;
offers three complete sample guides; lets users create, edit, validate, preview, and save a personal guide; and
documents every unavailable API-driven enhancement with a working manual fallback.
