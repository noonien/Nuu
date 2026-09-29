"""Just enough of the client's map formats to get walkable geometry out.

WDT (which files make up each map tile), ADT obj0 (where the big models are
placed), WMO (a building or city model: a root file and its groups, each with
vertices, triangles and per-triangle collision flags), and the world map's
BLP tiles for drawing.

World coordinates here are the client's: X north, Y west, Z up, in yards,
the same numbers C_Map.GetWorldPosFromMapPos gives in the game.
"""

import io
import math
import struct

TILE = 533.33333
MAP_CENTER = 32 * TILE  # 17066.666: ADT placement coordinates count from here


def chunks(data):
    """(tag, bytes) for each chunk; tags are stored reversed on disk."""
    offset = 0
    while offset + 8 <= len(data):
        tag = data[offset:offset + 4][::-1].decode("latin1")
        size = struct.unpack_from("<I", data, offset + 4)[0]
        yield tag, data[offset + 8:offset + 8 + size]
        offset += 8 + size


def chunk(data, tag):
    for name, body in chunks(data):
        if name == tag:
            return body
    return b""


# --- WDT and ADT -------------------------------------------------------------

def wdt_tiles(wdt):
    """{(x, y): {"root", "obj0", ...}} file IDs of each tile present."""
    maid = chunk(wdt, "MAID")
    tiles = {}
    for index in range(len(maid) // 32):
        ids = struct.unpack_from("<8I", maid, index * 32)
        if ids[0] or ids[1]:
            tiles[(index % 64, index // 64)] = {"root": ids[0], "obj0": ids[1], "obj1": ids[2], "tex0": ids[3],
                                                # The ground baked into one picture, and the
                                                # minimap (ground and buildings from above).
                                                "maptexture": ids[5], "minimap": ids[7]}
    return tiles


def tile_of(world_x, world_y):
    """The WDT tile (x, y) a world position is in."""
    return int(32 - world_y / TILE), int(32 - world_x / TILE)


def adt_wmo_placements(obj0):
    """Every WMO the tile places: file ID, unique ID, position, rotation."""
    modf = chunk(obj0, "MODF")
    out = []
    for index in range(len(modf) // 64):
        name_id, unique_id = struct.unpack_from("<2I", modf, index * 64)
        pos = struct.unpack_from("<3f", modf, index * 64 + 8)
        rot = struct.unpack_from("<3f", modf, index * 64 + 20)
        flags, doodad_set, name_set, scale = struct.unpack_from("<4H", modf, index * 64 + 56)
        extents = struct.unpack_from("<6f", modf, index * 64 + 32)
        out.append({
            "file": name_id if flags & 0x8 else None,  # 0x8: name_id is a file ID
            "unique": unique_id, "pos": pos, "rot": rot, "flags": flags, "doodad_set": doodad_set,
            # Bounds in world X and Y (from the placement's box, ADT frame).
            "box": (MAP_CENTER - extents[5], MAP_CENTER - extents[3], MAP_CENTER - extents[2], MAP_CENTER - extents[0]),
            "scale": (scale / 1024.0) if (flags & 0x4 and scale) else 1.0,
        })
    return out


def rotation(ax, ay, az):
    """Ry(ay) . Rz(az) . Rx(ax), angles in degrees, as a 3x3 list."""
    def rx(t):
        c, s = math.cos(t), math.sin(t)
        return [[1, 0, 0], [0, c, -s], [0, s, c]]

    def ry(t):
        c, s = math.cos(t), math.sin(t)
        return [[c, 0, s], [0, 1, 0], [-s, 0, c]]

    def rz(t):
        c, s = math.cos(t), math.sin(t)
        return [[c, -s, 0], [s, c, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(mul(ry(math.radians(ay)), rz(math.radians(az))), rx(math.radians(ax)))


def placement_transform(placement):
    """A function from a placed model's own coordinates (x, y, z; z up) to
    world ones.

    Placements are in ADT coordinates, counted from the map's corner with Y
    up: world X = 17066.67 - z, world Y = 17066.67 - x, height = y. As map
    editors (Noggit) read them, the model's axes are put into that frame as
    (x, z, -y) and turned by Ry(rot.y - 90) . Rz(rot.x) . Rx(-rot.z). With
    no tilt this is the turn the Undercity placement was checked with.
    """
    px, py, pz = placement["pos"]
    rx, ry, rz = placement["rot"]
    m = rotation(-rz, ry - 90.0, rx)
    scale = placement["scale"]

    def transform(x, y, z):
        a, b, c = x * scale, z * scale, -y * scale
        qx = px + m[0][0] * a + m[0][1] * b + m[0][2] * c
        qy = py + m[1][0] * a + m[1][1] * b + m[1][2] * c
        qz = pz + m[2][0] * a + m[2][1] * b + m[2][2] * c
        return MAP_CENTER - qz, MAP_CENTER - qx, qy
    return transform


def adt_m2_placements(obj0):
    """Every M2 (prop) the tile places: file ID, unique ID, position,
    rotation, scale."""
    mddf = chunk(obj0, "MDDF")
    out = []
    for index in range(len(mddf) // 36):
        name_id, unique_id = struct.unpack_from("<2I", mddf, index * 36)
        pos = struct.unpack_from("<3f", mddf, index * 36 + 8)
        rot = struct.unpack_from("<3f", mddf, index * 36 + 20)
        scale, flags = struct.unpack_from("<2H", mddf, index * 36 + 32)
        out.append({"file": name_id if flags & 0x40 else None, "unique": unique_id, "pos": pos, "rot": rot,
                    "scale": scale / 1024.0})
    return out


def terrain_triangles(root, keep=None):
    """A tile's ground as (vertices, triangles) in world coordinates, holes
    left out. `keep(x0, y0, x1, y1, area)` says whether a chunk is wanted,
    from its square (world X and Y ranges) and the game area it belongs to.

    Each MCNK chunk is 8 by 8 squares of TILE / 128 yards: 145 heights, the
    9 x 9 corners and the 8 x 8 middles in alternating rows, rows running
    south (world X falling) and columns east (world Y falling) from the
    chunk's position; each square is four triangles round its middle. A hole
    takes out a square (64 bits, with flag 0x10000) or 2 x 2 squares (16)."""
    unit = TILE / 128
    vertices, triangles = [], []
    for tag, body in chunks(root):
        if tag != "MCNK" or len(body) < 0x80:
            continue
        flags = struct.unpack_from("<I", body, 0)[0]
        area = struct.unpack_from("<I", body, 0x34)[0]
        cx, cy, cz = struct.unpack_from("<3f", body, 0x68)
        if keep and not keep(cx - 8 * unit, cy - 8 * unit, cx, cy, area):
            continue
        parts = dict(chunks(body[0x80:]))
        if "MCVT" not in parts:
            continue
        heights = struct.unpack_from("<145f", parts["MCVT"])
        if flags & 0x10000:
            holes_high = struct.unpack_from("<Q", body, 0x14)[0]
            hole = lambda i, j: (holes_high >> (i * 8 + j)) & 1  # noqa: E731
        else:
            holes_low = struct.unpack_from("<H", body, 0x3C)[0]
            hole = lambda i, j: (holes_low >> ((i // 2) * 4 + j // 2)) & 1  # noqa: E731
        base = len(vertices)
        for i in range(9):
            for j in range(9):
                vertices.append((cx - i * unit, cy - j * unit, cz + heights[i * 17 + j]))
        for i in range(8):
            for j in range(8):
                vertices.append((cx - (i + 0.5) * unit, cy - (j + 0.5) * unit, cz + heights[i * 17 + 9 + j]))
        for i in range(8):
            for j in range(8):
                if hole(i, j):
                    continue
                a, b = base + i * 9 + j, base + i * 9 + j + 1
                c, d = base + (i + 1) * 9 + j, base + (i + 1) * 9 + j + 1
                m = base + 81 + i * 8 + j
                # Wound to face up (Recast walks only upward-facing ground).
                triangles += [(a, m, b), (b, m, d), (d, m, c), (c, m, a)]
    return vertices, triangles


def wdt_flags(wdt):
    """The WDT's MPHD flags: 0x4 or 0x80 mean 4096-byte (8-bit) alpha maps."""
    mphd = chunk(wdt, "MPHD")
    return struct.unpack_from("<I", mphd, 0)[0] if len(mphd) >= 4 else 0


def tile_layers(tex0, big_alpha):
    """A tile's ground textures from its tex0 file: (texture file IDs, their
    tiling scales, and per chunk in file order its layers as [(texture
    index, 64 x 64 alpha bytes or None for the first)]).

    A layer's texture repeats 8 / scale times across its chunk, the scale
    being 2 ** ((MTXP flags >> 4) & 0xF). Alpha maps are RLE-compressed
    (layer flag 0x200), else 4096 bytes when the WDT says big alpha, else
    2048 bytes of 4-bit values."""
    textures, scales, chunks_out = [], [], []
    for tag, body in chunks(tex0):
        if tag == "MDID":
            textures = list(struct.unpack_from("<%dI" % (len(body) // 4), body))
        elif tag == "MTXP":
            scales = [2 ** ((struct.unpack_from("<I", body, i * 16)[0] >> 4) & 0xF) for i in range(len(body) // 16)]
        elif tag == "MCNK":
            parts = dict(chunks(body))
            mcly, mcal = parts.get("MCLY", b""), parts.get("MCAL", b"")
            layers = []
            for k in range(len(mcly) // 16):
                texture, flags, offset = struct.unpack_from("<3I", mcly, k * 16)
                if k == 0:
                    layers.append((texture, None))
                    continue
                if flags & 0x200:
                    out, at = bytearray(), offset
                    while len(out) < 4096 and at < len(mcal):
                        info = mcal[at]
                        at += 1
                        count = info & 0x7F
                        if info & 0x80:
                            out += bytes([mcal[at]]) * count
                            at += 1
                        else:
                            out += mcal[at:at + count]
                            at += count
                    alpha = bytes(out[:4096]).ljust(4096, b"\0")
                elif big_alpha:
                    alpha = mcal[offset:offset + 4096].ljust(4096, b"\0")
                else:
                    raw = mcal[offset:offset + 2048]
                    low, high = bytes(range(0, 256)).translate(bytes((b & 0x0F) * 17 for b in range(256))), \
                        bytes((b >> 4) * 17 for b in range(256))
                    pairs = bytearray(4096)
                    pairs[0::2] = raw.translate(low).ljust(2048, b"\0")
                    pairs[1::2] = raw.translate(high).ljust(2048, b"\0")
                    alpha = bytes(pairs)
                layers.append((texture, alpha))
            chunks_out.append(layers)
    scales += [1] * (len(textures) - len(scales))
    return textures, scales, chunks_out


# --- WMO -----------------------------------------------------------------------

MOPY_DETAIL = 0x04
MOPY_COLLISION = 0x08
MOPY_RENDER = 0x20


def wmo_groups(storage, root_id):
    """The file IDs of a WMO root's groups."""
    root = storage.read(root_id)
    if root is None:
        raise OSError("WMO %d is not in the store" % root_id)
    group_count = struct.unpack_from("<I", chunk(root, "MOHD"), 4)[0]
    gfid = chunk(root, "GFID")
    ids = struct.unpack_from("<%dI" % (len(gfid) // 4), gfid)
    return [file_id for file_id in ids[:group_count] if file_id]


def group_faces(parts):
    """A WMO group's triangle indices and, per triangle, its (flags,
    material): from MOVI/MOPY (16-bit indices; one byte each), or in newer
    files MOVX (32-bit indices) and MPY2 (two bytes each, material 0xFFFF
    for none). Without either, every triangle counts as collision."""
    movi, movx = parts.get("MOVI", b""), parts.get("MOVX", b"")
    indices = (struct.unpack_from("<%dI" % (len(movx) // 4), movx) if movx
               else struct.unpack_from("<%dH" % (len(movi) // 2), movi))
    count = len(indices) // 3
    mopy, mpy2 = parts.get("MOPY", b""), parts.get("MPY2", b"")
    if mpy2:
        faces = [struct.unpack_from("<2H", mpy2, t * 4) for t in range(min(count, len(mpy2) // 4))]
        faces = [(f, 0xFF if m == 0xFFFF else m) for f, m in faces]
    elif mopy:
        faces = [(mopy[t * 2], mopy[t * 2 + 1]) for t in range(min(count, len(mopy) // 2))]
    else:
        faces = []
    faces += [(MOPY_COLLISION, 0xFF)] * (count - len(faces))
    return indices, faces


def wmo_group_triangles(data):
    """(vertices, triangles) of the triangles a player collides with.

    Collision is what the server's own extractors keep: a triangle flagged
    for collision, or one that is drawn and is not detail work.
    """
    mogp = chunk(data, "MOGP")[0x44:]
    parts = dict(chunks(mogp))
    movt = parts.get("MOVT", b"")
    vertices = [struct.unpack_from("<3f", movt, i * 12) for i in range(len(movt) // 12)]
    indices, faces = group_faces(parts)
    triangles = []
    for t, (flags, _) in enumerate(faces):
        render = (flags & MOPY_RENDER) and not (flags & MOPY_DETAIL)
        if flags & MOPY_COLLISION or render:
            triangles.append(indices[t * 3:t * 3 + 3])
    return vertices, triangles


def wmo_world_mesh(storage, placement, transform):
    """All collision triangles of a placed WMO, in world coordinates."""
    vertices, triangles = [], []
    for group_id in wmo_groups(storage, placement["file"]):
        data = storage.read(group_id)
        if data is None:
            continue
        verts, tris = wmo_group_triangles(data)
        base = len(vertices)
        vertices.extend(transform(*v) for v in verts)
        triangles.extend((a + base, b + base, c + base) for a, b, c in tris)
    return vertices, triangles


def wmo_textures(storage, root):
    """Each material's first texture, as a file ID (None for none). Newer
    WMOs keep file IDs in MOMT; older ones offsets into the MOTX names."""
    momt, motx = chunk(root, "MOMT"), chunk(root, "MOTX")
    out = []
    for k in range(len(momt) // 64):
        flags, shader, blend, texture = struct.unpack_from("<4I", momt, k * 64)
        if motx:
            end = motx.find(b"\0", texture)
            path = motx[texture:end].decode("latin1").lower().replace("\\", "/")
            file_id = storage.file_id(path) if path else None
        else:
            file_id = texture or None
        out.append({"texture": file_id, "blend": blend})
    return out


def wmo_render(storage, placement, transform):
    """What a placed WMO draws: (vertices in world coordinates, their texture
    coordinates, triangles, each triangle's material index, the materials).
    Collision-only triangles (material 0xFF) are left out."""
    root = storage.read(placement["file"])
    materials = wmo_textures(storage, root)
    vertices, uvs, triangles, triangle_materials = [], [], [], []
    for group_id in wmo_groups(storage, placement["file"]):
        data = storage.read(group_id)
        if data is None:
            continue
        parts = dict(chunks(chunk(data, "MOGP")[0x44:]))
        movt, motv = parts.get("MOVT", b""), parts.get("MOTV", b"")
        count = len(movt) // 12
        if not count:
            continue
        base = len(vertices)
        vertices.extend(transform(*struct.unpack_from("<3f", movt, i * 12)) for i in range(count))
        if len(motv) >= 8 * count:
            uvs.extend(struct.unpack_from("<2f", motv, i * 8) for i in range(count))
        else:
            uvs.extend([(0.0, 0.0)] * count)
        indices, faces = group_faces(parts)
        for t, (_, material) in enumerate(faces):
            if material == 0xFF or material >= len(materials):
                continue
            a, b, c = indices[t * 3:t * 3 + 3]
            triangles.append((a + base, b + base, c + base))
            triangle_materials.append(material)
    return vertices, uvs, triangles, triangle_materials, materials


def wmo_doodads(storage, placement):
    """The props a placed WMO sets out (its doodad set 0 and the one the
    placement picks): [(M2 file ID, position, quaternion x y z w, scale)] in
    the WMO's own coordinates."""
    root = storage.read(placement["file"])
    if root is None:
        return []
    modd, mods, modi = chunk(root, "MODD"), chunk(root, "MODS"), chunk(root, "MODI")
    modn = chunk(root, "MODN")
    ids = struct.unpack_from("<%dI" % (len(modi) // 4), modi) if modi else None
    sets = [struct.unpack_from("<2I", mods, k * 32 + 20) for k in range(len(mods) // 32)]
    wanted = {0, placement.get("doodad_set", 0)}
    out = []
    for k, (start, count) in enumerate(sets):
        if k not in wanted:
            continue
        for d in range(start, min(start + count, len(modd) // 40)):
            word = struct.unpack_from("<I", modd, d * 40)[0]
            name = word & 0xFFFFFF
            pos = struct.unpack_from("<3f", modd, d * 40 + 4)
            quat = struct.unpack_from("<4f", modd, d * 40 + 16)
            scale = struct.unpack_from("<f", modd, d * 40 + 32)[0]
            if ids is not None:
                file_id = ids[name] if name < len(ids) else None
            else:
                end = modn.find(b"\0", name)
                path = modn[name:end].decode("latin1").lower().replace(".mdx", ".m2").replace(".mdl", ".m2")
                file_id = storage.file_id(path)
            if file_id:
                out.append((file_id, pos, quat, scale))
    return out


def m2_collision(storage, file_id, cache={}):
    """An M2's collision shell: (vertices, triangles) in its own
    coordinates, or None when it has none (most small props)."""
    if file_id in cache:
        return cache[file_id]
    data = storage.read(file_id)
    result = None
    if data:
        # A modern M2 wraps its MD20 data in an MD21 chunk (its tags are not
        # stored reversed, unlike the map files').
        md20 = data[8:8 + struct.unpack_from("<I", data, 4)[0]] if data[:4] == b"MD21" else data
        if md20[:4] == b"MD20" and len(md20) > 0xE8:
            n_tri, o_tri, n_vert, o_vert = struct.unpack_from("<4I", md20, 0xD8)
            if n_tri >= 3 and n_vert and o_tri + 2 * n_tri <= len(md20) and o_vert + 12 * n_vert <= len(md20):
                idx = struct.unpack_from("<%dH" % n_tri, md20, o_tri)
                verts = [struct.unpack_from("<3f", md20, o_vert + 12 * i) for i in range(n_vert)]
                tris = [idx[i:i + 3] for i in range(0, n_tri - 2, 3)]
                result = (verts, tris)
    cache[file_id] = result
    return result


def quaternion_transform(pos, quat, scale):
    """Model coordinates to its parent's: turned by the quaternion, scaled
    and moved to `pos`."""
    x, y, z, w = quat
    m = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]

    def transform(a, b, c):
        a, b, c = a * scale, b * scale, c * scale
        return (pos[0] + m[0][0] * a + m[0][1] * b + m[0][2] * c,
                pos[1] + m[1][0] * a + m[1][1] * b + m[1][2] * c,
                pos[2] + m[2][0] * a + m[2][1] * b + m[2][2] * c)
    return transform


LIQUID_TILE = TILE / 128  # 4.1667 yd: a WMO liquid tile, as a terrain one


def wmo_liquids(storage, placement, transform):
    """Every liquid tile of a placed WMO: (world X, world Y, height of the
    surface), the tile's centre; tiles are LIQUID_TILE yards square.

    A group's MLIQ chunk is a grid of vertices (with the surface height)
    over a grid of tiles; a tile whose flags have 0x08 set holds no liquid.
    """
    out = []
    for group_id in wmo_groups(storage, placement["file"]):
        data = storage.read(group_id)
        if data is None:
            continue
        parts = dict(chunks(chunk(data, "MOGP")[0x44:]))
        mliq = parts.get("MLIQ")
        if not mliq or len(mliq) < 30:
            continue
        xv, yv, xt, yt = struct.unpack_from("<4I", mliq, 0)
        cx, cy, cz = struct.unpack_from("<3f", mliq, 16)
        heights = [struct.unpack_from("<f", mliq, 30 + i * 8 + 4)[0] for i in range(xv * yv)]
        flags = mliq[30 + xv * yv * 8:30 + xv * yv * 8 + xt * yt]
        for j in range(yt):
            for i in range(xt):
                if j * xt + i >= len(flags) or flags[j * xt + i] & 0x08:
                    continue
                corners = [heights[(j + dj) * xv + (i + di)] for dj in (0, 1) for di in (0, 1)]
                x = cx + (i + 0.5) * LIQUID_TILE
                y = cy + (j + 0.5) * LIQUID_TILE
                wx, wy, wz = transform(x, y, sum(corners) / 4)
                out.append((round(wx, 2), round(wy, 2), round(wz, 2)))
    return out


def tile_mosaic(storage, tiles, rect, which="minimap"):
    """The tiles' pictures (`minimap` or `maptexture`) over a world rect
    (X min, X max, Y min, Y max), as one PIL image with north up and west
    left, and the world rect it covers exactly (tile edges)."""
    from PIL import Image
    x0, x1, y0, y1 = rect
    tx0, tx1 = int(32 - y1 / TILE), int(32 - y0 / TILE)
    ty0, ty1 = int(32 - x1 / TILE), int(32 - x0 / TILE)
    size = None
    pieces = {}
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            files = tiles.get((tx, ty))
            data = storage.read(files[which]) if files and files.get(which) else None
            if data:
                piece = Image.open(io.BytesIO(data)).convert("RGB")
                size = size or piece.size[0]
                pieces[(tx, ty)] = piece
    if not pieces:
        return None, None
    image = Image.new("RGB", ((tx1 - tx0 + 1) * size, (ty1 - ty0 + 1) * size))
    for (tx, ty), piece in pieces.items():
        image.paste(piece.resize((size, size)), ((tx - tx0) * size, (ty - ty0) * size))
    covered = ((32 - ty1 - 1) * TILE, (32 - ty0) * TILE, (32 - tx1 - 1) * TILE, (32 - tx0) * TILE)
    return image, covered


# --- World map art -------------------------------------------------------------

def world_map_image(storage, info):
    """A map's art (maps.get(...)) as one PIL image: its tiles laid out by
    row and column, cropped to the layer's size, which is what 0-100 %
    spans."""
    from PIL import Image
    tile = info["tile_size"]
    rows = 1 + max((r for r, _, _ in info["art"]), default=0)
    columns = 1 + max((c for _, c, _ in info["art"]), default=0)
    image = Image.new("RGB", (columns * tile, rows * tile))
    for row, column, file_id in info["art"]:
        data = storage.read(file_id)
        if data is None:
            continue
        piece = Image.open(io.BytesIO(data)).convert("RGB")
        image.paste(piece, (column * tile, row * tile))
    return image.crop((0, 0) + tuple(info["art_size"]))
