# Guide port pipeline

Developer tooling for porting authorized guide content into NuuRoad's guide
format v1 (`docs/examples/guide-v1.lua`). None of it is in `NuuRoad.toc`, none of it ships, and the addon
never reads a source addon's directory at runtime.

## Running it

Needs a standalone Lua 5.1, the same one the tests use. From the addon root:

```
nix-shell -p lua5_1 --run 'lua Tools/GuidePort/Audit.lua "<path to a source guide>.lua"'
```

For the RestedXP Mulgore source on this machine:

```
nix-shell -p lua5_1 --run 'lua Tools/GuidePort/Audit.lua \
  "/mnt/d/BNet/World of Warcraft/_classic_beta_/Interface/AddOns/RXPGuides/Guides/Forever/Horde-1-12_Mulgore.lua"'
```

No network, no game client, no dependency beyond the interpreter. The source
root is whatever path you pass; nothing is configured globally, so a machine
without the source addon installed simply cannot run the audit, and the test
suite skips the gate there rather than failing.

## The pieces

| File | What it does |
| --- | --- |
| `RestedXP.lua` | Reads the RestedXP guide DSL as text. Finds `RegisterGuide([[ ... ]])` by scanning and matches every line with patterns. Nothing is `loadstring`'d or executed, and no WoW API is called, so a malformed or hostile source can only produce a parse error. Every step and command keeps its source line. |
| `Mapping.lua` | The versioned mapping table: what each source construct becomes. This file is the definition of "fully ported". |
| `Audit.lua` | Prints coverage for one or more sources: every construct, how often it appears, what it becomes, and what is still missing. |

## What the statuses mean

- **mapped** - the format can hold it today.
- **todo** - it belongs in a full port and the schema cannot express it yet.
  Every `todo` carries a note saying what is needed.
- **instruction** - the source performs an action for the player. NuuRoad
  ports the words and leaves the doing to them, per the player-directed
  constraint in `CLAUDE.md`. A deliberate difference, not a gap.
- **excluded** - deliberately left out, with the reason recorded.
- **meta** - guide-level bookkeeping rather than a step.

A port is complete for a source when the audit shows nothing left as `todo`.

## The gate

`Tests/GuidePortTests.lua` fails when a source uses a construct that has no
entry in `Mapping.lua`. That is what keeps "is this fully ported?" a question
with an answer: a new construct appearing upstream breaks the build instead of
being silently dropped, which is exactly how `.link` was found. The same suite
asserts the reader never executes its input and that every unported construct
records why.
