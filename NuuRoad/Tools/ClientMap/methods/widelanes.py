#!/usr/bin/env python3
"""Wide lanes: a place as today's points and connections, each point with a
radius. A lane is a connection with a width: the convex hull of the discs at
its two ends (a capsule that may taper), and the build makes sure every lane
lies on floor of one level. The game routes along the lanes and pulls the
line taut inside them.

    python3 Tools/ClientMap/methods/widelanes.py venturemine [band=6] [tol=4] ...

Starts from the floor methods/rooms.py filters (steep floor, ledges and a
yard along every wall and drop gone, necks given back), then:

  * the band: floor within `band` yards of the filtered floor's edge. A
    passage narrower than twice that is all band; in a wider room the band
    is a ring along its walls round the open floor in the middle, where
    mobs stand. Open patches under `open` square yards, or no more than
    `depth` yards deeper than the band, count as band;
  * the band is thinned to its centre lines (skeleton.py's thinning and
    tracing): the middle of every corridor, and a line a few yards off the
    walls round every open room. Bumps in a wall shorter than `spur` times
    the clearance go, junctions closer than `merge` times it are one, and a
    loop round an obstacle enclosing less than `pillar` square yards loses
    its narrower side; the tip of a dead end narrower than `trim` yards
    gets no lanes;
  * each line is cut into lanes: from each point, the farthest point along
    the line whose hull with it is on floor and holds the disc of every
    point of the line in between, give or take `tol` yards (so the lanes
    cover what the line's discs do, and the joints fall where the floor
    is wide). A point's radius is its distance to the filtered floor's edge
    (at most `rmax`), cut to 70% or 45% where that makes a lane much longer;
  * the region's lifts and ways in join the nearest point;
  * crossings: between the ends of the lines (junctions, dead ends, ways
    in) that are more than `stretch` times their straight distance apart
    along the lanes, the straight lane between them where it is on floor,
    the biggest saving first;
  * a point between just two lanes goes when the lane straight past it is
    on floor and still holds its disc (within `tol`), and every radius
    grows back as far as its lanes allow.

On floor means: every navmesh column whose centre lies in the hull has a
span of the filtered floor, all reached from the first end's span through
the spans' own links without leaving the hull, none twice, and the second
end's span among them. So a lane never spans two floors stacked over each
other, and a straight line anywhere inside it can be walked. What ships is
checked again as rounded (map % to 3 places, radii down to a tenth of a
yard), both ways, a tenth of a yard off both radii of a lane at a time
until it passes.

methods/widelanes.js is the router, the algorithm the addon would run on
map positions only (see its header).

Writes .cache/<region>.method.widelanes.json (the viewer's layers and the
router's data) and .cache/<region>.widelanes.place.lua (the place as a
guide would carry it). Where the region is a benchmark it runs the router
under node on bench.py's trips and scores them as the viewer asks (map
position only; .cache/<region>.score.widelanes.json), and again with the
start's lane and the target's lane known (the lanes over each on its own
floor, as the tracker and an author's `near` would give them;
.score.widelanes.known.json), and runs the tracker along every true walk.
"""

import collections
import copy
import heapq
import json
import math
import os
import subprocess
import sys
import tempfile
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import bench  # noqa: E402
import maps  # noqa: E402
import regions  # noqa: E402
import skeleton as sk  # noqa: E402
from casc import CACHE  # noqa: E402


def _method(name):
    """methods/<name>.py as a module (Tools/ClientMap has a rooms.py too)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("method_" + name, os.path.join(HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rooms = _method("rooms")

SETTINGS = {
    "band": 6.0,      # yards of floor clearance: deeper floor is open, lanes keep to its edge
    "open": 60.0,     # square yards: a smaller open patch counts as band
    "depth": 1.5,     # yards: ... and so does one no deeper than this past the band
    "rmax": 8.0,      # yards: the widest radius a point gets
    "rmin": 0.3,      # yards: the narrowest
    "spur": 1.5,      # a dead end shorter than this times its clearance is a bump in the wall
    "merge": 1.0,     # junctions closer than this times their clearance are one
    "pillar": 40.0,   # square yards: a loop enclosing less runs round an obstacle
    "stretch": 1.4,   # a crossing where the lanes are longer than this times the straight line
    "cross": 6.0,     # yards: the shortest crossing considered
    "reach": 80.0,    # yards: the longest
    "shave": 1.0,     # yards kept off every wall and drop (rooms.py's floor filter)
    "trim": 1.0,      # yards: the narrow tip of a dead end gets no lanes
    "tol": 4.0,       # yards a disc of the centre line may stand out of its lane (-1: any)
}
FLOOR = dict(rooms.SETTINGS)   # the floor filter, as rooms.py has it
DX = (-1, 0, 1, 0)             # Recast's directions as (dx, dz)
DZ = (0, 1, 0, -1)
SHRINK = (1.0, 0.7, 0.45)      # radius factors tried when a lane will not reach far


def say(*args):
    print(*args, file=sys.stderr)


# ---- Hulls ----------------------------------------------------------------------

def hull_gap(px, py, ax, ay, ra, bx, by, rb):
    """How far (px, py) lies outside the hull of the discs (a, ra) and (b,
    rb); negative inside. The hull is every disc between the two, centre and
    radius moving together, so this is the least over t of the distance to
    disc t less its radius: a convex function of t, whose least value has a
    closed form. Works on arrays."""
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    if length <= abs(rb - ra) + 1e-9:
        # One disc holds the other.
        if ra >= rb:
            return np.hypot(px - ax, py - ay) - ra
        return np.hypot(px - bx, py - by) - rb
    ux, uy = dx / length, dy / length
    along = (px - ax) * ux + (py - ay) * uy
    across = np.abs((px - ax) * uy - (py - ay) * ux)
    s = (ra - rb) / length
    w = s * across / math.sqrt(1 - s * s)
    t = np.clip((along - w) / length, 0.0, 1.0)
    return np.hypot(along - t * length, across) - (ra + t * (rb - ra))


def hull_polygon(ax, ay, ra, bx, by, rb, sides=20):
    """The hull as a polygon (for drawing): the convex hull of both circles."""
    pts = []
    for cx, cy, r in ((ax, ay, ra), (bx, by, rb)):
        for k in range(sides):
            a = 2 * math.pi * k / sides
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


# ---- The floor ------------------------------------------------------------------

class Floor:
    """The filtered floor (rooms.Floor) with what the lanes need: each span's
    yards to the floor's edge (`r`), its centre in cell units (`u`, `v`),
    and a picture of which columns have floor at all."""

    def __init__(self, grid, fl):
        self.grid, self.fl = grid, fl
        self.cell = grid.cell
        self.D = rooms.distance(fl)
        self.u = fl.x + 0.5
        self.v = fl.z + 0.5
        self.x0, self.z0 = int(fl.x.min()), int(fl.z.min())
        self.occ = np.zeros((int(fl.z.max()) - self.z0 + 1, int(fl.x.max()) - self.x0 + 1), bool)
        self.occ[fl.z - self.z0, fl.x - self.x0] = True
        # Yards from each span's centre to the floor's edge: the distance
        # field through the links counts 3 for a diagonal step (2.83 would
        # be exact), so runs long by up to 6%; the straight distance to the
        # nearest column with no floor at all is exact but blind to a floor
        # stacked over the edge. The lesser of the two, less a whisker.
        from scipy import ndimage
        edt = ndimage.distance_transform_edt(np.pad(self.occ, 1))[1:-1, 1:-1]
        exact = (edt[fl.z - self.z0, fl.x - self.x0] - 0.5) * grid.cell
        self.r = np.maximum(0.0, np.minimum(exact, (self.D / 2.0 + 0.5) * grid.cell) - 0.05)
        self.checks = self.slow = 0
        self.sheets()

    def sheets(self):
        """Cuts the floor into sheets, each at most one span a column, grown
        through the links from the widest floor first, so that most hulls lie
        on one sheet and can be checked as pictures: `sheet` (each span's),
        `img` (each sheet's span in every column, -1 none), and `east`,
        `south` (whether a column's span is linked to the next one's in the
        sheet, across and down)."""
        fl = self.fl
        n = len(fl)
        self.sheet = np.full(n, -1, np.int32)
        self.img, self.east, self.south = [], [], []
        shape = self.occ.shape
        for seed in np.argsort(-self.D, kind="stable"):
            if self.sheet[seed] >= 0:
                continue
            k = len(self.img)
            img = np.full(shape, -1, np.int64)
            queue = collections.deque([int(seed)])
            self.sheet[seed] = k
            img[fl.z[seed] - self.z0, fl.x[seed] - self.x0] = seed
            while queue:
                s = queue.popleft()
                for o in fl.nb[s]:
                    if o < 0 or self.sheet[o] >= 0:
                        continue
                    at = (fl.z[o] - self.z0, fl.x[o] - self.x0)
                    if img[at] >= 0:
                        continue
                    img[at] = o
                    self.sheet[o] = k
                    queue.append(int(o))
            east = np.zeros(shape, bool)
            south = np.zeros(shape, bool)
            here = img[:, :-1]
            ok = (here >= 0) & (img[:, 1:] >= 0)
            east[:, :-1][ok] = fl.nb[here[ok], 2] == img[:, 1:][ok]
            here = img[:-1, :]
            ok = (here >= 0) & (img[1:, :] >= 0)
            south[:-1, :][ok] = fl.nb[here[ok], 1] == img[1:, :][ok]
            self.img.append(img)
            self.east.append(east)
            self.south.append(south)
        say("floor sheets: %d (%s spans)" % (len(self.img), ", ".join(
            str(c) for c in np.bincount(self.sheet)[:6])))

    def near(self, p, radius):
        """The spans within `radius` yards of span p's centre that its own
        floor reaches without leaving that circle."""
        fl = self.fl
        R = radius / self.cell
        seen = {int(p)}
        frontier = np.array([p], np.int64)
        px, pz = fl.x[p], fl.z[p]
        out = [frontier]
        while len(frontier):
            nb = fl.nb[frontier].reshape(-1)
            nb = np.unique(nb[nb >= 0])
            nb = nb[np.hypot(fl.x[nb] - px, fl.z[nb] - pz) <= R]
            nb = np.array([o for o in nb.tolist() if o not in seen], np.int64)
            seen.update(nb.tolist())
            out.append(nb)
            frontier = nb
        return np.concatenate(out)

    def covered(self, pa, ra, pb, rb, sa, sb):
        """The spans under the hull of (pa, ra) and (pb, rb) (cell units and
        yards) when it lies on one floor reached from span `sa` and holding
        span `sb` (numbers in the floor); None when it does not."""
        self.checks += 1
        fl, cell = self.fl, self.cell
        ax, ay = pa
        bx, by = pb
        ca, cb = ra / cell, rb / cell
        lo_x = int(math.floor(min(ax - ca, bx - cb)))
        hi_x = int(math.ceil(max(ax + ca, bx + cb)))
        lo_z = int(math.floor(min(ay - ca, by - cb)))
        hi_z = int(math.ceil(max(ay + ca, by + cb)))
        xs = np.arange(lo_x, hi_x + 1)
        zs = np.arange(lo_z, hi_z + 1)
        X, Z = np.meshgrid(xs, zs)
        inside = hull_gap(X + 0.5, Z + 0.5, ax, ay, ca, bx, by, cb) <= 0
        ox, oz = X[inside] - self.x0, Z[inside] - self.z0
        if ((ox < 0) | (oz < 0) | (ox >= self.occ.shape[1]) | (oz >= self.occ.shape[0])).any():
            return None
        # The box may stand past the floor's picture where the hull does not.
        cols = (xs >= self.x0) & (xs < self.x0 + self.occ.shape[1])
        rows = (zs >= self.z0) & (zs < self.z0 + self.occ.shape[0])
        if not (cols.all() and rows.all()):
            X, Z, inside = X[rows][:, cols], Z[rows][:, cols], inside[rows][:, cols]
            lo_x, lo_z = int(xs[cols][0]), int(zs[rows][0])
        if not self.occ[oz, ox].all():
            return None
        # Most hulls lie on the sheet of their first end: a picture check.
        k = self.sheet[sa]
        z0, x0 = lo_z - self.z0, lo_x - self.x0
        img = self.img[k][z0:z0 + inside.shape[0], x0:x0 + inside.shape[1]]
        under = img[inside]
        if (under >= 0).all():
            pairs = inside[:, :-1] & inside[:, 1:]
            if not self.east[k][z0:z0 + inside.shape[0], x0:x0 + inside.shape[1] - 1][pairs].all():
                return None
            pairs = inside[:-1, :] & inside[1:, :]
            if not self.south[k][z0:z0 + inside.shape[0] - 1, x0:x0 + inside.shape[1]][pairs].all():
                return None
            if img[fl.z[sb] - lo_z, fl.x[sb] - lo_x] == sb:
                return under
        # Across sheets: walk it.
        self.slow += 1
        h, w = inside.shape
        seen = np.full(inside.shape, -1, np.int64)
        for s in (sa, sb):
            i, j = fl.z[s] - lo_z, fl.x[s] - lo_x
            if not (0 <= i < h and 0 <= j < w and inside[i, j]):
                return None
        seen[fl.z[sa] - lo_z, fl.x[sa] - lo_x] = sa
        frontier = np.array([sa], np.int64)
        while len(frontier):
            found = []
            for d in range(4):
                cx = fl.x[frontier] + DX[d] - lo_x
                cz = fl.z[frontier] + DZ[d] - lo_z
                ok = (cx >= 0) & (cx < w) & (cz >= 0) & (cz < h)
                ok[ok] = inside[cz[ok], cx[ok]]
                nb = fl.nb[frontier, d]
                if (ok & (nb < 0)).any():
                    return None
                cand, ccx, ccz = nb[ok], cx[ok], cz[ok]
                prev = seen[ccz, ccx]
                if ((prev >= 0) & (prev != cand)).any():
                    return None
                fresh = prev < 0
                seen[ccz[fresh], ccx[fresh]] = cand[fresh]
                if (seen[ccz[fresh], ccx[fresh]] != cand[fresh]).any():
                    return None
                found.append(cand[fresh])
            frontier = np.unique(np.concatenate(found)) if found else np.zeros(0, np.int64)
        if (seen[inside] < 0).any():
            return None
        if seen[fl.z[sb] - lo_z, fl.x[sb] - lo_x] != sb:
            return None
        return seen[inside]


# ---- Centre lines of the band ---------------------------------------------------

def band_mask(F, s):
    """The band (a mask over the floor) and the open floor left out of it."""
    fl = F.fl
    deep = F.r > s["band"]
    open_ = np.zeros(len(fl), bool)
    if deep.any():
        sub = fl.sub(deep)
        pieces = rooms.components(sub)
        where = np.nonzero(deep)[0]
        area = np.bincount(pieces) * F.cell ** 2
        most = np.zeros(pieces.max() + 1)
        np.maximum.at(most, pieces, F.r[where])
        keep = (area >= s["open"]) & (most >= s["band"] + s["depth"])
        open_[where[keep[pieces]]] = True
    return ~open_, open_


def centre_lines(F, band, s):
    """skeleton.py's thinning and tracing of the band: a Graph over the
    whole navmesh's spans, with its bumps pruned and close junctions joined."""
    grid, fl = F.grid, F.fl
    mask = np.zeros(len(grid), bool)
    mask[fl.span[band]] = True
    thin_grid = copy.copy(grid)
    thin_grid.dist = sk.distance_field(grid, mask)
    alive, ring = sk.thin(thin_grid, mask)
    graph = sk.trace(thin_grid, alive, ring)
    # Clearance for pruning is the floor's, not the band's.
    floor_grid = copy.copy(grid)
    whole = np.zeros(len(grid), np.int32)
    whole[fl.span] = F.D
    floor_grid.dist = whole
    sk.prune(floor_grid, graph, s["spur"])
    sk.merge_junctions(floor_grid, graph, s["merge"])
    sk.prune(floor_grid, graph, s["spur"])
    return graph, floor_grid, alive


def loop_area(points):
    total = 0.0
    for i in range(len(points)):
        (ax, ay), (bx, by) = points[i - 1], points[i]
        total += ax * by - bx * ay
    return abs(total) / 2


def drop_pillar_loops(F, graph, floor_grid, s):
    """Takes the narrower side off every loop that encloses less than
    `pillar` square yards (a loop round an obstacle). Returns the paths
    dropped (whole navmesh spans)."""
    dropped = []
    cell2 = F.cell ** 2

    lengths = {}

    def length(path):
        key = (path[0], path[-1], len(path))
        if key not in lengths:
            xs = floor_grid.x[path].astype(float)
            zs = floor_grid.z[path].astype(float)
            lengths[key] = float(np.hypot(np.diff(xs), np.diff(zs)).sum() * floor_grid.cell)
        return lengths[key]

    def mean_clear(path):
        return float(np.mean(floor_grid.dist[path]))

    while True:
        adj = collections.defaultdict(list)
        for k, e in graph.edges.items():
            adj[e["a"]].append((k, e["b"]))
            adj[e["b"]].append((k, e["a"]))
        small = []
        for k, e in graph.edges.items():
            if e["a"] == e["b"]:
                pts = [(floor_grid.x[p], floor_grid.z[p]) for p in e["path"]]
                area = loop_area(pts) * cell2
                if area < s["pillar"]:
                    small.append((area, [k]))
                continue
            # The shortest other way between its ends.
            dist, prev, heap = {e["a"]: 0.0}, {}, [(0.0, e["a"])]
            while heap:
                d, n = heapq.heappop(heap)
                if n == e["b"]:
                    break
                if d > dist.get(n, 1e18) or d > 200:
                    continue
                for k2, m in adj[n]:
                    if k2 == k:
                        continue
                    nd = d + length(graph.edges[k2]["path"])
                    if nd < dist.get(m, 1e18):
                        dist[m], prev[m] = nd, (n, k2)
                        heapq.heappush(heap, (nd, m))
            if e["b"] not in prev:
                continue
            keys, n = [], e["b"]
            while n != e["a"]:
                n, k2 = prev[n]
                keys.append(k2)
            # The loop: this edge a to b, then back along the other way.
            pts = [(floor_grid.x[p], floor_grid.z[p]) for p in e["path"]]
            n = e["b"]
            for k2 in keys[::-1]:
                e2 = graph.edges[k2]
                p2 = e2["path"] if e2["a"] == n else e2["path"][::-1]
                pts += [(floor_grid.x[p], floor_grid.z[p]) for p in p2]
                n = e2["b"] if e2["a"] == n else e2["a"]
            area = loop_area(pts) * cell2
            if area < s["pillar"]:
                small.append((area, [k] + keys))
        if not small:
            return dropped
        small.sort(key=lambda t: t[0])
        _, keys = small[0]
        k = min(keys, key=lambda k2: mean_clear(graph.edges[k2]["path"]))
        dropped.append(graph.edges[k]["path"])
        del graph.edges[k]
        sk.prune(floor_grid, graph, s["spur"])


# ---- Lanes ----------------------------------------------------------------------

class Net:
    """The points (floor numbers), their radii and the lanes between them."""

    def __init__(self, F, s):
        self.F, self.s = F, s
        self.rad = {}
        self.lanes = set()        # (a, b) with a < b
        self.cover = {}           # lane -> spans under it
        self.kind = {}            # lane -> "line" or "crossing"
        self.forced = 0           # lanes fitted off the floor (none should be)

    def full(self, p):
        # The distance field counts 3 for a diagonal step (2.83 would be
        # exact), so it runs a little long: the disc keeps inside it.
        return max(self.s["rmin"], min(float(self.F.r[p]), self.s["rmax"]))

    def pos(self, p):
        return (float(self.F.u[p]), float(self.F.v[p]))

    def check(self, a, ra, b, rb):
        return self.F.covered(self.pos(a), ra, self.pos(b), rb, a, b)

    def add(self, a, b, spans, kind="line"):
        key = (min(a, b), max(a, b))
        self.lanes.add(key)
        self.cover[key] = spans
        self.kind[key] = kind

    def yd(self, a, b):
        (ax, ay), (bx, by) = self.pos(a), self.pos(b)
        return math.hypot(ax - bx, ay - by) * self.F.cell

    def fit(self, path, tol=-1.0):
        """Cuts one centre line (floor numbers, end to end) into lanes; with
        `tol` of 0 or more, a lane also holds the disc of every point of the
        line it passes, give or take `tol` yards, so the lanes cover what
        the line's discs do."""
        rmin = self.s["rmin"]
        for end in (path[0], path[-1]):
            self.rad.setdefault(end, self.full(end))
        i = 0
        while i < len(path) - 1:
            a = path[i]
            options = []
            for f in SHRINK:
                ra = max(rmin, self.rad[a] * f)

                def ok(j):
                    b = path[j]
                    rb = max(rmin, (self.rad[b] if b in self.rad else self.full(b)) * f)
                    if tol >= 0 and j > i + 1:
                        # Every disc between stays (nearly) inside the lane.
                        mid = np.array(path[i + 1:j])
                        (ax, ay), (bx, by) = self.pos(a), self.pos(b)
                        cell = self.F.cell
                        out = hull_gap(self.F.u[mid], self.F.v[mid], ax, ay, ra / cell, bx, by, rb / cell) * cell
                        disc = np.maximum(self.s["rmin"], np.minimum(self.F.r[mid], self.s["rmax"]))
                        if (out + disc > tol).any():
                            return None
                    return self.check(a, ra, b, rb)
                j_best, got = None, None
                last = len(path) - 1
                got = ok(last)
                if got is not None:
                    j_best = last
                else:
                    lo, hi = i, last
                    while hi - lo > 1:
                        mid = (lo + hi) // 2
                        found = ok(mid)
                        if found is not None:
                            lo, got = mid, found
                        else:
                            hi = mid
                    if lo > i:
                        j_best = lo
                if j_best is not None:
                    options.append((self.yd(a, path[j_best]) * f ** 0.5, f, j_best, got))
                    if j_best == last:
                        break
            if not options:
                # Not even the next span: step on with the narrowest lane.
                self.forced += 1
                j = i + 1
                b = path[j]
                self.rad[a] = rmin
                self.rad.setdefault(b, rmin)
                got = self.check(a, rmin, b, min(self.rad[b], rmin))
                self.rad[b] = min(self.rad[b], rmin)
                self.add(a, b, got if got is not None else np.array([a, b]))
                i = j
                continue
            _, f, j, got = max(options, key=lambda o: o[0])
            b = path[j]
            self.rad[a] = max(rmin, self.rad[a] * f)
            self.rad[b] = max(rmin, (self.rad[b] if b in self.rad else self.full(b)) * f)
            self.add(a, b, got)
            i = j

    def points(self):
        return sorted({p for lane in self.lanes for p in lane})

    def neighbours(self):
        adj = collections.defaultdict(set)
        for a, b in self.lanes:
            adj[a].add(b)
            adj[b].add(a)
        return adj

    def crossings(self, keep=()):
        """Adds straight lanes between the ends of the lines (points with
        other than two lanes, and those in `keep`) where the lanes are more
        than `stretch` times the straight line, the biggest saving first."""
        from scipy.sparse import coo_matrix
        from scipy.sparse.csgraph import dijkstra
        from scipy.spatial import cKDTree
        s = self.s
        pts = self.points()
        index = {p: i for i, p in enumerate(pts)}
        n = len(pts)
        xy = np.array([self.pos(p) for p in pts]) * self.F.cell
        rows = [index[a] for a, b in self.lanes] + [index[b] for a, b in self.lanes]
        cols = [index[b] for a, b in self.lanes] + [index[a] for a, b in self.lanes]
        w = [self.yd(a, b) for a, b in self.lanes] * 2
        G = dijkstra(coo_matrix((w, (rows, cols)), shape=(n, n)).tocsr(), directed=False)
        tree = cKDTree(xy)
        pairs = tree.query_pairs(s["reach"], output_type="ndarray")
        if not len(pairs):
            return 0
        # Only between the ends of the lines (junctions, dead ends, ways in):
        # a crossing is a way from one passage to another, not a short cut
        # along one room's wall.
        adj = self.neighbours()
        terminal = np.array([len(adj[p]) != 2 or p in keep for p in pts])
        pairs = pairs[terminal[pairs[:, 0]] & terminal[pairs[:, 1]]]
        if not len(pairs):
            return 0
        d = np.hypot(*(xy[pairs[:, 0]] - xy[pairs[:, 1]]).T)
        g = G[pairs[:, 0], pairs[:, 1]]
        want = (d >= s["cross"]) & (g > s["stretch"] * d)
        order = np.argsort(-(g - d)[want])
        added = 0
        for (i, j), dd in zip(pairs[want][order], d[want][order]):
            if G[i, j] <= s["stretch"] * dd:
                continue
            a, b = pts[i], pts[j]
            if (min(a, b), max(a, b)) in self.lanes:
                continue
            got = None
            for f in SHRINK:
                ra, rb = max(s["rmin"], self.rad[a] * f), max(s["rmin"], self.rad[b] * f)
                got = self.check(a, ra, b, rb)
                if got is not None:
                    break
            if got is None:
                continue
            self.rad[a], self.rad[b] = ra, rb
            self.add(a, b, got, "crossing")
            added += 1
            G = np.minimum(G, np.minimum(G[:, [i]] + dd + G[[j], :], G[:, [j]] + dd + G[[i], :]))
        return added

    def straighten(self, keep=()):
        """Drops a point between just two lanes when the lane straight past
        it is on floor."""
        dropped = 0
        changed = True
        while changed:
            changed = False
            adj = self.neighbours()
            for p in sorted(adj, key=lambda q: self.rad[q]):
                if p in keep or len(adj[p]) != 2:
                    continue
                a, b = sorted(adj[p])
                if (min(a, b), max(a, b)) in self.lanes or a == b:
                    continue
                if self.s["tol"] >= 0:
                    # Only when the straight lane still holds p's disc.
                    (ax, ay), (bx, by), (px, py) = self.pos(a), self.pos(b), self.pos(p)
                    cell = self.F.cell
                    out = float(hull_gap(np.array(px), np.array(py), ax, ay, self.rad[a] / cell, bx, by, self.rad[b] / cell)) * cell
                    if out + self.rad[p] > self.s["tol"]:
                        continue
                got = self.check(a, self.rad[a], b, self.rad[b])
                if got is None:
                    continue
                kinds = {self.kind[(min(a, p), max(a, p))], self.kind[(min(b, p), max(b, p))]}
                for q in (a, b):
                    key = (min(p, q), max(p, q))
                    self.lanes.discard(key)
                    del self.cover[key]
                    del self.kind[key]
                self.add(a, b, got, "crossing" if kinds == {"crossing"} else "line")
                dropped += 1
                changed = True
                break
        return dropped

    def regrow(self):
        """Every radius as large as its lanes allow (up to its full)."""
        adj = self.neighbours()
        for p in sorted(adj, key=lambda q: -self.full(q)):
            lo, hi = self.rad[p], self.full(p)
            for _ in range(4):
                if hi - lo < 0.1:
                    break
                mid = hi if _ == 0 else (lo + hi) / 2
                ok = {}
                for q in adj[p]:
                    got = self.check(p, mid, q, self.rad[q])
                    if got is None:
                        break
                    ok[q] = got
                if len(ok) == len(adj[p]):
                    lo = mid
                    for q, got in ok.items():
                        self.cover[(min(p, q), max(p, q))] = got
                    if mid == hi:
                        break
                else:
                    hi = mid
            self.rad[p] = lo


def build(region_name, s=None):
    s = dict(SETTINGS, **(s or {}))
    region = regions.REGIONS[region_name]
    t0 = time.time()
    grid, fl, dropped, lifts = rooms.walkable_floor(region_name, dict(FLOOR, shave=s["shave"]))
    F = Floor(grid, fl)
    say("floor: %d square yards (%.1f s)" % (len(fl) * grid.cell ** 2, time.time() - t0))
    band, open_ = band_mask(F, s)
    say("band: %d square yards, %d open" % (band.sum() * grid.cell ** 2, open_.sum() * grid.cell ** 2))
    graph, floor_grid, alive = centre_lines(F, band, s)
    say("centre lines: %d nodes, %d edges (%.1f s)" % (len(graph.nodes), len(graph.edges), time.time() - t0))
    pillars = drop_pillar_loops(F, graph, floor_grid, s)
    say("loops round obstacles: %d sides dropped (%.1f s)" % (len(pillars), time.time() - t0))
    raw = [[int(fl.index[p]) for p in e["path"]] for e in graph.edges.values()]
    net = Net(F, s)
    degree = collections.Counter()
    for e in graph.edges.values():
        degree[e["a"]] += 1
        degree[e["b"]] += 1
    trimmed = 0
    for key, e in graph.edges.items():
        path = [int(fl.index[p]) for p in e["path"]]
        a, b = int(fl.index[graph.nodes[e["a"]]["span"]]), int(fl.index[graph.nodes[e["b"]]["span"]])
        if path[0] != a:
            path = [a] + path
        if path[-1] != b:
            path = path + [b]
        # A dead end narrows to nothing where the centre line meets the
        # wall: its tip, narrower than `trim`, gets no lanes.
        if degree[e["b"]] == 1 and e["a"] != e["b"]:
            while len(path) > 2 and F.r[path[-1]] < s["trim"]:
                path.pop()
                trimmed += 1
        if degree[e["a"]] == 1 and e["a"] != e["b"]:
            while len(path) > 2 and F.r[path[0]] < s["trim"]:
                path.pop(0)
                trimmed += 1
        a, b = path[0], path[-1]
        # A loop with no junction: split it in the middle.
        if a == b:
            half = len(path) // 2
            net.fit(path[:half + 1], s["tol"])
            net.fit(path[half:], s["tol"])
        else:
            net.fit(path, s["tol"])
    say("fitted: %d points, %d lanes, %d forced off the floor (%d checks, %d walked, %.1f s)" % (
        len(net.points()), len(net.lanes), net.forced, F.checks, F.slow, time.time() - t0))
    specials, entrances = ends(net, region, grid, fl, lifts)
    keep = set(entrances) | {p for _, a, b in specials for p in (a, b)}
    added = net.crossings(keep)
    say("crossings: %d (%d checks, %.1f s)" % (added, F.checks, time.time() - t0))
    gone = net.straighten(keep)
    net.regrow()
    say("straightened: %d points gone; %d points, %d lanes (%d checks, %.1f s)" % (
        gone, len(net.points()), len(net.lanes), F.checks, time.time() - t0))
    return {"region": region_name, "map": region["map"], "name": region.get("title") or regions.name(region),
            "settings": s, "grid": grid, "fl": fl, "F": F, "net": net, "band": band, "open": open_,
            "raw": raw, "pillars": [[int(fl.index[p]) for p in path] for path in pillars], "dropped": dropped,
            "lifts": specials, "entrances": entrances, "skeleton": alive}


def ends(net, region, grid, fl, lifts):
    """Lifts and ways in: each end joins the nearest point it reaches."""
    specials = []
    for at, top, bottom in lifts:
        found = []
        for end in (top, bottom):
            joined = join_point(net, end)
            if joined is not None:
                found.append(joined)
        if len(found) == 2 and found[0] != found[1]:
            # A ride, not a lane on the floor: shipped as a connection like
            # any other (its two ends stand over each other).
            specials.append(("lift", found[0], found[1]))
            net.add(found[0], found[1], np.array(found), "lift")
    entrances = []
    for at in region.get("exits", []):
        x, y = regions.to_world(region["map"], *at)
        span = bench.nearest_span(grid, np.isin(np.arange(len(grid)), fl.span), x, y, reach=15.0)
        if span is not None:
            p = join_point(net, int(fl.index[span]))
            if p is not None:
                entrances.append(p)
    return specials, entrances


def join_point(net, span):
    """The point a span of the floor joins: itself if it is one, else it
    becomes a point with a lane to the nearest point it reaches."""
    if span < 0:
        return None
    pts = net.points()
    if span in pts:
        return span
    xy = np.array([net.pos(p) for p in pts])
    here = np.array(net.pos(span))
    order = np.argsort(np.hypot(*(xy - here).T))
    for k in order[:12]:
        p = pts[k]
        r = net.full(span)
        for f in SHRINK:
            got = net.check(span, max(net.s["rmin"], r * f), p, net.rad[p])
            if got is not None:
                net.rad[span] = max(net.s["rmin"], r * f)
                net.add(span, p, got)
                return span
    return None


# ---- What ships -----------------------------------------------------------------

def shipped(result):
    """The points (map %, 3 places; radius in yards, 1 place, rounded down)
    and lanes as the guide carries them, checked again as rounded: a lane
    the rounding pushed off the floor loses a tenth of a yard at both ends
    until it is back on."""
    F, net, grid = result["F"], result["net"], result["grid"]
    region = regions.REGIONS[result["region"]]
    mapper = rooms.Mapper(grid, region)
    frame = maps.get(region["map"])
    pts = net.points()
    index = {p: i for i, p in enumerate(pts)}
    at, rad = [], []
    for p in pts:
        mx, my = mapper.to_map(F.u[p], F.v[p])
        at.append((round(mx, 3), round(my, 3)))
        rad.append(math.floor(net.rad[p] * 10) / 10)

    def cells(m):
        # map % back to cell units (Mapper.to_map the other way).
        wy = frame["left"] + m[0] / 100 * (frame["right"] - frame["left"])
        wx = frame["top"] + m[1] / 100 * (frame["bottom"] - frame["top"])
        return ((wx - grid.bmin[0]) / grid.cell, (-wy - grid.bmin[2]) / grid.cell)
    lanes = sorted((index[a], index[b]) for a, b in net.lanes)
    lifts = {(min(index[a], index[b]), max(index[a], index[b])) for _, a, b in result["lifts"]}
    fixed = 0

    def on_floor(i, j):
        # Both ways: the check walks from the first end.
        return (F.covered(cells(at[i]), rad[i], cells(at[j]), rad[j], pts[i], pts[j]) is not None and
                F.covered(cells(at[j]), rad[j], cells(at[i]), rad[i], pts[j], pts[i]) is not None)
    for _ in range(30):
        bad = 0
        for i, j in lanes:
            if (i, j) not in lifts and not on_floor(i, j):
                rad[i] = max(0.1, round(rad[i] - 0.1, 1))
                rad[j] = max(0.1, round(rad[j] - 0.1, 1))
                bad += 1
        fixed += bad
        if not bad:
            break
    off = [(i, j) for i, j in lanes if (i, j) not in lifts and not on_floor(i, j)]
    if fixed or off:
        say("rounding: %d lane fixes; %d lanes the check cannot pass at any width: %s" % (
            fixed, len(off), ", ".join("%d-%d" % (i + 1, j + 1) for i, j in off)))
    kinds = [None] * len(pts)
    for p in result["entrances"]:
        kinds[index[p]] = "entrance"
    return {"pts": pts, "at": at, "r": rad, "lanes": lanes, "kinds": kinds, "lifts": lifts,
            "kind": [net.kind[(min(pts[i], pts[j]), max(pts[i], pts[j]))] for i, j in lanes]}


def router_data(result, ship):
    b = maps.get(result["map"])
    return {"yards": [abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100],
            "points": [[x, y, r] for (x, y), r in zip(ship["at"], ship["r"])],
            "lanes": [list(l) for l in ship["lanes"]]}


def lua(result, ship):
    """The place as a guide would carry it: today's schema (a guide's
    `places`, TRAVEL.md) with a radius `r` in yards on every point. A place
    without `r` on a point falls back to the place's `width`."""
    out = ["-- Tools/ClientMap/methods/widelanes.py %s: %d points, %d lanes" % (
        result["region"], len(ship["pts"]), len(ship["lanes"])),
        "{ place = %s, name = %s, width = 4," % (json.dumps(result["region"]), json.dumps(result["name"])),
        "  points = {"]
    for (x, y), r, kind in zip(ship["at"], ship["r"], ship["kinds"]):
        extra = ', kind = "%s"' % kind if kind else ""
        out.append("    { at = { %s, %s }, r = %s%s }," % (fmt(x), fmt(y), fmt(r), extra))
    out.append("  },")
    out.append("  connections = {")
    rows = ["{ %d, %d }," % (a + 1, b + 1) for a, b in ship["lanes"]]
    for i in range(0, len(rows), 8):
        out.append("    " + " ".join(rows[i:i + 8]))
    out.append("  },")
    out.append("},")
    return "\n".join(out) + "\n"


def fmt(v):
    text = ("%.3f" % v).rstrip("0").rstrip(".")
    return text if text not in ("", "-0") else "0"


# ---- Drawing --------------------------------------------------------------------

def overlay(result, ship, size, stats):
    grid = result["grid"]
    region = regions.REGIONS[result["region"]]
    mapper = rooms.Mapper(grid, region)
    F, fl = result["F"], result["fl"]
    data = router_data(result, ship)
    kx, ky = data["yards"]
    layers = []
    shapes = []
    colours = {"line": "#40c0f0", "crossing": "#f0c040", "lift": "#ff4040"}
    for (i, j), kind in zip(ship["lanes"], ship["kind"]):
        (ax, ay), (bx, by) = ship["at"][i], ship["at"][j]
        # Drawn in yards so the circles are round, then back to map %.
        poly = hull_polygon(ax * kx, ay * ky, ship["r"][i], bx * kx, by * ky, ship["r"][j])
        shapes.append({"poly": [[round(x / kx, 4), round(y / ky, 4)] for x, y in poly], "fill": colours[kind],
                       "opacity": 0.25, "stroke": colours[kind], "width": 0.5,
                       "tip": "%s %d-%d: r %.1f / %.1f yd, %.1f yd long" % (
                           kind, i + 1, j + 1, ship["r"][i], ship["r"][j],
                           math.hypot((ax - bx) * kx, (ay - by) * ky))})
    layers.append({"name": "Lanes", "on": True,
                   "note": "each lane: the hull of its two end discs (blue along the centre lines, yellow crossings, red lifts)",
                   "shapes": shapes})
    shapes = []
    for (i, j), kind in zip(ship["lanes"], ship["kind"]):
        shapes.append({"line": [list(ship["at"][i]), list(ship["at"][j])], "stroke": colours[kind], "width": 1.5})
    layers.append({"name": "Centre lines", "on": True, "note": "the connections", "shapes": shapes})
    shapes = []
    for k, p in enumerate(ship["pts"]):
        h = F.fl.h[p]
        shapes.append({"dot": list(ship["at"][k]), "r": 3, "fill": "#ff5050" if ship["kinds"][k] else "#ffffff",
                       "tip": "point %d: r %.1f yd, floor %.1f high%s" % (k + 1, ship["r"][k], h,
                                                                        ", " + ship["kinds"][k] if ship["kinds"][k] else "")})
    layers.append({"name": "Points", "on": True, "note": "points; hover for the radius", "shapes": shapes})
    shapes = []
    for rings in rooms.cell_rings(mapper, rooms.spans_cells(grid, fl.span[result["open"]]), 0.6):
        shapes.append({"rings": rings, "fill": "#e04040", "opacity": 0.3, "stroke": "#e04040", "width": 1})
    layers.append({"name": "Open floor", "on": False,
                   "note": "floor over %.0f yd from the filtered floor's edge, which lanes keep round" % result["settings"]["band"],
                   "shapes": shapes})
    shapes = []
    for path in result["raw"]:
        shapes.append({"line": [[round(v, 4) for v in mapper.to_map(F.u[p], F.v[p])] for p in path[::3] + path[-1:]],
                       "stroke": "#a0a0a0", "width": 1})
    for path in result["pillars"]:
        shapes.append({"line": [[round(v, 4) for v in mapper.to_map(F.u[p], F.v[p])] for p in path[::3] + path[-1:] if p >= 0],
                       "stroke": "#ff40ff", "width": 1.5, "dash": "3 3", "tip": "dropped: the narrower side of a loop round an obstacle"})
    layers.append({"name": "Band centre lines", "on": False,
                   "note": "grey: the band's centre lines the lanes are cut from; pink dashed: sides of loops round obstacles dropped",
                   "shapes": shapes})
    for name, key, colour, note in (
            ("Dropped: steep", "steep", "#a05020", "floor steeper than %.0f degrees" % FLOOR["slope"]),
            ("Dropped: ledges", "ledges", "#a0a020", "floor the ways in do not reach once steep floor and the shave are gone")):
        shapes = []
        for rings in rooms.cell_rings(mapper, rooms.spans_cells(grid, np.nonzero(result["dropped"][key])[0]), 0.6):
            shapes.append({"rings": rings, "fill": colour, "opacity": 0.6, "stroke": colour, "width": 1})
        layers.append({"name": name, "on": False, "note": note, "shapes": shapes})
    return {"name": "Wide lanes", "colour": "#40c0f0", "stats": ["%d points, %d lanes, %d bytes of Lua" % (
        len(ship["pts"]), len(ship["lanes"]), size)] + stats, "data": data, "layers": layers}


# ---- Checking -------------------------------------------------------------------

NODE = r"""
const fs = require("fs");
let router = null;
global.NuuRoadViewer = { method: (id, r) => { router = r; } };
require(process.argv[2]);
const input = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const data = input.data;
const yd = (a, b) => Math.hypot((a[0] - b[0]) * data.yards[0], (a[1] - b[1]) * data.yards[1]);
const ctx = { yd, yards: data.yards };
const out = {};
let t0 = process.hrtime.bigint();
router.prepare(data);
out.load_ms = Number(process.hrtime.bigint() - t0) / 1e6;
for (const pass of [0, 1]) {
  t0 = process.hrtime.bigint();
  out.routes = input.trips.map(([s, t, sl, tl]) => router.route(data, s, t, ctx, sl || undefined, tl || undefined));
  out[pass ? "ms" : "cold_ms"] = Number(process.hrtime.bigint() - t0) / 1e6;
}
out.located = input.locate.map((p) => router.locate(data, p));
t0 = process.hrtime.bigint();
let steps = 0;
out.tracked = [];
for (const [lanes, path] of input.walks) {
  let state = lanes && lanes.length ? lanes : router.locate(data, path[0]);
  for (let i = 1; i < path.length; i++) { state = router.track(data, state, path[i]); steps++; }
  out.tracked.push(state);
}
out.track_us = steps ? Number(process.hrtime.bigint() - t0) / 1e3 / steps : 0;
console.log(JSON.stringify(out));
"""


def run_js(data, trips, locate, walks):
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "input.json"), "w") as handle:
            json.dump({"data": data, "trips": trips, "locate": locate, "walks": walks}, handle)
        with open(os.path.join(tmp, "check.js"), "w") as handle:
            handle.write(NODE)
        out = subprocess.run(["node", os.path.join(tmp, "check.js"), os.path.join(HERE, "widelanes.js"),
                              os.path.join(tmp, "input.json")], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit("node: " + out.stderr)
    return json.loads(out.stdout)


def lanes_of_span(result, ship, span, reach=40):
    """The lanes over a span of the whole navmesh, on its own level: those
    whose floor holds it, else those of the nearest span that some lane
    holds, found through the navmesh's links (so never on another floor)."""
    grid, fl = result["grid"], result["fl"]
    owner = result.setdefault("_owner", None)
    if owner is None:
        owner = collections.defaultdict(list)
        pts = ship["pts"]
        for k, (i, j) in enumerate(ship["lanes"]):
            key = (min(pts[i], pts[j]), max(pts[i], pts[j]))
            for f in result["net"].cover[key]:
                owner[int(fl.span[f])].append(k)
        result["_owner"] = owner
    seen, frontier = {span}, [span]
    for _ in range(reach):
        found = sorted({k for s in frontier for k in owner.get(s, ())})
        if found:
            return found
        nxt = []
        for s in frontier:
            for o in grid.n[s]:
                if o >= 0 and o not in seen:
                    seen.add(int(o))
                    nxt.append(int(o))
        frontier = nxt
    return []


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
    t0 = time.time()
    result = build(region_name, s)
    ship = shipped(result)
    source = lua(result, ship)
    size = len(source.encode())
    with open(os.path.join(CACHE, region_name + ".widelanes.place.lua"), "w", encoding="ascii") as handle:
        handle.write(source)
    say("%s.widelanes.place.lua: %d bytes, %d points, %d lanes (%d crossings); built in %.1f s" % (
        region_name, size, len(ship["pts"]), len(ship["lanes"]), ship["kind"].count("crossing"), time.time() - t0))
    data = router_data(result, ship)
    stats = []
    bench_path = os.path.join(CACHE, region_name + ".bench.json")
    if region_name in bench.ENTRANCES and os.path.exists(bench_path):
        cases = bench.load(region_name)[2]["cases"]
        start_lanes = [lanes_of_span(result, ship, c["from"]["span"]) for c in cases]
        target_lanes = [lanes_of_span(result, ship, c["to"]["span"]) for c in cases]
        trips = [[c["from"]["at"], c["to"]["at"], None, None] for c in cases]
        known = [[c["from"]["at"], c["to"]["at"], sl or None, tl or None]
                 for c, sl, tl in zip(cases, start_lanes, target_lanes)]
        paths = [rooms.walk_points(c["path"], 0.5, data["yards"]) for c in cases]
        # The tracker along each true walk: from the start's lane, and lost
        # (no lane yet: every lane holding the first spot).
        walks = [[sl, path] for sl, path in zip(start_lanes, paths)] + [[None, path] for path in paths]
        js = run_js(data, trips + known, [c["to"]["at"] for c in cases], walks)
        n = len(cases)
        # For looking into single trips: the routes as the router gave them.
        if os.environ.get("WIDELANES_DUMP"):
            with open(os.environ["WIDELANES_DUMP"], "w") as handle:
                json.dump({"map": js["routes"][:n], "known": js["routes"][n:], "start_lanes": start_lanes,
                           "target_lanes": target_lanes}, handle)
        by_trip = {(tuple(c["from"]["at"]), tuple(c["to"]["at"])): r for c, r in zip(cases, js["routes"][:n])}
        by_known = {(tuple(c["from"]["at"]), tuple(c["to"]["at"])): r for c, r in zip(cases, js["routes"][n:])}
        score = bench.score(region_name, "widelanes", lambda a, b: (by_trip.get((tuple(a), tuple(b))) or {}).get("points"), size)
        known_score = bench.score(region_name, "widelanes.known",
                                  lambda a, b: (by_known.get((tuple(a), tuple(b))) or {}).get("points"), size)
        rows = json.load(open(os.path.join(CACHE, region_name + ".score.widelanes.json")))["rows"]
        stacked = [i for i, c in enumerate(cases) if len(floors_under(result, ship, c["to"]["span"])) > 1]
        right = sum(1 for i in stacked if rows[i].get("reached"))
        tracked = sum(1 for got, c in zip(js["tracked"][:n], cases) if got and all(on_level(result, ship, k, c["to"]["span"]) for k in got))
        lost = sum(1 for got, c in zip(js["tracked"][n:], cases) if got and all(on_level(result, ship, k, c["to"]["span"]) for k in got))
        per = js["ms"] / (2 * n)
        under = np.zeros(len(result["fl"]), bool)
        for spans in result["net"].cover.values():
            under[spans] = True
        stats += [
            "map only: walkable %d/%d, reached %d, ratio %.3f (worst %.2f), %.1f bends, clearance %.1f yd, open %.0f%%" % (
                score["walkable"], n, score["reached"], score["ratio_mean"] or 0, score["ratio_worst"] or 0,
                score["bends_mean"], score["clearance_mean"], 100 * score["open_mean"]),
            "lanes known: walkable %d/%d, reached %d, ratio %.3f (worst %.2f), %.1f bends, clearance %.1f yd, open %.0f%%" % (
                known_score["walkable"], n, known_score["reached"], known_score["ratio_mean"] or 0,
                known_score["ratio_worst"] or 0, known_score["bends_mean"], known_score["clearance_mean"],
                100 * known_score["open_mean"]),
            "routes: %.3f ms each in node (%.3f ms the first pass); load %.1f ms" % (per, js["cold_ms"] / (2 * n), js["load_ms"]),
            "tracker: %.2f us a step; along the %d true walks (0.5 yd steps) ends on the target's floor on %d "
            "from the start's lane, on %d starting lost" % (js["track_us"], n, tracked, lost),
            "stacked: %d targets stand in lanes of two floors; map only reaches the right floor for %d of them" % (
                len(stacked), right),
            "lanes cover %.0f%% of the filtered floor" % (100 * under.mean()),
        ]
        for line in stats:
            say(line)
        astray = [c["id"] for got, c in zip(js["tracked"][:n], cases)
                  if not (got and all(on_level(result, ship, k, c["to"]["span"]) for k in got))]
        if astray:
            say("tracker off the target's floor: %s" % ", ".join(astray))
        failed = [c["id"] for c, r in zip(cases, js["routes"][n:]) if not r]
        if failed:
            say("no route (lanes known): %s" % ", ".join(failed))
    else:
        js = run_js(data, [], [], [])
    with open(os.path.join(CACHE, region_name + ".method.widelanes.json"), "w") as handle:
        json.dump(overlay(result, ship, size, stats), handle)


def on_level(result, ship, k, span, rise=3.0):
    """Whether shipped lane k is on the floor of a navmesh span: the spot it
    covers nearest the span (on the map) is within `rise` yards of its height."""
    grid, fl, net = result["grid"], result["fl"], result["net"]
    i, j = ship["lanes"][k]
    cover = net.cover[(min(ship["pts"][i], ship["pts"][j]), max(ship["pts"][i], ship["pts"][j]))]
    near = cover[np.argmin(np.hypot(fl.x[cover] - grid.x[span], fl.z[cover] - grid.z[span]))]
    return abs(fl.h[near] - grid.world(span)[2]) <= rise


def floors_under(result, ship, span):
    """The spans of a navmesh column (that of `span`) that lanes cover: one
    per floor the lanes over that spot are on."""
    lanes_of_span(result, ship, span)   # fills result["_owner"]
    grid = result["grid"]
    column = int(grid.x[span]) + int(grid.z[span]) * grid.grid.width
    return [s for s in grid.grid.spans_in(column) if result["_owner"].get(int(s))]


if __name__ == "__main__":
    main()
