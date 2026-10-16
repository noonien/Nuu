#!/usr/bin/env python3
"""A place as its rooms and the doorways between them, with no route in it:
the game works the way through at run time by pulling a string taut
through the doorways (the funnel algorithm).

    python3 Tools/ClientMap/methods/rooms.py venturemine [slope=40] [shave=1.0] ...

Starts from the floor bench.py measures on (the navmesh's pieces, cut down
to the way into the models), then:

  * drops what a player does not walk on: floor steeper than `slope`
    degrees (rock faces and ledges Recast lets through at 50; specks under
    `speck` square yards stay), a band of `shave` yards along every wall
    and drop (so no room is narrower than twice that, and a route never
    grazes a wall), and every piece this leaves that the ways in (and the
    region's lifts) do not reach: ledges, the tops of rocks. A piece of
    `neck` square yards or more that only the shave or a steep patch cut
    off (a spit past a narrow gap) gets a thin way back instead;
  * splits what is left into rooms: a watershed of the distance to the
    walls grows a region from the middle of every open space, and two
    regions are one room when the line where they meet is not a narrowing
    (at least `door` times the narrower one's width). A room never covers
    a column twice, so floors stacked over each other are always different
    rooms;
  * gives every room an outline, one plain polygon: a room round an
    obstacle (any over `obstacle` yards across; none are filled by
    default, so no route cuts through a pillar) is cut in two across it,
    scraps join the room next door, and each wall is simplified to within
    `tolerance` yards (`outward` limits how far it may stand out past the
    wall);
  * a doorway is a straight piece of the line two rooms share.

Nothing else ships: `lua()` is the place as a guide would carry it (the
outlines and which edges are doorways), and the game cuts each room into
triangles when the place is loaded. methods/rooms.js is the router, the
same algorithm the addon would run: Dijkstra over stops along the doorways
picks the rooms, the funnel through their doorways and the triangles of
each room gives the taut line, and a tracker keeps the room the player is
in from doorway to doorway.

Writes .cache/<region>.method.rooms.json for view.py and
.cache/<region>.rooms.place.lua. For a region with bench trips it runs
rooms.js in node on them (so the scores are the routes the viewer draws)
and scores them with bench.py as the viewer asks: start and target by map
position alone. It also prints two scores the viewer cannot ask for: with
the start's room known, as the tracker keeps it walking in, and with the
target's room pinned as well, as an author's `near` would.
"""

import collections
import json
import math
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import bench  # noqa: E402
import maps  # noqa: E402
import navgrid  # noqa: E402
import regions  # noqa: E402
import skeleton as sk  # noqa: E402
from casc import CACHE  # noqa: E402

SETTINGS = {
    "slope": 40.0,       # degrees: steeper floor is a wall, not a way
    "shave": 1.0,        # yards off every edge of the floor
    "door": 0.6,         # a doorway is narrower than this share of the narrower room
    "smallest": 40.0,    # square yards: a smaller region joins a neighbour
    "obstacle": 0.0,     # yards: smaller obstacles are filled in
    "tolerance": 0.6,    # yards a wall may move into its room when simplified...
    "outward": 0.6,      # ...and out past itself
    "door_tolerance": 0.4,
    "piece": 4.0,        # square yards: smaller scraps left by the cuts are dropped
    "speck": 4.0,        # square yards: smaller patches of steep floor are floor
    "neck": 20.0,        # square yards: a bigger piece the shave cuts off is joined back...
    "gap": 12.0,         # ...when the gap is shorter than this, in yards
}
UNIT = 0.001             # map % per unit of the shipped numbers
DIRS = [(-1, 0), (0, 1), (1, 0), (0, -1)]  # Recast's directions as (dx, dz)


# ---- The floor ----------------------------------------------------------------

def base_floor(region_name):
    """(grid, mask, starts): bench.py's floor where the region has an
    entrance, else every piece of 500 square yards or more (the way into the
    models only, as skeleton.py cuts it); `starts` are the spans the place
    is entered from (the region's exits)."""
    region = regions.REGIONS[region_name]
    if region_name in bench.ENTRANCES:
        grid, mask = bench.floor(region_name)
        return grid, mask, [bench.nearest_span(grid, mask, *bench.ENTRANCES[region_name])]
    base = navgrid.load(region_name)
    labels = base.components()
    sizes = np.bincount(labels)
    mask = sizes[labels] * base.cell ** 2 >= 500.0
    if region.get("terrain") == "approach":
        mask &= sk.near_models(base, region.get("approach", 30.0))
    grid = sk.Work(base)
    grid.source = base.source
    starts = []
    for at in region.get("exits", []):
        x, y = regions.to_world(region["map"], *at)
        span = bench.nearest_span(grid, mask, x, y, reach=10.0)
        if span is not None:
            starts.append(span)
    return grid, mask, starts


class Floor:
    """The spans kept, numbered 0.. in order (`span`), with their links to
    each other (`nb`, Recast's four directions, -1 for none) and columns."""

    def __init__(self, grid, keep):
        self.grid = grid
        self.span = np.nonzero(keep)[0]
        self.index = np.full(len(grid), -1, np.int64)
        self.index[self.span] = np.arange(len(self.span))
        links = grid.n[self.span]
        self.nb = np.where(links >= 0, self.index[np.maximum(links, 0)], -1)
        self.x = grid.x[self.span].astype(np.int64)
        self.z = grid.z[self.span].astype(np.int64)
        self.h = grid.bmin[1] + grid.y[self.span] * grid.cell_height

    def __len__(self):
        return len(self.span)

    def sub(self, keep):
        return Floor(self.grid, np.isin(np.arange(len(self.grid)), self.span[keep]))


def slopes(grid, mask):
    """Degrees of slope under each span of `mask`. Along each axis the
    height change over two cells ahead and two behind, and the gentler of
    the two when they agree (none when they do not): a ramp or a rock face
    rises on both sides of a span, while the edge of a crate, a rail or a
    step the navmesh climbs onto rises on one side only, and is no slope."""
    idx = np.nonzero(mask)[0]
    h = grid.bmin[1] + grid.y * grid.cell_height

    def step(s, d, k):
        for _ in range(k):
            s = np.where(s >= 0, grid.n[np.maximum(s, 0), d], -1)
        return s

    def gradient(forward, back):
        out = np.zeros(len(idx))
        seen = np.zeros(len(idx), bool)
        for k in (2, 1):
            a, b = step(idx, forward, k), step(idx, back, k)
            ahead = np.where(a >= 0, (h[np.maximum(a, 0)] - h[idx]) / (k * grid.cell), np.nan)
            behind = np.where(b >= 0, (h[idx] - h[np.maximum(b, 0)]) / (k * grid.cell), np.nan)
            both = ~np.isnan(ahead) & ~np.isnan(behind) & ~seen
            agree = both & (ahead * behind > 0)
            out[agree] = np.where(np.abs(ahead) < np.abs(behind), ahead, behind)[agree]
            seen |= both
        # A span with floor on one side only: that side's change.
        for k in (1,):
            a, b = step(idx, forward, k), step(idx, back, k)
            one = ~seen & ((a >= 0) != (b >= 0))
            value = np.where(a >= 0, h[np.maximum(a, 0)] - h[idx], h[idx] - h[np.maximum(b, 0)]) / grid.cell
            out[one] = value[one]
        return out

    out = np.zeros(len(grid))
    out[idx] = np.degrees(np.arctan(np.hypot(gradient(2, 0), gradient(1, 3))))
    return out


def distance(fl):
    """Each span's distance to the edge of the floor, 2 per straight step and
    3 per diagonal one (0 on the edge), as Recast counts it."""
    nb = fl.nb
    ring = []
    for d in range(4):
        e = (d + 1) % 4
        ring.append((nb[:, d], 2))
        via_d = np.where(nb[:, d] >= 0, nb[np.maximum(nb[:, d], 0), e], -1)
        via_e = np.where(nb[:, e] >= 0, nb[np.maximum(nb[:, e], 0), d], -1)
        ring.append((np.where(via_d >= 0, via_d, via_e), 3))
    edge = (nb < 0).any(axis=1)
    big = 1 << 20
    dist = np.where(edge, 0, big).astype(np.int64)
    while True:
        best = dist.copy()
        for other, cost in ring:
            best = np.minimum(best, np.where(other >= 0, dist[np.maximum(other, 0)] + cost, big))
        best[edge] = 0
        if (best == dist).all():
            return dist
        dist = best


def components(fl):
    """A piece number for every span (4-connected through links)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    rows = np.repeat(np.arange(len(fl)), 4)
    cols = fl.nb.reshape(-1)
    ok = cols >= 0
    links = coo_matrix((np.ones(ok.sum(), np.int8), (rows[ok], cols[ok])), shape=(len(fl), len(fl)))
    return connected_components(links, directed=False)[1]


def walkable_floor(region_name, s):
    """The floor a route may use, and what was dropped from it and why."""
    region = regions.REGIONS[region_name]
    grid, mask, starts = base_floor(region_name)
    slope = slopes(grid, mask)
    steep = mask & (slope > s["slope"])
    # Specks of steep floor (a bump, a crate's edge) are floor: shaved
    # round, a scatter of them would take a whole cave floor away.
    patches = Floor(grid, steep)
    if len(patches):
        pieces = components(patches)
        sizes = np.bincount(pieces) * grid.cell ** 2
        steep = np.isin(np.arange(len(grid)), patches.span[sizes[pieces] >= s["speck"]])
    flat = Floor(grid, mask & ~steep)
    # The shave, in distance units (2 per cell), from the edge left after
    # the navmesh's own half yard.
    dist = distance(flat)
    shaved = np.zeros(len(grid), bool)
    shaved[flat.span[dist >= s["shave"] * 2 / grid.cell]] = True
    kept = shaved.copy()
    whole = Floor(grid, mask)
    for _ in range(3):
        fl = Floor(grid, kept)
        pieces = components(fl)
        restored = necks(whole, flat, dist, steep, kept, fl, pieces, reached(grid, fl, pieces, starts, region)[0], s)
        if restored is None:
            break
        kept |= restored
    necked = kept & ~shaved
    steep &= ~kept
    fl = Floor(grid, kept)
    pieces = components(fl)
    wanted, lifts = reached(grid, fl, pieces, starts, region)
    inside = np.isin(pieces, sorted(wanted))
    dropped = {
        "all": int(mask.sum()), "shaved": int(len(flat) - shaved.sum()), "necks": int(necked.sum()), "given": necked,
        "steep": steep,
        "ledges": np.isin(np.arange(len(grid)), fl.span[~inside]),
    }
    fl = fl.sub(inside)
    joined = []
    for at, (top, bottom) in lifts:
        a, b = _index_of(fl, top), _index_of(fl, bottom)
        if a >= 0 and b >= 0:
            joined.append((at, a, b))
    return grid, fl, dropped, joined


def reached(grid, fl, pieces, starts, region):
    """(pieces, lifts): the pieces of `fl` the ways in stand on (the
    nearest span to each) and those the region's lifts join to them; each
    lift found as (map %, (top span, bottom span))."""
    wanted = wanted_pieces(grid, fl, pieces, starts)
    sizes = np.bincount(pieces) * grid.cell ** 2
    lifts = []
    for at in region.get("lifts", []):
        x, y = regions.to_world(region["map"], *at)
        found = lift_ends(fl, pieces, sizes, x, y)
        if found:
            lifts.append((at, found))
    changed = True
    while changed:
        changed = False
        for at, (top, bottom) in lifts:
            a, b = int(pieces[fl.index[top]]), int(pieces[fl.index[bottom]])
            if (a in wanted) != (b in wanted):
                wanted.update((a, b))
                changed = True
    return wanted, lifts


def wanted_pieces(grid, fl, pieces, starts):
    """The pieces of `fl` the ways in stand on (the nearest span to each)."""
    wanted = set()
    for start in starts:
        best, best_d = None, None
        sx, sy, sh = grid.world(start)
        near = np.nonzero((np.abs(fl.x - grid.x[start]) <= 30) & (np.abs(fl.z - grid.z[start]) <= 30))[0]
        for i in near:
            wx, wy, wh = grid.world(fl.span[i])
            d = math.hypot(wx - sx, wy - sy) + abs(wh - sh) * 4
            if best_d is None or d < best_d:
                best, best_d = i, d
        if best is not None:
            wanted.add(int(pieces[best]))
    if not wanted and len(fl):
        wanted.add(int(np.argmax(np.bincount(pieces))))
    return wanted


def necks(whole, flat, dist, steep, kept, fl, pieces, wanted, s):
    """What to give back of the floor dropped so that nothing is cut off: a
    piece of `neck` square yards or more that only the shave or a steep
    patch parted from the floor the ways in are on (a spit of floor past a
    narrow gap, a ramp too steep for the rest of the rooms) gets a thin way
    back, along the middle of the gap and the gentlest of the slope, when
    the gap is under `gap` yards. Returns a mask over the whole navmesh, or
    None when nothing is given back."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra
    grid = whole.grid
    cell = grid.cell
    sizes = np.bincount(pieces) * cell ** 2
    lost = [p for p in range(len(sizes)) if p not in wanted and sizes[p] >= s["neck"]]
    if not lost:
        return None
    # Over the whole floor from the wanted pieces: a step costs more by the
    # walls and more again on steep floor.
    full = s["shave"] * 2 / cell
    near_wall = np.full(len(whole), full)
    inflat = flat.index[whole.span]
    near_wall[inflat >= 0] = np.minimum(full, dist[inflat[inflat >= 0]])
    toll = 1 + 2 * (full - near_wall) + 8 * steep[whole.span]
    rows = np.repeat(np.arange(len(whole)), 4)
    cols = whole.nb.reshape(-1)
    ok = cols >= 0
    graph = coo_matrix((toll[cols[ok]], (rows[ok], cols[ok])), shape=(len(whole), len(whole))).tocsr()
    at = whole.index[fl.span]
    sources = at[np.isin(pieces, sorted(wanted))]
    cost, pred, _ = dijkstra(graph, indices=sources, min_only=True, return_predecessors=True,
                             limit=s["gap"] / cell * 17)
    source = set(sources.tolist())
    restored = np.zeros(len(grid), bool)
    for p in lost:
        members = at[pieces == p]
        reach = cost[members]
        if not np.isfinite(reach).any():
            continue
        u = int(members[np.argmin(reach)])
        path = []
        while u >= 0:
            path.append(u)
            if u in source:
                break
            u = int(pred[u])
        # The way and the floor two steps round it (a way one cell wide
        # would touch itself at corners, and be cut there).
        ring = set(path)
        for _ in range(2):
            ring |= {int(o) for v in ring for o in whole.nb[v] if o >= 0}
        restored[whole.span[sorted(ring)]] = True
    restored &= ~kept
    return restored if restored.any() else None


def lift_ends(fl, pieces, sizes, x, y, reach=8.0):
    """The spans a lift at world (x, y) joins: the top floor there and the
    next big floor at least 8 yd under it. None if there are not two."""
    g = fl.grid
    column = g.grid.column_of(x, y)
    if column is None:
        return None
    cx, cz = column % g.grid.width, column // g.grid.width
    cells = int(reach / g.cell)
    near = np.nonzero((np.abs(fl.x - cx) <= cells) & (np.abs(fl.z - cz) <= cells))[0]
    near = [i for i in near if sizes[pieces[i]] >= 200]
    if not near:
        return None
    near.sort(key=lambda i: -fl.h[i])
    top = near[0]
    below = [i for i in near if fl.h[i] < fl.h[top] - 8]
    if not below:
        return None
    return int(fl.span[top]), int(fl.span[below[0]])


def _index_of(fl, span):
    """The number of global span `span` in `fl`, -1 if it is not kept."""
    return int(fl.index[span])


# ---- Rooms --------------------------------------------------------------------

def watershed(fl, dist):
    """A region for every open space: flooding down from the middles of the
    floor (the highest distance to a wall), level by level, each region
    grows into what the water reaches next to it, and floor the water
    reaches away from every region starts a new one. A region never takes a
    second span in a column it already has."""
    n = len(fl)
    width = fl.grid.grid.width
    column = fl.x + fl.z * width
    columns = int(column.max()) + 1
    label = np.full(n, -1, np.int64)
    owned = set()
    order = np.argsort(-dist, kind="stable")
    top = int(dist[order[0]]) if n else 0
    boundary = collections.deque()
    count = 0
    at = 0

    def take(span, region):
        key = region * columns + int(column[span])
        if key in owned:
            return False
        owned.add(key)
        label[span] = region
        return True

    for level in range(top - top % 2, -1, -2):
        while at < n and dist[order[at]] >= level:
            at += 1
        # Grow every region into the floor now under water beside it.
        queue = collections.deque(s for s in boundary)
        boundary = collections.deque()
        while queue:
            s = queue.popleft()
            r = label[s]
            open_side = False
            for o in fl.nb[s]:
                if o < 0 or label[o] >= 0:
                    continue
                if dist[o] >= level and take(o, r):
                    queue.append(o)
                else:
                    open_side = True
            if open_side:
                boundary.append(s)
        # What is left under water starts regions of its own.
        for i in range(at):
            s = order[i]
            if label[s] >= 0:
                continue
            region = count
            count += 1
            take(s, region)
            flood = collections.deque([s])
            while flood:
                u = flood.popleft()
                open_side = False
                for o in fl.nb[u]:
                    if o < 0 or label[o] >= 0:
                        continue
                    if dist[o] >= level and take(o, region):
                        flood.append(o)
                    else:
                        open_side = True
                if open_side:
                    boundary.append(u)
    return label


def borders(fl, label):
    """{(a, b): links between region a and region b} for a < b."""
    out = collections.Counter()
    for d in (1, 2):
        other = fl.nb[:, d]
        ok = other >= 0
        a, b = label[ok], label[other[ok]]
        diff = (a != b) & (a >= 0) & (b >= 0)
        for x, y in zip(a[diff], b[diff]):
            out[(min(x, y), max(x, y))] += 1
    return out


def merge(fl, dist, label, s):
    """Joins regions that are one space: where the line two regions share
    is at least `door` times the narrower one's width, it is not a
    doorway; and a region under `smallest` square yards joins the neighbour
    it shares most with. Never two spans of one column in a room."""
    cell = fl.grid.cell
    width = fl.grid.grid.width
    column = fl.x + fl.z * width
    n_regions = int(label.max()) + 1
    parent = list(range(n_regions))
    area = np.bincount(label, minlength=n_regions).astype(float) * cell * cell
    peak = np.zeros(n_regions)
    np.maximum.at(peak, label, dist)
    cols = [set() for _ in range(n_regions)]
    for span, r in enumerate(label):
        cols[r].add(int(column[span]))
    adj = collections.defaultdict(collections.Counter)
    for (a, b), links in borders(fl, label).items():
        adj[a][b] += links
        adj[b][a] += links

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def join(a, b):
        # b into a
        parent[b] = a
        area[a] += area[b]
        peak[a] = max(peak[a], peak[b])
        cols[a] |= cols[b]
        cols[b] = set()
        for c, links in adj.pop(b, {}).items():
            if c == a:
                continue
            adj[a][c] += links
            adj[c][a] += links
            del adj[c][b]
        adj[a].pop(b, None)

    def wide(r):
        # The room's width at its widest, in yards (distance units are a
        # quarter of a cell each side).
        return 2 * (peak[r] * cell / 2 + cell / 2)

    changed = True
    while changed:
        changed = False
        pairs = []
        for a in list(adj):
            for b, links in adj[a].items():
                if a < b:
                    share = links * cell / min(wide(a), wide(b))
                    small = bool(min(area[a], area[b]) < s["smallest"])
                    pairs.append((small, share, a, b))
        pairs.sort(key=lambda p: (-p[0], -p[1]))
        for small, share, a, b in pairs:
            if root(a) != a or root(b) != b:
                continue
            if not small and share < s["door"]:
                continue
            if small:
                # The smaller one joins the neighbour it shares most with.
                little = a if area[a] <= area[b] else b
                best = max(adj[little].items(), key=lambda item: item[1])[0] if adj[little] else None
                other = best
                if other is None:
                    continue
                if cols[little] & cols[other]:
                    continue
                a, b = (other, little) if area[other] >= area[little] else (little, other)
            elif cols[a] & cols[b]:
                continue
            if area[b] > area[a]:
                a, b = b, a
            join(a, b)
            changed = True
    roots = sorted({root(r) for r in range(n_regions)})
    number = {r: i for i, r in enumerate(roots)}
    return np.array([number[root(r)] for r in label], np.int64)


def raster(fl, spans):
    """The spans' columns as a 2D picture with a blank border: (picture,
    span at each cell or -1, x of column 0, z of row 0)."""
    xs, zs = fl.x[spans], fl.z[spans]
    x0, z0 = int(xs.min()) - 1, int(zs.min()) - 1
    shape = (int(zs.max()) - z0 + 2, int(xs.max()) - x0 + 2)
    at = np.full(shape, -1, np.int64)
    at[zs - z0, xs - x0] = spans
    return at >= 0, at, x0, z0


def tidy(fl, label, s):
    """Makes every room one plain polygon on the map. A room's cells must
    touch where they meet (a cell beside another of the same room but not
    linked to it, across a step too high, is dropped), never only at a
    corner (one of the two is dropped), and be one piece (small pieces are
    dropped, big ones become rooms). Holes under `obstacle` yards across
    are filled; a room round a bigger one, or round another room, is cut in
    two by a straight line across the hole, the shorter way.

    Returns (label, fills, cuts): fills is {room: [(x, z) filled]}, cuts
    the lines cut, as ((x, z), (x, z)) in cell corners."""
    from scipy import ndimage
    cell = fl.grid.cell
    label = label.copy()
    order = np.argsort(label, kind="stable")
    bounds = np.searchsorted(label[order], np.arange(label.max() + 2))
    members = {r: order[bounds[r]:bounds[r + 1]] for r in range(label.max() + 1)}
    fills, cuts = {}, []
    work = collections.deque(sorted(members))
    next_id = label.max() + 1
    smallest_piece = max(4, int(s["piece"] / cell ** 2))

    def drop(spans):
        label[spans] = -1

    def adopt(cells, r):
        """A scrap of room r joins the room next to it it is most linked
        to, if that room has none of its columns (dropping it could cut a
        way through). False if there is none."""
        links = collections.Counter()
        for c in cells:
            for o in fl.nb[c]:
                if o >= 0 and label[o] >= 0 and label[o] != r:
                    links[int(label[o])] += 1
        column = fl.x[cells] + fl.z[cells] * fl.grid.grid.width
        for other, _ in links.most_common():
            theirs = members.get(other)
            if theirs is None:
                continue
            theirs = theirs[label[theirs] == other]
            if np.isin(column, fl.x[theirs] + fl.z[theirs] * fl.grid.grid.width).any():
                continue
            label[cells] = other
            members[other] = np.concatenate([theirs, cells])
            work.append(other)
            return True
        return False

    while work:
        r = work.popleft()
        spans = members.get(r)
        if spans is None:
            continue
        spans = spans[label[spans] == r]
        members[r] = spans
        if len(spans) == 0:
            del members[r]
            continue
        inside, at, x0, z0 = raster(fl, spans)
        # Cells side by side but not linked.
        bad = set()
        for d, (dx, dz) in enumerate(DIRS):
            if dx < 0 or dz < 0:
                continue
            here = at[max(0, -dz):at.shape[0] - max(0, dz), max(0, -dx):at.shape[1] - max(0, dx)]
            there = at[max(0, dz):, max(0, dx):][:here.shape[0], :here.shape[1]]
            both = (here >= 0) & (there >= 0)
            a, b = here[both], there[both]
            unlinked = fl.nb[a, d] != b
            for p, q in zip(a[unlinked], b[unlinked]):
                bad.add(int(p) if fl.h[p] < fl.h[q] else int(q))
        if bad:
            drop(np.array(sorted(bad)))
            work.appendleft(r)
            continue
        # Cells meeting only at a corner.
        a, b = inside[:-1, :-1], inside[:-1, 1:]
        c, d = inside[1:, :-1], inside[1:, 1:]
        pinch = (a & d & ~b & ~c) | (b & c & ~a & ~d)
        if pinch.any():
            count = ndimage.convolve(inside.astype(int), [[0, 1, 0], [1, 0, 1], [0, 1, 0]], mode="constant")
            gone = set()
            for i, j in np.argwhere(pinch):
                pair = [(i, j), (i + 1, j + 1)] if a[i, j] and d[i, j] else [(i, j + 1), (i + 1, j)]
                pair.sort(key=lambda p: count[p])
                gone.add(int(at[pair[0]]))
            drop(np.array(sorted(gone)))
            work.appendleft(r)
            continue
        # One piece.
        pieces, count = ndimage.label(inside)
        if count > 1:
            sizes = np.bincount(pieces.ravel())
            sizes[0] = 0
            keep = int(np.argmax(sizes))
            for piece in range(1, count + 1):
                if piece == keep:
                    continue
                cells = at[pieces == piece]
                if sizes[piece] < smallest_piece and adopt(cells, r):
                    continue
                label[cells] = next_id
                members[next_id] = cells
                work.append(next_id)
                next_id += 1
            work.appendleft(r)
            continue
        # Holes.
        holes, count = ndimage.label(~inside)
        outside = holes[0, 0]
        filled = []
        cut = None
        for hole in range(1, count + 1):
            if hole == outside:
                continue
            mask = holes == hole
            across = 2 * ndimage.distance_transform_edt(np.pad(mask, 1)).max() * cell
            # A room on the far side of the hole's edge makes it a room
            # inside this one, not an obstacle.
            ring = ndimage.binary_dilation(mask) & inside
            enclosed = False
            for i, j in np.argwhere(ring):
                span = at[i, j]
                for d, (dx, dz) in enumerate(DIRS):
                    if mask[i + dz, j + dx]:
                        other = fl.nb[span, d]
                        if other >= 0 and label[other] >= 0:
                            enclosed = True
            if not enclosed and across - 2 * (s["shave"] + 0.5) < s["obstacle"]:
                filled += [(int(j + x0), int(i + z0)) for i, j in np.argwhere(mask)]
            elif cut is None or mask.sum() > cut.sum():
                cut = mask
        if cut is not None:
            rows, cols = np.nonzero(cut)
            zc, xc = int(np.median(rows)), int(np.median(cols))
            # Across the hole the shorter way: a row or a column of the room.
            by_row = int((inside[zc - 1] & inside[zc]).sum())
            by_col = int((inside[:, xc - 1] & inside[:, xc]).sum())
            halves = []
            if by_row <= by_col:
                top = inside.copy()
                top[zc:] = False
                halves = [top, inside & ~top]
                cuts.append(((x0, z0 + zc), (x0 + inside.shape[1], z0 + zc)))
            else:
                left = inside.copy()
                left[:, xc:] = False
                halves = [left, inside & ~left]
                cuts.append(((x0 + xc, z0), (x0 + xc, z0 + inside.shape[0])))
            first = True
            for half in halves:
                pieces, count = ndimage.label(half)
                for piece in range(1, count + 1):
                    cells = at[pieces == piece]
                    if len(cells) < smallest_piece and adopt(cells, r):
                        continue
                    if first:
                        label[cells] = r
                        members[r] = cells
                        work.append(r)
                        first = False
                    else:
                        label[cells] = next_id
                        members[next_id] = cells
                        work.append(next_id)
                        next_id += 1
            if first:
                del members[r]
            continue
        fills[r] = filled
    # Number the rooms left from 0.
    used = sorted(set(label[label >= 0].tolist()))
    number = {r: i for i, r in enumerate(used)}
    out = np.array([number.get(int(r), -1) for r in label], np.int64)
    return out, {number[r]: f for r, f in fills.items() if r in number}, cuts


# ---- Outlines -----------------------------------------------------------------

WALL = -1


def trace(fl, label, fills, r, spans):
    """The room's outline as cell corners (x, z), anticlockwise with x
    across and z down the grid's rows, and what lies across each edge: the
    room on the other side (a doorway) or WALL."""
    inside, at, x0, z0 = raster(fl, spans)
    for x, z in fills.get(r, []):
        inside[z - z0, x - x0] = True
    # Every edge of the room's cells with the room on its left.
    edges = {}
    height, width = inside.shape
    for i, j in np.argwhere(inside):
        span = at[i, j]
        x, z = j + x0, i + z0
        corners = [((x, z + 1), (x, z)), ((x + 1, z + 1), (x, z + 1)),
                   ((x + 1, z), (x + 1, z + 1)), ((x, z), (x + 1, z))]
        for d, (dx, dz) in enumerate(DIRS):
            if inside[i + dz, j + dx]:
                continue
            across = WALL
            if span >= 0:
                other = fl.nb[span, d]
                if other >= 0 and label[other] >= 0 and label[other] != r:
                    across = int(label[other])
            start, end = corners[d]
            edges[start] = (end, across)
    loops = []
    while edges:
        start = next(iter(edges))
        loop, kinds = [], []
        point = start
        while point in edges:
            end, across = edges.pop(point)
            loop.append(point)
            kinds.append(across)
            point = end
        loops.append((loop, kinds))
    # The outer one is the largest (the others would be holes left open).
    loops.sort(key=lambda lk: -abs(area2(lk[0])))
    return loops[0], len(loops) - 1


def area2(points):
    """Twice the signed area of a ring."""
    total = 0
    for i in range(len(points)):
        x1, y1 = points[i - 1]
        x2, y2 = points[i]
        total += x1 * y2 - x2 * y1
    return total


def simplify(points, tolerance):
    """Douglas-Peucker: the indices of `points` to keep so that no point
    left out is further than `tolerance` from the line kept, ends kept."""
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        (ax, ay), (bx, by) = points[a], points[b]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        best, best_d = None, -1.0
        for i in range(a + 1, b):
            px, py = points[i]
            if length:
                dist = abs(dx * (py - ay) - dy * (px - ax)) / length
            else:
                dist = math.hypot(px - ax, py - ay)
            if dist > best_d:
                best, best_d = i, dist
        if best_d > tolerance or (tolerance <= 0 and best_d > 1e-9):
            keep.add(best)
            stack += [(a, best), (best, b)]
    return sorted(keep)


def runs(loop, kinds):
    """The outline cut where what lies across changes: [(across, [points])],
    each run's points from its first corner to its last, ends shared with
    the runs beside it."""
    n = len(loop)
    change = [i for i in range(n) if kinds[i] != kinds[i - 1]]
    if not change:
        # One kind all round: cut it at the corner farthest from the first.
        far = max(range(n), key=lambda i: (loop[i][0] - loop[0][0]) ** 2 + (loop[i][1] - loop[0][1]) ** 2)
        return [(kinds[0], loop[:far + 1]), (kinds[0], loop[far:] + [loop[0]])]
    out = []
    for k, first in enumerate(change):
        last = change[(k + 1) % len(change)]
        if last <= first:
            last += n
        out.append((kinds[first], [loop[i % n] for i in range(first, last + 1)]))
    return out


def canonical(points):
    points = [tuple(p) for p in points]
    return tuple(points) if points[0] <= points[-1] else tuple(points[::-1])


def simplify_wall(points, inward, outward, turn):
    """Douglas-Peucker for a wall, one-sided: the indices of `points` to
    keep so that the line kept cuts no more than `inward` into the room
    and stands no more than `outward` out past the wall (a route along it
    must stay on the floor). `turn` is the sign of the ring's area: the
    room is on the left of each edge when it is positive."""
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        (ax, ay), (bx, by) = points[a], points[b]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        best, worst = None, 1.0
        for i in range(a + 1, b):
            px, py = points[i]
            if length:
                d = turn * (dx * (py - ay) - dy * (px - ax)) / length
            else:
                d = -math.hypot(px - ax, py - ay)
            # d > 0: the corner is inside the room, the line passes outside it.
            over = d / outward if d > 0 else -d / inward
            if over > worst:
                best, worst = i, over
        if best is not None:
            keep.add(best)
            stack += [(a, best), (best, b)]
    return sorted(keep)


def outline(run_list, door_memo, raw_doors, tolerance, door_tolerance, cell, turn=1, outward=0.25):
    """The room's polygon from its runs: walls simplified to `tolerance`
    yards, each doorway run the same way from both its rooms (to
    `door_tolerance`, or corner by corner for those in `raw_doors`).
    Returns (points, across) with across[i] the kind of edge i."""
    points, across = [], []
    for kind, run in run_list:
        if kind == WALL:
            if tolerance > 0:
                kept = [run[i] for i in simplify_wall(run, tolerance / cell, min(tolerance, outward) / cell, turn)]
            else:
                kept = [run[i] for i in simplify(run, 0)]
        else:
            key = canonical(run)
            if key not in door_memo or (key in raw_doors) != door_memo[key][0]:
                raw = key in raw_doors
                door_memo[key] = (raw, [key[i] for i in simplify(list(key), 0 if raw else door_tolerance / cell)])
            kept = list(door_memo[key][1])
            if kept[0] != tuple(run[0]):
                kept = kept[::-1]
        for p in kept[:-1]:
            points.append(tuple(p))
            across.append(kind)
    return points, across


def simple(points):
    """Whether a ring is a plain polygon: no repeated corner, no edge
    touching another except its neighbours at their shared corner, no
    edge folding back over the one before."""
    n = len(points)
    if n < 3 or len(set(points)) != n:
        return False

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def on(p, a, b):
        return min(a[0], b[0]) <= p[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= p[1] <= max(a[1], b[1])

    def meet(a, b, c, d):
        d1, d2 = cross(c, d, a), cross(c, d, b)
        d3, d4 = cross(a, b, c), cross(a, b, d)
        if ((d1 > 0) != (d2 > 0)) and d1 and d2 and ((d3 > 0) != (d4 > 0)) and d3 and d4:
            return True
        return ((d1 == 0 and on(a, c, d)) or (d2 == 0 and on(b, c, d)) or
                (d3 == 0 and on(c, a, b)) or (d4 == 0 and on(d, a, b)))

    boxes = []
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        boxes.append((min(a[0], b[0]), max(a[0], b[0]), min(a[1], b[1]), max(a[1], b[1])))
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        # Folding back: the next edge runs back along this one.
        c = points[(i + 2) % n]
        if cross(a, b, c) == 0 and (c[0] - b[0]) * (a[0] - b[0]) + (c[1] - b[1]) * (a[1] - b[1]) > 0:
            return False
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            bi, bj = boxes[i], boxes[j]
            if bi[1] < bj[0] or bj[1] < bi[0] or bi[3] < bj[2] or bj[3] < bi[2]:
                continue
            if meet(a, b, points[j], points[(j + 1) % n]):
                return False
    return True


class Mapper:
    """Cell corners (x, z) to map % and to the whole numbers shipped."""

    def __init__(self, grid, region):
        self.grid, self.map = grid, region["map"]
        self.frame = maps.get(self.map)
        self.origin = None

    def to_map(self, x, z):
        g, b = self.grid, self.frame
        wx = g.bmin[0] + x * g.cell
        wy = -(g.bmin[2] + z * g.cell)
        # regions.to_map, with the map's frame read once.
        return ((wy - b["left"]) / (b["right"] - b["left"]) * 100, (wx - b["top"]) / (b["bottom"] - b["top"]) * 100)

    def fix_origin(self, corners):
        xs, ys = zip(*(self.to_map(x, z) for x, z in corners))
        self.origin = (math.floor(min(xs) * 100) / 100, math.floor(min(ys) * 100) / 100)

    def unit(self, x, z):
        mx, my = self.to_map(x, z)
        return (int(round((mx - self.origin[0]) / UNIT)), int(round((my - self.origin[1]) / UNIT)))

    def back(self, p):
        return [round(self.origin[0] + p[0] * UNIT, 4), round(self.origin[1] + p[1] * UNIT, 4)]


def build(region_name, s=None):
    s = dict(SETTINGS, **(s or {}))
    region = regions.REGIONS[region_name]
    grid, fl, dropped, lifts = walkable_floor(region_name, s)
    print("floor: %d square yards of %d: %d steep, %d shaved off the edges (%d given back at necks), %d on ledges dropped" % (
        len(fl) * grid.cell ** 2, dropped["all"] * grid.cell ** 2, dropped["steep"].sum() * grid.cell ** 2,
        dropped["shaved"] * grid.cell ** 2, dropped["necks"] * grid.cell ** 2, dropped["ledges"].sum() * grid.cell ** 2),
        file=sys.stderr)
    dist = distance(fl)
    label = watershed(fl, dist)
    print("watershed: %d regions" % (label.max() + 1), file=sys.stderr)
    label = merge(fl, dist, label, s)
    print("joined: %d rooms" % (label.max() + 1), file=sys.stderr)
    label, fills, cuts = tidy(fl, label, s)
    count = int(label.max()) + 1
    print("in rooms: %d square yards" % ((label >= 0).sum() * grid.cell ** 2), file=sys.stderr)
    print("tidied: %d rooms, %d obstacles filled, %d cut across" % (
        count, sum(1 for f in fills.values() if f), len(cuts)), file=sys.stderr)
    order = np.argsort(label, kind="stable")
    bounds = np.searchsorted(label[order], np.arange(count + 1))
    members = [order[bounds[r]:bounds[r + 1]] for r in range(count)]
    traced, turns = [], []
    for r in range(count):
        (loop, kinds), open_holes = trace(fl, label, fills, r, members[r])
        if open_holes:
            print("room %d: %d holes left open" % (r, open_holes), file=sys.stderr)
        traced.append(runs(loop, kinds))
        turns.append(1 if area2(loop) > 0 else -1)
    mapper = Mapper(grid, region)
    mapper.fix_origin([p for run_list in traced for _, run in run_list for p in run])
    # Outlines: simplify, and where a room comes out crossing itself, again
    # more closely; its doorways corner by corner as a last resort.
    door_memo, raw_doors = {}, set()
    tolerance = [s["tolerance"]] * count
    for _ in range(20):
        polys, bad = [], []
        for r in range(count):
            points, across = outline(traced[r], door_memo, raw_doors, tolerance[r], s["door_tolerance"], grid.cell,
                                     turns[r], s["outward"])
            ints = [mapper.unit(*p) for p in points]
            polys.append((ints, across))
            if not simple(ints):
                bad.append(r)
        if not bad:
            break
        for r in bad:
            if tolerance[r] > 0:
                tolerance[r] = tolerance[r] / 2 if tolerance[r] > 0.15 else 0
            else:
                for kind, run in traced[r]:
                    if kind != WALL:
                        raw_doors.add(canonical(run))
    if bad:
        print("rooms still crossing themselves: %s" % bad, file=sys.stderr)
    # Every room anticlockwise on the numbers shipped (x across, y down the
    # map, so clockwise on the screen): the router relies on it.
    for r in range(count):
        ints, across = polys[r]
        if area2(ints) < 0:
            n = len(ints)
            ints = ints[::-1]
            across = [across[(n - 2 - k) % n] for k in range(n)]
            polys[r] = (ints, across)
    # Doorways: an edge of one room that is the same edge the other way
    # round in the room across it.
    where = {}
    for r, (ints, across) in enumerate(polys):
        for i in range(len(ints)):
            if across[i] != WALL:
                where[(ints[i], ints[(i + 1) % len(ints)])] = (r, i)
    doors, unmatched = [], 0
    for r, (ints, across) in enumerate(polys):
        for i in range(len(ints)):
            if across[i] == WALL:
                continue
            other = where.get((ints[(i + 1) % len(ints)], ints[i]))
            if other is None or other[0] != across[i]:
                unmatched += 1
                continue
            if r < other[0]:
                doors.append([r, i, other[0], other[1]])
    if unmatched:
        print("%d doorway edges with no match" % unmatched, file=sys.stderr)

    # Lifts: from the room at the top to the room at the bottom, at the spot.
    lift_rows = []
    for at, top, bottom in lifts:
        a, b = int(label[top]), int(label[bottom])
        if a >= 0 and b >= 0:
            x, y = regions.to_map(region["map"], *grid.world(fl.span[top])[:2])
            lift_rows.append([a, b, int(round((x - mapper.origin[0]) / UNIT)), int(round((y - mapper.origin[1]) / UNIT))])
    # Rooms no doorway or lift reaches.
    parent = list(range(count))

    def root(i):
        while parent[i] != i:
            i = parent[i]
        return i
    for a, _, b, _ in doors:
        parent[root(a)] = root(b)
    for a, b, _, _ in lift_rows:
        parent[root(a)] = root(b)
    groups = collections.defaultdict(list)
    for r in range(count):
        groups[root(r)].append(r)
    if len(groups) > 1:
        print("rooms apart from the rest: %s" % sorted((g for g in groups.values() if len(g) < count / 2), key=len),
              file=sys.stderr)
    exits = []
    for at in region.get("exits", []):
        x, y = regions.to_world(region["map"], *at)
        column = grid.grid.column_of(x, y)
        best = None
        if column is not None:
            cx, cz = column % grid.grid.width, column // grid.grid.width
            near = np.nonzero((np.abs(fl.x - cx) <= 40) & (np.abs(fl.z - cz) <= 40) & (label >= 0))[0]
            if len(near):
                best = near[np.argmin((fl.x[near] - cx) ** 2 + (fl.z[near] - cz) ** 2)]
        if best is not None:
            exits.append([int(label[best]), int(round((at[0] - mapper.origin[0]) / UNIT)),
                          int(round((at[1] - mapper.origin[1]) / UNIT))])
    info = []
    for r in range(count):
        spans = members[r]
        info.append({"area": round(len(spans) * grid.cell ** 2), "low": round(float(fl.h[spans].min()), 1),
                     "high": round(float(fl.h[spans].max()), 1), "tolerance": tolerance[r]})
    return {"region": region_name, "map": region["map"], "name": region.get("title") or regions.name(region), "settings": s,
            "origin": list(mapper.origin), "unit": UNIT, "yards": yards_per_percent(region["map"]),
            "rooms": [p[0] for p in polys], "doors": doors, "lifts": lift_rows, "exits": exits,
            "info": info, "grid": grid, "fl": fl, "label": label, "fills": fills, "cuts": cuts,
            "dropped": dropped, "mapper": mapper}


def yards_per_percent(map_id):
    b = maps.get(map_id)
    return [abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100]


# ---- What ships ---------------------------------------------------------------

def router_data(result):
    """What rooms.js is given: the rooms as whole numbers of `unit` map %
    from `origin`, and the doorways, lifts and ways in, numbered from 0."""
    return {"origin": result["origin"], "unit": result["unit"], "yards": result["yards"],
            "rooms": [[list(p) for p in ring] for ring in result["rooms"]],
            "doors": result["doors"], "lifts": result["lifts"], "exits": result["exits"]}


def numbers(values, per_line, indent):
    lines = []
    for i in range(0, len(values), per_line):
        lines.append(indent + ", ".join(str(v) for v in values[i:i + per_line]) + ",")
    return "\n".join(lines)


def lua(result):
    """The place as a guide would carry it, one entry of a guide's `places`
    (docs/guide-source.md) with rooms in place of points and connections:

      * `rooms`: a list of rooms, each one list of numbers: its first
        corner, then each next corner as the step from the one before (x, y
        pairs in `unit` map % from `origin`), anticlockwise with y down the
        map. Edge k of a room runs from its corner k to corner k + 1.
      * `doors`: a list of {room, edge, room, edge}: the edge the two rooms
        share, the way through (rooms and edges numbered from 1).
      * `lifts`: {top room, bottom room, x, y}; `entrances`: {room, x, y},
        where the place is walked into.

    Lists and keys are never mixed in one table. A step's `near` would name
    a room by a point the author labels (not shown here)."""
    out = ["-- Tools/ClientMap/methods/rooms.py %s: %d rooms, %d doorways, %d corners" % (
        result["region"], len(result["rooms"]), len(result["doors"]), sum(len(r) for r in result["rooms"])),
        "{ place = %s, name = %s, map = %d, origin = { %s, %s }, unit = %s," % (
            json.dumps(result["region"]), json.dumps(result["name"]), result["map"],
            repr(result["origin"][0]), repr(result["origin"][1]), repr(result["unit"])),
        "  rooms = {"]
    for r, ring in enumerate(result["rooms"]):
        flat = [ring[0][0], ring[0][1]]
        for i in range(1, len(ring)):
            flat += [ring[i][0] - ring[i - 1][0], ring[i][1] - ring[i - 1][1]]
        out.append("    { -- %d" % (r + 1))
        out.append(numbers(flat, 24, "      "))
        out.append("    },")
    out.append("  },")
    out.append("  doors = {")
    rows = ["{ %d, %d, %d, %d }," % (a + 1, ea + 1, b + 1, eb + 1) for a, ea, b, eb in result["doors"]]
    for i in range(0, len(rows), 6):
        out.append("    " + " ".join(rows[i:i + 6]))
    out.append("  },")
    out.append("  lifts = { %s}," % "".join("{ %d, %d, %d, %d }, " % (a + 1, b + 1, x, y) for a, b, x, y in result["lifts"]))
    out.append("  entrances = { %s}," % "".join("{ %d, %d, %d }, " % (r + 1, x, y) for r, x, y in result["exits"]))
    out.append("},")
    return "\n".join(out) + "\n"


# ---- Drawing ------------------------------------------------------------------

def cell_rings(mapper, cells, tolerance):
    """Outlines (map %) of a set of columns (x, z): [[ring, ...], ...] for
    each piece, outer ring first, holes after (drawn even-odd)."""
    from scipy import ndimage
    if not cells:
        return []
    xs = np.array([c[0] for c in cells])
    zs = np.array([c[1] for c in cells])
    x0, z0 = int(xs.min()) - 1, int(zs.min()) - 1
    img = np.zeros((int(zs.max()) - z0 + 2, int(xs.max()) - x0 + 2), bool)
    img[zs - z0, xs - x0] = True
    pieces, count = ndimage.label(img)
    out = []
    for piece in range(1, count + 1):
        inside = pieces == piece
        edges = {}
        for i, j in np.argwhere(inside):
            x, z = j + x0, i + z0
            corners = [((x, z + 1), (x, z)), ((x + 1, z + 1), (x, z + 1)),
                       ((x + 1, z), (x + 1, z + 1)), ((x, z), (x + 1, z))]
            for d, (dx, dz) in enumerate(DIRS):
                if not inside[i + dz, j + dx]:
                    edges[corners[d][0]] = corners[d][1]
        rings = []
        while edges:
            start = next(iter(edges))
            loop, point = [], start
            while point in edges:
                loop.append(point)
                point = edges.pop(point)
            loop.append(loop[0])
            kept = [loop[k] for k in simplify(loop, tolerance)][:-1]
            if len(kept) >= 3:
                rings.append([[round(v, 4) for v in mapper.to_map(*p)] for p in kept])
        rings.sort(key=lambda r: -abs(area2(r)))
        if rings:
            out.append(rings)
    return out


def spans_cells(grid, spans):
    return sorted({(int(grid.x[s]), int(grid.z[s])) for s in spans})


def overlay(result, size, score=None, extra=None):
    """The viewer's layers (view.py's method_overlays)."""
    mapper, grid = result["mapper"], result["grid"]
    back = mapper.back
    layers = []
    shapes = []
    colours = ["#4e9af1", "#f1a94e", "#5fd08a", "#d05f9e", "#b0a0f0", "#e0d060", "#60d0d0", "#f07070"]
    for r, ring in enumerate(result["rooms"]):
        info = result["info"][r]
        shapes.append({"poly": [back(p) for p in ring], "fill": colours[r % len(colours)], "opacity": 0.35,
                       "stroke": "#ffffff", "width": 1,
                       "tip": "room %d: %d sq yd, %d corners, floor %.0f to %.0f high" % (
                           r, info["area"], len(ring), info["low"], info["high"])})
    layers.append({"name": "Rooms", "on": True, "note": "each room's outline (holes under %.0f yd filled)" % result["settings"]["obstacle"],
                   "shapes": shapes})
    shapes = []
    for a, ea, b, eb in result["doors"]:
        ring = result["rooms"][a]
        p, q = ring[ea], ring[(ea + 1) % len(ring)]
        shapes.append({"line": [back(p), back(q)], "stroke": "#ff3030", "width": 3,
                       "tip": "doorway: room %d edge %d, room %d edge %d" % (a, ea, b, eb)})
    for a, b, x, y in result["lifts"]:
        shapes.append({"dot": back((x, y)), "r": 4, "fill": "#ff3030", "tip": "lift: room %d to room %d" % (a, b)})
    layers.append({"name": "Doorways", "on": True, "note": "where two rooms meet; routes cross rooms only here", "shapes": shapes})
    if extra and extra.get("triangles"):
        shapes = []
        for r, tris in enumerate(extra["triangles"]):
            for t in tris:
                shapes.append({"poly": t, "stroke": "#ffffff", "width": 0.5, "opacity": 0.4})
        layers.append({"name": "Triangles", "on": False, "note": "each room cut into triangles when the place loads (the funnel runs through them)",
                       "shapes": shapes})
    for name, key, colour, note in (
            ("Dropped: steep", "steep", "#a05020", "floor steeper than %.0f degrees (rock faces, ledges)" % result["settings"]["slope"]),
            ("Dropped: ledges", "ledges", "#a0a020", "floor the entrance does not reach once the steep floor and the shave are gone")):
        shapes = []
        for rings in cell_rings(mapper, spans_cells(grid, np.nonzero(result["dropped"][key])[0]), 0.6):
            shapes.append({"rings": rings, "fill": colour, "opacity": 0.6, "stroke": colour, "width": 1})
        layers.append({"name": name, "on": False, "note": note, "shapes": shapes})
    shapes = []
    for rings in cell_rings(mapper, spans_cells(grid, np.nonzero(result["dropped"]["given"])[0]), 0.6):
        shapes.append({"rings": rings, "fill": "#40c0ff", "opacity": 0.6, "stroke": "#40c0ff", "width": 1})
    layers.append({"name": "Given back at necks", "on": False,
                   "note": "floor the shave or a steep patch had cut off, joined back by a thin way", "shapes": shapes})
    shapes = []
    for r, cells in result["fills"].items():
        for rings in cell_rings(mapper, cells, 0.6):
            shapes.append({"rings": rings, "fill": "#909090", "opacity": 0.7, "tip": "obstacle filled in (room %d)" % r})
    for (ax, az), (bx, bz) in result["cuts"]:
        shapes.append({"line": [list(mapper.to_map(ax, az)), list(mapper.to_map(bx, bz))], "stroke": "#909090", "dash": "4 3", "width": 1})
    layers.append({"name": "Obstacles", "on": False,
                   "note": "grey: obstacles filled in (under `obstacle` yd); dashed: where a room round an obstacle was cut in two",
                   "shapes": shapes})
    stats = ["%d rooms, %d doorways, %d corners" % (len(result["rooms"]), len(result["doors"]),
                                                   sum(len(r) for r in result["rooms"])),
             "%d bytes of Lua" % size]
    if score:
        stats.append("bench: walkable %d/%d, reached %d, ratio %.3f (worst %.2f), %.1f bends, clearance %.1f yd" % (
            score["walkable"], score["cases"], score["reached"], score["ratio_mean"] or 0, score["ratio_worst"] or 0,
            score["bends_mean"], score["clearance_mean"]))
    if extra:
        stats += extra.get("stats", [])
    return {"name": "Rooms and doorways", "colour": "#ff9f1a", "stats": stats, "data": router_data(result), "layers": layers}


# ---- Checking -----------------------------------------------------------------

NODE = r"""
const fs = require("fs");
let router = null;
global.NuuRoadViewer = { method: (id, r) => { router = r; } };
require(process.argv[2]);
const input = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const data = input.data;
const yd = (a, b) => Math.hypot((a[0] - b[0]) * data.yards[0], (a[1] - b[1]) * data.yards[1]);
const ctx = { yd, yards: data.yards };
const out = { routes: [], tracked: [], located: [] };
let t0 = process.hrtime.bigint();
router.prepare(data);
out.load_ms = Number(process.hrtime.bigint() - t0) / 1e6;
out.triangles = router.triangles(data);
// A first pass fills the room caches (as a long session would); the second is timed.
for (const pass of [0, 1]) {
  t0 = process.hrtime.bigint();
  out.routes = input.trips.map(([s, t, rooms, pinned]) => router.route(data, s, t, ctx, rooms || undefined, pinned || undefined));
  out[pass ? "ms" : "cold_ms"] = Number(process.hrtime.bigint() - t0) / 1e6;
}
out.located = input.locate.map((p) => router.locate(data, p));
// The tracker along each walk: from the room given, point by point.
t0 = process.hrtime.bigint();
let steps = 0;
for (const [room, path] of input.walks) {
  let r = room >= 0 ? [room] : router.locate(data, path[0]);
  for (let i = 1; i < path.length; i++) { r = router.track(data, r, path[i - 1], path[i]); steps++; }
  out.tracked.push(r);
}
out.track_us = steps ? Number(process.hrtime.bigint() - t0) / 1e3 / steps : 0;
console.log(JSON.stringify(out));
"""


def run_js(data, trips, locate, walks):
    """rooms.js under node: routes for `trips` ([start, target, start
    rooms or None]), candidate rooms for `locate` points, and the room the
    tracker ends in along each of `walks` ([room, [map points]])."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "input.json"), "w") as handle:
            json.dump({"data": data, "trips": trips, "locate": locate, "walks": walks}, handle)
        with open(os.path.join(tmp, "check.js"), "w") as handle:
            handle.write(NODE)
        out = subprocess.run(["node", os.path.join(tmp, "check.js"), os.path.join(HERE, "rooms.js"),
                              os.path.join(tmp, "input.json")], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit("node: " + out.stderr)
    return json.loads(out.stdout)


def room_of_span(result, span, reach=12):
    """The room a span of the whole navmesh is in: its own, or that of the
    nearest kept span through the navmesh's links (a span in the shaved
    band by a wall)."""
    grid, fl, label = result["grid"], result["fl"], result["label"]
    seen, frontier = {span}, [span]
    for _ in range(reach):
        found = [int(label[fl.index[s]]) for s in frontier if fl.index[s] >= 0 and label[fl.index[s]] >= 0]
        if found:
            return collections.Counter(found).most_common(1)[0][0]
        nxt = []
        for s in frontier:
            for o in grid.n[s]:
                if o >= 0 and o not in seen:
                    seen.add(int(o))
                    nxt.append(int(o))
        frontier = nxt
    return -1


def walk_points(path, step_yd, yards):
    """A walk along `path` (map %) as points every `step_yd` yards."""
    out = [path[0]]
    for a, b in zip(path, path[1:]):
        L = math.hypot((b[0] - a[0]) * yards[0], (b[1] - a[1]) * yards[1])
        k = max(1, int(math.ceil(L / step_yd)))
        for j in range(1, k + 1):
            out.append([a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k])
    return out


def summarise(rows):
    """bench.score's summary of rows already checked."""
    ok = [r for r in rows if r.get("ratio") is not None]
    kinds = {}
    for r in rows:
        k = kinds.setdefault(r["kind"], {"n": 0, "walkable": 0, "ratio": []})
        k["n"] += 1
        k["walkable"] += bool(r["walkable"])
        if r.get("ratio") is not None:
            k["ratio"].append(r["ratio"])
    return {"walkable": sum(1 for r in rows if r["walkable"]), "reached": sum(1 for r in rows if r.get("reached")),
            "ratio_mean": sum(r["ratio"] for r in ok) / len(ok) if ok else 0,
            "ratio_worst": max((r["ratio"] for r in ok), default=0),
            "kinds": {k: {"n": v["n"], "walkable": v["walkable"],
                          "ratio_mean": sum(v["ratio"]) / len(v["ratio"]) if v["ratio"] else None} for k, v in kinds.items()}}


def main():
    args = sys.argv[1:]
    region_name = next((a for a in args if a in regions.REGIONS), "venturemine")
    s = {}
    for a in args:
        if "=" in a:
            k, v = a.split("=", 1)
            if k not in SETTINGS:
                raise SystemExit("unknown setting " + k)
            s[k] = float(v)
    result = build(region_name, s)
    source = lua(result)
    size = len(source.encode())
    with open(os.path.join(CACHE, region_name + ".rooms.place.lua"), "w", encoding="ascii") as handle:
        handle.write(source)
    print("%s.rooms.place.lua: %d bytes, %d rooms, %d doorways, %d corners" % (
        region_name, size, len(result["rooms"]), len(result["doors"]), sum(len(r) for r in result["rooms"])),
        file=sys.stderr)
    data = router_data(result)
    score, extra = None, {"stats": []}
    bench_path = os.path.join(CACHE, region_name + ".bench.json")
    if region_name in bench.ENTRANCES and os.path.exists(bench_path):
        cases = bench.load(region_name)[2]["cases"]
        yards = data["yards"]
        start_rooms = [room_of_span(result, c["from"]["span"]) for c in cases]
        target_rooms = [room_of_span(result, c["to"]["span"]) for c in cases]
        trips = [[c["from"]["at"], c["to"]["at"], None] for c in cases]
        tracked_trips = [[c["from"]["at"], c["to"]["at"], [r] if r >= 0 else None] for c, r in zip(cases, start_rooms)]
        walks = [[r, walk_points(c["path"], 0.5, yards)] for c, r in zip(cases, start_rooms)]
        # And with the target's room pinned too, as an author's `near` would.
        pinned_trips = [[a, b, rooms, [r] if r >= 0 else None] for (a, b, rooms), r in zip(tracked_trips, target_rooms)]
        js = run_js(data, trips + tracked_trips + pinned_trips, [c["to"]["at"] for c in cases] + [c["from"]["at"] for c in cases], walks)
        n = len(cases)
        lost, tracked, pinned = js["routes"][:n], js["routes"][n:2 * n], js["routes"][2 * n:]
        extra["triangles"] = js["triangles"]
        by_trip = {(tuple(c["from"]["at"]), tuple(c["to"]["at"])): r for c, r in zip(cases, lost)}
        score = bench.score(region_name, "rooms", lambda a, b: (by_trip.get((tuple(a), tuple(b))) or {}).get("points"), size)
        modes = {}
        for mode, routes in (("tracked", tracked), ("pinned", pinned)):
            rows = []
            for c, r in zip(cases, routes):
                got = (r or {}).get("points")
                row = bench.check(region_name, c, got) if got else {"walkable": False, "reached": False}
                row["kind"] = c["kind"]
                rows.append(row)
            modes[mode] = summarise(rows)
        ambiguous_t = sum(1 for rooms in js["located"][:n] if len(rooms) > 1)
        ambiguous_s = sum(1 for rooms in js["located"][n:] if len(rooms) > 1)
        right_t = sum(1 for got, want in zip(lost, target_rooms) if got and got["rooms"][-1] == want)
        ends = sum(1 for got, want in zip(js["tracked"], target_rooms) if got == [want])
        maybe = sum(1 for got, want in zip(js["tracked"], target_rooms) if want in got and len(got) > 1)
        per = js["ms"] / (3 * n)
        lines = [
            "routes: %.3f ms each in node (%.2f ms the first time, filling room caches); load %.1f ms" % (
                per, js["cold_ms"] / (3 * n), js["load_ms"]),
            "tracker: %.2f us a step; along the %d true walks (0.5 yd steps) ends sure of the target's room on %d, "
            "unsure but holding it on %d" % (js["track_us"], n, ends, maybe),
            "ambiguous: %d targets and %d starts in more than one room; nearest-room choice right for %d of %d targets" % (
                ambiguous_t, ambiguous_s, right_t, n),
        ]
        for mode, text in (("tracked", "start's room known (the tracker)"), ("pinned", "and the target's room pinned (near)")):
            m = modes[mode]
            lines.append("%s: walkable %d/%d, reached %d, ratio %.3f (worst %.2f); %s" % (
                text, m["walkable"], n, m["reached"], m["ratio_mean"], m["ratio_worst"],
                ", ".join("%s %d/%d %.3f" % (k, v["walkable"], v["n"], v["ratio_mean"] or 0) for k, v in m["kinds"].items())))
        for line in lines:
            print(line, file=sys.stderr)
        extra["stats"] += lines
        wrong = ["%s %s not %d" % (c["id"], got, want) for c, got, want in zip(cases, js["tracked"], target_rooms) if want not in got]
        if wrong:
            print("tracker lost on: %s" % ", ".join(wrong), file=sys.stderr)
    else:
        js = run_js(data, [], [], [])
        extra["triangles"] = js["triangles"]
    with open(os.path.join(CACHE, region_name + ".method.rooms.json"), "w") as handle:
        json.dump(overlay(result, size, score, extra), handle)


if __name__ == "__main__":
    main()
