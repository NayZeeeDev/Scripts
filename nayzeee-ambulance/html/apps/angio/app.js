/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · angio — angiography (find and coil internal bleeding)

   One file, two users:
     1. window.NZAAngio  — the procedural anatomy, contrast physics and the
        fluoroscopy renderer. Loaded by the NUI page AND by the DUI page
        (apps/angio/screen.html) that is drawn onto the in-world monitor.
     2. NZA.app('angio') — the procedure overlay (only when the NUI kit exists).

   Lua → JS actions:  open(data) · close · vitals(v) · room({ on }) · pressed() · anchors
   JS → Lua posts:    angio:step { phase, cam, access } · angio:screen { state } (20 Hz while the
                      DUI is live) · angio:run { kind, selective, blush, fromButton } → { ok, left, err }
                      angio:refill → { ok, left } · angio:coil { dist, onPath } → { ok, left, err }
                      angio:room { on } · angio:view { mode } · angio:say { line }
                      angio:finish { result } · angio:abort
   Body space: centimetres, x+ = patient's LEFT (image right), y+ = caudal, z+ = anterior.
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';

  /* ═══════════════════════════ MATHS ═══════════════════════════ */
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = t => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
  const TAU = Math.PI * 2, DEG = Math.PI / 180;
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const len = a => Math.hypot(a[0], a[1], a[2]);
  const norm = a => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
  const angDiff = (a, b) => { let d = (a - b) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; };
  function rng(seed) {
    let s = (seed >>> 0) || 1;
    return () => { s = (s + 0x6D2B79F5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }

  /* ═══════════════════════════ ANATOMY ═══════════════════════════ */
  const STEP = 0.5;          // cm between vessel nodes
  const MIN_R = 0.085;       // cm — narrowest lumen the catheter enters
  const FOV_W = 30;          // cm across the detector
  const BODY = { x0: -24, x1: 24, y0: -21, y1: 54 };
  const LEVELS = [['T11', -5.6], ['T12', -2.0], ['L1', 1.6], ['L2', 5.2], ['L3', 8.8], ['L4', 12.4], ['L5', 16.0]];
  const VW = { T11: 3.6, T12: 3.8, L1: 4.2, L2: 4.4, L3: 4.7, L4: 5.0, L5: 5.2 };

  // [id, key, parent, points, r0 mm, r1 mm, side]
  const MID = [
    ['aorta_t', 'aorta_t', null, [[1.0, -21, -2.8], [1.1, -15, -2.2], [1.2, -9, -1.6]], 11, 10.2],
    ['aorta', 'aorta', 'aorta_t', [[1.2, -9, -1.6], [1.4, -4, -1.2], [1.5, 0, -1.0], [1.4, 6, -0.6], [1.1, 11, -0.3], [0.8, 13.6, -0.2]], 10.2, 8.2],
    ['coeliac', 'coeliac', 'aorta', [[1.4, -2.8, -1.1], [1.6, -3.4, 0.6], [1.5, -4.0, 2.4]], 3.6, 3.2],
    ['splenic', 'splenic', 'coeliac', [[1.5, -4.0, 2.4], [3.8, -4.8, 2.4], [6.2, -3.6, 1.8], [8.4, -5.2, 1.1], [10.4, -4.0, 0.6], [12.0, -5.0, 0.2]], 3.0, 2.3],
    ['splenic_h1', 'splenic_h', 'splenic', [[12.0, -5.0, 0.2], [13.0, -6.8, 0.0], [13.6, -8.4, -0.2]], 1.6, 1.0],
    ['splenic_h2', 'splenic_h', 'splenic', [[12.0, -5.0, 0.2], [13.6, -5.2, 0.0], [14.8, -5.0, -0.2]], 1.5, 1.0],
    ['splenic_h3', 'splenic_h', 'splenic', [[12.0, -5.0, 0.2], [13.0, -3.2, 0.0], [13.4, -1.6, -0.2]], 1.5, 1.0],
    ['lgastric', 'lgastric', 'coeliac', [[1.5, -4.0, 2.4], [2.4, -6.4, 3.0], [2.0, -8.8, 3.4]], 1.3, 0.8],
    ['chepatic', 'chepatic', 'coeliac', [[1.5, -4.0, 2.4], [-1.2, -3.6, 2.8], [-3.8, -3.9, 2.6]], 2.8, 2.6],
    ['gda', 'gda', 'chepatic', [[-3.8, -3.9, 2.6], [-4.4, -1.4, 3.2], [-4.0, 1.6, 3.6], [-3.0, 3.6, 3.8]], 1.6, 1.0],
    ['phepatic', 'phepatic', 'chepatic', [[-3.8, -3.9, 2.6], [-5.6, -5.2, 2.3], [-6.6, -6.0, 2.0]], 2.3, 2.1],
    ['rhepatic', 'rhepatic', 'phepatic', [[-6.6, -6.0, 2.0], [-8.8, -7.0, 1.4], [-10.6, -8.6, 0.8], [-12.0, -9.4, 0.4]], 1.9, 1.3],
    ['rhep_a', 'rhep_b', 'rhepatic', [[-10.6, -8.6, 0.8], [-12.2, -7.4, 0.4], [-13.6, -6.0, 0.2]], 1.2, 0.9],
    ['rhep_p', 'rhep_b', 'rhepatic', [[-12.0, -9.4, 0.4], [-12.8, -11.0, 0.2], [-13.2, -12.6, 0.0]], 1.2, 0.9],
    ['lhepatic', 'lhepatic', 'phepatic', [[-6.6, -6.0, 2.0], [-5.6, -8.2, 2.4], [-4.2, -10.6, 2.8]], 1.4, 0.9],
    ['sma', 'sma', 'aorta', [[1.5, -1.4, -0.9], [1.4, -0.4, 1.8], [1.0, 2.4, 3.2], [0.4, 6.0, 4.0], [-0.8, 10.0, 4.2], [-2.4, 14.0, 4.0], [-4.4, 17.0, 3.6]], 3.4, 1.8],
    ['mcolic', 'mcolic', 'sma', [[1.0, 2.4, 3.2], [-0.6, 1.0, 4.4], [-2.6, 0.2, 5.0], [-5.4, 0.6, 5.0], [-7.8, 1.4, 4.6]], 1.6, 1.0],
    ['mcolic_l', 'mcolic', 'mcolic', [[-2.6, 0.2, 5.0], [0.4, -0.6, 5.2], [3.6, -0.2, 5.0]], 1.1, 0.8],
    ['rcolic', 'rcolic', 'sma', [[-0.8, 10.0, 4.2], [-3.6, 9.2, 4.4], [-6.8, 8.6, 4.2], [-9.4, 7.4, 3.6]], 1.4, 1.0],
    ['icolic', 'icolic', 'sma', [[-4.4, 17.0, 3.6], [-6.6, 18.0, 3.2], [-8.4, 19.6, 2.8], [-9.0, 21.6, 2.6]], 1.6, 1.1],
    ['j1', 'jejunal', 'sma', [[1.0, 3.0, 3.3], [3.6, 3.4, 4.2], [6.0, 4.4, 4.6], [7.8, 6.2, 4.8], [8.6, 8.2, 4.8]], 1.8, 1.0],
    ['j2', 'jejunal', 'sma', [[0.6, 5.0, 3.8], [3.2, 6.4, 4.4], [5.6, 8.4, 4.8], [6.8, 10.8, 4.9], [7.2, 12.6, 4.9]], 1.7, 1.0],
    ['j3', 'jejunal', 'sma', [[0.2, 7.4, 4.0], [2.6, 9.4, 4.5], [4.4, 12.0, 4.8], [5.0, 14.6, 4.9], [4.8, 16.4, 4.9]], 1.6, 1.0],
    ['i1', 'ileal', 'sma', [[-0.6, 10.6, 4.2], [1.6, 12.8, 4.6], [2.8, 15.6, 4.8], [2.4, 18.4, 4.8]], 1.5, 0.95],
    ['i2', 'ileal', 'sma', [[-2.2, 13.6, 4.0], [-0.6, 16.6, 4.4], [-0.4, 19.4, 4.6], [-1.4, 21.4, 4.6]], 1.4, 0.95],
    ['renal_l', 'renal', 'aorta', [[1.6, 0.8, -1.0], [3.6, 1.2, -1.8], [5.6, 1.6, -2.6], [6.6, 1.8, -3.0]], 2.8, 2.2, 'l'],
    ['renal_s1_l', 'renal_s', 'renal_l', [[6.6, 1.8, -3.0], [7.6, 0.2, -3.3], [8.4, -1.4, -3.4]], 1.5, 1.0, 'l'],
    ['renal_s2_l', 'renal_s', 'renal_l', [[6.6, 1.8, -3.0], [8.2, 1.8, -3.5], [9.2, 2.0, -3.6]], 1.5, 1.0, 'l'],
    ['renal_s3_l', 'renal_s', 'renal_l', [[6.6, 1.8, -3.0], [7.6, 3.6, -3.3], [8.2, 5.2, -3.4]], 1.5, 1.0, 'l'],
    ['renal_r', 'renal', 'aorta', [[1.2, 1.4, -1.0], [-1.6, 1.8, -1.6], [-4.2, 2.4, -2.4], [-6.0, 2.8, -3.0]], 2.8, 2.2, 'r'],
    ['renal_s1_r', 'renal_s', 'renal_r', [[-6.0, 2.8, -3.0], [-7.0, 1.2, -3.3], [-7.8, -0.4, -3.4]], 1.5, 1.0, 'r'],
    ['renal_s2_r', 'renal_s', 'renal_r', [[-6.0, 2.8, -3.0], [-7.6, 2.9, -3.5], [-8.6, 3.0, -3.6]], 1.5, 1.0, 'r'],
    ['renal_s3_r', 'renal_s', 'renal_r', [[-6.0, 2.8, -3.0], [-7.0, 4.6, -3.3], [-7.6, 6.2, -3.4]], 1.5, 1.0, 'r'],
    ['ima', 'ima', 'aorta', [[1.4, 8.6, -0.4], [2.6, 9.4, 0.8], [3.6, 10.6, 1.4], [4.0, 12.6, 1.6]], 1.9, 1.6],
    ['lcolic', 'lcolic', 'ima', [[3.6, 10.6, 1.4], [6.0, 9.2, 1.2], [8.8, 7.0, 0.9], [10.6, 4.0, 0.6], [11.2, 1.0, 0.5]], 1.3, 0.9],
    ['sigmoid1', 'sigmoid', 'ima', [[4.0, 12.6, 1.6], [5.6, 14.6, 1.4], [6.6, 17.0, 1.2], [5.8, 19.2, 1.0]], 1.3, 0.9],
    ['sigmoid2', 'sigmoid', 'sigmoid1', [[5.6, 14.6, 1.4], [8.0, 15.8, 1.0], [9.4, 18.0, 0.8]], 1.1, 0.9],
    ['srectal', 'srectal', 'ima', [[4.0, 12.6, 1.6], [3.2, 15.6, 1.6], [2.2, 19.0, 1.2], [1.0, 22.6, 0.6], [0.4, 25.0, 0.2]], 1.4, 0.9],
  ];
  [2.6, 6.2, 9.8, 12.4].forEach((y, i) => {
    MID.push([`lumbar${i}_l`, 'lumbar', 'aorta', [[1.6, y, -1.4], [3.2, y + 0.4, -3.0], [4.8, y + 1.0, -3.8]], 0.8, 0.6, 'l']);
    MID.push([`lumbar${i}_r`, 'lumbar', 'aorta', [[1.0, y, -1.4], [-1.4, y + 0.4, -3.2], [-3.4, y + 1.0, -4.0]], 0.8, 0.6, 'r']);
  });
  // Left-sided pelvic & leg vessels; mirrored for the right
  const SIDED = [
    ['cia', 'cia', 'aorta', [[0.8, 13.6, -0.2], [2.6, 15.6, -0.6], [4.2, 18.2, -1.2]], 5.0, 4.4],
    ['eia', 'eia', 'cia', [[4.2, 18.2, -1.2], [6.2, 21.0, -0.6], [7.8, 23.8, 0.4], [8.8, 26.4, 1.2]], 4.0, 3.6],
    ['cfa', 'cfa', 'eia', [[8.8, 26.4, 1.2], [9.3, 28.4, 1.6], [9.5, 30.4, 1.6]], 3.6, 3.4],
    ['sfa', 'sfa', 'cfa', [[9.5, 30.4, 1.6], [9.7, 35.0, 1.4], [9.5, 40.0, 1.2], [9.0, 46.0, 0.8], [8.6, 52, 0.5]], 3.0, 2.6],
    ['sfa_m', 'sfa_m', 'sfa', [[9.6, 37.6, 1.3], [11.0, 38.8, 0.8], [12.2, 40.8, 0.4], [12.6, 42.4, 0.2]], 1.2, 0.9],
    ['pfa', 'pfa', 'cfa', [[9.5, 30.4, 1.6], [10.8, 32.4, 1.0], [11.6, 35.6, 0.4], [11.8, 39.6, 0.0], [11.4, 44.0, -0.2]], 2.8, 1.8],
    ['pfa_p1', 'pfa_p', 'pfa', [[11.6, 35.6, 0.4], [13.2, 36.6, -0.2], [14.2, 38.4, -0.4], [14.6, 40.0, -0.5]], 1.1, 0.9],
    ['pfa_p2', 'pfa_p', 'pfa', [[11.8, 39.6, 0.0], [13.4, 41.0, -0.4], [14.0, 43.0, -0.6], [14.2, 44.6, -0.7]], 1.1, 0.9],
    ['lcfx', 'lcfx', 'pfa', [[10.8, 32.4, 1.0], [13.0, 31.6, 0.6], [14.6, 32.6, 0.4], [15.4, 34.6, 0.2]], 1.4, 1.0],
    ['iia', 'iia', 'cia', [[4.2, 18.2, -1.2], [4.6, 20.0, -2.2], [4.8, 21.4, -2.8]], 3.0, 2.8],
    ['iliolumbar', 'iliolumbar', 'iia', [[4.6, 20.0, -2.2], [6.2, 17.8, -2.8], [8.4, 15.8, -2.8], [10.2, 14.8, -2.4]], 1.1, 0.8],
    ['latsacral', 'latsacral', 'iia', [[4.7, 20.6, -2.4], [3.2, 22.0, -3.8], [2.6, 25.0, -4.0]], 0.8, 0.6],
    ['sglut', 'sglut', 'iia', [[4.8, 21.4, -2.8], [6.4, 21.6, -4.2], [8.0, 20.8, -5.4], [9.8, 20.2, -5.8], [11.2, 21.0, -5.6]], 2.2, 1.5],
    ['iia_ant', 'iia_ant', 'iia', [[4.8, 21.4, -2.8], [5.2, 23.4, -2.6], [5.4, 24.6, -2.6]], 2.2, 2.0],
    ['obt', 'obt', 'iia_ant', [[5.4, 24.6, -2.6], [6.8, 26.6, -1.6], [6.4, 29.0, -0.6], [5.6, 30.6, 0.0]], 1.3, 1.0],
    ['iglut', 'iglut', 'iia_ant', [[5.4, 24.6, -2.6], [6.4, 26.8, -4.2], [7.6, 29.0, -4.8], [8.2, 31.0, -4.8]], 1.6, 1.1],
    ['ipud', 'ipud', 'iia_ant', [[5.4, 24.6, -2.6], [4.8, 27.6, -3.2], [3.8, 30.6, -2.2], [2.8, 32.8, -1.0]], 1.3, 1.0],
  ];
  const SIDED_IDS = new Set(SIDED.map(d => d[0]));
  const DEFS = MID.slice();
  ['l', 'r'].forEach(side => SIDED.forEach(d => {
    const parent = SIDED_IDS.has(d[2]) ? `${d[2]}_${side}` : d[2];
    const pts = d[3].map(p => [side === 'r' ? -p[0] : p[0], p[1], p[2]]);
    DEFS.push([`${d[0]}_${side}`, d[1], parent, pts, d[4], d[5], side]);
  }));

  // Where each kind of bleed can sit, and the first-order vessel that feeds it (the "gate")
  const BLEEDS = {
    splenic: { v: ['splenic_h1', 'splenic_h2', 'splenic_h3'], gate: 'coeliac', at: 0.8 },
    hepatic: { v: ['rhep_a', 'rhep_p'], gate: 'coeliac', at: 0.8 },
    renal: { v: ['renal_s1', 'renal_s2', 'renal_s3'], sided: true, gate: 'renal', at: 0.8 },
    jejunal: { v: ['j1', 'j2', 'j3'], gate: 'sma', at: 0.92 },
    ileal: { v: ['i1', 'i2'], gate: 'sma', at: 0.92 },
    sma: { v: ['mcolic', 'rcolic', 'icolic'], gate: 'sma', at: 0.85 },
    ima: { v: ['sigmoid1', 'sigmoid2'], gate: 'ima', at: 0.85 },
    iia: { v: ['obt', 'iglut', 'ipud'], sided: true, gate: 'iia', at: 0.8 },
    gluteal: { v: ['sglut'], sided: true, gate: 'iia', at: 0.82 },
    obturator: { v: ['obt'], sided: true, gate: 'iia', at: 0.8 },
    femoral: { v: ['sfa_m'], sided: true, gate: 'cfa', at: 0.85 },
    profunda: { v: ['pfa_p1', 'pfa_p2'], sided: true, gate: 'cfa', at: 0.85 },
  };
  const AORTIC = new Set(['aorta_t', 'aorta']);

  function catmull(pts, per) {
    const out = [];
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
      for (let k = 0; k < per; k++) {
        const t = k / per, t2 = t * t, t3 = t2 * t;
        out.push([0, 1, 2].map(j => 0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3)));
      }
    }
    out.push(pts[pts.length - 1].slice());
    return out;
  }
  function resample(dense, step) {
    const out = [dense[0]];
    let acc = 0;
    for (let i = 1; i < dense.length; i++) {
      let a = out[out.length - 1];
      const b = dense[i];
      let d = len(sub(b, a));
      acc = d;
      while (acc >= step) {
        const t = step / d;
        a = [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
        out.push(a);
        d = len(sub(b, a)); acc = d;
      }
    }
    const last = dense[dense.length - 1];
    if (len(sub(last, out[out.length - 1])) > step * 0.35) out.push(last.slice()); else out[out.length - 1] = last.slice();
    return out;
  }

  /* build the patient-specific scene. params = { seed, key, side, sev } */
  function buildScene(params) {
    const seed = (params && params.seed) >>> 0 || 1;
    const R = rng(seed);
    const rr = (a, b) => a + R() * (b - a);
    const nodes = { x: [], y: [], z: [], r: [], v: [], p: [], c: [], s: [] };
    const vessels = [], byId = {};
    const add3 = (pos, r, v, p) => {
      const i = nodes.x.length;
      nodes.x.push(pos[0]); nodes.y.push(pos[1]); nodes.z.push(pos[2]); nodes.r.push(r); nodes.v.push(v); nodes.p.push(p); nodes.c.push([]);
      nodes.s.push(p >= 0 ? nodes.s[p] + Math.hypot(pos[0] - nodes.x[p], pos[1] - nodes.y[p], pos[2] - nodes.z[p]) : 0);
      if (p >= 0) nodes.c[p].push(i);
      return i;
    };
    const pos = i => [nodes.x[i], nodes.y[i], nodes.z[i]];

    DEFS.forEach(d => {
      const [id, key, parentId, ptsIn, r0, r1, side] = d;
      const vi = vessels.length;
      const pv = parentId ? byId[parentId] : null;
      const pts = ptsIn.map(p => p.slice());
      // patient variation: nudge interior points (never the aorta)
      if (!AORTIC.has(id)) for (let i = 1; i < pts.length; i++) { pts[i][0] += rr(-0.28, 0.28); pts[i][1] += rr(-0.28, 0.28); }
      let junction = -1;
      if (pv) {
        let best = Infinity;
        pv.own.forEach(n => { const dd = len(sub(pos(n), pts[0])); if (dd < best) { best = dd; junction = n; } });
        if (pv.junction >= 0) { const dd = len(sub(pos(pv.junction), pts[0])); if (dd < best) { best = dd; junction = pv.junction; } }
        pts[0] = pos(junction);
      }
      const dense = resample(catmull(pts, 10), STEP);
      const v = { id, key, side: side || '', idx: vi, parent: pv ? pv.idx : -1, junction, own: [], r0: r0 / 10, r1: r1 / 10, anc: null };
      vessels.push(v); byId[id] = v;
      let prev = junction;
      const n = dense.length - 1 || 1;
      dense.forEach((p, i) => {
        if (i === 0 && junction >= 0) return;
        const r = lerp(v.r0, v.r1, i / n);
        prev = add3(p, r, vi, prev);
        v.own.push(prev);
      });
      v.draw = junction >= 0 ? [junction].concat(v.own) : v.own.slice();
      v.nav = v.r1 >= MIN_R;
    });
    vessels.forEach(v => { v.anc = new Set([v.idx]); let p = v.parent; while (p >= 0) { v.anc.add(p); p = vessels[p].parent; } });

    /* decorative twigs & mesenteric arcades (fill with their feeding node, never navigable) */
    const deco = [];
    const twig = (from, dir, length, r, depth) => {
      const pts = [pos(from)];
      let p = pos(from), d = norm(dir);
      const segs = Math.max(2, Math.round(length / 0.35));
      for (let i = 0; i < segs; i++) {
        d = norm([d[0] + rr(-0.35, 0.35), d[1] + rr(-0.35, 0.35), d[2] * 0.6]);
        p = add(p, mul(d, length / segs));
        pts.push(p);
      }
      deco.push({ pts, r, feed: from, kind: 'twig' });
      if (depth > 0 && R() < 0.75) {
        const mid = pts[Math.floor(pts.length / 2)];
        const di = norm([d[0] + rr(-1, 1), d[1] + rr(-1, 1), 0]);
        deco.push({ pts: [mid, add(mid, mul(di, length * 0.45)), add(mid, mul(norm(add(di, d)), length * 0.8))], r: r * 0.7, feed: from, kind: 'twig' });
      }
    };
    vessels.forEach(v => {
      if (AORTIC.has(v.id) || v.key === 'lumbar' || v.key === 'cia' || v.key === 'eia' || v.key === 'latsacral') return;
      const own = v.own;
      const last = own[own.length - 1];
      if (!nodes.c[last].length) {
        const dir = norm(sub(pos(last), pos(own[Math.max(0, own.length - 3)])));
        const k = 2 + Math.floor(R() * 2);
        for (let i = 0; i < k; i++) {
          const a = (i - (k - 1) / 2) * 0.9 + rr(-0.45, 0.45);
          const ca = Math.cos(a), sa = Math.sin(a);
          twig(last, [dir[0] * ca - dir[1] * sa, dir[0] * sa + dir[1] * ca, dir[2]], rr(1.0, 2.2), Math.max(0.03, v.r1 * 0.45), 1);
        }
      }
      for (let i = 4; i < own.length - 2; i += 5 + Math.floor(R() * 4)) {
        if (R() < 0.55) continue;
        const a = own[i];
        const dir = norm(sub(pos(own[i + 1]), pos(own[i - 1])));
        const s = R() < 0.5 ? 1 : -1;
        twig(a, [dir[0] * 0.5 - dir[1] * s, dir[1] * 0.5 + dir[0] * s, 0], rr(0.6, 1.4), Math.max(0.025, nodes.r[a] * 0.35), 0);
      }
    });
    // arcades between the jejunal & ileal branch ends, plus vasa recta toward the bowel wall
    const arcIds = ['j1', 'j2', 'j3', 'i1', 'i2'].filter(id => byId[id]);
    const smaMid = [0.4, 9, 4];
    for (let i = 0; i < arcIds.length; i++) {
      const v = byId[arcIds[i]];
      const end = v.own[v.own.length - 1];
      const A = pos(end);
      const out = norm([A[0] - smaMid[0], A[1] - smaMid[1], 0]);
      // primary loop
      const loop = [];
      const tang = [-out[1], out[0], 0];
      const c0 = add(A, mul(out, 0.35));
      for (let k = 0; k <= 12; k++) {
        const a = Math.PI * (k / 12);
        loop.push(add(add(c0, mul(tang, Math.cos(a) * 0.95)), mul(out, Math.sin(a) * 0.75)));
      }
      deco.push({ pts: [A, c0], r: 0.05, feed: end, kind: 'arcade' });
      deco.push({ pts: loop, r: 0.045, feed: end, kind: 'arcade' });
      if (i < arcIds.length - 1) {
        const w = byId[arcIds[i + 1]];
        const B = pos(w.own[w.own.length - 1]);
        const mid = add(mul(add(A, B), 0.5), mul(out, 1.3));
        deco.push({ pts: catmull([A, mid, B], 8), r: 0.05, feed: end, kind: 'arcade' });
      }
      // vasa recta
      for (let k = 0; k < 9; k++) {
        const base = loop[2 + k];
        const tip = add(base, mul(norm([out[0] + rr(-0.3, 0.3), out[1] + rr(-0.3, 0.3), 0]), rr(0.7, 1.2)));
        deco.push({ pts: [base, tip], r: 0.022, feed: end, kind: 'recta' });
      }
    }
    deco.forEach(d => {
      let acc = 0; d.d = [0];
      for (let i = 1; i < d.pts.length; i++) { acc += len(sub(d.pts[i], d.pts[i - 1])); d.d.push(acc); }
    });

    /* parenchyma (capillary blush) */
    const organs = [];
    const organ = (x, y, z, rx, ry, rot, feed, a) => { if (byId[feed]) organs.push({ x, y, z, rx, ry, rot, feed: byId[feed].idx, a }); };
    organ(7.6, 2.4, -3.4, 2.8, 5.2, 0.18, 'renal_l', 0.32);
    organ(-7.2, 3.4, -3.4, 2.8, 5.2, -0.18, 'renal_r', 0.32);
    organ(12.6, -5.0, 0, 3.0, 4.6, -0.4, 'splenic', 0.26);
    organ(-9.6, -7.4, 1, 7.0, 5.0, 0.25, 'phepatic', 0.18);
    ['j1', 'j2', 'j3', 'i1', 'i2'].forEach(id => { const v = byId[id]; const p = pos(v.own[v.own.length - 1]); organ(p[0] + 0.8, p[1] + 0.3, p[2], 2.2, 1.3, 0.5, id, 0.16); });
    organ(-8.6, 2.0, 4, 3.2, 1.3, 0.1, 'mcolic', 0.12);
    organ(-9.6, 8.0, 3.5, 1.5, 3.4, 0, 'rcolic', 0.12);
    organ(8.6, 18.2, 1, 2.6, 1.6, 0.6, 'sigmoid1', 0.12);
    ['l', 'r'].forEach(s => {
      const m = s === 'l' ? 1 : -1;
      organ(10.4 * m, 20.6, -5.5, 3.2, 2.2, 0.3 * m, `sglut_${s}`, 0.18);
      organ(7.2 * m, 29.4, -4.6, 2.2, 2.0, 0, `iglut_${s}`, 0.14);
      organ(13.2 * m, 39.6, -0.2, 2.6, 5.4, 0.1 * m, `pfa_${s}`, 0.16);
    });

    /* the bleed */
    const def = BLEEDS[params && params.key] || BLEEDS.jejunal;
    const side = def.sided ? ((params && (params.side === 'l' || params.side === 'r')) ? params.side : (R() < 0.5 ? 'l' : 'r')) : '';
    const pick = def.v[Math.floor(R() * def.v.length)];
    const bv = byId[def.sided ? `${pick}_${side}` : pick] || byId.j2;
    const bn = bv.own[clamp(Math.round(bv.own.length * def.at) - 1, 0, bv.own.length - 1)];
    const sev = clamp(Math.round((params && params.sev) || 2), 1, 4);
    const blobs = [];
    for (let i = 0; i < 14; i++) {
      const a = rr(0, TAU), d = i ? Math.sqrt(R()) * 0.95 : 0;
      blobs.push({ dx: Math.cos(a) * d * 1.1, dy: Math.sin(a) * d * 0.8 + d * 0.35, r: i ? rr(0.22, 0.6) : 0.75, k: i ? rr(0.45, 0.75) : 0.95 });
    }
    const gate = byId[def.sided ? `${def.gate}_${side}` : def.gate] || byId.sma;
    const bleedAnc = new Set();
    for (let n = bn; n >= 0; n = nodes.p[n]) bleedAnc.add(n);
    const bleed = { node: bn, vessel: bv.idx, x: nodes.x[bn], y: nodes.y[bn], z: nodes.z[bn], R: 0.7 + sev * 0.32, sev, key: (params && params.key) || 'jejunal', side, gate: gate.idx, blobs, anc: bleedAnc };

    /* access entries */
    const cfa = s => byId[`cfa_${s}`];
    const entry = s => { const v = cfa(s); return v.own[Math.floor(v.own.length * 0.45)]; };
    const entries = {
      femoral_r: { node: entry('r'), side: 'r' },
      femoral_l: { node: entry('l'), side: 'l' },
      radial: { node: byId.aorta_t.own[0], side: '' },
    };

    /* body variation for the plain film */
    const gas = [];
    for (let i = 0; i < 30; i++) gas.push({ x: rr(-9, 9), y: rr(-1, 18), r: rr(0.35, 1.1), a: rr(0.05, 0.14) });
    const colon = [[-10.4, 18], [-10.8, 9], [-10.2, -1], [-7, 0.6], [-2, 5.6], [3, 4.4], [8, -0.8], [11.2, -3], [11.6, 4], [11.8, 12], [10.6, 18], [7, 21.6], [3, 21]];
    colon.forEach(p => { p[0] += rr(-0.6, 0.6); p[1] += rr(-0.6, 0.6); });

    return { seed, nodes, vessels, byId, deco, organs, bleed, entries, gas, colon, params: { seed, key: bleed.key, side, sev } };
  }

  const nodePos = (sc, i) => [sc.nodes.x[i], sc.nodes.y[i], sc.nodes.z[i]];
  const isChild = (sc, a, b) => sc.nodes.p[b] === a;           // b is downstream of a
  const edgeChild = (sc, a, b) => (isChild(sc, a, b) ? b : a);
  const edgeParent = (sc, a, b) => (isChild(sc, a, b) ? a : b);
  // tree distance from the root at a point on edge a→b at fraction f
  function treeS(sc, a, b, f) {
    const s = sc.nodes.s;
    return isChild(sc, a, b) ? lerp(s[a], s[b], f) : lerp(s[a], s[b], f);
  }
  function inSubtree(sc, root, n) { for (let i = n; i >= 0; i = sc.nodes.p[i]) if (i === root) return true; return false; }

  /* ═══════════════════════════ CONTRAST ═══════════════════════════ */
  const INJ = { run: 2.4, puff: 0.8 };
  const RUN_LEN = { run: 7.2, puff: 3.2 };
  const flowSpeed = r => 12 + 30 * clamp(r / 1.0, 0, 1);    // cm/s

  /* arrival time (s) of contrast at every node for an injection at the tip (edge a→b, f).
     coils = [{ a, b, f, pct, rel }]  → { arr, bleedT, bleedI, down } */
  function computeArrival(sc, inj, coils, kind, coilDist) {
    const N = sc.nodes.x.length;
    const arr = new Float32Array(N).fill(Infinity);
    const nd = sc.nodes;
    const a = inj.a, b = inj.b, f = inj.f;
    const down = edgeChild(sc, a, b);
    const up = edgeParent(sc, a, b);
    const segL = len(sub(nodePos(sc, a), nodePos(sc, b)));
    const tipToDown = isChild(sc, a, b) ? (1 - f) * segL : f * segL;
    // coils occluding: their downstream node; a coil on the injection edge distal to the tip blocks `down`
    const blocked = new Set();
    const coilInfo = (coils || []).filter(c => c.pct >= 99).map(c => {
      const cd = edgeChild(sc, c.a, c.b);
      const sC = treeS(sc, c.a, c.b, c.f);
      return { cd, sC };
    });
    const sTip = treeS(sc, a, b, f);
    coilInfo.forEach(c => {
      if (c.cd === down && c.sC > sTip - 0.05) blocked.add(down);
      else if (c.cd !== down) blocked.add(c.cd);
    });
    const maxD = kind === 'puff' ? 5.5 : Infinity;
    if (!blocked.has(down)) {
      arr[down] = tipToDown / flowSpeed(nd.r[down]);
      const stack = [down];
      while (stack.length) {
        const n = stack.pop();
        const kids = nd.c[n];
        for (let k = 0; k < kids.length; k++) {
          const c = kids[k];
          if (blocked.has(c)) continue;
          const dist = nd.s[c] - nd.s[down] + tipToDown;
          if (dist > maxD) continue;
          arr[c] = arr[n] + (nd.s[c] - nd.s[n]) / flowSpeed(nd.r[c]);
          stack.push(c);
        }
      }
    }
    if (kind === 'puff') {
      // a puff also refluxes a little: show the vessel just behind the tip
      let n = up, back = 0, t = 0.12;
      while (n >= 0 && back < 1.6) { if (!isFinite(arr[n])) arr[n] = t; const p = nd.p[n]; if (p < 0) break; back += nd.s[n] - nd.s[p]; t += 0.05; n = p; }
    }
    // the bleed
    const bl = sc.bleed;
    let bleedT = Infinity, bleedI = 0;
    if (isFinite(arr[bl.node])) { bleedT = arr[bl.node] + 0.15; bleedI = 1; }
    else if (inSubtree(sc, down, bl.node) || bl.anc.has(down)) {
      // fed from here but blocked by a coil: a coil too far from the bleed lets collaterals refill it
      let refill = true;
      coilInfo.forEach(c => {
        if (!bl.anc.has(c.cd) && c.cd !== bl.node && !inSubtree(sc, bl.node, c.cd)) return;
        const d = Math.abs(nd.s[bl.node] - c.sC);
        if (d <= (coilDist || 2) + 0.05) refill = false;
      });
      const reachesGate = inSubtree(sc, down, bl.node);
      if (refill && reachesGate && kind !== 'puff') {
        bleedT = (nd.s[bl.node] - nd.s[down] + tipToDown) / 18 + 1.4;
        bleedI = 0.55;
      }
    }
    return { arr, bleedT, bleedI, down };
  }

  const opacity = (t, a, inj) => {
    if (!(t >= a)) return 0;
    const rise = Math.min(1, (t - a) / 0.22);
    const ws = inj + a * 0.55 + 0.45;
    return rise * (t > ws ? Math.max(0, 1 - (t - ws) / 1.9) : 1);
  };

  /* ═══════════════════════════ RENDERER ═══════════════════════════ */
  function makeNoise(size) {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    const img = g.createImageData(size, size);
    for (let i = 0; i < size * size; i++) {
      const v = 128 + (Math.random() + Math.random() + Math.random() - 1.5) * 90;
      img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = clamp(v, 0, 255);
      img.data[i * 4 + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    return c;
  }

  const SA = 15;   // px per cm of the cached plain-film layer

  // The plain film (bones, soft tissue, bowel gas) for one C-arm angle
  function drawAnatomy(sc, carm) {
    const c = document.createElement('canvas');
    const W = Math.round((BODY.x1 - BODY.x0) * SA), H = Math.round((BODY.y1 - BODY.y0) * SA);
    c.width = W; c.height = H;
    const g = c.getContext('2d');
    const ca = Math.cos(carm * DEG), sa = Math.sin(carm * DEG);
    const X = (x, z) => ((x * ca + z * sa) - BODY.x0) * SA;
    const Y = y => (y - BODY.y0) * SA;
    const S = v => v * SA;
    const dark = a => `rgba(18,20,23,${a})`;
    const lite = a => `rgba(236,238,240,${a})`;
    const ellipse = (x, y, z, rx, ry, rot, fill, stroke, lw) => {
      g.beginPath(); g.ellipse(X(x, z), Y(y), Math.max(0.5, S(rx) * ca), S(ry), rot || 0, 0, TAU);
      if (fill) { g.fillStyle = fill; g.fill(); }
      if (stroke) { g.strokeStyle = stroke; g.lineWidth = S(lw || 0.2); g.stroke(); }
    };
    const path = (pts, z, close) => { g.beginPath(); pts.forEach((p, i) => (i ? g.lineTo(X(p[0], z), Y(p[1])) : g.moveTo(X(p[0], z), Y(p[1])))); if (close) g.closePath(); };
    const smoothPath = (pts, z, close) => {
      const d = catmull(close ? pts.concat([pts[0]]) : pts, 8).map(p => [p[0], p[1]]);
      path(d, z, close);
    };

    // soft tissue: thicker in the middle (darker), air outside the flanks (bright)
    g.fillStyle = '#9da1a5'; g.fillRect(0, 0, W, H);
    const body = g.createRadialGradient(X(0, 0), Y(10), S(4), X(0, 0), Y(10), S(30));
    body.addColorStop(0, 'rgba(70,74,78,.30)'); body.addColorStop(0.6, 'rgba(70,74,78,.14)'); body.addColorStop(1, 'rgba(70,74,78,0)');
    g.fillStyle = body; g.fillRect(0, 0, W, H);
    // flanks / skin line, hips and thighs
    g.fillStyle = lite(0.55);
    const flank = s => {
      const m = s;
      g.beginPath();
      g.moveTo(X(24 * m, 0), Y(-22));
      [[17.6, -21], [17.0, -8], [16.4, 4], [17.8, 14], [18.6, 24], [18.2, 32], [17.2, 42], [16.6, 54]].forEach(p => g.lineTo(X(p[0] * m, 0), Y(p[1])));
      g.lineTo(X(24 * m, 0), Y(56)); g.closePath(); g.fill();
    };
    g.filter = 'blur(6px)'; flank(1); flank(-1);
    // gap between the thighs
    g.beginPath(); g.moveTo(X(-3.4, 0), Y(56)); g.quadraticCurveTo(X(0, 0), Y(33), X(3.4, 0), Y(56)); g.closePath(); g.fill();
    g.filter = 'none';

    // organs (water density, slightly darker than fat)
    g.filter = 'blur(10px)';
    ellipse(-9.4, -7.6, 1, 8.2, 6.2, 0.22, dark(0.10));
    ellipse(12.4, -5.4, 0, 3.4, 5.0, -0.4, dark(0.07));
    ellipse(7.6, 2.4, -3.4, 3.0, 5.6, 0.18, dark(0.09));
    ellipse(-7.2, 3.4, -3.4, 3.0, 5.6, -0.18, dark(0.09));
    // psoas shadows
    [1, -1].forEach(m => {
      g.beginPath(); g.moveTo(X(2.4 * m, -4), Y(0)); g.lineTo(X(4.2 * m, -4), Y(0)); g.lineTo(X(7.6 * m, -3), Y(18)); g.lineTo(X(5.2 * m, -3), Y(20)); g.closePath();
      g.fillStyle = dark(0.07); g.fill();
    });
    g.filter = 'none';
    g.filter = 'blur(2px)';
    [1, -1].forEach(m => {
      g.beginPath(); g.moveTo(X(4.4 * m, -4), Y(0.2)); g.lineTo(X(8.0 * m, -3), Y(18.4));
      g.strokeStyle = dark(0.10); g.lineWidth = S(0.18); g.stroke();
    });
    g.filter = 'none';

    // bowel gas: colon frame with haustra, small bowel bubbles
    g.filter = 'blur(3px)';
    const col = sc.colon;
    for (let i = 0; i < col.length - 1; i++) {
      const a = col[i], b = col[i + 1];
      const segs = 4;
      for (let k = 0; k < segs; k++) {
        const t = (k + 0.5) / segs;
        const x = lerp(a[0], b[0], t), y = lerp(a[1], b[1], t);
        const ang = Math.atan2(b[1] - a[1], b[0] - a[0]);
        g.beginPath(); g.ellipse(X(x, 3), Y(y), S(0.85) * ca, S(1.15), ang + Math.PI / 2, 0, TAU);
        g.fillStyle = lite(0.07 + ((i * 7 + k * 3) % 5) * 0.022); g.fill();
      }
    }
    sc.gas.forEach(b => { ellipse(b.x, b.y, 4, b.r, b.r * 0.8, 0, lite(b.a)); });
    g.filter = 'none';

    // ribs (T10-T12)
    g.filter = 'blur(1.4px)';
    [[-11.0, 1.0], [-7.6, 0.9], [-4.2, 0.85]].forEach(([y, w]) => {
      [1, -1].forEach(m => {
        const pts = [[2.2 * m, y], [6 * m, y - 0.6], [10 * m, y + 1.2], [13.6 * m, y + 4.4], [15.6 * m, y + 8.6]];
        smoothPath(pts, -2);
        g.strokeStyle = dark(0.11); g.lineWidth = S(w * 1.1); g.lineCap = 'round'; g.stroke();
        g.strokeStyle = dark(0.1); g.lineWidth = S(0.14); g.stroke();
      });
    });
    // 11th / 12th floating ribs
    [[-2.6, 0.7, 9.6], [0.8, 0.6, 7.4]].forEach(([y, w, l]) => {
      [1, -1].forEach(m => {
        smoothPath([[2.4 * m, y], [5.4 * m, y + 1.0], [l * m, y + 3.4]], -3);
        g.strokeStyle = dark(0.15); g.lineWidth = S(w * 1.15); g.lineCap = 'round'; g.stroke();
      });
    });
    g.filter = 'none';

    // spine
    const zS = -4.6;
    g.filter = 'blur(1px)';
    LEVELS.forEach(([lv, y]) => {
      const w = VW[lv];
      const h = 2.65;
      const x0 = -w / 2;
      // body
      g.beginPath();
      const rx = X(x0, zS), ry = Y(y - h / 2), rw = S(w) * ca, rh = S(h);
      const rad = S(0.5);
      g.moveTo(rx + rad, ry); g.lineTo(rx + rw - rad, ry); g.quadraticCurveTo(rx + rw, ry, rx + rw, ry + rad);
      g.lineTo(rx + rw - S(0.15), ry + rh / 2); g.lineTo(rx + rw, ry + rh - rad); g.quadraticCurveTo(rx + rw, ry + rh, rx + rw - rad, ry + rh);
      g.lineTo(rx + rad, ry + rh); g.quadraticCurveTo(rx, ry + rh, rx, ry + rh - rad); g.lineTo(rx + S(0.15), ry + rh / 2); g.lineTo(rx, ry + rad); g.quadraticCurveTo(rx, ry, rx + rad, ry);
      const vb = g.createLinearGradient(rx, 0, rx + rw, 0);
      vb.addColorStop(0, dark(0.24)); vb.addColorStop(0.5, dark(0.15)); vb.addColorStop(1, dark(0.24));
      g.fillStyle = vb; g.fill();
      g.strokeStyle = dark(0.22); g.lineWidth = S(0.16); g.stroke();
      // endplates
      g.strokeStyle = dark(0.22); g.lineWidth = S(0.12);
      g.beginPath(); g.moveTo(rx + S(0.3), ry + S(0.1)); g.lineTo(rx + rw - S(0.3), ry + S(0.1)); g.moveTo(rx + S(0.3), ry + rh - S(0.1)); g.lineTo(rx + rw - S(0.3), ry + rh - S(0.1)); g.stroke();
      // transverse processes
      [1, -1].forEach(m => {
        const tl = lv.startsWith('T') ? 1.0 : (lv === 'L3' ? 2.3 : 1.8);
        g.beginPath();
        g.moveTo(X(m * (w / 2 - 0.2), zS), Y(y - 0.55)); g.quadraticCurveTo(X(m * (w / 2 + tl * 0.6), zS), Y(y - 0.5), X(m * (w / 2 + tl), zS), Y(y - 0.15));
        g.lineTo(X(m * (w / 2 + tl), zS), Y(y + 0.12)); g.quadraticCurveTo(X(m * (w / 2 + tl * 0.5), zS), Y(y + 0.15), X(m * (w / 2 - 0.2), zS), Y(y + 0.4)); g.closePath();
        g.fillStyle = dark(0.09); g.fill();
        // pedicles ("owl eyes")
        ellipse(m * (w / 2 - 0.8), y - 0.5, zS - 1, 0.34, 0.52, 0, dark(0.05), dark(0.26), 0.17);
      });
      // spinous process
      ellipse(0, y + 0.55, zS - 3, 0.32, 0.8, 0, dark(0.08), dark(0.16), 0.1);
    });
    g.filter = 'none';

    // pelvis
    const zP = -2;
    g.filter = 'blur(1.2px)';
    // sacrum
    const sac = [[-5.4, 18.4], [5.4, 18.4], [4.6, 22], [3.0, 25.6], [1.4, 28], [0, 29.2], [-1.4, 28], [-3.0, 25.6], [-4.6, 22]];
    smoothPath(sac, -5.2, true); g.fillStyle = dark(0.16); g.fill(); g.strokeStyle = dark(0.22); g.lineWidth = S(0.18); g.stroke();
    for (let i = 0; i < 4; i++) { [1, -1].forEach(m => ellipse(m * (2.6 - i * 0.35), 20.2 + i * 2.2, -5.2, 0.42, 0.34, 0, lite(0.2), dark(0.18), 0.1)); }
    [1, -1].forEach(m => {
      // iliac wing
      const wing = [[4.6 * m, 18.6], [7.0 * m, 13.4], [10.6 * m, 10.6], [14.2 * m, 11.2], [15.6 * m, 14.0], [14.6 * m, 18.4], [12.6 * m, 22.6], [11.6 * m, 25.4], [9.6 * m, 24.2], [7.0 * m, 23.6], [5.0 * m, 22.6]];
      smoothPath(wing, zP, true);
      g.fillStyle = dark(0.12); g.fill();
      g.strokeStyle = dark(0.26); g.lineWidth = S(0.55); g.stroke();
      // iliac crest thickening
      smoothPath([[7.0 * m, 13.4], [10.6 * m, 10.6], [14.2 * m, 11.2], [15.6 * m, 14.0]], zP);
      g.strokeStyle = dark(0.2); g.lineWidth = S(0.9); g.stroke();
      // SI joint
      smoothPath([[4.6 * m, 18.6], [5.2 * m, 21], [4.8 * m, 23.2]], -4.8);
      g.strokeStyle = lite(0.18); g.lineWidth = S(0.18); g.stroke();
      // acetabulum + femoral head / neck / trochanter / shaft
      ellipse(9.4 * m, 26.8, 0, 2.6, 2.6, 0, dark(0.10), dark(0.30), 0.36);
      ellipse(9.6 * m, 27.0, 0.5, 2.25, 2.25, 0, dark(0.16), dark(0.24), 0.2);
      g.beginPath();
      g.moveTo(X(10.4 * m, 0.5), Y(25.8)); g.lineTo(X(13.4 * m, 0.5), Y(27.6)); g.lineTo(X(14.6 * m, 0.5), Y(29.6)); g.lineTo(X(13.2 * m, 0.5), Y(31.6)); g.lineTo(X(11.4 * m, 0.5), Y(31.0)); g.lineTo(X(9.8 * m, 0.5), Y(28.8)); g.closePath();
      g.fillStyle = dark(0.18); g.fill();
      g.beginPath(); g.moveTo(X(11.4 * m, 0.5), Y(31)); g.lineTo(X(10.4 * m, 0.5), Y(56)); g.lineTo(X(13.8 * m, 0.5), Y(56)); g.lineTo(X(13.2 * m, 0.5), Y(31.6)); g.closePath();
      g.fillStyle = dark(0.16); g.fill();
      g.strokeStyle = dark(0.28); g.lineWidth = S(0.45);
      g.beginPath(); g.moveTo(X(11.4 * m, 0.5), Y(31)); g.lineTo(X(10.4 * m, 0.5), Y(56)); g.moveTo(X(13.2 * m, 0.5), Y(31.6)); g.lineTo(X(13.8 * m, 0.5), Y(56)); g.stroke();
      // lesser trochanter
      ellipse(11.2 * m, 33.6, 0.5, 0.7, 0.9, 0, dark(0.16));
      // pubic rami and ischium around the obturator foramen
      smoothPath([[7.4 * m, 26.0], [4.4 * m, 27.4], [1.0 * m, 28.6]], zP + 2);
      g.strokeStyle = dark(0.24); g.lineWidth = S(1.1); g.stroke();
      smoothPath([[1.0 * m, 30.4], [3.2 * m, 32.4], [6.2 * m, 33.4], [8.4 * m, 31.4], [8.6 * m, 28.6]], zP + 1);
      g.strokeStyle = dark(0.22); g.lineWidth = S(1.2); g.stroke();
      ellipse(5.0 * m, 30.2, zP + 1.5, 2.0, 1.45, 0.25 * m, lite(0.10), dark(0.18), 0.22);
    });
    // pelvic brim
    g.beginPath(); g.ellipse(X(0, -2), Y(22.8), S(6.6) * ca, S(5.2), 0, Math.PI * 1.02, Math.PI * 1.98, true);
    g.strokeStyle = dark(0.28); g.lineWidth = S(0.5); g.stroke();
    // symphysis
    ellipse(0, 29.6, 2, 0.9, 1.2, 0, dark(0.16));
    g.filter = 'none';

    // final softening
    const out = document.createElement('canvas');
    out.width = W; out.height = H;
    const og = out.getContext('2d');
    og.filter = 'blur(1.1px)';
    og.drawImage(c, 0, 0);
    og.filter = 'none';
    return out;
  }

  /* fluoroscopy view: draws a scene + state onto a canvas (DUI page and NUI fallback) */
  class FluoroView {
    constructor(canvas, opts = {}) {
      this.cv = canvas;
      this.g = canvas.getContext('2d');
      this.o = Object.assign({ locale: {}, brand: true }, opts);
      this.scene = null; this.key = '';
      this.anat = null; this.anatCarm = 999; this.anatAt = 0;
      this.noise = makeNoise(256);
      this.pattern = null;
      this.layer = document.createElement('canvas');
      this.arrKey = ''; this.arr = null;
      this.cam = null; this.mag = 1;
      this.lastXr = 0;
      this.noiseOff = [0, 0];
      this.ecgT = 0; this.ecg = [];
    }
    L(k, fb) { const v = this.o.locale && this.o.locale[k]; return v !== undefined ? v : fb; }
    ensure(sc) {
      if (!sc) return null;
      const key = `${sc.seed}|${sc.key}|${sc.side}|${sc.sev}`;
      if (key !== this.key) { this.scene = buildScene(sc); this.key = key; this.anat = null; this.arrKey = ''; }
      return this.scene;
    }
    standby(now) {
      const { g, cv } = this;
      const W = cv.width, H = cv.height;
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.fillStyle = '#030405'; g.fillRect(0, 0, W, H);
      const s = H / 720;
      const gr = g.createRadialGradient(W / 2, H / 2, 10, W / 2, H / 2, W * 0.6);
      gr.addColorStop(0, 'rgba(8,175,162,.10)'); gr.addColorStop(1, 'rgba(8,175,162,0)');
      g.fillStyle = gr; g.fillRect(0, 0, W, H);
      // detector ready ring: slow sweep around the radiation sign, model code under it
      const cx0 = W / 2, cy0 = H / 2 - 30 * s, rr = 62 * s;
      g.strokeStyle = 'rgba(255,255,255,.08)'; g.lineWidth = 3 * s; g.beginPath(); g.arc(cx0, cy0, rr, 0, TAU); g.stroke();
      const a0 = (now / 1400) % TAU;
      g.strokeStyle = 'rgba(15,212,196,.85)'; g.lineWidth = 3 * s; g.lineCap = 'round';
      g.beginPath(); g.arc(cx0, cy0, rr, a0, a0 + 1.1); g.stroke(); g.lineCap = 'butt';
      for (let i = 0; i < 48; i++) { const a = i / 48 * TAU; g.strokeStyle = `rgba(255,255,255,${i % 4 ? 0.08 : 0.2})`; g.lineWidth = 1 * s; g.beginPath(); g.moveTo(cx0 + Math.cos(a) * (rr + 8 * s), cy0 + Math.sin(a) * (rr + 8 * s)); g.lineTo(cx0 + Math.cos(a) * (rr + (i % 4 ? 12 : 16) * s), cy0 + Math.sin(a) * (rr + (i % 4 ? 12 : 16) * s)); g.stroke(); }
      drawTrefoil(g, cx0, cy0, 30 * s, 'rgba(242,194,48,.9)');
      g.textAlign = 'center';
      g.fillStyle = '#ffffff'; g.font = `700 ${22 * s}px "JetBrains Mono", monospace`;
      g.fillText(this.L('screen.model', 'AX-3'), W / 2, cy0 + rr + 52 * s);
      g.fillStyle = 'rgba(255,255,255,.5)'; g.font = `500 ${12 * s}px "JetBrains Mono", monospace`;
      g.fillText(this.L('screen.standby', 'ANGIOGRAPHY · STANDBY'), W / 2, cy0 + rr + 76 * s);
      g.textAlign = 'left';
    }
    /* st = state (see Sim.snapshot) */
    render(st, now) {
      const { g, cv } = this;
      const W = cv.width, H = cv.height;
      if (!st || !st.sc) return this.standby(now);
      const sc = this.ensure(st.sc);
      const nd = sc.nodes;
      const s = H / 720;
      const imgW = Math.min(W - 40 * s, H * 1.26);
      const ix = (W - imgW) / 2;
      this.mag = lerp(this.mag, clamp(st.mag || 1, 1, 2.5), 0.2);
      if (Math.abs(this.mag - (st.mag || 1)) < 0.004) this.mag = st.mag || 1;
      const scale = imgW / FOV_W * this.mag;
      const cx = ix + imgW / 2, cy = H / 2;
      const carm = st.carm || 0;
      const ca = Math.cos(carm * DEG), sa = Math.sin(carm * DEG);
      if (!this.cam) this.cam = { x: st.cx || 0, y: st.cy || 8 };
      this.cam.x = lerp(this.cam.x, st.cx || 0, 0.25); this.cam.y = lerp(this.cam.y, st.cy || 8, 0.25);
      const camX = this.cam.x, camY = this.cam.y;
      const PX = (x, z) => cx + ((x * ca + z * sa) - camX) * scale;
      const PY = y => cy + (y - camY) * scale;
      const P = i => [PX(nd.x[i], nd.z[i]), PY(nd.y[i])];

      // plain film cache (re-drawn when the C-arm moves)
      if (!this.anat || (Math.abs(this.anatCarm - carm) > 0.4 && now - this.anatAt > 140)) {
        this.anat = drawAnatomy(sc, carm); this.anatCarm = carm; this.anatAt = now;
      }
      const dsa = clamp(st.dsa || 0, 0, 1);

      g.setTransform(1, 0, 0, 1, 0, 0);
      g.globalCompositeOperation = 'source-over';
      g.globalAlpha = 1;
      g.fillStyle = '#050607'; g.fillRect(0, 0, W, H);
      g.save();
      roundRect(g, ix, 6 * s, imgW, H - 12 * s, 26 * s); g.clip();
      // plain film
      const k = scale / SA;
      g.drawImage(this.anat, cx + (BODY.x0 - camX) * scale, cy + (BODY.y0 - camY) * scale, this.anat.width * k, this.anat.height * k);
      if (dsa > 0) { g.globalAlpha = dsa * 0.86; g.fillStyle = '#a3a7ab'; g.fillRect(ix, 0, imgW, H); g.globalAlpha = 1; }

      // vessel layer (white = nothing, grey = contrast), multiplied onto the film
      const Ly = this.layer;
      if (Ly.width !== W || Ly.height !== H) { Ly.width = W; Ly.height = H; }
      const lg = Ly.getContext('2d');
      lg.globalCompositeOperation = 'source-over';
      lg.fillStyle = '#fff'; lg.fillRect(0, 0, W, H);
      lg.globalCompositeOperation = 'darken';
      lg.lineCap = 'round'; lg.lineJoin = 'round';
      const grey = a => { const v = Math.round(255 * (1 - 0.9 * clamp(a, 0, 1))); return `rgb(${v},${v},${v})`; };
      const seg = (i, p, a, wMul = 1) => {
        if (a <= 0.01) return;
        const A = P(i), B = P(p);
        const w = Math.max(1.2 * s, nd.r[i] * 2 * scale * wMul);
        lg.strokeStyle = grey(a * 0.45); lg.lineWidth = w + 2.4 * s;
        lg.beginPath(); lg.moveTo(A[0], A[1]); lg.lineTo(B[0], B[1]); lg.stroke();
        lg.strokeStyle = grey(a); lg.lineWidth = w;
        lg.beginPath(); lg.moveTo(A[0], A[1]); lg.lineTo(B[0], B[1]); lg.stroke();
      };
      const decoDraw = (d, a, tFill) => {
        if (a <= 0.01) return;
        lg.strokeStyle = grey(a); lg.lineWidth = Math.max(1 * s, d.r * 2 * scale);
        lg.beginPath();
        let started = false;
        for (let i = 0; i < d.pts.length; i++) {
          if (tFill !== undefined && d.d[i] > tFill) {
            if (i > 0) { const f = (tFill - d.d[i - 1]) / Math.max(0.001, d.d[i] - d.d[i - 1]); const q = d.pts[i - 1], r = d.pts[i]; lg.lineTo(PX(lerp(q[0], r[0], f), lerp(q[2], r[2], f)), PY(lerp(q[1], r[1], f))); }
            break;
          }
          const x = PX(d.pts[i][0], d.pts[i][2]), y = PY(d.pts[i][1]);
          if (!started) { lg.moveTo(x, y); started = true; } else lg.lineTo(x, y);
        }
        lg.stroke();
      };

      // road-map from the last run (faint)
      const rm = st.rm || [];
      if (rm.length) {
        const set = new Set(rm);
        const ra = 0.2 * (1 - dsa * 0.5);
        for (const vi of set) {
          const v = sc.vessels[vi]; if (!v) continue;
          for (let j = 1; j < v.draw.length; j++) seg(v.draw[j], v.draw[j - 1], ra);
        }
        sc.deco.forEach(d => { if (set.has(nd.v[d.feed])) decoDraw(d, ra * 0.8); });
      }

      // contrast run / puff
      let bleedOp = 0;
      const run = st.run;
      if (run) {
        const key = `${run.id}|${run.a}|${run.b}|${run.f.toFixed(3)}|${(st.coils || []).map(c => `${c[0]}.${c[1]}.${c[3]}`).join(',')}`;
        if (key !== this.arrKey) {
          const coils = (st.coils || []).map(c => ({ a: c[0], b: c[1], f: c[2], pct: c[3], rel: c[4] }));
          this.arr = computeArrival(sc, { a: run.a, b: run.b, f: run.f }, coils, run.k, st.cd || 2);
          this.arrKey = key;
        }
        const R = this.arr, t = run.t, inj = INJ[run.k] || 2.4;
        const op = i => opacity(t, R.arr[i], inj);
        // the bit of vessel between the tip and the first downstream node
        const tipP = lerpPos(sc, run.a, run.b, run.f);
        const dn = R.down;
        if (t > 0.02) {
          const a0 = Math.min(1, t / 0.2) * (opacity(t, 0, inj));
          const Q = P(dn);
          lg.strokeStyle = grey(a0); lg.lineWidth = Math.max(1.4 * s, nd.r[dn] * 2 * scale);
          lg.beginPath(); lg.moveTo(PX(tipP[0], tipP[2]), PY(tipP[1])); lg.lineTo(Q[0], Q[1]); lg.stroke();
        }
        for (let i = 0; i < nd.x.length; i++) {
          const p = nd.p[i];
          if (p < 0 || !isFinite(R.arr[i]) || !isFinite(R.arr[p])) continue;
          const a = Math.min(op(i), op(p) || op(i)) * (nd.r[i] > 0.3 ? 0.95 : 0.85);
          if (a > 0.01) seg(i, p, a);
        }
        // twigs and arcades
        sc.deco.forEach(d => {
          const a0 = R.arr[d.feed];
          if (!isFinite(a0)) return;
          const tf = (t - a0) * 9;
          if (tf <= 0) return;
          decoDraw(d, opacity(t, a0 + 0.12, inj) * 0.8, tf);
        });
        // capillary blush
        sc.organs.forEach(o => {
          const v = sc.vessels[o.feed];
          const end = v.own[v.own.length - 1];
          const a0 = R.arr[end];
          if (!isFinite(a0)) return;
          const tt = t - a0 - 0.55;
          if (tt <= 0) return;
          const a = o.a * (tt < 0.9 ? tt / 0.9 : Math.max(0, 1 - (tt - 0.9 - inj * 0.4) / 2.4));
          if (a <= 0.01) return;
          const x = PX(o.x, o.z), y = PY(o.y);
          lg.save(); lg.translate(x, y); lg.rotate(o.rot); lg.scale(1, o.ry / o.rx);
          const gr = lg.createRadialGradient(0, 0, 0, 0, 0, o.rx * scale * ca);
          gr.addColorStop(0, grey(a)); gr.addColorStop(0.75, grey(a * 0.7)); gr.addColorStop(1, '#fff');
          lg.fillStyle = gr; lg.beginPath(); lg.arc(0, 0, o.rx * scale * ca, 0, TAU); lg.fill();
          lg.restore();
        });
        if (isFinite(R.bleedT) && t > R.bleedT) bleedOp = R.bleedI * clamp((t - R.bleedT) / 2.4, 0, 1);
      }
      // extravasated contrast lingers after the run (stain)
      if (st.stain > bleedOp) bleedOp = st.stain;
      if (bleedOp > 0.01) {
        const b = sc.bleed;
        const bx = PX(b.x, b.z), by = PY(b.y);
        const grow = 0.45 + 0.55 * bleedOp;
        b.blobs.forEach(bl => {
          const r = Math.max(2, b.R * bl.r * scale * grow);
          const x = bx + bl.dx * scale * b.R * grow, y = by + bl.dy * scale * b.R * grow;
          const gr = lg.createRadialGradient(x, y, 0, x, y, r);
          gr.addColorStop(0, grey(bl.k * bleedOp)); gr.addColorStop(0.5, grey(bl.k * 0.62 * bleedOp)); gr.addColorStop(1, '#fff');
          lg.fillStyle = gr; lg.beginPath(); lg.arc(x, y, r, 0, TAU); lg.fill();
        });
      }
      g.globalCompositeOperation = 'multiply';
      g.drawImage(Ly, 0, 0);
      g.globalCompositeOperation = 'source-over';

      // coils (metal: the darkest thing on screen)
      (st.coils || []).forEach(c => drawCoil(g, sc, c, PX, PY, scale, s));

      // catheter
      const path = st.p || [];
      if (path.length >= 2) {
        g.lineCap = 'round'; g.lineJoin = 'round';
        g.strokeStyle = 'rgba(14,15,17,.92)'; g.lineWidth = Math.max(2.2 * s, 0.16 * scale);
        const tip = lerpPos(sc, path[path.length - 2], path[path.length - 1], st.f || 0);
        const T = [PX(tip[0], tip[2]), PY(tip[1])];
        g.beginPath();
        for (let i = 0; i < path.length - 1; i++) { const q = P(path[i]); if (i) g.lineTo(q[0], q[1]); else g.moveTo(q[0], q[1]); }
        g.lineTo(T[0], T[1]);
        g.stroke();
        // shaped tip (hook) - its 3D direction depends on the tip rotation
        const hook = tipHook(sc, path, st.f || 0, st.phi || 0);
        if (hook) {
          g.strokeStyle = 'rgba(10,11,12,.96)'; g.lineWidth = Math.max(2.4 * s, 0.17 * scale);
          g.beginPath(); g.moveTo(T[0], T[1]);
          hook.forEach(p => g.lineTo(PX(p[0], p[2]), PY(p[1])));
          g.stroke();
          const e = hook[hook.length - 1];
          g.fillStyle = '#060707'; g.beginPath(); g.arc(PX(e[0], e[2]), PY(e[1]), Math.max(2.2 * s, 0.11 * scale), 0, TAU); g.fill();
        }
        // radio-opaque marker band near the tip
        g.fillStyle = '#060707'; g.beginPath(); g.arc(T[0], T[1], Math.max(2.4 * s, 0.12 * scale), 0, TAU); g.fill();
      }

      // vertebral levels (orientation aid)
      g.font = `500 ${10.5 * s}px "JetBrains Mono", monospace`;
      g.fillStyle = 'rgba(255,255,255,.34)';
      LEVELS.forEach(([lv, y]) => { const yy = PY(y); if (yy > 30 * s && yy < H - 30 * s) g.fillText(lv, PX(-VW[lv] / 2 - 3.6, -4.6), yy + 4 * s); });
      // radiographic side marker
      g.fillStyle = 'rgba(255,255,255,.75)'; g.font = `700 ${18 * s}px Lexend, sans-serif`;
      g.fillText(this.L('screen.marker', 'L'), ix + imgW - 34 * s, 40 * s);

      // quantum mottle: animated while X-ray is on, frozen on last-image-hold
      if (st.xr || run) { this.noiseOff = [Math.random() * 256, Math.random() * 256]; }
      if (!this.pattern) this.pattern = g.createPattern(this.noise, 'repeat');
      g.save();
      g.globalCompositeOperation = 'overlay';
      g.globalAlpha = 0.16 + (st.xr ? 0.04 : 0);
      g.translate(this.noiseOff[0], this.noiseOff[1]);
      g.fillStyle = this.pattern; g.fillRect(-this.noiseOff[0], -this.noiseOff[1], W, H);
      g.restore();
      // vignette
      const vg = g.createRadialGradient(cx, cy, H * 0.3, cx, cy, imgW * 0.7);
      vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.55)');
      g.fillStyle = vg; g.fillRect(ix, 0, imgW, H);
      g.restore();

      // detector bezel
      g.strokeStyle = 'rgba(255,255,255,.06)'; g.lineWidth = 2 * s;
      roundRect(g, ix, 6 * s, imgW, H - 12 * s, 26 * s); g.stroke();

      // leak marker: corner-bracket reticle round the blush, pulsing diamond, label chip under it
      if (st.bs) {
        const b = sc.bleed;
        const bx = PX(b.x, b.z), by = PY(b.y);
        const half = Math.max(22 * s, b.R * scale * 1.15);
        const pulse = (Math.sin(now / 260) + 1) / 2;
        const arm = Math.min(14 * s, half * 0.5);
        // gap ring: tightens round the leak as the catheter tip closes in; the dotted ring is the coil
        // range, the ring locks onto it (solid teal) once the tip is in range on the feeding branch
        const gp = Array.isArray(st.gp) ? st.gp : null;
        if (gp) {
          const cd = st.cd || 2, lockR = half + 12 * s;
          const far = clamp((Number(gp[0]) - cd) / Math.max(1, (Number(gp[3]) || 30) - cd), 0, 1);
          g.save();
          g.setLineDash([1.5 * s, 4.5 * s]); g.lineWidth = 1.2 * s; g.strokeStyle = 'rgba(255,255,255,.32)';
          g.beginPath(); g.arc(bx, by, lockR, 0, TAU); g.stroke();
          g.setLineDash([]);
          if (gp[1]) {
            g.strokeStyle = `rgba(31,224,200,${0.7 + pulse * 0.3})`; g.lineWidth = 2.4 * s;
            g.shadowColor = 'rgba(31,224,200,.7)'; g.shadowBlur = 8 * s;
            g.beginPath(); g.arc(bx, by, lockR, 0, TAU); g.stroke();
          } else {
            const rr = lockR + (6 + Math.sqrt(far) * 70) * s;
            g.strokeStyle = gp[2] ? 'rgba(243,195,90,.85)' : 'rgba(255,255,255,.4)'; g.lineWidth = 1.8 * s;
            g.setLineDash(gp[2] ? [] : [6 * s, 5 * s]);
            g.beginPath(); g.arc(bx, by, rr, 0, TAU); g.stroke();
            g.setLineDash([]);
            // four ticks on the ring point inward: the ring closes toward the dotted coil range
            g.lineWidth = 1.6 * s;
            for (let k = 0; k < 4; k++) {
              const a = k * Math.PI / 2 + Math.PI / 4;
              g.beginPath(); g.moveTo(bx + Math.cos(a) * rr, by + Math.sin(a) * rr); g.lineTo(bx + Math.cos(a) * (rr - 6 * s), by + Math.sin(a) * (rr - 6 * s)); g.stroke();
            }
          }
          g.restore();
        }
        g.strokeStyle = `rgba(255,96,100,${0.75 + pulse * 0.25})`; g.lineWidth = 2 * s;
        [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([sx, sy]) => {
          const x = bx + sx * half, y = by + sy * half;
          g.beginPath(); g.moveTo(x, y - sy * arm); g.lineTo(x, y); g.lineTo(x - sx * arm, y); g.stroke();
        });
        const d = (5 + pulse * 2) * s;
        g.fillStyle = 'rgba(255,90,95,.95)';
        g.beginPath(); g.moveTo(bx, by - half - d - 6 * s); g.lineTo(bx + d, by - half - 6 * s); g.lineTo(bx, by - half + d - 6 * s); g.lineTo(bx - d, by - half - 6 * s); g.closePath(); g.fill();
        const lbl = this.L('screen.bleed', 'LEAK');
        g.font = `700 ${10.5 * s}px "JetBrains Mono", monospace`;
        const tw = g.measureText(lbl).width + 14 * s;
        const tx = bx - tw / 2, ty = by + half + 6 * s;
        g.fillStyle = 'rgba(8,9,11,.88)'; roundRect(g, tx, ty, tw, 18 * s, 4 * s); g.fill();
        g.fillStyle = '#e5484d'; g.fillRect(tx, ty + 3 * s, 2 * s, 12 * s);
        g.fillStyle = '#ff8a8d'; g.fillText(lbl, tx + 8 * s, ty + 13 * s);
      }

      this.hud(st, W, H, s, ix, imgW, now);
    }
    hud(st, W, H, s0, ix, imgW, now) {
      const g = this.g;
      const s = Math.max(s0, Math.min(0.94, s0 * 1.25));
      const h = st.hud || {};
      const L = (k, fb) => this.L(k, fb);
      const mono = (px, w = 500) => `${w} ${px * s}px "JetBrains Mono", monospace`;
      const lex = (px, w = 600) => `${w} ${px * s}px Lexend, sans-serif`;
      const bandL = ix, x0 = 18 * s;
      g.textBaseline = 'alphabetic';
      // left band: device plate (model code + radiation sign, no brand), patient, exposure
      const plateW = Math.min(bandL - x0 - 12 * s, 112 * s);
      g.fillStyle = 'rgba(255,255,255,.06)'; roundRect(g, x0, 16 * s, plateW, 34 * s, 6 * s); g.fill();
      g.strokeStyle = 'rgba(255,255,255,.1)'; g.lineWidth = 1 * s; roundRect(g, x0, 16 * s, plateW, 34 * s, 6 * s); g.stroke();
      drawTrefoil(g, x0 + 17 * s, 33 * s, 9 * s, 'rgba(242,194,48,.95)');
      g.fillStyle = '#fff'; g.font = mono(13, 700); g.fillText(L('screen.model', 'AX-3'), x0 + 32 * s, 31 * s);
      g.fillStyle = 'rgba(255,255,255,.45)'; g.font = mono(8.5); g.fillText(L('screen.suite', 'ANGIO'), x0 + 32 * s, 44 * s);
      const rows = [
        [L('screen.patient', 'PATIENT'), h.name || '--', h.sexAge],
        [L('screen.case', 'CASE'), h.caseId || '--'],
        [L('screen.exposure', 'EXPOSURE'), `${Math.round(h.kv || 81)} kV`, `${(h.ma || 2.4).toFixed(1)} mA · 15 f/s`],
        [L('screen.fluoro', 'FLUORO'), fmtTime(h.fl || 0)],
        [L('screen.dose', 'DOSE'), `${(h.dose || 0).toFixed(1)} mGy`],
      ];
      let y = 84 * s;
      const fitText = (txt, maxW) => { let t = String(txt); while (t.length > 3 && g.measureText(t).width > maxW) t = t.slice(0, -2); return t === String(txt) ? t : `${t}…`; };
      rows.forEach(([k, v, sub2], i) => {
        // instrument row: tone notch on the left, label over value
        g.fillStyle = i === 3 && (st.xr || st.run) ? '#f2b33d' : 'rgba(255,255,255,.16)'; g.fillRect(x0, y - 8 * s, 2 * s, (sub2 ? 44 : 28) * s);
        g.fillStyle = 'rgba(255,255,255,.4)'; g.font = mono(9); g.fillText(k, x0 + 9 * s, y);
        g.fillStyle = 'rgba(255,255,255,.92)'; g.font = mono(12.5, 500); g.fillText(fitText(v, bandL - x0 - 19 * s), x0 + 9 * s, y + 17 * s);
        if (sub2) { g.fillStyle = 'rgba(255,255,255,.5)'; g.font = mono(10); g.fillText(fitText(sub2, bandL - x0 - 19 * s), x0 + 9 * s, y + 32 * s); y += 15 * s; }
        y += 44 * s;
      });
      // scale bar (5 cm)
      const sc5 = 5 * (imgW / FOV_W) * (this.mag || 1);
      const by = H - 30 * s;
      g.strokeStyle = 'rgba(255,255,255,.6)'; g.lineWidth = 1.5 * s;
      g.beginPath(); g.moveTo(x0, by); g.lineTo(x0 + Math.min(sc5, bandL - x0 - 16 * s), by); g.stroke();
      for (let i = 0; i <= 5; i++) { const xx = x0 + Math.min(sc5, bandL - x0 - 16 * s) * i / 5; g.beginPath(); g.moveTo(xx, by); g.lineTo(xx, by - (i % 5 === 0 ? 8 : 4) * s); g.stroke(); }
      g.fillStyle = 'rgba(255,255,255,.55)'; g.font = mono(9.5); g.fillText(L('screen.scale', '5 cm'), x0, by - 12 * s);

      // right band: mode lamp, run, C-arm, contrast, ECG
      const rx = ix + imgW + 16 * s, rw = W - rx - 16 * s;
      const live = st.xr || !!st.run;
      g.fillStyle = live ? '#f2b33d' : 'rgba(255,255,255,.18)';
      g.beginPath(); g.arc(rx + 6 * s, 28 * s, 5 * s, 0, TAU); g.fill();
      if (live) { g.fillStyle = 'rgba(242,179,61,.25)'; g.beginPath(); g.arc(rx + 6 * s, 28 * s, 10 * s, 0, TAU); g.fill(); }
      g.fillStyle = '#fff'; g.font = lex(13, 700);
      g.fillText(st.dsa > 0.3 ? L('screen.dsa', 'DSA') : L('screen.fluoroMode', 'FLUORO'), rx + 18 * s, 33 * s);
      g.fillStyle = 'rgba(255,255,255,.45)'; g.font = mono(9.5);
      g.fillText(live ? L('screen.live', 'LIVE · 15 f/s') : L('screen.lih', 'LAST IMAGE HOLD'), rx, 52 * s);
      // current run, right under the mode lamp
      const label = String(h.label || '');
      if (label) {
        const parts = label.split(' · ');
        g.fillStyle = 'rgba(242,179,61,.16)'; roundRect(g, rx - 2 * s, 60 * s, rw + 2 * s, parts[1] ? 36 * s : 20 * s, 5 * s); g.fill();
        g.fillStyle = '#f3c35a'; g.font = mono(9, 700); g.fillText(fitText(parts[0].toUpperCase(), rw - 10 * s), rx + 5 * s, 73 * s);
        if (parts[1]) { g.fillStyle = 'rgba(255,255,255,.88)'; g.font = mono(10.5, 500); g.fillText(fitText(parts[1], rw - 10 * s), rx + 5 * s, 89 * s); }
      }
      const rrows = [
        [L('screen.run', 'RUN'), String(h.run || 0).padStart(2, '0')],
        [L('screen.field', 'FIELD'), `${Math.round(FOV_W / (this.mag || 1))} cm${(this.mag || 1) > 1.05 ? ` · ${L('screen.mag', 'MAG')}` : ''}`],
        [L('screen.contrast', 'CONTRAST'), `${Math.round(h.ml || 0)} mL`],
        [L('screen.coils', 'COILS'), String(h.coils || 0)],
      ];
      y = 118 * s;
      rrows.forEach(([k, v], i) => {
        g.fillStyle = 'rgba(255,255,255,.16)'; g.fillRect(rx, y - 8 * s, 2 * s, 28 * s);
        g.fillStyle = 'rgba(255,255,255,.4)'; g.font = mono(9); g.fillText(k, rx + 9 * s, y);
        g.fillStyle = 'rgba(255,255,255,.92)'; g.font = mono(12.5, 500); g.fillText(fitText(v, rw - 9 * s), rx + 9 * s, y + 17 * s);
        y += 42 * s;
        void i;
      });
      // C-arm: 240° dial, needle at the projection angle (RAO left, LAO right)
      const dr = Math.min(26 * s, rw * 0.32), dcx = rx + rw / 2, dcy = y + dr + 6 * s;
      const A0 = 150 * DEG, SW = 240 * DEG, tf = clamp(((st.carm || 0) + 45) / 90, 0, 1);
      g.lineCap = 'round';
      g.strokeStyle = 'rgba(255,255,255,.1)'; g.lineWidth = 4 * s; g.beginPath(); g.arc(dcx, dcy, dr, A0, A0 + SW); g.stroke();
      g.strokeStyle = 'rgba(15,212,196,.35)'; g.lineWidth = 7 * s; g.beginPath(); g.arc(dcx, dcy, dr, A0 + SW * 0.47, A0 + SW * 0.53); g.stroke();
      for (let i = 0; i <= 6; i++) { const a = A0 + SW * i / 6; g.strokeStyle = 'rgba(255,255,255,.25)'; g.lineWidth = 1 * s; g.beginPath(); g.moveTo(dcx + Math.cos(a) * (dr + 5 * s), dcy + Math.sin(a) * (dr + 5 * s)); g.lineTo(dcx + Math.cos(a) * (dr + 9 * s), dcy + Math.sin(a) * (dr + 9 * s)); g.stroke(); }
      const na = A0 + SW * tf;
      g.strokeStyle = '#0fd4c4'; g.lineWidth = 2.5 * s; g.beginPath(); g.moveTo(dcx + Math.cos(na) * (dr - 8 * s), dcy + Math.sin(na) * (dr - 8 * s)); g.lineTo(dcx + Math.cos(na) * (dr + 6 * s), dcy + Math.sin(na) * (dr + 6 * s)); g.stroke();
      g.lineCap = 'butt';
      g.textAlign = 'center'; g.fillStyle = 'rgba(255,255,255,.85)'; g.font = mono(10.5, 600); g.fillText(h.carmLabel || 'AP', dcx, dcy + 4 * s);
      g.fillStyle = 'rgba(255,255,255,.35)'; g.font = mono(8); g.fillText(L('screen.carm', 'C-ARM'), dcx, dcy + dr + 4 * s);
      g.textAlign = 'left';
      // ECG strip
      const ex = rx, ew = rw, ey = H - 52 * s, eh = 30 * s;
      g.fillStyle = 'rgba(255,255,255,.38)'; g.font = mono(9);
      g.fillText(`${L('screen.hr', 'HR')} ${h.hr ? Math.round(h.hr) : '--'}`, ex, ey - 4 * s);
      if (h.hr) {
        g.strokeStyle = '#0fd4c4'; g.lineWidth = 1.4 * s;
        g.beginPath();
        const t0 = now / 1000;
        for (let i = 0; i <= 60; i++) {
          const tt = t0 - (60 - i) * 0.04;
          const per = 60 / Math.max(30, h.hr);
          const ph = ((tt % per) + per) % per / per;
          const v = (window.NZA && window.NZA.vitals) ? window.NZA.vitals.pqrst(ph) : Math.exp(-((ph - 0.3) ** 2) / 0.0004);
          const xx = ex + ew * i / 60, yy = ey + eh * 0.65 - v * eh * 0.55;
          if (i) g.lineTo(xx, yy); else g.moveTo(xx, yy);
        }
        g.stroke();
      }
    }
  }

  function lerpPos(sc, a, b, f) {
    const A = nodePos(sc, a), B = nodePos(sc, b);
    return [lerp(A[0], B[0], f), lerp(A[1], B[1], f), lerp(A[2], B[2], f)];
  }
  // a point `back` cm behind the tip along the path
  function pathPointBack(sc, path, f, back) {
    let i = path.length - 1;
    let p = lerpPos(sc, path[i - 1], path[i], f);
    let rem = back;
    let cur = p, idx = i - 1;
    while (idx >= 0 && rem > 0) {
      const q = nodePos(sc, path[idx]);
      const d = len(sub(cur, q));
      if (d >= rem) { const t = rem / (d || 1); return [lerp(cur[0], q[0], t), lerp(cur[1], q[1], t), lerp(cur[2], q[2], t)]; }
      rem -= d; cur = q; idx--;
    }
    return cur;
  }
  function frameFor(t) {
    let e1 = sub([0, 0, 1], mul(t, t[2]));
    if (len(e1) < 0.25) e1 = sub([1, 0, 0], mul(t, t[0]));
    e1 = norm(e1);
    const e2 = norm(cross(t, e1));
    return [e1, e2];
  }
  function tipDir(sc, path, f) {
    if (!path || path.length < 2) return [0, 1, 0];
    const tip = lerpPos(sc, path[path.length - 2], path[path.length - 1], f);
    const back = pathPointBack(sc, path, f, 1.2);
    const d = sub(tip, back);
    return len(d) > 1e-4 ? norm(d) : norm(sub(nodePos(sc, path[path.length - 1]), nodePos(sc, path[path.length - 2])));
  }
  function tipHook(sc, path, f, phi) {
    if (!path || path.length < 2) return null;
    const tip = lerpPos(sc, path[path.length - 2], path[path.length - 1], f);
    const t = tipDir(sc, path, f);
    const [e1, e2] = frameFor(t);
    const d = add(mul(e1, Math.cos(phi)), mul(e2, Math.sin(phi)));
    const pts = [];
    for (let i = 1; i <= 5; i++) {
      const k = i / 5;
      const dir = norm(add(mul(t, 1 - k * 0.75), mul(d, k * 0.95)));
      const prev = pts.length ? pts[pts.length - 1] : tip;
      pts.push(add(prev, mul(dir, 0.16)));
    }
    return pts;
  }
  function drawCoil(g, sc, c, PX, PY, scale, s) {
    const [a, b, f, pct] = c;
    if (!(pct > 0)) return;
    const A = nodePos(sc, a), B = nodePos(sc, b);
    const base = lerpPos(sc, a, b, f);
    const dir = norm(sub(B, A));
    const lenC = 1.1 * clamp(pct / 100, 0, 1);
    if (lenC < 0.02) return;
    const r = Math.max(0.17, Math.min(0.27, sc.nodes.r[edgeChild(sc, a, b)] * 1.3));
    const [e1, e2] = frameFor(dir);
    const turns = Math.max(2, Math.round(lenC / 0.15));
    const pts = [];
    for (let i = 0; i <= turns * 12; i++) {
      const k = i / (turns * 12);
      const ang = k * turns * TAU;
      // packed coils ball up toward the end
      const along = lenC * Math.pow(k, 0.85);
      const rr = r * (0.72 + 0.28 * Math.sin(k * 7.5));
      const p = add(add(base, mul(dir, along)), add(mul(e1, Math.cos(ang) * rr), mul(e2, Math.sin(ang) * rr)));
      pts.push([PX(p[0], p[2]), PY(p[1])]);
    }
    const path = () => { g.beginPath(); pts.forEach((q, i) => (i ? g.lineTo(q[0], q[1]) : g.moveTo(q[0], q[1]))); };
    g.lineCap = 'round'; g.lineJoin = 'round';
    // platinum blooms on the detector: soft dark halo, then the wire
    g.strokeStyle = 'rgba(0,0,0,.28)'; g.lineWidth = Math.max(4.5 * s, 0.17 * scale); path(); g.stroke();
    g.strokeStyle = 'rgba(3,4,5,.98)'; g.lineWidth = Math.max(1.6 * s, 0.055 * scale); path(); g.stroke();
  }
  function roundRect(g, x, y, w, h, r) {
    g.beginPath(); g.moveTo(x + r, y); g.lineTo(x + w - r, y); g.quadraticCurveTo(x + w, y, x + w, y + r); g.lineTo(x + w, y + h - r);
    g.quadraticCurveTo(x + w, y + h, x + w - r, y + h); g.lineTo(x + r, y + h); g.quadraticCurveTo(x, y + h, x, y + h - r); g.lineTo(x, y + r); g.quadraticCurveTo(x, y, x + r, y); g.closePath();
  }
  // radiation warning sign (trefoil) - generic device marking, centred on cx, cy
  function drawTrefoil(g, cx, cy, r, color) {
    g.save();
    g.fillStyle = color || '#f2c230';
    g.beginPath(); g.arc(cx, cy, r * 0.2, 0, TAU); g.fill();
    for (let i = 0; i < 3; i++) {
      const a = -Math.PI / 2 + i * TAU / 3;
      g.beginPath(); g.arc(cx, cy, r, a - 0.52, a + 0.52); g.arc(cx, cy, r * 0.32, a + 0.52, a - 0.52, true); g.closePath(); g.fill();
    }
    g.restore();
  }
  // legacy tile mark (kept for the export; no longer drawn on device faces)
  function drawMark(g, x, y, size) {
    const gr = g.createLinearGradient(x, y, x + size * 0.6, y + size);
    gr.addColorStop(0, '#0fd4c4'); gr.addColorStop(1, '#067d74');
    const r = size * 0.2;
    g.fillStyle = gr;
    g.beginPath();
    g.moveTo(x + r, y); g.lineTo(x + size - r, y); g.quadraticCurveTo(x + size, y, x + size, y + r);
    g.lineTo(x + size, y + size * 0.56); g.lineTo(x + size * 0.56, y + size); g.lineTo(x + r, y + size);
    g.quadraticCurveTo(x, y + size, x, y + size - r); g.lineTo(x, y + r); g.quadraticCurveTo(x, y, x + r, y); g.closePath();
    g.fill();
    g.fillStyle = 'rgba(0,0,0,.85)';
    g.fillRect(x + size * 0.22, y + size * 0.22, size * 0.56, size * 0.22);
  }
  const fmtTime = sec => { sec = Math.max(0, Math.floor(sec)); return `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(sec % 60).padStart(2, '0')}`; };

  /* a ready-made state for previews (DUI page ?demo=1): catheter from the right groin to just
     short of the bleed, road-map from a flush run, a selective run t seconds in */
  function demoState(params, t) {
    const sc = buildScene(params);
    const nd = sc.nodes;
    const entry = sc.entries.femoral_r.node;
    const up = []; for (let n = entry; n >= 0; n = nd.p[n]) up.push(n);
    const down = []; for (let n = sc.bleed.node; n >= 0; n = nd.p[n]) down.push(n);
    const set = new Set(down);
    const li = up.findIndex(n => set.has(n));
    const path = up.slice(0, li + 1).concat(down.slice(0, down.indexOf(up[li])).reverse());
    let cut = path.length - 1, d = 0;
    while (cut > 1 && d < 2.4) { d += len(sub(nodePos(sc, path[cut]), nodePos(sc, path[cut - 1]))); cut--; }
    const p = path.slice(0, cut + 1);
    const ao = sc.byId.aorta.own[6];
    const flush = computeArrival(sc, { a: nd.p[ao], b: ao, f: 0.5 }, [], 'run', 2);
    const rm = new Set(); for (let i = 0; i < flush.arr.length; i++) if (isFinite(flush.arr[i])) rm.add(nd.v[i]);
    const tip = lerpPos(sc, p[p.length - 2], p[p.length - 1], 0.4);
    return {
      sc: sc.params, p, f: 0.4, phi: 1.2, cx: (tip[0] + sc.bleed.x) / 2 * 0.8, cy: (tip[1] + sc.bleed.y) / 2,
      coils: [], rm: [...rm], bs: true, stain: 0.3, cd: 2, xr: true, dsa: t > 0 ? 0.9 : 0, carm: 12,
      run: t > 0 ? { id: 1, a: p[p.length - 2], b: p[p.length - 1], f: 0.4, k: 'run', t } : null,
      hud: { name: 'Tomas Lindqvist', sexAge: 'M · 34 · O-', caseId: 'A-0412', kv: 84, ma: 2.6, fl: 214, dose: 86.4, run: 3, carmLabel: 'LAO 12°', ml: 34, coils: 0, label: 'Selective run · Ileal arcade', hr: 112 },
    };
  }

  window.NZAAngio = { buildScene, computeArrival, FluoroView, drawMark, drawTrefoil, demoState, BLEEDS, MIN_R, fmtTime };

  /* everything below is the NUI overlay - the DUI page stops here */
  if (!window.NZA || typeof window.NZA.app !== 'function') return;
  const NZA = window.NZA;
  const esc = NZA.esc;

  /* ═══════════════════════════ SIMULATION ═══════════════════════════ */
  class Sim {
    constructor(sc, cfg) {
      this.sc = sc; this.cfg = cfg;
      this.path = []; this.f = 0; this.phi = 0; this.carm = 0;
      this.coils = []; this.deploy = null;
      this.run = null; this.runId = 0; this.runs = 0; this.stain = 0; this.stainAt = 0;
      this.rm = []; this.bleedSeen = false;
      this.contrastMl = 0; this.left = cfg.budget; this.fl = 0; this.dose = 0;
      this.xrUntil = 0; this.blocked = null; this.pushT = 0;
      this.cam = { x: 0, y: 8 }; this.mag = 1;
      this.stats = { spasm: 0, wrongRuns: 0, offCoils: 0, extraCoils: 0, bestDist: Infinity };
    }
    setAccess(key) {
      const sc = this.sc, e = sc.entries[key] || sc.entries.femoral_r;
      const nd = sc.nodes;
      this.access = key;
      if (key === 'radial') {
        this.path = [e.node, nd.c[e.node][0]];
      } else {
        // antegrade puncture when the bleed sits below the groin on the same side
        const ante = (sc.bleed.key === 'femoral' || sc.bleed.key === 'profunda') && sc.bleed.side === e.side;
        this.antegrade = ante;
        const next = ante ? nd.c[e.node][0] : nd.p[e.node];
        this.path = [e.node, next];
      }
      this.f = 0.02;
      const tip = this.tip();
      this.cam = { x: tip[0], y: tip[1] };
    }
    tip() { return lerpPos(this.sc, this.path[this.path.length - 2], this.path[this.path.length - 1], this.f); }
    edge() { return [this.path[this.path.length - 2], this.path[this.path.length - 1]]; }
    vessel() { const [a, b] = this.edge(); return this.sc.vessels[this.sc.nodes.v[edgeChild(this.sc, a, b)]]; }
    sTip() { const [a, b] = this.edge(); return treeS(this.sc, a, b, this.f); }
    segLen(a, b) { return len(sub(nodePos(this.sc, a), nodePos(this.sc, b))); }
    neighbours(n) { const nd = this.sc.nodes; const out = nd.c[n].slice(); if (nd.p[n] >= 0) out.push(nd.p[n]); return out; }
    // direction leaving junction j toward neighbour c (looks ~1.5 cm ahead)
    branchDir(j, c) {
      const sc = this.sc, nd = sc.nodes;
      let prev = j, cur = c, dist = 0;
      for (let i = 0; i < 4 && dist < 1.5; i++) {
        dist += this.segLen(prev, cur);
        let nxt;
        if (nd.p[prev] === cur) nxt = nd.p[cur]; else nxt = nd.c[cur].find(k => nd.v[k] === nd.v[cur]);
        if (nxt === undefined || nxt < 0) break;
        prev = cur; cur = nxt;
      }
      return norm(sub(nodePos(sc, cur), nodePos(sc, j)));
    }
    edgeR(from, to) { const nd = this.sc.nodes; return nd.p[to] === from ? nd.r[to] : nd.r[from]; }
    options(j, from) {
      const t = tipDir(this.sc, this.path, this.f);
      const [e1, e2] = frameFor(t);
      return this.neighbours(j).filter(c => c !== from).map(c => {
        const b = this.branchDir(j, c);
        const along = dot(b, t);
        const perp = sub(b, mul(t, along));
        const pl = len(perp);
        const psi = Math.atan2(dot(perp, e2), dot(perp, e1));
        return { node: c, dir: b, along, perp: pl, psi, r: this.edgeR(j, c), v: this.sc.nodes.v[this.sc.nodes.p[c] === j ? c : j] };
      });
    }
    choose(j, from) {
      const opts = this.options(j, from);
      if (!opts.length) return { blocked: 'end' };
      const ok = opts.filter(o => o.r >= MIN_R);
      if (!ok.length) return { blocked: 'narrow' };
      if (ok.length === 1) return { node: ok[0].node };
      let best = null;
      ok.forEach(o => { if (o.perp > 0.3) { const d = Math.abs(angDiff(this.phi, o.psi)); if (d < 40 * DEG && (!best || d < best.d)) best = { node: o.node, d }; } });
      if (best) return { node: best.node };
      let straight = ok[0];
      ok.forEach(o => { if (o.along > straight.along) straight = o; });
      if (straight.along < 0.2) {
        // T junction: nothing straight ahead, follow the nearest rotation
        let near = ok[0];
        ok.forEach(o => { if (Math.abs(angDiff(this.phi, o.psi)) < Math.abs(angDiff(this.phi, near.psi))) near = o; });
        return { node: near.node };
      }
      return { node: straight.node };
    }
    // the next junction ahead of the tip (for the tip compass)
    nextJunction(maxAhead = 3.5) {
      const nd = this.sc.nodes;
      let a = this.path[this.path.length - 2], b = this.path[this.path.length - 1];
      let dist = (1 - this.f) * this.segLen(a, b);
      for (let i = 0; i < 20 && dist < maxAhead; i++) {
        const all = this.neighbours(b).filter(c => c !== a);
        const nb = all.filter(c => this.edgeR(b, c) >= MIN_R);
        if (nb.length >= 2) return { node: b, from: a, dist, options: this.options(b, a).filter(o => o.r >= MIN_R) };
        if (!all.length) return { node: b, from: a, dist, end: true, options: [] };
        if (!nb.length) return { node: b, from: a, dist, narrow: true, options: [] };
        const nxt = nb[0];
        dist += this.segLen(b, nxt);
        a = b; b = nxt;
      }
      return null;
    }
    move(ds) {
      this.blocked = null;
      while (ds > 1e-6) {
        const a = this.path[this.path.length - 2], b = this.path[this.path.length - 1];
        const L = this.segLen(a, b) || 0.001;
        const rem = (1 - this.f) * L;
        if (ds < rem) { this.f += ds / L; ds = 0; break; }
        ds -= rem; this.f = 1;
        const nx = this.choose(b, a);
        if (nx.blocked) { this.blocked = nx.blocked; break; }
        this.path.push(nx.node); this.f = 0;
      }
      while (ds < -1e-6) {
        const a = this.path[this.path.length - 2], b = this.path[this.path.length - 1];
        const L = this.segLen(a, b) || 0.001;
        const back = this.f * L;
        if (-ds < back) { this.f += ds / L; ds = 0; break; }
        ds += back; this.f = 0;
        if (this.path.length <= 2) { this.blocked = 'sheath'; break; }
        this.path.pop(); this.f = 1;
      }
    }
    // tree distance tip → bleed (catheter travel), and whether the tip feeds the bleed
    toBleed() {
      const sc = this.sc, nd = sc.nodes, bl = sc.bleed;
      const [a, b] = this.edge();
      const child = edgeChild(sc, a, b), par = edgeParent(sc, a, b);
      const sT = this.sTip();
      if (bl.anc.has(child) && bl.anc.has(par)) return { d: nd.s[bl.node] - sT, feeds: true };
      if (inSubtree(sc, bl.node, child)) return { d: sT - nd.s[bl.node], feeds: false, past: true };
      let n = par;
      while (n >= 0 && !bl.anc.has(n)) n = nd.p[n];
      const lca = Math.max(0, n);
      return { d: (sT - nd.s[lca]) + (nd.s[bl.node] - nd.s[lca]), feeds: false };
    }
    inGate() { const v = this.vessel(); return v && v.anc.has(this.sc.bleed.gate); }
    injection() { const [a, b] = this.edge(); return { a, b, f: this.f }; }
    coilEffect(c) {
      const sc = this.sc, nd = sc.nodes, bl = sc.bleed;
      const cd = edgeChild(sc, c.a, c.b), cp = edgeParent(sc, c.a, c.b);
      const sC = treeS(sc, c.a, c.b, c.f);
      const onPath = (bl.anc.has(cd) && bl.anc.has(cp)) || (inSubtree(sc, bl.node, cd) && Math.abs(sC - nd.s[bl.node]) <= 0.6);
      const dist = Math.abs(nd.s[bl.node] - sC);
      return { onPath, dist };
    }
    snapshot(extra) {
      const tip = this.tip();
      return Object.assign({
        sc: this.sc.params, p: this.path, f: this.f, phi: this.phi, carm: this.carm, mag: this.mag,
        cx: this.cam.x, cy: this.cam.y, coils: this.coils.map(c => [c.a, c.b, c.f, c.pct, c.rel ? 1 : 0]).concat(this.deploy ? [[this.deploy.a, this.deploy.b, this.deploy.f, this.deploy.pct, 0]] : []),
        rm: this.rm, bs: this.bleedSeen, stain: this.stain, cd: this.cfg.coilDist,
        run: this.run ? { id: this.run.id, a: this.run.inj.a, b: this.run.inj.b, f: this.run.inj.f, k: this.run.kind, t: this.run.t } : null,
        tip,
      }, extra || {});
    }
  }

  /* ═══════════════════════════ ACCESS DEVICE ═══════════════════════════ */
  const ACCESS = {
    femoral: { depth: 3.0, r: 0.4, vein: 1.25, veinR: 0.55, side: -1, speed: 0.6, bleed: 32, range: 2.2, aimSpeed: 0.9, view: 4.6 },
    radial: { depth: 0.65, r: 0.13, vein: 0.5, veinR: 0.12, side: 1, speed: 0.32, bleed: 11, range: 0.85, aimSpeed: 0.35, view: 1.3 },
  };

  /* ═══════════════════════════ NUI APP ═══════════════════════════ */
  const STEPS = 6;
  let A = null;                     // live procedure state
  const app = {
    escClose: false,
    modalKeys: true,
    // right-drag look-around / wheel zoom go to the game camera only while the wheel is free
    // (it aims the needle in 'aim' and drives the catheter in steps 2-5)
    get camInput() {
      if (!A || A.room || A.done) return false;
      if (A.step >= 2 && A.step <= 5) return false;
      return A.phase === 'aim' ? false : undefined;
    },
    init(el) {
      el.innerHTML = `
        <div class="ag-col">
          <div class="nza-hud ag-card ag-console">
            <div class="ag-h"><span class="ag-plate">CC-4</span><span class="nza-label" data-x="conTitle">Catheter console</span><span class="ag-xr" data-x="xr"><i></i><b data-x="xrl">X-RAY</b></span></div>
            <div class="ag-vit" data-x="vit"></div>
            <div class="ag-sec">
              <div class="ag-sl"><span data-x="tipLbl">Tip</span><span class="ag-sv" data-x="tipVal">0°</span></div>
              <div class="ag-tipwrap"><svg class="ag-compass" viewBox="-60 -60 120 120" data-x="compass"></svg><div class="ag-next" data-x="next"></div></div>
            </div>
            <div class="ag-sec">
              <div class="ag-sl"><span data-x="carmLbl">C-arm</span><span class="ag-sv" data-x="carmVal">AP</span></div>
              <div data-x="carmSeg"></div>
              <div data-x="carmSl" class="ag-slider"></div>
            </div>
            <div class="ag-sec ag-sup">
              <div><span class="nza-label" data-x="dyeLbl">Contrast</span><b data-x="dye">--</b><div class="mtr" data-x="dyeM"><i></i></div></div>
              <div><span class="nza-label" data-x="coilLbl">Coils</span><b data-x="coils">--</b><div class="ag-pips" data-x="pips"></div></div>
              <div><span class="nza-label" data-x="doseLbl">Dose</span><b data-x="dose">--</b><small data-x="fl">--</small></div>
            </div>
            <div class="ag-sec ag-view"><span class="nza-label" data-x="viewLbl">View</span><div data-x="viewSeg"></div></div>
            <div class="ag-sec ag-keys" data-x="keys"></div>
          </div>
          <div class="nza-hud ag-card ag-access">
            <div class="ag-h"><span class="ag-plate">US-2</span><span class="nza-label" data-x="accTitle">Access</span><span class="chipx sm teal" data-x="accChip">US-guided</span></div>
            <div class="ag-plan" data-x="plan"></div>
            <div class="ag-us"><canvas data-x="cvT"></canvas><span class="ag-cap" data-x="capT">Transverse</span></div>
            <div class="ag-us"><canvas data-x="cvL"></canvas><span class="ag-cap" data-x="capL">Longitudinal</span></div>
            <div class="ag-gauges">
              <div><span class="nza-label" data-x="g1l">Angle</span><b data-x="g1">45°</b><div data-x="g1m"></div></div>
              <div><span class="nza-label" data-x="g2l">Depth</span><b data-x="g2">0.0 cm</b><div data-x="g2m"></div></div>
              <div><span class="nza-label" data-x="g3l">Flash</span><b data-x="g3">--</b></div>
            </div>
          </div>
        </div>
        <div class="ag-screen" data-x="screen">
          <div class="dev ag-dev">
            <div class="ag-devtop"><span class="dev-brand"><span class="ag-plate">AX-3</span><span data-x="devName">Fluoroscopy monitor</span></span><span class="ag-devr"><span class="ag-sticker"><svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="2.2"/><path d="M12 9.2 8.6 3.3A10 10 0 0 0 3.2 12h6.6a2.3 2.3 0 0 1 2.2-2.8zM12 9.2l3.4-5.9A10 10 0 0 1 20.8 12h-6.6A2.3 2.3 0 0 0 12 9.2zM10.6 14.4l-3.3 5.8a10 10 0 0 0 9.4 0l-3.3-5.8a2.3 2.3 0 0 1-2.8 0z"/></svg></span><span class="dev-led" data-x="led"></span></span></div>
            <div class="dev-screen"><canvas data-x="fluoro"></canvas></div>
          </div>
        </div>
        <div class="nza-hud ag-result" data-x="result"></div>`;
      this.$ = {};
      el.querySelectorAll('[data-x]').forEach(n => { this.$[n.dataset.x] = n; });
    },
    open(data) { start(this, data || {}); },
    close() { stop(); },
    msg: {
      vitals(d) { if (A) onVitals(d); },
      room(d) { if (A) setRoom(!!(d && d.on), true); },
      pressed() { if (A) contrastRun(true); },
    },
    keys: {},
    keysUp: {},
    preview() { preview(); },
    demo(step) { demo(step); },
  };

  /* ── keys ── */
  const HOLD = ['KeyW', 'KeyS', 'KeyA', 'KeyD', 'KeyQ', 'KeyE', 'KeyF', 'Space', 'ShiftLeft', 'ShiftRight', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'];
  HOLD.forEach(code => {
    app.keys[code] = e => { if (!A) return false; A.held[code] = true; onPress(code, e); return true; };
    app.keysUp[code] = () => { if (!A) return false; A.held[code] = false; onRelease(code); return true; };
  });
  ['KeyR', 'KeyC', 'KeyZ', 'KeyV', 'KeyX', 'KeyB', 'KeyM', 'Digit1', 'Digit2', 'Digit3', 'Enter', 'Backspace'].forEach(code => {
    app.keys[code] = e => { if (!A) return false; onPress(code, e); return true; };
  });
  app.keys.Escape = () => !!A;   // owned by the ProcPanel hold-to-abort

  NZA.app('angio', app);

  /* ── helpers ── */
  const L = (k, fb) => { const v = A && A.loc ? A.loc[k] : undefined; return v !== undefined ? v : fb; };
  const F = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]|%\.1f/g, m => { const v = a[i++]; return m === '%.1f' ? Number(v).toFixed(1) : String(v); }); };
  const vesselLabel = v => {
    if (!v) return '--';
    const base = L(`vessel.${v.key}`, VESSEL_EN[v.key] || v.key);
    return v.side ? base.replace('%s', L(`side.${v.side}`, v.side === 'l' ? 'Left' : 'Right')) : base.replace('%s ', '').replace('%s', '');
  };
  const VESSEL_EN = {
    aorta_t: 'Descending aorta', aorta: 'Abdominal aorta', coeliac: 'Coeliac trunk', splenic: 'Splenic artery', splenic_h: 'Splenic branch',
    lgastric: 'Left gastric', chepatic: 'Common hepatic', gda: 'Gastroduodenal', phepatic: 'Proper hepatic', rhepatic: 'Right hepatic',
    rhep_b: 'Right hepatic branch', lhepatic: 'Left hepatic', sma: 'Superior mesenteric', mcolic: 'Middle colic', rcolic: 'Right colic',
    icolic: 'Ileocolic', jejunal: 'Jejunal arcade', ileal: 'Ileal arcade', renal: '%s renal', renal_s: '%s renal segment', ima: 'Inferior mesenteric',
    lcolic: 'Left colic', sigmoid: 'Sigmoid branch', srectal: 'Superior rectal', lumbar: '%s lumbar', cia: '%s common iliac', eia: '%s external iliac',
    cfa: '%s common femoral', sfa: '%s superficial femoral', sfa_m: '%s femoral muscular branch', pfa: '%s profunda femoris', pfa_p: '%s perforator',
    lcfx: '%s circumflex femoral', iia: '%s internal iliac', iliolumbar: '%s iliolumbar', latsacral: '%s lateral sacral', sglut: '%s superior gluteal',
    iia_ant: '%s anterior internal iliac', obt: '%s obturator', iglut: '%s inferior gluteal', ipud: '%s internal pudendal',
  };
  const ACCESS_EN = { femoral_r: 'Right femoral', femoral_l: 'Left femoral', radial: 'Right radial' };
  const ORGAN_EN = { spleen: 'Spleen', liver: 'Liver', kidney: 'Kidney', bowel: 'Small bowel', mesenteric: 'Mesentery', pelvic: 'Pelvis', femoral: 'Thigh', pelvis: 'Pelvic fracture', l_upper_leg: 'Left thigh fracture', r_upper_leg: 'Right thigh fracture' };
  const carmLabel = a => { const r = Math.round(a); if (Math.abs(r) < 3) return L('carm.ap', 'AP'); return r > 0 ? F(L('carm.lao', 'LAO %d°'), r) : F(L('carm.rao', 'RAO %d°'), -r); };
  const sfx = {
    whirr() { NZA.audio.tone(170, 1700, { vol: 0.05, type: 'sawtooth', slide: 230 }); NZA.audio.noise(1700, { vol: 0.03, lp: 600, hp: 90 }); },
    xray() { NZA.audio.noise(380, { vol: 0.025, lp: 5000, hp: 1800, attack: 0.1, release: 0.4 }); },
    flash() { NZA.audio.beep(980, 70, 0.08); NZA.audio.beep(1320, 90, 0.07); },
    tick() { NZA.audio.tick(); },
    coil() { NZA.audio.tone(2200, 30, { vol: 0.03, type: 'square' }); },
    thunk() { NZA.audio.tone(140, 160, { vol: 0.12, type: 'triangle', slide: 70 }); },
  };

  /* ═══════════════════════════ LIFECYCLE ═══════════════════════════ */
  function start(def, data) {
    stop();
    const d = data.data || data;
    const loc = data.locale || {};
    const cfg = Object.assign({
      budget: 100, coils: 1, bottles: 0, maxCoils: 6, coilDist: 2, holdTime: { femoral: 12, radial: 6 },
      runMl: 18, selectiveMl: 8, puffMl: 3, catheterSpeed: 4, parContrast: 45, parFluoro: 150,
    }, d);
    const scene = buildScene({ seed: d.seed || 7, key: (d.bleed && d.bleed.key) || 'jejunal', side: d.bleed && d.bleed.side, sev: (d.injury && d.injury.severity) || 2 });
    A = {
      def, $: def.$, loc, data: d, cfg, scene, sim: new Sim(scene, cfg), held: {}, t0: performance.now(), last: performance.now(),
      dui: !!data.dui, hasButton: !!data.hasButton, view: data.dui ? 'monitor' : 'screen', room: false,
      phase: 'choose', step: 1, access: null, acc: null, busy: false, done: false, lastInput: 0, wheel: 0, raf: 0,
      vitals: (d.patient && d.patient.vitals) || null, coilsLeft: Math.max(0, cfg.coils | 0), patient: d.patient || {},
      stats: { attempts: 0, angleErr: null, accessT: 0, hold: 0, holdIn: 0, over: 0 }, sendT: 0,
      bottles: Math.max(0, cfg.bottles | 0), budgetMax: cfg.budget, lastLabel: '', carmTarget: null, seal: null,
    };
    def.el.classList.toggle('ag-dui', A.dui);
    buildUi();
    A.fv = new FluoroView(def.$.fluoro, { locale: screenLocale() });
    A.pp = NZA.ui.ProcPanel(def.el, {
      step: 1, total: STEPS, tag: L('tag', 'Angiography'), title: L('s1.title', 'Get access'), text: '',
      steps: [L('s1.title', 'Get access'), L('s2.title', 'Navigate'), L('s3.title', 'Shoot the run'), L('s4.title', 'Pack the leak'), L('s5.title', 'Check the seal'), L('s6.title', 'Close the access')],
      stats: [], tools: [], hints: [],
      abort: { label: L('abort', 'Hold to cancel'), key: 'ESC', seconds: 1.2 },
      onAbort: () => { if (A && !A.done) { NZA.post('angio:abort', {}); } },
      onTool: k => onTool(k),
    });
    A.pp.el.classList.add('ag-pp');
    window.addEventListener('wheel', onWheel, { passive: true });
    setPhase('choose');
    A.raf = requestAnimationFrame(loop);
  }
  function stop() {
    if (!A) return;
    cancelAnimationFrame(A.raf);
    window.removeEventListener('wheel', onWheel);
    if (A.pp) A.pp.destroy();
    if (A.mon) A.mon.destroy();
    A.$.result.classList.remove('on');
    A = null;
  }
  function screenLocale() {
    const out = {};
    Object.keys(A.loc).forEach(k => { if (k.startsWith('screen.')) out[k] = A.loc[k]; });
    return out;
  }

  /* ── static UI ── */
  function buildUi() {
    const $ = A.$;
    $.xrl.textContent = L('ui.xray', 'X-RAY');
    $.conTitle.textContent = L('ui.console', 'Catheter console');
    $.tipLbl.textContent = L('ui.tip', 'Tip rotation');
    $.carmLbl.textContent = L('ui.carm', 'C-arm');
    $.dyeLbl.textContent = L('ui.contrast', 'Contrast');
    $.coilLbl.textContent = L('ui.coils', 'Coils');
    $.doseLbl.textContent = L('ui.dose', 'Dose');
    $.viewLbl.textContent = L('ui.view', 'View');
    $.devName.textContent = L('ui.device', 'Fluoroscopy monitor');
    $.capT.textContent = L('ui.transverse', 'Transverse');
    $.capL.textContent = L('ui.longitudinal', 'Longitudinal');
    $.accChip.textContent = L('ui.usGuided', 'US-guided');
    $.carmSeg.innerHTML = ''; $.carmSl.innerHTML = ''; $.viewSeg.innerHTML = ''; $.vit.innerHTML = '';
    A.carmSeg = NZA.ui.Segmented($.carmSeg, {
      options: [{ value: '-30', label: L('carm.rao30', 'RAO 30') }, { value: '0', label: L('carm.ap', 'AP') }, { value: '30', label: L('carm.lao30', 'LAO 30') }],
      value: '0', onChange: v => { A.carmTarget = Number(v); input(); },
    });
    A.carmSl = NZA.ui.Slider($.carmSl, { min: -45, max: 45, step: 1, value: 0, format: v => carmLabel(v), onChange: v => { A.sim.carm = v; A.carmTarget = null; input(); } });
    A.viewSeg = NZA.ui.Segmented($.viewSeg, {
      options: [{ value: 'monitor', label: L('ui.monitor', 'Monitor') }, { value: 'screen', label: L('ui.screen', 'Screen') }],
      value: A.view, onChange: v => setView(v),
    });
    if (!A.dui) A.viewSeg.el.classList.add('ag-disabled');
    A.mon = NZA.vitals.Monitor($.vit, { compact: true, traces: ['ecg'], height: 62, beep: false, title: (A.patient.name || '').toUpperCase() });
    if (A.vitals) A.mon.update(A.vitals);
    // gauges for access
    $.g1m.innerHTML = ''; $.g2m.innerHTML = '';
    A.g1 = NZA.ui.Meter($.g1m, { value: 0.5, zone: [0.444, 0.556], mark: 0.5, noFill: true });
    A.g2 = NZA.ui.Meter($.g2m, { value: 0 });
    updateSupplies();
  }

  function updateSupplies() {
    const $ = A.$, s = A.sim, c = A.cfg;
    const total = c.budget + 0;
    $.dye.textContent = `${Math.max(0, Math.round(s.left))} mL`;
    $.dyeM.querySelector('i').style.width = `${clamp(s.left / Math.max(1, A.budgetMax || total), 0, 1) * 100}%`;
    $.dyeM.classList.toggle('red', s.left < c.runMl);
    $.coils.textContent = String(A.coilsLeft);
    $.pips.innerHTML = Array.from({ length: Math.min(6, Math.max(A.coilsLeft, s.coils.length)) }, (_, i) => `<i class="${i < s.coils.length ? 'used' : ''}"></i>`).join('');
    $.dose.textContent = `${s.dose.toFixed(1)} mGy`;
    $.fl.textContent = `${L('ui.fl', 'FL')} ${fmtTime(s.fl)}`;
  }

  /* ═══════════════════════════ PHASES ═══════════════════════════ */
  // phase → [step, camera]
  const PHASE = {
    choose: [1, 'overview'], aim: [1, 'access'], wire: [1, 'access'], sheath: [1, 'access'], needle: [1, 'access'],
    nav: [2, 'monitor'], select: [3, 'monitor'], coil: [4, 'monitor'], confirm: [5, 'monitor'],
    pull: [6, 'access'], press: [6, 'access'], done: [6, 'access'],
  };
  function setPhase(ph, quiet) {
    const prev = A.phase;
    A.phase = ph;
    const [step, cam] = PHASE[ph];
    A.step = step;
    const accessUi = step === 1 || step === 6;
    A.def.el.classList.toggle('ag-accessmode', accessUi);
    A.def.el.classList.toggle('ag-navmode', !accessUi);
    A.def.el.classList.toggle('ag-showscreen', !accessUi && A.view === 'screen');
    A.def.el.classList.toggle('ag-choose', ph === 'choose');
    if (!quiet) NZA.post('angio:step', { phase: ph, step, cam: accessUi ? (ph === 'choose' ? 'overview' : 'access') : (A.view === 'screen' && !A.dui ? 'overview' : 'monitor'), access: A.access, view: A.view });
    if (ph === 'aim' && prev === 'choose') { const P = ACCESS[A.accKind]; A.acc = { aim: -P.side * P.range * 0.45, angle: 32, depth: 0, adv: 0, flash: null, wire: 0, sheath: 0, needle: 0, back: false, t0: performance.now() }; }
    if (ph === 'choose') renderPlan();
    // the coil is a few millimetres long: magnify the first time we get to it
    if (ph === 'coil' && !A.autoMag) { A.autoMag = true; setMag(MAG); }
    renderPanel();
    if (step === 6) renderAccessGauges();
  }

  /* step 1 planning card: where is it bleeding, which way in */
  function recommendAccess() {
    const k = A.scene.bleed.key, side = A.scene.bleed.side;
    if ((k === 'femoral' || k === 'profunda') && side) return { site: `femoral_${side}`, why: L('plan.whyAnte', 'Same-side groin, needle pointing down the leg: straight at the bleed.') };
    if (['iia', 'gluteal', 'obturator'].includes(k) && side) return { site: side === 'r' ? 'femoral_l' : 'femoral_r', why: L('plan.whyCross', 'Go in from the other groin and cross over the iliac fork.') };
    return { site: 'femoral_r', why: L('plan.whyStd', 'Right groin: the standard way up to the aorta and its branches.') };
  }
  function suspectLabel() {
    const inj = A.data.injury || {};
    const key = inj.type === 'fracture' ? inj.region : inj.organ;
    return L(`organ.${key}`, ORGAN_EN[key] || L('organ.unknown', 'Abdomen'));
  }
  function renderPlan() {
    const $ = A.$, sc = A.scene, rec = recommendAccess();
    A.rec = rec.site;
    const X = x => 60 + x * 1.9, Y = y => 62 + y * 1.55;
    const sites = {
      femoral_r: [X(-9.4), Y(28.6)], femoral_l: [X(9.4), Y(28.6)], radial: [21, 105],
    };
    const hold = A.cfg.holdTime || {};
    const notes = {
      femoral_r: F(L('plan.femoral', 'Big artery, easy to hit. %d s of pressure after.'), hold.femoral || 12),
      femoral_l: F(L('plan.femoral', 'Big artery, easy to hit. %d s of pressure after.'), hold.femoral || 12),
      radial: F(L('plan.radial', 'Small and fiddly, long way round. Closes in %d s.'), hold.radial || 6),
    };
    const bx = X(sc.bleed.x), by = Y(sc.bleed.y);
    const marks = Object.entries(sites).map(([k, [x, y]], i) => `
      <g class="ag-site ${k === rec.site ? 'rec' : ''}" data-site="${k}">
        <circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="8.6" class="halo"/>
        <circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="6" class="pin"/>
        <text x="${x.toFixed(1)}" y="${(y + 2.5).toFixed(1)}">${i + 1}</text>
      </g>`).join('');
    const inj = A.data.injury || {};
    $.plan.innerHTML = `
      <div class="ag-plan-top">
        <svg class="ag-body" viewBox="0 0 120 172" aria-hidden="true">
          <defs><radialGradient id="ag-bl"><stop offset="0" stop-color="#e5484d" stop-opacity=".75"/><stop offset="1" stop-color="#e5484d" stop-opacity="0"/></radialGradient></defs>
          <circle cx="60" cy="13" r="9" class="sil"/>
          <path class="sil" d="M53 21h14l1 6c9 1 16 3 19 7l6 22 6 34 3 18-6 2-5-17-5-28-3 14c2 9 3 17 3 25l-3 70H74l-5-62h-2l-1 0h-3l-5 62H44l-3-70c0-8 1-16 3-25l-3-14-5 28-5 17-6-2 3-18 6-34 6-22c3-4 10-6 19-7z"/>
          <path class="spine" d="M60 30v68"/>
          <circle cx="${bx.toFixed(1)}" cy="${by.toFixed(1)}" r="13" fill="url(#ag-bl)" class="bleed"/>
          <circle cx="${bx.toFixed(1)}" cy="${by.toFixed(1)}" r="2.4" class="bleed-dot"/>
          <text x="6" y="168" class="side">${esc(L('dir.r', 'R'))}</text><text x="108" y="168" class="side">${esc(L('dir.l', 'L'))}</text>
          ${marks}
        </svg>
        <div class="ag-sus">
          <span class="nza-label">${esc(L('plan.suspect', 'Suspected source'))}</span>
          <b>${esc(suspectLabel())}</b>
          <small>${esc(F(L('plan.bleed', '%s mL/min · severity %d/4'), Number(inj.bleed || 0).toFixed(0), inj.severity || 2))}</small>
          <span class="nza-label ag-rl">${esc(L('plan.rec', 'Recommended'))}</span>
          <b class="t-teal">${esc(L(`acc.${rec.site}`, ACCESS_EN[rec.site]))}</b>
          <small>${esc(rec.why)}</small>
        </div>
      </div>
      <div class="ag-opts">${Object.keys(sites).map((k, i) => `
        <button class="ag-opt ${k === rec.site ? 'rec' : ''}" data-site="${k}"><kbd>${i + 1}</kbd><span><b>${esc(L(`acc.${k}`, ACCESS_EN[k]))}</b><small>${esc(notes[k])}</small></span>${k === rec.site ? `<i>${esc(L('plan.best', 'Best'))}</i>` : ''}</button>`).join('')}
      </div>`;
    $.plan.querySelectorAll('[data-site]').forEach(n => n.addEventListener('click', () => { if (A && A.phase === 'choose') chooseAccess(n.dataset.site); }));
  }

  function stepText() {
    const ph = A.phase, s = A.sim;
    const gateName = vesselLabel(A.scene.vessels[A.scene.bleed.gate]);
    switch (ph) {
      case 'choose': return [L('s1.title', 'Get access'), L('s1.choose', 'Pick the way in. {1} right groin, {2} left groin, {3} right wrist.')];
      case 'aim': return [L('s1.needle', 'Needle in'), A.acc && A.acc.flash === 'venous' ? L('s1.venous', 'Dark, slow blood: that is the vein. Pull back with {S} and aim over the pulse.') : A.acc && A.acc.back ? L('s1.back', 'Through the back wall. Pull back slowly with {S} until the flash returns.') : L('s1.aim', 'Aim over the pulsing artery with {A}/{D}, set {Q}/{E} to **45°**, hold {W} until you see flashback.')];
      case 'wire': return [L('s1.wire', 'Feed the wire'), L('s1.wireT', 'Hold {W} to feed the guide wire through the needle. Stop if it fights you.')];
      case 'sheath': return [L('s1.sheath', 'Slide the sheath'), L('s1.sheathT', 'Hold {E} to slide the sheath over the wire into the artery.')];
      case 'needle': return [L('s1.remove', 'Withdraw the needle'), L('s1.removeT', 'The sheath is in the artery. Tap {R} to draw the needle back out of it.')];
      case 'nav': return [L('s2.title', 'Navigate'), F(L('s2.text', 'Get the catheter into the **%s**. {W}/{S} advance, {A}/{D} turn the tip at a branch. {X} puff, {C} contrast run.'), gateName)];
      case 'select': return [L('s3.title', 'Shoot the run'), A.hasButton ? L('s3.textBtn', 'Tip in place. Hit the red pedal button ({Z} to walk over) or {C}, then follow the dye on the monitor.') : L('s3.text', 'Tip in place. Press {C} to inject contrast and follow the dye on the monitor.')];
      case 'coil': {
        if (s.deploy && s.deploy.pct >= 100) return [L('s4.title', 'Pack the leak'), L('s4.out', 'The coil is fully out of the tip. {F} detaches it, {R} backs the catheter off.')];
        if (A.released) return [L('s4.title', 'Pack the leak'), L('s4.placed', 'Coil detached. {R} backs the catheter off, then check the seal.')];
        return [L('s4.title', 'Pack the leak'), F(L('s4.text', 'Steer the tip to within **%s cm** of the leak, then hold {F} to feed the coil out.'), A.cfg.coilDist)];
      }
      case 'confirm': return [L('s5.title', 'Check the seal'), A.hasButton ? L('s5.textBtn', 'Inject again: red pedal button ({Z}) or {C}. No contrast pooling means it is sealed.') : L('s5.text', 'Inject again with {C}. No contrast pooling means it is sealed.')];
      case 'pull': return [L('s6.title', 'Close the access'), L('s6.pull', 'Slide the sheath out. Tap {R}.')];
      case 'press': return [L('s6.title', 'Close the access'), L('s6.press', 'Hold {Space} to press on the puncture. Keep the pressure in the band.')];
      case 'done': return [L('done.title', 'Leak sealed'), ''];
    }
    return ['', ''];
  }

  // the overlay has no focus while walking: only the keys the game reads are shown
  function roomPanel() {
    A.pp.set({
      title: L('room.title', 'Walk to the pedal'), text: A.hasButton ? L('room.text', 'Walk to the red pedal button and press {E}. {Z} takes you back to the console.') : '',
      tools: [{ key: 'E', label: L('t.button', 'Pedal button'), icon: 'target', state: 'active' }, { key: 'Z', label: L('t.monitor', 'Back to console'), icon: 'monitor' }],
      hints: [], abort: false,
    });
    renderStats();
  }
  function renderPanel() {
    if (!A || !A.pp) return;
    if (A.room) return roomPanel();
    const [title, text] = stepText();
    const ph = A.phase;
    const tools = [];
    const hints = [];
    const s = A.sim;
    if (ph === 'choose') {
      tools.push({ key: '1', label: L('acc.femoral_r', 'Right femoral'), sub: L('acc.groin', 'groin'), icon: 'target' });
      tools.push({ key: '2', label: L('acc.femoral_l', 'Left femoral'), sub: L('acc.groin', 'groin'), icon: 'target' });
      tools.push({ key: '3', label: L('acc.radial', 'Right radial'), sub: L('acc.wrist', 'wrist'), icon: 'hand' });
    } else if (A.step === 1) {
      tools.push({ key: 'W', label: L('t.needle', 'Needle'), state: ph === 'aim' ? 'active' : 'done', icon: 'needle' });
      tools.push({ key: 'W', label: L('t.wire', 'Wire'), state: ph === 'wire' ? 'active' : (['sheath', 'needle'].includes(ph) ? 'done' : 'locked'), icon: 'tube' });
      tools.push({ key: 'E', label: L('t.sheath', 'Sheath'), state: ph === 'sheath' ? 'active' : (ph === 'needle' ? 'done' : 'locked'), icon: 'iv' });
      tools.push({ key: 'R', label: L('t.remove', 'Withdraw needle'), state: ph === 'needle' ? 'active' : 'locked', icon: 'arrow-up' });
      if (ph === 'aim') hints.push({ keys: ['A', 'D'], label: L('h.aim', 'aim') }, { keys: ['Q', 'E'], label: L('h.angle', 'angle') }, { keys: ['Shift'], label: L('h.faster', 'faster') });
      else if (ph === 'wire') hints.push({ keys: ['Q'], label: L('h.flatten', 'flatten') });
      if (ph !== 'aim' && NZA.inGame) hints.push({ keys: ['RMB'], label: L('h.look', 'orbit') });
    } else if (A.step === 6) {
      tools.push({ key: 'R', label: L('t.sheathOut', 'Remove sheath'), state: ph === 'pull' ? 'active' : 'done', icon: 'arrow-up' });
      tools.push({ key: 'Space', label: L('t.pressure', 'Pressure'), state: ph === 'press' ? 'active' : (ph === 'done' ? 'done' : 'locked'), icon: 'hand' });
      if (NZA.inGame) hints.push({ keys: ['RMB'], label: L('h.look', 'orbit') });
    } else {
      const dyeOut = s.left < A.cfg.selectiveMl;
      tools.push({ key: 'C', label: L('t.run', 'Inject'), sub: `${A.cfg.selectiveMl}–${A.cfg.runMl} mL`, icon: 'flask', state: ph === 'select' || ph === 'confirm' ? 'active' : (dyeOut ? 'need' : '') });
      tools.push({ key: 'X', label: L('t.puff', 'Test puff'), sub: `${A.cfg.puffMl} mL`, icon: 'syringe', state: dyeOut ? 'need' : '' });
      if (ph === 'coil' || ph === 'confirm') tools.push({ key: 'F', label: s.deploy && s.deploy.pct >= 100 ? L('t.release', 'Detach coil') : L('t.coil', 'Feed coil'), icon: 'spring', state: ph === 'coil' && !A.released ? 'active' : '', count: String(A.coilsLeft) });
      if (ph === 'coil') tools.push({ key: 'R', label: L('t.pull', 'Back off'), icon: 'arrow-down', state: A.released ? 'active' : '' });
      if (A.hasButton) tools.push({ key: 'Z', label: L('t.room', 'Walk to button'), icon: 'walk' });
      if (dyeOut && A.bottles > 0) tools.push({ key: 'B', label: L('t.bottle', 'New bottle'), icon: 'bottle', state: 'need', count: String(A.bottles) });
      renderKeys();
    }
    A.pp.set({ step: A.step, title, text, tools, hints, titleTone: ph === 'done' ? 'ok' : '' });
    renderStats();
  }

  // catheter controls live in the console card (the panel row keeps the actions)
  function renderKeys() {
    const rows = [
      [['W', 'S'], L('h.advance', 'advance')], [['A', 'D'], L('h.rotate', 'turn tip')],
      [['Q', 'E'], L('h.carm', 'C-arm')], [['M'], A.sim.mag > 1 ? L('h.unmag', 'full view') : L('h.mag', 'magnify')],
      [['Shift'], L('h.faster', 'faster')], [['Wheel'], L('h.fine', 'fine advance')],
    ];
    if (A.dui) rows.push([['V'], L('h.view', 'monitor / screen')]);
    const html = rows.map(([k, t]) => `<span>${k.map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(t)}</em></span>`).join('');
    if (A.$.keys.innerHTML !== html) A.$.keys.innerHTML = html;
  }

  function renderStats() {
    if (!A || !A.pp) return;
    const s = A.sim;
    if (A.phase === 'choose') {
      const inj = A.data.injury || {};
      const b = Number(inj.bleed || 0);
      A.pp.set({
        stats: [
          { id: 'src', label: L('plan.suspect', 'Suspected source'), value: suspectLabel(), small: true },
          { id: 'bleed', label: L('st.bleed', 'Bleed'), value: b.toFixed(0), unit: 'mL/min', tone: b >= 30 ? 'red' : '' },
        ],
        wide: { label: L('plan.rec', 'Recommended'), value: L(`acc.${A.rec || 'femoral_r'}`, ACCESS_EN[A.rec || 'femoral_r']), meter: null, caption: '' },
      });
      return;
    }
    A.roKey = '';
    if (A.step === 1 || A.step === 6) {
      const acc = A.acc || {};
      const stats = [
        { id: 'site', label: L('st.site', 'Site'), value: L(`acc.${A.access || 'femoral_r'}`, ACCESS_EN[A.access || 'femoral_r']), small: true },
        { id: 'tries', label: L('st.tries', 'Attempts'), value: String(A.stats.attempts + 1) },
      ];
      if (A.step === 6) {
        const pr = A.press || {};
        stats[1] = { id: 'bleed', label: L('st.siteBleed', 'Site bleed'), value: (pr.bleed ?? 0).toFixed(1), unit: 'mL/min', tone: (pr.bleed ?? 0) > 3 ? 'red' : 'teal' };
        A.pp.set({ stats, wide: { label: L('st.pressure', 'Pressure'), value: `${Math.round((pr.p || 0) * 100)}`, unit: '%', meter: { value: pr.p || 0, zone: [0.55, 0.8], mark: pr.p || 0, tone: (pr.p || 0) > 0.9 ? 'red' : '' }, caption: A.phase === 'done' ? L('st.closed', 'Access closed') : F(L('st.holdLeft', 'Hold %s s more'), Math.max(0, Math.ceil((pr.need || 0) - (pr.held || 0)))), captionTone: 'teal' } });
      } else {
        const prog = A.phase === 'wire' ? acc.wire : A.phase === 'sheath' ? acc.sheath : A.phase === 'needle' ? acc.needle : (acc.flash === 'arterial' ? 1 : 0);
        A.pp.set({ stats, wide: A.phase === 'choose' ? null : { label: L(`prog.${A.phase}`, { aim: 'Needle', wire: 'Wire', sheath: 'Sheath', needle: 'Needle out' }[A.phase] || ''), value: `${Math.round((prog || 0) * 100)}`, unit: '%', meter: { value: prog || 0, tone: A.phase === 'needle' ? 'white' : '' } } });
      }
      return;
    }
    // the distance to the leak lives on the image only (gap ring round the LEAK tag, see FluoroView);
    // the panel reads the seal (leak flow drop measured on the last run) and the supplies
    const gap = leakGap();
    const v = s.vessel();
    const seal = A.seal;
    const packed = s.coils.length, kit = packed + Math.max(0, A.coilsLeft | 0);
    const ml = Math.max(0, Math.round(s.left));
    const sealed = seal !== null && seal >= 100;
    const key = `${gap.near ? 1 : 0}|${v ? v.idx : -1}|${seal}|${ml}|${packed}|${A.coilsLeft}|${A.bleedCaption || ''}`;
    if (key === A.roKey) return;
    A.roKey = key;
    A.pp.set({
      wide: { label: L('st.seal', 'Seal'), value: seal === null ? '--' : String(seal), unit: seal === null ? '' : '%', tone: sealed ? 'teal' : seal > 0 ? 'amber' : '',
        meter: { value: (seal || 0) / 100, zone: [0.95, 1], tone: sealed ? '' : 'amber' }, caption: A.bleedCaption || '', captionTone: sealed ? 'teal' : 'red' },
      stats: [
        { id: 'vessel', label: L('st.vessel', 'Vessel'), value: vesselLabel(v), small: true, tone: gap.near ? 'teal' : '' },
        { id: 'dye', label: L('st.dyeLeft', 'Contrast left'), value: String(ml), unit: 'mL', tone: ml < A.cfg.selectiveMl ? 'red' : ml < A.cfg.runMl ? 'amber' : '' },
        { id: 'packed', label: L('st.packed', 'Coils packed'), value: `${packed}/${kit}`, tone: sealed ? 'teal' : A.coilsLeft ? '' : 'red' },
      ],
    });
  }
  // tree distance tip → leak, for the gap ring on the image: { d, near, feeds, span }
  function leakGap() {
    const tb = A.sim.toBleed();
    const d = Math.max(0, tb.d);
    return { d, near: !!tb.feeds && d <= A.cfg.coilDist, feeds: !!tb.feeds, span: Math.max(4, A.startDist || 30) };
  }

  /* ═══════════════════════════ INPUT ═══════════════════════════ */
  function input() { A.lastInput = performance.now(); }
  function onWheel(e) {
    if (!A || A.room || NZA.stack[NZA.stack.length - 1] !== 'angio') return;
    if (A.step === 1 && A.phase === 'aim') { A.acc.angle = clamp(A.acc.angle - Math.sign(e.deltaY) * 2, 15, 80); input(); return; }
    if (A.step >= 2 && A.step <= 5) { A.wheel += -Math.sign(e.deltaY) * 0.6; input(); }
  }
  function onPress(code, e) {
    const ph = A.phase;
    if (A.done) { if (code === 'Enter') finish(); return; }
    if (ph === 'choose') {
      if (code === 'Digit1') chooseAccess('femoral_r');
      if (code === 'Digit2') chooseAccess('femoral_l');
      if (code === 'Digit3') chooseAccess('radial');
      return;
    }
    if (code === 'KeyR') {
      if (ph === 'needle') { A.acc.needle = clamp(A.acc.needle + 0.12, 0, 1); sfx.tick(); if (A.acc.needle >= 1) needleOut(); renderStats(); }
      else if (ph === 'pull') { A.press.pull = clamp(A.press.pull + 0.14, 0, 1); sfx.tick(); if (A.press.pull >= 1) sheathOut(); renderStats(); }
      else if (ph === 'coil' && A.released) pullBack();
      else if (ph === 'coil' || ph === 'nav' || ph === 'select' || ph === 'confirm') { A.pullAnim = { left: 1.0 }; input(); }
      return;
    }
    if (A.step >= 2 && A.step <= 5) {
      if (code === 'KeyC') contrastRun(false);
      else if (code === 'KeyX') puff();
      else if (code === 'KeyZ' && A.hasButton) setRoom(true);
      else if (code === 'KeyV' && A.dui) setView(A.view === 'monitor' ? 'screen' : 'monitor');
      else if (code === 'KeyB') refill();
      else if (code === 'KeyF') coilPress();
      else if (code === 'KeyM') { setMag(A.sim.mag > 1 ? 1 : MAG); input(); }
    }
  }
  const MAG = 1.6;
  function setMag(m) {
    if (!A) return;
    A.sim.mag = m;
    sfx.tick();
    renderPanel();
  }
  function onRelease(code) {
    if (code === 'KeyF' && A.sim.deploy && A.sim.deploy.pct < 100) A.pp.flash('warn', L('f.coilHalf', 'Coil half out. Keep holding {F}, or {S} draws it back in.'), 2200);
  }
  function onTool(k) {
    if (!A) return;
    const map = { 1: 'Digit1', 2: 'Digit2', 3: 'Digit3', C: 'KeyC', X: 'KeyX', Z: 'KeyZ', R: 'KeyR', B: 'KeyB', F: 'KeyF', V: 'KeyV', M: 'KeyM' };
    if (map[k]) onPress(map[k]);
  }

  /* ═══════════════════════════ STEP 1 · ACCESS ═══════════════════════════ */
  function chooseAccess(key) {
    A.access = key;
    A.accKind = key === 'radial' ? 'radial' : 'femoral';
    A.sim.setAccess(key);
    A.$.accTitle.textContent = `${L('ui.access', 'Access')} · ${L(`acc.${key}`, ACCESS_EN[key])}`;
    const sc = A.scene;
    const crossOK = !(['iia', 'gluteal', 'obturator', 'femoral', 'profunda'].includes(sc.bleed.key)) || key === 'radial' || A.sim.antegrade || (sc.bleed.side && key !== `femoral_${sc.bleed.side}`);
    setPhase('aim');
    if (A.sim.antegrade) A.pp.flash('ok', L('f.antegrade', 'Antegrade puncture: the sheath points down the leg, straight at the bleed.'), 3600);
    else if (!crossOK) A.pp.flash('warn', L('f.ipsi', 'Same side as the bleed: you will have to turn back down at the iliac fork.'), 3600);
    NZA.post('angio:say', { line: 'scratch' });
  }
  function needleOut() {
    if (A.acc.out) return;
    A.acc.out = true;
    A.pp.flash('ok', L('f.portIn', 'Needle out. The sheath holds the way in.'), 2400);
    sfx.thunk();
    const acc = A.acc;
    const angErr = Math.abs((acc.flashAngle ?? acc.angle) - 45);
    A.stats.angleErr = angErr;
    A.stats.accessT = (performance.now() - acc.t0) / 1000;
    NZA.post('angio:step', { phase: 'needleOut', step: 1, cam: 'access', access: A.access });
    setTimeout(() => {
      if (!A) return;
      A.startDist = Math.max(4, A.sim.toBleed().d);
      setPhase('nav');
      A.pp.flash('ok', L('f.flushFirst', 'Tip: a contrast run from the aorta maps every vessel.'), 4200);
    }, 900);
  }

  function updateAccess(dt) {
    const acc = A.acc; if (!acc) return;
    const P = ACCESS[A.accKind];
    const h = A.held;
    if (A.phase === 'aim') {
      const shallow = acc.depth < P.depth * 0.3;
      const steer = (h.KeyD || h.ArrowRight ? 1 : 0) - (h.KeyA || h.ArrowLeft ? 1 : 0);
      if (steer && shallow) acc.aim = clamp(acc.aim + steer * dt * P.aimSpeed, -P.range, P.range);
      else if (steer && !acc.lockWarned) { acc.lockWarned = true; A.pp.flash('warn', L('f.aimLock', 'Pull back to the skin before you re-aim.'), 2000); }
      if (!steer) acc.lockWarned = false;
      acc.angle = clamp(acc.angle + ((h.KeyE ? 1 : 0) - (h.KeyQ ? 1 : 0)) * dt * 22, 15, 80);
      const adv = (h.KeyW || h.ArrowUp ? 1 : 0) - (h.KeyS || h.ArrowDown ? 1 : 0);
      if (adv) {
        const speed = P.speed * ((h.ShiftLeft || h.ShiftRight) ? 1.8 : 1);
        acc.adv = clamp(acc.adv + adv * speed * dt, 0, 8);
        acc.depth = acc.adv * Math.sin(acc.angle * DEG);
      }
      // what does the tip sit in?
      const dA = Math.abs(acc.aim);                       // lateral miss from the artery centre (cm)
      const dV = Math.abs(acc.aim - P.vein * P.side);     // ...and from the vein
      const inArtery = dA < P.r * 1.1 && acc.depth > P.depth - P.r && acc.depth < P.depth + P.r;
      const inVein = dV < P.veinR && acc.depth > P.depth - P.veinR && acc.depth < P.depth + P.veinR;
      const past = dA < P.r * 1.1 && acc.depth >= P.depth + P.r;
      const prev = acc.flash;
      if (inArtery) { acc.flash = 'arterial'; if (acc.back) { acc.back = false; } }
      else if (inVein) acc.flash = 'venous';
      else acc.flash = null;
      if (past && !acc.back) { acc.back = true; A.stats.attempts++; A.pp.flash('bad', L('f.back', 'Through the back wall.'), 2200); NZA.post('angio:say', { line: 'ow' }); renderPanel(); }
      if (acc.flash === 'venous' && prev !== 'venous') { A.stats.attempts++; A.pp.flash('warn', L('f.venous', 'Venous blood. Wrong vessel.'), 2400); renderPanel(); }
      if (acc.flash === 'arterial' && prev !== 'arterial') { sfx.flash(); acc.flashAngle = acc.angle; A.pp.flash('ok', L('f.flash', 'Flashback! Bright, pulsing blood. Hold still.'), 1800); }
      if (!acc.flash && acc.depth > P.depth + 1.6 && !acc.deepWarned) { acc.deepWarned = true; A.pp.flash('warn', L('f.deep', 'Too deep and nothing. Pull back and re-aim.'), 2400); }
      if (acc.depth < 0.3) acc.deepWarned = false;
      // stable flash for a moment → wire step
      if (acc.flash === 'arterial' && !adv) { acc.still = (acc.still || 0) + dt; if (acc.still > 0.6) { setPhase('wire'); } } else acc.still = 0;
      if (prev !== acc.flash) renderPanel();
    } else if (A.phase === 'wire') {
      acc.angle = clamp(acc.angle + ((h.KeyE ? 1 : 0) - (h.KeyQ ? 1 : 0)) * dt * 12, 15, 80);
      if (h.KeyW || h.ArrowUp) {
        if (acc.angle > 62 && acc.wire > 0.12) { if (!acc.resist) { acc.resist = true; A.pp.flash('warn', L('f.resist', 'The wire fights you: too steep. Flatten the needle with {Q}.'), 2600); } }
        else { acc.resist = false; acc.wire = clamp(acc.wire + dt / 2.4, 0, 1); }
        if (acc.wire >= 1) { sfx.tick(); setPhase('sheath'); }
      }
    } else if (A.phase === 'sheath') {
      if (h.KeyE) { acc.sheath = clamp(acc.sheath + dt / 2.0, 0, 1); if (acc.sheath >= 1) { sfx.thunk(); setPhase('needle'); } }
    } else if (A.phase === 'needle') {
      acc.needle = clamp(acc.needle - dt * 0.05, 0, 1);
    }
    renderAccessGauges();
  }
  function renderAccessGauges() {
    const acc = A.acc || {}, $ = A.$;
    const ang = acc.angle ?? 45;
    $.g1.textContent = `${Math.round(ang)}°`;
    $.g1.className = Math.abs(ang - 45) <= 5 ? 't-teal' : (Math.abs(ang - 45) > 15 ? 't-amber' : '');
    A.g1.set({ value: 0.5, mark: (ang - 15) / 65, zone: [(40 - 15) / 65, (50 - 15) / 65] });
    const P = ACCESS[A.accKind || 'femoral'];
    $.g2.textContent = `${(acc.depth || 0).toFixed(1)} cm`;
    A.g2.set({ value: clamp((acc.depth || 0) / (P.depth * 1.8), 0, 1), zone: [(P.depth - P.r) / (P.depth * 1.8), (P.depth + P.r) / (P.depth * 1.8)] });
    const fl = acc.flash === 'arterial' ? L('ui.flashArt', 'Pulsatile') : acc.flash === 'venous' ? L('ui.flashVen', 'Venous') : '--';
    $.g3.textContent = fl;
    $.g3.className = acc.flash === 'arterial' ? 't-teal' : acc.flash === 'venous' ? 't-amber' : '';
    if (A.step === 6 && A.press) {
      const pr = A.press;
      $.g1l.textContent = L('st.pressure', 'Pressure'); $.g1.textContent = `${Math.round(pr.p * 100)}%`;
      $.g1.className = pr.p > 0.9 ? 't-amber' : (pr.p >= 0.55 && pr.p <= 0.8 ? 't-teal' : '');
      A.g1.set({ value: pr.p, mark: pr.p, zone: [0.55, 0.8], noFill: false });
      $.g2l.textContent = L('st.siteBleed', 'Site bleed'); $.g2.innerHTML = `${pr.bleed.toFixed(1)}<span class="u">mL/min</span>`;
      A.g2.set({ value: clamp(pr.bleed / ACCESS[A.accKind].bleed, 0, 1), zone: null, tone: 'red' });
      $.g3l.textContent = L('st.held', 'Held'); $.g3.textContent = `${Math.floor(pr.held)}/${pr.need} s`; $.g3.className = 't-teal';
      return;
    }
    $.g1l.textContent = L('ui.angle', 'Angle');
    $.g2l.textContent = L('ui.depth', 'Depth'); $.g3l.textContent = L('ui.flash', 'Flash');
  }

  /* ultrasound-style access views (transverse + longitudinal) */
  function usTissue(g, w, h, skinY, pxcm, P, now, key) {
    if (!A.usNoise) A.usNoise = makeNoise(160);
    if (!A.usLines) A.usLines = {};
    if (!A.usLines[key]) {
      const R = rng(key === 'T' ? 91 : 173);
      const lines = [];
      for (let i = 0; i < 18; i++) lines.push({ y: 0.05 + R() * 0.9, x: R(), l: 0.12 + R() * 0.35, a: 0.05 + R() * 0.12, t: 0.6 + R() * 1.0 });
      A.usLines[key] = lines;
    }
    g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
    // speckle (grainy grey tissue), re-seeded a few times a second like a live probe
    g.save();
    g.beginPath(); g.rect(0, skinY, w, h - skinY); g.clip();
    g.globalAlpha = 0.62;
    const off = (Math.floor(now / 110) % 6) * 23 + (key === 'T' ? 0 : 61);
    g.translate(-off, -off * 0.7); g.scale(1.6, 1.25);
    g.fillStyle = g.createPattern(A.usNoise, 'repeat'); g.fillRect(off / 1.6, off * 0.7 / 1.25, w, h);
    g.restore();
    // time-gain: bright near the probe, fading with depth
    g.save();
    g.globalCompositeOperation = 'multiply';
    const tg = g.createLinearGradient(0, skinY, 0, h);
    tg.addColorStop(0, '#d8dcdd'); tg.addColorStop(0.35, '#9ea3a5'); tg.addColorStop(1, '#3c3f40');
    g.fillStyle = tg; g.fillRect(0, skinY, w, h - skinY);
    g.restore();
    // fibrous septa / muscle fibres
    A.usLines[key].forEach(l => {
      const y = skinY + l.y * (h - skinY);
      g.strokeStyle = `rgba(230,234,236,${l.a})`; g.lineWidth = l.t;
      g.beginPath(); g.moveTo(l.x * w - l.l * w * 0.5, y); g.quadraticCurveTo(l.x * w, y + 2, l.x * w + l.l * w * 0.5, y - 1); g.stroke();
    });
    // fascia planes
    [P.depth * 0.42, P.depth * 1.6].forEach((d, i) => {
      const y = skinY + d * pxcm;
      if (y > h) return;
      g.strokeStyle = `rgba(236,240,242,${i ? 0.3 : 0.42})`; g.lineWidth = i ? 1.3 : 1.8;
      g.beginPath(); g.moveTo(0, y + 3); g.bezierCurveTo(w * 0.3, y - 3, w * 0.6, y + 4, w, y - 2); g.stroke();
    });
    // probe gel + skin
    g.fillStyle = '#000'; g.fillRect(0, 0, w, skinY);
    g.strokeStyle = 'rgba(255,255,255,.8)'; g.lineWidth = 2; g.beginPath(); g.moveTo(0, skinY); g.lineTo(w, skinY); g.stroke();
  }
  // anechoic lumen with a bright wall and posterior acoustic enhancement
  function usVessel(g, x, y, rx, ry, wall, h) {
    const enh = g.createLinearGradient(0, y, 0, h);
    enh.addColorStop(0, 'rgba(255,255,255,.10)'); enh.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = enh; g.fillRect(x - rx, y, rx * 2, h - y);
    g.fillStyle = '#010202'; g.beginPath(); g.ellipse(x, y, Math.max(1, rx), Math.max(0.6, ry), 0, 0, TAU); g.fill();
    g.strokeStyle = `rgba(240,244,246,${wall})`; g.lineWidth = 2.2; g.stroke();
  }
  function drawAccess(now) {
    const $ = A.$;
    const P = ACCESS[A.accKind || 'femoral'];
    const acc = A.acc || { aim: 0, angle: 45, depth: 0, adv: 0 };
    const hr = (A.vitals && A.vitals.hr) || 96;
    const beat = Math.pow(Math.max(0, Math.sin((now / 1000) * TAU * hr / 60)), 6);
    const pr = A.step === 6 ? (A.press || { p: 0, pull: 0, bleed: 0 }) : null;
    const comp = pr ? pr.p : 0;
    const view = P.view;
    // transverse (short axis): aim left / right over the artery
    {
      const cv = $.cvT, g = cv.getContext('2d');
      const { w, h, scale } = NZA.fitCanvas(cv);
      g.setTransform(1, 0, 0, 1, 0, 0);
      const skinY = h * 0.07;
      const pxcm = (h - skinY) / view;
      usTissue(g, w, h, skinY, pxcm, P, now, 'T');
      const cx = w / 2;
      const ay = skinY + P.depth * pxcm;
      const vr = P.veinR * pxcm;
      const vSquash = clamp(1 - comp * 1.6 - (acc.aim !== undefined && Math.abs(acc.aim - P.vein * P.side) < P.veinR * 1.4 && acc.depth > 0.1 ? 0.25 : 0), 0.12, 1);
      usVessel(g, cx + P.vein * P.side * pxcm, ay + P.r * 0.25 * pxcm, vr * 1.2, vr * 0.85 * vSquash, 0.5, h);
      const ar = P.r * pxcm * (1 + beat * 0.08);
      usVessel(g, cx, ay, ar * (1 + comp * 0.3), ar * clamp(1 - comp * 0.85, 0.1, 1), 0.7 + beat * 0.3, h);
      g.font = `700 ${9 * scale}px Lexend, sans-serif`; g.textAlign = 'center';
      g.fillStyle = 'rgba(255,255,255,.6)'; g.fillText(L('ui.artery', 'A'), cx, ay - ar - 6 * scale);
      g.fillText(L('ui.vein', 'V'), cx + P.vein * P.side * pxcm, ay - vr - 4 * scale);
      g.textAlign = 'left';
      if (A.step === 1) {
        const nx = cx + acc.aim * pxcm;
        const onA = Math.abs(acc.aim) < P.r * 1.1;
        const onV = Math.abs(acc.aim - P.vein * P.side) < P.veinR;
        g.strokeStyle = onA ? 'rgba(15,212,196,.85)' : onV ? 'rgba(242,179,61,.85)' : 'rgba(255,255,255,.45)';
        g.setLineDash([3 * scale, 4 * scale]); g.lineWidth = 1.2 * scale;
        g.beginPath(); g.moveTo(nx, skinY); g.lineTo(nx, h); g.stroke(); g.setLineDash([]);
        // probe marker on the skin
        g.fillStyle = g.strokeStyle; g.beginPath(); g.moveTo(nx - 5 * scale, 2); g.lineTo(nx + 5 * scale, 2); g.lineTo(nx, skinY - 1); g.closePath(); g.fill();
        if (acc.depth > 0.02 && acc.needle < 1) {
          const ty = skinY + acc.depth * pxcm;
          // needle tip: bright dot with a reverberation tail
          for (let i = 1; i < 5; i++) { g.fillStyle = `rgba(255,255,255,${0.22 - i * 0.04})`; g.fillRect(nx - 2.5 * scale, ty + i * 4 * scale, 5 * scale, 1.5 * scale); }
          g.fillStyle = '#fff'; g.beginPath(); g.arc(nx, ty, 3 * scale, 0, TAU); g.fill();
        }
      }
      // depth scale
      g.fillStyle = 'rgba(255,255,255,.4)'; g.font = `500 ${8 * scale}px "JetBrains Mono", monospace`;
      const stepCm = view > 2 ? 1 : 0.25;
      for (let d = stepCm; d < view; d += stepCm) { const y = skinY + d * pxcm; g.fillRect(w - 7 * scale, y, 5 * scale, 1); }
      g.fillText(`${view.toFixed(view > 2 ? 0 : 1)} cm`, w - 34 * scale, h - 6 * scale);
    }
    // longitudinal (long axis): the needle angle, flashback, wire, sheath, pressure
    {
      const cv = $.cvL, g = cv.getContext('2d');
      const { w, h, scale } = NZA.fitCanvas(cv);
      g.setTransform(1, 0, 0, 1, 0, 0);
      const skinY = h * 0.24;
      const pxcm = (h - skinY) / view;
      usTissue(g, w, h, skinY, pxcm, P, now, 'L');
      const ay = skinY + P.depth * pxcm;
      const ar = P.r * pxcm * (1 + beat * 0.06);
      const ang = (acc.angle || 45) * DEG;
      const tipX = w * 0.6;
      const tipY = A.step === 6 ? ay - ar : skinY + (acc.depth || 0) * pxcm;
      const entryX = tipX - (tipY - skinY) / Math.tan(ang);
      // artery (compressed under the pad in step 6)
      const enh = g.createLinearGradient(0, ay + ar, 0, h);
      enh.addColorStop(0, 'rgba(255,255,255,.08)'); enh.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = enh; g.fillRect(0, ay + ar, w, h - ay - ar);
      g.fillStyle = '#010202';
      g.beginPath();
      const pinch = comp > 0.3 ? clamp((comp - 0.3) * 1.5, 0, 0.92) : 0;
      for (let x = 0; x <= w; x += 3) {
        const k = Math.exp(-Math.pow((x - entryX) / (26 * scale), 2)) * pinch;
        const y = ay - ar + ar * 2 * k * 0.5;
        if (x) g.lineTo(x, y); else g.moveTo(x, y);
      }
      for (let x = w; x >= 0; x -= 3) {
        const k = Math.exp(-Math.pow((x - entryX) / (26 * scale), 2)) * pinch;
        g.lineTo(x, ay + ar - ar * 2 * k * 0.5);
      }
      g.closePath(); g.fill();
      g.strokeStyle = `rgba(240,244,246,${0.65 + beat * 0.3})`; g.lineWidth = 2; g.stroke();
      // flow shimmer inside the lumen
      if (!pinch) {
        g.fillStyle = 'rgba(255,255,255,.05)';
        for (let i = 0; i < 6; i++) { const x = ((now / 6 + i * 57) % (w + 40)) - 20; g.fillRect(x, ay - ar * 0.4, 14, 1.2); }
      }
      // sheath / port
      const sheathIn = A.step === 6 ? 1 - (pr.pull || 0) : (acc.sheath || 0);
      if (sheathIn > 0.01) {
        const sx = lerp(entryX, tipX, sheathIn), sy = lerp(skinY, tipY, sheathIn);
        g.lineCap = 'round';
        g.strokeStyle = 'rgba(8,175,162,.85)'; g.lineWidth = 6 * scale;
        g.beginPath(); g.moveTo(entryX - Math.cos(ang) * 34 * scale, skinY - Math.sin(ang) * 34 * scale); g.lineTo(sx, sy); g.stroke();
        g.fillStyle = '#0fd4c4'; roundRect(g, entryX - Math.cos(ang) * 46 * scale - 6 * scale, skinY - Math.sin(ang) * 46 * scale - 5 * scale, 14 * scale, 10 * scale, 2 * scale); g.fill();
      }
      // needle with its hub (flashback shows here)
      if (A.step === 1 && acc.needle < 1) {
        const pull = acc.needle || 0;
        const nx = tipX - Math.cos(ang) * pull * 70 * scale, ny = tipY - Math.sin(ang) * pull * 70 * scale;
        const hx = entryX - Math.cos(ang) * (40 + pull * 70) * scale, hy = skinY - Math.sin(ang) * (40 + pull * 70) * scale;
        g.strokeStyle = '#f4f6f7'; g.lineWidth = 2 * scale; g.lineCap = 'butt';
        g.beginPath(); g.moveTo(hx, hy); g.lineTo(nx, ny); g.stroke();
        g.save(); g.translate(hx, hy); g.rotate(ang);
        g.fillStyle = 'rgba(255,255,255,.22)'; roundRect(g, -22 * scale, -6 * scale, 22 * scale, 12 * scale, 3 * scale); g.fill();
        if (acc.flash) { g.fillStyle = acc.flash === 'arterial' ? `rgba(229,72,77,${0.75 + beat * 0.25})` : 'rgba(110,32,36,.95)'; roundRect(g, -20 * scale, -4 * scale, 18 * scale, 8 * scale, 2 * scale); g.fill(); }
        g.restore();
      }
      // guide wire (J tip) running up the lumen
      if (A.step === 1 && (acc.wire || 0) > 0) {
        const wl = acc.wire * (w - tipX + 30 * scale);
        g.strokeStyle = 'rgba(255,255,255,.95)'; g.lineWidth = 1.3 * scale;
        g.beginPath(); g.moveTo(tipX, tipY);
        const bend = Math.min(wl, 16 * scale);
        g.quadraticCurveTo(tipX + bend * 0.6, tipY + (ay - tipY) * 0.9, tipX + bend, ay);
        if (wl > bend) g.lineTo(Math.min(w, tipX + wl), ay);
        g.stroke();
      }
      // step 6: blood oozing from the puncture + the pressure pad
      if (pr) {
        const b = clamp(pr.bleed / 30, 0, 1);
        if (b > 0.02) {
          for (let i = 0; i < 7; i++) {
            const k = ((now / 650 + i / 7) % 1);
            g.fillStyle = `rgba(229,72,77,${(1 - k) * b})`;
            g.beginPath(); g.arc(entryX + (i - 3) * 4 * scale, skinY - 3 * scale - k * 14 * scale, (2 + b * 3) * scale, 0, TAU); g.fill();
          }
        }
        const padY = skinY - 22 * scale + comp * 18 * scale;
        g.fillStyle = comp > 0.9 ? 'rgba(229,72,77,.75)' : (comp >= 0.55 && comp <= 0.8 ? 'rgba(15,212,196,.8)' : 'rgba(255,255,255,.45)');
        roundRect(g, entryX - 30 * scale, padY - 12 * scale, 60 * scale, 14 * scale, 5 * scale); g.fill();
        g.fillStyle = 'rgba(255,255,255,.55)'; g.font = `700 ${8 * scale}px Lexend, sans-serif`; g.textAlign = 'center';
        g.fillText(L('ui.pad', 'PRESS'), entryX, padY - 2.5 * scale); g.textAlign = 'left';
      }
      // angle readout arc at the skin entry
      if (A.step === 1 && acc.needle < 1) {
        g.strokeStyle = Math.abs((acc.angle || 45) - 45) <= 5 ? 'rgba(15,212,196,.9)' : 'rgba(242,179,61,.9)';
        g.lineWidth = 1.5 * scale;
        g.beginPath(); g.arc(entryX, skinY, 18 * scale, Math.PI, Math.PI + ang); g.stroke();
        g.fillStyle = g.strokeStyle; g.font = `600 ${9 * scale}px "JetBrains Mono", monospace`;
        g.fillText(`${Math.round(acc.angle || 45)}°`, entryX - 46 * scale, skinY - 6 * scale);
      }
    }
  }

  /* ═══════════════════════════ STEPS 2-5 · CATHETER ═══════════════════════════ */
  function updateCatheter(dt, now) {
    const s = A.sim, h = A.held;
    const shift = h.ShiftLeft || h.ShiftRight;
    let adv = ((h.KeyW || h.ArrowUp) ? 1 : 0) - ((h.KeyS || h.ArrowDown) ? 1 : 0);
    const rot = ((h.KeyD || h.ArrowRight) ? 1 : 0) - ((h.KeyA || h.ArrowLeft) ? 1 : 0);
    const carmIn = (h.KeyE ? 1 : 0) - (h.KeyQ ? 1 : 0);
    if (A.room) adv = 0;
    // coil deployment holds the catheter still
    if (s.deploy) {
      if (h.KeyF && s.deploy.pct < 100) { s.deploy.pct = clamp(s.deploy.pct + dt * 55, 0, 100); if (Math.random() < dt * 14) sfx.coil(); input(); renderStats(); if (s.deploy.pct >= 100) { renderPanel(); A.pp.flash('ok', L('f.coilOut', 'Coil fully out. {F} detaches it.'), 2200); } }
      if (adv < 0) { s.deploy.pct = clamp(s.deploy.pct - dt * 80, 0, 100); if (s.deploy.pct <= 0) { s.deploy = null; renderPanel(); } renderStats(); }
      adv = 0;
    }
    let ds = adv * A.cfg.catheterSpeed * (shift ? 2 : 1) * dt;
    if (A.wheel) { const w = clamp(A.wheel, -1.2, 1.2); ds += w * Math.min(1, dt * 10); A.wheel -= w * Math.min(1, dt * 10); if (Math.abs(A.wheel) < 0.02) A.wheel = 0; }
    if (A.pullAnim) { const d = Math.min(A.pullAnim.left, dt * 4); ds -= d; A.pullAnim.left -= d; if (A.pullAnim.left <= 0.001) A.pullAnim = null; }
    if (ds) {
      s.move(ds); input();
      if (s.blocked && ds > 0) {
        A.blockT = (A.blockT || 0) + dt;
        if (!A.blockMsg) { A.blockMsg = true; A.pp.flash('warn', s.blocked === 'narrow' ? L('f.narrow', 'Too narrow for the catheter.') : L('f.end', 'End of the vessel.'), 1800); }
        if (A.blockT > 1.3 && !A.spasmed) { A.spasmed = true; s.stats.spasm++; A.pp.flash('bad', L('f.spasm', 'Vessel spasm. Don\'t force it, pull back.'), 2600); NZA.post('angio:say', { line: 'cramp' }); }
      } else if (s.blocked === 'sheath' && ds < 0) {
        if (!A.blockMsg) { A.blockMsg = true; A.pp.flash('warn', L('f.sheath', 'Back at the sheath.'), 1500); }
      } else { A.blockT = 0; A.blockMsg = false; A.spasmed = false; }
    } else { A.blockT = 0; }
    if (rot) { s.phi = angDiff(s.phi + rot * dt * 2.4, 0); input(); }
    if (carmIn) { s.carm = clamp(s.carm + carmIn * dt * 26, -45, 45); A.carmTarget = null; input(); syncCarm(); }
    if (A.carmTarget !== null && A.carmTarget !== undefined) {
      s.carm = Math.abs(s.carm - A.carmTarget) < 0.5 ? A.carmTarget : lerp(s.carm, A.carmTarget, Math.min(1, dt * 5));
      if (s.carm === A.carmTarget) A.carmTarget = null;
      syncCarm(); input();
    }
    // table pan follows the tip
    const tip = s.tip();
    const ca = Math.cos(s.carm * DEG), sa = Math.sin(s.carm * DEG);
    const px = tip[0] * ca + tip[2] * sa;
    let tx = clamp(px * 0.7, -6, 6), ty = clamp(tip[1], -6, 40);
    const bl = A.scene.bleed;
    if ((s.bleedSeen || (s.run && s.run.blush)) && Math.abs(bl.y - tip[1]) < 20 && Math.abs(bl.x - tip[0]) < 24) {
      const bx = bl.x * ca + bl.z * sa;
      tx = clamp((px + bx) / 2 * 0.8, -7, 7); ty = clamp((tip[1] + bl.y) / 2, -6, 40);
    }
    s.cam.x = lerp(s.cam.x, tx, Math.min(1, dt * 1.8)); s.cam.y = lerp(s.cam.y, ty, Math.min(1, dt * 1.8));
    // x-ray: on while things move, plus runs
    const xr = now - A.lastInput < 600 || !!s.run;
    if (xr && !A.xr) sfx.xray();
    A.xr = xr;
    if (xr) { s.fl += dt; s.dose += dt * (s.run ? 4.2 : 1.1) * (1 + Math.abs(s.carm) / 70); }
    // runs
    if (s.run) {
      s.run.t += dt;
      const R = s.run.res;
      if (isFinite(R.bleedT) && s.run.t > R.bleedT + 0.6 && !s.run.seen) {
        s.run.seen = true; s.bleedSeen = true;
        A.bleedCaption = L('st.blush', 'Leak lit up on the run');
        renderStats();
      }
      if (s.run.t >= RUN_LEN[s.run.kind]) endRun();
    }
    if (s.stain > 0 && !s.run) s.stain = Math.max(0, s.stain - dt / 12);
    // phase gates
    if (A.phase === 'nav' && s.inGate()) { setPhase('select'); A.pp.flash('ok', F(L('f.inGate', 'You are in the %s.'), vesselLabel(A.scene.vessels[A.scene.bleed.gate])), 2200); }
    else if (A.phase === 'select' && !s.inGate() && !s.run) setPhase('nav');
    if (A.step >= 2 && A.step <= 5) { A.statT = (A.statT || 0) + dt; if (A.statT > 0.12) { A.statT = 0; renderStats(); updateSupplies(); renderCompass(); } }
  }
  function syncCarm() {
    const s = A.sim;
    A.$.carmVal.textContent = carmLabel(s.carm);
    if (A.carmSl) A.carmSl.set(Math.round(s.carm));
    if (A.carmSeg) A.carmSeg.set(String(Math.abs(s.carm) < 3 ? 0 : (Math.abs(s.carm - 30) < 3 ? 30 : (Math.abs(s.carm + 30) < 3 ? -30 : 'x'))));
  }

  function renderCompass() {
    const s = A.sim, svg = A.$.compass;
    const nj = s.nextJunction(4);
    const deg = Math.round(((s.phi / DEG) + 360) % 360);
    A.$.tipVal.textContent = `${deg}°`;
    const t = tipDir(A.scene, s.path, s.f);
    const [e1, e2] = frameFor(t);
    const axisName = v => {
      const ax = [Math.abs(v[0]), Math.abs(v[1]), Math.abs(v[2])];
      const m = ax.indexOf(Math.max(...ax));
      if (m === 0) return v[0] > 0 ? L('dir.l', 'L') : L('dir.r', 'R');
      if (m === 1) return v[1] > 0 ? L('dir.caud', 'CAUD') : L('dir.cran', 'CRAN');
      return v[2] > 0 ? L('dir.ant', 'ANT') : L('dir.post', 'POST');
    };
    const lab = [[0, axisName(e1)], [90, axisName(e2)], [180, axisName(mul(e1, -1))], [270, axisName(mul(e2, -1))]];
    const known = new Set(s.rm);
    let ticks = '';
    let selected = null;
    if (nj && nj.options && nj.options.length > 1) {
      // which one would the catheter take?
      const keep = s.phi;
      const pick = (() => {
        const ok = nj.options.filter(o => o.r >= MIN_R);
        let best = null;
        ok.forEach(o => { if (o.perp > 0.3) { const d = Math.abs(angDiff(keep, o.psi)); if (d < 40 * DEG && (!best || d < best.d)) best = { o, d }; } });
        if (best) return best.o;
        let st = ok[0]; ok.forEach(o => { if (st && o.along > st.along) st = o; });
        return st;
      })();
      selected = pick;
      nj.options.forEach(o => {
        const v = A.scene.vessels[o.v];
        const name = known.has(o.v) ? vesselLabel(v) : '?';
        const on = pick && o.node === pick.node;
        const narrow = o.r < MIN_R;
        if (o.perp <= 0.3) {
          ticks += `<circle cx="0" cy="0" r="7" class="${on ? 'on' : ''} ${narrow ? 'nar' : ''}"/>`;
          return;
        }
        const a = o.psi - Math.PI / 2;
        const x1 = Math.cos(a) * 34, y1 = Math.sin(a) * 34, x2 = Math.cos(a) * 46, y2 = Math.sin(a) * 46;
        const tx = Math.cos(a) * 54, ty = Math.sin(a) * 54;
        ticks += `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" class="tk ${on ? 'on' : ''} ${narrow ? 'nar' : ''}"/>`;
        if (name !== '?') ticks += `<circle cx="${tx.toFixed(1)}" cy="${ty.toFixed(1)}" r="2.2" class="dot ${on ? 'on' : ''}"/>`;
      });
    }
    const a = s.phi - Math.PI / 2;
    const ax = Math.cos(a) * 30, ay = Math.sin(a) * 30;
    svg.innerHTML = `
      <circle cx="0" cy="0" r="40" class="ring"/>
      <circle cx="0" cy="0" r="27" class="ring2"/>
      ${lab.map(([d, n]) => { const r = (d - 90) * DEG; return `<text x="${(Math.cos(r) * 50).toFixed(1)}" y="${(Math.sin(r) * 50 + 3).toFixed(1)}" class="lb">${esc(n)}</text>`; }).join('')}
      ${ticks}
      <line x1="0" y1="0" x2="${ax.toFixed(1)}" y2="${ay.toFixed(1)}" class="arrow"/>
      <circle cx="${ax.toFixed(1)}" cy="${ay.toFixed(1)}" r="4" class="head"/>`;
    const next = A.$.next;
    if (!nj) next.innerHTML = `<span class="nza-label">${esc(L('ui.next', 'Next branch'))}</span><b>${esc(L('ui.none', 'none ahead'))}</b>`;
    else if (nj.end) next.innerHTML = `<span class="nza-label">${esc(L('ui.ahead', 'Ahead'))}</span><b>${esc(L('ui.vesselEnd', 'Vessel ends'))}</b><small>${nj.dist.toFixed(1)} cm</small>`;
    else if (nj.narrow) next.innerHTML = `<span class="nza-label">${esc(L('ui.ahead', 'Ahead'))}</span><b>${esc(L('ui.tooNarrow', 'Too narrow'))}</b><small>${nj.dist.toFixed(1)} cm</small>`;
    else {
      const nm = selected ? (known.has(selected.v) ? vesselLabel(A.scene.vessels[selected.v]) : L('ui.unmapped', 'Unmapped branch')) : '--';
      next.innerHTML = `<span class="nza-label">${esc(L('ui.next', 'Next branch'))} · ${nj.dist.toFixed(1)} cm</span><b>${esc(nm)}</b><small>${esc(F(L('ui.branches', '%d ways'), nj.options.length))}</small>`;
    }
    const lamp = A.$.xr;
    lamp.classList.toggle('on', !!A.xr);
  }

  /* contrast */
  function isSelective() { const v = A.sim.vessel(); return !(v && (AORTIC.has(v.id) || v.key === 'cia' || v.key === 'eia' || v.key === 'cfa')); }
  async function contrastRun(fromButton) {
    if (!A || A.busy || A.sim.run || A.done) return;
    if (!(A.step >= 2 && A.step <= 5)) return;
    const s = A.sim;
    if (s.deploy && !A.released) { A.pp.flash('warn', L('f.coilFirst', 'Finish the coil first.'), 1800); return; }
    const selective = isSelective();
    const ml = selective ? A.cfg.selectiveMl : A.cfg.runMl;
    if (s.left < ml) { needDye(); return; }
    A.lastLabel = '';
    const inj = s.injection();
    const res = computeArrival(A.scene, inj, s.coils, 'run', A.cfg.coilDist);
    const blush = isFinite(res.bleedT);
    A.busy = true;
    const vname = vesselLabel(s.vessel());
    NZA.toast({ title: L('inj.title', 'Contrast away'), message: L('inj.text', 'The power injector is pushing contrast. Eyes on the monitor.'), type: 'info', icon: 'flask', duration: 2800 });
    sfx.whirr();
    const r = await NZA.post('angio:run', { kind: 'run', selective, blush, fromButton: !!fromButton, ml, vessel: vname });
    A && (A.busy = false);
    if (!A) return;
    if (!r || r.ok === false) {
      if (r && r.err === 'contrast') { if (typeof r.left === 'number') s.left = r.left; needDye(); return; }
      A.pp.flash('bad', (r && r.msg) || L('f.runFail', 'The injector did not fire.'), 2400); return;
    }
    s.left = typeof r.left === 'number' ? r.left : s.left - ml;
    s.contrastMl += ml;
    s.runId++; s.runs++;
    // in game the camera may cut to the injector first: the dye reaches the patient after `delay` s
    const delay = clamp(Number(r.delay) || 0, 0, 4);
    s.run = { id: s.runId, inj, kind: 'run', t: -delay, res, blush, label: F(selective ? L('run.selective', 'Selective run · %s') : L('run.flush', 'Aortogram · %s'), vname), selective };
    injectorMarker(ml, delay);
    if (A.phase === 'select' || A.phase === 'confirm' || (A.phase === 'coil' && A.released)) A.runPhase = A.phase;
    else A.runPhase = A.phase;
    NZA.post('angio:say', { line: 'warm' });
    updateSupplies(); renderPanel();
  }
  // a world label on the power injector while it pushes dye (anchor 'injector' from Lua)
  function injectorMarker(ml, delay) {
    if (!A || !A.def.anchors || !A.def.anchors.map || !A.def.anchors.map.injector) return;
    const m = NZA.ui.Marker('angio', 'injector', { label: F(L('inj.marker', 'Injecting %d mL'), ml), dot: 'teal', anchor: 'injector' });
    const id = A.runIdMark = (A.runIdMark || 0) + 1;
    setTimeout(() => { if (A && A.runIdMark === id) m.remove(); }, (INJ.run + delay) * 1000);
  }
  async function puff() {
    if (!A || A.busy || A.sim.run || A.done) return;
    const s = A.sim;
    if (s.left < A.cfg.puffMl) { needDye(); return; }
    const inj = s.injection();
    const res = computeArrival(A.scene, inj, s.coils, 'puff', A.cfg.coilDist);
    A.busy = true;
    const r = await NZA.post('angio:run', { kind: 'puff', selective: true, blush: false, ml: A.cfg.puffMl });
    if (!A) return;
    A.busy = false;
    if (!r || r.ok === false) { if (r && r.err === 'contrast') needDye(); return; }
    s.left = typeof r.left === 'number' ? r.left : s.left - A.cfg.puffMl;
    s.contrastMl += A.cfg.puffMl;
    s.runId++;
    s.run = { id: s.runId, inj, kind: 'puff', t: 0, res, label: L('run.puff', 'Test puff') };
    sfx.tick();
    updateSupplies();
  }
  function endRun() {
    const s = A.sim, run = s.run;
    s.run = null;
    A.lastLabel = run.label || '';
    // road-map: vessels that filled
    const reached = new Set();
    const nd = A.scene.nodes;
    for (let i = 0; i < run.res.arr.length; i++) if (isFinite(run.res.arr[i])) reached.add(nd.v[i]);
    if (run.kind === 'puff') { reached.forEach(v => { if (!s.rm.includes(v)) s.rm.push(v); }); return; }
    s.rm = [...reached];
    if (run.blush) { s.stain = Math.max(s.stain, (run.res.bleedI || 1) * 0.85); }
    const ph = A.phase;
    if (run.blush) {
      // seal = how much the leak flow dropped on this run (full blush 0 %, collateral refill ≈ 45 %)
      A.seal = s.coils.length ? Math.round(clamp(1 - (run.res.bleedI || 1), 0, 1) * 100) : 0;
      s.bleedSeen = true;
      A.bleedCaption = L('st.blush', 'Leak lit up on the run');
      if (ph === 'nav' || ph === 'select') {
        if (s.inGate()) { setPhase('coil'); A.pp.flash('bad', F(L('f.found', 'Leak found: contrast pooling off the %s. Pack it with a coil.'), vesselLabel(A.scene.vessels[A.scene.bleed.vessel])), 3600); }
        else A.pp.flash('ok', F(L('f.seenFlush', 'Leak spotted. Now steer into the %s.'), vesselLabel(A.scene.vessels[A.scene.bleed.gate])), 3600);
      } else if (ph === 'confirm' || (ph === 'coil' && A.released)) {
        A.released = false;
        setPhase('coil');
        A.pp.flash('bad', L('f.still', 'Still pooling. Place another coil, closer.'), 3400);
      }
    } else {
      if (ph === 'select' || ph === 'nav') {
        if (s.inGate() || run.selective) { s.stats.wrongRuns++; A.pp.flash('warn', L('f.noBleed', 'Nothing leaks from this vessel. Try another branch.'), 3000); if (ph === 'select') setPhase('nav'); }
        else A.pp.flash('ok', L('f.mapped', 'Vessels mapped. The road-map stays on screen.'), 2600);
      } else if (ph === 'confirm' || (ph === 'coil' && A.released)) {
        if (s.coils.length && s.coils.some(c => c.eff)) sealed();
        else { A.pp.flash('warn', L('f.noBlushNoCoil', 'No pooling from here. Inject closer to the coil.'), 3000); }
      }
    }
    renderPanel();
  }
  function needDye() {
    if (A.bottles > 0) A.pp.flash('warn', F(L('f.dyeOut', 'Out of contrast. {B} opens a new bottle (%d left).'), A.bottles), 3200);
    else A.pp.flash('bad', L('f.dyeNone', 'Out of contrast and no bottles left.'), 3200);
    renderPanel();
  }
  async function refill() {
    if (!A || A.busy) return;
    if (!(A.bottles > 0)) { needDye(); return; }
    A.busy = true;
    const r = await NZA.post('angio:refill', {});
    if (!A) return;
    A.busy = false;
    if (r && r.ok) {
      A.sim.left = typeof r.left === 'number' ? r.left : A.sim.left + A.cfg.budget;
      A.bottles = typeof r.bottles === 'number' ? r.bottles : A.bottles - 1;
      A.budgetMax = Math.max(A.budgetMax || A.cfg.budget, A.sim.left);
      A.pp.flash('ok', L('f.dyeIn', 'New bottle loaded.'), 1800);
    } else A.pp.flash('bad', L('f.dyeNone', 'Out of contrast and no bottles left.'), 2400);
    updateSupplies(); renderPanel();
  }

  /* coils */
  async function coilPress() {
    const s = A.sim;
    if (!(A.phase === 'coil' || A.phase === 'confirm')) { A.pp.flash('warn', L('f.coilWhen', 'Find the leak with an injection first.'), 2200); return; }
    if (s.run || A.busy) return;
    if (!s.deploy) {
      if (A.coilsLeft <= 0) { A.pp.flash('bad', L('f.noCoils', 'No coils left.'), 2400); return; }
      if (A.phase === 'confirm') { A.released = false; setPhase('coil'); }
      const [a, b] = s.edge();
      s.deploy = { a, b, f: s.f, pct: 0 };
      A.released = false;
      renderPanel();
      return;
    }
    if (s.deploy.pct < 100) return;   // holding F keeps pushing (update loop)
    // release
    const c = s.deploy;
    const eff = s.coilEffect(c);
    A.busy = true;
    const r = await NZA.post('angio:coil', { dist: Math.round(eff.dist * 100) / 100, onPath: eff.onPath });
    if (!A) return;
    A.busy = false;
    if (!r || r.ok === false) {
      A.pp.flash('bad', (r && r.msg) || L('f.noCoils', 'No coils left.'), 2400);
      s.deploy = null; renderPanel(); return;
    }
    c.rel = true; c.eff = eff.onPath && eff.dist <= A.cfg.coilDist; c.dist = eff.dist; c.onPath = eff.onPath;
    s.coils.push(c); s.deploy = null;
    A.coilsLeft = typeof r.left === 'number' ? r.left : Math.max(0, A.coilsLeft - 1);
    if (!eff.onPath) s.stats.offCoils++;
    if (s.coils.length > 1) s.stats.extraCoils = s.coils.length - 1;
    if (c.eff) s.stats.bestDist = Math.min(s.stats.bestDist, eff.dist);
    A.released = true;
    sfx.thunk();
    A.pp.flash(c.eff ? 'ok' : 'warn', c.eff ? L('f.released', 'Coil detached. Back off with {R}.') : (eff.onPath ? F(L('f.far', 'Coil detached %s cm short of the leak. It may not hold.'), eff.dist.toFixed(1)) : L('f.offTarget', 'Coil detached off target.')), 3000);
    updateSupplies(); renderPanel();
  }
  function pullBack() {
    A.pullAnim = { left: 2.0 };
    sfx.tick();
    setTimeout(() => { if (A && A.released && A.phase === 'coil') setPhase('confirm'); }, 600);
  }
  function sealed() {
    A.pp.flash('ok', L('f.sealed', 'No pooling. The leak is sealed.'), 3200);
    NZA.audio.success();
    A.bleedCaption = L('st.sealed', 'Sealed');
    A.seal = 100;
    setTimeout(() => {
      if (!A) return;
      A.press = { pull: 0, p: 0, held: 0, need: (A.cfg.holdTime && A.cfg.holdTime[A.accKind]) || (A.accKind === 'radial' ? 6 : 12), bleed: ACCESS[A.accKind].bleed, over: 0 };
      setPhase('pull');
    }, 1600);
  }

  /* ═══════════════════════════ STEP 6 · HAEMOSTASIS ═══════════════════════════ */
  function sheathOut() {
    sfx.thunk();
    A.pp.flash('warn', L('f.sheathOut', 'Sheath out. It is bleeding: press now.'), 2400);
    setPhase('press');
  }
  function updatePress(dt) {
    const pr = A.press; if (!pr || A.phase !== 'press') return;
    const down = A.held.Space || (A.demoPress && pr.p < 0.68);
    pr.p = clamp(pr.p + (down ? 0.55 : -0.9) * dt, 0, 1);
    const inZone = pr.p >= 0.55 && pr.p <= 0.8;
    A.stats.hold += dt;
    if (inZone) { pr.held += dt; A.stats.holdIn += dt; pr.bleed = Math.max(0, pr.bleed - dt * ACCESS[A.accKind].bleed / pr.need * 1.2); }
    else if (pr.p > 0.9) { pr.over += dt; A.stats.over += dt; if (!pr.warned) { pr.warned = true; A.pp.flash('bad', L('f.tooHard', 'Too hard: you are stopping the pulse. Ease off.'), 2200); } }
    else { pr.bleed = Math.min(ACCESS[A.accKind].bleed, pr.bleed + dt * 2.5); pr.warned = false; }
    if (pr.held >= pr.need) { complete(); return; }
    A.statT = (A.statT || 0) + dt;
    if (A.statT > 0.1) { A.statT = 0; renderStats(); renderAccessGauges(); }
  }

  /* ═══════════════════════════ RESULT ═══════════════════════════ */
  function scoreParts() {
    const s = A.sim, c = A.cfg, st = A.stats;
    const access = clamp(100 - (st.angleErr || 0) * 2 - st.attempts * 15 - Math.max(0, st.accessT - 50) * 0.4, 0, 100);
    const nav = clamp(100 - s.stats.wrongRuns * 12 - s.stats.spasm * 8, 0, 100);
    const dye = clamp(100 - Math.max(0, s.contrastMl - c.parContrast) * 1.2, 0, 100);
    const fl = clamp(100 - Math.max(0, s.fl - c.parFluoro) * 0.25, 0, 100);
    const best = isFinite(s.stats.bestDist) ? s.stats.bestDist : c.coilDist;
    const coil = clamp((best <= 1 ? 100 : 100 - (best - 1) * 30) - s.stats.extraCoils * 12 - s.stats.offCoils * 15, 0, 100);
    const haemo = clamp((st.hold > 0 ? st.holdIn / st.hold : 0) * 100 - st.over * 5, 0, 100);
    const total = Math.round(access * 0.15 + nav * 0.15 + dye * 0.1 + fl * 0.1 + coil * 0.3 + haemo * 0.2);
    return { access, nav, dye, fl, coil, haemo, total };
  }
  function complete() {
    if (A.done) return;
    A.done = true;
    setPhase('done');
    const sc = scoreParts();
    A.result = sc;
    const s = A.sim;
    const tone = v => (v >= 72 ? '' : v >= 45 ? 'amber' : 'red');
    const row = (k, fb, v, extra) => `<div class="ag-rrow ${tone(v)}"><i class="nt"></i><span class="lb">${esc(L(k, fb))}${extra ? `<small>${esc(extra)}</small>` : ''}</span><b>${Math.round(v)}</b></div>`;
    const R = 34, C = 2 * Math.PI * R, tot = clamp(sc.total, 0, 100);
    A.$.result.innerHTML = `
      <div class="ag-rhead">
        <span class="ag-ring ${tone(tot)}"><svg viewBox="0 0 84 84"><circle class="bg" cx="42" cy="42" r="${R}"/><circle class="tk" cx="42" cy="42" r="${R + 6}"/><circle class="fg" cx="42" cy="42" r="${R}" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - tot / 100)).toFixed(1)}"/></svg><b>${sc.total}</b><em>${esc(L('res.score', 'Score'))}</em></span>
        <div><span class="nza-label">${esc(L('res.label', 'Angiography'))}</span><h3>${esc(L('res.title', 'Leak sealed'))}</h3><p>${esc(F(L('res.sub', '%s · %d coil(s) · %d mL contrast · %s fluoro'), L(`acc.${A.access}`, ACCESS_EN[A.access]), s.coils.length, Math.round(s.contrastMl), fmtTime(s.fl)))}</p></div>
      </div>
      <div class="ag-rbody">
        ${row('res.access', 'Access', sc.access, A.stats.angleErr !== null ? `${Math.round(45 + (A.stats.angleErr || 0))}°` : '')}
        ${row('res.nav', 'Navigation', sc.nav, `${s.runs} ${L('res.runs', 'runs')}`)}
        ${row('res.dye', 'Contrast', sc.dye, `${Math.round(s.contrastMl)} mL`)}
        ${row('res.fl', 'Dose', sc.fl, `${s.dose.toFixed(0)} mGy`)}
        ${row('res.coil', 'Coil placement', sc.coil, isFinite(s.stats.bestDist) ? `${s.stats.bestDist.toFixed(1)} cm` : '')}
        ${row('res.haemo', 'Haemostasis', sc.haemo, '')}
      </div>`;
    A.$.result.classList.add('on');
    NZA.audio.success();
    A.pp.set({ abort: false });
    A.pp.complete({ title: L('done.title', 'Leak sealed'), text: L('done.text', 'The coil holds and the puncture is closed. Press {Enter} to finish.'), label: L('done.btn', 'Finish'), onDone: () => finish() });
    NZA.post('angio:step', { phase: 'done', step: 6, cam: 'access', access: A.access });
  }
  function finish() {
    if (!A || A.finished) return;
    A.finished = true;
    const s = A.sim, sc = A.result || scoreParts();
    NZA.post('angio:finish', {
      result: {
        score: sc.total, success: true, access: A.access, coils: s.coils.length, runs: s.runs,
        contrast: Math.round(s.contrastMl), fluoro: Math.round(s.fl), dose: Math.round(s.dose * 10) / 10,
        bestDist: isFinite(s.stats.bestDist) ? Math.round(s.stats.bestDist * 100) / 100 : null,
        parts: { access: Math.round(sc.access), nav: Math.round(sc.nav), contrast: Math.round(sc.dye), dose: Math.round(sc.fl), coil: Math.round(sc.coil), haemostasis: Math.round(sc.haemo) },
        vessel: vesselLabel(A.scene.vessels[A.scene.bleed.vessel]),
      },
    });
    A.pp.set({ title: L('done.saving', 'Saving the record...'), text: '' });
  }

  /* ═══════════════════════════ VIEW / ROOM ═══════════════════════════ */
  function setView(v) {
    if (!A || !A.dui) v = 'screen';
    A.view = v;
    if (A.viewSeg) A.viewSeg.set(v);
    A.def.el.classList.toggle('ag-showscreen', A.step >= 2 && A.step <= 5 && v === 'screen');
    NZA.post('angio:view', { mode: v });
  }
  function setRoom(on, fromLua) {
    if (!A) return;
    A.room = on;
    A.def.el.classList.toggle('ag-room', on);
    if (on) {
      NZA.ui.Marker('angio', 'button', { label: L('room.button', 'Inject contrast'), dot: 'red', tone: 'red', anchor: 'button' });
      roomPanel();
    } else {
      NZA.ui.Marker('angio', 'button').remove();
      A.pp.set({ abort: { label: L('abort', 'Hold to cancel'), key: 'ESC', seconds: 1.2 } });
      renderPanel();
    }
    if (!fromLua) NZA.post('angio:room', { on });
  }
  function onVitals(d) {
    const v = d && (d.vitals || d);
    if (!v) return;
    A.vitals = v;
    if (A.mon) A.mon.update(v);
  }

  /* ═══════════════════════════ FRAME LOOP ═══════════════════════════ */
  function loop(now) {
    if (!A) return;
    const dt = Math.min(0.05, (now - A.last) / 1000);
    A.last = now;
    if (A.step === 1 && A.phase !== 'choose') { updateAccess(dt); drawAccess(now); }
    else if (A.step === 6) { updatePress(dt); drawAccess(now); }
    else if (A.step >= 2 && A.step <= 5) updateCatheter(dt, now);
    // fluoroscopy image (NUI canvas when shown, DUI frames when live)
    if (A.step >= 2 && A.step <= 5) {
      const snap = A.sim.snapshot({ xr: !!A.xr, dsa: A.sim.run && A.sim.run.kind === 'run' ? smooth(A.sim.run.t / 0.6) * (1 - smooth((A.sim.run.t - (RUN_LEN.run - 1.2)) / 1.2)) : 0, hud: hudInfo(), gp: gapState() });
      if (!A.dui || A.view === 'screen' || !NZA.inGame) {
        const cv = A.$.fluoro;
        NZA.fitCanvas(cv);
        A.fv.render(snap, now);
      }
      if (A.dui && now - A.sendT > 50) {
        A.sendT = now;
        NZA.post('angio:screen', { state: compact(snap) });
      }
    } else if (A.dui && now - A.sendT > 400) {
      A.sendT = now;
      NZA.post('angio:screen', { state: { sc: A.scene.params, standby: false, hud: hudInfo(), p: [], f: 0, rm: [], coils: [], idle: true } });
    }
    A.raf = requestAnimationFrame(loop);
  }
  function compact(st) {
    const r = v => Math.round(v * 1000) / 1000;
    return {
      sc: st.sc, p: st.p, f: r(st.f), phi: r(st.phi), carm: r(st.carm), mag: st.mag || 1, cx: r(st.cx), cy: r(st.cy), coils: st.coils.map(c => [c[0], c[1], r(c[2]), Math.round(c[3]), c[4]]),
      rm: st.rm, bs: st.bs, stain: r(st.stain), cd: st.cd, run: st.run ? { id: st.run.id, a: st.run.a, b: st.run.b, f: r(st.run.f), k: st.run.k, t: r(st.run.t) } : null,
      xr: st.xr, dsa: r(st.dsa || 0), hud: st.hud, gp: st.gp || null,
    };
  }
  // [gap cm, in coil range, on the feeding branch, start gap] while the leak is marked and a coil can still go in
  function gapState() {
    if (!A.sim.bleedSeen || A.seal === 100 || !(A.phase === 'nav' || A.phase === 'select' || A.phase === 'coil' || A.phase === 'confirm')) return null;
    const g = leakGap();
    return [Math.round(g.d * 10) / 10, g.near ? 1 : 0, g.feeds ? 1 : 0, Math.round(g.span)];
  }
  function hudInfo() {
    const s = A.sim, p = A.patient || {};
    const v = A.vitals || {};
    return {
      name: p.name || '', sexAge: [p.sex ? String(p.sex).toUpperCase() : '', p.age || '', p.bloodType || ''].filter(Boolean).join(' · '),
      caseId: A.data.caseId || '', kv: 78 + Math.abs(s.carm) * 0.3 + (A.xr ? 3 : 0), ma: 2.2 + Math.abs(s.carm) * 0.015, fl: s.fl, dose: s.dose,
      run: s.runs, carmLabel: carmLabel(s.carm), ml: s.contrastMl, coils: s.coils.length, label: s.run ? s.run.label : (A.lastLabel || ''), hr: v.hr || 0,
    };
  }

  /* ═══════════════════════════ PREVIEW ═══════════════════════════ */
  function demoData() {
    return {
      locale: {},
      dui: false, hasButton: true,
      data: {
        seed: 4127, bleed: { key: 'ileal', side: '' }, injury: { id: 'i7', region: 'abdomen', type: 'internal', severity: 3, organ: 'bowel', vessel: 'ileal', bleed: 84 },
        patient: { name: 'Tomas Lindqvist', sex: 'm', age: 34, bloodType: 'O-', avpu: 'V', vitals: { hr: 118, sys: 92, dia: 56, map: 68, spo2: 95, rr: 22, rhythm: 'stach' } },
        budget: 100, coils: 3, bottles: 1, maxCoils: 6, coilDist: 2, holdTime: { femoral: 12, radial: 6 }, runMl: 18, selectiveMl: 8, puffMl: 3,
        catheterSpeed: 4, parContrast: 45, parFluoro: 150, caseId: 'A-0412',
      },
    };
  }
  function preview() {
    NZA.mock('angio:run', d => ({ ok: true, left: Math.max(0, (A ? A.sim.left : 100) - (d.ml || 18)) }));
    NZA.mock('angio:coil', () => ({ ok: true, left: Math.max(0, (A ? A.coilsLeft : 3) - 1) }));
    NZA.mock('angio:refill', () => ({ ok: true, left: (A ? A.sim.left : 0) + 100, bottles: 0 }));
    NZA.open('angio', demoData());
    demo(new URLSearchParams(location.search).get('step') || 'coil');
  }
  // jump to a representative state (preview + screenshots)
  function demo(step) {
    if (!A) NZA.open('angio', demoData());
    const s = A.sim, sc = A.scene, nd = sc.nodes;
    if (step === 'choose') { setPhase('choose'); return; }
    chooseAccess('femoral_r');
    if (step === 'access' || step === 'aim') { A.acc.angle = 44; A.acc.aim = 0.08; A.acc.adv = 3.6; A.acc.depth = A.acc.adv * Math.sin(44 * DEG); return; }
    if (step === 'needle') { A.acc.flash = 'arterial'; A.acc.wire = 1; A.acc.sheath = 1; A.acc.aim = 0.04; A.acc.angle = 44; A.acc.flashAngle = 44; A.acc.depth = 3.0; A.acc.needle = 0.32; setPhase('needle'); return; }
    A.stats.angleErr = 2; A.stats.accessT = 40;
    // catheter route from the groin to just short of the bleed
    const route = (target, stopBefore) => {
      const up = []; for (let n = s.path[0]; n >= 0; n = nd.p[n]) up.push(n);
      const down = []; for (let n = target; n >= 0; n = nd.p[n]) down.push(n);
      const set = new Set(down);
      const lcaIdx = up.findIndex(n => set.has(n));
      const lca = up[lcaIdx];
      const p = up.slice(0, lcaIdx + 1).concat(down.slice(0, down.indexOf(lca)).reverse());
      let cut = p.length - 1, d = 0;
      while (cut > 1 && d < stopBefore) { d += len(sub(nodePos(sc, p[cut]), nodePos(sc, p[cut - 1]))); cut--; }
      s.path = p.slice(0, cut + 1); s.f = 0.4;
    };
    const flush = () => {
      // an aortogram from the aorta: maps every vessel and shows the blush
      const ao = sc.byId.aorta.own[6];
      const res = computeArrival(sc, { a: nd.p[ao], b: ao, f: 0.5 }, [], 'run', 2);
      const set = new Set(); for (let i = 0; i < res.arr.length; i++) if (isFinite(res.arr[i])) set.add(nd.v[i]);
      s.rm = [...set]; s.bleedSeen = true; s.runs = 1; s.contrastMl = 18; s.left = 82; s.fl = 64; s.dose = 71.4;
    };
    A.startDist = 38;
    if (step === 'nav') { flush(); s.bleedSeen = false; s.stain = 0; route(sc.byId.aorta.own[26], 0); s.f = 0.3; setPhase('nav'); s.phi = 0.2; s.cam = { x: s.tip()[0] * 0.7, y: s.tip()[1] }; return; }
    flush();
    if (step === 'run' || step === 'select') route(sc.byId.sma.own[9], 0); else route(sc.bleed.node, 2.1);
    s.carm = 0; s.phi = 1.3; s.runs = 2; s.contrastMl = 26; s.left = 74; s.fl = 96; s.dose = 104.2;
    s.cam = { x: s.tip()[0] * 0.7, y: s.tip()[1] };
    A.bleedCaption = L('st.blush', 'Leak lit up on the run');
    A.seal = 0;
    if (step === 'run' || step === 'select') {
      setPhase('select');
      const inj = s.injection();
      s.runId = 9; s.run = { id: 9, inj, kind: 'run', t: 2.4, res: computeArrival(sc, inj, [], 'run', 2), blush: true, label: F(L('run.selective', 'Selective run · %s'), vesselLabel(s.vessel())) };
      A.lastInput = performance.now() + 1e7;
      return;
    }
    setPhase('coil');
    s.stain = 0.75;
    if (step === 'coil') { const [a, b] = s.edge(); s.deploy = { a, b, f: s.f, pct: 100 }; renderPanel(); renderStats(); return; }
    if (step === 'confirm') {
      const [a, b] = s.edge();
      const c = { a, b, f: s.f, pct: 100, rel: true }; const e = s.coilEffect(c); c.eff = true; c.dist = e.dist;
      s.coils.push(c); A.coilsLeft = 2; A.released = true; s.move(-1.4); s.stain = 0.2; setPhase('confirm');
      const inj = s.injection(); s.runId = 11; s.run = { id: 11, inj, kind: 'run', t: 3.1, res: computeArrival(sc, inj, s.coils, 'run', 2), blush: false, label: F(L('run.selective', 'Selective run · %s'), vesselLabel(s.vessel())) };
      return;
    }
    if (step === 'press' || step === 'pull') {
      A.press = { pull: step === 'pull' ? 0.42 : 1, p: 0.68, held: 7.2, need: 12, bleed: 9.4, over: 0 };
      setPhase(step);
      if (step === 'press') A.demoPress = true;
      return;
    }
    if (step === 'done') {
      const [a, b] = s.edge(); s.coils.push({ a, b, f: s.f, pct: 100, rel: true, eff: true, dist: 1.1 }); s.stats.bestDist = 1.1;
      A.press = { pull: 1, p: 0.66, held: 12, need: 12, bleed: 0, over: 0 }; A.stats.hold = 14; A.stats.holdIn = 12.4;
      complete();
    }
  }
})();
