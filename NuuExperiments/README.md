# NuuExperiments

Development only, never built or shipped. It tries client APIs (and anything else addon work needs to see in the
real client) and keeps what it saw in `NuuExperimentsDB`. The experiments do not use NuuKit, so they see the client as it is; only the windows are the kit's (the experiments
window and the copy window, from the development kit).

## Running

- `/nuux` opens the experiments window: each loaded experiment with how it last went (then the results of retired
  ones), and the chosen one's results, with Run, Copy (the copy window) and Clear; Run all and Prune in the title
  band. It follows runs as they start and end. Without NuuKit loaded, `/nuux` lists them in chat instead.
- New experiments run on their own a couple of seconds after login, once per client build (`auto = "build"`), out of
  combat. `/nuux run <id>` (or `all`) runs one now, and when it is done shows its results in a window, selected,
  to copy with Ctrl-C and paste; `/nuux show <id|all>` shows the last results again. Without NuuKit loaded, chat
  says to use `Results.py` instead.
- The game writes the results on `/reload` or logout, to
  `WTF/Account/<account>/SavedVariables/NuuExperiments.lua`. Read them with
  `python3 NuuExperiments/Tools/Results.py [id ...]`.
- `/nuux list` lists the loaded experiments and how each last went, in chat;
  `/nuux clear <id|all>` and `/nuux prune` (results and data of experiments no longer loaded) forget them.
- `/nuux stop <id>` (or Stop in the window) ends a run still going, such as a scan or the recorder.

Each result: `status`, `build`, `interface`, `date`, `character`, `inCombat`, `ms`, `values`, and `log` and `errors`
when there are any. The status is `ok`, `error`, `timeout` or `stopped` once a run ends; `running` while it waits;
`watching` for one listening all session; `interrupted` if the client reloaded or logged out first. An interrupted
once-per-build experiment runs again at the next login; a manual one, such as `quest-scan`, waits for Run and
carries on where it stopped.

## Writing one

One file per experiment in `Experiments/`, listed in the TOC:

```lua
local _, ns = ...

ns:Experiment({
    id = "item-info",            -- its key in NuuExperimentsDB.results
    title = "Item info on a cold cache",
    auto = "build",              -- "build" (default), "login" (every login), false (only /nuux run)
    combat = false,              -- true lets it run in combat
    run = function(t)
        t:Exists({ "C_Item.GetItemInfo", "GetItemInfo" })   -- values.globals[name] = its type or "nil"
        t:Try("cold", C_Item.GetItemInfo, 6948)            -- values.cold = { ok, returns = {n, ...} } or { ok = false, error }
        t:Wait(10)                                          -- goes on after run(); "timeout" if t:Done() never comes
        t:On("GET_ITEM_INFO_RECEIVED", function(event, itemID, success)
            if itemID ~= 6948 then return end
            t:Set("event", { itemID = itemID, success = success })
            t:Try("warm", C_Item.GetItemInfo, 6948)
            t:Done()
            return true                                     -- stop listening
        end)
    end,
})
```

`t:Set(key, value)` keeps any value (functions, frames and the like as text, tables copied), `t:Log(fmt, ...)` adds
a timed line, `t:After(seconds, fn)` runs later. An experiment known to take longer than three seconds says how far it
has got with `t:Progress(done, total, label)` ("120 of 6605 quests answered"), shown as a bar in the window while it
runs; one still running after three seconds without it gets a line in its log saying so. A run kept open with
`t:Keep()` has no end to count towards and calls none. Every error, in `run` or a callback, lands in `errors` with its
stack; the run goes on.

An experiment that collects data in bulk keeps it in `t:Data()`, a plain table under `NuuExperimentsDB.data[id]`:
not copied or cut at 200 entries like `t:Set`, and kept across runs (Clear forgets only the results), so the next
run carries on. Only strings, numbers, booleans and tables of them belong in it. `t:Keep()` keeps the run open all
session, listening, with no timeout.

## Quest data

Two experiments map quests the way ForeverGuide's scanner and recorder do, for `db/tools/build_horde.py`. They
collect data rather than test the client, so they stay loaded and are never retired.

- `quest-scan`, only by hand (`/nuux run quest-scan`, about ten minutes): asks the server about every quest ID in
  the client's quest table (`Experiments/QuestScanIDs.lua`, made by `python3 NuuExperiments/Tools/QuestIDs.py` from
  `db/sources/wago/forever/QuestV2.csv`) and keeps each one's title, level and objectives (type, text, count), and
  the IDs the server says it does not have. It slows down when answers come late; IDs never answered are asked
  again by the next run, which skips everything already answered on this build. A new build starts it over.
- `quest-record` (paused: its line in the TOC is commented out, so it does not load), at every login, listening all
  session: who offers each quest (quest window, gossip; NPC or
  object, or the item that starts it) and who takes it in, the XP and money at turn-in with the player's level,
  where each objective went up and which mob was targeted when it did, and the name, level and position of every
  NPC talked to. Its data is kept across logins and builds.

After a `/reload`, `python3 NuuExperiments/Tools/QuestExport.py` merges both, from every account's saved variables,
into `db/ingame/` (`quests.json`, `npcs.json`, `objects.json`), and `python3 db/tools/build_horde.py` uses them before
every other source: names, levels, counts, givers, turn-ins, NPC positions and XP, and Questie quests the server
does not have are left out.

XP is worked out the way the client does it: from each quest's level, XP difficulty and XP multiplier, which the
server sends and the client keeps in its quest cache (`Cache/WDB/<locale>/questcache.wdb`), with the client's
`QuestXP` table and rounding (the formula is in `docs/api-compatibility.md`, "Quest XP"). It is exact, and the
export checks it against the scan and against every turn-in `quest-record` saw, printing what does not match. The
cache keeps what the server said when a quest was first loaded, (as far as we know, unchecked) until the build changes, so after a server change
(dungeon quest XP was cut): close the game, delete `questcache.wdb`, log in, `/nuux run quest-scan` (a run after a
finished scan starts over), and close the game again so it writes the cache; then export. A turn-in that paid
something else wins over the cache. `db/horde/REPORT.md` lists the XP that differs from Questie's.

The cache holds more of what the server says about each quest, and the export takes it too: minimum level, the zone
or the class (or profession) a quest is filed under, its type (dungeon, elite), the quest offered straight after it,
the item it gives on accepting, its flags, and the races that may take it, as Forever has them (the Skyborne; Troll
druids). It never holds classes, prerequisites or breadcrumbs.

`build_horde.py` gives every quest a `prereqs`: `all` (each of these first), `anyOf` (one of these first),
`breadcrumbs` (optional quests that send you here) and `maybe` (the server offers this quest straight after a quest
with no objectives, which could be either), with `src`. Questie gives Classic's chains; the server's next-quest links
confirm them and add Forever's (a link from a quest with objectives is a prerequisite; no Classic breadcrumb but one
has objectives); ForeverGuide's lists fill in the rest. Prerequisites the server does not have are left out.

## Retiring one

Once its results are in and written up (client results go in `docs/api-compatibility.md` with the build and date),
take its line out of `NuuExperiments.toc` and move the file to `Experiments/Retired/`, where it stays to be put back
if a new build needs it checked again. A file not in the TOC never loads, so it never runs. Its last results stay
in the saved variables until `/nuux prune`.

Tests: from `NuuExperiments/`, `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"`.
