# NuuExperiments

Development only, never built or shipped. It tries client APIs (and anything else addon work needs to see in the
real client) and keeps what it saw in `NuuExperimentsDB`. The experiments do not use NuuKit, so they see the client as it is; only the results window is the kit's (its
copy window, from the development kit).

## Running

- New experiments run on their own a couple of seconds after login, once per client build (`auto = "build"`), out of
  combat. `/nuux run <id>` (or `all`) runs one now, and when it is done shows its results in a window, selected,
  to copy with Ctrl-C and paste; `/nuux show <id|all>` shows the last results again. Without NuuKit loaded, chat
  says to use `Results.py` instead.
- The game writes the results on `/reload` or logout, to
  `WTF/Account/<account>/SavedVariables/NuuExperiments.lua`. Read them with
  `python3 NuuExperiments/Tools/Results.py [id ...]`.
- `/nuux` lists the loaded experiments and how each last went;
  `/nuux clear <id|all>` and `/nuux prune` (results of experiments no longer loaded) forget them.

Each result: `status` (`ok`, `error`, `timeout`, `running` if the client reloaded first), `build`, `interface`,
`date`, `character`, `inCombat`, `ms`, `values`, and `log` and `errors` when there are any.

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
a timed line, `t:After(seconds, fn)` runs later. Every error, in `run` or a callback, lands in `errors` with its
stack; the run goes on.

## Retiring one

Once its results are in and written up (client results go in `docs/api-compatibility.md` with the build and date),
take its line out of `NuuExperiments.toc` and move the file to `Experiments/Retired/`, where it stays to be put back
if a new build needs it checked again. A file not in the TOC never loads, so it never runs. Its last results stay
in the saved variables until `/nuux prune`.

Tests: from `NuuExperiments/`, `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"`.
