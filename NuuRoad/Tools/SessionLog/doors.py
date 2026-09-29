#!/usr/bin/env python3
"""Candidate travel data from recorded play, for review.

    python3 Tools/SessionLog/doors.py

Reads the session log the way sessions.py does and prints two lists for
Data/Travel.lua, nothing more:

* doorways: every `door` row (the client's map changed while the player was on
  foot) clustered by the pair of maps and by place, so walking through
  Orgrimmar's west gate five times is one candidate with a count;
* flight masters: every `flightpath` row (the taxi map opened), averaged per
  node name, with the NPC from the `talk` row that opened it when there is one.

A candidate is only a suggestion. It says where the player crossed, not where
the gate is drawn: read it, walk it, and copy what holds up by hand. It only
reads; nothing here writes to the saved file or the addon.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sessions import load_sessions  # noqa: E402

CLUSTER = 1.5  # map percent: crossings closer than this are one doorway


def rows():
    for _, session in load_sessions():
        for row in session:
            d = row.get("d")
            if row.get("c") == "rec" and isinstance(d, dict):
                yield d


def position(d):
    at = d.get("at")
    if isinstance(at, list) and len(at) == 2 and all(isinstance(v, (int, float)) for v in at):
        return at
    return None


def main():
    doors = []  # { maps, map, points }
    flights = {}
    last_npc = None
    for d in rows():
        event = d.get("event")
        if event == "talk":
            last_npc = d.get("npc")
        at = position(d)
        if event == "door" and at and d.get("map"):
            maps = tuple(sorted((d.get("from"), d.get("to")), key=str))
            for cluster in doors:
                if cluster["maps"] == maps and cluster["map"] == d["map"] and math.dist(cluster["points"][0], at) < CLUSTER:
                    cluster["points"].append(at)
                    break
            else:
                doors.append({"maps": maps, "map": d["map"], "points": [at]})
        elif event == "flightpath" and at and d.get("node"):
            entry = flights.setdefault(d["node"], {"map": d.get("map"), "points": [], "npc": None})
            entry["points"].append(at)
            entry["npc"] = entry["npc"] or last_npc

    def mean(points):
        return [round(sum(p[i] for p in points) / len(points), 2) for i in (0, 1)]

    print("Doorways (map change on foot), most crossed first:")
    for cluster in sorted(doors, key=lambda c: -len(c["points"])):
        x, y = mean(cluster["points"])
        print("  maps %s <-> %s  on map %s at { %.2f, %.2f }  crossed %d times"
              % (cluster["maps"][0], cluster["maps"][1], cluster["map"], x, y, len(cluster["points"])))
    print()
    print("Flight masters (taxi map opened):")
    for name in sorted(flights):
        entry = flights[name]
        x, y = mean(entry["points"])
        npc = (", npc = %s" % entry["npc"]) if entry["npc"] else ""
        print('  { name = "%s"%s, map = %s, at = { %.2f, %.2f } },  -- seen %d times'
              % (name, npc, entry["map"], x, y, len(entry["points"])))


if __name__ == "__main__":
    main()
