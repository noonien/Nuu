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
- Development-only code stays out of releases. Files go in the addon's `Dev/` folder, listed in its TOC between
  `#@debug@` and `#@end-debug@`; lines inside shipped `.lua` files go between `--@debug@` and `--@end-debug@`.

## Releases

`python3 Tools/Build.py [--version X] [Addon ...]` writes each addon to `dist/<Addon>/` (and a zip and changelog)
with its own copy of the kit under `Libs/NuuKit/` and no development code: only the files its TOC lists outside the
debug blocks, `Bindings.xml`, the `Art/` it names, and the kit's shipped files and `Media/`. It stops on a missing
or non-ASCII file or a dev file in the output, then loads the built addons on the kit's stand-in for the client,
alone and together (`Tools/BuildTests.lua`; Lua from PATH or nix-shell). `--tag` tags `<Addon>-v<version>`.
- `NuuRoad` and `NuuProfessions` are optional dependencies of each other; neither may require the other to load.

## UI kit

- The kit's UI (widgets, themes, window chrome) follows `docs/ui-kit/PLAN.md`; the mockups are linked from
  `docs/ui-kit/README.md`. The kit ships reusable parts; each addon builds its own windows from them, except the diagnostics,
  session log and bug report windows, which are the kit's (`NuuKit/UI/Screens/`) and take the addon's parts in
  their specs.
- Captions and labels are sentence case, never all capitals.
- Where the kit stands and what to do next: `NuuKit/UI/status.md`. How widgets are written (and the costs a change
  must keep): `NuuKit/UI/README.md`. Client results go in `docs/api-compatibility.md`; `/nuukit report` measures the
  kit in the client.
- Tests: from `NuuKit/`, `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"`. `NuuKit.lua`, `Dev/`, `Tests/`
  and `Tools/` are never shipped. NuuProfessions and NuuRoad have their own runners, the same command from
  `NuuProfessions/` or `NuuRoad/`; they load the kit from `../NuuKit` and end with their windows on the kit's
  stand-in for the client (NuuRoad: `Tests/UI/Harness.lua` loads the whole addon once for its UI suites; one suite
  alone is `lua Tests/TestRunner.lua '<suite name>'`).
