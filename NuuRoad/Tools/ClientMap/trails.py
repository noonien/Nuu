"""Place recorder trails (Tools/SessionLog/places/*.lua, from SessionLog/places.py),
read without a Lua interpreter: only the fields the map tools use."""

import glob
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
TRAILS = os.path.abspath(os.path.join(HERE, "..", "SessionLog", "places"))

SAMPLE = re.compile(r"\{ at = \{ ([-\d.]+), ([-\d.]+) \}(.*?)\},?\s*$", re.M)
WORLD = re.compile(r"w = \{ ([-\d.]+), ([-\d.]+) \}")
MAP = re.compile(r"map = (\d+)")


def load(path):
    """{"name", "path", "samples": [{"at", "w", "map", "falling"}]}"""
    samples = []
    text = open(path, encoding="ascii", errors="replace").read()
    for match in SAMPLE.finditer(text):
        rest = match.group(3)
        world = WORLD.search(rest)
        map_id = MAP.search(rest)
        samples.append({
            "at": (float(match.group(1)), float(match.group(2))),
            "w": (float(world.group(1)), float(world.group(2))) if world else None,
            "map": int(map_id.group(1)) if map_id else None,
            "falling": "falling = true" in rest,
        })
    return {"name": os.path.basename(path), "path": path, "samples": samples}


def for_map(map_id, paths=None):
    """Every saved trail with samples on the map."""
    out = []
    for path in paths or sorted(glob.glob(os.path.join(TRAILS, "*.lua"))):
        trail = load(path)
        trail["samples"] = [s for s in trail["samples"] if s["map"] == map_id]
        if trail["samples"]:
            out.append(trail)
    return out
