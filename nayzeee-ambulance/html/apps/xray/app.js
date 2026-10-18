/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Radiology (app 'xray')

   One app, six modes (Lua sends them in the 'open' data):
     choose   X-ray console: pick the view (1-8 / click the body) → xray:choose { view }
     expose   radiographer console: breath hold (B), hold Space to expose → xray:expose { breath }
              Lua then sends 'filmReady' { id, view, viewLabel, quality } and 'result'
     read     lightbox: drag the film onto the viewer, pin the breaks on the AP and the
              lateral film (2 mark, F switch film, 1 move, 3 measure, C contrast, L light,
              R reset, scroll zoom, N normal film, Enter report) → xray:finish { marks, normal, measure }
              Lua sends 'result' (server outcome) or 'error' { msg }
     view     the same lightbox, look only (no permission)
     reduce   set the bone under live fluoroscopy (drag the lower piece, F live image)
              → xray:finish { score, angle, short, slips, painOver, fluoro }
     cast     padding, plaster turns, moulding → xray:finish { score, coverage, layersMin, layersMax, cracks }
   Every mode: xray:abort (hold ESC) · xray:close (router)

   The radiographs are drawn procedurally (ANAT) from the film metadata the server built
   from the patient's real injuries. Film space: x 0..1 left → right as it hangs on the
   viewer, y 0..1 top → bottom; AP: patient's right on the viewer's left; lateral films:
   anterior on the left. LIMB axes are the same numbers as server/modules/xray.lua.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'xray';
  const { esc, clamp } = NZA;
  const icon = (n) => NZA.icon(n);
  const TAU = Math.PI * 2;
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (a, b, t) => { t = clamp((t - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const rad = (d) => d * Math.PI / 180;

  let L = {};
  const T = (k, fb) => (L[k] !== undefined ? L[k] : fb);
  const F = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]/g, () => (a[i++] ?? '')); };

  function mulberry(seed) {
    let a = (seed >>> 0) || 1;
    return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  function hash(str) { let h = 2166136261; for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
  function mk(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.round(w)); c.height = Math.max(1, Math.round(h)); return c; }

  const fontsReady = (document.fonts && document.fonts.load)
    ? Promise.all(['600 14px Lexend', '400 11px "JetBrains Mono"', '700 11px "JetBrains Mono"'].map(f => document.fonts.load(f).catch(() => null)))
    : Promise.resolve();

  /* ═══════════════════════════ RADIOGRAPH RENDERER ═══════════════════════════ */

  // same numbers as server/modules/xray.lua (LIMB) - right limb; AP of a left limb is mirrored
  const LIMB = {
    leg: {
      ap: { femur: [0.535, 0.075, 0.505, 0.465], tibia: [0.505, 0.515, 0.500, 0.855], fibula: [0.448, 0.530, 0.452, 0.850] },
      lat: { femur: [0.520, 0.075, 0.500, 0.465], tibia: [0.500, 0.515, 0.520, 0.840], fibula: [0.535, 0.530, 0.548, 0.835] },
      mm: 1000,
    },
    arm: {
      ap: { humerus: [0.500, 0.070, 0.505, 0.430], radius: [0.468, 0.480, 0.452, 0.790], ulna: [0.542, 0.470, 0.535, 0.790] },
      lat: { humerus: [0.500, 0.070, 0.500, 0.430], radius: [0.488, 0.480, 0.470, 0.790], ulna: [0.515, 0.470, 0.522, 0.790] },
      mm: 800,
    },
  };
  const BONE_AXES = {
    femur: ['femur'], tibia: ['tibia'], fibula: ['fibula'], tibia_fibula: ['tibia', 'fibula'],
    humerus: ['humerus'], radius: ['radius'], ulna: ['ulna'], radius_ulna: ['radius', 'ulna'],
  };
  const viewKind = (v) => String(v || '').replace(/^[lr]_/, '');
  const viewSide = (v) => (/^l_/.test(v || '') ? 'l' : /^r_/.test(v || '') ? 'r' : null);

  const BONE = (a) => `rgba(160,178,194,${a})`;
  const CORT = (a) => `rgba(212,226,238,${a})`;
  const TIS = (a) => `rgba(128,144,158,${a})`;
  // inside a bone group (one bone made of several parts) the parts are united ('lighten' with
  // opaque colours) so they never add up; separate bones still add ('lighter') like real density
  const TB = [160, 178, 194], TC = [212, 226, 238];
  const col = (g, t, a) => (g._grp ? `rgb(${Math.round(t[0] * a)},${Math.round(t[1] * a)},${Math.round(t[2] * a)})` : `rgba(${t[0]},${t[1]},${t[2]},${a})`);
  const addOp = (g) => (g._grp ? 'lighten' : 'lighter');
  function group(C, fn) {
    if (C.only === 'distal' || C.gb._grp) { fn(); return; }
    const tmp = C._tmp || (C._tmp = mk(C.W, C.H)); const tg = tmp.getContext('2d'); tg._grp = true; tg.clearRect(0, 0, C.W, C.H);
    const real = C.gb; C.gb = tg;
    try { fn(); } finally { C.gb = real; }
    real.save(); real.globalCompositeOperation = 'lighter'; real.drawImage(tmp, 0, 0); real.restore();
  }

  /* ── geometry helpers (normalized film coords: x in W units, y in H units, sizes in W units) ── */
  function resample(pts, n) {
    const seg = []; let total = 0;
    for (let i = 1; i < pts.length; i++) { const d = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); seg.push(d); total += d; }
    const out = [];
    for (let k = 0; k <= n; k++) {
      let target = total * k / n, i = 0;
      while (i < seg.length - 1 && target > seg[i]) { target -= seg[i]; i++; }
      const t = seg[i] ? clamp(target / seg[i], 0, 1) : 0;
      out.push([lerp(pts[i][0], pts[i + 1][0], t), lerp(pts[i][1], pts[i + 1][1], t)]);
    }
    return { pts: out, len: total };
  }
  function bez(p0, p1, p2, p3, n = 16) {
    const out = [];
    for (let i = 0; i <= n; i++) {
      const t = i / n, u = 1 - t;
      out.push([u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
        u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]]);
    }
    return out;
  }
  function smoothPath(g, P, close = true) {
    const n = P.length;
    if (n < 3) { g.moveTo(P[0][0], P[0][1]); for (let i = 1; i < n; i++) g.lineTo(P[i][0], P[i][1]); if (close) g.closePath(); return; }
    const get = (i) => (close ? P[(i + n) % n] : P[clamp(i, 0, n - 1)]);
    g.moveTo(P[0][0], P[0][1]);
    const last = close ? n : n - 1;
    for (let i = 0; i < last; i++) {
      const p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
      g.bezierCurveTo(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6, p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6, p2[0], p2[1]);
    }
    if (close) g.closePath();
  }
  function polyPath(g, P, close = true) { g.moveTo(P[0][0], P[0][1]); for (let i = 1; i < P.length; i++) g.lineTo(P[i][0], P[i][1]); if (close) g.closePath(); }

  /* ── render context ── */
  function makeCtx(film, which, w, opts = {}) {
    const W = Math.round(w), H = Math.round(w * 1.25);
    const kind = viewKind(film.view);
    const C = {
      film, which, lat: which === 'lat', kind, W, H, side: viewSide(film.view),
      mirror: which === 'ap' && viewSide(film.view) === 'l',
      soft: mk(W, H), bone: mk(W, H), metal: mk(W, H),
      R: mulberry((film.seed || 7) * 31 + (which === 'lat' ? 17 : 3)),
      fx: [], frags: [], conds: [], live: opts.live || null, only: opts.only || null, distal: null,
    };
    C.gs = C.soft.getContext('2d'); C.gb = C.bone.getContext('2d'); C.gm = C.metal.getContext('2d');
    C.X = (x) => x * W; C.Y = (y) => y * H; C.S = (s) => s * W;
    C.P = (p) => [p[0] * W, p[1] * H];
    for (const f of (film.findings || [])) {
      const pos = f[which];
      if (!pos) continue;
      const p = { x: C.mirror ? 1 - pos.x : pos.x, y: pos.y };
      if (f.k === 'fx') C.fx.push(Object.assign({}, f, { p, rnd: mulberry(hash(String(f.id) + (film.seed || 0))) }));
      else if (f.k === 'frag') C.frags.push(Object.assign({}, f, { p }));
      else C.conds.push(Object.assign({}, f, { p }));
    }
    return C;
  }

  // projected displacement of a fracture on this film
  function motion(C, f, widthPx) {
    if (C.live && C.live.id === f.id) return C.live.m(C, f, widthPx);
    if (!f.disp) return { ang: 0, shift: 0, short: 0 };
    const share = C.lat ? Math.abs(Math.sin(f.phi || 0.6)) : Math.abs(Math.cos(f.phi || 0.6));
    const sgn = (Math.floor((f.phi || 0.6) * 1000) % 2) ? -1 : 1;
    const mm = (LIMB[C.kind] && LIMB[C.kind].mm) || 900;
    return {
      ang: rad((f.ang || 0) * share) * sgn,
      shift: (f.shift || 0.4) * (C.lat ? 0.5 : 0.75) * widthPx * (sgn > 0 ? 1 : -1),
      short: (f.short || 0) * C.H / mm,
    };
  }

  /* band along a polyline (px) with width fn (px) → polygon with optional jagged caps & transform */
  function band(Pp, wf, u0, u1, capS, capE, xf) {
    const n = Math.max(6, Math.ceil((u1 - u0) * 40));
    const N = Pp.length - 1;
    const at = (u) => {
      const f = clamp(u, 0, 1) * N, i = Math.min(N - 1, Math.floor(f)), t = f - i;
      const a = Pp[i], b = Pp[i + 1];
      const x = lerp(a[0], b[0], t), y = lerp(a[1], b[1], t);
      let tx = b[0] - a[0], ty = b[1] - a[1]; const l = Math.hypot(tx, ty) || 1; tx /= l; ty /= l;
      return { x, y, tx, ty, nx: -ty, ny: tx };
    };
    const pt = (u, s) => { const q = at(u), w = wf(clamp(u, 0, 1)); return [q.x + q.nx * s * w, q.y + q.ny * s * w]; };
    const left = [], right = [];
    for (let i = 0; i <= n; i++) { const u = lerp(u0, u1, i / n); left.push(pt(u, -0.5)); right.push(pt(u, 0.5)); }
    const poly = left.slice();
    if (capE) capE.forEach(c => poly.push(pt(u1 + c.du, c.s))); else poly.push(pt(u1, 0));
    for (let i = right.length - 1; i >= 0; i--) poly.push(right[i]);
    if (capS) for (let i = capS.length - 1; i >= 0; i--) poly.push(pt(u0 + capS[i].du, capS[i].s));
    const T = (arr) => (xf ? arr.map(xf) : arr);
    return { poly: T(poly), left: T(left), right: T(right), at };
  }

  function paintBand(g, b, dens = 1, cw = 2, edge = 1, canal = null) {
    const grp = !!g._grp;
    g.save(); g.globalCompositeOperation = addOp(g);
    g.beginPath(); polyPath(g, b.poly); g.fillStyle = col(g, TB, 0.4 * dens); g.fill();
    g.restore();
    if (canal) {     // the medullary canal is less dense than the cortex around it
      g.save();
      if (grp) { g.globalCompositeOperation = 'source-over'; g.fillStyle = col(g, TB, 0.4 * dens * 0.72); } else { g.globalCompositeOperation = 'destination-out'; g.fillStyle = 'rgba(0,0,0,.22)'; }
      g.filter = 'blur(1.5px)'; g.beginPath(); polyPath(g, canal.poly); g.fill(); g.restore();
    }
    g.save(); g.globalCompositeOperation = addOp(g);
    g.lineJoin = 'round'; g.lineCap = 'butt';
    g.strokeStyle = col(g, TC, grp ? (0.4 + 0.12 * edge) * dens : 0.13 * dens * edge); g.lineWidth = cw * 2.2;
    g.beginPath(); polyPath(g, b.left, false); g.stroke();
    g.beginPath(); polyPath(g, b.right, false); g.stroke();
    g.strokeStyle = col(g, TC, grp ? (0.4 + 0.26 * edge) * dens : 0.26 * dens * edge); g.lineWidth = cw;
    g.beginPath(); polyPath(g, b.left, false); g.stroke();
    g.beginPath(); polyPath(g, b.right, false); g.stroke();
    g.restore();
  }

  function jagCap(f, wPx, lenPx, comminuted) {
    const R = f.rnd || Math.random;
    const obl = (R() - 0.5) * (comminuted ? 1.6 : 1.1);
    const pts = [];
    const n = comminuted ? 9 : 7;
    for (let i = 0; i < n; i++) {
      const s = -0.5 + i / (n - 1);
      const jag = (i === 0 || i === n - 1) ? 0 : (R() - 0.5) * (comminuted ? 0.3 : 0.14);
      pts.push({ s, du: ((obl * s + jag) * wPx) / lenPx });
    }
    return pts;
  }

  /* a long bone along a straight or curved axis (normalized points), profile wf(u) in W units */
  function longBone(C, key, axisPts, wf, u0 = 0, u1 = 1, o = {}) {
    const g = C.gb, dens = o.dens || 1;
    const rs = resample(axisPts.map(p => [C.X(p[0]), C.Y(p[1])]), 48);
    const Pp = rs.pts, lenPx = rs.len;
    const wpx = (u) => C.S(wf(u));
    const cw = Math.max(1.2, C.S(wf(0.5)) * (o.cortex || 0.16));
    const list = C.fx.filter(f => (f.axes || []).includes(key));
    const canalW = (u) => wpx(u) * 0.5 * sstep(0.08, 0.25, u) * (1 - sstep(0.75, 0.92, u));
    const canalOf = (a, b2, xf) => (o.canal === false ? null : band(Pp, canalW, Math.max(a, 0.1), Math.min(b2, 0.9), null, null, xf || null));
    if (!list.length) {
      if (C.only !== 'distal') paintBand(g, band(Pp, wpx, u0, u1, null, null, null), dens, cw, 1, canalOf(u0, u1));
      return;
    }
    const f = list[0];
    // fracture position along the axis
    let best = 0, bd = 1e9;
    for (let i = 0; i < Pp.length; i++) { const d = Math.hypot(Pp[i][0] - C.X(f.p.x), Pp[i][1] - C.Y(f.p.y)); if (d < bd) { bd = d; best = i; } }
    const uf = clamp(best / (Pp.length - 1), u0 + 0.05, u1 - 0.05);
    const wAt = wpx(uf);
    const comm = f.kind === 'comminuted';
    const cap = f._cap || (f._cap = jagCap(f, wAt, lenPx, comm));
    const gapU = 1.6 / lenPx;
    const capD = cap.map(c => ({ s: c.s, du: c.du + gapU }));
    const b0 = band(Pp, wpx, u0, uf, null, cap, null);
    const q = b0.at(uf);
    const mkXf = (m) => (p) => {
      const ca = Math.cos(m.ang), sa = Math.sin(m.ang);
      const dx = p[0] - q.x, dy = p[1] - q.y;
      return [q.x + dx * ca - dy * sa + q.nx * m.shift - q.tx * m.short, q.y + dx * sa + dy * ca + q.ny * m.shift - q.ty * m.short];
    };
    if (C.only !== 'distal') paintBand(g, b0, dens, cw, 1, uf - 0.02 > 0.1 ? canalOf(u0, uf - 0.02) : null);
    const drawDistal = (gg, m) => {
      let tg = gg;
      if (!gg._grp) { const tmp = C._dtmp || (C._dtmp = mk(C.W, C.H)); tg = tmp.getContext('2d'); tg._grp = true; tg.clearRect(0, 0, C.W, C.H); }
      const b1 = band(Pp, wpx, uf, u1, capD, null, mkXf(m));
      paintBand(tg, b1, dens, cw, 1, uf + 0.02 < 0.9 ? canalOf(uf + 0.02, u1, mkXf(m)) : null);
      if (o.distalExtra) o.distalExtra(tg, mkXf(m));
      if (tg !== gg) { gg.save(); gg.globalCompositeOperation = 'lighter'; gg.drawImage(C._dtmp, 0, 0); gg.restore(); }
    };
    const m = motion(C, f, wAt);
    if (C.live && C.live.id === f.id && C.only === 'static') {
      C.distal = C.distal || [];
      C.distal.push({ draw: drawDistal, f, q, wAt });
    } else if (C.only !== 'static' || !C.live || C.live.id !== f.id) {
      if (C.only !== 'distal') drawDistal(g, m);
    }
    if (C.only === 'distal') return;
    // fracture site extras
    if (comm) {
      const R = f.rnd;
      for (let i = 0; i < 4; i++) {
        const a = R() * TAU, r = wAt * (0.3 + R() * 0.5), cx = q.x + Math.cos(a) * r, cy = q.y + Math.sin(a) * r * 0.6, s = wAt * (0.08 + R() * 0.12);
        g.save(); g.globalCompositeOperation = 'lighter'; g.beginPath();
        g.moveTo(cx - s, cy); g.lineTo(cx, cy - s * 0.7); g.lineTo(cx + s * 0.9, cy + s * 0.2); g.lineTo(cx - s * 0.2, cy + s * 0.8); g.closePath();
        g.fillStyle = CORT(0.35); g.fill(); g.restore();
      }
    }
    if (f.heal > 30 && (f.cast || f.splint || f.reduced)) {
      const a = Math.min(0.22, f.heal / 400);
      const gr = g.createRadialGradient(q.x, q.y, 0, q.x, q.y, wAt * 1.1);
      gr.addColorStop(0, BONE(a)); gr.addColorStop(1, BONE(0));
      g.save(); g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.beginPath(); g.ellipse(q.x, q.y, wAt * 0.95, wAt * 1.25, Math.atan2(q.ty, q.tx), 0, TAU); g.fill(); g.restore();
    }
    if (f.kind === 'open') {
      const gs = C.gs, R = f.rnd;
      gs.save(); gs.globalCompositeOperation = 'destination-out'; gs.strokeStyle = 'rgba(0,0,0,.55)'; gs.lineCap = 'round';
      for (let i = 0; i < 6; i++) {
        const a = R() * TAU, r = wAt * (0.8 + R() * 0.9);
        gs.lineWidth = 1 + R() * 2.5; gs.beginPath(); gs.moveTo(q.x + Math.cos(a) * r, q.y + Math.sin(a) * r);
        gs.lineTo(q.x + Math.cos(a) * (r + wAt * 0.5), q.y + Math.sin(a) * (r + wAt * 0.3)); gs.stroke();
      }
      gs.restore();
    }
  }

  function ellBone(C, x, y, rx, ry, rot = 0, dens = 1, edge = 1) {
    const g = C.gb; if (C.only === 'distal') return;
    g.save(); g.globalCompositeOperation = addOp(g);
    g.beginPath(); g.ellipse(C.X(x), C.Y(y), C.S(rx), C.S(ry), rot, 0, TAU);
    g.fillStyle = col(g, TB, 0.4 * dens); g.fill();
    g.strokeStyle = col(g, TC, g._grp ? (0.4 + 0.22 * edge) * dens : 0.24 * dens * edge); g.lineWidth = Math.max(1, C.S(Math.min(rx, ry)) * 0.14); g.stroke();
    g.restore();
  }
  function blobBone(C, pts, dens = 1, edge = 1, smooth = true) {
    const g = C.gb; if (C.only === 'distal') return;
    const P = pts.map(C.P);
    g.save(); g.globalCompositeOperation = addOp(g); g.beginPath(); (smooth ? smoothPath : polyPath)(g, P);
    g.fillStyle = col(g, TB, 0.4 * dens); g.fill(); g.strokeStyle = col(g, TC, g._grp ? (0.4 + 0.22 * edge) * dens : 0.24 * dens * edge); g.lineWidth = Math.max(1, C.W * 0.004); g.lineJoin = 'round'; g.stroke(); g.restore();
  }
  function lineBone(C, pts, w, dens = 1, smooth = false) {     // a bright line (cortex only), e.g. skull tables
    const g = C.gb; if (C.only === 'distal') return;
    g.save(); g.globalCompositeOperation = addOp(g); g.strokeStyle = col(g, TC, g._grp ? 0.62 * dens : 0.4 * dens); g.lineWidth = C.S(w); g.lineCap = 'round'; g.lineJoin = 'round';
    g.beginPath(); (smooth ? smoothPath : polyPath)(g, pts.map(C.P), false); g.stroke(); g.restore();
  }
  function tissue(C, pts, a, blur = 0, smooth = true) {
    if (C.only === 'distal') return;
    const g = C.gs; g.save(); if (blur) g.filter = `blur(${blur}px)`;
    g.beginPath(); (smooth ? smoothPath : polyPath)(g, pts.map(C.P)); g.fillStyle = TIS(a); g.fill(); g.restore();
  }
  function carve(C, layer, pts, a, blur = 0, smooth = true) {
    if (C.only === 'distal') return;
    const g = layer === 'bone' ? C.gb : C.gs;
    g.save(); g.globalCompositeOperation = 'destination-out'; if (blur) g.filter = `blur(${blur}px)`;
    g.beginPath(); (smooth ? smoothPath : polyPath)(g, pts.map(C.P)); g.fillStyle = `rgba(0,0,0,${a})`; g.fill(); g.restore();
  }
  function carveEll(C, layer, x, y, rx, ry, a, blur = 0, rot = 0) {
    if (C.only === 'distal') return;
    const g = layer === 'bone' ? C.gb : C.gs;
    g.save(); g.globalCompositeOperation = 'destination-out'; if (blur) g.filter = `blur(${blur}px)`;
    g.beginPath(); g.ellipse(C.X(x), C.Y(y), C.S(rx), C.S(ry), rot, 0, TAU); g.fillStyle = `rgba(0,0,0,${a})`; g.fill(); g.restore();
  }
  // rows [y, xLeft, xRight] → closed outline
  function rowsOutline(rows) {
    const l = rows.map(r => [r[1], r[0]]), rr = rows.slice().reverse().map(r => [r[2], r[0]]);
    return l.concat(rr);
  }
  function limbTissue(C, rows, a = 0.3) {
    tissue(C, rowsOutline(rows), a, 2);
    // the fat stripe under the skin is darker than muscle
    tissue(C, rowsOutline(rows.map(r => [r[0], r[1] + (r[2] - r[1]) * 0.07, r[2] - (r[2] - r[1]) * 0.07])), a * 0.45, 5);
  }
  function tube(C, a, b, w, dens = 1, key = null, o = {}) {      // short straight bone
    const axis = [a, b];
    longBone(C, key || ('_' + a.join() + b.join()), axis, typeof w === 'function' ? w : () => w, 0, 1, Object.assign({ dens }, o));
  }

  /* generic fracture line for flat / irregular bones */
  function crack(C, f, len, o = {}) {
    if (C.only === 'distal') return;
    const g = C.gb, R = f.rnd;
    const x = C.X(f.p.x), y = C.Y(f.p.y);
    const ang = o.angle !== undefined ? o.angle : R() * Math.PI;
    const L = C.S(len);
    const pts = [];
    const n = 9;
    for (let i = 0; i <= n; i++) {
      const t = i / n - 0.5;
      const j = (i === 0 || i === n) ? 0 : (R() - 0.5) * L * 0.12;
      pts.push([x + Math.cos(ang) * t * L - Math.sin(ang) * j, y + Math.sin(ang) * t * L + Math.cos(ang) * j]);
    }
    g.save(); g.globalCompositeOperation = 'destination-out'; g.strokeStyle = 'rgba(0,0,0,.95)'; g.lineWidth = Math.max(1.4, C.W * (f.disp ? 0.0045 : 0.0028)); g.lineJoin = 'round';
    g.beginPath(); polyPath(g, pts, false); g.stroke();
    if (o.branches !== false) {
      for (let k = 0; k < 2; k++) {
        const s = pts[2 + Math.floor(R() * (n - 3))], a2 = ang + (R() - 0.5) * 1.8, l2 = L * (0.2 + R() * 0.25);
        g.lineWidth = Math.max(1, C.W * 0.0022); g.beginPath(); g.moveTo(s[0], s[1]);
        g.lineTo(s[0] + Math.cos(a2) * l2 * 0.5 + (R() - 0.5) * 3, s[1] + Math.sin(a2) * l2 * 0.5 + (R() - 0.5) * 3); g.lineTo(s[0] + Math.cos(a2) * l2, s[1] + Math.sin(a2) * l2); g.stroke();
      }
    }
    g.restore();
    if (f.disp) {      // the edges overlap: a bright double contour next to the gap
      const off = C.S(0.006);
      g.save(); g.globalCompositeOperation = 'lighter'; g.strokeStyle = CORT(0.5); g.lineWidth = Math.max(1, C.W * 0.003);
      g.beginPath(); polyPath(g, pts.map(p => [p[0] - Math.sin(ang) * off, p[1] + Math.cos(ang) * off]), false); g.stroke(); g.restore();
    }
  }
  const fxFor = (C, pred) => C.fx.filter(pred);

  /* ── vertebrae ── */
  function vertAP(C, cx, cy, w, h, f, o = {}) {
    const g = C.gb; if (C.only === 'distal') return;
    let hh = h, dx = 0, dens = o.dens || 1;
    if (f) { hh = h * (f.disp ? 0.58 : 0.78); dens *= 1.35; dx = f.disp ? w * 0.18 : 0; }
    const X = C.X(cx) + C.S(dx), Y = C.Y(cy), Wd = C.S(w), Hh = C.S(hh), r = Math.min(Wd, Hh) * 0.22;
    g.save(); g.globalCompositeOperation = 'lighter';
    g.beginPath(); g.moveTo(X - Wd / 2 + r, Y - Hh / 2); g.lineTo(X + Wd / 2 - r, Y - Hh / 2); g.quadraticCurveTo(X + Wd / 2 + r * 0.4, Y, X + Wd / 2 - r, Y + Hh / 2);
    g.lineTo(X - Wd / 2 + r, Y + Hh / 2); g.quadraticCurveTo(X - Wd / 2 - r * 0.4, Y, X - Wd / 2 + r, Y - Hh / 2); g.closePath();
    g.fillStyle = BONE(0.34 * dens); g.fill(); g.strokeStyle = CORT(0.24 * dens); g.lineWidth = Math.max(1, Wd * 0.05); g.stroke();
    // pedicles
    g.strokeStyle = CORT(0.2 * dens); g.lineWidth = Math.max(1, Wd * 0.04);
    [-1, 1].forEach(s => { g.beginPath(); g.ellipse(X + s * Wd * 0.3, Y - Hh * 0.12, Wd * 0.09, Hh * 0.2, 0, 0, TAU); g.stroke(); });
    // spinous process
    g.fillStyle = BONE(0.2); g.beginPath(); g.ellipse(X, Y + Hh * 0.05, Wd * 0.06, Hh * 0.28, 0, 0, TAU); g.fill();
    if (o.transverse) { g.fillStyle = BONE(0.16); [-1, 1].forEach(s => { g.beginPath(); g.ellipse(X + s * Wd * (0.5 + o.transverse / 2), Y - Hh * 0.1, Wd * o.transverse / 2, Hh * 0.13, s * 0.15, 0, TAU); g.fill(); }); }
    g.restore();
  }
  function vertLAT(C, cx, cy, w, h, f, o = {}) {
    const g = C.gb; if (C.only === 'distal') return;
    let dens = o.dens || 1, wedge = 0, dx = 0;
    if (f) { dens *= 1.35; wedge = f.disp ? 0.45 : 0.25; dx = f.disp ? -w * 0.16 : 0; }
    const X = C.X(cx) + C.S(dx), Y = C.Y(cy), Wd = C.S(w), Hh = C.S(h);
    const ha = Hh * (1 - wedge), hp = Hh;    // anterior (left) / posterior heights
    g.save(); g.globalCompositeOperation = 'lighter';
    g.beginPath(); g.moveTo(X - Wd / 2, Y - ha / 2); g.lineTo(X + Wd / 2, Y - hp / 2); g.lineTo(X + Wd / 2, Y + hp / 2); g.lineTo(X - Wd / 2, Y + ha / 2); g.closePath();
    g.fillStyle = BONE(0.34 * dens); g.fill(); g.strokeStyle = CORT(0.24 * dens); g.lineWidth = Math.max(1, Wd * 0.05); g.lineJoin = 'round'; g.stroke();
    // posterior elements: pedicle → facet → spinous process
    const sp = o.spine || 0.9;
    g.fillStyle = BONE(0.16); g.strokeStyle = CORT(0.22); g.lineWidth = Math.max(1, Wd * 0.035);
    g.beginPath(); g.moveTo(X + Wd / 2, Y - hp * 0.35); g.lineTo(X + Wd * 0.95, Y - hp * 0.25); g.lineTo(X + Wd * (0.95 + sp), Y + hp * (0.3 + sp * 0.35));
    g.lineTo(X + Wd * (0.85 + sp), Y + hp * (0.55 + sp * 0.35)); g.lineTo(X + Wd * 0.85, Y + hp * 0.35); g.lineTo(X + Wd / 2, Y + hp * 0.25); g.closePath(); g.fill(); g.stroke();
    g.restore();
  }

  /* ── fragments (metal is radio-opaque: pure white with a hard edge) ── */
  function drawFragments(C) {
    const g = C.gm;
    for (const f of C.frags) {
      const x = C.X(f.p.x), y = C.Y(f.p.y), R = mulberry(hash(String(f.id) + (C.film.seed || 1) + C.which));
      const rot = (f.rot || 0) + (C.lat ? 1.1 : 0);
      g.save(); g.fillStyle = '#f6fbff';
      if (f.shape === 'bullet') {
        const len = C.S(0.026), wd = C.S(0.011);
        g.translate(x, y); g.rotate(rot);
        g.beginPath(); g.moveTo(-len / 2, -wd / 2); g.lineTo(len * 0.18, -wd / 2); g.quadraticCurveTo(len / 2, -wd / 2, len / 2 + wd * 0.2, 0);
        g.quadraticCurveTo(len / 2, wd / 2, len * 0.18, wd / 2); g.lineTo(-len / 2, wd / 2); g.closePath(); g.fill();
        // deformed / fragmented bullet → small spatter
        for (let i = 1; i < Math.min(6, (f.n || 1) * 2); i++) { g.beginPath(); g.arc((R() - 0.5) * len * 2.2, (R() - 0.5) * len * 1.6, C.S(0.002 + R() * 0.003), 0, TAU); g.fill(); }
      } else {
        for (let i = 0; i < Math.max(1, f.n || 1); i++) {
          const ox = i ? (R() - 0.5) * C.S(0.06) : 0, oy = i ? (R() - 0.5) * C.S(0.06) : 0, s = C.S(i ? 0.006 + R() * 0.006 : 0.012);
          g.beginPath(); const k = 5 + Math.floor(R() * 3);
          for (let j = 0; j < k; j++) { const a = j / k * TAU + R() * 0.5, r = s * (0.5 + R() * 0.7); const px = x + ox + Math.cos(a + rot) * r, py = y + oy + Math.sin(a + rot) * r; j ? g.lineTo(px, py) : g.moveTo(px, py); }
          g.closePath(); g.fill();
        }
      }
      g.restore();
    }
  }

  /* ═══════════════ ANATOMY PER VIEW ═══════════════ */
  const ANAT = {
    leg(C) {
      const L = LIMB.leg[C.lat ? 'lat' : 'ap'];
      const ax = (k) => [[L[k][0], L[k][1]], [L[k][2], L[k][3]]];
      if (!C.lat) {
        limbTissue(C, [[-0.02, 0.29, 0.73], [0.12, 0.31, 0.71], [0.26, 0.335, 0.685], [0.42, 0.385, 0.625], [0.5, 0.39, 0.62], [0.6, 0.372, 0.628], [0.72, 0.4, 0.6], [0.86, 0.432, 0.572], [0.9, 0.42, 0.59], [0.96, 0.415, 0.6], [1.02, 0.42, 0.6]]);
        // pelvis corner: ilium with the acetabular roof, pubic ramus around the obturator foramen (medial = viewer's right)
        group(C, () => {
          blobBone(C, [[0.52, -0.03], [0.86, -0.03], [0.88, 0.03], [0.8, 0.066], [0.7, 0.072], [0.635, 0.04], [0.6, 0.012], [0.56, 0.0]], 0.62);
          blobBone(C, [[0.63, 0.08], [0.72, 0.09], [0.86, 0.1], [0.92, 0.12], [0.92, 0.16], [0.8, 0.15], [0.7, 0.14], [0.645, 0.115]], 0.55);
          lineBone(C, [[0.53, 0.035], [0.56, 0.008], [0.6, 0.0], [0.64, 0.018], [0.65, 0.05]], 0.008, 1.1, true);
        });
        // femur: head, neck, trochanters, shaft and condyles are one bone
        group(C, () => {
          ellBone(C, 0.585, 0.058, 0.046, 0.046, 0, 1);
          blobBone(C, [[0.555, 0.05], [0.59, 0.08], [0.57, 0.11], [0.545, 0.14], [0.51, 0.135], [0.5, 0.1], [0.52, 0.07]], 0.95);
          blobBone(C, [[0.448, 0.072], [0.48, 0.06], [0.515, 0.075], [0.522, 0.12], [0.49, 0.145], [0.462, 0.12]], 0.95);
          ellBone(C, 0.567, 0.135, 0.017, 0.011, 0.3, 1);
          longBone(C, 'femur', ax('femur'), (u) => 0.066 + 0.03 * sstep(0.8, 1, u) + 0.014 * (1 - sstep(0, 0.12, u)), 0.06, 0.94, { cortex: 0.2 });
          blobBone(C, [[0.464, 0.4], [0.448, 0.43], [0.441, 0.455], [0.452, 0.472], [0.48, 0.477], [0.5, 0.47], [0.507, 0.46], [0.514, 0.47], [0.535, 0.478], [0.565, 0.474], [0.575, 0.455], [0.568, 0.43], [0.55, 0.4]], 1);
        });
        ellBone(C, 0.508, 0.44, 0.03, 0.038, 0, 0.42);          // patella seen through the femur
        group(C, () => {
          blobBone(C, [[0.432, 0.517], [0.46, 0.507], [0.49, 0.508], [0.497, 0.498], [0.503, 0.507], [0.512, 0.497], [0.52, 0.507], [0.55, 0.506], [0.578, 0.515], [0.574, 0.536], [0.545, 0.556], [0.47, 0.556], [0.438, 0.537]], 1);
          longBone(C, 'tibia', ax('tibia'), (u) => 0.058 + 0.05 * (1 - sstep(0, 0.2, u)) + 0.022 * sstep(0.82, 1, u), 0.04, 0.99, { cortex: 0.22 });
          blobBone(C, [[0.47, 0.846], [0.53, 0.846], [0.54, 0.866], [0.532, 0.878], [0.512, 0.869], [0.48, 0.869], [0.468, 0.86]], 1);
        });
        group(C, () => {
          ellBone(C, 0.447, 0.53, 0.019, 0.018, 0, 1);
          longBone(C, 'fibula', ax('fibula'), (u) => 0.021 + 0.01 * (1 - sstep(0, 0.08, u)) + 0.014 * sstep(0.86, 1, u), 0.02, 1.0, { dens: 0.9 });
          ellBone(C, 0.452, 0.866, 0.014, 0.018, 0, 1);
        });
        // ankle & foot seen from the front (foreshortened)
        blobBone(C, [[0.462, 0.88], [0.5, 0.872], [0.535, 0.88], [0.538, 0.9], [0.5, 0.905], [0.465, 0.9]], 0.95);     // talus
        ellBone(C, 0.497, 0.918, 0.045, 0.018, 0, 0.55);                                                            // calcaneus behind
        group(C, () => { [[0.455, 0.92], [0.48, 0.918], [0.505, 0.92], [0.53, 0.922]].forEach(p => ellBone(C, p[0], p[1], 0.014, 0.012, 0, 0.8)); });
        for (let i = 0; i < 5; i++) {
          const x = 0.446 + 0.026 * i, spread = (i - 2) * 0.012;
          tube(C, [x, 0.93], [x + spread, 0.968], (u) => 0.012 + 0.005 * sstep(0.75, 1, u), 0.7);
          tube(C, [x + spread, 0.972], [x + spread * 1.25, 0.99], 0.009, 0.6);
        }
      } else {
        limbTissue(C, [[-0.02, 0.29, 0.72], [0.2, 0.33, 0.69], [0.42, 0.375, 0.632], [0.5, 0.382, 0.622], [0.6, 0.41, 0.648], [0.72, 0.43, 0.612], [0.84, 0.448, 0.578], [0.88, 0.45, 0.6]]);
        tissue(C, [[0.47, 0.845], [0.6, 0.84], [0.67, 0.88], [0.695, 0.93], [0.66, 0.962], [0.4, 0.976], [0.2, 0.976], [0.115, 0.958], [0.12, 0.935], [0.3, 0.9], [0.42, 0.868]], 0.3, 2);
        group(C, () => {
          blobBone(C, [[0.49, -0.02], [0.58, -0.02], [0.6, 0.05], [0.585, 0.11], [0.545, 0.12], [0.505, 0.09], [0.49, 0.04]], 0.9);
          ellBone(C, 0.528, 0.03, 0.04, 0.04, 0, 0.6);
          longBone(C, 'femur', [[0.52, 0.075], [0.508, 0.27], [0.5, 0.465]], (u) => 0.07 + 0.035 * sstep(0.8, 1, u), 0.06, 0.93, { cortex: 0.2 });
          blobBone(C, [[0.462, 0.42], [0.452, 0.45], [0.47, 0.49], [0.52, 0.5], [0.565, 0.485], [0.574, 0.45], [0.556, 0.42]], 1);
        });
        ellBone(C, 0.422, 0.45, 0.022, 0.048, -0.15, 1.05);                 // patella
        group(C, () => {
          blobBone(C, [[0.45, 0.512], [0.5, 0.505], [0.552, 0.51], [0.556, 0.53], [0.53, 0.56], [0.47, 0.565], [0.448, 0.535]], 1);
          ellBone(C, 0.462, 0.552, 0.014, 0.022, 0, 1);                       // tibial tuberosity
          longBone(C, 'tibia', ax('tibia'), (u) => 0.058 + 0.04 * (1 - sstep(0, 0.18, u)) + 0.02 * sstep(0.85, 1, u), 0.04, 0.99, { cortex: 0.22 });
        });
        group(C, () => {
          ellBone(C, 0.537, 0.53, 0.018, 0.02, 0, 1);
          longBone(C, 'fibula', ax('fibula'), (u) => 0.022 + 0.008 * (1 - sstep(0, 0.08, u)) + 0.01 * sstep(0.86, 1, u), 0.02, 1, { dens: 0.75 });
        });
        // foot from the side: talus, calcaneus, midfoot, metatarsals, toes
        blobBone(C, [[0.49, 0.856], [0.52, 0.846], [0.552, 0.856], [0.556, 0.876], [0.53, 0.888], [0.495, 0.882], [0.482, 0.87]], 1);
        blobBone(C, [[0.53, 0.885], [0.565, 0.878], [0.61, 0.882], [0.65, 0.898], [0.662, 0.922], [0.65, 0.942], [0.615, 0.945], [0.57, 0.938], [0.535, 0.922], [0.522, 0.902]], 1);
        group(C, () => { ellBone(C, 0.468, 0.886, 0.02, 0.016, 0.2, 1); ellBone(C, 0.445, 0.902, 0.02, 0.016, 0.1, 1); ellBone(C, 0.49, 0.91, 0.024, 0.018, 0, 1); });
        for (let i = 0; i < 5; i++) {
          const y0 = 0.902 + 0.0035 * i, y1 = 0.93 + 0.004 * i, x1 = 0.255 + 0.01 * i;
          group(C, () => {
            tube(C, [0.432 - 0.005 * i, y0], [x1, y1], (u) => 0.014 + 0.007 * (1 - sstep(0, 0.12, u)) + 0.005 * sstep(0.85, 1, u), 0.45);
            tube(C, [x1 - 0.004, y1 + 0.002], [x1 - 0.05 + i * 0.004, y1 + 0.01], 0.011, 0.42);
            tube(C, [x1 - 0.053 + i * 0.004, y1 + 0.011], [x1 - 0.075 + i * 0.005, y1 + 0.016], 0.009, 0.4);
          });
        }
      }
      castSleeve(C, 'leg');
    },

    arm(C) {
      const L = LIMB.arm[C.lat ? 'lat' : 'ap'];
      const ax = (k) => [[L[k][0], L[k][1]], [L[k][2], L[k][3]]];
      limbTissue(C, [[-0.02, 0.33, 0.69], [0.06, 0.36, 0.66], [0.15, 0.38, 0.625], [0.4, 0.388, 0.615], [0.46, 0.392, 0.612], [0.55, 0.402, 0.6], [0.75, 0.428, 0.575], [0.8, 0.432, 0.57], [0.84, 0.41, 0.588], [0.89, 0.41, 0.592]]);
      if (!C.lat) {
        // fingers (soft tissue)
        [[0.405, 0.885, 0.385, 0.935], [0.452, 0.92, 0.442, 0.995], [0.495, 0.925, 0.494, 1.01], [0.53, 0.918, 0.538, 0.995], [0.562, 0.905, 0.578, 0.965]].forEach(f => tissue(C, capsule(f, 0.022), 0.26, 2));
        ellBone(C, 0.508, 0.062, 0.05, 0.05, 0, 1.05);
        ellBone(C, 0.462, 0.082, 0.02, 0.026, 0, 0.8);
        blobBone(C, [[0.43, 0.015], [0.5, 0.0], [0.58, 0.012], [0.56, 0.032], [0.47, 0.035]], 0.7);
        blobBone(C, [[0.57, 0.035], [0.6, 0.04], [0.62, 0.1], [0.68, 0.16], [0.66, 0.18], [0.6, 0.12], [0.575, 0.1]], 0.55);
        tube(C, [0.56, 0.02], [0.78, -0.01], 0.026, 0.7);
        longBone(C, 'humerus', ax('humerus'), (u) => 0.048 + 0.012 * (1 - sstep(0, 0.12, u)) + 0.075 * sstep(0.82, 1, u), 0.06, 0.97, { cortex: 0.2 });
        blobBone(C, [[0.452, 0.405], [0.47, 0.425], [0.49, 0.44], [0.505, 0.455], [0.522, 0.442], [0.545, 0.428], [0.562, 0.408], [0.57, 0.425], [0.555, 0.452], [0.53, 0.465], [0.48, 0.465], [0.455, 0.448], [0.442, 0.425]], 0.9);
        group(C, () => { ellBone(C, 0.468, 0.476, 0.022, 0.012, 0, 1); longBone(C, 'radius', ax('radius'), (u) => 0.03 + 0.006 * (1 - sstep(0, 0.06, u)) + 0.034 * sstep(0.84, 1, u), 0, 1, { cortex: 0.2 }); });
        group(C, () => { blobBone(C, [[0.522, 0.44], [0.55, 0.445], [0.565, 0.47], [0.552, 0.49], [0.53, 0.485]], 0.9); longBone(C, 'ulna', ax('ulna'), (u) => 0.025 + 0.018 * (1 - sstep(0, 0.1, u)) + 0.006 * sstep(0.9, 1, u), 0, 1, { cortex: 0.2 }); });
        [[0.462, 0.805, 0.02, 0.014], [0.495, 0.804, 0.017, 0.015], [0.524, 0.808, 0.015, 0.014], [0.542, 0.804, 0.009, 0.009],
          [0.44, 0.83, 0.016, 0.014], [0.467, 0.833, 0.013, 0.013], [0.496, 0.834, 0.017, 0.018], [0.528, 0.83, 0.016, 0.016]].forEach(b => ellBone(C, b[0], b[1], b[2], b[3], 0, 0.85));
        const mc = [[0.445, 0.845, 0.405, 0.885], [0.47, 0.85, 0.455, 0.915], [0.497, 0.852, 0.495, 0.92], [0.522, 0.85, 0.53, 0.912], [0.545, 0.845, 0.565, 0.9]];
        mc.forEach((m, i) => {
          tube(C, [m[0], m[1]], [m[2], m[3]], 0.015, 0.85);
          const dx = (m[2] - m[0]), dy = (m[3] - m[1]), l = Math.hypot(dx, dy), ux = dx / l, uy = dy / l;
          const segs = i === 0 ? [0.035, 0.026] : [0.04, 0.026, 0.018];
          let x = m[2], y = m[3];
          segs.forEach((s, k) => { const x2 = x + ux * s * (1 - k * 0.04), y2 = y + uy * s * 1.25; tube(C, [x + ux * 0.004, y + uy * 0.004], [x2, y2], 0.012 - k * 0.002, 0.7); x = x2; y = y2; });
        });
      } else {
        tissue(C, [[0.43, 0.82], [0.5, 0.83], [0.53, 0.88], [0.52, 0.95], [0.5, 1.02], [0.45, 1.02], [0.46, 0.94], [0.42, 0.9], [0.4, 0.86]], 0.28, 2);
        ellBone(C, 0.5, 0.06, 0.05, 0.05, 0, 1);
        longBone(C, 'humerus', ax('humerus'), (u) => 0.05 + 0.01 * (1 - sstep(0, 0.12, u)) + 0.04 * sstep(0.84, 1, u), 0.06, 0.97, { cortex: 0.2 });
        ellBone(C, 0.5, 0.437, 0.034, 0.03, 0, 1.0);
        blobBone(C, [[0.515, 0.43], [0.545, 0.425], [0.555, 0.45], [0.54, 0.47], [0.515, 0.46]], 0.9);
        longBone(C, 'radius', ax('radius'), (u) => 0.03 + 0.03 * sstep(0.84, 1, u), 0, 1, { cortex: 0.2 });
        longBone(C, 'ulna', ax('ulna'), (u) => 0.026 + 0.018 * (1 - sstep(0, 0.1, u)), 0, 1, { cortex: 0.2 });
        ellBone(C, 0.49, 0.818, 0.03, 0.022, 0, 1.1);
        for (let i = 0; i < 4; i++) tube(C, [0.495 + i * 0.006, 0.84], [0.485 + i * 0.008, 0.93], 0.016, 0.55);
        tube(C, [0.47, 0.835], [0.43, 0.895], 0.016, 0.8); tube(C, [0.43, 0.895], [0.41, 0.94], 0.012, 0.7);
        for (let i = 0; i < 4; i++) tube(C, [0.485 + i * 0.008, 0.93], [0.47 + i * 0.008, 1.0], 0.012, 0.5);
      }
      castSleeve(C, 'arm');
    },

    chest(C) {
      const fx = C.fx, hemo = C.conds.find(c => c.k === 'hemo'), ptx = C.conds.find(c => c.k === 'ptx');
      if (!C.lat) {
        const shift = ptx && ptx.tension ? (ptx.side === 'right' ? 0.05 : -0.05) : 0;
        // torso + arms + neck
        tissue(C, [[0.36, -0.02], [0.64, -0.02], [0.66, 0.06], [0.86, 0.1], [0.97, 0.16], [1.02, 0.3], [1.02, 1.02], [-0.02, 1.02], [-0.02, 0.3], [0.03, 0.16], [0.14, 0.1], [0.34, 0.06]], 0.62, 4);
        // lungs (air = dark)
        const rl = [[0.33, 0.1], [0.26, 0.13], [0.17, 0.25], [0.13, 0.45], [0.12, 0.66], [0.115, 0.755], [0.2, 0.705], [0.3, 0.665], [0.4, 0.69], [0.44 + shift, 0.71], [0.43 + shift, 0.55], [0.44 + shift, 0.4], [0.45 + shift, 0.25], [0.43 + shift * 0.5, 0.12]];
        const ll = [[0.67, 0.1], [0.74, 0.13], [0.83, 0.25], [0.87, 0.45], [0.88, 0.68], [0.885, 0.77], [0.8, 0.72], [0.7, 0.695], [0.64 + shift, 0.705], [0.7 + shift, 0.63], [0.67 + shift, 0.5], [0.59 + shift, 0.41], [0.565 + shift, 0.28], [0.57 + shift * 0.5, 0.12]];
        const lungs = { right: rl, left: ll };
        const collapse = (side) => (ptx && ptx.side === side ? clamp((ptx.size || 25) / 100 + (ptx.tension ? 0.3 : 0), 0.08, 0.6) : 0);
        Object.entries(lungs).forEach(([side, pts]) => {
          carve(C, 'soft', pts, 0.93, 6);
          const col = collapse(side);
          // vascular markings from the hilum (absent where the lung collapsed away from the wall)
          const hx = side === 'right' ? 0.43 + shift : 0.57 + shift, hy = 0.42;
          const g = C.gs; g.save(); g.beginPath(); smoothPath(g, pts.map(C.P)); g.clip();
          g.globalCompositeOperation = 'lighter'; g.strokeStyle = TIS(0.16); g.lineCap = 'round';
          const R = mulberry(hash(side + (C.film.seed || 1)));
          for (let i = 0; i < 26; i++) {
            const a = (side === 'right' ? Math.PI : 0) + (R() - 0.5) * 2.4 * (side === 'right' ? -1 : 1);
            let x = C.X(hx), y = C.Y(hy), w = C.S(0.006), len = C.S(0.05 + R() * 0.06), dir = a;
            for (let s = 0; s < 5; s++) {
              const nx = x + Math.cos(dir) * len, ny = y + Math.sin(dir) * len * 1.1;
              g.lineWidth = w; g.beginPath(); g.moveTo(x, y); g.lineTo(nx, ny); g.stroke();
              x = nx; y = ny; w *= 0.7; len *= 0.8; dir += (R() - 0.5) * 0.6;
            }
          }
          g.restore();
          if (col > 0) {
            // pneumothorax: no lung markings beyond the visceral pleural line
            const wallX = side === 'right' ? 0.13 : 0.87, inX = side === 'right' ? 0.13 + col * 0.32 : 0.87 - col * 0.32;
            const edge = [[inX, 0.14], [lerp(inX, wallX, -0.2), 0.3], [lerp(inX, wallX, -0.1), 0.5], [inX, 0.68]];
            const zone = side === 'right' ? [[0.1, 0.08], ...edge, [0.1, 0.74]] : [[0.9, 0.08], ...edge, [0.9, 0.74]];
            carve(C, 'soft', zone, 0.9, 3);
            const g2 = C.gs; g2.save(); g2.globalCompositeOperation = 'lighter'; g2.strokeStyle = TIS(0.55); g2.lineWidth = Math.max(1, C.W * 0.0028);
            g2.beginPath(); smoothPath(g2, edge.map(C.P), false); g2.stroke(); g2.restore();
          }
        });
        // trachea & bronchi
        carve(C, 'soft', [[0.485 + shift, -0.02], [0.515 + shift, -0.02], [0.517 + shift, 0.29], [0.56 + shift, 0.35], [0.55 + shift, 0.36], [0.5 + shift, 0.31], [0.45 + shift, 0.36], [0.44 + shift, 0.35], [0.483 + shift, 0.29]], 0.55, 2, false);
        // gastric bubble under the left dome
        carveEll(C, 'soft', 0.71, 0.75, 0.05, 0.025, 0.6, 3);
        // haemothorax: dependent white-out with a meniscus, blunted costophrenic angle
        if (hemo) {
          const right = hemo.side === 'right', x0 = right ? 0.1 : 0.9, x1 = right ? 0.46 : 0.54, top = hemo.top || 0.6;
          const pts = right
            ? [[0.1, top - 0.06], [0.2, top - 0.01], [0.3, top + 0.02], [0.42, top + 0.04], [0.47, 0.76], [0.47, 0.8], [0.1, 0.8]]
            : [[0.9, top - 0.06], [0.8, top - 0.01], [0.7, top + 0.02], [0.58, top + 0.04], [0.53, 0.76], [0.53, 0.8], [0.9, 0.8]];
          const g = C.gs; g.save(); g.beginPath(); smoothPath(g, lungs[hemo.side].map(C.P)); g.clip();
          g.filter = 'blur(7px)'; g.beginPath(); smoothPath(g, pts.map(C.P)); g.fillStyle = TIS(0.95); g.fill(); g.restore();
          void x0; void x1;
        }
        // spine through the mediastinum
        for (let lv = 1; lv <= 12; lv++) {
          const y = 0.13 + (lv - 1) * 0.055;
          vertAP(C, 0.5, y, 0.07 + lv * 0.002, 0.042, fx.find(f => f.bone === 't_spine' && f.level === lv), { transverse: 0.03, dens: 0.55 });
        }
        // clavicles & scapulae
        const clav = (s) => [[0.5 + s * 0.045, 0.165], [0.5 + s * 0.15, 0.158], [0.5 + s * 0.24, 0.13], [0.5 + s * 0.33, 0.118]];
        [-1, 1].forEach(s => {
          blobBone(C, [[0.5 + s * 0.3, 0.135], [0.5 + s * 0.4, 0.15], [0.5 + s * 0.42, 0.24], [0.5 + s * 0.37, 0.42], [0.5 + s * 0.32, 0.3]], 0.42);
          longBone(C, 'clav' + (s < 0 ? 'R' : 'L'), clav(s), () => 0.024, 0, 1, { cortex: 0.22 });
          ellBone(C, 0.5 + s * 0.44, 0.17, 0.05, 0.05, 0, 0.9);
        });
        // ribs: posterior (bright) and anterior (faint)
        [-1, 1].forEach(s => {
          for (let n = 1; n <= 10; n++) {
            const y0 = 0.1 + 0.055 * n;
            const xL = Math.min(0.36, 0.25 + 0.012 * n);
            const post = bez([0.5 + s * 0.04, y0], [0.5 + s * 0.17, y0 - 0.04], [0.5 + s * (xL + 0.04), y0 - 0.005], [0.5 + s * (xL + 0.035), y0 + 0.07], 20);
            longBone(C, `rib${s < 0 ? 'R' : 'L'}${n}`, post, () => 0.016, 0, 1, { cortex: 0.22, dens: 0.62, canal: false });
            if (n <= 7) {
              const ant = bez([0.5 + s * (xL + 0.035), y0 + 0.07], [0.5 + s * (xL + 0.02), y0 + 0.12], [0.5 + s * 0.24, y0 + 0.16], [0.5 + s * 0.15, y0 + 0.19], 14);
              longBone(C, `ant${s < 0 ? 'R' : 'L'}${n}`, ant, () => 0.012, 0, 1, { dens: 0.28, canal: false });
            }
          }
        });
        // diaphragm & heart edges are the borders of the carved lungs
      } else {
        tissue(C, [[0.14, -0.02], [0.86, -0.02], [0.9, 0.3], [0.9, 1.02], [0.1, 1.02], [0.1, 0.5], [0.12, 0.2]], 0.44, 4);
        tissue(C, [[0.3, -0.02], [0.7, -0.02], [0.66, 0.16], [0.34, 0.16]], 0.18, 6);
        const lung = [[0.3, 0.1], [0.45, 0.08], [0.62, 0.12], [0.76, 0.24], [0.82, 0.45], [0.83, 0.66], [0.8, 0.77], [0.7, 0.72], [0.55, 0.7], [0.4, 0.71], [0.24, 0.68], [0.2, 0.5], [0.21, 0.3], [0.24, 0.17]];
        carve(C, 'soft', lung, 0.82, 5);
        // heart shadow (anterior, lower)
        tissue(C, [[0.22, 0.44], [0.36, 0.4], [0.52, 0.46], [0.56, 0.6], [0.52, 0.71], [0.3, 0.72], [0.2, 0.66]], 0.42, 6);
        carve(C, 'soft', [[0.33, -0.02], [0.37, -0.02], [0.41, 0.3], [0.45, 0.4], [0.42, 0.41], [0.37, 0.31]], 0.45, 2, false);
        if (hemo) {
          const top = hemo.top || 0.6;
          tissue(C, [[0.45, 0.8], [0.5, top + 0.08], [0.62, top + 0.04], [0.76, top], [0.84, top + 0.06], [0.84, 0.8]], 0.5, 6);
        }
        if (ptx) { lineBone(C, [[0.3, 0.14], [0.26, 0.26], [0.27, 0.38]], 0.003, 0.6, true); }
        // sternum (anterior)
        longBone(C, 'sternum', [[0.205, 0.17], [0.185, 0.35], [0.165, 0.52]], (u) => 0.036 - 0.014 * u + 0.012 * (1 - sstep(0, 0.2, u)), 0, 1, { cortex: 0.12, dens: 0.45, canal: false });
        // thoracic spine (posterior)
        for (let lv = 1; lv <= 12; lv++) {
          const y = 0.13 + (lv - 1) * 0.055, x = 0.70 + 0.03 * Math.sin(Math.PI * (lv - 1) / 11);
          vertLAT(C, x, y, 0.075, 0.042, fx.find(f => f.bone === 't_spine' && f.level === lv), { spine: 0.6, dens: 0.8 });
        }
        // ribs overlapping posteriorly
        for (let n = 1; n <= 10; n++) {
          const y0 = 0.1 + 0.058 * n;
          const r = bez([0.74, y0], [0.84, y0 + 0.01], [0.74, y0 + 0.12], [0.5, y0 + 0.17], 18);
          longBone(C, 'ribLat' + n, r, () => 0.013, 0, 1, { dens: 0.2, canal: false });
        }
        // scapula & humeri
        blobBone(C, [[0.55, 0.15], [0.72, 0.18], [0.66, 0.42], [0.58, 0.3]], 0.35);
      }
      // generic breaks of flat bones on this film (clavicle / rib / sternum ones split their band)
      fxFor(C, f => ['scapula'].includes(f.bone) || (C.lat ? f.bone === 'clavicle' || f.bone === 'ribs' : f.bone === 'sternum')).forEach(f => crack(C, f, 0.06));
    },

    abdomen(C) {
      const fx = C.fx;
      if (!C.lat) {
        tissue(C, [[0.06, -0.02], [0.94, -0.02], [0.96, 0.4], [0.93, 0.62], [0.97, 1.02], [0.03, 1.02], [0.07, 0.62], [0.04, 0.4]], 0.42, 4);
        tissue(C, [[0.06, -0.02], [0.47, -0.02], [0.46, 0.12], [0.36, 0.2], [0.2, 0.26], [0.07, 0.24]], 0.12, 10);
        [-1, 1].forEach(s => {
          tissue(C, [[0.5 + s * 0.035, 0.12], [0.5 + s * 0.07, 0.13], [0.5 + s * 0.17, 0.6], [0.5 + s * 0.13, 0.62]], 0.08, 4, false);
          C.gs.save(); C.gs.globalCompositeOperation = 'lighter'; C.gs.strokeStyle = TIS(0.2); C.gs.lineWidth = 2; C.gs.filter = 'blur(2px)';
          C.gs.beginPath(); C.gs.ellipse(C.X(0.5 + s * 0.15), C.Y(0.26), C.S(0.055), C.S(0.11), s * -0.25, 0, TAU); C.gs.stroke(); C.gs.restore();
        });
        // bowel gas: colon frame + small loops
        const R = mulberry(hash('gas' + (C.film.seed || 1)));
        const frame = [[0.2, 0.62], [0.17, 0.45], [0.2, 0.28], [0.35, 0.3], [0.5, 0.33], [0.65, 0.3], [0.8, 0.27], [0.83, 0.45], [0.8, 0.62], [0.62, 0.74], [0.52, 0.78]];
        frame.forEach(p => { for (let k = 0; k < 3; k++) carveEll(C, 'soft', p[0] + (R() - 0.5) * 0.06, p[1] + (R() - 0.5) * 0.05, 0.02 + R() * 0.03, 0.012 + R() * 0.02, 0.45 + R() * 0.3, 2, R() * 3); });
        for (let k = 0; k < 9; k++) carveEll(C, 'soft', 0.35 + R() * 0.3, 0.38 + R() * 0.2, 0.012 + R() * 0.018, 0.01 + R() * 0.012, 0.35, 2, R() * 3);
        // T12 + L1-L5
        vertAP(C, 0.5, 0.055, 0.1, 0.055, null, { transverse: 0.02 });
        [-1, 1].forEach(s => longBone(C, 'r12' + s, bez([0.5 + s * 0.07, 0.06], [0.5 + s * 0.11, 0.075], [0.5 + s * 0.14, 0.1], [0.5 + s * 0.16, 0.15], 10), () => 0.015, 0, 1, { dens: 0.4, canal: false }));
        for (let lv = 1; lv <= 5; lv++) {
          vertAP(C, 0.5, 0.14 + (lv - 1) * 0.085, 0.11 + lv * 0.004, 0.064, fx.find(f => f.bone === 'l_spine' && f.level === lv), { transverse: lv === 3 ? 0.08 : 0.06 });
        }
        // pelvis
        [-1, 1].forEach(s => {
          blobBone(C, [[0.5 + s * 0.06, 0.56], [0.5 + s * 0.12, 0.5], [0.5 + s * 0.24, 0.47], [0.5 + s * 0.33, 0.5], [0.5 + s * 0.34, 0.56], [0.5 + s * 0.27, 0.66], [0.5 + s * 0.22, 0.72], [0.5 + s * 0.17, 0.74], [0.5 + s * 0.1, 0.66]], 0.75);
          lineBone(C, [[0.5 + s * 0.07, 0.6], [0.5 + s * 0.14, 0.64], [0.5 + s * 0.17, 0.72], [0.5 + s * 0.13, 0.8]], 0.006, 0.6, true);
          // pubic rami around the obturator foramen
          longBone(C, 'ramS' + s, [[0.5 + s * 0.18, 0.735], [0.5 + s * 0.1, 0.79], [0.5 + s * 0.02, 0.825]], () => 0.036, 0, 1, { cortex: 0.2, dens: 0.8, canal: false });
          longBone(C, 'ramI' + s, [[0.5 + s * 0.02, 0.87], [0.5 + s * 0.08, 0.905], [0.5 + s * 0.16, 0.87], [0.5 + s * 0.19, 0.8]], () => 0.034, 0, 1, { cortex: 0.2, dens: 0.8, canal: false });
          // hip: acetabulum + femoral head, neck, trochanters, shaft
          ellBone(C, 0.5 + s * 0.2, 0.765, 0.042, 0.042, 0, 1.05);
          lineBone(C, [[0.5 + s * 0.15, 0.72], [0.5 + s * 0.2, 0.705], [0.5 + s * 0.255, 0.735]], 0.006, 0.8, true);
          tube(C, [0.5 + s * 0.215, 0.775], [0.5 + s * 0.27, 0.83], 0.045, 0.9);
          ellBone(C, 0.5 + s * 0.3, 0.82, 0.03, 0.04, 0, 0.9);
          tube(C, [0.5 + s * 0.27, 0.84], [0.5 + s * 0.25, 1.03], 0.06, 1.0);
        });
        blobBone(C, [[0.44, 0.55], [0.56, 0.55], [0.545, 0.66], [0.52, 0.73], [0.48, 0.73], [0.455, 0.66]], 0.85);
        for (let k = 0; k < 4; k++) [-1, 1].forEach(s => carveEll(C, 'bone', 0.5 + s * 0.025, 0.58 + k * 0.035, 0.007, 0.006, 0.6, 0));
        carveEll(C, 'soft', 0.5, 0.79, 0.03, 0.022, 0.5, 3);
      } else {
        tissue(C, [[0.12, -0.02], [0.86, -0.02], [0.9, 0.5], [0.95, 1.02], [0.08, 1.02], [0.1, 0.6]], 0.44, 4);
        const R = mulberry(hash('gasl' + (C.film.seed || 1)));
        for (let k = 0; k < 16; k++) carveEll(C, 'soft', 0.2 + R() * 0.35, 0.1 + R() * 0.6, 0.015 + R() * 0.03, 0.01 + R() * 0.02, 0.4, 2, R() * 3);
        for (let lv = 1; lv <= 5; lv++) {
          const x = 0.64 - 0.03 * Math.sin(Math.PI * (lv - 1) / 4);
          vertLAT(C, x, 0.14 + (lv - 1) * 0.085, 0.11, 0.064, fx.find(f => f.bone === 'l_spine' && f.level === lv), { spine: 0.55 });
        }
        // sacrum + coccyx curving back, iliac wings seen side-on, both hips superimposed
        longBone(C, 'sacrumL', bez([0.67, 0.555], [0.73, 0.6], [0.77, 0.68], [0.735, 0.79], 14), (u) => 0.1 - 0.075 * u, 0, 1, { cortex: 0.1, dens: 0.6, canal: false });
        blobBone(C, [[0.46, 0.46], [0.56, 0.44], [0.68, 0.47], [0.72, 0.54], [0.66, 0.6], [0.58, 0.66], [0.5, 0.7], [0.44, 0.66], [0.42, 0.56]], 0.42, 0.6);
        lineBone(C, [[0.43, 0.6], [0.5, 0.64], [0.56, 0.7], [0.58, 0.76]], 0.006, 0.6, true);          // iliopectineal line
        group(C, () => {
          ellBone(C, 0.5, 0.775, 0.046, 0.046, 0, 1);
          blobBone(C, [[0.51, 0.79], [0.56, 0.82], [0.57, 0.87], [0.545, 0.9], [0.51, 0.88], [0.49, 0.83]], 0.9);
          longBone(C, 'femL', [[0.535, 0.86], [0.53, 1.04]], () => 0.07, 0, 1, { cortex: 0.2 });
        });
        lineBone(C, ([0, 1, 2, 3, 4, 5, 6, 7, 8]).map(i => [0.5 + Math.cos(rad(150 + i * 25)) * 0.058, 0.775 + Math.sin(rad(150 + i * 25)) * 0.058]), 0.006, 0.8, true);
        group(C, () => {
          longBone(C, 'pubL', [[0.46, 0.76], [0.38, 0.81], [0.31, 0.86]], () => 0.034, 0, 1, { cortex: 0.15, dens: 0.6, canal: false });
          blobBone(C, [[0.45, 0.83], [0.52, 0.86], [0.55, 0.92], [0.5, 0.95], [0.43, 0.9]], 0.55);
        });
      }
      fxFor(C, f => ['pelvis', 'acetabulum', 'sacrum'].includes(f.bone) && !(f.axes && f.axes.length)).forEach(f => crack(C, f, f.bone === 'pelvis' ? 0.07 : 0.05));
    },

    head(C) {
      const fx = C.fx;
      if (!C.lat) {
        tissue(C, [[0.5, 0.03], [0.85, 0.12], [0.93, 0.42], [0.86, 0.66], [0.72, 0.84], [0.68, 1.02], [0.32, 1.02], [0.28, 0.84], [0.14, 0.66], [0.07, 0.42], [0.15, 0.12]], 0.36, 4);
        // vault: outer & inner table with diploe between
        const vault = (r) => { const out = []; for (let a = 200; a <= 340; a += 7) out.push([0.5 + Math.cos(rad(a)) * 0.37 * r, 0.42 + Math.sin(rad(a)) * 0.36 * r * 1.25 * 0.8]); return out; };
        const ring = (rx, ry, cx = 0.5, cy = 0.42) => { const out = []; for (let a = 0; a < 360; a += 8) out.push([cx + Math.cos(rad(a)) * rx, cy + Math.sin(rad(a)) * ry]); return out; };
        blobBone(C, ring(0.375, 0.37), 0.42, 0.2);
        carve(C, 'bone', ring(0.345, 0.34), 0.55, 0);
        lineBone(C, ring(0.373, 0.368).concat([ring(0.373, 0.368)[0]]), 0.006, 1.1, true);
        lineBone(C, ring(0.348, 0.343).concat([ring(0.348, 0.343)[0]]), 0.004, 0.8, true);
        void vault;
        // frontal sinus, orbits, nasal cavity, maxillary sinuses, petrous ridges, mandible, teeth
        carveEll(C, 'bone', 0.5, 0.33, 0.05, 0.025, 0.45, 2);
        const orbit = (cx) => [[cx - 0.07, 0.44], [cx - 0.03, 0.418], [cx + 0.035, 0.42], [cx + 0.072, 0.445], [cx + 0.072, 0.5], [cx + 0.035, 0.525], [cx - 0.035, 0.522], [cx - 0.072, 0.495]];
        [-1, 1].forEach(s => {
          const cx = 0.5 + s * 0.14;
          carve(C, 'bone', orbit(cx), 0.42, 3);
          lineBone(C, orbit(cx).concat([orbit(cx)[0]]), 0.011, 0.55, true);
          carveEll(C, 'bone', 0.5 + s * 0.125, 0.592, 0.062, 0.042, 0.4, 4);
          lineBone(C, [[0.5 + s * 0.055, 0.54], [0.5 + s * 0.17, 0.515], [0.5 + s * 0.3, 0.505], [0.5 + s * 0.35, 0.52]], 0.02, 0.7, true);   // petrous ridge
          lineBone(C, [[0.5 + s * 0.2, 0.575], [0.5 + s * 0.29, 0.56], [0.5 + s * 0.35, 0.58]], 0.012, 0.45, true);                       // zygomatic arch
          lineBone(C, [[0.5 + s * 0.3, 0.55], [0.5 + s * 0.295, 0.66], [0.5 + s * 0.25, 0.76], [0.5 + s * 0.16, 0.81], [0.5 + s * 0.04, 0.825]], 0.034, 0.5, true);  // mandible
        });
        carve(C, 'bone', [[0.47, 0.5], [0.53, 0.5], [0.56, 0.6], [0.53, 0.625], [0.47, 0.625], [0.44, 0.6]], 0.5, 3);
        lineBone(C, [[0.5, 0.505], [0.502, 0.62]], 0.006, 0.55);
        // teeth: a dense dental arch with dark gaps between the teeth
        group(C, () => {
          blobBone(C, [[0.38, 0.655], [0.44, 0.648], [0.5, 0.646], [0.56, 0.648], [0.62, 0.655], [0.62, 0.69], [0.56, 0.684], [0.5, 0.683], [0.44, 0.684], [0.38, 0.69]], 1.1, 0.6);
          blobBone(C, [[0.385, 0.695], [0.44, 0.698], [0.5, 0.7], [0.56, 0.698], [0.615, 0.695], [0.61, 0.73], [0.56, 0.736], [0.5, 0.738], [0.44, 0.736], [0.39, 0.73]], 1.1, 0.6);
        });
        for (let i = 0; i <= 12; i++) { const x = 0.385 + i * 0.019; lineBone(C, [[x, 0.656], [x + 0.001, 0.734]], 0.0012, 0.0); carve(C, 'bone', [[x - 0.0012, 0.656], [x + 0.0012, 0.656], [x + 0.0022, 0.734], [x - 0.0002, 0.734]], 0.5, 0, false); }
        ellBone(C, 0.5, 0.88, 0.05, 0.04, 0, 0.6);
        vertAP(C, 0.5, 0.95, 0.12, 0.05, null);
      } else {
        tissue(C, [[0.18, 0.12], [0.5, 0.06], [0.85, 0.16], [0.95, 0.4], [0.88, 0.62], [0.72, 0.7], [0.68, 1.02], [0.4, 1.02], [0.36, 0.82], [0.2, 0.84], [0.13, 0.78], [0.12, 0.7], [0.1, 0.64], [0.1, 0.6], [0.06, 0.56], [0.1, 0.5], [0.13, 0.38]], 0.36, 4);
        const ring = (rx, ry, cx, cy) => { const out = []; for (let a = 0; a < 360; a += 8) out.push([cx + Math.cos(rad(a)) * rx, cy + Math.sin(rad(a)) * ry]); return out; };
        blobBone(C, ring(0.39, 0.3, 0.53, 0.4), 0.42, 0.2);
        carve(C, 'bone', ring(0.365, 0.275, 0.53, 0.4), 0.55, 0);
        const o = ring(0.39, 0.3, 0.53, 0.4), i2 = ring(0.366, 0.277, 0.53, 0.4);
        lineBone(C, o.concat([o[0]]), 0.006, 1.1, true);
        lineBone(C, i2.concat([i2[0]]), 0.004, 0.8, true);
        lineBone(C, [[0.4, 0.11], [0.43, 0.25], [0.42, 0.4]], 0.002, 0.5, true);         // coronal suture
        lineBone(C, [[0.77, 0.17], [0.8, 0.32], [0.84, 0.48]], 0.002, 0.5, true);         // lambdoid suture
        carveEll(C, 'bone', 0.2, 0.36, 0.035, 0.03, 0.5, 1);                              // frontal sinus
        lineBone(C, [[0.475, 0.47], [0.482, 0.488], [0.5, 0.494], [0.518, 0.488], [0.522, 0.472]], 0.005, 0.6, true);   // sella turcica
        lineBone(C, [[0.18, 0.41], [0.24, 0.4], [0.3, 0.43], [0.31, 0.49]], 0.01, 0.45, true);       // orbital roof
        tube(C, [0.15, 0.47], [0.11, 0.54], 0.012, 0.9);                                   // nasal bones
        blobBone(C, [[0.17, 0.54], [0.36, 0.53], [0.4, 0.6], [0.38, 0.66], [0.2, 0.67], [0.16, 0.6]], 0.6);
        carveEll(C, 'bone', 0.28, 0.59, 0.06, 0.035, 0.5, 2);
        group(C, () => {
          blobBone(C, [[0.18, 0.66], [0.3, 0.655], [0.4, 0.66], [0.4, 0.69], [0.3, 0.692], [0.185, 0.69]], 1.1, 0.6);
          blobBone(C, [[0.185, 0.698], [0.3, 0.7], [0.4, 0.698], [0.4, 0.728], [0.3, 0.732], [0.19, 0.726]], 1.1, 0.6);
        });
        for (let i = 0; i <= 9; i++) { const x = 0.19 + i * 0.023; carve(C, 'bone', [[x - 0.0012, 0.658], [x + 0.0012, 0.658], [x + 0.002, 0.73], [x - 0.0004, 0.73]], 0.45, 0, false); }
        longBone(C, 'mand', [[0.18, 0.78], [0.3, 0.775], [0.43, 0.75], [0.46, 0.66], [0.48, 0.57]], (u) => 0.04 - 0.015 * u, 0, 1, { cortex: 0.22 });
        ellBone(C, 0.63, 0.55, 0.035, 0.03, 0, 0.6);                                       // mastoid
        carveEll(C, 'bone', 0.58, 0.5, 0.012, 0.012, 0.6, 0);                             // ear canal
        ellBone(C, 0.56, 0.7, 0.03, 0.02, 0, 0.8);
        vertLAT(C, 0.57, 0.8, 0.08, 0.06, null, { spine: 0.5 });
        vertLAT(C, 0.585, 0.9, 0.08, 0.05, null, { spine: 0.6 });
      }
      fxFor(C, f => f.bone === 'skull').forEach(f => crack(C, f, 0.13));
      fxFor(C, f => ['orbit', 'zygoma', 'nasal', 'mandible'].includes(f.bone)).forEach(f => crack(C, f, 0.05, { branches: false }));
    },

    neck(C) {
      const fx = C.fx;
      const lv = (level) => 0.2 + (level - 2) * 0.095;
      const latX = { 2: 0.5, 3: 0.47, 4: 0.455, 5: 0.45, 6: 0.455, 7: 0.47, 8: 0.49 };
      if (!C.lat) {
        tissue(C, [[0.25, -0.02], [0.75, -0.02], [0.72, 0.5], [0.85, 0.85], [1.02, 0.92], [1.02, 1.02], [-0.02, 1.02], [-0.02, 0.92], [0.15, 0.85], [0.28, 0.5]], 0.42, 4);
        carve(C, 'soft', [[0.47, -0.02], [0.53, -0.02], [0.535, 1.02], [0.465, 1.02]], 0.45, 3, false);
        lineBone(C, [[0.18, 0.02], [0.25, 0.1], [0.38, 0.14], [0.5, 0.15], [0.62, 0.14], [0.75, 0.1], [0.82, 0.02]], 0.022, 0.8, true);
        for (let l = 2; l <= 8; l++) vertAP(C, 0.5, lv(l), 0.13 + l * 0.004, 0.062, fx.find(f => f.bone === 'c_spine' && f.level === l), { transverse: 0.04 });
        [-1, 1].forEach(s => {
          longBone(C, 'clN' + s, [[0.5 + s * 0.05, 0.9], [0.5 + s * 0.2, 0.885], [0.5 + s * 0.4, 0.86], [0.5 + s * 0.55, 0.84]], () => 0.03, 0, 1, { cortex: 0.2 });
          longBone(C, 'r1' + s, bez([0.5 + s * 0.08, 0.84], [0.5 + s * 0.2, 0.8], [0.5 + s * 0.3, 0.86], [0.5 + s * 0.25, 0.97], 14), () => 0.018, 0, 1, { dens: 0.7 });
        });
      } else {
        tissue(C, [[0.2, -0.02], [0.82, -0.02], [0.8, 0.5], [0.86, 1.02], [0.12, 1.02], [0.24, 0.6], [0.22, 0.3]], 0.42, 4);
        carve(C, 'soft', [[0.3, -0.02], [0.35, -0.02], [0.37, 0.4], [0.35, 1.02], [0.3, 1.02], [0.32, 0.4]], 0.5, 3, false);
        blobBone(C, [[0.52, -0.02], [0.85, -0.02], [0.82, 0.1], [0.62, 0.11]], 0.7);         // occiput
        ellBone(C, 0.41, 0.13, 0.025, 0.02, 0, 1);                                            // C1 anterior arch
        blobBone(C, [[0.45, 0.1], [0.5, 0.09], [0.52, 0.16], [0.47, 0.19]], 1);                // dens
        lineBone(C, [[0.15, 0.06], [0.28, 0.1], [0.36, 0.06]], 0.02, 0.6, true);               // mandible angle
        for (let l = 2; l <= 8; l++) vertLAT(C, latX[l], lv(l), 0.1, 0.062, fx.find(f => f.bone === 'c_spine' && f.level === l), { spine: 0.6 + l * 0.06 });
        lineBone(C, [[0.39, 0.16], [0.39, 0.4], [0.38, 0.7], [0.4, 0.95]], 0.002, 0.35, true);  // prevertebral line
      }
    },
  };

  // capsule outline around a segment [x1,y1,x2,y2] with width w
  function capsule(s, w) {
    const [x1, y1, x2, y2] = s, a = Math.atan2(y2 - y1, x2 - x1), nx = -Math.sin(a) * w / 2, ny = Math.cos(a) * w / 2 * 0.8;
    return [[x1 + nx, y1 + ny], [x2 + nx, y2 + ny], [x2 + Math.cos(a) * w * 0.3, y2 + Math.sin(a) * w * 0.3], [x2 - nx, y2 - ny], [x1 - nx, y1 - ny]];
  }

  // plaster cast on the film: a dense sleeve with a woven texture
  function castSleeve(C, kind) {
    const f = C.fx.find(x => x.cast);
    if (!f || C.only === 'distal') return;
    const g = C.gs, y0 = clamp(f.p.y - 0.2, 0, 1), y1 = clamp(f.p.y + 0.24, 0, 1.02);
    const L = LIMB[kind][C.lat ? 'lat' : 'ap'];
    const k = Object.keys(L)[f.p.y > 0.47 ? 1 : 0], a = L[k];
    const xAt = (y) => lerp(a[0], a[2], clamp((y - a[1]) / (a[3] - a[1]), 0, 1));
    const half = kind === 'leg' ? 0.15 : 0.12;
    const pts = [[xAt(y0) - half, y0], [xAt(y1) - half * 0.8, y1], [xAt(y1) + half * 0.8, y1], [xAt(y0) + half, y0]];
    g.save(); g.filter = 'blur(2px)'; g.beginPath(); polyPath(g, pts.map(C.P)); g.fillStyle = TIS(0.22); g.fill();
    g.clip(); g.filter = 'none'; g.globalCompositeOperation = 'lighter'; g.strokeStyle = TIS(0.07); g.lineWidth = 1;
    for (let y = C.Y(y0); y < C.Y(y1) + C.H; y += 7) { g.beginPath(); g.moveTo(0, y); g.lineTo(C.W, y - C.W * 0.35); g.stroke(); }
    g.restore();
  }

  let trabTile = null;
  function trabecular(C) {
    if (!trabTile) {
      trabTile = mk(128, 128);
      const tx = trabTile.getContext('2d'), R = mulberry(4242);
      for (let i = 0; i < 900; i++) { tx.fillStyle = `rgba(0,0,0,${0.2 + R() * 0.5})`; tx.beginPath(); tx.ellipse(R() * 128, R() * 128, 0.6 + R() * 1.4, 0.5 + R() * 0.9, R() * 3, 0, TAU); tx.fill(); }
    }
    const g = C.gb; g.save(); g.globalCompositeOperation = 'destination-out'; g.globalAlpha = 0.16; g.filter = 'blur(0.6px)';
    g.fillStyle = g.createPattern(trabTile, 'repeat'); g.fillRect(0, 0, C.W, C.H); g.restore();
  }

  function compose(C, w) {
    const { W, H, film } = C;
    if (C.only !== 'distal') trabecular(C);
    const out = mk(W, H), g = out.getContext('2d');
    g.fillStyle = '#020405'; g.fillRect(0, 0, W, H);
    drawFragments(C);
    g.save();
    if (C.mirror) { g.translate(W, 0); g.scale(-1, 1); }
    g.filter = 'blur(1.5px)'; g.drawImage(C.soft, 0, 0);
    g.globalCompositeOperation = 'lighter';
    g.filter = `blur(${Math.max(2, W / 150)}px)`; g.globalAlpha = 0.38; g.drawImage(C.bone, 0, 0);
    g.filter = 'blur(0.6px)'; g.globalAlpha = 1; g.drawImage(C.bone, 0, 0);
    g.filter = 'none'; g.globalCompositeOperation = 'source-over';
    g.shadowColor = 'rgba(235,245,255,.85)'; g.shadowBlur = Math.max(3, W / 120); g.drawImage(C.metal, 0, 0); g.shadowBlur = 0;
    g.restore();
    // breathing during the exposure smears the image
    if (film.quality === 'motion' && (C.kind === 'chest' || C.kind === 'abdomen')) {
      const tmp = mk(W, H); tmp.getContext('2d').drawImage(out, 0, 0);
      g.globalAlpha = 0.34; g.drawImage(tmp, 0, W * 0.007); g.drawImage(tmp, 0, -W * 0.007); g.globalAlpha = 1;
    }
    grain(g, W, H, (film.seed || 1) + (C.lat ? 5 : 0), 1);
    // anode heel + edge falloff
    const hg = g.createLinearGradient(0, 0, 0, H); hg.addColorStop(0, 'rgba(0,0,0,0)'); hg.addColorStop(1, 'rgba(0,0,0,.16)');
    g.fillStyle = hg; g.fillRect(0, 0, W, H);
    const vg = g.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.45, W / 2, H / 2, Math.max(W, H) * 0.78);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.45)'); g.fillStyle = vg; g.fillRect(0, 0, W, H);
    if (w !== false) labels(g, C);
    return out;
  }

  let noiseTile = null;
  function grain(g, W, H, seed, amount) {
    if (!noiseTile) {
      noiseTile = mk(256, 256);
      const nx = noiseTile.getContext('2d'), id = nx.createImageData(256, 256), R = mulberry(99);
      for (let i = 0; i < id.data.length; i += 4) { const v = 128 + (R() - 0.5) * 200; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
      nx.putImageData(id, 0, 0);
    }
    g.save(); g.globalCompositeOperation = 'soft-light'; g.globalAlpha = 0.5 * amount;
    const p = g.createPattern(noiseTile, 'repeat'); const ox = (seed * 37) % 256, oy = (seed * 91) % 256;
    g.translate(-ox, -oy); g.fillStyle = p; g.fillRect(ox, oy, W, H); g.restore();
    g.save(); g.globalCompositeOperation = 'lighter'; g.globalAlpha = 0.03 * amount; g.fillStyle = p; g.fillRect(0, 0, W, H); g.restore();
  }

  // burned-in film annotation: rotated series strip on the left edge, lead side marker with the
  // projection tag under it, a calibration ruler and the photographic ID block (flash card)
  function labels(g, C) {
    const { W, H, film, which } = C, s = W / 720;
    const ink = 'rgba(226,234,240,.80)', dim = 'rgba(226,234,240,.42)';
    const mono = (px, w = 500) => `${w} ${Math.round(px * s)}px "JetBrains Mono", monospace`;
    const view = String(film.viewLabel || film.view || '').toUpperCase();
    const proj = which === 'lat' ? 'LAT' : 'AP';
    g.save();
    // 1. series strip, reading bottom → top along the left edge
    g.save();
    g.translate(18 * s, H - 26 * s); g.rotate(-Math.PI / 2);
    g.textBaseline = 'top'; g.fillStyle = dim; g.font = mono(10);
    const strip = `${film.id || 'A0000'}  ·  ${view}  ·  ${which === 'lat' ? 'LATERAL' : 'FRONTAL AP'}  ·  SER 1 / IMG ${which === 'lat' ? 2 : 1}`;
    g.fillText(strip, 0, 0);
    const tw = g.measureText(strip).width;
    g.fillStyle = 'rgba(226,234,240,.22)'; g.fillRect(tw + 10 * s, 5 * s, Math.max(0, H - 80 * s - tw), 1 * s);
    g.restore();
    // 2. lead side marker + projection tag
    const side = C.side ? C.side.toUpperCase() : (which === 'lat' ? 'L' : 'R');
    const right = which === 'lat' || C.side === 'l';
    const mw = 28 * s, mh = 30 * s;
    const bx = right ? W - 26 * s - mw : 40 * s, by = 22 * s;
    g.fillStyle = 'rgba(246,250,255,.94)'; g.fillRect(bx, by, mw, mh);
    g.fillStyle = 'rgba(0,0,0,.18)'; g.fillRect(bx + mw - 3 * s, by + 3 * s, 3 * s, mh - 3 * s);
    g.fillStyle = '#05080a'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.font = `700 ${Math.round(20 * s)}px Lexend, sans-serif`; g.fillText(side, bx + mw / 2, by + mh / 2 + 1 * s);
    g.strokeStyle = ink; g.lineWidth = 1.2 * s; g.strokeRect(bx, by + mh + 6 * s, mw, 16 * s);
    g.fillStyle = ink; g.font = mono(9.5, 700); g.fillText(proj, bx + mw / 2, by + mh + 14.5 * s);
    // 3. calibration ruler, bottom left
    const rx = 40 * s, ry = H - 30 * s, rw = 120 * s;
    g.strokeStyle = 'rgba(232,240,246,.7)'; g.lineWidth = 1.4 * s;
    g.beginPath(); g.moveTo(rx, ry); g.lineTo(rx + rw, ry);
    for (let i = 0; i <= 10; i++) { const x = rx + rw * i / 10; g.moveTo(x, ry); g.lineTo(x, ry - (i % 5 === 0 ? 9 : 5) * s); }
    g.stroke();
    g.textAlign = 'left'; g.textBaseline = 'bottom'; g.fillStyle = dim; g.font = mono(8.5);
    g.fillText('CAL', rx, ry - 12 * s);
    // 4. ID flash card: a pale block exposed by the cassette printer, dark type on it
    const lines = [
      String(film.hospital || 'RADIOLOGY').toUpperCase(),
      `${String(film.name || '').toUpperCase()}${film.sex ? `  ${String(film.sex).toUpperCase()}` : ''}${film.age ? `/${film.age}` : ''}`,
      `${film.pid ? `${String(film.pid).toUpperCase()}  ` : ''}${film.dateText || ''}`,
      `${film.kv ? `${film.kv} kV  ${film.mas} mAs` : ''}${film.quality === 'motion' ? '  MOTION' : ''}`,
    ].filter(Boolean);
    const cw = 214 * s, ch = (14 + lines.length * 13) * s;
    const cx = W - 22 * s - cw, cy = H - 22 * s - ch;
    const cg = g.createLinearGradient(cx, cy, cx, cy + ch);
    cg.addColorStop(0, 'rgba(214,222,228,.88)'); cg.addColorStop(1, 'rgba(188,198,206,.84)');
    g.fillStyle = cg; g.fillRect(cx, cy, cw, ch);
    g.fillStyle = 'rgba(5,8,10,.85)'; g.fillRect(cx, cy, 4 * s, ch);
    g.textBaseline = 'top'; g.textAlign = 'left';
    lines.forEach((t, i) => {
      g.fillStyle = i === 0 ? '#06090b' : 'rgba(6,9,11,.82)';
      g.font = mono(i === 0 ? 9.5 : 9, i === 0 ? 700 : 500);
      let txt = t; while (txt.length > 4 && g.measureText(txt).width > cw - 20 * s) txt = txt.slice(0, -1);
      g.fillText(txt, cx + 12 * s, cy + 7 * s + i * 13 * s);
    });
    g.restore();
  }

  const filmCache = new Map();
  function renderFilm(film, which, w = 720) {
    const key = `${film.id}:${film.seed}:${which}:${w}:${film.quality}`;
    if (filmCache.has(key)) return filmCache.get(key);
    const C = makeCtx(film, which, w);
    prepFx(C);
    const fn = ANAT[C.kind] || ANAT.chest;
    fn(C);
    const out = compose(C);
    if (filmCache.size > 24) filmCache.delete(filmCache.keys().next().value);
    filmCache.set(key, out);
    return out;
  }
  // which axes a fracture sits on (long bones), and which rib / clavicle band
  function prepFx(C) {
    for (const f of C.fx) {
      f.axes = BONE_AXES[f.bone] ? BONE_AXES[f.bone].slice() : [];
      if (C.kind === 'chest') {
        if (!C.lat && f.bone === 'ribs') {
          const s = f.p.x < 0.5 ? 'R' : 'L';
          let best = 1, bd = 1e9;
          for (let n = 1; n <= 10; n++) { const y0 = 0.1 + 0.055 * n + 0.02; const d = Math.abs(y0 - f.p.y); if (d < bd) { bd = d; best = n; } }
          f.axes = [`rib${s}${best}`];
        }
        if (!C.lat && f.bone === 'clavicle') f.axes = [f.p.x < 0.5 ? 'clavR' : 'clavL'];
        if (C.lat && f.bone === 'sternum') f.axes = ['sternum'];
        if (C.lat && f.bone === 'ribs') f.axes = [];
      }
      if (C.kind === 'abdomen' && f.bone === 'pelvis' && f.site === 'ramus' && !C.lat) f.axes = [f.p.x < 0.5 ? 'ramS-1' : 'ramS1'];
      if (C.kind === 'abdomen' && f.bone === 'pelvis' && f.site === 'ramus' && C.lat) f.axes = ['pubL'];
    }
  }

  /* fluoroscopy: static cache + live distal fragment */
  function fluoroScene(film, which, liveId, w) {
    const live = { id: liveId, m: () => ({ ang: 0, shift: 0, short: 0 }) };
    const C = makeCtx(film, which, w, { live, only: 'static' });
    prepFx(C);
    (ANAT[C.kind] || ANAT.chest)(C);
    const base = compose(C, false);
    return { C, base, distal: C.distal || [] };
  }

  /* ── body figure (console) ── */
  const FIG = {
    body: 'M50 4c8 0 13 6 13 15s-5 18-13 18-13-9-13-18 5-15 13-15zM44 37h12l1 6c9 1 17 3 21 8 3 4 4 12 5 20l4 36c1 9 3 20 4 30l2 12c1 3-3 4-4 1l-5-12c-3-9-5-19-7-28l-3-24h-1c0 12 1 22 2 32 1 8 1 16 0 22l-2 30c-1 22-2 44-2 66 0 4-9 4-9 0l-2-66h-2l-2 66c0 4-9 4-9 0 0-22-1-44-2-66l-2-30c-1-6-1-14 0-22 1-10 2-20 2-32h-1l-3 24c-2 9-4 19-7 28l-5 12c-1 3-5 2-4-1l2-12c1-10 3-21 4-30l4-36c1-8 2-16 5-20 4-5 12-7 21-8z',
    zones: {
      head: 'M35 4h30v34H35z', neck: 'M41 38h18v10H41z', chest: 'M31 48h38v40H31z', abdomen: 'M32 88h36v44H32z',
      r_arm: 'M6 46h22v94H6z', l_arm: 'M72 46h22v94H72z', r_leg: 'M30 134h20v136H30z', l_leg: 'M50 134h20v136H50z',
    },
  };
  function figSVG(sel, cls = '', coll = false) {
    let extra = '';
    const z = coll && FIG.zones[sel] && FIG.zones[sel].match(/M([\d.]+) ([\d.]+)h([\d.]+)v([\d.]+)/);
    if (z) {
      const [x, y, w, h] = z.slice(1).map(Number);
      extra = `<rect class="coll" x="${x - 2}" y="${y - 2}" width="${w + 4}" height="${h + 4}"/><path class="cross" d="M${x + w / 2} ${y - 6}v${h + 12}M${x - 6} ${y + h / 2}h${w + 12}"/>`;
    }
    return `<svg viewBox="0 0 100 274" class="${cls}"><path class="body" d="${FIG.body}"/>${Object.entries(FIG.zones).map(([k, d]) => `<path class="zone ${k === sel ? 'on' : ''}" data-v="${k}" d="${d}"/>`).join('')}${extra}</svg>`;
  }

  /* ═══════════════════════════ APP STATE ═══════════════════════════ */
  let root = null;
  const S = { mode: null, d: null, pp: null, raf: 0, timers: [], off: [], m: null };
  const on = (t, ev, fn, o) => { t.addEventListener(ev, fn, o); S.off.push(() => t.removeEventListener(ev, fn, o)); };
  const later = (fn, ms) => { const id = setTimeout(fn, ms); S.timers.push(id); return id; };
  const KEY = (name, def) => ((S.d && S.d.keys && S.d.keys[name]) || def);
  const keyCap = (code) => String(code || '').replace(/^Key/, '').replace(/^Digit/, '').replace('Space', 'Space').replace('Enter', 'Enter');
  const isKey = (e, name, def) => e.code === KEY(name, def) || e.key === KEY(name, def);
  const sound = (name, ...a) => { try { NZA.audio[name] && NZA.audio[name](...a); } catch (_) { /* audio optional */ } };

  function teardown() {
    cancelAnimationFrame(S.raf); S.raf = 0;
    S.timers.forEach(clearTimeout); S.timers = [];
    S.off.forEach(f => f()); S.off = [];
    if (S.m && S.m.destroy) { try { S.m.destroy(); } catch (_) { /* noop */ } }
    if (S.pp) S.pp.destroy();
    S.pp = null; S.m = null; S.mode = null;
    if (root) root.innerHTML = '';
  }
  const post = (ev, data) => NZA.post(`${APP}:${ev}`, data || {});
  const frame = (fn) => { const loop = (t) => { S.raf = requestAnimationFrame(loop); fn(t); }; S.raf = requestAnimationFrame(loop); };
  const abortBtn = () => ({ key: 'ESC', label: T('hold_abort', 'Hold to cancel'), seconds: 1.0 });

  /* ═══════════════════════════ MODE: CHOOSE ═══════════════════════════ */
  function modeChoose(d) {
    const views = d.views || [];
    let sel = (views.find(v => v.sev) || views[2] || views[0] || {}).id;
    const box = NZA.el('div', 'xr-dev xr-choose nza-int');
    box.innerHTML = `
      ${devHead('RX-10', T('dev_console', 'Radiographic console'))}
      <div class="xr-ch-body">
        <div class="xr-scr xr-ch-fig">${figSVG(sel)}</div>
        <div class="xr-ch-list">
          <div class="xr-ch-pt"><b>${esc(d.name || T('patient', 'Patient'))}</b><span>${esc(T('choose_sub', 'Pick the body part for the film'))}</span></div>
          <div class="xr-ch-grid">${views.map((v, i) => `<button class="xr-vbtn" data-v="${esc(v.id)}"><kbd>${i + 1}</kbd><span>${esc(v.label)}</span><span class="sp"></span>${v.sev ? `<span class="tag ${v.sev >= 3 ? 'red' : ''}"><i></i>${esc(T('injured', 'Injured'))}</span>` : ''}</button>`).join('')}</div>
          <div class="xr-ch-set"><div class="dl" data-kv></div><div class="dl" data-mas></div><div class="pj"><div class="xr-k">${esc(T('projections', 'Projections'))}</div><div class="v">AP<small>+</small>LAT</div><div class="xr-k" style="margin-top:8px">SID</div><div class="v sm">180<small>cm</small></div></div></div>
          ${views.some(v => v.sev) ? `<div class="xr-ch-note">${icon('alert')}<span>${esc(T('complaint', 'Where it hurts'))}: <b>${esc(views.filter(v => v.sev).sort((a, b) => b.sev - a.sev).map(v => v.label).join(', '))}</b></span></div>` : ''}
          <div class="xr-ch-foot"><span class="hint">${esc(T('choose_hint', 'Clear the room before you expose.'))}</span><span class="sp"></span><button class="btn-line" data-x>${esc(T('cancel', 'Cancel'))}</button><button class="btn-teal" data-go>${icon('xray')}${esc(T('take', 'Take X-ray'))}</button></div>
        </div>
      </div>`;
    root.appendChild(box);
    const SET = { head: [75, 20], neck: [70, 16], chest: [110, 4], abdomen: [80, 32], l_arm: [60, 6], r_arm: [60, 6], l_leg: [65, 10], r_leg: [65, 10] };
    const paint = () => {
      box.querySelectorAll('.xr-vbtn').forEach(b => b.classList.toggle('on', b.dataset.v === sel));
      box.querySelectorAll('.zone').forEach(z => {
        const v = views.find(x => x.id === z.dataset.v);
        z.classList.toggle('on', z.dataset.v === sel); z.classList.toggle('inj', !!(v && v.sev)); z.classList.toggle('sev3', !!(v && v.sev >= 3));
      });
      const s = SET[sel] || [70, 10];
      box.querySelector('[data-kv]').innerHTML = miniDial(s[0] / 150, 'kVp', s[0], 'kV');
      box.querySelector('[data-mas]').innerHTML = miniDial(s[1] / 40, 'mAs', s[1], 'mAs');
    };
    const go = () => { if (!sel) return; sound('click', 880); box.querySelector('[data-go]').disabled = true; post('choose', { view: sel }); };
    box.addEventListener('click', (e) => {
      const b = e.target.closest('[data-v]'); if (b) { sel = b.dataset.v; sound('click'); paint(); return; }
      if (e.target.closest('[data-go]')) go();
      if (e.target.closest('[data-x]')) NZA.close(APP);
    });
    paint();
    S.m = {
      key(e) {
        const n = parseInt(e.key, 10);
        if (n >= 1 && n <= views.length) { sel = views[n - 1].id; sound('click'); paint(); return true; }
        if (e.key === 'Enter') { go(); return true; }
        if (e.key === 'Escape') { NZA.close(APP); return true; }
        return false;
      },
    };
  }

  /* ═══════════════════════════ MODE: EXPOSE ═══════════════════════════ */
  function modeExpose(d) {
    const needBreath = !!d.breath;
    const st = { phase: 'ready', breathAt: 0, hold: 0, holding: false, exposed: false };
    const box = NZA.el('div', 'xr-dev xr-console nza-int');
    box.innerHTML = `
      ${devHead('RX-10', T('dev_console', 'Radiographic console'))}
      <div class="xr-scr xr-co-scr">
        <div class="xr-co-fig">${figSVG(d.view, '', true)}</div>
        <div class="xr-co-info">
          <div><div class="xr-co-name">${esc(d.name || '')}</div><div class="xr-co-view">${esc(d.viewLabel || d.view)} · AP + LAT</div></div>
          <div class="xr-co-row"><span class="xr-k">kVp</span><span class="v xr-lcd">${esc(d.kv || 70)}<small>kV</small></span></div>
          <div class="xr-co-row"><span class="xr-k">mAs</span><span class="v xr-lcd">${esc(d.mas || 10)}<small>mAs</small></span></div>
          <div class="xr-co-grid"><div><span class="xr-k">SID</span><b>180 cm</b></div><div><span class="xr-k">${esc(T('focus', 'Focus'))}</span><b>${esc(T('fine', 'Fine'))}</b></div><div><span class="xr-k">${esc(T('grid', 'Grid'))}</span><b>${esc(T('on', 'On'))}</b></div></div>
          <div class="xr-co-room">${icon('check')}<span>${esc(T('room_clear', 'Door closed · room clear'))}</span></div>
          ${needBreath ? `<div class="xr-co-breath"><span class="xr-k">${esc(T('breath', 'Breath'))}</span><div class="bar"><i data-br></i></div><span data-brt>--</span></div>` : ''}
          <div class="xr-co-hold"><i data-hold></i></div>
          <div class="xr-co-state ready" data-state>${trefoil()}<span>${esc(T('st_ready', 'Ready'))}</span></div>
        </div>
        <div class="xr-co-film" data-film><canvas width="192" height="240"></canvas><div class="id" data-fid></div></div>
      </div>
      <div class="xr-co-slot"></div>`;
    root.appendChild(box);
    const flash = NZA.el('div', 'xr-flash'); root.appendChild(flash);
    const q = (s) => box.querySelector(s);
    const setState = (cls, txt) => { const el = q('[data-state]'); el.className = `xr-co-state ${cls}`; el.querySelector('span').textContent = txt; };
    const tools = () => {
      const t = [];
      if (needBreath) t.push({ key: keyCap(KEY('breath', 'KeyB')), label: T('tool_breath', 'Hold breath'), icon: 'lungs', state: st.breathAt ? 'done' : '' });
      t.push({ key: keyCap(KEY('expose', 'Space')), label: T('tool_expose', 'Hold to expose'), icon: 'xray', state: st.holding ? 'active' : '' });
      return t;
    };
    S.pp = NZA.ui.ProcPanel(root, {
      step: 1, total: 2, tag: T('tag_take', 'X-ray'),
      title: T('expose_title', 'Expose the film'),
      text: needBreath ? T('expose_text_breath', 'Everyone is out of the room. Press {B} so the patient holds their breath, then hold {Space} to expose.')
        : T('expose_text', 'Everyone is out of the room. Hold {Space} to expose the film.'),
      steps: [T('expose_title', 'Expose the film'), T('processing_title', 'Develop the film')],
      wide: { label: 'kVp', value: d.kv || 70, unit: 'kV', meter: { value: clamp((d.kv || 70) / 150, 0, 1), zone: [0.38, 0.8] }, caption: `${d.mas || 10} mAs · SID 180`, captionTone: 'teal' },
      stats: [{ id: 'view', label: T('view', 'View'), value: d.viewLabel || d.view, small: true }, { id: 'proj', label: T('projections', 'Projections'), value: 'AP + LAT', small: true }],
      tools: tools(), abort: abortBtn(),
      onAbort: () => { post('abort'); }, onTool: (k) => { if (k === keyCap(KEY('breath', 'KeyB'))) breath(); },
    });
    const breath = () => {
      if (!needBreath || st.exposed) return;
      st.breathAt = performance.now(); sound('click', 520); S.pp.set({ tools: tools() }); S.pp.flash('ok', T('breath_held', 'Patient: "Holding my breath..."'), 1800);
    };
    const bw = (d.breathWindow || 5) * 1000;
    let last = performance.now();
    frame((t) => {
      const dt = t - last; last = t;
      if (needBreath) {
        const left = st.breathAt ? Math.max(0, bw - (t - st.breathAt)) : 0;
        q('[data-br]').style.width = `${(left / bw) * 100}%`;
        q('[data-brt]').textContent = left ? `${(left / 1000).toFixed(1)}s` : '--';
        if (st.breathAt && !left && !st.exposed) { st.breathAt = 0; S.pp.set({ tools: tools() }); S.pp.flash('warn', T('breath_lost', 'The patient breathed again. Press {B} again.'), 2400); }
      }
      if (st.holding && !st.exposed) {
        st.hold = Math.min(1, st.hold + dt / 1100);
        if (st.hold < 1) { setState('prep', T('st_prep', 'Prep · rotor up')); if (Math.floor(st.hold * 10) !== Math.floor((st.hold - dt / 1100) * 10)) sound('tone', 600 + st.hold * 900, 50, { vol: 0.03 }); } else expose();
      } else if (!st.exposed) { st.hold = Math.max(0, st.hold - dt / 400); if (!st.hold) setState('ready', T('st_ready', 'Ready')); }
      q('[data-hold]').style.width = `${st.hold * 100}%`;
    });
    const expose = () => {
      st.exposed = true; st.holding = false;
      const breathOk = !needBreath || (st.breathAt && performance.now() - st.breathAt < bw);
      setState('on', T('st_on', 'X-ray on'));
      q('[data-led]').className = 'xr-led red';
      sound('tone', 1150, 420, { vol: 0.09, type: 'square' });
      flash.classList.add('go');
      later(() => {
        setState('done', T('st_processing', 'Processing film'));
        q('[data-led]').className = 'xr-led amber';
        S.pp.set({ step: 2, title: T('processing_title', 'Develop the film'), text: T('processing_text', 'The cassette is in the processor. The film drops out in a moment.'), tools: [], wide: { label: T('progress', 'Developer'), value: 0, unit: '%', meter: { value: 0 }, caption: '' } });
        let p = 0; const iv = setInterval(() => { p = Math.min(0.95, p + 0.06); if (S.pp) S.pp.wide({ value: Math.round(p * 100), meter: { value: p } }); }, 160);
        S.timers.push(iv);
      }, 450);
      post('expose', { breath: !!breathOk });
    };
    S.m = {
      key(e) {
        if (isKey(e, 'expose', 'Space')) { if (!st.exposed) { st.holding = true; S.pp.set({ tools: tools() }); } return true; }
        if (isKey(e, 'breath', 'KeyB')) { breath(); return true; }
        return false;
      },
      keyUp(e) { if (isKey(e, 'expose', 'Space')) { st.holding = false; if (S.pp && !st.exposed) S.pp.set({ tools: tools() }); return true; } return false; },
      filmReady(f) {
        const fl = q('[data-film]'); fl.classList.add('on');
        const cv = fl.querySelector('canvas');
        const demo = { id: f.id, view: d.view, viewLabel: d.viewLabel, seed: hash(String(f.id)), findings: [], quality: f.quality, name: d.name, kv: d.kv, mas: d.mas };
        fontsReady.then(() => { const img = renderFilm(demo, 'ap', 384); cv.getContext('2d').drawImage(img, 0, 0, 192, 240); requestAnimationFrame(() => cv.classList.add('dev')); });
        q('[data-fid]').textContent = `${f.id} · ${(f.viewLabel || '').toUpperCase()}`;
        if (S.pp) {
          S.pp.wide({ value: 100, meter: { value: 1 }, caption: f.id, captionTone: 'teal' });
          S.pp.complete({ title: T('film_ready', 'Film ready'), text: F(f.quality === 'motion' ? T('film_ready_motion', 'Film %s is in your pocket. The patient moved: the image is blurred.') : T('film_ready_text', 'Film %s is in your pocket. Read it on a lightbox.'), f.id), onDone: () => NZA.close(APP) });
        }
        sound('success');
      },
    };
  }
  // generic device head: engraved model plate, device name, radiation sticker, status LED
  function devHead(model, name, led = '<span class="xr-led on" data-led></span>', extra = '') {
    return `<div class="xr-dev-head"><span class="xr-plate">${esc(model)}</span><b>${esc(name)}</b><span class="sp"></span>${extra}<span class="xr-sticker" title="">${trefoil()}</span>${led}</div>`;
  }
  // small 240° dial (console readouts)
  function miniDial(frac, label, value, unit) {
    const R = 30, C = 40, A0 = 150, SW = 240, f = clamp(frac, 0, 1);
    const pt = (t, r = R) => { const a = (A0 + SW * t) * Math.PI / 180; return [C + r * Math.cos(a), C + r * Math.sin(a)]; };
    const arc = (t0, t1, r = R) => { const [x0, y0] = pt(t0, r), [x1, y1] = pt(t1, r); return `M${x0.toFixed(1)} ${y0.toFixed(1)}A${r} ${r} 0 ${(t1 - t0) * SW > 180 ? 1 : 0} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`; };
    let ticks = ''; for (let i = 0; i <= 8; i++) { const [a, b] = pt(i / 8, R + 5), [c, e] = pt(i / 8, R + (i % 4 ? 8 : 10)); ticks += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${e.toFixed(1)}"/>`; }
    return `<svg viewBox="0 0 80 70"><path class="trk" d="${arc(0, 1)}"/><path class="fill" d="${arc(0, Math.max(f, 0.01))}"/><g class="tk">${ticks}</g></svg><div class="dv"><span class="xr-k">${esc(label)}</span><b>${esc(value)}<small>${esc(unit)}</small></b></div>`;
  }
  // score as a status ring (the HUD's ring language), value in the middle
  function scoreRing(score, size = 64) {
    const v = clamp(Number(score) || 0, 0, 100), R = 26, C = 2 * Math.PI * R;
    const tone = v >= 72 ? 'ok' : v >= 45 ? 'warn' : 'bad';
    return `<span class="xr-ring ${tone}" style="width:${size}px;height:${size}px"><svg viewBox="0 0 64 64"><circle class="bg" cx="32" cy="32" r="${R}"/><circle class="tk" cx="32" cy="32" r="${R + 5}"/><circle class="fg" cx="32" cy="32" r="${R}" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - v / 100)).toFixed(1)}"/></svg><b>${Math.round(v)}</b></span>`;
  }
  function trefoil() {
    return '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="2.2"/><path d="M12 9.2 8.6 3.3A10 10 0 0 0 3.2 12h6.6a2.3 2.3 0 0 1 2.2-2.8zM12 9.2l3.4-5.9A10 10 0 0 1 20.8 12h-6.6A2.3 2.3 0 0 0 12 9.2zM10.6 14.4l-3.3 5.8a10 10 0 0 0 9.4 0l-3.3-5.8a2.3 2.3 0 0 1-2.8 0z"/></svg>';
  }

  /* ═══════════════════════════ MODE: READ / VIEW (lightbox) ═══════════════════════════ */
  function modeRead(d) {
    const film = d.film || {};
    const viewOnly = d.mode === 'view';
    const st = {
      hung: null, light: true, tool: viewOnly ? 'move' : 'mark', contrast: 0, zoom: 1, panX: 0, panY: 0,
      pins: { ap: [], lat: [] }, measure: { ap: null, lat: null }, opened: performance.now(), result: null, normal: false, step: 1,
    };
    const minMs = (d.minTime ?? 8) * 1000;
    const wrap = NZA.el('div', 'xr-read'); root.appendChild(wrap);
    const findings = film.findings || [];

    // ── jacket (left)
    const jacket = NZA.el('div', 'xr-jacket nza-hud solid nza-int');
    jacket.innerHTML = `
      <div class="xr-jk-head"><span class="t">${esc(T('jacket', 'Film jacket'))}</span><span class="sp"></span><span class="id">${esc(film.id || '')}</span></div>
      <div class="xr-env"><div class="nm">${esc(film.name || '')}</div><div class="mt">${esc([film.sex ? String(film.sex).toUpperCase() : '', film.age || ''].filter(Boolean).join(' · '))}${film.pid ? ` · ${esc(film.pid)}` : ''}</div>
        <div class="grid">
          <div><div class="l">${esc(T('study', 'Study'))}</div><div class="v">${esc(film.viewLabel || film.view || '')}</div></div>
          <div><div class="l">${esc(T('taken', 'Taken'))}</div><div class="v">${esc(film.dateText || '')}</div></div>
          <div><div class="l">${esc(T('radiographer', 'Radiographer'))}</div><div class="v">${esc(film.by || '—')}</div></div>
          <div><div class="l">${esc(T('quality', 'Quality'))}</div><div class="v" style="color:${film.quality === 'motion' ? '#f3c35a' : 'var(--teal-hi)'}">${esc(film.quality === 'motion' ? T('q_motion', 'Motion blur') : T('q_sharp', 'Sharp'))}</div></div>
        </div></div>
      <div class="xr-thumbs">
        <div class="xr-thumb" data-film="ap"><canvas width="240" height="300"></canvas><div class="lb">AP<em data-st>${esc(T('in_jacket', 'In jacket'))}</em></div><span class="pc" data-pc></span></div>
        <div class="xr-thumb" data-film="lat"><canvas width="240" height="300"></canvas><div class="lb">${esc(T('lateral', 'Lateral'))}<em data-st>${esc(T('in_jacket', 'In jacket'))}</em></div><span class="pc" data-pc></span></div>
      </div>
      <div class="xr-legend" data-legend style="display:none">
        <div class="r"><i></i>${esc(T('lg_ok', 'Confirmed (AP + lateral)'))}</div>
        <div class="r"><i class="a"></i>${esc(T('lg_part', 'Seen on one film'))}</div>
        <div class="r"><i class="m"></i>${esc(T('lg_miss', 'Missed / wrong pin'))}</div>
      </div>`;
    wrap.appendChild(jacket);

    // ── lightbox
    const box = NZA.el('div', 'xr-dev xr-box nza-int');
    box.innerHTML = `
      <div class="xr-box-top"><span class="xr-plate">LB-2</span><b>${esc(T('viewer', 'Film illuminator'))}</b><span class="sp"></span><span class="sw"><span class="xr-led on" data-led></span><span data-lt>${esc(T('light_on', 'Lamp lit'))}</span></span></div>
      <div class="xr-panel on" data-panel>
        <div class="xr-clip"></div>
        <div class="xr-stage" data-stage>
          <div class="xr-film hide" data-sheet><canvas width="720" height="900"></canvas><div class="xr-film-tint"></div><svg class="xr-measure" data-meas viewBox="0 0 536 670" preserveAspectRatio="none"></svg><div class="xr-pins" data-pins></div></div>
        </div>
        <div class="xr-drop" data-drop><i class="c tl"></i><i class="c tr"></i><i class="c bl"></i><i class="c br"></i>
          <div class="chip"><span class="ic">${icon('xray')}</span><div><b>${esc(T('drag_film', 'Pull a film up from the jacket'))}</b><small>${esc(F(T('drag_film_sub', 'or press %s to clip the AP film'), keyCap(KEY('switch', 'KeyF'))))}</small></div></div></div>
      </div>
      <div class="xr-box-bot"><span class="screw"></span><span>${esc(T('contrast', 'Window'))} <b data-ct style="color:#fff">${esc(T('ct_0', 'Soft'))}</b></span><span class="sp"></span><span class="xr-zoom" data-zoom>100%</span><span class="screw"></span></div>`;
    wrap.appendChild(box);

    // ── report window (right)
    const side = NZA.el('div', `xr-side${viewOnly ? ' short' : ''}`); wrap.appendChild(side);
    const win = NZA.ui.Win(side, {
      title: T('report', 'Radiology report'), sub: `${film.id || ''} · ${film.viewLabel || ''}`,
      mid: `<span class="xr-timer" data-timer></span>`,
      status: viewOnly ? [{ key: 'ESC', label: T('close', 'Close') }] : [{ key: 'Enter', label: T('submit', 'Submit report') }, { key: 'N', label: T('normal', 'Normal film') }],
      onClose: () => NZA.close(APP),
    });
    const q = (s) => wrap.querySelector(s);
    const sheet = q('[data-sheet]'), panel = q('[data-panel]'), stage = q('[data-stage]');
    const cv = sheet.querySelector('canvas');

    const renders = {};
    fontsReady.then(() => {
      ['ap', 'lat'].forEach(w => {
        renders[w] = renderFilm(film, w, 720);
        const th = jacket.querySelector(`.xr-thumb[data-film="${w}"] canvas`);
        th.getContext('2d').drawImage(renders[w], 0, 0, 240, 300);
      });
      if (st.hung) hang(st.hung, true); else panelText();
    });

    function sideHTML() {
      if (st.result) return resultHTML();
      const elapsed = performance.now() - st.opened;
      const pinsHTML = (w) => st.pins[w].length
        ? st.pins[w].map((p, i) => `<div class="xr-pinrow"><span class="n">${i + 1}</span><span>${esc(w === 'ap' ? 'AP' : T('lateral', 'Lateral'))} · ${Math.round(p.x * 100)}, ${Math.round(p.y * 100)}</span><span class="sp"></span></div>`).join('')
        : `<div class="xr-note amber">${esc(F(T('no_pins', 'No pin on the %s film yet.'), w === 'ap' ? 'AP' : T('lateral', 'lateral')))}</div>`;
      const meas = st.measure.ap || st.measure.lat;
      return `
        <div class="xr-sec"><h5>${esc(T('clinical', 'Request'))}</h5>
          <div class="xr-note">${esc(T('request_text', 'Trauma series. Find every break and retained fragment. Pin each one on the AP film and again on the lateral film.'))}</div></div>
        ${viewOnly ? `<div class="xr-sec"><div class="xr-note amber">${esc(T('view_only', 'You are not trained to report films. You can look, but not mark them.'))}</div></div>` : `
        <div class="xr-sec"><h5>${esc(T('your_pins', 'Your pins'))}</h5>${pinsHTML('ap')}${pinsHTML('lat')}</div>
        <div class="xr-sec"><h5>${esc(T('measure', 'Angle'))}</h5>${meas && meas.angle !== undefined ? `<div class="xr-pinrow"><span class="n" style="border-color:#f3c35a;color:#f3c35a">∠</span><span>${esc(T('measured', 'Measured angulation'))}</span><span class="sp"></span><b style="color:#fff">${meas.angle}°</b></div>` : `<div class="xr-note">${esc(T('measure_hint', 'Optional: press 3 and draw a line along each piece of a displaced break to measure its angle.'))}</div>`}</div>
        <div class="xr-sec"><div class="xr-note ${elapsed < minMs ? 'amber' : ''}">${elapsed < minMs ? esc(F(T('wait_report', 'Look at the films carefully. The report unlocks in %ss.'), Math.ceil((minMs - elapsed) / 1000))) : esc(T('ready_report', 'Press Enter to submit the report, or N if both films are normal.'))}</div></div>`}`;
    }
    function resultHTML() {
      const r = st.result;
      if (r.error) return `<div class="xr-sec"><div class="xr-note red">${esc(r.error)}</div></div>`;
      const rows = (r.rows || []).map(row => {
        const cls = row.confirmed ? 'ok' : (row.ap || row.lat) ? 'part' : 'miss';
        return `<div class="xr-row ${cls}"><span class="ic">${icon(cls === 'ok' ? 'check' : cls === 'part' ? 'alert' : 'x')}</span><span class="tx">${esc(row.label || '')}<small>AP ${row.ap ? '✓' : '—'} · ${esc(T('lateral', 'Lateral'))} ${row.lat ? '✓' : '—'}</small></span></div>`;
      }).join('');
      return `
        <div class="xr-res">${scoreRing(r.score, 72)}<div><div class="xr-k">${esc(T('score', 'Score'))}</div><div class="sc">${esc(r.score)}<small>/100</small></div><p>${esc(r.msg || '')}</p></div></div>
        <div class="xr-sec"><h5>${esc(T('findings', 'Findings'))}</h5>${rows || `<div class="xr-note">${esc(T('no_findings', 'No fracture or fragment on these films.'))}</div>`}
          ${r.falsePins ? `<div class="xr-note red">${esc(F(T('false_pins', '%d pin(s) marked nothing.'), r.falsePins))}</div>` : ''}
          ${r.measure ? `<div class="xr-note ${r.measure.ok ? '' : 'amber'}">${esc(F(T('measure_res', 'Angle: you measured %s°, the film shows %s°.'), r.measure.yours, r.measure.truth))}</div>` : ''}
          ${r.offline ? `<div class="xr-note amber">${esc(T('offline', 'The patient is not here: the reading was saved on the film only.'))}</div>` : ''}
          ${r.applied ? `<div class="xr-note">${esc(F(T('applied', '%d diagnosis confirmed in the patient record.'), r.applied))}</div>` : ''}</div>
        <div class="xr-sec"><div class="xr-note">${esc(T('result_hint', 'The rings show where each finding really is. F flips the film, Enter closes.'))}</div></div>`;
    }
    const renderSide = () => { win.main.innerHTML = sideHTML(); };

    function thumbs() {
      ['ap', 'lat'].forEach(w => {
        const th = jacket.querySelector(`.xr-thumb[data-film="${w}"]`);
        th.classList.toggle('up', st.hung === w);
        th.querySelector('[data-st]').textContent = st.hung === w ? T('on_viewer', 'On lamp') : T('in_jacket', 'In jacket');
        const pc = th.querySelector('[data-pc]'); pc.textContent = st.pins[w].length; pc.classList.toggle('on', st.pins[w].length > 0);
      });
    }
    function hang(which, silent) {
      st.hung = which;
      sheet.classList.remove('hide');
      if (renders[which]) cv.getContext('2d').drawImage(renders[which], 0, 0, 720, 900);
      sheet.style.transform = silent ? '' : 'translateY(-6px)';
      if (!silent) { later(() => { sheet.style.transform = ''; }, 30); sound('click', 300); sound('noise', 120, { vol: 0.05, lp: 3000, hp: 800 }); }
      q('[data-drop]').classList.add('hide');
      if (st.step === 1) { st.step = 2; }
      drawPins(); drawMeasure(); thumbs(); panelText(); renderSide();
    }
    function applyLight() {
      panel.classList.toggle('on', st.light);
      sheet.classList.toggle('off', !st.light);
      q('[data-led]').className = `xr-led ${st.light ? 'on' : ''}`;
      q('[data-lt]').textContent = st.light ? T('light_on', 'Lamp lit') : T('light_off', 'Lamp dark');
    }
    function applyContrast() {
      sheet.classList.remove('c1', 'c2'); if (st.contrast) sheet.classList.add(`c${st.contrast}`);
      q('[data-ct]').textContent = T(`ct_${st.contrast}`, ['Soft', 'Bone', 'Bright'][st.contrast]);
    }
    function applyView() {
      stage.style.transform = `translate(${st.panX}px,${st.panY}px) scale(${st.zoom})`;
      q('[data-zoom]').textContent = `${Math.round(st.zoom * 100)}%`;
    }
    // pins in film coords (0..1)
    function drawPins() {
      const box2 = q('[data-pins]'); box2.innerHTML = '';
      if (!st.hung) return;
      const truthOf = st.result && !st.result.error ? st.result : null;
      st.pins[st.hung].forEach((p, i) => {
        const el = NZA.el('div', `xr-pin ${p.state || ''}`); el.style.left = `${p.x * 100}%`; el.style.top = `${p.y * 100}%`;
        el.innerHTML = `<b>${st.hung === 'ap' ? 'AP' : 'LAT'} ${i + 1}</b>`;
        if (!truthOf && !viewOnly) el.addEventListener('mousedown', (e) => { if (e.button !== 0 || st.tool !== 'mark') return; e.stopPropagation(); st.pins[st.hung].splice(i, 1); sound('click', 400); drawPins(); thumbs(); panelText(); renderSide(); });
        box2.appendChild(el);
      });
      if (truthOf) {
        const rowById = {}; (truthOf.rows || []).forEach(r => { rowById[r.id] = r; });
        findings.forEach(f => {
          const pos = f[st.hung]; if (!pos) return;
          const r = rowById[f.id] || {};
          const cls = r.confirmed ? 'ok' : (r.ap || r.lat) ? 'part' : 'miss';
          const el = NZA.el('div', `xr-truth ${cls}`);
          const size = Math.max(0.05, f.r || 0.06) * 2 * 100;
          el.style.left = `${pos.x * 100}%`; el.style.top = `${pos.y * 100}%`; el.style.width = `${size}%`; el.style.height = `${size * 0.8}%`;
          el.innerHTML = `<span>${esc(f.label || '')}</span>`;
          box2.appendChild(el);
        });
      }
    }
    function drawMeasure() {
      const svg = q('[data-meas]'); svg.innerHTML = '';
      const m = st.hung && st.measure[st.hung]; if (!m) return;
      const line = (l) => l ? `<line x1="${l[0].x * 536}" y1="${l[0].y * 670}" x2="${l[1].x * 536}" y2="${l[1].y * 670}"/><circle cx="${l[0].x * 536}" cy="${l[0].y * 670}" r="3"/><circle cx="${l[1].x * 536}" cy="${l[1].y * 670}" r="3"/>` : '';
      svg.innerHTML = line(m.a) + line(m.b) + (m.angle !== undefined && m.b ? `<text x="${m.b[1].x * 536 + 10}" y="${m.b[1].y * 670}">${m.angle}°</text>` : '');
    }
    const angleOf = (a, b) => {
      const v1 = [a[1].x - a[0].x, (a[1].y - a[0].y) * 1.25], v2 = [b[1].x - b[0].x, (b[1].y - b[0].y) * 1.25];
      let ang = Math.abs(Math.atan2(v1[0] * v2[1] - v1[1] * v2[0], v1[0] * v2[0] + v1[1] * v2[1])) * 180 / Math.PI;
      if (ang > 90) ang = 180 - ang;
      return Math.round(ang);
    };

    function toolsList() {
      const st2 = (k) => (st.tool === k ? 'active' : '');
      const swap = { key: keyCap(KEY('switch', 'KeyF')), label: T('tool_switch', 'Other film'), sub: st.hung === 'ap' ? T('to_lat', 'to lateral') : st.hung === 'lat' ? T('to_ap', 'to AP') : '', icon: 'swap' };
      const win = { key: keyCap(KEY('contrast', 'KeyC')), label: T('tool_contrast', 'Window'), sub: T(`ct_${st.contrast}`, ['Soft', 'Bone', 'Bright'][st.contrast]), icon: 'sliders' };
      if (st.result) return [swap, win];
      const t = [];
      t.push({ key: keyCap(KEY('move', 'Digit1')), label: T('tool_move', 'Hand'), icon: 'hand', state: st2('move') });
      if (!viewOnly) {
        t.push({ key: keyCap(KEY('mark', 'Digit2')), label: T('tool_mark', 'Pin'), icon: 'target', state: st2('mark') });
        t.push({ key: keyCap(KEY('measure', 'Digit3')), label: T('tool_measure', 'Angle'), icon: 'ruler', state: st2('measure') });
      }
      t.push(swap);
      t.push({ key: keyCap(KEY('light', 'KeyL')), label: st.light ? T('tool_light_off', 'Lamp off') : T('tool_light_on', 'Lamp on'), icon: 'light', state: st.light ? '' : 'need' });
      t.push(win);
      return t;
    }
    const STEPS = viewOnly ? [T('step_hang', 'Hang a film'), T('step_view', 'Study the films')] : [T('step_hang', 'Hang a film'), T('step_mark', 'Pin every finding'), T('step_file', 'File the report')];
    function reviewDial() {
      const left = Math.max(0, minMs - (performance.now() - st.opened));
      const frac = minMs > 0 ? clamp(1 - left / minMs, 0, 1) : 1;
      if (st.result) {
        const sc = st.result.error ? 0 : (st.result.score || 0);
        return { label: T('score', 'Score'), value: st.result.error ? '--' : sc, unit: st.result.error ? '' : '/100', tone: sc >= 72 ? 'teal' : sc >= 45 ? 'amber' : 'red', meter: { value: sc / 100, tone: sc >= 72 ? '' : sc >= 45 ? 'amber' : 'red' }, caption: '' };
      }
      if (viewOnly) return null;
      return left > 0
        ? { label: T('s_review', 'Review'), value: Math.ceil(left / 1000), unit: 's', meter: { value: frac, tone: 'white' }, caption: T('s_unlock', 'until the report opens') }
        : { label: T('s_review', 'Review'), value: T('s_open', 'Open'), tone: 'teal', meter: { value: 1 }, caption: T('s_ready', 'File it with {Enter}'), captionTone: 'teal' };
    }
    function pairHTML() {
      return ['ap', 'lat'].map(w => {
        const n = st.pins[w].length;
        const dots = st.pins[w].slice(0, 6).map(p => `<i style="left:${(p.x * 100).toFixed(1)}%;top:${(p.y * 100).toFixed(1)}%"></i>`).join('');
        return `<div class="t ${st.hung === w ? 'hung' : ''} ${n ? 'ok' : ''}">
          <span class="mini"><canvas width="60" height="76" data-mini="${w}"></canvas><span class="fr">${dots}</span>${n ? `<span class="ck">${icon('check')}</span>` : ''}</span>
          <span class="tx"><b>${w === 'ap' ? 'AP' : esc(T('lateral', 'Lateral'))}</b><small>${viewOnly ? esc(st.hung === w ? T('on_viewer', 'On lamp') : T('in_jacket', 'In jacket')) : n ? esc(F(T('pins_n', '%d pinned'), n)) : esc(T('pins_0', 'Nothing pinned'))}</small></span>
        </div>`;
      }).join('');
    }
    function panelText() {
      if (!S.pp) return;
      const filmName = st.hung === 'lat' ? T('lateral', 'Lateral') : st.hung === 'ap' ? 'AP' : T('empty', 'Empty');
      const stats = [
        { id: 'lamp', label: T('s_viewer', 'Lamp'), value: st.light ? T('lit', 'Lit') : T('dark', 'Dark'), small: true, tone: st.light ? 'teal' : 'amber' },
        { id: 'film', label: T('s_on_viewer', 'Clipped'), value: filmName, small: true },
      ];
      if (st.result && !st.result.error) {
        const rows = st.result.rows || [];
        stats.splice(0, 2,
          { id: 'conf', label: T('s_confirmed', 'Confirmed'), value: `${rows.filter(x => x.confirmed).length}/${rows.length}`, tone: rows.every(x => x.confirmed) ? 'teal' : 'amber' },
          { id: 'false', label: T('s_false', 'Stray pins'), value: String(st.result.falsePins || 0), tone: st.result.falsePins ? 'red' : '' });
      }
      let title, text;
      if (st.result) {
        title = st.result.error ? T('read_error', 'Report not saved') : T('read_done', 'Report filed');
        text = st.result.error ? st.result.error : T('read_done_text', 'Compare your pins with the rings. Press {Enter} to close.');
      } else if (!st.hung) {
        title = T('step_hang', 'Hang a film'); text = T('step_hang_text', 'Drag the AP or lateral film from the jacket onto the lamp. {L} switches the lamp.');
      } else if (viewOnly) {
        title = T('step_view', 'Study the films'); text = T('step_view_text', '{F} flips to the other film, scroll to zoom, {C} changes the window, {R} recentres.');
      } else {
        title = T('step_mark', 'Pin every finding');
        text = T('step_mark_text', 'Pin each break or fragment on the AP film with {2}, flip to the lateral with {F} and pin it there too. {1} grabs the film.');
      }
      S.pp.set({ step: st.result ? 3 : st.hung ? 2 : 1, total: STEPS.length, steps: STEPS, title, titleTone: st.result && !st.result.error ? 'ok' : st.result ? 'bad' : '', text, stats, wide: reviewDial(), tools: toolsList() });
      if (pair) {
        pair.innerHTML = pairHTML();
        pair.querySelectorAll('[data-mini]').forEach(c => { const r = renders[c.dataset.mini]; if (r) c.getContext('2d').drawImage(r, 0, 0, 60, 76); });
      }
    }
    let pair = null;

    S.pp = NZA.ui.ProcPanel(root, {
      step: 1, total: STEPS.length, steps: STEPS, tag: T('tag_read', 'Film review'), title: '', text: '', stats: [], tools: [],
      hints: [{ keys: [keyCap(KEY('reset', 'KeyR'))], label: T('hint_reset', 'Recentre') }, { keys: [T('scroll', 'Scroll')], label: T('hint_zoom', 'Zoom') }, { keys: [T('rdrag', 'Right-drag')], label: T('hint_look', 'Orbit') }],
      abort: viewOnly ? { key: 'ESC', label: T('hold_close', 'Hold to close'), seconds: 0.6 } : abortBtn(),
      onAbort: () => { if (st.result) NZA.close(APP); else post('abort'); },
      onTool: (k) => toolKey(k),
    });
    pair = NZA.el('div', 'xr-pair');
    S.pp.slot.prepend(pair);

    function toolKey(k) {
      const map = { [keyCap(KEY('move', 'Digit1'))]: 'move', [keyCap(KEY('mark', 'Digit2'))]: 'mark', [keyCap(KEY('measure', 'Digit3'))]: 'measure' };
      if (map[k]) { if (viewOnly && map[k] !== 'move') return; if (st.result) return; st.tool = map[k]; sound('click'); sheetCursor(); panelText(); return; }
      if (k === keyCap(KEY('switch', 'KeyF'))) return switchFilm();
      if (k === keyCap(KEY('light', 'KeyL'))) { st.light = !st.light; sound('click', st.light ? 900 : 500); applyLight(); panelText(); return; }
      if (k === keyCap(KEY('contrast', 'KeyC'))) { st.contrast = (st.contrast + 1) % 3; sound('click'); applyContrast(); panelText(); }
    }
    function sheetCursor() { sheet.classList.toggle('mark', st.tool === 'mark' || st.tool === 'measure'); sheet.classList.toggle('move', st.tool === 'move'); }
    function switchFilm() {
      const next = st.hung === 'ap' ? 'lat' : 'ap';
      sheet.style.transform = 'translateX(-110%) rotate(-3deg)'; sheet.style.opacity = '0';
      sound('noise', 160, { vol: 0.05, lp: 3000, hp: 700 });
      later(() => { sheet.style.transition = 'none'; sheet.style.transform = 'translateX(110%) rotate(3deg)'; void sheet.offsetWidth; sheet.style.transition = ''; hang(next, true); sheet.style.transform = ''; sheet.style.opacity = ''; }, 220);
    }

    // film coords from a mouse event
    const filmPos = (e) => { const r = sheet.getBoundingClientRect(); return { x: clamp((e.clientX - r.left) / r.width, 0, 1), y: clamp((e.clientY - r.top) / r.height, 0, 1) }; };

    // ── marking / measuring / moving on the sheet
    let drag = null;
    on(sheet, 'mousedown', (e) => {
      if (e.button !== 0 || !st.hung) return;
      e.preventDefault();
      if (st.result) return;
      if (st.tool === 'mark' && !viewOnly) {
        if (!st.light) { S.pp.flash('warn', T('light_needed', 'Switch the lamp on first ({L}).'), 2000); return; }
        const list = st.pins[st.hung];
        if (list.length >= 8) { S.pp.flash('warn', T('too_many', 'Eight pins per film at most.'), 2000); return; }
        list.push(filmPos(e)); sound('click', 1100); drawPins(); thumbs(); panelText(); renderSide();
      } else if (st.tool === 'measure' && !viewOnly) {
        const p = filmPos(e);
        let m = st.measure[st.hung];
        if (!m || m.b) m = st.measure[st.hung] = { a: [p, p] }; else m.b = [p, p];
        drag = { kind: 'measure', m, which: m.b ? 'b' : 'a' };
      } else if (st.tool === 'move') {
        drag = { kind: 'move', x: e.clientX, y: e.clientY, px: st.panX, py: st.panY };
        sheet.classList.add('drag');
      }
    });
    on(window, 'mousemove', (e) => {
      if (!drag) return;
      if (drag.kind === 'measure') { drag.m[drag.which][1] = filmPos(e); if (drag.m.b && drag.which === 'b') drag.m.angle = angleOf(drag.m.a, drag.m.b); drawMeasure(); }
      if (drag.kind === 'move') { st.panX = drag.px + (e.clientX - drag.x) / (NZA.zoom || 1); st.panY = drag.py + (e.clientY - drag.y) / (NZA.zoom || 1); applyView(); }
    });
    on(window, 'mouseup', () => {
      if (!drag) return;
      if (drag.kind === 'measure') { if (drag.which === 'b') { drag.m.angle = angleOf(drag.m.a, drag.m.b); sound('click', 1200); renderSide(); } drawMeasure(); }
      sheet.classList.remove('drag'); drag = null;
    });
    // zoom (wheel) on the lightbox
    on(panel, 'wheel', (e) => {
      e.preventDefault();
      const r = panel.getBoundingClientRect(), z = NZA.zoom || 1;
      const mx = (e.clientX - r.left) / z, my = (e.clientY - r.top) / z;
      const nz = clamp(st.zoom * (e.deltaY < 0 ? 1.15 : 1 / 1.15), 1, 4);
      st.panX = mx - (mx - st.panX) * (nz / st.zoom); st.panY = my - (my - st.panY) * (nz / st.zoom); st.zoom = nz;
      if (nz === 1) { st.panX = 0; st.panY = 0; }
      applyView();
    }, { passive: false });

    // ── drag a film from the jacket onto the viewer
    jacket.querySelectorAll('.xr-thumb').forEach(th => {
      th.addEventListener('mousedown', (e) => {
        if (e.button !== 0) return;
        e.preventDefault();
        const which = th.dataset.film;
        const ghost = NZA.el('div', 'xr-ghost'); ghost.innerHTML = '<canvas width="150" height="188"></canvas>';
        if (renders[which]) ghost.querySelector('canvas').getContext('2d').drawImage(renders[which], 0, 0, 150, 188);
        document.body.appendChild(ghost);
        const mv = (ev) => {
          ghost.style.left = `${ev.clientX}px`; ghost.style.top = `${ev.clientY}px`;
          const r = panel.getBoundingClientRect(); panel.classList.toggle('hot', ev.clientX > r.left && ev.clientX < r.right && ev.clientY > r.top && ev.clientY < r.bottom);
        };
        const up = (ev) => {
          window.removeEventListener('mousemove', mv); window.removeEventListener('mouseup', up); ghost.remove();
          const r = panel.getBoundingClientRect(); panel.classList.remove('hot');
          if (ev.clientX > r.left && ev.clientX < r.right && ev.clientY > r.top && ev.clientY < r.bottom) hang(which);
        };
        mv(e);
        window.addEventListener('mousemove', mv); window.addEventListener('mouseup', up);
        S.off.push(() => { window.removeEventListener('mousemove', mv); window.removeEventListener('mouseup', up); ghost.remove(); });
      });
    });

    function submit(normal) {
      if (viewOnly || st.result || st.sent) return;
      const elapsed = performance.now() - st.opened;
      if (elapsed < minMs) { S.pp.flash('warn', F(T('too_soon', 'Take a closer look first (%ss).'), Math.ceil((minMs - elapsed) / 1000)), 2000); return; }
      if (!normal && (!st.pins.ap.length || !st.pins.lat.length)) { S.pp.flash('warn', T('need_both', 'Pin each finding on both films (AP and lateral), or press {N} if the films are normal.'), 2600); return; }
      st.sent = true; st.normal = !!normal;
      const meas = st.measure.ap && st.measure.ap.b ? { film: 'ap', angle: st.measure.ap.angle } : st.measure.lat && st.measure.lat.b ? { film: 'lat', angle: st.measure.lat.angle } : null;
      const res = { marks: { ap: st.pins.ap, lat: st.pins.lat }, normal: !!normal, measure: meas };
      S.pp.set({ title: T('sending', 'Filing the report...'), text: '', tools: [] });
      sound('click', 700);
      post('finish', res);
      if (!NZA.inGame) later(() => S.m.result(previewScore(film, res)), 500);
    }

    let tick = 0;
    frame(() => { if (++tick % 30 === 0 && !st.result) { const t = win.el.querySelector('[data-timer]'); if (t) t.textContent = NZA.fmt.time((performance.now() - st.opened) / 1000); renderSide(); if (S.pp && !viewOnly) S.pp.wide(reviewDial()); } });

    applyLight(); applyContrast(); applyView(); sheetCursor(); thumbs(); panelText(); renderSide();

    S.m = {
      hang, // preview helper
      key(e) {
        if (st.result) {
          if (e.key === 'Enter') { NZA.close(APP); return true; }
          if (isKey(e, 'switch', 'KeyF') && st.hung) { switchFilm(); return true; }
          if (isKey(e, 'contrast', 'KeyC')) { toolKey(keyCap(KEY('contrast', 'KeyC'))); return true; }
          return false;
        }
        if (e.key === 'Escape' && viewOnly) { NZA.close(APP); return true; }
        if (isKey(e, 'switch', 'KeyF')) { if (st.hung) switchFilm(); else hang('ap'); return true; }
        if (isKey(e, 'reset', 'KeyR')) { st.zoom = 1; st.panX = 0; st.panY = 0; applyView(); return true; }
        if (isKey(e, 'submit', 'Enter')) { submit(false); return true; }
        if (isKey(e, 'normal', 'KeyN') && !viewOnly) { submit(true); return true; }
        if (isKey(e, 'move', 'Digit1')) { toolKey(keyCap(KEY('move', 'Digit1'))); return true; }
        if (isKey(e, 'mark', 'Digit2')) { toolKey(keyCap(KEY('mark', 'Digit2'))); return true; }
        if (isKey(e, 'measure', 'Digit3')) { toolKey(keyCap(KEY('measure', 'Digit3'))); return true; }
        if (isKey(e, 'light', 'KeyL')) { toolKey(keyCap(KEY('light', 'KeyL'))); return true; }
        if (isKey(e, 'contrast', 'KeyC')) { toolKey(keyCap(KEY('contrast', 'KeyC'))); return true; }
        return false;
      },
      result(r) {
        st.result = r || {};
        // colour the pins: inside a finding's ring = hit
        ['ap', 'lat'].forEach(w => st.pins[w].forEach(p => {
          const hit = findings.some(f => f[w] && Math.hypot(f[w].x - p.x, (f[w].y - p.y) * 1.25) <= Math.max(f.r || 0.06, d.tolerance || 0.06));
          p.state = hit ? 'hit' : 'miss';
        }));
        st.tool = 'move';
        jacket.querySelector('[data-legend]').style.display = '';
        win.setStatus([{ key: 'Enter', label: T('done', 'Done') }, { key: keyCap(KEY('switch', 'KeyF')), label: T('tool_switch', 'Other film') }]);
        sound((r && r.score >= 50) ? 'success' : 'fail');
        drawPins(); panelText(); renderSide(); sheetCursor();
        if (S.pp) S.pp.set({ abort: { key: 'ESC', label: T('hold_close', 'Hold to close'), seconds: 0.5 } });
        S.pp.complete({ title: T('read_done', 'Report filed'), text: (r && r.msg) || '', onDone: () => NZA.close(APP) });
        panelText();
        S.pp.set({ tools: [] });
      },
      error(e) { st.result = { error: (e && e.msg) || T('err', 'Something went wrong') }; renderSide(); panelText(); later(() => NZA.close(APP), 3500); },
    };
  }

  // preview only: mirrors the server scoring so the result screen can be shown without the game
  function previewScore(film, res) {
    const tol = 0.06, findings = film.findings || [], rows = [];
    let credit = 0, used = { ap: new Set(), lat: new Set() };
    findings.forEach(f => {
      const hitOn = (w) => { let best = -1, bd = 1e9; (res.marks[w] || []).forEach((p, i) => { if (used[w].has(i)) return; const dd = Math.hypot(p.x - f[w].x, (p.y - f[w].y) * 1.25); if (dd <= Math.max(f.r || tol, tol) && dd < bd) { bd = dd; best = i; } }); if (best >= 0) { used[w].add(best); return bd / Math.max(f.r || tol, tol); } return null; };
      const a = hitOn('ap'), l = hitOn('lat');
      credit += (a !== null ? 0.5 * (1 - 0.35 * a) : 0) + (l !== null ? 0.5 * (1 - 0.35 * l) : 0);
      rows.push({ id: f.id, k: f.k, label: f.label, ap: a !== null, lat: l !== null, confirmed: a !== null && l !== null });
    });
    const falsePins = (res.marks.ap.length - used.ap.size) + (res.marks.lat.length - used.lat.size);
    let score = findings.length ? 100 * credit / findings.length - falsePins * 12 : 100 - falsePins * 24;
    if (res.normal && findings.length) score = 0;
    score = Math.round(clamp(score, 0, 100));
    const grade = score >= 95 ? 'S' : score >= 85 ? 'A' : score >= 72 ? 'B' : score >= 58 ? 'C' : score >= 40 ? 'D' : 'F';
    const conf = rows.filter(r => r.confirmed).length;
    return { score, grade, rows, falsePins, applied: conf, msg: conf === rows.length ? `All ${conf} findings confirmed` : `${conf} of ${rows.length} findings confirmed` };
  }

  /* ═══════════════════════════ MODE: REDUCE (fluoroscopy) ═══════════════════════════ */
  function modeReduce(d) {
    const view = d.view || 'r_leg';
    const kind = viewKind(view);
    const axisKey = ({ femur: 'femur', tibia: 'tibia', tibia_fibula: 'tibia', fibula: 'fibula', humerus: 'humerus', radius: 'radius', radius_ulna: 'radius', ulna: 'ulna' })[d.bone] || (kind === 'arm' ? (d.upper ? 'humerus' : 'radius') : (d.upper ? 'femur' : 'tibia'));
    const lay = (LIMB[kind] || LIMB.leg).ap[axisKey] || LIMB.leg.ap.tibia;
    const t = 0.52;
    const fp = { x: lay[0] + (lay[2] - lay[0]) * t, y: lay[1] + (lay[3] - lay[1]) * t };
    const startAng = Math.max(4, d.angle || 18);
    const sgn = 1;
    const film = {
      id: 'FLUORO', seed: hash(String(d.injury || 'x') + (d.name || '')), view: view.replace(/^l_/, 'r_'), viewLabel: d.regionLabel || '', name: d.name || '',
      findings: [{ id: 'live', k: 'fx', bone: d.bone || axisKey, kind: d.kind || 'closed', disp: true, ang: startAng, phi: 0, shift: 0.5, short: d.short || 10, ap: fp, lat: fp, r: 0.06 }],
    };
    const sim = { ang: startAng * sgn, short: d.short || 10, shift: 0.5, force: 0, target: 0, pain: 0, painOver: 0, slips: 0, fluoro: 0, live: false, lastImg: null,
      grab: null, step: 1, held: 0, started: performance.now(), shownAng: startAng, shownShort: d.short || 10, done: false, jerkCd: 0, releaseFast: 0 };
    const analg = clamp(d.analgesia || 0, 0, 0.8);
    const tol = d.tolerance || 3;
    const NEED = 0.52;                   // traction that pulls the bone out to length
    const PAINF = 0.62 + analg * 0.5;    // force above this hurts

    // DOM
    const dev = NZA.el('div', 'xr-dev xr-fluoro nza-int');
    dev.innerHTML = `
      ${devHead('CA-9', T('dev_carm', 'Mobile C-arm'), '<span class="xr-led" data-led></span>')}
      <div class="xr-scr xr-fl-scr"><canvas width="560" height="560" data-cv></canvas>
        <div class="xr-fl-ov">
          <div class="tl">${esc((d.name || '').toUpperCase())}<br>${esc((d.regionLabel || '').toUpperCase())} · ${esc((d.boneLabel || '').toUpperCase())}<br>AP · 62 kV · 2.1 mA</div>
          <div class="tr"><span class="live" data-live><i></i>LIVE</span><span class="lih" data-lih>LIH</span><br><span data-dose>0.0 s</span></div>
          <div class="bl">${esc(T('angle', 'Angle'))}<br><span class="big" data-ang>--°</span></div>
          <div class="br">${esc(T('shortening', 'Shortening'))}<br><span class="big" data-sh>-- mm</span></div>
        </div></div>`;
    root.appendChild(dev);
    const side = NZA.el('div', 'xr-tr nza-hud solid nza-int');
    side.innerHTML = `
      <h5>${esc(T('traction', 'Traction'))}</h5>
      <div class="xr-gauge"><canvas width="560" height="300" data-g></canvas></div>
      <div class="xr-vm">
        <div class="c"><div class="l">${esc(T('force', 'Force'))}</div><div class="v" data-f>0<small>N</small></div><div data-fm></div></div>
        <div class="c"><div class="l">${esc(T('pain', 'Pain'))}</div><div class="v" data-p>0<small>%</small></div><div data-pm></div></div>
      </div>
      <div class="xr-face" data-face><span class="mood">${icon('face')}</span><div class="t"><b data-ft>${esc(d.name || T('patient', 'Patient'))}</b><span data-fs>${esc(analg > 0.2 ? T('pain_relief', 'Pain relief on board') : T('no_relief', 'No pain relief: go gently'))}</span></div></div>`;
    root.appendChild(side);
    const q = (s) => root.querySelector(s);
    const cv = q('[data-cv]'), g = cv.getContext('2d');
    const gcv = q('[data-g]'), gg = gcv.getContext('2d');
    const fm = NZA.ui.Meter(q('[data-fm]'), { value: 0, zone: [NEED, PAINF], tone: '' });
    const pm = NZA.ui.Meter(q('[data-pm]'), { value: 0, tone: 'red' });

    let scene = null;
    const W = 900;
    fontsReady.then(() => { scene = fluoroScene(film, 'ap', 'live', W); shoot(); });
    // crop around the fracture
    const crop = { cx: fp.x * W, cy: fp.y * W * 1.25, size: W * 0.36 };
    const k = 560 / crop.size;
    function shoot() {
      if (!scene) return;
      const off = mk(560, 560), o = off.getContext('2d');
      o.fillStyle = '#000'; o.fillRect(0, 0, 560, 560);
      o.save(); o.setTransform(k, 0, 0, k, -(crop.cx - crop.size / 2) * k, -(crop.cy - crop.size / 2) * k);
      o.drawImage(scene.base, 0, 0);
      o.restore();
      o.save(); o.setTransform(k, 0, 0, k, -(crop.cx - crop.size / 2) * k, -(crop.cy - crop.size / 2) * k);
      scene.distal.forEach(dd => dd.draw(o, { ang: rad(sim.ang), shift: Math.sign(sim.ang || 1) * dd.wAt * (0.08 + 0.55 * Math.min(1, Math.abs(sim.ang) / startAng)), short: sim.short * scene.C.H / 1000 }));
      o.restore();
      // image intensifier look: inverted greys are typical for fluoro; keep radiograph polarity, add noise + circle
      grain(o, 560, 560, Math.floor(Math.random() * 999), 0.9);
      const vg = o.createRadialGradient(280, 280, 200, 280, 280, 290); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,1)');
      o.fillStyle = vg; o.fillRect(0, 0, 560, 560);
      o.strokeStyle = 'rgba(15,212,196,.25)'; o.setLineDash([4, 6]); o.beginPath(); o.moveTo(280, 30); o.lineTo(280, 530); o.moveTo(30, 280); o.lineTo(530, 280); o.stroke(); o.setLineDash([]);
      sim.lastImg = off; sim.shownAng = Math.abs(sim.ang); sim.shownShort = sim.short;
    }
    function paint() {
      g.clearRect(0, 0, 560, 560);
      if (sim.lastImg) g.drawImage(sim.lastImg, 0, 0);
      // traction arrow while pulling
      if (sim.grab) {
        g.save(); g.strokeStyle = sim.force > PAINF ? '#ff5a5f' : sim.force >= NEED ? '#0fd4c4' : '#f3c35a'; g.lineWidth = 3; g.lineCap = 'round';
        g.beginPath(); g.moveTo(sim.grab.x0, sim.grab.y0); g.lineTo(sim.grab.x, sim.grab.y); g.stroke();
        g.beginPath(); g.arc(sim.grab.x0, sim.grab.y0, 9, 0, TAU); g.stroke(); g.restore();
      }
      q('[data-ang]').textContent = `${Math.round(sim.shownAng)}°`;
      q('[data-ang]').className = `big ${sim.shownAng <= tol ? 'ok' : sim.shownAng > 12 ? 'bad' : ''}`;
      q('[data-sh]').textContent = `${Math.round(sim.shownShort)} mm`;
      q('[data-sh]').className = `big ${sim.shownShort <= 1 ? 'ok' : ''}`;
      q('[data-live]').classList.toggle('on', sim.live); q('[data-lih]').style.display = sim.live ? 'none' : '';
      q('[data-led]').className = `xr-led ${sim.live ? 'red' : ''}`;
      q('[data-dose]').textContent = `${sim.fluoro.toFixed(1)} s`;
      const N = Math.round(sim.force * 320);
      q('[data-f]').innerHTML = `${N}<small>N</small>`; q('[data-f]').className = `v ${sim.force > PAINF ? 'bad' : sim.force >= NEED ? 'ok' : ''}`;
      fm.set({ value: sim.force, tone: sim.force > PAINF ? 'red' : sim.force >= NEED ? '' : 'amber' });
      q('[data-p]').innerHTML = `${Math.round(sim.pain * 100)}<small>%</small>`; q('[data-p]').className = `v ${sim.pain > 0.85 ? 'bad' : sim.pain > 0.5 ? 'warn' : ''}`;
      pm.set({ value: sim.pain });
      const face = q('[data-face]'); face.className = `xr-face ${sim.pain > 0.85 ? 'bad' : sim.pain > 0.5 ? 'warn' : ''}`;
      // gauge: force trace
      gauge();
      if (S.pp) readout();
    }
    const trace = [];
    function gauge() {
      trace.push(sim.force); if (trace.length > 140) trace.shift();
      const w = 560, h = 300; gg.clearRect(0, 0, w, h);
      gg.fillStyle = 'rgba(8,175,162,.10)'; gg.fillRect(0, h - PAINF * h, w, (PAINF - NEED) * h);
      gg.strokeStyle = 'rgba(255,255,255,.06)'; for (let i = 1; i < 6; i++) { gg.beginPath(); gg.moveTo(0, h * i / 6); gg.lineTo(w, h * i / 6); gg.stroke(); }
      gg.strokeStyle = 'rgba(255,90,95,.5)'; gg.setLineDash([6, 6]); gg.beginPath(); gg.moveTo(0, h - PAINF * h); gg.lineTo(w, h - PAINF * h); gg.stroke(); gg.setLineDash([]);
      gg.strokeStyle = '#0fd4c4'; gg.lineWidth = 3; gg.beginPath();
      trace.forEach((v, i) => { const x = w - (trace.length - 1 - i) * 4, y = h - clamp(v, 0, 1) * h; i ? gg.lineTo(x, y) : gg.moveTo(x, y); }); gg.stroke();
      gg.fillStyle = 'rgba(255,255,255,.5)'; gg.font = '600 20px Lexend, sans-serif'; gg.fillText(T('pain_line', 'pain'), 12, h - PAINF * h - 8);
      gg.fillStyle = 'rgba(15,212,196,.75)'; gg.fillText(T('length_zone', 'out to length'), 12, h - NEED * h + 26);
    }
    // the axis of the bone on the screen (fluoro image), pointing to the distal end
    const axisDir = (() => { const dx = (lay[2] - lay[0]) * W, dy = (lay[3] - lay[1]) * W * 1.25, l = Math.hypot(dx, dy); return { x: dx / l, y: dy / l }; })();

    on(cv, 'mousedown', (e) => {
      if (e.button !== 0 || sim.done) return; e.preventDefault();
      const r = cv.getBoundingClientRect(), sx = 560 / r.width;
      const x = (e.clientX - r.left) * sx, y = (e.clientY - r.top) * sx;
      sim.grab = { x0: x, y0: y, x, y, sx, r, a0: sim.ang };
      cv.classList.add('grab'); sound('click', 300);
    });
    on(window, 'mousemove', (e) => {
      if (!sim.grab) return;
      const r = sim.grab.r;
      sim.grab.x = (e.clientX - r.left) * sim.grab.sx; sim.grab.y = (e.clientY - r.top) * sim.grab.sx;
    });
    on(window, 'mouseup', () => { if (sim.grab) { sim.grab = null; cv.classList.remove('grab'); } });

    let last = performance.now(), speakCd = 0;
    frame((now) => {
      const dt = Math.min(0.05, (now - last) / 1000); last = now;
      if (!sim.done) {
        // force follows how far you pull along the bone
        let along = 0, across = 0;
        if (sim.grab) {
          const dx = sim.grab.x - sim.grab.x0, dy = sim.grab.y - sim.grab.y0;
          along = dx * axisDir.x + dy * axisDir.y;
          across = dx * -axisDir.y + dy * axisDir.x;
          sim.target = clamp(along / 230, 0, 1.15);
        } else sim.target = 0;
        const prev = sim.force;
        sim.force += (sim.target - sim.force) * Math.min(1, dt * (sim.grab ? 6 : 9));
        const drop = (prev - sim.force) / dt;
        // traction restores length
        if (sim.force >= NEED) sim.short = Math.max(0, sim.short - dt * 9 * (sim.force / NEED));
        else sim.short = Math.min(d.short || 10, sim.short + dt * 3 * (1 - sim.force / NEED));
        // angle can only be corrected once the ends are out to length
        if (sim.grab) {
          const want = sim.grab.a0 + across / 7;
          const free = sim.short <= 1.5 ? 1 : 0.12;
          sim.ang += (want - sim.ang) * Math.min(1, dt * 5 * free);
          if (free < 1 && Math.abs(want - sim.ang) > 3 && Math.random() < dt * 3) { sound('noise', 80, { vol: 0.08, lp: 900, hp: 200 }); sim.pain = Math.min(1.2, sim.pain + 0.06); }
          if (free === 1) sim.grab.a0 = sim.ang - across / 7;
        }
        // muscles pull a free fragment back when you let go fast
        if (drop > 2.2 && Math.abs(sim.ang) <= tol + 1 && sim.step >= 2 && prev > NEED * 0.7) {
          sim.releaseFast += dt;
          if (sim.releaseFast > 0.08) {
            sim.releaseFast = 0; sim.slips++; sim.ang += (Math.random() < 0.5 ? -1 : 1) * startAng * (0.3 + Math.random() * 0.25); sim.short = Math.max(sim.short, 3);
            S.pp && S.pp.flash('bad', T('slipped', 'You let go too fast: the bone slipped. Pull it out to length again.'), 2600); sound('fail');
          }
        }
        // pain
        const over = Math.max(0, sim.force - PAINF);
        sim.pain = clamp(sim.pain + (over * 2.6 - 0.35) * dt + (sim.force > NEED ? 0.02 * dt : 0), 0, 1.2);
        sim.jerkCd = Math.max(0, sim.jerkCd - dt);
        if (sim.pain >= 1 && !sim.jerkCd) {
          sim.jerkCd = 2.5; sim.painOver++; sim.ang += (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 5); sim.force *= 0.4; if (sim.grab) sim.grab = null;
          S.pp && S.pp.flash('bad', T('too_hard', 'Too much force: the patient pulled away.'), 2400); sound('fail');
          NZA.speech({ name: d.name || '', text: T('scream', 'AAARGH! Stop, stop!'), ms: 1800 });
        } else if (sim.pain > 0.7 && (speakCd -= dt) < 0) { speakCd = 4; NZA.speech({ name: d.name || '', text: T('groan', 'Ngh... that really hurts...'), ms: 1600 }); }
        // live fluoro
        if (sim.live) { sim.fluoro += dt; shoot(); }
        // steps
        if (sim.step === 1 && sim.short <= 1 && sim.force >= NEED) { sim.held += dt; if (sim.held > 0.6) setStep(2); } else if (sim.step === 1) sim.held = 0;
        if (sim.step === 2 && Math.abs(sim.ang) <= tol && sim.short <= 1.5 && sim.force >= NEED * 0.85) { sim.held += dt; if (sim.held > 1.0) setStep(3); } else if (sim.step === 2) sim.held = 0;
        if (sim.step === 3 && Math.abs(sim.ang) > tol + 1.5) setStep(2);
      }
      paint();
    });

    let roKey = '';
    function readout() {
      const ang = Math.round(sim.shownAng), sh = Math.round(sim.shownShort), fl = sim.fluoro.toFixed(1), grip = sim.force < 0.08 ? 0 : 1;
      const key = `${ang}|${sh}|${fl}|${grip}|${sim.step}`;
      if (key === roKey) return;
      roKey = key;
      const span = Math.max(startAng, 20), ok = ang <= tol;
      S.pp.set({
        wide: { label: T('angle', 'Angle'), value: ang, unit: '°', tone: ok ? 'teal' : '', meter: { value: clamp(ang / span, 0, 1), zone: [0, tol / span], tone: ok ? '' : 'amber' },
          caption: sim.step === 3 ? (grip ? T('holding', 'Holding') : T('released', 'Released')) : F(T('angle_goal', 'Bring it under %s°'), tol), captionTone: ok ? 'teal' : '' },
        stats: [
          { id: 'short', label: T('shortening', 'Shortening'), value: sh, unit: 'mm', tone: sh <= 1 ? 'teal' : 'amber' },
          { id: 'dose', label: T('dose', 'Fluoro'), value: fl, unit: 's', tone: sim.fluoro > (d.fluoroBudget || 12) ? 'amber' : '' },
          { id: 'rel', label: T('grip', 'Grip'), value: grip ? T('holding', 'Holding') : T('released', 'Released'), small: true, tone: grip ? '' : 'teal' },
        ],
      });
    }
    function setStep(n) {
      sim.step = n; sim.held = 0; sound('success');
      const texts = {
        1: [T('red_1', 'Pull it out to length'), T('red_1_text', 'Grab the lower piece on the screen and **pull along the bone** until the ends no longer overlap. Hold {F} for a live image.')],
        2: [T('red_2', 'Correct the angle'), T('red_2_text', 'Keep the traction and **move sideways** to bring the angle to 0°. Tap {F} to check, too much force hurts.')],
        3: [T('red_3', 'Release and check'), T('red_3_text', 'Ease off **slowly**: move the mouse back before you let go. Take a check image with {F}, then press {Enter}.')],
      };
      S.pp.set({ step: n, steps: [texts[1][0], texts[2][0], texts[3][0]], title: texts[n][0], text: texts[n][1], tools: toolsR() });
    }
    const toolsR = () => [
      { key: 'LMB', label: T('tool_pull', 'Pull / align'), icon: 'hand', state: sim.grab ? 'active' : '' },
      { key: keyCap(KEY('fluoro', 'KeyF')), label: T('tool_fluoro', 'Live fluoro'), icon: 'xray', state: sim.live ? 'active' : '' },
      { key: 'Enter', label: T('tool_done', 'Finish'), icon: 'check', state: sim.step === 3 ? '' : 'locked' },
    ];
    S.pp = NZA.ui.ProcPanel(root, {
      step: 1, total: 3, tag: T('tag_reduce', 'Set the bone'), title: '', text: '',
      stats: [], tools: [], abort: abortBtn(), onAbort: () => post('abort'),
    });
    setStep(1);
    readout();
    function finish() {
      if (sim.done) return;
      if (sim.step < 3) { S.pp.flash('warn', T('not_yet', 'The bone is not set yet.'), 1800); return; }
      if (sim.force > 0.12) { S.pp.flash('warn', T('release_first', 'Release the traction slowly first.'), 1800); return; }
      sim.done = true;
      const angLeft = Math.abs(sim.ang);
      const budget = d.fluoroBudget || 12;
      let score = 100 - angLeft * 6 - sim.short * 4 - sim.painOver * 12 - sim.slips * 10 - Math.max(0, sim.fluoro - budget) * 2;
      score = Math.round(clamp(score, 0, 100));
      post('finish', { score, angle: Math.round(angLeft * 10) / 10, short: Math.round(sim.short * 10) / 10, slips: sim.slips, painOver: sim.painOver, fluoro: Math.round(sim.fluoro * 10) / 10 });
      S.pp.set({ title: T('saving', 'Saving...'), text: '', tools: [] });
      if (!NZA.inGame) later(() => S.m.result({ score, grade: score >= 85 ? 'A' : score >= 72 ? 'B' : 'C', angle: Math.round(angLeft), before: startAng, reduced: angLeft <= tol, msg: `Bone set: ${Math.round(angLeft)}° left` }), 400);
    }
    S.m = {
      key(e) {
        if (isKey(e, 'fluoro', 'KeyF')) { if (!sim.live) { sim.live = true; shoot(); sound('tone', 140, 160, { vol: 0.05, type: 'sawtooth' }); S.pp.set({ tools: toolsR() }); } return true; }
        if (e.key === 'Enter') { if (S.pp && S.pp.key(e)) return true; finish(); return true; }
        return false;
      },
      keyUp(e) { if (isKey(e, 'fluoro', 'KeyF')) { sim.live = false; S.pp && S.pp.set({ tools: toolsR() }); return true; } return false; },
      result(r) { resultCard(r, [[T('angle_left', 'Angle left'), `${r.angle ?? '-'}°`, r.reduced ? 'ok' : 'warn'], [T('before', 'Before'), `${r.before ?? startAng}°`, ''], [T('slips', 'Slips'), sim.slips, sim.slips ? 'warn' : 'ok'], [T('dose', 'Fluoro'), `${sim.fluoro.toFixed(1)} s`, sim.fluoro > (d.fluoroBudget || 12) ? 'warn' : 'ok']]); },
      _sim: sim, _shoot: shoot, _setStep: setStep,
    };
  }

  function resultCard(r, rows) {
    r = r || {};
    const card = NZA.el('div', 'xr-card nza-hud solid nza-int');
    card.innerHTML = `<div class="hd">${scoreRing(r.score, 72)}<div><div class="xr-k">${esc(T('score', 'Score'))}</div><h4>${esc(r.score ?? '--')}<span style="font-size:12px;color:var(--ink-3);font-weight:500">/100</span></h4><p>${esc(r.msg || '')}</p></div></div>
      <div class="rows">${rows.map(x => `<div class="rw"><span>${esc(x[0])}</span><b class="${x[2] || ''}">${esc(x[1])}</b></div>`).join('')}</div>
      <div class="ft"><button class="btn-teal" data-ok><kbd style="background:rgba(0,0,0,.18);border-color:rgba(0,0,0,.25);color:var(--on-teal)">Enter</kbd>${esc(T('done', 'Done'))}</button></div>`;
    root.appendChild(card);
    card.querySelector('[data-ok]').onclick = () => NZA.close(APP);
    if (S.pp) S.pp.complete({ title: T('complete', 'Complete'), text: r.msg || '', onDone: () => NZA.close(APP) });
    sound((r.score || 0) >= 50 ? 'success' : 'fail');
  }

  /* ═══════════════════════════ MODE: CAST ═══════════════════════════ */
  function modeCast(d) {
    const leg = !!d.leg;
    const minL = d.layersMin || 3, maxL = d.layersMax || 6;
    const N = 24;                                   // cells along the cast
    const st = { step: 1, pad: new Array(N).fill(0), layers: new Array(N).fill(0), turn: 0, lastV: null, mould: 0, setting: 0, cracks: 0, still: 0,
      cursor: null, down: false, done: false, mouldHeld: false, last: null, rolls: 0 };
    const head = NZA.el('div', 'xr-cast nza-hud solid nza-int');
    const castName = T(`cast_${d.castType || (leg ? 'short_leg' : 'short_arm')}`, leg ? 'Leg cast' : 'Arm cast');
    head.innerHTML = `
      <div class="xr-cast-head"><div><div class="t">${esc(castName)}</div><div class="s">${esc(d.regionLabel || '')} · ${esc(d.boneLabel || '')}</div></div><span class="sp"></span>
        <span class="chipx sm">${esc(F(T('layers_goal', '%s–%s layers'), minL, maxL))}</span></div>
      <div class="xr-cast-cv"><canvas width="1980" height="860" data-cv></canvas></div>
      <div class="xr-cast-strip"><span class="l">${esc(T('coverage', 'Coverage'))}</span><div class="cells" data-cells>${'<i></i>'.repeat(N)}</div>
        <div class="lg"><span><i style="background:rgba(229,165,10,.6)"></i>${esc(T('thin', 'Thin'))}</span><span><i style="background:var(--teal)"></i>${esc(T('good', 'Good'))}</span><span><i style="background:var(--red)"></i>${esc(T('heavy', 'Too thick'))}</span></div></div>`;
    root.appendChild(head);
    const cv = head.querySelector('[data-cv]'), g = cv.getContext('2d');
    const CW = 1980, CH = 860;
    // limb geometry on the canvas (proximal left → distal right)
    const x0 = 260, x1 = 1640, cy = 430;
    const radiusAt = (x) => { const t = clamp((x - x0) / (x1 - x0), 0, 1); return leg ? lerp(150, 92, sstep(0, 0.85, t)) : lerp(118, 78, sstep(0, 0.85, t)); };
    const cellOf = (x) => clamp(Math.floor((x - x0) / (x1 - x0) * N), 0, N - 1);
    const fracX = lerp(x0, x1, 0.5);
    const toCanvas = (e) => { const r = cv.getBoundingClientRect(); return { x: (e.clientX - r.left) * CW / r.width, y: (e.clientY - r.top) * CH / r.height }; };

    on(cv, 'mousedown', (e) => { if (e.button !== 0 || st.done) return; e.preventDefault(); st.down = true; st.lastV = null; st.cursor = toCanvas(e); st.last = st.cursor; });
    on(window, 'mouseup', () => { st.down = false; st.lastV = null; });
    on(cv, 'mousemove', (e) => {
      const p = toCanvas(e);
      const prev = st.cursor || p;
      st.cursor = p;
      const mv = Math.hypot(p.x - prev.x, p.y - prev.y);
      if (st.step === 3 && st.setting > 0) st.still += mv;
      if (!st.down || st.done) return;
      if (st.step === 1) {
        // roll the padding along the limb
        const c = cellOf(p.x); if (Math.abs(p.y - cy) < radiusAt(p.x) + 60) { for (let i = Math.max(0, c - 1); i <= Math.min(N - 1, c + 1); i++) st.pad[i] = Math.min(1, st.pad[i] + mv / 140); }
        if (Math.random() < 0.15) sound('noise', 60, { vol: 0.03, lp: 2500, hp: 900 });
      } else if (st.step === 2) {
        // circle the cursor: every full turn lays one plaster turn where the cursor is along the limb
        const v = { x: p.x - prev.x, y: p.y - prev.y };
        if (Math.hypot(v.x, v.y) > 2) {
          if (st.lastV) {
            let a = Math.atan2(v.y, v.x) - Math.atan2(st.lastV.y, st.lastV.x);
            while (a > Math.PI) a -= TAU; while (a < -Math.PI) a += TAU;
            st.turn += Math.abs(a);
            if (st.turn >= TAU) {
              st.turn -= TAU;
              const c = cellOf(p.x);
              for (let i = Math.max(0, c - 1); i <= Math.min(N - 1, c + 1); i++) st.layers[i] += i === c ? 1 : 0.5;
              st.rolls++; sound('noise', 140, { vol: 0.06, lp: 1600, hp: 300 }); sound('click', 500 + Math.random() * 80);
            }
          }
          st.lastV = v;
        }
      }
    });

    // procedure drape under the limb (cached): woven blue cloth, folds, soft key light
    const drape = mk(CW, CH);
    (() => {
      const dg = drape.getContext('2d');
      const base = dg.createLinearGradient(0, 0, 0, CH); base.addColorStop(0, '#16303a'); base.addColorStop(0.5, '#1d4150'); base.addColorStop(1, '#122630');
      dg.fillStyle = base; dg.fillRect(0, 0, CW, CH);
      const R = mulberry(77);
      dg.globalAlpha = 0.07;
      for (let y = 0; y < CH; y += 3) { dg.fillStyle = y % 6 ? '#000' : '#9fd'; dg.fillRect(0, y, CW, 1); }
      for (let x = 0; x < CW; x += 3) { dg.fillStyle = x % 6 ? '#000' : '#8cf'; dg.fillRect(x, 0, 1, CH); }
      dg.globalAlpha = 1;
      for (let i = 0; i < 7; i++) {            // soft folds
        const y = 60 + R() * (CH - 120), a = (R() - 0.5) * 0.12;
        const fg = dg.createLinearGradient(0, y - 30, 0, y + 30); fg.addColorStop(0, 'rgba(0,0,0,0)'); fg.addColorStop(0.5, 'rgba(0,0,0,.22)'); fg.addColorStop(0.56, 'rgba(160,220,235,.08)'); fg.addColorStop(1, 'rgba(0,0,0,0)');
        dg.save(); dg.translate(CW / 2, y); dg.rotate(a); dg.fillStyle = fg; dg.fillRect(-CW, -30, CW * 2, 60); dg.restore();
      }
      const key = dg.createRadialGradient(CW * 0.45, CH * 0.35, 40, CW * 0.45, CH * 0.4, CW * 0.65);
      key.addColorStop(0, 'rgba(255,248,235,.16)'); key.addColorStop(1, 'rgba(0,0,0,.45)');
      dg.fillStyle = key; dg.fillRect(0, 0, CW, CH);
    })();
    function paint(now) {
      g.clearRect(0, 0, CW, CH);
      g.drawImage(drape, 0, 0);
      // table shadow & limb
      g.fillStyle = 'rgba(0,0,0,.35)'; g.beginPath(); g.ellipse((x0 + x1) / 2, cy + 190, (x1 - x0) / 2 + 160, 40, 0, 0, TAU); g.fill();
      const top = [], bot = [];
      for (let x = -40; x <= x1 + 40; x += 20) { const r = radiusAt(x); top.push([x, cy - r]); bot.push([x, cy + r]); }
      const skin = g.createLinearGradient(0, cy - 160, 0, cy + 160); skin.addColorStop(0, '#a87a5c'); skin.addColorStop(0.18, '#cf9f80'); skin.addColorStop(0.42, '#e2b494'); skin.addColorStop(0.75, '#b07c5c'); skin.addColorStop(1, '#6a4532');
      // contact shadow right under the limb
      g.save(); g.filter = 'blur(18px)'; g.fillStyle = 'rgba(0,0,0,.45)'; g.beginPath(); g.ellipse((x0 + x1) / 2 + 40, cy + 150, (x1 - x0) / 2 + 120, 34, 0, 0, TAU); g.fill(); g.restore();
      g.beginPath(); top.forEach((p, i) => (i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1]))); bot.slice().reverse().forEach(p => g.lineTo(p[0], p[1])); g.closePath(); g.fillStyle = skin; g.fill();
      // hand / foot at the distal end
      g.fillStyle = skin;
      if (leg) {
        g.beginPath(); g.moveTo(x1 + 10, cy - 88); g.bezierCurveTo(x1 + 60, cy - 120, x1 + 70, cy - 230, x1 + 90, cy - 300);
        g.bezierCurveTo(x1 + 100, cy - 330, x1 + 150, cy - 335, x1 + 165, cy - 305); g.bezierCurveTo(x1 + 190, cy - 230, x1 + 205, cy - 120, x1 + 215, cy - 20);
        g.bezierCurveTo(x1 + 225, cy + 60, x1 + 190, cy + 105, x1 + 140, cy + 100); g.lineTo(x1 + 10, cy + 92); g.closePath(); g.fill();
        // foot form: sole in shade, ankle knuckle, toe creases
        g.save(); g.clip();
        const fs = g.createLinearGradient(x1 + 60, 0, x1 + 225, 0); fs.addColorStop(0, 'rgba(0,0,0,0)'); fs.addColorStop(0.5, 'rgba(0,0,0,0)'); fs.addColorStop(1, 'rgba(40,20,10,.4)');
        g.fillStyle = fs; g.fillRect(x1, cy - 340, 240, 460);
        const ank = g.createRadialGradient(x1 + 40, cy - 10, 4, x1 + 40, cy - 10, 60); ank.addColorStop(0, 'rgba(255,236,220,.14)'); ank.addColorStop(1, 'rgba(255,236,220,0)');
        g.fillStyle = ank; g.beginPath(); g.ellipse(x1 + 40, cy - 10, 60, 48, 0, 0, TAU); g.fill();
        g.strokeStyle = 'rgba(90,50,30,.35)'; g.lineWidth = 2.5;
        [[cy - 262, 0.0], [cy - 284, 0.08], [cy - 304, 0.14]].forEach(([y, k]) => { g.beginPath(); g.moveTo(x1 + 104 + k * 60, y); g.quadraticCurveTo(x1 + 140, y - 8, x1 + 176 - k * 40, y + 4); g.stroke(); });
        g.restore();
      }
      else { g.beginPath(); g.moveTo(x1 + 20, cy - 70); g.quadraticCurveTo(x1 + 200, cy - 110, x1 + 300, cy - 40); g.quadraticCurveTo(x1 + 330, cy + 10, x1 + 300, cy + 60); g.quadraticCurveTo(x1 + 200, cy + 100, x1 + 20, cy + 76); g.closePath(); g.fill(); }
      // fracture zone marker
      g.save(); g.strokeStyle = st.step === 3 ? 'rgba(15,212,196,.9)' : 'rgba(255,90,95,.55)'; g.setLineDash([10, 10]); g.lineWidth = 3;
      g.beginPath(); g.ellipse(fracX, cy, 90, radiusAt(fracX) + 34, 0, 0, TAU); g.stroke(); g.restore();
      // smooth hulls for padding and plaster (thickness follows the cell values, interpolated)
      const at = (arr, x) => { const f = (x - x0) / (x1 - x0) * N - 0.5, i = Math.floor(f), t = f - i; const v0 = arr[clamp(i, 0, N - 1)], v1 = arr[clamp(i + 1, 0, N - 1)]; return lerp(v0, v1, clamp(t, 0, 1)); };
      const hull = (arr, base, per, min) => {
        const segs = []; let cur = null;
        for (let x = x0; x <= x1; x += 8) {
          const v = at(arr, x);
          if (v > min) { if (!cur) { cur = []; segs.push(cur); } cur.push([x, radiusAt(x) + base + Math.min(10, v) * per]); } else cur = null;
        }
        return segs;
      };
      const fillHull = (seg, fill) => {
        g.beginPath(); seg.forEach((p, i) => (i ? g.lineTo(p[0], cy - p[1]) : g.moveTo(p[0], cy - p[1])));
        seg.slice().reverse().forEach(p => g.lineTo(p[0], cy + p[1])); g.closePath(); g.fillStyle = fill; g.fill();
        const sh = g.createLinearGradient(0, cy - 200, 0, cy + 200); sh.addColorStop(0, 'rgba(255,255,255,.22)'); sh.addColorStop(0.35, 'rgba(255,255,255,0)'); sh.addColorStop(0.7, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.32)');
        g.fillStyle = sh; g.fill();
      };
      hull(st.pad, 6, 2, 0.05).forEach(seg => {
        g.save(); fillHull(seg, 'rgba(238,240,236,.92)'); g.clip();
        g.strokeStyle = 'rgba(196,200,196,.5)'; g.lineWidth = 2;
        for (let y = cy - 200; y < cy + 200; y += 14) { g.beginPath(); g.moveTo(seg[0][0], y); g.lineTo(seg[seg.length - 1][0], y + 10); g.stroke(); }
        g.restore();
      });
      const wet = st.step < 3 ? 1 : 1 - clamp(st.setting, 0, 1);
      const shade = Math.round(lerp(248, 206, wet));
      hull(st.layers, 12, 2.6, 0.05).forEach(seg => {
        g.save(); fillHull(seg, `rgb(${shade},${shade},${shade - 6})`); g.clip();
        // the edges of the plaster turns, darker where it is thin
        for (let x = seg[0][0] - 200; x < seg[seg.length - 1][0] + 200; x += 22) {
          const n = at(st.layers, clamp(x, x0, x1));
          g.strokeStyle = `rgba(120,120,112,${clamp(0.35 - n * 0.04, 0.08, 0.35)})`; g.lineWidth = 2.4;
          g.beginPath(); g.moveTo(x - 60, cy - 220); g.lineTo(x + 60, cy + 220); g.stroke();
        }
        for (let i = 0; i < seg.length; i++) {         // thin spots show the padding through
          const n = at(st.layers, seg[i][0]);
          if (n < minL) { g.fillStyle = `rgba(150,140,120,${0.18 * (1 - n / minL)})`; g.fillRect(seg[i][0] - 4, cy - 300, 9, 600); }
        }
        g.restore();
      });
      // highlights for the 3D look
      const hl = g.createLinearGradient(0, cy - 180, 0, cy + 180); hl.addColorStop(0, 'rgba(255,255,255,.18)'); hl.addColorStop(0.3, 'rgba(255,255,255,0)'); hl.addColorStop(0.75, 'rgba(0,0,0,0)'); hl.addColorStop(1, 'rgba(0,0,0,.3)');
      g.save(); g.beginPath(); top.forEach((p, i) => (i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1]))); bot.slice().reverse().forEach(p => g.lineTo(p[0], p[1])); g.closePath(); g.clip();
      g.fillStyle = hl; g.fillRect(-40, cy - 220, x1 + 80, 440); g.restore();
      // cracks while setting
      for (let k = 0; k < st.cracks; k++) { const x = fracX - 60 + k * 50; g.strokeStyle = 'rgba(60,60,60,.8)'; g.lineWidth = 3; g.beginPath(); g.moveTo(x, cy - 80); g.lineTo(x + 14, cy - 30); g.lineTo(x - 6, cy + 10); g.lineTo(x + 10, cy + 60); g.stroke(); }
      // cursor tool
      if (st.cursor && !st.done) {
        const p = st.cursor;
        g.save(); g.strokeStyle = st.down ? '#0fd4c4' : 'rgba(255,255,255,.6)'; g.lineWidth = 3;
        if (st.step === 2) { g.beginPath(); g.arc(p.x, p.y, 46, 0, TAU); g.stroke(); g.beginPath(); g.arc(p.x, p.y, 46, -Math.PI / 2, -Math.PI / 2 + st.turn); g.strokeStyle = '#0fd4c4'; g.lineWidth = 7; g.stroke(); }
        else if (st.step === 3) { g.beginPath(); g.ellipse(p.x, p.y, 70, 40, 0, 0, TAU); g.stroke(); }
        else { g.beginPath(); g.roundRect ? g.roundRect(p.x - 34, p.y - 70, 68, 140, 18) : g.rect(p.x - 34, p.y - 70, 68, 140); g.stroke(); }
        g.restore();
      }
      void now;
    }
    function cells() {
      const els = head.querySelectorAll('[data-cells] i');
      els.forEach((el, i) => {
        let c = '';
        if (st.step === 1) c = st.pad[i] >= 0.95 ? 'pad' : '';
        else { const n = st.layers[i]; c = n <= 0 ? '' : n < minL * 0.5 ? 'l1' : n < minL ? 'l2' : n <= maxL ? 'ok' : 'hi'; }
        el.className = c;
      });
    }
    const padCov = () => st.pad.filter(v => v >= 0.95).length / N;
    const layerStats = () => { const mn = Math.min(...st.layers), mx = Math.max(...st.layers); const good = st.layers.filter(n => n >= minL && n <= maxL).length / N; return { mn, mx, good }; };
    function setStep(n) {
      st.step = n; sound('success');
      const t = {
        1: [T('cast_1', 'Stockinette and padding'), T('cast_1_text', 'Hold the mouse and **sweep along the whole limb** to roll on the stockinette and padding.')],
        2: [T('cast_2', 'Wrap the plaster'), F(T('cast_2_text', 'Hold the mouse and **circle** over the limb: every circle lays one plaster turn there. Give every part %s to %s layers.'), minL, maxL)],
        3: [T('cast_3', 'Mould and let it set'), T('cast_3_text', 'Hold {Space} with the cursor on the **break** to mould the plaster, release in the green band, then keep the mouse still while it sets.')],
      };
      S.pp.set({ step: n, steps: [t[1][0], t[2][0], t[3][0]], title: t[n][0], text: t[n][1], stats: statsC(), tools: toolsC() });
    }
    const toolsC = () => [
      { key: 'LMB', label: st.step === 1 ? T('tool_pad', 'Roll padding') : T('tool_wrap', 'Wrap plaster'), icon: 'gauze', state: st.step < 3 ? 'active' : 'done' },
      { key: keyCap(KEY('mould', 'Space')), label: T('tool_mould', 'Mould'), icon: 'hand', state: st.step === 3 ? (st.mouldHeld ? 'active' : '') : 'locked' },
      { key: 'Enter', label: st.step < 3 ? T('tool_next', 'Next step') : T('tool_done', 'Finish'), icon: 'check' },
    ];
    const statsC = () => {
      if (st.step === 1) return [{ id: 'cov', label: T('padding', 'Padding'), value: Math.round(padCov() * 100), unit: '%', meter: { value: padCov(), zone: [0.95, 1] } }];
      if (st.step === 2) { const s = layerStats(); return [{ id: 'mn', label: T('thinnest', 'Thinnest'), value: s.mn.toFixed(1), tone: s.mn >= minL ? 'teal' : 'amber' }, { id: 'mx', label: T('thickest', 'Thickest'), value: s.mx.toFixed(1), tone: s.mx > maxL ? 'red' : '' }, { id: 'gd', label: T('even', 'Even'), value: Math.round(s.good * 100), unit: '%', meter: { value: s.good } }]; }
      return [{ id: 'ml', label: T('mould', 'Mould'), value: Math.round(st.mould * 100), unit: '%', meter: { value: st.mould, zone: [0.62, 0.86] } }, { id: 'set', label: T('setting', 'Setting'), value: Math.round(clamp(st.setting, 0, 1) * 100), unit: '%', meter: { value: clamp(st.setting, 0, 1) } }];
    };
    S.pp = NZA.ui.ProcPanel(root, { step: 1, total: 3, tag: T('tag_cast', 'Apply cast'), title: '', text: '', tools: [], stats: [], abort: abortBtn(), onAbort: () => post('abort') });
    setStep(1);
    let last = performance.now(), statT = 0;
    frame((now) => {
      const dt = Math.min(0.05, (now - last) / 1000); last = now;
      if (st.step === 3 && !st.done) {
        if (st.mouldHeld && st.setting === 0) {
          const onBreak = st.cursor && Math.abs(st.cursor.x - fracX) < 110 && Math.abs(st.cursor.y - cy) < 200;
          if (onBreak) st.mould = Math.min(1.1, st.mould + dt * 0.32);
        }
        if (st.setting > 0 && st.setting < 1) {
          st.setting += dt / 5;
          if (st.still > 140) { st.still = 0; st.cracks++; sound('fail'); S.pp.flash('bad', T('crack', 'You moved while it was setting: the plaster cracked.'), 2200); }
          st.still = Math.max(0, st.still - dt * 40);
          if (st.setting >= 1) { st.setting = 1; S.pp.flash('ok', T('set_ok', 'The cast has set. Press {Enter}.'), 2600); sound('success'); }
        }
      }
      paint(now); if ((statT += dt) > 0.12) { statT = 0; cells(); S.pp.set({ stats: statsC(), tools: toolsC() }); }
    });
    function next() {
      if (st.done) return;
      if (st.step === 1) { if (padCov() < 0.95) { S.pp.flash('warn', T('pad_more', 'Cover the whole limb with padding first.'), 2000); return; } setStep(2); return; }
      if (st.step === 2) { const s = layerStats(); if (s.mn < 1) { S.pp.flash('warn', T('wrap_more', 'Some parts have no plaster yet.'), 2000); return; } setStep(3); return; }
      if (st.setting < 1) { S.pp.flash('warn', T('not_set', 'Mould the cast and let it set first.'), 2000); return; }
      st.done = true;
      const s = layerStats();
      const mouldOk = st.mould >= 0.62 && st.mould <= 0.86 ? 1 : st.mould < 0.62 ? st.mould / 0.62 : clamp(1 - (st.mould - 0.86) * 3, 0, 1);
      let score = 10 * padCov() + 45 * s.good + 20 * mouldOk + 25 * clamp(1 - Math.max(0, s.mx - maxL) * 0.15 - Math.max(0, minL - s.mn) * 0.2, 0, 1) - st.cracks * 10;
      score = Math.round(clamp(score, 0, 100));
      post('finish', { score, coverage: Math.round(s.good * 100), layersMin: Math.round(s.mn * 10) / 10, layersMax: Math.round(s.mx * 10) / 10, cracks: st.cracks, mould: Math.round(st.mould * 100) });
      S.pp.set({ title: T('saving', 'Saving...'), text: '', tools: [] });
      if (!NZA.inGame) later(() => S.m.result({ score, grade: score >= 85 ? 'A' : score >= 72 ? 'B' : 'C', msg: `${castName} applied${leg ? ' · Recommend crutches' : ''}` }), 400);
    }
    S.m = {
      key(e) {
        if (e.key === 'Enter') { if (S.pp && S.pp.key(e)) return true; next(); return true; }
        if (isKey(e, 'mould', 'Space')) { if (st.step === 3 && st.setting === 0) { st.mouldHeld = true; } return true; }
        return false;
      },
      keyUp(e) {
        if (isKey(e, 'mould', 'Space') && st.step === 3 && st.mouldHeld) {
          st.mouldHeld = false;
          if (st.setting === 0 && st.mould > 0.1) { st.setting = 0.001; st.still = 0; S.pp.flash(st.mould >= 0.62 && st.mould <= 0.86 ? 'ok' : 'warn', st.mould >= 0.62 && st.mould <= 0.86 ? T('mould_ok', 'Nicely moulded. Keep still while it sets.') : T('mould_off', 'Moulding is off. Keep still while it sets.'), 2400); }
          return true;
        }
        return false;
      },
      result(r) { resultCard(r, [[T('coverage', 'Coverage'), `${Math.round(layerStats().good * 100)}%`, layerStats().good > 0.8 ? 'ok' : 'warn'], [T('cracks', 'Cracks'), st.cracks, st.cracks ? 'bad' : 'ok'], [T('mould', 'Mould'), `${Math.round(st.mould * 100)}%`, st.mould >= 0.62 && st.mould <= 0.86 ? 'ok' : 'warn']]); },
      _st: st, _setStep: setStep,
    };
  }

  /* ═══════════════════════════ APP ═══════════════════════════ */
  const MODES = { choose: modeChoose, expose: modeExpose, read: modeRead, view: modeRead, reduce: modeReduce, cast: modeCast };
  const anyKey = (map) => new Proxy({}, { get: () => (e) => (S.m && S.m[map] ? (S.m[map](e) ? undefined : false) : false) });

  NZA.app(APP, {
    escClose: false,
    init(el) { root = el; },
    open(d) {
      teardown();
      L = Object.assign({}, d.locale || {});
      S.d = d; S.mode = d.mode || 'read';
      const wrapEl = NZA.el('div', 'xr-root'); root.appendChild(wrapEl);
      if (S.mode === 'reduce' || S.mode === 'cast') wrapEl.appendChild(NZA.el('div', 'xr-dim'));
      (MODES[S.mode] || modeRead)(d);
    },
    close() { teardown(); },
    msg: {
      filmReady(f) { if (S.m && S.m.filmReady) S.m.filmReady(f || {}); },
      result(r) { if (S.m && S.m.result && S.mode !== 'expose') S.m.result(r || {}); },
      error(e) { if (S.m && S.m.error) S.m.error(e || {}); else NZA.toast({ title: T('title', 'Radiology'), message: (e && e.msg) || '', type: 'error' }); },
    },
    keys: anyKey('key'),
    keysUp: anyKey('keyUp'),
    preview() {
      const p = new URLSearchParams(location.search);
      const mode = p.get('mode') || 'read';
      const view = p.get('view') || 'r_leg';
      const film = DEMO.film(view);
      if (mode === 'sheet') return sheet((p.get('views') || 'r_leg,chest').split(','), Number(p.get('w') || 480));
      if (mode === 'choose') return NZA.demo(APP, { mode, name: 'Michael Garcia', views: DEMO.views() });
      if (mode === 'expose') return NZA.demo(APP, { mode, view, viewLabel: DEMO.label(view), name: 'Michael Garcia', kv: 110, mas: 4, breath: view === 'chest', breathWindow: 5 });
      if (mode === 'reduce') return NZA.demo(APP, { mode, injury: 'i7', region: 'r_lower_leg', regionLabel: 'Right lower leg', bone: 'tibia', boneLabel: 'Tibia', kind: 'closed', angle: 18, short: 11, view: 'r_leg', analgesia: 0.35, tolerance: 3, fluoroBudget: 12, name: 'Michael Garcia' });
      if (mode === 'cast') return NZA.demo(APP, { mode, injury: 'i7', region: 'r_lower_leg', regionLabel: 'Right lower leg', bone: 'tibia', boneLabel: 'Tibia', castType: 'short_leg', leg: true, layersMin: 3, layersMax: 6, name: 'Michael Garcia' });
      NZA.demo(APP, { mode: mode === 'view' ? 'view' : 'read', token: 'demo', film, tolerance: 0.06, minTime: p.get('fast') ? 0 : 8 });
      if (p.get('hang')) later(() => S.m && S.m.hang && S.m.hang(p.get('hang')), 300);
    },
  });

  /* preview only: a contact sheet of rendered films (?app=xray&mode=sheet&views=chest,r_leg) */
  function sheet(views, w) {
    const box = NZA.el('div', ''); box.style.cssText = 'position:fixed;inset:0;display:flex;flex-wrap:wrap;align-items:flex-start;align-content:flex-start;gap:6px;padding:6px;background:#111;overflow:auto;z-index:99';
    document.body.appendChild(box);
    fontsReady.then(() => views.forEach(v => ['ap', 'lat'].forEach(which => { const c = renderFilm(DEMO.film(v), which, w); c.style.width = `${w}px`; box.appendChild(c); })));
  }

  /* ═══════════════════════════ PREVIEW DATA ═══════════════════════════ */
  const DEMO = {
    label: (v) => ({ head: 'Head', neck: 'Neck', chest: 'Chest', abdomen: 'Abdomen', l_arm: 'Left arm', r_arm: 'Right arm', l_leg: 'Left leg', r_leg: 'Right leg' })[v] || v,
    views: () => ['head', 'neck', 'chest', 'abdomen', 'l_arm', 'r_arm', 'l_leg', 'r_leg'].map(v => ({ id: v, label: DEMO.label(v), sev: v === 'r_leg' ? 3 : v === 'chest' ? 2 : null })),
    film(view) {
      const base = { id: 'RX-4471', pid: 'p:ABC123', name: 'Michael Garcia', sex: 'm', age: 34, view, viewLabel: DEMO.label(view), seed: 2034, quality: 'sharp', sev: 3, by: 'Dr. N. Ayzee', hospital: 'Pillbox Medical', dateText: '14/10/2026 21:42', kv: 65, mas: 10 };
      const F = {
        r_leg: [
          { id: 'f1', k: 'fx', inj: 'i7', bone: 'tibia', kind: 'closed', disp: true, ang: 18, phi: 0.55, shift: 0.6, short: 9, ap: { x: 0.503, y: 0.683 }, lat: { x: 0.51, y: 0.672 }, r: 0.06, label: 'Closed fracture of the tibia' },
          { id: 'f2', k: 'frag', inj: 'i3', n: 1, depth: 34, shape: 'bullet', rot: 0.6, ap: { x: 0.445, y: 0.25 }, lat: { x: 0.47, y: 0.25 }, r: 0.06, label: '1 fragment, 34 mm deep' },
        ],
        l_leg: [{ id: 'f1', k: 'fx', bone: 'femur', kind: 'comminuted', disp: true, ang: 22, phi: 0.9, shift: 0.7, short: 14, ap: { x: 0.48, y: 0.28 }, lat: { x: 0.511, y: 0.27 }, r: 0.06, label: 'Comminuted fracture of the femur' }],
        r_arm: [{ id: 'f1', k: 'fx', bone: 'radius_ulna', kind: 'closed', disp: true, ang: 16, phi: 0.4, shift: 0.5, short: 6, ap: { x: 0.461, y: 0.62 }, lat: { x: 0.48, y: 0.62 }, r: 0.06, label: 'Closed fracture of the radius and ulna' }],
        l_arm: [{ id: 'f1', k: 'fx', bone: 'humerus', kind: 'closed', disp: false, ang: 0, phi: 0.4, shift: 0.2, short: 0, ap: { x: 0.497, y: 0.25 }, lat: { x: 0.5, y: 0.25 }, r: 0.06, label: 'Closed fracture of the humerus' }],
        chest: [
          { id: 'f1', k: 'fx', bone: 'ribs', kind: 'closed', disp: true, ang: 10, phi: 0.5, shift: 0.4, short: 4, ap: { x: 0.21, y: 0.45 }, lat: { x: 0.5, y: 0.48 }, r: 0.06, label: 'Closed fracture of the ribs' },
          { id: 'f2', k: 'hemo', side: 'right', ml: 900, top: 0.48, ap: { x: 0.27, y: 0.62 }, lat: { x: 0.62, y: 0.65 }, r: 0.18, label: 'Haemothorax, right' },
          { id: 'f3', k: 'frag', n: 3, depth: 60, shape: 'shard', rot: 1.2, ap: { x: 0.66, y: 0.36 }, lat: { x: 0.31, y: 0.37 }, r: 0.06, label: '3 fragments, 60 mm deep' },
        ],
        abdomen: [
          { id: 'f1', k: 'fx', bone: 'pelvis', site: 'ramus', kind: 'closed', disp: true, ang: 8, phi: 0.5, shift: 0.3, short: 2, ap: { x: 0.39, y: 0.84 }, lat: { x: 0.3, y: 0.84 }, r: 0.06, label: 'Closed fracture of the pelvic ring' },
          { id: 'f2', k: 'fx', bone: 'l_spine', level: 2, kind: 'closed', disp: false, ang: 0, ap: { x: 0.5, y: 0.225 }, lat: { x: 0.618, y: 0.225 }, r: 0.06, label: 'Closed fracture of the lumbar spine' },
        ],
        head: [{ id: 'f1', k: 'fx', bone: 'skull', kind: 'closed', disp: true, ang: 6, ap: { x: 0.64, y: 0.12 }, lat: { x: 0.36, y: 0.15 }, r: 0.06, label: 'Closed fracture of the skull' }, { id: 'f2', k: 'frag', n: 1, depth: 70, shape: 'bullet', rot: 2, ap: { x: 0.42, y: 0.3 }, lat: { x: 0.45, y: 0.3 }, r: 0.06, label: '1 fragment, 70 mm deep' }],
        neck: [{ id: 'f1', k: 'fx', bone: 'c_spine', level: 5, kind: 'closed', disp: true, ang: 8, ap: { x: 0.5, y: 0.485 }, lat: { x: 0.45, y: 0.485 }, r: 0.06, label: 'Closed fracture of the cervical spine' }],
      };
      base.findings = F[view] || [];
      return base;
    },
  };
})();
