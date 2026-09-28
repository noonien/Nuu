# AGENTS.md

This repository holds the Nuu addons for WoW: Forever (the `_classic_beta_` client, `## Interface: 16001`):

| Addon | Purpose |
| --- | --- |
| `NuuKit` | Shared library. Development copy only; each release embeds its own copy of the kit files. |
| `NuuRoad` | Offline, player-directed guides. |
| `NuuProfessions` | Profession levelling planner. |

`link-addons.bat` junctions each addon folder into `../AddOns` so the client loads them from here.

## Ongoing work: splitting OpenRoad

We are splitting the monolithic OpenRoad addon (`../AddOns/OpenRoad`) into the Nuu addons above: guide reading,
authoring, and travel go to `NuuRoad`, the profession planner and crafting pieces go to `NuuProfessions`, and code
both need goes to `NuuKit`.

Until the split is complete, **always take inspiration from OpenRoad** before writing anything here:

- Before implementing a feature, module, or UI panel, find its counterpart in OpenRoad (`Domain/`, `UI/`, `API/`,
  `Data/`) and port or adapt it rather than designing it from scratch. Keep its behavior unless there is a reason to
  change it, and say why when you do.
- Read OpenRoad's `CLAUDE.md`, `PLAN.md`, `PROF_PLAN.md`, `GUIDE_PORTING_PLAN.md`, `TRAVEL.md`, and `docs/` for
  intent, hard constraints (player-directed, offline first, GUI-only, declarative guide data, ASCII only,
  beta-resilient APIs), and recorded API compatibility results. Those constraints apply to the Nuu addons too.
- Treat OpenRoad as read-only reference. Do not edit it as part of the split, and do not make the Nuu addons load,
  depend on, or read from it at runtime.
- Ignore `../AddOns/OpenRoad - Copy` and `OpenRoad.zip`; `../AddOns/OpenRoad` is the source of truth.

Once everything has moved over and OpenRoad is retired, remove this section.

## Conventions

- Each addon's one intentional global is its `ns` table (`_G.NuuRoad`, `_G.NuuProfessions`). Kit code reaches the
  addons as `ns.Kit`, which development builds fill through `ns.Kit = ns.Kit or _G.NuuKit`.
- `NuuKit/NuuKit.lua` is development-only, publishes `_G.NuuKit`, is never shipped, and must stay last in the TOC.
- `NuuRoad` and `NuuProfessions` are optional dependencies of each other; neither may require the other to load.

## UI kit

- The kit's UI (widgets, themes, window chrome) follows `docs/ui-kit/PLAN.md`; the mockups are linked from
  `docs/ui-kit/README.md`. The kit ships reusable parts only; each addon builds its own windows from them.
- Captions and labels are sentence case, never all capitals.
- Where the kit stands and what to do next: `NuuKit/UI/status.md`. Client results go in `docs/api-compatibility.md`.
- Tests: from `NuuKit/`, `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"`. `NuuKit.lua`, `Dev/`, `Tests/`
  and `Tools/` are never shipped.
