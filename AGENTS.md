# AGENTS.md

This repository holds the Nuu addons for WoW: Forever (the `_classic_beta_` client, `## Interface: 16001`):

| Addon | Purpose |
| --- | --- |
| `NuuKit` | Shared library. Development copy only; each release embeds its own copy of the kit files. |
| `NuuRoad` | Offline, player-directed guides. |
| `NuuProfessions` | Profession levelling planner. |
| `NuuGear` | Gear upgrades scored against stat weights for the character's spec (`NuuGear/status.md`). |
| `NuuExperiments` | Development only, never built: tries client APIs in game and keeps the results in its saved variables (`NuuExperiments/README.md`). |

`link-addons.bat` junctions each addon folder into `../AddOns` so the client loads them from here.

## Constraints

Every Nuu addon is player-directed, offline first and GUI-only, keeps guide data declarative, is ASCII only, and
uses beta-resilient APIs (feature-detected and guarded; results in `docs/api-compatibility.md`).

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

## Experiments

To learn how the client behaves, write an experiment instead of guessing: one file in `NuuExperiments/Experiments/`
that calls `ns:Experiment({ id, title, run = function(t) ... end })` and is listed in the TOC (template and the `t`
helpers in `NuuExperiments/README.md`). It runs at login once per client build, or with `/nuux run <id>`, and keeps
its results in `NuuExperimentsDB.results[id]`. `/nuux run <id>` and `/nuux show <id>` show them in the kit's copy
window, for the player to paste; after a `/reload`, `python3 NuuExperiments/Tools/Results.py [id]` prints them. Once
the results are written up in `docs/api-compatibility.md`, retire the experiment: take its line out of the TOC and
move the file to `Experiments/Retired/`. Experiments do not use NuuKit (only that window does) and NuuExperiments is
never built.

## UI kit

- The kit's UI (widgets, themes, window chrome) follows `docs/ui-kit/PLAN.md`; the mockups are linked from
  `docs/ui-kit/README.md`. The kit ships reusable parts; each addon builds its own windows from them, except the diagnostics,
  session log, bug report and copy windows, which are the kit's (`NuuKit/UI/Screens/`) and take the addon's parts in
  their specs.
- Captions and labels are sentence case, never all capitals.
- Where the kit stands and what to do next: `NuuKit/UI/status.md`. How widgets are written (and the costs a change
  must keep): `NuuKit/UI/README.md`. Client results go in `docs/api-compatibility.md`; `/nuukit report` measures the
  kit in the client.
- Tests: from `NuuKit/`, `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"`. `NuuKit.lua`, `Dev/`, `Tests/`
  and `Tools/` are never shipped. NuuProfessions, NuuRoad and NuuGear have their own runners, the same command from
  `NuuProfessions/`, `NuuRoad/` or `NuuGear/`; they load the kit from `../NuuKit` and end with their windows on the kit's
  stand-in for the client (NuuRoad: `Tests/UI/Harness.lua` loads the whole addon once for its UI suites; one suite
  alone is `lua Tests/TestRunner.lua '<suite name>'`).
