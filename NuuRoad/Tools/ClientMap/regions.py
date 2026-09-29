"""The places Tools/ClientMap knows how to build.

A region is one guide place's worth of world: the world map it is drawn on
(`map`, a UiMap ID; its name, frame, continent and art come from the client,
see maps.py), and what makes up its ground:

  * `crop`: the part of the map to use, as map % (x0, y0, x1, y1); the
    whole map when left out;
  * `terrain`: the ground of the map tiles (default True); "approach"
    keeps only the ground within `approach` yards (default 30) of a model's
    floor, the way into a cave;
  * `areas`: only the terrain chunks of these game areas (AreaTable IDs,
    as the chunks carry them), and the props on them;
  * `models`: only these WMO file IDs (default: every WMO in the area);
  * `props`: the M2 props with a collision shell, on the tiles and inside
    the WMOs (default True);
  * `lifts`: map % spots where a lift joins the floor at the top to the next
    big one at least 8 yd below (the server spawns lifts, the map files do
    not have them);
  * `exits`: map % spots where the place is entered or left;
  * `keep`: skeleton.py's default for which branches stay (core, long, all);
  * `title`: what the viewer calls it, when not the map's name.
"""

import maps

REGIONS = {
    "undercity": {
        "map": 1458,
        # The city is one WMO (new in the Forever beta, build 1.60.1.69977;
        # not the 1.12 undercity.wmo 114612 or the 8.x one 1783532). The
        # ground above it is Tirisfal's, not the place's.
        "terrain": False,
        "models": [7675285],
        # The three stubs of the corridor from the Ruins, each 2 yd short of a
        # landing 96 yd below. The south one is the lift the 2026-09-23 place
        # recorder walk rode down.
        "lifts": [(61.42, 44.21), (70.53, 44.13), (65.95, 50.92)],
        # From the door row the recorder wrote walking in from Tirisfal
        # Glades (map 1420) on 2026-09-23.
        "exits": [(66.04, 0.10)],
    },
    "bristleback": {
        # Bristleback cave in Mulgore, the nuuroad:fixture:cave-place cave:
        # one WMO, md_mushroomden, 19 yd from the mouth HordeMulgore16 gives.
        # The area is the cave's box and 40 yd round it, so the hillside at the
        # mouth is in and the rest of Mulgore is not.
        "title": "Bristleback cave",
        "map": 1412,
        "crop": (58.68, 80.16, 61.05, 83.83),
        "models": [110497],
        # The ground only as the way in: within 50 yd of the cave's floor (the
        # guide's mouth is 31 yd out from it).
        "terrain": "approach",
        "approach": 50.0,
        "exits": [(59.67, 83.33)],
        # A cave is its branches: keep them all (skeleton.py keep=all).
        "keep": "all",
    },
    "venturemine": {
        # The Venture Co. Mine in Mulgore (HordeMulgore612's section of that
        # name, entrance 61.51, 47.29): one big WMO, md_goldmine_variantc,
        # 558 by 546 yd; the area is its box and 40 yd round it.
        "title": "Venture Co. Mine",
        "map": 1412,
        "crop": (54.01, 39.71, 64.19, 55.26),
        "models": [110808],
        "terrain": "approach",
        "approach": 40.0,
        "exits": [(61.51, 47.29)],
        "keep": "all",
    },
    "orgrimmar": {
        "map": 1454,
        # The Forever beta's Orgrimmar is one WMO (autogen-names/unknown/
        # 21142.wmo, turned 34 degrees) over the old terrain, which lies under
        # it as a hidden base: the place is the WMOs' floors, not the ground.
        "terrain": False,
        # Valleys joined by single tunnels: keep the long branches, not only
        # the loops (drop only the nooks).
        "keep": "long",
    },
    "thunderbluff": {
        "map": 1456,
        # Thunder Bluff and its rises (areas 1638 to 1641: Thunder Bluff,
        # Elder Rise, Spirit Rise, Hunter Rise), not the Mulgore plain below.
        "areas": [1638, 1639, 1640, 1641],
    },
}


def name(region):
    return maps.get(region["map"])["name"]


def to_map(map_id, world_x, world_y):
    """World yards to map percentages (x across, y down)."""
    b = maps.get(map_id)
    return ((world_y - b["left"]) / (b["right"] - b["left"]) * 100,
            (world_x - b["top"]) / (b["bottom"] - b["top"]) * 100)


def to_world(map_id, x, y):
    """Map percentages to world yards (X, Y)."""
    b = maps.get(map_id)
    return (b["top"] + (b["bottom"] - b["top"]) * y / 100,
            b["left"] + (b["right"] - b["left"]) * x / 100)


def world_rect(map_id, crop=None):
    """(X min, X max, Y min, Y max) of the map, or of its `crop` (map %)."""
    x0, y0, x1, y1 = crop or (0, 0, 100, 100)
    ax, ay = to_world(map_id, x0, y0)
    bx, by = to_world(map_id, x1, y1)
    return min(ax, bx), max(ax, bx), min(ay, by), max(ay, by)


def area(region):
    return world_rect(region["map"], region.get("crop"))


# --- Marked places ----------------------------------------------------------------
# Caves marked in the zone browser (serve.py, /zones.html) are kept in
# marks.json beside this file; each becomes a region like "bristleback"
# above: the cave's model, its box and 40 yd round it, the ground within 40
# yd of the cave's floor as the way in, and every branch kept.

import json as _json
import os as _os

MARKS = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), "marks.json")
MARGIN = 40.0


def load_marks():
    if not _os.path.exists(MARKS):
        return []
    with open(MARKS) as handle:
        return _json.load(handle)


def save_marks(marks):
    with open(MARKS, "w") as handle:
        _json.dump(marks, handle, indent=1, sort_keys=True)
        handle.write("\n")


def mark_region(mark):
    b = maps.get(mark["map"])
    x0, y0, x1, y1 = mark["box"]
    grow_x = MARGIN / abs(b["right"] - b["left"]) * 100
    grow_y = MARGIN / abs(b["bottom"] - b["top"]) * 100
    return {"title": mark["title"], "map": mark["map"],
            "crop": (x0 - grow_x, y0 - grow_y, x1 + grow_x, y1 + grow_y),
            "models": [mark["model"]], "terrain": "approach", "approach": MARGIN, "keep": "all",
            "marked": True}


for _mark in load_marks():
    REGIONS.setdefault(_mark["region"], mark_region(_mark))
