#!/usr/bin/env python3
"""Wall-hugging lanes: a place as rooms, the doorways between them, and a
few short lines across each room that keep a couple of yards off its walls.

    python3 Tools/ClientMap/methods/lanes.py venturemine

One of the ways of pathing a place the viewer compares (view.py's
`method_overlays`); skeleton.py's centre lines are the other. Built from the
same navmesh, in five steps:

  1. The floor. The navmesh walks slopes up to 50 degrees, so rock faces
     and ledges count as floor. Here a slope over 35 degrees is not floor
     unless it is the way between two floors (a ramp: only the part of it
     within a few yards of the shortest way up is kept); flat patches under
     25 square yards that lead nowhere go (ledges), and so does anything
     under 2 yd wide that leads nowhere (the floor is opened by 1 yd: shrunk
     and grown again, and only the narrow bits that join two pieces are put
     back).
  2. Rooms. The floor's distance to the nearest wall has a peak in the
     middle of every room; each span goes to the peak it climbs to, and two
     neighbouring basins are one room unless the way between them narrows
     to under 60% of the smaller one (a doorway). Obstacles under 10 square
     yards are filled first, so a pillar does not split a hall; rooms under
     150 square yards join a neighbour. A room never lies over itself (no
     two of its spans in one map column). The rooms then grow back over the
     floor step 1 dropped, so a target on a rock face is still placed on
     its own level; lanes may cross that floor only at three times the cost.
  3. Doorways: where two rooms touch, the stretch of their shared edge,
     passed at the two cells either side with the most room round them, or,
     when it is wider than 8 yd, at both its ends a couple of yards off the
     wall. The place's ways out are doorways with one room.
  4. Lanes: in each room, for each pair of its doorway passes, the cheapest
     way across on the room's own cells, where a step costs its length
     times 1 two to three and a half yards off a wall, more right against
     it, and up to 2 times in the open. The cost is eased until the lane is
     at most `STRETCH` (25%) longer than the shortest way across. The lane
     keeps only the points where it must turn (3 yd off its cells at most,
     never nearer a wall than 1 yd unless it already ran there). A pillar
     does not count as a wall for the cost, though the lane goes round it.
  5. Outlines: each room's edge, simplified to 0.8 yd without leaving the
     floor, its small holes (pillars) as circles, so the game can tell which
     room a map position is in and whether a straight line in a room is
     clear.

The router (methods/lanes.js, the same algorithm the addon would run) takes
the room of the start and of the target from the outlines (the addon keeps
the player's room as a state, changed through doorways), joins each to the
lane points of its room it can see (round the room's inside corners when it
sees none), runs Dijkstra over the lanes and the doorways, and pulls the
route straight where that keeps within 1.5 yd of it.

Writes .cache/<region>.method.lanes.json (the viewer's layers and the
router's data) and .cache/<region>.lanes.lua (the place as a guide would
carry it). Where the region is a benchmark (bench.ENTRANCES) it also routes
bench.py's trips through lanes.js under node, scores them
(.cache/<region>.score.lanes.json) and the cheaper variant with them
(.cache/<region>.score.lanes-offset.json: no lanes shipped, each room's
lines along its outline made in the game), and measures how much of each
route runs over open floor.
"""

import collections
import json
import math
import os
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import bench  # noqa: E402
import maps  # noqa: E402
import navgrid  # noqa: E402
import regions  # noqa: E402
import skeleton as sk  # noqa: E402
from casc import CACHE  # noqa: E402

STEEP = 35.0          # degrees: steeper is a wall, unless it is a ramp between floors
LEDGE = 25.0          # square yards: a flat patch smaller than this that leads nowhere is a ledge
RAMP_SLACK = 4.0      # yd: a ramp keeps the spans within this of the shortest way up it
SHAVE = 1.0           # yd: the floor is opened by this much
PILLAR = 10.0         # square yards: an obstacle this small is filled for rooms and the wall cost
DOOR_RATIO = 0.6      # a doorway narrows to under this share of the smaller room
DOOR_WIDEST = 8.0     # yd: a wider doorway is passed at both its ends, not its middle
PERSIST = 1.0         # yd: a peak this little above the way to its neighbour is not a room
SMALLEST_ROOM = 150.0 # square yards: a smaller room joins its neighbour
BAND = (2.0, 3.5)     # yd from a wall: a lane costs x1 here
OPEN = 8.0            # ... rising to x2 at this far from a wall
STRETCH = 1.25        # a lane is at most this much longer than the shortest way across
LANE_TOLERANCE = 3.0  # yd: how far a lane may leave its cells when simplified
LANE_CLEAR = 1.0      # yd: ... as long as it keeps this far off every wall
EDGE_TOLERANCE = 0.8  # yd: the same for the room outlines
PILLAR_CIRCLE = 60.0  # square yards: a smaller hole in a room ships as a circle
OPEN_FLOOR = 6.0      # yd from any wall: the open floor where mobs stand
ROUGH = 3.0           # a lane over dropped floor (rock face, ledge) costs this much more a yard


def say(*args):
    print(*args, file=sys.stderr)


# ---- The floor ----------------------------------------------------------------

def neighbour(work, spans, d, mask):
    """The neighbour of each of `spans` in direction d, -1 where there is
    none on `mask`."""
    out = np.where(spans >= 0, work.n[np.maximum(spans, 0), d], -1)
    ok = out >= 0
    ok[ok] = mask[out[ok]]
    return np.where(ok, out, -1)


def slope(work, mask):
    """Each span's slope in degrees, from the heights two spans away either
    side (one where the floor ends), across and down."""
    h = work.y.astype(np.float64) * work.cell_height
    spans = np.arange(len(work))
    grad = []
    for back, ahead in ((0, 2), (3, 1)):
        ends, steps = [], []
        for d in (back, ahead):
            one = neighbour(work, spans, d, mask)
            two = neighbour(work, one, d, mask)
            end = np.where(two >= 0, two, np.where(one >= 0, one, spans))
            ends.append(end)
            steps.append(np.where(two >= 0, 2, np.where(one >= 0, 1, 0)))
        run = (steps[0] + steps[1]) * work.cell
        grad.append(np.where(run > 0, (h[ends[1]] - h[ends[0]]) / np.maximum(run, 1e-9), 0.0))
    return np.degrees(np.arctan(np.hypot(grad[0], grad[1])))


def links4(work, mask):
    from scipy.sparse import coo_matrix
    rows = np.repeat(np.arange(len(work)), 4)
    cols = work.n.reshape(-1)
    ok = (cols >= 0) & mask[rows]
    ok[ok] = mask[cols[ok]]
    return coo_matrix((np.ones(ok.sum(), np.int8), (rows[ok], cols[ok])), shape=(len(work), len(work))).tocsr()


def components(work, mask):
    """A piece number for each span of `mask` (4-connected), -1 elsewhere."""
    from scipy.sparse.csgraph import connected_components
    _, labels = connected_components(links4(work, mask), directed=False)
    labels = labels.astype(np.int64)
    labels[~mask] = -1
    # Renumber densely.
    used = np.unique(labels[mask])
    out = np.full(len(work), -1, np.int64)
    out[mask] = np.searchsorted(used, labels[mask])
    return out


def spread(work, mask, sources, limit):
    """Distance along `mask` from `sources` in distance field units (2 a
    straight step, 3 a diagonal), up to `limit`; larger elsewhere."""
    ring = sk.rings(work, mask)
    big = 1 << 20
    dist = np.where(sources & mask, 0, big).astype(np.int64)
    steps = [2, 3, 2, 3, 2, 3, 2, 3]
    for _ in range(limit // 2 + 2):
        best = dist.copy()
        for k in range(8):
            other = ring[:, k]
            ok = (other >= 0) & mask
            best = np.minimum(best, np.where(ok, dist[np.maximum(other, 0)] + steps[k], big))
        best[~mask] = big
        if (best == dist).all():
            break
        dist = best
    return dist


def base_floor(region_name):
    """(work, mask, entrance spans): the floor the place is made from, as
    bench.py takes it where the region is a benchmark (the piece its
    entrance stands on), else the navmesh's pieces of 500 square yards or
    more, cut to the way into the models, that the biggest reaches on foot
    or by lift."""
    region = regions.REGIONS[region_name]
    base = navgrid.load(region_name)
    work = sk.Work(base)
    work.source = base.source
    ends = []
    if region_name in bench.ENTRANCES:
        _, mask = bench.floor(region_name)
        work.dist = sk.distance_field(work, mask)
        ends.append(bench.nearest_span(work, mask, *bench.ENTRANCES[region_name]))
    else:
        labels = base.components()
        sizes = np.bincount(labels)
        mask = sizes[labels] * base.cell ** 2 >= 500.0
        if region.get("terrain") == "approach":
            mask &= sk.near_models(base, region.get("approach", 30.0))
        pieces = components(work, mask)
        # Lifts join the pieces at their top and bottom.
        parent = list(range(int(pieces.max()) + 1))

        def root(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for at in region.get("lifts", []):
            x, y = regions.to_world(region["map"], *at)
            near = {int(pieces[s]) for s in sk.floors_near(work, mask, x, y, reach=6.0)}
            near = sorted(near)
            for other in near[1:]:
                parent[root(other)] = root(near[0])
        roots = np.array([root(i) for i in range(len(parent))])
        group = np.where(mask, roots[np.maximum(pieces, 0)], -1)
        sizes = np.bincount(group[mask])
        mask = group == int(np.argmax(sizes))
        work.dist = sk.distance_field(work, mask)
    for at in region.get("exits", []):
        x, y = regions.to_world(region["map"], *at)
        span = bench.nearest_span(work, mask, x, y, reach=20.0)
        if span is not None:
            ends.append(span)
    return work, mask, [e for e in ends if e is not None]


def filter_floor(work, mask, ends):
    """The floor without rock faces, ledges and slivers (step 1). Returns
    (floor mask, {what was dropped: mask})."""
    from scipy.sparse.csgraph import dijkstra
    area = work.cell ** 2
    steep = mask & (slope(work, mask) > STEEP)
    flat = mask & ~steep
    flat_piece = components(work, flat)
    flat_area = np.bincount(flat_piece[flat]) * area
    big = flat & (flat_area[np.maximum(flat_piece, 0)] >= LEDGE)
    rest = mask & ~big
    cluster = components(work, rest)
    keep = big.copy()
    n_clusters = int(cluster.max()) + 1 if rest.any() else 0
    # Which big flat pieces each cluster of the rest touches, and where.
    touch = collections.defaultdict(lambda: collections.defaultdict(list))
    rest_spans = np.nonzero(rest)[0]
    for d in range(4):
        other = work.n[rest_spans, d]
        ok = other >= 0
        ok[ok] = big[other[ok]]
        for s, o in zip(rest_spans[ok], other[ok]):
            touch[int(cluster[s])][int(flat_piece[o])].append(int(s))
    ramps = 0
    links = None
    for c in range(n_clusters):
        sides = touch.get(c)
        if not sides or len(sides) < 2:
            continue
        if links is None:
            links = bench.links8(work, rest)
        spans = np.nonzero(cluster == c)[0]
        sub = links[spans][:, spans]
        index = {int(s): i for i, s in enumerate(spans)}
        # Distance from each side, then keep what lies near the shortest
        # way between some two sides.
        far = {}
        for piece, starts in sides.items():
            rows = sorted({index[s] for s in starts})
            far[piece] = dijkstra(sub, indices=rows, min_only=True)
        near = np.zeros(len(spans), bool)
        keys = sorted(far)
        for i in range(len(keys)):
            for j in range(i + 1, len(keys)):
                total = far[keys[i]] + far[keys[j]]
                best = total.min()
                if np.isfinite(best):
                    near |= total <= best + RAMP_SLACK
        keep[spans[near]] = True
        ramps += 1
    dropped_steep = steep & ~keep
    dropped_ledge = mask & ~steep & ~keep
    # Open by SHAVE: shrink, grow back, and put back the narrow bits that
    # join two pieces of what is left.
    dist = sk.distance_field(work, keep)
    units = int(round(SHAVE * 2 / work.cell))
    core = keep & (dist >= units)
    opened = keep & (spread(work, keep, core, units) <= units)
    piece = components(work, opened)
    thin = keep & ~opened
    thin_piece = components(work, thin)
    joins = collections.defaultdict(set)
    thin_spans = np.nonzero(thin)[0]
    for d in range(4):
        other = work.n[thin_spans, d]
        ok = other >= 0
        ok[ok] = opened[other[ok]]
        for s, o in zip(thin_spans[ok], other[ok]):
            joins[int(thin_piece[s])].add(int(piece[o]))
    back = [t for t, ps in joins.items() if len(ps) >= 2]
    floor = opened | (thin & np.isin(thin_piece, back))
    # Only what the entrances stand on (or the biggest piece).
    piece = components(work, floor)
    wanted = {int(piece[e]) for e in ends if floor[e]}
    if not wanted:
        wanted = {int(np.argmax(np.bincount(piece[floor])))}
    floor = np.isin(piece, sorted(wanted)) & floor
    dropped_thin = keep & ~floor
    say("floor: %d sq yd; dropped %d sq yd of rock face, %d of ledges, %d of slivers and cut-off bits; %d ramps" % (
        floor.sum() * area, dropped_steep.sum() * area, dropped_ledge.sum() * area, dropped_thin.sum() * area, ramps))
    return floor, {"rock face": dropped_steep, "ledges": dropped_ledge, "slivers": dropped_thin}


# ---- Rooms --------------------------------------------------------------------

def fill_pillars(work, floor):
    """The floor with obstacles under PILLAR square yards filled (extra
    spans on the end of `work`, marked virtual). Returns the grown mask."""
    labels = np.where(floor, 0, -1)
    grown = sk.fill_holes(work, floor.copy(), labels, [(0, int(floor.sum()))], most=PILLAR)
    return grown


def clearance(dist, cell):
    """Distance field units to yards from a wall (the navmesh keeps the
    player's radius off it, added back)."""
    return dist * cell / 2.0 + 0.5


class Sets:
    """Union-find over basins, each with its peak and the map columns it holds."""

    def __init__(self):
        self.parent, self.peak, self.columns = [], [], []

    def add(self, peak, column):
        self.parent.append(len(self.parent))
        self.peak.append(peak)
        self.columns.append({column})
        return len(self.parent) - 1

    def root(self, i):
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def overlap(self, a, b):
        small, large = sorted((self.columns[a], self.columns[b]), key=len)
        return any(c in large for c in small)

    def join(self, a, b):
        if len(self.columns[a]) < len(self.columns[b]):
            a, b = b, a
        self.parent[b] = a
        self.peak[a] = max(self.peak[a], self.peak[b])
        self.columns[a] |= self.columns[b]
        self.columns[b] = set()
        return a


def split_rooms(work, floor):
    """A room number for every span of `floor` (step 2), -1 elsewhere."""
    dist = sk.distance_field(work, floor)
    ring = sk.rings(work, floor)
    width = int(work.x.max()) + 2
    column = work.x + work.z * width
    spans = np.nonzero(floor)[0]
    order = spans[np.argsort(-dist[spans], kind="stable")]
    label = np.full(len(work), -1, np.int64)
    sets = Sets()
    cell = work.cell
    for s in order:
        s = int(s)
        c = clearance(dist[s], cell)
        col = int(column[s])
        roots = []
        for o in ring[s]:
            if o >= 0 and label[o] >= 0:
                r = sets.root(int(label[o]))
                if r not in roots:
                    roots.append((r))
        # Join the basin of the highest neighbour that does not already
        # hold this column.
        roots.sort(key=lambda r: -sets.peak[r])
        home = None
        for r in roots:
            if col not in sets.columns[r]:
                home = r
                break
        if home is None:
            home = sets.add(c, col)
        else:
            sets.columns[home].add(col)
        label[s] = home
        for r in roots:
            r, home = sets.root(r), sets.root(home)
            if r == home:
                continue
            low = min(sets.peak[r], sets.peak[home])
            if (low - c < PERSIST or c >= DOOR_RATIO * low) and not sets.overlap(r, home):
                sets.join(r, home)
    for s in spans:
        label[s] = sets.root(int(label[s]))
    # Small rooms join the neighbour they share most edge with.
    area = work.cell ** 2
    for _ in range(6):
        ids, counts = np.unique(label[spans], return_counts=True)
        size = dict(zip(ids.tolist(), (counts * area).tolist()))
        small = {r for r, a in size.items() if a < SMALLEST_ROOM}
        if not small:
            break
        border = collections.Counter()
        for s in np.nonzero(np.isin(label, list(small)))[0]:
            for o in work.n[s]:
                if o >= 0 and label[o] >= 0 and label[o] != label[s]:
                    border[(int(label[s]), int(label[o]))] += 1
        into = {}
        for (a, b), n in border.most_common():
            if a in into or b in into or a in into.values():
                continue
            if not sets.overlap(sets.root(a), sets.root(b)):
                into[a] = b
        if not into:
            break
        for a, b in into.items():
            ra, rb = sets.root(a), sets.root(b)
            joined = sets.join(ra, rb)
            label[label == a] = joined
            label[label == b] = joined
    ids = np.unique(label[spans])
    out = np.full(len(work), -1, np.int64)
    out[spans] = np.searchsorted(ids, label[spans])
    return out, dist


def grow_rooms(work, whole, room):
    """Rooms grown over the floor that was dropped (rock faces, ledges,
    slivers), each span to the room nearest along the floor, so a target
    standing there is still placed on its own level. A room never takes a
    second span in one map column."""
    width = int(work.x.max()) + 2
    column = work.x + work.z * width
    room = room.copy()
    taken = set(zip(column[room >= 0].tolist(), room[room >= 0].tolist()))
    frontier = list(np.nonzero(room >= 0)[0])
    while frontier:
        grown = []
        for s in frontier:
            r = int(room[s])
            for o in work.n[s]:
                o = int(o)
                if o < 0 or not whole[o] or room[o] >= 0:
                    continue
                key = (int(column[o]), r)
                if key in taken:
                    continue
                room[o] = r
                taken.add(key)
                grown.append(o)
        frontier = grown
    return room


# ---- Doorways -----------------------------------------------------------------

def find_doors(work, floor, room):
    """The doorways (step 3): where two rooms touch, each stretch of their
    shared edge. Returns a list of {"rooms": (a, b), "cells": {room: [spans]}}
    and a dict (span, other room) -> door number."""
    ring = sk.rings(work, floor)
    edge = collections.defaultdict(set)   # (a, b) -> spans on either side
    spans = np.nonzero(floor)[0]
    for d in range(4):
        other = work.n[spans, d]
        ok = other >= 0
        ok[ok] = floor[other[ok]]
        s, o = spans[ok], other[ok]
        diff = room[s] != room[o]
        for a, b in zip(s[diff], o[diff]):
            ra, rb = int(room[a]), int(room[b])
            key = (min(ra, rb), max(ra, rb))
            edge[key].add(int(a))
            edge[key].add(int(b))
    doors, door_of = [], {}
    for key in sorted(edge):
        cells = edge[key]
        seen = set()
        for start in sorted(cells):
            if start in seen:
                continue
            group, stack = [], [start]
            seen.add(start)
            while stack:
                s = stack.pop()
                group.append(s)
                for o in ring[s]:
                    o = int(o)
                    if o >= 0 and o in cells and o not in seen:
                        seen.add(o)
                        stack.append(o)
            door = {"rooms": key, "cells": {key[0]: [], key[1]: []}}
            for s in group:
                door["cells"][int(room[s])].append(s)
            if not door["cells"][key[0]] or not door["cells"][key[1]]:
                continue
            number = len(doors)
            doors.append(door)
            for r in key:
                other = key[1] if r == key[0] else key[0]
                for s in door["cells"][r]:
                    door_of[(s, other)] = number
    return doors, door_of


# ---- Rasters of a room ----------------------------------------------------------

class Raster:
    """One room on a flat grid of the map's columns, with the floor round it:
    `near` is the other spans within `margin` steps of it along the floor,
    nearest first."""

    def __init__(self, work, good, room, r, near, margin=24):
        self.r = r
        own = np.nonzero(room == r)[0]
        self.x0 = int(work.x[own].min()) - margin
        self.z0 = int(work.z[own].min()) - margin
        self.w = int(work.x[own].max()) - self.x0 + margin + 1
        self.h = int(work.z[own].max()) - self.z0 + margin + 1
        self.span = np.full((self.h, self.w), -1, np.int64)   # the room's own span
        self.local = np.zeros((self.h, self.w), np.int8)      # 1 floor, 2 filled pillar, 3 dropped floor
        self.span[work.z[own] - self.z0, work.x[own] - self.x0] = own
        # The floor round it, the nearest floor first where floors stack.
        zs, xs = work.z[near] - self.z0, work.x[near] - self.x0
        ok = (zs >= 0) & (zs < self.h) & (xs >= 0) & (xs < self.w)
        zs, xs, spans = zs[ok][::-1], xs[ok][::-1], near[ok][::-1]
        kind = lambda s: np.where(work.virtual[s], 2, np.where(good[s], 1, 3))  # noqa: E731
        self.local[zs, xs] = kind(spans)
        self.local[work.z[own] - self.z0, work.x[own] - self.x0] = kind(own)
        self.inside = self.span >= 0
        # Where a player can stand (dropped floor too: a rock face can be
        # climbed, and a target may be on it), and where the lanes run.
        self.real = (self.local == 1) | (self.local == 3)
        self.walk = self.inside & self.real
        self.rough = self.local == 3
        self.cell = work.cell
        self.work = work
        # Yards from the nearest wall (a filled pillar is not one; dropped
        # floor is).
        from scipy import ndimage
        self.yd = ndimage.distance_transform_edt((self.local == 1) | (self.local == 2)) * work.cell + work.cell / 2

    def world(self, x, z):
        w = self.work
        return (w.bmin[0] + (self.x0 + x + 0.5) * w.cell, -(w.bmin[2] + (self.z0 + z + 0.5) * w.cell))

    def clear_line(self, a, b, allowed):
        """Whether every pixel a straight line from pixel a to pixel b
        (x, z) touches is `allowed`."""
        (x0, z0), (x1, z1) = a, b
        dx, dz = x1 - x0, z1 - z0
        n = int(max(abs(dx), abs(dz)) * 3) + 1
        for k in range(n + 1):
            t = k / n
            x, z = x0 + dx * t, z0 + dz * t
            # Every pixel the line's point may round into.
            for px in {int(math.floor(x + 0.5 - 0.02)), int(math.floor(x + 0.5 + 0.02))}:
                for pz in {int(math.floor(z + 0.5 - 0.02)), int(math.floor(z + 0.5 + 0.02))}:
                    if not (0 <= px < self.w and 0 <= pz < self.h) or not allowed[pz, px]:
                        return False
        return True


def simplify(points, tolerance, ok):
    """Douglas-Peucker on pixel points, keeping the ends: a stretch becomes
    one line when no point is more than `tolerance` pixels off it and
    ok(a, b) holds for the line. Returns indices."""
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        (ax, az), (bx, bz) = points[i], points[j]
        dx, dz = bx - ax, bz - az
        length = math.hypot(dx, dz)
        worst, at = -1.0, None
        for k in range(i + 1, j):
            px, pz = points[k]
            if length < 1e-9:
                off = math.hypot(px - ax, pz - az)
            else:
                off = abs(dx * (pz - az) - dz * (px - ax)) / length
            if off > worst:
                worst, at = off, k
        if worst > tolerance or not ok(points[i], points[j]):
            keep.add(at)
            stack.append((i, at))
            stack.append((at, j))
    return sorted(keep)


def loops(inside):
    """The edges round the pixels of `inside` as closed loops of directed
    unit edges ((x, z) corner to corner, the inside on the right), each edge
    with its inside pixel and the side it faces (Recast direction)."""
    h, w = inside.shape
    pad = np.zeros((h + 2, w + 2), bool)
    pad[1:-1, 1:-1] = inside
    out_edges = collections.defaultdict(list)
    zs, xs = np.nonzero(inside)
    for z, x in zip(zs.tolist(), xs.tolist()):
        if not pad[z, x + 1]:        # above (z - 1): Recast direction 3
            out_edges[(x, z)].append(((x + 1, z), (x, z), 3))
        if not pad[z + 1, x + 2]:    # right (x + 1): direction 2
            out_edges[(x + 1, z)].append(((x + 1, z + 1), (x, z), 2))
        if not pad[z + 2, x + 1]:    # below (z + 1): direction 1
            out_edges[(x + 1, z + 1)].append(((x, z + 1), (x, z), 1))
        if not pad[z + 1, x]:        # left (x - 1): direction 0
            out_edges[(x, z + 1)].append(((x, z), (x, z), 0))
    result = []
    while out_edges:
        start = next(iter(out_edges))
        loop, corner, heading = [], start, None
        while True:
            options = out_edges.get(corner)
            if not options:
                break
            if len(options) == 1 or heading is None:
                pick = options[0]
            else:
                # At a pinch take the sharpest right turn, keeping pixels
                # that touch only at a corner apart.
                def turn(e):
                    ex, ez = e[0][0] - corner[0], e[0][1] - corner[1]
                    return -(heading[0] * ez - heading[1] * ex)
                pick = min(options, key=turn)
            options.remove(pick)
            if not options:
                del out_edges[corner]
            loop.append((corner, pick[0], pick[1], pick[2]))
            heading = (pick[0][0] - corner[0], pick[0][1] - corner[1])
            corner = pick[0]
            if corner == start:
                break
        if loop:
            result.append(loop)
    return result


def outline(raster, room, door_of, allowed):
    """The room's edge (step 5) as loops of pixel centres just inside it,
    simplified without ever leaving `allowed`. Returns [(points, open
    edges)], where points are pixel (x, z) and open edges are indices i
    whose line from point i to i + 1 is a doorway."""
    work = raster.work
    inside = raster.inside & raster.real
    # Fill holes under a square yard: noise in the navmesh, not obstacles.
    from scipy import ndimage
    holes, count = ndimage.label(~inside)
    if count:
        sizes = ndimage.sum(np.ones_like(holes), holes, range(1, count + 1))
        edge = set(np.unique(np.concatenate([holes[0], holes[-1], holes[:, 0], holes[:, -1]])).tolist())
        for i, size in enumerate(sizes):
            if i + 1 not in edge and size * raster.cell ** 2 < 1.0:
                inside |= holes == i + 1
    out = []
    for loop in loops(inside):
        chain, tags = [], []
        for corner, _, (px, pz), d in loop:
            span = raster.span[pz, px]
            tag = -1
            if span >= 0:
                other = work.n[span, d]
                if other >= 0 and room[other] >= 0 and room[other] != raster.r:
                    tag = door_of.get((int(span), int(room[other])), -1)
            if chain and chain[-1] == (px, pz):
                if tags[-1] != tag:
                    tags[-1] = -1
                continue
            chain.append((px, pz))
            tags.append(tag)
        if len(chain) > 1 and chain[0] == chain[-1]:
            if tags[0] != tags[-1]:
                tags[0] = -1
            chain.pop()
            tags.pop()
        if len(chain) < 3:
            continue
        # Split into runs of one tag, simplify each with its ends kept.
        n = len(chain)
        cuts = [i for i in range(n) if tags[i] != tags[i - 1]]
        if not cuts:
            far = max(range(n), key=lambda i: (chain[i][0] - chain[0][0]) ** 2 + (chain[i][1] - chain[0][1]) ** 2)
            cuts = [0, far]
        points, open_edges = [], []
        for k, a in enumerate(cuts):
            b = cuts[(k + 1) % len(cuts)]
            run = [chain[(a + i) % n] for i in range((b - a) % n or n)] + [chain[b]]
            tol = EDGE_TOLERANCE / raster.cell
            keep = simplify(run, tol, lambda p, q: raster.clear_line(p, q, allowed))
            is_door = tags[a] >= 0 and all(tags[(a + i) % n] == tags[a] for i in range((b - a) % n or n))
            for i in keep[:-1]:
                if is_door:
                    open_edges.append(len(points))
                points.append(run[i])
        # A door run's last edge ends on the next run's first point: already open.
        if len(points) >= 3:
            out.append((points, open_edges))
    return out


# ---- Lanes --------------------------------------------------------------------

EASE = (1.0, 0.75, 0.5, 0.35, 0.2, 0.1, 0.0)   # how much of the wall cost a lane may be given


def wall_cost(yd):
    """What a step costs per yard at `yd` from the nearest wall."""
    low, high = BAND
    return np.where(yd < low, 1.0 + (low - yd) / low,
                    np.where(yd <= high, 1.0, 1.0 + np.minimum(1.0, (yd - high) / (OPEN - high))))


def room_lanes(raster, terminals):
    """The lanes of one room (step 4): for each pair of `terminals` ((key,
    [pixel (x, z)]) with at least one walkable pixel), the pixel path of the
    cheapest way across. Returns [(key a, key b, [pixels], ease)]."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra
    cell = raster.cell
    yd = raster.yd
    walk = raster.walk
    zs, xs = np.nonzero(walk)
    index = np.full(walk.shape, -1, np.int64)
    index[zs, xs] = np.arange(len(zs))
    cost = wall_cost(yd[zs, xs]) + ROUGH * raster.rough[zs, xs]
    h, w = walk.shape
    rows, cols, length = [], [], []
    for dx, dz in ((1, 0), (0, 1), (1, 1), (1, -1)):
        tx, tz = xs + dx, zs + dz
        ok = (tx >= 0) & (tx < w) & (tz >= 0) & (tz < h)
        ok[ok] = walk[tz[ok], tx[ok]]
        if dx and dz:
            # A diagonal step only round a corner that is floor too.
            ok[ok] &= walk[zs[ok], tx[ok]] & walk[tz[ok], xs[ok]]
        a, b = np.nonzero(ok)[0], index[tz[ok], tx[ok]]
        rows += [a, b]
        cols += [b, a]
        step = cell * (math.sqrt(2) if dx and dz else 1.0)
        length += [np.full(len(a), step)] * 2
    rows, cols, length = np.concatenate(rows), np.concatenate(cols), np.concatenate(length)
    extra = (cost[rows] + cost[cols]) / 2 - 1
    ends = []
    for key, pixels in terminals:
        ids = sorted({int(index[z, x]) for x, z in pixels if walk[z, x]})
        if ids:
            ends.append((key, ids))
    if len(ends) < 2:
        return []
    found = {}

    def walked(path):
        px, pz = xs[path], zs[path]
        return float(np.hypot(np.diff(px), np.diff(pz)).sum() * cell)
    for i, (key_a, ids_a) in enumerate(ends[:-1]):
        runs = []
        for ease in EASE:
            graph = coo_matrix((length * (1 + ease * extra), (rows, cols)), shape=(len(zs), len(zs))).tocsr()
            dist, pred, _ = dijkstra(graph, indices=ids_a, min_only=True, return_predecessors=True)
            runs.append((ease, dist, pred))
        for key_b, ids_b in ends[i + 1:]:
            options = []
            for ease, dist, pred in runs:
                # The cheapest end on b's side under this cost, walked back.
                end = min(ids_b, key=lambda e: dist[e])
                if not np.isfinite(dist[end]):
                    continue
                path = [end]
                while pred[path[-1]] >= 0:
                    path.append(int(pred[path[-1]]))
                options.append((ease, path, walked(path)))
            if not options:
                continue
            shortest = options[-1][2]
            for ease, path, walk_length in options:
                if walk_length <= STRETCH * shortest + cell:
                    pixels = [(int(xs[p]), int(zs[p])) for p in path[::-1]]
                    found[(key_a, key_b)] = (pixels, ease)
                    break
    return [(a, b, pixels, ease) for (a, b), (pixels, ease) in found.items()]


# ---- The place ------------------------------------------------------------------

def loop_area(points, cell):
    """Signed area of a loop of pixel points, in square yards."""
    total = 0.0
    for i in range(len(points)):
        (ax, az), (bx, bz) = points[i - 1], points[i]
        total += ax * bz - bx * az
    return total / 2 * cell * cell


def build(region_name):
    """The place from the region's navmesh: (place, extras), where place is
    what the router and the guide get (map %, 0-based here) and extras are
    the grids behind it, for drawing."""
    region = regions.REGIONS[region_name]
    t0 = time.time()
    work, mask, ends = base_floor(region_name)
    floor, dropped = filter_floor(work, mask, ends)
    count = len(work)
    filled = fill_pillars(work, floor)
    extra = len(work) - count
    pad = lambda m: np.concatenate([m, np.zeros(extra, bool)])  # noqa: E731
    mask, floor = pad(mask), pad(floor)
    dropped = {k: pad(v) for k, v in dropped.items()}
    dropped["small obstacles (filled)"] = filled & work.virtual
    room, _ = split_rooms(work, filled)
    n_rooms = int(room.max()) + 1
    whole = filled | mask
    room = grow_rooms(work, whole, room)
    whole = room >= 0
    good = filled
    doors, door_of = find_doors(work, whole, room)
    say("%d rooms, %d doorways (%.0fs)" % (n_rooms, len(doors), time.time() - t0))

    def to_map(wx, wy):
        mx, my = regions.to_map(region["map"], wx, wy)
        return [round(mx, 2), round(my, 2)]

    # The entrances, on the floor that is left: each is a doorway with one room.
    entrances = []
    for e in ends:
        if room[e] < 0:
            x, y, h = work.world(e)
            e = bench.nearest_span(work, room >= 0, x, y, h, reach=10.0)
        if e is not None and room[e] >= 0 and all(e != f for f in entrances):
            entrances.append(int(e))

    # Where each doorway is passed: the two cells either side of it with the
    # most room round them; a doorway wider than DOOR_WIDEST is passed at
    # both its ends instead, a couple of yards off the wall (so a lane keeps
    # to its side of a wide opening). Every lane of either room through the
    # doorway starts or ends at one of these.
    clearance_field = sk.distance_field(work, whole)
    band = int(round((BAND[0] - 0.5) * 2 / work.cell))
    doors_out = []
    for door in doors:
        ra, rb = door["rooms"]
        other = set(door["cells"][rb])
        pairs = []
        for a in door["cells"][ra]:
            for b in work.n[a]:
                b = int(b)
                if b in other:
                    pairs.append((min(clearance_field[a], clearance_field[b]), a, b))
        cells = door["cells"][ra] + door["cells"][rb]
        pts = np.array([work.world(s)[:2] for s in cells])
        centre = pts.mean(axis=0)
        axis = pts - centre
        if len(pts) > 1:
            _, _, vt = np.linalg.svd(axis, full_matrices=False)
            along = axis @ vt[0]
            line_axis = vt[0]
        else:
            along, line_axis = np.zeros(1), np.array([1.0, 0.0])
        ends = pts[int(np.argmin(along))], pts[int(np.argmax(along))]
        width = float(np.hypot(*(ends[0] - ends[1]))) + work.cell
        best = max(pairs)
        chosen = [best]
        if width > DOOR_WIDEST:
            roomy = [q for q in pairs if q[0] >= min(band, best[0])]
            pos = [float((np.array(work.world(q[1])[:2]) - centre) @ line_axis) for q in roomy]
            chosen = [roomy[int(np.argmin(pos))], roomy[int(np.argmax(pos))]]
        for _, a, b in chosen:
            mid = np.array(work.world(a)[:2]) / 2 + np.array(work.world(b)[:2]) / 2
            doors_out.append({"rooms": [int(ra), int(rb)], "line": to_map(*ends[0]) + to_map(*ends[1]),
                              "at": to_map(*mid), "width": round(width, 1), "pass": {int(ra): int(a), int(rb): int(b)}})
    for e in entrances:
        x, y, _ = work.world(e)
        doors_out.append({"rooms": [int(room[e])], "line": to_map(x, y) * 2, "at": to_map(x, y), "width": 0,
                          "way out": True, "pass": {int(room[e]): int(e)}})

    # The floor within `margin` steps of each room, for its raster.
    from scipy.sparse.csgraph import dijkstra
    compact = np.nonzero(whole)[0]
    position = np.full(len(work), -1, np.int64)
    position[compact] = np.arange(len(compact))
    graph = links4(work, whole)[compact][:, compact]
    margin = 24
    rooms_out, lanes_out = [], []
    t1 = time.time()
    for r in range(n_rooms):
        own = np.nonzero(room == r)[0]
        dist = dijkstra(graph, indices=position[own], min_only=True, limit=margin, unweighted=True)
        reach = np.nonzero(np.isfinite(dist) & (dist > 0))[0]
        near = compact[reach[np.argsort(dist[reach], kind="stable")]]
        raster = Raster(work, good, room, r, near, margin)
        allowed = raster.real
        off_wall = allowed & (raster.yd >= LANE_CLEAR)
        # The outline: the loops round the floor, the small holes in it as circles.
        loops_px = outline(raster, room, door_of, allowed)
        areas = [loop_area(pts, raster.cell) for pts, _ in loops_px]
        outer = math.copysign(1, areas[int(np.argmax(np.abs(areas)))]) if areas else 1
        loops_map, pillars = [], []
        for (pts, _), area in zip(loops_px, areas):
            world = [raster.world(x, z) for x, z in pts]
            if area * outer < 0 and abs(area) < PILLAR_CIRCLE:
                cx = sum(p[0] for p in world) / len(world)
                cy = sum(p[1] for p in world) / len(world)
                radius = sum(math.hypot(p[0] - cx, p[1] - cy) for p in world) / len(world)
                pillars.append(to_map(cx, cy) + [round(radius, 1)])
            else:
                loops_map.append([c for p in world for c in to_map(*p)])
        # The lanes, between every two of the room's doorways and ways out.
        terminals, my_doors = [], []
        for d, door in enumerate(doors_out):
            if r in door["pass"]:
                s_ = door["pass"][r]
                my_doors.append(d)
                terminals.append((d, [(int(work.x[s_]) - raster.x0, int(work.z[s_]) - raster.z0)]))
        for key_a, key_b, pixels, ease in room_lanes(raster, terminals):
            # Off the walls, or where the lane itself already ran (a doorway
            # or a passage narrower than twice LANE_CLEAR).
            ok = off_wall.copy()
            ok[[z for _, z in pixels], [x for x, _ in pixels]] = True
            keep = simplify(pixels, LANE_TOLERANCE / raster.cell, lambda p, q: raster.clear_line(p, q, ok))
            line = [c for i in keep for c in to_map(*raster.world(*pixels[i]))]
            walked = sum(math.hypot(pixels[k + 1][0] - pixels[k][0], pixels[k + 1][1] - pixels[k][1])
                         for k in range(len(pixels) - 1)) * raster.cell
            lanes_out.append({"room": r, "from": key_a, "to": key_b, "points": line, "ease": ease,
                              "yd": round(walked, 1)})
        # How much of the room is open floor, far from any wall.
        inside = raster.inside & raster.real
        area = float(inside.sum()) * raster.cell ** 2
        open_share = float((raster.yd[inside] > OPEN_FLOOR).sum()) * raster.cell ** 2 / max(area, 1)
        heights = work.y[own] * work.cell_height + work.bmin[1]
        rooms_out.append({
            "outline": loops_map, "pillars": pillars, "open": round(open_share, 2),
            "doors": my_doors, "area": round(area),
            "widest": round(float(raster.yd[inside].max()) * 2, 1) if inside.any() else 0,
            "low": round(float(heights.min()), 1), "high": round(float(heights.max()), 1),
        })
    say("outlines and %d lanes (%.0fs)" % (len(lanes_out), time.time() - t1))
    b = maps.get(region["map"])
    place = {"region": region_name, "map": region["map"], "name": regions.name(region),
             "yards": [abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100],
             "rooms": rooms_out, "doors": [{k: v for k, v in d.items() if k != "pass"} for d in doors_out],
             "lanes": lanes_out}
    extras = {"work": work, "floor": floor, "filled": filled, "room": room, "dropped": dropped, "mask": mask}
    return place, extras


def router_data(place, offset=False):
    """What the router reads (0-based, map %): the place as the guide ships
    it. With `offset`, no lanes: each room says how far off its walls the
    game should make them."""
    rooms = []
    for room in place["rooms"]:
        out = {"outline": room["outline"], "pillars": [c for p in room["pillars"] for c in p], "open": room["open"]}
        if offset:
            out["offset"] = round(min(2.5, max(1.0, room["widest"] / 5)), 1)
        rooms.append(out)
    doors = [{"rooms": d["rooms"], "at": d["at"], "line": d["line"]} for d in place["doors"]]
    lanes = [] if offset else [{"room": l["room"], "from": l["from"], "to": l["to"], "points": l["points"]}
                               for l in place["lanes"]]
    return {"yards": place["yards"], "rooms": rooms, "doors": doors, "lanes": lanes, "offset": offset}


# ---- The place as a guide carries it --------------------------------------------

def numbers(values):
    return ", ".join(("%.2f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v) for v in values)


def lua(place, data):
    """The place as guide source: every table either a list or keys, never
    both; rooms, doorways and lanes numbered from 1 by their place in the list."""
    out = ["-- %s: %d rooms, %d doorways, %d lanes (Tools/ClientMap/methods/lanes.py)" % (
        place["name"], len(data["rooms"]), len(data["doors"]), len(data["lanes"])),
        "place = {", "    map = %d," % place["map"], "    rooms = {"]
    for room in data["rooms"]:
        loops = ", ".join("{ %s }" % numbers(loop) for loop in room["outline"])
        line = "        { outline = { %s }" % loops
        if room["pillars"]:
            line += ", pillars = { %s }" % numbers(room["pillars"])
        if room["open"]:
            line += ", open = %s" % numbers([room["open"]])
        if room.get("offset"):
            line += ", offset = %s" % numbers([room["offset"]])
        out.append(line + " },")
    out.append("    },")
    out.append("    doors = {")
    for door in data["doors"]:
        out.append("        { rooms = { %s }, at = { %s }, line = { %s } }," % (
            numbers([r + 1 for r in door["rooms"]]), numbers(door["at"]), numbers(door["line"])))
    out.append("    },")
    if data["lanes"]:
        out.append("    lanes = {")
        for lane in data["lanes"]:
            out.append("        { room = %d, from = %d, to = %d, points = { %s } }," % (
                lane["room"] + 1, lane["from"] + 1, lane["to"] + 1, numbers(lane["points"])))
        out.append("    },")
    out.append("}")
    return "\n".join(out) + "\n"


# ---- Running the router -----------------------------------------------------------

NODE_RUN = r"""
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const router = require(process.argv[2]);
const yd = (a, b) => Math.hypot((a[0] - b[0]) * input.yards[0], (a[1] - b[1]) * input.yards[1]);
let t0 = process.hrtime.bigint();
router.prepare(input.data);
const prepare = Number(process.hrtime.bigint() - t0) / 1e6;
const out = [], ms = [];
for (const [s, t] of input.trips) {
  t0 = process.hrtime.bigint();
  const r = router.route(input.data, s, t, { yd, yards: input.yards });
  ms.push(Number(process.hrtime.bigint() - t0) / 1e6);
  out.push(r ? r.points : null);
}
console.log(JSON.stringify({ routes: out, ms, prepare }));
"""


def run_js(data, trips):
    """Routes `trips` ([[start, target], ...] in map %) through lanes.js
    under node, as the viewer runs it. Returns {routes, ms, prepare}."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "input.json"), "w") as handle:
            json.dump({"data": data, "yards": data["yards"], "trips": trips}, handle)
        with open(os.path.join(tmp, "run.js"), "w") as handle:
            handle.write(NODE_RUN)
        out = subprocess.run(["node", os.path.join(tmp, "run.js"), os.path.join(HERE, "lanes.js"),
                              os.path.join(tmp, "input.json")], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit("node: " + out.stderr)
    return json.loads(out.stdout)


def open_share(region_name, case, points):
    """The share of a route's length more than OPEN_FLOOR yd from any wall,
    walked leg by leg over the bench floor as bench.check walks it."""
    grid, mask, _ = bench.load(region_name)
    region = regions.REGIONS[region_name]
    span = case["from"]["span"]
    total = far = 0.0
    for i in range(1, len(points)):
        x0, y0 = regions.to_world(region["map"], *points[i - 1])
        x1, y1 = regions.to_world(region["map"], *points[i])
        column = grid.grid.column_of(x1, y1)
        if column is None:
            continue
        tx, tz = column % grid.grid.width, column // grid.grid.width
        sx, sz = int(grid.x[span]), int(grid.z[span])
        steps = max(abs(tx - sx), abs(tz - sz))
        here = span
        for k in range(1, steps + 1):
            cx, cz = sx + round((tx - sx) * k / steps), sz + round((tz - sz) * k / steps)
            end, _ = bench.walk(grid, mask, here, cx, cz)
            if end < 0:
                end = bench.nearest_span(grid, mask, *regions.to_world(region["map"], *points[i]),
                                         grid.world(here)[2], reach=10.0)
                if end is None:
                    break
                here = end
                break
            step = math.hypot(cx - int(grid.x[here]), cz - int(grid.z[here])) * grid.cell
            yd = grid.dist[end] * grid.cell / 2 + 0.5
            total += step
            if yd > OPEN_FLOOR:
                far += step
            here = end
        span = here
    return far, total


def open_summary(region_name, routes):
    """(share of all route length on open floor, per kind) for routes in bench order."""
    _, _, bench_data = bench.load(region_name)
    kinds = collections.defaultdict(lambda: [0.0, 0.0])
    for case, points in zip(bench_data["cases"], routes):
        if points:
            far, total = open_share(region_name, case, points)
            kinds[case["kind"]][0] += far
            kinds[case["kind"]][1] += total
            kinds["all"][0] += far
            kinds["all"][1] += total
    return {k: round(f / t, 3) if t else None for k, (f, t) in kinds.items()}


# ---- The viewer's layers ------------------------------------------------------------

def ring_of(points_flat):
    return [[points_flat[i], points_flat[i + 1]] for i in range(0, len(points_flat), 2)]


def circle(x, y, r, yards):
    return [[round(x + r * math.cos(a * math.pi / 6) / yards[0], 3), round(y + r * math.sin(a * math.pi / 6) / yards[1], 3)]
            for a in range(12)]


def dropped_shapes(place, extras, colour):
    """The dropped floor as polygons, one set per kind."""
    work = extras["work"]
    region = regions.REGIONS[place["region"]]
    out = []
    for name, m in extras["dropped"].items():
        spans = np.nonzero(m)[0]
        if not len(spans):
            continue
        x0, z0 = int(work.x[spans].min()), int(work.z[spans].min())
        img = np.zeros((int(work.z[spans].max()) - z0 + 1, int(work.x[spans].max()) - x0 + 1), bool)
        img[work.z[spans] - z0, work.x[spans] - x0] = True
        rings = []
        for loop in loops(img):
            pts = [(c[0], c[1]) for c, _, _, _ in loop]
            keep = simplify(pts, 0.6 / work.cell, lambda p, q: True) if len(pts) > 3 else range(len(pts))
            ring = []
            for i in keep:
                x, z = pts[i]
                wx = work.bmin[0] + (x0 + x) * work.cell
                wy = -(work.bmin[2] + (z0 + z) * work.cell)
                mx, my = regions.to_map(region["map"], wx, wy)
                ring.append([round(mx, 3), round(my, 3)])
            if len(ring) >= 3:
                rings.append(ring)
        if rings:
            out.append({"rings": rings, "fill": colour[name], "stroke": "none", "opacity": 0.5,
                        "tip": "dropped: %s (%d sq yd)" % (name, len(spans) * work.cell ** 2)})
    return out


def overlay(place, extras, data, size, score, shares, offset_score):
    yards = place["yards"]
    room_shapes, pillar_shapes = [], []
    for i, room in enumerate(place["rooms"]):
        open_room = room["open"] > 0.1
        tip = "room %d: %d sq yd, %d%% open floor, widest %.0f yd, floor %.0f to %.0f, doorways %s" % (
            i + 1, room["area"], room["open"] * 100, room["widest"], room["low"], room["high"],
            ", ".join(str(d + 1) for d in room["doors"]))
        room_shapes.append({"rings": [ring_of(l) for l in room["outline"]], "stroke": "#e0a040" if open_room else "#8090a0",
                            "fill": "#e0a040" if open_room else "#8090a0", "opacity": 0.25, "width": 1, "tip": tip})
        for x, y, r in room["pillars"]:
            pillar_shapes.append({"poly": circle(x, y, r, yards), "stroke": "#ff60c0", "width": 1,
                                  "tip": "room %d: pillar, %.1f yd across" % (i + 1, 2 * r)})
    door_shapes = []
    for i, d in enumerate(place["doors"]):
        tip = "doorway %d: rooms %s, %.0f yd wide" % (i + 1, " and ".join(str(r + 1) for r in d["rooms"]), d["width"])
        if d.get("way out"):
            door_shapes.append({"dot": d["at"], "r": 5, "fill": "#ff4040", "tip": "way out %d: room %d" % (i + 1, d["rooms"][0] + 1)})
        else:
            door_shapes.append({"line": ring_of(d["line"]), "stroke": "#ffffff", "width": 3, "tip": tip})
            door_shapes.append({"dot": d["at"], "r": 2.5, "fill": "#ffffff", "tip": tip})
    lane_shapes = []
    for l in place["lanes"]:
        lane_shapes.append({"line": ring_of(l["points"]), "stroke": "#50e090", "width": 2,
                            "tip": "room %d: doorway %d to %d, %.0f yd%s" % (
                                l["room"] + 1, l["from"] + 1, l["to"] + 1, l["yd"],
                                "" if l["ease"] >= 1 else ", wall cost eased to %d%%" % (l["ease"] * 100))})
    colour = {"rock face": "#ff8030", "ledges": "#d0d040", "slivers": "#808080", "small obstacles (filled)": "#ff60c0"}
    stats = ["%d rooms, %d doorways, %d lanes (%d points); %d bytes of guide source" % (
        len(place["rooms"]), len(place["doors"]), len(place["lanes"]),
        sum(len(l["points"]) // 2 for l in place["lanes"]), size)]
    if score:
        stats.append("bench: walkable %d/%d, reached %d, ratio %.3f (worst %.2f), %.1f bends, %.2f ms" % (
            score["walkable"], score["cases"], score["reached"], score["ratio_mean"] or 0,
            score["ratio_worst"] or 0, score["bends_mean"], score["ms_mean"]))
    if shares:
        stats.append("route length over %.0f yd from a wall: %.0f%% (truth %.0f%%, today's place %.0f%%)" % (
            OPEN_FLOOR, 100 * shares["lanes"]["all"], 100 * shares["truth"]["all"], 100 * shares["current"]["all"]))
    if offset_score:
        stats.append("offset variant (no lanes shipped): walkable %d/%d, reached %d, ratio %.3f" % (
            offset_score["walkable"], offset_score["cases"], offset_score["reached"], offset_score["ratio_mean"] or 0))
    return {"name": "Wall-hugging lanes", "colour": "#50e090", "stats": stats, "data": data,
            "layers": [
                {"name": "rooms", "on": True, "shapes": room_shapes,
                 "note": "each room's outline, as the game tells which room a spot is in; orange: rooms with open floor"},
                {"name": "doorways", "on": True, "shapes": door_shapes,
                 "note": "white: the doorways between rooms (the dot is where a route passes); red: ways out"},
                {"name": "lanes", "on": True, "shapes": lane_shapes,
                 "note": "green: the lanes across each room, a couple of yards off the walls"},
                {"name": "pillars", "on": False, "shapes": pillar_shapes,
                 "note": "small obstacles, shipped as circles"},
                {"name": "dropped", "on": False, "shapes": dropped_shapes(place, extras, colour),
                 "note": "orange: rock faces over %.0f degrees; yellow: ledges; grey: slivers and cut-off bits; "
                         "pink: small obstacles filled for rooms" % STEEP},
            ]}


# ---- Main -----------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    region_name = next((a for a in args if a in regions.REGIONS), "venturemine")
    place, extras = build(region_name)
    data = router_data(place)
    source = lua(place, data)
    size = len(source.encode("ascii"))
    with open(os.path.join(CACHE, region_name + ".lanes.lua"), "w", encoding="ascii") as handle:
        handle.write(source)
    offset_data = router_data(place, offset=True)
    offset_size = len(lua(place, offset_data).encode("ascii"))
    say("%s.lanes.lua: %d bytes (the offset variant, without lanes: %d)" % (region_name, size, offset_size))
    score = shares = offset_score = None
    if os.path.exists(os.path.join(CACHE, region_name + ".bench.json")) and region_name in bench.ENTRANCES:
        cases = bench.load(region_name)[2]["cases"]
        trips = [[c["from"]["at"], c["to"]["at"]] for c in cases]
        # The routes lanes.js gives under node are the ones scored, so the
        # score is what the viewer draws.
        js = run_js(data, trips)
        routes = {json.dumps(t): r for t, r in zip(trips, js["routes"])}
        score = bench.score(region_name, "lanes", lambda s, t: routes[json.dumps([s, t])], size)
        say("lanes.js under node: %.2f ms a route (worst %.2f), %.1f ms to read the place" % (
            sum(js["ms"]) / len(js["ms"]), max(js["ms"]), js["prepare"]))
        current, _ = bench.current_router(region_name)
        shares = {"lanes": open_summary(region_name, js["routes"]),
                  "truth": open_summary(region_name, [c["path"] for c in cases]),
                  "current": open_summary(region_name, [current(*t) for t in trips])}
        say("route length over %.0f yd from a wall: %s" % (OPEN_FLOOR, json.dumps(shares)))
        off = run_js(offset_data, trips)
        off_routes = {json.dumps(t): r for t, r in zip(trips, off["routes"])}
        say("offset variant:")
        offset_score = bench.score(region_name, "lanes-offset", lambda s, t: off_routes[json.dumps([s, t])], offset_size)
        shares["offset"] = open_summary(region_name, off["routes"])
        say("offset variant under node: %.2f ms a route, %.1f ms to make its lanes; open share %s" % (
            sum(off["ms"]) / len(off["ms"]), off["prepare"], json.dumps(shares["offset"])))
    with open(os.path.join(CACHE, region_name + ".method.lanes.json"), "w") as handle:
        json.dump(overlay(place, extras, data, size, score, shares, offset_score), handle)


if __name__ == "__main__":
    main()
