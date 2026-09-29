#!/usr/bin/env python3
"""Read the session log as one timeline.

    python3 Tools/SessionLog/sessions.py                 every session, one line a row
    python3 Tools/SessionLog/sessions.py --quest 97253   only rows about that quest
    python3 Tools/SessionLog/sessions.py --npc 7161      only rows about that NPC
    python3 Tools/SessionLog/sessions.py --event accept  only that kind of row (repeatable)
    python3 Tools/SessionLog/sessions.py --since 20260922-2300
    python3 Tools/SessionLog/sessions.py --unguided      quests seen in play that no packaged guide names
    python3 Tools/SessionLog/sessions.py --bugs          bug reports not yet listed in fixed-bugs.md
    python3 Tools/SessionLog/sessions.py --steps         what the step viewer showed, each change as a diff
    python3 Tools/SessionLog/sessions.py --steps --step 39   only the rows about guide step 39
    python3 Tools/SessionLog/sessions.py --quest 97253 --full   every field, quest text and all
    python3 Tools/SessionLog/sessions.py --jsonl         the rows themselves, concatenated
    python3 Tools/SessionLog/sessions.py --trace         the latest trace session, every channel by time
    python3 Tools/SessionLog/sessions.py --trace 2 --channel travel   the one before, one channel
    python3 Tools/SessionLog/sessions.py --list-traces   the trace sessions kept

The log is `NuuRoadDB.log` in the game's saved variables
(WTF/Account/*/SavedVariables/NuuRoad.lua, or --saved), which keeps the last
days of sessions (the kit's recorder). This splits it into sessions, reads them
in time order, marks where each session begins, and says each row in one line:
when, where, and what happened, with quest and NPC names from the rows
themselves, the questlog snapshots, and Data/Names.lua.

`--unguided` is for a client that has moved on from the guides: every quest the
player accepted, turned in, or carried in the log that none of the packaged
guides in Data/BuiltIn/ mentions, with what the sessions know about it - who
gave it, where, what it asked for, and every objective and loot row after.

`--steps` reads the `guide` channel (Domain/StepState.lua, Domain/Progress.lua):
every move of the step pointer, and every change in what the flow saw at the
step the player was on - its condition read every way, how the game reported
it done, its group member by member, what was carried with it, where the flow
would stop next, and `STALLED` when the step read done and did not advance.
The first state of a session is printed whole; each after it prints only the
fields that changed. `--full` prints every state whole.

`--trace` reads the other log, `NuuRoadDB.trace`: the session-scoped trace
(`ns:Trace`), of which the game keeps only the last three logins or reloads.
Each row is one line - when, the channel, and the data as compact JSON - so it
reads with grep and jq; `--channel` and `--event` filter it as they filter the
lasting log, and `--full` indents each row's JSON instead.

It only reads. Nothing here writes to the saved file or the addon, and the
saved file is parsed (lua_table.py), never run.
"""

import argparse
import datetime
import glob
import json
import os
import re
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lua_table import parse_saved_variables, to_json_safe, LuaParseError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WOW_ROOT = os.path.abspath(os.path.join(ADDON_ROOT, "..", "..", ".."))
SAVED = os.path.join(WOW_ROOT, "WTF", "Account", "*", "SavedVariables", "NuuRoad.lua")
# Set by --saved: read this file instead of every account's.
saved_files = None
NAMES = os.path.join(ADDON_ROOT, "Data", "Names.lua")
BUILT_IN = os.path.join(ADDON_ROOT, "Data", "BuiltIn")
FIXED_BUGS = os.path.join(HERE, "fixed-bugs.md")


def named(t):
    """A session's name: when it began, to the second."""
    return datetime.datetime.fromtimestamp(t).strftime("%Y%m%d-%H%M%S")


def opens(row):
    """True for the identity row a session starts with."""
    d = row.get("d")
    return row.get("c") == "session" and isinstance(d, dict) and d.get("event") is None


def load_rows(path):
    """Every record in one saved file as {"t", "c", "d"}, oldest first."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        data = to_json_safe(parse_saved_variables(handle.read()))
    channels = ((data.get("NuuRoadDB") or {}).get("log") or {}).get("channels") or {}
    rows = []
    for channel, records in channels.items():
        if not isinstance(records, list):
            continue
        for order, record in enumerate(records):
            if isinstance(record, dict):
                rows.append((order, {"t": record.get("at"), "c": channel, "d": record.get("d")}))
    # The session's identity row opens it, so within one second it goes first.
    rows.sort(key=lambda pair: (pair[1]["t"] or 0, not opens(pair[1]), pair[1]["c"], pair[0]))
    return [row for _, row in rows]


def load_sessions(since=None):
    """(name, rows) for every session in the saved log, oldest first. A session
    is named for when it began: the clock on its identity row."""
    out = []
    for path in saved_files or sorted(glob.glob(SAVED)):
        try:
            rows = load_rows(path)
        except (OSError, LuaParseError) as error:
            print("skipped %s: %s" % (path, error), file=sys.stderr)
            continue
        current = None
        for row in rows:
            stamped = isinstance(row.get("t"), (int, float))
            if current is None or (opens(row) and stamped):
                current = (named(row["t"]) if stamped else "unknown", [])
                out.append(current)
            current[1].append(row)
    out.sort(key=lambda session: session[0])
    return [session for session in out if not since or session[0] >= since]


def load_traces():
    """Every trace session in the saved files, oldest first, as dicts with
    `at`, `identity`, `channels` and `dropped` (NuuKit/Core/Recorder.lua)."""
    out = []
    for path in saved_files or sorted(glob.glob(SAVED)):
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                data = to_json_safe(parse_saved_variables(handle.read()))
        except (OSError, LuaParseError) as error:
            print("skipped %s: %s" % (path, error), file=sys.stderr)
            continue
        sessions = ((data.get("NuuRoadDB") or {}).get("trace") or {}).get("sessions") or []
        if isinstance(sessions, dict):
            # An empty or sparse Lua list can come back keyed by number.
            sessions = [sessions[k] for k in sorted(sessions, key=lambda k: int(k) if str(k).isdigit() else 0)]
        for session in sessions:
            if isinstance(session, dict):
                out.append(session)
    out.sort(key=lambda session: session.get("at") or 0)
    return out


def trace_records(session):
    """A trace session's rows as (t, channel, d), merged by time; within a
    second a channel keeps its own order."""
    rows = []
    channels = session.get("channels")
    if not isinstance(channels, dict):  # an empty Lua table reads either way
        channels = {}
    for channel, records in channels.items():
        if not isinstance(records, list):
            continue
        for order, record in enumerate(records):
            if isinstance(record, dict):
                rows.append((record.get("at") or 0, channel, order, record.get("d")))
    rows.sort(key=lambda row: (row[0], row[1], row[2]))
    return rows


def trace_counts(session):
    channels = session.get("channels")
    counts = {c: len(r) for c, r in channels.items() if isinstance(r, list)} if isinstance(channels, dict) else {}
    dropped = session.get("dropped")
    dropped = dropped if isinstance(dropped, dict) else {}
    return ", ".join("%s %d%s" % (c, counts[c], " (+%s dropped)" % dropped[c] if dropped.get(c) else "")
                     for c in sorted(counts)) or "nothing traced"


def trace_identity(session):
    i = session.get("identity")
    i = i if isinstance(i, dict) else {}
    kind = "reload" if i.get("reload") else ("login" if i.get("login") else "load")
    words = ["%s-%s" % (i.get("character", "?"), i.get("realm", "?"))]
    if i.get("level") is not None:
        words.append("L%s" % i["level"])
    if i.get("client") or i.get("build"):
        words.append("client %s build %s" % (i.get("client", "?"), i.get("build", "?")))
    if i.get("addon"):
        words.append("addon %s" % i["addon"])
    words.append(kind)
    return ", ".join(words)


def list_traces(traces):
    for back, session in enumerate(reversed(traces), 1):
        at = session.get("at")
        print("%d  %s  %s  | %s" % (back, named(at) if isinstance(at, (int, float)) else "unknown", trace_identity(session),
                                    trace_counts(session)))


def show_trace(traces, back, args):
    if back < 1 or back > len(traces):
        sys.exit("no trace session %d: %d kept (--list-traces lists them)" % (back, len(traces)))
    session = traces[-back]
    at = session.get("at")
    print("== trace %s  %s  | %s" % (named(at) if isinstance(at, (int, float)) else "unknown", trace_identity(session),
                                     trace_counts(session)))
    for t, channel, _, d in trace_records(session):
        if args.channel and channel not in args.channel:
            continue
        if args.event and not (isinstance(d, dict) and d.get("event") in args.event):
            continue
        if args.full:
            print("%s  %s  %s" % (when(t), channel, json.dumps(d, indent=2, sort_keys=True, ensure_ascii=True)))
        else:
            print("%s  %s  %s" % (when(t), channel, json.dumps(d, sort_keys=True, separators=(",", ":"), ensure_ascii=True)))


def load_names():
    """Data/Names.lua's npcs, quests and items, read as text rather than run."""
    names = {"npcs": {}, "quests": {}, "items": {}}
    try:
        with open(NAMES, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        return names
    section = None
    for line in text.splitlines():
        header = re.match(r"\s*(?:Names\.)?(npcs|quests|items)\s*=\s*\{", line)
        if header:
            section = header.group(1)
            continue
        entry = re.match(r'\s*\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"', line)
        if section and entry:
            names[section].setdefault(int(entry.group(1)), entry.group(2).replace('\\"', '"'))
    return names


# Every field a guide step names a quest by.
GUIDE_QUEST = re.compile(r"\b(?:accept|turnin|objectives?|starts|quest|track|untrack)\s*=\s*(\{[^{}]*\}|\d+)")
GUIDE_ONLY = re.compile(r"quest\s+(\d+)")


def guided_quests():
    """Every quest ID a packaged guide mentions."""
    found = set()
    for path in glob.glob(os.path.join(BUILT_IN, "*.lua")):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for match in GUIDE_QUEST.finditer(text):
            found.update(int(n) for n in re.findall(r"\d+", match.group(1)))
        found.update(int(n) for n in GUIDE_ONLY.findall(text))
    return found


class Book:
    """Names for IDs: what the rows say first, Names.lua after."""

    def __init__(self, sessions):
        static = load_names()
        self.quests = dict(static["quests"])
        self.npcs = dict(static["npcs"])
        self.items = dict(static["items"])
        for _, rows in sessions:
            for row in rows:
                d = row.get("d")
                if not isinstance(d, dict):
                    continue
                if d.get("quest") and d.get("title"):
                    self.quests[d["quest"]] = d["title"]
                for q in d.get("quests") or []:
                    if isinstance(q, dict) and q.get("quest") and q.get("title"):
                        self.quests[q["quest"]] = q["title"]
                if d.get("npc") and (d.get("npcName") or d.get("name")):
                    self.npcs[d["npc"]] = d.get("npcName") or d.get("name")
                if d.get("from") and d.get("fromName"):
                    self.npcs[d["from"]] = d["fromName"]
                if d.get("item") and d.get("name"):
                    self.items[d["item"]] = d["name"]

    def quest(self, qid):
        return "%s %s" % (qid, self.quests.get(qid, "?"))

    def npc(self, nid):
        return "%s %s" % (nid, self.npcs.get(nid, "?"))

    def item(self, iid):
        return "%s %s" % (iid, self.items.get(iid, "?"))


def when(t):
    return datetime.datetime.fromtimestamp(t).strftime("%m-%d %H:%M:%S") if isinstance(t, (int, float)) else "--"


def where(d):
    at = d.get("at")
    if isinstance(at, list) and len(at) >= 2:
        return "%s %5.2f,%5.2f" % (d.get("map", "?"), at[0], at[1])
    return ""


def spot(s):
    if isinstance(s, dict) and isinstance(s.get("at"), list) and len(s["at"]) >= 2:
        return "%s %.2f,%.2f" % (s.get("map", "?"), s["at"][0], s["at"][1])
    return "?"


def say_travel(d):
    """The travel planner's rows (UI/TravelRoute.lua), one line each."""
    event = d.get("event", "")
    if event == "plan":
        head = "plan (%s) -> %s" % (d.get("reason"), spot(d.get("target")))
        if d.get("why"):
            return "%s: none, %s" % (head, d["why"])
        text = "%s: %s" % (head, d.get("summary"))
        choices = d.get("choices") or []
        if len(choices) > 1:
            text += " | choices: " + "; ".join(
                "%s%s %s ~%ss" % ("*" if c.get("id") == d.get("choice") else "", c.get("id"), c.get("outline"), c.get("cost"))
                for c in choices if isinstance(c, dict))
        legs = d.get("legs")
        if isinstance(legs, list):
            text += " | legs: " + "; ".join(
                "%s %s -> %s" % (l.get("kind"), l.get("text") or "", spot(l.get("to"))) for l in legs if isinstance(l, dict))
        return text
    if event == "arrow":
        text = "ARROW %s" % d.get("state")
        if d.get("leg"):
            text += " '%s'" % d["leg"]
        if d.get("towards") and d.get("towards") != "none":
            text += " -> %s %s" % (d["towards"], spot(d.get("spot")))
        if d.get("yards") is not None:
            text += " %s yd" % d["yards"]
        if d.get("clickable") is not None:
            text += " clickable" if d["clickable"] else " not clickable"
        if d.get("note"):
            text += " !! " + d["note"]
        return text
    if event == "test":
        text = "TEST %s/%s %s" % (d.get("test", ""), d.get("step", ""), str(d.get("result", "")).upper())
        if d.get("auto") and d.get("auto") != "none":
            text += " (auto %s)" % d["auto"]
        if d.get("note"):
            text += " -- " + d["note"]
        if d.get("result") in ("pass", "fail", "flag", "skip"):
            text += " | route: %s | arrow: %s" % (d.get("route") or d.get("why"), d.get("leg") or "at target")
        return text
    rest = {k: v for k, v in d.items() if k not in ("event", "map", "at")}
    return "%s %s" % (event, json.dumps(rest, sort_keys=True))


def say(row, book):
    """One line for one row."""
    d = row.get("d")
    if not isinstance(d, dict):
        return "%-7s %s" % (row.get("c"), json.dumps(d))
    if row.get("c") == "travel":
        return "travel " + say_travel(d)
    if row.get("c") == "bug":
        return "BUG %s/%s %s step %s (on %s): %s" % (d.get("kind"), d.get("category"), d.get("guide"), d.get("step"),
                                                   d.get("current"), (d.get("description") or "").replace("\n", " "))
    event = d.get("event", "")
    q = d.get("quest")
    if row.get("c") == "discover":
        return "DISCOVER %s step %s %s %s: missing %s -- game says %s @ map %s %s, %s (%s); authored form: %s" % (
            d.get("guide"), d.get("step"), d.get("role"), book.quest(q), d.get("missing"),
            book.npc(d["npc"]) if d.get("npc") else "no NPC", d.get("map"), d.get("x"), d.get("y"),
            d.get("npcName") or "-", d.get("authored"))
    if row.get("c") == "session" and not event:
        return "session  %s L%s %s %s, client %s build %s" % (
            d.get("character"), d.get("level"), d.get("race"), d.get("class"), d.get("client"), d.get("build"))
    if event == "questlog":
        quests = [x for x in d.get("quests") or [] if isinstance(x, dict)]
        return "questlog %d: %s" % (len(quests), "; ".join(book.quest(x.get("quest")) for x in quests))
    if event in ("accept", "turnin", "abandon"):
        text = "%s %s" % (event, book.quest(q))
        if d.get("npc"):
            text += " @ " + book.npc(d["npc"])
        if d.get("objectiveText"):
            text += " -- " + d["objectiveText"].replace("\n", " ")
        return text
    if event == "objective":
        return "objective %s part %s: %s (%s)" % (book.quest(q), d.get("part"), d.get("text"), d.get("type"))
    if event == "loot":
        text = "loot %s x%s" % (book.item(d.get("item")), d.get("count", 1))
        if d.get("from"):
            text += " from %s %s" % (d.get("fromKind", ""), book.npc(d["from"]))
        if q:
            text += " for " + book.quest(q)
        return text
    if event == "talk":
        return "talk %s %s" % (d.get("kind"), book.npc(d.get("npc")))
    rest = {k: v for k, v in d.items() if k not in ("event", "map", "at")}
    return "%s %s" % (event or row.get("c"), json.dumps(rest, sort_keys=True))


def mentions(row, quest=None, npc=None):
    d = row.get("d")
    if not isinstance(d, dict):
        return False
    if quest is not None:
        if d.get("quest") == quest:
            return True
        return any(isinstance(x, dict) and x.get("quest") == quest for x in d.get("quests") or [])
    if npc is not None:
        return npc in (d.get("npc"), d.get("from"))
    return True


def timeline(sessions, book, args):
    for name, rows in sessions:
        picked = []
        for row in rows:
            d = row.get("d") if isinstance(row.get("d"), dict) else {}
            if args.channel and row.get("c") not in args.channel:
                continue
            if args.event and d.get("event") not in args.event:
                continue
            if args.quest is not None and not mentions(row, quest=args.quest):
                continue
            if args.npc is not None and not mentions(row, npc=args.npc):
                continue
            picked.append(row)
        if not picked:
            continue
        if args.jsonl:
            for row in picked:
                print(json.dumps(dict(row, s=name), sort_keys=True))
            continue
        print("== %s" % name)
        for row in picked:
            d = row.get("d") if isinstance(row.get("d"), dict) else {}
            if args.full:
                if args.quest is not None and d.get("event") == "questlog":
                    d = dict(d, quests=[x for x in d.get("quests") or [] if isinstance(x, dict) and x.get("quest") == args.quest])
                print("%s  %s" % (when(row.get("t")), json.dumps(d, indent=2, sort_keys=True, ensure_ascii=True)))
            else:
                print("%s  %-16s %s" % (when(row.get("t")), where(d), say(row, book)))


def fixed_bugs():
    """The reports fixed-bugs.md lists, as (session, HH:MM:SS) pairs."""
    fixed = set()
    if os.path.exists(FIXED_BUGS):
        with open(FIXED_BUGS) as f:
            for match in re.finditer(r"^- `(\d{8}-\d{6}) (\d\d:\d\d:\d\d)`", f.read(), re.M):
                fixed.add((match.group(1), match.group(2)))
    return fixed


def bugs(sessions, show_all=False):
    """Every bug report filed in the game, as the player saw it."""
    fixed = set() if show_all else fixed_bugs()
    found, skipped = 0, 0
    for name, rows in sessions:
        for row in rows:
            d = row.get("d")
            if row.get("c") != "bug" or not isinstance(d, dict):
                continue
            if (name, when(row.get("t"))[-8:]) in fixed:
                skipped += 1
                continue
            found += 1
            print("== %s  %s  %s" % (name, when(row.get("t")), where(d)))
            for line in d.get("lines") or []:
                print(line)
            print()
    if not found:
        print("no open bug reports in the log")
    if skipped:
        print("(%d fixed report(s) left out, listed in %s; --all shows them)" % (skipped, os.path.relpath(FIXED_BUGS, ADDON_ROOT)))


STATE_ORDER = ("step", "of", "title", "kind", "status", "held", "only", "open", "completion", "observed",
               "scanDone", "settled", "auto", "stall", "goals", "group", "carried", "ahead", "passed")


def say_state_field(key, value):
    """One field of a step-state row, as a reader wants it."""
    if key == "group" and isinstance(value, dict):
        members = ", ".join("#%s %s" % (m.get("i"), m.get("why")) for m in value.get("members") or [] if isinstance(m, dict))
        return "%s-%s: %s" % (value.get("first"), value.get("last"), members)
    if key == "carried" and isinstance(value, list):
        return ", ".join("#%s%s" % (c.get("i"), " sticky" if c.get("sticky") else "") for c in value if isinstance(c, dict))
    if key == "passed" and isinstance(value, list):
        return ", ".join("#%s %s" % (p.get("i"), p.get("why")) for p in value if isinstance(p, dict))
    if key == "ahead" and isinstance(value, list):
        return ", ".join("#%s" % i for i in value)
    if key == "goals" and isinstance(value, list):
        return "; ".join(str(g) for g in value)
    return json.dumps(value) if isinstance(value, (dict, list)) else str(value)


def about_step(d, step):
    """True when a guide row concerns that step: on it, moving from or to it,
    or holding it in the group or the carried card."""
    if step is None:
        return True
    if step in (d.get("step"), d.get("from"), d.get("to")):
        return True
    for move in d.get("moves") or []:
        if isinstance(move, dict) and step in (move.get("from"), move.get("to")):
            return True
    group = d.get("group") if isinstance(d.get("group"), dict) else {}
    if any(isinstance(m, dict) and m.get("i") == step for m in group.get("members") or []):
        return True
    return any(isinstance(c, dict) and c.get("i") == step for c in d.get("carried") or [])


def steps(sessions, args):
    """The step viewer's history: moves, and each change of state as a diff."""
    for name, rows in sessions:
        picked = [row for row in rows if row.get("c") == "guide" and isinstance(row.get("d"), dict)
                  and about_step(row["d"], args.step)]
        if not picked:
            continue
        print("== %s" % name)
        last = None
        for row in picked:
            d = row["d"]
            stamp = when(row.get("t"))
            if d.get("event") == "step":
                print("%s  move %-8s #%s -> #%s  (%s)" % (stamp, d.get("how"), d.get("from"), d.get("to"), d.get("guide")))
                continue
            if d.get("event") != "state":
                continue
            if d.get("none") or d.get("finished"):
                print("%s  state: %s" % (stamp, "guide finished" if d.get("finished") else "no guide running"))
                last = None
                continue
            moves = ", ".join("#%s->#%s %s" % (m.get("from"), m.get("to"), m.get("why"))
                              for m in d.get("moves") or [] if isinstance(m, dict))
            head = "%s  state (%s)%s" % (stamp, d.get("cause"), ("  moved " + moves) if moves else "")
            if d.get("stall"):
                head += "  ** STALLED: reads done but %s **" % d["stall"]
            print(head)
            whole = args.full or last is None or last.get("guide") != d.get("guide")
            for key in STATE_ORDER:
                if key not in d and (whole or key not in (last or {})):
                    continue
                if not whole and last.get(key) == d.get(key):
                    continue
                shown = say_state_field(key, d[key]) if key in d else "(cleared)"
                print("      %-10s %s" % (key, shown))
            last = d


def unguided(sessions, book):
    """Quests the player met in play that no packaged guide mentions."""
    guided = guided_quests()
    seen = {}
    for name, rows in sessions:
        for row in rows:
            d = row.get("d")
            if not isinstance(d, dict):
                continue
            ids = []
            if d.get("event") in ("accept", "turnin", "abandon", "objective", "loot") and d.get("quest"):
                ids.append(d["quest"])
            ids.extend(x.get("quest") for x in d.get("quests") or [] if isinstance(x, dict) and x.get("quest"))
            for qid in ids:
                if qid not in guided:
                    seen.setdefault(qid, []).append((name, row))
    if not seen:
        print("every quest in the log is in a packaged guide")
        return
    for qid in sorted(seen):
        print("== %s" % book.quest(qid))
        described = False
        for name, row in seen[qid]:
            d = row["d"]
            if d.get("event") == "questlog":
                entry = next(x for x in d["quests"] if isinstance(x, dict) and x.get("quest") == qid)
                if not described and entry.get("objectiveText"):
                    print("   asks: %s" % entry["objectiveText"].replace("\n", " "))
                    described = True
                parts = entry.get("objectives")
                if isinstance(parts, list):
                    for part in parts:
                        print("   %s  in log: part %s %s (%s)" % (when(row.get("t")), part.get("part"), part.get("text"), part.get("type")))
                continue
            if d.get("event") == "accept" and d.get("objectiveText"):
                described = True
            print("   %s  %-16s %s" % (when(row.get("t")), where(d), say(row, book)))


def main():
    parser = argparse.ArgumentParser(description="Read the session log as one timeline.")
    parser.add_argument("--saved", help="read this SavedVariables file instead of every account's NuuRoad.lua")
    parser.add_argument("--quest", type=int, help="only rows about this quest ID")
    parser.add_argument("--npc", type=int, help="only rows about this NPC ID (as giver, talker, or loot source)")
    parser.add_argument("--event", action="append", help="only rows of this event (accept, loot, ...; with --trace, plan, change, ...); repeatable")
    parser.add_argument("--channel", action="append", help="only rows on this channel (rec, session, ...; with --trace, any traced channel); repeatable")
    parser.add_argument("--since", help="sessions from this name on, e.g. 20260922 or 20260922-2300")
    parser.add_argument("--full", action="store_true", help="print every field of each row")
    parser.add_argument("--jsonl", action="store_true", help="print the rows as JSON lines, each tagged with its session")
    parser.add_argument("--unguided", action="store_true", help="quests seen in play that no packaged guide mentions")
    parser.add_argument("--bugs", action="store_true", help="every open bug report filed from the game, in full")
    parser.add_argument("--all", action="store_true", help="with --bugs, the fixed ones in fixed-bugs.md too")
    parser.add_argument("--steps", action="store_true", help="the step viewer's history: moves and every change of state")
    parser.add_argument("--step", type=int, help="with --steps, only rows about this guide step")
    parser.add_argument("--trace", type=int, nargs="?", const=1, metavar="N",
                        help="print the Nth latest trace session (1, the latest, when N is left out)")
    parser.add_argument("--list-traces", action="store_true", help="list the trace sessions kept")
    args = parser.parse_args()

    global saved_files
    if args.saved:
        saved_files = [args.saved]
    if args.trace is not None or args.list_traces:
        traces = load_traces()
        if not traces:
            sys.exit("no trace sessions in %s" % (args.saved or SAVED))
        if args.list_traces:
            list_traces(traces)
        else:
            show_trace(traces, args.trace, args)
        return
    sessions = load_sessions(args.since)
    if not sessions:
        sys.exit("no sessions in %s" % (args.saved or SAVED))
    book = Book(sessions)
    if args.bugs:
        bugs(sessions, args.all)
    elif args.steps:
        steps(sessions, args)
    elif args.unguided:
        unguided(sessions, book)
    else:
        timeline(sessions, book, args)


if __name__ == "__main__":
    # Piped into head or less, stop quietly when the reader does.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    main()
