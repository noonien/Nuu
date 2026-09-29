#!/usr/bin/env python3
"""A place as a corner visibility graph: the floor traced into outlines, a
point at every corner a walk has to turn round, and the straight lines
between the corners that can see each other.

    python3 Tools/ClientMap/methods/visgraph.py venturemine [--score] [slope=35] [shave=1.0] ...

The shortest walk across a floor with walls is a string pulled tight: it
runs straight from corner to corner, and only turns at a corner of a wall
that sticks out into the floor. So the place is:

  * the floor, cut down to where a player walks: patches steeper than
    `slope` degrees at the foot of the walls or bigger than `ledge` square
    yards go (rock faces and ledges the navmesh calls walkable), unless
    the floor would come apart without them (a steep ramp); then `shave`
    yards off every edge, and passages narrower than `width` yards (a
    passage that joins what nothing else joins is shaved by only `door`);
    what is left is the biggest piece and what lifts reach from it;
  * layers, so that no layer has two floors in one spot of the map: floor
    with more floor above or below it is stacked, each stacked piece takes
    `band` yards of its floor round it, and pieces that then touch are one
    group (the whole of a walkway over a hall, or the strip of hall under
    it); groups that share a spot go into different layers, the biggest
    into layer 0 with all the floor that is not stacked. Layers are worked
    out on the whole floor, steep parts and all;
  * per layer, two outlines, traced and simplified to within `tol` yards:
    the floor's (what a route uses; obstacles up to `fill` yards across
    filled in first, so they add no corners) and the extent's (all the
    layer's floor: which layer a spot is on, where a target off the floor
    stands, and the seams where a player walks onto another layer). Two
    floors of a layer side by side on the map that do not join (the top
    and foot of a cliff) get a wall between them;
  * a corner at every floor outline point where the wall turns into the
    floor by `turn` degrees or more, `push` yards off the wall; a door on
    each seam (a point either side of it); the region's lifts;
  * a link between two points of a layer that can see each other along a
    line that only touches each corner from outside (both walls at a corner
    on one side of it), which is the only way a tight string leaves one.

The runtime has no height. It keeps the layer the player is on (track()):
it changes only when a move crosses a seam of that layer's extent, or a
wall of it (a drop) onto another layer's floor; the band makes every seam
lie on floor only one layer has. A target says its layer (a guide knows
which floor its NPC stands on); without one, every layer whose extent has
it is tried and the shortest route wins. A route joins the player and the
target to up to `ways` points of their layer's floor they can walk to
straight (across the extent, within `reach` yards), those to the corners
they see, and runs Dijkstra.

Writes .cache/<region>.method.visgraph.json (for view.py and the router in
visgraph.js, which is Router below line for line) and
.cache/<region>.visgraph.lua (the place as a guide would carry it).
`--score` runs bench.py's trips through Router.route twice, with the
layers known (the start's tracked along the walk from the entrance, the
target's from its floor) and with map % alone, and checks visgraph.js
gives the same routes under node.
"""

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
import skeleton  # noqa: E402
from casc import CACHE  # noqa: E402

DEFAULTS = {"slope": 35.0, "shave": 1.0, "width": 1.0, "fill": 3.0, "tol": 1.5, "push": 0.5,
            "turn": 5.0, "band": 3.0, "smallest": 500.0, "islet": 2.0, "snap": 8.0,
            "ledge": 25.0, "keep": 1.5, "reach": 25.0,
            "overlap": 4.0, "ways": 3, "door": 0.5}


COLOURS = ["#35c0ff", "#ffb020", "#b070ff", "#40e080", "#ff6090", "#e0e040"]


# ---- The floor -----------------------------------------------------------------

def span_links(grid, mask):
    from scipy.sparse import coo_matrix
    n = len(grid)
    rows = np.repeat(np.arange(n), 4)
    cols = grid.n.reshape(-1)
    ok = (cols >= 0) & mask[rows]
    ok[ok] &= mask[cols[ok]]
    return coo_matrix((np.ones(ok.sum(), np.int8), (rows[ok], cols[ok])), shape=(n, n)).tocsr()


def pieces_of(grid, mask):
    """A piece number for every span of `mask` (-1 elsewhere), joined through
    the spans' own links."""
    from scipy.sparse.csgraph import connected_components
    _, labels = connected_components(span_links(grid, mask), directed=False)
    return np.where(mask, labels, -1)


def floor(region_name, smallest):
    """(region, grid, mask, entrance span, lifts): the floor the place is
    made of. A benchmark region takes bench.py's floor, so a route is
    checked on the floor it was made from; any other region the pieces of
    `smallest` square yards or more, cut down to the way in as skeleton.py
    does, that can be reached from the first exit, walking or by lift. A
    lift is (top span, bottom span)."""
    region = regions.REGIONS[region_name]
    if region_name in bench.ENTRANCES:
        grid, mask = bench.floor(region_name, smallest)
        return region, grid, mask, bench.nearest_span(grid, mask, *bench.ENTRANCES[region_name]), []
    base = navgrid.load(region_name)
    grid = skeleton.Work(base)
    grid.source = base.source
    everything = np.ones(len(base), bool)
    labels = pieces_of(grid, everything)
    sizes = np.bincount(labels)
    mask = sizes[labels] * base.cell ** 2 >= smallest
    if region.get("terrain") == "approach":
        mask &= skeleton.near_models(base, region.get("approach", 30.0))
    piece = pieces_of(grid, mask)
    area = np.bincount(piece[mask]) * base.cell ** 2
    start = None
    for at in region.get("exits", []):
        start = bench.nearest_span(grid, mask, *regions.to_world(region["map"], *at), reach=10.0)
        if start is not None:
            break
    if start is None:
        start = int(np.nonzero(mask & (piece == int(np.argmax(area))))[0][0])
    lifts = []
    for at in region.get("lifts", []):
        x, y = regions.to_world(region["map"], *at)
        spans = skeleton.floors_near(grid, mask, x, y)
        if not spans:
            continue
        top = spans[0]
        below = [s for s in spans if grid.world(s)[2] <= grid.world(top)[2] - 8 and area[piece[s]] >= smallest]
        if not below:
            continue
        low = grid.world(below[0])[2]
        bottom = min((s for s in below if abs(grid.world(s)[2] - low) < 2),
                     key=lambda s: math.hypot(grid.world(s)[0] - x, grid.world(s)[1] - y))
        lifts.append((int(top), int(bottom)))
    keep, changed = {int(piece[start])}, True
    while changed:
        changed = False
        for a, b in lifts:
            for p, q in ((piece[a], piece[b]), (piece[b], piece[a])):
                if p in keep and q not in keep:
                    keep.add(int(q))
                    changed = True
    mask &= np.isin(piece, list(keep))
    lifts = [(a, b) for a, b in lifts if mask[a] and mask[b]]
    return region, grid, mask, start, lifts


def slopes(grid, mask):
    """Each span's slope in degrees, from the heights of the floor up to two
    cells either way along x and along z (through the spans' links)."""
    h = grid.y * grid.cell_height
    idx = np.arange(len(grid))

    def step(s, d):
        o = np.where(s >= 0, grid.n[np.maximum(s, 0), d], -1)
        ok = o >= 0
        ok[ok] = mask[o[ok]]
        return np.where(ok, o, -1)

    grads = []
    for plus, minus in ((2, 0), (1, 3)):
        ends, reach = [], []
        for d in (plus, minus):
            one = step(idx, d)
            two = step(one, d)
            ends.append(np.where(two >= 0, two, np.where(one >= 0, one, idx)))
            reach.append(np.where(two >= 0, 2, np.where(one >= 0, 1, 0)))
        k = reach[0] + reach[1]
        grads.append(np.where(k > 0, (h[ends[0]] - h[ends[1]]) / (np.maximum(k, 1) * grid.cell), 0.0))
    return np.degrees(np.arctan(np.hypot(grads[0], grads[1])))


def spread(grid, alive, seeds, most):
    """Spans of `alive` within `most` distance field units (4 a yard) of a
    seed, along the floor."""
    ring = skeleton.rings(grid, alive)
    big = 1 << 20
    dist = np.where(seeds, 0, big)
    steps = [2, 3, 2, 3, 2, 3, 2, 3]
    while True:
        best = dist.copy()
        for k in range(8):
            other = ring[:, k]
            ok = (other >= 0) & alive
            best = np.minimum(best, np.where(ok, dist[np.maximum(other, 0)] + steps[k], big))
        best[~alive] = big
        best[best > most] = big
        if (best == dist).all():
            return dist <= most
        dist = best


def steep_ground(grid, mask, s):
    """The spans of `mask` too steep to lead a player over: patches steeper
    than `slope` degrees (with any specks of flat floor under `ledge`
    square yards inside them) that run up to the edge of the floor (the
    foot of a wall, a ledge) or cover more than `ledge` square yards. A
    small steep patch out in the floor (a bump, a rut, a step in the rock)
    is walked over and stays, and so does any patch the floor would come
    apart without (a steep ramp between two levels; the smallest first)."""
    from scipy.sparse.csgraph import connected_components
    steep = mask & (slopes(grid, mask) > s["slope"])
    flat = mask & ~steep
    fp = pieces_of(grid, flat)
    fsize = np.bincount(fp[flat]) * grid.cell ** 2 if flat.any() else np.zeros(0)
    big = flat & (fsize[np.maximum(fp, 0)] >= s["ledge"])
    rough = mask & ~big
    edge = np.zeros(len(grid), bool)
    for d in range(4):
        other = grid.n[:, d]
        edge |= (other < 0) | ~mask[np.maximum(other, 0)]
    edge &= mask
    _, comp = connected_components(span_links(grid, rough), directed=False)
    comp = np.where(rough, comp, -1)
    count = int(comp.max()) + 1 if rough.any() else 0
    area = np.bincount(comp[steep], minlength=count) * grid.cell ** 2
    at_edge = np.bincount(comp[steep & edge], minlength=count) > 0
    drop = (at_edge | (area > s["ledge"])) & (area > 0)
    # Keep the patches that join pieces of floor nothing else joins.
    root = {}

    def find(p):
        while root.get(p, p) != p:
            p = root[p]
        return p

    rows = np.repeat(np.arange(len(grid)), 4)
    cols = grid.n.reshape(-1)
    ok = (cols >= 0) & rough[rows]
    ok[ok] &= big[cols[ok]]
    beside = {}
    for c, p in zip(comp[rows[ok]].tolist(), fp[cols[ok]].tolist()):
        beside.setdefault(c, set()).add(p)
    for c in sorted(np.nonzero(drop)[0].tolist(), key=lambda c: area[c]):
        roots = {find(p) for p in beside.get(c, ())}
        if len(roots) >= 2:
            drop[c] = False
            first = roots.pop()
            for r in roots:
                root[r] = first
    return rough & drop[np.maximum(comp, 0)] & (comp >= 0)


def joining(grid, floor, extra):
    """The pieces of `extra` that join pieces of `floor` nothing else joins
    (the smallest first)."""
    from scipy.sparse.csgraph import connected_components
    fp = pieces_of(grid, floor)
    _, comp = connected_components(span_links(grid, extra), directed=False)
    comp = np.where(extra, comp, -1)
    if not extra.any():
        return extra
    area = np.bincount(comp[extra])
    rows = np.repeat(np.arange(len(grid)), 4)
    cols = grid.n.reshape(-1)
    ok = (cols >= 0) & extra[rows]
    ok[ok] &= floor[cols[ok]]
    beside = {}
    for c, p in zip(comp[rows[ok]].tolist(), fp[cols[ok]].tolist()):
        beside.setdefault(c, set()).add(p)
    root, keep = {}, np.zeros(len(area), bool)

    def find(p):
        while root.get(p, p) != p:
            p = root[p]
        return p

    for c in sorted(beside, key=lambda c: area[c]):
        roots = {find(p) for p in beside[c]}
        if len(roots) >= 2:
            keep[c] = True
            first = roots.pop()
            for r in roots:
                root[r] = first
    return extra & keep[np.maximum(comp, 0)]


def walkable_floor(grid, mask, start, s, lifts=()):
    """(D, dropped): the floor a route may use, and what was taken off it
    (masks of steep, shaved and narrow spans, and those cut off from the
    entrance). What is kept is the biggest piece (the entrance itself may
    stand on steep ground), and any piece a lift from it reaches."""
    steep = steep_ground(grid, mask, s)
    flat = mask & ~steep
    dist = skeleton.distance_field(grid, flat)
    units = 2 / grid.cell  # distance field units a yard
    shaved = flat & (dist >= s["shave"] * units)
    core = shaved & (dist >= (s["shave"] + s["width"] / 2) * units)
    wide = spread(grid, shaved, core, s["width"] / 2 * units) & shaved
    # A passage too narrow to shave (a door, a gangway to a lift) is kept,
    # shaved by only `door` yards, if it joins pieces nothing else joins.
    if s["door"] < s["shave"]:
        wide |= joining(grid, wide, flat & ~wide & (dist >= (s["door"] + s["width"] / 2) * units))
    piece = pieces_of(grid, wide)
    keep = {int(np.argmax(np.bincount(piece[wide])))}
    ends = []
    for top, bottom in lifts:
        pair = [bench.nearest_span(grid, wide, *grid.world(span), reach=10.0) for span in (top, bottom)]
        if None not in pair:
            ends.append([int(piece[q]) for q in pair])
    changed = True
    while changed:
        changed = False
        for a, b in ends:
            if (a in keep) != (b in keep):
                keep |= {a, b}
                changed = True
    D = wide & np.isin(piece, list(keep))
    return D, {"steep": steep, "narrow": shaved & ~wide, "cut": wide & ~D}


# ---- Layers --------------------------------------------------------------------

def layer_spans(grid, F, band_yd, least):
    """A layer for every span of F (-1 elsewhere), so no layer has two floors
    in one column, and the number of layers.

    Floor with more floor above or below it is stacked; stacked pieces of
    under `least` square yards (a lip of rock over a ledge) are let be.
    Each stacked piece takes `band_yd` of its floor round it, and pieces
    that then touch are one group: the whole of a walkway over a hall, or
    the strip of hall under it. Groups that share a column go into
    different layers, the biggest first and into layer 0 with all the
    floor that is not stacked. So every other layer is its stacked floor
    and a band of floor only it has all round, and a player crosses that
    band (a seam at its outer edge) to get on or off it."""
    W = grid.grid.width
    col = grid.x.astype(np.int64) + grid.z.astype(np.int64) * W
    counts = np.bincount(col[F], minlength=W * grid.grid.depth)
    stacked = F & (counts[col] > 1)
    layer = np.where(F, 0, -1)
    piece = pieces_of(grid, stacked)
    if stacked.any():
        area = np.bincount(piece[stacked]) * grid.cell ** 2
        stacked &= area[np.maximum(piece, 0)] >= least
    if not stacked.any():
        return layer, 1
    grown = spread(grid, F, stacked, band_yd * 2 / grid.cell) & F
    group = pieces_of(grid, grown)
    # A group with two of its floors in one column (a ramp winding over
    # itself, or a floor and the one above joined by a ramp inside the
    # band) is cut back to its stacked pieces, each split by which floor
    # of the column it is from the bottom, and gets no band.
    spans = np.nonzero(grown)[0]
    key = group[spans] * (W * grid.grid.depth) + col[spans]
    uniq, seen = np.unique(key, return_counts=True)
    bad = np.unique(uniq[seen > 1] // (W * grid.grid.depth))
    if len(bad):
        cut = np.isin(group, bad)
        grown &= ~cut | stacked
        sub = stacked & cut
        order = np.nonzero(sub)[0]
        order = order[np.lexsort((grid.y[order], piece[order], col[order]))]
        rank = np.zeros(len(grid), np.int64)
        same = (col[order][1:] == col[order][:-1]) & (piece[order][1:] == piece[order][:-1])
        for i in np.nonzero(same)[0]:
            rank[order[i + 1]] = rank[order[i]] + 1
        linked = span_links(grid, grown).tocoo()
        tag = np.where(sub, piece * 64 + rank, -1)
        keep = (tag[linked.row] == tag[linked.col])
        from scipy.sparse import coo_matrix
        from scipy.sparse.csgraph import connected_components
        sub_links = coo_matrix((np.ones(keep.sum(), np.int8), (linked.row[keep], linked.col[keep])),
                               shape=(len(grid), len(grid)))
        whole_links = span_links(grid, grown & ~sub).tocoo()
        both = coo_matrix((np.ones(keep.sum() + len(whole_links.row), np.int8),
                           (np.concatenate([linked.row[keep], whole_links.row]),
                            np.concatenate([linked.col[keep], whole_links.col]))), shape=(len(grid), len(grid)))
        _, group = connected_components(both, directed=False)
        group = np.where(grown, group, -1)
        print("layers: %d groups winding over themselves, cut back to their stacked floor" % len(bad), file=sys.stderr)
    spans = np.nonzero(grown)[0]
    ids, small = np.unique(group[spans], return_inverse=True)
    g = np.full(len(grid), -1, np.int64)
    g[spans] = small
    size = np.bincount(small)
    # Which groups share a column.
    order = spans[np.argsort(col[spans], kind="stable")]
    cols = col[order]
    conflicts = [set() for _ in ids]
    start = 0
    while start < len(order):
        end = start
        while end + 1 < len(order) and cols[end + 1] == cols[start]:
            end += 1
        if end > start:
            here = {int(g[q]) for q in order[start:end + 1]}
            for a in here:
                conflicts[a] |= here - {a}
        start = end + 1
    assigned = np.full(len(ids), -1)
    for c in np.argsort(-size, kind="stable"):
        used = {assigned[o] for o in conflicts[c] if assigned[o] >= 0}
        k = 0
        while k in used:
            k += 1
        assigned[c] = k
    layer[spans] = assigned[g[spans]]
    return layer, int(layer.max()) + 1


# ---- Outlines ------------------------------------------------------------------

# A cell's sides as (Recast direction to the cell beyond, start corner,
# end corner) with the floor on the left, x across and z up.
SIDES = [(3, (0, 0), (1, 0)), (2, (1, 0), (1, 1)), (1, (1, 1), (0, 1)), (0, (0, 1), (0, 0))]
# Unit steps by heading: 0 +x, 1 +z, 2 -x, 3 -z.
HEADING = {(1, 0): 0, (0, 1): 1, (-1, 0): 2, (0, -1): 3}


def trace(img, label, shut=None):
    """The outlines of `img` (rows z, columns x) as rings of cell corners,
    floor on the left, each with a label per side (label[z, x, direction]:
    0 wall, else what is beyond). A side is outline where the cell beyond
    is not in `img`, or where `shut` says so (shut[z, x, direction]: two
    floors side by side on the map that do not join, as at the top of a
    cliff; the outline then runs both ways along it, a wall with no
    thickness). Where two cells meet only at a corner the ring turns
    away, so they are not joined."""
    H, W = img.shape
    pad = np.pad(img, 1)
    out = {}
    for d, a, b in SIDES:
        dx, dz = skeleton.OFFSETS[d]
        side = img & ~pad[1 + dz:1 + dz + H, 1 + dx:1 + dx + W]
        if shut is not None:
            side |= img & shut[:, :, d]
        zs, xs = np.nonzero(side)
        for z, x in zip(zs.tolist(), xs.tolist()):
            out.setdefault((x + a[0], z + a[1]), []).append(((x + b[0], z + b[1]), int(label[z, x, d])))
    rings = []
    while out:
        first = next(iter(out))
        ring, labels = [first], []
        here, heading = first, None
        while True:
            options = out[here]
            if len(options) > 1 and heading is not None:
                # Turn right first, then straight, then left.
                options.sort(key=lambda item: (HEADING[(item[0][0] - here[0], item[0][1] - here[1])] - heading + 1) % 4)
            q, lab = options.pop(0)
            if not options:
                del out[here]
            heading = HEADING[(q[0] - here[0], q[1] - here[1])]
            labels.append(lab)
            here = q
            if here == first:
                break
            ring.append(here)
        rings.append((ring, labels))
    return rings


def straight_runs(ring, labels):
    """The ring with points only where it turns or its label changes."""
    n = len(ring)
    keep = []
    for i in range(n):
        a, b, c = ring[i - 1], ring[i], ring[(i + 1) % n]
        turn = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if turn != 0 or labels[i - 1] != labels[i]:
            keep.append(i)
    return [ring[i] for i in keep], [labels[i] for i in keep]


def douglas(points, tol):
    """Douglas-Peucker on an open line: indices to keep, ends included."""
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    P = np.array(points, float)
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = P[i], P[j]
        d = b - a
        L = math.hypot(*d)
        seg = P[i + 1:j] - a
        if L == 0:
            dev = np.hypot(seg[:, 0], seg[:, 1])
        else:
            dev = np.abs(seg[:, 0] * d[1] - seg[:, 1] * d[0]) / L
        k = int(np.argmax(dev))
        if dev[k] > tol:
            m = i + 1 + k
            keep.add(m)
            stack.append((i, m))
            stack.append((m, j))
    return sorted(keep)


def simplify(ring, labels, tol):
    """Simplifies a ring run by run (a run: sides of one label), keeping the
    points where the label changes."""
    n = len(ring)
    cuts = [i for i in range(n) if labels[i - 1] != labels[i]]
    if not cuts:
        far = max(range(n), key=lambda i: (ring[i][0] - ring[0][0]) ** 2 + (ring[i][1] - ring[0][1]) ** 2)
        cuts = [0, far] if far else [0]
    out_ring, out_labels = [], []
    for k, c in enumerate(cuts):
        e = cuts[(k + 1) % len(cuts)]
        idx = list(range(c, e if e > c else e + n))
        idx.append(e if e > c else e + n)
        line = [ring[i % n] for i in idx]
        for j in douglas(line, tol)[:-1]:
            out_ring.append(line[j])
            out_labels.append(labels[c])
    return out_ring, out_labels


# ---- Geometry in yards on the map ----------------------------------------------
# The runtime works in yards on the map: map % times the map's yards per %,
# across and down, which keeps every angle and length true.

def cross(ax, ay, bx, by):
    return ax * by - ay * bx


def clean(ring, labels):
    """Drops repeated points and spikes (a point the ring goes out to and
    straight back from), which rounding can make."""
    changed = True
    while changed and len(ring) >= 3:
        changed = False
        n = len(ring)
        for i in range(n):
            a, b, c = ring[i - 1], ring[i], ring[(i + 1) % n]
            if b == a:
                del ring[i]
                del labels[i]
                changed = True
                break
            # A spike rounding made (a real one is a wall with no
            # thickness, and stays).
            short = min(abs(b[0] - a[0]) + abs(b[1] - a[1]), abs(c[0] - b[0]) + abs(c[1] - b[1])) <= 0.002
            if short and (a == c or (cross(b[0] - a[0], b[1] - a[1], c[0] - b[0], c[1] - b[1]) == 0
                                     and (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1]) <= 0)):
                del ring[i]
                del labels[i]
                changed = True
                break
    return ring, labels


def area2(ring):
    return sum(cross(ring[i - 1][0], ring[i - 1][1], ring[i][0], ring[i][1]) for i in range(len(ring)))


# ---- The router (visgraph.js is this, line for line) ---------------------------

class Router:
    """The place as the runtime holds it, built from the shipped data alone.
    Per layer two sets of walls in yards, each with a grid of which walls
    cross each cell: the floor's (what a route may use; corners stand off
    them and lines of sight are tested on them) and the extent's (all the
    floor of the layer, steep and narrow parts too; says which layer a spot
    is on and how to walk from it onto the floor). Then the corners pushed
    off the wall, the doors and lifts, and the links."""

    CELL = 8.0

    def __init__(self, data, yards):
        self.data, self.ky, self.kx = data, yards[0], yards[1]
        self.push, self.snap = data["push"], data["snap"]
        self.keep, self.reach, self.ways = data["keep"], data["reach"], data["ways"]
        self.floors = []   # per layer: (sides, grid); a side is (x1, y1, x2, y2)
        self.extents = []
        self.seams = []    # per layer: {side of the extent: the layer beyond it}
        self.nodes = []    # [layer, x, y]
        for L, layer in enumerate(data["layers"]):
            rings = [self.ring(flat) for flat in layer["walls"]]
            self.floors.append(self.walls(rings))
            self.extents.append(self.walls([self.ring(flat) for flat in layer["extent"]]))
            seams, runs = {}, layer["seams"]
            for k in range(0, len(runs), 3):
                for i in range(runs[k] - 1, runs[k + 1]):
                    seams[i] = runs[k + 2]
            self.seams.append(seams)
            count = 0
            corners = set(layer["corners"])
            for ring in rings:
                n = len(ring)
                for i in range(n):
                    count += 1
                    if count in corners:
                        x, y = self.pushed(ring[i - 1], ring[i], ring[(i + 1) % n])
                        self.nodes.append([L, x, y])
        pairs = []
        for kind in ("doors", "lifts"):
            for d in data[kind]:
                a = len(self.nodes)
                self.nodes.append([d[0], d[1] * self.ky, d[2] * self.kx])
                self.nodes.append([d[3], d[4] * self.ky, d[5] * self.kx])
                pairs.append((a, a + 1))
        self.adj = [[] for _ in self.nodes]
        links = data["links"]
        for i in range(0, len(links), 2):
            pairs.append((links[i] - 1, links[i + 1] - 1))
        for a, b in pairs:
            w = math.hypot(self.nodes[a][1] - self.nodes[b][1], self.nodes[a][2] - self.nodes[b][2])
            self.adj[a].append((b, w))
            self.adj[b].append((a, w))
        most = max([len(f[0]) for f in self.floors + self.extents] + [0])
        self.stamp, self.mark = 0, [0] * most

    def ring(self, flat):
        return [(flat[i] * self.ky, flat[i + 1] * self.kx) for i in range(0, len(flat), 2)]

    def walls(self, rings):
        sides = []
        for ring in rings:
            for i in range(len(ring)):
                a, b = ring[i], ring[(i + 1) % len(ring)]
                sides.append((a[0], a[1], b[0], b[1]))
        return sides, self.bucket(sides)

    def pushed(self, a, v, b):
        """A corner `push` yards off both walls that meet at it (never more
        than three times `push` from it); the tip of a wall with no
        thickness, `push` yards on past its end."""
        e1x, e1y = v[0] - a[0], v[1] - a[1]
        e2x, e2y = b[0] - v[0], b[1] - v[1]
        l1, l2 = math.hypot(e1x, e1y), math.hypot(e2x, e2y)
        n1x, n1y = -e1y / l1, e1x / l1
        n2x, n2y = -e2y / l2, e2x / l2
        bend = 1 + n1x * n2x + n1y * n2y
        if bend < 1e-6:
            return v[0] + e1x / l1 * self.push, v[1] + e1y / l1 * self.push
        k = self.push / bend
        ox, oy = (n1x + n2x) * k, (n1y + n2y) * k
        L = math.hypot(ox, oy)
        if L > 3 * self.push:
            ox, oy = ox * 3 * self.push / L, oy * 3 * self.push / L
        return v[0] + ox, v[1] + oy

    def bucket(self, sides):
        """Which sides cross each cell of an 8 yd grid, and by row which
        cells have any."""
        g = {"x": 0.0, "y": 0.0, "cells": {}, "rows": {}}
        if not sides:
            return g
        g["x"] = min(min(s[0], s[2]) for s in sides)
        g["y"] = min(min(s[1], s[3]) for s in sides)
        for i, s in enumerate(sides):
            for key in self.cells(g, s[0], s[1], s[2], s[3]):
                if key not in g["cells"]:
                    g["cells"][key] = []
                    g["rows"].setdefault(key // 65536, []).append(key % 65536)
                g["cells"][key].append(i)
        for r in g["rows"]:
            g["rows"][r].sort()
        return g

    def cells(self, g, x1, y1, x2, y2):
        """The grid cells a segment passes through: row by row, the cells
        between where it enters the row and where it leaves it."""
        C = self.CELL
        out = []
        ya, yb = min(y1, y2), max(y1, y2)
        r0, r1 = max(0, math.floor((ya - g["y"]) / C)), math.floor((yb - g["y"]) / C)
        for r in range(r0, r1 + 1):
            lo, hi = max(ya, g["y"] + r * C), min(yb, g["y"] + (r + 1) * C)
            if y2 == y1:
                xa, xb = x1, x2
            else:
                xa = x1 + (x2 - x1) * (lo - y1) / (y2 - y1)
                xb = x1 + (x2 - x1) * (hi - y1) / (y2 - y1)
            c0 = max(0, math.floor((min(xa, xb) - g["x"]) / C))
            c1 = math.floor((max(xa, xb) - g["x"]) / C)
            for c in range(c0, c1 + 1):
                out.append(r * 65536 + c)
        return out

    def sees(self, walls, ax, ay, bx, by):
        """Whether a to b crosses none of `walls` (touching one counts)."""
        sides, g = walls
        self.stamp += 1
        for key in self.cells(g, ax, ay, bx, by):
            for i in g["cells"].get(key, ()):
                if self.mark[i] == self.stamp:
                    continue
                self.mark[i] = self.stamp
                x1, y1, x2, y2 = sides[i]
                d1 = cross(bx - ax, by - ay, x1 - ax, y1 - ay)
                d2 = cross(bx - ax, by - ay, x2 - ax, y2 - ay)
                if (d1 > 0 and d2 > 0) or (d1 < 0 and d2 < 0):
                    continue
                d3 = cross(x2 - x1, y2 - y1, ax - x1, ay - y1)
                d4 = cross(x2 - x1, y2 - y1, bx - x1, by - y1)
                if (d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0):
                    return False
        return True

    def inside(self, walls, x, y):
        """Whether (x, y) is inside `walls`: a ray east from it crosses them
        an odd number of times."""
        sides, g = walls
        r = math.floor((y - g["y"]) / self.CELL)
        c = math.floor((x - g["x"]) / self.CELL)
        self.stamp += 1
        odd = False
        for k in g["rows"].get(r, ()):
            if k < c:
                continue
            for i in g["cells"][r * 65536 + k]:
                if self.mark[i] == self.stamp:
                    continue
                self.mark[i] = self.stamp
                x1, y1, x2, y2 = sides[i]
                if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                    odd = not odd
        return odd

    def near(self, walls, x, y, reach):
        """[(yards, x, y, side)]: the nearest point of each of `walls`
        within `reach` yards of (x, y), nearest first."""
        sides, g = walls
        out = []
        for i, (x1, y1, x2, y2) in enumerate(sides):
            if min(x1, x2) > x + reach or max(x1, x2) < x - reach or \
                    min(y1, y2) > y + reach or max(y1, y2) < y - reach:
                continue
            dx, dy = x2 - x1, y2 - y1
            L2 = dx * dx + dy * dy
            t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / L2))
            px, py = x1 + t * dx, y1 + t * dy
            d = math.hypot(x - px, y - py)
            if d <= reach:
                out.append((d, px, py, i))
        out.sort()
        return out

    def onto(self, walls, x, y, d, px, py, i):
        """The point just inside `walls` beside their point (px, py) (on side
        i), which is `d` yards from (x, y): on past the wall from (x, y),
        else to the wall's left (the floor is on the left of every wall);
        None if neither is inside."""
        x1, y1, x2, y2 = walls[0][i]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        for step in (0.15, 0.3, 0.6):
            if d > 1e-6:
                qx, qy = px + (px - x) / d * step, py + (py - y) / d * step
                if self.inside(walls, qx, qy):
                    return qx, qy
            if length > 0:
                qx, qy = px - dy / length * step, py + dx / length * step
                if self.inside(walls, qx, qy):
                    return qx, qy
        return None

    def approach(self, L, x, y, reach):
        """Where a player at (x, y), on layer L's extent, steps onto its
        floor: [(x, y)] if they are on it, else up to `ways` points of the
        floor within `reach` yards a straight line reaches without leaving
        the extent (a point of a wall, or a corner of one, stepped inside;
        the nearest first, each on a different wall). [] if none."""
        floor = self.floors[L]
        if self.inside(floor, x, y):
            return [(x, y)]
        found = self.near(floor, x, y, reach)
        for d, px, py, i in list(found):
            x1, y1 = floor[0][i][0], floor[0][i][1]
            e = math.hypot(x1 - x, y1 - y)
            if e <= reach:
                found.append((e, x1, y1, i))
        found.sort()
        out, used = [], set()
        for d, px, py, i in found:
            if i in used:
                continue
            q = self.onto(floor, x, y, d, px, py, i)
            if q and self.sees(self.extents[L], x, y, q[0], q[1]):
                out.append(q)
                used.add(i)
                if len(out) == self.ways:
                    break
        return out

    def place(self, x, y, want=None):
        """[(layer, x, y)]: the layers (x, y) may be on, each with the point
        of its extent a route starts or ends at: (x, y) where the extent
        has it, else the nearest point just inside it within `keep` yards.
        With `want`, only that layer if it can. Failing all that, the
        nearest point of any layer's extent within `snap` yards, or [] (not
        in the place)."""
        out = []
        for L in ([want] if want is not None else range(len(self.extents))):
            e = self.enter(L, x, y, self.keep)
            if e:
                qs = self.approach(L, e[0], e[1], self.reach)
                if qs:
                    out.append((L, e[0], e[1], qs))
        if out:
            return out
        if want is not None:
            return self.place(x, y)
        best = None
        for L in range(len(self.extents)):
            e = self.enter(L, x, y, self.snap)
            qs = e and self.approach(L, e[0], e[1], self.reach)
            if qs and (best is None or math.hypot(e[0] - x, e[1] - y) < best[0]):
                best = (math.hypot(e[0] - x, e[1] - y), L, e[0], e[1], qs)
        return [best[1:]] if best else []

    def enter(self, L, x, y, reach):
        """(x, y) if layer L's extent has it, else the nearest point just
        inside it within `reach` yards, else None."""
        walls = self.extents[L]
        if self.inside(walls, x, y):
            return x, y
        for d, px, py, i in self.near(walls, x, y, reach):
            e = self.onto(walls, x, y, d, px, py, i)
            if e:
                return e
        return None

    def track(self, L, was, now):
        """The layer a player is on who was on layer L at map % `was` and
        is now at map % `now` (L None: not known yet). A move across a seam
        of L's extent is onto the layer beyond it; one across a wall of it
        (a drop) is onto a layer whose extent has them, if L's does not
        and they are more than `keep` yards off it (the outline is rounded,
        and a player hugging a wall steps over it). Otherwise they stay on
        L, even where another layer has floor above or below."""
        x, y = now[0] * self.ky, now[1] * self.kx
        if L is None:
            for M in range(len(self.extents)):
                if self.inside(self.extents[M], x, y):
                    return M
            found = self.place(x, y)
            return found[0][0] if found else None
        ax, ay = was[0] * self.ky, was[1] * self.kx
        sides, g = self.extents[L]
        first, beyond = math.inf, None
        self.stamp += 1
        for key in self.cells(g, ax, ay, x, y):
            for i in g["cells"].get(key, ()):
                if self.mark[i] == self.stamp:
                    continue
                self.mark[i] = self.stamp
                x1, y1, x2, y2 = sides[i]
                d1 = cross(x - ax, y - ay, x1 - ax, y1 - ay)
                d2 = cross(x - ax, y - ay, x2 - ax, y2 - ay)
                d3 = cross(x2 - x1, y2 - y1, ax - x1, ay - y1)
                d4 = cross(x2 - x1, y2 - y1, x - x1, y - y1)
                if (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0):
                    t = d3 / (d3 - d4)
                    if t < first:
                        first, beyond = t, self.seams[L].get(i, -1)
        if beyond is None:
            return L
        if beyond >= 0:
            return beyond
        if self.inside(self.extents[L], x, y) or self.near(self.extents[L], x, y, self.keep):
            return L
        for M in range(len(self.extents)):
            if M != L and self.inside(self.extents[M], x, y):
                return M
        return L

    def route(self, start, target, layers=None):
        """start and target in map %; the route in map %, or None. `layers`
        is the layer the player is on (tracked) and the layer the target
        is on (said by the guide), either None if not known."""
        sx, sy = start[0] * self.ky, start[1] * self.kx
        tx, ty = target[0] * self.ky, target[1] * self.kx
        Ls, Lt = layers or (None, None)
        S, T = self.place(sx, sy, Ls), self.place(tx, ty, Lt)
        if not S or not T:
            return None
        best, best_path = math.inf, None
        # Straight there on a layer both are on: across its floor, or, a
        # short way, across its extent.
        for Ls, ax, ay, qs in S:
            for Lt, bx, by, rs in T:
                if Ls != Lt:
                    continue
                d = math.hypot(ax - bx, ay - by)
                if d <= self.reach and self.sees(self.extents[Ls], ax, ay, bx, by):
                    d += math.hypot(sx - ax, sy - ay) + math.hypot(bx - tx, by - ty)
                    if d < best:
                        best, best_path = d, [(ax, ay), (bx, by)]
                for qx, qy in qs:
                    for rx, ry in rs:
                        if self.sees(self.floors[Ls], qx, qy, rx, ry):
                            d = math.hypot(sx - ax, sy - ay) + math.hypot(ax - qx, ay - qy) + \
                                math.hypot(qx - rx, qy - ry) + math.hypot(rx - bx, ry - by) + math.hypot(bx - tx, by - ty)
                            if d < best:
                                best, best_path = d, [(ax, ay), (qx, qy), (rx, ry), (bx, by)]
        # Otherwise from where each gets onto the floor to the corners it
        # sees, and Dijkstra between.
        n = len(self.nodes)
        dist, prev, head = [math.inf] * n, [-1] * n, [None] * n
        for k, (Ls, ax, ay, qs) in enumerate(S):
            for j, (qx, qy) in enumerate(qs):
                lead = math.hypot(sx - ax, sy - ay) + math.hypot(ax - qx, ay - qy)
                for i, (L, x, y) in enumerate(self.nodes):
                    if L == Ls and self.sees(self.floors[L], qx, qy, x, y):
                        d = lead + math.hypot(x - qx, y - qy)
                        if d < dist[i]:
                            dist[i], head[i] = d, (k, j)
        tail, foot = [math.inf] * n, [None] * n
        for k, (Lt, bx, by, rs) in enumerate(T):
            for j, (rx, ry) in enumerate(rs):
                last = math.hypot(bx - tx, by - ty) + math.hypot(rx - bx, ry - by)
                for i, (L, x, y) in enumerate(self.nodes):
                    if L == Lt and self.sees(self.floors[L], x, y, rx, ry):
                        d = last + math.hypot(x - rx, y - ry)
                        if d < tail[i]:
                            tail[i], foot[i] = d, (k, j)
        done = [False] * n
        end = -1
        while True:
            u = -1
            for i in range(n):
                if not done[i] and dist[i] < math.inf and (u < 0 or dist[i] < dist[u]):
                    u = i
            if u < 0 or dist[u] >= best:
                break
            done[u] = True
            if dist[u] + tail[u] < best:
                best, end = dist[u] + tail[u], u
            for v, w in self.adj[u]:
                if dist[u] + w < dist[v]:
                    dist[v], prev[v], head[v] = dist[u] + w, u, head[u]
        if end >= 0:
            chain = []
            u = end
            while u >= 0:
                chain.append((self.nodes[u][1], self.nodes[u][2]))
                u = prev[u]
            chain.reverse()
            Ls, ax, ay, qs = S[head[end][0]]
            Lt, bx, by, rs = T[foot[end][0]]
            best_path = [(ax, ay), qs[head[end][1]]] + chain + [rs[foot[end][1]], (bx, by)]
        if best_path is None:
            return None
        points = [(sx, sy)] + best_path + [(tx, ty)]
        out = []
        for x, y in points:
            if not out or math.hypot(x - out[-1][0], y - out[-1][1]) > 1e-6:
                out.append((x, y))
        return [[x / self.ky, y / self.kx] for x, y in out]


# ---- The build -----------------------------------------------------------------

class Frame:
    """From a layer image's cell corners to map % and to the runtime's
    yards, and whether that turns the outlines over."""

    def __init__(self, grid, region, x0, z0):
        self.grid, self.map, self.x0, self.z0 = grid, region["map"], x0, z0
        b = maps.get(region["map"])
        self.yards = (abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100)
        p = [self.to_yards(self.to_map(u, v)) for u, v in ((0, 0), (1, 0), (0, 1))]
        self.flip = cross(p[1][0] - p[0][0], p[1][1] - p[0][1], p[2][0] - p[0][0], p[2][1] - p[0][1]) < 0

    def to_map(self, u, v):
        g = self.grid
        wx = g.bmin[0] + (u + self.x0) * g.cell
        wy = -(g.bmin[2] + (v + self.z0) * g.cell)
        return regions.to_map(self.map, wx, wy)

    def to_yards(self, m):
        return (m[0] * self.yards[0], m[1] * self.yards[1])


def layer_image(grid, S, layer, L, s, fill=True):
    """Layer L of the spans `S` as an image (rows z, columns x, one cell of
    margin): (img, side labels and shut sides for trace(), x0, z0, the
    obstacles filled in). Islets of a few square yards go; with `fill`,
    so do obstacles up to `fill` yards across."""
    from scipy import ndimage
    spans = np.nonzero(layer == L)[0]
    x0, z0 = int(grid.x[spans].min()) - 1, int(grid.z[spans].min()) - 1
    W = int(grid.x[spans].max()) - x0 + 2
    H = int(grid.z[spans].max()) - z0 + 2
    img = np.zeros((H, W), bool)
    zs, xs = grid.z[spans] - z0, grid.x[spans] - x0
    img[zs, xs] = True
    at = np.full((H, W), -1, np.int64)
    at[zs, xs] = spans
    # A column where the layer has two floors (an overlap too small to be
    # given a layer of its own) is left out: a hole, not a guess.
    many = np.zeros((H, W), np.int32)
    np.add.at(many, (zs, xs), 1)
    img &= many < 2
    spans = spans[many[zs, xs] < 2]
    label = np.zeros((H, W, 4), np.int16)
    seam = np.zeros((H, W), bool)
    for d in range(4):
        other = grid.n[spans, d]
        ok = other >= 0
        ok[ok] = S[other[ok]]
        ok[ok] &= layer[other[ok]] != L
        where = spans[ok]
        label[grid.z[where] - z0, grid.x[where] - x0, d] = layer[other[ok]] + 1
        dx, dz = skeleton.OFFSETS[d]
        zz, xx = grid.z[where] - z0 + dz, grid.x[where] - x0 + dx
        inside = (zz >= 0) & (zz < H) & (xx >= 0) & (xx < W)
        seam[zz[inside], xx[inside]] = True
    # Islets of a few square yards (the tip of a band) go.
    parts, count = ndimage.label(img)
    sizes = np.bincount(parts.ravel()) * grid.cell ** 2
    img &= sizes[parts] >= s["islet"]
    at[~img] = -1
    filled = np.zeros_like(img)
    if fill:
        # Obstacles up to `fill` yards across: the hole they leave in the
        # floor is that, the player's radius and the shave each side.
        most = (s["fill"] + 1.0 + 2 * s["shave"]) / grid.cell
        holes, count = ndimage.label(~img, structure=np.ones((3, 3)))
        border = set(np.unique(np.concatenate([holes[0], holes[-1], holes[:, 0], holes[:, -1]])).tolist())
        for i, box in enumerate(ndimage.find_objects(holes)):
            if box is None or i + 1 in border:
                continue
            if max(box[0].stop - box[0].start, box[1].stop - box[1].start) > most:
                continue
            hole = holes[box] == i + 1
            if (seam[box] & hole).any():
                continue
            filled[box] |= hole
        img |= filled
    # Two cells of the layer side by side that are not joined (a cliff's
    # top beside its foot) have a wall between them.
    shut = np.zeros((H, W, 4), bool)
    for d in range(4):
        dx, dz = skeleton.OFFSETS[d]
        here = np.nonzero(at >= 0)
        zz, xx = here[0] + dz, here[1] + dx
        span = at[here]
        beyond = at[zz, xx]
        shut[here[0], here[1], d] = (beyond >= 0) & (grid.n[span, d] != beyond)
    return img, label, shut, x0, z0, filled


def outline(img, label, frame, s, shut=None):
    """The layer's rings in map % (rounded to three places) and in yards,
    floor on the left, with a label per side."""
    out = []
    for ring, labels in trace(img, label, shut):
        ring, labels = straight_runs(ring, labels)
        if len(ring) < 3:
            continue
        ring, labels = simplify(ring, labels, s["tol"] / frame.grid.cell)
        m = [tuple(round(v, 3) for v in frame.to_map(u, v)) for u, v in ring]
        if frame.flip:
            # Reversed, a side's label moves with it: side i ran from point i to i+1.
            m = m[::-1]
            labels = labels[::-1][1:] + labels[::-1][:1]
        m, labels = clean(list(m), list(labels))
        if len(m) < 3:
            continue
        y = [frame.to_yards(p) for p in m]
        if abs(area2(y)) < 2 * 1.0:
            continue
        out.append({"map": m, "yd": y, "labels": labels})
    return out


def settle(router, L, x, y):
    """(x, y) in yards moved onto layer L's floor if it is just off it."""
    e = router.enter(L, x, y, router.snap)
    found = e and router.approach(L, e[0], e[1], router.snap)
    return found[0] if found else None


def seam_runs(rings):
    """The seams of a layer's rings as runs of sides: first side, last side
    (counted through all the rings from 1), the layer beyond."""
    runs, count = [], 0
    for r in rings:
        for lab in r["labels"]:
            count += 1
            if lab:
                if runs and runs[-2] == count - 1 and runs[-1] == lab - 1:
                    runs[-2] = count
                else:
                    runs += [count, count, lab - 1]
    return runs


def mask_rings(grid, region, mask, tol):
    """The 2D outline of a set of spans, in map %, for the viewer."""
    if not mask.any():
        return []
    spans = np.nonzero(mask)[0]
    x0, z0 = int(grid.x[spans].min()) - 1, int(grid.z[spans].min()) - 1
    img = np.zeros((int(grid.z[spans].max()) - z0 + 2, int(grid.x[spans].max()) - x0 + 2), bool)
    img[grid.z[spans] - z0, grid.x[spans] - x0] = True
    return image_rings(img, Frame(grid, region, x0, z0), tol, grid.cell)


def image_rings(img, frame, tol, cell):
    out = []
    for ring, labels in trace(img, np.zeros(img.shape + (4,), np.int16)):
        ring, labels = straight_runs(ring, labels)
        if len(ring) < 3:
            continue
        ring, _ = simplify(ring, labels, tol / cell)
        if len(ring) >= 3:
            out.append([[round(v, 2) for v in frame.to_map(u, v)] for u, v in ring])
    return out


def build(region_name, s):
    t0 = time.perf_counter()
    region, grid, mask, start, lifts = floor(region_name, s["smallest"])
    D, dropped = walkable_floor(grid, mask, start, s, lifts)
    # Layers are worked out on the whole floor, steep and shaved parts and
    # all, so a spot the route may not use (a ledge under a walkway) still
    # belongs to the layer of the floor it is part of.
    whole, count = layer_spans(grid, mask, s["band"], s["overlap"])
    layer = np.where(D, whole, -1)
    print("floor %d spans; kept %d (steep %d, narrow %d, cut off %d); %d layers" % (
        mask.sum(), D.sum(), dropped["steep"].sum(), dropped["narrow"].sum(), dropped["cut"].sum(), count),
        file=sys.stderr)
    frame0 = Frame(grid, region, 0, 0)
    yards = frame0.yards
    layers = []
    for L in range(count):
        lay = {"rings": [], "filled": [], "extent": [], "spans": int((layer == L).sum())}
        if (layer == L).any():
            img, label, shut, x0, z0, filled = layer_image(grid, D, layer, L, s)
            frame = Frame(grid, region, x0, z0)
            lay["rings"] = outline(img, label, frame, s, shut)
            lay["filled"] = image_rings(filled, frame, s["tol"], grid.cell)
        img, label, shut, x0, z0, _ = layer_image(grid, mask, whole, L, s, fill=False)
        lay["extent"] = outline(img, label, Frame(grid, region, x0, z0), s, shut)
        layers.append(lay)
    data = {"push": s["push"], "snap": s["snap"], "keep": s["keep"], "reach": s["reach"], "ways": int(s["ways"]),
            "layers": [{"walls": [[v for p in r["map"] for v in p] for r in lay["rings"]],
                        "extent": [[v for p in r["map"] for v in p] for r in lay["extent"]],
                        "seams": seam_runs(lay["extent"]), "corners": []}
                       for lay in layers],
            "doors": [], "lifts": [], "links": []}
    router = Router(data, yards)
    # Corners: where a wall turns into the floor, both sides of it walls.
    turn = math.radians(s["turn"])
    wedges = []
    for L, lay in enumerate(layers):
        count_v = 0
        for r in lay["rings"]:
            y, labels = r["yd"], r["labels"]
            n = len(y)
            for i in range(n):
                count_v += 1
                if labels[i - 1] or labels[i]:
                    continue
                a, v, b = y[i - 1], y[i], y[(i + 1) % n]
                c = cross(v[0] - a[0], v[1] - a[1], b[0] - v[0], b[1] - v[1])
                d = (v[0] - a[0]) * (b[0] - v[0]) + (v[1] - a[1]) * (b[1] - v[1])
                if c > 0 or (c == 0 and d >= 0) or math.atan2(-c, d) < turn:
                    continue
                px, py = router.pushed(a, v, b)
                if not router.inside(router.floors[L], px, py):
                    continue
                data["layers"][L]["corners"].append(count_v)
                wedges.append((a, v, b))
    # Doors: on each seam, every 6 yd, a point either side.
    doors = []
    for L, lay in enumerate(layers):
        for r in lay["rings"]:
            y, labels = r["yd"], r["labels"]
            n = len(y)
            # Start the walk round the ring at a change of label.
            first = next((k for k in range(n) if labels[k] != labels[k - 1]), None)
            if first is None:
                continue
            k = 0
            while k < n:
                j = (first + k) % n
                M = labels[j] - 1
                run = [j]
                while k + len(run) < n and labels[(first + k + len(run)) % n] == labels[j]:
                    run.append((first + k + len(run)) % n)
                k += len(run)
                if M <= L:
                    continue
                sides = [(y[q], y[(q + 1) % n]) for q in run]
                total = sum(math.dist(a, b) for a, b in sides)
                parts = max(1, int(round(total / 6.0)))
                for part in range(parts):
                    want, walked = total * (part + 0.5) / parts, 0.0
                    for a, b in sides:
                        length = math.dist(a, b)
                        if walked + length >= want and length > 0:
                            t = (want - walked) / length
                            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
                            nx, ny = -(b[1] - a[1]) / length, (b[0] - a[0]) / length
                            break
                        walked += length
                    for off in (0.6, 1.0, 1.5):
                        pa = [round((q[0] + nx * off) / yards[0], 3), round((q[1] + ny * off) / yards[1], 3)]
                        pb = [round((q[0] - nx * off) / yards[0], 3), round((q[1] - ny * off) / yards[1], 3)]
                        if router.inside(router.floors[L], pa[0] * yards[0], pa[1] * yards[1]) and \
                                router.inside(router.floors[M], pb[0] * yards[0], pb[1] * yards[1]):
                            doors.append([L, pa[0], pa[1], M, pb[0], pb[1]])
                            break
    data["doors"] = doors
    # Lifts: the floor at the top and at the bottom, each on its layer.
    for top, bottom in lifts:
        ends = []
        for span in (top, bottom):
            near = bench.nearest_span(grid, D, *grid.world(span), reach=10.0)
            if near is None:
                break
            L = int(layer[near])
            m = regions.to_map(region["map"], *grid.world(span)[:2])
            p = settle(router, L, m[0] * yards[0], m[1] * yards[1])
            if p is None:
                break
            ends.append([L, round(p[0] / yards[0], 3), round(p[1] / yards[1], 3)])
        if len(ends) == 2:
            data["lifts"].append(ends[0] + ends[1])
    # Links: every two points of a layer that see each other, tangent at
    # both ends where they are corners.
    router = Router(data, yards)
    nodes = router.nodes
    wedge = wedges + [None] * (len(nodes) - len(wedges))

    def tangent(i, j):
        w = wedge[i]
        if w is None:
            return True
        a, v, b = w
        ox, oy = nodes[j][1] - v[0], nodes[j][2] - v[1]
        return cross(ox, oy, a[0] - v[0], a[1] - v[1]) * cross(ox, oy, b[0] - v[0], b[1] - v[1]) >= 0

    links = []
    by_layer = {}
    for i, (L, x, y) in enumerate(nodes):
        by_layer.setdefault(L, []).append(i)
    pairs = 0
    for L, ids in by_layer.items():
        for p, i in enumerate(ids):
            for j in ids[p + 1:]:
                if not (tangent(i, j) and tangent(j, i)):
                    continue
                pairs += 1
                if router.sees(router.floors[L], nodes[i][1], nodes[i][2], nodes[j][1], nodes[j][2]):
                    links += [i + 1, j + 1]
    data["links"] = links
    router = Router(data, yards)
    print("%d corners, %d doors, %d lifts, %d links (%d tangent pairs tried), %.1f s" % (
        len(wedges), len(doors), len(data["lifts"]), len(links) // 2, pairs, time.perf_counter() - t0),
        file=sys.stderr)
    return {"region": region, "name": region_name, "data": data, "layers": layers, "yards": yards,
            "grid": grid, "mask": mask, "D": D, "layer": whole, "start": start,
            "dropped": {k: mask_rings(grid, region, v, s["tol"]) for k, v in dropped.items()},
            "settings": s, "router": router}


# ---- What ships ------------------------------------------------------------------

def numbers(values, per_line, indent):
    out = []
    for i in range(0, len(values), per_line):
        out.append(indent + ", ".join(v if isinstance(v, str) else ("%.2f" % v if isinstance(v, float) else str(v))
                                      for v in values[i:i + per_line]) + ",")
    return out


def lua(result):
    """The place as guide source. Every table is a list or a record, never
    both; a ring or a point is a flat list of x, y in map %."""
    data, region = result["data"], result["region"]
    lines = ['{ place = "%s", name = "%s", map = %d, kind = "corners",' % (
        result["name"], regions.name(region), region["map"])]
    if region.get("exits"):
        lines.append("  entrance = { %.3f, %.3f }," % tuple(region["exits"][0]))
    lines.append("  push = %s, snap = %s, keep = %s, reach = %s, ways = %d," % (
        data["push"], data["snap"], data["keep"], data["reach"], data["ways"]))
    lines.append("  layers = {")

    def rings(name, flat_rings):
        lines.append("      %s = {" % name)
        for ring in flat_rings:
            lines.append("        {")
            lines.extend(numbers(["%.3f,%.3f" % (ring[i], ring[i + 1]) for i in range(0, len(ring), 2)], 8, "          "))
            lines.append("        },")
        lines.append("      },")

    for L, layer in enumerate(data["layers"]):
        lines.append("    { -- layer %d: %d walls, %d corners" % (L + 1, len(layer["walls"]), len(layer["corners"])))
        rings("walls", layer["walls"])
        rings("extent", layer["extent"])
        # Seams: runs of the extent's sides (first, last, counted through
        # all its rings) and the layer beyond, three numbers a run.
        runs = layer["seams"]
        lines.append("      seams = {")
        lines += numbers(["%d,%d,%d" % (runs[i], runs[i + 1], runs[i + 2] + 1) for i in range(0, len(runs), 3)],
                         8, "        ")
        lines.append("      },")
        lines.append("      corners = {")
        lines += numbers(layer["corners"], 20, "        ")
        lines.append("      },")
        lines.append("    },")
    lines.append("  },")
    for kind in ("doors", "lifts"):
        if data[kind]:
            lines.append("  %s = {" % kind)
            for d in data[kind]:
                lines.append("    { %d, %.3f, %.3f, %d, %.3f, %.3f }," % (d[0] + 1, d[1], d[2], d[3] + 1, d[4], d[5]))
            lines.append("  },")
    lines.append("  links = {")
    lines += numbers(["%d,%d" % (data["links"][i], data["links"][i + 1]) for i in range(0, len(data["links"]), 2)],
                     12, "    ")
    lines.append("  },")
    lines.append("},")
    return "\n".join(lines) + "\n"


# ---- The viewer's layers -----------------------------------------------------------

def overlay(result, size, score=None, known=None):
    data, layers = result["data"], result["layers"]
    router = result["router"]
    yards = result["yards"]
    to_map = lambda x, y: [round(x / yards[0], 3), round(y / yards[1], 3)]  # noqa: E731
    shapes = {"floor": [], "extent": [], "seams": [], "corners": [], "links": [], "dropped": []}
    for L, lay in enumerate(layers):
        colour = COLOURS[L % len(COLOURS)]
        rings = [r["map"] for r in lay["rings"]]
        if rings:
            shapes["floor"].append({"rings": rings, "stroke": colour, "fill": colour, "opacity": 0.35, "width": 1,
                                    "tip": "layer %d: %d walls, %d spans" % (L + 1, len(rings), lay["spans"])})
        rings = [r["map"] for r in lay["extent"]]
        if rings:
            shapes["extent"].append({"rings": rings, "stroke": colour, "width": 1, "dash": [3, 2],
                                     "tip": "layer %d's extent: %d rings" % (L + 1, len(rings))})
        for r in lay["extent"]:
            m, labels = r["map"], r["labels"]
            for i in range(len(m)):
                if labels[i]:
                    shapes["seams"].append({"line": [m[i], m[(i + 1) % len(m)]], "stroke": "#ffffff", "width": 3,
                                            "tip": "seam: layer %d to %d" % (L + 1, labels[i])})
        for ring in lay["filled"]:
            shapes["dropped"].append({"poly": ring, "stroke": "#ff40ff", "fill": "#ff40ff", "opacity": 0.6,
                                      "tip": "obstacle filled in (no corners)"})
    for kind, colour in (("steep", "#ff8000"), ("narrow", "#a0a0a0"), ("cut", "#606060")):
        for ring in result["dropped"][kind]:
            shapes["dropped"].append({"poly": ring, "stroke": colour, "fill": colour, "opacity": 0.5,
                                      "tip": {"steep": "steeper than %g degrees" % result["settings"]["slope"],
                                              "narrow": "narrower than %g yd" % result["settings"]["width"],
                                              "cut": "cut off from the entrance"}[kind]})
    corners = sum(len(lay["corners"]) for lay in data["layers"])
    degree = [len(a) for a in router.adj]
    for i, (L, x, y) in enumerate(router.nodes):
        kind = "corner" if i < corners else ("door" if i < corners + 2 * len(data["doors"]) else "lift")
        colour = {"corner": COLOURS[L % len(COLOURS)], "door": "#ffffff", "lift": "#ff4040"}[kind]
        (shapes["corners"] if kind == "corner" else shapes["seams"]).append(
            {"dot": to_map(x, y), "r": 1.4, "fill": colour,
             "tip": "%s %d, layer %d, %d links" % (kind, i + 1, L + 1, degree[i])})
    for u, nbrs in enumerate(router.adj):
        for v, w in nbrs:
            if u < v:
                a, b = router.nodes[u], router.nodes[v]
                shapes["links"].append({"line": [to_map(a[1], a[2]), to_map(b[1], b[2])], "stroke": "#40ffff",
                                        "width": 0.6, "opacity": 0.6})
    s = result["settings"]
    stats = ["%d layers, %d corners, %d doors, %d lifts, %d links; %.1f KB of Lua" % (
        len(layers), corners, len(data["doors"]), len(data["lifts"]), len(data["links"]) // 2, size / 1024),
        "slope %g deg, shave %g yd, width %g yd, fill %g yd, tol %g yd, push %g yd, band %g yd" % (
            s["slope"], s["shave"], s["width"], s["fill"], s["tol"], s["push"], s["band"])]
    for label, sc in (("layers known", known), ("map % alone", score)):
        if sc:
            stats.append("bench, %s: walkable %d/%d, reached %d, ratio %.3f (worst %.2f), %.1f bends, %.2f ms" % (
                label, sc["walkable"], sc["cases"], sc["reached"], sc["ratio_mean"], sc["ratio_worst"],
                sc["bends_mean"], sc["ms_mean"]))
    return {"name": "Corner visibility graph", "colour": "#35c0ff", "stats": stats, "data": data,
            "layers": [
                {"name": "floor by layer", "on": True, "shapes": shapes["floor"],
                 "note": "the floor a route may use, one colour a layer (walls shaved, steep and narrow parts gone)"},
                {"name": "extent by layer", "on": False, "shapes": shapes["extent"],
                 "note": "all the floor of each layer, steep and narrow parts too: which layer a spot is on"},
                {"name": "seams, doors and lifts", "on": True, "shapes": shapes["seams"],
                 "note": "white lines: where two layers meet; white dots: a door either side; red: lifts"},
                {"name": "corners", "on": True, "shapes": shapes["corners"],
                 "note": "where a route may turn: corners of the walls, pushed off them"},
                {"name": "links", "on": False, "shapes": shapes["links"],
                 "note": "corners that see each other, tangent at both ends"},
                {"name": "dropped", "on": False, "shapes": shapes["dropped"],
                 "note": "orange: too steep; grey: too narrow or cut off; magenta: small obstacles filled in"},
            ]}


# ---- Scoring -------------------------------------------------------------------------

NODE_CHECK = r"""
const fs = require("fs");
let router = null;
global.NuuRoadViewer = { method: (id, r) => { router = r; } };
require(process.argv[2]);
const input = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const yd = (a, b) => Math.hypot((a[0] - b[0]) * input.yards[0], (a[1] - b[1]) * input.yards[1]);
const out = [];
const t0 = process.hrtime.bigint();
for (const [s, t, layers] of input.trips) {
  const r = router.route(input.data, s, t, { yd, yards: input.yards, layers });
  out.push(r ? r.points : null);
}
const ms = Number(process.hrtime.bigint() - t0) / 1e6;
console.log(JSON.stringify({ routes: out, ms }));
"""


def check_js(result, trips):
    """Runs visgraph.js under node on the same trips ([start, target,
    layers or None]); the routes it gives and the ms it took."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "input.json"), "w") as handle:
            json.dump({"data": result["data"], "yards": result["yards"], "trips": trips}, handle)
        with open(os.path.join(tmp, "check.js"), "w") as handle:
            handle.write(NODE_CHECK)
        out = subprocess.run(["node", os.path.join(tmp, "check.js"), os.path.join(HERE, "visgraph.js"),
                              os.path.join(tmp, "input.json")], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit("node: " + out.stderr)
    return json.loads(out.stdout)


def compare_js(result, trips):
    """The largest difference (map %) between route() and visgraph.js over
    `trips`, inf if any route differs in shape; and node's ms a route."""
    router = result["router"]
    js = check_js(result, trips)
    worst = 0.0
    for (a, b, layers), got in zip(trips, js["routes"]):
        mine = router.route(a, b, layers)
        if (mine is None) != (got is None) or (mine and len(mine) != len(got)):
            worst = math.inf
            continue
        if mine:
            worst = max(worst, max(abs(p - q) for u, v in zip(mine, got) for p, q in zip(u, v)))
    return worst, js["ms"] / len(trips)


def layer_hints(result):
    """What the runtime would know besides map %, for each of bench.py's
    trips: the layer the player is on at the start, tracked (Router.track)
    along the shortest walk to it from the entrance, and the layer of the
    target's own floor (which a guide would say). Returns ({(start, target):
    (layer, layer)}, spans walked, spans tracked onto the wrong layer, trips
    started on the wrong layer)."""
    from scipy.sparse.csgraph import dijkstra
    grid, mask, whole, router = result["grid"], result["mask"], result["layer"], result["router"]
    cases = bench.load(result["name"])[2]["cases"]
    links = bench.links8(grid, mask)
    entrance = bench.nearest_span(grid, mask, *bench.ENTRANCES[result["name"]])
    _, pred = dijkstra(links, indices=entrance, return_predecessors=True)
    at = lambda span: regions.to_map(result["region"]["map"], *grid.world(span)[:2])  # noqa: E731
    hints, walked, wrong, starts = {}, 0, 0, 0
    for case in cases:
        span, path = case["from"]["span"], []
        while span >= 0:
            path.append(span)
            span = pred[span] if span != entrance else -1
        L, was = None, None
        for span in path[::-1]:
            now = at(span)
            L = router.track(L, was, now)
            was = now
            walked += 1
            wrong += L != whole[span]
        starts += L != whole[case["from"]["span"]]
        hints[(tuple(case["from"]["at"]), tuple(case["to"]["at"]))] = (L, int(whole[case["to"]["span"]]))
    return hints, walked, wrong, starts


def main():
    args = sys.argv[1:]
    region_name = next((a for a in args if a in regions.REGIONS), "venturemine")
    s = dict(DEFAULTS)
    for a in args:
        if "=" in a:
            k, v = a.split("=", 1)
            if k not in s:
                raise SystemExit("unknown setting " + k)
            s[k] = float(v)
    result = build(region_name, s)
    source = lua(result)
    size = len(source.encode())
    with open(os.path.join(CACHE, region_name + ".visgraph.lua"), "w", encoding="ascii") as handle:
        handle.write(source)
    print("%s.visgraph.lua: %d bytes" % (region_name, size), file=sys.stderr)
    score = known = None
    if "--score" in args and os.path.exists(os.path.join(CACHE, region_name + ".bench.json")):
        router = result["router"]
        hints, walked, wrong, starts = layer_hints(result)
        print("tracking from the entrance: %d of %d spans walked on the wrong layer, %d of %d trips started on it" % (
            wrong, walked, starts, len(hints)), file=sys.stderr)
        print("with the layers known (tracked start, target's layer from the guide):", file=sys.stderr)
        known = bench.score(region_name, "visgraph.layers",
                            lambda a, b: router.route(a, b, hints[(tuple(a), tuple(b))]), size)
        print("map % alone:", file=sys.stderr)
        score = bench.score(region_name, "visgraph", router.route, size)
        cases = bench.load(region_name)[2]["cases"]
        trips = [[c["from"]["at"], c["to"]["at"], None] for c in cases]
        trips += [[a, b, list(hints[(tuple(a), tuple(b))])] for a, b, _ in trips]
        worst, ms = compare_js(result, trips)
        print("visgraph.js under node: %.2f ms a route; largest difference from route() %s map %%" % (
            ms, "(a different route)" if worst == math.inf else "%.2g" % worst), file=sys.stderr)
    with open(os.path.join(CACHE, region_name + ".method.visgraph.json"), "w") as handle:
        json.dump(overlay(result, size, score, known), handle)


if __name__ == "__main__":
    main()
