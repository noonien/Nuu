# NuuRoad guide porting plan

## Objective and boundaries

Port authorized guide content from the RestedXP (`RXPGuides`) and Zygor
(`ZygorGuidesViewerClassicTBCAnniv`) addons into NuuRoad's native, versioned guide format. Deliver complete,
playable NuuRoad guide packs: not a source-addon compatibility layer, a runtime Lua loader, or a verbatim dump of
foreign scripts.

Reference root requested for this work:

`/mnt/d/BNet/World of Warcraft/anniversary/Interface/AddOns`

The currently installed equivalent is
`/mnt/d/BNet/World of Warcraft/_anniversary_/Interface/AddOns`. Use both addons for product and implementation
inspiration: their guide organization, tracker behavior, waypoint/POI presentation, conditions, sticky objectives,
and player recovery paths are valuable references. NuuRoad must retain its own GUI-only, player-directed behavior
and its declarative data boundary.

The port is a developer-only build pipeline. The shipped addon may contain only NuuRoad-native data and code; it must
not read source-addon directories, `loadstring`/execute source guide Lua, embed the source parsers in the game client,
or claim source-addon compatibility.

## Gate 0: permission, scope, and provenance

1. Create `docs/guide-porting/provenance.md` before converting content. For every source file and produced guide,
   record source addon/version/path, author/copyright notice, license or written permission, intended distribution,
   reviewer, and source hash.
2. Obtain permission that covers both the text/data and any bundled images, links, translations, and derived routing
   work. A code license alone is not assumed to license guide content. Exclude trial, paid, placeholder, or otherwise
   unlicensed content until explicitly cleared.
3. Define the initial authorized scope by client flavor/content phase. Keep Forever/Camelot data separate from Classic,
   TBC, SoD, retail, and other source branches. Do not silently port content whose quest IDs, maps, or mechanics differ.
4. Establish attribution and removal/correction policy in the shipped pack metadata and release notes. Preserve source
   provenance in a non-player-facing manifest where required; do not expose proprietary source text as diagnostics.
5. Freeze an audited source snapshot by addon version and file hash. Changes in either addon create a new import batch,
   never an unreviewed overwrite of NuuRoad data.

**Exit:** each candidate guide is authorized, flavor-compatible, and traceable to an immutable source snapshot.

## Source inventory and selection

1. Write `tools/guide_port/inventory.lua` (or an equivalent host-side script) that reads TOC/XML include order and
   guide registrations without executing source addon code. Generate `build/guide-port/inventory.json` containing
   addon, file, guide name/group, content flavor, faction/class/race gates, level range, category, trial/placeholder
   state, source hash, and parser status.
2. Inventory RestedXP's `Guides/forever` first, then the applicable Classic guide files and optional profession,
   dungeon, daily, attunement, farming, talent, and survival categories. Recognize its registration wrapper, metadata
   directives (`#name`, `#group`, `#subgroup`, `#next`, `#defaultfor`, seasons), `step` blocks, `#` controls, and
   dot commands.
3. Inventory Zygor's applicable `Guides-*` trees using `RegisterGuide` and `RegisterGuidePlaceholder`. Capture the
   menu path and registration metadata separately from the step body. Treat placeholder and trial registrations as
   excluded unless authorized and intentionally supported.
4. Produce a reviewed source selection manifest (`sources.yaml`) with explicit include/exclude decisions. Start with
   one short, non-trial Forever starter guide from each authorized source and expand by complete category, not by raw
   file count.
5. Record collisions: same quest route, contradictory instructions, duplicated guide names, and cross-source variants.
   Choose one editorial owner per NuuRoad guide; never merge competing scripts mechanically.

**Exit:** the selected scope, exclusions, and conflicts are visible and reviewable before conversion begins.

## Native port contract

Extend the schema and corresponding reader/editor/progress/validation support before converting a source feature.
Every translated node must preserve source provenance, have a readable manual fallback, and be representable without
executable expressions.

| Source construct | NuuRoad representation and required behavior |
| --- | --- |
| Guide title, group/menu, author, level range, flavor, next guide | `meta` plus a pack manifest and explicit guide/section links; Browser filters for category, faction, class, race, level, phase, and source attribution. |
| `step` / Zygor `step` | One or more typed nodes in a section, retaining source-order and a stable generated source key. Split only when independent completion/visibility needs it. |
| `accept`, `turnin`, `complete`, quest objective flags | `acceptQuest`, `turnInQuest`, or `questObjective` with quest/objective IDs, NPC/object references, observed completion where supported, and manual complete/skip/undo. |
| `kill`, `collect`, `loot`, item counts, vendor/buy/sell, equip/use/interact | Typed action nodes with IDs/counts and target/item refs; support multiple eligible NPCs/items and a manual counter when the client cannot observe state. |
| `goto`, map markers, loops, `noway`, radius | Location plus POIs, travel route, or mob route. Preserve all alternate markers/loops; show text and manual next-point fallback if map APIs fail. |
| talk/target/trainer/flight/hearth/portal/instance/death skip | Existing movement/world node types plus refs and safety notes. Never automate targeting, travel, death, rewards, or protected interaction. |
| XP/ding, level, skill, training, reputation, currency, achievements, recipes | Existing progression node types and declarative predicates; use exact values/IDs when known and mark unknown APIs as manual. |
| `only if`, RXP `<<`, season/hardcore/xp-rate and source conditions | Predicate tree and choice/visibility edges. Add only explicitly defined, observable predicates; retain unsupported conditions as conversion blockers or reviewed manual notes, never as arbitrary Lua. |
| labels, requires, complete-with, sticky, optional, future | Stable node IDs, dependency/visibility edges, `objectiveGroup`, optional/reminder semantics, and guide-state checkpoints. A sticky objective must remain visible concurrently and complete independently. |
| Zygor `|tip`, notes, videos/links, formatting/icons | Sanitized ASCII body/notes and a safe rich-text subset. Preserve only authorized URLs; remove source UI markup, textures, color codes, and unsupported links. |
| choices, alternative paths, source `next` | Explicit `choice` nodes and declarative branch rules. Browser-to-browser continuation must be player-confirmed and never silently select a route. |

Add these schema fields/limits where absent: `meta.contentPhase`, `meta.source`, `meta.sourceGuideKey`, `meta.license`,
`meta.attribution`, `meta.packID`, `meta.tags`; node `source` provenance; `visibility`/`eligibility` predicate;
`dependencies`; `optional`; `refs.objects`, `refs.items`, `refs.spells`, `refs.quests`, `refs.npcs`; normalized
locations; `objectiveGroup` membership; safe `links`; and a structured `conversionNotes` field excluded from the
player tracker. Validate all references, edge targets, duplicate source keys, ASCII policy, string/array/node/route
limits, URL allowlist, and absence of functions/cycles.

**Exit:** every construct in the approved source corpus has an approved mapping, an explicitly recorded exclusion, or
a tested schema/UI/API implementation; no converter fallback silently degrades it to opaque prose.

## Build-time conversion pipeline

1. Keep converter code and generated intermediates outside addon load order: `tools/guide_port/`,
   `build/guide-port/`, and `Data/Packs/`. Add `tools/guide_port/README.md` with pinned interpreter/dependencies,
   reproducible commands, source-root configuration, and no-network operation.
2. Implement lexical readers for the two guide DSLs. They may parse registration calls and long-string guide bodies,
   but must not execute Lua or call WoW APIs. Fail closed on dynamic registration, concatenated/evaluated guide bodies,
   unsupported syntax, malformed directives, or parser ambiguity.
3. Normalize each parsed guide into a source-neutral intermediate representation (IR): source location/hash, metadata,
   ordered steps, directives, conditions, commands, locations, markers, messages, links, and comments. Preserve line
   spans so every output node can be traced to its input.
4. Translate IR through an explicit, versioned mapping table into NuuRoad tables. Generate deterministic guide IDs
   (`nuuroad:<pack>:<slug>`) and stable node IDs from source guide key/step/command identity; do not use array indexes
   alone, so source edits preserve player progress where semantics are unchanged.
5. Run a normalization pass: resolve zone/map aliases using a maintained Forever mapping table; normalize 0-100 versus
   0-1 coordinates; deduplicate adjacent locations; turn multi-marker targets into POIs/clusters; split mixed commands
   only where dependencies require it; remove UI markup; enforce ASCII; and attach content-phase/faction/class gates.
6. Resolve references against versioned Forever lookup tables for quests, objectives, NPCs, objects, items, spells,
   maps, professions, and reputation. Report unknown, mismatched, removed, and ambiguous IDs with source line spans.
   Do not guess missing IDs from names.
7. Emit four artifacts: native pack Lua files; a human-readable conversion report; a machine-readable unresolved-items
   report; and a provenance manifest. Generated Lua must be static tables only and pass `Schema:Validate` before it is
   copied into `Data/Packs/`.
8. Require deterministic output: same approved snapshot and converter version produce byte-identical generated pack
   data and reports. Check this in CI.

## Required NuuRoad implementation slices

1. **Pack loading and browser:** add manifest-driven optional built-in packs, deterministic load order, enable/disable
   settings, source/phase/version visibility, conflict-free IDs, upgrade migrations, and Browser filters matching port
   metadata. Packaged content remains immutable; cloning creates a personal guide without altering provenance.
2. **Schema, repository, and progress:** implement the port-contract fields, graph/dependency validation, stable node
   identity, guide/pack revision migration, source-hash-aware progress handling, and a resume screen when a revised
   guide changes or removes the player's current node.
3. **Conditions and branching:** implement a pure predicate evaluator with three-valued result (`true`, `false`,
   `unknown`), diagnostics, and a GUI manual override. Add only client-verified predicates for faction/race/class,
   level/XP, quest state/objectives, item/equipment, spell, profession, reputation, zone/instance, hardcore, phase,
   and time; convert unsupported source logic into a blocker or a review-approved manual note.
4. **Objectives and parallel work:** implement observed/manual quest objective, kill, loot, collection, XP, training,
   and profession progress; plural targets; manual count editing; `objectiveGroup` lifecycle; sticky display;
   `completewith` range handling; optional/future/reminder display; and safe skip/undo/reset behavior.
5. **Navigation:** implement named-map resolution, locations, POI categories, marker filtering, multiple markers,
   route/mob-loop selection, arrival radii, map transitions, arrow text fallback, and an explicit player-controlled
   alternative/next-point picker. Use source waypoints as authored guidance, never live-path prediction.
6. **Reader and tracker:** render titles, sanitized notes, references/tooltips, requirements, safety warnings,
   optional/status labels, links, unresolved-data notices, parallel objectives, and source attribution. Make every
   observed feature manually completable and preserve the current tracker state across reload.
7. **Creator parity:** add GUI viewing/editing support for every shipped ported node field, condition, POI/route,
   group, optional flag, and link. Preserve unsupported legacy fields on clone/edit rather than dropping them. Provide
   a source-provenance read-only panel for packaged guides and remove/replace attribution correctly on player clones.
8. **API adapters:** fill the Forever compatibility matrix and implement feature detection/events for each observed
   condition and progress type. Isolate all game API calls, throttle updates, handle combat restrictions, and report
   unknown state rather than false completion.

## Editorial conversion and review

1. Treat generated output as a draft. A content reviewer checks every converted guide for route correctness, quest
   order, prerequisites, rewards left to the player, faction/class/race/phase gates, coordinates, count targets,
   external links, grammar, ASCII-only text, and player-directed safety.
2. Reconcile source conflicts editorially. Prefer a single coherent NuuRoad route with explicit choices over blended,
   duplicated instructions. Document the selected source/version and substantive deviations in the manifest.
3. Preserve meaningful author tips as concise, authorized notes. Rewrite source-specific UI instructions (for example,
   click-to-confirm wording, texture markup, or source-addon settings) into NuuRoad controls or plain player actions.
4. Do not port automation or policies that conflict with NuuRoad: automatic target selection, combat actions,
   reward choice, route choice, or arbitrary script conditions. Keep a visible manual instruction where useful.
5. Review the same guide on a clean character and a progressed/atypical character. Validate alternate branch entry,
   skipped quests, already-completed objectives, unavailable NPCs, map/arrow failure, and manual recovery.

## Test and release gates

1. Unit-test both parsers with representative valid and invalid fragments from each approved syntax feature; include
   escaping, long strings, nested conditions, repeated directives, multiple map markers, labels/requires, sticky and
   complete-with behavior, comments, and malformed data. Assert that parsing never executes input.
2. Snapshot-test IR and generated NuuRoad tables. Add mapping coverage tests: every source command/directive found in
   the approved inventory must map, be intentionally excluded, or fail the build with a source location.
3. Run schema, graph, reference, ASCII, URL, size, provenance, determinism, and pack-load validation in CI. Reject
   unreviewed generated changes and any unresolved required reference.
3a. Run `Tools/CompareGuideOrder.lua <port> <source> "<#name>"` on every RestedXP-derived port. It matches each
   quest reference in the port to where that reference appears in the named source registration, walks our steps
   looking for a position that only ever moves forward, and reports any step that cannot find one - plus any step
   whose coordinates resolve on a different map than the source's `.goto` for it. Between them those two checks
   caught the Thunderhorn well and the Bael'dun digsite ported the wrong way round, which sent the player east and
   back again, and the Ragefire pickups ported as a Mulgore step when Rahauro stands in Thunder Bluff.
   Pass the registration's `#name`: one RestedXP file holds the same route several times over, once per experience
   rate, and without it matching wanders into a duplicate and calls everything after it out of order. The check does
   not apply to a Zygor-derived port, whose source is a different format entirely.
   Its reports are candidates, not verdicts: a step the source carried with `#completewith` legitimately sits
   elsewhere in our order. Read the source around the reported line before moving anything, and record in the port's
   header comment any divergence kept on purpose.
3b. Run `Tools/CheckGroups.lua [<guide>.lua ...] [--near 3] [--near-npc 1]` on every port, whatever its source.
   It reports steps that sit next to each other in a section (with only notes between them) but are not in one
   group. Kill, loot, pickup, click, and objective steps are reported when they are within `--near` map percent of
   each other, name the same target, or one's note names the other's target; accepts, turn-ins, and talks when they
   name the same NPC or the NPCs stand within `--near-npc`, unless the second hands in what the first accepted. The two kinds are never paired with each other, and
   steps no one character sees both of (the Horde and Alliance halves of a visit) are left out. It caught "Badwind"
   Bennic ported as a step of its own ahead of the Highlands Bandits whose cave he is in. With no files it checks
   every guide in `Data/Guides`. Its reports are candidates too: two camps side by side can stay apart.

4. Create small fixtures representing each converted construct, plus one end-to-end RestedXP-derived and one
   Zygor-derived authorized starter guide. Test selection, eligibility, routes/POIs, objective groups, manual controls,
   progress migration, reload/resume, and clone/edit parity.
5. Perform in-client smoke tests on the current Forever build for every release pack. Record build number, enabled
   APIs, fallbacks exercised, performance/memory measurements, and all unsupported features in
   `docs/api-compatibility.md` and the pack release checklist.
6. Release a pack only when permission/provenance, zero unresolved blockers, content review, automated validation,
   clean-client test, upgraded-progress test, and attribution review are signed off. Publish source version, NuuRoad
   pack version, scope, known manual fallbacks, and removal contact in release notes.

## Delivery order

1. Permission/provenance gate, source inventory, selection manifest, and one parser fixture per dialect.
2. IR, safe parsing, conversion reports, deterministic IDs, and schema/pack/provenance foundations.
3. Implement the missing reader/editor/progress/navigation features required by the first two authorized starter
   guides; ship only their supporting fixtures first.
4. Convert and review the two starter guides, then run their clean-client and migration tests.
5. Expand to complete authorized Forever leveling routes, then professions/attunements/dungeons/dailies and other
   categories one complete, tested pack at a time.
6. Maintain source snapshot diffs, conversion reports, and compatibility tests for every upstream/content update.

## Done criteria

The porting system is complete for a pack when all selected source guides are authorized and inventoried; every source
construct has a tested mapping or recorded exclusion; generated native tables validate and load without runtime source
dependencies; all references and conditions are verified for Forever or visibly manual; reader, tracker, navigation,
progress, Browser, and Creator Mode support the shipped data; provenance/attribution is intact; and automated plus
in-client tests pass for fresh, resumed, and revised-guide playthroughs.
