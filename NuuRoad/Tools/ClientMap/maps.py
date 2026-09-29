"""A world map (UiMap) as the client itself describes it: its name, which
continent it is on, where its 0-100 % square sits in world yards, and the
tiles of its art. Read from the client's tables (UiMap, UiMapAssignment,
UiMapXMapArt, UiMapArtTile, UiMapArtStyleLayer) and cached in
.cache/maps.json.

For Undercity (1458) the frame read here matches the one fitted from 931
place recorder samples to 0.01 yd.
"""

import json
import os

import db2
from casc import CACHE

# The terrain of each continent (Map.db2's Directory; that table's strings
# are not read yet).
CONTINENTS = {0: "azeroth", 1: "kalimdor"}


def _build(storage):
    names = {r["ID"]: r["Name_lang"] for r in db2.read(storage, "UiMap")}
    styles = {r["UiMapArtStyleID"]: r for r in db2.read(storage, "UiMapArtStyleLayer") if r["LayerIndex"] == 0}
    arts = {r["ID"]: r for r in db2.read(storage, "UiMapArt")}
    art_of = {r["UiMapID"]: r["UiMapArtID"] for r in db2.read(storage, "UiMapXMapArt") if r["PhaseID"] == 0}
    tiles = {}
    for r in db2.read(storage, "UiMapArtTile"):
        if r["LayerIndex"] == 0:
            tiles.setdefault(r["UiMapArtID"], []).append([r["RowIndex"], r["ColIndex"], r["FileDataID"]])
    out = {}
    for r in db2.read(storage, "UiMapAssignment"):
        ui_map = r["UiMapID"]
        # The assignment covering the whole map (0-1 on both axes) frames it.
        if r["UiMin"] != [0.0, 0.0] or r["UiMax"] != [1.0, 1.0] or ui_map in out:
            continue
        x0, y0, _, x1, y1, _ = r["Region"]
        art = art_of.get(ui_map)
        style = styles.get(arts[art]["UiMapArtStyleID"]) if art in arts else None
        out[ui_map] = {
            "name": names.get(ui_map, str(ui_map)),
            "continent": r["MapID"],
            # World Y at 0 % and 100 % across, world X at 0 % and 100 % down.
            "left": y1, "right": y0, "top": x1, "bottom": x0,
            "art": sorted(tiles.get(art, [])),
            "art_size": [style["LayerWidth"], style["LayerHeight"]] if style else [1002, 668],
            "tile_size": style["TileWidth"] if style else 256,
        }
    return out


def load(storage=None):
    """{ui map id: description}, built from the client once."""
    path = os.path.join(CACHE, "maps.json")
    if os.path.exists(path):
        return {int(k): v for k, v in json.load(open(path)).items()}
    if storage is None:
        from casc import Storage
        storage = Storage()
    maps = _build(storage)
    with open(path, "w") as out:
        json.dump(maps, out, indent=1)
    return maps


def get(ui_map, storage=None):
    maps = load(storage)
    if ui_map not in maps:
        raise KeyError("map %d is not in the client's tables" % ui_map)
    return maps[ui_map]
