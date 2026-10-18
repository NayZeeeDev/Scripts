/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Burn care & skin graft (app 'burn')           module: burn
   One full-screen 3D close-up (core/nza3d.js) for both burn procedures:

     burn care ('burn')   1 Cool      tool 1 Saline     hold LMB: run saline over the burn; the wound
                                                        imager shows the surface heat; wash the soot
                                                        off and bring the surface under the target
                          2 Depth     tool 2 Diascope   hold LMB on the burn: the glass blanches
                                                        partial-thickness skin, full thickness stays
                                                        fixed; walk it across the burn
                          3 Debride   tool 3 Forceps    grip a blister roof / loose dead skin and pull
     skin graft ('graft') 4 Excise    tool 4 Knife      trace the marked line round each full-
                                                        thickness area; the eschar lifts off
                          5 Harvest   tool 5 Dermatome  donor thigh: hold LMB from the start line and
                                                        push steadily; wheel = pressure (keep it in band)
                          6 Mesh      tool 6 Mesher     pick the carrier (1:1.5 / 1:3), hold LMB and
                                                        circle the pointer round the crank
                          7 Apply     tool 7 Stapler    lay the graft over the bed (grab, Q/E turn),
                                                        then staple every marked point round the edge
                          8 Dress     tool 8 Dressing   lay the burn dressing over, rub it down
   Partial-thickness burns go 1 → 2 → 3 → 8. A full-thickness burn can go straight on to the
   graft (the server is asked first) or be dressed now and grafted later.

   Lua → JS   open { mode 'care'|'graft', locale, patient{name,sex,temp,avpu}, injury{id,region,
                     regionLabel,pain,contamination,burn{degree,area,temp,soot,full,assessed,
                     assessedFull}, treat{cooled,debrided,dressed,grafted}}, tone, seed, donor,
                     donorLabel, items{burnDressing,dressing,graftKit,saline}, graft{ok,msg}, cfg }
              careDone (care outcome, the graft follows) · graft (graft case) · graftFail { msg }
              result (outcome) · abort
   JS → Lua   burn:finish { result } → { ok, pending }     burn:graftCheck {} → { ok, msg }
              burn:abort {}     burn:pain { pain }     burn:close (core)
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  const MM = 0.001, TAU = Math.PI * 2;
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%(?:\.\d+)?[sdf]/, v); }); return s; };
  const pct = v => Math.round(clamp(v, 0, 1) * 100);
  const f1 = v => (Math.round((+v || 0) * 10) / 10).toFixed(1);
  const hash = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const mkCanvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };

  // gameplay tuning; Config.Burn.Game overrides (sent as data.cfg)
  const DEFAULTS = {
    quality: 'high',
    bottleMl: 250, bottles: 2, salineFlow: 14, refillTime: 0.9, salineTemp: 19, jetRadius: 9, target: 31,
    holdTime: 1.4, coolFrac: 0.88, overcool: 24, sootDone: 10, rebound: 1,
    assessCover: 0.6, pressTime: 0.55, diascopeMm: 22,
    pullMm: 7,
    traceTol: 3, traceDone: 0.92,
    graftWidth: 40, speedMin: 10, speedMax: 32, pressureBand: [0.42, 0.68], pressureDrift: 0.32,
    feedPerTurn: 14, crankMax: 2.4,
    stapleSpacing: 11, stapleTol: 3.5,
    stuckDone: 0.9, coverMin: 0.85,
    cooledBelow: 31, sootLeftMax: 25, debridedMin: 0.75, secureAbove: 60, minCoverage: 0.7, minStaples: 0.6, minExcised: 0.7,
    weights: { cool: 35, assess: 15, debride: 25, dressing: 25 },
    graftWeights: { excise: 25, harvest: 20, mesh: 15, graft: 25, dressing: 15 },
    fallbackTime: 14,
  };

  // the belt: one tool per step (key = step number)
  const TOOLS = [
    { key: '1', id: 'saline', step: 1, icon: 'bottle', label: ['tool_saline', 'Saline'] },
    { key: '2', id: 'diascope', step: 2, icon: 'bn-diascope', label: ['tool_diascope', 'Diascope'] },
    { key: '3', id: 'forceps', step: 3, icon: 'forceps', label: ['tool_forceps', 'Forceps'] },
    { key: '4', id: 'knife', step: 4, icon: 'scalpel', label: ['tool_knife', 'Knife'] },
    { key: '5', id: 'dermatome', step: 5, icon: 'bn-dermatome', label: ['tool_dermatome', 'Dermatome'] },
    { key: '6', id: 'mesher', step: 6, icon: 'bn-mesher', label: ['tool_mesher', 'Mesher'] },
    { key: '7', id: 'stapler', step: 7, icon: 'bn-stapler', label: ['tool_stapler', 'Stapler'] },
    { key: '8', id: 'dressing', step: 8, icon: 'bandage', label: ['tool_dressing', 'Dressing'] },
  ];
  const STEP_NAMES = [null, ['sn_1', 'Cool the burn'], ['sn_2', 'Test the depth'], ['sn_3', 'Debride'], ['sn_4', 'Excise the eschar'],
    ['sn_5', 'Harvest the graft'], ['sn_6', 'Mesh the graft'], ['sn_7', 'Apply & staple'], ['sn_8', 'Dress the burn']];

  NZ.addIcons({
    'bn-diascope': '<circle cx="9" cy="15" r="5.5"/><path d="M6.5 13.2a3 3 0 0 1 2.8-1.7"/><path class="a" d="M13 11l7-7" style="stroke:var(--nzi-accent,currentColor)"/><path d="M18.5 3.5l2 2"/>',
    'bn-dermatome': '<path d="M3 17h10v3H3z"/><path d="M5 17l3-6h6l7-6"/><path class="a" d="M3 20.5h10" style="stroke:var(--nzi-accent,currentColor)"/><path d="M14 11l2 2"/>',
    'bn-mesher': '<rect x="3" y="7" width="13" height="10" rx="1.5"/><circle cx="7.5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><path class="a" d="M16 12h3.5v-4" style="stroke:var(--nzi-accent,currentColor)"/><circle cx="19.5" cy="7" r="1.2"/>',
    'bn-stapler': '<path d="M4 9h11l4 3v2H8l-4-2z"/><path d="M8 14l-1.5 5h4L12 14"/><path class="a" d="M17 16v3M20 16v3M17 19h3" style="stroke:var(--nzi-accent,currentColor)"/>',
  });

  /* ═════════════ noise (own, deterministic) ═════════════ */
  function valueNoise(seed) {
    const r = rng(seed), V = new Float32Array(512), P = new Uint16Array(512);
    const p = Array.from({ length: 256 }, (_, i) => i);
    for (let i = 255; i > 0; i--) { const j = Math.floor(r() * (i + 1)); const t = p[i]; p[i] = p[j]; p[j] = t; }
    for (let i = 0; i < 512; i++) { P[i] = p[i & 255]; V[i] = r(); }
    const val = (ix, iy) => V[P[(P[ix & 255] + iy) & 255]];
    return (x, y) => {
      const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
      const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
      const a = val(ix, iy), b = val(ix + 1, iy), c = val(ix, iy + 1), d = val(ix + 1, iy + 1);
      return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
    };
  }
  function fbm(n, x, y, oct = 4, gain = 0.5) {
    let s = 0, a = 1, f = 1, tot = 0;
    for (let i = 0; i < oct; i++) { s += n(x * f, y * f) * a; tot += a; a *= gain; f *= 2.03; }
    return s / tot;
  }
  // jittered-grid worley: { f1, f2, id }
  function worley(seed) {
    const r = rng(seed), J = new Float32Array(1024 * 2), I = new Float32Array(1024);
    for (let i = 0; i < 1024; i++) { J[i * 2] = 0.1 + r() * 0.8; J[i * 2 + 1] = 0.1 + r() * 0.8; I[i] = r(); }
    const out = { f1: 0, f2: 0, id: 0 };
    return (x, y) => {
      const ix = Math.floor(x), iy = Math.floor(y);
      let f1 = 9, f2 = 9, id = 0;
      for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
        const cx = ix + i, cy = iy + j, k = (((cx * 73856093) ^ (cy * 19349663)) >>> 0) & 1023;
        const dx = cx + J[k * 2] - x, dy = cy + J[k * 2 + 1] - y, d = Math.sqrt(dx * dx + dy * dy);
        if (d < f1) { f2 = f1; f1 = d; id = I[k]; } else if (d < f2) f2 = d;
      }
      out.f1 = f1; out.f2 = f2; out.id = id;
      return out;
    };
  }

  /* ═════════════ polygons (patch metres, s → right, t → toward the viewer) ═════════════ */
  function polyArea(P) { let a = 0; for (let i = 0, j = P.length - 1; i < P.length; j = i++) a += (P[j][0] + P[i][0]) * (P[j][1] - P[i][1]); return Math.abs(a / 2); }
  function inPoly(P, x, y) {
    let c = false;
    for (let i = 0, j = P.length - 1; i < P.length; j = i++) {
      const xi = P[i][0], yi = P[i][1], xj = P[j][0], yj = P[j][1];
      if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
    }
    return c;
  }
  // distance to the outline + arc position (0..1) of the nearest point
  function polyNearest(P, x, y, cum) {
    let best = Infinity, at = 0;
    for (let i = 0; i < P.length; i++) {
      const a = P[i], b = P[(i + 1) % P.length];
      const abx = b[0] - a[0], aby = b[1] - a[1], l2 = abx * abx + aby * aby || 1e-12;
      const f = clamp(((x - a[0]) * abx + (y - a[1]) * aby) / l2, 0, 1);
      const d = Math.hypot(x - a[0] - abx * f, y - a[1] - aby * f);
      if (d < best) { best = d; at = cum ? (cum[i] + f * Math.sqrt(l2)) / cum[P.length] : 0; }
    }
    return { d: best, at };
  }
  function polyCum(P) {
    const c = new Float64Array(P.length + 1);
    for (let i = 0; i < P.length; i++) { const a = P[i], b = P[(i + 1) % P.length]; c[i + 1] = c[i] + Math.hypot(b[0] - a[0], b[1] - a[1]); }
    return c;
  }
  function polyCentroid(P) { let x = 0, y = 0; P.forEach(p => { x += p[0]; y += p[1]; }); return [x / P.length, y / P.length]; }
  function polyBox(P, pad = 0) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    P.forEach(p => { x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]); });
    return [x0 - pad, y0 - pad, x1 + pad, y1 + pad];
  }
  // outward offset along vertex normals (outline is roughly star-shaped round its centroid)
  function polyOffset(P, d) {
    const n = P.length, out = [];
    let sgn = 0;
    for (let i = 0, j = n - 1; i < n; j = i++) sgn += (P[j][0] - P[i][0]) * (P[j][1] + P[i][1]);
    sgn = sgn > 0 ? 1 : -1;
    for (let i = 0; i < n; i++) {
      const a = P[(i - 1 + n) % n], b = P[(i + 1) % n];
      let nx = (b[1] - a[1]), ny = -(b[0] - a[0]);
      const l = Math.hypot(nx, ny) || 1;
      nx = nx / l * sgn; ny = ny / l * sgn;
      out.push([P[i][0] - nx * d, P[i][1] - ny * d]);
    }
    // make sure it grew (flip if the orientation guess was wrong)
    return polyArea(out) >= polyArea(P) === d >= 0 ? out : P.map((p, i) => [2 * p[0] - out[i][0], 2 * p[1] - out[i][1]]);
  }
  function blobPoly(cx, cy, R, ax, ay, rot, R2, N = 72) {
    const amps = [], phs = [];
    for (let k = 2; k <= 6; k++) { amps.push((0.05 + R2() * 0.1) / Math.sqrt(k - 1)); phs.push(R2() * TAU); }
    const P = [];
    const ca = Math.cos(rot), sa = Math.sin(rot);
    for (let i = 0; i < N; i++) {
      const th = (i / N) * TAU;
      let r = 1;
      for (let k = 2; k <= 6; k++) r += amps[k - 2] * Math.cos(k * th + phs[k - 2]);
      r += (R2() - 0.5) * 0.03;
      const x = Math.cos(th) * r * R * ax, y = Math.sin(th) * r * R * ay;
      P.push([cx + x * ca - y * sa, cy + x * sa + y * ca]);
    }
    // light smoothing of the jitter
    return P.map((p, i) => { const a = P[(i - 1 + N) % N], b = P[(i + 1) % N]; return [(a[0] + 2 * p[0] + b[0]) / 4, (a[1] + 2 * p[1] + b[1]) / 4]; });
  }

  /* ═════════════ the burn: shape (mirrors the engine's burn wound), zones, blisters, flaps ═════════════
     The engine draws the burn from its own noise texture; the same bytes are read here so the
     gameplay mask (heat, depth tests, coverage) matches the pixels on screen. */
  function burnShape(S, w) {
    const nt = S && S._noiseTex && S._noiseTex.image && S._noiseTex.image.data;
    const N = 256;
    const tex = (ch, u, v) => {
      if (!nt) return 0.5;
      const x = u * N - 0.5, y = v * N - 0.5, x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
      const xa = ((x0 % N) + N) % N, xb = (xa + 1) % N, ya = ((y0 % N) + N) % N, yb = (ya + 1) % N;
      const a = nt[(ya * N + xa) * 4 + ch], b = nt[(ya * N + xb) * 4 + ch], c = nt[(yb * N + xa) * 4 + ch], d = nt[(yb * N + xb) * 4 + ch];
      return (a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy) / 255;
    };
    const c = w.center, rr = w.radii, irr = w.p.irregular, seed = w.seedN;
    const fallbackN = valueNoise(77);
    return (s, t) => {
      const Px = s * 1000, Py = t * 1000;
      const qx = (Px - c[0] * 1000) / Math.max(rr[0] * 1000, 0.1), qy = (Py - c[1] * 1000) / Math.max(rr[1] * 1000, 0.1);
      const d = Math.hypot(qx, qy), ang = Math.atan2(qy, qx);
      const nA = nt ? tex(0, Math.cos(ang) * 0.19 + seed, Math.sin(ang) * 0.19 + seed) : fallbackN(Math.cos(ang) * 2 + 3, Math.sin(ang) * 2);
      const nB = nt ? tex(1, Px * 0.035 + seed * 0.7, Py * 0.035 + seed * 0.7) : fallbackN(Px * 0.05, Py * 0.05);
      return d / Math.max(0.2, 1 + irr * ((nA - 0.5) * 1.3 + (nB - 0.5) * 0.6));
    };
  }

  // Everything that is fixed for this burn (deterministic from the seed): zones, blisters, flaps.
  function planBurn(o) {
    const R = rng(o.seed ^ 0x51ed);
    const { rx, ry, dn, degree, full } = o;
    const cell = 0.0025;
    // burn mask area
    let Aburn = 0;
    for (let t = -ry * 1.5; t <= ry * 1.5; t += cell) for (let s = -rx * 1.5; s <= rx * 1.5; s += cell) if (dn(s, t) < 0.95) Aburn += cell * cell;
    const zones = [];
    if (degree >= 3 && full > 0) {
      const target = Aburn * clamp(full / 100, 0.05, 0.92);
      const shares = full > 58 ? [1] : full > 30 ? (R() < 0.55 ? [0.72, 0.28] : [1]) : [0.6, 0.4];
      for (let z = 0; z < shares.length; z++) {
        const Az = target * shares[z];
        let best = null;
        for (let tries = 0; tries < 40 && !best; tries++) {
          const a = R() * TAU, rd = z === 0 ? Math.sqrt(R()) * 0.28 : 0.35 + R() * 0.25;
          const cx = Math.cos(a) * rd * rx, cy = Math.sin(a) * rd * ry;
          if (dn(cx, cy) > 0.6) continue;
          const ax = 1 + (rx / ry - 1) * 0.35, ay = 1 / ax;
          const shape = blobPoly(0, 0, 1, ax, ay, (R() - 0.5) * 0.6, R);
          const k = Math.sqrt(Az / polyArea(shape));
          let poly = shape.map(p => [cx + p[0] * k, cy + p[1] * k]);
          // shrink until it sits inside the burn and clear of the other zones
          for (let it = 0; it < 40; it++) {
            const inside = poly.every(p => dn(p[0], p[1]) < 0.86);
            const clear = zones.every(Z => poly.every(p => !inPoly(Z.poly, p[0], p[1]) && polyNearest(Z.poly, p[0], p[1]).d > 0.006));
            if (inside && clear) { best = poly; break; }
            poly = poly.map(p => [cx + (p[0] - cx) * 0.94, cy + (p[1] - cy) * 0.94]);
          }
        }
        if (best) {
          const area = polyArea(best);
          zones.push({ id: z, poly: best, area, center: polyCentroid(best), box: polyBox(best, 0.004), found: false, excised: false });
        }
      }
    }
    const inZone = (s, t, pad = 0) => zones.some(Z => inPoly(Z.poly, s, t) || (pad > 0 && polyNearest(Z.poly, s, t).d < pad));
    // blisters: domes on partial-thickness skin
    const blisters = [];
    const nb = degree <= 1 ? 0 : degree === 2 ? 6 + Math.floor(R() * 6) : 3 + Math.floor(R() * 4);
    for (let tries = 0; tries < 400 && blisters.length < nb; tries++) {
      const s = (R() * 2 - 1) * rx * 0.95, t = (R() * 2 - 1) * ry * 0.95;
      const r = (2.4 + R() * R() * 6.5) * MM;
      if (dn(s, t) > 0.82 || inZone(s, t, r + 0.003)) continue;
      if (blisters.some(b => Math.hypot(b.s - s, b.t - t) < b.r + r + 0.0015)) continue;
      blisters.push({ kind: 'blister', s, t, r, h: (0.7 + R() * 0.9) * r * 0.33, removed: false, id: `b${blisters.length}` });
    }
    // sloughed epidermis: loose, curled sheets of dead skin
    const flaps = [];
    const nf = degree <= 1 ? 0 : 2 + Math.floor(R() * 3) + (degree >= 3 ? 1 : 0);
    for (let tries = 0; tries < 300 && flaps.length < nf; tries++) {
      const s = (R() * 2 - 1) * rx * 0.9, t = (R() * 2 - 1) * ry * 0.9;
      const w = (7 + R() * 7) * MM, h = (5 + R() * 5) * MM;
      if (dn(s, t) > 0.78 || inZone(s, t, 0.004)) continue;
      if (flaps.some(f => Math.hypot(f.s - s, f.t - t) < 0.014) || blisters.some(b => Math.hypot(b.s - s, b.t - t) < b.r + 0.006)) continue;
      flaps.push({ kind: 'flap', s, t, w, h, ang: R() * TAU, curl: 0.4 + R() * 0.6, removed: false, id: `f${flaps.length}`, v: Math.floor(R() * 4) });
    }
    // depth-test cells (≈ 6 mm) over the burn
    const cells = [];
    const cs = 0.006;
    for (let t = -ry * 1.3; t <= ry * 1.3; t += cs) for (let s = -rx * 1.3; s <= rx * 1.3; s += cs) {
      if (dn(s, t) < 0.95) cells.push({ s, t, full: inZone(s, t), tested: false });
    }
    // fine sample points: burn (dressing cover), each zone (excision / graft cover)
    const pts = [];
    for (let t = -ry * 1.3; t <= ry * 1.3; t += 0.004) for (let s = -rx * 1.3; s <= rx * 1.3; s += 0.004) if (dn(s, t) < 0.95) pts.push([s, t]);
    zones.forEach(Z => {
      Z.pts = [];
      const b = Z.box;
      for (let t = b[1]; t <= b[3]; t += 0.0025) for (let s = b[0]; s <= b[2]; s += 0.0025) if (inPoly(Z.poly, s, t)) Z.pts.push([s, t]);
    });
    return { Aburn, zones, blisters, flaps, cells, pts, inZone };
  }

  /* ═════════════ heat: 2D surface temperature over the burn (°C) ═════════════
     T = surface, D = deep tissue heat that keeps warming the surface back up (rebound),
     wet = saline film. Explicit diffusion on a grid of ~2 mm cells. */
  class Heat {
    constructor(o) {
      this.s0 = o.s0; this.t0 = o.t0; this.nx = o.nx; this.ny = o.ny;
      this.ds = o.w / (o.nx - 1); this.dt = o.h / (o.ny - 1);
      const n = this.nx * this.ny;
      this.mask = new Float32Array(n); this.T = new Float32Array(n); this.D = new Float32Array(n); this.wet = new Float32Array(n);
      this.tmp = new Float32Array(n);
      this.skin = 33.4;
      this.bed = 29.2;              // burnt skin barely perfuses: once the deep heat is gone it settles below the target
      this.rebound = o.rebound !== undefined ? o.rebound : 1;
      const R = rng(o.seed ^ 0x7e7e), nz = valueNoise(o.seed ^ 0x99);
      let k = 0;
      for (let j = 0; j < this.ny; j++) for (let i = 0; i < this.nx; i++, k++) {
        const s = this.s0 + i * this.ds, t = this.t0 + j * this.dt;
        const d = o.dn(s, t);
        const m = 1 - smooth(0.88, 1.02, d);
        this.mask[k] = m;
        const hot = o.peak - this.skin;
        const prof = (0.62 + 0.38 * (1 - smooth(0, 1, d))) * (0.86 + 0.28 * nz(s * 60, t * 60));
        const zoneHot = o.inZone(s, t) ? 4.5 : 0;
        const margin = (1 - smooth(1.0, 1.4, d)) * (1 - m) * 2.2;     // inflamed margin runs warm
        this.T[k] = this.skin + m * (hot * prof + zoneHot) + margin;
        this.D[k] = this.T[k] + m * (2 + zoneHot * 0.4);
      }
      void R;
      this.cnt = 0; for (let i = 0; i < n; i++) if (this.mask[i] > 0.5) this.cnt++;
    }
    index(s, t) {
      const i = Math.round((s - this.s0) / this.ds), j = Math.round((t - this.t0) / this.dt);
      if (i < 0 || j < 0 || i >= this.nx || j >= this.ny) return -1;
      return j * this.nx + i;
    }
    at(s, t) {
      const x = clamp((s - this.s0) / this.ds, 0, this.nx - 1.001), y = clamp((t - this.t0) / this.dt, 0, this.ny - 1.001);
      const i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j, k = j * this.nx + i;
      const A = this.T;
      return lerp(lerp(A[k], A[k + 1], fx), lerp(A[k + this.nx], A[k + this.nx + 1], fx), fy);
    }
    // jet: { s, t, r (m), temp, rate } | null
    step(dt, jet) {
      const nx = this.nx, ny = this.ny, T = this.T, D = this.D, M = this.mask, W = this.wet, tmp = this.tmp;
      const sub = Math.max(1, Math.ceil(dt / 0.02)), h = dt / sub;
      const kDiff = 1.6, kUp = 0.3 * this.rebound, kDown = 0.42, kPerfB = 0.03, kPerfS = 0.4, kJet = 10, kFilm = 1.4;
      for (let it = 0; it < sub; it++) {
        // diffusion (Neumann edges)
        for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
          const k = j * nx + i;
          const l = i > 0 ? T[k - 1] : T[k], r = i < nx - 1 ? T[k + 1] : T[k], u = j > 0 ? T[k - nx] : T[k], d = j < ny - 1 ? T[k + nx] : T[k];
          tmp[k] = T[k] + kDiff * h * (l + r + u + d - 4 * T[k]);
        }
        for (let k = 0; k < T.length; k++) {
          const m = M[k];
          let t = tmp[k];
          // deep heat rises; cool surface drains the deep reservoir
          t += kUp * m * (D[k] - t) * h;
          D[k] += kDown * m * (t - D[k]) * h;
          // perfusion pulls toward skin temperature (burnt tissue barely perfuses)
          t += m * kPerfB * (this.bed - t) * h + (1 - m) * kPerfS * (this.skin - t) * h;
          // saline film: conducts and evaporates
          if (W[k] > 0.001) { t += kFilm * W[k] * (24 - t) * h - 0.3 * W[k] * h; W[k] = Math.max(0, W[k] - 0.075 * h); }
          T[k] = t;
        }
        if (jet) {
          const r = jet.r, ri = Math.ceil(r * 1.25 / this.ds) + 1, rj = Math.ceil(r * 1.25 / this.dt) + 1;
          const ci = Math.round((jet.s - this.s0) / this.ds), cj = Math.round((jet.t - this.t0) / this.dt);
          for (let j = cj - rj; j <= cj + rj * 4; j++) {
            if (j < 0 || j >= ny) continue;
            for (let i = ci - ri; i <= ci + ri; i++) {
              if (i < 0 || i >= nx) continue;
              const k = j * nx + i;
              const ds = this.s0 + i * this.ds - jet.s, dtt = this.t0 + j * this.dt - jet.t;
              const d = Math.hypot(ds, dtt) / r;
              let w = d < 1.25 ? Math.pow(1 - d / 1.25, 2) : 0;
              // runoff: a band downhill of the stream stays wet
              if (dtt > 0 && Math.abs(ds) < r) w = Math.max(w, 0.45 * (1 - dtt / (r * 4)) * (1 - Math.abs(ds) / r));
              if (w <= 0) continue;
              T[k] += kJet * w * jet.rate * (jet.temp - T[k]) * h;
              W[k] = Math.max(W[k], w);
            }
          }
        }
      }
    }
    stats(target) {
      let s = 0, n = 0, mx = -Infinity, mi = Infinity, ki = 0, below = 0;
      for (let k = 0; k < this.T.length; k++) {
        if (this.mask[k] < 0.5) continue;
        const t = this.T[k];
        s += t; n++;
        if (t > mx) { mx = t; ki = k; }
        if (t < mi) mi = t;
        if (t < target) below++;
      }
      const i = ki % this.nx, j = Math.floor(ki / this.nx);
      return { mean: n ? s / n : this.skin, max: n ? mx : this.skin, min: n ? mi : this.skin, frac: n ? below / n : 1, hot: [this.s0 + i * this.ds, this.t0 + j * this.dt] };
    }
    // cool everything at once (resume after burn care: the surface is already cool)
    settle(temp) { for (let k = 0; k < this.T.length; k++) { const m = this.mask[k]; this.T[k] = lerp(this.T[k], temp, m); this.D[k] = lerp(this.D[k], temp + 1, m); } }
  }

  // thermal palette (cold blue → cyan → green → yellow → red → white), t 0..1
  const PAL = {
    lava: [[0, [8, 10, 46]], [0.16, [24, 54, 168]], [0.32, [10, 156, 210]], [0.48, [36, 196, 120]], [0.62, [236, 214, 44]], [0.78, [240, 106, 24]], [0.9, [214, 30, 38]], [1, [255, 236, 226]]],
    iron: [[0, [4, 4, 16]], [0.2, [60, 10, 110]], [0.4, [160, 24, 120]], [0.6, [228, 80, 40]], [0.8, [250, 176, 30]], [1, [255, 250, 220]]],
    grey: [[0, [10, 10, 12]], [1, [245, 245, 245]]],
  };
  function palLUT(name) {
    const stops = PAL[name] || PAL.lava, lut = new Uint8ClampedArray(256 * 3);
    for (let i = 0; i < 256; i++) {
      const t = i / 255;
      let k = 1;
      while (k < stops.length - 1 && stops[k][0] < t) k++;
      const a = stops[k - 1], b = stops[k], f = clamp((t - a[0]) / (b[0] - a[0] || 1), 0, 1);
      for (let c = 0; c < 3; c++) lut[i * 3 + c] = lerp(a[1][c], b[1][c], f);
    }
    return lut;
  }

  /* ═════════════ procedural textures (canvas) ═════════════ */
  function normalFromHeight(hgt, w, h, strength) {
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), id = c.createImageData(w, h), d = id.data;
    for (let y = 0; y < h; y++) {
      const ym = Math.max(0, y - 1) * w, yp = Math.min(h - 1, y + 1) * w, yc = y * w;
      for (let x = 0; x < w; x++) {
        const xm = Math.max(0, x - 1), xp = Math.min(w - 1, x + 1);
        const dx = (hgt[yc + xp] - hgt[yc + xm]) * strength, dy = (hgt[yp + x] - hgt[ym + x]) * strength;
        const nx = -dx, ny = dy, l = Math.hypot(nx, ny, 1);
        const i = (yc + x) * 4;
        d[i] = (nx / l * 0.5 + 0.5) * 255; d[i + 1] = (ny / l * 0.5 + 0.5) * 255; d[i + 2] = (1 / l * 0.5 + 0.5) * 255; d[i + 3] = 255;
      }
    }
    c.putImageData(id, 0, 0);
    return cv;
  }
  // polygon (patch metres) → soft mask Float32 (0..1) on a w×h canvas over box
  function polyMask(poly, box, w, h, blurPx) {
    const cv = mkCanvas(w, h), c = cv.getContext('2d');
    const sx = w / (box[2] - box[0]), sy = h / (box[3] - box[1]);
    if (blurPx) c.filter = `blur(${blurPx}px)`;
    c.fillStyle = '#fff';
    c.beginPath();
    poly.forEach((p, i) => { const x = (p[0] - box[0]) * sx, y = (p[1] - box[1]) * sy; if (i) c.lineTo(x, y); else c.moveTo(x, y); });
    c.closePath(); c.fill();
    const d = c.getImageData(0, 0, w, h).data, out = new Float32Array(w * h);
    for (let i = 0; i < w * h; i++) out[i] = d[i * 4 + 3] / 255;
    return out;
  }
  const mixC = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  function texSize(box, base = 512) {
    const bw = box[2] - box[0], bh = box[3] - box[1];
    return bw >= bh ? [base, clamp(Math.round(base * bh / bw), 96, base)] : [clamp(Math.round(base * bw / bh), 96, base), base];
  }

  // Full-thickness eschar: dry, leathery and waxy — white-tan to brown, patches of charred crust,
  // fine fissures (domain-warped so they never look like tiles), skin creases, thrombosed vessels
  // under the surface, a dark junction and grey flaking epidermis round the edge.
  function texEschar(Z, seed) {
    const box = Z.box, [w, h] = texSize(box, 512);
    const R = rng(seed), n = valueNoise(seed), n2 = valueNoise(seed ^ 0x55), n3 = valueNoise(seed ^ 0x3c), wy = worley(seed ^ 0x77);
    const mask = polyMask(Z.poly, box, w, h, 0), soft = polyMask(Z.poly, box, w, h, Math.round(w * 0.04));
    const mmX = (box[2] - box[0]) * 1000 / w, mmY = (box[3] - box[1]) * 1000 / h;
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), id = c.createImageData(w, h), d = id.data;
    const hgt = new Float32Array(w * h), rough = mkCanvas(w, h), rc = rough.getContext('2d'), rid = rc.createImageData(w, h), rd = rid.data;
    const WAX = [228, 214, 186], CREAM = [214, 190, 150], TAN = [176, 128, 82], BROWN = [116, 72, 42], CHAR = [42, 28, 20], FISS = [84, 26, 18], GREY = [188, 182, 170], JUNC = [124, 52, 38];
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x, X = x * mmX, Y = y * mmY;      // mm
      const e = soft[i];
      // domain warp so the leathery cells and cracks wander
      const wx = X + (fbm(n3, X * 0.06, Y * 0.06, 3) - 0.5) * 9, wyy = Y + (fbm(n3, X * 0.06 + 9, Y * 0.06, 3) - 0.5) * 9;
      const b1 = fbm(n, X * 0.035, Y * 0.035, 4), b2 = fbm(n2, X * 0.13, Y * 0.13, 3), b3 = n(X * 0.6 + 7, Y * 0.6);
      let col = mixC(WAX, CREAM, smooth(0.3, 0.55, b1));
      col = mixC(col, TAN, smooth(0.5, 0.75, b1 * 0.7 + b2 * 0.4) * 0.9);
      col = mixC(col, BROWN, smooth(0.62, 0.86, b1 * 0.5 + b2 * 0.6) * 0.75);
      // charred crust: patchy, crusty, mostly toward the middle
      const charN = fbm(n2, X * 0.05 + 11, Y * 0.05, 5) + (e - 0.75) * 0.3 + (b3 - 0.5) * 0.08;
      const charA = smooth(0.57, 0.76, charN);
      col = mixC(col, [98, 60, 36], smooth(0.47, 0.62, charN) * (1 - charA) * 0.55);     // scorched halo round the char
      col = mixC(col, mixC(CHAR, [70, 44, 30], b3 * 0.6), charA * 0.94);
      col = mixC(col, [92, 86, 80], charA * smooth(0.6, 0.75, n(X * 0.7 + 21, Y * 0.7)) * 0.35);   // grey ash bloom on the char
      // fissures: thin, irregular, deeper in the crust
      const W1 = wy(wx * 0.22, wyy * 0.22), crack = 1 - smooth(0.0, 0.03 + charA * 0.045, W1.f2 - W1.f1);
      const crackMask = Math.max(smooth(0.42, 0.6, n2(X * 0.06 + 31, Y * 0.06 + 7)), charA * 0.75) * (0.55 + 0.45 * smooth(0.2, 0.7, W1.id));
      const crackA = crack * crackMask * (0.12 + charA * 0.82) * smooth(0.3, 0.7, e);
      col = mixC(col, FISS, crackA);
      // skin creases: faint parallel wrinkles that survived the burn
      const crease = Math.pow(Math.abs(Math.sin((wx * 0.9 + wyy * 0.35) * 0.9 + b2 * 3)), 24) * (1 - charA);
      col = mixC(col, mixC(col, [60, 40, 30], 0.5), crease * 0.12);
      // edge: a dark junction line, then grey flaking dead epidermis
      const junction = smooth(0.18, 0.32, e) * (1 - smooth(0.32, 0.52, e));
      col = mixC(col, JUNC, junction * 0.55);
      const flake = (1 - smooth(0.12, 0.42, e)) * smooth(0.45, 0.62, n(X * 0.45 + 3, Y * 0.45));
      col = mixC(col, GREY, flake * 0.6);
      const gr = (n(X * 3.4, Y * 3.4) - 0.5) * 12 + (b3 - 0.5) * 6;
      // soft, ragged rim: the dark junction and the grey flaking skin fade into the burn round it
      const a = smooth(0.2, 0.5, e + (b2 - 0.5) * 0.22 + (b3 - 0.5) * 0.06) * (mask[i] ? 1 : 0.92);
      const o = i * 4;
      d[o] = col[0] + gr; d[o + 1] = col[1] + gr * 0.9; d[o + 2] = col[2] + gr * 0.8; d[o + 3] = a * 255;
      hgt[i] = 0.5 + b2 * 0.3 + charA * (0.35 + fbm(n, X * 0.9, Y * 0.9, 2) * 0.35) - crackA * 0.9 - crease * 0.06 + flake * 0.2;
      // waxy areas have a dull sheen, charred crust is bone dry
      const ro = clamp(0.58 + charA * 0.36 + crackA * 0.1 - (1 - charA) * (1 - smooth(0.3, 0.6, b1)) * 0.16, 0, 1) * 255;
      rd[o] = ro; rd[o + 1] = ro; rd[o + 2] = ro; rd[o + 3] = 255;
    }
    c.putImageData(id, 0, 0);
    rc.putImageData(rid, 0, 0);
    // thrombosed vessels seen through the waxy skin: thin, branching, slightly blurred
    c.save();
    c.globalCompositeOperation = 'source-atop';
    c.filter = 'blur(0.8px)';
    c.lineCap = 'round';
    const branch = (x, y, a, len, wdt, depth) => {
      if (depth > 4 || len < 4) return;
      c.strokeStyle = `rgba(78,30,44,${0.42 - depth * 0.07})`;
      c.lineWidth = wdt;
      c.beginPath(); c.moveTo(x, y);
      let px = x, py = y;
      for (let k = 0; k < 7; k++) { a += (R() - 0.5) * 0.55; px += Math.cos(a) * len / 7; py += Math.sin(a) * len / 7; c.lineTo(px, py); }
      c.stroke();
      if (R() < 0.8) branch(px, py, a + 0.45 + R() * 0.4, len * 0.6, wdt * 0.66, depth + 1);
      if (R() < 0.6) branch(px, py, a - 0.45 - R() * 0.4, len * 0.55, wdt * 0.6, depth + 1);
    };
    for (let k = 0; k < 5; k++) branch(R() * w, R() * h, R() * TAU, w * (0.16 + R() * 0.14), 1.6 + R() * 1.2, 0);
    c.filter = 'none';
    // embedded soot flecks and a few blistered-off islands
    for (let k = 0; k < 220; k++) { c.fillStyle = `rgba(10,7,6,${0.2 + R() * 0.5})`; c.beginPath(); c.arc(R() * w, R() * h, 0.5 + R() * R() * 2.2, 0, TAU); c.fill(); }
    c.restore();
    return { map: cv, normal: normalFromHeight(hgt, w, h, 3.6), rough, w, h };
  }

  // Excised bed: raw, glistening, punctate bleeders, yellow fat lobules, fibrin, the cut wall.
  function texBed(poly, box, seed) {
    const [w, h] = texSize(box, 512);
    const R = rng(seed), n = valueNoise(seed), wy = worley(seed ^ 0x31);
    const mask = polyMask(poly, box, w, h, 0), soft = polyMask(poly, box, w, h, Math.round(w * 0.02));
    const mmX = (box[2] - box[0]) * 1000 / w, mmY = (box[3] - box[1]) * 1000 / h;
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), id = c.createImageData(w, h), d = id.data;
    const hgt = new Float32Array(w * h);
    const RED = [166, 34, 28], RED2 = [204, 70, 58], FAT = [236, 192, 92], FAT2 = [214, 150, 60], FIB = [232, 214, 172], DERM = [238, 208, 194];
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x, X = x * mmX, Y = y * mmY, e = soft[i];
      const b1 = fbm(n, X * 0.08, Y * 0.08, 4);
      let col = mixC(RED, RED2, smooth(0.3, 0.75, b1));
      // fat lobules where the excision went into the subcutis: polygonal, warped cells packed edge to
      // edge, each a slightly different yellow, split by thin red septa with a tiny vessel in them
      const wX = (fbm(n, X * 0.07 + 11, Y * 0.07, 3) - 0.5) * 3.4, wY = (fbm(n, X * 0.07, Y * 0.07 + 31, 3) - 0.5) * 3.4;
      const L = wy(X * 0.42 + wX, Y * 0.42 + wY), edge = L.f2 - L.f1;
      const lob = smooth(0.01, 0.12, edge), sept = 1 - smooth(0.0, 0.035, edge);
      const fatZ = smooth(0.54, 0.7, fbm(n, X * 0.05 + 20, Y * 0.05, 3)), fatA = fatZ * lob;
      // fat: pale butter-yellow lobules, glossier in the middle, washed over with a thin film of blood
      let fat = mixC(mixC(FAT, FAT2, L.id * 0.8), [246, 222, 150], smooth(0.08, 0.45, edge) * 0.3);
      fat = mixC(fat, [196, 82, 60], smooth(0.35, 0.7, fbm(n, X * 0.18 + 70, Y * 0.18, 3)) * 0.45);
      col = mixC(col, fat, fatA * 0.78);
      col = mixC(col, [128, 22, 16], sept * fatZ * 0.5);
      // fibrin film
      col = mixC(col, FIB, smooth(0.62, 0.78, fbm(n, X * 0.12 + 50, Y * 0.12, 3)) * 0.38);
      // wall shadow and the pale cut edge of the skin
      const wall = 1 - smooth(0.15, 0.6, e);
      col = mixC(col, [70, 10, 8], wall * 0.55);
      const lip = smooth(0.02, 0.12, e) * (1 - smooth(0.12, 0.3, e));
      col = mixC(col, DERM, lip * 0.75);
      const gr = (n(X * 2.5, Y * 2.5) - 0.5) * 18;
      const o = i * 4;
      d[o] = col[0] + gr; d[o + 1] = col[1] + gr * 0.6; d[o + 2] = col[2] + gr * 0.5; d[o + 3] = mask[i] * 255;
      hgt[i] = b1 * 0.4 + fatA * (0.45 + 0.35 * smooth(0.0, 0.3, edge)) - sept * fatZ * 0.25 - wall * 0.8;
    }
    c.putImageData(id, 0, 0);
    // punctate bleeders: dark dots with a small wet halo
    c.save();
    c.globalCompositeOperation = 'source-atop';
    const nd = Math.round(w * h / 1400);
    for (let k = 0; k < nd; k++) {
      const x = R() * w, y = R() * h, r = 0.8 + R() * R() * 3.2;
      const g = c.createRadialGradient(x, y, 0, x, y, r * 2.4);
      g.addColorStop(0, 'rgba(70,4,4,.95)'); g.addColorStop(0.4, 'rgba(110,8,8,.7)'); g.addColorStop(1, 'rgba(140,16,12,0)');
      c.fillStyle = g; c.beginPath(); c.arc(x, y, r * 2.4, 0, TAU); c.fill();
    }
    // a few pools of fresh blood
    for (let k = 0; k < 4; k++) {
      const x = R() * w, y = R() * h, r = w * (0.03 + R() * 0.05);
      const g = c.createRadialGradient(x, y, 0, x, y, r);
      g.addColorStop(0, 'rgba(96,6,6,.75)'); g.addColorStop(1, 'rgba(120,10,8,0)');
      c.fillStyle = g; c.beginPath(); c.ellipse(x, y, r * 1.3, r, R() * 3, 0, TAU); c.fill();
    }
    c.restore();
    return { map: cv, normal: normalFromHeight(hgt, w, h, 2.4), w, h };
  }

  // Split-thickness graft (mm units): raw strip, slit (fresh from the mesher) or expanded (diamond mesh).
  // prof: Float32Array of quality per mm (0 bad .. 1 good), thin: per mm thickness (0 skip .. 1 normal .. 1.6 deep)
  function texGraft(o) {
    const pxmm = o.pxmm || 6, L = Math.max(10, o.length), Wd = o.width * (o.expand || 1);
    const w = Math.min(2048, Math.round(L * pxmm)), h = Math.min(1024, Math.round(Wd * pxmm));
    const kx = L / w, ky = Wd / h;
    const n = valueNoise(o.seed), R = rng(o.seed ^ 0x2a);
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), id = c.createImageData(w, h), d = id.data;
    const hgt = new Float32Array(w * h);
    const PINK = [218, 156, 138], PINK2 = [196, 128, 112], WHITE = [236, 206, 190];
    const expand = o.expand || 1, mode = o.mode || 'raw';
    // diamond lattice in the expanded sheet: cells of pitch px (along L) × py (across)
    const px = o.ratio === '1:3' ? 5.2 : 3.6, py = o.ratio === '1:3' ? 4.2 : 2.6;
    const tears = o.tears || [];
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x, X = x * kx, Y = y * ky;
      const mmI = clamp(Math.floor(X), 0, (o.thin ? o.thin.length : 1) - 1);
      const th = o.thin ? o.thin[mmI] : 1;
      const b = fbm(n, X * 0.35, Y * 0.35, 3), pore = n(X * 3.2, Y * 3.2);
      let col = mixC(PINK, PINK2, smooth(0.35, 0.7, b));
      col = mixC(col, WHITE, clamp(1 - th, 0, 1) * 0.5);           // thin graft is paler, more translucent
      col = mixC(col, [196, 120, 112], clamp(th - 1, 0, 0.6));      // too deep: redder, fat specks
      let a = 1;
      // ragged long edges, wavier where the hand drifted
      const wob = (n(X * 0.25, 3.3) - 0.5) * 1.4 * (o.wobble ? o.wobble[mmI] || 0 : 0.3) + (n(X * 1.7, 9.1) - 0.5) * 0.5;
      const yy = Y / expand;
      if (yy < 0.7 + wob || yy > o.width - 0.7 + wob * 0.6) a = 0;
      if (X < 0.6 || X > L - 0.6) a = 0;
      // skipped spots (too little pressure): holes in the graft
      if (th < 0.35 && n(X * 0.6 + 40, Y * 0.6) > 0.35 + th) a = 0;
      let hh = 0.6 + b * 0.3 - pore * 0.08;
      if (mode === 'slit' || mode === 'mesh') {
        const row = Math.floor(Y / py), off = row % 2 ? px / 2 : 0;
        const cx = ((X + off) % px + px) % px - px / 2, cy = (Y % py) - py / 2;
        if (mode === 'slit') {
          const slit = Math.abs(cy) < 0.18 && Math.abs(cx) < px * 0.36;
          if (slit) { col = mixC(col, [150, 70, 64], 0.7); hh -= 0.5; }
        } else {
          // open diamonds; bridges between them keep the lattice together
          const dmd = Math.abs(cx) / (px * 0.5) + Math.abs(cy) / (py * 0.5);
          const hole = o.ratio === '1:3' ? 0.72 : 0.6;
          if (dmd < hole) a = 0;
          else if (dmd < hole + 0.12) { col = mixC(col, [214, 130, 118], 0.55); hh -= 0.25; }
        }
      }
      for (const tr of tears) {
        const dx = (X - tr.x) / tr.r, dy = (Y - tr.y) / (tr.r * 0.45);
        if (dx * dx + dy * dy < 1 + (n(X, Y) - 0.5) * 0.6) a = 0;
      }
      const gr = (pore - 0.5) * 10;
      const ix = i * 4;
      d[ix] = col[0] + gr; d[ix + 1] = col[1] + gr * 0.8; d[ix + 2] = col[2] + gr * 0.8; d[ix + 3] = a * 255;
      hgt[i] = hh;
    }
    c.putImageData(id, 0, 0);
    void R;
    return { map: cv, normal: normalFromHeight(hgt, w, h, 1.6), w, h, length: L, width: Wd };
  }

  // Donor bed (strip mm units): glistening dermis with dense punctate bleeding; deeper = redder with fat,
  // skips = islands of intact skin (transparent)
  function texDonor(o) {
    const pxmm = 6, L = Math.max(10, o.length), Wd = o.width;
    const w = Math.min(2048, Math.round(L * pxmm)), h = Math.round(Wd * pxmm);
    const n = valueNoise(o.seed ^ 0x77), R = rng(o.seed ^ 0x13);
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), id = c.createImageData(w, h), d = id.data;
    const hgt = new Float32Array(w * h);
    const DERM = [236, 186, 176], DEEP = [190, 58, 48], FAT = [226, 184, 96];
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x, X = x / pxmm, Y = y / pxmm;
      const mmI = clamp(Math.floor(X), 0, o.thin.length - 1);
      const th = o.thin[mmI];
      const b = fbm(n, X * 0.3, Y * 0.3, 3);
      let col = mixC(DERM, DEEP, clamp((th - 0.6) * 0.9 + (b - 0.5) * 0.3, 0, 1));
      col = mixC(col, FAT, clamp(th - 1.25, 0, 0.5) * smooth(0.5, 0.7, n(X * 0.8, Y * 0.8)));
      let a = 1;
      const wob = (n(X * 0.25, 3.3) - 0.5) * 1.4 * (o.wobble[mmI] || 0) + (n(X * 1.7, 9.1) - 0.5) * 0.5;
      if (Y < 0.6 + wob || Y > Wd - 0.6 + wob * 0.6) a = 0;
      if (X > o.cut) a = 0;
      if (th < 0.35 && n(X * 0.6 + 40, Y * 0.6) > 0.35 + th) a = 0;
      const ix = i * 4;
      const gr = (n(X * 2.2, Y * 2.2) - 0.5) * 14;
      d[ix] = col[0] + gr; d[ix + 1] = col[1] + gr * 0.7; d[ix + 2] = col[2] + gr * 0.7; d[ix + 3] = a * 255;
      hgt[i] = b * 0.4;
    }
    c.putImageData(id, 0, 0);
    // pin-point bleeding: the classic dense red dots of a good split-thickness donor site
    c.save(); c.globalCompositeOperation = 'source-atop';
    const nd = Math.round(w * h / 240);
    for (let k = 0; k < nd; k++) {
      const x = R() * w, y = R() * h, th = o.thin[clamp(Math.floor(x / pxmm), 0, o.thin.length - 1)];
      const r = 0.6 + R() * (0.8 + th * 0.8);
      c.fillStyle = `rgba(${150 + R() * 40},${10 + R() * 12},${10 + R() * 10},${0.55 + R() * 0.4})`;
      c.beginPath(); c.arc(x, y, r, 0, TAU); c.fill();
    }
    c.restore();
    return { map: cv, normal: normalFromHeight(hgt, w, h, 1.2), w, h };
  }

  // Loose dead epidermis: four torn, wrinkled, translucent sheet variants in a 2×2 atlas
  function texFlaps(seed) {
    const S2 = 256, cv = mkCanvas(S2 * 2, S2 * 2), c = cv.getContext('2d'), id = c.createImageData(S2 * 2, S2 * 2), d = id.data;
    const n = valueNoise(seed), n2 = valueNoise(seed ^ 0x19), wy = worley(seed ^ 0x2d);
    for (let v = 0; v < 4; v++) {
      const ox = (v % 2) * S2, oy = Math.floor(v / 2) * S2, ph = v * 17.3;
      for (let y = 0; y < S2; y++) for (let x = 0; x < S2; x++) {
        const u = x / S2 - 0.5, w = y / S2 - 0.5;
        const ang = Math.atan2(w, u), r = Math.hypot(u / 1.15, w / 0.82);
        // torn outline: low-frequency lobes + frayed fine edge
        const edge = 0.36 + (n(Math.cos(ang) * 1.6 + ph, Math.sin(ang) * 1.6) - 0.5) * 0.16 + (n2(x * 0.12 + ph, y * 0.12) - 0.5) * 0.05;
        const inside = r < edge;
        const i = ((oy + y) * S2 * 2 + ox + x) * 4;
        if (!inside) { d[i + 3] = 0; continue; }
        const X = x + ph * 10, Y = y;
        const b = fbm(n, X * 0.02, Y * 0.02, 4), crease = 1 - smooth(0.0, 0.05, (() => { const W = wy(X * 0.035, Y * 0.06); return W.f2 - W.f1; })());
        let col = mixC([208, 198, 180], [176, 160, 140], smooth(0.35, 0.7, b));
        col = mixC(col, [204, 132, 118], smooth(0.55, 0.78, fbm(n2, X * 0.03, Y * 0.03, 3)) * 0.55);   // the pink underside showing through the thin parts
        col = mixC(col, [110, 90, 76], crease * 0.5);
        col = mixC(col, [96, 72, 58], smooth(0.6, 0.75, n2(X * 0.08 + 3, Y * 0.08)) * 0.25);            // soot caught in the dead skin
        const rim = smooth(edge - 0.05, edge, r);
        col = mixC(col, [232, 222, 206], rim * 0.55);
        d[i] = col[0]; d[i + 1] = col[1]; d[i + 2] = col[2]; d[i + 3] = (0.86 - rim * 0.3) * 255;
      }
    }
    c.putImageData(id, 0, 0);
    return cv;
  }

  // Partial-thickness surface for the skin shader patch (see patchSkin), drawn over the burn box:
  //   map    R deep-partial pallor (mottled ivory)   G sloughed epidermis (grey-white membrane)
  //          B weeping serum (gloss)
  //   normal relief: rolled membrane edges, wrinkles in the dead skin, papillary dermis
  // Superficial (1st degree) burns get no membranes and only a faint sheen.
  function texBurnDetail(o) {
    const { box, dn, zones, blisters, flaps, degree, seed } = o;
    const bw = box[2] - box[0], bh = box[3] - box[1];
    const base = 640;
    const w = bw >= bh ? base : Math.max(160, Math.round(base * bw / bh)), h = bw >= bh ? Math.max(160, Math.round(base * bh / bw)) : base;
    const n = valueNoise(seed ^ 0x1b), n2 = valueNoise(seed ^ 0x2c), n3 = valueNoise(seed ^ 0x3d), wy = worley(seed ^ 0x4e);
    const mmX = bw * 1000 / w, mmY = bh * 1000 / h;
    // soft "near full thickness" mask: the deep-partial ring hugs the eschar
    const near = new Float32Array(w * h);
    zones.forEach(Z => {
      const m = polyMask(polyOffset(Z.poly, 0.002), box, w, h, Math.max(2, Math.round(7 / mmX)));
      for (let i = 0; i < near.length; i++) near[i] = Math.max(near[i], m[i]);
    });
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), id = c.createImageData(w, h), d = id.data;
    const hgt = new Float32Array(w * h);
    const deg = clamp(degree | 0, 1, 3);
    const memAmt = deg <= 1 ? 0 : 1, palAmt = deg <= 1 ? 0 : deg === 2 ? 0.62 : 0.95;
    for (let y = 0; y < h; y++) {
      const t = box[1] + (y + 0.5) / h * bh;
      for (let x = 0; x < w; x++) {
        const s = box[0] + (x + 0.5) / w * bw, i = y * w + x, o4 = i * 4;
        const dd = dn(s, t);
        const core = 1 - smooth(0.86, 1.0, dd);
        if (core <= 0.001) { d[o4] = 0; d[o4 + 1] = 0; d[o4 + 2] = 0; d[o4 + 3] = 255; hgt[i] = 0.5; continue; }
        const X = x * mmX, Y = y * mmY;
        // domain warp: dead skin tears along wandering lines, never round
        const wx = X + (fbm(n3, X * 0.045, Y * 0.045, 3) - 0.5) * 14, wyy = Y + (fbm(n3, X * 0.045 + 13, Y * 0.045, 3) - 0.5) * 14;
        // deep partial: pale, reticulated ivory, toward the middle and around the eschar
        const pal0 = (1 - dd) * 0.85 + (fbm(n2, X * 0.04, Y * 0.04, 4) - 0.5) * 0.9 + near[i] * 0.7 - 0.18;
        const mot = smooth(0.38, 0.66, fbm(n2, wx * 0.2 + 5, wyy * 0.2, 3));
        const pal = smooth(0.25, 0.85, pal0) * (0.35 + 0.65 * mot) * palAmt;
        // sloughed epidermis: sheets in the mid band and a peeling rim at the edge
        const band = smooth(0.18, 0.42, dd) * (1 - smooth(0.9, 0.99, dd)) + (1 - smooth(0.0, 0.25, dd)) * 0.45;
        const sheetN = fbm(n, wx * 0.055, wyy * 0.055, 4) + (band - 1) * 0.35;
        const sheet = smooth(0.585, 0.61, sheetN);
        const rimLine = smooth(0.56, 0.585, sheetN) * (1 - smooth(0.585, 0.61, sheetN));    // torn edge where it lifts
        const peel = smooth(0.8, 0.88, dd) * (1 - smooth(0.93, 0.985, dd)) * smooth(0.4, 0.6, n(X * 0.09 + 4, Y * 0.09));
        let mem = clamp(Math.max(sheet * 0.92, peel * 0.85), 0, 1) * memAmt;
        // weeping serum: wet where the dermis is open, drier on the deep (pale) parts and on dead skin
        let weep = core * (0.92 - pal * 0.5 - mem * 0.3) * (0.82 + 0.18 * n(X * 0.3, Y * 0.3));
        if (deg <= 1) weep = core * 0.16;
        // relief (mm-ish): rolled edges stand up, wrinkles inside the sheets, papillae on the dermis
        const W = wy(wx * 0.32, wyy * 0.5);
        const wrinkle = (1 - smooth(0.0, 0.06, W.f2 - W.f1)) * sheet;
        const pap = (n(X * 2.2, Y * 2.2) - 0.5) * 0.08 * (1 - mem);
        hgt[i] = 0.5 + mem * 0.22 + rimLine * 0.55 * memAmt + peel * 0.3 * memAmt - wrinkle * 0.16 + pap;
        d[o4] = clamp(pal, 0, 1) * 255; d[o4 + 1] = mem * core * 255; d[o4 + 2] = clamp(weep, 0, 1) * 255; d[o4 + 3] = 255;
      }
    }
    // intact blisters: no loose skin under the dome, a puckered collar round it
    const sx = w / bw, sy = h / bh;
    const hole = (cx, cy, rr, collar) => {
      const x0 = Math.max(0, Math.floor((cx - rr * 1.6 - box[0]) * sx)), x1 = Math.min(w - 1, Math.ceil((cx + rr * 1.6 - box[0]) * sx));
      const y0 = Math.max(0, Math.floor((cy - rr * 1.6 - box[1]) * sy)), y1 = Math.min(h - 1, Math.ceil((cy + rr * 1.6 - box[1]) * sy));
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
        const s = box[0] + (x + 0.5) / sx, t = box[1] + (y + 0.5) / sy, q = Math.hypot(s - cx, t - cy) / rr;
        const i = y * w + x, o4 = i * 4;
        const inner = 1 - smooth(0.92, 1.08, q), ring = collar ? smooth(0.95, 1.1, q) * (1 - smooth(1.15, 1.5, q)) : 0;
        d[o4 + 1] = Math.max(d[o4 + 1] * (1 - inner), ring * 150 * memAmt);
        // under an intact roof the dermis looks pale and yellowish through the serum; under a dead sheet it is raw
        d[o4] = collar ? lerp(d[o4], 190, inner) : d[o4] * (1 - inner * 0.7);
        hgt[i] = lerp(hgt[i], 0.5, inner) + ring * 0.25 * memAmt;
      }
    };
    blisters.forEach(b => { if (!b.removed) hole(b.s, b.t, b.r, true); });
    flaps.forEach(f => { if (!f.removed) hole(f.s, f.t, Math.max(f.w, f.h) * 0.42, false); });
    c.putImageData(id, 0, 0);
    return { map: cv, normal: normalFromHeight(hgt, w, h, 2.4), w, h, box };
  }

  // the GLSL the burn puts into the engine's skin shader (replaces its partial-thickness colouring)
  const BURN_GLSL_PARS = `
    uniform sampler2D tBnDet; uniform sampler2D tBnNrm; uniform vec4 uBnBox; uniform float uBnOn; uniform float uBnHot;
    vec2 bnQ; float bnIn; float bnWeep;`;
  const BURN_GLSL_COL = `
    bnQ = (nzaP - uBnBox.xy) / uBnBox.zw;
    bnIn = step(0.0, bnQ.x) * step(bnQ.x, 1.0) * step(0.0, bnQ.y) * step(bnQ.y, 1.0) * uBnOn;
    vec3 bnD = texture2D(tBnDet, bnQ).rgb * bnIn;
    float bnCore = smoothstep(0.34, 0.5, nzaBs);
    // erythema: blotchy, stronger while the burn is still hot
    vec3 bnEryC = nzaCol * mix(vec3(1.0, 0.5, 0.43), vec3(0.94, 0.36, 0.32), nzaN2.g) * mix(1.04, 0.97, uBnHot);
    nzaCol = mix(nzaCol, bnEryC, smoothstep(0.0, 0.3, nzaBs) * mix(0.8, 1.0, uBnHot));
    // open dermis: wet cherry-salmon with punctate capillaries; deep partial pales to mottled ivory
    vec3 bnDerm = mix(vec3(0.74, 0.15, 0.13), vec3(0.86, 0.27, 0.22), nzaN3.r) * (0.9 + 0.2 * nzaN4.r);
    bnDerm = mix(bnDerm, vec3(0.42, 0.035, 0.035), (1.0 - smoothstep(0.0, 0.11, nzaN4.b)) * 0.55);
    vec3 bnPale = mix(vec3(0.88, 0.7, 0.58), vec3(0.8, 0.44, 0.36), nzaN3.g * 0.8);
    bnDerm = mix(bnDerm, bnPale, bnD.r);
    // dead epidermis: thin grey-white sheet, the dermis shows pink through the thin parts
    vec3 bnMem = mix(vec3(0.8, 0.76, 0.68), vec3(0.66, 0.6, 0.53), nzaN3.b);
    bnMem = mix(bnMem, bnDerm, 0.22 * (1.0 - nzaN2.r));
    vec3 bnSurf = mix(bnDerm, bnMem, bnD.g);
    vec3 nzaFull = mix(vec3(0.80, 0.72, 0.56), vec3(0.42, 0.28, 0.16), nzaN2.r);
    nzaCol = mix(nzaCol, bnSurf, bnCore * max(bnIn, 0.0));
    nzaCol = mix(nzaCol, mix(vec3(0.82, 0.30, 0.26), vec3(0.93, 0.84, 0.76), 0.3), bnCore * (1.0 - bnIn));
    nzaCol = mix(nzaCol, nzaFull, smoothstep(0.66, 0.86, nzaBs));
    bnWeep = bnD.b * bnCore;`;

  // Hydrogel burn dressing (replaces the engine's generic dressing print): non-woven border with
  // perforations and a generic product line, a cool translucent gel pad with its mesh liner.
  function texBurnDressing(wM, hM, pwM, phM, seed) {
    const pxm = 8000, w = Math.round(wM * pxm), h = Math.round(hM * pxm);
    const cv = mkCanvas(w, h), c = cv.getContext('2d'), R = rng(seed);
    const rc = Math.min(w, h) * 0.12;
    const rrect = (x, y, ww, hh, r) => { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + ww, y, x + ww, y + hh, r); c.arcTo(x + ww, y + hh, x, y + hh, r); c.arcTo(x, y + hh, x, y, r); c.arcTo(x, y, x + ww, y, r); c.closePath(); };
    c.clearRect(0, 0, w, h);
    c.save(); rrect(0.5, 0.5, w - 1, h - 1, rc); c.clip();
    c.fillStyle = '#f1efe9'; c.fillRect(0, 0, w, h);
    c.lineCap = 'round';
    for (let i = 0; i < w * h / 60; i++) {
      const x = R() * w, y = R() * h, a = R() * TAU, L = 3 + R() * 8;
      c.strokeStyle = `rgba(${R() < 0.5 ? '255,255,255' : '176,172,164'},${0.16 + R() * 0.22})`; c.lineWidth = 0.5 + R() * 0.5;
      c.beginPath(); c.moveTo(x, y); c.lineTo(x + Math.cos(a) * L, y + Math.sin(a) * L); c.stroke();
    }
    c.fillStyle = 'rgba(140,136,128,.2)';
    for (let y = 6; y < h; y += 10) for (let x = 6 + ((y / 10) % 2) * 5; x < w; x += 10) { c.beginPath(); c.arc(x, y, 0.8, 0, TAU); c.fill(); }
    // gel pad
    const pw = pwM * pxm, ph = phM * pxm, px = (w - pw) / 2, py = (h - ph) / 2;
    c.save();
    c.shadowColor = 'rgba(0,40,50,.25)'; c.shadowBlur = 12;
    rrect(px, py, pw, ph, 18); c.fillStyle = '#9ccbe0'; c.fill();
    c.restore();
    c.save(); rrect(px, py, pw, ph, 18); c.clip();
    const gr = c.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, Math.max(pw, ph) * 0.7);
    gr.addColorStop(0, '#c8e6f2'); gr.addColorStop(0.7, '#a2cde2'); gr.addColorStop(1, '#84b6cf');
    c.fillStyle = gr; c.fillRect(px, py, pw, ph);
    // mesh liner
    c.strokeStyle = 'rgba(255,255,255,.42)'; c.lineWidth = 1.2;
    for (let x = px; x < px + pw; x += 7) { c.beginPath(); c.moveTo(x, py); c.lineTo(x, py + ph); c.stroke(); }
    for (let y = py; y < py + ph; y += 7) { c.beginPath(); c.moveTo(px, y); c.lineTo(px + pw, y); c.stroke(); }
    // trapped micro-bubbles and gel sheen
    for (let i = 0; i < pw * ph / 900; i++) { const x = px + R() * pw, y = py + R() * ph, r = 0.8 + R() * R() * 3.2; c.strokeStyle = `rgba(255,255,255,${0.4 + R() * 0.4})`; c.lineWidth = 0.9; c.beginPath(); c.arc(x, y, r, 0, TAU); c.stroke(); }
    const sh = c.createLinearGradient(px, py, px + pw, py + ph);
    sh.addColorStop(0, 'rgba(255,255,255,.22)'); sh.addColorStop(0.35, 'rgba(255,255,255,0)'); sh.addColorStop(1, 'rgba(0,50,60,.12)');
    c.fillStyle = sh; c.fillRect(px, py, pw, ph);
    c.restore();
    c.strokeStyle = 'rgba(70,120,124,.45)'; c.lineWidth = 1.5; rrect(px, py, pw, ph, 18); c.stroke();
    // generic product print on the border
    const fs = Math.max(9, Math.round(Math.min(w, h) * 0.022));
    c.fillStyle = 'rgba(70,82,86,.6)'; c.font = `600 ${fs}px Lexend, sans-serif`; c.textBaseline = 'middle';
    c.fillText('HYDROGEL BURN DRESSING · STERILE R', rc * 0.6, h - (h - ph) / 4);
    c.textAlign = 'right'; c.font = `500 ${fs}px "JetBrains Mono", monospace`;
    c.fillText(`${Math.round(wM * 100)} × ${Math.round(hM * 100)} cm · LOT 4H2207`, w - rc * 0.6, (h - ph) / 4);
    c.restore();
    return cv;
  }

  // round soft sprite (steam)
  function texSoft() {
    const cv = mkCanvas(64, 64), c = cv.getContext('2d');
    const g = c.createRadialGradient(32, 32, 0, 32, 32, 32);
    g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.45, 'rgba(255,255,255,.35)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = g; c.fillRect(0, 0, 64, 64);
    return cv;
  }

  // printed labels for the instruments (generic device labelling only)
  function texLabel(kind) {
    const W = 512, H = 256, cv = mkCanvas(W, H), c = cv.getContext('2d');
    const bars = (x, y, wdt, hh, seed) => { const R = rng(seed); let px = x; c.fillStyle = '#16191b'; while (px < x + wdt) { const bw = 1 + Math.floor(R() * 3.2); if (R() > 0.42) c.fillRect(px, y, bw, hh); px += bw + 1; } };
    if (kind === 'bottle') {
      c.fillStyle = '#f5f7f7'; c.fillRect(0, 0, W, H);
      c.fillStyle = '#0a8f85'; c.fillRect(0, 0, W, 30);
      c.fillStyle = '#e5484d'; c.fillRect(0, H - 26, W, 26);
      c.fillStyle = '#fff'; c.font = '700 15px Lexend, sans-serif'; c.fillText('IRRIGATION SOLUTION', 18, 21);
      c.fillText('NOT FOR INJECTION', 18, H - 8);
      c.fillStyle = '#16191b'; c.font = '700 40px Lexend, sans-serif'; c.fillText('Sodium Chloride', 18, 80);
      c.font = '600 54px Lexend, sans-serif'; c.fillStyle = '#0a8f85'; c.fillText('0.9%', 18, 138);
      c.font = '500 18px Lexend, sans-serif'; c.fillStyle = '#3c4246'; c.fillText('w/v · sterile · single use', 150, 133);
      c.font = '600 20px "JetBrains Mono", monospace'; c.fillStyle = '#16191b'; c.fillText('250 mL', 18, 176);
      c.font = '500 13px "JetBrains Mono", monospace'; c.fillStyle = '#5b6266'; c.fillText('LOT 24B117   EXP 2028-04   2-25 °C', 18, 202);
      bars(330, 150, 160, 52, 7);
      // fill-level scale
      c.strokeStyle = '#16191b'; c.lineWidth = 1.4; c.font = '500 11px "JetBrains Mono", monospace'; c.fillStyle = '#16191b';
      for (let i = 0; i <= 5; i++) { const y = 40 + i * 30; c.beginPath(); c.moveTo(W - 34, y); c.lineTo(W - 18, y); c.stroke(); c.fillText(String(250 - i * 50), W - 66, y + 4); }
    } else if (kind === 'dermatome') {
      c.fillStyle = '#e9ecee'; c.fillRect(0, 0, W, H);
      c.fillStyle = '#1b1f22'; c.font = '700 34px Lexend, sans-serif'; c.fillText('DM-40', 22, 64);
      c.font = '500 18px Lexend, sans-serif'; c.fillStyle = '#4a5156'; c.fillText('ELECTRIC DERMATOME', 22, 94);
      c.strokeStyle = '#1b1f22'; c.lineWidth = 2; c.font = '600 14px "JetBrains Mono", monospace'; c.fillStyle = '#1b1f22';
      for (let i = 0; i <= 10; i++) { const x = 30 + i * 42; c.beginPath(); c.moveTo(x, 150); c.lineTo(x, i % 2 ? 166 : 176); c.stroke(); if (i % 2 === 0) c.fillText((i * 0.075).toFixed(2), x - 16, 200); }
      c.fillStyle = '#0a8f85'; c.fillRect(22, 118, 160, 6);
      c.fillStyle = '#5b6266'; c.font = '500 13px "JetBrains Mono", monospace'; c.fillText('mm   SN 40-31872', 22, 236);
    } else if (kind === 'stapler') {
      c.fillStyle = '#eef1f2'; c.fillRect(0, 0, W, H);
      c.fillStyle = '#0a8f85'; c.fillRect(0, 0, 18, H);
      c.fillStyle = '#16191b'; c.font = '700 40px Lexend, sans-serif'; c.fillText('35W', 44, 70);
      c.font = '500 19px Lexend, sans-serif'; c.fillStyle = '#4a5156'; c.fillText('SKIN STAPLER · 35 STAPLES', 44, 104);
      c.font = '600 15px "JetBrains Mono", monospace'; c.fillStyle = '#16191b'; c.fillText('STERILE EO   SINGLE USE', 44, 150);
      c.fillStyle = '#e5a50a'; c.beginPath(); c.moveTo(44, 220); c.lineTo(66, 182); c.lineTo(88, 220); c.closePath(); c.fill();
      c.fillStyle = '#16191b'; c.font = '700 22px Lexend, sans-serif'; c.fillText('!', 61, 214);
      c.font = '500 14px Lexend, sans-serif'; c.fillText('Align the arrow with the wound edge', 100, 208);
    } else if (kind === 'mesher') {
      c.fillStyle = '#c9d0d4'; c.fillRect(0, 0, W, H);
      const g = c.createLinearGradient(0, 0, W, H); g.addColorStop(0, 'rgba(255,255,255,.25)'); g.addColorStop(1, 'rgba(0,0,0,.18)');
      c.fillStyle = g; c.fillRect(0, 0, W, H);
      c.fillStyle = '#23282b'; c.font = '700 46px Lexend, sans-serif'; c.fillText('GM-2', 26, 82);
      c.font = '600 22px Lexend, sans-serif'; c.fillText('GRAFT MESHER', 26, 118);
      c.font = '500 16px "JetBrains Mono", monospace'; c.fillStyle = '#3a4246'; c.fillText('FEED →   TURN CLOCKWISE', 26, 170);
      c.fillText('SN GM2-0418   AUTOCLAVE 134 °C', 26, 204);
    } else if (kind === 'c15' || kind === 'c3') {
      // ribbed carrier board: grip tab with the ratio code on the left, a diamond-grooved bed,
      // a millimetre rule along the near edge and small print — no big printed ratio
      const tone = kind === 'c3' ? '#c23a3f' : '#0a8f85';
      c.fillStyle = '#e9edee'; c.fillRect(0, 0, W, H);
      c.fillStyle = tone; c.fillRect(0, 0, 64, H);
      c.save(); c.translate(42, H / 2); c.rotate(-Math.PI / 2);
      c.fillStyle = '#fff'; c.font = '700 26px "JetBrains Mono", monospace'; c.textAlign = 'center';
      c.fillText(kind === 'c3' ? 'C-3.0' : 'C-1.5', 0, 0);
      c.restore();
      c.strokeStyle = 'rgba(255,255,255,.45)'; c.lineWidth = 2;
      for (let y = 18; y < H - 10; y += 14) { c.beginPath(); c.moveTo(8, y); c.lineTo(20, y); c.stroke(); }
      // grooved bed
      c.save(); c.beginPath(); c.rect(84, 22, W - 104, H - 86); c.clip();
      c.fillStyle = '#dde3e5'; c.fillRect(84, 22, W - 104, H - 86);
      c.strokeStyle = 'rgba(40,52,58,.22)'; c.lineWidth = 1.2;
      const step = kind === 'c3' ? 9 : 13;
      for (let k = -H; k < W + H; k += step) { c.beginPath(); c.moveTo(84 + k, 22); c.lineTo(84 + k + H, 22 + H); c.stroke(); c.beginPath(); c.moveTo(84 + k, 22 + H); c.lineTo(84 + k + H, 22); c.stroke(); }
      c.restore();
      c.strokeStyle = 'rgba(0,0,0,.25)'; c.lineWidth = 1.5; c.strokeRect(84, 22, W - 104, H - 86);
      // rule
      c.strokeStyle = '#2a3034'; c.fillStyle = '#2a3034'; c.font = '500 10px "JetBrains Mono", monospace';
      for (let i = 0; i <= 40; i++) { const x = 90 + i * 10; c.lineWidth = i % 5 ? 1 : 1.6; c.beginPath(); c.moveTo(x, H - 60); c.lineTo(x, H - 60 + (i % 10 ? (i % 5 ? 5 : 8) : 11)); c.stroke(); if (i % 10 === 0) c.fillText(String(i), x - 4, H - 36); }
      c.fillStyle = '#4b5357'; c.font = '600 12px Lexend, sans-serif';
      c.fillText(kind === 'c3' ? 'MESH CARRIER · EXPANSION 3.0' : 'MESH CARRIER · EXPANSION 1.5', 90, H - 14);
      c.fillStyle = tone; c.beginPath(); c.moveTo(W - 46, H - 24); c.lineTo(W - 28, H - 17); c.lineTo(W - 46, H - 10); c.closePath(); c.fill();
    }
    return cv;
  }

  // plain-weave drape tile
  function texWeave(seed) {
    const N = 128, cv = mkCanvas(N, N), c = cv.getContext('2d'), id = c.createImageData(N, N), d = id.data, n = valueNoise(seed);
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const tx = (x % 8) / 8, ty = (y % 8) / 8, over = (Math.floor(x / 8) + Math.floor(y / 8)) % 2;
      const v = over ? 0.75 + 0.25 * Math.sin(ty * Math.PI) : 0.75 + 0.25 * Math.sin(tx * Math.PI);
      const k = (v * 0.85 + n(x * 0.2, y * 0.2) * 0.15) * 255, i = (y * N + x) * 4;
      d[i] = d[i + 1] = d[i + 2] = k; d[i + 3] = 255;
    }
    c.putImageData(id, 0, 0);
    return cv;
  }

  /* ═════════════ 3D helpers (three.js r149; everything here is freed by bin.dispose()) ═════════════ */
  function makeBin() {
    const set = new Set();
    return {
      own(x) { if (x) set.add(x); return x; },
      dispose() { set.forEach(x => { try { x.dispose(); } catch (e) { /* gone */ } }); set.clear(); },
      kill(obj) {
        if (!obj) return;
        if (obj.parent) obj.parent.remove(obj);
        obj.traverse(o => {
          if (o.geometry) { try { o.geometry.dispose(); } catch (e) { /* gone */ } set.delete(o.geometry); }
          if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => {
            if (m.userData && m.userData.shared) return;
            for (const k in m) { const v = m[k]; if (v && v.isTexture && !(v.userData && v.userData.shared)) { v.dispose(); set.delete(v); } }
            m.dispose(); set.delete(m);
          });
        });
      },
    };
  }
  function canvasTex(bin, cv, srgb = true, shared = false) {
    const THREE = window.THREE;
    const t = bin.own(new THREE.CanvasTexture(cv));
    if (srgb) t.encoding = THREE.sRGBEncoding;
    t.anisotropy = 4;
    if (shared) t.userData.shared = true;
    return t;
  }
  function makeMats(bin) {
    const THREE = window.THREE;
    const o = m => { bin.own(m); m.userData.shared = true; return m; };
    return {
      steel: o(new THREE.MeshStandardMaterial({ color: 0xe2e7ea, metalness: 1, roughness: 0.18 })),
      satin: o(new THREE.MeshStandardMaterial({ color: 0xc4cbd0, metalness: 1, roughness: 0.34 })),
      brushed: o(new THREE.MeshStandardMaterial({ color: 0xaeb6bb, metalness: 0.95, roughness: 0.42 })),
      darkSteel: o(new THREE.MeshStandardMaterial({ color: 0x5c6469, metalness: 1, roughness: 0.4 })),
      poly: o(new THREE.MeshPhysicalMaterial({ color: 0xeef1f1, roughness: 0.38, clearcoat: 0.4, clearcoatRoughness: 0.3 })),
      polyGrey: o(new THREE.MeshPhysicalMaterial({ color: 0xc9cfd2, roughness: 0.5, clearcoat: 0.25 })),
      graphite: o(new THREE.MeshPhysicalMaterial({ color: 0x2a2f33, roughness: 0.55, clearcoat: 0.2 })),
      rubber: o(new THREE.MeshStandardMaterial({ color: 0x1d2124, roughness: 0.7 })),
      teal: o(new THREE.MeshPhysicalMaterial({ color: 0x08afa2, roughness: 0.32, clearcoat: 0.6, clearcoatRoughness: 0.2 })),
      tealGlow: o(new THREE.MeshStandardMaterial({ color: 0x0fd4c4, emissive: 0x0fd4c4, emissiveIntensity: 0.0, roughness: 0.3 })),
      pet: o(new THREE.MeshPhysicalMaterial({ color: 0xf4fbff, roughness: 0.06, transparent: true, opacity: 0.26, clearcoat: 1, clearcoatRoughness: 0.04, depthWrite: false })),
      glass: o(new THREE.MeshPhysicalMaterial({ color: 0xeaf6ff, roughness: 0.02, transparent: true, opacity: 0.2, clearcoat: 1, clearcoatRoughness: 0.02, depthWrite: false, side: THREE.DoubleSide })),
      fluid: o(new THREE.MeshPhysicalMaterial({ color: 0xcfeaff, roughness: 0.08, transparent: true, opacity: 0.32, depthWrite: false })),
      clear: o(new THREE.MeshPhysicalMaterial({ color: 0xf4fbff, roughness: 0.05, transparent: true, opacity: 0.3, clearcoat: 1, depthWrite: false })),
      amber: o(new THREE.MeshPhysicalMaterial({ color: 0xe5a50a, roughness: 0.4, clearcoat: 0.5 })),
      ink: o(new THREE.MeshStandardMaterial({ color: 0x4a2276, roughness: 0.55, transparent: true, opacity: 0.88, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4 })),
      cut: o(new THREE.MeshPhysicalMaterial({ color: 0x5a0806, roughness: 0.2, clearcoat: 1, clearcoatRoughness: 0.1, polygonOffset: true, polygonOffsetFactor: -5 })),
    };
  }
  const lathe = (pts, seg = 40) => new window.THREE.LatheGeometry(pts.map(p => new window.THREE.Vector2(p[0], p[1])), seg);
  const tubeGeo = (pts, r, seg = 40, rad = 8) => new window.THREE.TubeGeometry(new window.THREE.CatmullRomCurve3(pts.map(p => (p.isVector3 ? p : new window.THREE.Vector3(p[0], p[1], p[2] || 0))), false, 'centripetal'), seg, r, rad, false);
  function addMesh(bin, parent, g, m, cast = true) { const me = new window.THREE.Mesh(bin.own(g), m); me.castShadow = cast; me.receiveShadow = true; parent.add(me); return me; }
  // loft an elliptical section along +Y: rows [{ y, w, t, x?, z? }]
  function loftRound(rows, seg = 16) {
    const THREE = window.THREE, g = new THREE.BufferGeometry(), pos = [], idx = [];
    rows.forEach(r => { for (let k = 0; k < seg; k++) { const a = (k / seg) * TAU; pos.push((r.x || 0) + Math.cos(a) * r.w / 2, r.y, (r.z || 0) + Math.sin(a) * r.t / 2); } });
    for (let i = 0; i < rows.length - 1; i++) for (let k = 0; k < seg; k++) { const a = i * seg + k, b = i * seg + ((k + 1) % seg), c = a + seg, d = b + seg; idx.push(a, d, b, a, c, d); }
    const n = pos.length / 3, r0 = rows[0], r1 = rows[rows.length - 1];
    pos.push(r0.x || 0, r0.y, r0.z || 0, r1.x || 0, r1.y, r1.z || 0);
    for (let k = 0; k < seg; k++) { idx.push(n, k, (k + 1) % seg); const o = (rows.length - 1) * seg; idx.push(n + 1, o + (k + 1) % seg, o + k); }
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
    return g;
  }

  // A grid that lies on the skin: centre [s, t], size [w, h] (m), angle (rad, screen), lift(lx, ly) (m above the skin).
  // uv (0,0) bottom-left ↔ canvas bottom-left; canvas top row ↔ ly = -h/2 (screen up).
  function conformGeo(S, o, geo) {
    const THREE = window.THREE;
    const nx = o.n[0], ny = o.n[1], w = o.size[0], h = o.size[1], ca = Math.cos(o.angle || 0), sa = Math.sin(o.angle || 0);
    const N = nx * ny;
    let pos, nor, uv;
    if (geo) { pos = geo.attributes.position.array; nor = geo.attributes.normal.array; }
    else {
      geo = new THREE.BufferGeometry();
      pos = new Float32Array(N * 3); nor = new Float32Array(N * 3); uv = new Float32Array(N * 2);
      const idx = [];
      for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) { const a = j * nx + i, b = a + 1, c = a + nx, d = c + 1; idx.push(a, c, b, b, c, d); }
      for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) { const k = j * nx + i; uv[k * 2] = i / (nx - 1); uv[k * 2 + 1] = 1 - j / (ny - 1); }
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3).setUsage(THREE.DynamicDrawUsage));
      geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3).setUsage(THREE.DynamicDrawUsage));
      geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      geo.setIndex(idx);
    }
    const tmp = {};
    for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
      const k = j * nx + i;
      const lx = (i / (nx - 1) - 0.5) * w, ly = (j / (ny - 1) - 0.5) * h;
      const s = o.c[0] + lx * ca - ly * sa, t = o.c[1] + lx * sa + ly * ca;
      const r = S._surfaceAtST(s, t, tmp);
      const lift = typeof o.lift === 'function' ? o.lift(lx, ly, i, j) : (o.lift || 0.0002);
      pos[k * 3] = r.point.x + r.normal.x * lift; pos[k * 3 + 1] = r.point.y + r.normal.y * lift; pos[k * 3 + 2] = r.point.z + r.normal.z * lift;
      nor[k * 3] = r.normal.x; nor[k * 3 + 1] = r.normal.y; nor[k * 3 + 2] = r.normal.z;
    }
    if (o.computeNormals) {
      geo.computeVertexNormals();
      // keep them pointing away from the skin
      const c0 = S._surfaceAtST(o.c[0], o.c[1], {}).normal, na = geo.attributes.normal.array;
      let dot = 0;
      for (let k = 0; k < N; k++) dot += na[k * 3] * c0.x + na[k * 3 + 1] * c0.y + na[k * 3 + 2] * c0.z;
      if (dot < 0) for (let k = 0; k < na.length; k++) na[k] = -na[k];
    }
    geo.attributes.position.needsUpdate = true; geo.attributes.normal.needsUpdate = true;
    geo.computeBoundingSphere();
    return geo;
  }
  // a thin band that follows a polyline on the skin (closed outline or open path), uv.x = arc length 0..1
  function ribbonGeo(S, pts, width, lift, closed) {
    const THREE = window.THREE, n = pts.length, pos = [], nor = [], uv = [], idx = [];
    const m = closed ? n + 1 : n;
    const cum = [0];
    for (let i = 1; i < m; i++) { const a = pts[(i - 1) % n], b = pts[i % n]; cum.push(cum[i - 1] + Math.hypot(b[0] - a[0], b[1] - a[1])); }
    const L = cum[m - 1] || 1;
    for (let i = 0; i < m; i++) {
      const p = pts[i % n], a = pts[closed ? (i - 1 + n) % n : Math.max(0, i - 1)], b = pts[closed ? (i + 1) % n : Math.min(n - 1, i + 1)];
      let dx = b[0] - a[0], dy = b[1] - a[1];
      const l = Math.hypot(dx, dy) || 1; dx /= l; dy /= l;
      for (const sd of [-1, 1]) {
        const r = S._surfaceAtST(p[0] - dy * width * 0.5 * sd, p[1] + dx * width * 0.5 * sd, {});
        pos.push(r.point.x + r.normal.x * lift, r.point.y + r.normal.y * lift, r.point.z + r.normal.z * lift);
        nor.push(r.normal.x, r.normal.y, r.normal.z);
        uv.push(cum[i] / L, sd < 0 ? 0 : 1);
      }
    }
    // wound so the faces point out of the skin (toward the camera)
    for (let i = 0; i < m - 1; i++) { const a = i * 2, b = a + 1, c = a + 2, d = a + 3; idx.push(a, b, c, b, d, c); }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    return g;
  }
  // soft-edged ink line alpha (v across the band)
  function texInk() {
    const cv = mkCanvas(64, 16), c = cv.getContext('2d'), g = c.createLinearGradient(0, 0, 0, 16);
    g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.3, 'rgba(255,255,255,.9)'); g.addColorStop(0.7, 'rgba(255,255,255,.9)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = g; c.fillRect(0, 0, 64, 16);
    return cv;
  }
  function texDisc(inner = 0.72) {
    const cv = mkCanvas(128, 128), c = cv.getContext('2d'), g = c.createRadialGradient(64, 64, 0, 64, 64, 64);
    g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(inner, 'rgba(255,255,255,.85)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = g; c.fillRect(0, 0, 128, 128);
    return cv;
  }

  /* ═════════════ instruments (tip at the origin, handle along +Y — the engine's tool convention) ═════════════ */
  function mkTool(S, bin, name, built, pose) {
    const THREE = window.THREE;
    const t = Object.assign(built, {
      name, pose: Object.assign({}, pose), press: 0,
      _p: new THREE.Vector3(), _q: new THREE.Quaternion(), _init: false,
    });
    t.tipWorld = () => t.group.getWorldPosition(new THREE.Vector3());
    t.group.visible = false;
    t.group.traverse(c => { if (c.isMesh && c.castShadow !== false) c.castShadow = true; });
    S.scene.add(t.group);
    return t;
  }

  // Irrigation bottle (upside down while pouring): nozzle at the origin; set({ fill 0..1, squeeze 0..1 })
  function buildBottle(bin, M) {
    const THREE = window.THREE, g = new THREE.Group();
    addMesh(bin, g, lathe([[0, 0], [0.0009, 0.0003], [0.0013, 0.006], [0.0021, 0.019], [0.0042, 0.03], [0.0045, 0.0335], [0, 0.0335]], 28), M.poly);
    const capM = M.teal;
    addMesh(bin, g, lathe([[0, 0.033], [0.0122, 0.0338], [0.0128, 0.0356], [0.0128, 0.0505], [0.0118, 0.052], [0, 0.052]], 40), capM);
    for (let i = 0; i < 30; i++) {
      const r = addMesh(bin, g, new THREE.BoxGeometry(0.0011, 0.0125, 0.0009), capM, false), a = (i / 30) * TAU;
      r.position.set(Math.cos(a) * 0.0129, 0.043, Math.sin(a) * 0.0129); r.rotation.y = -a;
    }
    const shell = new THREE.Group(); g.add(shell);
    const prof = [[0.0114, 0.052], [0.0124, 0.0565], [0.0205, 0.066], [0.0288, 0.0775], [0.0325, 0.09], [0.0329, 0.19], [0.0312, 0.198], [0.0242, 0.2035], [0.004, 0.2048], [0, 0.205]];
    const pet = addMesh(bin, shell, lathe(prof, 56), M.pet, false);
    pet.renderOrder = 4;
    // moulded rings on the bottle
    for (const y of [0.1, 0.178]) { const ring = addMesh(bin, shell, new THREE.TorusGeometry(0.0331, 0.0005, 6, 56), M.pet, false); ring.rotation.x = Math.PI / 2; ring.position.y = y; }
    const fluidG = new THREE.Group(); shell.add(fluidG);
    const neck = addMesh(bin, fluidG, lathe([[0, 0.052], [0.0108, 0.0525], [0.0118, 0.0565], [0.0195, 0.0662], [0.0276, 0.0775], [0.0309, 0.09], [0, 0.09]], 40), M.fluid, false);
    neck.renderOrder = 2;
    const col = addMesh(bin, fluidG, new THREE.CylinderGeometry(0.0312, 0.0312, 1, 48).translate(0, 0.5, 0), M.fluid, false);
    col.position.y = 0.09; col.renderOrder = 2;
    const meniscus = addMesh(bin, fluidG, new THREE.CircleGeometry(0.0312, 48), M.fluid, false);
    meniscus.rotation.x = -Math.PI / 2; meniscus.renderOrder = 2;
    const lab = addMesh(bin, shell, new THREE.CylinderGeometry(0.03335, 0.03335, 0.074, 56, 1, true, -0.2, Math.PI * 1.35),
      bin.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(bin, texLabel('bottle')), roughness: 0.42, clearcoat: 0.5 })), false);
    lab.position.y = 0.139;
    const api = {
      group: g, fill: 1,
      set(p) {
        if (p.fill !== undefined) {
          api.fill = clamp(p.fill, 0, 1);
          const hgt = api.fill * 0.1;
          col.visible = hgt > 0.0005; col.scale.y = Math.max(0.0001, hgt);
          neck.visible = api.fill > 0.001;
          meniscus.position.y = 0.09 + hgt; meniscus.visible = hgt > 0.0005;
        }
        if (p.squeeze !== undefined) { const s = 1 - p.squeeze * 0.06; shell.scale.set(s, 1, s); }
      },
    };
    api.set({ fill: 1 });
    return api;
  }

  // Diascope: clear glass disc in a steel bezel on an angled handle; origin = centre of the glass underside
  function buildDiascope(bin, M) {
    const THREE = window.THREE, g = new THREE.Group(), r = 0.011;
    const disc = addMesh(bin, g, new THREE.CylinderGeometry(r, r, 0.0032, 56).translate(0, 0.0016, 0), M.glass, false);
    disc.renderOrder = 4;
    const bez = addMesh(bin, g, new THREE.TorusGeometry(r + 0.0004, 0.0012, 12, 56), M.steel);
    bez.rotation.x = Math.PI / 2; bez.position.y = 0.0028;
    // engraved reticle on the glass (measuring circles)
    for (const rr of [0.004, 0.0075]) {
      const ring = addMesh(bin, g, new THREE.TorusGeometry(rr, 0.00012, 4, 48), M.darkSteel, false);
      ring.rotation.x = Math.PI / 2; ring.position.y = 0.00325;
    }
    const neck = [new THREE.Vector3(r + 0.0006, 0.0028, 0), new THREE.Vector3(r + 0.008, 0.008, 0), new THREE.Vector3(r + 0.016, 0.02, 0), new THREE.Vector3(r + 0.022, 0.034, 0)];
    addMesh(bin, g, tubeGeo(neck, 0.0016, 24, 10), M.satin);
    const grip = new THREE.Group(); g.add(grip);
    grip.position.set(r + 0.022, 0.034, 0);
    grip.rotation.z = -0.45;
    addMesh(bin, grip, new THREE.CylinderGeometry(0.0042, 0.0046, 0.07, 24).translate(0, 0.035, 0), M.brushed);
    for (let i = 0; i < 12; i++) { const k = addMesh(bin, grip, new THREE.TorusGeometry(0.00445, 0.00042, 6, 24), M.darkSteel, false); k.rotation.x = Math.PI / 2; k.position.y = 0.012 + i * 0.0036; }
    addMesh(bin, grip, new THREE.SphereGeometry(0.0046, 20, 12).translate(0, 0.07, 0), M.brushed);
    return { group: g, set() {} };
  }

  // Electric dermatome: blade head (rotated to sit flat on the skin), motor body, cable.
  // set({ on, tilt }) · update(dt) runs the blade.
  function buildDermatome(bin, M, tilt) {
    const THREE = window.THREE, g = new THREE.Group();
    const head = new THREE.Group(); g.add(head);
    head.rotation.x = tilt;
    addMesh(bin, head, new THREE.BoxGeometry(0.056, 0.0075, 0.02).translate(0, 0.00375, -0.004), M.darkSteel);
    // bevelled guard on the leading edge and a brushed top cover, so the head reads as machined steel
    addMesh(bin, head, new THREE.CylinderGeometry(0.0034, 0.0034, 0.056, 20).rotateZ(Math.PI / 2).translate(0, 0.0034, 0.0062), M.brushed);
    addMesh(bin, head, new THREE.BoxGeometry(0.052, 0.0012, 0.016).translate(0, 0.0081, -0.005), M.brushed);
    for (let i = 0; i < 9; i++) addMesh(bin, head, new THREE.BoxGeometry(0.0004, 0.0003, 0.0035).translate(-0.02 + i * 0.005, 0.0089, -0.009), M.graphite, false);
    const blade = new THREE.Group(); head.add(blade);
    addMesh(bin, blade, new THREE.BoxGeometry(0.05, 0.0005, 0.012).translate(0, 0.0009, 0.0035), M.steel);
    addMesh(bin, blade, new THREE.BoxGeometry(0.05, 0.0003, 0.0012).translate(0, 0.0008, 0.0098), M.steel);
    // width plate with screws, depth lever
    addMesh(bin, head, new THREE.BoxGeometry(0.046, 0.0014, 0.009).translate(0, 0.0083, 0.002), M.steel);
    for (const x of [-0.019, 0.019]) addMesh(bin, head, new THREE.CylinderGeometry(0.0013, 0.0013, 0.0008, 16).translate(x, 0.0094, 0.002), M.darkSteel, false);
    const lev = addMesh(bin, head, new THREE.BoxGeometry(0.0022, 0.0022, 0.016).translate(0, 0, 0.008), M.teal);
    lev.position.set(0.0295, 0.0055, -0.006); lev.rotation.x = -0.35;
    addMesh(bin, head, new THREE.CylinderGeometry(0.0036, 0.0036, 0.004, 24).rotateZ(Math.PI / 2).translate(0.0295, 0.0045, -0.006), M.darkSteel);
    // neck & body
    addMesh(bin, g, loftRound([{ y: 0.004, w: 0.048, t: 0.016, z: -0.004 }, { y: 0.02, w: 0.04, t: 0.024, z: -0.002 }, { y: 0.034, w: 0.033, t: 0.033 }], 20), M.darkSteel);
    addMesh(bin, g, new THREE.CylinderGeometry(0.0168, 0.0172, 0.142, 40).translate(0, 0.104, 0), M.brushed);
    // rubber grip sleeve with a teal thumb switch
    addMesh(bin, g, new THREE.CylinderGeometry(0.0176, 0.0176, 0.064, 40, 1, true).translate(0, 0.1, 0), M.rubber, false);
    addMesh(bin, g, new THREE.BoxGeometry(0.008, 0.014, 0.004).translate(0, 0.062, 0.0175), M.teal);
    for (const y of [0.07, 0.09, 0.11, 0.13]) { const b = addMesh(bin, g, new THREE.TorusGeometry(0.0172, 0.0013, 8, 40), M.rubber, false); b.rotation.x = Math.PI / 2; b.position.y = y; }
    const lab = addMesh(bin, g, new THREE.CylinderGeometry(0.01735, 0.01735, 0.045, 40, 1, true, Math.PI * 0.2, Math.PI * 0.9),
      bin.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(bin, texLabel('dermatome')), roughness: 0.4, clearcoat: 0.4 })), false);
    lab.position.y = 0.154;
    const led = addMesh(bin, g, new THREE.TorusGeometry(0.0171, 0.0009, 8, 40), bin.own(M.tealGlow.clone()), false);
    led.rotation.x = Math.PI / 2; led.position.y = 0.04;
    addMesh(bin, g, lathe([[0.0172, 0.175], [0.0168, 0.18], [0.012, 0.186], [0.006, 0.188], [0, 0.1885]], 32), M.graphite);
    addMesh(bin, g, new THREE.CylinderGeometry(0.0045, 0.006, 0.016, 20).translate(0, 0.195, 0), M.rubber);
    addMesh(bin, g, tubeGeo([[0, 0.2, 0], [0, 0.24, -0.006], [0.01, 0.3, -0.03], [0.03, 0.38, -0.06], [0.04, 0.5, -0.08]], 0.0032, 40, 8), M.rubber);
    // the graft strip curling up over the head (grows while cutting)
    const stripG = new THREE.Group(); head.add(stripG);
    const api = {
      group: g, on: false, ph: 0, strip: null, stripGroup: stripG,
      set(p) {
        if (p.on !== undefined) { api.on = !!p.on; led.material.emissiveIntensity = api.on ? 2.2 : 0.0; }
      },
      update(dt) {
        if (api.on) { api.ph += dt * 140; blade.position.x = Math.sin(api.ph) * 0.0006; } else blade.position.x = 0;
      },
    };
    return api;
  }

  // Skin stapler: nose at the origin; set({ fire 0..1 })
  function buildStapler(bin, M) {
    const THREE = window.THREE, g = new THREE.Group();
    addMesh(bin, g, loftRound([{ y: 0, w: 0.0075, t: 0.0028, z: 0.0006 }, { y: 0.006, w: 0.01, t: 0.005, z: 0.001 }, { y: 0.016, w: 0.016, t: 0.0095, z: 0.002 }], 16), M.satin);
    const arrow = addMesh(bin, g, new THREE.ConeGeometry(0.0018, 0.004, 3).rotateX(Math.PI).translate(0, 0.004, 0.0024), M.teal, false);
    arrow.scale.z = 0.3;
    addMesh(bin, g, loftRound([
      { y: 0.014, w: 0.017, t: 0.012, z: 0.002 }, { y: 0.03, w: 0.028, t: 0.022, z: 0.005 }, { y: 0.07, w: 0.032, t: 0.027, z: 0.007 },
      { y: 0.105, w: 0.031, t: 0.026, z: 0.0065 }, { y: 0.118, w: 0.024, t: 0.02, z: 0.005 },
    ], 24), M.poly);
    const win = addMesh(bin, g, new THREE.BoxGeometry(0.014, 0.034, 0.004).translate(0, 0.045, 0.0185), M.clear, false);
    win.renderOrder = 4;
    for (let i = 0; i < 9; i++) addMesh(bin, g, new THREE.BoxGeometry(0.009, 0.0007, 0.0012).translate(0, 0.031 + i * 0.0033, 0.0176), M.steel, false);
    const lab = addMesh(bin, g, new THREE.PlaneGeometry(0.03, 0.052), bin.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(bin, texLabel('stapler')), roughness: 0.4, clearcoat: 0.5 })), false);
    lab.position.set(0.0161, 0.075, 0.007); lab.rotation.y = Math.PI / 2;
    const trig = new THREE.Group(); g.add(trig);
    trig.position.set(0, 0.03, -0.006);
    addMesh(bin, trig, loftRound([{ y: 0, w: 0.016, t: 0.006 }, { y: 0.04, w: 0.02, t: 0.008, z: -0.01 }, { y: 0.075, w: 0.018, t: 0.007, z: -0.016 }], 14), M.teal);
    return { group: g, set(p) { if (p.fire !== undefined) trig.rotation.x = -0.32 + p.fire * 0.3; } };
  }

  // one placed skin staple: centre [s, t], dir = [ds, dt] across the graft edge (unit)
  function stapleMesh(S, bin, M, c, dir) {
    const THREE = window.THREE;
    const sp = S._surfaceAtST(c[0], c[1], {}), n = sp.normal;
    const Ts = new THREE.Vector3(), Tt = new THREE.Vector3();
    S._tangents(c[0], c[1], Ts, Tt);
    const across = Ts.clone().multiplyScalar(dir[0]).addScaledVector(Tt, dir[1]).normalize();
    const half = 0.0026, up = 0.00055, down = -0.0012;
    const P = (a, h) => sp.point.clone().addScaledVector(across, a).addScaledVector(n, h);
    const pts = [P(-half, down), P(-half, up * 0.6), P(-half * 0.8, up), P(0, up * 1.08), P(half * 0.8, up), P(half, up * 0.6), P(half, down)];
    const me = new THREE.Mesh(bin.own(tubeGeo(pts, 0.00026, 36, 6)), M.steel);
    me.castShadow = true;
    S.scene.add(me);
    return me;
  }

  /* ═════════════ the mesher bench (own three.js scene, drawn with the donor scene's renderer) ═════════════
     Feed runs along +x through the rollers at x = 0; the crank turns about +z on the near side. */
  function buildBench(bin, env, o) {
    const THREE = window.THREE, M = makeMats(bin);
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x050607);
    if (env) scene.environment = env;
    const cam = new THREE.PerspectiveCamera(30, 16 / 9, 0.01, 5);
    const view = { yaw: -0.12, pitch: 0.92, dist: 0.42, tx: 0.01, ty: 0.02, tz: 0.012 };
    const placeCam = () => {
      const cp = Math.cos(view.pitch), sp = Math.sin(view.pitch);
      cam.position.set(view.tx + Math.sin(view.yaw) * cp * view.dist, view.ty + sp * view.dist, view.tz + Math.cos(view.yaw) * cp * view.dist);
      cam.lookAt(view.tx, view.ty, view.tz);
      cam.updateMatrixWorld();
    };
    // lights: the same warm operating lamp + cool room bounce as the skin scenes
    const key = new THREE.SpotLight(0xfff0e0, 1.25, 0, 0.55, 0.85, 0);
    key.position.set(0.16, 0.85, 0.36); key.target.position.set(0, 0, 0);
    key.castShadow = true; key.shadow.mapSize.set(2048, 2048); key.shadow.bias = -0.00015; key.shadow.normalBias = 0.0006; key.shadow.radius = 3;
    key.shadow.camera.near = 0.3; key.shadow.camera.far = 2;
    const key2 = new THREE.SpotLight(0xfff6ec, 0.45, 0, 0.6, 1, 0);
    key2.position.set(-0.4, 0.7, 0.2); key2.target.position.set(0, 0, 0);
    const fill = new THREE.SpotLight(0xdde8ff, 0.3, 0, 0.7, 1, 0);
    fill.position.set(0.3, 0.4, -0.5); fill.target.position.set(0, 0, 0);
    const hemi = new THREE.HemisphereLight(0xdbe6ec, 0x2a1d18, 0.22);
    scene.add(key, key.target, key2, key2.target, fill, fill.target, hemi);

    // drape with folds
    const weave = texWeave(5), wnH = new Float32Array(128 * 128);
    { const d = weave.getContext('2d').getImageData(0, 0, 128, 128).data; for (let i = 0; i < wnH.length; i++) wnH[i] = d[i * 4] / 255; }
    const wa = canvasTex(bin, weave), wn = canvasTex(bin, normalFromHeight(wnH, 128, 128, 2.2), false);
    for (const t of [wa, wn]) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(70, 50); }
    const clothG = new THREE.PlaneGeometry(1.4, 1.0, 120, 86);
    const n = valueNoise(31), gp = clothG.attributes.position;
    for (let i = 0; i < gp.count; i++) {
      const x = gp.getX(i), y = gp.getY(i);
      let z = 0;
      z += Math.max(0, Math.sin(x * 9 + y * 3.2 + 1.2)) * 0.006 + Math.max(0, Math.sin(-x * 4.1 + y * 11 + 0.3)) * 0.004;
      z += (fbm(n, x * 3 + 4, y * 3, 3) - 0.5) * 0.016;
      z *= smooth(0.12, 0.3, Math.hypot(x, y * 1.3));     // flat under the mesher
      gp.setZ(i, z);
    }
    clothG.computeVertexNormals();
    const cloth = addMesh(bin, scene, clothG, bin.own(new THREE.MeshPhysicalMaterial({ color: 0x2b7d89, map: wa, normalMap: wn, normalScale: new THREE.Vector2(0.7, 0.7), roughness: 0.93, sheen: 0.7, sheenRoughness: 0.8, sheenColor: new THREE.Color(0x9fe6e0) })), false);
    cloth.rotation.x = -Math.PI / 2;

    // ── mesher body
    const dev = new THREE.Group(); scene.add(dev);
    addMesh(bin, dev, new THREE.BoxGeometry(0.16, 0.008, 0.118).translate(0, 0.004, 0), M.brushed);
    for (const x of [-0.07, 0.07]) for (const z of [-0.05, 0.05]) addMesh(bin, dev, new THREE.CylinderGeometry(0.006, 0.0065, 0.004, 16).translate(x, -0.001, z), M.rubber);
    for (const z of [-0.05, 0.05]) {
      addMesh(bin, dev, new THREE.BoxGeometry(0.05, 0.062, 0.012).translate(0, 0.039, z), M.satin);
      // bearing caps for both rollers
      for (const y of [0.0215, 0.0455]) addMesh(bin, dev, new THREE.CylinderGeometry(0.0085, 0.0085, 0.004, 28).rotateX(Math.PI / 2).translate(0, y, z + Math.sign(z) * 0.008), M.steel);
      // tension screws on top
      addMesh(bin, dev, new THREE.CylinderGeometry(0.0042, 0.0042, 0.006, 20).translate(0, 0.073, z), M.darkSteel);
      addMesh(bin, dev, new THREE.BoxGeometry(0.0009, 0.0015, 0.007).translate(0, 0.0762, z), M.rubber, false);
    }
    const plate = addMesh(bin, dev, new THREE.PlaneGeometry(0.042, 0.021), bin.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(bin, texLabel('mesher')), roughness: 0.35, metalness: 0.4, clearcoat: 0.5 })), false);
    plate.position.set(0, 0.04, 0.0562);
    // rollers: bottom smooth, top with circular cutting blades
    const rollBot = new THREE.Group(); rollBot.position.set(0, 0.0215, 0); dev.add(rollBot);
    addMesh(bin, rollBot, new THREE.CylinderGeometry(0.0102, 0.0102, 0.088, 40).rotateX(Math.PI / 2), M.satin);
    for (let i = 0; i < 8; i++) { const r = addMesh(bin, rollBot, new THREE.TorusGeometry(0.0103, 0.00025, 4, 40), M.darkSteel, false); r.position.z = -0.04 + i * 0.0115; }
    const rollTop = new THREE.Group(); rollTop.position.set(0, 0.0455, 0); dev.add(rollTop);
    addMesh(bin, rollTop, new THREE.CylinderGeometry(0.0074, 0.0074, 0.088, 32).rotateX(Math.PI / 2), M.darkSteel);
    const discG = bin.own(new THREE.CylinderGeometry(0.0112, 0.0112, 0.00055, 44).rotateX(Math.PI / 2));
    const nDisc = 52, discs = new THREE.InstancedMesh(discG, M.steel, nDisc);
    const mtx = new THREE.Matrix4();
    for (let i = 0; i < nDisc; i++) { mtx.makeTranslation(0, 0, -0.041 + i * (0.082 / (nDisc - 1))); discs.setMatrixAt(i, mtx); }
    discs.castShadow = true; rollTop.add(discs);
    // slot marks on the blades so the turning reads
    for (let k = 0; k < 6; k++) { const s = addMesh(bin, rollTop, new THREE.BoxGeometry(0.0016, 0.0016, 0.083), M.darkSteel, false); const a = k / 6 * TAU; s.position.set(Math.cos(a) * 0.0108, Math.sin(a) * 0.0108, 0); s.rotation.z = a; }
    // feed tables
    addMesh(bin, dev, new THREE.BoxGeometry(0.07, 0.0025, 0.088).translate(-0.047, 0.0315, 0), M.brushed);
    addMesh(bin, dev, new THREE.BoxGeometry(0.07, 0.0025, 0.088).translate(0.047, 0.0315, 0), M.brushed);
    for (const x of [-0.08, 0.08]) addMesh(bin, dev, new THREE.BoxGeometry(0.004, 0.006, 0.09).translate(x, 0.0335, 0), M.satin);
    // crank (near side, turns about +z)
    const hub = new THREE.Vector3(0, 0.0455, 0.07);
    addMesh(bin, dev, new THREE.CylinderGeometry(0.0072, 0.0072, 0.012, 28).rotateX(Math.PI / 2).translate(0, 0.0455, 0.063), M.steel);
    const crank = new THREE.Group(); crank.position.copy(hub); dev.add(crank);
    addMesh(bin, crank, new THREE.CylinderGeometry(0.0098, 0.0098, 0.006, 32).rotateX(Math.PI / 2), M.satin);
    addMesh(bin, crank, loftRound([{ y: 0, w: 0.012, t: 0.005 }, { y: 0.042, w: 0.008, t: 0.0045 }], 12).rotateZ(0), M.satin);
    const knobG = new THREE.Group(); knobG.position.set(0, 0.044, 0.003); crank.add(knobG);
    addMesh(bin, knobG, new THREE.CylinderGeometry(0.0022, 0.0022, 0.006, 16).rotateX(Math.PI / 2).translate(0, 0, 0.003), M.steel);
    addMesh(bin, knobG, lathe([[0, 0], [0.0058, 0.001], [0.0062, 0.006], [0.0056, 0.02], [0.0044, 0.0235], [0, 0.024]], 28).rotateX(Math.PI / 2).translate(0, 0, 0.006), M.teal);

    // carriers: the chosen one feeds the graft; the other lies on the drape
    const mkCarrier = kind => {
      const grp = new THREE.Group();
      addMesh(bin, grp, new THREE.BoxGeometry(0.15, 0.0014, 0.072), M.poly);
      const top = addMesh(bin, grp, new THREE.PlaneGeometry(0.15, 0.072), bin.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(bin, texLabel(kind)), roughness: 0.4, clearcoat: 0.4 })), false);
      top.rotation.x = -Math.PI / 2; top.position.y = 0.00072;
      for (let i = 0; i < 30; i++) { const r = addMesh(bin, grp, new THREE.BoxGeometry(0.0008, 0.0005, 0.058), M.polyGrey, false); r.position.set(-0.05 + i * 0.0033, 0.001, 0.002); }
      return grp;
    };
    const carriers = { '1:1.5': mkCarrier('c15'), '1:3': mkCarrier('c3') };
    Object.values(carriers).forEach(c => scene.add(c));
    // the graft on the carrier: raw part before the rollers, slit part after (clip planes at x = 0)
    const feedGroup = new THREE.Group(); scene.add(feedGroup);
    const clipIn = [new THREE.Plane(new THREE.Vector3(-1, 0, 0), 0)], clipOut = [new THREE.Plane(new THREE.Vector3(1, 0, 0), 0)];
    let rawMesh = null, slitMesh = null, Lg = 0.08, Wg = 0.04, carrierL = 0.15;

    // set dressing: kidney dish with saline, the dermatome put down after the harvest
    const dish = new THREE.Group(); scene.add(dish);
    addMesh(bin, dish, lathe([[0, 0], [0.03, 0.0005], [0.045, 0.006], [0.052, 0.016], [0.0545, 0.019], [0.0538, 0.0195], [0.05, 0.0165], [0.043, 0.008], [0.03, 0.002], [0, 0.0015]], 48), M.steel);
    const pool = addMesh(bin, dish, new THREE.CircleGeometry(0.044, 40), M.fluid, false);
    pool.rotation.x = -Math.PI / 2; pool.position.y = 0.0075;
    dish.scale.set(1.5, 1, 0.85); dish.position.set(-0.2, 0, -0.1); dish.rotation.y = 0.4;
    // put down flat behind the mesher: head toward the bench, body and cable away from it
    const derm = buildDermatome(bin, M, 0);
    const dermHold = new THREE.Group();
    derm.group.rotation.set(-Math.PI / 2, 0, 0);
    dermHold.add(derm.group);
    dermHold.rotation.y = -1.12;
    dermHold.position.set(0.105, 0.0174, -0.125);
    scene.add(dermHold);
    derm.group.traverse(c => { if (c.isMesh) c.castShadow = true; });

    const api = {
      scene, cam, hub, view, dev,
      ratio: '1:1.5',
      resize(w, h) { cam.aspect = w / Math.max(1, h); cam.updateProjectionMatrix(); },
      setGraft(rawTex, slitTex, lenMm, widMm) {
        if (rawMesh) bin.kill(rawMesh);
        if (slitMesh) bin.kill(slitMesh);
        Lg = lenMm * MM; Wg = widMm * MM;
        carrierL = 0.15;
        const g = new THREE.PlaneGeometry(Lg, Wg).rotateX(-Math.PI / 2);
        const mIn = bin.own(new THREE.MeshPhysicalMaterial({ map: rawTex, roughness: 0.36, clearcoat: 0.7, clearcoatRoughness: 0.2, sheen: 0.5, sheenColor: new THREE.Color(1, 0.9, 0.86), alphaTest: 0.5, side: THREE.DoubleSide, clippingPlanes: clipIn }));
        const mOut = bin.own(new THREE.MeshPhysicalMaterial({ map: slitTex, roughness: 0.36, clearcoat: 0.7, clearcoatRoughness: 0.2, sheen: 0.5, sheenColor: new THREE.Color(1, 0.9, 0.86), alphaTest: 0.5, side: THREE.DoubleSide, clippingPlanes: clipOut }));
        rawMesh = new THREE.Mesh(bin.own(g), mIn); slitMesh = new THREE.Mesh(g, mOut);
        rawMesh.castShadow = slitMesh.castShadow = true;
        rawMesh.position.y = slitMesh.position.y = 0.0011;
        feedGroup.add(rawMesh, slitMesh);
        api.setFeed(0);
      },
      setRatio(r) {
        api.ratio = r === '1:3' ? '1:3' : '1:1.5';
        const sel = carriers[api.ratio], other = carriers[api.ratio === '1:3' ? '1:1.5' : '1:3'];
        // the spare lies on the drape in front of the mesher, a little crooked
        other.position.set(-0.03, 0.0008, 0.13); other.rotation.set(0, 0.12, 0);
        sel.rotation.set(0, 0, 0);
        api.sel = sel;
        api.setFeed(api.feed || 0);
      },
      // feed in metres of carrier travel (0 = leading edge at the rollers)
      setFeed(f) {
        api.feed = f;
        const sel = api.sel || carriers[api.ratio];
        const x = -carrierL / 2 + 0.004 + f;
        sel.position.set(x, 0.0335, 0);
        feedGroup.position.set(x + carrierL / 2 - 0.012 - Lg / 2, 0.0335, 0);
        rollTop.rotation.z = -f / 0.0112;
        rollBot.rotation.z = f / 0.0102;
      },
      // carrier travel (m) until the trailing edge of the graft is through the rollers
      get needFeed() { return Lg + 0.014; },
      setCrank(a) { crank.rotation.z = -a; },
      hubScreen(w, h) {
        const v = hub.clone().project(cam);
        return { x: (v.x + 1) / 2 * w, y: (1 - v.y) / 2 * h };
      },
      orbit(dx, dy) { view.yaw = clamp(view.yaw - dx * 2.2, -0.7, 0.7); view.pitch = clamp(view.pitch + dy * 1.6, 0.55, 1.35); placeCam(); },
      zoom(sign) { view.dist = clamp(view.dist * Math.pow(1.1, sign), 0.24, 0.7); placeCam(); },
      recenter() { Object.assign(view, { yaw: -0.12, pitch: 0.92, dist: 0.42 }); placeCam(); },
      dispose() { bin.dispose(); },
    };
    placeCam();
    api.setRatio(o.ratio || '1:1.5');
    return api;
  }

  /* ═════════════ body map (front), region → shape ═════════════ */
  const BODY = {
    head: '<circle cx="32" cy="11" r="7.5"/>',
    neck: '<path d="M28.5 18h7v5h-7z"/>',
    chest: '<path d="M20 25c3-2 7-2.6 12-2.6S41 23 44 25l-.6 21H20.6z"/>',
    abdomen: '<path d="M20.6 46h22.8l-.6 13H21.2z"/>',
    pelvis: '<path d="M21.2 59h21.6l1 9c-3 2-7.6 3-11.8 3s-8.8-1-11.8-3z"/>',
    r_upper_arm: '<path d="M14.6 26.5l5.4-1.3.3 21-5.8 1z"/>',
    r_lower_arm: '<path d="M14.5 48.2l5.8-1 .2 21.5-5 .3z"/>',
    l_upper_arm: '<path d="M49.4 26.5l-5.4-1.3-.3 21 5.8 1z"/>',
    l_lower_arm: '<path d="M49.5 48.2l-5.8-1-.2 21.5 5 .3z"/>',
    r_upper_leg: '<path d="M21 70c3 1.6 6.6 2.4 10.4 2.6l-.6 26.4h-8.4z"/>',
    r_lower_leg: '<path d="M22.4 100h8.4l-.8 26h-6.4z"/>',
    l_upper_leg: '<path d="M43 70c-3 1.6-6.6 2.4-10.4 2.6l.6 26.4h8.4z"/>',
    l_lower_leg: '<path d="M41.6 100h-8.4l.8 26h6.4z"/>',
  };
  const BODY_ALIAS = { face: 'head', back: 'chest' };
  function bodySVG(burn, donor) {
    const b = BODY_ALIAS[burn] || burn, d = BODY_ALIAS[donor] || donor;
    return `<svg viewBox="0 0 64 130" class="bn-body">${Object.keys(BODY).map(k => `<g class="p ${k === b ? 'burn' : ''} ${k === d ? 'donor' : ''}">${BODY[k]}</g>`).join('')}</svg>`;
  }

  const DEMO = {
    mode: 'care',
    patient: { name: 'Michael Garcia', sex: 'm', temp: 36.9, avpu: 'A', kind: 'player' },
    injury: {
      id: 'i4', type: 'burn', region: 'r_upper_leg', regionLabel: 'Right thigh', label: 'Burn', severity: 4, pain: 72, contamination: 34,
      burn: { degree: 3, area: 99, temp: 52.6, soot: 78, full: 46, assessed: false },
      treat: { cooled: false, debrided: false, dressed: false, grafted: false },
    },
    tone: 0.3, seed: 4512, donor: 'l_upper_leg', donorLabel: 'Left thigh',
    items: { burnDressing: 2, dressing: 1, graftKit: 1, saline: 2 },
    graft: { ok: true },
  };

  NZA.app('burn', {
    escClose: false, full: true, noscale: true, camInput: false,

    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="bn-stage"></div>
        <div class="bn-tags"></div>
        <div class="bn-ui">
          <div class="bn-dev"></div>
          <div class="bn-case nza-hud solid"></div>
          <div class="bn-res-wrap"></div>
        </div>
        <div class="bn-cur"><svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>
          <span class="pg"><i class="band"></i><i class="lvl"></i><b></b></span></div>
        <div class="bn-veil"><div class="in"><span class="ring"></span><span class="lt"></span><span class="ls"></span></div></div>`;
      this.stage = el.querySelector('.bn-stage');
      this.tagsEl = el.querySelector('.bn-tags');
      this.ui = el.querySelector('.bn-ui');
      this.devEl = el.querySelector('.bn-dev');
      this.caseEl = el.querySelector('.bn-case');
      this.resWrap = el.querySelector('.bn-res-wrap');
      this.cur = el.querySelector('.bn-cur');
      this.curFg = el.querySelector('.bn-cur .fg');
      this.curTx = el.querySelector('.bn-cur .tx');
      this.curPg = el.querySelector('.bn-cur .pg');
      this.veil = el.querySelector('.bn-veil');
      this.onMouse = e => { this.mx = e.clientX; this.my = e.clientY; };
      window.addEventListener('mousemove', this.onMouse);
      const heard = e => { if (e.isTrusted) this.heard = true; };
      window.addEventListener('pointerdown', heard, true);
      window.addEventListener('keydown', heard, true);
      this.onWheel = e => this.wheel(e);
      window.addEventListener('wheel', this.onWheel, { passive: false });
      this.keys = {};
      ['1', '2', '3', '4', '5', '6', '7', '8'].forEach(k => { this.keys[k] = () => { this.pickTool(k); return true; }; });
      this.keys.t = this.keys.T = () => { this.toggleOverlay(); return true; };
      this.keys.q = this.keys.Q = () => this.turnKey(-1);
      this.keys.e = this.keys.E = () => this.turnKey(1);
      this.keys.g = this.keys.G = () => this.decide('graft');
      this.keys.d = this.keys.D = () => this.decide('dress');
      this.keys.r = this.keys.R = () => { if (this.bench && this.g && this.g.step === 6) { this.bench.recenter(); return true; } return false; };
      this.keys.Enter = () => this.enterKey();
    },

    /* ═════════════ lifecycle ═════════════ */
    open(d) {
      this.teardown();
      LOC = d.locale || {};
      this.d = d;
      this.cfg = Object.assign({}, DEFAULTS, d.cfg || {});
      this.cfg.weights = Object.assign({}, DEFAULTS.weights, (d.cfg && d.cfg.weights) || {});
      this.cfg.graftWeights = Object.assign({}, DEFAULTS.graftWeights, (d.cfg && d.cfg.graftWeights) || {});
      if (!Array.isArray(this.cfg.pressureBand) || this.cfg.pressureBand.length < 2) this.cfg.pressureBand = DEFAULTS.pressureBand.slice();
      this.alive = true;
      this.resultShown = false; this.canClose = false; this.finished = false; this.result = null; this.careOutcome = null; this.careResult = null;
      this.resWrap.innerHTML = '';
      this.devEl.style.display = ''; this.caseEl.style.display = '';
      this.mx = window.innerWidth / 2; this.my = window.innerHeight / 2;
      this.showVeil(T('loading', 'Preparing the burn…'), '');
      const token = this.openToken = (this.openToken || 0) + 1;
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive && token === this.openToken) this.boot(); }));
    },
    close() { this.teardown(); },

    teardown() {
      this.alive = false;
      clearTimeout(this.stepTimer); clearTimeout(this.sayTimer); clearTimeout(this.veilTimer);
      if (this.benchRaf) { cancelAnimationFrame(this.benchRaf); this.benchRaf = 0; }
      if (this.benchOff) { this.benchOff(); this.benchOff = null; }
      if (this.bench) { try { this.bench.dispose(); } catch (e) { console.error('[burn] bench', e); } this.bench = null; }
      for (const k of ['SB', 'S']) {
        const S = this[k];
        if (!S) continue;
        if (S.renderer) S.renderer.localClippingEnabled = false;
        try { S.dispose(); } catch (e) { console.error('[burn] dispose', e); }
        this[k] = null;
      }
      for (const k of ['binA', 'binB']) { if (this[k]) { this[k].dispose(); this[k] = null; } }
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      if (this.seg) this.seg = null;
      if (this.fallbackTimer) { clearInterval(this.fallbackTimer); this.fallbackTimer = null; }
      if (this.cur) this.cur.classList.remove('on');
      if (this.stage) { this.stage.innerHTML = ''; this.stage.className = 'bn-stage'; }
      if (this.tagsEl) this.tagsEl.innerHTML = '';
      this.tags = {};
      this.g = null; this.plan = null; this.heat = null;
    },

    msg: {
      careDone(o) { NZA.apps.burn.onCareDone(o || {}); },
      graft(d) { NZA.apps.burn.onGraft(d || {}); },
      graftFail(o) { NZA.apps.burn.onGraftFail(o || {}); },
      result(o) { NZA.apps.burn.showOutcome(o || {}); },
      abort() { NZA.apps.burn.teardown(); NZA.closeLocal('burn'); },
    },

    showVeil(title, sub) {
      clearTimeout(this.veilTimer);
      this.veil.querySelector('.lt').textContent = title || '';
      this.veil.querySelector('.ls').textContent = sub || '';
      this.veil.classList.remove('out');
      this.veil.classList.add('on');
    },
    hideVeil(ms = 120) {
      clearTimeout(this.veilTimer);
      this.veilTimer = setTimeout(() => { this.veil.classList.add('out'); this.veil.classList.remove('on'); }, ms);
    },

    /* ═════════════ boot: scene A (the burn) ═════════════ */
    boot() {
      const d = this.d, cfg = this.cfg;
      const inj = Object.assign({}, DEMO.injury, d.injury || {});
      inj.burn = Object.assign({}, DEMO.injury.burn, (d.injury && d.injury.burn) || {});
      inj.treat = Object.assign({ cooled: false, debrided: false, dressed: false, grafted: false }, (d.injury && d.injury.treat) || {});
      this.inj = inj;
      this.mode = d.mode === 'graft' ? 'graft' : 'care';
      if (!window.NZA3D || !NZA3D.supported()) return this.fallback();
      const b = inj.burn;
      const deg = clamp(Math.round(+b.degree || 2), 1, 3);
      const A = clamp(+b.area || 40, 8, 160);
      const limb = /arm|leg/.test(inj.region || '');
      const asp = limb ? 1.6 : 1.38;
      const rx = Math.sqrt(A * 1e-4 * asp / Math.PI), ry = rx / asp;
      const seed = (+d.seed || hash(`${inj.id}:${(d.patient && d.patient.name) || ''}`)) >>> 0;
      this.seed = seed;
      const viewW = clamp(rx * 2 * 1.85, 0.11, 0.34);
      let S;
      try {
        this.binA = makeBin();
        S = NZA3D.createScene(this.stage, {
          tone: d.tone !== undefined ? +d.tone : 0.3, region: inj.region || 'r_upper_leg', sex: (d.patient && d.patient.sex) || 'm',
          seed, hair: d.hair !== undefined && d.hair !== null ? +d.hair : null, quality: cfg.quality,
          focus: { uv: [0.5, 0.5], size: [rx * 2 + 0.02, ry * 2 + 0.02], view: viewW },
          work: [rx * 2 * 1.6 + 0.04, ry * 2 * 1.75 + 0.04],
          drape: this.mode === 'graft' ? { radius: Math.max(rx * 1.3, ry * 1.9) + 0.012 } : false,
        });
      } catch (e) {
        console.error('[burn] 3D scene', e);
        return this.fallback();
      }
      this.S = S;
      this.canvasA = S.canvas;
      // a lower, more raking lamp than the engine default: blister domes, rolled skin edges and the
      // eschar's fissures read in relief
      if (S.lightRig && Array.isArray(S.lightRig.key)) S.lightRig.key = [0.27, 0.07, 0.66];
      this.viewW = viewW;
      const w = S.wounds.add({ type: 'burn', uv: [0.5, 0.5], radius: [rx, ry], degree: Math.min(2, deg), irregular: 0.42, blisters: 0, seed: seed % 100000, rim: 0.85, rimWidth: 0.007 });
      this.w = w;
      const dn = burnShape(S, w);
      const plan = planBurn({ seed, rx, ry, dn, degree: deg, full: deg >= 3 ? clamp(+b.full || 0, 0, 100) : 0 });
      Object.assign(plan, { rx, ry, dn, deg, A });
      this.plan = plan;
      const peak = clamp(+b.temp || 46, 34, 80);
      const nx = 84, ny = clamp(Math.round(84 * (ry * 3.1) / (rx * 2.9)), 36, 96);
      this.heat = new Heat({ s0: -rx * 1.45, t0: -ry * 1.55, w: rx * 2.9, h: ry * 3.1, nx, ny, dn, peak, inZone: plan.inZone, seed, rebound: +cfg.rebound });
      this.heat.peak = peak;
      plan.zones.forEach(Z => {
        Z.cutPoly = polyOffset(Z.poly, 0.0026);
        Z.cum = polyCum(Z.cutPoly);
        Z.bins = new Uint8Array(Math.max(24, Math.ceil(Z.cum[Z.cutPoly.length] / 0.0015)));
        Z.cutArea = polyArea(Z.cutPoly);
      });

      const t0 = inj.treat;
      const g = this.g = {
        t: 0, step: 0, tool: null, lmb: false, done: {}, skipped: {}, uiT: 0, devT: 0, caseT: 0, trendT: 0,
        pain0: clamp(+inj.pain || 50, 5, 100), pain: 0, painSpike: 0, lastSay: -9, spoke: {},
        sedated: this.mode === 'graft', coreT: clamp(+(d.patient && d.patient.temp) || 36.9, 30, 42),
        conscious: !d.patient || !d.patient.avpu || d.patient.avpu === 'A' || d.patient.avpu === 'V',
        cool: { ml: cfg.bottleMl, bottle: 1, refill: 0, used: 0, pouring: false, holdT: 0, overcool: 0, soot0: clamp(+b.soot || 0, 0, 100), sootTotal0: 1, soot: clamp(+b.soot || 0, 0, 100), done: false, partial: false, warnT: 0, trend: [], steamT: 0, sizzleT: 0, best: 99, felt: false },
        as: { press: null, tests: 0, fixed: 0, est: null, cover: 0, last: null },
        db: { grip: null, removed: 0, fumbles: 0, total: plan.blisters.length + plan.flaps.length },
        ex: { strays: 0, devSum: 0, devN: 0, blood: 0, last: null, rebuildT: 0, excisedArea: 0 },
        hv: null, ms: null, gr: null, dr: { D: null, rub: false, cover: 0, settledT: 0, warnT: 0, secured: false },
        overlay: false, pal: 'lava', hold: false,
        stats0: this.heat.stats(cfg.target), scene: 'A',
      };
      g.pain = g.pain0;

      // already done earlier (resumed burn care / standalone graft)
      const resumed = { cooled: !!t0.cooled, debrided: !!t0.debrided, assessed: !!b.assessed };
      if (this.mode === 'graft') { resumed.cooled = true; resumed.debrided = true; resumed.assessed = true; }
      if (resumed.cooled) { this.heat.settle(cfg.target - 3.5); g.cool.done = true; g.done[1] = true; g.cool.soot = Math.min(g.cool.soot0, clamp(+b.soot || 0, 0, 100)); }
      if (resumed.debrided) { plan.blisters.forEach(x => { x.removed = true; }); plan.flaps.forEach(x => { x.removed = true; }); g.db.total = 0; g.done[3] = true; }
      if (resumed.assessed) {
        g.done[2] = true;
        plan.cells.forEach(c => { c.tested = true; });
        g.as.cover = 1;
        g.as.est = b.assessedFull !== undefined && b.assessedFull !== null ? +b.assessedFull : (deg >= 3 ? +b.full : 0);
        plan.zones.forEach(Z => { Z.found = true; });
      }
      if (this.mode === 'graft' && +b.excised >= cfg.minExcised) plan.zones.forEach(Z => { Z.excised = true; Z.preExcised = true; });

      this.patchSkin(plan, deg, seed);
      this.paintInitial(seed, resumed);
      this.buildSceneA(resumed);
      S.layers.decay('wet', 0.05);
      g.cool.sootTotal0 = Math.max(1e-6, this.sootTotal(true));
      S.on('frame', dt => this.frameA(dt));
      S.on('down', e => this.down(e));
      S.on('up', e => this.up(e));
      S.start();

      this.buildDevice();
      this.buildCase();
      this.buildPanel();
      let first;
      if (this.mode === 'graft') first = plan.zones.every(Z => Z.excised) ? 5 : 4;
      else first = !resumed.cooled ? 1 : !resumed.assessed ? 2 : !resumed.debrided && g.db.total ? 3 : 8;
      for (let k = 1; k < first; k++) if (!g.done[k] && (this.mode === 'care' || k < 4)) g.done[k] = true;
      this.enterStep(first, true);
      this.hideVeil(160);
      if (this.mode === 'care' && g.conscious && first === 1) this.sayLater('say_hot', 'It burns… please, cool it down!', 1600);
    },

    // The engine colours partial-thickness burns with its own round noise cells. For a burn that has
    // to read as real, the skin material of THIS scene gets our own partial-thickness layer: weeping
    // cherry dermis, mottled deep-partial pallor, torn sheets of dead epidermis with rolled edges.
    // Every anchor is optional — when the engine's shader text changes, the engine look stays.
    patchSkin(plan, deg, seed) {
      const THREE = window.THREE, S = this.S, mat = S.skin && S.skin.material;
      if (!mat || typeof mat.onBeforeCompile !== 'function') return;
      const box = [-plan.rx * 1.6, -plan.ry * 1.6, plan.rx * 1.6, plan.ry * 1.6];
      const det = texBurnDetail({ box, dn: plan.dn, zones: plan.zones, blisters: plan.blisters, flaps: plan.flaps, degree: deg, seed });
      const mapTex = canvasTex(this.binA, det.map, false), nrmTex = canvasTex(this.binA, det.normal, false);
      this.det = { cv: det.map, ctx: det.map.getContext('2d'), tex: mapTex, box, w: det.w, h: det.h };
      const U = this.bnU = {
        tBnDet: { value: mapTex }, tBnNrm: { value: nrmTex },
        uBnBox: { value: new THREE.Vector4(box[0], box[1], box[2] - box[0], box[3] - box[1]) },
        uBnOn: { value: 1 }, uBnHot: { value: 1 },
      };
      const base = mat.onBeforeCompile, baseKey = typeof mat.customProgramCacheKey === 'function' ? mat.customProgramCacheKey() : '';
      const A1 = 'vec3 nzaPart = ', A2 = 'nzaCol = mix(nzaCol, nzaFull, smoothstep(0.66, 0.86, nzaBs));';
      mat.onBeforeCompile = (sh, renderer) => {
        base.call(mat, sh, renderer);
        let f = sh.fragmentShader;
        const i1 = f.indexOf(A1), i2 = f.indexOf(A2);
        if (i1 < 0 || i2 < i1 || f.indexOf('#include <common>') < 0) return;
        f = f.slice(0, i1) + BURN_GLSL_COL + f.slice(i2 + A2.length);
        f = f.replace('#include <common>', '#include <common>\n' + BURN_GLSL_PARS);
        f = f.replace(/nzaWet = clamp\([^;]*;/, m => `${m}\n    nzaWet = max(nzaWet, bnWeep);`);
        f = f.replace(/roughnessFactor = mix\(roughnessFactor, 0\.92, nzaGrit\);/, m => `${m}\n    roughnessFactor = mix(roughnessFactor, 0.22, bnWeep * 0.85);`);
        f = f.replace(/vec2 nzaCoatXY = [^;]*;/, m => `vec2 bnNxy = (texture2D(tBnNrm, bnQ).xy * 2.0 - 1.0) * bnIn;\n    nzaMxy += bnNxy;\n    ${m}\n    nzaCoatXY += bnNxy * 0.8;`);
        sh.fragmentShader = f;
        Object.assign(sh.uniforms, U);
      };
      mat.customProgramCacheKey = () => `${baseKey}+nza-burn-2`;
      mat.needsUpdate = true;
    },
    // a deroofed blister / pulled-off sheet leaves raw, wet, pink dermis
    bareDetail(s, t, r) {
      const D = this.det;
      if (!D) return;
      const x = (s - D.box[0]) / (D.box[2] - D.box[0]) * D.w, y = (t - D.box[1]) / (D.box[3] - D.box[1]) * D.h;
      const rp = r / (D.box[2] - D.box[0]) * D.w;
      const gr = D.ctx.createRadialGradient(x, y, 0, x, y, rp);
      gr.addColorStop(0, 'rgba(10,0,255,1)'); gr.addColorStop(0.7, 'rgba(10,0,255,.85)'); gr.addColorStop(1, 'rgba(10,0,255,0)');
      D.ctx.fillStyle = gr;
      D.ctx.beginPath(); D.ctx.arc(x, y, rp, 0, TAU); D.ctx.fill();
      D.tex.needsUpdate = true;
    },

    // soot, ash, the eschar's footprint on the skin
    paintInitial(seed, resumed) {
      const S = this.S, plan = this.plan, R = rng(seed ^ 0x5007);
      const { rx, ry } = plan;
      const uv = (s, t) => S.stToUv(s, t);
      const soot = this.g.cool.soot0 / 100;
      if (soot > 0.02 && !resumed.cooled) {
        // a thin smoke-black haze over the burn and the skin round it (washable film) …
        for (let k = 0; k < 34; k++) {
          const a = R() * TAU, r = Math.pow(R(), 0.8) * 1.25;
          S.layers.splat('soot', uv(Math.cos(a) * r * rx, Math.sin(a) * r * ry), (4 + R() * 8) * MM, clamp((0.09 + R() * 0.12) * (0.4 + soot) * (r < 1 ? 1 : 0.7), 0, 1), { seed: 700 + k, count: 6 });
        }
        // … heavier black patches where the flames sat …
        for (let k = 0; k < 14; k++) {
          const a = R() * TAU, r = Math.sqrt(R()) * 0.85;
          S.layers.splat('soot', uv(Math.cos(a) * r * rx, Math.sin(a) * r * ry), (2.5 + R() * 4) * MM, 0.24 * (0.4 + soot), { seed: 1300 + k, count: 5 });
        }
        // … greasy ash-brown residue in a few places …
        for (let k = 0; k < 12; k++) {
          const a = R() * TAU, r = Math.pow(R(), 0.6) * 1.05;
          S.layers.splat('grime', uv(Math.cos(a) * r * rx, Math.sin(a) * r * ry), (2.5 + R() * 5) * MM, clamp((0.16 + R() * 0.16) * (0.35 + soot), 0, 1), { seed: 1900 + k, count: 5 });
        }
        // … and fine ash flecks, densest on the burn, thinning out over the healthy skin
        for (let k = 0; k < 360; k++) {
          const a = R() * TAU, r = Math.pow(R(), 0.6) * 1.35;
          S.layers.paint('soot', uv(Math.cos(a) * r * rx, Math.sin(a) * r * ry), (0.12 + R() * R() * 0.55) * MM, (0.55 + R() * 0.45) * (r < 1 ? 1 : 0.6), { hardness: 0.65 });
        }
      } else if (this.g.cool.soot > 2) {
        for (let k = 0; k < 18; k++) {
          const a = R() * TAU, r = Math.sqrt(R());
          S.layers.splat('grime', uv(Math.cos(a) * r * rx, Math.sin(a) * r * ry), (2 + R() * 5) * MM, 0.25 * this.g.cool.soot / 100, { seed: 300 + k, count: 4 });
        }
      }
      // the eschar's dark footprint under the crust, for a soft edge
      plan.zones.forEach((Z, zi) => {
        if (Z.excised) return;
        for (let i = 0; i < Z.pts.length; i += 5) S.layers.paint('eschar', uv(Z.pts[i][0], Z.pts[i][1]), 2.6 * MM, 0.22, { hardness: 0.2, grain: 0.5, grainScale: 90, seedX: zi * 3 + i });
      });
    },

    sootTotal(force) {
      const g = this.g;
      if (!force && g.cool._sootAt && g.t - g.cool._sootAt < 0.25) return g.cool._soot;
      g.cool._sootAt = g.t;
      g.cool._soot = this.S ? this.S.layers.total('soot') + this.S.layers.total('grime') * 0.6 : 0;
      return g.cool._soot;
    },

    /* ═════════════ scene A props: eschar crusts, blisters, dead skin, tools, overlay, steam ═════════════ */
    buildSceneA(resumed) {
      const THREE = window.THREE, S = this.S, plan = this.plan, bin = this.binA;
      const M = this.MA = makeMats(bin);
      // full-thickness eschar crusts
      plan.zones.forEach((Z, zi) => {
        if (Z.excised) { this.makeBed(Z, true); return; }
        const tx = texEschar(Z, this.seed + zi * 101);
        const box = Z.box, c = [(box[0] + box[2]) / 2, (box[1] + box[3]) / 2], size = [box[2] - box[0], box[3] - box[1]];
        const nX = clamp(Math.round(size[0] / 0.0016), 16, 72), nY = clamp(Math.round(size[1] / 0.0016), 16, 72);
        const geo = conformGeo(S, { c, size, n: [nX, nY], lift: (lx, ly) => 0.00028 + 0.00045 * Math.max(0, 1 - Math.hypot(lx / (size[0] / 2), ly / (size[1] / 2))) });
        bin.own(geo);
        const mat = bin.own(new THREE.MeshStandardMaterial({
          map: canvasTex(bin, tx.map), normalMap: canvasTex(bin, tx.normal, false), roughnessMap: canvasTex(bin, tx.rough, false),
          roughness: 1, metalness: 0, transparent: true, alphaTest: 0.02, depthWrite: false, normalScale: new THREE.Vector2(1.6, 1.6), polygonOffset: true, polygonOffsetFactor: -2,
        }));
        const me = new THREE.Mesh(geo, mat);
        me.receiveShadow = true; me.castShadow = true; me.renderOrder = 2;
        S.scene.add(me);
        Z.plate = me; Z.plateC = c;
        // the bed under it is prepared now (texture work happens behind the loading veil)
        Z.bedTex = texBed(Z.cutPoly, polyBox(Z.cutPoly, 0.0015), this.seed + zi * 37);
      });
      // blisters: the skin domes (engine bumps) under a glossy, fluid-filled roof
      this.blisterMat = bin.own(new THREE.MeshPhysicalMaterial({ color: 0xf4e3c2, roughness: 0.05, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.03,
        transparent: true, opacity: 0.5, depthWrite: false, sheen: 0.4, sheenColor: new THREE.Color(1, 0.96, 0.86), specularIntensity: 1, envMapIntensity: 1.4 }));
      plan.blisters.forEach(bl => {
        if (bl.removed) return;
        bl.bump = S.bumps.add({ uv: S.stToUv(bl.s, bl.t), radius: bl.r * 1.08, height: bl.h * 0.85, kind: 'blister' });
        bl.dome = this.makeDome(bl);
      });
      // loose dead skin
      if (plan.flaps.some(f => !f.removed)) {
        const atlas = texFlaps(this.seed ^ 0xf1a9);
        const base = canvasTex(bin, atlas);
        plan.flaps.forEach(f => {
          if (f.removed) return;
          const tex = bin.own(base.clone());
          tex.needsUpdate = true;
          tex.repeat.set(0.5, 0.5); tex.offset.set((f.v % 2) * 0.5, Math.floor(f.v / 2) * 0.5 === 0 ? 0.5 : 0);
          const mat = bin.own(new THREE.MeshPhysicalMaterial({ map: tex, color: new THREE.Color(0.93, 0.89, 0.86), roughness: 0.5, clearcoat: 0.7, clearcoatRoughness: 0.18, sheen: 0.3, sheenColor: new THREE.Color(1, 0.9, 0.84), sheenRoughness: 0.45, alphaTest: 0.35, side: THREE.DoubleSide, transparent: false }));
          // one side lies stuck in the wound, the free edge curls up and over
          const lift = (lx, ly) => 0.0002 + Math.pow(Math.max(0, lx / (f.w / 2) + 0.15), 2.4) * f.curl * 0.0042 + Math.abs(ly / (f.h / 2)) * 0.0003;
          const geo = bin.own(conformGeo(S, { c: [f.s, f.t], size: [f.w * 1.25, f.h * 1.25], n: [14, 12], angle: f.ang, lift, computeNormals: true }));
          const me = new THREE.Mesh(geo, mat);
          me.castShadow = true; me.receiveShadow = true;
          S.scene.add(me);
          f.mesh = me; f.lift = lift;
        });
      }
      // thermal overlay (AR view of the imager, key T)
      const H = this.heat;
      this.ovCanvas = mkCanvas(H.nx, H.ny);
      this.ovTex = canvasTex(bin, this.ovCanvas);
      this.ovTex.magFilter = THREE.LinearFilter;
      const ovGeo = bin.own(conformGeo(S, { c: [H.s0 + (H.nx - 1) * H.ds / 2, H.t0 + (H.ny - 1) * H.dt / 2], size: [(H.nx - 1) * H.ds, (H.ny - 1) * H.dt], n: [56, 40], lift: 0.0009 }));
      this.ovMesh = new THREE.Mesh(ovGeo, bin.own(new THREE.MeshBasicMaterial({ map: this.ovTex, transparent: true, opacity: 0, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -8 })));
      this.ovMesh.renderOrder = 9; this.ovMesh.visible = false;
      S.scene.add(this.ovMesh);
      // diascope blanching disc
      const discTex = canvasTex(bin, texDisc(0.7));
      this.blanch = new THREE.Mesh(new THREE.BufferGeometry(), bin.own(new THREE.MeshBasicMaterial({ map: discTex, color: 0xfff3ee, transparent: true, opacity: 0, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -6 })));
      this.blanch.renderOrder = 7;
      S.scene.add(this.blanch);
      this.blanchA = 0;
      // steam
      const steamTex = canvasTex(bin, texSoft());
      this.steam = [];
      for (let i = 0; i < 48; i++) {
        const sp = new THREE.Sprite(bin.own(new THREE.SpriteMaterial({ map: steamTex, color: 0xf2f6f8, transparent: true, opacity: 0, depthWrite: false })));
        sp.visible = false; sp.renderOrder = 10;
        S.scene.add(sp);
        this.steam.push({ sp, life: 0, max: 1, v: new THREE.Vector3() });
      }
      // instruments
      this.tb = {
        bottle: mkTool(S, bin, 'bottle', buildBottle(bin, M), { lift: 0.055, pressLift: 0.055, tilt: 0.42, yaw: 1.62, roll: 0, shadow: 0.025 }),
        diascope: mkTool(S, bin, 'diascope', buildDiascope(bin, M), { lift: 0.007, pressLift: 0.0002, tilt: 0.0, yaw: 0.6, roll: 0, shadow: 0.02 }),
        stapler: mkTool(S, bin, 'stapler', buildStapler(bin, M), { lift: 0.006, pressLift: 0.0005, tilt: 0.55, yaw: 1.3, roll: 0, shadow: 0.03 }),
      };
      // compile everything behind the veil
      Object.values(this.tb).forEach(t => { t.group.visible = true; t.group.position.set(0, -5, 0); });
      this.ovMesh.visible = true;
      S.prewarm(['forceps', 'scalpel'], true);
      Object.values(this.tb).forEach(t => { t.group.visible = false; });
      this.ovMesh.visible = false;
    },

    // the excised bed for a zone (raw tissue under the cut outline)
    makeBed(Z, instant) {
      const THREE = window.THREE, S = this.S, bin = this.binA;
      if (Z.bed) return;
      const box = polyBox(Z.cutPoly, 0.0015);
      const tx = Z.bedTex || texBed(Z.cutPoly, box, this.seed + Z.id * 37);
      Z.bedTex = null;
      const c = [(box[0] + box[2]) / 2, (box[1] + box[3]) / 2], size = [box[2] - box[0], box[3] - box[1]];
      const geo = bin.own(conformGeo(S, { c, size, n: [clamp(Math.round(size[0] / 0.002), 12, 60), clamp(Math.round(size[1] / 0.002), 12, 60)], lift: 0.00012 }));
      const mat = bin.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(bin, tx.map), normalMap: canvasTex(bin, tx.normal, false), normalScale: new THREE.Vector2(1.2, 1.2),
        roughness: 0.26, clearcoat: 1, clearcoatRoughness: 0.08, alphaTest: 0.5, polygonOffset: true, polygonOffsetFactor: -1, transparent: false }));
      const me = new THREE.Mesh(geo, mat);
      me.receiveShadow = true; me.renderOrder = 1;
      S.scene.add(me);
      Z.bed = me;
      if (!instant) {
        // fresh bleeding: dots and a trickle off the lowest edge
        const R = rng(this.seed + Z.id);
        for (let i = 0; i < 26; i++) {
          const p = Z.cutPoly[Math.floor(R() * Z.cutPoly.length)];
          S.layers.paint('blood', S.stToUv(p[0], p[1]), (0.5 + R() * 0.9) * MM, 0.35, { hardness: 0.4 });
        }
        let low = Z.cutPoly[0];
        Z.cutPoly.forEach(p => { if (p[1] > low[1]) low = p; });
        S.fluids.drip(S.stToUv(low[0], low[1] + 0.001), 0.12);
      }
    },

    // a blister roof: a thin spherical cap of serous fluid and dead epidermis
    makeDome(bl) {
      const THREE = window.THREE, S = this.S;
      const r = bl.r, hh = Math.max(0.0004, bl.h);
      const Rs = (r * r + hh * hh) / (2 * hh), th = Math.asin(clamp(r / Rs, 0, 1));
      const g = this.binA.own(new THREE.SphereGeometry(Rs, 28, 10, 0, TAU, 0, th));
      const me = new THREE.Mesh(g, this.blisterMat);
      const edge = S.surfaceAt(S.stToUv(bl.s + r * 1.05, bl.t)), ctr = S.surfaceAt(S.stToUv(bl.s, bl.t));
      // base level at the rim, cap apex a hair above the raised skin
      const n = ctr.normal.clone();
      const base = ctr.point.clone().addScaledVector(n, -(ctr.point.clone().sub(edge.point).dot(n)));
      me.position.copy(base).addScaledVector(n, -(Rs - hh) + 0.00012);
      me.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), n);
      me.scale.set(1, 1, 0.92);
      me.renderOrder = 5;
      me.userData = { base: me.position.clone(), n };
      S.scene.add(me);
      return me;
    },

    /* ═════════════ HUD: the wound imager (top-left) ═════════════ */
    buildDevice() {
      this.devEl.innerHTML = `
        <div class="dv-shell">
          <div class="dv-top"><span class="dv-lens"><i></i></span><span class="dv-model"><b>WI-6</b>${esc(T('dev_model', 'Wound imager'))}</span><span class="dv-led"></span></div>
          <div class="dv-screen">
            <div class="dv-bar"><span class="dv-mode"></span><span class="dv-pal"></span><span class="dv-rec"><i></i><b>00:00</b></span><span class="dv-bat"><i></i></span></div>
            <div class="dv-main"><canvas class="dv-img" width="400" height="300"></canvas><div class="dv-list"></div></div>
            <div class="dv-foot"><canvas class="dv-trend" width="400" height="56"></canvas><span class="dv-cap"></span></div>
          </div>
          <div class="dv-keys">
            <button class="dv-k" data-k="pal"><i></i>${esc(T('dev_pal', 'Palette'))}</button>
            <button class="dv-k" data-k="ar"><i></i>${esc(T('dev_ar', 'Overlay'))}<kbd>T</kbd></button>
            <button class="dv-k" data-k="hold"><i></i>${esc(T('dev_hold', 'Freeze'))}</button>
            <span class="dv-trig"></span>
          </div>
          <span class="dv-sticker"><svg viewBox="0 0 24 22"><path d="M12 1.5 23 20.5H1z"/><path d="M12 8v6M12 16.5v1.2"/></svg>${esc(T('dev_laser', 'Laser 2'))}</span>
        </div>`;
      this.devImg = this.devEl.querySelector('.dv-img');
      this.devTrend = this.devEl.querySelector('.dv-trend');
      this.devEl.querySelectorAll('.dv-k').forEach(btn => btn.addEventListener('click', () => {
        const k = btn.dataset.k;
        if (k === 'pal') { const order = ['lava', 'iron', 'grey']; this.g.pal = order[(order.indexOf(this.g.pal) + 1) % order.length]; this.lut = null; }
        if (k === 'ar') this.toggleOverlay();
        if (k === 'hold') this.g.hold = !this.g.hold;
        this.snd('click', 900);
        this.drawDevice(true);
      }));
    },
    devMode() {
      const g = this.g;
      if (!g) return 'thermal';
      return ({ 1: 'thermal', 2: 'depth', 3: 'tissue', 4: 'excise', 5: 'donor', 6: 'mesh', 7: 'graft', 8: 'cover' })[g.step] || 'thermal';
    },
    drawDevice(force) {
      const g = this.g;
      if (!g || !this.devImg) return;
      if (g.hold && !force) return;
      const mode = this.devMode(), cv = this.devImg, c = cv.getContext('2d'), W = cv.width, H = cv.height;
      c.fillStyle = '#04070a'; c.fillRect(0, 0, W, H);
      const modeNames = { thermal: T('dm_thermal', 'Surface heat'), depth: T('dm_depth', 'Depth map'), tissue: T('dm_tissue', 'Tissue'), excise: T('dm_excise', 'Excision'), donor: T('dm_donor', 'Donor'), mesh: T('dm_mesh', 'Expansion'), graft: T('dm_graft', 'Graft fit'), cover: T('dm_cover', 'Cover') };
      this.devEl.querySelector('.dv-mode').textContent = modeNames[mode];
      this.devEl.querySelector('.dv-pal').textContent = mode === 'thermal' ? g.pal.toUpperCase() : '';
      this.devEl.querySelector('.dv-rec b').textContent = NZA.fmt.time(g.t);
      this.devEl.querySelector('.dv-shell').classList.toggle('hold', !!g.hold);
      this.devEl.querySelector('[data-k="ar"]').classList.toggle('on', !!g.overlay);
      this.devEl.querySelector('[data-k="hold"]').classList.toggle('on', !!g.hold);
      let rows = [], cap = '';
      if (mode === 'thermal') { rows = this.devThermal(c, W, H); cap = T('dc_trend', 'Mean surface °C · target line'); }
      else if (mode === 'depth') { rows = this.devDepth(c, W, H); cap = T('dc_depth', 'Tested area · blanching vs fixed'); }
      else if (mode === 'tissue') { rows = this.devTissue(c, W, H); cap = T('dc_tissue', 'Blisters and dead skin left'); }
      else if (mode === 'excise') { rows = this.devExcise(c, W, H); cap = T('dc_excise', 'Cut line progress per area'); }
      else if (mode === 'donor') { rows = this.devDonor(c, W, H); cap = T('dc_donor', 'Speed · pressure along the strip'); }
      else if (mode === 'mesh') { rows = this.devMesh(c, W, H); cap = T('dc_mesh', 'Crank rate, turns/s'); }
      else if (mode === 'graft') { rows = this.devGraft(c, W, H); cap = T('dc_graft', 'Bed covered by the graft'); }
      else { rows = this.devCover(c, W, H); cap = T('dc_cover', 'Dressing over the burn'); }
      this.drawTrend(mode);
      const html = rows.map(r => `<div class="dr ${r[2] || ''}"><span>${esc(r[0])}</span><b>${esc(r[1])}</b></div>`).join('');
      const list = this.devEl.querySelector('.dv-list');
      if (list.innerHTML !== html) list.innerHTML = html;
      this.devEl.querySelector('.dv-cap').textContent = cap;
    },
    // patch metres → device pixels (the burn's frame, letterboxed)
    devXf(W, H, pad = 8) {
      const Hh = this.heat, w = (Hh.nx - 1) * Hh.ds, h = (Hh.ny - 1) * Hh.dt;
      const k = Math.min((W - pad * 2 - 30) / w, (H - pad * 2) / h);
      const ox = pad + (W - pad * 2 - 30 - w * k) / 2, oy = pad + (H - pad * 2 - h * k) / 2;
      return { k, x: s => ox + (s - Hh.s0) * k, y: t => oy + (t - Hh.t0) * k, w: w * k, h: h * k, ox, oy };
    },
    polyPath(c, P, X) { c.beginPath(); P.forEach((p, i) => (i ? c.lineTo(X.x(p[0]), X.y(p[1])) : c.moveTo(X.x(p[0]), X.y(p[1])))); c.closePath(); },
    devOutline(c, X, alpha = 0.35) {
      // burn outline from the heat mask (marching through cells)
      const Hh = this.heat;
      c.strokeStyle = `rgba(255,255,255,${alpha})`; c.lineWidth = 1;
      c.beginPath();
      for (let j = 0; j < Hh.ny - 1; j++) for (let i = 0; i < Hh.nx - 1; i++) {
        const k = j * Hh.nx + i, a = Hh.mask[k] > 0.5, b = Hh.mask[k + 1] > 0.5, d = Hh.mask[k + Hh.nx] > 0.5;
        const x = X.x(Hh.s0 + (i + 0.5) * Hh.ds), y = X.y(Hh.t0 + (j + 0.5) * Hh.dt);
        if (a !== b) { c.moveTo(x, y - Hh.dt * X.k / 2); c.lineTo(x, y + Hh.dt * X.k / 2); }
        if (a !== d) { c.moveTo(x - Hh.ds * X.k / 2, y); c.lineTo(x + Hh.ds * X.k / 2, y); }
      }
      c.stroke();
    },
    tempRange() { return [16, Math.max(46, Math.ceil((this.heat.peak || 50) / 2) * 2 + 2)]; },
    devThermal(c, W, H) {
      const g = this.g, Hh = this.heat, cfg = this.cfg, X = this.devXf(W, H);
      if (!this.lut || this.lutName !== g.pal) { this.lut = palLUT(g.pal); this.lutName = g.pal; }
      const [lo, hi] = this.tempRange();
      const small = this.heatImg || (this.heatImg = mkCanvas(Hh.nx, Hh.ny));
      const sc = small.getContext('2d'), id = sc.createImageData(Hh.nx, Hh.ny), d = id.data, lut = this.lut;
      for (let k = 0; k < Hh.T.length; k++) {
        const v = clamp(Math.round((Hh.T[k] - lo) / (hi - lo) * 255), 0, 255);
        d[k * 4] = lut[v * 3]; d[k * 4 + 1] = lut[v * 3 + 1]; d[k * 4 + 2] = lut[v * 3 + 2]; d[k * 4 + 3] = 255;
      }
      sc.putImageData(id, 0, 0);
      c.imageSmoothingEnabled = true; c.imageSmoothingQuality = 'high';
      c.drawImage(small, X.ox, X.oy, X.w, X.h);
      // isotherm at the target (marching squares, white dashed)
      c.save();
      c.setLineDash([3, 3]); c.strokeStyle = 'rgba(255,255,255,.85)'; c.lineWidth = 1.2;
      c.beginPath();
      const thr = cfg.target, nx = Hh.nx, Tt = Hh.T;
      const lerpP = (a, b, va, vb) => a + (b - a) * clamp((thr - va) / ((vb - va) || 1e-6), 0, 1);
      for (let j = 0; j < Hh.ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
        const k = j * nx + i, v0 = Tt[k], v1 = Tt[k + 1], v2 = Tt[k + nx + 1], v3 = Tt[k + nx];
        const pts = [];
        const x0 = X.x(Hh.s0 + i * Hh.ds), x1 = X.x(Hh.s0 + (i + 1) * Hh.ds), y0 = X.y(Hh.t0 + j * Hh.dt), y1 = X.y(Hh.t0 + (j + 1) * Hh.dt);
        if ((v0 < thr) !== (v1 < thr)) pts.push([lerpP(x0, x1, v0, v1), y0]);
        if ((v1 < thr) !== (v2 < thr)) pts.push([x1, lerpP(y0, y1, v1, v2)]);
        if ((v3 < thr) !== (v2 < thr)) pts.push([lerpP(x0, x1, v3, v2), y1]);
        if ((v0 < thr) !== (v3 < thr)) pts.push([x0, lerpP(y0, y1, v0, v3)]);
        if (pts.length >= 2) { c.moveTo(pts[0][0], pts[0][1]); c.lineTo(pts[1][0], pts[1][1]); }
        if (pts.length === 4) { c.moveTo(pts[2][0], pts[2][1]); c.lineTo(pts[3][0], pts[3][1]); }
      }
      c.stroke();
      c.restore();
      this.devOutline(c, X, 0.18);
      const st = this.lastStats || Hh.stats(cfg.target);
      // hottest point
      const hx = X.x(st.hot[0]), hy = X.y(st.hot[1]);
      c.fillStyle = '#fff'; c.beginPath(); c.moveTo(hx, hy - 7); c.lineTo(hx + 5, hy + 2); c.lineTo(hx - 5, hy + 2); c.closePath(); c.fill();
      c.font = '600 11px "JetBrains Mono", monospace'; c.fillStyle = '#fff';
      c.fillText(`${f1(st.max)}°`, hx + 7, hy + 2);
      // spot meter at the cursor / stream
      const spot = this.spot;
      let spotT = null;
      if (spot) {
        spotT = Hh.at(spot[0], spot[1]);
        const sx = X.x(spot[0]), sy = X.y(spot[1]);
        if (sx > X.ox && sx < X.ox + X.w && sy > X.oy && sy < X.oy + X.h) {
          c.strokeStyle = '#fff'; c.lineWidth = 1.4;
          c.beginPath(); c.arc(sx, sy, 7, 0, TAU); c.moveTo(sx - 13, sy); c.lineTo(sx - 4, sy); c.moveTo(sx + 4, sy); c.lineTo(sx + 13, sy); c.moveTo(sx, sy - 13); c.lineTo(sx, sy - 4); c.moveTo(sx, sy + 4); c.lineTo(sx, sy + 13); c.stroke();
          c.fillStyle = 'rgba(0,0,0,.55)'; c.fillRect(sx + 9, sy - 22, 46, 15);
          c.fillStyle = '#fff'; c.fillText(`${f1(spotT)}°`, sx + 12, sy - 11);
        }
      }
      // scale bar (right)
      const bx = W - 26, by0 = X.oy, by1 = X.oy + X.h;
      for (let y = by0; y < by1; y++) {
        const v = clamp(Math.round((1 - (y - by0) / (by1 - by0)) * 255), 0, 255);
        c.fillStyle = `rgb(${lut[v * 3]},${lut[v * 3 + 1]},${lut[v * 3 + 2]})`; c.fillRect(bx, y, 10, 1);
      }
      c.strokeStyle = 'rgba(255,255,255,.35)'; c.strokeRect(bx - 0.5, by0 - 0.5, 11, by1 - by0 + 1);
      c.font = '500 10px "JetBrains Mono", monospace'; c.fillStyle = 'rgba(255,255,255,.75)';
      c.fillText(String(hi), bx - 2, by0 - 3 < 10 ? by0 + 9 : by0 - 3);
      c.fillText(String(lo), bx - 2, by1 + 11 > H ? by1 - 2 : by1 + 11);
      const ty = by1 - (cfg.target - lo) / (hi - lo) * (by1 - by0);
      c.fillStyle = '#fff'; c.fillRect(bx - 5, ty - 0.5, 16, 1.5);
      c.fillText(String(cfg.target), bx - 22, ty + 3.5);
      const g2 = g.cool;
      return [
        [T('dl_mean', 'Mean'), `${f1(st.mean)} °C`, st.mean < cfg.target ? 'teal' : st.mean > 40 ? 'red' : 'amber'],
        [T('dl_max', 'Max'), `${f1(st.max)} °C`, st.max > 40 ? 'red' : ''],
        [T('dl_spot', 'Spot'), spotT !== null ? `${f1(spotT)} °C` : '--', ''],
        [T('dl_below', '< target'), `${pct(st.frac)}%`, st.frac >= cfg.coolFrac ? 'teal' : ''],
        [T('dl_soot', 'Soot'), `${Math.round(g2.soot)}%`, g2.soot <= cfg.sootDone ? 'teal' : 'amber'],
        [T('dl_saline', 'Saline'), `${Math.round(g2.ml + (cfg.bottles - g2.bottle) * cfg.bottleMl)} mL`, ''],
      ];
    },
    devDepth(c, W, H) {
      const g = this.g, plan = this.plan, X = this.devXf(W, H);
      c.fillStyle = '#0b1014'; c.fillRect(X.ox, X.oy, X.w, X.h);
      // grid
      c.strokeStyle = 'rgba(255,255,255,.04)'; c.lineWidth = 1;
      for (let x = X.ox; x < X.ox + X.w; x += 12) { c.beginPath(); c.moveTo(x, X.oy); c.lineTo(x, X.oy + X.h); c.stroke(); }
      for (let y = X.oy; y < X.oy + X.h; y += 12) { c.beginPath(); c.moveTo(X.ox, y); c.lineTo(X.ox + X.w, y); c.stroke(); }
      const sz = 0.006 * X.k;
      plan.cells.forEach(cl => {
        const x = X.x(cl.s) - sz / 2, y = X.y(cl.t) - sz / 2;
        if (!cl.tested) { c.fillStyle = 'rgba(255,255,255,.07)'; c.fillRect(x + 1, y + 1, sz - 2, sz - 2); return; }
        c.fillStyle = cl.full ? 'rgba(229,72,77,.85)' : 'rgba(255,170,160,.42)';
        c.fillRect(x + 0.5, y + 0.5, sz - 1, sz - 1);
      });
      this.devOutline(c, X, 0.45);
      plan.zones.forEach(Z => {
        if (!Z.found) return;
        c.strokeStyle = 'rgba(178,120,255,.95)'; c.lineWidth = 1.6; c.setLineDash([4, 3]);
        this.polyPath(c, Z.poly, X); c.stroke(); c.setLineDash([]);
      });
      const tested = plan.cells.filter(x => x.tested).length;
      const est = g.as.est;
      this.legend(c, W, H, [['rgba(255,170,160,.75)', T('lg_blanch', 'Blanches')], ['rgba(229,72,77,.95)', T('lg_fixed', 'Fixed')], ['rgba(255,255,255,.2)', T('lg_untested', 'Untested')]]);
      return [
        [T('dl_tested', 'Tested'), `${pct(tested / Math.max(1, plan.cells.length))}%`, tested / Math.max(1, plan.cells.length) >= this.cfg.assessCover ? 'teal' : ''],
        [T('dl_presses', 'Presses'), String(g.as.tests), ''],
        [T('dl_fixed', 'Fixed'), String(g.as.fixed), g.as.fixed ? 'red' : ''],
        [T('dl_full', 'Full thick.'), est === null ? '--' : `${Math.round(est)}%`, est ? 'red' : 'teal'],
        [T('dl_areas', 'Areas'), String(plan.zones.filter(Z => Z.found).length), ''],
      ];
    },
    legend(c, W, H, items) {
      c.font = '500 10px Lexend, sans-serif';
      let x = 10;
      const y = H - 9;
      items.forEach(([col, label]) => {
        c.fillStyle = col; c.fillRect(x, y - 7, 8, 8);
        c.fillStyle = 'rgba(255,255,255,.7)'; c.fillText(label, x + 12, y);
        x += 16 + c.measureText(label).width + 10;
      });
    },
    devTissue(c, W, H) {
      const plan = this.plan, g = this.g, X = this.devXf(W, H);
      this.devPhoto(c, X);
      [...plan.blisters, ...plan.flaps].forEach(it => {
        const x = X.x(it.s), y = X.y(it.t), r = Math.max(3, (it.r || it.w / 2) * X.k);
        c.lineWidth = 1.5;
        if (it.removed) { c.strokeStyle = 'rgba(15,212,196,.9)'; c.beginPath(); c.moveTo(x - 4, y); c.lineTo(x - 1, y + 3); c.lineTo(x + 5, y - 4); c.stroke(); return; }
        c.strokeStyle = g.db.grip && g.db.grip.item === it ? '#fff' : 'rgba(243,195,90,.95)';
        c.beginPath();
        if (it.kind === 'blister') c.arc(x, y, r, 0, TAU); else c.rect(x - r, y - r * 0.7, r * 2, r * 1.4);
        c.stroke();
      });
      this.legend(c, W, H, [['rgba(243,195,90,.95)', T('lg_left', 'To remove')], ['rgba(15,212,196,.9)', T('lg_done', 'Removed')]]);
      const tot = Math.max(1, g.db.total);
      return [
        [T('dl_blisters', 'Blisters'), `${plan.blisters.filter(b => !b.removed).length}`, ''],
        [T('dl_flaps', 'Dead skin'), `${plan.flaps.filter(b => !b.removed).length}`, ''],
        [T('dl_debrided', 'Debrided'), `${pct(g.db.removed / tot)}%`, g.db.removed / tot >= this.cfg.debridedMin ? 'teal' : ''],
        [T('dl_fumbles', 'Slipped'), String(g.db.fumbles), g.db.fumbles ? 'amber' : ''],
      ];
    },
    // a calm "visible light" rendition of the burn for the non-thermal modes
    devPhoto(c, X) {
      const Hh = this.heat;
      const small = this.photoImg || (this.photoImg = mkCanvas(Hh.nx, Hh.ny));
      if (!this.photoDone) {
        const sc = small.getContext('2d'), id = sc.createImageData(Hh.nx, Hh.ny), d = id.data;
        for (let k = 0; k < Hh.mask.length; k++) {
          const m = Hh.mask[k];
          d[k * 4] = lerp(52, 120, m); d[k * 4 + 1] = lerp(44, 40, m); d[k * 4 + 2] = lerp(40, 38, m); d[k * 4 + 3] = 255;
        }
        sc.putImageData(id, 0, 0);
        this.photoDone = true;
      }
      c.imageSmoothingEnabled = true;
      c.drawImage(small, X.ox, X.oy, X.w, X.h);
      this.devOutline(c, X, 0.3);
    },
    devExcise(c, W, H) {
      const plan = this.plan, g = this.g, X = this.devXf(W, H);
      this.devPhoto(c, X);
      let cutAll = 0;
      plan.zones.forEach(Z => {
        if (Z.excised) {
          c.fillStyle = 'rgba(190,40,34,.85)'; this.polyPath(c, Z.cutPoly, X); c.fill();
        } else {
          c.fillStyle = 'rgba(60,40,28,.9)'; this.polyPath(c, Z.poly, X); c.fill();
        }
        const N = Z.bins.length, P = Z.cutPoly, L = Z.cum[P.length];
        let done = 0;
        for (let i = 0; i < N; i++) {
          const a = (i / N) * L, b = ((i + 1) / N) * L;
          const pa = this.polyAt(Z, a), pb = this.polyAt(Z, b);
          c.strokeStyle = Z.bins[i] || Z.excised ? 'rgba(15,212,196,.95)' : 'rgba(178,120,255,.85)';
          c.lineWidth = Z.bins[i] || Z.excised ? 2.2 : 1.4;
          c.beginPath(); c.moveTo(X.x(pa[0]), X.y(pa[1])); c.lineTo(X.x(pb[0]), X.y(pb[1])); c.stroke();
          if (Z.bins[i]) done++;
        }
        cutAll += Z.excised ? 1 : done / N;
      });
      const ex = this.excisedFrac();
      this.legend(c, W, H, [['rgba(178,120,255,.95)', T('lg_line', 'Marked line')], ['rgba(15,212,196,.95)', T('lg_cut', 'Cut')], ['rgba(190,40,34,.95)', T('lg_bed', 'Bed')]]);
      return [
        [T('dl_areas', 'Areas'), `${plan.zones.filter(Z => Z.excised).length}/${plan.zones.length}`, ''],
        [T('dl_line', 'Line cut'), `${pct(cutAll / Math.max(1, plan.zones.length))}%`, ''],
        [T('dl_excised', 'Excised'), `${pct(ex)}%`, ex >= this.cfg.minExcised ? 'teal' : ''],
        [T('dl_dev', 'Off line'), g.ex.devN ? `${f1(g.ex.devSum / g.ex.devN * 1000)} mm` : '--', ''],
        [T('dl_blood', 'Blood loss'), `${Math.round(g.ex.blood)} mL`, g.ex.blood > 150 ? 'amber' : ''],
      ];
    },
    polyAt(Z, a) {
      const P = Z.cutPoly, cum = Z.cum;
      let i = 0;
      while (i < P.length - 1 && cum[i + 1] < a) i++;
      const p = P[i], q = P[(i + 1) % P.length], f = clamp((a - cum[i]) / ((cum[i + 1] - cum[i]) || 1e-9), 0, 1);
      return [lerp(p[0], q[0], f), lerp(p[1], q[1], f)];
    },
    drawTrend(mode) {
      const g = this.g, cv = this.devTrend, c = cv.getContext('2d'), W = cv.width, H = cv.height;
      c.clearRect(0, 0, W, H);
      c.fillStyle = 'rgba(255,255,255,.035)'; c.fillRect(0, 0, W, H);
      // faint grid: eight time columns, two value rows
      c.strokeStyle = 'rgba(255,255,255,.05)'; c.lineWidth = 1; c.beginPath();
      for (let i = 1; i < 8; i++) { const x = Math.round(i * W / 8) + 0.5; c.moveTo(x, 0); c.lineTo(x, H); }
      for (let i = 1; i < 3; i++) { const y = Math.round(i * H / 3) + 0.5; c.moveTo(0, y); c.lineTo(W, y); }
      c.stroke();
      let data = [], lo = 0, hi = 1, line = null, color = '#0fd4c4';
      if (mode === 'thermal' || mode === 'depth' || mode === 'tissue') {
        data = g.cool.trend; [lo, hi] = this.tempRange(); line = this.cfg.target;
      } else if (mode === 'donor' && g.hv) {
        data = g.hv.speedTrace; lo = 0; hi = this.cfg.speedMax * 1.6; color = '#f3c35a';
        const P = g.hv.pressTrace;
        if (P.length > 1) {
          c.strokeStyle = 'rgba(178,120,255,.9)'; c.lineWidth = 1.5; c.beginPath();
          P.forEach((v, i) => { const x = (i / Math.max(1, P.length - 1)) * W, y = H - 4 - v * (H - 8); if (i) c.lineTo(x, y); else c.moveTo(x, y); }); c.stroke();
        }
        c.fillStyle = 'rgba(61,220,132,.12)';
        const b0 = H - 4 - this.cfg.pressureBand[1] * (H - 8), b1 = H - 4 - this.cfg.pressureBand[0] * (H - 8);
        c.fillRect(0, b0, W, b1 - b0);
      } else if (mode === 'mesh' && g.ms) {
        data = g.ms.rateTrace; lo = 0; hi = this.cfg.crankMax * 1.8; line = this.cfg.crankMax; color = '#f3c35a';
      } else if (g.cool.trend.length) {
        data = g.cool.trend; [lo, hi] = this.tempRange(); line = this.cfg.target;
      }
      if (line !== null) {
        const y = H - 4 - (line - lo) / (hi - lo) * (H - 8);
        c.setLineDash([4, 4]); c.strokeStyle = mode === 'mesh' ? 'rgba(229,72,77,.8)' : 'rgba(255,255,255,.55)'; c.lineWidth = 1;
        c.beginPath(); c.moveTo(0, y); c.lineTo(W, y); c.stroke(); c.setLineDash([]);
      }
      if (data.length > 1) {
        const n = data.length;
        const grd = c.createLinearGradient(0, 0, 0, H); grd.addColorStop(0, color); grd.addColorStop(1, 'rgba(15,212,196,0)');
        c.beginPath();
        data.forEach((v, i) => { const x = (i / Math.max(1, n - 1)) * W, y = H - 4 - clamp((v - lo) / (hi - lo), 0, 1) * (H - 8); if (i) c.lineTo(x, y); else c.moveTo(x, y); });
        c.strokeStyle = color; c.lineWidth = 2; c.stroke();
        c.lineTo(W, H); c.lineTo(0, H); c.closePath(); c.globalAlpha = 0.18; c.fillStyle = grd; c.fill(); c.globalAlpha = 1;
      }
    },

    /* ═════════════ HUD: case card (top-right) ═════════════ */
    buildCase() {
      const d = this.d, inj = this.inj;
      const name = (d.patient && d.patient.name) || T('patient', 'Patient');
      const ini = String(name).trim().split(/\s+/).slice(0, 2).map(x => x[0] || '').join('').toUpperCase();
      this.caseEl.innerHTML = `
        <div class="cs-hd"><span class="cs-av"><svg viewBox="0 0 40 40"><circle class="bg" cx="20" cy="20" r="17"/><circle class="fg" cx="20" cy="20" r="17"/></svg><b>${esc(ini)}</b></span>
          <div class="cs-who"><div class="nm">${esc(name)}</div><div class="sub">${esc(T('case_sub', 'Burn · %s', inj.regionLabel || inj.region || ''))}</div></div></div>
        <div class="cs-body"><div class="cs-map">${bodySVG(inj.region, null)}</div><div class="cs-rows"></div></div>
        <div class="cs-chips"></div>`;
      this.renderCase();
    },
    renderCase() {
      const g = this.g, inj = this.inj, plan = this.plan, cfg = this.cfg;
      if (!g || !this.caseEl.firstChild) return;
      const b = inj.burn;
      const tbsa = (plan ? plan.A : +b.area || 0) / 18000 * 100;
      const est = g.as.est;
      let depth;
      if (est === null) depth = [T('cr_untested', 'Not tested'), 'amber'];
      else if (est > 0) depth = [T('cr_mixed', 'Full %s%', Math.round(est)), 'red'];
      else depth = [T('cr_partial', 'Partial'), 'teal'];
      const p = Math.round(g.pain);
      const core = g.coreT;
      const rows = [
        [T('cr_depth', 'Depth'), depth[0], depth[1]],
        [T('cr_area', 'Area'), `${Math.round(plan ? plan.A : +b.area || 0)} cm² · ${tbsa < 1 ? f1(tbsa) : Math.round(tbsa)}%`, ''],
        [T('cr_core', 'Core'), `${f1(core)} °C`, core < 35 ? 'red' : core < 36.2 ? 'amber' : ''],
        g.sedated ? [T('cr_pain', 'Pain'), T('cr_sedated', 'Sedated'), 'teal'] : [T('cr_pain', 'Pain'), `${p}%`, p >= 60 ? 'red' : p >= 30 ? 'amber' : 'teal', p / 100],
      ];
      if (g.ex.blood > 0 || this.mode === 'graft') rows.push([T('cr_blood', 'Blood loss'), `${Math.round(g.ex.blood + (g.hv ? g.hv.blood : 0))} mL`, g.ex.blood > 200 ? 'amber' : '']);
      const html = rows.map(r => `<div class="cr ${r[2] || ''}"><span>${esc(r[0])}</span><b>${esc(r[1])}</b>${r[3] !== undefined ? `<i class="m"><i style="width:${(clamp(r[3], 0, 1) * 100).toFixed(0)}%"></i></i>` : ''}</div>`).join('');
      const box = this.caseEl.querySelector('.cs-rows');
      if (box.innerHTML !== html) box.innerHTML = html;
      const chips = [];
      if (g.cool.overcool > 0.5) chips.push(`<span class="bn-chip ${g.cool.overcool > 3 ? 'red' : 'amber'}">${icon('snow')}${esc(T('chip_chill', 'Chilled %ss', Math.round(g.cool.overcool)))}</span>`);
      if (g.done[1]) chips.push(`<span class="bn-chip teal">${icon('check')}${esc(T('chip_cooled', 'Cooled'))}</span>`);
      if (g.done[3] && g.db.total) chips.push(`<span class="bn-chip teal">${icon('check')}${esc(T('chip_debrided', 'Debrided'))}</span>`);
      if (this.mode === 'graft') chips.push(`<span class="bn-chip">${icon('scissors')}${esc(T('chip_graft', 'Graft · %s', this.ratioLabel()))}</span>`);
      const ch = chips.join('');
      const cEl = this.caseEl.querySelector('.cs-chips');
      if (cEl.innerHTML !== ch) cEl.innerHTML = ch;
      // ring = pain (or calm teal when sedated)
      const fg = this.caseEl.querySelector('.cs-av .fg'), C = 2 * Math.PI * 17;
      fg.style.strokeDasharray = `${C.toFixed(1)}`;
      fg.style.strokeDashoffset = `${(C * (1 - (g.sedated ? 1 : clamp(p / 100, 0, 1)))).toFixed(1)}`;
      fg.style.stroke = g.sedated ? 'var(--teal)' : p >= 60 ? 'var(--red)' : p >= 30 ? 'var(--amber)' : 'var(--teal)';
      const map = this.caseEl.querySelector('.cs-map');
      const want = g.step >= 5 && g.step <= 6 ? this.d.donor : null;
      if (map.dataset.donor !== String(want)) { map.dataset.donor = String(want); map.innerHTML = bodySVG(inj.region, want); }
    },
    ratioLabel() { const g = this.g; return (g && g.ms && g.ms.ratio) || '—'; },

    /* ═════════════ procedure panel ═════════════ */
    buildPanel() {
      this.pp = NZA.ui.ProcPanel(this.ui, {
        step: 1, total: 8, tag: this.mode === 'graft' ? T('tag_graft', 'Skin graft') : T('tag_care', 'Burn care'), steps: null,
        title: '', text: '', stats: this.stats(), tools: this.toolList(),
        hints: [{ keys: ['RMB'], label: T('cam_look', 'Look') }, { keys: [T('key_wheel', 'Wheel')], label: T('cam_zoom', 'Zoom') }, { keys: ['R'], label: T('cam_recenter', 'Recentre') }, { keys: ['T'], label: T('cam_thermal', 'Heat overlay') }],
        abort: { label: T('hold_cancel', 'Hold to cancel'), key: 'ESC', seconds: 1.2 },
        onAbort: () => this.abort(),
        onTool: key => this.pickTool(key),
      });
      const body = this.pp.el.querySelector('.pp-body') || this.pp.el;
      const after = body.querySelector('.pp-text');
      this.tip = document.createElement('div'); this.tip.className = 'bn-tip';
      if (after && after.nextSibling) body.insertBefore(this.tip, after.nextSibling); else body.appendChild(this.tip);
      this.slot = document.createElement('div'); this.slot.className = 'bn-slot';
      const ppSlot = this.pp.slot;
      if (ppSlot && ppSlot.parentNode) ppSlot.parentNode.insertBefore(this.slot, ppSlot);
    },
    stats() {
      const g = this.g, inj = this.inj, plan = this.plan;
      const est = g ? g.as.est : null;
      const soot = g ? Math.round(g.cool.soot) : Math.round(+inj.burn.soot || 0);
      return [
        { id: 'site', label: T('st_site', 'Site'), value: inj.regionLabel || inj.region || '', small: true },
        { id: 'area', label: T('st_area', 'Burn area'), value: String(Math.round(plan ? plan.A : +inj.burn.area || 0)), unit: 'cm²' },
        { id: 'soot', label: T('st_soot', 'Soot left'), value: String(soot), unit: '%', tone: g && soot <= this.cfg.sootDone ? 'teal' : soot > 40 ? 'amber' : '' },
        { id: 'full', label: T('st_full', 'Full thickness'), value: est === null || est === undefined ? '--' : String(Math.round(est)), unit: est === null || est === undefined ? '' : '%', tone: est > 0 ? 'red' : '' },
      ];
    },
    toolList() {
      const g = this.g;
      return TOOLS.map(t => {
        const o = { key: t.key, label: T(t.label[0], t.label[1]), icon: t.icon };
        let state = '';
        if (g) {
          if (g.done[t.step] && t.step < g.step) state = 'done';
          if (g.skipped[t.step]) state = 'done';
          if (this.mode === 'care' && t.step >= 4 && t.step <= 7) state = 'locked';
          if (t.step === g.step) state = 'active';
          if (t.id === 'saline' && g.step === 1) o.count = String(Math.max(0, this.cfg.bottles - g.cool.bottle + (g.cool.ml > 0 ? 1 : 0)));
          if (t.id === 'stapler' && g.gr && g.gr.points) o.count = String(g.gr.points.filter(p => !p.done).length);
        }
        o.state = state;
        return o;
      });
    },
    refreshTools() { if (this.pp) this.pp.set({ tools: this.toolList() }); },
    setTip(text, tone = '') {
      if (!this.tip) return;
      this.tip.className = `bn-tip ${tone}`;
      this.tip.innerHTML = text ? `<span>${NZA.rich(text)}</span>` : '';
    },
    flash(type, text, ms) { if (this.pp) this.pp.flash(type, text, ms); },
    markSkips() {
      if (!this.pp) return;
      const g = this.g, segs = this.pp.el.querySelectorAll('.pp-segs i');
      segs.forEach((el, i) => el.classList.toggle('skip', !!(g && g.skipped[i + 1])));
    },

    /* ═════════════ steps ═════════════ */
    stepText(n) {
      const g = this.g, cfg = this.cfg;
      switch (n) {
        case 1: return [T('s1_title', 'Cool the burn'), T('s1_text', 'Hold {LMB} to run saline over the burn. Wash the soot off and bring the whole surface under **%s °C**, then let it rest.', cfg.target)];
        case 2: return [T('s2_title', 'Test the depth'), T('s2_text', 'Hold {LMB} to press the diascope on the burn. Skin that **blanches** is partial thickness; skin that stays **fixed** is full thickness. Walk it across the burn.')];
        case 3: return [T('s3_title', 'Debride'), T('s3_text', 'Grip a blister roof or loose dead skin with {LMB} and pull it away.')];
        case 4: return [T('s4_title', 'Excise the eschar'), T('s4_text', 'Hold {LMB} and trace the **purple line** round each full-thickness area. When the line is cut the eschar lifts off.')];
        case 5: return [T('s5_title', 'Harvest the graft'), T('s5_text', 'Hold {LMB} at the start line and push the dermatome along the thigh at a steady pace. Keep the pressure in the band with the **wheel**.')];
        case 6: return [T('s6_title', 'Mesh the graft'), T('s6_text', 'Pick a carrier with {Q} / {E}, then hold {LMB} and circle the pointer clockwise round the crank to feed the graft through.')];
        case 7: return g && g.gr && g.gr.phase === 'staple'
          ? [T('s7b_title', 'Staple the graft'), T('s7b_text', 'Click each **marked point** round the edge to fire a staple through the graft into the skin.')]
          : [T('s7_title', 'Lay the graft'), T('s7_text', 'Pick the graft up with {LMB}, lay it over the raw bed and let go. {Q} / {E} turn it while you hold it.')];
        case 8: return [T('s8_title', 'Dress the burn'), T('s8_text', 'Pick the burn dressing up by its edge, lay it over the whole burn and let go. Then hold {LMB} and rub it down.')];
      }
      return ['', ''];
    },
    // the step that follows n in this burn's path (for the panel's "Next" line)
    nextStepOf(n) {
      const g = this.g, plan = this.plan;
      if (n >= 8) return null;
      if (this.mode === 'care' && n <= 3) {
        for (let k = n + 1; k <= 3; k++) { if (g.done[k] || g.skipped[k] || (k === 3 && !g.db.total)) continue; return k; }
        return plan.zones.length && (g.as.est === null || g.as.est > 0) && n >= 2 ? 4 : 8;
      }
      return n + 1;
    },
    enterStep(n, first) {
      const g = this.g, S = this.S;
      g.step = n;
      const tx = this.stepText(n);
      const nx = this.nextStepOf(n), steps = [];
      if (nx) steps[n] = T(STEP_NAMES[nx][0], STEP_NAMES[nx][1]);
      this.pp.set({ step: n, title: tx[0], titleTone: '', text: tx[1], steps });
      this.markSkips();
      const act = this.pp.el.querySelector('.pp-act');
      if (act) act.innerHTML = '';
      this.slot.innerHTML = '';
      this.clearTags();
      if (S) S.markers.clear();
      if (n === 1) this.startCool();
      if (n === 2) this.startAssess();
      if (n === 3) this.startDebride();
      if (n === 4) this.startExcise();
      if (n === 5) { this.startHarvest(); return; }
      if (n === 6) { this.startMesh(); return; }
      if (n === 7) this.startGraft();
      if (n === 8) this.startDressing();
      const tool = TOOLS.find(t => t.step === n);
      this.useTool(tool ? tool.id : null);
      this.updatePanel(true);
      this.renderCase();
      if (!first) this.snd('success');
    },
    completeStep(n, msg, type = 'ok') {
      const g = this.g;
      if (!g || g.done[n] || g.step !== n) return;
      g.done[n] = true;
      this.flash(type, msg, 2600);
      this.refreshTools();
      clearTimeout(this.stepTimer);
      this.stepTimer = setTimeout(() => {
        if (this.g !== g || !this.alive || g.step !== n) return;
        this.nextAfter(n);
      }, 800);
    },
    nextAfter(n) {
      const g = this.g;
      if (n === 8) { this.finish(); return; }
      if (this.mode === 'care') {
        for (let k = n + 1; k <= 3; k++) {
          if (g.done[k] || g.skipped[k]) continue;
          if (k === 3 && !g.db.total) { g.done[3] = true; continue; }
          return this.enterStep(k);
        }
        return this.careEnd();
      }
      if (n < 8) this.enterStep(n + 1);
    },
    // after burn care: the dressing, or the graft question when full thickness was found
    careEnd() {
      const g = this.g, plan = this.plan;
      if (plan.zones.length && (g.as.est || 0) > 0) return this.askGraft();
      return this.enterStep(8);
    },
    skipTo(n) {
      const g = this.g;
      for (let k = g.step; k < n && k <= 3; k++) if (!g.done[k]) g.skipped[k] = true;
      this.stopAll();
      if (n === 8 && this.mode === 'care') return this.careEnd();
      this.enterStep(n);
    },
    // number keys: pick a tool; a later care tool skips ahead (press twice)
    pickTool(key) {
      const g = this.g;
      if (!g || this.finished || g.deciding) return;
      const t = TOOLS.find(x => x.key === key);
      if (!t) return;
      if (t.step === g.step) { this.useTool(t.id); return; }
      if (t.step < g.step) return this.flash('warn', T('tool_past', 'That step is behind you.'));
      if (this.mode === 'care' && t.step >= 4 && t.step <= 7) return this.flash('warn', T('tool_graft', 'Those instruments are for the skin graft — finish the burn care first.'));
      if (this.mode === 'graft') return this.flash('warn', T('tool_order', 'Finish **%s** first.', T(STEP_NAMES[g.step][0], STEP_NAMES[g.step][1])));
      const now = performance.now();
      if (this.skipArm && this.skipArm.key === key && now - this.skipArm.t < 2600) {
        this.skipArm = null;
        this.skipTo(t.step);
        return;
      }
      this.skipArm = { key, t: now };
      const what = g.step === 1 ? T('skip_cool', 'the burn is still hot') : g.step === 2 ? T('skip_assess', 'the depth is not tested') : T('skip_debride', 'dead skin is left on the burn');
      this.flash('warn', T('skip_confirm', 'Skip ahead? %s — press {%s} again.', what, key), 2600);
    },
    stopAll() {
      const g = this.g, S = this.S;
      if (!g) return;
      if (S) { S.fluids.jet(false); S.tools.press(false); }
      g.cool.pouring = false;
      if (g.as.press) g.as.press = null;
      if (g.db.grip) this.dropGrip();
      if (g.hv && g.hv.cutting) this.stopCut();
    },
    useTool(id) {
      const g = this.g, S = this.activeScene();
      if (!g) return;
      if (!S) { g.tool = id; this.refreshTools(); this.stepTip(); return; }
      this.stopAll();
      g.tool = id;
      let tool = null;
      if (S === this.S) {
        if (id === 'saline') tool = S.tools.use(this.tb.bottle);
        else if (id === 'diascope') tool = S.tools.use(this.tb.diascope);
        else if (id === 'forceps') { tool = S.tools.use('forceps'); if (tool) tool.set({ open: 1 }); }
        else if (id === 'knife') tool = S.tools.use('scalpel');
        else if (id === 'stapler') tool = S.tools.use(g.gr && g.gr.phase === 'place' ? 'forceps' : this.tb.stapler);
        else S.tools.use(null);
        if (tool && id === 'saline') tool.set({ fill: g.cool.ml / this.cfg.bottleMl, squeeze: 0 });
      } else if (S === this.SB) {
        S.tools.use(id === 'dermatome' && this.tbB ? this.tbB.derm : null);
      }
      this.refreshTools();
      this.stepTip();
    },
    activeScene() { return this.g && this.g.scene === 'B' ? this.SB : this.g && this.g.scene === 'bench' ? null : this.S; },
    stepTip() {
      const g = this.g, cfg = this.cfg;
      if (!g) return;
      switch (g.step) {
        case 1: return this.setTip(g.cool.done ? '' : T('tip_1', 'Sweep the stream slowly over the hottest areas — the imager shows them. Stop when it is cool: the deep heat warms the surface back up if you stop too early.'));
        case 2: return this.setTip(T('tip_2', 'Test at least **%s%** of the burn. Hold and slide: the glass lifts and presses again every few millimetres.', Math.round(cfg.assessCover * 100)));
        case 3: return this.setTip(g.db.total ? T('tip_3', 'Pull each piece about **%s mm** away to tear it free. Let go early and it falls back.', cfg.pullMm) : '');
        case 4: return this.setTip(T('tip_4', 'Stay within **%s mm** of the line. Cutting into healthy skin bleeds and costs you.', f1(cfg.traceTol)));
        case 5: return this.setTip(T('tip_5', 'Aim for **%s–%s mm/s**. Too slow stalls the blade, too fast chatters; too little pressure skips, too much cuts too deep.', cfg.speedMin, cfg.speedMax), '');
        case 6: return this.setTip(T('tip_6', 'Above **%s turns/s** the graft tears. 1:3 covers more but heals slower — use it only when the graft is short.', f1(cfg.crankMax)), '');
        case 7: return this.setTip(g.gr && g.gr.phase === 'staple' ? T('tip_7b', 'Staples every %s mm hold the graft while it takes. Miss the marks and it can shift.', cfg.stapleSpacing) : T('tip_7', 'Cover every bit of raw bed — edges left open heal badly. Overhang is trimmed when you start stapling.'));
        case 8: return this.setTip(T('tip_8', 'Grab the dressing by an **edge**, lay the pad over the whole burn, then rub from the centre out.'));
      }
      return this.setTip('');
    },

    /* ═════════════ input ═════════════ */
    down(e) {
      const g = this.g;
      if (!g || this.finished || e.button !== 0 || g.deciding) return;
      g.lmb = true;
      switch (g.step) {
        case 1: if (g.tool === 'saline') this.S.tools.press(true); break;
        case 2: if (g.tool === 'diascope') this.pressDiascope(); break;
        case 3: if (g.tool === 'forceps') this.grip(); break;
        case 5: if (g.tool === 'dermatome') this.startCut(); break;
        case 7: if (g.tool === 'stapler') this.graftDown(); break;
        case 8: this.dressDown(); break;
      }
    },
    up(e) {
      const g = this.g;
      if (!g || e.button !== 0) return;
      g.lmb = false;
      switch (g.step) {
        case 1: if (this.S) { this.S.fluids.jet(false); this.S.tools.press(false); } g.cool.pouring = false; break;
        case 2: this.releaseDiascope(); break;
        case 3: this.releaseGrip(); break;
        case 4: g.ex.last = null; if (this.S) this.S.tools.press(false); break;
        case 5: this.stopCut(); break;
        case 7: this.graftUp(); break;
        case 8: this.dressUp(); break;
      }
    },
    wheel(e) {
      const g = this.g;
      if (!g || !this.alive) return;
      if (g.step === 5 && g.hv && g.hv.cutting) {
        e.preventDefault();
        g.hv.p = clamp(g.hv.p - Math.sign(e.deltaY) * 0.045, 0, 1);
        g.hv.touched = g.t;
      } else if (g.step === 6 && this.bench && g.scene === 'bench') {
        e.preventDefault();
        this.bench.zoom(Math.sign(e.deltaY));
      }
    },
    turnKey(dir) {
      const g = this.g;
      if (!g) return false;
      if (g.step === 6 && g.ms && !g.ms.locked) { this.setRatio(dir < 0 ? '1:1.5' : '1:3'); return true; }
      if (g.step === 7 && g.gr && g.gr.carried) { g.gr.angGoal += dir * 0.14; return true; }
      return false;
    },
    enterKey() {
      const g = this.g;
      if (this.resultShown) { if (this.canClose) this.closeNow(); return true; }
      if (!g) return false;
      if (g.deciding) return this.decide('graft');
      if (g.step === 3 && g.db.total && g.db.removed / g.db.total >= this.cfg.debridedMin) { this.completeStep(3, T('s3_done_part', 'Enough dead skin removed.')); return true; }
      if (g.step === 5 && g.hv && !g.hv.cutting && g.hv.cut >= 15) { this.finishHarvest(); return true; }
      if (g.step === 7 && g.gr) {
        if (g.gr.phase === 'place' && g.gr.placed) { this.toStapling(); return true; }
        if (g.gr.phase === 'staple' && this.stapledFrac() >= this.cfg.minStaples) { this.completeStep(7, T('s7_done_part', 'Graft stapled.')); return true; }
      }
      return false;
    },
    toggleOverlay() {
      const g = this.g;
      if (!g || !this.ovMesh) return;
      g.overlay = !g.overlay;
      this.snd('click', g.overlay ? 1200 : 800);
    },

    /* ═════════════ frame (scene A) ═════════════ */
    frameA(dt) {
      const g = this.g;
      if (!g || !this.alive || g.scene !== 'A') return;
      g.t += dt;
      const S = this.S, cfg = this.cfg;
      const jet = g.cool.pouring ? g.cool.jet : null;
      this.heat.step(dt, jet);
      this.lastStats = this.heat.stats(cfg.target);
      if (this.bnU) { const u = this.bnU.uBnHot; u.value = lerp(u.value, clamp((this.lastStats.mean - 30) / 14, 0, 1), clamp(dt * 1.5, 0, 1)); }
      if (S.tools.hit) this.spot = [S.tools.hit.s, S.tools.hit.t];
      this.updatePain(dt);
      switch (g.step) {
        case 1: this.tickCool(dt); break;
        case 2: this.tickAssess(dt); break;
        case 3: this.tickDebride(dt); break;
        case 4: this.tickExcise(dt); break;
        case 7: this.tickGraft(dt); break;
        case 8: this.tickDressing(dt); break;
      }
      this.tickFx(dt);
      this.tickCommon(dt);
    },
    tickCommon(dt) {
      const g = this.g;
      g.trendT -= dt;
      if (g.trendT <= 0) {
        g.trendT = 0.5;
        if (this.lastStats) { g.cool.trend.push(this.lastStats.mean); if (g.cool.trend.length > 120) g.cool.trend.shift(); }
      }
      g.uiT -= dt; g.devT -= dt; g.caseT -= dt;
      if (g.uiT <= 0) { g.uiT = 0.12; this.updatePanel(); }
      if (g.devT <= 0) { g.devT = 0.09; this.drawDevice(); }
      if (g.caseT <= 0) { g.caseT = 0.3; this.renderCase(); }
      this.updateCursor();
      this.updateTags();
    },
    updatePain(dt) {
      const g = this.g, st = this.lastStats;
      g.painSpike *= Math.exp(-dt * 1.0);
      if (g.sedated) { g.pain = 0; return; }
      const heatF = st ? clamp((st.mean - 30) / Math.max(4, (this.heat.peak || 50) - 30), 0, 1) : 1;
      g.pain = clamp(g.pain0 * (0.42 + 0.58 * heatF) + g.painSpike, 0, 100);
      // body heat: long cold pours chill the patient
      if (g.cool.pouring) g.coreT -= (st && st.mean < this.cfg.overcool ? 0.05 : 0.004) * dt;
      else g.coreT += 0.0015 * dt;
    },
    hurt(amount) {
      const g = this.g;
      if (g.sedated || !g.conscious) return;
      g.painSpike = Math.min(55, g.painSpike + amount);
      if (g.painSpike > 18 && Math.random() < 0.45) {
        const S = this.activeScene();
        if (S) S.controls.shake(0.45, 320);
        this.say(['say_ow1', 'Ow — careful!'], ['say_ow2', 'That stings!'], ['say_ow3', 'Argh… easy, please!'], ['say_ow4', 'Is it bad? It hurts…']);
        NZA.post('burn:pain', { pain: Math.round(g.pain) });
      }
    },
    say(...lines) {
      const g = this.g;
      if (!g || g.sedated || !g.conscious || g.t - g.lastSay < 3.4) return;
      g.lastSay = g.t;
      const l = lines[Math.floor(Math.random() * lines.length)];
      NZA.speech({ name: (this.d.patient && this.d.patient.name) || T('patient', 'Patient'), text: T(l[0], l[1]), ms: 2600 });
    },
    sayOnce(id, key, text) {
      const g = this.g;
      if (!g || g.spoke[id]) return;
      g.spoke[id] = true;
      g.lastSay = -9;
      this.say([key, text]);
    },
    sayLater(key, text, ms) {
      clearTimeout(this.sayTimer);
      this.sayTimer = setTimeout(() => { if (this.alive && this.g) this.sayOnce(key, key, text); }, ms);
    },

    /* ═════════════ 1 · COOL ═════════════ */
    startCool() {
      const S = this.S;
      S.controls.frame([0.5, 0.5], this.viewW, { instant: false });
      this.tag('hot', { kind: 'hot' });
    },
    tickCool(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, c = g.cool, tool = S.tools.active;
      const bottle = this.tb.bottle;
      // open the next bottle
      if (c.refill > 0) {
        c.refill -= dt;
        S.fluids.jet(false); c.pouring = false;
        if (tool === bottle) bottle.set({ fill: clamp(1 - c.refill / cfg.refillTime, 0, 1), squeeze: 0 });
        this.cursorProgress(1 - clamp(c.refill / cfg.refillTime, 0, 1), T('cur_bottle', 'Next bottle…'));
        if (c.refill <= 0) { c.ml = cfg.bottleMl; c.bottle++; this.refreshTools(); this.snd('click', 520); }
        this.measureCool(dt);
        return;
      }
      const firing = g.tool === 'saline' && g.lmb && c.ml > 0 && S.tools.hit && tool === bottle && bottle.group.visible;
      if (!firing) {
        if (c.pouring) S.fluids.jet(false);
        c.pouring = false;
        if (tool === bottle) bottle.set({ squeeze: 0 });
        if (g.lmb && c.ml <= 0 && c.bottle >= cfg.bottles) this.cursorHint(T('cur_empty', 'Saline used up'), 'red');
        this.measureCool(dt);
        return;
      }
      const hit = S.tools.hit;
      S.fluids.jet({ on: true, from: bottle.tipWorld(), to: hit, wash: { soot: 1.7, grime: 1.5, blood: 0.5, clot: 0.2 }, wet: 1, rate: 1, radius: cfg.jetRadius * MM * 0.72, stream: 0.0007 });
      const use = Math.min(cfg.salineFlow * dt, c.ml);
      c.ml -= use; c.used += use;
      bottle.set({ fill: c.ml / cfg.bottleMl, squeeze: 1 });
      c.pouring = true;
      c.jet = { s: hit.s, t: hit.t, r: cfg.jetRadius * MM, temp: cfg.salineTemp, rate: 1 };
      // hot skin under the stream steams and hisses
      const Tl = this.heat.at(hit.s, hit.t);
      if (Tl > 37) {
        c.steamT -= dt * (Tl - 36) * 1.6;
        while (c.steamT <= 0) { c.steamT += 1; this.puff(hit.point, hit.normal, clamp((Tl - 36) / 20, 0.2, 1)); }
        c.sizzleT -= dt;
        if (c.sizzleT <= 0) { c.sizzleT = 0.32; this.snd('noise', 240, { vol: 0.025 * clamp((Tl - 36) / 12, 0.2, 1), lp: 7000, hp: 2600, attack: 0.1, release: 0.6 }); }
      }
      c.pourT = (c.pourT || 0) - dt;
      if (c.pourT <= 0) { c.pourT = 0.34; this.snd('noise', 380, { vol: 0.018, lp: 2600, hp: 500, attack: 0.15, release: 0.5 }); }
      if (c.ml <= 0.001) {
        S.fluids.jet(false); c.pouring = false;
        if (c.bottle < cfg.bottles) { c.refill = cfg.refillTime; }
        else if (!g.done[1]) {
          c.partial = true;
          this.flash('warn', T('cool_out', 'Out of saline — the surface is %s °C.', f1(this.lastStats.mean)), 3200);
        }
      }
      this.measureCool(dt);
    },
    measureCool(dt) {
      const g = this.g, cfg = this.cfg, c = g.cool, st = this.lastStats;
      if (!st || g.done[1]) return;
      c.soot = c.soot0 * clamp(this.sootTotal() / c.sootTotal0, 0, 1);
      if (st.mean < c.best) c.best = st.mean;
      if (st.mean < 36 && !c.felt) { c.felt = true; this.sayOnce('relief', 'say_relief', 'Oh… that is so much better.'); }
      // over-cooling: a cold flood on a cool burn chills the whole patient
      if (c.pouring && st.mean < cfg.overcool) {
        c.overcool += dt;
        c.warnT -= dt;
        if (c.warnT <= 0) { c.warnT = 4; this.flash('bad', T('cool_over', 'Too cold — %s °C. Stop pouring before the patient gets hypothermic.', f1(st.mean)), 3000); this.sayOnce('cold', 'say_cold', 'I’m… so cold…'); }
      }
      const cooled = st.frac >= cfg.coolFrac;
      if (!c.pouring && cooled) {
        c.holdT += dt;
        this.cursorProgress(clamp(c.holdT / cfg.holdTime, 0, 1), T('cur_hold', 'Holding under %s °C', cfg.target));
        if (c.holdT >= cfg.holdTime) {
          if (c.soot <= cfg.sootDone || (c.ml <= 0 && c.bottle >= cfg.bottles)) {
            c.done = true; c.final = st.mean;
            this.completeStep(1, T('s1_done', 'Cooled — %s °C, soot %s%.', f1(st.mean), Math.round(c.soot)));
          } else if (!c.sootWarned) {
            c.sootWarned = true;
            this.flash('warn', T('cool_soot', 'Cool enough — but **%s%** soot is left. Wash it off.', Math.round(c.soot)), 3600);
          }
        }
      } else c.holdT = 0;
      if (c.partial && !c.pouring && !g.done[1]) {
        c.done = st.frac >= cfg.coolFrac; c.final = st.mean;
        this.completeStep(1, c.done ? T('s1_done', 'Cooled — %s °C, soot %s%.', f1(st.mean), Math.round(c.soot)) : T('s1_done_warm', 'Saline used up — the burn is still %s °C.', f1(st.mean)), c.done ? 'ok' : 'warn');
      }
    },
    puff(point, normal, k) {
      const it = this.steam && this.steam.find(x => x.life <= 0);
      if (!it) return;
      it.life = it.max = 0.9 + Math.random() * 0.8;
      it.sp.position.copy(point).addScaledVector(normal, 0.003);
      it.v.copy(normal).multiplyScalar(0.018 + Math.random() * 0.02).add(new window.THREE.Vector3((Math.random() - 0.5) * 0.012, 0, (Math.random() - 0.5) * 0.012));
      it.k = k; it.size0 = 0.006 + Math.random() * 0.006;
      it.sp.visible = true;
    },

    /* ═════════════ 2 · DEPTH (diascope) ═════════════ */
    startAssess() {
      const S = this.S, plan = this.plan, g = this.g;
      S.controls.frame([0.5, 0.5], this.viewW, { instant: false });
      // re-show earlier tests
      (g.as.marks || []).forEach((m, i) => S.markers.set(`dt${i}`, m));
      void plan;
    },
    onBurn(s, t, pad = 1.1) { return this.plan.dn(s, t) < pad; },
    pressDiascope() {
      const g = this.g, S = this.S, hit = S.tools.hit;
      if (!hit) return;
      if (!this.onBurn(hit.s, hit.t, 1.15)) { this.flash('warn', T('dia_off', 'Press the glass **on the burn**.'), 1800); return; }
      g.as.press = { t: 0, s: hit.s, tt: hit.t, uv: hit.uv, read: false };
      S.tools.press(true);
      this.placeBlanch(hit.s, hit.t);
    },
    placeBlanch(s, t) {
      const old = this.blanch.geometry;
      this.blanch.geometry = conformGeo(this.S, { c: [s, t], size: [0.024, 0.024], n: [18, 18], lift: 0.0005 });
      if (old) old.dispose();
      this.blanchA = 0;
      this.blanchMode = 'press';
    },
    releaseDiascope() {
      const g = this.g;
      if (!g.as.press) return;
      if (!g.as.press.read && g.as.press.t > 0.05) this.flash('warn', T('dia_short', 'Hold the glass down a moment longer.'), 1600);
      g.as.press = null;
      this.S.tools.press(false);
      if (this.blanchMode === 'press' || this.blanchMode === 'blanch') this.blanchMode = 'refill';
    },
    tickAssess(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, P = g.as.press;
      if (!P) return;
      if (!g.lmb) { this.releaseDiascope(); return; }
      P.t += dt;
      const full = P.full !== undefined ? P.full : (P.full = this.fullFracAt(P.s, P.tt, cfg.diascopeMm * MM * 0.5));
      // partial thickness blanches under the glass; full thickness stays as it is
      if (this.blanchMode !== 'fixed') this.blanchA = clamp(P.t / cfg.pressTime, 0, 1) * 0.62 * (1 - smooth(0.35, 0.6, full));
      if (!P.read) this.cursorProgress(clamp(P.t / cfg.pressTime, 0, 1), T('cur_press', 'Pressing…'));
      if (!P.read && P.t >= cfg.pressTime) this.readDiascope(P);
      // slide on: lift and press again a few millimetres further
      const hit = S.tools.hit;
      if (P.read && hit && Math.hypot(hit.s - P.s, hit.t - P.tt) > 0.009 && this.onBurn(hit.s, hit.t, 1.15)) {
        g.as.press = { t: 0, s: hit.s, tt: hit.t, uv: hit.uv, read: false };
        this.placeBlanch(hit.s, hit.t);
      }
    },
    fullFracAt(s, t, r) {
      let n = 0, f = 0;
      for (let y = -r; y <= r; y += 0.0015) for (let x = -r; x <= r; x += 0.0015) {
        if (x * x + y * y > r * r || !this.onBurn(s + x, t + y, 0.97)) continue;
        n++; if (this.plan.inZone(s + x, t + y)) f++;
      }
      return n ? f / n : 0;
    },
    readDiascope(P) {
      const g = this.g, plan = this.plan, cfg = this.cfg, S = this.S;
      P.read = true;
      const R = cfg.diascopeMm * MM * 0.5 * 1.2;
      plan.cells.forEach(c => { if (!c.tested && Math.hypot(c.s - P.s, c.t - P.tt) <= R) c.tested = true; });
      const fixed = P.full > 0.45;
      g.as.tests++;
      if (fixed) g.as.fixed++;
      g.as.marks = g.as.marks || [];
      const mk = { uv: P.uv, kind: 'dot', size: 0.0036, color: fixed ? 0x8c4ee6 : 0x0fd4c4, pulse: false, opacity: 0.95 };
      g.as.marks.push(mk);
      S.markers.set(`dt${g.as.marks.length - 1}`, mk);
      plan.zones.forEach(Z => { if (!Z.found && plan.cells.some(c => c.tested && c.full && inPoly(Z.poly, c.s, c.t))) Z.found = true; });
      const tested = plan.cells.filter(c => c.tested), nFull = tested.filter(c => c.full).length;
      g.as.est = tested.length ? nFull / tested.length * 100 : 0;
      g.as.cover = tested.length / Math.max(1, plan.cells.length);
      this.blanchMode = fixed ? 'fixed' : 'blanch';
      if (fixed) { this.flash('warn', T('dia_fixed', 'Stays **fixed** — full thickness here.'), 2000); this.snd('tone', 300, 120, { vol: 0.05, type: 'triangle' }); }
      else { this.flash('ok', T('dia_blanch', '**Blanches** and refills — partial thickness.'), 2000); this.snd('tone', 880, 70, { vol: 0.04 }); }
      if (!fixed) this.hurt(4);
      if (g.as.cover >= cfg.assessCover && !g.done[2]) {
        const est = Math.round(g.as.est);
        this.completeStep(2, est > 0 ? T('s2_done_full', 'Depth mapped — about %s% full thickness.', est) : T('s2_done_partial', 'Depth mapped — partial thickness only.'), est > 0 ? 'warn' : 'ok');
      }
    },

    /* ═════════════ 3 · DEBRIDE (forceps) ═════════════ */
    startDebride() {
      const S = this.S, plan = this.plan, g = this.g;
      S.controls.frame([0.5, 0.5], this.viewW, { instant: false });
      if (!g.db.total) { this.completeStep(3, T('s3_none', 'No blisters or loose skin to remove.')); return; }
      [...plan.blisters, ...plan.flaps].forEach(it => {
        if (it.removed) return;
        const r = it.kind === 'blister' ? it.r : Math.max(it.w, it.h) * 0.5;
        S.markers.set(`db_${it.id}`, { uv: S.stToUv(it.s, it.t), kind: 'dashed', size: r * 2 + 0.004, color: 0xf3c35a, opacity: 0.5, pulse: false });
      });
    },
    nearItem(s, t) {
      const plan = this.plan;
      let best = null, bd = Infinity;
      [...plan.blisters, ...plan.flaps].forEach(it => {
        if (it.removed) return;
        const reach = it.kind === 'blister' ? it.r + 0.0025 : Math.max(it.w, it.h) * 0.55 + 0.002;
        const d = Math.hypot(it.s - s, it.t - t);
        if (d < reach && d < bd) { bd = d; best = it; }
      });
      return best;
    },
    grip() {
      const g = this.g, S = this.S, hit = S.tools.hit, fc = S.tools.active;
      if (!hit) return;
      const it = this.nearItem(hit.s, hit.t);
      if (!it) { if (fc) fc.set({ open: 0.15 }); this.flash('warn', T('db_nothing', 'Grip a **blister** or **loose skin**.'), 1600); return; }
      g.db.grip = { item: it, s0: hit.s, t0: hit.t, pull: 0 };
      if (fc) fc.set({ open: 0 });
      this.snd('tone', 420, 40, { vol: 0.04, type: 'triangle' });
      if (it.kind === 'blister' && it.dome) g.db.grip.cap = it.dome;
    },
    releaseGrip() {
      const g = this.g, fc = this.S && this.S.tools.active;
      if (fc && g.tool === 'forceps') fc.set({ open: 1 });
      if (g.db.grip) this.dropGrip(true);
    },
    dropGrip(fumble) {
      const g = this.g, gr = g.db.grip;
      if (!gr) return;
      g.db.grip = null;
      const it = gr.item;
      if (it.kind === 'blister' && it.bump) it.bump.set({ height: it.h * 0.85 });
      if (it.kind === 'blister' && it.dome) { it.dome.position.copy(it.dome.userData.base); it.dome.scale.set(1, 1, 0.92); it.dome.rotation.set(0, 0, 0); it.dome.quaternion.setFromUnitVectors(new window.THREE.Vector3(0, 1, 0), it.dome.userData.n); }
      if (it.kind === 'flap' && it.mesh) { it.mesh.position.set(0, 0, 0); it.mesh.rotation.set(0, 0, 0); }
      if (fumble && gr.pull > 0.0015) { g.db.fumbles++; this.flash('warn', T('db_slip', 'It slipped back — grip it and pull further.'), 1800); }
    },
    tickDebride(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, hit = S.tools.hit, gr = g.db.grip;
      if (!gr) {
        if (hit && !g.lmb) {
          const it = this.nearItem(hit.s, hit.t);
          if (it) this.cursorHint(it.kind === 'blister' ? T('cur_blister', 'Grip the blister') : T('cur_flap', 'Grip the dead skin'), 'teal');
        }
        return;
      }
      if (!g.lmb || !hit) return;
      const it = gr.item;
      gr.pull = Math.hypot(hit.s - gr.s0, hit.t - gr.t0);
      const f = clamp(gr.pull / (cfg.pullMm * MM), 0, 1);
      this.cursorProgress(f, T('cur_pull', 'Pull…'));
      const tip = S.tools.active ? S.tools.active.tipWorld() : hit.point;
      if (it.kind === 'blister') {
        it.bump.set({ height: it.h * 0.85 * (1 - 0.8 * f) });
        if (gr.cap) {
          // the roof peels off toward the forceps, wrinkling as it goes
          const b = gr.cap.userData.base;
          gr.cap.position.copy(b).lerp(tip, f * 0.55).addScaledVector(gr.cap.userData.n, f * 0.0025);
          gr.cap.scale.set(1 - f * 0.3, 1 - f * 0.55, 0.92 - f * 0.25);
        }
      } else if (it.mesh) {
        const sp = S.surfaceAt(S.stToUv(it.s, it.t));
        const off = tip.clone().sub(sp.point).multiplyScalar(0.45 * f);
        it.mesh.position.copy(off);
      }
      if (f >= 1) this.removeItem(it);
    },
    removeItem(it) {
      const g = this.g, S = this.S, gr = g.db.grip;
      it.removed = true;
      g.db.grip = null;
      g.db.removed++;
      const uv = S.stToUv(it.s, it.t), sp = S.surfaceAt(uv);
      if (it.kind === 'blister') {
        if (it.bump) { it.bump.remove(); it.bump = null; }
        it.dome = null;
        // the weeping, glistening pink base of a deroofed blister
        this.bareDetail(it.s, it.t, it.r * 1.3);
        S.layers.paint('wet', uv, it.r * 1.25, 1, { hardness: 0.2 });
        // the serum runs out over the burn (engine drops always land as blood, so the film is painted)
        S.layers.paint('wet', S.stToUv(it.s, it.t + it.r * 1.4), it.r * 1.1, 0.9, { hardness: 0.1 });
        S.layers.paint('blood', uv, it.r * 0.95, 0.05, { hardness: 0.2, grain: 0.3, grainScale: 120 });
        if (gr && gr.cap) { gr.cap.material = this.binA.own(gr.cap.material.clone()); this.fx({ mesh: gr.cap, life: 0.6, follow: true }); }
      } else if (it.mesh) {
        this.bareDetail(it.s, it.t, Math.max(it.w, it.h) * 0.62);
        S.layers.paint('wet', uv, Math.max(it.w, it.h) * 0.6, 0.8, { hardness: 0.2 });
        this.fx({ mesh: it.mesh, life: 0.6, follow: true, base: sp.point.clone() });
        it.mesh = null;
      }
      S.markers.remove(`db_${it.id}`);
      this.snd('tone', 640, 60, { vol: 0.05, type: 'triangle' });
      this.hurt(15);
      const tot = Math.max(1, g.db.total), frac = g.db.removed / tot;
      if (g.db.removed >= g.db.total) this.completeStep(3, T('s3_done', 'Debrided — every blister and loose piece is off.'));
      else if (frac >= this.cfg.debridedMin && !g.db.enough) { g.db.enough = true; this.setTip(T('tip_3b', 'Enough is off to dress it — press {Enter} to move on, or finish the rest.'), ''); }
    },
    // small one-off animations (removed skin fades away with the forceps)
    fx(o) { (this.fxList = this.fxList || []).push(Object.assign({ t: 0 }, o)); },
    tickFx(dt) {
      const S = this.S, g = this.g;
      // steam
      if (this.steam) this.steam.forEach(p => {
        if (p.life <= 0) { if (p.sp.visible) p.sp.visible = false; return; }
        p.life -= dt;
        const a = 1 - p.life / p.max;
        p.sp.position.addScaledVector(p.v, dt);
        p.v.multiplyScalar(Math.exp(-dt * 0.6));
        const s = p.size0 * (1 + a * 2.6);
        p.sp.scale.set(s, s, 1);
        p.sp.material.opacity = Math.sin(Math.min(1, a) * Math.PI) * 0.26 * p.k;
      });
      // diascope blanching / capillary refill
      if (this.blanch) {
        // capillary refill: the pale disc fades back to the burn's colour once the glass lifts
        if (this.blanchMode === 'refill') this.blanchA = Math.max(0, this.blanchA - dt * 0.5);
        if (this.blanchMode === 'fixed') this.blanchA = 0;
        this.blanch.material.opacity = this.blanchA;
        this.blanch.visible = this.blanchA > 0.01;
      }
      // eschar crusts lifting off
      (this.lifts || []).forEach(L => {
        L.t += dt;
        const f = clamp(L.t / 0.9, 0, 1), e = f * f * (3 - 2 * f);
        const m = L.mesh;
        m.position.copy(L.n).multiplyScalar(e * 0.012);
        m.position.addScaledVector(L.side, e * 0.01);
        m.material.opacity = 1 - smooth(0.55, 1, f);
        m.material.transparent = true;
        if (f >= 1 && !L.gone) { L.gone = true; this.binA.kill(m); }
      });
      if (this.lifts) this.lifts = this.lifts.filter(L => !L.gone);
      // removed skin
      if (this.fxList) {
        const tool = S && S.tools.active;
        this.fxList.forEach(o => {
          o.t += dt;
          const f = clamp(o.t / o.life, 0, 1);
          if (o.follow && tool && tool.group.visible) { const tp = tool.tipWorld(); if (o.base) tp.sub(o.base); o.mesh.position.lerp(tp, 0.25); }
          o.mesh.traverse(c => { if (c.material) { c.material.transparent = true; c.material.opacity = 1 - f; c.material.depthWrite = f < 0.5; } });
          if (f >= 1 && !o.gone) { o.gone = true; this.binA.kill(o.mesh); }
        });
        this.fxList = this.fxList.filter(o => !o.gone);
      }
      // thermal overlay
      if (this.ovMesh) {
        const want = g.overlay ? 0.78 : 0;
        const m = this.ovMesh.material;
        m.opacity = lerp(m.opacity, want, 1 - Math.exp(-dt * 10));
        this.ovMesh.visible = m.opacity > 0.01;
        g.ovT = (g.ovT || 0) - dt;
        if (this.ovMesh.visible && g.ovT <= 0) { g.ovT = 0.1; this.paintOverlay(); }
      }
    },
    paintOverlay() {
      const Hh = this.heat, cv = this.ovCanvas, c = cv.getContext('2d'), id = c.createImageData(Hh.nx, Hh.ny), d = id.data;
      if (!this.lut || this.lutName !== this.g.pal) { this.lut = palLUT(this.g.pal); this.lutName = this.g.pal; }
      const [lo, hi] = this.tempRange(), lut = this.lut;
      for (let k = 0; k < Hh.T.length; k++) {
        const v = clamp(Math.round((Hh.T[k] - lo) / (hi - lo) * 255), 0, 255);
        const a = clamp(Hh.mask[k] * 1.2 + clamp((Hh.T[k] - 34) / 4, 0, 1) * 0.6, 0, 1);
        d[k * 4] = lut[v * 3]; d[k * 4 + 1] = lut[v * 3 + 1]; d[k * 4 + 2] = lut[v * 3 + 2]; d[k * 4 + 3] = a * 255;
      }
      c.putImageData(id, 0, 0);
      this.ovTex.needsUpdate = true;
    },

    /* ═════════════ after burn care: graft now or later ═════════════ */
    askGraft() {
      const g = this.g, plan = this.plan;
      this.stopAll();
      if (this.S) { this.S.tools.use(null); this.S.markers.clear(); }
      g.tool = null;
      g.deciding = true;
      g.graftOk = null;
      const n = plan.zones.filter(Z => Z.found).length || plan.zones.length;
      this.pp.set({ title: T('dec_title', 'Full-thickness skin found'), titleTone: 'bad',
        text: T('dec_text', '**%s** area(s), about **%s%** of the burn, will not heal on their own. Graft them now, or dress the burn and graft later in theatre.', n, Math.round(g.as.est || 0)) });
      this.setTip('');
      this.renderDecision(T('dec_checking', 'Checking theatre and kit…'), '');
      this.refreshTools();
      NZA.post('burn:graftCheck', {}).then(r => {
        if (!this.alive || this.g !== g || !g.deciding) return;
        g.graftOk = !!(r && r.ok);
        this.renderDecision(g.graftOk ? T('dec_ready', 'Graft kit and theatre ready.') : ((r && r.msg) || T('dec_no', 'The graft cannot be done here.')), g.graftOk ? 'ok' : 'bad');
      });
    },
    renderDecision(status, tone) {
      const g = this.g, act = this.pp.el.querySelector('.pp-act');
      if (!act) return;
      const can = g.graftOk === true;
      act.innerHTML = `
        <div class="bn-dec">
          <div class="st ${tone}"><span class="dot"></span>${esc(status)}</div>
          <button class="pp-done ${can ? '' : 'off'}" data-d="graft">${esc(T('dec_graft', 'Graft now'))}<kbd>G</kbd></button>
          <button class="bn-line" data-d="dress">${esc(T('dec_dress', 'Dress, graft later'))}<kbd>D</kbd></button>
        </div>`;
      act.querySelectorAll('button').forEach(b => b.addEventListener('click', () => this.decide(b.dataset.d)));
    },
    decide(kind) {
      const g = this.g;
      if (!g || !g.deciding) return false;
      if (kind === 'graft') {
        if (g.graftOk !== true) { this.flash('bad', g.graftOk === false ? T('dec_cannot', 'The graft is not possible here — dress the burn.') : T('dec_wait', 'Still checking…'), 2000); return true; }
        g.deciding = false;
        this.finishCare(true);
        return true;
      }
      if (kind === 'dress') {
        g.deciding = false;
        const act = this.pp.el.querySelector('.pp-act');
        if (act) act.innerHTML = '';
        this.enterStep(8);
        return true;
      }
      return false;
    },

    /* ═════════════ care → graft hand-over ═════════════ */
    finishCare(cont) {
      const g = this.g;
      this.stopAll();
      this.careResult = this.careResultCalc(cont);
      g.waitGraft = true;
      this.pp.set({ title: T('cont_title', 'Getting the graft ready'), titleTone: '', text: T('cont_text', 'Saving the burn care and opening the graft kit…') });
      const act = this.pp.el.querySelector('.pp-act');
      if (act) act.innerHTML = `<div class="bn-dec"><div class="st"><span class="ring"></span>${esc(T('cont_wait', 'One moment…'))}</div></div>`;
      NZA.post('burn:finish', this.careResult).then(r => {
        if (!this.alive || this.g !== g) return;
        if (r && r.ok === false) this.onGraftFail({ msg: r.msg || T('err_save', 'The result could not be saved.') });
      });
    },
    onCareDone(o) {
      this.careOutcome = o;
      const g = this.g;
      if (g && this.pp) this.flash('ok', T('care_saved', 'Burn care saved · grade %s', o.grade || '—'), 2600);
    },
    onGraft(d) {
      const g = this.g;
      if (!g || !this.alive) return;
      if (!this.S) { this.d = Object.assign({}, this.d, d); return; }
      if (this.mode === 'graft' && g.step >= 4) return;      // already on the graft
      g.waitGraft = false;
      this.mode = 'graft';
      this.d.graftCase = d;
      g.sedated = true;
      g.done[1] = g.done[1] || !g.skipped[1];
      this.plan.zones.forEach(Z => { Z.found = true; });
      this.pp.set({ tag: T('tag_graft', 'Skin graft') });
      const act = this.pp.el.querySelector('.pp-act');
      if (act) act.innerHTML = '';
      this.enterStep(this.plan.zones.every(Z => Z.excised) ? 5 : 4);
    },
    onGraftFail(o) {
      const g = this.g;
      if (!g) return;
      g.waitGraft = false;
      this.finished = true;
      this.result = this.careResult || this.careResultCalc(true);
      this.showResult(this.result, Object.assign({}, this.careOutcome || {}, { error: o.msg || T('err_graft_start', 'The graft could not be started.'), noGraft: true }));
    },

    /* ═════════════ 4 · EXCISE (knife) ═════════════ */
    startExcise() {
      const S = this.S, plan = this.plan;
      S.controls.frame([0.5, 0.5], this.viewW * 0.92, { instant: false });
      plan.zones.forEach(Z => {
        if (Z.excised) return;
        this.drawInk(Z);
        this.tag(`z${Z.id}`, { kind: 'zone', Z });
      });
    },
    drawInk(Z) {
      const THREE = window.THREE, S = this.S, bin = this.binA;
      if (Z.ink) return;
      if (!this.inkTex) this.inkTex = canvasTex(bin, texInk(), false, true);
      const mat = bin.own(this.MA.ink.clone());
      mat.alphaMap = this.inkTex; mat.userData.shared = false;
      const me = new THREE.Mesh(bin.own(ribbonGeo(S, Z.cutPoly, 0.0011, 0.00022, true)), mat);
      me.renderOrder = 6;
      S.scene.add(me);
      Z.ink = me;
    },
    rebuildCut(Z) {
      const THREE = window.THREE, S = this.S, bin = this.binA;
      if (Z.cutMesh) bin.kill(Z.cutMesh);
      const grp = new THREE.Group();
      const N = Z.bins.length, L = Z.cum[Z.cutPoly.length];
      let i = 0;
      while (i < N) {
        if (!Z.bins[i]) { i++; continue; }
        let j = i;
        while (j + 1 < N && Z.bins[j + 1]) j++;
        const pts = [];
        const a = (i / N) * L, b = ((j + 1) / N) * L;
        for (let x = a; x <= b + 1e-6; x += 0.0008) pts.push(this.polyAt(Z, Math.min(x, b)));
        if (pts.length >= 2) {
          const me = new THREE.Mesh(ribbonGeo(S, pts, 0.0008, 0.0003, false), this.MA.cut);
          me.renderOrder = 7; grp.add(me);
        }
        i = j + 1;
      }
      S.scene.add(grp);
      Z.cutMesh = grp;
    },
    tickExcise(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, hit = S.tools.hit, plan = this.plan;
      if (!g.lmb || !hit) { g.ex.last = null; return; }
      S.tools.press(true);
      const tol = cfg.traceTol * MM;
      const moving = !g.ex.last || Math.hypot(hit.s - g.ex.last[0], hit.t - g.ex.last[1]) > 0.00025;
      let onLine = false;
      plan.zones.forEach(Z => {
        if (Z.excised) return;
        const near = polyNearest(Z.cutPoly, hit.s, hit.t, Z.cum);
        if (near.d > tol) return;
        onLine = true;
        if (!moving) return;
        const N = Z.bins.length, k = Math.floor(near.at * N);
        let changed = false;
        for (let q = -1; q <= 1; q++) { const ii = (k + q + N) % N; if (!Z.bins[ii]) { Z.bins[ii] = 1; changed = true; } }
        g.ex.devSum += near.d; g.ex.devN++;
        if (changed) Z.dirty = true;
      });
      if (moving && onLine) S.layers.paint('blood', hit.uv, 0.0005, 0.22, { hardness: 0.35 });
      if (moving && !onLine && g.ex.last && this.onBurn(hit.s, hit.t, 1.25) && !plan.zones.some(Z => !Z.excised && inPoly(Z.cutPoly, hit.s, hit.t))) {
        g.ex.strays += dt * 4;
        S.layers.stroke('blood', S.stToUv(g.ex.last[0], g.ex.last[1]), hit.uv, 0.00035, 0.2, { hardness: 0.4 });
        g.ex.warnT = (g.ex.warnT || 0) - dt;
        if (g.ex.warnT <= 0) { g.ex.warnT = 2.4; this.flash('warn', T('ex_stray', 'Off the line — that is skin that would heal.'), 1800); }
      }
      g.ex.last = [hit.s, hit.t];
      g.ex.rebuildT = (g.ex.rebuildT || 0) - dt;
      if (g.ex.rebuildT <= 0) {
        g.ex.rebuildT = 0.08;
        plan.zones.forEach(Z => {
          if (!Z.dirty || Z.excised) return;
          Z.dirty = false;
          this.rebuildCut(Z);
          const frac = Z.bins.reduce((a, b) => a + b, 0) / Z.bins.length;
          if (frac >= cfg.traceDone) this.exciseZone(Z);
        });
      }
      if (onLine) this.cursorHint(T('cur_cut', 'Cutting'), 'red');
    },
    exciseZone(Z) {
      const THREE = window.THREE, g = this.g, S = this.S, plan = this.plan;
      Z.excised = true;
      if (Z.ink) { this.binA.kill(Z.ink); Z.ink = null; }
      if (Z.cutMesh) { this.binA.kill(Z.cutMesh); Z.cutMesh = null; }
      this.untag(`z${Z.id}`);
      if (Z.plate) {
        const sp = S.surfaceAt(S.stToUv(Z.plateC[0], Z.plateC[1]));
        const Ts = new THREE.Vector3(), Tt = new THREE.Vector3();
        S._tangents(Z.plateC[0], Z.plateC[1], Ts, Tt);
        (this.lifts = this.lifts || []).push({ mesh: Z.plate, t: 0, n: sp.normal.clone(), side: Tt.multiplyScalar(-1) });
        Z.plate = null;
      }
      this.makeBed(Z, false);
      const cm2 = Z.cutArea * 1e4;
      g.ex.blood += cm2 * 0.9;
      g.ex.excisedArea += Z.area;
      this.snd('noise', 420, { vol: 0.05, lp: 1200, hp: 200, attack: 0.05, release: 0.6 });
      this.flash('ok', T('ex_zone', 'Eschar off — %s cm² of raw bed.', Math.round(cm2)), 2200);
      if (plan.zones.every(z => z.excised)) this.completeStep(4, T('s4_done', 'Every full-thickness area is excised.'));
    },
    excisedFrac() {
      const zs = this.plan.zones;
      const tot = zs.reduce((a, Z) => a + Z.area, 0);
      return tot ? zs.filter(Z => Z.excised).reduce((a, Z) => a + Z.area, 0) / tot : 0;
    },
    bedAreaMm2() { return this.plan.zones.filter(Z => Z.excised).reduce((a, Z) => a + Z.cutArea, 0) * 1e6; },

    /* ═════════════ 5 · HARVEST (donor scene) ═════════════ */
    startHarvest() {
      const g = this.g;
      this.stopAll();
      if (g.scene === 'B' && this.SB) { this.harvestReady(); return; }
      if (this.S) this.S.tools.use(null);
      g.scene = 'switching';
      this.showVeil(T('veil_donor', 'Donor site · %s', this.d.donorLabel || T('donor_thigh', 'Thigh')), T('veil_donor_sub', 'Draping the thigh for the dermatome'));
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive && this.g === g) this.buildSceneB(); }));
    },
    buildSceneB() {
      const THREE = window.THREE, d = this.d, cfg = this.cfg, g = this.g;
      if (this.S) this.S.stop();
      if (this.canvasA) this.canvasA.style.display = 'none';
      let SB;
      try {
        this.binB = makeBin();
        SB = NZA3D.createScene(this.stage, {
          tone: d.tone !== undefined ? +d.tone : 0.3, region: d.donor || 'l_upper_leg', sex: (d.patient && d.patient.sex) || 'm',
          seed: (this.seed + 77) >>> 0, quality: cfg.quality, focus: { uv: [0.5, 0.5], size: [0.16, 0.05], view: 0.215 },
          work: [0.21, 0.09], drape: { radius: 0.1, uv: [0.5, 0.5] },
        });
      } catch (e) {
        console.error('[burn] donor scene', e);
        return this.fallbackHarvest();
      }
      this.SB = SB;
      const bin = this.binB, M = this.MB = makeMats(bin);
      const bed = this.bedAreaMm2() || 1800;
      const Lneed = clamp(Math.round(bed / (cfg.graftWidth * 1.45)), 25, 135);
      const L3 = clamp(Math.round(bed / (cfg.graftWidth * 2.6)), 15, 135);
      // the planned strip is centred in the clear middle of the screen (HUD column left, tool belt right)
      const sStart = -clamp(Lneed * MM / 2 + 0.01, 0.03, 0.078), Lmax = 140;
      // a slightly oblique view from the side the blade travels to: the trailing handle leans away and
      // the raw donor bed behind the head stays in sight
      SB.controls.frame(SB.stToUv(sStart + Lneed * MM * 0.5, 0.006), clamp((Lneed * MM + 0.1) / 0.56, 0.26, 0.38), { yaw: 0.3, pitch: 1.08 });
      g.hv = {
        sStart, Lneed, L3, Lmax, cut: 0, front: sStart, p: 0.56, drift: 0, cutting: false, speed: 0,
        thin: new Float32Array(Lmax + 2).fill(1), wobble: new Float32Array(Lmax + 2), qual: new Float32Array(Lmax + 2).fill(1),
        speedTrace: [], pressTrace: [], traceT: 0, warnT: 0, motorT: 0, blood: 0, texT: 0, built: 0, stripLen: 0,
      };
      // surgical marker: the planned strip and the 1:3 tick
      const W2 = cfg.graftWidth * MM / 2;
      const rect = [[sStart, -W2], [sStart + Lneed * MM, -W2], [sStart + Lneed * MM, W2], [sStart, W2]];
      const inkTex = canvasTex(bin, texInk(), false);
      const ink = bin.own(M.ink.clone()); ink.alphaMap = inkTex; ink.userData.shared = false;
      const r1 = new THREE.Mesh(bin.own(ribbonGeo(SB, this.densify(rect, 0.002), 0.001, 0.0002, true)), ink); r1.renderOrder = 6; SB.scene.add(r1);
      const tick = [[sStart + L3 * MM, -W2 - 0.004], [sStart + L3 * MM, -W2 + 0.006]];
      const r2 = new THREE.Mesh(bin.own(ribbonGeo(SB, this.densify(tick, 0.001), 0.001, 0.0002, false)), ink); r2.renderOrder = 6; SB.scene.add(r2);
      // skin prep: povidone-iodine painted on in long, overlapping swab strokes round the planned strip
      {
        const R = rng((this.seed + 5) >>> 0), prepW = cfg.graftWidth * MM + 0.042, prepL = Lneed * MM + 0.05, n = 13;
        // a thin, even wash first, then overlapping swab strokes (darker where they overlap, streaky edges)
        SB.layers.paint('iodine', SB.stToUv(sStart + Lneed * MM / 2, 0), [prepL / 2, prepW / 2], 0.2, { hardness: 0.12, grain: 0.7, grainScale: 45 });
        for (let i = 0; i < n; i++) {
          const t = -prepW / 2 + (i + 0.5) * prepW / n + (R() - 0.5) * 0.003;
          const s0 = sStart - 0.024 - R() * 0.01, s1 = sStart + Lneed * MM + 0.02 + R() * 0.012;
          SB.layers.stroke('iodine', SB.stToUv(s0, t), SB.stToUv(s1, t + (R() - 0.5) * 0.005), 0.0042 + R() * 0.0016, 0.09 + R() * 0.08, { hardness: 0.15, grain: 0.75, grainScale: 60 });
        }
        for (let i = 0; i < 6; i++) SB.layers.paint('iodine', SB.stToUv(sStart - 0.02 + R() * (Lneed * MM + 0.04), (R() - 0.5) * prepW), (1 + R() * 2.5) * MM, 0.18 + R() * 0.18, { hardness: 0.3, grain: 0.5 });
      }
      // dermatome: held about 25° off the skin, handle trailing behind the blade (see alignDerm)
      const tilt = 1.12;
      this.tbB = { derm: mkTool(SB, bin, 'dermatome', buildDermatome(bin, M, tilt), { lift: 0.0042, pressLift: 0.0003, tilt, yaw: Math.PI * 0.97, roll: 0, shadow: 0.07 }) };
      this.tbB.derm.group.visible = true; this.tbB.derm.group.position.set(0, -5, 0);
      SB.prewarm([], false);
      this.tbB.derm.group.visible = false;
      this.stripTex = canvasTex(bin, texGraft({ seed: this.seed, length: 50, width: cfg.graftWidth, mode: 'raw', pxmm: 4 }).map);
      SB.layers.decay('wet', 0.05);
      SB.on('frame', dt => this.frameB(dt));
      SB.on('down', e => this.down(e));
      SB.on('up', e => this.up(e));
      SB.start();
      g.scene = 'B';
      this.hideVeil(150);
      this.harvestReady();
    },
    densify(P, step) {
      const out = [];
      for (let i = 0; i < P.length - 1; i++) {
        const a = P[i], b = P[i + 1], n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / step));
        for (let k = 0; k < n; k++) out.push([lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)]);
      }
      out.push(P[P.length - 1]);
      if (P.length > 2) { const a = P[P.length - 1], b = P[0], n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / step)); for (let k = 1; k < n; k++) out.push([lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)]); }
      return out;
    },
    harvestReady() {
      const g = this.g, SB = this.SB, hv = g.hv;
      this.useTool('dermatome');
      this.tag('hvStart', { kind: 'label', st: [hv.sStart, -0.026], text: T('tag_start', 'Start'), scene: 'B' });
      this.tag('hvEnd', { kind: 'label', st: [hv.sStart + hv.Lneed * MM, -0.026], text: T('tag_need', '1:1.5 · %s mm', hv.Lneed), scene: 'B' });
      this.tag('hv3', { kind: 'label', st: [hv.sStart + hv.L3 * MM, 0.028], text: T('tag_need3', '1:3 · %s mm', hv.L3), scene: 'B', tone: 'dim' });
      this.updatePanel(true);
      this.renderCase();
      this.stepTip();
      void SB;
    },
    frameB(dt) {
      const g = this.g;
      if (!g || !this.alive || g.scene !== 'B') return;
      g.t += dt;
      this.updatePain(dt);
      if (g.step === 5) { this.alignDerm(); this.tickHarvest(dt); }
      this.tickCommon(dt);
    },
    // keep the dermatome handle trailing straight back along the strip (−s), whatever the camera does
    alignDerm() {
      const SB = this.SB, d = this.tbB && this.tbB.derm, hit = SB && SB.tools.hit;
      if (!d || !hit) return;
      const a = SB.project(SB.stToUv(hit.s, hit.t)), b = SB.project(SB.stToUv(hit.s - 0.03, hit.t));
      const dx = (b.x - a.x) * window.innerWidth, dy = (a.y - b.y) * window.innerHeight;
      if (dx * dx + dy * dy > 4) d.pose.yaw = Math.atan2(dy, dx);
    },
    startCut() {
      const g = this.g, SB = this.SB, hv = g.hv, hit = SB && SB.tools.hit;
      if (!hv || !hit || hv.done) return;
      const at = hv.sStart + hv.cut * MM;
      if (Math.abs(hit.s - at) > 0.014 || Math.abs(hit.t) > 0.028) {
        this.flash('warn', hv.cut > 0 ? T('hv_resume', 'Set the dermatome down at the end of the cut to carry on.') : T('hv_start', 'Set the dermatome down on the **start line**.'), 2000);
        return;
      }
      hv.cutting = true;
      hv.front = Math.max(hv.front, Math.min(hit.s, at));
      hv.lastT = g.t;
      this.tbB.derm.set({ on: true });
      SB.controls.enabled = false;
      SB.tools.press(true);
      this.snd('tone', 180, 160, { vol: 0.05, type: 'sawtooth', slide: 230 });
    },
    stopCut() {
      const g = this.g, hv = g && g.hv;
      if (!hv || !hv.cutting) return;
      hv.cutting = false;
      if (this.tbB) this.tbB.derm.set({ on: false });
      if (this.SB) { this.SB.controls.enabled = true; this.SB.tools.press(false); }
      this.snd('tone', 230, 180, { vol: 0.04, type: 'sawtooth', slide: 120 });
      if (hv.cut >= hv.Lneed * 0.97 || hv.cut >= hv.Lmax - 1) { this.finishHarvest(); return; }
      if (hv.cut >= 15) this.setTip(T('hv_paused', 'Stopped at **%s mm**. Carry on from the end of the cut, or press {Enter} to take this graft.', Math.round(hv.cut)), 'amber');
    },
    thinFor(p) {
      const [a, b] = this.cfg.pressureBand;
      if (p < a) return 0.22 + 0.78 * Math.pow(p / a, 1.4);
      if (p <= b) return 1 + (p - (a + b) / 2) * 0.5;
      return 1.15 + (p - b) / Math.max(0.05, 1 - b) * 0.65;
    },
    tickHarvest(dt) {
      const g = this.g, SB = this.SB, cfg = this.cfg, hv = g.hv, hit = SB.tools.hit;
      const [pa, pb] = cfg.pressureBand;
      if (hv.cutting) {
        // the hand tires: pressure sags and wanders; the wheel corrects it
        hv.drift += (Math.random() - 0.5) * dt * 3;
        hv.drift *= Math.exp(-dt * 0.9);
        hv.p = clamp(hv.p + (hv.drift * 0.5 - 0.2) * cfg.pressureDrift * dt, 0, 1);
        hv.motorT -= dt;
        if (hv.motorT <= 0) { hv.motorT = 0.22; this.snd('tone', 196 + hv.p * 40, 230, { vol: 0.022, type: 'sawtooth' }); }
        if (hit && Math.abs(hit.t) < 0.032) {
          const nf = Math.min(Math.max(hv.front, hit.s), hv.sStart + hv.Lmax * MM);
          const adv = nf - hv.front;
          hv.speed = lerp(hv.speed, (adv / Math.max(dt, 1e-3)) * 1000, 1 - Math.exp(-dt * 7));
          if (adv > 0) {
            const from = hv.cut;
            hv.front = nf;
            hv.cut = clamp((nf - hv.sStart) * 1000, 0, hv.Lmax);
            for (let mm = Math.floor(from) + 1; mm <= Math.floor(hv.cut); mm++) {
              let th = this.thinFor(hv.p);
              if (hv.speed > cfg.speedMax) th *= 0.8 + Math.random() * 0.35;
              hv.thin[mm] = th;
              hv.wobble[mm] = clamp((Math.abs(hit.t) - 0.002) / 0.006, 0, 1);
              const sp = hv.speed;
              const qs = sp < cfg.speedMin ? 0.5 + 0.5 * clamp(sp / cfg.speedMin, 0, 1) : sp > cfg.speedMax ? Math.max(0.35, 1 - (sp - cfg.speedMax) / cfg.speedMax) : 1;
              const qp = hv.p < pa ? 0.3 + 0.7 * hv.p / pa : hv.p > pb ? Math.max(0.35, 1 - (hv.p - pb) * 2.2) : 1;
              hv.qual[mm] = qs * qp * (1 - 0.5 * hv.wobble[mm]);
            }
            // pin-point bleeding appears behind the blade
            if (Math.random() < 0.6) {
              const s = hv.sStart + Math.random() * hv.cut * MM, t = (Math.random() - 0.5) * cfg.graftWidth * MM * 0.9;
              SB.layers.paint('blood', SB.stToUv(s, t), (0.3 + Math.random() * 0.5) * MM, 0.3 * this.thinFor(hv.p), { hardness: 0.5 });
            }
            if (hv.cut >= hv.Lmax) this.stopCut();
          } else hv.speed = lerp(hv.speed, 0, 1 - Math.exp(-dt * 3));
        }
        // coaching
        hv.warnT -= dt;
        if (hv.warnT <= 0 && hv.cut > 4) {
          let msg = null;
          if (hv.p < pa) msg = T('hv_light', 'Too light — the blade skips. Wheel up.');
          else if (hv.p > pb) msg = T('hv_heavy', 'Too much pressure — it cuts too deep. Wheel down.');
          else if (hv.speed > cfg.speedMax) msg = T('hv_fast', 'Too fast — the blade chatters.');
          else if (hv.speed < cfg.speedMin * 0.6 && g.lmb) msg = T('hv_slow', 'Keep it moving — the blade stalls.');
          if (msg) { hv.warnT = 2.4; this.flash('warn', msg, 1800); }
        }
        hv.blood = hv.cut * cfg.graftWidth / 100 * 0.3;
        this.growDonor(dt);
      }
      hv.traceT -= dt;
      if (hv.traceT <= 0 && hv.cutting) {
        hv.traceT = 0.1;
        hv.speedTrace.push(hv.speed); hv.pressTrace.push(hv.p);
        if (hv.speedTrace.length > 140) { hv.speedTrace.shift(); hv.pressTrace.shift(); }
      }
      if (!hv.cutting && hit && !g.lmb) {
        const at = hv.sStart + hv.cut * MM;
        if (Math.abs(hit.s - at) < 0.014 && Math.abs(hit.t) < 0.028) this.cursorHint(hv.cut > 0 ? T('cur_resume', 'Carry on') : T('cur_start', 'Start here'), 'teal');
      }
      this.pressGauge = true;
    },
    // the raw donor strip behind the blade + the graft riding up over the head
    growDonor(dt) {
      const THREE = window.THREE, g = this.g, hv = g.hv, SB = this.SB, bin = this.binB, cfg = this.cfg;
      hv.texT -= dt;
      if (hv.cut - hv.built > 2 || (hv.texT <= 0 && hv.cut > hv.built)) {
        const rebuildTex = hv.texT <= 0 || !this.donorMesh;
        hv.built = hv.cut;
        const L = Math.max(2, hv.cut);
        const geo = conformGeo(SB, { c: [hv.sStart + L * MM / 2, 0], size: [L * MM, cfg.graftWidth * MM], n: [clamp(Math.round(L / 2), 4, 80), 12], lift: 0.00012 });
        if (!this.donorMesh) {
          this.donorMesh = new THREE.Mesh(geo, bin.own(new THREE.MeshPhysicalMaterial({ roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.08, alphaTest: 0.5, polygonOffset: true, polygonOffsetFactor: -2 })));
          this.donorMesh.receiveShadow = true;
          SB.scene.add(this.donorMesh);
        } else { this.donorMesh.geometry.dispose(); this.donorMesh.geometry = geo; }
        bin.own(geo);
        if (rebuildTex) {
          hv.texT = 0.6;
          const tx = texDonor({ seed: this.seed, length: L, width: cfg.graftWidth, thin: hv.thin, wobble: hv.wobble, cut: L });
          const m = this.donorMesh.material;
          if (m.map) m.map.dispose();
          if (m.normalMap) m.normalMap.dispose();
          m.map = canvasTex(bin, tx.map); m.normalMap = canvasTex(bin, tx.normal, false);
          m.needsUpdate = true;
        }
      }
      // the strip curling up over the dermatome head
      const len = Math.min(hv.cut, 46) * MM;
      if (Math.abs(len - hv.stripLen) > 0.0015) {
        hv.stripLen = len;
        const d = this.tbB.derm;
        if (d.strip) { d.stripGroup.remove(d.strip); d.strip.geometry.dispose(); }
        if (len > 0.002) {
          const curve = new THREE.CatmullRomCurve3([new THREE.Vector3(0, 0.0012, 0.0095), new THREE.Vector3(0, 0.0045, 0.006), new THREE.Vector3(0, 0.0105, 0.0005), new THREE.Vector3(0, 0.017, -0.0045), new THREE.Vector3(0, 0.026, -0.0055), new THREE.Vector3(0, 0.034, -0.001), new THREE.Vector3(0, 0.038, 0.007)]);
          const total = curve.getLength(), f = clamp(len / total, 0.02, 1), segs = 20, W = cfg.graftWidth * MM * 0.96;
          const pos = [], uv = [], idx = [];
          for (let i = 0; i <= segs; i++) {
            const p = curve.getPointAt((i / segs) * f);
            for (const sd of [-1, 1]) { pos.push(sd * W / 2, p.y, p.z); uv.push(i / segs * f, sd < 0 ? 0 : 1); }
          }
          for (let i = 0; i < segs; i++) { const a = i * 2; idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3); }
          const sg = new THREE.BufferGeometry();
          sg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); sg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); sg.setIndex(idx); sg.computeVertexNormals();
          if (!this.stripMat) this.stripMat = bin.own(new THREE.MeshPhysicalMaterial({ map: this.stripTex, roughness: 0.35, clearcoat: 0.8, sheen: 0.5, sheenColor: new THREE.Color(1, 0.9, 0.86), side: THREE.DoubleSide, alphaTest: 0.5 }));
          d.strip = new THREE.Mesh(bin.own(sg), this.stripMat);
          d.strip.castShadow = true;
          d.stripGroup.add(d.strip);
        }
      }
    },
    finishHarvest() {
      const g = this.g, hv = g.hv;
      if (!hv || hv.done) return;
      if (hv.cutting) this.stopCut();
      hv.done = true;
      const q = this.harvestQ();
      this.completeStep(5, T('s5_done', 'Graft harvested — %s × %s mm, quality %s%.', Math.round(hv.cut), this.cfg.graftWidth, Math.round(q * 100)), q >= 0.6 ? 'ok' : 'warn');
    },
    harvestQ() {
      const hv = this.g.hv;
      if (!hv || hv.cut < 1) return 0;
      let s = 0, n = 0;
      for (let mm = 1; mm <= Math.floor(hv.cut); mm++) { s += hv.qual[mm]; n++; }
      return n ? s / n : 0;
    },
    fallbackHarvest() {
      // the donor scene could not be built (out of GPU memory): take a standard graft
      const g = this.g, cfg = this.cfg;
      const bed = this.bedAreaMm2() || 1800;
      const L = clamp(Math.round(bed / (cfg.graftWidth * 1.45)), 25, 135);
      g.hv = { sStart: 0, Lneed: L, L3: L / 2, Lmax: 140, cut: L, thin: new Float32Array(142).fill(1), wobble: new Float32Array(142), qual: new Float32Array(142).fill(0.7), speedTrace: [], pressTrace: [], blood: L * cfg.graftWidth / 100 * 0.3, done: true };
      if (this.canvasA) this.canvasA.style.display = '';
      if (this.S) this.S.start();
      g.scene = 'A';
      this.hideVeil(0);
      g.done[5] = true; g.done[6] = true;
      g.ms = { ratio: '1:1.5', feed: 1, need: 1, tears: [], rateTrace: [], done: true, locked: true };
      this.enterStep(7);
    },

    /* ═════════════ 6 · MESH (bench) ═════════════ */
    startMesh() {
      const g = this.g;
      this.stopAll();
      if (this.SB) this.SB.tools.use(null);
      this.clearTags();
      g.scene = 'switching';
      this.showVeil(T('veil_mesh', 'Graft mesher'), T('veil_mesh_sub', 'Laying the strip on a carrier'));
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive && this.g === g) this.buildBenchScene(); }));
    },
    buildBenchScene() {
      const g = this.g, cfg = this.cfg, hv = g.hv, SB = this.SB;
      if (!SB) return this.fallbackHarvest();
      SB.stop();
      const bed = this.bedAreaMm2() || 1800, area = hv.cut * cfg.graftWidth;
      const cov15 = area * 1.45 / bed, cov3 = area * 2.6 / bed;
      g.ms = { ratio: cov15 >= 0.98 ? '1:1.5' : '1:3', feed: 0, angle: 0, rate: 0, tears: [], rateTrace: [], traceT: 0, lastAng: null, cranking: false, locked: false, done: false, warnT: 0, tearAcc: 0, cov15, cov3, clickT: 0 };
      this.binBench = makeBin();
      const bench = this.bench = buildBench(this.binBench, SB.scene.environment, { ratio: g.ms.ratio });
      g.ms.rawTex = canvasTex(this.binBench, texGraft({ seed: this.seed, length: hv.cut, width: cfg.graftWidth, thin: hv.thin, wobble: hv.wobble, mode: 'raw', pxmm: 5 }).map);
      this.setSlitTex();
      g.ms.need = bench.needFeed;
      const r = SB.renderer;
      r.localClippingEnabled = true;
      const cv = SB.canvas;
      const resize = () => { const w = window.innerWidth, h = window.innerHeight; r.setSize(w, h, false); bench.resize(w, h); };
      resize();
      let drag = null;
      const onDown = e => {
        if (e.button === 2) { drag = { x: e.clientX, y: e.clientY }; e.preventDefault(); return; }
        if (e.button !== 0 || g.step !== 6 || g.ms.done) return;
        g.lmb = true; g.ms.cranking = true; g.ms.lastAng = null; g.ms.locked = true;
        if (this.seg) this.seg.el.classList.add('locked');
      };
      const onMove = e => {
        if (drag) { bench.orbit((e.clientX - drag.x) / window.innerWidth, (e.clientY - drag.y) / window.innerHeight); drag.x = e.clientX; drag.y = e.clientY; }
      };
      const onUp = e => {
        if (e.button === 2) drag = null;
        if (e.button === 0) { g.lmb = false; if (g.ms) { g.ms.cranking = false; g.ms.lastAng = null; } }
      };
      cv.addEventListener('pointerdown', onDown);
      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp);
      window.addEventListener('resize', resize);
      this.benchOff = () => { cv.removeEventListener('pointerdown', onDown); window.removeEventListener('pointermove', onMove); window.removeEventListener('pointerup', onUp); window.removeEventListener('resize', resize); };
      let last = performance.now();
      const loop = now => {
        if (!this.alive || this.bench !== bench) return;
        this.benchRaf = requestAnimationFrame(loop);
        const dt = clamp((now - last) / 1000, 0, 0.05); last = now;
        try { this.frameBench(dt); r.render(bench.scene, bench.cam); } catch (err) { console.error('[burn] bench', err); }
      };
      this.benchRaf = requestAnimationFrame(loop);
      g.scene = 'bench';
      this.hideVeil(150);
      // carrier picker in the procedure column
      this.slot.innerHTML = `<div class="bn-ratio"><span class="lb">${esc(T('ratio_label', 'Carrier'))}</span><div class="sg"></div><span class="kq"><kbd>Q</kbd><kbd>E</kbd></span></div>`;
      this.seg = NZA.ui.Segmented(this.slot.querySelector('.sg'), { options: [{ value: '1:1.5', label: '1:1.5' }, { value: '1:3', label: '1:3' }], value: g.ms.ratio, onChange: v => this.setRatio(v) });
      this.crankEl = document.createElement('div');
      this.crankEl.className = 'bn-crank';
      this.crankEl.innerHTML = `<svg viewBox="0 0 200 200"><circle class="trk" cx="100" cy="100" r="84"/><path class="red" d=""/><circle class="fg" cx="100" cy="100" r="84"/><g class="arrows"><path d="M100 10 l10 6 -10 6z"/><path d="M190 100 l-6 10 -6 -10z"/><path d="M100 190 l-10 -6 10 -6z"/><path d="M10 100 l6 -10 6 10z"/></g></svg><span class="rt"><b>0.0</b><i>${esc(T('u_tps', 'turns/s'))}</i></span>`;
      this.tagsEl.appendChild(this.crankEl);
      this.useTool('mesher');
      this.updatePanel(true);
      this.stepTip();
    },
    setSlitTex() {
      const g = this.g, hv = g.hv, cfg = this.cfg;
      const tex = canvasTex(this.binBench, texGraft({ seed: this.seed, length: hv.cut, width: cfg.graftWidth, thin: hv.thin, wobble: hv.wobble, mode: 'slit', ratio: g.ms.ratio, tears: g.ms.tears, pxmm: 5 }).map);
      if (g.ms.slitTex) g.ms.slitTex.dispose();
      g.ms.slitTex = tex;
      this.bench.setGraft(g.ms.rawTex, tex, hv.cut, cfg.graftWidth);
      this.bench.setFeed(g.ms.feed);
    },
    setRatio(r) {
      const g = this.g;
      if (!g || !g.ms || g.step !== 6) return;
      if (g.ms.locked) { this.flash('warn', T('ms_locked', 'The graft is already in the mesher.'), 1600); if (this.seg) this.seg.set(g.ms.ratio); return; }
      if (g.ms.ratio === r) return;
      g.ms.ratio = r;
      this.bench.setRatio(r);
      this.setSlitTex();
      if (this.seg) this.seg.set(r);
      this.snd('click', 760);
      this.drawDevice(true);
    },
    frameBench(dt) {
      const g = this.g;
      if (!g || g.scene !== 'bench') return;
      g.t += dt;
      this.updatePain(dt);
      if (g.step === 6) this.tickMesh(dt);
      this.tickCommon(dt);
    },
    tickMesh(dt) {
      const g = this.g, ms = g.ms, cfg = this.cfg, bench = this.bench;
      const W = window.innerWidth, H = window.innerHeight, hub = bench.hubScreen(W, H);
      const ang = Math.atan2(this.my - hub.y, this.mx - hub.x);
      let turnsNow = 0;
      if (ms.cranking && !ms.done) {
        if (ms.lastAng !== null) {
          let d = ang - ms.lastAng;
          while (d > Math.PI) d -= TAU;
          while (d < -Math.PI) d += TAU;
          const r = Math.hypot(this.mx - hub.x, this.my - hub.y);
          if (r < 12) d = 0;
          if (d > 0) {
            turnsNow = d / TAU;
            ms.angle += d;
            const feedMm = turnsNow * cfg.feedPerTurn;
            ms.feed = Math.min(ms.need, ms.feed + feedMm * MM);
            if (ms.rate > cfg.crankMax) {
              ms.tearAcc += (ms.rate / cfg.crankMax - 1) * feedMm * 0.09;
              if (ms.tearAcc >= 1) {
                ms.tearAcc = 0;
                const hv = g.hv, at = clamp(hv.cut - (ms.feed * 1000 - 8), 2, hv.cut - 2);
                ms.tears.push({ x: at, y: 6 + Math.random() * (cfg.graftWidth - 12), r: 2.5 + Math.random() * 3 });
                this.flash('bad', T('ms_tear', 'Too fast — the graft tore.'), 2000);
                this.snd('noise', 160, { vol: 0.08, lp: 3000, hp: 800, attack: 0.02, release: 0.4 });
                this.setSlitTex();
              }
            }
            ms.clickT -= feedMm;
            if (ms.clickT <= 0) { ms.clickT = 3.5; this.snd('tick'); }
          } else if (d < -0.04) {
            ms.warnT -= dt;
            if (ms.warnT <= 0) { ms.warnT = 2; this.flash('warn', T('ms_ccw', 'The mesher only feeds **clockwise**.'), 1600); }
          }
        }
        ms.lastAng = ang;
      }
      ms.rate = lerp(ms.rate, turnsNow / Math.max(dt, 1e-3), 1 - Math.exp(-dt * (turnsNow > 0 ? 9 : 4)));
      bench.setCrank(ms.angle);
      bench.setFeed(ms.feed);
      ms.traceT -= dt;
      if (ms.traceT <= 0) { ms.traceT = 0.1; ms.rateTrace.push(ms.rate); if (ms.rateTrace.length > 140) ms.rateTrace.shift(); }
      // crank guide round the hub
      if (this.crankEl) {
        const z = NZA.zoom || 1;
        this.crankEl.style.transform = `translate(${(hub.x / z).toFixed(1)}px,${(hub.y / z).toFixed(1)}px)`;
        const C = 2 * Math.PI * 84, fr = clamp(ms.feed / ms.need, 0, 1);
        const fg = this.crankEl.querySelector('.fg');
        fg.setAttribute('stroke-dasharray', `${(fr * C).toFixed(1)} ${C.toFixed(1)}`);
        this.crankEl.querySelector('.arrows').setAttribute('transform', `rotate(${(ms.angle * 180 / Math.PI) % 360} 100 100)`);
        this.crankEl.classList.toggle('fast', ms.rate > cfg.crankMax);
        this.crankEl.classList.toggle('on', !!ms.cranking);
        this.crankEl.querySelector('.rt b').textContent = f1(ms.rate);
      }
      if (!ms.done && ms.feed >= ms.need - 1e-5) {
        ms.done = true; ms.cranking = false;
        this.completeStep(6, T('s6_done', 'Meshed at %s — %s tear(s).', ms.ratio, ms.tears.length), ms.tears.length ? 'warn' : 'ok');
      }
    },

    /* ═════════════ back to the burn ═════════════ */
    backToA() {
      const g = this.g;
      if (this.benchRaf) { cancelAnimationFrame(this.benchRaf); this.benchRaf = 0; }
      if (this.benchOff) { this.benchOff(); this.benchOff = null; }
      if (this.crankEl) { this.crankEl.remove(); this.crankEl = null; }
      if (this.bench) { this.bench.dispose(); this.bench = null; }
      if (this.binBench) { this.binBench.dispose(); this.binBench = null; }
      if (this.SB) { this.SB.renderer.localClippingEnabled = false; this.SB.dispose(); this.SB = null; }
      if (this.binB) { this.binB.dispose(); this.binB = null; }
      this.donorMesh = null; this.stripMat = null; this.tbB = null;
      if (this.canvasA) this.canvasA.style.display = '';
      if (this.S) { this.S.resize(); this.S.start(); }
      this.clearTags();
      g.scene = 'A';
      g.lmb = false;
    },

    /* ═════════════ 7 · APPLY & STAPLE ═════════════ */
    startGraft() {
      const THREE = window.THREE, g = this.g, S = this.S, cfg = this.cfg, plan = this.plan;
      if (g.scene !== 'A') this.backToA();
      if (this.slot) this.slot.innerHTML = '';
      S.controls.frame([0.5, 0.5], this.viewW * 1.2, { instant: false });
      if (g.gr) { this.stepTip(); return; }
      const hv = g.hv, ms = g.ms;
      const expand = ms.ratio === '1:3' ? 2.6 : 1.45;
      const Lm = hv.cut * MM, Wm = cfg.graftWidth * MM * expand;
      const tx = texGraft({ seed: this.seed, length: hv.cut, width: cfg.graftWidth, expand, thin: hv.thin, wobble: hv.wobble, mode: 'mesh', ratio: ms.ratio, tears: ms.tears.map(t => ({ x: t.x, y: t.y * expand, r: t.r * 1.2 })), pxmm: 5 });
      // rest it beside the burn, toward the viewer if there is room
      const Hh = S.patch.H / 2, Wh = S.patch.W / 2;
      let c = [plan.rx * 0.15, plan.ry + Wm / 2 + 0.012];
      if (c[1] + Wm / 2 > Hh * 0.95) c = [-(plan.rx + Lm / 2 + 0.012), 0];
      if (Math.abs(c[0]) + Lm / 2 > Wh * 0.95) c = [plan.rx * 0.1, -(plan.ry + Wm / 2 + 0.01)];
      const gr = g.gr = { phase: 'place', size: [Lm, Wm], c: c.slice(), cGoal: c.slice(), ang: 0.12, angGoal: 0.12, lift: 0.0003, liftGoal: 0.0003, carried: false, placed: false, coverage: 0, points: null, staples: [], misses: 0, dirty: true, tex: tx, warnT: 0 };
      const mat = this.binA.own(new THREE.MeshPhysicalMaterial({ map: canvasTex(this.binA, tx.map), normalMap: canvasTex(this.binA, tx.normal, false), normalScale: new THREE.Vector2(0.8, 0.8),
        roughness: 0.42, clearcoat: 0.8, clearcoatRoughness: 0.14, sheen: 0.12, sheenColor: new THREE.Color(1, 0.78, 0.72), color: new THREE.Color(0.93, 0.84, 0.82),
        // a split-thickness graft is thin: the red bed glows faintly through it
        transparent: true, opacity: 0.9, alphaTest: 0.5, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -3 }));
      gr.mesh = new THREE.Mesh(new THREE.BufferGeometry(), mat);
      gr.mesh.castShadow = true; gr.mesh.receiveShadow = true; gr.mesh.renderOrder = 3;
      S.scene.add(gr.mesh);
      this.rebuildSheet();
      this.bedPts = [];
      plan.zones.filter(Z => Z.excised).forEach(Z => Z.pts.forEach(p => this.bedPts.push(p)));
      this.trimPolys = plan.zones.filter(Z => Z.excised).map(Z => polyOffset(Z.cutPoly, 0.0022));
    },
    sheetLift(lx, ly) {
      const gr = this.g.gr;
      if (!gr.carried && gr.lift < 0.001) return gr.lift;
      // held from the middle: the ends droop toward the skin
      const ex = Math.abs(lx) / (gr.size[0] / 2), ey = Math.abs(ly) / (gr.size[1] / 2);
      return Math.max(0.0003, gr.lift - (ex * ex * 0.6 + ey * ey * 0.25) * gr.lift * 0.7);
    },
    rebuildSheet() {
      const gr = this.g.gr, S = this.S;
      const geo = conformGeo(S, { c: gr.c, size: gr.size, n: [42, 22], angle: gr.ang, lift: (lx, ly) => this.sheetLift(lx, ly) }, gr.mesh.geometry.attributes.position ? gr.mesh.geometry : null);
      if (geo !== gr.mesh.geometry) { gr.mesh.geometry.dispose(); gr.mesh.geometry = this.binA.own(geo); }
    },
    sheetLocal(s, t) {
      const gr = this.g.gr, dx = s - gr.c[0], dy = t - gr.c[1], ca = Math.cos(gr.ang), sa = Math.sin(gr.ang);
      return [dx * ca + dy * sa, -dx * sa + dy * ca];
    },
    onSheet(s, t, pad = 0) { const gr = this.g.gr, l = this.sheetLocal(s, t); return Math.abs(l[0]) <= gr.size[0] / 2 + pad && Math.abs(l[1]) <= gr.size[1] / 2 + pad; },
    graftCoverage() {
      const pts = this.bedPts || [];
      if (!pts.length) return 0;
      const gr = this.g.gr, tears = (this.g.ms && this.g.ms.tears.length) || 0;
      let n = 0;
      pts.forEach(p => { if (this.onSheet(p[0], p[1], -0.0008)) n++; });
      void gr;
      return clamp(n / pts.length - clamp(tears * 0.03, 0, 0.3), 0, 1);
    },
    graftDown() {
      const g = this.g, S = this.S, gr = g.gr, hit = S.tools.hit;
      if (!gr || !hit) return;
      if (gr.phase === 'place') {
        if (!this.onSheet(hit.s, hit.t, 0.003)) { this.flash('warn', T('gr_grab', 'Pick the graft up — click **on** it.'), 1600); return; }
        gr.carried = true; gr.placed = false;
        gr.off = [hit.s - gr.c[0], hit.t - gr.c[1]];
        gr.liftGoal = 0.008;
        const fc = S.tools.active; if (fc && fc.set) fc.set({ open: 0 });
        this.snd('tone', 360, 50, { vol: 0.04, type: 'triangle' });
        return;
      }
      this.stapleAt(hit);
    },
    graftUp() {
      const g = this.g, gr = g.gr;
      if (!gr || gr.phase !== 'place' || !gr.carried) return;
      gr.carried = false; gr.placed = true; gr.liftGoal = 0.0002;
      const fc = this.S.tools.active; if (fc && fc.set) fc.set({ open: 1 });
      gr.settleT = 0.45;
    },
    tickGraft(dt) {
      const g = this.g, S = this.S, gr = g.gr, hit = S.tools.hit, cfg = this.cfg;
      if (!gr) return;
      if (gr.phase === 'place') {
        if (gr.carried && hit) { gr.cGoal = [hit.s - gr.off[0], hit.t - gr.off[1]]; }
        const k = 1 - Math.exp(-dt * 14);
        const moved = Math.hypot(gr.cGoal[0] - gr.c[0], gr.cGoal[1] - gr.c[1]) > 1e-5 || Math.abs(gr.angGoal - gr.ang) > 1e-4 || Math.abs(gr.liftGoal - gr.lift) > 1e-5;
        gr.c[0] += (gr.cGoal[0] - gr.c[0]) * k; gr.c[1] += (gr.cGoal[1] - gr.c[1]) * k;
        gr.ang += (gr.angGoal - gr.ang) * k;
        gr.lift += (gr.liftGoal - gr.lift) * (1 - Math.exp(-dt * 9));
        if (moved || gr.dirty) { gr.dirty = false; this.rebuildSheet(); }
        if (!gr.carried && hit && this.onSheet(hit.s, hit.t, 0.002) && !g.lmb) this.cursorHint(T('cur_graft', 'Pick up the graft'), 'teal');
        if (gr.placed && gr.settleT !== undefined) {
          gr.settleT -= dt;
          if (gr.settleT <= 0) {
            gr.settleT = undefined;
            gr.coverage = this.graftCoverage();
            if (gr.coverage >= cfg.minCoverage) {
              this.flash('ok', T('gr_cover', 'Covers %s% of the bed — staple it.', pct(gr.coverage)), 2000);
              clearTimeout(this.stepTimer);
              this.stepTimer = setTimeout(() => { if (this.g === g && gr.phase === 'place' && gr.placed && !gr.carried) this.toStapling(); }, 700);
            } else {
              this.flash('warn', T('gr_low', 'Only **%s%** of the bed is covered — pick it up and move it, or press {Enter} to staple anyway.', pct(gr.coverage)), 3600);
            }
          }
        }
        gr.coverage = gr.carried ? this.graftCoverage() : gr.coverage;
        return;
      }
      // stapling: hint the nearest mark
      if (hit && !g.lmb && gr.points) {
        const p = this.nearPoint(hit.s, hit.t);
        if (p) this.cursorHint(T('cur_staple', 'Staple'), 'teal');
      }
    },
    toStapling() {
      const g = this.g, S = this.S, gr = g.gr, cfg = this.cfg, plan = this.plan;
      if (gr.phase === 'staple') return;
      gr.phase = 'staple';
      gr.coverage = this.graftCoverage();
      this.trimSheet();
      // staple marks round each bed, every few millimetres
      gr.points = [];
      plan.zones.filter(Z => Z.excised).forEach(Z => {
        const P = Z.cutPoly, L = Z.cum[P.length], n = Math.max(6, Math.round(L / (cfg.stapleSpacing * MM)));
        for (let i = 0; i < n; i++) {
          const a = (i / n) * L, p = this.polyAt(Z, a), q = this.polyAt(Z, (a + 0.002) % L);
          let dx = q[0] - p[0], dy = q[1] - p[1];
          const l = Math.hypot(dx, dy) || 1; dx /= l; dy /= l;
          gr.points.push({ s: p[0], t: p[1], dir: [-dy, dx], done: false, id: `st${gr.points.length}` });
        }
      });
      gr.points.forEach(p => S.markers.set(p.id, { uv: S.stToUv(p.s, p.t), kind: 'ring', size: 0.0034, color: 0x0fd4c4, pulse: true, opacity: 0.9 }));
      const tx = this.stepText(7);
      this.pp.set({ title: tx[0], text: tx[1] });
      this.useTool('stapler');
      this.refreshTools();
    },
    // cut the overhang away: keep the sheet only over the beds (+2 mm)
    trimSheet() {
      const gr = this.g.gr, src = gr.tex.map, w = src.width, h = src.height;
      const cv = mkCanvas(w, h), c = cv.getContext('2d');
      c.drawImage(src, 0, 0);
      const id = c.getImageData(0, 0, w, h), d = id.data;
      const ca = Math.cos(gr.ang), sa = Math.sin(gr.ang), polys = this.trimPolys || [];
      const step = 2;
      for (let y = 0; y < h; y += step) for (let x = 0; x < w; x += step) {
        const lx = (x / w - 0.5) * gr.size[0], ly = (y / h - 0.5) * gr.size[1];
        const s = gr.c[0] + lx * ca - ly * sa, t = gr.c[1] + lx * sa + ly * ca;
        if (polys.some(P => inPoly(P, s, t))) continue;
        for (let yy = y; yy < Math.min(h, y + step); yy++) for (let xx = x; xx < Math.min(w, x + step); xx++) d[(yy * w + xx) * 4 + 3] = 0;
      }
      c.putImageData(id, 0, 0);
      const m = gr.mesh.material;
      if (m.map) m.map.dispose();
      m.map = canvasTex(this.binA, cv);
      m.needsUpdate = true;
      this.snd('noise', 200, { vol: 0.03, lp: 5000, hp: 1500 });
    },
    nearPoint(s, t) {
      const gr = this.g.gr, tol = this.cfg.stapleTol * MM;
      let best = null, bd = tol;
      (gr.points || []).forEach(p => { if (p.done) return; const d = Math.hypot(p.s - s, p.t - t); if (d < bd) { bd = d; best = p; } });
      return best;
    },
    stapledFrac() { const gr = this.g.gr; return gr && gr.points && gr.points.length ? gr.points.filter(p => p.done).length / gr.points.length : 0; },
    stapleAt(hit) {
      const g = this.g, S = this.S, gr = g.gr;
      const p = this.nearPoint(hit.s, hit.t);
      const tool = S.tools.active;
      if (tool && tool.set) { tool.set({ fire: 1 }); setTimeout(() => { if (tool.set) tool.set({ fire: 0 }); }, 130); }
      if (!p) {
        gr.misses++;
        gr.warnT = 0;
        this.flash('warn', T('st_miss', 'Not on a mark — fire on the **rings** round the edge.'), 1600);
        this.snd('click', 300);
        return;
      }
      p.done = true;
      gr.staples.push(stapleMesh(S, this.binA, this.MA, [p.s, p.t], p.dir));
      S.markers.remove(p.id);
      this.snd('noise', 70, { vol: 0.08, lp: 5000, hp: 900, attack: 0.01, release: 0.5 });
      this.snd('tone', 120, 60, { vol: 0.08, type: 'square' });
      if (S.controls) S.controls.shake(0.12, 90);
      this.refreshTools();
      const fr = this.stapledFrac();
      if (fr >= 1) this.completeStep(7, T('s7_done', 'Graft stapled — %s staples.', gr.staples.length));
      else if (fr >= this.cfg.minStaples && !gr.enough) { gr.enough = true; this.setTip(T('tip_7c', 'Enough to hold it — press {Enter} to dress, or finish the ring.'), ''); }
    },

    /* ═════════════ 8 · DRESSING ═════════════ */
    startDressing() {
      const g = this.g, S = this.S, plan = this.plan;
      if (g.scene !== 'A') this.backToA();
      if (g.dr.D) return;
      const dw = plan.rx * 2 + 0.028, dh = plan.ry * 2 + 0.028, pw = dw - 0.014, ph = dh - 0.014;
      const Hh = S.patch.H / 2, Wh = S.patch.W / 2;
      let uv, ctr;
      // beside the burn (the wide screen has room left and right), else below it
      if (plan.rx + dw + 0.01 < Wh) { ctr = [plan.rx + dw / 2 + 0.01, plan.ry * 0.12]; }
      else if (plan.ry + dh + 0.01 < Hh) { ctr = [plan.rx * 0.08, plan.ry + dh / 2 + 0.008]; }
      else ctr = [plan.rx * 0.08, Math.min(Hh - dh / 2, plan.ry + dh / 2 + 0.004)];
      uv = S.stToUv(ctr[0], ctr[1]);
      g.dr.D = S.dressing.create({ size: [dw, dh], pad: [pw, ph], uv, angle: 0.06 });
      // our own hydrogel burn dressing print on the engine's dressing (its material is per dressing)
      const dm = g.dr.D.mesh && g.dr.D.mesh.material;
      if (dm) { dm.map = canvasTex(this.binA, texBurnDressing(dw, dh, pw, ph, this.seed)); dm.color.setRGB(1, 1, 1); dm.roughness = 0.7; dm.needsUpdate = true; }
      g.dr.restUv = uv; g.dr.ctr = ctr;
      const mid = S.stToUv(ctr[0] / 2, ctr[1] / 2);
      S.controls.frame(mid, clamp(Math.max(this.viewW * 1.25, Math.abs(ctr[0]) + dw + 0.05, (Math.abs(ctr[1]) + dh) * 1.9), 0.12, 0.42), { instant: false, pitch: 1.24 });
      this.burnUvs = plan.pts.filter((_, i) => i % 2 === 0).map(p => S.stToUv(p[0], p[1]));
    },
    dressDown() {
      const g = this.g, S = this.S, D = g.dr.D;
      if (!D) return;
      const hit = S.raycast();
      const pick = D.pick(hit);
      if (pick === 'edge' && D.stuck < 0.25 && D.state !== 'carried') {
        if (D.grab(hit)) { this.stage.classList.add('grabbing'); this.snd('tone', 300, 40, { vol: 0.03, type: 'triangle' }); return; }
      }
      if (D.state === 'placed' || D.state === 'falling') { g.dr.rub = true; return; }
      if (pick === 'body') this.flash('warn', T('dr_edge', 'Pick it up by its **edge**.'));
    },
    dressUp() {
      const g = this.g, D = g.dr.D;
      g.dr.rub = false;
      if (!D) return;
      if (D.state === 'carried') { D.release(); g.dr.settledT = 0; g.dr.tacked = false; this.stage.classList.remove('grabbing'); }
    },
    tackDressing(D) {
      const S = this.S, c = D.center(), at = S.raycast(S.project(c));
      if (!at) return;
      const sz = D.size || [0.06, 0.04];
      for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
        const sp = S.surfaceAt(S.stToUv(at.s + i * sz[0] * 0.3, at.t + j * sz[1] * 0.3));
        if (sp && sp.point) D.rub({ point: sp.point, normal: sp.normal }, 0.45);
      }
    },
    tickDressing(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, D = g.dr.D;
      if (!D) return;
      const hit = S.raycast();
      if (D.state === 'carried') { if (hit) D.move(hit); return; }
      if (!g.lmb) {
        const pick = hit ? D.pick(hit) : null;
        this.stage.classList.toggle('grab', pick === 'edge' && D.stuck < 0.25);
        if (pick === 'edge' && D.stuck < 0.25 && D.state === 'rest') this.cursorHint(T('cur_dgrab', 'Grab the edge'), 'teal');
      }
      if (D.state === 'placed' || D.state === 'falling') {
        g.dr.settledT += dt;
        // hydrogel is tacky: where it lands it grips a little at once, so the sheet does not creep down
        // the curve of the limb before it is rubbed on
        if (!g.dr.tacked && g.dr.settledT > 0.18) { g.dr.tacked = true; this.tackDressing(D); }
        if (g.dr.settledT > 0.4 && (g.dr.coverT = (g.dr.coverT || 0) - dt) <= 0) {
          g.dr.coverT = 0.3;
          g.dr.cover = D.covers(this.burnUvs);
          D.seep(clamp(0.1 + (this.mode === 'graft' ? 0.25 : 0.05), 0, 0.6) * clamp(g.dr.cover, 0.3, 1), S.stToUv(0, 0));
        }
      }
      if (g.dr.rub && g.lmb && hit && (D.state === 'placed' || D.state === 'falling')) {
        D.rub(hit, dt);
        this.cursorProgress(D.stuck, '');
      }
      if (D.state === 'placed' && g.dr.settledT > 0.6 && g.dr.cover < cfg.coverMin && D.stuck < 0.25) {
        g.dr.warnT -= dt;
        if (g.dr.warnT <= 0) { g.dr.warnT = 5; this.flash('warn', T('dr_cover', 'The pad covers only %s% of the burn — lift it by an edge and try again.', pct(g.dr.cover)), 3600); }
      }
      if (!g.done[8] && D.stuck >= cfg.stuckDone && g.dr.settledT > 0.4) {
        g.dr.cover = D.covers(this.burnUvs);
        const big = (this.plan.A || 0) >= cfg.secureAbove && ((this.d.items && +this.d.items.dressing) || 0) > 0;
        g.dr.secured = big;
        this.completeStep(8, big ? T('s8_done_secured', 'Dressed and secured — %s% of the burn covered.', pct(g.dr.cover)) : T('s8_done', 'Dressed — %s% of the burn covered.', pct(g.dr.cover)));
      }
    },

    /* ═════════════ imager pages for the graft ═════════════ */
    devDonor(c, W, H) {
      const g = this.g, hv = g.hv, cfg = this.cfg;
      if (!hv) return [];
      // the strip, mm by mm: thickness (colour) and quality (height)
      const x0 = 14, x1 = W - 14, y0 = 26, y1 = H - 40, L = hv.Lmax;
      c.fillStyle = '#0b1014'; c.fillRect(x0, y0, x1 - x0, y1 - y0);
      const px = (x1 - x0) / L;
      for (let mm = 1; mm <= Math.floor(hv.cut); mm++) {
        const th = hv.thin[mm], q = hv.qual[mm];
        const col = th < 0.6 ? [229, 165, 10] : th > 1.25 ? [229, 72, 77] : [15, 212, 196];
        c.fillStyle = `rgba(${col[0]},${col[1]},${col[2]},${0.35 + q * 0.6})`;
        const hgt = (y1 - y0) * (0.3 + 0.7 * q);
        c.fillRect(x0 + (mm - 1) * px, y1 - hgt, Math.max(1, px - 0.4), hgt);
      }
      // need markers
      const mark = (mm, label, col) => {
        const x = x0 + mm * px;
        c.strokeStyle = col; c.setLineDash([3, 3]); c.beginPath(); c.moveTo(x, y0 - 6); c.lineTo(x, y1 + 4); c.stroke(); c.setLineDash([]);
        c.fillStyle = col; c.font = '600 10px "JetBrains Mono", monospace'; c.fillText(label, Math.min(x + 3, W - 52), y0 - 9);
      };
      mark(hv.L3, '1:3', 'rgba(243,195,90,.9)');
      mark(hv.Lneed, '1:1.5', 'rgba(255,255,255,.85)');
      // blade position
      const bx = x0 + hv.cut * px;
      c.fillStyle = '#fff'; c.fillRect(bx - 1, y0, 2, y1 - y0);
      this.legend(c, W, H, [['rgba(15,212,196,.95)', T('lg_even', 'Even')], ['rgba(229,165,10,.95)', T('lg_thin', 'Thin / skip')], ['rgba(229,72,77,.95)', T('lg_deep', 'Too deep')]]);
      const sp = hv.speed, p = hv.p, [pa, pb] = cfg.pressureBand;
      return [
        [T('dl_length', 'Length'), `${Math.round(hv.cut)} mm`, hv.cut >= hv.Lneed ? 'teal' : ''],
        [T('dl_need', 'Need'), `${hv.Lneed} mm`, ''],
        [T('dl_speed', 'Speed'), `${Math.round(sp)} mm/s`, sp > cfg.speedMax || (hv.cutting && sp < cfg.speedMin) ? 'amber' : 'teal'],
        [T('dl_press', 'Pressure'), `${pct(p)}%`, p < pa || p > pb ? 'amber' : 'teal'],
        [T('dl_quality', 'Quality'), `${pct(this.harvestQ())}%`, ''],
      ];
    },
    devMesh(c, W, H) {
      const g = this.g, ms = g.ms, plan = this.plan, X = this.devXf(W, H);
      if (!ms) return [];
      this.devPhoto(c, X);
      plan.zones.forEach(Z => { if (!Z.excised) return; c.fillStyle = 'rgba(190,40,34,.9)'; this.polyPath(c, Z.cutPoly, X); c.fill(); });
      // the expanded graft footprint (centred on the beds) with its diamond lattice
      const hv = g.hv, cfg = this.cfg;
      const expand = ms.ratio === '1:3' ? 2.6 : 1.45;
      const bx = polyBox([].concat(...plan.zones.filter(Z => Z.excised).map(Z => Z.cutPoly)));
      const cx = (bx[0] + bx[2]) / 2, cy = (bx[1] + bx[3]) / 2;
      const Lm = hv.cut * MM, Wm = cfg.graftWidth * MM * expand;
      c.save();
      c.beginPath(); c.rect(X.x(cx - Lm / 2), X.y(cy - Wm / 2), Lm * X.k, Wm * X.k); c.clip();
      c.fillStyle = 'rgba(15,212,196,.22)'; c.fillRect(X.x(cx - Lm / 2), X.y(cy - Wm / 2), Lm * X.k, Wm * X.k);
      c.strokeStyle = 'rgba(15,212,196,.65)'; c.lineWidth = 1;
      const pxs = (ms.ratio === '1:3' ? 5.2 : 3.6) * MM * X.k * 1.6, pys = (ms.ratio === '1:3' ? 4.2 : 2.6) * MM * X.k * 1.6;
      for (let y = X.y(cy - Wm / 2); y < X.y(cy + Wm / 2) + pys; y += pys) for (let x = X.x(cx - Lm / 2); x < X.x(cx + Lm / 2) + pxs; x += pxs) {
        c.beginPath(); c.moveTo(x, y - pys / 2); c.lineTo(x + pxs / 2, y); c.lineTo(x, y + pys / 2); c.lineTo(x - pxs / 2, y); c.closePath(); c.stroke();
      }
      c.restore();
      c.strokeStyle = 'rgba(15,212,196,.95)'; c.lineWidth = 1.5; c.strokeRect(X.x(cx - Lm / 2), X.y(cy - Wm / 2), Lm * X.k, Wm * X.k);
      this.legend(c, W, H, [['rgba(190,40,34,.95)', T('lg_bed', 'Bed')], ['rgba(15,212,196,.7)', T('lg_graft', 'Graft at %s', ms.ratio)]]);
      const cov = ms.ratio === '1:3' ? ms.cov3 : ms.cov15;
      return [
        [T('dl_ratio', 'Carrier'), ms.ratio, ''],
        [T('dl_cov15', 'Cover 1:1.5'), `${pct(Math.min(1, ms.cov15))}%`, ms.cov15 >= 1 ? 'teal' : 'amber'],
        [T('dl_cov3', 'Cover 1:3'), `${pct(Math.min(1, ms.cov3))}%`, ms.cov3 >= 1 ? 'teal' : 'amber'],
        [T('dl_fed', 'Fed'), `${pct(ms.feed / ms.need)}%`, ''],
        [T('dl_tears', 'Tears'), String(ms.tears.length), ms.tears.length ? 'red' : 'teal'],
      ].concat(cov < 0.85 ? [[T('dl_short', 'Short'), T('dl_short_v', 'graft'), 'red']] : []);
    },
    devGraft(c, W, H) {
      const g = this.g, gr = g.gr, plan = this.plan, X = this.devXf(W, H);
      if (!gr) return [];
      this.devPhoto(c, X);
      plan.zones.forEach(Z => { if (!Z.excised) return; c.fillStyle = 'rgba(190,40,34,.9)'; this.polyPath(c, Z.cutPoly, X); c.fill(); });
      c.save();
      c.translate(X.x(gr.c[0]), X.y(gr.c[1])); c.rotate(gr.ang);
      c.fillStyle = 'rgba(240,200,186,.55)'; c.strokeStyle = 'rgba(255,255,255,.85)'; c.lineWidth = 1.2;
      c.fillRect(-gr.size[0] / 2 * X.k, -gr.size[1] / 2 * X.k, gr.size[0] * X.k, gr.size[1] * X.k);
      c.strokeRect(-gr.size[0] / 2 * X.k, -gr.size[1] / 2 * X.k, gr.size[0] * X.k, gr.size[1] * X.k);
      c.restore();
      (gr.points || []).forEach(p => {
        const x = X.x(p.s), y = X.y(p.t);
        c.fillStyle = p.done ? '#0fd4c4' : 'rgba(255,255,255,.4)';
        c.fillRect(x - 2, y - 2, 4, 4);
      });
      this.legend(c, W, H, [['rgba(190,40,34,.95)', T('lg_bed', 'Bed')], ['rgba(240,200,186,.8)', T('lg_sheet', 'Graft')], ['#0fd4c4', T('lg_staple', 'Staple')]]);
      const n = gr.points ? gr.points.filter(p => p.done).length : 0;
      return [
        [T('dl_cover', 'Bed covered'), `${pct(gr.coverage)}%`, gr.coverage >= this.cfg.minCoverage ? 'teal' : 'amber'],
        [T('dl_staples', 'Staples'), gr.points ? `${n}/${gr.points.length}` : '--', ''],
        [T('dl_misses', 'Misfires'), String(gr.misses), gr.misses ? 'amber' : ''],
        [T('dl_ratio', 'Carrier'), (g.ms && g.ms.ratio) || '--', ''],
      ];
    },
    devCover(c, W, H) {
      const g = this.g, plan = this.plan, X = this.devXf(W, H), D = g.dr.D;
      this.devPhoto(c, X);
      plan.zones.forEach(Z => { if (!Z.excised) return; c.fillStyle = 'rgba(190,40,34,.8)'; this.polyPath(c, Z.cutPoly, X); c.fill(); });
      if (D && D.state !== 'rest') {
        const ctr = D.center(), S = this.S;
        const q = S._toSurf(ctr);
        c.strokeStyle = 'rgba(15,212,196,.95)'; c.lineWidth = 1.5; c.fillStyle = 'rgba(255,255,255,.14)';
        c.fillRect(X.x(q.s - D.pad[0] / 2), X.y(q.t - D.pad[1] / 2), D.pad[0] * X.k, D.pad[1] * X.k);
        c.strokeRect(X.x(q.s - D.size[0] / 2), X.y(q.t - D.size[1] / 2), D.size[0] * X.k, D.size[1] * X.k);
      }
      this.legend(c, W, H, [['rgba(255,255,255,.4)', T('lg_pad', 'Pad')], ['rgba(15,212,196,.95)', T('lg_edge', 'Adhesive edge')]]);
      return [
        [T('dl_dcover', 'Covered'), `${pct(g.dr.cover)}%`, g.dr.cover >= this.cfg.coverMin ? 'teal' : ''],
        [T('dl_stuck', 'Stuck'), `${pct(D ? D.stuck : 0)}%`, D && D.stuck >= this.cfg.stuckDone ? 'teal' : ''],
        [T('dl_mean', 'Mean'), this.lastStats ? `${f1(this.lastStats.mean)} °C` : '--', ''],
      ];
    },

    /* ═════════════ panel refresh ═════════════ */
    updatePanel() {
      const g = this.g, pp = this.pp, cfg = this.cfg;
      if (!g || !pp) return;
      pp.set({ stats: this.stats() });
      let wide = null;
      const st = this.lastStats;
      switch (g.step) {
        case 1: {
          const [lo, hi] = this.tempRange(), m = st ? st.mean : 40;
          const left = Math.round(g.cool.ml + Math.max(0, cfg.bottles - g.cool.bottle) * cfg.bottleMl);
          wide = { label: T('w_temp', 'Surface'), value: f1(m), unit: '°C', tone: m <= cfg.target ? 'teal' : m > 40 ? 'red' : 'amber',
            meter: { value: clamp((m - lo) / (hi - lo), 0, 1), zone: [0, (cfg.target - lo) / (hi - lo)], tone: m <= cfg.target ? '' : m > 40 ? 'red' : 'amber' },
            caption: T('w_temp_cap', 'Target < %s °C · %s mL saline', cfg.target, left), captionTone: g.cool.overcool > 0.5 ? 'red' : '' };
          break;
        }
        case 2: {
          const cv = g.as.cover;
          wide = { label: T('w_tested', 'Tested'), value: String(pct(cv)), unit: '%', tone: cv >= cfg.assessCover ? 'teal' : '',
            meter: { value: cv, zone: [cfg.assessCover, 1] },
            caption: g.as.est === null ? T('w_tested_cap0', 'Press the glass on the burn') : T('w_tested_cap', 'Full thickness ≈ %s%', Math.round(g.as.est)), captionTone: g.as.est ? 'red' : '' };
          break;
        }
        case 3: {
          const tot = Math.max(1, g.db.total), f = g.db.removed / tot;
          wide = { label: T('w_debrided', 'Debrided'), value: String(pct(f)), unit: '%', tone: f >= cfg.debridedMin ? 'teal' : '',
            meter: { value: f, zone: [cfg.debridedMin, 1] }, caption: T('w_debrided_cap', '%s of %s pieces off', g.db.removed, g.db.total) };
          break;
        }
        case 4: {
          const f = this.excisedFrac();
          wide = { label: T('w_excised', 'Excised'), value: String(pct(f)), unit: '%', tone: f >= cfg.minExcised ? 'teal' : '',
            meter: { value: f, zone: [cfg.minExcised, 1] }, caption: T('w_excised_cap', 'Blood loss %s mL', Math.round(g.ex.blood)), captionTone: g.ex.blood > 150 ? 'amber' : '' };
          break;
        }
        case 5: {
          const hv = g.hv;
          if (!hv) break;
          wide = { label: T('w_length', 'Graft'), value: String(Math.round(hv.cut)), unit: 'mm', tone: hv.cut >= hv.Lneed ? 'teal' : '',
            meter: { value: clamp(hv.cut / hv.Lneed, 0, 1), zone: [hv.L3 / hv.Lneed, 1] },
            caption: T('w_length_cap', '%s mm/s · pressure %s%', Math.round(hv.speed), pct(hv.p)), captionTone: hv.p < cfg.pressureBand[0] || hv.p > cfg.pressureBand[1] ? 'amber' : '' };
          break;
        }
        case 6: {
          const ms = g.ms;
          if (!ms) break;
          wide = { label: T('w_mesh', 'Meshing'), value: String(pct(ms.feed / ms.need)), unit: '%', tone: ms.rate > cfg.crankMax ? 'red' : 'teal',
            meter: { value: clamp(ms.feed / ms.need, 0, 1) }, caption: T('w_mesh_cap', '%s turns/s · carrier %s', f1(ms.rate), ms.ratio), captionTone: ms.rate > cfg.crankMax ? 'red' : '' };
          break;
        }
        case 7: {
          const gr = g.gr;
          if (!gr) break;
          if (gr.phase === 'staple') {
            const n = gr.points.filter(p => p.done).length;
            wide = { label: T('w_staples', 'Staples'), value: String(n), unit: `/${gr.points.length}`, tone: 'teal', meter: { value: n / Math.max(1, gr.points.length), zone: [cfg.minStaples, 1] }, caption: T('w_staples_cap', 'Bed covered %s%', pct(gr.coverage)) };
          } else {
            wide = { label: T('w_cover', 'Covered'), value: String(pct(gr.coverage)), unit: '%', tone: gr.coverage >= cfg.minCoverage ? 'teal' : 'amber', meter: { value: gr.coverage, zone: [cfg.minCoverage, 1] }, caption: gr.carried ? T('w_cover_cap', '{Q} / {E} turn it') : T('w_cover_cap2', 'Lay it over the raw bed') };
          }
          break;
        }
        case 8: {
          const D = g.dr.D, s = D ? D.stuck : 0;
          wide = { label: T('w_stuck', 'Adhered'), value: String(pct(s)), unit: '%', tone: s >= cfg.stuckDone ? 'teal' : '',
            meter: { value: s, zone: [cfg.stuckDone, 1] }, caption: D && D.state !== 'rest' && D.state !== 'carried' ? T('w_dcover', 'Covers %s% of the burn', pct(g.dr.cover)) : T('w_stuck_cap', 'Lay it over the burn, then rub it down'), captionTone: D && D.state === 'placed' && g.dr.cover < cfg.coverMin ? 'amber' : '' };
          break;
        }
      }
      if (wide) pp.set({ wide });
    },

    /* ═════════════ scene tags (dark chips anchored in 3D) ═════════════ */
    tag(id, def) {
      this.tags = this.tags || {};
      let t = this.tags[id];
      if (!t) { t = { el: document.createElement('div') }; t.el.className = 'bn-tag'; this.tagsEl.appendChild(t.el); this.tags[id] = t; }
      t.def = def;
      t.el.className = `bn-tag ${def.kind || ''} ${def.tone || ''}`;
      return t;
    },
    untag(id) { const t = this.tags && this.tags[id]; if (t) { t.el.remove(); delete this.tags[id]; } },
    clearTags() { if (this.tags) Object.keys(this.tags).forEach(k => this.untag(k)); },
    updateTags() {
      const g = this.g;
      if (!this.tags || !g) return;
      const W = window.innerWidth, H = window.innerHeight;
      Object.keys(this.tags).forEach(id => {
        const t = this.tags[id], d = t.def;
        const S = d.scene === 'B' ? this.SB : this.S;
        if (!S || (d.scene === 'B') !== (g.scene === 'B') || g.scene === 'bench') { t.el.style.display = 'none'; return; }
        let st = d.st, html = '';
        if (d.kind === 'hot') {
          if (!this.lastStats || g.cool.done || g.step !== 1) { t.el.style.display = 'none'; return; }
          st = this.lastStats.hot;
          html = `<i></i><b>${esc(f1(this.lastStats.max))}°</b><em>${esc(T('tag_hot', 'Hottest'))}</em>`;
        } else if (d.kind === 'zone') {
          const Z = d.Z;
          if (!Z.tagSt) { let best = Z.cutPoly[0]; Z.cutPoly.forEach(p => { if (p[0] - p[1] > best[0] - best[1]) best = p; }); Z.tagSt = [best[0] + 0.0015, best[1] - 0.0015]; }
          st = Z.tagSt;
          const fr = Z.bins.reduce((a, b) => a + b, 0) / Z.bins.length;
          html = `<i></i><b>${esc(T('tag_full', 'Full thickness'))}</b><em>${pct(fr)}%</em>`;
        } else html = `<i></i><b>${esc(d.text || '')}</b>`;
        const p = S.project(S.stToUv(st[0], st[1]));
        if (!p.visible) { t.el.style.display = 'none'; return; }
        t.el.style.display = '';
        if (t.html !== html) { t.el.innerHTML = html; t.html = html; }
        const z = NZA.zoom || 1;
        t.el.style.transform = `translate(${(p.x * W / z).toFixed(1)}px,${(p.y * H / z).toFixed(1)}px)`;
      });
    },

    /* ═════════════ cursor ring, hints, pressure gauge ═════════════ */
    cursorProgress(p, text, red) { this.curP = { p, text, red, t: performance.now() }; },
    cursorHint(text, tone) { this.curH = { text, tone, t: performance.now() }; },
    updateCursor() {
      const now = performance.now(), g = this.g;
      const cp = this.curP && now - this.curP.t < 160 ? this.curP : null;
      const ch = this.curH && now - this.curH.t < 160 ? this.curH : null;
      const gauge = g && g.step === 5 && g.scene === 'B' && g.hv && !g.hv.done;
      const on = !!(cp || ch || gauge);
      this.cur.classList.toggle('on', on);
      if (!on) return;
      this.cur.style.transform = `translate(${this.mx}px,${this.my}px)`;
      const p = cp ? clamp(cp.p, 0, 1) : 0;
      this.curFg.setAttribute('stroke-dasharray', `${(p * 119.4).toFixed(1)} 120`);
      this.cur.classList.toggle('red', !!(cp && cp.red && p > 0.85));
      this.cur.querySelector('svg').style.display = cp ? '' : 'none';
      const tx = (ch && ch.text) || (cp && cp.text) || '';
      if (this.curTx.textContent !== tx) this.curTx.textContent = tx;
      this.curTx.className = `tx ${(ch && ch.tone) || ''}`;
      this.curPg.style.display = gauge ? '' : 'none';
      if (gauge) {
        const hv = g.hv, [a, b] = this.cfg.pressureBand;
        this.curPg.querySelector('.band').style.cssText = `bottom:${a * 100}%;height:${(b - a) * 100}%`;
        this.curPg.querySelector('.lvl').style.bottom = `${hv.p * 100}%`;
        this.curPg.querySelector('b').textContent = `${pct(hv.p)}`;
        this.curPg.classList.toggle('bad', hv.p < a || hv.p > b);
        this.curPg.classList.toggle('live', !!hv.cutting);
      }
    },

    /* ═════════════ sound (only after real input: no autoplay warnings in previews) ═════════════ */
    snd(name, ...args) {
      if (!this.heard || !NZA.audio || typeof NZA.audio[name] !== 'function') return;
      try { NZA.audio[name](...args); } catch (e) { /* audio unavailable */ }
    },

    /* ═════════════ results ═════════════ */
    careResultCalc(cont) {
      const g = this.g, cfg = this.cfg, plan = this.plan, c = g.cool, st = this.lastStats || (this.heat && this.heat.stats(cfg.target)) || { mean: 30, frac: 1 };
      const W = cfg.weights;
      let cool = 0;
      if (!g.skipped[1]) {
        cool = (c.done ? 100 : st.frac * 70) - Math.max(0, c.soot - cfg.sootDone) * 0.9 - c.overcool * 5 - (c.partial ? 8 : 0);
        if (g.done[1] && this.inj.treat.cooled && !c.used) cool = 80;
      }
      const truth = plan.Aburn ? plan.zones.reduce((a, Z) => a + Z.area, 0) / plan.Aburn * 100 : 0;
      let assess = 0;
      if (!g.skipped[2]) {
        const est = g.as.est || 0;
        assess = Math.min(1, g.as.cover / cfg.assessCover) * 60 + Math.max(0, 100 - Math.abs(est - truth) * 2) * 0.4;
        if (plan.zones.length && !plan.zones.some(Z => Z.found)) assess -= 15;
        if (this.inj.burn.assessed && !g.as.tests) assess = 80;
      }
      const tot = g.db.total;
      let debride = tot ? g.db.removed / tot * 100 - g.db.fumbles * 3 : 100;
      if (g.skipped[3]) debride = tot ? g.db.removed / tot * 60 : 100;
      const D = g.dr.D;
      const dressing = cont || !D ? 0 : clamp(g.dr.cover * 70 + D.stuck * 30 + (g.dr.secured ? 5 : 0), 0, 100);
      const parts = { cool: Math.round(clamp(cool, 0, 100)), assess: Math.round(clamp(assess, 0, 100)), debride: Math.round(clamp(debride, 0, 100)), dressing: Math.round(dressing) };
      const wd = cont ? 0 : W.dressing;
      const score = (parts.cool * W.cool + parts.assess * W.assess + parts.debride * W.debride + parts.dressing * wd) / Math.max(1, W.cool + W.assess + W.debride + wd);
      const mean = c.final !== undefined ? c.final : st.mean;
      return {
        phase: 'care', score: Math.round(clamp(score, 0, 100)), parts,
        cooled: !g.skipped[1] && (c.done || st.frac >= cfg.coolFrac), surfaceTemp: +f1(mean), sootLeft: Math.round(c.soot), overcool: +f1(c.overcool), salineMl: Math.round(c.used),
        tested: g.as.tests > 0 || !!this.inj.burn.assessed, testCover: +g.as.cover.toFixed(3), fullEst: Math.round(g.as.est || 0), truth: Math.round(truth),
        debrided: tot ? +(g.db.removed / tot).toFixed(3) : 1, debrideTotal: tot, fumbles: g.db.fumbles,
        dressed: !cont && !!(D && D.stuck >= cfg.stuckDone * 0.95), stuck: D ? +D.stuck.toFixed(3) : 0, cover: +(g.dr.cover || 0).toFixed(3), secured: !!g.dr.secured,
        continue: !!cont, seconds: Math.round(g.t), skipped: Object.keys(g.skipped).map(Number),
      };
    },
    graftResultCalc() {
      const g = this.g, cfg = this.cfg, plan = this.plan, Wt = cfg.graftWeights;
      const exF = this.excisedFrac();
      const dev = g.ex.devN ? g.ex.devSum / g.ex.devN * 1000 : 1.5;
      const excise = plan.zones.every(Z => Z.preExcised) ? 80 : exF * (100 - Math.max(0, dev - 0.8) * 12) - g.ex.strays * 3;
      const hv = g.hv || { cut: 0, L3: 1 };
      const harvest = this.harvestQ() * 100 * Math.min(1, hv.cut / Math.max(1, hv.L3));
      const ms = g.ms || { tears: [], ratio: '1:1.5', cov15: 1 };
      const mesh = 100 - ms.tears.length * 14 - (ms.ratio === '1:3' && ms.cov15 >= 1.05 ? 12 : 0);
      const gr = g.gr || { coverage: 0, misses: 0 };
      const graft = gr.coverage * 60 + this.stapledFrac() * 40 - gr.misses * 2;
      const D = g.dr.D;
      const dressing = D ? g.dr.cover * 70 + D.stuck * 30 : 0;
      const parts = { excise: Math.round(clamp(excise, 0, 100)), harvest: Math.round(clamp(harvest, 0, 100)), mesh: Math.round(clamp(mesh, 0, 100)), graft: Math.round(clamp(graft, 0, 100)), dressing: Math.round(clamp(dressing, 0, 100)) };
      const sum = Wt.excise + Wt.harvest + Wt.mesh + Wt.graft + Wt.dressing;
      const score = (parts.excise * Wt.excise + parts.harvest * Wt.harvest + parts.mesh * Wt.mesh + parts.graft * Wt.graft + parts.dressing * Wt.dressing) / Math.max(1, sum);
      return {
        phase: 'graft', score: Math.round(clamp(score, 0, 100)), parts,
        excised: +exF.toFixed(3), excisedCm2: +(plan.zones.filter(Z => Z.excised).reduce((a, Z) => a + Z.cutArea, 0) * 1e4).toFixed(1),
        donorCm2: +(hv.cut * cfg.graftWidth / 100).toFixed(1), graftMm: Math.round(hv.cut), coverage: +(gr.coverage || 0).toFixed(3), staples: +this.stapledFrac().toFixed(3),
        stapleCount: gr.staples ? gr.staples.length : 0, misses: gr.misses || 0, ratio: ms.ratio, tears: ms.tears.length, offLineMm: +dev.toFixed(2),
        dressed: !!(D && D.stuck >= cfg.stuckDone * 0.95), stuck: D ? +D.stuck.toFixed(3) : 0, cover: +(g.dr.cover || 0).toFixed(3),
        seconds: Math.round(g.t),
      };
    },
    finish() {
      const g = this.g;
      if (this.finished || !g) return;
      this.finished = true;
      this.stopAll();
      if (this.S) { this.S.tools.use(null); this.S.fluids.jet(false); this.S.markers.clear(); }
      this.stage.classList.remove('grab', 'grabbing');
      this.clearTags();
      const res = this.mode === 'graft' ? this.graftResultCalc() : this.careResultCalc(false);
      this.result = res;
      setTimeout(() => {
        if (!this.alive || this.g !== g) return;
        this.showResult(res, null);
        NZA.post('burn:finish', res).then(r => {
          if (!this.alive || this.g !== g) return;
          if (r && r.outcome) this.showOutcome(r.outcome);
          else if (r && r.ok === false) this.showOutcome({ error: r.msg || T('err_save', 'The result could not be saved.') });
        });
      }, 700);
    },
    feedback(res, out) {
      const fb = [], cfg = this.cfg;
      if (res.phase === 'care') {
        if (res.skipped.includes(1)) fb.push(['bad', T('fb_nocool', 'The burn was never cooled — it keeps burning deeper.')]);
        else if (res.cooled) fb.push(['ok', T('fb_cooled', 'Cooled to %s °C with %s mL of saline.', f1(res.surfaceTemp), res.salineMl)]);
        else fb.push(['warn', T('fb_warm', 'The surface was still %s °C.', f1(res.surfaceTemp))]);
        if (res.sootLeft > cfg.sootDone) fb.push(['warn', T('fb_soot', '%s% soot left in the burn — infection risk.', res.sootLeft)]);
        if (res.overcool > 0.5) fb.push(['bad', T('fb_over', 'Over-cooled for %s s — the patient is chilled.', Math.round(res.overcool))]);
        if (res.tested) fb.push([Math.abs(res.fullEst - res.truth) <= 12 ? 'ok' : 'warn', T('fb_depth', 'Depth estimate %s% full thickness (actual %s%).', res.fullEst, res.truth)]);
        if (res.debrideTotal) fb.push([res.debrided >= cfg.debridedMin ? 'ok' : 'warn', T('fb_debride', '%s% of the blisters and dead skin removed.', pct(res.debrided))]);
        if (res.continue) fb.push(['ok', T('fb_continue', 'Handed straight on to the skin graft.')]);
        else if (res.dressed) fb.push(['ok', T('fb_dressed', 'Dressed — %s% of the burn covered.', pct(res.cover))]);
        else fb.push(['bad', T('fb_nodress', 'The burn was left undressed.')]);
      } else {
        fb.push([res.excised >= cfg.minExcised ? 'ok' : 'bad', T('fb_excised', '%s% of the eschar excised, %s mm off the line on average.', pct(res.excised), f1(res.offLineMm))]);
        fb.push(['ok', T('fb_harvest', 'Graft %s × %s mm from the thigh.', res.graftMm, cfg.graftWidth)]);
        if (res.tears) fb.push(['warn', T('fb_tears', 'The graft tore %s time(s) in the mesher.', res.tears)]);
        fb.push([res.coverage >= cfg.minCoverage ? 'ok' : 'bad', T('fb_cover', 'Bed %s% covered at %s, %s staples.', pct(res.coverage), res.ratio, res.stapleCount)]);
        if (out && out.blood) fb.push(['warn', T('fb_blood', 'Blood lost: %s mL.', out.blood)]);
        fb.push([res.dressed ? 'ok' : 'bad', res.dressed ? T('fb_dressed', 'Dressed — %s% of the burn covered.', pct(res.cover)) : T('fb_nodress', 'The burn was left undressed.')]);
      }
      return fb;
    },
    showResult(res, outcome) {
      this.resultShown = true;
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      this.cur.classList.remove('on');
      const score = outcome && outcome.score !== undefined ? outcome.score : res.score;
      const grade = (outcome && outcome.grade) || (score >= 90 ? 'S' : score >= 80 ? 'A' : score >= 65 ? 'B' : score >= 50 ? 'C' : score >= 35 ? 'D' : 'F');
      const inj = this.inj, waiting = !outcome, err = outcome && outcome.error;
      this.canClose = !waiting;
      const R = 34, C = 2 * Math.PI * R;
      const rows = res.phase === 'care' ? [
        [T('r_cool', 'Cooling'), res.skipped.includes(1) ? T('skipped', 'Skipped') : `${f1(res.surfaceTemp)} °C`, T('r_cool_sub', 'soot %s%', res.sootLeft), res.parts.cool],
        [T('r_assess', 'Depth test'), res.tested ? `${res.fullEst}%` : T('skipped', 'Skipped'), T('r_assess_sub', 'full thickness'), res.parts.assess],
        [T('r_debride', 'Debridement'), res.debrideTotal ? `${pct(res.debrided)}%` : T('none', 'None needed'), '', res.parts.debride],
        [T('r_dressing', 'Dressing'), res.continue ? T('r_to_graft', 'At the graft') : `${pct(res.cover)}%`, res.continue ? '' : T('r_dressing_sub', 'covered'), res.continue ? null : res.parts.dressing],
      ] : [
        [T('r_excise', 'Excision'), `${pct(res.excised)}%`, T('r_excise_sub', '%s cm²', Math.round(res.excisedCm2)), res.parts.excise],
        [T('r_harvest', 'Harvest'), `${res.graftMm} mm`, T('r_harvest_sub', 'donor %s cm²', Math.round(res.donorCm2)), res.parts.harvest],
        [T('r_mesh', 'Mesh'), res.ratio, T('r_mesh_sub', '%s tear(s)', res.tears), res.parts.mesh],
        [T('r_graft', 'Graft'), `${pct(res.coverage)}%`, T('r_graft_sub', '%s staples', res.stapleCount), res.parts.graft],
        [T('r_dressing', 'Dressing'), `${pct(res.cover)}%`, T('r_dressing_sub', 'covered'), res.parts.dressing],
      ];
      const tone = v => (v >= 75 ? '' : v >= 45 ? 'amber' : 'red');
      const fb = this.feedback(res, outcome);
      const care = res.phase === 'graft' && this.careOutcome;
      const flags = res.phase === 'care'
        ? [[T('f_cooled', 'Cooled'), outcome ? outcome.cooled : res.cooled], [T('f_debrided', 'Debrided'), outcome ? outcome.debrided : res.debrided >= this.cfg.debridedMin], [T('f_dressed', 'Dressed'), outcome ? outcome.dressed : res.dressed]]
        : [[T('f_excised', 'Excised'), outcome ? outcome.excised : res.excised >= this.cfg.minExcised], [T('f_grafted', 'Grafted'), outcome ? outcome.grafted : res.coverage >= this.cfg.minCoverage], [T('f_dressed', 'Dressed'), outcome ? outcome.dressed : res.dressed]];
      const title = res.phase === 'care' ? (res.continue ? T('r_title_cont', 'Burn care done') : T('r_title_care', 'Burn cared for')) : T('r_title_graft', 'Skin graft in place');
      this.resWrap.innerHTML = `
        <div class="bn-res nza-hud solid ${score < 50 ? 'low' : ''}">
          <div class="rh">
            <span class="rg"><svg viewBox="0 0 80 80"><circle class="bg" cx="40" cy="40" r="${R}"/><circle class="fg g-${esc(grade)}" cx="40" cy="40" r="${R}" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - score / 100)).toFixed(1)}"/></svg><b>${esc(grade)}</b></span>
            <div class="rt"><span class="tg">${esc(res.phase === 'care' ? T('tag_care', 'Burn care') : T('tag_graft', 'Skin graft'))}</span><h3>${esc(title)}</h3>
              <p>${esc(inj.regionLabel || '')} · ${esc(T('r_meta', '%s cm² · %s', Math.round(this.plan ? this.plan.A : +inj.burn.area || 0), NZA.fmt.time(res.seconds)))}</p></div>
            <div class="sc"><b>${esc(score)}</b><span>${esc(T('r_score', 'Score'))}</span></div>
          </div>
          ${care ? `<div class="rc"><span>${esc(T('r_care_before', 'Burn care'))}</span><b class="g-${esc(care.grade || 'C')}">${esc(care.grade || '')}</b><em>${esc(String(care.score !== undefined ? care.score : ''))}</em></div>` : ''}
          <div class="rl">${rows.map(r => `<div class="ri"><span class="k">${esc(r[0])}</span><span class="d">${esc(r[1])}${r[2] ? `<i>${esc(r[2])}</i>` : ''}</span>${r[3] === null ? '<span class="m"></span><span class="n">—</span>' : `<span class="m">${NZA.ui.meterHTML({ value: r[3] / 100, tone: tone(r[3]) })}</span><span class="n">${esc(r[3])}</span>`}</div>`).join('')}</div>
          <div class="rf">${flags.map(f => `<span class="bn-chip ${f[1] ? 'teal' : 'red'}">${icon(f[1] ? 'check' : 'x')}${esc(f[0])}</span>`).join('')}</div>
          <ul class="fb">${fb.map(f => `<li class="${f[0]}">${esc(f[1])}</li>`).join('')}</ul>
          ${outcome && outcome.msg && !err ? `<div class="msg">${esc(outcome.msg)}</div>` : ''}
          ${err ? `<div class="msg err">${esc(err)}</div>` : ''}
          <div class="act">${waiting ? `<span class="wait"><span class="ring"></span>${esc(T('r_saving', 'Saving the treatment…'))}</span>` : ''}
            <button class="pp-done" ${waiting ? 'disabled style="opacity:.45;pointer-events:none"' : ''}>${esc(T('done', 'Done'))}<kbd>Enter</kbd></button></div>
        </div>`;
      const btn = this.resWrap.querySelector('.pp-done');
      if (btn) btn.onclick = () => { if (this.canClose) this.closeNow(); };
    },
    showOutcome(o) {
      o = o || {};
      if (!this.result && this.careResult) {
        // "graft now" was refused when the care was saved (no theatre / kit any more): burn care ends here
        if (this.g) this.g.waitGraft = false;
        this.finished = true;
        this.careOutcome = o;
        this.result = Object.assign({}, this.careResult, { continue: false });
      }
      if (!this.result) return;
      this.showResult(this.result, o || {});
      if (!o.error) this.snd('success');
    },
    abort() {
      if (this.finished) { if (this.canClose) this.closeNow(); return; }
      NZA.post('burn:abort', {});
      NZA.close('burn');
    },
    closeNow() { NZA.close('burn'); },

    /* ═════════════ no WebGL: short manual fallback ═════════════ */
    fallback() {
      this.hideVeil(0);
      const inj = this.inj || DEMO.injury;
      this.g = null;
      this.devEl.style.display = 'none'; this.caseEl.style.display = 'none';
      const graft = this.mode === 'graft';
      this.pp = NZA.ui.ProcPanel(this.ui, {
        step: 1, total: 1, tag: graft ? T('tag_graft', 'Skin graft') : T('tag_care', 'Burn care'), title: graft ? T('fb_title_graft', 'Grafting the burn') : T('fb_title', 'Caring for the burn'),
        text: T('fb_text', '3D view unavailable on this client — the burn is treated with a standard technique.'),
        stats: [{ label: T('st_site', 'Site'), value: inj.regionLabel || inj.region || '', small: true }, { label: T('st_area', 'Burn area'), value: String(Math.round(+inj.burn.area || 0)), unit: 'cm²' }],
        wide: { label: T('w_progress', 'Progress'), value: '0', unit: '%', meter: { value: 0 } },
        tools: [], abort: { label: T('hold_cancel', 'Hold to cancel'), key: 'ESC', seconds: 1.2 }, onAbort: () => this.abort(),
      });
      const dur = Math.max(8, +(this.cfg && this.cfg.fallbackTime) || 14);
      let t = 0;
      this.fallbackTimer = setInterval(() => {
        t += 0.25;
        if (this.pp) this.pp.wide({ value: String(Math.round(Math.min(1, t / dur) * 100)), meter: { value: Math.min(1, t / dur) } });
        if (t < dur) return;
        clearInterval(this.fallbackTimer); this.fallbackTimer = null;
        const b = inj.burn || {};
        const res = graft
          ? { phase: 'graft', score: 60, parts: { excise: 60, harvest: 60, mesh: 60, graft: 60, dressing: 60 }, excised: 1, excisedCm2: (+b.area || 40) * (+b.full || 0) / 100, donorCm2: (+b.area || 40) * (+b.full || 0) / 150, graftMm: 60, coverage: 0.85, staples: 1, stapleCount: 12, misses: 0, ratio: '1:1.5', tears: 0, offLineMm: 1, dressed: true, stuck: 1, cover: 1, seconds: Math.round(t), fallback: true }
          : { phase: 'care', score: 60, parts: { cool: 60, assess: 60, debride: 60, dressing: 60 }, cooled: true, surfaceTemp: 29, sootLeft: 5, overcool: 0, salineMl: 300, tested: true, testCover: 1, fullEst: +b.full || 0, truth: +b.full || 0, debrided: 1, debrideTotal: 1, fumbles: 0, dressed: true, stuck: 1, cover: 1, secured: false, continue: false, seconds: Math.round(t), skipped: [], fallback: true };
        this.result = res; this.finished = true; this.inj = inj;
        this.showResult(res, null);
        NZA.post('burn:finish', res).then(r => { if (r && r.outcome) this.showOutcome(r.outcome); });
      }, 250);
    },

    /* ═════════════ browser preview ═════════════ */
    preview() {
      const app = this;
      NZA.mock('burn:graftCheck', () => new Promise(res => setTimeout(() => res({ ok: true }), 500)));
      NZA.mock('burn:abort', { ok: true });
      NZA.mock('burn:pain', { ok: true });
      NZA.mock('burn:finish', r => {
        const s = (r && r.score) || 0, grade = s >= 90 ? 'S' : s >= 80 ? 'A' : s >= 65 ? 'B' : s >= 50 ? 'C' : s >= 35 ? 'D' : 'F';
        setTimeout(() => {
          if (r.phase === 'care' && r.continue) {
            app.msg.careDone({ score: s, grade, continue: true, msg: T('demo_cont', 'Burn cooled and debrided — on to the graft.') });
            app.msg.graft(Object.assign({}, DEMO, { mode: 'graft', continued: true }));
          } else {
            const o = { score: s, grade, msg: r.phase === 'graft' ? T('demo_graft', 'Graft stapled at %s and dressed.', r.ratio) : T('demo_care', 'Burn cooled, debrided and dressed.') };
            if (r.phase === 'graft') Object.assign(o, { grafted: r.coverage >= 0.7, excised: r.excised >= 0.7, dressed: r.dressed, blood: Math.round(r.excisedCm2 * 0.9 + r.donorCm2 * 0.3) });
            else Object.assign(o, { cooled: r.cooled, debrided: r.debrided >= 0.75, dressed: r.dressed });
            app.msg.result(o);
          }
        }, 650);
        return { ok: true, pending: true };
      });
      const q = new URLSearchParams(location.search);
      const data = Object.assign({}, DEMO, { locale: {} });
      if (q.get('mode') === 'graft') {
        data.mode = 'graft';
        data.injury = Object.assign({}, DEMO.injury, { treat: { cooled: true, debrided: true, dressed: true, grafted: false }, burn: Object.assign({}, DEMO.injury.burn, { assessed: true, assessedFull: 44, soot: 6 }) });
      }
      if (q.get('deg') === '2') data.injury = Object.assign({}, DEMO.injury, { burn: Object.assign({}, DEMO.injury.burn, { degree: 2, full: 0, area: 64, temp: 47 }) });
      NZA.demo('burn', data);
    },

    /* ═════════════ demo automation (preview / screenshots) ═════════════
       NZA.apps.burn.demoTo('cooling'|'cooled'|'testing'|'tested'|'debriding'|'decision'|'excising'|'excised'|
                            'harvesting'|'harvested'|'meshing'|'placing'|'stapling'|'dressing'|'done') */
    demoTo(stage) {
      const g = this.g;
      if (!g || !this.S) return false;
      const order = ['cooling', 'cooled', 'testing', 'tested', 'debriding', 'decision', 'excising', 'excised', 'harvesting', 'harvested', 'meshing', 'placing', 'stapling', 'dressing', 'done'];
      const want = order.indexOf(stage);
      const S = this.S;
      S.stop();
      const sim = (sec, fn, Sc = S) => { const n = Math.ceil(sec * 30); for (let i = 0; i < n; i++) { if (fn) fn(i / n, i); Sc.step(1 / 30, false); } };
      const aimS = (Sc, s, t) => { const p = Sc.project(Sc.stToUv(s, t)); Sc.pointer.x = p.x; Sc.pointer.y = p.y; this.mx = p.x * window.innerWidth; this.my = p.y * window.innerHeight; };
      const aim = (s, t) => aimS(S, s, t);
      const press = () => this.down({ button: 0 }), release = () => this.up({ button: 0 });
      const plan = this.plan, rx = plan.rx, ry = plan.ry;
      const flush = () => { clearTimeout(this.stepTimer); };
      const go = n => { flush(); if (g.step < n) this.enterStep(n); };
      // 1 · cool
      this.useTool('saline');
      aim(0, 0); sim(0.1); press();
      const coolSec = want === 0 ? 6 : 26;
      sim(coolSec, f => { const a = f * coolSec; aim(Math.sin(a * 1.3) * rx * 0.85, Math.sin(a * 2.1 + 0.5) * ry * 0.8); });
      if (want === 0) { aim(rx * 0.2, -ry * 0.1); sim(0.1); S.start(); return true; }
      release(); sim(2.5);
      if (!g.done[1]) { g.cool.done = true; g.cool.final = this.lastStats.mean; g.done[1] = true; }
      flush();
      if (want === 1) { this.nextAfter(1); S.start(); return true; }
      // 2 · test depth
      go(2);
      const pts = [];
      for (let t = -ry * 0.8; t <= ry * 0.8; t += 0.011) for (let s = -rx * 0.85; s <= rx * 0.85; s += 0.011) if (this.onBurn(s, t, 0.95)) pts.push([s, t]);
      const nT = want === 2 ? Math.ceil(pts.length * 0.4) : pts.length;
      for (let i = 0; i < nT && !g.done[2]; i++) { aim(pts[i][0], pts[i][1]); sim(0.03); press(); sim(0.7); if (!(want === 2 && i === nT - 1)) { release(); sim(0.05); } }
      if (want === 2) { S.start(); return true; }
      if (!g.done[2]) { g.done[2] = true; }
      flush();
      if (want === 3) { this.nextAfter(2); S.start(); return true; }
      // 3 · debride
      if (g.db.total) {
        go(3);
        const items = [...plan.blisters, ...plan.flaps];
        const nD = want === 4 ? Math.ceil(items.length * 0.5) : items.length;
        for (let i = 0; i < nD; i++) {
          const it = items[i]; if (it.removed) continue;
          aim(it.s, it.t); sim(0.05); press();
          const last = want === 4 && i === nD - 1;
          sim(last ? 0.25 : 0.5, f => aim(it.s + f * 0.009 * (last ? 0.5 : 1), it.t - f * 0.004));
          if (!last) { release(); sim(0.05); }
        }
        if (want === 4) { S.start(); return true; }
      }
      flush();
      if (this.mode === 'care') { this.nextAfter(3); }
      if (want === 5) { S.start(); return true; }
      if (g.deciding) { g.graftOk = true; this.decide('graft'); }
      // the preview mock answers with careDone + graft after a moment; do it now
      if (this.mode !== 'graft') { this.onCareDone({ score: 82, grade: 'A' }); this.onGraft(Object.assign({}, DEMO, { mode: 'graft' })); }
      // 4 · excise
      flush(); go(4);
      plan.zones.forEach((Z, zi) => {
        const P = Z.cutPoly, L = Z.cum[P.length];
        const part = want === 6 && zi === plan.zones.length - 1 ? 0.6 : 1.02;
        aim(P[0][0], P[0][1]); sim(0.05); press();
        sim(2.2 * part, f => { const p = this.polyAt(Z, (f * part * L) % L); aim(p[0] + (Math.random() - 0.5) * 0.0008, p[1]); });
        if (!(want === 6 && zi === plan.zones.length - 1)) { release(); sim(0.1); }
      });
      if (want === 6) { S.start(); return true; }
      sim(1.2);
      if (want === 7) { flush(); S.start(); return true; }
      // 5 · harvest (async scene build) → continue in a callback
      flush(); go(5);
      return new Promise(resolve => {
        const wait = () => {
          if (g.scene !== 'B' || !this.SB) { setTimeout(wait, 60); return; }
          const SB = this.SB, hv = g.hv;
          SB.stop();
          const simB = (sec, fn) => sim(sec, fn, SB);
          simB(0.1);   // let the camera settle on the harvest framing before aiming
          aimS(SB, hv.sStart + 0.001, 0); simB(0.1); press();
          const target = want === 8 ? hv.Lneed * 0.55 : hv.Lneed + 2;
          const dur = target / 20;
          simB(dur, f => { hv.p = 0.55 + Math.sin(f * 7) * 0.04; aimS(SB, hv.sStart + 0.001 + f * target * MM, Math.sin(f * 5) * 0.0015); });
          if (want === 8) { SB.start(); resolve(true); return; }
          release(); simB(0.2);
          flush();
          if (want === 9) { SB.start(); resolve(true); return; }
          if (!g.done[5]) this.finishHarvest();
          flush(); go(6);
          const waitB = () => {
            if (g.scene !== 'bench' || !this.bench) { setTimeout(waitB, 60); return; }
            const ms = g.ms;
            ms.locked = true;
            const steps = want === 10 ? 60 : 400;
            for (let i = 0; i < steps && !ms.done; i++) { ms.cranking = true; ms.angle += 0.32; ms.feed = Math.min(ms.need, ms.feed + 0.32 / TAU * this.cfg.feedPerTurn * MM); ms.rate = 1.6; this.tickMesh(1 / 30); }
            ms.cranking = false;
            if (want === 10) { resolve(true); return; }
            flush(); go(7);
            const gr = g.gr;
            S.stop();
            // lay the graft over the beds
            const bx = polyBox([].concat(...plan.zones.map(Z => Z.cutPoly)));
            const cx = (bx[0] + bx[2]) / 2, cy = (bx[1] + bx[3]) / 2;
            aim(gr.c[0], gr.c[1]); sim(0.05); press();
            const c0 = gr.c.slice();
            sim(0.8, f => aim(lerp(c0[0], cx, f), lerp(c0[1], cy, f)));
            gr.angGoal = 0;
            if (want === 11) { sim(0.3); S.start(); resolve(true); return; }
            release(); sim(0.8);
            flush(); if (gr.phase !== 'staple') this.toStapling();
            const nS = want === 12 ? Math.ceil(gr.points.length * 0.55) : gr.points.length;
            for (let i = 0; i < nS; i++) { const p = gr.points[i]; aim(p.s, p.t); sim(0.03); press(); sim(0.03); release(); }
            if (want === 12) { aim(gr.points[nS] ? gr.points[nS].s : 0, gr.points[nS] ? gr.points[nS].t : 0); sim(0.1); S.start(); resolve(true); return; }
            flush(); go(8);
            sim(0.4);
            const D = g.dr.D;
            if (want === 13) { aim(g.dr.ctr[0], g.dr.ctr[1]); S.start(); resolve(true); return; }
            // grab the near edge of the resting dressing and lay it over the burn
            const e0 = [g.dr.ctr[0], g.dr.ctr[1] - D.size[1] / 2 + 0.0015], e1 = [0, -D.size[1] / 2 + 0.0015];
            aim(e0[0], e0[1]); sim(0.05); press();
            sim(0.9, f => aim(lerp(e0[0], e1[0], f), lerp(e0[1], e1[1], f)));
            release(); sim(1.4);
            aim(0, 0); sim(0.05); press();
            for (let k = 0; k < 14 && !g.done[8]; k++) sim(2, f => aim(Math.sin(f * Math.PI * 6 + k) * D.size[0] * 0.49, Math.sin(f * Math.PI * 2 + k * 1.3) * D.size[1] * 0.49));
            release(); sim(0.3);
            S.start();
            resolve(true);
          };
          waitB();
        };
        wait();
      });
    },
  });
})();
