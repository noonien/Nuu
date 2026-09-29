#!/usr/bin/env python3
"""An offline picture of a place: one HTML file with the game's world map
under the walkable area, the centre lines, the computed place, and any places
given as guide source, each a layer to switch on and off. Wheel zooms, drag
pans, hovering a point says what it is. A 3D tab shows the same floors at
their heights, with the place on them and the world map underneath.

    python3 Tools/ClientMap/view.py undercity [place.lua ...]

Writes .cache/viewer/data/<region>.js and one page for every region built so
far, .cache/viewer/index.html, with a picker; the address keeps the region,
the tab and the rooms layer (#region=undercity&3d&rooms).

A place.lua is anything with `{ at = { x, y } }` points and a `connections`
list, as Tools/ProcessPlace.lua and skeleton.py print it.
"""

import base64
import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maps  # noqa: E402
import navgrid  # noqa: E402
import regions  # noqa: E402
import skeleton  # noqa: E402
import wowfiles  # noqa: E402
from casc import CACHE, Storage  # noqa: E402

MAP_W, MAP_H = 1002, 668   # the world map's pixels; 0-100 % spans these
YARDS_PER_PIXEL = 0.5      # the floor pictures, where the area allows
LARGEST = 4096             # ... and at most this many pixels across


def raster_frame(region):
    """Where the floor pictures go: over the region's crop (map %), at about
    half a yard a pixel. Returns (x0, y0, x1, y1, width px, height px)."""
    x0, y0, x1, y1 = region.get("crop") or (0, 0, 100, 100)
    b = maps.get(region["map"])
    width_yd = abs(b["right"] - b["left"]) * (x1 - x0) / 100
    height_yd = abs(b["bottom"] - b["top"]) * (y1 - y0) / 100
    scale = min(1 / YARDS_PER_PIXEL, LARGEST / max(width_yd, height_yd))
    return x0, y0, x1, y1, max(1, int(width_yd * scale)), max(1, int(height_yd * scale))


def pixels(region, frame, world_x, world_y):
    """Pixel columns and rows of world positions in a raster frame."""
    x0, y0, x1, y1, w, h = frame
    b = maps.get(region["map"])
    mx = (world_y - b["left"]) / (b["right"] - b["left"]) * 100
    my = (world_x - b["top"]) / (b["bottom"] - b["top"]) * 100
    px = ((mx - x0) / (x1 - x0) * w).astype(np.int64)
    py = ((my - y0) / (y1 - y0) * h).astype(np.int64)
    return px, py, (px >= 0) & (px < w) & (py >= 0) & (py < h)


def png(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def place_floors(grid, graph, region):
    """(mask of the spans on the place's floors, labels): the pieces the
    computed place reached, or every piece when there is none yet."""
    labels = grid.components()
    mask = np.isin(labels, graph["pieces"]) if graph and graph.get("pieces") else np.ones(len(grid), bool)
    if region.get("terrain") == "approach":
        mask &= skeleton.near_models(grid, region.get("approach", 30.0))
    return mask, labels


def walkable_layer(region_name, region, graph):
    """The walkable area as a picture: the place's floors coloured by height
    (the highest floor in each pixel), the rest grey."""
    path = os.path.join(CACHE, region_name + ".bin")
    if not os.path.exists(path):
        return None
    grid = navgrid.load(region_name)
    mask, _ = place_floors(grid, graph, region)
    frame = raster_frame(region)
    world_x = grid.bmin[0] + (grid.x + 0.5) * grid.cell
    world_y = -(grid.bmin[2] + (grid.z + 0.5) * grid.cell)
    height = grid.bmin[1] + grid.y * grid.cell_height
    px, py, inside = pixels(region, frame, world_x, world_y)
    w, h = frame[4], frame[5]
    rgba = np.zeros((h, w, 4), np.uint8)
    # Everything walkable, faint.
    other = inside & ~mask
    rgba[py[other], px[other]] = (150, 150, 150, 90)
    # Reached pieces by height, highest last so it wins.
    keep = inside & mask
    order = np.argsort(height[keep])
    hx, hy, hz = px[keep][order], py[keep][order], height[keep][order]
    lo, hi = float(hz.min()), float(hz.max())
    t = (hz - lo) / max(hi - lo, 1e-6)
    # Deep blue (low) through teal and green to yellow (high).
    stops = np.array([[40, 60, 200], [30, 170, 190], [80, 200, 90], [250, 220, 60]], float)
    pos = t * (len(stops) - 1)
    i = np.minimum(pos.astype(int), len(stops) - 2)
    f = (pos - i)[:, None]
    colour = (stops[i] * (1 - f) + stops[i + 1] * f).astype(np.uint8)
    rgba[hy, hx, :3] = colour
    rgba[hy, hx, 3] = 170
    return {"image": png(Image.fromarray(rgba, "RGBA")), "low": round(lo), "high": round(hi), "frame": frame}


def scene_layer(region_name, region, graph):
    """The 3D view's data: the floors worth keeping as a surface one yard
    across, and the rest as sparse points. Coordinates are yards from the map's top left
    corner (east, up, south), quantised to a quarter yard."""
    path = os.path.join(CACHE, region_name + ".bin")
    if not os.path.exists(path):
        return None
    grid = navgrid.load(region_name)
    mask, labels = place_floors(grid, graph, region)
    b = maps.get(region["map"])
    east = b["left"] - (-(grid.bmin[2] + (grid.z + 0.5) * grid.cell))
    south = b["top"] - (grid.bmin[0] + (grid.x + 0.5) * grid.cell)
    up = grid.bmin[1] + grid.y * grid.cell_height
    n = grid.n

    def hop(spans, d):
        ok = spans >= 0
        out = np.full(len(spans), -1, np.int64)
        out[ok] = n[spans[ok], d]
        return out

    # One yard across where the place is small, coarser where it is large,
    # so the page stays a size a browser opens (about 400,000 points).
    step = 2
    while mask.sum() / (step * step) > 400000:
        step += 1
    chosen = mask & (grid.x % step == 0) & (grid.z % step == 0)
    spans = np.nonzero(chosen)[0]
    vid = np.full(len(grid), -1, np.int64)
    vid[spans] = np.arange(len(spans))
    def hops(spans, d):
        for _ in range(step):
            spans = hop(spans, d)
        return spans

    right = hops(spans, 2)
    down = hops(spans, 1)
    corner = hops(right, 1)
    corner = np.where(corner >= 0, corner, hops(down, 2))

    def ids(other):
        out = np.full(len(other), -1, np.int64)
        ok = other >= 0
        out[ok] = vid[other[ok]]
        return out

    a, r, d, c = np.arange(len(spans)), ids(right), ids(down), ids(corner)
    whole = (r >= 0) & (d >= 0) & (c >= 0)
    tris = np.concatenate([np.stack([a[whole], d[whole], r[whole]], 1),
                           np.stack([r[whole], d[whole], c[whole]], 1)]).astype(np.uint32)

    def pack(values, dtype):
        return base64.b64encode(np.ascontiguousarray(values).astype(dtype).tobytes()).decode("ascii")

    vertices = np.stack([east[spans], up[spans], south[spans]], 1) * 4
    room_rgb = None
    npy_path = os.path.join(CACHE, region_name + ".rooms.npy")
    json_path = os.path.join(CACHE, region_name + ".rooms.json")
    if os.path.exists(npy_path) and os.path.exists(json_path):
        owner = np.load(npy_path)
        if len(owner) == len(grid):
            colours = room_colours(json.load(open(json_path)))
            of = owner[spans]
            rgb = np.full((len(spans), 3), 90, np.uint8)
            rgb[of >= 0] = colours[of[of >= 0]]
            room_rgb = base64.b64encode(rgb.tobytes()).decode("ascii")
    rest = (~mask) & (grid.x % (2 * step) == 0) & (grid.z % (2 * step) == 0)
    rest_points = np.stack([east[rest], up[rest], south[rest]], 1) * 4
    heights = up[spans]
    return {"rooms": room_rgb, "vertices": pack(vertices, "<i2"), "triangles": pack(tris, "<u4"), "rest": pack(rest_points, "<i2"),
            "low": float(heights.min()), "high": float(heights.max()),
            "size": [abs(b["right"] - b["left"]), abs(b["bottom"] - b["top"])],
            "left": b["left"], "top": b["top"]}


def surface_points(vertices, triangles, spacing=0.35):
    """Points spread over every triangle, about `spacing` yards apart (at
    least its corners and middle), for drawing the mesh from above."""
    a, b, c = vertices[triangles[:, 0]], vertices[triangles[:, 1]], vertices[triangles[:, 2]]
    size = np.maximum(np.linalg.norm(b - a, axis=1), np.linalg.norm(c - a, axis=1))
    size = np.maximum(size, np.linalg.norm(c - b, axis=1))
    steps = np.clip(np.ceil(size / spacing), 1, 60).astype(int)
    out = []
    for k in np.unique(steps):
        sel = steps == k
        grid = np.array([(i / k, j / k) for i in range(k + 1) for j in range(k + 1 - i)], np.float32)
        u, v = grid[:, 0][None, :, None], grid[:, 1][None, :, None]
        pa, pb, pc = a[sel][:, None, :], b[sel][:, None, :], c[sel][:, None, :]
        out.append((pa + (pb - pa) * u + (pc - pa) * v).reshape(-1, 3))
    return np.concatenate(out) if out else np.zeros((0, 3), np.float32)


def plan_layer(region_name, region, graph):
    """A floor plan drawn from the map's own geometry: the place's floors
    shaded by height, and dark wherever something stands on them (walls,
    pillars, crates: geometry 0.3 to 2.2 yd above the floor under it), water
    in blue. Ceilings and roofs, higher up, are left out, so a city
    underground or a cave reads as a plan and not as its roof."""
    mesh_path = os.path.join(CACHE, region_name + ".mesh.npz")
    if not os.path.exists(mesh_path):
        return None
    grid = navgrid.load(region_name)
    mask, _ = place_floors(grid, graph, region)
    frame = raster_frame(region)
    w, h = frame[4], frame[5]
    world_x = grid.bmin[0] + (grid.x + 0.5) * grid.cell
    world_y = -(grid.bmin[2] + (grid.z + 0.5) * grid.cell)
    height = grid.bmin[1] + grid.y * grid.cell_height
    px, py, inside = pixels(region, frame, world_x, world_y)
    keep = inside & mask
    floor = np.full((h, w), -np.inf, np.float32)
    np.maximum.at(floor, (py[keep], px[keep]), height[keep])
    walkable = np.isfinite(floor)
    # The floor height reaches a little past the floor's edge, so the walls
    # that bound it are measured against it too.
    from scipy import ndimage
    near = floor.copy()
    for _ in range(4):
        grown = ndimage.grey_dilation(np.where(np.isfinite(near), near, -1e9), size=3)
        near = np.where(np.isfinite(near), near, np.where(grown > -1e8, grown, -np.inf))
    mesh = np.load(mesh_path)
    points = surface_points(mesh["vertices"], mesh["triangles"])
    qx, qy, ok = pixels(region, frame, points[:, 0].astype(np.float64), points[:, 1].astype(np.float64))
    qx, qy, qz = qx[ok], qy[ok], points[ok, 2]
    base = near[qy, qx]
    standing = np.isfinite(base) & (qz > base + 0.3) & (qz < base + 2.2)
    wall = np.zeros((h, w), bool)
    wall[qy[standing], qx[standing]] = True
    # Water: where a liquid surface lies over the floor.
    water = np.zeros((h, w), bool)
    liquid_path = os.path.join(CACHE, region_name + ".liquid.json")
    if os.path.exists(liquid_path):
        liquid = json.load(open(liquid_path))
        half = liquid["tile"] / 2
        for x, y, surface in liquid["tiles"]:
            xs = np.array([x - half, x + half, x - half, x + half])
            ys = np.array([y - half, y - half, y + half, y + half])
            lx, ly, _ = pixels(region, frame, xs, ys)
            x0, x1 = max(0, lx.min()), min(w, lx.max() + 1)
            y0, y1 = max(0, ly.min()), min(h, ly.max() + 1)
            if x0 < x1 and y0 < y1:
                patch = floor[y0:y1, x0:x1]
                water[y0:y1, x0:x1] |= np.isfinite(patch) & (patch < surface - 0.3)
    # Shade the floor from its slope (light from the north-west) and height.
    filled = np.where(walkable, floor, np.nan)
    gy, gx = np.gradient(np.nan_to_num(filled, nan=np.nanmean(filled) if walkable.any() else 0.0))
    shade = np.clip(0.82 + 0.35 * (-gx * 0.7 - gy * 0.7) / 2, 0.55, 1.1)
    lo, hi = (float(np.nanmin(filled)), float(np.nanmax(filled))) if walkable.any() else (0.0, 1.0)
    t = np.clip((np.nan_to_num(filled, nan=lo) - lo) / max(hi - lo, 1e-6), 0, 1)
    rgba = np.zeros((h, w, 4), np.uint8)
    low, high = np.array([150, 158, 170], float), np.array([236, 226, 200], float)
    colour = (low[None, None] * (1 - t[..., None]) + high[None, None] * t[..., None]) * shade[..., None]
    rgba[walkable, :3] = np.clip(colour[walkable], 0, 255).astype(np.uint8)
    rgba[walkable, 3] = 255
    rgba[water & walkable] = (70, 130, 205, 255)
    rgba[wall] = (38, 34, 30, 255)
    return {"image": png(Image.fromarray(rgba, "RGBA")), "frame": frame,
            "low": round(lo), "high": round(hi)}


def jpeg(image, quality=85):
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=quality)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def minimap_layer(storage, region):
    """The game's own minimap tiles (ground and buildings from above, with
    their textures) over the region's crop, in the same frame as the floor
    pictures."""
    info = maps.get(region["map"], storage)
    folder = maps.CONTINENTS[info["continent"]]
    tiles = wowfiles.wdt_tiles(storage.read_path("world/maps/%s/%s.wdt" % (folder, folder)))
    frame = raster_frame(region)
    x0, y0, x1, y1, w, h = frame
    # The crop in world yards (map x runs with -Y, map y with -X).
    ax, ay = regions.to_world(region["map"], x0, y0)
    bx, by = regions.to_world(region["map"], x1, y1)
    rect = (min(ax, bx), max(ax, bx), min(ay, by), max(ay, by))
    image, covered = wowfiles.tile_mosaic(storage, tiles, rect, "minimap")
    if image is None:
        return None
    cx0, cx1, cy0, cy1 = covered
    per_yard = image.size[0] / (cy1 - cy0)
    # Mosaic pixels: column from the west edge (world Y falling), row from the north (X falling).
    left, top = (cy1 - max(ay, by)) * per_yard, (cx1 - max(ax, bx)) * per_yard
    right, bottom = (cy1 - min(ay, by)) * per_yard, (cx1 - min(ax, bx)) * per_yard
    part = image.crop((int(left), int(top), int(right), int(bottom))).resize((min(w, 4096), min(h, 4096)))
    return {"image": jpeg(part), "frame": frame}


TEXTURE_SIZE = 128  # each texture's cell in the atlas


def geometry_data(storage, region_name, region):
    """The map's own geometry, textured, for the 3D view: the WMOs with their
    materials' textures (packed into one atlas; each vertex says its cell and
    its texture coordinates, which repeat within the cell), the ground under
    the baked terrain texture of its tiles, and the props in plain grey."""
    report_path = os.path.join(CACHE, region_name + ".json")
    mesh_path = os.path.join(CACHE, region_name + ".mesh.npz")
    if not (os.path.exists(report_path) and os.path.exists(mesh_path)):
        return None
    report = json.load(open(report_path))
    b = maps.get(region["map"], storage)
    x0, x1, y0, y1 = regions.area(region)
    margin = 20.0

    def scene(v):
        """World (X, Y, height) to the 3D view's (east, up, south), quarter yards."""
        v = np.asarray(v, np.float64)
        return np.stack([b["left"] - v[:, 1], v[:, 2], b["top"] - v[:, 0]], 1)

    def inside(v, t):
        c = v[t].mean(axis=1)
        return ((c[:, 0] > x0 - margin) & (c[:, 0] < x1 + margin) & (c[:, 1] > y0 - margin) & (c[:, 1] < y1 + margin))

    slots, textures = {}, []
    parts = {"vertices": [], "uvs": [], "slots": [], "triangles": []}
    count = 0
    for w in report["wmo"]:
        placement = {"file": w["file"], "pos": w["pos"], "rot": w["rot"], "scale": w.get("scale", 1.0),
                     "doodad_set": w.get("doodad_set", 0), "unique": w["unique"]}
        verts, uvs, tris, mats, materials = wowfiles.wmo_render(storage, placement, wowfiles.placement_transform(placement))
        if not tris:
            continue
        verts, uvs, tris, mats = np.array(verts), np.array(uvs, np.float32), np.array(tris), np.array(mats)
        keep = inside(verts, tris)
        tris, mats = tris[keep], mats[keep]
        slot_of = []
        for m in materials:
            key = (m["texture"], m["blend"] == 1)
            if key not in slots:
                slots[key] = len(textures)
                textures.append(key)
            slot_of.append(slots[key])
        vertex_slot = np.zeros(len(verts), np.uint16)
        for k in range(3):
            vertex_slot[tris[:, k]] = np.array(slot_of)[mats]
        used, remap = np.unique(tris, return_inverse=True)
        parts["vertices"].append(scene(verts[used]))
        parts["uvs"].append(uvs[used])
        parts["slots"].append(vertex_slot[used])
        parts["triangles"].append(remap.reshape(-1, 3) + count)
        count += len(used)
    # The atlas: every texture shrunk to one cell, alpha kept where the
    # material cuts out (leaves, fences), otherwise solid.
    side = max(1, int(np.ceil(np.sqrt(max(len(textures), 1)))))
    size = 1
    while size < side * TEXTURE_SIZE:
        size *= 2
    atlas = Image.new("RGBA", (size, size), (128, 128, 128, 255))
    for i, (file_id, cut) in enumerate(textures):
        data = storage.read_picture(file_id) if file_id else None
        if data is None:
            continue
        try:
            picture = Image.open(io.BytesIO(data)).convert("RGBA").resize((TEXTURE_SIZE, TEXTURE_SIZE))
        except Exception:
            continue
        if not cut:
            picture.putalpha(255)
        atlas.paste(picture, ((i % (size // TEXTURE_SIZE)) * TEXTURE_SIZE, (i // (size // TEXTURE_SIZE)) * TEXTURE_SIZE))
    mesh = np.load(mesh_path)
    mv, mt, ms = mesh["vertices"], mesh["triangles"], mesh["sources"]

    def piece(source):
        t = mt[ms == source]
        if not len(t):
            return None
        t = t[inside(mv, t)]
        used, remap = np.unique(t, return_inverse=True)
        return {"vertices": b64(np.round(scene(mv[used]) * 4).astype("<i2")),
                "triangles": b64(remap.reshape(-1, 3).astype("<u4"))}

    ground = piece(1)
    if ground is not None:
        # The ground's texture: the tiles' baked terrain pictures over the area.
        info = maps.get(region["map"], storage)
        folder = maps.CONTINENTS[info["continent"]]
        tiles = wowfiles.wdt_tiles(storage.read_path("world/maps/%s/%s.wdt" % (folder, folder)))
        image, covered = wowfiles.tile_mosaic(storage, tiles, (x0 - margin, x1 + margin, y0 - margin, y1 + margin), "maptexture")
        if image is not None:
            if max(image.size) > 4096:
                image = image.resize((min(4096, image.size[0]), min(4096, image.size[1])))
            cx0, cx1, cy0, cy1 = covered
            ground["texture"] = jpeg(image)
            # Where the picture lies in the 3D view's (east, south) yards.
            ground["rect"] = [b["left"] - cy1, b["top"] - cx1, b["left"] - cy0, b["top"] - cx0]
    out = {"props": piece(3), "ground": ground, "atlas": png(atlas), "cells": size // TEXTURE_SIZE,
           "cell": TEXTURE_SIZE / size, "textures": len(textures)}
    if parts["vertices"]:
        out["models"] = {"vertices": b64(np.round(np.concatenate(parts["vertices"]) * 4).astype("<i2")),
                         "uvs": b64(np.concatenate(parts["uvs"]).astype("<f4")),
                         "slots": b64(np.concatenate(parts["slots"]).astype("<u2")),
                         "triangles": b64(np.concatenate(parts["triangles"]).astype("<u4"))}
    heights = scene(mv)[:, 1] if len(mv) else np.zeros(1)
    out["low"], out["high"] = float(heights.min()), float(heights.max())
    return out


def b64(array):
    return base64.b64encode(np.ascontiguousarray(array).tobytes()).decode("ascii")


ROOM_COLOURS = {"hall": (70, 130, 240), "room": (70, 200, 110), "corridor": (245, 150, 50),
                "stairs": (220, 80, 220), "crossing": (245, 225, 70), "water": (40, 200, 190)}


def room_colours(rooms):
    """An RGB colour per region: its kind's colour, lighter or darker by
    region so neighbours of one kind still differ."""
    out = []
    for r in rooms["regions"]:
        base = np.array(ROOM_COLOURS.get(r["kind"], (200, 200, 200)), float)
        shade = 0.72 + 0.5 * (((r["id"] * 2654435761) % 1000) / 1000.0)
        out.append(np.clip(base * shade, 0, 255).astype(np.uint8))
    return np.array(out, np.uint8).reshape(-1, 3)


def rooms_layer(region_name, region):
    """The rooms as two pictures: one to see (each region in its kind's
    colour, edges dark) and one to look up (the region number in the pixel's
    colour), with the regions and doorways themselves."""
    json_path = os.path.join(CACHE, region_name + ".rooms.json")
    npy_path = os.path.join(CACHE, region_name + ".rooms.npy")
    if not (os.path.exists(json_path) and os.path.exists(npy_path)):
        return None
    rooms = json.load(open(json_path))
    owner = np.load(npy_path)
    grid = navgrid.load(region_name)
    if len(owner) != len(grid):
        return None
    frame = raster_frame(region)
    world_x = grid.bmin[0] + (grid.x + 0.5) * grid.cell
    world_y = -(grid.bmin[2] + (grid.z + 0.5) * grid.cell)
    height = grid.bmin[1] + grid.y * grid.cell_height
    px, py, inside = pixels(region, frame, world_x, world_y)
    keep = (owner >= 0) & inside
    order = np.argsort(height[keep])
    hx, hy, ho = px[keep][order], py[keep][order], owner[keep][order]
    ids = np.full((frame[5], frame[4]), -1, np.int64)
    ids[hy, hx] = ho
    # Pixels no floor cell fell on (the grids do not line up) take a
    # neighbour's region, so only real edges are drawn.
    for shift in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        empty = ids < 0
        ids[empty] = np.roll(ids, shift, axis=(0, 1))[empty]
    inside = ids >= 0
    edge = np.zeros(ids.shape, bool)
    edge[:, 1:] |= (ids[:, 1:] != ids[:, :-1]) & inside[:, 1:] & inside[:, :-1]
    edge[1:, :] |= (ids[1:, :] != ids[:-1, :]) & inside[1:, :] & inside[:-1, :]
    colours = room_colours(rooms)
    rgba = np.zeros(ids.shape + (4,), np.uint8)
    rgba[inside, :3] = colours[ids[inside]]
    rgba[inside, 3] = 200
    rgba[edge] = (20, 20, 20, 230)
    lookup = np.zeros(ids.shape + (3,), np.uint8)
    code = ids + 1
    lookup[..., 0], lookup[..., 1], lookup[..., 2] = code >> 16, (code >> 8) & 255, code & 255
    return {"image": png(Image.fromarray(rgba, "RGBA")), "ids": png(Image.fromarray(lookup, "RGB")),
            "regions": rooms["regions"], "doors": rooms["doors"], "frame": frame}


PLACE_POINT = re.compile(r"\{\s*at\s*=\s*\{\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\}(.*?)\}\s*,?\s*(?:--\s*(.*))?$", re.M)
PLACE_CONNECTION = re.compile(r"\{\s*(\d+)\s*,\s*(\d+)\s*(,\s*true)?\s*\}")


def read_place(path):
    """Points and connections of a place written as guide source."""
    text = open(path, encoding="ascii", errors="replace").read()
    head, _, tail = text.partition("connections")
    points = []
    for match in PLACE_POINT.finditer(head):
        extra = match.group(3) or ""
        ident = re.search(r'id\s*=\s*"([^"]+)"', extra)
        kind = re.search(r'kind\s*=\s*"([^"]+)"', extra)
        points.append({"at": [float(match.group(1)), float(match.group(2))],
                       "label": (ident.group(1) if ident else "") + (" " + kind.group(1) if kind else ""),
                       "note": (match.group(4) or "").strip()})
    connections = [[int(a) - 1, int(b) - 1, bool(one)] for a, b, one in PLACE_CONNECTION.findall(tail)]
    return {"name": os.path.basename(path), "points": points, "connections": connections}


VIEWER = os.path.join(CACHE, "viewer")
METHODS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "methods")


def method_overlays(region_name):
    """Other ways of pathing the place, from methods/: each writes
    .cache/<region>.method.<id>.json, drawn as its own layers, and may give
    methods/<id>.js, a router the page runs for the route test.

    The data file: {"name", "colour", "stats": [text], "data": anything the
    router wants, "layers": [{"name", "on", "note", "shapes": [shape]}]},
    where a shape is one of {"poly": [[x, y], ...]} (a ring),
    {"rings": [ring, ...]} (a polygon with holes, even-odd), {"line":
    [[x, y], ...]} or {"dot": [x, y], "r"}, in map %, each with optional
    "stroke", "fill", "width", "dash", "opacity" and "tip" (hover text).

    The router: methods/<id>.js calls
    NuuRoadViewer.method("<id>", { route(data, start, target, ctx) }),
    where start and target are map % [x, y] as the game gives them (no
    height), and returns {points: [[x, y], ...] from start to target,
    note} or null. ctx.yd(a, b) is the yards between two map points."""
    out = []
    prefix = region_name + ".method."
    for name in sorted(os.listdir(CACHE)):
        if name.startswith(prefix) and name.endswith(".json"):
            method = json.load(open(os.path.join(CACHE, name)))
            method["id"] = name[len(prefix):-len(".json")]
            out.append(method)
    return out


def bench_cases(region_name):
    """bench.py's trips for the route test, if it has been run."""
    path = os.path.join(CACHE, region_name + ".bench.json")
    if not os.path.exists(path):
        return None
    bench = json.load(open(path))
    for case in bench["cases"]:
        for end in ("from", "to"):
            case[end] = {"at": case[end]["at"], "h": case[end]["world"][2]}
    return bench


def main():
    args = sys.argv[1:]
    region_name = args.pop(0) if args and args[0] in regions.REGIONS else "undercity"
    region = regions.REGIONS[region_name]
    storage = Storage()
    art = png(wowfiles.world_map_image(storage, maps.get(region["map"], storage)))
    graph_path = os.path.join(CACHE, region_name + ".graph.json")
    graph = json.load(open(graph_path)) if os.path.exists(graph_path) else None
    walkable = walkable_layer(region_name, region, graph)
    places = [read_place(path) for path in args]
    scene = scene_layer(region_name, region, graph)
    rooms = rooms_layer(region_name, region)
    plan = plan_layer(region_name, region, graph)
    minimap = minimap_layer(storage, region)
    title = "%s (map %d)" % (regions.name(region), region["map"])
    if region.get("title"):
        title = "%s (%s, map %d)" % (region["title"], regions.name(region), region["map"])
    b = maps.get(region["map"])
    yards = [abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100]
    data = {"title": title, "art": art, "yards": yards, "methods": method_overlays(region_name), "bench": bench_cases(region_name), "walkable": walkable, "graph": graph, "rooms": rooms, "plan": plan, "minimap": minimap, "places": places,
            "crop": list(region.get("crop") or (0, 0, 100, 100)), "w": MAP_W, "h": MAP_H, "scene": scene}
    # One page for every region built so far; each region's data is a script
    # beside it, loaded when picked (a page opened from disk may load scripts,
    # not fetch files).
    os.makedirs(os.path.join(VIEWER, "data"), exist_ok=True)
    with open(os.path.join(VIEWER, "data", region_name + ".js"), "w", encoding="ascii") as handle:
        handle.write("NuuRoadViewer.load(" + json.dumps(data) + ");\n")
    # The textured geometry is big: its own file, loaded when switched on.
    geometry = geometry_data(storage, region_name, region)
    if geometry:
        with open(os.path.join(VIEWER, "data", region_name + ".geo.js"), "w", encoding="ascii") as handle:
            handle.write("NuuRoadViewer.geometry(" + json.dumps(geometry) + ");\n")
    manifest_path = os.path.join(VIEWER, "regions.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    manifest[region_name] = title
    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    listing = [{"name": name, "title": manifest[name]} for name in sorted(manifest)]
    # Routers of the methods, beside the page.
    scripts = []
    if os.path.isdir(METHODS):
        os.makedirs(os.path.join(VIEWER, "methods"), exist_ok=True)
        for name in sorted(os.listdir(METHODS)):
            if name.endswith(".js"):
                with open(os.path.join(METHODS, name), encoding="ascii") as source:
                    text = source.read()
                with open(os.path.join(VIEWER, "methods", name), "w", encoding="ascii") as handle:
                    handle.write(text)
                scripts.append("methods/" + name)
    out = os.path.join(VIEWER, "index.html")
    with open(out, "w", encoding="ascii") as handle:
        handle.write(PAGE.replace("/*REGIONS*/[]", json.dumps(listing)).replace("/*METHODS*/[]", json.dumps(scripts)))
    print(out)
    if out.startswith("/mnt/"):
        print(out[5].upper() + ":\\" + out[7:].replace("/", "\\"))


PAGE = r"""<!doctype html>
<html><head><meta charset="ascii"><title>Place viewer</title>
<style>
:root { --bg: #16181c; --panel: #202329; --text: #e4e6ea; --muted: #9aa0aa; --line: #333842; }
@media (prefers-color-scheme: light) { :root { --bg: #f3f4f6; --panel: #ffffff; --text: #1d2026; --muted: #5d6470; --line: #d5d9e0; } }
html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text); font: 13px/1.4 system-ui, sans-serif; }
#app { display: flex; height: 100%; }
#side { width: 250px; padding: 12px; background: var(--panel); border-right: 1px solid var(--line); overflow: auto; box-sizing: border-box; }
#side h1 { font-size: 15px; margin: 0 0 8px; }
#pick { width: 100%; margin-bottom: 8px; padding: 5px; background: var(--bg); color: var(--text); border: 1px solid var(--line); border-radius: 4px; font: inherit; }
#side label { display: block; margin: 3px 0; cursor: pointer; }
#side .muted { color: var(--muted); font-size: 12px; }
#side .section { margin-top: 12px; padding-top: 8px; border-top: 1px solid var(--line); }
#view { flex: 1; position: relative; overflow: hidden; background: #0b0c0e; }
svg { width: 100%; height: 100%; cursor: grab; display: block; }
svg.dragging { cursor: grabbing; }
#readout { position: absolute; left: 10px; bottom: 10px; background: rgba(0,0,0,.7); color: #fff; padding: 4px 8px; border-radius: 4px; font: 12px monospace; pointer-events: none; }
#tip { position: absolute; background: rgba(0,0,0,.85); color: #fff; padding: 5px 8px; border-radius: 4px; font: 12px monospace; pointer-events: none; display: none; white-space: pre; }
#tabs { display: flex; gap: 4px; margin-bottom: 10px; }
#tabs button { flex: 1; padding: 5px; border: 1px solid var(--line); background: transparent; color: var(--text); border-radius: 4px; cursor: pointer; font: inherit; }
#tabs button.on { background: #3b6fd8; border-color: #3b6fd8; color: #fff; }
canvas { width: 100%; height: 100%; display: block; cursor: grab; }
button.rt { flex: 1; padding: 4px; border: 1px solid var(--line); background: transparent; color: var(--text); border-radius: 4px; cursor: pointer; font: inherit; }
button.rt.on { background: #3b6fd8; border-color: #3b6fd8; color: #fff; }
.swatch { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 4px; vertical-align: middle; }
@media (max-width: 700px) { #app { flex-direction: column; } #side { width: 100%; max-height: 40%; } }
</style></head>
<body><div id="app"><div id="side"><select id="pick" title="Region"></select><h1 id="title"></h1>
<div id="tabs"><button id="tab2d" class="on">Map</button><button id="tab3d">3D</button></div>
<div id="side2d"><div id="layers"></div>
<div class="section" id="routetest" style="display:none"><b>Route test</b>
<div class="muted">Pick a trip, or set a start and a target on the map (map % only, as the game gives them). Every method with a router draws its route; dashed white is the true shortest walk.</div>
<select id="trip" style="width:100%;margin:6px 0;padding:4px;background:var(--bg);color:var(--text);border:1px solid var(--line);border-radius:4px"></select>
<div style="display:flex;gap:4px"><button id="setstart" class="rt">Set start</button><button id="settarget" class="rt">Set target</button><button id="clearroute" class="rt">Clear</button></div>
<div id="routes" style="margin-top:6px;font:12px monospace;white-space:pre-wrap"></div></div>
<div class="section muted">Wheel or Q/E to zoom, drag or W/A/S/D to pan (Shift: faster), hover a point for its number and position. Map % as the game gives them.</div></div>
<div id="side3d" style="display:none"><div id="layers3d"></div>
<div class="section"><label>Height x <span id="exv">1.5</span><input id="ex" type="range" min="1" max="4" step="0.5" value="1.5" style="width:100%"></label>
<label>Cut away above <span id="cutv">all</span><input id="cut" type="range" min="0" max="1000" step="1" value="1000" style="width:100%"></label>
<button id="topview" style="width:100%;margin-top:6px;padding:5px;border:1px solid var(--line);background:transparent;color:var(--text);border-radius:4px;cursor:pointer">Top view</button></div>
<div class="section muted">Fly like a character with no gravity: W/S forward and back where you look, A/D step sideways, Q/E turn, Space/R up, X/F down, Shift faster. Drag to look round; the wheel sets the speed. Floors coloured by height; hover a point of the place for its number.</div></div>
<div class="section muted" id="stats"></div></div>
<div id="view"><svg id="svg" xmlns="http://www.w3.org/2000/svg"></svg><canvas id="gl" style="display:none"></canvas><div id="readout"></div><div id="tip"></div></div></div>
<script>
// Which region, which tab and which layers: kept in the address,
// "#region=orgrimmar&3d&rooms", so a reload or a link comes back to them.
const REGIONS = /*REGIONS*/[];
const HASH = new Set(location.hash.slice(1).split("&").filter(Boolean));
const CURRENT = ([...HASH].find(t => t.startsWith("region=")) || "").slice(7) || (REGIONS[0] || {}).name;
function setHash(token, on) {
  if (on) HASH.add(token); else HASH.delete(token);
  history.replaceState(null, "", "#" + [...HASH].join("&"));
}
const pick = document.getElementById("pick");
for (const r of REGIONS) { const o = document.createElement("option"); o.value = r.name; o.textContent = r.title; o.selected = r.name === CURRENT; pick.appendChild(o); }
pick.onchange = () => { for (const t of [...HASH]) if (t.startsWith("region=")) HASH.delete(t); setHash("region=" + pick.value, true); location.reload(); };
// Routers of the other ways of pathing a place (methods/*.js) load first,
// then the region's data.
const METHOD_SCRIPTS = /*METHODS*/[];
const ROUTERS = {};
window.NuuRoadViewer = { load: data => start(data), method: (id, router) => { ROUTERS[id] = router; } };
function loadScript(src) { return new Promise(done => { const tag = document.createElement("script"); tag.src = src;
  tag.onload = () => done(true); tag.onerror = () => done(false); document.body.appendChild(tag); }); }
if (CURRENT) Promise.all(METHOD_SCRIPTS.map(loadScript)).then(() => loadScript("data/" + CURRENT + ".js")).then(ok => {
  if (!ok) document.getElementById("title").textContent = "No data for " + CURRENT + ": run view.py " + CURRENT; });

function start(D) {
const NS = "http://www.w3.org/2000/svg";
const svg = document.getElementById("svg"), tip = document.getElementById("tip");
document.getElementById("title").textContent = D.title;
const X = x => x * D.w / 100, Y = y => y * D.h / 100;
function el(tag, attrs, parent) { const e = document.createElementNS(NS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); (parent || svg).appendChild(e); return e; }
const layers = [];
function layer(name, on, note) { const g = el("g", {}); g.style.display = on ? "" : "none"; layers.push({ name, g, on, note }); return g; }

const stats = [];
// Map art and the walkable area.
const base = layer("World map", true);
el("image", { href: D.art, x: 0, y: 0, width: D.w, height: D.h }, base);
if (D.minimap) {
  const g = layer("Minimap (the game's own tiles, textured)", false, "ground and buildings from above, as the game's minimap draws them");
  const f = D.minimap.frame;
  el("image", { href: D.minimap.image, x: X(f[0]), y: Y(f[1]), width: X(f[2]) - X(f[0]), height: Y(f[3]) - Y(f[1]), preserveAspectRatio: "none" }, g);
}
if (D.plan) {
  const g = layer("Floor plan (from the map's geometry)", true, "floors shaded by height (" + D.plan.low + " to " + D.plan.high + " yd), dark: walls and what stands on the floor, blue: water");
  const f = D.plan.frame;
  el("image", { href: D.plan.image, x: X(f[0]), y: Y(f[1]), width: X(f[2]) - X(f[0]), height: Y(f[3]) - Y(f[1]), preserveAspectRatio: "none" }, g);
}
if (D.walkable) {
  const w = layer("Walkable (by height)", !D.plan, "blue low, yellow high: " + D.walkable.low + " to " + D.walkable.high + " yd; grey: walkable but not part of the place (roofs, closed rooms)");
  const f = D.walkable.frame;
  el("image", { href: D.walkable.image, x: X(f[0]), y: Y(f[1]), width: X(f[2]) - X(f[0]), height: Y(f[3]) - Y(f[1]), preserveAspectRatio: "none", style: "image-rendering: pixelated" }, w);
}
// Rooms, halls, corridors, stairs and crossings.
let roomIds = null;
if (D.rooms) {
  const R = D.rooms;
  const g = layer("Rooms", false, "green room, blue hall, orange corridor or street, pink stairs or ramp, yellow crossing, teal water; black ticks: doorways. Hover a region for what it is.");
  const f = R.frame;
  el("image", { href: R.image, x: X(f[0]), y: Y(f[1]), width: X(f[2]) - X(f[0]), height: Y(f[3]) - Y(f[1]), preserveAspectRatio: "none", style: "image-rendering: pixelated" }, g);
  for (const d of R.doors) el("circle", { cx: X(d.at[0]), cy: Y(d.at[1]), r: 1.6, fill: "#111", stroke: "#fff", "stroke-width": .6, "vector-effect": "non-scaling-stroke" }, g);
  const img = new Image();
  img.onload = () => { const c = document.createElement("canvas"); c.width = img.width; c.height = img.height;
    const ctx = c.getContext("2d"); ctx.drawImage(img, 0, 0); roomIds = { data: ctx.getImageData(0, 0, c.width, c.height).data, w: c.width, h: c.height, g }; };
  img.src = R.ids;
  const k = {}; for (const r of R.regions) k[r.kind] = (k[r.kind] || 0) + 1;
  stats.push("Rooms: " + R.regions.length + " regions (" + Object.entries(k).map(e => e[1] + " " + e[0]).join(", ") + "), " + R.doors.length + " doorways");
}
function roomAt(mx, my) {
  if (!roomIds || roomIds.g.style.display === "none") return null;
  const f = D.rooms.frame;
  const x = Math.floor((mx * 100 / D.w - f[0]) / (f[2] - f[0]) * f[4]), y = Math.floor((my * 100 / D.h - f[1]) / (f[3] - f[1]) * f[5]);
  if (x < 0 || y < 0 || x >= roomIds.w || y >= roomIds.h) return null;
  const i = (y * roomIds.w + x) * 4, id = (roomIds.data[i] << 16) + (roomIds.data[i + 1] << 8) + roomIds.data[i + 2] - 1;
  return id >= 0 ? D.rooms.regions[id] : null;
}
// Centre lines.
if (D.graph) {
  const c = layer("Centre lines", false);
  for (const p of D.graph.centre) el("rect", { x: X(p[0]) - .25, y: Y(p[1]) - .25, width: .5, height: .5, fill: "#ff5ad7" }, c);
}
// Places: the computed one and any given.
const kindColour = { junction: "#ff3b3b", end: "#ffd000", bend: "#4ad1ff", entrance: "#3ddc84" };
function drawPlace(name, points, connections, colour, info) {
  const g = layer(name, true);
  for (const c of connections) {
    const a = points[c[0]], b = points[c[1]];
    if (!a || !b) continue;
    el("line", { x1: X(a.at[0]), y1: Y(a.at[1]), x2: X(b.at[0]), y2: Y(b.at[1]), stroke: colour, "stroke-width": 2, "vector-effect": "non-scaling-stroke", "marker-end": c[2] ? "url(#arrow)" : "" }, g);
  }
  points.forEach((p, i) => {
    const dot = el("circle", { cx: X(p.at[0]), cy: Y(p.at[1]), r: 2.2, fill: kindColour[p.kind] || colour, stroke: "#000", "stroke-width": .6, "vector-effect": "non-scaling-stroke" }, g);
    dot.addEventListener("mousemove", ev => { tip.textContent = "#" + (i + 1) + "  " + p.at[0].toFixed(2) + ", " + p.at[1].toFixed(2) + "\n" + info(p); tip.style.display = "block"; tip.style.left = (ev.offsetX + 14) + "px"; tip.style.top = (ev.offsetY + 14) + "px"; });
    dot.addEventListener("mouseleave", () => { tip.style.display = "none"; });
  });
}
const defs = el("defs", {});
const marker = el("marker", { id: "arrow", viewBox: "0 0 10 10", refX: 10, refY: 5, markerWidth: 6, markerHeight: 6, orient: "auto" }, defs);
el("path", { d: "M0,0 L10,5 L0,10 z", fill: "#ff4040" }, marker);
if (D.graph) {
  drawPlace("Computed place", D.graph.points, D.graph.connections, "#ff3b3b", p => p.kind + ", height " + p.world[2].toFixed(0) + " yd, clearance " + p.clearance + " yd");
  // Lifts (a top and a bottom in the same spot) and ways out.
  const ch = layer("Lifts and ways out", true, "purple rings: lift ends; green: a way out");
  for (const c of D.graph.lifts || []) for (const i of c) { const p = D.graph.points[i];
    el("circle", { cx: X(p.at[0]), cy: Y(p.at[1]), r: 5, fill: "none", stroke: "#d06bff", "stroke-width": 2.5, "vector-effect": "non-scaling-stroke" }, ch); }
  for (const i of D.graph.exits || []) { const p = D.graph.points[i];
    el("circle", { cx: X(p.at[0]), cy: Y(p.at[1]), r: 5, fill: "none", stroke: "#3ddc84", "stroke-width": 2.5, "vector-effect": "non-scaling-stroke" }, ch); }
  const k = {}; for (const p of D.graph.points) k[p.kind] = (k[p.kind] || 0) + 1;
  stats.push("Computed: " + D.graph.points.length + " points (" + Object.entries(k).map(e => e[1] + " " + e[0]).join(", ") + "), " + D.graph.connections.length + " connections, " + (D.graph.lifts || []).length + " lifts");
}
const placeColours = ["#ffffff", "#b388ff", "#69f0ae"];
D.places.forEach((p, i) => {
  drawPlace(p.name, p.points, p.connections, placeColours[i % placeColours.length], q => (q.label || "") + (q.note ? "  " + q.note : ""));
  stats.push(p.name + ": " + p.points.length + " points, " + p.connections.length + " connections");
});
// Other ways of pathing the place (methods/): their layers, and a route layer each.
function hover(e, text) {
  e.dataset.tip = "1";
  e.addEventListener("mousemove", ev => { tip.textContent = text; tip.style.display = "block"; tip.style.left = (ev.offsetX + 14) + "px"; tip.style.top = (ev.offsetY + 14) + "px"; });
  e.addEventListener("mouseleave", () => { tip.style.display = "none"; });
}
const pts = ring => ring.map(p => X(p[0]) + "," + Y(p[1])).join(" ");
function drawShape(s, g) {
  const style = { stroke: s.stroke || "#fff", "stroke-width": s.width || 1.5, "vector-effect": "non-scaling-stroke", fill: s.fill || "none" };
  let e;
  if (s.poly) e = el("polygon", Object.assign({ points: pts(s.poly) }, style), g);
  else if (s.rings) e = el("path", Object.assign({ d: s.rings.map(r => "M" + pts(r) + "Z").join(" "), "fill-rule": "evenodd" }, style), g);
  else if (s.line) e = el("polyline", Object.assign({}, style, { points: pts(s.line), fill: "none" }), g);
  else if (s.dot) e = el("circle", { cx: X(s.dot[0]), cy: Y(s.dot[1]), r: s.r || 1.6, fill: s.fill || s.stroke || "#fff", stroke: "#000", "stroke-width": .6, "vector-effect": "non-scaling-stroke" }, g);
  if (!e) return;
  if (s.dash) e.setAttribute("stroke-dasharray", s.dash);
  if (s.opacity) e.setAttribute("opacity", s.opacity);
  if (s.tip) hover(e, s.tip);
}
const yd = (a, b) => Math.hypot((a[0] - b[0]) * D.yards[0], (a[1] - b[1]) * D.yards[1]);
const routers = [];
if (D.graph) {
  // Today's place (skeleton.py) as the planner uses it: join the connection
  // nearest the player within 20 yd at both its ends, Dijkstra to the target's.
  routers.push({ m: { id: "current", name: "Current place", colour: "#ff3b3b", data: D.graph }, r: { route: routeCurrent } });
}
for (const m of D.methods || []) {
  for (const L of m.layers || []) {
    const g = layer(m.name + ": " + L.name, !!L.on, L.note);
    for (const s of L.shapes || []) drawShape(s, g);
  }
  for (const s of m.stats || []) stats.push(m.name + ": " + s);
  if (ROUTERS[m.id]) routers.push({ m, r: ROUTERS[m.id] });
}
function routeCurrent(G, start, target) {
  const P = G.points.map(p => p.at), C = G.connections;
  function attach(q) {
    let best = null;
    C.forEach((c, i) => { const a = P[c[0]], b = P[c[1]];
      const dx = b[0] - a[0], dy = b[1] - a[1], L = dx * dx + dy * dy;
      const t = L ? Math.max(0, Math.min(1, ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / L)) : 0;
      const f = [a[0] + t * dx, a[1] + t * dy], d = yd(q, f);
      if (d <= 20 && (!best || d < best.d)) best = { i, f, d }; });
    return best;
  }
  const s = attach(start), t = attach(target);
  if (!s || !t) return null;
  const n = P.length, adj = Array.from({ length: n + 2 }, () => []);
  for (const c of C) { const w = yd(P[c[0]], P[c[1]]); adj[c[0]].push([c[1], w]); if (!c[2]) adj[c[1]].push([c[0], w]); }
  const S = n, T = n + 1, where = [start, target];
  for (const [k, e] of [[S, s], [T, t]]) { const c = C[e.i];
    for (const end of [c[0], c[1]]) { const w = e.d + yd(e.f, P[end]); if (k === S) adj[S].push([end, w]); else adj[end].push([T, w]); } }
  if (s.i === t.i) adj[S].push([T, yd(start, target)]);
  const dist = new Array(n + 2).fill(Infinity), prev = new Array(n + 2).fill(-1), done = new Array(n + 2).fill(false);
  dist[S] = 0;
  for (;;) { let u = -1; for (let i = 0; i < n + 2; i++) if (!done[i] && dist[i] < Infinity && (u < 0 || dist[i] < dist[u])) u = i;
    if (u < 0 || u === T) break; done[u] = true;
    for (const [v, w] of adj[u]) if (dist[u] + w < dist[v]) { dist[v] = dist[u] + w; prev[v] = u; } }
  if (dist[T] === Infinity) return null;
  const path = []; for (let u = prev[T]; u !== S && u >= 0; u = prev[u]) path.unshift(P[u]);
  return { points: [start, ...path, target], note: G.points.length + " points" };
}
// The route test.
const routeLayer = layer("Route test", true, "green: start, red: target; each method's route in its colour, dashed white: the true shortest walk");
let routeStart = null, routeTarget = null, routeTruth = null, picking = null;
for (const t of HASH) { const m = t.match(/^(from|to)=([-\d.]+),([-\d.]+)$/); if (m) { const p = [+m[2], +m[3]]; if (m[1] === "from") routeStart = p; else routeTarget = p; } }
function runRoutes() {
  while (routeLayer.firstChild) routeLayer.removeChild(routeLayer.firstChild);
  const lines = [];
  if (routeTruth) { el("polyline", { points: pts(routeTruth.path), fill: "none", stroke: "#fff", "stroke-width": 2, "stroke-dasharray": "4 3", "vector-effect": "non-scaling-stroke" }, routeLayer);
    lines.push("truth " + routeTruth.truth2d + " yd (" + routeTruth.kind + ")"); }
  if (routeStart && routeTarget) for (const { m, r } of routers) {
    const t0 = performance.now(); let res = null, err = null;
    try { res = r.route(m.data, routeStart, routeTarget, { yd, yards: D.yards }); } catch (e) { err = e.message; }
    const ms = performance.now() - t0;
    if (!res || !res.points) { lines.push(m.name + ": " + (err ? "error " + err : "no route")); continue; }
    const colour = m.colour || "#ffd000";
    el("polyline", { points: pts(res.points), fill: "none", stroke: colour, "stroke-width": 3, opacity: .9, "vector-effect": "non-scaling-stroke", "stroke-linejoin": "round" }, routeLayer);
    // The arrow: from the start toward the first point it would show.
    if (res.points.length > 1) el("line", { x1: X(res.points[0][0]), y1: Y(res.points[0][1]), x2: X(res.points[1][0]), y2: Y(res.points[1][1]), stroke: colour, "stroke-width": 5, "vector-effect": "non-scaling-stroke", "marker-end": "url(#arrow)" }, routeLayer);
    for (const p of res.points.slice(1, -1)) el("circle", { cx: X(p[0]), cy: Y(p[1]), r: 1.3, fill: colour, stroke: "#000", "stroke-width": .5, "vector-effect": "non-scaling-stroke" }, routeLayer);
    let L = 0; for (let i = 1; i < res.points.length; i++) L += yd(res.points[i - 1], res.points[i]);
    lines.push(m.name + ": " + L.toFixed(1) + " yd" + (routeTruth ? " (x" + (L / routeTruth.truth2d).toFixed(2) + ")" : "") + ", " + (res.points.length - 2) + " bends, " + ms.toFixed(1) + " ms" + (res.note ? "\n  " + res.note : ""));
  }
  for (const [p, c] of [[routeStart, "#3ddc84"], [routeTarget, "#ff4040"]]) if (p) el("circle", { cx: X(p[0]), cy: Y(p[1]), r: 3, fill: c, stroke: "#000", "stroke-width": 1, "vector-effect": "non-scaling-stroke" }, routeLayer);
  document.getElementById("routes").textContent = lines.join("\n");
  apply();
}
function setRoutePoint(which, p) {
  if (which === "start") routeStart = p; else routeTarget = p;
  routeTruth = null; document.getElementById("trip").value = "";
  for (const t of [...HASH]) if (t.startsWith(which === "start" ? "from=" : "to=")) HASH.delete(t);
  setHash((which === "start" ? "from=" : "to=") + p[0].toFixed(3) + "," + p[1].toFixed(3), true);
  runRoutes();
}
document.getElementById("routetest").style.display = "";
const trip = document.getElementById("trip");
trip.innerHTML = "<option value=''>" + (D.bench ? "Trips (bench.py): " + D.bench.cases.length : "No trips: run bench.py") + "</option>" +
  (D.bench ? D.bench.cases.map((c, i) => "<option value='" + i + "'>" + c.id + ": " + c.truth2d + " yd, " + c.from.h.toFixed(0) + " to " + c.to.h.toFixed(0) + " high</option>").join("") : "");
trip.onchange = () => { if (trip.value === "") return; const c = D.bench.cases[+trip.value];
  routeStart = c.from.at; routeTarget = c.to.at; routeTruth = c; runRoutes(); };
for (const [id, which] of [["setstart", "start"], ["settarget", "target"]]) document.getElementById(id).onclick = () => {
  picking = picking === which ? null : which;
  document.getElementById("setstart").classList.toggle("on", picking === "start");
  document.getElementById("settarget").classList.toggle("on", picking === "target"); };
document.getElementById("clearroute").onclick = () => { routeStart = routeTarget = routeTruth = null; trip.value = "";
  for (const t of [...HASH]) if (/^(from|to)=/.test(t)) HASH.delete(t); setHash("x", false); runRoutes(); };
setTimeout(runRoutes, 0);
document.getElementById("stats").innerHTML = stats.map(s => "<div>" + s + "</div>").join("");

// Layer switches.
const box = document.getElementById("layers");
for (const l of layers) {
  const label = document.createElement("label");
  const input = document.createElement("input"); input.type = "checkbox"; input.checked = l.on;
  input.onchange = () => { l.g.style.display = input.checked ? "" : "none"; };
  if (HASH.has("rooms") && l.name !== "World map") { const want = l.name === "Rooms"; l.on = input.checked = want; l.g.style.display = want ? "" : "none"; }
  label.appendChild(input); label.appendChild(document.createTextNode(" " + l.name));
  box.appendChild(label);
  if (l.note) { const n = document.createElement("div"); n.className = "muted"; n.textContent = l.note; box.appendChild(n); }
}

// Pan and zoom.
let vb = { x: X(D.crop[0]), y: Y(D.crop[1]), w: X(D.crop[2]) - X(D.crop[0]), h: Y(D.crop[3]) - Y(D.crop[1]) };
function apply() {
  svg.setAttribute("viewBox", vb.x + " " + vb.y + " " + vb.w + " " + vb.h);
  // Points keep their size on screen at any zoom.
  const k = vb.w / Math.max(1, svg.clientWidth || 1000) * 1.6;
  for (const c of svg.querySelectorAll("circle")) {
    if (!c.dataset.r) c.dataset.r = c.getAttribute("r");
    c.setAttribute("r", c.dataset.r * k);
  }
}
apply();
function toMap(ev) { const r = svg.getBoundingClientRect(); const s = Math.max(vb.w / r.width, vb.h / r.height);
  const ox = vb.x + (vb.w - r.width * s) / 2, oy = vb.y + (vb.h - r.height * s) / 2;
  return { x: ox + (ev.clientX - r.left) * s, y: oy + (ev.clientY - r.top) * s }; }
svg.addEventListener("wheel", ev => { ev.preventDefault(); const p = toMap(ev); const f = ev.deltaY < 0 ? 0.8 : 1.25;
  vb = { x: p.x - (p.x - vb.x) * f, y: p.y - (p.y - vb.y) * f, w: vb.w * f, h: vb.h * f }; apply(); }, { passive: false });
let drag = null;
svg.addEventListener("mousedown", ev => { drag = { p: toMap(ev), sx: ev.clientX, sy: ev.clientY }; svg.classList.add("dragging"); });
svg.addEventListener("mouseup", ev => {
  if (!picking || !drag || Math.hypot(ev.clientX - drag.sx, ev.clientY - drag.sy) > 4) return;
  const p = toMap(ev); setRoutePoint(picking, [p.x * 100 / D.w, p.y * 100 / D.h]);
  picking = null; for (const id of ["setstart", "settarget"]) document.getElementById(id).classList.remove("on"); });
window.addEventListener("mouseup", () => { drag = null; svg.classList.remove("dragging"); });
svg.addEventListener("mousemove", ev => { const p = toMap(ev);
  document.getElementById("readout").textContent = (p.x * 100 / D.w).toFixed(2) + ", " + (p.y * 100 / D.h).toFixed(2);
  if (!drag && ev.target.tagName !== "circle" && !ev.target.dataset.tip) { const r = roomAt(p.x, p.y);
    if (r) { tip.textContent = r.kind + " #" + r.id + "\n" + r.area + " sq yd, " + r.width + " yd wide (" + r.widest + " at most), " + r.length + " yd long\nfloor " + r.low + " to " + r.high + " yd, " + r.doors + " doorways, " + r.neighbours.length + " neighbours";
      tip.style.display = "block"; tip.style.left = (ev.offsetX + 14) + "px"; tip.style.top = (ev.offsetY + 14) + "px"; }
    else tip.style.display = "none"; }
  if (drag) { vb.x -= p.x - drag.p.x; vb.y -= p.y - drag.p.y; apply(); } });

// ---- Keys ------------------------------------------------------------------
// WASD moves whichever view is showing (see keys3d and keys2d); held keys
// move smoothly, frame by frame, until let go.
let keys3d = null;
const held = new Set();
let lastFrame = 0;
function keyFrame(time) {
  if (!held.size || held.size === 1 && held.has("shift")) { lastFrame = 0; return; }
  const dt = lastFrame ? Math.min(0.05, (time - lastFrame) / 1000) : 0.016;
  lastFrame = time;
  if (canvas.style.display !== "none") { if (keys3d) keys3d(held, dt); } else keys2d(held, dt);
  requestAnimationFrame(keyFrame);
}
window.addEventListener("keydown", ev => {
  if (["INPUT", "SELECT", "TEXTAREA"].includes(ev.target.tagName) || ev.ctrlKey || ev.metaKey || ev.altKey) return;
  const key = ev.key.toLowerCase();
  if (key === "shift") { held.add("shift"); return; }
  if (!"wasdqerfx ".includes(key) || key.length !== 1) return;
  ev.preventDefault();
  const idle = !held.size || held.size === 1 && held.has("shift");
  held.add(key);
  if (idle) requestAnimationFrame(keyFrame);
});
window.addEventListener("keyup", ev => held.delete(ev.key.toLowerCase()));
window.addEventListener("blur", () => held.clear());
function keys2d(held, dt) {
  const step = (held.has("shift") ? 3 : 1) * dt;
  if (held.has("w")) vb.y -= vb.h * 0.8 * step;
  if (held.has("s")) vb.y += vb.h * 0.8 * step;
  if (held.has("a")) vb.x -= vb.w * 0.8 * step;
  if (held.has("d")) vb.x += vb.w * 0.8 * step;
  for (const [key, grow] of [["q", 1 + 1.5 * step], ["e", 1 / (1 + 1.5 * step)]]) {
    if (!held.has(key)) continue;
    const cx = vb.x + vb.w / 2, cy = vb.y + vb.h / 2;
    vb = { x: cx - vb.w * grow / 2, y: cy - vb.h * grow / 2, w: vb.w * grow, h: vb.h * grow };
  }
  apply();
}

// ---- 3D ------------------------------------------------------------------
const canvas = document.getElementById("gl");
let started3d = false;
function showTab(three) {
  document.getElementById("tab2d").classList.toggle("on", !three);
  document.getElementById("tab3d").classList.toggle("on", three);
  document.getElementById("side2d").style.display = three ? "none" : "";
  document.getElementById("side3d").style.display = three ? "" : "none";
  svg.style.display = three ? "none" : "";
  canvas.style.display = three ? "" : "none";
  tip.style.display = "none";
  setHash("3d", three);
  if (three && !started3d) { started3d = true; start3d(); }
  if (three) draw3d();
}
document.getElementById("tab2d").onclick = () => showTab(false);
document.getElementById("tab3d").onclick = () => showTab(true);
if (!D.scene) document.getElementById("tab3d").disabled = true;
setTimeout(() => { if (HASH.has("3d") && D.scene) showTab(true); }, 0);

let draw3d = () => {};
function start3d() {
  const S = D.scene;
  const gl = canvas.getContext("webgl", { antialias: true });
  if (!gl) { document.getElementById("layers3d").textContent = "This browser has no WebGL."; return; }
  gl.getExtension("OES_element_index_uint");
  const deriv = gl.getExtension("OES_standard_derivatives");
  const bytes = b64 => { const s = atob(b64), a = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) a[i] = s.charCodeAt(i); return a.buffer; };
  const toFloat = q => { const f = new Float32Array(q.length); for (let i = 0; i < q.length; i++) f[i] = q[i] / 4; return f; };
  const verts = toFloat(new Int16Array(bytes(S.vertices)));
  const tris = new Uint32Array(bytes(S.triangles));
  const rest = toFloat(new Int16Array(bytes(S.rest)));
  const ramp = `vec3 ramp(float t) { t = clamp(t, 0.0, 1.0);
    vec3 a = vec3(0.16,0.24,0.78), b = vec3(0.12,0.67,0.75), c = vec3(0.31,0.78,0.35), d = vec3(0.98,0.86,0.24);
    if (t < 0.3333) return mix(a, b, t * 3.0); if (t < 0.6667) return mix(b, c, t * 3.0 - 1.0); return mix(c, d, t * 3.0 - 2.0); }`;
  function program(vs, fs) {
    const p = gl.createProgram();
    for (const [type, src] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
      const sh = gl.createShader(type); gl.shaderSource(sh, src); gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
      gl.attachShader(p, sh);
    }
    gl.linkProgram(p); return p;
  }
  const surface = program(
    `attribute vec3 p; attribute vec3 rc; uniform mat4 m; uniform float ex, lo, hi; varying vec3 w, room; varying float t;
     void main() { vec3 q = vec3(p.x, p.y * ex, p.z); w = q; room = rc; t = (p.y - lo) / (hi - lo); gl_Position = m * vec4(q, 1.0); }`,
    (deriv ? "#extension GL_OES_standard_derivatives : enable\n" : "") +
    `precision highp float; varying vec3 w, room; varying float t; uniform float byRoom; ${ramp}
     void main() { float l = 1.0;` + (deriv ? ` vec3 n = normalize(cross(dFdx(w), dFdy(w))); l = 0.5 + 0.5 * abs(dot(n, normalize(vec3(0.35, 1.0, 0.25))));` : "") +
    ` gl_FragColor = vec4(mix(ramp(t), room, byRoom) * l, 1.0); }`);
  const flat = program(
    `attribute vec3 p; attribute vec3 c; uniform mat4 m; uniform float ex, size; varying vec3 v;
     void main() { v = c; gl_Position = m * vec4(p.x, p.y * ex, p.z, 1.0); gl_PointSize = size; }`,
    `precision mediump float; varying vec3 v; void main() { gl_FragColor = vec4(v, 1.0); }`);
  const textured = program(
    `attribute vec3 p; attribute vec2 uv; uniform mat4 m; varying vec2 v; void main() { v = uv; gl_Position = m * vec4(p, 1.0); }`,
    `precision mediump float; varying vec2 v; uniform sampler2D tex; void main() { gl_FragColor = vec4(texture2D(tex, v).rgb * 0.85, 1.0); }`);
  function buffer(data, target) { const b = gl.createBuffer(); gl.bindBuffer(target || gl.ARRAY_BUFFER, b); gl.bufferData(target || gl.ARRAY_BUFFER, data, gl.STATIC_DRAW); return b; }
  const surfaceBuf = buffer(verts), triBuf = buffer(tris, gl.ELEMENT_ARRAY_BUFFER);
  const roomRgb = S.rooms ? new Uint8Array(bytes(S.rooms)) : new Uint8Array(verts.length);
  const roomBuf = buffer(Float32Array.from(roomRgb, v => v / 255));
  // Coloured points and lines: position and colour interleaved.
  function colouredBuffer(items) { const a = new Float32Array(items.length * 6); items.forEach((it, i) => a.set(it, i * 6)); return { buf: buffer(a), count: items.length }; }
  const hex = h => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
  const restPts = []; for (let i = 0; i < rest.length; i += 3) restPts.push([rest[i], rest[i + 1], rest[i + 2], .45, .45, .45]);
  const restBuf = colouredBuffer(restPts);
  const lift = 0.6;  // lines float a little over the floor they run on
  const gpts = [], glines = [], gchanges = [], g3 = [];
  if (D.graph) {
    const P = D.graph.points.map(p => [S.left - p.world[1], p.world[2] + lift, S.top - p.world[0]]);
    const kc = { junction: hex("#ff3b3b"), end: hex("#ffd000"), bend: hex("#4ad1ff"), entrance: hex("#3ddc84") };
    D.graph.points.forEach((p, i) => { gpts.push([...P[i], ...(kc[p.kind] || [1, 1, 1])]); g3.push(P[i]); });
    const changes = new Set((D.graph.lifts || []).map(c => c[0] + "," + c[1]));
    for (const c of D.graph.connections) { const list = changes.has(c[0] + "," + c[1]) ? gchanges : glines;
      const col = list === gchanges ? hex("#d06bff") : [1, .25, .25]; list.push([...P[c[0]], ...col], [...P[c[1]], ...col]); }
  }
  const gptBuf = colouredBuffer(gpts), glineBuf = colouredBuffer(glines), gchangeBuf = colouredBuffer(gchanges);
  // The world map, flat under everything.
  const W = S.size[0], H = S.size[1], floorY = S.low - 8;
  // The plane covers the region's crop of the map, with that part of the art.
  const u0 = D.crop[0] / 100, v0 = D.crop[1] / 100, u1 = D.crop[2] / 100, v1 = D.crop[3] / 100;
  const quad = buffer(new Float32Array([u0 * W, 0, v0 * H, u0, v0, u1 * W, 0, v0 * H, u1, v0,
                                        u0 * W, 0, v1 * H, u0, v1, u1 * W, 0, v1 * H, u1, v1]));
  const tex = gl.createTexture(); const img = new Image();
  img.onload = () => { gl.bindTexture(gl.TEXTURE_2D, tex); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, img);
    for (const k of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, k, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); draw3d(); };
  img.src = D.art;

  // Layers.
  const on = { floors: true, byRoom: HASH.has("rooms") && !!S.rooms, rest: false, map: true, graph: true, changes: true, top: false, geometry: HASH.has("geo"), props: true };
  const names = [["geometry", "Map geometry (textured)"], ["props", "Props (collision shells, grey)"], ["floors", "Floors"], ...(S.rooms ? [["byRoom", "Colour floors by room"]] : []), ["rest", "Walkable, not in the place (grey)"], ["map", "World map"], ["graph", "Computed place"], ["changes", "Lifts"], ["top", "Place on top"]];
  const box3 = document.getElementById("layers3d");
  const boxes = {};
  for (const [key, label] of names) { const l = document.createElement("label"); const inp = document.createElement("input");
    inp.type = "checkbox"; inp.checked = on[key]; inp.onchange = () => { on[key] = inp.checked; if (key === "geometry") wantGeometry(); draw3d(); };
    boxes[key] = inp;
    l.appendChild(inp); l.appendChild(document.createTextNode(" " + label)); box3.appendChild(l); }
  const note = document.createElement("div"); note.className = "muted";
  note.textContent = "Heights " + S.low.toFixed(0) + " to " + S.high.toFixed(0) + " yd. Purple: lifts."; box3.appendChild(note);
  setTimeout(wantGeometry, 0);
  const exInput = document.getElementById("ex");
  exInput.oninput = () => { document.getElementById("exv").textContent = exInput.value; draw3d(); };

  // The map's own geometry, textured: loaded from its own file when first
  // switched on (it is big).
  let geo = null, geoLoading = false;
  const lit = deriv ? `vec3 n = normalize(cross(dFdx(w), dFdy(w))); float l = 0.55 + 0.45 * abs(dot(n, normalize(vec3(0.35, 1.0, 0.25))));` : `float l = 1.0;`;
  const head = (deriv ? "#extension GL_OES_standard_derivatives : enable\n" : "") + "precision highp float;";
  const modelProg = program(
    `attribute vec3 p; attribute vec2 uv; attribute float slot; uniform mat4 m; uniform float ex; varying vec3 w; varying vec2 t; varying float s, h;
     void main() { vec3 q = vec3(p.x, p.y * ex, p.z); w = q; t = uv; s = slot; h = p.y; gl_Position = m * vec4(q, 1.0); }`,
    head + ` varying vec3 w; varying vec2 t; varying float s, h; uniform sampler2D atlas; uniform float cells, cell, cut;
     void main() { if (h > cut) discard;
       vec2 c = vec2(mod(s, cells), floor(s / cells) + 0.0);
       vec4 col = texture2D(atlas, (c + 0.03 + fract(t) * 0.94) * cell);
       if (col.a < 0.5) discard; ${lit} gl_FragColor = vec4(col.rgb * l, 1.0); }`);
  const groundProg = program(
    `attribute vec3 p; uniform mat4 m; uniform float ex; uniform vec4 rect; varying vec3 w; varying vec2 t; varying float h;
     void main() { vec3 q = vec3(p.x, p.y * ex, p.z); w = q; h = p.y; t = (p.xz - rect.xy) / (rect.zw - rect.xy); gl_Position = m * vec4(q, 1.0); }`,
    head + ` varying vec3 w; varying vec2 t; varying float h; uniform sampler2D tex; uniform float cut;
     void main() { if (h > cut) discard; ${lit} gl_FragColor = vec4(texture2D(tex, t).rgb * l, 1.0); }`);
  const greyProg = program(
    `attribute vec3 p; uniform mat4 m; uniform float ex; varying vec3 w; varying float h;
     void main() { vec3 q = vec3(p.x, p.y * ex, p.z); w = q; h = p.y; gl_Position = m * vec4(q, 1.0); }`,
    head + ` varying vec3 w; varying float h; uniform float cut;
     void main() { if (h > cut) discard; ${lit} gl_FragColor = vec4(vec3(0.62, 0.6, 0.56) * l, 1.0); }`);
  function picture(src, repeat) {
    const t = gl.createTexture(), im = new Image();
    im.onload = () => { gl.bindTexture(gl.TEXTURE_2D, t); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, im);
      const pot = (im.width & (im.width - 1)) === 0 && (im.height & (im.height - 1)) === 0;
      for (const k of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, k, gl.CLAMP_TO_EDGE);
      if (pot) { gl.generateMipmap(gl.TEXTURE_2D); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR); }
      else gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      draw3d(); };
    im.src = src; return t;
  }
  function meshBuffers(part) {
    if (!part) return null;
    const v = new Int16Array(bytes(part.vertices)), f = new Float32Array(v.length);
    for (let i = 0; i < v.length; i++) f[i] = v[i] / 4;
    const t = new Uint32Array(bytes(part.triangles));
    return { v: buffer(f), t: buffer(t, gl.ELEMENT_ARRAY_BUFFER), count: t.length };
  }
  window.NuuRoadViewer.geometry = g => {
    geo = { ground: meshBuffers(g.ground), props: meshBuffers(g.props), low: g.low, high: g.high };
    if (g.ground && g.ground.texture) { geo.groundTex = picture(g.ground.texture); geo.rect = g.ground.rect; }
    if (g.models) {
      geo.models = meshBuffers(g.models);
      geo.uv = buffer(new Float32Array(bytes(g.models.uvs)));
      geo.slot = buffer(Float32Array.from(new Uint16Array(bytes(g.models.slots))));
      geo.atlas = picture(g.atlas); geo.cells = g.cells; geo.cell = g.cell;
    }
    // The floors would sit on the same surfaces: out of the way.
    on.floors = boxes.floors.checked = false;
    cutInput.oninput(); draw3d();
  };
  function wantGeometry() {
    if (geo || geoLoading || !on.geometry) return;
    geoLoading = true;
    const tag = document.createElement("script"); tag.src = "data/" + CURRENT + ".geo.js";
    tag.onerror = () => { boxes.geometry.parentNode.lastChild.textContent = " Map geometry: none built (run view.py)"; };
    document.body.appendChild(tag);
  }
  function drawMesh(prog, part, m, ex, extra) {
    if (!part) return;
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, part.v);
    const pl = gl.getAttribLocation(prog, "p"); gl.enableVertexAttribArray(pl); gl.vertexAttribPointer(pl, 3, gl.FLOAT, false, 12, 0);
    gl.uniformMatrix4fv(gl.getUniformLocation(prog, "m"), false, m);
    gl.uniform1f(gl.getUniformLocation(prog, "ex"), ex);
    gl.uniform1f(gl.getUniformLocation(prog, "cut"), cutHeight());
    const undo = extra ? extra() : [];
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, part.t);
    gl.drawElements(gl.TRIANGLES, part.count, gl.UNSIGNED_INT, 0);
    for (const a of undo) gl.disableVertexAttribArray(a);
  }
  const cutInput = document.getElementById("cut");
  function cutHeight() {
    const lo = geo ? Math.min(geo.low, S.low) : S.low, hi = geo ? Math.max(geo.high, S.high) : S.high;
    return +cutInput.value >= 1000 ? 1e9 : lo + (hi - lo) * cutInput.value / 1000;
  }
  cutInput.oninput = () => { const c = cutHeight(); document.getElementById("cutv").textContent = c > 1e8 ? "all" : c.toFixed(0) + " yd"; draw3d(); };
  // The camera flies like a character with no gravity and no collisions:
  // it stands somewhere and looks some way. Dragging looks round from where
  // it stands; W/S go forward and back where it looks, A/D step sideways,
  // Q/E turn, Space/R up, X/F down, Shift is faster; the wheel sets the speed.
  let minX = 1e9, maxX = -1e9, minZ = 1e9, maxZ = -1e9;
  for (let i = 0; i < verts.length; i += 3) { minX = Math.min(minX, verts[i]); maxX = Math.max(maxX, verts[i]); minZ = Math.min(minZ, verts[i + 2]); maxZ = Math.max(maxZ, verts[i + 2]); }
  const span = Math.max(maxX - minX, maxZ - minZ, 50), mid = [(minX + maxX) / 2, (S.low + S.high) / 2, (minZ + maxZ) / 2];
  // cam.y is in yards of height; the view stretches it by the height slider.
  const cam = { x: 0, y: 0, z: 0, yaw: 0.5, pitch: 0.6, speed: 25 };
  const forward = () => [-Math.cos(cam.pitch) * Math.sin(cam.yaw), -Math.sin(cam.pitch), -Math.cos(cam.pitch) * Math.cos(cam.yaw)];
  function standBack(distance) {
    // Stand `distance` yards back from the middle of the place, looking at it.
    const f = forward(), ex = +exInput.value;
    cam.x = mid[0] - f[0] * distance; cam.z = mid[2] - f[2] * distance;
    cam.y = (mid[1] * ex - f[1] * distance) / ex;
  }
  standBack(span * 0.75);
  const readout = document.getElementById("readout");
  const showSpeed = () => { readout.textContent = "speed " + cam.speed.toFixed(0) + " yd/s (wheel to change, Shift x4)"; };
  document.getElementById("topview").onclick = () => {
    cam.yaw = 0; cam.pitch = 1.55; cam.x = mid[0]; cam.z = mid[2];
    cam.y = S.high + span * 0.9 / +exInput.value; draw3d();
  };
  keys3d = (held, dt) => {
    const step = cam.speed * dt * (held.has("shift") ? 4 : 1), ex = +exInput.value;
    const f = forward(), rx = Math.cos(cam.yaw), rz = -Math.sin(cam.yaw);
    const go = (dx, dy, dz) => { cam.x += dx * step; cam.y += dy * step / ex; cam.z += dz * step; };
    if (held.has("w")) go(f[0], f[1], f[2]);
    if (held.has("s")) go(-f[0], -f[1], -f[2]);
    if (held.has("d")) go(rx, 0, rz);
    if (held.has("a")) go(-rx, 0, -rz);
    if (held.has(" ") || held.has("r")) go(0, 1, 0);
    if (held.has("x") || held.has("f")) go(0, -1, 0);
    if (held.has("q")) cam.yaw += 1.8 * dt;
    if (held.has("e")) cam.yaw -= 1.8 * dt;
    draw3d();
  };

  function mul(a, b) { const o = new Float32Array(16); for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k]; o[c * 4 + r] = s; } return o; }
  function matrix() {
    const ex = +exInput.value, aspect = canvas.width / canvas.height, f = 1 / Math.tan(Math.PI * 35 / 180), near = 0.3, far = 20000;
    const proj = new Float32Array([f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, 2 * far * near / (near - far), 0]);
    const e = [cam.x, cam.y * ex, cam.z], look = forward();
    const t = [e[0] + look[0], e[1] + look[1], e[2] + look[2]];
    const norm = v => { const l = Math.hypot(...v); return v.map(x => x / l); };
    const zAxis = norm([e[0] - t[0], e[1] - t[1], e[2] - t[2]]);
    const xAxis = norm([zAxis[2], 0, -zAxis[0]]);
    const yAxis = [zAxis[1] * xAxis[2] - zAxis[2] * xAxis[1], zAxis[2] * xAxis[0] - zAxis[0] * xAxis[2], zAxis[0] * xAxis[1] - zAxis[1] * xAxis[0]];
    const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    const view = new Float32Array([xAxis[0], yAxis[0], zAxis[0], 0, xAxis[1], yAxis[1], zAxis[1], 0, xAxis[2], yAxis[2], zAxis[2], 0, -dot(xAxis, e), -dot(yAxis, e), -dot(zAxis, e), 1]);
    return { m: mul(proj, view), ex, right: xAxis };
  }
  function drawColoured(b, mode, m, ex, size) {
    if (!b.count) return;
    gl.useProgram(flat); gl.bindBuffer(gl.ARRAY_BUFFER, b.buf);
    const pl = gl.getAttribLocation(flat, "p"), cl = gl.getAttribLocation(flat, "c");
    gl.enableVertexAttribArray(pl); gl.enableVertexAttribArray(cl);
    gl.vertexAttribPointer(pl, 3, gl.FLOAT, false, 24, 0); gl.vertexAttribPointer(cl, 3, gl.FLOAT, false, 24, 12);
    gl.uniformMatrix4fv(gl.getUniformLocation(flat, "m"), false, m);
    gl.uniform1f(gl.getUniformLocation(flat, "ex"), ex); gl.uniform1f(gl.getUniformLocation(flat, "size"), size);
    gl.drawArrays(mode, 0, b.count); gl.disableVertexAttribArray(cl);
  }
  let current = null;
  draw3d = () => {
    const r = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, r.width * dpr); canvas.height = Math.max(1, r.height * dpr);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0.043, 0.047, 0.055, 1); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); gl.enable(gl.DEPTH_TEST);
    const { m, ex } = current = matrix();
    if (on.map && img.complete) {
      gl.useProgram(textured); gl.bindBuffer(gl.ARRAY_BUFFER, quad);
      const pl = gl.getAttribLocation(textured, "p"), ul = gl.getAttribLocation(textured, "uv");
      gl.enableVertexAttribArray(pl); gl.enableVertexAttribArray(ul);
      gl.vertexAttribPointer(pl, 3, gl.FLOAT, false, 20, 0); gl.vertexAttribPointer(ul, 2, gl.FLOAT, false, 20, 12);
      const shifted = mul(m, new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, floorY * ex, 0, 1]));
      gl.uniformMatrix4fv(gl.getUniformLocation(textured, "m"), false, shifted);
      gl.bindTexture(gl.TEXTURE_2D, tex); gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4); gl.disableVertexAttribArray(ul);
    }
    if (on.geometry && geo) {
      if (geo.groundTex) drawMesh(groundProg, geo.ground, m, ex, () => {
        gl.uniform4fv(gl.getUniformLocation(groundProg, "rect"), geo.rect); gl.bindTexture(gl.TEXTURE_2D, geo.groundTex); return []; });
      else drawMesh(greyProg, geo.ground, m, ex);
      if (on.props) drawMesh(greyProg, geo.props, m, ex);
      if (geo.models) drawMesh(modelProg, geo.models, m, ex, () => {
        const ul = gl.getAttribLocation(modelProg, "uv"), sl = gl.getAttribLocation(modelProg, "slot");
        gl.bindBuffer(gl.ARRAY_BUFFER, geo.uv); gl.enableVertexAttribArray(ul); gl.vertexAttribPointer(ul, 2, gl.FLOAT, false, 8, 0);
        gl.bindBuffer(gl.ARRAY_BUFFER, geo.slot); gl.enableVertexAttribArray(sl); gl.vertexAttribPointer(sl, 1, gl.FLOAT, false, 4, 0);
        gl.uniform1f(gl.getUniformLocation(modelProg, "cells"), geo.cells); gl.uniform1f(gl.getUniformLocation(modelProg, "cell"), geo.cell);
        gl.bindTexture(gl.TEXTURE_2D, geo.atlas); return [ul, sl]; });
    }
    if (on.floors) {
      gl.useProgram(surface); gl.bindBuffer(gl.ARRAY_BUFFER, surfaceBuf); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, triBuf);
      const pl = gl.getAttribLocation(surface, "p"); gl.enableVertexAttribArray(pl); gl.vertexAttribPointer(pl, 3, gl.FLOAT, false, 12, 0);
      const rl = gl.getAttribLocation(surface, "rc"); gl.bindBuffer(gl.ARRAY_BUFFER, roomBuf); gl.enableVertexAttribArray(rl); gl.vertexAttribPointer(rl, 3, gl.FLOAT, false, 12, 0);
      gl.uniform1f(gl.getUniformLocation(surface, "byRoom"), on.byRoom ? 1 : 0);
      gl.uniformMatrix4fv(gl.getUniformLocation(surface, "m"), false, m);
      gl.uniform1f(gl.getUniformLocation(surface, "ex"), ex); gl.uniform1f(gl.getUniformLocation(surface, "lo"), S.low); gl.uniform1f(gl.getUniformLocation(surface, "hi"), S.high);
      gl.drawElements(gl.TRIANGLES, tris.length, gl.UNSIGNED_INT, 0); gl.disableVertexAttribArray(rl);
    }
    if (on.rest) drawColoured(restBuf, gl.POINTS, m, ex, 2);
    if (on.top) gl.disable(gl.DEPTH_TEST);
    if (on.graph) { drawColoured(glineBuf, gl.LINES, m, ex, 1); drawColoured(gptBuf, gl.POINTS, m, ex, 6); }
    if (on.changes) drawColoured(gchangeBuf, gl.LINES, m, ex, 1);
    gl.enable(gl.DEPTH_TEST);
  };
  window.addEventListener("resize", () => { if (canvas.style.display !== "none") draw3d(); });
  let drag3 = null;
  canvas.addEventListener("contextmenu", ev => ev.preventDefault());
  canvas.addEventListener("mousedown", ev => { drag3 = { x: ev.clientX, y: ev.clientY }; canvas.style.cursor = "grabbing"; });
  window.addEventListener("mouseup", () => { drag3 = null; canvas.style.cursor = "grab"; });
  canvas.addEventListener("mousemove", ev => {
    if (drag3) {
      const dx = ev.clientX - drag3.x, dy = ev.clientY - drag3.y; drag3.x = ev.clientX; drag3.y = ev.clientY;
      // Looking round from where the camera stands.
      cam.yaw -= dx * 0.004; cam.pitch = Math.min(1.55, Math.max(-1.55, cam.pitch + dy * 0.004));
      draw3d(); tip.style.display = "none"; return;
    }
    // Hover: the nearest point of the place on screen.
    if (!current || !g3.length || !on.graph) return;
    const r = canvas.getBoundingClientRect(); let best = null, bd = 100;
    g3.forEach((p, i) => { const m = current.m, x = p[0], y = p[1] * current.ex, z = p[2];
      const cw = m[3] * x + m[7] * y + m[11] * z + m[15]; if (cw <= 0) return;
      const sx = (m[0] * x + m[4] * y + m[8] * z + m[12]) / cw, sy = (m[1] * x + m[5] * y + m[9] * z + m[13]) / cw;
      const px = (sx + 1) / 2 * r.width, py = (1 - sy) / 2 * r.height;
      const d = (px - (ev.clientX - r.left)) ** 2 + (py - (ev.clientY - r.top)) ** 2; if (d < bd) { bd = d; best = i; } });
    if (best === null) { tip.style.display = "none"; return; }
    const p = D.graph.points[best];
    tip.textContent = "#" + (best + 1) + "  " + p.at[0].toFixed(2) + ", " + p.at[1].toFixed(2) + "\n" + p.kind + ", height " + p.world[2].toFixed(0) + " yd, clearance " + p.clearance + " yd";
    tip.style.display = "block"; tip.style.left = (ev.clientX - r.left + 14) + "px"; tip.style.top = (ev.clientY - r.top + 14) + "px";
  });
  canvas.addEventListener("wheel", ev => { ev.preventDefault();
    cam.speed = Math.min(400, Math.max(2, cam.speed * (ev.deltaY < 0 ? 1.25 : 0.8))); showSpeed(); }, { passive: false });
  showSpeed();
}
}
</script></body></html>
"""

if __name__ == "__main__":
    main()
