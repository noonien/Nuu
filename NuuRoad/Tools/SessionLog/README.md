# Session log

The session log (`ns.recorder`, the kit's recorder: `NuuKit/Core/Recorder.lua`)
keeps a log of recent sessions in the saved variables (`NuuRoadDB.log`), and the
tools here read it straight out of the saved file, outside the game. The
profession planner's own tools (replaying, playing through and fuzzing a plan)
went with it to `NuuProfessions/Tools/SessionLog`.

## Reading it

```
python3 Tools/SessionLog/sessions.py                 every session as one timeline
python3 Tools/SessionLog/sessions.py --quest 97253   only rows about one quest (--npc, --event, --since too)
python3 Tools/SessionLog/sessions.py --unguided      quests met in play that no packaged guide names
```

```
python3 Tools/SessionLog/sessions.py --channel travel   the travel planner's own log: plans, legs, dock, taxi, API probe
python3 Tools/SessionLog/sessions.py --channel discover   what a guide step left out that the game showed: a quest
                                                         giver or turn-in with no NPC, another NPC, or no spot, with
                                                         the authored form to paste (Domain/GuideCorrections.lua)
python3 Tools/SessionLog/sessions.py --bugs          every open bug report filed in the game (Menu -> Report a bug), in full;
                                                         fixed ones are listed in fixed-bugs.md and left out (--all shows them)
python3 Tools/SessionLog/sessions.py --steps         the step viewer's history (below): every pointer move, and every
                                                         change in what the flow saw at the current step, as a diff
python3 Tools/SessionLog/sessions.py --steps --step 39   only the rows about guide step 39 (on it, moved from or to it,
                                                         in its group, or carried)
python3 Tools/SessionLog/sessions.py --trace         the latest trace session (below), every channel merged by time
python3 Tools/SessionLog/sessions.py --trace 2 --channel travel   the session before it, one channel's rows only
python3 Tools/SessionLog/sessions.py --list-traces   the trace sessions kept: when each began, who, rows per channel
python3 Tools/SessionLog/doors.py                    candidate doorways and flight masters for Data/Travel.lua
python3 Tools/SessionLog/places.py                   place recorder walks, as Lua files for Tools/ProcessPlace.lua
```

`sessions.py` reads the log out of every account's saved
`WTF/Account/*/SavedVariables/NuuRoad.lua` (or the one `--saved` names), splits
it into sessions, and says each row in one line with quest, NPC and item names
filled in. `--full` prints every field, quest text included; `--jsonl` prints
the rows themselves, each tagged with its session. It only reads, and the saved
file is parsed (`lua_table.py`), never run: it is a tokenizer for the small
subset the client writes, not an interpreter.

The client writes the file at logout and `/reload`, so the log is as fresh as
the last of those.

`places.py` writes to `Tools/SessionLog/places/` (gitignored) and leaves a file
that is already there alone, so a walk keeps its file after the log has dropped
it for age.

## Logging, from inside the game

One call, from any file:

```lua
ns:Record("rec", { event = "accept", quest = 3091, npc = 3143 })
ns:Record("ui", "the browser was opened from the tracker")
ns:RecordHere("mark", { npc = 3143 })   -- the same, plus map and position
```

A channel says which part of the addon spoke. `session` is logging in,
reloading and logging out; `rec` is what the player did, as material for
writing a guide; `guide` is the guide being followed; `ui` is windows and
clicks. Anything else is named after whatever is being worked on and lives as
long as the work does - `poi` while the client's own quest POIs were being
measured, `mark` while target marking was. A channel does not have to be
declared and there is no list to add it to: recording to a name creates it.

Only `session` is written today - arriving, leaving, and who was playing. The
rest are names waiting for the work that fills them.

The data is whatever the caller has - a table, a string, a number, nested as
deep as it likes - and it is copied through a guard first: cycles, secret
values, functions and frames would each cost the whole session at the moment
the client writes it, so each becomes a short word (`<cycle>`, `<secret>`,
`<function>`) and the rest of the record survives.

Nothing is capped, and nothing is dropped but by age: records older than the
days set under OPTIONS -> RECORDING (10 unless changed) go at every login, or
at once with CLEAN UP there. That includes bug reports, so read them before
they age out.

## The step viewer's history

The `guide` channel holds two kinds of row. `event = "step"` is a move of the
step pointer (`Domain/Progress.lua`): how (observed, skipped, forward, back,
goto), from, to. `event = "state"` is a snapshot of what the flow saw at the
step the player was on (`Domain/StepState.lua`), written whenever it differs
from the last one - checked at every event and poll the flow looks at, so no
state is lost and a quiet minute writes nothing. A snapshot carries:

- the step, its title and kind, its recorded status, and whether it is held;
- `only` as text and `open`: how the flow reads it (open, waiting, bypassed,
  ruledOut);
- `completion`, `observed` (what the game says of it now), `scanDone` and
  `settled` (what the load scan says), and `goals`, the card's goal lines with
  the client's status and count;
- `auto`: what the flow will do on its next look (held, complete, bypassed,
  passed, waiting, moot, manual, incomplete), and `stall` when the step reads
  done and yet will not advance;
- `group`: the authored group around the step, member by member, with why the
  card shows each or leaves it out (current, before, shown, done, moot,
  unavailable and the condition);
- `carried`, the steps carried alongside it; `ahead`, the next steps the flow
  would stop on, and `passed`, the ones it would pass over on the way;
- `cause`, what made the flow look (an event name, `poll`, `arrival`, `npc`,
  `login`, and `after back` or the like following a button), and `moves`, the
  moves that look made and why ("observed", "bypassed: now item 247841",
  "passed: #44 is done").

A bug report quotes the current snapshot ("Step state") and the last rows of
the channel ("Step history").

## The trace: session-only logging

Beside the log there is the trace (`NuuRoadDB.trace`), for rows only worth
keeping while a bug is fresh - whole inputs and results, every change:

```lua
if ns:Tracing() then   -- skip building a big row when nothing would keep it
    ns:Trace("travel", { event = "plan", reason = reason, inputs = inputs, route = route })
end
```

Same channel names, same data, same guard as `ns:Record`, but kept by session
instead of by age: each login or `/reload` opens a new trace session and only
the last three are kept, so an accidental reload does not lose the session
before it. A trace session carries a short identity (character, realm, level,
client and build, addon, login or reload). A channel is not capped, but one
that runs past 5000 rows in a session drops its oldest a tenth at a time and
counts them under the session's `dropped`.

Use `ns:Record` for what should still explain something next week; use
`ns:Trace` for debugging one part. `--trace` prints one row a line - the time,
the channel, then the data as compact JSON (`--full` indents it), so it pipes
into grep and jq; `--channel` and `--event` filter it.

Nothing in NuuRoad traces today; the channel names are free for whichever part is being debugged.

Data is named the way a guide names it - `map`, `at = { x, y }`, `quest`, `npc`
- so a row reads like the thing it describes, and a coordinate lifted out of a
log lands in a guide as it stands.

The session block is written once at login, first of all, as a record on the
`session` channel. It opens the session: the tools split the log there and name
the session from its clock (`20260925-011245`). It holds the player
(`character`, `realm`, `guid`, `faction`, `race`, `class`, `level`, `xp`,
`xpMax`) and the client (`client`, `build`, `buildDate`, `toc`, `locale`,
`addon`).

A record is two fields: `at`, when it happened, seconds since the epoch as the
game read its own clock, and `d`, what the caller had. The tools read it as a
row of three - `t`, `c` for the channel, and `d` - sorted by `t`, so channels
interleave in the order things happened.
