#!/usr/bin/env python3
"""The benchmark every way of pathing a place is measured on: a region's
floor, a fixed set of trips across it, and the true shortest walk for each.

    python3 Tools/ClientMap/bench.py venturemine

The floor is what skeleton.py starts from (the navmesh's pieces of
`smallest` square yards or more, cut down to the way into the models) and
then only the piece the region's entrance stands on. A trip is a start and a
target on that floor; the kinds are:

  * deep: from the entrance to the spots farthest from it and from each
    other (the ends of the branches);
  * random: two spots anywhere with room round them (seed 1);
  * behind: two spots close on the map but far apart on foot, the case
    where a target near another room's wall pulls a route the wrong way;
  * stacked: a target with another floor of the place above or below it.

The truth is the shortest walk over the floor's half-yard cells (eight
neighbours, heights included), pulled straight wherever a line can be
walked. It runs 0.5 yd from the walls (the navmesh already keeps the
player's radius off them), so no method can beat it by more than rounding.

Writes .cache/<region>.bench.json. Methods import this module and call
check() on a route, or score() with a router for every trip (writes
.cache/<region>.score.<method>.json); view.py draws the trips and their
truths. `bench.py venturemine --score-current` scores today's place
(skeleton.py) as the baseline.
"""

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maps  # noqa: E402
import navgrid  # noqa: E402
import regions  # noqa: E402
import skeleton  # noqa: E402
from casc import CACHE  # noqa: E402

# Where each benchmark region is walked into, in world yards (X, Y, height).
ENTRANCES = {
    "venturemine": (-1513.0, -1049.0, 156.0),
}


def floor(region_name, smallest=500.0):
    """(grid, mask): the region's navmesh with its distance field, and the
    spans of the floor the entrance stands on. Kept in .cache/<region>.floor.npz."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    region = regions.REGIONS[region_name]
    base = navgrid.load(region_name)
    grid = skeleton.Work(base)
    grid.source = base.source
    path = os.path.join(CACHE, region_name + ".floor.npz")
    if os.path.exists(path) and os.path.getmtime(path) > os.path.getmtime(os.path.join(CACHE, region_name + ".bin")):
        saved = np.load(path)
        grid.dist = saved["dist"]
        return grid, saved["mask"]
    n = len(base)
    rows = np.repeat(np.arange(n), 4)
    cols = base.n.reshape(-1)
    ok = cols >= 0
    links = coo_matrix((np.ones(ok.sum(), np.int8), (rows[ok], cols[ok])), shape=(n, n)).tocsr()
    _, labels = connected_components(links, directed=False)
    sizes = np.bincount(labels)
    mask = sizes[labels] * base.cell ** 2 >= smallest
    if region.get("terrain") == "approach":
        mask &= skeleton.near_models(base, region.get("approach", 30.0))
    start = nearest_span(grid, mask, *ENTRANCES[region_name])
    if start is None:
        raise ValueError("no floor under the entrance of %s" % region_name)
    # Only the piece the entrance is on, as the mask leaves it.
    sub = links[mask][:, mask]
    _, pieces = connected_components(sub, directed=False)
    index = np.nonzero(mask)[0]
    keep = np.zeros(n, bool)
    keep[index[pieces == pieces[np.searchsorted(index, start)]]] = True
    grid.dist = skeleton.distance_field(grid, keep)
    np.savez_compressed(path, mask=keep, dist=grid.dist)
    return grid, keep


def nearest_span(grid, mask, x, y, h=None, reach=6.0):
    """The span of `mask` nearest (x, y), and nearest height `h` among
    stacked floors, within `reach` yards; None if there is none."""
    column = grid.grid.column_of(x, y)
    if column is None:
        return None
    cells = int(reach / grid.cell)
    cx, cz = column % grid.grid.width, column // grid.grid.width
    best, best_cost = None, None
    for dz in range(-cells, cells + 1):
        for dx in range(-cells, cells + 1):
            nx, nz = cx + dx, cz + dz
            if not (0 <= nx < grid.grid.width and 0 <= nz < grid.grid.depth):
                continue
            for span in grid.grid.spans_in(nx + nz * grid.grid.width):
                if not mask[span]:
                    continue
                wx, wy, wh = grid.world(span)
                flat = math.hypot(wx - x, wy - y)
                if flat > reach:
                    continue
                cost = flat + (abs(wh - h) * 4 if h is not None else 0)
                if best_cost is None or cost < best_cost:
                    best, best_cost = span, cost
    return best


def links8(grid, mask):
    """The floor as a sparse graph: each span to its eight neighbours,
    weighted by the 3D distance between their centres."""
    from scipy.sparse import coo_matrix
    ring = skeleton.rings(grid, mask)
    rows, cols = [], []
    n = grid.n
    safe = lambda a: np.maximum(a, 0)  # noqa: E731
    for k in range(8):
        other = ring[:, k]
        ok = mask & (other >= 0)
        ok[ok] &= mask[other[ok]]
        if k % 2:
            # A diagonal step only round a corner that is floor too.
            d, e = k // 2, (k // 2 + 1) % 4
            corner = np.zeros(len(grid), bool)
            for first, second in ((d, e), (e, d)):
                mid = n[:, first]
                corner |= (mid >= 0) & mask[safe(mid)] & (n[safe(mid), second] == other)
            ok &= corner
        rows.append(np.nonzero(ok)[0])
        cols.append(other[ok])
    rows, cols = np.concatenate(rows), np.concatenate(cols)
    pa = np.stack([grid.x[rows] * grid.cell, grid.z[rows] * grid.cell, grid.y[rows] * grid.cell_height], 1)
    pb = np.stack([grid.x[cols] * grid.cell, grid.z[cols] * grid.cell, grid.y[cols] * grid.cell_height], 1)
    weight = np.linalg.norm(pa - pb, axis=1)
    return coo_matrix((weight, (rows, cols)), shape=(len(grid), len(grid))).tocsr()


def walk(grid, mask, span, x1, z1, passed=None):
    """Follows a straight line from `span` to column (x1, z1) through the
    spans' own links, as skeleton.visible does. Returns (end span or -1,
    the least distance field value passed); `passed`, a list, gets the
    distance field value of every span stepped on."""
    x0, z0 = int(grid.x[span]), int(grid.z[span])
    dx, dz = x1 - x0, z1 - z0
    steps = max(abs(dx), abs(dz))
    x, z, least = x0, z0, int(grid.dist[span])
    for k in range(1, steps + 1):
        tx, tz = x0 + round(dx * k / steps), z0 + round(dz * k / steps)
        moves = []
        if tx != x:
            moves.append(0 if tx < x else 2)
        if tz != z:
            moves.append(3 if tz < z else 1)
        for order in (moves, moves[::-1]):
            here = span
            for d in order:
                here = grid.n[here, d] if here >= 0 else -1
                if here < 0 or not mask[here]:
                    here = -1
                    break
            if here >= 0:
                break
        if here < 0:
            return -1, least
        span, x, z = here, tx, tz
        least = min(least, int(grid.dist[span]))
        if passed is not None:
            passed.append(int(grid.dist[span]))
    return span, least


def span_point(grid, region, span):
    wx, wy, wh = grid.world(span)
    mx, my = regions.to_map(region["map"], wx, wy)
    return {"at": [round(mx, 4), round(my, 4)], "world": [round(wx, 2), round(wy, 2), round(wh, 2)], "span": int(span)}


def pick_cases(grid, mask, region, entrance, links):
    from scipy.sparse.csgraph import dijkstra
    rng = np.random.default_rng(1)
    floor_spans = np.nonzero(mask)[0]
    roomy = floor_spans[grid.dist[floor_spans] * grid.cell / 2 + 0.5 >= 1.5]
    cases = []
    # Deep: farthest point sampling on walking distance from the entrance.
    chosen = [entrance]
    best = dijkstra(links, indices=entrance)
    for _ in range(8):
        far = np.where(np.isfinite(best) & mask, best, -1)
        pick = int(np.argmax(far))
        chosen.append(pick)
        cases.append(("deep", entrance, pick))
        best = np.minimum(best, dijkstra(links, indices=pick))
    # Random.
    for _ in range(24):
        a, b = rng.choice(roomy, 2, replace=False)
        cases.append(("random", int(a), int(b)))
    # Behind: close on the map, far on foot.
    starts = rng.choice(roomy, 40, replace=False)
    far_on_foot = dijkstra(links, indices=starts)
    behind = []
    for row, a in enumerate(starts):
        ax, ay, _ = grid.world(a)
        sample = rng.choice(roomy, 400)
        world = np.stack([grid.bmin[0] + (grid.x[sample] + 0.5) * grid.cell,
                          -(grid.bmin[2] + (grid.z[sample] + 0.5) * grid.cell)], 1)
        flat = np.hypot(world[:, 0] - ax, world[:, 1] - ay)
        foot = far_on_foot[row, sample]
        ok = (flat > 5) & (flat < 25) & np.isfinite(foot)
        if ok.any():
            ratio = np.where(ok, foot / np.maximum(flat, 1), 0)
            j = int(np.argmax(ratio))
            behind.append((float(ratio[j]), int(a), int(sample[j])))
    behind.sort(reverse=True)
    for _, a, b in behind[:8]:
        cases.append(("behind", a, b))
    # Stacked: a target in a column with another floor of the place in it.
    counts = np.zeros(grid.grid.width * grid.grid.depth, np.int32)
    columns = grid.x[floor_spans] + grid.z[floor_spans] * grid.grid.width
    np.add.at(counts, columns, 1)
    stacked = roomy[counts[grid.x[roomy] + grid.z[roomy] * grid.grid.width] > 1]
    if len(stacked):
        for b in rng.choice(stacked, min(6, len(stacked)), replace=False):
            cases.append(("stacked", entrance, int(b)))
    return cases


def straighten(grid, mask, path):
    """The spans of `path` to keep: from each, the farthest one further
    along that a straight line reaches on its own floor (skeleton.visible
    also takes another floor of the same column)."""
    keep, i, last = [path[0]], 0, len(path) - 1
    while i < last:
        j = last
        while j > i + 1 and walk(grid, mask, path[i], int(grid.x[path[j]]), int(grid.z[path[j]]))[0] != path[j]:
            j = max(i + 1, j - max(1, (j - i) // 8))
        keep.append(path[j])
        i = j
    return keep


def truth(grid, mask, links, cases):
    """The shortest walk of each case, pulled straight."""
    from scipy.sparse.csgraph import dijkstra
    starts = sorted({a for _, a, _ in cases})
    dist, pred = dijkstra(links, indices=starts, return_predecessors=True)
    row = {s: i for i, s in enumerate(starts)}
    out = []
    for kind, a, b in cases:
        r = row[a]
        if not np.isfinite(dist[r, b]):
            out.append(None)
            continue
        path = [b]
        while path[-1] != a:
            path.append(int(pred[r, path[-1]]))
        path.reverse()
        pulled = straighten(grid, mask, path)
        length = sum(math.dist(grid.world(pulled[i]), grid.world(pulled[i + 1])) for i in range(len(pulled) - 1))
        out.append((pulled, length, float(dist[r, b])))
    return out


# ---- Checking a method's route ------------------------------------------------

_loaded = {}


def load(region_name):
    """(grid, mask, bench) for check(); read once per process."""
    if region_name not in _loaded:
        grid, mask = floor(region_name)
        bench = json.load(open(os.path.join(CACHE, region_name + ".bench.json")))
        _loaded[region_name] = (grid, mask, bench)
    return _loaded[region_name]


def check(region_name, case, points):
    """How a method's route for `case` (a case dict from the bench file)
    measures up. `points` is the whole route in map %, start to target.

    Walks each leg from where the last one ended through the floor's own
    links (so it stays on its level): `reached` is whether it ends on the
    target's floor (a route to the same spot on the floor above or below
    does not count); `walkable` is whether every leg can be walked in a
    straight line and it reaches the target; `blocked` counts the legs that
    cannot;
    `length` is in yards (2D, as the game measures); `ratio` is that over
    the truth's 2D length; `clearance` is the least and mean yards to a wall
    along the route, and `open` the share of it more than 6 yd from any wall
    (both say whether it keeps to the middle or the sides; legs that cannot
    be walked are left out of them)."""
    grid, mask, bench = load(region_name)
    region = regions.REGIONS[region_name]
    span = case["from"]["span"]
    blocked, least, samples = 0, None, []
    length = 0.0
    for i in range(1, len(points)):
        x0, y0 = regions.to_world(region["map"], *points[i - 1])
        x1, y1 = regions.to_world(region["map"], *points[i])
        length += math.hypot(x1 - x0, y1 - y0)
        column = grid.grid.column_of(x1, y1)
        passed = []
        end, low = (-1, 0) if column is None else walk(grid, mask, span, column % grid.grid.width, column // grid.grid.width, passed)
        if end < 0:
            blocked += 1
            # Carry on from the floor nearest the next point, at the level we were on.
            end = nearest_span(grid, mask, x1, y1, grid.world(span)[2], reach=10.0)
            if end is None:
                return {"walkable": False, "blocked": blocked, "length": None, "ratio": None, "lost": True}
        else:
            least = low if least is None else min(least, low)
            samples.extend(passed)
        span = end
    yd = lambda d: d * grid.cell / 2 + 0.5  # noqa: E731
    truth2d = case["truth2d"]
    # Reached: in the target's column and on its floor, not one above or below.
    goal = case["to"]["span"]
    reached = bool(span == goal) or bool(grid.x[span] == grid.x[goal] and grid.z[span] == grid.z[goal]
                                         and abs(grid.world(span)[2] - grid.world(goal)[2]) <= 2.5)
    return {"walkable": blocked == 0 and reached, "blocked": blocked, "length": round(length, 1),
            "ratio": round(length / truth2d, 3) if truth2d else None,
            "clearance": [round(yd(least), 1) if least is not None else None,
                          round(yd(sum(samples) / len(samples)), 1) if samples else None],
            "open": round(sum(1 for d in samples if yd(d) > 6.0) / len(samples), 3) if samples else None,
            "reached": reached}


def score(region_name, method_id, route, size=None):
    """Runs `route(start, target)` (map % in, map % route out, start to
    target, or None) over every trip, checks each, and writes
    .cache/<region>.score.<method_id>.json. `size` is what the method would
    ship for the place, in bytes of Lua source. Prints a summary."""
    import time
    _, _, bench = load(region_name)
    rows = []
    for case in bench["cases"]:
        t0 = time.perf_counter()
        points = route(case["from"]["at"], case["to"]["at"])
        ms = (time.perf_counter() - t0) * 1000
        row = {"id": case["id"], "kind": case["kind"], "ms": round(ms, 2)}
        if points:
            row.update(check(region_name, case, points))
            row["bends"] = len(points) - 2
        else:
            row.update({"walkable": False, "reached": False, "ratio": None})
        rows.append(row)
    ok = [r for r in rows if r.get("ratio") is not None]
    summary = {"method": method_id, "cases": len(rows), "routed": len(ok),
               "walkable": sum(1 for r in rows if r["walkable"]),
               "reached": sum(1 for r in rows if r.get("reached")),
               "ratio_mean": round(sum(r["ratio"] for r in ok) / len(ok), 3) if ok else None,
               "ratio_worst": max((r["ratio"] for r in ok), default=None),
               "clearance_mean": round(sum(r["clearance"][1] for r in ok if r.get("clearance") and r["clearance"][1]) / max(1, len(ok)), 2),
               "open_mean": round(sum(r["open"] for r in ok if r.get("open") is not None) / max(1, len(ok)), 3),
               "bends_mean": round(sum(r.get("bends", 0) for r in ok) / max(1, len(ok)), 1),
               "ms_mean": round(sum(r["ms"] for r in rows) / len(rows), 2), "size": size}
    by_kind = {}
    for r in rows:
        k = by_kind.setdefault(r["kind"], {"n": 0, "walkable": 0, "ratio": []})
        k["n"] += 1
        k["walkable"] += bool(r["walkable"])
        if r.get("ratio") is not None:
            k["ratio"].append(r["ratio"])
    summary["kinds"] = {k: {"n": v["n"], "walkable": v["walkable"],
                            "ratio_mean": round(sum(v["ratio"]) / len(v["ratio"]), 3) if v["ratio"] else None}
                        for k, v in by_kind.items()}
    with open(os.path.join(CACHE, "%s.score.%s.json" % (region_name, method_id)), "w") as handle:
        json.dump({"summary": summary, "rows": rows}, handle, indent=1)
    print(json.dumps(summary, indent=1))
    return summary


def current_router(region_name, width=20.0):
    """Today's place (skeleton.py's graph) as Domain/Travel.lua uses it: the
    connection nearest in 2D within `width` yd, joined at both ends, then
    Dijkstra to the target's connection."""
    import heapq
    graph = json.load(open(os.path.join(CACHE, region_name + ".graph.json")))
    region = regions.REGIONS[region_name]
    b = maps.get(region["map"])
    ky, kx = abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100
    P = [p["at"] for p in graph["points"]]
    C = graph["connections"]
    yd = lambda a, c: math.hypot((a[0] - c[0]) * ky, (a[1] - c[1]) * kx)  # noqa: E731

    def attach(q):
        best = None
        for i, c in enumerate(C):
            a, e = P[c[0]], P[c[1]]
            dx, dy = e[0] - a[0], e[1] - a[1]
            L = dx * dx + dy * dy
            t = max(0.0, min(1.0, ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / L)) if L else 0.0
            f = [a[0] + t * dx, a[1] + t * dy]
            d = yd(q, f)
            if d <= width and (best is None or d < best[2]):
                best = (i, f, d)
        return best

    def route(start, target):
        s, t = attach(start), attach(target)
        if not s or not t:
            return None
        n = len(P)
        adj = [[] for _ in range(n + 2)]
        for c in C:
            w = yd(P[c[0]], P[c[1]])
            adj[c[0]].append((c[1], w))
            if not (len(c) > 2 and c[2]):
                adj[c[1]].append((c[0], w))
        S, T = n, n + 1
        for end in C[s[0]][:2]:
            adj[S].append((end, s[2] + yd(s[1], P[end])))
        for end in C[t[0]][:2]:
            adj[end].append((T, t[2] + yd(t[1], P[end])))
        if s[0] == t[0]:
            adj[S].append((T, yd(start, target)))
        dist, prev, heap = {S: 0.0}, {}, [(0.0, S)]
        while heap:
            d, u = heapq.heappop(heap)
            if u == T:
                break
            if d > dist.get(u, 1e18):
                continue
            for v, w in adj[u]:
                if d + w < dist.get(v, 1e18):
                    dist[v], prev[v] = d + w, u
                    heapq.heappush(heap, (d + w, v))
        if T not in dist:
            return None
        path, u = [], prev[T]
        while u != S:
            path.append(P[u])
            u = prev[u]
        return [list(start)] + path[::-1] + [list(target)]

    source = open(os.path.join(CACHE, region_name + ".place.lua")).read()
    return route, len(source.encode())


def main():
    region_name = sys.argv[1] if len(sys.argv) > 1 else "venturemine"
    if "--score-current" in sys.argv:
        route, size = current_router(region_name)
        score(region_name, "current", route, size)
        return
    region = regions.REGIONS[region_name]
    grid, mask = floor(region_name)
    print("floor: %d spans (%d square yards)" % (mask.sum(), mask.sum() * grid.cell ** 2), file=sys.stderr)
    links = links8(grid, mask)
    entrance = nearest_span(grid, mask, *ENTRANCES[region_name])
    cases = pick_cases(grid, mask, region, entrance, links)
    truths = truth(grid, mask, links, cases)
    b = maps.get(region["map"])
    out = {"region": region_name, "map": region["map"],
           "entrance": span_point(grid, region, entrance),
           # Yards per map % across and down.
           "yards": [abs(b["right"] - b["left"]) / 100, abs(b["bottom"] - b["top"]) / 100],
           "cases": []}
    for i, ((kind, a, b_), found) in enumerate(zip(cases, truths)):
        if found is None:
            continue
        pulled, length, grid_length = found
        path = [span_point(grid, region, s)["at"] for s in pulled]
        flat = 0.0
        for j in range(len(pulled) - 1):
            ax, ay, _ = grid.world(pulled[j])
            bx, by, _ = grid.world(pulled[j + 1])
            flat += math.hypot(bx - ax, by - ay)
        out["cases"].append({"id": "%s%d" % (kind, i), "kind": kind,
                             "from": span_point(grid, region, a), "to": span_point(grid, region, b_),
                             "truth": round(length, 1), "truth2d": round(flat, 1), "path": path})
    with open(os.path.join(CACHE, region_name + ".bench.json"), "w") as handle:
        json.dump(out, handle)
    kinds = {}
    for c in out["cases"]:
        kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
    print("%d cases (%s)" % (len(out["cases"]), ", ".join("%d %s" % (n, k) for k, n in kinds.items())), file=sys.stderr)


if __name__ == "__main__":
    main()
