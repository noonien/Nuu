#!/usr/bin/env python3
"""Ship what trainers and merchants showed in play: Data/ProfessionRecorded.lua.

The trainer and merchant rows API/Client.lua records
(`NuuProfessionsDB.professions.trainers` and `.merchants`; OpenRoad kept the
same rows in `OpenRoadDB.professions`) live in one player's saved variables.
This tool merges the live WTF/Account/*/SavedVariables/NuuProfessions.lua (and
OpenRoad.lua, while it is still played)
over what Data/ProfessionRecorded.lua already ships (the latest `seen` wins per
NPC and key, so nothing shipped is lost) and writes the result back as addon
data, which Domain/Prices.lua reads beside the player's own book.

    python3 Tools/ProfData/recorded.py            write Data/ProfessionRecorded.lua
    python3 Tools/ProfData/recorded.py --dry-run  report only

The game's files are parsed (Tools/SessionLog/lua_table.py), never run.
"""

import argparse
import datetime
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "Tools", "SessionLog"))
from lua_table import parse_saved_variables, LuaParseError  # noqa: E402

OUTPUT = os.path.join(ROOT, "Data", "ProfessionRecorded.lua")
# The client folder this addon sits in: <client>/Interface/Nuu/NuuProfessions.
CLIENT = os.path.normpath(os.path.join(ROOT, "..", "..", ".."))

TRAINER_FIELDS = ("name", "cost", "profession", "skill", "level", "spellID", "itemID", "seen")
MERCHANT_FIELDS = ("price", "count", "stock", "currency", "items", "seen")


# Saved file -> the table in it that holds the book.
SAVED = (("NuuProfessions.lua", "NuuProfessionsDB"), ("OpenRoad.lua", "OpenRoadDB"))


def sources():
    """The live saved files, one per account and addon, with their table's name."""
    found = []
    for name, table in SAVED:
        for path in sorted(glob.glob(os.path.join(CLIENT, "WTF", "Account", "*", "SavedVariables", name))):
            found.append((path, table))
    return found


SHIPPED_TABLE = "ns.professionRecorded = "


def shipped():
    """What Data/ProfessionRecorded.lua ships now, as a saved file's book."""
    try:
        with open(OUTPUT, encoding="ascii", errors="replace") as handle:
            text = handle.read()
    except OSError:
        return {}
    start = text.find(SHIPPED_TABLE)
    if start < 0:
        return {}
    return parse_saved_variables("book = " + text[start + len(SHIPPED_TABLE):]).get("book") or {}


def key_of(raw):
    """A saved key as the addon wrote it: a number where it was one."""
    if isinstance(raw, (int, float)):
        return int(raw) if float(raw).is_integer() else raw
    if isinstance(raw, str) and raw.lstrip("-").isdigit():
        return int(raw)
    return raw


def current_names(row):
    """A trainer row saved by OpenRoad, or by NuuProfessions before the
    rename, names the profession `skill` and the skill it needs `rank`: in
    today's names, `profession` and `skill`."""
    if "rank" in row and "profession" not in row and isinstance(row.get("skill"), str):
        row = dict(row)
        row["profession"], row["skill"] = row["skill"], row.pop("rank")
    return row


def merge(into, rows, fields, origin):
    """Merge { npc: { key: row } } into `into`, the latest `seen` winning."""
    changed = 0
    for npc, entries in (rows or {}).items():
        if not isinstance(entries, dict):
            continue
        npc = key_of(npc)
        if not isinstance(npc, int):
            continue
        target = into.setdefault(npc, {})
        for key, row in entries.items():
            if not isinstance(row, dict):
                continue
            key = key_of(key)
            row = current_names(row)
            kept = {field: row[field] for field in fields if row.get(field) is not None}
            old = target.get(key)
            if old is None or (kept.get("seen") or 0) >= (old[0].get("seen") or 0):
                if old is None or old[0] != kept:
                    changed += 1
                target[key] = (kept, origin)
    return changed


def ascii_text(text):
    return "".join(ch if 32 <= ord(ch) < 127 else "?" for ch in text)


def lua_key(key):
    if isinstance(key, int):
        return "[%d]" % key
    return '["%s"]' % ascii_text(str(key)).replace("\\", "\\\\").replace('"', '\\"')


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else repr(value)
    if isinstance(value, str):
        return '"%s"' % ascii_text(value).replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(value, dict):
        # Only keyed tables (currency and item costs): never a list mixed in.
        parts = ["%s = %s" % (lua_key(key_of(k)), lua_value(v)) for k, v in sorted(value.items(), key=lambda kv: str(kv[0]))]
        return "{ " + ", ".join(parts) + " }"
    raise ValueError("cannot write %r" % (value,))


def row_text(row, fields):
    return "{ " + ", ".join("%s = %s" % (field, lua_value(row[field])) for field in fields if field in row) + " }"


def sort_key(key):
    return (0, key, "") if isinstance(key, int) else (1, 0, str(key))


def render(trainers, merchants, used, now):
    lines = [
        "-- Data/ProfessionRecorded.lua",
        "-- Generated by Tools/ProfData/recorded.py from recorded play. Do not edit.",
        "-- What profession trainers and merchants showed in trainer and merchant windows",
        "-- (API/Client.lua, NuuProfessionsDB.professions; OpenRoadDB.professions before",
        "-- the planner moved), each run merged over the last;",
        "-- the latest `seen` wins per NPC and key. Domain/Prices.lua reads it beside the",
        "-- player's own book, whose rows win. Provenance: recorded (Forever beta client).",
        "-- generated %s; this run merged %d file(s):" % (now, len(used)),
    ]
    for path in used:
        base = ROOT if os.path.abspath(path).startswith(ROOT + os.sep) else CLIENT
        lines.append("--   " + ascii_text(os.path.relpath(path, base).replace(os.sep, "/")))
    lines += [
        "local _, ns = ...",
        "ns.professionRecorded = {",
        "    trainers = {",
    ]
    for npc in sorted(trainers):
        lines.append("        [%d] = {" % npc)
        for key in sorted(trainers[npc], key=sort_key):
            lines.append("            %s = %s," % (lua_key(key), row_text(trainers[npc][key][0], TRAINER_FIELDS)))
        lines.append("        },")
    lines += ["    },", "    merchants = {"]
    for npc in sorted(merchants):
        lines.append("        [%d] = {" % npc)
        for key in sorted(merchants[npc], key=sort_key):
            lines.append("            %s = %s," % (lua_key(key), row_text(merchants[npc][key][0], MERCHANT_FIELDS)))
        lines.append("        },")
    lines += ["    },", "}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="report, write nothing")
    args = parser.parse_args()

    trainers, merchants, used = {}, {}, []
    try:
        book = shipped()
    except LuaParseError as error:
        sys.exit("cannot read %s: %s" % (os.path.relpath(OUTPUT, ROOT), error))
    merge(trainers, book.get("trainers"), TRAINER_FIELDS, OUTPUT)
    merge(merchants, book.get("merchants"), MERCHANT_FIELDS, OUTPUT)
    for path, table in sources():
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                data = parse_saved_variables(handle.read())
        except (LuaParseError, OSError) as error:
            print("skipped %s: %s" % (os.path.relpath(path, ROOT), error), file=sys.stderr)
            continue
        book = (data.get(table) or {}).get("professions") or {}
        if not isinstance(book, dict):
            continue
        found = merge(trainers, book.get("trainers"), TRAINER_FIELDS, path)
        found += merge(merchants, book.get("merchants"), MERCHANT_FIELDS, path)
        if found:
            used.append(path)

    for label, table in (("trainer", trainers), ("merchant", merchants)):
        for npc in sorted(table):
            print("%s %d: %d rows" % (label, npc, len(table[npc])))
    now = datetime.date.today().isoformat()
    text = render(trainers, merchants, used, now)
    if args.dry_run:
        print("dry run: %d trainers, %d merchants, nothing written" % (len(trainers), len(merchants)))
        return
    with open(OUTPUT, "w", encoding="ascii", newline="\n") as handle:
        handle.write(text)
    print("wrote %s (%d trainers, %d merchants)" % (os.path.relpath(OUTPUT, ROOT), len(trainers), len(merchants)))


if __name__ == "__main__":
    main()
