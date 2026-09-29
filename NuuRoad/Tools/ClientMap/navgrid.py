"""navmesh's output (.cache/<region>.bin) as numpy arrays, and the walkable
area worth keeping: the connected pieces a recorded trail stands on."""

import os
import struct

import numpy as np

import regions
import trails
from casc import CACHE


class Grid:
    def __init__(self, path):
        data = open(path, "rb").read()
        if data[:4] != b"ORNM":
            raise ValueError("%s is not navmesh output" % path)
        version, self.width, self.depth = struct.unpack_from("<3i", data, 4)
        self.bmin = struct.unpack_from("<3f", data, 16)
        self.cell, self.cell_height, count = struct.unpack_from("<2fi", data, 28)
        offset = 40
        columns = self.width * self.depth
        self.first = np.frombuffer(data, "<u4", columns, offset).astype(np.int64)
        offset += 4 * columns
        self.count = np.frombuffer(data, "u1", columns, offset).astype(np.int64)
        offset += columns
        fields = [("y", "<u2"), ("dist", "<u2"), ("n", "<i4", 4)] + ([("source", "u1")] if version >= 2 else [])
        spans = np.frombuffer(data, np.dtype(fields), count, offset)
        self.y = spans["y"].astype(np.int32)
        self.dist = spans["dist"].astype(np.int32)
        self.n = spans["n"].astype(np.int64)
        # What the floor is made of: 1 terrain, 2 model (WMO), 3 prop (M2).
        self.source = spans["source"].astype(np.int8) if version >= 2 else np.full(count, 2, np.int8)
        # The column (x, z) of every span.
        column = np.repeat(np.arange(columns), self.count)
        self.x = column % self.width
        self.z = column // self.width

    def __len__(self):
        return len(self.y)

    # Recast's x is world X and its z is minus world Y (extract.py).
    def world(self, span):
        """World (X, Y, height) of a span's centre."""
        return (self.bmin[0] + (self.x[span] + 0.5) * self.cell,
                -(self.bmin[2] + (self.z[span] + 0.5) * self.cell),
                self.bmin[1] + self.y[span] * self.cell_height)

    def column_of(self, world_x, world_y):
        gx = int((world_x - self.bmin[0]) / self.cell)
        gz = int((-world_y - self.bmin[2]) / self.cell)
        if 0 <= gx < self.width and 0 <= gz < self.depth:
            return gx + gz * self.width
        return None

    def spans_in(self, column):
        return range(self.first[column], self.first[column] + self.count[column])

    def components(self):
        """A component number for every span (4-connected through neighbours)."""
        label = np.full(len(self), -1, np.int64)
        current = 0
        for start in range(len(self)):
            if label[start] >= 0:
                continue
            label[start] = current
            stack = [start]
            while stack:
                span = stack.pop()
                for other in self.n[span]:
                    if other >= 0 and label[other] < 0:
                        label[other] = current
                        stack.append(other)
            current += 1
        return label


def load(region_name):
    return Grid(os.path.join(CACHE, region_name + ".bin"))


def candidates(grid, labels, x, y):
    """The pieces with a span in or next to the column under (x, y)."""
    column = grid.column_of(x, y)
    if column is None:
        return set()
    found = set()
    cx, cz = column % grid.width, column // grid.width
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            nx, nz = cx + dx, cz + dz
            if 0 <= nx < grid.width and 0 <= nz < grid.depth:
                for span in grid.spans_in(nx + nz * grid.width):
                    found.add(int(labels[span]))
    return found


def assign(grid, labels, sizes, samples):
    """Which piece each sample stood on (None where no floor is under it).

    A sample has no height, so a column can offer several pieces (a street
    and the roof above it). A walk stays on one floor until it changes on
    purpose, so each sample gets the piece that keeps the number of changes
    along the trail lowest; a tie goes to the bigger piece."""
    options = [sorted(candidates(grid, labels, x, y)) for x, y in samples]
    cost, back = [], []
    for i, opts in enumerate(options):
        here, links = {}, {}
        previous = cost[-1] if cost else {}
        for piece in opts:
            bias = 1e-6 / max(sizes[piece], 1)
            if not previous:
                here[piece], links[piece] = bias, None
                continue
            best = min(previous, key=lambda q: previous[q] + (q != piece))
            here[piece] = previous[best] + (best != piece) + bias
            links[piece] = best
        if not opts:
            here, links = dict(previous), {q: q for q in previous}
        cost.append(here)
        back.append(links)
    out = [None] * len(samples)
    if not cost or not cost[-1]:
        return out
    piece = min(cost[-1], key=cost[-1].get)
    for i in range(len(samples) - 1, -1, -1):
        out[i] = piece if options[i] else None
        piece = back[i].get(piece, piece) if back[i] else piece
        if piece is None:
            break
    return out


def reachable(grid, region, min_samples=10):
    """The pieces the recorded trails walked on, and where they went from
    one piece to another (a lift, or a step Recast would not climb).

    Returns (mask of kept spans, labels, [(piece, samples)], changes) where a
    change is {"from", "to", "a", "b"}: the pieces and the world (X, Y) of
    the last sample on one and the first on the other."""
    labels = grid.components()
    sizes = np.bincount(labels)
    counts, changes = {}, []
    for trail in trails.for_map(region["map"]):
        samples = [s["w"] for s in trail["samples"] if s["w"]]
        pieces = assign(grid, labels, sizes, samples)
        last = None
        for i, piece in enumerate(pieces):
            if piece is None:
                continue
            counts[piece] = counts.get(piece, 0) + 1
            if last is not None and pieces[last] != piece:
                changes.append({"from": pieces[last], "to": piece, "a": samples[last], "b": samples[i]})
            last = i
    kept = sorted(((piece, n) for piece, n in counts.items() if n >= min_samples), key=lambda item: -item[1])
    keep = {piece for piece, _ in kept}
    changes = [c for c in changes if c["from"] in keep and c["to"] in keep]
    mask = np.isin(labels, list(keep))
    return mask, labels, kept, changes


def sample_heights(grid, labels, samples):
    """The height of the floor each sample stood on (None where there is no
    floor under it), from the piece `assign` gives it."""
    sizes = np.bincount(labels[labels >= 0]) if len(labels) else []
    pieces = assign(grid, labels, sizes, samples)
    out = []
    for (x, y), piece in zip(samples, pieces):
        column = grid.column_of(x, y)
        best = None
        if column is not None and piece is not None:
            cx, cz = column % grid.width, column // grid.width
            for dx in (0, -1, 1):
                for dz in (0, -1, 1):
                    nx, nz = cx + dx, cz + dz
                    if 0 <= nx < grid.width and 0 <= nz < grid.depth and best is None:
                        for span in grid.spans_in(nx + nz * grid.width):
                            if labels[span] == piece:
                                best = grid.world(span)[2]
                                break
        out.append(best)
    return out


def water(grid, region_name, depth=1.2, reach=30.0):
    """Which spans lie under water: in a liquid tile (extract.py's
    .liquid.json) and more than `depth` yards below its surface, so a player
    there swims (and not more than `reach` below, which would be another
    floor under the pool). All False when there is no liquid file."""
    import json
    out = np.zeros(len(grid), bool)
    path = os.path.join(CACHE, region_name + ".liquid.json")
    if not os.path.exists(path):
        return out
    liquid = json.load(open(path))
    half = liquid["tile"] / 2
    height = grid.bmin[1] + grid.y * grid.cell_height
    for x, y, surface in liquid["tiles"]:
        # Columns under the tile: Recast x is world X, z is minus world Y.
        x0 = int((x - half - grid.bmin[0]) / grid.cell)
        x1 = int((x + half - grid.bmin[0]) / grid.cell)
        z0 = int((-(y + half) - grid.bmin[2]) / grid.cell)
        z1 = int((-(y - half) - grid.bmin[2]) / grid.cell)
        for gz in range(max(z0, 0), min(z1 + 1, grid.depth)):
            for gx in range(max(x0, 0), min(x1 + 1, grid.width)):
                column = gx + gz * grid.width
                for span in range(grid.first[column], grid.first[column] + grid.count[column]):
                    if surface - reach < height[span] < surface - depth:
                        out[span] = True
    return out
