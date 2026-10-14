/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · app "intubation"                 module: intubation
   Airway care: 8-step video-laryngoscope intubation and a standalone
   bag-valve-mask ventilation round.

   Lua → JS   open(data)            data = { mode = 'intubate'|'bvm', patient, vitals, anat, cfg, locale, monitor }
              vitals(v)             live server vitals (hr, map, sys, dia, rhythm) while open
              abort({ reason })     the procedure was cancelled from Lua (patient gone / moved)
              anchors               (core) screen positions of 'bvm' / 'mouth'
   JS → Lua   intubation:step   { step, phase }       scene sync (props, camera, animation)
              intubation:finish { result }            result.score 0..100 + placement details
              intubation:abort  {}                    medic held ESC
   Preview    index.html?app=intubation  (NZA.apps.intubation.dev.goto(step) drives any step)
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const APP = 'intubation';
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const rnd = (a, b) => a + Math.random() * (b - a);
  const esc = NZA.esc, icon = NZA.icon, el = NZA.el;
  const now = () => performance.now();
  const tfmt = s => NZA.fmt.time(s);
  let LOC = {};
  const T = (k, f) => (LOC[k] !== undefined && LOC[k] !== '' ? LOC[k] : f);
  const Tf = (k, f, ...a) => { let s = T(k, f); a.forEach(v => { s = s.replace(/%[sd]/, String(v)); }); return s.replace(/%%/g, '%'); };
  const snd = () => NZA.cfg.sounds !== false;

  /* ─────────────── airway icons (NAYZEEE stroke style) ─────────────── */
  NZ.addIcons({
    'itb-bvm': '<ellipse cx="8.5" cy="11" rx="5.5" ry="4.2"/><path d="M14 11h2.2"/><path d="M16.2 8h3.3l1.5 3-1.5 3h-3.3z"/><path d="M5.5 8.5 4 6.5" opacity=".6"/>',
    'itb-scope': '<rect x="3.5" y="3" width="8" height="5.5" rx="1"/><rect x="5" y="10" width="5" height="11" rx="1.4"/><path d="M10 11.5c4.2.2 7.7 2.2 10.5 6"/>',
    'itb-suction': '<path d="M3.5 20.5c4.5-1 6.8-4.2 8.6-8.1S16 5.8 19 5"/><circle cx="20" cy="4.8" r="1.6"/><path d="M8 18.5l1.4 1.4" opacity=".6"/>',
    'itb-tube': '<path d="M4 20.5c1.6-6.2 5.2-11.3 11-14.2"/><path d="M15 6.3l3.6-2"/><ellipse cx="13.6" cy="8.1" rx="2.8" ry="1.5" transform="rotate(-32 13.6 8.1)"/><path d="M5.6 15.5l2 .7M6.8 12.6l2 .7" opacity=".6"/>',
    'itb-holder': '<rect x="2.5" y="9" width="19" height="6" rx="3"/><circle cx="12" cy="12" r="2.1"/><path d="M12 3.5v3.5M12 17v3.5"/>',
    'itb-towel': '<path d="M3.5 9.5c0-1.4 1.1-2.5 2.5-2.5h12c1.4 0 2.5 1.1 2.5 2.5v5c0 1.4-1.1 2.5-2.5 2.5H6c-1.4 0-2.5-1.1-2.5-2.5z"/><path d="M3.5 12h17" opacity=".55"/>',
    'itb-capno': '<path d="M2.5 17h3l1.2-8h5.8l1.2 8h1.8l1.2-8h4.6"/><path d="M2.5 20.5h19" opacity=".5"/>',
  });

  /* ═══════════════════════════ GEOMETRY ═══════════════════════════
     Scene space of the laryngoscope camera: y up, the screen height spans
     -1..1. Everything the shader draws and every hit test share this. */
  const LENS = 0.075, STEER = 0.45, S_MAX = 1.18, PLANE = 0.56, CM_FULL = 27;

  function geo(st, A) {
    const D = st.depth;
    const ap = sstep(0.30, 1.0, D);
    const deep = Math.max(0, D - 1.0);
    const burp = st.burp ? 1 : 0;
    const s = lerp(0.34, S_MAX, ap) * (1 + deep * 1.9) * (1 + st.expo * 0.10 + burp * 0.05);
    const cy = lerp(0.30, -0.05, ap) + deep * 1.25 + st.expo * 0.07 + burp * 0.05 + A.gy;
    const cx = A.gx * s;
    const rest = -0.12 - 0.28 * A.dif - A.tongue * 0.05;
    const rimY = lerp(rest, 0.42, clamp(st.expo, 0, 1));
    return { cx, cy, s, rimY, valY: rimY + 0.46, apex: 0.32 + A.ant * 0.04 };
  }

  // element-relative (0..1, y down) → scene
  function toScene(x, y, W, H, steer) {
    const px = (x - 0.5) * W / (H / 2), py = (0.5 - y) * 2;
    const f = 1 + LENS * (px * px + py * py);
    return [px * f + steer * STEER, py * f];
  }
  // scene → element css px
  function toPx(sx, sy, W, H, steer) {
    const x = sx - steer * STEER, y = sy;
    let px = x, py = y;
    for (let i = 0; i < 6; i++) { const f = 1 + LENS * (px * px + py * py); px = x / f; py = y / f; }
    return [px * (H / 2) + W / 2, H / 2 - py * (H / 2)];
  }
  // iq's exact triangle distance
  function sdTri(px, py, ax, ay, bx, by, cx, cy) {
    const e0x = bx - ax, e0y = by - ay, e1x = cx - bx, e1y = cy - by, e2x = ax - cx, e2y = ay - cy;
    const v0x = px - ax, v0y = py - ay, v1x = px - bx, v1y = py - by, v2x = px - cx, v2y = py - cy;
    const c0 = clamp((v0x * e0x + v0y * e0y) / (e0x * e0x + e0y * e0y), 0, 1);
    const c1 = clamp((v1x * e1x + v1y * e1y) / (e1x * e1x + e1y * e1y), 0, 1);
    const c2 = clamp((v2x * e2x + v2y * e2y) / (e2x * e2x + e2y * e2y), 0, 1);
    const q0x = v0x - e0x * c0, q0y = v0y - e0y * c0, q1x = v1x - e1x * c1, q1y = v1y - e1y * c1, q2x = v2x - e2x * c2, q2y = v2y - e2y * c2;
    const s = Math.sign(e0x * e2y - e0y * e2x);
    const d0 = [q0x * q0x + q0y * q0y, s * (v0x * e0y - v0y * e0x)];
    const d1 = [q1x * q1x + q1y * q1y, s * (v1x * e1y - v1y * e1x)];
    const d2 = [q2x * q2x + q2y * q2y, s * (v2x * e2y - v2y * e2x)];
    const dx = Math.min(d0[0], d1[0], d2[0]), dy = Math.min(d0[1], d1[1], d2[1]);
    return -Math.sqrt(dx) * Math.sign(dy);
  }
  function glotD(qx, qy, A, g) { return sdTri(qx, qy, 0, g.apex, -0.125 * A.open, -0.28, 0.125 * A.open, -0.28) - 0.012; }

  // what is under a scene point at the level of the larynx
  function classify(sx, sy, A, g) {
    const qx = (sx - g.cx) / g.s, qy = (sy - g.cy) / g.s;
    const ex = qx / 0.30, rimC = g.rimY + 0.15 * ex * ex;
    if (Math.abs(qx) < 0.30 && qy > rimC && qy < g.valY) return 'epiglottis';
    const dT = glotD(qx, qy, A, g);
    if (dT < -0.018) return 'trachea';
    if (qy < -0.42 && Math.abs(qx) < 0.24) return 'oesophagus';
    if (dT < 0.085 && qy > -0.27) return 'cords';
    if (qy < -0.26 && qy > -0.46 && Math.abs(qx) < 0.26) return 'arytenoid';
    return 'tissue';
  }

  // Cormack–Lehane grade of the current view
  const CL_RANK = { 1: 0, '2a': 1, '2b': 2, 3: 3, 4: 4 };
  function clGrade(st, g) {
    if (st.depth < 0.70) return '4';
    if (st.depth > 1.22) return '4';
    if (g.rimY < -0.40) return '3';
    const frac = clamp((g.rimY + 0.28) / 0.60, 0, 1);
    if (frac > 0.86) return '1';
    if (frac > 0.42) return '2a';
    return '2b';
  }

  /* ═══════════════════════════ WEBGL AIRWAY ═══════════════════════════ */
  const VERT = 'attribute vec2 aPos; varying vec2 vUv; void main(){ vUv = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }';
  const FRAG = `
precision highp float;
varying vec2 vUv;
uniform vec2 uRes;
uniform float uTime;
uniform float uDepth;
uniform float uSteer;
uniform vec4 uGroup;
uniform vec4 uGlot;
uniform vec4 uMisc;
uniform vec3 uFluid;
uniform sampler2D uSoil;

float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
  float a = hash(i); float b = hash(i + vec2(1.0, 0.0)); float c = hash(i + vec2(0.0, 1.0)); float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); }
float fbm(vec2 p){ float s = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { s += a * noise(p); p = p * 2.03 + 1.7; a *= 0.5; } return s; }
float fbm2(vec2 p){ return 0.66 * noise(p) + 0.34 * noise(p * 2.1 + 3.1); }
float sdEl(vec2 p, vec2 r){ float k0 = length(p / r); float k1 = length(p / (r * r)); return k0 * (k0 - 1.0) / max(k1, 0.0001); }
float sdTri(vec2 p, vec2 p0, vec2 p1, vec2 p2){
  vec2 e0 = p1 - p0; vec2 e1 = p2 - p1; vec2 e2 = p0 - p2;
  vec2 v0 = p - p0; vec2 v1 = p - p1; vec2 v2 = p - p2;
  vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
  vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
  vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
  float s = sign(e0.x * e2.y - e0.y * e2.x);
  vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)), vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
  return -sqrt(d.x) * sign(d.y);
}
float smin(float a, float b, float k){ float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

/* layered surface: colour (sC), height (sH, drives the normals), gloss (sG), ambient occlusion (sA) */
vec3 sC; float sH; float sG; float sA; float sF; float gWq; float gWh;
float cov(float d, float w){ return 1.0 - smoothstep(-w, w, d); }
void lay(float a, float b, vec3 c, float h, float g){ sC = mix(sC, c, a); sH = mix(sH, h, b); sG = mix(sG, g, a); sA = mix(sA, 1.0, a * 0.35); }
// shape by distance: sharp colour edge, soft height edge (smooth normals, no 2x2 blocks)
void layd(float d, float m, vec3 c, float h, float g){ lay(cov(d, gWq) * m, cov(d, gWh) * m, c, h, g); }
void lays(float d, float m, float w, vec3 c, float h, float g){ lay(cov(d, w) * m, cov(d, w * 1.6) * m, c, h, g); }
float dome(float d, float r){ float t = clamp(-d / r, 0.0, 1.0); return t * (2.0 - t); }
vec3 vessels(vec3 c, vec2 p, float k){ float v = smoothstep(0.035, 0.0, abs(fbm(p) - 0.5)); return mix(c, c * vec3(0.62, 0.30, 0.42), v * k); }

void scene(vec2 frag){
  vec2 vuv = frag / uRes;
  float asp = uRes.x / uRes.y;
  vec2 p = (frag - 0.5 * uRes) / (0.5 * uRes.y);
  float r2 = dot(p, p);
  vec2 sp = p * (1.0 + 0.075 * r2);
  sp.x += uSteer * 0.45;
  float aa = 2.4 / uRes.y;
  float D = uDepth;
  vec2 G = uGroup.xy; float S = uGroup.z; float rimY = uGroup.w;
  vec2 q = (sp - G) / S;
  float wq = aa / S;
  float wh = max(wq * 4.0, 0.022);
  gWq = wq; gWh = wh;
  float near = smoothstep(0.25, 1.05, D);
  float lar = clamp((D - 0.26) * 4.0, 0.0, 1.0);

  /* ── pharyngeal wall: a wet tube converging on the larynx ── */
  vec2 wv = sp - G;
  float ang = atan(wv.y, wv.x);
  float rad = length(wv * vec2(0.85, 1.0));
  float folds = sin(ang * 13.0 + fbm(sp * 3.0) * 4.0) * 0.5 + 0.5;
  vec3 wall = mix(vec3(0.52, 0.11, 0.12), vec3(0.80, 0.27, 0.25), fbm(sp * 4.5 + 2.0));
  wall = mix(wall, wall * vec3(1.08, 0.86, 0.9), smoothstep(0.45, 0.75, fbm(sp * 9.0 + 5.0)));
  wall = vessels(wall, sp * 2.6 + 9.0, 0.42);
  wall = vessels(wall, sp * 5.2 + 3.0, 0.22);
  float tun = smoothstep(0.0, 1.4, rad);
  sC = wall * mix(0.30, 1.0, tun) * mix(0.55, 1.0, near);
  sH = 0.10 + 0.05 * folds * tun + 0.06 * fbm(sp * vec2(3.0, 6.0));
  sG = 1.0; sA = mix(0.55, 1.0, tun); sF = 0.0;

  /* ── larynx ── */
  float lit = mix(0.35, 1.0, near);
  vec2 qa = vec2(abs(q.x), q.y);
  // posterior hypopharynx / postcricoid mucosa and the closed oesophageal inlet
  float dPc = sdEl(q - vec2(0.0, -0.50), vec2(0.34, 0.20));
  lays(dPc, lar, 0.09, vessels(vec3(0.66, 0.22, 0.22), q * 6.0, 0.3) * lit, 0.18 + 0.12 * dome(dPc, 0.25), 1.0);
  float dOe = sdEl(q - vec2(0.0, -0.57), vec2(0.12, 0.012 + 0.006 * sin(q.x * 40.0)));
  float oeR = 0.5 + 0.5 * sin(atan(q.y + 0.57, q.x) * 9.0);
  lays(dOe - 0.035, lar * 0.55, 0.05, vec3(0.42, 0.10, 0.11) * lit * (0.85 + 0.15 * oeR), 0.12, 0.8);
  lays(dOe, lar, 0.012, vec3(0.12, 0.025, 0.03) * lit, 0.10, 0.25);
  // piriform fossae: dark pockets outside the aryepiglottic folds
  float dP = sdEl(qa - vec2(0.33, -0.12), vec2(0.09, 0.24));
  lay(cov(dP, 0.05) * lar, cov(dP, 0.06) * lar, vec3(0.16, 0.035, 0.04) * lit, -0.10 + 0.08 * (1.0 - dome(dP, 0.08)), 0.5);
  // laryngeal vestibule (inside the inlet)
  float dV = sdEl(q - vec2(0.0, -0.02), vec2(0.255, 0.345));
  lays(dV, lar, 0.03, vec3(0.50, 0.14, 0.15) * lit, 0.05 - 0.12 * dome(dV, 0.25), 1.0);
  // aryepiglottic folds: the raised rim of the inlet
  float dAE = abs(sdEl(q - vec2(0.0, -0.02), vec2(0.265, 0.355))) - 0.030;
  float aeB = step(-0.33, q.y);
  lays(dAE, aeB * lar, 0.022, vessels(vec3(0.84, 0.38, 0.38), q * 7.0, 0.25) * lit, 0.40 + 0.26 * dome(dAE, 0.045), 1.4);
  // glottis
  float op = uGlot.x;
  vec2 A0 = vec2(0.0, uGlot.y); vec2 B0 = vec2(-0.125 * op, -0.28); vec2 C0 = vec2(0.125 * op, -0.28);
  float dT = sdTri(q, A0, B0, C0) - 0.012;
  float post = step(-0.27, q.y);
  // ventricular (false) folds
  float dF = abs(dT - 0.068) - 0.032;
  lays(dF, post * lar, 0.034, vessels(vec3(0.66, 0.22, 0.23), q * 11.0, 0.25) * lit, 0.24 + 0.08 * dome(dF, 0.05), 1.1);
  // ventricle groove
  lays(abs(dT - 0.031) - 0.004, post * lar * 0.8, 0.010, vec3(0.30, 0.07, 0.08) * lit, 0.16, 0.6);
  // true vocal cords: pearly white bands, brighter on the free edge
  float dVc = abs(dT - 0.014) - 0.021;
  float edge = smoothstep(0.016, -0.004, abs(dT + 0.002));
  vec3 cordC = mix(vec3(0.86, 0.80, 0.74), vec3(1.0, 0.97, 0.93), edge);
  cordC = mix(cordC, vec3(0.80, 0.55, 0.52), 0.12 * fbm(q * 40.0));
  lays(dVc, post * lar, 0.009, cordC * lit, 0.30 + 0.07 * dome(dVc, 0.03), 1.3);
  // trachea through the cords: rings on the anterior wall, darkness in the depth
  float deep = smoothstep(0.0, 0.10, -dT);
  vec2 tq = (q - vec2(0.0, -0.05)) * vec2(1.0, 0.70);
  float rings = 0.5 + 0.5 * sin(length(tq) * 95.0);
  float ant = smoothstep(-0.05, 0.25, q.y);
  vec3 trach = mix(vec3(0.42, 0.13, 0.13), vec3(0.02, 0.004, 0.004), deep) * (0.70 + 0.30 * rings * ant * (1.0 - 0.7 * deep));
  layd(dT, lar, trach * lit, 0.0 - 0.25 * deep, 0.6);
  // arytenoid complex: corniculate + cuneiform tubercles, interarytenoid notch
  float ar = uGlot.z;
  float dAr = smin(sdEl(qa - vec2(0.100, -0.345), vec2(0.075, 0.062) * ar), sdEl(qa - vec2(0.190, -0.282), vec2(0.044, 0.052) * ar), 0.035);
  vec3 arC = vessels(vec3(0.88, 0.50, 0.48), q * 9.0, 0.25) * (0.92 + 0.12 * fbm(q * 18.0));
  layd(dAr, lar, arC * lit, 0.48 + 0.34 * dome(dAr, 0.06), 1.5);
  layd(sdEl(q - vec2(0.0, -0.352), vec2(0.014, 0.045)), lar, vec3(0.28, 0.06, 0.07) * lit, 0.25, 0.5);

  /* ── epiglottis (leaf with a curled rim), its shadow, the vallecula and tongue base ── */
  float epiOn = smoothstep(0.40, 0.62, D);
  float ex = q.x / 0.30;
  float rimC = rimY + 0.15 * ex * ex;
  float valY = rimY + 0.46;
  float yy = clamp((q.y - rimY) / 0.46, 0.0, 1.0);
  float dEw = abs(q.x) - (0.30 - 0.07 * yy);
  float dEb = max(max(rimC - q.y, dEw), q.y - valY);
  // shadow of the rim on what lies below it
  float shW = smoothstep(0.34, 0.24, abs(q.x));
  float sh = smoothstep(0.0, 0.10, rimC - q.y) * 0.55 + 0.45;
  sC *= mix(1.0, sh, shW * epiOn * step(q.y, rimC));
  float rimB = clamp(1.0 - (q.y - rimC) / 0.07, 0.0, 1.0);
  vec3 epiC = mix(vec3(0.86, 0.44, 0.44), vec3(0.98, 0.70, 0.66), rimB * 0.8);
  epiC = vessels(epiC, q * vec2(6.0, 9.0) + 4.0, 0.45) * (0.92 + 0.12 * fbm(q * 13.0));
  epiC *= 1.0 - 0.18 * smoothstep(0.03, 0.0, abs(q.x)) * (1.0 - rimB);
  epiC *= mix(1.0, 0.84, smoothstep(0.25, 0.9, yy));
  layd(dEb, epiOn, epiC * lit, 0.58 + 0.28 * sin(rimB * 1.5708) + 0.12 * dome(dEw, 0.12), 1.6);
  float dVal = abs(q.y - valY - 0.018) - 0.024;
  float vmm = step(abs(q.x), 0.42) * epiOn;
  layd(dVal, vmm, vec3(0.24, 0.06, 0.07) * lit, 0.12, 0.4);
  layd(abs(q.x) - 0.012, cov(dVal, wq) * vmm, vec3(0.68, 0.32, 0.32) * lit, 0.30, 0.9);
  float tb = q.y - (valY + 0.045 + 0.022 * sin(q.x * 11.0));
  vec2 cell = q * 13.0 + vec2(0.0, fbm(q * 3.0) * 1.5); vec2 ci = floor(cell); vec2 cf = fract(cell) - 0.5;
  float bsz = 0.22 + 0.26 * hash(ci + 3.7);
  float bump = step(0.35, hash(ci + 1.3)) * smoothstep(bsz, bsz * 0.2, length(cf + 0.55 * (vec2(hash(ci), hash(ci + 7.0)) - 0.5)));
  bump = max(bump * 0.8, 0.5 * smoothstep(0.62, 0.8, fbm(q * 26.0)));
  vec3 tbC = vessels(vec3(0.80, 0.38, 0.38), q * 5.0, 0.3) * (0.84 + 0.22 * bump);
  layd(-tb, epiOn, tbC * lit, 0.50 + 0.30 * clamp(tb * 3.0, 0.0, 1.0) + 0.035 * bump, 1.1);

  /* ── soft palate + uvula (posterior, bottom of the picture early in the insertion) ── */
  float pa = smoothstep(0.03, 0.62, D);
  float base = mix(-0.30, -1.55, pa);
  float dPal = sp.y - (base + 0.30 * sp.x * sp.x);
  vec3 palC = vessels(vec3(0.84, 0.36, 0.40), sp * 4.0, 0.35) * (0.84 + 0.2 * fbm(sp * 6.0));
  lay(cov(dPal, aa), cov(dPal, 0.03), palC, 0.62 + 0.3 * clamp(-dPal * 2.0, 0.0, 1.0), 1.1);
  vec2 u0 = sp - vec2(0.0, base);
  float dU = smin(sdEl(u0 - vec2(0.0, 0.30), vec2(0.075, 0.07)), sdEl(u0 - vec2(0.0, 0.13), vec2(0.05, 0.16)), 0.05);
  lay(cov(dU, aa), cov(dU, 0.03), vec3(0.90, 0.42, 0.46), 0.74 + 0.30 * dome(dU, 0.06), 1.5);

  /* ── tongue (anterior, top of the picture), the flange pushes it aside when steering ── */
  float ta = smoothstep(0.0, 0.66, D);
  float tE = mix(-0.02, 1.38, ta) + 0.30 * sp.x * sp.x - uGlot.w * 0.10;
  float dTo = tE - sp.y;
  float pap = fbm(sp * 30.0);
  vec3 tC = mix(vec3(0.80, 0.34, 0.36), vec3(0.92, 0.62, 0.60), smoothstep(0.55, 0.78, pap) * 0.45);
  lay(cov(dTo, aa), cov(dTo, 0.04), tC, 0.78 + 0.22 * clamp(-dTo * 1.6, 0.0, 1.0) + 0.04 * pap, 1.0);
  float sd = max(abs(uSteer) - 0.2, 0.0);
  float dS = (asp + 0.05 - sd * 2.4 - 0.18 * p.y * p.y) - p.x * sign(uSteer + 0.0001);
  lay(cov(dS, aa) * step(0.001, sd), cov(dS, 0.04) * step(0.001, sd), tC * 0.95, 0.8 + 0.2 * clamp(-dS * 3.0, 0.0, 1.0), 1.0);

  /* ── blood / vomit / water pooling at the bottom (posterior) ── */
  float f = texture2D(uSoil, vec2(vuv.x, 1.0 - vuv.y)).a * uMisc.w;
  float fc = smoothstep(0.22, 0.50, f);
  float fd = fbm(p * 7.0 + vec2(0.0, uTime * 0.05));
  vec2 bg = p * 15.0 + vec2(0.0, uTime * 0.12);
  vec2 bi = floor(bg); vec2 bfr = fract(bg) - 0.5;
  float brad = 0.12 + 0.20 * hash(bi);
  float froth = step(0.5, uFluid.g) * step(0.86, hash(bi + 3.1)) * dome(length(bfr) - brad * 0.5, 0.05) * smoothstep(0.55, 0.85, f);
  float thick = smoothstep(0.25, 0.85, f);
  vec3 flC = uFluid * mix(1.55, 0.78, thick) * (0.88 + 0.16 * fd);
  sC = mix(sC, flC, fc); sH = mix(sH, 0.46 + 0.20 * thick + 0.05 * froth, smoothstep(0.08, 0.50, f)); sG = mix(sG, 2.6, fc); sF = max(sF, fc * (1.0 - froth));

  /* ── blade tip (dark metal) entering from the top ── */
  float bl = smoothstep(0.10, 0.55, D);
  float bY = mix(1.35, 0.80, bl);
  float dBl = sdEl(p - vec2(0.0, bY + 0.42), vec2(0.66, 0.42));
  vec3 metal = vec3(0.05, 0.055, 0.06) + vec3(0.22, 0.24, 0.26) * smoothstep(0.02, 0.0, abs(dBl + 0.015)) + 0.03 * fbm(p * 5.0);
  lay(cov(dBl, aa) * step(0.01, bl), cov(dBl, 0.02) * step(0.01, bl), metal, 0.98 + 0.05 * dome(dBl, 0.1), 0.25);
  sH += 0.012 * fbm(sp * 40.0) * (1.0 - sF);
}

void main(){
  vec2 frag = vUv * uRes;
  float e = max(1.0, uRes.y / 520.0);
  scene(frag + vec2(e, 0.0)); float hx = sH;
  scene(frag + vec2(0.0, e)); float hy = sH;
  scene(frag);
  vec2 p = (frag - 0.5 * uRes) / (0.5 * uRes.y);
  float r2 = dot(p, p);
  /* ── lighting: coaxial LED next to the lens, wet mucosa ── */
  vec2 gr = clamp(vec2(hx - sH, hy - sH) / e * uRes.y * 0.034, vec2(-3.2), vec2(3.2));
  vec3 n = normalize(vec3(-gr.x, -gr.y, 1.0));
  vec3 L = normalize(vec3(0.0, 0.42, 1.0));
  vec3 V = vec3(0.0, 0.0, 1.0);
  vec3 Hv = normalize(L + V);
  float ndl = max(dot(n, L), 0.0);
  float diff = 0.22 + 0.86 * ndl;
  float nh = max(dot(n, Hv), 0.0);
  float lum = max(sC.r, max(sC.g, sC.b));
  float fres = pow(1.0 - max(dot(n, V), 0.0), 3.0);
  float spec = mix(0.10 * pow(nh, 18.0) + 0.85 * pow(nh, 90.0) + 1.6 * pow(nh, 600.0), 2.4 * pow(nh, 900.0) + 0.25 * pow(nh, 160.0), sF) * sG * mix(smoothstep(0.03, 0.25, lum), 1.0, sF);
  float cone = exp(-r2 * 0.55);
  vec3 sss = sC * vec3(1.0, 0.35, 0.30) * 0.22 * (1.0 - ndl);
  vec3 col = (sC * diff + sss) * sA * (0.50 + 0.66 * cone) + vec3(1.0, 0.95, 0.90) * spec * (0.30 + 0.70 * cone) + sC * fres * 0.18 * sG;
  float vig = smoothstep(1.66, 0.55, length(p * vec2(0.68, 1.0)));
  col *= vig;
  vec3 red = vec3(0.55, 0.10, 0.09) * (0.65 + 0.55 * fbm(p * 2.6 + uTime * 0.15));
  col = mix(col, red * vig, uMisc.x);
  col = mix(col, vec3(0.38, 0.04, 0.04) * (0.6 + 0.6 * fbm(p * 2.2)), uMisc.y * 0.6 * smoothstep(0.35, 0.7, fbm(p * 1.4 + 2.0)));
  col = col / (1.0 + col * 0.22);
  col += (hash(frag + fract(uTime * 7.0) * 113.0) - 0.5) * 0.022;
  col *= uMisc.z;
  gl_FragColor = vec4(pow(max(col, vec3(0.0)), vec3(0.95)), 1.0);
}`;

  function AirwayGL(canvas) {
    let gl = null, prog = null, tex = null, buf = null;
    const U = {};
    try { gl = canvas.getContext('webgl', { antialias: false, premultipliedAlpha: false, alpha: false, preserveDrawingBuffer: false }); } catch (e) { gl = null; }
    if (gl) {
      try {
        const deriv = gl.getExtension('OES_standard_derivatives');
        const head = deriv ? '#extension GL_OES_standard_derivatives : enable\n#define HAS_DERIV 1\n' : '';
        const mk = (type, src) => {
          const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
          if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
          return s;
        };
        prog = gl.createProgram();
        gl.attachShader(prog, mk(gl.VERTEX_SHADER, VERT));
        gl.attachShader(prog, mk(gl.FRAGMENT_SHADER, head + FRAG));
        gl.linkProgram(prog);
        if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
        gl.useProgram(prog);
        buf = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, buf);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
        const loc = gl.getAttribLocation(prog, 'aPos');
        gl.enableVertexAttribArray(loc);
        gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
        ['uRes', 'uTime', 'uDepth', 'uSteer', 'uGroup', 'uGlot', 'uMisc', 'uFluid', 'uSoil'].forEach(n => { U[n] = gl.getUniformLocation(prog, n); });
        tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
        gl.uniform1i(U.uSoil, 0);
      } catch (e) {
        console.warn('[intubation] video laryngoscope falls back to 2D:', e && e.message);
        gl = null;
      }
    }
    return {
      ok: !!gl,
      draw(o) {
        if (!gl) return;
        const fit = NZA.fitCanvas(canvas);
        gl.viewport(0, 0, fit.w, fit.h);
        gl.useProgram(prog);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, tex);
        if (o.soil && o.soilDirty) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, o.soil);
        gl.uniform2f(U.uRes, fit.w, fit.h);
        gl.uniform1f(U.uTime, o.time);
        gl.uniform1f(U.uDepth, o.st.depth);
        gl.uniform1f(U.uSteer, o.st.steer);
        gl.uniform4f(U.uGroup, o.g.cx, o.g.cy, o.g.s, o.g.rimY);
        gl.uniform4f(U.uGlot, o.A.open, o.g.apex, o.A.aryt, o.A.tongue);
        gl.uniform4f(U.uMisc, o.redout, o.smear, o.power, o.fluidOn);
        gl.uniform3f(U.uFluid, o.fluid[0], o.fluid[1], o.fluid[2]);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      },
      destroy() {
        if (!gl) return;
        try { gl.deleteTexture(tex); gl.deleteBuffer(buf); gl.deleteProgram(prog); const lc = gl.getExtension('WEBGL_lose_context'); if (lc) lc.loseContext(); } catch (e) { /* context already gone */ }
        gl = null;
      },
    };
  }

  /* ─────────────── fluid mask (blood / vomit / water on the screen) ─────────────── */
  const FLUID = { blood: [0.50, 0.035, 0.04], vomit: [0.56, 0.42, 0.13], water: [0.78, 0.72, 0.66], none: [0.50, 0.035, 0.04] };
  function Soil(amount, rate) {
    const W = 192, H = 112;
    const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
    const c = cv.getContext('2d', { willReadFrequently: true });
    let dirty = true, cover = 0, coverAt = 0;
    function blob(x, y, r, a) {
      const g = c.createRadialGradient(x, y, 0, x, y, r);
      g.addColorStop(0, `rgba(0,0,0,${a})`); g.addColorStop(0.65, `rgba(0,0,0,${a * 0.8})`); g.addColorStop(1, 'rgba(0,0,0,0)');
      c.fillStyle = g; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill();
    }
    // a drip: overlapping beads that widen as it runs down into the pool
    function streak(x, y, w, len) {
      let cx = x, cy = y;
      const steps = Math.max(3, Math.round(len / 2));
      for (let i = 0; i <= steps; i++) { const t = i / steps; blob(cx, cy, w * (0.4 + 0.6 * t), 0.92); cx += rnd(-0.7, 0.7); cy += 2; }
    }
    function seed(a) {
      c.clearRect(0, 0, W, H);
      if (a <= 0.01) { dirty = true; return; }
      const lvl = H * (1 - a * 0.6), ph = rnd(0, 6);
      // a pool on the posterior wall (bottom of the picture), shallower towards the sides
      c.fillStyle = '#000';
      c.beginPath(); c.moveTo(0, H);
      for (let x = 0; x <= W; x += 4) c.lineTo(x, lvl + Math.sin(x * 0.07 + ph) * 4 + Math.sin(x * 0.23 + ph * 2) * 1.6 + Math.abs(x - W / 2) * 0.12);
      c.lineTo(W, H); c.closePath(); c.fill();
      // drips running down the walls into the pool, a few beads clinging to the mucosa
      const n = Math.round(3 + a * 9);
      for (let i = 0; i < n; i++) streak(rnd(10, W - 10), rnd(lvl - 48, lvl - 8), rnd(2.2, 5), rnd(10, 32));
      const m = Math.round(2 + a * 6);
      for (let i = 0; i < m; i++) blob(rnd(8, W - 8), rnd(lvl - 30, lvl + 6), rnd(2, 4.5), rnd(0.75, 1));
      dirty = true; coverAt = 0;
    }
    seed(amount);
    return {
      canvas: cv,
      suck(x, y, r) {
        c.save(); c.globalCompositeOperation = 'destination-out';
        blob(x * W, y * H, r * H, 0.95); c.restore(); dirty = true;
      },
      refill(dt) {
        if (rate <= 0) return;
        if (Math.random() < dt * 5 * rate) { if (Math.random() < 0.6) streak(rnd(6, W - 6), H - rnd(18, 44), rnd(1.8, 3.6), rnd(10, 26)); else blob(rnd(0, W), H - rnd(0, 10), rnd(6, 12), rnd(0.35, 0.6)); dirty = true; }
      },
      coverage() {
        if (now() - coverAt < 220) return cover;
        coverAt = now();
        const d = c.getImageData(0, 0, W, H).data;
        let n = 0, tot = 0;
        for (let i = 3; i < d.length; i += 16) { tot++; if (d[i] > 110) n++; }
        cover = n / tot;
        return cover;
      },
      at(x, y) {
        const d = c.getImageData(clamp(Math.floor(x * W), 0, W - 1), clamp(Math.floor(y * H), 0, H - 1), 1, 1).data;
        return d[3] / 255;
      },
      take() { const d = dirty; dirty = false; return d; },
      reset(a) { seed(a); },
    };
  }

  /* ═══════════════════════════ MONITOR (top left) ═══════════════════════════
     Generic airway monitor (no brand on the device face): SpO₂ dial + instrument list on the
     left, ECG / PLETH / CO₂ traces (NZA.vitals.Monitor) on the right, apnoea ring + attempt
     pips + lowest SpO₂ along the bottom. */
  function MonitorDev(host) {
    const root = el('div', 'itb-mon dev nza-int nza-in');
    const DA0 = 150, DSW = 240, DR = 44, DC = 60;
    const dpt = (f, r = DR) => { const a = (DA0 + DSW * clamp(f, 0, 1)) * Math.PI / 180; return [DC + r * Math.cos(a), DC + r * Math.sin(a)]; };
    const darc = (f0, f1, r = DR) => { const [x0, y0] = dpt(f0, r), [x1, y1] = dpt(f1, r); return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${(f1 - f0) * DSW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`; };
    const sf = v => clamp((v - 50) / 50, 0, 1);
    let ticks = '';
    for (let i = 0; i <= 10; i++) { const [a, b] = dpt(i / 10, DR + 7), [c, d] = dpt(i / 10, DR + (i % 2 ? 9 : 12)); ticks += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`; }
    const [ax0, ay0] = dpt(sf(90), DR + 8), [ax1, ay1] = dpt(sf(90), DR - 8);
    const RC = 2 * Math.PI * 15;
    root.innerHTML = `
      <div class="itb-dhead"><span class="itb-model"><b>AM-7</b>${esc(T('mon_model', 'Airway monitor'))}</span><span class="itb-dstat"><span class="itb-bat"><i></i><i></i><i></i><i></i></span><span class="dev-led" data-k="led"></span></span></div>
      <div class="dev-screen itb-mon-scr">
        <div class="itb-mhead"><span class="itb-mtag">${esc(`${S && S.patient && S.patient.age ? `${S.patient.age}${T('mon_years', 'Y')} ` : ''}${S && S.patient && S.patient.sex === 'f' ? T('mon_f', 'F') : T('mon_m', 'M')}`)}</span><span class="itb-mrhy" data-k="rhy"></span><span class="itb-mstat" data-k="status"></span><span class="itb-mclock" data-k="clock">--:--</span></div>
        <div class="itb-mgrid">
          <div class="itb-mleft">
            <div class="itb-sat" data-k="sat">
              <svg viewBox="0 0 120 104"><path class="trk" d="${darc(0, 1)}"/><path class="zone" d="${darc(sf(94), 1)}"/><path class="fill" data-k="sfill" d=""/><g class="ticks">${ticks}</g><line class="lim" x1="${ax0.toFixed(1)}" y1="${ay0.toFixed(1)}" x2="${ax1.toFixed(1)}" y2="${ay1.toFixed(1)}"/></svg>
              <div class="sv"><span>SpO₂</span><b data-k="spo2">--</b><i data-k="arr"></i></div>
            </div>
            <div class="itb-ilist">
              <div class="hr"><span>HR</span><b data-k="hr">--</b></div>
              <div class="bp"><span>NIBP</span><b data-k="bp">--/--</b></div>
              <div class="co"><span>EtCO₂</span><b data-k="et">--</b></div>
              <div class="rr"><span>RR</span><b data-k="rr">--</b></div>
            </div>
          </div>
          <div class="itb-vm"></div>
        </div>
        <div class="itb-mfoot">
          <div class="itb-apn" data-k="apn"><span class="rg"><svg viewBox="0 0 36 36"><circle class="t" cx="18" cy="18" r="15"/><circle class="p" data-k="apr" cx="18" cy="18" r="15" transform="rotate(-90 18 18)" stroke-dasharray="0 ${RC.toFixed(1)}"/></svg>${icon('lungs')}</span><span class="tx"><small>${esc(T('mon_apnoea', 'APNOEIC FOR'))}</small><b data-k="apnoea">--:--</b></span></div>
          <div class="itb-atts"><small>${esc(T('mon_attempts', 'ATTEMPTS'))}</small><span class="pips" data-k="pips"></span></div>
          <div class="itb-lowest"><small>${esc(T('mon_lowest', 'LOWEST'))}</small><b data-k="low">--</b></div>
        </div>
      </div>
      <div class="itb-mon-keys">${['power', 'bell', 'heart', 'lungs', 'cog'].map(n => `<span class="dev-btn">${icon(n)}</span>`).join('')}<span class="itb-knob"></span></div>`;
    host.appendChild(root);
    const mon = NZA.vitals.Monitor(root.querySelector('.itb-vm'), { traces: ['ecg', 'pleth', 'co2'], height: 150, compact: true, beep: true, title: '' });
    const q = k => root.querySelector(`[data-k="${k}"]`);
    const RHY = { sinus: 'SINUS', stach: 'S.TACH', sbrady: 'S.BRADY', afib: 'AFIB', vf: 'VF', vt: 'VT', pea: 'PEA', asystole: 'ASYS' };
    let last = {};
    const put = (k, v, cls) => { const e = q(k); if (last[k] !== v) { e.textContent = v; last[k] = v; } if (cls !== undefined && last[`${k}_c`] !== cls) { e.className = cls; last[`${k}_c`] = cls; } };
    return {
      el: root,
      update(v) {
        mon.update({ hr: v.hr, spo2: v.spo2, sys: v.sys, dia: v.dia, map: v.map, rr: v.rr, temp: v.temp, etco2: v.etco2 > 0 ? v.etco2 : 0, rhythm: v.rhythm });
        const arrest = ARREST.has(v.rhythm);
        const sp = Math.round(v.spo2);
        put('spo2', arrest ? '--' : String(sp), sp < 90 ? 'red' : sp < 94 ? 'amber' : '');
        q('sfill').setAttribute('d', darc(0, Math.max(0.004, sf(v.spo2))));
        q('sfill').setAttribute('class', `fill ${sp < 90 ? 'red' : sp < 94 ? 'amber' : ''}`);
        put('arr', Math.abs(v.trend || 0) > 0.04 ? (v.trend > 0 ? '▲' : '▼') : '', v.trend > 0 ? 'up' : 'dn');
        put('hr', v.rhythm === 'asystole' || v.rhythm === 'vf' ? '---' : String(Math.round(v.hr)), (v.hr > 130 || v.hr < 45 || arrest) ? 'al' : '');
        put('bp', arrest ? '--/--' : `${Math.round(v.sys)}/${Math.round(v.dia)}`);
        put('et', v.etco2 > 0 ? String(Math.round(v.etco2)) : '--', v.etco2Alarm ? 'al' : '');
        put('rr', v.rr > 0 ? String(Math.round(v.rr)) : '--');
        put('rhy', RHY[v.rhythm] || String(v.rhythm || '').toUpperCase());
        put('low', `${Math.round(v.low)}%`, v.low < 90 ? 'red' : v.low < 94 ? 'amber' : '');
      },
      status(text, tone) {
        put('status', text, `itb-mstat ${tone || ''}`);
        q('led').className = `dev-led ${tone === 'red' ? 'red' : ''}`;
        root.classList.toggle('alarm', tone === 'red');
      },
      foot({ apnoea, apFrac, apTone, attempt, max, used }) {
        put('apnoea', apnoea, apTone || '');
        q('apr').setAttribute('stroke-dasharray', `${(clamp(apFrac || 0, 0, 1) * RC).toFixed(1)} ${RC.toFixed(1)}`);
        q('apn').className = `itb-apn ${apTone || ''}`;
        const pips = Array.from({ length: max }, (_, i) => `<i class="${i < used ? 'used' : i === attempt - 1 && attempt > used ? 'cur' : ''}">${i + 1}</i>`).join('');
        if (last.pips !== pips) { q('pips').innerHTML = pips; last.pips = pips; }
        const d = new Date();
        put('clock', `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`);
      },
      destroy() { mon.destroy(); root.remove(); },
    };
  }

  /* ═══════════════════════════ BAG (squeeze rhythm) ═══════════════════════════
     Hold 1 s, once every `cadence` seconds. Timing and length are judged. */
  function Bag({ cadence, ideal, onBreath, onDown }) {
    let holding = false, t0 = 0, lastStart = 0, count = 0;
    return {
      get holding() { return holding; },
      get lastStart() { return lastStart; },
      get count() { return count; },
      holdSec() { return holding ? (now() - t0) / 1000 : 0; },
      phase() { return lastStart ? (now() - lastStart) / 1000 / cadence : 1; },
      down() {
        if (holding) return;
        holding = true; t0 = now();
        if (snd()) NZA.audio.noise(1100, { vol: 0.07, lp: 650, hp: 140, attack: 0.25, release: 0.5 });
        onDown && onDown();
      },
      up() {
        if (!holding) return;
        holding = false;
        const hold = (now() - t0) / 1000;
        const first = !lastStart;
        const interval = first ? cadence : (t0 - lastStart) / 1000;
        lastStart = t0; count++;
        const hq = 1 - clamp((Math.abs(hold - ideal) - 0.2) / 0.6, 0, 1);
        const tq = first ? 1 : 1 - clamp((Math.abs(interval - cadence) - 0.5) / 1.5, 0, 1);
        const b = {
          hold, interval, first,
          short: hold < 0.45, long: hold > 1.6,
          early: !first && interval < cadence - 0.5, late: !first && interval > cadence + 0.5,
          vol: Math.round(clamp(hold * 520, 90, 1100)),
          q: hq * (first ? 1 : 0.35 + 0.65 * tq),
        };
        if (snd()) NZA.audio.tone(1900, 22, { vol: 0.03, type: 'square' });
        onBreath && onBreath(b);
      },
      reset() { holding = false; lastStart = 0; count = 0; },
    };
  }

  /* ═══════════════════════════ VENTILATION CARD (cadence ring) ═══════════════════════════ */
  function VentCard(host) {
    const root = el('div', 'itb-vent nza-hud rail nza-int nza-in');
    const R = 100, C = 2 * Math.PI * R;
    root.innerHTML = `
      <div class="itb-ph"><div><div class="nza-label">${esc(T('vent_label', 'Ventilation'))}</div><div class="itb-pt" data-k="title"></div></div><span class="chipx sm teal" data-k="o2">${esc(T('vent_o2', '15 L/min O₂'))}</span></div>
      <div class="itb-ring">
        <svg viewBox="0 0 240 240">
          <defs>
            <radialGradient id="itbBag" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#ffffff" stop-opacity=".30"/><stop offset="1" stop-color="#ffffff" stop-opacity=".05"/></radialGradient>
            <radialGradient id="itbBagOn" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#0fd4c4" stop-opacity=".55"/><stop offset="1" stop-color="#08afa2" stop-opacity=".12"/></radialGradient>
          </defs>
          <circle class="trk" cx="120" cy="120" r="${R}"/>
          <g class="ticks">${Array.from({ length: 20 }, (_, i) => { const a = i / 20 * Math.PI * 2; const r1 = i % 4 === 0 ? 86 : 90; return `<line x1="${120 + Math.sin(a) * r1}" y1="${120 - Math.cos(a) * r1}" x2="${120 + Math.sin(a) * 94}" y2="${120 - Math.cos(a) * 94}"/>`; }).join('')}</g>
          <circle class="win" cx="120" cy="120" r="${R}" transform="rotate(-90 120 120)" stroke-dasharray="${C * 0.2} ${C}" stroke-dashoffset="${C * 0.1}"/>
          <circle class="cad" cx="120" cy="120" r="${R}" transform="rotate(-90 120 120)" stroke-dasharray="0 ${C}"/>
          <circle class="hold" cx="120" cy="120" r="78" transform="rotate(-90 120 120)" stroke-dasharray="0 ${2 * Math.PI * 78}"/>
          <g class="needle"><circle cx="120" cy="${120 - R}" r="8"/></g>
          <g transform="translate(0 -20)"><g class="bvmart">
            <path class="tubing" d="M47 134c-6 8-4 17 5 20s15 9 12 18"/>
            <g class="resv"><path class="rbag" d="M72 110c-6-8-24-9-31 0-6 8-4 21 8 24 9 2 18-1 23-6z"/><path class="rfold" d="M50 107c4 5 5 13 1 20M59 105c3 7 3 16 0 23"/></g>
            <rect class="inlet" x="70" y="113.5" width="10" height="13" rx="2.5"/>
            <g class="bag">
              <path class="sack" d="M80 120c0-15 13-26 36-26s36 11 36 26-13 26-36 26-36-11-36-26z"/>
              <path class="rib" d="M93 99c-5 6-7 13-7 21s2 15 7 21M106 95c-3 7-4 16-4 25s1 18 4 25M126 95c3 7 4 16 4 25s-1 18-4 25M139 99c5 6 7 13 7 21s-2 15-7 21"/>
              <path class="grip" d="M108 109h16M106 115h20M106 121h20M106 127h20M108 133h16"/>
              <path class="shine" d="M95 103c9-5 24-7 39-3"/>
            </g>
            <path class="neck" d="M151 114.5h8v11h-8z"/>
            <path class="valve" d="M159 111h11l3 4v10l-3 4h-11z"/>
            <path class="duck" d="M161 120h7l2-3M168 120l2 3"/>
            <path class="mask" d="M178 103c11 0 19 8 21 17-2 9-10 17-21 17-3 0-5-2-5-5v-24c0-3 2-5 5-5z"/>
            <path class="cushion" d="M197 105c4 4 6 9 6 15s-2 11-6 15"/>
            <path class="flow" d="M88 120H197"/>
          </g></g>
        </svg>
        <div class="itb-ring-c"><b data-k="big"></b><span data-k="small"></span></div>
      </div>
      <div class="itb-mini3">
        <div><span>${esc(T('vent_breaths', 'Breaths'))}</span><b data-k="breaths">0</b></div>
        <div><span>${esc(T('vent_interval', 'Interval'))}</span><b data-k="int">--</b></div>
        <div><span>${esc(T('vent_volume', 'Volume'))}</span><b data-k="vol">--</b></div>
      </div>
      <div class="itb-hist" data-k="hist"></div>
      <div class="itb-gas"><div class="row"><span>${esc(T('vent_gastric', 'Air in the stomach'))}</span><b data-k="gas">0%</b></div><div data-k="gasm"></div></div>`;
    host.appendChild(root);
    const q = k => root.querySelector(`[data-k="${k}"]`);
    const cad = root.querySelector('.cad'), hold = root.querySelector('.hold'), needle = root.querySelector('.needle'), bag = root.querySelector('.bag');
    const resv = root.querySelector('.resv'), art = root.querySelector('.bvmart');
    let kv = 0, lastF = now();
    const gasM = NZA.ui.Meter(q('gasm'), { value: 0, tone: 'amber', zone: [0, 0.35] });
    return {
      el: root,
      title(t, o2) { q('title').textContent = t; if (o2 !== undefined) q('o2').textContent = o2; },
      frame({ phase, holdSec, holding, ideal, started }) {
        const ph = started ? phase : 1;
        const cyc = ph % 1 || (ph >= 1 ? 1 : 0);
        const shown = started ? Math.min(ph, 1.25) : 1;
        cad.setAttribute('stroke-dasharray', `${C * Math.min(shown, 1)} ${C}`);
        cad.classList.toggle('over', started && ph > 1.12);
        needle.setAttribute('transform', `rotate(${(started ? Math.min(ph, 1.25) : 1) * 360} 120 120)`);
        const hp = clamp(holdSec / (ideal * 1.6), 0, 1);
        hold.setAttribute('stroke-dasharray', `${2 * Math.PI * 78 * hp} ${2 * Math.PI * 78}`);
        hold.classList.toggle('good', holdSec >= ideal - 0.2 && holdSec <= ideal + 0.35);
        hold.classList.toggle('bad', holdSec > ideal + 0.6);
        // squeeze: the bag flattens under the hand and springs back; the reservoir fills while the inlet is shut
        const t = now(), fdt = Math.min(0.1, (t - lastF) / 1000); lastF = t;
        const goal = holding ? Math.min(1, holdSec / ideal) : 0;
        kv += (goal - kv) * Math.min(1, fdt * (holding ? 12 : 5));
        bag.setAttribute('transform', `translate(116 120) scale(${(1 + 0.06 * kv).toFixed(3)} ${(1 - 0.34 * kv).toFixed(3)}) translate(-116 -120)`);
        resv.setAttribute('transform', `translate(58 120) scale(${(0.9 + 0.2 * kv).toFixed(3)}) translate(-58 -120)`);
        art.classList.toggle('on', holding);
        root.classList.toggle('inwin', !holding && started && ph >= 0.9 && ph <= 1.12);
        void cyc;
      },
      text(big, small, tone) { const b = q('big'); b.textContent = big; b.className = tone || ''; q('small').textContent = small || ''; },
      stats({ breaths, interval, vol }) { q('breaths').textContent = breaths; q('int').textContent = interval; q('vol').textContent = vol; },
      hist(list) {
        q('hist').innerHTML = Array.from({ length: 10 }, (_, i) => {
          const b = list[list.length - 10 + i];
          if (!b) return '<i class="e"></i>';
          const h = clamp(b.vol / 1000, 0.08, 1);
          const tone = b.q >= 0.75 ? '' : b.q >= 0.4 ? 'amber' : 'red';
          return `<i class="${tone}" style="height:${Math.round(h * 100)}%"></i>`;
        }).join('') + '<span class="tgt"></span>';
      },
      gastric(v) { q('gas').textContent = `${Math.round(v)}%`; gasM.set({ value: v / 100, tone: v > 45 ? 'red' : 'amber' }); },
      destroy() { root.remove(); },
    };
  }

  /* ═══════════════════════════ SAGITTAL VIEW (head & neck cut-away) ═══════════════════════════
     Supine patient, head on the left, face up. Shows head tilt / towel / jaw thrust with the
     oral (OA), pharyngeal (PA) and laryngeal (LA) axes, and the blade / tube inside the airway. */
  const PIV = [262, 262];
  const HEAD = { S1: [272, 190], C: [252, 170], LL: [239, 162], M: [233, 156], UL: [228, 150], SN: [222, 145], NT: [212, 123], NA: [190, 139], BR: [168, 136],
    FH: [124, 150], VX: [80, 210], OC: [88, 284], BH: [152, 322], NP: [240, 318] };
  const TONGUE = [[236, 163], [247, 168], [259, 175], [271, 186], [280, 202], [286, 219], [288, 231], [276, 233], [262, 224], [250, 209], [241, 191], [236, 176]];
  const BLADE_TRACK = [[233, 156], [246, 165], [262, 175], [276, 191], [285, 211], [289, 226], [296, 241], [302, 259]];
  const TUBE_TR = [[252, 106], [236, 152], [262, 181], [283, 212], [301, 238], [316, 251], [360, 248], [420, 243], [480, 238], [540, 234]];
  const TUBE_OE = [[252, 106], [236, 152], [262, 181], [283, 212], [301, 238], [308, 262], [340, 276], [420, 280], [480, 282], [540, 283]];

  function crPath(pts, closed) {
    const n = pts.length;
    if (n < 2) return '';
    const P = i => pts[closed ? (i + n) % n : clamp(i, 0, n - 1)];
    let d = `M${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)}`;
    const last = closed ? n : n - 1;
    for (let i = 0; i < last; i++) {
      const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
      const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
      d += `C${c1[0].toFixed(1)} ${c1[1].toFixed(1)} ${c2[0].toFixed(1)} ${c2[1].toFixed(1)} ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
    }
    return closed ? `${d}Z` : d;
  }
  function polyAt(pts, f) {
    let tot = 0; const seg = [];
    for (let i = 1; i < pts.length; i++) { const l = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); seg.push(l); tot += l; }
    let want = clamp(f, 0, 1) * tot; const out = [pts[0]];
    for (let i = 1; i < pts.length; i++) {
      if (want <= seg[i - 1]) { const t = seg[i - 1] ? want / seg[i - 1] : 0; out.push([lerp(pts[i - 1][0], pts[i][0], t), lerp(pts[i - 1][1], pts[i][1], t)]); return out; }
      want -= seg[i - 1]; out.push(pts[i]);
    }
    return out;
  }
  function axisAngles(pos) {
    const tw = pos.towel ? 1 : 0;
    const oa = 90 - pos.tilt * 3.2 - tw * 14, pa = 70 - tw * 60, la = -4 + tw * 10;
    const align = clamp(1 - (Math.abs(oa - pa) + Math.abs(pa - la)) / 90, 0, 1);
    return { oa, pa, la, align };
  }

  function Sagittal(host, { mini = false, onDrag } = {}) {
    const root = el('div', `itb-sag ${mini ? 'mini' : ''}`);
    root.innerHTML = `
      <svg viewBox="0 0 600 360" preserveAspectRatio="xMidYMid meet">
        <defs>
          <linearGradient id="itbBody${mini ? 'm' : ''}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".09"/><stop offset="1" stop-color="#ffffff" stop-opacity=".02"/></linearGradient>
          <pattern id="itbHatch${mini ? 'm' : ''}" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="rgba(255,255,255,.07)" stroke-width="2"/></pattern>
        </defs>
        <path class="bed" d="M0 331H600"/>
        <rect class="bedf" x="0" y="331" width="600" height="29" fill="url(#itbHatch${mini ? 'm' : ''})"/>
        <path class="towel" d=""/>
        <path class="body" fill="url(#itbBody${mini ? 'm' : ''})" d=""/>
        <path class="head" fill="url(#itbBody${mini ? 'm' : ''})" d=""/>
        <path class="headline" d=""/>
        <path class="collar" d=""/>
        <path class="wall" d=""/>
        <path class="oes" d=""/>
        <path class="trach" d=""/>
        <g class="rings"></g>
        <path class="palate" d=""/>
        <path class="tongue" d=""/>
        <path class="epi" d=""/>
        <path class="cords" d=""/>
        <path class="teeth" d=""/>
        <g class="axes"><path class="ax oa"/><path class="ax pa"/><path class="ax la"/><text class="axl oa"></text><text class="axl pa"></text><text class="axl la"></text></g>
        <g class="tubeg"><path class="tube"/><path class="tubeline"/></g>
        <g class="bladeg"><path class="handle"/><path class="blade"/><circle class="led" r="3"/></g>
        <circle class="teethflash" r="11"/>
        <g class="hnd fore"><circle class="hr" r="15"/><circle class="hd" r="6"/><text class="hl"></text></g>
        <g class="hnd chin"><circle class="hr" r="15"/><circle class="hd" r="6"/><text class="hl"></text></g>
      </svg>`;
    host.appendChild(root);
    const svg = root.querySelector('svg');
    const g = c => root.querySelector(c);
    g('.hnd.fore .hl').textContent = T('pos_tilt', 'Head tilt');
    g('.hnd.chin .hl').textContent = T('pos_jaw', 'Jaw thrust');
    let st = { tilt: 0, jaw: 0, towel: false, cspine: false, handles: !mini, blade: null, tube: null, axes: true };
    let drag = null;

    const rot = (p, deg) => { const a = -deg * Math.PI / 180, dx = p[0] - PIV[0], dy = p[1] - PIV[1]; return [PIV[0] + dx * Math.cos(a) - dy * Math.sin(a), PIV[1] + dx * Math.sin(a) + dy * Math.cos(a)]; };
    function hp(p, jaw) {   // head frame → svg
      const tw = st.towel ? 1 : 0;
      let q = p;
      if (jaw) q = [q[0] + 3 * st.jaw, q[1] - 8 * st.jaw];
      q = rot(q, st.tilt);
      return [q[0], q[1] - 14 * tw];
    }
    function line(cx, cy, deg, len) { const a = deg * Math.PI / 180; return `M${(cx - Math.cos(a) * len).toFixed(1)} ${(cy - Math.sin(a) * len).toFixed(1)}L${(cx + Math.cos(a) * len).toFixed(1)} ${(cy + Math.sin(a) * len).toFixed(1)}`; }

    function render() {
      const tw = st.towel ? 1 : 0;
      const H = {};
      Object.keys(HEAD).forEach(k => { H[k] = hp(HEAD[k], k === 'C' || k === 'LL' || k === 'S1'); });
      const ring = ['S1', 'C', 'LL', 'M', 'UL', 'SN', 'NT', 'NA', 'BR', 'FH', 'VX', 'OC', 'BH', 'NP'].map(k => H[k]);
      g('.head').setAttribute('d', crPath(ring.concat([[H.NP[0] + 26, H.NP[1] - 40], [H.S1[0] + 12, H.S1[1] + 30]]), true));
      g('.headline').setAttribute('d', crPath(ring, false));
      const ny = -10 * tw;
      g('.body').setAttribute('d', `M${H.S1[0]} ${H.S1[1]}C${H.S1[0] + 14} ${H.S1[1] + 6} 300 ${198 + ny} 318 ${196 + ny}Q324 ${189 + ny} 332 ${193 + ny}Q342 ${197 + ny} 352 ${197 + ny}C420 186 520 178 600 176L600 331L310 331C${H.NP[0] + 40} 331 ${H.NP[0] + 14} ${H.NP[1] + 6} ${H.NP[0]} ${H.NP[1]}Z`);
      g('.towel').setAttribute('d', tw ? 'M62 331V318Q62 311 70 311H262Q272 311 272 318V331Z' : '');
      g('.collar').setAttribute('d', st.cspine ? `M${H.S1[0] + 6} ${H.S1[1] + 4}L346 ${200 + ny}M${H.NP[0] + 8} ${H.NP[1] - 2}L330 330` : '');
      // fixed neck internals (lifted a little by the towel)
      const yo = ny;
      g('.wall').setAttribute('d', `M${hp([280, 168])[0]} ${hp([280, 168])[1]}C300 ${190 + yo} 307 ${232 + yo} 304 ${262 + yo}C304 ${277 + yo} 330 ${285 + yo} 362 ${285 + yo}L600 290`);
      g('.oes').setAttribute('d', `M312 ${270 + yo}Q330 ${268 + yo} 360 ${268 + yo}L600 266M316 ${282 + yo}Q336 ${283 + yo} 362 ${283 + yo}L600 286`);
      g('.trach').setAttribute('d', `M318 ${240 + yo}Q340 ${236 + yo} 360 ${235 + yo}L600 224M320 ${262 + yo}Q342 ${259 + yo} 362 ${258 + yo}L600 248`);
      let rg = '';
      for (let x = 350; x < 600; x += 18) { const t = (x - 350) / 250; rg += `<line x1="${x}" y1="${lerp(235, 225, t) + yo}" x2="${x - 2}" y2="${lerp(258, 248, t) + yo}"/>`; }
      g('.rings').innerHTML = rg;
      g('.epi').setAttribute('d', `M302 ${250 + yo}Q293 ${238 + yo} ${288 + st.jaw * 2} ${223 + yo - st.jaw * 4}Q295 ${226 + yo} 306 ${246 + yo}Z`);
      g('.cords').setAttribute('d', `M313 ${243 + yo}L318 ${256 + yo}M309 ${244 + yo}L312 ${258 + yo}`);
      // head internals
      g('.palate').setAttribute('d', crPath([hp([226, 160]), hp([243, 166]), hp([258, 174]), hp([270, 182]), hp([276, 195]), hp([278, 202])], false));
      g('.tongue').setAttribute('d', crPath(TONGUE.map(p => hp(p, true)), true));
      const ut = hp([228, 151]), lt = hp([236, 160], true);
      g('.teeth').setAttribute('d', `M${ut[0]} ${ut[1]}l2 6M${lt[0]} ${lt[1]}l1 6`);
      // axes
      const ax = axisAngles(st);
      const ok = Math.abs(ax.oa - ax.pa) < 10 && Math.abs(ax.pa - ax.la) < 12;
      const mo = hp([238, 176]);
      g('.axes').style.display = st.axes ? '' : 'none';
      g('.ax.oa').setAttribute('d', line(mo[0], mo[1], ax.oa, 120));
      g('.ax.pa').setAttribute('d', line(295, 222 + yo, ax.pa, 120));
      g('.ax.la').setAttribute('d', line(336, 250 + yo, ax.la, 150));
      g('.axes').classList.toggle('ok', ok);
      const lab = (cls, x, y, deg, len, txt) => { const a = deg * Math.PI / 180; const t = g(`.axl.${cls}`); t.setAttribute('x', (x + Math.cos(a) * len).toFixed(1)); t.setAttribute('y', (y + Math.sin(a) * len).toFixed(1)); t.textContent = txt; };
      lab('oa', mo[0], mo[1], ax.oa, -128, 'OA'); lab('pa', 295, 222 + yo, ax.pa, -128, 'PA'); lab('la', 336, 250 + yo, ax.la, 158, 'LA');
      // handles
      g('.hnd.fore').style.display = st.handles && !st.cspine ? '' : 'none';
      g('.hnd.chin').style.display = st.handles ? '' : 'none';
      const fh = H.FH, ch = H.C;
      g('.hnd.fore').setAttribute('transform', `translate(${fh[0].toFixed(1)} ${fh[1].toFixed(1)})`);
      g('.hnd.chin').setAttribute('transform', `translate(${ch[0].toFixed(1)} ${ch[1].toFixed(1)})`);
      g('.hnd.fore .hl').setAttribute('x', -22); g('.hnd.fore .hl').setAttribute('y', -24);
      g('.hnd.chin .hl').setAttribute('x', 20); g('.hnd.chin .hl').setAttribute('y', -20);
      // blade
      const bg = g('.bladeg');
      if (st.blade) {
        const b = st.blade;
        const fr = clamp(b.depth / 1.3, 0, 1);
        const lift = clamp(b.lift || 0, 0, 1), lever = clamp(b.lever || 0, 0, 1);
        const mv = p => [p[0] + lift * 4, p[1] - lift * 9];
        const track = polyAt(BLADE_TRACK, fr * 0.999 + 0.001).map(p => mv(hp(p, false)));
        const m = track[0];
        const la = (-125 - lever * 16) * Math.PI / 180;
        const top = [m[0] + Math.cos(la) * 70, m[1] + Math.sin(la) * 70];
        bg.style.display = '';
        g('.handle').setAttribute('d', `M${m[0].toFixed(1)} ${m[1].toFixed(1)}L${top[0].toFixed(1)} ${top[1].toFixed(1)}`);
        g('.blade').setAttribute('d', crPath(track, false));
        g('.led').setAttribute('cx', top[0].toFixed(1)); g('.led').setAttribute('cy', top[1].toFixed(1));
        const tf = g('.teethflash'); const ut2 = hp([228, 151]);
        tf.setAttribute('cx', ut2[0]); tf.setAttribute('cy', ut2[1]);
        tf.classList.toggle('on', lever > 0.35);
      } else { bg.style.display = 'none'; g('.teethflash').classList.remove('on'); }
      // tube
      const tg = g('.tubeg');
      if (st.tube && st.tube.pr > 0.01) {
        const path = (st.tube.placed === 'oesophagus' ? TUBE_OE : TUBE_TR).map((p, i) => (i < 4 ? hp(p, false) : [p[0], p[1] + yo]));
        const pts = polyAt(path, clamp(st.tube.pr, 0, 1));
        tg.style.display = '';
        g('.tube').setAttribute('d', crPath(pts, false));
        g('.tubeline').setAttribute('d', crPath(pts, false));
        tg.classList.toggle('bad', st.tube.reveal && st.tube.placed === 'oesophagus');
      } else tg.style.display = 'none';
    }

    function svgPt(e) { const r = svg.getBoundingClientRect(); return [(e.clientX - r.left) / r.width * 600, (e.clientY - r.top) / r.height * 360]; }
    function down(kind, e) {
      if (e.button !== 0) return;
      e.preventDefault();
      const p = svgPt(e);
      drag = { kind, p0: p, tilt: st.tilt, jaw: st.jaw, a0: Math.atan2(p[1] - PIV[1], p[0] - PIV[0]) };
      root.classList.add('dragging');
      window.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
    }
    function move(e) {
      if (!drag) return;
      const p = svgPt(e);
      if (drag.kind === 'fore') {
        const a = Math.atan2(p[1] - PIV[1], p[0] - PIV[0]);
        let d = (a - drag.a0) * 180 / Math.PI; if (d > 180) d -= 360; if (d < -180) d += 360;
        onDrag && onDrag({ tilt: clamp(drag.tilt - d, 0, 40) });
      } else {
        const dy = drag.p0[1] - p[1], dx = p[0] - drag.p0[0];
        onDrag && onDrag({ jaw: clamp(drag.jaw + (dy * 0.9 + dx * 0.4) / 30, 0, 1) });
      }
    }
    function up() { drag = null; root.classList.remove('dragging'); window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); }
    g('.hnd.fore').addEventListener('pointerdown', e => down('fore', e));
    g('.hnd.chin').addEventListener('pointerdown', e => down('chin', e));
    render();
    return {
      el: root,
      set(n) { st = Object.assign(st, n); render(); },
      destroy() { up(); root.remove(); },
    };
  }

  /* ═══════════════════════════ VIDEO LARYNGOSCOPE (device + screen) ═══════════════════════════ */
  function Scope(host) {
    const root = el('div', 'itb-scope dev nza-int nza-pop');
    root.innerHTML = `
      <div class="itb-dhead"><span class="itb-model"><b>VL-3</b>${esc(T('vl_model', 'Video laryngoscope'))}</span>
        <span class="itb-dstat"><span class="itb-rec"><i></i>REC <b data-k="rec">00:00</b></span><span class="itb-bat"><i></i><i></i><i></i><i></i></span><span class="dev-led"></span></span></div>
      <div class="dev-screen itb-scr">
        <canvas class="itb-gl"></canvas>
        <canvas class="itb-ov"></canvas>
        <div class="itb-osd tl"><b>MAC 3</b><span data-k="tl"></span></div>
        <div class="itb-osd tr"><span class="itb-cl" data-k="cl">CL —</span></div>
        <div class="itb-gauge" data-k="gauge"><span class="gl" data-k="gl"></span><div class="gt"><i class="gz" data-k="gz"></i><i class="gm" data-k="gm"></i></div><span class="gv" data-k="gv"></span></div>
        <div class="itb-guide" data-k="guide"><svg viewBox="0 0 120 120"><path d="M22 98C40 80 60 52 86 30"/><path d="M66 28l22 0 0 22"/></svg><span></span></div>
        <div class="itb-osd msg" data-k="msg"></div>
      </div>
      <div class="itb-scope-foot"><span class="grip"></span><span data-k="foot"></span></div>`;
    host.appendChild(root);
    const q = k => root.querySelector(`[data-k="${k}"]`);
    const glc = root.querySelector('.itb-gl'), ov = root.querySelector('.itb-ov'), scr = root.querySelector('.itb-scr');
    const gl = AirwayGL(glc);
    const ctx = ov.getContext('2d');
    let lastMsg = '', lastCl = '';

    function size() { return { W: scr.clientWidth || 1, H: scr.clientHeight || 1 }; }
    function rel(e) { const r = scr.getBoundingClientRect(); return [clamp((e.clientX - r.left) / r.width, 0, 1), clamp((e.clientY - r.top) / r.height, 0, 1)]; }
    const gp = (g, qx, qy, W, H, steer) => toPx(g.cx + qx * g.s, g.cy + qy * g.s, W, H, steer);

    function glottisPoly(o, W, H) {
      const { g, A, st } = o;
      return [gp(g, 0, g.apex, W, H, st.steer), gp(g, -0.125 * A.open - 0.02, -0.29, W, H, st.steer), gp(g, 0.125 * A.open + 0.02, -0.29, W, H, st.steer)];
    }

    // flat 2D airway when WebGL is unavailable (keeps the game playable)
    function fallback(o, W, H) {
      const { g, st, A } = o;
      ctx.fillStyle = '#3a1112'; ctx.fillRect(0, 0, W, H);
      const P = (qx, qy) => gp(g, qx, qy, W, H, st.steer);
      const ell = (qx, qy, rx, ry, c) => { const p = P(qx, qy); ctx.fillStyle = c; ctx.beginPath(); ctx.ellipse(p[0], p[1], rx * g.s * H / 2, ry * g.s * H / 2, 0, 0, Math.PI * 2); ctx.fill(); };
      if (st.depth > 0.3) {
        ell(0, -0.08, 0.42, 0.46, '#8a3a3b');
        const t = glottisPoly(o, W, H);
        ctx.fillStyle = '#120404'; ctx.beginPath(); ctx.moveTo(...t[0]); ctx.lineTo(...t[1]); ctx.lineTo(...t[2]); ctx.closePath(); ctx.fill();
        ctx.strokeStyle = '#efe9dc'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(...t[1]); ctx.lineTo(...t[0]); ctx.lineTo(...t[2]); ctx.stroke();
        ell(-0.105, -0.352, 0.078 * A.aryt, 0.064 * A.aryt, '#c97a77'); ell(0.105, -0.352, 0.078 * A.aryt, 0.064 * A.aryt, '#c97a77');
        if (st.depth > 0.45) {
          const a = P(-0.30, g.rimY + 0.15), b = P(0, g.rimY), c = P(0.30, g.rimY + 0.15), d = P(0.24, g.valY), e = P(-0.24, g.valY);
          ctx.fillStyle = '#d9a090'; ctx.beginPath(); ctx.moveTo(...a); ctx.quadraticCurveTo(b[0], b[1] + 6, ...c); ctx.lineTo(...d); ctx.lineTo(...e); ctx.closePath(); ctx.fill();
          const tb = P(0, g.valY + 0.04);
          ctx.fillStyle = '#a24f50'; ctx.fillRect(0, 0, W, Math.max(0, tb[1]));
        }
      }
      if (st.depth < 0.66) { const te = H * (0.5 - (lerp(-0.02, 1.38, sstep(0, 0.66, st.depth))) / 2); ctx.fillStyle = '#c47b78'; ctx.fillRect(0, 0, W, clamp(te, 0, H)); }
    }

    function tubeShape(o, W, H) {
      const t = o.tube;
      const e = sstep(0, PLANE, Math.min(t.pr, PLANE));
      const aim = [t.ax * W, t.ay * H];
      const tip = [lerp(W * 0.88, aim[0], e), lerp(H * 0.97, aim[1], e)];
      const tipW = lerp(H * 0.15, Math.max(10, 0.15 * o.g.s * H / 2), e);
      const P0 = [W * 1.06, H * 1.14], P1 = [lerp(W * 1.0, tip[0], 0.18), tip[1] + H * 0.06], P2 = tip;
      const N = 40, L = [], R = [], C = [];
      for (let i = 0; i <= N; i++) {
        const u = i / N;
        const x = (1 - u) * (1 - u) * P0[0] + 2 * (1 - u) * u * P1[0] + u * u * P2[0];
        const y = (1 - u) * (1 - u) * P0[1] + 2 * (1 - u) * u * P1[1] + u * u * P2[1];
        const dx = 2 * (1 - u) * (P1[0] - P0[0]) + 2 * u * (P2[0] - P1[0]), dy = 2 * (1 - u) * (P1[1] - P0[1]) + 2 * u * (P2[1] - P1[1]);
        const len = Math.hypot(dx, dy) || 1, nx = -dy / len, ny = dx / len;
        const w = lerp(H * 0.24, tipW, Math.pow(u, 0.85)) / 2;
        C.push([x, y, nx, ny, w, dx / len, dy / len]); L.push([x + nx * w, y + ny * w]); R.push([x - nx * w, y - ny * w]);
      }
      return { C, L, R, tip, tipW };
    }
    function path(pts, back) { ctx.beginPath(); pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]))); if (back) { for (let i = back.length - 1; i >= 0; i--) ctx.lineTo(back[i][0], back[i][1]); ctx.closePath(); } }
    function offsetLine(C, k, from, to) { ctx.beginPath(); for (let i = from; i <= to; i++) { const c = C[i]; const x = c[0] + c[2] * c[4] * k, y = c[1] + c[3] * c[4] * k; if (i === from) ctx.moveTo(x, y); else ctx.lineTo(x, y); } }

    function drawTube(o, W, H) {
      const sh = tubeShape(o, W, H), { C, L, R } = sh;
      const N = C.length - 1;
      ctx.save();
      // shadow under the tube
      ctx.globalAlpha = 0.35; ctx.fillStyle = '#000';
      ctx.translate(6, 8); path(L, R); ctx.fill(); ctx.translate(-6, -8);
      ctx.globalAlpha = 1;
      // cuff
      const c0 = Math.round(N * 0.80), c1 = Math.round(N * 0.94);
      const cs = o.tube.inflated ? 1.75 : 1.28;
      const CL = [], CR = [];
      for (let i = c0; i <= c1; i++) { const c = C[i]; const bulge = Math.sin((i - c0) / (c1 - c0) * Math.PI); const w = c[4] * (1 + (cs - 1) * bulge); CL.push([c[0] + c[2] * w, c[1] + c[3] * w]); CR.push([c[0] - c[2] * w, c[1] - c[3] * w]); }
      path(CL, CR); ctx.fillStyle = 'rgba(236,242,245,0.20)'; ctx.fill(); ctx.strokeStyle = 'rgba(255,255,255,0.45)'; ctx.lineWidth = 1.2; ctx.stroke();
      if (!o.tube.inflated) { ctx.strokeStyle = 'rgba(255,255,255,0.22)'; for (let i = c0 + 1; i < c1; i += 2) { const c = C[i]; ctx.beginPath(); ctx.moveTo(c[0] + c[2] * c[4] * 1.2, c[1] + c[3] * c[4] * 1.2); ctx.lineTo(c[0] - c[2] * c[4] * 1.2, c[1] - c[3] * c[4] * 1.2); ctx.stroke(); } }
      // body
      path(L, R);
      const lg = ctx.createLinearGradient(W, H, sh.tip[0], sh.tip[1]);
      lg.addColorStop(0, 'rgba(238,244,246,0.62)'); lg.addColorStop(1, 'rgba(230,238,242,0.45)');
      ctx.fillStyle = lg; ctx.fill();
      ctx.lineWidth = 1.6; ctx.strokeStyle = 'rgba(70,84,92,0.55)';
      path(R); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,0.85)'; path(L); ctx.stroke();
      // highlight + radio-opaque line
      ctx.lineCap = 'round';
      offsetLine(C, -0.45, 2, N - 2); ctx.strokeStyle = 'rgba(255,255,255,0.65)'; ctx.lineWidth = Math.max(1.5, sh.tipW * 0.10); ctx.stroke();
      offsetLine(C, 0.25, 0, N - 1); ctx.strokeStyle = 'rgba(40,120,255,0.85)'; ctx.lineWidth = Math.max(1.4, sh.tipW * 0.07); ctx.stroke();
      // depth marks near the camera
      ctx.strokeStyle = 'rgba(12,14,16,0.75)';
      for (let i = 4; i < Math.round(N * 0.42); i += 3) { const c = C[i]; ctx.lineWidth = i % 9 === 1 ? 3 : 1.6; ctx.beginPath(); ctx.moveTo(c[0] + c[2] * c[4] * 0.1, c[1] + c[3] * c[4] * 0.1); ctx.lineTo(c[0] - c[2] * c[4] * 0.55, c[1] - c[3] * c[4] * 0.55); ctx.stroke(); }
      // bevel + Murphy eye
      const tc = C[N];
      ctx.save(); ctx.translate(tc[0], tc[1]); ctx.rotate(Math.atan2(tc[6], tc[5]) + Math.PI / 2 + 0.35);
      ctx.beginPath(); ctx.ellipse(0, 0, sh.tipW * 0.5, sh.tipW * 0.24, 0, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(25,10,10,0.75)'; ctx.fill(); ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 1.4; ctx.stroke();
      ctx.restore();
      const me = C[N - 2];
      ctx.beginPath(); ctx.ellipse(me[0] - me[2] * me[4] * 0.45, me[1] - me[3] * me[4] * 0.45, sh.tipW * 0.12, sh.tipW * 0.07, Math.atan2(me[6], me[5]), 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(30,12,12,0.7)'; ctx.fill();
      // the part that went through the cords / behind the arytenoids disappears into the dark
      if (o.tube.placed) {
        ctx.save();
        if (o.tube.placed === 'trachea') {
          const t = glottisPoly(o, W, H); ctx.beginPath(); ctx.moveTo(...t[0]); ctx.lineTo(...t[1]); ctx.lineTo(...t[2]); ctx.closePath(); ctx.clip();
        } else {
          const a = gp(o.g, 0, -0.42, W, H, o.st.steer); ctx.beginPath(); ctx.rect(0, a[1], W, H); ctx.clip();
        }
        path(L, R); ctx.fillStyle = 'rgba(8,2,2,0.82)'; ctx.fill();
        ctx.restore();
      }
      ctx.restore();
    }

    function drawSuction(o, W, H) {
      const x = o.suction.x * W, y = o.suction.y * H;
      const P0 = [W * 1.08, H * 0.70], P1 = [W * 0.86, y + H * 0.10];
      ctx.save(); ctx.lineCap = 'round';
      ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.lineWidth = 26;
      ctx.beginPath(); ctx.moveTo(P0[0] + 6, P0[1] + 8); ctx.quadraticCurveTo(P1[0] + 6, P1[1] + 8, x + 6, y + 8); ctx.stroke();
      ctx.strokeStyle = o.suction.on ? 'rgba(232,238,240,0.75)' : 'rgba(232,238,240,0.6)'; ctx.lineWidth = 22;
      ctx.beginPath(); ctx.moveTo(...P0); ctx.quadraticCurveTo(P1[0], P1[1], x, y); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(P0[0] - 6, P0[1] - 8); ctx.quadraticCurveTo(P1[0] - 6, P1[1] - 8, x - 4, y - 6); ctx.stroke();
      if (o.suction.on && o.suction.fluid) { ctx.strokeStyle = o.suction.color; ctx.globalAlpha = 0.55; ctx.lineWidth = 9; ctx.setLineDash([14, 10]); ctx.lineDashOffset = -o.time * 120; ctx.beginPath(); ctx.moveTo(...P0); ctx.quadraticCurveTo(P1[0], P1[1], x, y); ctx.stroke(); ctx.setLineDash([]); ctx.globalAlpha = 1; }
      ctx.fillStyle = 'rgba(236,242,244,0.85)'; ctx.beginPath(); ctx.arc(x, y, 12, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = 'rgba(30,20,20,0.75)'; [[0, 0], [-5, -3], [5, -3], [0, 5]].forEach(d => { ctx.beginPath(); ctx.arc(x + d[0], y + d[1], 1.8, 0, Math.PI * 2); ctx.fill(); });
      ctx.restore();
    }

    function drawMarker(o, W, H) {
      const m = o.marker; if (!m) return;
      const c = gp(o.g, 0, o.g.valY + 0.02, W, H, o.st.steer);
      const rx = 0.20 * o.g.s * H / 2, ry = 0.06 * o.g.s * H / 2;
      ctx.save();
      ctx.strokeStyle = m.ok ? 'rgba(15,212,196,0.95)' : 'rgba(255,255,255,0.75)'; ctx.lineWidth = 2; ctx.setLineDash([7, 6]); ctx.lineDashOffset = -o.time * 18;
      ctx.beginPath(); ctx.ellipse(c[0], c[1], rx, ry, 0, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]);
      ctx.font = '600 12px Lexend, sans-serif'; ctx.textAlign = 'left';
      const label = m.label; const tw = ctx.measureText(label).width + 16;
      const lx = c[0] + rx + 10, ly = c[1] - 12;
      ctx.fillStyle = m.ok ? 'rgba(8,175,162,0.92)' : 'rgba(12,13,16,0.82)';
      ctx.beginPath(); ctx.roundRect ? ctx.roundRect(lx, ly, tw, 24, 6) : ctx.rect(lx, ly, tw, 24); ctx.fill();
      ctx.fillStyle = m.ok ? '#00201d' : '#fff'; ctx.fillText(label, lx + 8, ly + 16);
      ctx.restore();
    }

    return {
      el: root, screen: scr, gl, size, rel,
      render(o) {
        const fit = NZA.fitCanvas(ov);
        const { W, H } = size();
        if (gl.ok) gl.draw(o);
        ctx.setTransform(fit.w / W, 0, 0, fit.h / H, 0, 0);
        ctx.clearRect(0, 0, W, H);
        if (!gl.ok) fallback(o, W, H);
        drawMarker(o, W, H);
        if (o.tube && o.tube.show) drawTube(o, W, H);
        if (o.suction && o.suction.show) drawSuction(o, W, H);
      },
      hud(h) {
        if (h.tl !== undefined) q('tl').textContent = h.tl;
        if (h.rec !== undefined) q('rec').textContent = h.rec;
        if (h.foot !== undefined) q('foot').innerHTML = h.foot;
        if (h.cl !== undefined && h.cl !== lastCl) { lastCl = h.cl; const c = q('cl'); c.textContent = h.cl; c.className = `itb-cl ${h.clTone || ''}`; }
        if (h.msg !== undefined && h.msg + (h.msgTone || '') !== lastMsg) { lastMsg = h.msg + (h.msgTone || ''); const m = q('msg'); m.textContent = h.msg; m.className = `itb-osd msg ${h.msg ? 'on' : ''} ${h.msgTone || ''}`; }
        if (h.gauge !== undefined) {
          const gg = q('gauge');
          gg.style.display = h.gauge ? '' : 'none';
          if (h.gauge) {
            q('gl').textContent = h.gauge.label; q('gv').textContent = h.gauge.text;
            const z = h.gauge.zone || [0, 0];
            q('gz').style.bottom = `${z[0] * 100}%`; q('gz').style.height = `${(z[1] - z[0]) * 100}%`;
            q('gm').style.bottom = `${clamp(h.gauge.value, 0, 1) * 100}%`;
            gg.classList.toggle('ok', !!h.gauge.ok); gg.classList.toggle('bad', !!h.gauge.bad);
          }
        }
        if (h.guide !== undefined) { const gd = q('guide'); gd.style.display = h.guide ? '' : 'none'; if (h.guide) { gd.querySelector('span').textContent = h.guide.label; gd.classList.toggle('on', !!h.guide.on); } }
      },
      destroy() { gl.destroy(); root.remove(); },
    };
  }

  /* ═══════════════════════════ CUFF (syringe + manometer) ═══════════════════════════ */
  function CuffPanel(host, { band, onHold }) {
    const root = el('div', 'itb-cuff nza-hud rail nza-int nza-in');
    const A0 = 135, SW = 270, PMAX = 60, CX = 100, CY = 102, RR = 78;
    const ang = p => (A0 + clamp(p, 0, PMAX) / PMAX * SW) * Math.PI / 180;
    const arc = (p0, p1, r) => { const a0 = ang(p0), a1 = ang(p1); const large = (a1 - a0) > Math.PI ? 1 : 0; return `M${(CX + Math.cos(a0) * r).toFixed(1)} ${(CY + Math.sin(a0) * r).toFixed(1)}A${r} ${r} 0 ${large} 1 ${(CX + Math.cos(a1) * r).toFixed(1)} ${(CY + Math.sin(a1) * r).toFixed(1)}`; };
    let ticks = '';
    for (let p = 0; p <= PMAX; p += 5) { const a = ang(p), r1 = p % 10 === 0 ? 62 : 67; ticks += `<line x1="${(CX + Math.cos(a) * r1).toFixed(1)}" y1="${(CY + Math.sin(a) * r1).toFixed(1)}" x2="${(CX + Math.cos(a) * 72).toFixed(1)}" y2="${(CY + Math.sin(a) * 72).toFixed(1)}"/>`; if (p % 10 === 0) ticks += `<text x="${(CX + Math.cos(a) * 50).toFixed(1)}" y="${(CY + Math.sin(a) * 50 + 4).toFixed(1)}">${p}</text>`; }
    let grads = '';
    for (let v = 0; v <= 10; v++) grads += `<line x1="${100 + v * 20}" y1="52" x2="${100 + v * 20}" y2="${v % 2 === 0 ? 66 : 60}"/>${v % 2 === 0 ? `<text x="${100 + v * 20}" y="80">${v}</text>` : ''}`;
    root.innerHTML = `
      <div class="itb-ph"><div><div class="nza-label">${esc(T('cuff_label', 'Cuff seal'))}</div><div class="itb-pt">${esc(T('cuff_title', '10 ml syringe · pilot balloon'))}</div></div><span class="chipx sm" data-k="seal"></span></div>
      <div class="itb-cuff-body">
        <svg class="syr" viewBox="0 0 460 150">
          <path class="line" d="M78 73H52"/><path class="line" d="M22 73C10 73 8 100 4 140"/>
          <ellipse class="pilot" data-k="pilot" cx="37" cy="73" rx="12" ry="8"/>
          <path class="luer" d="M80 66h20v14H80z"/>
          <rect class="air" data-k="air" x="100" y="50" width="200" height="46" rx="3"/>
          <rect class="barrel" x="100" y="48" width="200" height="50" rx="4"/>
          <g class="grads">${grads}</g>
          <path class="flange" d="M300 34v78"/>
          <g data-k="plunger"><rect class="stop" x="-7" y="50" width="14" height="46" rx="2"/><rect class="rod" x="7" y="66" width="150" height="14" rx="2"/><rect class="thumb" x="152" y="40" width="10" height="66" rx="3"/></g>
          <text class="hint" x="230" y="134" data-k="shint"></text>
        </svg>
        <svg class="gauge" viewBox="0 0 200 200">
          <circle class="face" cx="${CX}" cy="${CY}" r="${RR + 8}"/>
          <path class="band lo" d="${arc(0, band[0], RR)}"/><path class="band ok" d="${arc(band[0], band[1], RR)}"/><path class="band hi" d="${arc(band[1], 40, RR)}"/><path class="band crit" d="${arc(40, PMAX, RR)}"/>
          <g class="tk">${ticks}</g>
          <line class="needle" data-k="needle" x1="${CX}" y1="${CY}" x2="${CX}" y2="${CY - 64}"/>
          <circle class="hub" cx="${CX}" cy="${CY}" r="6"/>
          <text class="unit" x="${CX}" y="${CY + 38}">cmH₂O</text>
          <text class="val" data-k="pv" x="${CX}" y="${CY + 62}">0</text>
        </svg>
      </div>
      <div class="itb-mini3">
        <div><span>${esc(T('cuff_volume', 'Volume'))}</span><b data-k="ml">0.0 ml</b></div>
        <div><span>${esc(T('cuff_pressure', 'Pressure'))}</span><b data-k="p">0</b></div>
        <div><span>${esc(T('cuff_target', 'Target'))}</span><b>${band[0]}–${band[1]}</b></div>
      </div>`;
    host.appendChild(root);
    const q = k => root.querySelector(`[data-k="${k}"]`);
    const syr = root.querySelector('.syr');
    syr.addEventListener('pointerdown', e => { if (e.button === 0) onHold && onHold(1); if (e.button === 2) onHold && onHold(-1); });
    q('shint').textContent = T('cuff_hint', 'Hold to push · right click to let air out');
    return {
      el: root,
      set({ ml, p, leak }) {
        const left = 10 - ml;
        q('plunger').setAttribute('transform', `translate(${(100 + left * 20).toFixed(1)} 0)`);
        q('air').setAttribute('width', (left * 20).toFixed(1));
        q('pilot').setAttribute('rx', (8 + clamp(p, 0, 60) / 60 * 10).toFixed(1));
        q('pilot').setAttribute('ry', (5 + clamp(p, 0, 60) / 60 * 6).toFixed(1));
        q('needle').setAttribute('transform', `rotate(${(A0 + clamp(p, 0, PMAX) / PMAX * SW + 90).toFixed(1)} ${CX} ${CY})`);
        q('pv').textContent = Math.round(p);
        q('ml').textContent = `${ml.toFixed(1)} ml`;
        const inb = p >= band[0] && p <= band[1];
        const pe = q('p'); pe.textContent = `${Math.round(p)} cmH₂O`; pe.className = inb ? 't-teal' : p > band[1] ? 't-red' : '';
        q('pv').setAttribute('class', `val ${inb ? 'ok' : p > band[1] ? 'hi' : ''}`);
        const s = q('seal');
        s.textContent = leak ? T('cuff_leak', 'Leak') : inb ? T('cuff_sealed', 'Sealed') : p > band[1] ? T('cuff_high', 'Too high') : T('cuff_low', 'Under-filled');
        s.className = `chipx sm ${leak ? 'amber' : inb ? 'teal' : p > band[1] ? 'red' : ''}`;
      },
      destroy() { root.remove(); },
    };
  }

  /* ═══════════════════════════ CONFIRM (capnography + auscultation) ═══════════════════════════ */
  function ConfirmPanel(host, { onSpot }) {
    const root = el('div', 'itb-conf nza-int nza-in');
    root.innerHTML = `
      <div class="itb-capno dev">
        <div class="itb-dhead"><span class="itb-model"><b>CX-2</b>${esc(T('capno_title', 'Capnograph'))}</span><span class="dev-led"></span></div>
        <div class="dev-screen itb-capscr">
          <canvas class="itb-capcv"></canvas>
          <div class="itb-capnum"><span>EtCO₂</span><b data-k="et">--</b><small>mmHg</small><span>${esc(T('capno_rr', 'RESP'))}</span><b class="sm" data-k="rr">--</b></div>
          <div class="itb-capmsg" data-k="cmsg"></div>
        </div>
      </div>
      <div class="itb-ausc nza-hud rail">
        <div class="itb-ph"><div><div class="nza-label">${esc(T('ausc_label', 'Auscultation'))}</div><div class="itb-pt">${esc(T('ausc_title', 'Click a spot, then squeeze the bag'))}</div></div>${icon('stetho')}</div>
        <div class="itb-ausc-body">
          <svg viewBox="0 0 300 220">
            <path class="torso" d="M100 18c10 8 30 12 50 12s40-4 50-12c26 6 52 16 64 34 8 30 6 74-4 110-6 22-10 40-12 58H52c-2-18-6-36-12-58-10-36-12-80-4-110 12-18 38-28 64-34z"/>
            <path class="lung" d="M136 46c-22 0-48 14-56 40-8 28-6 62 2 86 18 6 36 2 52-8 4-36 6-78 2-118z"/>
            <path class="lung" d="M164 46c22 0 48 14 56 40 8 28 6 62-2 86-18 6-36 2-52-8-4-36-6-78-2-118z"/>
            <path class="trach" d="M150 6v44M150 50l-14 14M150 50l14 14"/>
            <path class="stom" d="M168 168c20-8 46-4 52 12 4 14-10 26-30 26-18 0-30-8-30-20"/>
            <g class="spot" data-s="r" transform="translate(98 108)"><circle class="pulse" r="22"/><circle class="ring" r="15"/><circle class="dot" r="4"/></g>
            <g class="spot" data-s="l" transform="translate(202 108)"><circle class="pulse" r="22"/><circle class="ring" r="15"/><circle class="dot" r="4"/></g>
            <g class="spot" data-s="epi" transform="translate(186 186)"><circle class="pulse" r="22"/><circle class="ring" r="15"/><circle class="dot" r="4"/></g>
            <text x="98" y="144">${esc(T('ausc_right', 'Right'))}</text><text x="202" y="144">${esc(T('ausc_left', 'Left'))}</text><text x="186" y="216">${esc(T('ausc_epi', 'Stomach'))}</text>
          </svg>
          <div class="itb-ausc-res">
            <div data-r="r"><span>${esc(T('ausc_right', 'Right'))}</span><b>—</b></div>
            <div data-r="l"><span>${esc(T('ausc_left', 'Left'))}</span><b>—</b></div>
            <div data-r="epi"><span>${esc(T('ausc_epi', 'Stomach'))}</span><b>—</b></div>
          </div>
        </div>
      </div>`;
    host.appendChild(root);
    const cv = root.querySelector('.itb-capcv'), ctx = cv.getContext('2d');
    const q = k => root.querySelector(`[data-k="${k}"]`);
    root.querySelectorAll('.spot').forEach(s => s.addEventListener('pointerdown', e => { if (e.button === 0) onSpot && onSpot(s.dataset.s); }));
    const breaths = [];
    const WIN = 14;
    const prof = (dt, h, dur) => {
      if (dt < 0 || dt > dur + 0.3) return 0;
      if (dt < 0.28) return h * sstep(0, 0.28, dt);
      if (dt < dur) return h * (0.9 + 0.1 * (dt - 0.28) / (dur - 0.28));
      return h * (1 - sstep(dur, dur + 0.3, dt));
    };
    function draw() {
      const fit = NZA.fitCanvas(cv);
      const W = cv.clientWidth || 1, H = cv.clientHeight || 1;
      ctx.setTransform(fit.w / W, 0, 0, fit.h / H, 0, 0);
      ctx.clearRect(0, 0, W, H);
      const top = 10, bot = H - 16, yOf = mm => bot - clamp(mm, 0, 60) / 60 * (bot - top);
      ctx.strokeStyle = 'rgba(255,255,255,0.07)'; ctx.lineWidth = 1; ctx.font = '500 9px Lexend, sans-serif'; ctx.fillStyle = 'rgba(255,255,255,0.35)';
      [0, 20, 40, 60].forEach(v => { const y = yOf(v); ctx.beginPath(); ctx.moveTo(26, y); ctx.lineTo(W, y); ctx.stroke(); ctx.fillText(String(v), 4, y + 3); });
      ctx.fillStyle = 'rgba(15,212,196,0.08)'; ctx.fillRect(26, yOf(45), W - 26, yOf(35) - yOf(45));
      const tn = now() / 1000;
      ctx.beginPath();
      for (let x = 26; x <= W; x += 2) {
        const tt = tn - (1 - (x - 26) / (W - 26)) * WIN;
        let v = 0;
        for (let i = breaths.length - 1; i >= 0; i--) { const b = breaths[i]; if (tt - b.t > b.dur + 0.4) break; v = Math.max(v, prof(tt - b.t, b.h, b.dur)); }
        const y = yOf(v);
        if (x === 26) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = '#f2d64b'; ctx.lineWidth = 2.2; ctx.shadowColor = '#f2d64b'; ctx.shadowBlur = 6; ctx.stroke(); ctx.shadowBlur = 0;
    }
    return {
      el: root,
      breath(h, dur = 1.7) { breaths.push({ t: now() / 1000, h, dur }); while (breaths.length > 30) breaths.shift(); },
      frame() { draw(); },
      nums({ et, rr, msg, tone }) {
        q('et').textContent = et > 0 ? Math.round(et) : '--';
        q('et').className = et >= 30 ? 'ok' : et > 0 ? 'lo' : 'none';
        q('rr').textContent = rr > 0 ? Math.round(rr) : '--';
        const m = q('cmsg'); m.textContent = msg || ''; m.className = `itb-capmsg ${tone || ''} ${msg ? 'on' : ''}`;
      },
      spot(cur, results) {
        root.querySelectorAll('.spot').forEach(s => { s.classList.toggle('on', s.dataset.s === cur); s.setAttribute('data-res', (results[s.dataset.s] && results[s.dataset.s].tone) || ''); });
        ['r', 'l', 'epi'].forEach(k => {
          const row = root.querySelector(`[data-r="${k}"]`); const r = results[k];
          row.querySelector('b').textContent = r ? r.label : '—'; row.className = r ? r.tone : '';
          row.classList.toggle('cur', k === cur);
        });
      },
      destroy() { root.remove(); },
    };
  }

  /* ═══════════════════════════ RESULT CARD ═══════════════════════════ */
  function ResultCard(host, r) {
    const root = el('div', 'itb-res nza-hud rail nza-int nza-pop');
    root.innerHTML = `
      <div class="itb-res-top"><div class="grade g-${esc(r.grade)}">${esc(r.grade)}</div><div><div class="nza-label">${esc(r.kicker)}</div><div class="itb-res-t ${r.tone || ''}">${esc(r.title)}</div><div class="nza-sub">${esc(r.sub || '')}</div></div><div class="itb-res-score"><b>${Math.round(r.score)}</b><span>/100</span></div></div>
      <div class="itb-res-rows">${r.rows.map(x => `<div><span>${esc(x[0])}</span><b class="${x[2] || ''}">${esc(x[1])}</b></div>`).join('')}</div>
      ${r.notes.length ? `<ul class="itb-res-notes">${r.notes.map(n => `<li class="${n[1] || ''}">${icon(n[1] === 'ok' ? 'check' : 'alert')}<span>${esc(n[0])}</span></li>`).join('')}</ul>` : ''}`;
    host.appendChild(root);
    return { el: root, destroy() { root.remove(); } };
  }

  /* ═══════════════════════════ SESSION ═══════════════════════════ */
  const ARREST = new Set(['vf', 'vt', 'asystole', 'pea']);
  const PHASE = { 1: 'preox', 2: 'position', 3: 'suction', 4: 'insert', 5: 'lift', 6: 'tube', 7: 'cuff', 8: 'confirm', B: 'bvm' };
  let S = null, UI = null, raf = 0, lastT = 0, uiT = 0, appDef = null;
  const held = {};
  let ptr = null;
  const mouse = { x: 0.62, y: 0.55 };

  const freshVl = () => ({ depth: 0.72, steer: rnd(-0.06, 0.06), expo: 0, lift: 0, lever: 0, leverOn: false, burp: false, stable: 0, hold: 0, locked: null, best: '4', teethAt: 0 });
  const freshTube = () => ({ show: false, ax: 0.58, ay: 0.58, pr: 0, push: false, pull: false, placed: null, hits: 0, inflated: false });
  const freshCuff = () => ({ ml: 0, p: 0, inj: 0, leak: true, tickT: 0 });
  const freshConf = () => ({ spot: null, res: {}, breaths: 0, eff: 0, capno: 0, oes: 0, listened: { r: false, l: false, epi: false }, lastEt: 0 });

  function newSession(d) {
    const a = d.anat || {}, v = d.vitals || {}, c = d.cfg || {};
    const grade = clamp(Math.round(a.grade || 1), 1, 4);
    const spo2 = clamp(Number(v.spo2) || 90, 40, 100);
    const s = {
      mode: d.mode === 'bvm' ? 'bvm' : 'intubate',
      patient: d.patient || {},
      cfg: {
        attempts: c.attempts || 3, cadence: c.cadence || 5, ideal: c.squeeze || 1, breaths: c.preoxBreaths || 6, bvmBreaths: c.breaths || 8,
        abort: c.abortSpo2 || 90, crash: c.crashSpo2 || 75, band: Array.isArray(c.cuffBand) ? c.cuffBand : [20, 30],
      },
      A: {
        grade, dif: (grade - 1) / 3, soil: clamp(Number(a.soil) || 0, 0, 1), soilKind: a.soilKind || 'blood', bleed: clamp(Number(a.bleed) || 0, 0, 1),
        cspine: !!a.cspine, tube: a.tube || 7.5, depth: a.depth || 23, cuffMl: clamp(Number(a.cuffMl) || 8.5, 5, 10),
        open: clamp(Number(a.open) || 0.85, 0.6, 1.1), gx: clamp(Number(a.gx) || 0, -0.12, 0.12), gy: clamp(Number(a.gy) || 0, -0.06, 0.06),
        aryt: clamp(Number(a.aryt) || 1, 0.8, 1.25), tongue: clamp(Number(a.tongue) || 0, 0, 1), ant: clamp(Number(a.ant) || 0, 0, 1),
        desat: clamp(Number(a.desat) || 1, 0.5, 2.5), safe: clamp(Number(a.safe) || 60, 15, 180), apnoeic: a.apnoeic !== false,
        intubated: !!a.intubated, misplaced: !!a.misplaced,
      },
      vit: { hr: Number(v.hr) || 110, sys: Number(v.sys) || 100, dia: Number(v.dia) || 62, map: Number(v.map) || 75, rhythm: v.rhythm || 'stach', temp: Number(v.temp) || 36.6 },
      spo2, spo2Disp: spo2, spo2Start: spo2, boost: 0, reserve: 0, trend: 0, hr: Number(v.hr) || 110, low: spo2,
      etco2: 0, rr: 0, breaths: [], lastGood: 0, gastric: clamp(Number(a.gastric) || 0, 0, 100),
      t0: now(), time: 0, power: 0, smear: 0, step: 0, stepT0: now(), attemptOn: false, attemptNo: 0, attemptT0: 0, attemptsUsed: 0, crashes: 0, warned: false, alarmAt: 0,
      pre: { n: 0, good: 0, q: [], hist: [] }, preScore: null, hist: [],
      pos: { tilt: 0, jaw: 0, towel: false, align: 0, hold: 0, done: false, score: 0 },
      suc: { on: false, c0: 0, ml: 0, done: false, skipped: false, left: 0, gurgleAt: 0, sndAt: 0 },
      vl: freshVl(), tube: freshTube(), cuff: freshCuff(), conf: freshConf(),
      bvm: { n: 0, q: [], good: 0 },
      teeth: 0, wrongPull: 0, detected: false, firstPass: true, clBest: '4', done: false, failed: false, result: null,
    };
    s.soil = Soil(s.mode === 'intubate' ? s.A.soil : 0, s.A.bleed);
    s.bag = Bag({ cadence: s.cfg.cadence, ideal: s.cfg.ideal, onBreath: b => { const st = STEPS[S.step]; if (st && st.breath) st.breath(b); } });
    return s;
  }

  /* ─────────────── physiology during the procedure ─────────────── */
  function sim(dt) {
    const A = S.A, v = S.vit;
    const arrest = ARREST.has(v.rhythm);
    const t = now();
    const since = S.lastGood ? (t - S.lastGood) / 1000 : 999;
    const vent = since < S.cfg.cadence * 1.7;
    if (S.boost > 0) { const take = S.boost * Math.min(1, dt / 2.4); S.spo2 += take; S.boost -= take; }
    if (!vent) {
      const k = A.desat * (A.apnoeic ? 1 : 0.5) * (arrest ? 2.2 : 1);
      if (S.reserve > 0) { S.reserve = Math.max(0, S.reserve - dt * k / A.safe); S.spo2 -= 0.02 * dt * k; }
      else S.spo2 -= (0.30 + 0.05 * Math.max(0, 97 - S.spo2)) * dt * k;
    }
    S.spo2 = clamp(S.spo2, 35, 100);
    const prev = S.spo2Disp;
    S.spo2Disp += (S.spo2 - S.spo2Disp) * Math.min(1, dt / 2.6);
    S.trend = lerp(S.trend, (S.spo2Disp - prev) / Math.max(dt, 0.001), Math.min(1, dt * 2));
    S.low = Math.min(S.low, S.spo2Disp);
    let hr = v.hr;
    if (S.spo2Disp < 92) hr += (92 - S.spo2Disp) * 1.5;
    if (S.spo2Disp < 78) hr = v.hr * clamp(0.45 + (S.spo2Disp - 60) / 40, 0.35, 1);
    if (S.step >= 4 && S.step <= 6) hr += 9;
    S.hr = lerp(S.hr, hr, Math.min(1, dt * 0.8));
    S.breaths = S.breaths.filter(b => t - b < 30000);
    S.rr = S.breaths.length >= 2 ? S.breaths.length * 2 : 0;
    if (since > 9) S.etco2 = 0;
  }

  // one squeeze reaches the patient: route 'mask' or 'tube'
  function deliverBreath(b, route) {
    const t = now();
    let eff = b.short ? 0.2 : b.long ? 0.9 : 1;
    let et = 0;
    if (route === 'mask') {
      et = 33 + rnd(-2, 3) + (S.attemptsUsed ? 4 : 0);
      if (b.long || (b.early && b.interval < S.cfg.cadence * 0.65)) S.gastric = clamp(S.gastric + 6 + Math.max(0, b.hold - 1.3) * 22, 0, 100);
      else S.gastric = Math.max(0, S.gastric - 0.6);
    } else if (S.tube.placed === 'trachea') {
      const leak = S.cuff.leak;
      const mainstem = tubeCm() > S.A.depth + 2;
      eff *= (leak ? 0.6 : 1) * (mainstem ? 0.8 : 1);
      et = (leak ? 22 : 36) + rnd(-2, 3) + (S.attemptOn ? 7 : 0);
    } else {
      eff = 0;
      et = S.conf.oes < 2 ? [8, 3][S.conf.oes] + rnd(0, 2) : 0;
      S.conf.oes++;
      S.gastric = clamp(S.gastric + 9, 0, 100);
    }
    if (eff > 0.15) {
      S.lastGood = t;
      S.boost += Math.max(0, 99.4 - (S.spo2 + S.boost)) * 0.22 * eff * (0.4 + 0.6 * b.q);
      S.reserve = Math.min(1, S.reserve + 0.17 * eff * (0.3 + 0.7 * b.q));
    }
    S.breaths.push(t);
    S.etco2 = et;
    return { eff, et };
  }

  const tubeCm = () => S.tube.pr * CM_FULL;
  function cuffPressure(ml) {
    let seal = S.A.cuffMl;
    if (S.tube.placed === 'oesophagus') seal *= 1.55;
    if (tubeCm() < S.A.depth - 2.5) seal *= 0.72;
    const a = 0.55 * seal;
    if (ml <= a) return ml * 1.2;
    return a * 1.2 + (25 - a * 1.2) * Math.pow((ml - a) / (seal - a), 1.7);
  }

  /* ─────────────── attempts ─────────────── */
  function startAttempt() { S.attemptOn = true; S.attemptNo++; S.attemptT0 = now(); if (S.attemptNo > 1) S.firstPass = false; }
  function abortAttempt(why) {
    if (!S || S.done) return;
    S.attemptOn = false; S.attemptsUsed++; S.warned = false;
    if (why === 'crash') S.crashes++;
    S.vl = freshVl(); S.tube = freshTube(); S.cuff = freshCuff(); S.conf = freshConf();
    S.firstPass = false;
    release();
    if (S.attemptsUsed >= S.cfg.attempts) { failAirway(); return; }
    goStep(1, { reox: true, why });
  }

  /* ─────────────── panels ─────────────── */
  const TOOL_DEF = () => [
    { key: '1', icon: 'itb-bvm', label: T('tool_bvm', 'BVM bag') },
    { key: '2', icon: 'itb-scope', label: T('tool_scope', 'Video laryngoscope') },
    { key: '3', icon: 'itb-suction', label: T('tool_suction', 'Suction') },
    { key: '4', icon: 'itb-tube', label: Tf('tool_tube', 'ETT %s', S.A.tube) },
    { key: '5', icon: 'syringe', label: T('tool_cuff', '10 ml syringe') },
    { key: '6', icon: 'itb-holder', label: T('tool_holder', 'Tube fixation') },
  ];
  function tools(active, done = []) {
    if (S.mode === 'bvm') {
      return [
        { key: '1', icon: 'itb-bvm', label: S.A.intubated ? T('tool_bvm_tube', 'Bag on the tube') : T('tool_bvm', 'BVM bag'), state: 'active', sub: T('in_use', 'IN HAND') },
        { key: '2', icon: 'drop', label: T('tool_o2', 'Oxygen 15 L/min'), state: 'done' },
      ];
    }
    return TOOL_DEF().map(t => Object.assign(t, t.key === active ? { state: 'active', sub: T('in_use', 'IN HAND') } : done.includes(t.key) ? { state: 'done' } : {}));
  }
  const STEP_NAMES = () => [T('n1', 'Pre-oxygenate'), T('n2', 'Position the head'), T('n3', 'Suction'), T('n4', 'Insert the blade'), T('n5', 'Lift'), T('n6', 'Pass the tube'), T('n7', 'Inflate the cuff'), T('n8', 'Confirm & secure')];
  function setPanel(o) {
    UI.pp.set(Object.assign({ step: S.mode === 'bvm' ? 1 : S.step, total: S.mode === 'bvm' ? 1 : 8, titleTone: '', steps: S.mode === 'bvm' ? null : STEP_NAMES() }, o));
    UI.ppHints = o.hints || UI.ppHints;
    updateStats();
  }
  function statList() {
    const sp = Math.round(S.spo2Disp);
    const spo2 = { id: 'spo2', label: 'SpO₂', value: sp, unit: '%', tone: sp < S.cfg.abort ? 'red' : sp < 94 ? 'amber' : '' };
    if (S.mode === 'bvm') {
      return [spo2,
        { id: 'br', label: T('st_breaths', 'Breaths'), value: S.bvm.n, unit: `/${S.cfg.bvmBreaths}` },
        { id: 'rate', label: T('st_rate', 'Rate'), value: S.rr || '--', unit: '/min' }];
    }
    const att = S.attemptOn ? (now() - S.attemptT0) / 1000 : -1;
    return [spo2,
      { id: 'att', label: T('st_attempt', 'Attempt'), value: att >= 0 ? tfmt(att) : '--:--', tone: att > 45 ? 'amber' : '' },
      { id: 'step', label: T('st_step', 'Step time'), value: tfmt((now() - S.stepT0) / 1000) }];
  }
  function updateStats() {
    if (!UI || !UI.pp || S.done) return;
    const st = STEPS[S.step];
    UI.pp.set({ stats: statList(), wide: st && st.wide ? st.wide() : null });
    const v = UI.pp.el.querySelector('.pp-stat[data-id="spo2"] .v');
    if (v && Math.abs(S.trend) > 0.04) v.insertAdjacentHTML('beforeend', `<span class="itb-arrow ${S.trend > 0 ? 'up' : 'dn'}">${S.trend > 0 ? '▲' : '▼'}</span>`);
  }
  function flash(type, text, ms) { if (UI && UI.pp) UI.pp.flash(type, text, ms === undefined ? 2600 : ms); }

  function show(kind) {
    const R = UI.root;
    const want = {
      vent: kind === 'vent', sagp: kind === 'sag', scope: kind === 'scope', cuff: kind === 'cuff', conf: kind === 'conf', res: kind === 'res',
      sagm: kind === 'scope' && S.step >= 4 && S.step <= 6,
    };
    const DR = UI.dockR, DC = UI.dockC;
    const drop = k => { if (UI[k]) { UI[k].destroy(); UI[k] = null; } };
    if (!want.vent) drop('vent'); else if (!UI.vent) UI.vent = VentCard(DR);
    if (!want.sagp) drop('sagp'); else if (!UI.sagp) UI.sagp = SagPanel(DR);
    if (!want.scope) drop('scope'); else if (!UI.scope) UI.scope = Scope(DC);
    if (!want.sagm) drop('sagm'); else if (!UI.sagm) UI.sagm = SagMini(R);
    if (!want.cuff) drop('cuff'); else if (!UI.cuff) UI.cuff = CuffPanel(DR, { band: S.cfg.band, onHold: d => { S.cuff.inj = d; } });
    if (!want.conf) drop('conf'); else if (!UI.conf) UI.conf = ConfirmPanel(DR, { onSpot: s => STEPS[8].spot(s) });
    if (!want.res) drop('res');
    UI.root.dataset.view = kind;
  }

  function SagPanel(host) {
    const root = el('div', 'itb-sagp nza-hud rail nza-int nza-in');
    root.innerHTML = `
      <div class="itb-ph"><div><div class="nza-label">${esc(T('pos_label', 'Airway position'))}</div><div class="itb-pt">${esc(S.A.cspine ? T('pos_title_c', 'In-line stabilisation') : T('pos_title', 'Sniffing position'))}</div></div>
        ${S.A.cspine ? `<span class="chipx sm red">${icon('alert')}${esc(T('pos_cspine', 'Neck injury'))}</span>` : `<span class="chipx sm teal">${esc(T('pos_axes', 'Align OA · PA · LA'))}</span>`}</div>
      <div class="itb-sagbox"></div>
      <div class="itb-posrow">
        <div class="itb-pc"><span>${icon('itb-towel')}${esc(T('pos_towel', 'Towel under the head'))}<kbd>T</kbd></span><i data-k="tg"></i></div>
        <div class="itb-pc"><span>${esc(T('pos_tilt', 'Head tilt'))}</span><b data-k="tilt">0°</b></div>
        <div class="itb-pc"><span>${esc(T('pos_jaw', 'Jaw thrust'))}</span><b data-k="jaw">0%</b></div>
      </div>`;
    host.appendChild(root);
    const sag = Sagittal(root.querySelector('.itb-sagbox'), { onDrag: p => { Object.assign(S.pos, p); } });
    const tg = NZA.ui.Toggle(root.querySelector('[data-k="tg"]'), { on: S.pos.towel, onChange: v => STEPS[2].towel(v) });
    return {
      el: root,
      update() {
        sag.set({ tilt: S.pos.tilt, jaw: S.pos.jaw, towel: S.pos.towel, cspine: S.A.cspine, handles: true, blade: null, tube: null, axes: true });
        tg.set(S.pos.towel);
        const tb = root.querySelector('[data-k="tilt"]'); tb.textContent = `${Math.round(S.pos.tilt)}°`;
        const inT = S.A.cspine ? S.pos.tilt <= 6 : S.pos.tilt >= 15 && S.pos.tilt <= 26;
        tb.className = inT ? 't-teal' : '';
        const jb = root.querySelector('[data-k="jaw"]'); jb.textContent = `${Math.round(S.pos.jaw * 100)}%`;
        jb.className = S.pos.jaw >= (S.A.cspine ? 0.75 : 0.6) ? 't-teal' : '';
      },
      destroy() { sag.destroy(); root.remove(); },
    };
  }
  function SagMini(host) {
    const root = el('div', 'itb-sagm nza-hud nza-int nza-in');
    root.innerHTML = `<div class="itb-ph sm"><div class="nza-label">${esc(T('sag_label', 'Blade position'))}</div><span class="itb-sagtag" data-k="tag"></span></div><div class="itb-sagbox"></div>`;
    host.appendChild(root);
    const sag = Sagittal(root.querySelector('.itb-sagbox'), { mini: true });
    return {
      el: root,
      update() {
        const tubeOn = S.step === 6 && S.tube.pr > 0.01;
        sag.set({ tilt: S.pos.tilt, jaw: S.pos.jaw, towel: S.pos.towel, cspine: S.A.cspine, handles: false, axes: false,
          blade: { depth: S.vl.depth, lift: S.step >= 5 ? S.vl.expo : 0, lever: S.vl.lever },
          tube: tubeOn ? { pr: Math.min(S.tube.pr, PLANE) / 1, placed: null } : null });
        const d = S.vl.depth;
        const tag = d > 1.12 ? T('sag_deep', 'Too deep') : d >= 0.93 ? T('sag_vall', 'Vallecula') : d > 0.55 ? T('sag_tb', 'Tongue base') : T('sag_oral', 'Oral cavity');
        const k = root.querySelector('[data-k="tag"]'); k.textContent = tag; k.className = `itb-sagtag ${d > 1.12 ? 'red' : d >= 0.93 ? 'teal' : ''}`;
      },
      destroy() { sag.destroy(); root.remove(); },
    };
  }

  /* ═══════════════════════════ STEPS ═══════════════════════════ */
  function goStep(n, opts = {}) {
    if (!S) return;
    const prev = STEPS[S.step];
    if (prev && prev.exit) prev.exit();
    release();
    S.step = n; S.stepT0 = now();
    STEPS[n].enter(opts);
    NZA.post(`${APP}:step`, { step: n, phase: opts.reox ? 'reox' : PHASE[n] });
    updateStats();
  }
  function release() {
    ptr = null;
    if (S) { S.suc.on = false; S.tube.push = false; S.tube.pull = false; S.cuff.inj = 0; S.vl.burp = false; if (S.bag.holding) S.bag.up(); }
    Object.keys(held).forEach(k => { held[k] = false; });
  }
  const H = (keys, label) => ({ keys, label });
  const breathMsg = b => (b.short ? ['bad', T('br_short', 'Too short — the chest did not rise')]
    : b.long ? ['warn', T('br_long', 'Too long — air is going into the stomach')]
      : b.early ? ['warn', T('br_early', 'Too early — wait for the ring')]
        : b.late ? ['warn', T('br_late', 'Late — keep a steady rhythm')]
          : ['ok', T('br_good', 'Good breath — the chest rises')]);

  function ventTick() {
    const bag = S.bag, started = bag.count > 0;
    UI.vent.frame({ phase: bag.phase(), holdSec: bag.holdSec(), holding: bag.holding, ideal: S.cfg.ideal, started });
    if (bag.holding) { const h = bag.holdSec(); UI.vent.text(`${h.toFixed(1)} s`, h < S.cfg.ideal - 0.2 ? T('vent_keep', 'keep squeezing') : h > S.cfg.ideal + 0.35 ? T('vent_release', 'release now') : T('vent_good', 'release'), h > S.cfg.ideal + 0.35 ? 'amber' : h >= S.cfg.ideal - 0.2 ? 'teal' : ''); return; }
    if (!started) { UI.vent.text(T('vent_squeeze', 'SQUEEZE'), T('vent_first', 'hold Space for 1 s'), 'teal'); return; }
    const rem = S.cfg.cadence - bag.phase() * S.cfg.cadence;
    if (rem > 0.5) UI.vent.text(`${rem.toFixed(1)} s`, T('vent_next', 'until the next breath'));
    else if (rem > -0.6) UI.vent.text(T('vent_squeeze', 'SQUEEZE'), T('vent_now', 'now'), 'teal');
    else UI.vent.text(T('vent_lateb', 'LATE'), T('vent_now', 'now'), 'amber');
  }

  const STEPS = {
    /* 1 · pre-oxygenate / re-oxygenate */
    1: {
      enter(o) {
        S.reox = !!o.reox;
        show('vent');
        UI.vent.title(T('vent_mask', 'Face mask · two-hand seal'), T('vent_o2', '15 L/min O₂'));
        S.bag.reset(); S.pre = { n: 0, good: 0, q: [], hist: [] };
        UI.vent.hist([]); UI.vent.stats({ breaths: `0/${S.cfg.breaths}`, interval: '--', vol: '--' }); UI.vent.gastric(S.gastric);
        setPanel({
          title: S.reox ? T('s1_title_re', 'Re-oxygenate') : T('s1_title', 'Pre-oxygenate'),
          text: S.reox ? Tf('s1_text_re', 'Mask back on. Give a smooth {Space} squeeze of about a second, one breath every %s s, until the SpO₂ climbs again.', S.cfg.cadence)
            : Tf('s1_text', 'Seal the mask and give a smooth {Space} squeeze of about a second, one breath every %s s. Fill the oxygen reserve before the mask comes off.', S.cfg.cadence),
          tag: S.reox ? Tf('tag_attempt', 'Attempt %s of %s', S.attemptsUsed + 1, S.cfg.attempts) : '',
          tools: tools('1'),
          hints: [H(['Space'], T('h_squeeze', 'squeeze')), H(['Enter'], T('h_continue', 'continue'))],
        });
        if (o.why === 'crash') flash('bad', T('f_crash', 'Critical desaturation — the attempt was abandoned. Bag the patient back up.'), 5000);
        else if (o.why === 'manual') flash('warn', T('f_aborted', 'Attempt aborted. Re-oxygenate before trying again.'), 4000);
        else if (o.why === 'pulled') flash('ok', T('f_pulled', 'Good call — no CO₂, the tube was in the oesophagus. Re-oxygenate.'), 5000);
        else if (o.why === 'wrongpull') flash('bad', T('f_wrongpull', 'That tube had a CO₂ trace — it was in the trachea.'), 5000);
        else if (o.why === 'out') flash('bad', T('f_out', 'The tube came out. Re-oxygenate and try again.'), 4500);
      },
      breath(b) {
        deliverBreath(b, 'mask');
        S.pre.n++; S.pre.q.push(b.q); S.pre.hist.push(b); if (b.q >= 0.6) S.pre.good++;
        UI.vent.hist(S.pre.hist);
        UI.vent.stats({ breaths: `${S.pre.good}/${S.cfg.breaths}`, interval: b.first ? '--' : `${b.interval.toFixed(1)} s`, vol: `${b.vol} ml` });
        UI.vent.gastric(S.gastric);
        const m = breathMsg(b); flash(m[0], m[1], 1800);
        if (S.gastric >= 60 && !S.vomitWarned) { S.vomitWarned = true; flash('bad', T('f_gastric', 'The stomach is full of air — the patient may vomit.'), 4000); S.soil.reset(Math.max(0.5, S.A.soil)); S.A.soil = Math.max(0.5, S.A.soil); S.A.soilKind = 'vomit'; S.suc.done = false; S.suc.c0 = 0; }
        if (S.pre.good >= S.cfg.breaths && S.reserve >= 0.8 && !S.pre.doneAt) {
          S.pre.doneAt = now();
          flash('ok', Tf('f_preox', 'Pre-oxygenated — SpO₂ %s%. Mask off.', Math.round(S.spo2)), 1500);
          setTimeout(() => { if (S && S.step === 1 && S.pre.doneAt) STEPS[1].next(); }, 1300);
        }
      },
      tick() { ventTick(); },
      wide() {
        return { label: T('w_reserve', 'O₂ reserve'), value: Math.round(S.reserve * 100), unit: '%', meter: { value: S.reserve, zone: [0.8, 1] },
          caption: S.reserve >= 0.8 ? T('c_reserve_ok', 'Full — safe to start') : Tf('c_reserve', 'Breath %s of %s · keep the rhythm', Math.min(S.pre.good + 1, S.cfg.breaths), S.cfg.breaths), captionTone: S.reserve >= 0.8 ? 'teal' : '' };
      },
      enterKey() { if (S.pre.n >= 3) this.next(); else flash('warn', T('f_three', 'Give at least 3 breaths first.')); },
      next() {
        if (!S.preScore) S.preScore = S.pre.q.length ? (S.pre.q.reduce((a, b) => a + b, 0) / S.pre.q.length) * Math.min(1, S.pre.good / S.cfg.breaths) : 0;
        goStep(S.pos.done ? 3 : 2);
      },
      squeeze: true,
    },

    /* 2 · head position */
    2: {
      enter() {
        show('sag');
        setPanel({
          title: T('s2_title', 'Position the head'),
          text: S.A.cspine ? T('s2_text_c', 'Suspected **neck injury** — keep the head neutral. No towel, no tilt: drag the chin up to thrust the jaw.')
            : T('s2_text', 'Make the **sniffing position**: towel under the head {T}, drag the forehead to tilt the head and the chin to thrust the jaw until the axes line up.'),
          tag: '', tools: tools('1'),
          hints: [H(['Drag'], T('h_handles', 'forehead / chin')), H(['W', 'S'], T('h_tilt', 'tilt')), H(['A', 'D'], T('h_jaw', 'jaw')), H(['T'], T('h_towel', 'towel')), H(['Space'], T('h_keepbag', 'keep bagging'))],
        });
        S.pos.hold = 0;
      },
      towel(v) {
        S.pos.towel = !!v;
        if (S.pos.towel && S.A.cspine) flash('bad', T('f_towel_c', 'Not with a neck injury — keep the spine in line.'));
      },
      tick(dt) {
        const p = S.pos;
        if (held.KeyW || held.ArrowUp) p.tilt = clamp(p.tilt + 16 * dt, 0, 40);
        if (held.KeyS || held.ArrowDown) p.tilt = clamp(p.tilt - 16 * dt, 0, 40);
        if (held.KeyD || held.ArrowRight) p.jaw = clamp(p.jaw + 0.7 * dt, 0, 1);
        if (held.KeyA || held.ArrowLeft) p.jaw = clamp(p.jaw - 0.7 * dt, 0, 1);
        const ax = axisAngles(p);
        p.align = ax.align;
        const ok = S.A.cspine ? (!p.towel && p.tilt <= 6 && p.jaw >= 0.75) : (p.towel && ax.align >= 0.78 && p.jaw >= 0.6);
        if (S.A.cspine && p.tilt > 10 && !p.warnTilt) { p.warnTilt = true; flash('bad', T('f_tilt_c', 'Do not tilt the head — the neck may be broken.')); }
        p.hold = ok ? p.hold + dt : 0;
        if (UI.sagp) UI.sagp.update();
        if (p.hold > 0.9 && !p.done) {
          p.done = true;
          p.score = S.A.cspine ? (p.towel ? 0.4 : 1) * (p.tilt > 10 ? 0.5 : 1) : clamp((ax.align - 0.6) / 0.32, 0, 1) * 0.7 + p.jaw * 0.3;
          flash('ok', S.A.cspine ? T('f_pos_c', 'Head neutral, jaw thrust held.') : T('f_pos', 'Sniffing position — the axes line up.'), 1400);
          setTimeout(() => { if (S && S.step === 2) goStep(3); }, 900);
        }
      },
      wide() {
        const a = S.A.cspine ? (S.pos.tilt <= 6 && !S.pos.towel ? 1 : 0.3) * (0.5 + S.pos.jaw * 0.5) : S.pos.align;
        return { label: S.A.cspine ? T('w_inline', 'In-line') : T('w_align', 'Alignment'), value: Math.round(a * 100), unit: '%', meter: { value: a, zone: [0.78, 1] },
          caption: S.pos.jaw < (S.A.cspine ? 0.75 : 0.6) ? T('c_jaw', 'Thrust the jaw to open the airway') : a >= 0.78 ? T('c_hold', 'Hold it…') : T('c_align', 'Line up the dashed axes'), captionTone: a >= 0.78 ? 'teal' : '' };
      },
      breath(b) { deliverBreath(b, 'mask'); const m = breathMsg(b); flash(m[0], m[1], 1500); },
      enterKey() { flash('warn', T('f_pos_need', 'Get the head into position first.')); },
      squeeze: true,
    },

    /* 3 · suction */
    3: {
      enter() {
        if (!S.attemptOn) startAttempt();
        show('scope');
        S.vl.depth = 0.74; S.vl.expo = 0.12;
        const cov = S.soil.coverage();
        if (!S.suc.c0) S.suc.c0 = Math.max(cov, 0.0001);
        S.suc.soiled = cov > 0.02;
        const kind = S.A.soilKind;
        const what = kind === 'vomit' ? T('soil_vomit', 'vomit') : kind === 'water' ? T('soil_water', 'water and froth') : T('soil_blood', 'blood');
        setPanel({
          title: T('s3_title', 'Suction the airway'),
          text: S.suc.soiled ? Tf('s3_text', 'The airway is **gurgling** with %s. Hold {Click} on the screen and sweep the suction tip through it.', what)
            : T('s3_text_clear', 'The airway is clear — no suction needed. Press {Enter} to insert the blade.'),
          tag: Tf('tag_attempt', 'Attempt %s of %s', S.attemptNo, S.cfg.attempts),
          tools: tools('3', ['1']),
          hints: S.suc.soiled ? [H(['Click'], T('h_suck', 'suction (hold)')), H(['Enter'], T('h_skip', 'skip')), H(['B'], T('h_abort_att', 'abort attempt'))] : [H(['Enter'], T('h_continue', 'continue')), H(['B'], T('h_abort_att', 'abort attempt'))],
        });
      },
      tick(dt) {
        const cov = S.soil.coverage();
        const t = now();
        if (S.suc.on) {
          const f = S.soil.at(mouse.x, mouse.y);
          S.soil.suck(mouse.x, mouse.y, 0.17);
          S.suc.ml += f * dt * 60;
          if (t - S.suc.sndAt > 230 && snd()) { S.suc.sndAt = t; NZA.audio.noise(260, { vol: f > 0.3 ? 0.07 : 0.03, lp: f > 0.3 ? 900 : 3200, hp: 300, attack: 0.1, release: 0.3 }); }
        } else if (S.suc.soiled && cov > 0.02 && t - S.suc.gurgleAt > 1500 && snd()) {
          S.suc.gurgleAt = t; NZA.audio.noise(520, { vol: 0.05, lp: 380, hp: 70, attack: 0.25, release: 0.45 });
        }
        S.soil.refill(dt * 0.6);
        if (S.suc.soiled && !S.suc.done && cov < 0.02) {
          S.suc.done = true; S.suc.left = 0;
          flash('ok', T('f_clear', 'Airway clear.'), 1300);
          setTimeout(() => { if (S && S.step === 3) goStep(4); }, 800);
        }
      },
      wide() {
        const cov = S.soil.coverage(), f = clamp(cov / Math.max(S.suc.c0, 0.02), 0, 1);
        return { label: T('w_soil', 'Airway soiling'), value: Math.round(f * 100), unit: '%', meter: { value: f, tone: 'red', zone: [0, 0.06] },
          caption: Tf('c_canister', 'Canister %s ml', Math.round(S.suc.ml)), captionTone: f < 0.1 ? 'teal' : '' };
      },
      enterKey() {
        const cov = S.soil.coverage();
        if (cov > 0.02) { S.suc.skipped = true; S.suc.left = clamp(cov / Math.max(S.suc.c0, 0.02), 0, 1); } else if (!S.suc.soiled) S.suc.skipped = true;
        goStep(4);
      },
      down(btn) { if (btn === 0) S.suc.on = true; },
    },

    /* 4 · insert the blade */
    4: {
      enter() {
        if (!S.attemptOn) startAttempt();
        show('scope');
        S.vl.depth = 0; S.vl.expo = 0; S.vl.stable = 0;
        setPanel({
          title: T('s4_title', 'Insert the blade'),
          text: T('s4_text', 'Drag up to slide the video laryngoscope over the tongue. Stop with the tip in the **vallecula**, just in front of the epiglottis.'),
          tag: Tf('tag_attempt', 'Attempt %s of %s', S.attemptNo, S.cfg.attempts),
          tools: tools('2', ['1', S.suc.done || S.suc.skipped ? '3' : '']),
          hints: [H(['Drag'], T('h_advance', 'advance / steer')), H(['W', 'S'], T('h_fine', 'fine')), H(['3'], T('h_suck', 'suction (hold)')), H(['B'], T('h_abort_att', 'abort attempt'))],
        });
      },
      tick(dt) {
        const v = S.vl;
        if (held.KeyW || held.ArrowUp) v.depth = clamp(v.depth + 0.32 * dt, 0, 1.35);
        if (held.KeyS || held.ArrowDown) v.depth = clamp(v.depth - 0.32 * dt, 0, 1.35);
        if (held.KeyA || held.ArrowLeft) v.steer = clamp(v.steer - 0.5 * dt, -0.6, 0.6);
        if (held.KeyD || held.ArrowRight) v.steer = clamp(v.steer + 0.5 * dt, -0.6, 0.6);
        const inV = v.depth >= 0.93 && v.depth <= 1.07 && Math.abs(v.steer) < 0.16;
        v.stable = inV && !ptr ? v.stable + dt : 0;
        if (v.stable > 0.5 && !v.placedAt) {
          v.placedAt = now();
          flash('ok', T('f_vall', 'Tip in the vallecula.'), 1200);
          setTimeout(() => { if (S && S.step === 4) goStep(5); }, 650);
        }
      },
      wide() {
        const d = S.vl.depth;
        const tone = d > 1.12 ? 'red' : d >= 0.93 ? 'teal' : '';
        return { label: T('w_blade', 'Blade depth'), value: Math.round(d / 1.0 * 100), unit: '%', meter: { value: clamp(d / 1.3, 0, 1), zone: [0.93 / 1.3, 1.07 / 1.3], tone: d > 1.12 ? 'red' : '' },
          caption: d > 1.12 ? T('c_deep', 'Too deep — pull back') : Math.abs(S.vl.steer) > 0.2 ? T('c_mid', 'Off the midline — steer back') : d >= 0.93 ? T('c_vall', 'In the vallecula') : T('c_advance', 'Advance over the tongue'), captionTone: tone };
      },
      enterKey() { flash('warn', T('f_vall_need', 'Put the tip in the vallecula first.')); },
      down(btn, x, y) { if (btn === 0) ptr = { btn, x0: x, y0: y, d0: S.vl.depth, s0: S.vl.steer }; },
      move(x, y) { if (!ptr) return; S.vl.depth = clamp(ptr.d0 + (ptr.y0 - y) * 1.6, 0, 1.35); S.vl.steer = clamp(ptr.s0 + (x - ptr.x0) * 1.2, -0.6, 0.6); },
    },

    /* 5 · lift */
    5: {
      enter() {
        show('scope');
        S.vl.hold = 0; S.vl.lift = 0;
        S.vl.target = this.best();
        setPanel({
          title: T('s5_title', 'Lift to see the cords'),
          text: T('s5_text', 'Drag **up and away** along the handle to lift the epiglottis. Never rock back on the teeth. Hold {E} for BURP if the view is poor.'),
          tools: tools('2', ['1', S.suc.done || S.suc.skipped ? '3' : '']),
          hints: [H(['Drag ↗'], T('h_lift', 'lift')), H(['E'], T('h_burp', 'BURP (hold)')), H(['3'], T('h_suck', 'suction (hold)')), H(['Enter'], T('h_accept', 'accept view'))],
        });
      },
      best() {
        const emax = 1 - 0.62 * S.A.dif;
        const g = geo({ depth: 1.0, expo: Math.min(1, emax + 0.14), burp: true }, S.A);
        const cl = clGrade({ depth: 1.0 }, g);
        return CL_RANK[cl] < CL_RANK['2b'] ? cl : '2b';
      },
      tick(dt) {
        const v = S.vl;
        if (held.KeyW || held.ArrowUp) v.depth = clamp(v.depth + 0.2 * dt, 0, 1.35);
        if (held.KeyS || held.ArrowDown) v.depth = clamp(v.depth - 0.2 * dt, 0, 1.35);
        if (ptr && ptr.btn === 0) {
          const dx = mouse.x - ptr.x0, dy = mouse.y - ptr.y0;
          const along = (dx * 0.55 - dy * 0.83) / 0.30;
          v.lift = clamp(along, 0, 1.25);
          v.lever = clamp(-dx / 0.16, 0, 1) * (v.lift > 0.1 ? 1 : 0.6);
        } else { v.lift = Math.max(0, v.lift - dt * 2.5); v.lever = Math.max(0, v.lever - dt * 3); }
        if (v.lever > 0.55 && !v.leverOn) {
          v.leverOn = true; S.teeth++;
          if (snd()) { NZA.audio.tone(2600, 28, { vol: 0.08, type: 'square' }); NZA.audio.tone(1300, 40, { vol: 0.06, type: 'square', at: 0.03 }); }
          flash('bad', T('f_teeth', 'Clunk — you levered on the upper teeth. Lift along the handle.'), 2600);
        }
        if (v.lever < 0.3) v.leverOn = false;
        const fit = 1 - clamp(Math.abs(v.depth - 1.0) / 0.12, 0, 1) * 0.8;
        const emax = 1 - 0.62 * S.A.dif;
        const alignF = S.A.cspine ? 0.85 : 0.75 + 0.25 * S.pos.align;
        const lifted = Math.min(v.lift, 1);
        const target = Math.min(lifted * fit * alignF, emax) + (v.burp ? 0.14 * Math.min(1, lifted * 2) : 0) - v.lever * 0.25;
        v.expo += (clamp(target, 0, 1) - v.expo) * Math.min(1, dt * 6);
        const cl = clGrade(v, geo(v, S.A));
        if (CL_RANK[cl] < CL_RANK[S.clBest]) S.clBest = cl;
        const good = CL_RANK[cl] <= CL_RANK[v.target];
        v.hold = good && ptr ? v.hold + dt : 0;
        if (v.lift > 1.12 && !v.forceWarn) { v.forceWarn = true; flash('warn', T('f_force', 'Easy — that is a lot of force.'), 1600); }
        if (v.lift < 0.9) v.forceWarn = false;
        if (v.hold > 0.7) this.lock(cl);
      },
      lock(cl) {
        const v = S.vl;
        v.locked = { expo: v.expo, cl };
        flash('ok', Tf('f_view', 'View held — Cormack–Lehane %s.', cl), 1500);
        if (snd()) NZA.audio.success();
        goStep(6);
      },
      wide() {
        const v = S.vl, cl = clGrade(v, geo(v, S.A));
        const good = CL_RANK[cl] <= CL_RANK[v.target || '2b'];
        return { label: T('w_view', 'View'), value: `CL ${cl}`, meter: { value: clamp(v.expo, 0, 1), zone: [0.55, 1], tone: v.lever > 0.35 ? 'red' : '' },
          caption: v.lever > 0.35 ? T('c_teeth', 'Rocking on the teeth!') : good ? T('c_hold_view', 'Good view — hold it') : clCaption(cl), captionTone: v.lever > 0.35 ? 'red' : good ? 'teal' : '' };
      },
      enterKey() {
        const cl = clGrade(S.vl, geo(S.vl, S.A));
        if (CL_RANK[cl] >= CL_RANK['3']) { flash('warn', T('f_noview', 'You cannot see the cords yet — lift more.')); return; }
        this.lock(cl);
      },
      down(btn, x, y) { if (btn === 0) ptr = { btn, x0: x, y0: y }; },
      move() { },
      burp: true,
    },

    /* 6 · pass the tube */
    6: {
      enter() {
        show('scope');
        const tb = S.tube; tb.show = true; tb.ax = clamp(mouse.x, 0.1, 0.9); tb.ay = clamp(mouse.y, 0.1, 0.9);
        setPanel({
          title: Tf('s6_title', 'Pass the tube %s', S.A.tube),
          text: Tf('s6_text', 'Aim the tip between the **vocal cords** and hold {Click} to push. Stop at **%s cm** at the teeth, then press {Enter}.', S.A.depth),
          tools: tools('4', ['1', '2', S.suc.done || S.suc.skipped ? '3' : '']),
          hints: [H(['Click'], T('h_push', 'push (hold)')), H(['Right click'], T('h_pull', 'pull back')), H(['E'], T('h_burp', 'BURP (hold)')), H(['Enter'], T('h_confirm', 'confirm'))],
        });
      },
      tick(dt) {
        const tb = S.tube, v = S.vl;
        v.expo += ((v.locked ? v.locked.expo : 0.5) + (v.burp ? 0.12 : 0) - v.expo) * Math.min(1, dt * 5);
        if (!tb.placed) { tb.ax += (clamp(mouse.x, 0.05, 0.95) - tb.ax) * Math.min(1, dt * 9); tb.ay += (clamp(mouse.y, 0.05, 0.95) - tb.ay) * Math.min(1, dt * 9); }
        const before = tb.pr;
        if (tb.push || held.KeyW || held.ArrowUp) tb.pr = Math.min(1, tb.pr + dt * 0.19);
        if (tb.pull || held.KeyS || held.ArrowDown) tb.pr = Math.max(0, tb.pr - dt * 0.26);
        if (before < PLANE && tb.pr >= PLANE && !tb.placed) {
          const { W, H: hh } = UI.scope.size();
          const sp = toScene(tb.ax, tb.ay, W, hh, v.steer);
          const kind = classify(sp[0], sp[1], S.A, geo(v, S.A));
          if (kind === 'trachea' || kind === 'oesophagus') {
            tb.placed = kind;
            if (snd()) NZA.audio.tone(240, 70, { vol: 0.05, type: 'sine' });
          } else {
            tb.pr = PLANE - 0.12; tb.hits++; S.firstPass = false;
            if (snd()) NZA.audio.tone(85, 160, { vol: 0.12, type: 'sine' });
            flash('warn', kind === 'epiglottis' ? T('f_hit_epi', 'The epiglottis is in the way — lift more or hold {E} for BURP.')
              : kind === 'cords' ? T('f_hit_cords', 'Resistance — you are on the cords. Aim for the middle of the gap.')
                : kind === 'arytenoid' ? T('f_hit_ary', 'You are on the arytenoids — aim higher, between the cords.')
                  : T('f_hit', 'Resistance — re-aim between the cords.'), 2400);
          }
        }
        if (tb.placed && tb.pr < PLANE - 0.02) tb.placed = null;
      },
      wide() {
        const cm = tubeCm(), t = S.A.depth;
        const ok = S.tube.placed && Math.abs(cm - t) <= 1;
        return { label: T('w_depth', 'Tube depth'), value: cm.toFixed(0), unit: T('u_cm_teeth', 'cm at the teeth'), meter: { value: cm / CM_FULL, zone: [(t - 1) / CM_FULL, (t + 1) / CM_FULL] },
          caption: !S.tube.placed ? (S.tube.pr < 0.05 ? T('c_aim', 'Aim, then push') : T('c_through', 'Through the cords…')) : cm > t + 2 ? T('c_tdeep', 'Too deep — pull back') : ok ? T('c_tok', 'Depth correct — press Enter') : T('c_tpush', 'Keep pushing'), captionTone: ok ? 'teal' : cm > t + 2 ? 'red' : '' };
      },
      enterKey() {
        if (!S.tube.placed) { flash('warn', T('f_pass_first', 'Pass the tube through the cords first.')); return; }
        if (tubeCm() < 17) { flash('warn', Tf('f_push_more', 'Push the tube further — %s cm at the teeth.', S.A.depth)); return; }
        goStep(7);
      },
      down(btn) { if (btn === 0) S.tube.push = true; if (btn === 2) S.tube.pull = true; },
      burp: true,
    },

    /* 7 · cuff */
    7: {
      enter() {
        show('cuff');
        S.tube.inflated = false;
        setPanel({
          title: T('s7_title', 'Inflate the cuff'),
          text: T('s7_text', 'Hold {Space} or {Click} the syringe to fill the cuff until the gauge sits at **20–30 cmH₂O**. {Right click} lets air out. Press {Enter} when it holds.'),
          tools: tools('5', ['1', '2', '3', '4']),
          hints: [H(['Space'], T('h_inflate', 'inflate (hold)')), H(['Backspace'], T('h_deflate', 'deflate')), H(['Enter'], T('h_confirm', 'confirm'))],
        });
      },
      tick(dt) {
        const c = S.cuff;
        const dir = c.inj || (held[' '] ? 1 : held.Backspace ? -1 : 0);
        if (dir) {
          c.ml = clamp(c.ml + dir * 2.4 * dt, 0, 10);
          if (now() - c.tickT > 260 && snd()) { c.tickT = now(); NZA.audio.tone(dir > 0 ? 900 : 600, 18, { vol: 0.03, type: 'triangle' }); }
        }
        c.p = cuffPressure(c.ml);
        c.leak = c.p < 18 || tubeCm() < S.A.depth - 3;
        S.tube.inflated = c.ml > 3;
        UI.cuff.set({ ml: c.ml, p: c.p, leak: c.leak });
      },
      wide() {
        const p = S.cuff.p, b = S.cfg.band;
        const ok = p >= b[0] && p <= b[1];
        return { label: T('w_cuff', 'Cuff'), value: Math.round(p), unit: 'cmH₂O', meter: { value: clamp(p / 60, 0, 1), zone: [b[0] / 60, b[1] / 60], tone: p > b[1] ? 'red' : '' },
          caption: ok ? T('c_cuff_ok', 'Sealed — press Enter') : p > b[1] ? T('c_cuff_hi', 'Too high — let some air out') : T('c_cuff_lo', 'Under-filled — the tube will leak'), captionTone: ok ? 'teal' : p > b[1] ? 'red' : '' };
      },
      enterKey() {
        const p = S.cuff.p, b = S.cfg.band;
        if (p < b[0] - 6) { flash('warn', T('f_cuff_lo', 'The cuff is nearly empty — fill it first.')); return; }
        if (p > b[1] + 10) { flash('bad', T('f_cuff_hi', 'Far too much pressure — it will damage the trachea.')); return; }
        S.cuffDone = { ml: S.cuff.ml, p };
        goStep(8);
      },
      squeezeKeyIsCuff: true,
    },

    /* 8 · confirm & secure */
    8: {
      enter() {
        show('conf');
        S.bag.reset();
        setPanel({
          title: T('s8_title', 'Confirm & secure'),
          text: T('s8_text', 'Squeeze the bag {Space} and watch the **capnography**. Click the chest to listen both sides and over the stomach. {F} secures the tube, {X} pulls it out.'),
          tools: tools('1', ['2', '3', '4', '5']),
          hints: [H(['Space'], T('h_squeeze', 'squeeze')), H(['W', 'S'], T('h_depth', '±1 cm')), H(['F'], T('h_secure', 'secure')), H(['X'], T('h_pulltube', 'pull tube'))],
        });
        UI.conf.spot(null, S.conf.res);
        UI.conf.nums({ et: 0, rr: 0, msg: T('cap_wait', 'Ventilate to see the trace'), tone: '' });
      },
      spot(s) { S.conf.spot = S.conf.spot === s ? null : s; UI.conf.spot(S.conf.spot, S.conf.res); },
      breath(b) {
        const r = deliverBreath(b, 'tube');
        const c = S.conf;
        c.breaths++;
        UI.conf.breath(r.et, clamp(b.hold * 1.6, 0.6, 2.4));
        if (r.eff > 0.15 && S.attemptOn) { S.attemptOn = false; S.attemptOk = true; }
        if (r.et >= 25) c.capno++;
        c.lastEt = r.et;
        const pl = S.tube.placed, cm = tubeCm(), mainstem = pl === 'trachea' && cm > S.A.depth + 2;
        const leak = S.cuff.leak;
        if (c.spot) {
          const sp = c.spot;
          let amp = 0, res;
          if (pl === 'trachea') {
            if (sp === 'epi') { res = { label: T('ausc_silent', 'Silent'), tone: 'ok' }; amp = 0.05; }
            else if (sp === 'l' && mainstem) { res = { label: T('ausc_quiet', 'Quiet'), tone: 'warn' }; amp = 0.15; }
            else { res = { label: T('ausc_breath', 'Breath sounds'), tone: 'ok' }; amp = 1; }
          } else if (sp === 'epi') { res = { label: T('ausc_gurgle', 'Gurgling'), tone: 'bad' }; amp = 1; }
          else { res = { label: T('ausc_faint', 'Faint'), tone: 'warn' }; amp = 0.18; }
          c.res[sp] = res; c.listened[sp] = true;
          UI.conf.spot(c.spot, c.res);
          if (snd()) {
            if (pl !== 'trachea' && sp === 'epi') [0, 0.18, 0.31, 0.5].forEach(a => NZA.audio.noise(140, { vol: 0.09, lp: 320, hp: 60, at: a, attack: 0.2, release: 0.5 }));
            else NZA.audio.noise(950, { vol: 0.16 * amp, lp: 700, hp: 120, attack: 0.35, release: 0.45 });
          }
        }
        if (leak && snd()) NZA.audio.noise(500, { vol: 0.05, lp: 2400, hp: 900, attack: 0.3, release: 0.4 });
        if (leak && c.breaths === 1) flash('warn', T('f_leak', 'Air is hissing out at the mouth — the cuff leaks.'), 2600);
        if (b.short) flash('bad', T('br_short', 'Too short — the chest did not rise'), 1400);
      },
      tick() {
        const c = S.conf;
        const et = S.etco2;
        const msg = c.breaths === 0 ? T('cap_wait', 'Ventilate to see the trace') : et >= 25 ? T('cap_ok', 'Waveform present') : et > 0 ? T('cap_low', 'Low trace') : T('cap_none', 'No CO₂ trace');
        UI.conf.nums({ et, rr: S.rr, msg, tone: c.breaths === 0 ? '' : et >= 25 ? 'teal' : 'red' });
      },
      wide() {
        const et = S.etco2;
        return { label: 'EtCO₂', value: et > 0 ? Math.round(et) : '--', unit: 'mmHg', meter: { value: clamp(et / 60, 0, 1), zone: [35 / 60, 45 / 60] },
          caption: Tf('c_depth8', 'Tube at %s cm · cuff %s cmH₂O', tubeCm().toFixed(0), Math.round(S.cuff.p)), captionTone: '' };
      },
      depth(d) {
        S.tube.pr = clamp(S.tube.pr + d / CM_FULL, 0, 1);
        S.cuff.p = cuffPressure(S.cuff.ml); S.cuff.leak = S.cuff.p < 18 || tubeCm() < S.A.depth - 3;
        S.conf.res = {}; UI.conf.spot(S.conf.spot, S.conf.res);
        if (tubeCm() < 15) { flash('bad', T('f_out', 'The tube came out.')); abortAttempt('out'); return; }
        flash('ok', Tf('f_depth', 'Tube at %s cm at the teeth.', tubeCm().toFixed(0)), 1200);
      },
      secure() {
        if (S.conf.breaths < 1) { flash('warn', T('f_vent_first', 'Ventilate and check the tube before you secure it.')); return; }
        S.conf.secured = true;
        if (snd()) NZA.audio.success();
        finishIntubation();
      },
      pull() {
        if (S.tube.placed === 'oesophagus') { S.detected = true; abortAttempt('pulled'); }
        else { S.wrongPull++; abortAttempt('wrongpull'); }
      },
      enterKey() { flash('warn', T('f_secure_key', 'Press F to secure the tube or X to pull it.')); },
      squeeze: true,
    },

    /* B · standalone bag-valve-mask round */
    B: {
      enter() {
        show('vent');
        if (S.A.intubated) { S.tube.placed = S.A.misplaced ? 'oesophagus' : 'trachea'; S.tube.pr = S.A.depth / CM_FULL; S.cuff.p = 24; S.cuff.leak = false; }
        UI.vent.title(S.A.intubated ? T('vent_tube', 'Bag on the endotracheal tube') : T('vent_mask', 'Face mask · two-hand seal'), T('vent_o2', '15 L/min O₂'));
        UI.vent.stats({ breaths: `0/${S.cfg.bvmBreaths}`, interval: '--', vol: '--' }); UI.vent.hist([]); UI.vent.gastric(S.gastric);
        setPanel({
          title: T('sb_title', 'Ventilate'),
          text: S.A.intubated ? Tf('sb_text_tube', 'Breathe through the tube: a smooth {Space} squeeze of about a second, one breath every %s s. Watch the chest rise and the CO₂ trace.', S.cfg.cadence)
            : Tf('sb_text', 'Seal the mask and give a smooth {Space} squeeze of about a second, one breath every %s s. Watch the chest rise and the SpO₂.', S.cfg.cadence),
          tools: tools('1'),
          hints: [H(['Space'], T('h_squeeze', 'squeeze'))],
        });
      },
      breath(b) {
        const r = deliverBreath(b, S.A.intubated ? 'tube' : 'mask');
        S.bvm.n++; S.bvm.q.push(r.eff > 0.15 ? b.q : b.q * 0.3); if (b.q >= 0.6 && r.eff > 0.15) S.bvm.good++;
        S.pre.hist.push(b);
        UI.vent.hist(S.pre.hist);
        UI.vent.stats({ breaths: `${S.bvm.n}/${S.cfg.bvmBreaths}`, interval: b.first ? '--' : `${b.interval.toFixed(1)} s`, vol: `${b.vol} ml` });
        UI.vent.gastric(S.gastric);
        const m = r.eff <= 0.15 && S.A.intubated ? ['bad', T('br_noco2', 'No chest rise and no CO₂ — check the tube')] : breathMsg(b);
        flash(m[0], m[1], 1800);
        if (S.bvm.n >= S.cfg.bvmBreaths) setTimeout(() => { if (S && !S.done) finishBvm(); }, 700);
      },
      tick() { ventTick(); },
      wide() {
        return { label: 'EtCO₂', value: S.etco2 > 0 ? Math.round(S.etco2) : '--', unit: 'mmHg', meter: { value: clamp(S.etco2 / 60, 0, 1), zone: [35 / 60, 45 / 60] },
          caption: Tf('c_gastric', 'Stomach air %s%', Math.round(S.gastric)), captionTone: S.gastric > 45 ? 'red' : '' };
      },
      enterKey() { },
      squeeze: true,
    },
  };
  function clCaption(cl) {
    return cl === '1' ? T('cl_1', 'Whole glottis visible') : cl === '2a' ? T('cl_2a', 'Most of the cords visible') : cl === '2b' ? T('cl_2b', 'Only the back of the cords')
      : cl === '3' ? T('cl_3', 'Epiglottis only — lift more') : T('cl_4', 'No laryngeal view');
  }

  /* ═══════════════════════════ RESULTS ═══════════════════════════ */
  const gradeOf = sc => (sc >= 95 ? 'S' : sc >= 85 ? 'A' : sc >= 72 ? 'B' : sc >= 58 ? 'C' : sc >= 40 ? 'D' : 'F');
  const mean = a => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);

  function complete(card, title, text, tone) {
    S.done = true; release();
    show('res');
    UI.res = ResultCard(UI.dockR, card);
    UI.pp.complete({ title, text, label: T('done', 'Done'), onDone: sendResult });
    if (tone === 'bad') UI.pp.set({ titleTone: 'bad' });
    UI.pp.set({ stats: statList(), wide: null, hints: [], abort: false });
    NZA.post(`${APP}:step`, { step: S.mode === 'bvm' ? 1 : 8, phase: 'done', placed: S.result.placed || null });
  }

  function finishIntubation() {
    const placed = S.tube.placed || 'none';
    const cm = Math.round(tubeCm());
    const mainstem = placed === 'trachea' && cm > S.A.depth + 2;
    const p = S.cuff.p, band = S.cfg.band, inBand = p >= band[0] && p <= band[1];
    const c = S.conf;
    const clL = S.vl.locked ? S.vl.locked.cl : S.clBest;
    const best = STEPS[5].best();
    let sc = 15 * (S.preScore !== null && S.preScore !== undefined ? S.preScore : 0.5);
    sc += 10 * (S.pos.score || 0);
    sc += S.suc.soiled ? 10 * (1 - (S.suc.left || 0)) : 10;
    sc += clamp(20 - Math.max(0, CL_RANK[clL] - CL_RANK[best]) * 5 - S.teeth * 5, 0, 20);
    sc += clamp(20 * (S.firstPass ? 1 : 0.7) - S.tube.hits * 3 - Math.max(0, Math.abs(cm - S.A.depth) - 1) * 3 - (mainstem ? 6 : 0), 0, 20);
    sc += inBand ? 10 : clamp(10 - Math.min(Math.abs(p - band[0]), Math.abs(p - band[1])) * 0.6, 0, 10);
    sc += (c.capno >= 3 ? 6 : c.capno > 0 ? 3 : 0) + (c.listened.l && c.listened.r ? 4 : (c.listened.l || c.listened.r) ? 2 : 0) + (c.listened.epi ? 2 : 0) + 3;
    sc -= S.attemptsUsed * 12 + Math.max(0, Math.min(90, S.spo2Start) - S.low) * 1.2 + S.crashes * 8 + S.wrongPull * 10;
    if (S.detected) sc += 4;
    if (placed === 'oesophagus') sc = Math.min(sc, 20);
    sc = clamp(Math.round(sc), 0, 100);
    const grade = gradeOf(sc);
    const elapsed = Math.round((now() - S.t0) / 1000);
    S.result = {
      mode: 'intubate', score: sc, grade, placed, depth: cm, mainstem, cuff: Math.round(p), cuffMl: Math.round(S.cuff.ml * 10) / 10, leak: !!S.cuff.leak,
      capno: c.capno >= 3, capnoBreaths: c.capno, ventilated: c.breaths, listened: Object.assign({}, c.listened), secured: true,
      attempts: S.attemptNo, failed: false, detected: S.detected, teeth: S.teeth, cl: clL, firstPass: S.firstPass, hits: S.tube.hits,
      lowSpo2: Math.round(S.low), endSpo2: Math.round(S.spo2), suction: S.suc.soiled ? (S.suc.done ? 'cleared' : 'partial') : 'clear',
      positioned: S.pos.done, preox: Math.round((S.preScore || 0) * 100), gastric: Math.round(S.gastric), elapsed,
    };
    const notes = [];
    if (placed === 'oesophagus' && c.breaths) notes.push([T('n_nocapno', 'There was no CO₂ trace — the tube may not be in the trachea.'), 'bad']);
    else if (c.capno < 3) notes.push([T('n_capno', 'Always confirm the tube with a capnography waveform.'), 'warn']);
    if (!(c.listened.l && c.listened.r)) notes.push([T('n_listen', 'Listen to both sides of the chest.'), 'warn']);
    if (mainstem) notes.push([T('n_mainstem', 'The tube is too deep — only one lung is ventilated.'), 'bad']);
    if (S.teeth) notes.push([Tf('n_teeth', 'You levered on the teeth %s×.', S.teeth), 'bad']);
    if (S.low < 90) notes.push([Tf('n_low', 'The patient dropped to %s% — pre-oxygenate better or abort earlier.', Math.round(S.low)), 'warn']);
    if (!inBand) notes.push([T('n_cuff', 'Keep the cuff between 20 and 30 cmH₂O.'), 'warn']);
    if (!notes.length) notes.push([T('n_great', 'Clean, confirmed first-pass intubation.'), 'ok']);
    const card = {
      grade, score: sc, kicker: T('res_kicker', 'Intubation'), title: placed === 'trachea' ? T('res_secured', 'Airway secured') : T('res_tube', 'Tube secured'),
      tone: placed === 'trachea' ? 'ok' : '', sub: `${S.patient.name || ''} · ${S.A.tube} ETT`,
      rows: [
        [T('r_view', 'Best view'), `CL ${clL}`, CL_RANK[clL] <= 1 ? 't-teal' : CL_RANK[clL] >= 3 ? 't-red' : 't-amber'],
        [T('r_attempts', 'Attempts'), `${S.attemptNo}/${S.cfg.attempts}${S.firstPass ? ` · ${T('r_first', 'first pass')}` : ''}`, S.attemptNo === 1 ? 't-teal' : 't-amber'],
        [T('r_tube', 'Tube'), Tf('r_tube_v', '%s at %s cm', S.A.tube, cm), Math.abs(cm - S.A.depth) <= 1 ? 't-teal' : 't-amber'],
        [T('r_cuff', 'Cuff'), `${Math.round(p)} cmH₂O`, inBand ? 't-teal' : 't-amber'],
        [T('r_capno', 'Capnography'), c.capno >= 3 ? T('r_capno_ok', 'Waveform confirmed') : c.breaths ? T('r_capno_none', 'No waveform') : T('r_capno_skip', 'Not checked'), c.capno >= 3 ? 't-teal' : 't-red'],
        [T('r_low', 'Lowest SpO₂'), `${Math.round(S.low)}%`, S.low < 90 ? 't-red' : S.low < 94 ? 't-amber' : 't-teal'],
        [T('r_time', 'Time'), tfmt(elapsed), ''],
      ],
      notes: notes.slice(0, 4),
    };
    complete(card, card.title, Tf('pp_done', 'Grade %s · press Enter to finish.', grade), '');
  }

  function failAirway() {
    const sc = clamp(Math.round(6 + 9 * (S.preScore || 0)), 0, 15);
    const grade = gradeOf(sc);
    S.tube.placed = null;
    S.result = {
      mode: 'intubate', score: sc, grade, placed: 'none', failed: true, attempts: S.attemptNo, detected: S.detected, teeth: S.teeth, cl: S.clBest,
      lowSpo2: Math.round(S.low), endSpo2: Math.round(S.spo2), firstPass: false, hits: S.tube.hits, gastric: Math.round(S.gastric), elapsed: Math.round((now() - S.t0) / 1000),
      capno: false, secured: false, depth: 0, cuff: 0,
    };
    const card = {
      grade, score: sc, kicker: T('res_kicker', 'Intubation'), title: T('res_failed', 'Failed airway'), tone: 'bad', sub: `${S.patient.name || ''}`,
      rows: [[T('r_attempts', 'Attempts'), `${S.attemptNo}/${S.cfg.attempts}`, 't-red'], [T('r_view', 'Best view'), `CL ${S.clBest}`, ''], [T('r_low', 'Lowest SpO₂'), `${Math.round(S.low)}%`, S.low < 90 ? 't-red' : '']],
      notes: [[T('n_failed', 'Keep bagging with the mask and get help.'), 'warn']],
    };
    complete(card, T('res_failed', 'Failed airway'), T('pp_failed', 'All attempts used. Keep the patient oxygenated with the bag.'), 'bad');
  }

  function finishBvm() {
    const avgQ = mean(S.bvm.q);
    const sc = clamp(Math.round(avgQ * 80 + 20 - Math.max(0, S.gastric - 30) * 0.5 - Math.max(0, Math.min(90, S.spo2Start) - S.low)), 0, 100);
    const grade = gradeOf(sc);
    const ineffective = S.A.intubated && S.A.misplaced;
    S.result = {
      mode: 'bvm', score: sc, grade, breaths: S.bvm.n, good: S.bvm.good, quality: Math.round(avgQ * 100), gastric: Math.round(S.gastric),
      lowSpo2: Math.round(S.low), endSpo2: Math.round(S.spo2), capno: S.etco2 >= 25, intubated: S.A.intubated, ineffective, elapsed: Math.round((now() - S.t0) / 1000),
    };
    const notes = [];
    if (ineffective) notes.push([T('n_bvm_tube', 'No chest rise and no CO₂ through the tube — check where it is.'), 'bad']);
    if (S.gastric > 45) notes.push([T('n_gastric', 'Too much air went into the stomach — squeeze gently, 1 s.'), 'warn']);
    if (avgQ < 0.6) notes.push([Tf('n_rhythm', 'Keep one breath every %s seconds.', S.cfg.cadence), 'warn']);
    if (!notes.length) notes.push([T('n_bvm_good', 'Steady, gentle breaths — well done.'), 'ok']);
    const card = {
      grade, score: sc, kicker: T('res_kicker_bvm', 'Ventilation'), title: ineffective ? T('res_bvm_bad', 'No air entry') : T('res_bvm', 'Round complete'), tone: ineffective ? 'bad' : 'ok',
      sub: `${S.patient.name || ''}`,
      rows: [
        [T('r_breaths', 'Breaths'), `${S.bvm.good}/${S.bvm.n} ${T('r_good', 'good')}`, S.bvm.good >= S.bvm.n * 0.75 ? 't-teal' : 't-amber'],
        [T('r_spo2', 'SpO₂ now'), `${Math.round(S.spo2Disp)}%`, S.spo2Disp >= 94 ? 't-teal' : S.spo2Disp >= 90 ? 't-amber' : 't-red'],
        [T('r_gastric', 'Stomach air'), `${Math.round(S.gastric)}%`, S.gastric > 45 ? 't-red' : ''],
        [T('r_rate', 'Rate'), `${S.rr || 0}/min`, ''],
      ],
      notes,
    };
    complete(card, card.title, Tf('pp_done', 'Grade %s · press Enter to finish.', grade), ineffective ? 'bad' : '');
  }

  function sendResult() {
    if (!S || S.sent || !S.result) return;
    S.sent = true;
    Promise.resolve(NZA.post(`${APP}:finish`, { result: S.result })).then(() => { if (!NZA.inGame) NZA.close(APP); });
  }
  function abortProc() {
    if (!S || S.sent) return;
    if (S.done && S.result) { sendResult(); return; }   // finished: leaving keeps the result
    S.sent = true;
    Promise.resolve(NZA.post(`${APP}:abort`, {})).then(() => { if (!NZA.inGame) NZA.close(APP); });
  }
  function toolInfo(k) {
    if (!S || S.done) return;
    const def = tools().find(t => t.key === k);
    if (!def) return;
    if (def.state === 'active') flash('ok', Tf('f_inuse', '%s — in use.', def.label), 1200);
    else if (def.state === 'done') flash('ok', Tf('f_used', '%s — done.', def.label), 1200);
    else flash('warn', Tf('f_notyet', '%s is not needed yet.', def.label), 1400);
  }

  /* ═══════════════════════════ FRAME LOOP ═══════════════════════════ */
  function scopeFrame(dt) {
    const v = S.vl;
    const st = STEPS[S.step];
    const sucKey = !S.done && S.step >= 4 && S.step <= 6 && (held['3'] || held.KeyQ);
    if (sucKey) {
      S.soil.suck(mouse.x, mouse.y, 0.15);
      if (now() - S.suc.sndAt > 230 && snd()) { S.suc.sndAt = now(); NZA.audio.noise(260, { vol: 0.05, lp: 1200, hp: 300, attack: 0.1, release: 0.3 }); }
    }
    if (!S.done && S.step >= 4 && S.step <= 6) S.soil.refill(dt * S.A.bleed);
    v.burp = !!(held.KeyE && st && st.burp);
    S.power = Math.min(1, (S.power || 0) + dt * 2.2);
    const cov = S.soil.coverage();
    if (S.step === 4 && v.depth > 0.35 && cov > 0.3 && ptr) S.smear = Math.min(0.75, (S.smear || 0) + dt * 0.12 * cov);
    S.smear = Math.max(0, (S.smear || 0) - dt * 0.04);
    const g = geo(v, S.A);
    const inV = v.depth >= 0.93 && v.depth <= 1.07 && Math.abs(v.steer) < 0.16;
    const fl = FLUID[S.A.soilKind] || FLUID.blood;
    const showSuc = S.step === 3 || sucKey;
    UI.scope.render({
      st: v, A: S.A, g, time: S.time, soil: S.soil.canvas, soilDirty: S.soil.take(), fluid: fl, fluidOn: 1,
      redout: sstep(1.16, 1.32, v.depth), smear: S.smear, power: S.power,
      tube: S.step === 6 ? S.tube : null,
      suction: { show: showSuc, on: S.suc.on || sucKey, x: mouse.x, y: mouse.y, fluid: S.suc.on || sucKey, color: `rgb(${fl.map(c => Math.round(c * 255)).join(',')})` },
      marker: S.step === 4 && v.depth > 0.72 && v.depth < 1.16 ? { label: T('osd_vall', 'Vallecula'), ok: inV } : null,
    });
    const cl = clGrade(v, g);
    const clTone = CL_RANK[cl] <= 1 ? 'teal' : CL_RANK[cl] === 2 ? 'amber' : 'red';
    let gauge = null, msg = '', msgTone = '';
    if (S.step === 3) gauge = { label: T('osd_soil', 'SOIL'), value: clamp(cov / Math.max(S.suc.c0, 0.02), 0, 1), zone: [0, 0.06], text: `${Math.round(clamp(cov / Math.max(S.suc.c0, 0.02), 0, 1) * 100)}%`, bad: cov > 0.05 };
    if (S.step === 4) {
      gauge = { label: T('osd_depth', 'DEPTH'), value: v.depth / 1.3, zone: [0.93 / 1.3, 1.07 / 1.3], text: `${Math.round(v.depth * 100)}%`, ok: inV, bad: v.depth > 1.12 };
      if (v.depth > 1.25) { msg = T('osd_oes', 'OESOPHAGUS — PULL BACK'); msgTone = 'red'; }
      else if (v.depth > 1.12) { msg = T('osd_deep', 'TOO DEEP — PULL BACK'); msgTone = 'red'; }
      else if (Math.abs(v.steer) > 0.2) { msg = T('osd_mid', 'TONGUE — STAY MIDLINE'); msgTone = 'amber'; }
    }
    if (S.step === 5) {
      gauge = { label: T('osd_lift', 'LIFT'), value: v.lift / 1.25, zone: [0.6 / 1.25, 1.0 / 1.25], text: `${Math.round(v.lift * 100)}%`, bad: v.lever > 0.35 };
      if (v.lever > 0.35) { msg = T('osd_teeth', 'TEETH — LIFT, DON\'T LEVER'); msgTone = 'red'; }
      else if (v.burp) { msg = 'BURP'; msgTone = 'teal'; }
    }
    if (S.step === 6) {
      const cm = tubeCm();
      gauge = { label: T('osd_tube', 'TUBE'), value: cm / CM_FULL, zone: [(S.A.depth - 1) / CM_FULL, (S.A.depth + 1) / CM_FULL], text: `${Math.round(cm)} cm`, ok: S.tube.placed && Math.abs(cm - S.A.depth) <= 1, bad: cm > S.A.depth + 2 };
      if (v.burp) { msg = 'BURP'; msgTone = 'teal'; }
    }
    if (sucKey) { msg = T('osd_suction', 'SUCTION'); msgTone = 'teal'; }
    UI.scope.hud({
      tl: Tf('osd_attempt', 'ATTEMPT %s/%s', Math.max(1, S.attemptNo), S.cfg.attempts),
      rec: S.attemptOn ? tfmt((now() - S.attemptT0) / 1000) : '--:--',
      cl: S.step >= 4 && v.depth > 0.6 ? `CL ${cl}` : 'CL —', clTone: S.step >= 4 && v.depth > 0.6 ? clTone : '',
      gauge, msg, msgTone,
      guide: S.step === 5 && !S.done ? { label: T('osd_liftdir', 'LIFT'), on: !!ptr } : null,
      foot: `<kbd>B</kbd> ${esc(T('h_abort_att', 'abort attempt'))}`,
    });
  }

  function ancFrame() {
    if (!UI || !UI.anc) return;
    const on = !!S && !S.done && (S.step === 1 || S.step === 'B');
    let a = null;
    if (on) a = UI.anchors.get('bvm') || UI.anchors.get('mouth') || (NZA.inGame ? null : { x: 0.555, y: 0.43 });
    const vis = on && a && a.visible !== false;
    if (!vis) { UI.anc.classList.remove('on'); return; }
    UI.anc.style.left = `${(a.x * 100).toFixed(2)}%`; UI.anc.style.top = `${(a.y * 100).toFixed(2)}%`;
    const bag = S.bag, started = bag.count > 0;
    const ph = started ? Math.min(1, bag.phase()) : 1;
    UI.anc.querySelector('.p').setAttribute('stroke-dasharray', `${(ph * 119.4).toFixed(1)} 119.4`);
    const rem = S.cfg.cadence * (1 - (started ? bag.phase() : 1));
    let txt, tone;
    if (bag.holding) { const h = bag.holdSec(); txt = Tf('anc_hold', 'Squeezing %s s', h.toFixed(1)); tone = h > S.cfg.ideal + 0.35 ? 'amber' : 'sq'; }
    else if (!started || rem <= 0.5) { txt = rem < -0.6 ? T('anc_late', 'Squeeze — late') : T('anc_now', 'Squeeze now'); tone = rem < -0.6 ? 'amber' : 'now'; }
    else { txt = Tf('anc_next', 'Next breath %s s', rem.toFixed(1)); tone = ''; }
    const b = UI.anc.querySelector('.chip b');
    if (b.textContent !== txt) b.textContent = txt;
    UI.anc.className = `itb-anc on ${tone}`;
  }

  function slowUi() {
    updateStats();
    if (S.step === 2 && UI.sagp) UI.sagp.update();
    if (!S.done && S.mode === 'intubate' && S.attemptOn) {
      if (S.spo2Disp < S.cfg.crash) {
        flash('bad', T('f_crash', 'Critical desaturation — the attempt was abandoned. Bag the patient back up.'), 5000);
        if (S.step === 8 && S.tube.placed === 'oesophagus') S.detected = true;
        abortAttempt('crash');
        return;
      }
      if (S.spo2Disp < S.cfg.abort) {
        if (!S.warned) { S.warned = true; flash('bad', Tf('f_desat', 'SpO₂ under %s% — stop and re-oxygenate {B}', S.cfg.abort), 0); }
        if (now() - S.alarmAt > 3200 && snd()) { S.alarmAt = now(); NZA.audio.alarm(2); }
      } else if (S.warned) { S.warned = false; flash('ok', '', 1); }
    }
    if (UI.mon) {
      const since = S.lastGood ? (now() - S.lastGood) / 1000 : -1;
      const ventOk = since >= 0 && since < S.cfg.cadence * 1.7;
      UI.mon.update({ hr: S.hr, spo2: S.spo2Disp, sys: S.vit.sys, dia: S.vit.dia, map: S.vit.map, rr: S.rr, temp: S.vit.temp, etco2: S.etco2, rhythm: S.vit.rhythm, trend: S.trend, low: S.low,
        etco2Alarm: S.step === 8 && S.conf.breaths > 1 && S.etco2 < 10 });
      let status = T('mon_monitoring', 'MONITORING'), tone = '';
      if (S.spo2Disp < S.cfg.abort) { status = T('mon_lowsat', 'LOW SpO₂'); tone = 'red'; }
      else if (S.trend < -0.05 && S.spo2Disp < 96) { status = T('mon_falling', 'SAT FALLING'); tone = 'amber'; }
      else if (S.attemptOn || (!ventOk && S.A.apnoeic)) { status = T('mon_apnoeic', 'APNOEIC'); tone = 'amber'; }
      else if (ventOk) { status = T('mon_vent', 'VENTILATING'); tone = 'teal'; }
      UI.mon.status(status, tone);
      const apSec = S.attemptOn ? (now() - S.attemptT0) / 1000 : (ventOk ? -1 : since);
      UI.mon.foot({ apnoea: apSec >= 0 ? tfmt(apSec) : '--:--', apFrac: apSec >= 0 ? apSec / Math.max(15, S.A.safe) : 0, apTone: apSec > 30 ? 'red' : apSec > 15 ? 'amber' : '',
        attempt: S.attemptNo, max: S.cfg.attempts, used: S.attemptsUsed });
    }
  }

  function frame(t) {
    if (!S) return;
    raf = requestAnimationFrame(frame);
    const dt = clamp((t - lastT) / 1000, 0, 0.1); lastT = t;
    S.time += dt;
    if (!S.done) { sim(dt); const st = STEPS[S.step]; if (st && st.tick) st.tick(dt); }
    if (!S) return;
    if (UI.scope) scopeFrame(dt);
    if (UI.sagm) UI.sagm.update();
    if (UI.conf) UI.conf.frame();
    ancFrame();
    uiT += dt;
    if (uiT >= 0.25) { uiT = 0; slowUi(); }
  }

  /* ═══════════════════════════ INPUT ═══════════════════════════ */
  const HOLD_KEYS = new Set([' ', 'KeyW', 'KeyS', 'KeyA', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'KeyQ', '3', 'KeyE', 'Backspace']);
  function onKey(k, down, e) {
    if (!S) return false;
    if (S.done) { if (down && k === 'Enter' && !e.repeat) UI.pp.key(e); return true; }
    if (down && e.repeat) return true;
    if (HOLD_KEYS.has(k)) held[k] = down;
    const st = STEPS[S.step];
    if (!st) return true;
    if (k === ' ') { if (st.squeeze) { if (down) S.bag.down(); else S.bag.up(); } return true; }
    if (!down) return true;
    switch (k) {
      case 'Enter': if (st.enterKey) st.enterKey(); return true;
      case 'KeyB':
        if (S.attemptOn) { if (S.step === 8 && S.tube.placed === 'oesophagus') S.detected = true; abortAttempt('manual'); }
        return true;
      case 'KeyE':
        if (st.burp && !S.burpTold) { S.burpTold = true; flash('ok', T('f_burp', 'BURP — your assistant presses the larynx back, up and to the right.'), 2000); }
        return true;
      case 'KeyT': if (S.step === 2) STEPS[2].towel(!S.pos.towel); return true;
      case 'KeyF': if (S.step === 8) STEPS[8].secure(); return true;
      case 'KeyX': if (S.step === 8) STEPS[8].pull(); return true;
      case 'KeyW': case 'ArrowUp': if (S.step === 8) STEPS[8].depth(1); return true;
      case 'KeyS': case 'ArrowDown': if (S.step === 8) STEPS[8].depth(-1); return true;
      case '1': case '2': case '4': case '5': case '6': toolInfo(k); return true;
      case '3': if (!(S.step >= 4 && S.step <= 6)) toolInfo(k); return true;
      default: return true;
    }
  }
  function onDown(e) {
    if (!S || S.done || !UI) return;
    if (UI.scope && UI.scope.screen.contains(e.target)) {
      const r = UI.scope.rel(e); mouse.x = r[0]; mouse.y = r[1];
      const st = STEPS[S.step];
      if (st && st.down) { e.preventDefault(); st.down(e.button, r[0], r[1]); }
    }
  }
  function onMove(e) {
    if (!S || !UI || !UI.scope) return;
    const r = UI.scope.rel(e); mouse.x = r[0]; mouse.y = r[1];
    const st = STEPS[S.step];
    if (ptr && st && st.move) st.move(r[0], r[1]);
  }
  function onUp() {
    if (!S) return;
    ptr = null; S.suc.on = false; S.tube.push = false; S.tube.pull = false; S.cuff.inj = 0;
  }

  /* ═══════════════════════════ APP ═══════════════════════════ */
  function build(d) {
    const root = el('div', 'itb');
    appDef.el.appendChild(root);
    UI = { root, anchors: NZA.ui.Anchors(APP), dockR: el('div', 'itb-dock r'), dockC: el('div', 'itb-dock c') };
    root.append(UI.dockC, UI.dockR);
    if (d.monitor !== false) UI.mon = MonitorDev(root); else root.classList.add('no-mon');
    UI.pp = NZA.ui.ProcPanel(root, { step: 1, total: S.mode === 'bvm' ? 1 : 8, abort: { label: T('abort', 'Hold to cancel'), key: 'ESC', seconds: 1.2 }, onAbort: abortProc, onTool: k => toolInfo(k) });
    UI.anc = el('div', 'itb-anc');
    UI.anc.innerHTML = `<span class="dia"><svg viewBox="0 0 44 44"><circle class="t" cx="22" cy="22" r="19"/><circle class="p" cx="22" cy="22" r="19" transform="rotate(-90 22 22)" stroke-dasharray="0 119.4"/></svg><i></i></span><span class="chip"><small>${esc(T('anc_kicker', 'BVM · 15 L O₂'))}</small><b></b></span>`;
    root.appendChild(UI.anc);
    root.addEventListener('contextmenu', e => e.preventDefault());
    root.addEventListener('pointerdown', onDown, true);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  }
  function teardown() {
    cancelAnimationFrame(raf); raf = 0;
    window.removeEventListener('pointermove', onMove);
    window.removeEventListener('pointerup', onUp);
    if (UI) {
      ['vent', 'sagp', 'scope', 'sagm', 'cuff', 'conf', 'res', 'mon'].forEach(k => { if (UI[k]) { try { UI[k].destroy(); } catch (e) { console.error(e); } } });
      if (UI.pp) UI.pp.destroy();
      UI.root.remove();
    }
    UI = null; S = null; ptr = null;
    Object.keys(held).forEach(k => { held[k] = false; });
  }

  const KEY_LIST = [' ', 'Enter', 'Backspace', 'KeyB', 'KeyE', 'KeyT', 'KeyF', 'KeyX', 'KeyW', 'KeyS', 'KeyA', 'KeyD', 'KeyQ', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', '1', '2', '3', '4', '5', '6'];
  const keys = {}, keysUp = {};
  KEY_LIST.forEach(k => { keys[k] = e => onKey(k, true, e); keysUp[k] = e => onKey(k, false, e); });

  const DEMO = mode => ({
    mode, monitor: true,
    patient: { name: 'Michael Garcia', sex: 'm', age: 34 },
    vitals: { hr: 118, sys: 96, dia: 58, map: 71, spo2: 86, rr: 0, temp: 36.2, rhythm: 'stach' },
    anat: { grade: 2, soil: 0.55, soilKind: 'blood', bleed: 0.3, cspine: false, tube: 7.5, depth: 23, cuffMl: 8.6, open: 0.9, gx: 0.02, gy: 0, aryt: 1, tongue: 0.2, ant: 0.2,
      desat: 1.1, safe: 55, apnoeic: true, gastric: 8, intubated: mode === 'bvm' ? false : undefined },
    cfg: { attempts: 3, cadence: 5, squeeze: 1, preoxBreaths: 6, abortSpo2: 90, crashSpo2: 75, cuffBand: [20, 30], breaths: 8 },
    locale: {},
  });

  const dev = {
    goto(n) {
      if (!S) NZA.demo(APP, DEMO('intubate'));
      const k = Number(n);
      S.spo2 = S.spo2Disp = S.low = 97; S.reserve = 0.9; S.preScore = 0.86; S.lastGood = now();
      if (k >= 3) Object.assign(S.pos, { done: true, towel: true, tilt: 21, jaw: 0.8, align: 0.92, score: 0.9 });
      if (k >= 4) { S.suc.done = true; S.suc.soiled = true; S.suc.c0 = 0.4; S.soil.reset(0.12); }
      if (k >= 5) S.vl.depth = 1.0;
      if (k >= 6) { S.vl.locked = { expo: 0.84, cl: '1' }; S.vl.expo = 0.84; S.clBest = '1'; }
      if (k >= 7) Object.assign(S.tube, { placed: 'trachea', pr: 23 / CM_FULL, show: true, ax: 0.5, ay: 0.52 });
      if (k >= 8) { S.cuff.ml = 8.5; S.cuff.p = cuffPressure(8.5); S.cuff.leak = false; S.cuffDone = { ml: 8.5, p: S.cuff.p }; }
      if (k >= 3 && !S.attemptOn) startAttempt();
      goStep(k);
    },
    set(fn) { if (S) fn(S, { mouse, held, STEPS, geo, clGrade }); },
    breaths(n, opts = {}) {
      for (let i = 0; i < n; i++) {
        const b = Object.assign({ hold: 1.0, interval: 5, first: i === 0 && !S.bag.count, q: 0.95, vol: 520, short: false, long: false, early: false, late: false }, opts);
        STEPS[S.step].breath(b);
      }
    },
    state: () => S,
  };

  appDef = NZA.app(APP, {
    escClose: false,
    modalKeys: true,
    open(data) {
      teardown();
      LOC = Object.assign({}, (data && data.locale) || {});
      S = newSession(data || {});
      build(data || {});
      goStep(S.mode === 'bvm' ? 'B' : 1);
      lastT = performance.now(); uiT = 0;
      raf = requestAnimationFrame(frame);
    },
    close() { teardown(); },
    msg: {
      vitals(v) {
        if (!S || !v) return;
        ['hr', 'sys', 'dia', 'map', 'temp'].forEach(k => { if (typeof v[k] === 'number') S.vit[k] = v[k]; });
        if (typeof v.rhythm === 'string') S.vit.rhythm = v.rhythm;
      },
      abort(d) { NZA.toast({ title: T('t_stopped', 'Procedure stopped'), message: (d && d.reason) || '', type: 'error' }); },
    },
    keys, keysUp,
    preview() {
      NZA.mock(`${APP}:step`, { ok: true });
      NZA.mock(`${APP}:finish`, { ok: true });
      NZA.mock(`${APP}:abort`, { ok: true });
      const u = new URLSearchParams(location.search);
      NZA.demo(APP, DEMO(u.get('mode') === 'bvm' ? 'bvm' : 'intubate'));
      if (u.get('step')) dev.goto(u.get('step'));
    },
    dev,
  });
})();
