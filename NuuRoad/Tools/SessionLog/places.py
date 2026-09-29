#!/usr/bin/env python3
"""The place recorder's trails, out of the session log and into Lua files.

    python3 Tools/SessionLog/places.py

Every walk with the place recorder (its `placetrail` rows: a `start`, one
`sample` row per sample with any marks made there, and a `stop`; or, from
older sessions, the whole trail in one row) is put back together and
written to Tools/SessionLog/places/<session>-<trail>.lua as `return { ... }`, ready for

    lua Tools/ProcessPlace.lua Tools/SessionLog/places/<file>.lua

which works the place out again, with other settings if the first try was not
right. A file that is already there is left alone, so a trail the log has
since dropped for age keeps its file. It only reads the saved log.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sessions import ADDON_ROOT, load_sessions  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "places")
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua(value, indent=""):
    """A JSON value as a Lua literal: lists stay lists, objects keyed tables."""
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)  # a JSON string of ASCII text is a valid Lua string
    inner = indent + "  "
    if isinstance(value, list):
        # A list of small scalars stays on one line: at = { 40.12, 22.31 }.
        if all(not isinstance(item, (list, dict)) for item in value):
            return "{ " + ", ".join(lua(item) for item in value) + " }"
        return "{\n" + "".join(inner + lua(item, inner) + ",\n" for item in value) + indent + "}"
    parts = []
    for key in sorted(value):
        name = key if NAME.match(key) else "[" + json.dumps(key) + "]"
        parts.append(name + " = " + lua(value[key], inner))
    text = "{ " + ", ".join(parts) + " }"
    if len(text) < 160 and "\n" not in text:
        return text
    return "{\n" + "".join(inner + part + ",\n" for part in parts) + indent + "}"


def write(session, trail_id, trail):
    """One trail file, unless it is already there. True when written."""
    trail_id = re.sub(r"[^A-Za-z0-9_+-]", "_", str(trail_id or "trail"))
    path = os.path.join(OUT, "%s-%s.lua" % (session, trail_id))
    if os.path.exists(path) or not trail.get("samples"):
        return False
    with open(path, "w", encoding="ascii", errors="replace") as handle:
        handle.write("-- Place recorder trail from session %s. Process it with:\n" % session)
        handle.write("--   lua Tools/ProcessPlace.lua %s\n" % os.path.relpath(path, ADDON_ROOT))
        handle.write("return " + lua(trail) + "\n")
    print("%s  (%d samples, %d marks%s)" % (path, len(trail["samples"]), len(trail.get("marks") or []),
                                          "" if trail.get("stopped", True) else ", not stopped: the session ended mid-walk"))
    return True


def main():
    os.makedirs(OUT, exist_ok=True)
    written = 0
    for session, rows in load_sessions():
        walks = {}
        order = []
        for row in rows:
            d = row.get("d")
            if row.get("c") != "placetrail" or not isinstance(d, dict):
                continue
            event = d.get("event")
            if event is None and d.get("samples"):
                # The old shape: the whole trail in one row, written at STOP.
                trail = {key: d[key] for key in ("name", "map", "place", "samples", "marks") if key in d}
                written += write(session, d.get("trail"), trail)
                continue
            trail_id = d.get("trail")
            if trail_id not in walks:
                walks[trail_id] = {"samples": [], "marks": [], "stopped": False}
                order.append(trail_id)
            walk = walks[trail_id]
            if event == "start":
                for key in ("name", "map", "place"):
                    if d.get(key) is not None:
                        walk[key] = d[key]
            elif event == "sample" and isinstance(d.get("s"), dict):
                walk["samples"].append(d["s"])
                for mark in d.get("marks") or []:
                    if isinstance(mark, dict):
                        walk["marks"].append(dict(mark, sample=len(walk["samples"])))
            elif event == "stop":
                walk["stopped"] = True
                if d.get("name"):
                    walk["name"] = d["name"]
        for trail_id in order:
            walk = walks[trail_id]
            stopped = walk.pop("stopped")
            trail = {key: walk[key] for key in ("name", "map", "place", "samples", "marks") if key in walk}
            trail["stopped"] = stopped
            written += write(session, trail_id, trail)
    if written == 0:
        print("No new place recorder trails in the log.")


if __name__ == "__main__":
    main()
