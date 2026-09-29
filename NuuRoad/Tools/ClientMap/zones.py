#!/usr/bin/env python3
"""What a zone holds, for the zone browser (serve.py, /zones.html): every
placed model (WMO) classified as a cave, a dungeon entrance, a building or
something else, the holes in the ground (where a cave or tunnel opens), and
the zone's own minimap picture under them.

    python3 Tools/ClientMap/zones.py 1412        (writes .cache/zones/1412.json and .jpg)

Kinds come from the model's path: world/wmo/dungeon/md_* are the small caves,
dens, mines, hives, crypts and tunnels of the open world (not the ships and
keeps among them); the other world/wmo/dungeon/ models are instance
entrances; models the Forever beta added have made-up names (autogen-names)
and are "new" until someone looks.
"""

import io
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maps  # noqa: E402
import regions  # noqa: E402
import wowfiles  # noqa: E402
from casc import CACHE, Storage  # noqa: E402

OUT = os.path.join(CACHE, "zones")
NOT_CAVES = ("md_shipwreck", "md_pirateship", "md_ruinedkeep")
LARGEST = 4096  # pixels across the zone picture at most


def kind_of(name):
    if not name:
        return "new"
    parts = name.split("/")
    if len(parts) > 3 and parts[2] == "dungeon":
        if parts[3].startswith("md_") and not parts[3].startswith(NOT_CAVES):
            return "cave"
        if parts[3].startswith("md_"):
            return "other"
        return "dungeon"
    if "autogen-names" in name:
        return "new"
    if "/buildings/" in name or "/thunderbluff/" in name:
        return "building"
    return "other"


def holes(root):
    """World (X, Y) of every hole square in a tile's ground, and its size."""
    unit = wowfiles.TILE / 128
    out = []
    for tag, body in wowfiles.chunks(root):
        if tag != "MCNK" or len(body) < 0x80:
            continue
        flags = struct.unpack_from("<I", body, 0)[0]
        cx, cy, _ = struct.unpack_from("<3f", body, 0x68)
        if flags & 0x10000:
            bits, cell = struct.unpack_from("<Q", body, 0x14)[0], 1
            squares = [(i, j) for i in range(8) for j in range(8) if bits >> (i * 8 + j) & 1]
        else:
            bits, cell = struct.unpack_from("<H", body, 0x3C)[0], 2
            squares = [(i * 2, j * 2) for i in range(4) for j in range(4) if bits >> (i * 4 + j) & 1]
        for i, j in squares:
            out.append((cx - (i + cell / 2) * unit, cy - (j + cell / 2) * unit, cell * unit))
    return out


def build(map_id, storage=None):
    storage = storage or Storage()
    info = maps.get(map_id, storage)
    folder = maps.CONTINENTS.get(info["continent"])
    if folder is None:
        raise SystemExit("map %d is not on a continent this knows" % map_id)
    tiles = wowfiles.wdt_tiles(storage.read_path("world/maps/%s/%s.wdt" % (folder, folder)))
    x0, x1, y0, y1 = regions.world_rect(map_id)
    inside = lambda x, y: x0 <= x <= x1 and y0 <= y <= y1  # noqa: E731
    models, gaps, seen = [], [], set()
    for (tx, ty), files in sorted(tiles.items()):
        tile_x0, tile_y0 = (32 - ty - 1) * wowfiles.TILE, (32 - tx - 1) * wowfiles.TILE
        if tile_x0 > x1 or tile_x0 + wowfiles.TILE < x0 or tile_y0 > y1 or tile_y0 + wowfiles.TILE < y0:
            continue
        for placement in wowfiles.adt_wmo_placements(storage.read(files["obj0"]) or b""):
            if placement["unique"] in seen or placement["file"] is None:
                continue
            seen.add(placement["unique"])
            bx0, by0, bx1, by1 = placement["box"]
            cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
            if not inside(cx, cy):
                continue
            name = storage.name(placement["file"])
            mx, my = regions.to_map(map_id, cx, cy)
            a, b = regions.to_map(map_id, bx1, by1), regions.to_map(map_id, bx0, by0)
            models.append({
                "file": placement["file"], "unique": placement["unique"], "name": name or "",
                "kind": kind_of(name), "at": [round(mx, 2), round(my, 2)],
                "box": [round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2)],
                "size": [round(bx1 - bx0), round(by1 - by0)],
                "height": round(placement["pos"][1], 1)})
        for x, y, size in holes(storage.read(files["root"]) or b""):
            if inside(x, y):
                mx, my = regions.to_map(map_id, x, y)
                gaps.append([round(mx, 2), round(my, 2)])
    result = {"map": map_id, "name": info["name"], "models": models, "holes": gaps,
              "yards": [round(abs(info["right"] - info["left"])), round(abs(info["bottom"] - info["top"]))]}
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "%d.json" % map_id), "w") as out:
        json.dump(result, out)
    picture(storage, map_id, tiles, (x0, x1, y0, y1))
    return result


def picture(storage, map_id, tiles, rect):
    """The zone's minimap tiles over its 0-100 % square, as a JPEG."""
    x0, x1, y0, y1 = rect
    image, covered = wowfiles.tile_mosaic(storage, tiles, rect, "minimap")
    if image is None:
        return
    cx0, cx1, cy0, cy1 = covered
    per_yard = image.size[0] / (cy1 - cy0)
    # Mosaic columns run from the west edge (world Y falling), rows from the north.
    box = ((cy1 - y1) * per_yard, (cx1 - x1) * per_yard, (cy1 - y0) * per_yard, (cx1 - x0) * per_yard)
    part = image.crop(tuple(int(v) for v in box))
    scale = min(1.0, LARGEST / max(part.size))
    if scale < 1:
        part = part.resize((int(part.size[0] * scale), int(part.size[1] * scale)))
    part.save(os.path.join(OUT, "%d.jpg" % map_id), "JPEG", quality=85)


def zones():
    """The maps the browser offers: those on a continent, not the continents."""
    out = {}
    for map_id, info in maps.load().items():
        if info["continent"] not in maps.CONTINENTS:
            continue
        if abs(info["right"] - info["left"]) > 12000:  # a continent or the world
            continue
        out[map_id] = info["name"]
    return out


def main():
    storage = Storage()
    for arg in sys.argv[1:] or [str(m) for m in zones()]:
        result = build(int(arg), storage)
        kinds = {}
        for m in result["models"]:
            kinds[m["kind"]] = kinds.get(m["kind"], 0) + 1
        print("%s (%d): %s, %d holes" % (result["name"], result["map"],
                                         ", ".join("%d %s" % (n, k) for k, n in sorted(kinds.items())),
                                         len(result["holes"])))


if __name__ == "__main__":
    main()
