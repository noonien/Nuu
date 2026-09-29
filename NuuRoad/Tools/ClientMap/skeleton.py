#!/usr/bin/env python3
"""A guide place from a region's walkable area alone: points at the
junctions, and only as many between them as keep every straight line inside
the passage.

    python3 Tools/ClientMap/skeleton.py undercity [keep=core|long|all] [spur=1.5] [margin=1.0]
                                        [merge=1.0] [fill=80] [close=2.5] [smallest=500]

Reads .cache/<region>.bin (navmesh). Every floor of `smallest` square yards
or more is thinned to its centre lines: spans are peeled off the edges,
nearest the wall first, as long as that never cuts a passage or closes a
loop, and the ridge of the distance field (the middle of every passage) is
never peeled. What is left is traced into a graph, and:

  * the region's lifts (regions.py) join the floor at the top to the one
    below; the map files have no lifts, the server spawns them;
  * the place is what can be reached from the biggest floor, walking or by
    lift; roofs and closed rooms fall away;
  * small obstacles (at most `fill` square yards: pillars, stalls) are
    filled in before thinning, so lines run over them, not round them;
  * a junction is where three or more centre lines meet; junctions closer
    together than `merge` times their clearance (8 yards at most) become one;
  * a dead end shorter than `spur` times the clearance where it leaves its
    junction is a bump in a wall, not a passage, and goes;
  * `keep=core` then drops every branch that leads nowhere (rooms, alcoves),
    keeping the loops and the ways to the region's exits and lifts;
    `keep=long` drops only the dead ends shorter than 25 yd (nooks), keeping
    tunnels to side valleys; `keep=all` keeps every branch;
  * along a passage, a point is kept only where the straight line to the
    next would otherwise leave the floor or pass within `margin` yards of an
    edge (a wall, or a drop); points closer than `close` yards merge.

Recorded trails do not shape the place. They are only a check at the end:
how many of their samples lie within 5 yards of it.

Writes .cache/<region>.graph.json (for view.py) and prints the place as guide
source, in the form Tools/ProcessPlace.lua prints.
"""

import heapq
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import navgrid  # noqa: E402
import regions  # noqa: E402
import trails  # noqa: E402
from casc import CACHE  # noqa: E402

# Recast's directions: 0 -x, 1 +z, 2 +x, 3 -z, which run round the compass,
# so the eight neighbours in order are n0, n0+1, n1, n1+2, n2, n2+3, n3, n3+0.


def rings(grid, alive):
    """(N, 8) array of each span's eight neighbours in order round it (-1: none)."""
    n = grid.n
    ring = np.full((len(grid), 8), -1, np.int64)
    for d in range(4):
        e = (d + 1) % 4
        ring[:, 2 * d] = n[:, d]
        # The corner between d and e, reached either way round.
        via_d = np.where(n[:, d] >= 0, n[np.maximum(n[:, d], 0), e], -1)
        via_e = np.where(n[:, e] >= 0, n[np.maximum(n[:, e], 0), d], -1)
        ring[:, 2 * d + 1] = np.where(via_d >= 0, via_d, via_e)
    return ring


OFFSETS = [(-1, 0), (0, 1), (1, 0), (0, -1)]  # Recast's directions as (dx, dz)


class Work:
    """A copy of the grid's per-span arrays that can grow: filled-in holes
    are extra spans on the end."""

    def __init__(self, grid):
        self.grid = grid
        self.x, self.z, self.y = grid.x.copy(), grid.z.copy(), grid.y.copy()
        self.n, self.dist = grid.n.copy(), grid.dist.copy()
        self.bmin, self.cell, self.cell_height = grid.bmin, grid.cell, grid.cell_height
        self.virtual = np.zeros(len(self.x), bool)

    def __len__(self):
        return len(self.x)

    def world(self, span):
        return (self.bmin[0] + (self.x[span] + 0.5) * self.cell,
                -(self.bmin[2] + (self.z[span] + 0.5) * self.cell),
                self.bmin[1] + self.y[span] * self.cell_height)


def fill_holes(work, mask, labels, pieces, most=80.0, flat=2.0):
    """Fills the small obstacles inside each piece (pillars, stalls, statues)
    with spans of floor, so the centre line runs over them instead of round
    them. A hole is a patch of columns the piece has no floor in, closed in
    by the piece on every side, at most `most` square yards, whose floor all
    round is level within `flat` yards (so a ramp's underside is left
    alone). Returns the grown mask."""
    from scipy import ndimage
    cell_area = work.cell * work.cell
    added_x, added_z, added_y, added_piece = [], [], [], []
    width = int(work.x.max()) + 2
    depth = int(work.z.max()) + 2
    filled = 0
    for piece, _ in pieces:
        spans = np.nonzero(mask & (labels == piece))[0]
        occupied = np.zeros((depth, width), bool)
        occupied[work.z[spans], work.x[spans]] = True
        # One floor per column, or the column is ambiguous for a fill.
        height = np.full((depth, width), np.nan)
        counts = np.zeros((depth, width), np.int32)
        np.add.at(counts, (work.z[spans], work.x[spans]), 1)
        height[work.z[spans], work.x[spans]] = work.y[spans] * work.cell_height
        holes, count = ndimage.label(~occupied)
        edge = set(np.unique(np.concatenate([holes[0], holes[-1], holes[:, 0], holes[:, -1]])).tolist())
        for index, box in enumerate(ndimage.find_objects(holes)):
            hole = index + 1
            if box is None or hole in edge:
                continue
            z0, z1 = max(box[0].start - 1, 0), min(box[0].stop + 1, depth)
            x0, x1 = max(box[1].start - 1, 0), min(box[1].stop + 1, width)
            inside = holes[z0:z1, x0:x1] == hole
            if inside.sum() * cell_area > most:
                continue
            ring = ndimage.binary_dilation(inside) & occupied[z0:z1, x0:x1]
            if (counts[z0:z1, x0:x1][ring] > 1).any():
                continue
            around = height[z0:z1, x0:x1][ring]
            if around.max() - around.min() > flat:
                continue
            level = int(round(np.median(around) / work.cell_height))
            for z, x in np.argwhere(inside):
                added_z.append(z + z0)
                added_x.append(x + x0)
                added_y.append(level)
                added_piece.append(piece)
            filled += 1
    if not added_x:
        return mask
    start = len(work)
    work.x = np.concatenate([work.x, np.array(added_x)])
    work.z = np.concatenate([work.z, np.array(added_z)])
    work.y = np.concatenate([work.y, np.array(added_y, np.int32)])
    work.n = np.concatenate([work.n, np.full((len(added_x), 4), -1, np.int64)])
    work.dist = np.concatenate([work.dist, np.zeros(len(added_x), np.int32)])
    work.virtual = np.concatenate([work.virtual, np.ones(len(added_x), bool)])
    mask = np.concatenate([mask, np.ones(len(added_x), bool)])
    labels_added = np.array(added_piece)
    work.added_piece = labels_added
    # Join the new spans to each other and to the floor round them.
    where = {}
    for span in np.nonzero(mask)[0]:
        piece = labels_added[span - start] if span >= start else labels[span]
        where[(int(work.x[span]), int(work.z[span]), int(piece))] = int(span)
    for span in range(start, len(work)):
        piece = int(labels_added[span - start])
        for d, (dx, dz) in enumerate(OFFSETS):
            other = where.get((int(work.x[span]) + dx, int(work.z[span]) + dz, piece))
            if other is not None:
                work.n[span, d] = other
                work.n[other, (d + 2) % 4] = span
    print("filled %d small obstacles (%d spans)" % (filled, len(added_x)), file=sys.stderr)
    return mask


def distance_field(work, mask):
    """Each span's distance to the nearest edge of the area, 2 per straight
    step and 3 per diagonal one, as Recast counts it."""
    ring = rings(work, mask)
    inside = mask.copy()
    edge = np.zeros(len(work), bool)
    for d in range(4):
        other = work.n[:, d]
        edge |= (other < 0) | ~mask[np.maximum(other, 0)]
    big = 1 << 20
    dist = np.where(inside & ~edge, big, 0).astype(np.int64)
    dist[~inside] = 0
    steps = [2, 3, 2, 3, 2, 3, 2, 3]
    while True:
        best = dist.copy()
        for k in range(8):
            other = ring[:, k]
            ok = (other >= 0) & inside
            candidate = np.where(ok, dist[np.maximum(other, 0)] + steps[k], big)
            best = np.minimum(best, candidate)
        best[~inside] = 0
        best[edge] = 0
        if (best == dist).all():
            break
        dist = best
    return dist.astype(np.int32)


def thin(grid, alive):
    """The centre lines of `alive`: a boolean mask of what is left."""
    alive = alive.copy()
    ring = rings(grid, alive)
    dist = grid.dist
    # The ridge: spans at least as far from the walls as all eight neighbours.
    neighbour_dist = np.where(ring >= 0, dist[np.maximum(ring, 0)], -1)
    ridge = alive & (dist >= neighbour_dist.max(axis=1)) & (dist > 0)

    def on(span):
        return span >= 0 and alive[span]

    def simple(span):
        # Yokoi's 8-connectivity number: exactly one run of neighbours, so
        # taking the span away joins nothing and cuts nothing.
        b = [0 if on(o) else 1 for o in ring[span]]
        count = 0
        for k in (0, 2, 4, 6):
            count += b[k] - b[k] * b[(k + 1) % 8] * b[(k + 2) % 8]
        return count == 1

    def border(span):
        return any(not on(ring[span][k]) for k in (0, 2, 4, 6))

    heap = []
    queued = np.zeros(len(grid), bool)
    for span in np.nonzero(alive)[0]:
        if border(span):
            heap.append((dist[span], int(span)))
            queued[span] = True
    heapq.heapify(heap)
    while heap:
        _, span = heapq.heappop(heap)
        queued[span] = False
        if not alive[span] or ridge[span]:
            continue
        if not simple(span):
            continue
        neighbours = sum(1 for o in ring[span] if on(o))
        if neighbours <= 1:
            continue  # the end of a line
        alive[span] = False
        for o in ring[span]:
            if on(o) and not queued[o]:
                heapq.heappush(heap, (dist[o], int(o)))
                queued[o] = True
    # The ridge is two spans wide where a passage is an even number of cells
    # across; one more pass without it takes the extra side off.
    changed = True
    while changed:
        changed = False
        for span in np.nonzero(alive)[0]:
            if border(span) and simple(span) and sum(1 for o in ring[span] if on(o)) > 1:
                # Only take it if every neighbour it touches stays joined.
                alive[span] = False
                changed = True
    return alive, ring


class Graph:
    """Nodes (spans standing for a point) and edges (the spans between)."""

    def __init__(self):
        self.nodes = {}   # id -> {"span": s, "spans": [..]}
        self.edges = {}   # id -> {"a": node, "b": node, "path": [spans]}
        self.next_node = 0
        self.next_edge = 0

    def add_node(self, spans, span):
        self.nodes[self.next_node] = {"span": span, "spans": list(spans)}
        self.next_node += 1
        return self.next_node - 1

    def add_edge(self, a, b, path):
        self.edges[self.next_edge] = {"a": a, "b": b, "path": list(path)}
        self.next_edge += 1

    def degree(self, node):
        return sum((e["a"] == node) + (e["b"] == node) for e in self.edges.values())

    def edges_of(self, node):
        return [k for k, e in self.edges.items() if e["a"] == node or e["b"] == node]


def trace(grid, skeleton, ring):
    """The skeleton as a graph: junction clusters and ends as nodes, the
    lines between as edges."""
    on = lambda s: s >= 0 and skeleton[s]  # noqa: E731
    spans = np.nonzero(skeleton)[0]
    neighbours = {int(s): [int(o) for o in ring[s] if on(o)] for s in spans}
    special = {s for s, ns in neighbours.items() if len(ns) != 2}
    graph = Graph()
    node_of = {}
    # Junction spans that touch are one junction.
    for s in special:
        if s in node_of:
            continue
        cluster, stack = [], [s]
        node_of[s] = -1
        while stack:
            x = stack.pop()
            cluster.append(x)
            for o in neighbours[x]:
                if o in special and o not in node_of:
                    node_of[o] = -1
                    stack.append(o)
        centre = max(cluster, key=lambda x: grid.dist[x])
        node = graph.add_node(cluster, centre)
        for x in cluster:
            node_of[x] = node
    walked = set()
    for s in special:
        for first in neighbours[s]:
            if first in special or (s, first) in walked:
                continue
            path, previous, current = [s], s, first
            while current not in special:
                path.append(current)
                walked.add((previous, current))
                following = [o for o in neighbours[current] if o != previous]
                if not following:
                    break
                previous, current = current, following[0]
                if current == s:
                    break
            walked.add((previous, current))
            path.append(current)
            walked.add((current, path[-2]))
            if current in node_of and (node_of[current] != node_of[s] or len(path) > 3):
                graph.add_edge(node_of[s], node_of[current], path)
    # Loops with no junction on them at all (a ring of pure passage).
    covered = set(x for e in graph.edges.values() for x in e["path"]) | special
    for s in spans:
        s = int(s)
        if s in covered:
            continue
        loop, previous, current = [s], None, s
        while True:
            following = [o for o in neighbours[current] if o != previous and o not in loop[1:]]
            if not following:
                break
            previous, current = current, following[0]
            if current == s:
                break
            loop.append(current)
        covered.update(loop)
        node = graph.add_node([s], s)
        graph.add_edge(node, node, loop + [s])
    return graph


def yards(grid, a, b):
    ax, ay, _ = grid.world(a)
    bx, by, _ = grid.world(b)
    return math.hypot(ax - bx, ay - by)


def clearance(grid, span):
    """Yards from the span to the nearest wall (Recast's distance is about 2
    per cell, counted from the edge left after eroding by the player's
    radius, which is added back)."""
    return grid.dist[span] * grid.cell / 2.0 + 0.5


def path_length(grid, path):
    return sum(yards(grid, path[i], path[i + 1]) for i in range(len(path) - 1))


def prune(grid, graph, spur, protect=()):
    """Drops short dead ends and merges the edges that leaves in two. Nodes
    in `protect` (lift ends, ways out) stay."""
    changed = True
    while changed:
        changed = False
        for key, edge in list(graph.edges.items()):
            a, b = edge["a"], edge["b"]
            if a == b or edge.get("lift"):
                continue
            for end, other in ((a, b), (b, a)):
                if end in protect:
                    continue
                if graph.degree(end) == 1 and graph.degree(other) >= 3:
                    if path_length(grid, edge["path"]) < spur * clearance(grid, graph.nodes[other]["span"]):
                        del graph.edges[key]
                        del graph.nodes[end]
                        changed = True
                        break
        for node in list(graph.nodes):
            if node in protect:
                continue
            keys = graph.edges_of(node)
            loops = any(graph.edges[k]["a"] == graph.edges[k]["b"] or graph.edges[k].get("lift") for k in keys)
            if len(keys) == 2 and not loops:
                e1, e2 = graph.edges[keys[0]], graph.edges[keys[1]]
                p1 = e1["path"] if e1["b"] == node else e1["path"][::-1]
                p2 = e2["path"] if e2["a"] == node else e2["path"][::-1]
                start = e1["a"] if e1["b"] == node else e1["b"]
                end = e2["b"] if e2["a"] == node else e2["a"]
                del graph.edges[keys[0]]
                del graph.edges[keys[1]]
                del graph.nodes[node]
                graph.add_edge(start, end, p1 + p2[1:])
                changed = True


def merge_junctions(grid, graph, factor, most=8.0, protect=()):
    """Joins junctions that stand closer together than their clearance times
    `factor` (at most `most` yards) into one, where the passage is widest.
    Distances are straight lines between where the junctions stand, so a
    plaza full of small junctions cannot chain into one far-reaching node."""
    changed = True
    while changed:
        changed = False
        for key, edge in list(graph.edges.items()):
            a, b = edge["a"], edge["b"]
            if a == b or edge.get("lift") or a in protect or b in protect:
                continue
            if graph.degree(a) < 3 or graph.degree(b) < 3:
                continue
            span_a, span_b = graph.nodes[a]["span"], graph.nodes[b]["span"]
            if abs(grid.world(span_a)[2] - grid.world(span_b)[2]) > 3:
                continue
            reach = min(most, factor * max(clearance(grid, span_a), clearance(grid, span_b)))
            if yards(grid, span_a, span_b) >= reach:
                continue
            del graph.edges[key]
            if grid.dist[span_b] > grid.dist[span_a]:
                a, b = b, a
            graph.nodes[a]["spans"] += graph.nodes[b]["spans"] + edge["path"]
            for other in graph.edges.values():
                if other["a"] == b:
                    other["a"] = a
                if other["b"] == b:
                    other["b"] = a
            del graph.nodes[b]
            changed = True
            break


def drop_dead_ends(graph, protect=()):
    """Takes off every branch that leads nowhere, until only the passages on
    some loop, or on the way to a node in `protect` (a way out), are left:
    the streets, not the rooms off them."""
    changed = True
    while changed:
        changed = False
        for node in list(graph.nodes):
            if node in protect:
                continue
            keys = graph.edges_of(node)
            if len(keys) == 1 and graph.edges[keys[0]]["a"] != graph.edges[keys[0]]["b"]:
                del graph.edges[keys[0]]
                del graph.nodes[node]
                changed = True
            elif not keys:
                del graph.nodes[node]


def visible(grid, mask, a, b, margin):
    """Whether a straight line from span a to span b can be walked: stepping
    column by column along it, through the spans' own neighbour links (so
    floors stacked over it do not count), never off the area and never
    closer than `margin` (distance field units) to its edge."""
    x0, z0, x1, z1 = int(grid.x[a]), int(grid.z[a]), int(grid.x[b]), int(grid.z[b])
    dx, dz = x1 - x0, z1 - z0
    steps = max(abs(dx), abs(dz))
    span, x, z = a, x0, z0
    for k in range(1, steps + 1):
        tx, tz = x0 + round(dx * k / steps), z0 + round(dz * k / steps)
        moves = []
        if tx != x:
            moves.append(0 if tx < x else 2)
        if tz != z:
            moves.append(3 if tz < z else 1)
        # A diagonal step goes round whichever corner is open.
        for order in (moves, moves[::-1]):
            here = span
            for d in order:
                here = grid.n[here, d] if here >= 0 else -1
                if here < 0 or not mask[here] or grid.dist[here] < margin:
                    here = -1
                    break
            if here >= 0:
                break
        if here < 0:
            return False
        span, x, z = here, tx, tz
    return span == b or (grid.x[span] == grid.x[b] and grid.z[span] == grid.z[b])


def straighten(grid, mask, path, margin):
    """Indices into `path` of the spans to keep: from each kept span, the
    farthest one further along that it can see."""
    keep, i = [0], 0
    last = len(path) - 1
    dist = [int(grid.dist[s]) for s in path]
    while i < last:
        j = last
        # Never ask for more room than the passage itself has.
        while j > i + 1 and not visible(grid, mask, path[i], path[j], min(margin, min(dist[i:j + 1]))):
            # Back off quickly from far away, then span by span.
            j = max(i + 1, j - max(1, (j - i) // 8))
        keep.append(j)
        i = j
    return keep


def merge_close(points, connections, close, fixed=()):
    """Points closer than `close` yards on the same floor become one (the
    one with the most room round it, or the one in `fixed`), and the
    connections follow. Returns (points, connections, old index -> new)."""
    parent = list(range(len(points)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b in connections:
        pa, pb = points[a]["world"], points[b]["world"]
        if math.hypot(pa[0] - pb[0], pa[1] - pb[1]) < close and abs(pa[2] - pb[2]) < 3:
            ra, rb = root(a), root(b)
            if ra != rb:
                if (rb in fixed, points[rb]["clearance"]) > (ra in fixed, points[ra]["clearance"]):
                    ra, rb = rb, ra
                if rb in fixed:
                    continue
                parent[rb] = ra
    index, kept = {}, []
    for i, p in enumerate(points):
        if root(i) == i:
            index[i] = len(kept)
            kept.append(p)
    out = []
    for a, b in connections:
        a, b = index[root(a)], index[root(b)]
        if a != b and [a, b] not in out and [b, a] not in out:
            out.append([a, b])
    return kept, out, {i: index[root(i)] for i in range(len(points))}


def attach(grid, graph, skeleton, labels, span, reach=8.0):
    """The node standing for `span`: the nearest point of the centre lines on
    the same piece within `reach` yards, split out of its edge if need be."""
    piece = labels[span]
    x, y, _ = grid.world(span)
    best, best_d = None, reach
    for node, data in graph.nodes.items():
        s = data["span"]
        if labels[s] == piece:
            d = math.hypot(grid.world(s)[0] - x, grid.world(s)[1] - y)
            if d < best_d:
                best, best_d = ("node", node), d
    for key, edge in graph.edges.items():
        if edge.get("lift"):
            continue
        for i, s in enumerate(edge["path"][1:-1], 1):
            if labels[s] == piece:
                d = math.hypot(grid.world(s)[0] - x, grid.world(s)[1] - y)
                if d < best_d:
                    best, best_d = ("edge", key, i), d
    if best is None:
        return None
    if best[0] == "node":
        return best[1]
    _, key, i = best
    edge = graph.edges.pop(key)
    node = graph.add_node([edge["path"][i]], edge["path"][i])
    graph.add_edge(edge["a"], node, edge["path"][:i + 1])
    graph.add_edge(node, edge["b"], edge["path"][i:])
    return node


def floors_near(grid, mask, x, y, reach=4.0):
    """Spans of `mask` within `reach` yards of (x, y), highest first."""
    column = grid.grid.column_of(x, y)
    if column is None:
        return []
    cx, cz = column % grid.grid.width, column // grid.grid.width
    r = int(math.ceil(reach / grid.cell))
    found = []
    for dx in range(-r, r + 1):
        for dz in range(-r, r + 1):
            nx, nz = cx + dx, cz + dz
            if 0 <= nx < grid.grid.width and 0 <= nz < grid.grid.depth and math.hypot(dx, dz) * grid.cell <= reach:
                found.extend(s for s in grid.grid.spans_in(nx + nz * grid.grid.width) if mask[s])
    return sorted(found, key=lambda s: -grid.y[s])


def add_lift(grid, graph, skeleton, mask, labels, sizes, at, region):
    """Joins the highest floor at a lift to the next big floor 8 yards or
    more below it. Returns the two nodes, or None."""
    x, y = regions.to_world(region["map"], *at)
    spans = floors_near(grid, mask, x, y)
    if not spans:
        return None
    top = spans[0]
    top_z = grid.world(top)[2]
    below = [s for s in spans if grid.world(s)[2] <= top_z - 8 and sizes[labels[s]] * grid.cell ** 2 >= 500]
    if not below:
        return None
    bottom_z = grid.world(below[0])[2]
    bottom = min((s for s in below if abs(grid.world(s)[2] - bottom_z) < 2),
                 key=lambda s: math.hypot(grid.world(s)[0] - x, grid.world(s)[1] - y))
    a = attach(grid, graph, skeleton, labels, top)
    b = attach(grid, graph, skeleton, labels, bottom)
    if a is None or b is None or a == b:
        return None
    graph.add_edge(a, b, [graph.nodes[a]["span"], graph.nodes[b]["span"]])
    graph.edges[graph.next_edge - 1]["lift"] = True
    return a, b


def drop_short_dead_ends(grid, graph, protect, shortest):
    """Takes off branches that lead nowhere and are shorter than `shortest`
    yards (nooks, alcoves), again and again, so a twig on a twig goes too.
    Longer branches (a tunnel to a side valley, a cave gallery) stay."""
    changed = True
    while changed:
        changed = False
        for node in list(graph.nodes):
            if node in protect or node not in graph.nodes:
                continue
            keys = graph.edges_of(node)
            if len(keys) != 1:
                continue
            edge = graph.edges[keys[0]]
            if edge["a"] == edge["b"] or edge.get("lift"):
                continue
            if path_length(grid, edge["path"]) < shortest:
                del graph.edges[keys[0]]
                del graph.nodes[node]
                changed = True
        if changed:
            prune(grid, graph, 0.0, protect)


def keep_reached(graph, starts):
    """Drops every node and edge that cannot be reached from `starts`."""
    seen, stack = set(starts), list(starts)
    while stack:
        node = stack.pop()
        for key in graph.edges_of(node):
            e = graph.edges[key]
            for other in (e["a"], e["b"]):
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
    for key in [k for k, e in graph.edges.items() if e["a"] not in seen]:
        del graph.edges[key]
    for node in [n for n in graph.nodes if n not in seen]:
        del graph.nodes[node]


def trail_check(region, points, connections):
    """How much of the recorded walking the computed place covers: the share
    of trail samples within 5 yards of one of its connections (in the map's
    plane; samples have no height). A check only: trails do not shape the
    place."""
    samples = [s["w"] for t in trails.for_map(region["map"]) for s in t["samples"] if s["w"]]
    if not samples:
        return None
    segments = [(points[a]["world"], points[b]["world"]) for a, b in connections]
    near = 0
    for x, y in samples:
        for (ax, ay, _), (bx, by, _) in segments:
            dx, dy = bx - ax, by - ay
            length2 = dx * dx + dy * dy
            t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / length2))
            if math.hypot(x - ax - t * dx, y - ay - t * dy) <= 5:
                near += 1
                break
    return {"samples": len(samples), "near": near}


def near_models(grid, reach):
    """Spans on a model's (WMO's) floor, or within `reach` yards of one
    along the floor."""
    import collections
    steps = int(reach / grid.cell)
    depth = np.full(len(grid), -1, np.int64)
    queue = collections.deque()
    for span in np.nonzero(grid.source == 2)[0]:
        depth[span] = 0
        queue.append(span)
    while queue:
        span = queue.popleft()
        if depth[span] >= steps:
            continue
        for other in grid.n[span]:
            if other >= 0 and depth[other] < 0:
                depth[other] = depth[span] + 1
                queue.append(other)
    return depth >= 0


class Prepared:
    """What building the place starts from: the region's floors
    thinned to centre lines and traced into a graph, with its lifts and ways
    out joined and only what can be reached from the biggest floor kept."""


def prepare(region_name, fill=80.0, smallest=500.0, dry=False):
    """`dry` leaves out the floor under water (canals, pools) before
    thinning, so the passages beside it are passages of their own."""
    region = regions.REGIONS[region_name]
    base = navgrid.load(region_name)
    labels = base.components()
    sizes = np.bincount(labels)
    pieces = [(p, int(n)) for p, n in enumerate(sizes) if n * base.cell ** 2 >= smallest]
    mask = np.isin(labels, [p for p, _ in pieces])
    if region.get("terrain") == "approach":
        # Only the way up to the models: ground and props within `approach`
        # yards (along the floor) of a model's floor, and the models' floor.
        mask &= near_models(base, region.get("approach", 30.0))
    wet = navgrid.water(base, region_name) if dry else np.zeros(len(base), bool)
    mask &= ~wet
    print("%d walkable spans, %d in %d pieces of %d square yards or more%s" % (
        len(base), mask.sum(), len(pieces), smallest,
        ", %d under water left out" % wet.sum() if dry else ""), file=sys.stderr)
    grid = Work(base)
    mask = fill_holes(grid, mask, labels, pieces, most=fill)
    labels = np.concatenate([labels, getattr(grid, "added_piece", np.zeros(0, np.int64))])
    grid.dist = distance_field(grid, mask)
    skeleton, ring = thin(grid, mask)
    print("centre lines: %d spans" % skeleton.sum(), file=sys.stderr)
    graph = trace(grid, skeleton, ring)
    print("traced: %d nodes, %d edges" % (len(graph.nodes), len(graph.edges)), file=sys.stderr)

    protect, lifts = set(), []
    for at in region.get("lifts", []):
        joined = add_lift(grid, graph, skeleton, mask, labels, sizes, at, region)
        if joined is None:
            print("lift at %s: no two floors to join" % (at,), file=sys.stderr)
            continue
        protect.update(joined)
        lifts.append(joined)
    # The place is what can be reached from the biggest floor, walking or by lift.
    # (Measured on what is left of each piece, so a hillside cut down to the
    # way into a cave does not count for all of the hill.)
    left = np.bincount(labels[:len(base)][mask[:len(base)]], minlength=len(sizes))
    biggest = int(np.argmax(left))
    keep_reached(graph, [n for n, d in graph.nodes.items() if labels[d["span"]] == biggest])
    reached = sorted({int(labels[d["span"]]) for d in graph.nodes.values()})
    # Ways out join the nearest floor of the place (not a roof above it).
    exits = []
    for at in region.get("exits", []):
        x, y = regions.to_world(region["map"], *at)
        spans = [s for s in floors_near(grid, mask, x, y, reach=8.0) if labels[s] in reached]
        spans.sort(key=lambda s: math.hypot(grid.world(s)[0] - x, grid.world(s)[1] - y))
        node = attach(grid, graph, skeleton, labels, spans[0]) if spans else None
        if node is None:
            print("way out at %s: no floor of the place near it" % (at,), file=sys.stderr)
            continue
        protect.add(node)
        exits.append(node)
    print("reached: %d pieces, %d nodes, %d edges" % (len(reached), len(graph.nodes), len(graph.edges)), file=sys.stderr)

    out = Prepared()
    out.region, out.grid, out.mask, out.labels, out.sizes = region, grid, mask, labels, sizes
    out.skeleton, out.ring, out.graph = skeleton, ring, graph
    out.protect, out.lifts, out.exits, out.reached = protect, lifts, exits, reached
    out.wet = np.concatenate([wet, np.zeros(len(grid) - len(wet), bool)])
    return out


def build(region_name, keep="core", spur=1.5, margin=1.0, merge=1.0, fill=80.0, close=2.5, smallest=500.0):
    p = prepare(region_name, fill, smallest)
    region, grid, mask, labels = p.region, p.grid, p.mask, p.labels
    skeleton, graph, protect, exits, reached = p.skeleton, p.graph, p.protect, p.exits, p.reached

    prune(grid, graph, spur, protect)
    merge_junctions(grid, graph, merge, protect=protect)
    prune(grid, graph, spur, protect)
    if keep == "core":
        drop_dead_ends(graph, protect)
    elif keep == "long":
        drop_short_dead_ends(grid, graph, protect, 25.0)
    elif keep != "all":
        raise SystemExit("keep= is core, long or all")
    prune(grid, graph, spur, protect)
    merge_junctions(grid, graph, merge, protect=protect)
    prune(grid, graph, spur, protect)
    print("kept (%s): %d nodes, %d edges" % (keep, len(graph.nodes), len(graph.edges)), file=sys.stderr)

    # Points: every node, then the bends each edge needs.
    points, index_of = [], {}

    def point(span, kind):
        if span not in index_of:
            x, y, z = grid.world(span)
            mx, my = regions.to_map(region["map"], x, y)
            index_of[span] = len(points)
            points.append({"span": int(span), "world": [round(x, 2), round(y, 2), round(z, 2)],
                           "at": [round(mx, 2), round(my, 2)], "kind": kind,
                           "clearance": round(clearance(grid, span), 1), "piece": int(labels[span])})
        return index_of[span]

    for node in graph.nodes.values():
        point(node["span"], "node")
    connections, lift_pairs = [], []
    # The margin in distance field units (2 per cell, from the eroded edge).
    units = max(0.0, margin - 0.5) * 2 / grid.cell
    for edge in graph.edges.values():
        a, b = graph.nodes[edge["a"]]["span"], graph.nodes[edge["b"]]["span"]
        if edge.get("lift"):
            lift_pairs.append((a, b))
            continue
        path = [a] + edge["path"][1:-1] + [b]
        chain = [point(path[i], "bend") for i in straighten(grid, mask, path, units)]
        for i in range(len(chain) - 1):
            if chain[i] != chain[i + 1]:
                connections.append([chain[i], chain[i + 1]])
    fixed = {index_of[graph.nodes[n]["span"]] for n in protect if n in graph.nodes}
    points, connections, remap = merge_close(points, connections, close, fixed)
    lifts_out = [[remap[index_of[a]], remap[index_of[b]]] for a, b in lift_pairs]
    connections += lifts_out
    exits_out = sorted({remap[index_of[graph.nodes[n]["span"]]] for n in exits if n in graph.nodes})
    degree = {}
    for a, b in connections:
        degree[a] = degree.get(a, 0) + 1
        degree[b] = degree.get(b, 0) + 1
    for i, p in enumerate(points):
        d = degree.get(i, 0)
        p["kind"] = "junction" if d >= 3 else ("end" if d <= 1 else "bend")
    for i in exits_out:
        points[i]["kind"] = "entrance"
    for a, b in lifts_out:
        points[a]["lift"] = points[b]["lift"] = True
    centre = [[round(v, 2) for v in regions.to_map(region["map"], *grid.world(s)[:2])]
              for s in np.nonzero(skeleton)[0] if labels[s] in reached]
    check = trail_check(region, points, connections)
    result = {"region": region_name, "map": region["map"], "name": regions.name(region),
              "settings": {"keep": keep, "spur": spur, "margin": margin, "merge": merge, "fill": fill,
                           "close": close, "smallest": smallest},
              "points": points, "connections": connections, "lifts": lifts_out, "exits": exits_out,
              "centre": centre, "pieces": reached, "check": check}
    with open(os.path.join(CACHE, region_name + ".graph.json"), "w") as out:
        json.dump(result, out)
    kinds = {}
    for p in points:
        kinds[p["kind"]] = kinds.get(p["kind"], 0) + 1
    print("place: %d points (%s), %d connections, %d lifts" % (
        len(points), ", ".join("%d %s" % (n, k) for k, n in sorted(kinds.items())), len(connections),
        len(lifts_out)), file=sys.stderr)
    if check:
        print("check: %d of %d trail samples (%.0f%%) are within 5 yd of the place" % (
            check["near"], check["samples"], check["near"] * 100 / check["samples"]), file=sys.stderr)
    return result


def lua(result):
    lines = ['{ place = "%s", name = "%s", map = %d,' % (result["region"], result["name"], result["map"]),
             "  points = {"]
    for i, p in enumerate(result["points"]):
        kind = ' kind = "entrance",' if p["kind"] == "entrance" else ""
        lines.append("      { at = { %.2f, %.2f },%s }, -- %d %s%s, height %.0f" % (
            p["at"][0], p["at"][1], kind, i + 1, p["kind"], " (lift)" if p.get("lift") else "", p["world"][2]))
    lines.append("  },")
    lines.append("  connections = {")
    row = []
    lifts = [tuple(c) for c in result.get("lifts", [])]
    for a, b in result["connections"]:
        if (a, b) in lifts:
            continue
        row.append("{ %d, %d }," % (a + 1, b + 1))
        if len(row) == 8:
            lines.append("      " + " ".join(row))
            row = []
    if row:
        lines.append("      " + " ".join(row))
    for a, b in lifts:
        lines.append("      { %d, %d }, -- lift" % (a + 1, b + 1))
    lines.append("  },")
    lines.append("},")
    return "\n".join(lines)


def main():
    name = "undercity"
    settings = {}
    for item in sys.argv[1:]:
        if "=" in item:
            key, value = item.split("=", 1)
            settings[key] = value if key == "keep" else float(value)
        else:
            name = item
    settings.setdefault("keep", regions.REGIONS[name].get("keep", "core"))
    print(lua(build(name, **settings)))


if __name__ == "__main__":
    main()
