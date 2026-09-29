#!/usr/bin/env python3
"""Bakes a zone for the 3D explorer (scene.html), tile by tile, once:

    python3 Tools/ClientMap/scene/bake.py 1412            (serve.py must be running for the models)

For each map tile under the zone, into .cache/scene/<continent>/:

  <tx>_<ty>.glb       the ground, full detail, holes left out, under the
                      tile's own baked ground texture;
  <tx>_<ty>.low.glb   the same with a quarter of the points, for far away;
  <tx>_<ty>.json      every model placed on the tile (a WMO or M2 is the
                      tile's when its middle is on it), each as a 4x4
                      matrix, with the props the WMOs set out.

and every model any tile needs, baked by models.js (wow.export's own
exporters) into .cache/scene/models/<file id>.glb unless already there.

The scene's frame is the one ADT placements are written in (x = 17066.67 -
world Y, y = height, z = 17066.67 - world X), because a baked model's own
frame (wow.export writes (x, z, -y) of the model's coordinates) goes into
it by the placement's matrix alone: translate, turn Ry(rot.y - 90) .
Rz(rot.x) . Rx(-rot.z), scale.
"""

import io
import json
import math
import os
import struct
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import maps  # noqa: E402
import regions  # noqa: E402
import wowfiles  # noqa: E402
from casc import CACHE, Storage  # noqa: E402

OUT = os.path.join(CACHE, "scene")
C = wowfiles.MAP_CENTER
UNIT = wowfiles.TILE / 128
# A model's own frame (z up) into its baked GLB's (y up).
TO_GLB = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)


def placement_matrix(placement):
    """4x4 from a baked model's frame into the scene's, for an ADT placement."""
    rx, ry, rz = placement["rot"]
    m = np.eye(4)
    m[:3, :3] = np.array(wowfiles.rotation(-rz, ry - 90.0, rx)) * placement["scale"]
    m[:3, 3] = placement["pos"]
    return m


def doodad_matrix(pos, quat, scale):
    """4x4 from a prop's baked frame into its WMO's baked frame."""
    x, y, z, w = quat
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = TO_GLB @ r @ TO_GLB.T * scale
    m[:3, 3] = TO_GLB @ np.array(pos)
    return m


def flat(m):
    """Column-major, as three.js Matrix4.fromArray wants it."""
    return [round(float(v), 4) for v in m.T.reshape(-1)]


# --- The ground ----------------------------------------------------------------------------

def ground(root, step, layers=None):
    """(positions, uvs, indices, layer ids) of a tile's ground in the scene's
    frame. step 1: every point (the 9 x 9 corners and 8 x 8 middles of each
    chunk); step 2: the corners only, a quarter of the triangles. With the
    tile's `layers` (wowfiles.tile_layers' per-chunk list), every point also
    gets its chunk's eight layer textures (index into the tile's textures,
    -1 for none; written as bytes, 255 for none)."""
    positions, uvs, indices, ids = [], [], [], []
    tile_x = tile_y = None
    index = -1
    for tag, body in wowfiles.chunks(root):
        if tag != "MCNK" or len(body) < 0x80:
            continue
        index += 1
        chunk_ids = [-1] * 8
        if layers and index < len(layers):
            for k, (texture, _) in enumerate(layers[index][:8]):
                chunk_ids[k] = texture
        flags = struct.unpack_from("<I", body, 0)[0]
        cx, cy, cz = struct.unpack_from("<3f", body, 0x68)
        parts = dict(wowfiles.chunks(body[0x80:]))
        if "MCVT" not in parts:
            continue
        heights = struct.unpack_from("<145f", parts["MCVT"])
        if flags & 0x10000:
            bits = struct.unpack_from("<Q", body, 0x14)[0]
            hole = lambda i, j: (bits >> (i * 8 + j)) & 1  # noqa: E731
        else:
            bits = struct.unpack_from("<H", body, 0x3C)[0]
            hole = lambda i, j: (bits >> ((i // 2) * 4 + j // 2)) & 1  # noqa: E731
        if tile_x is None:
            # The tile's north-west corner, for the texture's coordinates.
            tile_x = round(cx / wowfiles.TILE) * wowfiles.TILE
            tile_y = round(cy / wowfiles.TILE) * wowfiles.TILE
        base = len(positions)

        def add(wx, wy, h):
            positions.append((C - wy, h, C - wx))
            uvs.append(((tile_y - wy) / wowfiles.TILE, (tile_x - wx) / wowfiles.TILE))
            ids.append(chunk_ids)

        if step == 1:
            for i in range(9):
                for j in range(9):
                    add(cx - i * UNIT, cy - j * UNIT, cz + heights[i * 17 + j])
            for i in range(8):
                for j in range(8):
                    add(cx - (i + 0.5) * UNIT, cy - (j + 0.5) * UNIT, cz + heights[i * 17 + 9 + j])
            for i in range(8):
                for j in range(8):
                    if hole(i, j):
                        continue
                    a, b = base + i * 9 + j, base + i * 9 + j + 1
                    c, d = base + (i + 1) * 9 + j, base + (i + 1) * 9 + j + 1
                    m = base + 81 + i * 8 + j
                    indices += [a, b, m, b, d, m, d, c, m, c, a, m]
        else:
            for i in range(0, 9, 2):
                for j in range(0, 9, 2):
                    add(cx - i * UNIT, cy - j * UNIT, cz + heights[i * 17 + j])
            for i in range(4):
                for j in range(4):
                    if any(hole(i * 2 + a, j * 2 + b) for a in (0, 1) for b in (0, 1)):
                        continue
                    a, b = base + i * 5 + j, base + i * 5 + j + 1
                    c, d = base + (i + 1) * 5 + j, base + (i + 1) * 5 + j + 1
                    indices += [a, b, c, b, d, c]
    return positions, uvs, indices, ids


def alpha_atlases(root, layers):
    """Two 1024 x 1024 RGBA pictures of a tile's blend maps, 64 x 64 per
    chunk laid out as the chunks lie (north up, west left): the first holds
    layers 2 to 5 of every chunk, the second 6 to 8."""
    atlases = np.zeros((2, 1024, 1024, 4), np.uint8)
    chunk_size = wowfiles.TILE / 16
    index = -1
    tile_x = tile_y = None
    for tag, body in wowfiles.chunks(root):
        if tag != "MCNK" or len(body) < 0x80:
            continue
        index += 1
        cx, cy, _ = struct.unpack_from("<3f", body, 0x68)
        if tile_x is None:
            tile_x = round(cx / wowfiles.TILE) * wowfiles.TILE
            tile_y = round(cy / wowfiles.TILE) * wowfiles.TILE
        row, col = round((tile_x - cx) / chunk_size), round((tile_y - cy) / chunk_size)
        if index >= len(layers) or not (0 <= row < 16 and 0 <= col < 16):
            continue
        for k, (_, alpha) in enumerate(layers[index][1:8]):
            atlas, channel = divmod(k, 4)
            atlases[atlas, row * 64:(row + 1) * 64, col * 64:(col + 1) * 64, channel] = \
                np.frombuffer(alpha, np.uint8).reshape(64, 64)
    return atlases


def write_glb(path, positions, uvs, indices, jpeg, ids=None):
    """A one-mesh GLB: positions, texture coordinates, triangles, one JPEG
    as its texture (unlit: the picture is already the ground's light), and
    with `ids` each point's eight layer textures as _LAYERS0 and _LAYERS1."""
    pos = np.asarray(positions, "<f4")
    uv = np.asarray(uvs, "<f4")
    # The scene's frame is the world's mirrored (x from -Y, z from -X), so
    # triangles wound for the world face down in it: turn them over.
    idx = np.asarray(indices, "<u4").reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
    blobs, views, offset = [], [], 0
    extra = []
    if ids is not None:
        # One byte per layer; 255 for none.
        lay = np.where(np.asarray(ids) < 0, 255, np.asarray(ids)).astype(np.uint8)
        extra = [lay[:, :4].copy().tobytes(), lay[:, 4:].copy().tobytes()]
    for data, target in ((pos.tobytes(), 34962), (uv.tobytes(), 34962), (idx.tobytes(), 34963), (jpeg, None)) + \
            tuple((e, 34962) for e in extra):
        pad = (-len(data)) % 4
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        blobs.append(data + b"\0" * pad)
        offset += len(data) + pad
    doc = {
        "asset": {"version": "2.0", "generator": "NuuRoad scene/bake.py"},
        "extensionsUsed": ["KHR_materials_unlit"],
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": dict({"POSITION": 0, "TEXCOORD_0": 1},
                                                       **({"_LAYERS0": 3, "_LAYERS1": 4} if extra else {})),
                                    "indices": 2, "material": 0}]}],
        "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1},
                       "extensions": {"KHR_materials_unlit": {}}}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"bufferView": 3, "mimeType": "image/jpeg"}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 2, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ] + [{"bufferView": 4 + k, "componentType": 5121, "count": len(pos), "type": "VEC4"} for k in range(len(extra))],
        "bufferViews": views, "buffers": [{"byteLength": offset}],
    }
    text = json.dumps(doc).encode()
    text += b" " * ((-len(text)) % 4)
    body = b"".join(blobs)
    with open(path, "wb") as out:
        out.write(struct.pack("<3I", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(body)))
        out.write(struct.pack("<2I", len(text), 0x4E4F534A) + text)
        out.write(struct.pack("<2I", len(body), 0x004E4942) + body)


# --- A tile -----------------------------------------------------------------------------------

def owns(tx, ty, x, y):
    """Whether world (x, y) is on tile (tx, ty)."""
    return wowfiles.tile_of(x, y) == (tx, ty)


TEXTURES = os.path.join(OUT, "textures")
TEXTURE_SIZE = 256


def bake_texture(storage, file_id):
    """A ground texture as a JPEG, once, for the explorer's blending."""
    path = os.path.join(TEXTURES, "%d.jpg" % file_id)
    if os.path.exists(path):
        return True
    data = storage.read_picture(file_id)
    if data is None:
        return False
    from PIL import Image
    try:
        image = Image.open(io.BytesIO(data)).convert("RGB").resize((TEXTURE_SIZE, TEXTURE_SIZE))
    except Exception:
        return False
    os.makedirs(TEXTURES, exist_ok=True)
    image.save(path, "JPEG", quality=88)
    return True


def bake_tile(storage, folder, tx, ty, files, needed, big_alpha=True):
    out_dir = os.path.join(OUT, folder)
    base = os.path.join(out_dir, "%d_%d" % (tx, ty))
    root = storage.read(files["root"]) or b""
    picture = storage.read(files["maptexture"]) if files.get("maptexture") else None
    if picture:
        from PIL import Image
        image = Image.open(io.BytesIO(picture)).convert("RGB")
        buffer = io.BytesIO()
        image.save(buffer, "JPEG", quality=85)
        jpeg = buffer.getvalue()
    else:
        jpeg = b""
    # The ground's own texture layers, for the full-detail ground.
    tex0 = storage.read(files["tex0"]) if files.get("tex0") else None
    textures, scales, layers = wowfiles.tile_layers(tex0, big_alpha) if tex0 else ([], [], [])
    textures_ok = [bake_texture(storage, t) for t in textures]
    if layers:
        from PIL import Image
        for k, atlas in enumerate(alpha_atlases(root, layers)):
            Image.fromarray(atlas, "RGBA").save(base + ".alpha%d.png" % k, compress_level=1)
    for step, suffix in ((1, ".glb"), (2, ".low.glb")):
        positions, uvs, indices, ids = ground(root, step, layers if step == 1 else None)
        if positions and jpeg:
            write_glb(base + suffix, positions, uvs, indices, jpeg, ids if step == 1 and layers else None)
    obj0 = storage.read(files["obj0"]) or b""
    wmos, props = [], []
    for placement in wowfiles.adt_wmo_placements(obj0):
        bx0, by0, bx1, by1 = placement["box"]
        if placement["file"] is None or not owns(tx, ty, (bx0 + bx1) / 2, (by0 + by1) / 2):
            continue
        matrix = placement_matrix(placement)
        wmos.append({"file": placement["file"], "unique": placement["unique"], "m": flat(matrix)})
        needed.add(placement["file"])
        for file_id, pos, quat, scale in wowfiles.wmo_doodads(storage, placement):
            props.append({"file": file_id, "m": flat(matrix @ doodad_matrix(pos, quat, scale))})
            needed.add(file_id)
    for placement in wowfiles.adt_m2_placements(obj0):
        if not placement["file"]:
            continue
        x, y = C - placement["pos"][2], C - placement["pos"][0]
        if not owns(tx, ty, x, y):
            continue
        props.append({"file": placement["file"], "m": flat(placement_matrix(placement))})
        needed.add(placement["file"])
    with open(base + ".json", "w") as out:
        json.dump({"tile": [tx, ty], "wmo": wmos, "m2": props,
                   "ground": os.path.exists(base + ".glb"),
                   "textures": [t if ok else 0 for t, ok in zip(textures, textures_ok)], "scales": scales,
                   "layers": bool(layers)}, out)
    return len(wmos), len(props)


def bake_zone(map_id, storage=None):
    storage = storage or Storage()
    info = maps.get(map_id, storage)
    folder = maps.CONTINENTS[info["continent"]]
    wdt = storage.read_path("world/maps/%s/%s.wdt" % (folder, folder))
    tiles = wowfiles.wdt_tiles(wdt)
    big_alpha = bool(wowfiles.wdt_flags(wdt) & 0x84)
    x0, x1, y0, y1 = regions.world_rect(map_id)
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    needed, baked = set(), []
    for (tx, ty), files in sorted(tiles.items()):
        tile_x0, tile_y0 = (32 - ty - 1) * wowfiles.TILE, (32 - tx - 1) * wowfiles.TILE
        if tile_x0 > x1 or tile_x0 + wowfiles.TILE < x0 or tile_y0 > y1 or tile_y0 + wowfiles.TILE < y0:
            continue
        if os.path.exists(os.path.join(OUT, folder, "%d_%d.json" % (tx, ty))):
            with open(os.path.join(OUT, folder, "%d_%d.json" % (tx, ty))) as handle:
                done = json.load(handle)
            needed.update(p["file"] for p in done["wmo"] + done["m2"])
            baked.append([tx, ty])
            continue
        w, p = bake_tile(storage, folder, tx, ty, files, needed, big_alpha)
        baked.append([tx, ty])
        print("tile %d_%d: %d WMOs, %d props" % (tx, ty, w, p), flush=True)
    # A zone's list of tiles, and where to start: its middle.
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    with open(os.path.join(OUT, "zone-%d.json" % map_id), "w") as out:
        json.dump({"map": map_id, "name": info["name"], "continent": folder, "tiles": baked,
                   "centre": [C - my, C - mx]}, out)
    models = os.path.join(OUT, "models")
    missing = sorted(i for i in needed if not os.path.exists(os.path.join(models, "%d.glb" % i)))
    print("%d models needed, %d to bake" % (len(needed), len(missing)), flush=True)
    for start in range(0, len(missing), 200):
        subprocess.run(["node", os.path.join(HERE, "models.js")] + [str(i) for i in missing[start:start + 200]],
                       check=False)


def main():
    storage = Storage()
    for arg in sys.argv[1:]:
        bake_zone(int(arg), storage)


if __name__ == "__main__":
    main()
