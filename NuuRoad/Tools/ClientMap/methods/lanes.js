// Wall-hugging lanes: the router the addon would run (methods/lanes.py builds
// the data). Written as plain loops over arrays so it carries over to Lua 5.1
// line for line: no closures kept between calls, no libraries.
//
// The place: rooms (outline loops and small pillars as circles, in map %),
// doorways (the rooms either side, where to pass), and lanes (short lines
// across a room from one doorway to another, a couple of yards off the
// walls). A route: the room of the start and of the target from the outlines
// (a map position alone; the addon keeps the player's room as a state changed
// only by crossing a doorway, passed here as ctx.room), the start joined to
// every lane point of its room it can see without crossing the room's
// outline, the same for the target, then Dijkstra over the lanes and the
// doorways.
//
// The cheaper variant (data.offset set, no lanes shipped) makes each room's
// lanes once, when the place is first used: along the room's outline, pushed
// in by the room's own offset.
(function () {
  "use strict";
  var JOIN_FREE = 4.0;   // yd: a join this short costs its length
  var JOIN_OPEN = 2.0;   // beyond it, each yard costs 1 + JOIN_OPEN * the room's open share
  var NEAR_ROOM = 10.0;  // yd: a spot outside every room is taken into the nearest this close
  var STRETCH = 1.25;    // the offset variant: a line round a room at most this much longer than straight
  var BUMP = 2.0;
  var PULL = 1.5;        // yd: a point this close to the line past it is left out of a route
  var PULL_AHEAD = 8;    // how many points on a route is pulled straight at a time        // yd: the offset variant: a bump in the wall under this is not followed

  // ---- Geometry, in yards -------------------------------------------------

  function cross(ax, ay, bx, by, cx, cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }

  // Whether segments p-q and a-b cross (touching at an end does not count).
  function crosses(px, py, qx, qy, ax, ay, bx, by) {
    var d1 = cross(px, py, qx, qy, ax, ay), d2 = cross(px, py, qx, qy, bx, by);
    if ((d1 > 0 && d2 > 0) || (d1 < 0 && d2 < 0)) return false;
    var d3 = cross(ax, ay, bx, by, px, py), d4 = cross(ax, ay, bx, by, qx, qy);
    if ((d3 > 0 && d4 > 0) || (d3 < 0 && d4 < 0)) return false;
    if (d1 === 0 && d2 === 0) return false;
    return true;
  }

  // Yards from (x, y) to the segment a-b, and the nearest point on it.
  function toSegment(x, y, ax, ay, bx, by) {
    var dx = bx - ax, dy = by - ay, l = dx * dx + dy * dy, t = 0;
    if (l > 0) t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / l));
    var fx = ax + t * dx, fy = ay + t * dy;
    return [Math.hypot(x - fx, y - fy), fx, fy];
  }

  // ---- The place, read once ------------------------------------------------

  function prepare(data) {
    if (data._lanes) return data._lanes;
    var t0 = Date.now();
    var kx = data.yards[0], ky = data.yards[1];
    var P = { rooms: [], doors: [], nodes: [], adj: [], roomNodes: [], tag: [] };
    var r, i, j, k;
    for (r = 0; r < data.rooms.length; r++) {
      var src = data.rooms[r], room = { loops: [], pillars: [], open: src.open || 0, box: [1e9, 1e9, -1e9, -1e9] };
      var best = -1, bestArea = 0;
      for (i = 0; i < src.outline.length; i++) {
        var flat = src.outline[i], loop = [], area = 0;
        for (j = 0; j < flat.length; j += 2) {
          var x = flat[j] * kx, y = flat[j + 1] * ky;
          loop.push(x, y);
          if (x < room.box[0]) room.box[0] = x;
          if (y < room.box[1]) room.box[1] = y;
          if (x > room.box[2]) room.box[2] = x;
          if (y > room.box[3]) room.box[3] = y;
        }
        for (j = 0; j < loop.length; j += 2) {
          k = (j + 2) % loop.length;
          area += loop[j] * loop[k + 1] - loop[k] * loop[j + 1];
        }
        if (Math.abs(area) > bestArea) { bestArea = Math.abs(area); best = i; }
        room.loops.push(loop);
        loop.area = area / 2;
      }
      room.outer = best;
      for (i = 0; i < (src.pillars || []).length; i += 3)
        room.pillars.push(src.pillars[i] * kx, src.pillars[i + 1] * ky, src.pillars[i + 2]);
      room.offset = src.offset;
      P.rooms.push(room);
      P.roomNodes.push([]);
    }
    // A node's tag: its room, or -(d + 1) for doorway d (in both its rooms).
    function node(x, y, tag) {
      P.nodes.push([x, y]);
      P.tag.push(tag);
      P.adj.push([]);
      return P.nodes.length - 1;
    }
    function link(a, b) {
      var w = Math.hypot(P.nodes[a][0] - P.nodes[b][0], P.nodes[a][1] - P.nodes[b][1]);
      P.adj[a].push(b, w);
      P.adj[b].push(a, w);
    }
    var ends = [];
    for (i = 0; i < data.doors.length; i++) {
      var d = data.doors[i];
      var n = node(d.at[0] * kx, d.at[1] * ky, -(i + 1));
      P.doors.push({ rooms: d.rooms, node: n, line: [d.line[0] * kx, d.line[1] * ky, d.line[2] * kx, d.line[3] * ky] });
      for (j = 0; j < d.rooms.length; j++) P.roomNodes[d.rooms[j]].push(n);
      ends.push([]);
    }
    var lanes = data.lanes;
    if (data.offset) lanes = offsetLanes(P, data);
    for (i = 0; i < lanes.length; i++) {
      var lane = lanes[i], pts = lane.points, prev = -1, first = -1;
      for (j = 0; j < pts.length; j += 2) {
        var m = node(pts[j] * kx, pts[j + 1] * ky, lane.room);
        P.roomNodes[lane.room].push(m);
        if (prev >= 0) link(prev, m);
        else first = m;
        prev = m;
      }
      ends[lane.from].push(first);
      ends[lane.to].push(prev);
    }
    // Each lane end to its doorway, and the lane ends at one doorway to each other.
    for (i = 0; i < ends.length; i++) {
      for (j = 0; j < ends[i].length; j++) {
        link(P.doors[i].node, ends[i][j]);
        for (k = j + 1; k < ends[i].length; k++) {
          var e1 = P.nodes[ends[i][j]], e2 = P.nodes[ends[i][k]];
          if (Math.hypot(e1[0] - e2[0], e1[1] - e2[1]) <= 3) link(ends[i][j], ends[i][k]);
        }
      }
    }
    P.ms = Date.now() - t0;
    data._lanes = P;
    return P;
  }

  // Whether (x, y) is inside the room (even-odd over its loops).
  function inside(room, x, y) {
    if (x < room.box[0] || x > room.box[2] || y < room.box[1] || y > room.box[3]) return false;
    var c = false;
    for (var i = 0; i < room.loops.length; i++) {
      var L = room.loops[i], n = L.length;
      for (var j = 0, k = n - 2; j < n; k = j, j += 2) {
        if ((L[j + 1] > y) !== (L[k + 1] > y) &&
            x < (L[k] - L[j]) * (y - L[j + 1]) / (L[k + 1] - L[j + 1]) + L[j]) c = !c;
      }
    }
    return c;
  }

  // Whether a straight line from a to b stays in the room: it crosses none
  // of the room's outline and passes by its pillars. The ends are pulled in
  // a little, as lane ends and doorways lie on the outline.
  function clear(room, ax, ay, bx, by) {
    var l = Math.hypot(bx - ax, by - ay);
    if (l < 0.01) return true;
    var s = Math.min(0.3, l / 4) / l;
    var px = ax + (bx - ax) * s, py = ay + (by - ay) * s, qx = bx - (bx - ax) * s, qy = by - (by - ay) * s;
    var i, j, k;
    for (i = 0; i < room.loops.length; i++) {
      var L = room.loops[i], n = L.length;
      for (j = 0, k = n - 2; j < n; k = j, j += 2)
        if (crosses(px, py, qx, qy, L[k], L[k + 1], L[j], L[j + 1])) return false;
    }
    for (i = 0; i < room.pillars.length; i += 3)
      if (toSegment(room.pillars[i], room.pillars[i + 1], px, py, qx, qy)[0] < room.pillars[i + 2]) return false;
    return true;
  }

  // The nearest point of room r to (x, y) a little inside it:
  // [yards away, x, y].
  function into(P, r, x, y) {
    var room = P.rooms[r], best = null, i, j, k;
    if (inside(room, x, y)) return [0, x, y];
    for (i = 0; i < room.loops.length; i++) {
      var L = room.loops[i], n = L.length;
      for (j = 0, k = n - 2; j < n; k = j, j += 2) {
        var f = toSegment(x, y, L[k], L[k + 1], L[j], L[j + 1]);
        if (!best || f[0] < best[0]) best = f;
      }
    }
    for (var step = 0.3; step <= 2.0; step += 0.3) {
      for (var a = 0; a < 16; a++) {
        var tx = best[1] + Math.cos(a * Math.PI / 8) * step, ty = best[2] + Math.sin(a * Math.PI / 8) * step;
        if (inside(room, tx, ty)) return [best[0], tx, ty];
      }
    }
    return best;
  }

  // The rooms a spot may be in: [[room, x, y], ...], the spot itself where a
  // room holds it, else the nearest point of the nearest room within NEAR_ROOM.
  function locate(P, x, y) {
    var out = [], r, best = null;
    for (r = 0; r < P.rooms.length; r++) if (inside(P.rooms[r], x, y)) out.push([r, x, y]);
    if (out.length) return out;
    for (r = 0; r < P.rooms.length; r++) {
      var f = into(P, r, x, y);
      if (f[0] <= NEAR_ROOM && (!best || f[0] < best[0])) best = [f[0], r, f[1], f[2]];
    }
    return best ? [[best[1], best[2], best[3]]] : [];
  }

  // Yards from (x, y) to the nearest edge of the room's outline.
  function depth(room, x, y) {
    var best = 1e18;
    for (var i = 0; i < room.loops.length; i++) {
      var L = room.loops[i], n = L.length;
      for (var j = 0, k = n - 2; j < n; k = j, j += 2)
        best = Math.min(best, toSegment(x, y, L[k], L[k + 1], L[j], L[j + 1])[0]);
    }
    return best;
  }

  // Where floors stack, a spot is in more than one room and a map position
  // cannot say which. The addon knows the player's own room (a state
  // changed only through doorways, ctx.room here) and a guide author can
  // name the target's (`near`, ctx.targetRoom). Otherwise the room the spot
  // lies deepest in is taken: a thing to find stands on open floor more
  // often than at the edge of a room, where another floor's tunnel passes
  // over or under. ctx.pick = "all" keeps every room that holds the spot
  // and lets the shortest route win (tried: worse on the benchmark).
  function settle(P, found, pick) {
    if (found.length < 2 || pick === "all") return found;
    var best = found[0], bestDepth = -1;
    for (var i = 0; i < found.length; i++) {
      var d = depth(P.rooms[found[i][0]], found[i][1], found[i][2]);
      if (d > bestDepth) { bestDepth = d; best = found[i]; }
    }
    return [best];
  }

  function joinCost(room, l) {
    return l + Math.max(0, l - JOIN_FREE) * JOIN_OPEN * room.open;
  }

  // The inside corners of a room's outline (where a wall juts into it),
  // pushed half a yard off the wall: the ways round to a lane from a spot
  // that sees none. Made once a room, when first needed.
  function corners(room) {
    if (room.corners) return room.corners;
    var out = [];
    for (var i = 0; i < room.loops.length; i++) {
      var L = room.loops[i], n = L.length / 2, sign = L.area > 0 ? 1 : -1;
      if (i !== room.outer) sign = -sign;  // a hole's corners jut in the other way
      for (var v = 0; v < n; v++) {
        var h = (v + n - 1) % n, w = (v + 1) % n;
        var ax = L[2 * v] - L[2 * h], ay = L[2 * v + 1] - L[2 * h + 1];
        var bx = L[2 * w] - L[2 * v], by = L[2 * w + 1] - L[2 * v + 1];
        // A right turn when the inside is on the left: the wall juts in here.
        if ((ax * by - ay * bx) * sign >= 0) continue;
        var la = Math.hypot(ax, ay) || 1, lb = Math.hypot(bx, by) || 1;
        var mx = (-ay / la - by / lb) * sign, my = (ax / la + bx / lb) * sign, ml = Math.hypot(mx, my) || 1;
        var x = L[2 * v] + mx / ml * 0.5, y = L[2 * v + 1] + my / ml * 0.5;
        if (inside(room, x, y)) out.push(x, y);
      }
    }
    room.corners = out;
    return out;
  }

  // How a spot in room r joins the lanes: [[node, cost, [x, y, ...] the
  // corners passed on the way], ...]. Every lane point and doorway of the
  // room the spot sees; if it sees none, the way round the room's inside
  // corners to the nearest it can reach.
  function joins(P, r, x, y) {
    var room = P.rooms[r], nodes = P.roomNodes[r], out = [], j, p;
    for (j = 0; j < nodes.length; j++) {
      p = P.nodes[nodes[j]];
      if (clear(room, x, y, p[0], p[1])) out.push([nodes[j], joinCost(room, Math.hypot(p[0] - x, p[1] - y)), []]);
    }
    if (out.length) return out;
    var C = corners(room), m = C.length / 2, dist = [], prev = [], done = [], k;
    for (k = 0; k < m; k++) {
      done.push(false);
      prev.push(-1);
      dist.push(clear(room, x, y, C[2 * k], C[2 * k + 1]) ? Math.hypot(C[2 * k] - x, C[2 * k + 1] - y) : 1e18);
    }
    for (;;) {
      var u = -1;
      for (k = 0; k < m; k++) if (!done[k] && dist[k] < 1e18 && (u < 0 || dist[k] < dist[u])) u = k;
      if (u < 0) return out;
      done[u] = true;
      var ux = C[2 * u], uy = C[2 * u + 1], via = [];
      for (k = u; k >= 0; k = prev[k]) via.unshift(C[2 * k], C[2 * k + 1]);
      for (j = 0; j < nodes.length; j++) {
        p = P.nodes[nodes[j]];
        if (clear(room, ux, uy, p[0], p[1])) out.push([nodes[j], joinCost(room, dist[u] + Math.hypot(p[0] - ux, p[1] - uy)), via]);
      }
      if (out.length) return out;
      for (k = 0; k < m; k++) {
        if (done[k]) continue;
        var d = dist[u] + Math.hypot(C[2 * k] - ux, C[2 * k + 1] - uy);
        if (d < dist[k] && clear(room, ux, uy, C[2 * k], C[2 * k + 1])) { dist[k] = d; prev[k] = u; }
      }
    }
  }

  // ---- The route ----------------------------------------------------------

  function route(data, start, target, ctx) {
    var P = prepare(data);
    var kx = data.yards[0], ky = data.yards[1];
    var sx = start[0] * kx, sy = start[1] * ky, tx = target[0] * kx, ty = target[1] * ky;
    var pick = ctx && ctx.pick;
    var from = ctx && ctx.room != null ? [[ctx.room].concat(into(P, ctx.room, sx, sy).slice(1))] : settle(P, locate(P, sx, sy), pick);
    var to = ctx && ctx.targetRoom != null ? [[ctx.targetRoom].concat(into(P, ctx.targetRoom, tx, ty).slice(1))] : settle(P, locate(P, tx, ty), pick);
    if (!from.length || !to.length) return null;
    var n = P.nodes.length, S = n, T = n + 1, i, j, k, f, g;
    // Dijkstra with a binary heap of [cost, node]; each node's way in is
    // prev[node] and, off the start, the spot and corners it came by.
    var dist = [], prev = [], via = [], viaRoom = [], heap = [];
    function push(c, v) {
      heap.push([c, v]);
      var h = heap.length - 1;
      while (h > 0) {
        var up = (h - 1) >> 1;
        if (heap[up][0] <= heap[h][0]) break;
        var t = heap[up]; heap[up] = heap[h]; heap[h] = t; h = up;
      }
    }
    function pop() {
      var top = heap[0], last = heap.pop();
      if (heap.length) {
        heap[0] = last;
        var h = 0;
        for (;;) {
          var l = 2 * h + 1, rr = l + 1, m = h;
          if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
          if (rr < heap.length && heap[rr][0] < heap[m][0]) m = rr;
          if (m === h) break;
          var t = heap[m]; heap[m] = heap[h]; heap[h] = t; h = m;
        }
      }
      return top;
    }
    function reach(v, c, u, way, r) {
      if (dist[v] == null || c < dist[v]) { dist[v] = c; prev[v] = u; via[v] = way; viaRoom[v] = r; push(c, v); }
    }
    for (i = 0; i < from.length; i++) {
      f = from[i];
      var off = Math.hypot(f[1] - sx, f[2] - sy);
      var js = joins(P, f[0], f[1], f[2]);
      for (j = 0; j < js.length; j++) reach(js[j][0], js[j][1] + off, S, [f[1], f[2]].concat(js[j][2]), f[0]);
      for (j = 0; j < to.length; j++) {
        g = to[j];
        if (g[0] === f[0] && clear(P.rooms[f[0]], f[1], f[2], g[1], g[2]))
          reach(T, off + joinCost(P.rooms[f[0]], Math.hypot(g[1] - f[1], g[2] - f[2])), S, [f[1], f[2], g[1], g[2]], f[0]);
      }
    }
    // The target's joins, walked backwards: from a node to the target.
    var toTarget = {};
    for (i = 0; i < to.length; i++) {
      g = to[i];
      var jt = joins(P, g[0], g[1], g[2]);
      for (j = 0; j < jt.length; j++) {
        var back = [];
        for (k = jt[j][2].length - 2; k >= 0; k -= 2) back.push(jt[j][2][k], jt[j][2][k + 1]);
        back.push(g[1], g[2]);
        if (toTarget[jt[j][0]] == null || jt[j][1] < toTarget[jt[j][0]][0]) toTarget[jt[j][0]] = [jt[j][1], back, g[0]];
      }
    }
    while (heap.length) {
      var top = pop(), u = top[1], d = top[0];
      if (d > dist[u]) continue;
      if (u === T) break;
      var adj = P.adj[u];
      for (j = 0; j < adj.length; j += 2) reach(adj[j], d + adj[j + 1], u, null, -1);
      var tl = toTarget[u];
      if (tl) reach(T, d + tl[0], u, tl[1], tl[2]);
    }
    if (dist[T] == null) return null;
    // Back from the target: each node, and the spots and corners on its way in.
    var chain = [], at = T;
    while (at !== S) { chain.push(at); at = prev[at]; }
    chain.reverse();
    // The route in yards, each point with its tag (room or doorway).
    var yds = [sx, sy], tags = [viaRoom[chain[0]]];
    function add(x, y, tag) {
      var n2 = yds.length;
      if (Math.abs(yds[n2 - 2] - x) > 1e-6 || Math.abs(yds[n2 - 1] - y) > 1e-6) { yds.push(x, y); tags.push(tag); }
    }
    for (i = 0; i < chain.length; i++) {
      var v = chain[i], way = via[v];
      if (way && prev[v] === S) for (k = 0; k < way.length; k += 2) add(way[k], way[k + 1], viaRoom[v]);
      if (v !== T) add(P.nodes[v][0], P.nodes[v][1], P.tag[v]);
      else if (way && prev[v] !== S) for (k = 0; k < way.length; k += 2) add(way[k], way[k + 1], viaRoom[v]);
    }
    add(tx, ty, viaRoom[T]);
    var kept = straighten(P, yds, tags), pts = [];
    for (i = 0; i < kept.length; i++) pts.push([yds[2 * kept[i]] / kx, yds[2 * kept[i] + 1] / ky]);
    pts[0] = [start[0], start[1]];
    pts[pts.length - 1] = [target[0], target[1]];
    var rooms = [], trooms = [];
    for (i = 0; i < from.length; i++) rooms.push(from[i][0] + 1);
    for (i = 0; i < to.length; i++) trooms.push(to[i][0] + 1);
    return { points: pts, note: "room " + rooms.join("/") + " to room " + trooms.join("/") + ", " +
             (chain.length - 1) + " lane points, " + Math.round(dist[T]) + " yd cost" };
  }

  // The rooms a tagged point is in.
  function roomsOf(P, tag) {
    return tag >= 0 ? [tag] : P.doors[-tag - 1].rooms;
  }

  // Whether a straight line between two tagged points can be walked: inside
  // a room they share, or from one room into the next through a doorway
  // between them (crossing its line, clear in each room either side).
  function sees(P, ax, ay, ta, bx, by, tb) {
    var ra = roomsOf(P, ta), rb = roomsOf(P, tb), i, j, d;
    for (i = 0; i < ra.length; i++)
      if (rb.indexOf(ra[i]) >= 0 && clear(P.rooms[ra[i]], ax, ay, bx, by)) return true;
    for (d = 0; d < P.doors.length; d++) {
      var door = P.doors[d];
      if (door.rooms.length < 2) continue;
      for (i = 0; i < 2; i++) {
        var x = door.rooms[i], y = door.rooms[1 - i];
        if (ra.indexOf(x) < 0 || rb.indexOf(y) < 0) continue;
        var L = door.line, dx = L[2] - L[0], dy = L[3] - L[1];
        var den = (bx - ax) * dy - (by - ay) * dx;
        if (Math.abs(den) < 1e-9) continue;
        var t = ((L[0] - ax) * dy - (L[1] - ay) * dx) / den;
        var u = ((L[0] - ax) * (by - ay) - (L[1] - ay) * (bx - ax)) / den;
        var len = Math.hypot(dx, dy), m = len > 1 ? 0.5 / len : 0;
        if (t < 0 || t > 1 || u < m || u > 1 - m) continue;
        var px = ax + (bx - ax) * t, py = ay + (by - ay) * t;
        if (clear(P.rooms[x], ax, ay, px, py) && clear(P.rooms[y], px, py, bx, by)) return true;
      }
    }
    return false;
  }

  // The route without its needless points (yards, flat, with tags): from
  // each point on, the farthest point that can be seen without any point
  // between lying more than PULL off the line; so a doorway's two sides and
  // the zig-zags into and out of it go, and the way along a wall stays.
  function straighten(P, yds, tags) {
    var n = yds.length / 2, out = [0], i = 0;
    while (i < n - 1) {
      var j = i + 1;
      for (var k = Math.min(n - 1, i + PULL_AHEAD); k > i + 1; k--) {
        var ok = true;
        for (var m = i + 1; ok && m < k; m++)
          if (toSegment(yds[2 * m], yds[2 * m + 1], yds[2 * i], yds[2 * i + 1], yds[2 * k], yds[2 * k + 1])[0] > PULL) ok = false;
        if (ok && sees(P, yds[2 * i], yds[2 * i + 1], tags[i], yds[2 * k], yds[2 * k + 1], tags[k])) { j = k; break; }
      }
      out.push(j);
      i = j;
    }
    return out;
  }

  // ---- The cheaper variant: lanes along the outline, made in the game ------

  function offsetLanes(P, data) {
    var out = [], kx = data.yards[0], ky = data.yards[1];
    for (var r = 0; r < P.rooms.length; r++) {
      var room = P.rooms[r], mine = [];
      for (var i = 0; i < P.doors.length; i++)
        if (P.doors[i].rooms.indexOf(r) >= 0) mine.push(i);
      if (room.outer < 0) continue;
      var ring = offsetRing(room, room.offset || 2.5);
      for (var a = 0; a < mine.length; a++) {
        for (var b = a + 1; b < mine.length; b++) {
          var pa = P.nodes[P.doors[mine[a]].node], pb = P.nodes[P.doors[mine[b]].node];
          var line = alongWall(room, ring, pa, pb);
          var pts = [];
          for (var k = 0; k < line.length; k += 2) pts.push(line[k] / kx, line[k + 1] / ky);
          out.push({ room: r, from: mine[a], to: mine[b], points: pts });
        }
      }
    }
    return out;
  }

  // The room's outer loop pushed in by `off` yd; points that land outside the room are left out (null).
  function offsetRing(room, off) {
    var L = room.loops[room.outer], n = L.length / 2, sign = L.area > 0 ? 1 : -1, out = [];
    for (var i = 0; i < n; i++) {
      var h = (i + n - 1) % n, j = (i + 1) % n;
      var e1x = L[2 * i] - L[2 * h], e1y = L[2 * i + 1] - L[2 * h + 1], l1 = Math.hypot(e1x, e1y) || 1;
      var e2x = L[2 * j] - L[2 * i], e2y = L[2 * j + 1] - L[2 * i + 1], l2 = Math.hypot(e2x, e2y) || 1;
      var n1x = -e1y / l1 * sign, n1y = e1x / l1 * sign, n2x = -e2y / l2 * sign, n2y = e2x / l2 * sign;
      var mx = n1x + n2x, my = n1y + n2y, ml = Math.hypot(mx, my);
      if (ml < 1e-6) { mx = n1x; my = n1y; ml = 1; }
      mx /= ml; my /= ml;
      var scale = off / Math.max(0.5, mx * n1x + my * n1y);
      var x = L[2 * i] + mx * scale, y = L[2 * i + 1] + my * scale;
      out.push(inside(room, x, y) ? [x, y] : null);
    }
    return out;
  }

  // From a to b along the wall, the shorter way round, bumps under BUMP left out.
  function alongWall(room, ring, a, b) {
    var n = ring.length, ia = 0, ib = 0, da = 1e18, db = 1e18, i;
    for (i = 0; i < n; i++) {
      if (!ring[i]) continue;
      var d1 = Math.hypot(ring[i][0] - a[0], ring[i][1] - a[1]), d2 = Math.hypot(ring[i][0] - b[0], ring[i][1] - b[1]);
      if (d1 < da) { da = d1; ia = i; }
      if (d2 < db) { db = d2; ib = i; }
    }
    var best = null, bestLength = 1e18;
    for (var dir = -1; dir <= 1; dir += 2) {
      var pts = [a];
      for (i = ia; ; i = (i + dir + n) % n) {
        if (ring[i]) pts.push(ring[i]);
        if (i === ib) break;
      }
      pts.push(b);
      var line = pull(room, pts), length = 0;
      for (i = 2; i < line.length; i += 2) length += Math.hypot(line[i] - line[i - 2], line[i + 1] - line[i - 1]);
      if (length < bestLength) { bestLength = length; best = line; }
    }
    var straight = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (clear(room, a[0], a[1], b[0], b[1]) && bestLength > STRETCH * straight) return [a[0], a[1], b[0], b[1]];
    return best;
  }

  // Greedy: from each point the farthest one on that can be seen with no point between more than BUMP off the line.
  function pull(room, pts) {
    var out = [pts[0][0], pts[0][1]], i = 0, last = pts.length - 1;
    while (i < last) {
      var j = i + 1;
      for (var k = last; k > i + 1; k--) {
        var ok = clear(room, pts[i][0], pts[i][1], pts[k][0], pts[k][1]);
        for (var m = i + 1; ok && m < k; m++)
          if (toSegment(pts[m][0], pts[m][1], pts[i][0], pts[i][1], pts[k][0], pts[k][1])[0] > BUMP) ok = false;
        if (ok) { j = k; break; }
      }
      out.push(pts[j][0], pts[j][1]);
      i = j;
    }
    return out;
  }

  var api = { route: route, prepare: prepare, locate: locate, into: into, inside: inside, clear: clear };
  if (typeof NuuRoadViewer !== "undefined") NuuRoadViewer.method("lanes", api);
  if (typeof module !== "undefined") module.exports = api;
})();
