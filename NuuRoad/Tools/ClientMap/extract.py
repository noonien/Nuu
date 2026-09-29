#!/usr/bin/env python3
"""A region's walkable geometry, out of the client and into a mesh file.

    python3 Tools/ClientMap/extract.py undercity

Reads the map tiles under the region's area (regions.py; the continent and
frame come from the client, maps.py) and gathers, in world coordinates:

  * the ground of each tile, holes left out (unless `terrain` is off), only
    the chunks of the region's `areas` when it names them;
  * every WMO whose box reaches into the area (or only the region's
    `models`), with its liquid surfaces;
  * the props with a collision shell: those the WMOs set out, and those the
    tiles place when the ground is used (unless `props` is off).

Writes .cache/<region>.obj for navmesh (Recast's axes: x = world X,
y = height, z = -world Y), the same as .cache/<region>.mesh.npz for the
viewer, .cache/<region>.json (what was placed where) and
.cache/<region>.liquid.json (water surfaces). As a check it says how many
place recorder samples on the region's map stand over a floor it made; the
viewer (view.py) shows the rest by eye.
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maps  # noqa: E402
import regions  # noqa: E402
import trails  # noqa: E402
import wowfiles  # noqa: E402
from casc import CACHE, Storage  # noqa: E402

MARGIN = 20.0  # yards of the world kept round the area, so its edges are not cut short


class Mesh:
    """Triangles, each tagged with where it comes from: terrain, a model
    (WMO) or a prop (M2); navmesh keeps the tag on the floor it makes."""

    SOURCES = ("terrain", "model", "prop")

    def __init__(self):
        self.vertices, self.triangles, self.sources = [], [], []

    def add(self, vertices, triangles, transform=None, source="model"):
        base = len(self.vertices)
        self.vertices.extend(transform(*v) if transform else v for v in vertices)
        self.triangles.extend((a + base, b + base, c + base) for a, b, c in triangles)
        self.sources.extend([source] * len(triangles))


def overlaps(box, rect):
    """Whether a (X min, Y min, X max, Y max) box reaches into a rect
    (X min, X max, Y min, Y max) grown by MARGIN."""
    x0, y0, x1, y1 = box
    ax, bx, ay, by = rect
    return x1 >= ax - MARGIN and x0 <= bx + MARGIN and y1 >= ay - MARGIN and y0 <= by + MARGIN


def tiles_under(tiles, rect):
    for (tx, ty), files in sorted(tiles.items()):
        # A tile covers world X from (32 - ty - 1) to (32 - ty) tiles, Y likewise with tx.
        x0, y0 = (32 - ty - 1) * wowfiles.TILE, (32 - tx - 1) * wowfiles.TILE
        if overlaps((x0, y0, x0 + wowfiles.TILE, y0 + wowfiles.TILE), rect):
            yield (tx, ty), files


def floor_cells(vertices, triangles, cell=1.0):
    """The (i, j) cells, `cell` yards square, under a floor-like triangle
    (within 45 degrees of level, facing up or down), in world X and Y."""
    cells = set()
    for a, b, c in triangles:
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = vertices[a], vertices[b], vertices[c]
        ux, uy, uz = bx - ax, by - ay, bz - az
        vx, vy, vz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        det = ux * vy - uy * vx
        if length == 0 or det == 0 or abs(nz) / length < 0.7:
            continue
        for i in range(int(math.floor(min(ax, bx, cx) / cell)), int(math.floor(max(ax, bx, cx) / cell)) + 1):
            for j in range(int(math.floor(min(ay, by, cy) / cell)), int(math.floor(max(ay, by, cy) / cell)) + 1):
                px, py = (i + 0.5) * cell - ax, (j + 0.5) * cell - ay
                s = (px * vy - py * vx) / det
                t = (ux * py - uy * px) / det
                if s >= -0.3 and t >= -0.3 and s + t <= 1.3:
                    cells.add((i, j))
    return cells


def check_against_trails(region, mesh):
    """How many recorded samples on the map stand over a floor of the mesh."""
    samples = [s["w"] for t in trails.for_map(region["map"]) for s in t["samples"] if s["w"]]
    if not samples:
        print("  no place recorder trail on map %d to check against" % region["map"])
        return
    cells = floor_cells(mesh.vertices, mesh.triangles)
    over = sum((math.floor(x), math.floor(y)) in cells for x, y in samples)
    print("  %d of %d trail samples (%.0f%%) stand over a floor" % (over, len(samples), over * 100 / len(samples)))


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "undercity"
    region = regions.REGIONS[name]
    storage = Storage()
    info = maps.get(region["map"], storage)
    rect = regions.area(region)
    folder = maps.CONTINENTS[info["continent"]]
    tiles = wowfiles.wdt_tiles(storage.read_path("world/maps/%s/%s.wdt" % (folder, folder)))
    wanted = set(region.get("models") or [])
    use_terrain, use_props = region.get("terrain", True), region.get("props", True)
    mesh, liquids = Mesh(), []
    report = {"wmo": [], "props": 0, "prop_triangles": 0, "terrain_triangles": 0}
    wmos, m2s = {}, {}
    areas = set(region.get("areas") or [])
    kept_chunks = []

    def keep_chunk(x0, y0, x1, y1, area):
        if not overlaps((x0, y0, x1, y1), rect) or (areas and area not in areas):
            return False
        kept_chunks.append((x0, y0, x1, y1))
        return True

    for (tx, ty), files in tiles_under(tiles, rect):
        if use_terrain:
            root = storage.read(files["root"]) or b""
            verts, tris = wowfiles.terrain_triangles(root, keep=keep_chunk)
            mesh.add(verts, tris, source="terrain")
            report["terrain_triangles"] += len(tris)
        obj0 = storage.read(files["obj0"]) or b""
        for placement in wowfiles.adt_wmo_placements(obj0):
            if placement["file"] is None:
                continue
            if wanted and placement["file"] not in wanted:
                continue
            if not overlaps(placement["box"], rect):
                continue
            wmos[placement["unique"]] = placement
        # Props the tiles place stand on the ground: without the ground (a
        # city that is one WMO), they are the surface's, not the place's.
        if use_props and use_terrain:
            for placement in wowfiles.adt_m2_placements(obj0):
                x, y = wowfiles.MAP_CENTER - placement["pos"][2], wowfiles.MAP_CENTER - placement["pos"][0]
                if placement["file"] and overlaps((x, y, x, y), rect):
                    m2s[placement["unique"]] = placement
    if areas:
        # With the ground cut down to the region's areas, only the props that
        # stand on what is left.
        m2s = {k: p for k, p in m2s.items()
               if any(x0 <= wowfiles.MAP_CENTER - p["pos"][2] <= x1 and y0 <= wowfiles.MAP_CENTER - p["pos"][0] <= y1
                      for x0, y0, x1, y1 in kept_chunks)}
    if not wmos and not use_terrain:
        raise SystemExit("none of %s is placed on the tiles under map %d" % (sorted(wanted), region["map"]))
    for placement in wmos.values():
        transform = wowfiles.placement_transform(placement)
        verts, tris = wowfiles.wmo_world_mesh(storage, placement, transform)
        mesh.add(verts, tris)
        liquids.extend(wowfiles.wmo_liquids(storage, placement, transform))
        props = 0
        if use_props:
            for file_id, pos, quat, scale in wowfiles.wmo_doodads(storage, placement):
                shell = wowfiles.m2_collision(storage, file_id)
                if shell is None:
                    continue
                inner = wowfiles.quaternion_transform(pos, quat, scale)
                mesh.add(shell[0], shell[1], lambda x, y, z, inner=inner: transform(*inner(x, y, z)), source="prop")
                props += 1
                report["prop_triangles"] += len(shell[1])
        report["wmo"].append({"file": placement["file"], "name": storage.name(placement["file"]),
                              "unique": placement["unique"], "pos": placement["pos"], "rot": placement["rot"],
                              "scale": placement["scale"], "doodad_set": placement["doodad_set"],
                              "triangles": len(tris), "props": props})
    for placement in m2s.values():
        shell = wowfiles.m2_collision(storage, placement["file"])
        if shell is None:
            continue
        mesh.add(shell[0], shell[1], wowfiles.placement_transform(placement), source="prop")
        report["props"] += 1
        report["prop_triangles"] += len(shell[1])
    print("%s (%s): %d WMOs, %d props on the tiles, %d terrain triangles, %d prop triangles" % (
        name, info["name"], len(wmos), report["props"], report["terrain_triangles"], report["prop_triangles"]))
    check_against_trails(region, mesh)
    obj = os.path.join(CACHE, name + ".obj")
    with open(obj, "w") as out:
        out.write("# %s: world X, height, -world Y\n" % name)
        for x, y, z in mesh.vertices:
            out.write("v %.3f %.3f %.3f\n" % (x, z, -y))
        # Faces grouped by source ("g terrain", "g model", "g prop").
        for source in Mesh.SOURCES:
            out.write("g %s\n" % source)
            for (a, b, c), tag in zip(mesh.triangles, mesh.sources):
                if tag == source:
                    out.write("f %d %d %d\n" % (a + 1, b + 1, c + 1))
    # The same mesh for the viewer (world X, Y, height; source 1 terrain, 2
    # model, 3 prop), quicker to read than the OBJ.
    import numpy as np
    np.savez_compressed(os.path.join(CACHE, name + ".mesh.npz"),
                        vertices=np.array(mesh.vertices, np.float32),
                        triangles=np.array(mesh.triangles, np.int32).reshape(-1, 3),
                        sources=np.array([Mesh.SOURCES.index(t) + 1 for t in mesh.sources], np.uint8))
    with open(os.path.join(CACHE, name + ".json"), "w") as out:
        json.dump(dict(report, region=name, map=region["map"]), out, indent=1)
    with open(os.path.join(CACHE, name + ".liquid.json"), "w") as out:
        json.dump({"tile": wowfiles.LIQUID_TILE, "tiles": liquids}, out)
    print("%s: %d vertices, %d triangles, %d liquid tiles" % (obj, len(mesh.vertices), len(mesh.triangles), len(liquids)))


if __name__ == "__main__":
    main()
