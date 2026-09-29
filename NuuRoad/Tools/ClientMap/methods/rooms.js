// The router of methods/rooms.py: a place as rooms and doorways, the way
// through worked out when asked, the way the addon would in Lua 5.1 (plain
// arrays and loops, no libraries).
//
// When the place is loaded: every room is cut into triangles (ear
// clipping; a room is one plain polygon, so the triangles form a tree and
// there is one channel of triangles between any two of them), and every
// doorway gets a few stops along it, a stop every `SPACING` yards.
//
// A route: the rooms the start and the target are in (by containing room,
// never by the nearest line: every room holding the point when floors are
// stacked, or the rooms whose edge is nearest within `REACH` yards when it
// is in none); Dijkstra over the doorway stops, where a step is a walk
// across one room from stop to stop, measured along the room's own taut
// line; then the funnel (string pulling) through the chosen doorways and
// the triangles inside each room gives the taut line. The arrow points at
// its first bend.
//
// While the player walks, `track` keeps the rooms they may be in (one,
// once walked in; every room holding the point after a teleport): each
// changes only when the player crosses one of its doorways (or its lift),
// or when the player is plainly out of it. A route from several rooms
// takes the nearest; `route` is given the tracker's rooms, and may be given
// the room a guide pins its target to, when floors are stacked.
(function () {
  "use strict";

  const SPACING = 5.0;   // yards between doorway stops
  const REACH = 10.0;    // yards: a point in no room joins the nearest edge this close
  const LIFT = 15.0;     // yards a lift ride costs
  const SLACK = 1.6;     // yards: past a room's outline by more, the player has left it

  function cross(ax, ay, bx, by, cx, cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }

  // ---- Loading --------------------------------------------------------------

  // Map % to yards with y up (so anticlockwise is the usual way round).
  function toYards(P, mx, my) { return [mx * P.kx, -my * P.ky]; }
  function toMap(P, p) { return [p[0] / P.kx, -p[1] / P.ky]; }

  // Ear clipping. Returns triangles [a, b, c] of vertex numbers, each
  // anticlockwise. A polygon that will not clip cleanly (a sliver) gives
  // up its flattest corner.
  function triangulate(xs, ys) {
    const n = xs.length;
    let area = 0;
    for (let i = 0, j = n - 1; i < n; j = i++) area += xs[j] * ys[i] - xs[i] * ys[j];
    const turn = area >= 0 ? 1 : -1;
    const left = [];
    for (let i = 0; i < n; i++) left.push(i);
    const tris = [];
    const emit = (a, b, c) => { tris.push(turn > 0 ? [a, b, c] : [a, c, b]); };
    while (left.length > 3) {
      const m = left.length;
      let found = -1;
      for (let pass = 0; pass < 2 && found < 0; pass++) {
        for (let k = 0; k < m; k++) {
          const a = left[(k + m - 1) % m], b = left[k], c = left[(k + 1) % m];
          const t = turn * cross(xs[a], ys[a], xs[b], ys[b], xs[c], ys[c]);
          if (pass === 0 ? t <= 0 : t < 0) continue;
          let clear = true;
          for (let q = 0; q < m && clear; q++) {
            const v = left[q];
            if (v === a || v === b || v === c) continue;
            if ((xs[v] === xs[a] && ys[v] === ys[a]) || (xs[v] === xs[b] && ys[v] === ys[b]) ||
                (xs[v] === xs[c] && ys[v] === ys[c])) continue;
            const d1 = turn * cross(xs[a], ys[a], xs[b], ys[b], xs[v], ys[v]);
            const d2 = turn * cross(xs[b], ys[b], xs[c], ys[c], xs[v], ys[v]);
            const d3 = turn * cross(xs[c], ys[c], xs[a], ys[a], xs[v], ys[v]);
            if (d1 >= 0 && d2 >= 0 && d3 >= 0) clear = false;
          }
          if (clear) { found = k; break; }
        }
      }
      if (found < 0) {
        // No clean ear: the flattest convex corner.
        let best = -Infinity;
        for (let k = 0; k < m; k++) {
          const a = left[(k + m - 1) % m], b = left[k], c = left[(k + 1) % m];
          const t = turn * cross(xs[a], ys[a], xs[b], ys[b], xs[c], ys[c]);
          if (t > best) { best = t; found = k; }
        }
      }
      emit(left[(found + m - 1) % m], left[found], left[(found + 1) % m]);
      left.splice(found, 1);
    }
    emit(left[0], left[1], left[2]);
    return tris;
  }

  function prepare(data) {
    if (data._place) return data._place;
    const P = { kx: data.yards[0], ky: data.yards[1], rooms: [], doors: [], stops: [], lifts: [] };
    const ox = data.origin[0], oy = data.origin[1], unit = data.unit;
    for (const ring of data.rooms) {
      const xs = [], ys = [];
      for (const [ix, iy] of ring) {
        const p = toYards(P, ox + ix * unit, oy + iy * unit);
        xs.push(p[0]); ys.push(p[1]);
      }
      const n = xs.length;
      const tris = triangulate(xs, ys);
      // Neighbours across each side of each triangle; the triangle on each
      // edge of the outline.
      const sides = new Map();
      const nb = tris.map(() => [-1, -1, -1]);
      const edgeTri = new Array(n).fill(-1);
      tris.forEach((t, ti) => {
        for (let s = 0; s < 3; s++) {
          const a = t[s], b = t[(s + 1) % 3];
          const key = a < b ? a * 65536 + b : b * 65536 + a;
          const other = sides.get(key);
          if (other) { nb[ti][s] = other[0]; nb[other[0]][other[1]] = ti; }
          else sides.set(key, [ti, s]);
          if ((a + 1) % n === b || (b + 1) % n === a) edgeTri[(a + 1) % n === b ? a : b] = ti;
        }
      });
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (let i = 0; i < n; i++) {
        x0 = Math.min(x0, xs[i]); x1 = Math.max(x1, xs[i]); y0 = Math.min(y0, ys[i]); y1 = Math.max(y1, ys[i]);
      }
      P.rooms.push({ xs, ys, tris, nb, edgeTri, box: [x0, y0, x1, y1], stops: [], doors: [], lifts: [], pair: new Map() });
    }
    // Doorways and their stops.
    for (const [ra, ea, rb, eb] of data.doors) {
      const A = P.rooms[ra], n = A.xs.length;
      const p = [A.xs[ea], A.ys[ea]], q = [A.xs[(ea + 1) % n], A.ys[(ea + 1) % n]];
      const d = P.doors.length;
      P.doors.push({ ra, ea, rb, eb, p, q });
      A.doors.push(d); P.rooms[rb].doors.push(d);
      const length = Math.hypot(q[0] - p[0], q[1] - p[1]);
      const k = Math.max(1, Math.round(length / SPACING));
      for (let j = 0; j < k; j++) {
        const f = (j + 0.5) / k;
        const s = P.stops.length;
        P.stops.push({ door: d, at: [p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f], rooms: [ra, rb],
                       tris: [A.edgeTri[ea], P.rooms[rb].edgeTri[eb]] });
        A.stops.push(s); P.rooms[rb].stops.push(s);
      }
    }
    for (const [ra, rb, ix, iy] of data.lifts || []) {
      const at = toYards(P, ox + ix * unit, oy + iy * unit);
      const ends = [ra, rb].map((r) => nearestIn(P, r, at));
      const s = P.stops.length;
      const l = P.lifts.length;
      P.lifts.push({ ra, rb, at: [ends[0].at, ends[1].at] });
      P.stops.push({ lift: l, at: ends[0].at, other: ends[1].at, rooms: [ra, rb], tris: [ends[0].tri, ends[1].tri] });
      P.rooms[ra].stops.push(s); P.rooms[rb].stops.push(s);
      P.rooms[ra].lifts.push(l); P.rooms[rb].lifts.push(l);
    }
    data._place = P;
    return P;
  }

  // ---- Where a point is ------------------------------------------------------

  function inTri(R, t, x, y) {
    const [a, b, c] = R.tris[t];
    const e = -1e-9;
    return cross(R.xs[a], R.ys[a], R.xs[b], R.ys[b], x, y) >= e &&
           cross(R.xs[b], R.ys[b], R.xs[c], R.ys[c], x, y) >= e &&
           cross(R.xs[c], R.ys[c], R.xs[a], R.ys[a], x, y) >= e;
  }

  function triOf(R, x, y) {
    if (x < R.box[0] || x > R.box[2] || y < R.box[1] || y > R.box[3]) return -1;
    for (let t = 0; t < R.tris.length; t++) if (inTri(R, t, x, y)) return t;
    return -1;
  }

  // The nearest point of room r's outline to `at`: {at, tri, d}.
  function nearestIn(P, r, at) {
    const R = P.rooms[r], n = R.xs.length;
    let best = null;
    for (let i = 0; i < n; i++) {
      const ax = R.xs[i], ay = R.ys[i], bx = R.xs[(i + 1) % n], by = R.ys[(i + 1) % n];
      const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy;
      const f = L ? Math.max(0, Math.min(1, ((at[0] - ax) * dx + (at[1] - ay) * dy) / L)) : 0;
      const px = ax + f * dx, py = ay + f * dy, d = Math.hypot(at[0] - px, at[1] - py);
      if (!best || d < best.d) best = { at: [px, py], tri: R.edgeTri[i], d, room: r };
    }
    return best;
  }

  // Every room holding the point (yards), or else those whose edge is
  // nearest within REACH (the point moved onto it): [{room, tri, at}].
  function candidates(P, at) {
    const out = [];
    P.rooms.forEach((R, r) => {
      const t = triOf(R, at[0], at[1]);
      if (t >= 0) out.push({ room: r, tri: t, at, d: 0 });
    });
    if (out.length) return out;
    const near = [];
    for (let r = 0; r < P.rooms.length; r++) {
      const b = P.rooms[r].box;
      if (at[0] < b[0] - REACH || at[0] > b[2] + REACH || at[1] < b[1] - REACH || at[1] > b[3] + REACH) continue;
      const e = nearestIn(P, r, at);
      if (e.d <= REACH) near.push(e);
    }
    if (!near.length) return out;
    const least = Math.min(...near.map((e) => e.d));
    return near.filter((e) => e.d <= least + 0.5);
  }

  function locate(data, map) {
    const P = prepare(data);
    return candidates(P, toYards(P, map[0], map[1])).map((c) => c.room);
  }

  // ---- Inside a room ---------------------------------------------------------

  // The triangles from t0 to t1 (the one way through the room's tree).
  function channel(R, t0, t1) {
    if (t0 === t1) return [t0];
    const prev = new Int32Array(R.tris.length).fill(-2);
    prev[t0] = -1;
    const queue = [t0];
    for (let h = 0; h < queue.length; h++) {
      const t = queue[h];
      if (t === t1) break;
      for (const o of R.nb[t]) if (o >= 0 && prev[o] === -2) { prev[o] = t; queue.push(o); }
    }
    const out = [];
    for (let t = t1; t !== -1; t = prev[t]) { out.push(t); if (t === t0) break; }
    return out.reverse();
  }

  // The side two triangles share, as [left, right] seen walking from t
  // into o (triangles are anticlockwise, so walking out through a->b, b is
  // on the left).
  function portal(R, t, o) {
    const tri = R.tris[t];
    for (let s = 0; s < 3; s++) {
      if (R.nb[t][s] === o) {
        const a = tri[s], b = tri[(s + 1) % 3];
        return [R.xs[b], R.ys[b], R.xs[a], R.ys[a]];
      }
    }
    throw new Error("triangles do not meet");
  }

  // Leaving room R through its outline edge e, as [left, right]: the
  // edge as its (anticlockwise) triangle runs along it, whichever way
  // round the room itself was drawn.
  function exitPortal(R, e) {
    const n = R.xs.length, a = e, b = (e + 1) % n, tri = R.tris[R.edgeTri[e]];
    for (let s = 0; s < 3; s++) {
      const u = tri[s], v = tri[(s + 1) % 3];
      if ((u === a && v === b) || (u === b && v === a)) return [R.xs[v], R.ys[v], R.xs[u], R.ys[u]];
    }
    throw new Error("edge not on its triangle");
  }

  function addChannel(portals, R, t0, t1) {
    const tri = channel(R, t0, t1);
    for (let i = 0; i + 1 < tri.length; i++) portals.push(portal(R, tri[i], tri[i + 1]));
  }

  // The funnel: the taut line through `portals` ([lx, ly, rx, ry]; the
  // first and last are the start and the end, both sides one point).
  function funnel(portals) {
    const out = [[portals[0][0], portals[0][1]]];
    let ax = portals[0][0], ay = portals[0][1];
    let lx = ax, ly = ay, rx = ax, ry = ay;
    let li = 0, ri = 0;
    for (let i = 1; i < portals.length; i++) {
      const pl = portals[i];
      const plx = pl[0], ply = pl[1], prx = pl[2], pry = pl[3];
      // The right side: tighter, and not past the left.
      if (cross(ax, ay, rx, ry, prx, pry) >= 0) {
        if ((ax === rx && ay === ry) || cross(ax, ay, lx, ly, prx, pry) < 0) { rx = prx; ry = pry; ri = i; }
        else {
          ax = lx; ay = ly; out.push([ax, ay]);
          rx = lx = ax; ry = ly = ay; ri = li; i = li; continue;
        }
      }
      if (cross(ax, ay, lx, ly, plx, ply) <= 0) {
        if ((ax === lx && ay === ly) || cross(ax, ay, rx, ry, plx, ply) > 0) { lx = plx; ly = ply; li = i; }
        else {
          ax = rx; ay = ry; out.push([ax, ay]);
          lx = rx = ax; ly = ry = ay; li = ri; i = ri; continue;
        }
      }
    }
    const end = portals[portals.length - 1];
    const last = out[out.length - 1];
    if (last[0] !== end[0] || last[1] !== end[1]) out.push([end[0], end[1]]);
    return out;
  }

  function length(points) {
    let L = 0;
    for (let i = 1; i < points.length; i++) L += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
    return L;
  }

  // The taut line across one room from (a, ta) to (b, tb).
  function across(R, a, ta, b, tb) {
    const portals = [[a[0], a[1], a[0], a[1]]];
    addChannel(portals, R, ta, tb);
    portals.push([b[0], b[1], b[0], b[1]]);
    return funnel(portals);
  }

  // Where stop s is, and its triangle, seen from room r.
  function stopIn(P, s, r) {
    const S = P.stops[s], k = S.rooms[0] === r ? 0 : 1;
    return { at: k === 0 || S.lift === undefined ? S.at : S.other, tri: S.tris[k] };
  }

  // Walking distance across room r between two of its stops (kept).
  function pairLength(P, r, s1, s2) {
    const R = P.rooms[r];
    const key = s1 < s2 ? s1 * 65536 + s2 : s2 * 65536 + s1;
    let d = R.pair.get(key);
    if (d === undefined) {
      const a = stopIn(P, s1, r), b = stopIn(P, s2, r);
      d = length(across(R, a.at, a.tri, b.at, b.tri));
      R.pair.set(key, d);
    }
    return d;
  }

  // ---- A route ---------------------------------------------------------------

  // Dijkstra over the doorway stops, from every candidate of the start to
  // every candidate of the target. Returns {rooms: [...], stops: [...],
  // from, to, length} or null.
  function plan(P, starts, targets) {
    const N = P.stops.length, SRC = N, DST = N + 1;
    const dist = new Float64Array(N + 2).fill(Infinity);
    const prev = new Int32Array(N + 2).fill(-1);
    const via = new Int32Array(N + 2).fill(-1);    // the room walked to reach each
    const fromCand = new Int32Array(N + 2).fill(-1);
    const done = new Uint8Array(N + 2);
    const heap = [];
    const push = (d, v) => {
      heap.push([d, v]);
      for (let i = heap.length - 1; i > 0;) {
        const p = (i - 1) >> 1;
        if (heap[p][0] <= heap[i][0]) break;
        [heap[p], heap[i]] = [heap[i], heap[p]]; i = p;
      }
    };
    const pop = () => {
      const top = heap[0], last = heap.pop();
      if (heap.length) {
        heap[0] = last;
        for (let i = 0; ;) {
          const l = 2 * i + 1, r = l + 1;
          let m = i;
          if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
          if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
          if (m === i) break;
          [heap[m], heap[i]] = [heap[i], heap[m]]; i = m;
        }
      }
      return top;
    };
    const relax = (u, v, d, room, cand) => {
      if (d < dist[v]) { dist[v] = d; prev[v] = u; via[v] = room; fromCand[v] = cand; push(d, v); }
    };
    const targetOf = new Map();
    targets.forEach((c, k) => { if (!targetOf.has(c.room)) targetOf.set(c.room, []); targetOf.get(c.room).push(k); });
    dist[SRC] = 0;
    starts.forEach((c, k) => {
      const R = P.rooms[c.room];
      for (const s of R.stops) {
        const b = stopIn(P, s, c.room);
        relax(SRC, s, length(across(R, c.at, c.tri, b.at, b.tri)), c.room, k);
      }
      for (const j of targetOf.get(c.room) || []) {
        const t = targets[j];
        relax(SRC, DST, length(across(R, c.at, c.tri, t.at, t.tri)), c.room, k * 1000 + j);
      }
    });
    while (heap.length) {
      const [d, u] = pop();
      if (done[u]) continue;
      done[u] = 1;
      if (u === DST) break;
      const S = P.stops[u];
      const ride = S.lift !== undefined ? LIFT : 0;
      for (const r of S.rooms) {
        // Along a lift the other end is reached by riding, not walking.
        const R = P.rooms[r];
        for (const s of R.stops) if (s !== u && !done[s]) relax(u, s, d + ride + pairLength(P, r, u, s), r, -1);
        for (const j of targetOf.get(r) || []) {
          const t = targets[j], a = stopIn(P, u, r);
          relax(u, DST, d + ride + length(across(R, a.at, a.tri, t.at, t.tri)), r, j);
        }
      }
    }
    if (dist[DST] === Infinity) return null;
    const stops = [], rooms = [via[DST]];
    let u = prev[DST], lastCand = fromCand[DST];
    while (u !== SRC) { stops.push(u); rooms.push(via[u]); lastCand = fromCand[u]; u = prev[u]; }
    stops.reverse(); rooms.reverse();
    let from, to;
    if (stops.length === 0) { from = starts[Math.floor(fromCand[DST] / 1000)]; to = targets[fromCand[DST] % 1000]; }
    else { from = starts[lastCand]; to = targets[fromCand[DST]]; }
    return { rooms, stops, from, to, length: dist[DST] };
  }

  // The portals of a planned route: each room's triangles from where it is
  // entered to where it is left, and the doorway (or lift) between rooms.
  function portalsOf(P, planned, start, target) {
    const { rooms, stops, from, to } = planned;
    const portals = [[start[0], start[1], start[0], start[1]]];
    if (from.at[0] !== start[0] || from.at[1] !== start[1]) portals.push([from.at[0], from.at[1], from.at[0], from.at[1]]);
    let at = from.at, tri = from.tri;
    for (let i = 0; i < rooms.length; i++) {
      const r = rooms[i], R = P.rooms[r];
      if (i < stops.length) {
        const S = P.stops[stops[i]];
        const here = stopIn(P, stops[i], r);
        addChannel(portals, R, tri, here.tri);
        const next = rooms[i + 1];
        const there = stopIn(P, stops[i], next);
        if (S.lift !== undefined) {
          portals.push([here.at[0], here.at[1], here.at[0], here.at[1]]);
          portals.push([there.at[0], there.at[1], there.at[0], there.at[1]]);
        } else {
          const D = P.doors[S.door];
          portals.push(exitPortal(R, D.ra === r ? D.ea : D.eb));
        }
        at = there.at; tri = there.tri;
      } else {
        addChannel(portals, R, tri, to.tri);
      }
    }
    portals.push([to.at[0], to.at[1], to.at[0], to.at[1]]);
    if (to.at[0] !== target[0] || to.at[1] !== target[1]) portals.push([target[0], target[1], target[0], target[1]]);
    return portals;
  }

  // The candidates of a point, kept to `rooms` when they are known (the
  // tracker's rooms for the player; the room an author's `near` names for a
  // target): a point outside such a room (on the shaved band by a wall)
  // joins its nearest edge.
  function within(P, at, rooms) {
    const all = candidates(P, at);
    if (!rooms) return all;
    return rooms.map((r) => all.find((c) => c.room === r) || nearestIn(P, r, at));
  }

  function routeYards(P, start, target, startRooms, targetRooms) {
    const S = within(P, start, startRooms);
    const T = within(P, target, targetRooms);
    if (!S.length || !T.length) return { points: null, note: !S.length ? "start in no room" : "target in no room" };
    const planned = plan(P, S, T);
    if (!planned) return { points: null, note: "no way between the rooms" };
    const points = funnel(portalsOf(P, planned, start, target));
    return { points, planned, S, T };
  }

  // Room r after a step from A to B (yards) that may cross its doorways:
  // each doorway reaches past its ends to the real walls (the rooms stop
  // short of them by the shave), so a player hugging a wall still crosses it.
  function through(P, r, A0, B) {
    const A = [A0[0], A0[1]];
    for (let hop = 0; hop < 4; hop++) {
      const R = P.rooms[r];
      let crossed = -1, best = Infinity;
      for (const d of R.doors) {
        const D = P.doors[d];
        const dx = D.q[0] - D.p[0], dy = D.q[1] - D.p[1], L = Math.hypot(dx, dy) || 1;
        const ex = dx / L * SLACK, ey = dy / L * SLACK;
        const px = D.p[0] - ex, py = D.p[1] - ey, qx = D.q[0] + ex, qy = D.q[1] + ey;
        const d1 = cross(px, py, qx, qy, A[0], A[1]), d2 = cross(px, py, qx, qy, B[0], B[1]);
        const d3 = cross(A[0], A[1], B[0], B[1], px, py), d4 = cross(A[0], A[1], B[0], B[1], qx, qy);
        if ((d1 > 0) === (d2 > 0) || (d3 > 0) === (d4 > 0) || d2 === 0) continue;
        const f = d1 / (d1 - d2);
        if (f < best) { best = f; crossed = d; }
      }
      if (crossed < 0) break;
      const D = P.doors[crossed];
      r = D.ra === r ? D.rb : D.ra;
      const f = Math.min(1, best + 1e-6);
      A[0] += (B[0] - A[0]) * f; A[1] += (B[1] - A[1]) * f;
    }
    // A lift ridden: at its other end, off the room it left.
    for (const l of P.rooms[r].lifts) {
      const L = P.lifts[l], other = L.ra === r ? L.rb : L.ra;
      const far = L.ra === r ? L.at[1] : L.at[0];
      if (Math.hypot(B[0] - far[0], B[1] - far[1]) < 3 && triOf(P.rooms[r], B[0], B[1]) < 0) r = other;
    }
    return r;
  }

  const api = {
    // startRooms: the rooms the tracker has the player in; targetRooms:
    // the room the guide pins the target to. Either may be left out.
    route(data, start, target, ctx, startRooms, targetRooms) {
      const P = prepare(data);
      const res = routeYards(P, toYards(P, start[0], start[1]), toYards(P, target[0], target[1]), startRooms, targetRooms);
      if (!res.points) return null;
      const note = "rooms " + res.planned.rooms.join(" > ") + "; " +
        (res.S.length > 1 ? res.S.length + " rooms could hold the start; " : "") +
        (res.T.length > 1 ? res.T.length + " rooms could hold the target, took the nearest" : "") +
        P.rooms.length + " rooms, " + P.doors.length + " doorways, " + P.stops.length + " stops";
      return { points: res.points.map((p) => toMap(P, p)), rooms: res.planned.rooms, note };
    },

    // The rooms the player may be in after walking from map point a to b,
    // given those they may have been in (one, once the place is known; all
    // those holding the point after a teleport). Each is carried through
    // any doorway (or lift) the step crosses; one the player is plainly
    // out of (SLACK yards past its outline, more than the shave and the
    // navmesh's own margin) gives way to the rooms holding the point, those
    // through its doorways first; none left, the point is placed afresh.
    track(data, rooms, a, b) {
      const P = prepare(data);
      const A = toYards(P, a[0], a[1]), B = toYards(P, b[0], b[1]);
      const out = [];
      const add = (r) => { if (!out.includes(r)) out.push(r); };
      for (const r0 of (Array.isArray(rooms) ? rooms : [rooms])) {
        const r = through(P, r0, A, B);
        const R = P.rooms[r];
        if (triOf(R, B[0], B[1]) >= 0 || nearestIn(P, r, B).d <= SLACK) { add(r); continue; }
        let found = false;
        for (const d of R.doors) {
          const D = P.doors[d], o = D.ra === r ? D.rb : D.ra;
          if (triOf(P.rooms[o], B[0], B[1]) >= 0) { add(o); found = true; }
        }
        if (!found) for (const c of candidates(P, B)) add(c.room);
      }
      if (!out.length) for (const c of candidates(P, B)) add(c.room);
      return out;
    },

    locate,
    prepare,
    // For tests: the pieces.
    parts: { toYards, candidates, plan, portalsOf, funnel, channel },
    triangles(data) {
      const P = prepare(data);
      return P.rooms.map((R) => R.tris.map((t) => t.map((v) => toMap(P, [R.xs[v], R.ys[v]]))));
    },
  };

  if (typeof NuuRoadViewer !== "undefined") NuuRoadViewer.method("rooms", api);
  if (typeof module !== "undefined") module.exports = api;
})();
