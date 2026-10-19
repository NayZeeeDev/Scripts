/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · treat app · BLEED CONTROL 3D                    window.TreatBleed3D
   The treat app's 'bleed' mode as a full-screen 3D close-up on core/nza3d.js (the suture /
   burn look) under the shared procedure HUD (NZA.ui.ProcPanel) and the treat context card.
   apps/treat/app.js starts it from open() when WebGL2 works; its 2D overlay stays the fallback.

   Steps (data.steps from the server; same names, scores and pace as the 2D game):
     pressure  a gloved hand (in from the medic's side, lower right; about a fifth of the view)
               holds a gauze pad that follows the cursor. Hold LMB with the pad on the wound: the
               bleeding slows (ooze and spurts drop, the pad soaks), the gauge fills; let go and it
               bleeds again
     pack      deep wounds: a gloved finger feeds haemostatic gauze from the roll into the cavity,
               one push per hold (the ring fills → let go → push again); the ribbon slides into the
               wound and the cavity fills up. Then hold pressure on the packing.
     wrap      limbs: the pad stays on the wound; drag the bandage roll up over the limb (it goes
               round underneath by itself), each turn half over the last, a steady pace = even
               tension; then clip the end (click the clip, E or Space)
     dressing  torso / any non-limb site: pick the pressure dressing up, lay the pad over the
               wound, let go, then rub it down until it sticks
   Lua → JS   the app's own messages (open, vitals, result); the open data also carries tone + seed
              (server/modules/firstaid_procs.lua: the patient's skin, the same as in the suture / burn
              close-ups); without them both fall back to a hash of the patient name
   JS → Lua   through the app, exactly the 2D posts: treat:finish { result: { score, steps, lost } }
              · treat:abort {}
   Preview    index.html?app=treat&mode=bleed&stage=pressure|pack|hold|wrap|secure|dressing|seal|done
              &wound=gunshot|stab|laceration|shrapnel|abrasion  &site=thigh|leg|arm|forearm|chest|
              abdomen|back|neck  &deep=0|1  &tone=0..1  &sex=m|f  &turns=0..4  &partial=0..1  &no3d=1 (2D fallback)
   Everything 3D that the engine lacks (gloved hands, gauze pad, packing roll + ribbon, packed
   gauze, crepe bandage wrapped round the limb, bandage clip, target ring) is built here with
   THREE on S.scene and freed with the scene (S.dispose + this file's own bin).
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA) return;
  const THREE = window.THREE;
  const MM = 0.001, TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const rng = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const hash = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const keyLabel = code => (code === 'Space' ? 'Space' : code === 'Enter' ? 'Enter' : String(code || '').replace(/^Key|^Digit/, ''));

  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]|%\.\df/, v); }); return s; };

  // limb geometry per region (the engine's limb radii) · patch length · bandage width · pad · roll
  const LIMB = {
    upper_arm: { R: 0.05, W: 0.66, band: 0.075, pad: 0.07, roll: 0.02, view: 0.33 },
    lower_arm: { R: 0.04, W: 0.6, band: 0.065, pad: 0.06, roll: 0.018, view: 0.3 },
    upper_leg: { R: 0.075, W: 0.8, band: 0.1, pad: 0.085, roll: 0.025, view: 0.4 },
    lower_leg: { R: 0.055, W: 0.72, band: 0.09, pad: 0.076, roll: 0.022, view: 0.36 },
  };
  const TONES = [0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88];
  const BLOOD = [0.36, 0.012, 0.014];
  const STEP_ICON = { pressure: 'gauze', pack: 'gauze-roll', wrap: 'bandage', dressing: 'dressing-pad' };

  /* ═════════════════════════════ CSS (stage, cursor ring, loading veil) ═════════════════════════════ */
  const CSS = `
#app-treat .tb3-stage{position:absolute;inset:0;overflow:hidden;cursor:crosshair;pointer-events:auto;background:#050607}
#app-treat .tb3-stage.grab{cursor:grab}
#app-treat .tb3-stage.grabbing{cursor:grabbing}
#app-treat .tb3-stage.hide{cursor:none}
#app-treat .tb3-stage.point{cursor:pointer}
#app-treat .tb3-cur{position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;opacity:0;transition:opacity 140ms}
#app-treat .tb3-cur.on{opacity:1}
#app-treat .tb3-cur svg{position:absolute;left:-23px;top:-23px;width:46px;height:46px;transform:rotate(-90deg)}
#app-treat .tb3-cur.noring svg{display:none}
#app-treat .tb3-cur .bg{stroke:rgba(255,255,255,.22);fill:none;stroke-width:3}
#app-treat .tb3-cur .fg{stroke:var(--teal-hi);fill:none;stroke-width:3;stroke-linecap:round;filter:drop-shadow(0 0 4px rgba(15,212,196,.7))}
#app-treat .tb3-cur.red .fg{stroke:#ff7478;filter:drop-shadow(0 0 4px rgba(229,72,77,.7))}
#app-treat .tb3-cur.amber .fg{stroke:#f3c35a;filter:drop-shadow(0 0 4px rgba(229,165,10,.6))}
#app-treat .tb3-cur .tx{position:absolute;left:30px;top:-11px;height:22px;display:inline-flex;align-items:center;padding:0 8px;border-radius:6px;white-space:nowrap;
  font:600 11px var(--font);color:var(--white);background:rgba(12,13,16,.86);border:1px solid var(--hud-line)}
#app-treat .tb3-cur.noring .tx{left:16px}
#app-treat .tb3-cur .tx:empty{display:none}
#app-treat .tb3-cur.teal .tx{color:var(--teal-hi)} #app-treat .tb3-cur.red .tx{color:#ff9a9d} #app-treat .tb3-cur.amber .tx{color:#f3c35a}
#app-treat .tb3-load{position:absolute;inset:0;display:grid;place-items:center;background:#050607;transition:opacity 260ms;pointer-events:none}
#app-treat .tb3-load.out{opacity:0}
#app-treat .tb3-load .in{display:flex;flex-direction:column;align-items:center;gap:12px;color:var(--ink-3);font-size:12px}
#app-treat .tb3-load .ring{width:34px;height:34px;border-radius:50%;border:3px solid rgba(255,255,255,.1);border-top-color:var(--teal);animation:tb3-spin 900ms linear infinite}
@keyframes tb3-spin{to{transform:rotate(360deg)}}`;
  function injectCss() {
    if (document.getElementById('tb3-css')) return;
    const s = document.createElement('style');
    s.id = 'tb3-css'; s.textContent = CSS;
    document.head.appendChild(s);
  }

  /* ═════════════════════════════ textures (CPU canvases, cached) ═════════════════════════════ */
  const TEX = {};
  const cvs = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
  function heightToNormal(hc, strength) {
    const w = hc.width, h = hc.height, src = hc.getContext('2d').getImageData(0, 0, w, h).data;
    const out = cvs(w, h), oc = out.getContext('2d'), id = oc.createImageData(w, h);
    const H = (x, y) => src[(((y + h) % h) * w + ((x + w) % w)) * 4] / 255;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const dx = (H(x + 1, y) - H(x - 1, y)) * strength, dy = (H(x, y + 1) - H(x, y - 1)) * strength;
        const l = Math.hypot(dx, dy, 1), i = (y * w + x) * 4;
        id.data[i] = (-dx / l * 0.5 + 0.5) * 255; id.data[i + 1] = (dy / l * 0.5 + 0.5) * 255; id.data[i + 2] = (1 / l * 0.5 + 0.5) * 255; id.data[i + 3] = 255;
      }
    }
    oc.putImageData(id, 0, 0);
    return out;
  }
  // open-weave cotton gauze: 12 × 12 threads per tile, wavy, fuzzy (albedo + normal)
  function gauzeTex() {
    if (TEX.gauze) return TEX.gauze;
    const n = 128, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(311);
    x.fillStyle = '#3a3a3a'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#dcd6ca'; ax.fillRect(0, 0, n, n);
    const N = 12, step = n / N;
    for (const dir of [0, 1]) {
      for (let k = 0; k < N; k++) {
        const off = (k + 0.5) * step, v = 170 + r() * 70;
        x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = step * 0.44;
        ax.strokeStyle = `rgb(${246 - r() * 10},${243 - r() * 10},${235 - r() * 12})`; ax.lineWidth = step * 0.5;
        x.beginPath(); ax.beginPath();
        for (let i = 0; i <= 24; i++) {
          const p = (i / 24) * n, wv = Math.sin((i / 24) * TAU * 2 + k * 1.7) * 0.7;
          const X = dir ? p : off + wv, Y = dir ? off + wv : p;
          if (i) { x.lineTo(X, Y); ax.lineTo(X, Y); } else { x.moveTo(X, Y); ax.moveTo(X, Y); }
        }
        x.stroke(); ax.stroke();
      }
    }
    // loose fibres (fuzz)
    for (let i = 0; i < 420; i++) {
      const sx = r() * n, sy = r() * n, ang = r() * TAU, L = 2 + r() * 7;
      ax.strokeStyle = `rgba(255,253,247,${0.18 + r() * 0.25})`; ax.lineWidth = 0.6;
      ax.beginPath(); ax.moveTo(sx, sy); ax.lineTo(sx + Math.cos(ang) * L, sy + Math.sin(ang) * L); ax.stroke();
      x.strokeStyle = 'rgba(255,255,255,0.25)'; x.lineWidth = 0.6;
      x.beginPath(); x.moveTo(sx, sy); x.lineTo(sx + Math.cos(ang) * L, sy + Math.sin(ang) * L); x.stroke();
    }
    TEX.gauze = { albedo: a, normal: heightToNormal(h, 2.6) };
    return TEX.gauze;
  }
  // 8-ply gauze pad face: a fine, soft, low-contrast weave (one tile ≈ 3 cm, ~1 mm threads)
  function padTex() {
    if (TEX.pad) return TEX.pad;
    const n = 256, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(523);
    x.fillStyle = '#6a6a6a'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#e9e5dc'; ax.fillRect(0, 0, n, n);
    const N = 30, step = n / N;
    for (const dir of [0, 1]) {
      for (let k = 0; k < N; k++) {
        const off = (k + 0.5) * step, v = 150 + r() * 70;
        x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = step * 0.5;
        const av = 244 + r() * 9;
        ax.strokeStyle = `rgba(${av},${av - 2},${av - 8},0.9)`; ax.lineWidth = step * 0.55;
        x.beginPath(); ax.beginPath();
        for (let i = 0; i <= 30; i++) {
          const p = (i / 30) * n, wv = Math.sin((i / 30) * TAU * 3 + k * 2.1) * 0.5;
          const X = dir ? p : off + wv, Y = dir ? off + wv : p;
          if (i) { x.lineTo(X, Y); ax.lineTo(X, Y); } else { x.moveTo(X, Y); ax.moveTo(X, Y); }
        }
        x.stroke(); ax.stroke();
      }
    }
    for (let i = 0; i < 900; i++) {
      const sx = r() * n, sy = r() * n, ang = r() * TAU, L = 2 + r() * 9;
      ax.strokeStyle = `rgba(255,254,250,${0.12 + r() * 0.22})`; ax.lineWidth = 0.7;
      ax.beginPath(); ax.moveTo(sx, sy); ax.quadraticCurveTo(sx + Math.cos(ang + 0.6) * L * 0.5, sy + Math.sin(ang + 0.6) * L * 0.5, sx + Math.cos(ang) * L, sy + Math.sin(ang) * L); ax.stroke();
    }
    TEX.pad = { albedo: a, normal: heightToNormal(h, 1.3) };
    return TEX.pad;
  }
  // elastic crepe bandage: crimped weave across, fine threads along, selvedge edges with a thin
  // stripe (generic: no print). u = along the bandage (one tile ≈ 5 cm), v = across
  function crepeTex() {
    if (TEX.crepe) return TEX.crepe;
    const W = 256, H = 128, h = cvs(W, H), x = h.getContext('2d'), a = cvs(W, H), ax = a.getContext('2d'), r = rng(77);
    x.fillStyle = '#808080'; x.fillRect(0, 0, W, H);
    ax.fillStyle = '#ddd0b8'; ax.fillRect(0, 0, W, H);
    // crimps across the width (the crêpe), each a wavy ridge
    const NC = 46;
    for (let k = 0; k < NC; k++) {
      const x0 = (k + 0.5) * W / NC, v = 128 + (k % 2 ? 70 : -60) + (r() - 0.5) * 30;
      x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = W / NC * 0.6;
      const av = 218 + (k % 2 ? 16 : -10) + (r() - 0.5) * 10;
      ax.strokeStyle = `rgba(${av + 8},${av},${av - 18},0.55)`; ax.lineWidth = W / NC * 0.5;
      x.beginPath(); ax.beginPath();
      for (let i = 0; i <= 16; i++) {
        const y = (i / 16) * H, X = x0 + Math.sin((i / 16) * TAU * 2 + k * 0.9) * 2.2 + Math.sin((i / 16) * TAU * 5 + k * 2.3) * 0.8;
        if (i) { x.lineTo(X, y); ax.lineTo(X, y); } else { x.moveTo(X, y); ax.moveTo(X, y); }
      }
      x.stroke(); ax.stroke();
    }
    // fine threads along the length
    for (let j = 0; j < 46; j++) {
      const y = (j + 0.5) * H / 46;
      x.strokeStyle = 'rgba(200,200,200,0.22)'; x.lineWidth = 0.8; x.beginPath(); x.moveTo(0, y); x.lineTo(W, y); x.stroke();
      ax.strokeStyle = `rgba(255,252,244,${0.08 + r() * 0.1})`; ax.lineWidth = 0.9; ax.beginPath(); ax.moveTo(0, y); ax.lineTo(W, y); ax.stroke();
    }
    // selvedge: denser woven band at each edge + one thin stripe
    for (const y0 of [0, H - 7]) {
      ax.fillStyle = 'rgba(214,203,184,0.85)'; ax.fillRect(0, y0, W, 7);
      x.fillStyle = 'rgba(150,150,150,0.6)'; x.fillRect(0, y0, W, 7);
    }
    ax.fillStyle = 'rgba(92,150,170,0.75)'; ax.fillRect(0, 11, W, 1.6); ax.fillRect(0, H - 12.6, W, 1.6);
    TEX.crepe = { albedo: a, normal: heightToNormal(h, 2.4) };
    return TEX.crepe;
  }
  // nitrile glove: micro grain + faint stretch lines
  function gloveTex() {
    if (TEX.glove) return TEX.glove;
    const n = 256, c = cvs(n, n), x = c.getContext('2d'), r = rng(91);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    for (let i = 0; i < 5200; i++) { const v = 100 + r() * 70; x.fillStyle = `rgb(${v},${v},${v})`; x.beginPath(); x.arc(r() * n, r() * n, 0.6 + r() * 1.1, 0, TAU); x.fill(); }
    x.globalAlpha = 0.18;
    for (let i = 0; i < 90; i++) { const yy = r() * n; x.strokeStyle = r() < 0.5 ? '#5a5a5a' : '#a8a8a8'; x.lineWidth = 0.6; x.beginPath(); x.moveTo(0, yy); x.bezierCurveTo(n * 0.3, yy + r() * 6 - 3, n * 0.7, yy + r() * 6 - 3, n, yy); x.stroke(); }
    TEX.glove = heightToNormal(c, 2.2);
    return TEX.glove;
  }
  // uniform sleeve twill
  function twillTex() {
    if (TEX.twill) return TEX.twill;
    const n = 128, h = cvs(n, n), x = h.getContext('2d'), r = rng(61);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    const step = n / 24;
    x.lineWidth = step * 0.55;
    for (let k = -n; k < 2 * n; k += step) { const v = 150 + r() * 40; x.strokeStyle = `rgba(${v},${v},${v},0.55)`; x.beginPath(); x.moveTo(k, 0); x.lineTo(k + n, n); x.stroke(); }
    TEX.twill = heightToNormal(h, 1.4);
    return TEX.twill;
  }
  // dashed ring decal (white; tinted by the material)
  function ringTex() {
    if (TEX.ring) return TEX.ring;
    const N = 256, c = cvs(N, N), x = c.getContext('2d'), m = N / 2;
    x.strokeStyle = '#fff'; x.lineCap = 'round';
    const g = x.createRadialGradient(m, m, 80, m, m, 122); g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.55, 'rgba(255,255,255,.26)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    x.fillStyle = g; x.fillRect(0, 0, N, N);
    x.lineWidth = 9;
    for (let i = 0; i < 20; i++) { x.beginPath(); x.arc(m, m, 104, (i / 20) * TAU, (i / 20 + 0.03) * TAU); x.stroke(); }
    TEX.ring = c;
    return c;
  }

  /* ═════════════════════════════ geometry helpers ═════════════════════════════ */
  // sweep a rounded cross-section along a spine: prof(t) → { w, h, e (superellipse), pad }
  function sweepGeo(pts, prof, o = {}) {
    const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
    const NS = o.seg || 32, NR = o.rad || 18, CAP = 6;
    const up0 = (o.up || new THREE.Vector3(0, 0, 1)).clone().normalize();
    const rings = [];
    for (let i = 0; i <= NS; i++) rings.push({ t: i / NS, k: 1, adv: 0 });
    if (o.capEnd) for (let j = 1; j <= CAP; j++) { const a = (j / CAP) * Math.PI / 2; rings.push({ t: 1, k: Math.max(0.02, Math.cos(a)), adv: Math.sin(a) }); }
    const P = [], UVs = [], idx = [];
    const Tg = new THREE.Vector3(), B = new THREE.Vector3(), Sd = new THREE.Vector3(), p = new THREE.Vector3();
    const len = curve.getLength();
    rings.forEach(rg => {
      p.copy(curve.getPointAt(rg.t));
      Tg.copy(curve.getTangentAt(rg.t));
      B.copy(up0).addScaledVector(Tg, -up0.dot(Tg));
      if (B.lengthSq() < 1e-8) B.set(1, 0, 0);
      B.normalize();
      Sd.crossVectors(Tg, B).normalize();
      const pr = prof(rg.t), e = 2 / (pr.e || 2);
      p.addScaledVector(Tg, Math.min(pr.w, pr.h) * rg.adv * (o.capLen || 1));
      for (let j = 0; j < NR; j++) {
        const a = (j / NR) * TAU - Math.PI / 2, c = Math.cos(a), s = Math.sin(a);
        const sx = Math.sign(c) * Math.pow(Math.abs(c), e), sz = Math.sign(s) * Math.pow(Math.abs(s), e);
        const pad = s < 0 ? 1 + (pr.pad || 0) * -s : 1;
        const ox = sx * pr.w * rg.k, oz = sz * pr.h * rg.k * pad;
        P.push(p.x + Sd.x * ox + B.x * oz, p.y + Sd.y * ox + B.y * oz, p.z + Sd.z * ox + B.z * oz);
        UVs.push(j / NR, (rg.t * len) / 0.03);
      }
    });
    for (let i = 0; i < rings.length - 1; i++) {
      for (let j = 0; j < NR; j++) {
        const a = i * NR + j, b = i * NR + ((j + 1) % NR), c = (i + 1) * NR + j, d = (i + 1) * NR + ((j + 1) % NR);
        idx.push(a, c, b, b, c, d);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(UVs, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    return g;
  }
  // a regular grid (cols × rows quads) with uv 0..1; positions filled by the caller
  function gridGeo(cols, rows) {
    const nv = (cols + 1) * (rows + 1);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(nv * 3), 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(nv * 3), 3).setUsage(THREE.DynamicDrawUsage));
    const uv = new Float32Array(nv * 2);
    for (let j = 0; j <= rows; j++) for (let i = 0; i <= cols; i++) { const k = j * (cols + 1) + i; uv[k * 2] = i / cols; uv[k * 2 + 1] = 1 - j / rows; }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    const idx = [];
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) { const a = j * (cols + 1) + i, b = a + 1, c = a + cols + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
    g.setIndex(idx);
    return g;
  }
  // grid normals from neighbour differences, flipped to agree with `out` (a per-vertex outward hint)
  function gridNormals(g, cols, rows, outFn) {
    const p = g.attributes.position.array, n = g.attributes.normal.array, W1 = cols + 1;
    for (let j = 0; j <= rows; j++) {
      for (let i = 0; i <= cols; i++) {
        const k = j * W1 + i, l = j * W1 + Math.max(0, i - 1), r = j * W1 + Math.min(cols, i + 1), u = Math.max(0, j - 1) * W1 + i, d = Math.min(rows, j + 1) * W1 + i;
        const ax = p[r * 3] - p[l * 3], ay = p[r * 3 + 1] - p[l * 3 + 1], az = p[r * 3 + 2] - p[l * 3 + 2];
        const bx = p[d * 3] - p[u * 3], by = p[d * 3 + 1] - p[u * 3 + 1], bz = p[d * 3 + 2] - p[u * 3 + 2];
        let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
        const L = Math.hypot(nx, ny, nz) || 1;
        nx /= L; ny /= L; nz /= L;
        const o = outFn(k);
        if (nx * o[0] + ny * o[1] + nz * o[2] < 0) { nx = -nx; ny = -ny; nz = -nz; }
        n[k * 3] = nx; n[k * 3 + 1] = ny; n[k * 3 + 2] = nz;
      }
    }
    g.attributes.position.needsUpdate = true; g.attributes.normal.needsUpdate = true;
    g.computeBoundingSphere();
  }
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };

  /* ═════════════════════════════ preview data (browser only) ═════════════════════════════ */
  const SITES = {
    thigh: ['l_upper_leg', 'Left thigh', 'leg'], leg: ['r_lower_leg', 'Right lower leg', 'leg'], shin: ['r_lower_leg', 'Right lower leg', 'leg'],
    arm: ['r_upper_arm', 'Right upper arm', 'arm'], forearm: ['l_lower_arm', 'Left forearm', 'arm'],
    chest: ['chest', 'Chest', false], abdomen: ['abdomen', 'Abdomen', false], back: ['back', 'Back', false], neck: ['neck', 'Neck', false],
  };
  const TYPE_LABEL = { gunshot: 'Gunshot wound', stab: 'Stab wound', laceration: 'Deep laceration', shrapnel: 'Shrapnel wounds', abrasion: 'Bleeding abrasion' };
  function previewTweak(d) {
    if (NZA.inGame) return;
    const q = new URLSearchParams(location.search);
    const inj = d.injury = Object.assign({}, d.injury || {});
    let restep = false;
    const w = q.get('wound');
    if (w && TYPE_LABEL[w]) { inj.type = w; inj.typeLabel = TYPE_LABEL[w]; if (w === 'abrasion') inj.arterial = false; }
    const site = SITES[q.get('site')];
    if (site) { inj.region = site[0]; inj.regionLabel = site[1]; inj.limb = site[2]; restep = true; }
    if (q.get('deep') !== null) { d.deep = q.get('deep') === '1'; restep = true; }
    if (q.get('arterial') !== null) inj.arterial = q.get('arterial') === '1';
    if (q.get('tone') !== null) d.tone = clamp(+q.get('tone') || 0, 0, 1);
    if (q.get('sex')) d.patient = Object.assign({}, d.patient || {}, { sex: q.get('sex') === 'f' ? 'f' : 'm' });
    if (restep) {
      const limb = !!LIMB[String(inj.region || '').replace(/^[lr]_/, '')];
      d.method = limb ? 'wrap' : 'dressing';
      d.steps = ['pressure'].concat(d.deep ? ['pack'] : [], [d.method]);
    }
  }

  /* ═════════════════════════════ meshes ═════════════════════════════ */
  function materials(keep) {
    const tex = (c, srgb, rep) => { const t = keep(new THREE.CanvasTexture(c)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; if (srgb) t.encoding = THREE.sRGBEncoding; if (rep) t.repeat.set(rep[0], rep[1]); return t; };
    const gz = padTex(), cr = crepeTex();
    const M = {
      // nitrile exam glove (cobalt) and the medic's uniform sleeve
      glove: keep(new THREE.MeshPhysicalMaterial({ color: 0x1f35a0, roughness: 0.5, normalMap: tex(gloveTex(), false, [2, 2]), normalScale: new THREE.Vector2(0.32, 0.32), sheen: 0.14, sheenRoughness: 0.55, sheenColor: new THREE.Color(0x4a62c0), clearcoat: 0.22, clearcoatRoughness: 0.42, envMapIntensity: 0.7 })),
      sleeve: keep(new THREE.MeshPhysicalMaterial({ color: 0x1d3a4a, roughness: 0.9, normalMap: tex(twillTex(), false, [3, 3]), normalScale: new THREE.Vector2(0.6, 0.6), sheen: 0.5, sheenColor: new THREE.Color(0x6aa4b4) })),
      // gauze (packing ribbon, roll, packed mass): weave albedo, vertex colours carry the blood
      gauze: keep(new THREE.MeshPhysicalMaterial({ map: tex(gz.albedo, true), normalMap: tex(gz.normal, false), normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.94, sheen: 0.6, sheenRoughness: 0.7, sheenColor: new THREE.Color(1, 1, 1), vertexColors: true, side: THREE.DoubleSide })),
      packed: keep(new THREE.MeshPhysicalMaterial({ map: tex(gz.albedo, true, [0.6, 0.6]), normalMap: tex(gz.normal, false, [0.6, 0.6]), roughness: 0.9, sheen: 0.5, sheenRoughness: 0.7, sheenColor: new THREE.Color(1, 1, 1), clearcoat: 0, clearcoatRoughness: 0.3 })),
      crepe: keep(new THREE.MeshPhysicalMaterial({ map: tex(cr.albedo, true), normalMap: tex(cr.normal, false), normalScale: new THREE.Vector2(1.1, 1.1), roughness: 0.9, sheen: 0.45, sheenRoughness: 0.6, sheenColor: new THREE.Color(1, 0.97, 0.9), vertexColors: true, side: THREE.DoubleSide })),
      crepeEnd: keep(new THREE.MeshPhysicalMaterial({ color: 0xcfc1a6, roughness: 0.85 })),
      // the roll's outer layer: the same crepe without the grazing sheen, so it shades as a cylinder
      crepeRoll: keep(new THREE.MeshPhysicalMaterial({ map: tex(cr.albedo, true), normalMap: tex(cr.normal, false), normalScale: new THREE.Vector2(1.1, 1.1), color: 0xf2eee6, roughness: 0.96, sheen: 0.08, sheenRoughness: 0.8, sheenColor: new THREE.Color(1, 0.97, 0.9), vertexColors: true })),
      core: keep(new THREE.MeshStandardMaterial({ color: 0x9a8f80, roughness: 0.8 })),
      steel: keep(new THREE.MeshPhysicalMaterial({ color: 0xdfe4e8, roughness: 0.22, metalness: 0.95, envMapIntensity: 1.6, clearcoat: 0.3, clearcoatRoughness: 0.2 })),
      elastic: keep(new THREE.MeshPhysicalMaterial({ color: 0xd8c9ad, roughness: 0.8, sheen: 0.4, sheenColor: new THREE.Color(1, 0.95, 0.85) })),
      ring: keep(new THREE.MeshBasicMaterial({ map: tex(ringTex(), false), color: 0xe5484d, transparent: true, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 })),
    };
    M.tex = tex;
    return M;
  }

  // gloved right hand + sleeve. Tool frame: origin at the contact point, +Y toward the wrist (tool
  // axis), back of the hand +Z, palm toward -Z, thumb on +X. press = palm flat (on a pad),
  // point = index finger out, the others curled (feeds gauze into a wound)
  const HAND_POSE = {
    // the flat of four fingers on a pad (or rubbing a dressing down), thumb off to the side
    // (thumbDir: where the thumb leaves the palm; flat on a pad it lies along the index finger)
    press: { flex: [[0.2, 0.22, 0.1], [0.18, 0.22, 0.1], [0.2, 0.24, 0.1], [0.24, 0.26, 0.12]], thumb: [0.35, 0.2, 0.12], thumbDir: [0.42, -0.82, -0.3], wrist: 0.16 },
    point: { flex: [[0.06, 0.05, 0.02], [1.35, 1.5, 0.85], [1.4, 1.55, 0.85], [1.45, 1.55, 0.85]], thumb: [0.95, 0.75, 0.6], thumbDir: [0.5, -0.66, -0.5], wrist: 0.12 },
  };
  function buildHand(M, keep, poseName) {
    const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
    const P = HAND_POSE[poseName];
    const g = new THREE.Group(), inner = new THREE.Group();
    g.add(inner);
    const FINGERS = [
      { x: 0.027, len: [0.044, 0.026, 0.021], r: 0.0092, splay: -0.06 },
      { x: 0.008, len: [0.048, 0.029, 0.022], r: 0.0094, splay: 0.0 },
      { x: -0.011, len: [0.045, 0.027, 0.021], r: 0.0089, splay: 0.06 },
      { x: -0.028, len: [0.035, 0.021, 0.019], r: 0.0079, splay: 0.14 },
    ];
    const pads = [];
    const palmG = keep(new THREE.SphereGeometry(1, 40, 28));
    {
      const p = palmG.attributes.position, w = 0.084, l = 0.098, t = 0.025;
      for (let i = 0; i < p.count; i++) {
        let x = p.getX(i), y = p.getY(i), zz = p.getZ(i);
        const sq = v => Math.sign(v) * Math.pow(Math.abs(v), 0.84);
        x = sq(x) * w / 2; y = sq(y) * l / 2; zz = sq(zz) * t / 2;
        const fy = clamp((y + l / 2) / l, 0, 1);
        const k = lerp(1, 0.78, fy) * (1 - 0.06 * Math.pow(Math.abs(y) / (l / 2), 3));
        x *= k;
        // a flat back that slims down to the knuckles (no lid over the fingers), a soft arch
        if (zz > 0) zz *= lerp(0.74, 1, smooth(0, 0.34, fy));
        zz += (1 - Math.pow(x / (w / 2), 2)) * t * 0.07 * (zz > 0 ? 1 : 0.25);
        if (zz > 0) zz += 0.0022 * Math.exp(-Math.pow((y + l / 2 - 0.006) / 0.008, 2));
        p.setXYZ(i, x, y, zz);
      }
      palmG.computeVertexNormals();
    }
    const palm = new THREE.Mesh(palmG, M.glove);
    palm.position.set(-0.001, 0.046, 0);
    inner.add(palm);
    const blobG = keep(new THREE.SphereGeometry(1, 28, 18));
    const thenar = new THREE.Mesh(blobG, M.glove);
    thenar.scale.set(0.017, 0.03, 0.011); thenar.position.set(0.026, 0.066, -0.008); thenar.rotation.z = -0.35;
    inner.add(thenar);
    const hypo = new THREE.Mesh(blobG, M.glove);
    hypo.scale.set(0.014, 0.034, 0.009); hypo.position.set(-0.03, 0.06, -0.007);
    inner.add(hypo);
    FINGERS.forEach((f, fi) => {
      const flex = P.flex[fi], sp = f.splay;
      const dir = th => V3(Math.sin(sp) * Math.cos(th), -Math.cos(sp) * Math.cos(th), -Math.sin(th));
      const pts = [V3(f.x - Math.sin(sp) * 0.024, 0.024, -0.0015)];
      let cur = V3(f.x, 0, 0), th = 0, acc = 0;
      pts.push(cur.clone());
      const joints = [0], total = f.len.reduce((a, b) => a + b, 0);
      f.len.forEach((L, si) => {
        th += flex[si];
        const d = dir(th);
        pts.push(cur.clone().addScaledVector(d, L * 0.5), cur.clone().addScaledVector(d, si === 2 ? L - f.r * 0.7 : L));
        acc += L; joints.push(acc / total);
        if (si === 2) {
          const nrm = V3(-Math.sin(sp) * Math.sin(th), Math.sin(th) * Math.cos(sp), -Math.cos(th));
          const pad = new THREE.Object3D();
          pad.position.copy(cur.clone().addScaledVector(d, L * 0.55).addScaledVector(nrm, f.r * 0.92));
          inner.add(pad); pads[fi] = pad;
        }
        cur = cur.clone().addScaledVector(d, L);
      });
      const geo = keep(sweepGeo(pts, t => {
        const tt = clamp((t - 0.06) / 0.94, 0, 1);
        let r = f.r * lerp(1.02, 0.84, tt);
        joints.forEach((jt, ji) => { if (ji > 0 && ji < 3) r *= 1 + 0.07 * Math.exp(-Math.pow((tt - jt) / 0.05, 2)); });
        return { w: r * 1.06, h: r * 0.9, e: 2.2, pad: 0.06 };
      }, { seg: 30, rad: 16, up: V3(0, 0, 1), capEnd: true, capLen: 0.95 }));
      inner.add(new THREE.Mesh(geo, M.glove));
    });
    {
      const fl = P.thumb, base = V3(0.03, 0.07, -0.012), d0 = V3(...P.thumbDir).normalize();
      const turn = (v, a) => V3(v.x * Math.cos(a) + v.y * Math.sin(a) * 0.35, v.y * Math.cos(a) - v.x * Math.sin(a) * 0.35, v.z - Math.sin(a) * 0.55).normalize();
      const p1 = base.clone().addScaledVector(turn(d0, fl[0] * 0.4), 0.032);
      const p2 = p1.clone().addScaledVector(turn(d0, fl[0] * 0.4 + fl[1]), 0.027);
      const p3 = p2.clone().addScaledVector(turn(d0, fl[0] * 0.4 + fl[1] + fl[2]), 0.022);
      const pts = [base.clone().addScaledVector(d0, -0.012), base, base.clone().lerp(p1, 0.5), p1, p1.clone().lerp(p2, 0.5), p2, p3];
      inner.add(new THREE.Mesh(keep(sweepGeo(pts, t => { const r = 0.0102 * lerp(1.06, 0.84, t); return { w: r * 1.05, h: r * 0.88, e: 2.2, pad: 0.05 }; }, { seg: 26, rad: 16, up: V3(0.5, 0, 1), capEnd: true, capLen: 0.9 })), M.glove));
    }
    // wrist, rolled cuff and sleeve on a pivot: the forearm rises off the skin
    const wrist = new THREE.Group();
    wrist.position.set(-0.002, 0.086, 0.001); wrist.rotation.x = P.wrist;
    inner.add(wrist);
    wrist.add(new THREE.Mesh(keep(sweepGeo([V3(0, 0.002, 0), V3(0, 0.034, 0.001), V3(0, 0.082, 0.002)], t => ({ w: lerp(0.035, 0.031, t), h: lerp(0.016, 0.021, t), e: 2.3 }), { seg: 10, rad: 24 })), M.glove));
    const cuff = new THREE.Mesh(keep(new THREE.TorusGeometry(0.033, 0.0034, 10, 36)), M.glove);
    cuff.rotation.x = Math.PI / 2; cuff.scale.set(1, 0.68, 1); cuff.position.set(0, 0.082, 0.002); wrist.add(cuff);
    const knit = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.036, 0.035, 0.03, 32, 1, true)), M.sleeve);
    knit.scale.set(1, 1, 0.72); knit.position.set(0, 0.104, 0.002); wrist.add(knit);
    const slv = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.054, 0.038, 0.3, 32, 1, false)), M.sleeve);
    slv.scale.set(1, 1, 0.8); slv.position.set(0, 0.264, 0.005); wrist.add(slv);
    inner.updateMatrixWorld(true);
    const c = poseName === 'point' ? pads[0].getWorldPosition(V3(0, 0, 0)) : [0, 1, 2].reduce((v, i) => v.add(pads[i].getWorldPosition(V3(0, 0, 0))), V3(0, 0, 0)).multiplyScalar(1 / 3);
    // a size-S / M glove: a little smaller than the ultrasound hand, so it never swamps the close-up
    const SC = 0.86;
    inner.scale.setScalar(SC);
    inner.position.copy(c).multiplyScalar(-SC);
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    g.visible = false;
    return { group: g, inner, base: inner.position.clone() };
  }

  /* ═════════════════════════════ THE GAME ═════════════════════════════ */
  const PUSH_T = 0.55;          // s per gauze push (the finger feeds one fold in)
  const WRAP_A0 = 1.3;          // engine angle (rad) where each turn starts: the near side of the limb, in view
  const WRAP_AFAR = -0.62;      // ... and where the visible part ends: over the far top
  const WRAP_TREF = 0.6;        // tension per (visible passes / s) dragged on screen: band 0.38..0.72 ≈ 0.6–1.3 s per pass
  const WRAP_CATCH = 7;         // rad/s the roll catches up with the cursor
  const WRAP_END = 0.95;        // the bandage ends this far past a full turn (rad): on the near top, in view

  class Game {
    constructor(app, data) {
      this.app = app; this.d = data;
      LOC = Object.assign({}, data.locale || {});
      previewTweak(data);
      this.inj = data.injury = Object.assign({ id: 'w', type: 'laceration', region: 'chest', severity: 2, bleed: 8 }, data.injury || {});
      this.key3 = String(this.inj.region || 'chest').replace(/^[lr]_/, '');
      this.limb = LIMB[this.key3] || null;
      this.steps = (Array.isArray(data.steps) && data.steps.length ? data.steps : ['pressure', this.limb ? 'wrap' : 'dressing']).slice();
      this.KEY = Object.assign({ confirm: 'Space', lock: 'KeyE', done: 'Enter' }, data.keys || {});
      app.steps = this.steps;
      app.tune = this.tune = Object.assign({ pressureTarget: 0.3, pressureHold: 2.5, packStrips: 4, wrapTurns: 4, tensionBand: [0.38, 0.72] }, data.tune || {});
      const G = this.G = app.G;
      G.b = data.underTq ? 0.12 : 1; G.maxB = G.b; G.cover = false; G.strips = [];
      this.alive = true; this.ready = false; this.stepIdx = -1; this.t = 0; this.lmb = false; this.uiAt = 0;
      this.cur = { p: null, text: '', tone: '' };
      this.bin = new Set();
      // the app shell: an opaque full-screen close-up, no game-camera input, no 2D stage / device
      app.full = true; app.opaque = true; app.camInput = false;
      app.el.classList.add('nza-full');
      if (app.cv) app.cv.style.display = 'none';
      if (app.dev) app.dev.classList.remove('on');
      injectCss();
      this.stage = el('div', 'tb3-stage');
      app.root.insertBefore(this.stage, app.root.firstChild);
      this.curEl = el('div', 'tb3-cur', '<svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>');
      app.root.appendChild(this.curEl);
      this.curFg = this.curEl.querySelector('.fg'); this.curTx = this.curEl.querySelector('.tx');
      this.loadEl = el('div', 'tb3-load', `<div class="in"><span class="ring"></span><span>${NZA.esc(T('b3_loading', 'Preparing the close-up…'))}</span></div>`);
      app.root.appendChild(this.loadEl);
      if (data.underTq) app.setTip(T('tip_under_tq', 'A tourniquet is holding this bleed. Pack and dress it now so it can come off later.'), 'amber');
      else if (data.deep) app.setTip(T('tip_deep', '**Deep wound.** Pressure alone will not hold it: pack it with gauze, then dress it.'), 'red');
      else app.setTip(T('tip_shallow', 'Firm, direct pressure first. Then cover it so it stays controlled.'));
      // keys reach the game through the app's phase hook; the tool belt through onTool
      app.ph = { key: e => this.key(e), keyUp: () => false };
      app.pp.set({ onTool: k => this.pickTool(k) });
      this.onBlur = () => { if (this.lmb) this.up({ button: 0 }); };
      this.onResize = () => { this.zoom = 0; };
      window.addEventListener('blur', this.onBlur);
      window.addEventListener('resize', this.onResize);
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive) this.boot(); }));
    }

    keep(x) { if (x) this.bin.add(x); return x; }

    /* ─────────────── scene ─────────────── */
    boot() {
      const d = this.d, inj = this.inj, L = this.limb;
      const name = (d.patient && d.patient.name) || '';
      const seed = (+d.seed || hash(`${inj.id}:${name}`)) >>> 0;
      this.R = rng(seed);
      const tone = d.tone !== undefined && d.tone !== null && d.tone !== '' ? clamp(+d.tone || 0, 0, 1) : TONES[hash(name || inj.id) % TONES.length];
      const sex = (d.patient && d.patient.sex) === 'f' ? 'f' : 'm';
      this.sev = clamp(Math.round(+inj.severity || 2), 1, 4);
      // wound centre: on top of the limb (shifted toward the side the spot is on), or mid-torso
      const spot = inj.spot || { x: 0.5, y: 0.5 };
      let wUv;
      // 'medium' = what the in-game cap (Config.UI.quality3d 'auto') gives anyway: the preview shows the real look
      const opts = { tone, region: inj.region || 'chest', sex, seed, quality: (d.cfg && d.cfg.quality) || 'medium' };
      if (L) {
        const H = TAU * L.R * 0.995;
        opts.size = [L.W, H];
        const tOff = clamp((+spot.x || 0.5) - 0.5, -0.3, 0.3) * L.R * 0.5;
        wUv = [0.5 + clamp((+spot.y || 0.5) - 0.5, -0.3, 0.3) * 0.04, 0.5 - tOff / H];
        opts.work = [0.3, Math.min(H, 0.26)];
      } else {
        wUv = [0.5 + clamp((+spot.x || 0.5) - 0.5, -0.4, 0.4) * 0.12, 0.5 + clamp((+spot.y || 0.5) - 0.5, -0.4, 0.4) * 0.1];
        // a roomier torso patch (its edges never show around the dressing); head / face / neck keep the
        // engine's own size (their small radius would wrap a bigger patch past a full turn)
        if (/^(chest|back|abdomen|pelvis)$/.test(this.key3)) opts.size = [0.6, 0.44];
        opts.work = [0.34, 0.28];
      }
      opts.focus = { uv: wUv, size: [0.08, 0.05], view: this.viewFor('pressure') };
      let S;
      try { S = NZA3D.createScene(this.stage, opts); } catch (e) { console.error('[treat] 3D scene', e); return this.fail(); }
      this.S = S;
      this.wUv = wUv; this.wST = S.uvToST(wUv);
      S.controls.limits.pitchMin = 0.5;
      // the drape under a limb: a dark field blanket rather than theatre teal
      if (S._cloth) { S._cloth.material.color.setHex(0x2b3a40); }
      try {
        this.M = materials(x => this.keep(x));
        this.makeWound();
        this.paintInitial();
        this.makeObjects();
      } catch (e) { console.error('[treat] 3D build', e); return this.fail(); }
      S.layers.decay('wet', 0.05);
      this.prewarm();
      S.on('frame', (dt, render) => this.frame(dt, render !== false));
      S.on('down', e => this.down(e));
      S.on('up', e => this.up(e));
      S.on('pointer', () => { if (this.ready && this.ph && this.ph.pointer && !this.finished) this.ph.pointer(); });
      S.start();
      this.ready = true;
      this.nextStep();
      setTimeout(() => this.loadEl && this.loadEl.classList.add('out'), 140);
      if (this.pendingJump) { const j = this.pendingJump; this.pendingJump = null; this.jump(j); }
    }

    // 3D could not start after all: hand the session to the 2D game
    fail() {
      const a = this.app;
      this.dispose();
      a.b3 = null;
      if (a.cv) a.cv.style.display = '';
      if (a.dev) a.dev.classList.add('on');
      a.ph = null;
      a.pp.set({ onTool: () => {} });
      a.initBleed(); a.renderCard();
      a.last = performance.now();
      const loop = () => { a.raf = requestAnimationFrame(loop); a.frame(); };
      a.raf = requestAnimationFrame(loop);
    }

    // view width (m) per step. The gloved hand is the same size on every limb, so the hand steps never
    // frame tighter than this (a forearm close-up would let the hand cover a third of the screen)
    viewFor(step) {
      const L = this.limb;
      if (step === 'pack') return L ? clamp(L.R * 5, 0.3, 0.36) : 0.32;
      if (step === 'wrap') return L ? clamp(L.R * 5.6, 0.25, 0.46) : 0.3;
      if (step === 'dressing') return 0.33;
      return L ? Math.max(L.view, 0.38) : 0.38;
    }
    frameStep(step, instant) {
      const S = this.S, L = this.limb;
      // wrap: aimed a little toward the near side (where each turn starts, the roll in view) and to the
      // left of the wound, so the roll clears the step panel and the clip end the tool belt
      if (step === 'wrap' && L) { S.controls.frame([this.wUv[0] - 0.03 / S.patch.W, 0.46], this.viewFor('wrap'), { pitch: 0.95, instant: !!instant }); return; }
      if (step === 'dressing' && this.dress) { const h = this.dress.home; S.controls.frame([(h[0] + this.wUv[0]) / 2, (h[1] + this.wUv[1]) / 2], this.viewFor('dressing'), { pitch: 1.1, instant: !!instant }); return; }
      S.controls.frame(this.wUv, this.viewFor(step), { pitch: step === 'pack' ? 1.2 : 1.14, instant: !!instant });
    }

    /* ─────────────── the wound (kind and depth from the data) ─────────────── */
    makeWound() {
      const S = this.S, inj = this.inj, R = this.R, sev = this.sev, deep = !!this.d.deep;
      const dmm = +inj.depth || 0;
      const c = this.wUv, seed = (hash(inj.id || 'w') % 100000);
      const type = inj.type || 'laceration';
      const limbAngle = this.limb ? 0 : (R() - 0.5) * 0.8;
      this.extra = [];
      let w;
      if (type === 'gunshot' || type === 'shrapnel') {
        const gun = type === 'gunshot';
        const rad = gun ? (2.6 + sev * 0.55 + (deep ? 0.9 : 0)) : (2.0 + sev * 0.45 + (deep ? 0.6 : 0));
        w = S.wounds.add({ type: 'gunshot', uv: c, radius: rad * MM, ring: (gun ? 1.1 + sev * 0.22 : 0.7) * MM, depth: clamp(Math.max(dmm, deep ? 15 : 9), 7, 18) * MM, jagged: gun ? 0.3 + sev * 0.08 : 0.85, seed });
        if (!gun) {
          for (let k = 0; k < 2 + Math.min(3, sev); k++) {
            const a = R() * TAU, dd = (9 + R() * 16) * MM;
            this.extra.push(S.wounds.add({ type: 'gunshot', uv: S.stToUv(this.wST[0] + Math.cos(a) * dd, this.wST[1] + Math.sin(a) * dd), radius: (0.7 + R() * 0.8) * MM, ring: 0.4 * MM, depth: 3 * MM, jagged: 0.9, seed: seed + 11 + k }));
          }
        }
        this.wRad = rad * MM;
        this.wLen = 0;
        this.wDepth = w.p.depth;
      } else if (type === 'stab') {
        const L = clamp(+inj.length || (14 + sev * 5), 12, 40);
        w = S.wounds.add({ type: 'stab', uv: c, angle: limbAngle + (R() - 0.5) * 0.6 + 0.25, length: L * MM, gape: (2.4 + sev * 0.5 + (deep ? 0.8 : 0)) * MM, depth: clamp(Math.max(dmm, deep ? 16 : 10), 8, 22) * MM, jagged: 0.12, seed });
        this.wLen = L * MM; this.wRad = L * MM / 2; this.wDepth = w.p.depth;
      } else if (type === 'abrasion') {
        // a graze: shallow parallel scrapes over a raw, oozing patch
        const L = clamp(+inj.length || 40, 24, 70) * MM, ang = limbAngle + (R() - 0.5) * 0.4;
        w = S.wounds.add({ type: 'laceration', uv: c, angle: ang, length: L, gape: 1.2 * MM, depth: 1.1 * MM, jagged: 0.95, rim: 0.9, seed });
        for (let k = 0; k < 5; k++) {
          const off = (k - 2) * (2.6 + R() * 1.4) * MM, along = (R() - 0.5) * 8 * MM;
          if (k === 2) continue;
          const ca = Math.cos(ang), sa = -Math.sin(ang);
          const uv = S.stToUv(this.wST[0] + along * ca - off * sa, this.wST[1] + along * sa + off * ca);
          this.extra.push(S.wounds.add({ type: 'laceration', uv, angle: ang + (R() - 0.5) * 0.08, length: L * (0.55 + R() * 0.4), gape: (0.5 + R() * 0.5) * MM, depth: 0.6 * MM, jagged: 0.95, rim: 0.7, seed: seed + 5 + k }));
        }
        this.wLen = L; this.wRad = L / 2; this.wDepth = 1.2 * MM;
      } else {
        const L = clamp(+inj.length || 45, 20, 110);
        w = S.wounds.add({ type: 'laceration', uv: c, angle: limbAngle + (R() - 0.5) * 0.35, length: L * MM, gape: clamp(L * 0.075 + (deep ? 1.2 : 0), 3, 8) * MM, depth: clamp(Math.max(dmm, 4 + sev * 2 + (deep ? 3 : 0)), 5, 16) * MM, jagged: clamp(0.45 + sev * 0.08, 0.3, 0.8), seed });
        this.wLen = L * MM; this.wRad = L * MM / 2; this.wDepth = w.p.depth;
      }
      this.w = w;
      this.line = w.code === 1;
      // satellite shrapnel holes / the other scrapes of a graze ooze a little on their own
      this.extra.forEach(e => S.fluids.bleed(e, type === 'abrasion' ? 0.5 : 0.8));
      // points that must end up under a pad / dressing
      if (this.line) this.wPts = w.points().filter((_, i, a) => i % 2 === 0 || i === a.length - 1);
      else {
        this.wPts = [c.slice()];
        for (let k = 0; k < 8; k++) { const a = (k / 8) * TAU; this.wPts.push(S.stToUv(this.wST[0] + Math.cos(a) * this.wRad * 1.1, this.wST[1] + Math.sin(a) * this.wRad * 1.1)); }
      }
    }
    // metres from a skin point to the wound (centre line / hole centre)
    woundDist(uv) {
      if (this.line) return this.w.locate(uv).d;
      return this.S.distanceUv(uv, this.wUv);
    }
    nearestWoundST(uv) {
      if (!this.line) return this.wST.slice();
      const r = this.w.at(clamp(this.w.locate(uv).tN, 0.08, 0.92));
      return [r.s, r.t];
    }
    halfOpen(tN) { return this.line ? Math.max(this.w.halfGape(tN), 1.2 * MM) : this.wRad; }
    // where the line of sight to a hit crosses the skin surface (a hit down in a deep hole lands on its
    // near wall: aiming at the middle of the opening must count as the middle)
    aimUv(hit) {
      if (!hit) return null;
      const h = hit.height || 0;
      if (h > -0.0008) return hit.uv;
      const S = this.S, d = hit.point.clone().sub(S.camera.position).normalize();
      const N = new THREE.Vector3(), P = new THREE.Vector3();
      S._surf(hit.s, hit.t, P, N);
      const P2 = hit.point.clone().addScaledVector(d, h / Math.max(0.25, -d.dot(N)));
      const q = S._toSurf(P2);
      return S.stToUv(q.s, q.t);
    }
    // reach of a press on the wound with the pad (pad centre within this of the wound)
    padReach() { return Math.max(this.padSize * 0.36, 14 * MM); }
    packReach() { return (this.line ? Math.max(this.halfOpen(0.5), 2 * MM) : this.wRad) + 9 * MM; }

    // grime-free field wound: fresh blood in and around it, a bruise, dried trickles and flecks
    paintInitial() {
      const S = this.S, R = this.R, sev = this.sev;
      const at = (ds, dt) => S.stToUv(this.wST[0] + ds, this.wST[1] + dt);
      for (let k = 0; k < 6; k++) {
        const a = R() * TAU, dd = (4 + R() * 12) * MM;
        S.layers.paint('bruise', at(Math.cos(a) * dd, Math.sin(a) * dd), [(10 + R() * 10) * MM, (7 + R() * 6) * MM], 0.05 + sev * 0.016, { hardness: 0, grain: 0.3, grainScale: 90, angle: R() * Math.PI });
      }
      for (const p of this.wPts) S.layers.splat('blood', p, (1.6 + R() * 1.6) * MM, 0.55 + R() * 0.3, { seed: 3 + Math.floor(R() * 99), count: 5 });
      if (this.line) for (const p of this.w.points()) S.layers.paint('blood', p, [this.halfOpen(0.5) + 0.6 * MM, this.halfOpen(0.5) + 0.6 * MM], 0.3, { hardness: 0.3 });
      // smeared blood around, mostly downhill (toward the viewer)
      const reach = this.wRad + 6 * MM;
      for (let k = 0; k < 9 + sev * 3; k++) {
        const a = R() * TAU, dd = reach * (0.3 + R() * 1.2), down = R() * R() * 12 * MM;
        S.layers.splat('blood', at(Math.cos(a) * dd, Math.sin(a) * dd * 0.7 + down), (0.9 + R() * 1.8) * MM, 0.12 + R() * 0.2, { seed: 50 + k, count: 4 });
      }
      // a graze: a raw, weeping patch under the scrapes
      if (this.inj.type === 'abrasion') {
        const ang = this.w.p.angle || 0;
        S.layers.paint('bruise', this.wUv, [this.wLen * 0.62, 9 * MM], 0.2, { hardness: 0, grain: 0.5, grainScale: 140, angle: ang });
        S.layers.paint('blood', this.wUv, [this.wLen * 0.5, 6.5 * MM], 0.22, { hardness: 0.05, grain: 0.75, grainScale: 320, angle: ang });
        S.layers.paint('clot', this.wUv, [this.wLen * 0.42, 4.5 * MM], 0.12, { hardness: 0.05, grain: 0.8, grainScale: 420, angle: ang });
      }
      // dried flecks and trickles
      for (let k = 0; k < 30 + sev * 10; k++) {
        const a = R() * TAU, dd = reach + R() * R() * 26 * MM, r = (0.12 + R() * R() * 0.5) * MM;
        S.layers.paint('clot', at(Math.cos(a) * dd, Math.sin(a) * dd), [r * (0.8 + R() * 0.6), r], 0.18 + R() * 0.3, { hardness: 0.45, angle: R() * Math.PI });
      }
      for (let k = 0; k < 3; k++) {
        const s0 = (R() - 0.5) * this.wRad * 1.6, len = (10 + R() * 16) * MM;
        S.layers.stroke('clot', at(s0, this.wRad * 0.6), at(s0 + (R() - 0.5) * 6 * MM, this.wRad + len), 0.0007, 0.05, { hardness: 0.45, grain: 0.4, grainScale: 120 });
      }
      // a couple of fresh runs already on their way
      for (let k = 0; k < 2; k++) S.fluids.drip(at((R() - 0.5) * this.wRad, this.wRad + 1 * MM), 0.08 + R() * 0.04);
    }

    /* ─────────────── objects ─────────────── */
    makeObjects() {
      const S = this.S, M = this.M, L = this.limb;
      this.padSize = L ? L.pad : 0.09;
      this.hands = {
        press: buildHand(M, x => this.keep(x), 'press'),
        point: buildHand(M, x => this.keep(x), 'point'),
      };
      Object.values(this.hands).forEach(h => S.scene.add(h.group));
      const self = this;
      const mkTool = (name, hand, pose, upd) => ({
        name, group: hand.group, pose, press: 0, _p: new THREE.Vector3(), _q: new THREE.Quaternion(), _init: false,
        tipWorld: () => hand.group.getWorldPosition(new THREE.Vector3()), set() {}, update: upd,
      });
      // press / rub: the flat of the fingers on the pad's top. The engine lifts a tool along its own
      // axis, which for a hand lying almost flat slides it sideways off the pad: move it back so the
      // fingers ride straight above the cursor point, at skin level over the wound hole too (the hit
      // there is down in the hole). Tool frame: +Y = axis, +Z = back of the hand; the surface normal
      // is axis·cos(tilt) + Z·sin(tilt)
      // the hand comes in from the medic's side (lower right) with the forearm low and receding: it
      // covers the pad's near half and ~1/5 of the view, never the wound, the pad or the ring
      const PRESS_TILT = 1.22, COS_T = Math.cos(PRESS_TILT), PRESS_YAW = -0.6;
      const handAt = (hand, tool) => {
        const hit = S.tools.hit, h = hit ? Math.min(0, hit.height || 0) : 0;
        const pz = tool.pose, c = Math.cos(pz.tilt), s = Math.sin(pz.tilt);
        const along = lerp(pz.lift, pz.pressLift, tool.press), up = along * c - h;
        hand.inner.position.copy(hand.base);
        hand.inner.position.y += up * c - along;
        hand.inner.position.z += up * s;
      };
      const th = (this.limb ? 0.0058 : 0.0064);
      this.tools = {
        press: mkTool('b3press', this.hands.press, { lift: (th + 0.0135) / COS_T, pressLift: (th * 0.7 + 0.0012) / COS_T, tilt: PRESS_TILT, yaw: PRESS_YAW, roll: 0, shadow: 0.06 },
          () => handAt(self.hands.press, self.tools.press)),
        rub: mkTool('b3rub', this.hands.press, { lift: 0.008 / COS_T, pressLift: 0.0028 / COS_T, tilt: PRESS_TILT, yaw: PRESS_YAW, roll: 0, shadow: 0.06 },
          () => handAt(self.hands.press, self.tools.rub)),
        point: mkTool('b3point', this.hands.point, { lift: 0.004, pressLift: -(this.wDepth * 0.55 + 0.002), tilt: 0.9, yaw: 0.55, roll: 0, shadow: 0.035 }),
      };
      this.pad = this.makePad();
      this.ring = this.makeRing();
    }

    // compile every shader up front behind the loading veil (no hitch on the first use)
    prewarm() {
      const S = this.S, shown = [];
      const show = o => { if (o && !o.visible) { o.visible = true; shown.push(o); } };
      Object.values(this.hands).forEach(h => { show(h.group); h.group.position.set(0, -5, 0); });
      show(this.pad.mesh); show(this.ring.mesh);
      const kit = this.steps.includes('pack') ? this.packKit() : null;
      if (kit) { show(kit.roll); show(kit.ribbon); kit.blobs.forEach(show); }
      const bd = this.limb && this.steps.includes('wrap') ? this.bandage() : null;
      if (bd) { show(bd.mesh); show(bd.roll); show(bd.clip); }
      S.prewarm([], !this.limb || !this.steps.includes('wrap'));
      shown.forEach(o => { o.visible = false; });
    }

    // conforming gauze pad (8-ply, folded edges): carried by the press hand or left on the wound
    makePad() {
      const S = this.S, M = this.M, self = this;
      const NP = 18, size = this.padSize, hw = size / 2, th0 = (this.limb ? 0.0042 : 0.0046);
      const geo = this.keep(gridGeo(NP, NP));
      const cv = cvs(128, 128), cx = cv.getContext('2d');
      const tex = M.tex(cv, true);
      tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
      const gz = padTex();
      const mat = this.keep(new THREE.MeshPhysicalMaterial({ map: tex, normalMap: M.tex(gz.normal, false, [3, 3]), normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.95, sheen: 0.6, sheenRoughness: 0.7, sheenColor: new THREE.Color(1, 1, 1), side: THREE.DoubleSide }));
      const mesh = new THREE.Mesh(geo, mat);
      mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false; mesh.visible = false;
      S.scene.add(mesh);
      const stains = [];
      // the weave lives in the normal map; the colour map is soft off-white (+ the blood it soaks)
      const base = cvs(128, 128), bx = base.getContext('2d'), br = rng(29);
      bx.fillStyle = '#eeeae1'; bx.fillRect(0, 0, 128, 128);
      for (let i = 0; i < 260; i++) { const v = 228 + br() * 26; bx.fillStyle = `rgba(${v},${v - 2},${v - 7},0.35)`; bx.fillRect(br() * 128, br() * 128, 1 + br() * 3, 1 + br() * 3); }
      const redraw = () => {
        cx.drawImage(base, 0, 0);
        // folded edges read a touch darker (layers of gauze)
        const e = cx.createLinearGradient(0, 0, 128, 0); e.addColorStop(0, 'rgba(120,110,95,.18)'); e.addColorStop(0.08, 'rgba(0,0,0,0)'); e.addColorStop(0.92, 'rgba(0,0,0,0)'); e.addColorStop(1, 'rgba(120,110,95,.18)');
        cx.fillStyle = e; cx.fillRect(0, 0, 128, 128);
        stains.forEach(s => {
          const x = s.u * 128, y = (1 - s.v) * 128, r = s.r * 128;
          const g = cx.createRadialGradient(x, y, 0, x, y, r);
          g.addColorStop(0, `rgba(96,6,8,${0.92 * s.a})`); g.addColorStop(0.55, `rgba(128,12,12,${0.72 * s.a})`); g.addColorStop(0.85, `rgba(150,24,18,${0.3 * s.a})`); g.addColorStop(1, 'rgba(160,30,20,0)');
          cx.fillStyle = g; cx.beginPath(); cx.ellipse(x, y, r * s.ex, r, s.rot, 0, TAU); cx.fill();
        });
        tex.needsUpdate = true;
      };
      redraw();
      const P = new THREE.Vector3(), N = new THREE.Vector3(), C = new THREE.Vector3(), CN = new THREE.Vector3(), Ts = new THREE.Vector3(), Tt = new THREE.Vector3();
      // folded edges: round over ≈ 7 mm; the face is gently pillowed
      const prof = (x, y) => { const e = 0.007; const b = smooth(-hw, -hw + e, x) * (1 - smooth(hw - e, hw, x)) * smooth(-hw, -hw + e, y) * (1 - smooth(hw - e, hw, y)); return Math.pow(b, 0.5) * (0.88 + 0.12 * (1 - (x * x + y * y) / (hw * hw * 2))); };
      const out = new Float32Array((NP + 1) * (NP + 1) * 3);
      const api = {
        mesh, size, s: 0, t: 0, ang: 0.18, press: 0, hover: 0, squash: 0, mode: 'hidden', soak: 0,
        thickness() { return th0 * (1 - 0.3 * api.squash); },
        // height of the pad's top above the skin at patch point (s, t) (0 off the pad), for the bandage
        heightAt(s, t) {
          if (api.mode !== 'placed') return 0;
          const ds = s - api.s, dt = t - api.t, ca = Math.cos(api.ang), sa = Math.sin(api.ang);
          const x = ds * ca + dt * sa, y = -ds * sa + dt * ca;
          if (Math.abs(x) > hw || Math.abs(y) > hw) return 0;
          return api.thickness() * prof(x, y);
        },
        // centre (s, t); press 0..1 (conforms to the skin as it is pressed); hover = gap under it (m)
        place(s, t, press, hover) {
          api.s = s; api.t = t; api.press = press; api.hover = hover;
          api.squash = press;
          const pa = S._surf, ca = Math.cos(api.ang), sa = Math.sin(api.ang), th = api.thickness();
          pa(s, t, C, CN);
          C.addScaledVector(CN, Math.max(0, S.heightAt(S.stToUv(s, t))));
          S._tangents(s, t, Ts, Tt);
          const k = clamp(0.3 + 0.7 * press, 0, 1);
          const pos = geo.attributes.position.array;
          for (let j = 0; j <= NP; j++) {
            for (let i = 0; i <= NP; i++) {
              const kk = j * (NP + 1) + i;
              const x = (i / NP - 0.5) * size, y = (j / NP - 0.5) * size;
              const ds = x * ca - y * sa, dt = x * sa + y * ca;
              pa(s + ds, t + dt, P, N);
              const h = Math.max(S.heightAt(S.stToUv(s + ds, t + dt)), -2.6 * MM * press);
              P.addScaledVector(N, h);
              // flat (held in the hand) ↔ moulded to the skin (pressed)
              const fx = C.x + Ts.x * ds + Tt.x * dt, fy = C.y + Ts.y * ds + Tt.y * dt, fz = C.z + Ts.z * ds + Tt.z * dt;
              const bx = lerp(fx, P.x, k), by = lerp(fy, P.y, k), bz = lerp(fz, P.z, k);
              const nx = lerp(CN.x, N.x, k), ny = lerp(CN.y, N.y, k), nz = lerp(CN.z, N.z, k);
              const up = hover + 0.0004 + th * prof(x, y) + (Math.sin(x * 160 + y * 90) * 0.00025) * prof(x, y);
              pos[kk * 3] = bx + nx * up; pos[kk * 3 + 1] = by + ny * up; pos[kk * 3 + 2] = bz + nz * up;
              out[kk * 3] = nx; out[kk * 3 + 1] = ny; out[kk * 3 + 2] = nz;
            }
          }
          gridNormals(geo, NP, NP, kk => [out[kk * 3], out[kk * 3 + 1], out[kk * 3 + 2]]);
          mesh.visible = true;
        },
        // blood soaking into the pad where it lies over the wound
        stain(dt, rate) {
          if (rate <= 0) return;
          api.soak = Math.min(1, api.soak + dt * rate);
          api._acc = (api._acc || 0) + dt;
          if (api._acc < 0.28) return;
          api._acc = 0;
          const ds = self.wST[0] - api.s, dtt = self.wST[1] - api.t, ca = Math.cos(api.ang), sa = Math.sin(api.ang);
          const x = ds * ca + dtt * sa, y = -ds * sa + dtt * ca;
          const u = x / size + 0.5, v = 0.5 - y / size;
          if (u < -0.2 || u > 1.2 || v < -0.2 || v > 1.2) return;
          const grow = 0.07 + api.soak * 0.32 + (self.line ? self.wLen / size * 0.25 : 0);
          stains.push({ u: u + (Math.random() - 0.5) * 0.06, v: v + (Math.random() - 0.5) * 0.06, r: grow * (0.6 + Math.random() * 0.5), a: 0.35 + Math.random() * 0.4, ex: self.line ? 1.5 : 1 + Math.random() * 0.3, rot: (self.line ? -self.w.p.angle - api.ang : Math.random() * 3) });
          if (stains.length > 46) stains.splice(0, stains.length - 46);
          redraw();
        },
        hide() { mesh.visible = false; api.mode = 'hidden'; },
      };
      return api;
    }

    // dashed target ring, moulded to the skin round the wound
    makeRing() {
      const S = this.S, NR = 14;
      const geo = this.keep(gridGeo(NR, NR));
      const mesh = new THREE.Mesh(geo, this.M.ring);
      mesh.renderOrder = 5; mesh.frustumCulled = false; mesh.visible = false;
      S.scene.add(mesh);
      const P = new THREE.Vector3(), N = new THREE.Vector3(), out = new Float32Array((NR + 1) * (NR + 1) * 3);
      return {
        mesh, r: 0,
        set(st, radius, color) {
          this.r = radius;
          if (color !== undefined) mesh.material.color.setHex(color);
          const size = radius / 0.41, pos = geo.attributes.position.array;
          for (let j = 0; j <= NR; j++) for (let i = 0; i <= NR; i++) {
            const k = j * (NR + 1) + i, s = st[0] + (i / NR - 0.5) * size, t = st[1] + (j / NR - 0.5) * size;
            S._surf(s, t, P, N);
            P.addScaledVector(N, Math.max(0, S.heightAt(S.stToUv(s, t))) + 0.0007);
            pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
            out[k * 3] = N.x; out[k * 3 + 1] = N.y; out[k * 3 + 2] = N.z;
          }
          gridNormals(geo, NR, NR, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
          mesh.visible = true;
        },
        hide() { mesh.visible = false; },
        pulse(time, on) { mesh.material.opacity = on ? 0.62 + Math.sin(time * 5) * 0.3 : 0.25; },
      };
    }

    /* ── packing kit: haemostatic gauze roll on the skin, the ribbon into the wound, the packed mass ── */
    packKit() {
      if (this.kit) return this.kit;
      const S = this.S, M = this.M, R = this.R, self = this;
      const L = this.limb;
      const rr0 = L ? clamp(L.roll * 0.42, 0.0085, 0.0105) : 0.0095, wk = 0.018;
      // roll: beside the wound (screen right, a little toward the viewer)
      const rollST = [this.wST[0] - Math.max(0.048, this.wRad + 0.034), this.wST[1] + 0.006];
      const roll = new THREE.Group();
      const rollInner = new THREE.Group(); roll.add(rollInner);
      const side = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(1, 1, wk, 40, 1, true).rotateZ(Math.PI / 2)), M.gauze);
      const caps = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.985, 0.985, wk * 0.99, 40, 1, false).rotateZ(Math.PI / 2)), M.crepeEnd);
      const core = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.0028, 0.0028, wk * 1.01, 16, 1, false).rotateZ(Math.PI / 2)), M.core);
      rollInner.add(side, caps);
      roll.add(core);
      // vertex colours for the roll side (white)
      { const g = side.geometry, n = g.attributes.position.count, col = new Float32Array(n * 3).fill(1); g.setAttribute('color', new THREE.BufferAttribute(col, 3)); }
      roll.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      roll.visible = false;
      S.scene.add(roll);
      // ribbon
      const NRB = 40, AC = 2;
      const rib = this.keep(gridGeo(AC, NRB));
      rib.setAttribute('color', new THREE.BufferAttribute(new Float32Array((AC + 1) * (NRB + 1) * 3).fill(1), 3));
      const ribbon = new THREE.Mesh(rib, M.gauze);
      ribbon.castShadow = true; ribbon.receiveShadow = true; ribbon.frustumCulled = false; ribbon.visible = false;
      S.scene.add(ribbon);
      // packed mass: crumpled gauze blobs in the cavity (rise as it fills)
      const blobGeo = this.keep(new THREE.IcosahedronGeometry(1, 2));
      {
        const p = blobGeo.attributes.position, r2 = rng(17);
        const bumps = Array.from({ length: 9 }, () => [r2() * 2 - 1, r2() * 2 - 1, r2() * 2 - 1, 0.1 + r2() * 0.16]);
        for (let i = 0; i < p.count; i++) {
          const v = new THREE.Vector3(p.getX(i), p.getY(i), p.getZ(i)).normalize();
          let k = 1;
          bumps.forEach(b => { const d = v.x * b[0] + v.y * b[1] + v.z * b[2]; k += b[3] * Math.max(0, d) * Math.sin(d * 9); });
          p.setXYZ(i, v.x * k, v.y * k * 0.62, v.z * k);
        }
        blobGeo.computeVertexNormals();
      }
      const blobs = [];
      const nb = this.line ? clamp(Math.round(this.wLen / (7 * MM)), 3, 9) : 4;
      for (let i = 0; i < nb; i++) {
        const m = new THREE.Mesh(blobGeo, M.packed);
        m.castShadow = true; m.receiveShadow = true; m.visible = false;
        let st, rb;
        if (this.line) {
          const tN = 0.1 + 0.8 * (i + 0.5) / nb, r = this.w.at(tN);
          st = [r.s, r.t];
          rb = clamp(this.halfOpen(tN) * 1.25, 2.2 * MM, 5.5 * MM);
          m.userData.dir = Math.atan2(r.dir[1], r.dir[0]);
        } else {
          const a = (i / nb) * TAU + 0.4, d = i ? this.wRad * 0.32 : 0;
          st = [this.wST[0] + Math.cos(a) * d, this.wST[1] + Math.sin(a) * d];
          rb = clamp(this.wRad * (i ? 0.62 : 0.88), 2 * MM, 6.5 * MM);
          m.userData.dir = R() * TAU;
        }
        m.userData.st = st; m.userData.rb = rb; m.userData.at = (i / nb) * 0.55;
        S.scene.add(m);
        blobs.push(m);
      }
      const P = new THREE.Vector3(), N = new THREE.Vector3(), Ts = new THREE.Vector3(), Tt = new THREE.Vector3(), X = new THREE.Vector3(), Y = new THREE.Vector3(), Z = new THREE.Vector3(), Mx = new THREE.Matrix4();
      const kit = {
        roll, ribbon, blobs, rr: rr0, fed: 0, packed: 0, ins: this.wST.slice(), dip: 0, soak: 0,
        show(on) { roll.visible = on; ribbon.visible = on; },
        insertAt(st) { kit.ins = st.slice(); },
        feed(m) { kit.fed += m; },
        setPacked(v) { kit.packed = clamp(v, 0, 1); },
        // per frame: roll pose, ribbon path, blob levels, blood
        update(dt, finger) {
          // roll shrinks as gauze goes in, rolls toward the wound
          kit.rr = rr0 * Math.sqrt(Math.max(0.3, 1 - 0.55 * kit.packed));
          S._surf(rollST[0], rollST[1], P, N);
          P.addScaledVector(N, Math.max(0, S.heightAt(S.stToUv(rollST[0], rollST[1]))) + kit.rr);
          S._tangents(rollST[0], rollST[1], Ts, Tt);
          X.copy(Tt); Y.copy(N); Z.crossVectors(X, Y).normalize();
          Mx.makeBasis(X, Y, Z);
          roll.position.copy(P); roll.quaternion.setFromRotationMatrix(Mx);
          rollInner.scale.set(1, kit.rr, kit.rr);
          rollInner.rotation.x = -kit.fed / Math.max(kit.rr, 0.004);
          // ribbon: from under the roll over the skin to the opening, then down into the cavity
          if (ribbon.visible) self.ribbonPath(kit, rollST, wk, NRB, AC, finger);
          // blobs
          kit.soak = Math.min(1, kit.soak + dt * (0.04 + 0.16 * self.G.b) * (kit.packed > 0 ? 1 : 0));
          const col = M.packed.color;
          col.setRGB(lerp(1, BLOOD[0] * 1.8, kit.soak * 0.85), lerp(1, BLOOD[1] * 3, kit.soak * 0.9), lerp(1, BLOOD[2] * 3, kit.soak * 0.9));
          M.packed.roughness = lerp(0.9, 0.5, kit.soak); M.packed.clearcoat = 0.4 * kit.soak;
          blobs.forEach(m => {
            const u = m.userData, f = clamp((kit.packed - u.at) / 0.45, 0, 1);
            m.visible = kit.packed > 0 && f > 0;
            if (!m.visible) return;
            S._surf(u.st[0], u.st[1], P, N);
            const lvl = lerp(-self.wDepth * 0.9, -u.rb * 0.12, Math.pow(f, 0.8));
            m.position.copy(P).addScaledVector(N, lvl);
            m.quaternion.setFromUnitVectors(Y.set(0, 1, 0), N);
            m.rotateY(u.dir);
            m.scale.set(u.rb * (self.line ? 1.35 : 1), u.rb, u.rb);
          });
        },
      };
      this.kit = kit;
      return kit;
    }
    ribbonPath(kit, rollST, wk, NRB, AC, finger) {
      const S = this.S, g = kit.ribbon.geometry, pos = g.attributes.position.array, uv = g.attributes.uv.array, col = g.attributes.color.array;
      const P = new THREE.Vector3(), N = new THREE.Vector3();
      const a = [rollST[0], rollST[1]], b = kit.ins;
      const ds = b[0] - a[0], dt = b[1] - a[1], len = Math.hypot(ds, dt) || 1e-6;
      const ux = ds / len, uy = dt / len;
      const rim = this.line ? this.halfOpen(this.w.locate(S.stToUv(b[0], b[1])).tN) + 1.2 * MM : this.wRad + 1.4 * MM;
      const flat = Math.max(0.001, len - rim), dipL = this.wDepth * (0.85 + 0.15 * kit.packed) + 0.004;
      const total = flat + dipL;
      const out = new Float32Array((AC + 1) * (NRB + 1) * 3);
      const C = new THREE.Vector3(), CN = new THREE.Vector3(), Sd = new THREE.Vector3(), Tg = new THREE.Vector3();
      const pts = [], nrm = [];
      for (let j = 0; j <= NRB; j++) {
        const L = (j / NRB) * total;
        if (L <= flat) {
          const s = a[0] + ux * L, t = a[1] + uy * L;
          S._surf(s, t, P, N);
          // lies on the skin, lifts off it a touch at the roll and arches over the wound rim
          const lift = 0.0005 + kit.rr * 0.15 * Math.exp(-L / 0.004) + 0.0012 * smooth(flat - 0.006, flat, L);
          P.addScaledVector(N, Math.max(0, S.heightAt(S.stToUv(s, t))) + lift);
        } else {
          // over the rim and down into the cavity, sliding from the rim to the insertion point;
          // the finger pushes the end deeper while it is in
          const f = (L - flat) / dipL;
          const fp = finger && finger.on ? finger.depth : 0;
          const dpt = lerp(0.0012, -dipL + 0.004, Math.pow(f, 0.8)) - fp * f;
          S._surf(b[0] - ux * rim * (1 - f), b[1] - uy * rim * (1 - f), P, N);
          P.addScaledVector(N, dpt);
        }
        pts.push(P.clone()); nrm.push(N.clone());
      }
      let acc = 0;
      for (let j = 0; j <= NRB; j++) {
        const p0 = pts[Math.max(0, j - 1)], p1 = pts[Math.min(NRB, j + 1)];
        Tg.subVectors(p1, p0).normalize();
        Sd.crossVectors(nrm[j], Tg).normalize();
        if (j) acc += pts[j].distanceTo(pts[j - 1]);
        const f = acc / total;
        const w = wk * (1 - 0.72 * smooth(flat / total - 0.06, 1, f));
        const crumple = 0.0009 * smooth(flat / total - 0.12, 1, f) * Math.sin(j * 2.3);
        for (let i = 0; i <= AC; i++) {
          const v = i / AC - 0.5, k = j * (AC + 1) + i;
          C.copy(pts[j]).addScaledVector(Sd, v * w).addScaledVector(nrm[j], (0.25 - v * v) * 0.0012 + crumple * (i - 1));
          pos[k * 3] = C.x; pos[k * 3 + 1] = C.y; pos[k * 3 + 2] = C.z;
          out[k * 3] = nrm[j].x; out[k * 3 + 1] = nrm[j].y; out[k * 3 + 2] = nrm[j].z;
          uv[k * 2] = (acc + kit.fed) / 0.03; uv[k * 2 + 1] = i / AC * (w / 0.03);
          // the end in the wound is soaked
          const soak = smooth(flat / total - 0.25, flat / total + 0.04, f) * (0.55 + 0.4 * this.G.b);
          col[k * 3] = lerp(1, BLOOD[0] * 1.9, soak); col[k * 3 + 1] = lerp(1, BLOOD[1] * 3, soak); col[k * 3 + 2] = lerp(1, BLOOD[2] * 3, soak);
        }
      }
      g.attributes.uv.needsUpdate = true; g.attributes.color.needsUpdate = true;
      gridNormals(g, AC, NRB, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
    }

    /* ── crepe bandage wrapped round the limb: one spiral band, half over the last turn ── */
    bandage() {
      if (this.bd) return this.bd;
      const S = this.S, M = this.M, L = this.limb, self = this;
      const R = S.shape.R, bw = L.band, N = this.tune.wrapTurns || 4, TH = 0.00105;
      const pitch = bw * 0.5;
      const s0 = this.wST[0] - (N - 1) / 2 * pitch;
      const SEG = 96, AC = 12, dphi = TAU / SEG;
      const PHI_MAX = N * TAU + 1.2;
      const NSEG = Math.ceil(PHI_MAX / dphi) + 2;
      const g = this.keep(gridGeo(AC, NSEG));
      g.setAttribute('color', new THREE.BufferAttribute(new Float32Array((AC + 1) * (NSEG + 1) * 3).fill(1), 3));
      const mesh = new THREE.Mesh(g, M.crepe);
      mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false; mesh.visible = false;
      S.scene.add(mesh);
      // across-profile: rounded selvedges
      const ACV = [], ACR = [];
      for (let i = 0; i <= AC; i++) { const v = i / AC * 2 - 1; ACV.push(v); ACR.push(-TH * 0.7 * Math.pow(Math.abs(v), 8)); }
      // roll (axis along the limb)
      const roll = new THREE.Group(), rInner = new THREE.Group(); roll.add(rInner);
      const rr0 = L.roll * 0.85;
      const rside = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(1, 1, bw * 0.97, 48, 1, true).rotateZ(Math.PI / 2)), M.crepeRoll);
      { const gg = rside.geometry; gg.setAttribute('color', new THREE.BufferAttribute(new Float32Array(gg.attributes.position.count * 3).fill(1), 3)); const u = gg.attributes.uv; for (let i = 0; i < u.count; i++) u.setXY(i, u.getX(i) * 3, u.getY(i)); }
      const rcap = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.985, 0.985, bw * 0.965, 48, 1, false).rotateZ(Math.PI / 2)), M.crepeEnd);
      const rcore = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.006, 0.006, bw * 0.98, 20, 1, false).rotateZ(Math.PI / 2)), M.core);
      rInner.add(rside, rcap);
      roll.add(rcore);
      roll.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      roll.visible = false;
      S.scene.add(roll);
      // clip: two toothed steel plates on a short elastic band
      // (each plate + its teeth on a side group, so the plates can lie round the limb's curve)
      const clip = new THREE.Group(), sides = [];
      const band = new THREE.Mesh(this.keep(new THREE.BoxGeometry(0.006, 0.0014, 0.034)), M.elastic);
      band.position.y = 0.0004;
      clip.add(band);
      [-1, 1].forEach(sg => {
        const side = new THREE.Group();
        side.userData.sg = sg; side.position.set(0, 0, sg * 0.019);
        const plate = new THREE.Mesh(this.keep(new THREE.BoxGeometry(0.017, 0.0008, 0.012)), M.steel);
        plate.position.set(0, 0.0007, 0); side.add(plate);
        for (let k = 0; k < 4; k++) { const tooth = new THREE.Mesh(this.keep(new THREE.ConeGeometry(0.0009, 0.003, 6)), M.steel); tooth.rotation.x = sg * Math.PI * 0.62; tooth.position.set((k - 1.5) * 0.004, -0.0002, sg * 0.0055); side.add(tooth); }
        clip.add(side); sides.push(side);
      });
      clip.traverse(o => { if (o.isMesh) o.castShadow = true; });
      clip.visible = false;
      S.scene.add(clip);
      const Pt = new THREE.Vector3();
      // spiral half a width per turn; after the last visible pass the end goes straight round (an
      // anchoring turn) and lies on top of the last turn, where the clip holds it
      const capPhi = (N - 1) * TAU + (WRAP_A0 - WRAP_AFAR);
      const scOf = phi => s0 + (Math.min(phi, capPhi) / TAU) * pitch;
      const aOf = phi => WRAP_A0 - phi;
      // height of what lies under the band at (s, a): skin (bridged over the wound), the pad
      const wrapA = a => (((a + Math.PI) % TAU) + TAU) % TAU - Math.PI;   // any angle → the patch's −π..π
      const baseR = (s, a) => {
        const t = wrapA(a) * R;
        let h = 0;
        if (Math.abs(s - self.wST[0]) < 0.06 && Math.abs(t - self.wST[1]) < 0.06) {
          h = Math.max(0, S.heightAt(S.stToUv(s, t)));
          const ph = Math.max(self.pad.heightAt(s, t), self.pad.heightAt(s + 0.004, t), self.pad.heightAt(s - 0.004, t), self.pad.heightAt(s, t + 0.004), self.pad.heightAt(s, t - 0.004));
          if (ph > 0) h = Math.max(h, ph + 0.0007);
          if (self.kit && self.kit.packed > 0.9 && self.woundDist(S.stToUv(s, t)) < self.halfOpen(0.5) + 1.5 * MM) h = Math.max(h, 0.0008);
        }
        return R + h + 0.00035;
      };
      const put = (phi, i, k3, pos, w) => {
        const a = aOf(phi), sc = scOf(phi);
        const v = ACV[i], s = sc - v * w / 2;   // across runs -s → +s reversed: the outside is the front face
        // one layer under where the previous turn lies (the lower-s half), none on the first turn
        const under = phi >= N * TAU ? 2.3 : phi >= TAU ? smooth(0.002, -0.002, s - sc) : 0;
        const r = baseR(s, a) + TH * (1 + under) + ACR[i];
        pos[k3] = s; pos[k3 + 1] = r * Math.cos(a) - R; pos[k3 + 2] = r * Math.sin(a);
        return under;
      };
      const layers = new Float32Array((AC + 1) * (NSEG + 1));
      const bd = {
        mesh, roll, clip, phi: 0, drawn: 0, seep: 0, rollR: rr0, bw, N, s0, pitch, R,
        scOf, aOf,
        show(on) { mesh.visible = on; roll.visible = on; },
        // build the band from 0 to phi; the roll sits on its end
        setPhi(phi, widthMul = 1) {
          phi = clamp(phi, 0, PHI_MAX);
          bd.phi = phi;
          const pos = g.attributes.position.array, uv = g.attributes.uv.array;
          const kmax = Math.min(NSEG, Math.ceil(phi / dphi));
          const w = bw * widthMul;
          for (let k = bd.drawn > 0 ? Math.max(0, Math.min(bd.drawn, kmax) - 1) : 0; k <= kmax; k++) {
            const ph = Math.min(k * dphi, phi);
            for (let i = 0; i <= AC; i++) {
              const kk = k * (AC + 1) + i;
              layers[kk] = put(ph, i, kk * 3, pos, w);
              uv[kk * 2] = (ph * R) / 0.05; uv[kk * 2 + 1] = i / AC;
            }
          }
          bd.drawn = kmax;
          g.setDrawRange(0, Math.max(0, kmax) * AC * 6);
          g.attributes.uv.needsUpdate = true;
          // normals: radial with the across tilt of the overlap step folded in by the grid pass
          gridNormals(g, AC, kmax, kk => { const k = Math.floor(kk / (AC + 1)), a = aOf(Math.min(k * dphi, phi)); return [0, Math.cos(a), Math.sin(a)]; });
          // roll on the band end
          const a = aOf(phi), sc = scOf(phi);
          const r = baseR(sc, a) + TH * 2 + bd.rollR;
          roll.position.set(sc, r * Math.cos(a) - R, r * Math.sin(a));
          roll.rotation.set(-phi * (R / Math.max(bd.rollR, 0.008)), 0, 0);
          bd.rollR = rr0 * Math.sqrt(Math.max(0.35, 1 - 0.55 * phi / (N * TAU)));
          rInner.scale.set(1, bd.rollR, bd.rollR);
        },
        // blood showing through the turns over the wound (vertex colours)
        tint(seep) {
          bd.seep = seep;
          const col = g.attributes.color.array, pos = g.attributes.position.array;
          const sw = self.wST[0], aw = self.wST[1] / R, sig = 0.01 + 0.026 * seep;
          for (let k = 0; k <= bd.drawn; k++) {
            for (let i = 0; i <= AC; i++) {
              const kk = k * (AC + 1) + i;
              const s = pos[kk * 3], a = Math.atan2(pos[kk * 3 + 2], pos[kk * 3 + 1] + R);
              let da = a - aw; da = ((da + Math.PI) % TAU + TAU) % TAU - Math.PI;
              const d2 = (s - sw) * (s - sw) + (da * R) * (da * R) * 1.3;
              const turnN = Math.floor(Math.min(k * dphi, bd.phi) / TAU);
              const st = seep * 2.3 * Math.exp(-d2 / (sig * sig)) * Math.pow(0.8, turnN + layers[kk]) * (0.8 + 0.3 * Math.sin(s * 700 + a * 35) * Math.sin(s * 230 - a * 90));
              const f = clamp(st, 0, 0.92);
              col[kk * 3] = lerp(1, 0.46, f); col[kk * 3 + 1] = lerp(1, 0.035, f); col[kk * 3 + 2] = lerp(1, 0.04, f);
            }
          }
          g.attributes.color.needsUpdate = true;
        },
        // the clip on the end (frame f from endFrame), lift above it; the plates follow the curve
        placeClip(f, lift) {
          clip.position.copy(f.p).addScaledVector(f.n, lift);
          clip.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), f.n);
          const rr = Math.max(0.02, Math.hypot(f.p.y + R, f.p.z) + lift);
          sides.forEach(sd => { const ph = sd.userData.sg * 0.019 / rr; sd.position.set(0, rr * Math.cos(ph) - rr, rr * Math.sin(ph)); sd.rotation.x = ph; });
          clip.visible = true;
        },
        // where the bandage ends (for the clip): position + frame
        endFrame(phi) {
          const a = aOf(phi), sc = scOf(phi), r = baseR(sc, a) + TH * 2.4;
          Pt.set(sc, r * Math.cos(a) - R, r * Math.sin(a));
          return { p: Pt.clone(), n: new THREE.Vector3(0, Math.cos(a), Math.sin(a)), a: wrapA(a), s: sc };
        },
        // engine angle under the cursor for the roll's slice of the limb (screen-height lookup)
        angleAtPointer() {
          // visible samples from the near side (low on screen) over the top to the far side
          const sc = scOf(bd.phi), cam = S.camera.position, py = S.pointer.y, r = R + 0.003;
          const lo = WRAP_AFAR - 0.35, hi = WRAP_A0 + 0.35, n = 30, vis = [];
          for (let j = 0; j <= n; j++) {
            const a = hi - (j / n) * (hi - lo);
            Pt.set(sc, r * Math.cos(a) - R, r * Math.sin(a));
            if (Math.cos(a) * (cam.y - Pt.y) + Math.sin(a) * (cam.z - Pt.z) <= 0) continue;   // faces away
            vis.push({ a, y: S.project(Pt).y });
          }
          if (!vis.length) return hi;
          bd.span = Math.max(0.05, vis[0].y - vis[vis.length - 1].y);   // screen height of the visible pass
          if (py >= vis[0].y) return vis[0].a;                       // below the near side: the start
          for (let j = 1; j < vis.length; j++) {
            const p0 = vis[j - 1], p1 = vis[j];
            if (py <= p0.y && py >= p1.y) return lerp(p0.a, p1.a, (p0.y - py) / Math.max(1e-6, p0.y - p1.y));
          }
          return lo;                                                 // above the far side: past the top
        },
      };
      this.bd = bd;
      return bd;
    }

    /* ─────────────── step flow ─────────────── */
    nextStep() {
      this.stepIdx += 1;
      const name = this.steps[this.stepIdx];
      if (!name) return this.finish();
      this.enter(name);
    }
    enter(name) {
      if (this.ph && this.ph.exit) this.ph.exit();
      const make = { pressure: this.phPressure, pack: this.phPack, wrap: this.limb ? this.phWrap : this.phDressing, dressing: this.phDressing }[name] || this.phDressing;
      this.ph = make.call(this);
      this.ph.name = name;
      this.ph.t0 = this.t;
      const names = { pressure: T('sn_pressure', 'Press on the wound'), pack: T('sn_pack', 'Pack the wound'), wrap: T('sn_wrap', 'Wrap the limb'), dressing: T('sn_dressing', 'Seal a dressing') };
      const inj = this.inj;
      this.app.pp.set(Object.assign({
        step: this.stepIdx + 1, total: this.steps.length, tag: `${T('tag_bleed', 'Bleed control')} · ${inj.regionLabel || ''}`.replace(/ · $/, ''),
        steps: this.steps.map(s => names[s] || s), titleTone: '',
        hints: this.hintsFor(this.ph.hints),
      }, this.ph.panelInit()));
      this.updateTools();
      this.ph.panel && this.ph.panel();
    }
    // the key hints row: the step's own action first, then the camera keys
    hintsFor(own) {
      return (own || []).concat([
        { keys: [T('b3_k_rmb', 'RMB')], label: T('b3_h_look', 'Look around') },
        { keys: [T('b3_k_wheel', 'Wheel')], label: T('b3_h_zoom', 'Zoom') },
        { keys: ['R'], label: T('b3_h_recentre', 'Recentre') },
      ]);
    }
    updateTools() {
      const names = { pressure: T('tool_pad', 'Gauze pad'), pack: T('b3_tool_roll', 'Haemostatic gauze'), wrap: T('tool_bandage', 'Bandage'), dressing: T('tool_dressing', 'Pressure dressing') };
      const subs = { pressure: T('b3_sub_pad', '10 × 10 cm · 8-ply'), pack: T('b3_sub_roll', 'Packing strip roll'), wrap: T('b3_sub_bandage', 'Elastic crepe'), dressing: T('b3_sub_dressing', 'Pad + adhesive border') };
      this.app.pp.set({
        tools: this.steps.map((s, i) => ({
          key: String(i + 1), label: names[s] || s, sub: subs[s], icon: STEP_ICON[s] || 'bandage',
          state: i < this.stepIdx ? 'done' : i === this.stepIdx ? 'active' : 'locked',
          why: T('b3_tool_later', 'Finish the step you are on first.'),
        })),
      });
    }
    pickTool(key) {
      const i = (+key || 0) - 1;
      if (!this.ph || this.finished || i === this.stepIdx || i < 0 || i >= this.steps.length) return;
      if (i < this.stepIdx) this.app.pp.flash('warn', T('b3_tool_done', 'That step is done.'), 1600);
    }
    stepDone(score, flash) {
      const ph = this.ph;
      if (!ph || ph.finished) return;
      ph.finished = true;
      this.G.steps[ph.name] = Math.round(clamp(score, 0, 100));
      NZA.audio.success();
      if (flash) this.app.pp.flash('ok', flash, 1800);
      this.cursor(null, '');
      const name = ph.name;
      setTimeout(() => { if (this.alive && this.ph === ph && ph.name === name) this.nextStep(); }, 850);
    }
    finish() {
      if (this.finished) return;
      this.finished = true;
      const G = this.G;
      if (this.ph && this.ph.exit) this.ph.exit();
      this.ph = { name: 'done', panel() {}, tick() {} };
      this.useTool(null);
      this.ring.hide();
      this.cursor(null, '');
      this.stageCursor('');
      G.cover = true;
      const vals = this.steps.map(s => G.steps[s] || 0);
      const score = vals.length ? vals.reduce((x, y) => x + y, 0) / vals.length : 0;
      this.app.submit({ score: Math.round(score), steps: Object.assign({}, G.steps), lost: Math.round(G.lost) });
    }

    useTool(name) {
      const S = this.S;
      S.tools.press(false);
      const t = name ? this.tools[name] : null;
      S.tools.use(t || null);
      this.toolName = name;
    }
    stageCursor(cls) { const c = `tb3-stage ${cls || ''}`.trim(); if (this.stage.className !== c) this.stage.className = c; }
    cursor(p, text, tone) { this.cur.p = p; this.cur.text = text || ''; this.cur.tone = tone || ''; }
    flashOnce(type, text, ms) { const n = performance.now(); if (this.lastFlash === text && n - this.lastFlashAt < 1800) return; this.lastFlash = text; this.lastFlashAt = n; this.app.pp.flash(type, text, ms || 2000); }

    /* ─────────────── input ─────────────── */
    down(e) {
      if (!this.ready || e.button !== 0 || this.finished || this.app.result) return;
      this.lmb = true;
      if (this.ph && this.ph.down) this.ph.down(e);
    }
    up(e) {
      if (e.button !== 0) return;
      const was = this.lmb;
      this.lmb = false;
      if (this.S) this.S.tools.press(false);
      if (was && this.ph && this.ph.up) this.ph.up(e);
    }
    key(e) {
      if (/^Digit[1-9]$/.test(e.code || '')) return this.app.pp.key(e);
      if (this.ph && this.ph.key) return this.ph.key(e);
      return false;
    }

    /* ─────────────── per frame ─────────────── */
    frame(dt, render) {
      if (!this.alive || !this.S) return;
      this.t += dt;
      if (this.ph && this.ph.tick) this.ph.tick(dt);
      this.bleedTick(dt);
      if (this.kit && (this.kit.roll.visible || this.kit.packed > 0)) this.kit.update(dt, this.fingerState());
      if (!render) return;
      this.ring.pulse(this.t, !this.lmb);
      this.drawCursor();
      const n = performance.now();
      if (n - this.uiAt > 120) { this.uiAt = n; if (this.ph && this.ph.panel) this.ph.panel(); }
    }
    fingerState() {
      const t = this.tools.point;
      if (this.toolName !== 'point' || !this.S.tools.hit) return null;
      return { on: t.press > 0.05, depth: (this.wDepth * 0.5) * t.press };
    }
    drawCursor() {
      const c = this.cur, S = this.S;
      const on = !this.finished && !this.app.result && (c.p !== null || !!c.text);
      this.curEl.classList.toggle('on', on);
      if (!on) return;
      if (!this.zoom) this.zoom = parseFloat(getComputedStyle(this.app.el).zoom) || 1;
      const x = S.pointer.x * window.innerWidth / this.zoom, y = S.pointer.y * window.innerHeight / this.zoom;
      this.curEl.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`;
      const cls = `tb3-cur on ${c.p === null ? 'noring' : ''} ${c.tone}`;
      if (this.curEl.className !== cls) this.curEl.className = cls;
      if (c.p !== null) this.curFg.setAttribute('stroke-dasharray', `${(clamp(c.p, 0, 1) * 119.4).toFixed(1)} 120`);
      if (this.curTx.textContent !== c.text) this.curTx.textContent = c.text;
    }

    // the wound bleeds by G.b (0..1 of its bleed): ooze in the wound, spurts on each beat when
    // arterial, a pool that spreads downhill; whatever lies on it soaks instead
    bleedTick(dt) {
      const S = this.S, G = this.G, inj = this.inj;
      const res = this.app.result;
      const bleed = Math.max(0, res && res.bleed !== undefined ? +res.bleed || 0 : +inj.bleed || 0);
      const cov = G.cover ? 0.15 : 1;
      const flow = bleed * G.b * cov;
      if (!res) G.lost += flow * dt / 60;
      G.flowNow = flow;
      this.beatT = (this.beatT || 0) - dt;
      let beat = false;
      if (this.beatT <= 0) { this.beatT = 60 / clamp(G.hr || 90, 30, 200); beat = true; }
      const open = !this.covered;
      const intensity = clamp(Math.log10(1 + bleed) / 2.4, 0.15, 1) * G.b * cov;
      const vis = open && !res ? clamp(1 + 1.8 * Math.log2(1 + bleed / 3), 0.8, 12) * G.b * cov : 0;
      const cur = this.oozeVis || 0;
      this.oozeT = (this.oozeT || 0) - dt;
      if ((Math.abs(vis - cur) > Math.max(0.35, cur * 0.18) && this.oozeT <= 0) || ((vis === 0) !== (cur === 0))) {
        S.fluids.bleed(this.w, vis > 0.05 ? vis : 0); this.oozeVis = vis > 0.05 ? vis : 0; this.oozeT = 0.4;
      }
      if (beat && inj.arterial && open && intensity > 0.05 && !res) {
        const sp = S.surfaceAt(this.wUv);
        sp.point.addScaledVector(sp.normal, 0.0015);
        S.fluids.drops(sp.point, Math.round(2 + 9 * intensity), BLOOD, 0.22 + 0.5 * intensity);
        if (intensity > 0.3) S.layers.paint('wet', this.wUv, 0.006, 0.2, { hardness: 0.1 });
      }
      // the pool around the wound spreads (downhill = toward the viewer)
      this.poolT = (this.poolT || 0) - dt;
      if (this.poolT <= 0 && open && intensity > 0.03 && !res) {
        this.poolT = 0.32;
        const R = Math.random, grow = 1 + Math.min(2.2, G.lost / 160);
        const a = R() * TAU, dd = this.wRad + (1 + R() * 5) * MM * grow;
        const uv = this.S.stToUv(this.wST[0] + Math.cos(a) * dd, this.wST[1] + Math.abs(Math.sin(a)) * dd * 0.8 + R() * 4 * MM * grow);
        S.layers.paint('blood', uv, [(1.6 + R() * 3) * MM * grow, (1.2 + R() * 2) * MM * grow], 0.05 + 0.14 * intensity, { hardness: 0.3, grain: 0.3, grainScale: 150, angle: R() * Math.PI });
      }
    }

    /* ═════════════════════════════ 1. DIRECT PRESSURE ═════════════════════════════ */
    phPressure() {
      const g = this, G = this.G, tune = this.tune, deep = !!this.d.deep;
      const floor = deep ? 0.2 : 0.04;
      this.useTool('press');
      this.pad.mode = 'tool';
      this.ring.set(this.wST, Math.max(this.padReach(), this.wRad + 6 * MM), 0xe5484d);
      this.frameStep('pressure', !this.stepIdx);
      const ps = { s: this.wST[0] + 0.03, t: this.wST[1] + 0.02, ok: false };
      return {
        onT: 0, pressT: 0, holdT: 0,
        hints: [{ keys: [T('k_lmb', 'Hold LMB')], label: T('h_press', 'press') }],
        panelInit() {
          return {
            title: T('ph_pressure', 'Apply direct pressure'),
            text: T('b3_pressure_t', 'Move the gauze pad over the wound and **hold {LMB}** to press it down. Keep holding until the gauge fills. Let go and it bleeds again.'),
          };
        },
        on() { return g.lmb && g.padOn(); },
        down() { if (!g.padOn()) g.flashOnce('warn', T('b3_off_wound', 'Put the pad on the wound itself, inside the red ring.'), 1800); },
        tick(dt) {
          const on = this.on();
          g.S.tools.press(g.lmb);
          if (g.lmb) { this.pressT += dt; if (on) this.onT += dt; }
          if (on) G.b = Math.max(floor, G.b - (deep ? 0.22 : 0.34) * dt);
          else G.b = Math.min(G.maxB, G.b + (g.lmb ? 0.1 : 0.2) * dt * G.maxB);
          G.cover = false;
          g.covered = on;
          if (G.b <= tune.pressureTarget && on) this.holdT += dt; else this.holdT = Math.max(0, this.holdT - dt * 2);
          g.carryPad(dt, ps);
          if (on) g.pad.stain(dt, 0.04 + 0.18 * G.b);
          if (this.holdT >= tune.pressureHold && !this.finished) {
            const total = g.t - this.t0, acc = this.pressT > 0 ? this.onT / this.pressT : 0, speed = clamp(1 - (total - 5) / 14, 0, 1);
            g.stepDone(100 * (0.62 * acc + 0.38 * speed), T('ok_pressure', 'Bleeding slowed under pressure.'));
          }
          const hit = g.S.tools.hit;
          g.stageCursor(hit && g.S.tools.active && g.S.tools.active.group.visible ? 'hide' : '');
          if (this.finished) return;
          if (on) g.cursor(this.holdT / tune.pressureHold, G.b > tune.pressureTarget ? T('b3_cur_pressing', 'Pressing… bleeding slows') : T('b3_cur_hold', 'Hold it'), 'teal');
          else if (g.lmb) g.cursor(0, T('b3_cur_off', 'Off the wound'), 'red');
          else g.cursor(null, g.padOn() ? T('b3_cur_press', 'Hold LMB') : '', '');
        },
        exit() {
          g.covered = false;
          const next = g.steps[g.stepIdx + 1];
          if (next === 'wrap' && g.limb) g.leavePad(); else g.pad.hide();
        },
        panel() {
          const hold = clamp(this.holdT / tune.pressureHold, 0, 1), on = this.on();
          g.app.pp.set({
            stats: g.app.bleedStats([{ id: 'hold', label: T('st_hold', 'Held'), value: Math.min(this.holdT, tune.pressureHold).toFixed(1), unit: 's' }]),
            wide: {
              label: T('b3_w_pressure', 'Pressure'), value: String(Math.round(hold * 100)), unit: '%', tone: on ? '' : 'red',
              meter: { value: hold, tone: on ? '' : 'red' },
              caption: on ? (G.b > tune.pressureTarget ? T('b3_cap_slowing', 'Bleeding %s% · keep pressing', Math.round(G.b * 100)) : T('cap_hold', 'Keep it there…')) : (g.lmb ? T('off_wound', 'Off wound') : T('cap_release', 'Not pressing: bleeding')),
              captionTone: on ? 'teal' : 'red',
            },
          });
        },
      };
    }
    // is the pad (tool) over the wound?
    padOn() {
      const hit = this.S.tools.hit;
      if (!hit || this.toolName !== 'press' || !this.S.tools.active || !this.S.tools.active.group.visible) return false;
      return this.woundDist(this.aimUv(hit)) <= this.padReach();
    }
    // the pad follows the hand (smoothed like the tool), moulding to the skin as it is pressed
    carryPad(dt, ps) {
      const S = this.S, hit = S.tools.hit, t = this.tools.press;
      if (!hit || !S.tools.active || !S.tools.active.group.visible || this.toolName !== 'press') { this.pad.mesh.visible = false; ps.ok = false; return; }
      const k = ps.ok ? 1 - Math.exp(-dt * 30) : 1;
      ps.s = lerp(ps.s, hit.s, k); ps.t = lerp(ps.t, hit.t, k); ps.ok = true;
      this.pad.mode = 'tool';
      this.pad.place(ps.s, ps.t, t.press, 0.0122 * (1 - t.press));
    }
    // leave the pad on the wound (it goes under the bandage)
    leavePad() {
      const p = this.pad;
      p.mode = 'placed';
      p.place(this.wST[0], this.wST[1], 1, 0);
    }

    /* ═════════════════════════════ 2. PACK THE WOUND ═════════════════════════════ */
    phPack() {
      const g = this, G = this.G, tune = this.tune;
      const kit = this.packKit();
      kit.show(true);
      kit.insertAt(this.nearestWoundST(this.wUv));
      this.pad.hide();
      this.useTool('point');
      this.ring.set(this.wST, this.packReach(), 0xe5484d);
      this.frameStep('pack');
      const ps = { s: this.wST[0], t: this.wST[1], ok: false };
      const ph = {
        phase: 'feed', packed: kit.packed || 0, accs: [], waste: 0, push: null, holdT: 0, needRelease: false,
        hints: [{ keys: [T('k_lmb', 'Hold LMB')], label: T('b3_h_push', 'push gauze in') }],
        panelInit() {
          return {
            title: T('ph_pack', 'Pack the wound'),
            text: T('b3_pack_t', 'Push the gauze into the wound with your finger: **hold {LMB}** on the wound until the ring fills, **let go**, and push again. Fill it right up to the skin.'),
          };
        },
        down() {
          if (this.phase !== 'feed') { if (!g.padOn()) g.flashOnce('warn', T('b3_off_wound', 'Put the pad on the wound itself, inside the red ring.'), 1800); return; }
          const hit = g.S.tools.hit;
          if (!hit) { g.flashOnce('warn', T('b3_no_skin', 'Point at the wound first.'), 1500); return; }
          const d = g.woundDist(g.aimUv(hit)), lim = g.packReach();
          if (d > lim) { g.flashOnce('warn', T('b3_pack_off', 'Push the gauze into the wound itself, inside the red ring.'), 1800); return; }
          this.push = { t: 0, acc: clamp(1 - d / lim, 0, 1), done: false };
          kit.insertAt(g.nearestWoundST(hit.uv));
          g.S.tools.press(true);
          NZA.audio.click(480);
        },
        up() {
          if (this.push && !this.push.done && this.push.t > 0.05) g.flashOnce('warn', T('b3_push_short', 'Hold until the ring fills, then let go.'), 1600);
          this.push = null;
          this.needRelease = false;
        },
        tick(dt) {
          const S = g.S;
          if (this.phase === 'feed') {
            G.b = Math.min(G.maxB, G.b + 0.05 * dt); G.cover = false;
            const p = this.push;
            g.covered = !!(p && g.lmb);
            if (p && g.lmb) {
              S.tools.press(true);
              const hit = S.tools.hit;
              if (!p.done && (!hit || g.woundDist(g.aimUv(hit)) > g.packReach() * 1.4)) {
                this.push = null; this.waste += 1; S.tools.press(false);
                NZA.audio.fail();
                g.app.pp.flash('bad', T('b3_push_slip', 'Your finger slipped out of the wound: that gauze is wasted.'), 1800);
              } else if (!p.done) {
                const prev = p.t;
                p.t = Math.min(PUSH_T, p.t + dt);
                kit.feed((p.t - prev) / PUSH_T * 0.045);
                if (p.t >= PUSH_T) { p.done = true; this.fold(p); }
              }
            } else if (!g.lmb) S.tools.press(false);
            const pr = this.push;
            g.stageCursor(S.tools.hit && S.tools.active && S.tools.active.group.visible ? 'hide' : '');
            if (pr && g.lmb && !pr.done) g.cursor(pr.t / PUSH_T, T('b3_cur_push', 'Pushing in…'), 'teal');
            else if (this.needRelease && g.lmb) g.cursor(1, T('b3_cur_release', 'Let go'), 'teal');
            else g.cursor(null, S.tools.hit && g.woundDist(g.aimUv(S.tools.hit)) <= g.packReach() ? T('b3_cur_push_hint', 'Hold LMB: push') : '', '');
          } else {
            // hold pressure on the packing (as the 2D game: below 16 % for 1.6 s)
            const on = g.lmb && g.padOn();
            S.tools.press(g.lmb);
            if (on) G.b = Math.max(0.04, G.b - 0.32 * dt); else G.b = Math.min(0.5, G.b + 0.06 * dt);
            g.covered = on;
            if (on && G.b <= 0.16) this.holdT += dt; else this.holdT = Math.max(0, this.holdT - dt);
            g.carryPad(dt, ps);
            if (on) g.pad.stain(dt, 0.05 + 0.15 * G.b);
            if (this.holdT >= 1.6 && !this.finished) {
              const acc = this.accs.length ? this.accs.reduce((s, x) => s + x, 0) / this.accs.length : 0.5;
              const total = g.t - this.t0;
              const sc = 100 * (0.7 * (0.35 + 0.65 * acc) + 0.3 * clamp(1 - (total - 9) / 20, 0, 1)) - this.waste * 9;
              g.stepDone(sc, T('ok_pack', 'Packing holds.'));
            }
            g.stageCursor(S.tools.hit && S.tools.active && S.tools.active.group.visible ? 'hide' : '');
            if (this.finished) return;
            if (on) g.cursor(this.holdT / 1.6, G.b > 0.16 ? T('b3_cur_pressing', 'Pressing… bleeding slows') : T('b3_cur_hold', 'Hold it'), 'teal');
            else if (g.lmb) g.cursor(0, T('b3_cur_off', 'Off the wound'), 'red');
            else g.cursor(null, g.padOn() ? T('b3_cur_press', 'Hold LMB') : '', '');
          }
        },
        fold(p) {
          const gain = (0.5 + 0.5 * p.acc) / (tune.packStrips || 4);
          this.packed = Math.min(1, this.packed + gain);
          this.accs.push(p.acc);
          G.strips.push({ a: Math.random() * TAU, r: 0.25 + Math.random() * 0.5, born: g.t });
          kit.setPacked(this.packed);
          G.b = Math.max(0.12, G.b - 0.14 * (0.5 + p.acc));
          NZA.audio.click(p.acc > 0.6 ? 760 : 600);
          this.needRelease = true;
          if (p.acc < 0.35) g.app.pp.flash('warn', T('pack_edge', 'Too close to the edge: push it into the deepest part.'), 1600);
          if (this.packed >= 1) {
            this.phase = 'hold';
            kit.show(false);
            kit.setPacked(1);
            g.useTool('press');
            g.ring.set(g.wST, Math.max(g.padReach(), g.wRad + 6 * MM), 0xe5484d);
            // the pad and hand need the wider pressure view (the hand stays a small part of it)
            g.frameStep('pressure');
            g.app.pp.set({
              title: T('ph_pack_hold', 'Hold pressure on the packing'), text: T('b3_pack_hold_t', 'Packed tight. Put a pad on it and **hold {LMB}** to press the packing down until the bleeding stops.'),
              hints: g.hintsFor([{ keys: [T('k_lmb', 'Hold LMB')], label: T('h_press', 'press') }]),
            });
            g.app.pp.flash('ok', T('ok_packed', 'Wound packed.'), 1500);
          }
        },
        exit() {
          g.covered = false;
          const next = g.steps[g.stepIdx + 1];
          if (next === 'wrap' && g.limb) g.leavePad(); else g.pad.hide();
        },
        panel() {
          const extra = this.phase === 'feed'
            ? [{ id: 'packed', label: T('st_packed', 'Packed'), value: String(Math.round(this.packed * 100)), unit: '%' }, { id: 'waste', label: T('st_waste', 'Wasted'), value: String(this.waste), tone: this.waste ? 'amber' : '' }]
            : [{ id: 'hold', label: T('st_hold', 'Held'), value: Math.min(this.holdT, 1.6).toFixed(1), unit: 's' }];
          g.app.pp.set({
            stats: g.app.bleedStats(extra),
            wide: this.phase === 'feed'
              ? { label: T('w_packed', 'Wound packed'), value: `${Math.round(this.packed * 100)}`, unit: '%', meter: { value: this.packed, segs: true }, caption: T('cap_pack', 'Every feed that lands deep fills it faster'), captionTone: 'teal' }
              : { label: T('w_bleed', 'Bleeding'), value: `${Math.round(G.b * 100)}`, unit: '%', meter: { value: G.b, zone: [0, 0.16], tone: G.b > 0.16 ? 'red' : '' }, caption: g.lmb ? T('cap_hold', 'Keep it there…') : T('cap_release', 'Not pressing: bleeding'), captionTone: g.lmb ? 'teal' : 'red' },
          });
        },
      };
      return ph;
    }

    /* ═════════════════════════════ 3a. WRAP THE LIMB ═════════════════════════════ */
    phWrap() {
      const g = this, G = this.G, tune = this.tune, KEY = this.KEY;
      const band = tune.tensionBand || [0.38, 0.72];
      const N = tune.wrapTurns || 4;
      if (this.pad.mode !== 'placed') this.leavePad();
      if (this.kit) { this.kit.show(false); }
      const bd = this.bandage();
      bd.show(true);
      bd.setPhi(0);
      this.useTool(null);
      this.ring.hide();
      this.covered = true;   // the pad lies on the wound: it soaks, the turns show the seep
      this.frameStep('wrap');
      const PASS = WRAP_A0 - WRAP_AFAR;
      const ph = {
        phase: 'wrap', turns: [], turn: 0, phi: 0, target: 0, evt: [], grab: false, omega: 0, tension: 0, samples: [], pass: null, seep: 0.18,
        hints: [{ keys: [T('k_drag', 'Drag')], label: T('b3_h_wrap', 'roll it over the limb') }, { keys: [keyLabel(KEY.lock)], label: T('h_secure', 'secure the end') }],
        panelInit() {
          return {
            title: T('ph_wrap', 'Wrap the limb'),
            text: T('b3_wrap_t', '**Drag the roll up** over the limb, from your side to the far side: it goes round underneath by itself. Keep a steady pace for even tension. %s turns, each half over the last.', N),
          };
        },
        key(e) {
          if ((e.code === KEY.lock || e.code === KEY.confirm) && this.phase === 'secure') { this.secure(); return true; }
          return false;
        },
        // where the cursor wants the roll: only forward, within this turn's visible pass
        aim() {
          const start = this.turn * TAU;
          return clamp(start + (WRAP_A0 - bd.angleAtPointer()), start, start + PASS);
        },
        // pointer events drive the roll's target and the drag speed (real time between events), so a
        // drag that starts and ends between two hitching frames still counts in full
        pointer() {
          if (this.phase !== 'wrap' || !this.grab || this.pass) return;
          // tension = how fast the hand drags up over the limb (passes per second on screen): a steady
          // drag of ≈ 0.6–1.2 s per pass is even, faster pulls it tight, slower leaves it loose
          const t = performance.now(), py = g.S.pointer.y, tg = this.aim();
          const adv = tg > this.target + 1e-4;
          if (adv) this.target = tg;
          this.evt.push([t, py, this.target]);
          while (this.evt.length > 2 && t - this.evt[0][0] > 220) this.evt.shift();
          const e0 = this.evt[0], dts = (t - e0[0]) / 1000;
          if (dts > 0.04 && this.target > e0[2] + 1e-4) {
            const v = (e0[1] - py) / (bd.span || 0.3) / dts;
            this.omega = Math.max(0, v) * 2.5;
            if (v > 0.05) { this.tension = clamp(v * WRAP_TREF, 0, 1); this.samples.push(this.tension); }
          }
        },
        down() {
          if (this.phase === 'wrap') {
            if (this.pass) return;
            this.grab = true;
            this.target = Math.max(this.target, this.aim());   // a press ahead of the roll: it rolls there (not timed)
            this.evt = [[performance.now(), g.S.pointer.y, this.target]];
            return;
          }
          if (this.phase === 'secure') {
            const p = g.S.project(this.clipAt.p), dx = (p.x - g.S.pointer.x) * window.innerWidth, dy = (p.y - g.S.pointer.y) * window.innerHeight;
            if (Math.hypot(dx, dy) < Math.max(90, window.innerHeight * 0.09)) this.secure();
            else g.flashOnce('warn', T('b3_clip_here', 'Click the clip at the end of the bandage (or press {%s}).', keyLabel(KEY.lock)), 1800);
          }
        },
        up() { if (this.grab) this.pointer(); this.grab = false; this.evt = []; },
        tick(dt) {
          const S = g.S;
          if (this.phase === 'secure') {
            const p = S.project(this.clipAt.p), near = Math.hypot((p.x - S.pointer.x) * window.innerWidth, (p.y - S.pointer.y) * window.innerHeight) < Math.max(90, window.innerHeight * 0.09);
            g.stageCursor(near ? 'point' : '');
            g.cursor(null, near ? T('lbl_clip', 'Clip it') : '', 'teal');
            this.seepTick(dt);
            return;
          }
          if (this.phase !== 'wrap') return;
          if (this.pass) {
            const ps = this.pass;
            ps.t += dt;
            const f = clamp(ps.t / ps.T, 0, 1), e = f * f * (3 - 2 * f);
            this.phi = lerp(ps.from, ps.to, e);
            bd.setPhi(this.phi);
            if (f >= 1) {
              this.pass = null;
              this.turn += 1;
              this.target = this.phi;
              if (this.turns.length >= N) this.toSecure();
            }
            this.seepTick(dt);
            g.cursor(null, '', '');
            return;
          }
          const start = this.turn * TAU;
          const held = this.grab && g.lmb;
          if (held) this.pointer();
          // the roll catches up with the target (also after the release: it goes where it was dragged)
          const prev = this.phi;
          this.phi = Math.min(start + PASS, this.phi + Math.max(0, Math.min(this.target - this.phi, WRAP_CATCH * dt)));
          if (!held) this.omega *= Math.exp(-dt * 5);
          if (this.phi !== prev) bd.setPhi(this.phi, 1 - 0.1 * (this.tension - 0.5));
          this.seepTick(dt);
          if (this.phi - start >= PASS - 1e-4) this.endTurn();
          g.stageCursor(held ? 'grabbing' : 'grab');
          const tn = this.tension, show = held && this.omega > 0.4;
          if (show) g.cursor(null, tn > band[1] ? T('b3_cur_tight', 'Too tight: slower') : tn < band[0] ? T('b3_cur_loose', 'Too loose: faster') : T('even', 'Even'), tn > band[1] ? 'red' : tn < band[0] ? 'amber' : 'teal');
          else g.cursor(null, held ? '' : T('b3_cur_drag', 'Drag up over the limb'), '');
        },
        seepTick(dt) {
          this.seep = Math.min(0.85, this.seep + dt * (0.01 + 0.05 * G.b));
          this.tintT = (this.tintT || 0) - dt;
          if (this.tintT <= 0) { this.tintT = 0.3; bd.tint(this.seep); }
        },
        endTurn() {
          const s = this.samples; this.samples = [];
          const mean = s.length ? s.reduce((x, y) => x + y, 0) / s.length : 0.5;
          const inBand = s.length ? s.filter(x => x >= band[0] && x <= band[1]).length / s.length : 0.5;
          const kind = mean > band[1] ? 'tight' : mean < band[0] ? 'loose' : 'even';
          const q = clamp(inBand * 0.75 + (kind === 'even' ? 0.25 : 0.05), 0, 1);
          this.turns.push({ q, kind });
          G.b = Math.max(0.06, G.b * (kind === 'loose' ? 0.86 : 0.7));
          g.covered = true;
          NZA.audio.click(kind === 'even' ? 700 : 480);
          if (kind === 'tight') g.app.pp.flash('warn', T('wrap_tight', 'Too tight: you are cutting off the circulation. Slow down.'), 1700);
          else if (kind === 'loose') g.app.pp.flash('warn', T('wrap_loose', 'Too loose: it will slip. A little faster and firmer.'), 1700);
          this.grab = false;
          this.pass = { from: this.phi, to: (this.turn + 1) * TAU, t: 0, T: 0.5 };
        },
        toSecure() {
          this.phase = 'secure';
          this.phi = N * TAU + WRAP_END;
          bd.setPhi(this.phi);
          bd.roll.visible = false;
          this.clipAt = bd.endFrame(this.phi - 0.12);
          g.S.markers.set('clip', { uv: g.S.stToUv(this.clipAt.s, this.clipAt.a * bd.R), kind: 'pin', size: 0.016, color: 0x0fd4c4, pulse: true });
          bd.placeClip(this.clipAt, 0.012);
          g.app.pp.set({ title: T('ph_secure', 'Secure the end'), text: T('b3_secure_t', 'Fix the end with the clip: **click the clip** or press {%s}.', keyLabel(KEY.lock)) });
        },
        secure() {
          if (this.finished || this.phase !== 'secure') return;
          this.phase = 'done';
          bd.placeClip(this.clipAt, 0.0012);   // on the top layer (the end lies a layer above f.p)
          g.S.markers.remove('clip');
          NZA.audio.click(900);
          const q = this.turns.length ? this.turns.reduce((s, t) => s + t.q, 0) / this.turns.length : 0.5;
          const tight = this.turns.filter(t => t.kind === 'tight').length;
          G.cover = true;
          g.stageCursor('');
          g.stepDone(100 * q - tight * 6, T('ok_wrap', 'Bandage secured. Check the fingers / toes stay pink.'));
        },
        exit() {},
        panel() {
          const tn = this.tension, active = this.omega > 0.4;
          const label = !active ? '--' : tn > band[1] ? T('tight', 'Tight') : tn < band[0] ? T('loose', 'Loose') : T('even', 'Even');
          g.app.pp.set({
            stats: g.app.bleedStats([{ id: 'turns', label: T('st_turns', 'Turns'), value: `${this.turns.length}/${N}` }]),
            wide: this.phase === 'wrap'
              ? { label: T('w_tension', 'Tension'), value: label, tone: active && tn > band[1] ? 'red' : '', meter: { value: tn, zone: band, mark: tn, noFill: true }, caption: T('cap_wrap', 'Each turn overlaps the last by half'), captionTone: '' }
              : { label: T('st_turns', 'Turns'), value: `${this.turns.length}/${N}`, meter: { value: 1, segs: true }, caption: T('lbl_clip', 'Clip it'), captionTone: 'teal' },
          });
        },
      };
      return ph;
    }

    /* ═════════════════════════════ 3b. PRESSURE DRESSING ═════════════════════════════ */
    dressing() {
      if (this.dress) return this.dress;
      const S = this.S;
      const pw = clamp(Math.max(0.075, this.wLen + 0.026), 0.075, 0.12), ph = clamp(Math.max(0.06, this.wRad * 2 + 0.03), 0.06, 0.09);
      const size = [pw + 0.05, ph + 0.044];
      const ang = this.line ? this.w.p.angle || 0 : 0.1;
      // waits beside the wound (screen right, a little toward the viewer), inside the patch
      const sw = S.patch.W, sh = S.patch.H;
      const hs = clamp(this.wST[0] + Math.max(this.wRad, pw / 2) + size[0] * 0.5 + 0.03, -sw / 2 + size[0] * 0.6, sw / 2 - size[0] * 0.6);
      const ht = clamp(this.wST[1] + 0.03, -sh / 2 + size[1] * 0.6, sh / 2 - size[1] * 0.6);
      const home = S.stToUv(hs, ht);
      const D = S.dressing.create({ size, pad: [pw, ph], uv: home, angle: ang + 0.15 });
      this.dress = { D, home, size, pad: [pw, ph] };
      return this.dress;
    }
    // a pressure dressing presses the wound edges together: ease the open wound shut under it, so the
    // rubbed-down cloth bridges it (in an open groove the cloth sinks in and the rims poke through)
    easeWound() {
      const ease = w => {
        if (!w || !w.p) return;
        if (w.code === 1) w.setClosure(() => 0.92);
        w.set({ depth: Math.min(w.p.depth || 0, 0.0016), open: Math.min(w.p.open !== undefined ? w.p.open : 1, 0.35), rim: Math.min(w.p.rim !== undefined ? w.p.rim : 1, 0.25) });
      };
      ease(this.w);
      (this.extra || []).forEach(ease);
    }
    // fraction of the wound points under the dressing's pad, measured at skin level (the engine's
    // D.covers() measures from the wound floor, which in a deep open wound is too far below the pad)
    padCover() {
      const dr = this.dress, S = this.S, g = dr.D.mesh.geometry, pos = g.attributes.position.array, uv = g.attributes.uv.array;
      const hu = dr.pad[0] / dr.size[0] / 2, hv = dr.pad[1] / dr.size[1] / 2, P = new THREE.Vector3(), N = new THREE.Vector3();
      let n = 0;
      for (const w of this.wPts) {
        const st = S.uvToST(w);
        S._surf(st[0], st[1], P, N);
        let best = Infinity, bi = -1;
        for (let k = 0; k < uv.length / 2; k++) {
          const dx = pos[k * 3] - P.x, dy = pos[k * 3 + 1] - P.y, dz = pos[k * 3 + 2] - P.z, d = dx * dx + dy * dy + dz * dz;
          if (d < best) { best = d; bi = k; }
        }
        if (bi >= 0 && best < 0.007 * 0.007 && Math.abs(uv[bi * 2] - 0.5) < hu && Math.abs(uv[bi * 2 + 1] - 0.5) < hv) n++;
      }
      return this.wPts.length ? n / this.wPts.length : 0;
    }
    // a click on the body of the dressing grabs the nearest point of its edge
    edgeHit(D, hit) {
      const pos = D.mesh.geometry.attributes.position.array, uv = D.mesh.geometry.attributes.uv.array;
      let best = Infinity, bi = -1;
      for (let k = 0; k < uv.length / 2; k++) {
        const u = uv[k * 2], v = uv[k * 2 + 1];
        if (u > 0.001 && u < 0.999 && v > 0.001 && v < 0.999) continue;
        const dx = pos[k * 3] - hit.point.x, dy = pos[k * 3 + 1] - hit.point.y, dz = pos[k * 3 + 2] - hit.point.z, d = dx * dx + dy * dy + dz * dz;
        if (d < best) { best = d; bi = k; }
      }
      if (bi < 0) return null;
      return { point: new THREE.Vector3(pos[bi * 3], pos[bi * 3 + 1], pos[bi * 3 + 2]), normal: hit.normal, uv: hit.uv };
    }
    phDressing() {
      const g = this, G = this.G;
      this.pad.hide();
      if (this.kit) this.kit.show(false);
      const dr = this.dressing(), D = dr.D;
      this.useTool(null);
      this.ring.set(this.wST, Math.max(dr.pad[0], dr.pad[1]) * 0.5, 0xe5484d);
      this.frameStep('dressing');
      const ph = {
        phase: 'place', carrying: false, cov: 0, settle: 0, seep: 0.1, letGo: 0,
        hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_place', 'place') }, { keys: [T('k_lmb', 'Hold LMB')], label: T('b3_h_rub', 'rub it down') }],
        panelInit() {
          return {
            title: T('ph_dressing', 'Apply the pressure dressing'),
            text: T('b3_dress_t', '**Pick the dressing up** (click and hold it), carry the pad over the wound so it covers it completely, and **let go**.'),
          };
        },
        down() {
          const S = g.S;
          if (this.phase === 'place') {
            if (this.settle > 0 || this.letGo > 0) return;
            const hit = S.raycast(S.pointer);
            const p = hit && D.pick(hit);
            if (!p) { g.flashOnce('warn', T('b3_dress_pick', 'Click on the dressing to pick it up.'), 1600); return; }
            const h2 = p === 'edge' ? hit : g.edgeHit(D, hit);
            // carried by its edge, but the spot under the cursor stays under the cursor
            const es = S._toSurf(h2 ? h2.point : hit.point);
            this.off = [es.s - hit.s, es.t - hit.t];
            if (h2 && D.grab(h2)) { this.carrying = true; NZA.audio.click(520); g.ring.set(g.wST, Math.max(dr.pad[0], dr.pad[1]) * 0.5, 0x0fd4c4); }
          } else if (this.phase === 'rub') S.tools.press(true);
        },
        // the dressing follows the pointer events (a carry that happens between two hitching frames
        // still lands where it was dropped)
        pointer() { if (this.carrying) { const hit = g.S.raycast(g.S.pointer); if (hit) this.moveTo(hit); } },
        moveTo(hit) { const o = this.off || [0, 0]; D.move(g.S.surfaceAt(g.S.stToUv(hit.s + o[0], hit.t + o[1]))); },
        up() {
          if (this.carrying) { this.pointer(); this.carrying = false; this.letGo = 0.001; }
          g.S.tools.press(false);
        },
        tick(dt) {
          const S = g.S;
          if (this.phase === 'place') {
            G.b = Math.min(G.maxB, G.b + 0.04 * dt);
            if (this.carrying && g.lmb) { const hit = S.raycast(S.pointer); if (hit) this.moveTo(hit); }
            // let go once the cloth has caught up with the hand (a few cloth steps)
            if (this.letGo > 0) { this.letGo += dt; if (this.letGo > 0.28) { this.letGo = 0; D.release(); this.settle = 0.001; } }
            if (this.settle > 0) { this.settle += dt; if (D.state === 'placed' || this.settle > 1.1) { this.settle = 0; this.check(); } }
            g.stageCursor(this.carrying || this.letGo ? 'grabbing' : 'grab');
            g.cursor(null, this.carrying ? T('cap_dress', 'Centre the pad on the wound') : '', 'teal');
            return;
          }
          if (this.phase !== 'rub') return;
          const hit = S.tools.hit;
          const rubbing = g.lmb && hit && D.pick(hit);
          S.tools.press(!!g.lmb);
          if (rubbing) { D.rub(hit, dt); G.b = Math.max(0.05, G.b - 0.12 * dt); }
          this.seep = Math.min(0.75, this.seep + dt * (0.008 + 0.05 * G.b));
          D.seep(this.seep, g.wUv);
          g.stageCursor(hit && S.tools.active && S.tools.active.group.visible ? 'hide' : '');
          if (D.stuck >= 0.9 && !this.finished) {
            const total = g.t - this.t0;
            g.stepDone(100 * (0.6 * this.cov + 0.4 * clamp(1 - (total - 6) / 16, 0, 1)), T('ok_dressing', 'Dressing sealed.'));
            return;
          }
          if (this.finished) return;
          g.cursor(D.stuck / 0.9, rubbing ? T('b3_cur_rub', 'Rubbing down…') : g.lmb ? T('b3_cur_rub_on', 'Rub over the dressing') : T('b3_cur_rub_hint', 'Hold LMB and rub'), rubbing ? 'teal' : '');
        },
        check() {
          const cov = g.padCover();
          const c = D.center(), cs = g.S._toSurf(c), dd = Math.hypot(cs.s - g.wST[0], cs.t - g.wST[1]);
          const centred = clamp(1 - dd / (Math.min(dr.pad[0], dr.pad[1]) * 0.55), 0, 1);
          if (cov < 0.6) { NZA.audio.fail(); g.app.pp.flash('bad', T('dress_miss', 'The pad is not over the wound. Try again.'), 1700); g.ring.set(g.wST, Math.max(dr.pad[0], dr.pad[1]) * 0.5, 0xe5484d); return; }
          this.cov = clamp(0.5 * cov + 0.5 * centred, 0, 1);
          this.phase = 'rub';
          G.cover = true; g.covered = true;
          g.easeWound();
          G.b = Math.max(0.1, G.b * (1 - 0.4 * this.cov));
          g.ring.hide();
          g.useTool('rub');
          g.S.controls.frame(g.wUv, g.viewFor('pressure'), { pitch: 1.12, instant: false });   // the pressure view: room for the rubbing hand
          NZA.audio.click(700);
          g.app.pp.set({ title: T('ph_seal', 'Seal the edges'), text: T('b3_seal_t', '**Hold {LMB} and rub** over the dressing, from the middle out to every edge, until it sticks all round.') });
        },
        exit() {},
        panel() {
          const st = D.stuck || 0;
          g.app.pp.set({
            stats: g.app.bleedStats([{ id: 'cover', label: T('st_cover', 'Cover'), value: String(Math.round(this.cov * 100)), unit: '%' }]),
            wide: this.phase === 'place'
              ? { label: T('w_bleed', 'Bleeding'), value: `${Math.round(G.b * 100)}`, unit: '%', meter: { value: G.b, tone: G.b > 0.4 ? 'red' : '' }, caption: T('cap_dress', 'Centre the pad on the wound'), captionTone: 'teal' }
              : { label: T('b3_w_sealed', 'Sealed'), value: String(Math.round(clamp(st / 0.9, 0, 1) * 100)), unit: '%', meter: { value: clamp(st / 0.9, 0, 1) }, caption: T('cap_seal', 'Seal all four edges'), captionTone: 'teal' },
          });
        },
      };
      return ph;
    }

    /* ─────────────── preview: open at a stage (index.html?app=treat&mode=bleed&stage=…) ─────────────── */
    jump(stage) {
      if (!this.ready) { this.pendingJump = stage; return; }
      const order = this.steps, q = new URLSearchParams(location.search), N = this.tune.wrapTurns || 4;
      const demo = { pressure: 91, pack: 84, wrap: 80, dressing: 82 };
      const packedKit = soak => { const kit = this.packKit(); kit.setPacked(1); kit.soak = soak; kit.show(false); kit.update(0.016, null); };
      const go = name => {
        const i = order.indexOf(name);
        if (i < 0) return false;
        for (let k = 0; k < i; k++) this.G.steps[order[k]] = demo[order[k]] || 80;
        if (this.ph && this.ph.exit) this.ph.exit();
        this.ph = null;
        if (order.indexOf('pack') > -1 && order.indexOf('pack') < i) packedKit(0.7);
        if (name !== 'pressure') this.G.b = 0.35;
        this.stepIdx = i - 1;
        this.nextStep();
        return true;
      };
      const st = String(stage || '').toLowerCase();
      if (st === 'pack') { go('pack'); return; }
      if (st === 'hold' || st === 'packhold') {
        if (go('pack')) { this.ph.packed = 0.999; this.ph.fold({ acc: 1 }); this.ph.needRelease = false; }
        return;
      }
      if (st === 'wrap' || st === 'secure') {
        if (!go('wrap') || !this.bd) { go('dressing'); return; }
        const ph = this.ph, n = st === 'secure' ? N : clamp(+(q.get('turns') || 0), 0, N);
        for (let k = 0; k < n; k++) { ph.turns.push({ q: 0.86, kind: 'even' }); ph.turn = k + 1; ph.phi = ph.target = (k + 1) * TAU; }
        if (n) { this.G.b = 0.2; this.covered = true; ph.seep = 0.45; this.bd.setPhi(ph.phi); this.bd.tint(ph.seep); }
        if (n >= N) ph.toSecure();
        else if (q.get('partial') !== null) { ph.phi += clamp(+q.get('partial'), 0, 1) * (WRAP_A0 - WRAP_AFAR); ph.target = ph.phi; this.bd.setPhi(ph.phi); }
        return;
      }
      if (st === 'dressing' || st === 'seal') {
        if (!go('dressing') && !go('wrap')) return;
        if (st === 'seal' && this.dress && this.ph && this.ph.check) this.placeDressing(true);
        return;
      }
      if (st === 'done' || st === 'result') {
        for (const s of order) this.G.steps[s] = demo[s] || 80;
        if (this.ph && this.ph.exit) this.ph.exit();
        this.ph = null;
        if (order.includes('pack')) packedKit(0.85);
        if (order.includes('wrap') && this.limb) {
          this.leavePad();
          const bd = this.bandage();
          bd.show(true); bd.setPhi(N * TAU + WRAP_END); bd.roll.visible = false; bd.tint(0.5);
          const f = bd.endFrame(bd.phi - 0.12);
          bd.placeClip(f, 0.0012);
          this.frameStep('wrap', true);
        } else if (order.includes('dressing') || order.includes('wrap')) {
          this.dressing();
          this.placeDressing(false);
          this.dress.D.seep(0.45, this.wUv);
        }
        this.G.b = 0.1; this.covered = true;
        this.stepIdx = order.length - 1;
        this.finish();
      }
    }
    // preview: carry the dressing's pad onto the wound by hand (simulated), let it settle, rub some
    placeDressing(check) {
      const S = this.S, dr = this.dress, D = dr.D;
      const homeST = S.uvToST(dr.home);
      const e = this.edgeHit(D, { point: S.surfaceAt(dr.home).point, normal: new THREE.Vector3(0, 1, 0), uv: dr.home });
      if (!e || !D.grab(e)) return;
      const es = S._toSurf(e.point);
      const target = S.surfaceAt(S.stToUv(es.s + this.wST[0] - homeST[0], es.t + this.wST[1] - homeST[1]));
      for (let k = 0; k < 45; k++) { D.move(target); D.step(1 / 30); }
      D.release();
      for (let k = 0; k < 50; k++) D.step(1 / 30);
      if (!check) { this.easeWound(); for (let k = 0; k < 60; k++) { const a = k * 0.7, r = (k % 6) * 0.008; D.rub(S.surfaceAt(S.stToUv(this.wST[0] + Math.cos(a) * r, this.wST[1] + Math.sin(a) * r * 0.8)), 0.08); } D.step(1 / 30); return; }
      this.ph.check();
      if (this.ph.phase === 'rub') for (let k = 0; k < 14; k++) { const a = k * 0.9, r = 0.004 + (k % 4) * 0.005; D.rub(S.surfaceAt(S.stToUv(this.wST[0] + Math.cos(a) * r, this.wST[1] + Math.sin(a) * r * 0.8)), 0.06); }
    }

    /* ─────────────── teardown ─────────────── */
    dispose() {
      if (!this.alive) return;
      this.alive = false;
      const app = this.app;
      window.removeEventListener('blur', this.onBlur);
      window.removeEventListener('resize', this.onResize);
      if (this.S) { try { this.S.dispose(); } catch (e) { console.error('[treat] dispose', e); } this.S = null; }
      this.bin.forEach(x => { try { x.dispose(); } catch (e) { /* gone */ } });
      this.bin.clear();
      [this.stage, this.curEl, this.loadEl].forEach(n => { if (n && n.parentNode) n.parentNode.removeChild(n); });
      app.full = false; app.opaque = false; delete app.camInput;
      app.el.classList.remove('nza-full');
      this.ph = null;
    }
  }
  window.TreatBleed3D = {
    ok() {
      if (!window.NZA3D || !THREE) return false;
      if (!NZA.inGame && /[?&]no3d=1\b/.test(location.search)) return false;
      try { return !!NZA3D.supported(); } catch (e) { return false; }
    },
    start(app, data) { return new Game(app, data); },
  };
})();
