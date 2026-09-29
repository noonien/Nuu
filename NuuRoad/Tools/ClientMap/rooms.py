#!/usr/bin/env python3
"""The place's floors split into rooms, halls, corridors, stairs, crossings
and water, with the doorways between them.

    python3 Tools/ClientMap/rooms.py undercity

Starts from the same floors and centre lines as skeleton.py (`prepare`),
cuts the centre lines into pieces, joins the pieces that are one space, and
gives every floor cell to the piece nearest it along the floor:

  * water (floor more than 1.2 yd under a liquid surface: a canal, a pool)
    is left out before thinning, so the streets beside it are their own
    passages, and each stretch of water is a region;
  * a doorway cuts a passage where it narrows to between 2 and 4 yd wide
    and to under 60% of the room on both sides (within 15 yd);
  * stairs are a piece of their own: a stretch rising more steeply than 20
    degrees by 2.5 yd or more;
  * junctions (where centre lines meet) are pieces; two junctions whose
    widest circles overlap, with nothing narrow between, are one open area;
  * a passage piece that lies within a junction's circle is that
    junction's floor, not a corridor;
  * at a junction not much wider than its passages (they keep at least half
    its clearance), the two passages running on through it (120 degrees
    apart or more) are one corridor or street; side branches stay their own.

Each region is then classified from its floor, against its widest point
(the biggest circle that fits): stairs (stairs or a ramp); a corridor (a
tunnel, a street: its area at least 2.5 times the square of that circle's
width, or at least 3 times as long as its usual width and never much wider); a hall (1200 square yards or more, or
16 yd across at its widest); a crossing (a small space where corridors
meet); else a room. Regions under 60 square yards join the neighbour they
share most edge with.

Writes .cache/<region>.rooms.json (regions, doorways) and
.cache/<region>.rooms.npy (the region of every walkable cell, -1 for none)
for view.py.
"""

import collections
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regions  # noqa: E402
import skeleton as sk  # noqa: E402
from casc import CACHE  # noqa: E402

DOOR_MOST = 4.0      # a doorway is at most this much clearance (yd)
DOOR_LEAST = 1.0     # ... and at least this much: a 2 yd door, not a gap
DOOR_RATIO = 0.6     # ... and under this share of the room either side
DOOR_REACH = 15.0    # ... looking this far either side
STEEP = 0.36         # stairs: rise over run (20 degrees)
STAIR_RISE = 2.5     # ... and at least this much rise
NARROW = 0.7         # ... never narrowing below NARROW x clearance
HALL_AREA = 1200.0   # square yards
HALL_WIDTH = 16.0
CORRIDOR_RATIO = 2.5
CROSSING_AREA = 150.0
SMALLEST = 60.0      # square yards


def profile(grid, path):
    s, c, z = [0.0], [], []
    for i, span in enumerate(path):
        x, y, h = grid.world(span)
        if i:
            px, py, _ = grid.world(path[i - 1])
            s.append(s[-1] + math.hypot(x - px, y - py))
        c.append(sk.clearance(grid, span))
        z.append(h)
    return np.array(s), np.array(c), np.array(z)


def cuts(grid, path):
    """Doorways (indices) and stair stretches ([first, last]) along a path."""
    s, c, z = profile(grid, path)
    n = len(path)
    doors = []
    for i in range(1, n - 1):
        if s[i] < 2 or s[-1] - s[i] < 2 or c[i] > DOOR_MOST or c[i] < DOOR_LEAST:
            continue
        near = (s >= s[i] - 6) & (s <= s[i] + 6)
        if c[i] > c[near].min():
            continue
        left = c[(s >= s[i] - DOOR_REACH) & (s <= s[i])].max()
        right = c[(s >= s[i]) & (s <= s[i] + DOOR_REACH)].max()
        if c[i] <= DOOR_RATIO * min(left, right) and (not doors or s[i] - s[doors[-1]] >= 6):
            doors.append(i)
    steep = np.zeros(n, bool)
    j = 0
    for i in range(n):
        while j < n - 1 and s[j] - s[i] < 3:
            j += 1
        if s[j] - s[i] >= 2 and abs(z[j] - z[i]) / (s[j] - s[i]) >= STEEP:
            steep[i:j + 1] = True
    stairs, i = [], 0
    while i < n:
        if steep[i]:
            k = i
            while k + 1 < n and steep[k + 1]:
                k += 1
            if stairs and s[i] - s[stairs[-1][1]] < 2:
                stairs[-1][1] = k
            else:
                stairs.append([i, k])
            i = k + 1
        else:
            i += 1
    stairs = [(a, b) for a, b in stairs if abs(z[b] - z[a]) >= STAIR_RISE]
    return doors, stairs, s, c


class Units:
    """Union-find over pieces of centre line; each piece knows its spans."""

    def __init__(self):
        self.parent, self.spans, self.kind = [], [], []

    def add(self, spans, kind):
        self.parent.append(len(self.parent))
        self.spans.append(list(spans))
        self.kind.append(kind)
        return len(self.parent) - 1

    def root(self, i):
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def join(self, a, b):
        a, b = self.root(a), self.root(b)
        if a != b:
            self.parent[b] = a


def build(region_name):
    p = sk.prepare(region_name, dry=True)
    grid, graph, region = p.grid, p.graph, p.region
    reached = p.mask & np.isin(p.labels, p.reached)
    # Bumps in the walls are not passages: take them off first (the floor
    # beside them still goes to whatever piece is nearest).
    sk.prune(grid, graph, 1.5, p.protect)
    units = Units()
    node_unit = {}
    for node, data in graph.nodes.items():
        node_unit[node] = units.add(data["spans"], "junction")
    doors = []  # (span, clearance, unit on one side, unit on the other)
    for key, edge in graph.edges.items():
        if edge.get("lift"):
            continue
        path = edge["path"]
        ua, ub = node_unit[edge["a"]], node_unit[edge["b"]]
        if len(path) < 3:
            units.join(ua, ub)
            continue
        found_doors, stairs, s, c = cuts(grid, path)
        # A narrowing on a flight of stairs is the stairs, not a doorway.
        found_doors = [i for i in found_doors if not any(a - 2 <= i <= b + 2 for a, b in stairs)]
        # Cut points in order; stairs are pieces of their own.
        marks = sorted([(i, i, "door") for i in found_doors] + [(a, b, "stairs") for a, b in stairs])
        pieces, start, last_unit = [], 1, ua
        prev_door = None
        for a, b, what in marks:
            if a <= start and what == "door":
                continue
            if a > start:
                u = units.add(path[start:a], "passage")
                pieces.append((u, start, a - 1))
                if prev_door is not None:
                    doors[prev_door][3] = u
                    prev_door = None
                last_unit = u
            if what == "door":
                doors.append([path[a], float(c[a]), last_unit, None])
                prev_door = len(doors) - 1
                last_unit = None
                start = a + 1
            else:
                u = units.add(path[a:b + 1], "stairs")
                if prev_door is not None:
                    doors[prev_door][3] = u
                    prev_door = None
                last_unit = u
                start = b + 1
        if start < len(path) - 1:
            u = units.add(path[start:len(path) - 1], "passage")
            pieces.append((u, start, len(path) - 2))
            if prev_door is not None:
                doors[prev_door][3] = u
                prev_door = None
            last_unit = u
        if prev_door is not None:
            doors[prev_door][3] = ub
        # Neighbouring pieces along the path that no door or stairs separate,
        # ends included: the candidates for being one space.
        joins, order = [], []
        piece_at = {}
        for u, a, b in pieces:
            piece_at[a] = u
        stair_at = {a: (a, b) for a, b in stairs}
        door_at = set(found_doors)
        prev = ua
        i = 1
        while i < len(path) - 1:
            if i in door_at:
                prev = None
                i += 1
            elif i in stair_at:
                prev = None
                i = stair_at[i][1] + 1
            elif i in piece_at:
                u = piece_at[i]
                if prev is not None:
                    order.append((prev, u))
                prev = u
                i = [b for uu, a, b in pieces if uu == u][0] + 1
            else:
                i += 1
        if prev is not None:
            order.append((prev, ub))
        for a, b in order:
            joins.append((a, b))
        edge["pieces"] = pieces
        edge["joins"] = joins
        edge["length"] = float(s[-1])
        edge["clear"] = float(c.min())
        edge["cut"] = bool(found_doors or stairs)
    # Which pieces are one space.
    def unit_clear(u):
        spans = units.spans[u]
        if units.kind[u] == "junction":
            return max(sk.clearance(grid, x) for x in spans)
        return float(np.median([sk.clearance(grid, x) for x in spans]))

    def unit_length(u):
        spans = units.spans[u]
        return float(profile(grid, spans)[0][-1]) if len(spans) > 1 else 0.0

    touching = collections.defaultdict(list)  # junction -> [(piece, spans outward)]
    for key, edge in graph.edges.items():
        if edge.get("lift") or len(edge["path"]) < 3:
            continue
        ua, ub = node_unit[edge["a"]], node_unit[edge["b"]]
        ca, cb = unit_clear(ua), unit_clear(ub)
        # Open area: two junctions whose circles overlap, nothing between.
        if not edge["cut"] and edge["length"] <= ca + cb and edge["clear"] >= NARROW * min(ca, cb):
            for x, y in edge["joins"]:
                units.join(x, y)
            continue
        for x, y in edge["joins"]:
            for j, piece in ((x, y), (y, x)):
                if units.kind[j] != "junction" or units.kind[piece] != "passage":
                    continue
                spans = units.spans[piece]
                outward = spans if j == ua else spans[::-1]
                if unit_length(piece) <= unit_clear(j) + 2:
                    units.join(j, piece)      # the junction's own floor
                touching[j].append((piece, outward))
    # Through streets: at a junction no wider than its passages, the two
    # passages running on through it are one corridor.
    stats = {"through": 0}
    for j, pieces_here in touching.items():
        if len(pieces_here) < 2:
            continue
        cj = unit_clear(j)
        centre = grid.world(max(units.spans[j], key=lambda x: grid.dist[x]))
        options = []
        for piece, outward in pieces_here:
            if unit_clear(piece) < 0.5 * cj:
                continue
            ahead = outward[min(len(outward) - 1, int(6 / grid.cell))]
            x, y, _ = grid.world(ahead)
            options.append((piece, math.atan2(y - centre[1], x - centre[0])))
        best = None
        for i in range(len(options)):
            for k in range(i + 1, len(options)):
                d = abs(options[i][1] - options[k][1]) % (2 * math.pi)
                d = math.degrees(min(d, 2 * math.pi - d))
                if d >= 120 and (best is None or d > best[0]):
                    best = (d, options[i][0], options[k][0])
        if best:
            stats["through"] += 1
            units.join(best[1], j)
            units.join(best[1], best[2])

    print("%d junctions joined the passages running through them" % stats["through"], file=sys.stderr)
    # Every walkable cell goes to the nearest piece along the floor.
    owner = np.full(len(grid), -1, np.int64)
    queue = collections.deque()
    for u in range(len(units.parent)):
        r = units.root(u)
        for span in units.spans[u]:
            if reached[span] and owner[span] < 0:
                owner[span] = r
                queue.append(span)
    door_spans = {d[0] for d in doors}
    for span in door_spans:
        owner[span] = -1
    while queue:
        span = queue.popleft()
        for other in grid.n[span]:
            if other >= 0 and reached[other] and owner[other] < 0 and other not in door_spans:
                owner[other] = owner[span]
                queue.append(other)
    for span in door_spans:
        # A doorway cell goes to whichever side holds more of its neighbours.
        sides = [owner[o] for o in grid.n[span] if o >= 0 and owner[o] >= 0]
        if sides:
            owner[span] = max(set(sides), key=sides.count)

    # Merge slivers into the neighbour they share most edge with.
    cell_area = grid.cell ** 2
    real = ~grid.virtual
    for _ in range(3):
        ids, counts = np.unique(owner[(owner >= 0) & real], return_counts=True)
        area = dict(zip(ids.tolist(), (counts * cell_area).tolist()))
        small = {r for r, a in area.items() if a < SMALLEST}
        if not small:
            break
        border = collections.Counter()
        for span in np.nonzero(np.isin(owner, list(small)))[0]:
            for other in grid.n[span]:
                if other >= 0 and owner[other] >= 0 and owner[other] != owner[span]:
                    border[(int(owner[span]), int(owner[other]))] += 1
        into = {}
        for (a, b), n in border.most_common():
            if a not in into and b not in small | set(into):
                into[a] = b
        if not into:
            break
        for a, b in into.items():
            owner[owner == a] = b

    # Water: each stretch of it (in the pieces the place reaches) is a region.
    wet = p.wet & np.isin(p.labels, p.reached)
    next_id = int(owner.max()) + 1 if (owner >= 0).any() else 0
    water_ids = set()
    for start in np.nonzero(wet & (owner < 0))[0]:
        if owner[start] >= 0:
            continue
        owner[start] = next_id
        stack = [start]
        while stack:
            span = stack.pop()
            for other in grid.n[span]:
                if other >= 0 and wet[other] and owner[other] < 0:
                    owner[other] = next_id
                    stack.append(other)
        water_ids.add(next_id)
        next_id += 1

    # Describe each region.
    ids = sorted(set(owner[(owner >= 0) & real].tolist()))
    number = {r: i for i, r in enumerate(ids)}
    region_of = np.array([number.get(int(o), -1) for o in owner]) if len(owner) else owner
    skel_spans = np.nonzero(p.skeleton & reached)[0]
    out_regions = []
    for r in ids:
        cells = np.nonzero((owner == r) & real)[0]
        line = [s for s in skel_spans if owner[s] == r]
        area = len(cells) * cell_area
        clear = np.array([sk.clearance(grid, s) for s in line]) if line else np.array([0.5])
        width = 2 * float(np.median(clear))
        widest = float(clear.max())
        # Length: as long as its floor is, for its width.
        length = area / max(width, 1.0)
        heights = grid.bmin[1] + grid.y[cells] * grid.cell_height
        kinds = [units.kind[u] for u in range(len(units.parent)) if units.root(u) == r]
        if not len(cells):
            continue
        centre_span = max(line, key=lambda s: grid.dist[s]) if line else cells[len(cells) // 2]
        x, y, z = grid.world(centre_span)
        mx, my = regions.to_map(region["map"], x, y)
        if r in water_ids:
            kind = "water"
        elif "stairs" in kinds and kinds.count("stairs") >= len(kinds) / 2:
            kind = "stairs"
        elif (area >= CORRIDOR_RATIO * (2 * widest) ** 2
              or (length >= 3 * width and 2 * widest <= 1.6 * width)):
            kind = "corridor"
        elif area >= HALL_AREA or 2 * widest >= HALL_WIDTH:
            kind = "hall"
        elif "junction" in kinds and area < CROSSING_AREA:
            kind = "crossing"
        else:
            kind = "room"
        out_regions.append({"id": number[r], "kind": kind, "area": round(area), "width": round(width, 1),
                            "widest": round(2 * widest, 1),
                            "length": round(length, 1), "low": round(float(heights.min()), 1),
                            "high": round(float(heights.max()), 1),
                            "at": [round(mx, 2), round(my, 2)], "height": round(z, 1)})
    out_doors = []
    for span, clear, a, b in doors:
        ra = number.get(int(owner[span]), -1)
        sides = sorted({number[int(owner[o])] for o in grid.n[span] if o >= 0 and int(owner[o]) in number})
        x, y, z = grid.world(span)
        mx, my = regions.to_map(region["map"], x, y)
        out_doors.append({"at": [round(mx, 2), round(my, 2)], "height": round(z, 1), "width": round(2 * clear, 1),
                          "regions": sides or [ra]})
    doors_of = collections.Counter(r for d in out_doors for r in d["regions"])
    neighbours = collections.defaultdict(set)
    for span in np.nonzero(region_of >= 0)[0]:
        for other in grid.n[span]:
            if other >= 0 and region_of[other] >= 0 and region_of[other] != region_of[span]:
                neighbours[int(region_of[span])].add(int(region_of[other]))
    for reg in out_regions:
        reg["doors"] = doors_of.get(reg["id"], 0)
        reg["neighbours"] = sorted(neighbours[reg["id"]])
    base = np.full(len(grid.grid), -1, np.int32)
    base[:] = region_of[:len(grid.grid)]
    np.save(os.path.join(CACHE, region_name + ".rooms.npy"), base)
    result = {"region": region_name, "map": region["map"], "regions": out_regions, "doors": out_doors}
    with open(os.path.join(CACHE, region_name + ".rooms.json"), "w") as handle:
        json.dump(result, handle)
    tally = collections.Counter(r["kind"] for r in out_regions)
    print("%d regions (%s), %d doorways" % (len(out_regions), ", ".join(
        "%d %s" % (n, k) for k, n in tally.most_common()), len(out_doors)), file=sys.stderr)
    return result


def main():
    build(sys.argv[1] if len(sys.argv) > 1 else "undercity")


if __name__ == "__main__":
    main()
