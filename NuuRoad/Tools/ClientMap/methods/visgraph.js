// Corner visibility graph: the router the addon would run (methods/visgraph.py
// builds the data, and its Router class is this, line for line). Plain loops
// over arrays, so it carries over to Lua 5.1: no libraries, nothing kept
// between calls but the place as loaded.
//
// The place, per layer (a layer is flat on the map: no two of its floors
// share a spot): the walls of its floor (what a route may use: corners stand
// off them, and lines between corners are tested on them), the walls of its
// extent (all its floor, steep and narrow parts too: says which layer a spot
// is on, and how to walk from it onto the floor) with the seams where it meets
// another layer, and which wall points are corners. Then doors (a point either
// side of a seam), lifts, and the links between corners that see each other.
//
// A route: the start and the target placed on a layer (the one the player is
// tracked on, and the one the guide says the target is on, when known: ctx.layers
// = [start layer, target layer]; else every layer whose extent has them), each
// joined to up to `ways` points of that layer's floor it can walk to straight,
// those joined to every corner of the layer they can see, then Dijkstra.
(function () {
  "use strict";
  var CELL = 8.0;

  function cross(ax, ay, bx, by) {
    return ax * by - ay * bx;
  }

  function Router(data, yards) {
    this.ky = yards[0];
    this.kx = yards[1];
    this.push = data.push;
    this.snap = data.snap;
    this.keep = data.keep;
    this.reach = data.reach;
    this.ways = data.ways;
    this.floors = [];
    this.extents = [];
    this.seams = [];
    this.nodes = [];
    var L, i, k, most = 0;
    for (L = 0; L < data.layers.length; L++) {
      var layer = data.layers[L];
      var rings = [];
      for (i = 0; i < layer.walls.length; i++) rings.push(this.ring(layer.walls[i]));
      this.floors.push(this.walls(rings));
      var erings = [];
      for (i = 0; i < layer.extent.length; i++) erings.push(this.ring(layer.extent[i]));
      this.extents.push(this.walls(erings));
      var seams = {}, runs = layer.seams;
      for (k = 0; k < runs.length; k += 3) {
        for (i = runs[k] - 1; i < runs[k + 1]; i++) seams[i] = runs[k + 2];
      }
      this.seams.push(seams);
      var count = 0, corners = {};
      for (i = 0; i < layer.corners.length; i++) corners[layer.corners[i]] = true;
      for (var r = 0; r < rings.length; r++) {
        var ring = rings[r], n = ring.length;
        for (i = 0; i < n; i++) {
          count++;
          if (corners[count]) {
            var p = this.pushed(ring[(i - 1 + n) % n], ring[i], ring[(i + 1) % n]);
            this.nodes.push([L, p[0], p[1]]);
          }
        }
      }
    }
    var pairs = [], kinds = ["doors", "lifts"];
    for (k = 0; k < kinds.length; k++) {
      var list = data[kinds[k]] || [];
      for (i = 0; i < list.length; i++) {
        var d = list[i], a = this.nodes.length;
        this.nodes.push([d[0], d[1] * this.ky, d[2] * this.kx]);
        this.nodes.push([d[3], d[4] * this.ky, d[5] * this.kx]);
        pairs.push([a, a + 1]);
      }
    }
    this.adj = [];
    for (i = 0; i < this.nodes.length; i++) this.adj.push([]);
    var links = data.links;
    for (i = 0; i < links.length; i += 2) pairs.push([links[i] - 1, links[i + 1] - 1]);
    for (i = 0; i < pairs.length; i++) {
      var u = pairs[i][0], v = pairs[i][1];
      var w = Math.hypot(this.nodes[u][1] - this.nodes[v][1], this.nodes[u][2] - this.nodes[v][2]);
      this.adj[u].push([v, w]);
      this.adj[v].push([u, w]);
    }
    var all = this.floors.concat(this.extents);
    for (i = 0; i < all.length; i++) most = Math.max(most, all[i].sides.length);
    this.stamp = 0;
    this.mark = new Array(most).fill(0);
  }

  Router.prototype.ring = function (flat) {
    var out = [];
    for (var i = 0; i < flat.length; i += 2) out.push([flat[i] * this.ky, flat[i + 1] * this.kx]);
    return out;
  };

  Router.prototype.walls = function (rings) {
    var sides = [];
    for (var r = 0; r < rings.length; r++) {
      var ring = rings[r];
      for (var i = 0; i < ring.length; i++) {
        var a = ring[i], b = ring[(i + 1) % ring.length];
        sides.push([a[0], a[1], b[0], b[1]]);
      }
    }
    return { sides: sides, grid: this.bucket(sides) };
  };

  // A corner `push` yards off both walls that meet at it (never more than
  // three times `push` from it); the tip of a wall with no thickness, `push`
  // yards on past its end.
  Router.prototype.pushed = function (a, v, b) {
    var e1x = v[0] - a[0], e1y = v[1] - a[1];
    var e2x = b[0] - v[0], e2y = b[1] - v[1];
    var l1 = Math.hypot(e1x, e1y), l2 = Math.hypot(e2x, e2y);
    var n1x = -e1y / l1, n1y = e1x / l1;
    var n2x = -e2y / l2, n2y = e2x / l2;
    var bend = 1 + n1x * n2x + n1y * n2y;
    if (bend < 1e-6) return [v[0] + e1x / l1 * this.push, v[1] + e1y / l1 * this.push];
    var k = this.push / bend;
    var ox = (n1x + n2x) * k, oy = (n1y + n2y) * k;
    var L = Math.hypot(ox, oy);
    if (L > 3 * this.push) {
      ox = ox * 3 * this.push / L;
      oy = oy * 3 * this.push / L;
    }
    return [v[0] + ox, v[1] + oy];
  };

  // Which sides cross each cell of an 8 yd grid, and by row which cells have any.
  Router.prototype.bucket = function (sides) {
    var g = { x: 0, y: 0, cells: new Map(), rows: new Map() };
    if (!sides.length) return g;
    var i, x = Infinity, y = Infinity;
    for (i = 0; i < sides.length; i++) {
      x = Math.min(x, sides[i][0], sides[i][2]);
      y = Math.min(y, sides[i][1], sides[i][3]);
    }
    g.x = x;
    g.y = y;
    for (i = 0; i < sides.length; i++) {
      var s = sides[i], keys = this.cells(g, s[0], s[1], s[2], s[3]);
      for (var j = 0; j < keys.length; j++) {
        var key = keys[j];
        if (!g.cells.has(key)) {
          g.cells.set(key, []);
          var row = Math.floor(key / 65536);
          if (!g.rows.has(row)) g.rows.set(row, []);
          g.rows.get(row).push(key % 65536);
        }
        g.cells.get(key).push(i);
      }
    }
    g.rows.forEach(function (list) { list.sort(function (p, q) { return p - q; }); });
    return g;
  };

  // The grid cells a segment passes through: row by row, the cells between
  // where it enters the row and where it leaves it.
  Router.prototype.cells = function (g, x1, y1, x2, y2) {
    var out = [];
    var ya = Math.min(y1, y2), yb = Math.max(y1, y2);
    var r0 = Math.max(0, Math.floor((ya - g.y) / CELL)), r1 = Math.floor((yb - g.y) / CELL);
    for (var r = r0; r <= r1; r++) {
      var lo = Math.max(ya, g.y + r * CELL), hi = Math.min(yb, g.y + (r + 1) * CELL);
      var xa, xb;
      if (y2 === y1) {
        xa = x1;
        xb = x2;
      } else {
        xa = x1 + (x2 - x1) * (lo - y1) / (y2 - y1);
        xb = x1 + (x2 - x1) * (hi - y1) / (y2 - y1);
      }
      var c0 = Math.max(0, Math.floor((Math.min(xa, xb) - g.x) / CELL));
      var c1 = Math.floor((Math.max(xa, xb) - g.x) / CELL);
      for (var c = c0; c <= c1; c++) out.push(r * 65536 + c);
    }
    return out;
  };

  // Whether a to b crosses none of `walls` (touching one counts).
  Router.prototype.sees = function (walls, ax, ay, bx, by) {
    var sides = walls.sides, g = walls.grid;
    this.stamp++;
    var keys = this.cells(g, ax, ay, bx, by);
    for (var k = 0; k < keys.length; k++) {
      var list = g.cells.get(keys[k]);
      if (!list) continue;
      for (var j = 0; j < list.length; j++) {
        var i = list[j];
        if (this.mark[i] === this.stamp) continue;
        this.mark[i] = this.stamp;
        var s = sides[i];
        var d1 = cross(bx - ax, by - ay, s[0] - ax, s[1] - ay);
        var d2 = cross(bx - ax, by - ay, s[2] - ax, s[3] - ay);
        if ((d1 > 0 && d2 > 0) || (d1 < 0 && d2 < 0)) continue;
        var d3 = cross(s[2] - s[0], s[3] - s[1], ax - s[0], ay - s[1]);
        var d4 = cross(s[2] - s[0], s[3] - s[1], bx - s[0], by - s[1]);
        if ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) return false;
      }
    }
    return true;
  };

  // Whether (x, y) is inside `walls`: a ray east from it crosses them an odd
  // number of times.
  Router.prototype.inside = function (walls, x, y) {
    var sides = walls.sides, g = walls.grid;
    var r = Math.floor((y - g.y) / CELL), c = Math.floor((x - g.x) / CELL);
    this.stamp++;
    var odd = false, row = g.rows.get(r);
    if (!row) return false;
    for (var k = 0; k < row.length; k++) {
      if (row[k] < c) continue;
      var list = g.cells.get(r * 65536 + row[k]);
      for (var j = 0; j < list.length; j++) {
        var i = list[j];
        if (this.mark[i] === this.stamp) continue;
        this.mark[i] = this.stamp;
        var s = sides[i];
        if ((s[1] > y) !== (s[3] > y) && x < s[0] + (y - s[1]) * (s[2] - s[0]) / (s[3] - s[1])) odd = !odd;
      }
    }
    return odd;
  };

  function byNearest(p, q) {
    for (var i = 0; i < 4; i++) {
      if (p[i] !== q[i]) return p[i] < q[i] ? -1 : 1;
    }
    return 0;
  }

  // [[yards, x, y, side]]: the nearest point of each of `walls` within
  // `reach` yards of (x, y), nearest first.
  Router.prototype.near = function (walls, x, y, reach) {
    var sides = walls.sides, out = [];
    for (var i = 0; i < sides.length; i++) {
      var s = sides[i];
      if (Math.min(s[0], s[2]) > x + reach || Math.max(s[0], s[2]) < x - reach ||
          Math.min(s[1], s[3]) > y + reach || Math.max(s[1], s[3]) < y - reach) continue;
      var dx = s[2] - s[0], dy = s[3] - s[1];
      var L2 = dx * dx + dy * dy;
      var t = L2 === 0 ? 0 : Math.max(0, Math.min(1, ((x - s[0]) * dx + (y - s[1]) * dy) / L2));
      var px = s[0] + t * dx, py = s[1] + t * dy;
      var d = Math.hypot(x - px, y - py);
      if (d <= reach) out.push([d, px, py, i]);
    }
    out.sort(byNearest);
    return out;
  };

  // The point just inside `walls` beside their point (px, py) (on side i),
  // `d` yards from (x, y): on past the wall from (x, y), else to the wall's
  // left (the floor is on the left of every wall); null if neither is inside.
  Router.prototype.onto = function (walls, x, y, d, px, py, i) {
    var s = walls.sides[i];
    var dx = s[2] - s[0], dy = s[3] - s[1];
    var length = Math.hypot(dx, dy), steps = [0.15, 0.3, 0.6];
    for (var k = 0; k < steps.length; k++) {
      var step = steps[k], qx, qy;
      if (d > 1e-6) {
        qx = px + (px - x) / d * step;
        qy = py + (py - y) / d * step;
        if (this.inside(walls, qx, qy)) return [qx, qy];
      }
      if (length > 0) {
        qx = px - dy / length * step;
        qy = py + dx / length * step;
        if (this.inside(walls, qx, qy)) return [qx, qy];
      }
    }
    return null;
  };

  // Where a player at (x, y), on layer L's extent, steps onto its floor:
  // [[x, y]] if on it, else up to `ways` points of the floor within `reach`
  // yards a straight line reaches without leaving the extent.
  Router.prototype.approach = function (L, x, y, reach) {
    var floor = this.floors[L];
    if (this.inside(floor, x, y)) return [[x, y]];
    var found = this.near(floor, x, y, reach), count = found.length, k;
    for (k = 0; k < count; k++) {
      var i = found[k][3], x1 = floor.sides[i][0], y1 = floor.sides[i][1];
      var e = Math.hypot(x1 - x, y1 - y);
      if (e <= reach) found.push([e, x1, y1, i]);
    }
    found.sort(byNearest);
    var out = [], used = {};
    for (k = 0; k < found.length; k++) {
      var f = found[k];
      if (used[f[3]]) continue;
      var q = this.onto(floor, x, y, f[0], f[1], f[2], f[3]);
      if (q && this.sees(this.extents[L], x, y, q[0], q[1])) {
        out.push(q);
        used[f[3]] = true;
        if (out.length === this.ways) break;
      }
    }
    return out;
  };

  // (x, y) if layer L's extent has it, else the nearest point just inside it
  // within `reach` yards, else null.
  Router.prototype.enter = function (L, x, y, reach) {
    var walls = this.extents[L];
    if (this.inside(walls, x, y)) return [x, y];
    var found = this.near(walls, x, y, reach);
    for (var k = 0; k < found.length; k++) {
      var e = this.onto(walls, x, y, found[k][0], found[k][1], found[k][2], found[k][3]);
      if (e) return e;
    }
    return null;
  };

  // [[layer, x, y, floor points]]: the layers (x, y) may be on, each with the
  // point of its extent a route starts or ends at and where that steps onto
  // the floor. With `want`, only that layer if it can.
  Router.prototype.place = function (x, y, want) {
    var out = [], L, e, qs;
    var layers = [];
    if (want !== null && want !== undefined) layers.push(want);
    else for (L = 0; L < this.extents.length; L++) layers.push(L);
    for (var k = 0; k < layers.length; k++) {
      L = layers[k];
      e = this.enter(L, x, y, this.keep);
      if (e) {
        qs = this.approach(L, e[0], e[1], this.reach);
        if (qs.length) out.push([L, e[0], e[1], qs]);
      }
    }
    if (out.length) return out;
    if (want !== null && want !== undefined) return this.place(x, y, null);
    var best = null;
    for (L = 0; L < this.extents.length; L++) {
      e = this.enter(L, x, y, this.snap);
      qs = e ? this.approach(L, e[0], e[1], this.reach) : [];
      if (qs.length && (best === null || Math.hypot(e[0] - x, e[1] - y) < best[0])) {
        best = [Math.hypot(e[0] - x, e[1] - y), L, e[0], e[1], qs];
      }
    }
    return best ? [best.slice(1)] : [];
  };

  // The layer a player is on who was on layer L at map % `was` and is now at
  // map % `now` (L null: not known yet). A move across a seam of L's extent is
  // onto the layer beyond it; one across a wall of it (a drop) is onto a layer
  // whose extent has them, if L's does not and they are more than `keep`
  // yards off it. Otherwise they stay on L.
  Router.prototype.track = function (L, was, now) {
    var x = now[0] * this.ky, y = now[1] * this.kx, M;
    if (L === null || L === undefined) {
      for (M = 0; M < this.extents.length; M++) if (this.inside(this.extents[M], x, y)) return M;
      var found = this.place(x, y, null);
      return found.length ? found[0][0] : null;
    }
    var ax = was[0] * this.ky, ay = was[1] * this.kx;
    var sides = this.extents[L].sides, g = this.extents[L].grid;
    var first = Infinity, beyond = null;
    this.stamp++;
    var keys = this.cells(g, ax, ay, x, y);
    for (var k = 0; k < keys.length; k++) {
      var list = g.cells.get(keys[k]);
      if (!list) continue;
      for (var j = 0; j < list.length; j++) {
        var i = list[j];
        if (this.mark[i] === this.stamp) continue;
        this.mark[i] = this.stamp;
        var s = sides[i];
        var d1 = cross(x - ax, y - ay, s[0] - ax, s[1] - ay);
        var d2 = cross(x - ax, y - ay, s[2] - ax, s[3] - ay);
        var d3 = cross(s[2] - s[0], s[3] - s[1], ax - s[0], ay - s[1]);
        var d4 = cross(s[2] - s[0], s[3] - s[1], x - s[0], y - s[1]);
        if ((d1 > 0) !== (d2 > 0) && (d3 > 0) !== (d4 > 0)) {
          var t = d3 / (d3 - d4);
          if (t < first) {
            first = t;
            beyond = this.seams[L][i] !== undefined ? this.seams[L][i] : -1;
          }
        }
      }
    }
    if (beyond === null) return L;
    if (beyond >= 0) return beyond;
    if (this.inside(this.extents[L], x, y) || this.near(this.extents[L], x, y, this.keep).length) return L;
    for (M = 0; M < this.extents.length; M++) {
      if (M !== L && this.inside(this.extents[M], x, y)) return M;
    }
    return L;
  };

  // start and target in map %; the route in map %, or null. `layers` is the
  // layer the player is on and the layer the target is on, either null if
  // not known.
  Router.prototype.route = function (start, target, layers) {
    var sx = start[0] * this.ky, sy = start[1] * this.kx;
    var tx = target[0] * this.ky, ty = target[1] * this.kx;
    var S = this.place(sx, sy, layers ? layers[0] : null);
    var T = this.place(tx, ty, layers ? layers[1] : null);
    if (!S.length || !T.length) return null;
    var best = Infinity, bestPath = null, a, b, j, m, d, i;
    // Straight there on a layer both are on: across its floor, or, a short
    // way, across its extent.
    for (a = 0; a < S.length; a++) {
      for (b = 0; b < T.length; b++) {
        var s = S[a], t = T[b];
        if (s[0] !== t[0]) continue;
        d = Math.hypot(s[1] - t[1], s[2] - t[2]);
        if (d <= this.reach && this.sees(this.extents[s[0]], s[1], s[2], t[1], t[2])) {
          d += Math.hypot(sx - s[1], sy - s[2]) + Math.hypot(t[1] - tx, t[2] - ty);
          if (d < best) {
            best = d;
            bestPath = [[s[1], s[2]], [t[1], t[2]]];
          }
        }
        for (j = 0; j < s[3].length; j++) {
          for (m = 0; m < t[3].length; m++) {
            var q = s[3][j], r = t[3][m];
            if (this.sees(this.floors[s[0]], q[0], q[1], r[0], r[1])) {
              d = Math.hypot(sx - s[1], sy - s[2]) + Math.hypot(s[1] - q[0], s[2] - q[1]) +
                  Math.hypot(q[0] - r[0], q[1] - r[1]) + Math.hypot(r[0] - t[1], r[1] - t[2]) +
                  Math.hypot(t[1] - tx, t[2] - ty);
              if (d < best) {
                best = d;
                bestPath = [[s[1], s[2]], q, r, [t[1], t[2]]];
              }
            }
          }
        }
      }
    }
    // Otherwise from where each gets onto the floor to the corners it sees,
    // and Dijkstra between.
    var n = this.nodes.length, node;
    var dist = new Array(n).fill(Infinity), prev = new Array(n).fill(-1), head = new Array(n).fill(null);
    var tail = new Array(n).fill(Infinity), foot = new Array(n).fill(null);
    for (a = 0; a < S.length; a++) {
      for (j = 0; j < S[a][3].length; j++) {
        var qs = S[a][3][j];
        var lead = Math.hypot(sx - S[a][1], sy - S[a][2]) + Math.hypot(S[a][1] - qs[0], S[a][2] - qs[1]);
        for (i = 0; i < n; i++) {
          node = this.nodes[i];
          if (node[0] === S[a][0] && this.sees(this.floors[node[0]], qs[0], qs[1], node[1], node[2])) {
            d = lead + Math.hypot(node[1] - qs[0], node[2] - qs[1]);
            if (d < dist[i]) {
              dist[i] = d;
              head[i] = [a, j];
            }
          }
        }
      }
    }
    for (b = 0; b < T.length; b++) {
      for (j = 0; j < T[b][3].length; j++) {
        var rs = T[b][3][j];
        var last = Math.hypot(T[b][1] - tx, T[b][2] - ty) + Math.hypot(rs[0] - T[b][1], rs[1] - T[b][2]);
        for (i = 0; i < n; i++) {
          node = this.nodes[i];
          if (node[0] === T[b][0] && this.sees(this.floors[node[0]], node[1], node[2], rs[0], rs[1])) {
            d = last + Math.hypot(node[1] - rs[0], node[2] - rs[1]);
            if (d < tail[i]) {
              tail[i] = d;
              foot[i] = [b, j];
            }
          }
        }
      }
    }
    var done = new Array(n).fill(false), end = -1;
    for (;;) {
      var u = -1;
      for (i = 0; i < n; i++) {
        if (!done[i] && dist[i] < Infinity && (u < 0 || dist[i] < dist[u])) u = i;
      }
      if (u < 0 || dist[u] >= best) break;
      done[u] = true;
      if (dist[u] + tail[u] < best) {
        best = dist[u] + tail[u];
        end = u;
      }
      var adj = this.adj[u];
      for (j = 0; j < adj.length; j++) {
        var v = adj[j][0], w = adj[j][1];
        if (dist[u] + w < dist[v]) {
          dist[v] = dist[u] + w;
          prev[v] = u;
          head[v] = head[u];
        }
      }
    }
    if (end >= 0) {
      var chain = [];
      for (u = end; u >= 0; u = prev[u]) chain.push([this.nodes[u][1], this.nodes[u][2]]);
      chain.reverse();
      var hs = S[head[end][0]], ft = T[foot[end][0]];
      bestPath = [[hs[1], hs[2]], hs[3][head[end][1]]].concat(chain, [ft[3][foot[end][1]], [ft[1], ft[2]]]);
    }
    if (bestPath === null) return null;
    var points = [[sx, sy]].concat(bestPath, [[tx, ty]]), out = [];
    for (i = 0; i < points.length; i++) {
      var p = points[i], o = out[out.length - 1];
      if (!o || Math.hypot(p[0] - o[0], p[1] - o[1]) > 1e-6) out.push(p);
    }
    var self = this;
    return out.map(function (p) { return [p[0] / self.ky, p[1] / self.kx]; });
  };

  var built = new WeakMap();

  if (typeof NuuRoadViewer === "undefined") return;
  NuuRoadViewer.method("visgraph", {
    route: function (data, start, target, ctx) {
      var router = built.get(data);
      if (!router) {
        router = new Router(data, ctx.yards);
        built.set(data, router);
      }
      var points = router.route(start, target, ctx.layers || null);
      if (!points) return null;
      return { points: points, note: (points.length - 2) + " bends" };
    },
  });
})();
