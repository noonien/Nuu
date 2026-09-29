// The router of methods/widelanes.py: a place as points with a radius and
// the connections between them, each connection a lane (the hull of its two
// end discs, which the build keeps on one floor), the way the addon would
// run it in Lua 5.1 (plain arrays and loops, no libraries).
//
// A route: the lanes the start and the target are in (every lane whose hull
// holds the point, or the nearest within `REACH` yards when none does; the
// tracker's lanes when the player has been walking, and the lane an
// author's `near` names for a target where floors are stacked); Dijkstra
// over the points, a lane costing its length; then the funnel (string
// pulling) through the chain of lanes. The portal at each point on the way
// runs across the way (square to the bisector of the way in and the way
// out): on the inside of a bend it ends where the two lanes' straight edges
// cross, elsewhere as far as both lanes reach. It lies in both lanes, so the
// taut line stays inside the lanes, on the floor. A start or target off
// every lane joins its lane by a straight leg to the nearest spot inside
// it. The arrow points at the first bend.
//
// While the player walks, `track` keeps the lanes they may be on: a lane
// changes only to one that shares a point with it (so a floor over or under
// the player is never picked up), to the one nearest the player when they
// leave it; a player farther than `REACH` from all of them is lost, and
// found again by the lanes holding their position (all floors there, until
// walking on rules the others out).
(function () {
  "use strict";

  const REACH = 10.0;   // yards: a point in no lane joins the nearest lane this close
  const INSET = 0.1;    // yards: how far inside a lane an off-lane start or target joins it

  function prepare(data) {
    if (data._wide) return data._wide;
    const kx = data.yards[0], ky = data.yards[1];
    const P = { kx: kx, ky: ky, x: [], y: [], r: [], la: [], lb: [], len: [], adj: [] };
    for (let i = 0; i < data.points.length; i++) {
      const p = data.points[i];
      P.x.push(p[0] * kx);
      P.y.push(-p[1] * ky);
      P.r.push(p[2]);
      P.adj.push([]);
    }
    for (let k = 0; k < data.lanes.length; k++) {
      const a = data.lanes[k][0], b = data.lanes[k][1];
      P.la.push(a);
      P.lb.push(b);
      P.len.push(Math.hypot(P.x[b] - P.x[a], P.y[b] - P.y[a]));
      P.adj[a].push(k);
      P.adj[b].push(k);
    }
    data._wide = P;
    return P;
  }

  // Where on lane k the point (x, y) is nearest: [gap, t], the gap being
  // how far it is outside the hull (negative inside), t how far along the
  // lane (0 at its first point, 1 at its second) the nearest disc stands.
  function measure(P, k, x, y) {
    const a = P.la[k], b = P.lb[k];
    const ax = P.x[a], ay = P.y[a], ra = P.r[a], rb = P.r[b];
    const dx = P.x[b] - ax, dy = P.y[b] - ay;
    const L = P.len[k];
    if (L <= Math.abs(rb - ra) + 1e-9) {
      if (ra >= rb) return [Math.hypot(x - ax, y - ay) - ra, 0];
      return [Math.hypot(x - P.x[b], y - P.y[b]) - rb, 1];
    }
    const ux = dx / L, uy = dy / L;
    const along = (x - ax) * ux + (y - ay) * uy;
    const across = Math.abs((x - ax) * uy - (y - ay) * ux);
    const s = (ra - rb) / L;
    const w = s * across / Math.sqrt(1 - s * s);
    let t = (along - w) / L;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return [Math.hypot(along - t * L, across) - (ra + t * (rb - ra)), t];
  }

  function gap(P, k, x, y) { return measure(P, k, x, y)[0]; }

  // The point itself when lane k holds it, else the nearest spot a little
  // inside the lane.
  function entry(P, k, x, y) {
    const m = measure(P, k, x, y);
    if (m[0] <= 0) return [x, y];
    const a = P.la[k], b = P.lb[k], t = m[1];
    const cx = P.x[a] + (P.x[b] - P.x[a]) * t, cy = P.y[a] + (P.y[b] - P.y[a]) * t;
    const r = Math.max(0, P.r[a] + (P.r[b] - P.r[a]) * t - INSET);
    const d = Math.hypot(x - cx, y - cy);
    if (d < 1e-9) return [cx, cy];
    return [cx + (x - cx) * r / d, cy + (y - cy) * r / d];
  }

  // Every lane holding (x, y) yards, or the nearest within REACH.
  function lanesAt(P, x, y) {
    const out = [];
    let best = -1, bestGap = REACH;
    for (let k = 0; k < P.la.length; k++) {
      const g = gap(P, k, x, y);
      if (g <= 0) out.push(k);
      else if (g <= bestGap) { best = k; bestGap = g; }
    }
    if (!out.length && best >= 0) out.push(best);
    return out;
  }

  function locate(data, map) {
    const P = prepare(data);
    return lanesAt(P, map[0] * P.kx, -map[1] * P.ky);
  }

  // The tracker: from the lanes the player may be on (`state`) to those
  // after a move to `map`.
  function track(data, state, map) {
    const P = prepare(data);
    const x = map[0] * P.kx, y = -map[1] * P.ky;
    const next = [];
    for (let i = 0; i < state.length; i++) {
      let k = state[i];
      let g = gap(P, k, x, y);
      // Off the lane: on to whichever lane sharing a point with it is
      // nearest, as long as that brings the player nearer (a few hops for
      // a long step).
      for (let hop = 0; hop < 4 && g > 0; hop++) {
        let best = k, bestGap = g;
        const ends = [P.la[k], P.lb[k]];
        for (let e = 0; e < 2; e++) {
          const around = P.adj[ends[e]];
          for (let j = 0; j < around.length; j++) {
            const k2 = around[j];
            if (k2 === k) continue;
            const g2 = gap(P, k2, x, y);
            if (g2 < bestGap) { best = k2; bestGap = g2; }
          }
        }
        if (best === k) break;
        k = best;
        g = bestGap;
      }
      if (g <= REACH && next.indexOf(k) < 0) next.push(k);
    }
    if (!next.length) return lanesAt(P, x, y);
    const inside = [];
    for (let i = 0; i < next.length; i++) if (gap(P, next[i], x, y) <= 0) inside.push(next[i]);
    return inside.length ? inside : next;
  }

  // ---- Routing --------------------------------------------------------------

  function cross(ax, ay, bx, by, cx, cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }

  // The funnel: the taut line through `portals` ([lx, ly, rx, ry], left
  // and right as walked; the first and last are the start and the end,
  // both sides one point).
  function funnel(portals) {
    const out = [[portals[0][0], portals[0][1]]];
    let ax = portals[0][0], ay = portals[0][1];
    let lx = ax, ly = ay, rx = ax, ry = ay;
    let li = 0, ri = 0;
    for (let i = 1; i < portals.length; i++) {
      const pl = portals[i];
      const plx = pl[0], ply = pl[1], prx = pl[2], pry = pl[3];
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

  // A binary heap of [cost, point] kept in two plain arrays.
  function push(hc, hp, c, p) {
    let i = hc.length;
    hc.push(c); hp.push(p);
    while (i > 0) {
      const up = (i - 1) >> 1;
      if (hc[up] <= c) break;
      hc[i] = hc[up]; hp[i] = hp[up];
      i = up;
    }
    hc[i] = c; hp[i] = p;
  }

  function pop(hc, hp) {
    const c = hc[0], p = hp[0];
    const lc = hc.pop(), lp = hp.pop();
    const n = hc.length;
    if (n) {
      let i = 0;
      while (true) {
        let m = 2 * i + 1;
        if (m >= n) break;
        if (m + 1 < n && hc[m + 1] < hc[m]) m++;
        if (hc[m] >= lc) break;
        hc[i] = hc[m]; hp[i] = hp[m];
        i = m;
      }
      hc[i] = lc; hp[i] = lp;
    }
    return [c, p];
  }

  // How far from point p along (nx, ny) both lanes k1 and k2 (which meet
  // at p) hold: at least p's radius, found by halving.
  function reach(P, k1, k2, p, nx, ny) {
    const px = P.x[p], py = P.y[p];
    let lo = P.r[p];
    let hi = lo + Math.min(P.len[k1] + P.r[P.la[k1]] + P.r[P.lb[k1]], P.len[k2] + P.r[P.la[k2]] + P.r[P.lb[k2]]);
    if (gap(P, k1, px + nx * hi, py + ny * hi) <= 0 && gap(P, k2, px + nx * hi, py + ny * hi) <= 0) return hi;
    for (let i = 0; i < 16; i++) {
      const mid = (lo + hi) / 2, x = px + nx * mid, y = py + ny * mid;
      if (gap(P, k1, x, y) <= 0 && gap(P, k2, x, y) <= 0) lo = mid; else hi = mid;
    }
    return lo;
  }

  // The straight edge of lane k on the left (side 1) or the right (-1) as
  // walked from its end `from`: [x1, y1, x2, y2], or null when one disc
  // holds the other.
  function edge(P, k, from, side) {
    const to = P.la[k] === from ? P.lb[k] : P.la[k];
    const L = P.len[k];
    const r1 = P.r[from], r2 = P.r[to];
    if (L <= Math.abs(r1 - r2) + 1e-9) return null;
    const ux = (P.x[to] - P.x[from]) / L, uy = (P.y[to] - P.y[from]) / L;
    const s = (r1 - r2) / L, c = side * Math.sqrt(1 - s * s);
    // The edge's outward normal: s along the lane, c across it (left is (-uy, ux)).
    const mx = s * ux - c * uy, my = s * uy + c * ux;
    return [P.x[from] + r1 * mx, P.y[from] + r1 * my, P.x[to] + r2 * mx, P.y[to] + r2 * my];
  }

  // Where two segments cross, or null.
  function meet(a, b) {
    if (!a || !b) return null;
    const dax = a[2] - a[0], day = a[3] - a[1], dbx = b[2] - b[0], dby = b[3] - b[1];
    const den = dax * dby - day * dbx;
    if (Math.abs(den) < 1e-12) return null;
    const t = ((b[0] - a[0]) * dby - (b[1] - a[1]) * dbx) / den;
    const u = ((b[0] - a[0]) * day - (b[1] - a[1]) * dax) / den;
    if (t < 0 || t > 1 || u < 0 || u > 1) return null;
    return [a[0] + t * dax, a[1] + t * day];
  }

  // The portals of a chain of points from e to f (yards), where lanes[i]
  // is the lane into chain[i] and lanes[i + 1] the lane out of it: at each
  // point a line across the way (square to the bisector of the way in and
  // the way out) as far as both its lanes reach. Both lanes hold the
  // point's disc, so the portal is at least its diameter.
  function portalsOf(P, e, chain, lanes, f) {
    const portals = [[e[0], e[1], e[0], e[1]]];
    for (let i = 0; i < chain.length; i++) {
      const p = chain[i];
      const px = P.x[p], py = P.y[p];
      const qx = i > 0 ? P.x[chain[i - 1]] : e[0], qy = i > 0 ? P.y[chain[i - 1]] : e[1];
      const wx = i + 1 < chain.length ? P.x[chain[i + 1]] : f[0], wy = i + 1 < chain.length ? P.y[chain[i + 1]] : f[1];
      const ix = px - qx, iy = py - qy, ox = wx - px, oy = wy - py;
      const li = Math.hypot(ix, iy), lo = Math.hypot(ox, oy);
      let dx = (li > 1e-9 ? ix / li : 0) + (lo > 1e-9 ? ox / lo : 0);
      let dy = (li > 1e-9 ? iy / li : 0) + (lo > 1e-9 ? oy / lo : 0);
      let d = Math.hypot(dx, dy);
      if (d < 1e-9) { dx = lo > 1e-9 ? ox : 1; dy = lo > 1e-9 ? oy : 0; d = Math.hypot(dx, dy); }
      // Left of the way (y up): (-dy, dx).
      const nx = -dy / d, ny = dx / d;
      {
        // On the inside of a bend the lanes' edges cross short of the
        // disc: the portal ends there, the corner the taut line hugs.
        // Elsewhere as far across as both lanes reach.
        const kin = lanes[i], kout = lanes[i + 1];
        const back = P.la[kin] === p ? P.lb[kin] : P.la[kin];
        const on = P.la[kout] === p ? P.lb[kout] : P.la[kout];
        const xl = meet(edge(P, kin, back, 1), edge(P, kout, p, 1));
        const xr = meet(edge(P, kin, back, -1), edge(P, kout, p, -1));
        let lx, ly, rx, ry;
        if (xl && on !== back) { lx = xl[0]; ly = xl[1]; }
        else { const left = reach(P, kin, kout, p, nx, ny); lx = px + nx * left; ly = py + ny * left; }
        if (xr && on !== back) { rx = xr[0]; ry = xr[1]; }
        else { const right = reach(P, kin, kout, p, -nx, -ny); rx = px - nx * right; ry = py - ny * right; }
        portals.push([lx, ly, rx, ry]);
      }
    }
    portals.push([f[0], f[1], f[0], f[1]]);
    return portals;
  }

  function length(points) {
    let L = 0;
    for (let i = 1; i < points.length; i++) L += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
    return L;
  }

  // The route in yards: [points, lanes walked, chain of points, portals],
  // or null. Dijkstra over the points, a lane costing its length, from
  // where the start stands in each of its lanes to where the target stands
  // in each of its; a start and a target in one lane are a straight line.
  function routeYards(P, sx, sy, tx, ty, startLanes, targetLanes) {
    const S = startLanes && startLanes.length ? startLanes : lanesAt(P, sx, sy);
    const T = targetLanes && targetLanes.length ? targetLanes : lanesAt(P, tx, ty);
    if (!S.length || !T.length) return null;
    const n = P.x.length;
    const cost = new Array(n), from = new Array(n), via = new Array(n);
    for (let i = 0; i < n; i++) { cost[i] = Infinity; from[i] = -1; via[i] = -1; }
    const sIn = [], tIn = [];
    for (let i = 0; i < S.length; i++) sIn.push(entry(P, S[i], sx, sy));
    for (let i = 0; i < T.length; i++) tIn.push(entry(P, T[i], tx, ty));
    let best = Infinity, how = null;
    const hc = [], hp = [];
    for (let i = 0; i < S.length; i++) {
      const k = S[i], e = sIn[i];
      const c0 = Math.hypot(e[0] - sx, e[1] - sy);
      for (let j = 0; j < T.length; j++) {
        if (T[j] !== k) continue;
        const f = tIn[j];
        const c = c0 + Math.hypot(f[0] - e[0], f[1] - e[1]) + Math.hypot(tx - f[0], ty - f[1]);
        if (c < best) { best = c; how = [i, j, -1]; }
      }
      const ends = [P.la[k], P.lb[k]];
      for (let q = 0; q < 2; q++) {
        const p = ends[q];
        const c = c0 + Math.hypot(P.x[p] - e[0], P.y[p] - e[1]);
        if (c < cost[p]) { cost[p] = c; from[p] = -1 - i; via[p] = k; push(hc, hp, c, p); }
      }
    }
    while (hc.length) {
      const top = pop(hc, hp);
      const c = top[0], u = top[1];
      if (c > cost[u] || c >= best) continue;
      const around = P.adj[u];
      for (let j = 0; j < around.length; j++) {
        const k = around[j];
        const v = P.la[k] === u ? P.lb[k] : P.la[k];
        const nc = c + P.len[k];
        if (nc < cost[v]) { cost[v] = nc; from[v] = u; via[v] = k; push(hc, hp, nc, v); }
      }
    }
    for (let j = 0; j < T.length; j++) {
      const k = T[j], f = tIn[j];
      const ends = [P.la[k], P.lb[k]];
      for (let q = 0; q < 2; q++) {
        const p = ends[q];
        const c = cost[p] + Math.hypot(f[0] - P.x[p], f[1] - P.y[p]) + Math.hypot(tx - f[0], ty - f[1]);
        if (c < best) { best = c; how = [-1, j, p]; }
      }
    }
    if (!how) return null;
    const f = tIn[how[1]];
    let e, chain = [], lanes = [];
    if (how[2] < 0) {
      e = sIn[how[0]];
      lanes.push(S[how[0]]);
    } else {
      // Back from the target's lane to the start's: lanes[i] is the lane
      // into chain[i], the last the target's lane.
      lanes.push(T[how[1]]);
      let p = how[2];
      while (true) {
        chain.push(p);
        lanes.push(via[p]);
        if (from[p] < 0) { e = sIn[-1 - from[p]]; break; }
        p = from[p];
      }
      chain.reverse();
      lanes.reverse();
    }
    const portals = portalsOf(P, e, chain, lanes, f);
    const points = funnel(portals);
    if (e[0] !== sx || e[1] !== sy) points.unshift([sx, sy]);
    if (f[0] !== tx || f[1] !== ty) points.push([tx, ty]);
    return [points, lanes, chain, portals];
  }

  function route(data, start, target, ctx, startLanes, targetLanes) {
    const P = prepare(data);
    const got = routeYards(P, start[0] * P.kx, -start[1] * P.ky, target[0] * P.kx, -target[1] * P.ky,
                           startLanes, targetLanes);
    if (!got) return null;
    const points = [];
    for (let i = 0; i < got[0].length; i++) points.push([got[0][i][0] / P.kx, -got[0][i][1] / P.ky]);
    let length = 0;
    for (let i = 1; i < got[0].length; i++) length += Math.hypot(got[0][i][0] - got[0][i - 1][0], got[0][i][1] - got[0][i - 1][1]);
    const portals = [];
    for (let i = 0; i < got[3].length; i++) {
      const q = got[3][i];
      portals.push([q[0] / P.kx, -q[1] / P.ky, q[2] / P.kx, -q[3] / P.ky]);
    }
    return { points: points, lanes: got[1], chain: got[2], portals: portals,
             note: got[1].length + " lanes, " + (points.length - 2) + " bends, " + length.toFixed(1) + " yd" };
  }

  const api = { prepare: prepare, route: route, locate: locate, track: track, parts: { measure: measure, funnel: funnel } };
  if (typeof NuuRoadViewer !== "undefined") NuuRoadViewer.method("widelanes", api);
  if (typeof module !== "undefined") module.exports = api;
})();
